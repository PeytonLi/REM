"""REM graph schema — nodes, edges, SBAR-plus objs, source/category vocab.

Source of truth: PRD §6.2 and §6.4. FROZEN after hour 2 (WORKPLAN §2). Every
other module in the graph core imports from here. Two things the PRD leaves as a
naming collision are resolved here:

  * `Action` in §6.4 (the SBAR-plus line item, an obj the LLM fills) keeps the
    name — it is the frozen cross-seam type B's client renders.
  * `Action` in §6.2 (the graph task node for R4 / Justifies) becomes `ActionNode`
    so both can coexist in one module namespace.
"""

import from time { time }


# ---------------------------------------------------------------------------
# Source & category vocabulary (PRD §6.2). `Episode.source` stays a `str` so the
# JSON/CSV ingest path stays trivial; these sets document the 10 valid values and
# let the tripwire group them without string literals scattered across files.
# ---------------------------------------------------------------------------

glob SOURCES: set[str] = {
    "nursing_note", "vitals_manual", "mar", "lab", "family", "verbal_handoff",
    "wearable_vitals", "wearable_fall", "wearable_mobility", "wearable_sleep"
};

glob WEARABLE_SOURCES: set[str] = {
    "wearable_vitals", "wearable_fall", "wearable_mobility", "wearable_sleep"
};

# Categories the tripwire watches (R1 corroboration, R5 decline). A Clinical whose
# category is outside this set can still exist — it just never rings a phone.
glob WATCHED: set[str] = {
    "respiratory", "cardiac", "infection", "neuro", "mobility", "sleep", "fall", "skin"
};


# ---------------------------------------------------------------------------
# Graph nodes (PRD §6.2)
# ---------------------------------------------------------------------------

node Episode {
    """Raw, timestamped, attributed observation. Cheap to make, decays fast."""
    has content: str;
    has source: str;                 # one of SOURCES
    has author: str;                 # staff name, or device_id for wearable_* sources
    has at: float;                   # epoch seconds
    has strength: float = 1.0;
    has access_count: int = 0;
    has last_accessed: float = 0.0;  # epoch seconds; 0.0 == never retrieved
    has archived: bool = False;      # pruned (§6.3 phase 4). Never `del`.
    has subject: str = "";           # coarse subject tag for reconcile gating (§15)
}

node Clinical {
    """Semantic belief distilled from >=3 episodes. Decays slowly. Always cited."""
    has claim: str;
    has category: str;
    has last_asserted: float;
    has last_verified: float;
    has strength: float = 1.0;
    has suppressed: bool = False;    # reconcile loser (§6.3 phase 3). Never `del`.
    has subject: str = "";           # reconcile gating tag (§15)
}

node ActionNode {
    """A care task. `Justifies` links the belief that keeps it running (R2/R4)."""
    has task: str;
    has due: float;
    has owner: str;
}

node Handoff {
    """One shift-report object. Chains to the prior via `Follows` (§6.5)."""
    has shift: str;
    has signed_by: str = "";
    has sbar: SBARPlus | None = None;
}

node Clinician {
    """A link in the escalation chain (§5): CNA -> nurse -> charge/DON -> on-call MD."""
    has name: str;
    has phone: str;
    has role: str;                   # RN | LPN | CNA | on-call MD
    has rank: int = 0;               # ascending escalation order; walker climbs it
}


# ---------------------------------------------------------------------------
# Graph edges (PRD §6.2). Typed endpoints so traversals infer node types.
# ---------------------------------------------------------------------------

edge Derived: Clinical --> Episode {}                       # provenance (G2)
edge Causes: Episode --> Episode {}                         # the "why" (failure mode #1)
edge Justifies: Clinical --> ActionNode {}                  # why an order runs
edge Contradicts: Clinical --> Clinical {
    has resolved_toward: str = "";
    has at: float = 0.0;
}
edge Refines: Clinical --> Clinical {}
edge Completed: ActionNode --> ActionNode {                 # marker; self-loop carries `at`
    has at: float = 0.0;
}
edge Fired: Clinical --> Clinical {                         # suppression marker (self-loop)
    has at: float = 0.0;
    has rule: str = "";
    has tier: int = 0;
}
edge Acknowledged: Clinician --> Clinical {
    has at: float = 0.0;
    has readback_ok: bool = False;
}
edge Escalates: Clinician --> Clinician {
    has after_seconds: int = 0;
}
edge Follows: Handoff --> Handoff {}


# ---------------------------------------------------------------------------
# SBAR-plus composition objs (PRD §6.4). LLM fills these; never graph-persisted.
# ---------------------------------------------------------------------------

obj Action {
    """One line item on the handoff's explicit action list."""
    has task: str;
    has owner: str;
    has due: str;
}

obj IfThen {
    """A contingency: if `trigger` is observed, do `response`."""
    has trigger: str;
    has response: str;
}

obj SBARPlus {
    """Situation/Background/Assessment/Recommendation + action list + contingencies."""
    has situation: str;
    has background: str;
    has assessment: str;
    has recommendation: str;
    has action_list: list[Action] = [];
    has contingencies: list[IfThen] = [];
}


# ---------------------------------------------------------------------------
# Report objs — typed channels for the walker REST responses (WORKPLAN §4).
# ---------------------------------------------------------------------------

obj Finding {
    """One tripwire hit, ready to report or escalate."""
    has rule: str;                   # R1..R6
    has claim: str;
    has category: str;
    has tier: int;                   # 0 handoff / 1 dashboard / 2 push / 3 call
    has fired: bool;
    has evidence: list[str] = [];    # human-readable citations
    has claim_id: str = "";          # jid of the source Clinical, for provenance()
}

obj Step {
    """One line of the Consolidate replay log (demo replays this, PRD §13)."""
    has phase: str;                  # replay | abstract | reconcile | prune
    has detail: str;
    has before: int = 0;
    has after: int = 0;
}


# ---------------------------------------------------------------------------
# Time helpers. Kept here so every module shares one clock.
# ---------------------------------------------------------------------------

"""Current epoch seconds."""
def now -> float {
    return time();
}

"""Seconds -> hours, for the 72h / 24h window checks."""
def hours(seconds: float) -> float {
    return seconds / 3600.0;
}

"""True for the four device-sourced episode kinds (§6.2a)."""
def is_wearable(source: str) -> bool {
    return source in WEARABLE_SOURCES;
}
