"""Reusable provenance graph panel.

Force-directed layout via d3-force (the npm graph lib confirmed in the hour-0
spike, PRD 10.2/13). Renders Episode/Clinical stub nodes as an SVG graph.
Click a node to select it; pass `highlightIds` from outside (e.g. a clicked
SBAR-plus line) to light up its source episodes -- this is the provenance
click-through that is screen 2's "five-second wow" (PRD 13, 1:45-2:05).

Nodes/links are plain `dict` (not typed nodes) on purpose: d3-force bolts
`x`/`y`/`vx`/`vy`/`index` onto each node object at layout time, and a plain
JS-object-shaped dict absorbs that with no schema friction.
"""

import from "d3-force" { forceSimulation, forceManyBody, forceLink, forceCenter, forceCollide }

glob _WIDTH: float = 560.0;
glob _HEIGHT: float = 420.0;

def _node_id(d: dict) -> str {
    return d["id"] as str;
}

def _clamp(v: float, lo: float, hi: float) -> float {
    return max(lo, min(hi, v));
}

"""Run the force simulation to convergence synchronously -- no live timer;
a static pre-computed layout is all a click-to-highlight demo needs."""
def layout_graph(nodes: list[dict], links: list[dict]) -> dict {
    sim = (forceSimulation(nodes)
        .force("charge", forceManyBody().strength(-170))
        .force("link", forceLink(links).id(_node_id).distance(75))
        .force("center", forceCenter(_WIDTH / 2.0, _HEIGHT / 2.0))
        .force("collide", forceCollide(24))
        .stop());

    i = 0;
    while i < 300 {
        sim.tick();
        i = i + 1;
    }
    return {"nodes": nodes, "links": links};
}

def:pub GraphPanel(
    nodes: list[dict],
    links: list[dict],
    highlightIds: list[str] = [],
    onNodeClick: Callable[[str], None] | None = None,
    height: int = 420
) -> JsxElement {
    has laidNodes: list[dict] = [];
    has laidLinks: list[dict] = [];

    async can with entry {
        result = layout_graph([{**n} for n in nodes], [{**l} for l in links]);
        laidNodes = result["nodes"] as list[dict];
        laidLinks = result["links"] as list[dict];
    }

    def handle_click(nodeId: str) {
        if onNodeClick {
            onNodeClick(nodeId);
        }
    }

    def is_hot(nodeId: str) -> bool {
        return nodeId in highlightIds;
    }

    def node_fill(kind: str, hot: bool) -> str {
        if hot {
            return "#f97316";
        }
        return "#60a5fa" if kind == "Clinical" else "#9ca3af";
    }

    def node_radius(kind: str, hot: bool) -> float {
        base = 12.0 if kind == "Clinical" else 8.0;
        return base + 4.0 if hot else base;
    }

    return <div
        className="graph-panel"
        style={{
            "width": "100%",
            "height": f"{height}px",
            "position": "relative",
            "background": "#0b1020",
            "borderRadius": "12px",
            "overflow": "hidden"
        }}
    >
        {if len(laidNodes) == 0 {
            <p style={{"color": "#9ca3af", "padding": "1rem", "margin": "0"}}>Laying out graph...</p>
            skip;
        }}
        <svg width="100%" height={height} viewBox={f"0 0 {_WIDTH} {_HEIGHT}"}>
            {for l in laidLinks {
                src = l["source"] as dict;
                tgt = l["target"] as dict;
                sx = _clamp((src["x"] as float), 20.0, _WIDTH - 20.0);
                sy = _clamp((src["y"] as float), 20.0, _HEIGHT - 20.0);
                tx = _clamp((tgt["x"] as float), 20.0, _WIDTH - 20.0);
                ty = _clamp((tgt["y"] as float), 20.0, _HEIGHT - 20.0);
                lit = is_hot(src["id"] as str) or is_hot(tgt["id"] as str);
                <line
                    key={(src["id"] as str) + "-" + (tgt["id"] as str)}
                    x1={sx} y1={sy} x2={tx} y2={ty}
                    stroke={"#f97316" if lit else "#374151"}
                    strokeWidth={2 if lit else 1}
                />
            }}
            {for n in laidNodes {
                nid = n["id"] as str;
                kind = n["kind"] as str;
                hot = is_hot(nid);
                cx = _clamp((n["x"] as float), 20.0, _WIDTH - 20.0);
                cy = _clamp((n["y"] as float), 20.0, _HEIGHT - 20.0);
                <g key={nid} onClick={lambda (e: MouseEvent) { handle_click(nid); }} style={{"cursor": "pointer"}}>
                    <circle
                        cx={cx} cy={cy} r={node_radius(kind, hot)}
                        fill={node_fill(kind, hot)}
                        stroke={"#fff" if hot else "none"}
                        strokeWidth={2}
                    />
                    <text x={cx + 14.0} y={cy + 4.0} fill="#e5e7eb" fontSize="10">
                        {n["label"] as str}
                    </text>
                </g>
            }}
        </svg>
    </div>;
}
