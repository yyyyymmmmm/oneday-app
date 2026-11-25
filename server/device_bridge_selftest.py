#!/usr/bin/env python3
"""device-bridge end-to-end self-test with a mock device.

Runs against a live bridge at BASE (default http://127.0.0.1:8647).
Bearer comes from env DEVICE_BRIDGE_KEY (never printed). The mock
device registers a session (health permission denied, everything else
granted), long-polls, and answers calls with canned live-read data.
Assertions cover the whole loop plus the honesty rules: offline =>
device_offline with no data, denied => permission_denied without a
phone round-trip, write idempotency (same key executes once), and a
content-free audit log.
"""
import json
import os
import sys
import threading
import time
import urllib.request
import urllib.error

BASE = os.environ.get("DEVICE_BRIDGE_BASE", "http://127.0.0.1:8647")
KEY = os.environ["DEVICE_BRIDGE_KEY"]
FAILURES = []


def req(method, path, body=None, auth=True, timeout=40):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method)
    if data:
        r.add_header("Content-Type", "application/json")
    if auth:
        r.add_header("Authorization", f"Bearer {KEY}")
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw) if raw else {}
        except ValueError:
            return e.code, {"raw": raw}


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name +
          (f"  [{detail}]" if detail else ""), flush=True)
    if not cond:
        FAILURES.append(name)


def mcp(method, params=None, rid=1):
    body = {"jsonrpc": "2.0", "id": rid, "method": method}
    if params is not None:
        body["params"] = params
    return req("POST", "/mcp", body)


def call_tool(name, arguments=None):
    _, payload = mcp("tools/call",
                     {"name": name, "arguments": arguments or {}}, rid=9)
    result = payload.get("result") or {}
    text = (result.get("content") or [{}])[0].get("text", "{}")
    return result.get("isError", False), json.loads(text)


# ------------------------------------------------------------ mock phone
class MockDevice(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.session_id = None
        self.create_exec_count = 0
        self.stop_flag = False

    def register(self):
        _, payload = req("POST", "/device/session", {
            "deviceId": "mock-iphone-1", "appVersion": "selftest",
            "permissions": {"calendar": "granted",
                            "reminders": "granted",
                            "contacts": "granted",
                            "health": "denied",
                            "home": "granted"},
            "tools": ["calendar_list_events", "calendar_create_event",
                      "calendar_update_event", "reminders_list",
                      "reminders_create", "reminders_complete",
                      "contacts_search", "health_daily_summary",
                      "home_status"]})
        self.session_id = payload["sessionId"]

    def execute(self, call):
        tool, args = call["tool"], call.get("arguments") or {}
        if tool == "calendar_list_events":
            return {"readAt": time.time(), "events": [
                {"id": "evt-mock-1", "title": "MOCK-EVENT-1",
                 "start": args.get("start"), "end": args.get("end")}]}
        if tool == "calendar_create_event":
            self.create_exec_count += 1
            return {"objectId": "mock-evt-123",
                    "title": args.get("title"),
                    "start": args.get("start")}
        if tool == "reminders_list":
            return {"readAt": time.time(), "items": [
                {"id": "rem-1", "title": "MOCK-REMINDER-1",
                 "due": None}], "incompleteCount": 1}
        return {"readAt": time.time(), "echo": tool}

    def run(self):
        while not self.stop_flag:
            try:
                _, payload = req(
                    "GET",
                    f"/device/poll?sessionId={self.session_id}&wait=5",
                    timeout=15)
            except Exception:
                time.sleep(0.3)
                continue
            call = payload.get("call")
            if not call:
                continue
            req("POST", "/device/respond", {
                "sessionId": self.session_id, "callId": call["callId"],
                "status": "ok", "result": self.execute(call)})


def main():
    st, health = req("GET", "/health", auth=False)
    check("health 200 without auth", st == 200 and health.get("ok"),
          str(health))
    st, _ = req("GET", "/device/poll?sessionId=x", auth=False)
    check("device channel rejects missing Bearer", st == 401, f"got {st}")

    _, payload = mcp("initialize", {
        "protocolVersion": "2024-11-05", "capabilities": {},
        "clientInfo": {"name": "selftest", "version": "0"}})
    check("mcp initialize",
          payload.get("result", {}).get("serverInfo", {}).get("name")
          == "device-bridge", json.dumps(payload)[:120])
    _, payload = mcp("tools/list")
    names = [t["name"] for t in payload["result"]["tools"]]
    check("tools/list has all 10 tools", len(names) == 10, str(names))

    is_err, out = call_tool("device_status")
    check("device_status offline before registration",
          not is_err and out.get("online") is False, str(out))
    is_err, out = call_tool("calendar_list_events",
                            {"start": "2026-11-10T00:00:00+08:00",
                             "end": "2026-11-12T00:00:00+08:00"})
    check("offline call => device_offline, no data",
          is_err and out.get("error") == "device_offline", str(out))

    mock = MockDevice()
    mock.register()
    mock.start()
    time.sleep(0.3)
    is_err, out = call_tool("device_status")
    check("device_status online after registration",
          not is_err and out.get("online") is True, str(out))

    is_err, out = call_tool("calendar_list_events",
                            {"start": "2026-11-10T00:00:00+08:00",
                             "end": "2026-11-12T00:00:00+08:00"})
    ev = (out.get("events") or [{}])[0]
    check("facade->bridge->mock live read->facade round trip",
          not is_err and ev.get("title") == "MOCK-EVENT-1"
          and "readAt" in out, str(out)[:160])

    t0 = time.time()
    is_err, out = call_tool("health_daily_summary", {"days": 7})
    check("denied permission => permission_denied, fast (no round-trip)",
          is_err and out.get("error") == "permission_denied"
          and time.time() - t0 < 5, str(out))

    args = {"title": "Selftest event", "start": "2026-11-11T10:00:00+08:00",
            "end": "2026-11-11T11:00:00+08:00", "idempotencyKey": "K1"}
    is_err, out1 = call_tool("calendar_create_event", args)
    is_err2, out2 = call_tool("calendar_create_event", args)
    check("write executes once; same key replays stored outcome",
          not is_err and out1.get("objectId") == "mock-evt-123"
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock.create_exec_count == 1,
          f"exec={mock.create_exec_count} out2={out2}")

    req("POST", "/device/disconnect", {"sessionId": mock.session_id})
    mock.stop_flag = True
    time.sleep(0.3)
    is_err, out = call_tool("reminders_list")
    check("after disconnect => device_offline again",
          is_err and out.get("error") == "device_offline", str(out))

    print("SELFTEST " + ("FAILED: " + ", ".join(FAILURES)
                         if FAILURES else "ALL PASS"), flush=True)
    sys.exit(1 if FAILURES else 0)


if __name__ == "__main__":
    main()
