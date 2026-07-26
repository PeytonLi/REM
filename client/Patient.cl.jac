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

    return <div className="container" style={{"maxWidth": "820px"}}>
        <button onClick={lambda (e: MouseEvent) { onBack(); }} className="btn btn-ghost btn-sm"
            style={{"paddingLeft": "0", "marginBottom": "0.4rem"}}>← back to past handoffs</button>

        <div style={{"display": "flex", "alignItems": "center", "gap": "0.75rem"}}>
            <h1 className="h1">{resident.get("name", "Resident") as str}</h1>
            <span className="muted">{"Room " + (resident.get("room", "") as str)}</span>
            <button onClick={rebuild} disabled={rebuilding or loading} className="btn btn-outline btn-sm"
                style={{"marginLeft": "auto"}}>{"Rebuilding…" if rebuilding else "↻ Rebuild knowledge"}</button>
        </div>

        {if errorMsg {
            <div className="alert alert-error" style={{"margin": "0.8rem 0"}}>{errorMsg}</div>
        }}

        {if loading {
            <p className="muted" style={{"marginTop": "1.5rem"}}>
                Distilling this resident's knowledge from their handoffs…
            </p>
        }}

        {if not loading {
            <div>
                <p className="muted" style={{"fontSize": "0.85rem", "margin": "0.6rem 0"}}>
                    {str(counts.get("beliefs", 0)) + " beliefs · " + str(counts.get("episodes", 0)) + " observations · tap a node to trace its provenance"}
                </p>

                {if len(gnodes) <= 1 {
                    <div className="empty">
                        No knowledge yet — record a handoff for this resident, then rebuild.
                    </div>
                } else {
                    <div key={"g" + str(graphVer)} style={{"borderRadius": "16px", "overflow": "hidden", "boxShadow": "var(--shadow)"}}>
                        <GraphPanel nodes={gnodes} links={glinks} highlightIds={highlight} onNodeClick={onNode} height={440}/>
                    </div>
                }}

                {if len(beliefs) > 0 {
                    <div style={{"marginTop": "1.2rem"}}>
                        <div className="field" style={{"marginBottom": "0.5rem"}}>Beliefs</div>
                        {for (bi, b) in enumerate(beliefs) {
                            bid = (b as dict)["id"] as str;
                            <div key={str(bi)} onClick={lambda (e: MouseEvent) { onNode(bid); }}
                                className={"row row-active" if bid in highlight else "row"}
                                style={{"marginBottom": "0.4rem"}}>{(b as dict)["label"] as str}</div>
                        }}
                    </div>
                }}

                <div style={{"marginTop": "1.4rem"}}>
                    <div className="field" style={{"marginBottom": "0.5rem"}}>Handoff history</div>
                    {if len(handoffs) == 0 {
                        <p className="muted" style={{"margin": "0"}}>No handoffs recorded yet.</p>
                    }}
                    {for (hi, h) in enumerate(handoffs) {
                        <div key={str(hi)} className="chunk" style={{"marginBottom": "0.4rem"}}>
                            <div style={{"display": "flex", "gap": "0.5rem", "alignItems": "center", "marginBottom": "0.2rem"}}>
                                <span className={"badge badge-success" if ((h as dict)["status"] as str) == "signed" else "badge badge-warn"}>
                                    {((h as dict)["status"] as str).upper()}
                                </span>
                                <span className="muted-sm">{"shift " + ((h as dict).get("shift", "") as str)}</span>
                            </div>
                            <div style={{"fontSize": "0.9rem"}}>{(h as dict)["situation"] as str}</div>
                        </div>
                    }}
                </div>
            </div>
        }}
    </div>;
}
