"""Work-ledger core for the oneday bridge (design:
work-ledger-design-20261110.md).

The ledger is the bridge's own book of "what work happened":
items are units of work (one run / one kanban task / one bridge
job / one approval / one standalone device call), NOT sessions.
One writing discipline feeds it (C-4 convergence, 2026-11-14):
events reported directly by their owner at the moment they
happen -- the App's run reports, bridge-self job records, and
two append-only event files (write-gate decisions, device audit)
whose owners append at event time and which the Collector below
consumes in order. There is no reconciler: nothing scans foreign
state and merges it into the book. Terminal states are only ever
set from a direct report.

Fold rule (B-02 convergence, 2026-11-15): the snapshot is a
single fold over the event log IN EVENT ORDER. Every producer --
the App channel, bridge-self records, the Collector -- only
appends events; a later event is the current fact, full stop.
There is no field-priority merge and no evidence ranking in the
storage layer: the EVIDENCE_RANK / TITLE_RANK tables that used
to adjudicate terminal conflicts and title replacements are
retired. titleSource survives as a provenance label only. A
terminal state can still be corrected, but only by a later
direct report landing later in the log, and the correction is
written into the item history -- never by a rank comparison.

Storage: append-only JSONL event log (spec 5.4). One line per
event (created / status / evidence / updated / cursor / meta /
baseline). Startup replays the log into an in-memory snapshot.
A corrupt line quarantines the whole file to
``<name>.corrupt-<timestamp>`` (never deleted), the snapshot is
built from the replayable prefix, the store runs degraded
(writes refused, reads served) and the prefix is written back
to a fresh log so appends can continue -- the original bytes
survive under the quarantine name, so nothing is ever
overwritten by an empty book.

This module is deliberately free of HTTP and of any Hermes
client code, which is what makes the event ingestion and the
zombie ladder unit-testable with a fake clock.
"""

from __future__ import annotations

import json
import os
import re
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path

STATUSES = ("queued", "running", "blocked_approval", "completed",
            "failed", "cancelled", "stale")
TERMINAL = frozenset({"completed", "failed", "cancelled"})
ACTIVE = frozenset({"queued", "running", "blocked_approval"})

# Round-end statuses that mean "the round's deliverables are
# the whole story" (§475 part 2, delivery-point settlement):
# ok / empty / partial all land the job completed on the live
# finish path, and "full" (ideas pool already at water level,
# nothing owed) joins them -- before part 2 it fell through
# to classify_failure and a pool-full round booked as FAILED.
# One shared table so the live finish path and the boot-time
# orphan settlement can never drift apart again.
DELIVERY_CONSISTENT_STATUSES = frozenset(
    {"ok", "empty", "partial", "full"})

# (EVIDENCE_RANK retired in the B-02 convergence, 2026-11-15:
# the fold is by event order now -- see the module docstring.
# terminalRank values persisted in old event logs stay readable
# on replay for history continuity, never interpreted.)

ALLOWED = {
    "queued": ACTIVE | TERMINAL | {"stale"},
    "running": ACTIVE | TERMINAL | {"stale"},
    "blocked_approval": ACTIVE | TERMINAL | {"stale"},
    # stale is a reversible non-terminal: revive to an active
    # state, or settle to a terminal one on transcript evidence.
    "stale": ACTIVE | TERMINAL,
    "completed": frozenset(),
    "failed": frozenset(),
    "cancelled": frozenset(),
}

FAIL_CATEGORIES = ("上游出错", "超时", "被审批中止", "用户停止",
                   "执行被打断", "原因未明")


class LedgerError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def classify_failure(raw) -> tuple:
    """Map a raw error/boundary text to (status, failReason).

    The category is a filing label; the excerpt is the evidence.
    Insufficient evidence files as 原因未明 -- never dress a
    guess up as a cause (spec 4.4). An approval-aborted round is
    a cancellation, not a failure."""
    text = str(raw or "").strip()
    low = text.lower()
    excerpt = text[:160] if text else None

    def reason(category):
        out = {"category": category}
        if excerpt:
            out["excerpt"] = excerpt
        return out

    if not text:
        return "failed", reason("原因未明")
    if ("待审批" in text or "waiting_for_approval" in low) and \
            any(k in text for k in ("中止", "停止", "取消")):
        return "cancelled", reason("被审批中止")
    if "user_cancel" in low or "cancelled by user" in low or \
            ("用户" in text and ("停止" in text or "取消" in text)):
        return "cancelled", reason("用户停止")
    if "interrupt" in low or "打断" in text or "中断" in text:
        return "failed", reason("执行被打断")
    if "timeout" in low or "timed out" in low or "超时" in text:
        return "failed", reason("超时")
    return "failed", reason("上游出错")


def resolve_title(*, server_title=None, server_title_grade=None,
                  user_text=None, registered_name=None,
                  registered_source="job_name", started_at=0.0,
                  tz=None) -> tuple:
    """The anti-fabrication title chain (spec 5.2). Every level
    must be text that already exists; the chain stops at the
    first real text it finds. Returns (title, titleSource).

    1. server session title, but only at llm/user grade -- the
       'derived' placeholder grade is a first-line splice and is
       strictly worse than level 2, so it is skipped.
    2. the user's own words: first line, verbatim, truncated at
       30 chars with an ellipsis (no rewriting, no completion).
    3. a registered name (job registry / kanban task title).
    4. fallback: 「未命名任务 · HH:mm」 -- ugly but true.
    """
    if server_title and str(server_title).strip() \
            and server_title_grade in ("llm", "user"):
        return str(server_title).strip(), "server_llm"
    if user_text and str(user_text).strip():
        first = str(user_text).strip().splitlines()[0].strip()
        if first:
            if len(first) > 30:
                first = first[:30] + "…"
            return first, "user_excerpt"
    if registered_name and str(registered_name).strip():
        return str(registered_name).strip(), registered_source
    when = datetime.fromtimestamp(started_at or time.time(), tz=tz)
    return f"未命名任务 · {when.strftime('%H:%M')}", "fallback"


