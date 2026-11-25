#!/usr/bin/env python3
"""device-sync: synced minimal copies of the phone's record-type data
(design: oneday-design-review/device-sync-design-20261110.md, user
decisions 2026-11-10 21:52 + 21:58).

Model: the app, under the user's own system permissions, syncs a
field-minimised copy of record-type datasets (contacts, calendar,
reminders, photo index, per-day step aggregates) to this companion
service over the existing single-key channel. The agent then answers
whole-book questions (count / distribution / dedupe / paging) from
this local SQLite store instead of waking the phone for every read.
Realtime and action tools still go live through device_bridge.

User rulings baked in:
- 2026-11-10 21:58, permission revoked => STOP SUPPLY: query tools
  for that dataset return a status error and no record data at all.
  The copy itself is kept; re-granting the permission resumes supply.
  (REVOKED_SERVES_COPY below is the flippable switch, fixed to the
  stop-supply position by that ruling.)
- 2026-11-10 21:58, photos are a FULL asset index (one metadata row
  per asset), aggregates computed over the index. Still: no image
  data, no coordinates, ever.

Store discipline: one SQLite file (sync.db, mode 0600) inside the
device module's data dir; the only readers are the device MCP query
tools, the sync write path (write-only for content; receipts carry
counts and times only), and the panel status view (state only, never
record content). Plain SQLite, not SQLCipher: the decryption key
would live on the same host as the data, so its marginal benefit
does not justify the dependency (spec section 2.3 allows either).

Freshness honesty: every query result carries the copy's sync time
plus a ready-made plain-language freshness sentence generated here;
an expired copy (>24h) says so in words; a copy whose permission was
revoked serves nothing (see above).
"""

from __future__ import annotations

import json
import os
import sqlite3
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

# 2026-11-10 21:58 ruling: revoked permission => stop supply entirely.
REVOKED_SERVES_COPY = False

EXPIRED_AFTER_SEC = 24 * 3600
DATASETS = ("contacts", "calendar", "reminders", "photos", "motion")
DATASET_LABEL = {
    "contacts": "通讯录",
    "calendar": "日历",
    "reminders": "提醒事项",
    "photos": "照片",
    "motion": "步数",
}
# which live tool a dataset's writes go through (pending-write marks)
WRITE_DATASET = {"calendar_create_event": "calendar",
                 "calendar_update_event": "calendar",
                 "reminders_create": "reminders",
                 "reminders_complete": "reminders"}

_lock = threading.RLock()
_db_path: Path | None = None

try:
    from zoneinfo import ZoneInfo
    _LOCAL_TZ = ZoneInfo(os.environ.get("TZ", "Asia/Shanghai"))
except Exception:  # pragma: no cover - zoneinfo missing
    _LOCAL_TZ = timezone(timedelta(hours=8))


class SyncError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


class CopyEmpty(Exception):
    """Dataset has never been synced (or its copy was deleted)."""


# ------------------------------------------------------------ schema
_SCHEMA = """
CREATE TABLE IF NOT EXISTS sync_state(
  dataset TEXT PRIMARY KEY,
  synced_at REAL, received_at REAL,
  item_count INTEGER NOT NULL DEFAULT 0,
  auth_range TEXT, range_note TEXT,
  coverage_start TEXT, coverage_end TEXT,
  permission_state TEXT,
  pending_write INTEGER NOT NULL DEFAULT 0,
  syncing INTEGER NOT NULL DEFAULT 0,
  last_error TEXT, extra TEXT);
CREATE TABLE IF NOT EXISTS contacts(
  id TEXT PRIMARY KEY, display_name TEXT, family_name TEXT,
  given_name TEXT, phones TEXT, emails TEXT, organization TEXT,
  groups_json TEXT, fingerprint TEXT);
CREATE INDEX IF NOT EXISTS idx_contacts_name ON contacts(display_name);
CREATE TABLE IF NOT EXISTS calendar_events(
  occurrence_id TEXT PRIMARY KEY, event_id TEXT, title TEXT,
  start_ts REAL, start_iso TEXT, end_ts REAL, end_iso TEXT,
  all_day INTEGER, calendar_name TEXT, location TEXT);
CREATE INDEX IF NOT EXISTS idx_cal_start ON calendar_events(start_ts);
CREATE TABLE IF NOT EXISTS reminders(
  id TEXT PRIMARY KEY, title TEXT, due_ts REAL, due_iso TEXT,
  priority INTEGER, list_name TEXT);
CREATE TABLE IF NOT EXISTS photos_assets(
  asset_id TEXT PRIMARY KEY, created_ts REAL, created_iso TEXT,
  created_month TEXT, media_type TEXT, subtype TEXT,
  width INTEGER, height INTEGER, duration_sec REAL,
  is_favorite INTEGER, album_name TEXT, has_location INTEGER);
CREATE INDEX IF NOT EXISTS idx_photos_month ON photos_assets(created_month);
CREATE TABLE IF NOT EXISTS motion_days(
  date TEXT PRIMARY KEY, steps INTEGER, distance_m REAL,
  flights INTEGER, source TEXT);
CREATE TABLE IF NOT EXISTS sync_batches(
  batch_key TEXT PRIMARY KEY, dataset TEXT, batch_id TEXT, mode TEXT,
  received INTEGER NOT NULL DEFAULT 0, created_at REAL, meta TEXT);
CREATE TABLE IF NOT EXISTS stage_records(
  batch_key TEXT, record_id TEXT, payload TEXT,
  PRIMARY KEY(batch_key, record_id));
"""

