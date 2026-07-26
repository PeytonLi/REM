# REM telephony bridge

SignalWire media streams ↔ ElevenLabs Agents. `adapters/voice.jac` POSTs here
and waits; the bridge places the call, proxies audio, and returns the caller's
own words so Jac can judge the read-back.

## Why this exists rather than ElevenLabs-native telephony

Two dead ends, both hit and both documented so nobody repeats them:

- **ElevenLabs SIP trunk → SignalWire.** Returns `404 Domain unavailable` on
  every transport, port, and domain tried. SignalWire SIP endpoints host
  *registered devices*; they do not terminate an unregistered INVITE to an
  arbitrary PSTN number, which is exactly what ElevenLabs sends.
- **ElevenLabs-native → Twilio.** Works, and is still the fallback. But a Twilio
  **trial** account prepends a spoken trial notice to every call, and (per the
  VoiceSRE bridge this is ported from) strips `<Connect><Stream>` from TwiML.
  Removing that costs a Twilio upgrade.

SignalWire has neither restriction and speaks the Twilio-compatible protocol,
so the bridge pattern works unmodified against it.

## Deploy (Render)

`render.yaml` is here. Root Directory is `bridge`.

1. New Web Service → connect this repo → Root Directory `bridge`
2. Set env vars (all `sync: false`, so set them in the dashboard):
   `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`, `SIGNALWIRE_SPACE_URL`,
   `SIGNALWIRE_PROJECT_ID`, `SIGNALWIRE_TOKEN`, `SIGNALWIRE_PHONE_NUMBER`
3. Deploy, then set **`PUBLIC_URL`** to the service's own https URL
   (e.g. `https://rem-bridge.onrender.com`) and redeploy. The bridge hands that
   hostname to SignalWire in the TwiML, so it must know its own address.
4. Back in the app's `.env`, set `BRIDGE_URL` to the same URL.

**Render free tier sleeps after inactivity.** A cold start can take ~30s, which
would stall the first call of the demo. Hit `/health` a minute before presenting.

## Run locally

Needs a public tunnel, because SignalWire must reach the bridge:

```bash
cd bridge && npm install
node --env-file=../.env server.mjs      # --env-file tolerates CRLF .env files
cloudflared tunnel --url http://localhost:8080
# put the tunnel URL in PUBLIC_URL, restart, and set BRIDGE_URL to it too
```

## Endpoints

| Route | Purpose |
|---|---|
| `GET /health` | liveness, echoes the configured `PUBLIC_URL` |
| `POST /call` | `{to, script}` → **blocks** → `{answered, turns}` |
| `ALL /twiml` | SignalWire fetches this to learn where to stream |
| `WS /media` | audio proxy, SignalWire ↔ ElevenLabs |

## Design notes

- **`first_message` is the finding.** `escalate.jac::script_for()` decides every
  word; the agent only speaks it. Keeping the model out of *what* gets said is
  the §7.4 seam — do not let the agent paraphrase findings.
- **Silence is never acknowledgment.** No answer, voicemail, or timeout resolves
  as `answered: false`, so `Escalate` climbs to the next clinician instead of
  recording a page as handled.
- **The read-back judgement stays in Jac.** The bridge only returns turns;
  `readback_ok()` decides. A bare "okay" must not count.
- The agent prompt here mirrors `docs/elevenlabs-agent.md`. Keep them in sync.
