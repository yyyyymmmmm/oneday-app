#!/usr/bin/env python3
"""P7 self-test for oneday_bridge.py ID-1: the ideas C source
(calendar sync copy, parity spec ch.4.2).

In-process throughout. The clock is frozen at 2026-11-12 07:30
Asia/Shanghai (the daily round's own hour) so windows and
proximity labels are deterministic. Device stores are seeded
ONLY through device_sync's sanctioned write path (stage_batch +
complete) -- never by writing SQLite rows directly. Each
scenario gets a fresh device_sync module instance (its init
latches once per process) registered as sys.modules
["device_sync"], which is what the bridge's lazy import picks
up; the bridge's DEVICE_DATA_DIR global is pointed at the
scenario dir, mirroring production's shared volume.

Phases:
1. window / ordering / material lines / anchor registry, and
   the C gates end-to-end (anchor gate, G1 detail gate,
   anchor-level dedup, ref shape).
2. permission revoked -> stop supply: zero rows served, the
   copy stays on disk, material shows the C section empty and
   the round record carries the reason; granted again ->
   supply recovers.
3. copy never synced (store file absent, then store present
   but empty) -> explicit note, assembly unaffected.
4. line cap (10); stale copy serves NOTHING (B3, 2026-11-24:
   the whole C section stops, the material prints 无可用日程
   instead of the frozen copy's leftover rows).
5. one full generation round lands a C-anchored card; after
   revocation the same citation no longer resolves and the
   round records the stop-supply note (audit I-A1 / I-A2
   mechanics at bridge level).
"""
import importlib.util
import json
import os
import sqlite3
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.abspath(__file__))


def _sibling(name):
    """Module copies sit next to the tests in the staging dir;
    in the repo tree they live in ../modules."""
    p = os.path.join(HERE, name)
    if os.path.exists(p):
        return p
    return os.path.join(HERE, "..", "modules", name)


BRIDGE = _sibling("oneday_bridge.py")
# the bridge imports sibling modules (ledger, device_sync);
# in the staging dir they are already on the path.
sys.path.insert(0, os.path.dirname(os.path.abspath(BRIDGE)))
TZ = ZoneInfo("Asia/Shanghai")
FIXED_NOW = datetime(2026, 11, 12, 7, 30, tzinfo=TZ).timestamp()

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


def local_ts(day_offset, hh, mm=0):
    d = datetime.fromtimestamp(FIXED_NOW, TZ).date() \
        + timedelta(days=day_offset)
    return datetime(d.year, d.month, d.day, hh, mm,
                    tzinfo=TZ).timestamp()


def ev(oid, title, start_ts, end_ts, all_day=False, cal="个人",
       loc=""):
    return {"occurrenceId": oid, "eventId": "e-" + oid,
            "title": title, "start": iso_utc(start_ts),
            "end": iso_utc(end_ts), "allDay": all_day,
            "calendarName": cal, "location": loc}


