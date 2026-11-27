"""Settings admin -- the phase-2 write side of the settings registry
(hermes-deploy 2.5.0, DESIGN section 435 phase 2; the read side is
settings_registry.py, phase 1, hermes-deploy 1.13.0).

One write path for every settings mutation, whoever the actor is:

- the AI tool surface (tools/settings_admin_tool.py, toolset
  ``settings_admin``) calls in-process with actor="agent";
- the gateway endpoints (POST /v1/settings/entries,
  POST /v1/settings/revoke, GET /v1/settings/events in api_server.py)
  call with actor="user" -- the app face acts for the owner.

Both go through the same scope check, the same validation, the same
realization machinery and the same audit log. There is no AI-only
back door and no app-only back door (spec section 2.2).

Dead-lines (spec sections 2.4 / 5 phase 2 / 6, do not widen):

- WHITELIST. An agent write is accepted only when the record's
  ``writable_by`` is "agent" or "both", the record is reversible,
  and the key is outside the forbidden zones (audit / env /
  credentials / payments / send / user_data_delete -- first key
  segment). Anything else is refused with code ``scope_denied``.
  secret-ref records are never written through here by anyone:
  credential values live in the vault, the registry holds references
  only. Records with ``writable_by: "none"`` (the ledger class) are
  not writable through here either -- the audit log itself is
  append-only and has no write endpoint at all.
- AUDIT. Every accepted mutation appends one JSON line to
  ``settings_events.jsonl`` in the settings dir: {id, ts, actor,
  run_id, action, key, before, after}. The file is append-only;
  this module never rewrites or deletes a line. A user revoke does
  not edit history either -- it appends a compensation event that
  restores the before value (action "revoke", ``revokes`` set).
- REALIZATION. config-backed records (``source: "config"``) are
  written through the upstream hermes_cli.config load/save machine
  and self-checked by reading the value back (the grants/revoke
  discipline). Registry-valued records land in the snapshot overlay
  (/opt/data/settings/registry.json) with an atomic replace; seed
  metadata stays authoritative there exactly as phase 1 defined --
  an overlay entry for a seed key carries only its value.
- MASTER GATE. The agent write surface is live only while the
  instance config carries ``settings.agent_admin: true`` (spec
  section 5 phase 2: default off, flipped once with the approved
  application). The gate is read fail-closed. The user endpoints
  are not behind the gate: the owner's own face never locks the
  owner out of undoing what the agent did.
"""

import json
import logging
import os
import threading
import time
import urllib.request
from pathlib import Path

try:
    from gateway.platforms import settings_registry as _sr
except Exception:  # package selftest path (patches/ on sys.path)
    import settings_registry as _sr

logger = logging.getLogger("gateway.platforms.settings_admin")

SETTINGS_DIR = _sr.SETTINGS_DIR
SNAPSHOT_PATH = _sr.SNAPSHOT_PATH
EVENTS_PATH = SETTINGS_DIR / "settings_events.jsonl"

FORBIDDEN_HEADS = frozenset({
    "audit", "env", "credentials", "payments", "send",
    "user_data_delete"})

_lock = threading.Lock()


# ------------------------------------------------------------------
# small helpers
# ------------------------------------------------------------------

def _now() -> float:
    return time.time()


def _err(status: int, code: str, message: str):
    return status, {"error": message, "code": code}


def agent_admin_enabled() -> bool:
    """The phase-2 master gate: instance config settings.agent_admin.

    Fail-closed: any read problem means the agent write surface is
    off."""
    try:
        from hermes_cli.config import load_config_readonly
        cfg = load_config_readonly() or {}
    except Exception:
        return False
    section = cfg.get("settings")
    return isinstance(section, dict) \
        and section.get("agent_admin") is True


def _seed_keys() -> set:
    return {r["key"] for r in _sr.seed_records()}


def _merged_records() -> list:
    """Registry records (seed metadata authoritative, overlay
    records appended) as phase 1 serves them."""
    return _sr.get_registry()["records"]


def _find_record(key: str):
    for rec in _merged_records():
        if rec.get("key") == key:
            return rec
    return None


def _config_get(path: str):
    """Live value at a dotted config path, or None when unset."""
    from hermes_cli.config import load_config_readonly
    cfg = load_config_readonly() or {}
    node = cfg
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def current_value(record: dict):
    """The record's effective current value: live config for
    config-backed records, snapshot-or-default for the rest."""
    if record.get("source") == "config" and record.get("config_path"):
        value = _config_get(record["config_path"])
        return record.get("default") if value is None else value
    return record.get("value", record.get("default"))


def _public_record(record: dict) -> dict:
    out = dict(record)
    out["value"] = current_value(record)
    return out


# ------------------------------------------------------------------
# snapshot overlay IO (registry-valued records)
# ------------------------------------------------------------------

