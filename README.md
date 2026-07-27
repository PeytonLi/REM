# REM

> 🏆 **JacHacks Finalist** — built in 24 hours at Founders, Inc., Fort Mason, San Francisco.

**A nursing home shift handoff is a memory consolidation event. We built one — and it never sleeps, even when the resident does.**

REM ingests everything that happens to a resident across a shift — nursing documentation, labs, a continuously worn health-monitoring device, and the spoken handoff conversation itself — consolidates it into a provenance-linked belief graph, and emits a structured SBAR-plus handoff report. When a deterministic rule fires on the graph, REM places a live phone call to the on-duty nurse.

Built in [Jac](https://www.jaseci.org/) — zero persistence code, zero separate database, zero separate frontend process.

---

## Problem

Handoffs are where resident care, responsibility, and information transfer between caregivers. They are also where residents get hurt. Up to **70% of care errors** trace back to ineffective handoff communication. Long-term care makes this worse: fewer nurses per resident, heavier reliance on CNAs for observation, high agency/travel-staff turnover, and residents who can't always self-report changes.

Five specific failures, all graph problems disguised as document problems:

| Failure | What happens | Why current tools miss it |
|---|---|---|
| **The "why" dies first** | Day 1: resident develops a rash on ceftriaxone → switched to levofloxacin. By shift 6, every note just says "on levofloxacin." Nobody knows why. | Summaries carry state, not causation. The reasoning edge is dropped. |
| **Copy-forward zombies** | "Suspected UTI" entered day 1, culture negative day 2, antibiotic still running day 5. | Each shift inherits the prior note. Nothing tracks *last verified* vs. *last asserted*. |
| **Cross-shift patterns** | Three nurses each note one nighttime desaturation on their own shift. No individual note is alarming. Nobody sees three. A wearable logging every event doesn't fix this — it means more data in more silos. | Every tool is bounded by a shift. Nothing looks across them. |
| **Slow decline, invisible day-to-day** | Mobility and sleep quality quietly decline for four days before a fall. No single shift note is concerning. | Daily documentation isn't built to notice a multi-day trend. |
| **Interrupted handoff** | Report starts, someone's paged away, restart from the top or skip sections. | No resumable state. Handoff is a conversation, not an object. |

---

## Solution

REM treats a shift handoff as a **memory consolidation event**. Raw episodes (notes, vitals, device readings, spoken words) are compressed into semantic beliefs with full provenance chains. An SBAR-plus report is composed from those beliefs. A deterministic rule engine — no model in the loop — decides when the phone rings.

**Four claims the product is built on:**

1. **A handoff is compression.** Twelve hours of episodic detail → a semantic summary that survives into the next shift.
2. **SBAR is a type, not a template.** Given a typed output struct, `by llm()` generates the composition. Extended with an explicit action list and if/then contingencies — the two components clinicians actually miss most.
3. **Urgency is a rule, not a judgment.** The model extracts and composes. A deterministic rule engine decides when the phone rings.
4. **A wearable doesn't need a new memory system. It needs to feed the one that already works.** Continuous vitals, fall detection, and mobility/sleep trends are just another episodic source — same ingestion shape as a nursing note, same decay, same consolidation.

---

## How it works

```
 Raw Episodes         Consolidation          SBAR-plus Handoff       Tripwire + Escalate
 ─────────────        ─────────────          ────────────────        ───────────────────
                                                                     
 Nursing notes   →                         → Situation              R1: ≥3 corroborations
 Manual vitals   →   1. Replay (traverse)   → Background             R2: Live contradiction
 MAR entries     →   2. Abstract (by llm)   → Assessment             R3: Unverified drift
 Lab results     →   3. Reconcile (by llm)  → Recommendation         R4: Orphaned action
 Device readings →   4. Prune (archive)     → Action list            R5: Antecedent decline
 Spoken handoff  →                           → If/then contingencies R6: Fall → call NOW
                                                                     
 All become Episode nodes              Composed from Clinical nodes  Deterministic graph predicates
 │ decay, boost on access │            │ every claim cites ≥3 sources│  zero model calls in tripwire
 └────────────────────────┘            └────────────────────────────┘
```

### Two-layer memory

- **Episodic nodes** — raw, timestamped, attributed. Nursing notes, vitals, MAR, labs, family reports, verbal handoff transcript, device readings. Cheap to create. Decay fast.
- **Semantic (Clinical) nodes** — beliefs distilled from ≥3 episodes. Decay slowly. Every one carries `Derived` edges to its sources. A `Clinical` node **cannot be constructed** without citations.

**Decay governs salience, never deletion.** Nothing is ever removed from a resident's record. Low-strength episodes drop out of the summary but stay in the graph, one click away.

### Walkers

| Walker | What it does |
|---|---|
| `Consolidate` | 4-phase sweep: Replay (traverse) → Abstract (≥3 episodes → Clinical belief, by llm) → Reconcile (detect duplicates/contradictions) → Prune (archive, never delete) |
| `Compose` | Assembles the SBAR-plus handoff from surviving Clinical nodes + high-strength episodes. Nested struct filled by LLM, then frozen. |
| `Tripwire` | Evaluates six deterministic graph-predicate rules (R1–R6). Zero model calls. Writes `Fired` edges. |
| `Escalate` | Walks the CNA → nurse → charge nurse/DON → on-call MD chain, places phone calls via the SignalWire bridge, records `Acknowledged` edges with read-back verification. |

### The phone call — not a chatbot

The escalation call is not a conversation. It is a **40-second script**, written by the graph, spoken by the agent. Identify → one finding → provenance → ask for read-back. If the nurse reads it back correctly, the call ends. If not, the walker climbs the chain to the next clinician. Silence, voicemail, or timeout → `answered: false` → escalate.

### Input modalities — one shape, three sources

Manual charting, continuous device readings, and spoken handoff transcription all land as the exact same `Episode` node. No parallel systems, no special branches in consolidation. A device reading is just a nursing note written by a sensor.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  REM (Jac)                                               │
│                                                          │
│  schema.jac     decay.jac     consolidate.jac            │
│  compose.jac    tripwire.jac  escalate.jac               │
│  retrieve.jac   enrich.jac    fixture.jac                │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │  Adapt: voice.jac  │  Ingest: ingest.jac         │    │
│  │  → Deepgram diarize│  → Device CSVs → Episodes   │    │
│  │  → Bridge POST     │  → Transcript → Episodes    │    │
│  └──────────┬─────────┴─────────────────────────────┘    │
│             │                                             │
└─────────────┼────────────────────────────────────────────┘
              │ POST /call
┌─────────────▼────────────────────────────────────────────┐
│  Telephony Bridge (Node, hosted on Render)                │
│                                                          │
│  POST /call {to, script} → blocks → {answered, turns}    │
│  SignalWire ↔ WebSocket media proxy ↔ ElevenLabs Agents  │
│                                                          │
│  SignalWire: outbound PSTN call, TwiML compat             │
│  ElevenLabs: TTS + ASR, script injected as first_message │
└──────────────────────────────────────────────────────────┘

  No Twilio trial restrictions. No model in the dialing decision.
```

**Stack:**
- **Language / Runtime:** Jac + Jaseci — native persistent graph = zero persistence code
- **Graph:** Jac's built-in persistent graph — the graph *is* the database
- **LLM:** byllm plugin (`by llm()` on typed signatures), routed to OpenAI (gpt-4o-mini for extraction, gpt-4o for SBARPlus composition)
- **Transcription:** Deepgram Nova-3, batch mode with diarization
- **Telephony:** SignalWire (outbound PSTN, TwiML-compatible) + ElevenLabs Agents (TTS/ASR)
- **Bridge:** Node.js + Fastify + WebSocket, deployed on Render
- **Frontend:** Jac full-stack client, served from the same `jac start` process

---

## How we differentiate ourselves

### 1. The model extracts. Rules decide.

> *"The model can affect whether the facts are right. It cannot affect what counts as urgent."*

Every escalation is a deterministic graph pattern match with **zero model calls** in the firing path. R1–R6 are pure graph predicates. A fall is a fall — not something the model "feels" is urgent. This separation is the product's entire safety argument, and it's enforced in the type system, not in code review.

### 2. Every claim has a paper trail

Click any line in the SBAR-plus report → the graph lights up the exact source episodes: nursing note, device reading, or spoken transcript — with author/device and timestamp. This is the "five-second wow" that proves the graph is load-bearing. Not a black box, not a summary you have to trust.

### 3. The graph didn't change to absorb a new modality

Sensor data and spoken conversation use the same `Episode` shape as a nursing note. `source` changes. `author` changes. Nothing downstream changes. Three input modalities, one ingestion path, one consolidation walker, provable in one file (`consolidate.jac` — zero `wearable_*` branches).

### 4. The omission panel catches what humans skip

After a spoken handoff, REM compares what the graph says should have been conveyed against what was actually said. The obligation set is deterministic (tier-0-and-above findings, past-due actions, live contradictions). Only one LLM call per claim: "was this mentioned?" Not "should this have been?" — that question belongs to the graph.

### 5. Non-destructive by construction

Nothing is ever deleted. Salience decides what gets airtime in the summary, not what exists in the record. A suppressed claim is one click away. This is a legal and safety non-starter for real deployment — and it's enforced at the node/edge level, not by convention.

### 6. The restraint is the product

> *"142 findings. 3 calls."*

Tripwire runs six rules over an entire five-day graph. Most findings land silently in the next handoff (Tier 0). A few get dashboard flags or push notifications (Tiers 1–2). Only the ones a human must act on *right now* ring a phone (Tier 3). Zero false positives on 40 deliberately planted near-miss decoys. The false-positive rate is the number that matters — it's what causes nurses to stop answering pages.

---

## Run it

### Setup

```bash
jac install byllm            # deps into .jac/venv
cp .env.example .env         # fill in API keys
```

### Tests — deterministic, no API key, no network

```bash
jac clean --all --force
for f in decay retrieve consolidate compose tripwire escalate fixture; do jac test $f.jac; done
jac test eval/metrics.jac
```

### Deterministic end-to-end (seed → tripwire → escalate)

```bash
jac clean --all --force && jac run driver.jac
```

### Live pipeline (with real LLM calls)

```bash
jac clean --all --force && REM_LIVE=1 jac run pipeline_demo.jac
```

### REST service

```bash
jac clean --all --force
REM_LIVE=1 jac start main.sv.jac --no-client

curl -X POST localhost:8000/walker/SeedGraph  -d '{}'
curl -X POST localhost:8000/walker/Consolidate -d '{}'
curl -X POST localhost:8000/walker/Tripwire   -d '{"now_ref":1712347200.0}'
```

Swagger at `/docs`, graph at `/graph`.

### Telephony bridge

See [`bridge/README.md`](bridge/README.md). Hosted on Render; `adapters/voice.jac` POSTs to it at the `BRIDGE_URL` in `.env`.

---

## Verified numbers (live run over 5-day fixture)

```
consolidate   353 → 36 live nodes   (320 noise archived, 89.8% compression)
tripwire      7 findings fired, rules R1–R6, 3 tier-3 (phone), 0 / 40 decoys
escalate      Acknowledged edge written, read-back OK
eval          fact survival  REM 11/12 vs naive 6/12
              false positives 0 / 40      contradictions 1 / 1
              decline caught  yes (4-day lead)     fall latency 8.0 s
              alarm ratio 7 : 3     confusion TP 11 / FN 1 / FP 0 / TN 40
```

---

## Project docs

- [`docs/REM-PRD.md`](docs/REM-PRD.md) — Full product spec
- [`docs/WORKPLAN.md`](docs/WORKPLAN.md) — Two-person work split
- [`docs/handoff-A.md`](docs/handoff-A.md) — Graph core handoff (Person A)
- [`docs/handoff-B.md`](docs/handoff-B.md) — Boundary & voice handoff (Person B)
- [`bridge/README.md`](bridge/README.md) — Telephony bridge deploy & design notes
- [`docs/elevenlabs-agent.md`](docs/elevenlabs-agent.md) — ElevenLabs agent configuration
