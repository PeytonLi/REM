# Handoff — Person B: Boundary, Voice & Demo

Read first: [`docs/REM-PRD.md`](./REM-PRD.md) §9, §10.2, §11, §13 · [`docs/WORKPLAN.md`](./WORKPLAN.md) §2–§4 (ownership + contracts).

**You own the graph boundary.** Everything that produces episodes for the graph or renders results out of it, plus every external provider. You never edit `consolidate.jac`, `tripwire.jac`, or `schema.jac`.

**You are blocked by nobody after hour 3.** A ships `required_findings()` returning 3 hand-built `Clinical` nodes at hour 3, so the omission panel and all four screens are buildable before consolidation exists.

---

## Scope

| Deliverable | PRD ref | Hours |
|---|---|---|
| `jac start --client` hello-world spike + npm graph lib check | §10.2 | 0–1 |
| **Record the 45s handoff audio** — needs a second voice, do it at hour 2 | §9.6 | 2–3 |
| `seed/` — 400 episodes, 4 planted findings, 40 decoys | §11 | 2–3 |
| Stubs for `place_call` / `transcribe` → hand to A | WORKPLAN §3 | 3 |
| `baseline.jac` — naive control + left pane, then never touch again | §13 | 3–6 |
| `adapters/voice.jac` — Deepgram batch + diarization | §9.5 | 13–15 |
| `ingest.jac` — `IngestTranscript` | §9.2 | 13–15 |
| `client/` — four screens + provenance highlighting | §10.2 | 15–17 |
| `omission.jac` — `was_conveyed()` + panel | §9.3 | 19–20 |
| ElevenLabs outbound call wiring | §8 | 20–22 |
| README, demo video, **backup call recording** | §13 | 23–24 |

## Non-negotiable

1. **Diarization is required, not optional** (§9.2). An unattributed transcript breaks the entire provenance model. Two-speaker recording, distinct voices, verify the labels before demo day.
2. **The voice layer is swappable, not load-bearing** (§10.5). If telephony dies, `place_call()` returns a `CallResult` produced by an on-screen notification instead. A's walker never knows the difference. Build it this way from hour 3.
3. **Batch, not streaming** (§9.5). 40–50% cheaper, far simpler, and live mic in a loud room is a coin flip.
4. **The 40 decoys are the product's headline number** (§12). Near-misses specifically: two observers not three, a contradiction on an inactive order, a stale claim justifying nothing, an `Action` completed one minute late. Lazy decoys make the zero-false-positive claim worthless.
5. **Say "synthetic data" on a slide.** Someone will ask.

## Traps

- **Deepgram mangles drug names.** Use keyterm prompting with your drug list. The recorded script is yours to control — no excuse for "ceftriaxone" coming back wrong.
- **ElevenLabs free tier is 15 min/month, 4 concurrent.** Test calls bill at half rate → ~20–30 demo calls total. Don't burn them debugging; use A's stub path for that.
- **Deepgram's $200 credit is separate** from the ElevenLabs budget. It is effectively free at this volume; the ElevenLabs minutes are the scarce resource.
- **Do not reach for the static-HTML escape hatch before hour 14** (§10.2). Walkers already expose as REST, so it is a ~1h fallback, but reaching for it early forfeits the "single-file full-stack" rubric criterion for velocity you don't need across four screens.
- **Record the backup call video before presenting.** Conference wifi will fail. Cue it so you can keep talking through the failure.

## Done when

Playing the recorded file resolves a diarized transcript → episodes land in the graph → omission panel populates with 3 items → split screen shows ~4,000-word naive vs. ~300-word I-PASS → clicking a line lights up its source episodes including the spoken one.

---

## Parallel agent split

