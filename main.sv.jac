"""REM API service — the graph core exposed over REST (WORKPLAN §4).

`jac start main.sv.jac` (or `jac run` for local) auto-exposes every `:pub` walker
below at `POST /walker/<Name>`, with Swagger at `/docs` and a live graph view at
`/graph`. Importing each module registers its walker; this file adds no logic of
its own — it is the seam where B's client (or curl) reaches A's graph.

Endpoints A owns (this file):
    POST /walker/SeedGraph      -> {reports:[<raw episode count>]}      (demo reset)
    POST /walker/Consolidate    -> {reports:[ConsolidateResult]}        (§6.3)
    POST /walker/ApplyDecay     -> {reports:[<nodes touched>]}          (§6.2)
    POST /walker/Compose        -> {reports:[SBARPlus]}                 (§6.4)
    POST /walker/Tripwire       -> {reports:[Finding, ...]}             (§7)
    POST /walker/Escalate       -> {reports:[EscalationResult]}         (§8)
    POST /walker/Retrieve       -> {reports:[Episode, ...]}            (§6.2)
    POST /function/required_findings, /function/provenance             (§9.3, §13)

Endpoints B owns (not here): /walker/Baseline, /walker/IngestDevice,
/walker/IngestTranscript.

Set `REM_LIVE=1` in the server environment to use the real models for the two
LLM walkers (Consolidate abstraction, Compose); unset, both fall back to a
deterministic offline path so the server runs with no API key.
"""

import from fixture { SeedGraph }
import from consolidate { Consolidate }
import from decay { ApplyDecay }
import from retrieve { Retrieve, required_findings, provenance }
import from compose { Compose }
import from tripwire { Tripwire }
import from escalate { Escalate }


# Expose the two A-provided seam functions as /function/<name> endpoints
# (contracts.jac). They run on the caller's graph — same shape B codes against.
"""The obligations set (PRD §9.3) as claim strings, for the omission panel."""
def:pub obligations -> list[str] {
    return [c.claim for c in required_findings()];
}

"""Click-to-source (PRD §13): the source-episode contents behind a belief."""
def:pub sources_for(claim_id: str) -> list[str] {
    return [e.content for e in provenance(claim_id)];
}
