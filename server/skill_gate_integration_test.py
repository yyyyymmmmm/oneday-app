#!/usr/bin/env python3
"""End-to-end integration test for the skill admission hard gate
(DESIGN section 444).

Copies the upstream Hermes source (official inventory snapshot) into
a temp tree, installs the gate module into tools/, applies the
SHIPPED hook diff (patches/skill_manager_tool.gate-hook.diff) to the
copied skill_manager_tool.py with patch(1), then drives the real
``skill_manage`` entry point against a stub HERMES_HOME:

- a clean create lands on disk and is ledgered ``admitted``;
- a create carrying a credential literal is refused by the gate and
  leaves no skill directory behind;
- a syntax-broken write_file is refused, the file never appears;
- a frontmatter-breaking patch is refused and the previous admitted
  SKILL.md stays byte-identical.

Run: python3 skill_gate_integration_test.py   (exit 0 = all passed)
Env: SKILL_GATE_UPSTREAM_REPO overrides the snapshot location;
     SKILL_GATE_TEST_DEPS adds PYTHONPATH entries for the driver
     (e.g. a ruamel.yaml install, needed by hermes_yaml).
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PKG = Path(__file__).resolve().parent
REPO = Path(os.environ.get(
    "SKILL_GATE_UPSTREAM_REPO",
    Path.home() / "workspace" / "research_notes"
    / "hermes-official-inventory-20261122" / "repo"))
GATE_MODULE = PKG / "patches" / "skill_admission_gate.py"
HOOK_DIFF = PKG / "patches" / "skill_manager_tool.gate-hook.diff"

CHECKS = []


def check(name, cond, detail=""):
    CHECKS.append((name, bool(cond)))
    print(("PASS " if cond else "FAIL ") + name
          + ((" -- " + str(detail)) if detail and not cond else ""))


GOOD_MD = """---
name: gate-demo
description: Gate demo skill.
---

# Gate demo

Plain instructions, no external files.
"""

LEAK_MD = """---
name: gate-bad
description: Gate bad skill.
---

# Gate bad

```python
api_key = "sk-a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
```
"""

DRIVER = r'''
import json
from tools import skill_manager_tool as sm


def call(**kw):
    out = json.loads(sm.skill_manage(**kw))
    if out.get("staged"):
        from tools import write_approval as wa
        pend = wa.list_pending(wa.SKILLS)
        out = json.loads(sm.apply_skill_pending(pend[-1]["payload"]))
    return out


results = {}
results["create_good"] = call(
    action="create", name="gate-demo", content=%(good)r)
results["create_leak"] = call(
    action="create", name="gate-bad", content=%(leak)r)
results["write_bad_py"] = call(
    action="write_file", name="gate-demo",
    file_path="scripts/bad.py", file_content="def broken(:\n    pass\n")
results["patch_break"] = call(
    action="patch", name="gate-demo",
    old_string="description: Gate demo skill.",
    new_string="title: No description anymore")
print("RESULTS " + json.dumps(results))
'''


def main() -> int:
    if not (REPO / "tools" / "skill_manager_tool.py").is_file():
        check("upstream snapshot present", False, REPO)
        return 1
    tmp = Path(tempfile.mkdtemp(prefix="skillgate-int-"))
    tree = tmp / "tree"
    tree.mkdir()
    for name in ("tools", "agent", "hermes_cli"):
        shutil.copytree(REPO / name, tree / name,
                        ignore=shutil.ignore_patterns("__pycache__"))
    for py in REPO.glob("*.py"):
        shutil.copy2(py, tree / py.name)
    shutil.copy2(GATE_MODULE, tree / "tools" / "skill_admission_gate.py")

    proc = subprocess.run(
        ["patch", "-p1", "-d", str(tree), "-i", str(HOOK_DIFF)],
        capture_output=True, text=True)
    check("shipped hook diff applies cleanly to the upstream snapshot",
          proc.returncode == 0, proc.stdout + proc.stderr)
    hooked = (tree / "tools" / "skill_manager_tool.py").read_text(
        encoding="utf-8")
    check("hook present in patched file",
          "skill_admission_gate import admission_check" in hooked
          or "from tools.skill_admission_gate import admission_check"
          in hooked)

    home = tmp / "home"
    home.mkdir()
    env = dict(os.environ)
    env["HERMES_HOME"] = str(home)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    deps = os.environ.get("SKILL_GATE_TEST_DEPS", "")
    env["PYTHONPATH"] = os.pathsep.join(
        [d for d in (deps, str(tree)) if d])
    driver = DRIVER % {"good": GOOD_MD, "leak": LEAK_MD}
    proc = subprocess.run(
        [sys.executable, "-c", driver], cwd=str(tree), env=env,
        capture_output=True, text=True, timeout=300)
    line = next((l for l in proc.stdout.splitlines()
                 if l.startswith("RESULTS ")), "")
    check("driver ran end-to-end", bool(line),
          (proc.stdout + proc.stderr)[-1500:])
    if not line:
        return 1
    results = json.loads(line[len("RESULTS "):])

    skill_dir = home / "skills" / "gate-demo"
    check("clean create succeeded through the real tool",
          results["create_good"].get("success") is True,
          results["create_good"])
    check("clean create landed on disk",
          (skill_dir / "SKILL.md").is_file())
    check("credential create refused by the gate",
          results["create_leak"].get("success") is not True
          and "admission gate" in json.dumps(results["create_leak"]),
          results["create_leak"])
    check("refused create left no skill directory",
          not (home / "skills" / "gate-bad").exists())
    check("syntax-broken write_file refused",
          results["write_bad_py"].get("success") is not True
          and "syntax" in json.dumps(results["write_bad_py"]),
          results["write_bad_py"])
    check("refused file never appeared",
          not (skill_dir / "scripts" / "bad.py").exists())
    check("frontmatter-breaking patch refused",
          results["patch_break"].get("success") is not True,
          results["patch_break"])
    check("previous admitted SKILL.md byte-identical",
          (skill_dir / "SKILL.md").read_text(encoding="utf-8") == GOOD_MD)

    ledger = (home / "memories" / "oneday" / "admission"
              / "skill_admission.jsonl")
    rows = [json.loads(l) for l in
            ledger.read_text(encoding="utf-8").splitlines() if l.strip()] \
        if ledger.is_file() else []
    statuses = {(r.get("skill"), r.get("status")) for r in rows}
    check("ledger holds the admitted create",
          ("gate-demo", "admitted") in statuses, statuses)
    check("ledger holds the rejected decisions",
          ("gate-bad", "rejected") in statuses
          and ("gate-demo", "rejected") in statuses, statuses)
    check("ledger rows name the actor",
          all(r.get("created_by") == "agent" for r in rows), rows)

    failed = [n for n, ok in CHECKS if not ok]
    print("\n%d checks, %d passed, %d failed"
          % (len(CHECKS), len(CHECKS) - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
