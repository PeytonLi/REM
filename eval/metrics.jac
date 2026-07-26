"""The seven evaluation metrics (PRD §12) as pure, LLM-free functions.

Each metric is a small deterministic function taking hand-built inputs (or reading
the graph), so the demo can report honest numbers and the orchestrator can wire
the real fixture counts in later without touching this file. A `run_eval` runner
assembles an `EvalReport` and prints a confusion-matrix-style summary of the
fire / no-fire decision over planted findings + decoys.

The seven (PRD §12 table):
  1. Fact survival        — planted must-know facts still alive (naive vs REM)
  2. False-positive rate  — spurious fires against planted decoys (target 0)
  3. Contradiction detect — planted zombies caught (1/1)
  4. Antecedent decline   — caught + lead time in days before the fall
  5. Fall response        — latency in seconds from wearable_fall to the call
  6. Compression          — nodes before vs after (+ token estimate)
  7. Alarm ratio          — total findings vs tier-3 calls ("142 : 3")

Root-absolute import (resolves from project root regardless of this file's depth).
"""

import from schema { Episode, now }


# ---------------------------------------------------------------------------
# Result objs
# ---------------------------------------------------------------------------

obj DeclineResult {
    """Antecedent-decline outcome: was it caught, and how many days before the fall."""
    has caught: bool = False;
    has lead_days: float = 0.0;
}

obj ConfusionMatrix {
    """Fire / no-fire decision counts over planted findings (positive) + decoys (negative)."""
    has tp: int = 0;                 # planted finding that fired  (correct alarm)
    has fp: int = 0;                 # decoy that fired            (false alarm)
    has tn: int = 0;                 # decoy that stayed silent    (correct silence)
    has fn: int = 0;                 # planted finding missed      (missed alarm)
}

obj EvalReport {
    """The seven metrics collected for one eval run."""
    has fact_survival_naive: int = 0;
    has fact_survival_rem: int = 0;
    has false_positives: int = 0;
    has contradictions_caught: int = 0;
    has decline_caught: bool = False;
    has decline_lead_days: float = 0.0;
    has fall_latency_s: float = 0.0;
    has compression: float = 0.0;
    has alarm_ratio: str = "";
    has confusion: ConfusionMatrix = ConfusionMatrix();
}


# ---------------------------------------------------------------------------
# 1. Fact survival (PRD §12: REM >= 11/12, naive <= 6/12)
# ---------------------------------------------------------------------------

"""Count how many planted must-know fact tags are still present in `survivors`.

Call once with the naive-baseline survivors and once with REM's survivors.
"""
def fact_survival(planted: list[str], survivors: list[str]) -> int {
    keep = set(survivors);
    count = 0;
    for tag in planted {
        if tag in keep {
            count += 1;
        }
    }
    return count;
}


# ---------------------------------------------------------------------------
# 2. False-positive rate (PRD §12: target 0 spurious fires over 40 decoys)
# ---------------------------------------------------------------------------

"""Return the number of spurious fires — the count that matters (target 0).

`decoys` is the planted decoy count, kept so `false_positive_rate` can divide.
"""
def false_positive_count(_decoys: int, spurious_fires: int) -> int {
    return spurious_fires;
}

"""Spurious fires as a fraction of decoys (0.0 when no decoys)."""
def false_positive_rate(decoys: int, spurious_fires: int) -> float {
    if decoys == 0 {
        return 0.0;
    }
    return spurious_fires / decoys;
}


# ---------------------------------------------------------------------------
# 3. Contradiction detection (PRD §12: planted zombies caught, 1/1)
# ---------------------------------------------------------------------------

"""Count how many planted zombie/contradiction tags were caught."""
def contradictions_caught(planted: list[str], caught: list[str]) -> int {
    hit = set(caught);
    n = 0;
    for tag in planted {
        if tag in hit {
            n += 1;
        }
    }
    return n;
}


# ---------------------------------------------------------------------------
# 4. Antecedent decline detection (PRD §12: 1/1, with correct lead time)
# ---------------------------------------------------------------------------

"""Was the decline caught before the fall, and by how many days?

`detected_at`/`fall_at` are epoch seconds. Caught means a real detection
(`detected_at > 0`) that landed at or before the fall. Lead time is reported in
days; it is 0.0 when nothing was detected.
"""
def decline_detection(detected_at: float, fall_at: float) -> DeclineResult {
    if detected_at <= 0.0 or detected_at > fall_at {
        return DeclineResult(caught=False, lead_days=0.0);
    }
    return DeclineResult(caught=True, lead_days=(fall_at - detected_at) / 86400.0);
}


