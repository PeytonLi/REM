"""Manual (non-device) episode fixture for the REM demo graph.

Device-sourced episodes come from seed/device.py. This file owns everything a
human charted: nursing notes, manual vitals, MAR entries, labs, family reports.

Emits:
  seed/patient.json   - bare list[Episode], the shape Person A consumes
  seed/expected.json  - ground truth for eval (planted ids, decoys, causal chain)

Run:
  python seed/gen.py
  python seed/gen.py --self-check
"""

import argparse
import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

SEED = 7
OUT_DIR = Path(__file__).parent
BASE = datetime(2026, 3, 2, 0, 0, tzinfo=timezone.utc)  # day 1 == Mar 2

RESIDENT = "Ruth Alvarez, 82F, Room 3B"

# Night RN rotates so the three desaturations get three distinct human observers.
# See NOTE-R1 at the bottom of this file.
NIGHT_RN = {
    1: "RN Dev Patel",
    2: "RN Priya Shah",
    3: "RN Alan Whitfield",
    4: "RN Dev Patel",
    5: "RN Priya Shah",
}
DAY_RN = {
    1: "RN Maya Ortiz",
    2: "RN Maya Ortiz",
    3: "RN Grace Chen",
    4: "RN Maya Ortiz",
    5: "RN Grace Chen",
}
DAY_CNA = {1: "CNA Ruben Diaz", 2: "CNA Ruben Diaz", 3: "CNA Alice Nkemdi",
           4: "CNA Ruben Diaz", 5: "CNA Alice Nkemdi"}
NIGHT_CNA = {1: "CNA Tomas Reyes", 2: "CNA Tomas Reyes", 3: "CNA Joy Abara",
             4: "CNA Tomas Reyes", 5: "CNA Joy Abara"}


def ts(day, hour, minute=0):
    """Epoch seconds for day N (1-indexed) at HH:MM."""
    return (BASE + timedelta(days=day - 1, hours=hour, minutes=minute)).timestamp()


def shift_of(t):
    """Shift label. Night shift belongs to the calendar day it STARTED."""
    dt = datetime.fromtimestamp(t, timezone.utc)
    day = (dt - BASE).days + 1
    if 7 <= dt.hour < 19:
        return f"D{day}-day"
    if dt.hour < 7:
        return f"D{day - 1}-night"
    return f"D{day}-night"


def ep(eid, content, source, author, at, tag, note=None):
    e = {
        "id": eid,
        "content": content,
        "source": source,
        "author": author,
        "at": at,
        "shift": shift_of(at),
        "tag": tag,  # planted | noise | decoy | filler
    }
    if note:
        e["note"] = note  # why this decoy must not fire; eval reads this
    return e


# ---------------------------------------------------------------------------
# Planted findings 1 & 2 (PRD 11.2): the rash-switch chain and the UTI zombie.
# One clinical story carries both: suspected UTI -> ceftriaxone -> rash ->
# switch to levofloxacin -> culture negative -> levofloxacin still running D5.
# ---------------------------------------------------------------------------

def planted_abx():
    return [
        ep("P-UTI-SUSPECT",
           "Resident febrile 38.4 C, new-onset confusion and urinary urgency. "
           "Suspected UTI. Urine culture sent, empiric ceftriaxone ordered by on-call MD.",
           "nursing_note", DAY_RN[1], ts(1, 9, 15), "planted"),
        ep("P-ABX-START",
           "Ceftriaxone 1 g IV administered, first dose.",
           "mar", DAY_RN[1], ts(1, 10, 0), "planted"),
        ep("P-RASH",
           "New maculopapular rash across chest and both forearms, roughly 6 hours after "
           "the first ceftriaxone dose. No respiratory involvement, no facial swelling. MD notified.",
           "nursing_note", "LPN Grace Chen", ts(1, 16, 40), "planted"),
        ep("P-ABX-SWITCH",
           "Ceftriaxone discontinued per MD due to suspected drug rash. "
           "Levofloxacin 500 mg PO started in its place.",
           "mar", DAY_RN[1], ts(1, 18, 20), "planted"),
        ep("P-RASH-FOLLOWUP",
           "Rash unchanged overnight, no spread. Resident denies itching. "
           "No further ceftriaxone given.",
           "nursing_note", NIGHT_RN[1], ts(1, 23, 30), "planted"),
        ep("P-CULTURE-NEG",
           "Urine culture final result: no growth at 48 hours. Negative.",
           "lab", "Lab - Central Processing", ts(3, 11, 5), "planted"),
    ]


