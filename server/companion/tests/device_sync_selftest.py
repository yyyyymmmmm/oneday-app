#!/usr/bin/env python3
"""device-sync end-to-end self-test: boots a real device_bridge copy
on a scratch port with a temp data dir and a mock phone, then drives
the sync channel and the MCP tools over HTTP.

Coverage (spec device-sync-design-20261110.md sections 2-5):
seeded contacts -> count/stats/list/search/get with exact numbers;
interrupted and count-mismatched batches keep the old copy; manifest
diff + incremental apply; partial auth range labelling; calendar
copy-or-whole-live rule (complexity audit item 2); reminders
counts; full photo index stats;
motion day-merge; pending-write mark; revoked permission stops
supply (2026-11-10 21:58 ruling); deletion falls back to live reads
and reclaims the store file.
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import urllib.error
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BRIDGE = next(p for p in (
    os.path.join(ROOT, "modules", "device_bridge.py"),
    os.path.join(HERE, "device_bridge.py")) if os.path.exists(p))
PORT = 8648
BASE = f"http://127.0.0.1:{PORT}"
KEY = "sync-selftest-key"
FAILURES = []
TMP = tempfile.mkdtemp(prefix="device-sync-test-")
DATA_DIR = os.path.join(TMP, "device-data")


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
          (f"  [{detail}]" if detail and not cond else ""), flush=True)
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


def sync_upload(dataset, batch_id, records, mode="full", **kw):
    st, out = req("POST", "/device/sync/batch",
                  {"dataset": dataset, "batchId": batch_id,
                   "records": records, "mode": mode})
    assert st == 200, (st, out)
    body = {"dataset": dataset, "batchId": batch_id,
            "expectedTotal": kw.pop("expected", len(records)),
            "deviceCompletedAt": kw.pop("completed_at", time.time()),
            "mode": mode}
    body.update(kw)
    return req("POST", "/device/sync/complete", body)


# ------------------------------------------------------------ mock phone
class MockDevice(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.session_id = None
        self.stop_flag = False

    def register(self):
        _, payload = req("POST", "/device/session", {
            "deviceId": "mock-iphone-sync", "appVersion": "selftest",
            "permissions": {"calendar": "granted",
                            "reminders": "granted",
                            "contacts": "granted",
                            "health": "denied", "home": "granted"},
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
                {"id": "evt-live-1", "title": "MOCK-LIVE-EVENT",
                 "start": args.get("start"), "end": args.get("end")}]}
        if tool == "calendar_create_event":
            return {"objectId": "mock-created-1",
                    "title": args.get("title")}
        if tool == "contacts_search":
            return {"readAt": time.time(), "matches": [],
                    "echo": "live-contacts-search"}
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


CONTACTS = [
    {"id": "ct-1", "displayName": "张三", "familyName": "张",
     "givenName": "三",
     "phones": [{"value": "138 0000 1111", "label": "手机"}],
     "emails": [{"value": "zs@example.com", "label": "工作"}],
     "organization": "甲公司", "groups": ["家人"], "fingerprint": "fp1"},
    {"id": "ct-2", "displayName": "张三",
     "phones": [{"value": "13800001111", "label": "手机"}],
     "emails": [], "organization": None, "groups": ["家人"],
     "fingerprint": "fp2"},
    {"id": "ct-3", "displayName": "李四",
     "phones": [{"value": "13900002222", "label": "手机"}],
     "emails": [{"value": "ls@example.com", "label": ""}],
     "organization": None, "groups": ["同事"], "fingerprint": "fp3"},
    {"id": "ct-4", "displayName": "王五", "phones": [],
     "emails": [{"value": "ww@example.com", "label": ""}],
     "organization": None, "groups": [], "fingerprint": "fp4"},
    {"id": "ct-5", "displayName": "赵六",
     "phones": [{"value": "13700003333", "label": "手机"}],
     "emails": [], "organization": None, "groups": ["同事"],
     "fingerprint": "fp5"},
    {"id": "ct-6", "displayName": "李四",
     "phones": [{"value": "13600009999", "label": "手机"}],
     "emails": [], "organization": None, "groups": [],
     "fingerprint": "fp6"},
    {"id": "ct-7", "displayName": "孙七",
     "phones": [{"value": "13500007777", "label": "手机"}],
     "emails": [{"value": "sq@example.com", "label": ""}],
     "organization": None, "groups": ["家人"], "fingerprint": "fp7"},
]


def seed_contacts(batch="seed1"):
    st, out = req("POST", "/device/sync/batch",
                  {"dataset": "contacts", "batchId": batch,
                   "records": CONTACTS[:4], "mode": "full"})
    assert st == 200, (st, out)
    st, out = req("POST", "/device/sync/batch",
                  {"dataset": "contacts", "batchId": batch,
                   "records": CONTACTS[4:], "mode": "full"})
    assert st == 200 and out["received"] == 7, (st, out)
    return req("POST", "/device/sync/complete",
               {"dataset": "contacts", "batchId": batch,
                "expectedTotal": 7, "deviceCompletedAt": time.time(),
                "mode": "full", "authRange": "full"})


def main():
    env = dict(os.environ, DEVICE_BRIDGE_KEY=KEY,
               DATA_DIR=DATA_DIR, DEVICE_PORT=str(PORT),
               TZ="Asia/Shanghai")
    os.makedirs(DATA_DIR, exist_ok=True)
    proc = subprocess.Popen(
        [sys.executable, BRIDGE],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True)
    try:
        for _ in range(60):
            try:
                st, health = req("GET", "/health", auth=False)
                if st == 200:
                    break
            except Exception:
                pass
            time.sleep(0.5)
        check("bridge boots with sync store", health.get("ok") is True,
              str(health))
        db_path = os.path.join(DATA_DIR, "sync.db")
        check("sync.db created with 0600",
              os.path.exists(db_path)
              and (os.stat(db_path).st_mode & 0o777) == 0o600,
              oct(os.stat(db_path).st_mode & 0o777)
              if os.path.exists(db_path) else "missing")

        mock = MockDevice()
        mock.register()
        mock.start()
        time.sleep(0.3)

        # ---- contacts: seed + exact numbers --------------------------
        st, receipt = seed_contacts()
        check("contacts complete receipt",
              st == 200 and receipt["total_in_store"] == 7
              and receipt["received"] == 7
              and receipt["auth_range"] == "full", str(receipt))
        is_err, out = call_tool("contacts_count")
        check("contacts_count = 7 with envelope",
              not is_err and out["total"] == 7
              and out["source"] == "sync_copy"
              and out["auth_range"] == "full"
              and "数据截至" in out["freshness"]
              and bool(out["synced_at"]), str(out))
        is_err, out = call_tool("contacts_stats")
        check("contacts_stats exact",
              not is_err and out["total"] == 7
              and out["with_phone"] == 6
              and out["with_phone_pct"] == 85.7
              and out["with_email"] == 4
              and out["with_email_pct"] == 57.1
              and out["by_group"] == {"家人": 3, "同事": 2}
              and out["duplicate_candidate_groups"] == 2, str(out))
        is_err, page1 = call_tool("contacts_list", {"limit": 3,
                                                    "offset": 0})
        is_err2, page3 = call_tool("contacts_list", {"limit": 3,
                                                     "offset": 6})
        check("contacts_list paging",
              not is_err and page1["total_matches"] == 7
              and page1["returned"] == 3 and page1["has_more"] is True
              and not is_err2 and page3["returned"] == 1
              and page3["has_more"] is False
              and set(page1["contacts"][0].keys())
              == {"id", "displayName", "primaryPhone", "organization"},
              str(page1)[:200])
        is_err, out = call_tool("contacts_search",
                                {"query": "13800001111"})
        check("contacts_search by bare digits matches spaced number",
              not is_err and out["total_matches"] == 2
              and {c["id"] for c in out["contacts"]} == {"ct-1", "ct-2"},
              str(out)[:200])
        is_err, out = call_tool("contacts_search", {"query": "李四"})
        check("contacts_search by name",
              not is_err and out["total_matches"] == 2, str(out)[:160])
        is_err, out = call_tool("contacts_get", {"contactId": "ct-4"})
        check("contacts_get minimal fields only",
              not is_err
              and out["contact"]["displayName"] == "王五"
              and out["contact"]["phones"] == []
              and "notes" not in out["contact"]
              and "fingerprint" not in out["contact"], str(out)[:200])

        # ---- interrupted / mismatched batches keep the old copy ------
        req("POST", "/device/sync/batch",
            {"dataset": "contacts", "batchId": "half",
             "records": CONTACTS[:2], "mode": "full"})
        is_err, out = call_tool("contacts_count")
        check("staged-but-unfinished batch changes nothing",
              not is_err and out["total"] == 7, str(out))
        st, out = req("POST", "/device/sync/complete",
                      {"dataset": "contacts", "batchId": "half",
                       "expectedTotal": 5,
                       "deviceCompletedAt": time.time(), "mode": "full"})
        is_err, cnt = call_tool("contacts_count")
        check("count mismatch => 409 and old copy intact",
              st == 409 and out.get("error") == "sync_count_mismatch"
              and not is_err and cnt["total"] == 7, str(out))

        # ---- manifest diff + incremental apply -----------------------
        entries = [{"id": c["id"], "fingerprint": c["fingerprint"]}
                   for c in CONTACTS if c["id"] != "ct-7"]
        entries[2]["fingerprint"] = "fp3-changed"
        entries.append({"id": "ct-8", "fingerprint": "fp8"})
        st, diff = req("POST", "/device/sync/manifest",
                       {"dataset": "contacts", "entries": entries})
        check("manifest diff exact",
              st == 200
              and set(diff["changed_ids"]) == {"ct-3", "ct-8"}
              and diff["removed_ids"] == ["ct-7"]
              and diff["unchanged_count"] == 5
              and diff["current_total"] == 7, str(diff))
        changed_ct3 = dict(CONTACTS[2])
        changed_ct3["phones"] = [{"value": "13900002223",
                                   "label": "手机"}]
        changed_ct3["fingerprint"] = "fp3-changed"
        new_ct8 = {"id": "ct-8", "displayName": "周八",
                   "phones": [{"value": "13400008888", "label": "手机"}],
                   "emails": [], "organization": None, "groups": [],
                   "fingerprint": "fp8"}
        st, out = sync_upload("contacts", "inc1",
                              [changed_ct3, new_ct8], mode="incremental",
                              removedIds=["ct-7"])
        is_err, cnt = call_tool("contacts_count")
        is_err2, got = call_tool("contacts_get", {"contactId": "ct-3"})
        is_err3, gone = call_tool("contacts_get",
                                  {"contactId": "ct-7"})
        check("incremental apply: update + insert + remove",
              st == 200 and not is_err and cnt["total"] == 7
              and not is_err2
              and got["contact"]["phones"][0]["value"] == "13900002223"
              and is_err3
              and gone.get("error") == "contact_not_found",
              str(out) + str(gone))

        # ---- partial auth range labelling ----------------------------
        st, out = req("POST", "/device/sync/state",
                      {"dataset": "contacts",
                       "authRange": "limited"})
        is_err, cnt = call_tool("contacts_count")
        check("range change flags reimport; results carry range note",
              st == 200 and out["reimport_required"] is True
              and not is_err and cnt["auth_range"] == "limited"
              and "部分" in cnt.get("range_note", ""), str(cnt))
        req("POST", "/device/sync/state",
            {"dataset": "contacts", "authRange": "full"})

        # ---- calendar: copy-or-whole-live (audit item 2) ------------
        cov = {"start": "2026-10-11T00:00:00+08:00",
               "end": "2027-02-08T23:59:59+08:00"}
        events = [
            {"occurrenceId": "occ-1", "eventId": "ev-1",
             "title": "团队周会", "start": "2026-11-12T10:00:00+08:00",
             "end": "2026-11-12T11:00:00+08:00", "allDay": False,
             "calendarName": "工作", "location": "会议室"},
            {"occurrenceId": "occ-2", "eventId": "ev-2",
             "title": "牙医", "start": "2026-11-20T09:00:00+08:00",
             "end": "2026-11-20T09:30:00+08:00", "allDay": False,
             "calendarName": "个人", "location": None},
            {"occurrenceId": "occ-3", "eventId": "ev-3",
             "title": "出差上海", "start": "2026-12-01T08:00:00+08:00",
             "end": "2026-12-03T20:00:00+08:00", "allDay": False,
             "calendarName": "工作", "location": "上海"}]
        st, out = sync_upload("calendar", "cal1", events,
                              coverage=cov)
        check("calendar seed receipt", st == 200
              and out["total_in_store"] == 3, str(out))
        is_err, out = call_tool(
            "calendar_list_events",
            {"start": "2026-11-10T00:00:00+08:00",
             "end": "2026-11-30T23:59:59+08:00"})
        check("calendar list fully inside coverage => copy only",
              not is_err and out["servedBy"] == "sync_copy"
              and len(out["events"]) == 2
              and out["coverage"]["start"] == cov["start"], str(out)[:220])
        is_err, out = call_tool(
            "calendar_list_events",
            {"start": "2026-11-10T00:00:00+08:00",
             "end": "2027-03-01T00:00:00+08:00"})
        evs = out.get("events") or []
        check("calendar list past coverage => whole live call, "
              "no stitched segments",
              not is_err and out["servedBy"] == "live_fallback"
              and "segments" not in out and "uncovered" not in out
              and len(evs) == 1
              and evs[0].get("title") == "MOCK-LIVE-EVENT"
              and evs[0].get("start") == "2026-11-10T00:00:00+08:00"
              and evs[0].get("end") == "2027-03-01T00:00:00+08:00",
              str(out)[:220])
        is_err, out = call_tool(
            "calendar_count",
            {"start": "2026-11-01T00:00:00+08:00",
             "end": "2026-11-30T23:59:59+08:00"})
        check("calendar_count in window = 2",
              not is_err and out["count"] == 2, str(out))
        is_err, out = call_tool("calendar_search", {"query": "牙医"})
        check("calendar_search hits copy",
              not is_err and out["total_matches"] == 1, str(out))

        # ---- reminders ------------------------------------------------
        now = datetime.now()
        today = now.strftime("%Y-%m-%d")
        yesterday = (now - timedelta(days=1)).strftime("%Y-%m-%d")
        rems = [
            {"id": "rm-1", "title": "交水电费",
             "due": f"{today}T18:00:00+08:00", "priority": 1,
             "listName": "生活"},
            {"id": "rm-2", "title": "过期的报告",
             "due": f"{yesterday}T10:00:00+08:00", "priority": 2,
             "listName": "工作"},
            {"id": "rm-3", "title": "无日期的想法", "due": None,
             "priority": 0, "listName": "生活"}]
        st, out = sync_upload("reminders", "rem1", rems,
                              aggregates={"todayCompleted": 3,
                                          "overdueCount": 1})
        is_err, cnt = call_tool("reminders_count")
        is_err2, lst = call_tool("reminders_list")
        check("reminders count/list from copy",
              st == 200 and not is_err and cnt["incomplete"] == 3
              and cnt["due_today"] == 1 and cnt["overdue"] == 1
              and cnt["today_completed"] == 3
              and not is_err2 and lst["incomplete_count"] == 3
              and lst["source"] == "sync_copy", str(cnt))

        # ---- photos: full index, aggregates computed ------------------
        assets = []
        for i in range(1200):
            month = 1 + i % 10
            assets.append({
                "assetId": f"ph-{i}",
                "createdAt": f"2026-{month:02d}-15T10:00:00+08:00",
                "mediaType": "video" if i % 5 == 0 else "photo",
                "subtype": "screenshot" if i % 150 == 0 else None,
                "width": 4032, "height": 3024,
                "durationSec": 12.5 if i % 5 == 0 else None,
                "isFavorite": i % 100 == 0,
                "albumName": "截图" if i % 150 == 0 else "相机",
                "hasLocation": i % 3 == 0})
        for j in range(3):
            chunk = assets[j * 500:(j + 1) * 500]
            st, out = req("POST", "/device/sync/batch",
                          {"dataset": "photos", "batchId": "ph1",
                           "records": chunk, "mode": "full"})
            assert st == 200, (st, out)
        st, out = req("POST", "/device/sync/complete",
                      {"dataset": "photos", "batchId": "ph1",
                       "expectedTotal": 1200,
                       "deviceCompletedAt": time.time(), "mode": "full"})
        is_err, stats = call_tool("photos_stats")
        by_month = {m["month"]: m for m in stats.get("by_month", [])}
        is_err2, recent = call_tool("photos_recent", {"limit": 5})
        check("photos full-index stats computed exactly",
              st == 200 and not is_err and stats["total"] == 1200
              and stats["by_media_type"] == {"photo": 960, "video": 240}
              and stats["favorites"] == 12
              and stats["screenshots"] == 8
              and len(by_month) == 10
              and by_month["2026-01"]["total"] == 120
              and not is_err2 and len(recent["assets"]) == 5
              and "width" not in recent["assets"][0], str(stats)[:200])

        # ---- motion: expired wording, then day-merge ------------------
        days1 = [{"date": f"2026-11-{d:02d}", "steps": 1000 + d,
                  "distanceM": 700.0, "flights": 2,
                  "source": "手机计步"} for d in range(4, 11)]
        st, out = sync_upload("motion", "mo1", days1, mode="merge",
                              completed_at=time.time() - 25 * 3600)
        is_err, summ = call_tool("motion_steps_summary", {"days": 7})
        check("motion freshness admits expired copy",
              st == 200 and not is_err and "已过期" in summ["freshness"]
              and "手机计步" in summ["source_note"], str(summ)[:200])
        expect = {r["date"]: r["steps"] for r in days1}
        days2 = [{"date": f"2026-11-{d:02d}",
                  "steps": 9999 if d == 10 else 1000 + d,
                  "distanceM": 700.0, "flights": 2,
                  "source": "手机计步"} for d in range(8, 15)]
        for r in days2:
            expect[r["date"]] = r["steps"]
        st, out = sync_upload("motion", "mo2", days2, mode="merge")
        is_err, summ = call_tool("motion_steps_summary", {"days": 30})
        got = {r["date"]: r["steps"] for r in summ.get("days", [])}
        check("motion merge: newer day wins, older days kept",
              st == 200 and not is_err and got == expect
              and summ["total_steps"] == sum(expect.values())
              and "已过期" not in summ["freshness"], str(got))

        # ---- pending write mark ---------------------------------------
        is_err, out = call_tool(
            "calendar_create_event",
            {"title": "新日程", "start": "2026-11-15T10:00:00+08:00",
             "end": "2026-11-15T11:00:00+08:00",
             "idempotencyKey": "sync-test-w1"})
        is_err2, status = call_tool("device_status")
        cal_sync = (status.get("sync") or {}).get("calendar") or {}
        check("write marks pending; status carries sync section",
              not is_err and out.get("objectId") == "mock-created-1"
              and not is_err2
              and cal_sync.get("pending_write") is True
              and cal_sync.get("item_count") == 3
              and (status.get("sync") or {}).get("contacts", {})
              .get("item_count") == 7, str(status)[:240])
        st, out = sync_upload("calendar", "cal2", events, coverage=cov)
        is_err, cnt = call_tool(
            "calendar_count",
            {"start": "2026-11-01T00:00:00+08:00",
             "end": "2026-11-30T23:59:59+08:00"})
        check("next sync clears the pending-write note",
              st == 200 and not is_err
              and "刚写入的一条" not in cnt["freshness"], str(cnt))

        # ---- revoked permission: stop supply --------------------------
        req("POST", "/device/sync/state",
            {"dataset": "contacts", "permissionState": "revoked"})
        is_err, out = call_tool("contacts_count")
        is_err2, status = call_tool("device_status")
        kept = (status.get("sync") or {}).get("contacts", {}) \
            .get("item_count")
        check("revoked => permission_required (§244 P-5 升格), no data, copy kept",
              is_err and out.get("error") == "permission_required"
              and out.get("blockerLayer") == "permission"
              and bool(out.get("resumeToken"))
              and "total" not in out and kept == 7, str(out))
        req("POST", "/device/sync/state",
            {"dataset": "contacts", "permissionState": "granted"})
        is_err, out = call_tool("contacts_count")
        check("re-grant resumes supply",
              not is_err and out["total"] == 7, str(out))

        # ---- deletion: fallback + reclaim -----------------------------
        size_before = os.path.getsize(db_path)
        st, out = req("POST", "/device/sync/delete",
                      {"dataset": "contacts"})
        is_err, out2 = call_tool("contacts_search", {"query": "张三"})
        check("deleted copy => live fallback, stamped",
              st == 200 and not is_err
              and out2.get("servedBy") == "live_fallback"
              and "现查" in out2.get("note", ""), str(out2)[:200])
        is_err, out = call_tool("contacts_count")
        check("copy-only tool after delete => sync_copy_empty",
              is_err and out.get("error") == "sync_copy_empty", str(out))
        st, out = req("POST", "/device/sync/delete", {})
        st2, status = req("GET", "/device/sync/status")
        zeroed = all(not d["synced"] and d["item_count"] == 0
                     for d in status["datasets"].values())
        size_after = os.path.getsize(db_path)
        check("delete all => zeroed status and file reclaimed",
              st == 200 and zeroed and size_after < size_before,
              f"{size_before} -> {size_after}")
    finally:
        mock.stop_flag = True
        proc.terminate()
        try:
            out = proc.stdout.read() if proc.stdout else ""
        except Exception:
            out = ""
        if FAILURES:
            print("---- bridge log tail ----")
            print("\n".join((out or "").splitlines()[-30:]))
    print("SELFTEST " + ("FAILED: " + ", ".join(FAILURES)
                         if FAILURES else "ALL PASS"), flush=True)
    sys.exit(1 if FAILURES else 0)


if __name__ == "__main__":
    main()
