#!/usr/bin/env python3
"""Channels bridge self-test (channels phase 1).

Boots channels_bridge.py as a subprocess against a temp
HERMES_HOME (fake .env / config.yaml / gateway_state.json /
state.db), then asserts the surviving contract end to end:

- status starts honest: telegram not_configured, weixin frozen;
- POST /channels/credentials is RETIRED （桥-2 步 A,
  2026-11-15): every credential body -- malformed, platform-
  rejected, or formerly valid, for telegram and the whole
  token batch -- answers 404 and writes NOTHING to the
  gateway config (credentials now go through the Dashboard
  direct path);
- the status READ side is unchanged: with the gateway .env /
  config.yaml seeded directly into the post-save shape (the
  exact state the retired writer used to produce), status
  reads configured with state=pending_restart -- NOT
  connected;
- connected is reported only when gateway_state.json itself
  says the adapter is connected;
- instant apply no longer rides the credentials endpoint:
  even with a dashboard session token provisioned, a
  credentials POST stays 404 and triggers NO gateway restart
  call (the token now serves only the QR onboarding paths,
  health still reports instantApply/whatsappQr).
"""
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
# Staged layout (run_bridge_selftests.sh) puts the module copy
# beside the test; in the repo it lives in ../modules.
BRIDGE = os.path.join(HERE, "channels_bridge.py")
if not os.path.exists(BRIDGE):
    BRIDGE = os.path.join(HERE, "..", "modules",
                          "channels_bridge.py")
KEY = "channels-selftest-key"
PORT = 18749
STUB_PORT = 18750
DASH_PORT = 18751
PLAT_PORT = 18752
DASH_TOKEN = "dash-selftest-token"
BASE = f"http://127.0.0.1:{PORT}"
GOOD_TOKEN = "test-good-token" + "x" * 30
BAD_TOKEN = "test-bad-token" + "y" * 30

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def call(method, path, body=None, key=KEY):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data,
                                 method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


