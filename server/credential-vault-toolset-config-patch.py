#!/usr/bin/env python3
"""Enable only the credential_vault toolset in an instance config.

Text-scoped and idempotent. A timestamped backup is made before the
single api_server list row is inserted. No other config values change.
"""
import re
import shutil
import sys
import time
from pathlib import Path

TOOLSET = "credential_vault"


def die(message):
    print("!! " + message)
    sys.exit(1)


def locate_toolset(lines):
    section = None
    for index, line in enumerate(lines):
        if re.match(r"^platform_toolsets:\s*$", line):
            section = index
            break
    if section is None:
        die("platform_toolsets: section not found")

    api = None
    for index in range(section + 1, len(lines)):
        line = lines[index]
        if line and not line.startswith((" ", "\t", "#")):
            break
        if re.match(r"^  api_server:\s*$", line):
            api = index
            break
    if api is None:
        die("platform_toolsets.api_server block not found")

    last_item = api
    present = False
    for index in range(api + 1, len(lines)):
        line = lines[index]
        match = re.match(r"^    -\s*(\S+)\s*$", line)
        if match:
            last_item = index
            if match.group(1) == TOOLSET:
                present = True
            continue
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        break
    return present, last_item + 1


def main():
    deploy = Path(sys.argv[1] if len(sys.argv) > 1 else "/srv/hermes")
    config = deploy / "data" / "config.yaml"
    if not config.is_file():
        die("config not found: " + str(config))

    original = config.read_text(encoding="utf-8")
    lines = original.split("\n")
    present, insert_at = locate_toolset(lines)
    if present:
        print("credential_vault already enabled; nothing to do")
        return

    backup = config.with_name(
        "config.yaml.bak-credential-vault-" + time.strftime("%Y%m%d%H%M%S"))
    shutil.copy2(str(config), str(backup))
    lines.insert(insert_at, "    - " + TOOLSET)
    updated = "\n".join(lines)
    config.write_text(updated, encoding="utf-8")

    check_lines = config.read_text(encoding="utf-8").split("\n")
    enabled, _ = locate_toolset(check_lines)
    if not enabled:
        config.write_text(original, encoding="utf-8")
        die("post-write verification failed; original config restored")
    print("backup: " + backup.name)
    print("verified: platform_toolsets.api_server includes credential_vault")


if __name__ == "__main__":
    main()
