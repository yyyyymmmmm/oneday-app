#!/usr/bin/env python3
"""settings-admin-config-patch.py -- hermes-deploy 2.5.0 (DESIGN
section 435 phase 2) one-shot config migration.

Scope: exactly two spots of the instance config
(<deploy-dir>/data/config.yaml):

  1. platform_toolsets.api_server gains the ``settings_admin``
     toolset row (registry passthrough -- the same route
     self_reactions / options_card take), so the agent's settings
     tools can enter the phone surface's schema.
  2. A top-level ``settings:`` section is created (or completed)
     with ``agent_admin: true`` -- the phase-2 master gate. The
     gate ships default-off upstream; flipping it on this instance
     is the approved phase-2 act (user approval 2026-11-25, spec
     section 5 phase 2: "default off, flipped once with the
     approved application").

The edit is text-scoped (line surgery inside the api_server list;
one appended section) so the rest of the config -- comments,
ordering, other keys -- is byte-identical afterwards. A
timestamped backup is written next to the config before any
change. Idempotent: a config already in final form verifies and
exits 0 without writing. No secrets are read or printed.

Usage: python3 settings-admin-config-patch.py [deploy-dir]
       (default /srv/hermes)
"""
import re
import shutil
import sys
import time
from pathlib import Path

TOOLSET = "settings_admin"

GATE_BLOCK = [
    "",
    "# AI settings administration master gate (hermes-deploy 2.5.0,",
    "# DESIGN section 435 phase 2; approved 2026-11-25). Upstream",
    "# default is off; this instance runs with the agent settings",
    "# write surface on. Every write is whitelist-scoped, audited",
    "# in /opt/data/settings/settings_events.jsonl and revocable",
    "# by the user; setting this back to false closes the agent",
    "# write surface without touching the user's own face.",
    "settings:",
    "  agent_admin: true",
]


def die(msg):
    print("!! " + msg)
    sys.exit(1)


def find_toolset_state(lines):
    """(present, insert_at): whether api_server already lists the
    toolset, and the line index after its last list item."""
    sec = None
    for i, ln in enumerate(lines):
        if re.match(r"^platform_toolsets:\s*$", ln):
            sec = i
            break
    if sec is None:
        die("platform_toolsets: section not found")
    api = None
    for i in range(sec + 1, len(lines)):
        ln = lines[i]
        if ln and not ln.startswith(" ") and not ln.startswith("#"):
            break
        if re.match(r"^  api_server:\s*$", ln):
            api = i
            break
    if api is None:
        die("platform_toolsets.api_server block not found")
    last_item = api
    present = False
    for i in range(api + 1, len(lines)):
        ln = lines[i]
        m = re.match(r"^    -\s*(\S+)\s*$", ln)
        if m:
            last_item = i
            if m.group(1) == TOOLSET:
                present = True
            continue
        if ln.strip() == "" or ln.lstrip().startswith("#"):
            continue
        break
    return present, last_item + 1


def find_gate_state(lines):
    """(state, idx): state is 'true' / 'other' / 'missing-key' /
    'missing-section'; idx is the agent_admin line index when one
    exists, else the settings: section index, else None."""
    sec = None
    for i, ln in enumerate(lines):
        if re.match(r"^settings:\s*$", ln):
            sec = i
            break
    if sec is None:
        return "missing-section", None
    for i in range(sec + 1, len(lines)):
        ln = lines[i]
        if ln and not ln.startswith(" ") and not ln.startswith("#"):
            break
        m = re.match(r"^  agent_admin:\s*(\S+)", ln)
        if m:
            return ("true" if m.group(1) == "true" else "other"), i
    return "missing-key", sec


def verify(lines) -> bool:
    present, _ = find_toolset_state(lines)
    state, _ = find_gate_state(lines)
    return present and state == "true"


def main():
    deploy = Path(sys.argv[1] if len(sys.argv) > 1
                  else "/srv/hermes")
    cfg_path = deploy / "data" / "config.yaml"
    if not cfg_path.exists():
        die(f"config not found: {cfg_path}")
    text = cfg_path.read_text(encoding="utf-8")
    lines = text.split("\n")

    if verify(lines):
        print("settings-admin config already in final form; "
              "nothing to do")
        return

    backup = cfg_path.with_name(
        f"config.yaml.bak-settings-admin-{int(time.time())}")
    shutil.copy2(cfg_path, backup)
    print(f"backup: {backup.name}")

    present, insert_at = find_toolset_state(lines)
    if not present:
        lines.insert(insert_at, f"    - {TOOLSET}")
        print(f"platform_toolsets.api_server += {TOOLSET}")
    else:
        print("platform_toolsets.api_server already lists "
              f"{TOOLSET}")

    state, idx = find_gate_state(lines)
    if state == "missing-section":
        while lines and lines[-1] == "":
            lines.pop()
        lines.extend(GATE_BLOCK)
        lines.append("")
        print("settings: section appended with agent_admin: true")
    elif state == "missing-key":
        lines.insert(idx + 1, "  agent_admin: true")
        print("settings.agent_admin inserted (true)")
    elif state == "other":
        lines[idx] = "  agent_admin: true"
        print("settings.agent_admin flipped to true")
    else:
        print("settings.agent_admin already true")

    cfg_path.write_text("\n".join(lines), encoding="utf-8")
    after = cfg_path.read_text(encoding="utf-8").split("\n")
    if not verify(after):
        die("post-write verification failed; restore from backup "
            f"{backup.name}")
    print("verified: toolset row present, agent_admin true")


if __name__ == "__main__":
    main()
