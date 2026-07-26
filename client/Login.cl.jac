"""Login screen (PRD 5.1). Seeded demo users, no self-registration.

Mounts -> ensures the demo staff/residents exist (SeedDemo is idempotent), then
authenticates username+password against a User node (Login walker). On success
hands the caller the logged-in identity {id, username, name, role}; the app shell
holds it for the rest of the session. Quick-login chips make the demo one tap.
"""

sv import from handoff { Login, SeedDemo }


def:pub LoginView(onLogin: Callable[[dict], None]) -> JsxElement {
    has username: str = "";
    has password: str = "demo";
    has errorMsg: str = "";
    has busy: bool = False;

    # Make sure the demo graph is seeded before anyone tries to log in.
    async can with entry {
        try {
            root spawn SeedDemo();
        } except Exception as e {
            errorMsg = "Could not seed demo data: " + str(e);
        }
    }

    async def doLogin(uname: str, pw: str) -> None {
        errorMsg = "";
        busy = True;
        try {
            res = root spawn Login(username=uname, password=pw);
            info = res.reports[0];
            if info["ok"] {
                onLogin(info);
            } else {
                errorMsg = "Invalid username or password.";
            }
        } except Exception as err {
            errorMsg = "Login failed: " + str(err);
        }
        busy = False;
    }

    async def submit(e: MouseEvent) -> None {
        await doLogin(username, password);
    }

    def setU(e: any) -> None { username = e.target.value; }
    def setP(e: any) -> None { password = e.target.value; }

    # One-tap demo identities. All seeded with password "demo".
    quicks = [
        {"u": "mortiz", "name": "Maya Ortiz", "role": "RN"},
        {"u": "dpatel", "name": "Dev Patel", "role": "RN"},
        {"u": "jlee", "name": "Jordan Lee", "role": "LPN"},
        {"u": "acna", "name": "Alex Cruz", "role": "CNA"}
    ];

    return <div className="rem-app stack">
        <div className="card" style={{"width": "380px", "maxWidth": "100%"}}>
            <div style={{"display": "flex", "alignItems": "center", "gap": "0.6rem", "marginBottom": "0.2rem"}}>
                <span className="rem-brand" style={{"fontSize": "1.35rem"}}>REM</span>
            </div>
            <p className="muted" style={{"margin": "0.1rem 0 1.4rem 0", "fontSize": "0.9rem"}}>
                Shift handoff sign-in
            </p>

            <label className="label">Username</label>
            <input value={username} onChange={setU} placeholder="mortiz" className="input"
                style={{"marginBottom": "0.9rem"}}/>

            <label className="label">Password</label>
            <input value={password} onChange={setP} type="password" className="input"
                style={{"marginBottom": "1.2rem"}}/>

            <button onClick={submit} disabled={busy} className="btn btn-primary btn-block">
                {"Signing in…" if busy else "Sign in"}
            </button>

            {if errorMsg {
                <div className="alert alert-error" style={{"marginTop": "0.9rem"}}>{errorMsg}</div>
            }}

            <hr className="divider" style={{"margin": "1.4rem 0 1rem 0"}}/>
            <div className="muted" style={{"fontSize": "0.75rem", "marginBottom": "0.55rem"}}>
                Demo accounts · password <strong>demo</strong>
            </div>
            <div style={{"display": "flex", "flexWrap": "wrap", "gap": "0.4rem"}}>
                {for (i, q) in enumerate(quicks) {
                    <button key={str(i)} onClick={lambda (e: MouseEvent) { doLogin(q["u"] as str, "demo"); }}
                        className="chip">{(q["name"] as str) + " · " + (q["role"] as str)}</button>
                }}
            </div>
        </div>
    </div>;
}
