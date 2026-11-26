#!/usr/bin/env python3
"""write-gate-bridge: HTTP bridge for Hermes write-approval (memory/skills).

Single-file service, stdlib HTTP + Hermes in-image modules only.
Runs in a sidecar container sharing the hermes image (v0.23.0) and the
/opt/data volume (HERMES_HOME=/opt/data, provided by the image ENV).

Contract: see ~/workspace/hermes-deploy/write-approval-bridge-plan.md §3.
- list/detail read pending records via tools.write_approval
- approve/reject go through hermes_cli.write_approval_commands
  .handle_pending_subcommand (memory store: tools.memory_tool
  .load_on_disk_store, same as the gateway's own /memory handler)
- every decision appends one metadata-only line to
  <HERMES_HOME>/write-gate/decisions.jsonl (no payload/diff/content)
- access log: method/path/status only, never bodies

P7 memory-entries routes (contract: memory-bridge-contract-20261109.md §2):
- GET /memories and GET /memories/{id} read entries through
  tools.memory_tool.load_on_disk_store() (same store the decider loads)
- POST /memories/propose is the only App-initiated write surface: it stages
  through tools.write_approval.stage_write — the exact internal the memory
  tool itself stages through — with origin "oneday_app", after pinning the
  target entry via store.resolve_entry like the tool's _pin_matched_entries.
  Nothing here ever writes memory files directly.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# --- startup self-check (fail-closed) -------------------------------------
SUPPORTED = True
SUPPORT_ERROR = ""
try:
    from tools import write_approval as wa
    from hermes_cli.write_approval_commands import handle_pending_subcommand
except Exception as e:  # pragma: no cover
    SUPPORTED = False
    SUPPORT_ERROR = f"{type(e).__name__}: {e}"
    wa = None  # type: ignore
    handle_pending_subcommand = None  # type: ignore

API_KEY = os.environ.get("WRITE_GATE_BRIDGE_KEY", "")
PORT = int(os.environ.get("WRITE_GATE_PORT", "8643"))
ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,80}$")
SUBSYSTEMS = ("memory", "skills")

_decision_lock = threading.Lock()
_write_lock = threading.Lock()  # global serialization for approve/reject


def _home() -> Path:
    from hermes_constants import get_hermes_home
    return Path(get_hermes_home())


def _iso(ts) -> str | None:
    try:
        return datetime.fromtimestamp(float(ts), tz=timezone.utc).isoformat()
    except Exception:
        return None


def _structured_fields(subsystem: str, rec: dict) -> dict:
    """Structured headline fields (0.36.21 copy-humanization):
    the App builds its Chinese card titles from these fields,
    never from the raw upstream summary string (which is an
    English ops string like "batch(3 ops: patch, ...) on X").
    Everything is extracted here, where the replay payload is
    at hand; values stay raw data (no prose), the App owns the
    wording templates."""
    payload = rec.get("payload") or {}
    op = payload.get("action") or rec.get("action", "")
    out = {"op": op}
    if subsystem == "skills":
        name = payload.get("name")
        if isinstance(name, str) and name:
            out["target_name"] = name
        ops = payload.get("ops") or payload.get("operations")
        if op == "batch" and isinstance(ops, list) and ops:
            out["op_count"] = len(ops)
            kinds = []
            for o in ops:
                if isinstance(o, dict) and isinstance(o.get("action"), str):
                    kinds.append(o["action"])
            if kinds:
                out["op_kinds"] = kinds
            # batch: supplement target_name from operations if top payload lacks it
            if "target_name" not in out:
                names = []
                for o in ops:
                    if isinstance(o, dict):
                        n = o.get("name")
                        if isinstance(n, str) and n:
                            names.append(n)
                unique_names = list(dict.fromkeys(names))
                if len(unique_names) == 1:
                    out["target_name"] = unique_names[0]
            # batch: content_preview from first text-bearing op
            for o in ops:
                if not isinstance(o, dict):
                    continue
                action = o.get("action")
                fields = o
                text = _skill_op_text(action, fields)
                if isinstance(text, str) and text.strip():
                    out["content_preview"] = " ".join(text.split())[:120]
                    break
        if op == "create":
            content = payload.get("content")
            if isinstance(content, str) and content.strip():
                out["content_preview"] = content.strip()[:120]
    elif subsystem == "memory":
        target = payload.get("target")
        if target in ("memory", "user"):
            out["mem_target"] = target
        text = None
        if op in ("add", "create", "replace", "edit", "update"):
            text = payload.get("content")
        elif op in ("remove", "delete"):
            text = payload.get("old_text")
        if isinstance(text, str) and text.strip():
            out["content_preview"] = " ".join(text.split())[:120]
    return out


def _skill_op_text(action, fields: dict):
    """Extract text from a single skill op for content preview."""
    if action in ("create",):
        return fields.get("content")
    if action in ("write_file",):
        return fields.get("file_content") or fields.get("content")
    if action in ("edit",):
        return fields.get("content") or fields.get("new_string")
    if action in ("patch",):
        return fields.get("new_string")
    return None


# --- approval anchor (§128: companion-side temporal correlation) -------------
#
# The upstream staged record carries no session field (contract fact,
# see approval-anchor-spec-20261111.md §1), so the bridge reconstructs
# the originating chat session by correlating the record's created_at
# against sessions/messages in the Hermes state.db, opened read-only.
# Purely additive: every failure mode (no db, no unique candidate,
# tie) yields anchor=None and the App falls back to today's behavior.
# Tier order per spec §3: T0 oneday_app never anchors; T1 = the
# staging tool call itself (memory/skill_manage message within
# ±120s); T3 = background_review + the session that was most
# recently active in messages before created_at (within 1800s).
# A tie at any tier gives up (anchor=None) instead of guessing.
#
# T2 removal (2026-11-11, complexity item 3, user-approved): the
# spec's T2 tier (foreground + exactly one session active around
# created_at) hit 0/25 in the full production decisions history
# and its only eligible origin (foreground) had zero records at
# all; see anchor-t2-evaluation-20261111.md. Foreground records
# without an in-window staging tool call now fall through to
# anchor=None (the standing degrade path: end-of-stream card +
# hub fallback) instead of being guessed at. The root fix
# (staged records carrying the session id) is a Hermes-core
# item; T2 is not to be revived.
#
# T3 signal note (production-verified 2026-11-11): the spec §3
# table phrases T3 via sessions.last_activity_at, but that column
# is stamped at turn wrap-up and routinely lands a few seconds
# AFTER the review's staged created_at, so the literal window
# [created-1800, created] misses the reviewed session (replay:
# 1/4). The spec's own §2 evidence used message activity (±120s),
# which reproduces 4/4 on the same production sample. T3 is
# therefore implemented on message timestamps: most recent last
# message wins, with a ±120s concurrency guard (two target
# sessions active around created_at -> give up).
# Records whose created_at came from the file-mtime fallback
# (created_at_approx) use doubled windows and never earn T1.

import fnmatch
import sqlite3

ANCHOR_EXCLUDE_PATTERNS = (
    "oneday-probe-*",      # acceptance probes (§122 probe family)
    "oneday-verify-*",     # acceptance/seed sessions
    "sync-acceptance*",    # sync acceptance harness
    "audit-*",             # audit harness sessions
    "mcp-devicetest-*",    # connector device-test sessions
)
ANCHOR_TOOL_NAMES = ("memory", "skill_manage")
_ANCHOR_T1_WINDOW = 120.0
_ANCHOR_T3_WINDOW = 1800.0


def _anchor_excluded(session_id: str) -> bool:
    return any(fnmatch.fnmatchcase(session_id, pat)
               for pat in ANCHOR_EXCLUDE_PATTERNS)


class _AnchorResolver:
    """One resolver per request: lazily opens state.db read-only and
    loads the target-session set once, then answers per record."""

    def __init__(self):
        self._conn = None
        self._tried = False
        self._sessions: list[dict] = []

    def _load(self) -> bool:
        if self._tried:
            return self._conn is not None
        self._tried = True
        try:
            db = _home() / "state.db"
            self._conn = sqlite3.connect(
                f"file:{db}?mode=ro", uri=True, timeout=2.0)
            rows = self._conn.execute(
                "SELECT id, started_at, ended_at, last_activity_at"
                " FROM sessions WHERE source='api_server'"
                " AND COALESCE(archived, 0)=0 AND COALESCE(hidden, 0)=0"
            ).fetchall()
            self._sessions = [
                {"id": r[0], "started_at": r[1], "ended_at": r[2],
                 "last_activity_at": r[3]}
                for r in rows if r[0] and not _anchor_excluded(r[0])
            ]
            return True
        except Exception:
            self._conn = None
            self._sessions = []
            return False

    def close(self) -> None:
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
            self._conn = None

    def db_available(self) -> bool:
        """True when state.db could be opened for this request —
        i.e. a verdict computed now rests on actual evidence.
        Callers persisting verdicts (the write-once anchor
        ledger) must not freeze a 'no anchor' that merely means
        'the db was unreachable this once'."""
        return self._load()

    def _sessions_with_message(self, lo: float, hi: float,
                               tool_names=None) -> set:
        if self._conn is None:
            return set()
        ids = {s["id"] for s in self._sessions}
        if not ids:
            return set()
        try:
            if tool_names:
                marks = ",".join("?" for _ in tool_names)
                rows = self._conn.execute(
                    f"SELECT DISTINCT session_id FROM messages"
                    f" WHERE tool_name IN ({marks})"
                    f" AND timestamp BETWEEN ? AND ?",
                    (*tool_names, lo, hi)).fetchall()
            else:
                rows = self._conn.execute(
                    "SELECT DISTINCT session_id FROM messages"
                    " WHERE timestamp BETWEEN ? AND ?",
                    (lo, hi)).fetchall()
        except Exception:
            return set()
        return {r[0] for r in rows if r[0] in ids}

    def anchor_for(self, origin, created, approx: bool):
        """{"sessionId", "tier"} or None. created is epoch seconds."""
        if origin == "oneday_app" or created is None:
            return None  # T0: App-staged proposals have no origin chat
        try:
            created = float(created)
        except Exception:
            return None
        if not self._load():
            return None
        scale = 2.0 if approx else 1.0
        # T1: the staging tool call itself, in exactly one session.
        if not approx:
            w = _ANCHOR_T1_WINDOW
            cand = self._sessions_with_message(
                created - w, created + w, ANCHOR_TOOL_NAMES)
            if len(cand) == 1:
                return {"sessionId": next(iter(cand)), "tier": "T1"}
            if len(cand) > 1:
                return None  # tie: give up rather than guess
        # (T2 removed 2026-11-11 — see the header note above.
        # Foreground records fall through to the T3 origin check,
        # which does not match them, and return None.)
        # T3: background_review — the reviewed session is the one
        # whose last message is most recent before created_at
        # (small forward tolerance: wrap-up messages can land a
        # few seconds after the staged record). Guard: if two
        # target sessions both have messages within ±tol of
        # created_at, the moment is genuinely concurrent — give up.
        if origin == "background_review":
            w = _ANCHOR_T3_WINDOW * scale
            tol = _ANCHOR_T1_WINDOW * scale
            ids = {s["id"] for s in self._sessions}
            last: dict[str, float] = {}
            if self._conn is not None and ids:
                try:
                    rows = self._conn.execute(
                        "SELECT session_id, MAX(timestamp) FROM messages"
                        " WHERE timestamp BETWEEN ? AND ?"
                        " GROUP BY session_id",
                        (created - w, created + tol)).fetchall()
                    last = {r[0]: r[1] for r in rows
                            if r[0] in ids and r[1] is not None}
                except Exception:
                    last = {}
            if not last:
                return None
            near = [sid for sid, ts in last.items()
                    if ts >= created - tol]
            if len(near) > 1:
                return None
            best = max(last.values())
            winners = [sid for sid, ts in last.items() if ts == best]
            if len(winners) == 1:
                return {"sessionId": winners[0], "tier": "T3"}
            return None
        return None


# --- approval anchor write-once ledger (C-5 convergence) ------------------
#
# Until now the anchor was recomputed from state.db on EVERY export
# request. The correlation inputs keep moving (the candidate sessions
# gain new messages), so the same record could anchor to different
# sessions — or lose its anchor to a fresh tie — between two polls,
# while the App freezes placement at first materialization and reads
# the live value again for tap-through: two derivations of one fact,
# free to disagree (overcomplexity audit C-5).
#
# Convergence: the anchor is computed ONCE per record and written
# into a bridge-side ledger (write-gate/anchors.json, {"anchors":
# {"<subsystem>:<id>": {"sessionId","tier"} | null}}). Every export
# surface (pending list, pending detail, decisions) serves the
# ledger value verbatim; the resolver only ever runs for records
# the ledger has never seen. A verdict is frozen only when it rests
# on evidence: origin oneday_app is deterministically anchorless
# (T0), and any other verdict requires state.db to have been
# reachable for that computation — a db outage yields a transient
# null that is NOT persisted, so the record can still earn its
# anchor on a later export. Ledger failures never break an export:
# worst case the response carries the freshly computed value (or
# null) exactly as before this change.

_anchor_ledger_lock = threading.Lock()
_anchor_ledger_cache: dict | None = None


def _anchor_ledger_path() -> Path:
    return _home() / "write-gate" / "anchors.json"


def _anchor_ledger_load() -> dict:
    global _anchor_ledger_cache
    if _anchor_ledger_cache is not None:
        return _anchor_ledger_cache
    data: dict = {}
    try:
        raw = json.loads(
            _anchor_ledger_path().read_text(encoding="utf-8"))
        if isinstance(raw, dict) and isinstance(raw.get("anchors"), dict):
            data = raw["anchors"]
    except Exception:
        data = {}
    _anchor_ledger_cache = data
    return data


def _anchor_ledger_store(key: str, anchor) -> None:
    """Persist a first verdict (caller holds _anchor_ledger_lock
    and has checked the key is absent). Write is atomic (tmp +
    replace); failures are logged, never raised."""
    ledger = _anchor_ledger_load()
    if key in ledger:
        return
    ledger[key] = anchor
    try:
        path = _anchor_ledger_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name("anchors.json.tmp")
        tmp.write_text(
            json.dumps({"anchors": ledger}, ensure_ascii=False),
            encoding="utf-8")
        os.replace(tmp, path)
    except Exception as e:
        print(f"anchor ledger write failed: {e}", file=sys.stderr)


def _anchor_for_record(subsystem: str, rec_id: str, origin,
                       created, approx: bool,
                       resolver: _AnchorResolver | None):
    """The record's anchor: ledger value when the record has been
    seen before, else a fresh computation that is frozen into the
    ledger when it is evidence-based (see header note)."""
    if not rec_id:
        return (resolver.anchor_for(origin, created, approx)
                if resolver is not None else None)
    key = f"{subsystem}:{rec_id}"
    with _anchor_ledger_lock:
        ledger = _anchor_ledger_load()
        if key in ledger:
            return ledger[key]
    anchor = (resolver.anchor_for(origin, created, approx)
              if resolver is not None else None)
    definitive = origin == "oneday_app" or (
        resolver is not None and resolver.db_available())
    if definitive:
        with _anchor_ledger_lock:
            _anchor_ledger_store(key, anchor)
            return _anchor_ledger_load().get(key, anchor)
    return anchor


def _parse_epoch(value):
    """Epoch seconds from a stored created_at (float/int epoch or
    ISO-8601 string); None when unparseable."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except Exception:
            pass
        try:
            return datetime.fromisoformat(
                value.replace("Z", "+00:00")).timestamp()
        except Exception:
            return None
    return None


