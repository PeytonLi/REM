"""SBAR-plus composition — the handoff writer (PRD §6.4).

The typed struct IS the prompt: `compose_handoff` has no body, the LLM fills a
nested struct directly, and there is no output parsing or retry-on-malformed-JSON.

byLLM builds its output JSON-schema from the return type, and (verified on this
byllm 0.6) it cannot resolve a nested obj whose inner type is *imported from
another module* — `list[Action]` on the imported `SBARPlus` crashes the schema
builder with `'str' object has no attribute 'fields'`. So the LLM fills a LOCAL
draft (`SBARDraft` + `ActionDraft`/`IfThenDraft`, declared here), which is then
copied into the frozen `schema.SBARPlus` the rest of the system renders. This is
exactly the byllm-guide pattern: the AI schema and the storage schema stay
independent. `SBARPlus`/`Action`/`IfThen` remain frozen and untouched.

MODEL ROUTING (PRD §10.4): route by structural difficulty. Flat structs and enum
classification stay on the cheap project default (`gpt-4o-mini` in jac.toml). The
nested SBAR composition is the structurally-hard call, so it routes to the
stronger model via the local `compose_model` glob. We do NOT edit jac.toml.

MOCK vs REAL SEAM: live runs (`REM_LIVE=1`) use the real `gpt-4o`; tests/default
use MockLLM so `jac test` needs no key and no network.
"""

import from schema { Episode, Clinical, SBARPlus, Action, IfThen }
import from jaclang.byllm.lib { Model }
import os;


# --- Local draft types the LLM fills (see module docstring) ----------------
obj ActionDraft {
    """One action-list line item, LLM-filled."""
    has task: str;
    has owner: str;
    has due: str;
}
sem ActionDraft.task  = "A single concrete task, phrased as an imperative (e.g. 'Recheck SpO2').";
sem ActionDraft.owner = "Role responsible for the task: RN, LPN, CNA, or on-call MD.";
sem ActionDraft.due   = "When the task is due — a time or cadence (e.g. 'q2h', 'before 2000').";

obj IfThenDraft {
    """One if/then contingency, LLM-filled."""
    has trigger: str;
    has response: str;
}
sem IfThenDraft.trigger  = "An observable condition to watch for (e.g. 'SpO2 < 88% on 2L').";
sem IfThenDraft.response = "The exact action to take when the trigger is observed.";

obj SBARDraft {
    """The full SBAR-plus, LLM-filled, before it is copied into schema.SBARPlus."""
    has situation: str;
    has background: str;
    has assessment: str;
    has recommendation: str;
    has action_list: list[ActionDraft] = [];
    has contingencies: list[IfThenDraft] = [];
}
sem SBARDraft.situation = "One or two sentences: who the resident is and the single "
    "most important thing happening right now this shift.";
sem SBARDraft.background = "Relevant history and trend leading to the situation — "
    "baseline, recent changes, timeline. Concise, only what bears on the situation.";
sem SBARDraft.assessment = "The nurse's clinical read of what is going on and how "
    "concerning it is. A judgment, not a restatement of the data.";
sem SBARDraft.recommendation = "What the oncoming nurse should do and watch for — "
    "the plan, stated as concrete clinical guidance.";
sem SBARDraft.action_list = "Explicit, discrete tasks the next shift must complete. "
    "Each has a clear task, an owner, and a due window.";
sem SBARDraft.contingencies = "If/then safety nets: foreseeable triggers and the exact "
    "response for each, so deterioration is caught without a phone call first.";


# --- Model routing (PRD §10.4) ---------------------------------------------
# The nested SBAR composition is the structurally-hard call -> stronger model.
# Only invoked on the live path (`REM_LIVE=1`); the non-live path returns a
# deterministic canned draft (below) so `jac test` and offline demos need no key,
# no network, and no MockLLM (whose schema builder can't handle a nested obj).
glob compose_model: Model = Model(model_name="gpt-4o");


# --- The LLM-backed writer (PRD §6.4): declare, don't implement --------------
# Inputs are plain strings (episode contents, belief claims) — byLLM serializes
# them straight into the prompt with no node-graph internals to trip over.
def compose_handoff(episodes: list[str], beliefs: list[str]) -> SBARDraft by compose_model();

sem compose_handoff = "Compose a nurse-to-nurse SBAR-plus shift handoff for a "
    "long-term-care resident. Ground every line strictly in the supplied beliefs "
    "and episodes — never invent facts. SBAR (Situation, Background, Assessment, "
    "Recommendation) is the nurse-level standard; layer on an explicit action list "
    "and if/then contingencies so nothing actionable is lost across the shift.";
