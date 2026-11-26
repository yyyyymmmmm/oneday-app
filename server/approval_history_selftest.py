#!/usr/bin/env python3
"""Approval bar 1 selftest (queue 182): guard-event capture + unified
approval history. Run: python3 approval_history_selftest.py

Covers: classify_guard_result against the upstream result shapes,
record_guard_event idempotency, the observing shim's install /
uninstall / kill-switch behaviour against a fake tools.approval, the
parked-approval path staying intact, and approval_history's per-source
reconciliation (including the anti-fake-green error paths).
"""

import json
import os
import sys
import tempfile
import threading
import types
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "patches"))

tmp = Path(tempfile.mkdtemp(prefix="approval-bar1-selftest-"))
LEDGER = tmp / "approval_ledger.jsonl"
DECISIONS = tmp / "decisions.jsonl"
os.environ["HERMES_APPROVAL_LEDGER_PATH"] = str(LEDGER)
os.environ["HERMES_WRITEGATE_DECISIONS_PATH"] = str(DECISIONS)

# --- fake upstream modules (tools.approval / tools.terminal_tool /
# gateway.run) -------------------------------------------------------
tools_pkg = types.ModuleType("tools")
tools_pkg.__path__ = []
sys.modules["tools"] = tools_pkg

approval_mod = types.ModuleType("tools.approval")
approval_mod._lock = threading.RLock()
approval_mod._gateway_queues = {}
approval_mod._pending = {}

_state = {
    "unattended": [],
    "session_key": "cron:nightly",
    "guard_result": {"approved": True, "message": None},
    "code_result": {"approved": True, "message": None},
    "guard_calls": 0,
}


def _fake_check_all(command, env_type, approval_callback=None,
                    has_host_access=False):
    _state["guard_calls"] += 1
    return _state["guard_result"]


def _fake_check_code(code, env_type, has_host_access=False):
    return _state["code_result"]


class _Ctx:
    def __init__(self, name):
        self.name = name


approval_mod.check_all_command_guards = _fake_check_all
approval_mod.check_execute_code_guard = _fake_check_code
approval_mod._unattended_contexts = lambda: [_Ctx(n) for n in _state["unattended"]]
approval_mod.get_current_session_key = lambda: _state["session_key"]
approval_mod._command_findings = lambda cmd: [("dangerous_rm", "recursive delete")]
sys.modules["tools.approval"] = approval_mod
tools_pkg.approval = approval_mod

terminal_mod = types.ModuleType("tools.terminal_tool")
terminal_mod._check_all_guards_impl = _fake_check_all
sys.modules["tools.terminal_tool"] = terminal_mod
tools_pkg.terminal_tool = terminal_mod

gateway_pkg = types.ModuleType("gateway")
gateway_pkg.__path__ = []
sys.modules["gateway"] = gateway_pkg
run_mod = types.ModuleType("gateway.run")
run_mod._redact_approval_command = lambda t: t
sys.modules["gateway.run"] = run_mod
gateway_pkg.run = run_mod

import approval_projection as ap  # noqa: E402
import approval_history as ah  # noqa: E402

fails = []


def check(name, cond):
    print(f"  {'ok' if cond else 'FAIL'} {name}")
    if not cond:
        fails.append(name)


def ledger_lines():
    if not LEDGER.exists():
        return []
    return [json.loads(l) for l in LEDGER.read_text(encoding="utf-8").splitlines() if l.strip()]


CRON_DENY = {
    "approved": False,
    "message": ("BLOCKED: Command flagged as dangerous (heredoc script "
                "execution) but cron jobs run without a user present to "
                "approve it. Find an alternative approach that avoids "
                "this command. To allow dangerous commands in cron "
                "jobs, set approvals.cron_mode: approve in config.yaml."),
}
SQ_DENY = {
    "approved": False,
    "message": ("BLOCKED: Command flagged as dangerous (x) but "
                "single-query mode (-q) runs without a user present to "
                "approve it."),
    "pattern_key": "dangerous_rm", "description": "recursive delete",
}
ALLOW_SESSION = {
    "approved": True, "message": None,
    "pre_approved": [{"description": "recursive delete", "scope": "session"}],
}
ALLOW_LIST = {
    "approved": True, "message": None,
    "pre_approved": [{"description": "recursive delete",
                      "scope": "allowlist", "rule": "rm -rf /tmp/*"}],
}
HUMAN_DENY = {
    "approved": False, "message": "BLOCKED: User denied this command.",
    "pattern_key": "dangerous_rm", "description": "recursive delete",
    "outcome": "denied", "user_consent": False,
}
PENDING = {
    "approved": False, "pattern_key": "dangerous_rm",
    "status": "pending_approval", "approval_pending": True,
    "command": "rm -rf /tmp/x", "description": "recursive delete",
    "message": "asking",
}
CODE_CRON_DENY = {
    "approved": False,
    "message": ("BLOCKED: execute_code runs arbitrary local Python "
                "(including subprocess calls that bypass shell-string "
                "approval checks). Cron jobs run without a user "
                "present to approve it."),
    "pattern_key": "execute_code", "description": "execute_code script",
    "outcome": "blocked", "user_consent": False,
}

