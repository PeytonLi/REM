"""Run the graph core on Person B's REAL data (seed/patient.json + device_readings).

A-owned integration harness. Loads the 400 manual episodes and 14 device
readings onto root (flat topology, which the graph core's 1-hop reads expect),
assigns a clinical subject to each so consolidation can cluster them, then runs
the full pipeline and checks fired rules against seed/expected.json.

This deliberately loads flat-on-root rather than through B's Handoff-nested
IngestDevice — the topology reconciliation between the two is a seam decision for
the team; this harness proves the graph core produces the right findings on the
real dataset today.

Run:  jac clean --all --force && REM_LIVE=1 jac run real_pipeline.jac
"""

import json;
import from schema { Episode, Clinical, now }
import from decay { ApplyDecay }
import from consolidate { Consolidate }
import from enrich { EnrichOrders }
import from tripwire { Tripwire }


"""Assign a coarse clinical subject by reading the content (deterministic — no
model). Planted topics cluster; generic ADL/noise buckets to 'adl'; the rest
stay unclustered ('') so decoys don't form spurious beliefs."""
def subject_of(content: str, source: str) -> str {
    c = content.lower();
    if "spo2" in c or "desaturat" in c or "o2 sat" in c or "oxygen" in c { return "spo2"; }
    if "fall" in c or "accelerometer" in c { return "fall"; }
    if "steps" in c or "mobility" in c { return "mobility"; }
    if "sleep" in c { return "sleep"; }
    if "uti" in c or "urine" in c or "urinary" in c or "levofloxacin" in c or "culture" in c { return "uti"; }
    if "rash" in c or "maculopapular" in c or "ceftriaxone" in c { return "rash"; }
    if "adl" in c or "ambulat" in c or "repositioned" in c or "up to chair" in c
        or "bed bath" in c or "oral care" in c or "bathroom" in c or "assisted" in c { return "adl"; }
    return "";
}


"""Format one device reading into a short episode note (deterministic)."""
def device_content(r: dict) -> str {
    m = r["metric"] as str;
    v = r["value"];
    base = r?["baseline"];
    if m == "spo2" { return f"SpO2 measured {v}% on the wearable overnight"; }
    if m == "fall" { return f"Fall detected via accelerometer, {v}"; }
    if m == "mobility" { return f"{v} steps today (mobility), baseline ~{base}"; }
    if m == "sleep" { return f"Sleep-quality score {v}/100, baseline ~{base}"; }
    return f"{m}: {v}";
}


with entry:__main__ {
    # -- load the 400 manual episodes ----------------------------------------
    with open("seed/patient.json") as f {
        manual: list[dict] = json.load(f);
    }
    latest = 0.0;
    for row in manual {
        at = row["at"] as float;
        if at > latest { latest = at; }
        root ++> Episode(
            content = row["content"] as str,
            source  = row["source"] as str,
            author  = row["author"] as str,
            at      = at,
            subject = subject_of(row["content"] as str, row["source"] as str)
        );
    }

    # -- load the 14 device readings -----------------------------------------
    with open("seed/device_readings.json") as f {
        device: list[dict] = json.load(f);
    }
    for r in device {
        at = r["timestamp"] as float;
        if at > latest { latest = at; }
        root ++> Episode(
            content = device_content(r),
            source  = r["source"] as str,
            author  = r["device_id"] as str,
            at      = at,
            subject = r["metric"] as str
        );
    }
    print(f"[load] {len(manual)} manual + {len(device)} device = "
        + f"{len([root -->[?:Episode]])} episodes on root");

    # -- pipeline: decay -> consolidate -> tripwire --------------------------
    root spawn ApplyDecay(at_time=latest);
    con = (root spawn Consolidate()).reports[0];
    print(f"[consolidate] {con.before} -> {con.after} live nodes");
    orders = (root spawn EnrichOrders()).reports[0];
    print(f"[enrich] {orders} running order(s) created + justified");
    print("[beliefs]");
    for c in [root -->[?:Clinical, suppressed == False]] {
        print(f"  ({c.category}) {c.claim}");
    }

    tw = root spawn Tripwire(now_ref=latest + 60.0);
    fired = [f for f in tw.reports if f.fired];
    rules = {};
    for f in fired { rules[f.rule] = True; }
    print(f"\n[tripwire] {len(fired)} findings fired: {sorted(rules.keys())}");
    for f in fired {
        print(f"  {f.rule} tier {f.tier}: {f.claim}");
    }

    # -- compare to expected.json --------------------------------------------
    with open("seed/expected.json") as f {
        expected: dict = json.load(f);
    }
    want = sorted((expected["should_fire"] as dict).keys());
    got = sorted(rules.keys());
    print(f"\n[expected] should fire: {want}");
    print(f"[actual]   did fire:    {got}");
    missing = [r for r in want if r not in rules];
    print(f"[gap] not yet firing on real data: {missing}");
}
