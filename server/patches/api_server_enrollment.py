"""Device enrollment store & thread-safe async queue (extracted from api_server.py, Phase 5.1)."""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import os
import secrets
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Optional

_ENROLLMENT_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # pairing.py ALPHABET
_ENROLLMENT_CODE_LENGTH = 20        # QR-carried, ~100 bits, never typed
_ENROLLMENT_TTL_SECONDS = 300       # ledger 153 cites OpenBot's 2 min; 5 min
                                    # leaves room for the first-run camera
                                    # permission prompt on the new device
_ENROLLMENT_MAX_PENDING = 3         # pairing.py MAX_PENDING_PER_PLATFORM
_ENROLLMENT_MAX_FAILED = 5          # pairing.py MAX_FAILED_ATTEMPTS
_ENROLLMENT_LOCKOUT_SECONDS = 600


def _enrollment_store_path() -> Path:
    try:
        from hermes_constants import get_hermes_home
        root = Path(get_hermes_home())
    except Exception:
        root = Path(os.environ.get("HERMES_HOME") or (Path.home() / ".hermes"))
    return root / "enrollment" / "device-enrollment.json"


class _EnrollmentStore:
    """JSON-file store for one-time device-enrollment codes.

    Only salted SHA-256 hashes of codes are persisted (chmod 0600), the
    same discipline as gateway/pairing.py. A process-level lock serializes
    the gateway's own handlers; this process is the file's only writer.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._path = _enrollment_store_path()

    def _load(self) -> dict:
        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
        except Exception:
            pass
        return {}

    def _save(self, data: dict) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self._path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data), encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(self._path)

    def _instance_id(self, data: dict) -> str:
        instance_id = data.get("instance_id")
        if not isinstance(instance_id, str) or not instance_id:
            instance_id = uuid.uuid4().hex + uuid.uuid4().hex
            data["instance_id"] = instance_id
            self._save(data)
        return instance_id

    @staticmethod
    def _fingerprint_of(instance_id: str) -> str:
        return hashlib.sha256(instance_id.encode("utf-8")).hexdigest()[:16]

    def fingerprint(self) -> str:
        with self._lock:
            data = self._load()
            return self._fingerprint_of(self._instance_id(data))

    @staticmethod
    def _hash_code(code: str, salt: bytes) -> str:
        # gateway/pairing.py PairingStore._hash_code, same morphology.
        return hashlib.sha256(salt + code.encode("utf-8")).hexdigest()

    @staticmethod
    def _cleanup(data: dict, now: float) -> None:
        codes = data.get("codes")
        if isinstance(codes, dict):
            stale = [k for k, v in codes.items()
                     if not isinstance(v, dict)
                     or float(v.get("expires_at") or 0) <= now]
            for key in stale:
                del codes[key]

    def issue(self) -> Optional[dict]:
        """Mint a one-time code; {code, expires_at} or None when the
        pending cap is reached."""
        now = time.time()
        with self._lock:
            data = self._load()
            self._instance_id(data)
            self._cleanup(data, now)
            codes = data.setdefault("codes", {})
            if len(codes) >= _ENROLLMENT_MAX_PENDING:
                self._save(data)
                return None
            code = "".join(secrets.choice(_ENROLLMENT_ALPHABET)
                           for _ in range(_ENROLLMENT_CODE_LENGTH))
            salt = os.urandom(16)
            codes[uuid.uuid4().hex[:16]] = {
                "hash": self._hash_code(code, salt), "salt": salt.hex(),
                "created_at": now, "expires_at": now + _ENROLLMENT_TTL_SECONDS,
            }
            self._save(data)
            return {"code": code, "expires_at": now + _ENROLLMENT_TTL_SECONDS}

    def claim(self, code: str) -> tuple[str, Optional[dict]]:
        """Redeem a code exactly once. Returns (outcome, payload) with
        outcome "ok" (payload carries the instance fingerprint),
        "invalid", "expired", or "locked"."""
        now = time.time()
        code = "".join(str(code or "").upper().split())
        with self._lock:
            data = self._load()
            fingerprint = self._fingerprint_of(self._instance_id(data))
            if float(data.get("locked_until") or 0) > now:
                return "locked", None
            codes = data.get("codes")
            if not isinstance(codes, dict):
                codes = {}
            matched_key = None
            matched_expired = False
            for entry_id, entry in codes.items():
                if not isinstance(entry, dict):
                    continue
                try:
                    salt = bytes.fromhex(entry["salt"])
                except (KeyError, ValueError):
                    continue
                if hmac.compare_digest(self._hash_code(code, salt),
                                       str(entry.get("hash") or "")):
                    matched_key = entry_id
                    matched_expired = float(entry.get("expires_at") or 0) <= now
                    break
            if matched_key is not None:
                del codes[matched_key]
                if matched_expired:
                    self._save(data)
                    return "expired", None
                data["failed_attempts"] = 0
                self._save(data)
                return "ok", {"fingerprint": fingerprint}
            self._cleanup(data, now)
            failed = int(data.get("failed_attempts") or 0) + 1
            if failed >= _ENROLLMENT_MAX_FAILED:
                data["locked_until"] = now + _ENROLLMENT_LOCKOUT_SECONDS
                failed = 0
            data["failed_attempts"] = failed
            self._save(data)
            return "invalid", None


_enrollment_store = _EnrollmentStore()


def __getattr__(name: str):
    """Resolve shared SSE limits from api_server after its initialization completes."""
    if name in {
        "API_SERVER_HEARTBEAT_SECONDS",
        "API_SERVER_LATENCY_SAMPLE_LIMIT",
        "CHAT_COMPLETIONS_SSE_KEEPALIVE_SECONDS",
        "MAX_CONTENT_LIST_SIZE",
        "MAX_NORMALIZED_TEXT_LENGTH",
        "RESPONSES_AUTO_TRUNCATION_HISTORY_LIMIT",
    }:
        try:
            from gateway.platforms import api_server
        except ImportError:
            import api_server
        return getattr(api_server, name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


class ThreadSafeAsyncQueue(asyncio.Queue):
    """``asyncio.Queue`` a non-loop thread (run_conversation's executor) can push into via
    ``put_threadsafe``; the SSE consumer's ``await get()`` is woken by ``call_soon_threadsafe``."""

    def put_threadsafe(self, item, *, loop: asyncio.AbstractEventLoop | None = None) -> None:
        (loop or self._loop_ref).call_soon_threadsafe(self.put_nowait, item)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Always constructed inside a running async handler (the SSE
        # request handlers below), so get_running_loop() is safe here.
        self._loop_ref = asyncio.get_running_loop()


