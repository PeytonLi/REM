"""Retrieval screen (PRD 5.6).

Pick a resident, see their handoffs newest-first, each flagged draft or signed so
an incoming nurse never mistakes an unsigned draft for a finalized handoff. Open
one to read the SBAR-plus summary and drill into the source transcript behind it
(the provenance). Drafts and signed summaries both appear; only the badge differs.
"""

import from .theme { speakerColor, initials }
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
            return <span className="badge badge-success">SIGNED</span>;
        }
        return <span className="badge badge-warn">DRAFT</span>;
    }

    return <div className="container">
        <div style={{"display": "flex", "alignItems": "center", "gap": "0.75rem"}}>
            <h1 className="h1">Past handoffs</h1>
            <button onClick={lambda (e: MouseEvent) { onNew(); }} className="btn btn-success btn-sm"
                style={{"marginLeft": "auto"}}>＋ New handoff</button>
        </div>

        {if errorMsg {
            <div className="alert alert-error" style={{"margin": "0.8rem 0"}}>{errorMsg}</div>
        }}

        <div style={{"display": "flex", "gap": "0.4rem", "flexWrap": "wrap", "margin": "1rem 0"}}>
            {for (ri, r) in enumerate(residents) {
                rid = (r as dict)["id"] as str;
                rname = (r as dict)["name"] as str;
                rroom = (r as dict)["room"] as str;
                <button key={str(ri)} onClick={lambda (e: MouseEvent) { pickResident(rid, rname, rroom); }}
                    className={"chip chip-active" if rid == selectedRid else "chip"}>{rname + " · " + rroom}</button>
            }}
        </div>

        {if selectedRid {
            <button onClick={lambda (e: MouseEvent) { onInspect({"id": selectedRid, "name": selectedName, "room": selectedRoom}); }}
                className="btn btn-primary" style={{"marginBottom": "0.6rem"}}>
                {"🧠 " + selectedName + "'s knowledge graph"}
            </button>
        }}

        {if loading {
            <p className="muted">Loading…</p>
        }}

        {if detail.get("ok", False) {
            <div className="card">
                <button onClick={closeDetail} className="btn btn-ghost btn-sm" style={{"marginBottom": "0.6rem", "paddingLeft": "0"}}>← back to list</button>
                {for (di, sm) in enumerate(detail["summaries"] as list) {
                    <div key={str(di)} style={{"marginBottom": "1rem"}}>
                        <div style={{"display": "flex", "alignItems": "center", "gap": "0.5rem", "marginBottom": "0.5rem"}}>
                            <strong>{(sm as dict).get("resident_name", "Resident") as str}</strong>
                            {badge((sm as dict)["status"] as str)}
                            {if ((sm as dict)["status"] as str) == "signed" {
                                <span className="muted-sm">{"signed by " + ((sm as dict)["signed_by"] as str)}</span>
                            }}
                        </div>
                        <p style={{"margin": "0.2rem 0"}}><span className="field">S </span>{(sm as dict)["situation"] as str}</p>
                        <p style={{"margin": "0.2rem 0"}}><span className="field">B </span>{(sm as dict)["background"] as str}</p>
                        <p style={{"margin": "0.2rem 0"}}><span className="field">A </span>{(sm as dict)["assessment"] as str}</p>
                        <p style={{"margin": "0.2rem 0"}}><span className="field">R </span>{(sm as dict)["recommendation"] as str}</p>
                    </div>
                }}
                <hr className="divider"/>
                <div className="field" style={{"marginBottom": "0.5rem"}}>Source transcript</div>
                <div className="feed">
                    {for (ti, s) in enumerate(detail["transcript"] as list) {
                        spk = (s as dict)["speaker"] as str;
                        <div key={str(ti)} className="msg">
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

        {if selectedRid and not detail.get("ok", False) and not loading {
            <div>
                {if len(handoffs) == 0 {
                    <div className="empty">{"No handoffs recorded for " + selectedName + " yet."}</div>
                }}
                {for (hi, h) in enumerate(handoffs) {
                    sid = (h as dict)["session_id"] as str;
                    <div key={str(hi)} onClick={lambda (e: MouseEvent) { openDetail(sid); }} className="chunk"
                        style={{"marginBottom": "0.6rem", "cursor": "pointer"}}>
                        <div style={{"display": "flex", "alignItems": "center", "gap": "0.5rem", "marginBottom": "0.3rem"}}>
                            {badge((h as dict)["status"] as str)}
                            <span className="muted-sm">
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