_TABLE_OF = {"contacts": "contacts", "calendar": "calendar_events",
             "reminders": "reminders", "photos": "photos_assets",
             "motion": "motion_days"}
_ID_OF = {"contacts": "id", "calendar": "occurrence_id",
          "reminders": "id", "photos": "asset_id", "motion": "date"}


def init(data_dir: Path) -> None:
    global _db_path
    with _lock:
        if _db_path is not None:
            return
        data_dir.mkdir(parents=True, exist_ok=True)
        _db_path = Path(data_dir) / "sync.db"
        if not _db_path.exists():
            _db_path.touch()
        try:
            os.chmod(_db_path, 0o600)
        except OSError:
            pass
        con = _connect()
        try:
            con.executescript(_SCHEMA)
            con.commit()
        finally:
            con.close()
        try:
            os.chmod(_db_path, 0o600)
        except OSError:
            pass


def _connect() -> sqlite3.Connection:
    if _db_path is None:
        raise SyncError("sync_not_ready", "sync store not initialised")
    con = sqlite3.connect(str(_db_path), timeout=30)
    con.row_factory = sqlite3.Row
    return con


def db_file_size() -> int:
    try:
        return _db_path.stat().st_size if _db_path else 0
    except OSError:
        return 0


# ------------------------------------------------------------ helpers
def _iso(epoch: float | None) -> str | None:
    if epoch is None:
        return None
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat()


def _parse_ts(value) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value).strip()
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        pass
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_LOCAL_TZ)
    return dt.timestamp()


def _day_label(dt: datetime, now: datetime) -> str:
    hm = dt.strftime("%H:%M")
    if dt.date() == now.date():
        return f"今天 {hm}"
    if dt.date() == (now - timedelta(days=1)).date():
        return ("昨晚 " if dt.hour >= 18 else "昨天 ") + hm
    return f"{dt.month}月{dt.day}日 {hm}"


def freshness_text(synced_at: float | None,
                   pending_write: bool = False) -> str:
    if synced_at is None:
        return "还没有同步过"
    now = datetime.now(_LOCAL_TZ)
    dt = datetime.fromtimestamp(synced_at, _LOCAL_TZ)
    label = _day_label(dt, now)
    age = time.time() - synced_at
    if age > EXPIRED_AFTER_SEC:
        text = f"数据截至{label}，已过期"
    elif age < 90:
        text = f"数据截至{label}，刚刚同步"
    elif age < 3600:
        text = f"数据截至{label}，约 {max(1, int(age // 60))} 分钟前同步"
    elif dt.date() == now.date():
        text = f"数据截至{label}，约 {int(age // 3600)} 小时前同步"
    else:
        text = f"数据截至{label}"
    if pending_write:
        text += "；刚写入的一条可能还没反映在副本里"
    return text


def _get_state(con, dataset: str) -> dict | None:
    row = con.execute("SELECT * FROM sync_state WHERE dataset=?",
                      (dataset,)).fetchone()
    if row is None:
        return None
    st = dict(row)
    try:
        st["extra"] = json.loads(st.get("extra") or "{}")
    except ValueError:
        st["extra"] = {}
    return st


def _put_state(con, dataset: str, **fields) -> None:
    cur = _get_state(con, dataset)
    base = cur or {"dataset": dataset, "synced_at": None,
                   "received_at": None, "item_count": 0,
                   "auth_range": None, "range_note": None,
                   "coverage_start": None, "coverage_end": None,
                   "permission_state": None, "pending_write": 0,
                   "syncing": 0, "last_error": None, "extra": {}}
    base.update(fields)
    extra = base.get("extra") or {}
    con.execute(
        "INSERT INTO sync_state(dataset, synced_at, received_at,"
        " item_count, auth_range, range_note, coverage_start,"
        " coverage_end, permission_state, pending_write, syncing,"
        " last_error, extra) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"
        " ON CONFLICT(dataset) DO UPDATE SET"
        " synced_at=excluded.synced_at, received_at=excluded.received_at,"
        " item_count=excluded.item_count, auth_range=excluded.auth_range,"
        " range_note=excluded.range_note,"
        " coverage_start=excluded.coverage_start,"
        " coverage_end=excluded.coverage_end,"
        " permission_state=excluded.permission_state,"
        " pending_write=excluded.pending_write,"
        " syncing=excluded.syncing, last_error=excluded.last_error,"
        " extra=excluded.extra",
        (dataset, base["synced_at"], base["received_at"],
         base["item_count"], base["auth_range"], base["range_note"],
         base["coverage_start"], base["coverage_end"],
         base["permission_state"], base["pending_write"],
         base["syncing"], base["last_error"],
         json.dumps(extra, ensure_ascii=False)))


