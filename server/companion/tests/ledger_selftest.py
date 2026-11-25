#!/usr/bin/env python3
"""Work-ledger self-test (work-ledger-design-20261110.md).

Part A: in-process core (modules/ledger.py) with a fake clock --
  the C-4 single-source contract (2026-11-14): the App report
  is the only writer of run items, a lost terminal is never
  fabricated (the zombie ladder flags and stales instead), an
  idle collector invents nothing, terminal correction by
  event order (B-02: no evidence ranks), the title chain, the board is NOT
  mirrored, approvals land from decision events only, device
  events are one line one item (no window correlation), the
  corrupt-line quarantine, compaction, summary/since reads and
  the App report shapes.
Part B: HTTP contract -- a real oneday_bridge subprocess
against a fake Hermes: App report -> terminal report settles
(the collector no longer settles from the transcript, and the
board is not mirrored), list/detail/summary/health shapes.
Part C: the panel front proxies /api/companion/ledger as
counts only -- no item titles anywhere in the payload.
Part D: the monitor source (A-05 single-stream) -- a change
seeded straight into the bridge change store (no write hook
fired, the pre-1.0.64 world) is backfilled by the collector
reconcile into the ledger in the canonical client-synthesis
shape (kind=monitor, monitor-change: id, summary title with
monitor-name fallback); the pass is idempotent; a live
check-detected change lands via the hook in the same shape;
monitor lines never count as in-progress work in the summary.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import urllib.error
from datetime import timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TZ = timezone(timedelta(hours=8))

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def _load_ledger_mod():
    for cand in (os.path.join(HERE, "ledger.py"),
                 os.path.join(ROOT, "modules", "ledger.py")):
        if os.path.exists(cand):
            spec = importlib.util.spec_from_file_location(
                "ledger", cand)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            return mod
    raise RuntimeError("ledger.py not found")


L = _load_ledger_mod()
T0 = 1_700_000_000.0


class Clock:
    def __init__(self, t=T0):
        self.t = t

    def __call__(self):
        return self.t

    def advance(self, seconds):
        self.t += seconds


_ENV_N = [0]


def make_env(tmp):
    # One events file per scenario: sharing a file across
    # stores leaks items and cursors between scenarios.
    _ENV_N[0] += 1
    clock = Clock()
    store = L.LedgerStore(
        os.path.join(tmp, f"ledger-{_ENV_N[0]}.jsonl"),
        now_fn=clock, tz=TZ)
    col = L.Collector(store, tz=TZ, now_fn=clock)
    return clock, store, col


def cycle_slow(col):
    """One collector cycle. (Pre-C-4 this ran SLOW_STEP_EVERY
    cycles so the every-4th-cycle approvals/device steps fired;
    event ingestion now runs on every cycle.)"""
    col.cycle()


def part_a():
    tmp = tempfile.mkdtemp(prefix="ledger-a-")

    # -- A1 single source: the App report is the only writer -------
    clock, store, col = make_env(tmp)
    item, _ = L.apply_app_report(store, {
        "runId": "R1", "sessionId": "S1",
        "titleSeed": "帮我查一下天气\n第二行不要",
        "startedAt": T0}, tz=TZ)
    check("A1 report creates running item",
          item["status"] == "running"
          and item["origin"] == "reported")
    check("A1 title is the user's first line verbatim",
          item["title"] == "帮我查一下天气"
          and item["titleSource"] == "user_excerpt",
          str(item.get("title")))
    L.apply_app_report(store, {
        "runId": "R1", "terminal": "completed",
        "endedAt": T0 + 30}, tz=TZ)
    seq_after_report = store.seq
    col.cycle()
    it = store.get("run:R1")
    check("A1 terminal report settles the item",
          it["status"] == "completed"
          and it["endedAt"] == T0 + 30)
    check("A1 collector adds nothing (no second writer)",
          len([i for i in store.items.values()
               if i.get("sessionId") == "S1"]) == 1
          and it["lastSeq"] == seq_after_report
          and not any(h.get("by") == "collector"
                      for h in it["history"]))

    # -- A2 lost terminal: never fabricated, ladder to stale --------
    clock, store, col = make_env(tmp)
    L.apply_app_report(store, {
        "runId": "R2", "sessionId": "S2", "titleSeed": "写封邮件",
        "startedAt": T0}, tz=TZ)
    clock.advance(600)
    col.cycle()
    it = store.get("run:R2")
    check("A2 lost terminal stays running (no transcript rescue)",
          it["status"] == "running")
    clock.advance(1201)  # 1801 total
    col.cycle()
    it = store.get("run:R2")
    check("A2 silence past the stale threshold marks stale",
          it["status"] == "stale", str(it["status"]))

    # -- A3 no discovery: an idle collector writes nothing ----------
    clock, store, col = make_env(tmp)
    for _ in range(3):
        col.cycle()
    check("A3 collector invents no items on its own",
          store.items == {}, str(store.items))

    # -- A4 terminal conflicts ---------------------------------------
    clock, store, col = make_env(tmp)
    # (a) the App's own terminal stands; nothing corrects it
    L.apply_app_report(store, {
        "runId": "R4a", "sessionId": "S4a", "titleSeed": "活a",
        "startedAt": T0}, tz=TZ)
    L.apply_app_report(store, {
        "runId": "R4a", "terminal": "failed",
        "error": "网络错误", "endedAt": T0 + 10}, tz=TZ)
    col.cycle()
    it = store.get("run:R4a")
    check("A4a App failure stands (no later report corrects it)",
          it["status"] == "failed"
          and it.get("correctedBy") is None, str(it))
    # (b) same for a completion
    L.apply_app_report(store, {
        "runId": "R4b", "sessionId": "S4b", "titleSeed": "活b",
        "startedAt": T0}, tz=TZ)
    L.apply_app_report(store, {
        "runId": "R4b", "terminal": "completed",
        "endedAt": T0 + 10}, tz=TZ)
    col.cycle()
    it = store.get("run:R4b")
    check("A4b App completion stands",
          it["status"] == "completed")
    # (c) B-02: no evidence ranks -- a later direct report of a
    # different terminal CORRECTS the earlier one, by event
    # order, and the correction is on the record
    job, _ = store.create_or_merge({
        "id": "job:test:1", "kind": "job", "source": "bridge",
        "title": "点子生成 · 1月1日", "titleSource": "job_name",
        "status": "running", "startedAt": T0,
        "origin": "bridge_self", "by": "bridge"})
    store.set_status("job:test:1", "completed", by="bridge",
                     ended_at=T0 + 5)
    res = store.set_status("job:test:1", "failed", by="app")
    it = store.get("job:test:1")
    check("A4c later terminal report corrects by event order",
          res == "ok" and it["status"] == "failed"
          and it.get("correctedBy") == "app"
          and any(h.get("corrected") for h in it["history"]))
    # (d) ...but a terminal still cannot move back to a
    # non-terminal state (transition table, not a ranking)
    res = store.set_status("job:test:1", "running", by="app")
    it = store.get("job:test:1")
    check("A4d terminal cannot revive to running",
          res == "invalid" and it["status"] == "failed")

    # -- A5 zombie ladder on a reported run ----------------------------
    clock, store, col = make_env(tmp)
    L.apply_app_report(store, {
        "runId": "R5", "sessionId": "S5", "titleSeed": "一个长任务",
        "startedAt": T0}, tz=TZ)
    iid = "run:R5"
    clock.advance(46)
    col.cycle()
    it = store.get(iid)
    check("A5 +46s: still running, evidence-lagging flagged",
          it["status"] == "running"
          and it["evidenceLagging"] is True)
    clock.advance(555)  # +601 total
    col.cycle()
    it = store.get(iid)
    check("A5 +601s: check window is grace, no stale yet",
          it["status"] == "running")
    clock.advance(1200)  # +1801 total
    col.cycle()
    it = store.get(iid)
    check("A5 +1801s: stale, spinner stops, not completed",
          it["status"] == "stale", str(it["status"]))
    L.apply_app_report(store, {
        "runId": "R5", "terminal": "completed",
        "endedAt": T0 + 1900}, tz=TZ)
    it = store.get(iid)
    check("A5 revival: a late direct report settles the stale item",
          it["status"] == "completed"
          and it["endedAt"] == T0 + 1900, str(it))

    # -- A6 title chain -----------------------------------------------
    t, s = L.resolve_title(server_title="真标题",
                           server_title_grade="llm",
                           user_text="用户的话", started_at=T0,
                           tz=TZ)
    check("A6 llm server title wins", (t, s) == ("真标题",
                                                 "server_llm"))
    t, s = L.resolve_title(server_title="派生占位",
                           server_title_grade="derived",
                           user_text="用户原话第一行\n第二行",
                           started_at=T0, tz=TZ)
    check("A6 derived grade skipped for the excerpt",
          (t, s) == ("用户原话第一行", "user_excerpt"))
    long_line = "一二三四五六七八九十" * 4
    t, s = L.resolve_title(user_text=long_line, started_at=T0,
                           tz=TZ)
    check("A6 excerpt truncates verbatim at 30 + ellipsis",
          t == long_line[:30] + "…" and len(t) == 31, t)
    t, s = L.resolve_title(registered_name="点子生成",
                           started_at=T0, tz=TZ)
    check("A6 registered name", (t, s) == ("点子生成", "job_name"))
    t, s = L.resolve_title(started_at=T0, tz=TZ)
    from datetime import datetime as _dt
    expect = "未命名任务 · " + _dt.fromtimestamp(
        T0, tz=TZ).strftime("%H:%M")
    check("A6 fallback is unnamed + time, never invented",
          (t, s) == (expect, "fallback"), t)
    status, reason = L.classify_failure("")
    check("A6 no-evidence failure files as 原因未明",
          status == "failed"
          and reason["category"] == "原因未明")
    status, reason = L.classify_failure(
        "生成触发了待审批动作，已中止本轮")
    check("A6 approval abort is a cancellation",
          status == "cancelled"
          and reason["category"] == "被审批中止")

    # -- A7 the board is not mirrored ----------------------------------
    clock, store, col = make_env(tmp)
    col.cycle()
    check("A7 kanban state never enters the book",
          store.get("task:T1") is None and store.items == {})

    # -- A8 approvals: decision events only ------------------------------
    clock, store, col = make_env(tmp)
    dec_path = os.path.join(tmp, "decisions.jsonl")
    aud_path = os.path.join(tmp, "audit.jsonl")
    col.decisions_path = dec_path
    col.device_audit_path = aud_path
    col.cycle()
    check("A8 undecided approvals are not mirrored",
          store.get("appr:P1") is None)
    with open(dec_path, "w", encoding="utf-8") as f:
        f.write(json.dumps({
            "id": "P1", "subsystem": "memory", "summary": "记住一件事",
            "created_at": "2023-11-14T22:00:00+00:00",
            "decided_at": "2023-11-14T22:05:00+00:00",
            "decision": "approved"}, ensure_ascii=False) + "\n")
    col.cycle()
    it = store.get("appr:P1")
    check("A8 decision event lands the approval decided",
          it is not None and it["status"] == "completed"
          and it["origin"] == "reported", str(it))
    with open(dec_path, "a", encoding="utf-8") as f:
        f.write(json.dumps({
            "id": "P2", "subsystem": "skills",
            "summary": "把周报技能改一下",
            "created_at": "2023-11-14T22:00:00+00:00",
            "decided_at": "2023-11-14T22:06:00+00:00",
            "decision": "rejected"}, ensure_ascii=False) + "\n")
    col.cycle()
    it = store.get("appr:P2")
    check("A8 rejection cancels with the approval category",
          it["status"] == "cancelled"
          and it["failReason"]["category"] == "被审批中止")
    col.cycle()
    n_appr = len([i for i in store.items.values()
                  if i["kind"] == "approval"])
    check("A8 cursor: a second pass reprocesses nothing",
          n_appr == 2, str(n_appr))

    # -- A9 device events: one line, one item ------------------------------
    clock, store, col = make_env(tmp)
    col.device_audit_path = aud_path
    L.apply_app_report(store, {
        "runId": "R9", "sessionId": "S9", "titleSeed": "查联系人",
        "startedAt": T0}, tz=TZ)
    with open(aud_path, "w", encoding="utf-8") as f:
        f.write(json.dumps({"ts": T0 + 10, "callId": "C1",
                            "tool": "contacts_search",
                            "source": "mcp", "status": "ok"})
                + "\n")
    col.cycle()
    it = store.get("dev:C1")
    check("A9 in-run device call is its own item (no folding)",
          it is not None and it["status"] == "completed"
          and it["kind"] == "device"
          and store.get("run:R9")["counts"].get("toolCalls")
          is None, str(it))
    with open(aud_path, "a", encoding="utf-8") as f:
        f.write(json.dumps({"ts": T0 + 5000, "callId": "C2",
                            "tool": "calendar_list",
                            "source": "mcp", "status": "ok"})
                + "\n")
    col.cycle()
    it = store.get("dev:C2")
    check("A9 standalone device call becomes its own item",
          it is not None and it["status"] == "completed"
          and it["kind"] == "device", str(it))
    L.apply_app_report(store, {
        "runId": "R9b", "sessionId": "S9b", "titleSeed": "另一个",
        "startedAt": T0 + 4990}, tz=TZ)
    L.apply_app_report(store, {
        "runId": "R9c", "sessionId": "S9c", "titleSeed": "再一个",
        "startedAt": T0 + 4995}, tz=TZ)
    with open(aud_path, "a", encoding="utf-8") as f:
        f.write(json.dumps({"ts": T0 + 5005, "callId": "C3",
                            "tool": "motion_summary",
                            "source": "mcp", "status": "ok"})
                + "\n")
    col.cycle()
    check("A9 overlapping runs no longer make a call ambiguous",
          store.get("dev:C3") is not None
          and "ambiguousDeviceCalls" not in col.state)

    # -- A10 corrupt line quarantine --------------------------------------
    bad_path = os.path.join(tmp, "bad-events.jsonl")
    good_item = {"id": "run:X1", "kind": "run", "source": "app",
                 "title": "活", "titleSource": "user_excerpt",
                 "status": "running", "startedAt": T0,
                 "endedAt": None, "lastEvidenceAt": T0,
                 "origin": "reported", "link": None,
                 "counts": {}, "failReason": None, "history": []}
    with open(bad_path, "w", encoding="utf-8") as f:
        f.write(json.dumps({"type": "meta", "bornAt": T0})
                + "\n")
        f.write(json.dumps({"type": "created", "seq": 1,
                            "item": good_item}) + "\n")
        f.write('{"type": "created", BROKEN\n')
        f.write(json.dumps({"type": "created", "seq": 2,
                            "item": dict(good_item,
                                         id="run:X2")}) + "\n")
    store2 = L.LedgerStore(bad_path, now_fn=Clock(), tz=TZ)
    check("A10 corrupt line degrades, prefix survives",
          bool(store2.degraded_reason)
          and store2.get("run:X1") is not None
          and store2.get("run:X2") is None)
    check("A10 original quarantined, never deleted",
          any("corrupt-" in n for n in os.listdir(tmp)))
    try:
        store2.create_or_merge(dict(good_item, id="run:X3"))
        refused = False
    except L.LedgerError:
        refused = True
    check("A10 degraded store refuses writes", refused)

    # -- A11 compaction -----------------------------------------------------
    clock, store, col = make_env(tmp)
    store.create_or_merge({
        "id": "run:OLD", "kind": "run", "source": "app",
        "title": "旧活", "titleSource": "user_excerpt",
        "status": "completed", "startedAt": T0 - 100,
        "endedAt": T0, "origin": "reported", "by": "app"})
    store.create_or_merge({
        "id": "run:LIVE", "kind": "run", "source": "app",
        "title": "在干的", "titleSource": "user_excerpt",
        "status": "running", "startedAt": T0 - 100,
        "origin": "reported", "by": "app"})
    clock.advance(31 * 24 * 3600)
    dropped = store.compact(clock())
    check("A11 compaction drops old terminal, keeps the live",
          dropped == 1 and store.get("run:OLD") is None
          and store.get("run:LIVE") is not None)
    store2 = L.LedgerStore(store.path, now_fn=clock, tz=TZ)
    check("A11 compacted log replays to the same snapshot",
          store2.get("run:LIVE") is not None
          and store2.get("run:OLD") is None
          and store2.born_at == store.born_at)

    # -- A12 summary + since --------------------------------------------
    clock, store, col = make_env(tmp)
    L.apply_app_report(store, {
        "runId": "R12", "sessionId": "S12", "titleSeed": "活",
        "startedAt": T0}, tz=TZ)
    store.create_or_merge({
        "id": "appr:P12", "kind": "approval", "source": "bridge",
        "title": "批一下", "titleSource": "record_excerpt",
        "status": "blocked_approval", "startedAt": T0,
        "origin": "reported", "by": "collector"})
    col.cycle()
    s = store.summary(clock())
    check("A12 summary counts agree with the book",
          s["inProgress"] == 1 and s["blockedApproval"] == 1
          and s["total"] == 2, str(s))
    seq_now = store.seq
    check("A12 changes_since is empty at the head, full from 0",
          store.changes_since(seq_now) == []
          and len(store.changes_since(0)) == 2)

    # -- A13 report shapes -----------------------------------------------------
    clock, store, col = make_env(tmp)
    item, _ = L.apply_app_report(store, {
        "runId": "R13", "stillRunning": True,
        "startedAt": T0}, tz=TZ)
    check("A13 heartbeat for an unknown run opens a minimal item",
          item is not None and item["status"] == "running")
    item, _ = L.apply_app_report(store, {
        "runId": "R13b", "terminal": "cancelled",
        "titleSeed": "算了不做了", "startedAt": T0,
        "endedAt": T0 + 5}, tz=TZ)
    check("A13 terminal-first report lands terminal, user-stop",
          item["status"] == "cancelled"
          and item["failReason"]["category"] == "用户停止",
          str(item))
    try:
        L.apply_app_report(store, {"terminal": "completed"},
                           tz=TZ)
        ok = False
    except L.LedgerError as e:
        ok = e.status == 400
    check("A13 report without runId is a 400", ok)



# --- Part B/C: HTTP contract -----------------------------------------

BPORT = 8646           # front's module table pins oneday to 8646
HPORT = 18993
FPORT = 18651
BKEY = "ledger-test-key"
T0B = int(time.time())
B_MSGS = [
    {"role": "user", "created_at": T0B,
     "content": "帮我写封邮件"},
    {"role": "assistant", "created_at": T0B + 20,
     "content": "写好了"},
]


class FakeHermesB(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self._json(200, {"status": "ok"})
        if self.path.startswith("/api/sessions/") \
                and self.path.endswith("/messages"):
            return self._json(200, {"messages": B_MSGS})
        if self.path.startswith("/api/sessions"):
            return self._json(200, {"sessions": [{
                "id": "sess-b1", "title": "",
                "message_count": len(B_MSGS),
                "started_at": T0B}]})
        if self.path.startswith("/api/plugins/kanban/board"):
            return self._json(200, {"columns": {"todo": {
                "tasks": [{"id": "kb1", "title": "整理发票",
                           "status": "todo"}]}}})
        if self.path.startswith("/v1/runs/"):
            return self._json(404, {"error": "no such run"})
        return self._json(404, {})

    def do_POST(self):
        if self.path == "/auth/password-login":
            return self._json(200, {"ok": True})
        return self._json(404, {})


def call(method, url, body=None, key=None, timeout=10):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}
    except Exception as e:
        return 0, {"_error": str(e)}


def wait_until(fn, timeout=25, interval=0.4):
    end = time.time() + timeout
    while time.time() < end:
        v = fn()
        if v:
            return v
        time.sleep(interval)
    return None


def part_b():
    tmp = tempfile.mkdtemp(prefix="ledger-b-")
    fake = ThreadingHTTPServer(("127.0.0.1", HPORT), FakeHermesB)
    threading.Thread(target=fake.serve_forever, daemon=True).start()
    bridge_py = next(
        (p for p in (os.path.join(HERE, "oneday_bridge.py"),
                     os.path.join(ROOT, "modules",
                                  "oneday_bridge.py"))
         if os.path.exists(p)), None)
    env = dict(os.environ)
    env.update({
        "ONEDAY_BRIDGE_KEY": BKEY, "ONEDAY_PORT": str(BPORT),
        "DATA_PATH": os.path.join(tmp, "data.json"),
        "HERMES_BASE_URL": f"http://127.0.0.1:{HPORT}",
        "HERMES_API_KEY": "fake-api-key",
        "HERMES_DASH_USER": "admin",
        "HERMES_DASH_PASSWORD": "fake",
        "LEDGER_COLLECTOR_SECONDS": "1",
        "LEDGER_DECISIONS_PATH": os.path.join(tmp,
                                              "decisions.jsonl"),
        "LEDGER_DEVICE_AUDIT_PATH": os.path.join(tmp,
                                                 "audit.jsonl"),
        "PYTHONPATH": os.path.dirname(bridge_py),
    })
    bridge = subprocess.Popen(
        [sys.executable, bridge_py], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True)
    front = None
    try:
        base = f"http://127.0.0.1:{BPORT}"
        ok = wait_until(
            lambda: call("GET", base + "/health")[0] == 200, 30)
        check("B bridge boots", bool(ok))
        code, health = call("GET", base + "/health")
        check("B health exposes collector + ledger blocks",
              "collector" in health and "ledger" in health
              and health["ledger"].get("degraded") is False,
              str(health))
        code, _ = call("POST", base + "/ledger/report",
                       {"runId": "x"})
        check("B report without the key is 401", code == 401)
        code, body = call("POST", base + "/ledger/report", {
            "runId": "run-b1", "sessionId": "sess-b1",
            "titleSeed": "帮我写封邮件", "startedAt": T0B},
            key=BKEY)
        check("B start report accepted",
              code == 200
              and body["item"]["status"]
              in ("running", "completed"),
              str(body))
        code, body = call("GET", base + "/ledger", key=BKEY)
        sess_items = [i for i in body.get("items", [])
                      if i.get("sessionId") == "sess-b1"]
        check("B one book line for the turn (single source) "
              "+ freshness fields",
              len(sess_items) == 1
              and "collectorHeartbeatAt" in body
              and "snapshotSeq" in body, str(sess_items))

        def settled():
            c, lst = call("GET", base + "/ledger", key=BKEY)
            if c != 200:
                return None
            for i in lst.get("items", []):
                if i.get("sessionId") == "sess-b1" \
                        and i.get("status") == "completed":
                    c2, d = call(
                        "GET", base + "/ledger/" + i["id"],
                        key=BKEY)
                    return d if c2 == 200 else None
            return None

        # C-4: the collector no longer settles from the
        # transcript -- after several 1 s ticks the run is still
        # exactly what the App reported: running.
        time.sleep(3)
        code, body = call("GET", base + "/ledger", key=BKEY)
        still = [i for i in body.get("items", [])
                 if i.get("sessionId") == "sess-b1"]
        check("B collector does not settle from the transcript",
              len(still) == 1
              and still[0]["status"] == "running",
              str(still))
        code, _ = call("POST", base + "/ledger/report", {
            "runId": "run-b1", "terminal": "completed",
            "endedAt": T0B + 20}, key=BKEY)
        detail = wait_until(settled, 30)
        check("B terminal report settles the run",
              code == 200 and detail is not None)
        if detail:
            check("B endedAt is the report's settle time",
                  detail.get("endedAt") == T0B + 20,
                  str(detail.get("endedAt")))
            check("B detail carries the flow history",
                  any(h.get("to") == "completed"
                      for h in detail.get("history", [])))
        # C-4: the board is not mirrored into the book.
        time.sleep(2)
        code, _ = call("GET", base + "/ledger/task:kb1", key=BKEY)
        check("B kanban task is not mirrored into the book",
              code == 404, str(code))
        code, summary = call("GET", base + "/ledger/summary",
                             key=BKEY)
        check("B summary is counts-only + heartbeat",
              code == 200 and "items" not in summary
              and summary.get("todayCompleted", 0) >= 1
              and summary.get("collectorHeartbeatAt"),
              str(summary))
        code, body = call("GET", base + "/ledger", key=BKEY)
        seq = body["snapshotSeq"]
        time.sleep(2.5)
        code, incr = call("GET",
                          base + f"/ledger?since={seq}", key=BKEY)
        check("B since-incremental is quiet when nothing changed",
              code == 200 and incr.get("items") == [],
              str(incr.get("items")))

        # -- Part C: panel proxy, counts only ----------------------
        fenv = dict(os.environ)
        fenv.update({
            "COMPANION_FRONT_PORT": str(FPORT),
            "COMPANION_SERVICE_KEY": "svc-ledger-key",
            "ONEDAY_BRIDGE_KEY": BKEY,
            "HERMES_BASE": f"http://127.0.0.1:{HPORT}",
            "COMPANION_STATE_DIR": os.path.join(tmp, "fstate"),
            "COMPANION_ONEDAY_DATA": os.path.join(tmp,
                                                  "data.json"),
            "COMPANION_DECISIONS_PATH": os.path.join(
                tmp, "decisions.jsonl"),
        })
        front = subprocess.Popen(
            [sys.executable, os.path.join(ROOT, "front",
                                          "front.py")],
            env=fenv, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True)
        fbase = f"http://127.0.0.1:{FPORT}/api/companion"
        up = wait_until(
            lambda: call("GET", fbase + "/ledger",
                         key="svc-ledger-key")[0] == 200, 30)
        check("C front /ledger proxy answers", bool(up))
        code, body = call("GET", fbase + "/ledger",
                          key="svc-ledger-key")
        raw = json.dumps(body, ensure_ascii=False)
        check("C panel payload is counts only, no titles leak",
              code == 200 and "inProgress" in body
              and "\"title\"" not in raw
              and "整理发票" not in raw
              and "帮我写封邮件" not in raw, raw[:200])
        code, _ = call("GET", fbase + "/ledger")
        check("C panel route still requires auth", code == 401)
    finally:
        for proc in (front, bridge):
            if proc is not None and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except Exception:
                    proc.kill()
        fake.shutdown()


# --- Part D: monitor source (A-05 single-stream) ---------------------

DPORT = 18648
DHPORT = 18994
DTPORT = 18995

_target_body = {"text": "alpha v1"}


class TargetPage(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        body = _target_body["text"].encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def part_d():
    tmp = tempfile.mkdtemp(prefix="ledger-d-")
    fake = ThreadingHTTPServer(("127.0.0.1", DHPORT), FakeHermesB)
    threading.Thread(target=fake.serve_forever, daemon=True).start()
    target = ThreadingHTTPServer(("127.0.0.1", DTPORT), TargetPage)
    threading.Thread(target=target.serve_forever, daemon=True).start()
    # Seed the bridge store with a monitor + two changes the
    # ledger has never seen (the write hook never fired --
    # history from before the server source existed). Only
    # the collector reconcile can earn these their lines.
    seed_monitor = {
        "id": "mon_seed", "name": "种子监测",
        "target": "https://example.com/seed",
        "scheduleText": None, "cronJobId": None, "enabled": True,
        "lastCheckedAt": T0B, "lastResult": "changed",
        "lastError": None, "unreadChanges": 2,
        "latestChangeSummary": "内容发生变化：种子差异",
        "latestChangeAt": T0B + 200,
        "createdAt": T0B, "updatedAt": T0B + 200,
        "cron": None, "intervalSeconds": None, "goalId": None,
        "snapshotText": "seed v2", "snapshotFp": "seedfp",
        "nextRunAt": None}
    seed_db = {
        "goals": [], "ideas": [], "monitors": [seed_monitor],
        "changes": [
            {"id": "chg_seed1", "monitorId": "mon_seed",
             "detectedAt": T0B + 100,
             "summary": "内容发生变化：种子差异",
             "before": "seed v1", "after": "seed v2",
             "read": False},
            {"id": "chg_seed2", "monitorId": "mon_seed",
             "detectedAt": T0B + 200, "summary": "",
             "before": "seed v1", "after": "seed v2",
             "read": False}],
        "goalEntries": [], "briefings": [], "feedPosts": [],
        "goalTaskLinks": [], "traces": [], "aiSessions": [],
        "cronBindings": [], "kanbanBindings": [],
        "proactiveQueue": [], "meta": {}}
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w") as f:
        json.dump(seed_db, f)
    bridge_py = next(
        (p for p in (os.path.join(HERE, "oneday_bridge.py"),
                     os.path.join(ROOT, "modules",
                                  "oneday_bridge.py"))
         if os.path.exists(p)), None)
    env = dict(os.environ)
    env.update({
        "ONEDAY_BRIDGE_KEY": BKEY, "ONEDAY_PORT": str(DPORT),
        "DATA_PATH": data_path,
        "HERMES_BASE_URL": f"http://127.0.0.1:{DHPORT}",
        "HERMES_API_KEY": "fake-api-key",
        "HERMES_DASH_USER": "admin",
        "HERMES_DASH_PASSWORD": "fake",
        "LEDGER_COLLECTOR_SECONDS": "1",
        "LEDGER_DECISIONS_PATH": os.path.join(tmp,
                                              "decisions.jsonl"),
        "LEDGER_DEVICE_AUDIT_PATH": os.path.join(tmp,
                                                 "audit.jsonl"),
        "PYTHONPATH": os.path.dirname(bridge_py),
    })
    bridge = subprocess.Popen(
        [sys.executable, bridge_py], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True)
    base = f"http://127.0.0.1:{DPORT}"
    try:
        ok = wait_until(
            lambda: call("GET", base + "/health")[0] == 200, 30)
        check("D bridge boots", bool(ok))

        def ledger_items():
            _, body = call("GET", base + "/ledger", key=BKEY)
            return body.get("items", [])

        def monitor_lines():
            return [i for i in ledger_items()
                    if i["id"].startswith("monitor-change:")]

        found = wait_until(
            lambda: len(monitor_lines()) == 2, 25)
        check("D reconcile backfills seeded changes", bool(found),
              str(monitor_lines()))
        by_id = {i["id"]: i for i in monitor_lines()}
        seed1 = by_id.get("monitor-change:chg_seed1", {})
        check("D backfilled line is the canonical shape",
              seed1.get("kind") == "monitor"
              and seed1.get("source") == "bridge"
              and seed1.get("title") == "内容发生变化：种子差异"
              and seed1.get("titleSource") == "monitor_change"
              and seed1.get("status") == "completed"
              and seed1.get("startedAt") == T0B + 100
              and seed1.get("endedAt") == T0B + 100
              and seed1.get("origin") == "bridge_self"
              and seed1.get("link") == {"kind": "monitor",
                                        "targetId": "mon_seed"},
              str(seed1))
        seed2 = by_id.get("monitor-change:chg_seed2", {})
        check("D empty summary falls back to the monitor name",
              seed2.get("title") == "种子监测", str(seed2))

        events_path = os.path.join(tmp, "ledger-events.jsonl")

        def created_count(item_id):
            n = 0
            with open(events_path) as f:
                for line in f:
                    ev = json.loads(line)
                    if ev.get("type") == "created" \
                            and ev.get("item", {}).get("id") \
                            == item_id:
                        n += 1
            return n

        check("D backfill wrote exactly one created event",
              created_count("monitor-change:chg_seed1") == 1)
        time.sleep(2.5)  # >= 2 collector cycles at 1 s
        check("D reconcile is idempotent (no repeat events)",
              created_count("monitor-change:chg_seed1") == 1
              and len(monitor_lines()) == 2)

        # Live path: create -> baseline check -> flip -> check.
        _target_body["text"] = "alpha v1"
        s, mon = call("POST", base + "/monitors",
                      {"name": "实火监测",
                       "target": f"http://127.0.0.1:{DTPORT}/page"},
                      key=BKEY)
        check("D live monitor created", s == 201, f"{s} {mon}")
        mid = mon.get("id")
        s, _ = call("POST", base + f"/monitors/{mid}/check",
                    key=BKEY)
        check("D unchanged check records no change",
              s == 200 and len(monitor_lines()) == 2, f"{s}")
        _target_body["text"] = "alpha v2 CHANGED"
        s, _ = call("POST", base + f"/monitors/{mid}/check",
                    key=BKEY)
        check("D changed check accepted", s == 200, f"{s}")
        s, chgs = call("GET", base + f"/monitors/{mid}/changes",
                       key=BKEY)
        change_ids = [c["id"] for c in chgs.get("items", [])]
        live = wait_until(
            lambda: [i for i in monitor_lines()
                     if i["link"].get("targetId") == mid], 15)
        check("D hook lands the live change in the ledger",
              bool(live) and len(live) == 1
              and live[0]["id"]
              == f"monitor-change:{change_ids[0]}"
              and live[0]["kind"] == "monitor"
              and live[0]["title"].startswith("内容发生变化"),
              str(live))

        _, summary = call("GET", base + "/ledger/summary",
                          key=BKEY)
        check("D monitor lines never count as in-progress work",
              summary.get("inProgress") == 0
              and summary.get("blockedApproval") == 0,
              str(summary))
    finally:
        bridge.terminate()
        try:
            bridge.wait(timeout=10)
        except Exception:
            bridge.kill()
        fake.shutdown()
        target.shutdown()


def main():
    part_a()
    part_b()
    part_d()
    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
