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
sv import from handoff { EndHandoff }


def:pub RecordView(session: dict, onEnded: Callable[[list, list], None]) -> JsxElement {
    has status: str = "idle";       # idle | connecting | listening | stopped | processing
    has interim: str = "";
    has segments: list = [];
    has errorMsg: str = "";

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

    def linesFor(label: str) -> list {
        return [s for s in segments if (s as dict)["speaker"] == label];
    }

    # --- loading state: transcription + summary running --------------------
    if status == "processing" {
        return <div style={{
            "minHeight": "100vh", "display": "flex", "flexDirection": "column",
            "alignItems": "center", "justifyContent": "center", "color": "#e5e7eb",
            "fontFamily": "system-ui, -apple-system, sans-serif"
        }}>
            <div style={{
                "width": "44px", "height": "44px", "border": "4px solid #1f2937",
                "borderTopColor": "#2563eb", "borderRadius": "50%",
                "animation": "spin 1s linear infinite"
            }}></div>
            <p style={{"marginTop": "1.2rem", "color": "#9ca3af"}}>
                Transcribing the recording and composing the summary…
            </p>
            <style>{"@keyframes spin { to { transform: rotate(360deg); } }"}</style>
        </div>;
    }

    listening = status == "listening" or status == "connecting";

    return <div style={{
        "maxWidth": "620px", "margin": "1.5rem auto", "padding": "0 1rem",
        "fontFamily": "system-ui, -apple-system, sans-serif", "color": "#e5e7eb"
    }}>
        <div style={{
            "border": "1px solid #374151", "borderRadius": "18px", "padding": "1.5rem",
            "background": "#0b1220"
        }}>
            # -- header: title, paired-nurse avatar, resident label
            <div style={{"display": "flex", "alignItems": "center", "justifyContent": "space-between"}}>
                <h1 style={{"margin": "0", "fontSize": "1.4rem"}}>Handoff</h1>
                <span style={{"color": "#9ca3af"}}>{session.get("residents_label", "") as str}</span>
            </div>
            <div style={{"display": "flex", "alignItems": "center", "gap": "0.6rem", "margin": "0.9rem 0"}}>
                <div style={{"display": "flex"}}>
                    <span style={{"width": "34px", "height": "34px", "borderRadius": "50%", "border": "2px solid #6b7280", "background": "#111827"}}></span>
                    <span style={{"width": "34px", "height": "34px", "borderRadius": "50%", "border": "2px solid #6b7280", "background": "#111827", "marginLeft": "-12px"}}></span>
                </div>
                <span style={{"color": "#9ca3af", "fontSize": "0.85rem"}}>
                    {(session.get("incoming_name", "") as str) + " · " + (session.get("shift", "") as str)}
                </span>
                <span style={{
                    "marginLeft": "auto", "display": "inline-flex", "alignItems": "center",
                    "gap": "0.4rem", "color": "#9ca3af", "fontSize": "0.85rem"
                }}>
                    <span style={{
                        "width": "9px", "height": "9px", "borderRadius": "50%",
                        "background": "#ef4444" if status == "listening" else "#6b7280"
                    }}></span>
                    {status}
                </span>
            </div>
            <div style={{"borderTop": "1px solid #1f2937", "margin": "0 0 1rem 0"}}></div>

            {if errorMsg {
                <div style={{
                    "background": "#7f1d1d", "color": "#fecaca", "padding": "0.55rem 0.8rem",
                    "borderRadius": "8px", "marginBottom": "1rem", "fontSize": "0.85rem"
                }}>{errorMsg}</div>
            }}

            # -- two speaker panels, filling live
            {for (pi, label) in enumerate(["Speaker 1", "Speaker 2"]) {
                <div key={str(pi)} style={{"marginBottom": "1.1rem"}}>
                    <div style={{"display": "flex", "alignItems": "center", "gap": "0.6rem", "marginBottom": "0.4rem"}}>
                        <span style={{"width": "26px", "height": "26px", "borderRadius": "50%", "border": "2px solid #6b7280"}}></span>
                        <span style={{"fontWeight": "600"}}>{label}</span>
                    </div>
                    <div style={{
                        "minHeight": "84px", "border": "1px solid #374151", "borderRadius": "12px",
                        "padding": "0.7rem 0.9rem", "background": "#111827", "lineHeight": "1.5"
                    }}>
                        {for (li, s) in enumerate(linesFor(label)) {
                            <span key={str(li)}>{((s as dict)["text"] as str) + " "}</span>
                        }}
                        {if interim and status == "listening" and label == "Speaker 1" {
                            <span style={{"color": "#6b7280", "fontStyle": "italic"}}>{interim + " …"}</span>
                        }}
                    </div>
                </div>
            }}

            # -- end control
            <button onClick={end} disabled={status == "processing"} style={{
                "width": "100%", "padding": "0.75rem", "background": "#dc2626",
                "color": "white", "border": "none", "borderRadius": "10px",
                "cursor": "pointer", "fontWeight": "700", "marginTop": "0.4rem"
            }}>■ End handoff</button>
            <p style={{"color": "#6b7280", "fontSize": "0.8rem", "textAlign": "center", "marginBottom": "0"}}>
                {str(len(segments)) + " lines captured"}
            </p>
        </div>
    </div>;
}
