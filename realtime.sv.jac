"""Real-time verbal-handoff capture -- server seam (live-mic branch of PRD §9).

The batch path (`adapters/voice.transcribe`) sends a finished recording to
Deepgram and gets every segment back at once. This module is the *streaming*
counterpart: the browser holds the microphone and talks to Deepgram's live
WebSocket directly (client/live_transcribe.cl.jac), so no audio ever crosses
this server. All the server does is:

  * `DeepgramToken` -- hand the browser a credential it can open that socket
    with. Browsers cannot set an `Authorization` header on a WebSocket, so
    Deepgram takes the credential as a WS *subprotocol* instead. Two shapes:
      - scheme "token"  + the raw project key      (default; always works)
      - scheme "bearer" + a short-lived grant token (DEEPGRAM_USE_GRANT=1)
    Same-origin only in a real deployment; for the demo the app is the gate.

  * `IngestUtterance` -- one finalized utterance -> one `Episode`, identical in
    every way to what `IngestTranscript` produces from the batch path. Primitive
    fields only (no `Segment` obj) so the client sends plain JSON and never has
    to construct a server type. `source = "verbal_handoff"`, `author =` the
    diarized speaker -- provenance still needs an author (PRD §9.2).

Degrades like every other boundary piece (PRD §10.5): no key -> the token
walker reports `ok=False` and the client falls back to the scripted transcript.
"""

import os;
import requests;
import from schema { Episode, Handoff }

glob DEEPGRAM_GRANT_URL: str = "https://api.deepgram.com/v1/auth/grant";


walker:pub DeepgramToken {
    """Report a credential the browser can open Deepgram's live socket with.

    reports[0] = {"ok": bool, "scheme": "token"|"bearer", "token": str,
                  "ttl": int}. `ok=False` (empty token) means no key is
    configured and the client should take the scripted-handoff fallback."""
    has reports: list[dict] = [];

    can mint with Root entry {
        key = os.getenv("DEEPGRAM_API_KEY");
        if not key {
            report {"ok": False, "scheme": "token", "token": "", "ttl": 0};
            return;
        }

        # Default: hand back the raw project key with the "token" subprotocol --
        # the documented, reliable browser path. Opt into short-lived grant
        # tokens (never expose the project key to the page) with DEEPGRAM_USE_GRANT=1.
        if os.getenv("DEEPGRAM_USE_GRANT") == "1" {
            try {
                # Annotated, not an inline literal: the checker infers a
                # Literal-keyed dict from an inline body and rejects it against
                # `json=` (same seam as adapters/voice.jac).
                grant_body: dict[str, any] = {"ttl_seconds": 60};
                resp = requests.post(
                    DEEPGRAM_GRANT_URL,
                    headers={"Authorization": f"Token {key}"},
                    json=grant_body,
                    timeout=10
                );
                resp.raise_for_status();
                body = resp.json();
                report {
                    "ok": True, "scheme": "bearer",
                    "token": body["access_token"] as str,
                    "ttl": body.get("expires_in", 60) as int
                };
                return;
            } except Exception as e {
                # Fall through to the raw-key path rather than break the demo.
                print(f"[realtime] grant token failed ({e}) -- using raw key");
            }
        }

        report {"ok": True, "scheme": "token", "token": key, "ttl": 0};
    }
}


walker:pub IngestUtterance {
    """One finalized diarized utterance -> one verbal_handoff Episode.

    Primitive fields so the browser posts plain JSON. Get-or-create the shift's
    Handoff (a bare REST spawn lands on `root`, not a Handoff), then append --
    the same shape IngestTranscript writes, so consolidation/tripwire cannot
    tell a streamed utterance from a batch-transcribed one."""
    has text: str;
    has speaker: str;
    has start: float = 0.0;
    has shift: str = "D5-night";
    has reports: list[Episode] = [];

    can enter with Root entry {
        visit [here --> [?:Handoff, shift == self.shift]] else {
            fresh = here ++> Handoff(shift=self.shift);
            visit fresh;
        }
    }

    can absorb with Handoff entry {
        report here ++> Episode(
            content = self.text,
            source  = "verbal_handoff",
            author  = self.speaker,
            at      = self.start
        );
    }
}