_HUMAN_ACTIONS = {
    "patch": "修改了", "edit": "修改了", "edit_file": "修改了",
    "write_file": "写入了", "create": "新建了", "add": "新增了",
    "replace": "替换了", "remove": "删除了", "delete": "删除了",
}


def _human_verb(actions) -> str:
    """One headline verb for a batch of op kinds: the single mapped
    verb when all known kinds agree, 更新了 for a mixed batch, and ""
    when no kind is known (no factual verb to print)."""
    verbs = {_HUMAN_ACTIONS[a] for a in actions if a in _HUMAN_ACTIONS}
    if not verbs:
        return ""
    return next(iter(verbs)) if len(verbs) == 1 else "更新了"


_BATCH_SUMMARY_RE = re.compile(
    r"^batch\(\d+\s+ops?:\s*([^)]*)\)\s*on\s+(.+)$")
_APPLY_SUMMARY_RE = re.compile(
    r"^apply\s+\d+\s+op\(s\)\s+to\s+(.+?):\s*-\s*([A-Za-z_]+)\s*:")


def _parse_batch_summary(summary: str):
    """(kinds, slugs) from a skills-batch summary line, or None.

    The write-gate's decision summary is the object's true home:
    ``batch(4 ops: patch, patch, patch, patch) on hermes-agent,
    weekly-review-planning``. A truncated slug (excerpt cap bit it,
    ending in …) means the object is NOT recoverable — return None
    rather than print a cut-off name as if it were whole.
    """
    m = _BATCH_SUMMARY_RE.match(summary or "")
    if not m:
        return None
    kinds = [k.strip() for k in m.group(1).split(",") if k.strip()]
    slugs = [s.strip() for s in m.group(2).split(",")]
    if not kinds or not slugs or any(
            not s or s.endswith("…") or s == "..." for s in slugs):
        return None
    return kinds, slugs


def _join_slugs(slugs) -> str:
    joined = "、".join(slugs)
    if len(joined) <= 56:
        return joined
    return f"{slugs[0]} 等 {len(slugs)} 个对象"


def derive_title_human(fields: dict) -> str:
    """Derive an approval headline from the write-gate's structured facts.

    Do not cap target_name: resolve_title's excerpt cap is for user prose,
    and must not destroy the object used by this independent title.

    Object sources, in order: the structured ``target_name`` /
    ``mem_target`` fields when the decision line carries them, else the
    decision ``summary`` text itself — the batch form names its slugs
    after ``on``, the memory form names its target after ``to``. The
    summary parse is what heals the lines whose structured fields are
    absent (the live decisions file carries target_name on 0 of its
    lines; the object only ever lived in the summary). When neither
    source yields a whole object, return "" — a missing headline is
    honest, a fabricated one is not.
    """
    if not isinstance(fields, dict):
        return ""
    actions = fields.get("op_kinds")
    if not isinstance(actions, list) or not actions:
        actions = [fields.get("op")]
    actions = [str(a).strip() for a in actions if a]
    verb = _human_verb(actions)

    target = fields.get("target_name")
    if isinstance(target, str) and target.strip():
        return f"{verb} {target.strip()}" if verb else ""
    if fields.get("mem_target") in ("memory", "user"):
        obj = "长期记忆" if fields["mem_target"] == "memory" \
            else "用户档案"
        return f"{verb} {obj}" if verb else ""

    summary = fields.get("summary")
    if not isinstance(summary, str) or not summary.strip():
        return ""
    summary = summary.strip()
    parsed = _parse_batch_summary(summary)
    if parsed is not None:
        kinds, slugs = parsed
        verb = _human_verb(kinds)
        return f"{verb} {_join_slugs(slugs)}" if verb else ""
    m = _APPLY_SUMMARY_RE.match(summary)
    if m:
        where = m.group(1).strip().lower()
        if "user" in where:
            obj = "用户档案"
        elif "memory" in where or "profile" in where:
            obj = "长期记忆"
        else:
            return ""
        verb = _human_verb([m.group(2)])
        return f"{verb} {obj}" if verb else ""
    return ""


# --- activity summary (hermes-deploy 1.23.0) -------------------------
#
# The hub task row's second line: the last thing the run actually
# did, as one "verb + object" phrase (Chowder-style friendly label:
# verb template per tool + the call's primary-argument preview as
# the object, object capped at 30 chars). Two producers feed the
# item's ``summary`` field at terminal settle, one derivation:
# the App may report its own summary in the terminal report (it is
# the first knower of its run), and the gateway report handler
# derives one server-side from the run's live activity registry
# when the report carries none. The capsule's live phrase and the
# settled row text are the same derivation at two moments.

_ACTIVITY_VERBS = {
    "web_search": "搜索", "browser_search": "搜索",
    "web_extract": "读取网页", "browser_navigate": "打开网页",
    "browser_snapshot": "查看网页", "browser_click": "点击网页",
    "browser_type": "填写网页", "read_file": "读取",
    "write_file": "写入", "patch": "修改", "edit_file": "修改",
    "search_files": "查找", "list_files": "列出",
    "terminal": "运行", "execute_code": "运行代码",
    "process": "管理进程", "memory": "更新记忆",
    "skill_manage": "管理技能", "skills_list": "查看技能",
    "skill_view": "查看技能", "delegate_task": "委派子任务",
    "send_message": "发送消息", "image_generate": "生成图片",
    "text_to_speech": "生成语音", "vision_analyze": "分析图片",
    "todo": "更新待办", "clarify": "询问用户",
    "cronjob": "管理定时任务", "kanban_create": "建看板任务",
    "kanban_complete": "完成看板任务", "kanban_block": "阻塞看板任务",
    "session_search": "检索历史会话",
}

_SUMMARY_MAX = 120


def derive_activity_summary(tool, preview) -> str:
    """One settled "verb + object" phrase from a run's last tool
    activity. Object = the call's preview text (primary argument),
    whitespace-collapsed and capped at 30 chars; no object falls
    back to the bare verb, no verb falls back to the preview alone.
    Empty in, empty out -- never dress a guess up as an action."""
    obj = " ".join(str(preview or "").split())
    if len(obj) > 30:
        obj = obj[:30] + "…"
    verb = _ACTIVITY_VERBS.get(str(tool or "").strip(), "")
    if verb and obj:
        return f"{verb} {obj}"
    if verb:
        return verb
    return obj


