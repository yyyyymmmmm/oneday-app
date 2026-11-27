"""Present a tappable option card under the reply (hermes-deploy 1.12.0).

Package-owned tool (no upstream counterpart). The model calls
``present_options`` in the same turn as the reply whose text asks the
question; the handler only validates and parks the declared choices in
``gateway.platforms.options_pending`` -- the runs patch attaches them
to the turn's final assistant message at terminal state, where they
land in ``messages.display_metadata["options"]`` and the OneDay App
renders them as a single-column quick-pick card (tap = the option's
send_text is sent as the user's next message).

Nothing is written to the store here, so a failed / interrupted turn
can never leave a card behind. Registration is a single entry in the
registry-only ``options_card`` toolset; the api_server surface receives
it when the instance config lists ``options_card`` in
``platform_toolsets.api_server`` (registry passthrough, the same route
``self_reactions`` takes). The deployment gate is
``display.options_card`` (default off = latent): with the gate closed
the tool never enters the phone surface's schema.
"""

import json

from gateway.session_context import get_session_env
from tools import desktop_ui
from tools.registry import registry, tool_error

PRESENT_OPTIONS_SCHEMA = {
    "name": "present_options",
    "description": (
        "Offer the user a small set of tappable options under this reply. Your reply "
        "text itself is the question -- this tool only carries the choices. The "
        "options appear as buttons under your message; tapping one sends that "
        "option's send_text as the user's next message, so each send_text must read "
        "like something the user would say. Use this ONLY when the user genuinely "
        "needs to pick between a few concrete alternatives (a plan, a next step, a "
        "yes/no with flavors) -- never for open-ended questions, and never narrate "
        "the tool or repeat the options in your reply text (the card renders them; "
        "repeating them doubles the presentation). At most one call per reply: "
        "calling again replaces the previous set. Keep labels short and human; put "
        "the full instruction in send_text when the label is a shorthand."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "options": {
                "type": "array",
                "minItems": 2,
                "maxItems": 6,
                "items": {
                    "type": "object",
                    "properties": {
                        "label": {
                            "type": "string",
                            "description": "The button text: short, plain, human (max 60 chars).",
                        },
                        "send_text": {
                            "type": "string",
                            "description": (
                                "What gets sent as the user's message when this option is "
                                "tapped (max 500 chars). Omit to send the label itself."
                            ),
                        },
                    },
                    "required": ["label"],
                },
                "description": "2-6 options, each with a label and an optional send_text.",
            },
        },
        "required": ["options"],
    },
}


def check_options_card_requirements() -> bool:
    """Deployment gate for the api_server option card (``display.options_card``).

    Default False: shipping the patch changes nothing until the deployment
    explicitly opens the gate (latent rollout, hermes-deploy 1.12.0)."""
    return desktop_ui.user_enabled("options_card", default=False)


def _present_options(args) -> str:
    """api_server surface: validate and park this turn's option card.

    The card is NOT written anywhere durable here -- the final assistant
    row does not exist yet. The runs patch attaches the parked options
    when (and only when) the run completes.
    """
    platform = get_session_env("HERMES_SESSION_PLATFORM", "")
    if platform != "api_server":
        return tool_error("Option cards are only available on the app surface.")
    if not check_options_card_requirements():
        return tool_error("Option cards are disabled on this deployment.")
    try:
        from gateway.platforms import options_pending as pending
    except Exception:
        return tool_error("Option cards are unavailable on this deployment.")
    options = pending.validate_options((args or {}).get("options"))
    if options is None:
        return tool_error(
            "Invalid options: pass 2-6 options, each with a non-empty label "
            "(max 60 chars) and an optional send_text (max 500 chars); "
            "duplicate send_text values are dropped and can invalidate the set.")
    session_id = get_session_env("HERMES_SESSION_ID", "")
    if not session_id:
        return tool_error("No active session -- option cards need a persisted conversation.")
    run_key = get_session_env("HERMES_SESSION_KEY", "")
    if not pending.put(session_id, run_key, options):
        return tool_error("Option cards are unavailable on this deployment.")
    return json.dumps({"success": True, "noted": True}, ensure_ascii=False)


registry.register(
    name="present_options", toolset="options_card", schema=PRESENT_OPTIONS_SCHEMA,
    handler=lambda args, **kw: _present_options(args),
    check_fn=check_options_card_requirements, emoji="\U0001F518",
)