def _record_head(subsystem: str, rec: dict) -> dict:
    """The record head every export surface shares (C-7
    convergence): pending records and decision-log entries are
    shaped from this one source, then each surface adds its own
    fields (created_at / decided_at / decision / anchor ...).
    Until now the same five fields were assembled twice, in
    _norm_record and in _append_decision."""
    return {
        "id": rec.get("id", ""),
        "subsystem": subsystem,
        "action": rec.get("action", ""),
        "summary": rec.get("summary", ""),
        "origin": rec.get("origin", "foreground"),
    }


def _norm_record(subsystem: str, rec: dict, include_payload: bool,
                 resolver: _AnchorResolver | None = None) -> dict:
    out = _record_head(subsystem, rec)
    out.update(_structured_fields(subsystem, rec))
    created = rec.get("created_at")
    approx = False
    if created is None:
        try:
            created = wa._pending_path(subsystem, rec.get("id", "")).stat().st_mtime
            approx = True
        except Exception:
            created = None
    out["created_at"] = _iso(created) if created is not None else None
    if approx:
        out["created_at_approx"] = True
    if resolver is not None:
        out["anchor"] = _anchor_for_record(
            subsystem, rec.get("id", ""), out["origin"],
            _parse_epoch(created), approx, resolver)
    reason = _blocked_reason(subsystem, rec)
    if reason:
        # B-05 single reason field (1.0.63): the phase tag says
        # which stage produced the reason; presentation reads
        # exactly one place. The decide response's execution
        # twin is in _decide.
        out["reason"] = reason
        out["reason_phase"] = "pre-check"
    if include_payload:
        out["payload"] = rec.get("payload", {})
    return out


