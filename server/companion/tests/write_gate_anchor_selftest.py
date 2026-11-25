#!/usr/bin/env python3
"""Self-test for write_gate_bridge.py approval anchor (§128).

Boots the real bridge module copy against fake Hermes modules plus
a fake state.db (sqlite, sessions/messages) under a fake
HERMES_HOME, and asserts the temporal-correlation tiers from
approval-anchor-spec-20261111.md §3:

- T3 replay: a background_review record anchors to the one session
  whose last activity precedes it (probe/archived/kanban sessions
  in the same window are excluded from the target set).
- T3 tie (two candidate sessions) -> anchor null.
- Probe-only window -> anchor null (exclusion leaves no candidate).
- oneday_app records never anchor (T0).
- T1: the staging tool call (memory/skill_manage message) inside
  exactly one session wins over merely-active sessions.
- T1 tie -> anchor null.
- T2 removed (2026-11-11): a foreground record with a covering
  session but no staging tool call in window anchors null.
- /decisions rows carry the anchor too (decided-row backfill).
- created_at_approx (mtime fallback): windows double and T1 is
  never awarded.
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
KEY = "writegate-anchor-selftest-key"
PORT = 18750
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

T = 1760000000.0  # fixed epoch for the deterministic clusters


def build_state_db(home):
    db = sqlite3.connect(os.path.join(home, "state.db"))
    db.execute("CREATE TABLE sessions (id TEXT, source TEXT,"
               " started_at REAL, ended_at REAL, last_activity_at REAL,"
               " archived INTEGER, hidden INTEGER)")
    db.execute("CREATE TABLE messages (id INTEGER, session_id TEXT,"
               " role TEXT, tool_name TEXT, timestamp REAL)")

    def sess(sid, source, started, ended, last, archived=0):
        db.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?,0)",
                   (sid, source, started, ended, last, archived))

    def msg(sid, ts, tool=None, role="user"):
        db.execute("INSERT INTO messages (session_id, role, tool_name,"
                   " timestamp) VALUES (?,?,?,?)", (sid, role, tool, ts))

    # Cluster @T: T3 replay. Main chat last active T-600; probe at
    # T-300 and an archived session at T-200 must not compete; the
    # kanban session at T-100 is never a target.
    sess("oneday-side-aaaa", "api_server", T - 10000, None, T - 600)
    sess("oneday-side-old0", "api_server", T - 20000, T - 15000, T - 15000)
    sess("oneday-probe-xyz", "api_server", T - 5000, None, T - 300)
    sess("oneday-side-arch", "api_server", T - 9000, None, T - 200,
         archived=1)
    sess("kanban-worker-1", "kanban", T - 5000, None, T - 100)
    msg("oneday-side-aaaa", T - 600)
    msg("oneday-probe-xyz", T - 300)
    msg("oneday-side-old0", T - 15000)

    # Cluster @T+100000: T3 tie (identical last-message times) -> null.
    t2 = T + 100000
    sess("oneday-side-d111", "api_server", t2 - 9000, None, t2 - 500)
    sess("oneday-side-d222", "api_server", t2 - 9000, None, t2 - 700)
    msg("oneday-side-d111", t2 - 500)
    msg("oneday-side-d222", t2 - 500)

    # Cluster @T+150000: T3 concurrency guard — two target sessions
    # both active within ±120s of the staged moment -> null, even
    # though one is strictly more recent.
    tc = T + 150000
    sess("oneday-side-e111", "api_server", tc - 9000, None, tc - 30)
    sess("oneday-side-e222", "api_server", tc - 9000, None, tc - 10)
    msg("oneday-side-e111", tc - 30)
    msg("oneday-side-e222", tc - 10)

    # Cluster @T+200000: only a probe session in the window -> null.
    t3 = T + 200000
    sess("oneday-probe-only", "api_server", t3 - 4000, None, t3 - 300)
    msg("oneday-probe-only", t3 - 300)

    # Cluster @T+300000: T1. t111 carries the memory tool call;
    # t222 is merely active nearby.
    t4 = T + 300000
    sess("oneday-side-t111", "api_server", t4 - 1000, None, t4 + 50)
    sess("oneday-side-t222", "api_server", t4 - 1000, None, t4 + 40)
    msg("oneday-side-t111", t4 - 30, tool="memory", role="tool")
    msg("oneday-side-t222", t4 - 10)

    # Cluster @T+400000: T1 tie -> null.
    t5 = T + 400000
    sess("oneday-side-u111", "api_server", t5 - 1000, None, t5 + 50)
    sess("oneday-side-u222", "api_server", t5 - 1000, None, t5 + 40)
    msg("oneday-side-u111", t5 - 20, tool="skill_manage", role="tool")
    msg("oneday-side-u222", t5 - 25, tool="memory", role="tool")

    # Cluster @T+500000: T2-removal regression. One covering
    # session with plain near messages, no staging tool call
    # anywhere near -> null now that T2 is gone.
    t6 = T + 500000
    sess("oneday-side-v111", "api_server", t6 - 1000, None, t6 + 100)
    msg("oneday-side-v111", t6 - 60)

    # Approx cluster @now: last activity 2000s ago — outside the
    # plain 1800s T3 window, inside the doubled 3600s one. A memory
    # tool message sits 30s before now but must NOT earn T1.
    now = time.time()
    sess("oneday-side-now1", "api_server", now - 9000, None, now - 2000)
    msg("oneday-side-now1", now - 30, tool="memory", role="tool")
    db.commit()
    db.close()


def seed_pending(home, sub, pid, origin, created_at):
    d = os.path.join(home, "pending", sub)
    os.makedirs(d, exist_ok=True)
    rec = {"id": pid, "action": "add", "summary": f"seeded {pid}",
           "origin": origin, "payload": {"action": "add"}}
    if created_at is not None:
        rec["created_at"] = created_at
    path = os.path.join(d, pid + ".json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(rec, f)
    if created_at is None:
        os.utime(path, (time.time(), time.time()))


def main():
    stage = tempfile.mkdtemp(prefix="writegate-anchor-")
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

    build_state_db(home)

    seed_pending(home, "skills", "rec-t3", "background_review", T)
    seed_pending(home, "skills", "rec-t3tie", "background_review",
                 T + 100000)
    seed_pending(home, "skills", "rec-t3conc", "background_review",
                 T + 150000)
    seed_pending(home, "skills", "rec-probeonly", "background_review",
                 T + 200000)
    seed_pending(home, "memory", "rec-app", "oneday_app", T)
    seed_pending(home, "memory", "rec-t1", "foreground", T + 300000)
    seed_pending(home, "memory", "rec-t1tie", "foreground", T + 400000)
    seed_pending(home, "memory", "rec-t2", "foreground", T + 500000)
    seed_pending(home, "memory", "rec-none", "foreground", T + 900000)
    seed_pending(home, "memory", "rec-approx", "background_review", None)

    # One decided row in the T3 cluster for the /decisions backfill.
    wg = os.path.join(home, "write-gate")
    os.makedirs(wg, exist_ok=True)
    decided = {
        "id": "dec-t3", "subsystem": "skills", "action": "edit",
        "summary": "seeded decided", "origin": "background_review",
        "created_at": datetime.fromtimestamp(
            T, tz=timezone.utc).isoformat(),
        "decided_at": datetime.fromtimestamp(
            T + 60, tz=timezone.utc).isoformat(),
        "decision": "approved",
    }
    with open(os.path.join(wg, "decisions.jsonl"), "w",
              encoding="utf-8") as f:
        f.write(json.dumps(decided) + "\n")

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
        check("bridge boots with fake hermes modules + state.db", up)
        if not up:
            return 1

        status, data = call("GET", "/pending")
        by_id = {r["id"]: r for r in data.get("records", [])}
        check("pending read ok, all seeded records present",
              status == 200 and len(by_id) == 10, f"ids={sorted(by_id)}")

        a = by_id.get("rec-t3", {}).get("anchor")
        check("T3 replay anchors to the reviewed session",
              a == {"sessionId": "oneday-side-aaaa", "tier": "T3"},
              f"anchor={a}")
        a = by_id.get("rec-t3tie", {}).get("anchor")
        check("T3 tie -> anchor null", a is None, f"anchor={a}")
        a = by_id.get("rec-t3conc", {}).get("anchor")
        check("T3 concurrency guard -> anchor null", a is None,
              f"anchor={a}")
        a = by_id.get("rec-probeonly", {}).get("anchor")
        check("probe-only window -> anchor null", a is None,
              f"anchor={a}")
        a = by_id.get("rec-app", {}).get("anchor")
        check("oneday_app never anchors (T0)", a is None, f"anchor={a}")
        a = by_id.get("rec-t1", {}).get("anchor")
        check("T1 anchors to the session with the tool call",
              a == {"sessionId": "oneday-side-t111", "tier": "T1"},
              f"anchor={a}")
        a = by_id.get("rec-t1tie", {}).get("anchor")
        check("T1 tie -> anchor null", a is None, f"anchor={a}")
        a = by_id.get("rec-t2", {}).get("anchor")
        check("foreground without tool call -> null (T2 removed)",
              a is None, f"anchor={a}")
        rec_none = by_id.get("rec-none", {})
        check("no activity anywhere -> anchor key present, null",
              "anchor" in rec_none and rec_none.get("anchor") is None,
              f"rec={rec_none}")
        rec_apx = by_id.get("rec-approx", {})
        a = rec_apx.get("anchor")
        check("approx record: doubled T3 window hits, T1 capped",
              rec_apx.get("created_at_approx") is True
              and a == {"sessionId": "oneday-side-now1", "tier": "T3"},
              f"rec={rec_apx}")

        status, data = call("GET", "/decisions")
        rows = data.get("decisions", [])
        dec = [r for r in rows if r.get("id") == "dec-t3"]
        check("decisions row carries backfilled T3 anchor",
              len(dec) == 1
              and dec[0].get("anchor") == {
                  "sessionId": "oneday-side-aaaa", "tier": "T3"},
              f"rows={rows}")
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

    print(f"write_gate_anchor_selftest: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
