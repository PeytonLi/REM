"""REM client shell -- SPIKE STAGE.

Hour-0 de-risking spike (PRD 10.2 / handoff-B B4): render ONE graph node
through GraphPanel and confirm the app boots end to end before the five
screens are built out. Replaced by the real tabbed shell once the spike is
confirmed -- see the follow-up edit to this file.
"""

import from .GraphPanel { GraphPanel }

def:pub app() -> JsxElement {
    return <div style={{"padding": "2rem", "fontFamily": "system-ui, sans-serif", "background": "#111827", "minHeight": "100vh", "color": "#e5e7eb"}}>
        <h1>REM -- spike</h1>
        <p>One node, one force-directed graph lib, loaded via jac.toml [dependencies.npm].</p>
        <GraphPanel
            nodes={[{"id": "E1", "kind": "Episode", "label": "hello world episode"}]}
            links={[]}
            height={240}
        />
    </div>;
}
