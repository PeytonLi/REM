"""
Synthetic wearable health-monitor data generator for nursing-home patients.

Two granularities, matching how real wearables actually report:

  1. REALTIME (per-second): heart rate, SpO2, respiration rate, body
     temperature, accelerometer magnitude, and fall detection.
  2. DAILY (per-day): mobility/activity level and sleep quality — these
     often decline gradually in the days BEFORE an acute event, which is
     the "slow burn" story your persistent-memory / handoff system is
     meant to catch that a single-shift nurse would miss.

Usage:
    python generate_vitals.py realtime --event desaturation --out vitals.csv --plot
    python generate_vitals.py realtime --event bradycardia --fall --out vitals.csv
    python generate_vitals.py realtime --event fever --out vitals.csv
    python generate_vitals.py daily --days 7 --out daily_trend.csv
"""

import argparse
import numpy as np
import pandas as pd


# ---------------------------------------------------------------------------
# Real-time vitals: HR, SpO2, respiration, temperature, accel/fall event
# ---------------------------------------------------------------------------


def generate_vitals(
    duration_s=120,
    sample_rate_hz=1,
    event_start_s=20,
    decline_duration_s=30,
    event_type="desaturation",
    include_fall=False,
    fall_time_s=None,
    seed=None,
):
    if seed is not None:
        np.random.seed(seed)

    n = duration_s * sample_rate_hz
    t = np.arange(n) / sample_rate_hz

    hr_baseline, spo2_baseline = 75.0, 97.0
    rr_baseline, temp_baseline = 16.0, 36.8  # breaths/min, deg C

    hr = np.full(n, hr_baseline)
    spo2 = np.full(n, spo2_baseline)
    rr = np.full(n, rr_baseline)
    temp = np.full(n, temp_baseline)

    progress = np.clip((t - event_start_s) / decline_duration_s, 0.0, 1.0)

    if event_type == "desaturation":
        lower_bound = 85.0
        spo2 = spo2_baseline - progress * (spo2_baseline - lower_bound)
        hr = hr_baseline + progress * 15
        rr = rr_baseline + progress * 10  # tachypnea, compensating
    elif event_type == "bradycardia":
        lower_bound = 40.0
        hr = hr_baseline - progress * (hr_baseline - lower_bound)
        spo2 = spo2_baseline - progress * 5
        rr = rr_baseline - progress * 4
    elif event_type == "fever":
        temp = temp_baseline + progress * 2.4  # up to ~39.2C
        hr = hr_baseline + progress * 20
        rr = rr_baseline + progress * 6
    else:
        raise ValueError("event_type must be 'desaturation', 'bradycardia', or 'fever'")

    hr = np.clip(hr + np.random.normal(0, 1.5, n), 30, 180)
    spo2 = np.clip(spo2 + np.random.normal(0, 0.5, n), 70, 100)
    rr = np.clip(rr + np.random.normal(0, 0.8, n), 6, 40)
    temp = np.clip(temp + np.random.normal(0, 0.1, n), 34, 41)

    # accelerometer: resting ~1g with jitter; fall = brief impact spike + stillness after
    fall_flag = np.zeros(n, dtype=bool)
    accel_g = np.random.normal(1.0, 0.05, n)
    if include_fall:
        fall_time_s = fall_time_s if fall_time_s is not None else event_start_s // 2
        fall_idx = int(fall_time_s * sample_rate_hz)
        if 0 <= fall_idx < n:
            accel_g[fall_idx] = np.random.uniform(3.5, 5.0)
            fall_flag[fall_idx] = True
            accel_g[fall_idx + 1 :] = np.random.normal(
                0.98, 0.01, max(0, n - fall_idx - 1)
            )

    df = pd.DataFrame(
        {
            "time_s": t,
            "heart_rate_bpm": hr.round(1),
            "spo2_pct": spo2.round(1),
            "resp_rate_bpm": rr.round(1),
            "body_temp_c": temp.round(2),
            "accel_g": accel_g.round(2),
            "fall_detected": fall_flag,
        }
    )

    df["alert_spo2_low"] = df["spo2_pct"] < 90
    df["alert_hr_abnormal"] = (df["heart_rate_bpm"] < 50) | (df["heart_rate_bpm"] > 120)
    df["alert_resp_abnormal"] = (df["resp_rate_bpm"] < 10) | (df["resp_rate_bpm"] > 24)
    df["alert_fever"] = df["body_temp_c"] > 38.0
    df["alert_fall"] = df["fall_detected"]
    return df


