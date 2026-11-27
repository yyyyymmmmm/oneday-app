"""Mail gateway: IMAP/SMTP account data source for the hub mail face.

Bar 1 (queue 181, hub mail proposal): the server-side data source
only -- account store, connection testing, polling IMAP sync into a
local cache, unified-inbox queries and account CRUD. No page, no AI
tools; those are later bars on top of this module.

Credential discipline (single source of truth = credential_vault):
an account row stores ONLY the vault entry id (``credential_id``).
Passwords are written to the vault under service ``mail_account``
with domains [imap host, smtp host] and are read back exclusively
through ``credential_vault.vault_use`` with the executors registered
at the bottom of this module: decryption happens inside the vault
call, the plaintext exists only in the executor's frame while it
talks to the mail server, and only {status, summary} ever returns.
Sync results travel back through a job-context sink, never through
the vault return value, and no account row, cache row, log line or
API response ever carries a password.

Failure discipline: a credential rejection is attempted at most
once per operation -- structurally: every path issues exactly one
login call and there is no retry loop anywhere in this module
(``MAX_AUTH_ATTEMPTS = 1`` is a declared invariant documenting
that discipline, not a runtime counter). A sync that meets a
rejection flips the account to ``credential_invalid`` and stops --
the poller never retries a rejected password into an account
lockout. Connection-test failures are classified into human
categories (address / port / credential / tls / protocol / network)
with a plain-language detail each, and an account is only persisted
after a full test pass (test -> vault write -> account row, in that
order, so a vault failure leaves no half-created account behind).

Sync: polling only (no IDLE in bar 1). The per-folder UID cursor is
persisted after every successful pass; a failed pass advances
nothing, so the next pass resumes exactly where the last good one
stopped (breakpoint resume), and cache writes are idempotent upserts
keyed by (account, folder, uid).

Test seam: IMAP/SMTP client construction goes through injectable
factories (``set_factories``) so the package selftest can run the
whole loop against in-process fake servers. Wire-level interop with
a real mail server (real imaplib/smtplib over TLS) is NOT covered
by the selftest and must be verified with a real test mailbox
before deployment.
"""

from __future__ import annotations

import email
import email.policy
import imaplib
import json
import os
import re
import smtplib
import socket
import ssl
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Callable

DATA_DIR = Path(os.environ.get("MAIL_GATEWAY_DIR", "/opt/data/mail"))
ACCOUNTS_PATH = Path(os.environ.get("MAIL_ACCOUNTS_PATH", str(DATA_DIR / "accounts.json")))
MESSAGES_PATH = Path(os.environ.get("MAIL_MESSAGES_PATH", str(DATA_DIR / "messages.json")))
DRAFTS_PATH = Path(os.environ.get("MAIL_DRAFTS_PATH", str(DATA_DIR / "drafts.json")))
POLL_SECONDS = max(30, int(os.environ.get("MAIL_SYNC_POLL_SECONDS", "300")))
FETCH_PER_PASS = 100
BODY_CAP = 32768
SNIPPET_CAP = 240
CACHE_PER_FOLDER = 500
MAX_AUTH_ATTEMPTS = 1
VAULT_SERVICE = "mail_account"
DEFAULT_FOLDER = "INBOX"

SECURITIES = frozenset({"ssl", "starttls"})
STATUSES = frozenset({"active", "paused", "credential_invalid", "error"})

CATEGORY_HUMAN = {
    "address": "主机名解析失败，请检查服务器地址是否写对",
    "port": "连不上服务器端口，请检查端口号与网络",
    "credential": "密码被拒：可能填错了密码；开了两步验证的账号请改填应用专用密码",
    "tls": "加密方式不合或证书有误，请核对 SSL / STARTTLS 设置",
    "protocol": "服务器应答异常，请核对服务器参数",
    "network": "网络异常，请稍后重试",
    "validation": "参数不完整或格式不对",
}

_lock = threading.RLock()
_job = threading.local()


# --------------------------------------------------------------------------
# error classification

def _classify(exc: BaseException) -> str:
    if isinstance(exc, socket.gaierror):
        return "address"
    if isinstance(exc, (ssl.SSLError, ssl.CertificateError)):
        return "tls"
    if isinstance(exc, ConnectionRefusedError):
        return "port"
    if isinstance(exc, (TimeoutError, socket.timeout)):
        return "port"
    if isinstance(exc, smtplib.SMTPAuthenticationError):
        return "credential"
    if isinstance(exc, imaplib.IMAP4.error):
        msg = str(exc).lower()
        if any(k in msg for k in ("authenticationfailed", "authentication failed",
                                  "login failed", "invalid credentials", "login failure")):
            return "credential"
        return "protocol"
    if isinstance(exc, smtplib.SMTPConnectError):
        return "port"
    if isinstance(exc, smtplib.SMTPException):
        return "protocol"
    if isinstance(exc, OSError):
        return "network"
    return "protocol"


