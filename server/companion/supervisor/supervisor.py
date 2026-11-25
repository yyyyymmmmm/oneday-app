#!/usr/bin/env python3
"""OneDay Companion supervisor (PID 1, stdlib only).

Hosts the five bridge modules + front as child processes inside one
container. Responsibilities (and nothing more):
  - parse companion.env by segment, inject each segment only into its
    own module process (F03 key separation preserved in-process);
  - start/stop children per desired state (persisted in state dir);
  - restart crashed children: 2s first, exponential backoff on fast
    crashes, mark crash-loop after repeated fast crashes;
  - expose a token-guarded control channel on 127.0.0.1:8651 for front
    (status / start / stop / log tail);
  - clean shutdown: SIGTERM/SIGINT stops every child, reaps zombies.

Health aggregation does NOT live here (that is front's job, spec S11:
keep the supervisor minimal so the only from-scratch critical piece
stays small).
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parent.parent
STATE_DIR = Path(os.environ.get("COMPANION_STATE_DIR", "/opt/companion-state"))
ENV_FILE = Path(os.environ.get("COMPANION_ENV_FILE", "/opt/companion/companion.env"))
MANIFEST = Path(os.environ.get("COMPANION_MODULES_JSON", str(Path(__file__).with_name("modules.json"))))
CONTROL_PORT = int(os.environ.get("COMPANION_CONTROL_PORT", "8651"))
PYTHON = os.environ.get("COMPANION_PYTHON", "/opt/hermes/.venv/bin/python3")

FAST_CRASH_SEC = float(os.environ.get("COMPANION_FAST_CRASH_SEC", "10"))
BACKOFF_BASE = float(os.environ.get("COMPANION_BACKOFF_BASE_SEC", "2"))
BACKOFF_CAP = float(os.environ.get("COMPANION_BACKOFF_CAP_SEC", "60"))
CRASH_LOOP_THRESHOLD = int(os.environ.get("COMPANION_CRASH_LOOP_THRESHOLD", "5"))
STOP_GRACE_SEC = 5.0
LOG_LINES = 300


def log(msg: str) -> None:
    print(f"[supervisor] {msg}", flush=True)


# ---------------------------------------------------------------- env file
def parse_env_file(path: Path) -> dict[str, dict[str, str]]:
    """Parse companion.env: sections introduced by '# [name]' (or '[name]'),
    KEY=VALUE lines, '#' comments. Values may be single/double quoted."""
    segments: dict[str, dict[str, str]] = {"global": {}}
    current = "global"
    if not path.exists():
        log(f"env file not found: {path} (all segments empty)")
        return segments
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        probe = line.lstrip("#").strip()
        if probe.startswith("[") and probe.endswith("]") and "=" not in probe:
            current = probe[1:-1].strip()
            segments.setdefault(current, {})
            continue
        if line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        segments.setdefault(current, {})[key] = value
    return segments


# ---------------------------------------------------------------- module
class Module:
    def __init__(self, spec: dict, segments: dict[str, dict[str, str]]):
        self.id = spec["id"]
        self.name = spec.get("name", self.id)
        self.path = ROOT / spec["path"]
        self.port = spec.get("port")
        self.segment = spec.get("segment", "global")
        self.desired = True
        self.proc: subprocess.Popen | None = None
        self.restarts = 0
        self.started_at: float | None = None
        self.fast_crashes = 0
        self.next_start_at = 0.0
        self.stop_deadline: float | None = None
        self.ever_started = False
        self.logs: deque[str] = deque(maxlen=LOG_LINES)
        self.env = self._build_env(spec, segments)

    def _build_env(self, spec: dict, segments: dict[str, dict[str, str]]) -> dict[str, str]:
        env: dict[str, str] = {
            "PATH": "/opt/hermes/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "LANG": "C.UTF-8",
            "PYTHONUNBUFFERED": "1",
        }
        glob = segments.get("global", {})
        if spec.get("include_global"):
            # front is the [global] consumer (template header: the
            # global segment is shared by supervisor and front)
            env.update(glob)
        seg = segments.get(self.segment, {})
        env.update(seg)
        if "TZ" in glob:
            env["TZ"] = glob["TZ"]
        for key, from_seg in (spec.get("env_from") or {}).items():
            src = segments.get(from_seg, {})
            if key in src:
                env[key] = src[key]
        if spec.get("inject_module_keys"):
            # Front probes each module with that module's own key
            # (spec 2.5: aggregation lives in front). This is the single
            # deliberate exception to segment isolation; the keys are
            # never returned by any front API.
            for other in ("device",):  # write-gate/overview/oneday 已随断桥批二/批三退役入网关
                for k, v in segments.get(other, {}).items():
                    if k.endswith("_BRIDGE_KEY"):
                        env[k] = v
            env["COMPANION_CONTROL_PORT"] = str(CONTROL_PORT)
            env["COMPANION_STATE_DIR"] = str(STATE_DIR)
            env["COMPANION_ENV_FILE"] = str(ENV_FILE)
        return env

    # ------------------------------------------------------------ lifecycle
    def spawn(self) -> None:
        cmd = [PYTHON, str(self.path)]
        try:
            self.proc = subprocess.Popen(
                cmd, cwd=str(ROOT), env=self.env,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, errors="replace", bufsize=1,
            )
        except Exception as e:  # interpreter missing etc: treat as crash
            log(f"{self.id}: spawn failed: {e}")
            self.proc = None
            self._schedule_retry(fast=True)
            return
        self.started_at = time.time()
        self.stop_deadline = None
        if self.ever_started:
            self.restarts += 1
        self.ever_started = True
        log(f"{self.id}: started pid={self.proc.pid} port={self.port}")
        t = threading.Thread(target=self._pump, args=(self.proc,), daemon=True)
        t.start()

    def _pump(self, proc: subprocess.Popen) -> None:
        try:
            for line in proc.stdout:  # type: ignore[union-attr]
                line = line.rstrip("\n")
                self.logs.append(line)
                print(f"[{self.id}] {line}", flush=True)
        except Exception:
            pass

    def request_stop(self) -> None:
        self.desired = False
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            self.stop_deadline = time.time() + STOP_GRACE_SEC

    def request_start(self) -> None:
        self.desired = True
        self.fast_crashes = 0
        self.next_start_at = 0.0
        if not self.proc or self.proc.poll() is not None:
            self.spawn()

    def _schedule_retry(self, fast: bool) -> None:
        if fast:
            self.fast_crashes += 1
        delay = min(BACKOFF_CAP, BACKOFF_BASE * (2 ** max(0, self.fast_crashes - 1))) \
            if self.fast_crashes else BACKOFF_BASE
        self.next_start_at = time.time() + delay

    def tick(self) -> None:
        if self.proc and self.proc.poll() is not None:
            rc = self.proc.returncode
            ran = time.time() - (self.started_at or time.time())
            log(f"{self.id}: exited rc={rc} after {ran:.1f}s")
            self.proc = None
            self.started_at = None
            if self.desired:
                self._schedule_retry(fast=ran < FAST_CRASH_SEC)
                if ran >= 60:
                    self.fast_crashes = 0
        if self.stop_deadline and self.proc and self.proc.poll() is None \
                and time.time() > self.stop_deadline:
            log(f"{self.id}: stop grace exceeded, killing")
            self.proc.kill()
            self.stop_deadline = None
        if self.desired and not self.proc and time.time() >= self.next_start_at:
            self.spawn()

    # ------------------------------------------------------------ status
    def state(self) -> str:
        if not self.desired:
            return "disabled"
        if self.proc and self.proc.poll() is None:
            return "running"
        if self.fast_crashes >= CRASH_LOOP_THRESHOLD:
            return "crash-loop"
        if self.ever_started:
            return "restarting"
        return "stopped"

    def rss_mb(self) -> float | None:
        if not self.proc or self.proc.poll() is not None:
            return None
        try:
            for line in Path(f"/proc/{self.proc.pid}/status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    return round(int(line.split()[1]) / 1024.0, 1)
        except Exception:
            return None
        return None

    def status(self) -> dict:
        return {
            "id": self.id, "name": self.name, "desired": self.desired,
            "state": self.state(),
            "pid": self.proc.pid if self.proc and self.proc.poll() is None else None,
            "restarts": self.restarts,
            "uptimeSec": round(time.time() - self.started_at) if self.started_at else 0,
            "rssMB": self.rss_mb(),
            "port": self.port,
        }


# ---------------------------------------------------------------- supervisor
class Supervisor:
    def __init__(self) -> None:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        self.segments = parse_env_file(ENV_FILE)
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.modules: dict[str, Module] = {}
        for spec in manifest["modules"]:
            self.modules[spec["id"]] = Module(spec, self.segments)
        self._load_desired()
        self.token = self._control_token()
        self.shutting_down = False

    def _control_token(self) -> str:
        p = STATE_DIR / "control.token"
        if p.exists():
            return p.read_text().strip()
        import secrets
        tok = secrets.token_hex(32)
        p.write_text(tok)
        p.chmod(0o600)
        return tok

    def _desired_path(self) -> Path:
        return STATE_DIR / "desired.json"

    def _load_desired(self) -> None:
        saved: dict = {}
        p = self._desired_path()
        if p.exists():
            try:
                saved = json.loads(p.read_text())
            except Exception:
                saved = {}
        glob = self.segments.get("global", {})
        for mod in self.modules.values():
            if mod.id in saved:
                mod.desired = bool(saved[mod.id])
            else:
                env_key = f"MODULE_{mod.id.upper()}_ENABLED"
                mod.desired = glob.get(env_key, "1") != "0"

    def save_desired(self) -> None:
        data = {m.id: m.desired for m in self.modules.values()}
        tmp = self._desired_path().with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=1))
        tmp.replace(self._desired_path())

    def start_all(self) -> None:
        for mod in self.modules.values():
            if mod.desired:
                mod.spawn()

    def tick(self) -> None:
        for mod in self.modules.values():
            mod.tick()
        # Reap orphans we do not own (PID 1 duty); Popen children are
        # reaped through poll() above, waitpid here only sweeps strays.
        while True:
            try:
                pid, _ = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                break
            if pid <= 0:
                break

    def shutdown(self) -> None:
        log("shutting down: stopping all modules")
        for mod in self.modules.values():
            mod.desired = False
            if mod.proc and mod.proc.poll() is None:
                mod.proc.terminate()
        deadline = time.time() + STOP_GRACE_SEC + 2
        while time.time() < deadline:
            alive = [m for m in self.modules.values()
                     if m.proc and m.proc.poll() is None]
            if not alive:
                break
            time.sleep(0.2)
        for mod in self.modules.values():
            if mod.proc and mod.proc.poll() is None:
                mod.proc.kill()
        log("all modules stopped")


# ---------------------------------------------------------------- control API
def make_handler(sup: Supervisor):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):  # keep container log clean
            pass

        def _send(self, code: int, obj: dict) -> None:
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _authed(self) -> bool:
            import hmac
            return hmac.compare_digest(
                self.headers.get("X-Control-Token", ""), sup.token)

        def do_GET(self):
            if not self._authed():
                return self._send(401, {"error": "unauthorized"})
            u = urlparse(self.path)
            parts = [p for p in u.path.split("/") if p]
            if u.path == "/status":
                return self._send(200, {
                    "modules": {m.id: m.status() for m in sup.modules.values()}})
            if len(parts) == 3 and parts[0] == "modules" and parts[2] == "logs":
                mod = sup.modules.get(parts[1])
                if not mod:
                    return self._send(404, {"error": "no such module"})
                n = int(parse_qs(u.query).get("lines", ["50"])[0])
                return self._send(200, {"lines": list(mod.logs)[-n:]})
            return self._send(404, {"error": "not found"})

        def do_POST(self):
            if not self._authed():
                return self._send(401, {"error": "unauthorized"})
            parts = [p for p in self.path.split("/") if p]
            if len(parts) == 3 and parts[0] == "modules" and parts[2] in ("start", "stop"):
                mod = sup.modules.get(parts[1])
                if not mod:
                    return self._send(404, {"error": "no such module"})
                if parts[2] == "start":
                    mod.request_start()
                else:
                    mod.request_stop()
                sup.save_desired()
                return self._send(200, {"ok": True, "module": mod.status()})
            return self._send(404, {"error": "not found"})

    return Handler


def main() -> int:
    sup = Supervisor()
    server = ThreadingHTTPServer(("127.0.0.1", CONTROL_PORT), make_handler(sup))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    log(f"control channel on 127.0.0.1:{CONTROL_PORT}")

    def _signal(signum, frame):
        sup.shutting_down = True

    signal.signal(signal.SIGTERM, _signal)
    signal.signal(signal.SIGINT, _signal)

    sup.start_all()
    while not sup.shutting_down:
        sup.tick()
        time.sleep(0.5)
    server.shutdown()
    sup.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