def dataset_state(dataset: str) -> dict | None:
    with _lock:
        con = _connect()
        try:
            return _get_state(con, dataset)
        finally:
            con.close()


def _gate(con, dataset: str) -> dict:
    """Return the state for a queryable copy. Raises CopyEmpty when
    there is nothing to serve, SyncError(permission_revoked) when the
    permission is off (stop-supply ruling, 2026-11-10 21:58)."""
    st = _get_state(con, dataset)
    if st is None or st["synced_at"] is None:
        raise CopyEmpty(dataset)
    if st["permission_state"] == "revoked" and not REVOKED_SERVES_COPY:
        raise SyncError(
            "permission_revoked",
            f"手机上的{DATASET_LABEL[dataset]}权限已经关了，"
            "这份副本暂停提供，里面的数据一条都不会给出；"
            "重新在系统里打开这个权限后即可恢复。")
    return st


def envelope(dataset: str, st: dict) -> dict:
    env = {"source": "sync_copy",
           "synced_at": _iso(st["synced_at"]),
           "freshness": freshness_text(st["synced_at"],
                                       bool(st["pending_write"])),
           "auth_range": st["auth_range"] or "full"}
    if env["auth_range"] == "limited":
        env["range_note"] = st["range_note"] or {
            "contacts": "这是用户勾选的部分联系人，不是全部",
            "calendar": "这是用户勾选的部分日历，不是全部",
            "reminders": "这是用户勾选的部分清单，不是全部",
            "photos": "这是用户勾选的部分照片，不是全部",
            "motion": "这是部分数据"}.get(dataset, "这是部分数据，不是全部")
    if dataset == "calendar" and st["coverage_start"]:
        env["coverage"] = {"start": st["coverage_start"],
                           "end": st["coverage_end"]}
    return env


# ------------------------------------------------------------ sync write path
def _record_id(dataset: str, rec: dict) -> str | None:
    key = {"contacts": "id", "calendar": "occurrenceId",
           "reminders": "id", "photos": "assetId",
           "motion": "date"}[dataset]
    v = rec.get(key)
    return str(v) if v not in (None, "") else None


def stage_batch(dataset: str, batch_id: str, records: list,
                mode: str = "full", meta: dict | None = None) -> dict:
    """Stage one batch (<=500 records). Staged data never touches the
    live tables; a new batch for the same dataset supersedes any
    unfinished one, whose staged rows are dropped."""
    if dataset not in DATASETS:
        raise SyncError("unknown_dataset", f"no such dataset: {dataset}")
    batch_key = f"{dataset}:{batch_id}"
    with _lock:
        con = _connect()
        try:
            old = con.execute(
                "SELECT batch_key FROM sync_batches WHERE dataset=?",
                (dataset,)).fetchall()
            for row in old:
                if row["batch_key"] != batch_key:
                    con.execute("DELETE FROM stage_records"
                                " WHERE batch_key=?", (row["batch_key"],))
                    con.execute("DELETE FROM sync_batches"
                                " WHERE batch_key=?", (row["batch_key"],))
            con.execute(
                "INSERT INTO sync_batches(batch_key, dataset, batch_id,"
                " mode, received, created_at, meta) VALUES(?,?,?,?,0,?,?)"
                " ON CONFLICT(batch_key) DO UPDATE SET"
                " mode=excluded.mode, meta=excluded.meta",
                (batch_key, dataset, batch_id, mode, time.time(),
                 json.dumps(meta or {}, ensure_ascii=False)))
            for rec in records:
                rid = _record_id(dataset, rec)
                if rid is None:
                    continue
                con.execute(
                    "INSERT OR REPLACE INTO stage_records(batch_key,"
                    " record_id, payload) VALUES(?,?,?)",
                    (batch_key, rid,
                     json.dumps(rec, ensure_ascii=False)))
            n = con.execute(
                "SELECT COUNT(*) c FROM stage_records WHERE batch_key=?",
                (batch_key,)).fetchone()["c"]
            con.execute("UPDATE sync_batches SET received=?"
                        " WHERE batch_key=?", (n, batch_key))
            _put_state(con, dataset, syncing=1)
            con.commit()
            return {"dataset": dataset, "batchId": batch_id,
                    "received": n}
        finally:
            con.close()


