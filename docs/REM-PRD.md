# REM — Product Requirements Document
**Long-term care shift handoff memory, built on a consolidating graph, fed by a resident-worn device.**

JacHacks submission · Tracks: Social Impact (primary), Agentic AI (secondary), Best Use of Jaclang
Status: Draft v2 · Build window: 24 hours

Name is a placeholder. REM = the sleep stage where memory consolidation happens — which now also happens to be one of the vitals the device actually tracks. Alternatives: Vigil, Handoff, Nightshift.

## 1. One-liner

A nursing home shift handoff is a memory consolidation event. We built one.

REM ingests everything that happens to a resident across a shift — nursing documentation, labs, and a continuously worn health-monitoring device — consolidates it into a provenance-linked belief graph, and emits a structured handoff report, plus a phone call to the on-duty nurse when, and only when, a deterministic rule fires on the graph.

## 2. Problem

Handoffs are the moment resident care, responsibility, and information transfer between caregivers. They are also where residents get hurt. Up to 70% of care errors trace back to ineffective handoff communication, which is why facilities lean on standardized tools like SBAR — the nurse-to-nurse shift-report standard — precisely because unstructured handoffs fail.

Long-term care makes this worse than a hospital ward, not better: fewer nurses per resident, heavier reliance on CNAs for direct observation, higher agency/travel-staff turnover, and residents who can't always self-report a change the way an alert hospital patient might.

The failures are communication and staffing, not primarily clinical complexity. The real breakdowns:

| Failure mode | What happens | Why current tools miss it |
|---|---|---|
| The "why" dies first | Day 1: resident develops a rash on their prescribed antibiotic → switched to an alternative. By shift 6, every note just says "on [alternate drug]." Nobody knows why. | Summaries carry state, not causation. The reasoning edge is dropped. |
| Copy-forward zombies | "Suspected UTI" enters day 1, urine culture comes back negative day 2, antibiotic still charted and running on day 5. | Each shift inherits the prior note. Nothing tracks *last verified* vs. *last asserted*. |
| Cross-shift patterns | Three different nurses each note one nighttime desaturation on their own shift. No individual note is alarming. Nobody sees three. A wearable logging every event automatically doesn't fix this on its own — it just means there's more data sitting in more silos. | Every tool is bounded by a shift. Nothing looks across them, device-sourced or not. |
| Slow decline, invisible day-to-day | Mobility and sleep quality quietly decline for four days before a fall. No single day's note is concerning enough to escalate. | Daily documentation isn't built to notice a multi-day trend; only a longitudinal query does. |
| Interrupted handoff | Report starts, someone's paged away, restart from the top or skip sections. | No resumable state. Handoff is a conversation, not an object. |

Every one of these is a graph problem presented as a document problem.

## 3. Thesis

Four claims the product is built on:

1. **A handoff is compression.** Twelve hours of episodic detail → a semantic summary that survives into the next shift. This is exactly memory consolidation, performed badly, in a hallway, from recall.
2. **SBAR is a type, not a template.** Given a typed output struct, `by llm()` generates the composition step. We extend the standard SBAR shape (Situation/Background/Assessment/Recommendation) with an explicit action list and if/then contingencies — the two components clinicians actually miss most — rather than inventing a new mnemonic.
3. **Urgency is a rule, not a judgment.** The model extracts and composes. A deterministic rule engine decides when the phone rings. This is the difference between a system a facility could adopt and a demo.
4. **A wearable doesn't need a new memory system. It needs to feed the one that already works.** Continuous vitals, fall detection, and mobility/sleep trend are just another episodic source — same ingestion shape as a nursing note, same decay, same consolidation.

## 4. Goals / Non-goals

