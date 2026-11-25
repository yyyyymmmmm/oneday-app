#!/usr/bin/env python3
"""GD-2/GD-3 self-test for oneday_bridge.py goal tail changes.

Phase A: HTTP contract against a subprocess bridge booted on a
seeded data file (no Hermes key): briefing view carries
note/lastOpenedAt (pre-GD-3 records read null), the opened
stamp endpoint writes + persists, the goal tasks face joins
links x board snapshot x event ring, the ungrouped face
applies the harmonised-reading classification, and grouping
through the standing task-links write removes the row.

Phase B: in-process briefing round with stubbed Hermes runs:
the stored note is assembled BY CODE from the material counts
(old material outside the 7-day window is not counted), and
_mark_briefing_opened stamps the produced letter.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

BRIDGE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "oneday_bridge.py")
KEY = "gd23-selftest-key"
PORT = 18747
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


# Relative to the real clock on purpose: the bridge prunes
# ancient feed events on its own schedule, so a fixed past
# epoch would see the seeded event ring emptied mid-test.
NOW = time.time()

SEED = {
    "goals": [
        {"id": "g_a", "title": "目标甲", "note": "", "milestones": [],
         "createdAt": NOW - 90000, "updatedAt": NOW - 90000,
         "parentId": None, "source": "manual", "category": None},
        {"id": "g_b", "title": "目标乙", "note": "", "milestones": [],
         "createdAt": NOW - 80000, "updatedAt": NOW - 80000,
         "parentId": None, "source": "manual", "category": None},
    ],
    "briefings": [
        {"id": "b_1", "goalId": "g_a", "period": "2023-W46",
         "title": "新信", "body": "正文一。\n\n正文二。",
         "createdAt": NOW - 3600,
         "note": "依据近 7 天2 条进展", "lastOpenedAt": None},
        # pre-GD-3 record: neither new key exists on disk
        {"id": "b_old", "goalId": "g_a", "period": "2023-W45",
         "title": "旧信", "body": "旧正文。", "createdAt": NOW - 90000},
    ],
    "goalEntries": [],
    "goalTaskLinks": [
        {"id": "gl_1", "goalId": "g_a", "taskId": "t_linked1",
         "milestoneId": None, "createdAt": NOW - 5000,
         "completionEntryAt": None, "stoppedEntryAt": None,
         "stoppedEntryBucket": None},
        {"id": "gl_2", "goalId": "g_a", "taskId": "t_gone",
         "milestoneId": None, "createdAt": NOW - 4000,
         "completionEntryAt": None, "stoppedEntryAt": None,
         "stoppedEntryBucket": None},
    ],
    "ideas": [
        {"id": "i_adopted", "title": "被采纳的点子", "detail": "",
         "goalId": None, "createdAt": NOW - 3000, "source": "generated",
         "status": "adopted", "taskId": "t_adopted"},
        {"id": "i_grouped", "title": "已归目标的点子", "detail": "",
         "goalId": "g_a", "createdAt": NOW - 3000,
         "source": "generated", "status": "adopted",
         "taskId": "t_grouped"},
        {"id": "i_dismissed", "title": "已放下的点子", "detail": "",
         "goalId": None, "createdAt": NOW - 3000,
         "source": "generated", "status": "dismissed",
         "taskId": "t_dismissed"},
    ],
    "kanbanBindings": [
        {"taskId": "t_chat", "title": "对话里派的活",
         "ownerSessionId": "s_1", "goalId": None,
         "createdAt": NOW - 2000, "lastStatus": "blocked",
         "doneTraced": False},
        {"taskId": "t_bound", "title": "带目标派的活",
         "ownerSessionId": "s_1", "goalId": "g_a",
         "createdAt": NOW - 2000, "lastStatus": "ready",
         "doneTraced": False},
    ],
    "meta": {"feed": {
        "taskSnapshot": {"t_linked1": "running", "t_adopted": "todo",
                         "t_grouped": "done", "t_chat": "blocked",
                         "t_bound": "ready", "t_stranger": "todo",
                         "t_dismissed": "done"},
        "taskTitles": {"t_linked1": "关联任务一", "t_adopted": "采纳任务",
                       "t_chat": "对话任务", "t_stranger": "陌生任务"},
        "kanbanPolledAt": NOW - 100,
        "events": [
            {"at": NOW - 900, "state": "todo",
             "refs": [{"type": "task", "id": "t_linked1"}]},
            {"at": NOW - 800, "state": "running",
             "refs": [{"type": "task", "id": "t_linked1"}]},
            {"at": NOW - 700, "state": "blocked",
             "refs": [{"type": "task", "id": "t_chat"}]},
        ],
    }},
}


def phase_a():
    tmp = tempfile.mkdtemp(prefix="gd23a-")
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(SEED, f, ensure_ascii=False)
    env = dict(os.environ, ONEDAY_BRIDGE_KEY=KEY,
               DATA_PATH=data_path,
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
        # GD-3: briefing view carries note / lastOpenedAt
        s, bl = call("GET", "/goals/g_a/briefings")
        by_id = {b["id"]: b for b in bl["items"]}
        check("A briefing note passthrough", s == 200
              and by_id["b_1"]["note"] == "依据近 7 天2 条进展",
              f"{s} {bl}")
        check("A pre-GD3 briefing reads nulls", by_id["b_old"]["note"] is None
              and by_id["b_old"]["lastOpenedAt"] is None,
              f"{by_id.get('b_old')}")
        # GD-3: opened stamp writes and persists
        t0 = time.time()
        s, opened = call("POST", "/goals/g_a/briefings/b_1/opened")
        check("A opened stamps lastOpenedAt", s == 200
              and opened["lastOpenedAt"] is not None
              and t0 - 5 <= opened["lastOpenedAt"] <= time.time() + 5,
              f"{s} {opened}")
        s, bl2 = call("GET", "/goals/g_a/briefings")
        by_id2 = {b["id"]: b for b in bl2["items"]}
        check("A opened stamp persisted",
              by_id2["b_1"]["lastOpenedAt"] == opened["lastOpenedAt"],
              f"{by_id2['b_1']}")
        s, _ = call("POST", "/goals/g_a/briefings/b_nope/opened")
        check("A opened missing briefing 404", s == 404, f"{s}")
        s, _ = call("POST", "/goals/g_b/briefings/b_1/opened")
        check("A opened wrong goal 404", s == 404, f"{s}")
        # GD-2 face 1: linked tasks live rows
        s, tl = call("GET", "/goals/g_a/tasks")
        rows = {r["taskId"]: r for r in tl["items"]}
        check("A goal tasks rows", s == 200 and len(rows) == 2,
              f"{s} {tl}")
        r1 = rows.get("t_linked1", {})
        check("A linked row live fields",
              r1.get("title") == "关联任务一"
              and r1.get("status") == "running"
              and r1.get("bucket") == "running"
              and r1.get("updatedAt") == NOW - 800,
              f"{r1}")
        r2 = rows.get("t_gone", {})
        check("A off-board linked row honest nulls",
              r2.get("status") is None and r2.get("bucket") is None
              and r2.get("updatedAt") is None, f"{r2}")
        s, _ = call("GET", "/goals/g_nope/tasks")
        check("A goal tasks missing goal 404", s == 404, f"{s}")
        # GD-2 face 2: classification
        s, ug = call("GET", "/goals/ungrouped-tasks")
        urows = {r["taskId"]: r for r in ug["items"]}
        check("A ungrouped set exact",
              s == 200 and set(urows) == {"t_adopted", "t_chat"},
              f"{s} {ug}")
        check("A ungrouped polledAt", ug["polledAt"] == NOW - 100,
              f"{ug.get('polledAt')}")
        ra = urows.get("t_adopted", {})
        check("A adopted row", ra.get("origin") == "adopted"
              and ra.get("ideaId") == "i_adopted"
              and ra.get("status") == "todo"
              and ra.get("bucket") == "waiting", f"{ra}")
        rc = urows.get("t_chat", {})
        check("A chat row", rc.get("origin") == "chat"
              and rc.get("ownerSessionId") == "s_1"
              and rc.get("bucket") == "blocked"
              and rc.get("updatedAt") == NOW - 700, f"{rc}")
        # grouping via the standing write removes the row
        s, link = call("POST", "/goals/g_b/task-links",
                       {"taskId": "t_chat"})
        check("A group write 201", s == 201
              and link["taskId"] == "t_chat", f"{s} {link}")
        s, ug2 = call("GET", "/goals/ungrouped-tasks")
        check("A grouped row leaves the face",
              {r["taskId"] for r in ug2["items"]} == {"t_adopted"},
              f"{ug2}")
    finally:
        proc.terminate()
        proc.wait(timeout=5)


def phase_b():
    tmp = tempfile.mkdtemp(prefix="gd23b-")
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    sys.path.insert(0, os.path.dirname(BRIDGE))
    import oneday_bridge as ob
    ob._load()
    ob.HERMES_API_KEY = "test-api-key"

    # note assembly: fixed template, zero classes omitted
    check("B note all zero is None", ob._briefing_note(
        {"entries": 0, "tasks": 0, "changes": 0}) is None)
    check("B note single class", ob._briefing_note(
        {"entries": 2, "tasks": 0, "changes": 0}) == "依据近 7 天2 条进展")
    check("B note full template", ob._briefing_note(
        {"entries": 2, "tasks": 1, "changes": 3})
        == "依据近 7 天2 条进展、1 项任务变化、3 条监测变化")
    check("B note skips zero middle", ob._briefing_note(
        {"entries": 1, "tasks": 0, "changes": 1})
        == "依据近 7 天1 条进展、1 条监测变化")

    def fake_submit(prompt, idem):
        return "run_stub", None

    def fake_poll(run_id):
        return json.dumps({"title": "本周信", "body": "正文。"}), None

    ob._hermes_submit_run = fake_submit
    ob._hermes_poll_run = fake_poll
    ob._fetch_kanban_tasks = lambda: ({}, None)
    now = ob._now()
    with ob._lock:
        g = ob._create_goal({"title": "计数目标"})
        gid = g["id"]
        # 2 entries inside the window, 1 outside (not counted)
        ob._create_entry(gid, {"body": "进展一"})
        ob._create_entry(gid, {"body": "进展二"})
        ob._db["goalEntries"].append({
            "id": "e_old", "goalId": gid, "body": "旧进展",
            "source": "user", "createdAt": now - 8 * 24 * 3600})
        # 1 adopted idea with a task for this goal (task class)
        ob._db["ideas"].append({
            "id": "i_b", "title": "点子", "detail": "",
            "goalId": gid, "createdAt": now - 100,
            "source": "generated", "status": "adopted",
            "taskId": "t_b"})
        # 1 monitor with 1 in-window change, 1 stale change
        ob._db["monitors"].append({
            "id": "m_b", "name": "监测", "goalId": gid})
        ob._db["changes"].append({
            "id": "c_new", "monitorId": "m_b",
            "detectedAt": now - 3600, "summary": "新变化"})
        ob._db["changes"].append({
            "id": "c_old", "monitorId": "m_b",
            "detectedAt": now - 9 * 24 * 3600, "summary": "旧变化"})
        ob._save_locked()
    ob._run_briefing_round("manual")
    with ob._lock:
        briefs = list(ob._db["briefings"])
    check("B round produced one letter", len(briefs) == 1,
          f"{briefs}")
    if briefs:
        b = briefs[0]
        check("B stored note counts match material",
              b.get("note") == "依据近 7 天2 条进展、1 项任务变化、1 条监测变化",
              f"{b.get('note')}")
        check("B stored lastOpenedAt starts null",
              b.get("lastOpenedAt") is None, f"{b}")
        with ob._lock:
            view = ob._mark_briefing_opened(gid, b["id"])
        check("B mark opened stamps + view carries it",
              view["lastOpenedAt"] is not None
              and view["note"] == b["note"], f"{view}")


phase_a()
phase_b()
print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
