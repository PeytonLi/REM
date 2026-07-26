"""Consolidate walker — the four-phase memory consolidation pass (PRD §6.3).

Runs at every shift boundary (or on the demo button). It turns a pile of raw,
timestamped `Episode` observations into a small set of durable `Clinical`
beliefs, reconciles those beliefs against each other, and prunes captured noise.

Four phases, in order:

  1. Replay   — PURE graph traversal, no LLM. Assemble the working set of recent,
                not-yet-abstracted episodes and group them by their `subject` tag.
  2. Abstract — for every subject-cluster of >=3 episodes, ONE `by llm()` call
                extracts the invariant belief -> one new `Clinical` node + a
                `Derived` edge to each source episode. The >=3 floor is a hard
                hallucination guard: a 2-episode cluster produces ZERO Clinicals.
  3. Reconcile— `Clinical` pairs are gated by `subject` tag BEFORE any LLM call
                (the O(n^2) mitigation, PRD §15). The LLM classifies each gated
                pair duplicate / refinement / contradiction / unrelated.
  4. Prune    — low-strength episodes already captured by a semantic parent get
                `archived = True`. Nothing is ever `del`'d (PRD §6.1).

Architectural invariant (PRD G8 / §6.2a): a device episode is treated IDENTICALLY
to a nursing note. There is deliberately NO `wearable_*` branch anywhere in this
file — the source string never steers control flow. If you find yourself writing
`if source == "wearable..."` you have broken the design.
"""

import from schema { Episode, Clinical, Step, Derived, Contradicts, Refines, now }
import from decay { STRENGTH_FLOOR }
import from jaclang.byllm.lib { Model, MockLLM }
import os;


# ---------------------------------------------------------------------------
# LLM seam (PRD §6.3 phases 2 & 3). Declared `by llm()` — no body. Described with
# `sem`, never docstrings. The struct IS the prompt (PRD §6.4).
# ---------------------------------------------------------------------------

obj ClinicalDraft {
    """LLM-filled draft of a belief. Copied into a graph `Clinical` node once cited."""
    has claim: str;
    has category: str;
    has subject: str;
}
sem ClinicalDraft.claim    = "The single invariant belief the episodes jointly support, as a clinician would state it. Assert only what the episodes actually show — never generalize beyond them.";
sem ClinicalDraft.category = "One clinical category for the belief, e.g. respiratory, cardiac, infection, neuro, mobility, sleep, fall, skin.";
sem ClinicalDraft.subject  = "A short coarse subject tag (one or two words) naming what the belief is about, used to group related beliefs.";


def abstract_cluster(contents: list[str]) -> ClinicalDraft by llm();
sem abstract_cluster = "Given the raw text of >=3 related observations about one resident, extract the single invariant clinical belief they jointly support. Extraction, not generation: the belief must be traceable to the observations. Do not invent anything the observations do not show.";
sem abstract_cluster.contents = "The raw `content` strings of the episodes in one subject-cluster.";


enum Relation { DUPLICATE, REFINEMENT, CONTRADICTION, UNRELATED }
sem Relation.DUPLICATE     = "The two beliefs assert the same thing; they should be merged and their provenance unioned.";
sem Relation.REFINEMENT    = "One belief is a more specific version of the other; the specific one refines the general one.";
sem Relation.CONTRADICTION = "The two beliefs cannot both be true; one must win and the other be suppressed.";
sem Relation.UNRELATED     = "The two beliefs are about different matters despite sharing a subject tag; leave both alone.";


def classify_pair(a: str, b: str) -> Relation by llm();
sem classify_pair = "Classify the relationship between two clinical beliefs about the same resident and subject as duplicate, refinement, contradiction, or unrelated.";
sem classify_pair.a = "The claim text of the first belief.";
sem classify_pair.b = "The claim text of the second belief.";


