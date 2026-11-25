#!/usr/bin/env python3
"""Channels bridge special-batch self-test (email + WhatsApp).

Boots channels_bridge.py as a subprocess against a temp
HERMES_HOME and a stub Dashboard (WhatsApp onboarding API):

- email credentials: POST /channels/credentials is RETIRED
  （桥-2 步 A, 2026-11-15) -- every email body (missing
  allowlist, invalid allowlist entry, IMAP-rejected code,
  SMTP-rejected code, formerly valid custom save, gmail
  preset save) answers 404 and writes nothing; the email
  status READ side is then exercised against the post-save
  env/config shape seeded directly into the fixtures
  (configured + pending_restart, never connected). The
  IMAP/SMTP stub servers remain booted but are no longer
  consulted by the retired endpoint.
- whatsapp QR: start returns the stub's QR payload; status
  polls surface the ROTATED payload; once the stub reports
  connected, the bridge calls the dashboard apply step exactly
  once (Bearer token carried) and reports applied; cancel
  issues the DELETE. Without a dashboard session token,
  qr/start fails honestly with 503.
"""
import base64
import json
import os
import socketserver
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
KEY = "channels-special-selftest-key"
PORT = 18752
DASH_PORT = 18762
IMAP_PORT = 11143
SMTP_PORT = 11587
BASE = f"http://127.0.0.1:{PORT}"
DASH_TOKEN = "dash-special-token"
GOOD_CODE = "GOOD-AUTH-CODE-16"
SMTP_BAD_CODE = "IMAPOK-SMTPBAD-16"
ADDRESS = "owner@example-mail.com"
GMAIL_ADDRESS = "owner@gmail.com"
SENDER = "friend@example.com"

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


# ---------------------------------------------------------- mail stubs

class IMAPHandler(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b"* OK stub IMAP ready\r\n")
        for raw in self.rfile:
            line = raw.decode("utf-8", "replace").strip()
            parts = line.split(" ")
            if len(parts) < 2:
                continue
            tag, cmd = parts[0], parts[1].upper()
            if cmd == "LOGIN":
                ok = GOOD_CODE in line or SMTP_BAD_CODE in line
                word = "OK" if ok else "NO"
                msg = "LOGIN completed" if ok else "LOGIN failed"
                self.wfile.write(
                    f"{tag} {word} {msg}\r\n".encode())
            elif cmd == "LOGOUT":
                self.wfile.write(b"* BYE logging out\r\n")
                self.wfile.write(
                    f"{tag} OK LOGOUT completed\r\n".encode())
                return
            elif cmd == "CAPABILITY":
                self.wfile.write(
                    b"* CAPABILITY IMAP4rev1\r\n")
                self.wfile.write(
                    f"{tag} OK CAPABILITY completed\r\n".encode())
            else:
                self.wfile.write(
                    f"{tag} OK {cmd} completed\r\n".encode())


class SMTPHandler(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b"220 stub ESMTP ready\r\n")
        awaiting_password = False
        for raw in self.rfile:
            line = raw.decode("utf-8", "replace").strip()
            up = line.upper()
            if awaiting_password:
                awaiting_password = False
                try:
                    pw = base64.b64decode(line).decode()
                except Exception:
                    pw = ""
                if pw == GOOD_CODE:
                    self.wfile.write(
                        b"235 2.7.0 Authentication successful\r\n")
                else:
                    self.wfile.write(
                        b"535 5.7.8 Authentication credentials "
                        b"invalid\r\n")
                continue
            if up.startswith("EHLO") or up.startswith("HELO"):
                self.wfile.write(
                    b"250-stub greets\r\n250 AUTH LOGIN\r\n")
            elif up.startswith("AUTH LOGIN"):
                self.wfile.write(b"334 UGFzc3dvcmQ6\r\n")
                awaiting_password = True
            elif up.startswith("QUIT"):
                self.wfile.write(b"221 2.0.0 Bye\r\n")
                return
            else:
                self.wfile.write(b"250 OK\r\n")


