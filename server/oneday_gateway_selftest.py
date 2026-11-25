#!/usr/bin/env python3
"""Batch-3 gateway selftest (stub environment): oneday_gateway +
overview_gateway smoke over the in-process dispatch.

Stubs: a throwaway HERMES_HOME, a throwaway DATA_PATH, a fixed
cron callback key via env, DELIVERY_ROOT pointed at the stub home,
and overview's _get_json monkeypatched with canned owner answers.
No network, no production state. Run: python3 oneday_gateway_selftest.py
"""
import json
import os
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(tempfile.mkdtemp(prefix="oneday-gw-selftest-"))
HOME = ROOT / "home"
HOME.mkdir(parents=True)
(HOME / "scripts").mkdir()
DATA_DIR = ROOT / "oneday"
DATA_DIR.mkdir()
OVERVIEW_DIR = ROOT / "overview"

os.environ["HERMES_HOME"] = str(HOME)
os.environ["DATA_PATH"] = str(DATA_DIR / "data.json")
os.environ["STATE_DIR"] = str(OVERVIEW_DIR)
os.environ["ONEDAY_CRON_CALLBACK_KEY"] = "test-callback-key"
os.environ["API_SERVER_KEY"] = "test-api-key"
os.environ["DELIVERY_ROOT"] = str(HOME)
os.environ["DELIVERY_SENTINEL_DB"] = str(HOME / "state.db")
# In-package the font ships flat in patches/ and install.sh mounts
# it to gateway/platforms/assets/ in the container; the segment
# default (sibling assets/) resolves there. Here, point at the
# flat package location explicitly.
os.environ["DELIVERY_FONT"] = str(
    Path(__file__).resolve().parent / "patches" / "NotoSansSC-subset.ttf")

sys.path.insert(0, str(Path(__file__).resolve().parent / "patches"))

import oneday_gateway as od          # noqa: E402
import overview_gateway as ov        # noqa: E402

PASS = 0
FAIL = 0


