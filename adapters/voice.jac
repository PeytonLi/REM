"""Voice adapters -- REAL implementations (tasks B3 + B6).

`transcribe()`  -- Deepgram Nova-3 batch, diarization + keyterm prompting (PRD 9.4).
`place_call()`  -- ElevenLabs Agents outbound over the SignalWire SIP trunk (PRD 8).

PRD 10.5 -- the call layer is swappable, not load-bearing. BOTH functions keep
the exact signatures Person A codes against, and BOTH degrade instead of
raising: no credentials, no network, no audio file, or a provider error and you
get the scripted/on-screen path back. `Escalate` never knows the difference,
and the self-check at the bottom runs offline.

Configuration lives in `.env` (see `.env.example`). The ElevenLabs agent must
already have the SignalWire trunk registered as a GENERIC SIP trunk (SIP URI +
digest auth) -- ElevenLabs provisions no numbers itself on any tier, and the
Twilio-specific "native integration" flow is the wrong one here.
"""

import os;
import requests;
import from contracts { Segment, CallResult }
import from jaclang.byllm.lib { Model }

# Jac has no module-level try/except, so the optional-dotenv guard lives in a
# function called from `with entry` below.
def _load_env {
    try {
        import from dotenv { load_dotenv }
        load_dotenv();
    } except ImportError as e {
        # python-dotenv is optional; real env vars still work without it.
        print(f"[voice] dotenv not installed ({e}), reading os.environ directly");
    }
}

with entry {
    _load_env();
}

# Same cheap/budget model omission.jac uses -- this is a single boolean, not a
# composition. `any` (not `Model`) so the self-check can swap in a MockLLM.
glob cheap: any = Model(model_name="deepseek/deepseek-chat");


# ============================================================================
# B3 -- transcription (Deepgram Nova-3 batch)
# ============================================================================

glob DEEPGRAM_URL: str = "https://api.deepgram.com/v1/listen";

# Deepgram mangles drug names, and the whole provenance story dies if the graph
# ingests "seftriaxone". Keyterm prompting is nova-3 only; max 500 tokens total.
glob KEYTERMS: list[str] = [
    "ceftriaxone", "levofloxacin", "levo", "cefepime", "vancomycin",
    "nitrofurantoin", "piperacillin", "tazobactam", "MAR", "afebrile",
    "desaturation", "SpO2", "urine culture", "Alvarez", "Ortiz", "Patel"
];

# Deepgram diarizes to integers, assigned in order of first speech. The graph
# needs a stable human author on every episode, so map once, here. The outgoing
# nurse opens the handoff, so she is speaker 0 -- verify against the recording
# before demo day (see audio/README.md).
glob SPEAKERS: dict[int, str] = {0: "RN Maya Ortiz", 1: "RN Dev Patel"};

glob AUDIO_MIME: dict[str, str] = {
    ".wav": "audio/wav", ".mp3": "audio/mpeg", ".m4a": "audio/mp4",
    ".flac": "audio/flac", ".ogg": "audio/ogg", ".webm": "audio/webm"
};


"""Diarized batch transcription. Degrades to the scripted handoff if the key or
the audio file is missing, or if Deepgram errors -- the demo still runs."""
def transcribe(path: str) -> list[Segment] {
    key = os.getenv("DEEPGRAM_API_KEY");
    if not key {
        print("[voice] no DEEPGRAM_API_KEY -- using scripted handoff");
        return scripted_segments();
    }
    if not os.path.exists(path) {
        print(f"[voice] no audio at {path} -- using scripted handoff");
        return scripted_segments();
    }

    # diarize is non-negotiable (PRD 9.2): an unattributed transcript has no
    # author, and provenance needs one. utterances turns the word-level speaker
    # tags into speaker-contiguous segments, which is exactly Segment's shape.
    params = [
        ("model", "nova-3"), ("diarize", "true"), ("utterances", "true"),
        ("smart_format", "true"), ("punctuate", "true")
    ];
    for term in KEYTERMS {
        params.append(("keyterm", term));
    }

    ext = os.path.splitext(path)[1].lower();
    with open(path, "rb") as f {
        audio = f.read();
    }

    try {
        resp = requests.post(
            DEEPGRAM_URL,
            params=params,
            data=audio,
            headers={
                "Authorization": f"Token {key}",
                "Content-Type": AUDIO_MIME.get(ext, "application/octet-stream")
            },
            timeout=180
        );
        resp.raise_for_status();
        utterances = resp.json()["results"]["utterances"];
    } except Exception as e {
        print(f"[voice] Deepgram failed ({e}) -- using scripted handoff");
        return scripted_segments();
    }

    segments: list[Segment] = [];
    for u in utterances {
        spk = u.get("speaker", 0);
        segments.append(Segment(
            text=u["transcript"],
            speaker=SPEAKERS.get(spk, f"Speaker {spk}"),
            start=float(u["start"])
        ));
    }
    if not segments {
        print("[voice] Deepgram returned no utterances -- using scripted handoff");
        return scripted_segments();
    }
    print(f"[voice] transcribed {path}: {len(segments)} segments, "
          f"{len({s.speaker for s in segments})} speakers");
    return segments;
}