def _materialize(con, dataset: str, rows: list[dict]) -> None:
    if dataset == "contacts":
        for r in rows:
            con.execute(
                "INSERT OR REPLACE INTO contacts(id, display_name,"
                " family_name, given_name, phones, emails, organization,"
                " groups_json, fingerprint) VALUES(?,?,?,?,?,?,?,?,?)",
                (str(r.get("id")), r.get("displayName") or "",
                 r.get("familyName"), r.get("givenName"),
                 json.dumps(r.get("phones") or [], ensure_ascii=False),
                 json.dumps(r.get("emails") or [], ensure_ascii=False),
                 r.get("organization"),
                 json.dumps(r.get("groups") or [], ensure_ascii=False),
                 r.get("fingerprint")))
    elif dataset == "calendar":
        for r in rows:
            con.execute(
                "INSERT OR REPLACE INTO calendar_events(occurrence_id,"
                " event_id, title, start_ts, start_iso, end_ts, end_iso,"
                " all_day, calendar_name, location)"
                " VALUES(?,?,?,?,?,?,?,?,?,?)",
                (str(r.get("occurrenceId")), r.get("eventId"),
                 r.get("title") or "", _parse_ts(r.get("start")),
                 str(r.get("start") or ""), _parse_ts(r.get("end")),
                 str(r.get("end") or ""), 1 if r.get("allDay") else 0,
                 r.get("calendarName"), r.get("location")))
    elif dataset == "reminders":
        for r in rows:
            con.execute(
                "INSERT OR REPLACE INTO reminders(id, title, due_ts,"
                " due_iso, priority, list_name) VALUES(?,?,?,?,?,?)",
                (str(r.get("id")), r.get("title") or "",
                 _parse_ts(r.get("due")),
                 str(r.get("due") or "") or None,
                 r.get("priority"), r.get("listName")))
    elif dataset == "photos":
        for r in rows:
            ts = _parse_ts(r.get("createdAt"))
            month = None
            if ts is not None:
                month = datetime.fromtimestamp(
                    ts, _LOCAL_TZ).strftime("%Y-%m")
            con.execute(
                "INSERT OR REPLACE INTO photos_assets(asset_id,"
                " created_ts, created_iso, created_month, media_type,"
                " subtype, width, height, duration_sec, is_favorite,"
                " album_name, has_location) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                (str(r.get("assetId")), ts, str(r.get("createdAt") or ""),
                 month, r.get("mediaType") or "photo", r.get("subtype"),
                 r.get("width"), r.get("height"), r.get("durationSec"),
                 1 if r.get("isFavorite") else 0, r.get("albumName"),
                 1 if r.get("hasLocation") else 0))
    elif dataset == "motion":
        for r in rows:
            con.execute(
                "INSERT OR REPLACE INTO motion_days(date, steps,"
                " distance_m, flights, source) VALUES(?,?,?,?,?)",
                (str(r.get("date")), r.get("steps"), r.get("distanceM"),
                 r.get("flights"), r.get("source") or "手机计步"))