class StubDashboard(BaseHTTPRequestHandler):
    wa_connected = False
    hits = []

    def log_message(self, *a):
        pass

    def _json(self, code, payload):
        raw = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        type(self).hits.append(
            ("POST", self.path,
             self.headers.get("Authorization")))
        if self.path == "/api/gateway/restart":
            return self._json(200, {"ok": True, "pid": 777})
        if self.path == ("/api/messaging/whatsapp/onboarding"
                         "/start"):
            return self._json(200, {
                "pairing_id": "wp-1", "status": "waiting",
                "qr_payload": "QR-PAYLOAD-ONE",
                "expires_at": 1999999999, "mode": "self-chat",
                "allowed_users": []})
        if self.path == ("/api/messaging/whatsapp/onboarding"
                         "/wp-1/apply"):
            return self._json(200, {
                "ok": True, "needs_restart": True,
                "restart_started": True})
        return self._json(404, {"error": "nope"})

    def do_GET(self):
        type(self).hits.append(
            ("GET", self.path,
             self.headers.get("Authorization")))
        if self.path == ("/api/messaging/whatsapp/onboarding"
                         "/wp-1"):
            if type(self).wa_connected:
                return self._json(200, {
                    "pairing_id": "wp-1",
                    "status": "connected",
                    "qr_payload": None, "expires_at": None,
                    "mode": "self-chat",
                    "account_name": "Self Tester",
                    "account_phone": "+8613800000000"})
            return self._json(200, {
                "pairing_id": "wp-1", "status": "waiting",
                "qr_payload": "QR-PAYLOAD-TWO",
                "expires_at": 1999999999, "mode": "self-chat"})
        return self._json(404, {"error": "nope"})

    def do_DELETE(self):
        type(self).hits.append(
            ("DELETE", self.path,
             self.headers.get("Authorization")))
        return self._json(200, {"ok": True})


def wait_up(proc):
    for _ in range(40):
        try:
            code, _ = call("GET", "/health", key=None)
            if code == 200:
                return True
        except Exception:
            time.sleep(0.25)
    print(proc.stdout.read() if proc and proc.stdout else "")
    return False