**Goals**
- **G1** — Produce a reviewable SBAR-plus handoff from raw multi-source episodes.
- **G2** — Preserve causal provenance: every assertion traces to source episodes with author/device and timestamp.
- **G3** — Detect contradictions and unverified drift across shifts.
- **G4** — Surface patterns invisible within a single shift, whether reported by staff or logged by the device.
- **G5** — Escalate by phone on deterministic rules, with a measured false-positive rate.
- **G6** — Make the graph visibly load-bearing to a judge in under 10 seconds.
- **G7** — Accept spoken handoffs as input and flag what the conversation omitted.
- **G8** — Ingest continuous wearable vitals, fall events, and daily mobility/sleep trend as first-class episodes, through the exact same Consolidate pipeline as manual documentation — no parallel system.
- **G9** — Surface slow-onset, multi-day decline (mobility, sleep) as an antecedent finding, not just same-symptom corroboration.

**Non-goals**
- Not a diagnostic tool. Zero clinical inference.
- Not autonomous. The outgoing nurse reviews, edits, and signs. REM never speaks to the incoming nurse as authority.
- No real PHI. Synthetic data only, stated on a slide.
- No real hardware. The "device" is a synthetic data generator standing in for a consumer or medical wearable API — a swappable input, not something built in 24 hours.
- No EHR integration. Mock ingestion adapters.
- No HIPAA/BAA posture, no CMS long-term-care compliance review. Out of scope for a 24h build; noted as required future work.
- Not a replacement for hands-on rounding. The device and graph reduce what gets lost at handoff; they don't reduce how often a CNA checks on someone.

## 5. Users

**Primary — outgoing nurse (LPN/RN).** Covering a full hall or wing, often 20–30 residents, far more than a hospital nurse's patient load. Needs a draft handoff she can review in 90 seconds and correct in 3. Relies heavily on CNA reports and the device feed, since personal observation time per resident is thin. Trust requires seeing where each line came from.

**Secondary — incoming nurse.** Needs to know what changed, what's unverified, and what nobody has followed up on.

**Tertiary — charge nurse / on-call physician.** Nursing homes frequently have no physician on site, especially overnight, so the real escalation chain is CNA → nurse → charge nurse/DON → on-call physician. REM's escalation walker mirrors that chain, not a flattened hospital hierarchy.

## 6. Architecture

### 6.1 Two-layer memory

**Episodic nodes** — raw, timestamped, attributed. Nursing notes, vitals, medication administration, labs, family-reported observations, verbal handoff transcript, and now: continuous device readings, fall events, and daily mobility/sleep summaries. Cheap to create. Decay fast.

**Semantic nodes** — clinical beliefs distilled from ≥3 episodes. Decay slowly. Every one carries `Derived` edges to its sources.

Extraction, never generation. A semantic node may only assert what is traceable to source episodes. Enforce in the type: a `Clinical` node requires a non-empty `Derived` set at construction. If `by llm()` can't cite it, it doesn't exist.

Decay governs salience, not deletion. Nothing is ever removed from a resident's record — legal and safety non-starter. `strength` answers "how much does this deserve airtime in the next handoff." Low-strength episodes drop out of the summary, stay in the graph, one click away.

### 6.2 Schema

```
node Episode {
    has content: str;
    has source: str;          # "nursing_note" | "vitals_manual" | "mar" | "lab"
                               # | "family" | "verbal_handoff"
                               # | "wearable_vitals" | "wearable_fall"
                               # | "wearable_mobility" | "wearable_sleep"
    has author: str;          # staff name, or device_id for wearable sources
    has at: float;
    has strength: float = 1.0;
    has access_count: int = 0;
}

node Clinical {                # semantic belief
    has claim: str;
    has category: str;
    has last_asserted: float;
    has last_verified: float;
    has strength: float = 1.0;
    has suppressed: bool = false;
}

node Action { has task: str; has due: float; has owner: str; }
node Handoff { has sbar: SBARPlus; has shift: str; has signed_by: str; }
node Clinician { has name: str; has phone: str; has role: str; }   # RN | LPN | CNA | on-call MD

edge Derived {}                # Clinical -> Episode  (provenance)
edge Causes {}                 # Episode -> Episode   (the "why")
edge Justifies {}              # Clinical -> Action   (why an order is running)
edge Contradicts { has resolved_toward: str; has at: float; }
edge Refines {}
edge Completed { has at: float; }
edge Fired { has at: float; has rule: str; }
edge Acknowledged { has at: float; has readback_ok: bool; }
edge Escalates { has after_seconds: int; }
edge Follows {}                # Handoff -> prior Handoff
```

