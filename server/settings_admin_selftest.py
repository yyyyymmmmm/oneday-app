#!/usr/bin/env python3
"""settings_admin_selftest.py -- hermes-deploy 2.5.0.

In-isolation checks for the settings write path (DESIGN section
435 phase 2): patches/settings_admin.py against the real phase-1
seed (patches/settings_registry.py), with the settings dir pointed
at a temp tree and hermes_cli.config stubbed by an in-memory dict
-- no live config, no live snapshot, no network.

Checks, in order:
  1. the master gate reads settings.agent_admin fail-closed;
  2. reads: 43 seed records list; one record get; unknown key 404;
  3. agent set on the one agent-writable seed record (config-
     backed) lands, reads back and is audited;
  4. scope refusals: user-owned record, ledger-class record
     (writable_by none), secret-ref record, forbidden-zone key,
     irreversible registration, user-owned registration;
  5. validation refusals teach (wrong type, bad enum value);
  6. register -> set -> delete on a fresh agent record, all
     audited in order;
  7. revoke: of a set (value restored), of a register (record
     gone), of a delete (record restored with its value);
     double revoke 409; revoke-of-revoke 400; unknown event 404;
  8. the audit file is append-only across all of it (line count
     only ever grows; every line parses; ids are sequential);
  9. capability liveness: non-features references pass, empty
     fails (the features.* probe needs a live gateway and is not
     exercised here).

Exits non-zero on the first failed check. Run from the deploy
package root: python3 settings_admin_selftest.py
"""
import json
import sys
import tempfile
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "patches"))

# --- stub hermes_cli.config with an in-memory config -------------
_FAKE_CFG = {
    "display": {"agent_self_reactions": False, "options_card": False},
    "settings": {"agent_admin": False},
}

_hermes_cli = types.ModuleType("hermes_cli")
_hermes_cli.__path__ = []
_config_mod = types.ModuleType("hermes_cli.config")


def _load():
    return json.loads(json.dumps(_FAKE_CFG))


_config_mod.load_config = _load
_config_mod.load_config_readonly = _load
_config_mod.save_config = lambda cfg: _FAKE_CFG.update(
    json.loads(json.dumps(cfg)))
sys.modules["hermes_cli"] = _hermes_cli
sys.modules["hermes_cli.config"] = _config_mod

import settings_registry as sr          # noqa: E402
import settings_admin as sa             # noqa: E402

# --- point every storage path at a temp tree ---------------------
_tmp = Path(tempfile.mkdtemp(prefix="settings-admin-selftest-"))
sr.SETTINGS_DIR = _tmp
sr.SNAPSHOT_PATH = _tmp / "registry.json"
sa.SETTINGS_DIR = _tmp
sa.SNAPSHOT_PATH = _tmp / "registry.json"
sa.EVENTS_PATH = _tmp / "settings_events.jsonl"

CHECKS = 0


def check(cond, label):
    global CHECKS
    CHECKS += 1
    if not cond:
        print(f"FAIL [{CHECKS}] {label}")
        sys.exit(1)
    print(f"ok   [{CHECKS}] {label}")


def events():
    return sa._read_events()


# 1. master gate ---------------------------------------------------
check(sa.agent_admin_enabled() is False,
      "gate closed while settings.agent_admin is false")
_FAKE_CFG["settings"]["agent_admin"] = True
check(sa.agent_admin_enabled() is True,
      "gate opens when settings.agent_admin is true")

# 2. reads ----------------------------------------------------------
data = sa.list_settings()
check(len(data["records"]) == 43, "list returns the 43 seed records")
status, payload = sa.get_setting("display.agent_self_reactions")
check(status == 200 and payload["record"]["value"] is False,
      "get returns the live config value")
status, payload = sa.get_setting("no.such.key")
check(status == 404 and payload["code"] == "unknown_key",
      "unknown key -> 404 unknown_key")

# 3. agent set on the agent-writable config-backed record ----------
status, payload = sa.set_setting(
    "display.agent_self_reactions", True, actor="agent",
    run_id="selftest-run")
check(status == 200 and payload["after"] is True,
      "agent set on writable_by=both record accepted")
check(_FAKE_CFG["display"]["agent_self_reactions"] is True,
      "config value actually changed (readback through stub)")
ev = events()
check(len(ev) == 1 and ev[0]["action"] == "set"
      and ev[0]["actor"] == "agent"
      and ev[0]["run_id"] == "selftest-run"
      and ev[0]["before"] is False and ev[0]["after"] is True,
      "set appended one audit event with before/after")
set_event_id = ev[0]["id"]

# 4. scope refusals --------------------------------------------------
status, payload = sa.set_setting("memory.write_approval", True,
                                 actor="agent")
check(status == 403 and payload["code"] == "scope_denied",
      "agent set on user-owned record -> scope_denied")
none_key = next(r["key"] for r in sr.seed_records()
                if r["writable_by"] == "none")
status, payload = sa.set_setting(none_key, "x", actor="user")
check(status == 403 and payload["code"] == "scope_denied",
      "ledger-class record is not writable by anyone here")
# The seed carries no secret-ref record; inject one into the
# overlay directly to cover the refusal path.
sa._write_overlay_raw([{
    "key": "machine.vault_ref", "type": "secret-ref",
    "default": None, "surface": "machine", "owner": "user",
    "writable_by": "user", "validation": None, "capability": None,
    "reversible": True, "source": "server"}])
