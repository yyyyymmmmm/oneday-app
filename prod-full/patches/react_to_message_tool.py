#!/usr/bin/env python3
"""Agent emoji reaction in the Hermes desktop app: the counterpart to the user's tapback
(same store, one-per-author, ``author="agent"``). Lives in the ``desktop_ui`` toolset so it
costs nothing elsewhere (adapters expose reactions via ``send_message(action="react")``);
defaults to the triggering message and emits ``message.reaction`` for live painting.

Local patch (hermes-deploy 1.8.0, demand-ledger 202): the same tool also serves the
api_server (phone) surface as an agent *self-reaction* -- the agent reacts to the user's
latest message with a single emoji, the reaction landing on that user message once the
turn settles. The registry rejects a second registration of the same tool name under a
different toolset (cross-toolset shadowing), so there is still exactly ONE registration;
it now lives in the ``self_reactions`` toolset and the handler dispatches per surface.
Desktop sessions keep receiving the tool because ``TOOLSETS["desktop_ui"]`` names it
statically and definitions resolve by name; the desktop handler, schema and check below
are the upstream ones, unchanged. On the api_server surface the handler writes the
reaction to the target row itself, the moment the tool executes (hermes-deploy
1.16.0 rev4; the 1.8.0-1.16.0 register-then-attach-at-terminal chain is retired),
and records the write in ``gateway.platforms.self_reaction_pending`` for the runs
patch's terminal audit."""

import contextlib
import json
import logging
import os

from gateway.session_context import get_session_env
from tools import desktop_ui
from tools.registry import registry, tool_error

logger = logging.getLogger(__name__)


def _open_session_db():
    """Open the SessionDB for the profile owning this turn, or ``None``."""
    try:
        from hermes_state_registry import acquire
        return acquire()
    except Exception:
        return None


def react_to_message_tool(emoji: str, message_row_id=None, messages_back=None) -> str:
    """Attach (or with an empty ``emoji`` retract) the agent's reaction."""
    emoji = (emoji or "").strip()
    # Routing keys identify a channel; message rows belong to the live durable session.
    session_key = get_session_env("HERMES_SESSION_ID", "") or get_session_env("HERMES_SESSION_KEY", "")
    if not session_key:
        return tool_error("No active session — reactions need a persisted conversation.")
    db = _open_session_db()
    if db is None:
        return tool_error("Session storage is unavailable.")
    try:
        row_id, target_role = message_row_id, "user"
        if row_id is None:
            # Default: the latest user message; `messages_back` steps to earlier user turns
            # (ids aren't visible to the model; "two messages ago" is how a person thinks).
            back = max(0, int(messages_back or 0))
            row_id = db.latest_message_row_id(session_key, role="user", offset=back)
            if row_id is None:
                return tool_error(f"No user message found {back} back." if back else "No user message to react to yet.")
        else:
            target_role = db.get_message_role(session_key, int(row_id)) or "user"
        try:
            reactions = db.set_message_reaction(session_key, int(row_id), emoji or None, author="agent")
        except Exception as exc:
            return tool_error(f"Failed to set the reaction: {exc}")
        if reactions is None:
            return tool_error(f"Message {row_id} is not part of this conversation.")
        # Paint it live; a missing bridge (non-desktop) is not an error — the reaction is
        # persisted. `role` lets the renderer match a live message without a durable row id.
        with contextlib.suppress(Exception):
            desktop_ui.emit("message.reaction", {"row_id": int(row_id), "reactions": reactions, "role": target_role})
        return json.dumps({"success": True, "row_id": int(row_id), "reactions": reactions}, ensure_ascii=False)
    finally:
        with contextlib.suppress(Exception):
            from hermes_state_registry import release_or_close
            release_or_close(db)


def check_react_requirements() -> bool:
    """Opt-in flag (Settings → Appearance); ``desktop_ui`` already restricts to GUI sessions."""
    return desktop_ui.user_enabled("message_reactions", default=False)