Decay: `strength *= exp(-Δt / (τ · (1 + log(1 + access_count))))`. Retrieval bumps `last_accessed` and boosts strength, so use shapes what survives.

### 6.2a Wearable ingestion — same shape, new source

The graph didn't need to change to absorb a new sensory modality — it needed a formatting adapter. A device reading becomes a short natural-language `Episode.content` string, same as a nursing note:

```
def format_wearable_episode(row: dict, metric: str) -> str by cheap();
# e.g. "SpO2 dropped to 84% (03:20)"
#      "Fall detected via accelerometer, no movement for 2 min (02:14)"
#      "Mobility: 1,180 steps today, down from a ~2,500 baseline"
#      "Sleep quality score 42/100, down from a ~80 baseline"

walker IngestDevice {
    has readings: list[dict];
    can absorb with Handoff entry {
        for r in self.readings {
            here ++> Episode(
                content = format_wearable_episode(r, r["metric"]),
                source  = r["source"],       # wearable_vitals / _fall / _mobility / _sleep
                author  = r["device_id"],
                at      = r["timestamp"]
            );
        }
    }
}
```

Same `Consolidate` walker, same decay, same reconciliation. This is the exact same architectural claim §9.2 makes for speech — it applies again here for sensor data.

### 6.3 Walkers

**Consolidate** — runs per shift boundary (or on a demo button). Four phases:

1. **Replay** — enter at recent episodes, hop to associatively-near neighbors, assemble working set. Pure traversal, no LLM.
2. **Abstract** — for clusters of ≥3 related episodes, `by llm()` extracts the invariant → new `Clinical` node + `Derived` edges. The ≥3 floor is a hallucination guard.
3. **Reconcile** — for `Clinical` pairs sharing subject matter, `by llm()` classifies duplicate / refinement / contradiction / unrelated. Duplicates merge and union provenance. Contradictions get a `Contradicts` edge; recency + support count picks the live side. Loser is suppressed, not deleted.
4. **Prune** — episodes below the strength floor whose content is fully captured by a semantic parent get `archived = true`. Never `del`.

**Compose** — assembles the SBAR-plus handoff from surviving semantic nodes + high-strength episodes.

**Tripwire** — evaluates deterministic rules against graph state after consolidation.

**Escalate** — walks the escalation chain, placing calls until acknowledged.

### 6.4 SBAR-plus composition

```
obj Action { has task: str; has owner: str; has due: str; }
obj IfThen { has trigger: str; has response: str; }

obj SBARPlus {
    has situation: str;
    has background: str;
    has assessment: str;
    has recommendation: str;
    has action_list: list[Action];
    has contingencies: list[IfThen];
}

def compose_handoff(
    episodes: list[Episode],
    beliefs: list[Clinical]
) -> SBARPlus by llm();
```

The struct is the prompt. No prompt engineering, no output parsing, no retry-on-malformed-JSON.

*Why SBAR and not I-PASS:* I-PASS is validated specifically for physician handoffs; SBAR is the nurse-to-nurse shift-report standard actually used at the CNA/LPN/RN level this product lives at. We keep I-PASS's two most useful additions — an explicit action list and if/then contingencies — layered on top, since those are the parts SBAR alone tends to lose.

### 6.5 Handoff chaining

Each `Handoff` node links to the prior via `Follows`.

- **Resumable.** Interrupted mid-report → resume at the exact node instead of restarting.
- **Queryable history.** "When did this claim first appear, and has anyone confirmed it since?" is a traversal.

## 7. Tripwire: how it decides to call

The LLM does extraction and composition. A rule engine does decision. Firing is a subgraph pattern match with no model in the loop.

### 7.1 Rules

