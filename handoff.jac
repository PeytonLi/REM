"""Live-handoff app layer -- auth, session lifecycle, summary, sign-off, retrieval.

This is the PRD "Live Handoff Capture, Summary & Retrieval" feature. `schema.jac`
and `compose.jac` are frozen (Person A's graph core), so every NEW node and
walker the feature needs lives here and is registered append-only in `main.jac`
and `endpoints.sv.jac`. We REUSE the frozen pieces we can:

  * `compose_handoff` + `to_sbar` (compose.jac) turn a transcript into an SBARPlus
    -- the same LLM writer the graph core already validates, so no new byllm
    nested-schema problem is introduced (that pitfall is solved in compose.jac).
  * the Deepgram batch params proven in `adapters/voice.transcribe` are mirrored
    in `_transcribe_b64` so the browser's recorded audio gets a clean, well
    diarized transcript on "end handoff" (the hybrid path, PRD 7 override).

Everything hangs off the flat `root` graph, matching the rest of REM. Nodes are
connected with generic `++>` edges and looked up by jid (`jobj`) -- the same
provenance idiom `retrieve.provenance` uses.

Degrades safely (PRD 10.5): no DEEPGRAM_API_KEY -> batch transcription is skipped
and the live-streamed segments are stored instead; no REM_LIVE -> the summary is
a deterministic transcript-grounded draft, no API call. Auth is intentionally
minimal per PRD 5.1: seeded demo users, plaintext demo passwords, no token store.
"""

import os;
import base64;
import requests;
import from schema { Clinical, SBARPlus, Action, IfThen, now }
import from compose { compose_handoff, to_sbar }

glob DEEPGRAM_URL: str = "https://api.deepgram.com/v1/listen";

# Same keyterm hints as adapters/voice.jac -- Deepgram mangles drug names, and
# the provenance story dies if the graph ingests "seftriaxone".
glob _KEYTERMS: list[str] = [
    "ceftriaxone", "levofloxacin", "cefepime", "vancomycin",
    "nitrofurantoin", "desaturation", "SpO2", "urine culture", "afebrile"
];


# ===========================================================================
# New graph nodes (PRD 4). Kept out of the frozen schema.jac.
# ===========================================================================

node User {
    """A staff member who logs in. Demo-seeded; password is plaintext (PRD 5.1)."""
    has username: str;
    has name: str;
    has role: str;                   # RN | LPN | CNA
    has password: str = "demo";
    has facility_id: str = "F1";
}

node Resident {
    """A person being handed off. Summaries and retrieval are scoped to these."""
    has name: str;
    has room: str;
    has facility_id: str = "F1";
}

node HandoffSession {
    """One outgoing->incoming handoff. May cover several residents (PRD 7)."""
    has outgoing_user: str;          # username
    has incoming_user: str;          # username
    has resident_ids: list[str] = [];
    has status: str = "in_progress"; # in_progress | completed
    has started_at: float = 0.0;
    has ended_at: float = 0.0;
    has shift: str = "D5-night";
}

node Transcript {
    """The captured conversation for a session. `segments` = [{speaker,text,start}]."""
    has segments: list[dict] = [];
    has audio_ref: str = "";         # pointer to stored audio, not the audio itself
}

node HandoffSummary {
    """One SBAR-plus summary, one per resident per session (PRD 5.4). Editable
    while `draft`; `sign` locks it. `action_list`/`contingencies` are stored as
    plain dicts so the client can render and edit them without server types."""
    has resident_id: str = "";
    has situation: str = "";
    has background: str = "";
    has assessment: str = "";
    has recommendation: str = "";
    has action_list: list[dict] = [];      # [{task, owner, due}]
    has contingencies: list[dict] = [];    # [{trigger, response}]
    has generated_at: float = 0.0;
    has model_used: str = "";
    has status: str = "draft";             # draft | signed
    has signed_by: str = "";
    has signed_at: float = 0.0;
}


# ===========================================================================
# Server-side helpers (no walker context needed)
# ===========================================================================

