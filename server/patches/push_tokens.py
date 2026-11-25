"""APNs device push-token registry (local patch, batch 4b).

Receiving end for the OneDay iOS app's push token registration
(``Sources/OneDayCore/PushRegistration.swift``):

- ``POST /v1/push/tokens`` accepts:
  ``{"device_token": "<hex>", "environment": "sandbox"|"production",
     "bundle_id": "...", "app_version": "..."}``
  performs an idempotent upsert keyed by ``device_token``, and returns
  ``{"registered": true, "environment": "...", "updated_at": "..."}``.
- ``GET /v1/push/tokens`` lists registered tokens (masked preview + metadata)
  for diagnostics / APNs sender readiness checks.
- ``DELETE /v1/push/tokens/{device_token}`` unregisters one device token.

Storage is an atomic chmod-0600 JSON file under
``PUSH_TOKENS_PATH`` (default ``/opt/data/push/tokens.json``), bounded to
``MAX_TOKENS`` entries (evicting oldest ``updated_at`` on overflow).
"""

from __future__ import annotations

import json
import logging
import os
import re
import threading
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger("gateway.platforms.push_tokens")

STORE_PATH = Path(os.environ.get(
    "PUSH_TOKENS_PATH", "/opt/data/push/tokens.json"))
MAX_TOKENS = 32
_ENVIRONMENTS = frozenset({"sandbox", "production"})
_HEX_TOKEN_RE = re.compile(r"^[0-9a-f]{32,512}$")
_MAX_STR = 160

_lock = threading.RLock()


def _now_iso() -> str:
    return datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z")


def _clean_str(value, cap: int = _MAX_STR) -> str | None:
    if not isinstance(value, str):
        return None
    out = value.strip()[:cap]
    return out or None


def _load_locked() -> dict[str, dict]:
    try:
        raw = json.loads(STORE_PATH.read_text(encoding="utf-8"))
        if isinstance(raw, dict) and isinstance(raw.get("tokens"), dict):
            return {
                k: v for k, v in raw["tokens"].items()
                if isinstance(k, str) and isinstance(v, dict)
            }
    except FileNotFoundError:
        return {}
    except Exception:
        logger.exception("push_tokens: store read failed")
    return {}


def _save_locked(tokens: dict[str, dict]) -> None:
    STORE_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": 1,
        "updated_at": _now_iso(),
        "tokens": tokens,
    }
    tmp = STORE_PATH.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, STORE_PATH)


def register_token(body) -> tuple[int, dict]:
    """Validate and upsert one APNs device token. Returns ``(status, payload)``."""
    if not isinstance(body, dict):
        return 400, {"error": "Request body must be a JSON object", "code": "invalid_request"}

    raw_token = body.get("device_token")
    if not isinstance(raw_token, str):
        return 400, {"error": "Missing or invalid device_token", "code": "invalid_device_token"}
    token = raw_token.strip().lower()
    if len(token) % 2 != 0 or not _HEX_TOKEN_RE.match(token):
        return 400, {"error": "device_token must be an even-length lowercase hex string", "code": "invalid_device_token"}

    env = body.get("environment")
    if env not in _ENVIRONMENTS:
        return 400, {"error": "environment must be 'sandbox' or 'production'", "code": "invalid_environment"}

    bundle_id = _clean_str(body.get("bundle_id"))
    if not bundle_id:
        return 400, {"error": "Missing bundle_id", "code": "invalid_bundle_id"}

    app_version = _clean_str(body.get("app_version"), 64) or "unknown"
    now = _now_iso()

    with _lock:
        tokens = _load_locked()
        existing = tokens.get(token)
        created_at = (existing.get("created_at") if isinstance(existing, dict) else None) or now
        tokens[token] = {
            "device_token": token,
            "environment": env,
            "bundle_id": bundle_id,
            "app_version": app_version,
            "created_at": created_at,
            "updated_at": now,
        }
        if len(tokens) > MAX_TOKENS:
            ordered = sorted(
                tokens.items(),
                key=lambda item: str(item[1].get("updated_at") or ""),
                reverse=True,
            )
            tokens = dict(ordered[:MAX_TOKENS])
        _save_locked(tokens)

    return 200, {
        "registered": True,
        "environment": env,
        "bundle_id": bundle_id,
        "updated_at": now,
    }


def list_tokens(*, include_raw: bool = False) -> list[dict]:
    """Return registered tokens newest-first (masked by default)."""
    with _lock:
        tokens = _load_locked()
    rows = sorted(
        tokens.values(),
        key=lambda r: str(r.get("updated_at") or ""),
        reverse=True,
    )
    out = []
    for row in rows:
        tok = str(row.get("device_token") or "")
        entry = {
            "token_preview": (tok[:8] + "..." + tok[-6:]) if len(tok) > 16 else tok,
            "environment": row.get("environment"),
            "bundle_id": row.get("bundle_id"),
            "app_version": row.get("app_version"),
            "created_at": row.get("created_at"),
            "updated_at": row.get("updated_at"),
        }
        if include_raw:
            entry["device_token"] = tok
        out.append(entry)
    return out


def delete_token(device_token: str) -> tuple[int, dict]:
    """Unregister one device token (idempotent)."""
    token = (device_token or "").strip().lower()
    if not token:
        return 400, {"error": "Missing device_token", "code": "invalid_device_token"}
    with _lock:
        tokens = _load_locked()
        existed = token in tokens
        if existed:
            del tokens[token]
            _save_locked(tokens)
    return 200, {"deleted": existed}
