"""APNs push sender module (batch 4b sender half + #46 async aioapns upgrade).

Reads APNs provider credentials from environment variables:
- ``APNS_KEY_PATH``: path to Apple ``.p8`` ES256 private key file
- ``APNS_KEY_ID``: 10-char Apple Key ID
- ``APNS_TEAM_ID``: 10-char Apple Team ID
- ``APNS_TOPIC``: iOS Bundle ID (e.g. ``com.oneday.app``)

Payload shape matches ``Sources/OneDayCore/PushRegistration.swift``
(``PushNotificationRouteResolver``):
- approval: ``{"aps": {...}, "kind": "approval", "request_id": "..."}``
- run:      ``{"aps": {...}, "kind": "run", "session_id": "..."}``

Transport strategy (#46):
- Async path (``send_notification_async``) prefers ``aioapns`` (HTTP/2
  persistent connection pool) when installed, falling back transparently
  to ``httpx[http2]`` + ``PyJWT``.
- Sync path (``send_notification``) stays 100% backward-compatible for
  existing synchronous callers and returns
  ``skipped_reason="apns_not_configured"`` when credentials are absent.
- ``PushDispatchScheduler`` provides a coalescing async dispatch queue
  so rapid burst notifications never overwhelm APNs or block request
  handlers.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from pathlib import Path
from typing import Any

logger = logging.getLogger("gateway.platforms.push_sender")

APNS_HOSTS = {
    "sandbox": "https://api.sandbox.push.apple.com",
    "production": "https://api.push.apple.com",
}


def apns_config() -> dict[str, str]:
    return {
        "key_path": os.environ.get("APNS_KEY_PATH", "").strip(),
        "key_id": os.environ.get("APNS_KEY_ID", "").strip(),
        "team_id": os.environ.get("APNS_TEAM_ID", "").strip(),
        "topic": os.environ.get("APNS_TOPIC", "").strip(),
    }


def is_configured() -> bool:
    cfg = apns_config()
    return bool(
        cfg["key_path"]
        and Path(cfg["key_path"]).is_file()
        and cfg["key_id"]
        and cfg["team_id"]
        and cfg["topic"]
    )


def build_payload(
    *,
    title: str,
    body: str,
    kind: str,
    request_id: str | None = None,
    session_id: str | None = None,
    badge: int | None = None,
) -> dict[str, Any]:
    """Build APNs JSON payload matching OneDay PushNotificationRouteResolver."""
    aps: dict[str, Any] = {
        "alert": {"title": title, "body": body},
        "sound": "default",
    }
    if badge is not None:
        aps["badge"] = int(badge)
    payload: dict[str, Any] = {"aps": aps, "kind": kind}
    if kind == "approval" and request_id:
        payload["request_id"] = request_id
    elif kind == "run" and session_id:
        payload["session_id"] = session_id
    return payload


def _resolve_tokens(tokens: list[dict[str, Any]] | None) -> list[dict[str, Any]]:
    if tokens is not None:
        return tokens
    try:
        from gateway.platforms import push_tokens as _pt
        return _pt.list_tokens(include_raw=True)
    except Exception:
        return []


def _prune_token(tok: str) -> bool:
    try:
        from gateway.platforms import push_tokens as _pt
        _pt.delete_token(tok)
        return True
    except Exception:
        return False


async def _send_via_aioapns(
    payload: dict[str, Any],
    tokens: list[dict[str, Any]],
    cfg: dict[str, str],
) -> dict[str, Any] | None:
    """Async delivery via ``aioapns`` when installed; returns None if unavailable."""
    try:
        from aioapns import APNs, NotificationRequest  # type: ignore
    except ImportError:
        return None

    sent = failed = pruned = 0
    clients: dict[tuple[str, bool], Any] = {}
    try:
        for row in tokens:
            tok = str(row.get("device_token") or "").strip()
            if not tok:
                continue
            use_sandbox = str(row.get("environment") or "production") == "sandbox"
            topic = str(row.get("bundle_id") or cfg["topic"])
            ckey = (topic, use_sandbox)
            client = clients.get(ckey)
            if client is None:
                client = APNs(
                    key=cfg["key_path"],
                    key_id=cfg["key_id"],
                    team_id=cfg["team_id"],
                    topic=topic,
                    use_sandbox=use_sandbox,
                )
                clients[ckey] = client
            req = NotificationRequest(device_token=tok, message=payload)
            try:
                resp = await client.send_notification(req)
                if getattr(resp, "is_successful", False):
                    sent += 1
                else:
                    failed += 1
                    desc = str(getattr(resp, "description", "") or "")
                    if "BadDeviceToken" in desc or "Unregistered" in desc:
                        if _prune_token(tok):
                            pruned += 1
            except Exception:
                logger.exception("push_sender(aioapns): delivery error for %s", tok[:8])
                failed += 1
    finally:
        for client in clients.values():
            close = getattr(client, "close", None)
            if callable(close):
                try:
                    res = close()
                    if asyncio.iscoroutine(res):
                        await res
                except Exception:
                    pass
    return {
        "sent": sent,
        "failed": failed,
        "pruned": pruned,
        "transport": "aioapns",
        "payload": payload,
    }


def _send_via_httpx(
    payload: dict[str, Any],
    tokens: list[dict[str, Any]],
    cfg: dict[str, str],
) -> dict[str, Any]:
    """Synchronous HTTP/2 + ES256 JWT delivery via PyJWT + httpx[http2]."""
    try:
        import jwt  # type: ignore
        import httpx  # type: ignore
    except ImportError as exc:
        return {
            "sent": 0,
            "failed": 0,
            "pruned": 0,
            "skipped_reason": f"missing_dependency:{exc.name}",
            "payload": payload,
        }

    private_key = Path(cfg["key_path"]).read_text(encoding="utf-8")
    bearer = jwt.encode(
        {"iss": cfg["team_id"], "iat": int(time.time())},
        private_key,
        algorithm="ES256",
        headers={"kid": cfg["key_id"]},
    )
    raw_body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    sent = failed = pruned = 0
    with httpx.Client(http2=True, timeout=10.0) as client:
        for row in tokens:
            tok = str(row.get("device_token") or "").strip()
            env = str(row.get("environment") or "production")
            host = APNS_HOSTS.get(env, APNS_HOSTS["production"])
            if not tok:
                continue
            try:
                resp = client.post(
                    f"{host}/3/device/{tok}",
                    headers={
                        "authorization": f"bearer {bearer}",
                        "apns-topic": str(row.get("bundle_id") or cfg["topic"]),
                        "apns-push-type": "alert",
                        "apns-priority": "10",
                    },
                    content=raw_body,
                )
                if resp.status_code == 200:
                    sent += 1
                elif resp.status_code in (400, 410):
                    failed += 1
                    if resp.status_code == 410 or "BadDeviceToken" in resp.text:
                        if _prune_token(tok):
                            pruned += 1
                else:
                    failed += 1
            except Exception:
                logger.exception("push_sender: delivery error for %s", tok[:8])
                failed += 1
    return {
        "sent": sent,
        "failed": failed,
        "pruned": pruned,
        "transport": "httpx",
        "payload": payload,
    }


async def send_notification_async(
    *,
    title: str,
    body: str,
    kind: str,
    request_id: str | None = None,
    session_id: str | None = None,
    badge: int | None = None,
    tokens: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Async APNs dispatch: prefers ``aioapns``, falls back to ``httpx`` off-loop."""
    payload = build_payload(
        title=title, body=body, kind=kind,
        request_id=request_id, session_id=session_id, badge=badge,
    )
    if not is_configured():
        return {
            "sent": 0,
            "failed": 0,
            "pruned": 0,
            "skipped_reason": "apns_not_configured",
            "payload": payload,
        }
    resolved = _resolve_tokens(tokens)
    if not resolved:
        return {
            "sent": 0,
            "failed": 0,
            "pruned": 0,
            "skipped_reason": "no_registered_tokens",
            "payload": payload,
        }
    cfg = apns_config()
    aio_res = await _send_via_aioapns(payload, resolved, cfg)
    if aio_res is not None:
        return aio_res
    return await asyncio.to_thread(_send_via_httpx, payload, resolved, cfg)


