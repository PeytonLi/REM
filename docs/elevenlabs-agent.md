# ElevenLabs agent config (REM escalation call)

The agent is deliberately dumb. `escalate.jac::script_for()` builds the entire
spoken finding and `adapters/voice.jac::place_call()` passes it as the
`finding_script` dynamic variable. The agent's only jobs are to say it, get a
read-back, and hang up.

Keeping it this narrow is the point, not laziness: the graph decides what is
urgent and what gets said, and the model is only the voice (PRD §7.4). An agent
that paraphrases findings would put an LLM back in the decision path.

It may answer a nurse's question ("which patient was this?", "what time was
it?") — but only by quoting `{{finding_context}}`, a fixed fact block that
`escalate.jac::context_for()` reads off the graph (resident, claim, category,
clock times, `Derived` provenance). Retrieval stays in the graph; the model gets
a closed set of facts, not a licence to improvise. A question outside that set
still gets the refusal, which is the behaviour that matters: a nurse must never
hear a detail the record does not contain.

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

## Audio format — the settings that cost four failed calls

Verified against a live call. Get either of these wrong and the call connects,
bills you, and produces nothing usable:

| Setting | Required | Symptom when wrong |
|---|---|---|
| ASR → **user input audio format** | `ulaw_8000` | agent never hears the nurse, so no read-back is ever detected |
| TTS → **agent output audio format** | `ulaw_8000` | caller hears **noise / background static** — real audio in the wrong encoding, not silence |

SignalWire media streams are μ-law 8kHz in **both** directions. A fresh agent
defaults to `pcm_16000`, which is what produced the static. The working VoiceSRE
agent is `ulaw_8000` on both, which is how this was finally diagnosed — diff a
known-good agent rather than guess.

The `agent_output_audio_format` field is the one to check first: `pcm_16000`
sounds like noise, and it is easy to misread that as a broken bridge.

## Overrides that must be enabled

Dashboard → agent → **Security** → allow overrides for:

- `first_message`
- `prompt`

Both default to **off**, and when off the bridge's injected finding is discarded
**silently** — the agent falls back to its dashboard greeting and the call sounds
fine while saying the wrong thing. That is the failure mode to fear, because
nothing errors: the graph stops controlling what is said and the model starts
improvising clinical content, which is exactly what §7.4 forbids.

Both are set via the API in one PATCH:

```json
PATCH /v1/convai/agents/{agent_id}
{
  "conversation_config": {
    "asr": {"user_input_audio_format": "ulaw_8000"},
    "tts": {"agent_output_audio_format": "ulaw_8000"}
  },
  "platform_settings": {
    "overrides": {"conversation_config_override": {
      "agent": {"first_message": true, "prompt": {"prompt": true}}
    }}
  }
}
```

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

If the nurse asks you a question, answer it in one short sentence using ONLY the
finding you just read and the CASE FACTS below, quoting their wording, then go
back to asking for the read-back.

CASE FACTS (the only details you may state; do not add to them):
{{finding_context}}

Hard rules:
- You are NOT a clinician. Never diagnose, never interpret a finding, never give
  clinical advice, never speculate about cause or treatment.
- Never invent details. If the answer is not in the finding or the CASE FACTS,
  say: "I only have the finding I just read. Please check the chart or the
  handoff record."
- Never state or imply that the nurse acknowledged something they did not say.
- Do not argue or persuade. If the nurse defers or refuses, thank them and end
  the call.
- Be brief: no speeches, and do not keep the nurse on the line once the
  read-back is done.
```

The bridge (`bridge/server.mjs`) overrides this prompt per call and appends the
same CASE FACTS block itself, so the two paths behave alike — but the dashboard
copy still matters: it is what runs if the prompt override is ever disabled.

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
