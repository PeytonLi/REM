"""Frozen cross-seam contracts (WORKPLAN §3).

The ONLY place the graph-interior (A) and graph-boundary (B) tracks touch. Both
sides code against these shapes. Shared obj definitions live here; the function
signatures they carry are documented below and implemented on the owning side:

    # --- B provides, A consumes (adapters/voice.jac) --------------------
    def transcribe(path: str) -> list[Segment];
    def place_call(phone: str, script: str) -> CallResult;

    # --- A provides, B consumes (query.jac) -----------------------------
    def required_findings() -> list[Clinical];   # obligations set, PRD §9.3
    def provenance(claim_id: str) -> list[Episode];   # click-to-source, PRD §13

FROZEN at hour 2. Changes after freeze require the other track's ack.
"""


obj Segment {
    """One diarized utterance from a transcribed verbal handoff (PRD §9)."""
    has text: str;
    has speaker: str;
    has start: float;
}

obj CallResult {
    """Outcome of one outbound escalation call (PRD §8, §10.5)."""
    has acknowledged: bool;
    has readback: bool;
    has transcript: str = "";
}
