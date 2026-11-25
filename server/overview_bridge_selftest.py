#!/usr/bin/env python3
"""Self-test for overview_bridge.py refId pass-through (OneDay 0.36.5).

Subprocess bridge on temp ledgers: first boot baselines both
(empty) ledgers, then decision/monitor lines appended afterwards
must surface as notifications where write_gate_decision items
carry refId = the decisions entry's record id (the App's
auto-resolve linkage key), an empty/missing id degrades to null,
and monitor items carry refId null.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "overview_bridge.py")
KEY = "overview-selftest-key"
PORT = 18748
BASE = f"http://127.0.0.1:{PORT}"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def call(method, path, key=KEY):
    req = urllib.request.Request(BASE + path, method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, {}
    except urllib.error.URLError:
        return 0, {}


def wait_notifications(want, timeout=20):
    deadline = time.time() + timeout
    items = []
    while time.time() < deadline:
        status, data = call("GET", "/notifications")
        if status == 200:
            items = data.get("items", [])
            if len(items) >= want:
                return items
        time.sleep(0.7)
    return items


def main():
    tmp = tempfile.mkdtemp(prefix="overview-selftest-")
    decisions = os.path.join(tmp, "decisions.jsonl")
    monitor = os.path.join(tmp, "monitor.jsonl")
    state_dir = os.path.join(tmp, "state")
    open(decisions, "w").close()
    env = dict(os.environ)
    env.update({
        "OVERVIEW_BRIDGE_KEY": KEY,
        "OVERVIEW_PORT": str(PORT),
        "DECISIONS_PATH": decisions,
        "MONITOR_PATH": monitor,
        "STATE_DIR": state_dir,
        "HERMES_BASE": "http://127.0.0.1:9",
        "WRITE_GATE_BASE": "http://127.0.0.1:9",
        "WRITE_GATE_BRIDGE_KEY": "unused",
    })
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        # Bridge must answer (401 without key proves it is up).
        up = False
        for _ in range(40):
            status, _ = call("GET", "/notifications", key=None)
            if status == 401:
                up = True
                break
            time.sleep(0.3)
        check("bridge up (401 unauthenticated)", up)
        if not up:
            return

        with open(decisions, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "id": "rec-selftest-1", "subsystem": "memory",
                "action": "write", "summary": "selftest summary",
                "decision": "approved",
                "decided_at": "2026-11-10T00:00:00Z",
            }, ensure_ascii=False) + "\n")
            f.write(json.dumps({
                "id": "", "subsystem": "skills",
                "action": "write", "summary": "",
                "decision": "rejected",
                "decided_at": "2026-11-10T00:01:00Z",
            }, ensure_ascii=False) + "\n")
        with open(monitor, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "id": "mon-selftest-1", "kind": "monitor_change",
                "title": "t", "body": "b",
                "createdAt": "2026-11-10T00:02:00Z",
            }, ensure_ascii=False) + "\n")

        items = wait_notifications(3)
        check("three notifications arrive", len(items) == 3,
              f"got {len(items)}")
        by_kind = {}
        for n in items:
            by_kind.setdefault(n.get("kind"), []).append(n)
        wg = by_kind.get("write_gate_decision", [])
        check("two write_gate_decision items", len(wg) == 2)
        with_ref = [n for n in wg if n.get("refId") == "rec-selftest-1"]
        check("decision carries refId = record id", len(with_ref) == 1,
              f"refIds={[n.get('refId') for n in wg]}")
        null_ref = [n for n in wg if n.get("refId") is None]
        check("empty record id degrades refId to null",
              len(null_ref) == 1)
        mon = by_kind.get("monitor_change", [])
        check("monitor item present", len(mon) == 1)
        check("monitor item refId is null",
              len(mon) == 1 and mon[0].get("refId") is None)

        status, overview = call("GET", "/overview")
        check("overview unread counts all three",
              status == 200
              and overview.get("unreadNotifications") == 3,
              f"{status} {overview.get('unreadNotifications')}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