print("== classify_guard_result (upstream shapes) ==")
c = ap.classify_guard_result(CRON_DENY, unattended=["cron"])
check("cron deny -> cron_deny", c is not None and c[0] == "cron_deny" and c[1]["guard_context"] == "cron")
c = ap.classify_guard_result(SQ_DENY, unattended=["single_query"])
check("single-query deny -> unattended_deny", c is not None and c[0] == "unattended_deny")
c = ap.classify_guard_result(ALLOW_SESSION, unattended=[])
check("session pre-approved -> guard_allow", c is not None and c[0] == "guard_allow" and c[1]["scopes"] == ["session"])
c = ap.classify_guard_result(ALLOW_LIST, unattended=[])
check("allowlist hit -> guard_allow", c is not None and c[0] == "guard_allow" and c[1]["scopes"] == ["allowlist"])
check("plain approved -> None", ap.classify_guard_result({"approved": True, "message": None}, unattended=["cron"]) is None)
check("human deny -> None", ap.classify_guard_result(HUMAN_DENY, unattended=["cron"]) is None)
check("parked pending -> None", ap.classify_guard_result(PENDING, unattended=["cron"]) is None)
check("cron-shaped deny without unattended ctx -> None", ap.classify_guard_result(CRON_DENY, unattended=[]) is None)
c = ap.classify_guard_result(CODE_CRON_DENY, gate="execute_code", unattended=["cron"])
check("execute_code cron deny -> cron_deny", c is not None and c[0] == "cron_deny")
check("execute_code deny under command gate -> None", ap.classify_guard_result(CODE_CRON_DENY, gate="command", unattended=["cron"]) is None)

print("== record_guard_event idempotency ==")
r1 = ap.record_guard_event("guard|fixed-key-1", "cron_deny",
                           {"guard_context": "cron"},
                           command="rm -rf /tmp/x", description="recursive delete",
                           pattern_keys=["dangerous_rm"], session_key="cron:nightly")
r2 = ap.record_guard_event("guard|fixed-key-1", "cron_deny",
                           {"guard_context": "cron"},
                           command="rm -rf /tmp/x", description="recursive delete",
                           pattern_keys=["dangerous_rm"], session_key="cron:nightly")
check("same key twice -> same record", r1["request_id"] == r2["request_id"])
guard_lines = [l for l in ledger_lines() if l["event"] == "guard_event"]
check("same key twice -> one ledger line", len(guard_lines) == 1)
check("record is born terminal + sourced", r1["status"] == "answered" and r1["source"] == "guard" and r1["choice"] == "deny")
r3 = ap.record_guard_event("guard|fixed-key-2", "cron_deny",
                           {"guard_context": "cron"},
                           command="rm -rf /tmp/x", description="recursive delete",
                           pattern_keys=["dangerous_rm"], session_key="cron:nightly")
check("distinct key -> distinct record", r3["request_id"] != r1["request_id"] and len([l for l in ledger_lines() if l["event"] == "guard_event"]) == 2)

print("== parked path intact ==")
parked = {
    "request_id": "req-selftest-1", "session_key": "sess-1",
    "run_id": None, "session_id": None, "source": "queue",
    "answerable": True, "command": "rm -rf /tmp/y",
    "description": "recursive delete", "pattern_keys": ["dangerous_rm"],
    "choices": ["once", "session", "always", "deny"], "status": "pending",
    "choice": None, "created_at": 1000.0, "expires_at": 1300.0,
    "decided_at": None,
}
with ap._lock:
    ap._emit("created", parked)
    ap._settle_record(ap._records["req-selftest-1"], "answered", choice="once")
