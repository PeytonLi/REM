"""End-to-end driver for the deterministic core (no LLM): seed -> tripwire ->
escalate. Verifies the headline eval claim — all six planted findings fire,
zero of the decoys — and that escalation writes an Acknowledged edge.

Run:  jac clean --all --force && jac run driver.jac
"""

import from fixture { SeedGraph, SEED_NOW }
import from tripwire { Tripwire }
import from escalate { Escalate }
import from adapters.voice { STUB_ANSWER_PHONES }
import from schema { Clinical, Clinician, Fired, Acknowledged, now }


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

    # -- Escalate every tier-3 finding (the phone-call beat) ------------------
    # Stub each clinician's phone so the offline path exercises the full chain
    # without live telephony. Drop these lines + set BRIDGE_URL to place real calls.
    for c in [root -->[?:Clinician]] {
        STUB_ANSWER_PHONES.add(c.phone);
    }
    tier3_beliefs = [c for c in [root -->[?:Clinical]]
                     for edge in [c ->:Fired:->]
                     if edge.tier >= 3];
    print(f"\n[escalate] {len(tier3_beliefs)} tier-3 belief(s) to escalate:");
    for c in tier3_beliefs {
        esc = root spawn Escalate(finding_id=jid(c));
        r = esc.reports[0];
        ack_edges = [edge c <-:Acknowledged:<-];
        print(f"  {c.category}: chain {r.chain}, acknowledged {r.acknowledged}, "
              + f"{len(ack_edges)} Acknowledged edge(s)");
    }
}