def clean_summary(value) -> str:
    """Sanitize a producer-supplied summary for storage: one line,
    whitespace-collapsed, capped. Empty stays empty."""
    text = " ".join(str(value or "").split())
    return text[:_SUMMARY_MAX]


_INTERNAL_KEYS = ("terminalRank", "preStaleStatus")


def item_view(item: dict, detail: bool = False) -> dict:
    out = {k: v for k, v in item.items()
           if k not in _INTERNAL_KEYS}
    if not detail:
        out.pop("history", None)
    return out


class LedgerStore:
    """Append-only event log + materialized snapshot."""

    def __init__(self, path, now_fn=time.time, tz=None):
        self.path = Path(path)
        self._now = now_fn
        self.tz = tz
        self._lock = threading.RLock()
        self.items: dict = {}
        self.seq = 0
        self.cursors: dict = {}
        self.degraded_reason = ""
        self.collector_heartbeat_at = None
        self.last_event_at = None
        self.born_at = None
        self._fh = None
        self._load()

    # -- persistence ------------------------------------------------

    def _quarantine_stamp(self) -> str:
        return datetime.now().strftime("%Y%m%d-%H%M%S")

    def _load(self) -> None:
        if not self.path.exists():
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.touch()
            try:
                os.chmod(self.path, 0o600)
            except OSError:
                pass
            # The ledger starts keeping books at its birth:
            # turns that already settled before this moment are
            # history the ledger never saw (spec section 6 --
            # no backfill) and the collector skips them.
            self.born_at = self._now()
            with open(self.path, "w", encoding="utf-8") as f:
                f.write(json.dumps(
                    {"type": "meta", "bornAt": self.born_at,
                     "at": self.born_at},
                    ensure_ascii=False) + "\n")
            self._fh = open(self.path, "a", encoding="utf-8")
            return
        raw = self.path.read_bytes()
        lines = raw.split(b"\n")
        good: list = []
        bad_at = None
        for idx, line in enumerate(lines):
            if not line.strip():
                continue
            try:
                ev = json.loads(line.decode("utf-8"))
                if not isinstance(ev, dict) or "type" not in ev:
                    raise ValueError("事件行格式不对")
            except Exception:
                bad_at = idx
                break
            good.append(line)
            self._apply(ev)
        if bad_at is not None:
            quarantine = self.path.with_name(
                f"{self.path.name}.corrupt-{self._quarantine_stamp()}")
            try:
                os.replace(self.path, quarantine)
                where = str(quarantine)
            except OSError as e:
                where = f"隔离改名失败（{e}），原件仍在原地 {self.path}"
            # The replayable prefix goes back to a fresh log so
            # appends can continue; the original file survives
            # untouched under the quarantine name.
            with open(self.path, "wb") as f:
                for line in good:
                    f.write(line + b"\n")
            self.degraded_reason = (
                f"台账事件账第 {bad_at + 1} 行损坏；原件已隔离至 "
                f"{where}；以可回放部分建账，写入已停用，"
                "请先修复事件账后重启桥")
        self._fh = open(self.path, "a", encoding="utf-8")
        if self.born_at is None:
            self.born_at = self._now()
            if not self.degraded_reason:
                self._append({"type": "meta",
                              "bornAt": self.born_at})

    def _apply(self, ev: dict) -> None:
        seq = ev.get("seq")
        if isinstance(seq, int):
            self.seq = max(self.seq, seq)
        if ev.get("at"):
            self.last_event_at = ev["at"]
        kind = ev.get("type")
        if kind in ("created", "baseline"):
            item = ev.get("item") or {}
            if item.get("id"):
                item = dict(item)
                item.setdefault("history", [])
                item.setdefault("counts", {})
                item["lastSeq"] = seq
                self.items[item["id"]] = item
        elif kind == "status":
            item = self.items.get(ev.get("id"))
            if item:
                item["status"] = ev.get("to", item["status"])
                if ev.get("endedAt") is not None:
                    item["endedAt"] = ev["endedAt"]
                if ev.get("failReason") is not None:
                    item["failReason"] = ev["failReason"]
                if ev.get("summary"):
                    item["summary"] = ev["summary"]
                # Replay compat only: pre-B-02 logs carry
                # terminalRank on status events. It is preserved
                # so old items keep their shape, never read back
                # as a decision input (the rank table is gone).
                if ev.get("terminalRank") is not None:
                    item["terminalRank"] = ev["terminalRank"]
                if ev.get("preStaleStatus") is not None:
                    item["preStaleStatus"] = ev["preStaleStatus"]
                item.setdefault("history", []).append(
                    ev.get("historyEntry") or {})
                item["lastSeq"] = seq
        elif kind == "evidence":
            item = self.items.get(ev.get("id"))
            if item:
                at = ev.get("evidenceAt") or 0
                if at > (item.get("lastEvidenceAt") or 0):
                    item["lastEvidenceAt"] = at
                counts = ev.get("counts")
                if counts:
                    cur = item.setdefault("counts", {})
                    if ev.get("countsMode") == "set":
                        for k, v in counts.items():
                            cur[k] = v
                    else:
                        for k, v in counts.items():
                            cur[k] = (cur.get(k) or 0) + v
                item["lastSeq"] = seq
        elif kind == "updated":
            item = self.items.get(ev.get("id"))
            if item:
                for k, v in (ev.get("fields") or {}).items():
                    item[k] = v
                entry = ev.get("historyEntry")
                if entry:
                    item.setdefault("history", []).append(entry)
                item["lastSeq"] = seq
        elif kind == "cursor":
            self.cursors[ev.get("source")] = {
                "offset": ev.get("offset") or 0,
                "hash": ev.get("hash") or ""}
        elif kind == "collector":
            self.collector_heartbeat_at = ev.get("heartbeatAt")
        elif kind == "meta":
            nxt = ev.get("nextSeq")
            if isinstance(nxt, int):
                self.seq = max(self.seq, nxt - 1)
            if ev.get("bornAt"):
                self.born_at = ev["bornAt"]

    def _append(self, ev: dict) -> int:
        if self.degraded_reason:
            raise LedgerError(
                503, "台账事件账损坏，桥处于降级模式：写入已停用，"
                     "请先修复事件账后重启桥")
        self.seq += 1
        ev["seq"] = self.seq
        ev.setdefault("at", self._now())
        line = json.dumps(ev, ensure_ascii=False)
        if self._fh is None:
            self._fh = open(self.path, "a", encoding="utf-8")
        self._fh.write(line + "\n")
        self._fh.flush()
        os.fsync(self._fh.fileno())
        self._apply(ev)
        return self.seq

    # -- item writes --------------------------------------------------

    def create_or_merge(self, item: dict) -> tuple:
        """Create the item, or fold a repeat report into the
        existing one with the same natural key. The fold is by
        event order (B-02): a repeat report appends ONE "updated"
        event carrying the fields it actually reports (title,
        sessionId, runId, link) -- later in the log wins, with no
        field-priority table and no title ranking. Returns
        (item, created). (Name kept for the existing call sites;
        there is no merge adjudication left to deserve it.)
        """
        with self._lock:
            iid = item["id"]
            existing = self.items.get(iid)
            if existing is None:
                fresh = {
                    "id": iid,
                    "kind": item.get("kind", "run"),
                    "source": item.get("source", "api"),
                    "title": item.get("title", ""),
                    "titleSource": item.get("titleSource",
                                            "fallback"),
                    "status": item.get("status", "running"),
                    "startedAt": item.get("startedAt")
                    or self._now(),
                    "endedAt": item.get("endedAt"),
                    "lastEvidenceAt": item.get("lastEvidenceAt")
                    or item.get("startedAt") or self._now(),
                    "origin": item.get("origin", "reported"),
                    "link": item.get("link"),
                    "counts": dict(item.get("counts") or {}),
                    "failReason": item.get("failReason"),
                    "summary": clean_summary(item.get("summary"))
                    or None,
                    "history": list(item.get("history") or []),
                    "evidenceLagging": False,
                }
                if item.get("title_human"):
                    fresh["title_human"] = str(item["title_human"])
                for opt in ("sessionId", "runId", "correctedBy"):
                    if item.get(opt) is not None:
                        fresh[opt] = item[opt]
                if not fresh["history"]:
                    fresh["history"].append({
                        "at": fresh["startedAt"], "from": None,
                        "to": fresh["status"],
                        "by": item.get("by", "collector")})
                self._append({"type": "created", "item": fresh})
                return self.items[iid], True
            # Fold: the later report's fields land as one
            # "updated" event, in log order. No gap-only rule,
            # no title rank -- if a producer re-reports a field,
            # its newest value is the fact.
            fields = {}
            if item.get("title_human") and \
                    existing.get("title_human") != item["title_human"]:
                fields["title_human"] = str(item["title_human"])
            for key in ("sessionId", "runId", "link"):
                if item.get(key) is not None \
                        and existing.get(key) != item[key]:
                    fields[key] = item[key]
            if item.get("title"):
                if existing.get("title") != item["title"]:
                    fields["title"] = item["title"]
                if item.get("titleSource") and \
                        existing.get("titleSource") \
                        != item["titleSource"]:
                    fields["titleSource"] = item["titleSource"]
            if fields:
                self._append({"type": "updated", "id": iid,
                              "fields": fields})
            ev_at = item.get("lastEvidenceAt") \
                or item.get("startedAt")
            if ev_at and ev_at > (existing.get("lastEvidenceAt")
                                   or 0):
                self.touch_evidence(iid, ev_at, "merge")
            return self.items[iid], False

    def set_status(self, item_id: str, to: str, *, by: str,
                   ended_at: float = None,
                   fail_reason: dict = None, note: str = None,
                   summary: str = None,
                   at: float = None) -> str:
        """Attempt a status transition. Returns "ok" / "noop" /
        "invalid". The fold is by event order (B-02): a later
        direct report of a DIFFERENT terminal state corrects the
        earlier one -- the correction is appended as a status
        event with a corrected history entry, never adjudicated
        by evidence rank (the rank table is retired). A terminal
        state still cannot move back to a non-terminal one: that
        is a transition-table rule, not a ranking."""
        with self._lock:
            item = self.items.get(item_id)
            if item is None or to not in STATUSES:
                return "invalid"
            at = at if at is not None else self._now()
            cur = item["status"]
            if cur in TERMINAL:
                if to == cur:
                    return "noop"
                if to not in TERMINAL:
                    return "invalid"
                entry = {"at": at, "from": cur, "to": to,
                         "by": by, "corrected": True}
                if note:
                    entry["note"] = note
                ev = {
                    "type": "status", "id": item_id, "to": to,
                    "endedAt": ended_at
                    if ended_at is not None
                    else item.get("endedAt"),
                    "failReason": fail_reason,
                    "historyEntry": entry}
                if summary:
                    ev["summary"] = summary
                self._append(ev)
                upd = self.items[item_id]
                upd["correctedBy"] = by
                return "ok"
            if to == cur:
                return "noop"
            if to not in ALLOWED.get(cur, frozenset()):
                return "invalid"
            entry = {"at": at, "from": cur, "to": to, "by": by}
            if note:
                entry["note"] = note
            ev = {"type": "status", "id": item_id, "to": to,
                  "historyEntry": entry}
            if to in TERMINAL:
                ev["endedAt"] = ended_at \
                    if ended_at is not None else at
                ev["failReason"] = fail_reason
                if summary:
                    ev["summary"] = summary
            if to == "stale" and cur in ACTIVE:
                ev["preStaleStatus"] = cur
            self._append(ev)
            return "ok"

    def touch_evidence(self, item_id: str, at: float, kind: str,
                       counts: dict = None,
                       counts_mode: str = "add") -> None:
        with self._lock:
            item = self.items.get(item_id)
            if item is None:
                return
            if at <= (item.get("lastEvidenceAt") or 0) \
                    and not counts:
                return
            ev = {"type": "evidence", "id": item_id,
                  "evidenceAt": at, "kind": kind}
            if counts:
                ev["counts"] = counts
                ev["countsMode"] = counts_mode
            self._append(ev)

    def update_fields(self, item_id: str, fields: dict, *,
                      by: str, note: str = None,
                      at: float = None) -> None:
        with self._lock:
            item = self.items.get(item_id)
            if item is None:
                return
            real = {k: v for k, v in fields.items()
                    if item.get(k) != v}
            if not real and not note:
                return
            ev = {"type": "updated", "id": item_id,
                  "fields": real}
            if note:
                ev["historyEntry"] = {
                    "at": at if at is not None else self._now(),
                    "from": item.get("status"),
                    "to": item.get("status"), "by": by,
                    "note": note}
            self._append(ev)

    def record_cursor(self, source: str, offset: int,
                      line_hash: str = "") -> None:
        with self._lock:
            cur = self.cursors.get(source) or {}
            if cur.get("offset") == offset \
                    and cur.get("hash") == line_hash:
                return
            self._append({"type": "cursor", "source": source,
                          "offset": offset, "hash": line_hash})

    def set_collector_heartbeat(self, at: float,
                                persist: bool = False) -> None:
        with self._lock:
            self.collector_heartbeat_at = at
            if persist and not self.degraded_reason:
                self._append({"type": "collector",
                              "heartbeatAt": at})

    # -- reads --------------------------------------------------------

    def get(self, item_id: str):
        with self._lock:
            item = self.items.get(item_id)
            return dict(item) if item else None

    def summary(self, now: float = None) -> dict:
        with self._lock:
            now = now if now is not None else self._now()
            by_status = {s: 0 for s in STATUSES}
            for item in self.items.values():
                by_status[item["status"]] = \
                    by_status.get(item["status"], 0) + 1
            day = datetime.fromtimestamp(now, tz=self.tz)
            start = day.replace(hour=0, minute=0, second=0,
                                microsecond=0).timestamp()
            end = start + 24 * 3600
            today = {"completed": 0, "failed": 0, "cancelled": 0}
            for item in self.items.values():
                ended = item.get("endedAt")
                if ended and start <= ended < end \
                        and item["status"] in today:
                    today[item["status"]] += 1
            return {
                "inProgress": by_status["queued"]
                + by_status["running"],
                "blockedApproval": by_status["blocked_approval"],
                "stale": by_status["stale"],
                "todayCompleted": today["completed"],
                "todayFailed": today["failed"],
                "todayCancelled": today["cancelled"],
                "byStatus": by_status,
                "total": len(self.items),
            }

    def list_items(self) -> list:
        with self._lock:
            items = sorted(self.items.values(),
                           key=lambda i: i.get("startedAt") or 0,
                           reverse=True)
            return [item_view(i) for i in items[:500]]

    def detail(self, item_id: str):
        with self._lock:
            item = self.items.get(item_id)
            return item_view(item, detail=True) if item else None

    def changes_since(self, seq: int) -> list:
        with self._lock:
            changed = [i for i in self.items.values()
                       if (i.get("lastSeq") or 0) > seq]
            changed.sort(key=lambda i: i.get("lastSeq") or 0)
            return [item_view(i) for i in changed]

    def health(self) -> dict:
        with self._lock:
            return {
                "degraded": bool(self.degraded_reason),
                "degradedReason": self.degraded_reason or None,
                "collectorHeartbeatAt":
                    self.collector_heartbeat_at,
                "ledgerUpdatedAt": self.last_event_at,
                "items": len(self.items),
                "seq": self.seq,
            }

    # -- retention ------------------------------------------------------

    def compact(self, now: float = None,
                keep_days: int = 30) -> int:
        """Drop terminal items older than keep_days and rewrite
        the log as baselines for the survivors (spec 5.4).
        Non-terminal items are never compacted away -- they are
        the zombie ladder's business, not the sweeper's."""
        with self._lock:
            if self.degraded_reason:
                raise LedgerError(
                    503, "台账处于降级模式，压实已停用")
            now = now if now is not None else self._now()
            cutoff = now - keep_days * 24 * 3600
            survivors = {}
            dropped = 0
            for iid, item in self.items.items():
                if item["status"] in TERMINAL \
                        and (item.get("endedAt") or 0) < cutoff:
                    dropped += 1
                else:
                    survivors[iid] = item
            tmp = self.path.with_suffix(".tmp")
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(json.dumps(
                    {"type": "meta", "nextSeq": self.seq + 1,
                     "bornAt": self.born_at, "at": now},
                    ensure_ascii=False) + "\n")
                for item in survivors.values():
                    f.write(json.dumps(
                        {"type": "baseline",
                         "item": {k: v for k, v in item.items()
                                  if k != "lastSeq"},
                         "seq": item.get("lastSeq"),
                         "at": now},
                        ensure_ascii=False) + "\n")
                for source, cur in self.cursors.items():
                    f.write(json.dumps(
                        {"type": "cursor", "source": source,
                         "offset": cur.get("offset") or 0,
                         "hash": cur.get("hash") or "",
                         "at": now}, ensure_ascii=False) + "\n")
                f.flush()
                os.fsync(f.fileno())
            if self._fh is not None:
                self._fh.close()
            os.replace(tmp, self.path)
            try:
                os.chmod(self.path, 0o600)
            except OSError:
                pass
            self._fh = open(self.path, "a", encoding="utf-8")
            self.items = survivors
            return dropped


