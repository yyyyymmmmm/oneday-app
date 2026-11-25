"""OneDay custom gateway routes mixin: short-lived token auth (#1) & APNs push (#4).

Extracted from ``server/patches/api_server.py`` (following the upstream
``OpenAICompatRoutesMixin`` pattern) so OneDay-owned endpoints stay cohesive,
independently testable, and easy to merge across upstream Hermes upgrades.
"""

from __future__ import annotations

import asyncio
from typing import Any, Optional

try:
    from aiohttp import web
except ImportError:  # pragma: no cover - selftest without aiohttp
    web = None  # type: ignore[assignment]


ONEDAY_CAPABILITY_ENDPOINTS = (
    ("push_tokens", ("POST", "/v1/push/tokens", "push_tokens")),
    ("push_tokens_list", ("GET", "/v1/push/tokens", "push_tokens")),
    ("push_tokens_delete", ("DELETE", "/v1/push/tokens/{device_token}", "push_tokens")),
    ("auth_exchange", ("POST", "/v1/auth/token", "short_lived_tokens")),
    ("auth_refresh", ("POST", "/v1/auth/refresh", "short_lived_tokens")),
    ("auth_sessions", ("GET", "/v1/auth/sessions", "short_lived_tokens")),
    ("auth_revoke", ("DELETE", "/v1/auth/sessions/{session_id}", "short_lived_tokens")),
)


def _err(
    message: str,
    status: int,
    *,
    err_type: str = "invalid_request_error",
    code: str | None = None,
):
    payload = {
        "error": {
            "message": str(message),
            "type": err_type,
            "param": None,
            "code": code,
        }
    }
    return web.json_response(payload, status=status)


def oneday_http_routes(adapter: Any) -> list[tuple[str, str, Any]]:
    """Return the (method, path, handler) rows for OneDay push & short-lived auth."""
    return [
        ("POST", "/v1/push/tokens", adapter._handle_post_push_tokens),
        ("GET", "/v1/push/tokens", adapter._handle_list_push_tokens),
        ("DELETE", "/v1/push/tokens/{device_token}", adapter._handle_delete_push_token),
        ("POST", "/v1/auth/token", adapter._handle_auth_exchange),
        ("POST", "/v1/auth/refresh", adapter._handle_auth_refresh),
        ("GET", "/v1/auth/sessions", adapter._handle_auth_sessions),
        ("DELETE", "/v1/auth/sessions/{session_id}", adapter._handle_auth_revoke),
    ]


