"""overview_gateway: the OneDay overview / notification
aggregation surface as an in-process gateway module.

Batch 3 of the bridge retirement (bridge-retirement-spec-20261124
section 3, row 12): the companion overview bridge (port 8644)
moved into the gateway. The bridge file is carried over verbatim
except for the shell differences registered in
bridge-batch3-rollout-20261124.md:

- the HTTP shell becomes three public functions (get_overview /
  get_notifications / mark_read) in the write_gate_gateway style;
  auth moves to api_server's @_require_auth (API_SERVER_KEY,
  single credential source) and the bridge key
  OVERVIEW_BRIDGE_KEY is retired;
- the three owner sources are all gateway-local now: hermes
  itself (loopback 8642), the write-gate gateway surface (shape
  route /api/write-gate on the same loopback) and the oneday
  gateway surface (shape route /api/oneday-bridge); every client
  key resolves to API_SERVER_KEY (legacy env names kept as
  fallbacks for isolated testing only);
- STATE_DIR default moves to /opt/data/overview (state file
  carried over in place at rollout);
- _print() call sites route through a logger shim (_print).

The aggregation contract is unchanged: four sources read at read
time (write-gate decisions born read, monitor notifications,
write-gate pending born unread but excluded from the /overview
unread count, gateway run terminal states), live baselines
(monitor_since / runs_since) and read marks owned here.

Package 2.4.0 (G1 task-side failure coverage, DESIGN section
385.1): two more read-time sources join the aggregation --
cron job failures (kind cron_failed, one entry per OPEN incident
in cron/executions.db's cron_incidents table, which already
aggregates by (job_id, error signature) upstream) and kanban
task failures (kind kanban_failed, one entry per task whose
LATEST terminal task_run failed, scanned read-only across
/opt/data/kanban/boards/*/kanban.db). Both are born unread and
DO count into the /overview unread count (a failure is an
incident, not a wait state -- unlike pending approvals). Each
source has its own live baseline (cron_since / kanban_since)
so pre-existing failure stock never backfills. Error text is
projected as a single sanitized line (<=120 chars, paths and
stack traces stripped): lifecycle facts only, content never
leaks -- the same discipline as the runs projection.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import sqlite3
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

HERMES_API_KEY = os.environ.get("API_SERVER_KEY") or \
    os.environ.get("HERMES_API_KEY", "")
HERMES_BASE = os.environ.get("HERMES_BASE", "http://127.0.0.1:8642").rstrip("/")
WRITE_GATE_BASE = os.environ.get(
    "WRITE_GATE_BASE", "http://127.0.0.1:8642/api/write-gate").rstrip("/")
# Server-side service credential (F03 rotation, 2026-11-10):
# the pendingApprovals count is read from write-gate's
# /status, which since the per-bridge key split requires
# write-gate's OWN key. This bridge therefore holds that
# key as a client credential for this one internal call
# (env WRITE_GATE_BRIDGE_KEY, delivered via
# overview-bridge.env). It is never accepted as THIS
# bridge's key and never leaves the server.
WRITE_GATE_CLIENT_KEY = os.environ.get("API_SERVER_KEY") or \
    os.environ.get("WRITE_GATE_BRIDGE_KEY", "")
ONEDAY_BASE = os.environ.get(
    "ONEDAY_BASE", "http://127.0.0.1:8642/api/oneday-bridge").rstrip("/")
# Same client-credential pattern as WRITE_GATE_CLIENT_KEY above:
# monitor notifications are read from the oneday bridge's
# GET /monitors/notifications with that bridge's OWN key
# (env ONEDAY_BRIDGE_KEY, delivered via modules.json env_from).
# It is never accepted as THIS bridge's key and never leaves
# the server.
ONEDAY_CLIENT_KEY = os.environ.get("API_SERVER_KEY") or \
    os.environ.get("ONEDAY_BRIDGE_KEY", "")
STATE_DIR = Path(os.environ.get("STATE_DIR", "/opt/data/overview"))
# G1 (2.4.0): failure-source locations. The cron ledger and the
# kanban boards are read read-only at read time; env overrides
# exist for isolated testing only.
CRON_DB_PATH = Path(os.environ.get(
    "CRON_EXECUTIONS_DB", "/opt/data/cron/executions.db"))
CRON_JOBS_PATH = Path(os.environ.get(
    "CRON_JOBS_FILE", "/opt/data/cron/jobs.json"))
KANBAN_BOARDS_DIR = Path(os.environ.get(
    "KANBAN_BOARDS_DIR", "/opt/data/kanban/boards"))
import logging as _logging

logger = _logging.getLogger(__name__)


def _print(*args, **kwargs):
    """Bridge _print() shim (batch 3): stdout prints -> logger.info,
    stderr prints -> logger.warning. Call sites are the bridge's own,
    mechanically renamed _print( -> _print( ."""
    kwargs.pop("flush", None)
    _file = kwargs.pop("file", None)
    _msg = " ".join(str(a) for a in args)
    if _file is sys.stderr:
        logger.warning("%s", _msg)
    else:
        logger.info("%s", _msg)


STATE_PATH = STATE_DIR / "state.json"
DECISIONS_LIMIT = 50
MONITOR_LIMIT = 100
CRON_LIMIT = 50
KANBAN_LIMIT = 50

_TITLES = {
    ("memory", "approved"): "记忆写入已批准",
    ("memory", "rejected"): "记忆写入已被驳回",
    ("skills", "approved"): "技能写入已批准",
    ("skills", "rejected"): "技能写入已被驳回",
}

_lock = threading.Lock()
# Slim state (B-03, 1.0.63): no notification copies, no offsets,
# no seen sets. What remains is genuinely overview-owned:
# - read_ids: ids of monitor-side notifications the user marked
#   read (decision receipts are born read by construction and
#   never land here);
# - monitor_since: the monitor source's live baseline --
#   monitor records older than this are history that predates
#   the source going live and are never backfilled (the
#   pre-1.0.63 baseline rule, kept as a timestamp instead of a
#   file offset + line hashes).
_state: dict = {"read_ids": [], "monitor_since": None, "runs_since": None,
                "cron_since": None, "kanban_since": None}
_read_set: set = set()


def _now_iso() -> str:
    return datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z")


# --- state -----------------------------------------------------------------

def _save_locked() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    _state["read_ids"] = sorted(_read_set)[-5000:]
    tmp = STATE_PATH.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(_state, f, ensure_ascii=False)
    os.replace(tmp, STATE_PATH)


def _load_state() -> None:
    global _read_set
    if STATE_PATH.exists():
        data = None
        try:
            data = json.loads(STATE_PATH.read_text(encoding="utf-8"))
        except Exception as e:
            _print(f"state load failed ({e}); starting fresh",
                  file=sys.stderr)
        if isinstance(data, dict) and "notifications" in data:
            # Migration from the pre-1.0.63 materialized store:
            # carry over the monitor-side items' read marks and
            # set the monitor baseline at the oldest stored
            # monitor-side item, so exactly the stock the user
            # could already see stays visible -- nothing older
            # backfills and no read mark is lost. Decision
            # receipts need nothing: they are re-derived from
            # write-gate /decisions on every read, born read.
            legacy = [n for n in data.get("notifications", [])
                      if isinstance(n, dict)]
            mon = [n for n in legacy
                   if n.get("kind") != "write_gate_decision"]
            _read_set = {n["id"] for n in mon
                         if n.get("read") and n.get("id")}
            stamps = [n.get("createdAt") for n in mon
                      if n.get("createdAt")]
            _state["read_ids"] = sorted(_read_set)
            _state["monitor_since"] = (min(stamps) if stamps
                                       else _now_iso())
            _state["runs_since"] = _now_iso()
            _state["cron_since"] = _now_iso()
            _state["kanban_since"] = _now_iso()
            _save_locked()
            return
        if isinstance(data, dict):
            _read_set = set(data.get("read_ids", []))
            _state["read_ids"] = sorted(_read_set)
            _state["monitor_since"] = data.get("monitor_since")
            _state["runs_since"] = data.get("runs_since")
            _state["cron_since"] = data.get("cron_since")
            _state["kanban_since"] = data.get("kanban_since")
            if not _state["monitor_since"]:
                _state["monitor_since"] = _now_iso()
                _save_locked()
            if not _state["runs_since"]:
                # Runs source goes live now (1.0.67): terminal runs
                # from before this moment are history, never
                # backfilled (same baseline rule as monitors).
                _state["runs_since"] = _now_iso()
                _save_locked()
            if not _state["cron_since"]:
                # Cron failure source goes live now (2.4.0, G1):
                # incidents last seen before this moment are
                # history, never backfilled (same baseline rule).
                _state["cron_since"] = _now_iso()
                _save_locked()
            if not _state["kanban_since"]:
                # Kanban failure source goes live now (2.4.0, G1).
                _state["kanban_since"] = _now_iso()
                _save_locked()
            return
    # First boot: the monitor baseline is now -- monitor history
    # that predates this bridge going live is never backfilled.
    _state["monitor_since"] = _now_iso()
    _state["runs_since"] = _now_iso()
    _state["cron_since"] = _now_iso()
    _state["kanban_since"] = _now_iso()
    _save_locked()


# --- notifications: read-time aggregation (B-03) -----------------------------
#
# Both sources are queried over HTTP at read time from their owner
# modules; this bridge keeps no copies. A source that fails to
# answer degrades to empty for that request (logged), never to a
# 500 for the whole surface -- the same philosophy as the
# /overview pending-approvals count below.

def _parse_ts(value) -> float:
    if not value:
        return 0.0
    try:
        return datetime.fromisoformat(
            str(value).replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0.0


def _decision_notification(entry: dict) -> dict | None:
    sub = entry.get("subsystem", "")
    dec = entry.get("decision", "")
    if dec not in ("approved", "rejected"):
        return None
    title = _TITLES.get((sub, dec), "写入审批已处理")
    body = (entry.get("summary") or "").strip()
    if not body:
        what = {"memory": "一项记忆写入", "skills": "一项技能写入"}.get(
            sub, "一项写入")
        verb = {"approved": "已批准", "rejected": "已被驳回"}.get(dec, "已处理")
        body = what + verb
    rid = entry.get("id") or None
    return {
        "id": "wg-" + (rid or hashlib.sha1(
            f"{sub}|{dec}|{entry.get('decided_at')}|{body}".encode(
                "utf-8")).hexdigest()[:12]),
        "kind": "write_gate_decision",
        # refId (0.36.5): the write-gate record id from the
        # decisions entry, carried for decided-history linkage;
        # an empty/missing record id degrades to null.
        "refId": rid,
        "title": title,
        "body": body,
        "createdAt": entry.get("decided_at") or _now_iso(),
        # Born read: approved/rejected are the only values
        # admitted here, so a decision receipt is always the
        # record of an already-finished approval -- a record,
        # not a reminder (user ruling 2026-11-11). Judged from
        # the event's own status field, never from title text.
        "read": True,
        "changeId": None,
    }


def _monitor_notification(entry: dict) -> dict:
    # Monitor ledger records are already in notification shape; kind /
    # title / body / id / createdAt pass through as recorded.
    # 1.0.14 (§123 H2): refId (monitor id) + changeId pass through
    # when the producer recorded them; legacy lines without them
    # surface as null and the app degrades to the monitors section.
    nid = entry.get("id") or ("mon-" + hashlib.sha1(
        json.dumps(entry, ensure_ascii=False, sort_keys=True).encode(
            "utf-8")).hexdigest()[:12])
    return {
        "id": nid,
        "kind": entry.get("kind") or "monitor_change",
        "title": entry.get("title") or "监测有变化",
        "body": (entry.get("body") or "").strip(),
        "createdAt": entry.get("createdAt") or _now_iso(),
        "read": nid in _read_set,
        "refId": entry.get("refId"),
        "changeId": entry.get("changeId"),
    }


def _fetch_decisions() -> list:
    try:
        status, data = _get_json(
            f"{WRITE_GATE_BASE}/decisions?limit={DECISIONS_LIMIT}",
            WRITE_GATE_CLIENT_KEY, 3)
        if status != 200 or not isinstance(data, dict):
            return []
        rows = data.get("decisions") or []
    except Exception as e:
        _print(f"write-gate /decisions query failed: {e!r}",
              file=sys.stderr, flush=True)
        return []
    out = []
    for row in rows:
        if isinstance(row, dict):
            n = _decision_notification(row)
            if n is not None:
                out.append(n)
    return out


def _fetch_monitor() -> list:
    try:
        status, data = _get_json(
            f"{ONEDAY_BASE}/monitors/notifications?limit={MONITOR_LIMIT}",
            ONEDAY_CLIENT_KEY, 3)
        if status != 200 or not isinstance(data, dict):
            return []
        rows = data.get("items") or []
    except Exception as e:
        _print(f"oneday /monitors/notifications query failed: {e!r}",
              file=sys.stderr, flush=True)
        return []
    since = _state.get("monitor_since") or ""
    out = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        # Live baseline: records older than the source going
        # live are history, never backfilled.
        if since and (row.get("createdAt") or "") < since:
            continue
        out.append(_monitor_notification(row))
    return out


_PENDING_TITLES = {
    "memory": "记忆写入待审批",
    "skills": "技能写入待审批",
}


def _pending_notification(entry: dict) -> dict | None:
    rid = entry.get("id") or None
    if not rid:
        return None
    sub = entry.get("subsystem", "")
    body = (entry.get("summary") or "").strip()
    if not body:
        what = {"memory": "一项记忆写入", "skills": "一项技能写入"}.get(
            sub, "一项写入")
        body = what + "等待审批"
    nid = "wgp-" + rid
    return {
        "id": nid,
        "kind": "approval_pending",
        "refId": rid,
        "title": _PENDING_TITLES.get(sub, "写入待审批"),
        "body": body,
        "createdAt": entry.get("created_at") or _now_iso(),
        # Born unread: a pending approval asks for a decision.
        # The mark lives in read_ids like monitor items; once the
        # approval is decided the entry leaves this source and the
        # born-read decision receipt replaces it.
        "read": nid in _read_set,
        "changeId": None,
    }


def _fetch_pending() -> list:
    try:
        status, data = _get_json(
            f"{WRITE_GATE_BASE}/pending", WRITE_GATE_CLIENT_KEY, 3)
        if status != 200 or not isinstance(data, dict):
            return []
        rows = data.get("records") or []
    except Exception as e:
        _print(f"write-gate /pending query failed: {e!r}",
              file=sys.stderr, flush=True)
        return []
    out = []
    for row in rows:
        if isinstance(row, dict):
            n = _pending_notification(row)
            if n is not None:
                out.append(n)
    return out


def _run_notification(entry: dict) -> dict | None:
    status = entry.get("status")
    if status == "completed":
        kind, title, body = "task_completed", "运行完成", "一轮运行已完成"
    elif status == "failed":
        kind, title, body = "run_failed", "运行失败", "一轮运行失败"
    else:
        # cancelled / interrupted are user-initiated stops, and
        # anything non-terminal never reaches this list at all.
        return None
    if status == "completed" and str(
            entry.get("session_id") or "").startswith("run_"):
        # Source-side fix (batch 3; user report 2026-11-24 #6):
        # pipeline rounds run as pseudo-sessions whose session_id
        # IS the run_id (feed / ideas / briefing rounds and their
        # sub-runs). Their completion is pipeline bookkeeping, not
        # a user task finishing -- the bridge-era source minted a
        # task_completed notification for every seat (62.5% of one
        # day's completion notifications). Failed pipeline runs
        # still surface below: a broken round is exactly what the
        # user wants to hear about.
        return None
    run_id = entry.get("run_id") or ""
    if not run_id:
        return None
    updated = entry.get("updated_at") or 0
    try:
        created = datetime.fromtimestamp(
            float(updated), tz=timezone.utc).isoformat().replace(
                "+00:00", "Z")
    except Exception:
        created = _now_iso()
    nid = "run-" + run_id
    return {
        "id": nid,
        "kind": kind,
        "refId": entry.get("session_id"),
        "title": title,
        "body": body,
        "createdAt": created,
        "read": nid in _read_set,
        "changeId": None,
    }


def _fetch_runs() -> list:
    if not HERMES_API_KEY:
        return []
    try:
        status, data = _get_json(
            f"{HERMES_BASE}/v1/runs?limit=50", HERMES_API_KEY, 3)
        if status != 200 or not isinstance(data, dict):
            return []
        rows = data.get("data") or []
    except Exception as e:
        _print(f"hermes /v1/runs query failed: {e!r}",
              file=sys.stderr, flush=True)
        return []
    since = _parse_ts(_state.get("runs_since"))
    out = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        # Live baseline: runs terminated before this source went
        # live are history, never backfilled.
        if since and float(row.get("updated_at") or 0) <= since:
            continue
        n = _run_notification(row)
        if n is not None:
            out.append(n)
    return out


# --- G1 (2.4.0): cron / kanban failure sources ---------------------
#
# Both sources read SQLite ledgers READ-ONLY at read time and keep
# no copies, like every other source here. A missing or unreadable
# ledger degrades that source to empty for the request (logged),
# never to a 500 for the whole surface.

_PATH_RE = re.compile(r"(?:/[\w.\-]+)+/?")


def _one_line_reason(text, limit: int = 120) -> str:
    """Project an error blob to ONE sanitized summary line with
    redaction and classification: paths/URLs/tokens replaced,
    exception type names and status codes recognized and mapped
    to human categories, whitespace collapsed, length capped."""
    from .error_boundary import redact

    raw = str(text or "").strip()
    if not raw:
        return ""

    # Take first non-empty line
    out = ""
    for line in raw.splitlines():
        line = line.strip()
        if line:
            out = line
            break

    # Apply full redaction (paths, URLs, whitespace, length cap)
    out = redact(out)

    # Classify common patterns to human categories
    lower = out.lower()
    if "timeout" in lower or "timed out" in lower:
        return "上游服务超时"
    if "connection" in lower or "connect" in lower:
        return "连接失败"
    if "permission" in lower or "forbidden" in lower or "unauthorized" in lower:
        return "权限不足"
    if "not found" in lower or "404" in out:
        return "资源未找到"
    if "rate limit" in lower or "429" in out:
        return "请求过于频繁"
    if "internal" in lower or "500" in out:
        return "服务器内部错误"

    # Already redacted, apply final length cap
    if len(out) > limit:
        out = out[:limit - 1].rstrip() + "…"

    return out


def _iso_z(value) -> str:
    """Normalize an ISO timestamp (any offset) to the Z form the
    notification shape uses; unparseable values degrade to now."""
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).isoformat().replace(
            "+00:00", "Z")
    except Exception:
        return _now_iso()


def _cron_job_names() -> dict:
    try:
        data = json.loads(CRON_JOBS_PATH.read_text(encoding="utf-8"))
        rows = data.get("jobs") if isinstance(data, dict) else data
        return {str(r.get("id")): str(r.get("name") or r.get("id"))
                for r in rows if isinstance(r, dict) and r.get("id")}
    except Exception:
        return {}


def _cron_failure_notification(incident: dict, names: dict) -> dict:
    job_id = str(incident.get("job_id") or "")
    name = names.get(job_id) or job_id or "未知任务"
    reason = _one_line_reason(incident.get("error")) \
        or str(incident.get("failure_type") or "执行失败")
    nid = "cron-" + str(incident.get("id") or "")
    return {
        "id": nid,
        "kind": "cron_failed",
        "refId": job_id or None,
        "title": "定时任务失败",
        "body": f"{name}：{reason}",
        "createdAt": _iso_z(incident.get("last_seen_at")),
        # Born unread: a failure is an incident, not a record.
        "read": nid in _read_set,
        "changeId": None,
    }


def _fetch_cron_failures() -> list:
    if not CRON_DB_PATH.exists():
        return []
    try:
        conn = sqlite3.connect(
            f"file:{CRON_DB_PATH}?mode=ro", uri=True, timeout=3)
        conn.row_factory = sqlite3.Row
        try:
            rows = conn.execute(
                "SELECT id, job_id, state, failure_type,"
                " first_seen_at, last_seen_at, error"
                " FROM cron_incidents"
                " WHERE state IN ('detected', 'alerted')"
                " ORDER BY julianday(last_seen_at) DESC"
                " LIMIT ?", (CRON_LIMIT,)).fetchall()
        finally:
            conn.close()
    except Exception as e:
        _print(f"cron incidents query failed: {e!r}",
               file=sys.stderr, flush=True)
        return []
    # One entry per OPEN incident: cron_incidents already
    # aggregates executions by (job_id, error signature)
    # upstream, so the same fault re-failing every round refreshes
    # last_seen_at on the SAME incident instead of minting a new
    # entry here. Resolved/closed incidents stay silent.
    since = _parse_ts(_state.get("cron_since"))
    names = _cron_job_names()
    out = []
    for row in rows:
        incident = dict(row)
        # Live baseline: incidents last seen before this source
        # went live are history, never backfilled.
        if since and _parse_ts(incident.get("last_seen_at")) <= since:
            continue
        out.append(_cron_failure_notification(incident, names))
    return out


_KANBAN_FAIL_STATUSES = {"crashed", "timed_out", "failed"}
_KANBAN_FAIL_OUTCOMES = {"crashed", "timed_out", "spawn_failed",
                         "gave_up", "stale", "rate_limited"}


def _kanban_run_failed(run: dict) -> bool:
    if str(run.get("status") or "") in _KANBAN_FAIL_STATUSES:
        return True
    if str(run.get("outcome") or "") in _KANBAN_FAIL_OUTCOMES:
        return True
    # A terminal run carrying an error but no failure verdict
    # still counts -- unless it completed (done runs may carry
    # diagnostic text in error on some paths).
    return bool(str(run.get("error") or "").strip()) \
        and str(run.get("status") or "") != "done"


def _kanban_failure_notification(board: str, run: dict) -> dict:
    task_id = str(run.get("task_id") or "")
    title = str(run.get("task_title") or "").strip() or task_id or "未知任务"
    reason = _one_line_reason(run.get("error")) \
        or str(run.get("outcome") or run.get("status") or "执行失败")
    nid = f"kanban-{board}-{task_id}"
    try:
        created = datetime.fromtimestamp(
            float(run.get("ended_at") or 0),
            tz=timezone.utc).isoformat().replace("+00:00", "Z")
    except Exception:
        created = _now_iso()
    return {
        "id": nid,
        "kind": "kanban_failed",
        "refId": task_id or None,
        "title": "看板任务失败",
        "body": f"{board} · {title}：{reason}",
        "createdAt": created,
        "read": nid in _read_set,
        "changeId": None,
    }


def _fetch_kanban_failures() -> list:
    if not KANBAN_BOARDS_DIR.exists():
        return []
    since = _parse_ts(_state.get("kanban_since"))
    out = []
    for board_dir in sorted(KANBAN_BOARDS_DIR.iterdir()):
        db_path = board_dir / "kanban.db"
        if not board_dir.is_dir() or not db_path.exists():
            continue
        try:
            conn = sqlite3.connect(
                f"file:{db_path}?mode=ro", uri=True, timeout=3)
            conn.row_factory = sqlite3.Row
            try:
                rows = conn.execute(
                    "SELECT r.id, r.task_id, r.status, r.outcome,"
                    " r.error, r.ended_at, t.title AS task_title"
                    " FROM task_runs r"
                    " LEFT JOIN tasks t ON t.id = r.task_id"
                    " WHERE r.ended_at IS NOT NULL"
                    " ORDER BY r.id").fetchall()
            finally:
                conn.close()
        except Exception as e:
            _print(f"kanban board {board_dir.name} query failed: {e!r}",
                   file=sys.stderr, flush=True)
            continue
        # Terminal-failure caliber: only a task's LATEST terminal
        # run decides. A crash that a retry later healed does not
        # surface; intermediate retries never mint entries.
        latest: dict = {}
        for row in rows:
            run = dict(row)
            latest[str(run.get("task_id") or "")] = run
        for run in latest.values():
            if not _kanban_run_failed(run):
                continue
            # Live baseline, same rule as the other sources.
            if since and float(run.get("ended_at") or 0) <= since:
                continue
            out.append(_kanban_failure_notification(
                board_dir.name, run))
    out.sort(key=lambda n: _parse_ts(n.get("createdAt")), reverse=True)
    return out[:KANBAN_LIMIT]


def _current_notifications() -> list:
    """Merged newest-first view over all owner sources."""
    items = (_fetch_decisions() + _fetch_monitor()
             + _fetch_pending() + _fetch_runs()
             + _fetch_cron_failures() + _fetch_kanban_failures())
    items.sort(key=lambda n: _parse_ts(n.get("createdAt")),
               reverse=True)
    return items


# --- upstream queries --------------------------------------------------------

def _get_json(url: str, key: str | None, timeout: float):
    req = Request(url, headers={"Accept": "application/json"})
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    with urlopen(req, timeout=timeout) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8"))


def _overview() -> dict:
    hermes_up = False
    active = 0
    try:
        status, _ = _get_json(HERMES_BASE + "/health", None, 2)
        hermes_up = status == 200
    except Exception:
        hermes_up = False
    if hermes_up and HERMES_API_KEY:
        try:
            status, data = _get_json(
                HERMES_BASE + "/api/sessions?limit=500", HERMES_API_KEY, 4)
            if status == 200 and isinstance(data, dict):
                rows = data.get("data") or []
                active = sum(1 for r in rows if not r.get("ended_at"))
        except Exception:
            active = 0
    pending = 0
    try:
        status, data = _get_json(
            WRITE_GATE_BASE + "/status", WRITE_GATE_CLIENT_KEY, 3)
        if status == 200:
            counts = data.get("counts") or {}
            pending = int(counts.get("memory", 0)) + int(
                counts.get("skills", 0))
    except Exception as e:
        # Never let a broken service call pass silently:
        # the count falls back to 0 in the payload, but the
        # failure is on the record in the bridge log.
        _print(f"write-gate /status query failed: {e!r}",
              file=sys.stderr, flush=True)
        pending = 0
    # Unread caliber: monitor items + run items (both are pure
    # notification-stream sources). Decision receipts are born
    # read; pending-approval entries are NOT added here -- they
    # are already counted on the pendingApprovals axis above,
    # and one real-world item must not count twice. G1 (2.4.0):
    # cron / kanban failure items DO count here -- a failure is
    # an incident that must interrupt, not a wait state, and it
    # is not counted on any other axis.
    unread = sum(1 for n in _fetch_monitor() if not n["read"])
    unread += sum(1 for n in _fetch_runs() if not n["read"])
    unread += sum(1 for n in _fetch_cron_failures() if not n["read"])
    unread += sum(1 for n in _fetch_kanban_failures() if not n["read"])
    return {
        "hermesUp": hermes_up,
        "activeSessions": active,
        "pendingApprovals": pending,
        "unreadNotifications": unread,
        "generatedAt": _now_iso(),
    }


def _public(n: dict) -> dict:
    return {
        "id": n["id"],
        "kind": n["kind"],
        "title": n["title"],
        "body": n["body"],
        "createdAt": n["createdAt"],
        "read": bool(n.get("read")),
        # Passed through for every kind. Monitor notifications
        # carry refId=monitor id + changeId from 1.0.14 on;
        # older stored ones surface both as None.
        "refId": n.get("refId"),
        "changeId": n.get("changeId"),
    }


# --- gateway shell (batch 3): public functions ------------------------

_started = False


def start() -> None:
    """Idempotent boot: load the slim state (read marks + live
    baselines), as the bridge's main() did before serving."""
    global _started
    if _started:
        return
    _started = True
    _load_state()


def get_overview():
    start()
    try:
        return 200, _overview()
    except Exception as e:
        _print(f"overview failed: {e!r}", file=sys.stderr, flush=True)
        return 500, {"error": "服务器内部错误"}


def get_notifications():
    start()
    try:
        items = _current_notifications()[:50]
        return 200, {"items": [_public(n) for n in items]}
    except Exception as e:
        _print(f"notifications failed: {e!r}", file=sys.stderr,
               flush=True)
        return 500, {"error": "服务器内部错误"}


def mark_read(nid: str):
    start()
    try:
        target = next(
            (n for n in _current_notifications() if n["id"] == nid),
            None)
        if target is None:
            return 404, {"error": "not found"}
        if target["kind"] != "write_gate_decision":
            # Decision receipts are born read; only monitor-side
            # items take a persisted mark.
            with _lock:
                _read_set.add(nid)
                _save_locked()
        return 200, {"ok": True}
    except Exception as e:
        _print(f"mark read failed: {e!r}", file=sys.stderr, flush=True)
        return 500, {"error": "服务器内部错误"}


if __name__ == "__main__":
    sys.exit(main())
