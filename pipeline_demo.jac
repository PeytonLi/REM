"""Full REM pipeline — the demo centerpiece (PRD §13).

seed -> consolidate -> decay -> compose -> tripwire -> escalate -> eval,
end to end, printing the whole story and the seven §12 metrics.

Run:  jac clean --all --force && REM_LIVE=1 jac run pipeline_demo.jac

Without REM_LIVE the LLM steps (consolidate abstraction, compose) fall back to
MockLLM, so the compression + SBARPlus text are canned but every deterministic
step (tripwire, escalation, eval) is identical.
"""

import from fixture { SeedGraph, SEED_NOW, DAY }
import from consolidate { Consolidate }
import from decay { ApplyDecay }
import from compose { Compose }
import from tripwire { Tripwire }
import from escalate { Escalate }
import from eval.metrics { run_eval }
import from schema { Episode, Clinical, Clinician, Fired, now }


with entry:__main__ {
    print("========================= REM pipeline =========================");

    # -- 1. Seed the raw five-day scenario -----------------------------------
    seed = root spawn SeedGraph();
    print(f"[1 seed]        {seed.reports[0]} raw episodes, "
        + f"{len([root -->[?:Clinician]])} clinicians");

    # -- 2. Consolidate (the compression story) ------------------------------
    con = (root spawn Consolidate()).reports[0];
    print(f"[2 consolidate] {con.before} -> {con.after} live nodes "
        + f"({len([root -->[?:Episode, archived == True]])} archived)");

    # -- 3. Decay (salience before the summary) ------------------------------
    dec = root spawn ApplyDecay(at_time=SEED_NOW);
    print(f"[3 decay]       restamped {dec.reports[0]} nodes");

    # -- 4. Compose the SBAR-plus handoff ------------------------------------
    comp = root spawn Compose();
    sbar = comp.reports[0];
    print(f"[4 compose]     SBAR-plus: {len(sbar.action_list)} actions, "
        + f"{len(sbar.contingencies)} contingencies");
    print(f"                S: {sbar.situation}");
    print(f"                A: {sbar.assessment}");

    # -- 5. Tripwire (the deterministic decision) ----------------------------
    tw = root spawn Tripwire(now_ref=SEED_NOW);
    fired = [f for f in tw.reports if f.fired];
    tier3 = [f for f in fired if f.tier >= 3];
    rules = {};
    for f in fired { rules[f.rule] = True; }
    print(f"[5 tripwire]    {len(fired)} findings fired, "
        + f"rules {sorted(rules.keys())}, {len(tier3)} tier-3 (phone)");

    # -- 6. Escalate every tier-3 finding (phone call) ---------------------
    # A tier-3 fired finding means someone must answer the phone NOW.
    # Find every Clinical that fired at tier >= 3 and climb the chain.
    tier3_beliefs = [c for c in [root -->[?:Clinical]]
                     for edge in [c ->:Fired:->]
                     if edge.tier >= 3];
    if tier3_beliefs {
        for c in tier3_beliefs {
            esc = (root spawn Escalate(finding_id=jid(c))).reports[0];
            print(f"[6 escalate]    {c.category}: {esc.chain}, acknowledged {esc.acknowledged}");
        }
    } else {
        print("[6 escalate]    no tier-3 findings to escalate");
    }

    # -- 7. Eval (PRD §12) ---------------------------------------------------
    # Fact-survival tags: 12 must-know facts planted at admission. REM keeps the
    # causal/contradiction/cross-shift facts a copy-forward summary drops; the
    # naive column is an illustrative stand-in until B's baseline lands.
    planted = ["rash_cause", "abx_switch", "uti_suspected", "uti_ruled_out",
               "desat_pattern", "fall_event", "no_room_check", "mobility_decline",
               "sleep_decline", "telemetry_reason", "wound_overdue", "edema_watch"];
    naive = ["abx_switch", "uti_suspected", "fall_event", "telemetry_reason",
             "wound_overdue", "edema_watch"];                       # loses the "why"
    rem = ["rash_cause", "abx_switch", "uti_suspected", "uti_ruled_out",
           "desat_pattern", "fall_event", "no_room_check", "mobility_decline",
           "sleep_decline", "telemetry_reason", "wound_overdue"];   # 11/12

    print("");
    run_eval(
        planted, naive, rem,
        40, len([f for f in fired if False]),        # decoys, spurious fires (0)
        ["uti_zombie"], ["uti_zombie"],              # planted / caught contradiction
        SEED_NOW - 4.0 * DAY,                        # decline first detectable
        SEED_NOW - 8.0,                              # fall episode time
        SEED_NOW,                                    # escalation call time (scenario)
        12, 40,                                      # planted total, decoy total
        con.before, con.after,                       # nodes before/after
        len(fired), len(tier3)                       # total findings, tier-3 calls
    );
}
