"""The deterministic tripwire (PRD §7) — a rule engine, never a model.

The LLM does extraction and composition upstream; **decision is pure graph
pattern-matching**. There is deliberately NO `by llm()` anywhere in this file
(handoff-A invariant 4). `fires_*()` are pure predicates over the FLAT graph:
every Clinical / Episode / ActionNode hangs directly off `root`, so every rule is
a 1-hop read plus arithmetic on timestamps.

Six rules (PRD §7.1):
  R1 corroboration      — ≥3 Derived, ≥3 distinct authors, ≥2 shifts, ≤72h, WATCHED
  R2 live contradiction — a suppressed loser still driving a running ActionNode
  R3 unverified drift   — last_asserted − last_verified > 24h on an active belief
  R4 orphaned action    — an ActionNode past due with no Completed edge
  R5 antecedent decline — mobility/sleep trending down ≥3 consecutive days
  R6 fall               — ANY wearable_fall episode → Tier 3, bypasses the clock

Tier (PRD §7.2) is a static lookup; a clock gate drops can-wait findings to 0 at
night — except R6. Firing writes a `Fired` self-loop for suppression (PRD §7.3);
a rule re-opens only when new evidence arrives (a 4th observation), never on a
re-read of the same three.
"""

import from schema {
    Episode, Clinical, ActionNode,
    Derived, Justifies, Contradicts, Completed, Fired,
    Finding, WATCHED, now, hours
}


# ---------------------------------------------------------------------------
# Static severity table (PRD §7.2). This is the ONLY place a rule maps to a
# channel — the entire "142 findings, 3 calls" restraint argument lives here.
#
#   tier 0  next handoff   (default; most findings die here)
#   tier 1  dashboard flag
#   tier 2  push notification
#   tier 3  phone call
#
# ACUTE categories are the three where corroboration/contradiction warrants a
# push-or-call; everything else caps at a dashboard flag.
# ---------------------------------------------------------------------------

glob ACUTE: set[str] = {"respiratory", "cardiac", "infection"};


"""Static tier lookup on (rule, category, time_sensitivity). No graph reads.

  R6                 -> 3 always (a fall is inherently high-severity).
  R1/R2 acute        -> 3 if time-sensitive else 2 (call vs push).
  R1/R2 non-acute    -> 1 (dashboard).
  R3 acute/non-acute -> 2 / 1 (copy-forward zombie on an active drug).
  R4 orphaned action -> 1 (dropped follow-up).
  R5 decline         -> 1 (slow burn; the dashboard is where it belongs).
  anything else      -> 0 (handoff).
"""
def tier_for(rule: str, category: str, time_sensitive: bool) -> int {
    if rule == "R6" {
        return 3;
    }
    if rule == "R1" or rule == "R2" {
        if category in ACUTE {
            return 3 if time_sensitive else 2;
        }
        return 1;
    }
    if rule == "R3" {
        return 2 if category in ACUTE else 1;
    }
    if rule == "R4" {
        return 1;
    }
    if rule == "R5" {
        return 1;
    }
    return 0;
}


