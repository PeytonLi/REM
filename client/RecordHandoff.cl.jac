"""Recording screen (PRD 5.3 + the two-pane mockup).

Recording starts on mount and stays live for the whole session: two speaker
panels fill in real time as the conversation happens (streaming diarization).
The same audio is buffered so that "End handoff" re-transcribes the whole
recording in batch (cleaner diarization, the hybrid path) before composing the
summary. Tapping End shows a loading state while transcription + summary run,
then the app swaps to the summary pane -- recording -> loading -> summary, no
third screen (PRD 7).

Callbacks handed to the transcription service are captured once at start and
would read stale `has` state, so finalized transcript lives in the service
module and here we only ever OVERWRITE `segments` from getSegments() (the
always-current source). Same discipline as the original LiveHandoff screen.
"""

import from .live_transcribe {
    startLive, stopLive, getSegments, clearSegments, getAudioB64, getAudioMime
}
import from .theme { speakerColor, initials, fmtClock }
sv import from handoff { EndHandoff }


def:pub RecordView(session: dict, onEnded: Callable[[list, list], None]) -> JsxElement {
    has status: str = "idle";       # idle | connecting | listening | stopped | processing
    has interim: str = "";
    has segments: list = [];
    has errorMsg: str = "";
    has tab: str = "transcript";    # transcript | summary

    def cbInterim(t: str) -> None { interim = t; }
    def cbStatus(s: str) -> None { status = s; }
    def cbError(m: str) -> None { errorMsg = m; }

    async def cbFinal(seg: dict) -> None {
        interim = "";
        segments = getSegments();
    }

    def beginLive() -> None {
        errorMsg = "";
        segments = [];
        interim = "";
        clearSegments();
        startLive({
            "onInterim": cbInterim, "onFinal": cbFinal,
            "onStatus": cbStatus, "onError": cbError
        });
    }

    # Recording is live for the whole session -- start it as the screen mounts.
    async can with entry {
        beginLive();
    }

    async def end(e: MouseEvent) -> None {
        stopLive();
        status = "processing";
        interim = "";
        try {
            b64 = await getAudioB64();
            segs = getSegments();
            res = root spawn EndHandoff(
                session_id=session["id"] as str,
                live_segments=segs,
                audio_b64=b64,
                mime=getAudioMime()
            );
            out = res.reports[0];
            if out["ok"] {
                onEnded(out["summaries"] as list, out["transcript"]["segments"] as list);
            } else {
                errorMsg = "Could not finish handoff: " + (out["error"] as str);
                status = "stopped";
            }
        } except Exception as err {
            errorMsg = "Could not finish handoff: " + str(err);
            status = "stopped";
        }
    }

    def pickTranscript(e: MouseEvent) -> None { tab = "transcript"; }
    def pickSummary(e: MouseEvent) -> None { tab = "summary"; }

    # --- loading state: transcription + summary running --------------------
    if status == "processing" {
        return <div className="rem-app" style={{
            "minHeight": "70vh", "display": "flex", "flexDirection": "column",
            "alignItems": "center", "justifyContent": "center"
        }}>
            <div className="spinner"></div>
            <p className="muted" style={{"marginTop": "1.2rem"}}>
                Transcribing the recording and composing the summary…
            </p>
        </div>;
    }

    listening = status == "listening" or status == "connecting";

    return <div className="container" style={{"maxWidth": "640px"}}>
        <div style={{"display": "flex", "alignItems": "center", "gap": "0.75rem", "marginBottom": "0.9rem"}}>
            <h1 className="h1">Live handoff</h1>
            {if listening {
                <span className="badge badge-warn" style={{"background": "var(--danger-soft)", "color": "var(--danger-ink)"}}>
                    <span className={"rec-dot" if status == "listening" else "rec-dot-idle"}></span>
                    {"Listening" if status == "listening" else "Connecting…"}
                </span>
            } else {
                <span className="badge badge-muted">Stopped</span>
            }}
        </div>
        <p className="muted-sm" style={{"margin": "0 0 1rem 0"}}>
            {(session.get("residents_label", "") as str) + " · to " + (session.get("incoming_name", "") as str) + " · " + (session.get("shift", "") as str)}
        </p>

        <div className="tabs" style={{"marginBottom": "1rem"}}>
            <button onClick={pickTranscript} className={"tab tab-active" if tab == "transcript" else "tab"}>Transcript</button>
            <button onClick={pickSummary} className={"tab tab-active" if tab == "summary" else "tab"}>Summary</button>
        </div>

        {if errorMsg {
            <div className="alert alert-error" style={{"marginBottom": "1rem"}}>{errorMsg}</div>
        }}

        {if tab == "summary" {
            <div className="empty">The SBAR summary is generated when you end the handoff.</div>
        }}

        {if tab == "transcript" {
            <div className="card" style={{"padding": "1.25rem"}}>
                {if len(segments) == 0 and not interim {
                    <div style={{"display": "flex", "flexDirection": "column", "alignItems": "center", "gap": "0.7rem", "padding": "1.6rem 1rem"}}>
                        <div className={"eq" if status == "listening" else "eq eq-idle"}>
                            <span></span><span></span><span></span><span></span><span></span><span></span><span></span>
                        </div>
                        <span className="muted-sm">Listening for the conversation…</span>
                    </div>
                }}

                <div className="feed">
                    {for (li, s) in enumerate(segments) {
                        spk = (s as dict)["speaker"] as str;
                        <div key={str(li)} className="msg">
                            <div className="msg-av" style={{"background": speakerColor(spk)}}>{initials(spk)}</div>
                            <div className="msg-main">
                                <div className="msg-head">
                                    <span className="msg-name">{spk}</span>
                                    <span className="msg-time">{fmtClock((s as dict)["start"] as float)}</span>
                                </div>
                                <div className="msg-body">{(s as dict)["text"] as str}</div>
                            </div>
                        </div>
                    }}
                    {if interim and status == "listening" {
                        <div className="msg msg-interim">
                            <div className="msg-av" style={{"background": "#c9cdd4"}}>…</div>
                            <div className="msg-main">
                                <div className="msg-head"><span className="msg-name muted">transcribing</span></div>
                                <div className="msg-body">{interim}</div>
                            </div>
                        </div>
                    }}
                </div>
            </div>
        }}

        <div className="dock">
            <div className="dock-side">
                <span className="dock-num">{str(len(segments))}</span>
                <span className="dock-lbl">lines</span>
            </div>
            <div style={{"display": "flex", "flexDirection": "column", "alignItems": "center", "gap": "0.5rem"}}>
                <button onClick={end} disabled={status == "processing"} className="rec-btn rec-btn-stop" title="End handoff">
                    <span className="rec-square"></span>
                </button>
                <span className="muted" style={{"fontSize": "0.72rem"}}>End &amp; summarise</span>
            </div>
            <div className="dock-side">
                <div className={"eq" if status == "listening" else "eq eq-idle"}>
                    <span></span><span></span><span></span><span></span><span></span><span></span><span></span>
                </div>
            </div>
        </div>
    </div>;
}