# ---------------------------------------------------------------------------
# 5. Fall response (PRD §12: latency in seconds, no missed / false fall)
# ---------------------------------------------------------------------------

"""Latency in seconds from the fall episode's `at` to the escalation call time."""
def fall_latency(fall_at: float, call_at: float) -> float {
    return call_at - fall_at;
}

"""Graph-driven `at` of the earliest `wearable_fall` episode (0.0 if none).

Lets `fall_latency(graph_fall_at(), call_at)` run straight off the demo graph.
"""
def graph_fall_at -> float {
    earliest = 0.0;
    for ep in [root -->[?:Episode]] {
        if ep.source == "wearable_fall" and (earliest == 0.0 or ep.at < earliest) {
            earliest = ep.at;
        }
    }
    return earliest;
}


# ---------------------------------------------------------------------------
# 6. Compression (PRD §12: ~400 -> ~80 nodes, ~70% token reduction)
# ---------------------------------------------------------------------------

"""Fraction of nodes removed by consolidation: 1 - after/before (0.0 if before==0)."""
def compression_ratio(nodes_before: int, nodes_after: int) -> float {
    if nodes_before == 0 {
        return 0.0;
    }
    return 1.0 - (nodes_after / nodes_before);
}

"""Rough token estimate for a node count (~40 tokens/node), for the ~70% claim."""
def est_tokens(nodes: int) -> int {
    return nodes * 40;
}


# ---------------------------------------------------------------------------
# 7. Alarm ratio (PRD §12: report honestly, e.g. "142 : 3")
# ---------------------------------------------------------------------------

"""Total findings vs tier-3 calls as a human-readable ratio string."""
def alarm_ratio(total_findings: int, tier3_calls: int) -> str {
    return f"{total_findings} : {tier3_calls}";
}


# ---------------------------------------------------------------------------
# Confusion matrix over the fire / no-fire decision
# ---------------------------------------------------------------------------

"""Build the TP/FP/TN/FN matrix from planted (positive) and decoy (negative) fires.

Planted findings are supposed to fire; decoys are supposed to stay silent.
"""
def confusion_matrix(
    planted_fired: int, planted_total: int, decoy_fired: int, decoy_total: int
) -> ConfusionMatrix {
    return ConfusionMatrix(
        tp=planted_fired,
        fn=planted_total - planted_fired,
        fp=decoy_fired,
        tn=decoy_total - decoy_fired
    );
}

"""Print the confusion matrix as a small labelled grid."""
def print_confusion(cm: ConfusionMatrix) {
    print("            fired    silent");
    print(f"  planted    {cm.tp:>3}      {cm.fn:>3}   (TP / FN)");
    print(f"  decoy      {cm.fp:>3}      {cm.tn:>3}   (FP / TN)");
}


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

"""Assemble the seven metrics into one EvalReport and print a summary.

Inputs are plain counts/times so the orchestrator can pass real fixture numbers.
`fall_at`/`call_at` default to a graph read + now() when left at 0.0.
"""
def run_eval(
    planted_facts: list[str],
    naive_survivors: list[str],
    rem_survivors: list[str],
    decoys: int,
    spurious_fires: int,
    planted_zombies: list[str],
    caught_zombies: list[str],
    decline_detected_at: float,
    fall_at: float,
    call_at: float,
    planted_total: int,
    decoy_total: int,
    nodes_before: int,
    nodes_after: int,
    total_findings: int,
    tier3_calls: int
) -> EvalReport {
    when = fall_at if fall_at > 0.0 else graph_fall_at();
    called = call_at if call_at > 0.0 else now();
    decline = decline_detection(decline_detected_at, when);
    cm = confusion_matrix(len(rem_survivors), planted_total, spurious_fires, decoy_total);

    report_obj = EvalReport(
        fact_survival_naive=fact_survival(planted_facts, naive_survivors),
        fact_survival_rem=fact_survival(planted_facts, rem_survivors),
        false_positives=false_positive_count(decoys, spurious_fires),
        contradictions_caught=contradictions_caught(planted_zombies, caught_zombies),
        decline_caught=decline.caught,
        decline_lead_days=decline.lead_days,
        fall_latency_s=fall_latency(when, called),
        compression=compression_ratio(nodes_before, nodes_after),
        alarm_ratio=alarm_ratio(total_findings, tier3_calls),
        confusion=cm
    );

    print("=== REM eval (PRD §12) ===");
    print(f"  fact survival     naive {report_obj.fact_survival_naive} | REM {report_obj.fact_survival_rem} / {len(planted_facts)}");
    print(f"  false positives   {report_obj.false_positives} / {decoys} decoys");
    print(f"  contradictions    {report_obj.contradictions_caught} / {len(planted_zombies)}");
    print(f"  decline caught    {report_obj.decline_caught} (lead {report_obj.decline_lead_days} days)");
    print(f"  fall latency      {report_obj.fall_latency_s} s");
    print(f"  compression       {report_obj.compression} ({nodes_before} -> {nodes_after} nodes)");
    print(f"  alarm ratio       {report_obj.alarm_ratio}");
    print_confusion(cm);
    return report_obj;
}


