"""AI settings administration tools (hermes-deploy 2.5.0, DESIGN
section 435 phase 2).

Package-owned tools (no upstream counterpart). Seven narrow tools
in the registry-only ``settings_admin`` toolset let the agent work
the settings registry it shares with the user: list / get / set /
register / delete entries, and register / remove hub surface
records. Every mutation runs through gateway.platforms.settings_admin
-- the same write path, scope whitelist, validation and audit log
the user's own app face uses (POST /v1/settings/entries); this file
only adapts tool calls to it with actor="agent".

Deployment gates, both required before a tool can fire:

- the instance config lists ``settings_admin`` in
  ``platform_toolsets.api_server`` (registry passthrough, the same
  route ``self_reactions`` / ``options_card`` take), and
- the master gate ``settings.agent_admin`` is true in the instance
  config (default off; flipped once with the approved phase-2
  application, spec section 5). With the gate closed the tools do
  not enter the phone surface's schema at all.
"""

import json

from gateway.session_context import get_session_env
from tools.registry import registry, tool_error

_READ_SCHEMA_PROPS = {
    "surface": {"type": "string",
                "description": "Only return records on this surface "
                               "(e.g. agent, chat, hub, machine)."},
    "owner": {"type": "string", "enum": ["user", "agent", "shared"],
              "description": "Only return records with this owner."},
}

SETTINGS_LIST_SCHEMA = {
    "name": "settings_list",
    "description": (
        "List the settings registry: every setting entry with its "
        "type, current value, default, owner and writability. Use "
        "this to discover what exists before changing anything. "
        "You and the user share this one registry -- there is no "
        "separate agent configuration."),
    "parameters": {"type": "object", "properties": _READ_SCHEMA_PROPS},
}

SETTINGS_GET_SCHEMA = {
    "name": "settings_get",
    "description": (
        "Read one settings record by key, with its current value, "
        "default and writability."),
    "parameters": {
        "type": "object",
        "properties": {
            "key": {"type": "string",
                    "description": "The record's registry key."}},
        "required": ["key"]},
}

SETTINGS_SET_SCHEMA = {
    "name": "settings_set",
    "description": (
        "Change a setting's value. Only records whose writability "
        "includes the agent and that are reversible can be changed "
        "this way; credential, payment, sending, audit and "
        "user-data-deletion zones are refused, as are records the "
        "user owns outright. Every accepted change is written to "
        "the audit log and the user can undo it. A refusal comes "
        "back with the reason -- do not retry around it, surface "
        "it to the user instead."),
    "parameters": {
        "type": "object",
        "properties": {
            "key": {"type": "string",
                    "description": "The record's registry key."},
            "value": {"description": "The new value; must match "
                                       "the record's type."}},
        "required": ["key", "value"]},
}

SETTINGS_REGISTER_SCHEMA = {
    "name": "settings_register",
    "description": (
        "Register a NEW settings entry (a new key with its type, "
        "default, surface and owner) -- this is how a new setting "
        "comes into existence without an app release. You may only "
        "register agent- or shared-owned, reversible records. The "
        "record needs: key, type (bool/enum/string/number/text), "
        "default, surface, owner, writable_by, validation (or "
        "null), capability (or null), reversible."),
    "parameters": {
        "type": "object",
        "properties": {
            "record": {"type": "object",
                       "description": "The full registry record."}},
        "required": ["record"]},
}

SETTINGS_DELETE_SCHEMA = {
    "name": "settings_delete",
    "description": (
        "Delete a settings entry you registered (or clear a value "
        "you set on a catalog entry, restoring its default). "
        "Catalog entries themselves and user-owned records cannot "
        "be deleted by you; propose those to the user instead. "
        "Deletions are audited and the user can undo them."),
    "parameters": {
        "type": "object",
        "properties": {
            "key": {"type": "string",
                    "description": "The record's registry key."}},
        "required": ["key"]},
}

SURFACE_REGISTER_SCHEMA = {
    "name": "surface_register",
    "description": (
        "Add a hub surface (segment) for a capability that has "
        "come alive -- e.g. when a new channel is built and its "
        "probe is live. The capability must actually be live: "
        "registration against a dead capability is refused. The "
        "user sees the new segment without an app release and can "
        "undo the addition from the audit view."),
    "parameters": {
        "type": "object",
        "properties": {
            "key": {"type": "string",
                    "description": "Surface record key, "
                                   "hub.surface.<name>."},
            "title": {"type": "string",
                      "description": "Segment title shown in the "
                                     "hub."},
            "capability": {"type": "string",
                           "description": "Capability reference "
                                          "the segment rides on, "
                                          "e.g. features.<name>."},
            "destination": {"type": "string",
                            "description": "Where the segment "
                                           "leads in the app."}},
        "required": ["key", "title", "capability"]},
}

