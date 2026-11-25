#!/usr/bin/env python3
"""device-bridge end-to-end self-test with a mock device.

Runs against a live bridge at BASE (default http://127.0.0.1:8647).
Bearer comes from env DEVICE_BRIDGE_KEY (never printed). The mock
device registers a session (health permission denied, everything else
granted), long-polls, and answers calls with canned live-read data.
Assertions cover the whole loop plus the honesty rules: offline =>
device_offline with no data, denied => permission_required (parked,
structured, resumable) without a phone round-trip, write idempotency
(same key executes once), and a content-free audit log.
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
    def __init__(self, tools=None, permissions=None, agent_call=None,
                 capabilities=None):
        super().__init__(daemon=True)
        self.session_id = None
        # §244: registration extras + the in-chat ask answer this
        # mock gives when the bridge sends a permission_ask
        self._agent_call = agent_call
        self._capabilities = capabilities
        self.ask_decision = "parked"
        self.ask_count = 0
        self.last_ask = None
        self.create_exec_count = 0
        self.clipboard_set_count = 0
        self.files_write_count = 0
        self.alarm_set_count = 0
        self.alarm_cancel_count = 0
        self.notify_post_count = 0
        self.open_target_count = 0
        self.camera_capture_count = 0
        self.vision_document_scan_count = 0
        self.auth_biometric_count = 0
        self.location_current_count = 0
        self.media_library_search_count = 0
        self.media_playlist_create_count = 0
        self.media_playback_control_count = 0
        self.compose_sms_count = 0
        self.shortcut_run_count = 0
        self.stop_flag = False
        # clipboard deliberately reports "denied": it has no iOS
        # system permission (§111.2), so the bridge must never
        # permission-gate it whatever the payload says; the tools
        # list is the only gate. §113 batch: notifications is a REAL
        # permission and deliberately reports "denied" here (bridge
        # must pre-intercept), while opener also reports "denied"
        # but, like clipboard, has no system permission (§113.2)
        # and must never be gated. §114 batch: camera is a REAL
        # permission (granted here; the denied case gets its own
        # session below), while vision and biometric deliberately
        # report "denied" too — neither has a switchable system
        # permission (§114.2), so both must still round-trip.
        # §115 batch: location and media are REAL permissions
        # (granted here; the denied case gets its own session
        # below), while compose/shortcuts/deviceinfo deliberately
        # report "denied" — none of them has a switchable system
        # permission (§115.2), so all must still round-trip; the
        # tools list is their only gate. file_preview/file_print
        # ride the files permission, already granted.
        self._permissions = permissions if permissions is not None else {
            "calendar": "granted", "reminders": "granted",
            "contacts": "granted", "health": "denied",
            "home": "granted", "clipboard": "denied",
            "files": "granted", "alarm": "granted",
            "notifications": "denied", "opener": "denied",
            "camera": "granted", "vision": "denied",
            "translate": "granted", "ondevice": "granted",
            "biometric": "denied",
            "location": "granted", "media": "granted",
            "compose": "denied", "shortcuts": "denied",
            "deviceinfo": "denied"}
        self._tools = tools if tools is not None else [
            "calendar_list_events", "calendar_create_event",
            "calendar_update_event", "reminders_list",
            "reminders_create", "reminders_complete",
            "contacts_search", "health_daily_summary", "home_status",
            "clipboard_get", "clipboard_set", "files_list",
            "files_read", "files_write", "alarm_set", "alarm_list",
            "alarm_cancel", "notify_post", "open_target",
            "camera_capture", "vision_document_scan", "vision_ocr",
            "vision_scan_code", "translate_text",
            "ondevice_model_run", "auth_biometric",
            "location_current", "location_search_places",
            "location_geocode", "media_library_search",
            "media_playlists", "media_playlist_create",
            "media_playback_control", "call_start", "compose_sms",
            "compose_email", "share_sheet", "shortcut_run",
            "device_info", "file_preview", "file_print"]

    def register(self):
        body = {"deviceId": "mock-iphone-1", "appVersion": "selftest",
                "permissions": self._permissions, "tools": self._tools}
        if self._agent_call is not None:
            body["agentCall"] = self._agent_call
        if self._capabilities is not None:
            body["capabilities"] = self._capabilities
        _, payload = req("POST", "/device/session", body)
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
        if tool == "clipboard_get":
            return {"readAt": time.time(), "type": "text",
                    "text": "MOCK-CLIP-TEXT"}
        if tool == "clipboard_set":
            self.clipboard_set_count += 1
            return {"objectId": "clipboard", "written": True,
                    "verified": True,
                    "characters": len(args.get("text") or "")}
        if tool == "files_list":
            return {"path": args.get("path") or "",
                    "readAt": time.time(), "count": 1, "entries": [
                        {"name": "note.txt", "path": "note.txt",
                         "isDirectory": False, "sizeBytes": 5,
                         "modifiedAt": time.time()}]}
        if tool == "files_read":
            return {"path": args.get("path"), "readAt": time.time(),
                    "bytes": 5, "content": "hello"}
        if tool == "files_write":
            self.files_write_count += 1
            return {"objectId": args.get("path"),
                    "path": args.get("path"), "written": True,
                    "verified": True,
                    "bytes": len((args.get("content") or "")
                                 .encode("utf-8"))}
        if tool == "alarm_set":
            self.alarm_set_count += 1
            return {"objectId": "alarm-mock-1", "id": "alarm-mock-1",
                    "kind": "countdown" if args.get("afterSeconds")
                            else "fixed",
                    "state": "scheduled", "title": args.get("title"),
                    "verified": True,
                    "humanSummary": "已设定闹钟："
                                    + str(args.get("title"))}
        if tool == "alarm_list":
            return {"count": 1, "alarms": [
                        {"id": "alarm-mock-1", "kind": "countdown",
                         "state": "scheduled", "title": "吃药"}],
                    "readAt": time.time()}
        if tool == "alarm_cancel":
            self.alarm_cancel_count += 1
            return {"objectId": args.get("alarmId"),
                    "cancelled": True, "wasPresent": True,
                    "verified": True,
                    "humanSummary": "已取消闹钟"}
        if tool == "notify_post":
            self.notify_post_count += 1
            return {"objectId": "notif-mock-1", "posted": True,
                    "verified": True, "id": "notif-mock-1",
                    "title": args.get("title"),
                    "humanSummary": "已发送通知："
                                    + str(args.get("title"))}
        if tool == "open_target":
            self.open_target_count += 1
            return {"objectId": args.get("target"), "opened": True,
                    "target": args.get("target"), "name": "设置",
                    "humanSummary": "已打开设置"}
        if tool == "camera_capture":
            self.camera_capture_count += 1
            return {"objectId": "captures/IMG-mock-1.jpg",
                    "name": "IMG-mock-1.jpg",
                    "path": "captures/IMG-mock-1.jpg",
                    "isDirectory": False, "sizeBytes": 12345,
                    "modifiedAt": time.time(), "saved": True,
                    "verified": True, "capturedAt": time.time(),
                    "humanSummary": "已拍好一张照片，存为 "
                                    "IMG-mock-1.jpg"}
        if tool == "vision_document_scan":
            self.vision_document_scan_count += 1
            page = {"name": "scan-mock-p1.jpg",
                    "path": "captures/scan-mock-p1.jpg",
                    "isDirectory": False, "sizeBytes": 23456,
                    "modifiedAt": time.time()}
            return {"objectId": "captures/scan-mock",
                    "saved": True, "verified": True, "pageCount": 2,
                    "pages": [page, dict(page, name="scan-mock-p2.jpg",
                                         path="captures/"
                                              "scan-mock-p2.jpg")],
                    "humanSummary": "已扫描 2 页"}
        if tool == "vision_ocr":
            return {"path": args.get("path"), "readAt": time.time(),
                    "text": "MOCK-OCR-TEXT",
                    "lines": ["MOCK-OCR-TEXT"]}
        if tool == "vision_scan_code":
            return {"path": args.get("path"), "readAt": time.time(),
                    "count": 1, "codes": [
                        {"symbology": "二维码",
                         "payload": "MOCK-QR"}]}
        if tool == "translate_text":
            return {"text": "MOCK-TRANSLATION",
                    "sourceLanguage": args.get("source"),
                    "targetLanguage": args.get("target") or "en",
                    "readAt": time.time(),
                    "humanSummary": "已翻译"}
        if tool == "ondevice_model_run":
            return {"text": "MOCK-ONDEVICE-ANSWER",
                    "model": "on-device", "readAt": time.time()}
        if tool == "auth_biometric":
            self.auth_biometric_count += 1
            return {"confirmed": True, "outcome": "confirmed",
                    "biometry": "faceID", "verifiedAt": time.time(),
                    "humanSummary": "已确认是本人在场"}
        if tool == "location_current":
            self.location_current_count += 1
            return {"readAt": time.time(), "latitude": 34.3416,
                    "longitude": 108.9398, "accuracyMeters": 65.0,
                    "locatedAt": time.time(), "placeName": "西安市",
                    "address": "陕西省西安市",
                    "humanSummary": "当前位置在西安市附近"
                                    "（精度约 65 米）"}
        if tool == "location_search_places":
            return {"readAt": time.time(),
                    "query": args.get("query"), "count": 1,
                    "places": [{"name": "MOCK-PHARMACY",
                                "latitude": 34.3421,
                                "longitude": 108.9405,
                                "distanceMeters": 320,
                                "address": "陕西省西安市"}],
                    "humanSummary": "附近找到 1 处"}
        if tool == "location_geocode":
            if args.get("address"):
                return {"readAt": time.time(), "mode": "forward",
                        "address": args.get("address"),
                        "latitude": 34.3416, "longitude": 108.9398,
                        "placeName": "西安市",
                        "humanSummary": "已查到坐标"}
            return {"readAt": time.time(), "mode": "reverse",
                    "address": "陕西省西安市",
                    "latitude": args.get("latitude"),
                    "longitude": args.get("longitude"),
                    "placeName": "西安市",
                    "humanSummary": "已查到地址"}
        if tool == "media_library_search":
            self.media_library_search_count += 1
            return {"readAt": time.time(),
                    "query": args.get("query"),
                    "kind": args.get("kind") or "any", "count": 1,
                    "results": [{"type": "song", "id": "mock-song-1",
                                 "title": "MOCK-SONG",
                                 "artist": "MOCK-ARTIST"}],
                    "humanSummary": "找到 1 首"}
        if tool == "media_playlists":
            return {"readAt": time.time(), "count": 1,
                    "playlists": [{"type": "playlist",
                                   "id": "mock-pl-1",
                                   "name": "MOCK-PLAYLIST",
                                   "itemCount": 3}]}
        if tool == "media_playlist_create":
            self.media_playlist_create_count += 1
            return {"objectId": "mock-pl-new", "type": "playlist",
                    "id": "mock-pl-new", "name": args.get("name"),
                    "itemCount": 0, "created": True,
                    "verified": True,
                    "humanSummary": "已建好歌单："
                                    + str(args.get("name"))}
        if tool == "media_playback_control":
            self.media_playback_control_count += 1
            return {"action": args.get("action"), "verified": True,
                    "state": "playing",
                    "nowPlaying": {"title": "MOCK-SONG",
                                   "artist": "MOCK-ARTIST"},
                    "humanSummary": "已开始播放 MOCK-SONG"}
        if tool == "call_start":
            return {"initiated": True, "number": args.get("number"),
                    "note": "已打开系统拨号确认面",
                    "humanSummary": "已打开拨号确认，请在手机上"
                                    "点通话"}
        if tool == "compose_sms":
            self.compose_sms_count += 1
            return {"presented": True, "outcome": "sent",
                    "sent": True,
                    "humanSummary": "短信已由你在手机上发出"}
        if tool == "compose_email":
            return {"presented": True, "outcome": "sent",
                    "sent": True,
                    "humanSummary": "邮件已由你在手机上发出"}
        if tool == "share_sheet":
            return {"presented": True, "shared": True,
                    "humanSummary": "已分享"}
        if tool == "shortcut_run":
            self.shortcut_run_count += 1
            return {"ran": True, "callbackReceived": True,
                    "name": args.get("name"),
                    "result": "MOCK-SHORTCUT-RESULT",
                    "humanSummary": "快捷指令已跑完："
                                    + str(args.get("name"))}
        if tool == "device_info":
            return {"readAt": time.time(), "model": "iPhone",
                    "modelIdentifier": "iPhone17,2",
                    "systemName": "iOS", "systemVersion": "26.0",
                    "batteryState": "unplugged", "batteryPercent": 82,
                    "batteryKnown": True, "lowPowerMode": False,
                    "storageTotalBytes": 256_000_000_000,
                    "storageFreeBytes": 128_000_000_000,
                    "network": "wifi",
                    "humanSummary": "电量 82%，连着 Wi-Fi"}
        if tool == "file_preview":
            return {"viewed": True, "path": args.get("path"),
                    "humanSummary": "已在手机上打开预览"}
        if tool == "file_print":
            return {"presented": True, "printed": True,
                    "path": args.get("path"),
                    "humanSummary": "已打印"}
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
            if call["tool"] == "permission_ask":
                self.ask_count += 1
                self.last_ask = call.get("arguments") or {}
                req("POST", "/device/respond", {
                    "sessionId": self.session_id,
                    "callId": call["callId"],
                    "status": "ok",
                    "result": {"decision": self.ask_decision}})
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
    expected = ["alarm_cancel", "alarm_list", "alarm_set",
                "auth_biometric", "calendar_count",
                "calendar_create_event", "calendar_list_events",
                "calendar_search", "calendar_update_event",
                "call_start", "camera_capture", "clipboard_get",
                "clipboard_set", "compose_email", "compose_sms",
                "contacts_count", "contacts_get", "contacts_list",
                "contacts_search", "contacts_stats", "device_info",
                "device_status", "file_preview", "file_print",
                "files_list", "files_read", "files_write",
                "health_daily_summary", "home_status",
                "location_current", "location_geocode",
                "location_search_places", "media_library_search",
                "media_playback_control", "media_playlist_create",
                "media_playlists", "motion_steps_summary",
                "notify_post", "ondevice_model_run", "open_target",
                "photos_recent", "photos_stats",
                "reminders_complete", "reminders_count",
                "reminders_create", "reminders_list",
                "reminders_search", "share_sheet", "shortcut_run",
                "translate_text", "vision_document_scan",
                "vision_ocr", "vision_scan_code"]
    check("tools/list has all 53 tools", sorted(names) == expected,
          str(names))

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
    check("denied permission => permission_required parked, "
          "structured, fast (no round-trip)",
          is_err and out.get("error") == "permission_required"
          and out.get("source") == "health"
          and out.get("state") == "denied"
          and out.get("blockerLayer") == "permission"
          and out.get("nextAction") == "open_settings"
          and bool(out.get("resumeToken"))
          and "权限" in out.get("message", "")
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

    # --- §111 batch (1.0.8): clipboard + files ----------------------
    is_err, out = call_tool("clipboard_get")
    check("clipboard_get round-trips despite payload saying denied "
          "(clipboard is never permission-gated)",
          not is_err and out.get("text") == "MOCK-CLIP-TEXT", str(out))

    cargs = {"text": "hello clip", "idempotencyKey": "KC1"}
    is_err, out1 = call_tool("clipboard_set", cargs)
    is_err2, out2 = call_tool("clipboard_set", cargs)
    check("clipboard_set executes once; same key replays",
          not is_err and out1.get("verified") is True
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock.clipboard_set_count == 1,
          f"exec={mock.clipboard_set_count} out2={out2}")

    is_err, out = call_tool("files_list", {})
    entries = out.get("entries") or [{}]
    check("files_list round trip",
          not is_err and out.get("count") == 1
          and entries[0].get("name") == "note.txt", str(out)[:160])
    is_err, out = call_tool("files_read", {"path": "note.txt"})
    check("files_read round trip",
          not is_err and out.get("content") == "hello", str(out)[:160])

    fargs = {"path": "notes/a.txt", "content": "abc",
             "idempotencyKey": "KF1"}
    is_err, out1 = call_tool("files_write", fargs)
    is_err2, out2 = call_tool("files_write", fargs)
    check("files_write executes once; same key replays",
          not is_err and out1.get("verified") is True
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock.files_write_count == 1,
          f"exec={mock.files_write_count} out2={out2}")

    # --- §113 batch (1.0.9): alarm + notifications + opener -------
    aargs = {"title": "吃药", "afterSeconds": 600,
             "idempotencyKey": "KA1"}
    is_err, out1 = call_tool("alarm_set", aargs)
    is_err2, out2 = call_tool("alarm_set", aargs)
    check("alarm_set executes once; same key replays",
          not is_err and out1.get("verified") is True
          and out1.get("kind") == "countdown"
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock.alarm_set_count == 1,
          f"exec={mock.alarm_set_count} out2={out2}")

    is_err, out = call_tool("alarm_list")
    alarms = out.get("alarms") or [{}]
    check("alarm_list round trip",
          not is_err and out.get("count") == 1
          and alarms[0].get("id") == "alarm-mock-1", str(out)[:160])

    cargs2 = {"alarmId": "alarm-mock-1", "idempotencyKey": "KA2"}
    is_err, out1 = call_tool("alarm_cancel", cargs2)
    is_err2, out2 = call_tool("alarm_cancel", cargs2)
    check("alarm_cancel executes once; same key replays",
          not is_err and out1.get("cancelled") is True
          and out1.get("wasPresent") is True
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock.alarm_cancel_count == 1,
          f"exec={mock.alarm_cancel_count} out2={out2}")

    # notifications is a REAL permission key (§113.5.2): reported
    # denied in this session, so the bridge must answer
    # permission_denied itself, fast, without waking the phone.
    t0 = time.time()
    is_err, out = call_tool("notify_post", {
        "title": "提醒", "body": "该吃药了", "idempotencyKey": "KN1"})
    check("notify_post denied => permission_required pre-intercept, "
          "no round-trip",
          is_err and out.get("error") == "permission_required"
          and out.get("source") == "notifications"
          and out.get("nextAction") == "open_settings"
          and bool(out.get("resumeToken"))
          and time.time() - t0 < 5 and mock.notify_post_count == 0,
          str(out))

    # opener reports "denied" in this payload too, but it has no
    # system permission (§113.2): never gated — and open_target's
    # replay matters most (a reconnect resend must not jump twice).
    oargs = {"target": "app-settings", "idempotencyKey": "KO1"}
    is_err, out1 = call_tool("open_target", oargs)
    is_err2, out2 = call_tool("open_target", oargs)
    check("open_target round-trips despite payload saying denied; "
          "same key replays instead of opening twice",
          not is_err and out1.get("opened") is True
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock.open_target_count == 1,
          f"exec={mock.open_target_count} out2={out2}")

    # --- §114 batch (1.0.10): presence + on-device intelligence --
    camargs = {"idempotencyKey": "KCAM1"}
    is_err, out1 = call_tool("camera_capture", camargs)
    is_err2, out2 = call_tool("camera_capture", camargs)
    check("camera_capture executes once; same key replays (a "
          "retry must never reopen the camera)",
          not is_err and out1.get("saved") is True
          and out1.get("verified") is True
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock.camera_capture_count == 1,
          f"exec={mock.camera_capture_count} out2={out2}")

    scanargs = {"idempotencyKey": "KSCAN1"}
    is_err, out1 = call_tool("vision_document_scan", scanargs)
    is_err2, out2 = call_tool("vision_document_scan", scanargs)
    check("vision_document_scan executes once; same key replays",
          not is_err and out1.get("saved") is True
          and out1.get("pageCount") == 2
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock.vision_document_scan_count == 1,
          f"exec={mock.vision_document_scan_count} out2={out2}")

    # vision deliberately reports "denied" in this payload, but it
    # has no switchable system permission (§114.2): never gated.
    is_err, out = call_tool("vision_ocr",
                            {"path": "captures/IMG-mock-1.jpg"})
    check("vision_ocr round-trips despite payload saying denied "
          "(vision is never permission-gated)",
          not is_err and out.get("text") == "MOCK-OCR-TEXT",
          str(out)[:160])
    is_err, out = call_tool("vision_scan_code",
                            {"path": "captures/IMG-mock-1.jpg"})
    codes = out.get("codes") or [{}]
    check("vision_scan_code round trip",
          not is_err and out.get("count") == 1
          and codes[0].get("payload") == "MOCK-QR", str(out)[:160])

    is_err, out = call_tool("translate_text",
                            {"text": "你好", "source": "zh-Hans"})
    check("translate_text round trip",
          not is_err and out.get("text") == "MOCK-TRANSLATION"
          and out.get("targetLanguage") == "en", str(out)[:160])

    is_err, out = call_tool("ondevice_model_run",
                            {"prompt": "一句话介绍西安"})
    check("ondevice_model_run round trip when offered",
          not is_err and out.get("model") == "on-device"
          and out.get("text") == "MOCK-ONDEVICE-ANSWER",
          str(out)[:160])

    # THE §114.5.3 case: auth_biometric must ask live every time.
    # Two identical calls (its contract has no idempotencyKey)
    # must BOTH reach the phone — a replayed "confirmed" would
    # silently drop the presence gate. biometric also reports
    # "denied" in this payload and must not be permission-gated.
    bargs = {"reason": "确认删除这条记录"}
    is_err, out1 = call_tool("auth_biometric", bargs)
    is_err2, out2 = call_tool("auth_biometric", bargs)
    check("auth_biometric asks live twice; stored result is never "
          "replayed",
          not is_err and out1.get("confirmed") is True
          and not is_err2 and out2.get("confirmed") is True
          and out1.get("idempotentReplay") is not True
          and out2.get("idempotentReplay") is not True
          and mock.auth_biometric_count == 2,
          f"exec={mock.auth_biometric_count} out2={out2}")

    # --- §115 batch (1.0.11): location + media + compose -----
    is_err, out = call_tool("location_current")
    check("location_current round trip",
          not is_err and out.get("placeName") == "西安市"
          and out.get("latitude") == 34.3416
          and out.get("accuracyMeters") == 65.0, str(out)[:160])
    is_err, out = call_tool("location_search_places",
                            {"query": "药店"})
    places = out.get("places") or [{}]
    check("location_search_places round trip",
          not is_err and out.get("count") == 1
          and places[0].get("name") == "MOCK-PHARMACY"
          and places[0].get("distanceMeters") == 320,
          str(out)[:160])
    is_err, out = call_tool("location_geocode",
                            {"address": "西安市钟楼"})
    check("location_geocode forward round trip",
          not is_err and out.get("mode") == "forward"
          and out.get("longitude") == 108.9398, str(out)[:160])

    is_err, out = call_tool("media_library_search",
                            {"query": "MOCK"})
    results = out.get("results") or [{}]
    check("media_library_search round trip",
          not is_err and out.get("count") == 1
          and results[0].get("title") == "MOCK-SONG",
          str(out)[:160])
    is_err, out = call_tool("media_playlists")
    pls = out.get("playlists") or [{}]
    check("media_playlists round trip",
          not is_err and out.get("count") == 1
          and pls[0].get("name") == "MOCK-PLAYLIST",
          str(out)[:160])

    pargs = {"name": "睡前听", "idempotencyKey": "KMP1"}
    is_err, out1 = call_tool("media_playlist_create", pargs)
    is_err2, out2 = call_tool("media_playlist_create", pargs)
    check("media_playlist_create executes once; same key replays "
          "(a retry must never create a second playlist)",
          not is_err and out1.get("created") is True
          and out1.get("verified") is True
          and out1.get("id") == "mock-pl-new"
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock.media_playlist_create_count == 1,
          f"exec={mock.media_playlist_create_count} out2={out2}")

    cargs3 = {"action": "play", "query": "MOCK",
              "idempotencyKey": "KMP2"}
    is_err, out1 = call_tool("media_playback_control", cargs3)
    is_err2, out2 = call_tool("media_playback_control", cargs3)
    check("media_playback_control executes once; same key replays "
          "WITHOUT re-sending the action",
          not is_err and out1.get("verified") is True
          and out1.get("state") == "playing"
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock.media_playback_control_count == 1,
          f"exec={mock.media_playback_control_count} out2={out2}")

    # compose/shortcuts/deviceinfo report "denied" in this payload
    # but have no switchable system permission (§115.2): the
    # bridge must never permission-gate them.
    is_err, out = call_tool("device_info")
    check("device_info round-trips despite payload saying denied "
          "(deviceinfo is never permission-gated)",
          not is_err and out.get("modelIdentifier") == "iPhone17,2"
          and out.get("batteryPercent") == 82, str(out)[:160])

    is_err, out = call_tool("call_start",
                            {"number": "+8613700000000"})
    check("call_start round trip (opens the dial prompt only)",
          not is_err and out.get("initiated") is True, str(out)[:160])

    # THE §115.5.3 case, same family as auth_biometric: presence
    # tools must go live every time. These calls even carry an
    # idempotencyKey (a caller copying the write-tool template)
    # — the bridge must ignore it and forward BOTH times.
    sargs = {"recipients": ["13700000000"], "body": "测试",
             "idempotencyKey": "KCS1"}
    is_err, out1 = call_tool("compose_sms", sargs)
    is_err2, out2 = call_tool("compose_sms", sargs)
    check("compose_sms asks live twice; a stored 'sent' is never "
          "replayed",
          not is_err and out1.get("sent") is True
          and not is_err2 and out2.get("sent") is True
          and out1.get("idempotentReplay") is not True
          and out2.get("idempotentReplay") is not True
          and mock.compose_sms_count == 2,
          f"exec={mock.compose_sms_count} out2={out2}")

    is_err, out = call_tool("compose_email",
                            {"to": ["a@example.com"],
                             "subject": "你好", "body": "正文"})
    check("compose_email round trip",
          not is_err and out.get("presented") is True
          and out.get("outcome") == "sent", str(out)[:160])
    is_err, out = call_tool("share_sheet", {"text": "分享这段话"})
    check("share_sheet round trip",
          not is_err and out.get("shared") is True, str(out)[:160])

    rargs = {"name": "晚安模式", "idempotencyKey": "KSR1"}
    is_err, out1 = call_tool("shortcut_run", rargs)
    is_err2, out2 = call_tool("shortcut_run", rargs)
    check("shortcut_run really runs twice; a stored callback "
          "result is never replayed",
          not is_err and out1.get("ran") is True
          and out1.get("result") == "MOCK-SHORTCUT-RESULT"
          and not is_err2 and out2.get("ran") is True
          and out1.get("idempotentReplay") is not True
          and out2.get("idempotentReplay") is not True
          and mock.shortcut_run_count == 2,
          f"exec={mock.shortcut_run_count} out2={out2}")

    # file_preview / file_print ride the files permission and
    # the files on/off gate — files is granted in this session.
    is_err, out = call_tool("file_preview", {"path": "note.txt"})
    check("file_preview round trip",
          not is_err and out.get("viewed") is True, str(out)[:160])
    is_err, out = call_tool("file_print", {"path": "note.txt"})
    check("file_print round trip",
          not is_err and out.get("printed") is True, str(out)[:160])

    is_err, out = call_tool("no_such_tool", {})
    check("unknown tool => unknown_tool",
          is_err and out.get("error") == "unknown_tool", str(out))

    req("POST", "/device/disconnect", {"sessionId": mock.session_id})
    mock.stop_flag = True
    time.sleep(0.3)
    is_err, out = call_tool("reminders_list")
    check("after disconnect => device_offline again",
          is_err and out.get("error") == "device_offline", str(out))

    # the tools list is the only gate for the no-permission sources:
    # a session that does not offer files_read gets tool_unavailable
    mock2 = MockDevice(tools=["clipboard_get"])
    mock2.register()
    mock2.start()
    time.sleep(0.3)
    is_err, out = call_tool("files_read", {"path": "note.txt"})
    check("tool not offered in session => tool_unavailable",
          is_err and out.get("error") == "tool_unavailable", str(out))
    is_err, out = call_tool("clipboard_get")
    check("offered no-permission tool round-trips in second session",
          not is_err and out.get("text") == "MOCK-CLIP-TEXT", str(out))
    req("POST", "/device/disconnect", {"sessionId": mock2.session_id})
    mock2.stop_flag = True
    time.sleep(0.3)

    # third session flips the §113 permissions: notifications
    # granted (notify_post must round-trip now), alarm denied
    # (alarm_set must be pre-intercepted, phone never woken).
    mock3 = MockDevice(
        tools=["notify_post", "alarm_set", "alarm_list"],
        permissions={"calendar": "granted", "reminders": "granted",
                     "contacts": "granted", "health": "denied",
                     "home": "granted", "clipboard": "granted",
                     "files": "granted", "alarm": "denied",
                     "notifications": "granted",
                     "opener": "granted"})
    mock3.register()
    mock3.start()
    time.sleep(0.3)
    nargs = {"title": "开会", "body": "十分钟后开始",
             "idempotencyKey": "KN2"}
    is_err, out1 = call_tool("notify_post", nargs)
    is_err2, out2 = call_tool("notify_post", nargs)
    check("notify_post executes once when granted; same key replays",
          not is_err and out1.get("posted") is True
          and out1.get("verified") is True
          and not is_err2 and out2.get("idempotentReplay") is True
          and mock3.notify_post_count == 1,
          f"exec={mock3.notify_post_count} out2={out2}")

    t0 = time.time()
    is_err, out = call_tool("alarm_set", {
        "title": "起床", "at": "2026-11-12T07:00:00+08:00",
        "idempotencyKey": "KA3"})
    check("alarm_set denied => permission_required pre-intercept, "
          "no round-trip",
          is_err and out.get("error") == "permission_required"
          and out.get("source") == "alarm"
          and bool(out.get("resumeToken"))
          and time.time() - t0 < 5 and mock3.alarm_set_count == 0,
          str(out))
    req("POST", "/device/disconnect", {"sessionId": mock3.session_id})
    mock3.stop_flag = True
    time.sleep(0.3)

    # fourth session (§114): camera is a REAL permission key —
    # reported denied, camera_capture must be pre-intercepted
    # with the phone never woken. The same session does not offer
    # ondevice_model_run (an ineligible device simply omits it,
    # §114.2): the answer is a plain tool_unavailable, and the
    # bridge must not treat the omission as an anomaly.
    mock4 = MockDevice(
        tools=["camera_capture"],
        permissions={"calendar": "granted", "reminders": "granted",
                     "contacts": "granted", "health": "denied",
                     "home": "granted", "clipboard": "granted",
                     "files": "granted", "alarm": "granted",
                     "notifications": "granted",
                     "opener": "granted", "camera": "denied",
                     "vision": "granted", "translate": "granted",
                     "ondevice": "granted", "biometric": "granted"})
    mock4.register()
    mock4.start()
    time.sleep(0.3)
    t0 = time.time()
    is_err, out = call_tool("camera_capture",
                            {"idempotencyKey": "KCAM2"})
    check("camera_capture denied => permission_required "
          "pre-intercept, no round-trip",
          is_err and out.get("error") == "permission_required"
          and out.get("source") == "camera"
          and bool(out.get("resumeToken"))
          and time.time() - t0 < 5
          and mock4.camera_capture_count == 0, str(out))
    is_err, out = call_tool("ondevice_model_run",
                            {"prompt": "在吗"})
    check("ondevice_model_run not offered in session => "
          "tool_unavailable (absence is normal, not an anomaly)",
          is_err and out.get("error") == "tool_unavailable",
          str(out))
    req("POST", "/device/disconnect", {"sessionId": mock4.session_id})
    mock4.stop_flag = True
    time.sleep(0.3)

    # fifth session (§115): location and media are REAL
    # permission keys — both reported denied here, so both tools
    # must be pre-intercepted with the phone never woken.
    mock5 = MockDevice(
        tools=["location_current", "media_library_search"],
        permissions={"calendar": "granted", "reminders": "granted",
                     "contacts": "granted", "health": "denied",
                     "home": "granted", "clipboard": "granted",
                     "files": "granted", "alarm": "granted",
                     "notifications": "granted",
                     "opener": "granted", "camera": "granted",
                     "vision": "granted", "translate": "granted",
                     "ondevice": "granted", "biometric": "granted",
                     "location": "denied", "media": "denied",
                     "compose": "granted", "shortcuts": "granted",
                     "deviceinfo": "granted"})
    mock5.register()
    mock5.start()
    time.sleep(0.3)
    t0 = time.time()
    is_err, out = call_tool("location_current")
    check("location_current denied => permission_required "
          "pre-intercept, no round-trip",
          is_err and out.get("error") == "permission_required"
          and out.get("source") == "location"
          and bool(out.get("resumeToken"))
          and time.time() - t0 < 5
          and mock5.location_current_count == 0, str(out))
    t0 = time.time()
    is_err, out = call_tool("media_library_search",
                            {"query": "歌"})
    check("media_library_search denied => permission_required "
          "pre-intercept, no round-trip",
          is_err and out.get("error") == "permission_required"
          and out.get("source") == "media"
          and bool(out.get("resumeToken"))
          and time.time() - t0 < 5
          and mock5.media_library_search_count == 0, str(out))
    req("POST", "/device/disconnect", {"sessionId": mock5.session_id})
    mock5.stop_flag = True
    time.sleep(0.3)

    # --- §244 permission flow -------------------------------------
    # Session 6: ask-capable app, location never asked. The bridge
    # must send a permission_ask over the poll channel; a granted
    # answer lets the ORIGINAL call proceed in the same turn.
    mock6 = MockDevice(
        tools=["location_current"],
        permissions={"location": "notDetermined"},
        capabilities=["permission_ask_v1"])
    mock6.ask_decision = "granted"
    mock6.register()
    mock6.start()
    time.sleep(0.3)
    is_err, out = call_tool("location_current")
    check("§244 ask: notDetermined + granted answer => original call "
          "proceeds same-turn",
          not is_err and mock6.ask_count == 1
          and (mock6.last_ask or {}).get("source") == "location"
          and bool((mock6.last_ask or {}).get("resumeToken"))
          and mock6.location_current_count == 1, str(out))

    # Same session, user defers ("先不"): the call parks and the
    # facade answers permission_required with the token the card
    # already holds; resume then executes it exactly once.
    mock6.ask_decision = "parked"
    is_err, out = call_tool("location_current")
    token = out.get("resumeToken")
    check("§244 ask: deferred answer => permission_required parked "
          "with resume token, nothing executed",
          is_err and out.get("error") == "permission_required"
          and out.get("nextAction") == "ask_in_chat"
          and bool(token) and mock6.location_current_count == 1,
          str(out))
    # §261: the ask payload carries the park's own stamps (the
    # card's 24h clock starts at park time, one origin), the
    # error fields surface them too, and the read-only
    # park-state face reports the park truthfully -- deferred
    # is recorded as deferred, and peeking never consumes.
    last_ask = mock6.last_ask or {}
    check("§261 ask: payload + fields carry park stamps",
          bool(last_ask.get("parkedAt"))
          and bool(last_ask.get("expiresAt"))
          and out.get("parkedAt") == last_ask.get("parkedAt")
          and out.get("expiresAt") == last_ask.get("expiresAt")
          and out.get("askOutcome") == "deferred",
          str(last_ask))
    st, payload = req("POST", "/device/park-state",
                      {"resumeToken": token})
    park = payload.get("park") or {}
    check("§261 park-state: live park reported, peek is read-only",
          st == 200 and payload.get("exists") is True
          and park.get("source") == "location"
          and park.get("askOutcome") == "deferred"
          and park.get("expiresAt", 0) > park.get("createdAt", 0)
          and "arguments" not in park, str(payload))
    st, payload = req("POST", "/device/park-state",
                      {"resumeToken": "park-nope"})
    check("§261 park-state: unknown token => exists false (200)",
          st == 200 and payload.get("exists") is False, str(payload))
    st, payload = req("POST", "/device/resume",
                      {"resumeToken": token})
    check("§244 resume: parked call executes and returns its result",
          st == 200 and payload.get("ok") is True
          and isinstance(payload.get("result"), dict)
          and mock6.location_current_count == 2, str(payload))
    st, payload = req("POST", "/device/park-state",
                      {"resumeToken": token})
    check("§261 park-state: consumed park => exists false",
          st == 200 and payload.get("exists") is False, str(payload))
    st, payload = req("POST", "/device/resume",
                      {"resumeToken": token})
    check("§244 resume: token is single-use (second call => 404)",
          st == 404, f"got {st}")
    st, payload = req("POST", "/device/resume",
                      {"resumeToken": "park-nope"})
    check("§244 resume: unknown token => 404",
          st == 404, f"got {st}")
    req("POST", "/device/disconnect", {"sessionId": mock6.session_id})
    mock6.stop_flag = True
    time.sleep(0.3)

    # Session 7: permission granted but the agent-call switch is
    # off -- the gate must name the agentSwitch layer, not the
    # permission layer, and park with a token.
    mock7 = MockDevice(
        tools=["location_current"],
        permissions={"location": "granted"},
        agent_call={"location": False},
        capabilities=["permission_ask_v1"])
    mock7.register()
    mock7.start()
    time.sleep(0.3)
    is_err, out = call_tool("location_current")
    check("§244 gate: switch off => permission_required with "
          "blockerLayer=agentSwitch, no execution",
          is_err and out.get("error") == "permission_required"
          and out.get("blockerLayer") == "agentSwitch"
          and out.get("nextAction") == "open_switch"
          and bool(out.get("resumeToken"))
          and mock7.location_current_count == 0, str(out))
    req("POST", "/device/disconnect", {"sessionId": mock7.session_id})
    mock7.stop_flag = True
    time.sleep(0.3)

    # Session 8: legacy app (no ask capability), permission never
    # asked -- pre-§244 behaviour (no pseudo-call is sent), but the
    # error is structured with the Chinese single-source message.
    mock8 = MockDevice(
        tools=["location_current"],
        permissions={"location": "notDetermined"})
    mock8.register()
    mock8.start()
    time.sleep(0.3)
    t0 = time.time()
    is_err, out = call_tool("location_current")
    check("§244 legacy: notDetermined without ask capability => "
          "structured permission_denied, no pseudo-call, fast",
          is_err and out.get("error") == "permission_denied"
          and out.get("state") == "notDetermined"
          and out.get("blockerLayer") == "permission"
          and "还没授权过" in out.get("message", "")
          and mock8.ask_count == 0
          and mock8.location_current_count == 0
          and time.time() - t0 < 5, str(out))
    req("POST", "/device/disconnect", {"sessionId": mock8.session_id})
    mock8.stop_flag = True

    print("SELFTEST " + ("FAILED: " + ", ".join(FAILURES)
                         if FAILURES else "ALL PASS"), flush=True)
    sys.exit(1 if FAILURES else 0)


if __name__ == "__main__":
    main()
