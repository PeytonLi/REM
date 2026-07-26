"""Nurse homescreen -- the landing screen after login.

Ties the app together: a greeting + shift context, a hard-capped "needs
attention" strip, the primary "Start handoff" action, and every facility
resident sorted by concern (there is no roster/assignment model in the MVP, so
all residents show). Concern status is DERIVED from real handoff state via the
HomeFeed walker; on a fresh demo graph (no handoffs yet) a small placeholder
overlay keeps the screen legible. Tapping a resident opens their handoff
history (PatientView). Deliberately NOT a live-vitals monitor -- one line of
status per row, nothing more (feature spec, alarm-fatigue + non-goal).
"""

sv import from handoff { HomeFeed }
import from .theme { initials }


def:pub HomeView(
    user: dict,
    onStartHandoff: Callable[[], None],
    onOpenResident: Callable[[dict], None],
    onRetrieve: Callable[[], None],
    onSignOut: Callable[[], None]
) -> JsxElement {
    has residents: list = [];
    has loading: bool = True;
    has errorMsg: str = "";
    has query: str = "";
    has showAllAttn: bool = False;

    async can with entry {
        try {
            res = root spawn HomeFeed();
            residents = res.reports[0]["residents"] as list;
        } except Exception as e {
            errorMsg = "Could not load homescreen: " + str(e);
        }
        loading = False;
    }

    def onQuery(e: any) -> None { query = e.target.value; }
    def toggleAttn(e: MouseEvent) -> None { showAllAttn = not showAllAttn; }

    # Real handoff state always wins; the `demo` reasons only fill in when the
    # facility has no handoff history at all, so the landing screen still reads.
    def deriveStatus(r: dict, i: int, demo: bool) -> dict {
        if r["open"] as bool {
            return {"kind": "concern", "bucket": 0, "reason": "Handoff in progress", "hot": True};
        }
        if r["has_draft"] as bool {
            return {"kind": "watch", "bucket": 1, "reason": "Draft handoff — not signed", "hot": False};
        }
        if demo and i == 0 {
            return {"kind": "concern", "bucket": 0, "reason": "Fall flagged overnight · unresolved", "hot": True};
        }
        if demo and i == 1 {
            return {"kind": "watch", "bucket": 1, "reason": "Desat pattern · watching", "hot": False};
        }
        if (r["last_at"] as float) > 0.0 {
            return {"kind": "stable", "bucket": 2, "reason": "Stable · handoff on file", "hot": False};
        }
        return {"kind": "stable", "bucket": 2, "reason": "No handoffs yet", "hot": False};
    }

    def dotClass(kind: str) -> str {
        if kind == "concern" { return "dot dot-concern"; }
        if kind == "watch" { return "dot dot-watch"; }
        return "dot dot-stable";
    }

    fullName = user.get("name", "") as str;
    parts = [p for p in fullName.split(" ") if p];
    firstName = (parts[0] as str) if len(parts) > 0 else "there";

    demo = True;
    for r in residents {
        rd = r as dict;
        if (rd["open"] as bool) or (rd["has_draft"] as bool) or ((rd["last_at"] as float) > 0.0) {
            demo = False;
        }
    }

    enriched: list[dict] = [];
    for (i, r) in enumerate(residents) {
        rd = r as dict;
        d = deriveStatus(rd, i, demo);
        enriched.append({
            "id": rd["id"], "name": rd["name"], "room": rd["room"],
            "kind": d["kind"], "bucket": d["bucket"], "reason": d["reason"], "hot": d["hot"]
        });
    }

    attnConcern = [e for e in enriched if (e["kind"] as str) == "concern"];
    attnWatch = [e for e in enriched if (e["kind"] as str) == "watch"];
    attention = attnConcern + attnWatch;
    attnShown = attention if showAllAttn else attention[0:3];

    q = query.strip().lower();
    filtered = enriched;
    if q {
        filtered = [e for e in enriched
            if (q in (e["name"] as str).lower()) or (q in (e["room"] as str).lower())];
    }
    b0 = [e for e in filtered if (e["bucket"] as int) == 0];
    b1 = [e for e in filtered if (e["bucket"] as int) == 1];
    b2 = [e for e in filtered if (e["bucket"] as int) == 2];
    ordered = b0 + b1 + b2;

    return <div className="home">
        <div className="home-head">
            <div style={{"flex": "1 1 auto", "minWidth": "0"}}>
                <h1 className="home-greet">{"Good evening, " + firstName}</h1>
                <p className="home-sub">Night shift · Hall B · 19:00–07:00</p>
            </div>
            <button className="avatar" title="Sign out"
                onClick={lambda (e: MouseEvent) { onSignOut(); }}>{initials(fullName)}</button>
        </div>

        {if errorMsg {
            <div className="alert alert-error">{errorMsg}</div>
        }}

        {if loading {
            <div className="attn attn-empty"><div className="attn-head">Loading…</div></div>
        }}

        {if not loading {
            <div className={"attn attn-empty" if len(attention) == 0 else "attn"}>
                <div className="attn-head">
                    <span>Needs attention</span>
                    {if len(attention) > 0 {
                        <span className="attn-count">{str(len(attention))}</span>
                    }}
                </div>
                {if len(attention) == 0 {
                    <div className="muted-sm">All residents stable — nothing flagged.</div>
                }}
                {for (ai, a) in enumerate(attnShown) {
                    <div key={str(ai)} className="attn-item">
                        <span className={"attn-room attn-tier1" if (a["hot"] as bool) else "attn-room"}>
                            {"Rm " + (a["room"] as str)}
                        </span>
                        <span>{a["reason"] as str}</span>
                    </div>
                }}
                {if len(attention) > 3 {
                    <button className="attn-more" onClick={toggleAttn}>
                        {("Show top 3" if showAllAttn else ("View all " + str(len(attention)) + " →"))}
                    </button>
                }}
            </div>
        }}

        <button className="btn btn-primary btn-block" onClick={lambda (e: MouseEvent) { onStartHandoff(); }}>
            + Start handoff
        </button>
        <div className="cta-note">Shift ends in 42 min</div>

        <div className="sec-head">
            <span className="sec-title">{"Residents · " + str(len(residents))}</span>
            <input className="searchbox" value={query} onChange={onQuery} placeholder="Search room…"/>
        </div>

        <div className="res-list">
            {if not loading and len(ordered) == 0 {
                <div className="res-empty">{"No residents match “" + query + "”."}</div>
            }}
            {for (ri, e) in enumerate(ordered) {
                <button key={str(ri)} className="res-row"
                    onClick={lambda (ev: MouseEvent) { onOpenResident({"id": e["id"], "name": e["name"], "room": e["room"]}); }}>
                    <span className={dotClass(e["kind"] as str)}></span>
                    <span className="res-main">
                        <span className="res-name">{"Rm " + (e["room"] as str) + " · " + (e["name"] as str)}</span>
                        <span className={"res-reason res-reason-hot" if (e["hot"] as bool) else "res-reason"}>
                            {e["reason"] as str}
                        </span>
                    </span>
                    <span className="chev">›</span>
                </button>
            }}
        </div>

        <div className="tabbar">
            <button className="tabbar-item tabbar-active">
                <span className="tabbar-ic">⌂</span><span>Home</span>
            </button>
            <button className="tabbar-item" onClick={lambda (e: MouseEvent) { onRetrieve(); }}>
                <span className="tabbar-ic">⇄</span><span>Handoffs</span>
            </button>
            <button className="tabbar-item">
                <span className="tabbar-ic">☰</span><span>Residents</span>
            </button>
            <button className="tabbar-item" onClick={lambda (e: MouseEvent) { onSignOut(); }}>
                <span className="tabbar-ic">◔</span><span>Me</span>
            </button>
        </div>
    </div>;
}
