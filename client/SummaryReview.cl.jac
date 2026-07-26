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

sv import from handoff { EditSummary, SignSummary }


def:pub SummaryView(
    user: dict,
    summaries: list,
    transcript: list,
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
        return <div style={{"color": "#e5e7eb", "padding": "2rem", "textAlign": "center"}}>
            No summary was generated.
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

    return <div style={{
        "maxWidth": "720px", "margin": "1.5rem auto", "padding": "0 1rem",
        "fontFamily": "system-ui, -apple-system, sans-serif", "color": "#e5e7eb"
    }}>
        <div style={{"display": "flex", "alignItems": "center", "gap": "0.75rem"}}>
            <h1 style={{"margin": "0"}}>Handoff summary</h1>
            {if locked {
                <span style={{"background": "#064e3b", "color": "#a7f3d0", "padding": "0.2rem 0.6rem", "borderRadius": "999px", "fontSize": "0.75rem", "fontWeight": "700"}}>
                    {"SIGNED · " + (c["signed_by"] as str)}
                </span>
            } else {
                <span style={{"background": "#78350f", "color": "#fcd34d", "padding": "0.2rem 0.6rem", "borderRadius": "999px", "fontSize": "0.75rem", "fontWeight": "700"}}>
                    DRAFT · unsigned
                </span>
            }}
        </div>

        # -- resident tabs (one summary per resident)
        {if len(items) > 1 {
            <div style={{"display": "flex", "gap": "0.4rem", "marginTop": "0.8rem", "flexWrap": "wrap"}}>
                {for (ti, it) in enumerate(items) {
                    <button key={str(ti)} onClick={lambda (e: MouseEvent) { activeIdx = ti; showTranscript = False; }} style={{
                        "padding": "0.35rem 0.7rem", "borderRadius": "8px", "cursor": "pointer",
                        "border": "1px solid #2563eb" if ti == activeIdx else "1px solid #374151",
                        "background": "#132038" if ti == activeIdx else "#111827", "color": "#e5e7eb"
                    }}>{(it as dict).get("resident_name", "Resident") as str}</button>
                }}
            </div>
        }}

        <p style={{"color": "#9ca3af", "marginTop": "0.6rem"}}>
            {"Resident: " + (c.get("resident_name", "—") as str) + " · " + (c["model_used"] as str)}
        </p>

        {if notice {
            <div style={{"background": "#064e3b", "color": "#a7f3d0", "padding": "0.5rem 0.8rem", "borderRadius": "8px", "marginBottom": "0.8rem", "fontSize": "0.85rem"}}>{notice}</div>
        }}
        {if errorMsg {
            <div style={{"background": "#7f1d1d", "color": "#fecaca", "padding": "0.5rem 0.8rem", "borderRadius": "8px", "marginBottom": "0.8rem", "fontSize": "0.85rem"}}>{errorMsg}</div>
        }}

        # -- SBAR narrative fields
        {for (fi, f) in enumerate(fields) {
            <div key={str(fi)} style={{"marginBottom": "0.9rem"}}>
                <label style={{"fontSize": "0.8rem", "color": "#93c5fd", "fontWeight": "600"}}>{f["label"] as str}</label>
                <textarea
                    value={c[f["k"] as str] as str}
                    disabled={locked}
                    onChange={lambda (e: any) { setField(f["k"] as str, e.target.value); }}
                    style={{
                        "width": "100%", "boxSizing": "border-box", "marginTop": "0.3rem",
                        "minHeight": "62px", "padding": "0.55rem 0.7rem", "background": "#0b1220" if not locked else "#0a0f1a",
                        "color": "#e5e7eb", "border": "1px solid #374151", "borderRadius": "8px",
                        "fontFamily": "inherit", "fontSize": "0.92rem", "resize": "vertical"
                    }}
                ></textarea>
            </div>
        }}

        # -- action list
        <div style={{"marginTop": "0.5rem"}}>
            <div style={{"fontSize": "0.8rem", "color": "#93c5fd", "fontWeight": "600", "marginBottom": "0.4rem"}}>Action list</div>
            {for (ai, a) in enumerate(c["action_list"] as list) {
                <div key={str(ai)} style={{"display": "flex", "gap": "0.4rem", "marginBottom": "0.4rem"}}>
                    <input value={(a as dict)["task"] as str} disabled={locked}
                        onChange={lambda (e: any) { setRow("action_list", ai, "task", e.target.value); }}
                        placeholder="task" style={{"flex": "3", "minWidth": "0", "padding": "0.4rem 0.55rem", "background": "#111827", "color": "#e5e7eb", "border": "1px solid #374151", "borderRadius": "6px"}}/>
                    <input value={(a as dict)["owner"] as str} disabled={locked}
                        onChange={lambda (e: any) { setRow("action_list", ai, "owner", e.target.value); }}
                        placeholder="owner" style={{"flex": "1", "minWidth": "0", "padding": "0.4rem 0.55rem", "background": "#111827", "color": "#e5e7eb", "border": "1px solid #374151", "borderRadius": "6px"}}/>
                    <input value={(a as dict)["due"] as str} disabled={locked}
                        onChange={lambda (e: any) { setRow("action_list", ai, "due", e.target.value); }}
                        placeholder="due" style={{"flex": "1", "minWidth": "0", "padding": "0.4rem 0.55rem", "background": "#111827", "color": "#e5e7eb", "border": "1px solid #374151", "borderRadius": "6px"}}/>
                </div>
            }}
        </div>

        # -- contingencies
        <div style={{"marginTop": "0.9rem"}}>
            <div style={{"fontSize": "0.8rem", "color": "#93c5fd", "fontWeight": "600", "marginBottom": "0.4rem"}}>Contingencies (if / then)</div>
            {for (ci, ct) in enumerate(c["contingencies"] as list) {
                <div key={str(ci)} style={{"display": "flex", "gap": "0.4rem", "marginBottom": "0.4rem"}}>
                    <input value={(ct as dict)["trigger"] as str} disabled={locked}
                        onChange={lambda (e: any) { setRow("contingencies", ci, "trigger", e.target.value); }}
                        placeholder="if…" style={{"flex": "1", "minWidth": "0", "padding": "0.4rem 0.55rem", "background": "#111827", "color": "#e5e7eb", "border": "1px solid #374151", "borderRadius": "6px"}}/>
                    <input value={(ct as dict)["response"] as str} disabled={locked}
                        onChange={lambda (e: any) { setRow("contingencies", ci, "response", e.target.value); }}
                        placeholder="then…" style={{"flex": "1", "minWidth": "0", "padding": "0.4rem 0.55rem", "background": "#111827", "color": "#e5e7eb", "border": "1px solid #374151", "borderRadius": "6px"}}/>
                </div>
            }}
        </div>

        # -- source transcript (provenance)
        <div style={{"marginTop": "1rem"}}>
            <button onClick={toggleTranscript} style={{
                "background": "none", "border": "1px solid #374151", "color": "#93c5fd",
                "padding": "0.4rem 0.7rem", "borderRadius": "8px", "cursor": "pointer", "fontSize": "0.85rem"
            }}>{("Hide" if showTranscript else "View") + " source transcript"}</button>
            {if showTranscript {
                <div style={{"marginTop": "0.6rem", "background": "#0b1220", "border": "1px solid #1f2937", "borderRadius": "10px", "padding": "0.8rem"}}>
                    {if len(transcript) == 0 {
                        <p style={{"color": "#6b7280", "margin": "0"}}>No transcript captured.</p>
                    }}
                    {for (si, s) in enumerate(transcript) {
                        <div key={str(si)} style={{"marginBottom": "0.4rem", "fontSize": "0.9rem"}}>
                            <span style={{"color": "#60a5fa", "fontWeight": "600", "marginRight": "0.5rem"}}>{(s as dict)["speaker"] as str}</span>
                            <span>{(s as dict)["text"] as str}</span>
                        </div>
                    }}
                </div>
            }}
        </div>

        # -- actions
        <div style={{"display": "flex", "gap": "0.6rem", "marginTop": "1.4rem", "alignItems": "center"}}>
            {if not locked {
                <button onClick={onSave} disabled={busy} style={{
                    "padding": "0.6rem 1.1rem", "background": "#374151", "color": "white",
                    "border": "none", "borderRadius": "8px", "cursor": "pointer", "fontWeight": "600"
                }}>Save draft</button>
            }}
            {if not locked {
                <button onClick={onSign} disabled={busy or not canSign} title={"" if canSign else "Only RN or LPN can sign off"} style={{
                    "padding": "0.6rem 1.1rem", "background": "#16a34a" if canSign else "#1f2937",
                    "color": "white" if canSign else "#6b7280", "border": "none", "borderRadius": "8px",
                    "cursor": "pointer" if canSign else "not-allowed", "fontWeight": "600"
                }}>{"Sign off" if canSign else "Sign off (RN/LPN only)"}</button>
            }}
            <button onClick={lambda (e: MouseEvent) { onDone(); }} style={{
                "marginLeft": "auto", "padding": "0.6rem 1.1rem", "background": "none",
                "color": "#93c5fd", "border": "1px solid #374151", "borderRadius": "8px", "cursor": "pointer"
            }}>Done → past handoffs</button>
        </div>
    </div>;
}
