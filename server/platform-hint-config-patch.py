#!/usr/bin/env python3
"""platform-hint-config-patch.py -- hermes-deploy 2.7.1 one-shot config migration.

Scope: exactly one spot of the instance config
(<deploy-dir>/data/config.yaml): a top-level ``platform_hints:``
section whose ``api_server.replace`` substitutes the upstream
built-in api_server platform hint.

Why: the upstream hint orders the model to assume plain text and
forbid markdown (no asterisks, bullets, headers, code fences). Every
OneDay session runs on api_server, so that hint silently overrode the
user's bold-anchor writing rule (see platform-hint-fix-20261126.md).
The replacement keeps the hint's MEDIA:/file-delivery semantics
verbatim in effect and only changes the formatting stance: the OneDay
client renders markdown; follow the prompt's writing-style rules.

The edit is text-scoped (one appended section, or an in-place repair
of an existing platform_hints block) so the rest of the config --
comments, ordering, other keys -- is byte-identical afterwards. A
timestamped backup is written next to the config before any change.
Idempotent: a config already in final form verifies and exits 0
without writing. No secrets are read or printed.

Usage: python3 platform-hint-config-patch.py [deploy-dir]
       (default /www/dk_project/dk_app/hermes)
"""
import shutil
import sys
import time
from pathlib import Path

HINT = (
    "You are responding through the OneDay app, reached through the gateway "
    "API server. The client renders markdown: bold, lists, tables and code "
    "blocks display properly. Follow the writing-style rules in this prompt: "
    "in information-dense replies, bold the few anchor words (a key "
    "conclusion, a number, a name, a time) so the user can scan; keep casual "
    "conversation unbolded and never bold whole sentences or paragraphs. "
    "File/media delivery: images referenced as MEDIA:/absolute/path tags "
    "(.png/.jpg/.jpeg/.gif/.webp/.bmp, up to 5MB) are inlined as base64 data "
    "URLs in responses on the chat, completions, and responses endpoints. "
    "Non-image files are NOT intercepted anywhere, and the runs endpoint "
    "intercepts nothing - a MEDIA: tag there renders as literal text exposing "
    "a raw host filesystem path. For those cases, state the plain file path "
    "in your response text instead of a MEDIA: tag."
)

BLOCK = (
    "\nplatform_hints:\n"
    "  api_server:\n"
    "    replace: \"" + HINT + "\"\n"
)


def main() -> int:
    deploy = Path(sys.argv[1] if len(sys.argv) > 1 else "/www/dk_project/dk_app/hermes")
    cfg = deploy / "data" / "config.yaml"
    if not cfg.is_file():
        print("config not found: %s" % cfg)
        return 1
    text = cfg.read_text(encoding="utf-8")
    if "platform_hints:" in text:
        if HINT in text:
            print("already in final form, no write")
            return 0
        print("platform_hints present but hint differs -- manual review needed, no write")
        return 2
    backup = cfg.with_name(cfg.name + ".bak-" + time.strftime("%Y%m%d%H%M%S") + "-platformhint")
    shutil.copy2(cfg, backup)
    cfg.write_text(text.rstrip("\n") + "\n" + BLOCK, encoding="utf-8")
    print("appended platform_hints block; backup: %s" % backup.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
