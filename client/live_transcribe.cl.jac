"""Live microphone -> Deepgram streaming -> callbacks (PRD §9, live-mic branch).

The browser holds the mic and talks to Deepgram's realtime WebSocket DIRECTLY --
audio never touches the Jac server. This module owns the three browser resources
(getUserMedia stream, MediaRecorder, WebSocket) as module-level `glob` state so
they survive re-renders, and exposes two entry points plus a callback bag the
LiveHandoff component wires its reactive state into:

    startLive(cbs)  -- mint a token, open the socket, start streaming mic audio
    stopLive()      -- stop the recorder, close the socket, release the mic

Callbacks (all optional, invoked with `.call(None, ...)` per jac-cl-js-interop):
    cbs["onInterim"](text)          -- a not-yet-final partial, for the live caret
    cbs["onFinal"](segment_dict)    -- a finalized diarized utterance
    cbs["onStatus"](status_str)     -- "connecting" | "listening" | "stopped"
    cbs["onError"](message)         -- fatal: no mic, no key, socket died

`onFinal` gets {"text","speaker","start"} -- the same shape contracts.Segment
carries -- and the component turns it into an Episode via IngestUtterance. This
file does no graph writes; it only produces transcript.

Docstrings sit BEFORE each `def` (Jac: a string inside a function body is a bare
expression needing `;`). jac check flags browser globals (WebSocket, navigator,
JSON...) as possibly-undefined -- correct at runtime; see jac-cl-js-interop.
"""

sv import from realtime { DeepgramToken }

# --- module state: one live session at a time --------------------------------
glob _ws: any = None;
glob _recorder: any = None;
glob _stream: any = None;
glob _cbs: dict = {};

# Full-session audio, accumulated for the batch re-transcription pass on stop
# (the hybrid path, PRD 7 override). The same MediaRecorder chunks that stream
# to Deepgram live are also kept here so "end handoff" can re-transcribe the
# WHOLE recording at higher (utterance-level) diarization quality.
glob _audio_chunks: list = [];
glob _audio_mime: str = "audio/webm";

# Authoritative finalized-utterance list. Held here (not in component state) so
# it is always current when a callback reads it -- a callback registered at
# start() closes over stale `has` state, but a module glob never goes stale
# (jac-cl-js-interop). The component mirrors this into state to render.
glob _segments: list = [];

# jac2js emits a literal "\n" as backslash-n in cl code -- build newlines from
# chr(10) (jac-cl-js-interop, string gotchas).
glob _NL: str = chr(10);

# Speaker ids Deepgram diarizes to (0,1,2...) mapped to display labels. Generic
# by default -- live mic has no way to know who is who. Provenance only needs a
# stable, non-integer author.
glob _SPEAKER_LABELS: dict = {0: "Speaker 1", 1: "Speaker 2", 2: "Speaker 3"};

# Drug names Deepgram mangles without a hint -- the provenance story dies if the
# graph ingests "seftriaxone". Keyterm prompting is nova-3 only (PRD §9.4).
glob _KEYTERMS: list = [
    "ceftriaxone", "levofloxacin", "cefepime", "vancomycin",
    "nitrofurantoin", "desaturation", "SpO2", "urine culture", "afebrile"
];


"""A fresh copy of every finalized utterance so far (new ref -> re-render)."""
def:pub getSegments() -> list {
    return _segments[:];
}

"""The full recording as base64 (no data: prefix) for the batch re-transcribe.

Empty string if nothing was captured. Concatenates the kept MediaRecorder
chunks into one Blob, reads its bytes, and base64s them by hand (btoa needs a
binary string). Opus is compressed, so a few-minute handoff stays small enough
that the per-byte loop is fine for the demo."""
async def:pub getAudioB64() -> str {
    if len(_audio_chunks) == 0 {
        return "";
    }
    blob = new(Blob, _audio_chunks, {"type": _audio_mime});   # jac:ignore[W2001]
    buf = await blob.arrayBuffer();
    bytes = new(Uint8Array, buf);                             # jac:ignore[W2001]
    binary: str = "";
    i = 0;
    n = bytes.length;
    while i < n {
        binary = binary + (String.fromCharCode(bytes[i]) as str);   # jac:ignore[W2001]
        i = i + 1;
    }
    return btoa(binary) as str;                               # jac:ignore[W2001]
}

