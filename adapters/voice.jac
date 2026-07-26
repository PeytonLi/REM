"""Voice adapters — B-owned seam stubs (WORKPLAN §3, PRD §10.5).

These are the hour-3 stubs from the frozen contract: `place_call` always
succeeds, `transcribe` returns hard-coded segments. A never waits on telephony
or Deepgram. The real implementations swap in behind the same signatures
(ElevenLabs / Deepgram) without the graph core changing.

Owned by B in the real split; provided here so A's escalation path runs
end-to-end. Graceful degradation (§10.5): if telephony dies, Escalate still runs
and still writes Acknowledged edges — this stub *is* that degraded path.
"""

import from contracts { Segment, CallResult }

# Test seam: phone numbers in this set do NOT answer (call not acknowledged).
# Lets the escalation walker be exercised climbing the chain past no-answers.
# In the real adapter this is simply what happens when a nurse doesn't pick up.
glob REFUSE_PHONES: set[str] = set();


"""Place an outbound escalation call and wait for read-back.

Stub: acknowledged with a good read-back unless `phone` is in REFUSE_PHONES. The
real adapter dials `phone`, speaks `script`, and transcribes the read-back.
"""
def place_call(phone: str, script: str) -> CallResult {
    if phone in REFUSE_PHONES {
        return CallResult(acknowledged=False, readback=False, transcript="");
    }
    return CallResult(
        acknowledged=True,
        readback=True,
        transcript=f"[stub call to {phone}] read-back OK"
    );
}


"""Transcribe a recorded verbal handoff into diarized segments.

Stub: six hard-coded utterances standing in for Deepgram Nova-3 batch output,
including the causal explanation that lives nowhere in the written record
(PRD §9.1 — the rash-switch reasoning).
"""
def transcribe(path: str) -> list[Segment] {
    return [
        Segment(text="Okay, handing off Mrs. Chen in room 14.", speaker="RN Maya", start=0.0),
        Segment(text="We switched her antibiotic on day one because she got a rash on the first one.", speaker="RN Maya", start=4.0),
        Segment(text="Her UTI culture came back negative, by the way.", speaker="RN Maya", start=9.0),
        Segment(text="Vitals have been mostly stable on my shift.", speaker="RN Maya", start=13.0),
        Segment(text="Got it. Anything overnight I should watch?", speaker="RN Jordan", start=17.0),
        Segment(text="Just keep an eye on her, she's been a little more tired than usual.", speaker="RN Maya", start=20.0)
    ];
}