"""True when `now_ref` lands in the quiet hours 00:00–06:59."""
def is_night(now_ref: float) -> bool {
    hour = int((now_ref % 86400.0) // 3600.0);
    return hour >= 0 and hour <= 6;
}


"""Apply the clock gate to a base tier (PRD §7.2).

A finding that can wait for the next handoff (`not time_sensitive`) is dropped to
tier 0 during the quiet hours — do not wake anyone for a review item at 3 AM. R6
is the deliberate exception: a fall bypasses the gate entirely (invariant 6).
"""
def gate(rule: str, time_sensitive: bool, base_tier: int, now_ref: float) -> int {
    if rule == "R6" {
        return base_tier;
    }
    if (not time_sensitive) and is_night(now_ref) {
        return 0;
    }
    return base_tier;
}


# ---------------------------------------------------------------------------
# Pure graph helpers over a Clinical's Derived provenance set.
# ---------------------------------------------------------------------------

"""Distinct author/device count across a Clinical's Derived episodes."""
def distinct_authors(c: Clinical) -> int {
    authors = [ep.author for ep in [c ->:Derived:->]];
    return len(set(authors));
}


"""Span in hours between the earliest and latest Derived episode."""
def span_hours(c: Clinical) -> float {
    times = [ep.at for ep in [c ->:Derived:->]];
    if len(times) == 0 {
        return 0.0;
    }
    return hours(max(times) - min(times));
}


"""Shift bucket for a timestamp: day index + day/night tag.

Day index = floor(at / 86400). Night = hour < 7 or hour >= 19. Two episodes
share a bucket only if they fall on the same calendar day AND the same shift, so
counting distinct buckets counts distinct shifts.
"""
def shift_bucket(at: float) -> str {
    day = int(at // 86400.0);
    hour = int((at % 86400.0) // 3600.0);
    tag = "N" if (hour < 7 or hour >= 19) else "D";
    return str(day) + "-" + tag;
}


"""Distinct (day, shift) buckets across a Clinical's Derived episodes."""
def distinct_shifts(c: Clinical) -> int {
    buckets = [shift_bucket(ep.at) for ep in [c ->:Derived:->]];
    return len(set(buckets));
}


"""True when SOME ≤`window_h` sliding sub-window over the Clinical's Derived
episodes holds ≥`min_authors` distinct authors spanning ≥`min_shifts` shifts.

A slowly-accreting belief (real desat data: overnight manual desats on D1–D3 plus
wearable readings out to D5) can span far more than 72h end-to-end yet still carry
a tight cross-shift corroboration cluster inside it. Requiring the ENTIRE Derived
set within 72h misses that cluster; this scans every 72h window instead. Episodes
are sorted by `at`; for each window start we extend forward while within the span
and count distinct authors + shifts, firing on the first window that qualifies.
"""
def has_corroborating_window(c: Clinical, window_h: float,
                             min_authors: int, min_shifts: int) -> bool {
    rows = sorted([(ep.at, ep.author, shift_bucket(ep.at))
                   for ep in [c ->:Derived:->]]);
    if len(rows) < min_authors {
        return False;
    }
    span = window_h * 3600.0;
    n = len(rows);
    i = 0;
    while i < n {
        authors: set[str] = set();
        shifts: set[str] = set();
        j = i;
        while j < n and rows[j][0] - rows[i][0] <= span {
            authors.add(rows[j][1]);
            shifts.add(rows[j][2]);
            j += 1;
        }
        if len(authors) >= min_authors and len(shifts) >= min_shifts {
            return True;
        }
        i += 1;
    }
    return False;
}


"""An ActionNode is 'running' when it carries no Completed self-loop."""
def is_active_action(a: ActionNode) -> bool {
    return len([a ->:Completed:->]) == 0;
}


"""True when a Clinical justifies at least one still-running ActionNode."""
def has_active_intervention(c: Clinical) -> bool {
    for a in [c ->:Justifies:->] {
        if is_active_action(a) {
            return True;
        }
    }
    return False;
}


"""Suppression check (PRD §7.3).

A Clinical is 'recently fired' when it already carries a Fired edge AND no Derived
episode is newer than that edge's `at`. A 4th observation (an episode timestamped
after the fire) re-opens the rule; re-reading the same three does not.
"""
def recently_fired(c: Clinical) -> bool {
    fired_edges = [edge c ->:Fired:->];
    if len(fired_edges) == 0 {
        return False;
    }
    latest = max([e.at for e in fired_edges]);
    for ep in [c ->:Derived:->] {
        if ep.at > latest {
            return False;
        }
    }
    return True;
}


"""Write the Fired self-loop that suppresses re-firing until new evidence."""
def fire_clinical(c: Clinical, rule: str, tier: int, now_ref: float) {
    c +>:Fired(at=now_ref, rule=rule, tier=tier):+> c;
}


"""First numeric token in an episode's text content, as a float.

DETERMINISTIC parse, NOT a model: strip commas, then take the first run of digits
(with a single embedded decimal point). "5,000 steps" -> 5000.0, "6.5 hours" ->
6.5. Returns -1.0 when no number is present.
"""
def metric_value(content: str) -> float {
    cleaned = content.replace(",", "");
    number = "";
    seen_dot = False;
    for ch in cleaned {
        if ch.isdigit() {
            number += ch;
        } elif ch == "." and len(number) > 0 and not seen_dot {
            number += ch;
            seen_dot = True;
        } elif len(number) > 0 {
            break;
        }
    }
    if len(number) > 0 and number != "." {
        return float(number);
    }
    return -1.0;
}


"""True when there is a run of ≥3 consecutive calendar days each strictly below
the previous (2 decrements over 3 days). An isolated low day never qualifies."""
def has_decline(days: list[int], vals: list[float]) -> bool {
    run = 1;
    i = 1;
    while i < len(days) {
        if days[i] == days[i - 1] + 1 and vals[i] < vals[i - 1] {
            run += 1;
            if run >= 3 {
                return True;
            }
        } else {
            run = 1;
        }
        i += 1;
    }
    return False;
}


# ---------------------------------------------------------------------------
# Rule predicates — each a pure boolean over the graph.
# ---------------------------------------------------------------------------

"""R1: corroborated cross-shift pattern in a watched category (PRD §7.1).

Corroboration is judged over a 72h SLIDING window, not the belief's full lifespan:
a belief that accretes evidence over many days still fires the moment any 72h slice
of it carries ≥3 distinct authors across ≥2 shifts.
"""
def fires_r1(c: Clinical) -> bool {
    return not c.suppressed          # a superseded loser doesn't corroborate; see R2
        and len([c ->:Derived:->]) >= 3
        and c.category in WATCHED
        and not recently_fired(c)
        and has_corroborating_window(c, 72.0, 3, 2);
}


"""R2: `c` is the losing (suppressed) side of a Contradicts edge yet still drives
a running intervention — the ruled-out belief keeping a drug going."""
def fires_r2(c: Clinical) -> bool {
    if not c.suppressed {
        return False;
    }
    on_contradiction = len([c <-:Contradicts:<-]) > 0
        or len([c ->:Contradicts:->]) > 0;
    return on_contradiction
        and has_active_intervention(c)
        and not recently_fired(c);
}


"""R3: unverified drift — asserted well after last verification, still driving an
active intervention (the copy-forward zombie)."""
def fires_r3(c: Clinical) -> bool {
    drift = hours(c.last_asserted - c.last_verified) > 24.0;
    return not c.suppressed          # the live side drifts; the loser is R2's concern
        and drift
        and has_active_intervention(c)
        and not recently_fired(c);
}


# ---------------------------------------------------------------------------
# Rule evaluators — one Finding per hit; write Fired edges for Clinical-subject
# rules (R1–R3) that clear their tier gate.
# ---------------------------------------------------------------------------

def eval_r1(now_ref: float) -> list[Finding] {
    out: list[Finding] = [];
    for c in [root -->[?:Clinical]] {
        if not fires_r1(c) {
            continue;
        }
        # Time-sensitive when the corroboration is not just present but TIGHT: a
        # ≥3-author / ≥2-shift cluster inside a single 48h window (call vs push).
        time_sensitive = has_corroborating_window(c, 48.0, 3, 2);
        base = tier_for("R1", c.category, time_sensitive);
        t = gate("R1", time_sensitive, base, now_ref);
        if t > 0 {
            fire_clinical(c, "R1", t, now_ref);
        }
        ev = [ep.source + " by " + ep.author + ": " + ep.content
              for ep in [c ->:Derived:->]];
        out.append(Finding(rule="R1", claim=c.claim, category=c.category,
                           tier=t, fired=(t > 0), evidence=ev, claim_id=jid(c)));
    }
    return out;
}


def eval_r2(now_ref: float) -> list[Finding] {
    out: list[Finding] = [];
    for c in [root -->[?:Clinical]] {
        if not fires_r2(c) {
            continue;
        }
        time_sensitive = True;
        base = tier_for("R2", c.category, time_sensitive);
        t = gate("R2", time_sensitive, base, now_ref);
        if t > 0 {
            fire_clinical(c, "R2", t, now_ref);
        }
        ev = ["active task: " + a.task
              for a in [c ->:Justifies:->] if is_active_action(a)];
        out.append(Finding(rule="R2", claim=c.claim, category=c.category,
                           tier=t, fired=(t > 0), evidence=ev, claim_id=jid(c)));
    }
    return out;
}


def eval_r3(now_ref: float) -> list[Finding] {
    out: list[Finding] = [];
    for c in [root -->[?:Clinical]] {
        if not fires_r3(c) {
            continue;
        }
        time_sensitive = False;
        base = tier_for("R3", c.category, time_sensitive);
        t = gate("R3", time_sensitive, base, now_ref);
        if t > 0 {
            fire_clinical(c, "R3", t, now_ref);
        }
        ev = ["asserted " + str(hours(c.last_asserted - c.last_verified))
              + "h after last verification"];
        out.append(Finding(rule="R3", claim=c.claim, category=c.category,
                           tier=t, fired=(t > 0), evidence=ev, claim_id=jid(c)));
    }
    return out;
}


def eval_r4(now_ref: float) -> list[Finding] {
    out: list[Finding] = [];
    for a in [root -->[?:ActionNode]] {
        overdue = a.due > 0.0 and a.due < now_ref;
        if not overdue {
            continue;
        }
        if len([a ->:Completed:->]) > 0 {
            continue;
        }
        owners = [c for c in [root -->[?:Clinical]] if a in [c ->:Justifies:->]];
        cat = owners[0].category if len(owners) > 0 else "";
        cid = jid(owners[0]) if len(owners) > 0 else jid(a);
        time_sensitive = False;
        base = tier_for("R4", cat, time_sensitive);
        t = gate("R4", time_sensitive, base, now_ref);
        out.append(Finding(rule="R4", claim="overdue task: " + a.task,
                           category=cat, tier=t, fired=(t > 0),
                           evidence=["owner " + a.owner + ", due " + str(a.due)],
                           claim_id=cid));
    }
    return out;
}


def eval_r5(now_ref: float) -> list[Finding] {
    out: list[Finding] = [];
    for src in ["wearable_mobility", "wearable_sleep"] {
        eps = [ep for ep in [root -->[?:Episode]] if ep.source == src];
        day_map: dict[int, list[float]] = {};
        for ep in eps {
            d = int(ep.at // 86400.0);
            if d not in day_map {
                day_map[d] = [];
            }
            day_map[d].append(metric_value(ep.content));
        }
        days_sorted = sorted(day_map.keys());
        day_list: list[int] = [];
        val_list: list[float] = [];
        for d in days_sorted {
            vals = day_map[d];
            day_list.append(d);
            val_list.append(sum(vals) / len(vals));
        }
        if not has_decline(day_list, val_list) {
            continue;
        }
        cat = "mobility" if src == "wearable_mobility" else "sleep";
        if cat not in WATCHED {
            continue;
        }
        time_sensitive = False;
        base = tier_for("R5", cat, time_sensitive);
        t = gate("R5", time_sensitive, base, now_ref);
        ev = ["day " + str(day_list[k]) + ": " + str(val_list[k])
              for k in range(len(day_list))];
        out.append(Finding(rule="R5",
                           claim=cat + " declining over " + str(len(day_list)) + " days",
                           category=cat, tier=t, fired=(t > 0),
                           evidence=ev, claim_id=jid(eps[0])));
    }
    return out;
}


def eval_r6(now_ref: float) -> list[Finding] {
    out: list[Finding] = [];
    falls = [ep for ep in [root -->[?:Episode]] if ep.source == "wearable_fall"];
    for ep in falls {
        # R6 is the deliberate exception (invariant 6): straight to Tier 3, and
        # the clock gate is bypassed, so 3 AM does not de-escalate it.
        base = tier_for("R6", "fall", True);
        t = gate("R6", True, base, now_ref);
        out.append(Finding(rule="R6", claim="fall detected: " + ep.content,
                           category="fall", tier=t, fired=True,
                           evidence=[ep.source + " by " + ep.author + ": " + ep.content],
                           claim_id=jid(ep)));
    }
    return out;
}


# ---------------------------------------------------------------------------
# The walker: evaluate every rule, persist Fired edges, report one Finding each.
# ---------------------------------------------------------------------------

walker:pub Tripwire {
    """Deterministic tripwire. `now_ref` (default 0.0 -> now()) pins the clock so
    tests can drive the night gate; `reports` carries one Finding per rule hit."""
    has now_ref: float = 0.0;
    has reports: list[Finding] = [];

    can run with Root entry {
        nr = self.now_ref if self.now_ref != 0.0 else now();
        self.now_ref = nr;
        findings: list[Finding] = [];
        findings += eval_r1(nr);
        findings += eval_r2(nr);
        findings += eval_r3(nr);
        findings += eval_r4(nr);
        findings += eval_r5(nr);
        findings += eval_r6(nr);
        for hit in findings {
            report hit;
        }
    }
}


# ---------------------------------------------------------------------------
# Self-checks (NO LLM). Minimal inline graphs; the clock is pinned via now_ref.
# Assertions filter reports by claim_id / rule so tests stay independent even
# though jac's test root is shared. R5 decoy is declared BEFORE the R5 positive
# case so no declining data exists when the decoy runs.
# ---------------------------------------------------------------------------

test "R1 fires on a 3-author cross-shift desaturation cluster" {
    d = 100.0;
    c = root ++> Clinical(claim="R1P spo2 drifting", category="respiratory",
        last_asserted=d * 86400.0, last_verified=d * 86400.0, subject="R1P");
    e1 = root ++> Episode(content="spo2 88", source="wearable_vitals",
        author="dev-1", at=d * 86400.0 + 8.0 * 3600.0, subject="R1P");
    e2 = root ++> Episode(content="spo2 87", source="nursing_note",
        author="RN Maya", at=d * 86400.0 + 20.0 * 3600.0, subject="R1P");
    e3 = root ++> Episode(content="spo2 86", source="vitals_manual",
        author="RN Sam", at=(d + 1.0) * 86400.0 + 9.0 * 3600.0, subject="R1P");
    c +>:Derived():+> e1;
    c +>:Derived():+> e2;
    c +>:Derived():+> e3;
    nr = (d + 1.0) * 86400.0 + 12.0 * 3600.0;   # noon: not the night gate
    res = root spawn Tripwire(now_ref=nr);
    mine = [h for h in res.reports if h.rule == "R1" and h.claim_id == jid(c)];
    assert len(mine) == 1;
    assert mine[0].fired;
    assert mine[0].tier >= 2;
}


test "R1 does not fire with only 2 distinct authors" {
    d = 110.0;
    c = root ++> Clinical(claim="R1N spo2 drifting", category="respiratory",
        last_asserted=d * 86400.0, last_verified=d * 86400.0, subject="R1N");
    e1 = root ++> Episode(content="spo2 88", source="wearable_vitals",
        author="dev-9", at=d * 86400.0 + 8.0 * 3600.0, subject="R1N");
    e2 = root ++> Episode(content="spo2 87", source="nursing_note",
        author="dev-9", at=d * 86400.0 + 20.0 * 3600.0, subject="R1N");
    e3 = root ++> Episode(content="spo2 86", source="vitals_manual",
        author="RN Kim", at=(d + 1.0) * 86400.0 + 9.0 * 3600.0, subject="R1N");
    c +>:Derived():+> e1;
    c +>:Derived():+> e2;
    c +>:Derived():+> e3;
    nr = (d + 1.0) * 86400.0 + 12.0 * 3600.0;
    res = root spawn Tripwire(now_ref=nr);
    mine = [h for h in res.reports if h.rule == "R1" and h.claim_id == jid(c)];
    assert len(mine) == 0;
}


test "R5 does not fire on a single low-step outing day" {
    d = 200.0;
    root ++> Episode(content="500 steps", source="wearable_mobility",
        author="dev-band", at=d * 86400.0 + 10.0 * 3600.0, subject="R5decoy");
    nr = d * 86400.0 + 12.0 * 3600.0;
    res = root spawn Tripwire(now_ref=nr);
    mine = [h for h in res.reports if h.rule == "R5"];
    assert len(mine) == 0;
}


test "R5 fires on a 4-consecutive-day mobility decline" {
    vals = [5000, 4000, 3000, 2000];
    base = 100;
    for i in range(4) {
        day = float(base + i);
        root ++> Episode(content=str(vals[i]) + " steps",
            source="wearable_mobility", author="dev-band",
            at=day * 86400.0 + 10.0 * 3600.0, subject="R5pos");
    }
    nr = 103.0 * 86400.0 + 12.0 * 3600.0;
    res = root spawn Tripwire(now_ref=nr);
    mine = [h for h in res.reports if h.rule == "R5" and h.category == "mobility"];
    assert len(mine) >= 1;
    assert mine[0].fired;
    assert mine[0].tier >= 1;
}


test "R6 fires a lone fall to Tier 3 even at 3 AM" {
    d = 300.0;
    ep = root ++> Episode(content="impact detected", source="wearable_fall",
        author="dev-band", at=d * 86400.0 + 3.0 * 3600.0, subject="R6");
    nr = d * 86400.0 + 3.0 * 3600.0;   # 03:00 — the night gate would zero anything else
    res = root spawn Tripwire(now_ref=nr);
    mine = [h for h in res.reports if h.rule == "R6" and h.claim_id == jid(ep)];
    assert len(mine) == 1;
    assert mine[0].tier == 3;
    assert mine[0].fired;
}


test "firing the same finding twice writes exactly one Fired edge" {
    d = 400.0;
    c = root ++> Clinical(claim="R1twice hr climbing", category="cardiac",
        last_asserted=d * 86400.0, last_verified=d * 86400.0, subject="twice");
    e1 = root ++> Episode(content="hr 130", source="wearable_vitals",
        author="dev-a", at=d * 86400.0 + 8.0 * 3600.0, subject="twice");
    e2 = root ++> Episode(content="hr 128", source="nursing_note",
        author="RN X", at=d * 86400.0 + 20.0 * 3600.0, subject="twice");
    e3 = root ++> Episode(content="hr 132", source="vitals_manual",
        author="RN Y", at=(d + 1.0) * 86400.0 + 9.0 * 3600.0, subject="twice");
    c +>:Derived():+> e1;
    c +>:Derived():+> e2;
    c +>:Derived():+> e3;
    nr = (d + 1.0) * 86400.0 + 12.0 * 3600.0;
    root spawn Tripwire(now_ref=nr);
    root spawn Tripwire(now_ref=nr);
    edges = [edge c ->:Fired:->];
    assert len(edges) == 1;
}