"""The MIME type the recording was captured in (for the batch transcribe)."""
def:pub getAudioMime() -> str {
    return _audio_mime;
}

"""Reset the finalized-utterance buffer at the start of a new handoff."""
def:pub clearSegments() -> None {
    _segments = [];
}

"""The whole handoff as one string, for the post-hoc omission check."""
def:pub fullTranscript() -> str {
    parts = [];
    for s in _segments {
        parts.append(s["speaker"] + ": " + s["text"]);
    }
    return _NL.join(parts);
}

"""Invoke a stored callback if the component registered one."""
def _fire(name: str, arg: any) {
    cb = _cbs.get(name);
    if cb {
        cb.call(None, arg);   # jac:ignore[E1030]
    }
}

"""Map a Deepgram speaker integer to a stable display label."""
def _label_for(speaker: int) -> str {
    return _SPEAKER_LABELS.get(speaker, "Speaker " + str(speaker + 1));
}

"""Split one Deepgram alternative into contiguous per-speaker runs.

Diarization rides on `alt.words[]`, one `speaker` int per word. A single final
frame can span a speaker change (person A finishes, person B starts inside the
same result), so labeling the whole frame by `words[0]` collapses two people
into one -- that is why "it doesn't detect different speakers". Instead we walk
the words and cut a new segment every time the speaker id changes, so each run
carries exactly one speaker. `punctuated_word` (smart_format) keeps casing and
commas; fall back to the raw word. No words at all -> one speaker-0 segment."""
def _split_by_speaker(alt: any) -> list {
    words = alt.words;
    if not words or len(words) == 0 {
        return [{"speaker": 0, "text": alt.transcript, "start": 0.0}];
    }
    runs = [];
    cur_spk: int = words[0].speaker or 0;
    cur_start: float = words[0].start or 0.0;
    cur_words = [];
    for w in words {
        wspk: int = w.speaker or 0;
        if wspk != cur_spk and len(cur_words) > 0 {
            runs.append({"speaker": cur_spk, "text": " ".join(cur_words), "start": cur_start});
            cur_spk = wspk;
            cur_start = w.start or 0.0;
            cur_words = [];
        }
        cur_words.append(w.punctuated_word or w.word);
    }
    if len(cur_words) > 0 {
        runs.append({"speaker": cur_spk, "text": " ".join(cur_words), "start": cur_start});
    }
    return runs;
}

"""Deepgram realtime URL: nova-3, diarized, interim results on, drug keyterms."""
def _dg_url() -> str {
    url: str = "wss://api.deepgram.com/v1/listen?model=nova-3&diarize=true&interim_results=true&punctuate=true&smart_format=true";
    for term in _KEYTERMS {
        url = url + "&keyterm=" + encodeURIComponent(term);   # jac:ignore[W2001]
    }
    return url;
}

"""One MediaRecorder blob -> Deepgram (live) AND the batch buffer.

The chunk is kept for the whole-recording re-transcribe regardless of socket
state, then streamed to Deepgram only while the socket is open."""
def _on_chunk(e: any) {
    if e.data and e.data.size > 0 {
        _audio_chunks.append(e.data);
        if _ws and _ws.readyState == 1 {
            _ws.send(e.data);
        }
    }
}

"""Socket is open: pick a codec Deepgram accepts, start streaming mic audio.
A named def (not an inline lambda) because Jac lambda bodies are expressions --
statements like `if`/assignment must live in a def."""
def _start_recorder() {
    mime: str = "audio/webm;codecs=opus";
    if not MediaRecorder.isTypeSupported(mime) {   # jac:ignore[W2001]
        mime = "audio/webm";
    }
    _audio_mime = mime;
    rec = new(MediaRecorder, _stream, {"mimeType": mime});   # jac:ignore[W2001]
    _recorder = rec;
    chunk = _on_chunk;
    rec.ondataavailable = lambda (e: any) { chunk.call(None, e); };   # jac:ignore[E1030]
    rec.start(250);   # flush a chunk every 250ms -> near-real-time partials
    _fire("onStatus", "listening");
}

