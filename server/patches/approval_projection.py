"""Approval persistence projection (local patch, hermes-deploy batch 2).

Projects the gateway's in-memory approval state (``tools.approval``) into an
append-only JSONL ledger under /opt/data, so pending approvals are
discoverable across sessions (``GET /v1/approvals``), resolvable by global
request_id, and survive gateway restarts *as records*.

Design dead-lines (batch plan 2026-11-22, user-approved semantics):

- The in-memory queue is the ONLY execution truth. This module never sits
  in the decision chain: it observes, records, and re-checks live state
  before reporting or resolving anything. A projection fault therefore
  degrades discovery, never approval enforcement (faults are logged and
  surfaced via ``degraded()``).
- A record that claims ``pending`` is re-verified against the live queue
  (or the no-notifier ``_pending`` dict) at read time and at resolve time;
  anything not live is reported ``expired`` instead of answerable.
- Decisions are captured from the entry objects themselves
  (``result`` / ``cancelled`` / ``expired``) via ``observe_gateway_settle``
  plus a periodic reconciler, so an answer given on ANY surface (run
  endpoint, /approve, this aggregate endpoint) lands in the ledger.
- Unattended (cron) approvals never enqueue in upstream v0.23.0 -- the
  presence trio is cleared and ``approvals.cron_mode`` (default deny)
  resolves instantly -- so there is nothing to project for them; what this
  layer persists is every approval that genuinely parks waiting for a
  human, plus the no-notifier ``submit_pending`` records.
- Retention (user-approved 2026-11-22): undecided records expire after
  7 days; decided records are purged after 1 year. ``sweep()`` takes
  explicit ``now``/TTL arguments so tests can inject short windows
  without touching the production constants below.

Ledger format: one JSON object per line, an event with a full record
snapshot (``created`` / ``decided`` / ``expired`` / ``withdrawn`` /
``purged``). Folding = last snapshot per request_id wins; ``purged``
removes. Command/description are stored only after the gateway's own
egress redaction (``_redact_approval_command``), mirroring decisions.jsonl
metadata discipline.
"""

import hashlib
import json
import logging
import os
import threading
import time

logger = logging.getLogger("gateway.platforms.approval_projection")

PENDING_TTL_SECONDS = 7 * 86400          # undecided -> expired (user-approved)
DECIDED_RETENTION_SECONDS = 365 * 86400  # decided -> purged (user-approved)
DEFAULT_WAIT_SECONDS = 300               # approvals.timeout upstream default
RECONCILE_INTERVAL_SECONDS = 2.0

_VALID_CHOICES = ("once", "session", "always", "deny")
_TERMINAL = ("answered", "expired", "withdrawn")

_lock = threading.RLock()
_records = {}          # request_id -> record dict (folded ledger state)
_live_entries = {}     # request_id -> _ApprovalEntry ref (queue source only)
_live_pending_keys = set()  # synthetic ids currently present in _pending dict
_started = False
_degraded = False
_thread = None


def _ledger_path():
    return os.environ.get(
        "HERMES_APPROVAL_LEDGER_PATH", "/opt/data/approvals/approval_ledger.jsonl")


def _now():
    return time.time()


def _redact(text):
    if not isinstance(text, str) or not text:
        return text if isinstance(text, str) else ""
    try:
        from gateway.run import _redact_approval_command
        return _redact_approval_command(text)
    except Exception:
        return "<redaction unavailable>"


def _choices_for(data):
    smart_denied = bool(data.get("smart_denied"))
    allow_session = bool(data.get("allow_session", True))
    allow_permanent = bool(data.get("allow_permanent", True))
    if smart_denied or not allow_session:
        return ["once", "deny"]
    return ["once", "session", "always", "deny"] if allow_permanent else ["once", "session", "deny"]


# ---------------------------------------------------------------- ledger IO

def _append_event(event, record):
    """Append one event line (fsync). Caller holds _lock. Raises on IO error."""
    path = _ledger_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    line = json.dumps({"v": 1, "event": event, "ts": _now(), "record": record},
                      ensure_ascii=False)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")
        fh.flush()
        os.fsync(fh.fileno())


