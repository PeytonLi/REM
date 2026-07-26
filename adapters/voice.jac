"""Voice adapters -- STUB implementations (WORKPLAN section 3, hour-3 deliverable).

These exist so Person A is never blocked on telephony or transcription. Both
always succeed. The real implementations land in tasks B3 (Deepgram) and B6
(ElevenLabs via SignalWire SIP trunk) and MUST keep these exact signatures.

PRD 10.5 -- the call layer is swappable, not load-bearing. If telephony dies on
demo day, `place_call` returns a CallResult produced by an on-screen
notification instead, and the Escalate walker never knows the difference. That
is a design constraint, not a fallback bolted on later.
"""

import from contracts { Segment, CallResult }


"""STUB: always acknowledged, always clean read-back.

Real version (B6): ElevenLabs Agents outbound, routed over the SignalWire SIP
trunk. ElevenLabs provisions no numbers itself on any tier, so the trunk is
registered as a generic SIP trunk (SIP URI + digest auth).
"""
def place_call(phone: str, script: str) -> CallResult {
    return CallResult(
        acknowledged=True,
        readback=True,
        transcript=f"[stub] delivered to {phone}: {script}"
    );
}


"""STUB: six hard-coded diarized segments from the 45s handoff script.

Real version (B3): Deepgram Nova-3 batch with diarization enabled. Diarization
is REQUIRED, not optional -- provenance needs an author, and an unattributed
transcript breaks the trust model (PRD 9.2).

The script deliberately contains one causal explanation that exists nowhere in
the written record (the rash), and deliberately omits things the graph knows
are required -- that is what feeds the omission panel.
"""
def transcribe(path: str) -> list[Segment] {
    print(f"[stub] transcribe ignoring {path}, returning scripted segments");
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


with entry:__main__ {
    # Self-check: the stubs must satisfy the contract A codes against.
    r = place_call("+15555550123", "test script");
    assert r.acknowledged, "stub call must acknowledge so A is never blocked";
    assert r.readback, "stub call must report a clean read-back";

    segs = transcribe("audio/handoff.wav");
    assert len(segs) == 6, f"expected 6 stub segments, got {len(segs)}";
    for s in segs {
        assert s.speaker, "every segment needs a speaker -- provenance needs an author";
        assert s.text, "every segment needs text";
    }
    # Two distinct speakers, and the causal reason the written record lacks.
    assert len({s.speaker for s in segs}) == 2, "script must be a 2-speaker handoff";
    assert any(["rash" in s.text for s in segs]), "the spoken causal reason must be present";
    print(f"voice stub self-check OK: {len(segs)} segments, 2 speakers, call acknowledged");
}