def zombie_tail():
    """Copy-forward notes days 3-5: 'on levofloxacin for suspected UTI', why is gone."""
    out = []
    for d in (3, 4, 5):
        out.append(ep(
            f"P-ZOMBIE-D{d}",
            "Continues on levofloxacin for suspected UTI. Afebrile, no urinary complaints.",
            "nursing_note", DAY_RN[d], ts(d, 8, 30), "planted"))
        for hour in (9, 21):
            out.append(ep(
                f"P-MAR-LEVO-D{d}-{hour}",
                "Levofloxacin 500 mg PO administered.",
                "mar", DAY_RN[d] if hour < 19 else NIGHT_RN[d], ts(d, hour, 0), "planted"))
    return out


def desat_corroboration():
    """One human spot-check per desaturation night, each by a different RN.

    The wearable logs all three (seed/device.py). These give R1 the distinct
    human observers the rule requires -- see NOTE-R1.
    """
    events = [(1, 2, 15, 88), (2, 1, 50, 86), (3, 3, 25, 84)]
    out = []
    for i, (day, hour, minute, spo2) in enumerate(events, start=1):
        # 0X:YY on the calendar morning after `day` belongs to D{day}-night
        at = ts(day + 1, hour, minute)
        out.append(ep(
            f"P-DESAT-N{i}-NOTE",
            f"Spot-check SpO2 {spo2}% on room air during rounds, resident asleep. "
            "Repositioned and encouraged deep breaths, improved. Will continue to monitor.",
            "vitals_manual", NIGHT_RN[day], at, "planted"))
    return out


# ---------------------------------------------------------------------------
# Noise (PRD 11.2 #6): ~40 near-identical ADL notes. Tests pruning.
# ---------------------------------------------------------------------------

ADL_TEMPLATES = [
    "Assisted with ADLs, tolerated well.",
    "Ambulated in hallway with standby assist, steady gait.",
    "Assisted to bathroom, no incontinence episode.",
    "Bed bath given, skin intact, no new areas of concern.",
    "Repositioned in bed for comfort, call light within reach.",
    "Assisted with oral care, no complaints.",
    "Up to chair for meal, tolerated sitting 40 minutes.",
    "Ambulated to dining room with front-wheeled walker, standby assist.",
]


def noise(rng, n=40):
    out = []
    for i in range(n):
        day = rng.randint(1, 5)
        hour = rng.choice([8, 10, 11, 13, 15, 17, 20, 22])
        author = DAY_CNA[day] if 7 <= hour < 19 else NIGHT_CNA[day]
        out.append(ep(f"N-{i:03d}", rng.choice(ADL_TEMPLATES), "nursing_note",
                      author, ts(day, hour, rng.randint(0, 59)), "noise"))
    return out


# ---------------------------------------------------------------------------
# Decoys (PRD 11.2): must NOT fire R1-R6. Each carries `note` explaining why.
# ---------------------------------------------------------------------------

