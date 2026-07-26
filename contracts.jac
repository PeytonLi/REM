"""Cross-seam contract types (WORKPLAN section 3).

PROVISIONAL -- Person A owns this file and freezes it at hour 2. Person B wrote
this copy verbatim from WORKPLAN section 3 so the B track could compile before
the freeze. If A's frozen version differs, A's wins; delete this and re-point.

These are the ONLY types that cross between the two tracks.
"""

obj Segment {
    has text: str;
    has speaker: str;
    has start: float;
}

obj CallResult {
    has acknowledged: bool;
    has readback: bool;
    has transcript: str;
}