def complete(dataset: str, batch_id: str, expected_total: int,
             device_completed_at=None, mode: str | None = None,
             coverage: dict | None = None, aggregates: dict | None = None,
             removed_ids: list | None = None, auth_range: str | None = None,
             range_note: str | None = None,
             permission_state: str | None = None) -> dict:
    """Confirm a staged batch and swap it in atomically. If the staged
    count does not match the declared total, the batch is discarded
    and the previous copy stays exactly as it was."""
    if dataset not in DATASETS:
        raise SyncError("unknown_dataset", f"no such dataset: {dataset}")
    batch_key = f"{dataset}:{batch_id}"
    with _lock:
        con = _connect()
        try:
            brow = con.execute(
                "SELECT * FROM sync_batches WHERE batch_key=?",
                (batch_key,)).fetchone()
            if brow is None:
                raise SyncError("unknown_batch",
                                "no staged batch under this id")
            mode = mode or brow["mode"] or "full"
            staged = con.execute(
                "SELECT payload FROM stage_records WHERE batch_key=?",
                (batch_key,)).fetchall()
            if len(staged) != int(expected_total):
                con.execute("DELETE FROM stage_records WHERE batch_key=?",
                            (batch_key,))
                con.execute("DELETE FROM sync_batches WHERE batch_key=?",
                            (batch_key,))
                _put_state(con, dataset, syncing=0,
                           last_error="同步条数对不上，这一批已丢弃，"
                                      "副本仍是上一份")
                con.commit()
                raise SyncError(
                    "sync_count_mismatch",
                    f"staged {len(staged)} records but the app declared "
                    f"{expected_total}; batch discarded, previous copy "
                    "untouched")
            rows = [json.loads(r["payload"]) for r in staged]
            table = _TABLE_OF[dataset]
            if mode == "full":
                con.execute(f"DELETE FROM {table}")
                _materialize(con, dataset, rows)
            elif mode == "incremental":
                _materialize(con, dataset, rows)
                idcol = _ID_OF[dataset]
                for rid in removed_ids or []:
                    con.execute(f"DELETE FROM {table} WHERE {idcol}=?",
                                (str(rid),))
            elif mode == "merge":  # motion days: newer day wins
                _materialize(con, dataset, rows)
            else:
                raise SyncError("unknown_mode", f"no such mode: {mode}")
            total = con.execute(
                f"SELECT COUNT(*) c FROM {table}").fetchone()["c"]
            con.execute("DELETE FROM stage_records WHERE batch_key=?",
                        (batch_key,))
            con.execute("DELETE FROM sync_batches WHERE batch_key=?",
                        (batch_key,))
            extra = {}
            if dataset == "reminders" and aggregates:
                extra = {"today_completed": aggregates.get("todayCompleted"),
                         "overdue_at_sync": aggregates.get("overdueCount")}
            st = _get_state(con, dataset) or {}
            _put_state(
                con, dataset,
                synced_at=_parse_ts(device_completed_at) or time.time(),
                received_at=time.time(), item_count=total,
                auth_range=auth_range or st.get("auth_range") or "full",
                range_note=range_note if range_note is not None
                else st.get("range_note"),
                coverage_start=(coverage or {}).get("start")
                if coverage else st.get("coverage_start"),
                coverage_end=(coverage or {}).get("end")
                if coverage else st.get("coverage_end"),
                permission_state=permission_state
                or ("granted" if st.get("permission_state") != "revoked"
                    else "revoked"),
                pending_write=0, syncing=0, last_error=None, extra=extra)
            con.commit()
            st = _get_state(con, dataset)
            return {"dataset": dataset, "received": len(rows),
                    "total_in_store": total,
                    "synced_at": _iso(st["synced_at"]),
                    "auth_range": st["auth_range"]}
        finally:
            con.close()


def abort_batch(dataset: str, batch_id: str) -> None:
    batch_key = f"{dataset}:{batch_id}"
    with _lock:
        con = _connect()
        try:
            con.execute("DELETE FROM stage_records WHERE batch_key=?",
                        (batch_key,))
            con.execute("DELETE FROM sync_batches WHERE batch_key=?",
                        (batch_key,))
            _put_state(con, dataset, syncing=0)
            con.commit()
        finally:
            con.close()


def manifest_compare(dataset: str, entries: list[dict]) -> dict:
    """Contacts manifest diff (spec 3.3): the app sends id+fingerprint
    for the whole book; we answer which ids are new/changed and which
    stored ids have disappeared. Only contacts carries fingerprints."""
    if dataset != "contacts":
        raise SyncError("manifest_unsupported",
                        "manifest compare is defined for contacts only")
    with _lock:
        con = _connect()
        try:
            stored = {r["id"]: r["fingerprint"] for r in con.execute(
                "SELECT id, fingerprint FROM contacts")}
        finally:
            con.close()
    seen, changed = set(), []
    for e in entries:
        rid = str(e.get("id"))
        seen.add(rid)
        if stored.get(rid) != e.get("fingerprint"):
            changed.append(rid)
    removed = [rid for rid in stored if rid not in seen]
    return {"changed_ids": changed, "removed_ids": removed,
            "unchanged_count": len(seen) - len(changed),
            "current_total": len(stored)}


def report_state(dataset: str, permission_state: str | None = None,
                 auth_range: str | None = None,
                 range_note: str | None = None) -> dict:
    """The app reports permission/range changes here between syncs.
    A change of auth range means the fingerprint basis changed, so the
    answer flags that the next sync must be a full re-import."""
    if dataset not in DATASETS:
        raise SyncError("unknown_dataset", f"no such dataset: {dataset}")
    with _lock:
        con = _connect()
        try:
            st = _get_state(con, dataset)
            old_range = st["auth_range"] if st else None
            fields = {}
            if permission_state is not None:
                fields["permission_state"] = permission_state
            if auth_range is not None:
                fields["auth_range"] = auth_range
            if range_note is not None:
                fields["range_note"] = range_note
            if fields:
                _put_state(con, dataset, **fields)
                con.commit()
            reimport = bool(auth_range and old_range
                            and auth_range != old_range)
            return {"dataset": dataset,
                    "reimport_required": reimport,
                    "permission_state": permission_state
                    or (st or {}).get("permission_state"),
                    "auth_range": auth_range or old_range}
        finally:
            con.close()


def mark_pending_write(dataset: str) -> None:
    with _lock:
        con = _connect()
        try:
            _put_state(con, dataset, pending_write=1)
            con.commit()
        finally:
            con.close()