| # | Rule | Pattern | Catches |
|---|---|---|---|
| R1 | Corroboration | `Clinical` with ≥3 `Derived` edges, ≥3 distinct authors/devices, spanning ≥2 shifts, within 72h, category in WATCHED | Cross-shift patterns (the desaturations) — regardless of whether each episode came from a nurse or the device |
| R2 | Live contradiction | `Contradicts` lands where the losing claim still has an active `Justifies` → running `Action` | UTI ruled out, antibiotic still running |
| R3 | Unverified drift | `last_asserted − last_verified > 24h` on a claim justifying an active intervention | Copy-forward zombies |
| R4 | Orphaned action | `Action` past due with no `Completed` edge | Dropped follow-ups |
| R5 | Antecedent decline | `wearable_mobility` or `wearable_sleep` episodes trending downward for ≥3 consecutive days, in the WATCHED category | The slow-burn decline that precedes a fall or acute event, invisible in any single day's note |
| R6 | Fall event | Any `wearable_fall` episode | Falls don't need corroboration — a single fall is inherently high-severity and goes straight to Tier 3 |

```
def fires(n: Clinical) -> bool {
    return len([n -->:Derived:-->]) >= 3
        and distinct_authors(n) >= 3
        and span_hours(n) <= 72
        and n.category in WATCHED
        and not recently_fired(n);
}
```

None of R1–R5 are expressible as a threshold on a scalar. R6 is deliberately the exception — a fall is a single discrete safety event, and treating it like everything else (waiting for corroboration) would be a design failure, not restraint.

### 7.2 Severity tiers — the alarm-fatigue control

Firing ≠ phone call. Tier is a static lookup on `(rule_type, resident_acuity, time_sensitivity)`:

| Tier | Channel |
|---|---|
| 0 | Appears in next handoff (default — most findings die here) |
| 1 | Dashboard flag |
| 2 | Push notification |
| 3 | Phone call |

Plus a clock gate for everything except R6: if a finding can wait for the next handoff and it's 3 AM, drop to tier 0. Fall events (R6) bypass the clock gate entirely — a fall at 3 AM is exactly when it matters most, given fracture risk in an elderly resident and the likelihood nobody's nearby.

Report the ratio in the pitch: "142 findings. 3 calls." The restraint is the product.

### 7.3 Suppression

Firing writes a `Fired` edge. Rules require absence of a recent one. Acknowledgment suppresses until new evidence arrives — a fourth desaturation re-opens; re-reading the same three does not.

### 7.4 The honest seam

Extraction feeds the rules, so the model does influence firing. Name it on stage:

> The model can affect whether the facts are right. It cannot affect what counts as urgent.

The first half is checkable — every typed observation links to source data, verifiable in two seconds. "The model felt this was urgent" is checkable by nobody.

## 8. Escalation & voice

```
walker Escalate {
    has finding: Clinical;
    can page with Clinician entry {
        result = place_call(here.phone, speak(self.finding));
        if result.acknowledged {
            here +>:Acknowledged(at=now(), readback_ok=result.readback):+> self.finding;
            disengage;
        }
        visit [-->](`?Clinician);   # nurse → charge nurse/DON → on-call MD
    }
}
```

Verbal read-back required before acknowledgment counts.

**Call script A — fall event (primary demo call), 40 seconds, hard cap**

> "This is the handoff assistant calling about Mrs. [Resident], Room 14. The wearable detected a fall at 2:14 AM with no movement for the following two minutes, and no room check has been logged yet. Requesting an immediate check. Can you read back the request?"

**Call script B — cross-shift corroboration (shown via graph/omission panel, not necessarily a second live call)**

> "Consolidation flagged a pattern across the last three shifts: nocturnal oxygen desaturation at 02:10, 01:45, and 03:20, logged separately by the wearable and never connected across shifts. Requesting continuous pulse oximetry review. Can you read back the request?"

Identify → one finding → provenance → ask → read-back.

## 9. Verbal handoff capture (ambient input)

Terminology: this is speech-to-text, not TTS. We transcribe spoken handoffs and structure them; we don't read documents aloud.

### 9.1 Why this is the highest-value manual input

The spoken handoff is where the reasoning lives. "We switched her antibiotic because she got a rash" gets said in a hallway and never written down — failure mode #1 from §2. Ambient capture is the direct fix.

### 9.2 Where it fits — nowhere new

Transcript utterances become `Episode` nodes with `source = "verbal_handoff"` and `author =` the diarized speaker. They flow into the exact same `Consolidate` walker as every other source, including the device stream.

```
def structure_utterance(text: str, speaker: str) -> Observation by cheap();