def _gate_state() -> dict:
    if not SUPPORTED:
        return {"memory": False, "skills": False}
    return {
        "memory": bool(wa.write_approval_enabled(wa.MEMORY)),
        "skills": bool(wa.write_approval_enabled(wa.SKILLS)),
    }


def _counts() -> dict:
    if not SUPPORTED:
        return {"memory": 0, "skills": 0}
    return {
        "memory": wa.pending_count(wa.MEMORY),
        "skills": wa.pending_count(wa.SKILLS),
    }


# --- review construction ---------------------------------------------------

def _memory_review(rec: dict) -> dict:
    payload = rec.get("payload", {})
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    return {
        "subsystem": "memory",
        "targetLabel": "memory",
        "language": "json",
        "current": "",
        "proposed": text,
        "diff": text,
        "notes": [],
    }


def _skills_review(rec: dict) -> dict:
    payload = rec.get("payload", {})
    action = payload.get("action", "")
    name = payload.get("name", "")
    diff = wa.skill_pending_diff(rec)
    notes: list[dict] = []
    requested_old = None

    if action == "delete":
        target_label = name
        language, current, proposed = "diff", "", ""
        notes.append({"type": "deleteSkill", "skillName": name})
    elif action == "remove_file":
        target_label = payload.get("file_path") or "SKILL.md"
        language, current, proposed = "diff", "", ""
        notes.append({"type": "removeFile", "targetLabel": target_label})
    elif action == "batch":
        target_label, language, current, proposed = "SKILL.md", "diff", "", ""
    elif action == "create":
        target_label, language = "SKILL.md", "markdown"
        current, proposed = "", payload.get("content") or ""
    elif action == "edit":
        target_label, language = "SKILL.md", "diff"
        current = wa._staged_base(name, target_label, None)
        proposed = payload.get("content") or ""
    elif action == "write_file":
        target_label = payload.get("file_path") or "SKILL.md"
        language = "diff"
        current = wa._staged_base(name, target_label, None)
        proposed = payload.get("file_content") or ""
    elif action == "patch":
        target_label = payload.get("file_path") or "SKILL.md"
        language = "diff"
        current = wa._staged_base(name, target_label, None)
        folded, err = wa._fold_patch(
            current, payload.get("old_string") or "",
            payload.get("new_string") or "", payload.get("replace_all"))
        proposed = folded if err is None else ""
        if err is not None or (diff or "").startswith("(patch would fail"):
            notes.append({"type": "patchOldStringMissing", "targetLabel": target_label})
            requested_old = payload.get("old_string") or ""
    else:
        target_label, language, current, proposed = "SKILL.md", "diff", "", ""

    review = {
        "subsystem": "skills",
        "targetLabel": target_label,
        "language": language,
        "current": current,
        "proposed": proposed,
        "diff": diff,
        "notes": notes,
    }
    if requested_old:
        review["requestedOldString"] = requested_old
    return review


