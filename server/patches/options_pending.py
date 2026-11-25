"""In-process pending store + attach helper for agent option cards (hermes-deploy 1.12.0).

The api_server-surface ``present_options`` tool handler does not write
the options itself: it registers the model's declared choices here, and
the gateway runs patch (``api_server_runs.py``) attaches them to the
turn's final assistant message when the run reaches its terminal state.
Decoupling registration from attachment is what guarantees the failure
discipline (mirrors ``self_reaction_pending``, hermes-deploy 1.8.0):

* a run that ends failed / cancelled / interrupted never attaches
  (the terminal hook only fires the attach on ``completed``);
* a gateway restart drops every pending entry -- which is correct,
  because a restart also interrupts every in-flight run, so there is
  nothing left to attach to.

Storage is deliberately process-local (a dict + lock): no disk, no
residue, nothing to clean up on rollback. ``validate_options`` is the
single source of truth for the payload shape, shared by the tool
handler (write-side check) and the terminal attach (attach-side
re-check -- the store is never trusted).

Unlike self-reactions there is NO tool-use filter: asking the user to
pick a direction after doing work is this feature's primary use case.
"""

import threading
import time
import uuid
from typing import Any, Optional

# Payload shape limits (options-card spec §1.2, DESIGN §441). The card
# is a quick-pick surface: 2-6 short choices; send_text may carry the
# full instruction behind a short label.
MIN_OPTIONS = 2
MAX_OPTIONS = 6
MAX_LABEL_CHARS = 60
MAX_SEND_TEXT_CHARS = 500

_lock = threading.Lock()
_pending: dict[tuple[str, str, str], dict[str, Any]] = {}


def _clean_text(value: Any, limit: int) -> str:
    """Trim, strip control characters, and hard-cap one text field."""
    if not isinstance(value, str):
        return ""
    text = "".join(ch for ch in value if ch >= " " or ch in "\t").strip()
    return text[:limit]


def validate_options(raw: Any) -> Optional[list[dict[str, str]]]:
    """Normalize a declared options payload, or return None if invalid.

    Accepts the tool's raw argument (a list of ``{"label", "send_text"}``
    dicts) and returns the canonical stored form: label/send_text pairs,
    send_text defaulted to the label, duplicates by send_text dropped.
    Fewer than MIN_OPTIONS surviving entries is invalid -- a one-item
    "choice" is not a choice.
    """
    if not isinstance(raw, list):
        return None
    cleaned: list[dict[str, str]] = []
    seen_send: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            return None
        label = _clean_text(item.get("label"), MAX_LABEL_CHARS)
        if not label:
            return None
        send_text = _clean_text(item.get("send_text"), MAX_SEND_TEXT_CHARS) or label
        if send_text in seen_send:
            continue
        seen_send.add(send_text)
        cleaned.append({"label": label, "send_text": send_text})
        if len(cleaned) > MAX_OPTIONS:
            return None
    if len(cleaned) < MIN_OPTIONS:
        return None
    return cleaned


def put(session_id: str, run_key: str, options: list[dict[str, str]]) -> bool:
    """Register one pending option card, keyed by session and run.

    *options* must already be normalized by :func:`validate_options`.
    Each registration gets its own card id, so cards in one session (and
    even repeated calls carrying the same session-scoped run key) coexist.
    """
    if not session_id or not options:
        return False
    with _lock:
        card_id = uuid.uuid4().hex
        key = (session_id, run_key or "", card_id)
        _pending[key] = {
            "card_id": card_id,
            "session_id": session_id,
            "options": options,
            "run_key": run_key or "",
            "at": time.time(),
        }
    return True


def pop(session_id: str, run_key: str = "") -> Optional[dict[str, Any]]:
    """Remove one pending entry, optionally matching its exact run key.

    The no-run form is retained for compatibility and only consumes an
    unambiguous session entry. A supplied run_key must match exactly.
    """
    if not session_id:
        return None
    with _lock:
        if run_key:
            matches = [key for key in _pending
                       if key[0] == session_id and key[1] == run_key]
            if len(matches) != 1:
                return None
            return _pending.pop(matches[0], None)
        matches = [key for key in _pending if key[0] == session_id]
        if len(matches) != 1:
            return None
        return _pending.pop(matches[0], None)


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
    """Remove one identified card after a definitive attach rejection."""
    if not session_id or not card_id:
        return None
    with _lock:
        key = next((key for key in _pending
                    if key[0] == session_id and key[2] == card_id), None)
        return _pending.pop(key, None) if key is not None else None


def settle(session_id: str, card_id: str, settle_fn: Any) -> tuple[Optional[dict[str, Any]], Any]:
    """Run the durable decision while holding the pending-list lock.

    The entry remains visible if ``settle_fn`` raises, returns False, or
    reports ``no_row``. Attached or definitively rejected cards are removed
    before readers can observe the updated list.
    """
    if not session_id or not card_id:
        return None, False
    with _lock:
        key = next((key for key in _pending
                    if key[0] == session_id and key[2] == card_id), None)
        if key is None:
            return None, False
        entry = _pending[key]
        result = settle_fn(dict(entry))
        if result in ("attached", "rejected") or result is True:
            _pending.pop(key, None)
        return dict(entry), result


def attach_options(db: Any, session_id: str, row_id: int,
                   options: list[dict[str, str]]) -> bool:
    """Stamp the options payload onto one message row's display_metadata.

    Single-transaction read-modify-write using the same primitives as
    ``SessionDB.set_message_reaction`` (upstream has no generic
    display_metadata setter, and the one display-kind stamper replaces
    the whole dict, which would clobber reactions/delivery markers on
    the row): only the ``options`` key is set; every other metadata key
    is preserved verbatim. Returns False when the row is outside the
    session's visible resume lineage.
    """
    if db is None or not session_id or row_id is None or not options:
        return False
    from hermes_state_common import _placeholders
    from hermes_state_messages import _DISPLAY_META_ROW_SQL, _SET_DISPLAY_META_SQL

    lineage = db._resume_lineage_ids(session_id)
    sql, params = (
        _DISPLAY_META_ROW_SQL.format(ids=_placeholders(lineage)),
        (int(row_id), *lineage),
    )
    payload = {"v": 1, "options": options, "at": time.time()}

    def _do(conn):
        row = conn.execute(sql, params).fetchone()
        if row is None:
            return False
        meta = db._decode_display_metadata(row[0]) or {}
        meta["options"] = payload
        conn.execute(
            _SET_DISPLAY_META_SQL,
            (db._encode_display_metadata(meta) if meta else None, int(row_id)),
        )
        return True

    return bool(db._execute_write(_do))
