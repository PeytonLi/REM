"""Imitate a patient fall and page the on-call nurse. Python twin of testcall.jac.

    python fallcall.py                  # replay the committed fall -> real call
    python fallcall.py --now            # stamp it as happening right now
    python fallcall.py --to +1555...    # dial someone else
    python fallcall.py --self-check     # no dialing, asserts detection + script

The fall is a REPLAY of the wearable event the graph ingests
(seed/device_readings.json, produced by seed/device.py), re-checked against the
same accelerometer threshold, so the words the nurse hears match what the demo
shows on screen. The wording mirrors escalate.jac's script_for().

Bypasses the graph and the Escalate walker on purpose -- same split testcall.jac
draws: if this rings and the demo still fails, the fault is in the graph, not the
phone line. Escalate is what climbs CNA -> RN -> charge -> MD; this dials one
number. Read-back judgement also stays in Jac (readback_ok, adapters/voice.jac);
here the human's turns are printed for you to judge.

Costs one call off the ElevenLabs allowance. Do not put it in a loop.
"""

import argparse
import json
import os
import time
from pathlib import Path

import requests

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass  # real env vars still work

ROOT = Path(__file__).resolve().parent
READINGS = ROOT / "seed" / "device_readings.json"

# Duplicated from seed/device.py rather than imported: that module pulls pandas
# and the vitals generator at import time, and this script must run anywhere.
FALL_THRESHOLD_G = 2.5

PATIENT = "Harold Alvarez"
ROOM = "3B"
CALL_TIMEOUT_S = 200.0  # bridge blocks up to 150s for ring + talk + wrap


def fall_event(now: bool = False) -> dict:
    """The wearable fall from the device stream, re-checked against the threshold."""
    rows = json.loads(READINGS.read_text())
    falls = [
        r
        for r in rows
        if r["source"] == "wearable_fall" and r["value"] > FALL_THRESHOLD_G
    ]
    if not falls:
        raise SystemExit(f"no fall above {FALL_THRESHOLD_G}g in {READINGS}")
    ev = dict(falls[0])
    if now:
        ev["timestamp"] = time.time()
    return ev


def clock_of(timestamp: float) -> str:
    """Wall clock of the event, 12h. UTC: seed/gen.py anchors the demo day to UTC."""
    t = time.gmtime(timestamp)
    return f"{t.tm_hour % 12 or 12}:{t.tm_min:02d} {'AM' if t.tm_hour < 12 else 'PM'}"


def stillness_of(seconds: int) -> str:
    if seconds < 60:
        return f"{seconds} seconds"
    mins = seconds // 60
    return f"{mins} minute" + ("s" if mins != 1 else "")


def script_for(ev: dict, patient: str = PATIENT, room: str = ROOM) -> str:
    """The words the agent speaks. Deterministic, no LLM -- same rule as escalate.jac."""
    return (
        f"This is the handoff assistant calling about {patient}, Room {room}. "
        f"The wearable detected a fall at {clock_of(ev['timestamp'])}, "
        f"a {ev['value']} g impact, with no movement for the following "
        f"{stillness_of(ev.get('stillness_after_s', 0))}, and no room check has "
        "been logged yet. Requesting an immediate check. "
        "Can you read back the request?"
    )


def context_for(ev: dict, patient: str = PATIENT, room: str = ROOM) -> str:
    """The bounded fact set the agent may quote if the nurse asks a question.

    Same idea as escalate.jac::context_for(): every line is data the fall event
    already carries, so "which patient was this?" and "what time was it?" get
    answered without the model inventing anything. Anything outside these lines
    still gets "I only have the finding I just read."
    """
    return "\n".join(
        [
            f"Resident: {patient}, Room {room}.",
            "Finding: unwitnessed fall detected by the wearable, no room check "
            "logged yet.",
            "Category: fall.",
            f"Detected at: {clock_of(ev['timestamp'])} (UTC).",
            f"Impact: {ev['value']} {ev['unit']}, threshold {FALL_THRESHOLD_G} g.",
            f"Stillness after the impact: {stillness_of(ev.get('stillness_after_s', 0))}.",
            f"Evidence: {ev['source']} recorded by device {ev['device_id']}.",
            "Room check logged since the fall: none.",
        ]
    )