def _load_overlay_raw() -> list:
    try:
        data = json.loads(SNAPSHOT_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return []
    except Exception:
        logger.warning("settings snapshot unreadable; treating as "
                       "empty overlay", exc_info=True)
        return []
    if isinstance(data, dict) and isinstance(data.get("records"), list):
        return data["records"]
    if isinstance(data, list):
        return data
    return []


def _write_overlay_raw(records: list) -> None:
    SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
    tmp = SNAPSHOT_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps({"records": records},
                              ensure_ascii=False, indent=1),
                   encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, SNAPSHOT_PATH)


# ------------------------------------------------------------------
# audit log (append-only)
# ------------------------------------------------------------------

def _append_event(event: dict) -> dict:
    SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
    count = 0
    try:
        with EVENTS_PATH.open("rb") as fh:
            count = sum(1 for _ in fh)
    except FileNotFoundError:
        count = 0
    event = {"id": f"se-{count + 1:06d}", **event}
    with EVENTS_PATH.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(event, ensure_ascii=False) + "\n")
    return event


def _read_events() -> list:
    try:
        lines = EVENTS_PATH.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []
    events = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except Exception:
            continue
        if isinstance(item, dict):
            events.append(item)
    return events


def list_events(limit: int = 50, key: str = None) -> dict:
    """GET /v1/settings/events projection: chronological audit
    lines (the hub audit segment renders them next to grants /
    decisions). Read-only; there is deliberately no write verb on
    this collection anywhere."""
    events = _read_events()
    if key:
        events = [e for e in events if e.get("key") == key]
    limit = max(1, min(int(limit or 50), 500))
    return {"object": "list", "data": events[-limit:],
            "total": len(events)}


# ------------------------------------------------------------------
# scope + validation
# ------------------------------------------------------------------

def _forbidden_key(key: str) -> bool:
    head = key.replace("/", ".").split(".")[0]
    return head in FORBIDDEN_HEADS


def _check_write_scope(record: dict, actor: str):
    """None when the write may proceed, else an error tuple."""
    key = record["key"]
    if _forbidden_key(key):
        return _err(403, "scope_denied",
                    f"{key}: forbidden zone (credentials, payments, "
                    "sending, audit and user-data deletion never go "
                    "through the settings write path)")
    if record.get("type") == "secret-ref":
        return _err(403, "scope_denied",
                    f"{key}: secret-ref records hold references "
                    "only; credential values live in the vault")
    if record.get("writable_by") == "none":
        return _err(403, "scope_denied",
                    f"{key}: record is not writable (ledger class)")
    if actor == "agent":
        if record.get("writable_by") not in ("agent", "both"):
            return _err(403, "scope_denied",
                        f"{key}: writable_by="
                        f"{record.get('writable_by')!r} does not "
                        "include the agent")
        if record.get("reversible") is not True:
            return _err(403, "scope_denied",
                        f"{key}: agent writes require a reversible "
                        "record")
    return None


def _validate_value(record: dict, value):
    """None when the value fits the record, else an error tuple.
    Errors teach: the message names the expected shape."""
    key, rtype = record["key"], record.get("type")
    validation = record.get("validation") or {}
    kind = validation.get("kind")
    if rtype in ("entry", "surface"):
        return _err(400, "invalid_value",
                    f"{key}: type {rtype} carries no settable value")
    if rtype == "bool" or kind == "bool":
        if not isinstance(value, bool):
            return _err(400, "invalid_value",
                        f"{key}: expected a boolean")
    elif rtype == "enum" or kind == "enum":
        values = validation.get("values") or []
        if value not in values:
            return _err(400, "invalid_value",
                        f"{key}: expected one of {values}")
    elif rtype == "number" or kind == "number":
        if isinstance(value, bool) \
                or not isinstance(value, (int, float)):
            return _err(400, "invalid_value",
                        f"{key}: expected a number")
        if "min" in validation and value < validation["min"]:
            return _err(400, "invalid_value",
                        f"{key}: below minimum {validation['min']}")
        if "max" in validation and value > validation["max"]:
            return _err(400, "invalid_value",
                        f"{key}: above maximum {validation['max']}")
    elif rtype in ("string", "text") or kind in ("string", "text"):
        if not isinstance(value, str):
            return _err(400, "invalid_value",
                        f"{key}: expected a string")
        max_len = validation.get("max_length")
        if max_len and len(value) > max_len:
            return _err(400, "invalid_value",
                        f"{key}: longer than {max_len} characters")
    if kind == "json-string-array":
        if not isinstance(value, list) \
                or not all(isinstance(v, str) for v in value):
            return _err(400, "invalid_value",
                        f"{key}: expected a list of strings")
    return None


