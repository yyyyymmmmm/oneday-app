"""Pure projection and request-parsing helpers extracted from api_server.py (#44).

Preserves exact projection semantics for reactions, options cards, and
canonical-ordered vault_request blocks (2.18.3) while shrinking ``api_server.py``.
"""

from __future__ import annotations

import json
from typing import Any, Optional

_TRUE_REQUEST_BOOL_STRINGS = frozenset({"1", "true", "yes", "on"})
_FALSE_REQUEST_BOOL_STRINGS = frozenset({"0", "false", "no", "off"})
_USAGE_TOKEN_KEYS = ("input_tokens", "output_tokens", "total_tokens")


def _approval_event_choices(
    *, smart_denied: bool, allow_session: bool, allow_permanent: bool
) -> list[str]:
    if smart_denied or not allow_session:
        return ["once", "deny"]
    return ["once", "session", "always", "deny"] if allow_permanent else ["once", "session", "deny"]


def _coerce_request_bool(value: Any, default: bool = False) -> bool:
    """Normalize boolean-like payload values; only explicit bool-ish scalars count."""
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in _TRUE_REQUEST_BOOL_STRINGS:
            return True
        return False if normalized in _FALSE_REQUEST_BOOL_STRINGS else default
    return bool(value) if isinstance(value, (int, float)) else default


def _clean_request_string(value: Any) -> Optional[str]:
    """Return a stripped request string, or None for absent/non-string values."""
    return (value.strip() or None) if isinstance(value, str) else None


def _chat_usage_payload(usage: dict[str, Any]) -> dict[str, int]:
    """OpenAI Chat Completions ``usage`` block from the agent's usage."""
    values = (usage.get(key, 0) for key in _USAGE_TOKEN_KEYS)
    return dict(zip(("prompt_tokens", "completion_tokens", "total_tokens"), values))


def _responses_usage_payload(usage: dict[str, Any]) -> dict[str, int]:
    """OpenAI Responses ``usage`` block from the agent's usage dict."""
    return {key: usage.get(key, 0) for key in _USAGE_TOKEN_KEYS}


def _reactions_from_display_metadata(meta: Any) -> list[dict[str, Any]]:
    """Well-formed reaction dicts from a message row's display_metadata."""
    if isinstance(meta, str):
        try:
            meta = json.loads(meta)
        except Exception:
            return []
    if not isinstance(meta, dict):
        return []
    reactions = meta.get("reactions")
    if not isinstance(reactions, list):
        return []
    return [r for r in reactions if isinstance(r, dict)]


def _options_from_display_metadata(meta: Any) -> dict[str, Any]:
    """Well-formed option-card payload from a message row's display_metadata."""
    if isinstance(meta, str):
        try:
            meta = json.loads(meta)
        except Exception:
            return {}
    if not isinstance(meta, dict):
        return {}
    payload = meta.get("options")
    if not isinstance(payload, dict):
        return {}
    items = payload.get("options")
    if not isinstance(items, list):
        return {}
    cleaned = []
    for item in items:
        if not isinstance(item, dict):
            continue
        label = item.get("label")
        if not isinstance(label, str) or not label:
            continue
        entry = {"label": label}
        send_text = item.get("send_text")
        entry["send_text"] = send_text if isinstance(send_text, str) and send_text else label
        cleaned.append(entry)
    if not cleaned:
        return {}
    projected: dict[str, Any] = {"v": payload.get("v") or 1, "options": cleaned}
    at = payload.get("at")
    if isinstance(at, (int, float)):
        projected["at"] = at
    return projected


def _canonical_vault_field_order(fields: Any) -> list[str]:
    """Canonical request-card field order (account, password, rest)."""
    try:
        from gateway.platforms.credential_vault import canonical_field_order
        return canonical_field_order(fields)
    except ImportError:
        def rank(field: str) -> int:
            name = field.strip().lower()
            if name in ("username", "account", "email", "用户名", "账号"):
                return 0
            if name in ("password", "密码"):
                return 1
            return 2

        unique = [f for f in dict.fromkeys(fields) if isinstance(f, str) and f]
        return sorted(unique, key=rank)


def _vault_request_from_display_metadata(meta: Any) -> dict[str, Any]:
    """Well-formed vault-request block from a message row's display_metadata."""
    if isinstance(meta, str):
        try:
            meta = json.loads(meta)
        except Exception:
            return {}
    if not isinstance(meta, dict):
        return {}
    payload = meta.get("vault_request")
    if not isinstance(payload, dict) or payload.get("type") != "vault_request":
        return {}
    request_id = payload.get("request_id")
    service = payload.get("service")
    fields = payload.get("fields")
    status = payload.get("status")
    if not isinstance(request_id, str) or not request_id.startswith("vreq_"):
        return {}
    if not isinstance(service, str) or not service:
        return {}
    if not isinstance(fields, list) or any(not isinstance(f, str) or not f for f in fields):
        return {}
    if not isinstance(status, str) or not status:
        return {}
    projected: dict[str, Any] = {
        "v": payload.get("v") or 1,
        "type": "vault_request",
        "request_id": request_id,
        "service": service,
        "domain": payload.get("domain") if isinstance(payload.get("domain"), str) else "",
        "reason": payload.get("reason") if isinstance(payload.get("reason"), str) else "",
        "fields": _canonical_vault_field_order(fields),
        "status": status,
    }
    expires_at = payload.get("expires_at")
    if isinstance(expires_at, (int, float)):
        projected["expires_at"] = int(expires_at)
    at = payload.get("at")
    if isinstance(at, (int, float)):
        projected["at"] = at
    return projected
