# Handoff — Person A: Graph Core

Read first: [`docs/REM-PRD.md`](./REM-PRD.md) §6, §7, §8, §12 · [`docs/WORKPLAN.md`](./WORKPLAN.md) §2–§4 (ownership + contracts).

**You own the graph interior.** Everything that reads or writes graph structure. You never touch the client, the seed generator, or any external provider SDK.

**You are blocked by nobody after hour 3.** B's stubs (`place_call`, `transcribe`) land at hour 3 and always return success. Code against a 20-episode hand-written JSON until B's real fixture arrives — the real one is a drop-in.

---

## Scope

| Deliverable | PRD ref | Hours |
|---|---|---|
| `schema.jac` — nodes, edges, `IPASS` objs | §6.2, §6.4 | 0–2 |
| `contracts.jac` — cross-seam objs + signatures, then **freeze** | WORKPLAN §3 | 0–2 |
| DeepSeek `-> IPASS` validation, routing decision | §10.4 | 1–2 |
| `decay.jac` + retrieval walker | §6.2 | 6–8 |
| `consolidate.jac` — Replay / Abstract / Reconcile / Prune | §6.3 | 8–13 |
| `compose.jac` — I-PASS assembly | §6.4 | 8–13 |
| `tripwire.jac` — R1–R4, tier table, suppression | §7 | 17–19 |
| `escalate.jac` — chain walk, `Acknowledged` edges | §8 | 20–22 |
| `eval/` — the five metrics | §12 | 22–23 |

## Non-negotiable invariants

These are the product's entire safety argument. Enforce them in types, not in review.

1. **`Clinical` construction requires a non-empty `Derived` set.** If `by llm()` cannot cite it, the node does not exist. Reject at construction, not after.
2. **≥3 episodes before abstraction.** Hard floor. Two is a hallucination.
3. **Nothing is ever `del`'d.** Losers get `suppressed = true`, pruned episodes get `archived = true`. You will want to roll back on stage.
4. **No model in the firing decision.** `fires()` is pure graph predicate. If you find yourself writing `by llm()` inside `tripwire.jac`, stop.
5. **Fire writes a `Fired` edge; rules require absence of a recent one.** Acknowledgment suppresses until *new* evidence (a 4th observation), not until re-read.

## Traps

- **`drop_params = true` fails silently** (§10.4). Set `verbose = true` at hour 0 and actually read the logged calls. If nested `IPASS` degrades, you find out at hour 2 or at hour 14 — pick.
- **Reconcile is O(n²)** (§15). Gate pairs by subject tag or embedding similarity *before* the LLM call, or one sweep eats the budget.
- **Do not run consolidation live in the demo** (§13). Persist the post-sweep graph and replay the traversal from a recorded log. Build the log emitter as part of `Consolidate` from the start — retrofitting it at hour 22 is miserable.
- Decay τ and the thresholds (3 observers / 72h / 24h) are hand-tuned. Leave them as named constants at the top of the file, not inline literals — you will tune them during eval.

## Done when

`/walker/Consolidate` drops 412 → ~80 nodes, `/walker/Compose` returns a clean nested `IPASS`, `/walker/Tripwire` fires on all 4 planted findings and **zero of B's 40 decoys**, and `/walker/Escalate` writes an `Acknowledged` edge against B's stub call.

---

## Parallel agent split

Five agents. A1 must merge before A2–A4 run against real data, but all five can be **written** concurrently against the frozen schema — that is why the schema freezes at hour 2.

Each agent writes only the files its task names. Every task leaves one runnable `assert`-based self-check; no test framework.

### A1 — Schema + decay + retrieval
**Writes:** `schema.jac`, `contracts.jac`, `decay.jac`, `retrieve.jac`
**Reads:** PRD §6.2
Node/edge/obj definitions verbatim from §6.2 and §6.4. Decay formula with τ and access-count boost as named constants. Retrieval walker bumps `last_accessed` and boosts strength.
**Self-check:** episode strength after 48h with 0 accesses < strength with 5 accesses; assert exact decay values against hand-computed numbers.
**Done when:** schema loads, `contracts.jac` frozen and announced to B.

### A2 — Consolidate (the big one)
**Writes:** `consolidate.jac`
**Reads:** PRD §6.3, `schema.jac`
Four phases. Phase 1 pure traversal, no LLM. Phase 2 abstraction with the ≥3 floor. Phase 3 reconcile with subject-tag gating before any LLM call, `Contradicts` edge, loser suppressed. Phase 4 prune to `archived`, never `del`. Emit a step log for demo replay.
**Self-check:** a 2-episode cluster produces zero `Clinical` nodes; a 3-episode cluster produces one with 3 `Derived` edges; a suppressed loser is still reachable by traversal.
**Done when:** node count drops on the real fixture and every `Clinical` cites ≥3 sources.

### A3 — Compose + model routing
**Writes:** `compose.jac`, `jac.toml`
**Reads:** PRD §6.4, §10.3, §10.4
Run the hour-2 validation first: 10 throwaway `-> IPASS` calls against DeepSeek with hand-written inputs. If nested structs come back clean 10/10, drop the second model and save the money; otherwise route `compose_handoff` to the stronger model per §10.4. Record the result in the PR description — B's demo script depends on which way this went.
**Self-check:** assert `IPASS.action_list` is a non-empty `list[Action]` with populated fields, 3 runs.

### A4 — Tripwire
**Writes:** `tripwire.jac`
**Reads:** PRD §7
R1–R4 as pure graph predicates. Static tier lookup on `(rule_type, acuity, time_sensitivity)`. Clock gate: can-wait-until-0700 at 0300 → tier 0. `Fired` edge suppression, re-opened only by new evidence.
**Self-check:** the 3-desaturation fixture fires R1; the same fixture with 2 distinct authors does not; firing twice in a row produces one `Fired` edge.
**Done when:** zero fires across B's 40 decoys. This number is the pitch (§12).

### A5 — Escalate + eval
**Writes:** `escalate.jac`, `eval/`
**Reads:** PRD §8, §12
Walker visits `Clinician` chain, calls B's `place_call()`, writes `Acknowledged(readback_ok=…)` on success and disengages, otherwise keeps traveling. Eval harness computes the five §12 metrics and prints the confusion matrix.
**Self-check:** with a stub that refuses the first two clinicians, assert the walker reaches the third and stops there.
**Depends on:** A4 for real findings. Write against a hand-built `Clinical` until then.

---

## Suggested skills

- `superpowers:dispatching-parallel-agents` — for the A1–A5 fan-out above
- `superpowers:systematic-debugging` — when byLLM returns malformed nested structs; do not guess at prompt tweaks
- `superpowers:test-driven-development` — the invariants in this doc are assertions before they are code
- `context7` / `everything-claude-code:docs-lookup` — Jac, Jaseci, and byLLM syntax. Do not write Jac from memory; the language moves.
