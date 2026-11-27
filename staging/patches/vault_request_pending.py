"""In-process pending store + attach helper for vault request blocks.

Structured delivery for credential request cards (2.17.2), built
isomorphic to the option-card path (``options_pending``, 1.12.0): the
``request_credential`` tool handler does not write the card itself --
it parks the new request's id here, and the gateway runs patch
(``api_server_runs.py``) attaches the canonical block to the turn's
final assistant message when the run reaches its terminal state,
where it lands in ``messages.display_metadata["vault_request"]`` and
the API surfaces it as the message's top-level ``vault_request``
object (``type="vault_request"``). The App renders the card from that
block; the ``[[vreq:...]]`` body marker remains only as the archive
fallback for pre-2.17.2 history.

Differences from the option-card store, all deliberate:

* The pending entry carries only the request id (+ session/run
  binding). The block itself is NEVER stored here: the terminal
  attach rebuilds it from the vault's live record
  (``credential_vault.request_block``) and drops the card when the
  request is no longer pending, so a stamped block can never drift
  from the vault's state.
* The request itself is durable (credential_vault persists it), but
  this parking lot is process-local by design: a gateway restart
  drops parked entries, which is correct -- a restart also
  interrupts every in-flight run, so there is nothing left to
  attach to. The durable request stays listable via
  ``GET /v1/vault/requests`` regardless.
"""

import threading
import time
import uuid
from typing import Any, Optional

_lock = threading.Lock()
_pending: dict[tuple[str, str, str], dict[str, Any]] = {}

_BLOCK_FIELDS = ("request_id", "service", "domain", "reason", "fields", "status")


def _canonical_field_order(fields: Any) -> list[str]:
    """Canonical request-card field order (account, password, rest).

    The single source lives in ``credential_vault.canonical_field_order``;
    the local mirror only covers non-gateway import layouts (the package
    selftest imports this module as ``patches.vault_request_pending``).
    """
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

        unique = [f for f in dict.fromkeys(fields)
                  if isinstance(f, str) and f]
        return sorted(unique, key=rank)


def validate_block(raw: Any) -> Optional[dict[str, Any]]:
    """Normalize a structured vault-request block, or None if invalid.

    Accepts the canonical block shape produced by
    ``credential_vault.request_block`` and returns the stored payload
    form (contract fields only, in contract order). This is the single
    shape check shared by the parking side and the terminal attach --
    the store is never trusted, so the attach re-runs it.
    """
    if not isinstance(raw, dict) or raw.get("type") != "vault_request":
        return None
    request_id = raw.get("request_id")
    if not isinstance(request_id, str) or not request_id.startswith("vreq_"):
        return None
    service = raw.get("service")
    domain = raw.get("domain")
    reason = raw.get("reason")
    status = raw.get("status")
    if not isinstance(service, str) or not service:
        return None
    if not isinstance(domain, str) or not isinstance(reason, str):
        return None
    if not isinstance(status, str) or not status:
        return None
    fields = raw.get("fields")
    if not isinstance(fields, list) or not fields \
            or any(not isinstance(f, str) or not f for f in fields):
        return None
    block: dict[str, Any] = {
        "type": "vault_request",
        "request_id": request_id,
        "service": service[:120],
        "domain": domain[:253],
        "reason": reason[:240],
        "fields": _canonical_field_order(fields),
        "status": status[:32],
    }
    expires_at = raw.get("expires_at")
    if isinstance(expires_at, (int, float)):
        block["expires_at"] = int(expires_at)
    return block


def put(session_id: str, run_key: str, request_id: str, scope: str = "default") -> bool:
    """Park one created request for this turn's terminal attach.

    Keyed by (session, run, request id): the request id is inherently
    unique, so repeated parking of the same request is idempotent.
    """
    if not session_id or not request_id:
        return False
    with _lock:
        key = (session_id, run_key or "", request_id)
        _pending[key] = {
            "card_id": uuid.uuid4().hex,
            "request_id": request_id,
            "session_id": session_id,
            "scope": scope or "default",
            "run_key": run_key or "",
            "at": time.time(),
        }
    return True


def list_pending(session_id: str) -> list[dict[str, Any]]:
    """Return a snapshot of all unresolved entries for one session."""
    if not session_id:
        return []
    with _lock:
        return [dict(entry) for (sid, _, _), entry in _pending.items()
                if sid == session_id]


def discard(session_id: str) -> None:
    """Drop all pending entries for *session_id* without attaching them."""
    if not session_id:
        return
    with _lock:
        for key in [key for key in _pending if key[0] == session_id]:
            _pending.pop(key, None)


def drop(session_id: str, card_id: str) -> Optional[dict[str, Any]]:
    """Remove one identified entry after a definitive attach rejection."""
    if not session_id or not card_id:
        return None
    with _lock:
        key = next((key for key in _pending
                    if key[0] == session_id
                    and _pending[key].get("card_id") == card_id), None)
        return _pending.pop(key, None) if key is not None else None


def settle(session_id: str, card_id: str, settle_fn: Any) -> tuple[Optional[dict[str, Any]], Any]:
    """Run the durable decision while holding the pending-list lock.

    The entry remains visible if ``settle_fn`` raises, returns False, or
    reports ``no_row``. Attached or definitively rejected cards are
    removed before readers can observe the updated list.
    """
    if not session_id or not card_id:
        return None, False
    with _lock:
        key = next((key for key in _pending
                    if key[0] == session_id
                    and _pending[key].get("card_id") == card_id), None)
        if key is None:
            return None, False
        entry = _pending[key]
        result = settle_fn(dict(entry))
        if result in ("attached", "rejected") or result is True:
            _pending.pop(key, None)
        return dict(entry), result


def attach_vault_request(db: Any, session_id: str, row_id: int,
                         block: dict[str, Any]) -> bool:
    """Stamp the vault-request block onto one message row's display_metadata.

    Single-transaction read-modify-write using the same primitives as
    ``options_pending.attach_options``: only the ``vault_request`` key
    is set; every other metadata key (reactions, options, delivery
    markers) is preserved verbatim. Returns False when the row is
    outside the session's visible resume lineage.
    """
    if db is None or not session_id or row_id is None or not block:
        return False
    from hermes_state_common import _placeholders
    from hermes_state_messages import _DISPLAY_META_ROW_SQL, _SET_DISPLAY_META_SQL

    lineage = db._resume_lineage_ids(session_id)
    sql, params = (
        _DISPLAY_META_ROW_SQL.format(ids=_placeholders(lineage)),
        (int(row_id), *lineage),
    )
    payload = {"v": 1, **block, "at": time.time()}

    def _do(conn):
        row = conn.execute(sql, params).fetchone()
        if row is None:
            return False
        meta = db._decode_display_metadata(row[0]) or {}
        meta["vault_request"] = payload
        conn.execute(
            _SET_DISPLAY_META_SQL,
            (db._encode_display_metadata(meta) if meta else None, int(row_id)),
        )
        return True

    return bool(db._execute_write(_do))