REACT_TO_MESSAGE_SCHEMA = {
    "name": "react_to_message",
    "description": (
        "React to a message with a single emoji, the way you'd tapback in iMessage. "
        "Reach for it when a reaction is what a person would do: something funny gets "
        "a 😂, warmth gets a ❤️, a plan you're on board with gets a 👍 — then just "
        "carry on with whatever the message actually needs. If a reaction says it "
        "all, it can BE the reply (skip the redundant 'sounds good!' turn). Use it "
        "like a person would: occasionally, when felt — not on every message, and "
        "never as a status signal. NEVER narrate or explain a reaction ('I reacted "
        "with...', 'Reacting now') — the emoji appearing on the bubble is the whole "
        "point, and commentary kills it. Never type the reaction emoji in your reply text instead of calling this — a typed emoji is not a reaction. Defaults to the user's most recent message. "
        "One reaction per message: a different emoji replaces yours, an empty string "
        "retracts it."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "emoji": {
                "type": "string",
                "description": (
                    "The emoji to react with (e.g. '❤️', '😂', '👍'). Pass an empty "
                    "string to remove your reaction."
                ),
            },
            "message_row_id": {
                "type": "integer",
                "description": (
                    "Optional. The specific message to react to. Omit to react to the "
                    "user's latest message, which is almost always what you want."
                ),
            },
            "messages_back": {
                "type": "integer",
                "description": (
                    "Optional. React to an EARLIER user message: 1 = the one before "
                    "the latest, 2 = two before, and so on. For when something lands "
                    "late — the joke you only got after answering."
                ),
            },
        },
        "required": ["emoji"],
    },
}


def check_self_react_requirements() -> bool:
    """Deployment gate for the api_server self-reaction (``display.agent_self_reactions``).

    Default False: shipping the patch changes nothing until the deployment
    explicitly opens the gate (latent rollout, hermes-deploy 1.8.0)."""
    return desktop_ui.user_enabled("agent_self_reactions", default=False)


def check_react_availability() -> bool:
    """Single registration, two surfaces: available when either surface's gate is open.

    The handler re-checks the gate for the surface it is actually serving,
    so an open gate on one surface never leaks behaviour into the other."""
    return check_react_requirements() or check_self_react_requirements()


def _self_react_to_message(emoji: str) -> str:
    """api_server surface: write this turn's self-reaction immediately.

    Local patch (hermes-deploy 1.16.0 rev4): the reaction is written to
    the target row the moment this tool executes; it no longer waits
    for the run's terminal state. The 1.8.0-1.16.0 chain (register in
    ``self_reaction_pending``, attach from the runs patch when the run
    completes) lost the badge whenever its back half broke: a guard
    discarded the entry (the 1.15.0 run_key failure), or the run never
    reached a terminal state at all (a gateway restart mid-turn,
    2026-11-24: the tool had executed, the pick was registered, the
    badge never landed). Writing at call time makes the badge
    independent of everything the run does afterwards.

    Target: exactly one criterion -- the latest user message row of
    this session, resolved now, inside the turn that row triggered
    (per-session turn leases serialize runs, so the latest user row
    IS this turn's). No run-key equality or cross-run checks; the
    1.15.0 investigation showed no key visible in this context
    carries the run_id, and inside the turn none is needed.

    Receipt discipline is judged here, at write time, on persisted
    execution order: if a non-reaction tool already left a result row
    in this turn (a ``tool`` row after the target whose name is not
    this tool's), the work has already started, so this call is
    neither a receipt (receipts go first) nor a chat reaction (the
    turn is a working turn) -- it is dropped with a warning log, the
    same verdict the terminal filter used to reach. Otherwise the
    write lands: a pure-chat turn and a receipt turn look identical
    from here (no other tool has run yet), and both are legitimate.
    A later call in the same turn replaces the earlier pick (the
    store's one-per-author tapback semantics); repeating the same
    emoji is read first and skipped, because the store would toggle
    it off.

    The pick is still recorded in ``self_reaction_pending`` -- now a
    write record rather than a pending attach -- so the runs patch's
    terminal audit can retract the one case write time cannot see:
    a non-receipt reaction written while the turn still looked like
    conversation, after which the turn used other tools anyway.
    """
    emoji = (emoji or "").strip()
    if not emoji:
        return tool_error("Pass a single emoji to react, or skip reacting.")
    try:
        from gateway.platforms import self_reaction_pending as pending
    except Exception:
        return tool_error("Self-reactions are unavailable on this deployment.")
    session_id = get_session_env("HERMES_SESSION_ID", "")
    if not session_id:
        return tool_error("No active session — reactions need a persisted conversation.")
    # The run_key survives only as a diagnostic breadcrumb on the
    # write record; nothing binds on it (no key visible in the tool
    # context carries the run_id -- the 1.15.0 finding).
    run_key = ""
    try:
        from tools.approval_context import get_current_session_key
        run_key = get_current_session_key("") or ""
    except Exception:
        run_key = ""
    if not run_key:
        run_key = get_session_env("HERMES_SESSION_KEY", "")
    db = _open_session_db()
    if db is None:
        return tool_error("Self-reactions are unavailable on this deployment.")
    try:
        target_row_id = db.latest_message_row_id(session_id, role="user", offset=0)
        if target_row_id is None:
            return tool_error("Could not find the message to react to.")
        started = db._read_one(
            "SELECT 1 FROM messages WHERE session_id = ? AND id > ? "
            "AND active = 1 AND role = 'tool' "
            "AND COALESCE(tool_name, '') != 'react_to_message' LIMIT 1",
            (session_id, int(target_row_id)))
        if started is not None:
            logger.warning(
                "[self_reaction] write dropped: work already started "
                "session=%s row=%s emoji=%s", session_id, target_row_id, emoji)
            return json.dumps({"success": True, "noted": True}, ensure_ascii=False)
        existing = db.get_message_reactions(session_id, int(target_row_id))
        if not any(r.get("author") == "agent" and r.get("emoji") == emoji
                   for r in existing):
            written = db.set_message_reaction(
                session_id, int(target_row_id), emoji, author="agent")
            if written is None:
                return tool_error("Could not register the reaction.")
    except Exception:
        logger.warning(
            "[self_reaction] immediate write failed session=%s",
            session_id, exc_info=True)
        return tool_error("Could not register the reaction.")
    finally:
        with contextlib.suppress(Exception):
            from hermes_state_registry import release_or_close
            release_or_close(db)
    pending.put(session_id, run_key, emoji, target_row_id)
    return json.dumps({"success": True, "noted": True}, ensure_ascii=False)