# --- decisions log ----------------------------------------------------------

def _append_jsonl(name: str, entry: dict) -> None:
    """The write-gate's single JSONL append pipeline (C-7
    convergence): decisions and decide-attempts are written
    through this one function -- same lock, same one-line
    format. The FILES stay separate on purpose: the overview
    bridge mints one notification per decisions.jsonl line, so
    failed attempts must never land in that stream (they would
    surface as phantom 'already handled' receipts)."""
    try:
        d = _home() / "write-gate"
        d.mkdir(parents=True, exist_ok=True)
        with _decision_lock:
            with open(d / name, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False)
                        + "\n")
    except Exception as e:
        print(f"{name} write failed: {e}", file=sys.stderr)


def _append_decision(rec: dict, subsystem: str, decision: str,
                     via_rule: str | None = None) -> None:
    entry = _record_head(subsystem, rec)
    entry["created_at"] = _iso(rec.get("created_at"))
    entry["decided_at"] = datetime.now(tz=timezone.utc).isoformat()
    entry["decision"] = decision
    # History rows get the same structured headline fields as
    # pending records, so decided entries render the same
    # human titles instead of the raw summary string.
    entry.update(_structured_fields(subsystem, rec))
    if via_rule:
        # Rule-based auto-approval (0.36.21 approval-card package):
        # the decision value stays "approved"; via_rule carries the
        # rule id so history/panel can show 「按规则放行」 honestly.
        entry["via_rule"] = via_rule
    _append_jsonl("decisions.jsonl", entry)


def _read_decisions(limit: int) -> list[dict]:
    p = _home() / "write-gate" / "decisions.jsonl"
    if not p.exists():
        return []
    rows = []
    try:
        for line in p.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except Exception:
                    pass
    except Exception:
        return []
    rows.reverse()  # newest first
    return rows[:limit]


# --- always-allow rules (0.36.21 approval-card package) -----------------------
#
# Persistent rules keyed by (subsystem, origin): a newly staged write
# whose key matches a rule is approved automatically through the exact
# same decide path as a manual approval, and the decision log line
# carries via_rule=<rule id> so the auto-approval is traceable,
# never silent.
# Rules live bridge-side only (<HERMES_HOME>/write-gate/rules.json);
# the App never stores them. Revocation is a first-class endpoint —
# no rule surface ships without it.
#
# Hook point: staging happens inside Hermes (wa.stage_write), not
# through this bridge, so matching runs as a sweep — on every
# /pending and /status read, plus a background thread — rather than
# at stage time. A record the App already displays may therefore be
# decided between two polls; the App reconciles that against
# /decisions (via_rule) instead of treating it as vanished.

_rules_lock = threading.Lock()


def _rules_path() -> Path:
    return _home() / "write-gate" / "rules.json"


def _rule_id(subsystem: str, origin: str) -> str:
    digest = hashlib.sha256(
        f"{subsystem}\x00{origin}".encode("utf-8")).hexdigest()
    return "rule_" + digest[:16]


def _load_rules() -> list[dict]:
    try:
        data = json.loads(_rules_path().read_text(encoding="utf-8"))
    except Exception:
        return []
    rows = data.get("rules", []) if isinstance(data, dict) else []
    out = []
    for r in rows:
        if not isinstance(r, dict):
            continue
        sub, origin = r.get("subsystem"), r.get("origin")
        if sub not in SUBSYSTEMS or not isinstance(origin, str) or not origin:
            continue
        out.append({
            "id": r.get("id") or _rule_id(sub, origin),
            "subsystem": sub,
            "origin": origin,
            "created_at": r.get("created_at"),
        })
    return out


def _save_rules(rules: list[dict]) -> None:
    p = _rules_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(
        json.dumps({"rules": rules}, ensure_ascii=False, indent=2),
        encoding="utf-8")
    tmp.replace(p)  # atomic rename: a crash mid-write keeps the old file


def _add_rule(subsystem: str, origin: str):
    """Idempotent create. Returns (rule, created)."""
    with _rules_lock:
        rules = _load_rules()
        for r in rules:
            if r["subsystem"] == subsystem and r["origin"] == origin:
                return r, False
        rule = {
            "id": _rule_id(subsystem, origin),
            "subsystem": subsystem,
            "origin": origin,
            "created_at": datetime.now(tz=timezone.utc).isoformat(),
        }
        rules.append(rule)
        _save_rules(rules)
        return rule, True


def _remove_rule(rule_id: str) -> bool:
    with _rules_lock:
        rules = _load_rules()
        kept = [r for r in rules if r["id"] != rule_id]
        if len(kept) == len(rules):
            return False
        _save_rules(kept)
        return True


def _match_rule(rules: list[dict], subsystem: str, origin: str):
    for r in rules:
        if r["subsystem"] == subsystem and r["origin"] == origin:
            return r
    return None


