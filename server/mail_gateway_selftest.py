#!/usr/bin/env python3
"""Mail gateway (bar 1, queue 181) package selftest.

Run: python3 mail_gateway_selftest.py   (needs the `cryptography` package)

The whole loop runs against in-process fake IMAP/SMTP servers injected
through mail_gateway.set_factories: add account -> connection test ->
vault storage -> polling sync -> unified inbox -> password rotation ->
delete. Wire-level interop with a real mail server is NOT covered
here; that needs a real test mailbox before deployment.

The sample passwords are assembled at runtime from fragments so the
full strings never appear in any file; the final check greps the
whole temp tree for them and demands zero hits.
"""

import email.message
import imaplib
import json
import smtplib
import socket
import ssl
import sys
import tempfile
import types
from datetime import datetime, timezone
from pathlib import Path

from patches import credential_vault as vault
from patches import mail_gateway as mail

# Route the module's `from gateway.platforms import credential_vault`
# at the real vault in this package (container layout is flat).
_gateway = types.ModuleType("gateway")
_platforms = types.ModuleType("gateway.platforms")
_platforms.credential_vault = vault
_platforms.mail_gateway = mail
_gateway.platforms = _platforms
sys.modules.setdefault("gateway", _gateway)
sys.modules["gateway.platforms"] = _platforms

fails = []


def check(name, cond):
    print(f"  {'ok' if cond else 'FAIL'} {name}")
    if not cond:
        fails.append(name)


PW = "".join(["s3cr", "3t-TEST-", "pw-181"])
PW_NEW = "".join(["NEW-", "pw-r0tated-", "181"])
KEY = "selftest-mail-api-server-key"

tmp = Path(tempfile.mkdtemp(prefix="mail-gateway-selftest-"))
vault.STORE_PATH = tmp / "vault" / "entries.json"
vault.AUDIT_PATH = tmp / "vault" / "audit.jsonl"
vault.REQUESTS_PATH = tmp / "vault" / "requests.json"
mail.ACCOUNTS_PATH = tmp / "mail" / "accounts.json"
mail.MESSAGES_PATH = tmp / "mail" / "messages.json"
mail.DRAFTS_PATH = tmp / "mail" / "drafts.json"

# ---------------------------------------------------------------- fake servers
HOSTS: dict[str, dict[int, dict]] = {}


def _server(host, port, security, user, password):
    HOSTS.setdefault(host, {})[port] = {
        "security": security, "login_attempts": 0, "fail_fetch": set(),
        "accounts": {user: {"password": password,
                            "folders": {"INBOX": []}}},
    }


def _lookup(host, port):
    if host not in HOSTS:
        raise socket.gaierror(-2, "Name or service not known")
    if port not in HOSTS[host]:
        raise ConnectionRefusedError(111, "Connection refused")
    return HOSTS[host][port]


class FakeIMAP:
    def __init__(self, srv):
        self.srv = srv
        self.user = None
        self.folder = "INBOX"

    def login(self, user, password):
        self.srv["login_attempts"] += 1
        acct = self.srv["accounts"].get(user)
        if acct is None or acct["password"] != password:
            raise imaplib.IMAP4.error("LOGIN failed: AUTHENTICATIONFAILED invalid credentials")
        self.user = user
        return ("OK", [b"Logged in"])

    def list(self):
        return ("OK", [b'(\\HasNoChildren) "/" INBOX'])

    def select(self, folder):
        self.folder = folder
        msgs = self.srv["accounts"][self.user]["folders"][folder]
        return ("OK", [str(len(msgs)).encode()])

    def uid(self, command, *args):
        msgs = self.srv["accounts"][self.user]["folders"][self.folder]
        if command == "search":
            criteria = args[1] if len(args) > 1 else "ALL"
            picked = [m for m in msgs if criteria != "UNSEEN" or "\\Seen" not in m["flags"]]
            return ("OK", [" ".join(str(m["uid"]) for m in picked).encode()])
        if command == "fetch":
            uid = int(args[0])
            if uid in self.srv["fail_fetch"]:
                # Transient drop: this fetch fails once, then recovers.
                self.srv["fail_fetch"].discard(uid)
                raise ConnectionResetError(104, "Connection reset by peer")
            for seq, m in enumerate(msgs, 1):
                if m["uid"] == uid:
                    flags = " ".join(m["flags"])
                    meta = f"{seq} (UID {uid} FLAGS ({flags}) RFC822 {{{len(m['raw'])}}})".encode()
                    return ("OK", [(meta, m["raw"]), b")"])
            return ("OK", [])
        raise imaplib.IMAP4.error("unsupported")

    def logout(self):
        return ("BYE", [b"bye"])