"""The 45s handoff script, verbatim -- the degraded path for `transcribe`, and
the source of truth for the recording (audio/handoff.script.md).

It deliberately carries one causal explanation that exists nowhere in the
written record (the rash), and deliberately omits two things the graph
requires (the overnight desaturation pattern, the room check after the fall).
That omission is what feeds the panel in omission.jac -- do not "fix" it."""
def scripted_segments() -> list[Segment] {
    return [
        Segment(
            text="Okay, room 3B, Ruth Alvarez, eighty-two, day five.",
            speaker="RN Maya Ortiz",
            start=0.0
        ),
        Segment(
            text="She's still on the levofloxacin. We swapped her off the "
                 "ceftriaxone day one because she came up in a rash across her "
                 "chest and both arms.",
            speaker="RN Maya Ortiz",
            start=4.2
        ),
        Segment(
            text="Right, I saw the levo on the MAR but not the reason.",
            speaker="RN Dev Patel",
            start=12.8
        ),
        Segment(
            text="Yeah, it never made it into the notes properly. Vitals have "
                 "been stable, she's afebrile.",
            speaker="RN Maya Ortiz",
            start=17.5
        ),
        Segment(
            text="Anything overnight I should watch?",
            speaker="RN Dev Patel",
            start=24.1
        ),
        Segment(
            text="She's been a bit tired but nothing I'd flag. Should be a "
                 "quiet one.",
            speaker="RN Maya Ortiz",
            start=27.9
        )
    ];
}


# ============================================================================
# B6 -- outbound call (ElevenLabs Agents over the SignalWire SIP trunk)
# ============================================================================

# REST, not the elevenlabs SDK: jac ships its own Python and `requests` is
# already there, so this adds no install step to the demo machine. Two
# endpoints, four fields -- the SDK buys nothing here.
glob ELEVENLABS_API: str = "https://api.elevenlabs.io/v1/convai";

# Test seam kept from A's stub -- escalate.jac imports this and adds numbers to
# it so the walker can be exercised climbing the chain past no-answers. Honoured
# here too: in the real adapter a refused number is simply nobody picking up, so
# it returns un-acknowledged and Escalate keeps walking. Do not remove without
# telling A -- escalate.jac's self-check depends on it.
glob REFUSE_PHONES: set[str] = set();

# The dual of REFUSE_PHONES, added when A's stub met B's real adapter. A number
# here answers with a scripted read-back and makes NO network call, so
# escalate.jac's chain-climbing tests run offline.
#
# Empty by default, and deliberately so: without an explicit test opt-in this
# adapter never reports an acknowledgment it did not receive. A's stub answered
# every call, which is fine for a stub and wrong for the real thing -- claiming a
# nurse acknowledged a page that was never placed is the one lie this system
# cannot tell (PRD §16, deterministic escalation). Un-configured telephony
# degrades to an on-screen notification and Escalate keeps walking, which is the
# honest outcome: nobody heard it.
glob STUB_ANSWER_PHONES: set[str] = set();

glob CALL_POLL_S: float = 3.0;
glob CALL_TIMEOUT_S: float = 150.0;   # the 40s cap is on the agent; this is the
                                      # wall-clock give-up for ring + talk + wrap.

"""Read-back check. The agent reads the request; acknowledgment only counts if
the HUMAN says the substance of it back (PRD 8). Judged against the human's
turns alone -- checking the full transcript would trivially pass, since the
agent itself said the request."""
def readback_ok(request: str, reply: str) -> bool by cheap();
sem readback_ok = "Decide whether a person on a phone call repeated back the substance of a request that was just made to them. Answer true only if their own words restate what is being asked for -- the action requested and who or what it concerns. Ignore wording, ignore politeness, ignore whether they agreed to do it. A bare 'yes', 'okay', 'got it', or 'I'll take care of it' is NOT a read-back and must answer false.";
sem readback_ok.request = "The request the automated caller made, as spoken.";
sem readback_ok.reply = "Everything the human said on the call, their turns only.";


"""On-screen notification instead of audio (PRD 10.5). Not acknowledged --
nobody heard it, so `Escalate` must keep walking the clinician chain."""
def notify(phone: str, script: str, why: str) -> CallResult {
    print(f"\n*** ESCALATION ({why}) -> {phone} ***\n{script}\n");
    return CallResult(
        acknowledged=False,
        readback=False,
        transcript=f"[on-screen notification: {why}] to {phone}: {script}"
    );
}


