#!/usr/bin/env python3
"""Channels bridge Feishu self-test (channels phase 2).

Boots channels_bridge.py as a subprocess against a temp
HERMES_HOME, then asserts the surviving contract:

- status starts honest: feishu open + token kind +
  not_configured; weixin still frozen; whatsapp still the
  closed qr shell;
- POST /channels/credentials is RETIRED （桥-2 步 A,
  2026-11-15): Feishu bodies (rejected pair, malformed
  open_id allowlist, missing secret, formerly valid pair)
  and Telegram bodies alike answer 404 with the gateway
  .env byte-identical afterwards (zero writes);
- the status READ side is unchanged: with the gateway .env /
  config.yaml seeded directly into the post-save Feishu
  shape, status reads configured + pending_restart, still
  NOT connected (connected only comes from the gateway
  runtime record).
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
BRIDGE = os.path.join(HERE, "channels_bridge.py")
if not os.path.exists(BRIDGE):
    BRIDGE = os.path.join(HERE, "..", "modules",
                          "channels_bridge.py")
KEY = "channels-feishu-selftest-key"
PORT = 18849
STUB_PORT = 18850
BASE = f"http://127.0.0.1:{PORT}"
GOOD_APP_ID = "cli_good_app"
GOOD_SECRET = "test-good-secret"
BAD_SECRET = "test-bad-secret"
GOOD_TG = "123456789:AAE" + "x" * 30

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


class StubFeishu(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _reply(self, payload, code=200):
        raw = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            body = {}
        if self.path == ("/open-apis/auth/v3/"
                        "tenant_access_token/internal"):
            if body.get("app_id") == GOOD_APP_ID \
                    and body.get("app_secret") == GOOD_SECRET:
                self._reply({"code": 0, "msg": "ok",
                             "tenant_access_token": "t-stub",
                             "expire": 7200})
            else:
                self._reply({"code": 10014,
                             "msg": "app secret invalid"})
        else:
            self._reply({"code": 404}, 404)

    def do_GET(self):
        if self.path == "/open-apis/bot/v3/info":
            if self.headers.get("Authorization") \
                    == "Bearer t-stub":
                self._reply({"code": 0, "msg": "ok", "bot": {
                    "app_name": "小天测试助手",
                    "open_id": "ou_bot"}})
            else:
                self._reply({"code": 99991663,
                             "msg": "tenant token invalid"})
        elif self.path.startswith(f"/bot{GOOD_TG}/getMe"):
            self._reply({"ok": True, "result": {
                "id": 123456789, "is_bot": True,
                "first_name": "OneDay Test Bot",
                "username": "oneday_test_bot"}})
        else:
            self._reply({"ok": False, "error_code": 401,
                         "description": "Unauthorized"}, 401)


def main():
    stub = ThreadingHTTPServer(("127.0.0.1", STUB_PORT),
                               StubFeishu)
    threading.Thread(target=stub.serve_forever,
                     daemon=True).start()

    tmp = tempfile.mkdtemp(prefix="channels-feishu-selftest-")
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
                   [("f1", "feishu"), ("t1", "telegram")])
    db.commit()
    db.close()

    env = dict(os.environ,
               CHANNELS_BRIDGE_KEY=KEY,
               CHANNELS_PORT=str(PORT),
               HERMES_HOME=tmp,
               CHANNELS_FEISHU_API_BASE=
               f"http://127.0.0.1:{STUB_PORT}",
               CHANNELS_TELEGRAM_API_BASE=
               f"http://127.0.0.1:{STUB_PORT}",
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

        code, view = call("GET", "/channels/status")
        plats = {p["platform"]: p for p in view["platforms"]}
        f = plats["feishu"]
        check("feishu open, token kind, not_configured",
              f["open"] is True and f["kind"] == "token"
              and f["state"] == "not_configured"
              and f["configured"] is False
              and f["connected"] is False, f"got {f}")
        check("feishu session count from state.db",
              f["sessionCount"] == 1)
        check("weixin still frozen",
              plats["weixin"]["state"] == "frozen")
        check("whatsapp is qr kind",
              plats["whatsapp"]["kind"] == "qr")

        # ---- credentials endpoint RETIRED （桥-2 步 A) ----
        env_before = open(env_path).read()
        retired_bodies = [
            ("feishu rejected pair",
             {"platform": "feishu",
              "fields": {"appId": GOOD_APP_ID,
                         "appSecret": BAD_SECRET}}),
            ("feishu malformed open_id allowlist",
             {"platform": "feishu",
              "fields": {"appId": GOOD_APP_ID,
                         "appSecret": GOOD_SECRET},
              "allowedUserIds": ["not-an-open-id"]}),
            ("feishu missing appSecret",
             {"platform": "feishu",
              "fields": {"appId": GOOD_APP_ID}}),
            ("feishu formerly valid pair",
             {"platform": "feishu",
              "fields": {"appId": GOOD_APP_ID,
                         "appSecret": GOOD_SECRET},
              "allowedUserIds": ["ou_user1", "on_user2"]}),
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

        # Status READ side against the post-save Feishu shape
        # seeded directly into the fixtures.
        with open(env_path, "a", encoding="utf-8") as fh:
            fh.write(f"FEISHU_APP_ID={GOOD_APP_ID}\n"
                     f"FEISHU_APP_SECRET={GOOD_SECRET}\n"
                     "FEISHU_CONNECTION_MODE=websocket\n"
                     "FEISHU_ALLOW_ALL_USERS=false\n"
                     "FEISHU_ALLOWED_USERS=ou_user1,on_user2\n")
        with open(config_path, "a", encoding="utf-8") as fh:
            fh.write("platforms:\n  feishu:\n"
                     "    enabled: true\n")
        env_after = open(env_path).read()
        check("seeded env holds feishu keys, kept other keys",
              f"FEISHU_APP_ID={GOOD_APP_ID}" in env_after
              and f"FEISHU_APP_SECRET={GOOD_SECRET}" in env_after
              and "FEISHU_CONNECTION_MODE=websocket" in env_after
              and "FEISHU_ALLOW_ALL_USERS=false" in env_after
              and "FEISHU_ALLOWED_USERS=ou_user1,on_user2"
                  in env_after
              and "OTHER_KEY=keepme" in env_after,
              f"env={env_after}")
        config_after = open(config_path).read()
        check("seeded config enables feishu, comments survive",
              "feishu:" in config_after
              and "enabled: true" in config_after
              and "comments must survive" in config_after)

        code, view = call("GET", "/channels/status")
        f = {p["platform"]: p
             for p in view["platforms"]}["feishu"]
        check("seeded shape: configured, pending, NOT connected",
              f["configured"] is True
              and f["connected"] is False
              and f["state"] == "pending_restart",
              f"got {f}")

        # telegram bodies hit the same retired 404
        code, view = call("POST", "/channels/credentials",
                          {"platform": "telegram",
                           "fields": {"botToken":
                                      "123456789:ZZZ"
                                      + "y" * 30}})
        check("credentials retired 404: telegram rejected",
              code == 404, f"got {code} {view}")
        code, view = call("POST", "/channels/credentials",
                          {"platform": "telegram",
                           "fields": {"botToken": GOOD_TG}})
        check("credentials retired 404: telegram valid",
              code == 404, f"got {code} {view}")
    finally:
        try:
            proc.terminate()
        except Exception:
            pass
        stub.shutdown()
    print(f"channels_bridge_feishu_selftest: {passed} passed, "
          f"{failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