def _apply_decision(sub: str, rec: dict, action_word: str,
                    via_rule: str | None = None):
    """Replay one decision through the upstream pending handler.
    Caller must hold _write_lock. Success is proven the same way as
    the HTTP path: the record is gone afterwards. Returns
    (success, output)."""
    memory_store = None
    if sub == "memory":
        from tools.memory_tool import load_on_disk_store
        memory_store = load_on_disk_store()
    output = handle_pending_subcommand(
        sub, [action_word, rec.get("id", "")], memory_store=memory_store)
    still_there = wa.get_pending(sub, rec.get("id", "")) is not None
    success = not still_there
    if success:
        decision = "approved" if action_word == "approve" else "rejected"
        _append_decision(rec, sub, decision, via_rule=via_rule)
    return success, output or ""


def _cap_reason(reason) -> str | None:
    """The one reason normalization (C-7 convergence, B-05
    single field): every reason the bridge surfaces -- the
    pending record's pre-check reason and the decide response's
    execution reason -- is capped at 500 chars through here and
    rides the single `reason` field with a `reason_phase` tag
    ("pre-check" / "execution"), so presentation never has to
    guess which of two fields to read."""
    if not reason:
        return None
    return str(reason)[:500] or None


def _failure_reason(output: str, pid: str) -> str | None:
    """The upstream approve handler reports per-record failures as
    a 'Failed:' section with '  <id>: <reason>' lines. Pull this
    record's reason out so a failed decide can tell the caller WHY
    (1.0.29: until now the reason rode only in the free-text output
    and the App could only show a generic 'decision did not take
    effect' line — production case 62927061, 2026-11-11)."""
    if not output:
        return None
    in_failed = False
    for line in output.splitlines():
        if line.strip() == "Failed:":
            in_failed = True
            continue
        if in_failed:
            stripped = line.strip()
            if stripped.startswith(pid + ":"):
                return _cap_reason(stripped[len(pid) + 1:].strip())
            if stripped and not line.startswith((" ", "\t")):
                break
    return None


def _append_attempt(rec: dict, subsystem: str, action_word: str,
                    reason: str | None) -> None:
    """Metadata-only log of FAILED decide attempts (companion
    1.0.29). decisions.jsonl stays decided-only (overview reads it
    as the decided ledger); failed attempts get their own file so
    a 'decision did not take effect' report is traceable after the
    fact instead of living only in one HTTP response."""
    entry = {
        "id": rec.get("id", ""),
        "subsystem": subsystem,
        "action": rec.get("action", ""),
        "origin": rec.get("origin", "foreground"),
        "attempted_decision": (
            "approved" if action_word == "approve" else "rejected"),
        "attempted_at": datetime.now(tz=timezone.utc).isoformat(),
        "result": "failed",
        "reason": reason,
        "reason_phase": "execution",
    }
    _append_jsonl("decide-attempts.jsonl", entry)


def _blocked_reason(subsystem: str, rec: dict) -> str | None:
    """Deterministic-replay pre-check for skills 'create' ops
    (companion 1.0.29). Upstream staging does NOT run the write
    guards; the description budget / frontmatter / size checks run
    only inside _guarded_write at apply time, so a record can be
    staged that can NEVER be approved (production case 62927061:
    82-char description vs the 60-char skill-index budget — every
    approve attempt failed identically and the record stayed
    pending forever). Recompute the same pure validators the
    applier runs and surface the reason on the record so clients
    can present 'this cannot be approved: <reason>' instead of a
    live-looking decide button. Any doubt -> None (no field):
    this is advisory, the decide path stays the only authority."""
    if subsystem != "skills":
        return None
    try:
        from tools import skill_manager_tool as sm
    except Exception:
        return None
    payload = rec.get("payload") or {}
    ops = []
    if payload.get("action") == "batch":
        raw = payload.get("operations") or payload.get("ops") or []
        ops = [o for o in raw if isinstance(o, dict)]
    elif payload.get("action"):
        ops = [payload]
    for o in ops:
        if o.get("action") != "create":
            continue
        name = o.get("name") or ""
        content = o.get("content") or ""
        try:
            err = (sm._validate_name(name)
                   or sm._validate_category(o.get("category"))
                   or sm._validate_frontmatter(content)
                   or sm._validate_content_size(content)
                   or sm._description_budget_error(content, before=None))
            if not err and sm._find_skill(name):
                err = f"A skill named '{name}' already exists."
        except Exception:
            return None
        if err:
            return _cap_reason(str(err))
    return None


def _sweep_rules() -> int:
    """Auto-approve every pending record whose (subsystem, origin)
    matches a rule. Returns how many were approved. No-op when the
    gate modules are unavailable or no rules exist."""
    if not SUPPORTED:
        return 0
    rules = _load_rules()
    if not rules:
        return 0
    approved = 0
    with _write_lock:
        for sub in SUBSYSTEMS:
            for rec in wa.list_pending(sub):
                origin = rec.get("origin") or "foreground"
                rule = _match_rule(rules, sub, origin)
                if rule is None:
                    continue
                try:
                    ok, _ = _apply_decision(
                        sub, rec, "approve", via_rule=rule["id"])
                except Exception as e:
                    print(f"rule sweep failed for {sub}/{rec.get('id')}: {e}",
                          file=sys.stderr)
                    continue
                if ok:
                    approved += 1
    return approved


# --- activity grouping (task-level human presentation) ----------------------

_ACTIVITY_VERBS = {
    "patch": "修改了", "edit": "修改了", "edit_file": "修改了",
    "write_file": "写入了", "create": "新建了", "add": "新增了",
    "replace": "替换了", "remove": "删除了", "delete": "删除了",
}


def _activity_object_label(rec):
    """Object label from one record's structured fields."""
    subsystem = rec.get("subsystem", "")
    if subsystem == "skills":
        target_name = rec.get("target_name")
        if target_name:
            return f"技能《{target_name}》"
        return "技能"
    elif subsystem == "memory":
        mem_target = rec.get("mem_target")
        if mem_target == "user":
            return "用户档案"
        return "长期记忆"
    return None


