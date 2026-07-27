"""Escalation walker + call-script builder (PRD §8, §5, §10.5).

The escalation chain is the long-term-care reality (§5): CNA -> nurse ->
charge nurse/DON -> on-call MD, NOT a flattened hospital hierarchy. `Clinician`
nodes hang off `root` and are strung together by `Escalates` edges in ascending
`rank`. `Escalate` starts at the lowest-rank clinician and climbs: it places a
call, and only a call that is acknowledged *with a verbal read-back* stops the
climb and writes an `Acknowledged` edge onto the finding.

Graceful degradation (§10.5): `place_call` is B's stub. The walker runs and
writes `Acknowledged` edges regardless of whether real telephony is wired — the
stub path *is* the degraded path, no special-casing.

Note on `disengage`: PRD §8's sketch calls `disengage` on acknowledgment, but in
jaclang a `disengage` discards deferred exit abilities, which would swallow the
single `with Root exit` report. We instead flip an `acknowledged` flag and stop
queueing the next clinician, so the walker finishes naturally and reports exactly
one `EscalationResult` from `with Root exit`.
"""

import os;
import time;
import from schema { Clinician, Clinical, Episode, Escalates, Acknowledged, Derived, now }
import from adapters.voice { place_call, REFUSE_PHONES, STUB_ANSWER_PHONES }

# The scenario is one resident (PRD §11), and no node carries their name -- so the
# one identity fact the nurse will ask for ("which patient was this?") lives here.
glob RESIDENT: str = os.getenv("REM_RESIDENT") or "Harold Alvarez, Room 3";


obj EscalationResult {
    """Outcome of one escalation walk: did anyone ack, and who was called."""
    has acknowledged: bool = False;
    has chain: list[str] = [];        # ordered names of clinicians actually called
}


"""Build the outbound call script for a finding — deterministic, no LLM.

Primary demo is the R6 fall (Call script A, §8). The wording is derived from the
finding's `claim` so the script is faithful to the belief being escalated and
still asks for the mandatory read-back.
"""
def script_for(finding: Clinical) -> str {
    return (
        "This is the handoff assistant calling. "
        + finding.claim
        + " No room check has been logged yet. Requesting an immediate check. "
        + "Can you read back the request?"
    );
}


"""Clock label for an epoch second. UTC, because the seeded demo day is UTC."""
def clock(at: float) -> str {
    return time.strftime("%H:%M on %d %b", time.gmtime(at));
}


"""The bounded fact set the agent may quote when the nurse asks a question.

Every line is already in the graph -- the identity of the resident, the belief
being escalated, its clock times, and its `Derived` provenance. The agent gets no
license to invent, only to answer "which patient?" or "what time was that?" from
the same belief the call is about, which keeps §7.4 intact: the graph decides the
content, the model is only the voice. Anything outside these lines still gets
"I only have the finding I just read."
"""
def context_for(finding: Clinical) -> str {
    lines: list[str] = [
        "Resident: " + RESIDENT + ".",
        "Finding: " + finding.claim,
        "Category: " + finding.category + ".",
        "Detected at: " + clock(finding.last_asserted) + " (UTC).",
        "Last verified by a person: " + clock(finding.last_verified) + " (UTC)."
    ];
    for ep in [finding ->:Derived:->] {
        lines.append(
            "Evidence: " + ep.source + " recorded by " + ep.author
            + " at " + clock(ep.at) + ": " + ep.content
        );
    }
    return "\n".join(lines);
}


"""Climb the Clinician chain in rank order, calling each until one acknowledges.

Spawn on `root` with a Clinical jid in `finding_id`. The walker resolves the jid
(guarded — a bad jid raises), starts at the lowest-rank root-attached Clinician,
and on each clinician places a call. A call that is acknowledged with a verbal
read-back writes `Acknowledged(at, readback_ok)` and stops the climb; otherwise
the walker follows the `Escalates` edge to the next-higher clinician. Reports one
`EscalationResult` from `with Root exit`, with `chain` = the clinicians called.
"""
walker:pub Escalate {
    has finding_id: str = "";
    has finding: Clinical | None = None;
    has acknowledged: bool = False;
    has chain: list[str] = [];
    has reports: list[EscalationResult] = [];

    can start with Root entry {
        try {
            target = jobj(self.finding_id);
        } except Exception {
            skip;                     # bad jid -> exit reports acknowledged=False
        }
        if not isinstance(target, Clinical) {
            skip;
        }
        self.finding = target;

        clinicians = [root -->[?:Clinician]];
        if not clinicians {
            skip;
        }
        lowest = clinicians[0];
        for c in clinicians {
            if c.rank < lowest.rank {
                lowest = c;
            }
        }
        visit [lowest];               # start at the lowest-rank link in the chain
    }

    can page with Clinician entry {
        if self.acknowledged {
            skip;
        }
        f = self.finding;
        if not isinstance(f, Clinical) {
            skip;
        }
        self.chain.append(here.name);
        result = place_call(here.phone, script_for(f), context_for(f));
        if result.acknowledged {
            here +>:Acknowledged(at=now(), readback_ok=result.readback):+> f;
            self.acknowledged = True;
            skip;                     # stop climbing; let Root exit report
        }
        visit [here ->:Escalates:->]; # nurse -> charge nurse/DON -> on-call MD
    }

    can finish with Root exit {
        report EscalationResult(acknowledged=self.acknowledged, chain=self.chain);
    }
}


