"""Integration fixture — the one-resident, five-day scenario (PRD §11).

A's development / demo / eval harness. In the real split B owns `seed/`; this
stands in for it so the graph core runs end-to-end without B. It builds the graph
in the state a shift boundary leaves it: raw episodes for the compression story,
plus the consolidated belief structure the tripwire fires on — so R1–R6 and the
eval numbers are reproducible without depending on a live LLM.

All six planted findings (PRD §11.2) and the decoy set (must NOT fire) are here.
Timestamps hang off a fixed SEED_NOW anchor, which is also passed to Tripwire as
`now_ref` for a deterministic clock.

Reset before re-seeding: `jac clean --all --force` (re-running duplicates nodes).
"""

import os;
import from schema {
    Episode, Clinical, ActionNode, Clinician,
    Derived, Causes, Justifies, Contradicts, Escalates, Completed
}

# The one clinician whose phone actually rings on demo day. Read from the
# environment (REM_DEMO_PHONE in .env) so nobody's personal number is committed.
# Falls back to a reserved +1555 number, which can never connect -- so an unset
# variable degrades to "no answer" and the walker climbs the chain, rather than
# dialing a stranger.
glob DEMO_PHONE: str = os.getenv("REM_DEMO_PHONE") or "+15550000001";
glob DEMO_PHONE_RN: str = os.getenv("REM_DEMO_PHONE_RN") or "+15550000002";
glob DEMO_PHONE_CHARGE: str = os.getenv("REM_DEMO_PHONE_CHARGE") or "+15550000003";
glob DEMO_PHONE_MD: str = os.getenv("REM_DEMO_PHONE_MD") or "+15550000004";

# --- scenario clock ---------------------------------------------------------
glob SEED_NOW: float = 1712347200.0;   # 2024-04-05 20:00 UTC — the shift-6 handoff
glob DAY: float = 86400.0;
glob HOUR: float = 3600.0;
glob NOISE_COUNT: int = 320;           # ~400 raw nodes total, for the ~400->~80 story


