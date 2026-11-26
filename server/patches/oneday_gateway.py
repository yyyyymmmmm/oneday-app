"""oneday_gateway: the OneDay domain surface (goals / ideas /
monitors / feed / ledger / deliveries / file library / traces /
MCP facades / cron callbacks) as an in-process gateway module.

Batch 3 of the bridge retirement (bridge-retirement-spec-20261124
section 3, rows 10-11): the companion oneday bridge (port 8646)
moved into the gateway. The bridge's core file and its fifteen
C-8 segment files are carried over verbatim except for the shell
differences registered in bridge-batch3-rollout-20261124.md:

- the HTTP server shell (BaseHTTPRequestHandler) becomes a
  request-context adapter: api_server handlers build a context
  (method / path / headers / body) and call dispatch(); the
  bridge's own _dispatch machinery runs unchanged on it;
- auth moves to api_server's @_require_auth (API_SERVER_KEY,
  single credential source); the bridge key ONEDAY_BRIDGE_KEY is
  retired. The one exception is the /internal/cron/* surface,
  which keeps its dedicated callback key check inside the
  dispatch, exactly as the bridge ran it;
- DATA_PATH default moves to the gateway data tree
  (/opt/data/oneday/data.json); the data file format is unchanged
  and the state files are carried over in place at rollout;
- _print() call sites route through a logger shim (_print);
- the segment files sit next to this module (gateway/platforms)
  and are exec-loaded by the same _load_segment machinery;
- ledger.py rides along as oneday_ledger_lib.py (verbatim).

Boot: start() mirrors the bridge main() sequence (load, reconcile
loop, cron ensure, ledger collector, delivery sentinel,
automation watcher), minus the HTTP listener and the bridge-key
fail-closed gate.
"""

from __future__ import annotations

import csv
import hashlib
import hmac
import io
import json
import os
import re
import secrets
import sys
import threading
import time
import urllib.error
import urllib.request
import zipfile
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import parse_qs, parse_qsl, urlencode, urlparse

try:
    from gateway.platforms import oneday_ledger_lib as _ledger_mod
except ImportError:  # direct / selftest loading
    import oneday_ledger_lib as _ledger_mod

try:
    from gateway.platforms import activity_feed as _activity_mod
except ImportError:  # direct / selftest loading
    import activity_feed as _activity_mod

try:
    from gateway.platforms import title_engine as _title_mod
except ImportError:  # direct / selftest loading
    import title_engine as _title_mod

try:
    from error_boundary import redact
except ImportError:
    def redact(e): return str(e)[:80]

import logging as _logging

logger = _logging.getLogger(__name__)


def _print(*args, **kwargs):
    """Bridge _print() shim (batch 3): stdout prints -> logger.info,
    stderr prints -> logger.warning. Call sites are the bridge's own,
    mechanically renamed _print( -> _print( ."""
    kwargs.pop("flush", None)
    _file = kwargs.pop("file", None)
    _msg = " ".join(str(a) for a in args)
    if _file is sys.stderr:
        logger.warning("%s", _msg)
    else:
        logger.info("%s", _msg)


DATA_PATH = Path(os.environ.get("DATA_PATH", "/opt/data/oneday/data.json"))
#: The device sync copy lives in the device bridge's data dir
#: (same container, shared volume). This bridge only ever READS
#: it, through device_sync's own query path (ID-1); the env name
#: is deliberately distinct from the device bridge's DATA_DIR.
DEVICE_DATA_DIR = Path(os.environ.get(
    "DEVICE_DATA_DIR", "/opt/device-data"))
MAX_BODY = 1_048_576

_lock = threading.Lock()
_db: dict = {"goals": [], "ideas": [], "monitors": [], "changes": [],
             "goalEntries": [], "briefings": [], "feedPosts": [],
             "goalTaskLinks": [], "traces": [], "aiSessions": [],
             "cronBindings": [], "kanbanBindings": [],
             "taskGoals": {}, "goalEchoState": {},
             "proactiveQueue": [], "meta": {}}
# Non-empty => the data file failed to load; the bridge is running
# read-only degraded (see _load). Writes are refused everywhere.
_degraded_reason: str = ""


def _now() -> float:
    return time.time()


def _new_id(prefix: str, existing: set) -> str:
    while True:
        cand = prefix + secrets.token_hex(6)
        if cand not in existing:
            return cand


def _save_locked() -> None:
    if _degraded_reason:
        # Fail-safe: in degraded mode the in-memory db is an empty
        # placeholder; writing it back would destroy the (quarantined)
        # original data. Refuse every save. (_Err is resolved at call
        # time; it is defined below at module level.)
        raise _Err(503, "数据文件损坏，桥处于只读降级模式：写入已停用，"
                        "请先修复数据文件后重启桥")
    DATA_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = DATA_PATH.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(_db, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, DATA_PATH)
    try:
        os.chmod(DATA_PATH, 0o600)
    except OSError:
        pass


def _load() -> None:
    global _degraded_reason
    if DATA_PATH.exists():
        try:
            data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                raise ValueError("数据文件顶层不是 JSON 对象")
            if isinstance(data.get("goals"), list):
                _db["goals"] = data["goals"]
            if isinstance(data.get("ideas"), list):
                _db["ideas"] = data["ideas"]
            if isinstance(data.get("monitors"), list):
                _db["monitors"] = data["monitors"]
            if isinstance(data.get("changes"), list):
                _db["changes"] = data["changes"]
            if isinstance(data.get("goalEntries"), list):
                _db["goalEntries"] = data["goalEntries"]
            if isinstance(data.get("briefings"), list):
                _db["briefings"] = data["briefings"]
            if isinstance(data.get("feedPosts"), list):
                _db["feedPosts"] = data["feedPosts"]
            if isinstance(data.get("goalTaskLinks"), list):
                _db["goalTaskLinks"] = data["goalTaskLinks"]
            if isinstance(data.get("taskGoals"), dict):
                _db["taskGoals"] = data["taskGoals"]
            if isinstance(data.get("goalEchoState"), dict):
                _db["goalEchoState"] = data["goalEchoState"]
            if isinstance(data.get("traces"), list):
                _db["traces"] = data["traces"]
            if isinstance(data.get("aiSessions"), list):
                _db["aiSessions"] = data["aiSessions"]
            if isinstance(data.get("cronBindings"), list):
                _db["cronBindings"] = data["cronBindings"]
            if isinstance(data.get("kanbanBindings"), list):
                _db["kanbanBindings"] = data["kanbanBindings"]
            if isinstance(data.get("proactiveQueue"), list):
                _db["proactiveQueue"] = data["proactiveQueue"]
            if isinstance(data.get("meta"), dict):
                _db["meta"] = data["meta"]
            # 1.0.65: fold any pre-single-track goalTaskLinks
            # into the taskGoals field store. The fold guards
            # itself; a failure leaves the collection in place
            # for the next boot and never reaches the degraded
            # path below.
            _migrate_goal_task_links()
            return
        except Exception as e:
            # Stop-bleed (F04/R1): NEVER fall through to saving an
            # empty db over the data file. Quarantine the original
            # (rename, never delete) and run read-only degraded.
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            quarantine = DATA_PATH.with_name(
                f"{DATA_PATH.name}.corrupt-{stamp}")
            try:
                os.replace(DATA_PATH, quarantine)
                where = str(quarantine)
            except OSError as qe:
                where = (f"隔离改名失败（{qe}），原件仍在原地 "
                         f"{DATA_PATH}")
            _degraded_reason = (
                f"数据文件解析失败（{redact(e)}）；原件已隔离；"
                "桥以空库只读降级运行，禁止回写正式数据文件")
            _print(f"DATA DEGRADED: {_degraded_reason}",
                  file=sys.stderr, flush=True)
            return
    with _lock:
        _save_locked()