"""Outbound agent call. `script` is handed to the agent as the
`finding_script` dynamic variable -- the agent prompt is
identify -> one finding -> provenance -> ask -> read-back, with the finding
text coming from here so the walker controls what gets said."""
def place_call(phone: str, script: str) -> CallResult {
    if phone in REFUSE_PHONES {
        return notify(phone, script, "no answer");
    }
    if phone in STUB_ANSWER_PHONES {
        return CallResult(
            acknowledged=True,
            readback=True,
            transcript=f"[stub call to {phone}] read-back OK"
        );
    }
    key = os.getenv("ELEVENLABS_API_KEY");
    agent_id = os.getenv("ELEVENLABS_AGENT_ID");
    number_id = os.getenv("ELEVENLABS_PHONE_NUMBER_ID");
    if not (key and agent_id and number_id) {
        return notify(phone, script, "telephony not configured");
    }

    headers = {"xi-api-key": key};
    conv_id = "";
    turns: list[dict] = [];
    # Annotated dict[str, any], not a literal inline: the checker infers a
    # Literal-keyed dict from an inline body and rejects it against `json=`.
    payload: dict[str, any] = {
        "agent_id": agent_id,
        "agent_phone_number_id": number_id,
        "to_number": phone,
        "conversation_initiation_client_data": {
            "dynamic_variables": {"finding_script": script}
        }
    };
    try {
        import time;
        placed = requests.post(
            f"{ELEVENLABS_API}/sip-trunk/outbound-call",
            headers=headers,
            json=payload,
            timeout=30
        );
        placed.raise_for_status();
        call = placed.json();
        conv_id = call.get("conversation_id") or "";
        if not call.get("success") or not conv_id {
            return notify(phone, script, f"call not placed: {call.get('message')}");
        }

        status = "initiated";
        waited = 0.0;
        while waited < CALL_TIMEOUT_S {
            time.sleep(CALL_POLL_S);
            waited += CALL_POLL_S;
            got = requests.get(
                f"{ELEVENLABS_API}/conversations/{conv_id}", headers=headers, timeout=30
            );
            got.raise_for_status();
            conv = got.json();
            status = conv.get("status") or "";
            # "processing" means the call ended and the transcript is still
            # being written -- keep waiting, or we read an empty transcript and
            # wrongly report the page unacknowledged.
            if status in ["done", "failed"] {
                turns = conv.get("transcript") or [];
                break;
            }
        }
        if status != "done" {
            return notify(phone, script, f"call did not complete ({status}, {conv_id})");
        }
    } except Exception as e {
        return notify(phone, script, f"telephony error: {e}");
    }

    human = "\n".join([t["message"] for t in turns if t.get("role") == "user" and t.get("message")]);
    full = "\n".join([f"{t.get('role')}: {t['message']}" for t in turns if t.get("message")]);

    # Acknowledged means a person actually spoke on the call. Read-back is the
    # walker's termination condition, so parse it honestly -- an empty line or
    # a voicemail beep is not an acknowledgment.
    acknowledged = bool(human.strip());
    readback = acknowledged and readback_ok(script, human);
    print(f"[voice] call {conv_id}: acknowledged={acknowledged} readback={readback}");
    return CallResult(acknowledged=acknowledged, readback=readback, transcript=full);
}


with entry:__main__ {
    # Offline by design: no keys -> both functions take their degraded path, so
    # this self-check needs no network and no credits.
    segs = transcribe("audio/handoff.wav");

    # Every segment carries an author -- provenance dies without one.
    for s in segs {
        assert s.speaker, "every segment needs a speaker -- provenance needs an author";
        assert s.text, "every segment needs text";
    }
    # Speaker labels are stable across the file: the set of labels is small and
    # closed, and no label is a bare Deepgram integer.
    speakers = {s.speaker for s in segs};
    assert len(speakers) == 2, f"expected a 2-speaker handoff, got {speakers}";
    assert speakers <= set(SPEAKERS.values()), f"unmapped speaker label in {speakers}";
    # The spoken causal reason that exists nowhere in the written record.
    assert any(["rash" in s.text for s in segs]), "the spoken causal reason must be present";

    # Degraded call: never acknowledged, so Escalate keeps walking the chain
    # instead of silently marking a finding handled.
    r = place_call("+15555550123", "test script");
    assert not r.acknowledged, "an unplaced call must not count as acknowledged";
    assert not r.readback, "an unplaced call must not report a read-back";
    assert "+15555550123" in r.transcript, "degraded path must record the target";

    print(f"voice self-check OK: {len(segs)} segments, {len(speakers)} speakers, "
          "degraded call correctly not acknowledged");
}
