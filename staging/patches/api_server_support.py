"""Concurrency and idempotency primitives extracted from api_server.py (Phase 9.1)."""

from __future__ import annotations

import asyncio
import threading
import time
from typing import Any, Optional


class _IdempotencyCache:
    """In-memory idempotency cache with TTL and basic LRU semantics."""

    def __init__(self, max_items: int = 1000, ttl_seconds: int = 300):
        from collections import OrderedDict

        self._store = OrderedDict()
        self._inflight: dict[tuple[str, str], asyncio.Task[Any]] = {}
        self._ttl = ttl_seconds
        self._max = max_items

    def _purge(self):
        now = time.time()
        expired = [k for k, v in self._store.items() if now - v["ts"] > self._ttl]
        for k in expired:
            self._store.pop(k, None)
        while len(self._store) > self._max:
            self._store.popitem(last=False)

    async def get_or_set(self, key: str, fingerprint: str, compute_coro):
        self._purge()
        item = self._store.get(key)
        if item and item["fp"] == fingerprint:
            return item["resp"]
        inflight_key = (key, fingerprint)
        task = self._inflight.get(inflight_key)
        if task is None:
            async def _compute_and_store():
                resp = await compute_coro()
                self._store[key] = {"resp": resp, "fp": fingerprint, "ts": time.time()}
                self._purge()
                return resp

            task = asyncio.create_task(_compute_and_store())
            self._inflight[inflight_key] = task

            def _clear_inflight(done_task: asyncio.Task[Any]) -> None:
                if self._inflight.get(inflight_key) is done_task:
                    self._inflight.pop(inflight_key, None)

            task.add_done_callback(_clear_inflight)
        return await asyncio.shield(task)


class _ProviderAuthResolutionError(RuntimeError):
    """Typed provider credential failure, distinct from other runtime failures."""

    def is_rate_limited(self) -> bool:
        """A quota cap with valid credentials is not an authentication failure."""
        from hermes_cli.auth import is_rate_limited_auth_error

        cause = self.__cause__
        cause = getattr(cause, "__cause__", None) if isinstance(cause, RuntimeError) else cause
        return bool(is_rate_limited_auth_error(cause))

    def user_text(self) -> str:
        """Human-facing provider error line for API-backed chat UIs."""
        from agent.i18n import t

        label = t("platform.api_server.provider_rate_limited" if self.is_rate_limited()
                  else "platform.api_server.provider_auth_failed")
        return t("platform.api_server.provider_error_line", label=label, error=self)


class _SessionEventQueue:
    """Ordered SSE queue; enqueue is safe from executor threads."""

    def __init__(self, session_id: str, run_id: str):
        self.loop = asyncio.get_running_loop()
        self.queue: asyncio.Queue[Optional[tuple[str, dict[str, Any]]]] = asyncio.Queue()
        self.session_id = session_id
        self.run_id = run_id
        self.seq = 0
        # Cross-thread puts handed to the loop and not yet applied.
        self._inflight = 0
        self._inflight_lock = threading.Lock()

    def payload(self, name: str, payload: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        self.seq += 1
        payload.setdefault("session_id", self.session_id)
        payload.setdefault("run_id", self.run_id)
        payload.setdefault("seq", self.seq)
        payload.setdefault("ts", time.time())
        return name, payload

    def enqueue(self, name: str, payload: dict[str, Any]) -> None:
        event = self.payload(name, payload)
        try:
            running_loop = asyncio.get_running_loop()
        except RuntimeError:
            running_loop = None
        if running_loop is self.loop:
            self.queue.put_nowait(event)
            return
        with self._inflight_lock:
            self._inflight += 1

        def _apply() -> None:
            try:
                self.queue.put_nowait(event)
            finally:
                self._settle_one()

        try:
            self.loop.call_soon_threadsafe(_apply)
        except RuntimeError:  # loop closed: the stream is gone
            self._settle_one()

    def _settle_one(self) -> None:
        with self._inflight_lock:
            self._inflight -= 1

    async def flush(self) -> None:
        """Wait until every worker-thread event has reached the queue."""
        while True:
            with self._inflight_lock:
                if not self._inflight:
                    return
            await asyncio.sleep(0)