# --- App report channel (spec 2.1) ---------------------------------

def apply_app_report(store: LedgerStore, body: dict, *,
                     tz=None) -> tuple:
    """Apply one App report. Returns (item, seq). The App is the
    first knower of its own runs: a start report lands within a
    second, a terminal report carries the same settle the chat
    page itself reached; since the C-4 convergence the report
    channel is the only writer of run items, and nothing
    second-guesses it -- its events simply land in the log, in
    order (B-02).

    Protocol (1.23.0): a terminal report may carry ``summary`` --
    one "verb + object" phrase for the run's last activity (see
    derive_activity_summary). Absent/empty stays absent: the
    gateway report handler injects a server-derived value into
    the same field when it has live activity for the run."""
    run_id = str(body.get("runId") or "").strip()
    if not run_id:
        raise LedgerError(400, "上报缺少 runId")
    iid = f"run:{run_id}"
    now = store._now()
    started = body.get("startedAt")
    started = float(started) if isinstance(started, (int, float)) \
        else now
    terminal = body.get("terminal")
    if terminal:
        status = str(terminal)
        if status not in TERMINAL:
            raise LedgerError(400, "terminal 取值不对")
        fail_reason = None
        if status in ("failed", "cancelled"):
            raw_reason = body.get("failReason")
            if isinstance(raw_reason, dict) \
                    and raw_reason.get("category") \
                    in FAIL_CATEGORIES:
                fail_reason = {
                    "category": raw_reason["category"]}
                if raw_reason.get("excerpt"):
                    fail_reason["excerpt"] = \
                        str(raw_reason["excerpt"])[:160]
            else:
                _, fail_reason = classify_failure(
                    body.get("error") or body.get("failReason"))
                if status == "cancelled" \
                        and fail_reason["category"] \
                        not in ("被审批中止", "用户停止"):
                    fail_reason = {"category": "用户停止"}
                    if body.get("error"):
                        fail_reason["excerpt"] = \
                            str(body["error"])[:160]
        ended = body.get("endedAt")
        ended = float(ended) if isinstance(ended, (int, float)) \
            else now
        existing = store.get(iid)
        if existing is None:
            title, tsrc = resolve_title(
                user_text=body.get("titleSeed"),
                started_at=started, tz=tz)
            store.create_or_merge({
                "id": iid, "kind": "run", "source": "app",
                "title": title, "titleSource": tsrc,
                "status": "running", "startedAt": started,
                "origin": "reported", "runId": run_id,
                "sessionId": body.get("sessionId"),
                "link": {"kind": "session",
                         "targetId": body.get("sessionId")}
                if body.get("sessionId") else None,
                "by": "app"})
        # Terminal settle carries the run's activity summary
        # (1.23.0): the App's own reported summary wins; the
        # gateway handler may inject a server-derived one into the
        # same field when the App reported none. Stored on the
        # status event so the fold replays it like any other fact.
        store.set_status(iid, status, by="app",
                         ended_at=ended, fail_reason=fail_reason,
                         summary=clean_summary(body.get("summary"))
                         or None)
        return store.get(iid), store.seq
    if body.get("stillRunning"):
        existing = store.get(iid)
        if existing is None:
            title, tsrc = resolve_title(
                user_text=body.get("titleSeed"),
                started_at=started, tz=tz)
            store.create_or_merge({
                "id": iid, "kind": "run", "source": "app",
                "title": title, "titleSource": tsrc,
                "status": "running", "startedAt": started,
                "lastEvidenceAt": now, "origin": "reported",
                "runId": run_id,
                "sessionId": body.get("sessionId"),
                "link": {"kind": "session", "targetId":
                         body.get("sessionId")}
                if body.get("sessionId") else None,
                "by": "app"})
        else:
            store.touch_evidence(iid, now, "app")
        return store.get(iid), store.seq
    # Start report.
    title, tsrc = resolve_title(
        user_text=body.get("titleSeed"), started_at=started, tz=tz)
    status = "queued" if body.get("queued") else "running"
    item, _created = store.create_or_merge({
        "id": iid, "kind": "run", "source": "app",
        "title": title, "titleSource": tsrc, "status": status,
        "startedAt": started, "origin": "reported",
        "runId": run_id, "sessionId": body.get("sessionId"),
        "link": {"kind": "session", "targetId":
                 body.get("sessionId")}
        if body.get("sessionId") else None,
        "by": "app"})
    if item["status"] == "queued" and status == "running":
        store.set_status(iid, "running", by="app")
    return store.get(iid), store.seq