class StubTelegram(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.startswith(f"/bot{GOOD_TOKEN}/getMe"):
            payload = {"ok": True, "result": {
                "id": 123456789, "is_bot": True,
                "first_name": "OneDay Test Bot",
                "username": "oneday_test_bot"}}
            code = 200
        else:
            payload = {"ok": False, "error_code": 401,
                       "description": "Unauthorized"}
            code = 401
        raw = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


class StubPlatforms(BaseHTTPRequestHandler):
    """One stub standing in for the four token-batch platforms'
    official verification endpoints (dingtalk access-token
    exchange, qqbot access-token exchange, discord bot identity,
    slack auth.test + apps.connections.open). Each accepts
    exactly one good credential and rejects the rest the way the
    real platform does."""

    def log_message(self, *a):
        pass

    def _reply(self, code, payload):
        raw = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return {}

    def do_POST(self):
        body = self._body()
        if self.path == "/v1.0/oauth2/accessToken":
            if body.get("appKey") == "ding-good" \
                    and body.get("appSecret") == "ding-secret":
                self._reply(200, {"accessToken": "dt-token",
                                  "expiresIn": 7200})
            else:
                self._reply(400, {"code": "invalid.client",
                                  "message": "bad credentials"})
        elif self.path == "/app/getAppAccessToken":
            if body.get("appId") == "qq-good" \
                    and body.get("clientSecret") == "qq-secret":
                self._reply(200, {"access_token": "qq-token",
                                  "expires_in": "7200"})
            else:
                self._reply(200, {"code": 100016,
                                  "message": "invalid client_secret"})
        elif self.path == "/api/auth.test":
            if self.headers.get("Authorization") \
                    == "Bearer xoxb-good":
                self._reply(200, {"ok": True, "team": "T1",
                                  "user": "hermes"})
            else:
                self._reply(200, {"ok": False,
                                  "error": "invalid_auth"})
        elif self.path == "/api/apps.connections.open":
            if self.headers.get("Authorization") \
                    == "Bearer xapp-good":
                self._reply(200, {"ok": True,
                                  "url": "wss://stub.invalid"})
            else:
                self._reply(200, {"ok": False,
                                  "error": "invalid_auth"})
        else:
            self._reply(404, {"error": "no such path"})

    def do_GET(self):
        if self.path == "/api/v10/users/@me":
            if self.headers.get("Authorization") \
                    == "Bot discord-good-token":
                self._reply(200, {"id": "111",
                                  "username": "hermes_test_bot",
                                  "bot": True})
            else:
                self._reply(401, {"message": "401: Unauthorized"})
        else:
            self._reply(404, {"error": "no such path"})


class StubDashboard(BaseHTTPRequestHandler):
    mode = "ok"
    hits = []

    def log_message(self, *a):
        pass

    def do_POST(self):
        type(self).hits.append(
            (self.path, self.headers.get("Authorization")))
        if type(self).mode == "ok":
            payload, code = {"ok": True, "pid": 424242}, 200
        else:
            payload, code = {"error": "unauthorized"}, 401
        raw = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


def main():
    stub = ThreadingHTTPServer(("127.0.0.1", STUB_PORT),
                               StubTelegram)
    threading.Thread(target=stub.serve_forever,
                     daemon=True).start()
    dash = ThreadingHTTPServer(("127.0.0.1", DASH_PORT),
                               StubDashboard)
    threading.Thread(target=dash.serve_forever,
                     daemon=True).start()
    plat = ThreadingHTTPServer(("127.0.0.1", PLAT_PORT),
                               StubPlatforms)
    threading.Thread(target=plat.serve_forever,
                     daemon=True).start()

    tmp = tempfile.mkdtemp(prefix="channels-selftest-")
    env_path = os.path.join(tmp, ".env")
    with open(env_path, "w", encoding="utf-8") as fh:
        fh.write("# gateway secrets\nOTHER_KEY=keepme\n")
    config_path = os.path.join(tmp, "config.yaml")
    with open(config_path, "w", encoding="utf-8") as fh:
        fh.write("# production config -- comments must survive\n"
                 "model:\n  default: test\n")
    db = sqlite3.connect(os.path.join(tmp, "state.db"))
    db.execute("CREATE TABLE sessions (id TEXT, source TEXT)")
    db.executemany("INSERT INTO sessions VALUES (?, ?)",
                   [("s1", "telegram"), ("s2", "telegram"),
                    ("s3", "api_server")])
    db.commit()
    db.close()

    env = dict(os.environ,
               CHANNELS_BRIDGE_KEY=KEY,
               CHANNELS_PORT=str(PORT),
               HERMES_HOME=tmp,
               CHANNELS_TELEGRAM_API_BASE=
               f"http://127.0.0.1:{STUB_PORT}",
               CHANNELS_DINGTALK_API_BASE=
               f"http://127.0.0.1:{PLAT_PORT}",
               CHANNELS_QQ_API_BASE=
               f"http://127.0.0.1:{PLAT_PORT}",
               CHANNELS_DISCORD_API_BASE=
               f"http://127.0.0.1:{PLAT_PORT}",
               CHANNELS_SLACK_API_BASE=
               f"http://127.0.0.1:{PLAT_PORT}",
               CHANNELS_TRACE_DIR=os.path.join(tmp, "traces"),
               ONEDAY_BASE="http://127.0.0.1:9")
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True)
    try:
        for _ in range(40):
            try:
                code, _ = call("GET", "/health", key=None)
                if code == 200:
                    break
            except Exception:
                time.sleep(0.25)
        else:
            print(proc.stdout.read() if proc.stdout else "")
            raise SystemExit("bridge did not come up")

        code, _ = call("GET", "/channels/status", key=None)
        check("status requires bridge key", code == 401)

        code, view = call("GET", "/channels/status")
        plats = {p["platform"]: p for p in view["platforms"]}
        tg = plats["telegram"]
        check("initial telegram not_configured",
              tg["state"] == "not_configured"
              and tg["configured"] is False
              and tg["connected"] is False)
        check("telegram session count from state.db",
              tg["sessionCount"] == 2)
        check("weixin frozen",
              plats["weixin"]["state"] == "frozen")
        check("whatsapp is qr kind, open for pairing",
              plats["whatsapp"]["kind"] == "qr"
              and plats["whatsapp"]["open"] is True)
        check("gateway not running initially",
              view["gatewayRunning"] is False)
        for pid in ("dingtalk", "qqbot", "discord", "slack"):
            check(f"token batch {pid} open, not_configured",
                  plats[pid]["open"] is True
                  and plats[pid]["kind"] == "token"
                  and plats[pid]["state"] == "not_configured",
                  f"got {plats[pid]}")

        # ---- credentials endpoint RETIRED （桥-2 步 A) ----
        # Every credential body answers 404 and writes nothing,
        # whatever its shape: malformed, platform-rejected, or
        # formerly valid.
        env_before = open(env_path).read()
        retired_bodies = [
            ("malformed token",
             {"platform": "telegram",
              "fields": {"botToken": "not-a-token"}}),
            ("telegram-rejected token",
             {"platform": "telegram",
              "fields": {"botToken": BAD_TOKEN}}),
            ("unknown field",
             {"platform": "telegram",
              "fields": {"botToken": GOOD_TOKEN,
                         "surprise": "x"}}),
            ("frozen weixin",
             {"platform": "weixin", "fields": {}}),
            ("non-numeric allowed id",
             {"platform": "telegram",
              "fields": {"botToken": GOOD_TOKEN},
              "allowedUserIds": ["12a45"]}),
            ("dingtalk rejected pair",
             {"platform": "dingtalk",
              "fields": {"clientId": "ding-good",
                         "clientSecret": "ding-wrong"}}),
            ("qqbot rejected pair",
             {"platform": "qqbot",
              "fields": {"appId": "qq-good",
                         "clientSecret": "qq-wrong"}}),
            ("discord rejected token",
             {"platform": "discord",
              "fields": {"botToken": "discord-bad-token"}}),
            ("slack rejected bot token",
             {"platform": "slack",
              "fields": {"botToken": "xoxb-bad",
                         "appToken": "xapp-good"}}),
            ("slack rejected app token",
             {"platform": "slack",
              "fields": {"botToken": "xoxb-good",
                         "appToken": "xapp-bad"}}),
            ("dingtalk missing secret",
             {"platform": "dingtalk",
              "fields": {"clientId": "ding-good"}}),
        ]
        for label, body in retired_bodies:
            code, view = call("POST", "/channels/credentials",
                              body)
            check(f"credentials retired 404: {label}",
                  code == 404, f"got {code} {view}")
        check("retired endpoint wrote nothing",
              open(env_path).read() == env_before)
        check("config untouched by retired endpoint",
              "platforms:" not in open(config_path).read())

        code, view = call("POST", "/channels/credentials",
                          {"platform": "telegram",
                           "fields": {"botToken": GOOD_TOKEN},
                           "allowedUserIds": ["12345", "678"]})
        check("credentials retired 404: formerly valid token",
              code == 404, f"got {code} {view}")
        check("no dashboard token -> no restart call made",
              len(StubDashboard.hits) == 0)
        check("formerly valid token wrote nothing",
              open(env_path).read() == env_before)

        # Status READ side, exercised against the post-save
        # shape seeded directly into the fixtures (the exact
        # .env keys + config enablement the retired writer
        # used to produce; credentials themselves now arrive
        # via the Dashboard direct path).
        with open(env_path, "a", encoding="utf-8") as fh:
            fh.write(f"TELEGRAM_BOT_TOKEN={GOOD_TOKEN}\n"
                     "TELEGRAM_ALLOWED_USERS=12345,678\n")
        with open(config_path, "a", encoding="utf-8") as fh:
            fh.write("platforms:\n  telegram:\n"
                     "    enabled: true\n")
        env_after = open(env_path).read()
        check("seeded env holds token + allowed users, "
              "kept other keys",
              f"TELEGRAM_BOT_TOKEN={GOOD_TOKEN}" in env_after
              and "TELEGRAM_ALLOWED_USERS=12345,678" in env_after
              and "OTHER_KEY=keepme" in env_after)
        config_after = open(config_path).read()
        check("seeded config enables telegram, "
              "comments survive",
              "platforms:" in config_after
              and "enabled: true" in config_after
              and "comments must survive" in config_after)

        code, view = call("GET", "/channels/status")
        tg = {p["platform"]: p
              for p in view["platforms"]}["telegram"]
        check("after save: configured, pending, NOT connected",
              tg["configured"] is True
              and tg["connected"] is False
              and tg["state"] == "pending_restart",
              f"got {tg}")
        check("after save: identity satisfied",
              tg["needsIdentity"] is False)

        # ---- token batch: formerly accepted bodies ----
        # All four platforms' once-valid credential bodies hit
        # the same retired 404; then their post-save env/config
        # shape is seeded directly and the status read checked.
        batch_bodies = [
            ("dingtalk",
             {"clientId": "ding-good",
              "clientSecret": "ding-secret",
              "allowedUsers": "staff-001,staff-002"}),
            ("qqbot",
             {"appId": "qq-good", "clientSecret": "qq-secret",
              "allowedUsers": "openid-abc"}),
            ("discord",
             {"botToken": "discord-good-token",
              "allowedUsers": "123456789012345678"}),
            ("slack",
             {"botToken": "xoxb-good", "appToken": "xapp-good",
              "allowedUsers": "U012ABC"}),
        ]
        env_pre_batch = open(env_path).read()
        for pid, fields in batch_bodies:
            code, view = call("POST", "/channels/credentials",
                              {"platform": pid, "fields": fields})
            check(f"credentials retired 404: {pid} valid body",
                  code == 404, f"got {code} {view}")
        check("batch bodies wrote nothing",
              open(env_path).read() == env_pre_batch)
        with open(env_path, "a", encoding="utf-8") as fh:
            fh.write("DINGTALK_CLIENT_ID=ding-good\n"
                     "DINGTALK_CLIENT_SECRET=ding-secret\n"
                     "DINGTALK_ALLOWED_USERS=staff-001,staff-002\n"
                     "QQ_APP_ID=qq-good\n"
                     "QQ_CLIENT_SECRET=qq-secret\n"
                     "QQ_ALLOWED_USERS=openid-abc\n"
                     "DISCORD_BOT_TOKEN=test-discord-token"
                     "DISCORD_ALLOWED_USERS=123456789012345678\n"
                     "SLACK_BOT_TOKEN=xoxb-good\n"
                     "SLACK_APP_TOKEN=xapp-good\n"
                     "SLACK_ALLOWED_USERS=U012ABC\n")
        with open(config_path, "a", encoding="utf-8") as fh:
            for pid in ("dingtalk", "qqbot", "discord", "slack"):
                fh.write(f"  {pid}:\n    enabled: true\n")
        env_batch = open(env_path).read()
        check("seeded batch env keys present, other keys kept",
              "DINGTALK_CLIENT_ID=ding-good" in env_batch
              and "DINGTALK_CLIENT_SECRET=ding-secret" in env_batch
              and "DINGTALK_ALLOWED_USERS=staff-001,staff-002"
                  in env_batch
              and "QQ_APP_ID=qq-good" in env_batch
              and "QQ_CLIENT_SECRET=qq-secret" in env_batch
              and "QQ_ALLOWED_USERS=openid-abc" in env_batch
              and "DISCORD_BOT_TOKEN=test-discord-token" in env_batch
              and "DISCORD_ALLOWED_USERS=123456789012345678"
                  in env_batch
              and "SLACK_BOT_TOKEN=xoxb-good" in env_batch
              and "SLACK_APP_TOKEN=xapp-good" in env_batch
              and "SLACK_ALLOWED_USERS=U012ABC" in env_batch
              and "OTHER_KEY=keepme" in env_batch)
        code, view = call("GET", "/channels/status")
        plats = {p["platform"]: p for p in view["platforms"]}
        for pid in ("dingtalk", "qqbot", "discord", "slack"):
            check(f"{pid} after save: configured pending, "
                  "NOT connected",
                  plats[pid]["configured"] is True
                  and plats[pid]["connected"] is False
                  and plats[pid]["state"] == "pending_restart",
                  f"got {plats[pid]}")

        gw = {"gateway_state": "running", "platforms": {
            "telegram": {"state": "connected",
                         "error_message": None}}}
        with open(os.path.join(tmp, "gateway_state.json"),
                  "w", encoding="utf-8") as fh:
            json.dump(gw, fh)
        code, view = call("GET", "/channels/status")
        tg = {p["platform"]: p
              for p in view["platforms"]}["telegram"]
        check("gateway record connected -> status connected",
              tg["connected"] is True
              and tg["state"] == "connected")
        check("gatewayRunning true", view["gatewayRunning"]
              is True)

        gw["platforms"]["telegram"] = {
            "state": "error",
            "error_message": "getMe failed: Unauthorized"}
        with open(os.path.join(tmp, "gateway_state.json"),
                  "w", encoding="utf-8") as fh:
            json.dump(gw, fh)
        code, view = call("GET", "/channels/status")
        tg = {p["platform"]: p
              for p in view["platforms"]}["telegram"]
        check("gateway record error -> status error, not connected",
              tg["state"] == "error" and tg["connected"] is False
              and "Unauthorized" in tg.get("message", ""))

        code, _ = call("POST", "/channels/qr/start",
                       {"platform": "whatsapp"})
        check("qr start without dashboard token: honest 503",
              code == 503)

        # ---- instant apply: dashboard token provisioned ----
        proc.terminate()
        proc.wait(timeout=5)
        env2 = dict(env,
                    HERMES_DASHBOARD_SESSION_TOKEN=DASH_TOKEN,
                    CHANNELS_DASHBOARD_BASE=
                    f"http://127.0.0.1:{DASH_PORT}")
        proc2 = subprocess.Popen(
            [sys.executable, BRIDGE], env=env2,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True)
        try:
            health = None
            for _ in range(40):
                try:
                    code, health = call("GET", "/health",
                                        key=None)
                    if code == 200:
                        break
                except Exception:
                    time.sleep(0.25)
            check("health reports instantApply with token",
                  bool(health) and health.get("instantApply")
                  is True, f"got {health}")

            # Retired endpoint stays retired with the token
            # provisioned: 404, and NO gateway restart call is
            # triggered by it (instant apply now belongs to
            # the Dashboard's own save flow).
            code, view = call(
                "POST", "/channels/credentials",
                {"platform": "telegram",
                 "fields": {"botToken": GOOD_TOKEN}})
            check("credentials retired 404 with dash token",
                  code == 404, f"got {code} {view}")
            check("no restart call from retired endpoint",
                  len(StubDashboard.hits) == 0,
                  f"hits={StubDashboard.hits}")
            check("dashboard token never echoed",
                  DASH_TOKEN not in json.dumps(view))
            code, view = call("GET", "/channels/status")
            tg = {p["platform"]: p
                  for p in view["platforms"]}["telegram"]
            check("status still reads seeded configured shape",
                  tg["configured"] is True
                  and tg["connected"] is False,
                  f"got {tg}")

            StubDashboard.mode = "unauthorized"
            code, view = call(
                "POST", "/channels/credentials",
                {"platform": "telegram",
                 "fields": {"botToken": GOOD_TOKEN}})
            check("dashboard 401 mode: still retired 404",
                  code == 404, f"got {code} {view}")
            check("dashboard 401 mode: still no restart call",
                  len(StubDashboard.hits) == 0,
                  f"hits={StubDashboard.hits}")
        finally:
            proc2.terminate()
    finally:
        try:
            proc.terminate()
        except Exception:
            pass
        stub.shutdown()
        dash.shutdown()
        plat.shutdown()
    print(f"channels_bridge_selftest: {passed} passed, "
          f"{failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
