#!/usr/bin/env python3
"""Selftest for the OneDay skill admission hard gate (DESIGN section 444).

Exercises the gate module (patches/skill_admission_gate.py) against a
stub HERMES_HOME: a good skill is admitted and ledgered in the
section-439 format; bad skills (Python syntax error, dangling
reference on a non-create write, credential literal, frontmatter
name mismatch, unregistered declared tool) are rejected with the
on-disk tree untouched; a patch that would break a healthy skill is
rejected with the previous version byte-identical; a validator fault
and an unwritable ledger both refuse the write (fail-closed); the
user-only exemption channel and the user-owned kill switch behave
as specified.

Run: python3 skill_gate_selftest.py   (exit 0 = all passed)
"""

import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path

PKG = Path(__file__).resolve().parent
MODULE_PATH = PKG / "patches" / "skill_admission_gate.py"

CHECKS = []


def check(name, cond, detail=""):
    CHECKS.append((name, bool(cond)))
    print(("PASS " if cond else "FAIL ") + name
          + ((" -- " + str(detail)) if detail and not cond else ""))


GOOD_MD = """---
name: demo-skill
description: Demo skill used by the gate selftest.
---

# Demo

See [the guide](references/guide.md) and run `scripts/run.py`.
"""

GOOD_PY = "import os\n\n\ndef main():\n    return os.environ.get('DEMO_KEY')\n"

FAKE_SECRET = "sk-" + "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"


