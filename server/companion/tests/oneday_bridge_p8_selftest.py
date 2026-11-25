#!/usr/bin/env python3
"""P8 self-test for oneday_bridge.py GD-1: the goal `activity`
derivation (parity spec ch.4.3).

In-process throughout. The derivation never reads the wall
clock (every stamp comes from stored records), so the fixture
uses one fixed epoch base and relative offsets -- fully
deterministic. Goals/links/entries and the feed poll's kanban
state graph (meta.feed taskSnapshot/taskTitles/events) are
seeded through the on-disk data file + _load(), exactly the
shapes production carries.

Phases:
1. bucket mapping for the raw kanban vocabulary.
2. state derivation: running / blocked (priority over
   running) / failed folds into blocked / waiting / all-done
   idle / no-link idle / cancelled.
3. gaps are noted, never silent: link missing from the
   snapshot, snapshot never polled, poll failure note carried
   through, unknown raw state counted + noted.
4. latestProgress picks the newest entry even when the store
   is unordered; lastActivityAt takes the true max across
   goal/entry/link/event stamps; `since` comes from the event
   ring and stays None when the ring holds nothing.
5. read-only proof: goals/entries/links/feedPosts are
   byte-identical after list + detail derivations.
6. perf: 150 goals x 3 links derive in one _list_goals()
   pass, timed.
"""
import copy
import importlib.util
import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def _sibling(name):
    p = os.path.join(HERE, name)
    if os.path.exists(p):
        return p
    return os.path.join(HERE, "..", "modules", name)


BRIDGE = _sibling("oneday_bridge.py")
sys.path.insert(0, os.path.dirname(os.path.abspath(BRIDGE)))
KEY = "p8-selftest-key"
T0 = 1_700_000_000.0

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def goal(gid, status="active", updated=T0 - 1000):
    return {"id": gid, "title": f"目标 {gid}", "note": "",
            "milestones": [], "createdAt": T0 - 90000,
            "updatedAt": updated, "status": status,
            "completedAt": T0 - 400 if status == "completed"
            else None, "parentId": None, "source": "manual"}


def link(gid, tid, at):
    return {"id": f"gl_{tid}", "goalId": gid, "taskId": tid,
            "milestoneId": None, "createdAt": at,
            "completionEntryAt": None}


def entry(gid, eid, body, at):
    return {"id": eid, "goalId": gid, "body": body,
            "source": "user", "createdAt": at}


def seed():
    goals = [goal("g_run"), goal("g_block"), goal("g_fail"),
             goal("g_wait"), goal("g_done", status="completed"),
             goal("g_none"), goal("g_missing"), goal("g_mixed"),
             goal("g_cancel"), goal("g_unknown")]
    links = [
        link("g_run", "t_run1", T0 - 200),
        link("g_run", "t_wait1", T0 - 200),
        link("g_block", "t_blk", T0 - 200),
        link("g_block", "t_run2", T0 - 200),
        link("g_fail", "t_fail", T0 - 200),
        link("g_wait", "t_todo", T0 - 200),
        link("g_done", "t_d1", T0 - 900),
        link("g_done", "t_d2", T0 - 900),
        link("g_missing", "t_ghost", T0 - 200),
        link("g_mixed", "t_run3", T0 - 200),
        link("g_mixed", "t_ghost2", T0 - 200),
        link("g_cancel", "t_cx", T0 - 200),
        link("g_unknown", "t_weird", T0 - 200),
    ]
    entries = [
        # g_run's newest entry is NOT last in the store:
        # latestProgress must pick by createdAt, not position.
        entry("g_run", "e_r2", "较新的进展", T0 - 100),
        entry("g_run", "e_r1", "较旧的进展", T0 - 300),
        entry("g_done", "e_d", "任务《收尾》已完成（任务号 t_d2）",
              T0 - 500),
    ]
    snap = {
        "t_run1": "in_progress", "t_wait1": "todo",
        "t_blk": "blocked", "t_run2": "running",
        "t_fail": "failed", "t_todo": "ready",
        "t_d1": "done", "t_d2": "closed",
        "t_run3": "doing", "t_cx": "cancelled",
        "t_weird": "in_flight",
    }
    titles = {t: f"任务 {t}" for t in snap}
    events = [
        {"key": "task:t_run1:1", "at": T0 - 50, "kind": "task",
         "text": "x", "state": "in_progress",
         "refs": [{"type": "task", "id": "t_run1"}]},
        {"key": "task:t_blk:1", "at": T0 - 30, "kind": "task",
         "text": "x", "state": "blocked",
         "refs": [{"type": "task", "id": "t_blk"}]},
        {"key": "task:t_d2:1", "at": T0 - 400, "kind": "task",
         "text": "x", "state": "closed",
         "refs": [{"type": "task", "id": "t_d2"}]},
    ]
    return {
        "goals": goals, "ideas": [], "monitors": [],
        "changes": [], "goalEntries": entries, "briefings": [],
        "feedPosts": [], "goalTaskLinks": links,
        "meta": {"feed": {
            "events": events, "taskSnapshot": snap,
            "taskTitles": titles, "kanbanPolledAt": T0 - 60,
            "kanbanNote": None}},
    }


