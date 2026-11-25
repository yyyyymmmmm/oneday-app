#!/usr/bin/env python3
"""overview-bridge: read-only aggregation sidecar for OneDay phase 1.

Serves the frozen overview contract for the OneDay app:
- GET  /overview                 -> hermesUp / activeSessions /
                                    pendingApprovals / unreadNotifications /
                                    generatedAt
- GET  /notifications            -> newest-first notification items (<=50)
- POST /notifications/{id}/read  -> {"ok": true}

Data sources (all server-local, nothing leaves the box):
- hermesUp / activeSessions: Hermes API server (hermes:8642). hermesUp =
  GET /health == 200; activeSessions = sessions from GET /api/sessions
  whose ended_at is empty (still open) -- caliber noted in rollout record.
- pendingApprovals: write-gate bridge GET /status counts (memory+skills),
  same caliber as the bridge itself, queried server-side with write-gate's
  own key (service credential, see WRITE_GATE_CLIENT_KEY note).
- notifications: aggregated AT READ TIME over HTTP from the two
  owner modules (B-03 convergence, companion 1.0.63 -- this bridge
  used to tail the owners' JSONL ledgers with byte offsets + line
  hashes and materialize copies in its own state; that machinery
  is gone, the owners are the single source):
  1. write-gate GET /decisions -- terminal approved/rejected rows
     become kind="write_gate_decision" notifications (title mapped
     zh, body from the decision summary). Decision receipts are
     BORN READ (2026-11-11 caliber, user ruling: already-decided
     approvals must not raise reminders): the ledger only ever
     carries terminal values, so every such item is the record of
     an approval that was already decided before the notification
     existed -- records stay listed for lookup but never raise an
     unread dot or badge count.
  2. oneday-bridge GET /monitors/notifications -- change records
     written by the monitor engine and the automation rounds;
     kind/title/body/id are passed through as recorded
     (kind="monitor_change" / "agent_message").
  3. write-gate GET /pending -- approvals still waiting become
     kind="approval_pending" entries (companion 1.0.67, demand-
     ledger 162 gap G2). Born UNREAD (they ask for a decision);
     the entry exists exactly while the approval is pending --
     once decided it vanishes from this source and the terminal
     decision receipt (source 1, born read) takes its place. The
     /overview unread count does NOT add them: pending approvals
     are already counted on their own axis (pendingApprovals),
     so counting both would double-count one real-world item.
  4. hermes GET /v1/runs -- recent terminal runs in the gateway
     key's scope (companion 1.0.67, demand-ledger 162/163 gaps
     G1/G3): completed becomes kind="task_completed", failed
     becomes kind="run_failed" (the app tier classifier keys on
     the fail signal in the kind). Bodies carry NO run content --
     lifecycle facts only, same privacy caliber as Live
     Activities (section 385.3). Cancelled/interrupted runs are
     user-initiated stops and are not emitted. A live baseline
     (runs_since) applies like the monitor source's: runs that
     terminated before this source went live are history and
     never backfilled.
  The only state this bridge still owns is the two sources'
  live baselines (monitor_since / runs_since: records older
  than the source going live are history and never backfilled)
  and the user's read marks for non-receipt items (read_ids). A source that
  fails to answer degrades to empty for that request (logged),
  never to a 500 for the whole surface.

Auth: single Bearer key, scoped to this bridge
(OVERVIEW_BRIDGE_KEY env, own key since the 2026-11-10
F03 rotation). Fail-closed when unset.
Access log: method/path/status only.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import sys
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

API_KEY = os.environ.get("OVERVIEW_BRIDGE_KEY", "")
HERMES_API_KEY = os.environ.get("HERMES_API_KEY", "")
HERMES_BASE = os.environ.get("HERMES_BASE", "http://hermes:8642").rstrip("/")
WRITE_GATE_BASE = os.environ.get(
    "WRITE_GATE_BASE", "http://write-gate-bridge:8643").rstrip("/")
# Server-side service credential (F03 rotation, 2026-11-10):
# the pendingApprovals count is read from write-gate's
# /status, which since the per-bridge key split requires
# write-gate's OWN key. This bridge therefore holds that
# key as a client credential for this one internal call
# (env WRITE_GATE_BRIDGE_KEY, delivered via
# overview-bridge.env). It is never accepted as THIS
# bridge's key and never leaves the server.
WRITE_GATE_CLIENT_KEY = os.environ.get("WRITE_GATE_BRIDGE_KEY", "")
ONEDAY_BASE = os.environ.get(
    "ONEDAY_BASE", "http://127.0.0.1:8646").rstrip("/")
# Same client-credential pattern as WRITE_GATE_CLIENT_KEY above:
# monitor notifications are read from the oneday bridge's
# GET /monitors/notifications with that bridge's OWN key
# (env ONEDAY_BRIDGE_KEY, delivered via modules.json env_from).
# It is never accepted as THIS bridge's key and never leaves
# the server.
ONEDAY_CLIENT_KEY = os.environ.get("ONEDAY_BRIDGE_KEY", "")
STATE_DIR = Path(os.environ.get("STATE_DIR", "/opt/overview-data"))
STATE_PATH = STATE_DIR / "state.json"
PORT = int(os.environ.get("OVERVIEW_PORT", "8644"))
DECISIONS_LIMIT = 50
MONITOR_LIMIT = 100

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
_state: dict = {"read_ids": [], "monitor_since": None, "runs_since": None}
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
            print(f"state load failed ({e}); starting fresh",
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
            _save_locked()
            return
        if isinstance(data, dict):
            _read_set = set(data.get("read_ids", []))
            _state["read_ids"] = sorted(_read_set)
            _state["monitor_since"] = data.get("monitor_since")
            _state["runs_since"] = data.get("runs_since")
            if not _state["monitor_since"]:
                _state["monitor_since"] = _now_iso()
                _save_locked()
            if not _state["runs_since"]:
                # Runs source goes live now (1.0.67): terminal runs
                # from before this moment are history, never
                # backfilled (same baseline rule as monitors).
                _state["runs_since"] = _now_iso()
                _save_locked()
            return
    # First boot: the monitor baseline is now -- monitor history
    # that predates this bridge going live is never backfilled.
    _state["monitor_since"] = _now_iso()
    _state["runs_since"] = _now_iso()
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
        print(f"write-gate /decisions query failed: {e!r}",
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
        print(f"oneday /monitors/notifications query failed: {e!r}",
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
        print(f"write-gate /pending query failed: {e!r}",
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
        print(f"hermes /v1/runs query failed: {e!r}",
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


def _current_notifications() -> list:
    """Merged newest-first view over all owner sources."""
    items = (_fetch_decisions() + _fetch_monitor()
             + _fetch_pending() + _fetch_runs())
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
        print(f"write-gate /status query failed: {e!r}",
              file=sys.stderr, flush=True)
        pending = 0
    # Unread caliber: monitor items + run items (both are pure
    # notification-stream sources). Decision receipts are born
    # read; pending-approval entries are NOT added here -- they
    # are already counted on the pendingApprovals axis above,
    # and one real-world item must not count twice.
    unread = sum(1 for n in _fetch_monitor() if not n["read"])
    unread += sum(1 for n in _fetch_runs() if not n["read"])
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


# --- HTTP layer ---------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "overview-bridge/1.0"

    def log_message(self, fmt, *args):  # method/path/status only
        try:
            status = args[1] if len(args) > 1 else "-"
        except Exception:
            status = "-"
        print(f"{self.command} {self.path} -> {status}", file=sys.stderr)

    def _send(self, code: int, obj: dict):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authed(self) -> bool:
        header = self.headers.get("Authorization", "")
        expected = f"Bearer {API_KEY}"
        return bool(API_KEY) and hmac.compare_digest(header, expected)

    def _drain_body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except Exception:
            n = 0
        if n > 0:
            self.rfile.read(min(n, 1 << 20))

    def do_GET(self):
        if not self._authed():
            return self._send(401, {"error": "unauthorized"})
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        try:
            if parts == ["overview"]:
                return self._send(200, _overview())
            if parts == ["notifications"]:
                items = _current_notifications()[:50]
                return self._send(
                    200, {"items": [_public(n) for n in items]})
            return self._send(404, {"error": "not found"})
        except Exception as e:
            return self._send(500, {"error": f"{type(e).__name__}: {e}"})

    def do_POST(self):
        self._drain_body()
        if not self._authed():
            return self._send(401, {"error": "unauthorized"})
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        try:
            if len(parts) == 3 and parts[0] == "notifications" \
                    and parts[2] == "read":
                nid = parts[1]
                target = next(
                    (n for n in _current_notifications()
                     if n["id"] == nid), None)
                if target is None:
                    return self._send(404, {"error": "not found"})
                if target["kind"] != "write_gate_decision":
                    # Decision receipts are born read; only
                    # monitor-side items take a persisted mark.
                    with _lock:
                        _read_set.add(nid)
                        _save_locked()
                return self._send(200, {"ok": True})
            return self._send(404, {"error": "not found"})
        except Exception as e:
            return self._send(500, {"error": f"{type(e).__name__}: {e}"})


def main():
    if not API_KEY:
        print("OVERVIEW_BRIDGE_KEY is not set; refusing to start (fail-closed).",
              file=sys.stderr)
        return 2
    _load_state()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    print(f"overview-bridge listening on :{PORT}", file=sys.stderr)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
