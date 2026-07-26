"""REM client shell + screen router.

The whole "Live Handoff Capture, Summary & Retrieval" flow (PRD):

    login → start → record → (loading) → summary → retrieve

There is no react-router here -- a single `has screen` string drives which view
renders, and each view gets callbacks that advance the flow. All cross-screen
state (the logged-in user, the active session, the just-generated summaries and
transcript) lives here in the shell and is handed down as props; the views hold
only their own local UI state.
"""

import from .Login { LoginView }
import from .StartHandoff { StartHandoffView }
import from .RecordHandoff { RecordView }
import from .SummaryReview { SummaryView }
import from .Retrieve { RetrieveView }
import from .Patient { PatientView }


def:pub app() -> JsxElement {
    has screen: str = "login";        # login | start | record | summary | retrieve | patient
    has user: dict = {};              # {id, username, name, role}
    has session: dict = {};           # {id, shift, resident_ids, residents_label, incoming_name}
    has summaries: list = [];         # drafts from EndHandoff, for the summary screen
    has transcript: list = [];        # segments behind those summaries
    has patient: dict = {};           # {id, name, room} for the patient knowledge screen

    def onLogin(u: dict) -> None { user = u; screen = "start"; }
    def onLogout(e: MouseEvent) -> None { user = {}; session = {}; screen = "login"; }
    def onStarted(s: dict) -> None { session = s; screen = "record"; }
    def onEnded(summ: list, tsegs: list) -> None {
        summaries = summ; transcript = tsegs; screen = "summary";
    }
    def goStart(e: MouseEvent) -> None { session = {}; screen = "start"; }
    def goRetrieve() -> None { screen = "retrieve"; }
    def newHandoff() -> None { session = {}; screen = "start"; }
    def goPatient(r: dict) -> None { patient = r; screen = "patient"; }

    return <div style={{"background": "#111827", "minHeight": "100vh"}}>
        {if screen != "login" {
            <div style={{
                "display": "flex", "alignItems": "center", "gap": "1rem",
                "padding": "0.7rem 1.2rem", "borderBottom": "1px solid #1f2937",
                "background": "#0b1220", "color": "#e5e7eb",
                "fontFamily": "system-ui, -apple-system, sans-serif"
            }}>
                <strong style={{"letterSpacing": "0.05em"}}>REM</strong>
                <span style={{"color": "#9ca3af", "fontSize": "0.85rem"}}>
                    {(user.get("name", "") as str) + " · " + (user.get("role", "") as str)}
                </span>
                <span style={{"marginLeft": "auto", "display": "flex", "gap": "0.6rem"}}>
                    <button onClick={goStart} style={{
                        "background": "none", "border": "1px solid #374151", "color": "#93c5fd",
                        "padding": "0.35rem 0.7rem", "borderRadius": "8px", "cursor": "pointer", "fontSize": "0.82rem"
                    }}>New handoff</button>
                    <button onClick={lambda (e: MouseEvent) { goRetrieve(); }} style={{
                        "background": "none", "border": "1px solid #374151", "color": "#93c5fd",
                        "padding": "0.35rem 0.7rem", "borderRadius": "8px", "cursor": "pointer", "fontSize": "0.82rem"
                    }}>Past handoffs</button>
                    <button onClick={onLogout} style={{
                        "background": "none", "border": "1px solid #374151", "color": "#9ca3af",
                        "padding": "0.35rem 0.7rem", "borderRadius": "8px", "cursor": "pointer", "fontSize": "0.82rem"
                    }}>Sign out</button>
                </span>
            </div>
        }}

        {if screen == "login" {
            <LoginView onLogin={onLogin}/>
        }}
        {if screen == "start" {
            <StartHandoffView user={user} onStarted={onStarted}/>
        }}
        {if screen == "record" {
            <RecordView session={session} onEnded={onEnded}/>
        }}
        {if screen == "summary" {
            <SummaryView user={user} summaries={summaries} transcript={transcript} onDone={goRetrieve}/>
        }}
        {if screen == "retrieve" {
            <RetrieveView onNew={newHandoff} onInspect={goPatient}/>
        }}
        {if screen == "patient" {
            <PatientView resident={patient} onBack={goRetrieve}/>
        }}
    </div>;
}
