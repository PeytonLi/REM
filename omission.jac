"""omission.jac -- Person B, task B5 (PRD 9.3 / handoff-B).

POST-HOC OMISSION CHECK
=======================
Runs once a verbal handoff transcript exists -- never mid-sentence, never a
live nudge. It compares what the graph says must be conveyed against what
the transcript actually said.

THE LINE THIS FILE MUST NOT CROSS:
    The GRAPH decides what counts as required (required_findings() below --
    a deterministic query, zero model calls, zero judgment).
    The MODEL only ever answers one narrow question per claim: "was this
    specific claim mentioned in this specific transcript?" (was_conveyed()).
If an LLM call here ever starts inventing or ranking obligations, the design
has been inverted -- that question belongs to the graph, not the model.
"""

import from schema { Clinical }
import from jaclang.byllm.lib { Model }

# `any` here (not `Model`) so the self-check can swap this glob for a
# MockLLM without fighting static typing -- this is the one spot in the
# project where the model backing a `by` call is meant to be swappable.
glob cheap: any = Model(model_name="deepseek/deepseek-chat");
# ^ DeepSeek per PRD 10.1/10.3 -- cheap/budget model, this call is a single
# boolean per claim, not the nested SBARPlus composition. Reads
# DEEPSEEK_API_KEY from the environment (see .env.example). The self-check
# below reassigns `cheap` to a MockLLM, so `jac test` needs no API key.

# ============================================================================
# PROVISIONAL -- OWNED BY PERSON A. Real contract (docs/WORKPLAN.md section 3):
#     def required_findings() -> list[Clinical];
#
# The real obligation set is a deterministic graph query: tier>=0 findings,
# actions past due, live contradictions, any claim justifying an active
# intervention -- NO model involved anywhere in it. Until A lands that
# traversal, this returns 3 hand-built Clinical nodes matching the PRD 9.3 /
# handoff-B demo panel (antibiotic-switch reasoning, the desaturation
# pattern, the missed fall room-check), so the omission panel and this
# file's self-check are exercisable end-to-end right now.
#
# A: replace only this function's body with the real query. Nothing else
# in this file (was_conveyed, not_conveyed_claims, OmissionPanel) should
# need to change.
# ============================================================================
def required_findings() -> list[Clinical] {
    return [
        Clinical(
            claim="Antibiotic was switched to an alternative because of a rash reaction on day 1",
            category="medication",
            last_asserted=0.0,
            last_verified=0.0,
        ),
        Clinical(
            claim="Overnight oxygen desaturation happened three separate times across shifts and was never connected as a pattern",
            category="respiratory",
            last_asserted=0.0,
            last_verified=0.0,
        ),
        Clinical(
            claim="No room check has been logged following the 2:14 AM fall",
            category="safety",
            last_asserted=0.0,
            last_verified=0.0,
        ),
    ];
}
# ============================================================================
# END PROVISIONAL BLOCK
# ============================================================================

def was_conveyed(claim: str, transcript: str) -> bool by cheap();
sem was_conveyed = "Decide whether the substance of one specific clinical claim was communicated anywhere in a spoken shift-handoff transcript, in any wording or paraphrase. This is a coverage check only -- never judge whether the claim SHOULD have been said, only whether it WAS said, in substance, somewhere in the transcript. Answer true or false.";
sem was_conveyed.claim = "One required clinical claim/obligation to check for, taken verbatim from the graph's required_findings().";
sem was_conveyed.transcript = "The full transcript text of the spoken handoff being checked for coverage.";

"""Filter the graph's deterministic obligation set down to what the
transcript did not cover. The only model call inside this loop is the
per-claim was_conveyed() boolean -- the obligation set itself never
touches an LLM."""
def not_conveyed_claims(transcript: str) -> list[Clinical] {
    missed: list[Clinical] = [];
    for finding in required_findings() {
        if not was_conveyed(finding.claim, transcript) {
            missed.append(finding);
        }
    }
    return missed;
}

"""Post-hoc omission panel. Spawn on root with the finished transcript;
reports the Clinical findings the graph required and the conversation
skipped -- this is the UI panel's entire data source (PRD 9.3)."""
walker:pub OmissionPanel {
    has transcript: str;
    has reports: list[list[Clinical]] = [];

    can check with Root entry {
        report not_conveyed_claims(self.transcript);
    }
}
