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
import from .theme { remCss }


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

    return <div className="rem-app">
        <style>{remCss()}</style>
        {if screen != "login" {
            <div className="rem-header">
                <span className="rem-brand">REM</span>
                <span className="muted-sm">
                    {(user.get("name", "") as str) + " · " + (user.get("role", "") as str)}
                </span>
                <span style={{"marginLeft": "auto", "display": "flex", "gap": "0.5rem"}}>
                    <button onClick={goStart} className="btn btn-ghost btn-sm">New handoff</button>
                    <button onClick={lambda (e: MouseEvent) { goRetrieve(); }} className="btn btn-ghost btn-sm">Past handoffs</button>
                    <button onClick={onLogout} className="btn btn-outline btn-sm">Sign out</button>
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
