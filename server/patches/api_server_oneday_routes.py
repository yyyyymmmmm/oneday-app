"""OneDay custom gateway routes mixin: short-lived token auth (#1) & APNs push (#4).

Extracted from ``server/patches/api_server.py`` (following the upstream
``OpenAICompatRoutesMixin`` pattern) so OneDay-owned endpoints stay cohesive,
independently testable, and easy to merge across upstream Hermes upgrades.

2.8.0 adds the panel web-login bridge (``POST /api/companion/web-login``)
and its companion reveal (``POST /api/env/reveal``): the App's one-step
password login, previously served only by the companion front process
(retired in 2.0.0/2.3.0), restored natively on the gateway with the
contract unchanged (front 1.0.33+ semantics; see ``_handle_web_login``).
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import http.client
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
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
    ("vault_entries", ("GET", "/v1/vault/entries", "credential_vault")),
    ("vault_entry", ("GET", "/v1/vault/entries/{entry_id}", "credential_vault")),
    ("vault_create", ("POST", "/v1/vault/entries", "credential_vault")),
    ("vault_replace", ("PUT", "/v1/vault/entries/{entry_id}", "credential_vault")),
    ("vault_revoke", ("DELETE", "/v1/vault/entries/{entry_id}", "credential_vault")),
    ("vault_requests", ("GET", "/v1/vault/requests", "credential_vault")),
    ("vault_request_status", ("GET", "/v1/vault/requests/{request_id}", "credential_vault")),
    ("vault_fulfill", ("POST", "/v1/vault/requests/{request_id}/fulfill", "credential_vault")),
    ("web_login", ("POST", "/api/companion/web-login", "panel_web_login")),
    ("env_reveal", ("POST", "/api/env/reveal", "panel_web_login")),
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


# ------------------------------------------------------------ web login bridge
# Ported from the retired companion front (server/companion/front/front.py,
# 1.0.33+) with semantics unchanged: the panel (deployer) password is the
# one credential the user knows; it is verified by scrypt against
# password.json, then exchanged server-side for a Hermes dashboard
# session cookie using the deployment credentials in the gateway's own
# environment. The dashboard password itself never leaves the server.

_WEB_LOGIN_FAIL_LIMIT = 5
_WEB_LOGIN_FAIL_WINDOW = 300
_WEB_LOGIN_FAILS: dict[str, list[float]] = {}
_REVEAL_ALLOWLIST = frozenset({"API_SERVER_KEY"})


def _panel_password_file() -> Path:
    override = os.environ.get("PANEL_PASSWORD_FILE", "")
    if override:
        return Path(override)
    return Path("/opt/companion-state/password.json")


def _panel_password_hash() -> str:
    p = _panel_password_file()
    if p.exists():
        try:
            return json.loads(p.read_text()).get("hash", "") or ""
        except Exception:
            pass
    return os.environ.get("PANEL_PASSWORD_HASH", "")


def _verify_panel_password(pw: str, stored: str) -> bool:
    try:
        _, n, r, p, salt_hex, dk_hex = stored.split("$")
        dk = hashlib.scrypt(
            pw.encode(),
            salt=bytes.fromhex(salt_hex),
            n=int(n),
            r=int(r),
            p=int(p),
            dklen=len(bytes.fromhex(dk_hex)),
            maxmem=2**26,
        )
        return hmac.compare_digest(dk.hex(), dk_hex)
    except Exception:
        return False


def _dashboard_base() -> str:
    return (
        os.environ.get("HERMES_DASHBOARD_BASE")
        or os.environ.get("ONEDAY_DASH_BASE_URL")
        or "http://127.0.0.1:9119"
    ).rstrip("/")


def _dashboard_password_login() -> tuple[int, list[str]]:
    """Exchange the deployment credentials for a Hermes dashboard
    session inside the server network. Returns (status, Set-Cookie
    header values) so the caller can pass the cookie through as-is."""
    from urllib.parse import urlparse

    user = os.environ.get("HERMES_DASHBOARD_BASIC_AUTH_USERNAME", "")
    password = os.environ.get("HERMES_DASHBOARD_BASIC_AUTH_PASSWORD", "")
    u = urlparse(_dashboard_base())
    conn = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=8)
    body = json.dumps(
        {"provider": "basic", "username": user, "password": password, "next": "/"}
    )
    try:
        conn.request(
            "POST", "/auth/password-login", body, {"Content-Type": "application/json"}
        )
        resp = conn.getresponse()
        resp.read()
        cookies = resp.headers.get_all("Set-Cookie") or []
        return resp.status, cookies
    finally:
        conn.close()


def _dashboard_cookie_valid(cookie: str) -> bool:
    """A dashboard session cookie counts as valid only if the dashboard
    itself answers an auth-gated read (GET /api/env) with 200 for it."""
    if not cookie:
        return False
    req = urllib.request.Request(
        _dashboard_base() + "/api/env", headers={"Cookie": cookie}, method="GET"
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            return resp.status == 200
    except Exception:
        return False


def _web_login_client_ip(request: Any) -> str:
    """Source IP for login rate-limit accounting (front 1.0.34 parity):
    public traffic arrives via the same-host nginx, so the peer is
    loopback and X-Real-IP carries the real source; trust it only then."""
    peer = request.remote or ""
    if peer in ("127.0.0.1", "::1"):
        real = request.headers.get("X-Real-IP", "")
        if real:
            return real
    return peer


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
        ("GET", "/v1/vault/entries", adapter._handle_vault_list),
        ("GET", "/v1/vault/entries/{entry_id}", adapter._handle_vault_get),
        ("POST", "/v1/vault/entries", adapter._handle_vault_create),
        ("PUT", "/v1/vault/entries/{entry_id}", adapter._handle_vault_replace),
        ("DELETE", "/v1/vault/entries/{entry_id}", adapter._handle_vault_delete),
        ("GET", "/v1/vault/requests", adapter._handle_vault_requests_list),
        ("GET", "/v1/vault/requests/{request_id}", adapter._handle_vault_request_status),
        ("POST", "/v1/vault/requests/{request_id}/fulfill", adapter._handle_vault_fulfill),
        ("POST", "/api/companion/web-login", adapter._handle_web_login),
        ("POST", "/api/env/reveal", adapter._handle_env_reveal),
    ]


class OneDayAuthPushRoutesMixin:
    """Mixin for ``APIServerAdapter`` providing ``/v1/push/tokens``,
    ``/v1/auth/*``, ``/v1/vault/*`` and the panel web-login bridge."""

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

    def _vault_module(self):
        from gateway.platforms import credential_vault
        return credential_vault

    @staticmethod
    def _vault_session(request):
        return request.get("auth_session_id") or ""

    @staticmethod
    def _vault_scope():
        from gateway.platforms.api_server import _api_request_profile
        return _api_request_profile.get() or "default"

    async def _handle_vault_list(self, request):
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        try:
            return web.json_response({"object": "list", "data": self._vault_module().list_entries(self._vault_scope())})
        except Exception:
            return _err("Credential vault unavailable", 503, code="vault_unavailable")

    async def _handle_vault_get(self, request):
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        try:
            row = self._vault_module().get_entry(request.match_info.get("entry_id", ""), self._vault_scope())
            return web.json_response(row if row else {"status": "not_found"}, status=200 if row else 404)
        except Exception:
            return _err("Credential vault unavailable", 503, code="vault_unavailable")

    async def _handle_vault_create(self, request):
        return await self._vault_write(request, None)

    async def _handle_vault_replace(self, request):
        return await self._vault_write(request, request.match_info.get("entry_id", ""))

    async def _vault_write(self, request, entry_id):
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        try:
            body = await request.json()
            status, payload = await asyncio.to_thread(
                self._vault_module().write_entry, body, self._expected_api_key(), entry_id, self._vault_scope())
            return web.json_response(payload, status=status)
        except Exception:
            return _err("Credential vault unavailable", 503, code="vault_unavailable")

    async def _handle_vault_delete(self, request):
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        try:
            status, payload = await asyncio.to_thread(self._vault_module().delete_entry, request.match_info.get("entry_id", ""), self._vault_scope())
            return web.json_response(payload, status=status)
        except Exception:
            return _err("Credential vault unavailable", 503, code="vault_unavailable")

    async def _handle_vault_request_status(self, request):
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        if not self._vault_session(request):
            return web.json_response({"status": "not_found"}, status=404)
        try:
            payload = self._vault_module().request_status(request.match_info.get("request_id", ""), self._vault_session(request), self._vault_scope())
            return web.json_response(payload if payload else {"status": "not_found"}, status=200 if payload else 404)
        except Exception:
            return _err("Credential request unavailable", 503, code="vault_unavailable")

    async def _handle_vault_requests_list(self, request):
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        if not self._vault_session(request):
            return web.json_response({"status": "not_found"}, status=404)
        try:
            status = request.query.get("status", "pending")
            data = self._vault_module().list_requests(self._vault_session(request), self._vault_scope(), status)
            return web.json_response({"object": "list", "data": data})
        except Exception:
            return _err("Credential request unavailable", 503, code="vault_unavailable")

    async def _handle_vault_fulfill(self, request):
        auth_err = self._check_auth(request)
        if auth_err:
            return auth_err
        if not self._vault_session(request):
            return web.json_response({"status": "not_found"}, status=404)
        try:
            body = await request.json()
            status, payload = await asyncio.to_thread(
                self._vault_module().fulfill_request,
                request.match_info.get("request_id", ""), body,
                self._expected_api_key(), self._vault_session(request), self._vault_scope())
            return web.json_response(payload, status=status)
        except Exception:
            return _err("Credential request unavailable", 503, code="vault_unavailable")

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

    # ---------------------------------------------------------- web login
    @staticmethod
    def _web_login_fails(fkey: str) -> list[float]:
        now = time.time()
        fails = [
            t
            for t in _WEB_LOGIN_FAILS.get(fkey, [])
            if now - t < _WEB_LOGIN_FAIL_WINDOW
        ]
        _WEB_LOGIN_FAILS[fkey] = fails
        return fails

    async def _handle_web_login(self, request: Any) -> Any:
        """POST /api/companion/web-login -- panel password in, dashboard
        session cookie out. Public by design (the password is the
        credential); failures share the front-era 5-per-300s per-IP
        limit. Contract identical to companion front 1.0.33+."""
        try:
            body = await request.json()
        except Exception:
            body = {}
        if not isinstance(body, dict):
            body = {}
        fkey = f"{_web_login_client_ip(request)}:password"
        fails = self._web_login_fails(fkey)
        if len(fails) >= _WEB_LOGIN_FAIL_LIMIT:
            return web.json_response(
                {"ok": False, "error": "尝试太多次，请几分钟后再试"}, status=429
            )
        stored = await asyncio.to_thread(_panel_password_hash)
        ok = bool(stored) and await asyncio.to_thread(
            _verify_panel_password, str(body.get("password", "")), stored
        )
        if not ok:
            fails.append(time.time())
            _WEB_LOGIN_FAILS[fkey] = fails
            return web.json_response(
                {"ok": False, "error": "登录失败，请检查后重试"}, status=401
            )
        _WEB_LOGIN_FAILS.pop(fkey, None)
        if not os.environ.get(
            "HERMES_DASHBOARD_BASIC_AUTH_USERNAME"
        ) or not os.environ.get("HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"):
            return web.json_response(
                {"ok": False, "error": "服务器还没有配好网页登录，请联系部署者"},
                status=500,
            )
        try:
            code, cookies = await asyncio.to_thread(_dashboard_password_login)
        except Exception:
            code, cookies = 0, []
        if code != 200 or not cookies:
            return web.json_response(
                {"ok": False, "error": "登录服务暂时不可用，请稍后再试"}, status=502
            )
        resp = web.json_response({"ok": True}, status=200)
        for c in cookies:
            resp.headers.add("Set-Cookie", c)
        return resp

    async def _handle_env_reveal(self, request: Any) -> Any:
        """POST /api/env/reveal -- dashboard-session-gated env reveal.

        The App fetches API_SERVER_KEY immediately after web-login,
        riding the dashboard session cookie the bridge set. Only
        allowlisted keys are served, and the session is validated
        against the dashboard itself, never trusted blindly."""
        try:
            body = await request.json()
        except Exception:
            body = {}
        if not isinstance(body, dict):
            body = {}
        key = str(body.get("key", ""))
        if key not in _REVEAL_ALLOWLIST:
            return _err("Key is not revealable", 403, code="reveal_not_allowed")
        cookie = request.headers.get("Cookie", "")
        valid = await asyncio.to_thread(_dashboard_cookie_valid, cookie)
        if not valid:
            return _err(
                "Dashboard session required",
                401,
                err_type="gateway_auth_error",
                code="no_dashboard_session",
            )
        value = self._expected_api_key()
        if not value:
            return _err(
                "Value is not available", 503, code="reveal_unavailable"
            )
        return web.json_response({"key": key, "value": value}, status=200)