def _load_ledger():
    """Fold the JSONL ledger into _records. Returns True on clean load."""
    path = _ledger_path()
    loaded = {}
    if not os.path.exists(path):
        _records.update(loaded)
        return True
    ok = True
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                rec = obj["record"]
                rid = rec["request_id"]
                if obj["event"] == "purged":
                    loaded.pop(rid, None)
                else:
                    loaded[rid] = rec
            except Exception:
                ok = False
                logger.warning("approval ledger: skipping corrupt line", exc_info=True)
    _records.update(loaded)
    return ok


def _emit(event, record):
    """Persist + fold one event; on IO failure mark degraded, never raise."""
    global _degraded
    record = dict(record)
    try:
        _append_event(event, record)
    except Exception:
        _degraded = True
        logger.warning("approval ledger append failed (%s)", event, exc_info=True)
    if event == "purged":
        _records.pop(record["request_id"], None)
    else:
        _records[record["request_id"]] = record


def degraded():
    return _degraded


# ---------------------------------------------------------------- live views

def _queue_snapshot():
    """{session_key: [(entry, data_copy), ...]} read under the approval lock."""
    try:
        from tools import approval as _approval
    except Exception:
        return {}
    snap = {}
    with _approval._lock:
        for session_key, queue in _approval._gateway_queues.items():
            snap[session_key] = [(entry, dict(entry.data)) for entry in queue]
    return snap


def _pending_snapshot():
    """{session_key: approval_dict} for the no-notifier submit_pending store."""
    try:
        from tools import approval as _approval
    except Exception:
        return {}
    with _approval._lock:
        return {k: dict(v) for k, v in _approval._pending.items()}


def _live_queue_ids():
    ids = set()
    for items in _queue_snapshot().values():
        for _entry, data in items:
            if data.get("request_id"):
                ids.add(data["request_id"])
    return ids


def _synthetic_pending_id(session_key, approval):
    raw = "|".join([session_key or "",
                    str(approval.get("command", "")),
                    str(approval.get("pattern_key", ""))])
    return "pending-" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]


# ---------------------------------------------------------------- outcomes

def _settle_record(record, status, *, choice=None, reason=None, cause=None):
    record = dict(record)
    record["status"] = status
    record["decided_at"] = _now()
    if choice is not None:
        record["choice"] = choice
    if reason is not None:
        record["decision_reason"] = reason
    if cause is not None:
        record["status_cause"] = cause
    event = {"answered": "decided", "expired": "expired",
             "withdrawn": "withdrawn"}[status]
    _emit(event, record)
    return record


def _capture_outcome(request_id, entry, settle_reason=None):
    """Fold one queue entry's final state into its record (idempotent)."""
    with _lock:
        record = _records.get(request_id)
        if record is None or record.get("status") in _TERMINAL:
            return
        result = getattr(entry, "result", None)
        if result:
            _settle_record(record, "answered", choice=result,
                           reason=getattr(entry, "reason", None))
        elif getattr(entry, "expired", False) or settle_reason == "timeout":
            _settle_record(record, "expired", cause="timeout")
        elif getattr(entry, "cancelled", None) or settle_reason in (
                "session_closed", "interrupted", "notify_failed"):
            _settle_record(record, "withdrawn",
                           cause=getattr(entry, "cancelled", None) or settle_reason)
        elif settle_reason == "resolved":
            # Settled as resolved but no choice captured on the entry ref we
            # hold (coalesced leader answered a follower): treat as answered
            # with unknown choice rather than leaving a phantom pending.
            _settle_record(record, "answered", choice=None)
        else:
            _settle_record(record, "expired", cause="queue_lost")


def _make_observer(request_id, entry):
    def _observer(reason):
        try:
            _capture_outcome(request_id, entry, reason)
        except Exception:
            logger.debug("approval projection observer failed", exc_info=True)
    return _observer


# ---------------------------------------------------------------- reconcile

