"""Write records for agent self-reactions (hermes-deploy 1.8.0; rev4 in 1.16.0).

Since hermes-deploy 1.16.0 rev4 the api_server-surface
``react_to_message`` handler writes the reaction to the target
message row itself, at the moment the tool executes (see
react_to_message_tool.py). This store no longer parks picks for a
terminal attach -- that chain is retired: it lost the badge whenever
its back half broke (a guard discarding the entry in 1.15.0, or a
run that never reached a terminal state at all, e.g. a gateway
restart mid-turn on 2026-11-24). What remains here is the turn's
*write record*: the runs patch's terminal audit pops it to retract
the one case write time cannot judge (a non-receipt reaction
written before the turn turned into work). A record whose run died
before finishing is discarded by the next audit WITHOUT retracting
-- the badge it wrote stands, which is the point of writing at
call time.

Storage is deliberately process-local (a dict + lock): no disk, no
residue, nothing to clean up on rollback. The palette below is a
*recommended* set -- guidance for the model's usual picks, shared
with the tool description -- and since hermes-deploy 1.16.0 it is
not a gate: any single emoji the model picks is written (user
ruling 2026-11-24: the Muse reaction standard takes priority;
the 1.8.0-1.15.0 write-side and attach-side palette checks are
retired).
"""

import threading
import time
from typing import Any, Optional

# Recommended palette (demand-ledger 202, user-approved 2026-11-24).
# One entry per role the reference products cover: 👍 ack/done, ❤️ warmth,
# 🤔 thinking, 😂 humour, 🎉 success, 👀 watching/seen. Guidance only
# since 1.16.0 -- NOT a gate (see module docstring).
EMOJI_PALETTE: tuple[str, ...] = (
    "\U0001F44D",      # 👍
    "❤️",  # ❤️
    "\U0001F914",      # 🤔
    "\U0001F602",      # 😂
    "\U0001F389",      # 🎉
    "\U0001F440",      # 👀
)

_lock = threading.Lock()
_pending: dict[str, dict[str, Any]] = {}


def put(session_id: str, run_key: str, emoji: str,
        target_row_id: Optional[int]) -> bool:
    """Record (or replace) this turn's written self-reaction for *session_id*.

    The reaction itself has already been written by the handler;
    this record exists for the runs patch's terminal audit. Any
    single emoji is accepted (1.16.0: the palette is a recommended
    set, not a gate). Returns False without storing only when the
    session id or the emoji is empty. Repeated calls in one turn
    overwrite: at most one record per turn survives by construction.
    """
    if not session_id or not emoji:
        return False
    with _lock:
        _pending[session_id] = {
            "emoji": emoji,
            "run_key": run_key or "",
            "target_row_id": target_row_id,
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