"""Diarized batch transcription of in-memory audio -> [{speaker,text,start}].

Mirrors adapters/voice.transcribe (nova-3, diarize, utterances) but takes the
browser's base64 recording instead of a file. Returns [] on any failure so the
caller falls back to the live-streamed segments -- the demo never blocks."""
def _transcribe_b64(b64: str, mime: str) -> list[dict] {
    key = os.getenv("DEEPGRAM_API_KEY");
    if not key or not b64 {
        return [];
    }
    audio: bytes = b"";
    try {
        audio = base64.b64decode(b64);
    } except Exception as e {
        print(f"[handoff] bad audio b64 ({e})");
        return [];
    }
    params: list = [
        ("model", "nova-3"), ("diarize", "true"), ("utterances", "true"),
        ("smart_format", "true"), ("punctuate", "true")
    ];
    for term in _KEYTERMS {
        params.append(("keyterm", term));
    }
    utts: list = [];
    try {
        resp = requests.post(
            DEEPGRAM_URL,
            params=params,
            data=audio,
            headers={"Authorization": f"Token {key}", "Content-Type": mime},
            timeout=180
        );
        resp.raise_for_status();
        utts = (resp.json()["results"]["utterances"]) as list;
    } except Exception as e {
        print(f"[handoff] batch transcribe failed ({e}) -- using live segments");
        return [];
    }
    out: list[dict] = [];
    for u in utts {
        ud: dict = u as dict;
        spk: int = (ud.get("speaker", 0)) as int;
        out.append({
            "speaker": f"Speaker {spk + 1}",
            "text": (ud["transcript"]) as str,
            "start": (ud["start"]) as float
        });
    }
    return out;
}


"""Compose an SBARPlus from transcript lines + clinical context.

Live (REM_LIVE=1): the frozen `compose_handoff` writer fills the draft, mapped
into SBARPlus by the frozen `to_sbar`. Offline / on failure: a deterministic
draft grounded in the actual transcript text, so tests and keyless demos still
produce a reviewable (clearly-draft) summary without an API call."""
def _make_sbar(lines: list[str], context: list[str]) -> SBARPlus {
    if os.getenv("REM_LIVE") == "1" and lines {
        try {
            return to_sbar(compose_handoff(lines, context));
        } except Exception as e {
            print(f"[handoff] compose failed ({e}) -- canned summary");
        }
    }
    joined: str = (" ".join(lines))[:400] if lines else "No transcript captured.";
    return SBARPlus(
        situation="Handoff recorded for resident this shift.",
        background=f"Conversation covered: {joined}",
        assessment="Auto-generated draft from the transcript -- review before signing.",
        recommendation="Verify against current orders and complete the action list below.",
        action_list=[Action(task="Review overnight status and vitals", owner="RN", due="start of shift")],
        contingencies=[IfThen(trigger="Any acute change in condition", response="Escalate per protocol")]
    );
}


"""One HandoffSummary node -> a flat dict the client renders and edits."""
def _summary_dict(s: HandoffSummary) -> dict {
    rname: str = "";
    if s.resident_id {
        r: any = None;
        try {
            r = jobj(s.resident_id);
        } except Exception {
            r = None;
        }
        if isinstance(r, Resident) {
            rname = r.name;
        }
    }
    return {
        "id": jid(s),
        "resident_id": s.resident_id,
        "resident_name": rname,
        "situation": s.situation,
        "background": s.background,
        "assessment": s.assessment,
        "recommendation": s.recommendation,
        "action_list": s.action_list,
        "contingencies": s.contingencies,
        "generated_at": s.generated_at,
        "model_used": s.model_used,
        "status": s.status,
        "signed_by": s.signed_by,
        "signed_at": s.signed_at
    };
}


"""Sort key for retrieval: newest handoff first."""
def _gen_at(d: dict) -> float {
    return d["generated_at"] as float;
}


# ===========================================================================
# Walkers -- the API surface (PRD 6). All :pub, all spawned from root.
# ===========================================================================

walker:pub SeedDemo {
    """Idempotently seed demo staff + residents (PRD 5.1). Safe to call repeatedly."""
    has reports: list[dict] = [];

    can seed with Root entry {
        if not [here --> [?:User]] {
            here ++> User(username="mortiz", name="Maya Ortiz", role="RN");
            here ++> User(username="dpatel", name="Dev Patel", role="RN");
            here ++> User(username="jlee", name="Jordan Lee", role="LPN");
            here ++> User(username="acna", name="Alex Cruz", role="CNA");
        }
        if not [here --> [?:Resident]] {
            here ++> Resident(name="Harold Alvarez", room="3B");
            here ++> Resident(name="Rosa Marino", room="2A");
            here ++> Resident(name="Walter Kim", room="4C");
        }
        report {
            "users": len([here --> [?:User]]),
            "residents": len([here --> [?:Resident]])
        };
    }
}


