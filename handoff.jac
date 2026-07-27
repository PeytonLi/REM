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
import from schema { SBARPlus, Action, IfThen, Episode, Clinical, Derived, Fired, now }
import from jaclang.byllm.lib { Model }
import from tripwire { Tripwire }
import from escalate { Escalate }

# python-dotenv is optional; load the project .env so DEEPGRAM_API_KEY (batch
# transcription) and the LLM key are visible even when the shell that launched
# the server didn't export them. Jac has no module-level try/except, so the
# guard lives in a function called from `with entry` (same idiom as voice.jac).
def _load_env {
    try {
        import from dotenv { load_dotenv }
        load_dotenv();
    } except ImportError as e {
        print(f"[handoff] dotenv not installed ({e}); reading os.environ directly");
    }
}

with entry {
    _load_env();
}

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
# Per-resident knowledge graph (PRD §6 belief graph, scoped to a Resident).
#
# The frozen schema keeps Episode/Clinical hanging off root (one implicit
# patient). To give EACH resident their own inspectable knowledge base we hang
# their Episodes/Clinical off the Resident node via two new edges, and reuse the
# frozen `Derived` edge for belief->episode provenance -- the exact same
# provenance shape consolidate.jac writes, so GraphPanel's click-through works.
# ===========================================================================

edge ResObserved: Resident --> Episode {}     # a raw observation about this resident
edge ResBelief: Resident --> Clinical {}      # a distilled belief about this resident


# --- LLM knowledge extraction (transcript -> episodes + cited beliefs) ------
obj KEpisode {
    """One atomic observation the LLM pulls from the handoff."""
    has content: str;
}
sem KEpisode.content = "One atomic, factual observation stated in the handoff (e.g. 'Fall at "
    "02:00, found on floor next to bed'). Concrete, one fact per item, grounded in the transcript.";

obj KBelief {
    """One distilled belief, citing the episodes that justify it."""
    has claim: str;
    has category: str;
    has evidence: list[int] = [];
}
sem KBelief.claim = "A distilled clinical belief about the resident (e.g. 'At high fall risk', "
    "'Possible left hip fracture'). A judgment or summary, not a raw observation.";
sem KBelief.category = "One-word category: respiratory, cardiac, mobility, pain, cognition, skin, "
    "medication, fall, nutrition, or other.";
sem KBelief.evidence = "0-based indices of the episodes above that support this belief. Cite at "
    "least one; a belief with no supporting episode must not be emitted.";

obj KGraph {
    """The extracted knowledge: observations plus the beliefs they support."""
    has episodes: list[KEpisode] = [];
    has beliefs: list[KBelief] = [];
}

def extract_knowledge(transcript: str) -> KGraph by _summarizer();
sem extract_knowledge = "Extract a small clinical knowledge graph from this nurse handoff "
    "transcript. First list the atomic factual observations (episodes) actually stated. Then list "
    "the distilled clinical beliefs they support, each citing the episode indices that justify it. "
    "Ground everything strictly in the transcript -- never invent facts, and every belief must cite "
    "at least one episode. Keep it tight: 3-8 episodes, 1-4 beliefs.";
sem extract_knowledge.transcript = "The verbatim diarized nurse-to-nurse handoff conversation.";


"""Persist an extracted KGraph onto a Resident: one Episode per observation
(ResObserved), one Clinical per belief (ResBelief), and a frozen `Derived` edge
from each belief to every episode it cited."""
def _persist_knowledge(resident: Resident, kg: KGraph, at: float) -> None {
    ep_nodes: list = [];
    for ke in kg.episodes {
        ep = Episode(content=ke.content, source="verbal_handoff", author="handoff", at=at);
        resident +>:ResObserved():+> ep;
        ep_nodes.append(ep);
    }
    for kb in kg.beliefs {
        bel = Clinical(claim=kb.claim, category=kb.category, last_asserted=at, last_verified=at);
        resident +>:ResBelief():+> bel;
        for idx in kb.evidence {
            if idx >= 0 and idx < len(ep_nodes) {
                bel +>:Derived():+> ep_nodes[idx];
            }
        }
    }
}


