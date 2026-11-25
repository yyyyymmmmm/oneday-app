#!/usr/bin/env python3
"""Automation facade self-test for oneday_bridge.py (P4+P5,
2026-11-13): cron_create / cron_list / cron_delete,
kanban_create_task / kanban_get_task, reach_send.

A stub Hermes Dashboard (cookie login + cron REST + kanban
plugin API + board) stands in for the real server; the bridge
runs its real HTTP surface on an ephemeral port; the module
clock is patched to pin the proactive window boundaries.

Coverage:
1. tools/list carries exactly the six automation tools.
2. cron_create without ownerSessionId -> error + failed trace
   (owner binding is a hard requirement, no ownerless timers).
3. cron_create ok -> engine payload pins deliver="local",
   binding persisted (memory + data file + reload), ok trace
   with the five elements.
4. cron_list annotates facade jobs; cron_delete refuses a job
   the facade did not create; cron_delete ok removes job +
   binding.
5. Watcher folds a new cron run into cron.fired (ok, then
   failed with the verbatim last_error), exactly once per run;
   a vanished job books cron.orphaned and drops the binding.
6. kanban create requires owner; create+get round-trip; the
   watcher folds a board-side completion into
   kanban.completed exactly once.
7. reach_send: dryRun books the trace only (ledger untouched);
   in-window delivers onto the notification ledger as
   kind=agent_message; out-of-window queues; the watcher
   flushes the queue when the window opens (reach.delivered).
8. Window boundaries: 08:59 out, 09:00 in, 21:29 in, 21:30 out
   (Asia/Shanghai, [09:00, 21:30)).
"""
import importlib.util
import json
import os
import sys
import tempfile
import threading
import urllib.request
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.abspath(__file__))


def _sibling(name):
    p = os.path.join(HERE, name)
    if os.path.exists(p):
        return p
    return os.path.join(HERE, "..", "modules", name)


BRIDGE = _sibling("oneday_bridge.py")
sys.path.insert(0, os.path.dirname(os.path.abspath(BRIDGE)))
KEY = "automation-selftest-key"
TZ = ZoneInfo("Asia/Shanghai")

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


# ------------------------------------------------------------ stub
class Stub:
    def __init__(self):
        self.jobs = {}
        self.tasks = {}
        self.job_seq = 0
        self.task_seq = 0
        self.cron_posts = []
        self.cron_deletes = []
        self.task_posts = []
        self.logins = 0


STUB = Stub()


class StubHandler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj, cookie=False):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        if cookie:
            self.send_header("Set-Cookie", "session=stub; Path=/")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/auth/password-login":
            STUB.logins += 1
            return self._send(200, {"ok": True}, cookie=True)
        if path == "/api/cron/jobs":
            body = self._body()
            STUB.cron_posts.append(body)
            STUB.job_seq += 1
            job = {"id": f"job-{STUB.job_seq}",
                   "name": body.get("name"),
                   "schedule": body.get("schedule"),
                   "prompt": body.get("prompt"),
                   "deliver": body.get("deliver"),
                   "paused": bool(body.get("paused")),
                   "last_run_at": None, "last_status": None,
                   "next_run_at": "2026-11-14T09:00:00+08:00"}
            STUB.jobs[job["id"]] = job
            return self._send(200, job)
        if path == "/api/plugins/kanban/tasks":
            body = self._body()
            STUB.task_posts.append(body)
            STUB.task_seq += 1
            task = {"id": f"t_{STUB.task_seq}",
                    "title": body.get("title"),
                    "status": "todo",
                    "assignee": body.get("assignee"),
                    "priority": body.get("priority", 0),
                    "created_at": "2026-11-13T10:00:00+08:00"}
            STUB.tasks[task["id"]] = task
            return self._send(200, {"task": task})
        return self._send(404, {"detail": "stub: no route"})

    def do_GET(self):
        u = urlparse(self.path)
        path = u.path
        if path == "/api/cron/jobs":
            return self._send(200, list(STUB.jobs.values()))
        if path.startswith("/api/cron/jobs/"):
            job = STUB.jobs.get(path.rsplit("/", 1)[1])
            if job:
                return self._send(200, job)
            return self._send(404, {"detail": "Cron job not found"})
        if path == "/api/plugins/kanban/board":
            return self._send(200, {"tasks": [
                {"id": t["id"], "title": t["title"],
                 "status": t["status"]}
                for t in STUB.tasks.values()]})
        if path.startswith("/api/plugins/kanban/tasks/"):
            task = STUB.tasks.get(path.rsplit("/", 1)[1])
            if task:
                return self._send(200, {"task": task})
            return self._send(404, {"detail": "no such task"})
        return self._send(404, {"detail": "stub: no route"})

    def do_DELETE(self):
        path = urlparse(self.path).path
        if path.startswith("/api/cron/jobs/"):
            jid = path.rsplit("/", 1)[1]
            STUB.cron_deletes.append(jid)
            if jid in STUB.jobs:
                del STUB.jobs[jid]
                return self._send(200, {"ok": True})
            return self._send(404, {"detail": "Cron job not found"})
        return self._send(404, {"detail": "stub: no route"})