walker IngestTranscript {
    has segments: list[Segment];
    can absorb with Handoff entry {
        for seg in self.segments {
            obs = structure_utterance(seg.text, seg.speaker);
            here ++> Episode(
                content = seg.text,
                source  = "verbal_handoff",
                author  = seg.speaker,
                at      = seg.start
            );
        }
    }
}
```

Diarization is required, not optional — provenance needs an author.

### 9.3 Omission check

After the conversation ends, compare what the graph says should have been conveyed against what was actually said. The set of obligations is deterministic — tier-0-and-above findings, actions past due, live contradictions, any claim justifying an active intervention. Only LLM call is a per-claim boolean:

```
def was_conveyed(claim: str, transcript: str) -> bool by cheap();
```

Output:

> **Not conveyed in this handoff (3):**
> · Reason for antibiotic switch — rash, day 1
> · Overnight desaturation pattern — 3 events, wearable-logged, never connected
> · Room check for the 2:14 AM fall — no completion recorded

### 9.4 Provider

Deepgram Nova-3, batch mode, diarization enabled. $200 free credit, no card. Alternatives: AssemblyAI (cheaper, stronger on accented audio); OpenAI transcription (no diarization — disqualifying here).

## 10. Tech stack

### 10.1 Core

| Layer | Choice | Why |
|---|---|---|
| Language / runtime | Jac + Jaseci | Requirement, and genuinely the right tool: persistent per-user root graph = zero persistence code |
| Graph store | Jac's native persistent graph | The graph is the database |
| LLM calls | byllm plugin | `by llm()` on typed signatures — extraction and composition |
| Model | DeepSeek via byllm/LiteLLM (see §10.3) | Cost, with routing for the one call that can't be flaky |
| Server | `jac start main.jac` | REST + auth + Swagger + persistence, no code |

### 10.2 Frontend — Jac full-stack (LOCKED)

Decision: everything in Jac, served by `jac start main.jac`. No separate frontend process.

Screens:
1. Split-screen comparison (naive vs. REM SBAR-plus)
2. Graph view with provenance highlighting on click
3. Device dashboard — live vitals trace + daily mobility/sleep trend, so a judge can *see* the wearable narrative, not just read about it
4. Consolidation run view (walker animation, live counts)
5. Tripwire / escalation log

Contingency if the client layer is genuinely broken: walkers auto-expose as REST endpoints, so a minimal static HTML + vanilla JS page is a ~1 hour escape hatch. Don't reach for it before hour 14.

### 10.3 External providers

| Provider | Use | Plan | Notes |
|---|---|---|---|
| ElevenLabs Agents | Outbound call + voice | Free tier: 15 min/mo | Native outbound calling |
| Deepgram | Verbal handoff transcription + diarization | $200 free credit | Nova-3 batch |
| DeepSeek API | `by llm()` backend — extraction, reconcile | Pay-as-you-go | Budget ~$2–5 |
| Fallback model | `compose_handoff` only | Pay-as-you-go | ~6 calls per demo run |
| — | Wearable data | Free — our own Python generator | See §11.1; no vendor, no API key |

### 10.4 Model routing

Route by structural difficulty — flat structs and enum classification to DeepSeek, the nested `SBARPlus` composition to a stronger model. Validate at hour 2, not hour 14.

### 10.5 Graceful degradation

Build the call layer swappable. If telephony dies, `Escalate` still runs and still writes `Acknowledged` edges — render as an on-screen notification instead of audio.

## 11. Data — synthetic, and say so

One resident. Five-day window. Six shifts. ~400 manual episodes, plus a continuous device stream.

### 11.1 Device data

Already built: a Python generator (`generate_vitals.py`) with two modes —

- **`realtime`** — per-second heart rate, SpO2, respiration, body temperature, accelerometer/fall, with three selectable deterioration types (`desaturation`, `bradycardia`, `fever`) and an independent `--fall` flag
- **`daily`** — per-day steps and sleep-quality score, with a configurable decline start day

Output CSVs feed directly into `IngestDevice` (§6.2a) — no additional adapter work needed beyond the formatting function.

### 11.2 Planted findings

1. **The rash-switch.** Day 1 causal chain: antibiotic → rash → switched to alternative. Must survive to shift 6 with the *why* intact. → tests `Causes` preservation.
2. **The UTI zombie.** "Suspected UTI" day 1, urine culture negative day 2, antibiotic still running day 5. → tests R2.
3. **The three desaturations.** Wearable-logged at 02:10 / 01:45 / 03:20 across three shifts, never connected. → tests R1, and is the demo climax.
4. **The fall.** A single `wearable_fall` episode, no CNA check logged afterward. → tests R6 and the escalation call.
5. **The antecedent decline.** Mobility and sleep-quality score trending down for 4 days before the fall — nobody's daily note flags it in isolation. → tests R5, and gives the omission panel a genuinely retrospective insight: "the decline was visible four days out."
6. **Noise.** ~40 variations of "assisted with ADLs, tolerated well" / "ambulated in hallway with standby assist." → tests pruning.

Plus ~40 decoys that must NOT fire: two observers instead of three, a contradiction on an inactive order, a stale claim justifying nothing, an action completed one minute late, and one isolated low-step day caused by a scheduled outing rather than real decline (tests that R5 doesn't over-fire on noise).

## 12. Evaluation

| Metric | Method | Target |
|---|---|---|
| Fact survival | Plant 12 must-know facts at admission; count survivors at shift 6, naive vs. REM | REM ≥ 11/12, naive ≤ 6/12 |
| False positive rate | 40 planted decoys, count spurious fires | 0 |
| Contradiction detection | Planted zombies caught | 1/1 |
| Antecedent decline detection | Planted 4-day mobility/sleep decline caught before the fall | 1/1, with correct lead time reported |
| Fall response | Latency from `wearable_fall` episode to escalation call | Report actual seconds; no missed fall, no false fall from accelerometer jitter alone |
| Compression | Nodes and tokens, before vs. after | ~400 → ~80 nodes; ~70% token reduction |
| Alarm ratio | Findings vs. tier-3 calls | Report honestly (e.g. 142 : 3) |

False positives are the number that matters — they're what causes nurses to stop answering pages.

State clearly: thresholds (3 observers, 72h window, 24h staleness, 3-day decline) are hand-tuned on synthetic data. Real deployment needs clinical validation.

## 13. Demo — 3 minutes

| Time | Beat |
|---|---|
| 0:00–0:15 | Hook. "A nursing home shift handoff is a memory consolidation event. So we built one — and it never sleeps, even when the resident does." |
| 0:15–0:40 | Device dashboard live: vitals trace declining, mobility/sleep trend dropping over the prior days. "This has been happening for four days. No single shift note said so." |
| 0:40–1:05 | Play the recorded verbal handoff. Transcript resolves with speaker labels; one causal explanation is spoken that exists nowhere in the written record. |
| 1:05–1:25 | Omission panel populates: the antibiotic reasoning, the desaturation pattern, and the missed room check — all things the graph knew and the conversation skipped. |
| 1:25–1:45 | Split screen, shift 6. Left: what the incoming nurse gets today — accumulated copy-forward, ~4,000 words. Right: REM's SBAR-plus, ~300 words, rash reasoning present, UTI claim struck through and dated. |
| 1:45–2:05 | Click a line. Graph lights up the exact source episodes — nursing note, device reading, or transcript — with author/device and timestamp. |
| 2:05–2:25 | Consolidation replay (pre-computed, replayed live). Counts drop 412 → 82. |
| 2:25–2:50 | The call. Real phone, speakerphone near the mic. Agent delivers the fall escalation, naming its own evidence. Nurse reads back. `Acknowledged` edge appears on screen. |
| 2:50–3:00 | The restraint slide + close: "142 findings. 3 calls. Zero false positives on 40 decoys." Synthetic data disclosure. |

**Demo rules:** don't run consolidation live against the API — pre-compute and replay. Record a backup video of a successful call before presenting. Someone will ask about real data and real hardware — have the slide ready for both.

## 14. Build order (24h)

| Hours | Work | Gate |
|---|---|---|
| 0–1 | Repo, `jac install byllm`, ElevenLabs signup, Deepgram key, `jac start --client` hello-world spike | Phone verified, one node renders |
| 1–2 | DeepSeek → `SBARPlus` validation, 10 throwaway calls | Routing decided |
| 2–4 | Schema + seed generator: 4 manual planted findings + 40 decoys. Run `generate_vitals.py` for the fall + desaturation + daily-trend CSVs. Record the 45s handoff audio now | Seed data + device CSVs load, audio in hand |
| 4–7 | Naive baseline retrieval (control + left pane) | Baseline renders |
| 7–9 | Decay + retrieval walker | — |
| 9–13 | Consolidate phases 2–4, plus `IngestDevice` adapter | Must work before anything below |
| 13–15 | Deepgram batch transcription + `IngestTranscript` walker | Transcript → episodes |
| 15–17 | Device dashboard + provenance-highlighting UI + graph viz | Click-to-source works, live trace renders |
| 17–19 | Tripwire rules (R1–R6) + tier table + suppression | — |
| 19–20 | Omission check | — |
| 20–22 | Escalate walker + ElevenLabs call | Degrade to notifications if blocked |
| 22–23 | Eval numbers, confusion matrix | — |
| 23–24 | Video, README, backup call recording, buffer | — |

**If you fall behind — cut in this order.** You now have three input modalities (structured episodes, verbal capture, and a continuous device stream) plus escalation — that's ambitious for 24 hours. Cut from the bottom, and note the device stream now outranks verbal capture, since it's the actual product being pitched:

1. Spoken/recorded conflict detection (§9.4 in the original scope) — nice, not load-bearing.
2. Verbal handoff capture entirely (§9) — a strong differentiator, but the device narrative alone carries a real story without it.
3. Live phone call → degrade to on-screen notification. `Escalate` still runs and still writes `Acknowledged` edges.
4. Graph animation → static before/after.

**Do not cut:** consolidation, provenance click-through, omission check, and device ingestion (R5/R6). Those are the project now.

## 15. Risks

| Risk | Mitigation |
|---|---|
| Reconcile is O(n²) over pairs | Gate by embedding similarity or subject tag before calling the LLM |
| Live call fails on stage | Pre-recorded backup, cued |
| DeepSeek returns malformed nested struct | Validate at hour 2. Route `compose_handoff` to a stronger model |
| Latency on live consolidation | Pre-compute and replay |
| Fall detection false-positives on accel jitter | Threshold the impact spike well above normal movement noise; verify against the decoy set |
| Judge challenges clinical realism | Lead with the review-and-sign framing; state hand-tuned thresholds openly |
| Judge asks "is this real hardware?" | Be direct: synthetic data standing in for a consumer/medical wearable API, by design for a 24h build |

## 16. Safety positioning

- **Draft, not directive.** The outgoing nurse reviews, edits, and signs.
- **No clinical inference.** Extraction only.
- **Deterministic escalation.** The model does not decide urgency.
- **Non-destructive.** Salience affects the summary, never the record.
- **Synthetic data, synthetic device.** No PHI, no real hardware, no HIPAA/CMS claims. Real deployment requires clinical validation of thresholds and a real compliance posture.

## 17. Out of scope / future

- Real wearable hardware and a real consumer/medical device API integration
- EHR integration (FHIR ingestion adapters)
- Real-time streaming capture and mid-conversation nudges
- Multi-resident load view for a full wing
- Threshold learning from acknowledgment/dismissal feedback
- Clinical validation study, HIPAA posture, CMS long-term-care compliance review

---

### Appendix — pitch lines worth memorizing

- "A nursing home shift handoff is a memory consolidation event. So we built one."
- "The model can affect whether the facts are right. It cannot affect what counts as urgent."
- "142 findings. 3 calls."
- "No single shift note flagged it. The device saw all three. Nobody connected them."
- "The decline was visible four days before the fall."
- "Nothing is deleted. Salience decides what gets airtime, not what exists."
- "The graph didn't change to absorb a device, or a voice. It was already the right shape."