SURFACE_REMOVE_SCHEMA = {
    "name": "surface_remove",
    "description": (
        "Remove a hub surface record you registered. Built-in "
        "catalog surfaces cannot be removed by you."),
    "parameters": {
        "type": "object",
        "properties": {
            "key": {"type": "string",
                    "description": "The surface record's key."}},
        "required": ["key"]},
}


def check_settings_admin_requirements() -> bool:
    """Deployment gate for the settings_admin toolset: the
    settings_admin module must be importable and the instance
    master gate ``settings.agent_admin`` must be on (default off
    -- shipping the patch changes nothing until the approved
    application flips it, hermes-deploy 2.5.0)."""
    try:
        from gateway.platforms import settings_admin as _sa
    except Exception:
        return False
    return _sa.agent_admin_enabled()


def _admin():
    from gateway.platforms import settings_admin as _sa
    return _sa


def _guard():
    """Common handler preconditions; returns an error string or
    None."""
    platform = get_session_env("HERMES_SESSION_PLATFORM", "")
    if platform != "api_server":
        return tool_error(
            "Settings administration is only available on the app "
            "surface.")
    if not check_settings_admin_requirements():
        return tool_error(
            "Settings administration is disabled on this deployment "
            "(the settings.agent_admin gate is off).")
    return None


def _run_id() -> str:
    return get_session_env("HERMES_SESSION_KEY", "") or None


def _receipt(status: int, payload: dict) -> str:
    if status != 200:
        return tool_error(
            f"{payload.get('code', 'error')}: "
            f"{payload.get('error', 'settings write failed')}")
    return json.dumps(payload, ensure_ascii=False)


def _settings_list(args) -> str:
    err = _guard()
    if err:
        return err
    data = _admin().list_settings(
        surface=(args or {}).get("surface") or None,
        owner=(args or {}).get("owner") or None)
    return json.dumps(data, ensure_ascii=False)


def _settings_get(args) -> str:
    err = _guard()
    if err:
        return err
    status, payload = _admin().get_setting((args or {}).get("key", ""))
    return _receipt(status, payload)


def _settings_set(args) -> str:
    err = _guard()
    if err:
        return err
    args = args or {}
    status, payload = _admin().set_setting(
        args.get("key", ""), args.get("value"),
        actor="agent", run_id=_run_id())
    return _receipt(status, payload)


def _settings_register(args) -> str:
    err = _guard()
    if err:
        return err
    status, payload = _admin().register_setting(
        (args or {}).get("record"), actor="agent", run_id=_run_id())
    return _receipt(status, payload)


def _settings_delete(args) -> str:
    err = _guard()
    if err:
        return err
    status, payload = _admin().delete_setting(
        (args or {}).get("key", ""), actor="agent", run_id=_run_id())
    return _receipt(status, payload)


def _surface_register(args) -> str:
    err = _guard()
    if err:
        return err
    args = args or {}
    capability = args.get("capability", "")
    if not _admin().capability_live(capability):
        return tool_error(
            f"capability_dead: {capability} is not live on this "
            "deployment; a surface is only registered against a "
            "live capability.")
    record = {
        "key": args.get("key", ""), "type": "surface",
        "default": None, "surface": "hub", "owner": "agent",
        "writable_by": "agent", "validation": None,
        "capability": capability, "reversible": True,
        "title": args.get("title", ""), "source": "server",
    }
    if args.get("destination"):
        record["destination"] = args["destination"]
    status, payload = _admin().register_setting(
        record, actor="agent", run_id=_run_id())
    return _receipt(status, payload)


def _surface_remove(args) -> str:
    err = _guard()
    if err:
        return err
    status, payload = _admin().delete_setting(
        (args or {}).get("key", ""), actor="agent", run_id=_run_id())
    return _receipt(status, payload)


for _name, _schema, _handler in (
        ("settings_list", SETTINGS_LIST_SCHEMA, _settings_list),
        ("settings_get", SETTINGS_GET_SCHEMA, _settings_get),
        ("settings_set", SETTINGS_SET_SCHEMA, _settings_set),
        ("settings_register", SETTINGS_REGISTER_SCHEMA,
         _settings_register),
        ("settings_delete", SETTINGS_DELETE_SCHEMA, _settings_delete),
        ("surface_register", SURFACE_REGISTER_SCHEMA,
         _surface_register),
        ("surface_remove", SURFACE_REMOVE_SCHEMA, _surface_remove)):
    registry.register(
        name=_name, toolset="settings_admin", schema=_schema,
        handler=lambda args, _h=_handler, **kw: _h(args),
        check_fn=check_settings_admin_requirements,
        emoji="\U0001F9ED")