"""Seed the entire scenario graph on root. Reports the raw episode count."""
walker:pub SeedGraph {
    has reports: list[int] = [];

    can build with Root entry {
        raw = 0;

        # -- escalation chain (PRD §5): CNA -> RN -> charge/DON -> on-call MD --
        cna = root ++> Clinician(name="CNA Rosa", phone=DEMO_PHONE, role="CNA", rank=1);
        rn = root ++> Clinician(name="RN Jordan", phone=DEMO_PHONE_RN, role="RN", rank=2);
        charge = root ++> Clinician(name="Charge Nurse Pat", phone=DEMO_PHONE_CHARGE, role="RN", rank=3);
        md = root ++> Clinician(name="Dr. On-Call", phone=DEMO_PHONE_MD, role="on-call MD", rank=4);
        cna +>:Escalates(after_seconds=60):+> rn;
        rn +>:Escalates(after_seconds=90):+> charge;
        charge +>:Escalates(after_seconds=120):+> md;

        # -- planted #1: the rash-switch causal chain (survives to shift 6) ----
        e_abx = root ++> Episode(content="Started amoxicillin for suspected infection",
            source="mar", author="RN Maya", at=SEED_NOW - 4.0 * DAY, strength=0.6, subject="abx");
        e_rash = root ++> Episode(content="Developed a rash on the trunk",
            source="nursing_note", author="RN Maya", at=SEED_NOW - 4.0 * DAY + 4.0 * HOUR, strength=0.6, subject="abx");
        e_switch = root ++> Episode(content="Switched to doxycycline due to the rash",
            source="mar", author="RN Maya", at=SEED_NOW - 4.0 * DAY + 6.0 * HOUR, strength=0.6, subject="abx");
        e_abx +>:Causes():+> e_rash;
        e_rash +>:Causes():+> e_switch;
        raw += 3;
        rash = root ++> Clinical(claim="Antibiotic switched to doxycycline because amoxicillin caused a rash",
            category="skin", last_asserted=SEED_NOW, last_verified=SEED_NOW, strength=0.9, subject="abx");
        rash +>:Derived():+> e_abx;
        rash +>:Derived():+> e_rash;
        rash +>:Derived():+> e_switch;

        # -- planted #3: three nocturnal desaturations, never connected (R1) ---
        d1 = root ++> Episode(content="SpO2 dropped to 84% overnight (02:10)",
            source="wearable_vitals", author="dev_014", at=SEED_NOW - 2.0 * DAY, strength=0.7, subject="spo2");
        c1 = root ++> Episode(content="Resident looked a little dusky overnight",
            source="nursing_note", author="RN Alice", at=SEED_NOW - 2.0 * DAY + 300.0, strength=0.5, subject="spo2");
        d2 = root ++> Episode(content="SpO2 dropped to 86% overnight (01:45)",
            source="wearable_vitals", author="dev_014", at=SEED_NOW - 1.0 * DAY, strength=0.7, subject="spo2");
        c2 = root ++> Episode(content="Brief desaturation noted, resolved on its own",
            source="nursing_note", author="RN Bob", at=SEED_NOW - 1.0 * DAY + 300.0, strength=0.5, subject="spo2");
        d3 = root ++> Episode(content="SpO2 dropped to 85% overnight (03:20)",
            source="wearable_vitals", author="dev_014", at=SEED_NOW - 0.25 * DAY, strength=0.7, subject="spo2");
        c3 = root ++> Episode(content="Another overnight dip in oxygen",
            source="nursing_note", author="RN Carol", at=SEED_NOW - 0.25 * DAY + 300.0, strength=0.5, subject="spo2");
        raw += 6;
        desat = root ++> Clinical(claim="Recurrent nocturnal oxygen desaturation across three shifts",
            category="respiratory", last_asserted=SEED_NOW, last_verified=SEED_NOW, strength=0.9, subject="spo2");
        for e in [d1, c1, d2, c2, d3, c3] {
            desat +>:Derived():+> e;
        }

        # -- planted #2: the UTI zombie (R2 live contradiction) ---------------
        e_uti1 = root ++> Episode(content="Suspected UTI, started on ciprofloxacin",
            source="nursing_note", author="RN Maya", at=SEED_NOW - 4.0 * DAY, strength=0.4, subject="uti");
        e_uti2 = root ++> Episode(content="Urine culture came back negative",
            source="lab", author="Lab", at=SEED_NOW - 3.0 * DAY, strength=0.7, subject="uti");
        raw += 2;
        uti_susp = root ++> Clinical(claim="Suspected UTI", category="infection",
            last_asserted=SEED_NOW - 4.0 * DAY, last_verified=SEED_NOW - 4.0 * DAY,
            strength=0.3, suppressed=True, subject="uti");
        uti_neg = root ++> Clinical(claim="UTI ruled out — urine culture negative", category="infection",
            last_asserted=SEED_NOW - 3.0 * DAY, last_verified=SEED_NOW - 3.0 * DAY,
            strength=0.8, subject="uti");
        uti_susp +>:Derived():+> e_uti1;
        uti_neg +>:Derived():+> e_uti2;
        uti_neg +>:Contradicts(resolved_toward="ruled out", at=SEED_NOW - 3.0 * DAY):+> uti_susp;
        cipro = root ++> ActionNode(task="Ciprofloxacin 500mg BID", due=SEED_NOW + DAY, owner="RN");
        uti_susp +>:Justifies():+> cipro;   # loser still justifies a RUNNING order -> R2 fires

        # -- planted (R3): copy-forward drift on an active intervention --------
        tele = root ++> Clinical(claim="On continuous telemetry for possible arrhythmia",
            category="cardiac", last_asserted=SEED_NOW, last_verified=SEED_NOW - 3.0 * DAY,
            strength=0.7, subject="tele");
        tele_order = root ++> ActionNode(task="Continuous cardiac telemetry", due=SEED_NOW + DAY, owner="RN");
        tele +>:Justifies():+> tele_order;   # last_asserted - last_verified = 72h > 24h -> R3 fires

        # -- planted (R4): orphaned past-due action, no completion -------------
        root ++> ActionNode(task="Wound-care follow-up dressing change", due=SEED_NOW - 2.0 * HOUR, owner="RN");

        # -- planted #5: 4-day mobility + sleep decline (R5) ------------------
        # content leads with the metric value so it parses deterministically
        mob = [2480, 2300, 1850, 1350, 1120];
        slp = [82, 79, 61, 50, 42];
        for i in range(5) {
            root ++> Episode(content=f"{mob[i]} steps today (mobility), down from a ~2500 baseline",
                source="wearable_mobility", author="dev_014", at=SEED_NOW - (4.0 - i) * DAY, strength=0.6, subject="mobility");
            root ++> Episode(content=f"{slp[i]} sleep-quality score, down from a ~80 baseline",
                source="wearable_sleep", author="dev_014", at=SEED_NOW - (4.0 - i) * DAY, strength=0.6, subject="sleep");
            raw += 2;
        }

        # -- planted #4: the fall (R6) — single event, no room check ----------
        e_fall = root ++> Episode(content="Fall detected via accelerometer, no movement for 2 min (02:14)",
            source="wearable_fall", author="dev_014", at=SEED_NOW - 8.0, strength=1.0, subject="fall");
        raw += 1;
        # A Clinical for the fall so Escalate has a finding to call about. R6 still
        # fires on the raw episode; this is the escalatable belief it produces.
        fall = root ++> Clinical(claim="Unwitnessed fall at 02:14, no room check logged yet",
            category="fall", last_asserted=SEED_NOW, last_verified=SEED_NOW, strength=1.0, subject="fall");
        fall +>:Derived():+> e_fall;

        # -- DECOYS: 4 structural near-misses that must NOT fire ---------------
        # (a) R1 near-miss: 3 derived episodes but only 2 distinct authors
        b1 = root ++> Episode(content="Mild ankle edema noted", source="nursing_note",
            author="RN Alice", at=SEED_NOW - 2.0 * DAY, strength=0.4, subject="edema");
        b2 = root ++> Episode(content="Ankle edema again", source="nursing_note",
            author="RN Alice", at=SEED_NOW - 1.0 * DAY, strength=0.4, subject="edema");
        b3 = root ++> Episode(content="Still some edema", source="nursing_note",
            author="RN Bob", at=SEED_NOW - 0.5 * DAY, strength=0.4, subject="edema");
        raw += 3;
        edema = root ++> Clinical(claim="Intermittent ankle edema", category="cardiac",
            last_asserted=SEED_NOW, last_verified=SEED_NOW, strength=0.5, subject="edema");
        edema +>:Derived():+> b1;
        edema +>:Derived():+> b2;
        edema +>:Derived():+> b3;   # only 2 distinct authors -> R1 must NOT fire

        # (b) R2 near-miss: contradiction whose losing order is already completed
        old1 = root ++> Clinical(claim="Was on stool softener", category="infection",
            last_asserted=SEED_NOW - 4.0 * DAY, last_verified=SEED_NOW - 4.0 * DAY,
            strength=0.2, suppressed=True, subject="bowel");
        old2 = root ++> Clinical(claim="Stool softener discontinued", category="infection",
            last_asserted=SEED_NOW - 2.0 * DAY, last_verified=SEED_NOW - 2.0 * DAY,
            strength=0.5, subject="bowel");
        old2 +>:Contradicts(resolved_toward="discontinued", at=SEED_NOW - 2.0 * DAY):+> old1;
        done_order = root ++> ActionNode(task="Stool softener", due=SEED_NOW - 3.0 * DAY, owner="RN");
        old1 +>:Justifies():+> done_order;
        done_order +>:Completed(at=SEED_NOW - 2.0 * DAY):+> done_order;   # completed -> R2 must NOT fire

        # (c) R3 near-miss: stale claim justifying NOTHING
        root ++> Clinical(claim="History of seasonal allergies", category="neuro",
            last_asserted=SEED_NOW, last_verified=SEED_NOW - 5.0 * DAY, strength=0.3, subject="allergy");

        # (d) R4 near-miss: action completed one minute late (still completed)
        late = root ++> ActionNode(task="Evening vitals check", due=SEED_NOW - 3.0 * HOUR, owner="CNA");
        late +>:Completed(at=SEED_NOW - 3.0 * HOUR + 60.0):+> late;   # completed -> R4 must NOT fire

        # -- pruning noise: ~320 low-strength ADL notes (planted #6) ----------
        # Shared subject "adl" so Consolidate clusters them into one belief and
        # then prunes (archives) the lot — this is the 400->~80 compression.
        for i in range(NOISE_COUNT) {
            root ++> Episode(content=f"Assisted with ADLs, tolerated well (note {i})",
                source="nursing_note", author="CNA Rosa",
                at=SEED_NOW - 3.0 * DAY + i * 120.0, strength=0.12, subject="adl");
            raw += 1;
        }

        report raw;
    }
}


test "seed builds the scenario and plants six findings' worth of structure" {
    r = root spawn SeedGraph();
    assert r.reports[0] >= 340;                       # ~350 raw episodes (320 noise + planted)
    assert len([root -->[?:Clinician]]) == 4;        # full escalation chain
    assert len([root -->[?:Clinical]]) >= 8;         # beliefs + decoy beliefs
    # the fall episode exists and is a wearable_fall
    falls = [root -->[?:Episode, source == "wearable_fall"]];
    assert len(falls) == 1;
}
