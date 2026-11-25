"""Selftest for the option-card server machinery (hermes-deploy 1.12.0).

Part A (this file, local, stub-based): validate_options, the pending
store, the present_options handler, both projection helpers and the
_attach_options guard chain -- the shipped function bodies are pulled
out of the patch files by AST and executed, so what is tested is the
exact code that ships. Part B runs inside the hermes container against
a real SessionDB (see options_card_container_test.py).

Run: python3 options_card_selftest.py  ->  prints SELFTEST PASSED + count
"""

import ast
import importlib.util
import json
import pathlib
import sys
import types

ROOT = pathlib.Path(__file__).resolve().parent
PATCHES = ROOT / "patches"
CHECKS = []


def check(name, cond):
    CHECKS.append((name, bool(cond)))
    if not cond:
        print(f"FAIL: {name}")


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def extract_fn(path, fn_name):
    src = pathlib.Path(path).read_text()
    tree = ast.parse(src)
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == fn_name:
            return ast.get_source_segment(src, node)
    raise AssertionError(f"{fn_name} not found in {path}")


# ---------- pending store + validation (real module) ----------
pending = load_module("options_pending", PATCHES / "options_pending.py")
v = pending.validate_options

good = v([{"label": "方案 A"}, {"label": "方案 B", "send_text": "按方案 B 走，全量执行"}])
check("validate basic", good == [
    {"label": "方案 A", "send_text": "方案 A"},
    {"label": "方案 B", "send_text": "按方案 B 走，全量执行"}])
check("validate rejects 1 item", v([{"label": "only"}]) is None)
check("validate rejects 7 items", v([{"label": str(i)} for i in range(7)]) is None)
check("validate rejects empty label", v([{"label": "  "}, {"label": "x"}]) is None)
check("validate rejects non-list", v({"label": "x"}) is None)
check("validate rejects non-dict item", v([{"label": "x"}, "y"]) is None)
check("validate dedupes send_text", v([
    {"label": "A", "send_text": "go"}, {"label": "B", "send_text": "go"},
    {"label": "C"}]) == [{"label": "A", "send_text": "go"},
                          {"label": "C", "send_text": "C"}])
check("validate dedupe below min invalid",
      v([{"label": "A", "send_text": "go"}, {"label": "B", "send_text": "go"}]) is None)
check("validate caps label", v([
    {"label": "x" * 100}, {"label": "y"}])[0]["label"] == "x" * 60)
check("validate strips controls", v([
    {"label": "a\x00b"}, {"label": "c"}])[0]["label"] == "ab")

check("pending put/pop", pending.put("s1", "r1", good) and
      pending.pop("s1")["run_key"] == "r1" and pending.pop("s1") is None)
pending.put("s2", "r1", good)
pending.put("s2", "r2", good)
check("pending overwrite one entry", pending.pop("s2")["run_key"] == "r2")

# ---------- tool handler (real module, stubbed deps) ----------
gw = types.ModuleType("gateway")
gw.__path__ = []
platforms = types.ModuleType("gateway.platforms")
platforms.__path__ = []
platforms.options_pending = pending
session_context = types.ModuleType("gateway.session_context")
ENV = {"HERMES_SESSION_PLATFORM": "api_server",
       "HERMES_SESSION_ID": "sess-1", "HERMES_SESSION_KEY": "run-1"}
session_context.get_session_env = lambda k, d="": ENV.get(k, d)
gw.platforms = platforms
gw.session_context = session_context
sys.modules.update({"gateway": gw, "gateway.platforms": platforms,
                    "gateway.session_context": session_context})

tools_pkg = types.ModuleType("tools")
tools_pkg.__path__ = []
desktop_ui = types.ModuleType("tools.desktop_ui")
GATE = {"open": True}
desktop_ui.user_enabled = lambda key, default=False: GATE["open"]
registry_mod = types.ModuleType("tools.registry")
REGISTERED = {}


class _Registry:
    def register(self, **kw):
        REGISTERED.update(kw)


registry_mod.registry = _Registry()
registry_mod.tool_error = lambda msg: json.dumps({"error": msg})
tools_pkg.desktop_ui = desktop_ui
tools_pkg.registry = registry_mod
sys.modules.update({"tools": tools_pkg, "tools.desktop_ui": desktop_ui,
                    "tools.registry": registry_mod})

