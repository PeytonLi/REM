"""Summary review, edit & sign-off screen (PRD 5.4-5.5).

Opens on the auto-generated draft SBAR-plus summary (one per resident). The
outgoing nurse edits any field, then signs off -- signing records who + when
(SignSummary) and locks the summary from further edits. Sign-off is gated to
RN/LPN; a CNA sees the sign button disabled. "View source transcript" reveals
the transcript the summary was composed from -- the provenance behind the lines.

Editing writes back with EditSummary on Save/Sign; nested action_list /
contingencies are edited in place and the whole `items` list is re-referenced so
the view re-renders (reactive state needs a fresh ref, not an in-place mutation).
"""

import from .theme { speakerColor, initials }
sv import from handoff { EditSummary, SignSummary }


def:pub SummaryView(
    user: dict,
    summaries: list,
    transcript: list,
    audioUrl: str = "",
    audioMime: str = "audio/webm",
    tripwire: list = [],
    escalations: list = [],
    onDone: Callable[[], None]
) -> JsxElement {
    has items: list = summaries;
    has activeIdx: int = 0;
    has showTranscript: bool = False;
    has busy: bool = False;
    has errorMsg: str = "";
    has notice: str = "";

    canSign = (user.get("role", "") as str) in ["RN", "LPN"];

    def cur() -> dict {
        return items[activeIdx] as dict;
    }

    def isLocked() -> bool {
        return (cur()["status"] as str) == "signed";
    }

    def setField(field: str, value: str) -> None {
        c = cur();
        c[field] = value;
        items = items[:];
    }

    def setRow(listkey: str, idx: int, field: str, value: str) -> None {
        rows = cur()[listkey] as list;
        (rows[idx] as dict)[field] = value;
        items = items[:];
    }

    async def save(sign: bool) -> None {
        errorMsg = "";
        notice = "";
        busy = True;
        c = cur();
        try {
            res = root spawn EditSummary(
                summary_id=c["id"] as str,
                situation=c["situation"] as str,
                background=c["background"] as str,
                assessment=c["assessment"] as str,
                recommendation=c["recommendation"] as str,
                action_list=c["action_list"] as list,
                contingencies=c["contingencies"] as list
            );
            edited = res.reports[0];
            if not edited["ok"] {
                errorMsg = edited["error"] as str;
                busy = False;
                return;
            }
            if sign {
                sres = root spawn SignSummary(
                    summary_id=c["id"] as str,
                    signed_by=user.get("name", "") as str,
                    role=user.get("role", "") as str
                );
                signed = sres.reports[0];
                if not signed["ok"] {
                    errorMsg = signed["error"] as str;
                    busy = False;
                    return;
                }
                items[activeIdx] = signed["summary"];
                items = items[:];
                notice = "Signed off. This summary is now locked.";
            } else {
                notice = "Draft saved.";
            }
        } except Exception as err {
            errorMsg = "Save failed: " + str(err);
        }
        busy = False;
    }

    async def onSave(e: MouseEvent) -> None { await save(False); }
    async def onSign(e: MouseEvent) -> None { await save(True); }
    def toggleTranscript(e: MouseEvent) -> None { showTranscript = not showTranscript; }

    if len(items) == 0 {
        return <div className="container">
            <div className="empty">No summary was generated.</div>
        </div>;
    }

    c = cur();
    locked = isLocked();
    fields = [
        {"k": "situation", "label": "Situation"},
        {"k": "background", "label": "Background"},
        {"k": "assessment", "label": "Assessment"},
        {"k": "recommendation", "label": "Recommendation"}
    ];

    return <div className="container">
        <div style={{"display": "flex", "alignItems": "center", "gap": "0.75rem"}}>
            <h1 className="h1">Handoff summary</h1>
            {if locked {
                <span className="badge badge-success">{"SIGNED · " + (c["signed_by"] as str)}</span>
            } else {
                <span className="badge badge-warn">DRAFT · unsigned</span>
            }}
        </div>

        {if len(items) > 1 {
            <div className="tabs" style={{"marginTop": "0.8rem"}}>
                {for (ti, it) in enumerate(items) {
                    <button key={str(ti)} onClick={lambda (e: MouseEvent) { activeIdx = ti; showTranscript = False; }}
                        className={"tab tab-active" if ti == activeIdx else "tab"}>
                        {(it as dict).get("resident_name", "Resident") as str}
                    </button>
                }}
            </div>
        }}

        <p className="muted" style={{"marginTop": "0.6rem", "fontSize": "0.88rem"}}>
            {"Resident: " + (c.get("resident_name", "—") as str) + " · " + (c["model_used"] as str)}
        </p>

        {if notice {
            <div className="alert alert-success" style={{"marginBottom": "0.8rem"}}>{notice}</div>
        }}
        {if errorMsg {
            <div className="alert alert-error" style={{"marginBottom": "0.8rem"}}>{errorMsg}</div>
        }}

        <div className="card">
            {for (fi, f) in enumerate(fields) {
                <div key={str(fi)} style={{"marginBottom": "0.9rem"}}>
                    <label className="field">{f["label"] as str}</label>
                    <textarea
                        value={c[f["k"] as str] as str}
                        disabled={locked}
                        onChange={lambda (e: any) { setField(f["k"] as str, e.target.value); }}
                        className="textarea"
                        style={{"marginTop": "0.35rem"}}
                    ></textarea>
                </div>
            }}

            <div style={{"marginTop": "0.5rem"}}>
                <div className="field" style={{"marginBottom": "0.45rem"}}>Action list</div>
                {for (ai, a) in enumerate(c["action_list"] as list) {
                    <div key={str(ai)} style={{"display": "flex", "gap": "0.4rem", "marginBottom": "0.4rem"}}>
                        <input value={(a as dict)["task"] as str} disabled={locked}
                            onChange={lambda (e: any) { setRow("action_list", ai, "task", e.target.value); }}
                            placeholder="task" className="input" style={{"flex": "3", "minWidth": "0"}}/>
                        <input value={(a as dict)["owner"] as str} disabled={locked}
                            onChange={lambda (e: any) { setRow("action_list", ai, "owner", e.target.value); }}
                            placeholder="owner" className="input" style={{"flex": "1", "minWidth": "0"}}/>
                        <input value={(a as dict)["due"] as str} disabled={locked}
                            onChange={lambda (e: any) { setRow("action_list", ai, "due", e.target.value); }}
                            placeholder="due" className="input" style={{"flex": "1", "minWidth": "0"}}/>
                    </div>
                }}
            </div>

            <div style={{"marginTop": "0.9rem"}}>
                <div className="field" style={{"marginBottom": "0.45rem"}}>Contingencies (if / then)</div>
                {for (ci, ct) in enumerate(c["contingencies"] as list) {
                    <div key={str(ci)} style={{"display": "flex", "gap": "0.4rem", "marginBottom": "0.4rem"}}>
                        <input value={(ct as dict)["trigger"] as str} disabled={locked}
                            onChange={lambda (e: any) { setRow("contingencies", ci, "trigger", e.target.value); }}
                            placeholder="if…" className="input" style={{"flex": "1", "minWidth": "0"}}/>
                        <input value={(ct as dict)["response"] as str} disabled={locked}
                            onChange={lambda (e: any) { setRow("contingencies", ci, "response", e.target.value); }}
                            placeholder="then…" className="input" style={{"flex": "1", "minWidth": "0"}}/>
                    </div>
                }}
            </div>
        </div>

        <div style={{"marginTop": "1rem"}}>
            <button onClick={toggleTranscript} className="btn btn-outline btn-sm">
                {("Hide" if showTranscript else "View") + " source transcript"}
            </button>
            {if showTranscript {
                <div className="card" style={{"marginTop": "0.6rem"}}>
                    {if len(transcript) == 0 {
                        <p className="muted" style={{"margin": "0"}}>No transcript captured.</p>
                    }}
                    <div className="feed">
                        {for (si, s) in enumerate(transcript) {
                            spk = (s as dict)["speaker"] as str;
                            <div key={str(si)} className="msg">
                                <div className="msg-av" style={{"background": speakerColor(spk)}}>{initials(spk)}</div>
                                <div className="msg-main">
                                    <div className="msg-head"><span className="msg-name">{spk}</span></div>
                                    <div className="msg-body">{(s as dict)["text"] as str}</div>
                                </div>
                            </div>
                        }}
                    </div>
                </div>
            }}
        </div>

        # -- audio recording playback --------------------------------------
        {if audioUrl {
            <div style={{
                "marginTop": "1.5rem", "background": "#020617",
                "border": "1px solid #374151", "borderRadius": "14px",
                "padding": "1.25rem"
            }}>
                <div style={{
                    "display": "flex", "alignItems": "center", "gap": "0.5rem",
                    "marginBottom": "0.75rem"
                }}>
                    <span style={{"fontSize": "1.4rem"}}>🎙️</span>
                    <div>
                        <div style={{"color": "#f1f5f9", "fontWeight": "700", "fontSize": "0.95rem"}}>
                            Handoff Recording
                        </div>
                        <div style={{"color": "#6b7280", "fontSize": "0.8rem"}}>
                            Ground-truth source for all transcribed episodes
                        </div>
                    </div>
                </div>
                <audio
                    controls
                    style={{"width": "100%", "height": "48px", "borderRadius": "8px"}}
                >
                    <source src={audioUrl} type={audioMime}/>
                </audio>
            </div>
        }}

        # -- tripwire findings + escalation results -------------------------
        {if len(tripwire) > 0 {
            <div style={{
                "marginTop": "1.25rem", "background": "#1f2937",
                "border": "1px solid #374151", "borderRadius": "10px",
                "padding": "1rem"
            }}>
                <div style={{"color": "#fbbf24", "fontWeight": "700", "marginBottom": "0.5rem"}}>
                    {"Findings fired (" + str(len(tripwire)) + ")"}
                </div>
                {for (k, f) in enumerate(tripwire) {
                    <div key={str(k)} style={{
                        "padding": "0.4rem 0", "fontSize": "0.9rem",
                        "display": "flex", "justifyContent": "space-between",
                        "color": "#d1d5db"
                    }}>
                        <span style={{"flex": "1"}}>{(f as dict)["rule"] as str + " — " + (f as dict)["claim"] as str}</span>
                        <span style={{
                            "background": "#dc2626" if ((f as dict)["tier"] as int) >= 3 else "#d97706",
                            "color": "white", "padding": "0.15rem 0.5rem",
                            "borderRadius": "6px", "fontSize": "0.8rem",
                            "fontWeight": "600"
                        }}>{"T" + str((f as dict)["tier"] as int) + (" 📞" if ((f as dict)["tier"] as int) >= 3 else "")}</span>
                    </div>
                }}
                {if len(escalations) > 0 {
                    <div style={{"marginTop": "0.75rem"}}>
                        <div style={{"color": "#fbbf24", "fontWeight": "700", "marginBottom": "0.4rem"}}>
                            Escalation results
                        </div>
                        {for (j, e) in enumerate(escalations) {
                            ed = e as dict;
                            acked = ed["acknowledged"] as bool;
                            chain = ed["chain"] as list;
                            label = ("Acknowledged by " + (chain[len(chain) - 1] as str)) if acked and len(chain) > 0 else ("Not acknowledged");
                            <div key={str(j)} style={{
                                "padding": "0.4rem 0.6rem", "marginBottom": "0.3rem",
                                "borderRadius": "8px", "fontSize": "0.85rem",
                                "background": "#064e3b" if acked else "#7f1d1d"
                            }}>
                                <div style={{"color": "#a7f3d0" if acked else "#fecaca", "fontWeight": "600"}}>
                                    {ed["claim"] as str}
                                </div>
                                <div style={{"color": "#9ca3af", "marginTop": "0.15rem"}}>
                                    {label}
                                </div>
                            </div>
                        }}
                    </div>
                }}
            </div>
        }}

        <div style={{"display": "flex", "gap": "0.6rem", "marginTop": "1.4rem", "alignItems": "center"}}>
            {if not locked {
                <button onClick={onSave} disabled={busy} className="btn btn-outline">Save draft</button>
            }}
            {if not locked {
                <button onClick={onSign} disabled={busy or not canSign} className="btn btn-success"
                    title={"" if canSign else "Only RN or LPN can sign off"}>
                    {"Sign off" if canSign else "Sign off (RN/LPN only)"}
                </button>
            }}
            <button onClick={lambda (e: MouseEvent) { onDone(); }} className="btn btn-ghost" style={{"marginLeft": "auto"}}>
                Done → past handoffs
            </button>
        </div>
    </div>;
}