def page(phone: str, script: str, context: str = "") -> dict:
    """Place the call through the bridge. Degrades to an on-screen notification.

    Never reports an acknowledgment it did not receive -- an unplaced call is
    exactly what makes Escalate climb to the next clinician (PRD 10.5).
    """
    bridge = os.getenv("BRIDGE_URL")
    if not bridge:
        print(f"\n*** ESCALATION (telephony not configured) -> {phone} ***\n{script}\n")
        return {"answered": False, "turns": []}
    r = requests.post(
        f"{bridge.rstrip('/')}/call",
        json={"to": phone, "script": script, "context": context},
        timeout=CALL_TIMEOUT_S,
    )
    r.raise_for_status()
    return r.json()


def self_check() -> None:
    ev = fall_event()
    assert ev["value"] > FALL_THRESHOLD_G, "replayed event must clear the threshold"
    assert ev["stillness_after_s"] > 0, "a fall needs a stillness window"

    s = script_for(ev)
    assert "read back" in s, "the script must ask for a read-back"
    assert clock_of(ev["timestamp"]) in s, "the script must carry the event's clock time"
    assert ROOM in s and PATIENT in s, "the script must identify patient and room"
    assert s == script_for(ev), "script must be deterministic"

    assert stillness_of(120) == "2 minutes" and stillness_of(45) == "45 seconds"
    assert stillness_of(60) == "1 minute"

    # The two questions the nurse actually asked on the live call must be
    # answerable from the facts alone.
    facts = context_for(ev)
    assert PATIENT in facts and ROOM in facts, "'which patient?' must be answerable"
    assert clock_of(ev["timestamp"]) in facts, "'what time?' must be answerable"
    assert facts == context_for(ev), "facts must be deterministic"

    # Unconfigured telephony must not fake an answer.
    saved = os.environ.pop("BRIDGE_URL", None)
    try:
        assert not page("+15555550123", s, facts)["answered"], (
            "unplaced call is not answered"
        )
    finally:
        if saved is not None:
            os.environ["BRIDGE_URL"] = saved

    print(f"self-check OK\n\n{s}\n\nCASE FACTS the agent may quote:\n{facts}\n")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--to", help="override the number (default: the on-call nurse)")
    p.add_argument("--now", action="store_true", help="stamp the fall as happening now")
    p.add_argument("--self-check", action="store_true", help="no call, just assertions")
    args = p.parse_args()

    if args.self_check:
        self_check()
        raise SystemExit(0)

    phone = args.to or os.getenv("REM_DEMO_PHONE_RN") or os.getenv("REM_DEMO_PHONE")
    if not phone:
        raise SystemExit(
            "no number: set REM_DEMO_PHONE_RN (or REM_DEMO_PHONE) in .env, or pass --to"
        )

    ev = fall_event(now=args.now)
    script = script_for(ev)
    print(
        f"FALL DETECTED  {ev['value']} g > {FALL_THRESHOLD_G} g threshold  "
        f"({ev['device_id']}, {clock_of(ev['timestamp'])})"
    )
    print(f"paging on-call nurse at {phone} ... (answer it)\n{script}\n")

    result = page(phone, script, context_for(ev))
    turns = [t["message"] for t in result.get("turns") or [] if t.get("message")]

    print(f"  answered   : {result.get('answered')}")
    print(f"  timed out  : {result.get('timedOut', False)}")
    print(f"  error      : {result.get('error')}")
    for t in turns:
        print(f"  nurse said : {t}")
    print()
    if turns:
        print("Did those words restate the request? That -- not a bare 'okay' -- is")
        print("what readback_ok() in adapters/voice.jac requires to stop the climb.")
    else:
        print("Nobody spoke: unacknowledged, which is what makes Escalate climb")
        print("to the charge nurse and then the on-call MD.")