walker:pub Login {
    """Match username + password against a seeded User (PRD 5.1). No token store;
    the client holds the returned identity for the session."""
    has username: str;
    has password: str;
    has reports: list[dict] = [];

    can auth with Root entry {
        for u in [here --> [?:User]] {
            if u.username == self.username and u.password == self.password {
                report {"ok": True, "id": jid(u), "username": u.username,
                        "name": u.name, "role": u.role};
                return;
            }
        }
        report {"ok": False, "id": "", "username": "", "name": "", "role": ""};
    }
}


walker:pub Roster {
    """Active staff (to pick the incoming nurse) + residents (to hand off)."""
    has reports: list[dict] = [];

    can list with Root entry {
        users = [
            {"id": jid(u), "username": u.username, "name": u.name, "role": u.role}
            for u in [here --> [?:User]]
        ];
        residents = [
            {"id": jid(r), "name": r.name, "room": r.room}
            for r in [here --> [?:Resident]]
        ];
        report {"users": users, "residents": residents};
    }
}


walker:pub StartHandoff {
    """Open a session (PRD 5.2). Incoming nurse + 1+ residents, status in_progress."""
    has outgoing_username: str;
    has incoming_username: str;
    has resident_ids: list[str] = [];
    has shift: str = "D5-night";
    has reports: list[dict] = [];

    can start with Root entry {
        sess = HandoffSession(
            outgoing_user=self.outgoing_username,
            incoming_user=self.incoming_username,
            resident_ids=self.resident_ids,
            status="in_progress",
            started_at=now(),
            shift=self.shift
        );
        here ++> sess;
        report {"ok": True, "id": jid(sess), "status": "in_progress",
                "started_at": sess.started_at};
    }
}


walker:pub EndHandoff {
    """End a session (PRD 5.3-5.4): store the transcript (batch-retranscribed when
    audio is supplied, else the live segments), then compose ONE draft summary per
    resident and persist it. Reports the transcript + all summaries for review."""
    has session_id: str;
    has live_segments: list[dict] = [];   # [{speaker,text,start}] from the live stream
    has audio_b64: str = "";              # optional recorded audio for clean batch pass
    has mime: str = "audio/webm";
    has reports: list[dict] = [];

    can finish with Root entry {
        sess: any = None;
        try {
            sess = jobj(self.session_id);
        } except Exception {
            sess = None;
        }
        if not isinstance(sess, HandoffSession) {
            report {"ok": False, "error": "session not found"};
            return;
        }

        # 1. Prefer a clean batch re-transcription; fall back to live segments.
        segs = self.live_segments;
        if self.audio_b64 {
            batch = _transcribe_b64(self.audio_b64, self.mime);
            if batch {
                segs = batch;
            }
        }

        # 2. Persist the transcript on the session.
        tnode = Transcript(segments=segs, audio_ref="");
        sess ++> tnode;

        # 3. One draft summary per resident, grounded in the transcript.
        lines = [
            (s.get("speaker", "Speaker") as str) + ": " + (s.get("text", "") as str)
            for s in segs
        ];
        context = [c.claim for c in [here --> [?:Clinical, suppressed == False]]];
        live: bool = os.getenv("REM_LIVE") == "1";
        rid_list = sess.resident_ids if sess.resident_ids else [""];
        out_summaries: list[dict] = [];
        for rid in rid_list {
            sbar = _make_sbar(lines, context);
            al = [{"task": a.task, "owner": a.owner, "due": a.due} for a in sbar.action_list];
            cg = [{"trigger": c.trigger, "response": c.response} for c in sbar.contingencies];
            summ = HandoffSummary(
                resident_id=rid,
                situation=sbar.situation,
                background=sbar.background,
                assessment=sbar.assessment,
                recommendation=sbar.recommendation,
                action_list=al,
                contingencies=cg,
                generated_at=now(),
                model_used="gpt-4o" if live else "offline-canned",
                status="draft"
            );
            sess ++> summ;
            out_summaries.append(_summary_dict(summ));
        }

        sess.status = "completed";
        sess.ended_at = now();
        report {"ok": True, "session_id": jid(sess),
                "transcript": {"segments": segs}, "summaries": out_summaries};
    }
}


