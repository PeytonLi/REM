"""REM client shell.

Renders the Live Handoff screen (PRD §9, live-mic branch): real-time
microphone transcription that writes each finalized utterance to the belief
graph, then runs the post-hoc omission check. The graph viz / device dashboard
screens plug in alongside this as they are built out.
"""

import from .LiveHandoff { LiveHandoff }

def:pub app() -> JsxElement {
    return <div style={{"background": "#111827", "minHeight": "100vh"}}>
        <LiveHandoff/>
    </div>;
}