class FakeSMTP:
    def __init__(self, srv):
        self.srv = srv

    def login(self, user, password):
        self.srv["login_attempts"] += 1
        acct = self.srv["accounts"].get(user)
        if acct is None or acct["password"] != password:
            raise smtplib.SMTPAuthenticationError(535, b"authentication failed")
        return (235, b"ok")

    def quit(self):
        return (221, b"bye")


def fake_imap_factory(host, port, security):
    srv = _lookup(host, port)
    if srv["security"] != security:
        raise ssl.SSLError("wrong version number")
    return FakeIMAP(srv)


def fake_smtp_factory(host, port, security):
    srv = _lookup(host, port)
    if srv["security"] != security:
        raise ssl.SSLError("wrong version number")
    return FakeSMTP(srv)


mail.set_factories(fake_imap_factory, fake_smtp_factory)


def raw_message(subject, body, day, uid, attachment=False):
    msg = email.message.EmailMessage()
    msg["From"] = "Boss <boss@example.test>"
    msg["To"] = "me@test.local"
    msg["Subject"] = subject
    msg["Message-ID"] = f"<m{uid}@example.test>"
    msg["Date"] = datetime(2026, 11, day, 9, 0, tzinfo=timezone.utc)
    msg.set_content(body)
    if attachment:
        msg.add_attachment(b"fake-pdf-bytes", maintype="application",
                           subtype="pdf", filename="report.pdf")
    return msg.as_bytes()


ADDR = "me@test.local"
_server("imap.test.local", 993, "ssl", ADDR, PW)
_server("smtp.test.local", 465, "ssl", ADDR, PW)
inbox = HOSTS["imap.test.local"][993]["accounts"][ADDR]["folders"]["INBOX"]
inbox.append({"uid": 1, "flags": ["\\Seen"], "raw": raw_message("旧信", "already read", 20, 1)})
inbox.append({"uid": 2, "flags": [], "raw": raw_message("服务器周报", "weekly report body", 24, 2, attachment=True)})
inbox.append({"uid": 3, "flags": [], "raw": raw_message("午餐？", "lunch today?", 25, 3)})

BODY = {"address": ADDR, "display_name": "测试邮箱", "provider_key": "custom",
        "imap_host": "imap.test.local", "imap_port": 993, "imap_security": "ssl",
        "smtp_host": "smtp.test.local", "smtp_port": 465, "smtp_security": "ssl",
        "username": ADDR}

print("== connection test classification ==")
status, payload = mail.test_connection(BODY, "wrong-password")
check("wrong password rejected", status == 200 and payload["ok"] is False)
check("imap category credential", payload["imap"]["category"] == "credential")
check("smtp category credential", payload["smtp"]["category"] == "credential")
check("human detail present", "应用专用密码" in payload["imap"]["detail"])
check("imap login attempted exactly once", HOSTS["imap.test.local"][993]["login_attempts"] == 1)
check("smtp login attempted exactly once", HOSTS["smtp.test.local"][465]["login_attempts"] == 1)

status, payload = mail.test_connection({**BODY, "imap_host": "no-such-host.test"}, PW)
check("bad host -> address", payload["imap"]["category"] == "address")
status, payload = mail.test_connection({**BODY, "imap_port": 9999}, PW)
check("bad port -> port", payload["imap"]["category"] == "port")
status, payload = mail.test_connection({**BODY, "imap_security": "starttls"}, PW)
check("security mismatch -> tls", payload["imap"]["category"] == "tls")
status, payload = mail.test_connection(BODY, PW)
check("good params pass", status == 200 and payload["ok"] is True)
status, payload = mail.test_connection({**BODY, "address": "not-an-address"}, PW)
check("bad address shape -> 400", status == 400)

