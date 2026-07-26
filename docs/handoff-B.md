# Handoff — Person B: Boundary, Voice, Device & Demo

Read first: [`docs/REM-PRD.md`](./REM-PRD.md) §6.2a, §9, §10.2, §11, §13 · [`docs/WORKPLAN.md`](./WORKPLAN.md) §2–§4 (ownership + contracts).

**You own the graph boundary.** Everything that produces episodes for the graph or renders results out of it, plus every external provider and the device generator. You have **three input modalities** now — structured episodes, verbal capture, and the continuous device stream — but all three land as the same `Episode` node. You never edit `consolidate.jac`, `tripwire.jac`, or `schema.jac`.

**You are blocked by nobody after hour 3.** A ships `required_findings()` returning 3 hand-built `Clinical` nodes at hour 3, so the omission panel and all five screens are buildable before consolidation exists.

**The device stream is the actual product being pitched** (§13, §14). It outranks verbal capture in the cut order. `generate_vitals.py` is already built (§11.1) — you are wiring its CSVs in, not building a sensor.

---

## Scope

| Deliverable | PRD ref | Hours |
|---|---|---|
| `jac start --client` hello-world spike + npm graph lib check | §10.2 | 0–1 |
| **Record the 45s handoff audio** — needs a second voice, do it at hour 2 | §13, §14 | 2–3 |
| `seed/` — 400 manual episodes, 2 manual planted findings, 40 decoys | §11 | 2–3 |
| Run `generate_vitals.py` — fall + 3-desaturation + daily-trend CSVs | §11.1 | 2–3 |
| Stubs for `place_call` / `transcribe` → hand to A | WORKPLAN §3 | 3 |
| `baseline.jac` — naive control + left pane, then never touch again | §13 | 3–6 |
| `ingest.jac` — `IngestDevice` + `format_wearable_episode` | §6.2a | 9–13 |
| `adapters/voice.jac` — Deepgram batch + diarization | §9.4 | 13–15 |
| `ingest.jac` — `IngestTranscript` | §9.2 | 13–15 |
| `client/` — five screens + provenance highlighting | §10.2 | 15–17 |
| `omission.jac` — `was_conveyed()` + panel | §9.3 | 19–20 |
| ElevenLabs outbound call wiring | §8 | 20–22 |
| README, demo video, **backup call recording** | §13 | 23–24 |

## Non-negotiable

1. **Diarization is required, not optional** (§9.2). An unattributed transcript breaks the entire provenance model. Two-speaker recording, distinct voices, verify the labels before demo day.
2. **The voice layer is swappable, not load-bearing** (§10.5). If telephony dies, `place_call()` returns a `CallResult` produced by an on-screen notification instead. A's walker never knows the difference. Build it this way from hour 3.
3. **Batch, not streaming** (§9.4). Deepgram Nova-3 batch mode — cheaper, far simpler, and live mic in a loud room is a coin flip.
4. **Device ingestion is a formatting adapter, not a new architecture** (§6.2a). A CSV row becomes an `Episode.content` string via `format_wearable_episode(...) by cheap()`, `source = wearable_*`, `author = device_id`. If you find yourself adding a node type or a second consolidation path, you have taken a wrong turn — this is the exact same claim §9.2 makes for speech.
5. **The 40 decoys are the product's headline number** (§12). Near-misses specifically: two observers not three, a contradiction on an inactive order, a stale claim justifying nothing, an `Action` completed one minute late, and **one isolated low-step day caused by a scheduled outing** (tests that R5 doesn't over-fire on noise). Lazy decoys make the zero-false-positive claim worthless.
6. **Say "synthetic data, synthetic device" on a slide** (§16). Someone will ask about both the data and the hardware — the device is a swappable stand-in for a consumer/medical wearable API, by design for a 24h build.

## Traps

- **Deepgram mangles drug names.** Use keyterm prompting with your drug list. The recorded script is yours to control — no excuse for a wrong drug name coming back.
- **Fall detection false-positives on accelerometer jitter** (§11.1, §15). Your generator owns the fall signal — threshold the impact spike well above normal movement noise so a lone jitter never reads as a fall, and verify against the decoy set. No missed fall, no false fall.
- **ElevenLabs free tier is 15 min/month, 4 concurrent.** Test calls bill at half rate → ~20–30 demo calls total. Don't burn them debugging; use A's stub path for that.
- **Deepgram's $200 credit is separate** from the ElevenLabs budget. It is effectively free at this volume; the ElevenLabs minutes are the scarce resource.
- **Do not reach for the static-HTML escape hatch before hour 14** (§10.2). Walkers already expose as REST, so it is a ~1h fallback, but reaching for it early forfeits the "single-file full-stack" rubric criterion for velocity you don't need across five screens.
- **Record the backup call video before presenting.** Conference wifi will fail. Cue it so you can keep talking through the failure.

## Done when

Playing the recorded file resolves a diarized transcript → episodes land in the graph; the device CSVs resolve via `IngestDevice` → `wearable_*` episodes land in the same graph and the device dashboard shows the declining live trace; omission panel populates with 3 items → split screen shows ~4,000-word naive vs. ~300-word SBAR-plus → clicking a line lights up its source episodes, whether nursing note, spoken utterance, or device reading.

---

## Parallel agent split

