# REM — Product Requirements Document

**Clinical handoff memory, built on a consolidating graph.**

JacHacks submission · Tracks: Social Impact (primary), Agentic AI (secondary), Best Use of Jaclang
Status: Draft v1 · Build window: 24 hours

> Name is a placeholder. REM = the sleep stage where memory consolidation happens. Alternatives: Vigil, Handoff, Nightshift.

---

## 1. One-liner

**A hospital handoff is a memory consolidation event. We built one.**

REM ingests everything that happens to a patient across a shift, consolidates it into a provenance-linked belief graph overnight, and emits a structured I-PASS handoff — plus a phone call to the on-shift nurse when, and only when, a deterministic rule fires on the graph.

---

## 2. Problem

Handoffs are the moment patient care, responsibility, and information transfer between caregivers. They are also where patients get hurt. Institutions mandate structured frameworks — SBAR, I-PASS — precisely because unstructured handoffs fail.

The failures are **communication and environmental**, not primarily time. Structured handoffs actually *save* time by eliminating repetitive chatter. The real breakdowns:

| Failure mode | What happens | Why current tools miss it |
|---|---|---|
| **The "why" dies first** | Day 1: ceftriaxone → rash → switched to vanc. By shift 6, every note says "on vanc." Nobody knows why. | Summaries carry state, not causation. The reasoning edge is dropped. |
| **Copy-forward zombies** | "Suspected sepsis" enters day 1, cultures negative day 2, still riding along day 5. | Each shift inherits the prior note. Nothing tracks *last verified* vs. *last asserted*. |
| **Cross-shift patterns** | Three nurses each note one nighttime desaturation on their own shift. No individual note is alarming. Nobody sees three. | Every tool is bounded by a shift. Nothing looks across them. |
| **Interrupted handoff** | Report starts, pager goes off, restart from the top or skip sections. | No resumable state. Handoff is a conversation, not an object. |

Every one of these is a **graph problem** presented as a document problem.

---

## 3. Thesis

Three claims the product is built on:

1. **A handoff is compression.** Twelve hours of episodic detail → a semantic summary that survives into the next shift. This is exactly memory consolidation, performed badly, in a hallway, from recall.
2. **I-PASS is a type, not a template.** Given a typed output struct, `by llm()` generates the composition step. The schema *is* the specification.
3. **Urgency is a rule, not a judgment.** The model extracts and composes. A deterministic rule engine decides when the phone rings. This is the difference between a system a hospital could adopt and a demo.

---

## 4. Goals / Non-goals

### Goals
- G1 — Produce a reviewable I-PASS handoff from raw multi-source episodes.
- G2 — Preserve causal provenance: every assertion traces to source episodes with author and timestamp.
- G3 — Detect contradictions and unverified drift across shifts.
- G4 — Surface patterns invisible within a single shift.
- G5 — Escalate by phone on deterministic rules, with measured false-positive rate.
- G6 — Make the graph *visibly* load-bearing to a judge in under 10 seconds.
- G7 — Accept spoken handoffs as input and flag what the conversation omitted.

### Non-goals
- Not a diagnostic tool. Zero clinical inference.
- Not autonomous. The outgoing clinician reviews, edits, and signs. REM never speaks directly to the incoming clinician as authority.
- No real PHI. Synthetic data only, stated on a slide.
- No EHR integration. Mock ingestion adapters.
- No HIPAA/BAA posture. Out of scope for a 24h build; noted as required future work.

---

## 5. Users

**Primary — Outgoing nurse (Maya, RN, med-surg).** End of a 12-hour shift. Needs a draft handoff she can review in 90 seconds and correct in 3. Trust requires seeing where each line came from.

**Secondary — Incoming nurse (Dev, RN).** Needs to know what changed, what's unverified, and what nobody has followed up on.

**Tertiary — Charge nurse.** Receives escalation when the primary doesn't acknowledge.

---

## 6. Architecture

### 6.1 Two-layer memory

**Episodic nodes** — raw, timestamped, verbatim, attributed. Nursing notes, vitals, med administration, labs, family-reported observations. Cheap to create. Decay fast.

