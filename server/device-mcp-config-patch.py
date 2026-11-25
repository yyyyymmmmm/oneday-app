#!/usr/bin/env python3
"""device-mcp-config-patch.py -- hermes-deploy 2.0.0 (bridge-retirement
batch 5) one-shot config migration.

Scope: exactly one entry of the instance config -- mcp_servers.device
in <deploy-dir>/data/config.yaml:
  url:                https://hermes.example.com/api/device-mcp
                      -> http://127.0.0.1:8642/api/device-mcp
  headers.Authorization: Bearer <retired bridge key>
                      -> Bearer <API_SERVER_KEY> (the single key)

The single key is taken from the environment (API_SERVER_KEY) or,
failing that, parsed out of the instance's docker-compose.yml
environment list. It is never printed; the report carries lengths
only. A timestamped backup is written next to the config before any
change. The edit is text-scoped (line surgery inside the device
block only) so the rest of the config -- comments, ordering, other
servers -- is byte-identical afterwards. Idempotent: a config
already in final form verifies and exits 0 without writing.

Usage: python3 device-mcp-config-patch.py [deploy-dir]
       (default /srv/hermes)
"""
import os
import re
import shutil
import sys
import time
from pathlib import Path

NEW_URL = "http://127.0.0.1:8642/api/device-mcp"


def die(msg):
    print("!! " + msg)
    sys.exit(1)


def load_key(deploy: Path) -> str:
    key = os.environ.get("API_SERVER_KEY", "").strip()
    if key:
        return key
    compose = deploy / "docker-compose.yml"
    if compose.exists():
        m = re.search(r"-\s*API_SERVER_KEY=(\S+)",
                      compose.read_text(encoding="utf-8"))
        if m:
            return m.group(1).strip().strip('"').strip("'")
    die("API_SERVER_KEY not found in env or instance compose; aborting")


def main():
    deploy = Path(sys.argv[1] if len(sys.argv) > 1
                  else "/srv/hermes")
    cfg_path = deploy / "data" / "config.yaml"
    if not cfg_path.exists():
        die(f"config not found: {cfg_path}")
    key = load_key(deploy)
    want_auth = "Bearer " + key

    lines = cfg_path.read_text(encoding="utf-8").split("\n")

    # Locate mcp_servers: section, then the device: block inside it.
    sec = None
    for i, ln in enumerate(lines):
        if re.match(r"^mcp_servers:\s*$", ln):
            sec = i
            break
    if sec is None:
        die("mcp_servers: section not found")
    dev = None
    for i in range(sec + 1, len(lines)):
        ln = lines[i]
        if ln and not ln.startswith(" ") and not ln.startswith("#"):
            break  # left the section
        if re.match(r"^  device:\s*$", ln):
            dev = i
            break
    if dev is None:
        die("mcp_servers.device block not found")
    end = len(lines)
    for i in range(dev + 1, len(lines)):
        ln = lines[i]
        if ln.strip() and not ln.startswith("    "):
            end = i
            break

    url_hits = []
    auth_hits = []
    for i in range(dev + 1, end):
        if re.match(r"^\s+url:\s*", lines[i]):
            url_hits.append(i)
        if re.match(r"^\s+Authorization:\s*", lines[i]):
            auth_hits.append(i)
    if len(url_hits) != 1:
        die(f"device block url lines: {len(url_hits)} (expected 1)")
    if len(auth_hits) != 1:
        die(f"device block Authorization lines: {len(auth_hits)}"
            " (expected 1)")

    ui, ai = url_hits[0], auth_hits[0]
    cur_url = re.sub(r"^\s+url:\s*", "", lines[ui]).strip()
    cur_auth = re.sub(r"^\s+Authorization:\s*", "", lines[ai]).strip()
    changed = []
    if cur_url != NEW_URL:
        indent = lines[ui][:len(lines[ui]) - len(lines[ui].lstrip())]
        lines[ui] = f"{indent}url: {NEW_URL}"
        changed.append(f"url {cur_url} -> {NEW_URL}")
    if cur_auth != want_auth:
        indent = lines[ai][:len(lines[ai]) - len(lines[ai].lstrip())]
        lines[ai] = f"{indent}Authorization: {want_auth}"
        changed.append(
            f"Authorization replaced (old len {len(cur_auth)},"
            f" new len {len(want_auth)})")

    if not changed:
        print("device entry already in final form (gateway URL +"
              " single key); nothing to do")
        return
    backup = cfg_path.with_name(
        "config.yaml.bak-" + time.strftime("%Y%m%d%H%M%S"))
    shutil.copy2(cfg_path, backup)
    cfg_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"backup: {backup.name}")
    for c in changed:
        print(" -", c)
    print("config.yaml mcp_servers.device migrated to gateway"
          " (single key)")


if __name__ == "__main__":
    main()
