## Inspiration

About 22% of Medicare beneficiaries experience adverse events during skilled nursing facility stays, and another 11% experience temporary harm, according to an HHS Office of Inspector General report. A big slice of those errors trace back to the shift handoff, the moment when one nurse hands responsibility for 20 to 30 residents to the next nurse, often in a rushed conversation in a hallway, from memory. The number you see cited most often is that 70% of serious medical errors stem from ineffective handoff communication. That figure originated in hospital studies, but long-term care makes the problem worse: fewer nurses per resident, heavier reliance on CNAs, high turnover from agency and travel staff, and residents who cannot always self-report a change the way an alert hospital patient might.

We kept coming back to the same five failure modes. The "why" behind a medication change dies somewhere around shift three and nobody knows why a resident is on a particular drug anymore. Copy-forward errors accumulate because each shift inherits the last note without tracking what was verified and what was just repeated. Patterns that span multiple shifts, like three different nurses each charting one overnight desaturation, sit in separate silos and no single note looks concerning on its own. Slow declines in mobility or sleep quality are invisible day to day but obvious across a week. And handoffs get interrupted. Someone gets paged away and the report restarts from the top while whole sections get skipped.

These are all graph problems dressed up as documentation problems. We built a graph to solve them.

## What it does

REM ingests everything that happens to a resident across a shift: nursing notes, medication records, lab results, continuous vitals from a wearable device, and the spoken handoff conversation itself. All of it lands in a single belief graph as timestamped, attributed `Episode` nodes. A consolidation walker sweeps the graph at each shift boundary and distills clusters of related episodes into `Clinical` belief nodes. Every belief carries `Derived` edges back to its source episodes, so any claim can be traced to who recorded it and when.

From those beliefs, REM composes an SBAR-plus handoff report: Situation, Background, Assessment, Recommendation, plus an action list and if/then contingencies. The outgoing nurse reviews and signs it. It is a draft, not a directive.

Separately, six deterministic rules run as pure graph predicates with no model in the loop. A corroboration rule fires when three or more distinct observers across at least two shifts report the same finding within a 72 hour window. A live contradiction rule catches a ruled-out diagnosis still driving a running intervention, like a UTI that came back negative but still has an active antibiotic order. An unverified drift rule flags beliefs that have been asserted for over 24 hours without anyone confirming them. An orphaned action rule catches overdue tasks nobody completed. A decline rule detects mobility or sleep scores trending down for three or more consecutive days. And a fall rule fires instantly on any fall event, straight to the highest tier, no corroboration needed.

When a rule fires, the finding gets a tier from a static severity table. Most die at Tier 0 and appear in the next handoff. A few get dashboard flags or push notifications. The ones a human needs to act on right now ring a phone. The escalation walker climbs the CNA to nurse to charge nurse to on-call physician chain until someone picks up, listens to the finding, and reads it back. If nobody answers, the call is not acknowledged and the walker keeps climbing. The model never decides what is urgent.

There is also an omission check. After a spoken handoff, REM compares what the graph says should have been covered against what the conversation actually mentioned, and surfaces the gaps. The outgoing nurse may have explained the rash that caused the antibiotic switch, but forgot to mention the three overnight desaturations. The panel catches that.

## How we built it

The whole thing runs in Jac, a language built on a native persistent graph. There is no separate database, no ORM, no persistence code. The graph is the database. `jac start main.jac` gives you REST endpoints, Swagger docs, and the client UI from a single file with no separate frontend process.

The graph has two layers. Episodic nodes are raw, timestamped, and attributed. They decay over time: $\text{strength} \mathrel{*}= \exp(-\Delta t / (\tau \cdot (1 + \log(1 + \text{access\_count}))))$, so frequently retrieved facts resist decay. Episodes decay over a 36 hour time constant. Clinical beliefs decay over 7 days. The strength floor is 0.15; below that, an episode drops out of the summary but stays in the graph. Nothing is deleted. Semantic nodes are clinical beliefs extracted from groups of three or more related episodes. A `Clinical` node cannot be constructed without a non-empty set of `Derived` edges pointing to its sources. That invariant is enforced in the type system, not in code review.