def _group_title_human(members):
    """Human title for a group: members already sorted newest first."""
    if not members:
        return "一项写入"
    verbs = set()
    for rec in members:
        op_kinds = rec.get("op_kinds")
        if isinstance(op_kinds, list):
            for k in op_kinds:
                v = _ACTIVITY_VERBS.get(k)
                if v:
                    verbs.add(v)
        else:
            op = rec.get("op", "")
            v = _ACTIVITY_VERBS.get(op)
            if v:
                verbs.add(v)
    objects = []
    for rec in members:
        obj = _activity_object_label(rec)
        if obj:
            objects.append(obj)
    unique_objs = list(dict.fromkeys(objects))
    if len(unique_objs) == 1:
        obj = unique_objs[0]
        if len(verbs) == 1:
            return f"{next(iter(verbs))} {obj}"
        else:
            return f"更新了 {obj}"
    elif len(unique_objs) > 1:
        verb = next(iter(verbs)) if len(verbs) == 1 else "更新了"
        first_obj = objects[0] if objects else unique_objs[0]
        return f"{verb} {first_obj} 等 {len(members)} 项"
    else:
        all_skills = all(rec.get("subsystem") == "skills" for rec in members)
        all_memory = all(rec.get("subsystem") == "memory" for rec in members)
        if all_skills:
            return "技能写入"
        elif all_memory:
            return "记忆写入"
        return "一项写入"


def list_activity(limit_raw, grouped_raw):
    """GET /activity?limit=N&grouped=0/1 → (status, payload)."""
    if not SUPPORTED:
        return 409, {"error": f"write gate unsupported: {SUPPORT_ERROR}"}
    _sweep_rules()

    # pending records
    pending = []
    resolver = _AnchorResolver()
    try:
        for sub in SUBSYSTEMS:
            for rec in wa.list_pending(sub):
                normed = _norm_record(sub, rec, include_payload=False, resolver=resolver)
                normed["state"] = "pending"
                pending.append(normed)

        # decisions
        try:
            limit = int(limit_raw) if limit_raw else 50
        except Exception:
            limit = 50
        limit = max(1, min(limit, 200))
        decisions = []
        for row in _read_decisions(limit):
            row["anchor"] = _anchor_for_record(
                row.get("subsystem", ""), row.get("id", ""),
                row.get("origin", "foreground"),
                _parse_epoch(row.get("created_at")),
                False, resolver)
            row["state"] = "decided"
            decisions.append(row)
    finally:
        resolver.close()

    # check grouping mode
    if grouped_raw in ("0", "false", "no") or os.environ.get("ONEDAY_WG_ACTIVITY_GROUPING") == "off":
        merged = pending + decisions
        merged.sort(key=lambda r: _parse_epoch(r.get("decided_at") or r.get("created_at")) or 0, reverse=True)
        return 200, {
            "groups": [],
            "grouped": False,
            "records": merged,
            "counts": _counts(),
            "supported": SUPPORTED
        }

    # grouping mode
    from collections import defaultdict
    groups_dict = defaultdict(list)
    for rec in pending + decisions:
        anchor = rec.get("anchor")
        if anchor and isinstance(anchor, dict):
            sid = anchor.get("sessionId")
            if sid:
                key = f"session:{sid}"
            else:
                key = f"record:{rec.get('subsystem', '')}:{rec.get('id', '')}"
        else:
            key = f"record:{rec.get('subsystem', '')}:{rec.get('id', '')}"
        groups_dict[key].append(rec)

    groups = []
    for key, members in groups_dict.items():
        members.sort(key=lambda r: _parse_epoch(r.get("decided_at") or r.get("created_at")) or 0, reverse=True)

        sid = key.split(":", 1)[1] if key.startswith("session:") else None
        first_anchor = None
        for m in members:
            a = m.get("anchor")
            if a and isinstance(a, dict):
                first_anchor = a
                break
        tier = first_anchor.get("tier") if first_anchor else None

        title = _group_title_human(members)
        preview = None
        for m in members:
            p = m.get("content_preview")
            if p:
                preview = p
                break

        has_pending = any(m.get("state") == "pending" for m in members)
        has_rejected = any(m.get("decision") == "rejected" for m in members)
        if has_pending:
            status = "pending"
        elif has_rejected:
            status = "failed"
        else:
            status = "completed"

        counts = {
            "pending": sum(1 for m in members if m.get("state") == "pending"),
            "approved": sum(1 for m in members if m.get("decision") == "approved"),
            "rejected": sum(1 for m in members if m.get("decision") == "rejected"),
            "total": len(members)
        }

        created_times = [_parse_epoch(m.get("created_at")) for m in members]
        created_times = [t for t in created_times if t is not None]
        created_at = min(created_times) if created_times else 0.0

        updated_times = [_parse_epoch(m.get("decided_at") or m.get("created_at")) for m in members]
        updated_times = [t for t in updated_times if t is not None]
        updated_at = max(updated_times) if updated_times else 0.0

        groups.append({
            "id": key,
            "session_id": sid,
            "tier": tier,
            "title_human": title,
            "preview": preview,
            "status": status,
            "counts": counts,
            "created_at": _iso(created_at),
            "updated_at": _iso(updated_at),
            "records": members
        })

    groups.sort(key=lambda g: _parse_epoch(g.get("updated_at")) or 0, reverse=True)

    return 200, {
        "groups": groups,
        "grouped": True,
        "counts": _counts(),
        "supported": SUPPORTED
    }


def _sweep_rules() -> int:
    """Auto-approve every pending record whose (subsystem, origin)
    matches a rule. Returns how many were approved. No-op when the
    gate modules are unavailable or no rules exist."""
    if not SUPPORTED:
        return 0
    rules = _load_rules()
    if not rules:
        return 0
    approved = 0
    with _write_lock:
        for sub in SUBSYSTEMS:
            for rec in wa.list_pending(sub):
                origin = rec.get("origin") or "foreground"
                rule = _match_rule(rules, sub, origin)
                if rule is None:
                    continue
                try:
                    ok, _ = _apply_decision(
                        sub, rec, "approve", via_rule=rule["id"])
                except Exception as e:
                    print(f"rule sweep failed for {sub}/{rec.get('id')}: {e}",
                          file=sys.stderr)
                    continue
                if ok:
                    approved += 1
    return approved


def _rules_sweeper_loop() -> None:
    while True:
        time.sleep(5)
        try:
            _sweep_rules()
        except Exception as e:
            print(f"rule sweeper error: {e}", file=sys.stderr)


# --- memory entries (P7 contract §2) -----------------------------------------

MEM_ENTRY_ID_RE = re.compile(r"^mem_[0-9a-f]{16}$")
MEM_ORIGIN = "oneday_app"


