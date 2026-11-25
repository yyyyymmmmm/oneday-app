#!/usr/bin/env python3
"""Supervisor self-test: drives a real supervisor subprocess hosting two
dummy modules (one healthy sleeper, one instant crasher) and checks:
startup, kill -9 auto-restart, crash-loop backoff marking, desired-state
persistence across supervisor restart, and clean SIGTERM shutdown."""
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SUP = os.path.join(ROOT, "supervisor", "supervisor.py")
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


def req(method, path, token, body=None):
    r = urllib.request.Request(BASE + path, method=method,
                               data=json.dumps(body).encode() if body is not None else None,
                               headers={"X-Control-Token": token})
    try:
        with urllib.request.urlopen(r, timeout=5) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")
    except Exception:
        return 0, {}


def wait_for(fn, timeout=30, interval=0.4):
    end = time.time() + timeout
    while time.time() < end:
        v = fn()
        if v:
            return v
        time.sleep(interval)
    return None


def main():
    tmp = tempfile.mkdtemp(prefix="companion-sup-")
    state = os.path.join(tmp, "state")
    manifest = {
        "modules": [
            {"id": "dummyOk", "name": "DummyOK", "path": "tests/dummy_ok.py",
             "port": 0, "segment": "global"},
            {"id": "dummyCrash", "name": "DummyCrash", "path": "tests/dummy_crash.py",
             "port": 0, "segment": "global"},
        ]
    }
    mpath = os.path.join(tmp, "modules.json")
    json.dump(manifest, open(mpath, "w"))
    envpath = os.path.join(tmp, "companion.env")
    open(envpath, "w").write("# [global]\nTZ=Asia/Shanghai\n")

    env = dict(os.environ,
               COMPANION_STATE_DIR=state,
               COMPANION_ENV_FILE=envpath,
               COMPANION_MODULES_JSON=mpath,
               COMPANION_CONTROL_PORT=str(PORT),
               COMPANION_PYTHON=sys.executable,
               COMPANION_BACKOFF_BASE_SEC="0.5",
               COMPANION_BACKOFF_CAP_SEC="4",
               COMPANION_CRASH_LOOP_THRESHOLD="5")
    token = None

    def start_supervisor():
        p = subprocess.Popen([sys.executable, SUP], env=env,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True)
        return p

    sup = start_supervisor()
    try:
        token_file = os.path.join(state, "control.token")
        check("control token file created", wait_for(lambda: os.path.exists(token_file), 10))
        token = open(token_file).read().strip()

        st = wait_for(lambda: req("GET", "/status", token)[1]
                      .get("modules", {}).get("dummyOk", {}).get("state") == "running")
        check("dummyOk running after start", bool(st))
        pid1 = req("GET", "/status", token)[1]["modules"]["dummyOk"]["pid"]
        check("dummyOk has pid", isinstance(pid1, int))

        st = wait_for(lambda: req("GET", "/status", token)[1]
                      .get("modules", {}).get("dummyCrash", {}).get("state") == "crash-loop", 40)
        check("dummyCrash marked crash-loop", bool(st),
              req("GET", "/status", token)[1].get("modules", {}).get("dummyCrash", {}))

        os.kill(pid1, signal.SIGKILL)
        def restarted():
            m = req("GET", "/status", token)[1]["modules"]["dummyOk"]
            return m["pid"] not in (None, pid1) and m["restarts"] >= 1 and m
        m = wait_for(restarted, 15)
        check("kill -9 auto-restart with new pid, restarts>=1", bool(m), str(m))
        pid2 = m["pid"] if m else None

        code, _ = req("POST", "/modules/dummyOk/stop", token)
        check("stop returns 200", code == 200)
        st = wait_for(lambda: req("GET", "/status", token)[1]
                      ["modules"]["dummyOk"]["state"] == "disabled", 12)
        check("dummyOk disabled after stop", bool(st))
        desired = json.load(open(os.path.join(state, "desired.json")))
        check("desired.json persisted dummyOk=false", desired.get("dummyOk") is False)

        sup.send_signal(signal.SIGTERM)
        rc = sup.wait(timeout=20)
        check("supervisor exits 0 on SIGTERM", rc == 0, f"rc={rc}")
        if pid2:
            alive = os.path.exists(f"/proc/{pid2}")
            check("no orphan dummyOk after shutdown", not alive)

        sup = start_supervisor()
        st = wait_for(lambda: req("GET", "/status", token)[1]
                      .get("modules", {}).get("dummyOk", {}).get("state") == "disabled", 15)
        check("desired=false survives supervisor restart", bool(st))
        code, body = req("POST", "/modules/dummyOk/start", token)
        st = wait_for(lambda: req("GET", "/status", token)[1]
                      ["modules"]["dummyOk"]["state"] == "running", 10)
        check("start via control works", bool(st))
    finally:
        if sup.poll() is None:
            sup.send_signal(signal.SIGTERM)
            try:
                sup.wait(timeout=15)
            except subprocess.TimeoutExpired:
                sup.kill()
    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