**Semantic nodes** — clinical beliefs distilled from **≥3** episodes. Decay slowly. Every one carries `Derived` edges to its sources.

> **Extraction, never generation.** A semantic node may only assert what is traceable to source episodes. Enforce in the type: a `Clinical` node requires a non-empty `Derived` set at construction. If `by llm()` can't cite it, it doesn't exist.

> **Decay governs salience, not deletion.** Nothing is ever removed from a clinical record — legal and safety non-starter. `strength` answers "how much does this deserve airtime in the next handoff." Low-strength episodes drop out of the *summary*, stay in the graph, one click away.

### 6.2 Schema

```jac
node Episode {
    has content: str;
    has source: str;          # "nursing_note" | "vitals" | "mar" | "lab" | "family"
    has author: str;
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
node Handoff { has ipass: IPASS; has shift: str; has signed_by: str; }
node Clinician { has name: str; has phone: str; has role: str; }

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

### 6.3 Walkers

**`Consolidate`** — runs per shift boundary (or on a demo button). Four phases:

1. **Replay** — enter at recent episodes, hop to associatively-near neighbors, assemble working set. Pure traversal, no LLM.
2. **Abstract** — for clusters of ≥3 related episodes, `by llm()` extracts the invariant → new `Clinical` node + `Derived` edges. The ≥3 floor is a hallucination guard; generalize from one episode and the model will invent.
3. **Reconcile** — for `Clinical` pairs sharing subject matter, `by llm()` classifies duplicate / refinement / contradiction / unrelated. Duplicates merge and union provenance. Contradictions get a `Contradicts` edge; recency + support count picks the live side. **Loser is suppressed, not deleted** — you must be able to explain why the system changed its mind.
4. **Prune** — episodes below the strength floor whose content is fully captured by a semantic parent get `archived = true`. Never `del`.

**`Compose`** — assembles the I-PASS from surviving semantic nodes + high-strength episodes.

**`Tripwire`** — evaluates deterministic rules against graph state after consolidation.

**`Escalate`** — walks the escalation chain, placing calls until acknowledged.

### 6.4 I-PASS composition

```jac
obj Action { has task: str; has owner: str; has due: str; }
obj IfThen { has trigger: str; has response: str; }

obj IPASS {
    has illness_severity: str;      # "stable" | "watcher" | "unstable"
    has patient_summary: str;
    has action_list: list[Action];
    has contingencies: list[IfThen];
    has synthesis: str;
}

