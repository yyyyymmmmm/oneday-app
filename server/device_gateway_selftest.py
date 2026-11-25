#!/usr/bin/env python3
"""device-gateway self-test (bridge-retirement batch 5, hermes-deploy
2.0.0): drives device_gateway.dispatch_sync in-process against a
throwaway data dir, with a mock device on the other end of the poll
channel. Covers: key-free health, single-key fail-closed auth,
session lifecycle, MCP initialize/tools-list (count pinned to the
module registry), a live tool round-trip through poll/respond,
write idempotency (same key executes once), a sync write/read
round-trip through the moved SQLite store, offline honesty, and a
content-free audit log. No production data, no real keys.
Run: python3 device_gateway_selftest.py
"""
import json
import os
import sys
import tempfile
import threading
from pathlib import Path

ROOT = Path(tempfile.mkdtemp(prefix="device-gateway-selftest-"))
os.environ["DEVICE_DATA_DIR"] = str(ROOT)
os.environ["API_SERVER_KEY"] = "test-single-key"

sys.path.insert(0, str(Path(__file__).parent / "patches"))
import device_gateway as dg  # noqa: E402

PASS = 0
FAIL = 0
FAILURES = []


def check(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok {name}")
    else:
        FAIL += 1
        FAILURES.append(name)
        print(f"  FAIL {name} {extra}")


AUTH = {"Authorization": "Bearer test-single-key"}


def call(method, path, body=None, headers=None, raw_headers=None):
    hdrs = dict(raw_headers if raw_headers is not None
                else (headers if headers is not None else AUTH))
    raw = json.dumps(body).encode() if body is not None else b""
    hdrs["Content-Length"] = str(len(raw))
    status, out = dg.dispatch_sync(method, path, hdrs, raw)
    try:
        return status, json.loads(out or b"{}")
    except Exception:
        return status, {"_raw": out}


def mcp(method, params=None, rid=1):
    return call("POST", "/mcp",
                {"jsonrpc": "2.0", "id": rid, "method": method,
                 "params": params or {}})


def tool_call(name, arguments, rid=9):
    return mcp("tools/call", {"name": name, "arguments": arguments},
               rid=rid)


def tool_result(resp):
    return json.loads(resp["result"]["content"][0]["text"])


# -- auth + health -----------------------------------------------------
st, body = call("GET", "/health", headers={})
check("health key-free 200", st == 200 and body.get("ok") is True
      and body.get("sessionOnline") is False, f"{st} {body}")
st, body = call("POST", "/mcp",
                {"jsonrpc": "2.0", "id": 1, "method": "ping"},
                headers={})
check("no key -> 401", st == 401, f"{st}")
st, body = call("POST", "/mcp",
                {"jsonrpc": "2.0", "id": 1, "method": "ping"},
                raw_headers={"Authorization": "Bearer wrong"})
check("wrong key -> 401", st == 401, f"{st}")

# -- MCP handshake + registry ------------------------------------------
st, body = mcp("initialize")
check("mcp initialize", st == 200
      and body["result"]["serverInfo"]["name"] == "device-bridge",
      f"{st}")
st, body = mcp("tools/list")
tools = body["result"]["tools"]
check("tools/list == module registry",
      len(tools) == len(dg.TOOLS)
      and [t["name"] for t in tools] == [t["name"] for t in dg.TOOLS],
      f"{len(tools)} vs {len(dg.TOOLS)}")
print(f"  .. tools count = {len(tools)}")

# -- offline honesty -----------------------------------------------------
st, body = tool_call("device_info", {})
res = tool_result(body)
check("offline live call -> device_offline",
      body["result"]["isError"] is True
      and res.get("error") == "device_offline", f"{res}")

# -- session + live round-trip ------------------------------------------
st, body = call("POST", "/device/session", {
    "deviceId": "mock-1", "appVersion": "selftest",
    "permissions": {"deviceinfo": "granted", "calendar": "granted"},
    "tools": ["device_info", "calendar_create_event"],
    "capabilities": []})
sid = body.get("sessionId")
check("session register 201", st == 201 and bool(sid), f"{st} {body}")

st, body = tool_call("device_status", {})
res = tool_result(body)
check("device_status online", res.get("online") is True
      and res.get("deviceId") == "mock-1", f"{res}")


def live_roundtrip(name, arguments, answer):
    """Run a tools/call on a thread; play the phone on this one."""
    box = {}

    def run():
        box["resp"] = tool_call(name, arguments)
    th = threading.Thread(target=run)
    th.start()
    st, poll = call("GET", f"/device/poll?sessionId={sid}&wait=10")
    got = poll.get("call") or {}
    st2, _ = call("POST", "/device/respond", {
        "sessionId": sid, "callId": got.get("callId"),
        "status": "ok", "result": answer})
    th.join(timeout=20)
    resp = box.get("resp")
    return got, (resp[1] if resp else None)


got, resp = live_roundtrip(
    "device_info", {}, {"model": "MockPhone", "objectId": "dev-1"})
res = tool_result(resp)
check("live round-trip via poll/respond",
      got.get("tool") == "device_info"
      and res.get("model") == "MockPhone", f"{got} {res}")

# -- write idempotency ----------------------------------------------------
args = {"title": "自测事件", "start": "2026-01-01T10:00:00+08:00",
        "end": "2026-01-01T11:00:00+08:00",
        "idempotencyKey": "selftest-key-1"}
got, resp = live_roundtrip(
    "calendar_create_event", args, {"objectId": "evt-1"})
res = tool_result(resp)
check("write executes once", res.get("objectId") == "evt-1",
      f"{res}")
st, body = tool_call("calendar_create_event", args)
res = tool_result(body)
check("same idempotency key -> replay, no phone round-trip",
      res.get("idempotentReplay") is True
      and res.get("objectId") == "evt-1", f"{res}")

# -- sync round-trip ------------------------------------------------------
st, body = call("POST", "/device/sync/batch", {
    "dataset": "contacts", "batchId": "b1", "mode": "full",
    "records": [{"id": "c1", "displayName": "自测联系人",
                 "phones": ["10086"]}]})
check("sync batch staged", st == 200 and body.get("received") == 1,
      f"{st} {body}")
st, body = call("POST", "/device/sync/complete", {
    "dataset": "contacts", "batchId": "b1", "expectedTotal": 1,
    "permissionState": "granted"})
check("sync complete", st == 200
      and body.get("total_in_store") == 1, f"{st} {body}")
st, body = tool_call("contacts_count", {})
res = tool_result(body)
check("contacts_count from moved store",
      res.get("total") == 1, f"{res}")
st, body = call("GET", "/device/sync/status")
check("sync status face", st == 200
      and body["datasets"]["contacts"].get("synced_at") is not None,
      f"{st}")

# -- disconnect + audit ---------------------------------------------------
st, body = call("POST", "/device/disconnect", {"sessionId": sid})
check("disconnect", st == 200 and body.get("ok") is True, f"{st}")
st, body = tool_call("device_status", {})
res = tool_result(body)
check("device_status offline after disconnect",
      res.get("online") is False, f"{res}")
audit = (ROOT / "audit.jsonl").read_text(encoding="utf-8")
check("audit written, content-free",
      "device_info" in audit and "MockPhone" not in audit
      and "自测联系人" not in audit, "")
check("data files in new home with 0600",
      (ROOT / "sync.db").exists()
      and oct((ROOT / "audit.jsonl").stat().st_mode)[-3:] == "600",
      f"{oct((ROOT / 'audit.jsonl').stat().st_mode)}")

print(f"\n{PASS} passed, {FAIL} failed")
if FAILURES:
    print("failures:", FAILURES)
sys.exit(1 if FAIL else 0)