print("== add account: test gate, vault storage, no plaintext ==")
status, payload = mail.create_account(BODY, "wrong-password", KEY)
check("create with wrong password -> 422", status == 422 and payload["status"] == "test_failed")
check("nothing persisted", mail.list_accounts() == [] and vault.list_entries() == [])

status, meta = mail.create_account(BODY, PW, KEY)
check("create ok -> 201", status == 201)
check("meta hides credential reference", "credential_id" not in meta and meta["credential_configured"] is True)
account_id = meta["id"]
entries = vault.list_entries()
check("vault holds one mail_account entry", len(entries) == 1 and entries[0]["service"] == "mail_account")
cred_id = entries[0]["id"]
accounts_text = (tmp / "mail" / "accounts.json").read_text(encoding="utf-8")
check("accounts store has no password", PW not in accounts_text)

print("== sync: full pass, unified inbox, breakpoint resume ==")
status, payload = mail.sync_account(account_id, KEY)
check("sync ok", status == 200 and payload["fetched"] == 3)
check("cursor advanced", payload["cursor"] == 3)
check("unread counted", payload["unread_count"] == 2)
listing = mail.list_messages()
check("unified inbox total", listing["total"] == 3)
check("newest first", [r["uid"] for r in listing["data"]] == [3, 2, 1])
check("list rows carry no body", all("body_text" not in r for r in listing["data"]))
full = mail.get_message(account_id, "INBOX", 2)
check("full message has body + attachment", full is not None
      and "weekly report body" in full["body_text"]
      and full["attachments"][0]["filename"] == "report.pdf")
unread = mail.list_messages(unread_only=True)
check("unread filter", unread["total"] == 2)

inbox.append({"uid": 4, "flags": [], "raw": raw_message("新信", "fresh one", 26, 4)})
status, payload = mail.sync_account(account_id, KEY)
check("incremental sync fetches only the new one", status == 200 and payload["fetched"] == 1 and payload["cursor"] == 4)
status, payload = mail.sync_account(account_id, KEY)
check("resume at cursor fetches nothing", status == 200 and payload["fetched"] == 0)

print("== pause gate ==")
status, meta = mail.update_account(account_id, {"status": "paused"}, KEY)
check("pause ok", status == 200 and meta["status"] == "paused")
status, payload = mail.sync_account(account_id, KEY)
check("sync while paused -> 409", status == 409)
status, meta = mail.update_account(account_id, {"status": "active"}, KEY)
check("resume ok", status == 200 and meta["status"] == "active")

print("== provider-side rotation: rejection flips status, one attempt only ==")
HOSTS["imap.test.local"][993]["accounts"][ADDR]["password"] = PW_NEW
HOSTS["smtp.test.local"][465]["accounts"][ADDR]["password"] = PW_NEW
before = HOSTS["imap.test.local"][993]["login_attempts"]
status, payload = mail.sync_account(account_id, KEY)
check("sync with stale password -> 502", status == 502 and payload["error"]["category"] == "credential")
check("exactly one login attempt", HOSTS["imap.test.local"][993]["login_attempts"] - before == 1)
check("account flipped to credential_invalid", mail.get_account(account_id)["status"] == "credential_invalid")
status, payload = mail.sync_account(account_id, KEY)
check("sync blocked while credential_invalid", status == 409)

status, payload = mail.update_account(account_id, {"password": "still-wrong"}, KEY)
check("rotation with wrong password -> 422", status == 422)
check("stored credential untouched by failed rotation", mail.get_account(account_id)["status"] == "credential_invalid")
status, meta = mail.update_account(account_id, {"password": PW_NEW}, KEY)
check("rotation with right password -> active", status == 200 and meta["status"] == "active")
status, payload = mail.sync_account(account_id, KEY)
check("sync works after rotation", status == 200)

print("== drafts store ==")
status, draft = mail.create_draft(account_id, {"to": "boss@example.test", "subject": "回复：周报", "body_text": "收到"})
check("draft created", status == 201 and draft["status"] == "draft")
check("draft listed", len(mail.list_drafts(account_id)) == 1)

