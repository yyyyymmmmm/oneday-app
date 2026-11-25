"""Durable ``/v1/runs`` admission, status, events, and control handlers."""

import asyncio
import contextvars
import functools
import hashlib
import json
import logging
import os
import threading
import time
import uuid
from collections import deque
from contextlib import suppress
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Tuple

try:
    from aiohttp import web
except ImportError:
    web = None  # type: ignore[assignment]
try:
    from aiohttp.web_request import RequestKey
except ImportError:
    # Separate block: aiohttp < 3.14 lacks RequestKey, and a shared except
    # would reset the already-imported ``web`` to None (500 on POST /v1/runs).
    RequestKey = None  # type: ignore[assignment,misc]

from gateway.platforms.api_server_room_grants import _json_error, _room_grant_error_response
from gateway.turn_executor import _UnboundedThreadExecutor
from gateway.platforms.api_server_run_idempotency import TERMINAL_STATUSES


logger = logging.getLogger("gateway.platforms.api_server")

# Executor-thread lifetime for API-server agent turns (#116535). The handler-side
# ``_inflight_agent_runs`` count in api_server.py drops in the handler's ``finally`` when the
# handler task is cancelled (disconnect/shutdown) while the executor thread behind
# ``run_in_executor`` keeps running -- so the shutdown close gate cannot rely on it. This
# module-level count is taken on the submitting thread before ``run_in_executor`` and released
# in the worker thread's own ``finally``, which also keeps it visible past ``adapters.clear()``.
_API_WORKER_LOCK = threading.Lock()
_API_WORKER_LIVE = 0
# API-server agent turns and cron fires run on their own executor, as Desktop and messaging turns
# do (``GatewayRunner._get_executor``). asyncio's default pool is ``min(32, cpu_count + 4)`` threads
# shared with every ``asyncio.to_thread`` SessionDB read in the session handlers, so once live
# turns filled it each /api/sessions read queued behind a whole turn (#144362). Turn concurrency is
# bounded where it is refused: ``gateway.api_server.max_concurrent_runs`` (429 past the cap).
# Created on first use and retired at adapter disconnect (``_close_run_state``), so its parked
# threads do not outlive the adapter that used them; the loop's default executor this replaced
# went away with its loop the same way.
_API_TURN_EXECUTOR: _UnboundedThreadExecutor | None = None
_API_TURN_EXECUTOR_LOCK = threading.Lock()


# Local patch (hermes-deploy 1.20.0): runtime receipt state machine for
# agent self-reactions (design: receipt-runtime-design-20261124.md). The
# receipt on a tool-using turn is issued by the runtime, not the model:
# the run event callback's tool.started hook opens the machine (👀), a
# 2-second timer swaps in 🤔 on long turns, and the terminal hook in
# _execute_run._finish settles it (✅ completed / ❌ failed; cancelled and
# interrupted runs keep their last badge). A social fallback judge covers
# pure-conversation turns the model itself left unreacted. All writes use
# the read-first guarded idiom shared with the reaction endpoint, the
# tool handler and the terminal audit; counters land in state_meta under
# receipt_rt:<YYYY-MM-DD>:<event> (CST).
_RECEIPT_LOCK = threading.Lock()
_RECEIPT_EYES = "\U0001F440"      # 👀 received
_RECEIPT_THINKING = "\U0001F914"  # 🤔 long turn, still working
_RECEIPT_DONE = "\u2705"          # ✅ terminal: completed
_RECEIPT_FAILED = "\u274C"        # ❌ terminal: failed
_RECEIPT_THINKING_DELAY = 2.0     # OpenFang's received -> thinking threshold
_RECEIPT_JUDGE_TIMEOUT = 15.0
_RECEIPT_JUDGE_LATE_WINDOW = 30.0


def api_turn_executor() -> _UnboundedThreadExecutor:
    """The executor that runs API-server agent turns and cron fires (never the loop's default)."""
    global _API_TURN_EXECUTOR
    with _API_TURN_EXECUTOR_LOCK:
        if _API_TURN_EXECUTOR is None:
            _API_TURN_EXECUTOR = _UnboundedThreadExecutor(thread_name_prefix="hermes-api-turn")
        return _API_TURN_EXECUTOR


def retire_api_turn_executor() -> _UnboundedThreadExecutor | None:
    """Shut the API turn executor down without waiting and return it (None if never used).

    Parked workers exit now; a worker still inside a turn finishes it, releases its
    ``api_worker_live_count`` share as before, and exits instead of parking. A later submit gets
    a fresh executor, so another adapter still serving keeps working.
    """
    global _API_TURN_EXECUTOR
    with _API_TURN_EXECUTOR_LOCK:
        executor, _API_TURN_EXECUTOR = _API_TURN_EXECUTOR, None
    if executor is not None:
        executor.shutdown(wait=False)
    return executor


def api_worker_live_count() -> int:
    """Executor threads still inside an API-server agent turn (``_run_agent`` and ``/v1/runs``)."""
    with _API_WORKER_LOCK:
        return _API_WORKER_LIVE


async def on_turn_executor(fn, /, *args, **kwargs):
    """``asyncio.to_thread`` (context copied the same way) on the API turn executor."""
    call = functools.partial(contextvars.copy_context().run, fn, *args, **kwargs)
    return await asyncio.get_running_loop().run_in_executor(api_turn_executor(), call)


def _submit_api_worker(loop, fn):
    """``loop.run_in_executor(api_turn_executor(), fn)`` with the worker-lifetime count held for the submission.

    Increment on the submitting (handler) thread so the count is live before the worker can
    exit; decrement in the worker thread's own ``finally`` so handler cancellation cannot drop
    it early. When submission itself fails (executor shut down, or no thread can be started
    -> RuntimeError) the worker never runs, so the count is released here instead — a leaked
    count would make the shutdown close gate skip the SessionDB close for the process lifetime.
    """
    global _API_WORKER_LIVE
    with _API_WORKER_LOCK:
        _API_WORKER_LIVE += 1

    def _counted():
        try:
            return fn()
        finally:
            global _API_WORKER_LIVE
            with _API_WORKER_LOCK:
                _API_WORKER_LIVE -= 1

    try:
        return loop.run_in_executor(api_turn_executor(), _counted)
    except BaseException:
        with _API_WORKER_LOCK:
            _API_WORKER_LIVE -= 1
        raise
_ROOM_RETENTION_REQUEST_KEY = (
    RequestKey("hermes.room_run_retention_until", float) if RequestKey is not None
    else "hermes.room_run_retention_until")
# Forwarded subagent lifecycle fields; free-text ones are secret-redacted.
_SUBAGENT_EVENT_KEYS = (
    "goal", "task_count", "task_index", "subagent_id", "child_session_id", "delegation_id", "parent_id",
    "depth", "model", "tool_count", "status", "summary", "duration_seconds", "input_tokens",
    "output_tokens", "reasoning_tokens", "api_calls", "cost_usd", "files_read", "files_written",
    "output_tail")
_SUBAGENT_TEXT_KEYS = ("goal", "summary", "output_tail")
# Terminal usage payload: (wire key, agent attribute), in wire order. Cache reads ride along so a
# cost poller does not book them as full-price input (#102101).
_USAGE_FIELDS = (
    ("input_tokens", "session_prompt_tokens"), ("output_tokens", "session_completion_tokens"),
    ("total_tokens", "session_total_tokens"), ("cache_read_tokens", "session_cache_read_tokens"),
    ("cache_write_tokens", "session_cache_write_tokens"))
# Tool-progress event -> SSE payload fields (tool_name, preview, kwargs); key order is wire format.
def _call_id(kw: dict[str, Any]) -> dict[str, Any]:
    return {"tool_call_id": kw["tool_call_id"]} if kw.get("tool_call_id") else {}


_FIXED_EVENT_FIELDS = {
    "tool.started": lambda tool, preview, kw: {"tool": tool, "preview": preview, **_call_id(kw)},
    "tool.completed": lambda tool, preview, kw: {
        "tool": tool, "duration": round(kw.get("duration", 0), 3), "error": kw.get("is_error", False),
        **_call_id(kw)},
    "reasoning.available": lambda tool, preview, kw: {"text": preview or ""}}
_TOOL_COMPLETED_PREVIEW_MAX_CHARS = 500


def _tool_completed_preview(result: Any, redact_sensitive_text: Callable[..., str]) -> str:
    """Bounded, secret-redacted result summary for the public run stream — redacted BEFORE
    truncation so a cut never leaves a secret's prefix on the wire."""
    if result is None:
        return ""
    text = result if isinstance(result, str) else json.dumps(result, ensure_ascii=False, default=str)
    preview = redact_sensitive_text(text, force=True)
    limit = _TOOL_COMPLETED_PREVIEW_MAX_CHARS
    return preview if len(preview) <= limit else preview[: limit - 3] + "..."


_RUN_STREAM_SUBSCRIBER_OVERFLOW = object()
_RUN_STREAM_WRITE_TIMEOUT = 5.0


class _RunStream:
    """Sequence and retain one run's events while fanning out to SSE clients."""

    BACKLOG_LIMIT = 1000
    SUBSCRIBER_QUEUE_LIMIT = 256

    def __init__(self) -> None:
        self.subscribers: set[asyncio.Queue] = set()
        self.backlog: deque[tuple[int, Optional[dict[str, Any]]]] = deque(
            maxlen=self.BACKLOG_LIMIT
        )
        self.next_seq = 0
        self.terminal = False

    def put_nowait(self, event: Optional[dict[str, Any]]) -> None:
        if self.terminal:
            return
        seq = self.next_seq
        self.next_seq += 1
        self.backlog.append((seq, event))
        if event is None:
            self.terminal = True
        for queue in list(self.subscribers):
            try:
                queue.put_nowait((seq, event))
            except asyncio.QueueFull:
                self.detach(queue)
                while not queue.empty():
                    queue.get_nowait()
                queue.put_nowait((seq, _RUN_STREAM_SUBSCRIBER_OVERFLOW))

    def attach(
        self, last_seq: int = -1
    ) -> tuple[asyncio.Queue, list[tuple[int, Optional[dict[str, Any]]]]]:
        replay = [(seq, event) for seq, event in self.backlog if seq > last_seq]
        # Headroom for events produced while the replay is still being written.
        queue: asyncio.Queue = asyncio.Queue(maxsize=self.SUBSCRIBER_QUEUE_LIMIT + len(replay))
        self.subscribers.add(queue)
        return queue, replay

    def detach(self, queue: asyncio.Queue) -> None:
        self.subscribers.discard(queue)


def _remember_room_retention(request: web.Request, claims: dict[str, Any]) -> None:
    value = float(claims.get("status_expires_at") or claims.get("expires_at") or 0)
    try:
        request[_ROOM_RETENTION_REQUEST_KEY] = value
    except (AttributeError, TypeError):
        request._hermes_room_run_retention_until = value


def _room_retention_until(request: web.Request) -> float:
    try:
        value = request.get(_ROOM_RETENTION_REQUEST_KEY, 0)
    except AttributeError:
        value = getattr(request, "_hermes_room_run_retention_until", 0)
    return max(0.0, float(value or 0))


def _run_event(run_id: str, name: str, **fields: Any) -> dict[str, Any]:
    """Build one SSE event payload (key order is part of the wire format)."""
    return {"event": name, "run_id": run_id, "timestamp": time.time(), **fields}


