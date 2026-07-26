"""REM graph schema -- transcribed from PRD section 6.2 / 6.4.

PROVISIONAL, AND DELIBERATELY PARTIAL -- Person A owns this file and freezes it
at hour 2 (WORKPLAN section 2). This copy exists only so the Person B track can
compile before that freeze, so it carries ONLY the archetypes B actually reads
or writes:

  - Episode   : every ingest path produces these (manual, verbal, wearable)
  - Clinical  : B reads these for the omission panel; B never creates one
  - SBARPlus  : B renders this; A composes it
  - Handoff   : the entry node walkers attach episodes to

A's consolidation machinery -- Derived / Causes / Justifies / Contradicts /
Refines / Completed / Fired / Acknowledged / Escalates / Follows, plus the
Action and Clinician nodes -- is intentionally NOT here. Those edges have
endpoint decisions that belong to A, and guessing them would create a merge
conflict for no benefit to B.

Two spec conflicts A needs to resolve before freezing -- see SPEC-CONFLICT
notes at the bottom of this file.
"""

obj ActionLine {
    has task: str;
    has owner: str;
    has due: str;
}

obj IfThen {
    has trigger: str;
    has response: str;
}

obj SBARPlus {
    has situation: str;
    has background: str;
    has assessment: str;
    has recommendation: str;
    has action_list: list[ActionLine];
    has contingencies: list[IfThen];
}

node Episode {
    has content: str;
    has source: str;      # nursing_note | vitals_manual | mar | lab | family
                          # | verbal_handoff
                          # | wearable_vitals | wearable_fall
                          # | wearable_mobility | wearable_sleep
    has author: str;      # staff name, or device_id for wearable sources
    has at: float;
    has strength: float = 1.0;
    has access_count: int = 0;
    has archived: bool = False;   # PRD 6.3 phase 4 -- never `del`
}

node Clinical {
    has claim: str;
    has category: str;
    has last_asserted: float;
    has last_verified: float;
    has strength: float = 1.0;
    has suppressed: bool = False;   # PRD 6.3 phase 3 -- losers suppress, not delete
}

node Handoff {
    has shift: str;
    has signed_by: str = "";
}

# SPEC-CONFLICT 1 -- `Action` is declared twice in the PRD, as a graph node
# (section 6.2, `has due: float`) and as a composition struct (section 6.4,
# `has due: str`). One namespace cannot hold both. Resolved here by renaming the
# struct to `ActionLine` and leaving the graph node `Action` to A, untouched.
# If A would rather rename the node, change this and tell B.
#
# SPEC-CONFLICT 2 -- `node Handoff` in section 6.2 carries `has sbar: SBARPlus`,
# which forces every Handoff to hold a composed SBAR before Compose has run.
# Dropped that field here; A should attach the composed SBARPlus via an edge, or
# make the field optional (`SBARPlus | None = None`). B only needs `shift`.
