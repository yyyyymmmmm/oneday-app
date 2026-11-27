"""Short-lived access/refresh token auth (ADR #1, finalized parameters).

Parameters (docs/short-lived-token-adr.md):
- Access Token TTL: 24 hours (86400s), HMAC-SHA256 signed compact token
  ``odt1.<payload_b64url>.<sig_b64url>``.
- Refresh Token TTL: 30 days sliding (2592000s), 90 days absolute max
  (7776000s), stored ONLY as salted SHA-256 hash in chmod-0600 JSON store.
- Rotation: every refresh rotates the refresh token, keeps a 10-second
  grace window (returning the same newly minted pair for concurrent
  cold-start requests), and enforces Reuse Detection (reusing a rotated
  token outside the grace window revokes the entire device session).
- Phase-1 Revocation: delete/mark revoked in server session table;
  access token carries ``sid`` and is checked against active sessions.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import secrets
import threading
import time
import uuid
from pathlib import Path
from typing import Any

logger = logging.getLogger("gateway.platforms.auth_tokens")

STORE_PATH = Path(os.environ.get(
    "AUTH_SESSIONS_PATH", "/opt/data/auth/sessions.json"))

ACCESS_TTL_SECONDS = 24 * 3600           # 24 hours
REFRESH_SLIDING_TTL_SECONDS = 30 * 86400 # 30 days sliding
REFRESH_MAX_TTL_SECONDS = 90 * 86400     # 90 days absolute cap
ROTATION_GRACE_SECONDS = 10.0            # 10s grace window for concurrent refreshes
MAX_SESSIONS = 64
TOKEN_PREFIX = "odt1."

_lock = threading.RLock()


def _b64u_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64u_decode(text: str) -> bytes:
    pad = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + pad)


def _hash_token(token: str, salt_hex: str) -> str:
    salt = bytes.fromhex(salt_hex)
    return hashlib.sha256(salt + token.encode("utf-8")).hexdigest()


def _signing_key(api_key: str) -> bytes:
    return hashlib.sha256(f"oneday-short-token-v1:{api_key}".encode("utf-8")).digest()


def _sign_access_token(
    *, session_id: str, now: float, ttl: int, api_key: str
) -> tuple[str, int]:
    exp = int(now) + int(ttl)
    payload = {
        "v": 1,
        "typ": "access",
        "sid": session_id,
        "iat": int(now),
        "exp": exp,
        "jti": uuid.uuid4().hex[:12],
    }
    payload_b64 = _b64u_encode(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    )
    sig = hmac.new(_signing_key(api_key), payload_b64.encode("ascii"), hashlib.sha256).digest()
    return f"{TOKEN_PREFIX}{payload_b64}.{_b64u_encode(sig)}", exp


try:
    from gateway.platforms import oneday_db as _oneday_db
except ImportError:
    try:
        import oneday_db as _oneday_db  # type: ignore
    except ImportError:
        _oneday_db = None


def _load_locked() -> dict[str, dict[str, Any]]:
    if _oneday_db is not None:
        try:
            return _oneday_db.load_auth_sessions(STORE_PATH)
        except Exception:
            logger.exception("auth_tokens: sqlite store read failed; falling back to JSON")
    try:
        raw = json.loads(STORE_PATH.read_text(encoding="utf-8"))
        if isinstance(raw, dict) and isinstance(raw.get("sessions"), dict):
            return {
                k: v for k, v in raw["sessions"].items()
                if isinstance(k, str) and isinstance(v, dict)
            }
    except FileNotFoundError:
        return {}
    except Exception:
        logger.exception("auth_tokens: store read failed")
    return {}


def _save_locked(sessions: dict[str, dict[str, Any]]) -> None:
    if _oneday_db is not None:
        try:
            _oneday_db.save_auth_sessions(sessions, STORE_PATH)
        except Exception:
            logger.exception("auth_tokens: sqlite store write failed")
    STORE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = STORE_PATH.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "sessions": sessions}, f, ensure_ascii=False, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, STORE_PATH)


def _prune_locked(sessions: dict[str, dict[str, Any]], now: float) -> None:
    expired = [
        sid for sid, rec in sessions.items()
        if float(rec.get("max_expires_at") or 0) <= now
        and (rec.get("revoked") or float(rec.get("refresh_expires_at") or 0) <= now)
    ]
    for sid in expired:
        sessions.pop(sid, None)
    if len(sessions) > MAX_SESSIONS:
        ordered = sorted(
            sessions.items(),
            key=lambda kv: float(kv[1].get("last_used_at") or 0),
            reverse=True,
        )
        sessions.clear()
        sessions.update(ordered[:MAX_SESSIONS])


def exchange_key_for_tokens(
    *,
    api_key: str,
    device_name: str = "",
    app_version: str = "",
    now: float | None = None,
) -> dict[str, Any]:
    """Mint a new device session + (access_token, refresh_token) pair."""
    ts = time.time() if now is None else float(now)
    session_id = f"sess_{uuid.uuid4().hex[:16]}"
    refresh_token = f"odr1.{session_id}.{secrets.token_urlsafe(32)}"
    salt_hex = os.urandom(16).hex()
    access_token, access_exp = _sign_access_token(
        session_id=session_id, now=ts, ttl=ACCESS_TTL_SECONDS, api_key=api_key
    )
    refresh_exp = min(ts + REFRESH_SLIDING_TTL_SECONDS, ts + REFRESH_MAX_TTL_SECONDS)

    record = {
        "session_id": session_id,
        "device_name": str(device_name or "").strip()[:120] or "OneDay Device",
        "app_version": str(app_version or "").strip()[:64] or "unknown",
        "created_at": ts,
        "last_used_at": ts,
        "max_expires_at": ts + REFRESH_MAX_TTL_SECONDS,
        "refresh_expires_at": refresh_exp,
        "current_salt": salt_hex,
        "current_hash": _hash_token(refresh_token, salt_hex),
        "previous_hashes": [],
        "grace_prev_salt": None,
        "grace_prev_hash": None,
        "grace_until": 0.0,
        "grace_cached_response": None,
        "revoked": False,
        "revoked_reason": None,
    }
    with _lock:
        sessions = _load_locked()
        _prune_locked(sessions, ts)
        sessions[session_id] = record
        _save_locked(sessions)

    return {
        "token_type": "Bearer",
        "session_id": session_id,
        "access_token": access_token,
        "expires_in": ACCESS_TTL_SECONDS,
        "access_expires_at": access_exp,
        "refresh_token": refresh_token,
        "refresh_expires_at": int(refresh_exp),
    }


def refresh_tokens(
    *,
    refresh_token: str,
    api_key: str,
    app_version: str | None = None,
    now: float | None = None,
) -> tuple[int, dict[str, Any]]:
    """Rotate refresh_token with 10s grace window and reuse detection."""
    ts = time.time() if now is None else float(now)
    raw = str(refresh_token or "").strip()
    parts = raw.split(".")
    if len(parts) != 3 or parts[0] != "odr1" or not parts[1]:
        return 401, {"error": "Invalid refresh token format", "code": "invalid_refresh_token"}
    session_id = parts[1]

    with _lock:
        sessions = _load_locked()
        rec = sessions.get(session_id)
        if not rec:
            return 401, {"error": "Session not found", "code": "invalid_refresh_token"}
        if rec.get("revoked"):
            return 401, {"error": "Session has been revoked", "code": "session_revoked"}
        if ts >= float(rec.get("max_expires_at") or 0) or ts >= float(rec.get("refresh_expires_at") or 0):
            return 401, {"error": "Refresh token expired", "code": "refresh_token_expired"}

        # Check 10s grace window first (handles concurrent cold-start refreshes safely).
        grace_salt = rec.get("grace_prev_salt")
        grace_hash = rec.get("grace_prev_hash")
        if grace_salt and grace_hash and ts <= float(rec.get("grace_until") or 0):
            if hmac.compare_digest(_hash_token(raw, grace_salt), str(grace_hash)):
                cached = rec.get("grace_cached_response")
                if isinstance(cached, dict):
                    return 200, dict(cached)

        # Check current active refresh token hash.
        cur_salt = str(rec.get("current_salt") or "")
        cur_hash = str(rec.get("current_hash") or "")
        if cur_salt and cur_hash and hmac.compare_digest(_hash_token(raw, cur_salt), cur_hash):
            new_refresh = f"odr1.{session_id}.{secrets.token_urlsafe(32)}"
            new_salt = os.urandom(16).hex()
            new_hash = _hash_token(new_refresh, new_salt)
            access_token, access_exp = _sign_access_token(
                session_id=session_id, now=ts, ttl=ACCESS_TTL_SECONDS, api_key=api_key
            )
            new_refresh_exp = min(ts + REFRESH_SLIDING_TTL_SECONDS, float(rec["max_expires_at"]))

            prev_list = list(rec.get("previous_hashes") or [])
            if grace_salt and grace_hash:
                prev_list.append({"salt": grace_salt, "hash": grace_hash})
            prev_list = prev_list[-16:]  # keep recent history for reuse detection

            response = {
                "token_type": "Bearer",
                "session_id": session_id,
                "access_token": access_token,
                "expires_in": ACCESS_TTL_SECONDS,
                "access_expires_at": access_exp,
                "refresh_token": new_refresh,
                "refresh_expires_at": int(new_refresh_exp),
            }

            rec["grace_prev_salt"] = cur_salt
            rec["grace_prev_hash"] = cur_hash
            rec["grace_until"] = ts + ROTATION_GRACE_SECONDS
            rec["grace_cached_response"] = response
            rec["previous_hashes"] = prev_list
            rec["current_salt"] = new_salt
            rec["current_hash"] = new_hash
            rec["last_used_at"] = ts
            rec["refresh_expires_at"] = new_refresh_exp
            if app_version:
                rec["app_version"] = str(app_version).strip()[:64] or rec["app_version"]
            _save_locked(sessions)
            return 200, response

        # Reuse detection: check expired grace slot or historical hashes -> revoke entire family!
        reused = False
        if grace_salt and grace_hash:
            if hmac.compare_digest(_hash_token(raw, grace_salt), str(grace_hash)):
                reused = True
        if not reused:
            for item in rec.get("previous_hashes") or ():
                if isinstance(item, dict) and item.get("salt") and item.get("hash"):
                    if hmac.compare_digest(_hash_token(raw, str(item["salt"])), str(item["hash"])):
                        reused = True
                        break
        if reused:
            rec["revoked"] = True
            rec["revoked_reason"] = "refresh_token_reuse_detected"
            rec["grace_cached_response"] = None
            _save_locked(sessions)
            logger.warning("auth_tokens: reuse detected for %s; session family revoked", session_id)
            return 401, {
                "error": "Refresh token reuse detected; device session revoked",
                "code": "refresh_token_reused",
            }

        return 401, {"error": "Invalid refresh token", "code": "invalid_refresh_token"}


def verify_access_token(
    token: str,
    *,
    api_key: str,
    now: float | None = None,
) -> tuple[bool, str | None, str | None]:
    """Verify an ``odt1.*`` access token. Returns ``(ok, session_id, error_code)``."""
    ts = time.time() if now is None else float(now)
    if not token.startswith(TOKEN_PREFIX):
        return False, None, "not_short_token"
    body = token[len(TOKEN_PREFIX):]
    if "." not in body:
        return False, None, "invalid_access_token"
    payload_b64, sig_b64 = body.split(".", 1)
    expected_sig = hmac.new(
        _signing_key(api_key), payload_b64.encode("ascii"), hashlib.sha256
    ).digest()
    try:
        actual_sig = _b64u_decode(sig_b64)
    except Exception:
        return False, None, "invalid_access_token"
    if not hmac.compare_digest(actual_sig, expected_sig):
        return False, None, "invalid_access_token"
    try:
        payload = json.loads(_b64u_decode(payload_b64).decode("utf-8"))
    except Exception:
        return False, None, "invalid_access_token"
    if not isinstance(payload, dict) or payload.get("typ") != "access":
        return False, None, "invalid_access_token"
    if ts >= float(payload.get("exp") or 0):
        return False, None, "access_token_expired"
    session_id = str(payload.get("sid") or "")
    if not session_id:
        return False, None, "invalid_access_token"
    with _lock:
        sessions = _load_locked()
        rec = sessions.get(session_id)
        if not rec or rec.get("revoked"):
            return False, None, "session_revoked"
    return True, session_id, None


def list_sessions() -> list[dict[str, Any]]:
    """Return active + recently revoked device sessions (safe metadata only)."""
    with _lock:
        sessions = _load_locked()
    rows = sorted(
        sessions.values(),
        key=lambda r: float(r.get("last_used_at") or 0),
        reverse=True,
    )
    return [
        {
            "session_id": r.get("session_id"),
            "device_name": r.get("device_name"),
            "app_version": r.get("app_version"),
            "created_at": r.get("created_at"),
            "last_used_at": r.get("last_used_at"),
            "refresh_expires_at": r.get("refresh_expires_at"),
            "revoked": bool(r.get("revoked")),
            "revoked_reason": r.get("revoked_reason"),
        }
        for r in rows
    ]


def revoke_session(
    *,
    session_id: str | None = None,
    all_other_devices: bool = False,
    keep_session_id: str | None = None,
) -> tuple[int, dict[str, Any]]:
    """Revoke one session_id or all sessions except keep_session_id."""
    with _lock:
        sessions = _load_locked()
        revoked_ids: list[str] = []
        if all_other_devices:
            for sid, rec in sessions.items():
                if keep_session_id and sid == keep_session_id:
                    continue
                if not rec.get("revoked"):
                    rec["revoked"] = True
                    rec["revoked_reason"] = "user_revoked_other_devices"
                    rec["grace_cached_response"] = None
                    revoked_ids.append(sid)
            if revoked_ids:
                _save_locked(sessions)
            return 200, {"revoked": len(revoked_ids), "session_ids": revoked_ids}

        target = str(session_id or "").strip()
        if not target:
            return 400, {"error": "session_id or all_other_devices is required", "code": "invalid_request"}
        rec = sessions.get(target)
        if not rec:
            return 200, {"revoked": 0, "session_ids": []}
        if not rec.get("revoked"):
            rec["revoked"] = True
            rec["revoked_reason"] = "user_revoked"
            rec["grace_cached_response"] = None
            revoked_ids.append(target)
            _save_locked(sessions)
        return 200, {"revoked": len(revoked_ids), "session_ids": revoked_ids}
