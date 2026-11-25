#!/usr/bin/env python3
"""Self-test for the write-gate anchor write-once ledger (C-5).

Boots the real bridge module copy against fake Hermes modules plus
a fake state.db and asserts the convergence contract:

- First export computes the anchor (T3) and persists it into
  write-gate/anchors.json.
- After the correlation inputs MOVE (a competing session becomes
  strictly more recent — a fresh computation would flip the
  winner), the export still serves the frozen anchor.
- The /decisions row for the same record serves the same frozen
  anchor.
- oneday_app verdicts freeze as null (deterministic T0).
- A verdict reached while state.db is ABSENT (no evidence) is not
  persisted: once the db appears, the record still earns its
  anchor.
"""
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "write_gate_bridge.py")
KEY = "writegate-anchor-ledger-selftest-key"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def call(base, method, path, body=None):
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    headers["Authorization"] = f"Bearer {KEY}"
    req = urllib.request.Request(base + path, data=data, headers=headers,
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

T = 1760000000.0  # fixed epoch for the deterministic clusters


def stage_bridge(stage):
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


def boot(stage, home, port):
    env = dict(os.environ)
    env["WRITE_GATE_BRIDGE_KEY"] = KEY
    env["WRITE_GATE_PORT"] = str(port)
    env["FAKE_HERMES_HOME"] = home
    env["PYTHONPATH"] = stage
    proc = subprocess.Popen(
        [sys.executable, os.path.join(stage, "write_gate_bridge.py")],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True)
    base = f"http://127.0.0.1:{port}"
    deadline = time.time() + 20
    while time.time() < deadline:
        status, _ = call(base, "GET", "/status")
        if status == 200:
            return proc, base
        time.sleep(0.3)
    return proc, base


def seed_pending(home, sub, pid, origin, created_at):
    d = os.path.join(home, "pending", sub)
    os.makedirs(d, exist_ok=True)
    rec = {"id": pid, "action": "add", "summary": f"seeded {pid}",
           "origin": origin, "payload": {"action": "add"},
           "created_at": created_at}
    with open(os.path.join(d, pid + ".json"), "w", encoding="utf-8") as f:
        json.dump(rec, f)


def read_ledger(home):
    p = os.path.join(home, "write-gate", "anchors.json")
    if not os.path.exists(p):
        return None
    with open(p, encoding="utf-8") as f:
        return json.load(f).get("anchors", {})


def scenario_frozen():
    stage = tempfile.mkdtemp(prefix="writegate-ledger-")
    home = os.path.join(stage, "hermes-home")
    os.makedirs(home)
    stage_bridge(stage)

    db = sqlite3.connect(os.path.join(home, "state.db"))
    db.execute("CREATE TABLE sessions (id TEXT, source TEXT,"
               " started_at REAL, ended_at REAL, last_activity_at REAL,"
               " archived INTEGER, hidden INTEGER)")
    db.execute("CREATE TABLE messages (id INTEGER, session_id TEXT,"
               " role TEXT, tool_name TEXT, timestamp REAL)")
    db.execute("INSERT INTO sessions (id, source, started_at," " ended_at, last_activity_at, archived, hidden)" " VALUES (?,?,?,?,?,0,0)",
               ("oneday-side-aaaa", "api_server", T - 10000, None, T - 600))
    db.execute("INSERT INTO messages (session_id, role, tool_name,"
               " timestamp) VALUES (?,?,?,?)",
               ("oneday-side-aaaa", "user", None, T - 600))
    db.commit()
    db.close()

    seed_pending(home, "skills", "led-t3", "background_review", T)
    seed_pending(home, "memory", "led-app", "oneday_app", T)

    proc, base = boot(stage, home, 18751)
    try:
        status, data = call(base, "GET", "/pending")
        by_id = {r["id"]: r for r in data.get("records", [])}
        a = by_id.get("led-t3", {}).get("anchor") or {}
        check("first export computes T3 anchor",
              status == 200 and a.get("sessionId") == "oneday-side-aaaa"
              and a.get("tier") == "T3", f"anchor={a}")
        check("oneday_app anchor is null on first export",
              by_id.get("led-app", {}).get("anchor") is None)

        ledger = read_ledger(home)
        check("verdicts persisted to anchors.json",
              ledger is not None
              and (ledger.get("skills:led-t3") or {}).get("sessionId")
              == "oneday-side-aaaa"
              and "memory:led-app" in ledger
              and ledger.get("memory:led-app") is None,
              f"ledger={ledger}")

        # Move the world: a competing session becomes strictly more
        # recent than aaaa (fresh computation would flip to bbbb).
        db = sqlite3.connect(os.path.join(home, "state.db"))
        db.execute("INSERT INTO sessions (id, source, started_at," " ended_at, last_activity_at, archived, hidden)" " VALUES (?,?,?,?,?,0,0)",
                   ("oneday-side-bbbb", "api_server", T - 9000, None,
                    T - 60))
        db.execute("INSERT INTO messages (session_id, role, tool_name,"
                   " timestamp) VALUES (?,?,?,?)",
                   ("oneday-side-bbbb", "user", None, T - 60))
        db.commit()
        db.close()

        status, data = call(base, "GET", "/pending")
        by_id = {r["id"]: r for r in data.get("records", [])}
        a2 = by_id.get("led-t3", {}).get("anchor") or {}
        check("second export serves the frozen anchor, not the flip",
              a2.get("sessionId") == "oneday-side-aaaa",
              f"anchor={a2}")

        status, _ = call(base, "POST", "/pending/skills/led-t3/approve")
        check("decide succeeds", status == 200)
        status, data = call(base, "GET", "/decisions?limit=10")
        rows = {r["id"]: r for r in data.get("decisions", [])}
        a3 = rows.get("led-t3", {}).get("anchor") or {}
        check("decisions row serves the same frozen anchor",
              a3.get("sessionId") == "oneday-side-aaaa",
              f"anchor={a3}")
    finally:
        proc.terminate()


def scenario_no_evidence_not_frozen():
    stage = tempfile.mkdtemp(prefix="writegate-ledger-nodb-")
    home = os.path.join(stage, "hermes-home")
    os.makedirs(home)
    stage_bridge(stage)
    # No state.db at boot: the resolver has no evidence.
    seed_pending(home, "memory", "led-nodb", "background_review", T)

    proc, base = boot(stage, home, 18752)
    try:
        status, data = call(base, "GET", "/pending")
        by_id = {r["id"]: r for r in data.get("records", [])}
        check("no-db export yields null anchor",
              status == 200
              and by_id.get("led-nodb", {}).get("anchor") is None)
        ledger = read_ledger(home) or {}
        check("no-evidence null is NOT persisted",
              "memory:led-nodb" not in ledger, f"ledger={ledger}")

        # Evidence arrives: a staging tool call in one session.
        db = sqlite3.connect(os.path.join(home, "state.db"))
        db.execute("CREATE TABLE sessions (id TEXT, source TEXT,"
                   " started_at REAL, ended_at REAL,"
                   " last_activity_at REAL, archived INTEGER,"
                   " hidden INTEGER)")
        db.execute("CREATE TABLE messages (id INTEGER, session_id TEXT,"
                   " role TEXT, tool_name TEXT, timestamp REAL)")
        db.execute("INSERT INTO sessions (id, source, started_at," " ended_at, last_activity_at, archived, hidden)" " VALUES (?,?,?,?,?,0,0)",
                   ("oneday-side-late", "api_server", T - 1000, None,
                    T + 50))
        db.execute("INSERT INTO messages (session_id, role, tool_name,"
                   " timestamp) VALUES (?,?,?,?)",
                   ("oneday-side-late", "tool", "memory", T - 30))
        db.commit()
        db.close()

        status, data = call(base, "GET", "/pending")
        by_id = {r["id"]: r for r in data.get("records", [])}
        a = by_id.get("led-nodb", {}).get("anchor") or {}
        check("record earns its anchor once evidence exists",
              a.get("sessionId") == "oneday-side-late"
              and a.get("tier") == "T1", f"anchor={a}")
        ledger = read_ledger(home) or {}
        check("earned anchor is now persisted",
              (ledger.get("memory:led-nodb") or {}).get("sessionId")
              == "oneday-side-late", f"ledger={ledger}")
    finally:
        proc.terminate()


def main():
    scenario_frozen()
    scenario_no_evidence_not_frozen()
    print(f"anchor-ledger selftest: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
