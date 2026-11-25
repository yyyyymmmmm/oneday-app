#!/usr/bin/env python3
"""Self-test for overview_bridge.py (B-03 read-time design, 1.0.63).

The bridge no longer tails ledger files: it aggregates at read
time from stub owner modules (write-gate /decisions, oneday
/monitors/notifications). Asserted contract:

- decision rows become write_gate_decision notifications, born
  read (2026-11-11 caliber), refId = the decisions entry's
  record id, an empty/missing id degrades to null;
- monitor records pass through, born unread, and the live
  baseline (monitor_since) keeps pre-live history out;
- POST /notifications/{id}/read persists the mark across a
  reboot (read_ids state); unknown ids 404;
- a legacy pre-1.0.63 state.json migrates: monitor read marks
  carry over, the baseline lands on the oldest stored monitor
  item, and stored decision copies vanish (the owner ledger is
  the single source now);
- a dead owner source degrades to empty, never to a 500.
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "overview_bridge.py")
KEY = "overview-selftest-key"
PORT = 18748
WG_PORT = 18751
ONEDAY_PORT = 18752
BASE = f"http://127.0.0.1:{PORT}"

passed = failed = 0

WG_ROWS = []    # newest-first, as the real /decisions returns
MON_ROWS = []   # newest-first, as the real read surface returns


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


def _stub_handler(rows_key):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            if rows_key == "wg" and self.path.startswith("/status"):
                body = {"counts": {"memory": 0, "skills": 0}}
            elif rows_key == "wg" and self.path.startswith("/decisions"):
                body = {"decisions": WG_ROWS}
            elif rows_key == "mon" and self.path.startswith(
                    "/monitors/notifications"):
                body = {"items": MON_ROWS}
            else:
                self.send_response(404)
                self.end_headers()
                return
            raw = json.dumps(body).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
    return H


def start_stub(port, rows_key):
    srv = ThreadingHTTPServer(("127.0.0.1", port),
                              _stub_handler(rows_key))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def boot(state_dir):
    env = dict(os.environ)
    env.update({
        "OVERVIEW_BRIDGE_KEY": KEY,
        "OVERVIEW_PORT": str(PORT),
        "STATE_DIR": state_dir,
        "HERMES_BASE": "http://127.0.0.1:9",
        "WRITE_GATE_BASE": f"http://127.0.0.1:{WG_PORT}",
        "WRITE_GATE_BRIDGE_KEY": "wg-stub-key",
        "ONEDAY_BASE": f"http://127.0.0.1:{ONEDAY_PORT}",
        "ONEDAY_BRIDGE_KEY": "oneday-stub-key",
    })
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    up = False
    for _ in range(40):
        status, _ = call("GET", "/notifications", key=None)
        if status == 401:
            up = True
            break
        time.sleep(0.3)
    return proc, up


def stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()


def now_iso():
    return datetime.now(tz=timezone.utc).isoformat().replace(
        "+00:00", "Z")


def main():
    tmp = tempfile.mkdtemp(prefix="overview-selftest-")
    state_dir = os.path.join(tmp, "state")
    wg = start_stub(WG_PORT, "wg")
    mon = start_stub(ONEDAY_PORT, "mon")

    # ---- phase 1: read-time aggregation over live stubs --------
    proc, up = boot(state_dir)
    try:
        check("bridge up (401 unauthenticated)", up)
        if not up:
            return
        status, data = call("GET", "/notifications")
        check("empty sources -> empty list",
              status == 200 and data.get("items") == [],
              f"{status} {data}")

        WG_ROWS.extend([
            {"id": "", "subsystem": "skills", "action": "write",
             "summary": "", "decision": "rejected",
             "decided_at": "2026-11-10T00:01:00Z"},
            {"id": "rec-selftest-1", "subsystem": "memory",
             "action": "write", "summary": "selftest summary",
             "decision": "approved",
             "decided_at": "2026-11-10T00:00:00Z"},
        ])
        mon_ts = now_iso()
        MON_ROWS.append({
            "id": "mon-selftest-1", "kind": "monitor_change",
            "title": "t", "body": "b", "createdAt": mon_ts})

        status, data = call("GET", "/notifications")
        items = data.get("items", [])
        check("three notifications aggregate at read time",
              status == 200 and len(items) == 3,
              f"{status} got {len(items)}")
        check("newest first (monitor item leads)",
              len(items) == 3
              and items[0].get("id") == "mon-selftest-1",
              f"{[n.get('id') for n in items]}")
        by_kind = {}
        for n in items:
            by_kind.setdefault(n.get("kind"), []).append(n)
        wgd = by_kind.get("write_gate_decision", [])
        check("two write_gate_decision items", len(wgd) == 2)
        with_ref = [n for n in wgd if n.get("refId") == "rec-selftest-1"]
        check("decision carries refId = record id", len(with_ref) == 1,
              f"refIds={[n.get('refId') for n in wgd]}")
        null_ref = [n for n in wgd if n.get("refId") is None]
        check("empty record id degrades refId to null",
              len(null_ref) == 1)
        check("decision ids derive from the record id",
              len(with_ref) == 1
              and with_ref[0].get("id") == "wg-rec-selftest-1",
              f"{[n.get('id') for n in wgd]}")
        mon_items = by_kind.get("monitor_change", [])
        check("monitor item present, refId null (as recorded)",
              len(mon_items) == 1
              and mon_items[0].get("refId") is None)
        check("decision receipts are born read",
              len(wgd) == 2
              and all(n.get("read") is True for n in wgd),
              f"reads={[n.get('read') for n in wgd]}")
        check("monitor item is born unread",
              len(mon_items) == 1
              and mon_items[0].get("read") is False)

        status, overview = call("GET", "/overview")
        check("overview unread counts only the monitor item",
              status == 200
              and overview.get("unreadNotifications") == 1,
              f"{status} {overview.get('unreadNotifications')}")

        status, _ = call("POST", "/notifications/mon-selftest-1/read")
        check("mark monitor item read -> 200", status == 200,
              f"{status}")
        status, data = call("GET", "/notifications")
        mon_items = [n for n in data.get("items", [])
                     if n.get("id") == "mon-selftest-1"]
        check("monitor item now read",
              len(mon_items) == 1
              and mon_items[0].get("read") is True)
        status, overview = call("GET", "/overview")
        check("overview unread back to 0",
              status == 200
              and overview.get("unreadNotifications") == 0,
              f"{status} {overview.get('unreadNotifications')}")
        status, _ = call("POST", "/notifications/nope-404/read")
        check("mark unknown id -> 404", status == 404, f"{status}")
        status, _ = call(
            "POST", "/notifications/wg-rec-selftest-1/read")
        check("mark decision receipt read -> 200 (born read)",
              status == 200, f"{status}")
    finally:
        stop(proc)

    # ---- phase 2: read mark survives a reboot ------------------
    proc, up = boot(state_dir)
    try:
        check("bridge reboots over slim state", up)
        if up:
            status, data = call("GET", "/notifications")
            mon_items = [n for n in data.get("items", [])
                         if n.get("id") == "mon-selftest-1"]
            check("read mark persisted across reboot",
                  len(mon_items) == 1
                  and mon_items[0].get("read") is True,
                  f"{mon_items}")
            with open(os.path.join(state_dir, "state.json"),
                      encoding="utf-8") as f:
                slim = json.load(f)
            check("state file is slim (read_ids + monitor_since)",
                  "read_ids" in slim and "monitor_since" in slim
                  and "notifications" not in slim
                  and "offset" not in slim,
                  f"keys={sorted(slim)}")
    finally:
        stop(proc)

    # ---- phase 3: legacy state migration -----------------------
    state2 = os.path.join(tmp, "state2")
    os.makedirs(state2)
    with open(os.path.join(state2, "state.json"), "w",
              encoding="utf-8") as f:
        json.dump({
            "offset": 999, "seen": ["x"], "mon_offset": 999,
            "mon_seen": ["y"], "seq": 99,
            "notifications": [
                {"id": "wg-legacy00001", "kind": "write_gate_decision",
                 "refId": "rec-legacy", "title": "技能写入已批准",
                 "body": "legacy stock",
                 "createdAt": "2026-11-10T00:03:00Z",
                 "read": False, "_seq": 98},
                {"id": "mon-seed-read", "kind": "monitor_change",
                 "refId": None, "changeId": None, "title": "t1",
                 "body": "b1", "createdAt": "2026-11-10T00:05:00Z",
                 "read": True, "_seq": 99},
                {"id": "mon-seed-unread", "kind": "monitor_change",
                 "refId": None, "changeId": None, "title": "t2",
                 "body": "b2", "createdAt": "2026-11-10T00:06:00Z",
                 "read": False, "_seq": 100},
            ]}, f, ensure_ascii=False)
    MON_ROWS.clear()
    MON_ROWS.extend([
        {"id": "mon-seed-unread", "kind": "monitor_change",
         "title": "t2", "body": "b2",
         "createdAt": "2026-11-10T00:06:00Z"},
        {"id": "mon-seed-read", "kind": "monitor_change",
         "title": "t1", "body": "b1",
         "createdAt": "2026-11-10T00:05:00Z"},
        {"id": "mon-ancient", "kind": "monitor_change",
         "title": "t0", "body": "b0",
         "createdAt": "2026-11-10T00:01:00Z"},
    ])
    proc, up = boot(state2)
    try:
        check("bridge reboots over legacy state", up)
        if up:
            status, data = call("GET", "/notifications")
            by_id = {n.get("id"): n for n in data.get("items", [])}
            check("legacy read mark carried over",
                  by_id.get("mon-seed-read", {}).get("read") is True,
                  f"{by_id.get('mon-seed-read')}")
            check("legacy unread monitor item stays unread",
                  by_id.get("mon-seed-unread", {}).get("read") is False,
                  f"{by_id.get('mon-seed-unread')}")
            check("pre-baseline monitor history not backfilled",
                  "mon-ancient" not in by_id, f"{sorted(by_id)}")
            check("stored decision copy not resurrected "
                  "(owner ledger is the source)",
                  "wg-legacy00001" not in by_id, f"{sorted(by_id)}")
            status, overview = call("GET", "/overview")
            check("overview unread counts the one monitor item",
                  status == 200
                  and overview.get("unreadNotifications") == 1,
                  f"{status} {overview.get('unreadNotifications')}")
    finally:
        stop(proc)

    # ---- phase 4: dead owner source degrades, never 500s -------
    mon.shutdown()
    proc, up = boot(state_dir)
    try:
        check("bridge up for degradation phase", up)
        if up:
            status, data = call("GET", "/notifications")
            kinds = {n.get("kind") for n in data.get("items", [])}
            check("dead monitor source -> decisions still serve",
                  status == 200
                  and kinds == {"write_gate_decision"},
                  f"{status} {kinds}")
    finally:
        stop(proc)
        wg.shutdown()
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