def _fail(category: str) -> dict[str, Any]:
    return {"ok": False, "category": category, "detail": CATEGORY_HUMAN[category]}


# --------------------------------------------------------------------------
# client factories (injectable for tests)

def _default_imap_factory(host: str, port: int, security: str):
    if security == "ssl":
        return imaplib.IMAP4_SSL(host, port, timeout=20)
    client = imaplib.IMAP4(host, port, timeout=20)
    if security == "starttls":
        client.starttls()
    return client


def _default_smtp_factory(host: str, port: int, security: str):
    if security == "ssl":
        return smtplib.SMTP_SSL(host, port, timeout=20)
    client = smtplib.SMTP(host, port, timeout=20)
    if security == "starttls":
        client.ehlo()
        client.starttls()
        client.ehlo()
    return client


_factories: dict[str, Callable[..., Any]] = {"imap": _default_imap_factory, "smtp": _default_smtp_factory}


def set_factories(imap_factory: Callable[..., Any] | None = None,
                  smtp_factory: Callable[..., Any] | None = None) -> None:
    """Test seam: swap the IMAP/SMTP client constructors."""
    if imap_factory is not None:
        _factories["imap"] = imap_factory
    if smtp_factory is not None:
        _factories["smtp"] = smtp_factory


# --------------------------------------------------------------------------
# JSON stores (atomic write + 0600, same discipline as credential_vault)

_STORE_FILES = {"accounts": "ACCOUNTS_PATH", "messages": "MESSAGES_PATH", "drafts": "DRAFTS_PATH"}


def _store_path(kind: str) -> Path:
    return globals()[_STORE_FILES[kind]]


def _load_store(kind: str) -> dict[str, Any]:
    path = _store_path(kind)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) and isinstance(data.get(kind), dict) else {kind: {}}
    except FileNotFoundError:
        return {kind: {}}
    except Exception:
        return {kind: {}}


def _save_store(kind: str, data: dict[str, Any]) -> None:
    path = _store_path(kind)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


# --------------------------------------------------------------------------
# parameter validation

_HOST_RE = re.compile(r"(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?")
_ADDR_RE = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,190}$")


def _clean_str(value: Any, cap: int) -> str | None:
    if not isinstance(value, str):
        return None
    out = value.strip()
    return out[:cap] if out and len(out) <= cap else None


def _server_block(body: dict[str, Any], prefix: str, default_ssl: int, default_tls: int) -> dict[str, Any] | None:
    host = _clean_str(body.get(f"{prefix}_host"), 253)
    security = body.get(f"{prefix}_security") or "ssl"
    if not host or not _HOST_RE.fullmatch(host) or security not in SECURITIES:
        return None
    port = body.get(f"{prefix}_port")
    if port is None:
        port = default_ssl if security == "ssl" else default_tls
    if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
        return None
    return {"host": host.lower(), "port": port, "security": security}


def validate_params(body: Any) -> dict[str, Any] | None:
    """Normalize an account parameter body; None when anything is off."""
    if not isinstance(body, dict):
        return None
    address = _clean_str(body.get("address"), 254)
    if not address or not _ADDR_RE.fullmatch(address):
        return None
    imap = _server_block(body, "imap", 993, 143)
    smtp = _server_block(body, "smtp", 465, 587)
    if imap is None or smtp is None:
        return None
    username = _clean_str(body.get("username"), 256) or address
    display_name = body.get("display_name")
    if display_name is not None and not isinstance(display_name, str):
        return None
    provider_key = body.get("provider_key")
    if provider_key is not None and (not isinstance(provider_key, str) or len(provider_key) > 64):
        return None
    return {
        "address": address,
        "display_name": (display_name or "").strip()[:120],
        "provider_key": (provider_key or "custom").strip()[:64] or "custom",
        "imap": imap, "smtp": smtp, "username": username,
    }


# --------------------------------------------------------------------------
# connection test (plaintext password from the caller; nothing persists)