Four walkers do the heavy lifting. Consolidate runs four phases: Replay traverses the graph to find related episodes, Abstract calls a cheap LLM to extract the invariant from clusters of three or more episodes, Reconcile classifies overlapping beliefs as duplicates or contradictions and suppresses the loser without deleting it, and Prune archives episodes whose content is fully captured by a semantic parent. Compose assembles the SBAR-plus handoff from the surviving Clinical nodes, using a stronger model for the nested struct composition and a cheaper one for flat extraction. Tripwire evaluates the six rules as pure graph predicates. Zero `by llm()` calls. Escalate walks the clinician chain and places calls through a SignalWire media stream bridge that proxies audio between the PSTN and an ElevenLabs agent. The agent speaks the finding verbatim from a script the graph wrote, asks for a read-back, and hangs up. The read-back judgment is the only LLM call in the escalation path.

On the input side, manual charting episodes come from a JSON fixture representing one resident across five days and six shifts. Continuous device data starts as per-second CSVs from a Python vitals generator, gets distilled into one episode per clinical event by `seed/device.py`, and flows through `IngestDevice` into the same Episode shape everything else uses. Spoken handoff audio is captured live from the browser microphone, streamed to Deepgram Nova-3 with diarization for speaker labels, and re-transcribed in batch at the end of the session for cleaner results.

The client is a single-page Jac app with screens for login, starting a handoff, recording with live transcription, reviewing and editing the SBAR summary, signing off, and browsing past handoffs. A separate live handoff screen embeds an audio player for the original recording and shows tripwire findings and escalation results inline when the handoff ends.

The whole pipeline produces numbers we can verify. Over a 353 episode fixture, consolidation compresses to 36 live nodes. Tripwire fires 7 findings across all six rules, 3 of them tier 3 phone calls, with zero false positives on 40 deliberately planted near-miss decoys. REM preserves 11 of 12 must-know facts that a naive copy-forward summary drops to 6.

## Challenges we ran into

The biggest technical challenge was getting the ElevenLabs agent to actually speak through a phone call. The PRD assumed a straightforward SIP trunk path. SignalWire SIP endpoints host registered devices and do not terminate an unregistered INVITE to an arbitrary PSTN number. ElevenLabs sent exactly that. Every transport, port, and domain returned a 404. We built a media stream bridge instead: a Node server that places the outbound call through SignalWire's Twilio-compatible REST API, proxies the audio between SignalWire media streams and ElevenLabs WebSocket, and blocks until the call ends so the Jac walker can judge the read-back. The bridge is deployed on Render's free tier. It works, but we burned a full evening on dead SIP paths before we accepted that the bridge was the answer.

The audio format took another four failed calls to get right. SignalWire media streams use μ-law 8kHz in both directions. A fresh ElevenLabs agent defaults to PCM 16kHz. Get the output format wrong and the caller hears static. Get the input format wrong and the agent never hears the nurse speak. We only figured it out by diffing the config against a known-good VoiceSRE agent.

On the Jac side, the byllm plugin cannot build an output schema for a nested object imported from another module. The SBARPlus composition needs a nested struct with action lists and contingencies. We worked around it by having the LLM fill a local flat draft that gets copied into the frozen SBARPlus, keeping the AI and storage schemas independent.

The consolidation reconcile pass is O(n²) over Clinical belief pairs. We gated pairs by subject tag before any LLM call to keep the API budget under control for a 24 hour build window.

The frontend gave us a scare at hour zero. The npm dependency for the force directed graph visualization loaded cleanly through `jac.toml`, but the Jac client compilation pipeline interprets block scoping differently from vanilla JavaScript. A variable declared inside a try block gets scoped to that block and referencing it outside produces a TDZ error at runtime. We learned to pre-declare every variable above the try.

## Accomplishments that we're proud of

The tripwire is genuinely a pure graph predicate engine. There is not a single `by llm()` call in `tripwire.jac`. Every rule is a function that walks edges and compares timestamps. The suppression check prevents a finding from re-firing on the same data. A fourth observation reopens a rule. A re-read of the same three does not. That safety argument, the model extracts facts and rules decide urgency, is the product. And it is enforced in code, not in a slide.

The five input modalities use one Episode shape. A nursing note, a wearable SpO₂ reading, a fall event, a mobility step count, and a spoken transcript utterance all land as the same node type with different `source` and `author` values. Consolidation has zero branches for `wearable_*` sources. The graph did not change to absorb a device or a voice. It was already the right shape.