def terminal_run_status(result: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    """Map a ``run_conversation`` result to its terminal run status and the wire fields every
    terminal event/status carries. An interrupted turn is ``cancelled``; a turn that ended
    without finishing (``failed``, ``partial``, or ``completed=False`` such as the iteration
    budget) is ``failed``, so ``completed: true`` never rides next to ``partial: true``."""
    interrupted = bool(result.get("interrupted"))
    finished = (
        not interrupted and not result.get("failed") and not result.get("partial")
        and result.get("completed") is not False
    )
    status = "cancelled" if interrupted else "completed" if finished else "failed"
    fields: dict[str, Any] = {
        "completed": finished, "partial": bool(result.get("partial")), "interrupted": interrupted,
    }
    if not finished and result.get("turn_exit_reason"):
        fields["turn_exit_reason"] = str(result["turn_exit_reason"])
    if result.get("pending_steer"):
        # Undelivered steer text rides on every terminal event/status for client replay.
        fields["pending_steer"] = result["pending_steer"]
    return status, fields


def _run_not_found(_openai_error, run_id: str) -> web.Response:
    return _json_error(_openai_error, f"Run not found: {run_id}", code="run_not_found", status=404)


def _uses_room_run_auth(self, request: web.Request) -> bool:
    return request.path.endswith("/v1/runs") and bool(self._room_grant_token(request))


def _initialize_run_state(self, *, store_factory) -> None:
    """Initialize adapter-owned durable and live ``/v1/runs`` state."""
    self._run_idempotency_store = store_factory()
    self._run_owner_pid = os.getpid()
    try:
        from gateway.status import get_process_start_time
        self._run_owner_started = int(get_process_start_time(self._run_owner_pid) or 0)
    except Exception:
        self._run_owner_started = 0
    # All keyed by run_id: SSE fanout streams (+creation time for the TTL sweep), live
    # agent/task refs for cooperative stop (the executor thread may outlive the request,
    # hence the separate stopping set), pollable statuses, and approval session keys
    # (approval core resolves by session key, clients by run_id).
    self._run_idempotency_ids: set[str] = set()
    self._stopping_run_ids: set[str] = set()
    self._shutdown_interrupted_run_ids: set[str] = set()
    self._run_shutdown_requested_at: Optional[float] = None
    # Streaming run id -> its canonical admission id, held while that request observes the turn.
    self._run_admission_aliases: dict[str, str] = {}
    (
        self._run_owners, self._run_streams, self._run_streams_created, self._active_run_agents,
        self._active_run_tasks, self._run_statuses, self._run_approval_sessions,
    ) = ({} for _ in range(7))
    # Local patch (hermes-deploy 1.20.0): per-run receipt state machine
    # entries, keyed by run_id (see the receipt block at module level).
    # The 1.8.0-1.16.0 _run_tool_use / _run_first_tool_at tables are
    # retired with the terminal audit's retraction case: the runtime now
    # owns the working turn's reaction slot end to end, so the audit no
    # longer needs to know which tools a run used or when its first tool
    # call landed.
    self._run_receipt_state: dict[str, dict] = {}


def _http_routes(self) -> list[tuple[str, str, Any]]:
    return [
        ("POST", "/v1/runs", self._handle_runs), ("GET", "/v1/runs", self._handle_list_runs),
        ("GET", "/v1/runs/{run_id}", self._handle_get_run),
        ("GET", "/v1/runs/{run_id}/events", self._handle_run_events),
        ("POST", "/v1/runs/{run_id}/approval", self._handle_run_approval),
        ("POST", "/v1/runs/{run_id}/clarify", self._handle_run_clarify),
        ("POST", "/v1/runs/{run_id}/steer", self._handle_steer_run),
        ("POST", "/v1/runs/{run_id}/resolve-unknown", self._handle_resolve_unknown_run),
        ("POST", "/v1/runs/{run_id}/stop", self._handle_stop_run)]


def _list_terminal_runs(self, scope: str, limit: int) -> list[dict[str, Any]]:
    """Recent terminal runs recorded under ``scope`` in the durable
    idempotency store, newest first (local patch, hermes-deploy 1.7.0).

    Status-only projection for notification/monitoring consumers: the
    stored status_json also carries the run output, which is content
    and never leaves through this list -- only lifecycle fields are
    projected. Reads go through the store's own connection under its
    lock, so no second handle races the WAL writer.
    """
    store = getattr(self, "_run_idempotency_store", None)
    if store is None:
        return []
    conn = getattr(store, "_conn", None)
    if conn is None:
        return []
    lock = getattr(store, "_lock", None)

    def _query() -> list[dict[str, Any]]:
        rows = conn.execute(
            "SELECT run_id, status_json FROM run_idempotency "
            "WHERE scope=? ORDER BY updated_at DESC LIMIT 200",
            (scope,)).fetchall()
        out: list[dict[str, Any]] = []
        for run_id, status_json in rows:
            try:
                status = json.loads(status_json)
            except Exception:
                continue
            if status.get("status") not in TERMINAL_STATUSES:
                continue
            out.append({
                "run_id": run_id,
                "session_id": status.get("session_id"),
                "status": status.get("status"),
                "completed": bool(status.get("completed")),
                "partial": bool(status.get("partial")),
                "interrupted": bool(status.get("interrupted")),
                "model": status.get("model"),
                "created_at": status.get("created_at"),
                "updated_at": status.get("updated_at"),
            })
            if len(out) >= limit:
                break
        return out

    if lock is not None:
        with lock:
            return _query()
    return _query()


async def _handle_list_runs(self, request: web.Request, *, _api_server) -> web.Response:
    """GET /v1/runs -- recent terminal runs in the caller's scope.

    Local patch (hermes-deploy 1.7.0, demand-ledger 162/163 server gaps
    G1/G3): the run source for the notification stream. The companion
    overview bridge polls this list and turns terminal states into
    in-app notification entries (completed -> task_completed, failed
    -> run_failed). Auth and scope follow the per-run status door
    exactly: a caller only ever sees runs admitted under its own
    idempotency scope.
    """
    auth_err = self._check_run_auth(request, permission="status")
    if auth_err:
        return auth_err
    try:
        limit = int(request.query.get("limit", "50"))
    except Exception:
        limit = 50
    limit = max(1, min(limit, 100))
    scope = self._run_idempotency_scope(request)
    data = await asyncio.to_thread(_list_terminal_runs, self, scope, limit)
    return web.json_response({"object": "list", "data": data})


def _idempotency_capabilities(self, *, store_type) -> dict[str, Any]:
    return {
        "supported": True,
        "durable": self._run_idempotency_store.durable,
        "retention_seconds": store_type.RETENTION_SECONDS,
        # Local patch (hermes-deploy 1.5.0 client-message-id, 2026-11-23):
        # POST /v1/runs also accepts the body's client_message_id as the
        # idempotency key when no Idempotency-Key header is present (see
        # _client_message_id_key); advertised here so clients can probe it.
        "client_message_id": True,
        # Local patch (hermes-deploy 1.7.0, 2026-11-23): GET /v1/runs lists
        # recent terminal runs in the caller's own scope -- the run source
        # for the notification stream (demand-ledger 162/163 server gaps
        # G1/G3); see _handle_list_runs.
        "terminal_list": True}


# --- Run activity registry (hermes-deploy 1.23.0) --------------------
#
# The live half of the hub's activity mechanism: every tool.started
# on a run records (tool, preview) here -- the same event the App's
# capsule phrase is derived from. When the run's terminal report
# reaches the ledger without a summary of its own, the OneDay
# gateway's report handler pops the last activity and derives the
# settled "verb + object" phrase server-side (oneday_ledger_lib.
# derive_activity_summary), so the task row and the capsule never
# carry two different wordings of the same step. Entries are popped
# at terminal settle and by the report handler; a size cap keeps
# abandoned runs from accumulating.

_run_last_activity: dict = {}
_run_activity_lock = threading.Lock()
_RUN_ACTIVITY_CAP = 1024


def _note_run_activity(run_id: str, tool: str, preview) -> None:
    if not run_id or not tool:
        return
    with _run_activity_lock:
        _run_last_activity[run_id] = {
            "tool": tool, "preview": preview or "", "at": time.time()}
        if len(_run_last_activity) > 64:
            # Abandoned runs (terminal report never filed) age out
            # after an hour; the cap below is the hard backstop.
            cutoff = time.time() - 3600
            for rid in [r for r, a in _run_last_activity.items()
                        if a.get("at", 0) < cutoff]:
                _run_last_activity.pop(rid, None)
        while len(_run_last_activity) > _RUN_ACTIVITY_CAP:
            _run_last_activity.pop(next(iter(_run_last_activity)),
                                   None)


def _pop_run_activity(run_id: str):
    with _run_activity_lock:
        return _run_last_activity.pop(run_id, None)


def _self_reactions_gate_on() -> bool:
    """The deployment gate (``display.agent_self_reactions``), read the way
    the per-turn reminder reads it: any failure means off, never an error."""
    try:
        from tools import desktop_ui
        return bool(desktop_ui.user_enabled("agent_self_reactions", default=False))
    except Exception:
        return False


def _receipt_count(event: str) -> None:
    """Increment one receipt-runtime counter in ``state_meta`` (best effort).

    Keys are ``receipt_rt:<YYYY-MM-DD>:<event>`` with the date in CST, so
    the miss rate is a plain SQL read away (design section 5). Counting
    failures are swallowed: observability must never break a turn."""
    try:
        from datetime import datetime, timedelta, timezone
        day = datetime.now(timezone(timedelta(hours=8))).strftime("%Y-%m-%d")
        from hermes_state_registry import acquire, release_or_close
        db = acquire()
        if db is None:
            return
        try:
            key = f"receipt_rt:{day}:{event}"
            raw = db.get_meta(key)
            try:
                value = int(raw) if raw is not None else 0
            except (TypeError, ValueError):
                value = 0
            db.set_meta(key, str(value + 1))
        finally:
            with suppress(Exception):
                release_or_close(db)
    except Exception:
        pass


def _write_reaction_guarded(session_id: str, row_id: int, emoji: str) -> str:
    """Read-first guarded write of the agent reaction slot.

    Returns "written" / "already" / "failed". The same idiom as the
    reaction endpoint and the tool handler: read the current reactions
    first and skip the write when the same emoji already stands (the
    store toggles a reaction OFF when it is re-sent), replace a different
    one, and treat a None result (row not in this session) as failure."""
    try:
        from hermes_state_registry import acquire, release_or_close
        db = acquire()
        if db is None:
            return "failed"
        try:
            existing = db.get_message_reactions(session_id, int(row_id))
            for entry in existing:
                if entry.get("author") == "agent":
                    if entry.get("emoji") == emoji:
                        return "already"
                    break
            written = db.set_message_reaction(
                session_id, int(row_id), emoji, author="agent")
            return "written" if written is not None else "failed"
        finally:
            with suppress(Exception):
                release_or_close(db)
    except Exception:
        return "failed"


def _receipt_write_for(st: dict, emoji: str, ok_event: Optional[str]) -> bool:
    """Guarded write for one state entry, with a single same-emoji retry
    (the Agent Swarm shape: a failed receipt write is retried once, then
    counted and logged -- it never breaks the run)."""
    result = _write_reaction_guarded(st["session_id"], st["row_id"], emoji)
    if result == "failed":
        result = _write_reaction_guarded(st["session_id"], st["row_id"], emoji)
    if result == "failed":
        _receipt_count("transition_failed")
        logger.warning(
            "[api_server] receipt transition failed session=%s row=%s emoji=%s",
            st.get("session_id"), st.get("row_id"), emoji)
        return False
    if ok_event:
        _receipt_count(ok_event)
    return True


def _receipt_transition(self, run_id: str, emoji: str, ok_event: Optional[str], *,
                        expect_stage: Optional[str] = None,
                        next_stage: Optional[str] = None) -> bool:
    """One state-machine transition under the receipt lock (stage check,
    guarded write, stage advance). Never raises."""
    with _RECEIPT_LOCK:
        st = (getattr(self, "_run_receipt_state", None) or {}).get(run_id)
        if st is None:
            return False
        if expect_stage is not None and st.get("stage") != expect_stage:
            return False
        if not _receipt_write_for(st, emoji, ok_event):
            return False
        if next_stage is not None:
            st["stage"] = next_stage
        return True


def _receipt_begin(self, run_id: str, session_id: Optional[str], loop) -> None:
    """Open the receipt state machine for a tool-using run.

    Called from the run event callback on the run's first non-reaction
    ``tool.started``. Only the ``_execute_run`` funnels pass a session_id;
    without one (or with the gate closed) the machine stays inert and the
    turn behaves exactly as before this patch. If the model already
    placed a reaction on the target row, the machine adopts the slot
    without overwriting it and still settles it at the terminal hook."""
    try:
        if not session_id:
            return
        table = getattr(self, "_run_receipt_state", None)
        if table is None:
            return
        with _RECEIPT_LOCK:
            if run_id in table:
                return
        if not _self_reactions_gate_on():
            return
        row_id = None
        adopted = False
        try:
            from hermes_state_registry import acquire, release_or_close
            db = acquire()
            if db is None:
                return
            try:
                row_id = db.latest_message_row_id(session_id, role="user", offset=0)
                if row_id is not None:
                    for entry in db.get_message_reactions(session_id, int(row_id)):
                        if entry.get("author") == "agent":
                            adopted = True
                            break
            finally:
                with suppress(Exception):
                    release_or_close(db)
        except Exception:
            return
        if row_id is None:
            return
        st = {
            "session_id": session_id, "row_id": int(row_id),
            "stage": "received", "gate_on": True, "adopted": adopted,
            "timer": None, "since": time.time(),
        }
        with _RECEIPT_LOCK:
            if run_id in table:
                return
            table[run_id] = st
        if adopted:
            _receipt_count("received_adopted")
        else:
            _receipt_write_for(st, _RECEIPT_EYES, "received_written")
        with suppress(Exception):
            loop.call_soon_threadsafe(_arm_receipt_timer, self, run_id, loop)
    except Exception:
        logger.warning("[api_server] receipt begin failed run=%s", run_id, exc_info=True)


def _arm_receipt_timer(self, run_id: str, loop) -> None:
    """Arm the 2-second thinking timer (runs on the run's event loop)."""
    with _RECEIPT_LOCK:
        st = (getattr(self, "_run_receipt_state", None) or {}).get(run_id)
        if st is None or st.get("stage") != "received":
            return
        st["timer"] = loop.call_later(
            _RECEIPT_THINKING_DELAY, _receipt_thinking_due, self, run_id)


def _receipt_thinking_due(self, run_id: str) -> None:
    """Timer callback: a run still in ``received`` after the delay is a
    long turn -- swap 👀 for 🤔 (OpenFang's lifecycle)."""
    _receipt_transition(
        self, run_id, _RECEIPT_THINKING, "thinking_written",
        expect_stage="received", next_stage="thinking")


def _receipt_terminal(self, run_id: str, status: str) -> Optional[dict]:
    """Settle the state machine at a terminal status: ✅ on completed,
    ❌ on failed. Returns the popped entry, or None when this run never
    entered the machine. Cancelled/interrupted runs never reach this
    hook -- their last badge stands."""
    table = getattr(self, "_run_receipt_state", None)
    if table is None:
        return None
    with _RECEIPT_LOCK:
        st = table.pop(run_id, None)
    if st is None:
        return None
    timer = st.get("timer")
    if timer is not None:
        with suppress(Exception):
            timer.cancel()
    if status == "completed":
        _receipt_write_for(st, _RECEIPT_DONE, "done_written")
    elif status == "failed":
        _receipt_write_for(st, _RECEIPT_FAILED, "failed_written")
    return st


def _receipt_retire(self, run_id: str) -> None:
    """Drop a state entry without migrating (the ``_retire_live_run``
    backstop for runs that never hit the terminal hook)."""
    table = getattr(self, "_run_receipt_state", None)
    if table is None:
        return
    with _RECEIPT_LOCK:
        st = table.pop(run_id, None)
    if st is not None:
        timer = st.get("timer")
        if timer is not None:
            with suppress(Exception):
                timer.cancel()


def _audit_self_reaction(self, run_id: str, session_id: str) -> Optional[dict]:
    """Terminal audit for the write-at-call self-reaction (simplified in
    hermes-deploy 1.20.0).

    The reaction itself was written by the tool handler the moment
    ``react_to_message`` executed (see react_to_message_tool.py); this
    hook attaches and retracts nothing. It pops the turn's write record
    from ``self_reaction_pending`` and returns it -- the social fallback
    judge consumes the record (a record means the model posted, so the
    judge stands down). A record left behind by a run that died before
    finishing is discarded WITHOUT touching its badge (the freshness
    check below): the badge was written inside its own turn and stands.
    That independence is the point of writing at call time -- the
    1.8.0-1.16.0 terminal attach that used to live here lost exactly
    those badges (guard discards in 1.15.0; a mid-turn gateway restart
    on 2026-11-24 that left a registered 🎉 forever unattached).

    The former retraction case (a non-receipt reaction written while
    the turn still looked like conversation, after which the turn used
    other tools anyway) is retired: in a working turn the runtime
    receipt state machine owns the slot and settles it at the terminal
    hook, so there is nothing left to retract. All exceptions are
    swallowed: an audit must never break terminal bookkeeping.
    """
    def _drop(reason: str, **fields: Any) -> None:
        logger.warning(
            "[api_server] self-reaction audit for run %s: reason=%s %s",
            run_id, reason,
            " ".join(f"{k}={v!r}" for k, v in fields.items()))

    try:
        from gateway.platforms import self_reaction_pending as pending
        entry = pending.pop(session_id)
        if entry is None:
            return None
        created = (getattr(self, "_run_streams_created", None) or {}).get(run_id)
        entry_at = float(entry.get("at") or 0)
        if created is not None:
            if entry_at < float(created) - 5:
                _drop("stale_write_record", entry_at=entry_at, run_created=float(created))
                return None
        elif time.time() - entry_at > 600:
            _drop("stale_write_record", entry_at=entry_at, run_created=None)
            return None
        return entry
    except Exception:
        logger.warning("[api_server] self-reaction audit failed for run %s", run_id, exc_info=True)
        return None


_RECEIPT_JUDGE_PROMPT = (
    "You are a reaction judge for a chat app. Decide whether the assistant "
    "should attach exactly one emoji reaction to the user's latest message, "
    "the way a friend would in a chat thread: sharing feelings, good or bad "
    "news, a joke, or a plan they're pleased about usually deserves one; a "
    "bare question or plain information gets none. For a hard or vulnerable "
    "message pick a caring emoji, never a celebratory one. Answer with "
    "exactly one emoji from this set: 👍 ❤️ 🤔 😂 🎉 👀 — or the single "
    "word none. Nothing else."
)


def _receipt_message_text(message: dict) -> str:
    """Plain text of a stored message row (string content, or the text
    parts of a multimodal content list); anything else reads as empty."""
    content = message.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for part in content:
            if isinstance(part, dict) and isinstance(part.get("text"), str):
                parts.append(part["text"])
            elif isinstance(part, str):
                parts.append(part)
        return "\n".join(parts)
    return ""


def _maybe_social_judge(self, run, audit_record, *, had_receipt: bool) -> None:
    """Social fallback judge dispatch (terminal, completed runs only).

    Scope: a pure-conversation turn (no receipt state entry) on a real
    session-history delivery, gate open. The denominator counter lands
    here, once per in-scope turn; when the model itself posted (audit
    record present) the judge stands down without a second opinion. The
    judgement runs on a daemon thread and never blocks terminal
    bookkeeping. All exceptions are swallowed."""
    try:
        session_id = run.session_id
        if not session_id or not run.session_history_delivery or had_receipt:
            return
        if not _self_reactions_gate_on():
            return
        _receipt_count("chat_turn_completed")
        if audit_record is not None:
            return
        threading.Thread(
            target=_social_judge_worker, args=(session_id, time.time()),
            name=f"receipt-judge-{run.run_id}", daemon=True).start()
    except Exception:
        logger.warning("[api_server] social judge dispatch failed", exc_info=True)


def _social_judge_worker(session_id: str, finished_at: float) -> None:
    """One short aux call; on a positive verdict, one guarded write.

    The verdict is restricted to the recommended palette (main-line
    ruling 2026-11-24; the model's own picks on the main path stay
    unrestricted). The write re-reads the slot first and never
    overwrites: if the model's own late write landed meanwhile, the
    judge stands down (``judge_skipped_occupied``). A verdict that would
    land more than 30 seconds after the turn finished is dropped --
    a badge appearing long after the reply was read helps no one."""
    try:
        from gateway.platforms import self_reaction_pending as pending
        palette = set(pending.EMOJI_PALETTE)
        target_row_id = None
        rows: list = []
        try:
            from hermes_state_registry import acquire, release_or_close
            db = acquire()
            if db is None:
                _receipt_count("judge_failed")
                return
            try:
                target_row_id = db.latest_message_row_id(
                    session_id, role="user", offset=0)
                if target_row_id is None:
                    _receipt_count("judge_failed")
                    return
                rows = db.get_messages(session_id, latest=True, limit=60)
            finally:
                with suppress(Exception):
                    release_or_close(db)
        except Exception:
            _receipt_count("judge_failed")
            return
        trigger_text = ""
        prior: list[str] = []
        for row in rows:
            row_id = row.get("id")
            if not isinstance(row_id, int) or row_id > int(target_row_id):
                continue
            role = row.get("role")
            if role not in ("user", "assistant"):
                continue
            text = _receipt_message_text(row).strip()
            if not text:
                continue
            if row_id == int(target_row_id):
                trigger_text = text[:1000]
            else:
                prior.append(f"{role}: {text[:300]}")
        if not trigger_text:
            _receipt_count("judge_none")
            return
        user_content = "\n".join(prior[-6:] + [f"user (latest): {trigger_text}"])
        try:
            from agent.auxiliary_client import call_llm, extract_content_or_reasoning
            # Revision 1 (hermes-deploy 1.20.0, application-stage finding):
            # this worker runs on a daemon thread, outside the per-turn
            # secret scope; on the multiplexed gateway, resolving the
            # provider credential inside call_llm then raises
            # UnscopedSecretError and every verdict dies as judge_failed.
            # Install the profile's own scope for the call, the shape the
            # kanban watcher dispatcher uses for its background work.
            # Best effort: where the scope machinery is unavailable the
            # call proceeds as before (single-profile deployments need
            # no scope).
            _scope_token = None
            try:
                from agent.secret_scope import (
                    build_profile_secret_scope, set_secret_scope)
                from hermes_constants import get_hermes_home
                _home = get_hermes_home()
                _scope_token = set_secret_scope(
                    build_profile_secret_scope(_home),
                    profile_home=str(_home))
            except Exception:
                _scope_token = None
            try:
                response = call_llm(
                    task="reaction_judge",
                    messages=[
                        {"role": "system", "content": _RECEIPT_JUDGE_PROMPT},
                        {"role": "user", "content": user_content},
                    ],
                    temperature=0, max_tokens=16,
                    timeout=_RECEIPT_JUDGE_TIMEOUT,
                    reasoning_config={"enabled": False})
            finally:
                if _scope_token is not None:
                    with suppress(Exception):
                        from agent.secret_scope import reset_secret_scope
                        reset_secret_scope(_scope_token)
            verdict = extract_content_or_reasoning(response).strip()
        except Exception:
            _receipt_count("judge_failed")
            logger.warning(
                "[api_server] social judge call failed session=%s",
                session_id, exc_info=True)
            return
        if verdict not in palette:
            # "none", multi-emoji strings, prose -- anything that is not
            # exactly one palette emoji counts as a none verdict.
            _receipt_count("judge_none")
            return
        if time.time() - finished_at > _RECEIPT_JUDGE_LATE_WINDOW:
            _receipt_count("judge_failed")
            logger.warning(
                "[api_server] social judge verdict too late, dropped session=%s",
                session_id)
            return
        written = None
        try:
            from hermes_state_registry import acquire, release_or_close
            db = acquire()
            if db is None:
                _receipt_count("judge_failed")
                return
            try:
                existing = db.get_message_reactions(session_id, int(target_row_id))
                if any(r.get("author") == "agent" for r in existing):
                    _receipt_count("judge_skipped_occupied")
                    return
                written = db.set_message_reaction(
                    session_id, int(target_row_id), verdict, author="agent")
            finally:
                with suppress(Exception):
                    release_or_close(db)
        except Exception:
            _receipt_count("judge_failed")
            return
        if written is None:
            _receipt_count("judge_failed")
            return
        _receipt_count("judge_written")
    except Exception:
        logger.warning(
            "[api_server] social judge failed session=%s", session_id, exc_info=True)


def _attach_options(self, run_id: str, session_id: str) -> None:
    """Attach this run's pending option card, if any (hermes-deploy 1.12.0).

    Called synchronously from ``_execute_run``'s finish path BEFORE the
    terminal status is published, and only for ``completed`` runs, so a
    client reading the settled turn already sees the card under the
    turn's final assistant message. Every guard fails closed (no card):
    no pending entry; an entry registered by a different run; a payload
    that no longer validates (the store is never trusted -- the same
    validate_options the tool handler used runs again here); or no
    assistant text row to land on. Unlike self-reactions there is NO
    tool-use filter: asking the user to pick a direction after doing
    work is this feature's primary use case. All exceptions are
    swallowed: a card must never break terminal bookkeeping.

    Timing fix (hermes-deploy 2.3.1): under real /v1/runs traffic the
    turn's terminal assistant text row is committed by the delivery
    commit, which lands AFTER this finish path runs -- at attach time
    the DB holds only the empty-text tool-call row, which
    ``latest_message_row_id`` (require_text) skips, so the first lookup
    found no row and the card was silently dropped (flip verification
    2026-11-25, runs run_3369ebe3 / run_f37fdc18). The first attempt
    stays synchronous (row already present = pre-2.3.1 behavior); on
    "no row yet" a daemon thread retries for a few seconds until the
    delivery row lands. A registered card that still cannot land is
    NEVER silent: the drop paths log a warning carrying the session
    and run ids.
    """
    try:
        import threading
        import time

        from gateway.platforms import options_pending as pending

        def _try_once() -> str:
            """One attach attempt: 'attached' | 'no_row' | 'rejected'."""
            try:
                from hermes_state_registry import acquire, release_or_close
                db = acquire()
                if db is None:
                    return "no_row"
                try:
                    row_id = db.latest_message_row_id(
                        session_id, role="assistant", offset=0)
                    if row_id is None:
                        return "no_row"
                    return "attached" if pending.attach_options(
                        db, session_id, int(row_id), options) else "rejected"
                finally:
                    with suppress(Exception):
                        release_or_close(db)
            except Exception:
                return "no_row"

        entries = pending.list_pending(session_id)
        entry = next((item for item in entries
                      if (item.get("run_key") or "") == run_id
                      or (item.get("run_key") or "").endswith(":" + run_id)), None)
        if entry is None:
            # Session-scoped handler keys do not always contain the bare
            # run id. Preserve the established freshness bind, but only
            # by choosing the newest candidate: turns in one session are
            # lease-serialized, so that entry belongs to this run.
            created_at = None
            statuses = getattr(self, "_run_statuses", None)
            if isinstance(statuses, dict):
                created_at = (statuses.get(run_id) or {}).get("created_at")
            candidates = [item for item in entries
                          if created_at and item.get("at")
                          and float(item["at"]) >= float(created_at) - 1.0]
            if candidates:
                entry = max(candidates, key=lambda item: float(item["at"]))
        if entry is None:
            # Any entries that predate this run are leftovers from an
            # interrupted turn; remove only those identified stale cards.
            created_at = None
            statuses = getattr(self, "_run_statuses", None)
            if isinstance(statuses, dict):
                created_at = (statuses.get(run_id) or {}).get("created_at")
            if created_at:
                for stale in entries:
                    if stale.get("at") and float(stale["at"]) < float(created_at) - 1.0:
                        pending.drop(session_id, stale.get("card_id", ""))
            return
        # Run binding (hermes-deploy 2.3.1 rev1): the tool handler
        # registers run_key = HERMES_SESSION_KEY
        # ("agent:main:api_server:dm:<...>"), never the bare run_id --
        # an equality guard here dropped every real-traffic card (the
        # same break the self-reaction attach fixed in 1.15.0 by
        # abandoning run_key equality). Bind instead by self-verified
        # facts: an exact or key-suffix match, or freshness -- the
        # entry was registered after this run was created (turns in
        # one session are lease-serialized, so a live entry at finish
        # belongs to this run; an entry predating the run is a dead
        # run's leftover and is dropped).
        run_key = entry.get("run_key") or ""
        card_id = entry.get("card_id") or ""
        bound = run_key == run_id or run_key.endswith(":" + run_id)
        if not bound:
            created_at = None
            statuses = getattr(self, "_run_statuses", None)
            if isinstance(statuses, dict):
                created_at = (statuses.get(run_id) or {}).get("created_at")
            registered_at = entry.get("at")
            bound = bool(
                created_at and registered_at
                and float(registered_at) >= float(created_at) - 1.0)
        if not bound:
            logger.warning(
                "[api_server] options card dropped: pending run_key mismatch "
                "session=%s run=%s pending_run=%s",
                session_id, run_id, entry.get("run_key"))
            pending.drop(session_id, entry.get("card_id", ""))
            return
        options = pending.validate_options(entry.get("options"))
        if options is None:
            logger.warning(
                "[api_server] options card dropped: pending payload failed "
                "validation session=%s run=%s", session_id, run_id)
            pending.drop(session_id, entry.get("card_id", ""))
            return
        run_key = entry.get("run_key") or ""

        def _settle_once(current: dict[str, Any]) -> str:
            """Attach while holding the pending-list lock."""
            return _try_once()

        # The store removes the entry only after a successful metadata
        # write, under the same lock used by pending-list readers.
        outcome = pending.settle(session_id, card_id, _settle_once)[1]
        if outcome is False:
            return
        if outcome == "attached":
            return
        if outcome == "rejected":
            logger.warning(
                "[api_server] options card NOT attached: target row outside "
                "visible lineage session=%s run=%s", session_id, run_id)
            return

        def _retry_until_delivery_row() -> None:
            deadline = time.monotonic() + 5.0
            while time.monotonic() < deadline:
                time.sleep(0.25)
                outcome = pending.settle(session_id, card_id, _settle_once)[1]
                if outcome == "attached":
                    return
                if outcome == "rejected":
                    break
            logger.warning(
                "[api_server] options card NOT attached: no assistant text "
                "row landed session=%s run=%s", session_id, run_id)
            pending.drop(session_id, card_id)

        threading.Thread(
            target=_retry_until_delivery_row,
            name=f"options-attach-{run_id}", daemon=True).start()
    except Exception:
        logger.debug("[api_server] options attach failed for run %s", run_id, exc_info=True)


def _close_run_state(self) -> None:
    retire_api_turn_executor()
    try:
        if getattr(self, "_run_idempotency_store", None) is not None:
            self._run_idempotency_store.close()
    except Exception:
        logger.debug("Failed to close run idempotency store for %s", self.name, exc_info=True)


def _set_run_status(self, run_id: str, status: str, **fields: Any) -> dict[str, Any]:
    """Update pollable run status without exposing private agent objects."""
    now = time.time()
    current = self._run_statuses.get(run_id, {})
    previous_status = str(current.get("status") or "")
    field_names = set(fields)
    current.update({"object": "hermes.run", "run_id": run_id, "status": status, "updated_at": now})
    current.setdefault("created_at", fields.pop("created_at", now))
    current.update(fields)
    shutdown_requested_at = getattr(self, "_run_shutdown_requested_at", None)
    if shutdown_requested_at is not None and status not in TERMINAL_STATUSES:
        current.setdefault("shutdown_requested_at", shutdown_requested_at)
    if status != "waiting_for_approval":
        current.pop("approval", None)
    self._run_statuses[run_id] = current
    should_persist = (
        status != previous_status
        or status in TERMINAL_STATUSES
        or bool(field_names & {
            "output", "error", "usage", "pending_steer", "session_id", "shutdown_requested_at"}))
    if run_id in self._run_idempotency_ids and should_persist:
        try:
            self._run_idempotency_store.update_status(run_id, current)
        except Exception:
            logger.exception("[api_server] failed to persist idempotent run status %s", run_id)
    return current


def _mark_shutdown_interrupted_runs(self, run_ids) -> None:
    """Publish the shutdown outcome before cooperative interruption can race teardown."""
    for run_id in run_ids:
        self._shutdown_interrupted_run_ids.add(run_id)
        self._set_run_status(
            run_id,
            "interrupted",
            error="Gateway shutdown interrupted the run.",
            last_event="run.interrupted",
        )


def _mark_shutdown_requested(self) -> int:
    """Persist when gateway shutdown began without changing the run state vocabulary."""
    shutdown_requested_at = getattr(self, "_run_shutdown_requested_at", None)
    if shutdown_requested_at is None:
        shutdown_requested_at = time.time()
        self._run_shutdown_requested_at = shutdown_requested_at
    marked = 0
    for run_id, current in list(self._run_statuses.items()):
        if current.get("status") in TERMINAL_STATUSES or "shutdown_requested_at" in current:
            continue
        self._set_run_status(
            run_id, str(current.get("status") or "running"),
            shutdown_requested_at=shutdown_requested_at)
        marked += 1
    return marked


def _make_run_event_callback(self, run_id: str, loop: asyncio.AbstractEventLoop, *, _api_server, session_id: Optional[str] = None):
    """Return a callback that pushes structured events to the run SSE queue."""
    redact_sensitive_text = _api_server.redact_sensitive_text

    def _push(event: dict[str, Any]) -> None:
        self._set_run_status(
            run_id, self._run_statuses.get(run_id, {}).get("status", "running"), last_event=event.get("event"))
        q = self._run_streams.get(run_id)
        if q is not None:
            with suppress(Exception):
                loop.call_soon_threadsafe(q.put_nowait, event)

    def _callback(event_type: str, tool_name: str | None = None, preview: str | None = None, args=None, **kwargs):
        # Local patch (hermes-deploy 1.8.0): the self-reaction tool is an internal
        # side channel -- its events never reach the run stream (client process
        # rows must not show the call), and the call itself does not count as
        # tool use for the terminal audit below.
        # Local patch (hermes-deploy 1.12.0, rebased onto 1.23.0): the
        # present_options tool is the same kind of internal side channel,
        # so the guard widens to cover it. The widening also keeps it out
        # of the two chains added after 1.12.0: the receipt state machine
        # opens on the first NON-reaction tool call, and the activity
        # registry's last entry feeds the ledger's derived terminal
        # summary -- an internal card presentation must enter neither.
        if tool_name in ("react_to_message", "present_options"):
            return
        if event_type == "tool.started" and tool_name:
            # Local patch (hermes-deploy 1.20.0): the first non-reaction
            # tool call opens the runtime receipt state machine (👀 on
            # the message that triggered this run). session_id reaches
            # this factory only from _execute_run; every other funnel
            # leaves it None and the machine stays inert there.
            _receipt_begin(self, run_id, session_id, loop)
            # Local patch (hermes-deploy 1.23.0): record the step in
            # the run activity registry -- the ledger's terminal
            # settle derives the task row's summary from the last
            # entry when the App's report carries none.
            _note_run_activity(run_id, tool_name, preview)
        # _thinking / subagent.tool / subagent_progress are deliberately dropped (UI noise);
        # lifecycle boundaries must land so clients can observe delegate_task failures.
        fields = _FIXED_EVENT_FIELDS.get(event_type)
        if fields is not None:
            event_fields = fields(tool_name, preview, kwargs)
            if event_type == "tool.completed":
                event_fields["preview"] = _tool_completed_preview(
                    kwargs.get("result"), redact_sensitive_text)
            _push(_run_event(run_id, event_type, **event_fields))
        elif event_type in {"subagent.start", "subagent.complete"}:
            event = _run_event(run_id, event_type)
            if preview is not None:
                event["preview"] = redact_sensitive_text(str(preview), force=True)
            for key in _SUBAGENT_EVENT_KEYS:
                value = kwargs.get(key)
                if value is not None:
                    # Free text may carry child tool output: force secret redaction on this public stream.
                    redact = key in _SUBAGENT_TEXT_KEYS and isinstance(value, str)
                    event[key] = redact_sensitive_text(value, force=True) if redact else value
            _push(event)

    return _callback


# Answering a prompt the run raised is one capability whichever tool asked: approvals
# and clarify share the grant's ``approve`` permission. Acknowledging a lost owner epoch
# ends the run like a stop, so ``/resolve-unknown`` rides the ``stop`` permission.
_ROOM_CONTROL_PERMISSIONS = {
    "/stop": "stop", "/resolve-unknown": "stop", "/approval": "approve", "/clarify": "approve"}


def _room_permission_for(request: web.Request) -> str:
    for suffix, permission in _ROOM_CONTROL_PERMISSIONS.items():
        if request.path.endswith(suffix):
            return permission
    return "status" if request.method == "GET" else "dispatch"


def _run_idempotency_scope(self, request: web.Request, *, _api_server) -> str:
    """Opaque auth/profile namespace; never persist bearer credentials."""
    if self._room_grant_token(request):
        claims = self._room_grant_claims(request, permission=_room_permission_for(request))
        _remember_room_retention(request, claims)
        parts = (claims[k] for k in (
            "room_id", "home_install_id", "authority_gateway_id", "authority_epoch",
            "member_id", "target_install_id", "target_profile"))
    else:
        parts = (_api_server._api_request_profile.get() or "default",
                 self._expected_api_key() or "unauthenticated-test-listener")
    return hashlib.sha256("\0".join(map(str, parts)).encode()).hexdigest()


def _check_run_auth(self, request: web.Request, *, permission: str, _api_server) -> web.Response | None:
    if not self._room_grant_token(request):
        return self._check_auth(request)
    try:
        self._room_grant_claims(request, permission=permission)
    except Exception as exc:
        return _room_grant_error_response(exc, _openai_error=_api_server._openai_error)
    return None


def _owner_alive(owner_pid: int, owner_started: int) -> bool:
    """True when the recorded owner pid still exists and is the same process incarnation."""
    try:
        from gateway.status import _pid_exists, get_process_start_time, start_time_fingerprints_match
        return owner_pid > 0 and bool(_pid_exists(owner_pid)) and (
            not owner_started
            or start_time_fingerprints_match(owner_started, get_process_start_time(owner_pid) or 0))
    except Exception:
        return False


def _durable_run_status(self, request: web.Request, run_id: str) -> dict[str, Any] | None:
    """Hydrate a scoped run status and fail stale owners closed."""
    from gateway.platforms.api_server_authority_runs import run_projection
    canonical = run_projection(self, run_id)
    if canonical is not None:
        # The documented poll shape: the canonical projection decides status/output/usage; the
        # retained run record still names the object, the requested model and the served runtime.
        retained = self._run_statuses.get(run_id) or {}
        return {"object": "hermes.run", **{key: retained[key] for key in ("model", "runtime", "created_at")
                                           if key in retained}, **canonical}
    status = self._run_statuses.get(run_id)
    if status is not None:
        if run_id in self._run_idempotency_ids:
            scope = self._run_idempotency_scope(request)
            self._run_idempotency_store.extend_retention(scope, run_id, _room_retention_until(request))
        return status
    scope = self._run_idempotency_scope(request)
    record = self._run_idempotency_store.status_for_run(
        scope, run_id, retention_until=_room_retention_until(request))
    if record is None:
        return None
    status = dict(record["status"])
    if status.get("status") not in TERMINAL_STATUSES and not _owner_alive(
        int(record.get("owner_pid") or 0), int(record.get("owner_started") or 0)):
        status.update(
            status="interrupted", error="The gateway restarted before this run settled.",
            last_event="run.interrupted", updated_at=time.time())
        self._run_idempotency_store.update_status(run_id, status)
    self._run_statuses[run_id] = status
    self._run_idempotency_ids.add(run_id)
    self._run_owners[run_id] = scope
    return status


def _resolve_conversation_history(
    self, body: dict, raw_input: Any, *, _openai_error
) -> tuple[list[dict[str, str]], Any, Any, web.Response | None]:
    """Return ``(history, instructions, stored_session_id, error)``; precedence:
    ``conversation_history`` > ``previous_response_id`` chain > all-but-last ``input`` messages."""
    instructions = body.get("instructions")
    previous_response_id = body.get("previous_response_id")
    conversation_history: list[dict[str, str]] = []
    raw_history = body.get("conversation_history")
    if raw_history:
        if not isinstance(raw_history, list):
            return [], instructions, None, _json_error(
                _openai_error, "'conversation_history' must be an array of message objects", status=400)
        for i, entry in enumerate(raw_history):
            if not isinstance(entry, dict) or {"role", "content"} - set(entry):
                return [], instructions, None, _json_error(
                    _openai_error, f"conversation_history[{i}] must have 'role' and 'content' fields",
                    status=400)
            conversation_history.append({"role": str(entry["role"]), "content": str(entry["content"])})
        if previous_response_id:
            logger.debug("Both conversation_history and previous_response_id provided; using conversation_history")
    stored_session_id = None
    if not conversation_history and previous_response_id:
        stored = self._current_response_store().get(previous_response_id)
        if stored:
            conversation_history = list(stored.get("conversation_history", []))
            stored_session_id = stored.get("session_id")
            if instructions is None:
                instructions = stored.get("instructions")
    if not conversation_history and isinstance(raw_input, list) and len(raw_input) > 1:
        for msg in raw_input[:-1]:
            if isinstance(msg, dict) and msg.get("role") and msg.get("content"):
                content = msg["content"]
                if isinstance(content, list):  # flatten multi-part content blocks to text
                    content = " ".join(p.get("text", "") for p in content
                                       if isinstance(p, dict) and p.get("type") == "text")
                conversation_history.append({"role": msg["role"], "content": str(content)})
    return conversation_history, instructions, stored_session_id, None


async def _resolve_chained_history(self, body: dict, raw_input: Any, *, _openai_error):
    """``_resolve_conversation_history`` with the chain's live session: a deleted chain moves to
    its next generation (an explicit body ``session_id`` still wins in the caller), and a store
    that cannot answer is the retryable store verdict (``continued_session``). The last item is the
    stored session the chain moved past (``walked_from``), else None."""
    from gateway.platforms.api_server_authority_runs import continued_session
    # Off the loop: a previous_response_id chain reads (and json-decodes) the stored history.
    history, instructions, chain_root, error = await asyncio.to_thread(
        _resolve_conversation_history, self, body, raw_input, _openai_error=_openai_error)
    stored_session_id = chain_root
    if error is None:
        stored_session_id, error = await continued_session(self, chain_root)
    return history, instructions, stored_session_id, error, (
        chain_root if stored_session_id and stored_session_id != chain_root else None)


def _accepted_response(run_id: str, status: str, gateway_session_key, *, replayed: bool) -> web.Response:
    """202 admission response; replays are flagged via ``Idempotency-Replayed``."""
    headers = {"Idempotency-Replayed": "true"} if replayed else {}
    if gateway_session_key:
        headers["X-Hermes-Session-Key"] = gateway_session_key
    return web.json_response(
        {"run_id": run_id, "status": status, "replayed": replayed}, status=202, headers=headers)


def _replay_or_conflict(self, request, outcome, record, gateway_session_key, _openai_error) -> web.Response:
    """409 for a fingerprint conflict, else a 202 replay of the already-admitted run."""
    if outcome == "conflict":
        return _json_error(
            _openai_error, "Idempotency-Key was already used with a different request payload",
            code="idempotency_key_conflict", status=409)
    original_id = str(record["run_id"])
    status = self._durable_run_status(request, original_id) or record["status"]
    return _accepted_response(original_id, status.get("status", "queued"), gateway_session_key, replayed=True)


@dataclass(slots=True)
class _RunLaunch:
    """State for an admitted run's background task; contextvars are captured here
    because the task outlives the request (and its middleware profile scope)."""

    owner: Any
    run_id: str
    queue: _RunStream
    session_id: str
    gateway_session_key: Optional[str]
    declared_selected: bool
    user_message: str
    conversation_history: list[dict[str, str]]
    # #98619: only continuation paths that reload session history may grant wake authority —
    # a previous_response_id continuation consumes its ResponseStore snapshot instead, and a
    # caller-supplied conversation_history is authoritative for the turn; neither consumes a
    # SessionDB delivery row, so both stay default-denied.
    session_history_delivery: bool
    agent_kwargs: dict  # ``_create_agent`` keyword arguments (prompt, model overrides, route, room policy)
    request_profile: Any
    turn_author: Optional[dict[str, Any]] = None  # memory-attribution label only; grants nothing
    admission: Any = None
    walked_from: Optional[str] = None  # the swept stored session the chain moved past (``bind_api_steps``)

    @property
    def approval_session_key(self) -> str:
        # Isolated per run: session ids are conversation scopes, not authorization namespaces.
        return self.run_id

    def put_event(self, event: Optional[dict]) -> None:
        """Enqueue only while this run still owns live transport state."""
        if self.owner._run_streams.get(self.run_id) is self.queue:
            self.queue.put_nowait(event)


def _forget_run(self, run_id: str, *tables) -> None:
    """Drop *run_id* from the given run-keyed dicts/sets, then release its owner stamp."""
    for table in tables:
        (table.discard if isinstance(table, set) else lambda k: table.pop(k, None))(run_id)
    self._release_run_owner_if_forgotten(run_id)


def _retire_live_run(self, run_id: str) -> None:
    """Retire agent/task/approval control state once the executor-backed task is done."""
    # Local patch (hermes-deploy 1.20.0): a retired run's receipt entry
    # is dropped without migrating -- cancelled/interrupted runs keep
    # the last badge the machine wrote.
    _receipt_retire(self, run_id)
    _forget_run(self, run_id, self._active_run_agents, self._active_run_tasks, self._run_approval_sessions,
                self._stopping_run_ids, self._shutdown_interrupted_run_ids)


def _drop_run_transport(self, run_id: str) -> None:
    _forget_run(
        self,
        run_id,
        self._run_streams,
        self._run_streams_created,
    )


async def _resolve_live_session_id(self, session_id: str) -> str:
    """Adopt the live compression-continuation tip for a client-addressed session (#98619):
    a /v1/runs run bound to a pre-rotation id would otherwise load a stale history slice and
    write its turn into the closed parent (CompressionSessionClosedError). Same canonical
    resolution ``/api/sessions/{id}/messages`` reads use; fails open to the original id."""
    db = await self._ensure_session_db_async()
    resolver = getattr(db, "resolve_resume_session_id", None) if db is not None else None
    if not callable(resolver):
        return session_id
    try:
        resolved = await asyncio.to_thread(resolver, session_id)
        return str(resolved) if resolved else session_id
    except Exception:
        logger.debug("/v1/runs live-session resolve failed for %s", session_id, exc_info=True)
        return session_id


async def run_internal_session_turn(self, *, session_id: str, text: str, profile: str,
                                notification_category: str = "result", _api_server) -> None:
    """Run one background wake turn against a raw session id IN-PROCESS (no HTTP, no API key).

    The HTTP wake self-post cannot serve a multiplexed *served* profile: ``/p/<profile>/`` on
    the shared listener authenticates with that profile's own ``API_SERVER_KEY`` — which a
    route-only profile legitimately does not have — while an unprefixed self-post would resume
    the session in the DEFAULT profile's store. ``gateway.wake`` therefore runs the turn here,
    inside the owner profile's runtime scope (the session DB, model resolution and tool policy
    all follow the ambient scope), with ``profile`` naming the profile the caller proved owns
    the session — never derived here, so a missing proof cannot silently become the default.
    Raises on failure so the caller can rewind its cursor: a draining gateway fails at once
    (the HTTP self-post's 503) while a saturated concurrent-run cap is retried with the same
    backoff the HTTP self-post uses for a 429.
    """
    from gateway.wake import _RETRY_DELAYS_SECONDS
    profile = (profile or "").strip()
    if not profile:
        raise ValueError("run_internal_session_turn requires the owning profile")
    token = _api_server._api_request_profile.set(profile)
    attempts = 1 + len(_RETRY_DELAYS_SECONDS)
    last_err: Optional[BaseException] = None
    try:
        for attempt in range(attempts):
            if attempt:
                await asyncio.sleep(_RETRY_DELAYS_SECONDS[attempt - 1])
            if self._draining_response() is not None:
                raise RuntimeError(
                    f"internal wake refused for session {session_id}: the gateway is draining")
            # Transient: the cap clears on its own, exactly as the HTTP self-post's 429 does.
            if self._concurrency_limited_response() is not None:
                last_err = RuntimeError(
                    "internal wake deferred: the API server is at its concurrent-run cap")
                logger.warning("%s; attempt %d/%d", last_err, attempt + 1, attempts)
                continue
            # #98619/#13437: adopt the live continuation tip first, the same canonical
            # resolution the HTTP self-post consumes — a compressed origin must be woken on the
            # transcript that is actually live, never the retired parent slice.
            resolved = await _resolve_live_session_id(self, session_id)
            session, err = await self._get_existing_session_or_404(resolved)
            if err is not None or not session:
                raise RuntimeError(
                    f"internal wake target session {resolved!r} is not in the active profile store")
            history = await self._conversation_history_for_session(resolved)
            # Same route resolution as the HTTP self-post (/v1/chat/completions): a model_routes
            # alias for the virtual model applies to the wake turn too.
            route, overrides, err = self._select_request_route(
                {"model": self._model_name}, session_id=resolved, gateway_session_key=None,
                model_alias=self._model_name)
            if err is not None:
                raise RuntimeError(f"internal wake route conflict for session {resolved!r}")
            await self._run_agent(
                user_message=text, conversation_history=history, session_id=resolved,
                gateway_session_key=None, **overrides, route=route, requested_runtime={},
                route_source="global", session_history_delivery="1",
                notification_category=notification_category,
            )
            return
        raise RuntimeError(
            f"internal wake gave up for session {session_id} after {attempts} attempts: {last_err}")
    finally:
        if token is not None:
            _api_server._api_request_profile.reset(token)


def _client_message_id_key(body, _openai_error) -> tuple:
    """Local patch (hermes-deploy 1.5.0 client-message-id, 2026-11-23): resolve the
    request body's ``client_message_id`` as an idempotency key source, for clients
    that key dedup on a persisted per-message id (OneDay outbox, checklist 154)
    instead of the ``Idempotency-Key`` header.

    Returns ``(key, error_response)``. An absent/null field is ``("", None)`` —
    the request is simply unkeyed, exactly like a missing header. A present but
    malformed value (non-string, or not 1-255 visible ASCII once stripped) is a
    400 ``invalid_client_message_id``: silently ignoring it would let the caller
    believe dedup is armed when it is not. A whitespace-only string strips to
    "" and is treated as absent, mirroring the header path."""
    if not isinstance(body, dict):
        return "", None
    value = body.get("client_message_id")
    if value is None:
        return "", None
    if not isinstance(value, str):
        return "", _json_error(
            _openai_error, "client_message_id must be a string",
            code="invalid_client_message_id", status=400)
    key = value.strip()
    if not key:
        return "", None
    if len(key) > 255 or any(ord(ch) < 33 or ord(ch) > 126 for ch in key):
        return "", _json_error(
            _openai_error, "client_message_id must be 1-255 visible ASCII characters",
            code="invalid_client_message_id", status=400)
    return key, None


def _run_idempotency_identity(self, request, body, gateway_session_key, idempotency_key) -> tuple:
    """``(principal scope, request fingerprint)`` for a keyed POST /v1/runs; ``("", "")`` unkeyed."""
    if not idempotency_key:
        return "", ""
    return self._run_idempotency_scope(request), hashlib.sha256(json.dumps(
        {"body": body, "gateway_session_key": gateway_session_key or ""},
        sort_keys=True, separators=(",", ":"), ensure_ascii=False,
    ).encode()).hexdigest()


def _run_user_message(raw_input, _openai_error) -> tuple:
    """POST /v1/runs ``input`` -> ``(user_message, error_response_or_None)``."""
    if not raw_input:
        return None, _json_error(_openai_error, "Missing 'input' field", status=400)
    if isinstance(raw_input, str):
        user_message = raw_input
    else:
        user_message = raw_input[-1].get("content", "") if isinstance(raw_input, list) else ""
    if not user_message:
        return None, _json_error(_openai_error, "No user message found in input", status=400)
    return user_message, None


async def _admit_run_to_authority(
    self, launch, run_id, session_history_delivery, _declared_selected,
    idempotency_scope, idempotency_key, _openai_error,
) -> Optional[web.Response]:
    """Admit a /v1/runs turn to the session authority FIFO -> ``None``, or the refusal."""
    from gateway.platforms.api_server_authority_runs import run_admission, store_error_response
    from gateway.session_api_turn import admit_api_turn_async
    from gateway.session_contract import SessionRef
    from hermes_state_runtime import RuntimeStoreError
    try:
        with self._profile_scope(launch.request_profile):
            launch.admission = await admit_api_turn_async(self, user_message=launch.user_message,
                conversation_history=launch.conversation_history, active_run_id=run_id,
                run_owner_scope=self._run_owners[run_id],
                turn_author=launch.turn_author,
                history_from_session=session_history_delivery,
                session_history_delivery='1' if session_history_delivery else '',
                bind_declared_conversation=_declared_selected, walked_from=launch.walked_from,
                **launch.agent_kwargs)
    except Exception as exc:  # health: allow BLE001 -- answered below; a committed admission is kept
        # A storage failure after the admission committed (a later media-release write) still
        # owns that run: forgetting it would let a keyed retry admit the same work twice.
        owned = None if isinstance(exc, RuntimeStoreError) else await asyncio.to_thread(run_admission, self, run_id)
        if owned is not None:
            launch.admission = (owned[0], SessionRef(owned[0].profile_id, owned[1]['target_session_id']), owned[1])
            return None
        # A refused admission owns no run: drop every reservation so an exact
        # retry is refused again instead of replaying a run nobody executes.
        _forget_run(
            self, run_id, self._run_streams, self._run_streams_created, self._run_approval_sessions,
            self._run_statuses, self._run_owners, self._run_idempotency_ids)
        if idempotency_key:
            self._run_idempotency_store.forget(idempotency_scope, idempotency_key)
        return store_error_response(_openai_error, exc)
    return None


async def _handle_runs(self, request: web.Request, *, _api_server) -> web.Response:
    """POST /v1/runs — start an agent run, return run_id immediately."""
    _openai_error = _api_server._openai_error
    # Long-term memory scope header (see chat_completions for details).
    gateway_session_key, key_err = self._parse_session_key_header(request)
    if key_err is not None:
        return key_err
    try:
        body = await request.json()
    except Exception:
        return _json_error(_openai_error, "Invalid JSON", status=400)
    body, room_error = await self._normalize_room_dispatch(request, body)
    if room_error is not None:
        return room_error
    room_dispatch, room_execution_policy = (
        v if isinstance(v, dict) else None for v in (
            (body.get("hosted_room_dispatch"), body.get("_room_execution_policy"))
            if isinstance(body, dict) else (None, None)))
    idempotency_key = request.headers.get("Idempotency-Key", "").strip()
    if len(idempotency_key) > 255 or any(ord(ch) < 33 or ord(ch) > 126 for ch in idempotency_key):
        return _json_error(
            _openai_error, "Idempotency-Key must be 1-255 visible ASCII characters",
            code="invalid_idempotency_key", status=400)
    if not idempotency_key:
        # Local patch (hermes-deploy 1.5.0 client-message-id, 2026-11-23): with no
        # header key, fall back to the body's client_message_id. The resolved key
        # flows through the same scope/fingerprint/store machinery below, so the
        # replay (202 + Idempotency-Replayed) and conflict (409
        # idempotency_key_conflict) semantics are identical whichever source
        # supplied the key. The header keeps precedence when both are present;
        # the body still fingerprints whole, so a retry that changes
        # client_message_id under a fixed header conflicts like any other
        # payload change.
        idempotency_key, client_id_error = _client_message_id_key(body, _openai_error)
        if client_id_error is not None:
            return client_id_error
    idempotency_scope, idempotency_fingerprint = _run_idempotency_identity(
        self, request, body, gateway_session_key, idempotency_key)
    raw_input = body.get("input")
    user_message, input_err = _run_user_message(raw_input, _openai_error)
    if input_err is not None:
        return input_err
    try:
        turn_author = _api_server._request_turn_author(body)
    except ValueError as exc:
        return _json_error(_openai_error, str(exc), code="invalid_author", status=400)
    conversation_history, instructions, stored_session_id, history_err, walked_from = await _resolve_chained_history(
        self, body, raw_input, _openai_error=_openai_error)
    if history_err is not None:
        return history_err
    previous_response_id = body.get("previous_response_id")
    session_id = body.get("session_id") or stored_session_id
    route = self._resolve_route(body.get("model"))
    agent_overrides = _api_server._request_agent_overrides(body, virtual_model=self._model_name)
    selection_error = self._request_route_conflict_error(
        session_id=session_id, gateway_session_key=gateway_session_key,
        requested_model=agent_overrides.get("requested_model"),
        requested_provider=agent_overrides.get("requested_provider"), route=route)
    if selection_error:
        return _json_error(_openai_error, selection_error, status=400)
    # A lost-acceptance replay must resolve even while the original run holds the last
    # concurrency slot; this read reserves nothing (the atomic reserve below closes the race).
    if idempotency_key:
        outcome, record = self._run_idempotency_store.lookup(
            idempotency_scope, idempotency_key, idempotency_fingerprint,
            retention_until=_room_retention_until(request))
        if outcome == "conflict" or (outcome == "reused" and record is not None):
            return _replay_or_conflict(self, request, outcome, record, gateway_session_key, _openai_error)
    # Enforce concurrency only for a genuinely new run.
    limited = self._concurrency_limited_response()
    if limited is not None:
        return limited
    run_id = f"run_{uuid.uuid4().hex}"
    self._run_owners[run_id] = self._run_idempotency_scope(request)
    # Same precedence as /v1/responses: body session_id > response chain > X-Hermes-Session-Key
    # conversation > run_id (which would otherwise re-key every affinity surface per run).
    # An explicit or chained session owns its routing key and is never rebound to the header.
    _declared_selected = not session_id and bool(gateway_session_key)
    selected_session_id = session_id or (
        await asyncio.to_thread(self._declared_conversation_session, gateway_session_key)
        if _declared_selected else None)
    # A client-addressed id from before a compression rotation must adopt the live tip (#98619):
    # history loads from it, the turn writes to it, and a detached delivery row persisted to it
    # is what the next same-id run consumes below.
    if selected_session_id:
        selected_session_id = await _resolve_live_session_id(self, str(selected_session_id))
    session_id = selected_session_id or run_id
    # History loads for the session the request actually selected — including one resolved from
    # a declared X-Hermes-Session-Key, whose persisted delivery rows must reach the next
    # same-key run's context (#98619).  previous_response_id continuations keep their
    # ResponseStore snapshot as history (they cannot consume a SessionDB delivery row and are
    # accordingly denied wake capability in _run_agent_sync); the fresh run_id fallback has
    # nothing persisted to load yet.  Wake authority is fixed here, before the load can
    # overwrite ``conversation_history``: a caller-supplied history is authoritative for this
    # turn, never consumes the SessionDB delivery row, and is denied on the same contract.
    session_history_delivery = not previous_response_id and not conversation_history
    if not conversation_history and selected_session_id and not previous_response_id:
        conversation_history = await self._conversation_history_for_session(str(selected_session_id))
    q = self._run_streams[run_id] = _RunStream()
    created_at = self._run_streams_created[run_id] = time.time()
    self._run_approval_sessions[run_id] = run_id  # approval session key (see _RunLaunch)
    initial_status = self._set_run_status(
        run_id, "queued", created_at=created_at, session_id=session_id, model=body.get("model", self._model_name))
    if idempotency_key:
        outcome, record = self._run_idempotency_store.reserve(
            idempotency_scope, idempotency_key, idempotency_fingerprint, run_id, initial_status,
            owner_pid=self._run_owner_pid, owner_started=self._run_owner_started,
            retention_until=_room_retention_until(request))
        if outcome != "created":
            _forget_run(
                self, run_id, self._run_streams, self._run_streams_created, self._run_approval_sessions,
                self._run_statuses, self._run_owners)
            return _replay_or_conflict(self, request, outcome, record, gateway_session_key, _openai_error)
        self._run_idempotency_ids.add(run_id)
    launch = _RunLaunch(
        self, run_id, q, session_id, gateway_session_key, _declared_selected, user_message,
        conversation_history, session_history_delivery,
        agent_kwargs=dict(
            ephemeral_system_prompt=instructions, session_id=session_id, gateway_session_key=gateway_session_key,
            route=route, room_dispatch=room_dispatch, room_execution_policy=room_execution_policy,
            **{k: agent_overrides.get(k) for k in ("requested_model", "requested_provider", "model_options")}),
        request_profile=_api_server._api_request_profile.get(),
        turn_author=turn_author, walked_from=walked_from if session_id == stored_session_id else None)
    # A canonical Bot Chat that a Desktop holds live is that Desktop's to run: executing here would
    # be a second writer beside its lease (#114959). The owner's mailbox takes the turn and its
    # receipt drives this run's status, so `peer run` keeps its run_id and `peer status` still works.
    # Under session authority the same call admits the turn to the Bot Chat's own FIFO, which is
    # why it is decided BEFORE ``admit_api_turn`` would bind the chat as an API conversation.
    admitted = await self._admit_to_live_bot_chat(session_id, user_message, turn_author) if selected_session_id else None
    _retarget_to_delivered_chat(self, launch, admitted)
    if admitted is None and getattr(self.gateway_runner, 'session_authority', None) is not None:
        refused = await _admit_run_to_authority(
            self, launch, run_id, session_history_delivery, _declared_selected,
            idempotency_scope, idempotency_key, _openai_error)
        if refused is not None:
            return refused
    self._activate_admitted_request()
    if admitted is not None:
        task = self._active_run_tasks[run_id] = asyncio.create_task(
            _execute_run_via_live_owner(self, launch, *admitted, _api_server=_api_server))
    else:
        task = self._active_run_tasks[run_id] = asyncio.create_task(_execute_run(self, launch, _api_server=_api_server))
    with suppress(TypeError):
        self._background_tasks.add(task)  # tracked for shutdown drain
    if hasattr(task, "add_done_callback"):
        task.add_done_callback(self._background_tasks.discard)
    return _accepted_response(run_id, "started", gateway_session_key, replayed=False)


def _retarget_to_delivered_chat(self, launch: _RunLaunch, admitted) -> None:
    """The owner moved an API-held "Bot Chat" title aside and the turn landed in the local chat it
    minted (MSG-21): the run record (and its idempotency replay) names that chat, not the old row."""
    delivered = admitted[1].get("session_id") if admitted is not None else None
    if delivered and delivered != launch.session_id:
        launch.session_id = delivered
        self._set_run_status(launch.run_id, "queued", session_id=delivered)


def _run_usage(agent) -> dict[str, int]:
    """Terminal ``usage`` payload from the agent's session counters; a missing or non-numeric
    counter (test doubles, agents without cache accounting) reads as ``0``."""
    usage = {}
    for key, attr in _USAGE_FIELDS:
        value = getattr(agent, attr, 0)
        usage[key] = int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else 0
    return usage


def _served_runtime(agent) -> dict[str, str]:
    """The ``{provider, model}`` pair that actually served the turn. After a ``fallback_providers``
    switch the agent keeps the fallback runtime until the NEXT turn restores the primary, so when
    ``run_conversation()`` returns these attributes name the served pair — the run record's
    ``model`` field only echoes the request (#102101). Non-string attributes read as ``""``."""
    pair = {}
    for key in ("provider", "model"):
        value = getattr(agent, key, "")
        pair[key] = value if isinstance(value, str) else ""
    return pair


def _run_agent_sync(self, run: _RunLaunch, agent, approval_notify, *, _api_server):
    """Executor-thread body of one run; returns ``(result, usage, served_runtime)``."""
    from gateway.session_context import clear_session_vars
    from gateway.hosted_room_execution_policy import (
        RoomExecutionPolicy, bind_room_execution_policy, reset_room_execution_policy)
    # No eager slash-worker pre-warm: slash.exec spawns one on demand (its error path already relies on that
    # respawn to recover from a dead worker). Each worker child runs its own MCP discovery (#61891), so
    # pre-warming one per session forks the full stdio MCP fleet — ~20 OS processes per retained session on
    # a config with a few stdio servers — even for sessions that never run a worker-routed command. Sessions
    # held by a live transport are never reaped, so with the desktop app open for days those fleets
    # accumulate until the OS refuses new process spawns.
    from tools.approval import register_gateway_notify, unregister_gateway_notify
    from tools.approval_context import reset_current_session_key, set_current_session_key
    session_id = run.session_id
    effective_task_id = session_id or run.run_id
    # (token, reset) pairs unwound in the finally block; bound only once each step succeeds.
    resets: list[tuple[Any, Callable]] = []
    with self._profile_scope(run.request_profile):
        try:
            # Contextvars, not process env: concurrent runs must not share identity.
            resets.append((set_current_session_key(run.approval_session_key), reset_current_session_key))
            # chat_id carries the raw session id like _run_agent() does; without it
            # tools.async_delegation sees no HERMES_SESSION_CHAT_ID and forces delegations sync.
            session_tokens = self._bind_api_server_session(
                chat_id=session_id or "", session_key=run.approval_session_key, session_id=session_id or "",
                profile=run.request_profile or "",
                # #98619 audited opt-in: the /v1/runs session id is wake-capable only when its
                # own continuation path reloads session history — an explicit body/chained
                # session id or a declared X-Hermes-Session-Key conversation (both load
                # SessionDB in _handle_runs), or the run_id fallback the client can post back
                # as body.session_id.  A previous_response_id continuation consumes its
                # ResponseStore snapshot instead and can never see a SessionDB delivery row,
                # so it stays default-denied until a merge contract exists for that chain;
                # likewise a caller-supplied conversation_history is authoritative for the
                # turn and never reads the delivery row, so it is denied the same way.
                session_history_delivery="1" if run.session_history_delivery else "")
            if session_tokens:
                resets.append((session_tokens, clear_session_vars))
            if run.agent_kwargs["room_dispatch"] is not None:
                policy = RoomExecutionPolicy.from_mapping(run.agent_kwargs["room_execution_policy"] or {})
                resets.append((bind_room_execution_policy(policy), reset_room_execution_policy))
            register_gateway_notify(run.approval_session_key, approval_notify)
            # /v1/runs owns its agent lifecycle (no TurnRunner): record process ownership
            # so stop/cancel reaps only the background processes this run created.
            _api_server._publish_turn_process_ownership(agent, effective_task_id)
            # Passed only when set: a human turn keeps today's call shape.
            author_kwargs = {"turn_author": run.turn_author} if run.turn_author is not None else {}
            r = agent.run_conversation(
                user_message=run.user_message, conversation_history=run.conversation_history,
                task_id=effective_task_id, **author_kwargs)
        finally:
            # Clear ownership now so a later stop can't reap work this run left running.
            _api_server._clear_turn_process_ownership(agent)
            self._memory_sessions.checkin(agent)
            # Declared-conversation binding, same precedence gate as _run_agent.
            if run.declared_selected:
                self._bind_declared_conversation(
                    getattr(agent, "session_id", None) or session_id, run.gateway_session_key)
            try:
                unregister_gateway_notify(run.approval_session_key)
            finally:
                for token, reset in resets:
                    with suppress(Exception):
                        reset(token)
        return r, _run_usage(agent), _served_runtime(agent)


def _make_approval_notify(self, run: _RunLaunch, *, _api_server) -> Callable[[dict[str, Any]], None]:
    """Approval-request bridge: redact, stamp the event envelope, park the run status, enqueue."""
    run_id, q, loop = run.run_id, run.queue, asyncio.get_running_loop()

    def _approval_notify(approval_data: dict[str, Any]) -> None:
        # Clients must never receive the raw flagged command (#48456): the shared builder redacts.
        event = _api_server._approval_request_event(run_id, approval_data)
        self._set_run_status(run_id, "waiting_for_approval", last_event="approval.request", approval=event)
        with suppress(Exception):
            loop.call_soon_threadsafe(q.put_nowait, event)

    return _approval_notify


async def _execute_run_via_live_owner(self, run: _RunLaunch, home, record: dict[str, Any], *, _api_server) -> None:
    """Drive a run whose turn a live Bot Chat owner is executing, from that owner's mailbox receipt.

    The receipt is the only truth about the turn: ``settled`` completes the run with the owner's
    reply, a failed receipt fails it with the owner's classified reason. ``/stop`` cannot reach the
    owner's turn — the mailbox has no recall once a record is claimed — so a stop ends this run
    as ``cancelled`` while the chat finishes on its own; the stop handler already reports that a
    run without an in-process agent is not interruptible here.
    """
    from gateway.platforms.api_server_bot_chat import await_live_delivery

    run_id = run.run_id
    delivery_id = record["delivery_id"]

    def _finish(status: str, **fields: Any) -> None:
        if run_id in self._shutdown_interrupted_run_ids:
            # Shutdown already published "interrupted"; the cancel that follows must not
            # rewrite it as a plain "cancelled" (same guard as the native _execute_run).
            status, fields = "interrupted", {"error": "Gateway shutdown interrupted the run."}
        self._set_run_status(run_id, status, **fields, last_event=f"run.{status}")
        with suppress(Exception):
            run.put_event(_run_event(run_id, f"run.{status}", **fields))

    try:
        self._set_run_status(run_id, "running", delivery_id=delivery_id)
        record = await await_live_delivery(
            self, home, record, None, should_stop=lambda: run_id in self._stopping_run_ids)
        if record["status"] in ("queued", "claimed"):
            _finish("cancelled", completed=False, partial=False, interrupted=True)
            return
        if record["status"] == "settled":
            _finish("completed", completed=True, partial=False, interrupted=False,
                    output=record.get("reply") or "", usage={})
        elif record["status"] == "cancelled":
            _finish("cancelled", completed=False, partial=False, interrupted=True)
        else:
            _finish("failed", completed=False, partial=False, interrupted=False,
                    error=record.get("error") or f"Bot Chat delivery {record['status']}",
                    **({"reason": record["reason"]} if record.get("reason") else {}))
    except asyncio.CancelledError:
        _finish("cancelled", completed=False, partial=False, interrupted=True)
        raise
    except Exception as exc:
        logger.exception("[api_server] run %s (live Bot Chat) failed", run_id)
        _finish("failed", completed=False, partial=False, interrupted=False, error=str(exc))
    finally:
        with suppress(Exception):
            run.put_event(None)  # sentinel: close the SSE stream
        _retire_live_run(self, run_id)


async def _execute_run(self, run: _RunLaunch, *, _api_server) -> None:
    """Drive one admitted run, publish its terminal event/status, release live state."""
    _redact_api_error_text = _api_server._redact_api_error_text
    run_id, loop = run.run_id, asyncio.get_running_loop()
    _run_started_at = time.perf_counter()

    def _text_cb(delta: Optional[str]) -> None:
        if delta is None or run_id not in self._run_streams:
            return
        with suppress(Exception):
            loop.call_soon_threadsafe(run.put_event, _run_event(run_id, "message.delta", delta=delta))

    def _interim_cb(text: str, *, already_streamed: bool = False) -> None:
        # Mid-turn assistant commentary (Codex ``phase="commentary"``, text beside tool calls),
        # same ``message.interim`` contract as the TUI gateway; reasoning never reaches this
        # callback and the final answer still arrives via ``run.completed`` (#67580).
        if not isinstance(text, str) or not text.strip() or run_id not in self._run_streams:
            return
        with suppress(Exception):
            loop.call_soon_threadsafe(run.put_event, _run_event(
                run_id, "message.interim", text=text, already_streamed=bool(already_streamed)))

    def _finish(status: str, extra: Optional[dict] = None, **fields: Any) -> None:
        """Terminal status, then best-effort ``run.<status>`` event; key order is wire shape."""
        extra = extra or {}
        if run_id in self._shutdown_interrupted_run_ids:
            status = "interrupted"
            fields = {"error": "Gateway shutdown interrupted the run."}
            extra = {}
        if status in ("completed", "failed"):
            # Local patch (hermes-deploy 1.20.0): settle the runtime
            # receipt state machine before the terminal status becomes
            # visible (✅ on completion, ❌ on failure; cancelled and
            # interrupted runs are not migrated -- they keep their last
            # badge). The completed path also pops the turn's reaction
            # write record (the audit attaches and retracts nothing any
            # more) and offers pure-conversation turns to the social
            # fallback judge.
            _receipt_entry = _receipt_terminal(self, run_id, status)
            if status == "completed":
                _audit_record = _audit_self_reaction(self, run_id, run.session_id)
                _maybe_social_judge(
                    self, run, _audit_record,
                    had_receipt=_receipt_entry is not None)
                # Local patch (hermes-deploy 1.12.0, rebased onto
                # 1.23.0): attach the turn's pending option card at the
                # same pre-visibility point the 1.8.0 self-reaction
                # attach used -- after the self-reaction chain above,
                # before _set_run_status publishes the terminal status.
                _attach_options(self, run_id, run.session_id)
        self._set_run_status(run_id, status, **fields, last_event=f"run.{status}", **extra)
        with suppress(Exception):
            # A worker can finish before its Future is wrapped, so awaiting it
            # need not yield to already-scheduled commentary/tool callbacks.
            loop.call_soon(run.put_event, _run_event(run_id, f"run.{status}", **fields, **extra))

    try:
        # Shutdown landed between admission and the task's first tick: nothing to
        # interrupt yet, and starting a turn now would outlive the gateway.
        if run_id in self._shutdown_interrupted_run_ids:
            _finish("interrupted")
            return
        self._set_run_status(run_id, "running")
        if run_id in self._stopping_run_ids:
            _finish("cancelled")
            return
        if run.admission is not None:
            from gateway.session_api_turn import observe_api_controls, observe_api_turn
            tool_cb = self._make_run_event_callback(run_id, loop, session_id=run.session_id)

            def _control_cb(event_type, prompt):
                # Same authority prompt the WS viewer and GET pending_controls expose, on the
                # run's own stream so a streaming-only client learns it must respond.
                with suppress(Exception):
                    loop.call_soon_threadsafe(run.put_event, _run_event(run_id, event_type, **prompt))

            def _tool_start(call_id, name, args):
                from agent.display import build_tool_preview
                tool_cb("tool.started", name, build_tool_preview(name, args or {}) or "", args, tool_call_id=call_id)

            def _tool_complete(call_id, name, args, result):
                from agent.display import _detect_tool_failure
                is_error, _ = _detect_tool_failure(name, result)
                tool_cb("tool.completed", name, None, args, tool_call_id=call_id, is_error=bool(is_error))

            with observe_api_controls(run.admission, _control_cb):
                result, usage = await observe_api_turn(
                    run.admission, stream_delta_callback=_text_cb,
                    tool_start_callback=_tool_start, tool_complete_callback=_tool_complete)
            # The canonical turn has no agent object here; the served pair rides on the
            # committed usage/result runtime metadata when the turn recorded one.
            served_runtime = ((usage or {}).get("runtime") if isinstance(usage, dict) else None) or (
                result.get("runtime") if isinstance(result, dict) else None) or {}
        else:
            with self._profile_scope(run.request_profile):
                agent = self._create_agent(
                    stream_delta_callback=_text_cb, tool_progress_callback=self._make_run_event_callback(run_id, loop, session_id=run.session_id),
                    interim_assistant_callback=_interim_cb, **run.agent_kwargs)
            self._active_run_agents[run_id] = agent
            approval_notify = _make_approval_notify(self, run, _api_server=_api_server)
            result, usage, served_runtime = await _submit_api_worker(
                loop, lambda: _run_agent_sync(self, run, agent, approval_notify, _api_server=_api_server))
        # Publish request metrics (daily counters + latency) with each completed run (#52323).
        self._record_api_metrics(usage, time.perf_counter() - _run_started_at)
        if not isinstance(result, dict):
            result = {}
        # The committed outcome decides: a stop issued over WS by another viewer interrupts
        # this run just as much as one issued through this adapter's own /stop.
        status, fields = terminal_run_status(result)
        if status == "cancelled":
            _finish("cancelled", fields)
        elif result.get("failed"):
            # Non-retryable client errors (401/400) return failed=True rather than raising.
            _finish("failed", fields, error=_redact_api_error_text(result.get("error") or "agent run failed"))
        else:
            # ``runtime`` rides on both the pollable status and the run.completed event via _finish, in the
            # canonical shape every other api_server surface emits (route_source/requested, cleaned ids).
            requested = {k: run.agent_kwargs.get(f"requested_{k}") for k in ("provider", "model")}
            served_runtime = self._sanitize_runtime_metadata(
                runtime=served_runtime, requested_runtime=requested if any(requested.values()) else None,
                route_source=("model_routes" if run.agent_kwargs.get("route")
                              else "raw_request" if any(requested.values()) else "global"))
            _finish(status, fields, output=result.get("final_response", ""), usage=usage, runtime=served_runtime)
    except asyncio.CancelledError:
        _finish("cancelled")
        raise
    except _api_server._ProviderAuthResolutionError as exc:
        # Same controlled provider-auth message the _run_agent() endpoints give.
        logger.warning("Provider resolution failed for run=%s: %s", run_id, exc)
        _finish("failed", error=exc.user_text())
    except Exception as exc:
        if getattr(exc, "reason", None) == "admission_queued":
            # Still queued at a retiring owner: the next owner runs it once, and GET /v1/runs/{id}
            # reads that row. A run.failed here would invite a poller to resubmit it.
            self._set_run_status(run_id, "queued", last_event="run.queued")
            with suppress(Exception):
                loop.call_soon(run.put_event, _run_event(run_id, "run.queued", message=str(exc)))
            return
        logger.exception("[api_server] run %s failed", run_id)
        _finish("failed", error=_redact_api_error_text(exc))
    finally:
        # On cancellation (/stop) the executor thread may still block on an approval
        # Event; unregistering releases it. Idempotent on normal completion.
        _unregister_approval_notify(run.approval_session_key)
        with suppress(Exception):
            loop.call_soon(run.put_event, None)  # close after the queued events
        _retire_live_run(self, run_id)


def _unregister_approval_notify(approval_session_key: Optional[str]) -> None:
    """Best-effort release of a run's approval waiter (no-op without a key)."""
    with suppress(Exception):
        from tools.approval import unregister_gateway_notify
        if approval_session_key:
            unregister_gateway_notify(approval_session_key)


def _release_run_owner_if_forgotten(self, run_id: str) -> None:
    """Drop the owner stamp only once nothing keyed by *run_id* survives: ownership must
    outlive every surface it protects (retired on different clocks); ownerless = fail-closed."""
    live = (self._run_statuses, self._active_run_agents, self._active_run_tasks, self._run_streams,
            self._run_approval_sessions)
    if not any(run_id in table for table in live):
        self._run_owners.pop(run_id, None)


def _request_owns_run(self, request: web.Request, run_id: str) -> bool:
    scope = self._run_idempotency_scope(request)
    owner = self._run_owners.get(run_id)
    if owner is not None:
        return owner == scope
    # No in-memory owner: only a durable record under the caller's scope admits it.
    # Under multiplex_profiles every profile holds a valid key, so ownerless = allow-all.
    # Run state that exists without an owner stamp is an unanswered authorization question, not a run anyone
    # may control — under gateway.multiplex_profiles every served profile holds a valid key, so admitting it
    # would make the boundary allow-all (#93689).
    if self._run_idempotency_store.owns_run(scope, run_id):
        return True
    from gateway.session_api_turn import owns_api_run
    return owns_api_run(self, run_id, scope)


def _load_owned_run(self, request, *, _api_server, permission: Optional[str], active_fallback: bool):
    """Authenticate (*permission* -> room-grant aware; ``None`` -> API key only) and resolve
    ``(run_id, status, agent, task, error)``; *active_fallback* reports a live in-process run
    without pollable status as ``running`` instead of 404."""
    auth_err = self._check_run_auth(request, permission=permission) if permission else self._check_auth(request)
    if auth_err:
        return None, None, None, None, auth_err
    _openai_error = _api_server._openai_error
    run_id = request.match_info["run_id"]
    if not self._request_owns_run(request, run_id):
        return run_id, None, None, None, _run_not_found(_openai_error, run_id)
    agent = self._active_run_agents.get(run_id)
    task = self._active_run_tasks.get(run_id)
    status = self._durable_run_status(request, run_id)
    if status is None and active_fallback and (agent is not None or task is not None):
        status = self._set_run_status(run_id, "running")
    if status is None:
        return run_id, None, agent, task, _run_not_found(_openai_error, run_id)
    return run_id, status, agent, task, None


async def _handle_get_run(self, request: web.Request, *, _api_server) -> web.Response:
    """GET /v1/runs/{run_id} — return pollable run status for external UIs."""
    _, status, _, _, err = _load_owned_run(
        self, request, _api_server=_api_server, permission="status", active_fallback=True)
    return err or web.json_response(status)


async def _handle_run_events(self, request: web.Request, *, _api_server) -> web.StreamResponse:
    """GET /v1/runs/{run_id}/events — stream structured agent lifecycle events."""
    # Same door as GET /v1/runs/{id}: a room grant that may poll the run may stream it.
    auth_err = self._check_run_auth(request, permission="status")
    if auth_err:
        return auth_err
    run_id = request.match_info["run_id"]
    if not self._request_owns_run(request, run_id):
        return _run_not_found(_api_server._openai_error, run_id)
    # Allow subscribing slightly before the run is registered (race window).
    # Confirm the force-kill actually reaped the process before we clear its PID file / scoped locks.
    # SIGKILL can fail to take (e.g. an uninterruptible-sleep or zombie-reaping parent), and if we blindly
    # clear the metadata and start a fresh instance we end up with two live gateways fighting over the same
    # token — the duplicate-gateway failure in #19471.
    for _ in range(20):
        if run_id in self._run_streams:
            break
        await asyncio.sleep(0.05)
    else:
        return _run_not_found(_api_server._openai_error, run_id)
    stream = self._run_streams[run_id]
    raw_last_seq = request.headers.get("Last-Event-ID") or request.query.get("last_seq")
    try:
        last_seq = max(-1, int(str(raw_last_seq).strip())) if raw_last_seq is not None else -1
    except (TypeError, ValueError):
        last_seq = -1
    q, replay = stream.attach(last_seq)
    response = web.StreamResponse(status=200, headers=self._sse_headers(request))

    async def _write(data: bytes) -> None:
        try:
            async with asyncio.timeout(_RUN_STREAM_WRITE_TIMEOUT):
                await response.write(data)
        except TimeoutError:
            with suppress(Exception):
                response.force_close()
            raise

    async def _write_event(seq: int, event: dict[str, Any]) -> None:
        payload = dict(event)
        payload["seq"] = seq
        await _write(_api_server._sse_frame(payload, id=seq))

    prepared = False
    try:
        await response.prepare(request)
        prepared = True
        # Flush the response head before waiting on the queue: aiohttp holds the headers
        # until the first body write, so a subscriber that connects before the run's first
        # event (e.g. before `approval.request`) sees no bytes and fetch()/EventSource never
        # resolve. A comment frame is ignored by every conforming SSE consumer.
        await _write(b": open\n\n")
        if replay and replay[0][0] > last_seq + 1:
            truncation = _run_event(
                run_id,
                "replay.truncated",
                oldest_retained_seq=replay[0][0],
            )
            if raw_last_seq is not None:
                truncation["requested_seq"] = last_seq
            await _write(_api_server._sse_frame(truncation))
        for seq, event in replay:
            if event is None:
                await _write(b": stream closed\n\n")
                return response
            await _write_event(seq, event)
        if stream.terminal and q.empty():
            await _write(b": stream closed\n\n")
            return response
        while True:
            try:
                seq, event = await asyncio.wait_for(
                    q.get(), timeout=_api_server.CHAT_COMPLETIONS_SSE_KEEPALIVE_SECONDS)
            except TimeoutError:
                await _write(b": keepalive\n\n")
                continue
            if event is _RUN_STREAM_SUBSCRIBER_OVERFLOW:
                logger.debug("[api_server] closing slow SSE subscriber for run %s", run_id)
                break
            if event is None:  # run finished
                await _write(b": stream closed\n\n")
                break
            await _write_event(seq, event)
    except Exception as exc:
        if not prepared:
            raise
        logger.debug("[api_server] SSE stream error for run %s: %s", run_id, exc)
    finally:
        stream.detach(q)
        self._release_run_owner_if_forgotten(run_id)
    return response


def _mark_run_event(self, run_id: str, name: str, **fields: Any) -> None:
    """Record a control-plane event on the run status and (best effort) its SSE stream."""
    self._set_run_status(run_id, "running", last_event=name)
    q = self._run_streams.get(run_id)
    if q is not None:
        with suppress(Exception):
            q.put_nowait(_run_event(run_id, name, **fields))


_APPROVAL_CHOICE_ALIASES = {"approve": "once", "approved": "once", "allow": "once"}


async def _handle_run_approval(self, request: web.Request, *, _api_server) -> web.Response:
    """POST /v1/runs/{run_id}/approval — resolve a pending run approval."""
    _openai_error = _api_server._openai_error
    run_id, _, _, _, err = _load_owned_run(
        self, request, _api_server=_api_server, permission="approve", active_fallback=False)
    if err is not None:
        return err
    try:
        body = await request.json()
    except Exception:
        return _json_error(_openai_error, "Invalid JSON", status=400)
    if getattr(self.gateway_runner, 'session_authority', None) is not None:
        if self._room_grant_token(request) and body.get('choice') not in {'once', 'deny'}:
            return _json_error(_openai_error, 'Room approvals require once or deny', status=400)
        return await _respond_authority_run(self, run_id, body, kind='approval', _api_server=_api_server)
    raw_choice = str(body.get("choice", "")).strip().lower()
    choice = _APPROVAL_CHOICE_ALIASES.get(raw_choice, raw_choice)
    room_scoped = bool(self._room_grant_token(request))
    raw_request_id = body.get("request_id")
    request_id = raw_request_id.strip() if isinstance(raw_request_id, str) else ""
    # Room grants may resolve exactly one request and never widen to session/always.
    allowed = {"once", "deny"} if room_scoped else {"once", "session", "always", "deny"}
    resolve_all = any(_api_server._coerce_request_bool(body.get(k), default=False) for k in ("all", "resolve_all"))
    approval_session_key = self._run_approval_sessions.get(run_id)
    for failed, message, code, status in (
        (raw_request_id is not None and (not request_id or len(request_id) > 256),
         "Approval request_id is invalid.", "invalid_approval_request", 400),
        (choice not in allowed,
         "Invalid approval choice; expected one of: " + ", ".join(sorted(allowed)),
         "invalid_approval_choice", 400),
        (room_scoped and resolve_all,
         "Room approvals can resolve only one exact request", "invalid_approval_scope", 400),
        (room_scoped and not request_id,
         "Room approvals require the exact request_id.", "approval_request_required", 400),
        (not approval_session_key,
         f"Run has no active approval session: {run_id}", "approval_not_active", 409)):
        if failed:
            return _json_error(_openai_error, message, code=code, status=status)
    try:
        from tools.approval import resolve_gateway_approval
        resolved = resolve_gateway_approval(
            approval_session_key, choice, resolve_all=resolve_all, request_id=request_id or None)
    except Exception as exc:
        logger.exception("[api_server] approval resolution failed for run %s", run_id)
        return _json_error(_openai_error, str(exc), status=500)
    if resolved <= 0:
        return _json_error(
            _openai_error, f"Run has no pending approval: {run_id}", code="approval_not_pending", status=409)
    request_id_field = {"request_id": request_id} if request_id else {}
    _mark_run_event(self, run_id, "approval.responded", choice=choice, **request_id_field, resolved=resolved)
    return web.json_response({
        "object": "hermes.run.approval_response", "run_id": run_id, "choice": choice, **request_id_field,
        "resolved": resolved})


async def _respond_authority_run(self, run_id, body, *, kind, _api_server):
    from gateway.platforms.api_server_authority_runs import respond_run, store_error_response
    from hermes_state_runtime import RuntimeStoreError
    try:
        result = await respond_run(self, run_id, body, kind=kind)
        return web.json_response({'run_id': run_id, **result})
    except RuntimeStoreError as exc:
        return store_error_response(_api_server._openai_error, exc)


async def _handle_run_clarify(self, request, *, _api_server):
    run_id, _, _, _, err = _load_owned_run(
        self, request, _api_server=_api_server, permission="approve", active_fallback=False)
    if err is not None:
        return err
    body, err = await self._read_json_body(request)
    if err is not None:
        return err
    return await _respond_authority_run(self, run_id, body, kind='clarify', _api_server=_api_server)


def _steer_refused(_openai_error, run_id):
    return _json_error(_openai_error, f"Run is not currently accepting steer input: {run_id}",
                       code="run_not_accepting_steer", status=409)


async def _handle_steer_run(self, request: web.Request, *, _api_server) -> web.Response:
    """POST /v1/runs/{run_id}/steer — inject guidance into a running agent."""
    _openai_error = _api_server._openai_error
    run_id, status, agent, _, err = _load_owned_run(
        self, request, _api_server=_api_server, permission=None, active_fallback=False)
    if err is not None:
        return err
    owned = None
    if getattr(self.gateway_runner, 'session_authority', None) is not None:
        from gateway.platforms.api_server_authority_runs import run_admission
        owned = run_admission(self, run_id)
        owned = owned if run_id not in self._stopping_run_ids else None
        agent = None
    # /stop keeps agent refs during cooperative shutdown, so the status gate (not the
    # agent ref) is what rejects stop-then-steer.
    if status.get("status") != "running" or (owned is None and not hasattr(agent, "steer")):
        return _steer_refused(_openai_error, run_id)
    body, err = await self._read_json_body(request)
    if err:
        return err
    raw_text = body.get("input") or body.get("message") or body.get("text") or ""
    steer_text = _api_server._normalize_chat_content(raw_text).strip()
    if not steer_text:
        return _json_error(
            _openai_error, "Missing non-empty steer text; expected 'input', 'message', or 'text'.",
            code="invalid_steer_input", status=400)
    if owned is not None:
        from gateway.session_contract import SessionRef
        from hermes_state_runtime import RuntimeStoreError
        authority, row = owned
        sid, latched = row['target_session_id'], False
        try:
            with authority.sessions[sid].event_stream.lock:
                authority.check_approval_generation(sid, row['generation'])
                # Before the claimed turn adopts its agent the steer is latched for that agent.
                agent, latched = authority.steer_agent(SessionRef(authority.profile_id, sid), row['generation'], steer_text)
        except (KeyError, RuntimeStoreError):
            agent = None
        if not latched and not hasattr(agent, "steer"):
            return _steer_refused(_openai_error, run_id)
        if latched:
            _mark_run_event(self, run_id, "run.steered", accepted=True)
            return web.json_response({"object": "hermes.run.steer", "run_id": run_id, "accepted": True})
    try:
        accepted = bool(agent.steer(steer_text))
    except Exception as exc:
        logger.exception("[api_server] steer failed for run %s", run_id)
        return _json_error(_openai_error, _api_server._redact_api_error_text(exc), code="steer_failed", status=500)
    if not accepted:
        return _json_error(
            _openai_error, f"Run did not accept steer text: {run_id}", code="steer_not_accepted", status=409)
    _mark_run_event(self, run_id, "run.steered", accepted=True)
    return web.json_response({"object": "hermes.run.steer", "run_id": run_id, "accepted": True})


async def _handle_stop_run(self, request: web.Request, *, _api_server) -> web.Response:
    """POST /v1/runs/{run_id}/stop — interrupt a running agent."""
    _openai_error = _api_server._openai_error
    run_id, status, agent, task, err = _load_owned_run(
        self, request, _api_server=_api_server, permission="stop", active_fallback=True)
    if err is not None:
        return err
    # A run whose turn a live Bot Chat owns (``_execute_run_via_live_owner``) is not an API
    # admission: its stop is the legacy in-process task cancel below, never ``stop_run``.
    if (getattr(self.gateway_runner, 'session_authority', None) is not None
            and not (task is not None and status.get("delivery_id"))):
        from gateway.platforms.api_server_authority_runs import stop_run, store_error_response
        from hermes_state_runtime import RuntimeStoreError
        try:
            return web.json_response(await stop_run(self, run_id))
        except RuntimeStoreError as exc:
            return store_error_response(_openai_error, exc)
    if status.get("status") in TERMINAL_STATUSES:
        return web.json_response(status)
    if agent is None and task is None:
        return _json_error(
            _openai_error, f"Run is not active in this gateway process: {run_id}",
            code="run_not_active", status=409)
    self._set_run_status(run_id, "stopping", last_event="run.stopping")
    self._stopping_run_ids.add(run_id)
    if agent is not None:
        with suppress(Exception):
            _api_server.request_hard_interrupt(agent, "Stop requested via API")
        # Reap only this run's background processes (epoch-gated inside, so a concurrent
        # run on the same session_id keeps its own); no-op if the run already finished.
        _api_server._reap_disconnected_agent_processes(agent, source="api_server_run_stop")
    return web.json_response({"run_id": run_id, "status": "stopping"})


async def _handle_resolve_unknown_run(
    self, request: web.Request, *, _api_server
) -> web.Response:
    """POST /v1/runs/{run_id}/resolve-unknown — acknowledge one lost owner epoch."""
    run_id, _, _, _, err = _load_owned_run(
        self, request, _api_server=_api_server, permission="stop", active_fallback=False)
    if err is not None:
        return err
    try:
        body = await request.json()
    except (ValueError, LookupError):  # bad JSON/UTF-8 (ValueError) or unknown charset: no body
        body = None
    from gateway.platforms.api_server_authority_runs import resolve_unknown_run, store_error_response
    from hermes_state_runtime import RuntimeStoreError
    try:
        result = await resolve_unknown_run(self, run_id, body)
        return web.json_response({'run_id': run_id, **result})
    except RuntimeStoreError as exc:
        return store_error_response(_api_server._openai_error, exc)


async def _sweep_orphaned_runs(self) -> None:
    """Periodically expire transport buffers and terminal status records."""
    while True:
        await asyncio.sleep(60)
        self._sweep_orphaned_runs_once(time.time())


def _sweep_orphaned_runs_once(self, now: Optional[float] = None) -> None:
    """Expire old SSE buffers without treating transport age as run age."""
    if now is None:
        now = time.time()
    for run_id, created_at in list(self._run_streams_created.items()):
        stream = self._run_streams.get(run_id)
        if now - created_at <= self._RUN_STREAM_TTL or (stream is not None and stream.subscribers):
            continue
        logger.debug("[api_server] sweeping expired run transport %s", run_id)
        task = self._active_run_tasks.get(run_id)
        # Transport TTL bounds buffering; live control state survives until the task returns.
        _drop_run_transport(self, run_id)
        if task is None or task.done():
            _unregister_approval_notify(self._run_approval_sessions.get(run_id))
            _retire_live_run(self, run_id)
    for run_id, status in list(self._run_statuses.items()):
        if (status.get("status") in {"completed", "failed", "cancelled"}
                and now - float(status.get("updated_at", 0) or 0) > self._RUN_STATUS_TTL):
            _forget_run(self, run_id, self._run_statuses, self._run_idempotency_ids)
