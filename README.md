# REM — graph core

Long-term-care shift-handoff memory on a consolidating belief graph, fed by a
resident-worn device. See [`docs/REM-PRD.md`](docs/REM-PRD.md) for the full
product spec and [`docs/WORKPLAN.md`](docs/WORKPLAN.md) for the two-person split.

This tree is **Person A's deliverable — the graph interior** (schema, decay,
consolidation, composition, tripwire, escalation, eval). Person B's boundary
pieces (client, real seed generator, live telephony/Deepgram adapters) plug in
behind the frozen contracts in [`contracts.jac`](contracts.jac); B's voice
adapter is stubbed here in [`adapters/voice.jac`](adapters/voice.jac).

## What's here

| File | Role | PRD |
|---|---|---|
| `schema.jac` | Nodes, edges, `SBARPlus` objs, source/category vocab. **Frozen.** | §6.2, §6.4 |
| `contracts.jac` | Cross-seam obj definitions. **Frozen.** | WORKPLAN §3 |
| `decay.jac` | Decay formula + `ApplyDecay` walker (salience, never deletion) | §6.2 |
| `retrieve.jac` | Retrieval boost walker + `required_findings` / `provenance` seam fns | §6.2, §9.3, §13 |
| `consolidate.jac` | 4-phase Consolidate: Replay / Abstract / Reconcile / Prune | §6.3 |
| `compose.jac` | SBAR-plus composition (LLM fills a draft → frozen `SBARPlus`) | §6.4 |
| `tripwire.jac` | R1–R6 as **pure graph predicates**, tier table, clock gate, suppression | §7 |
| `escalate.jac` | Walks the CNA→nurse→charge→MD chain, writes `Acknowledged` edges | §8 |
| `eval/metrics.jac` | The seven §12 metrics + confusion matrix | §12 |
| `fixture.jac` | The one-resident, five-day scenario: 6 planted findings + 40 decoys | §11 |
| `main.sv.jac` | REST service — exposes every walker at `/walker/<Name>` | WORKPLAN §4 |

## Invariants (the safety argument, enforced in types)

1. A `Clinical` belief requires ≥3 source episodes (the abstraction floor) and
   carries `Derived` edges to every one — no citation, no node.
2. Nothing is ever `del`'d. Reconcile losers get `suppressed=True`, pruned
   episodes `archived=True`; both stay reachable by traversal.
3. **No model in the firing decision.** `tripwire.jac` contains zero `by llm()`.
   R5 (decline) and R6 (fall) are graph/timestamp predicates like R1–R4.
4. R6 (fall) is the deliberate exception: a single `wearable_fall` episode fires
   straight to Tier 3 and bypasses the clock gate.
5. A device episode is treated identically to a nursing note — there is no
   `wearable_*` branch anywhere in consolidation.

## Run it

Setup (once):

```bash
jac install byllm            # deps into .jac/venv
```

Tests — deterministic, no API key, no network (MockLLM / canned drafts):

```bash
jac clean --all --force
for f in decay retrieve consolidate compose tripwire escalate fixture; do jac test $f.jac; done
jac test eval/metrics.jac
```

The deterministic end-to-end (seed → tripwire → escalate; proves six fires,
zero decoys, one Acknowledged edge):

```bash
jac clean --all --force && jac run driver.jac
```

The full live pipeline (consolidation compression + real SBAR-plus). Uses the
real models — needs `OPENAI_API_KEY` (routes `gpt-4o-mini` for extraction,
`gpt-4o` for the nested SBAR composition per PRD §10.4):

```bash
jac clean --all --force && REM_LIVE=1 jac run pipeline_demo.jac
```

Without `REM_LIVE`, every LLM step falls back to a deterministic offline path so
the whole pipeline still runs — only the abstracted claim text and SBAR prose are
canned; tripwire, escalation, and eval are byte-identical.

The REST service:

```bash
jac clean --all --force
REM_LIVE=1 jac start main.sv.jac --no-client        # Swagger at /docs, graph at /graph
curl -X POST localhost:8000/walker/SeedGraph  -d '{}'
curl -X POST localhost:8000/walker/Consolidate -d '{}'
curl -X POST localhost:8000/walker/Tripwire   -d '{"now_ref":1712347200.0}'
```

## Latest verified numbers (live run over `fixture.jac`)

```
consolidate   353 -> 36 live nodes   (320 noise archived, 89.8% compression)
tripwire      7 findings fired, rules R1–R6, 3 tier-3 (phone), 0 / 40 decoys
escalate      Acknowledged edge written, read-back OK
eval          fact survival  REM 11/12 vs naive 6/12
              false positives 0 / 40      contradictions 1 / 1
              decline caught  yes (4-day lead)     fall latency 8.0 s
              alarm ratio 7 : 3     confusion TP 11 / FN 1 / FP 0 / TN 40
```

## Model routing (PRD §10.4)

The PRD specs DeepSeek; this environment routes to OpenAI via byllm/LiteLLM.
Flat structs and enum classification (consolidation extract/reconcile) →
`gpt-4o-mini`. The structurally-hard nested `SBARPlus` composition → `gpt-4o`.
byllm 0.6 cannot build an output schema for a nested obj imported from another
module, so the LLM fills a local draft that is copied into the frozen `SBARPlus`
(the byllm-guide pattern; keeps the AI and storage schemas independent).