def _test_imap(params: dict[str, Any], password: str) -> dict[str, Any]:
    cfg = params["imap"]
    try:
        client = _factories["imap"](cfg["host"], cfg["port"], cfg["security"])
        try:
            client.login(params["username"], password)  # exactly one attempt
            client.list()
        finally:
            try:
                client.logout()
            except Exception:
                pass
    except Exception as exc:
        return _fail(_classify(exc))
    return {"ok": True}


def _test_smtp(params: dict[str, Any], password: str) -> dict[str, Any]:
    cfg = params["smtp"]
    try:
        client = _factories["smtp"](cfg["host"], cfg["port"], cfg["security"])
        try:
            client.login(params["username"], password)  # exactly one attempt
        finally:
            try:
                client.quit()
            except Exception:
                pass
    except Exception as exc:
        return _fail(_classify(exc))
    return {"ok": True}


def test_connection(body: Any, password: Any) -> tuple[int, dict[str, Any]]:
    """POST /v1/mail/test-connection: live-probe both sides, persist nothing."""
    params = validate_params(body)
    if params is None or not isinstance(password, str) or not password or len(password) > 8192:
        return 400, {"status": "rejected", "error": _fail("validation")}
    imap_res = _test_imap(params, password)
    smtp_res = _test_smtp(params, password)
    return 200, {"status": "tested", "ok": imap_res["ok"] and smtp_res["ok"],
                 "imap": imap_res, "smtp": smtp_res}


# --------------------------------------------------------------------------
# vault integration

def _vault():
    from gateway.platforms import credential_vault
    return credential_vault


def _account_meta(row: dict[str, Any]) -> dict[str, Any]:
    """Public account shape: metadata only, never the credential reference."""
    return {
        "id": row["id"], "address": row["address"],
        "display_name": row["display_name"], "provider_key": row["provider_key"],
        "imap": dict(row["imap"]), "smtp": dict(row["smtp"]),
        "username": row["username"], "status": row["status"],
        "credential_configured": bool(row.get("credential_id")),
        "unread_count": row.get("unread_count", 0),
        "last_sync_at": row.get("last_sync_at"),
        "last_sync_error": row.get("last_sync_error"),
        "created_at": row["created_at"], "updated_at": row["updated_at"],
    }


def _get_row(account_id: str) -> dict[str, Any] | None:
    with _lock:
        row = _load_store("accounts")["accounts"].get(account_id)
        return dict(row) if row else None


def list_accounts() -> list[dict[str, Any]]:
    with _lock:
        rows = sorted(_load_store("accounts")["accounts"].values(),
                      key=lambda r: r["created_at"])
        return [_account_meta(r) for r in rows]


def get_account(account_id: str) -> dict[str, Any] | None:
    row = _get_row(account_id)
    return _account_meta(row) if row else None


def create_account(body: Any, password: Any, api_key: str) -> tuple[int, dict[str, Any]]:
    """Test first; only a full pass writes vault entry + account row."""
    params = validate_params(body)
    if params is None or not isinstance(password, str) or not password or len(password) > 8192:
        return 400, {"status": "rejected", "error": _fail("validation")}
    imap_res = _test_imap(params, password)
    smtp_res = _test_smtp(params, password)
    if not (imap_res["ok"] and smtp_res["ok"]):
        return 422, {"status": "test_failed", "imap": imap_res, "smtp": smtp_res}
    vault = _vault()
    status, receipt = vault.write_entry({
        "name": f"邮箱 {params['address']}", "service": VAULT_SERVICE,
        "domains": sorted({params["imap"]["host"], params["smtp"]["host"]}),
        "username": params["username"], "values": {"password": password},
    }, api_key)
    if status != 200:
        # Nothing persisted on this side yet: the whole add rolls back.
        return 503, {"status": "vault_unavailable"}
    now = int(time.time())
    account_id = "mac_" + uuid.uuid4().hex[:16]
    row = {
        "id": account_id, **params, "credential_id": receipt["id"],
        "status": "active", "sync_cursor": {}, "unread_count": 0,
        "last_sync_at": None, "last_sync_error": None,
        "created_at": now, "updated_at": now,
    }
    with _lock:
        data = _load_store("accounts")
        data["accounts"][account_id] = row
        _save_store("accounts", data)
    return 201, _account_meta(row)


