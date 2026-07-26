// REM telephony bridge: SignalWire media streams <-> ElevenLabs Agents.
//
// Ported from the VoiceSRE bridge. SignalWire, not Twilio, for the reason that
// project documented: Twilio trial accounts strip <Connect><Stream> from TwiML
// entirely, and a trial account also prepends a spoken trial notice to every
// call. SignalWire has neither restriction.
//
// SignalWire speaks the Twilio-compatible protocol -- same TwiML, same media
// frames -- so this is the Twilio bridge pattern pointed at a different vendor.
//
// Difference from VoiceSRE: that bridge fired a webhook and returned
// immediately. REM's place_call() is synchronous and needs the caller's own
// words back to judge the read-back (PRD §8), so POST /call BLOCKS until the
// call ends and returns the human's turns. The read-back judgement itself stays
// in Jac (readback_ok, adapters/voice.jac) -- the bridge only moves audio.
//
//   node bridge/server.mjs        (needs PUBLIC_URL pointing at a tunnel)

import Fastify from "fastify";
import fastifyFormBody from "@fastify/formbody";
import fastifyWs from "@fastify/websocket";
import WebSocket from "ws";

const {
  ELEVENLABS_API_KEY,
  ELEVENLABS_AGENT_ID,
  SIGNALWIRE_SPACE_URL,
  SIGNALWIRE_PROJECT_ID,
  SIGNALWIRE_TOKEN,
  SIGNALWIRE_PHONE_NUMBER,
  PUBLIC_URL,
  BRIDGE_PORT = 8080,
} = process.env;

for (const [k, v] of Object.entries({
  ELEVENLABS_API_KEY, ELEVENLABS_AGENT_ID, SIGNALWIRE_SPACE_URL,
  SIGNALWIRE_PROJECT_ID, SIGNALWIRE_TOKEN, SIGNALWIRE_PHONE_NUMBER,
})) {
  if (!v) throw new Error(`bridge: missing required env ${k}`);
}

const PUBLIC_HOST = (PUBLIC_URL || "").replace(/^https?:\/\//, "").replace(/\/$/, "");
const SW_SPACE = SIGNALWIRE_SPACE_URL.replace(/^https?:\/\//, "").replace(/\/$/, "");
const SW_AUTH = "Basic " + Buffer.from(`${SIGNALWIRE_PROJECT_ID}:${SIGNALWIRE_TOKEN}`).toString("base64");

// The agent must not improvise: escalate.jac already decided every word via
// script_for(). Mirrors docs/elevenlabs-agent.md -- keep them in sync.
const AGENT_PROMPT = [
  "You are an automated clinical handoff assistant placing a single outbound",
  "escalation call to a nurse in a long-term care facility.",
  "Speak the finding exactly as given in your first message. Do not rephrase it,",
  "do not add to it, do not summarize it.",
  "Then ask the nurse to read the request back.",
  "If they read back the substance of the request, say 'Thank you, that's correct'",
  "and end the call. If they do not, ask once: 'Could you read the request back to",
  "me?' Then end the call either way.",
  "You are NOT a clinician. Never diagnose, never interpret a finding, never give",
  "clinical advice, never speculate about cause or treatment.",
  "Never invent details. If asked anything you were not told, say: 'I only have the",
  "finding I just read. Please check the chart or the handoff record.'",
  "Never state or imply that the nurse acknowledged something they did not say.",
  "Do not argue or persuade. Keep the whole call under 40 seconds.",
].join(" ");

const CALL_TIMEOUT_MS = 150_000;

// callId -> { script, turns, answered, resolve, timer }
const pending = new Map();

async function createCall({ to, url }) {
  const res = await fetch(
    `https://${SW_SPACE}/api/laml/2010-04-01/Accounts/${SIGNALWIRE_PROJECT_ID}/Calls.json`,
    {
      method: "POST",
      headers: { Authorization: SW_AUTH, "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ From: SIGNALWIRE_PHONE_NUMBER, To: to, Url: url }),
    },
  );
  if (!res.ok) throw new Error(`signalwire calls.create ${res.status}: ${await res.text()}`);
  return res.json();
}

async function getSignedUrl() {
  const r = await fetch(
    `https://api.elevenlabs.io/v1/convai/conversation/get_signed_url?agent_id=${ELEVENLABS_AGENT_ID}`,
    { headers: { "xi-api-key": ELEVENLABS_API_KEY } },
  );
  if (!r.ok) throw new Error(`get_signed_url ${r.status}: ${await r.text()}`);
  return (await r.json()).signed_url;
}

function settle(callId, extra = {}) {
  const p = pending.get(callId);
  if (!p) return;
  clearTimeout(p.timer);
  pending.delete(callId);
  p.resolve({ answered: p.answered, turns: p.turns, ...extra });
}

const fastify = Fastify();
fastify.register(fastifyFormBody);
fastify.register(fastifyWs);

fastify.get("/health", async () => ({ ok: true, publicUrl: PUBLIC_URL || null }));

// adapters/voice.jac POSTs here and waits for the finished call.
fastify.post("/call", async (req, reply) => {
  const { to, script } = req.body || {};
  if (!to || !script) return reply.code(400).send({ error: "to and script required" });
  if (!PUBLIC_HOST) return reply.code(500).send({ error: "PUBLIC_URL not set" });

  const callId = `rem_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const done = new Promise((resolve) => {
    pending.set(callId, {
      script, turns: [], answered: false, resolve,
      // Never hang the walker: a call nobody answers must resolve as
      // unanswered so Escalate climbs to the next clinician.
      timer: setTimeout(() => settle(callId, { timedOut: true }), CALL_TIMEOUT_MS),
    });
  });

  try {
    const call = await createCall({
      to,
      url: `https://${PUBLIC_HOST}/twiml?callId=${encodeURIComponent(callId)}`,
    });
    console.log(`[bridge] placed ${call.sid} -> ${to}`);
  } catch (e) {
    settle(callId, { error: e.message });
    return reply.code(502).send({ error: e.message });
  }

  return reply.send(await done);
});