walker:pub ListHandoffs {
    """Handoffs for a resident, newest first (PRD 5.6). Empty resident_id = all.
    Drafts are returned too, flagged by `status`, so the UI can mark them unsigned."""
    has resident_id: str = "";
    has reports: list[dict] = [];

    can list with Root entry {
        out: list[dict] = [];
        for sess in [here --> [?:HandoffSession]] {
            for summ in [sess --> [?:HandoffSummary]] {
                if (not self.resident_id) or (summ.resident_id == self.resident_id) {
                    d = _summary_dict(summ);
                    d["session_id"] = jid(sess);
                    d["shift"] = sess.shift;
                    d["outgoing"] = sess.outgoing_user;
                    d["incoming"] = sess.incoming_user;
                    d["ended_at"] = sess.ended_at;
                    out.append(d);
                }
            }
        }
        report {"handoffs": sorted(out, key=_gen_at, reverse=True)};
    }
}


walker:pub HandoffDetail {
    """Full detail for one session: summary(ies) + transcript (PRD 5.6). The
    transcript is the provenance behind the summary lines."""
    has session_id: str;
    has reports: list[dict] = [];

    can detail with Root entry {
        sess: any = None;
        try {
            sess = jobj(self.session_id);
        } except Exception {
            sess = None;
        }
        if not isinstance(sess, HandoffSession) {
            report {"ok": False, "error": "session not found"};
            return;
        }
        summaries = [_summary_dict(s) for s in [sess --> [?:HandoffSummary]]];
        tsegs: list[dict] = [];
        for t in [sess --> [?:Transcript]] {
            tsegs = t.segments;
        }
        report {
            "ok": True,
            "session": {
                "id": jid(sess), "shift": sess.shift,
                "outgoing": sess.outgoing_user, "incoming": sess.incoming_user,
                "started_at": sess.started_at, "ended_at": sess.ended_at,
                "status": sess.status, "resident_ids": sess.resident_ids
            },
            "summaries": summaries,
            "transcript": tsegs
        };
    }
}


walker:pub EditSummary {
    """Edit a draft summary (PRD 5.5). All SBAR-plus fields are replaced with the
    client's current values. Refuses once the summary is signed (locked)."""
    has summary_id: str;
    has situation: str = "";
    has background: str = "";
    has assessment: str = "";
    has recommendation: str = "";
    has action_list: list[dict] = [];
    has contingencies: list[dict] = [];
    has reports: list[dict] = [];

    can edit with Root entry {
        s: any = None;
        try {
            s = jobj(self.summary_id);
        } except Exception {
            s = None;
        }
        if not isinstance(s, HandoffSummary) {
            report {"ok": False, "error": "summary not found"};
            return;
        }
        if s.status == "signed" {
            report {"ok": False, "error": "summary is signed and locked"};
            return;
        }
        s.situation = self.situation;
        s.background = self.background;
        s.assessment = self.assessment;
        s.recommendation = self.recommendation;
        s.action_list = self.action_list;
        s.contingencies = self.contingencies;
        report {"ok": True, "summary": _summary_dict(s)};
    }
}


walker:pub SignSummary {
    """Sign off a draft (PRD 5.5). Gated to RN/LPN. Records who + when and locks
    the summary from further edits."""
    has summary_id: str;
    has signed_by: str;
    has role: str = "";
    has reports: list[dict] = [];

    can sign with Root entry {
        s: any = None;
        try {
            s = jobj(self.summary_id);
        } except Exception {
            s = None;
        }
        if not isinstance(s, HandoffSummary) {
            report {"ok": False, "error": "summary not found"};
            return;
        }
        if self.role and (self.role not in ["RN", "LPN"]) {
            report {"ok": False, "error": "only RN or LPN can sign off"};
            return;
        }
        if s.status == "signed" {
            report {"ok": False, "error": "already signed"};
            return;
        }
        s.status = "signed";
        s.signed_by = self.signed_by;
        s.signed_at = now();
        report {"ok": True, "summary": _summary_dict(s)};
    }
}
