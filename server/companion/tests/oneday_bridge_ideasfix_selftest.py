#!/usr/bin/env python3
"""Ideas B-fix self-test (2026-11-24): the three assembly fixes
for the ideas generation round --
B1. the stored-card lists (已有卡片 / 已忽略清单) print titles
    only; the old rounds' relative evidenceRefs are gone, so
    they can no longer collide with this round's renumbered
    refs;
B2. the K source feeds only non-done kanban tasks;
B3. a stale calendar copy stops the whole C section: zero
    events served, the material says 无可用日程 instead of
    printing the frozen copy's leftover (holiday) rows.

The A fix (published feed posts as a P material source) was
prefabricated and then REMOVED on the user's 2026-11-24 ruling
(ideas eat only the user's own material: sessions / goals /
kanban / memory / calendar). Phase 0 asserts the removal:
no P section, no P prompt note, P is not a valid ref shape,
and a stored feed post never enters the material.

In-process throughout, following the p7 harness shape: the
bridge is loaded from the staged module copies, the clock is
frozen at 2026-11-24 09:00 Asia/Shanghai, network neighbours
are stubbed at the module seams (session digests, memory
excerpts, the ledger Dashboard channel, device_sync). The
kanban and calendar FETCHERS run for real -- B2/B3 live inside
them, stubbing them would test nothing.
"""
import importlib.util
import json
import os
import sys
import tempfile
import types
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.abspath(__file__))


def _sibling(name):
    p = os.path.join(HERE, name)
    if os.path.exists(p):
        return p
    return os.path.join(HERE, "..", "modules", name)


BRIDGE = _sibling("oneday_bridge.py")
sys.path.insert(0, os.path.dirname(os.path.abspath(BRIDGE)))
TZ = ZoneInfo("Asia/Shanghai")
FIXED_NOW = datetime(2026, 11, 24, 9, 0, tzinfo=TZ).timestamp()
DAY = 24 * 3600

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def iso_utc(ts):
    return datetime.fromtimestamp(ts, timezone.utc).isoformat()


class FakeDash:
    """The ledger's Dashboard channel seam: .get(path) -> payload."""

    def __init__(self, payload):
        self.payload = payload

    def get(self, path):
        return self.payload


def make_fake_dsync(events, synced_at):
    ds = types.ModuleType("device_sync")

    class CopyEmpty(Exception):
        pass

    class SyncError(Exception):
        def __init__(self, code, message=""):
            super().__init__(message)
            self.code = code
            self.message = message

    ds.CopyEmpty = CopyEmpty
    ds.SyncError = SyncError
    ds.init = lambda d: None
    ds.calendar_copy_events = lambda start, end: (
        events, {"synced_at": synced_at})
    ds._parse_ts = lambda v: (
        datetime.fromisoformat(v).timestamp() if v else None)
    return ds


def cal_ev(oid, title, start_ts, end_ts, calendar="个人"):
    return {"occurrenceId": oid, "title": title,
            "start": iso_utc(start_ts), "end": iso_utc(end_ts),
            "allDay": False, "calendarName": calendar,
            "location": ""}