listed = {r["request_id"]: r for r in ap.list_approvals()}
check("parked record settles + lists", listed["req-selftest-1"]["status"] == "answered" and listed["req-selftest-1"]["choice"] == "once")
check("guard events list alongside parked", any(r.get("event_kind") == "cron_deny" for r in listed.values()))

print("== observing shim: install / observe / uninstall / kill switch ==")
n = ap.install_guard_hooks()
check("hooks installed (>=3 entry points)", n >= 3)
check("install is idempotent", ap.install_guard_hooks() == n)
_state["unattended"] = ["cron"]
_state["guard_result"] = CRON_DENY
before = len([l for l in ledger_lines() if l["event"] == "guard_event"])
out = terminal_mod._check_all_guards_impl("python3 - <<'EOF'\nEOF", "local")
check("shim returns the original result verbatim", out is CRON_DENY)
after = [l for l in ledger_lines() if l["event"] == "guard_event"]
check("cron deny via terminal binding recorded once", len(after) == before + 1)
rec = after[-1]["record"]
check("recorded with session + context", rec["session_key"] == "cron:nightly" and rec["guard_context"] == "cron" and rec["event_kind"] == "cron_deny")
_state["guard_result"] = ALLOW_SESSION
approval_mod.check_all_command_guards("rm -rf /tmp/z", "local")
after2 = [l for l in ledger_lines() if l["event"] == "guard_event"]
check("guard allow recorded", len(after2) == len(after) + 1 and after2[-1]["record"]["event_kind"] == "guard_allow" and after2[-1]["record"]["scopes"] == ["session"] and after2[-1]["record"]["pattern_keys"] == ["dangerous_rm"])
_state["guard_result"] = {"approved": True, "message": None}
approval_mod.check_all_command_guards("ls", "local")
check("clean approval not recorded", len([l for l in ledger_lines() if l["event"] == "guard_event"]) == len(after2))
_state["code_result"] = CODE_CRON_DENY
approval_mod.check_execute_code_guard("import os", "local")
after3 = [l for l in ledger_lines() if l["event"] == "guard_event"]
check("execute_code cron deny recorded", len(after3) == len(after2) + 1 and after3[-1]["record"]["gate"] == "execute_code")
ap.uninstall_guard_hooks()
check("uninstall restores originals", terminal_mod._check_all_guards_impl is _fake_check_all and approval_mod.check_all_command_guards is _fake_check_all)
_state["guard_result"] = CRON_DENY
terminal_mod._check_all_guards_impl("rm -rf /tmp/x", "local")
check("no recording after uninstall", len([l for l in ledger_lines() if l["event"] == "guard_event"]) == len(after3))
os.environ["HERMES_APPROVAL_GUARD_EVENTS"] = "off"
check("kill switch blocks install", ap.install_guard_hooks() == 0)
del os.environ["HERMES_APPROVAL_GUARD_EVENTS"]

print("== approval_history reconciliation ==")
LEDGER2 = tmp / "ledger2.jsonl"
DEC2 = tmp / "decisions2.jsonl"
os.environ["HERMES_APPROVAL_LEDGER_PATH"] = str(LEDGER2)
os.environ["HERMES_WRITEGATE_DECISIONS_PATH"] = str(DEC2)


def _line(event, record):
    return json.dumps({"v": 1, "event": event, "ts": record.get("decided_at") or record.get("created_at"), "record": record}, ensure_ascii=False)


exec_records = []
base = {"session_key": "sess-9", "run_id": None, "session_id": "s-9",
        "answerable": True, "command": "rm -rf /tmp/a",
        "description": "recursive delete", "pattern_keys": ["dangerous_rm"],
        "choices": ["once", "session", "always", "deny"]}
a = dict(base, request_id="req-A", source="queue", status="pending",
         choice=None, created_at=2000.0, expires_at=2300.0, decided_at=None)
exec_records.append(_line("created", a))
a2 = dict(a, status="answered", choice="once", decided_at=2100.0)
exec_records.append(_line("decided", a2))
b = dict(base, request_id="req-B", source="queue", status="answered",
         choice="always", created_at=2200.0, expires_at=2500.0,
         decided_at=2300.0)