"""One Deepgram frame -> onInterim (partial) or onFinal (utterance)."""
def _on_message(event: any) {
    # First assignment BEFORE the try, or jac2js block-scopes `msg` to the try
    # body (a `let`) and every use below is a TDZ ReferenceError (jac-cl-js-interop).
    msg: any = None;
    try {
        msg = JSON.parse(event.data);   # jac:ignore[W2001]
    } except Exception as e {
        console.error("[live] bad frame", e);   # jac:ignore[W2001]
        return;
    }
    if msg.type != "Results" {
        return;   # Metadata / UtteranceEnd frames carry no transcript
    }
    alt = msg.channel.alternatives[0];
    text = alt.transcript;
    if not text or not text.strip() {
        return;   # Deepgram emits empty partials between utterances
    }

    # Debug: surface exactly what Deepgram returned, incl. the per-word speaker
    # ids that drive diarization. Filter DevTools console by "[deepgram]".
    kind = "final" if msg.is_final else "interim";
    spk_map = [];
    if alt.words {
        for w in alt.words {
            spk_map.append({"w": w.punctuated_word or w.word, "speaker": w.speaker});
        }
    }
    console.log("[deepgram]", kind, "| text:", text, "| speakers:", spk_map, "| raw:", msg);   # jac:ignore[W2001]

    if msg.is_final {
        # One final frame can hold more than one speaker -- split it so each
        # displayed line and each ingested Episode is a single speaker.
        for r in _split_by_speaker(alt) {
            seg = {
                "text": r["text"],
                "speaker": _label_for(r["speaker"]),
                "start": r["start"] or (msg.start or 0.0)
            };
            _segments = _segments + [seg];
            _fire("onFinal", seg);
        }
    } else {
        _fire("onInterim", text);
    }
}

"""Mint a token, open the mic + socket, begin streaming. Any failure lands on
cbs["onError"] and leaves no half-open resources."""
async def:pub startLive(cbs: dict) -> None {
    _cbs = cbs;
    _segments = [];
    _audio_chunks = [];
    _fire("onStatus", "connecting");

    # 1. Credential to open Deepgram's socket with (server seam).
    tok = root spawn DeepgramToken();
    info = tok.reports[0];
    if not info["ok"] or not info["token"] {
        _fire("onError", "No Deepgram key configured -- use the scripted handoff.");
        return;
    }

    # 2. Microphone. Rejects if the user denies permission or there's no device.
    try {
        _stream = await navigator.mediaDevices.getUserMedia({"audio": True});   # jac:ignore[W2001]
    } except Exception as e {
        _fire("onError", "Microphone unavailable: " + str(e));
        return;
    }

    # 3. Socket. Deepgram takes the credential as a WS subprotocol, never a header.
    ws = new(WebSocket, _dg_url(), [info["scheme"], info["token"]]);   # jac:ignore[W2001]
    _ws = ws;

    # Thin trampoline lambdas only -- all real logic lives in named defs above.
    opener = _start_recorder;
    handler = _on_message;
    ws.onopen = lambda { opener.call(None); };                    # jac:ignore[E1030]
    ws.onmessage = lambda (e: any) { handler.call(None, e); };    # jac:ignore[E1030]
    ws.onerror = lambda (e: any) { _fire("onError", "Transcription socket error."); };
    ws.onclose = lambda { _fire("onStatus", "stopped"); };
}

"""Stop the recorder, tell Deepgram we're done, close the socket, free the mic."""
def:pub stopLive() {
    if _recorder and _recorder.state != "inactive" {
        _recorder.stop();
    }
    if _stream {
        for t in _stream.getTracks() {
            t.stop();
        }
    }
    if _ws {
        if _ws.readyState == 1 {
            _ws.send(JSON.stringify({"type": "CloseStream"}));   # jac:ignore[W2001]
            _ws.close();
        }
    }
    _ws = None;
    _recorder = None;
    _stream = None;
}
