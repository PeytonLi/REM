"""omission.test.jac -- annex to omission.jac (jac-testing: <mod>.test.jac).
Run: jac test omission.jac

Self-check required by handoff-B B5:
  1. Obligation set comes from the graph query, not the model -- calling
     required_findings() costs zero LLM calls and is always the same 3.
  2. A transcript that mentions 1 of 3 required claims leaves the panel
     listing exactly 2, using MockLLM so no API key is needed.
"""

import from jaclang.byllm.lib { MockLLM }

test "obligation set comes from the graph query, not the model" {
    # No `cheap` reassignment here at all -- if this test needed a queued
    # MockLLM output to pass, required_findings() would have quietly
    # started asking a model what's required, which is the exact inversion
    # this design forbids.
    findings = required_findings();
    assert len(findings) == 3;

    claims_text = " ".join([f.claim for f in findings]);
    assert "rash" in claims_text;
    assert "desaturation" in claims_text;
    assert "fall" in claims_text;
}

test "transcript mentioning 1 of 3 required claims leaves exactly 2 not conveyed" {
    cheap = MockLLM(model_name="mockllm", config={"outputs": [True, False, False]});

    transcript = "She's still on the alternative antibiotic because of that rash she had on day one.";
    missed = not_conveyed_claims(transcript);

    assert len(missed) == 2;
    missed_text = " ".join([m.claim for m in missed]);
    assert "rash" not in missed_text;
    assert "desaturation" in missed_text;
    assert "fall" in missed_text;
}

test "OmissionPanel walker reports the same not-conveyed list" {
    cheap = MockLLM(model_name="mockllm", config={"outputs": [True, False, False]});

    transcript = "She's still on the alternative antibiotic because of that rash she had on day one.";
    result = root spawn OmissionPanel(transcript=transcript);

    assert len(result.reports) == 1;
    assert len(result.reports[0]) == 2;
}
