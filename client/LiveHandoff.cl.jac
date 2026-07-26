"""Live handoff capture screen (PRD §9, live-mic branch).

Press record, speak the shift handoff, watch it transcribe in real time with
speaker labels. Every finalized utterance becomes a verbal_handoff Episode on
the graph as it lands (IngestUtterance) -- so by the time you stop, the graph
already holds the conversation and the omission check runs against it.

State discipline (jac-cl-js-interop): the callbacks handed to the transcription
service are captured once, at start(), and would read stale `has` state. So the
finalized transcript lives in the service module; here we only ever OVERWRITE
state from an always-current source (getSegments()) or from the callback's own
argument -- never `x = x + arg`. That is why there is no manual counter.
"""

import from .live_transcribe { startLive, stopLive, getSegments, clearSegments, fullTranscript }

sv import from realtime { IngestUtterance }
sv import from omission { OmissionPanel }
sv import from tripwire { Tripwire }
sv import from escalate { Escalate }


def:pub LiveHandoff() -> JsxElement {
    has status: str = "idle";          # idle | connecting | listening | stopped
    has interim: str = "";             # the partial being spoken right now
    has segments: list = [];           # finalized utterances (mirror of service)
    has errorMsg: str = "";
    has omissions: list = [];          # claims the graph required, talk skipped
    has omissionRan: bool = False;
    has tripwireRan: bool = False;
    has firedFindings: list = [];   # findings from the post-handoff tripwire
    has escalatedFindings: list = []; # tier-3 findings that were escalated
    has shift: str = "D5-night";

    # -- transcription-service callbacks (captured once at start) --------------
    def cbInterim(t: str) -> None { interim = t; }
    def cbStatus(s: str) -> None { status = s; }
    def cbError(m: str) -> None { errorMsg = m; status = "idle"; }

    # A finalized utterance: overwrite from the always-current service list, and
    # persist it as an Episode. No stale reads -- getSegments() is authoritative.
    async def cbFinal(seg: dict) -> None {
        interim = "";
        segments = getSegments();
        root spawn IngestUtterance(
            text=seg["text"], speaker=seg["speaker"],
            start=seg["start"], shift=shift
        );
    }

    def start(e: MouseEvent) -> None {
        errorMsg = "";
        omissions = [];
        omissionRan = False;
        tripwireRan = False;
        firedFindings = [];
        escalatedFindings = [];
        segments = [];
        interim = "";
        clearSegments();
        startLive({
            "onInterim": cbInterim, "onFinal": cbFinal,
            "onStatus": cbStatus, "onError": cbError
        });
    }

    # Stop the mic, run the omission check, then re-evaluate the tripwire
    # against the freshly ingested episodes. If a new corroboration pushes a
    # Clinical belief past the threshold, the phone rings — right here, from
    # the live handoff screen.
    async def stop(e: MouseEvent) -> None {
        stopLive();
        status = "stopped";
        interim = "";
        transcript = fullTranscript();
        if not transcript.strip() {
            return;
        }
        # -- omission check (post-hoc, what the conversation skipped) -------
        try {
            res = root spawn OmissionPanel(transcript=transcript);
            missed = res.reports[0];
            omissions = [c.claim for c in missed];
            omissionRan = True;
        } except Exception as err {
            errorMsg = "Omission check unavailable (needs a model key): " + str(err);
        }
        # -- tripwire: re-evaluate rules with the new episodes in the graph --
        try {
            tw = root spawn Tripwire(now_ref=0.0);
            firedFindings = [{rule: f.rule, tier: f.tier, claim: f.claim,
                              fired: f.fired, claim_id: f.claim_id}
                             for f in tw.reports if f.fired];
            tripwireRan = True;
            # Escalate every tier-3 finding — this is where the phone rings.
            escalatedFindings = [];
            for f in firedFindings {
                if f.tier >= 3 and f.claim_id {
                    try {
                        esc = root spawn Escalate(finding_id=f.claim_id);
                        er = esc.reports[0];
                        escalatedFindings.append({
                            claim: f.claim,
                            acknowledged: er.acknowledged,
                            chain: er.chain,
                        });
                    } except Exception as e2 {
                        escalatedFindings.append({
                            claim: f.claim,
                            acknowledged: False,
                            chain: [],
                            error: str(e2),
                        });
                    }
                }
            }
        } except Exception as err2 {
            errorMsg = "Tripwire unavailable: " + str(err2);
        }
    }

    listening = status == "listening" or status == "connecting";

    return <div style={{
        "maxWidth": "760px", "margin": "1.5rem auto", "padding": "0 1rem",
        "fontFamily": "system-ui, -apple-system, sans-serif", "color": "#e5e7eb"
    }}>
        <div style={{"display": "flex", "alignItems": "baseline", "gap": "0.75rem"}}>
            <h1 style={{"margin": "0"}}>Live Handoff</h1>
            <span style={{"color": "#9ca3af", "fontSize": "0.9rem"}}>
                {"Room 3B · shift " + shift}
            </span>
        </div>
        <p style={{"color": "#9ca3af", "marginTop": "0.25rem"}}>
            Real-time transcription. Each finalized line is written to the belief
            graph as it is spoken.
        </p>

        # -- controls + live status
        <div style={{"display": "flex", "alignItems": "center", "gap": "0.75rem", "margin": "1rem 0"}}>
            {if listening {
                <button onClick={stop} style={{
                    "padding": "0.6rem 1.3rem", "background": "#dc2626",
                    "color": "white", "border": "none", "borderRadius": "8px",
                    "cursor": "pointer", "fontWeight": "600"
                }}>■ Stop &amp; check</button>
            } else {
                <button onClick={start} style={{
                    "padding": "0.6rem 1.3rem", "background": "#16a34a",
                    "color": "white", "border": "none", "borderRadius": "8px",
                    "cursor": "pointer", "fontWeight": "600"
                }}>● Start handoff</button>
            }}
            <span style={{
                "display": "inline-flex", "alignItems": "center", "gap": "0.4rem",
                "color": "#9ca3af", "fontSize": "0.9rem"
            }}>
                <span style={{
                    "width": "9px", "height": "9px", "borderRadius": "50%",
                    "background": "#ef4444" if status == "listening" else "#6b7280"
                }}></span>
                {status}
            </span>
            <span style={{"marginLeft": "auto", "color": "#9ca3af", "fontSize": "0.9rem"}}>
                {str(len(segments)) + " episodes captured"}
            </span>
        </div>

        {if errorMsg {
            <div style={{
                "background": "#7f1d1d", "color": "#fecaca", "padding": "0.6rem 0.9rem",
                "borderRadius": "8px", "marginBottom": "1rem", "fontSize": "0.9rem"
            }}>{errorMsg}</div>
        }}

        # -- transcript
        <div style={{
            "background": "#0b1220", "border": "1px solid #1f2937", "borderRadius": "10px",
            "padding": "1rem", "minHeight": "220px"
        }}>
            {if len(segments) == 0 and not interim {
                <p style={{"color": "#6b7280", "margin": "0"}}>
                    Transcript will appear here as you speak…
                </p>
            }}
            {for (i, s) in enumerate(segments) {
                <div key={str(i)} style={{"marginBottom": "0.6rem"}}>
                    <span style={{
                        "color": "#60a5fa", "fontWeight": "600", "fontSize": "0.8rem",
                        "marginRight": "0.5rem"
                    }}>{s["speaker"]}</span>
                    <span style={{"color": "#e5e7eb"}}>{s["text"]}</span>
                </div>
            }}
            {if interim {
                <div style={{"color": "#9ca3af", "fontStyle": "italic"}}>{interim + " …"}</div>
            }}
        </div>

        # -- omission panel (post-hoc)
        {if omissionRan {
            <div style={{"marginTop": "1.25rem"}}>
                {if len(omissions) == 0 {
                    <div style={{
                        "background": "#064e3b", "color": "#a7f3d0", "padding": "0.8rem 1rem",
                        "borderRadius": "10px"
                    }}>Nothing required by the graph was missed in this handoff.</div>
                } else {
                    <div style={{
                        "background": "#1f2937", "border": "1px solid #b45309", "borderRadius": "10px",
                        "padding": "1rem"
                    }}>
                        <div style={{"color": "#fbbf24", "fontWeight": "700", "marginBottom": "0.5rem"}}>
                            {"Not conveyed in this handoff (" + str(len(omissions)) + ")"}
                        </div>
                        {for (j, claim) in enumerate(omissions) {
                            <div key={str(j)} style={{
                                "color": "#fde68a", "padding": "0.3rem 0", "fontSize": "0.92rem"
                            }}>{"· " + claim}</div>
                        }}
                    </div>
                }}
            </div>
        }}
        # -- tripwire findings + escalation result
        {if tripwireRan {
            <div style={{"marginTop": "1.25rem"}}>
                {if len(firedFindings) == 0 {
                    <div style={{
                        "background": "#1f2937", "color": "#9ca3af",
                        "padding": "0.8rem 1rem", "borderRadius": "10px"
                    }}>No new findings fired. The graph saw nothing new that crossed a threshold.</div>
                } else {
                    <div style={{
                        "background": "#1f2937", "border": "1px solid #374151",
                        "borderRadius": "10px", "padding": "1rem"
                    }}>
                        <div style={{"color": "#fbbf24", "fontWeight": "700", "marginBottom": "0.5rem"}}>
                            {"Findings fired (" + str(len(firedFindings)) + ")"}
                        </div>
                        {for (k, f) in enumerate(firedFindings) {
                            <div key={str(k)} style={{
                                "padding": "0.4rem 0", "fontSize": "0.9rem",
                                "display": "flex", "justifyContent": "space-between",
                                "color": "#d1d5db"
                            }}>
                                <span style={{"flex": "1"}}>{f.rule + "  — " + f.claim}</span>
                                <span style={{
                                    "background": "#dc2626" if f.tier >= 3 else "#d97706",
                                    "color": "white", "padding": "0.15rem 0.5rem",
                                    "borderRadius": "6px", "fontSize": "0.8rem",
                                    "fontWeight": "600"
                                }}>{"T" + str(f.tier) + (" 📞" if f.tier >= 3 else "")}</span>
                            </div>
                        }}
                        {if len(escalatedFindings) > 0 {
                            <div style={{"marginTop": "0.75rem"}}>
                                <div style={{"color": "#fbbf24", "fontWeight": "700", "marginBottom": "0.4rem"}}>
                                    Escalation results
                                </div>
                                {for (j, e) in enumerate(escalatedFindings) {
                                    <div key={str(j)} style={{
                                        "padding": "0.4rem 0.6rem", "marginBottom": "0.3rem",
                                        "borderRadius": "8px", "fontSize": "0.85rem",
                                        "background": "#064e3b" if e.acknowledged else "#7f1d1d"
                                    }}>
                                        <div style={{"color": "#a7f3d0" if e.acknowledged else "#fecaca", "fontWeight": "600"}}>
                                            {e.claim}
                                        </div>
                                        <div style={{"color": "#9ca3af", "marginTop": "0.15rem"}}>
                                            {if e.acknowledged {
                                                "Acknowledged by " + e.chain[len(e.chain) - 1]
                                            } else {
                                                "Not acknowledged" + (" — " + e.chain[len(e.chain) - 1] + " reached" if len(e.chain) > 0 else "")
                                            }}
                                        </div>
                                    </div>
                                }}
                            </div>
                        }}
                    </div>
                }}
            </div>
        }}
    </div>;
}