def delete_copies(datasets: list[str] | None = None) -> dict:
    """Delete synced copies (Muse semantics: pairing, phone data and
    permissions are untouched; only this store is emptied). Physical
    delete plus VACUUM so the space is actually reclaimed."""
    targets = datasets or list(DATASETS)
    with _lock:
        con = _connect()
        try:
            for ds in targets:
                con.execute(f"DELETE FROM {_TABLE_OF[ds]}")
                con.execute("DELETE FROM sync_state WHERE dataset=?",
                            (ds,))
                con.execute(
                    "DELETE FROM stage_records WHERE batch_key IN"
                    " (SELECT batch_key FROM sync_batches"
                    "  WHERE dataset=?)", (ds,))
                con.execute("DELETE FROM sync_batches WHERE dataset=?",
                            (ds,))
            con.commit()
        finally:
            con.close()
        con = _connect()
        try:
            con.execute("VACUUM")
            con.commit()
        finally:
            con.close()
    return {"deleted": targets, "db_file_bytes": db_file_size()}


def status_all() -> dict:
    with _lock:
        con = _connect()
        try:
            out = {}
            for ds in DATASETS:
                st = _get_state(con, ds)
                if st is None or st["synced_at"] is None:
                    out[ds] = {"dataset": ds,
                               "label": DATASET_LABEL[ds],
                               "synced": False, "item_count": 0,
                               "permission_state":
                                   st["permission_state"] if st else None,
                               "pending_write":
                                   bool(st["pending_write"]) if st else False}
                    continue
                age = time.time() - st["synced_at"]
                out[ds] = {
                    "dataset": ds, "label": DATASET_LABEL[ds],
                    "synced": True,
                    "synced_at": _iso(st["synced_at"]),
                    "freshness": freshness_text(
                        st["synced_at"], bool(st["pending_write"])),
                    "expired": age > EXPIRED_AFTER_SEC,
                    "item_count": st["item_count"],
                    "auth_range": st["auth_range"] or "full",
                    "permission_state": st["permission_state"],
                    "pending_write": bool(st["pending_write"]),
                    "syncing": bool(st["syncing"]),
                    "last_error": st["last_error"]}
                if ds == "calendar":
                    out[ds]["coverage"] = {"start": st["coverage_start"],
                                           "end": st["coverage_end"]}
                if ds == "reminders":
                    out[ds]["aggregates"] = st["extra"]
            return out
        finally:
            con.close()


# ------------------------------------------------------------ queries
def _contact_min(row) -> dict:
    phones = json.loads(row["phones"] or "[]")
    return {"id": row["id"], "displayName": row["display_name"],
            "primaryPhone": phones[0]["value"] if phones else None,
            "organization": row["organization"]}


def _contact_full(row) -> dict:
    return {"id": row["id"], "displayName": row["display_name"],
            "familyName": row["family_name"],
            "givenName": row["given_name"],
            "phones": json.loads(row["phones"] or "[]"),
            "emails": json.loads(row["emails"] or "[]"),
            "organization": row["organization"],
            "groups": json.loads(row["groups_json"] or "[]")}


def contacts_count() -> dict:
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "contacts")
            n = con.execute("SELECT COUNT(*) c FROM contacts").fetchone()["c"]
            out = envelope("contacts", st)
            out.update({"total": n})
            return out
        finally:
            con.close()


def contacts_stats() -> dict:
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "contacts")
            rows = con.execute("SELECT * FROM contacts").fetchall()
        finally:
            con.close()
    total = len(rows)
    with_phone = with_email = 0
    by_group: dict[str, int] = {}
    parent: dict[int, int] = {}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    name_keys: dict[str, int] = {}
    phone_keys: dict[str, int] = {}
    for i, row in enumerate(rows):
        parent[i] = i
        phones = json.loads(row["phones"] or "[]")
        emails = json.loads(row["emails"] or "[]")
        if phones:
            with_phone += 1
        if emails:
            with_email += 1
        for g in json.loads(row["groups_json"] or "[]"):
            by_group[g] = by_group.get(g, 0) + 1
        name = (row["display_name"] or "").strip()
        if name:
            if name in name_keys:
                union(i, name_keys[name])
            else:
                name_keys[name] = i
        for p in phones:
            digits = "".join(ch for ch in str(p.get("value", ""))
                             if ch.isdigit())
            if len(digits) > 11:
                digits = digits[-11:]
            if digits:
                if digits in phone_keys:
                    union(i, phone_keys[digits])
                else:
                    phone_keys[digits] = i
    groups: dict[int, int] = {}
    for i in range(total):
        r = find(i)
        groups[r] = groups.get(r, 0) + 1
    dup_groups = sum(1 for v in groups.values() if v > 1)
    out = envelope("contacts", st)
    out.update({
        "total": total,
        "with_phone": with_phone,
        "with_phone_pct": round(with_phone * 100.0 / total, 1)
        if total else 0.0,
        "with_email": with_email,
        "with_email_pct": round(with_email * 100.0 / total, 1)
        if total else 0.0,
        "by_group": by_group,
        "duplicate_candidate_groups": dup_groups})
    return out