# --- Event ingestion + zombie ladder (C-4 convergence) --------------
#
# The Collector is the book's ingestion clerk, ticking on the
# bridge's 15 s loop. It writes ONLY from the two append-only
# event files (decisions / device audit), consumed in order
# through store cursors: it is a pure event producer into the
# same log every other writer appends to, and the store folds
# strictly by event order (B-02) -- the Collector carries no
# merge or ranking logic of its own. It also runs the zombie
# ladder: an item
# whose owner stopped reporting is flagged evidence-lagging past
# the lagging threshold and marked stale (lost contact) past the
# stale threshold -- never settled by inference. The check
# window between the two thresholds is pure grace: no look is
# performed any more. A stale item revives when its owner files
# a late direct report (the store's transition table allows it).


def settle_job_delivered(store: "LedgerStore", item_id: str,
                         produced: int, *, now: float,
                         by: str = "bridge") -> str:
    """Delivery-point settlement (§475 part 2): settle a
    bridge-self job completed at the moment its round's
    deliverables have ALL landed in the store, with the
    produced count booked on the item.

    The job's user-facing meaning is the round's deliverables;
    once they are in the store and saved, whatever the round
    thread still has queued (history record, next-run
    bookkeeping, distribution tallies) is tail work -- it
    must not hold the job at "running", and its failure must
    not roll the delivered status back (the segment's finish
    path checks its delivered set and leaves the status
    alone). An item already terminal (settled by anyone) is
    a noop; a stale-marked item still settles -- stale ->
    completed is a legal transition, and delivery is fresh
    evidence, not an inference. Returns set_status's result
    ("ok" / "noop" / "invalid")."""
    item = store.get(item_id)
    if item is None or item.get("status") in TERMINAL:
        return "noop"
    res = store.set_status(item_id, "completed", by=by,
                           ended_at=now,
                           note="交付齐，先行结算完成")
    if res == "ok":
        store.touch_evidence(
            item_id, now, "delivery",
            counts={"produced": int(produced)},
            counts_mode="set")
    return res