def _react_dispatch(args) -> str:
    """Route one ``react_to_message`` call to the surface that is serving the turn."""
    platform = get_session_env("HERMES_SESSION_PLATFORM", "") or os.environ.get("HERMES_PLATFORM", "")
    if platform == "api_server":
        if not check_self_react_requirements():
            return tool_error("Self-reactions are disabled on this deployment.")
        if args.get("message_row_id") is not None or args.get("messages_back") is not None:
            return tool_error(
                "On this surface the reaction always lands on the user's latest "
                "message in this conversation; row selection is not supported.")
        return _self_react_to_message(args.get("emoji", ""))
    if not check_react_requirements():
        return tool_error("Message reactions are disabled.")
    return react_to_message_tool(
        emoji=args.get("emoji", ""), message_row_id=args.get("message_row_id"),
        messages_back=args.get("messages_back"))


_SELF_REACTION_DESCRIPTION = (
    "React to the user's latest message with a single emoji — your way of showing "
    "you saw what they said: something funny gets a 😂, warmth gets a ❤️, a plan "
    "you're on board with gets a 👍. The usual picks are 👍 ❤️ 🤔 😂 🎉 👀, but any "
    "single emoji that fits better is fine. The reaction lands on THEIR message "
    "the moment you call this. Use it like a person would: occasionally, when felt — "
    "not on every message. Two cases: (1) plain conversation — when the user "
    "is sharing (how they feel, news good or bad, a joke, a plan), a fitting "
    "reaction is the default and skipping needs a reason; bare questions and "
    "plain information still get none; (2) the turn will use tools — do NOT "
    "call this at all: the runtime attaches its own receipt to the user's "
    "message (👀 when the work starts, ✅ when it completes, ❌ if it "
    "fails) and owns the turn's reaction slot; a pick you attach in a "
    "working turn is replaced. NEVER narrate or explain a reaction ('I reacted with...', "
    "'Reacting now') — the emoji appearing is the whole point. NEVER type the receipt or reaction emoji in your reply text instead of calling this — at the head of a sentence or standing on its own, a typed emoji is not a reaction and reads as you applauding yourself; this call is the only way a reaction reaches their message. At most one per "
    "reply: calling again replaces your pick."
)

_SELF_REACTION_PARAMETERS = {
    "type": "object",
    "properties": {
        "emoji": {
            "type": "string",
            "description": "A single emoji. Usual picks: 👍 ❤️ 🤔 😂 🎉 👀.",
        },
    },
    "required": ["emoji"],
}


def _react_schema_override():
    """Narrow the schema on the api_server surface (emoji-only, self-reaction wording).

    Best-effort: definition building may run outside the turn's session
    binding, in which case the static (desktop) schema is served and the
    handler still hard-rejects row-selection arguments on this surface."""
    try:
        platform = get_session_env("HERMES_SESSION_PLATFORM", "") or os.environ.get("HERMES_PLATFORM", "")
    except Exception:
        return None
    if platform != "api_server":
        return None
    return {"description": _SELF_REACTION_DESCRIPTION, "parameters": _SELF_REACTION_PARAMETERS}


registry.register(
    name="react_to_message", toolset="self_reactions", schema=REACT_TO_MESSAGE_SCHEMA,
    handler=lambda args, **kw: _react_dispatch(args),
    check_fn=check_react_availability, emoji="💛",
    dynamic_schema_overrides=_react_schema_override,
)
