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

    return <div style={{
        "minHeight": "100vh", "display": "flex", "alignItems": "center",
        "justifyContent": "center", "fontFamily": "system-ui, -apple-system, sans-serif"
    }}>
        <div style={{
            "width": "360px", "background": "#0b1220", "border": "1px solid #1f2937",
            "borderRadius": "14px", "padding": "1.75rem", "color": "#e5e7eb"
        }}>
            <h1 style={{"margin": "0 0 0.25rem 0", "fontSize": "1.5rem"}}>REM</h1>
            <p style={{"margin": "0 0 1.25rem 0", "color": "#9ca3af", "fontSize": "0.9rem"}}>
                Shift handoff sign-in
            </p>

            <label style={{"fontSize": "0.8rem", "color": "#9ca3af"}}>Username</label>
            <input value={username} onChange={setU} placeholder="mortiz" style={{
                "width": "100%", "boxSizing": "border-box", "margin": "0.25rem 0 0.9rem 0",
                "padding": "0.6rem 0.7rem", "background": "#111827", "color": "#e5e7eb",
                "border": "1px solid #374151", "borderRadius": "8px"
            }}/>

            <label style={{"fontSize": "0.8rem", "color": "#9ca3af"}}>Password</label>
            <input value={password} onChange={setP} type="password" style={{
                "width": "100%", "boxSizing": "border-box", "margin": "0.25rem 0 1.1rem 0",
                "padding": "0.6rem 0.7rem", "background": "#111827", "color": "#e5e7eb",
                "border": "1px solid #374151", "borderRadius": "8px"
            }}/>

            <button onClick={submit} disabled={busy} style={{
                "width": "100%", "padding": "0.65rem", "background": "#2563eb",
                "color": "white", "border": "none", "borderRadius": "8px",
                "cursor": "pointer", "fontWeight": "600", "opacity": "0.6" if busy else "1"
            }}>{"Signing in…" if busy else "Sign in"}</button>

            {if errorMsg {
                <div style={{
                    "background": "#7f1d1d", "color": "#fecaca", "padding": "0.5rem 0.7rem",
                    "borderRadius": "8px", "marginTop": "0.9rem", "fontSize": "0.85rem"
                }}>{errorMsg}</div>
            }}

            <div style={{"marginTop": "1.4rem", "borderTop": "1px solid #1f2937", "paddingTop": "1rem"}}>
                <div style={{"fontSize": "0.75rem", "color": "#6b7280", "marginBottom": "0.5rem"}}>
                    Demo accounts (password: demo)
                </div>
                <div style={{"display": "flex", "flexWrap": "wrap", "gap": "0.4rem"}}>
                    {for (i, q) in enumerate(quicks) {
                        <button key={str(i)} onClick={lambda (e: MouseEvent) { doLogin(q["u"] as str, "demo"); }} style={{
                            "padding": "0.35rem 0.6rem", "background": "#111827",
                            "color": "#93c5fd", "border": "1px solid #374151",
                            "borderRadius": "999px", "cursor": "pointer", "fontSize": "0.78rem"
                        }}>{(q["name"] as str) + " · " + (q["role"] as str)}</button>
                    }}
                </div>
            </div>
        </div>
    </div>;
}
