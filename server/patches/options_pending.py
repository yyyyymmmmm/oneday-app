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
from typing import Any, Optional

# Payload shape limits (options-card spec §1.2, DESIGN §441). The card
# is a quick-pick surface: 2-6 short choices; send_text may carry the
# full instruction behind a short label.
MIN_OPTIONS = 2
MAX_OPTIONS = 6
MAX_LABEL_CHARS = 60
MAX_SEND_TEXT_CHARS = 500

_lock = threading.Lock()
_pending: dict[str, dict[str, Any]] = {}


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
    """Register (or replace) the pending option card for *session_id*.

    *options* must already be normalized by :func:`validate_options`.
    Repeated calls in one turn overwrite: at most one card per turn
    survives by construction.
    """
    if not session_id or not options:
        return False
    with _lock:
        _pending[session_id] = {
            "options": options,
            "run_key": run_key or "",
            "at": time.time(),
        }
    return True


def pop(session_id: str) -> Optional[dict[str, Any]]:
    """Remove and return the pending entry for *session_id*, if any."""
    if not session_id:
        return None
    with _lock:
        return _pending.pop(session_id, None)


def discard(session_id: str) -> None:
    """Drop any pending entry for *session_id* without attaching it."""
    if not session_id:
        return
    with _lock:
        _pending.pop(session_id, None)


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
