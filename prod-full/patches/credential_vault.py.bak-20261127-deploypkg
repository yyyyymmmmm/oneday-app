"""Encrypted credential metadata and one-time request surface.

The vault derives its AES-GCM key from the existing API_SERVER_KEY. This
single-key design is provisional and requires a separate key-lifecycle ADR.

Request access modes (2.13.0): requests are bound at creation to the
chat session that asked. HTTP callers authenticated with a short-lived
device token stay filtered to their own device session. A caller that
authenticated with the long-lived API_SERVER_KEY itself (the deployment
master key -- the same key that already authorizes entry create /
replace / delete and approval decisions) passes session_id=None, the
owner mode: every request in scope is listable / decidable. In the
chat flow the two session namespaces (the conversation's
``HERMES_SESSION_ID`` vs device ``sess_*`` ids) do not intersect, and
long-key callers previously got a hard 404 before any filtering, so a
chat-created request was unreachable over HTTP; owner mode restores
the surface without widening device-token access by one bit.

Durability + entry shape (2.17.2): pending requests are persisted to
a sibling store file (same atomic-write discipline as entries), so a
gateway restart or redeploy no longer kills a live request card; the
in-process dict is a write-through cache and the original absolute
``expires_at`` keeps governing the TTL across restarts. Entry domains
are optional: an empty or absent domain list is a valid entry (the
client form no longer forces a domain); per-domain format validation
for supplied domains is unchanged.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Callable

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:  # fail closed when the deployment crypto provider is absent
    AESGCM = None

STORE_PATH = Path(os.environ.get("CREDENTIAL_VAULT_PATH", "/opt/data/vault/entries.json"))
AUDIT_PATH = Path(os.environ.get("CREDENTIAL_VAULT_AUDIT_PATH", "/opt/data/vault/audit.jsonl"))
REQUESTS_PATH = Path(os.environ.get("CREDENTIAL_VAULT_REQUESTS_PATH", "/opt/data/vault/requests.json"))
REQUEST_TTL = 15 * 60
FIELDS = frozenset({"username", "password", "token", "api_key", "secret", "otp"})

# Canonical field order for the request card (queue 167): the card is a
# login form, so account-class fields come first, password-class second,
# everything else after. Neither the caller's order nor alphabetical
# order is trusted -- sorted() puts "password" ahead of "username",
# which is exactly how the card shipped password-first. Within one
# class the caller's relative order is preserved (stable sort).
_ACCOUNT_FIELDS = frozenset({"username", "account", "email", "用户名", "账号"})
_PASSWORD_FIELDS = frozenset({"password", "密码"})


def _field_rank(field: str) -> int:
    name = field.strip().lower()
    if name in _ACCOUNT_FIELDS:
        return 0
    if name in _PASSWORD_FIELDS:
        return 1
    return 2


def canonical_field_order(fields: Any) -> list[str]:
    """Dedupe *fields* (first occurrence wins), then order canonically."""
    unique = [f for f in dict.fromkeys(fields) if isinstance(f, str) and f]
    return sorted(unique, key=_field_rank)
OPERATIONS: dict[tuple[str, str], Callable[..., dict[str, Any]]] = {}
_lock = threading.RLock()
_requests: dict[str, dict[str, Any]] = {}
_requests_loaded: set[str] = set()


def _key(api_key: str) -> bytes:
    if not api_key:
        raise ValueError("vault key unavailable")
    return hashlib.sha256(b"oneday-credential-vault-v1:" + api_key.encode()).digest()


def _paths(scope: str) -> tuple[Path, Path]:
    scope = scope or "default"
    safe_scope = "default" if scope == "default" else hashlib.sha256(scope.encode()).hexdigest()[:16]
    if safe_scope == "default":
        return STORE_PATH, AUDIT_PATH
    return (STORE_PATH.with_name(f"{STORE_PATH.stem}-{safe_scope}{STORE_PATH.suffix}"),
            AUDIT_PATH.with_name(f"{AUDIT_PATH.stem}-{safe_scope}{AUDIT_PATH.suffix}"))


def _load(scope: str = "default") -> dict[str, Any]:
    store_path, _ = _paths(scope)
    try:
        data = json.loads(store_path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) and isinstance(data.get("entries"), dict) else {"entries": {}}
    except FileNotFoundError:
        return {"entries": {}}


def _save(data: dict[str, Any], scope: str = "default") -> None:
    store_path, _ = _paths(scope)
    store_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = store_path.with_name(store_path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, store_path)


def _request_paths(scope: str) -> Path:
    scope = scope or "default"
    if scope == "default":
        return REQUESTS_PATH
    safe_scope = hashlib.sha256(scope.encode()).hexdigest()[:16]
    return REQUESTS_PATH.with_name(f"{REQUESTS_PATH.stem}-{safe_scope}{REQUESTS_PATH.suffix}")


def _ensure_requests_loaded(scope: str) -> None:
    """Load persisted requests for *scope* into the in-process store.

    Call with ``_lock`` held. The on-disk file is the cross-restart
    record (2.17.2); the dict is a write-through cache owned by this
    process, so a first touch after a restart rehydrates every request
    that was live when the previous process stopped. A request caught
    mid-fulfillment (status "consuming" at crash time) reverts to
    pending: the sealed entry write either landed as a normal vault
    entry or did not, and the request itself must not wedge shut.
    """
    scope = scope or "default"
    if scope in _requests_loaded:
        return
    _requests_loaded.add(scope)
    try:
        data = json.loads(_request_paths(scope).read_text(encoding="utf-8"))
        rows = data.get("requests") if isinstance(data, dict) else None
        if isinstance(rows, dict):
            for request_id, req in rows.items():
                if isinstance(req, dict) and req.get("scope", scope) == scope:
                    if req.get("status") == "consuming":
                        req["status"] = "pending"
                    _requests.setdefault(request_id, req)
    except FileNotFoundError:
        pass
    except Exception:
        pass


def _persist_requests(scope: str) -> None:
    """Write-through persist of one scope's requests (atomic, 0600).

    Same discipline as :func:`_save`: tmp file + fsync + os.replace, so
    a crash mid-write can never leave a torn store behind.
    """
    scope = scope or "default"
    path = _request_paths(scope)
    rows = {k: v for k, v in _requests.items() if v.get("scope") == scope}
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"requests": rows}, f, ensure_ascii=False, separators=(",", ":"))
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def _audit(event: dict[str, Any], scope: str = "default") -> None:
    _, audit_path = _paths(scope)
    audit_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(audit_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, (json.dumps(event, separators=(",", ":")) + "\n").encode())
    finally:
        os.close(fd)


def _encrypt(values: dict[str, str], api_key: str) -> dict[str, str]:
    if AESGCM is None:
        raise RuntimeError("vault_crypto_unavailable")
    nonce = os.urandom(12)
    ciphertext = AESGCM(_key(api_key)).encrypt(nonce, json.dumps(values, separators=(",", ":")).encode(), None)
    return {"nonce": base64.b64encode(nonce).decode(), "ciphertext": base64.b64encode(ciphertext).decode()}


def _valid_domains(raw: Any) -> list[str] | None:
    if raw is None:
        return []
    if not isinstance(raw, list) or len(raw) > 32:
        return None
    out = []
    for value in raw:
        if not isinstance(value, str):
            return None
        domain = value.strip().lower().rstrip(".")
        if len(domain) > 253 or not re.fullmatch(r"(?=.{1,253}$)[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", domain):
            return None
        out.append(domain)
    return sorted(set(out))


def _meta(entry_id: str, row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": entry_id, "name": row["name"], "service": row["service"],
        "domains": list(row["domains"]), "username": row.get("username"),
        "field_names": list(row["field_names"]), "updated_at": row["updated_at"],
        "version": row["version"], "has_secret": True,
    }


def list_entries(scope: str = "default") -> list[dict[str, Any]]:
    with _lock:
        data = _load(scope)
        return [_meta(k, v) for k, v in data["entries"].items() if not v.get("revoked")]


def get_entry(entry_id: str, scope: str = "default") -> dict[str, Any] | None:
    with _lock:
        row = _load(scope)["entries"].get(entry_id)
        return _meta(entry_id, row) if row and not row.get("revoked") else None


def write_entry(body: Any, api_key: str, entry_id: str | None = None, scope: str = "default") -> tuple[int, dict[str, Any]]:
    if not isinstance(body, dict):
        return 400, {"status": "rejected"}
    name, service = body.get("name"), body.get("service")
    domains = _valid_domains(body.get("domains"))
    values = body.get("values")
    username = body.get("username")
    if not isinstance(name, str) or not name.strip() or len(name) > 120 or not isinstance(service, str) or not service.strip() or len(service) > 120 or domains is None:
        return 400, {"status": "rejected"}
    if not isinstance(values, dict) or not values or set(values) - FIELDS or any(not isinstance(v, str) or len(v) > 8192 for v in values.values()):
        return 400, {"status": "rejected"}
    if username is not None and (not isinstance(username, str) or len(username) > 256):
        return 400, {"status": "rejected"}
    try:
        sealed = _encrypt(values, api_key)
    except Exception:
        return 503, {"status": "unavailable"}
    now = int(time.time())
    with _lock:
        data = _load(scope)
        current = data["entries"].get(entry_id) if entry_id else None
        if entry_id and (not current or current.get("revoked")):
            return 404, {"status": "not_found"}
        key = entry_id or "vlt_" + uuid.uuid4().hex[:20]
        version = int((current or {}).get("version", 0)) + 1
        data["entries"][key] = {
            "name": name.strip(), "service": service.strip(), "domains": domains,
            "username": username, "field_names": sorted(values), "updated_at": now,
            "version": version, "sealed": sealed, "revoked": False,
        }
        _save(data, scope)
        _audit({"at": now, "action": "entry.write", "id": key, "version": version}, scope)
    return 200, {"id": key, "version": version, "updated_at": now, "status": "stored"}


def delete_entry(entry_id: str, scope: str = "default") -> tuple[int, dict[str, Any]]:
    now = int(time.time())
    with _lock:
        data = _load(scope)
        row = data["entries"].get(entry_id)
        if not row or row.get("revoked"):
            return 404, {"status": "not_found"}
        row.pop("sealed", None)
        row["revoked"] = True
        row["updated_at"] = now
        row["version"] = int(row.get("version", 0)) + 1
        _save(data, scope)
        _audit({"at": now, "action": "entry.revoked", "id": entry_id, "version": row["version"]}, scope)
        return 200, {"id": entry_id, "version": row["version"], "updated_at": now, "status": "revoked"}


def create_request(service: str, domain: str, reason: str, fields: Any, session_id: str, scope: str = "default") -> dict[str, Any]:
    clean_domain = (domain or "").strip().lower().rstrip(".")
    if not service or len(service) > 120 or not clean_domain or not isinstance(fields, list) or not fields or set(fields) - FIELDS:
        raise ValueError("invalid_request")
    request_id = "vreq_" + secrets.token_urlsafe(18)
    now = time.time()
    with _lock:
        _ensure_requests_loaded(scope)
        for key, req in list(_requests.items()):
            if req.get("scope") == scope and (req["expires_at"] <= now or req["status"] != "pending"):
                _requests.pop(key, None)
        for req in _requests.values():
            if req["session_id"] == session_id and req.get("scope") == scope and req["status"] == "pending":
                req["status"] = "superseded"
        _requests[request_id] = {
            "service": service[:120], "domain": clean_domain,
            "reason": (reason or "")[:240], "fields": canonical_field_order(fields),
            "session_id": session_id, "created_at": now,
            "expires_at": now + REQUEST_TTL, "status": "pending", "scope": scope,
        }
        _persist_requests(scope)
        _audit({"at": int(now), "action": "request.created", "id": request_id,
                "service": service[:120], "domain": clean_domain,
                "fields": canonical_field_order(fields)}, scope)
    return {"request_id": request_id, "status": "pending", "expires_at": int(now + REQUEST_TTL)}


def list_requests(session_id: str, scope: str = "default", status: str | None = "pending") -> list[dict[str, Any]]:
    now = time.time()
    with _lock:
        _ensure_requests_loaded(scope)
        rows = []
        changed = False
        for request_id, req in _requests.items():
            if (session_id is not None and req["session_id"] != session_id) or req.get("scope") != scope:
                continue
            if req["status"] == "pending" and req["expires_at"] <= now:
                req["status"] = "expired"
                changed = True
            if status not in (None, "") and req["status"] != status:
                continue
            rows.append((req["created_at"], {
                "request_id": request_id,
                "service": req["service"],
                "domain": req["domain"],
                "reason": req["reason"],
                "fields": canonical_field_order(req["fields"]),
                "status": req["status"],
                "expires_at": int(req["expires_at"]),
            }))
        if changed:
            _persist_requests(scope)
        rows.sort(key=lambda item: item[0], reverse=True)
        return [row for _, row in rows]


def fulfill_request(request_id: str, body: Any, api_key: str, session_id: str, scope: str = "default") -> tuple[int, dict[str, Any]]:
    with _lock:
        _ensure_requests_loaded(scope)
        req = _requests.get(request_id)
        now = time.time()
        if not req or (session_id is not None and req["session_id"] != session_id) or req.get("scope") != scope:
            return 404, {"status": "not_found"}
        if req["expires_at"] <= now:
            req["status"] = "expired"
            _persist_requests(scope)
            return 410, {"status": "expired"}
        if req["status"] != "pending":
            return 409, {"status": "consumed"}
        if not isinstance(body, dict) or body.get("decision") not in ("fulfill", "reject"):
            return 400, {"status": "rejected"}
        req["status"] = "consuming"
        _persist_requests(scope)
    if body["decision"] == "reject":
        with _lock:
            req["status"] = "rejected"
            _persist_requests(scope)
            _audit({"at": int(time.time()), "action": "request.rejected",
                    "id": request_id}, scope)
        return 200, {"status": "rejected"}
    values = body.get("values")
    if not isinstance(values, dict) or set(values) != set(req["fields"]):
        with _lock:
            req["status"] = "pending"
            _persist_requests(scope)
        return 400, {"status": "rejected"}
    status, result = write_entry({
        "name": req["service"], "service": req["service"],
        "domains": [req["domain"]], "values": values,
        "username": body.get("username"),
    }, api_key, scope=scope)
    with _lock:
        req["status"] = "fulfilled" if status == 200 else "failed"
        _persist_requests(scope)
        _audit({"at": int(time.time()),
                "action": "request.fulfilled" if status == 200 else "request.fulfillment_failed",
                "id": request_id}, scope)
    if status != 200:
        return status, {"status": "unavailable"}
    return 200, {"status": "fulfilled", "credential_ref": result["id"]}


def vault_use(entry_id: str, domain: str, purpose: str, operation: str, *, api_key: str, scope: str = "default") -> dict[str, Any]:
    domain = (domain or "").strip().lower().rstrip(".")
    with _lock:
        row = _load(scope)["entries"].get(entry_id)
        if not row or row.get("revoked"):
            _audit({"at": int(time.time()), "action": "vault.use.denied", "id": entry_id, "reason": "not_found"}, scope)
            return {"status": "denied", "summary": "credential unavailable"}
        if domain not in row.get("domains", []):
            _audit({"at": int(time.time()), "action": "vault.use.denied", "id": entry_id, "domain": domain, "reason": "domain_mismatch"}, scope)
            return {"status": "denied", "summary": "domain not authorized"}
        executor = OPERATIONS.get((purpose, operation))
        if executor is None or AESGCM is None:
            _audit({"at": int(time.time()), "action": "vault.use.denied", "id": entry_id, "domain": domain, "purpose": purpose, "operation": operation, "reason": "operation_not_allowed"}, scope)
            return {"status": "denied", "summary": "operation not allowlisted"}
        sealed = row["sealed"]
    try:
        values = None
        values = json.loads(AESGCM(_key(api_key)).decrypt(base64.b64decode(sealed["nonce"]), base64.b64decode(sealed["ciphertext"]), None))
        outcome = executor(domain=domain, values=values)
        if not isinstance(outcome, dict):
            outcome = {"status": "failed", "summary": "operation failed"}
        safe = {"status": str(outcome.get("status", "completed"))[:32], "summary": str(outcome.get("summary", "completed"))[:240]}
    except Exception:
        safe = {"status": "failed", "summary": "operation failed"}
    finally:
        values = None
    _audit({"at": int(time.time()), "action": "vault.use", "id": entry_id, "domain": domain, "purpose": purpose, "operation": operation, "status": safe["status"]}, scope)
    return {"credential_ref": entry_id, **safe}


def request_status(request_id: str, session_id: str, scope: str = "default") -> dict[str, Any] | None:
    with _lock:
        _ensure_requests_loaded(scope)
        req = _requests.get(request_id)
        if not req or (session_id is not None and req["session_id"] != session_id) or req.get("scope") != scope:
            return None
        if req["status"] == "pending" and req["expires_at"] <= time.time():
            req["status"] = "expired"
            _persist_requests(scope)
        return {"request_id": request_id, "status": req["status"], "expires_at": int(req["expires_at"])}


def request_block(request_id: str, session_id: str | None, scope: str = "default") -> dict[str, Any] | None:
    """Canonical structured ``vault_request`` block for one request.

    This is the single source of truth for the block the gateway stamps
    onto the turn's final assistant message (2.17.2, structured
    delivery): the tool handler parks only the request id, and both the
    terminal attach and any later re-read rebuild the block here, so a
    parked copy can never drift from the vault's live record. The
    ``status`` is computed against the live TTL without mutating the
    stored row. Returns None when the request is unknown to the caller.
    """
    with _lock:
        _ensure_requests_loaded(scope)
        req = _requests.get(request_id)
        if not req or (session_id is not None and req["session_id"] != session_id) or req.get("scope") != scope:
            return None
        status = req["status"]
        if status == "pending" and req["expires_at"] <= time.time():
            status = "expired"
        return {
            "type": "vault_request",
            "request_id": request_id,
            "service": req["service"],
            "domain": req["domain"],
            "reason": req["reason"],
            "fields": canonical_field_order(req["fields"]),
            "status": status,
            "expires_at": int(req["expires_at"]),
        }
