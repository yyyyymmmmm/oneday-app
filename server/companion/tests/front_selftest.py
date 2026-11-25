#!/usr/bin/env python3
"""Front self-test: fake Hermes (health/models/sessions) + real front
subprocess. Covers: dual login, rate limit, CSRF, info shape, selfcheck
(both tiers), connections create/credential rollback discipline."""
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import urllib.error
from urllib.parse import urljoin
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FRONT = os.path.join(ROOT, "front", "front.py")
FPORT = 18650
HPORT = 18942
NPORT = 18943
DPORT = 18944
BPORT = 18945
BOX_GOOD_KEY = "box-good-key-123456"
NEWAPI_CALLS = []
BASE = f"http://127.0.0.1:{FPORT}/api/companion"
GOOD_KEY = "login-key-good"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


class FakeHermes(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authed(self):
        return self.headers.get("Authorization") == f"Bearer {GOOD_KEY}"

    def do_GET(self):
        if self.path == "/health":
            return self._json(200, {"status": "ok"})
        if self.path == "/v1/models":
            return self._json(200, {"data": []}) if self._authed() \
                else self._json(401, {"error": "bad key"})
        return self._json(404, {})

    def do_POST(self):
        if self.path == "/api/sessions":
            return self._json(201, {"id": "x", "model": "deepseek-flash"})
        if self.path.endswith("/model"):
            return self._json(200, {"ok": True})
        return self._json(404, {})

    def do_DELETE(self):
        return self._json(200, {"ok": True})


FAKE_SYNC = {"datasets": {
    "contacts": {"dataset": "contacts", "label": "通讯录",
                 "synced": True, "synced_at": "2026-11-10T01:00:00+00:00",
                 "item_count": 7, "auth_range": "full",
                 "permission_state": "granted", "expired": False,
                 "pending_write": False, "syncing": False,
                 "last_error": None},
    "calendar": {"dataset": "calendar", "label": "日历",
                 "synced": False, "item_count": 0,
                 "permission_state": None, "pending_write": False},
    "reminders": {"dataset": "reminders", "label": "提醒事项",
                  "synced": False, "item_count": 0,
                  "permission_state": None, "pending_write": False},
    "photos": {"dataset": "photos", "label": "照片",
               "synced": False, "item_count": 0,
               "permission_state": None, "pending_write": False},
    "motion": {"dataset": "motion", "label": "步数",
               "synced": False, "item_count": 0,
               "permission_state": None, "pending_write": False}}}
FAKE_DEVICE_CALLS = []
FAKE_DEVICE_KEY = "front-test-device-key"


class FakeDashboard(BaseHTTPRequestHandler):
    """Stand-in for the Hermes dashboard login (9119): accepts only
    the deployment credentials and issues a session cookie, so the
    web-login bridge's cookie pass-through can be checked."""

    def log_message(self, *a):
        pass

    def do_POST(self):
        if self.path != "/auth/password-login":
            code = 404
            body = b"{}"
            cookie = None
        else:
            n = int(self.headers.get("Content-Length", "0"))
            try:
                req_body = json.loads(self.rfile.read(n) or b"{}")
            except Exception:
                req_body = {}
            if req_body.get("provider") == "basic" \
                    and req_body.get("username") == "dash-user" \
                    and req_body.get("password") == "dash-pass":
                code = 200
                body = b'{"ok": true, "next": "/"}'
                cookie = "hermes_session=fake-session-token; Path=/; HttpOnly"
            else:
                code = 401
                body = b'{"error": "invalid"}'
                cookie = None
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        if cookie:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(body)


class FakeNewAPI(BaseHTTPRequestHandler):
    """New API gateway admin face, real wire shape: the channel list
    carries a secret `key` per channel that the front must never
    forward to the App."""

    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        NEWAPI_CALLS.append({
            "path": self.path,
            "auth": self.headers.get("Authorization"),
            "user": self.headers.get("New-Api-User"),
        })
        if not self.path.startswith("/api/channel/"):
            return self._json(404, {})
        if self.headers.get("Authorization") != "Bearer newapi-admin-test":
            return self._json(401, {"success": False,
                                    "message": "bad admin token"})
        return self._json(200, {
            "success": True, "message": "",
            "data": {"page": 0, "page_size": 100, "total": 2,
                     "items": [
                         {"id": 14, "name": "DeepSeek 官方", "status": 1,
                          "priority": 5, "weight": 100, "group": "DeepSeek",
                          "models": "deepseek-flash, deepseek-v4-pro",
                          "key": "sk-must-never-leak"},
                         {"id": 9, "name": "Claude 旗舰(备用)", "status": 2,
                          "priority": 0, "weight": 0,
                          "group": "default,Claude 旗舰",
                          "models": "claude-sonnet",
                          "key": "sk-also-secret"},
                     ]}})


class FakeDevice(BaseHTTPRequestHandler):
    """Stand-in for the device module's sync status/delete surface."""
    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self._json(200, {"ok": True})
        if self.path == "/device/sync/status":
            if self.headers.get("Authorization") \
                    != "Bearer " + FAKE_DEVICE_KEY:
                return self._json(401, {"error": "unauthorized"})
            return self._json(200, FAKE_SYNC)
        return self._json(404, {})

    def do_POST(self):
        if self.path == "/device/sync/delete":
            FAKE_DEVICE_CALLS.append(self.path)
            return self._json(200, {"deleted": ["contacts"]})
        return self._json(404, {})


def req(method, url, body=None, headers=None):
    h = dict(headers or {})
    data = json.dumps(body).encode() if body is not None else None
    if data:
        h["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r, timeout=15) as resp:
            return resp.status, json.loads(resp.read() or b"{}"), resp.headers
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}"), e.headers
        except Exception:
            return e.code, {}, e.headers
    except Exception as e:
        return 0, {"_error": str(e)}, {}


def raw_req(url):
    r = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(r, timeout=15) as resp:
            return resp.status, resp.read(), resp.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers
    except Exception as e:
        return 0, str(e).encode(), {}


def check_page_assets(page_path):
    """Fetch the panel page and every asset it references, resolving
    relative URLs the way a browser would against the page URL.
    Guards the 2026-11-10 incident where index.html pointed at
    app.css/app.js without the static/ prefix and both 404'd,
    leaving the panel unstyled with all views stacked."""
    page_url = f"http://127.0.0.1:{FPORT}{page_path}"
    code, body, _ = raw_req(page_url)
    if code != 200:
        return False, f"{page_path} itself -> {code}"
    html = body.decode("utf-8", "replace")
    refs = re.findall(r'<link[^>]+href="([^"]+)"', html)
    refs += re.findall(r'<script[^>]+src="([^"]+)"', html)
    if not refs:
        return False, f"{page_path} references no assets"
    for ref in refs:
        if ref.startswith(("http://", "https://", "data:")):
            continue
        asset_url = urljoin(page_url, ref)
        acode, _, ahdrs = raw_req(asset_url)
        ctype = ahdrs.get("Content-Type", "")
        if acode != 200:
            return False, f"{page_path} ref {ref} -> {asset_url} = {acode}"
        if ref.endswith(".css") and "text/css" not in ctype:
            return False, f"{ref} content-type {ctype}"
        if ref.endswith(".js") and "javascript" not in ctype:
            return False, f"{ref} content-type {ctype}"
    return True, ""


def wait_up():
    for _ in range(60):
        try:
            code, _, _ = req("GET", BASE + "/session")
            if code == 200:
                return True
        except Exception:
            pass
        time.sleep(0.3)
    return False


WINRM_STUB = '''
"""Selftest stub for pywinrm (front's winrm_probe imports it).
Behaviour keyed by username: badpass -> InvalidCredentialsError,
ghost -> ConnectionError, anything else -> hostname STUB-PC."""
import sys, types


class InvalidCredentialsError(Exception):
    pass


exceptions = types.ModuleType("winrm.exceptions")
exceptions.InvalidCredentialsError = InvalidCredentialsError
sys.modules["winrm.exceptions"] = exceptions


class _Result:
    def __init__(self, code, out=b""):
        self.status_code = code
        self.std_out = out
        self.std_err = b""


class Session:
    def __init__(self, target, auth=None, transport=None,
                 server_cert_validation=None):
        self._user = (auth or ("", ""))[0]

    def run_cmd(self, cmd):
        if self._user == "badpass":
            raise InvalidCredentialsError("401")
        if self._user == "ghost":
            raise ConnectionError("no route to host")
        return _Result(0, b"STUB-PC\\r\\n")
'''


class FakeBoxMCP(BaseHTTPRequestHandler):
    """Stand-in for the Simular official MCP (桥-3 解耦后 front 直连
    验活的对象): only the good key gets an initialize answer."""

    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        try:
            req_body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            req_body = {}
        if self.headers.get("Authorization") != f"Bearer {BOX_GOOD_KEY}":
            body = b'{"error": "bad key"}'
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        method = req_body.get("method", "")
        if method == "initialize":
            obj = {"jsonrpc": "2.0", "id": 1, "result": {
                "protocolVersion": "2025-03-26", "capabilities": {},
                "serverInfo": {"name": "fake-box", "version": "1.0"}}}
            body = json.dumps(obj).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Mcp-Session-Id", "fake-box-session")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif method == "tools/list":
            obj = {"jsonrpc": "2.0", "id": 2, "result": {"tools": [
                {"name": "box_status"}, {"name": "screenshot"}]}}
            body = json.dumps(obj).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:  # notifications/initialized etc.
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()


def main():
    tmp = tempfile.mkdtemp(prefix="companion-front-")
    stub_dir = os.path.join(tmp, "stubs")
    os.makedirs(stub_dir)
    open(os.path.join(stub_dir, "winrm.py"), "w").write(WINRM_STUB)
    state = os.path.join(tmp, "state")
    hermes_home = os.path.join(tmp, "hermes-home")
    os.makedirs(hermes_home)
    env_path = os.path.join(hermes_home, ".env")
    env_orig = "OTHER=1\n"
    open(env_path, "w").write(env_orig)
    open(os.path.join(hermes_home, "config.yaml"), "w").write(
        "model:\n  default: deepseek-flash\nauxiliary:\n  vision:\n    model: deepseek-flash\n"
        "mcp_servers:\n  box:\n    url: https://example.invalid/mcp\n")
    oneday_dir = os.path.join(tmp, "oneday")
    os.makedirs(oneday_dir)
    open(os.path.join(oneday_dir, "data.json"), "w").write('{"goals": []}')
    comp_env = os.path.join(tmp, "companion.env")
    open(comp_env, "w").write("# [global]\nTZ=Asia/Shanghai\n\n# [box]\nMCP_BOX_API_KEY=\n")

    pw_hash = subprocess.run([sys.executable, FRONT, "--hash-password", "test-pass-123"],
                             capture_output=True, text=True).stdout.strip()
    check("hash-password CLI produces scrypt hash", pw_hash.startswith("scrypt$"))

    fake = ThreadingHTTPServer(("127.0.0.1", HPORT), FakeHermes)
    threading.Thread(target=fake.serve_forever, daemon=True).start()
    fake_newapi = ThreadingHTTPServer(("127.0.0.1", NPORT), FakeNewAPI)
    threading.Thread(target=fake_newapi.serve_forever, daemon=True).start()
    fake_dash = ThreadingHTTPServer(("127.0.0.1", DPORT), FakeDashboard)
    threading.Thread(target=fake_dash.serve_forever, daemon=True).start()
    fake_box = ThreadingHTTPServer(("127.0.0.1", BPORT), FakeBoxMCP)
    threading.Thread(target=fake_box.serve_forever, daemon=True).start()
    try:
        fake_dev = ThreadingHTTPServer(("127.0.0.1", 8647), FakeDevice)
        threading.Thread(target=fake_dev.serve_forever,
                         daemon=True).start()
    except OSError:
        fake_dev = None
        print("SKIP sync panel checks (port 8647 busy)")

    env = dict(os.environ,
               PYTHONPATH=stub_dir,
               COMPANION_FRONT_PORT=str(FPORT), COMPANION_COOKIE_SECURE="0",
               COMPANION_SERVICE_KEY="svc-key-test", HERMES_API_KEY=GOOD_KEY,
               HERMES_BASE=f"http://127.0.0.1:{HPORT}",
               COMPANION_STATE_DIR=state, COMPANION_ENV_FILE=comp_env,
               COMPANION_HERMES_ENV=env_path,
               COMPANION_CONFIG_PATH=os.path.join(hermes_home, "config.yaml"),
               COMPANION_ONEDAY_DATA=os.path.join(oneday_dir, "data.json"),
               COMPANION_DECISIONS_PATH=os.path.join(tmp, "decisions.jsonl"),
               COMPANION_CONTROL_PORT="18799", HERMES_HOME=hermes_home,
               DEVICE_BRIDGE_KEY=FAKE_DEVICE_KEY,
               BOX_MCP_URL=f"http://127.0.0.1:{BPORT}/mcp",
               NEWAPI_BASE_URL=f"http://127.0.0.1:{NPORT}",
               NEWAPI_ADMIN_TOKEN="newapi-admin-test",
               NEWAPI_ADMIN_USER_ID="1",
               HERMES_DASHBOARD_BASE=f"http://127.0.0.1:{DPORT}",
               HERMES_DASHBOARD_USER="dash-user",
               HERMES_DASHBOARD_PASSWORD="dash-pass",
               PANEL_PASSWORD_HASH=pw_hash)
    front = subprocess.Popen([sys.executable, FRONT], env=env,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        check("front comes up", wait_up())
        ok, extra = check_page_assets("/companion/")
        check("panel assets resolve+200 via /companion/", ok, extra)
        ok, extra = check_page_assets("/")
        check("panel assets resolve+200 via /", ok, extra)
        svc = {"Authorization": "Bearer svc-key-test"}

        code, _, _ = req("GET", BASE + "/info")
        check("info without auth is 401", code == 401)
        code, info, _ = req("GET", BASE + "/info", headers=svc)
        check("info shape + hermesUp + unknown module state",
              code == 200 and info.get("hermesUp") is True
              and info["modules"]["writeGate"]["state"] == "unknown"
              and info["companionVersion"] and "generatedAt" in info,
              str(info)[:200])

        code, body, hdrs = req("POST", BASE + "/login",
                               {"method": "key", "key": GOOD_KEY})
        cookie = hdrs.get("Set-Cookie", "")
        check("key login succeeds, cookie+csrf issued",
              code == 200 and body.get("ok") and "companion_session=" in cookie
              and "HttpOnly" in cookie and "SameSite=Strict" in cookie)
        sid = cookie.split(";", 1)[0]
        csrf = body.get("csrf")
        auth = {"Cookie": sid}
        code, sess, _ = req("GET", BASE + "/session", headers=auth)
        check("session endpoint sees login", code == 200 and sess.get("authenticated"))

        code, _, _ = req("POST", BASE + "/password", {"password": "new-pass-456"},
                         headers=auth)
        check("password change without CSRF is 403", code == 403)
        code, body, _ = req("POST", BASE + "/password", {"password": "new-pass-456"},
                            headers={**auth, "X-Companion-CSRF": csrf})
        check("password change with CSRF works", code == 200 and body.get("ok"))

        code, body, _ = req("POST", BASE + "/login",
                            {"method": "password", "password": "new-pass-456"})
        check("login with new password works", code == 200 and body.get("ok"))

        # web-login bridge (1.0.33): deployer password in, dashboard
        # session cookie out. The successful call also clears the
        # shared rate-limit bucket, so the burn test below is unaffected.
        code, body, _ = req("POST", BASE + "/web-login",
                            {"password": "wrong"})
        check("web-login wrong password is 401",
              code == 401 and body.get("ok") is False, f"{code} {body}")
        code, body, hdrs = req("POST", BASE + "/web-login",
                               {"password": "new-pass-456"})
        check("web-login passes dashboard cookie through",
              code == 200 and body.get("ok") is True
              and "hermes_session=fake-session-token"
              in hdrs.get("Set-Cookie", ""),
              f"{code} {body} {hdrs.get('Set-Cookie')}")

        # change-password (1.0.35): authenticated surface, verifies
        # the CURRENT password, shares the login rate-limit pool.
        # Success below clears the shared bucket again.
        code, body, _ = req("POST", BASE + "/change-password",
                            {"currentPassword": "new-pass-456",
                             "newPassword": "final-pass-789"})
        check("change-password without auth is 401", code == 401,
              f"{code} {body}")
        code, body, _ = req("POST", BASE + "/change-password",
                            {"currentPassword": "wrong",
                             "newPassword": "final-pass-789"}, headers=svc)
        check("change-password wrong current is 401",
              code == 401 and body.get("ok") is False, f"{code} {body}")
        code, body, _ = req("POST", BASE + "/change-password",
                            {"currentPassword": "new-pass-456",
                             "newPassword": "short"}, headers=svc)
        check("change-password short new is 400", code == 400,
              f"{code} {body}")
        code, body, _ = req("POST", BASE + "/change-password",
                            {"currentPassword": "new-pass-456",
                             "newPassword": "new-pass-456"}, headers=svc)
        check("change-password same-as-current is 400", code == 400,
              f"{code} {body}")
        code, body, _ = req("POST", BASE + "/change-password",
                            {"currentPassword": "new-pass-456",
                             "newPassword": "final-pass-789"}, headers=svc)
        check("change-password happy path is 200",
              code == 200 and body.get("ok") is True, f"{code} {body}")
        code, body, _ = req("POST", BASE + "/login",
                            {"method": "password", "password": "final-pass-789"})
        check("login with changed password works",
              code == 200 and body.get("ok"))
        code, body, hdrs = req("POST", BASE + "/web-login",
                               {"password": "final-pass-789"})
        check("web-login with changed password works",
              code == 200 and body.get("ok") is True
              and "hermes_session=fake-session-token"
              in hdrs.get("Set-Cookie", ""), f"{code} {body}")
        # restore the password the rate-limit section below expects
        code, body, _ = req("POST", BASE + "/change-password",
                            {"currentPassword": "final-pass-789",
                             "newPassword": "new-pass-456"}, headers=svc)
        check("change-password round-trip restores test password",
              code == 200 and body.get("ok") is True, f"{code} {body}")

        # agent identity (1.0.36): rename writes only the SOUL.md title
        # line; avatar round-trips through the authenticated surface.
        soul_file = os.path.join(hermes_home, "SOUL.md")
        with open(soul_file, "w", encoding="utf-8") as f:
            f.write("You are a helpful agent.\n\nBody stays.\n")
        code, body, _ = req("POST", BASE + "/agent-name",
                            {"name": "小助手"})
        check("agent-name without auth is 401", code == 401,
              f"{code} {body}")
        code, body, _ = req("POST", BASE + "/agent-name",
                            {"name": "坏。名字"}, headers=svc)
        check("agent-name with punctuation is 400", code == 400,
              f"{code} {body}")
        code, body, _ = req("POST", BASE + "/agent-name",
                            {"name": "小助手"}, headers=svc)
        check("agent-name insert-title is 200",
              code == 200 and body.get("name") == "小助手", f"{code} {body}")
        with open(soul_file, encoding="utf-8") as f:
            soul_now = f.read()
        check("agent-name preserves body",
              soul_now.startswith("# 小助手\n") and "Body stays." in soul_now,
              soul_now[:80])
        code, body, _ = req("POST", BASE + "/agent-name",
                            {"name": "阿伴"}, headers=svc)
        check("agent-name replace-title is 200",
              code == 200 and body.get("name") == "阿伴", f"{code} {body}")
        with open(soul_file, encoding="utf-8") as f:
            soul_now = f.read()
        check("agent-name replaces only the title line",
              soul_now.startswith("# 阿伴\n") and "小助手" not in soul_now
              and "Body stays." in soul_now, soul_now[:80])
        check("agent-name leaves a backup",
              any(n.startswith("SOUL.md.bak-agentname-")
                  for n in os.listdir(hermes_home)))
        code, raw, hdrs = raw_req(BASE + "/avatar")
        check("avatar GET without auth is 401", code == 401, f"{code}")
        png_b64 = ("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lE"
                   "QVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")
        code, body, _ = req("POST", BASE + "/avatar",
                            {"data_url": f"data:image/png;base64,{png_b64}"},
                            headers=svc)
        check("avatar POST png is 200 with version",
              code == 200 and bool(body.get("version")), f"{code} {body}")
        code, body, _ = req("POST", BASE + "/avatar",
                            {"data_url": "data:image/png;base64,aGVsbG8="},
                            headers=svc)
        check("avatar POST fake png is 400", code == 400, f"{code} {body}")
        r = urllib.request.Request(BASE + "/avatar", method="GET",
                                   headers=svc)
        try:
            with urllib.request.urlopen(r, timeout=15) as resp:
                av_code, av_type = resp.status, resp.headers.get("Content-Type", "")
                av_len = len(resp.read())
        except Exception as e:
            av_code, av_type, av_len = 0, "", 0
        check("avatar GET returns stored png",
              av_code == 200 and av_type.startswith("image/png") and av_len > 20,
              f"{av_code} {av_type} {av_len}")

        code, body, _ = req("GET", BASE + "/connections", headers=svc)
        ids = [c["id"] for c in body.get("connections", [])]
        check("connection seeds listed", code == 200 and "github" in ids
              and "hermes-mcp" in ids, str(ids))
        gh = next(c for c in body["connections"] if c["id"] == "github")
        check("github starts unconfigured, no value leaked",
              gh["configured"] is False and "token" not in json.dumps(gh).lower())

        code, body, _ = req("POST", BASE + "/connections",
                            {"kind": "cloud_computer", "provider": "vps_agent",
                             "name": "测试 VPS"}, headers=svc)
        vps_id = body.get("connection", {}).get("id")
        check("create vps_agent record", code == 200 and bool(vps_id), str(body))
        code, body, _ = req("POST", f"{BASE}/connections/{vps_id}/credential",
                            {"endpointUrl": "http://127.0.0.1:1", "token": "t" * 24},
                            headers=svc)
        check("vps credential with dead endpoint fails verify",
              code == 200 and body.get("ok") is False, str(body))
        check(".env rolled back after failed vps verify",
              open(env_path).read() == env_orig)
        code, body, _ = req("POST", f"{BASE}/connections/{vps_id}/disconnect",
                            {}, headers=svc)
        check("disconnect works", code == 200 and body.get("ok"))

        # --- windows login form (cloudpc closeout, spec §4) ---
        code, body, _ = req("POST", BASE + "/connections",
                            {"kind": "cloud_computer", "provider": "vps_agent",
                             "name": "测试 Windows"}, headers=svc)
        win_id = body.get("connection", {}).get("id")
        check("create windows vps record", code == 200 and bool(win_id),
              str(body))
        code, body, _ = req("POST", f"{BASE}/connections/{win_id}/credential",
                            {"host": "stubhost", "username": "Administrator",
                             "password": "Sup3rSecret!"}, headers=svc)
        check("windows credential via winrm stub verifies",
              code == 200 and body.get("ok") is True
              and "STUB-PC" in str(body.get("detail")), str(body))
        code, body, _ = req("GET", BASE + "/connections", headers=svc)
        win_rec = next(c for c in body["connections"] if c["id"] == win_id)
        check("windows record configured, effective pending link",
              win_rec["configured"] is True
              and "待打通" in str(win_rec.get("effective")), str(win_rec))
        check("windows password never leaks in list output",
              "Sup3rSecret!" not in json.dumps(body))
        code, body, _ = req("POST", f"{BASE}/connections/{win_id}/credential",
                            {"host": "stubhost", "username": "badpass",
                             "password": "wrong"}, headers=svc)
        check("windows credential with bad password rejected",
              code == 200 and body.get("ok") is False, str(body))
        code, body, _ = req("GET", BASE + "/connections", headers=svc)
        win_rec = next(c for c in body["connections"] if c["id"] == win_id)
        check("bad password rolls back (record unconfigured)",
              win_rec["configured"] is False, str(win_rec))
        code, body, _ = req("POST", f"{BASE}/connections/{win_id}/credential",
                            {"host": "127.0.0.1", "username": "ghost",
                             "password": "x"}, headers=svc)
        check("windows credential to dead host rejected",
              code == 200 and body.get("ok") is False, str(body))
        code, body, _ = req("POST", f"{BASE}/connections/{win_id}/credential",
                            {"host": "https://evil.example", "username": "a",
                             "password": "x"}, headers=svc)
        check("windows credential with URL-shaped host is 400",
              code == 400, str(body))
        code, body, _ = req("POST", f"{BASE}/connections/{win_id}/disconnect",
                            {}, headers=svc)
        check("windows disconnect works", code == 200 and body.get("ok"))

        code, body, _ = req("POST", BASE + "/connections/github/credential",
                            {"token": "github_pat_" + "x" * 30}, headers=svc)
        check("github credential with fake token fails verify + rolls back",
              code == 200 and body.get("ok") is False
              and open(env_path).read() == env_orig, str(body)[:200])

        # --- simular default record (桥-3 解耦): no box module exists
        # in this stack at all; cred/verify/disconnect must all work
        # over the direct MCP path alone ---
        comp_env_orig = open(comp_env).read()
        code, body, _ = req("POST", BASE + "/connections/box/verify", {},
                            headers=svc)
        check("box verify with no key fails (direct probe: down)",
              code == 200 and body.get("ok") is False, str(body))
        code, body, _ = req("POST", BASE + "/connections/box/credential",
                            {"apiKey": "box-wrong-key-00000"}, headers=svc)
        check("box credential with wrong key fails direct verify",
              code == 200 and body.get("ok") is False, str(body))
        check("companion.env rolled back after failed box verify",
              open(comp_env).read() == comp_env_orig)
        code, body, _ = req("POST", BASE + "/connections/box/credential",
                            {"apiKey": BOX_GOOD_KEY}, headers=svc)
        check("box credential with good key verifies direct + saved",
              code == 200 and body.get("ok") is True
              and f"MCP_BOX_API_KEY={BOX_GOOD_KEY}" in open(comp_env).read(),
              str(body))
        code, body, _ = req("GET", BASE + "/connections", headers=svc)
        box_rec = next(c for c in body["connections"] if c["id"] == "box")
        check("box record configured after direct cred",
              box_rec["configured"] is True, str(box_rec))
        code, body, _ = req("POST", BASE + "/connections/box/verify", {},
                            headers=svc)
        check("box verify with saved key ok (direct probe: up)",
              code == 200 and body.get("ok") is True, str(body))
        code, body, _ = req("POST", BASE + "/connections/box/credential",
                            {"apiKey": "box-wrong-key-00000"}, headers=svc)
        check("box re-key with wrong key rolls back to saved key",
              code == 200 and body.get("ok") is False
              and f"MCP_BOX_API_KEY={BOX_GOOD_KEY}" in open(comp_env).read(),
              str(body))
        code, body, _ = req("POST", BASE + "/connections/box/disconnect",
                            {}, headers=svc)
        check("box disconnect clears key, no module linkage",
              code == 200 and body.get("ok") is True
              and BOX_GOOD_KEY not in open(comp_env).read(), str(body))
        code, body, _ = req("POST", BASE + "/connections/box/verify", {},
                            headers=svc)
        check("box verify after disconnect fails again",
              code == 200 and body.get("ok") is False, str(body))

        code, body, _ = req("POST", BASE + "/selfcheck/run", {"probes": False},
                            headers=svc)
        ro_ids = [i["id"] for i in body.get("readonly", [])]
        check("selfcheck readonly runs (hermes ok)",
              code == 200 and "hermes-health" in ro_ids
              and next(i for i in body["readonly"] if i["id"] == "hermes-health")["status"] == "ok",
              str(ro_ids))
        check("selfcheck manual tier present",
              len(body.get("manual", [])) == 3)
        code, body, _ = req("POST", BASE + "/selfcheck/run", {"probes": True},
                            headers=svc)
        probe = next((i for i in body.get("probe", []) if i["id"] == "probe-session"), None)
        check("probe tier full chain ok against fake hermes",
              probe is not None and probe["status"] == "ok", str(probe))

        code, body, _ = req("POST", BASE + "/modules/writeGate/toggle",
                            {"enabled": False}, headers=svc)
        check("writeGate disable without confirm is 409",
              code == 409 and body.get("needConfirm") is True, str(body))
        code, body, _ = req("POST", BASE + "/modules/device/toggle",
                            {"enabled": False, "confirm": True}, headers=svc)
        check("toggle with control channel down is honest 503",
              code == 503, str(body))

        code, body, _ = req("GET", BASE + "/version", headers=svc)
        check("version view: hermes actual undetected -> null",
              code == 200 and body["hermes"]["expected"] == "v0.23.0"
              and body["hermes"]["actual"] is None
              and body["companion"]["apiLevel"] == 1, str(body)[:200])

        if fake_dev is not None:
            code, body, _ = req("GET", BASE + "/sync", headers=svc)
            ds = body.get("datasets", [])
            check("sync view: five datasets, state only, no records",
                  code == 200 and len(ds) == 5
                  and ds[0]["dataset"] == "contacts"
                  and ds[0]["item_count"] == 7
                  and "displayName" not in json.dumps(body)
                  and "phones" not in json.dumps(body), str(body)[:200])
            code, body, _ = req("POST", BASE + "/sync/delete", {},
                                headers=auth)
            check("sync delete via cookie without CSRF is 403",
                  code == 403, str(body))
            code, body, _ = req("POST", BASE + "/sync/delete", {},
                                headers=svc)
            check("sync delete proxies to device module",
                  code == 200 and body.get("ok") is True
                  and FAKE_DEVICE_CALLS == ["/device/sync/delete"],
                  str(body))

        # gateway channels (1.0.5): read-only proxy, contract shape,
        # admin credential used server-side, channel keys never leak
        code, gw, _ = req("GET", BASE + "/gateway-channels", headers=svc)
        chans = gw.get("channels") or []
        check("gateway-channels 200 + contract shape",
              code == 200 and len(chans) == 2
              and chans[0].get("id") == "14"
              and chans[0].get("name") == "DeepSeek 官方"
              and chans[0].get("status") == "enabled"
              and chans[0].get("models") == ["deepseek-flash",
                                             "deepseek-v4-pro"]
              and chans[0].get("priority") == 5
              and chans[0].get("weight") == 100
              and chans[0].get("group") == "DeepSeek"
              and chans[1].get("status") == "disabled",
              f"{code} {str(gw)[:240]}")
        check("gateway-channels never forwards channel keys",
              code == 200 and "sk-must-never-leak" not in str(gw)
              and "sk-also-secret" not in str(gw)
              and all("key" not in c for c in chans), str(gw)[:240])
        check("gateway admin credential presented server-side",
              bool(NEWAPI_CALLS)
              and NEWAPI_CALLS[-1]["auth"] == "Bearer newapi-admin-test"
              and NEWAPI_CALLS[-1]["user"] == "1",
              str(NEWAPI_CALLS[-1:]))
        code, _, _ = req("GET", BASE + "/gateway-channels")
        check("gateway-channels without auth is 401", code == 401)

        # rate limit keys on the real client IP (1.0.34): the test
        # peer is loopback, like nginx in production, so the bucket
        # must follow X-Real-IP — and a different real IP must not be
        # locked out by someone else's failures.
        hdr_a = {"X-Real-IP": "203.0.113.10"}
        codes = []
        for _ in range(5):
            c, _, _ = req("POST", BASE + "/login",
                          {"method": "password", "password": "wrong"},
                          headers=hdr_a)
            codes.append(c)
        c6, _, _ = req("POST", BASE + "/login",
                       {"method": "password", "password": "new-pass-456"},
                       headers=hdr_a)
        check("loopback peer: bucket follows X-Real-IP (5x401 then 429)",
              codes == [401] * 5 and c6 == 429, f"{codes} then {c6}")
        c, body, _ = req("POST", BASE + "/login",
                         {"method": "password", "password": "new-pass-456"},
                         headers={"X-Real-IP": "203.0.113.11"})
        check("different X-Real-IP has its own bucket (not locked out)",
              c == 200 and body.get("ok"), f"{c} {body}")
        c, _, _ = req("POST", BASE + "/web-login", {"password": "wrong"},
                      headers=hdr_a)
        check("web-login shares the per-IP bucket (locked IP -> 429)",
              c == 429, f"{c}")

        # rate limit last: burn the password bucket
        codes = []
        for _ in range(5):
            c, _, _ = req("POST", BASE + "/login",
                          {"method": "password", "password": "wrong"})
            codes.append(c)
        c6, _, _ = req("POST", BASE + "/login",
                       {"method": "password", "password": "new-pass-456"})
        check("5 wrong passwords -> 401s, 6th attempt -> 429",
              codes == [401] * 5 and c6 == 429, f"{codes} then {c6}")

        code, _, _ = req("POST", BASE + "/logout", {}, headers=auth)
        code2, sess, _ = req("GET", BASE + "/session", headers=auth)
        check("logout kills session", code == 200 and sess.get("authenticated") is False)
    finally:
        front.terminate()
        try:
            front.wait(timeout=8)
        except subprocess.TimeoutExpired:
            front.kill()
        fake.shutdown()
        fake_newapi.shutdown()
        fake_dash.shutdown()
        if fake_dev is not None:
            fake_dev.shutdown()
    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