def load_dsync(name):
    spec = importlib.util.spec_from_file_location(
        name, _sibling("device_sync.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def seed_calendar(dsync, ddir, records, completed_at=FIXED_NOW):
    dsync.init(Path(ddir))
    dsync.stage_batch("calendar", "p7-batch", records, mode="full")
    dsync.complete("calendar", "p7-batch", len(records),
                   device_completed_at=iso_utc(completed_at),
                   permission_state="granted")


def scenario_events():
    return [
        ev("occ_dent", "牙科复诊", local_ts(1, 14), local_ts(1, 15),
           loc="城南诊所"),
        ev("occ_hol", "Thanksgiving", local_ts(3, 0),
           local_ts(3, 23, 59), all_day=True, cal="US Holidays"),
        ev("occ_fam", "家庭聚餐", local_ts(5, 0), local_ts(5, 23, 59),
           all_day=True, cal="家庭"),
        ev("occ_past", "老同学聚会", local_ts(-1, 19),
           local_ts(-1, 21)),
        ev("occ_far", "远期产品评审", local_ts(20, 10),
           local_ts(20, 11)),
        ev("occ_old", "上月例会", local_ts(-10, 10),
           local_ts(-10, 11)),
    ]


def main():
    tmp = tempfile.mkdtemp(prefix="p7-")
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump({"goals": [], "ideas": [], "monitors": [],
                   "changes": [], "goalEntries": [], "briefings": [],
                   "feedPosts": [], "goalTaskLinks": [], "meta": {}},
                  f, ensure_ascii=False)
    os.environ["ONEDAY_BRIDGE_KEY"] = "p7-selftest-key"
    os.environ["DATA_PATH"] = data_path
    os.environ["HERMES_API_KEY"] = "fake-key"
    spec = importlib.util.spec_from_file_location("ob_p7", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    mod._now = lambda: FIXED_NOW
    mod._fetch_session_digests = lambda: ([], None)
    mod._fetch_kanban_details = lambda: ([], None)
    mod._fetch_memory_excerpts = lambda keywords: ([], None)

    # ---------- phase 1: window / order / lines / gates ----------
    ddir = os.path.join(tmp, "device-data")
    os.makedirs(ddir)
    dsync = load_dsync("ds_p7_main")
    seed_calendar(dsync, ddir, scenario_events())
    sys.modules["device_sync"] = dsync
    mod.DEVICE_DATA_DIR = Path(ddir)

    events, note = mod._fetch_calendar_events()
    check("1 fetcher returns the 4 in-window events, ordered "
          "upcoming-nearest then just-ended",
          [e["occurrenceId"] for e in events] ==
          ["occ_dent", "occ_hol", "occ_fam", "occ_past"],
          f"{[e['occurrenceId'] for e in events]}")
    check("1 fetcher note is None on a healthy copy", note is None,
          f"{note}")
    check("1 fetcher keeps summary fields only",
          events[0]["calendarName"] == "个人"
          and events[0]["location"] == "城南诊所"
          and events[0]["allDay"] is False
          and events[1]["allDay"] is True, f"{events[0]}")

    prompt, notes, goal_ids, anchors, lines = mod._assemble_material()
    check("1 material has the C section",
          "## 近期日程（编号 C" in prompt)
    check("1 material excludes out-of-window events",
          "远期产品评审" not in prompt and "上月例会" not in prompt)
    dent_ref = next(r for r, a in anchors.items()
                    if a["objectId"] == "occ_dent")
    hol_ref = next(r for r, a in anchors.items()
                   if a["objectId"] == "occ_hol")
    past_ref = next(r for r, a in anchors.items()
                    if a["objectId"] == "occ_past")
    check("1 anchors registered with kind C",
          anchors[dent_ref]["kind"] == "C"
          and anchors[dent_ref]["title"] == "牙科复诊",
          f"{anchors.get(dent_ref)}")
    dent_line = lines[dent_ref]
    check("1 timed line: full date, time, place, proximity",
          "11月13日 14:00" in dent_line
          and "《牙科复诊》" in dent_line
          and "地点：城南诊所" in dent_line
          and "（明天）" in dent_line, dent_line)
    check("1 all-day holiday line names its calendar",
          "全天" in lines[hol_ref]
          and "（日历：US Holidays）" in lines[hol_ref],
          lines[hol_ref])
    check("1 past line is labelled 昨天",
          "（昨天）" in lines[past_ref], lines[past_ref])
    check("1 no calendar note on a healthy round",
          notes.get("calendar") is None, f"{notes}")

    check("1 ref shape accepts C, rejects strangers",
          bool(mod.ANCHOR_REF_RE.match("C1"))
          and bool(mod.ANCHOR_REF_RE.match("C12"))
          and not mod.ANCHOR_REF_RE.match("C")
          and not mod.ANCHOR_REF_RE.match("X1")
          and not mod.ANCHOR_REF_RE.match("c1"))

    good = {"title": "我可以帮你整理牙科复诊要带的东西",
            "detail": "11月13日 14:00 的牙科复诊在城南诊所：我先"
                      "把要带的东西列成清单发你确认，你点头后我再"
                      "准备，确认前不做别的。",
            "evidence": "日历上 11月13日 14:00 有牙科复诊",
            "evidenceRef": dent_ref, "goalId": None}
    fact_free = {"title": "我可以帮你安排一下日程",
                 "detail": "11月13日 14:00 牙科复诊快到了，我先"
                           "帮你把时间留出来。",
                 "evidence": "你最近日程挺满的",
                 "evidenceRef": dent_ref, "goalId": None}
    generic = {"title": "我可以帮你把复诊的事办了",
               "detail": "我先帮你把相关的东西都准备好，到时候"
                         "提醒你一声，不用你操心这些小事。",
               "evidence": "日历上 11月13日 14:00 有牙科复诊",
               "evidenceRef": dent_ref, "goalId": None}
    unknown = {"title": "我可以帮你处理第九条日程",
               "detail": "11月13日 14:00 牙科复诊，我来准备。",
               "evidence": "日历上 11月13日 有安排",
               "evidenceRef": "C9", "goalId": None}
    dup = {"title": "我可以帮你查感恩节的来历",
           "detail": "11月15日 全天是 Thanksgiving，我把它的"
                     "来历整理成一页发你。",
           "evidence": "日历上 11月15日 全天 Thanksgiving",
           "evidenceRef": hol_ref, "goalId": None}
    ideas_seed = [{"id": "i_hol", "title": "已有节假日卡",
                   "anchorId": "C:occ_hol", "status": "pending",
                   "createdAt": FIXED_NOW - 100}]
    cards, dropped, reasons, perr = mod._parse_generated_cards(
        json.dumps([good, fact_free, generic, unknown, dup],
                   ensure_ascii=False),
        set(), anchors, ideas_seed, lines)
    check("1 gates: the one good C card lands with its anchorId",
          perr is None and len(cards) == 1
          and cards[0]["anchorId"] == "C:occ_dent",
          f"{cards} {perr}")
    check("1 gates: drops accounted (2 noAnchor, 1 G1, 1 dup)",
          dropped == 4 and reasons["noAnchor"] == 2
          and reasons["noDetailAnchor"] == 1
          and reasons["dupAnchor"] == 1, f"{reasons}")

    # ---------- phase 2: revoked -> stop supply ----------------
    dsync.report_state("calendar", permission_state="revoked")
    events2, note2 = mod._fetch_calendar_events()
    check("2 revoked: zero events, stop-supply note",
          events2 == [] and note2 is not None and "停供" in note2,
          f"{events2} {note2}")
    prompt2, notes2, _, anchors2, _ = mod._assemble_material()
    check("2 revoked: material carries no calendar content",
          "《牙科复诊》" not in prompt2 and not anchors2
          and "（无）" in prompt2, "")
    check("2 revoked: round record carries the reason (I-A1)",
          notes2.get("calendar") is not None
          and "停供" in notes2["calendar"], f"{notes2}")
    con = sqlite3.connect(
        f"file:{os.path.join(ddir, 'sync.db')}?mode=ro", uri=True)
    kept = con.execute(
        "SELECT COUNT(*) FROM calendar_events").fetchone()[0]
    con.close()
    check("2 revoked: the copy itself is kept on disk", kept == 6,
          f"{kept}")
    dsync.report_state("calendar", permission_state="granted")
    events3, _ = mod._fetch_calendar_events()
    check("2 granted again: supply recovers",
          len(events3) == 4, f"{len(events3)}")

    # ---------- phase 3: never synced --------------------------
    ddir3 = os.path.join(tmp, "device-empty")
    os.makedirs(ddir3)
    dsync3 = load_dsync("ds_p7_empty")
    sys.modules["device_sync"] = dsync3
    mod.DEVICE_DATA_DIR = Path(ddir3)
    ev_a, note_a = mod._fetch_calendar_events()
    check("3 store file absent: explicit not-synced note",
          ev_a == [] and note_a == "日历副本尚未同步",
          f"{ev_a} {note_a}")
    dsync3.init(Path(ddir3))
    ev_b, note_b = mod._fetch_calendar_events()
    check("3 store present but never synced: CopyEmpty note",
          ev_b == [] and note_b == "日历副本尚未同步",
          f"{ev_b} {note_b}")
    prompt3, notes3, _, _, _ = mod._assemble_material()
    check("3 assembly unaffected, C section marked empty",
          "## 近期日程（编号 C" in prompt3
          and notes3.get("calendar") == "日历副本尚未同步",
          f"{notes3}")

    # ---------- phase 4: cap + stale ---------------------------
    ddir4 = os.path.join(tmp, "device-many")
    os.makedirs(ddir4)
    dsync4 = load_dsync("ds_p7_many")
    many = [ev(f"occ_m{n}", f"跟进会第{n}场", local_ts(n, 10),
               local_ts(n, 11)) for n in range(1, 13)]
    seed_calendar(dsync4, ddir4, many)
    sys.modules["device_sync"] = dsync4
    mod.DEVICE_DATA_DIR = Path(ddir4)
    ev_m, note_m = mod._fetch_calendar_events()
    check("4 cap: 12 in-window events trimmed to 10, nearest "
          "first", len(ev_m) == 10
          and ev_m[0]["occurrenceId"] == "occ_m1"
          and note_m is None, f"{len(ev_m)} {note_m}")

    ddir5 = os.path.join(tmp, "device-stale")
    os.makedirs(ddir5)
    dsync5 = load_dsync("ds_p7_stale")
    seed_calendar(dsync5, ddir5,
                  [ev("occ_stale", "明日例会", local_ts(1, 10),
                      local_ts(1, 11))],
                  completed_at=FIXED_NOW - 25 * 3600)
    sys.modules["device_sync"] = dsync5
    mod.DEVICE_DATA_DIR = Path(ddir5)
    ev_s, note_s = mod._fetch_calendar_events()
    check("4 stale copy: NO events served, staleness noted (B3)",
          len(ev_s) == 0 and note_s is not None
          and "已过期" in note_s, f"{len(ev_s)} {note_s}")
    prompt4, notes4, _, anchors4, _ = mod._assemble_material()
    check("4 stale copy: material C section says 无可用日程 and "
          "carries no stale rows",
          "（无可用日程：日历副本已过期）" in prompt4
          and "《明日例会》" not in prompt4
          and not any(a["kind"] == "C"
                      for a in anchors4.values())
          and notes4.get("calendar") is not None
          and "已过期" in notes4["calendar"],
          f"{notes4}")

    # ---------- phase 5: full round ----------------------------
    sys.modules["device_sync"] = dsync
    mod.DEVICE_DATA_DIR = Path(ddir)
    gen_card = {"title": "我可以帮你整理牙科复诊要带的东西",
                "detail": "11月13日 14:00 的牙科复诊在城南诊所："
                          "我先把要带的东西列成清单发你确认，你"
                          "点头后我再准备，确认前不做别的。",
                "evidence": "日历上 11月13日 14:00 有牙科复诊",
                "evidenceRef": "C1", "goalId": None}

    gen_card2 = dict(gen_card)
    gen_card2["title"] = "我可以帮你列一份复诊前确认清单"
    gen_outputs = [gen_card, gen_card2]

    def fake_submit(prompt, idem):
        return idem, None

    def fake_poll(run_id):
        if run_id.startswith("ideas-check-"):
            return json.dumps(
                [{"title": gen_card["title"], "ok": True,
                  "issues": ""}], ensure_ascii=False), None
        return json.dumps([gen_outputs.pop(0)],
                          ensure_ascii=False), None

    mod._hermes_submit_run = fake_submit
    mod._hermes_poll_run = fake_poll
    mod._run_generation_round("manual")
    with mod._lock:
        ideas = list(mod._db["ideas"])
        hist = list(mod._db["meta"]["ideasGen"]["history"])
    rec = hist[-1]
    landed = [i for i in ideas
              if i.get("anchorId") == "C:occ_dent"]
    check("5 round lands the C-anchored card",
          rec["produced"] == 1 and len(landed) == 1
          and landed[0]["evidenceRef"] == "C1", f"{rec} {landed}")
    check("5 healthy round records no calendar note",
          "calendar" not in (rec.get("materialNotes") or {}),
          f"{rec.get('materialNotes')}")

    dsync.report_state("calendar", permission_state="revoked")
    mod._run_generation_round("manual")
    with mod._lock:
        hist = list(mod._db["meta"]["ideasGen"]["history"])
    rec2 = hist[-1]
    check("5 revoked round: C citation unresolvable, dropped, "
          "stop-supply in the record",
          rec2["produced"] == 0
          and rec2["droppedReasons"].get("noAnchor", 0) >= 1
          and "停供" in (rec2.get("materialNotes") or {}).get(
              "calendar", ""), f"{rec2}")
    dsync.report_state("calendar", permission_state="granted")

    print(f"\nP7 RESULT: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