def decoys(rng):
    out = []

    # R1 near-miss: same subject, only TWO distinct observers (rule needs >=3).
    two_observer = [
        ("mild pitting edema in right ankle", 2),
        ("intermittent dry cough after meals", 3),
        ("reduced appetite at breakfast", 4),
        ("complaint of mild lower back stiffness", 2),
    ]
    for c, (subject, day) in enumerate(two_observer):
        for j, author in enumerate((DAY_RN[day], "LPN Grace Chen")):
            out.append(ep(
                f"X-R1-{c}-{j}",
                f"Noted {subject}. Monitored, no intervention required.",
                "nursing_note", author, ts(day, 9 + j * 5, 20), "decoy",
                note="R1 near-miss: only 2 distinct observers, rule requires >=3"))

    # R2 near-miss: a contradiction that lands on an order already discontinued.
    out.append(ep("X-R2-ORDER", "Vitamin K 5 mg PO ordered daily for low INR.",
                  "mar", DAY_RN[1], ts(1, 14, 0), "decoy",
                  note="R2 near-miss: order below is DC'd before the contradiction"))
    out.append(ep("X-R2-DC", "Vitamin K discontinued per MD, INR now therapeutic.",
                  "mar", DAY_RN[2], ts(2, 15, 30), "decoy",
                  note="R2 near-miss: order inactive from here on"))
    out.append(ep("X-R2-CONTRA", "Repeat INR 2.4, within therapeutic range. "
                                 "Earlier low-INR concern resolved.",
                  "lab", "Lab - Central Processing", ts(4, 10, 15), "decoy",
                  note="R2 near-miss: contradicts an INACTIVE order, no live Justifies"))

    # R3 near-miss: a stale claim that justifies no active intervention.
    out.append(ep("X-R3-CLAIM", "Resident reports occasional dry mouth. "
                                "No treatment ordered, comfort measures only.",
                  "nursing_note", DAY_RN[1], ts(1, 12, 45), "decoy",
                  note="R3 near-miss: stale >24h but justifies no active intervention"))
    out.append(ep("X-R3-ECHO", "Dry mouth mentioned again, still no order in place.",
                  "nursing_note", DAY_RN[4], ts(4, 12, 50), "decoy",
                  note="R3 near-miss: still justifies nothing"))

    # R4 near-miss: actions completed, just barely late. Rule needs past-due AND uncompleted.
    for k in range(5):
        day = 2 + (k % 3)
        due = ts(day, 14, 0)
        out.append(ep(f"X-R4-DUE-{k}", f"Repositioning check due at 14:00 (task {k}).",
                      "nursing_note", DAY_CNA[day], due - 3600, "decoy",
                      note="R4 near-miss: paired completion exists, 1 minute late"))
        out.append(ep(f"X-R4-DONE-{k}", f"Repositioning check completed (task {k}).",
                      "nursing_note", DAY_CNA[day], due + 60, "decoy",
                      note="R4 near-miss: completed 1 min past due, still completed"))

    # Assorted single-observer oddities: nothing to corroborate, nothing to contradict.
    singles = [
        "Resident declined evening snack, stated not hungry.",
        "Family called to check in, no concerns raised.",
        "Reading glasses misplaced, located in dayroom.",
        "Requested extra blanket overnight.",
        "Hearing aid battery replaced.",
        "Declined group activity, preferred to rest.",
        "Nail care performed by podiatry.",
        "Room temperature adjusted at resident request.",
        "Denture soak completed.",
        "Preferred left side-lying position noted.",
        "Watched television in dayroom for 1 hour.",
        "Complained the dinner tray was cold, replaced.",
        "Asked what day of the week it was, reoriented without difficulty.",
        "Slippers replaced with non-skid pair per fall-prevention policy.",
        "Visited by facility chaplain at own request.",
    ]
    for i, text in enumerate(singles):
        day = rng.randint(1, 5)
        hour = rng.choice([9, 12, 16, 19, 21])
        author = DAY_RN[day] if 7 <= hour < 19 else NIGHT_RN[day]
        out.append(ep(f"X-SINGLE-{i:02d}", text, "nursing_note", author,
                      ts(day, hour, rng.randint(0, 59)), "decoy",
                      note="single observer, no pattern to corroborate"))
    return out


# ---------------------------------------------------------------------------
# Filler: routine charting that makes the 400-episode volume real.
# ---------------------------------------------------------------------------