def update_account(account_id: str, body: Any, api_key: str) -> tuple[int, dict[str, Any]]:
    """Display name, pause/resume, and password change (re-tested first)."""
    if not isinstance(body, dict):
        return 400, {"status": "rejected", "error": _fail("validation")}
    row = _get_row(account_id)
    if row is None:
        return 404, {"status": "not_found"}
    if "password" in body:
        new_password = body.get("password")
        if not isinstance(new_password, str) or not new_password or len(new_password) > 8192:
            return 400, {"status": "rejected", "error": _fail("validation")}
        params = {"address": row["address"], "imap": row["imap"],
                  "smtp": row["smtp"], "username": row["username"]}
        imap_res = _test_imap(params, new_password)
        smtp_res = _test_smtp(params, new_password)
        if not (imap_res["ok"] and smtp_res["ok"]):
            # Stored credential untouched: the old one may still be valid.
            return 422, {"status": "test_failed", "imap": imap_res, "smtp": smtp_res}
        vault = _vault()
        status, _receipt = vault.write_entry({
            "name": f"邮箱 {row['address']}", "service": VAULT_SERVICE,
            "domains": sorted({row["imap"]["host"], row["smtp"]["host"]}),
            "username": row["username"], "values": {"password": new_password},
        }, api_key, entry_id=row["credential_id"])
        if status != 200:
            return 503, {"status": "vault_unavailable"}
        row["status"] = "active"
        row["last_sync_error"] = None
    if "display_name" in body:
        if not isinstance(body["display_name"], str):
            return 400, {"status": "rejected", "error": _fail("validation")}
        row["display_name"] = body["display_name"].strip()[:120]
    if "status" in body:
        if body["status"] not in ("active", "paused"):
            return 400, {"status": "rejected", "error": _fail("validation")}
        row["status"] = body["status"]
    row["updated_at"] = int(time.time())
    with _lock:
        data = _load_store("accounts")
        data["accounts"][account_id] = row
        _save_store("accounts", data)
    return 200, _account_meta(row)


def delete_account(account_id: str) -> tuple[int, dict[str, Any]]:
    """Revoke the vault entry, drop the account's cache and drafts, drop the row."""
    row = _get_row(account_id)
    if row is None:
        return 404, {"status": "not_found"}
    vault = _vault()
    status, _payload = vault.delete_entry(row["credential_id"])
    if status not in (200, 404):
        return 503, {"status": "vault_unavailable"}
    with _lock:
        data = _load_store("accounts")
        data["accounts"].pop(account_id, None)
        _save_store("accounts", data)
        messages = _load_store("messages")
        messages["messages"] = {k: v for k, v in messages["messages"].items()
                                if v.get("account_id") != account_id}
        _save_store("messages", messages)
        drafts = _load_store("drafts")
        drafts["drafts"] = {k: v for k, v in drafts["drafts"].items()
                            if v.get("account_id") != account_id}
        _save_store("drafts", drafts)
    return 200, {"id": account_id, "status": "deleted"}


# --------------------------------------------------------------------------
# message cache

def _message_key(account_id: str, folder: str, uid: int) -> str:
    return f"{account_id}:{folder}:{uid}"


