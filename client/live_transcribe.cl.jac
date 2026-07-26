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
def getSegments() -> list {
    return _segments[:];
}

"""Reset the finalized-utterance buffer at the start of a new handoff."""
def clearSegments() -> None {
    _segments = [];
}

"""The whole handoff as one string, for the post-hoc omission check."""
def fullTranscript() -> str {
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

"""Deepgram realtime URL: nova-3, diarized, interim results on, drug keyterms."""
def _dg_url() -> str {
    url: str = "wss://api.deepgram.com/v1/listen?model=nova-3&diarize=true&interim_results=true&punctuate=true&smart_format=true";
    for term in _KEYTERMS {
        url = url + "&keyterm=" + encodeURIComponent(term);   # jac:ignore[W2001]
    }
    return url;
}

"""One MediaRecorder blob -> Deepgram, if the socket is open."""
def _on_chunk(e: any) {
    if _ws and _ws.readyState == 1 and e.data and e.data.size > 0 {
        _ws.send(e.data);
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
    rec = new(MediaRecorder, _stream, {"mimeType": mime});   # jac:ignore[W2001]
    _recorder = rec;
    chunk = _on_chunk;
    rec.ondataavailable = lambda (e: any) { chunk.call(None, e); };   # jac:ignore[E1030]
    rec.start(250);   # flush a chunk every 250ms -> near-real-time partials
    _fire("onStatus", "listening");
}

"""One Deepgram frame -> onInterim (partial) or onFinal (utterance)."""
def _on_message(event: any) {
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

    # Diarization rides on the words; take the utterance's first speaker.
    speaker: int = 0;
    if alt.words and len(alt.words) > 0 {
        speaker = alt.words[0].speaker or 0;
    }

    if msg.is_final {
        seg = {
            "text": text,
            "speaker": _label_for(speaker),
            "start": msg.start or 0.0
        };
        _segments = _segments + [seg];
        _fire("onFinal", seg);
    } else {
        _fire("onInterim", text);
    }
}

"""Mint a token, open the mic + socket, begin streaming. Any failure lands on
cbs["onError"] and leaves no half-open resources."""
async def startLive(cbs: dict) -> None {
    _cbs = cbs;
    _segments = [];
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
def stopLive() {
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