# ------------------------------------------------------------------
# realization
# ------------------------------------------------------------------

def _apply_config_value(record: dict, value) -> None:
    """Write a config-backed value through the upstream load/save
    machine and self-check by reading it back (grants discipline).
    Raises RuntimeError on any mismatch."""
    from hermes_cli.config import load_config, save_config
    path = record["config_path"]
    cfg = load_config()
    node = cfg
    parts = path.split(".")
    for part in parts[:-1]:
        nxt = node.get(part)
        if not isinstance(nxt, dict):
            nxt = {}
            node[part] = nxt
        node = nxt
    node[parts[-1]] = value
    save_config(cfg)
    if _config_get(path) != value:
        raise RuntimeError(f"config readback mismatch at {path}")


def _apply_registry_value(record: dict, value) -> None:
    """Write a registry-valued record's value into the snapshot
    overlay. Seed keys get a value-only entry (phase-1 rule);
    overlay-registered keys update their full record."""
    key = record["key"]
    overlay = _load_overlay_raw()
    for entry in overlay:
        if isinstance(entry, dict) and entry.get("key") == key:
            entry["value"] = value
            break
    else:
        if key in _seed_keys():
            overlay.append({"key": key, "value": value})
        else:
            full = dict(record)
            full["value"] = value
            overlay.append(full)
    _write_overlay_raw(overlay)


def _apply_value(record: dict, value) -> None:
    if record.get("source") == "config" and record.get("config_path"):
        _apply_config_value(record, value)
    else:
        _apply_registry_value(record, value)


# ------------------------------------------------------------------
# reads
# ------------------------------------------------------------------

def list_settings(surface: str = None, owner: str = None) -> dict:
    records = [_public_record(r) for r in _merged_records()]
    if surface:
        records = [r for r in records if r.get("surface") == surface]
    if owner:
        records = [r for r in records if r.get("owner") == owner]
    return {"object": "settings.list", "records": records}


def get_setting(key: str):
    record = _find_record(key)
    if record is None:
        return _err(404, "unknown_key", f"{key}: no such setting")
    return 200, {"object": "settings.record",
                 "record": _public_record(record)}


# mutations (internal *_locked run under _lock; public wrappers
# take it. All return (status, payload).)
# ------------------------------------------------------------------

def _stamp(action: str, via_revoke: bool, revokes: str):
    fields = {"action": "revoke" if via_revoke else action}
    if revokes:
        fields["revokes"] = revokes
    return fields


def _set_locked(key, value, actor, run_id, via_revoke=False,
                revokes=None):
    record = _find_record(key)
    if record is None:
        return _err(404, "unknown_key", f"{key}: no such setting")
    denied = _check_write_scope(record, actor)
    if denied:
        return denied
    invalid = _validate_value(record, value)
    if invalid:
        return invalid
    before = current_value(record)
    try:
        _apply_value(record, value)
    except Exception as exc:
        logger.exception("settings set failed for %s", key)
        return _err(500, "apply_failed",
                    f"{key}: write failed: {exc!r}")
    event = _append_event({
        "ts": _now(), "actor": actor, "run_id": run_id,
        **_stamp("set", via_revoke, revokes),
        "key": key, "before": before, "after": value})
    return 200, {"object": "settings.receipt", "key": key,
                 "before": before, "after": value,
                 "event_id": event["id"]}


def _register_locked(record, actor, run_id, via_revoke=False,
                     revokes=None):
    if not isinstance(record, dict) \
            or not isinstance(record.get("key"), str):
        return _err(400, "invalid_record",
                    "record must be an object with a string key")
    key = record["key"]
    if _forbidden_key(key):
        return _err(403, "scope_denied", f"{key}: forbidden zone")
    if record.get("type") == "secret-ref":
        return _err(403, "scope_denied",
                    f"{key}: secret-ref records are not registrable "
                    "through the write path")
    problems = _sr.validate_records([record])
    if problems:
        return _err(400, "invalid_record", "; ".join(problems))
    if _find_record(key) is not None:
        return _err(409, "key_exists",
                    f"{key}: a record with this key already exists; "
                    "set its value or delete it first")
    if actor == "agent" and not via_revoke:
        if record.get("owner") not in ("agent", "shared"):
            return _err(403, "scope_denied",
                        "the agent may only register agent- or "
                        "shared-owned records")
        if record.get("reversible") is not True:
            return _err(403, "scope_denied",
                        "agent registrations must be reversible")
    stored = dict(record)
    stored.setdefault("source", "server")
    overlay = _load_overlay_raw()
    overlay.append(stored)
    try:
        _write_overlay_raw(overlay)
    except Exception as exc:
        logger.exception("settings register failed for %s", key)
        return _err(500, "apply_failed",
                    f"{key}: write failed: {exc!r}")
    event = _append_event({
        "ts": _now(), "actor": actor, "run_id": run_id,
        **_stamp("register", via_revoke, revokes),
        "key": key, "before": None, "after": stored})
    return 200, {"object": "settings.receipt", "key": key,
                 "registered": True, "event_id": event["id"]}