# ---------------------------------------------------------------------------
# Model binding. This module binds `llm` to MockLLM so `jac test` runs with no
# API key and no network (jac-by-llm guide). Declared AFTER the return types so
# the pre-built outputs resolve. In production you swap this one line for
# `glob llm = Model(model_name="gpt-4o-mini");` — nothing else changes, because
# the `by llm()` signatures are identical against either backend. The outputs
# are consumed one per `by llm()` call, in order: spo2 draft (test B), cardiac
# draft (test C run-1), cardiac draft (test C run-2), then the CONTRADICTION.
# ---------------------------------------------------------------------------

# Live runs (`REM_LIVE=1`) use the real cheap model; tests/default use MockLLM so
# `jac test` needs no key and no network. The `by llm()` signatures are identical
# against either backend — only this one line changes.
glob llm = Model(model_name="gpt-4o-mini") if (os.getenv("REM_LIVE") == "1") else MockLLM(model_name="mockllm", config={"outputs": [
    ClinicalDraft(claim="SpO2 recurrently desaturates overnight",
                  category="respiratory", subject="spo2"),
    ClinicalDraft(claim="Evening blood pressure runs high",
                  category="cardiac", subject="cardiac"),
    ClinicalDraft(claim="Evening blood pressure runs low",
                  category="cardiac", subject="cardiac"),
    Relation.CONTRADICTION
]});


# ---------------------------------------------------------------------------
# Module result obj — the typed report channel payload (WORKPLAN §4).
# ---------------------------------------------------------------------------

obj ConsolidateResult {
    """One consolidation pass, summarized. `log` is the replay tape (PRD §13):
    the demo replays these Steps instead of re-running the LLM live.

    `before`/`after` count LIVE nodes only — non-archived episodes plus
    non-suppressed clinicals. Suppressed/archived nodes still exist in the graph
    (never `del`'d) and stay reachable by traversal; they are simply excluded
    from the live count so `after` reflects what the next handoff will see."""
    has before: int;
    has after: int;
    has log: list[Step] = [];
}


# ---------------------------------------------------------------------------
# Pure helpers (no LLM, no mutation).
# ---------------------------------------------------------------------------

"""Number of source episodes a belief cites — its support count (PRD §7 R1)."""
def support_count(c: Clinical) -> int {
    return len([c ->:Derived:->]);
}


# ---------------------------------------------------------------------------
# The walker. Topology is flat (every node hangs off root), so all four phases
# run in the single Root-entry ability via 1-hop reads; the result is reported
# once from the Root-exit ability.
# ---------------------------------------------------------------------------

