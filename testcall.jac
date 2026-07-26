"""Place ONE real escalation call, to prove the telephony path end to end.

    jac run testcall.jac

Deliberately bypasses the graph and the Escalate walker: this tests only
ElevenLabs -> SignalWire -> a handset. If this works and the demo still fails,
the fault is in the graph, not the phone line -- which is exactly the split you
want to know at hour 22.

Dials REM_DEMO_PHONE from .env. Costs one call off the ElevenLabs monthly
allowance, so do not leave it in a loop.

What to check when it rings (PRD §8):
  1. It rings at all                 -> SignalWire accepts outbound from the trunk
  2. The agent speaks the FINDING,
     not a generic greeting          -> the {{finding_script}} wiring is right
  3. Read the request back properly  -> should come back acknowledged, readback=True
  4. Run it again and say only
     "okay"                          -> should come back readback=False.
                                        A bare acknowledgement is not a read-back,
                                        and Escalate must keep climbing.
"""

import os;
import from adapters.voice { place_call }

# The primary demo call from PRD §8, script A -- same shape escalate.jac's
# script_for() builds from a Clinical node.
glob FALL_SCRIPT: str =
    "This is the handoff assistant calling about Ruth Alvarez, Room 3B. "
    "The wearable detected a fall at 3:05 AM with no movement for the "
    "following two minutes, and no room check has been logged yet. "
    "Requesting an immediate check. Can you read back the request?";


with entry:__main__ {
    phone = os.getenv("REM_DEMO_PHONE");
    if not phone {
        print("REM_DEMO_PHONE is not set in .env -- nothing to dial.");
    } else {
        print(f"dialing {phone} ... (answer it)");
        result = place_call(phone, FALL_SCRIPT);
        print("");
        print(f"  acknowledged : {result.acknowledged}");
        print(f"  readback     : {result.readback}");
        print(f"  transcript   : {result.transcript}");
        print("");
        if result.transcript.startswith("[on-screen notification") {
            print("DEGRADED -- no real call was placed. Check the reason above:");
            print("  'telephony not configured' -> a var is missing from .env");
            print("  'call not placed'          -> ElevenLabs rejected it (trunk/agent)");
            print("  'call did not complete'    -> it dialed but never connected");
        } elif result.acknowledged {
            print("Live call answered. Telephony path is good.");
        } else {
            print("Call completed but nobody spoke -- treated as unacknowledged,");
            print("which is what makes Escalate climb to the next clinician.");
        }
    }
}
