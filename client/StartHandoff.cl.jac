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

    return <div className="container" style={{"maxWidth": "620px"}}>
        <h1 className="h1">Start a handoff</h1>
        <p className="muted" style={{"marginTop": "0.35rem"}}>
            {"Outgoing: " + (user.get("name", "—") as str) + " · " + (user.get("role", "") as str)}
        </p>

        <div className="card" style={{"marginTop": "1rem"}}>
            <label className="label">Incoming nurse</label>
            <select value={incoming} onChange={onIncomingChange} className="select" style={{"marginBottom": "1.2rem"}}>
                <option value="">— select —</option>
                {for u in users {
                    if u["username"] != user.get("username", "") {
                        <option key={u["username"] as str} value={u["username"] as str}>
                            {(u["name"] as str) + " (" + (u["role"] as str) + ")"}
                        </option>
                    }
                }}
            </select>

            <label className="label">Residents to hand off</label>
            <div style={{"margin": "0 0 1.2rem 0", "display": "flex", "flexDirection": "column", "gap": "0.45rem"}}>
                {for r in residents {
                    rid = r["id"] as str;
                    on = rid in picked;
                    <div key={rid} onClick={lambda (e: MouseEvent) { toggle(rid); }}
                        className={"row row-active" if on else "row"}>
                        <span className={"check check-on" if on else "check"}>{"✓" if on else ""}</span>
                        <span>{(r["name"] as str) + " · Room " + (r["room"] as str)}</span>
                    </div>
                }}
            </div>

            <label className="label">Shift</label>
            <input value={shift} onChange={onShiftChange} className="input" style={{"marginBottom": "1.3rem"}}/>

            {if errorMsg {
                <div className="alert alert-error" style={{"marginBottom": "0.9rem"}}>{errorMsg}</div>
            }}

            <button onClick={begin} disabled={busy} className="btn btn-success btn-block">
                {"Starting…" if busy else "● Start recording"}
            </button>
        </div>
    </div>;
}
