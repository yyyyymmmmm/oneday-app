#!/usr/bin/env python3
"""Self-test for the capabilities version_gate block (2026-11-26, 审计 T-2 补回).

The gate itself is declarative: api_server.py advertises
``version_gate {min_app_version, recommended_app_version, hermes_version}``
in the GET /v1/capabilities response and the App enforces it. This test
covers the server half end to end:

  1. the block is present in patches/api_server.py, in the capabilities
     response, between "auth" and "runtime" (its 2.7.1-line position);
  2. the shipped block text is evaluated verbatim (only os.getenv and
     _hermes_version are stubbed) -- defaults are 0.50.125 / 0.51.0 and
     the ONEDAY_MIN_APP_VERSION / ONEDAY_RECOMMENDED_APP_VERSION env
     overrides reach the advertised values;
  3. gate semantics over the advertised values: below min -> blocked,
     at/above min -> pass, below recommended -> upgrade hint present,
     at/above recommended -> no hint. Version comparison is numeric
     per component (0.50.99 < 0.50.125), not lexicographic.
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
API_SERVER = ROOT / "patches" / "api_server.py"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def extract_gate_block(source: str) -> str:
    """Return the source text of the version_gate dict literal."""
    m = re.search(
        r'"version_gate": \{\n(.*?)\n            \},',
        source, re.DOTALL)
    assert m, "version_gate block not found in capabilities response"
    return '"version_gate": {\n' + m.group(1) + "\n}"


def eval_gate(source: str, env: dict) -> dict:
    """Evaluate the shipped block verbatim with a stubbed environment."""
    block = extract_gate_block(source)
    saved = {k: os.environ.get(k) for k in
             ("ONEDAY_MIN_APP_VERSION", "ONEDAY_RECOMMENDED_APP_VERSION")}
    for k in saved:
        os.environ.pop(k, None)
    os.environ.update(env)
    try:
        expr = "{" + block + "}"
        result = eval(expr, {"os": os,
                             "_hermes_version": lambda: "0.23.0-test"})
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    return result["version_gate"]


def parse_version(v: str):
    return tuple(int(p) for p in v.split("."))


def gate_decision(app_version: str, gate: dict) -> str:
    """App-side enforcement semantics over the advertised gate values."""
    app = parse_version(app_version)
    if app < parse_version(gate["min_app_version"]):
        return "blocked"
    if app < parse_version(gate["recommended_app_version"]):
        return "pass_with_upgrade_hint"
    return "pass"


def main() -> None:
    source = API_SERVER.read_text(encoding="utf-8")

    # 1. Presence + position inside the capabilities response.
    i_auth = source.find('"object": "hermes.api_server.capabilities"')
    i_gate = source.find('"version_gate"')
    i_runtime = source.find('"runtime": {', i_gate)
    check("gate: block present in api_server.py", i_gate > 0)
    check("gate: block sits inside capabilities response",
          0 < i_auth < i_gate < i_runtime)
    check("gate: min default literal 0.50.125 in block",
          '"0.50.125"' in extract_gate_block(source))
    check("gate: recommended default literal 0.51.0 in block",
          '"0.51.0"' in extract_gate_block(source))

    # 2. Shipped defaults, evaluated verbatim.
    gate = eval_gate(source, {})
    check("gate: default min_app_version == 0.50.125",
          gate["min_app_version"] == "0.50.125", repr(gate))
    check("gate: default recommended_app_version == 0.51.0",
          gate["recommended_app_version"] == "0.51.0", repr(gate))
    check("gate: hermes_version wired from _hermes_version()",
          gate["hermes_version"] == "0.23.0-test", repr(gate))

    # 3. Env overrides reach the advertised values.
    gate_env = eval_gate(source, {
        "ONEDAY_MIN_APP_VERSION": "0.51.0",
        "ONEDAY_RECOMMENDED_APP_VERSION": "0.52.0"})
    check("gate: env override min", gate_env["min_app_version"] == "0.51.0",
          repr(gate_env))
    check("gate: env override recommended",
          gate_env["recommended_app_version"] == "0.52.0", repr(gate_env))

    # 4. Gate semantics over the default gate.
    check("semantics: 0.50.124 below min -> blocked",
          gate_decision("0.50.124", gate) == "blocked")
    check("semantics: 0.49.9 below min -> blocked",
          gate_decision("0.49.9", gate) == "blocked")
    check("semantics: 0.50.99 < 0.50.125 numerically -> blocked",
          gate_decision("0.50.99", gate) == "blocked")
    check("semantics: 0.50.125 at min -> pass with upgrade hint",
          gate_decision("0.50.125", gate) == "pass_with_upgrade_hint")
    check("semantics: 0.50.130 between -> pass with upgrade hint",
          gate_decision("0.50.130", gate) == "pass_with_upgrade_hint")
    check("semantics: 0.51.0 at recommended -> pass, no hint",
          gate_decision("0.51.0", gate) == "pass")
    check("semantics: 0.51.1 (current shipped) -> pass, no hint",
          gate_decision("0.51.1", gate) == "pass")

    # 5. Semantics follow env-raised gate.
    check("semantics: raised min blocks 0.50.130",
          gate_decision("0.50.130", gate_env) == "blocked")
    check("semantics: raised recommended hints 0.51.1",
          gate_decision("0.51.1", gate_env) == "pass_with_upgrade_hint")

    print(f"version_gate_selftest: {passed} passed, {failed} failed")
    if failed:
        sys.exit(1)
    print("version_gate_selftest: ALL PASSED")


if __name__ == "__main__":
    main()