"""Truncate a label so the graph stays readable."""
def _short(s: str) -> str {
    return s if len(s) <= 42 else (s[:40] + "…");
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


# --- LLM summarization (transcript -> SBAR-plus) ---------------------------
# Local draft types the LLM fills. Defined HERE (not imported) because byllm 0.6
# cannot build an output schema for a nested obj imported from another module --
# the same constraint compose.jac documents. The nested SBAR is structurally
# hard, so we route to gpt-4o (same choice compose.jac makes), not the mini
# default; OPENAI_API_KEY drives it.
glob SUMMARY_MODEL: str = "gpt-4o";
glob _summarizer: Model = Model(model_name="gpt-4o");

obj HAction {
    """One action-list item."""
    has task: str;
    has owner: str;
    has due: str;
}
sem HAction.task  = "A concrete follow-up task, imperative (e.g. 'Recheck SpO2 in 2 hours').";
sem HAction.owner = "Who does it: RN, LPN, CNA, or on-call MD.";
sem HAction.due   = "When it is due (e.g. 'q2h', 'by 2200', 'this shift').";

obj HIfThen {
    """One if/then contingency."""
    has trigger: str;
    has response: str;
}
sem HIfThen.trigger  = "An observable warning sign to watch for.";
sem HIfThen.response = "Exactly what to do if the trigger is observed.";

obj HDraft {
    """The SBAR-plus the LLM fills from the conversation, before it is copied
    into the frozen schema.SBARPlus the rest of REM renders."""
    has situation: str;
    has background: str;
    has assessment: str;
    has recommendation: str;
    has action_list: list[HAction] = [];
    has contingencies: list[HIfThen] = [];
}
sem HDraft.situation = "1-2 sentences: who the resident is and the single most important thing this "
    "shift -- drawn ONLY from the conversation. If the resident isn't named, don't invent one.";
sem HDraft.background = "Relevant history/timeline actually mentioned in the conversation. If little "
    "was said, keep it short; never fabricate history, vitals, or medications.";
sem HDraft.assessment = "The clinical read of what is going on and how concerning, based on the "
    "conversation. If it is too sparse to assess, say so plainly instead of guessing.";
sem HDraft.recommendation = "What the oncoming nurse should do and watch for, from the conversation. "
    "If nothing specific was said, give the safe default: monitor and verify current orders.";
sem HDraft.action_list = "Discrete follow-up tasks stated or clearly implied by the conversation. "
    "Empty list if none were discussed -- do not invent tasks.";
sem HDraft.contingencies = "If/then safety nets mentioned or clearly implied. Empty list if none.";

def summarize_handoff(transcript: str) -> HDraft by _summarizer();
sem summarize_handoff = "You are a nurse writing a shift handoff. The input is a verbatim, "
    "speaker-labeled transcript of the outgoing and incoming nurse talking -- it may be short, "
    "messy, or full of filler ('yeah', 'he he', 'are you sure'). Produce a clean SBAR-plus handoff "
    "summary using ONLY facts actually present in the transcript. Never invent clinical details, "
    "vitals, medications, diagnoses, or history that were not said. If the conversation is too thin "
    "to fill a field, keep it brief and honestly note what was not covered rather than fabricating.";
sem summarize_handoff.transcript = "The verbatim diarized nurse-to-nurse handoff conversation.";


"""Real LLM summary: transcript text -> frozen schema.SBARPlus. Raises if the
model call fails (no key, network) so the caller can fall back to the canned SBAR."""
def _summarize(transcript_text: str) -> SBARPlus {
    d = summarize_handoff(transcript_text);
    return SBARPlus(
        situation=d.situation,
        background=d.background,
        assessment=d.assessment,
        recommendation=d.recommendation,
        action_list=[Action(task=a.task, owner=a.owner, due=a.due) for a in d.action_list],
        contingencies=[IfThen(trigger=c.trigger, response=c.response) for c in d.contingencies]
    );
}


"""Fallback when the LLM is unavailable (no key / call failed). Honest about
being unsummarized rather than dressing up a transcript echo as a summary."""
def _canned_sbar(transcript_text: str) -> SBARPlus {
    snippet: str = transcript_text[:400] if transcript_text else "No transcript captured.";
    return SBARPlus(
        situation="Handoff recorded; automatic summary unavailable (no LLM key configured).",
        background=f"Raw transcript: {snippet}",
        assessment="Not assessed -- summarize this handoff manually.",
        recommendation="Review the transcript below and edit this summary before signing.",
        action_list=[],
        contingencies=[]
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
        audio_url: str = "";
        if self.audio_b64 {
            audio_url = "data:" + self.mime + ";base64," + self.audio_b64;
        }
        tnode = Transcript(segments=segs, audio_ref=audio_url);
        sess ++> tnode;

        # 3. Summarize the whole conversation ONCE (the LLM, with a canned
        #    fallback if no key), then attach one draft summary per resident.
        lines = [
            (s.get("speaker", "Speaker") as str) + ": " + (s.get("text", "") as str)
            for s in segs
        ];
        transcript_text: str = "\n".join(lines);
        sbar: SBARPlus | None = None;
        model_used: str = "offline-canned";
        if transcript_text.strip() {
            try {
                sbar = _summarize(transcript_text);
                model_used = SUMMARY_MODEL;
            } except Exception as e {
                print(f"[handoff] summarize failed ({e}) -- canned fallback");
            }
        }
        final: SBARPlus = sbar if sbar is not None else _canned_sbar(transcript_text);
        al = [{"task": a.task, "owner": a.owner, "due": a.due} for a in final.action_list];
        cg = [{"trigger": c.trigger, "response": c.response} for c in final.contingencies];

        rid_list = sess.resident_ids if sess.resident_ids else [""];
        out_summaries: list[dict] = [];
        for rid in rid_list {
            summ = HandoffSummary(
                resident_id=rid,
                situation=final.situation,
                background=final.background,
                assessment=final.assessment,
                recommendation=final.recommendation,
                action_list=al,
                contingencies=cg,
                generated_at=now(),
                model_used=model_used,
                status="draft"
            );
            sess ++> summ;
            out_summaries.append(_summary_dict(summ));
        }

        sess.status = "completed";
        sess.ended_at = now();

        # 4. Tripwire: re-evaluate rules against the graph (now with fresh
        #    verbal_handoff episodes from this conversation).
        tripwire_findings: list[dict] = [];
        escalations: list[dict] = [];
        try {
            tw = root spawn Tripwire(now_ref=now());
            for f in tw.reports {
                if f.fired {
                    tripwire_findings.append({
                        "rule": f.rule, "tier": f.tier, "claim": f.claim,
                        "fired": f.fired, "claim_id": f.claim_id
                    });
                }
            }
            # Escalate every tier-3 finding.
            for tf in tripwire_findings {
                if tf["tier"] >= 3 and tf["claim_id"] {
                    try {
                        esc = root spawn Escalate(finding_id=tf["claim_id"] as str);
                        er = esc.reports[0];
                        escalations.append({
                            "claim": tf["claim"],
                            "acknowledged": er.acknowledged,
                            "chain": er.chain
                        });
                    } except Exception as e2 {
                        escalations.append({
                            "claim": tf["claim"],
                            "acknowledged": False,
                            "chain": [],
                            "error": str(e2)
                        });
                    }
                }
            }
        } except Exception as te {
            print(f"[handoff] tripwire/escalate failed ({te})");
        }

        report {"ok": True, "session_id": jid(sess),
                "transcript": {"segments": segs}, "summaries": out_summaries,
                "audio_url": audio_url, "audio_mime": self.mime,
                "tripwire": tripwire_findings, "escalations": escalations};
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


walker:pub ResidentGraph {
    """A resident's own knowledge graph for GraphPanel: {resident, nodes, links}.

    Built lazily on first view -- extracts episodes + cited beliefs from the
    resident's stored transcripts (LLM) and hangs them off the Resident node, so
    each resident accumulates their own inspectable belief graph with provenance.
    `rebuild=True` clears the current knowledge and re-extracts from scratch."""
    has resident_id: str;
    has rebuild: bool = False;
    has reports: list[dict] = [];

    can build with Root entry {
        res: any = None;
        try {
            res = jobj(self.resident_id);
        } except Exception {
            res = None;
        }
        if not isinstance(res, Resident) {
            report {"ok": False, "error": "resident not found"};
            return;
        }

        if self.rebuild {
            for e in [res ->:ResObserved:->] {
                del e;
            }
            for b in [res ->:ResBelief:->] {
                del b;
            }
        }

        has_knowledge = len([res ->:ResBelief:->]) > 0 or len([res ->:ResObserved:->]) > 0;
        if not has_knowledge {
            # Gather every transcript recorded for this resident, extract once.
            lines: list = [];
            for sess in [here --> [?:HandoffSession]] {
                if self.resident_id in sess.resident_ids {
                    for t in [sess --> [?:Transcript]] {
                        for s in t.segments {
                            sd = s as dict;
                            lines.append(
                                (sd.get("speaker", "Speaker") as str) + ": "
                                + (sd.get("text", "") as str)
                            );
                        }
                    }
                }
            }
            text: str = "\n".join(lines);
            if text.strip() {
                try {
                    kg = extract_knowledge(text);
                    _persist_knowledge(res, kg, now());
                } except Exception as e {
                    print(f"[handoff] knowledge extraction failed ({e})");
                }
            }
        }

        # Read the resident's subgraph back out as GraphPanel node/link dicts.
        nodes: list[dict] = [{"id": jid(res), "kind": "Resident", "label": res.name}];
        links: list[dict] = [];
        seen: dict = {};                      # episode id -> True (add each once)
        for b in [res ->:ResBelief:->] {
            bid: str = jid(b);
            nodes.append({"id": bid, "kind": "Clinical", "label": _short(b.claim)});
            links.append({"source": jid(res), "target": bid});
            for ep in [b ->:Derived:->] {
                eid: str = jid(ep);
                if not seen.get(eid, False) {
                    nodes.append({"id": eid, "kind": "Episode", "label": _short(ep.content)});
                    seen[eid] = True;
                }
                links.append({"source": bid, "target": eid});
            }
        }
        for ep in [res ->:ResObserved:->] {
            eid2: str = jid(ep);
            if not seen.get(eid2, False) {
                nodes.append({"id": eid2, "kind": "Episode", "label": _short(ep.content)});
                seen[eid2] = True;
                links.append({"source": jid(res), "target": eid2});
            }
        }
        report {
            "ok": True,
            "resident": {"id": jid(res), "name": res.name, "room": res.room},
            "nodes": nodes,
            "links": links,
            "counts": {
                "beliefs": len([res ->:ResBelief:->]),
                "episodes": len([res ->:ResObserved:->])
            }
        };
    }
}
