"""Order enrichment — turn medication episodes into running-order structure.

Consolidation abstracts *beliefs* and (for a lab-negated cluster) splits them into
a suppressed "suspected" loser + a live "ruled out" winner joined by a `Contradicts`
edge. What it does NOT model is the running *care order*: R2 (live contradiction)
only fires when that suppressed loser is still justifying an order that is actually
running. This walker supplies exactly that missing piece, deterministically (no LLM):

  * A drug with a MAR "administered/ordered/started" episode and no later
    "discontinued/held" episode is a RUNNING order -> one `ActionNode`. Its `due`
    is 0.0 (a continuous med order is not a due-dated follow-up, so R4 skips it);
    it has no `Completed` edge, so it counts as active for R2/R3.
  * The order is justified by a same-subject belief, preferring a suppressed
    loser — the copy-forward zombie consolidation just suppressed.

Runs AFTER Consolidate (beliefs + contradictions must exist) and BEFORE Tripwire.
Source-agnostic apart from reading `source == "mar"`; never inspects `wearable_*`.
"""

import from schema { Episode, Clinical, ActionNode, Justifies, now }


"""First token of a MAR line, lowercased — the drug name (e.g. 'levofloxacin')."""
def drug_of(content: str) -> str {
    parts = content.strip().split(" ");
    return parts[0].lower() if parts else "";
}


walker:pub EnrichOrders {
    """Create ActionNodes for running medication orders and justify them from a
    same-subject belief (preferring a suppressed loser). Reports the count."""
    has reports: list[int] = [];

    can run with Root entry {
        # Drugs explicitly discontinued/held are NOT running.
        discontinued: set[str] = set();
        for e in [here -->[?:Episode, source == "mar"]] {
            lc = e.content.lower();
            if "discontinued" in lc or "held" in lc {
                discontinued.add(drug_of(e.content));
            }
        }

        made = 0;
        seen: set[str] = set();
        for e in [here -->[?:Episode, source == "mar"]] {
            c = e.content.lower();
            running = ("administered" in c) or ("ordered" in c) or ("started" in c);
            drug = drug_of(e.content);
            if running and drug != "" and drug not in discontinued and drug not in seen {
                seen.add(drug);
                order = here ++> ActionNode(task=e.content, due=0.0, owner=e.author);

                # Justify the order from a same-subject belief; prefer a suppressed
                # loser (the contradicted claim still driving a running order = R2).
                target: Clinical | None = None;
                for b in [here -->[?:Clinical, subject == e.subject]] {
                    if b.suppressed {
                        target = b;
                    } elif target is None {
                        target = b;
                    }
                }
                if target is not None {
                    (target as Clinical) +>:Justifies():+> order;
                }
                made += 1;
            }
        }
        report made;
    }
}


test "enrich builds a running order and justifies it from the suppressed loser" {
    # Consolidation has already suppressed the suspected-UTI belief (the zombie).
    susp = root ++> Clinical(claim="Suspected UTI", category="infection",
        last_asserted=now(), last_verified=now(), suppressed=True, subject="uti");
    root ++> Episode(content="Levofloxacin 500 mg PO administered.", source="mar",
        author="RN A", at=now(), subject="uti");
    root ++> Episode(content="Ceftriaxone discontinued per MD due to rash.", source="mar",
        author="RN B", at=now(), subject="rash");

    r = root spawn EnrichOrders();

    # Exactly one running order (levofloxacin); ceftriaxone was discontinued.
    assert len([root -->[?:ActionNode]]) == 1;
    # The suppressed loser now justifies the running order -> R2 will fire.
    assert len([susp ->:Justifies:->]) == 1;
    assert r.reports[0] == 1;
}