The escalation chain reflects how long-term care actually works. It is CNA to nurse to charge nurse to on-call physician, not a flat hospital hierarchy. A call that goes to voicemail is not acknowledged. Silence is not acknowledgment. The walker keeps climbing. The read-back check parses what the human actually said, not what the agent said, and a bare "okay" correctly fails.

The omission check runs post-hoc, not mid-sentence. The obligation set is a deterministic graph query. The only model call is a per-claim boolean: was this specific claim mentioned in this specific transcript? The model does not decide what should have been said. That question belongs to the graph.

Every claim in the SBAR report traces to its sources with one click. A judge can verify where a claim came from, who recorded it, and when, in under ten seconds.

## What we learned

We learned that the SIP trunking path between ElevenLabs and SignalWire, which looks clean on paper because SignalWire appears on ElevenLabs' supported trunk list, is a dead end for outbound PSTN calls. The trunk list entry means SignalWire is supported as a generic SIP trunk for inbound calls to registered devices. Outbound INVITEs to arbitrary numbers get a 404 on every domain variant. The bridge pattern, SignalWire REST API for call placement plus WebSocket media proxy, is the path that actually works and is what we should have started with.

We learned that ElevenLabs agent audio format defaults are wrong for PSTN media streams. Both ASR input and TTS output must be set to `ulaw_8000`. The default `pcm_16000` produces static on output and silence on input. The PATCH to fix it is four fields and should be in every agent setup guide.

We learned that a batch re-transcription pass over the full recording, done at the end of the handoff instead of relying purely on the streaming live transcription, produces much cleaner diarization. The live stream gives you real time speaker labels for the UI. The batch pass gives you the clean transcript for the graph. Running both costs one extra Deepgram API call and is worth it.

We learned that Jac's `by llm()` typed extraction is genuinely the right abstraction for this domain. Defining an output struct and letting the LLM fill it means no prompt engineering, no output parsing, no retry-on-malformed-JSON. The struct is the prompt. The one place it broke down, the nested SBARPlus composition, had a clean workaround that kept the AI and storage schemas separate.

We learned that the false positive rate matters more than the detection rate for a system that interrupts clinicians. Nurses stop answering pages when the system cries wolf. Our 40 deliberate near-miss decoys, two observers instead of three, a contradiction on an inactive order, a stale claim justifying nothing, an action completed one minute late, a single low step day from a scheduled outing rather than real decline, are the product's headline number. Zero false positives is the claim that matters.

## What's next for REM

The obvious next step is replacing the synthetic data generator with a real wearable API. The `Episode` shape already accepts `source=wearable_*` and the consolidation pipeline has no wearable-specific branches, so swapping in a real device feed is a formatting adapter, not a rewrite. An Apple Watch or Withings API with continuous SpO₂, heart rate, accelerometer, and sleep staging data would plug directly into `IngestDevice`.

The omission panel should move from post-hoc to mid-conversation. The same `was_conveyed()` boolean over the live transcript, checked every few seconds, could surface a gentle nudge: "the desaturation pattern has not been mentioned yet." Stopping short of a mid-sentence interruption keeps it useful without being annoying.

The escalation threshold should learn from acknowledgment and dismissal feedback. Right now the 3 observer floor, 72 hour window, 24 hour staleness limit, and 3 day decline threshold are hand-tuned on synthetic data. Real deployment would need those thresholds calibrated against actual clinical outcomes and nurse feedback. A facility that finds the system too noisy should be able to tune it without touching code.

Adding a full wing view that shows every resident's consolidated beliefs at a glance, with color coded urgency tiers, would make REM useful between handoffs, not just at shift boundaries. The charge nurse could scan 30 residents in 30 seconds and know which two need attention.

Real HIPAA posture and a CMS long-term care compliance review are the hard, unglamorous work that separates a demo from something a facility could actually deploy. Those were explicitly out of scope for a 24 hour build, but they are the gates to any real pilot.

The most interesting direction is flipping the direction of the call. Right now REM calls the nurse when a rule fires. The reverse, letting a nurse call REM and ask "has anything changed with Mrs. Alvarez since my last shift," could turn the graph into an on-demand second opinion instead of a one way alarm.