def main():
    imap = socketserver.ThreadingTCPServer(
        ("127.0.0.1", IMAP_PORT), IMAPHandler)
    smtp = socketserver.ThreadingTCPServer(
        ("127.0.0.1", SMTP_PORT), SMTPHandler)
    for srv in (imap, smtp):
        srv.daemon_threads = True
        threading.Thread(target=srv.serve_forever,
                         daemon=True).start()
    dash = ThreadingHTTPServer(("127.0.0.1", DASH_PORT),
                               StubDashboard)
    threading.Thread(target=dash.serve_forever,
                     daemon=True).start()

    tmp = tempfile.mkdtemp(prefix="channels-special-")
    env_path = os.path.join(tmp, ".env")
    with open(env_path, "w", encoding="utf-8") as fh:
        fh.write("# gateway secrets\nOTHER_KEY=keepme\n")
    config_path = os.path.join(tmp, "config.yaml")
    with open(config_path, "w", encoding="utf-8") as fh:
        fh.write("# production config -- comments must survive\n"
                 "model:\n  default: test\n")

    env = dict(os.environ,
               CHANNELS_BRIDGE_KEY=KEY,
               CHANNELS_PORT=str(PORT),
               HERMES_HOME=tmp,
               CHANNELS_TRACE_DIR=os.path.join(tmp, "traces"),
               ONEDAY_BASE="http://127.0.0.1:9",
               HERMES_DASHBOARD_SESSION_TOKEN=DASH_TOKEN,
               CHANNELS_DASHBOARD_BASE=
               f"http://127.0.0.1:{DASH_PORT}")
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True)
    try:
        if not wait_up(proc):
            raise SystemExit("bridge did not come up")

        code, health = call("GET", "/health", key=None)
        check("health reports whatsappQr ready",
              health.get("whatsappQr") is True, f"got {health}")

        code, view = call("GET", "/channels/status")
        plats = {p["platform"]: p for p in view["platforms"]}
        check("email open for pairing",
              plats["email"]["open"] is True)
        check("whatsapp open for pairing",
              plats["whatsapp"]["open"] is True)
        check("whatsapp starts not_configured",
              plats["whatsapp"]["state"] == "not_configured"
              and plats["whatsapp"]["connected"] is False)

        fields = {"address": ADDRESS, "password": GOOD_CODE,
                  "imapHost": "127.0.0.1",
                  "imapPort": str(IMAP_PORT),
                  "smtpHost": "127.0.0.1",
                  "smtpPort": str(SMTP_PORT)}
        env_before = open(env_path).read()

        # ---- credentials endpoint RETIRED （桥-2 步 A) ----
        bad_imap = dict(fields, password="WRONG-CODE-0000")
        bad_smtp = dict(fields, password=SMTP_BAD_CODE)
        gmail_fields = dict(fields, address=GMAIL_ADDRESS)
        retired_bodies = [
            ("email without allowlist",
             {"platform": "email", "fields": fields,
              "preset": "custom"}),
            ("email non-address allowlist entry",
             {"platform": "email", "fields": fields,
              "preset": "custom",
              "allowedUserIds": ["not-an-address"]}),
            ("email imap-rejected code",
             {"platform": "email", "fields": bad_imap,
              "preset": "custom", "allowedUserIds": [SENDER]}),
            ("email smtp-rejected code",
             {"platform": "email", "fields": bad_smtp,
              "preset": "custom", "allowedUserIds": [SENDER]}),
            ("email formerly valid custom save",
             {"platform": "email", "fields": fields,
              "preset": "custom", "allowedUserIds": [SENDER]}),
            ("email gmail preset save",
             {"platform": "email", "fields": gmail_fields,
              "preset": "gmail", "allowedUserIds": [SENDER]}),
        ]
        for label, body in retired_bodies:
            code, view = call("POST", "/channels/credentials",
                              body)
            check(f"credentials retired 404: {label}",
                  code == 404, f"got {code} {view}")
            check(f"retired 404 wrote nothing: {label}",
                  open(env_path).read() == env_before)

        # Email status READ side against the post-save shape
        # seeded directly into the fixtures (custom-preset
        # trust posture included, as the retired writer left
        # it; EMAIL_ALLOW_ALL_USERS was never part of it).
        with open(env_path, "a", encoding="utf-8") as fh:
            fh.write(f"EMAIL_ADDRESS={ADDRESS}\n"
                     f"EMAIL_PASSWORD={GOOD_CODE}\n"
                     "EMAIL_IMAP_HOST=127.0.0.1\n"
                     f"EMAIL_IMAP_PORT={IMAP_PORT}\n"
                     "EMAIL_SMTP_HOST=127.0.0.1\n"
                     f"EMAIL_SMTP_PORT={SMTP_PORT}\n"
                     f"EMAIL_ALLOWED_USERS={SENDER}\n"
                     "EMAIL_TRUST_FROM_HEADER=true\n")
        with open(config_path, "a", encoding="utf-8") as fh:
            fh.write("platforms:\n  email:\n"
                     "    enabled: true\n")
        env_after = open(env_path).read()
        check("seeded env holds email fields + allowlist",
              f"EMAIL_ADDRESS={ADDRESS}" in env_after
              and f"EMAIL_PASSWORD={GOOD_CODE}" in env_after
              and f"EMAIL_IMAP_PORT={IMAP_PORT}" in env_after
              and f"EMAIL_SMTP_PORT={SMTP_PORT}" in env_after
              and f"EMAIL_ALLOWED_USERS={SENDER}" in env_after
              and "OTHER_KEY=keepme" in env_after)
        check("seeded custom posture: trust-header, no authserv",
              "EMAIL_TRUST_FROM_HEADER=true" in env_after
              and "EMAIL_AUTHSERV_ID" not in env_after)
        check("allow-all absent from seeded shape",
              "EMAIL_ALLOW_ALL_USERS" not in env_after)

        code, view = call("GET", "/channels/status")
        em = {p["platform"]: p
              for p in view["platforms"]}["email"]
        check("seeded shape: configured, pending, NOT connected",
              em["configured"] is True
              and em["connected"] is False
              and em["state"] == "pending_restart", f"got {em}")

        # ---------------- WhatsApp QR flow ----------------
        code, view = call("POST", "/channels/qr/start",
                          {"platform": "telegram"})
        check("qr start refuses non-qr platform 400",
              code == 400, f"got {code} {view}")

        code, view = call("POST", "/channels/qr/start",
                          {"platform": "whatsapp"})
        check("qr start returns first payload", code == 200
              and view.get("status") == "waiting"
              and view.get("qrPayload") == "QR-PAYLOAD-ONE",
              f"got {code} {view}")
        check("qr start carried pairing id",
              view.get("pairingId") == "wp-1")

        code, view = call("GET", "/channels/qr/status")
        check("qr status surfaces rotated payload",
              code == 200
              and view.get("qrPayload") == "QR-PAYLOAD-TWO",
              f"got {code} {view}")

        StubDashboard.wa_connected = True
        code, view = call("GET", "/channels/qr/status")
        check("connected status reported with account",
              code == 200 and view.get("status") == "connected"
              and view.get("accountName") == "Self Tester",
              f"got {code} {view}")
        check("apply called once on connected",
              view.get("applied") is True)
        apply_hits = [h for h in StubDashboard.hits
                      if h[1].endswith("/apply")]
        check("dashboard saw exactly one apply",
              len(apply_hits) == 1
              and apply_hits[0][2] == f"Bearer {DASH_TOKEN}",
              f"hits={apply_hits}")
        code, view = call("GET", "/channels/qr/status")
        apply_hits = [h for h in StubDashboard.hits
                      if h[1].endswith("/apply")]
        check("second poll does not re-apply",
              len(apply_hits) == 1 and view.get("applied")
              is True)

        # Module restart mid-pairing must not orphan the
        # session: a fresh process restores the pairing id
        # from the state volume and keeps reporting on the
        # SAME dashboard session (no second apply).
        proc.terminate()
        proc.wait(timeout=5)
        proc = subprocess.Popen(
            [sys.executable, BRIDGE], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True)
        if not wait_up(proc):
            raise SystemExit("bridge did not come up (reboot)")
        code, view = call("GET", "/channels/qr/status")
        apply_hits = [h for h in StubDashboard.hits
                      if h[1].endswith("/apply")]
        check("after restart: session restored, still applied",
              code == 200 and view.get("status") == "connected"
              and view.get("applied") is True
              and len(apply_hits) == 1,
              f"got {code} {view} applies={len(apply_hits)}")

        code, view = call("POST", "/channels/qr/cancel",
                          {"platform": "whatsapp"})
        delete_hits = [h for h in StubDashboard.hits
                       if h[0] == "DELETE"]
        check("cancel issues dashboard DELETE",
              code == 200 and len(delete_hits) == 1,
              f"got {code} hits={delete_hits}")
        check("dashboard token never echoed in qr views",
              DASH_TOKEN not in json.dumps(view))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            pass

    # ---- second boot: no dashboard token -> honest 503 ----
    env2 = dict(env)
    env2.pop("HERMES_DASHBOARD_SESSION_TOKEN", None)
    proc2 = subprocess.Popen(
        [sys.executable, BRIDGE], env=env2,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True)
    try:
        if not wait_up(proc2):
            raise SystemExit("bridge (no token) did not come up")
        code, health = call("GET", "/health", key=None)
        check("health without token: whatsappQr false",
              health.get("whatsappQr") is False)
        code, view = call("POST", "/channels/qr/start",
                          {"platform": "whatsapp"})
        check("qr start without token fails honest 503",
              code == 503, f"got {code} {view}")
    finally:
        proc2.terminate()
        imap.shutdown()
        smtp.shutdown()
        dash.shutdown()
    print(f"channels_bridge_special_selftest: {passed} passed, "
          f"{failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