def main():
    tmp = tempfile.mkdtemp(prefix="ideasfix-")
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump({"goals": [], "ideas": [], "monitors": [],
                   "changes": [], "goalEntries": [], "briefings": [],
                   "feedPosts": [], "goalTaskLinks": [], "meta": {}},
                  f, ensure_ascii=False)
    os.environ["ONEDAY_BRIDGE_KEY"] = "ideasfix-selftest-key"
    os.environ["DATA_PATH"] = data_path
    os.environ["HERMES_API_KEY"] = "fake-key"
    spec = importlib.util.spec_from_file_location("ob_ideasfix",
                                                  BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    mod._now = lambda: FIXED_NOW
    mod._fetch_memory_excerpts = lambda keywords: ([], None)

    # ---------- shared seed (11-17-shaped own material) -------
    mod._db["feedPosts"] = [{
        "id": "fp_rich", "kind": "research",
        "createdAt": FIXED_NOW - 2 * DAY,
        "title": "动态帖标题不该进点子素材",
        "body": "11月20日发布，处理速度提升 40%。",
        "category": "副业", "direction": "副业",
    }]
    mod._db["goals"] = [{"id": "g_1", "title": "副业数据卡",
                         "note": ""}]
    mod._db["ideas"] = [
        {"id": "i_live", "title": "已有卡片甲",
         "evidenceRef": "S3", "anchorId": "S:sess_old",
         "status": "pending", "createdAt": FIXED_NOW - DAY},
        {"id": "i_dis", "title": "已忽略卡片乙",
         "evidenceRef": "K2", "anchorId": "K:task_old",
         "status": "dismissed", "dismissReason": "tooGeneric",
         "statusAt": FIXED_NOW - DAY,
         "createdAt": FIXED_NOW - 2 * DAY},
    ]
    mod._fetch_session_digests = lambda: ([{
        "id": "sess_1", "title": "副业数据卡复盘",
        "startedAt": FIXED_NOW - DAY, "messageCount": 9,
        "summary": "11月23日定了 2.0 的发布节奏，300 人次使用后"
                   "先看留存再决定要不要加批量导出。"}], None)
    mod._ledger_dash = FakeDash({"tasks": [
        {"id": "t_done", "title": "已办完的任务",
         "status": "done", "updated_at": iso_utc(FIXED_NOW - DAY)},
        {"id": "t_block", "title": "卡住的任务",
         "status": "blocked",
         "updated_at": iso_utc(FIXED_NOW - DAY)},
    ]})
    ddir = os.path.join(tmp, "device-data")
    os.makedirs(ddir)
    Path(ddir, "sync.db").touch()
    sys.modules["device_sync"] = make_fake_dsync(
        [cal_ev("occ_1", "明天复盘会", FIXED_NOW + DAY,
                FIXED_NOW + DAY + 3600)],
        synced_at=FIXED_NOW - 3600)
    mod.DEVICE_DATA_DIR = Path(ddir)

    prompt, notes, goal_ids, anchors, lines = \
        mod._assemble_material()

    # ---------- phase 0: A removal guards ---------------------
    check("0 A removed: no P section, no P prompt note, no P "
          "anchors", "已发布动态帖" not in prompt
          and "补充素材编号" not in prompt
          and not any(a["kind"] == "P"
                      for a in anchors.values()))
    check("0 A removed: P is not a valid ref shape",
          not mod.ANCHOR_REF_RE.match("P1")
          and bool(mod.ANCHOR_REF_RE.match("S1")))
    check("0 A removed: a stored feed post never enters the "
          "material", "动态帖标题不该进点子素材" not in prompt)

    # ---------- B1: list refs removed -------------------------
    check("B1 stored-card lists print titles without old refs",
          "已有卡片甲" in prompt and "已忽略卡片乙" in prompt
          and "（据 S3）" not in prompt
          and "（据 K2）" not in prompt
          and "〔太泛〕" in prompt)

    # ---------- B2: kanban done filter ------------------------
    mod._ledger_dash = FakeDash({"tasks": [
        {"id": "t_d1", "title": "办完一", "status": "done",
         "updated_at": iso_utc(FIXED_NOW - DAY)},
        {"id": "t_d2", "title": "办完二", "status": "completed",
         "updated_at": iso_utc(FIXED_NOW - DAY)},
        {"id": "t_b", "title": "卡住三", "status": "blocked",
         "updated_at": iso_utc(FIXED_NOW - DAY)},
        {"id": "t_s", "title": "积压四", "status": "todo",
         "updated_at": iso_utc(FIXED_NOW - 10 * DAY)},
        {"id": "t_f", "title": "在办五", "status": "todo",
         "updated_at": iso_utc(FIXED_NOW - 3600)},
    ]})
    tasks, knote = mod._fetch_kanban_details()
    tids = [t["id"] for t in tasks]
    check("B2 fetcher drops done/completed, keeps the rest",
          tids and "t_d1" not in tids and "t_d2" not in tids
          and set(tids) == {"t_b", "t_s", "t_f"}, f"{tids}")
    by_id = {t["id"]: t for t in tasks}
    check("B2 signals: blocked 卡住, stale 长期未动",
          by_id["t_b"]["signal"] == "卡住"
          and by_id["t_s"]["signal"].startswith("长期未动"),
          f"{by_id}")
    prompt_b2, _, _, _, _ = mod._assemble_material()
    check("B2 material K section has no done titles",
          "办完一" not in prompt_b2 and "办完二" not in prompt_b2
          and "卡住三" in prompt_b2)

    # ---------- B3: stale calendar ----------------------------
    sys.modules["device_sync"] = make_fake_dsync(
        [cal_ev("occ_hol", "Thanksgiving", FIXED_NOW + 3 * DAY,
                FIXED_NOW + 3 * DAY + 3600, calendar="US Holidays"),
         cal_ev("occ_meet", "过期副本里的会", FIXED_NOW + DAY,
                FIXED_NOW + DAY + 3600)],
        synced_at=FIXED_NOW - 25 * 3600)
    evs, cnote = mod._fetch_calendar_events()
    check("B3 stale copy serves zero events, staleness noted",
          evs == [] and cnote is not None and "已过期" in cnote,
          f"{evs} {cnote}")
    prompt_b3, notes_b3, _, anchors_b3, _ = \
        mod._assemble_material()
    check("B3 material C section says 无可用日程, no stale rows, "
          "no C anchors",
          "（无可用日程：日历副本已过期）" in prompt_b3
          and "Thanksgiving" not in prompt_b3
          and "过期副本里的会" not in prompt_b3
          and not any(a["kind"] == "C"
                      for a in anchors_b3.values())
          and notes_b3.get("calendar") is not None
          and "已过期" in notes_b3["calendar"],
          f"{notes_b3}")
    sys.modules["device_sync"] = make_fake_dsync(
        [cal_ev("occ_ok", "健康副本的会", FIXED_NOW + DAY,
                FIXED_NOW + DAY + 3600)],
        synced_at=FIXED_NOW - 3600)
    evs2, cnote2 = mod._fetch_calendar_events()
    check("B3 healthy copy serves again",
          len(evs2) == 1 and cnote2 is None,
          f"{len(evs2)} {cnote2}")

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