def contacts_list(limit: int = 50, offset: int = 0) -> dict:
    limit = max(1, min(int(limit or 50), 100))
    offset = max(0, int(offset or 0))
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "contacts")
            total = con.execute(
                "SELECT COUNT(*) c FROM contacts").fetchone()["c"]
            rows = con.execute(
                "SELECT * FROM contacts ORDER BY display_name, id"
                " LIMIT ? OFFSET ?", (limit, offset)).fetchall()
        finally:
            con.close()
    out = envelope("contacts", st)
    out.update({"total_matches": total, "returned": len(rows),
                "has_more": offset + len(rows) < total,
                "contacts": [_contact_min(r) for r in rows]})
    return out


def contacts_search(query: str) -> dict:
    q = (query or "").strip().lower()
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "contacts")
            rows = con.execute("SELECT * FROM contacts").fetchall()
        finally:
            con.close()
    q_digits = "".join(ch for ch in q if ch.isdigit())
    hits = []
    for row in rows:
        full = _contact_full(row)
        hay = [full["displayName"] or "", full["organization"] or ""]
        hay += [str(e.get("value", "")) for e in full["emails"]]
        matched = any(q in h.lower() for h in hay if h)
        for p in full["phones"]:
            value = str(p.get("value", ""))
            if q in value.lower():
                matched = True
            digits = "".join(ch for ch in value if ch.isdigit())
            if len(digits) > 11:
                digits = digits[-11:]
            if len(q_digits) >= 4 and q_digits in digits:
                matched = True
        if matched:
            hits.append(full)
    out = envelope("contacts", st)
    out.update({"query": query, "total_matches": len(hits),
                "contacts": hits})
    return out


def contacts_get(contact_id: str) -> dict:
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "contacts")
            row = con.execute("SELECT * FROM contacts WHERE id=?",
                              (str(contact_id),)).fetchone()
        finally:
            con.close()
    if row is None:
        raise SyncError("contact_not_found",
                        "副本里没有这个标识的联系人")
    out = envelope("contacts", st)
    out.update({"contact": _contact_full(row)})
    return out


# ---- calendar
def calendar_copy_events(start_ts: float, end_ts: float):
    """Events of the copy overlapping [start_ts, end_ts).
    Returns (events, state). Raises CopyEmpty / SyncError."""
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "calendar")
            rows = con.execute(
                "SELECT * FROM calendar_events WHERE start_ts < ?"
                " AND COALESCE(end_ts, start_ts) >= ?"
                " ORDER BY start_ts", (end_ts, start_ts)).fetchall()
        finally:
            con.close()
    events = [{"occurrenceId": r["occurrence_id"],
               "eventId": r["event_id"], "title": r["title"],
               "start": r["start_iso"], "end": r["end_iso"],
               "allDay": bool(r["all_day"]),
               "calendarName": r["calendar_name"],
               "location": r["location"], "segmentSource": "sync_copy"}
              for r in rows]
    return events, st


def calendar_coverage_epochs(st: dict):
    start = _parse_ts(st.get("coverage_start"))
    end = _parse_ts(st.get("coverage_end"))
    return start, end


def calendar_count(start_ts: float, end_ts: float) -> dict:
    events, st = calendar_copy_events(start_ts, end_ts)
    out = envelope("calendar", st)
    out.update({"count": len(events)})
    return out


def calendar_search(query: str) -> dict:
    q = (query or "").strip().lower()
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "calendar")
            rows = con.execute(
                "SELECT * FROM calendar_events ORDER BY start_ts"
                ).fetchall()
        finally:
            con.close()
    hits = []
    for r in rows:
        hay = " ".join([r["title"] or "", r["location"] or "",
                        r["calendar_name"] or ""]).lower()
        if q in hay:
            hits.append({"occurrenceId": r["occurrence_id"],
                         "eventId": r["event_id"], "title": r["title"],
                         "start": r["start_iso"], "end": r["end_iso"],
                         "allDay": bool(r["all_day"]),
                         "calendarName": r["calendar_name"],
                         "location": r["location"]})
    out = envelope("calendar", st)
    out.update({"query": query, "total_matches": len(hits),
                "events": hits})
    return out


# ---- reminders
def _reminder_row(r) -> dict:
    return {"id": r["id"], "title": r["title"], "due": r["due_iso"],
            "priority": r["priority"], "listName": r["list_name"]}


