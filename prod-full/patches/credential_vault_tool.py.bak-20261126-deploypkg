"""Narrow AI tools for credential request cards and server-side use."""

import json

from gateway.session_context import get_session_env
from tools.registry import registry, tool_error


REQUEST_SCHEMA = {
    "name": "request_credential",
    "description": "Ask the user to provide credentials in a secure app card. Never ask for, accept, or repeat credential values in chat. Returns request metadata only.",
    "parameters": {"type": "object", "properties": {
        "service": {"type": "string"}, "domain": {"type": "string"},
        "reason": {"type": "string"}, "fields": {"type": "array", "items": {"type": "string", "enum": ["username", "password", "token", "api_key", "secret", "otp"]}},
    }, "required": ["service", "domain", "reason", "fields"]},
}
LOOKUP_SCHEMA = {
    "name": "lookup_meta",
    "description": "Find credential metadata only. Secret values are never returned.",
    "parameters": {"type": "object", "properties": {
        "service": {"type": "string"}, "domain": {"type": "string"},
    }},
}
USE_SCHEMA = {
    "name": "vault_use",
    "description": "Ask the server to perform an allowlisted operation using an authorized credential. The credential value is never returned. If no approved operation matches, report that the operation is unavailable.",
    "parameters": {"type": "object", "properties": {
        "entry_id": {"type": "string"}, "domain": {"type": "string"},
        "purpose": {"type": "string"}, "operation": {"type": "string"},
    }, "required": ["entry_id", "domain", "purpose", "operation"]},
}


def _guard():
    if get_session_env("HERMES_SESSION_PLATFORM", "") != "api_server":
        return tool_error("Credential vault tools are only available on the app surface.")
    try:
        from gateway.platforms import credential_vault as _vault
        if _vault.AESGCM is None:
            return tool_error("Credential vault is unavailable.")
    except Exception:
        return tool_error("Credential vault is unavailable.")
    return None


def _scope():
    try:
        from agent.secret_scope import get_secret
        return str(get_secret("HERMES_SESSION_PROFILE", "") or "default")
    except Exception:
        return "default"


def _api_key():
    try:
        from agent.secret_scope import get_secret
        return str(get_secret("API_SERVER_KEY", "") or "")
    except Exception:
        return ""


def _request(args):
    err = _guard()
    if err:
        return err
    try:
        from gateway.platforms import credential_vault as _vault
        result = _vault.create_request(
            (args or {}).get("service", ""), (args or {}).get("domain", ""),
            (args or {}).get("reason", ""), (args or {}).get("fields"),
            get_session_env("HERMES_SESSION_KEY", ""), _scope())
        return json.dumps(result, ensure_ascii=False)
    except Exception:
        return tool_error("Credential request could not be created.")


def _lookup(args):
    err = _guard()
    if err:
        return err
    from gateway.platforms import credential_vault as _vault
    service = (args or {}).get("service")
    domain = str((args or {}).get("domain") or "").strip().lower().rstrip(".")
    rows = _vault.list_entries(_scope())
    rows = [r for r in rows if (not service or r["service"].casefold() == str(service).casefold()) and (not domain or domain in r["domains"])]
    return json.dumps(rows, ensure_ascii=False)


def _use(args):
    err = _guard()
    if err:
        return err
    from gateway.platforms import credential_vault as _vault
    args = args or {}
    result = _vault.vault_use(
        args.get("entry_id", ""), args.get("domain", ""),
        args.get("purpose", ""), args.get("operation", ""),
        api_key=_api_key(), scope=_scope())
    return json.dumps(result, ensure_ascii=False)


for _name, _schema, _handler in (
        ("request_credential", REQUEST_SCHEMA, _request),
        ("lookup_meta", LOOKUP_SCHEMA, _lookup),
        ("vault_use", USE_SCHEMA, _use)):
    registry.register(name=_name, toolset="credential_vault", schema=_schema,
                      handler=lambda args, _h=_handler, **kw: _h(args),
                      check_fn=lambda: True, emoji="\U0001F512")
