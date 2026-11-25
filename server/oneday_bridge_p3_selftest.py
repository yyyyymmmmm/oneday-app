#!/usr/bin/env python3
"""P3 self-test for oneday_bridge.py feed changes.

Phase A: HTTP contract against a subprocess bridge (temp data
preseeded with one idea + one briefing + one monitor change from
"today", no Hermes key): the segment-one assembler folds them
into one digest post on the scheduler tick; read/delete/generate
endpoints behave; a morning round without HERMES_API_KEY records
itself as skipped, never as a post.
Phase B: in-process morning round with stubbed Hermes runs:
fake-ref output drops the whole post, {"skip": true} records an
honest empty round, and a valid output lands as kind=morning.
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

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "oneday_bridge.py")
KEY = "p3-selftest-key"
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


def phase_a():
    tmp = tempfile.mkdtemp(prefix="p3a-")
    now = time.time()
    seed = {
        "goals": [{"id": "g_t1", "title": "自测目标", "note": "",
                   "milestones": [], "createdAt": now - 86400,
                   "updatedAt": now - 86400, "status": "active",
                   "completedAt": None, "parentId": None,
                   "source": "manual"}],
        "ideas": [{"id": "i_t1", "title": "自测点子", "detail": "d",
                   "goalId": None, "createdAt": now, "source": "manual",
                   "evidence": None, "evidenceRef": None,
                   "status": "pending", "taskId": None,
                   "expiresAt": None}],
        "monitors": [{"id": "m_t1", "name": "自测监测",
                      "target": "https://example.com",
                      "enabled": False, "nextRunAt": None,
                      "createdAt": now - 86400, "updatedAt": now}],
        "changes": [{"id": "c_t1", "monitorId": "m_t1",
                     "detectedAt": now, "summary": "页面变了",
                     "before": "a", "after": "b", "read": False}],
        "goalEntries": [],
        "briefings": [{"id": "b_t1", "goalId": "g_t1",
                       "period": "2026-W46", "title": "自测简报",
                       "body": "x", "createdAt": now}],
        "feedPosts": [],
        "meta": {},
    }
    with open(os.path.join(tmp, "data.json"), "w",
              encoding="utf-8") as f:
        json.dump(seed, f, ensure_ascii=False)
    env = dict(os.environ, ONEDAY_BRIDGE_KEY=KEY,
               DATA_PATH=os.path.join(tmp, "data.json"),
               ONEDAY_PORT=str(PORT))
    env.pop("HERMES_API_KEY", None)
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
        s, body = call("GET", "/feed", key="wrong")
        check("A feed requires auth", s == 401, f"{s}")
        digest = None
        for _ in range(40):
            s, body = call("GET", "/feed")
            if s == 200 and body.get("items"):
                digest = body["items"][0]
                break
            time.sleep(2)
        check("A digest post assembled", digest is not None)
        if digest:
            check("A digest kind", digest["kind"] == "digest")
            check("A digest counts 3 events",
                  "3 件" in digest["title"], digest["title"])
            refs = {(r["type"], r["id"]) for r in digest["refs"]}
            check("A briefing ref carries goalId",
                  any(r["type"] == "briefing"
                      and r.get("goalId") == "g_t1"
                      for r in digest["refs"]))
            check("A digest refs cover idea/briefing/monitor",
                  refs == {("idea", "i_t1"), ("briefing", "b_t1"),
                           ("monitor", "m_t1")}, f"{refs}")
            check("A digest unread", digest["readAt"] is None)
            pid = digest["id"]
            s, got = call("GET", f"/feed/{pid}")
            check("A get one post", s == 200
                  and got["id"] == pid, f"{s}")
            s, read = call("POST", f"/feed/{pid}/read")
            check("A read settles readAt",
                  s == 200 and read["readAt"] is not None, f"{s}")
            s, gen = call("GET", "/feed/generation")
            check("A ledger assembly eventsToday=3",
                  s == 200
                  and gen["assembly"]["eventsToday"] == 3
                  and gen["unread"] == 0, f"{s} {gen}")
            s, _ = call("POST", "/feed/generate")
            check("A manual morning trigger accepted", s == 202,
                  f"{s}")
            skipped = False
            for _ in range(30):
                s, gen = call("GET", "/feed/generation")
                hist = gen["morning"]["history"]
                if hist and hist[-1]["status"] == "skipped":
                    skipped = True
                    break
                time.sleep(1)
            check("A morning without key records skipped", skipped)
            s, body = call("GET", "/feed")
            check("A skipped round made no post",
                  all(p["kind"] != "morning"
                      for p in body["items"]))
            s, _ = call("DELETE", f"/feed/{pid}")
            check("A delete ok", s == 200, f"{s}")
            s, _ = call("GET", f"/feed/{pid}")
            check("A deleted post 404s", s == 404, f"{s}")
        s, _ = call("GET", "/feed/nope")
        check("A unknown post 404s", s == 404, f"{s}")
    finally:
        proc.terminate()
        proc.wait(timeout=10)


def phase_b():
    tmp = tempfile.mkdtemp(prefix="p3b-")
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    os.environ["HERMES_API_KEY"] = "fake-key"
    spec = importlib.util.spec_from_file_location("ob_b", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    with mod._lock:
        mod._db["ideas"].append({
            "id": "i_b1", "title": "B 点子", "detail": "d",
            "goalId": None, "createdAt": mod._now(),
            "source": "manual", "evidence": None,
            "evidenceRef": None, "status": "pending",
            "taskId": None, "expiresAt": None})
        mod._save_locked()
    mod._fetch_recent_sessions = lambda: ([], "桩：无会话")
    mod._fetch_kanban_tasks = lambda: ({}, "桩：无任务板")
    outputs = []

    def fake_submit(prompt, idem):
        return "run_b", None

    def fake_poll(run_id):
        return outputs.pop(0), None

    mod._hermes_submit_run = fake_submit
    mod._hermes_poll_run = fake_poll

    def history():
        with mod._lock:
            return list(mod._db["meta"]["feedGen"]["history"])

    def posts():
        with mod._lock:
            return list(mod._db["feedPosts"])

    outputs.append(json.dumps({
        "title": "假引用帖", "body": "正文", "why": "理由",
        "links": [], "refs": [{"type": "idea", "id": "i_FAKE"}]},
        ensure_ascii=False))
    mod._run_morning_round("manual")
    check("B fake ref drops whole post",
          len(posts()) == 0 and history()[-1]["status"] == "failed"
          and "引用" in (history()[-1]["error"] or ""),
          f"{history()[-1] if history() else None}")

    outputs.append(json.dumps({"skip": True, "reason": "没素材"},
                              ensure_ascii=False))
    mod._run_morning_round("manual")
    check("B skip records honest empty round",
          len(posts()) == 0 and history()[-1]["status"] == "empty"
          and history()[-1].get("skipReason") == "没素材",
          f"{history()[-1]}")

    outputs.append(json.dumps({
        "title": "真晨报", "body": "正文内容", "why": "因为值得",
        "links": [{"title": "示例", "url": "https://example.com/x"},
                  {"title": "坏链", "url": "ftp://nope"}],
        "refs": [{"type": "idea", "id": "i_b1"}]},
        ensure_ascii=False))
    mod._run_morning_round("manual")
    ps = posts()
    check("B valid output lands as morning",
          len(ps) == 1 and ps[0]["kind"] == "morning"
          and history()[-1]["status"] == "ok", f"{ps}")
    if ps:
        check("B links filtered to http(s)",
              ps[0]["links"] == [{"title": "示例",
                                  "url": "https://example.com/x"}],
              f"{ps[0]['links']}")
        check("B post refs/why/expiry settled",
              ps[0]["refs"] == [{"type": "idea", "id": "i_b1"}]
              and ps[0]["why"] == "因为值得"
              and ps[0]["expiresAt"] > ps[0]["createdAt"]
              and ps[0]["readAt"] is None)




def phase_c():
    """Remote-poll diffs: kanban baseline stays silent, a status
    change + a new task become events; approvals only speak up
    on increases."""
    tmp = tempfile.mkdtemp(prefix="p3c-")
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    os.environ["HERMES_API_KEY"] = "fake-key"
    spec = importlib.util.spec_from_file_location("ob_c", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    boards = [({"t1": ("任务一", "todo")}, None),
              ({"t1": ("任务一", "done"),
                "t2": ("任务二", "todo")}, None)]
    mod._fetch_kanban_tasks = lambda: boards.pop(0)
    counts = [1, 2, 1]
    mod._http_json = lambda url, **kw: (
        200, {"counts": {"memory": counts.pop(0), "skills": 0}}, "")
    mod._feed_poll_remote()
    with mod._lock:
        feed = mod._feed_meta_locked()
        ev1 = list(feed["events"])
    check("C baseline poll silent",
          ev1 == [] and feed["approvalTotal"] == 1
          and feed["taskSnapshot"] == {"t1": "todo"}, f"{ev1}")
    mod._feed_poll_remote()
    with mod._lock:
        feed = mod._feed_meta_locked()
        kinds = sorted(e["kind"] for e in feed["events"])
        texts = " ".join(e["text"] for e in feed["events"])
    check("C changes become events",
          kinds == ["approval", "task", "task"], f"{kinds}")
    check("C event texts carry facts",
          "状态变为 done" in texts and "新任务" in texts
          and "2 项待审批" in texts, texts)
    boards.append(({"t1": ("任务一", "done"),
                    "t2": ("任务二", "todo")}, None))
    mod._feed_poll_remote()
    with mod._lock:
        n = len(mod._feed_meta_locked()["events"])
    check("C approval decrease stays silent", n == 3, f"{n}")


if __name__ == "__main__":
    phase_a()
    phase_b()
    phase_c()
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