def load_gate():
    spec = importlib.util.spec_from_file_location(
        "skill_admission_gate", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def ledger_rows(home: Path):
    path = home / "memories" / "oneday" / "admission" / "skill_admission.jsonl"
    if not path.is_file():
        return []
    return [json.loads(line) for line in
            path.read_text(encoding="utf-8").splitlines() if line.strip()]


def last_row(home: Path, status=None):
    rows = ledger_rows(home)
    if status:
        rows = [r for r in rows if r.get("status") == status]
    return rows[-1] if rows else None


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="skillgate-stub-"))
    home = tmp / "data"
    home.mkdir(parents=True)
    os.environ["HERMES_HOME"] = str(home)
    os.environ.pop("ONEDAY_MEMORY_ROOT", None)
    os.environ.pop("SKILL_GATE_CONFIG", None)
    gate = load_gate()

    skills_root = home / "skills"
    skill_dir = skills_root / "demo-skill"
    skill_dir.mkdir(parents=True)

    def call(action, target_rel, content, name="demo-skill", **kw):
        return gate.admission_check(name, skill_dir, skill_dir / target_rel,
                                    action, content, **kw)

    # ---- 1. good create: admitted, ledgered in section-439 format ----
    err = call("create", "SKILL.md", GOOD_MD)
    check("good create admitted", err is None, err)
    row = last_row(home, "admitted")
    check("admitted row in ledger", row is not None)
    check("ledger row format (skill/created_by/verify/status/first)",
          row and row.get("skill") == "demo-skill"
          and row.get("created_by") == "agent"
          and (row.get("verify") or {}).get("method")
          == "skill_gate:pre_write_suite"
          and bool((row.get("verify") or {}).get("evidence"))
          and bool(row.get("first")))
    evidence = home / "memories" / (row or {}).get("verify", {}).get("evidence", "")
    check("evidence report exists on disk", evidence.is_file(), evidence)
    report = json.loads(evidence.read_text(encoding="utf-8")) \
        if evidence.is_file() else {}
    check("report: all five checks ok",
          report.get("ok") is True
          and set(report.get("checks", {}))
          == {"structure", "frontmatter", "syntax", "references",
              "credentials"})
    check("create-time dangling refs recorded as notes, not failures",
          any("guide.md" in n for n in
              report.get("checks", {}).get("references", {}).get("notes", [])))

    # ---- simulate the create landing, then complete the tree ----
    (skill_dir / "SKILL.md").write_text(GOOD_MD, encoding="utf-8")
    (skill_dir / "references").mkdir()
    (skill_dir / "references" / "guide.md").write_text("# Guide\n",
                                                       encoding="utf-8")
    err = call("write_file", "scripts/run.py", GOOD_PY)
    check("good write_file admitted (env lookup is not a credential)",
          err is None, err)
    (skill_dir / "scripts").mkdir(exist_ok=True)
    (skill_dir / "scripts" / "run.py").write_text(GOOD_PY, encoding="utf-8")

    # ---- 2. bad skill: Python syntax error rejected, disk untouched ----
    before = (skill_dir / "SKILL.md").read_bytes()
    err = call("write_file", "scripts/bad.py", "def broken(:\n    pass\n")
    check("syntax-error write rejected", err is not None
          and "syntax" in err, err)
    check("rejected row ledgered",
          (last_row(home, "rejected") or {}).get("skill") == "demo-skill")
    check("disk untouched by rejected write",
          not (skill_dir / "scripts" / "bad.py").exists()
          and (skill_dir / "SKILL.md").read_bytes() == before)

    # ---- 3. bad skill: credential literal rejected ----
    err = call("write_file", "scripts/leak.py",
               'api_key = "%s"\n' % FAKE_SECRET)
    check("credential literal rejected", err is not None
          and "credentials" in err, err)
    rep_row = last_row(home, "rejected")
    rep_path = home / "memories" / (rep_row or {}).get("verify", {}).get("evidence", "")
    rep_text = rep_path.read_text(encoding="utf-8") if rep_path.is_file() else ""
    check("report never echoes the secret itself",
          FAKE_SECRET not in rep_text and FAKE_SECRET
          not in (home / "memories" / "oneday" / "admission"
                  / "skill_admission.jsonl").read_text(encoding="utf-8"))
    err = call("write_file", "scripts/ok.py",
               'import os\nKEY = os.environ["DEMO_KEY"]\n'
               'PLACEHOLDER = "your-api-key-here"\n')
    check("env lookup + placeholder pass the credential check",
          err is None, err)

    # ---- 4. patch that would break the skill: rejected, old version kept ----
    broken_md = GOOD_MD.replace(
        "description: Demo skill used by the gate selftest.\n", "")
    err = call("patch", "SKILL.md", broken_md)
    check("frontmatter-breaking patch rejected", err is not None
          and "frontmatter" in err, err)
    check("previous admitted version byte-identical after rejected patch",
          (skill_dir / "SKILL.md").read_bytes() == before)

    # ---- 5. dangling reference on a non-create write: rejected ----
    err = call("patch", "SKILL.md",
               GOOD_MD + "\nAlso see [missing](references/nope.md).\n")
    check("dangling reference rejected on patch", err is not None
          and "references" in err, err)

    # ---- 6. frontmatter name mismatch: rejected ----
    err = call("edit", "SKILL.md",
               GOOD_MD.replace("name: demo-skill", "name: other-skill"))
    check("frontmatter name mismatch rejected", err is not None
          and "frontmatter" in err, err)

    # ---- 7. declared tools: registry enforced when provided ----
    tools_md = GOOD_MD.replace(
        "description: Demo skill used by the gate selftest.",
        "description: Demo skill used by the gate selftest.\n"
        "tools: [terminal, bogus_tool]")
    err = call("edit", "SKILL.md", tools_md, known_tools={"terminal"})
    check("undeclared tool rejected when registry provided",
          err is not None and "references" in err, err)
    err = call("edit", "SKILL.md", tools_md)
    check("tool check skipped (recorded) without a registry",
          err is None, err)

    # ---- 8. validator fault: fail-closed refusal + gate_error row ----
    original_validate = gate.validate_tree
    gate.validate_tree = lambda *a, **k: (_ for _ in ()).throw(
        RuntimeError("boom"))
    try:
        err = call("patch", "SKILL.md", GOOD_MD)
    finally:
        gate.validate_tree = original_validate
    check("validator fault refuses the write (fail-closed)",
          err is not None and "fail-closed" in err, err)
    check("gate_error row ledgered",
          (last_row(home, "gate_error") or {}).get("skill") == "demo-skill")
    check("disk untouched by faulted write",
          (skill_dir / "SKILL.md").read_bytes() == before)

    # ---- 9. exemption channel: user-only, default off ----
    cfg_path = home / "skill_gate.json"
    cfg_path.write_text(json.dumps(
        {"exemptions": {"demo-skill": {"approved_by": "agent"}}}),
        encoding="utf-8")
    err = call("write_file", "scripts/bad2.py", "def broken(:\n")
    check("agent-granted exemption is NOT honored",
          err is not None and "syntax" in err, err)
    cfg_path.write_text(json.dumps(
        {"exemptions": {"demo-skill": {"approved_by": "user",
                                       "at": "2026-11-24T00:00:00Z"}}}),
        encoding="utf-8")
    err = call("write_file", "scripts/bad2.py", "def broken(:\n")
    check("user-granted exemption admits without the suite",
          err is None, err)
    check("exempted row ledgered",
          (last_row(home, "exempted") or {}).get("skill") == "demo-skill")
    cfg_path.unlink()

    # ---- 10. kill switch: user-owned config disables, still ledgered ----
    cfg_path.write_text(json.dumps({"enabled": False}), encoding="utf-8")
    err = call("write_file", "scripts/bad3.py", "def broken(:\n")
    check("kill switch lets the write through", err is None, err)
    row = last_row(home, "gate_disabled")
    check("gate_disabled row ledgered with empty evidence",
          row is not None
          and (row.get("verify") or {}).get("evidence") == "")
    cfg_path.unlink()

    # ---- 11. unwritable ledger on a clean pass: fail-closed ----
    ledger = home / "memories" / "oneday" / "admission" / "skill_admission.jsonl"
    saved = ledger.read_bytes()
    ledger.unlink()
    ledger.mkdir()
    try:
        err = call("write_file", "scripts/ok2.py", "X = 1\n")
    finally:
        ledger.rmdir()
        ledger.write_bytes(saved)
    check("unwritable ledger refuses an otherwise clean write",
          err is not None and "fail-closed" in err, err)

    failed = [n for n, ok in CHECKS if not ok]
    print("\n%d checks, %d passed, %d failed"
          % (len(CHECKS), len(CHECKS) - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
