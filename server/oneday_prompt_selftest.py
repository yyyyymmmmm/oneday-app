#!/usr/bin/env python3
"""Selftest for the OneDay first-layer prompt module (§442, #22).

Stubs hermes_constants so the module renders against a temp
HERMES_HOME: full identity -> rendered text with placeholders gone;
missing file / empty value / broken JSON -> None (assembly untouched).

Run: python3 oneday_prompt_selftest.py   (exit 0 = all passed)
"""
import importlib.util
import json
import sys
import tempfile
import types
from pathlib import Path

PKG = Path(__file__).resolve().parent
CHECKS = []

def check(name, cond, detail=""):
    CHECKS.append((name, bool(cond)))
    print(("PASS " if cond else "FAIL ") + name, "" if cond else detail)

def main():
    tmp = Path(tempfile.mkdtemp(prefix="odprompt-stub-"))
    fake = types.ModuleType("hermes_constants")
    fake.get_hermes_home = lambda: tmp
    sys.modules["hermes_constants"] = fake
    spec = importlib.util.spec_from_file_location(
        "oneday_prompt", PKG / "patches" / "oneday_prompt.py")
    om = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(om)

    check("render: missing identity.json -> None", om.render_oneday_prompt() is None)
    (tmp / "identity.json").write_text(json.dumps(
        {"agent_name": "小天", "company_name": "示例科技", "product_name": "OneDay"}),
        encoding="utf-8")
    out = om.render_oneday_prompt()
    check("render: full identity renders", isinstance(out, str) and len(out) > 10000)
    check("render: placeholders gone", out is not None and "{{" not in out)
    check("render: identity values in text",
          out is not None and "You are 小天" in out and "示例科技" in out
          and "personal agent in OneDay" in out)
    check("render: safety chapter present",
          out is not None and "Safety — The Red Lines" in out
          and "sexual content involving minors" in out)
    check("render: credential request marker instruction present",
          out is not None and "[[vreq:vreq_...]]" in out
          and "never put credential values in chat" in out)
    (tmp / "identity.json").write_text(json.dumps(
        {"agent_name": "", "company_name": "示例科技", "product_name": "OneDay"}),
        encoding="utf-8")
    check("render: empty value -> None", om.render_oneday_prompt() is None)
    (tmp / "identity.json").write_text("{broken", encoding="utf-8")
    check("render: broken JSON -> None", om.render_oneday_prompt() is None)

    failed = [n for n, ok in CHECKS if not ok]
    print("\n%d/%d passed" % (len(CHECKS) - len(failed), len(CHECKS)))
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