sem compose_handoff.episodes = "Recent raw observation texts (vitals, notes, wearable "
    "events) that survived decay — the concrete evidence base.";
sem compose_handoff.beliefs = "Distilled, still-active clinical belief statements about "
    "the resident — the durable picture the handoff must convey.";


"""Copy an LLM draft into the frozen schema.SBARPlus the rest of REM renders."""
def to_sbar(d: SBARDraft) -> SBARPlus {
    return SBARPlus(
        situation=d.situation,
        background=d.background,
        assessment=d.assessment,
        recommendation=d.recommendation,
        action_list=[Action(task=a.task, owner=a.owner, due=a.due) for a in d.action_list],
        contingencies=[IfThen(trigger=c.trigger, response=c.response) for c in d.contingencies]
    );
}


"""Deterministic offline stand-in for the LLM (non-live runs / tests).

Structurally identical to a live draft — nested action list + contingencies —
so the walker and `to_sbar` are exercised end-to-end without an API call."""
def _demo_draft(beliefs: list[str]) -> SBARDraft {
    covers = "; ".join(beliefs[:4]) if beliefs else "no active beliefs";
    return SBARDraft(
        situation="Resident with several active findings this shift.",
        background=f"Active picture: {covers}.",
        assessment="Multiple concurrent findings; watch the respiratory and fall risks.",
        recommendation="Verify orders against current status; follow the action list below.",
        action_list=[
            ActionDraft(task="Recheck overnight SpO2 trend", owner="RN", due="q2h"),
            ActionDraft(task="Confirm room check after the fall", owner="CNA", due="immediately")
        ],
        contingencies=[
            IfThenDraft(trigger="SpO2 < 88% overnight", response="Escalate to on-call MD"),
            IfThenDraft(trigger="Any further fall", response="Neuro checks q15min, notify MD")
        ]
    );
}


# --- Walker: gather surviving semantics + salient episodes, then compose -----
walker:pub Compose {
    """Collect non-suppressed beliefs and high-strength episodes from the FLAT
    graph (everything hangs off root), compose the SBAR-plus, and report it once.

    Live (`REM_LIVE=1`): the stronger model fills the draft. Offline: a
    deterministic canned draft — same shape, no API — so the pipeline still runs."""
    has min_strength: float = 0.5;   # episodes below this dropped out of the summary
    has sbar: SBARPlus | None = None;
    has reports: list[SBARPlus] = [];

    can gather with Root entry {
        beliefs = [c.claim for c in [root -->[?:Clinical, suppressed == False]]];
        episodes = [e.content for e in [root -->[?:Episode, strength >= self.min_strength]]];
        draft = compose_handoff(episodes, beliefs) if (os.getenv("REM_LIVE") == "1")
            else _demo_draft(beliefs);
        self.sbar = to_sbar(draft);
    }

    can emit with Root exit {
        if self.sbar is not None {
            report self.sbar;
        }
    }
}


# ---------------------------------------------------------------------------
# Tests — MockLLM (glob above) serves one pre-built SBARDraft per by-call, so no
# API is hit. Assert across 3 runs that the mapped SBARPlus comes back populated.
# ---------------------------------------------------------------------------

test "compose fills a well-formed nested SBARPlus over 3 runs" {
    root ++> Clinical(
        claim="COPD exacerbation", category="respiratory",
        last_asserted=0.0, last_verified=0.0
    );
    root ++> Episode(content="SpO2 88% on room air", source="vitals_manual", author="RN", at=0.0);
    root ++> Episode(content="RR 24", source="vitals_manual", author="RN", at=0.0, strength=0.2);

    for i in range(3) {
        result = root spawn Compose();
        assert len(result.reports) == 1;
        sbar = result.reports[0];
        assert isinstance(sbar, SBARPlus);

        # scalar SBAR fields are populated
        assert len(sbar.situation) > 0;
        assert len(sbar.assessment) > 0;

        # action_list: non-empty list[Action] with populated fields
        assert isinstance(sbar.action_list, list);
        assert len(sbar.action_list) > 0;
        for a in sbar.action_list {
            assert isinstance(a, Action);
            assert len(a.task) > 0;
            assert len(a.owner) > 0;
            assert len(a.due) > 0;
        }

        # contingencies: non-empty list[IfThen] with populated fields
        assert isinstance(sbar.contingencies, list);
        assert len(sbar.contingencies) > 0;
        for c in sbar.contingencies {
            assert isinstance(c, IfThen);
            assert len(c.trigger) > 0;
            assert len(c.response) > 0;
        }
    }
}
