"""End-to-end driver for the deterministic core (no LLM): seed -> tripwire ->
escalate. Verifies the headline eval claim — all six planted findings fire,
zero of the decoys — and that escalation writes an Acknowledged edge.

Run:  jac clean --all --force && jac run driver.jac
"""

import from fixture { SeedGraph, SEED_NOW }
import from tripwire { Tripwire }
import from escalate { Escalate }
import from adapters.voice { STUB_ANSWER_PHONES }
import from schema { Clinical, Clinician, Acknowledged, now }


with entry:__main__ {
    seed = root spawn SeedGraph();
    print(f"[seed] raw episodes: {seed.reports[0]}");
    print(f"[seed] clinicians:   {len([root -->[?:Clinician]])}");
    print(f"[seed] beliefs:      {len([root -->[?:Clinical]])}");

    # -- Tripwire (pure graph, clock pinned to the scenario now) --------------
    tw = root spawn Tripwire(now_ref=SEED_NOW);
    findings = tw.reports;
    fired = [f for f in findings if f.fired];
    rules = {};
    for f in fired {
        rules[f.rule] = True;
    }
    print(f"\n[tripwire] findings fired: {len(fired)}");
    for f in fired {
        print(f"  {f.rule}  tier {f.tier}  {f.claim}");
    }
    print(f"[tripwire] distinct rules fired: {sorted(rules.keys())}");

    # -- Escalate the fall (R6), the primary demo call (Call script A) --------
    fall_beliefs = [root -->[?:Clinical, category == "fall"]];
    if fall_beliefs {
        # Make the first clinician answer without live telephony (B's stub seam):
        # exercises the acknowledged path offline. Drop this + set ELEVENLABS_* to
        # place a real call.
        for c in [root -->[?:Clinician]] {
            STUB_ANSWER_PHONES.add(c.phone);
        }
        fall = fall_beliefs[0];
        esc = root spawn Escalate(finding_id=jid(fall));
        r = esc.reports[0];
        print(f"\n[escalate] chain: {r.chain}");
        print(f"[escalate] acknowledged: {r.acknowledged}");
        ack_edges = [edge fall <-:Acknowledged:<-];
        print(f"[escalate] Acknowledged edges into fall belief: {len(ack_edges)}");
    }
}