class _Err(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def _clean_title(value, what="标题") -> str:
    if not isinstance(value, str) or not value.strip():
        raise _Err(400, f"{what}不能为空")
    return value.strip()


# G-6 (2026-11-24): _build_milestones removed with the milestone
# concept (see oneday_seg_goals.py G-6 note).


GOAL_STATUSES = ("active", "completed")
GOAL_SOURCES = ("manual", "chat")
#: goal categories (0.40.0, spec three-pages v2 ch.3): the
#: seven life-area buckets of the creation flow. A category is
#: the user's own pick at creation/edit time -- the bridge
#: validates the enum and stores it verbatim, it never infers
#: one for existing goals (they read back null).
GOAL_CATEGORIES = ("health", "relationships", "finance",
                   "career", "interest", "efficiency", "other")

# REPAIR (2026-11-24, goals B/C/D line): the block above had
# been lost from this repo copy while the shipped image kept
# it (found by diffing the running 1.0.70 container against
# the repo -- goal creation 500'd from a repo build). Restored
# verbatim from production 1.0.70. The repo additionally runs
# ahead of production in the section-459 blocks (briefings
# single-layer text, ideas domain/categoryLabel/kind, feed
# event posts); those belong to the section-459 line and ship
# on its own schedule, not with the goals package.
def _clean_category(value):
    """None -> None (uncategorised); an enum string -> itself;
    anything else is a 400 with a human reason."""
    if value is None:
        return None
    if not isinstance(value, str) or value not in GOAL_CATEGORIES:
        raise _Err(400, "类别不对（只许健康/人际关系/财务/事业/"
                        "兴趣/效率提升/其他七类之一，或不选）")
    return value
ENTRY_SOURCES = ("user", "agent")
ENTRY_BODY_CAP = 2000


def _goal_status(g: dict) -> str:
    status = g.get("status")
    return status if status in GOAL_STATUSES else "active"


def _goal_view(g: dict) -> dict:
    # latestEntry is embedded so the App's list rows can show
    # the newest progress line without an N+1 fetch per goal;
    # it is a read-through of the entries collection, never a
    # second store. (_entry_view is defined below; resolved at
    # call time.)
    latest = None
    entries_count = 0
    for e in _db["goalEntries"]:
        if e["goalId"] == g["id"]:
            entries_count += 1
            if (latest is None
                    or e["createdAt"] > latest["createdAt"]):
                latest = e
    # G-3a (2026-11-24): cheap change fingerprint so the App can
    # revalidate the goals face conditionally while it is visible
    # -- agent-written progress becomes visible without the user
    # leaving and re-entering the face. Any entry add/delete or
    # goal edit moves the fingerprint.
    fingerprint = hashlib.sha1(
        f"{g['id']}|{g['updatedAt']}|{entries_count}|"
        f"{latest['id'] if latest else ''}|"
        f"{latest['createdAt'] if latest else ''}".encode()
    ).hexdigest()[:16]
    return {
        "id": g["id"],
        "title": g["title"],
        "note": g.get("note", ""),
        "createdAt": g["createdAt"],
        "updatedAt": g["updatedAt"],
        "status": _goal_status(g),
        "completedAt": g.get("completedAt"),
        "parentId": g.get("parentId"),
        "source": g.get("source")
        if g.get("source") in GOAL_SOURCES else "manual",
        # category: stored verbatim or null; anything off-enum
        # in an old/foreign record reads as null, never guessed
        "category": g.get("category")
        if g.get("category") in GOAL_CATEGORIES else None,
        "latestEntry": _entry_view(latest) if latest else None,
        "entriesFingerprint": fingerprint,
        # GD-1 (parity spec ch.4.3): read-time activity
        # derivation over the goal's kanban links; defined in
        # the goal-task-links section below, resolved at call
        # time. Presentation only -- status above stays the
        # lifecycle truth.
        "activity": _goal_activity(g, latest),
    }


def _check_parent(gid_self, parent_id, goals: list) -> None:
    """Depth rules for parentId (P2): the parent must exist, must
    itself be top-level (sub-goals are exactly one level deep), a
    goal cannot parent itself, and a goal that already HAS
    sub-goals cannot become one (its children would end up two
    levels deep). Raises _Err(400) with a human reason."""
    if parent_id is None:
        return
    if not isinstance(parent_id, str):
        raise _Err(400, "parentId 必须是字符串或 null")
    if gid_self is not None and parent_id == gid_self:
        raise _Err(400, "目标不能把自己设为父目标")
    parent = next((g for g in goals if g["id"] == parent_id), None)
    if parent is None:
        raise _Err(400, "父目标不存在")
    if parent.get("parentId"):
        raise _Err(400, "子目标下不能再挂子目标（只许一层）")
    if gid_self is not None and any(
            g.get("parentId") == gid_self for g in goals):
        raise _Err(400, "这个目标已有子目标，不能再成为子目标")


IDEA_STATUSES = ("pending", "adopted", "dismissed", "expired",
                 "built", "merged")
IDEA_SOURCES = ("generated", "manual")
#: status transitions a client PATCH may drive (expired is set by the
#: bridge sweep only; adopted is set by PATCHing taskId or directly)
IDEA_PATCH_TRANSITIONS = {
    "pending": {"adopted", "dismissed"},
    "adopted": set(),
    "dismissed": set(),
    "expired": set(),
    # ID-2: built/merged are loop-settled terminal states,
    # never client-writable
    "built": set(),
    "merged": set(),
}
IDEA_EXPIRE_SECONDS = 14 * 24 * 3600  # generated cards live 14 days
#: why a card was dismissed, as marked by the user (ideas v2):
#: "tooGeneric" feeds the generator's avoidance + specificity bar
IDEA_DISMISS_REASONS = ("tooGeneric",)
#: idea categories (1.0.34): the SAME seven-bucket enum as the
#: goal creation flow -- GOAL_CATEGORIES above is the bridge's
#: single source of truth for both. Unlike goals (the user's own
#: pick, may stay null), every idea card carries one: the
#: generator must name it, _clean_idea_category folds a missing
#: or illegal value to "other", and POST /ideas defaults a
#: missing key to "other". A card is never dropped over its
#: category.
IDEA_DEFAULT_CATEGORY = "other"
#: Chinese labels for the enum, for prompts and human surfaces
CATEGORY_LABELS = {
    "health": "健康", "relationships": "人际关系",
    "finance": "财务", "career": "事业", "interest": "兴趣",
    "efficiency": "效率提升", "other": "其他",
}


def _clean_idea_category(value):
    """An enum string -> itself; anything else (incl. None)
    -> "other". Never raises: categories fold, cards don't drop."""
    if isinstance(value, str) and value in GOAL_CATEGORIES:
        return value
    return IDEA_DEFAULT_CATEGORY


#: Idea classification, Muse two-dimension form (§459,
#: 2026-11-24): a DOMAIN from Muse's own production domain
#: set (ideas.ideas.domain, observed 2026-11-24) plus a FREE
#: category label in the user's own words (Muse's
#: category_label: 「婚礼」「服务器运维」「Ai 培训」...). The
#: legacy seven-bucket category above stays stored and served
#: for the shipped App; domain/categoryLabel are the parity
#: dimensions the next App consumes. Domain folds like the
#: legacy category does -- a card is never dropped over its
#: classification.
IDEAS_DOMAINS = (
    "personal_productivity", "entertainment", "shopping",
    "finance", "relationships", "health", "career",
    "home_automation", "connect_devices", "creation_media",
    "family", "goal_scoped",
)
DOMAIN_LABELS = {
    "personal_productivity": "个人效率", "entertainment": "娱乐",
    "shopping": "购物", "finance": "财务",
    "relationships": "人际关系", "health": "健康",
    "career": "事业", "home_automation": "智能家居",
    "connect_devices": "设备连接", "creation_media": "创作媒体",
    "family": "家庭", "goal_scoped": "目标相关",
}
IDEA_DEFAULT_DOMAIN = "personal_productivity"
#: legacy seven-bucket -> domain, for pre-§459 cards and for
#: folding a card that arrives with only the legacy field
_LEGACY_CATEGORY_DOMAIN = {
    "health": "health", "relationships": "relationships",
    "finance": "finance", "career": "career",
    "efficiency": "personal_productivity",
    "interest": "entertainment", "other": "personal_productivity",
}
#: idea landing kinds (ledger item 30, nanoMuse evaluation):
#: the card declares at generation time what tapping it
#: builds -- a chat, a routine, or a goal. chat is the
#: dominant default; anything unknown folds to it.
IDEA_KINDS = ("chat", "routine", "goal")
IDEA_DEFAULT_KIND = "chat"


def _clean_idea_domain(value, legacy_category=None):
    """A Muse domain string -> itself; a missing/illegal one
    derives from the legacy category when available, else the
    default domain. Never raises, never returns None: every
    card has a domain."""
    if isinstance(value, str) and value in IDEAS_DOMAINS:
        return value
    mapped = _LEGACY_CATEGORY_DOMAIN.get(
        _clean_idea_category(legacy_category)
        if legacy_category is not None else None)
    return mapped or IDEA_DEFAULT_DOMAIN


def _clean_idea_kind(value):
    """chat/routine/goal -> itself; anything else -> chat."""
    if isinstance(value, str) and value in IDEA_KINDS:
        return value
    return IDEA_DEFAULT_KIND


def _clean_category_label(value):
    """The free category label: a short string in the user's
    own words (<= 24 chars) or None. Presentation-only; a bad
    shape collapses to None, never drops the card."""
    if not isinstance(value, str):
        return None
    value = " ".join(value.split()).strip()
    if not value:
        return None
    return value[:24]


def _clean_emoji(value):
    """One content emoji chosen by the generator; anything
    that is not a short string collapses to None (the App
    falls back by anchor kind). Length cap only -- grapheme
    counting is the client's business."""
    if not isinstance(value, str):
        return None
    value = value.strip()
    if not value or len(value) > 16:
        return None
    return value


def _clean_deliverables(value) -> list:
    """The idea detail sheet's includes list
    ([{name, summary}]); malformed entries are dropped,
    never the whole card."""
    out = []
    if not isinstance(value, list):
        return out
    for d in value[:6]:
        if not isinstance(d, dict):
            continue
        name = str(d.get("name") or "").strip()
        if not name:
            continue
        out.append({
            "name": name[:60],
            "summary": str(d.get("summary") or "").strip()[:120],
        })
    return out


def _idea_view(i: dict) -> dict:
    return {
        "id": i["id"],
        "title": i["title"],
        "detail": i.get("detail", ""),
        # 0.47.0 (§117): content emoji + includes list;
        # pre-existing records carry neither (None / [])
        "emoji": i.get("emoji"),
        # 1.0.34: every card surfaces a category; a record
        # without one (pre-backfill terminal cards) reads
        # "other" here -- the stored value is never invented,
        # the view just never emits null.
        "category": _clean_idea_category(i.get("category")),
        # §459: the Muse two-dimension classification.
        # domain never reads null (folded from the stored
        # value, else derived from the legacy category);
        # categoryLabel is the free label and may be null on
        # pre-migration cards; kind is the landing form the
        # card declares (chat default).
        "domain": _clean_idea_domain(i.get("domain"),
                                     i.get("category")),
        "categoryLabel": _clean_category_label(
            i.get("categoryLabel")),
        "kind": _clean_idea_kind(i.get("kind")),
        "deliverables": [dict(d)
                         for d in i.get("deliverables") or []],
        "goalId": i.get("goalId"),
        "createdAt": i["createdAt"],
        "source": i.get("source", "manual"),
        "evidence": i.get("evidence", ""),
        "evidenceRef": i.get("evidenceRef"),
        # ideas v2 (0.39.0): the resolved anchor behind evidenceRef,
        # "<kind>:<object id>" -- round-relative ref numbers are
        # meaningless across rounds, anchor-level dedup keys on this.
        "anchorId": i.get("anchorId"),
        "dismissReason": i.get("dismissReason"),
        # ID-2 (rev2 ch.2): pool bookkeeping rides the view --
        # quality triple + composite, the settled pool score and
        # its one-line reason, the dedup fingerprint and the
        # merge mapping (a merged card's canonical id), and the
        # pool origin (native | seed; manual cards read manual).
        "quality": i.get("quality"),
        "poolScore": i.get("poolScore"),
        "scoreWhy": i.get("scoreWhy"),
        "contentFingerprint": i.get("contentFingerprint"),
        "mergedInto": i.get("mergedInto"),
        "mergeReason": i.get("mergeReason"),
        "origin": i.get("origin") or (
            "native" if i.get("source") == "generated"
            else "manual"),
        "status": i.get("status", "pending"),
        "taskId": i.get("taskId"),
        "expiresAt": i.get("expiresAt"),
    }


def _load_segment(name: str) -> None:
    """C-8 split loader: exec one segment file in this
    module's own namespace, at the segment's original
    position, so definition order, module-level side
    effects, the shared _db and every monkeypatch seam stay
    exactly as they were in the single file. The segment
    files (oneday_seg_*.py) sit next to this file in both
    the repo and the shipped image."""
    _path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), name)
    with open(_path, encoding="utf-8") as _f:
        _src = _f.read()
    exec(compile(_src, name, "exec"), globals())


