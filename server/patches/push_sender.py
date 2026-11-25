"""APNs push sender module (batch 4b sender half).

Reads APNs provider credentials from environment variables:
- ``APNS_KEY_PATH``: path to Apple ``.p8`` ES256 private key file
- ``APNS_KEY_ID``: 10-char Apple Key ID
- ``APNS_TEAM_ID``: 10-char Apple Team ID
- ``APNS_TOPIC``: iOS Bundle ID (e.g. ``com.oneday.app``)

Payload shape matches ``Sources/OneDayCore/PushRegistration.swift``
(``PushNotificationRouteResolver``):
- approval: ``{"aps": {...}, "kind": "approval", "request_id": "..."}``
- run:      ``{"aps": {...}, "kind": "run", "session_id": "..."}``

When credentials are not configured (before paid Apple Developer account
is provisioned), ``send_notification`` fails gracefully with
``skipped_reason="apns_not_configured"`` without crashing callers.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

logger = logging.getLogger("gateway.platforms.push_sender")

APNS_HOSTS = {
    "sandbox": "https://api.sandbox.push.apple.com",
    "production": "https://api.push.apple.com",
}


def apns_config() -> dict[str, str]:
    return {
        "key_path": os.environ.get("APNS_KEY_PATH", "").strip(),
        "key_id": os.environ.get("APNS_KEY_ID", "").strip(),
        "team_id": os.environ.get("APNS_TEAM_ID", "").strip(),
        "topic": os.environ.get("APNS_TOPIC", "").strip(),
    }


def is_configured() -> bool:
    cfg = apns_config()
    return bool(
        cfg["key_path"]
        and Path(cfg["key_path"]).is_file()
        and cfg["key_id"]
        and cfg["team_id"]
        and cfg["topic"]
    )


def build_payload(
    *,
    title: str,
    body: str,
    kind: str,
    request_id: str | None = None,
    session_id: str | None = None,
    badge: int | None = None,
) -> dict[str, Any]:
    """Build APNs JSON payload matching OneDay PushNotificationRouteResolver."""
    aps: dict[str, Any] = {
        "alert": {"title": title, "body": body},
        "sound": "default",
    }
    if badge is not None:
        aps["badge"] = int(badge)
    payload: dict[str, Any] = {"aps": aps, "kind": kind}
    if kind == "approval" and request_id:
        payload["request_id"] = request_id
    elif kind == "run" and session_id:
        payload["session_id"] = session_id
    return payload


def send_notification(
    *,
    title: str,
    body: str,
    kind: str,
    request_id: str | None = None,
    session_id: str | None = None,
    tokens: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Dispatch notification to registered tokens (graceful no-op if unconfigured)."""
    payload = build_payload(
        title=title, body=body, kind=kind,
        request_id=request_id, session_id=session_id,
    )
    if not is_configured():
        return {
            "sent": 0,
            "failed": 0,
            "pruned": 0,
            "skipped_reason": "apns_not_configured",
            "payload": payload,
        }
    if tokens is None:
        try:
            from gateway.platforms import push_tokens as _pt
            tokens = _pt.list_tokens(include_raw=True)
        except Exception:
            tokens = []
    if not tokens:
        return {
            "sent": 0,
            "failed": 0,
            "pruned": 0,
            "skipped_reason": "no_registered_tokens",
            "payload": payload,
        }
    # Actual HTTP/2 + ES256 JWT delivery requires PyJWT + httpx[http2] on the
    # production host once the Apple .p8 key is provisioned.
    try:
        import time
        import jwt  # type: ignore
        import httpx  # type: ignore
    except ImportError as exc:
        return {
            "sent": 0,
            "failed": 0,
            "pruned": 0,
            "skipped_reason": f"missing_dependency:{exc.name}",
            "payload": payload,
        }

    cfg = apns_config()
    private_key = Path(cfg["key_path"]).read_text(encoding="utf-8")
    bearer = jwt.encode(
        {"iss": cfg["team_id"], "iat": int(time.time())},
        private_key,
        algorithm="ES256",
        headers={"kid": cfg["key_id"]},
    )
    raw_body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    sent = failed = pruned = 0
    with httpx.Client(http2=True, timeout=10.0) as client:
        for row in tokens:
            tok = str(row.get("device_token") or "").strip()
            env = str(row.get("environment") or "production")
            host = APNS_HOSTS.get(env, APNS_HOSTS["production"])
            if not tok:
                continue
            try:
                resp = client.post(
                    f"{host}/3/device/{tok}",
                    headers={
                        "authorization": f"bearer {bearer}",
                        "apns-topic": str(row.get("bundle_id") or cfg["topic"]),
                        "apns-push-type": "alert",
                        "apns-priority": "10",
                    },
                    content=raw_body,
                )
                if resp.status_code == 200:
                    sent += 1
                elif resp.status_code in (400, 410):
                    failed += 1
                    if resp.status_code == 410 or "BadDeviceToken" in resp.text:
                        try:
                            from gateway.platforms import push_tokens as _pt
                            _pt.delete_token(tok)
                            pruned += 1
                        except Exception:
                            pass
                else:
                    failed += 1
            except Exception:
                logger.exception("push_sender: delivery error for %s", tok[:8])
                failed += 1
    return {"sent": sent, "failed": failed, "pruned": pruned, "payload": payload}
