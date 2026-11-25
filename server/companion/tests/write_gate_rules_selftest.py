#!/usr/bin/env python3
"""Self-test for write_gate_bridge.py always-allow rules (OneDay 0.36.21).

Boots the real bridge module copy against fake Hermes modules
(tools.write_approval backed by JSON files under a fake
HERMES_HOME, hermes_cli.write_approval_commands deleting the
pending file on decide — the same observable contract as upstream).

Covers: rule CRUD + idempotent create, sweep auto-approval on
/pending reads with via_rule in the decision log, non-matching
origin left pending, revocation re-exposing later records, and
auth/validation failures.
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
KEY = "writegate-rules-selftest-key"
PORT = 18749
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

FAKE_CLI = '''
import os
from pathlib import Path

def handle_pending_subcommand(sub, args, memory_store=None):
    action, pid = args[0], args[1]
    p = Path(os.environ["FAKE_HERMES_HOME"]) / "pending" / sub / (pid + ".json")
    if p.exists():
        p.unlink()
    return f"{action} {pid} ok"
'''


def seed_pending(home, sub, pid, origin, action="add"):
    d = os.path.join(home, "pending", sub)
    os.makedirs(d, exist_ok=True)
    rec = {
        "id": pid,
        "action": action,
        "summary": f"seeded {pid}",
        "origin": origin,
        "created_at": 1760000000.0,
        "payload": {"action": action},
    }
    with open(os.path.join(d, pid + ".json"), "w", encoding="utf-8") as f:
        json.dump(rec, f)


def main():
    stage = tempfile.mkdtemp(prefix="writegate-rules-")
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
    os.makedirs(os.path.join(stage, "hermes_cli"))
    with open(os.path.join(stage, "hermes_cli", "__init__.py"), "w") as f:
        f.write("")
    with open(os.path.join(stage, "hermes_cli",
                           "write_approval_commands.py"), "w") as f:
        f.write(FAKE_CLI)

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
        check("bridge boots with fake hermes modules", up)
        if not up:
            return 1

        status, data = call("GET", "/rules", key=None)
        check("rules endpoint requires auth", status == 401, f"got {status}")

        status, data = call("GET", "/rules")
        check("rules start empty", status == 200 and data.get("rules") == [],
              f"got {status} {data}")

        status, data = call("POST", "/rules",
                            {"subsystem": "memory",
                             "origin": "background_review"})
        rule = data.get("rule", {})
        check("create rule -> 201 with rule_ id",
              status == 201 and rule.get("id", "").startswith("rule_")
              and rule.get("subsystem") == "memory"
              and rule.get("origin") == "background_review",
              f"got {status} {data}")
        rule_id = rule.get("id", "")

        status, data = call("POST", "/rules",
                            {"subsystem": "memory",
                             "origin": "background_review"})
        check("create same rule again -> 200 same id (idempotent)",
              status == 200 and data.get("rule", {}).get("id") == rule_id,
              f"got {status} {data}")

        status, data = call("POST", "/rules",
                            {"subsystem": "bogus", "origin": "x"})
        check("create rule with bad subsystem -> 400", status == 400,
              f"got {status}")
        status, data = call("POST", "/rules",
                            {"subsystem": "memory", "origin": "  "})
        check("create rule with blank origin -> 400", status == 400,
              f"got {status}")

        # Matching record is swept on the /pending read and lands in
        # the decision log with via_rule; a non-matching one stays.
        seed_pending(home, "memory", "rec-match", "background_review")
        seed_pending(home, "memory", "rec-other", "foreground")
        status, data = call("GET", "/pending")
        ids = [r["id"] for r in data.get("records", [])]
        check("matching record auto-approved on /pending read",
              status == 200 and "rec-match" not in ids, f"ids={ids}")
        check("non-matching record stays pending",
              "rec-other" in ids, f"ids={ids}")

        status, data = call("GET", "/decisions")
        entries = data.get("decisions", [])
        match = [e for e in entries if e.get("id") == "rec-match"]
        check("decision log marks the auto-approval with via_rule",
              len(match) == 1 and match[0].get("decision") == "approved"
              and match[0].get("via_rule") == rule_id,
              f"entries={entries}")

        # A skills rule sweeps skills records the same way.
        status, data = call("POST", "/rules",
                            {"subsystem": "skills", "origin": "assistant_tool"})
        skill_rule_id = data.get("rule", {}).get("id", "")
        seed_pending(home, "skills", "rec-skill", "assistant_tool",
                     action="edit")
        status, data = call("GET", "/pending")
        ids = [r["id"] for r in data.get("records", [])]
        check("skills rule sweeps skills record",
              "rec-skill" not in ids and "rec-other" in ids, f"ids={ids}")

        # Revocation: after deleting the memory rule, the next
        # same-key record is pending again.
        status, data = call("DELETE", f"/rules/{rule_id}")
        check("delete rule -> 200 success",
              status == 200 and data.get("success") is True,
              f"got {status} {data}")
        status, data = call("DELETE", f"/rules/{rule_id}")
        check("delete same rule again -> 404", status == 404,
              f"got {status}")
        status, data = call("DELETE", "/rules/not-an-id!")
        check("delete rule with malformed id -> 400", status == 400,
              f"got {status}")
        seed_pending(home, "memory", "rec-after-revoke", "background_review")
        status, data = call("GET", "/pending")
        ids = [r["id"] for r in data.get("records", [])]
        check("after revocation same-key record stays pending",
              "rec-after-revoke" in ids, f"ids={ids}")

        status, data = call("GET", "/rules")
        remaining = [r["id"] for r in data.get("rules", [])]
        check("rules list reflects revocation, keeps skills rule",
              remaining == [skill_rule_id], f"remaining={remaining}")

        # Structured headline fields: pending records carry the
        # fields the App builds Chinese titles from (never the
        # raw summary string).
        def seed_full(sub, pid, origin, payload):
            d = os.path.join(home, "pending", sub)
            os.makedirs(d, exist_ok=True)
            rec = {"id": pid, "action": payload.get("action", ""),
                   "summary": "raw english ops string",
                   "origin": origin, "created_at": 1760000000.0,
                   "payload": payload}
            with open(os.path.join(d, pid + ".json"), "w",
                      encoding="utf-8") as f:
                json.dump(rec, f)

        seed_full("skills", "rec-batch", "cli", {
            "action": "batch", "name": "personal-data-insights",
            "ops": [{"action": "patch"}, {"action": "patch"},
                    {"action": "patch"}]})
        seed_full("memory", "rec-mem", "cli", {
            "action": "add", "target": "user",
            "content": "喜欢喝美式咖啡，不加糖"})
        status, data = call("GET", "/pending")
        by_id = {r["id"]: r for r in data.get("records", [])}
        batch = by_id.get("rec-batch", {})
        check("batch record carries target_name/op_count/op_kinds",
              batch.get("target_name") == "personal-data-insights"
              and batch.get("op") == "batch"
              and batch.get("op_count") == 3
              and batch.get("op_kinds") == ["patch", "patch", "patch"],
              f"batch={batch}")
        mem = by_id.get("rec-mem", {})
        check("memory record carries mem_target/content_preview",
              mem.get("mem_target") == "user"
              and mem.get("op") == "add"
              and mem.get("content_preview") == "喜欢喝美式咖啡，不加糖",
              f"mem={mem}")
        status, data = call("POST", "/pending/memory/rec-mem/approve")
        check("approve structured memory record succeeds",
              status == 200 and data.get("success") is True,
              f"got {status} {data}")
        status, data = call("GET", "/decisions")
        entries = [e for e in data.get("decisions", [])
                   if e.get("id") == "rec-mem"]
        check("decision entry carries structured fields too",
              len(entries) == 1
              and entries[0].get("mem_target") == "user"
              and entries[0].get("content_preview") == "喜欢喝美式咖啡，不加糖",
              f"entries={entries}")

        # Manual decide path still works after the refactor.
        status, data = call("POST", "/pending/memory/rec-other/approve")
        check("manual approve still succeeds",
              status == 200 and data.get("success") is True
              and data.get("decision") == "approved",
              f"got {status} {data}")
        status, data = call("GET", "/decisions")
        manual = [e for e in data.get("decisions", [])
                  if e.get("id") == "rec-other"]
        check("manual decision logged without via_rule",
              len(manual) == 1 and "via_rule" not in manual[0],
              f"manual={manual}")
    finally:
        proc.terminate()
        try:
            out, _ = proc.communicate(timeout=5)
        except Exception:
            proc.kill()
            out, _ = proc.communicate()
        if failed:
            print("---- bridge output ----")
            print(out[-3000:])
        shutil.rmtree(stage, ignore_errors=True)

    print(f"write_gate_rules_selftest: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