tool = load_module("present_options_tool", PATCHES / "present_options_tool.py")
check("tool registered", REGISTERED.get("name") == "present_options" and
      REGISTERED.get("toolset") == "options_card")

handler = tool._present_options
out = json.loads(handler({"options": [{"label": "继续"}, {"label": "停下"}]}))
check("handler success", out.get("success") is True)
entry = pending.pop("sess-1")
check("handler parked pending", entry and entry["run_key"] == "run-1" and
      entry["options"][0] == {"label": "继续", "send_text": "继续"})

GATE["open"] = False
out = json.loads(handler({"options": [{"label": "a"}, {"label": "b"}]}))
check("handler gate closed errors", "error" in out and pending.pop("sess-1") is None)
GATE["open"] = True
ENV["HERMES_SESSION_PLATFORM"] = "desktop"
out = json.loads(handler({"options": [{"label": "a"}, {"label": "b"}]}))
check("handler non-api_server errors", "error" in out)
ENV["HERMES_SESSION_PLATFORM"] = "api_server"
out = json.loads(handler({"options": [{"label": "only"}]}))
check("handler invalid options error", "error" in out and pending.pop("sess-1") is None)

# ---------- projection helpers (extracted from both patch files) ----------
for fname in ("api_server.py", "web_routers_sessions.py"):
    ns = {"json": json, "Any": object}
    exec(extract_fn(PATCHES / fname, "_options_from_display_metadata"), ns)
    proj = ns["_options_from_display_metadata"]
    stored = {"options": {"v": 1, "at": 123.5, "options": [
        {"label": "A", "send_text": "go A"}, {"label": "B"}]},
        "reactions": [{"emoji": "x", "author": "user"}]}
    got = proj(stored)
    check(f"{fname} projection shape", got == {"v": 1, "at": 123.5, "options": [
        {"label": "A", "send_text": "go A"}, {"label": "B", "send_text": "B"}]})
    check(f"{fname} projection empty on missing", proj({}) == {} and proj(None) == {})
    check(f"{fname} projection drops bad items",
          proj({"options": {"options": [{"label": ""}, {"nope": 1}]}}) == {})
    check(f"{fname} projection json-string meta",
          proj(json.dumps(stored))["options"][0]["label"] == "A")

# ---------- _attach_options guard chain (extracted, stubbed db) ----------
runs_src = (PATCHES / "api_server_runs.py").read_text()
attach_seg = extract_fn(PATCHES / "api_server_runs.py", "_attach_options")
check("attach is called in _finish before status publish",
      runs_src.index("_attach_options(self, run_id, run.session_id)")
      < runs_src.index('self._set_run_status(run_id, status, **fields, last_event=f"run.{status}", **extra)'))
check("present_options events suppressed",
      'tool_name in ("react_to_message", "present_options")' in runs_src)

CALLS = []


class FakeDB:
    def __init__(self, row_id):
        self._row_id = row_id

    def latest_message_row_id(self, session_id, role="assistant", offset=0):
        assert role == "assistant"
        return self._row_id


fake_pending = types.SimpleNamespace(
    pop=pending.pop, validate_options=pending.validate_options,
    attach_options=lambda db, sid, rid, opts: CALLS.append((sid, rid, opts)) or True)
hreg = types.ModuleType("hermes_state_registry")
hreg.acquire = lambda: FakeDB(42)
hreg.release_or_close = lambda db: None
sys.modules["hermes_state_registry"] = hreg
platforms.options_pending = fake_pending

import logging
ns = {"logger": logging.getLogger("t"), "suppress": __import__("contextlib").suppress,
      "Exception": Exception}
# _attach_options references gateway.platforms import at call time; route it.
real_import = __builtins__["__import__"] if isinstance(__builtins__, dict) else __builtins__.__import__


def fake_import(name, *a, **kw):
    if name == "gateway.platforms":
        mod = types.ModuleType("gateway.platforms")
        mod.options_pending = fake_pending
        return mod
    if name == "hermes_state_registry":
        return hreg
    return real_import(name, *a, **kw)