exec_records.append(_line("decided", b))
g1 = {"request_id": "evt-1", "session_key": "cron:nightly", "run_id": None,
      "session_id": None, "source": "guard", "event_kind": "cron_deny",
      "gate": "command", "answerable": False, "command": "cat /etc/shadow",
      "description": "", "pattern_keys": [], "choices": [],
      "status": "answered", "choice": "deny", "scopes": None,
      "guard_context": "cron", "created_at": 2400.0, "expires_at": None,
      "decided_at": 2400.0}
exec_records.append(_line("guard_event", g1))
g2 = dict(g1, request_id="evt-2", event_kind="guard_allow", choice=None,
          scopes=["permanent"], created_at=2500.0, decided_at=2500.0)
exec_records.append(_line("guard_event", g2))
LEDGER2.write_text("\n".join(exec_records) + "\n", encoding="utf-8")

wg_rows = [
    {"id": "wg-1", "subsystem": "memory", "action": "add",
     "summary": "add to memory", "origin": "foreground",
     "created_at": "2026-11-26T01:00:00+00:00",
     "decided_at": "2026-11-26T01:01:00+00:00", "decision": "approved",
     "op": "add", "content_preview": "hello"},
    {"id": "wg-2", "subsystem": "skills", "action": "batch",
     "summary": "batch(2 ops) on demo", "origin": "background_review",
     "created_at": "2026-11-26T02:00:00+00:00",
     "decided_at": "2026-11-26T02:01:00+00:00", "decision": "approved",
     "op": "batch", "op_count": 2, "op_kinds": ["create", "patch"],
     "target_name": "demo", "via_rule": "rule-1"},
    {"id": "wg-3", "subsystem": "memory", "action": "remove",
     "summary": "remove from memory", "origin": "assistant_tool",
     "created_at": "2026-11-26T03:00:00+00:00",
     "decided_at": "2026-11-26T03:01:00+00:00", "decision": "rejected",
     "op": "remove"},
]
DEC2.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in wg_rows) + "\n", encoding="utf-8")

h = ah.list_approval_history()
check("total = 4 exec + 3 writegate", h["total"] == 7)
check("reconciled", h["reconciled"] is True)
check("exec equation: folded == projected", h["sources"]["exec"]["ledger_records"] == 4 and h["sources"]["exec"]["projected"] == 4)
check("exec breakdown: parked 2 + guard 2", h["sources"]["exec"]["parked"] == 2 and h["sources"]["exec"]["guard_events"] == 2)
check("writegate equation: rows == projected", h["sources"]["writegate"]["decision_rows"] == 3 and h["sources"]["writegate"]["projected"] == 3)
check("via_rule counted apart", h["counts"]["via_rule"] == 1 and h["counts"]["human_decided"] == 6)
by_id = {i["id"]: i for i in h["history"]}
check("cron item: initiator scheduled", by_id["exec:evt-1"]["initiator"]["type"] == "scheduled")
check("guard allow item: tier + scopes material", by_id["exec:evt-2"]["tier"] == "pre_approved" and by_id["exec:evt-2"]["title_material"]["scopes"] == ["permanent"])
check("writegate rule item: tier rule + via_rule id", by_id["writegate:wg-2"]["tier"] == "rule" and by_id["writegate:wg-2"]["via_rule"] == "rule-1")
check("writegate item: title material carried", by_id["writegate:wg-2"]["title_material"]["target_name"] == "demo")
check("sorted newest first", h["history"][0]["decided_at"] >= h["history"][-1]["decided_at"])
h3 = ah.list_approval_history(limit=3)
check("limit respected, total stays honest", h3["returned"] == 3 and h3["total"] == 7)

print("== anti-fake-green ==")
LEDGER2.write_text("not json\n{bad\n", encoding="utf-8")
h = ah.list_approval_history()
check("one corrupt source -> partial + named", h["partial"] is True and h["source_errors"] == ["exec"] and h["total"] == 3)
DEC2.write_text("garbage\n", encoding="utf-8")
try:
    ah.list_approval_history()
    check("both corrupt -> RuntimeError", False)
except RuntimeError:
    check("both corrupt -> RuntimeError", True)
LEDGER2.write_text("", encoding="utf-8")
DEC2.write_text("", encoding="utf-8")
h = ah.list_approval_history()
check("empty-but-readable sources -> stated zero", h["total"] == 0 and h["reconciled"] is True and h["partial"] is False)

print()
if fails:
    print(f"SELFTEST FAILED: {len(fails)} check(s): {fails}")
    sys.exit(1)
print("SELFTEST PASSED")