# ---------------------------------------------------------------------------
# Self-checks — tiny hand-built inputs, no API
# ---------------------------------------------------------------------------

test "fact survival counts planted tags still alive" {
    assert fact_survival(["a", "b", "c"], ["a", "c"]) == 2;
    assert fact_survival(["a", "b", "c"], []) == 0;
    assert fact_survival(["a", "b", "c"], ["a", "b", "c", "z"]) == 3;
}

test "false-positive count is the spurious-fire count; target 0" {
    assert false_positive_count(40, 0) == 0;
    assert false_positive_count(40, 2) == 2;
    assert false_positive_rate(40, 2) == 0.05;
    assert false_positive_rate(0, 0) == 0.0;
}

test "contradiction detection catches planted zombies (1/1)" {
    assert contradictions_caught(["zombie_uti"], ["zombie_uti"]) == 1;
    assert contradictions_caught(["zombie_uti"], []) == 0;
}

test "antecedent decline reports caught + lead time in days" {
    fall = 400000.0;
    detected = fall - (4.0 * 86400.0);          # 4 days before the fall
    d = decline_detection(detected, fall);
    assert d.caught;
    assert d.lead_days == 4.0;
    miss = decline_detection(0.0, fall);         # never detected
    assert not miss.caught;
    assert miss.lead_days == 0.0;
}

test "fall latency is call time minus fall time, in seconds" {
    assert fall_latency(1000.0, 1042.0) == 42.0;
}

test "graph_fall_at reads the earliest wearable_fall episode" {
    root ++> Episode(content="Fall detected, no movement 2 min", source="wearable_fall",
                     author="dev-01", at=2000.0);
    root ++> Episode(content="earlier fall", source="wearable_fall",
                     author="dev-01", at=1500.0);
    root ++> Episode(content="vitals", source="wearable_vitals", author="dev-01", at=100.0);
    assert graph_fall_at() == 1500.0;
    assert fall_latency(graph_fall_at(), 1542.0) == 42.0;
}

test "compression ratio and token estimate" {
    r = compression_ratio(400, 80);
    assert abs(r - 0.8) < 1e-9;
    assert compression_ratio(0, 0) == 0.0;
    assert est_tokens(80) == 3200;
}

test "alarm ratio formats total findings vs tier-3 calls" {
    assert alarm_ratio(142, 3) == "142 : 3";
}

test "confusion matrix splits planted (positive) from decoys (negative)" {
    cm = confusion_matrix(11, 12, 0, 40);
    assert cm.tp == 11;
    assert cm.fn == 1;
    assert cm.fp == 0;
    assert cm.tn == 40;
}

test "run_eval assembles all seven and returns an EvalReport" {
    rep = run_eval(
        planted_facts=["a", "b", "c"],
        naive_survivors=["a"],
        rem_survivors=["a", "b", "c"],
        decoys=40,
        spurious_fires=0,
        planted_zombies=["zombie_uti"],
        caught_zombies=["zombie_uti"],
        decline_detected_at=400000.0 - (4.0 * 86400.0),
        fall_at=400000.0,
        call_at=400042.0,
        planted_total=3,
        decoy_total=40,
        nodes_before=400,
        nodes_after=80,
        total_findings=142,
        tier3_calls=3
    );
    assert rep.fact_survival_naive == 1;
    assert rep.fact_survival_rem == 3;
    assert rep.false_positives == 0;
    assert rep.contradictions_caught == 1;
    assert rep.decline_caught;
    assert rep.decline_lead_days == 4.0;
    assert rep.fall_latency_s == 42.0;
    assert rep.alarm_ratio == "142 : 3";
    assert rep.confusion.tp == 3;
    assert rep.confusion.fn == 0;
    assert rep.confusion.tn == 40;
}
