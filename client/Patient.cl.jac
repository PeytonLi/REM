"""Patient knowledge screen.

Each resident has their own belief graph, distilled from their handoff
transcripts (ResidentGraph walker, LLM extraction). This screen renders it with
the reusable GraphPanel: click a belief to light up the episodes it was derived
from -- the provenance click-through. Below the graph, the belief list and the
resident's handoff timeline. "Rebuild" re-extracts from scratch.

The graph is built lazily on first view, so the initial load can take a moment
(one LLM call) -- a loading state covers it. GraphPanel lays out once on mount,
so a changing `key` remounts it whenever the data is (re)built.
"""

import from .GraphPanel { GraphPanel }
sv import from handoff { ResidentGraph, ListHandoffs }


def:pub PatientView(resident: dict, onBack: Callable[[], None]) -> JsxElement {
    has gnodes: list = [];
    has glinks: list = [];
    has counts: dict = {};
    has highlight: list = [];
    has handoffs: list = [];
    has loading: bool = True;
    has rebuilding: bool = False;
    has errorMsg: str = "";
    has graphVer: int = 0;

    async def load(rebuild: bool) -> None {
        errorMsg = "";
        try {
            res = root spawn ResidentGraph(
                resident_id=resident["id"] as str, rebuild=rebuild
            );
            g = res.reports[0];
            if g["ok"] {
                gnodes = g["nodes"] as list;
                glinks = g["links"] as list;
                counts = g["counts"] as dict;
                highlight = [];
                graphVer = graphVer + 1;
            } else {
                errorMsg = g["error"] as str;
            }
        } except Exception as e {
            errorMsg = "Could not load knowledge graph: " + str(e);
        }
    }

    async can with entry {
        await load(False);
        try {
            hres = root spawn ListHandoffs(resident_id=resident["id"] as str);
            handoffs = hres.reports[0]["handoffs"] as list;
        } except Exception as e {
            errorMsg = "Could not load handoffs: " + str(e);
        }
        loading = False;
    }

    async def rebuild(e: MouseEvent) -> None {
        rebuilding = True;
        await load(True);
        rebuilding = False;
    }

    # Click a node -> highlight it plus everything one edge away (its provenance).
    def onNode(nid: str) -> None {
        hot = [nid];
        for l in glinks {
            ld = l as dict;
            if (ld["source"] as str) == nid {
                hot = hot + [ld["target"] as str];
            }
            if (ld["target"] as str) == nid {
                hot = hot + [ld["source"] as str];
            }
        }
        highlight = hot;
    }

    beliefs = [n for n in gnodes if (n as dict)["kind"] == "Clinical"];

    return <div style={{
        "maxWidth": "820px", "margin": "1.5rem auto", "padding": "0 1rem",
        "fontFamily": "system-ui, -apple-system, sans-serif", "color": "#e5e7eb"
    }}>
        <button onClick={lambda (e: MouseEvent) { onBack(); }} style={{
            "background": "none", "border": "none", "color": "#93c5fd", "cursor": "pointer",
            "padding": "0", "marginBottom": "0.6rem"
        }}>← back to past handoffs</button>

        <div style={{"display": "flex", "alignItems": "center", "gap": "0.75rem"}}>
            <h1 style={{"margin": "0"}}>{resident.get("name", "Resident") as str}</h1>
            <span style={{"color": "#9ca3af"}}>{"Room " + (resident.get("room", "") as str)}</span>
            <button onClick={rebuild} disabled={rebuilding or loading} style={{
                "marginLeft": "auto", "padding": "0.4rem 0.8rem", "background": "none",
                "color": "#93c5fd", "border": "1px solid #374151", "borderRadius": "8px",
                "cursor": "pointer", "fontSize": "0.82rem"
            }}>{"Rebuilding…" if rebuilding else "↻ Rebuild knowledge"}</button>
        </div>

        {if errorMsg {
            <div style={{"background": "#7f1d1d", "color": "#fecaca", "padding": "0.5rem 0.8rem", "borderRadius": "8px", "margin": "0.8rem 0", "fontSize": "0.85rem"}}>{errorMsg}</div>
        }}

        {if loading {
            <p style={{"color": "#9ca3af", "marginTop": "1.5rem"}}>
                Distilling this resident's knowledge from their handoffs…
            </p>
        }}

        {if not loading {
            <div>
                <p style={{"color": "#9ca3af", "fontSize": "0.85rem", "margin": "0.6rem 0"}}>
                    {str(counts.get("beliefs", 0)) + " beliefs · " + str(counts.get("episodes", 0)) + " observations · tap a node to trace its provenance"}
                </p>

                {if len(gnodes) <= 1 {
                    <div style={{"background": "#0b1220", "border": "1px solid #1f2937", "borderRadius": "12px", "padding": "1.5rem", "textAlign": "center", "color": "#6b7280"}}>
                        No knowledge yet — record a handoff for this resident, then rebuild.
                    </div>
                } else {
                    <div key={"g" + str(graphVer)}>
                        <GraphPanel nodes={gnodes} links={glinks} highlightIds={highlight} onNodeClick={onNode} height={440}/>
                    </div>
                }}

                # -- belief list (with provenance count), the text form of the graph
                {if len(beliefs) > 0 {
                    <div style={{"marginTop": "1.2rem"}}>
                        <div style={{"fontSize": "0.8rem", "color": "#93c5fd", "fontWeight": "600", "marginBottom": "0.5rem"}}>Beliefs</div>
                        {for (bi, b) in enumerate(beliefs) {
                            bid = (b as dict)["id"] as str;
                            <div key={str(bi)} onClick={lambda (e: MouseEvent) { onNode(bid); }} style={{
                                "background": "#132038" if bid in highlight else "#0b1220",
                                "border": "1px solid #2563eb" if bid in highlight else "1px solid #1f2937",
                                "borderRadius": "8px", "padding": "0.55rem 0.8rem", "marginBottom": "0.4rem",
                                "cursor": "pointer"
                            }}>{(b as dict)["label"] as str}</div>
                        }}
                    </div>
                }}

                # -- handoff timeline
                <div style={{"marginTop": "1.4rem"}}>
                    <div style={{"fontSize": "0.8rem", "color": "#93c5fd", "fontWeight": "600", "marginBottom": "0.5rem"}}>Handoff history</div>
                    {if len(handoffs) == 0 {
                        <p style={{"color": "#6b7280", "margin": "0"}}>No handoffs recorded yet.</p>
                    }}
                    {for (hi, h) in enumerate(handoffs) {
                        <div key={str(hi)} style={{"background": "#0b1220", "border": "1px solid #1f2937", "borderRadius": "8px", "padding": "0.6rem 0.8rem", "marginBottom": "0.4rem"}}>
                            <div style={{"display": "flex", "gap": "0.5rem", "alignItems": "center", "marginBottom": "0.2rem"}}>
                                <span style={{
                                    "padding": "0.12rem 0.5rem", "borderRadius": "999px", "fontSize": "0.7rem", "fontWeight": "700",
                                    "background": "#064e3b" if ((h as dict)["status"] as str) == "signed" else "#78350f",
                                    "color": "#a7f3d0" if ((h as dict)["status"] as str) == "signed" else "#fcd34d"
                                }}>{((h as dict)["status"] as str).upper()}</span>
                                <span style={{"color": "#9ca3af", "fontSize": "0.78rem"}}>{"shift " + ((h as dict).get("shift", "") as str)}</span>
                            </div>
                            <div style={{"fontSize": "0.9rem"}}>{(h as dict)["situation"] as str}</div>
                        </div>
                    }}
                </div>
            </div>
        }}
    </div>;
}