def filler(rng, target):
    out = []
    i = 0
    for day in range(1, 6):
        for hour in (0, 4, 8, 12, 16, 20):
            if day == 1 and hour < 7:
                continue  # resident is not admitted until D1 09:15
            author = DAY_RN[day] if 7 <= hour < 19 else NIGHT_RN[day]
            bp_s, bp_d = rng.randint(112, 138), rng.randint(62, 82)
            out.append(ep(f"F-VS-{i:03d}",
                          f"Vitals: BP {bp_s}/{bp_d}, HR {rng.randint(66, 88)}, "
                          f"RR {rng.randint(14, 19)}, T {round(rng.uniform(36.4, 37.2), 1)} C, "
                          f"SpO2 {rng.randint(94, 98)}% on room air.",
                          "vitals_manual", author, ts(day, hour, rng.randint(0, 30)), "filler"))
            i += 1

    routine_meds = ["Lisinopril 10 mg PO", "Atorvastatin 20 mg PO", "Acetaminophen 650 mg PO",
                    "Vitamin D 1000 IU PO", "Docusate 100 mg PO", "Pantoprazole 40 mg PO"]
    for day in range(1, 6):
        for hour in (9, 13, 21):
            for med in rng.sample(routine_meds, 3):
                author = DAY_RN[day] if 7 <= hour < 19 else NIGHT_RN[day]
                out.append(ep(f"F-MAR-{i:03d}", f"{med} administered.", "mar",
                              author, ts(day, hour, rng.randint(0, 45)), "filler"))
                i += 1

    obs = [
        "Oriented to person and place, mild confusion about date.",
        "Skin assessment: no breakdown, heels floated.",
        "Intake 60% of meal, encouraged fluids.",
        "Voided clear yellow urine, no odor.",
        "Bowel movement recorded, formed.",
        "Denies pain at rest, rates 2/10 with movement.",
        "Slept in intervals, awake briefly at rounds.",
        "Participated in bedside range-of-motion exercises.",
    ]
    family = [
        "Daughter visited, brought photographs, resident engaged.",
        "Son called, asked about appetite and sleep.",
        "Family reports resident seemed more tired than usual on their last visit.",
        "Niece visited briefly after dinner.",
    ]
    while len(out) < target:
        day = rng.randint(1, 5)
        hour = rng.randint(7, 22)
        if rng.random() < 0.08:
            src, text, author = "family", rng.choice(family), "Family - daughter"
        else:
            src = "nursing_note"
            text = rng.choice(obs)
            author = DAY_RN[day] if 7 <= hour < 19 else NIGHT_CNA[day]
        out.append(ep(f"F-OBS-{i:03d}", text, src, author,
                      ts(day, hour, rng.randint(0, 59)), "filler"))
        i += 1
    return out


def build():
    rng = random.Random(SEED)
    eps = planted_abx() + zombie_tail() + desat_corroboration()
    eps += noise(rng)
    eps += decoys(rng)
    eps += filler(rng, target=400 - len(eps))
    eps.sort(key=lambda e: e["at"])
    return eps


EXPECTED = {
    "resident": RESIDENT,
    "window_days": 5,
    "causal_chain": [
        # Person A wires these as Causes edges. Order is cause -> effect.
        ["P-ABX-START", "P-RASH"],
        ["P-RASH", "P-ABX-SWITCH"],
    ],
    "should_fire": {
        "R1": "three overnight desaturations, 3 distinct RNs + wearable, 3 shifts",
        "R2": "P-CULTURE-NEG contradicts suspected-UTI while levofloxacin still running D5",
        "R5": "4-day mobility/sleep decline (seed/device.py)",
        "R6": "single wearable_fall episode (seed/device.py)",
    },
    "must_survive_to_shift_6": ["P-RASH", "P-ABX-SWITCH", "P-CULTURE-NEG"],
}


