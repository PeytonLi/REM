"""Retrieval screen (PRD 5.6).

Pick a resident, see their handoffs newest-first, each flagged draft or signed so
an incoming nurse never mistakes an unsigned draft for a finalized handoff. Open
one to read the SBAR-plus summary and drill into the source transcript behind it
(the provenance). Drafts and signed summaries both appear; only the badge differs.
"""

sv import from handoff { Roster, ListHandoffs, HandoffDetail }


def:pub RetrieveView(
    onNew: Callable[[], None],
    onInspect: Callable[[dict], None]
) -> JsxElement {
    has residents: list = [];
    has selectedRid: str = "";
    has selectedName: str = "";
    has selectedRoom: str = "";
    has handoffs: list = [];
    has detail: dict = {};
    has loading: bool = False;
    has errorMsg: str = "";

    async can with entry {
        try {
            res = root spawn Roster();
            residents = res.reports[0]["residents"] as list;
        } except Exception as e {
            errorMsg = "Could not load residents: " + str(e);
        }
    }

    async def pickResident(rid: str, name: str, room: str) -> None {
        selectedRid = rid;
        selectedName = name;
        selectedRoom = room;
        detail = {};
        loading = True;
        errorMsg = "";
        try {
            res = root spawn ListHandoffs(resident_id=rid);
            handoffs = res.reports[0]["handoffs"] as list;
        } except Exception as e {
            errorMsg = "Could not load handoffs: " + str(e);
        }
        loading = False;
    }

    async def openDetail(sid: str) -> None {
        loading = True;
        try {
            res = root spawn HandoffDetail(session_id=sid);
            detail = res.reports[0] as dict;
        } except Exception as e {
            errorMsg = "Could not load handoff: " + str(e);
        }
        loading = False;
    }

    def closeDetail(e: MouseEvent) -> None { detail = {}; }

    def badge(status: str) -> JsxElement {
        if status == "signed" {
            return <span style={{"background": "#064e3b", "color": "#a7f3d0", "padding": "0.15rem 0.5rem", "borderRadius": "999px", "fontSize": "0.72rem", "fontWeight": "700"}}>SIGNED</span>;
        }
        return <span style={{"background": "#78350f", "color": "#fcd34d", "padding": "0.15rem 0.5rem", "borderRadius": "999px", "fontSize": "0.72rem", "fontWeight": "700"}}>DRAFT</span>;
    }

    return <div style={{
        "maxWidth": "720px", "margin": "1.5rem auto", "padding": "0 1rem",
        "fontFamily": "system-ui, -apple-system, sans-serif", "color": "#e5e7eb"
    }}>
        <div style={{"display": "flex", "alignItems": "center", "gap": "0.75rem"}}>
            <h1 style={{"margin": "0"}}>Past handoffs</h1>
            <button onClick={lambda (e: MouseEvent) { onNew(); }} style={{
                "marginLeft": "auto", "padding": "0.5rem 0.9rem", "background": "#16a34a",
                "color": "white", "border": "none", "borderRadius": "8px", "cursor": "pointer", "fontWeight": "600"
            }}>＋ New handoff</button>
        </div>

        {if errorMsg {
            <div style={{"background": "#7f1d1d", "color": "#fecaca", "padding": "0.5rem 0.8rem", "borderRadius": "8px", "margin": "0.8rem 0", "fontSize": "0.85rem"}}>{errorMsg}</div>
        }}

        # -- resident picker
        <div style={{"display": "flex", "gap": "0.4rem", "flexWrap": "wrap", "margin": "1rem 0"}}>
            {for (ri, r) in enumerate(residents) {
                rid = (r as dict)["id"] as str;
                rname = (r as dict)["name"] as str;
                rroom = (r as dict)["room"] as str;
                <button key={str(ri)} onClick={lambda (e: MouseEvent) { pickResident(rid, rname, rroom); }} style={{
                    "padding": "0.45rem 0.8rem", "borderRadius": "999px", "cursor": "pointer",
                    "border": "1px solid #2563eb" if rid == selectedRid else "1px solid #374151",
                    "background": "#132038" if rid == selectedRid else "#111827", "color": "#e5e7eb"
                }}>{rname + " · " + rroom}</button>
            }}
        </div>

        {if selectedRid {
            <button onClick={lambda (e: MouseEvent) { onInspect({"id": selectedRid, "name": selectedName, "room": selectedRoom}); }} style={{
                "padding": "0.5rem 0.9rem", "background": "#4338ca", "color": "white",
                "border": "none", "borderRadius": "8px", "cursor": "pointer", "fontWeight": "600",
                "marginBottom": "0.6rem"
            }}>{"🧠 " + selectedName + "'s knowledge graph"}</button>
        }}

        {if loading {
            <p style={{"color": "#9ca3af"}}>Loading…</p>
        }}

        # -- detail view (open handoff) OR the list
        {if detail.get("ok", False) {
            <div style={{"background": "#0b1220", "border": "1px solid #1f2937", "borderRadius": "12px", "padding": "1.1rem"}}>
                <button onClick={closeDetail} style={{"background": "none", "border": "none", "color": "#93c5fd", "cursor": "pointer", "padding": "0", "marginBottom": "0.6rem"}}>← back to list</button>
                {for (di, sm) in enumerate(detail["summaries"] as list) {
                    <div key={str(di)} style={{"marginBottom": "1rem"}}>
                        <div style={{"display": "flex", "alignItems": "center", "gap": "0.5rem", "marginBottom": "0.5rem"}}>
                            <strong>{(sm as dict).get("resident_name", "Resident") as str}</strong>
                            {badge((sm as dict)["status"] as str)}
                            {if ((sm as dict)["status"] as str) == "signed" {
                                <span style={{"color": "#9ca3af", "fontSize": "0.8rem"}}>{"signed by " + ((sm as dict)["signed_by"] as str)}</span>
                            }}
                        </div>
                        <p style={{"margin": "0.2rem 0"}}><span style={{"color": "#93c5fd"}}>S: </span>{(sm as dict)["situation"] as str}</p>
                        <p style={{"margin": "0.2rem 0"}}><span style={{"color": "#93c5fd"}}>B: </span>{(sm as dict)["background"] as str}</p>
                        <p style={{"margin": "0.2rem 0"}}><span style={{"color": "#93c5fd"}}>A: </span>{(sm as dict)["assessment"] as str}</p>
                        <p style={{"margin": "0.2rem 0"}}><span style={{"color": "#93c5fd"}}>R: </span>{(sm as dict)["recommendation"] as str}</p>
                    </div>
                }}
                <div style={{"borderTop": "1px solid #1f2937", "paddingTop": "0.7rem", "marginTop": "0.5rem"}}>
                    <div style={{"color": "#9ca3af", "fontSize": "0.8rem", "marginBottom": "0.4rem"}}>Source transcript</div>
                    {for (ti, s) in enumerate(detail["transcript"] as list) {
                        <div key={str(ti)} style={{"fontSize": "0.88rem", "marginBottom": "0.3rem"}}>
                            <span style={{"color": "#60a5fa", "fontWeight": "600", "marginRight": "0.5rem"}}>{(s as dict)["speaker"] as str}</span>
                            <span>{(s as dict)["text"] as str}</span>
                        </div>
                    }}
                </div>
            </div>
        }}

        {if selectedRid and not detail.get("ok", False) and not loading {
            <div>
                {if len(handoffs) == 0 {
                    <p style={{"color": "#6b7280"}}>{"No handoffs recorded for " + selectedName + " yet."}</p>
                }}
                {for (hi, h) in enumerate(handoffs) {
                    sid = (h as dict)["session_id"] as str;
                    <div key={str(hi)} onClick={lambda (e: MouseEvent) { openDetail(sid); }} style={{
                        "background": "#0b1220", "border": "1px solid #1f2937", "borderRadius": "10px",
                        "padding": "0.8rem 1rem", "marginBottom": "0.6rem", "cursor": "pointer"
                    }}>
                        <div style={{"display": "flex", "alignItems": "center", "gap": "0.5rem", "marginBottom": "0.3rem"}}>
                            {badge((h as dict)["status"] as str)}
                            <span style={{"color": "#9ca3af", "fontSize": "0.8rem"}}>
                                {"shift " + ((h as dict).get("shift", "") as str) + " · " + ((h as dict).get("outgoing", "") as str) + " → " + ((h as dict).get("incoming", "") as str)}
                            </span>
                        </div>
                        <div style={{"fontSize": "0.92rem"}}>{(h as dict)["situation"] as str}</div>
                    </div>
                }}
            </div>
        }}
    </div>;
}