def _delete_locked(key, actor, run_id, via_revoke=False,
                   revokes=None):
    record = _find_record(key)
    if record is None:
        return _err(404, "unknown_key", f"{key}: no such setting")
    denied = _check_write_scope(record, actor)
    if denied:
        return denied
    before = {"record": dict(record), "value": current_value(record)}
    overlay = _load_overlay_raw()
    kept = [e for e in overlay
            if not (isinstance(e, dict) and e.get("key") == key)]
    is_seed = key in _seed_keys()
    if len(kept) == len(overlay):
        return _err(400, "nothing_to_delete",
                    f"{key}: no overlay entry to remove"
                    + ("; seed records themselves are the catalog "
                       "and cannot be deleted" if is_seed else ""))
    try:
        _write_overlay_raw(kept)
    except Exception as exc:
        logger.exception("settings delete failed for %s", key)
        return _err(500, "apply_failed",
                    f"{key}: write failed: {exc!r}")
    event = _append_event({
        "ts": _now(), "actor": actor, "run_id": run_id,
        **_stamp("delete", via_revoke, revokes),
        "key": key, "before": before, "after": None})
    return 200, {"object": "settings.receipt", "key": key,
                 "deleted": not is_seed, "value_cleared": is_seed,
                 "event_id": event["id"]}


def set_setting(key: str, value, actor: str, run_id: str = None):
    with _lock:
        return _set_locked(key, value, actor, run_id)


def register_setting(record, actor: str, run_id: str = None):
    with _lock:
        return _register_locked(record, actor, run_id)


def delete_setting(key: str, actor: str, run_id: str = None):
    with _lock:
        return _delete_locked(key, actor, run_id)


def revoke_event(event_id: str, actor: str = "user",
                 run_id: str = None):
    """Undo one audit event by appending a compensation event
    (spec section 2.4: history is never edited; the revoke itself
    is on the record). Revoking a revoke is refused, as is a
    second revoke of the same event."""
    with _lock:
        events = _read_events()
        target = next((e for e in events
                       if e.get("id") == event_id), None)
        if target is None:
            return _err(404, "unknown_event",
                        f"{event_id}: no such audit event")
        if target.get("action") == "revoke":
            return _err(400, "not_revocable",
                        f"{event_id}: a revoke cannot be revoked")
        if any(e.get("revokes") == event_id for e in events):
            return _err(409, "already_revoked",
                        f"{event_id}: already revoked")
        action, key = target.get("action"), target.get("key")
        if action == "set":
            status, payload = _set_locked(
                key, target.get("before"), actor, run_id,
                via_revoke=True, revokes=event_id)
        elif action == "register":
            if _find_record(key) is None:
                return _err(400, "not_revocable",
                            f"{event_id}: the registered record "
                            f"{key} is already absent (a later "
                            "delete removed it); revoke that "
                            "delete instead if it should come back")
            status, payload = _delete_locked(
                key, actor, run_id,
                via_revoke=True, revokes=event_id)
        elif action == "delete":
            before = target.get("before") or {}
            record = dict(before.get("record") or {})
            if key in _seed_keys():
                status, payload = _set_locked(
                    key, before.get("value"), actor, run_id,
                    via_revoke=True, revokes=event_id)
            else:
                if before.get("value") is not None:
                    record["value"] = before["value"]
                status, payload = _register_locked(
                    record, actor, run_id,
                    via_revoke=True, revokes=event_id)
        else:
            return _err(400, "not_revocable",
                        f"{event_id}: action {action!r} has no "
                        "compensation")
        if status == 200:
            payload = dict(payload)
            payload["revokes"] = event_id
        return status, payload


# ------------------------------------------------------------------
# capability liveness (surface self-registration gate, spec 2.5)
# ------------------------------------------------------------------

def capability_live(capability) -> bool:
    """A surface record may only be registered against a live
    capability. ``features.*`` references are checked against the
    gateway's own /v1/capabilities over loopback (fail-closed);
    other reference forms (deploy-package probe numbers) cannot be
    probed at runtime and pass."""
    if not capability:
        return False
    if not isinstance(capability, str) \
            or not capability.startswith("features."):
        return True
    name = capability.split(".", 1)[1]
    key = os.environ.get("API_SERVER_KEY") \
        or os.environ.get("HERMES_API_KEY", "")
    if not key:
        return False
    req = urllib.request.Request(
        "http://127.0.0.1:8642/v1/capabilities",
        headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception:
        return False
    return bool((data.get("features") or {}).get(name))