def _reconcile_once():
    from tools import approval as _approval

    snap = _queue_snapshot()
    live_ids = set()
    for session_key, items in snap.items():
        for entry, data in items:
            rid = data.get("request_id")
            if not rid:
                continue
            live_ids.add(rid)
            with _lock:
                is_new_ref = rid not in _live_entries
                if is_new_ref:
                    _live_entries[rid] = entry
                record = _records.get(rid)
                if record is None:
                    created = _now()
                    timeout_s = data.get("timeout_s") or DEFAULT_WAIT_SECONDS
                    record = {
                        "request_id": rid,
                        "session_key": session_key,
                        "run_id": None,
                        "session_id": None,
                        "source": "queue",
                        "answerable": True,
                        "command": _redact(data.get("command", "")),
                        "description": _redact(data.get("description", "")),
                        "pattern_keys": list(data.get("pattern_keys")
                                             or [data.get("pattern_key", "")]),
                        "choices": _choices_for(data),
                        "status": "pending",
                        "choice": None,
                        "created_at": created,
                        "expires_at": created + timeout_s,
                        "decided_at": None,
                    }
                    _emit("created", record)
            if is_new_ref:
                try:
                    _approval.observe_gateway_settle(
                        session_key, rid, _make_observer(rid, entry))
                except Exception:
                    logger.debug("observe_gateway_settle failed", exc_info=True)

    # Entries that left the queue: capture outcome from the held ref.
    with _lock:
        gone = [rid for rid in _live_entries if rid not in live_ids]
    for rid in gone:
        entry = _live_entries.pop(rid, None)
        if entry is not None:
            _capture_outcome(rid, entry)

    # No-notifier submit_pending store.
    pending = _pending_snapshot()
    current_keys = set()
    for session_key, approval in pending.items():
        rid = _synthetic_pending_id(session_key, approval)
        current_keys.add(rid)
        with _lock:
            if rid not in _records:
                created = _now()
                record = {
                    "request_id": rid,
                    "session_key": session_key,
                    "run_id": None,
                    "session_id": None,
                    "source": "pending",
                    "answerable": False,
                    "command": _redact(approval.get("command", "")),
                    "description": _redact(approval.get("description", "")),
                    "pattern_keys": list(approval.get("pattern_keys")
                                         or [approval.get("pattern_key", "")]),
                    "choices": _choices_for(approval),
                    "status": "pending",
                    "choice": None,
                    "created_at": created,
                    "expires_at": created + PENDING_TTL_SECONDS,
                    "decided_at": None,
                }
                _emit("created", record)
    with _lock:
        vanished = [rid for rid in _live_pending_keys if rid not in current_keys]
        _live_pending_keys.clear()
        _live_pending_keys.update(current_keys)
    for rid in vanished:
        with _lock:
            record = _records.get(rid)
            if record is not None and record.get("status") == "pending":
                _settle_record(record, "expired", cause="pending_cleared")

    sweep()


def sweep(now=None, pending_ttl_seconds=PENDING_TTL_SECONDS,
          decided_retention_seconds=DECIDED_RETENTION_SECONDS):
    """Expire stale pendings and purge old decisions.

    Explicit ``now``/TTL parameters are the test-injection surface: a test
    record with a short TTL (or an old created_at) is expired by calling
    sweep with matching arguments -- production constants stay untouched.
    Returns {"expired": n, "purged": n}.
    """
    now = _now() if now is None else now
    expired = purged = 0
    # Never expire a record whose waiter is still live, whatever its age:
    # the live queue outranks the ledger (projection is not the truth).
    try:
        live_ids = _live_queue_ids()
        live_ids.update(_synthetic_pending_id(sk, ap)
                        for sk, ap in _pending_snapshot().items())
    except Exception:
        live_ids = set()
    with _lock:
        for record in list(_records.values()):
            if record.get("status") == "pending":
                if record.get("request_id") in live_ids:
                    continue
                if now - float(record.get("created_at") or now) > pending_ttl_seconds:
                    _settle_record(record, "expired", cause="ttl")
                    expired += 1
            elif record.get("status") in _TERMINAL:
                decided_at = record.get("decided_at")
                if decided_at and now - float(decided_at) > decided_retention_seconds:
                    _emit("purged", record)
                    purged += 1
    if purged:
        _compact()
    return {"expired": expired, "purged": purged}