// SignalWire fetches this over the tunnel to learn where to stream audio.
fastify.all("/twiml", async (req, reply) => {
  const callId = req.query.callId || "";
  reply.type("text/xml").send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Connect>
    <Stream url="wss://${PUBLIC_HOST}/media">
      <Parameter name="callId" value="${callId}" />
    </Stream>
  </Connect>
</Response>`);
});

fastify.register(async (f) => {
  f.get("/media", { websocket: true }, (ws) => {
    let streamSid = null;
    let elevenWs = null;
    let callId = "";

    ws.on("error", console.error);

    const setupEleven = async () => {
      const signedUrl = await getSignedUrl();
      elevenWs = new WebSocket(signedUrl);

      elevenWs.on("open", () => {
        const p = pending.get(callId);
        // first_message IS the finding: the graph wrote it, the agent only says it.
        elevenWs.send(JSON.stringify({
          type: "conversation_initiation_client_data",
          conversation_config_override: {
            agent: { prompt: { prompt: AGENT_PROMPT }, first_message: p?.script || "" },
          },
          dynamic_variables: { finding_script: p?.script || "" },
        }));
      });

      elevenWs.on("message", (data) => {
        let m;
        try { m = JSON.parse(data); } catch { return; }
        switch (m.type) {
          case "audio": {
            const payload = m.audio?.chunk || m.audio_event?.audio_base_64;
            if (streamSid && payload) {
              ws.send(JSON.stringify({ event: "media", streamSid, media: { payload } }));
            }
            break;
          }
          case "user_transcript": {
            const t = m.user_transcription_event?.user_transcript || "";
            const p = pending.get(callId);
            if (t && p) {
              console.log("[caller]", t);
              p.turns.push({ role: "user", message: t });
              p.answered = true;   // a human spoke; silence is not an acknowledgment
            }
            break;
          }
          case "interruption":
            if (streamSid) ws.send(JSON.stringify({ event: "clear", streamSid }));
            break;
          case "ping":
            if (m.ping_event?.event_id) {
              elevenWs.send(JSON.stringify({ type: "pong", event_id: m.ping_event.event_id }));
            }
            break;
          default:
            break;
        }
      });

      elevenWs.on("error", (e) => console.error("[ElevenLabs] ws error:", e.message));
      elevenWs.on("close", () => settle(callId));
    };

    ws.on("message", (raw) => {
      let msg;
      try { msg = JSON.parse(raw); } catch { return; }
      switch (msg.event) {
        case "start":
          streamSid = msg.start.streamSid;
          callId = (msg.start.customParameters || {}).callId || "";
          console.log(`[bridge] stream start callId=${callId}`);
          setupEleven();
          break;
        case "media":
          if (elevenWs?.readyState === WebSocket.OPEN) {
            elevenWs.send(JSON.stringify({ user_audio_chunk: msg.media.payload }));
          }
          break;
        case "stop":
          if (elevenWs?.readyState === WebSocket.OPEN) elevenWs.close();
          settle(callId);
          break;
        default:
          break;
      }
    });

    ws.on("close", () => {
      if (elevenWs?.readyState === WebSocket.OPEN) elevenWs.close();
      settle(callId);
    });
  });
});

fastify.listen({ port: Number(BRIDGE_PORT), host: "0.0.0.0" }, (err, addr) => {
  if (err) { console.error(err); process.exit(1); }
  console.log(`[bridge] listening on ${addr}`);
  console.log(`[bridge] PUBLIC_URL=${PUBLIC_URL || "(unset -- set it before calling)"}`);
});