def settle_orphan_jobs(store: "LedgerStore", histories: dict, *,
                       now: float, by: str = "bridge") -> int:
    """Boot-time settlement of bridge-self job items whose
    owner process died mid-round (2026-11-24, §475).

    A `job:*` item still active when the bridge boots is
    DEFINITIONALLY orphaned: its writer was the previous
    incarnation's round thread, and that thread no longer
    exists -- this is a fact known at boot, not an inference,
    so the zombie ladder's "never settled by inference" rule
    (written for owners that may merely be silent) does not
    apply. The round's own history record, when one exists at
    or after the item's start, is the settlement evidence and
    the finish mapping mirrors the live finish path exactly
    (DELIVERY_CONSISTENT_STATUSES -> completed, skipped ->
    failed, anything else via classify_failure). Items a
    round already settled at its delivery point (§475 part 2)
    are terminal by the time a later boot runs this pass, so
    they are skipped by the ACTIVE filter below -- delivery
    settlement and orphan settlement can never double-settle
    or roll each other back. With no record the
    round left no trace at all: settle failed as interrupted,
    saying so. Returns the number of items settled."""
    settled = 0
    for item in list(store.list_items()):
        iid = item.get("id") or ""
        if not iid.startswith("job:"):
            continue
        if item.get("status") not in ACTIVE:
            continue
        kind = iid.split(":")[1] if iid.count(":") >= 2 else ""
        started = item.get("startedAt") or 0
        rec = None
        for cand in histories.get(kind) or []:
            at = cand.get("at") or 0
            # A round's record carries the round's own start
            # stamp (the ledger start and the round start are
            # the same _now() breath), so the match window is
            # seconds-tight: a LATER round's record must
            # never settle this item.
            if started - 2 <= at <= started + 10 and (
                    rec is None or at < (rec.get("at") or 0)):
                rec = cand
        if rec is None:
            res = store.set_status(
                iid, "failed", by=by, ended_at=now,
                fail_reason={
                    "category": "执行被打断",
                    "excerpt": "运行进程已重启，本轮未留下完成记录"},
                note="进程重启后结算：属主进程已不在，本轮未收尾")
            if res == "ok":
                settled += 1
            continue
        raw = str(rec.get("status") or "")
        err = rec.get("error")
        if raw in DELIVERY_CONSISTENT_STATUSES:
            res = store.set_status(
                iid, "completed", by=by, ended_at=now,
                note="进程重启后按本轮记录补结算")
        elif raw == "skipped":
            res = store.set_status(
                iid, "failed", by=by, ended_at=now,
                fail_reason={"category": "原因未明",
                             "excerpt": str(
                                 err or "本轮未执行")[:160]},
                note="进程重启后按本轮记录补结算")
        else:
            to, fail_reason = classify_failure(err)
            res = store.set_status(
                iid, to, by=by, ended_at=now,
                fail_reason=fail_reason,
                note="进程重启后按本轮记录补结算")
        if res == "ok":
            settled += 1
    return settled