def self_check(eps):
    by_id = {e["id"]: e for e in eps}
    tag = lambda t: [e for e in eps if e["tag"] == t]

    assert len(eps) == 400, f"expected 400 episodes, got {len(eps)}"
    assert len(tag("decoy")) >= 38, f"need ~40 decoys, got {len(tag('decoy'))}"
    assert len(tag("noise")) == 40

    # Planted causal chain is intact and correctly ordered in time.
    for cause, effect in EXPECTED["causal_chain"]:
        assert by_id[cause]["at"] < by_id[effect]["at"], f"{cause} must precede {effect}"

    # The rash reason exists exactly once, in the note the naive baseline drops.
    assert "ceftriaxone" in by_id["P-RASH"]["content"].lower()
    assert "rash" in by_id["P-ABX-SWITCH"]["content"].lower()

    # UTI zombie: culture negative D3, antibiotic still administered D5.
    assert by_id["P-CULTURE-NEG"]["at"] < by_id["P-MAR-LEVO-D5-9"]["at"]

    # R1 fuel: three human desat notes, three distinct authors, three shifts.
    desat = [by_id[f"P-DESAT-N{i}-NOTE"] for i in (1, 2, 3)]
    assert len({d["author"] for d in desat}) == 3, "desat notes need 3 distinct RNs"
    assert len({d["shift"] for d in desat}) == 3, "desat notes must span 3 shifts"
    assert all(d["shift"].endswith("-night") for d in desat)

    # No decoy cluster reaches R1's >=3 distinct authors on a shared subject.
    for c in range(4):
        grp = [e for e in eps if e["id"].startswith(f"X-R1-{c}-")]
        assert len({e["author"] for e in grp}) == 2, "R1 decoy must stay at 2 observers"

    # Every R4 decoy has its completion, so none is an orphaned action.
    dues = {e["id"].rsplit("-", 1)[1] for e in eps if e["id"].startswith("X-R4-DUE-")}
    dones = {e["id"].rsplit("-", 1)[1] for e in eps if e["id"].startswith("X-R4-DONE-")}
    assert dues == dones, "every R4 decoy needs a paired completion"

    # No manual episode claims a wearable source -- that is device.py's job.
    assert not [e for e in eps if e["source"].startswith("wearable")]

    # Ten real shifts, D1-day through D5-night. No episode predates admission.
    shifts = {e["shift"] for e in eps}
    assert shifts == {f"D{d}-{p}" for d in range(1, 6) for p in ("day", "night")}, \
        f"unexpected shifts: {sorted(shifts)}"
    assert min(e["at"] for e in eps) >= ts(1, 7), "nothing may predate the D1 day shift"

    for e in eps:
        assert e["content"] and e["author"] and e["source"]
        assert e["at"] > 0
    print(f"self-check OK: {len(eps)} episodes "
          f"({len(tag('planted'))} planted, {len(tag('noise'))} noise, "
          f"{len(tag('decoy'))} decoy, {len(tag('filler'))} filler)")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--self-check", action="store_true")
    args = p.parse_args()

    episodes = build()
    self_check(episodes)
    if not args.self_check:
        (OUT_DIR / "patient.json").write_text(json.dumps(episodes, indent=1))
        (OUT_DIR / "expected.json").write_text(json.dumps(EXPECTED, indent=1))
        print(f"wrote {OUT_DIR/'patient.json'} and {OUT_DIR/'expected.json'}")

# NOTE-R1 -- data decision worth knowing before you tune the rule:
# PRD 11.2 makes the three desaturations wearable-logged, but R1 (7.1) requires
# ">=3 distinct authors/devices". One wearable is ONE author, so device episodes
# alone cannot satisfy R1. Fixed here at the data layer, not the rule layer: each
# desaturation also gets a human spot-check note from a DIFFERENT night RN, which
# is what actually happens on a unit and preserves the pitch exactly -- three
# nurses each saw one, nobody saw three. If Person A would rather relax R1 to
# ">=3 distinct authors OR >=3 distinct shifts", these three notes can go.