# ---------------------------------------------------------------------------
# Daily trend: mobility (steps) and sleep quality, declining gradually
# ---------------------------------------------------------------------------


def generate_daily_trend(days=7, decline_start_day=None, seed=None):
    if seed is not None:
        np.random.seed(seed)

    decline_start_day = (
        decline_start_day if decline_start_day is not None else days // 2
    )
    day = np.arange(days)

    steps_baseline = 2500  # typical light daily steps, elderly resident
    sleep_hours_baseline = 7.0
    sleep_quality_baseline = 80.0  # 0-100 score

    progress = np.clip(
        (day - decline_start_day) / max(1, (days - decline_start_day)), 0, 1
    )

    steps = steps_baseline - progress * (steps_baseline * 0.6)
    sleep_hours = sleep_hours_baseline - progress * 2.5
    sleep_quality = sleep_quality_baseline - progress * 35

    steps = np.clip(steps + np.random.normal(0, 100, days), 0, None)
    sleep_hours = np.clip(sleep_hours + np.random.normal(0, 0.3, days), 0, 12)
    sleep_quality = np.clip(sleep_quality + np.random.normal(0, 3, days), 0, 100)

    df = pd.DataFrame(
        {
            "day": day,
            "steps": steps.round(0).astype(int),
            "sleep_hours": sleep_hours.round(1),
            "sleep_quality_score": sleep_quality.round(0).astype(int),
        }
    )
    df["alert_low_mobility"] = df["steps"] < steps_baseline * 0.5
    df["alert_poor_sleep"] = df["sleep_quality_score"] < 60
    return df


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="mode", required=True)

    rt = sub.add_parser("realtime", help="generate per-second vitals stream")
    rt.add_argument("--duration", type=int, default=120)
    rt.add_argument("--event-start", type=int, default=20)
    rt.add_argument("--decline", type=int, default=30)
    rt.add_argument(
        "--event",
        choices=["desaturation", "bradycardia", "fever"],
        default="desaturation",
    )
    rt.add_argument("--fall", action="store_true", help="inject a fall event")
    rt.add_argument("--fall-time", type=int, default=None)
    rt.add_argument("--out", default="vitals.csv")
    rt.add_argument("--seed", type=int, default=None)
    rt.add_argument("--plot", action="store_true")

    dt = sub.add_parser("daily", help="generate day-level mobility/sleep trend")
    dt.add_argument("--days", type=int, default=7)
    dt.add_argument("--decline-start-day", type=int, default=None)
    dt.add_argument("--out", default="daily_trend.csv")
    dt.add_argument("--seed", type=int, default=None)

    args = p.parse_args()

    if args.mode == "realtime":
        df = generate_vitals(
            duration_s=args.duration,
            event_start_s=args.event_start,
            decline_duration_s=args.decline,
            event_type=args.event,
            include_fall=args.fall,
            fall_time_s=args.fall_time,
            seed=args.seed,
        )
        df.to_csv(args.out, index=False)
        print(f"wrote {len(df)} rows to {args.out}")
        if args.plot:
            import matplotlib.pyplot as plt

            fig, axes = plt.subplots(4, 1, figsize=(9, 10), sharex=True)
            axes[0].plot(df["time_s"], df["heart_rate_bpm"], color="tab:red")
            axes[0].set_ylabel("HR (bpm)")
            axes[1].plot(df["time_s"], df["spo2_pct"], color="tab:blue")
            axes[1].set_ylabel("SpO2 (%)")
            axes[2].plot(df["time_s"], df["resp_rate_bpm"], color="tab:green")
            axes[2].set_ylabel("Resp (bpm)")
            axes[3].plot(df["time_s"], df["body_temp_c"], color="tab:orange")
            axes[3].set_ylabel("Temp (C)")
            axes[3].set_xlabel("time (s)")
            for ax in axes:
                ax.axvline(args.event_start, color="gray", linestyle="--", linewidth=1)
            plt.suptitle(f"Synthetic vitals -- {args.event} event")
            fig.tight_layout()
            png_path = args.out.rsplit(".", 1)[0] + ".png"
            fig.savefig(png_path, dpi=150)
            print(f"wrote plot to {png_path}")

    elif args.mode == "daily":
        df = generate_daily_trend(
            days=args.days, decline_start_day=args.decline_start_day, seed=args.seed
        )
        df.to_csv(args.out, index=False)
        print(f"wrote {len(df)} rows to {args.out}")
        print(df)