# --- [C-8 segment] goals: oneday_seg_goals.py ----------
_load_segment("oneday_seg_goals.py")

# --- [C-8 segment] traces: oneday_seg_traces.py --------
_load_segment("oneday_seg_traces.py")

# --- [C-8 segment] goals_facade: oneday_seg_goals_facade.py -
_load_segment("oneday_seg_goals_facade.py")

# --- [C-8 segment] sessions: oneday_seg_sessions.py ----
_load_segment("oneday_seg_sessions.py")

# --- [C-8 segment] automation: oneday_seg_automation.py -
_load_segment("oneday_seg_automation.py")

# --- [C-8 segment] goals_activity: oneday_seg_goals_activity.py -
_load_segment("oneday_seg_goals_activity.py")

# --- [C-8 segment] ideas_pool: oneday_seg_ideas_pool.py -
_load_segment("oneday_seg_ideas_pool.py")

# --- [C-8 segment] monitors: oneday_seg_monitors.py ----
_load_segment("oneday_seg_monitors.py")

# --- [C-8 segment] ideas_gen: oneday_seg_ideas_gen.py --
_load_segment("oneday_seg_ideas_gen.py")

# --- [C-8 segment] briefings: oneday_seg_briefings.py --
_load_segment("oneday_seg_briefings.py")

# --- [C-8 segment] feed: oneday_seg_feed.py ------------
_load_segment("oneday_seg_feed.py")

# --- [C-8 segment] ledger: oneday_seg_ledger.py --------
_load_segment("oneday_seg_ledger.py")

# --- [C-8 segment] delivery: oneday_seg_delivery.py ----
_load_segment("oneday_seg_delivery.py")

# --- [A-06 segment] file library: oneday_seg_filelibrary.py --
_load_segment("oneday_seg_filelibrary.py")

# --- [1.0.73 segment] library MCP facade: oneday_seg_library_mcp.py --
_load_segment("oneday_seg_library_mcp.py")

# --- [B-01 segment] cron convergence: oneday_seg_cron.py --
_load_segment("oneday_seg_cron.py")




class _Headers(dict):
    """Case-insensitive header lookup over a plain dict (the bridge
    reads Authorization / Content-Length / X-Cron-Callback-Key)."""

    def get(self, name, default=None):
        for k, v in self.items():
            if k.lower() == name.lower():
                return v
        return default