Six agents. B1 and B2 are urgent (they unblock A and the demo's left pane). B4 is the long pole — start its spike at hour 0.

Each agent writes only the files its task names. Every task leaves one runnable `assert`-based self-check; no test framework.

### B1 — Seed data + device CSVs + stubs *(highest priority, unblocks A)*
**Writes:** `seed/gen.py`, `seed/patient.json`, device CSVs (via the existing `generate_vitals.py`), `adapters/voice.jac` (stub version only)
**Reads:** PRD §11, WORKPLAN §3
One patient, 5-day admission, 6 shifts, ~400 manual episodes across the manual sources. Plant the two manual findings from §11.2: the **antibiotic → rash → alternative** causal chain (must survive to shift 6 with the *why* intact) and the **UTI zombie** ("Suspected UTI" day 1, urine culture negative day 2, antibiotic still running day 5). Then run `generate_vitals.py` to produce the device-driven findings: the **three desaturations** (02:10 / 01:45 / 03:20, wearable-logged across three shifts, never connected), the **fall** (a single `wearable_fall` episode with no CNA room-check logged after), and the **4-day antecedent decline** in mobility and sleep-quality score. Add ~40 "ambulated in hallway" noise variants, then 40 deliberate near-miss decoys including the scheduled-outing low-step day.
Ship the stub adapters in the same commit: `place_call()` → `CallResult(acknowledged=true, readback=true)`, `transcribe()` → 6 hard-coded segments.
**Self-check:** assert the fixture contains exactly 3 desaturation episodes spanning ≥2 shifts, one `wearable_fall` with no following room-check `Completed`, a ≥3-day monotized mobility/sleep decline, and that no decoy would satisfy R1–R6.
**Done when:** A has the fixture, the device CSVs, and both stubs. Hour 3, hard deadline.

### B2 — Naive baseline
**Writes:** `baseline.jac`
**Reads:** PRD §13
Last note + accumulated copy-forward, ~4,000 words. This is both the experimental control and the demo's left pane. Build it, verify it, then never touch it again — its badness is the point.
**Self-check:** assert output word count > 3,000 and that the antibiotic-switch *reason* (the rash) is absent while "on [the alternate drug]" is present.

### B3 — Ingest: device + transcript
**Writes:** `ingest.jac` (`IngestDevice` + `IngestTranscript` + `format_wearable_episode`), `adapters/voice.jac` (real `transcribe`), `audio/handoff.wav`
**Reads:** PRD §6.2a, §9.1–§9.2, §9.4
`IngestDevice` maps CSV rows → `Episode(source=wearable_*, author=device_id)` via `format_wearable_episode(row, metric) -> str by cheap()`. `IngestTranscript` maps diarized segments → `Episode(source="verbal_handoff", author=<speaker>)`. Deepgram Nova-3 batch with diarization, keyterm-prompted with the drug list. **No new downstream architecture** for either path — if you add a node type, you've taken a wrong turn (§6.2a, §9.2). The 45s script must contain one causal explanation that exists nowhere in the written record, and must deliberately omit two things the graph requires.
**Self-check:** assert every produced `Episode` (device or verbal) has a non-empty `author`; assert speaker labels are stable across the audio file; assert a `wearable_fall` row yields exactly one `Episode` with `source="wearable_fall"`.

### B4 — Client, five screens *(long pole — spike at hour 0)*
**Writes:** `client/`
**Reads:** PRD §10.2, §13
Hour 0–1: hello-world rendering one node, and confirm the force-directed graph lib loads via `[dependencies.npm]` in `jac.toml`. That 30-minute check is the only real unknown in this path.
Then the five §10.2 screens: split-screen comparison (naive vs. SBAR-plus), graph view with provenance highlighting on click, **device dashboard** (live vitals trace + daily mobility/sleep trend, so a judge can *see* the wearable narrative), consolidation run view (replayed from A's step log, **not** live), and tripwire/escalation log.
**Self-check:** clicking a composed SBAR-plus line calls `provenance()` and highlights ≥1 node; the device dashboard renders a declining trace over the seeded window.
**Codes against:** A's stubbed `required_findings()` / `provenance()` until hour 8.

### B5 — Omission check
**Writes:** `omission.jac`, `client/omission-panel`
**Reads:** PRD §9.3
The obligation set is a **graph query** (A's `required_findings()`) — no model. The only LLM call is the per-claim boolean `was_conveyed(claim, transcript) -> bool by cheap()`. Post-hoc, never mid-sentence. The panel's three demo items are the antibiotic-switch reasoning, the overnight desaturation pattern, and the missed room-check for the fall.
**Self-check:** with a transcript that mentions 1 of 3 required claims, assert the panel lists exactly 2.
**Protect this ahead of the phone call** — it addresses the stated problem more directly and carries none of the telephony risk.

### B6 — ElevenLabs + demo package
**Writes:** `adapters/voice.jac` (real `place_call`), `README.md`, `demo/`
**Reads:** PRD §8, §13, §16
Outbound agent call, 40-second hard cap, script structure: identify → one finding → provenance → ask → read-back. The **primary demo call is the fall escalation (Call script A, §8)**; the cross-shift corroboration (script B) is shown via the graph/omission panel. Read-back is the walker's termination condition, so parse it honestly.
Then: README, 3-minute demo video, **backup call recording cued before presenting**, synthetic-data-and-device slide, the restraint slide (findings : calls ratio from A's eval, e.g. "142 findings. 3 calls. Zero false positives on 40 decoys").
**Degrades to:** on-screen notification. If this is the thing that slips, it is supposed to slip — cut item #3 in §14.

---

## Suggested skills

- `superpowers:dispatching-parallel-agents` — for the B1–B6 fan-out above
- `context7` / `everything-claude-code:docs-lookup` — Jac, `jac-client`, Deepgram Nova-3, ElevenLabs Agents. Every one of these has moved recently; do not write from memory.
- `/browse` — for verifying the client renders and for screenshots during the demo build
- `frontend-design` or `ui-ux-pro-max` — the five screens, once they function
- `superpowers:systematic-debugging` — for the hour-0 `jac-client` npm spike if it misbehaves
