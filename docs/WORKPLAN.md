# REM — Two-Person Work Split

Source of truth: [`docs/REM-PRD.md`](./REM-PRD.md). This document only covers **who builds what, against which interfaces, and when they sync.** Nothing here restates the PRD.

- Person A → [`docs/handoff-A.md`](./handoff-A.md) — **Graph core.** Schema, decay, consolidation, composition, tripwire, escalation walker, eval.
- Person B → [`docs/handoff-B.md`](./handoff-B.md) — **Edges.** Seed data, naive baseline, voice adapters, transcript ingest, omission check, UI, demo.

---

## 1. The seam

The split is **graph interior vs. graph boundary**. A owns everything that reads and writes graph structure. B owns everything that produces episodes for it or renders results out of it.

This works because §9.2 of the PRD already guarantees it: new input modalities require **zero new downstream architecture**. B can build the entire speech path against `Episode` alone, and A can build consolidation against a 20-episode hand-written fixture. Neither blocks the other after hour 3.

## 2. File ownership — hard boundary

Do not edit a file you do not own. If you need a change in the other person's file, message them; do not "just fix it."

| Path | Owner | Notes |
|---|---|---|
| `schema.jac` | **A** | **FROZEN after hour 2.** Both read constantly. Changes after freeze require B's ack. |
| `contracts.jac` | **A**, then frozen | Shared `obj` definitions used across the seam (§3). |
| `decay.jac`, `retrieve.jac` | A | |
| `consolidate.jac` | A | Replay / Abstract / Reconcile / Prune |
| `compose.jac` | A | `IPASS`, model routing (PRD §10.4) |
| `tripwire.jac` | A | R1–R4, tier table, suppression |
| `escalate.jac` | A | Walks the `Clinician` chain, calls B's adapter |
| `eval/` | A | Metrics table, PRD §12 |
| `seed/` | **B** | Generator + `seed/patient.json` fixture |
| `baseline.jac` | B | Naive control + left pane |
| `adapters/voice.jac` | B | `transcribe()`, `place_call()` — swappable, PRD §10.5 |
| `ingest.jac` | B | `IngestTranscript` |
| `omission.jac` | B | `was_conveyed()` + panel query, consumes A's `required_findings()` |
| `client/` | B | All four screens, graph viz |
| `main.jac` | **shared, append-only** | Import lines only. Never reorder. Conflicts here are your own fault. |
| `README.md`, `docs/` | B | Except this file and the handoffs. |

## 3. Frozen contracts — write these first, hour 0–2

These are the only places the two tracks touch. Both people stub the other side and code against the stub. **Land these before anything else.**

```jac
# contracts.jac  — owned by A, frozen at hour 2

obj Segment    { has text: str; has speaker: str; has start: float; }
obj CallResult { has acknowledged: bool; has readback: bool; has transcript: str; }

# --- B provides, A consumes -------------------------------------------
def transcribe(path: str) -> list[Segment];       # adapters/voice.jac
def place_call(phone: str, script: str) -> CallResult;

# --- A provides, B consumes -------------------------------------------
def required_findings() -> list[Clinical];        # obligations set, PRD §9.3
def provenance(claim_id: str) -> list[Episode];   # click-to-source, PRD §13
```

Plus the seed fixture shape, owned by B:

```json
[{"content": "...", "source": "nursing_note", "author": "RN Maya", "at": 1712345678.0}]
```

**Stubs, delivered hour 3, non-negotiable:**
- B ships `place_call()` returning `CallResult(acknowledged=true, readback=true)` immediately, and `transcribe()` returning 6 hard-coded segments. A never waits on telephony or Deepgram.
- A ships `required_findings()` returning 3 hand-built `Clinical` nodes. B never waits on consolidation to build the omission panel.
- A codes against a 20-episode hand-written JSON until B's real 400-episode fixture lands.

## 4. Walker → REST contract

`jac start main.jac` auto-exposes walkers. B's client codes against these names; A does not rename them after hour 8.

| Endpoint | Owner | Returns |
|---|---|---|
| `/walker/Baseline` | B | naive summary string (left pane) |
| `/walker/Consolidate` | A | `{before: int, after: int, log: list[Step]}` |
| `/walker/Compose` | A | `IPASS` |
| `/walker/Tripwire` | A | `{findings: list, tiers: dict, fired: list}` |
| `/walker/IngestTranscript` | B | `{episodes_created: int}` |
| `/walker/Escalate` | A | `{acknowledged: bool, chain: list[str]}` |

## 5. Sync points — 5 total, keep them short

| Hour | Sync | Exit condition |
|---|---|---|
| **0–2** | Kickoff, together | Repo up, `jac install byllm`, phone verified, `schema.jac` + `contracts.jac` frozen, `-> IPASS` routing validated (PRD §10.4), **45s handoff audio recorded** (needs both voices — do it now, not at hour 15) |
| **3** | Stub exchange | Both stubs merged. Split for real. |
| **8** | Graph live | Consolidation produces real nodes; B's client swaps off fixtures onto real endpoints |
| **15** | Speech end-to-end | Transcript → episodes → consolidation, one command |
| **20** | Integration freeze | No new features. Only eval, rehearsal, README, backup video. |

Between syncs: async only. Do not interrupt.

## 6. Cut order (unchanged from PRD §14) — who eats the cut

1. Spoken/recorded conflict (§9.4) — **B**
2. Live phone call → on-screen notification — **B drops ElevenLabs, A's `Escalate` is untouched**
3. Graph animation → static before/after — **B**

Never cut: consolidation (A), provenance click-through (A+B), omission check (B). If A is behind at hour 16, B takes `tripwire.jac` — it is the most self-contained piece A owns.

## 7. Parallel agents

Each handoff doc ends with a subagent breakdown: file-disjoint tasks that can run concurrently within one person's track. Rule for both: **an agent may only write files its task names.** Agents that need to touch a file outside their list report back instead of editing.
