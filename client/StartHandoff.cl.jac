"""Start-handoff screen (PRD 5.2).

The outgoing nurse is whoever is logged in. They pick the incoming nurse from the
active roster and one or more residents to hand off, then open the session
(StartHandoff walker). On success the app moves to the recording screen. One
session can cover several residents (PRD 7) -- a whole hall in one recording.
"""

sv import from handoff { Roster, StartHandoff }


def:pub StartHandoffView(user: dict, onStarted: Callable[[dict], None]) -> JsxElement {
    has users: list = [];
    has residents: list = [];
    has incoming: str = "";
    has picked: list = [];             # selected resident ids
    has shift: str = "D5-night";
    has errorMsg: str = "";
    has busy: bool = False;

    async can with entry {
        try {
            res = root spawn Roster();
            data = res.reports[0];
            users = data["users"] as list;
            residents = data["residents"] as list;
            # default the incoming nurse to the first colleague that isn't me
            for u in users {
                if u["username"] != user.get("username", "") {
                    incoming = u["username"] as str;
                    break;
                }
            }
        } except Exception as e {
            errorMsg = "Could not load roster: " + str(e);
        }
    }

    def onIncomingChange(e: any) -> None { incoming = e.target.value; }
    def onShiftChange(e: any) -> None { shift = e.target.value; }

    def toggle(rid: str) -> None {
        if rid in picked {
            picked = [x for x in picked if x != rid];
        } else {
            picked = picked + [rid];
        }
    }

    async def begin(e: MouseEvent) -> None {
        errorMsg = "";
        if not incoming {
            errorMsg = "Choose the incoming nurse.";
            return;
        }
        if len(picked) == 0 {
            errorMsg = "Choose at least one resident.";
            return;
        }
        busy = True;
        try {
            res = root spawn StartHandoff(
                outgoing_username=user.get("username", "") as str,
                incoming_username=incoming,
                resident_ids=picked,
                shift=shift
            );
            info = res.reports[0];
            # resident + nurse labels for the recording/summary headers
            rlabels = [];
            for r in residents {
                if (r["id"] as str) in picked {
                    rlabels.append(r["name"] as str);
                }
            }
            iname = "";
            for u in users {
                if u["username"] == incoming { iname = u["name"] as str; }
            }
            onStarted({
                "id": info["id"], "shift": shift, "resident_ids": picked,
                "residents_label": ", ".join(rlabels), "incoming_name": iname
            });
        } except Exception as err {
            errorMsg = "Could not start handoff: " + str(err);
            busy = False;
        }
    }

    return <div style={{
        "maxWidth": "620px", "margin": "2rem auto", "padding": "0 1rem",
        "fontFamily": "system-ui, -apple-system, sans-serif", "color": "#e5e7eb"
    }}>
        <h1 style={{"margin": "0 0 0.25rem 0"}}>Start a handoff</h1>
        <p style={{"color": "#9ca3af", "marginTop": "0"}}>
            {"Outgoing: " + (user.get("name", "—") as str) + " · " + (user.get("role", "") as str)}
        </p>

        <div style={{
            "background": "#0b1220", "border": "1px solid #1f2937", "borderRadius": "12px",
            "padding": "1.25rem", "marginTop": "1rem"
        }}>
            <label style={{"fontSize": "0.85rem", "color": "#9ca3af"}}>Incoming nurse</label>
            <select value={incoming} onChange={onIncomingChange} style={{
                "width": "100%", "boxSizing": "border-box", "margin": "0.3rem 0 1.1rem 0",
                "padding": "0.55rem", "background": "#111827", "color": "#e5e7eb",
                "border": "1px solid #374151", "borderRadius": "8px"
            }}>
                <option value="">— select —</option>
                {for u in users {
                    if u["username"] != user.get("username", "") {
                        <option key={u["username"] as str} value={u["username"] as str}>
                            {(u["name"] as str) + " (" + (u["role"] as str) + ")"}
                        </option>
                    }
                }}
            </select>

            <label style={{"fontSize": "0.85rem", "color": "#9ca3af"}}>Residents to hand off</label>
            <div style={{"margin": "0.4rem 0 1.1rem 0", "display": "flex", "flexDirection": "column", "gap": "0.4rem"}}>
                {for r in residents {
                    rid = r["id"] as str;
                    on = rid in picked;
                    <div key={rid} onClick={lambda (e: MouseEvent) { toggle(rid); }} style={{
                        "display": "flex", "alignItems": "center", "gap": "0.6rem",
                        "padding": "0.55rem 0.7rem", "cursor": "pointer", "borderRadius": "8px",
                        "border": "1px solid #2563eb" if on else "1px solid #374151",
                        "background": "#132038" if on else "#111827"
                    }}>
                        <span style={{
                            "width": "16px", "height": "16px", "borderRadius": "4px",
                            "border": "1px solid #6b7280", "display": "inline-flex",
                            "alignItems": "center", "justifyContent": "center",
                            "background": "#2563eb" if on else "transparent", "fontSize": "0.7rem"
                        }}>{"✓" if on else ""}</span>
                        <span>{(r["name"] as str) + " · Room " + (r["room"] as str)}</span>
                    </div>
                }}
            </div>

            <label style={{"fontSize": "0.85rem", "color": "#9ca3af"}}>Shift</label>
            <input value={shift} onChange={onShiftChange} style={{
                "width": "100%", "boxSizing": "border-box", "margin": "0.3rem 0 1.2rem 0",
                "padding": "0.55rem", "background": "#111827", "color": "#e5e7eb",
                "border": "1px solid #374151", "borderRadius": "8px"
            }}/>

            {if errorMsg {
                <div style={{
                    "background": "#7f1d1d", "color": "#fecaca", "padding": "0.5rem 0.7rem",
                    "borderRadius": "8px", "marginBottom": "0.9rem", "fontSize": "0.85rem"
                }}>{errorMsg}</div>
            }}

            <button onClick={begin} disabled={busy} style={{
                "width": "100%", "padding": "0.7rem", "background": "#16a34a",
                "color": "white", "border": "none", "borderRadius": "8px",
                "cursor": "pointer", "fontWeight": "600", "opacity": "0.6" if busy else "1"
            }}>{"Starting…" if busy else "● Start recording"}</button>
        </div>
    </div>;
}
