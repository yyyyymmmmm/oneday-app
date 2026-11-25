#!/usr/bin/env python3
"""Self-test for write_gate_bridge.py reason surfaces:
the pre-check reason on skills create records, the execution
reason on failed decides, and the decide-attempts.jsonl trace
(1.0.29 additions; B-05 convergence in 1.0.63 merged the former
blocked_reason / failure_reason pair into the single `reason`
field + `reason_phase` tag asserted below).

Boots the real bridge module copy against fake Hermes modules.
The fake skill_manager_tool mirrors the upstream contract the
pre-check relies on (pure validators; description budget of 60
chars on the skill index). The fake CLI replays approve for one
seeded record as a deterministic upstream failure (record kept,
'Failed:' output) and for the other as success (record removed).
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "write_gate_bridge.py")
KEY = "writegate-blocked-selftest-key"
PORT = 18751
BASE = f"http://127.0.0.1:{PORT}"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def call(method, path, body=None, key=KEY):
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if key:
        headers["Authorization"] = f"Bearer {key}"
    req = urllib.request.Request(BASE + path, data=data, headers=headers,
                                 method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            return e.code, json.loads(raw) if raw else {}
        except Exception:
            return e.code, {}
    except urllib.error.URLError:
        return 0, {}


FAKE_CONSTANTS = '''
import os
def get_hermes_home():
    return os.environ["FAKE_HERMES_HOME"]
'''

FAKE_WA = '''
import json, os
from pathlib import Path
MEMORY = "memory"
SKILLS = "skills"

def _dir(sub):
    d = Path(os.environ["FAKE_HERMES_HOME"]) / "pending" / sub
    d.mkdir(parents=True, exist_ok=True)
    return d

def _pending_path(sub, pid):
    return _dir(sub) / (pid + ".json")

def write_approval_enabled(sub):
    return True

def list_pending(sub):
    out = []
    for p in sorted(_dir(sub).glob("*.json")):
        out.append(json.loads(p.read_text(encoding="utf-8")))
    return out

def get_pending(sub, pid):
    p = _pending_path(sub, pid)
    if not p.exists():
        return None
    return json.loads(p.read_text(encoding="utf-8"))

def pending_count(sub):
    return len(list_pending(sub))

def skill_pending_diff(rec):
    return ""

def _staged_base(name, target, sub):
    return ""

def _fold_patch(current, old, new, replace_all):
    return current, None
'''

FAKE_MEMORY_TOOL = '''
def load_on_disk_store():
    return object()

def get_memory_dir():
    import os
    from pathlib import Path
    d = Path(os.environ["FAKE_HERMES_HOME"]) / "memories"
    d.mkdir(parents=True, exist_ok=True)
    return d
'''

FAKE_SM = '''
import re

def _validate_name(name):
    return None

def _validate_category(category):
    return None

def _validate_frontmatter(content):
    return None

def _validate_content_size(content, label="SKILL.md"):
    return None

def _description_budget_error(content, before=None):
    m = re.search(r'description:\\s*"([^"]*)"', content)
    desc = m.group(1) if m else ""
    if len(desc) > 60:
        return (f"Description is {len(desc)} chars; a skill description "
                "must fit the 60-char skill index.")
    return None

def _find_skill(name):
    return None
'''

FAKE_CLI = '''
import os
from pathlib import Path

def handle_pending_subcommand(sub, args, memory_store=None):
    action, pid = args[0], args[1]
    if pid == "deadbeef":
        # deterministic upstream replay failure: record is kept
        return ("Approved 0 skills write(s).\\nFailed:\\n"
                "  deadbeef: Description is 82 chars; a skill "
                "description must fit the 60-char skill index.")
    p = Path(os.environ["FAKE_HERMES_HOME"]) / "pending" / sub / (pid + ".json")
    if p.exists():
        p.unlink()
    return f"Approved 1 {sub} write(s)."
'''


def skill_content(desc):
    return ("---\nname: seeded-skill\n"
            f'description: "{desc}"\n'
            "---\n\n# Seeded\nbody\n")


def seed(home, pid, desc):
    d = os.path.join(home, "pending", "skills")
    os.makedirs(d, exist_ok=True)
    rec = {
        "id": pid,
        "subsystem": "skills",
        "action": "batch",
        "summary": "batch(1 ops: create) on seeded-skill",
        "origin": "background_review",
        "created_at": 1760000000.0,
        "payload": {
            "action": "batch",
            "operations": [{
                "action": "create",
                "name": "seeded-skill",
                "category": "research",
                "content": skill_content(desc),
            }],
        },
    }
    with open(os.path.join(d, pid + ".json"), "w", encoding="utf-8") as f:
        json.dump(rec, f)


def main():
    stage = tempfile.mkdtemp(prefix="writegate-blocked-")
    home = os.path.join(stage, "hermes-home")
    os.makedirs(home)
    shutil.copy(BRIDGE, os.path.join(stage, "write_gate_bridge.py"))
    with open(os.path.join(stage, "hermes_constants.py"), "w") as f:
        f.write(FAKE_CONSTANTS)
    os.makedirs(os.path.join(stage, "tools"))
    with open(os.path.join(stage, "tools", "__init__.py"), "w") as f:
        f.write("")
    with open(os.path.join(stage, "tools", "write_approval.py"), "w") as f:
        f.write(FAKE_WA)
    with open(os.path.join(stage, "tools", "memory_tool.py"), "w") as f:
        f.write(FAKE_MEMORY_TOOL)
    with open(os.path.join(stage, "tools", "skill_manager_tool.py"), "w") as f:
        f.write(FAKE_SM)
    os.makedirs(os.path.join(stage, "hermes_cli"))
    with open(os.path.join(stage, "hermes_cli", "__init__.py"), "w") as f:
        f.write("")
    with open(os.path.join(stage, "hermes_cli",
                           "write_approval_commands.py"), "w") as f:
        f.write(FAKE_CLI)

    seed(home, "deadbeef", "x" * 82)
    seed(home, "good0001", "Short and valid.")

    env = dict(os.environ)
    env["WRITE_GATE_BRIDGE_KEY"] = KEY
    env["WRITE_GATE_PORT"] = str(PORT)
    env["FAKE_HERMES_HOME"] = home
    env["PYTHONPATH"] = stage
    proc = subprocess.Popen(
        [sys.executable, os.path.join(stage, "write_gate_bridge.py")],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True)
    try:
        deadline = time.time() + 20
        up = False
        while time.time() < deadline:
            status, _ = call("GET", "/status")
            if status == 200:
                up = True
                break
            time.sleep(0.3)
        check("bridge boots", up)
        if not up:
            print(proc.stdout.read() if proc.stdout else "")
            return 1

        status, data = call("GET", "/pending")
        recs = {r["id"]: r for r in data.get("records", [])}
        check("list: dead record carries reason (pre-check phase)",
              "82 chars" in (recs.get("deadbeef", {}).get("reason") or "")
              and recs.get("deadbeef", {}).get("reason_phase") == "pre-check",
              f"got {recs.get('deadbeef')}")
        check("list: legacy blocked_reason field is gone",
              "blocked_reason" not in recs.get("deadbeef", {}),
              f"got {recs.get('deadbeef')}")
        check("list: healthy record has no reason",
              "reason" not in recs.get("good0001", {}),
              f"got {recs.get('good0001')}")

        status, data = call("GET", "/pending/skills/deadbeef")
        check("detail: reason present (pre-check phase)",
              "82 chars" in ((data.get("record") or {}).get("reason") or "")
              and (data.get("record") or {}).get("reason_phase") == "pre-check",
              f"got {data}")

        status, data = call("POST", "/pending/skills/deadbeef/approve")
        check("failed decide: http 200 + success false",
              status == 200 and data.get("success") is False, f"got {data}")
        check("failed decide: reason parsed (execution phase)",
              "Description is 82 chars" in (data.get("reason") or "")
              and data.get("reason_phase") == "execution",
              f"got {data}")
        check("failed decide: legacy failure_reason field is gone",
              "failure_reason" not in data, f"got {data}")

        attempts_path = os.path.join(home, "write-gate", "decide-attempts.jsonl")
        attempts = []
        if os.path.exists(attempts_path):
            attempts = [json.loads(l) for l in
                        open(attempts_path, encoding="utf-8") if l.strip()]
        check("failed decide: attempt logged",
              len(attempts) == 1 and attempts[0]["id"] == "deadbeef"
              and attempts[0]["result"] == "failed"
              and "82 chars" in (attempts[0]["reason"] or "")
              and attempts[0].get("reason_phase") == "execution",
              f"got {attempts}")

        status, data = call("POST", "/pending/skills/good0001/approve")
        check("good decide: success true, no reason",
              status == 200 and data.get("success") is True
              and "reason" not in data, f"got {data}")
        attempts = [json.loads(l) for l in
                    open(attempts_path, encoding="utf-8") if l.strip()]
        check("good decide: no extra attempt row", len(attempts) == 1,
              f"got {attempts}")
        decisions = [json.loads(l) for l in open(
            os.path.join(home, "write-gate", "decisions.jsonl"),
            encoding="utf-8") if l.strip()]
        check("good decide: decisions ledger has the approval only",
              len(decisions) == 1 and decisions[0]["id"] == "good0001",
              f"got {decisions}")

        status, data = call("GET", "/status")
        check("counts: dead record still pending (1)",
              data.get("counts", {}).get("skills") == 1, f"got {data}")
    finally:
        proc.terminate()
        shutil.rmtree(stage, ignore_errors=True)
    print(f"RESULT write_gate_blocked_selftest: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