class OneDayAuthPushRoutesMixin:
    """Mixin for ``APIServerAdapter`` providing ``/v1/push/tokens`` and ``/v1/auth/*``."""

    def _check_short_lived_bearer(
        self, token: str, expected_key: str, request: Any
    ) -> tuple[bool, Optional[Any]]:
        """Validate ``odt1.*`` short-lived access tokens.

        Returns ``(handled, error_response_or_None)``. When ``token`` does not
        start with ``odt1.``, returns ``(False, None)`` so caller falls through
        to the legacy ``API_SERVER_KEY`` comparison.
        """
        if not token.startswith("odt1."):
            return False, None
        try:
            from gateway.platforms import auth_tokens as _at
            ok, sid, err_code = _at.verify_access_token(token, api_key=expected_key)
        except Exception:
            ok, sid, err_code = False, None, "auth_tokens_unavailable"
        if ok and sid:
            request["auth_session_id"] = sid
            return True, None
        return True, _err(
            "Short-lived access token rejected",
            401,
            err_type="gateway_auth_error",
            code=err_code or "invalid_access_token",
        )

    async def _handle_post_push_tokens(self, request: Any) -> Any:
        """POST /v1/push/tokens -- upsert one APNs device push token (batch 4b)."""
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        try:
            from gateway.platforms import push_tokens as _pt
        except Exception:
            return _err("push tokens module unavailable", 503, code="push_tokens_unavailable")
        try:
            body = await request.json()
        except Exception:
            return _err("Invalid JSON in push token registration", 400, code="invalid_json")
        status, payload = await asyncio.to_thread(_pt.register_token, body)
        if status != 200:
            return _err(
                payload.get("error", "push token registration failed"),
                status,
                code=payload.get("code", "invalid_request"),
            )
        return web.json_response(payload, status=200)

    async def _handle_list_push_tokens(self, request: Any) -> Any:
        """GET /v1/push/tokens -- list registered APNs device tokens (masked)."""
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        try:
            from gateway.platforms import push_tokens as _pt
        except Exception:
            return _err("push tokens module unavailable", 503, code="push_tokens_unavailable")
        data = await asyncio.to_thread(_pt.list_tokens)
        apns_configured = False
        try:
            from gateway.platforms import push_sender as _ps
            apns_configured = bool(_ps.is_configured())
        except Exception:
            apns_configured = False
        return web.json_response({
            "object": "list",
            "data": data,
            "apns_configured": apns_configured,
        })

    async def _handle_delete_push_token(self, request: Any) -> Any:
        """DELETE /v1/push/tokens/{device_token} -- unregister one device token."""
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        try:
            from gateway.platforms import push_tokens as _pt
        except Exception:
            return _err("push tokens module unavailable", 503, code="push_tokens_unavailable")
        token = request.match_info.get("device_token", "")
        status, payload = await asyncio.to_thread(_pt.delete_token, token)
        if status != 200:
            return _err(
                payload.get("error", "push token delete failed"),
                status,
                code=payload.get("code", "invalid_request"),
            )
        return web.json_response(payload, status=200)

    async def _handle_auth_exchange(self, request: Any) -> Any:
        """POST /v1/auth/token -- exchange long-lived API key for short-lived token pair."""
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        try:
            from gateway.platforms import auth_tokens as _at
        except Exception:
            return _err("auth tokens module unavailable", 503, code="auth_tokens_unavailable")
        try:
            body = await request.json()
        except Exception:
            body = {}
        if not isinstance(body, dict):
            body = {}
        expected_key = self._expected_api_key()
        if not expected_key:
            return _err(
                "Gateway API key is not available for this profile",
                503,
                code="auth_key_unavailable",
            )
        payload = await asyncio.to_thread(
            _at.exchange_key_for_tokens,
            api_key=expected_key,
            device_name=str(body.get("device_name") or ""),
            app_version=str(body.get("app_version") or ""),
        )
        return web.json_response(payload, status=200)

    async def _handle_auth_refresh(self, request: Any) -> Any:
        """POST /v1/auth/refresh -- public by design; refresh_token is the credential."""
        try:
            from gateway.platforms import auth_tokens as _at
        except Exception:
            return _err("auth tokens module unavailable", 503, code="auth_tokens_unavailable")
        try:
            body = await request.json()
        except Exception:
            return _err("Invalid JSON in refresh request", 400, code="invalid_json")
        if not isinstance(body, dict) or not body.get("refresh_token"):
            return _err("Missing refresh_token", 400, code="invalid_request")
        expected_key = self._expected_api_key()
        if not expected_key:
            return _err(
                "Gateway API key is not available for this profile",
                503,
                code="auth_key_unavailable",
            )
        status, payload = await asyncio.to_thread(
            _at.refresh_tokens,
            refresh_token=str(body.get("refresh_token") or ""),
            api_key=expected_key,
            app_version=body.get("app_version"),
        )
        if status != 200:
            return _err(
                payload.get("error", "refresh failed"),
                status,
                err_type="gateway_auth_error",
                code=payload.get("code", "invalid_refresh_token"),
            )
        return web.json_response(payload, status=200)

    async def _handle_auth_sessions(self, request: Any) -> Any:
        """GET /v1/auth/sessions -- list active and recently revoked device sessions."""
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        try:
            from gateway.platforms import auth_tokens as _at
        except Exception:
            return _err("auth tokens module unavailable", 503, code="auth_tokens_unavailable")
        data = await asyncio.to_thread(_at.list_sessions)
        return web.json_response({"object": "list", "data": data}, status=200)

    async def _handle_auth_revoke(self, request: Any) -> Any:
        """DELETE /v1/auth/sessions/{session_id} -- revoke one device session."""
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        try:
            from gateway.platforms import auth_tokens as _at
        except Exception:
            return _err("auth tokens module unavailable", 503, code="auth_tokens_unavailable")
        session_id = request.match_info.get("session_id", "")
        status, payload = await asyncio.to_thread(
            _at.revoke_session,
            session_id=session_id,
        )
        if status != 200:
            return _err(
                payload.get("error", "session revoke failed"),
                status,
                code=payload.get("code", "invalid_request"),
            )
        return web.json_response(payload, status=200)