ns["__import__"] = fake_import
exec(attach_seg, ns)
attach = ns["_attach_options"]

pending.put("sess-9", "run-9", [{"label": "A", "send_text": "A"},
                                {"label": "B", "send_text": "B"}])
attach(object(), "run-9", "sess-9")
check("attach happy path writes", CALLS == [("sess-9", 42, [
    {"label": "A", "send_text": "A"}, {"label": "B", "send_text": "B"}])])
CALLS.clear()
pending.put("sess-9", "run-OTHER", [{"label": "A", "send_text": "A"},
                                    {"label": "B", "send_text": "B"}])
attach(object(), "run-9", "sess-9")
check("attach run_key mismatch drops", CALLS == [])
attach(object(), "run-9", "sess-9")
check("attach no pending no-op", CALLS == [])
hreg.acquire = lambda: FakeDB(None)
pending.put("sess-9", "run-9", [{"label": "A", "send_text": "A"},
                                {"label": "B", "send_text": "B"}])
attach(object(), "run-9", "sess-9")
check("attach no assistant row drops", CALLS == [])

# ---------- timing case (2.3.1): target row lands only after attach starts ----
# Real-traffic shape: at _finish time the DB holds only the empty-text
# tool-call assistant row (skipped by require_text); the terminal text
# row is committed by the turn's delivery commit a moment later. The
# attach must not give up on the first empty lookup.
import time as _time


class DelayedDB:
    """Text row appears on the 3rd lookup; other sessions never land."""

    def __init__(self):
        self.lookups = 0

    def latest_message_row_id(self, session_id, role="assistant", offset=0):
        assert role == "assistant"
        if session_id != "sess-T":
            return None
        self.lookups += 1
        return 77 if self.lookups >= 3 else None


_delayed = DelayedDB()
hreg.acquire = lambda: _delayed
pending.put("sess-T", "run-T", [{"label": "甲", "send_text": "甲"},
                                {"label": "乙", "send_text": "乙"}])
attach(object(), "run-T", "sess-T")
_deadline = _time.time() + 3.0
while _time.time() < _deadline and not any(c[0] == "sess-T" for c in CALLS):
    _time.sleep(0.05)
check("attach retries until delivery row lands",
      [c for c in CALLS if c[0] == "sess-T"] == [("sess-T", 77, [
          {"label": "甲", "send_text": "甲"}, {"label": "乙", "send_text": "乙"}])])
hreg.acquire = lambda: FakeDB(42)

# ---------- run binding (2.3.1 rev1): session-key run_key + freshness --------
# Real traffic: the tool handler registers run_key = HERMES_SESSION_KEY
# ("agent:main:api_server:dm:<...>"), never the bare run_id -- an
# equality guard drops every real card (same break the self-reaction
# attach fixed in 1.15.0). Binding: exact/suffix match, else freshness
# (entry registered after this run was created; same-session turns are
# lease-serialized, so a live entry at finish belongs to this run).
import types as _types

_now = _time.time()
_self = _types.SimpleNamespace(
    _run_statuses={"run-K": {"created_at": _now - 10.0}})
pending.put("sess-K", "agent:main:api_server:dm:conv-1",
            [{"label": "A", "send_text": "A"}, {"label": "B", "send_text": "B"}])
attach(_self, "run-K", "sess-K")
check("attach binds session-key run_key by freshness",
      [c for c in CALLS if c[0] == "sess-K"] == [("sess-K", 42, [
          {"label": "A", "send_text": "A"}, {"label": "B", "send_text": "B"}])])
CALLS.clear()
pending.put("sess-K", "agent:main:api_server:dm:conv-1",
            [{"label": "A", "send_text": "A"}, {"label": "B", "send_text": "B"}])
pending._pending["sess-K"]["at"] = _now - 100.0  # stale: predates run-K
attach(_self, "run-K", "sess-K")
check("attach drops stale entry from dead run", CALLS == [])

failed = [n for n, ok in CHECKS if not ok]
print(f"{len(CHECKS) - len(failed)}/{len(CHECKS)} checks passed")
if failed:
    sys.exit(1)
print("SELFTEST PASSED")