walker:pub Consolidate {
    """Reports exactly one `ConsolidateResult` per spawn."""
    has reports: list[ConsolidateResult] = [];
    has log: list[Step] = [];
    has before_count: int = 0;

    can run with Root entry {
        self.before_count = self.live_count();

        # -- Phase 1: Replay (pure traversal, NO LLM) -----------------------
        # Working set = recent, non-archived episodes not yet abstracted (no
        # incoming Derived edge). Grouping is by subject tag ONLY — the source
        # string is never inspected, so a device episode clusters exactly like a
        # nursing note.
        clusters: dict[str, list[Episode]] = {};
        for ep in [here -->[?:Episode, archived == False]] {
            if not [ep <-:Derived:<-] {
                keep = ep.subject.strip();
                if keep != "" {
                    if keep in clusters {
                        clusters[keep].append(ep);
                    } else {
                        clusters[keep] = [ep];
                    }
                }
            }
        }
        replayed = self.live_count();
        self.log.append(Step(
            phase="replay",
            detail=f"assembled {len(clusters)} subject-cluster(s) from working set",
            before=self.before_count, after=replayed
        ));

        # -- Phase 2: Abstract (LLM, >=3 floor) -----------------------------
        before_abs = self.live_count();
        made = 0;
        for subj in clusters.keys() {
            eps = clusters[subj];
            if len(eps) < 3 {
                # Hard hallucination guard: fewer than 3 episodes -> no belief.
                continue;
            }
            draft = abstract_cluster([e.content for e in eps]);
            belief = here ++> Clinical(
                claim=draft.claim,
                category=draft.category,
                subject=subj,                 # cluster tag drives reconcile gating
                last_asserted=now(),
                last_verified=now()
            );
            for e in eps {
                belief +>:Derived():+> e;     # provenance to every source episode
            }
            made += 1;
        }
        after_abs = self.live_count();
        self.log.append(Step(
            phase="abstract",
            detail=f"abstracted {made} new clinical belief(s) from clusters of >=3",
            before=before_abs, after=after_abs
        ));

        # -- Phase 3: Reconcile (subject-gated, then LLM) -------------------
        before_rec = self.live_count();
        by_subject: dict[str, list[Clinical]] = {};
        for c in [here -->[?:Clinical, suppressed == False]] {
            keep = c.subject.strip();
            if keep == "" {
                continue;
            }
            if keep in by_subject {
                by_subject[keep].append(c);
            } else {
                by_subject[keep] = [c];
            }
        }
        actions = 0;
        for subj in by_subject.keys() {
            group = by_subject[subj];
            i = 0;
            while i < len(group) {
                j = i + 1;
                while j < len(group) {
                    a = group[i];
                    b = group[j];
                    # Both sides may have been suppressed earlier this pass.
                    if a.suppressed or b.suppressed {
                        j += 1;
                        continue;
                    }
                    rel = classify_pair(a.claim, b.claim);
                    if rel == Relation.DUPLICATE {
                        self.merge_beliefs(a, b);
                        actions += 1;
                    } elif rel == Relation.CONTRADICTION {
                        self.mark_contradiction(a, b);
                        actions += 1;
                    } elif rel == Relation.REFINEMENT {
                        self.mark_refinement(a, b);
                        actions += 1;
                    }
                    # UNRELATED: leave both alone.
                    j += 1;
                }
                i += 1;
            }
        }
        after_rec = self.live_count();
        self.log.append(Step(
            phase="reconcile",
            detail=f"resolved {actions} gated pair(s) (duplicate/contradiction/refinement)",
            before=before_rec, after=after_rec
        ));

        # -- Phase 4: Prune (flag only, never del) --------------------------
        before_prune = self.live_count();
        pruned = 0;
        for ep in [here -->[?:Episode, archived == False]] {
            # "Captured by a semantic parent" == has an incoming Derived edge.
            if ep.strength < STRENGTH_FLOOR and [ep <-:Derived:<-] {
                ep.archived = True;           # never `del` — salience, not deletion
                pruned += 1;
            }
        }
        after_prune = self.live_count();
        self.log.append(Step(
            phase="prune",
            detail=f"archived {pruned} low-strength captured episode(s)",
            before=before_prune, after=after_prune
        ));
    }

    can finish with Root exit {
        report ConsolidateResult(
            before=self.before_count,
            after=self.live_count(),
            log=self.log
        );
    }

    """Live node count: non-archived episodes + non-suppressed clinicals."""
    def live_count -> int {
        return len([root -->[?:Episode, archived == False]])
             + len([root -->[?:Clinical, suppressed == False]]);
    }

    """Duplicate: union provenance onto the surviving side, suppress the loser."""
    def merge_beliefs(a: Clinical, b: Clinical) {
        winner = a;
        loser = b;
        if not self.wins(a, b) {
            winner = b;
            loser = a;
        }
        for ep in [loser ->:Derived:->] {
            if ep not in [winner ->:Derived:->] {
                winner +>:Derived():+> ep;
            }
        }
        loser.suppressed = True;              # never `del`
    }

    """Contradiction: add a Contradicts edge, keep the live side, suppress loser."""
    def mark_contradiction(a: Clinical, b: Clinical) {
        winner = a;
        loser = b;
        if not self.wins(a, b) {
            winner = b;
            loser = a;
        }
        winner +>:Contradicts(resolved_toward=winner.claim, at=now()):+> loser;
        loser.suppressed = True;              # never `del`
    }

    """Refinement: the more recent belief refines the older one (no suppression)."""
    def mark_refinement(a: Clinical, b: Clinical) {
        newer = a;
        older = b;
        if b.last_asserted > a.last_asserted {
            newer = b;
            older = a;
        }
        newer +>:Refines():+> older;
    }

    """True if `a` is the live side over `b`: recency first, support count breaks ties."""
    def wins(a: Clinical, b: Clinical) -> bool {
        if a.last_asserted != b.last_asserted {
            return a.last_asserted > b.last_asserted;
        }
        return support_count(a) >= support_count(b);
    }
}