class Handler:
    """Request-context adapter: the bridge's dispatch machinery,
    driven by an in-process context instead of a socket. _send /
    _send_bytes record the response into the context; _body reads
    the buffered request body through rfile, as on the socket."""

    def __init__(self, ctx):
        self.command = ctx["method"]
        self.path = ctx["path"]
        self.headers = ctx["headers"]
        self.rfile = io.BytesIO(ctx["body"])
        self._resp = ctx["resp"]

    def _send(self, status: int, obj: dict) -> None:
        raw = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self._resp["status"] = status
        self._resp["body"] = raw
        self._resp["headers"] = {
            "Content-Type": "application/json; charset=utf-8"}
        _print(f"{self.command} {urlparse(self.path).path} -> {status}",
               flush=True)

    def _authed(self) -> bool:
        # Batch 3: authentication lives in api_server (@_require_auth,
        # API_SERVER_KEY single source); every request reaching this
        # dispatch has already been authenticated there. The cron
        # callback surface keeps its own dedicated key check in
        # _dispatch_cron_callback, upstream of this gate.
        return True

    def _dispatch_cron_callback(self, parts) -> None:
        # /internal/cron/* -- the Hermes cron engine's callback
        # surface (B-01, 1.0.59). Authenticated by the dedicated
        # callback key ONLY (never the bridge Bearer key, which
        # no cron script ever sees). Fail-closed when no key is
        # configured.
        try:
            key = _cron_callback_key()
            hdr = self.headers.get("X-Cron-Callback-Key", "")
            if not key or not hmac.compare_digest(hdr, key):
                return self._send(
                    401, {"error": "未授权：缺少或错误的回调钥匙"})
            if self.command != "POST":
                return self._send(404, {"error": "路径不存在"})
            if parts == ["internal", "cron", "ping"]:
                return self._send(200, {"ok": True, "pong": _now()})
            if len(parts) == 4 and parts[:3] == ["internal", "cron",
                                                  "rounds"]:
                status, obj = _cron_cb_round(parts[3])
                return self._send(status, obj)
            if len(parts) == 5 and parts[:3] == ["internal", "cron",
                                                 "monitors"] \
                    and parts[4] == "check":
                status, obj = _cron_cb_monitor_check(parts[3])
                return self._send(status, obj)
            return self._send(404, {"error": "路径不存在"})
        except _Err as e:
            return self._send(e.status, {"error": e.message})
        except Exception as e:
            _print(f"cron callback error: {e!r}", file=sys.stderr,
                  flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    def _dispatch_monitors(self, parts) -> None:
        # Monitor handlers take their own locks: checks fetch outside
        # the global lock, so this branch runs before the locked block.
        try:
            if parts == ["monitors", "notifications"]:
                # B-03 (1.0.63): the notification ledger's read
                # surface -- overview aggregates at read time
                # from here instead of tailing the file. Checked
                # before the len==2 monitor-id branch on purpose:
                # "notifications" is a fixed word, never an id.
                if self.command == "GET":
                    query = parse_qs(urlparse(self.path).query)
                    try:
                        limit = int(query.get("limit", ["100"])[0])
                    except Exception:
                        limit = 100
                    limit = max(1, min(limit, 200))
                    return self._send(200, {
                        "items": _list_monitor_notifications(limit)})
            if parts == ["monitors"]:
                if self.command == "GET":
                    return self._send(200, {"items": _list_monitors()})
                if self.command == "POST":
                    return self._send(201, _create_monitor(self._body()))
            elif len(parts) == 2 and parts[0] == "monitors":
                if self.command == "DELETE":
                    _delete_monitor(parts[1])
                    return self._send(200, {"ok": True})
            elif len(parts) == 3 and parts[0] == "monitors":
                mid, action = parts[1], parts[2]
                if self.command == "GET" and action == "changes":
                    return self._send(200, {"items": _list_changes(mid)})
                if self.command == "POST" and action == "check":
                    return self._send(200, _check_monitor(mid))
                if self.command == "POST" and action == "pause":
                    return self._send(200, _set_enabled(mid, False))
                if self.command == "POST" and action == "resume":
                    return self._send(200, _set_enabled(mid, True))
                if self.command == "POST" and action == "read":
                    _read_monitor(mid)
                    return self._send(200, {"ok": True})
            elif len(parts) == 5 and parts[0] == "monitors" \
                    and parts[2] == "changes" and parts[4] == "read":
                if self.command == "POST":
                    _read_change(parts[1], parts[3])
                    return self._send(200, {"ok": True})
            return self._send(404, {"error": "路径不存在"})
        except _Err as e:
            return self._send(e.status, {"error": e.message})
        except Exception as e:  # never leak internals, but don't hang
            _print(f"unhandled error: {e!r}", file=sys.stderr, flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    def _dispatch_traces(self, parts) -> None:
        # P0 留痕底座接口：POST 写一条、GET 读列表/单条。写入的五
        # 要素在 _create_trace 门口校验；降级模式下非 GET 已被
        # _dispatch 总闸 503，不会走到这里。
        try:
            if parts == ["traces"]:
                if self.command == "GET":
                    query = parse_qs(urlparse(self.path).query)
                    return self._send(200,
                                      {"items": _list_traces(query)})
                if self.command == "POST":
                    return self._send(201,
                                      _create_trace(self._body()))
            elif len(parts) == 2 and parts[0] == "traces":
                if self.command == "GET":
                    return self._send(200, _get_trace(parts[1]))
            return self._send(404, {"error": "路径不存在"})
        except _Err as e:
            return self._send(e.status, {"error": e.message})
        except Exception as e:  # never leak internals, but don't hang
            _print(f"unhandled error: {e!r}", file=sys.stderr,
                  flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    def _dispatch_goals_mcp(self) -> None:
        # P3 目标门面：与 device 桥 /mcp 同形的 JSON-RPC 门面。
        # 每个 tools/call 先经 _goal_tool_call 落 P0 留痕再回执。
        if self.command != "POST":
            return self._send(405, {"error": "方法不允许"})
        try:
            body = self._body()
        except Exception as e:
            return self._send(400, {"error": f"请求体不对：{e}"})
        rid = body.get("id")
        method = body.get("method", "")
        if rid is None:  # notification: accept, no reply body needed
            return self._send(202, {})
        if method == "initialize":
            return self._send(200, {
                "jsonrpc": "2.0", "id": rid, "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "oneday-goals",
                                   "version": "0.1.0"}}})
        if method == "ping":
            return self._send(200, {"jsonrpc": "2.0", "id": rid,
                                    "result": {}})
        if method == "tools/list":
            tools = [{"name": t["name"],
                      "description": t["description"],
                      "inputSchema": t["inputSchema"]}
                     for t in GOAL_TOOLS]
            return self._send(200, {"jsonrpc": "2.0", "id": rid,
                                    "result": {"tools": tools}})
        if method == "tools/call":
            params = body.get("params") or {}
            result, is_error = _goal_tool_call(
                params.get("name", ""),
                params.get("arguments") or {})
            return self._send(200, {
                "jsonrpc": "2.0", "id": rid, "result": {
                    "content": [{"type": "text", "text": json.dumps(
                        result, ensure_ascii=False)}],
                    "isError": is_error}})
        return self._send(200, {
            "jsonrpc": "2.0", "id": rid, "error": {
                "code": -32601,
                "message": f"method not found: {method}"}})

    # RETIRED 2026-11-14 (A3): /ai-sessions REST 门退役，核心逻辑
    # (_create_ai_session_core 等) 保留供 /mcp-sessions 使用。
    # AI_SESSION_PREFIX 与分类规则 R3b 仍在生效，不可删除。
    # def _dispatch_ai_sessions(self, parts) -> None:
    #     # P2 会话包 REST 门：POST 建旁聊（经 traced core，成败都
    #     # 先落一条 sessions.create 留痕）、GET 读出生记录（验链
    #     # 与清理的出处）。降级模式下非 GET 已被 _dispatch 总闸
    #     # 503，不会走到 POST。
    #     try:
    #         if parts == ["ai-sessions"]:
    #             if self.command == "GET":
    #                 query = parse_qs(urlparse(self.path).query)
    #                 return self._send(
    #                     200, {"items": _list_ai_sessions(
    #                         (query.get("limit") or [None])[0])})
    #             if self.command == "POST":
    #                 return self._send(
    #                     201, _create_ai_session_traced(self._body()))
    #         return self._send(404, {"error": "路径不存在"})
    #     except _Err as e:
    #         return self._send(e.status, {"error": e.message})
    #     except Exception as e:  # never leak internals, but don't hang
    #         _print(f"unhandled error: {e!r}", file=sys.stderr,
    #                   flush=True)
    #         return self._send(500, {"error": "服务器内部错误"})

    def _dispatch_sessions_mcp(self) -> None:
        # P2 会话门面：与 goals 门面同形的 JSON-RPC，独立端点
        # /mcp-sessions（goals 门面的 tools/list 契约一字不动）；
        # 每个 tools/call 经 _session_tool_call 落 P0 留痕。
        if self.command != "POST":
            return self._send(405, {"error": "方法不允许"})
        try:
            body = self._body()
        except Exception as e:
            return self._send(400, {"error": f"请求体不对：{e}"})
        rid = body.get("id")
        method = body.get("method", "")
        if rid is None:  # notification: accept, no reply body needed
            return self._send(202, {})
        if method == "initialize":
            return self._send(200, {
                "jsonrpc": "2.0", "id": rid, "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "oneday-sessions",
                                   "version": "0.1.0"}}})
        if method == "ping":
            return self._send(200, {"jsonrpc": "2.0", "id": rid,
                                    "result": {}})
        if method == "tools/list":
            tools = [{"name": t["name"],
                      "description": t["description"],
                      "inputSchema": t["inputSchema"]}
                     for t in SESSION_TOOLS]
            return self._send(200, {"jsonrpc": "2.0", "id": rid,
                                    "result": {"tools": tools}})
        if method == "tools/call":
            params = body.get("params") or {}
            result, is_error = _session_tool_call(
                params.get("name", ""),
                params.get("arguments") or {})
            return self._send(200, {
                "jsonrpc": "2.0", "id": rid, "result": {
                    "content": [{"type": "text", "text": json.dumps(
                        result, ensure_ascii=False)}],
                    "isError": is_error}})
        return self._send(200, {
            "jsonrpc": "2.0", "id": rid, "error": {
                "code": -32601,
                "message": f"method not found: {method}"}})

    def _dispatch_library_mcp(self) -> None:
        # 资源库门面（1.0.73）：与 goals/sessions 门面同形的
        # JSON-RPC，独立端点 /library-mcp；只读工具 library_list
        # 内部直调 _file_library_view（与 App 资源库页同一函数、
        # 同一准入集）；每个 tools/call 经 _library_tool_call
        # 落 P0 留痕。
        if self.command != "POST":
            return self._send(405, {"error": "方法不允许"})
        try:
            body = self._body()
        except Exception as e:
            return self._send(400, {"error": f"请求体不对：{e}"})
        rid = body.get("id")
        method = body.get("method", "")
        if rid is None:  # notification: accept, no reply body needed
            return self._send(202, {})
        if method == "initialize":
            return self._send(200, {
                "jsonrpc": "2.0", "id": rid, "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "oneday-library",
                                   "version": "0.1.0"}}})
        if method == "ping":
            return self._send(200, {"jsonrpc": "2.0", "id": rid,
                                    "result": {}})
        if method == "tools/list":
            tools = [{"name": t["name"],
                      "description": t["description"],
                      "inputSchema": t["inputSchema"]}
                     for t in LIBRARY_TOOLS]
            return self._send(200, {"jsonrpc": "2.0", "id": rid,
                                    "result": {"tools": tools}})
        if method == "tools/call":
            params = body.get("params") or {}
            result, is_error = _library_tool_call(
                params.get("name", ""),
                params.get("arguments") or {})
            return self._send(200, {
                "jsonrpc": "2.0", "id": rid, "result": {
                    "content": [{"type": "text", "text": json.dumps(
                        result, ensure_ascii=False)}],
                    "isError": is_error}})
        return self._send(200, {
            "jsonrpc": "2.0", "id": rid, "error": {
                "code": -32601,
                "message": f"method not found: {method}"}})

    def _dispatch_automation_mcp(self) -> None:
        """POST /automation-mcp: the MCP-shaped automation facade
        (P4+P5, see AUTOMATION_TOOLS). Same JSON-RPC surface as
        _dispatch_goals_mcp; every tools/call books its P0 trace
        inside _automation_tool_call before answering."""
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except (TypeError, ValueError):
            length = 0
        raw = self.rfile.read(length) if length > 0 else b""
        try:
            req = json.loads(raw.decode("utf-8")) if raw else {}
            if not isinstance(req, dict):
                raise ValueError("body must be an object")
        except Exception:
            return self._send(400, {"jsonrpc": "2.0", "id": None,
                                    "error": {"code": -32700,
                                              "message":
                                              "Parse error"}})
        method = req.get("method")
        rid = req.get("id")
        if method == "initialize":
            params = req.get("params") or {}
            return self._send(200, {
                "jsonrpc": "2.0", "id": rid,
                "result": {
                    "protocolVersion": params.get(
                        "protocolVersion", "2024-11-05"),
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "oneday-automation",
                                   "version": "0.1.0"}}})
        if method == "ping":
            return self._send(200, {"jsonrpc": "2.0", "id": rid,
                                    "result": {}})
        if isinstance(method, str) \
                and method.startswith("notifications/"):
            return self._send(202, {})
        if method == "tools/list":
            return self._send(200, {
                "jsonrpc": "2.0", "id": rid,
                "result": {"tools": AUTOMATION_TOOLS}})
        if method == "tools/call":
            params = req.get("params") or {}
            name = params.get("name")
            args = params.get("arguments")
            if not isinstance(name, str) \
                    or not isinstance(args, dict):
                return self._send(200, {
                    "jsonrpc": "2.0", "id": rid,
                    "result": {"content": [{
                        "type": "text",
                        "text": "tools/call 需要 name 与 "
                                "arguments 对象"}],
                        "isError": True}})
            result = _automation_tool_call(name, args)
            return self._send(200, {"jsonrpc": "2.0", "id": rid,
                                    "result": result})
        return self._send(200, {
            "jsonrpc": "2.0", "id": rid,
            "error": {"code": -32601,
                      "message": f"Method not found: {method}"}})

    def _dispatch_goaldepth(self, parts) -> None:
        # Goal-depth handlers (P2 entries/briefings) take their own
        # short locks, like the generation branch: a briefing round
        # runs on its own thread and must never sit inside the
        # dispatch lock.
        try:
            if parts == ["goals", "briefings", "generate"]:
                if self.command == "POST":
                    # G-7 (2026-11-24): manual briefing generation
                    # is an internal ops surface now (Muse parity:
                    # briefings are system-scheduled, never on
                    # demand). The route stays for server-side
                    # diagnostics but requires the cron callback
                    # key on top of the bridge key; the App has no
                    # caller and gets a plain 404.
                    cb_key = _cron_callback_key()
                    cb_hdr = self.headers.get(
                        "X-Cron-Callback-Key", "")
                    if not cb_key or not hmac.compare_digest(
                            cb_hdr, cb_key):
                        return self._send(
                            404, {"error": "路径不存在"})
                    if _start_briefing("manual"):
                        return self._send(202, {"ok": True,
                                                "started": True})
                    return self._send(
                        409, {"error": "一轮简报生成正在进行中"})
            elif parts == ["goals", "briefings"]:
                if self.command == "GET":
                    return self._send(200, _briefing_ledger_view())
            elif len(parts) == 3 and parts[0] == "goals" \
                    and parts[2] == "entries":
                gid = parts[1]
                if self.command == "GET":
                    with _lock:
                        return self._send(
                            200, {"items": _list_entries(gid)})
                if self.command == "POST":
                    with _lock:
                        return self._send(
                            201, _create_entry(gid, self._body()))
            elif len(parts) == 4 and parts[0] == "goals" \
                    and parts[2] == "entries":
                if self.command == "DELETE":
                    with _lock:
                        _delete_entry(parts[1], parts[3])
                    return self._send(200, {"ok": True})
            elif len(parts) == 3 and parts[0] == "goals" \
                    and parts[2] == "briefings":
                if self.command == "GET":
                    with _lock:
                        return self._send(
                            200, {"items": _list_briefings(parts[1])})
            elif len(parts) == 5 and parts[0] == "goals" \
                    and parts[2] == "briefings" \
                    and parts[4] == "opened":
                if self.command == "POST":
                    with _lock:
                        return self._send(
                            200, _mark_briefing_opened(
                                parts[1], parts[3]))
            elif len(parts) == 3 and parts[0] == "goals" \
                    and parts[2] == "tasks":
                if self.command == "GET":
                    with _lock:
                        return self._send(
                            200, {"items": _goal_tasks_view(
                                parts[1])})
            elif len(parts) == 3 and parts[0] == "goals" \
                    and parts[2] == "task-links":
                gid = parts[1]
                if self.command == "GET":
                    with _lock:
                        return self._send(
                            200, {"items": _list_task_links(gid)})
                if self.command == "POST":
                    with _lock:
                        return self._send(
                            201, _create_task_link(
                                gid, self._body()))
            elif len(parts) == 3 and parts[0] == "goals" \
                    and parts[2] == "delegate":
                # 1.0.65 one-shot delegation: NOT wrapped in
                # _lock here -- the handler takes the lock only
                # for its short store reads/writes around the
                # Dashboard round-trip (creating the card while
                # holding the store lock would stall every other
                # face behind a network call).
                if self.command == "POST":
                    return self._send(
                        201, _delegate_goal_task(
                            parts[1], self._body()))
            elif len(parts) == 3 and parts[0] == "tasks" \
                    and parts[2] == "goal":
                # 1.0.65: the goalId field's standalone write
                # face (assign / move / clear).
                if self.command == "PUT":
                    with _lock:
                        return self._send(
                            200, _put_task_goal(
                                parts[1], self._body()))
            return self._send(404, {"error": "路径不存在"})
        except _Err as e:
            return self._send(e.status, {"error": e.message})
        except Exception as e:  # never leak internals, but don't hang
            _print(f"unhandled error: {e!r}", file=sys.stderr, flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    def _dispatch_generation(self, parts) -> None:
        # Generation/meta handlers take their own short locks:
        # a generation round runs on its own thread and must never
        # sit inside the dispatch lock.
        try:
            if parts == ["ideas", "generate"]:
                if self.command == "POST":
                    if _start_generation("manual"):
                        return self._send(202, {"ok": True,
                                                "started": True})
                    return self._send(409, {"error": "一轮生成正在进行中"})
            elif parts == ["ideas", "generation"]:
                if self.command == "GET":
                    return self._send(200, _generation_view())
            elif parts == ["meta", "brief"]:
                # Two-layer brief (0.38.0): GET returns both
                # layers; PUT accepts {"interest": str} (user
                # layer -- a true change starts an expansion
                # run) and/or {"brief": str} (execution layer,
                # set verbatim; a true change triggers a
                # research round). The pre-0.38.0 {"brief": str}
                # contract keeps working unchanged in effect.
                if self.command == "GET":
                    with _lock:
                        doc = _brief_doc_locked()
                    return self._send(200, doc)
                if self.command == "PUT":
                    body = self._body()
                    interest = body.get("interest")
                    brief = body.get("brief")
                    # §459 single-layer save: {"text": ...} is
                    # the one-field form -- it saves verbatim
                    # as the interest layer (the user's own
                    # words); the background expansion polishes
                    # it afterwards, never during the save.
                    if body.get("text") is not None:
                        if not isinstance(body.get("text"), str):
                            raise _Err(400, "text 必须是字符串")
                        if interest is None:
                            interest = body.get("text")
                    if interest is not None \
                            and not isinstance(interest, str):
                        raise _Err(400, "interest 必须是字符串")
                    if brief is not None \
                            and not isinstance(brief, str):
                        raise _Err(400, "brief 必须是字符串")
                    if interest is None and brief is None:
                        raise _Err(400, "需要 interest 或 brief 字段")
                    if isinstance(interest, str) \
                            and len(interest) > BRIEF_INTEREST_LIMIT:
                        raise _Err(400, "兴趣原文太长（上限 2000 字）")
                    if isinstance(brief, str) \
                            and len(brief) > BRIEF_PROMPT_LIMIT:
                        raise _Err(400, "brief 太长（上限 4000 字）")
                    expand_interest = None
                    brief_changed = False
                    with _lock:
                        if isinstance(brief, str):
                            old_brief = str(
                                _db["meta"].get("brief", "") or "")
                            if brief.strip() != old_brief.strip():
                                brief_changed = True
                            _db["meta"]["brief"] = brief
                            _db["meta"]["briefUpdatedAt"] = _now()
                        if isinstance(interest, str):
                            old_interest = str(
                                _db["meta"].get(
                                    "briefInterest", "") or "")
                            if interest.strip() \
                                    != old_interest.strip():
                                _db["meta"]["briefInterest"] = \
                                    interest
                                _db["meta"][
                                    "briefInterestUpdatedAt"] = \
                                    _now()
                                if interest.strip():
                                    expand_interest = interest
                                    # the interest layer is the
                                    # user's own words: record
                                    # the change as a stated
                                    # taste constraint (spec
                                    # §127, stated outranks
                                    # every inferred signal)
                                    _taste_add_stated_locked(
                                        interest, "brief")
                        _save_locked()
                        doc = _brief_doc_locked()
                    started = False
                    if expand_interest is not None:
                        started = _start_brief_expand(
                            expand_interest)
                    elif brief_changed:
                        started = _start_research("brief")
                    doc["expandStarted"] = started
                    # a stated change is a taste event: the
                    # reconcile folds it outside generation
                    _start_taste_reconcile()
                    return self._send(200, doc)
            return self._send(404, {"error": "路径不存在"})
        except _Err as e:
            return self._send(e.status, {"error": e.message})
        except Exception as e:  # never leak internals, but don't hang
            _print(f"unhandled error: {e!r}", file=sys.stderr, flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    def _dispatch_feed(self, parts) -> None:
        # Feed handlers take their own short locks, like the
        # generation branch: assembly/research rounds run on their
        # own threads and must never sit inside the dispatch lock.
        try:
            if parts == ["feed"]:
                if self.command == "GET":
                    query = parse_qs(urlparse(self.path).query)
                    try:
                        days = float(query.get("days", ["30"])[0])
                    except (TypeError, ValueError):
                        days = 30.0
                    result = self._send(
                        200, {"items": _list_feed(days)})
                    # the reader showing up is itself a
                    # signal: it may queue one adhoc round
                    # (rev2 S1.7; tier-gated inside)
                    _feed_maybe_adhoc()
                    return result
            elif parts == ["feed", "generate"]:
                if self.command == "POST":
                    if _start_research("manual"):
                        return self._send(202, {"ok": True,
                                                "started": True})
                    return self._send(
                        409, {"error": "一轮动态生成正在进行中"})
            elif parts == ["feed", "generation"]:
                if self.command == "GET":
                    return self._send(200, _feed_generation_view())
            elif len(parts) == 2 and parts[0] == "feed":
                if self.command == "GET":
                    return self._send(200, _get_feed_post(parts[1]))
                if self.command == "DELETE":
                    _delete_feed_post(parts[1])
                    _start_taste_reconcile()
                    return self._send(200, {"ok": True})
            elif len(parts) == 3 and parts[0] == "feed" \
                    and parts[2] == "read":
                if self.command == "POST":
                    return self._send(
                        200, _read_feed_post(parts[1]))
            elif len(parts) == 3 and parts[0] == "feed" \
                    and parts[2] == "like":
                if self.command == "POST":
                    body = self._body()
                    liked = body.get("liked")
                    if not isinstance(liked, bool):
                        raise _Err(400, "liked 必须是布尔")
                    view = _like_feed_post(parts[1], liked)
                    _start_taste_reconcile()
                    return self._send(200, view)
            elif len(parts) == 3 and parts[0] == "feed" \
                    and parts[2] == "signal":
                if self.command == "POST":
                    body = self._body()
                    out = _signal_feed_post(
                        parts[1], str(body.get("type") or ""),
                        body.get("note"))
                    _start_taste_reconcile()
                    return self._send(200, out)
            return self._send(404, {"error": "路径不存在"})
        except _Err as e:
            return self._send(e.status, {"error": e.message})
        except Exception as e:  # never leak internals, but don't hang
            _print(f"unhandled error: {e!r}", file=sys.stderr,
                  flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    def _dispatch_ledger(self, parts) -> None:
        # Ledger handlers run outside the dispatch lock: report
        # application and collector writes serialize on the
        # ledger store's own lock, and a slow collector cycle
        # must never stall the bridge's other faces.
        try:
            store = _ledger()
            if parts == ["ledger", "report"]:
                if self.command != "POST":
                    return self._send(405, {"error": "方法不对"})
                body = self._body()
                # Terminal settle summary (hermes-deploy 1.23.0):
                # a terminal report without its own summary gets
                # one derived server-side from the run's last live
                # activity (api_server_runs registry -- the same
                # event stream the capsule phrase reads), so the
                # task row shows the run's last real step. Any
                # failure here leaves the report exactly as filed:
                # a missing summary must never fail a settle.
                if body.get("terminal") \
                        and not str(body.get("summary") or "").strip():
                    try:
                        try:
                            from gateway.platforms import \
                                api_server_runs as _runs_mod
                        except ImportError:
                            import api_server_runs as _runs_mod
                        act = _runs_mod._pop_run_activity(
                            str(body.get("runId") or ""))
                        if act:
                            derived = _ledger_mod \
                                .derive_activity_summary(
                                    act.get("tool"),
                                    act.get("preview"))
                            if derived:
                                body["summary"] = derived
                    except Exception:
                        pass
                item, seq = _ledger_mod.apply_app_report(
                    store, body, tz=_sched_tz())
                return self._send(200, {
                    "seq": seq,
                    "item": _ledger_mod.item_view(item,
                                                  detail=True)})
            if parts == ["ledger", "summary"]:
                if self.command == "GET":
                    return self._send(200, _ledger_counts_view())
            elif parts == ["ledger"]:
                if self.command == "GET":
                    query = parse_qs(urlparse(self.path).query)
                    raw = query.get("since", [None])[0]
                    since = None
                    if raw is not None:
                        try:
                            since = int(raw)
                        except (TypeError, ValueError):
                            raise _Err(400, "since 必须是整数")
                    return self._send(
                        200, _ledger_list_view(since))
            elif parts == ["ledger", "threads"]:
                if self.command == "GET":
                    query = parse_qs(urlparse(self.path).query)
                    raw_limit = query.get("limit", [None])[0]
                    limit = 50
                    if raw_limit is not None:
                        try:
                            limit = int(raw_limit)
                        except (TypeError, ValueError):
                            raise _Err(400, "limit 必须是整数")
                    cursor = query.get("cursor", [None])[0]
                    return self._send(
                        200, _ledger_threads_view(cursor, limit))
            elif len(parts) == 3 and parts[0] == "ledger" \
                    and parts[1] == "threads":
                if self.command == "GET":
                    detail = _ledger_thread_detail(parts[2])
                    if detail is None:
                        return self._send(
                            404, {"error": "线程不存在"})
                    return self._send(200, detail)
            elif len(parts) == 2 and parts[0] == "ledger":
                if self.command == "GET":
                    detail = store.detail(parts[1])
                    if detail is None:
                        return self._send(
                            404, {"error": "条目不存在"})
                    return self._send(200, detail)
            return self._send(404, {"error": "路径不存在"})
        except _ledger_mod.LedgerError as e:
            return self._send(e.status, {"error": e.message})
        except _Err as e:
            return self._send(e.status, {"error": e.message})
        except Exception as e:  # never leak internals, but don't hang
            _print(f"unhandled error: {e!r}", file=sys.stderr,
                  flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    def _dispatch_deliveries(self, parts) -> None:
        try:
            if parts == ["deliveries"]:
                if self.command != "POST":
                    return self._send(405, {"error": "方法不允许"})
                with _DELIVERY_LOCK:
                    code, out = _delivery_register(self._body())
                return self._send(code, out)
            if parts == ["deliveries", "by-message"]:
                # Delivery-sentinel index (plan A): read-only,
                # additive -- pre-sentinel Apps never call this.
                if self.command != "GET":
                    return self._send(405, {"error": "方法不允许"})
                query = parse_qs(urlparse(self.path).query)
                sid = (query.get("session_id") or [""])[0]
                if not sid:
                    return self._send(400,
                                      {"error": "缺少 session_id"})
                mid_raw = (query.get("message_id") or [""])[0]
                if mid_raw:
                    if not mid_raw.isdigit():
                        return self._send(
                            400, {"error": "message_id 不合法"})
                    mid = int(mid_raw)
                    found = _delivery_index(sid, mid)
                    return self._send(200, {
                        "sessionId": sid, "messageId": mid,
                        "deliveries": found[0][1] if found else []})
                return self._send(200, {
                    "sessionId": sid,
                    "messages": [
                        {"messageId": m, "deliveries": items}
                        for m, items in _delivery_index(sid)]})
            if len(parts) in (2, 3) and parts[0] == "deliveries":
                rid = parts[1]
                if not _DELIVERY_ID_RE.match(rid):
                    return self._send(404,
                                      {"error": "登记号不存在"})
                rec = _delivery_find(rid)
                if rec is None:
                    return self._send(404,
                                      {"error": "登记号不存在"})
                if len(parts) == 2:
                    if self.command != "GET":
                        return self._send(405, {"error": "方法不允许"})
                    return self._send(
                        200,
                        _delivery_public(rec, _delivery_status(rec)))
                which = parts[2]
                if which not in ("thumb", "cover", "content"):
                    return self._send(404, {"error": "路径不存在"})
                if self.command != "GET":
                    return self._send(405, {"error": "方法不允许"})
                if _delivery_status(rec) == "gone":
                    return self._send(410, {"error": "文件已不存在"})
                if which == "content":
                    fpath = Path(rec["path"])
                    if not fpath.exists() or not fpath.is_file():
                        return self._send(410, {"error": "文件已不存在"})
                    mime = rec.get("mime") or "application/octet-stream"
                    raw = fpath.read_bytes()
                    total = len(raw)
                    rng = self.headers.get("Range", "")
                    m_rng = re.match(r"^bytes=(\d*)-(\d*)$", rng.strip()) if rng else None
                    extra_hdrs = {
                        "Accept-Ranges": "bytes",
                        "Content-Disposition": f'inline; filename="{rec["name"]}"',
                    }
                    if m_rng and total > 0:
                        s_raw, e_raw = m_rng.group(1), m_rng.group(2)
                        if s_raw == "" and e_raw != "":
                            suffix = int(e_raw)
                            start = max(0, total - suffix)
                            end = total - 1
                        else:
                            start = int(s_raw) if s_raw else 0
                            end = int(e_raw) if e_raw else total - 1
                            end = min(end, total - 1)
                        if start >= total or start > end:
                            self._resp["status"] = 416
                            self._resp["body"] = b""
                            self._resp["headers"] = {
                                "Content-Range": f"bytes */{total}",
                                "Accept-Ranges": "bytes",
                            }
                            return
                        extra_hdrs["Content-Range"] = f"bytes {start}-{end}/{total}"
                        return self._send_bytes(
                            206, raw[start:end + 1], mime,
                            extra_headers=extra_hdrs)
                    return self._send_bytes(
                        200, raw, mime, extra_headers=extra_hdrs)
                asset = DELIVERY_ASSET_DIR / rid / f"{which}.jpg"
                flags = rec.get("cover") or {}
                if not flags.get(which) or not asset.exists():
                    return self._send(404, {"error": "没有这类封面"})
                return self._send_bytes(200, asset.read_bytes(),
                                        "image/jpeg")
            return self._send(404, {"error": "路径不存在"})
        except _Err as e:
            return self._send(e.status, {"error": e.message})
        except Exception as e:
            _print(f"unhandled error: {e!r}", file=sys.stderr,
                  flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    def _send_bytes(self, status: int, raw: bytes,
                    content_type: str,
                    etag: str | None = None,
                    extra_headers: dict | None = None) -> None:
        headers = {"Content-Type": content_type}
        if etag:
            headers["ETag"] = etag
        if extra_headers:
            headers.update(extra_headers)
        headers["Cache-Control"] = \
            "private, max-age=31536000, immutable"
        self._resp["status"] = status
        self._resp["body"] = raw
        self._resp["headers"] = headers
        _print(f"{self.command} {urlparse(self.path).path} -> {status}",
               flush=True)

    def _body(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            raise _Err(400, "请求体长度不对")
        if length > MAX_BODY:
            raise _Err(413, "请求体过大")
        raw = self.rfile.read(length) if length else b""
        if not raw:
            return {}
        try:
            data = json.loads(raw.decode("utf-8"))
        except Exception:
            raise _Err(400, "请求体不是合法 JSON")
        if not isinstance(data, dict):
            raise _Err(400, "请求体必须是 JSON 对象")
        return data

    def _dispatch_file_library(self, parts) -> None:
        # A-06 (1.0.66): the aggregated file-library read
        # surface; the walk + admission live in the filelibrary
        # segment. Read-only; offset/limit paging is optional
        # and never a silent cap (see _file_library_view).
        try:
            if parts == ["file-library"]:
                if self.command != "GET":
                    return self._send(405, {"error": "方法不允许"})
                query = parse_qs(urlparse(self.path).query)
                try:
                    offset = int(query.get("offset", ["0"])[0])
                except (TypeError, ValueError):
                    raise _Err(400, "offset 必须是整数")
                if offset < 0:
                    raise _Err(400, "offset 不得为负")
                limit = None
                raw_limit = query.get("limit", [None])[0]
                if raw_limit is not None:
                    try:
                        limit = int(raw_limit)
                    except (TypeError, ValueError):
                        raise _Err(400, "limit 必须是整数")
                    if limit < 0:
                        raise _Err(400, "limit 不得为负")
                return self._send(
                    200, _file_library_view(offset, limit))
            return self._send(404, {"error": "路径不存在"})
        except _Err as e:
            return self._send(e.status, {"error": e.message})
        except Exception as e:  # never leak internals, but don't hang
            _print(f"unhandled error: {e!r}", file=sys.stderr,
                  flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    def _dispatch(self) -> None:
        path = urlparse(self.path).path.rstrip("/") or "/"
        parts = [p for p in path.split("/") if p]
        try:
            if parts == ["health"]:
                health = {"ok": True, "service": "oneday-bridge",
                          "degraded": bool(_degraded_reason)}
                if _degraded_reason:
                    health["degradedReason"] = _degraded_reason
                    health["writesEnabled"] = False
                try:
                    store = _ledger()
                    hb = store.collector_heartbeat_at
                    health["ledger"] = {
                        "degraded": bool(store.degraded_reason),
                        "items": len(store.items)}
                    if store.degraded_reason:
                        health["ledger"]["degradedReason"] = \
                            store.degraded_reason
                    health["collector"] = {
                        "lastRunAt": hb,
                        "lagSeconds": (round(_now() - hb, 1)
                                       if hb else None)}
                except Exception as e:
                    health["ledger"] = {"error": redact(e)}
                health["deliverySentinel"] = dict(_sentinel_status)
                return self._send(200, health)
            if parts and parts[0] == "internal":
                return self._dispatch_cron_callback(parts)
            if not self._authed():
                return self._send(401, {"error": "未授权：缺少或错误的钥匙"})
            if _degraded_reason and self.command != "GET":
                return self._send(503, {
                    "error": "数据文件损坏，桥处于只读降级模式：写入已停用，"
                             "请先修复数据文件后重启桥",
                    "degraded": True})
            if parts and parts[0] == "traces":
                return self._dispatch_traces(parts)
            if parts == ["mcp"]:
                return self._dispatch_goals_mcp()
            if parts == ["automation-mcp"]:
                return self._dispatch_automation_mcp()
            # RETIRED 2026-11-14 (A3): /ai-sessions REST 门路由已退役
            # if parts and parts[0] == "ai-sessions":
            #     return self._dispatch_ai_sessions(parts)
            if parts == ["mcp-sessions"]:
                return self._dispatch_sessions_mcp()
            if parts == ["library-mcp"]:
                return self._dispatch_library_mcp()
            if parts and parts[0] == "monitors":
                return self._dispatch_monitors(parts)
            if parts == ["meta", "brief"] or (
                    len(parts) == 2 and parts[0] == "ideas"
                    and parts[1] in ("generate", "generation")):
                return self._dispatch_generation(parts)
            if parts and parts[0] == "feed":
                return self._dispatch_feed(parts)
            if parts and parts[0] == "deliveries":
                return self._dispatch_deliveries(parts)
            if parts and parts[0] == "file-library":
                return self._dispatch_file_library(parts)
            # RETIRED 2026-11-14 (API-direct B4/B5): /files/spreadsheet
            # and /media/rendition moved to the standalone fileproc
            # module (port 8652); this bridge answers 404 for them.
            if parts and parts[0] == "ledger":
                return self._dispatch_ledger(parts)
            if parts and parts[0] == "goals" and (
                    parts == ["goals", "briefings"]
                    or parts == ["goals", "briefings", "generate"]
                    or (len(parts) >= 3
                        and parts[2] in ("entries", "briefings",
                                         "task-links", "tasks",
                                         "delegate"))):
                return self._dispatch_goaldepth(parts)
            if len(parts) == 3 and parts[0] == "tasks" \
                    and parts[2] == "goal":
                # 1.0.65: the goalId field's write face lives in
                # the goaldepth dispatcher with its goal kin.
                return self._dispatch_goaldepth(parts)
            with _lock:
                if parts == ["goals"]:
                    if self.command == "GET":
                        return self._send(200, {"items": _list_goals()})
                    if self.command == "POST":
                        return self._send(201,
                                          _create_goal(self._body()))
                elif parts == ["goals", "ungrouped-tasks"]:
                    # GD-2 face 2; matched before the /goals/{id}
                    # arm below (goal ids are g_-prefixed, so no
                    # real goal can shadow this literal).
                    if self.command == "GET":
                        return self._send(
                            200, _ungrouped_tasks_view())
                elif len(parts) == 2 and parts[0] == "goals":
                    if self.command == "PATCH":
                        return self._send(
                            200, _patch_goal(parts[1], self._body()))
                    if self.command == "DELETE":
                        _delete_goal(parts[1])
                        return self._send(200, {"ok": True})
                elif parts == ["ideas"]:
                    if self.command == "GET":
                        return self._send(200, {
                            "items": _list_ideas(),
                            # ID-2: the active snapshot rides
                            # along so readers can present the
                            # loop's settled grouping/order
                            "snapshot":
                                _active_snapshot_view_locked(),
                        })
                    if self.command == "POST":
                        return self._send(201,
                                          _create_idea(self._body()))
                elif len(parts) == 3 and parts[0] == "ideas" \
                        and parts[2] == "signal":
                    if self.command == "POST":
                        return self._send(
                            200, _idea_signal_locked(
                                parts[1], self._body()))
                elif len(parts) == 2 and parts[0] == "ideas":
                    if self.command == "PATCH":
                        return self._send(
                            200, _patch_idea(parts[1], self._body()))
                    if self.command == "DELETE":
                        _delete_idea(parts[1])
                        return self._send(200, {"ok": True})
            return self._send(404, {"error": "路径不存在"})
        except _Err as e:
            return self._send(e.status, {"error": e.message})
        except Exception as e:  # never leak internals, but don't hang
            _print(f"unhandled error: {e!r}", file=sys.stderr, flush=True)
            return self._send(500, {"error": "服务器内部错误"})

# --- gateway shell (batch 3): boot + in-process dispatch -------------

_started = False
_start_lock = threading.Lock()


def start() -> None:
    """Idempotent boot: the bridge main() sequence minus the HTTP
    listener and the bridge-key gate (auth lives in api_server).
    Each side book keeps the bridge's own failure isolation: a
    failed starter is logged, never fatal."""
    global _started
    with _start_lock:
        if _started:
            return
        _started = True
    _load()
    sched = threading.Thread(target=_reconcile_loop, daemon=True)
    sched.start()
    try:
        _cron_startup()
    except Exception as e:
        _print(f"cron ensure not started: {e!r}", file=sys.stderr,
               flush=True)
    try:
        _ledger_start_collector()
    except Exception as e:
        _print(f"ledger collector not started: {e!r}",
               file=sys.stderr, flush=True)
    try:
        _sentinel_start()
    except Exception as e:
        _print(f"delivery sentinel not started: {e!r}",
               file=sys.stderr, flush=True)
    try:
        _automation_start()
    except Exception as e:
        _print(f"automation watcher not started: {e!r}",
               file=sys.stderr, flush=True)


def dispatch(method: str, path: str, headers, body: bytes):
    """In-process entry for the api_server handlers. `path` is the
    bridge-relative path (query string included); returns
    (status, body_bytes, headers_dict)."""
    start()
    hdrs = _Headers(headers or {})
    if body and "Content-Length" not in hdrs:
        hdrs["Content-Length"] = str(len(body))
    resp: dict = {}
    ctx = {"method": method, "path": path, "headers": hdrs,
           "body": body or b"", "resp": resp}
    Handler(ctx)._dispatch()
    return (resp.get("status", 500), resp.get("body", b""),
            resp.get("headers", {}))


if __name__ == "__main__":
    sys.exit(main())