print("== delete: vault revoked, cache and drafts cleared ==")
status, payload = mail.delete_account(account_id)
check("delete ok", status == 200)
check("vault entry revoked", vault.get_entry(cred_id) is None)
check("account gone", mail.list_accounts() == [])
check("cache cleared", mail.list_messages()["total"] == 0)
check("drafts cleared", mail.list_drafts() == [])

print("== mid-sync failure: cursor holds, partial rows dropped, retry resumes (F-1) ==")
_server("imap2.test.local", 993, "ssl", ADDR, PW)
_server("smtp2.test.local", 465, "ssl", ADDR, PW)
inbox2 = HOSTS["imap2.test.local"][993]["accounts"][ADDR]["folders"]["INBOX"]
for uid in (1, 2, 3):
    inbox2.append({"uid": uid, "flags": [],
                   "raw": raw_message(f"补测信 {uid}", f"f1 body {uid}", 20 + uid, uid)})
BODY2 = {**BODY, "imap_host": "imap2.test.local", "smtp_host": "smtp2.test.local"}
status, meta2 = mail.create_account(BODY2, PW, KEY)
check("f1 account created", status == 201)
acct2 = meta2["id"]

# The fetch of message 2 drops the connection mid-round (once; then the
# server recovers). Message 1 is fetched into the round's local rows
# before the drop, so this also proves partial rows are never cached
# and the cursor is only committed after a fully successful round.
HOSTS["imap2.test.local"][993]["fail_fetch"] = {2}
logins_before = HOSTS["imap2.test.local"][993]["login_attempts"]
status, payload = mail.sync_account(acct2, KEY)
check("mid-sync failure -> 502 sync_failed", status == 502 and payload["status"] == "sync_failed")
check("mid-sync failure classified network, not credential",
      payload["error"]["category"] == "network")
check("account stays active after transient failure", mail.get_account(acct2)["status"] == "active")
check("failed round logged in exactly once",
      HOSTS["imap2.test.local"][993]["login_attempts"] - logins_before == 1)
check("partial fetch not cached", mail.list_messages(account_id=acct2)["total"] == 0)
row2 = json.loads((tmp / "mail" / "accounts.json").read_text(encoding="utf-8"))["accounts"][acct2]
check("cursor did not advance on failure", int(row2.get("sync_cursor", {}).get("INBOX", 0)) == 0)

status, payload = mail.sync_account(acct2, KEY)
check("retry sync ok", status == 200)
check("retry fetched every unfinished message", payload["fetched"] == 3)
check("cursor advanced to end after retry", payload["cursor"] == 3)
listing2 = mail.list_messages(account_id=acct2)
check("no duplicate cache rows after retry",
      listing2["total"] == 3 and sorted(r["uid"] for r in listing2["data"]) == [1, 2, 3])
status, payload = mail.sync_account(acct2, KEY)
check("post-retry sync fetches nothing", status == 200 and payload["fetched"] == 0)

status, payload = mail.delete_account(acct2)
check("f1 account cleaned up", status == 200 and mail.list_accounts() == []
      and mail.list_messages()["total"] == 0)

print("== routes wiring ==")
from patches import api_server_oneday_routes as routes
adapter = routes.OneDayAuthPushRoutesMixin()
rows = routes.oneday_http_routes(adapter)
mail_rows = [r for r in rows if r[1].startswith("/v1/mail/")]
check("9 mail routes registered", len(mail_rows) == 9)
caps = dict(routes.ONEDAY_CAPABILITY_ENDPOINTS)
check("capability endpoints carry mail_gateway flag",
      caps.get("mail_accounts", (None, None, None))[2] == "mail_gateway")

print("== password zero-hit sweep over every file written ==")
hits = []
for path in tmp.rglob("*"):
    if path.is_file():
        data = path.read_bytes()
        if PW.encode() in data or PW_NEW.encode() in data:
            hits.append(str(path))
check("zero password hits in stores/audit/logs", hits == [])

print()
if fails:
    print(f"SELFTEST FAILED: {len(fails)} check(s): {fails}")
    sys.exit(1)
print("SELFTEST PASSED")
