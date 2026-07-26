"""Ingest: device + transcript (WORKPLAN B3, PRD 6.2a / 9.1-9.2 / 9.4).

Two walkers, one LLM formatting function. Both walkers do exactly one thing:
turn a row from a new modality into a plain `Episode` node hung off the
`Handoff` entry node. No new node type, no second consolidation path -- the
architectural point of 6.2a and 9.2 is that absorbing wearable data and
absorbing speech cost nothing beyond a formatting adapter.

`IngestTranscript` takes `list[Segment]` (contracts.jac) that some other task
(the Deepgram adapter) is responsible for producing -- this file does not
build that client.
"""

import json;
import from jaclang.byllm.lib { Model, MockLLM }
import from schema { Episode, Handoff }
import from contracts { Segment }

# Cheap/cost-routed model for the one formatting call this file makes (PRD
# 10.4: flat structs/classification go to the cheap model; only the nested
# SBARPlus composition -- not our concern here -- gets the stronger one).
glob cheap: Model = Model(model_name="deepseek/deepseek-chat");

def format_wearable_episode(row: dict, metric: str) -> str by cheap();
sem format_wearable_episode =
    "Turn one wearable/device reading into a single short natural-language "
    "clinical episode note, in the style of a nursing charting entry. "
    "Examples: 'SpO2 dropped to 84% (03:20)', 'Fall detected via "
    "accelerometer, no movement for 2 min (02:14)', 'Mobility: 1,180 steps "
    "today, down from a ~2,500 baseline', 'Sleep quality score 42/100, down "
    "from a ~80 baseline'. Derive the clock time shown in parentheses from "
    "the row's unix timestamp (local time, HH:MM, 24h). Use value/unit "
    "for the headline number, and baseline when present for comparison. "
    "One sentence, no preamble, no markdown.";
sem format_wearable_episode.row =
    "The raw device reading. Keys always include metric, source, device_id, "
    "timestamp, value, unit, tag; sometimes baseline, note, heart_rate_bpm, "
    "resp_rate_bpm (vitals rows), or stillness_after_s (fall rows).";
sem format_wearable_episode.metric =
    "Which metric this reading is: spo2, fall, mobility, or sleep.";

walker:pub IngestDevice {
    """Maps device readings -> plain Episode nodes. PRD 6.2a."""
    has readings: list[dict];
    has reports: list[Episode] = [];

    can absorb with Handoff entry {
        for r in self.readings {
            metric: str = r["metric"] as str;
            ep = here ++> Episode(
                content = format_wearable_episode(r, metric),
                source  = r["source"] as str,       # wearable_vitals / _fall / _mobility / _sleep
                author  = r["device_id"] as str,
                at      = r["timestamp"] as float
            );
            report ep;
        }
    }
}

walker:pub IngestTranscript {
    """Maps diarized transcript segments -> plain Episode nodes. PRD 9.2."""
    has segments: list[Segment];
    has reports: list[Episode] = [];

    can absorb with Handoff entry {
        for seg in self.segments {
            ep = here ++> Episode(
                content = seg.text,
                source  = "verbal_handoff",
                author  = seg.speaker,
                at      = seg.start
            );
            report ep;
        }
    }
}

with entry:__main__ {
    # MockLLM so the self-check needs no API key and no network (jac-by-llm).
    cheap = MockLLM(
        model_name="mockllm",
        config={"outputs": ["mock formatted episode"] * 20}
    ) as Model;

    with open("seed/device_readings.json") as f {
        rows: list[dict] = json.load(f);
    }
    assert len(rows) == 14, f"expected 14 seed device readings, got {len(rows)}";

    hoff = root ++> Handoff(shift="self-check");
    device_result = hoff spawn IngestDevice(readings=rows);

    # 3. Ingesting all 14 seed rows yields exactly 14 episodes.
    assert len(device_result.reports) == 14, (
        f"expected 14 device episodes, got {len(device_result.reports)}"
    );

    # 2. A wearable_fall row yields exactly one episode with source == "wearable_fall".
    fall_episodes = [e for e in device_result.reports if e.source == "wearable_fall"];
    assert len(fall_episodes) == 1, (
        f"expected exactly 1 wearable_fall episode, got {len(fall_episodes)}"
    );

    segs: list[Segment] = [
        Segment(text="Room 3B, day five.", speaker="RN Maya Ortiz", start=0.0),
        Segment(text="Copy, thanks.", speaker="RN Dev Patel", start=4.0)
    ];
    hoff2 = root ++> Handoff(shift="self-check-verbal");
    verbal_result = hoff2 spawn IngestTranscript(segments=segs);
    assert len(verbal_result.reports) == 2, (
        f"expected 2 verbal episodes, got {len(verbal_result.reports)}"
    );

    # 1. Every produced Episode (device OR verbal) has a non-empty author --
    # provenance needs an author; an unattributed episode breaks the trust model.
    all_episodes = device_result.reports + verbal_result.reports;
    for e in all_episodes {
        assert e.author, f"episode with source={e.source} has empty author";
    }

    print(
        f"ingest self-check OK: {len(device_result.reports)} device episodes "
        f"(1 fall), {len(verbal_result.reports)} verbal episodes, all authored"
    );
}