def _entry_digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _mem_snapshot():
    """All current entries via the on-disk store, plus the store itself.

    Order per contract §2.2: memory target first, then user, each in file
    order. ``updatedAt`` is the containing file's mtime (entries carry no
    per-entry timestamp upstream); ``id`` is content-addressed, so two
    entries with identical text share an id and update/delete hit the
    first — the same match-by-text semantics as the store itself.
    """
    from tools.memory_tool import load_on_disk_store, get_memory_dir
    store = load_on_disk_store()
    mem_dir = get_memory_dir()
    entries = []
    for target, texts in (("memory", store.memory_entries),
                          ("user", store.user_entries)):
        path = mem_dir / ("USER.md" if target == "user" else "MEMORY.md")
        try:
            mtime = path.stat().st_mtime
        except Exception:
            mtime = 0.0
        for text in texts:
            digest = _entry_digest(text)
            title = ""
            for line in text.splitlines():
                if line.strip():
                    title = line.strip()
                    break
            entries.append({
                "id": "mem_" + digest[:16],
                "target": target,
                "title": title[:60],
                "summary": " ".join(text.split())[:120],
                "updatedAt": mtime,
                "digest": digest,
                "_text": text,
            })
    return entries, store


def _entry_public(e: dict, detail: bool = False) -> dict:
    out = {k: e[k] for k in ("id", "target", "title", "summary",
                             "updatedAt", "digest")}
    if detail:
        out["content"] = e["_text"]
    return out


def _mem_summary_for(operation: str, target: str, content, old_text) -> str:
    """Same staged-summary shape the memory tool produces: its per-action
    (summary, detail) text joined as f"{summary}: {detail[:120]}"."""
    label = "user profile" if target == "user" else "memory"
    if operation == "create":
        head, detail = f"add to {label}", content or ""
    elif operation == "update":
        head = f"replace in {label}"
        detail = f"entry matching: {old_text}\nwhole entry becomes: {content}"
    else:  # delete
        head, detail = f"remove from {label}", old_text or ""
    return f"{head}: {detail[:120]}"


def _propose_memory(body: dict):
    """Validate and stage one App-initiated memory write. Returns
    (status, response_dict). Staging goes through wa.stage_write — the
    internal the memory tool itself uses — so the record is handled by
    the existing pending/decide flow unchanged."""
    if not SUPPORTED:
        return 409, {"error": f"write gate unsupported: {SUPPORT_ERROR}"}
    operation = body.get("operation")
    target = body.get("target")
    if operation not in ("create", "update", "delete"):
        return 400, {"error": "operation 不合法"}
    if target not in ("memory", "user"):
        return 400, {"error": "target 不合法"}
    if not wa.write_approval_enabled(wa.MEMORY):
        return 409, {"error": "记忆写入审批未启用，暂时不能提交"}
    content = body.get("content")
    if operation in ("create", "update"):
        if not isinstance(content, str) or not content.strip():
            return 400, {"error": "内容不能为空"}
    entries, store = _mem_snapshot()
    if operation == "create":
        payload = {"action": "add", "target": target,
                   "content": content, "old_text": None}
        old_text = None
    else:
        entry_id = body.get("entryId")
        if not isinstance(entry_id, str) or not entry_id:
            return 400, {"error": "缺少 entryId"}
        base = body.get("baseDigest")
        if not isinstance(base, str) or not base:
            return 400, {"error": "缺少 baseDigest"}
        entry = next((e for e in entries
                      if e["id"] == entry_id and e["target"] == target), None)
        if entry is None:
            return 404, {"error": "这条记忆已不存在"}
        if base != entry["digest"]:
            return 409, {"error": "这条记忆已经变了，请刷新后重新编辑"}
        old_text = entry["_text"]
        verb = "replace" if operation == "update" else "remove"
        payload = {"action": verb, "target": target,
                   "content": content if operation == "update" else None,
                   "old_text": old_text}
        # Pin the exact entry being reviewed, mirroring the memory tool's
        # _pin_matched_entries, so approval replays onto this entry and
        # refuses if it changed underneath.
        result = store.resolve_entry(target, old_text, verb)
        if not result.get("success"):
            return 409, {"error": result.get("error") or result.get("message")
                         or "这条记忆已经变了，请刷新后重新编辑"}
        payload["matched_entry"] = result["matched_entry"]
    summary = _mem_summary_for(operation, target, content, old_text)
    with _write_lock:
        record = wa.stage_write(wa.MEMORY, payload, summary=summary,
                                origin=MEM_ORIGIN)
        if wa.get_pending(wa.MEMORY, record["id"]) is None:
            return 500, {"error": "暂存失败，请稍后再试"}
    return 201, {"pendingId": record["id"], "operation": operation,
                 "target": target}