def check(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok {name}")
    else:
        FAIL += 1
        print(f"  FAIL {name} {extra}")


def call(method, path, body=None, headers=None):
    raw = json.dumps(body).encode() if body is not None else b""
    status, resp, hdrs = od.dispatch(method, path, headers or {}, raw)
    try:
        parsed = json.loads(resp.decode()) if resp else None
    except Exception:
        parsed = None
    return status, parsed, resp, hdrs


print("== oneday_gateway dispatch ==")
s, b, _, _ = call("GET", "/health")
check("health 200 ok", s == 200 and b.get("ok") is True, f"{s} {b}")
check("health carries sentinel+ledger blocks",
      "deliverySentinel" in b and "ledger" in b)

s, b, _, _ = call("GET", "/goals")
check("goals empty list", s == 200 and b == {"items": []}, f"{s} {b}")

s, b, _, _ = call("POST", "/goals", {"title": "冒烟目标"})
check("goal create 201", s == 201 and b.get("title") == "冒烟目标",
      f"{s} {b}")
gid = b["id"]
s, b, _, _ = call("POST", f"/goals/{gid}/entries", {"body": "第一条进展"})
check("entry create 201", s == 201, f"{s} {b}")
s, b, _, _ = call("GET", f"/goals/{gid}/entries")
check("entries list 1", s == 200 and len(b["items"]) == 1, f"{s} {b}")
s, b, _, _ = call("GET", "/goals")
check("goals list 1 with latestEntry",
      s == 200 and len(b["items"]) == 1
      and b["items"][0].get("latestEntry"), f"{s} {b}")

s, b, _, _ = call("POST", "/ideas", {"title": "冒烟点子"})
check("idea create 201", s == 201, f"{s} {b}")
s, b, _, _ = call("GET", "/ideas")
check("ideas list + snapshot key",
      s == 200 and "items" in b and "snapshot" in b, f"{s} {b}")

s, b, _, _ = call("GET", "/meta/brief")
check("meta brief 200", s == 200 and "brief" in b, f"{s} {b}")
s, b, _, _ = call("PUT", "/meta/brief", {"brief": "冒烟 brief"})
check("meta brief PUT 200", s == 200 and b.get("brief") == "冒烟 brief",
      f"{s} {b}")

s, b, _, _ = call("GET", "/feed")
check("feed list 200", s == 200 and "items" in b, f"{s} {b}")
s, b, _, _ = call("GET", "/feed/generation")
check("feed generation 200", s == 200 and "research" in b, f"{s} {b}")

s, b, _, _ = call("GET", "/monitors")
check("monitors list 200", s == 200 and b == {"items": []}, f"{s} {b}")
s, b, _, _ = call("GET", "/monitors/notifications")
check("monitor notifications 200", s == 200 and "items" in b, f"{s} {b}")

s, b, _, _ = call("GET", "/ledger/summary")
check("ledger summary 200", s == 200, f"{s} {b}")
s, b, _, _ = call("GET", "/ledger")
check("ledger list 200", s == 200, f"{s} {b}")

s, b, _, _ = call("POST", "/traces",
                  {"action": "smoke.test", "status": "ok",
                   "result": "冒烟留痕",
                   "target": {"kind": "smoke", "id": "t1"}})
check("trace create 201", s == 201, f"{s} {b}")
s, b, _, _ = call("GET", "/traces")
check("traces list 1", s == 200 and len(b["items"]) == 1, f"{s} {b}")

doc = HOME / "smoke-delivery.md"
doc.write_text("# 冒烟交付\n这是一份冒烟测试交付文件。\n", encoding="utf-8")
s, b, _, _ = call("POST", "/deliveries", {"path": str(doc)})
check("delivery register 201 + marker",
      s == 201 and str(b.get("marker", "")).startswith("[[deliver:dlv_"),
      f"{s} {b}")
rid = b["id"]
s, b, _, _ = call("GET", f"/deliveries/{rid}")
check("delivery meta 200 ok status",
      s == 200 and b.get("status") == "ok", f"{s} {b}")
s, b, raw, hdrs = call("GET", f"/deliveries/{rid}/thumb")
check("delivery thumb bytes or honest 404",
      (s == 200 and hdrs.get("Content-Type") == "image/jpeg")
      or s == 404, f"{s} {hdrs}")
s, b, _, _ = call("GET", f"/deliveries/by-message?session_id=s1")
check("delivery by-message 200", s == 200 and b.get("sessionId") == "s1",
      f"{s} {b}")

s, b, _, _ = call("GET", "/file-library")
check("file-library 200", s == 200 and "items" in b, f"{s} {b}")

for mcp_path, name in (("/mcp", "oneday-goals"),
                       ("/mcp-sessions", "oneday-sessions"),
                       ("/automation-mcp", "oneday-automation")):
    s, b, _, _ = call("POST", mcp_path,
                      {"jsonrpc": "2.0", "id": 1, "method": "initialize"})
    check(f"{mcp_path} initialize",
          s == 200 and b["result"]["serverInfo"]["name"] == name,
          f"{s} {b}")
    s, b, _, _ = call("POST", mcp_path,
                      {"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    check(f"{mcp_path} tools/list non-empty",
          s == 200 and len(b["result"]["tools"]) >= 1, f"{s} {b}")

s, b, _, _ = call("POST", "/internal/cron/ping")
check("cron ping without key 401", s == 401, f"{s} {b}")
s, b, _, _ = call("POST", "/internal/cron/ping",
                  headers={"X-Cron-Callback-Key": "test-callback-key"})
check("cron ping with key 200 pong",
      s == 200 and b.get("pong"), f"{s} {b}")
s, b, _, _ = call("POST", "/internal/cron/ping",
                  headers={"X-Cron-Callback-Key": "wrong"})
check("cron ping wrong key 401", s == 401, f"{s} {b}")

s, b, _, _ = call("GET", "/no-such-face")
check("unknown path 404", s == 404, f"{s} {b}")

# The boot-time ensure pass needs the Dashboard channel (no creds
# in the stub, it logged and deferred). Patch the channel with a
# canned empty job list and run one ensure pass directly: round
# scripts + the callback key file must land in HERMES_HOME/scripts.
od._dash_json = lambda path, **kw: (
    {"jobs": []} if kw.get("method") in (None, "GET")
    else {"job": {"id": "job-stub"}})
od._cron_ensure_all()
_scripts = sorted(x.name for x in (HOME / "scripts").iterdir())
check("cron ensure writes round scripts + key file",
      "oneday-round-ideas.py" in _scripts
      and ".oneday-callback-key" in _scripts, f"{_scripts}")
_script_text = (HOME / "scripts" / "oneday-round-ideas.py").read_text()
check("generated script carries gateway callback base",
      "127.0.0.1:8642/api/oneday-bridge" in _script_text)
check("data file written in place",
      (DATA_DIR / "data.json").exists()
      and json.loads((DATA_DIR / "data.json").read_text())
      .get("goals"))

print("== overview_gateway (canned sources) ==")
FUTURE = "2999-01-01T00:00:00Z"
NOW_EPOCH = time.time() + 100000


def canned(url, key, timeout):
    if url.endswith("/health"):
        return 200, {}
    if "/api/sessions" in url:
        return 200, {"data": [{"ended_at": None}, {"ended_at": "x"},
                              {"ended_at": None}]}
    if url.endswith("/api/write-gate/status"):
        return 200, {"counts": {"memory": 2, "skills": 1}}
    if "/api/write-gate/decisions" in url:
        return 200, {"decisions": [{
            "id": "d1", "subsystem": "memory", "decision": "approved",
            "summary": "写入一条记忆", "decided_at": FUTURE}]}
    if url.endswith("/api/write-gate/pending"):
        return 200, {"records": [{
            "id": "p1", "subsystem": "skills", "summary": "技能待批",
            "created_at": FUTURE}]}
    if "/api/oneday-bridge/monitors/notifications" in url:
        return 200, {"items": [{
            "id": "mon1", "kind": "monitor_change", "title": "监测变化",
            "body": "页面变了", "createdAt": FUTURE}]}
    if "/v1/runs" in url:
        return 200, {"data": [{
            "run_id": "r1", "status": "completed", "session_id": "s1",
            "updated_at": NOW_EPOCH}]}
    raise AssertionError(f"unexpected url {url}")


ov._get_json = canned
s, b = ov.get_overview()
check("overview 200", s == 200, f"{s} {b}")
check("overview hermesUp + sessions",
      b.get("hermesUp") is True and b.get("activeSessions") == 2,
      f"{b}")
check("overview pendingApprovals sums write-gate counts",
      b.get("pendingApprovals") == 3, f"{b}")
check("overview unread = monitor + runs (pending excluded)",
      b.get("unreadNotifications") == 2, f"{b}")

s, b = ov.get_notifications()
kinds = [n["kind"] for n in b["items"]]
check("notifications 4 items all kinds",
      s == 200 and sorted(kinds) == [
          "approval_pending", "monitor_change", "task_completed",
          "write_gate_decision"], f"{s} {kinds}")
by_kind = {n["kind"]: n for n in b["items"]}
check("decision receipt born read",
      by_kind["write_gate_decision"]["read"] is True)
check("pending born unread",
      by_kind["approval_pending"]["read"] is False)

s, b = ov.mark_read("mon1")
check("mark_read monitor 200", s == 200 and b.get("ok") is True,
      f"{s} {b}")
s, b = ov.get_notifications()
by_kind = {n["kind"]: n for n in b["items"]}
check("monitor now read", by_kind["monitor_change"]["read"] is True)
s, b = ov.mark_read("wg-d1")
check("mark_read decision receipt 200 (born read, no-op)",
      s == 200, f"{s} {b}")
s, b = ov.mark_read("no-such-id")
check("mark_read unknown 404", s == 404, f"{s} {b}")
check("overview state persisted in place",
      (OVERVIEW_DIR / "state.json").exists())

print(f"== summary: PASS {PASS} / FAIL {FAIL} ==")
sys.exit(1 if FAIL else 0)
