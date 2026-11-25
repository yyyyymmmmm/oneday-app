#!/usr/bin/env python3
"""§261 permission-flow convergence checks (in-process).

Covers what the live selftest cannot reach without a 120s
wait: the ask-timeout branch must record askOutcome=
unanswered on the park (not silently fold into 'parked'),
a user deferral records deferred, and the ask payload
carries the park's own createdAt/expiresAt stamps.
Run: python3 permission_flow_261_test.py
"""
import os
import sys
import tempfile
import threading
import time

os.environ["DATA_DIR"] = tempfile.mkdtemp(prefix="parks-")
os.environ.setdefault("DEVICE_BRIDGE_KEY", "test-key")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "modules"))

import device_bridge as db

FAILURES = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name +
          (f"  [{detail}]" if detail else ""), flush=True)
    if not cond:
        FAILURES.append(name)


db.ASK_TIMEOUT = 0.3
db._session = {"sessionId": "sess-261"}

# --- timeout => unanswered -------------------------------------
tok_a = db._park_call("location_current", {}, "location", "permission")
result = db._ask_permission("location", "location_current", tok_a)
park = db._peek_park(tok_a) or {}
check("timeout: ask returns parked", result == "parked", result)
check("timeout: park records askOutcome=unanswered",
      park.get("askOutcome") == "unanswered", str(park.get("askOutcome")))

# --- stamps ride the ask payload --------------------------------
tok_b = db._park_call("location_current", {}, "location", "permission")
holder = {}


def run_ask():
    holder["result"] = db._ask_permission(
        "location", "location_current", tok_b)


t = threading.Thread(target=run_ask, daemon=True)
t.start()
rec = None
for _ in range(100):
    with db._cond:
        for r in db._pending.values():
            if r["tool"] == db.PERMISSION_ASK_TOOL and \
                    r["arguments"].get("resumeToken") == tok_b:
                rec = r
    if rec is not None:
        break
    time.sleep(0.02)
check("payload: ask record delivered", rec is not None)
args = (rec or {}).get("arguments") or {}
park_b = db._peek_park(tok_b) or {}
check("payload: parkedAt/expiresAt match the park stamps",
      args.get("parkedAt") == park_b.get("createdAt")
      and args.get("expiresAt") == park_b.get("expiresAt"),
      str(args))
if rec is not None:
    rec["response"] = {"status": "ok", "result": {"decision": "parked"}}
    rec["event"].set()
t.join(timeout=5)
park_b = db._peek_park(tok_b) or {}
check("deferred: user 'later' records askOutcome=deferred",
      holder.get("result") == "parked"
      and park_b.get("askOutcome") == "deferred",
      str(park_b.get("askOutcome")))

# --- fields surface stamps + outcome ----------------------------
fields = db._permission_fields("location", "notDetermined",
                               "permission", "ask_in_chat", tok_b)
check("fields: parkedAt/expiresAt/askOutcome surfaced",
      fields.get("parkedAt") == park_b.get("createdAt")
      and fields.get("expiresAt") == park_b.get("expiresAt")
      and fields.get("askOutcome") == "deferred", str(fields))

print(f"\n{'ALL GREEN' if not FAILURES else 'FAILURES: ' + str(FAILURES)}")
sys.exit(1 if FAILURES else 0)