def load_mod(data):
    tmp = tempfile.mkdtemp(prefix="p8-")
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = data_path
    os.environ.pop("HERMES_API_KEY", None)
    spec = importlib.util.spec_from_file_location("ob_p8",
                                                  BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    return mod


def views(mod):
    with mod._lock:
        items = mod._list_goals()
    return {g["id"]: g for g in items}


def main():
    mod = load_mod(seed())

    # Phase 1: buckets over the raw vocabulary
    b = mod._kanban_bucket
    check("1 bucket running set",
          b("in_progress") == "running" and b("WIP") == "running"
          and b("review") == "running")
    check("1 bucket blocked/failed",
          b("BLOCKED") == "blocked" and b("failed") == "failed"
          and b("rejected") == "failed")
    check("1 bucket done/waiting/cancelled",
          b("done") == "done" and b("complete") == "done"
          and b("triage") == "waiting" and b("ready") == "waiting"
          and b("canceled") == "cancelled")
    check("1 bucket unknown degrades to other",
          b("in_flight") == "other" and b("") == "other"
          and b(None) == "other")

    vs = views(mod)

    # Phase 2: the four states + folds
    a = vs["g_run"]["activity"]
    check("2 running state + counts",
          a["state"] == "running" and a["runningCount"] == 1
          and a["waitingCount"] == 1 and a["linkedCount"] == 2
          and a["missingCount"] == 0, f"{a}")
    check("2 running focus/since/label",
          a["focusTask"]["id"] == "t_run1"
          and a["focusTask"]["status"] == "in_progress"
          and a["focusTask"]["title"] == "任务 t_run1"
          and a["since"] == T0 - 50
          and a["label"] == "1 件任务进行中，1 件待开始",
          f"{a}")
    a = vs["g_block"]["activity"]
    check("2 blocked outranks running",
          a["state"] == "blocked" and a["blockedCount"] == 1
          and a["runningCount"] == 1
          and a["focusTask"]["id"] == "t_blk"
          and a["since"] == T0 - 30, f"{a}")
    a = vs["g_fail"]["activity"]
    check("2 failed folds into blocked state",
          a["state"] == "blocked" and a["failedCount"] == 1
          and a["blockedCount"] == 0
          and a["label"] == "1 件关联任务失败"
          and a["focusTask"]["status"] == "failed", f"{a}")
    a = vs["g_wait"]["activity"]
    check("2 waiting state",
          a["state"] == "waiting" and a["waitingCount"] == 1
          and a["focusTask"]["id"] == "t_todo"
          and a["since"] is None, f"{a}")
    a = vs["g_done"]["activity"]
    check("2 all-done idle on completed goal",
          vs["g_done"]["status"] == "completed"
          and a["state"] == "idle" and a["doneCount"] == 2
          and a["label"] == "关联任务已全部完成"
          and a["since"] == T0 - 400, f"{a}")
    a = vs["g_none"]["activity"]
    check("2 no-link goal idles honestly",
          a["state"] == "idle" and a["label"] == "暂无关联任务"
          and a["linkedCount"] == 0 and a["focusTask"] is None
          and a["latestProgress"] is None
          and a["lastActivityAt"] == T0 - 1000
          and a["note"] is None, f"{a}")
    a = vs["g_cancel"]["activity"]
    check("2 cancelled-only idles with count kept",
          a["state"] == "idle" and a["cancelledCount"] == 1,
          f"{a}")

    # Phase 3: gaps noted, never silent
    a = vs["g_missing"]["activity"]
    check("3 link missing from snapshot noted",
          a["state"] == "idle" and a["missingCount"] == 1
          and a["label"] == "关联任务状态暂不可用"
          and a["note"] and "不在当前任务板上" in a["note"],
          f"{a}")
    a = vs["g_mixed"]["activity"]
    check("3 missing does not poison present tasks",
          a["state"] == "running" and a["missingCount"] == 1
          and a["note"] and "不在当前任务板上" in a["note"],
          f"{a}")
    a = vs["g_unknown"]["activity"]
    check("3 unknown raw state counted + noted",
          a["state"] == "idle" and a["note"]
          and "状态未识别" in a["note"], f"{a}")
    with mod._lock:
        feed = mod._feed_meta_locked()
        feed["kanbanPolledAt"] = 0
        feed["taskSnapshot"] = {}
        a = mod._goal_view(
            next(g for g in mod._db["goals"]
                 if g["id"] == "g_run"))["activity"]
    check("3 never-polled snapshot noted",
          a["state"] == "idle" and a["missingCount"] == 2
          and a["note"] and "尚未同步" in a["note"], f"{a}")
    with mod._lock:
        feed = mod._feed_meta_locked()
        feed["kanbanPolledAt"] = T0 - 60
        feed["kanbanNote"] = "任务板读取失败（HTTP 500）"
        a = mod._goal_view(
            next(g for g in mod._db["goals"]
                 if g["id"] == "g_run"))["activity"]
    check("3 poll failure note carried through",
          a["note"] and "任务板读取失败" in a["note"], f"{a}")

    # Phase 4: latest progress + last activity + time order
    mod2 = load_mod(seed())
    vs2 = views(mod2)
    a = vs2["g_run"]["activity"]
    check("4 latestProgress is newest by createdAt",
          a["latestProgress"] == {"text": "较新的进展",
                                  "at": T0 - 100}
          and vs2["g_run"]["latestEntry"]["id"] == "e_r2",
          f"{a}")
    check("4 lastActivityAt is the true max (event wins)",
          a["lastActivityAt"] == T0 - 50, f"{a}")
    a = vs2["g_done"]["activity"]
    check("4 lastActivityAt from completion event",
          a["lastActivityAt"] == T0 - 400
          and a["latestProgress"]["at"] == T0 - 500, f"{a}")
    check("4 polledAt rides along as freshness",
          a["polledAt"] == T0 - 60, f"{a}")

    # Phase 5: read-only proof
    before = {k: copy.deepcopy(mod2._db[k]) for k in
              ("goals", "goalEntries", "goalTaskLinks",
               "feedPosts")}
    with mod2._lock:
        mod2._list_goals()
        g = next(g for g in mod2._db["goals"]
                 if g["id"] == "g_block")
        mod2._goal_view(g)
    check("5 derivation writes no goal/entry/link/post data",
          all(mod2._db[k] == before[k] for k in before))

    # Phase 6: perf at volume
    data = seed()
    bulk_goals, bulk_links, bulk_entries = [], [], []
    snap, titles = {}, {}
    states = ["in_progress", "blocked", "todo", "done",
              "failed", "ready"]
    for i in range(150):
        gid = f"bulk_{i}"
        bulk_goals.append(goal(gid, updated=T0 - 5000))
        for j in range(3):
            tid = f"bt_{i}_{j}"
            bulk_links.append(link(gid, tid, T0 - 4000))
            snap[tid] = states[(i + j) % len(states)]
            titles[tid] = f"批量任务 {tid}"
        bulk_entries.append(
            entry(gid, f"be_{i}", "批量进展", T0 - 3000))
    data["goals"] += bulk_goals
    data["goalTaskLinks"] += bulk_links
    data["goalEntries"] += bulk_entries
    data["meta"]["feed"]["taskSnapshot"] = snap
    data["meta"]["feed"]["taskTitles"] = titles
    mod3 = load_mod(data)
    started = time.perf_counter()
    with mod3._lock:
        items = mod3._list_goals()
    elapsed = time.perf_counter() - started
    print(f"INFO perf: {len(items)} goals derived in "
          f"{elapsed * 1000:.1f} ms")
    check("6 bulk derivation complete + fast (<1s)",
          len(items) == 160
          and all("activity" in g for g in items)
          and elapsed < 1.0, f"{elapsed:.3f}s")
    bulk0 = {g["id"]: g for g in items}["bulk_0"]["activity"]
    check("6 bulk row derived from its own links",
          bulk0["linkedCount"] == 3
          and bulk0["state"] == "blocked", f"{bulk0}")

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