def reminders_list(list_name: str | None = None) -> dict:
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "reminders")
            if list_name:
                rows = con.execute(
                    "SELECT * FROM reminders WHERE list_name=?"
                    " ORDER BY due_ts IS NULL, due_ts",
                    (list_name,)).fetchall()
            else:
                rows = con.execute(
                    "SELECT * FROM reminders"
                    " ORDER BY due_ts IS NULL, due_ts").fetchall()
        finally:
            con.close()
    out = envelope("reminders", st)
    out.update({"incomplete_count": len(rows),
                "items": [_reminder_row(r) for r in rows]})
    return out


def reminders_count() -> dict:
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "reminders")
            rows = con.execute(
                "SELECT due_ts FROM reminders").fetchall()
        finally:
            con.close()
    now = datetime.now(_LOCAL_TZ)
    day_start = now.replace(hour=0, minute=0, second=0,
                             microsecond=0).timestamp()
    day_end = day_start + 86400
    overdue = sum(1 for r in rows
                  if r["due_ts"] is not None and r["due_ts"] < day_start)
    due_today = sum(1 for r in rows
                    if r["due_ts"] is not None
                    and day_start <= r["due_ts"] < day_end)
    out = envelope("reminders", st)
    out.update({"incomplete": len(rows), "due_today": due_today,
                "overdue": overdue,
                "today_completed": st["extra"].get("today_completed")})
    return out


def reminders_search(query: str) -> dict:
    q = (query or "").strip().lower()
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "reminders")
            rows = con.execute("SELECT * FROM reminders").fetchall()
        finally:
            con.close()
    hits = [_reminder_row(r) for r in rows
            if q in (r["title"] or "").lower()]
    out = envelope("reminders", st)
    out.update({"query": query, "total_matches": len(hits),
                "items": hits})
    return out


# ---- photos (aggregates computed over the full asset index)
def photos_stats() -> dict:
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "photos")
            total = con.execute(
                "SELECT COUNT(*) c FROM photos_assets").fetchone()["c"]
            by_type = {r["media_type"]: r["c"] for r in con.execute(
                "SELECT media_type, COUNT(*) c FROM photos_assets"
                " GROUP BY media_type")}
            favorites = con.execute(
                "SELECT COUNT(*) c FROM photos_assets"
                " WHERE is_favorite=1").fetchone()["c"]
            screenshots = con.execute(
                "SELECT COUNT(*) c FROM photos_assets"
                " WHERE subtype='screenshot'"
                " OR album_name LIKE '%截图%'"
                " OR album_name LIKE '%Screenshot%'").fetchone()["c"]
            months = {}
            for r in con.execute(
                    "SELECT created_month m, media_type t, COUNT(*) c"
                    " FROM photos_assets WHERE created_month IS NOT NULL"
                    " GROUP BY created_month, media_type"):
                slot = months.setdefault(
                    r["m"], {"month": r["m"], "photos": 0, "videos": 0,
                             "total": 0})
                if r["t"] == "video":
                    slot["videos"] += r["c"]
                else:
                    slot["photos"] += r["c"]
                slot["total"] += r["c"]
            span = con.execute(
                "SELECT MIN(created_iso) a, MAX(created_iso) b"
                " FROM photos_assets").fetchone()
        finally:
            con.close()
    out = envelope("photos", st)
    out.update({"total": total, "by_media_type": by_type,
                "favorites": favorites, "screenshots": screenshots,
                "by_month": [months[k] for k in sorted(months)],
                "earliest": span["a"], "latest": span["b"]})
    return out


def photos_recent(limit: int = 50) -> dict:
    limit = max(1, min(int(limit or 50), 200))
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "photos")
            rows = con.execute(
                "SELECT * FROM photos_assets"
                " ORDER BY created_ts DESC LIMIT ?", (limit,)).fetchall()
        finally:
            con.close()
    out = envelope("photos", st)
    out.update({"assets": [
        {"assetId": r["asset_id"], "createdAt": r["created_iso"],
         "mediaType": r["media_type"], "subtype": r["subtype"],
         "isFavorite": bool(r["is_favorite"]),
         "albumName": r["album_name"]} for r in rows]})
    return out


# ---- motion (per-day aggregates merged across syncs)
def motion_summary(days: int = 7) -> dict:
    days = max(1, min(int(days or 7), 366))
    with _lock:
        con = _connect()
        try:
            st = _gate(con, "motion")
            rows = con.execute(
                "SELECT * FROM motion_days ORDER BY date DESC LIMIT ?",
                (days,)).fetchall()
        finally:
            con.close()
    rows = list(reversed(rows))
    out = envelope("motion", st)
    out.update({
        "source_note": "手机计步（与健康的日摘要是两条来源，不要混称）",
        "days": [{"date": r["date"], "steps": r["steps"],
                  "distanceM": r["distance_m"], "flights": r["flights"],
                  "source": r["source"]} for r in rows],
        "total_steps": sum(r["steps"] or 0 for r in rows)})
    return out
