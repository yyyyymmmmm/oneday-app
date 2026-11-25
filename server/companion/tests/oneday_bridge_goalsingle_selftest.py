#!/usr/bin/env python3
"""Goal<->kanban single-track self-test for oneday_bridge.py
(1.0.65, sweep A-04).

Phase A (HTTP, subprocess bridge on a seeded data file):
the pre-1.0.65 goalTaskLinks collection folds into the
taskGoals field store at load -- earliest link wins a
duplicated taskId, links to a deleted goal drop, echo stamps
seed goalEchoState, the fold ledger lands in meta; the goal
tasks face carries goalId on every row; the deprecated
task-links faces read as a synthesized projection; the PUT
/tasks/{id}/goal write face sets / moves / clears with the
contract's 400s; a delegate call without Dashboard
credentials fails WITHOUT writing an assignment.

Phase B (in-process, Dashboard channel stubbed): delegate
creates the card with the standing create shape and writes
the field in the same operation; a retried delegate with
the same idempotencyKey returns the original assignment and
creates no second card; the completion recorder does not
re-fire for a migrated, already-stamped task but fires for
an unstamped one; moving a task to another goal resets its
echo ledger.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

_HERE = os.path.dirname(os.path.abspath(__file__))
_SIBLING = os.path.join(_HERE, "oneday_bridge.py")
BRIDGE = _SIBLING if os.path.exists(_SIBLING) else os.path.abspath(
    os.path.join(_HERE, "..", "modules", "oneday_bridge.py"))
KEY = "goalsingle-selftest-key"
PORT = 18753
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


def seed(now):
    return {
        "goals": [
            {"id": "g_a", "title": "目标甲", "note": "",
             "milestones": [{"id": "ms1", "title": "第一步",
                             "done": False}],
             "createdAt": now - 90000, "updatedAt": now - 90000,
             "status": "active", "completedAt": None,
             "parentId": None, "source": "manual",
             "category": None},
            {"id": "g_b", "title": "目标乙", "note": "",
             "milestones": [],
             "createdAt": now - 80000, "updatedAt": now - 80000,
             "status": "active", "completedAt": None,
             "parentId": None, "source": "manual",
             "category": None},
        ],
        "ideas": [], "monitors": [], "changes": [],
        "goalEntries": [], "briefings": [], "feedPosts": [],
        "goalTaskLinks": [
            # already completion-stamped before the fold: its
            # fact entry exists and must never re-fire
            {"id": "gl_old", "goalId": "g_a", "taskId": "t_done",
             "milestoneId": None, "createdAt": now - 5000,
             "completionEntryAt": now - 4000,
             "stoppedEntryAt": None, "stoppedEntryBucket": None},
            # duplicate taskId under a second goal, LATER:
            # the field is single-valued, earliest wins
            {"id": "gl_dup", "goalId": "g_b", "taskId": "t_done",
             "milestoneId": None, "createdAt": now - 3000,
             "completionEntryAt": None,
             "stoppedEntryAt": None, "stoppedEntryBucket": None},
            {"id": "gl_open", "goalId": "g_a", "taskId": "t_open",
             "milestoneId": "ms1", "createdAt": now - 2000,
             "completionEntryAt": None,
             "stoppedEntryAt": None, "stoppedEntryBucket": None},
            # link to a goal that no longer exists: dropped
            {"id": "gl_dead", "goalId": "g_gone",
             "taskId": "t_orphan", "milestoneId": None,
             "createdAt": now - 1000,
             "completionEntryAt": None,
             "stoppedEntryAt": None, "stoppedEntryBucket": None},
        ],
        "meta": {"feed": {
            "taskSnapshot": {"t_done": "done",
                             "t_open": "running"},
            "taskTitles": {"t_done": "已办完的事",
                           "t_open": "在办的事"},
            "kanbanPolledAt": now - 60, "events": []}},
    }


def phase_a():
    tmp = tempfile.mkdtemp(prefix="goalsingle-a-")
    now = time.time()
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(seed(now), f, ensure_ascii=False)
    env = dict(os.environ, ONEDAY_BRIDGE_KEY=KEY,
               DATA_PATH=data_path, ONEDAY_PORT=str(PORT))
    env.pop("HERMES_API_KEY", None)
    env.pop("HERMES_DASH_USER", None)
    env.pop("HERMES_DASH_PASSWORD", None)
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
        with open(data_path, encoding="utf-8") as f:
            stored = json.load(f)
        tg = stored.get("taskGoals") or {}
        check("A fold: links collection retired empty",
              stored.get("goalTaskLinks") == [],
              f"{stored.get('goalTaskLinks')}")
        check("A fold: earliest link wins the field",
              tg.get("t_done", {}).get("goalId") == "g_a",
              f"{tg}")
        check("A fold: milestone rides along",
              tg.get("t_open", {}).get("milestoneId") == "ms1",
              f"{tg}")
        check("A fold: dead-goal link dropped",
              "t_orphan" not in tg, f"{tg}")
        mig = (stored.get("meta") or {}).get("taskGoalMigration")
        check("A fold: count ledger in meta",
              mig and mig["links"] == 4 and mig["assigned"] == 2
              and mig["conflicts"] == 1 and mig["dropped"] == 1,
              f"{mig}")
        echo = stored.get("goalEchoState") or {}
        check("A fold: completion stamp seeded the echo ledger",
              echo.get("t_done", {}).get("completedGoalId")
              == "g_a"
              and echo["t_done"]["completedEntryAt"]
              == now - 4000, f"{echo}")
        # goal tasks face: rows carry the field itself
        s, body = call("GET", "/goals/g_a/tasks")
        rows = {r["taskId"]: r for r in body["items"]}
        check("A goal tasks rows carry goalId",
              s == 200 and set(rows) == {"t_done", "t_open"}
              and all(r["goalId"] == "g_a"
                      for r in rows.values()), f"{s} {body}")
        check("A goal tasks row keeps live fields",
              rows["t_open"]["status"] == "running"
              and rows["t_open"]["bucket"] == "running"
              and rows["t_open"]["assignedAt"] == now - 2000,
              f"{rows.get('t_open')}")
        check("A goal tasks row carries the completion stamp",
              rows["t_done"]["completionEntryAt"] == now - 4000
              and rows["t_open"]["completionEntryAt"] is None,
              f"{rows.get('t_done')}")
        s, body = call("GET", "/goals/g_b/tasks")
        check("A losing goal has no rows (single-valued)",
              s == 200 and body["items"] == [], f"{s} {body}")
        # compat projection: synthesized link shape + stamps
        s, body = call("GET", "/goals/g_a/task-links")
        links = {l["taskId"]: l for l in body["items"]}
        check("A compat links synthesized from the field",
              s == 200 and set(links) == {"t_done", "t_open"}
              and links["t_done"]["id"] == "gt_t_done"
              and links["t_done"]["completionEntryAt"]
              == now - 4000
              and links["t_open"]["completionEntryAt"] is None,
              f"{s} {body}")
        # PUT write face: set / move / clear + validation
        s, body = call("PUT", "/tasks/t_new/goal",
                       {"goalId": "g_b"})
        check("A PUT sets the field",
              s == 200 and body["goalId"] == "g_b"
              and body["taskId"] == "t_new"
              and body["assignedAt"] is not None, f"{s} {body}")
        s, body = call("GET", "/goals/g_b/tasks")
        check("A PUT row visible on the goal face",
              {r["taskId"] for r in body["items"]} == {"t_new"},
              f"{body}")
        s, body = call("PUT", "/tasks/t_new/goal",
                       {"goalId": "g_a", "milestoneId": "ms1"})
        check("A PUT moves the task (single truth)",
              s == 200 and body["goalId"] == "g_a"
              and body["milestoneId"] == "ms1", f"{s} {body}")
        s, body = call("GET", "/goals/g_b/tasks")
        check("A move leaves no copy behind",
              body["items"] == [], f"{body}")
        s, _ = call("PUT", "/tasks/t_new/goal",
                    {"goalId": "g_a", "milestoneId": "nope"})
        check("A PUT bogus milestone 400", s == 400, f"{s}")
        s, _ = call("PUT", "/tasks/t_new/goal",
                    {"milestoneId": "ms1"})
        check("A PUT missing goalId key 400", s == 400, f"{s}")
        s, _ = call("PUT", "/tasks/t_new/goal",
                    {"goalId": None, "milestoneId": "ms1"})
        check("A PUT milestone without goal 400",
              s == 400, f"{s}")
        s, _ = call("PUT", "/tasks/t_new/goal",
                    {"goalId": "g_nope"})
        check("A PUT missing goal 404", s == 404, f"{s}")
        s, body = call("PUT", "/tasks/t_new/goal",
                       {"goalId": None})
        check("A PUT null clears the field",
              s == 200 and body["goalId"] is None
              and body["assignedAt"] is None, f"{s} {body}")
        s, body = call("GET", "/goals/g_a/tasks")
        check("A cleared task leaves the goal face",
              {r["taskId"] for r in body["items"]}
              == {"t_done", "t_open"}, f"{body}")
        # delegate without Dashboard credentials: fails
        # honestly and writes NO assignment
        s, _ = call("POST", "/goals/g_a/delegate",
                    {"title": "不该落地的委派"})
        check("A delegate without dash channel fails 5xx",
              s >= 500, f"{s}")
        with open(data_path, encoding="utf-8") as f:
            stored = json.load(f)
        check("A failed delegate wrote no assignment",
              set((stored.get("taskGoals") or {}).keys())
              == {"t_done", "t_open"},
              f"{stored.get('taskGoals')}")
    finally:
        proc.terminate()
        proc.wait(timeout=10)


def phase_b():
    tmp = tempfile.mkdtemp(prefix="goalsingle-b-")
    now = time.time()
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(seed(now), f, ensure_ascii=False)
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = data_path
    os.environ.pop("HERMES_API_KEY", None)
    spec = importlib.util.spec_from_file_location(
        "ob_goalsingle", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()

    # fold happened at load: the stamped task must not re-fire
    with mod._lock:
        mod._record_completed_task_entries_locked(
            {"t_done": ("已办完的事", "done"),
             "t_open": ("在办的事", "done")}, now)
        entries = [e for e in mod._db["goalEntries"]
                   if e["goalId"] == "g_a"]
    check("B migrated stamp blocks re-fire, unstamped fires",
          len(entries) == 1 and "t_open" in entries[0]["body"],
          f"{entries}")

    # delegate with a stubbed Dashboard channel
    calls = []

    def fake_dash(path, *, method="GET", body=None):
        calls.append((method, path, body))
        if path.startswith("/api/plugins/kanban/tasks?"):
            return {"task": {"id": "t_del1",
                             "title": body["title"],
                             "status": "ready"}}
        if path.startswith("/api/plugins/kanban/dispatch"):
            return {"ok": True}
        raise AssertionError(f"unexpected dash call {path}")

    mod._dash_json = fake_dash
    out = mod._delegate_goal_task(
        "g_b", {"title": "订婚礼场地",
                "idempotencyKey": "del-key-1"})
    check("B delegate returns the assignment",
          out["taskId"] == "t_del1" and out["goalId"] == "g_b"
          and out["assignedAt"] is not None, f"{out}")
    creates = [c for c in calls if c[0] == "POST"
               and "tasks?" in c[1]]
    check("B delegate created exactly one card",
          len(creates) == 1, f"{calls}")
    card = creates[0][2] if creates else {}
    check("B card body is the standing create shape",
          card.get("assignee") == "default"
          and card.get("idempotency_key") == "del-key-1"
          and card.get("body")
          == "为目标《目标乙》安排的一件事。",
          f"{card}")
    check("B dispatch attempted after create",
          any("dispatch" in c[1] for c in calls), f"{calls}")
    with mod._lock:
        a = mod._db["taskGoals"].get("t_del1") or {}
    check("B field written with the delegate key",
          a.get("goalId") == "g_b"
          and a.get("delegateKey") == "del-key-1", f"{a}")
    out2 = mod._delegate_goal_task(
        "g_b", {"title": "订婚礼场地",
                "idempotencyKey": "del-key-1"})
    creates2 = [c for c in calls if c[0] == "POST"
                and "tasks?" in c[1]]
    check("B retried delegate creates no second card",
          out2["taskId"] == "t_del1" and len(creates2) == 1,
          f"{out2} {calls}")
    # moving the delegated task resets its echo ledger
    with mod._lock:
        mod._record_completed_task_entries_locked(
            {"t_del1": ("订婚礼场地", "done")}, now)
        mod._set_task_goal_locked("t_del1", "g_a", None)
        st = mod._db["goalEchoState"].get("t_del1")
    check("B move resets the echo ledger",
          st is None or st.get("completedEntryAt") is None,
          f"{st}")
    # goal deletion clears fields + ledgers of its tasks
    with mod._lock:
        mod._delete_goal("g_a")
        left = {t: a for t, a in mod._db["taskGoals"].items()
                if a["goalId"] == "g_a"}
    check("B goal deletion clears its tasks' fields",
          left == {}, f"{left}")


def main():
    phase_a()
    phase_b()
    print(f"goalsingle selftest: {passed} passed, "
          f"{failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
