#!/usr/bin/env python3
"""Self-test for extracted OneDayAuthPushRoutesMixin (api_server_oneday_routes.py)."""

from __future__ import annotations

import asyncio
import hashlib
import importlib.util
import json
import os
import secrets
import sys
import tempfile
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


class _FakeHeaders(dict):
    def add(self, key, value):
        self.setdefault(key, []).append(value)


class _FakeResponse:
    def __init__(self, data, status=200):
        self.data = data
        self.status = status
        self.headers = _FakeHeaders()


class _FakeWeb:
    @staticmethod
    def json_response(data, status=200):
        return _FakeResponse(data, status=status)


class _FakeRequest(dict):
    def __init__(self, *, headers=None, body=None, match_info=None, query=None, remote="203.0.113.7"):
        super().__init__()
        self.headers = headers or {}
        self._body = body
        self.match_info = match_info or {}
        self.query = query or {}
        self.remote = remote

    async def json(self):
        return self._body


async def run() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        # Wire fake gateway.platforms package pointing at server/patches
        gw = types.ModuleType("gateway")
        gp = types.ModuleType("gateway.platforms")
        sys.modules["gateway"] = gw
        sys.modules["gateway.platforms"] = gp

        auth_tokens = _load("gateway.platforms.auth_tokens", ROOT / "patches" / "auth_tokens.py")
        push_tokens = _load("gateway.platforms.push_tokens", ROOT / "patches" / "push_tokens.py")
        push_sender = _load("gateway.platforms.push_sender", ROOT / "patches" / "push_sender.py")
        routes_mod = _load(
            "gateway.platforms.api_server_oneday_routes",
            ROOT / "patches" / "api_server_oneday_routes.py",
        )
        setattr(gp, "auth_tokens", auth_tokens)
        setattr(gp, "push_tokens", push_tokens)
        setattr(gp, "push_sender", push_sender)
        setattr(gp, "api_server_oneday_routes", routes_mod)

        auth_tokens.STORE_PATH = Path(tmp) / "sessions.json"
        push_tokens.STORE_PATH = Path(tmp) / "push_tokens.json"
        routes_mod.web = _FakeWeb

        api_key = "test-master-api-key-0123456789"

        class _DummyAdapter(routes_mod.OneDayAuthPushRoutesMixin):
            def _expected_api_key(self) -> str:
                return api_key

            @staticmethod
            def _vault_scope() -> str:
                return "default"

            def _check_auth(self, request):
                hdr = request.headers.get("Authorization", "")
                if not hdr.startswith("Bearer "):
                    return _FakeResponse({"error": {"code": "unauthorized"}}, status=401)
                tok = hdr[7:].strip()
                handled, err = self._check_short_lived_bearer(tok, api_key, request)
                if handled:
                    return err
                if tok == api_key:
                    return None
                return _FakeResponse({"error": {"code": "unauthorized"}}, status=401)

        adapter = _DummyAdapter()

        # 1. Route table exposes auth, push, vault, and web-login endpoints
        table = routes_mod.oneday_http_routes(adapter)
        assert len(table) == 17, f"expected 17 routes, got {len(table)}"
        assert len(routes_mod.ONEDAY_CAPABILITY_ENDPOINTS) == 17
        assert {(method, path) for method, path, _ in table[-2:]} == {
            ("POST", "/api/companion/web-login"),
            ("POST", "/api/env/reveal"),
        }
        assert {(method, path) for method, path, _ in table[-10:-2]} == {
            ("GET", "/v1/vault/entries"),
            ("GET", "/v1/vault/entries/{entry_id}"),
            ("POST", "/v1/vault/entries"),
            ("PUT", "/v1/vault/entries/{entry_id}"),
            ("DELETE", "/v1/vault/entries/{entry_id}"),
            ("GET", "/v1/vault/requests"),
            ("GET", "/v1/vault/requests/{request_id}"),
            ("POST", "/v1/vault/requests/{request_id}/fulfill"),
        }
        assert [path for method, path, _ in table if method == "GET" and path.startswith("/v1/vault/requests")][:2] == [
            "/v1/vault/requests", "/v1/vault/requests/{request_id}"]

        # 2. Exchange long-lived key -> short-lived pair
        r = await adapter._handle_auth_exchange(_FakeRequest(
            headers={"Authorization": f"Bearer {api_key}"},
            body={"device_name": "iPhone Test", "app_version": "0.51.0"},
        ))
        assert r.status == 200
        sid = r.data["session_id"]
        access = r.data["access_token"]
        refresh = r.data["refresh_token"]
        assert access.startswith("odt1.")
        assert refresh.startswith("odr1.")

        # 3. Use short-lived access token to list sessions
        req_sessions = _FakeRequest(headers={"Authorization": f"Bearer {access}"})
        r_list = await adapter._handle_auth_sessions(req_sessions)
        assert r_list.status == 200
        assert req_sessions.get("auth_session_id") == sid
        assert len(r_list.data["data"]) == 1

        # 3b. Vault request listing is session-bound and forwards the status query.
        calls = []
        class _VaultStub:
            @staticmethod
            def list_requests(session_id, scope, status):
                calls.append((session_id, scope, status))
                return [{"request_id": "vreq_test", "status": status}]
        adapter._vault_module = lambda: _VaultStub
        req_vault_list = _FakeRequest(
            headers={"Authorization": f"Bearer {access}"}, query={"status": "expired"})
        r_vault_list = await adapter._handle_vault_requests_list(req_vault_list)
        assert r_vault_list.status == 200
        assert r_vault_list.data == {"object": "list", "data": [{"request_id": "vreq_test", "status": "expired"}]}
        assert calls == [(sid, "default", "expired")]
        req_vault_default = _FakeRequest(headers={"Authorization": f"Bearer {access}"})
        r_vault_default = await adapter._handle_vault_requests_list(req_vault_default)
        assert r_vault_default.status == 200
        assert calls[-1] == (sid, "default", "pending")
        # 3c. Owner mode (2.13.0): the long-lived master key lists across
        # sessions -- the handler forwards session_id=None; device tokens
        # above keep their own session. (Pre-2.13.0 this asserted 404.)
        owner_list = await adapter._handle_vault_requests_list(_FakeRequest(
            headers={"Authorization": f"Bearer {api_key}"}))
        assert owner_list.status == 200
        assert calls[-1] == (None, "default", "pending")

        # 4. Refresh without Authorization header
        r_ref = await adapter._handle_auth_refresh(_FakeRequest(body={"refresh_token": refresh}))
        assert r_ref.status == 200
        assert r_ref.data["refresh_token"] != refresh

        # 5. Revoke session and verify old access token is rejected
        r_rev = await adapter._handle_auth_revoke(_FakeRequest(
            headers={"Authorization": f"Bearer {api_key}"},
            match_info={"session_id": sid},
        ))
        assert r_rev.status == 200
        assert r_rev.data["revoked"] == 1

        r_rejected = await adapter._handle_auth_sessions(
            _FakeRequest(headers={"Authorization": f"Bearer {access}"})
        )
        assert r_rejected.status == 401
        assert r_rejected.data["error"]["code"] == "session_revoked"

        # 6. Push token register / list (with apns_configured) / delete
        tok_hex = "a" * 64
        r_p1 = await adapter._handle_post_push_tokens(_FakeRequest(
            headers={"Authorization": f"Bearer {api_key}"},
            body={
                "device_token": tok_hex,
                "environment": "sandbox",
                "bundle_id": "site.didichou.oneday",
                "app_version": "0.51.0",
            },
        ))
        assert r_p1.status == 200
        r_p2 = await adapter._handle_list_push_tokens(_FakeRequest(
            headers={"Authorization": f"Bearer {api_key}"},
        ))
        assert r_p2.status == 200
        assert r_p2.data["apns_configured"] is False
        assert len(r_p2.data["data"]) == 1

        r_p3 = await adapter._handle_delete_push_token(_FakeRequest(
            headers={"Authorization": f"Bearer {api_key}"},
            match_info={"device_token": tok_hex},
        ))
        assert r_p3.status == 200

        # 7. Web-login bridge: scrypt panel password -> dashboard cookie;
        #    reveal serves only allowlisted keys behind a valid session.
        panel_pw = "panel-test-pw"
        salt = secrets.token_bytes(16)
        dk = hashlib.scrypt(panel_pw.encode(), salt=salt, n=16384, r=8, p=1,
                            dklen=32, maxmem=2 ** 26)
        pw_file = Path(tmp) / "password.json"
        pw_file.write_text(json.dumps(
            {"hash": f"scrypt$16384$8$1${salt.hex()}${dk.hex()}"}))
        os.environ["PANEL_PASSWORD_FILE"] = str(pw_file)
        os.environ["HERMES_DASHBOARD_BASIC_AUTH_USERNAME"] = "dashuser"
        os.environ["HERMES_DASHBOARD_BASIC_AUTH_" + "PASSWORD"] = "dashpass"
        routes_mod._dashboard_password_login = lambda: (
            200, ["session=abc123; Path=/; HttpOnly"])
        routes_mod._dashboard_cookie_valid = (
            lambda cookie: "session=abc123" in cookie)

        r_bad = await adapter._handle_web_login(_FakeRequest(
            body={"password": "wrong"}, remote="198.51.100.9"))
        assert r_bad.status == 401
        r_ok = await adapter._handle_web_login(_FakeRequest(
            body={"password": panel_pw}, remote="198.51.100.9"))
        assert r_ok.status == 200
        assert r_ok.data == {"ok": True}
        assert r_ok.headers.get("Set-Cookie") == ["session=abc123; Path=/; HttpOnly"]

        # Rate limit: 5 failures from one IP, the 6th attempt is refused
        for _ in range(5):
            r_rl = await adapter._handle_web_login(_FakeRequest(
                body={"password": "wrong"}, remote="198.51.100.10"))
            assert r_rl.status == 401
        r_rl = await adapter._handle_web_login(_FakeRequest(
            body={"password": panel_pw}, remote="198.51.100.10"))
        assert r_rl.status == 429

        r_rev_nocookie = await adapter._handle_env_reveal(_FakeRequest(
            body={"key": "API_SERVER_KEY"}))
        assert r_rev_nocookie.status == 401
        r_rev_badkey = await adapter._handle_env_reveal(_FakeRequest(
            headers={"Cookie": "session=abc123"}, body={"key": "HOME"}))
        assert r_rev_badkey.status == 403
        r_rev = await adapter._handle_env_reveal(_FakeRequest(
            headers={"Cookie": "session=abc123"}, body={"key": "API_SERVER_KEY"}))
        assert r_rev.status == 200
        assert r_rev.data == {"key": "API_SERVER_KEY", "value": api_key}

    print("oneday_routes_selftest: ALL PASSED")


if __name__ == "__main__":
    asyncio.run(run())
