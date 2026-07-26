# ElevenLabs agent config (REM escalation call)

The agent is deliberately dumb. `escalate.jac::script_for()` builds the entire
spoken finding and `adapters/voice.jac::place_call()` passes it as the
`finding_script` dynamic variable. The agent's only jobs are to say it, get a
read-back, and hang up.

Keeping it this narrow is the point, not laziness: the graph decides what is
urgent and what gets said, and the model is only the voice (PRD §7.4). An agent
that paraphrases findings would put an LLM back in the decision path.

## Create it

Dashboard → **Agents** → **Create agent** → Blank template.

| Setting | Value |
|---|---|
| Name | `REM escalation` |
| First message | `{{finding_script}}` |
| Language | English |
| LLM | any fast model (`gemini-2.5-flash` is fine — it is not reasoning) |
| Max duration | `120` seconds (the 40s cap in PRD §8 is on the spoken script) |
| Voice | anything calm and clear; avoid an overly casual one |

**First message must be exactly `{{finding_script}}`** — that is the dynamic
variable `place_call()` sends. If it is missing, the agent opens with silence or
a generic greeting and the demo call says nothing useful.

## System prompt

```
You are an automated clinical handoff assistant placing a single outbound
escalation call to a nurse in a long-term care facility.

Your only job:
1. Speak the finding exactly as given to you. Do not rephrase it, do not add to
   it, do not summarize it.
2. Ask the nurse to read the request back.
3. If they read back the substance of the request, say "Thank you, that's
   correct" and end the call.
4. If they do not read it back, ask once: "Could you read the request back to
   me?" Then end the call either way.

Hard rules:
- You are NOT a clinician. Never diagnose, never interpret a finding, never give
  clinical advice, never speculate about cause or treatment.
- Never invent details. If asked anything you were not told, say: "I only have
  the finding I just read. Please check the chart or the handoff record."
- Never state or imply that the nurse acknowledged something they did not say.
- Do not argue or persuade. If the nurse defers or refuses, thank them and end
  the call.
- Keep the whole call under 40 seconds.
```

## Wire it up

Copy the agent ID into `.env` as `ELEVENLABS_AGENT_ID`. Import the SignalWire
number (see `.env.example`) and copy the returned id into
`ELEVENLABS_PHONE_NUMBER_ID`.

## Before demo day

- The read-back is the walker's termination condition, and `readback_ok()` in
  `adapters/voice.jac` judges it against the human's turns only. A bare "okay"
  correctly does not count — test with a real read-back and with a bare "okay"
  so you know both paths behave.
- Destination numbers come from `Clinician.phone` in the graph, not from any env
  var. `fixture.jac` ships `+1555...` placeholders that never connect; put a real
  handset in there for the live beat.
- Record the backup call video before presenting (PRD §13).