# --- HTTP layer --------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "write-gate-bridge/1.0"

    def log_message(self, fmt, *args):  # method/path/status only
        try:
            status = args[1] if len(args) > 1 else "-"
        except Exception:
            status = "-"
        print(f"{self.command} {self.path} -> {status}", file=sys.stderr)

    # helpers
    def _send(self, code: int, obj: dict):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authed(self) -> bool:
        header = self.headers.get("Authorization", "")
        expected = f"Bearer {API_KEY}"
        return bool(API_KEY) and hmac.compare_digest(header, expected)

    def _read_body(self) -> bytes:
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except Exception:
            n = 0
        if n > 0:
            return self.rfile.read(min(n, 1 << 20))
        return b""

    # routing
    def do_GET(self):
        if not self._authed():
            return self._send(401, {"error": "unauthorized"})
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        try:
            if parts == ["status"]:
                _sweep_rules()
                return self._send(200, {
                    "supported": SUPPORTED,
                    "gate": _gate_state(),
                    "counts": _counts(),
                })
            if parts == ["rules"]:
                # Bridge-local state: readable even when the gate
                # modules are unavailable (rules take effect only
                # once the gate is supported again).
                return self._send(200, {"rules": _load_rules()})
            if parts == ["pending"]:
                if not SUPPORTED:
                    return self._send(409, {"error": f"write gate unsupported: {SUPPORT_ERROR}"})
                _sweep_rules()
                records = []
                resolver = _AnchorResolver()
                try:
                    for sub in SUBSYSTEMS:
                        for rec in wa.list_pending(sub):
                            records.append(_norm_record(
                                sub, rec, include_payload=False,
                                resolver=resolver))
                finally:
                    resolver.close()
                records.sort(key=lambda r: r.get("created_at") or "")
                return self._send(200, {
                    "records": records, "counts": _counts(), "supported": SUPPORTED})
            if parts == ["decisions"]:
                qs = parse_qs(urlparse(self.path).query)
                try:
                    limit = int(qs.get("limit", ["50"])[0])
                except Exception:
                    limit = 50
                limit = max(1, min(limit, 200))
                rows = _read_decisions(limit)
                resolver = _AnchorResolver()
                try:
                    for row in rows:
                        row["anchor"] = _anchor_for_record(
                            row.get("subsystem", ""), row.get("id", ""),
                            row.get("origin", "foreground"),
                            _parse_epoch(row.get("created_at")),
                            False, resolver)
                finally:
                    resolver.close()
                return self._send(200, {"decisions": rows})
            if parts == ["activity"]:
                qs = parse_qs(urlparse(self.path).query)
                limit = qs.get("limit", [None])[0]
                grouped = qs.get("grouped", [None])[0]
                status, payload = list_activity(limit, grouped)
                return self._send(status, payload)
            if len(parts) == 3 and parts[0] == "pending":
                sub, pid = parts[1], parts[2]
                if sub not in SUBSYSTEMS or not ID_RE.match(pid):
                    return self._send(400, {"error": "invalid subsystem or id"})
                if not SUPPORTED:
                    return self._send(409, {"error": f"write gate unsupported: {SUPPORT_ERROR}"})
                rec = wa.get_pending(sub, pid)
                if rec is None:
                    return self._send(404, {"error": "pending record not found"})
                review = _memory_review(rec) if sub == "memory" else _skills_review(rec)
                resolver = _AnchorResolver()
                try:
                    record = _norm_record(sub, rec, include_payload=True,
                                          resolver=resolver)
                finally:
                    resolver.close()
                return self._send(200, {
                    "record": record,
                    "review": review})
            if parts == ["memories"]:
                if not SUPPORTED:
                    return self._send(409, {"error": f"write gate unsupported: {SUPPORT_ERROR}"})
                entries, _store = _mem_snapshot()
                return self._send(200, {
                    "entries": [_entry_public(e) for e in entries],
                    "generatedAt": time.time()})
            if len(parts) == 2 and parts[0] == "memories":
                if not SUPPORTED:
                    return self._send(409, {"error": f"write gate unsupported: {SUPPORT_ERROR}"})
                if not MEM_ENTRY_ID_RE.match(parts[1]):
                    return self._send(404, {"error": "这条记忆已不存在"})
                entries, _store = _mem_snapshot()
                entry = next((e for e in entries if e["id"] == parts[1]), None)
                if entry is None:
                    return self._send(404, {"error": "这条记忆已不存在"})
                return self._send(200, {"entry": _entry_public(entry, detail=True)})
            return self._send(404, {"error": "not found"})
        except Exception as e:
            return self._send(500, {"error": f"{type(e).__name__}: {e}"})

    def do_POST(self):
        raw = self._read_body()
        if not self._authed():
            return self._send(401, {"error": "unauthorized"})
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        try:
            if parts == ["rules"]:
                try:
                    body = json.loads(raw.decode("utf-8")) if raw else {}
                except Exception:
                    return self._send(400, {"error": "请求体不是合法 JSON"})
                if not isinstance(body, dict):
                    return self._send(400, {"error": "请求体不合法"})
                sub = body.get("subsystem")
                origin = body.get("origin")
                if sub not in SUBSYSTEMS:
                    return self._send(400, {"error": "subsystem 不合法"})
                if (not isinstance(origin, str) or not origin.strip()
                        or len(origin) > 200
                        or any(ord(c) < 32 for c in origin)):
                    return self._send(400, {"error": "origin 不合法"})
                rule, created = _add_rule(sub, origin.strip())
                return self._send(201 if created else 200, {"rule": rule})
            if parts == ["memories", "propose"]:
                try:
                    body = json.loads(raw.decode("utf-8")) if raw else {}
                except Exception:
                    return self._send(400, {"error": "请求体不是合法 JSON"})
                if not isinstance(body, dict):
                    return self._send(400, {"error": "请求体不合法"})
                code, obj = _propose_memory(body)
                return self._send(code, obj)
            if len(parts) == 4 and parts[0] == "pending" and parts[3] in ("approve", "reject"):
                sub, pid, action_word = parts[1], parts[2], parts[3]
                if sub not in SUBSYSTEMS or not ID_RE.match(pid):
                    return self._send(400, {"error": "invalid subsystem or id"})
                if not SUPPORTED:
                    return self._send(409, {"error": f"write gate unsupported: {SUPPORT_ERROR}"})
                return self._decide(sub, pid, action_word)
            return self._send(404, {"error": "not found"})
        except Exception as e:
            return self._send(500, {"error": f"{type(e).__name__}: {e}"})

    def do_DELETE(self):
        if not self._authed():
            return self._send(401, {"error": "unauthorized"})
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        try:
            if len(parts) == 2 and parts[0] == "rules":
                if not ID_RE.match(parts[1]):
                    return self._send(400, {"error": "invalid rule id"})
                if _remove_rule(parts[1]):
                    return self._send(200, {"success": True})
                return self._send(404, {"error": "rule not found"})
            return self._send(404, {"error": "not found"})
        except Exception as e:
            return self._send(500, {"error": f"{type(e).__name__}: {e}"})

    def _decide(self, sub: str, pid: str, action_word: str):
        with _write_lock:
            rec = wa.get_pending(sub, pid)
            if rec is None:
                return self._send(404, {"error": "pending record not found"})
            success, output = _apply_decision(sub, rec, action_word)
            decision = "approved" if action_word == "approve" else "rejected"
            resp = {
                "success": success,
                "output": output,
                "decision": decision,
            }
            if not success:
                reason = _failure_reason(output, pid)
                resp["reason"] = reason
                resp["reason_phase"] = "execution"
                _append_attempt(rec, sub, action_word, reason)
            return self._send(200, resp)


def main():
    if not API_KEY:
        print("WRITE_GATE_BRIDGE_KEY is not set; refusing to start (fail-closed).", file=sys.stderr)
        return 2
    if not SUPPORTED:
        print(f"WARNING: write gate modules unavailable: {SUPPORT_ERROR}; "
              "serving fail-closed (writes -> 409).", file=sys.stderr)
    sweeper = threading.Thread(
        target=_rules_sweeper_loop, name="write-gate-rule-sweeper",
        daemon=True)
    sweeper.start()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    print(f"write-gate-bridge listening on :{PORT} supported={SUPPORTED}", file=sys.stderr)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