# ===========================================================================
# Tests — MockLLM only, no network. Graph + MockLLM output cursor are shared
# across tests in declaration order; reset between RUNS with
# `jac clean --all --force`. The glob `llm` above holds the outputs consumed
# here, in this exact order: spo2 draft, cardiac draft, cardiac draft, then the
# CONTRADICTION relation.
# ===========================================================================

"""Helper: attach an episode to root with a subject tag."""
def _seed(content: str, source: str, subject: str) -> Episode {
    return root ++> Episode(
        content=content, source=source, author="tester",
        at=now(), subject=subject
    );
}


test "two-episode cluster produces zero clinical nodes" {
    # A cluster below the >=3 floor must NOT reach the LLM and must yield 0 beliefs.
    _seed("Refused morning fluids", "nursing_note", "hydration");
    _seed("Only sipped water at lunch", "nursing_note", "hydration");

    result = root spawn Consolidate();

    assert len(result.reports) == 1;
    assert len([root -->[?:Clinical, subject == "hydration"]]) == 0;
    # Four phases always logged.
    assert len(result.reports[0].log) == 4;
}


test "three-episode cluster produces one clinical with three derived edges" {
    # Deliberately mixes a device source in with nurse sources — same pipeline,
    # no wearable branch. The floor of 3 is met, so exactly one belief is minted.
    _seed("SpO2 dipped to 88% overnight", "nursing_note", "spo2");
    _seed("SpO2 84% at 03:20 on monitor", "wearable_vitals", "spo2");
    _seed("Nurse noted desaturation on rounds", "nursing_note", "spo2");

    root spawn Consolidate();

    beliefs = [root -->[?:Clinical, subject == "spo2", suppressed == False]];
    assert len(beliefs) == 1;
    assert len([beliefs[0] ->:Derived:->]) == 3;
}


test "reconcile contradiction suppresses loser but keeps it reachable" {
    # First pass abstracts one cardiac belief from 3 fresh episodes.
    _seed("BP 168/94 this evening", "vitals_manual", "cardiac");
    _seed("BP 172/96 before dinner", "vitals_manual", "cardiac");
    _seed("Evening hypertension flagged", "nursing_note", "cardiac");
    root spawn Consolidate();

    # Second pass abstracts a SECOND cardiac belief from 3 NEW episodes (the
    # first batch is now excluded — already Derived). Two same-subject beliefs
    # then trip the subject-gated reconcile -> CONTRADICTION.
    _seed("BP 92/54 this evening", "vitals_manual", "cardiac");
    _seed("BP 88/50 before dinner", "vitals_manual", "cardiac");
    _seed("Evening hypotension flagged", "nursing_note", "cardiac");
    root spawn Consolidate();

    cardiac = [root -->[?:Clinical, subject == "cardiac"]];
    suppressed = [c for c in cardiac if c.suppressed];
    live = [c for c in cardiac if not c.suppressed];

    # Loser suppressed, not deleted -> still reachable by plain traversal.
    assert len(suppressed) == 1;
    assert len(live) == 1;
    assert suppressed[0] in [root -->[?:Clinical]];
    assert suppressed[0].suppressed;
    # The Contradicts edge was written from the live side to the loser.
    assert len([live[0] ->:Contradicts:->]) == 1;
}
