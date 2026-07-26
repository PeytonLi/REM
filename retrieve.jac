"""Retrieval + the A-provided seam functions (PRD §6.2, §9.3, §13).

Retrieval is the other half of decay: reading an episode bumps its access count
and boosts its strength, so *use shapes what survives* into the next handoff.

Also home to the two functions A provides across the seam (contracts.jac):
  * required_findings() — the obligations set the omission check consumes (§9.3)
  * provenance(claim_id) — click-to-source for the graph view (§13)
"""

import from schema { Episode, Clinical, ActionNode, Derived, Justifies, Contradicts, now }
import from decay { RETRIEVAL_BOOST, STRENGTH_FLOOR }


"""Apply a retrieval hit to one episode in place: count it, restamp it, boost it.

Strength is capped at 1.0 — retrieval reinforces, it does not inflate.
"""
def boost(ep: Episode, at_time: float) {
    ep.access_count += 1;
    ep.last_accessed = at_time;
    ep.strength = 1.0 if ep.strength + RETRIEVAL_BOOST > 1.0 else ep.strength + RETRIEVAL_BOOST;
}


"""Retrieve episodes, optionally filtered by subject tag, and reinforce them.

Every returned episode is boosted, so pulling a belief's sources into a handoff
keeps them alive. Archived episodes are skipped — they stay in the graph but are
one click away, not in the working set.
"""
walker:pub Retrieve {
    has subject: str = "";
    has at_time: float = 0.0;
    has hits: list[Episode] = [];
    has reports: list[Episode] = [];

    can start with Root entry {
        if self.at_time == 0.0 {
            self.at_time = now();
        }
        visit [-->];
    }

    can pick with Episode entry {
        keep = (not here.archived)
            and (self.subject == "" or here.subject == self.subject);
        if keep {
            boost(here, self.at_time);
            self.hits.append(here);
        }
        visit [-->];
    }

    can finish with Root exit {
        for ep in self.hits {
            report ep;
        }
    }
}


# ---------------------------------------------------------------------------
# A provides, B consumes (contracts.jac)
# ---------------------------------------------------------------------------

"""The obligations set (PRD §9.3): what a handoff is *required* to convey.

Deterministic — no LLM. A live belief is an obligation when it justifies an
active care task, is contradicted, or sits in a watched category. Suppressed
losers are excluded. The omission check compares this against what was said.
"""
def required_findings -> list[Clinical] {
    out: list[Clinical] = [];
    for c in [root -->[?:Clinical]] {
        if c.suppressed {
            continue;
        }
        justifies = len([c ->:Justifies:->]) > 0;
        contradicted = len([c ->:Contradicts:->]) > 0
            or len([c <-:Contradicts:<-]) > 0;
        watched = c.strength >= STRENGTH_FLOOR;
        if justifies or contradicted or watched {
            out.append(c);
        }
    }
    return out;
}


"""Click-to-source (PRD §13): the source episodes a belief was derived from.

`claim_id` is the jid of a Clinical node; returns its `Derived` provenance set.
"""
def provenance(claim_id: str) -> list[Episode] {
    try {
        target = jobj(claim_id);
    } except Exception {
        return [];
    }
    if not isinstance(target, Clinical) {
        return [];
    }
    return [target ->:Derived:->];
}


# ---------------------------------------------------------------------------
# Self-checks
# ---------------------------------------------------------------------------

test "retrieval boosts strength and bumps access count" {
    ep = Episode(content="x", source="nursing_note", author="RN Maya", at=now(),
                 strength=0.5, access_count=0);
    boost(ep, now());
    assert ep.access_count == 1;
    assert ep.strength == 0.75;
    assert ep.last_accessed > 0.0;
}

test "boost caps strength at 1.0" {
    ep = Episode(content="x", source="lab", author="Lab", at=now(), strength=0.9);
    boost(ep, now());
    assert ep.strength == 1.0;
}

test "provenance returns [] for a non-Clinical jid" {
    assert provenance("not-a-real-jid") == [];
}