def _compact():
    """Rewrite the ledger with one snapshot line per surviving record."""
    path = _ledger_path()
    tmp = path + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            for record in _records.values():
                event = {"pending": "created", "answered": "decided",
                         "expired": "expired", "withdrawn": "withdrawn"}[
                             record.get("status", "pending")]
                fh.write(json.dumps({"v": 1, "event": event, "ts": _now(),
                                     "record": record}, ensure_ascii=False) + "\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except Exception:
        global _degraded
        _degraded = True
        logger.warning("approval ledger compaction failed", exc_info=True)


# ---------------------------------------------------------------- public API

def start():
    """Idempotent: load ledger, expire orphaned pendings, launch reconciler."""
    global _started, _thread
    with _lock:
        if _started:
            return True
        _started = True
    try:
        with _lock:
            _load_ledger()
            # Records still "pending" from a previous process can never be
            # answered (their waiter died with that process; the run was
            # interrupted upstream). Keep them queryable, mark them expired.
            for record in list(_records.values()):
                if record.get("status") == "pending":
                    _settle_record(record, "expired", cause="process_restart")
    except Exception:
        global _degraded
        _degraded = True
        logger.warning("approval projection start failed", exc_info=True)

    def _loop():
        while True:
            try:
                _reconcile_once()
            except Exception:
                logger.debug("approval reconcile failed", exc_info=True)
            time.sleep(RECONCILE_INTERVAL_SECONDS)

    _thread = threading.Thread(target=_loop, name="approval-projection",
                               daemon=True)
    _thread.start()
    return True


def _public(record):
    return {
        "request_id": record.get("request_id"),
        "session_key": record.get("session_key"),
        "run_id": record.get("run_id"),
        "session_id": record.get("session_id"),
        "source": record.get("source"),
        "answerable": bool(record.get("answerable")),
        "command": record.get("command", ""),
        "description": record.get("description", ""),
        "pattern_keys": record.get("pattern_keys", []),
        "choices": record.get("choices", []),
        "status": record.get("status"),
        "choice": record.get("choice"),
        "created_at": record.get("created_at"),
        "expires_at": record.get("expires_at"),
        "decided_at": record.get("decided_at"),
        "status_cause": record.get("status_cause"),
    }


def list_approvals():
    """All records, newest first; pendings re-verified against live state."""
    start()
    live_queue = _live_queue_ids()
    pending = _pending_snapshot()
    live_pending = {_synthetic_pending_id(sk, ap) for sk, ap in pending.items()}
    out = []
    with _lock:
        records = list(_records.values())
    for record in records:
        if record.get("status") == "pending":
            rid = record["request_id"]
            live = rid in live_queue if record.get("source") == "queue" \
                else rid in live_pending
            if not live:
                entry = _live_entries.get(rid)
                if entry is not None:
                    _capture_outcome(rid, entry)
                else:
                    with _lock:
                        current = _records.get(rid)
                        if current is not None and current.get("status") == "pending":
                            _settle_record(current, "expired", cause="queue_lost")
                with _lock:
                    record = _records.get(rid, record)
        out.append(_public(record))
    out.sort(key=lambda r: float(r.get("created_at") or 0), reverse=True)
    return out


def resolve_approval(request_id, choice, reason=None):
    """Resolve one pending approval by global request_id.

    Returns (http_status, payload). The live queue is re-checked before
    answering (never trust the disk state), and the actual resolution goes
    through the upstream resolve path -- the run resumes from there.
    """
    start()
    if choice not in _VALID_CHOICES:
        return 400, {"error": "invalid approval choice", "code": "invalid_approval_choice"}
    with _lock:
        record = _records.get(request_id)
    if record is None:
        return 404, {"error": "approval not found", "code": "approval_not_found"}
    if record.get("status") in _TERMINAL:
        return 409, {"error": "approval already decided", "code": "approval_already_decided",
                     "status": record.get("status"), "choice": record.get("choice")}
    if record.get("source") != "queue" or not record.get("answerable"):
        return 409, {"error": "approval is not answerable (no live waiter)",
                     "code": "approval_not_answerable"}
    if request_id not in _live_queue_ids():
        entry = _live_entries.get(request_id)
        if entry is not None:
            _capture_outcome(request_id, entry)
        return 409, {"error": "approval no longer pending", "code": "approval_not_pending"}
    from tools.approval import resolve_gateway_approval
    resolved = resolve_gateway_approval(
        record["session_key"], choice, request_id=request_id, reason=reason)
    if resolved <= 0:
        return 409, {"error": "approval no longer pending", "code": "approval_not_pending"}
    entry = _live_entries.get(request_id)
    if entry is not None:
        _capture_outcome(request_id, entry, "resolved")
    return 200, {"object": "hermes.approval_response", "request_id": request_id,
                 "choice": choice, "resolved": resolved}