def send_notification(
    *,
    title: str,
    body: str,
    kind: str,
    request_id: str | None = None,
    session_id: str | None = None,
    badge: int | None = None,
    tokens: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Dispatch notification to registered tokens (graceful no-op if unconfigured)."""
    payload = build_payload(
        title=title, body=body, kind=kind,
        request_id=request_id, session_id=session_id, badge=badge,
    )
    if not is_configured():
        return {
            "sent": 0,
            "failed": 0,
            "pruned": 0,
            "skipped_reason": "apns_not_configured",
            "payload": payload,
        }
    resolved = _resolve_tokens(tokens)
    if not resolved:
        return {
            "sent": 0,
            "failed": 0,
            "pruned": 0,
            "skipped_reason": "no_registered_tokens",
            "payload": payload,
        }
    return _send_via_httpx(payload, resolved, apns_config())


class PushDispatchScheduler:
    """Coalescing async push queue with bounded concurrency (#46).

    Deduplicates rapid bursts sharing the same ``coalesce_key`` (e.g.
    ``approval:<id>`` or ``run:<session_id>``) within a short window
    before handing off to ``send_notification_async``.
    """

    def __init__(self, *, coalesce_window_sec: float = 0.5, max_queue: int = 128) -> None:
        self._window = max(0.0, float(coalesce_window_sec))
        self._max_queue = max(1, int(max_queue))
        self._pending: dict[str, dict[str, Any]] = {}
        self._order: list[str] = []
        self._task: asyncio.Task[None] | None = None

    def enqueue(self, coalesce_key: str, **kwargs: Any) -> bool:
        if coalesce_key not in self._pending:
            if len(self._order) >= self._max_queue:
                return False
            self._order.append(coalesce_key)
        self._pending[coalesce_key] = kwargs
        return True

    async def flush_once(self) -> list[dict[str, Any]]:
        if not self._order:
            return []
        keys = list(self._order)
        self._order.clear()
        batch = [self._pending.pop(k) for k in keys if k in self._pending]
        results: list[dict[str, Any]] = []
        for item in batch:
            results.append(await send_notification_async(**item))
        return results

    def start(self) -> None:
        if self._task is not None and not self._task.done():
            return
        async def _loop() -> None:
            while True:
                await asyncio.sleep(max(0.1, self._window))
                try:
                    await self.flush_once()
                except Exception:
                    logger.exception("PushDispatchScheduler: flush error")
        self._task = asyncio.create_task(_loop())

    def stop(self) -> None:
        if self._task is not None and not self._task.done():
            self._task.cancel()
        self._task = None
