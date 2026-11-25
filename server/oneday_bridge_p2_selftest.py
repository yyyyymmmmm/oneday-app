#!/usr/bin/env python3
"""P2 self-test for oneday_bridge.py goal-depth changes.

Phase A: HTTP contract against a subprocess bridge (temp data,
no Hermes key): goal status/sub-goal rules, entries CRUD,
monitor goalId, delete cascade, briefing ledger endpoints.
Phase B: in-process briefing round with stubbed Hermes runs:
material gate (skip no-material), letter lands, idempotent
re-run, kanban note stays out of material.
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
KEY = "p2-selftest-key"
PORT = 18746
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


def phase_a():
    tmp = tempfile.mkdtemp(prefix="p2a-")
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
        s, g = call("POST", "/goals", {"title": "父目标",
                                       "milestones": [{"title": "m1"}]})
        check("A create goal 201 + new fields", s == 201
              and g["status"] == "active" and g["completedAt"] is None
              and g["parentId"] is None and g["source"] == "manual",
              f"{s} {g}")
        gid = g["id"]
        s, sub = call("POST", "/goals", {"title": "子目标",
                                         "parentId": gid})
        check("A create sub-goal", s == 201 and sub["parentId"] == gid)
        subid = sub["id"]
        s, _ = call("POST", "/goals", {"title": "孙目标",
                                       "parentId": subid})
        check("A grandchild rejected 400", s == 400, f"{s}")
        s, _ = call("POST", "/goals", {"title": "x",
                                       "parentId": "g_nope"})
        check("A missing parent 400", s == 400, f"{s}")
        s, _ = call("PATCH", f"/goals/{gid}",
                    {"parentId": subid})
        check("A parent-with-children cannot become sub 400",
              s == 400, f"{s}")
        s, g2 = call("PATCH", f"/goals/{gid}", {"status": "completed"})
        check("A complete settles completedAt",
              s == 200 and g2["status"] == "completed"
              and isinstance(g2["completedAt"], float), f"{s} {g2}")
        s, g3 = call("PATCH", f"/goals/{gid}", {"status": "active"})
        check("A reopen clears completedAt",
              s == 200 and g3["status"] == "active"
              and g3["completedAt"] is None)
        s, _ = call("PATCH", f"/goals/{gid}", {"status": "paused"})
        check("A paused status rejected 400", s == 400, f"{s}")
        s, e1 = call("POST", f"/goals/{gid}/entries",
                     {"body": "第一步走通了"})
        check("A entry create (default source=user)",
              s == 201 and e1["source"] == "user", f"{s} {e1}")
        s, e2 = call("POST", f"/goals/{gid}/entries",
                     {"body": "智能体记的", "source": "agent"})
        check("A entry create agent", s == 201 and e2["source"] == "agent")
        s, _ = call("POST", f"/goals/{gid}/entries", {"body": "  "})
        check("A empty entry 400", s == 400, f"{s}")
        s, _ = call("POST", "/goals/g_nope/entries", {"body": "x"})
        check("A entry on missing goal 404", s == 404, f"{s}")
        s, lst = call("GET", f"/goals/{gid}/entries")
        check("A entries list asc", s == 200
              and [i["body"] for i in lst["items"]]
              == ["第一步走通了", "智能体记的"])
        s, gl = call("GET", "/goals")
        mine = [x for x in gl["items"] if x["id"] == gid]
        check("A goal view embeds latestEntry",
              mine and mine[0]["latestEntry"]["body"] == "智能体记的",
              f"{mine}")
        s, _ = call("DELETE", f"/goals/{gid}/entries/{e1['id']}")
        check("A entry delete", s == 200)
        s, lst = call("GET", f"/goals/{gid}/entries")
        check("A entries after delete", len(lst["items"]) == 1)
        s, bl = call("GET", f"/goals/{gid}/briefings")
        check("A briefings empty list", s == 200 and bl["items"] == [])
        s, led = call("GET", "/goals/briefings")
        check("A briefing ledger view", s == 200
              and "nextRunAt" in led and led["nextRunAt"])
        s, r = call("POST", "/goals/briefings/generate")
        check("A manual round trigger 202", s == 202
              and r.get("started") is True, f"{s} {r}")
        time.sleep(1.5)
        s, led = call("GET", "/goals/briefings")
        hist = led["history"]
        check("A round recorded skipped (no Hermes key)",
              hist and hist[-1]["status"] == "skipped", f"{hist}")
        s, mon = call("POST", "/monitors",
                      {"name": "m", "target": "https://example.com",
                       "goalId": gid})
        check("A monitor with goalId", s == 201
              and mon.get("goalId") == gid, f"{s} {mon}")
        s, _ = call("POST", "/monitors",
                    {"name": "m2", "target": "https://example.com",
                     "goalId": "g_nope"})
        check("A monitor bad goalId 400", s == 400, f"{s}")
        s, _ = call("DELETE", f"/goals/{gid}")
        check("A delete parent", s == 200)
        s, goals = call("GET", "/goals")
        check("A sub-goal cascaded away",
              all(x["id"] != subid for x in goals["items"])
              and goals["items"] == [])
        s, mons = call("GET", "/monitors")
        check("A monitor unlinked on goal delete",
              mons["items"] and mons["items"][0]["goalId"] is None)
        s, _ = call("GET", f"/goals/{gid}/entries")
        check("A entries of deleted goal 404", s == 404, f"{s}")
    finally:
        proc.terminate()
        proc.wait(timeout=5)


def phase_b():
    tmp = tempfile.mkdtemp(prefix="p2b-")
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    sys.path.insert(0, os.path.dirname(BRIDGE))
    import oneday_bridge as ob
    ob._load()
    ob.HERMES_API_KEY = "stub-key"
    prompts = []

    def fake_submit(prompt, idem):
        prompts.append((prompt, idem))
        return "run_stub", None

    def fake_poll(run_id):
        return json.dumps({"title": "本周简报标题",
                           "body": "本周有进展。\n\n状态如此。\n\n下一步建议。"}), None

    ob._hermes_submit_run = fake_submit
    ob._hermes_poll_run = fake_poll
    ob._fetch_kanban_tasks = lambda: ({}, "桩测注记-不应进素材")
    with ob._lock:
        g1 = ob._create_goal({"title": "有素材的目标"})
        g2 = ob._create_goal({"title": "无素材的目标"})
        ob._create_entry(g1["id"], {"body": "本周推进了一步"})
    ob._run_briefing_round("manual")
    with ob._lock:
        briefs = list(ob._db["briefings"])
        hist = ob._db["meta"]["briefGen"]["history"]
    check("B one briefing produced", len(briefs) == 1
          and briefs[0]["goalId"] == g1["id"]
          and briefs[0]["title"] == "本周简报标题", f"{briefs}")
    check("B ledger ok + skipped counted",
          hist and hist[-1]["status"] == "ok"
          and hist[-1]["produced"] == 1
          and hist[-1]["skippedNoMaterial"] == 1, f"{hist}")
    check("B kanban note kept out of material",
          prompts and "桩测注记" not in prompts[0][0])
    check("B material carries the entry fact",
          prompts and "本周推进了一步" in prompts[0][0])
    check("B idem key per week+goal",
          prompts and prompts[0][1].endswith(g1["id"])
          and prompts[0][1].startswith("goal-brief-"))
    with ob._lock:
        listed = ob._list_briefings(g1["id"])
    check("B list briefings via view (name-collision guard)",
          len(listed) == 1 and listed[0]["body"].startswith("本周有进展"))
    check("B ledger view shape",
          ob._briefing_ledger_view()["history"][-1]["produced"] == 1)
    ob._run_briefing_round("manual")
    with ob._lock:
        briefs2 = list(ob._db["briefings"])
        hist2 = ob._db["meta"]["briefGen"]["history"]
    check("B re-run idempotent (already-exists)",
          len(briefs2) == 1 and hist2[-1]["alreadyExists"] == 1,
          f"{hist2[-1] if hist2 else None}")


phase_a()
phase_b()
print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