def compose_handoff(
    episodes: list[Episode],
    beliefs: list[Clinical]
) -> IPASS by llm();
```

The struct is the prompt. No prompt engineering, no output parsing, no retry-on-malformed-JSON. This is the single clearest demonstration of Jac's meaning-typed model on a framework hospitals already mandate.

### 6.5 Handoff chaining

Each `Handoff` node links to the prior via `Follows`. Two payoffs:
- **Resumable.** Interrupted mid-report → resume at the exact node instead of restarting. Directly addresses the environmental-chaos failure mode.
- **Queryable history.** "When did this claim first appear, and has anyone confirmed it since?" is a traversal.

---

## 7. Tripwire: how it decides to call

The LLM does **extraction** and **composition**. A rule engine does **decision**. Firing is a subgraph pattern match with no model in the loop.

### 7.1 Rules

| # | Rule | Pattern | Catches |
|---|---|---|---|
| R1 | **Corroboration** | `Clinical` with ≥3 `Derived` edges, ≥3 distinct authors, spanning ≥2 shifts, within 72h, category in `WATCHED` | Cross-shift patterns (the desaturations) |
| R2 | **Live contradiction** | `Contradicts` lands where the losing claim still has an active `Justifies` → running `Action` | Sepsis ruled out, antibiotics still running |
| R3 | **Unverified drift** | `last_asserted − last_verified > 24h` on a claim justifying an active intervention | Copy-forward zombies |
| R4 | **Orphaned action** | `Action` past `due` with no `Completed` edge | Dropped follow-ups |

```jac
def fires(n: Clinical) -> bool {
    return len([n -->:Derived:-->]) >= 3
        and distinct_authors(n) >= 3
        and span_hours(n) <= 72
        and n.category in WATCHED
        and not recently_fired(n);
}
```

None of these are expressible as a threshold on a scalar. That's the argument for the graph.

### 7.2 Severity tiers — the alarm-fatigue control

Firing ≠ phone call. Tier is a static lookup on `(rule_type, patient_acuity, time_sensitivity)`:

| Tier | Channel |
|---|---|
| 0 | Appears in next handoff (**default** — most findings die here) |
| 1 | Dashboard flag |
| 2 | Push notification |
| 3 | **Phone call** |

Plus a clock gate: if the finding can wait for the 0700 handoff and it's 0300, drop to tier 0. **The phone rings only when the delay itself is the harm.**

Report the ratio in the pitch: *"142 findings. 3 calls."* The restraint is the product.

### 7.3 Suppression

Firing writes a `Fired` edge. Rules require absence of a recent one. Acknowledgment suppresses until **new evidence** arrives — a fourth desaturation re-opens; re-reading the same three does not. Without this you ship a machine that calls someone nine times about one thing.

### 7.4 The honest seam

Extraction feeds the rules, so the model does influence firing. Name it on stage:

> **The model can affect whether the facts are right. It cannot affect what counts as urgent.**

The first half is checkable — every typed observation links to source text, verifiable in two seconds. "The model felt this was urgent" is checkable by nobody. That asymmetry is the architecture's whole justification.

---

## 8. Escalation & voice

Escalation is a path in the graph, and the walker walks it.

```jac
walker Escalate {
    has finding: Clinical;
    can page with Clinician entry {
        result = place_call(here.phone, speak(self.finding));
        if result.acknowledged {
            here +>:Acknowledged(at=now(), readback_ok=result.readback):+> self.finding;
            disengage;
        }
        visit [-->](`?Clinician);   # primary RN → charge RN → attending
    }
}
```

Unanswered → keep traveling. Acknowledged → write edge, disengage. Not a metaphor for escalation; it *is* escalation.

**Verbal read-back required** before acknowledgment counts. Closed-loop communication is real clinical practice, it's a good stage beat, and it gives the walker a real termination condition instead of a timeout.

### Call script — 40 seconds, hard cap

> "This is the handoff assistant calling about bed 14, Room 3B. Consolidation flagged a pattern across the last three shifts: nocturnal oxygen desaturation at 0210, 0145, and 0320, documented separately by three different nurses. No single shift note flagged it. Requesting overnight continuous pulse oximetry. Can you read back the request?"

Identify → one finding → provenance → ask → read-back. Note that it names its own evidence.

---

## 9. Verbal handoff capture (ambient input)

> Terminology: this is **speech-to-text**, not TTS. We transcribe spoken handoffs and structure them; we don't read documents aloud.

### 9.1 Why this is the highest-value input

Nurses shouldn't type. But more than convenience: **the spoken handoff is where the reasoning lives.** "We swapped to vanc because she got a rash on the ceftriaxone" gets said in a hallway and never written down. That's failure mode #1 from §2 — the "why" dies first — and ambient capture is the direct fix, not a side feature.

It also fixes the demo's weakest moment. Without it, the pitch opens with "we generated 400 synthetic episodes." With it, it opens with two clinicians talking.

### 9.2 Where it fits — nowhere new

Transcript utterances become `Episode` nodes with `source = "verbal_handoff"` and `author` = the diarized speaker. They flow into the **exact same** `Consolidate` walker as every other source.

**Zero new downstream architecture.** That's the point worth making on stage: the graph didn't need to change to absorb a new sensory modality. Everything already built — decay, abstraction, reconciliation, tripwires — applies to speech for free.

```jac
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

**Diarization is required, not optional.** Provenance needs an author — "who said this" is a first-class field on `Episode`, and an unattributed transcript breaks the entire trust model.

### 9.3 Omission check — the standout feature

After the conversation ends, compare **what the graph says should have been conveyed** against **what was actually said**.

The set of obligations is deterministic — tier-0-and-above findings, actions past due without a `Completed` edge, live contradictions, any claim justifying an active intervention. That's a graph query, no model involved. The only LLM call is a per-claim boolean:

```jac
def was_conveyed(claim: str, transcript: str) -> bool by cheap();
```

Output:

> **Not conveyed in this handoff (3):**
> · Reason for vanc switch — ceftriaxone rash, day 1
> · Overnight desaturation pattern — 3 events, 3 observers
> · Wound check due 0400 — no completion recorded

Same architectural principle as the tripwire: **the model checks coverage, the graph decides what counts as required.**

This is post-hoc, not real-time. A nudge mid-sentence is worse UX and much harder to build; "here's what you missed, want to add it?" is nearly as useful and vastly safer to demo.

### 9.4 Spoken/recorded conflict

If a speaker asserts something the graph knows was ruled out — "she's septic, still on abx" when cultures came back negative on day 2 — that's a `Contradicts` edge sourced from speech, surfaced in the same review pane. Cheap to add once §9.3 exists.

### 9.5 Provider

**Deepgram.** Nova-3, batch mode, diarization enabled.

| | |
|---|---|
| Free credit | **$200, no credit card, no expiration** — roughly 43,000 minutes |
| Base rate | ~$0.0043/min pre-recorded (batch) |
| Diarization | Paid add-on, ~$0.002/min — negligible against $200 |
| Streaming | ~$0.0077/min if you ever need it |

Alternatives: AssemblyAI (~$0.0025/min batch, $50 free credit, stronger on noisy/accented audio); OpenAI transcription (~$0.003–0.006/min, **no diarization** — disqualifying here).

**Use batch, not streaming.** It's 40–50% cheaper, dramatically simpler, and live streaming in a loud hackathon room is a coin flip. Keep Deepgram separate from your ElevenLabs budget — the ElevenLabs free tier is only 15 minutes and it's already committed to escalation calls.

### 9.6 Demo handling

**Pre-record a 45-second scripted handoff conversation.** Two voices, deliberately including one causal explanation that exists nowhere in the written record, and deliberately *omitting* two things the graph knows are required.

Play the file, show the transcript resolve, show it enter the graph, show the omission panel populate. That's a stronger and far more reliable beat than a live mic. Add live capture only if you're ahead at hour 20.

---

## 10. Tech stack

### 10.1 Core

| Layer | Choice | Why |
|---|---|---|
| Language / runtime | **Jac + Jaseci** | Requirement, and genuinely the right tool: persistent per-user root graph = zero persistence code |
| Graph store | Jac's native persistent graph | The graph *is* the database. No ORM, no schema migration |
| LLM calls | **`byllm`** plugin (`jac install byllm`) | `by llm()` on typed signatures — extraction and composition |
| Model | **DeepSeek** via byllm/LiteLLM (see §10.3) | Cost. Split routing for the one call that can't be flaky |
| Server | `jac start main.jac` | REST + auth + Swagger + persistence, no code |
| Package mgmt | `jac install` / **pnpm** for frontend deps | — |

### 10.2 Frontend — Jac full-stack (LOCKED)

**Decision: Option A. Everything in Jac, served by `jac start main.jac`.** No Next.js, no separate frontend process, no fetch layer, no CORS.

Rationale: the rubric names *"single-file full-stack development"* as one of four scored criteria alongside `by llm()`, walkers, and graph-native modeling. A separate frontend forfeits one of the four for UI velocity we don't need — this is a demo with roughly four screens.

`jac-client` is React-like and pulls from npm, so pnpm-installed packages are still available via `[dependencies.npm]` in `jac.toml`.

**Screens:**
1. Split-screen comparison (naive vs. REM I-PASS)
2. Graph view with provenance highlighting on click
3. Consolidation run view (walker animation, live counts)
4. Tripwire / escalation log

**De-risking, hour 0–1:** spike a hello-world that renders one node from the graph, and confirm your force-directed graph library loads through `[dependencies.npm]`. That's a 30-minute check, and it's the only unknown in this path.

**Contingency if the client layer is genuinely broken (not merely unfamiliar):** the walkers already auto-expose as REST endpoints, so a minimal static HTML + vanilla JS page hitting those endpoints is a ~1 hour escape hatch that still avoids a second framework. Don't reach for it before hour 14.

### 10.3 External providers

| Provider | Use | Plan | Notes |
|---|---|---|---|
| **ElevenLabs Agents** | Outbound call + voice | Free tier: 15 min/mo, 4 concurrent | Native outbound calling — no separate telephony vendor. Test calls bill at half rate. ~20–30 demo calls available |
| **Deepgram** | Verbal handoff transcription + diarization | **$200 free credit, no card, no expiration** | Nova-3 batch, ~$0.0043/min + ~$0.002/min diarization. Effectively free at our volume. See §9.5 |
| **DeepSeek API** | `by llm()` backend — extraction, reconcile | Pay-as-you-go | Routed via byLLM → LiteLLM. Budget ~$2–5 |
| Fallback model | `compose_handoff` only | Pay-as-you-go | ~6 calls per demo run. Pennies. See §10.4 |
| — | Seed data generation | Either | One-time, offline |

```toml
# jac.toml
[plugins.byllm.model]
default_model = "deepseek/deepseek-chat"
api_key = "${DEEPSEEK_API_KEY}"

[plugins.byllm.call_params]
temperature = 0.2          # extraction, not creativity

[plugins.byllm.litellm]
drop_params = true         # ⚠️ see §10.4
```

### 10.4 Model routing — the one thing to watch

byLLM makes your Jac type the LLM's output schema: `-> MyObj` is supposed to guarantee a properly structured object. How reliably that holds depends on the provider's structured-output support, and DeepSeek's is weaker than OpenAI's or Anthropic's.

Note also that `drop_params = true` **silently discards** params a provider doesn't support. If schema enforcement degrades, it degrades quietly rather than erroring. Set `verbose = true` early and actually read the logged calls.

**Route by structural difficulty:**

| Call | Return type | Volume | Model |
|---|---|---|---|
| `extract_observation` | flat struct | ~400 | DeepSeek |
| `classify_pair` | enum | hundreds (O(n²)) | DeepSeek |
| `abstract_belief` | `str` | ~30 | DeepSeek |
| **`compose_handoff`** | **nested `IPASS`** (`list[Action]`, `list[IfThen]`) | **~6** | **Stronger model** |

The volume is in the first three, which is where the cost lives and where DeepSeek is fine — flat structs and enum classification are easy. `compose_handoff` is the one that produces the artifact the entire demo is built around, and it runs six times. Paying full rate for six calls is not a budget line.

byLLM supports per-call overrides, so this is a one-argument change:

```jac
glob cheap = Model(model_name="deepseek/deepseek-chat");
glob solid = Model(model_name="<stronger-model>");

def classify_pair(a: str, b: str) -> Relation by cheap();
def compose_handoff(e: list[Episode], b: list[Clinical]) -> IPASS by solid();
```

**Validate this at hour 2, not hour 14.** Write one throwaway `-> IPASS` call against DeepSeek with hand-written inputs and see whether the nested struct comes back clean ten times in a row. If it does, drop the second model entirely and save the money. If it doesn't, you've learned it while it's cheap to fix.

### 10.5 Graceful degradation

Build the call layer **swappable, not load-bearing.** If telephony dies, `Escalate` still runs and still writes `Acknowledged` edges — you render it as an on-screen notification instead of audio. Same architecture, less theater. Design it this way from the start.

---

## 11. Data — synthetic, and say so

**One patient. Five-day admission. Six shifts. ~400 episodes.**

Sources: nursing notes, vitals, med administration records, labs, family-reported observations. That last one covers "everything that happened to this patient" without ambient audio you can't build in 24h.

Generate with an LLM in ~20 minutes, but **plant four things deliberately:**

1. **The ceftriaxone rash.** Day 1 causal chain: ceftriaxone → rash → switch to vanc. Must survive to shift 6 with the *why* intact. → tests `Causes` preservation.
2. **The sepsis zombie.** "Suspected sepsis" day 1, cultures negative day 2, antibiotics still running day 5. → tests R2.
3. **The three desaturations.** 0210 / 0145 / 0320 across three shifts, three different nurses, none individually alarming. → tests R1, and is the demo climax.
4. **Noise.** ~40 variations of "ambulated in hallway, tolerated well." → tests pruning.

**Plus ~40 decoys that must NOT fire.** Near-misses specifically: two observers instead of three, a contradiction on an inactive order, a stale claim justifying nothing, an `Action` completed one minute late.

---

## 12. Evaluation

Because firing is deterministic, you can *measure* it — which almost nobody at a hackathon does.

| Metric | Method | Target |
|---|---|---|
| **Fact survival** | Plant 12 must-know facts at admission; count survivors at shift 6, naive vs. REM | REM ≥ 11/12, naive ≤ 6/12 |
| **False positive rate** | 40 planted decoys, count spurious fires | **0** |
| **Contradiction detection** | Planted zombies caught | 3/3 |
| **Compression** | Nodes and tokens, before vs. after | ~400 → ~80 nodes; ~70% token reduction |
| **Alarm ratio** | Findings vs. tier-3 calls | Report honestly (e.g. 142 : 3) |

**False positives are the number that matters** — they're what causes nurses to stop answering pages. "Zero false alarms across 40 planted decoys," with decoys shown, is a stronger claim than any live-call theater.

State clearly: thresholds (3 observers, 72h window, 24h staleness) are hand-tuned on synthetic data. Real deployment needs clinical validation. **Saying this is a strength, not a weakness.**

---

## 13. Demo — 3 minutes

| Time | Beat |
|---|---|
| **0:00–0:15** | **Hook.** "A hospital handoff is a memory consolidation event. So we built one." |
| **0:15–0:50** | **Play the recorded handoff.** Two clinicians, 45 seconds. Transcript resolves live with speaker labels. One causal explanation is spoken that exists nowhere in the written record. Utterances land in the graph as episodes. |
| **0:50–1:15** | **Omission panel populates.** Three things the graph knows were required and weren't said — including the desat pattern. *"Nobody forgot. Nobody could have known."* |
| **1:15–1:35** | **Split screen, shift 6.** Left: what the incoming nurse gets today — last note plus accumulated copy-forward, ~4,000 words. Right: REM's I-PASS, ~300 words, rash warning present, sepsis claim struck through and dated. |
| **1:35–1:50** | **Click a line.** Graph lights up the exact source episodes — timestamps, authors, verified-or-not. Includes the one sourced from speech. *The five-second wow.* |
| **1:50–2:10** | **Consolidation replay.** Walker animates across nodes, counts drop 412 → 78. **Pre-computed and replayed — see below.** |
| **2:10–2:40** | **The call.** Real phone, speakerphone near the mic. Agent delivers the desaturation escalation naming its own evidence. Nurse reads back. `Acknowledged` edge appears on screen. |
| **2:40–2:55** | **The restraint slide.** 142 findings → 3 calls. Zero false positives on 40 decoys. "The model never decides to call you." |
| **2:55–3:00** | **Close.** Synthetic data disclosure. |

### Demo rules
- **Do not run consolidation live against the API.** Hundreds of LLM calls at even 2s each is minutes, not the 30 seconds you have — and that's before rate limits. Run the sweep beforehand, persist the resulting graph, and have the button replay the traversal from a recorded log. The animation is identical; it just isn't waiting on a network. Say "pre-computed" once if asked — nobody expects a live batch job in a 3-minute pitch, and the graph transformation is the claim, not the wall-clock time.
- **Record a backup video of a successful call before presenting.** Conference wifi will fail, latency will spike, or you'll get dead air. Have it cued so you can keep talking through the failure.
- Build the naive baseline early — it is both your experimental control and your left pane.
- Someone will ask about real data. Have the slide ready.

---

## 14. Build order (24h)

| Hours | Work | Gate |
|---|---|---|
| 0–1 | Repo, `jac install byllm`, ElevenLabs signup + **verify phone number**, Deepgram key, `jac start --client` hello-world spike + npm graph lib check | Phone verified, one node renders |
| 1–2 | **DeepSeek `-> IPASS` validation** — 10 throwaway calls, check nested struct fidelity | Routing decided (§10.4) |
| 2–3 | Schema + seed generator with the 4 planted findings + 40 decoys. **Record the 45s handoff audio now** — you need a teammate and they'll be asleep later | Seed data loads, audio in hand |
| 3–6 | Naive baseline retrieval (control + left pane). Then never touch it again | Baseline renders |
| 6–8 | Decay + retrieval walker | — |
| 8–13 | `Consolidate` phases 2–4 | **Must work before anything below** |
| 13–15 | Deepgram batch transcription + `IngestTranscript` walker | Transcript → episodes |
| 15–17 | Provenance-highlighting UI + graph viz | Click-to-source works |
| 17–19 | Tripwire rules + tier table + suppression | — |
| 19–20 | Omission check (`was_conveyed` + required-set query) | — |
| 20–22 | `Escalate` walker + ElevenLabs call | Degrade to notifications if blocked |
| 22–23 | Eval numbers, confusion matrix | — |
| 23–24 | Video, README, **backup call recording**, buffer | — |

### If you fall behind — cut in this order

You now have two voice features on a 24-hour budget. Something will give. Cut from the bottom:

1. **Spoken/recorded conflict (§9.4)** — nice, not load-bearing
2. **Live phone call** → degrade to on-screen notification. The `Escalate` walker still runs and still writes `Acknowledged` edges; you lose theater, not architecture
3. **Graph animation** → static before/after

**Do not cut:** consolidation, provenance click-through, omission check. Those three *are* the project. The phone call is the most memorable beat but the least essential — protect the omission check ahead of it, since it addresses the stated problem more directly and carries none of the telephony risk.

---

## 15. Risks

| Risk | Mitigation |
|---|---|
| Reconcile is O(n²) over pairs — one sweep eats the API budget | Gate by embedding similarity or subject tag **before** calling the LLM |
| Live call fails on stage | Pre-recorded backup, cued |
| **DeepSeek returns malformed nested `IPASS`** | Validate at hour 2 with a throwaway call. Route `compose_handoff` to a stronger model (§10.4) |
| **`drop_params` hides degraded schema enforcement** | `verbose = true` from the start; read the logged calls |
| **Latency on live consolidation** | Pre-compute and replay the traversal (§13) |
| `jac-client` unfamiliar | Hour 0–1 spike. Static HTML + REST escape hatch only after hour 14 |
| LLM invents clinical facts | ≥3-episode floor + non-empty `Derived` requirement enforced in the type |
| Destructive delete during live demo | `archived` flag, never `del` — you will want to roll back on stage |
| **Diarization mislabels speakers** | Provenance needs an author. Use a 2-speaker recording with distinct voices; verify labels before demo day |
| **Transcription mangles drug names** | Deepgram keyterm prompting with your drug list; the recorded script is yours to control |
| **Two voice features, 24 hours** | Documented cut order in §14. Omission check outranks the phone call |
| Judge challenges clinical realism | Lead with the review-and-sign framing; it's both correct and reads as sophistication |

---

## 16. Safety positioning

State these explicitly; they are differentiators, not disclaimers.

- **Draft, not directive.** The outgoing clinician reviews, edits, and signs. REM never addresses the incoming clinician as authority.
- **No clinical inference.** Extraction only. Nothing asserted that isn't traceable.
- **Deterministic escalation.** The model does not decide urgency.
- **Non-destructive.** Salience affects the summary, never the record.
- **Synthetic data.** No PHI, no HIPAA claims, no BAA. Real deployment requires clinical validation of thresholds and a proper compliance posture — out of scope for 24 hours.

---

## 17. Out of scope / future

- EHR integration (FHIR ingestion adapters)
- Real-time (streaming) capture and mid-conversation nudges; bedside ambient capture beyond the handoff itself
- Multi-patient load view for a full unit
- Threshold learning from acknowledgment/dismissal feedback
- Clinical validation study, HIPAA posture, BAAs

---

## Appendix — pitch lines worth memorizing

- *"A handoff is a memory consolidation event. So we built one."*
- *"The model can affect whether the facts are right. It cannot affect what counts as urgent."*
- *"142 findings. 3 calls."*
- *"No single shift note flagged it. Three nurses each saw it once."*
- *"Nothing is deleted. Salience decides what gets airtime, not what exists."*
- *"Nobody forgot. Nobody could have known."* — for the omission panel
- *"The graph didn't change to absorb speech. It was already the right shape."*
