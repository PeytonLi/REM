"""Topology-robust graph reads (the A<->B seam fix).

A's graph core was written flat — every node hangs directly off `root` — and reads
with 1-hop comprehensions like `[root -->[?:Episode]]`. B's ingest walkers
(PRD §6.2a) attach episodes under a per-shift `Handoff` node instead, so they sit
TWO hops from root and a 1-hop read misses them.

These helpers gather a node type from BOTH places — directly off root AND under
any `Handoff` hanging off root — so the pipeline sees episodes regardless of which
ingest path produced them. On a flat graph they return exactly the 1-hop set, so
they are a safe drop-in for the old reads.
"""

import from schema { Episode, Clinical, ActionNode, Handoff }


"""All episodes reachable from root: direct children + those under Handoffs."""
def all_episodes -> list[Episode] {
    out: list[Episode] = [root -->[?:Episode]];
    for h in [root -->[?:Handoff]] {
        for e in [h -->[?:Episode]] {
            out.append(e);
        }
    }
    return out;
}


"""All beliefs reachable from root (direct + Handoff-nested)."""
def all_clinicals -> list[Clinical] {
    out: list[Clinical] = [root -->[?:Clinical]];
    for h in [root -->[?:Handoff]] {
        for c in [h -->[?:Clinical]] {
            out.append(c);
        }
    }
    return out;
}


"""All care tasks reachable from root (direct + Handoff-nested)."""
def all_actions -> list[ActionNode] {
    out: list[ActionNode] = [root -->[?:ActionNode]];
    for h in [root -->[?:Handoff]] {
        for a in [h -->[?:ActionNode]] {
            out.append(a);
        }
    }
    return out;
}


test "helpers gather nodes from root and from under a Handoff" {
    root ++> Episode(content="flat", source="nursing_note", author="RN", at=0.0);
    h = root ++> Handoff(shift="D5-night");
    h ++> Episode(content="nested", source="wearable_fall", author="dev", at=1.0);

    eps = all_episodes();
    contents = [e.content for e in eps];
    assert "flat" in contents;      # 1-hop, as before
    assert "nested" in contents;    # 2-hop under the Handoff — the fix
}
