"""Wearable episodes for the REM demo graph.

Wraps datasets/generate_vitals.py. The raw stream is per-second; the graph does
NOT want 120 episodes per event. This extracts one episode per clinical EVENT
(a desaturation nadir, a fall, a day's mobility/sleep) and leaves the raw CSVs
on disk for the device dashboard to plot.

Emits:
  seed/device/*.csv            - raw traces, for the B4 dashboard
  seed/device_readings.json    - list[dict] in the shape IngestDevice consumes

Run:
  python seed/device.py
  python seed/device.py --self-check
"""

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "datasets"))
from generate_vitals import generate_daily_trend, generate_vitals  # noqa: E402

sys.path.insert(0, str(ROOT / "seed"))
from gen import ts  # noqa: E402  -- shared clock, so device and manual line up

OUT_DIR = Path(__file__).parent
CSV_DIR = OUT_DIR / "device"
DEVICE_ID = "wearable-3B-014"
FALL_THRESHOLD_G = 2.5  # impact spike above this reads as a fall; jitter stays below

# (label, day the night shift started, hh, mm) -- matches P-DESAT-N*-NOTE in gen.py
DESAT_EVENTS = [("n1", 1, 2, 15), ("n2", 2, 1, 50), ("n3", 3, 3, 25)]
FALL_EVENT = (4, 3, 5)  # D4-night, 03:05 on calendar day 5


def _event_row(df, col, how):
    idx = df[col].idxmin() if how == "min" else df[col].idxmax()
    return df.loc[idx]


def realtime_events():
    """One episode per desaturation nadir, plus the fall. Raw CSVs saved alongside."""
    readings = []
    for i, (label, day, hh, mm) in enumerate(DESAT_EVENTS):
        df = generate_vitals(event_type="desaturation", seed=100 + i)
        df.to_csv(CSV_DIR / f"desat_{label}.csv", index=False)
        row = _event_row(df, "spo2_pct", "min")
        readings.append({
            "metric": "spo2",
            "source": "wearable_vitals",
            "device_id": DEVICE_ID,
            "timestamp": ts(day + 1, hh, mm),
            "value": float(row["spo2_pct"]),
            "unit": "%",
            "heart_rate_bpm": float(row["heart_rate_bpm"]),
            "resp_rate_bpm": float(row["resp_rate_bpm"]),
            "tag": "planted",
        })

    day, hh, mm = FALL_EVENT
    df = generate_vitals(event_type="desaturation", include_fall=True,
                         fall_time_s=10, seed=200)
    # A sub-threshold jitter spike, deliberately NOT flagged: the R6 decoy.
    jitter_idx = len(df) - 20
    df.loc[jitter_idx, "accel_g"] = 1.8
    df.to_csv(CSV_DIR / "fall_n4.csv", index=False)

    fall_rows = df[df["fall_detected"]]
    assert len(fall_rows) == 1, "generator must produce exactly one flagged fall"
    row = fall_rows.iloc[0]
    readings.append({
        "metric": "fall",
        "source": "wearable_fall",
        "device_id": DEVICE_ID,
        "timestamp": ts(day + 1, hh, mm),
        "value": float(row["accel_g"]),
        "unit": "g",
        "stillness_after_s": 120,
        "tag": "planted",
    })
    return readings


def daily_events():
    """Per-day mobility and sleep. Day 1 is a scheduled-outing low-step decoy."""
    df = generate_daily_trend(days=5, decline_start_day=1, seed=42)
    df.loc[0, "steps"] = 920           # off-unit family outing, not decline
    df.loc[0, "sleep_quality_score"] = 78
    df.loc[0, "alert_low_mobility"] = True
    df.to_csv(CSV_DIR / "daily_trend.csv", index=False)

    readings = []
    for _, r in df.iterrows():
        day = int(r["day"]) + 1
        outing = day == 1
        readings.append({
            "metric": "mobility", "source": "wearable_mobility",
            "device_id": DEVICE_ID, "timestamp": ts(day, 23, 30),
            "value": int(r["steps"]), "unit": "steps", "baseline": 2500,
            "tag": "decoy" if outing else "planted",
            **({"note": "R5 decoy: isolated low-step day, scheduled outing, not decline"}
               if outing else {}),
        })
        readings.append({
            "metric": "sleep", "source": "wearable_sleep",
            "device_id": DEVICE_ID, "timestamp": ts(day, 23, 45),
            "value": int(r["sleep_quality_score"]), "unit": "score_0_100",
            "baseline": 80, "tag": "planted",
        })
    return readings


def build():
    CSV_DIR.mkdir(parents=True, exist_ok=True)
    readings = realtime_events() + daily_events()
    readings.sort(key=lambda r: r["timestamp"])
    return readings


def self_check(readings):
    desat = [r for r in readings if r["metric"] == "spo2"]
    falls = [r for r in readings if r["source"] == "wearable_fall"]
    mob = sorted((r for r in readings if r["metric"] == "mobility"),
                 key=lambda r: r["timestamp"])
    sleep = sorted((r for r in readings if r["metric"] == "sleep"),
                   key=lambda r: r["timestamp"])

    assert len(desat) == 3, f"need exactly 3 desaturation events, got {len(desat)}"
    assert all(r["value"] < 90 for r in desat), "a desaturation must read below 90%"

    # R6: exactly one fall, and the jitter spike must not have become a second one.
    assert len(falls) == 1, f"need exactly one fall episode, got {len(falls)}"
    assert falls[0]["value"] > FALL_THRESHOLD_G, "fall impact must clear the threshold"
    trace = pd.read_csv(CSV_DIR / "fall_n4.csv")
    unflagged_peak = trace.loc[~trace["fall_detected"], "accel_g"].max()
    assert unflagged_peak < FALL_THRESHOLD_G, (
        f"unflagged accel peak {unflagged_peak}g would read as a fall")

    # R5: mobility and sleep decline for >=3 consecutive days, ignoring the outing day.
    trend = [r["value"] for r in mob[1:]]
    assert all(a > b for a, b in zip(trend, trend[1:])), f"mobility must decline: {trend}"
    sl = [r["value"] for r in sleep[1:]]
    assert all(a > b for a, b in zip(sl, sl[1:])), f"sleep must decline: {sl}"
    assert len(trend) >= 3, "R5 needs at least 3 consecutive declining days"

    # The outing day must not extend the decline: day 1 is BELOW day 2.
    assert mob[0]["value"] < mob[1]["value"], "outing day must break, not extend, the trend"
    assert mob[0]["tag"] == "decoy"

    # The fall comes after the decline it was supposed to be preceded by.
    assert falls[0]["timestamp"] > mob[-2]["timestamp"], "fall must follow the decline"

    for r in readings:
        assert r["device_id"] and r["source"].startswith("wearable")
        assert r["timestamp"] > 0
    print(f"self-check OK: {len(readings)} device readings "
          f"({len(desat)} desat, {len(falls)} fall, {len(mob)} mobility, {len(sleep)} sleep)")
    print(f"  mobility trace: {[r['value'] for r in mob]}  (day 1 = outing decoy)")
    print(f"  sleep trace:    {[r['value'] for r in sleep]}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--self-check", action="store_true")
    args = p.parse_args()

    rs = build()
    self_check(rs)
    if not args.self_check:
        (OUT_DIR / "device_readings.json").write_text(json.dumps(rs, indent=1))
        print(f"wrote {OUT_DIR/'device_readings.json'} and {CSV_DIR}/*.csv")