Six agents. B1 and B2 are urgent (they unblock A and the demo's left pane). B4 is the long pole — start its spike at hour 0.

Each agent writes only the files its task names. Every task leaves one runnable `assert`-based self-check; no test framework.

### B1 — Seed data + stubs *(highest priority, unblocks A)*
**Writes:** `seed/gen.py`, `seed/patient.json`, `adapters/voice.jac` (stub version only)
**Reads:** PRD §11, WORKPLAN §3
One patient, 5-day admission, 6 shifts, ~400 episodes across the 5 sources. Plant all four findings from §11 exactly as specified: the ceftriaxone→rash→vanc causal chain, the sepsis zombie, the three desaturations (0210/0145/0320, three named nurses), ~40 "ambulated in hallway" noise variants. Then 40 deliberate near-miss decoys.
Ship the stub adapters in the same commit: `place_call()` → `CallResult(acknowledged=true, readback=true)`, `transcribe()` → 6 hard-coded segments.
**Self-check:** assert the fixture contains exactly 3 desaturation episodes with 3 distinct authors spanning ≥2 shifts, and that no decoy has ≥3 distinct authors.
**Done when:** A has the fixture and both stubs. Hour 3, hard deadline.

### B2 — Naive baseline
**Writes:** `baseline.jac`
**Reads:** PRD §13
Last note + accumulated copy-forward, ~4,000 words. This is both the experimental control and the demo's left pane. Build it, verify it, then never touch it again — its badness is the point.
**Self-check:** assert output word count > 3,000 and that the ceftriaxone rash *reason* is absent while "on vanc" is present.

### B3 — Deepgram + transcript ingest
**Writes:** `adapters/voice.jac` (real `transcribe`), `ingest.jac`, `audio/handoff.wav`
**Reads:** PRD §9.1–§9.2, §9.5, §9.6
Nova-3 batch with diarization. Keyterm prompt with the drug list. `IngestTranscript` maps segments → `Episode(source="verbal_handoff", author=<diarized speaker>)`. **No new downstream architecture** — if you find yourself adding a node type, you have taken a wrong turn.
The 45s script must contain one causal explanation that exists nowhere in the written record, and must deliberately omit two things the graph requires.
**Self-check:** assert every produced `Episode` has a non-empty `author` and that speaker labels are stable across the file.

### B4 — Client, four screens *(long pole — spike at hour 0)*
**Writes:** `client/`
**Reads:** PRD §10.2, §13
Hour 0–1: hello-world rendering one node, and confirm the force-directed graph lib loads via `[dependencies.npm]` in `jac.toml`. That 30-minute check is the only real unknown in this path.
Then: split-screen comparison, graph view with provenance highlighting on click, consolidation run view (replayed from A's step log, **not** live), tripwire/escalation log.
**Self-check:** clicking a composed I-PASS line calls `provenance()` and highlights ≥1 node.
**Codes against:** A's stubbed `required_findings()` / `provenance()` until hour 8.

### B5 — Omission check
**Writes:** `omission.jac`, `client/omission-panel`
**Reads:** PRD §9.3
The obligation set is a **graph query** (A's `required_findings()`) — no model. The only LLM call is the per-claim boolean `was_conveyed(claim, transcript) -> bool by cheap()`. Post-hoc, never mid-sentence.
**Self-check:** with a transcript that mentions 1 of 3 required claims, assert the panel lists exactly 2.
**Protect this ahead of the phone call** — it addresses the stated problem more directly and carries none of the telephony risk.

### B6 — ElevenLabs + demo package
**Writes:** `adapters/voice.jac` (real `place_call`), `README.md`, `demo/`
**Reads:** PRD §8, §13, §16
Outbound agent call, 40-second hard cap, script structure: identify → one finding → provenance → ask → read-back. Read-back is the walker's termination condition, so parse it honestly.
Then: README, 3-minute demo video, **backup call recording cued before presenting**, synthetic-data slide, the restraint slide (findings : calls ratio from A's eval).
**Degrades to:** on-screen notification. If this is the thing that slips, it is supposed to slip — cut item #2 in §14.

---

## Suggested skills

- `superpowers:dispatching-parallel-agents` — for the B1–B6 fan-out above
- `context7` / `everything-claude-code:docs-lookup` — Jac, `jac-client`, Deepgram Nova-3, ElevenLabs Agents. Every one of these has moved recently; do not write from memory.
- `/browse` — for verifying the client renders and for screenshots during the demo build
- `frontend-design` or `ui-ux-pro-max` — the four screens, once they function
- `superpowers:systematic-debugging` — for the hour-0 `jac-client` npm spike if it misbehaves