def _cache_messages(rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with _lock:
        data = _load_store("messages")
        for row in rows:
            data["messages"][_message_key(row["account_id"], row["folder"], row["uid"])] = row
        # Retention: keep the newest CACHE_PER_FOLDER per (account, folder).
        by_folder: dict[tuple[str, str], list[dict[str, Any]]] = {}
        for row in data["messages"].values():
            by_folder.setdefault((row["account_id"], row["folder"]), []).append(row)
        for key, group in by_folder.items():
            if len(group) > CACHE_PER_FOLDER:
                group.sort(key=lambda r: r["uid"])
                for stale in group[:-CACHE_PER_FOLDER]:
                    data["messages"].pop(_message_key(key[0], key[1], stale["uid"]), None)
        _save_store("messages", data)


def _message_meta(row: dict[str, Any]) -> dict[str, Any]:
    return {k: row[k] for k in ("account_id", "folder", "uid", "message_id",
                                "from", "to", "subject", "date", "seen",
                                "snippet", "attachments")}


def list_messages(account_id: str | None = None, folder: str = DEFAULT_FOLDER,
                  limit: int = 50, offset: int = 0,
                  unread_only: bool = False) -> dict[str, Any]:
    """Unified inbox: every account's cached folder, newest first."""
    limit = max(1, min(int(limit or 50), 200))
    offset = max(0, int(offset or 0))
    with _lock:
        rows = [r for r in _load_store("messages")["messages"].values()
                if r["folder"] == folder
                and (account_id is None or r["account_id"] == account_id)
                and (not unread_only or not r["seen"])]
    rows.sort(key=lambda r: (r["date"], r["uid"]), reverse=True)
    return {"total": len(rows),
            "data": [_message_meta(r) for r in rows[offset:offset + limit]]}


def get_message(account_id: str, folder: str, uid: int) -> dict[str, Any] | None:
    with _lock:
        row = _load_store("messages")["messages"].get(_message_key(account_id, folder, uid))
        return dict(row) if row else None


# --------------------------------------------------------------------------
# drafts store (bar 1 lays the model; tools/UI arrive in later bars)

def create_draft(account_id: str, body: Any) -> tuple[int, dict[str, Any]]:
    if _get_row(account_id) is None:
        return 404, {"status": "not_found"}
    if not isinstance(body, dict):
        return 400, {"status": "rejected", "error": _fail("validation")}
    now = int(time.time())
    draft = {
        "id": "mdr_" + uuid.uuid4().hex[:16], "account_id": account_id,
        "source": _clean_str(body.get("source"), 16) or "new",
        "reply_to_message_id": _clean_str(body.get("reply_to_message_id"), 256),
        "to": _clean_str(body.get("to"), 512) or "",
        "subject": _clean_str(body.get("subject"), 512) or "",
        "body_text": body.get("body_text") if isinstance(body.get("body_text"), str) else "",
        "status": "draft", "approval_ref": None,
        "send_error": None, "created_at": now, "updated_at": now,
    }
    with _lock:
        data = _load_store("drafts")
        data["drafts"][draft["id"]] = draft
        _save_store("drafts", data)
    return 201, draft


def list_drafts(account_id: str | None = None, status: str | None = None) -> list[dict[str, Any]]:
    with _lock:
        rows = [d for d in _load_store("drafts")["drafts"].values()
                if (account_id is None or d["account_id"] == account_id)
                and (status is None or d["status"] == status)]
    rows.sort(key=lambda d: d["updated_at"], reverse=True)
    return rows


# --------------------------------------------------------------------------
# IMAP sync through the vault (plaintext lives only in the executor frame)

def _parse_message(raw: bytes, account_id: str, folder: str, uid: int, seen: bool) -> dict[str, Any]:
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    date_epoch = int(time.time())
    try:
        if msg["Date"] is not None and msg["Date"].datetime is not None:
            date_epoch = int(msg["Date"].datetime.timestamp())
    except Exception:
        pass
    body_text = ""
    try:
        body = msg.get_body(("plain", "html"))
        if body is not None:
            text = body.get_content()
            if body.get_content_type() == "text/html":
                text = re.sub(r"<[^>]+>", " ", text)
            body_text = str(text)[:BODY_CAP]
    except Exception:
        body_text = ""
    attachments = []
    try:
        for part in msg.iter_attachments():
            payload = part.get_payload(decode=True) or b""
            attachments.append({"filename": part.get_filename() or "",
                                "size": len(payload),
                                "content_type": part.get_content_type()})
    except Exception:
        pass
    return {
        "account_id": account_id, "folder": folder, "uid": uid,
        "message_id": str(msg["Message-ID"] or "").strip()[:256],
        "from": str(msg["From"] or "")[:512], "to": str(msg["To"] or "")[:512],
        "subject": str(msg["Subject"] or "")[:512], "date": date_epoch,
        "seen": bool(seen), "body_text": body_text,
        "snippet": re.sub(r"\s+", " ", body_text).strip()[:SNIPPET_CAP],
        "attachments": attachments, "fetched_at": int(time.time()),
    }


def _exec_sync(domain: str, values: dict[str, str]) -> dict[str, Any]:
    """vault_use executor for ("mail_account", "sync").

    Runs inside the vault call: builds the IMAP client, logs in once,
    fetches every UID past the job cursor, and hands parsed rows to
    the job sink. Only the category (never exception text, never the
    password) is recorded on failure.
    """
    job = getattr(_job, "ctx", None)
    if not isinstance(job, dict):
        return {"status": "failed", "summary": "operation failed"}
    account, folder = job["account"], job["folder"]
    cfg = account["imap"]
    result = job["result"]
    try:
        client = _factories["imap"](cfg["host"], cfg["port"], cfg["security"])
        try:
            client.login(account["username"], values.get("password", ""))  # one attempt
            client.select(folder)
            _typ, data = client.uid("search", None, "ALL")
            all_uids = sorted(int(u) for u in (data[0].split() if data and data[0] else []))
            fresh = [u for u in all_uids if u > job["after_uid"]][:job["limit"]]
            rows = []
            for uid in fresh:
                _typ, fetched = client.uid("fetch", str(uid), "(FLAGS RFC822)")
                for item in fetched or []:
                    if isinstance(item, tuple) and len(item) >= 2 and isinstance(item[1], (bytes, bytearray)):
                        meta = item[0].decode("utf-8", "replace") if isinstance(item[0], (bytes, bytearray)) else str(item[0])
                        rows.append(_parse_message(bytes(item[1]), account["id"], folder,
                                                   uid, "\\Seen" in meta))
            _typ, unseen = client.uid("search", None, "UNSEEN")
            result["unseen"] = len(unseen[0].split()) if unseen and unseen[0] else 0
        finally:
            try:
                client.logout()
            except Exception:
                pass
    except Exception as exc:
        result["category"] = _classify(exc)
        result["auth_failed"] = result["category"] == "credential"
        return {"status": "failed", "summary": CATEGORY_HUMAN[result["category"]]}
    job["sink"](rows)
    result["fetched"] = len(rows)
    result["max_uid"] = max([r["uid"] for r in rows], default=job["after_uid"])
    return {"status": "completed", "summary": f"synced {len(rows)} messages"}


def _register_operations() -> None:
    try:
        vault = _vault()
        vault.OPERATIONS[("mail_account", "sync")] = _exec_sync
    except Exception:
        pass


_register_operations()


def sync_account(account_id: str, api_key: str, folder: str = DEFAULT_FOLDER) -> tuple[int, dict[str, Any]]:
    """One polling pass: fetch past the stored cursor, advance it on success."""
    row = _get_row(account_id)
    if row is None:
        return 404, {"status": "not_found"}
    if row["status"] == "paused":
        return 409, {"status": "paused"}
    if row["status"] == "credential_invalid":
        return 409, {"status": "credential_invalid", "error": _fail("credential")}
    job = {"account": row, "folder": folder,
           "after_uid": int(row.get("sync_cursor", {}).get(folder, 0)),
           "limit": FETCH_PER_PASS, "sink": _cache_messages, "result": {}}
    _register_operations()  # idempotent; import-time registration may have raced
    _job.ctx = job
    try:
        outcome = _vault().vault_use(row["credential_id"], row["imap"]["host"],
                                     VAULT_SERVICE, "sync", api_key=api_key)
    finally:
        _job.ctx = None
    result = job["result"]
    now = int(time.time())
    with _lock:
        data = _load_store("accounts")
        live = data["accounts"].get(account_id)
        if live is None:
            return 404, {"status": "not_found"}
        if outcome.get("status") != "completed":
            category = result.get("category", "network")
            live["last_sync_error"] = {"category": category,
                                      "detail": CATEGORY_HUMAN[category], "at": now}
            if result.get("auth_failed"):
                live["status"] = "credential_invalid"
            live["updated_at"] = now
            _save_store("accounts", data)
            return 502, {"status": "sync_failed", "error": _fail(category)}
        live.setdefault("sync_cursor", {})[folder] = max(
            int(live["sync_cursor"].get(folder, 0)), int(result.get("max_uid", 0)))
        live["last_sync_at"] = now
        live["last_sync_error"] = None
        if folder == DEFAULT_FOLDER:
            live["unread_count"] = int(result.get("unseen", live.get("unread_count", 0)))
        live["updated_at"] = now
        _save_store("accounts", data)
        cursor = live["sync_cursor"][folder]
        unread = live["unread_count"]
    return 200, {"status": "synced", "fetched": int(result.get("fetched", 0)),
                 "cursor": cursor, "unread_count": unread}


# --------------------------------------------------------------------------
# polling syncer

_poller_stop = threading.Event()
_poller_thread: threading.Thread | None = None
_poller_key: str | None = None


def _poll_loop() -> None:
    while not _poller_stop.wait(POLL_SECONDS):
        if not _poller_key:
            continue
        try:
            for meta in list_accounts():
                if meta["status"] == "active":
                    try:
                        sync_account(meta["id"], _poller_key)
                    except Exception:
                        pass
        except Exception:
            pass


def start(api_key: str | None = None) -> None:
    """Start the polling syncer (idempotent). Called from api_server connect()."""
    global _poller_thread, _poller_key
    if api_key:
        _poller_key = api_key
    _register_operations()
    if _poller_thread is not None and _poller_thread.is_alive():
        return
    _poller_stop.clear()
    _poller_thread = threading.Thread(target=_poll_loop, name="mail-gateway-poller", daemon=True)
    _poller_thread.start()


def stop() -> None:
    _poller_stop.set()
