"""Decay — salience over time (PRD §6.2).

    strength *= exp(-Δt / (τ · (1 + log(1 + access_count))))

Decay governs *salience, not deletion* (PRD §6.1). Nothing is ever removed;
strength answers "how much does this deserve airtime in the next handoff." Use
boosts survival — a frequently-retrieved episode decays slower.

All tuning knobs are named constants at the top of the file, not inline literals
(handoff-A "Traps") — they get hand-tuned during eval.
"""

import from math { exp, log }
import from schema { Episode, Clinical, now }

# --- tuning knobs (hand-tuned on synthetic data; see PRD §12) ---------------
glob TAU_EPISODE: float = 129600.0;   # 36h in seconds — episodic memory decays fast
glob TAU_CLINICAL: float = 604800.0;  # 7d in seconds — semantic beliefs decay slow
glob STRENGTH_FLOOR: float = 0.15;    # below this an episode drops out of the summary
glob RETRIEVAL_BOOST: float = 0.25;   # additive strength bump on retrieval


"""Multiplicative decay factor over `dt` seconds at a given access count.

The access-count term lengthens the effective time-constant, so use slows decay.
Pure function — no graph reads — so it is trivially unit-testable.
"""
def decay_factor(dt: float, access_count: int, tau: float) -> float {
    if dt <= 0.0 {
        return 1.0;
    }
    effective_tau = tau * (1.0 + log(1.0 + access_count));
    return exp(-dt / effective_tau);
}


"""Strength an episode would have at time `at_time`, given its last access.

Δt is measured from the later of creation (`at`) and `last_accessed`, so a
retrieval resets the clock as well as adding the boost.
"""
def episode_strength(ep: Episode, at_time: float) -> float {
    ref = ep.last_accessed if ep.last_accessed > ep.at else ep.at;
    dt = at_time - ref;
    return ep.strength * decay_factor(dt, ep.access_count, TAU_EPISODE);
}


"""Strength a belief would have at time `at_time`. Beliefs use the slow τ and
decay from `last_asserted` (re-assertion is the belief's 'access')."""
def clinical_strength(c: Clinical, at_time: float) -> float {
    dt = at_time - c.last_asserted;
    return c.strength * decay_factor(dt, 0, TAU_CLINICAL);
}


"""Write the decayed strength back onto every episode/belief below the graph.

Applied at a shift boundary before Compose so the summary reflects current
salience. Never archives or deletes — that is Consolidate's prune phase.
"""
walker:pub ApplyDecay {
    has at_time: float = 0.0;
    has touched: int = 0;
    has reports: list[int] = [];

    can start with Root entry {
        if self.at_time == 0.0 {
            self.at_time = now();
        }
        visit [-->];
    }

    can decay_episode with Episode entry {
        here.strength = episode_strength(here, self.at_time);
        self.touched += 1;
        visit [-->];
    }

    can decay_clinical with Clinical entry {
        here.strength = clinical_strength(here, self.at_time);
        self.touched += 1;
        visit [-->];
    }

    can finish with Root exit {
        report self.touched;
    }
}


# ---------------------------------------------------------------------------
# Self-check (handoff-A A1): strength after 48h with 0 accesses < with 5 accesses,
# and exact decay values against hand-computed numbers.
# ---------------------------------------------------------------------------

test "use slows decay: 5 accesses beat 0 over 48h" {
    dt = 48.0 * 3600.0;
    cold = decay_factor(dt, 0, TAU_EPISODE);
    warm = decay_factor(dt, 5, TAU_EPISODE);
    assert warm > cold;
}

test "decay_factor matches hand-computed value" {
    dt = 36.0 * 3600.0;                 # exactly one time-constant, 0 accesses
    f = decay_factor(dt, 0, TAU_EPISODE);
    assert abs(f - exp(-1.0)) < 1e-9;   # dt == tau -> e^-1
}

test "access count lengthens the time-constant exactly" {
    dt = 36.0 * 3600.0;
    f = decay_factor(dt, 5, TAU_EPISODE);
    eff = TAU_EPISODE * (1.0 + log(6.0));
    assert abs(f - exp(-dt / eff)) < 1e-9;
}

test "no forward decay for non-positive dt" {
    assert decay_factor(0.0, 0, TAU_EPISODE) == 1.0;
    assert decay_factor(-100.0, 3, TAU_EPISODE) == 1.0;
}