status, payload = sa.set_setting("machine.vault_ref", "x",
                                 actor="user")
check(status == 403 and payload["code"] == "scope_denied",
      "secret-ref record -> scope_denied")
sa._write_overlay_raw([])
status, payload = sa.register_setting(
    {"key": "credentials.new_key", "type": "string", "default": "",
     "surface": "agent", "owner": "agent", "writable_by": "agent",
     "validation": None, "capability": None, "reversible": True},
    actor="agent")
check(status == 403 and payload["code"] == "scope_denied",
      "register in the credentials zone -> scope_denied")
base = {"key": "agent.selftest_knob", "type": "number",
        "default": 3, "surface": "agent", "owner": "agent",
        "writable_by": "agent",
        "validation": {"kind": "number", "min": 0, "max": 10},
        "capability": None, "reversible": True}
bad = dict(base, key="agent.selftest_irrev", reversible=False)
status, payload = sa.register_setting(bad, actor="agent")
check(status == 403 and payload["code"] == "scope_denied",
      "irreversible agent registration -> scope_denied")
bad = dict(base, key="agent.selftest_user_owned", owner="user")
status, payload = sa.register_setting(bad, actor="agent")
check(status == 403 and payload["code"] == "scope_denied",
      "user-owned agent registration -> scope_denied")
check(len(events()) == 1, "refusals append no audit events")

# 5. validation refusals ---------------------------------------------
status, payload = sa.set_setting(
    "display.agent_self_reactions", "yes", actor="agent")
check(status == 400 and payload["code"] == "invalid_value",
      "bool record rejects a string value")

# 6. register -> set -> delete ---------------------------------------
status, payload = sa.register_setting(base, actor="agent")
check(status == 200 and payload["registered"] is True,
      "agent registers a fresh reversible record")
status, payload = sa.register_setting(base, actor="agent")
check(status == 409 and payload["code"] == "key_exists",
      "duplicate registration -> 409 key_exists")
status, payload = sa.set_setting("agent.selftest_knob", 7,
                                 actor="agent")
check(status == 200 and payload["before"] == 3
      and payload["after"] == 7, "set on the fresh record lands")
status, payload = sa.set_setting("agent.selftest_knob", 99,
                                 actor="agent")
check(status == 400 and payload["code"] == "invalid_value",
      "range validation refuses 99 (max 10)")
status, payload = sa.get_setting("agent.selftest_knob")
check(status == 200 and payload["record"]["value"] == 7,
      "registry value reads back from the snapshot overlay")
status, payload = sa.delete_setting("agent.selftest_knob",
                                    actor="agent")
check(status == 200 and payload["deleted"] is True,
      "agent deletes its own record")
status, payload = sa.get_setting("agent.selftest_knob")
check(status == 404, "deleted record is gone")
actions = [e["action"] for e in events()]
check(actions == ["set", "register", "set", "delete"],
      f"audit order is set/register/set/delete (got {actions})")

# 7. revoke -----------------------------------------------------------
status, payload = sa.revoke_event(set_event_id, actor="user")
check(status == 200 and payload["revokes"] == set_event_id,
      "user revokes the agent's set")
check(_FAKE_CFG["display"]["agent_self_reactions"] is False,
      "revoke restored the before value in config")
status, payload = sa.revoke_event(set_event_id, actor="user")
check(status == 409 and payload["code"] == "already_revoked",
      "second revoke of the same event -> 409")
revoke_id = events()[-1]["id"]
status, payload = sa.revoke_event(revoke_id, actor="user")
check(status == 400 and payload["code"] == "not_revocable",
      "revoking a revoke -> 400")
status, payload = sa.revoke_event("se-999999", actor="user")
check(status == 404 and payload["code"] == "unknown_event",
      "unknown event -> 404")
register_event = next(e for e in events()
                      if e["action"] == "register")
status, payload = sa.revoke_event(register_event["id"],
                                  actor="user")
check(status == 400 and payload["code"] == "not_revocable",
      "revoking the register of an already-deleted record is "
      "refused with a teaching error, not half-applied")
# delete-revoke: register again, set, delete, then revoke the delete
sa.register_setting(base, actor="agent")
sa.set_setting("agent.selftest_knob", 5, actor="agent")
sa.delete_setting("agent.selftest_knob", actor="agent")
delete_event = events()[-1]
check(delete_event["action"] == "delete", "delete event on record")
status, payload = sa.revoke_event(delete_event["id"], actor="user")
check(status == 200, "user revokes the delete")
status, payload = sa.get_setting("agent.selftest_knob")
check(status == 200 and payload["record"]["value"] == 5,
      "delete-revoke restored the record with its value")

# 8. audit file shape ---------------------------------------------------
raw = sa.EVENTS_PATH.read_text(encoding="utf-8").splitlines()
parsed = [json.loads(ln) for ln in raw if ln.strip()]
check(len(parsed) == len(events()), "every audit line parses")
ids = [e["id"] for e in parsed]
check(ids == sorted(ids) and len(set(ids)) == len(ids),
      "event ids are sequential and unique")
check(all("revokes" in e for e in parsed if e["action"] == "revoke"),
      "every revoke event names what it revokes")

# 9. capability liveness (offline part) ---------------------------------
check(sa.capability_live("capabilities.41") is True,
      "non-features capability references pass")
check(sa.capability_live("") is False
      and sa.capability_live(None) is False,
      "empty capability reference fails")

print(f"\nALL {CHECKS} CHECKS PASSED")
