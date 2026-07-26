"""baseline.jac -- Person B, task B2: the naive handoff baseline.

This is deliberately BAD. It is both the experimental control (PRD Sec 12,
"fact survival") and the demo's left pane (PRD Sec 13): what an incoming nurse
gets today -- the last shift's documentation plus accumulated copy-forward.

WHY THIS IS NOT JUST "CONCATENATE EVERY EPISODE":
A dump of all 400 episodes would carry the day-1 rash narrative verbatim, and
the left pane would then contain the very causal reason the right pane is
supposed to be the only one to preserve. That is not what an incoming nurse
receives, and it would quietly destroy the split-screen claim.

Real copy-forward propagates STATE, not narrative. Each shift inherits the
prior note's assertions -- "continues on levofloxacin", "suspected UTI" -- and
a one-time day-1 explanation that nobody repeats simply never propagates. So
the rule here is: an episode reaches the incoming nurse only if it is from the
final shift, or its content KEEPS BEING RE-ASSERTED across >=3 distinct shifts.

That is principled rather than circular -- nothing drops the rash episode by
name. It dies because nobody repeated it, which is exactly failure mode #1 in
PRD Sec 2: the "why" dies first.

No summarization, no dedup, no LLM call. Runs from the project root.
"""

import json;
import re;

import from schema { Episode }

glob SEED_PATH: str = "seed/patient.json";

# Shift 6 of the demo is the last shift the incoming nurse is taking over from.
glob FINAL_SHIFT: str = "D5-night";

# How many distinct shifts must re-assert a claim before copy-forward carries
# it. Hand-tuned on synthetic data (PRD Sec 12) -- at 2 the day-1 rash note
# survives via its own overnight follow-up, which is not copy-forward at all.
glob RECUR_MIN_SHIFTS: int = 3;


def load_rows(path: str) -> list[dict] {
    with open(path) as f {
        raw: any = json.load(f);
        rows: list[dict] = raw as list[dict];
    }
    rows.sort(key=lambda (r: dict) -> float { return r["at"] as float; });
    return rows;
}


"""Normalize a note down to a copy-forward signature: numbers and punctuation
stripped, first 8 words kept. Two shifts charting the same standing claim in
slightly different words collapse to the same signature."""
def signature(content: str) -> str {
    s: str = content.lower();
    s = re.sub(r"\d+(\.\d+)?", "#", s);
    s = re.sub(r"[^a-z# ]", " ", s);
    return " ".join(s.split()[:8]);
}


"""Which distinct shifts re-assert each signature."""
def shifts_by_signature(rows: list[dict]) -> dict[str, set[str]] {
    acc: dict[str, set[str]] = {};
    for row in rows {
        key: str = signature(row["content"] as str);
        if key not in acc {
            acc[key] = set();
        }
        acc[key].add(row["shift"] as str);
    }
    return acc;
}


def as_episode(row: dict) -> Episode {
    # Consumes the schema-owned Episode node. `shift` is not an Episode field
    # (schema.jac is A's) so it is carried alongside as raw row data.
    return Episode(
        content = row["content"] as str,
        source  = row["source"] as str,
        author  = row["author"] as str,
        at      = row["at"] as float,
    );
}


def naive_summary(rows: list[dict]) -> str {
    recurrence = shifts_by_signature(rows);
    lines: list[str] = [];
    for row in rows {
        shift: str = row["shift"] as str;
        repeated: bool = len(recurrence[signature(row["content"] as str)]) >= RECUR_MIN_SHIFTS;
        if shift != FINAL_SHIFT and not repeated {
            continue;   # never got copied forward; the incoming nurse never sees it
        }
        ep = as_episode(row);
        lines.append(f"[{shift} | {ep.author}] {ep.content}");
    }
    return "\n".join(lines);
}


walker:pub Baseline {
    """Naive handoff: last shift plus accumulated copy-forward.

    NOTE for whoever owns main.jac: this walker is not imported anywhere yet,
    so /walker/Baseline will not self-register until either main.jac imports it
    (`import from baseline { Baseline }`) or a client module `sv import`s it.
    B2's boundaries forbid editing main.jac -- flagging it here instead.
    """
    has reports: list[str] = [];

    can run with Root entry {
        rows = load_rows(SEED_PATH);
        report naive_summary(rows);
    }
}


with entry:__main__ {
    rows = load_rows(SEED_PATH);
    summary = naive_summary(rows);
    low: str = summary.lower();

    word_count: int = len(summary.split());
    print(f"naive baseline word count: {word_count}");
    assert word_count > 3000, f"expected > 3000 words of copy-forward bloat, got {word_count}";

    # State survives copy-forward -- this is what every later note says.
    assert "levofloxacin" in low, "the alternate drug must survive copy-forward";
    assert "uti" in low, "the UTI zombie must ride along past the negative culture";

    # The WHY does not. Absence outright, not merely "not in the same sentence":
    # an earlier version of this check only looked within one sentence and
    # passed while the naive pane still read "discontinued due to suspected
    # drug rash. Levofloxacin started in its place." -- which is the entire
    # fact the right-hand pane is supposed to be alone in preserving.
    assert "rash" not in low, "causal reason leaked into the naive baseline";
    assert "ceftriaxone" not in low, "the original drug leaked into the naive baseline";

    print("self-check passed: state survives, the why is gone -- bad in the right way.");
}