# ---------------------------------------------------------------------------
# Self-checks
# ---------------------------------------------------------------------------

test "script_for is deterministic and derived from the finding's claim" {
    f = Clinical(claim="The wearable detected a fall at 2:14 AM with no movement for two minutes.",
                 category="fall", last_asserted=now(), last_verified=now());
    s = script_for(f);
    assert "read back" in s;
    assert "fall at 2:14 AM" in s;
    assert s == script_for(f);        # deterministic
}

test "context_for carries who, what, and when -- and nothing invented" {
    f = Clinical(claim="Unwitnessed fall at 02:14, no room check logged yet",
                 category="fall", last_asserted=1712347200.0,
                 last_verified=1712347200.0, subject="fall");
    root ++> f;
    ep = root ++> Episode(content="Fall detected via accelerometer, no movement for 2 min (02:14)",
                          source="wearable_fall", author="dev_014",
                          at=1712347192.0, subject="fall");
    f +>:Derived():+> ep;

    c = context_for(f);
    assert RESIDENT in c;                 # "which patient was this again?"
    assert "20:00" in c;                  # "what time was it again?"
    assert "fall" in c;
    assert "dev_014" in c;                # provenance is quotable, so is its author
    assert ep.content in c;
    assert c == context_for(f);           # deterministic, no LLM
}

test "escalation climbs past two no-answers to the third clinician" {
    c1 = Clinician(name="CNA Dana", phone="555-0001", role="CNA", rank=1);
    c2 = Clinician(name="RN Maya", phone="555-0002", role="RN", rank=2);
    c3 = Clinician(name="Dr. Lee", phone="555-0003", role="on-call MD", rank=3);
    root ++> c1;
    root ++> c2;
    root ++> c3;
    c1 +>:Escalates(after_seconds=60):+> c2;
    c2 +>:Escalates(after_seconds=120):+> c3;

    finding = Clinical(claim="Fall detected in Room 14, no movement for two minutes.",
                       category="fall", last_asserted=now(), last_verified=now());
    root ++> finding;

    REFUSE_PHONES.add("555-0001");
    REFUSE_PHONES.add("555-0002");
    # Dr. Lee picks up. Explicit now that the adapter is real: it will not
    # invent an acknowledgment just because telephony is unconfigured.
    STUB_ANSWER_PHONES.add("555-0003");

    r = root spawn Escalate(finding_id=jid(finding));
    res = r.reports[0];
    assert res.acknowledged;
    assert res.chain == ["CNA Dana", "RN Maya", "Dr. Lee"];
    assert len(res.chain) == 3;

    acks = [edge finding <-:Acknowledged:<-];
    assert len(acks) == 1;            # exactly one Acknowledged edge, at the top
    assert acks[0].readback_ok;

    REFUSE_PHONES.discard("555-0001");
    REFUSE_PHONES.discard("555-0002");
    STUB_ANSWER_PHONES.discard("555-0003");
}

test "first clinician answers: chain length 1, acknowledged" {
    c1 = Clinician(name="CNA Dana", phone="555-1001", role="CNA", rank=1);
    c2 = Clinician(name="RN Maya", phone="555-1002", role="RN", rank=2);
    root ++> c1;
    root ++> c2;
    c1 +>:Escalates():+> c2;

    finding = Clinical(claim="SpO2 desaturation flagged.", category="respiratory",
                       last_asserted=now(), last_verified=now());
    root ++> finding;

    STUB_ANSWER_PHONES.add("555-1001");
    r = root spawn Escalate(finding_id=jid(finding));
    res = r.reports[0];
    assert res.acknowledged;
    assert len(res.chain) == 1;
    assert res.chain == ["CNA Dana"];
    assert len([edge finding <-:Acknowledged:<-]) == 1;
    STUB_ANSWER_PHONES.discard("555-1001");
}

test "bad finding jid degrades gracefully: no ack, empty chain" {
    c1 = Clinician(name="CNA Dana", phone="555-2001", role="CNA", rank=1);
    root ++> c1;

    r = root spawn Escalate(finding_id="not-a-real-jid");
    res = r.reports[0];
    assert not res.acknowledged;
    assert res.chain == [];
}
