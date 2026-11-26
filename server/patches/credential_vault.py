"""Encrypted credential metadata and one-time request surface.

The vault derives its AES-GCM key from the existing API_SERVER_KEY. This
single-key design is provisional and requires a separate key-lifecycle ADR.
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
REQUEST_TTL = 15 * 60
FIELDS = frozenset({"username", "password", "token", "api_key", "secret", "otp"})
OPERATIONS: dict[tuple[str, str], Callable[..., dict[str, Any]]] = {}
_lock = threading.RLock()
_requests: dict[str, dict[str, Any]] = {}


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
    if not isinstance(raw, list) or not raw or len(raw) > 32:
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
    if not isinstance(name, str) or not name.strip() or len(name) > 120 or not isinstance(service, str) or not service.strip() or len(service) > 120 or not domains:
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
        for key, req in list(_requests.items()):
            if req["expires_at"] <= now or req["status"] != "pending":
                _requests.pop(key, None)
        for req in _requests.values():
            if req["session_id"] == session_id and req.get("scope") == scope and req["status"] == "pending":
                req["status"] = "superseded"
        _requests[request_id] = {
            "service": service[:120], "domain": clean_domain,
            "reason": (reason or "")[:240], "fields": sorted(set(fields)),
            "session_id": session_id, "created_at": now,
            "expires_at": now + REQUEST_TTL, "status": "pending", "scope": scope,
        }
        _audit({"at": int(now), "action": "request.created", "id": request_id,
                "service": service[:120], "domain": clean_domain,
                "fields": sorted(set(fields))}, scope)
    return {"request_id": request_id, "status": "pending", "expires_at": int(now + REQUEST_TTL)}


def list_requests(session_id: str, scope: str = "default", status: str | None = "pending") -> list[dict[str, Any]]:
    now = time.time()
    with _lock:
        rows = []
        for request_id, req in _requests.items():
            if req["session_id"] != session_id or req.get("scope") != scope:
                continue
            if req["status"] == "pending" and req["expires_at"] <= now:
                req["status"] = "expired"
            if status not in (None, "") and req["status"] != status:
                continue
            rows.append((req["created_at"], {
                "request_id": request_id,
                "service": req["service"],
                "domain": req["domain"],
                "reason": req["reason"],
                "fields": list(req["fields"]),
                "status": req["status"],
                "expires_at": int(req["expires_at"]),
            }))
        rows.sort(key=lambda item: item[0], reverse=True)
        return [row for _, row in rows]


def fulfill_request(request_id: str, body: Any, api_key: str, session_id: str, scope: str = "default") -> tuple[int, dict[str, Any]]:
    with _lock:
        req = _requests.get(request_id)
        now = time.time()
        if not req or req["session_id"] != session_id or req.get("scope") != scope:
            return 404, {"status": "not_found"}
        if req["expires_at"] <= now:
            req["status"] = "expired"
            return 410, {"status": "expired"}
        if req["status"] != "pending":
            return 409, {"status": "consumed"}
        if not isinstance(body, dict) or body.get("decision") not in ("fulfill", "reject"):
            return 400, {"status": "rejected"}
        req["status"] = "consuming"
    if body["decision"] == "reject":
        with _lock:
            req["status"] = "rejected"
            _audit({"at": int(time.time()), "action": "request.rejected",
                    "id": request_id}, scope)
        return 200, {"status": "rejected"}
    values = body.get("values")
    if not isinstance(values, dict) or set(values) != set(req["fields"]):
        with _lock:
            req["status"] = "pending"
        return 400, {"status": "rejected"}
    status, result = write_entry({
        "name": req["service"], "service": req["service"],
        "domains": [req["domain"]], "values": values,
        "username": body.get("username"),
    }, api_key, scope=scope)
    with _lock:
        req["status"] = "fulfilled" if status == 200 else "failed"
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
        req = _requests.get(request_id)
        if not req or req["session_id"] != session_id or req.get("scope") != scope:
            return None
        if req["status"] == "pending" and req["expires_at"] <= time.time():
            req["status"] = "expired"
        return {"request_id": request_id, "status": req["status"], "expires_at": int(req["expires_at"])}
