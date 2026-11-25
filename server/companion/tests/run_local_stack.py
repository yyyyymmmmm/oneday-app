#!/usr/bin/env python3
"""Full local stack rehearsal: real supervisor + real five modules +
real front, test keys, temp data dirs, fake Hermes on 18942.
This is the M0 'one command' local boot:  python3 tests/run_local_stack.py
Checks module ports, aggregated info states, module toggle through
front, kill -9 recovery, and clean supervisor shutdown."""
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SUP = os.path.join(ROOT, "supervisor", "supervisor.py")
HPORT = 18942
API = "http://127.0.0.1:8650/api/companion"
SVC = {"Authorization": "Bearer svc-stack-key"}

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


class FakeHermes(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self._json(200, {"status": "ok"})
        if self.path == "/v1/models":
            ok = self.headers.get("Authorization", "").startswith("Bearer ")
            return self._json(200, {"data": []}) if ok else self._json(401, {})
        if self.path.startswith("/api/sessions"):
            return self._json(200, {"data": []})
        return self._json(404, {})

    def do_POST(self):
        return self._json(404, {})


def req(method, url, body=None, headers=None, timeout=6):
    h = dict(headers or {})
    data = json.dumps(body).encode() if body is not None else None
    if data:
        h["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}
    except Exception as e:
        return 0, {"_error": str(e)}


def wait_for(fn, timeout=30, interval=0.5):
    end = time.time() + timeout
    while time.time() < end:
        v = fn()
        if v:
            return v
        time.sleep(interval)
    return None


def main():
    tmp = tempfile.mkdtemp(prefix="companion-stack-")
    state = os.path.join(tmp, "state")
    hermes_home = os.path.join(tmp, "data")
    os.makedirs(os.path.join(hermes_home, "write-gate"))
    open(os.path.join(hermes_home, "write-gate", "decisions.jsonl"), "w").close()
    open(os.path.join(hermes_home, ".env"), "w").write("")
    open(os.path.join(hermes_home, "config.yaml"), "w").write("model:\n  default: deepseek-flash\n")
    overview_data = os.path.join(tmp, "overview-data")
    oneday_data = os.path.join(tmp, "oneday-data")
    device_data = os.path.join(tmp, "device-data")
    for d in (overview_data, oneday_data, device_data):
        os.makedirs(d)
    open(os.path.join(oneday_data, "data.json"), "w").write('{"goals": [], "ideas": []}')
    open(os.path.join(oneday_data, "monitor-notifications.jsonl"), "w").close()

    env_text = f"""# [global]
TZ=Asia/Shanghai
COMPANION_SERVICE_KEY=svc-stack-key
HERMES_API_KEY=login-key-good
HERMES_BASE=http://127.0.0.1:{HPORT}
HERMES_HOME={hermes_home}
COMPANION_HERMES_ENV={hermes_home}/.env
COMPANION_CONFIG_PATH={hermes_home}/config.yaml
COMPANION_ONEDAY_DATA={oneday_data}/data.json
COMPANION_DECISIONS_PATH={hermes_home}/write-gate/decisions.jsonl
COMPANION_COOKIE_SECURE=0

# [front]
PANEL_PASSWORD_HASH=

# [write-gate]
WRITE_GATE_BRIDGE_KEY=wg-stack-key
WRITE_GATE_PORT=8643
PYTHONPATH=

# [overview]
OVERVIEW_BRIDGE_KEY=ov-stack-key
OVERVIEW_PORT=8644
STATE_DIR={overview_data}
DECISIONS_PATH={hermes_home}/write-gate/decisions.jsonl
MONITOR_PATH={oneday_data}/monitor-notifications.jsonl
HERMES_BASE=http://127.0.0.1:{HPORT}
WRITE_GATE_BASE=http://127.0.0.1:8643

# [box] —— 桥-3 已退役（1.0.57）：BOX_BRIDGE_KEY/BOX_PORT 不再写入，
# 只留连接记录语义的 MCP_BOX_API_KEY。
MCP_BOX_API_KEY=fake-box-key

# [oneday]
ONEDAY_BRIDGE_KEY=od-stack-key
ONEDAY_PORT=8646
DATA_PATH={oneday_data}/data.json
HERMES_BASE_URL=http://127.0.0.1:{HPORT}
HERMES_DASH_USER=admin
HERMES_DASH_PASSWORD=fake

# [device]
DEVICE_BRIDGE_KEY=dev-stack-key
DEVICE_PORT=8647
DATA_DIR={device_data}
"""
    env_file = os.path.join(tmp, "companion.env")
    open(env_file, "w").write(env_text)

    fake = ThreadingHTTPServer(("127.0.0.1", HPORT), FakeHermes)
    threading.Thread(target=fake.serve_forever, daemon=True).start()

    env = dict(os.environ, COMPANION_STATE_DIR=state, COMPANION_ENV_FILE=env_file,
               COMPANION_PYTHON=sys.executable)
    sup = subprocess.Popen([sys.executable, SUP], env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        code_body = wait_for(lambda: req("GET", "http://127.0.0.1:8647/health")[0] == 200
                             and req("GET", "http://127.0.0.1:8647/health"), 40)
        check("device module up on 8647", bool(code_body))
        c, b = req("GET", "http://127.0.0.1:8643/status",
                   headers={"Authorization": "Bearer wg-stack-key"})
        check("write-gate up, fail-closed supported=false",
              c == 200 and b.get("supported") is False, str(b))
        c, _ = req("GET", "http://127.0.0.1:8644/overview",
                   headers={"Authorization": "Bearer ov-stack-key"})
        check("overview up on 8644", c == 200, f"code={c}")
        c, b = req("GET", "http://127.0.0.1:8646/health",
                   headers={"Authorization": "Bearer od-stack-key"})
        check("oneday up on 8646, not degraded",
              c == 200 and b.get("degraded") is False, str(b))
        info = wait_for(lambda: (lambda r: r[1] if r[0] == 200 else None)(
            req("GET", API + "/info", headers=SVC)), 30)
        check("front info responds", bool(info))
        if info:
            m = info["modules"]
            check("info: hermesUp true", info["hermesUp"] is True)
            check("info: writeGate degraded (no Hermes code locally)",
                  m["writeGate"]["state"] == "degraded", str(m["writeGate"]))
            check("info: overview up", m["overview"]["state"] == "up", str(m["overview"]))
            check("info: oneday up", m["oneday"]["state"] == "up", str(m["oneday"]))
            check("info: device up", m["device"]["state"] == "up", str(m["device"]))
            check("info: box module retired (absent from modules)",
                  "box" not in m, str(sorted(m)))

        c, mods = req("GET", API + "/modules", headers=SVC)
        od = next((x for x in mods.get("modules", []) if x["id"] == "oneday"), {})
        check("modules view: oneday running with pid + rss",
              od.get("state") == "running" and isinstance(od.get("pid"), int)
              and od.get("rssMB"), str(od))

        c, _ = req("POST", API + "/modules/device/toggle",
                   {"enabled": False}, headers=SVC)
        gone = wait_for(lambda: req("GET", "http://127.0.0.1:8647/health")[0] == 0, 15)
        check("toggle device off through front", c == 200 and bool(gone))
        c, info2 = req("GET", API + "/info", headers=SVC)
        check("info shows device disabled",
              info2["modules"]["device"]["state"] == "disabled")
        c, _ = req("POST", API + "/modules/device/toggle",
                   {"enabled": True}, headers=SVC)
        back = wait_for(lambda: req("GET", "http://127.0.0.1:8647/health")[0] == 200, 20)
        check("toggle device back on", c == 200 and bool(back))

        if od.get("pid"):
            os.kill(od["pid"], signal.SIGKILL)
            def recovered():
                cc, bb = req("GET", "http://127.0.0.1:8646/health",
                             headers={"Authorization": "Bearer od-stack-key"})
                if cc != 200:
                    return None
                _, mm = req("GET", API + "/modules", headers=SVC)
                row = next((x for x in mm.get("modules", []) if x["id"] == "oneday"), {})
                return row if row.get("restarts", 0) >= 1 and row.get("pid") != od["pid"] else None
            row = wait_for(recovered, 30)
            check("kill -9 oneday: supervisor restarts it, restarts>=1", bool(row), str(row))

        sup.send_signal(signal.SIGTERM)
        rc = sup.wait(timeout=25)
        check("supervisor SIGTERM exits 0", rc == 0, f"rc={rc}")
        import socket as _socket
        def _port_open(port):
            try:
                with _socket.create_connection(("127.0.0.1", port), timeout=1):
                    return True
            except Exception:
                return False
        still = [p for p in (8643, 8644, 8646, 8647, 8650, 8651)
                 if _port_open(p)]
        check("no module processes left after shutdown (ports closed)",
              not still, f"ports still open: {still}")
    finally:
        if sup.poll() is None:
            sup.kill()
        fake.shutdown()
    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