class Collector:
    """Event-file ingestion + zombie ladder over a LedgerStore.

    decisions_path / device_audit_path are append-only JSONL
    event logs whose owners append at event time (the write-gate
    bridge at decide time, the device bridge at call time).
    """

    def __init__(self, store: LedgerStore, *,
                 lagging=45.0, check=600.0, stale=1800.0,
                 tz=None, now_fn=None,
                 decisions_path=None, device_audit_path=None):
        self.store = store
        self.lagging = float(lagging)
        self.check_after = float(check)
        self.stale_after = float(stale)
        self.tz = tz
        self._now = now_fn or store._now
        self.decisions_path = decisions_path
        self.device_audit_path = device_audit_path
        self._last_persist = 0.0
        self._last_compact_day = None
        self.state = {"lastRunAt": None, "sources": {},
                      "cycles": 0}

    # -- helpers -----------------------------------------------------

    def _src(self, name, ok, note=None):
        self.state["sources"][name] = \
            {"ok": ok, "note": note, "at": self._now()}

    def _read_new_lines(self, source: str, path) -> list:
        """Incremental JSONL read via the store cursor (offset +
        last-line hash, the overview-bridge pattern). A shrunk or
        rewritten file restarts from 0; unparseable lines are
        skipped, never fatal."""
        if not path:
            return []
        p = Path(path)
        if not p.exists():
            return []
        try:
            raw = p.read_bytes()
        except OSError:
            return []
        cursor = self.store.cursors.get(source) or {}
        offset = cursor.get("offset") or 0
        if offset > len(raw):
            offset = 0
        chunk = raw[offset:]
        if not chunk:
            return []
        lines = chunk.split(b"\n")
        complete = lines[:-1]  # last piece may be a partial write
        out = []
        consumed = offset
        last_hash = cursor.get("hash") or ""
        import hashlib
        for line in complete:
            consumed += len(line) + 1
            if not line.strip():
                continue
            last_hash = hashlib.sha1(line).hexdigest()
            try:
                obj = json.loads(line.decode("utf-8"))
            except Exception:
                continue
            if isinstance(obj, dict):
                out.append(obj)
        if consumed != offset:
            self.store.record_cursor(source, consumed, last_hash)
        return out

    @staticmethod
    def _parse_iso(value):
        if isinstance(value, (int, float)):
            return float(value) / 1000 if value > 1e11 \
                else float(value)
        if isinstance(value, str) and value:
            try:
                dt = datetime.fromisoformat(
                    value.replace("Z", "+00:00"))
                return dt.timestamp()
            except Exception:
                return None
        return None

    # -- cycle ---------------------------------------------------------

    def cycle(self) -> dict:
        now = self._now()
        actions = {"created": 0, "settled": 0, "stale": 0}
        self._step_decisions(actions, now)
        self._step_title_human(actions, now)
        self._step_device(actions, now)
        self._step_zombies(actions, now)
        self.state["lastRunAt"] = now
        self.state["cycles"] += 1
        self.store.set_collector_heartbeat(
            now, persist=(now - self._last_persist >= 300))
        if now - self._last_persist >= 300:
            self._last_persist = now
        day = datetime.fromtimestamp(now, tz=self.tz).strftime(
            "%Y-%m-%d")
        if self._last_compact_day is None:
            self._last_compact_day = day
        elif day != self._last_compact_day:
            self._last_compact_day = day
            try:
                self.store.compact(now)
            except LedgerError:
                pass
        return actions

    def _step_decisions(self, actions, now):
        """Write-gate decision events: a decided approval enters
        the book (born from its decision event if the book has
        never seen it) and settles in the same pass."""
        if self.decisions_path:
            self._src("decisions", True)
        for line in self._read_new_lines("decisions",
                                         self.decisions_path):
            pid = str(line.get("id") or "")
            decision = str(line.get("decision") or "")
            if not pid or decision not in ("approved", "rejected"):
                continue
            iid = f"appr:{pid}"
            decided = self._parse_iso(line.get("decided_at")) \
                or now
            created = self._parse_iso(line.get("created_at")) \
                or decided
            to = "completed" if decision == "approved" \
                else "cancelled"
            fail_reason = None
            if decision == "rejected":
                fail_reason = {"category": "被审批中止"}
                if line.get("summary"):
                    fail_reason["excerpt"] = \
                        str(line["summary"])[:160]
            existing = self.store.get(iid)
            if existing is None:
                title, tsrc = resolve_title(
                    user_text=line.get("summary"),
                    started_at=created, tz=self.tz)
                if tsrc == "user_excerpt":
                    tsrc = "record_excerpt"
                self.store.create_or_merge({
                    "id": iid, "kind": "approval",
                    "source": "bridge", "title": title,
                    "title_human": derive_title_human(line),
                    "titleSource": tsrc,
                    "status": "blocked_approval",
                    "startedAt": created,
                    "lastEvidenceAt": decided,
                    "origin": "reported",
                    "link": {"kind": "approval",
                             "targetId": pid},
                    "by": "collector"})
                actions["created"] += 1
            res = self.store.set_status(
                iid, to, by="collector",
                ended_at=decided, fail_reason=fail_reason,
                note="审批已裁决：" + decision)
            if res == "ok":
                actions["settled"] += 1

    def _step_title_human(self, actions, now):
        """Backfill approval headlines the write-time derivation
        missed (queue 173). title_human is stored at creation from
        the decision line, but lines written before the summary
        parse existed — and items born from the App's pending mirror
        whose decision line arrived shaped differently — sit in the
        book with no headline while their decision line still names
        the object in its summary. This step re-reads the decisions
        file whole (it is small and append-only) and fills the gaps
        through update_fields, so the heal is itself an event in the
        log. Items whose decision line is gone (the file rotated
        before this step existed) keep no headline: the object is
        unrecoverable and is never guessed."""
        if not self.decisions_path:
            return
        try:
            raw = Path(self.decisions_path).read_text(
                encoding="utf-8")
        except Exception:
            return
        lines = {}
        for chunk in raw.splitlines():
            chunk = chunk.strip()
            if not chunk:
                continue
            try:
                line = json.loads(chunk)
            except Exception:
                continue
            pid = str(line.get("id") or "")
            if pid:
                lines[pid] = line
        if not lines:
            return
        healed = 0
        for item in list(self.store.items.values()):
            if item.get("kind") != "approval":
                continue
            if str(item.get("title_human") or "").strip():
                continue
            pid = str(item.get("id") or "")
            if pid.startswith("appr:"):
                pid = pid[len("appr:"):]
            line = lines.get(pid)
            if line is None:
                continue
            human = derive_title_human(line)
            if human:
                self.store.update_fields(
                    item["id"], {"title_human": human},
                    by="collector")
                healed += 1
        if healed:
            actions["title_human_healed"] = healed

    def _step_device(self, actions, now):
        """Device-call events: one audit line is one standalone
        device item, born settled from its own event. No window
        attribution into run items any more -- the merge was a
        drift source (a call folded or stood alone depending on
        which runs happened to be open at read time)."""
        if self.device_audit_path:
            self._src("device", True)
        for line in self._read_new_lines("device_audit",
                                         self.device_audit_path):
            tool = str(line.get("tool") or "")
            call_id = line.get("callId")
            ts = line.get("ts")
            if not tool or tool.startswith("sync:") \
                    or not call_id \
                    or not isinstance(ts, (int, float)):
                continue
            ts = float(ts) / 1000 if ts > 1e11 else float(ts)
            iid = f"dev:{call_id}"
            if self.store.get(iid) is not None:
                continue
            status_raw = str(line.get("status") or "")
            failed = status_raw not in (
                "", "ok", "success", "completed")
            self.store.create_or_merge({
                "id": iid, "kind": "device",
                "source": "device",
                "title": f"设备调用 · {tool}",
                "titleSource": "job_name",
                "status": "failed" if failed else "completed",
                "startedAt": ts, "endedAt": ts,
                "lastEvidenceAt": ts,
                "origin": "reported",
                "link": {"kind": "device", "targetId": tool},
                "failReason": {"category": "原因未明",
                               "excerpt": f"调用状态："
                                          f"{status_raw}"}
                if failed else None,
                "by": "collector"})
            actions["created"] += 1

    def _step_zombies(self, actions, now):
        for item in list(self.store.items.values()):
            if item["status"] in TERMINAL:
                continue
            age = now - (item.get("lastEvidenceAt") or 0)
            if age <= self.lagging:
                if item.get("evidenceLagging"):
                    self.store.update_fields(
                        item["id"], {"evidenceLagging": False},
                        by="collector")
                continue
            if age <= self.stale_after:
                if not item.get("evidenceLagging"):
                    self.store.update_fields(
                        item["id"], {"evidenceLagging": True},
                        by="collector")
                continue
            if item["status"] != "stale":
                res = self.store.set_status(
                    item["id"], "stale", by="collector",
                    note="失联待核：超时无新证据，属主未再上报")
                if res == "ok":
                    actions["stale"] += 1