# ------------------------------------------------------------ setup
stub_server = ThreadingHTTPServer(("127.0.0.1", 0), StubHandler)
stub_port = stub_server.server_address[1]
threading.Thread(target=stub_server.serve_forever,
                 daemon=True).start()

TMP = tempfile.mkdtemp(prefix="automation-selftest-")
DATA = os.path.join(TMP, "data.json")
LEDGER = os.path.join(TMP, "monitor-notifications.jsonl")
os.environ["ONEDAY_BRIDGE_KEY"] = KEY
os.environ["DATA_PATH"] = DATA
os.environ["HERMES_BASE_URL"] = f"http://127.0.0.1:{stub_port}"
os.environ["HERMES_DASH_USER"] = "stub-user"
os.environ["HERMES_DASH_PASSWORD"] = "stub-pass"
os.environ.pop("HERMES_API_KEY", None)

spec = importlib.util.spec_from_file_location("ob_auto", BRIDGE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod._load()

CLOCK = [datetime(2026, 11, 13, 10, 0, tzinfo=TZ).timestamp()]
mod._now = lambda: CLOCK[0]

bridge = ThreadingHTTPServer(("127.0.0.1", 0), mod.Handler)
bport = bridge.server_address[1]
threading.Thread(target=bridge.serve_forever, daemon=True).start()

_opener = urllib.request.build_opener(
    urllib.request.ProxyHandler({}))


def call(method, path, body=None, key=KEY):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"http://127.0.0.1:{bport}" + path, data=data,
        method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with _opener.open(req, timeout=10) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


_rid = [0]


def tool(name, args=None):
    _rid[0] += 1
    st, resp = call("POST", "/automation-mcp", {
        "jsonrpc": "2.0", "id": _rid[0], "method": "tools/call",
        "params": {"name": name, "arguments": args or {}}})
    assert st == 200, (st, resp)
    result = resp["result"]
    payload = json.loads(result["content"][0]["text"]) \
        if not result.get("isError") else None
    return result.get("isError", False), payload, \
        result["content"][0]["text"]


def traces(action=None):
    q = "?limit=200" + (f"&action={action}" if action else "")
    st, resp = call("GET", "/traces" + q)
    assert st == 200, (st, resp)
    return resp["items"]


def ledger_records():
    if not os.path.exists(LEDGER):
        return []
    return [json.loads(x) for x in
            open(LEDGER, encoding="utf-8") if x.strip()]


def at(day, hh, mm):
    return datetime(2026, 11, day, hh, mm,
                    tzinfo=TZ).timestamp()


# ------------------------------------------------------------ tests
def main():
    # window boundaries (pure function, pinned clock values)
    check("window 08:59 out", not mod._proactive_in_window(at(13, 8, 59)))
    check("window 09:00 in", mod._proactive_in_window(at(13, 9, 0)))
    check("window 21:29 in", mod._proactive_in_window(at(13, 21, 29)))
    check("window 21:30 out", not mod._proactive_in_window(at(13, 21, 30)))

    # 1. tools/list
    _rid[0] += 1
    st, resp = call("POST", "/automation-mcp", {
        "jsonrpc": "2.0", "id": _rid[0], "method": "tools/list"})
    names = [t["name"] for t in resp["result"]["tools"]]
    check("tools/list names exact",
          set(names) == {"cron_create", "cron_list", "cron_delete",
                         "kanban_create_task", "kanban_get_task",
                         "reach_send"} and len(names) == 6,
          str(names))

    # 2. cron_create without owner -> refused + failed trace
    err, _, text = tool("cron_create", {
        "name": "无主任务", "schedule": "0 9 * * *",
        "prompt": "做事"})
    check("cron_create without owner refused", err
          and "ownerSessionId" in text, text)
    tr = traces("cron.create")
    check("refusal booked a failed trace",
          len(tr) == 1 and tr[0]["status"] == "failed"
          and tr[0]["error"], json.dumps(tr, ensure_ascii=False))

    # 3. cron_create ok
    err, view, _ = tool("cron_create", {
        "name": "晨间巡检", "schedule": "0 9 * * 1-5",
        "prompt": "巡检目标进展", "ownerSessionId": "sess-owner-1"})
    check("cron_create ok", not err and view["jobId"] == "job-1",
          str(view))
    post = STUB.cron_posts[-1]
    check("engine payload pins deliver=local",
          post["deliver"] == "local", json.dumps(post))
    check("engine payload defaults timezone",
          post["timezone"] == "Asia/Shanghai", json.dumps(post))
    with mod._lock:
        binds = [dict(b) for b in mod._db["cronBindings"]]
    check("binding stored with owner+echo",
          len(binds) == 1
          and binds[0]["ownerSessionId"] == "sess-owner-1"
          and binds[0]["echoSessionId"] == "sess-owner-1",
          str(binds))
    on_disk = json.load(open(DATA, encoding="utf-8"))
    check("binding persisted to data file",
          len(on_disk.get("cronBindings", [])) == 1)
    tr = traces("cron.create")
    ok_tr = [t for t in tr if t["status"] == "ok"]
    check("cron.create ok trace five elements",
          len(ok_tr) == 1 and ok_tr[0]["target"]["id"] == "job-1"
          and ok_tr[0]["target"]["kind"] == "cron_job"
          and ok_tr[0]["result"] and ok_tr[0]["at"],
          json.dumps(ok_tr, ensure_ascii=False))

    # 4. list / delete discipline
    err, view, _ = tool("cron_list")
    check("cron_list shows the facade job",
          not err and view["count"] == 1
          and view["items"][0]["nextRunAt"], str(view))
    STUB.jobs["job-foreign"] = {
        "id": "job-foreign", "name": "面板任务", "schedule": "0 8 * * *",
        "prompt": "x", "deliver": "local", "paused": False,
        "last_run_at": None, "last_status": None,
        "next_run_at": None}
    err, _, text = tool("cron_delete", {"jobId": "job-foreign"})
    check("cron_delete refuses foreign job", err
          and "job-foreign" in STUB.jobs
          and "job-foreign" not in STUB.cron_deletes, text)

    # 5. watcher cron folds
    job = STUB.jobs["job-1"]
    job["last_run_at"] = "2026-11-13T09:00:00+08:00"
    job["last_status"] = "ok"
    mod._automation_tick()
    fired = traces("cron.fired")
    check("cron.fired ok trace to owner",
          len(fired) == 1 and fired[0]["status"] == "ok"
          and fired[0]["detail"]["ownerSessionId"] == "sess-owner-1",
          json.dumps(fired, ensure_ascii=False))
    mod._automation_tick()
    check("cron.fired exactly once per run",
          len(traces("cron.fired")) == 1)
    job["last_run_at"] = "2026-11-14T09:00:00+08:00"
    job["last_status"] = "error"
    job["last_error"] = "boom verbatim 42"
    mod._automation_tick()
    fired = traces("cron.fired")
    bad = [t for t in fired if t["status"] == "failed"]
    check("cron.fired failed keeps verbatim error",
          len(bad) == 1 and bad[0]["error"] == "boom verbatim 42",
          json.dumps(bad, ensure_ascii=False))
    del STUB.jobs["job-1"]
    mod._automation_tick()
    orph = traces("cron.orphaned")
    with mod._lock:
        binds = list(mod._db["cronBindings"])
    check("vanished job books cron.orphaned + drops binding",
          len(orph) == 1 and orph[0]["status"] == "failed"
          and binds == [], json.dumps(orph, ensure_ascii=False))

    # delete happy path on a fresh job
    err, view, _ = tool("cron_create", {
        "name": "临时任务", "schedule": "every 2h", "prompt": "p",
        "ownerSessionId": "sess-owner-1", "paused": True})
    jid = view["jobId"]
    err, view, _ = tool("cron_delete", {"jobId": jid})
    check("cron_delete ok removes job + binding",
          not err and jid not in STUB.jobs, str(view))
    with mod._lock:
        check("bindings empty after delete",
              mod._db["cronBindings"] == [])

    # 6. kanban
    err, _, text = tool("kanban_create_task", {"title": "无主卡"})
    check("kanban_create without owner refused", err
          and "ownerSessionId" in text, text)
    err, view, _ = tool("kanban_create_task", {
        "title": "核对年会天气", "body": "15 号复核三家预报",
        "ownerSessionId": "sess-owner-1"})
    check("kanban_create ok", not err and view["taskId"] == "t_1",
          str(view))
    check("kanban payload carried title",
          STUB.task_posts[-1]["title"] == "核对年会天气")
    err, view, _ = tool("kanban_get_task", {"taskId": "t_1"})
    check("kanban_get round-trip", not err
          and view["status"] == "todo", str(view))
    STUB.tasks["t_1"]["status"] = "done"
    mod._automation_tick()
    done = traces("kanban.completed")
    check("kanban.completed trace to owner",
          len(done) == 1
          and done[0]["detail"]["ownerSessionId"] == "sess-owner-1",
          json.dumps(done, ensure_ascii=False))
    mod._automation_tick()
    check("kanban.completed exactly once",
          len(traces("kanban.completed")) == 1)

    # 7. reach: dry run first (in-window clock 10:00)
    CLOCK[0] = at(13, 10, 0)
    before = len(ledger_records())
    err, view, _ = tool("reach_send", {
        "text": "干跑消息", "sourceAction": "selftest",
        "refSessionId": "sess-owner-1", "dryRun": True})
    check("reach dryRun delivers nothing",
          not err and view["dryRun"] is True
          and view["delivered"] is False
          and len(ledger_records()) == before, str(view))
    err, view, _ = tool("reach_send", {
        "text": "窗口内消息", "sourceAction": "kanban.completed",
        "refSessionId": "sess-owner-1"})
    recs = ledger_records()
    check("reach in-window lands on the ledger",
          not err and view["delivered"] is True
          and len(recs) == before + 1
          and recs[-1]["kind"] == "agent_message"
          and recs[-1]["body"] == "窗口内消息"
          and recs[-1]["refId"] == "sess-owner-1",
          json.dumps(recs, ensure_ascii=False))
    CLOCK[0] = at(13, 23, 5)
    err, view, _ = tool("reach_send", {
        "text": "深夜排队消息", "sourceAction": "cron.fired",
        "refSessionId": "sess-owner-1"})
    check("reach out-of-window queues, does not send",
          not err and view["queued"] is True
          and len(ledger_records()) == before + 1, str(view))
    with mod._lock:
        q = [x for x in mod._db["proactiveQueue"]
             if x["status"] == "queued"]
    check("queue row stored", len(q) == 1
          and q[0]["body"] == "深夜排队消息", str(q))
    mod._automation_tick()  # still out of window: no flush
    check("no flush while window closed",
          len(ledger_records()) == before + 1)
    CLOCK[0] = at(14, 9, 30)
    mod._automation_tick()
    recs = ledger_records()
    with mod._lock:
        q = [x for x in mod._db["proactiveQueue"]
             if x["body"] == "深夜排队消息"]
    dl = traces("reach.delivered")
    check("flush on window open delivers + books trace",
          len(recs) == before + 2
          and recs[-1]["body"] == "深夜排队消息"
          and q and q[0]["status"] == "sent"
          and len(dl) == 1 and dl[0]["status"] == "ok",
          json.dumps(dl, ensure_ascii=False))
    sends = traces("reach.send")
    check("every reach_send booked a trace",
          len([t for t in sends if t["status"] == "ok"]) == 3,
          str(len(sends)))

    # 8. persistence across reload
    spec2 = importlib.util.spec_from_file_location("ob_auto2",
                                                   BRIDGE)
    mod2 = importlib.util.module_from_spec(spec2)
    spec2.loader.exec_module(mod2)
    mod2._load()
    check("reload keeps bindings/queue/traces",
          isinstance(mod2._db["cronBindings"], list)
          and len(mod2._db["proactiveQueue"]) == 1
          and len(mod2._db["traces"]) >= 8,
          f"queue={len(mod2._db['proactiveQueue'])} "
          f"traces={len(mod2._db['traces'])}")

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
