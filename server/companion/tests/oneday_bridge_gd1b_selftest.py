#!/usr/bin/env python3
"""GD-1b self-test for oneday_bridge.py (2026-11-14).

Phase A (HTTP, subprocess bridge): milestone-all-done auto
entry (path two) -- fires on the all-checked transition,
does not re-fire while staying all-done, fires again after
an uncheck + recheck.
Phase B (in-process): stopped-task auto entries (path one)
-- blocked/failed entries once per stopped episode, stamp
clears on leaving the stopped states, completion recorder
unaffected.
Phase C (in-process): GD-4 -- a briefing round whose goal
is deleted mid-flight must not land an orphan briefing.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

_HERE = os.path.dirname(os.path.abspath(__file__))
# staged layout (run_bridge_selftests.sh): module sits next to
# the test; repo layout: module lives in ../modules
_SIBLING = os.path.join(_HERE, "oneday_bridge.py")
BRIDGE = _SIBLING if os.path.exists(_SIBLING) else os.path.abspath(
    os.path.join(_HERE, "..", "modules", "oneday_bridge.py"))
KEY = "gd1b-selftest-key"
PORT = 18751
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


def call(method, path, body=None, key=KEY):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def auto_entries(entries):
    return [e for e in entries
            if e["source"] == "agent"
            and "里程碑已全部完成" in e["body"]]


def phase_a():
    tmp = tempfile.mkdtemp(prefix="gd1b-a-")
    env = dict(os.environ, ONEDAY_BRIDGE_KEY=KEY,
               DATA_PATH=os.path.join(tmp, "data.json"),
               ONEDAY_PORT=str(PORT))
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                s, _ = call("GET", "/health", key=None)
                if s == 200:
                    break
            except Exception:
                pass
            time.sleep(0.2)
        s, g = call("POST", "/goals", {
            "title": "里程碑目标",
            "milestones": [{"title": "第一步"}, {"title": "第二步"}]})
        check("A create goal with milestones", s == 201, f"{s} {g}")
        gid = g["id"]
        ms = g["milestones"]

        def patch_ms(done_flags):
            body = {"milestones": [
                {"id": m["id"], "title": m["title"], "done": d}
                for m, d in zip(ms, done_flags)]}
            return call("PATCH", f"/goals/{gid}", body)

        s, _ = patch_ms([True, False])
        check("A patch partial done ok", s == 200, f"{s}")
        s, ents = call("GET", f"/goals/{gid}/entries")
        check("A no auto entry before all done",
              s == 200 and auto_entries(ents["items"]) == [],
              f"{s} {ents}")
        s, _ = patch_ms([True, True])
        check("A patch all done ok", s == 200, f"{s}")
        s, ents = call("GET", f"/goals/{gid}/entries")
        autos = auto_entries(ents["items"])
        check("A all-done auto entry fired once",
              s == 200 and len(autos) == 1
              and "共 2 项" in autos[0]["body"], f"{s} {ents}")
        s, _ = call("PATCH", f"/goals/{gid}", {"note": "补一句备注"})
        s, _ = patch_ms([True, True])
        s, ents = call("GET", f"/goals/{gid}/entries")
        check("A staying all-done does not re-fire",
              len(auto_entries(ents["items"])) == 1, f"{ents}")
        s, _ = patch_ms([True, False])
        s, _ = patch_ms([True, True])
        s, ents = call("GET", f"/goals/{gid}/entries")
        check("A uncheck + recheck fires again",
              len(auto_entries(ents["items"])) == 2, f"{ents}")
    finally:
        proc.terminate()
        proc.wait(timeout=5)


def load_module(tmp):
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    sys.path.insert(0, os.path.dirname(BRIDGE))
    import oneday_bridge as ob
    ob._load()
    return ob


def phase_b():
    tmp = tempfile.mkdtemp(prefix="gd1b-b-")
    ob = load_module(tmp)
    now = 1_700_000_000.0
    with ob._lock:
        g = ob._create_goal({"title": "委派目标"})
        gid = g["id"]
        link = ob._create_task_link(gid, {"taskId": "t_1"})
        lid = link["id"]

        def entries():
            return [e for e in ob._db["goalEntries"]
                    if e["goalId"] == gid]

        def echo_now():
            # 1.0.65: the exactly-once episode ledger is the
            # poll's goalEchoState, not a stamp on a link record
            return ob._db["goalEchoState"].get("t_1") or {}

        ob._record_stopped_task_entries_locked(
            {"t_1": ("写周报", "blocked")}, now)
        check("B blocked entry fired",
              len(entries()) == 1
              and "被阻塞" in entries()[0]["body"]
              and entries()[0]["source"] == "agent",
              f"{entries()}")
        check("B stamp set to blocked",
              echo_now().get("stoppedBucket") == "blocked"
              and echo_now().get("stoppedEntryAt") == now)
        ob._record_stopped_task_entries_locked(
            {"t_1": ("写周报", "blocked")}, now + 10)
        check("B staying blocked does not re-fire",
              len(entries()) == 1)
        ob._record_stopped_task_entries_locked(
            {"t_1": ("写周报", "failed")}, now + 20)
        check("B blocked -> failed fires a second entry",
              len(entries()) == 2
              and "失败" in entries()[1]["body"], f"{entries()}")
        ob._record_stopped_task_entries_locked(
            {"t_1": ("写周报", "in_progress")}, now + 30)
        check("B leaving stopped states clears stamp, no entry",
              len(entries()) == 2
              and echo_now().get("stoppedBucket") is None)
        ob._record_stopped_task_entries_locked(
            {"t_1": ("写周报", "blocked")}, now + 40)
        check("B re-block after recovery fires again",
              len(entries()) == 3, f"{entries()}")
        ob._record_completed_task_entries_locked(
            {"t_1": ("写周报", "done")}, now + 50)
        ob._record_completed_task_entries_locked(
            {"t_1": ("写周报", "done")}, now + 60)
        done_entries = [e for e in entries()
                        if "已完成" in e["body"]]
        check("B completion recorder still exactly-once",
              len(done_entries) == 1, f"{entries()}")
        view = next(v for v in ob._list_task_links(gid)
                    if v["taskId"] == "t_1")
        check("B compat link view carries stoppedEntryAt",
              "stoppedEntryAt" in view
              and view["id"] == "gt_t_1", f"{view}")


def phase_c():
    tmp = tempfile.mkdtemp(prefix="gd1b-c-")
    ob = load_module(tmp)
    ob.HERMES_API_KEY = "stub-key"
    holder = {}

    def fake_submit(prompt, idem):
        return "run_stub", None

    def fake_poll(run_id):
        # the goal disappears while the round is in flight
        with ob._lock:
            ob._delete_goal(holder["gid"])
        return json.dumps({"title": "本周简报标题",
                           "body": "本周有进展。"}), None

    ob._hermes_submit_run = fake_submit
    ob._hermes_poll_run = fake_poll
    ob._fetch_kanban_tasks = lambda: ({}, None)
    with ob._lock:
        g = ob._create_goal({"title": "会被删掉的目标"})
        holder["gid"] = g["id"]
        ob._create_entry(g["id"], {"body": "本周推进了一步"})
    ob._run_briefing_round("manual")
    with ob._lock:
        briefs = [b for b in ob._db["briefings"]
                  if b["goalId"] == holder["gid"]]
        hist = ob._db["meta"]["briefGen"]["history"]
    check("C no orphan briefing for deleted goal",
          briefs == [], f"{briefs}")
    check("C round records skipped-goal-gone",
          hist and hist[-1].get("skippedGoalGone") == 1
          and any(o.get("result") == "skipped-goal-gone"
                  for o in hist[-1]["outcomes"]),
          f"{hist[-1] if hist else None}")


phase_a()
phase_b()
phase_c()
print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
