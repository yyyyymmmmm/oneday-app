#!/usr/bin/env python3
"""oneday-bridge: goals + ideas + monitors sidecar for OneDay
(P4/P5/P6).

Serves the frozen oneday-bridge contract:
- GET    /goals              -> {"items": [goal, ...]}   (createdAt asc)
- POST   /goals              -> 201 goal (category optional: one
                                of the GOAL_CATEGORIES enum or
                                null -> else 400; parentId optional:
                                must name an existing top-level goal,
                                sub-goals cannot nest -> else 400;
                                source optional: "manual" | "chat")
- PATCH  /goals/{id}         -> 200 goal (title/note optional;
                                G-6: milestones removed, a
                                milestones key is ignored;
                                status optional: "active" |
                                "completed", completedAt is settled
                                by the bridge on transition;
                                parentId optional, same depth rules;
                                category optional, same enum rules,
                                explicit null clears it)
- DELETE /goals/{id}         -> {"ok": true} (ideas pointing at the
                                goal get goalId=null, no dangling refs;
                                sub-goals, entries and briefings go
                                with it; monitors get goalId=null;
                                its tasks' goalId fields are
                                cleared with it, kanban tasks
                                untouched)
- GET    /goals/{id}/entries -> {"items": [entry, ...]} (createdAt asc)
- POST   /goals/{id}/entries -> 201 entry (body non-empty; source
                                "user" | "agent", default "user";
                                append-only, entries are never edited)
- DELETE /goals/{id}/entries/{eid} -> {"ok": true}
- GET    /goals/{id}/task-links -> {"items": [link, ...]}
                                (createdAt asc; 0.40.0.
                                DEPRECATED 1.0.65: a compatibility
                                projection over the taskGoals
                                field store for the pre-1.0.65
                                App; the synthesized link is
                                derived per request, no link
                                record exists any more)
- POST   /goals/{id}/task-links -> 201 link (taskId required;
                                milestoneId accepted and ignored
                                (G-6: concept removed);
                                writes the task's goalId field
                                through (compat projection, see
                                above); a duplicate write returns
                                the existing assignment, so a
                                retried delegation never doubles)
- POST   /goals/{id}/delegate -> 201 assignment + title
                                (1.0.65: one-shot delegation --
                                the bridge creates the kanban
                                card through the Dashboard
                                channel and writes the task's
                                goalId field in the same
                                operation; title required,
                                milestoneId accepted and ignored
                                (G-6), idempotencyKey
                                optional and retry-safe)
- PUT    /tasks/{taskId}/goal -> 200 assignment {taskId,
                                goalId, milestoneId, assignedAt}
                                (1.0.65: the goalId field's
                                standalone write face; goalId
                                null clears the assignment;
                                milestoneId accepted and ignored
                                (G-6), always reads back null)
- GET    /goals/{id}/briefings -> {"items": [briefing, ...]}
                                (createdAt desc, newest first)
- POST   /goals/briefings/generate -> 202 {"ok": true,
                                "started": bool} (G-7: internal ops
                                only -- requires the X-Cron-Callback-
                                Key header on top of the bridge key,
                                else 404; the App has no caller.
                                409 while a round is running)
- GET    /goals/briefings    -> {"lastRunAt", "nextRunAt", "history"}
                                (weekly briefing ledger)
- POST   /goals/{id}/briefings/{bid}/opened -> 200 briefing
                                (GD-3: the App opened this letter;
                                stamps lastOpenedAt -- ledger
                                visibility only, never a read-nag)
- GET    /goals/{id}/tasks   -> {"items": [assigned task live
                                row]} (GD-2: the taskGoals field
                                projected with the feed poll's
                                board snapshot and event ring:
                                goalId / title / raw status /
                                bucket / updatedAt)
- GET    /goals/ungrouped-tasks -> {"items": [...], "polledAt"}
                                (GD-2: board tasks of the
                                user-initiated classes -- idea-
                                adopted and session-dispatched --
                                that carry no goal link; system /
                                scheduled / probe cards never enter
                                this face, parity spec ch.3
                                harmonised reading)
- GET    /ideas              -> {"items": [idea, ...], "snapshot":
                                {snapshotId, createdAt, sections} | null}
                                (ID-2: pool order = the active
                                snapshot's positions; merged cards are
                                mapped onto their canonical and leave
                                the list)
- POST   /ideas              -> 201 idea (goalId must name an existing
                                goal when non-null -> else 400;
                                source="generated" requires a non-empty
                                evidence -> else 400)
- PATCH  /ideas/{id}         -> 200 idea (only status/taskId may change;
                                status machine: pending -> adopted |
                                dismissed | expired, adopted is final
                                except taskId fill-in; setting taskId
                                implies adopted; dismissals may carry
                                dismissReason="tooGeneric", which the
                                generator counts into its avoidance;
                                a merged id resolves to its canonical)
- POST   /ideas/{id}/signal  -> {"ok": true} (ID-2 fast-channel
                                feedback: type = open | discuss |
                                tooGeneric)
- DELETE /ideas/{id}         -> {"ok": true}
- POST   /ideas/generate     -> 202 {"ok": true, "started": bool}
                                (ops trigger for one generation round;
                                409 while a round is already running)
- GET    /ideas/generation   -> {"lastRunAt", "nextRunAt", "history"}
- GET    /meta/brief         -> {"brief", "interest",
                                "briefUpdatedAt",
                                "interestUpdatedAt", "expanding",
                                "expandError"} (two-layer brief,
                                0.38.0: "brief" is the execution
                                layer every pipeline consumes,
                                "interest" the user's own words)
- PUT    /meta/brief         -> same document + {"expandStarted"}
                                (body {"interest": str} and/or
                                {"brief": str}; a true interest
                                change starts an expansion run, a
                                true brief change a research round)
- GET    /feed               -> {"items": [post, ...]}   (createdAt
                                desc; ?days=N window, default 30;
                                expired posts are not listed)
- GET    /feed/{id}          -> post
- POST   /feed/{id}/read     -> post (readAt settled by the bridge)
- POST   /feed/{id}/like     -> post ({"liked": bool}; likedAt is
                                bridge-owned, a fresh like folds
                                into the taste notes)
- POST   /feed/{id}/signal   -> {"ok": true} ({"type": "discuss",
                                "note": optional user-stated
                                preference sentence}; folds into
                                the taste notes, chat text never
                                crosses over)
- DELETE /feed/{id}          -> {"ok": true} (a deletion folds
                                into the taste notes as a weak
                                dislike signal)
- POST   /feed/generate      -> 202 {"ok": true, "started": bool}
                                (ops trigger for one research
                                round; 409 while a round is
                                already running)
- GET    /feed/generation    -> {"assembly": {...}, "research":
                                {lastRunAt, nextRunAt, history},
                                "unread": n}  (feed ledger; single
                                "research" key -- the pre-0.38.0
                                "morning" alias was removed in
                                complexity item 1)
- GET    /monitors           -> {"items": [monitor, ...]}
- POST   /monitors           -> 201 monitor (baseline fetch seeds the
                                snapshot; never reports a change)
- GET    /monitors/{id}/changes -> {"items": [change, ...]}
                                (detectedAt desc)
- POST   /monitors/{id}/changes/{cid}/read -> {"ok": true}
- POST   /monitors/{id}/read -> {"ok": true} (all changes read)
- POST   /monitors/{id}/check -> 200 monitor (fetch -> fingerprint ->
                                diff -> changed/unchanged/failed)
- POST   /monitors/{id}/pause | /resume -> 200 monitor
- DELETE /monitors/{id}      -> {"ok": true} (changes go with it)
- POST   /deliveries         -> 201|200 {id, marker, meta}
                                (delivery registry: body
                                {path} only; the bridge reads
                                the real file back, see
                                delivery-registry-spec)
- GET    /deliveries/{id}    -> meta + live status
- GET    /deliveries/{id}/thumb|cover -> JPEG snapshot
- GET    /deliveries/by-message?session_id=<id>[&message_id=<n>]
                                -> attachment index written by the
                                delivery sentinel (assistant
                                messages auto-registered from the
                                paths they mention; see the
                                sentinel section below)
- MOVED  /files/spreadsheet (§125) and /media/rendition (§138):
                                both endpoints moved out to the
                                standalone fileproc module (port
                                8652) on 2026-11-14 (API-direct
                                package B4/B5); this bridge answers
                                404 for them. Contracts unchanged.

monitor = {id, name, target, scheduleText, cronJobId (the Hermes
        cron job id since 1.0.59 -- scheduling lives in the Hermes
        cron engine, see the cron segment; null only for manual
        monitors or while registration is pending), enabled,
        lastCheckedAt, lastResult, lastError, unreadChanges,
        latestChangeSummary, latestChangeAt, createdAt, updatedAt,
        goalId (optional, P2: the goal this monitor watches for;
        null when unattached; deleting the goal unlinks it)}
change  = {id, monitorId, detectedAt, summary, before, after, read}
On "changed" an overview-shaped notification record is appended to
monitor-notifications.jsonl next to the data file.

goal = {id, title, note, (G-6: milestones removed),
        createdAt, updatedAt,     (epoch seconds, float)
        status ("active" | "completed"; pre-P2 records read as
        "active"), completedAt (epoch seconds or null),
        parentId (goal id or null; sub-goals are exactly one
        level deep), source ("manual" | "chat"; pre-P2 records
        read as "manual"), category ("health" | "relationships"
        | "finance" | "career" | "interest" | "efficiency" |
        "other" or null; 0.40.0 -- the user's own pick at
        creation time, NEVER inferred; pre-0.40.0 records and
        records without the field read as null = uncategorised),
        latestEntry (newest entry object or null; read-through
        embed for list rows, not stored)}
taskGoal = {goalId, milestoneId (always null since G-6),
        assignedAt, delegateKey (only on bridge-delegated
        tasks)} -- a kanban task's goalId FIELD, keyed by
        taskId in _db["taskGoals"] (1.0.65 single track).
        The goal<->kanban association's only truth: single-
        valued per task, written by POST /goals/{id}/delegate,
        PUT /tasks/{taskId}/goal, the automation facade's
        kanban_create_task(goalId) and the deprecated
        task-links compat write; every read face (goal tasks,
        ungrouped tasks, goal activity, briefings) derives
        from it. Kanban cards cannot hold the field
        themselves (fixed-column tasks schema, no goalId, no
        generic metadata slot -- verified 0.39.0, re-verified
        1.0.65), so it lives with the goals domain's owner.
        Deleting a goal clears its tasks' fields (the tasks
        themselves are untouched). The pre-1.0.65
        goalTaskLinks collection was folded into this store
        once at load (meta.taskGoalMigration keeps the count
        ledger) and is never written again.
        The echoes' exactly-once state is NOT part of the
        field: _db["goalEchoState"] (taskId -> {completed-
        EntryAt/completedGoalId, stoppedEntryAt/stopped-
        Bucket/stoppedGoalId}) is the feed poll's private
        ledger. When the poll sees an assigned task in a
        done state, the bridge writes ONE fact-only progress
        entry to the goal (source "agent", task title + task
        id only), exactly once per task + goal. GD-1b
        (2026-11-14): the same poll also watches for an
        assigned task entering a blocked/failed state and
        writes ONE fact-only entry per stopped episode; the
        episode clears when the task leaves the stopped
        states, so a later re-block earns a fresh entry.
entry = {id, goalId, body, source ("user" | "agent"), createdAt}
        -- the goal's append-only progress log (P2)
briefing = {id, goalId, period (ISO week "2026-W46", Asia/Shanghai),
        title, body, createdAt, note, lastOpenedAt}
        -- one letter per goal per week, written by the briefing
        pipeline below, never edited. note (GD-3) is the letter's
        material composition counted BY CODE from the same three
        material classes the letter was written from (last-7-days
        progress entries / associated tasks / monitor changes),
        zero-count classes omitted, null when all three are zero;
        lastOpenedAt (GD-3) is stamped when the App opens the
        letter, null until then -- ledger visibility only.
idea = {id, title, detail, goalId, createdAt,
        source ("generated" | "manual"), evidence, evidenceRef,
        anchorId ("<kind>:<object id>" resolved from evidenceRef
        at generation time; null on manual/pre-v2 cards),
        dismissReason (null | "tooGeneric"), statusAt,
        status ("pending" | "adopted" | "dismissed" | "expired"),
        taskId, expiresAt (epoch seconds or null; generated cards
        expire 14 days after creation, manual cards never)}

Goal weekly briefings (P2): a bridge-internal weekly round
(Mondays 08:00 Asia/Shanghai, fired by a Hermes cron job since
1.0.59 -- see the cron segment) writes one
letter-style briefing per ACTIVE top-level goal that has material
(sub-goals are part of their parent's archive, not letter targets)
-- its
progress entries of the last 7 days, the kanban state of tasks
adopted from its ideas, and the last 7 days of changes from
monitors attached to it (via monitor.goalId). Material is
assembled read-only (kanban state is read through the same
Dashboard cookie channel as session titles); goals without
material are skipped and counted in the ledger
(meta.briefGen.history), never padded into a letter. Each goal's
letter is one Hermes /v1/runs call (deepseek-flash, Idempotency-Key
per week+goal); output is strict-parsed as {"title", "body"} and
only then stored. A (goalId, period) pair gets at most one
briefing, so re-running a round is idempotent. The progress
percentage is never generated: milestone counts are facts the App
derives from the stored milestone list itself.

Idea generation (P1, v2 in 0.39.0 per spec
three-pages-mechanism-v2 ch.2): a bridge-internal daily round
(07:30 Asia/Shanghai, fired by a Hermes cron job since 1.0.59)
assembles material from SEVEN read-only sources (the shared
brief; S = last-14-days sessions, two-stage via a flash digest
round that preserves fact anchors; G = goals with their last-14
-days progress entries and latest briefing; M = monitor changes
of the last 7 days; K = kanban board substance via the Dashboard
channel; R = long-term memory excerpts via the write-gate
bridge's GET /memories), asks Hermes POST /v1/runs (model
deepseek-flash, Idempotency-Key per round) for 0-3 structured
cards, then folds them through three gates: the hard evidence
gate (generated + empty evidence never lands, shared with
POST /ideas), the anchor gate (evidenceRef must resolve in the
round's anchor registry and the evidence must carry a date /
number / proper noun), and the action gate (a self-check round
re-judges the cards against two benchmark examples; the user's
『太泛』 dismissals flow into the avoidance material). Dedup is
anchor-level (a stored card's resolved anchorId blocks the same
object across rounds; titles remain the second layer) and drops
are counted by reason in the run record. Failures are recorded
in meta.ideasGen.history and never produce cards. Generation
needs HERMES_API_KEY (the Hermes api_server_key) in the bridge
env; the Dashboard sources also need HERMES_DASH_USER /
HERMES_DASH_PASSWORD, the memory source WRITE_GATE_BRIDGE_KEY.
When the key is unset the round is recorded as skipped, CRUD is
unaffected.

Feed (P3): one producer lands in one store (feedPosts), plus an
event ledger that never posts. The day's real events -- new
ideas, new goal briefings, monitor changes, kanban task status
changes (polled through the Dashboard channel, throttled,
diffed against a stored snapshot; the first snapshot is a
silent baseline) and pending write-approvals (count polled
through the public single-key gateway route, presenting the
bridge's Hermes credential; only increases become events),
plus the monitor-down and milestone-all transition events --
are still collected on the reconcile tick into meta.feed's
ledger, which feeds the generation counters and the kanban
snapshot's other consumers. Feed purity (user ruling,
2026-11-12; the FD-1 digest/event design is retired): events
are NEVER turned into posts -- no digest (「今日小结」), no
standalone A-grade event posts; the flow carries interest
content only, and approvals/events surface through their own
channels (notifications, chat approval cards), which never ran
through this store. Digest/event posts already in the store
are archived in place by the assembler (an archivedAt stamp;
excluded from GET /feed; the record stays for audit, never
deleted by the sweep). Segment two (0.38.0, replacing the P3
morning round) is the brief-driven web-research pipeline: a
five-step chain (plan -> Tavily search -> extract -> compose ->
verify, deepseek-flash for the two model steps) runs daily at
08:30 Asia/Shanghai and whenever the brief execution layer
truly changes; each direction in the brief yields 0-1 posts
(kind "research", whole round capped at 3). Verification is
the P3 discipline widened: every link must come from the
round's candidate set (one foreign link drops the post),
images must come from the extract results and pass a HEAD
check, refs validate against real objects when present.
Pre-0.38.0 "morning" posts stay readable. Ledgers live under
meta.feed / meta.feedGen (GET /feed/generation).
post = {id, kind ("research" | "morning"; "digest" | "event"
        are legacy-only since feed purity 1.0.32), title,
        body (Markdown), refs: [{type, id}],
        links: [{title, url}], why,
        images: [{url, sourceUrl}] (research posts),
        emoji (0.47.0: research = model-picked; older posts
        carry none),
        archivedAt (feed purity, 1.0.32: legacy digest/event
        posts carry it and never list; the record itself stays
        readable by id),
        sourceCard: {kind, name, description, url, imageUrl,
        facts: [{label, value}]} | null (research posts),
        direction (research posts),
        createdAt, expiresAt (30 days), readAt (epoch or null)}

- POST   /traces             -> 201 trace (P0 留痕底座, AI internal
                                powers 2026-11-13: append-only action
                                log; every record carries the five
                                echo elements -- action name, pointable
                                target, time, result summary, and on
                                failure the verbatim error; a "failed"
                                record without error text, or an "ok"
                                record without a result, is refused
                                400; failures are first-class records,
                                never silently dropped)
- GET    /traces             -> {"items": [trace, ...]} (newest
                                first; filters ?action= ?status=
                                ?targetId= ?since=<epoch> ?limit=N,
                                default 100, cap 500)
- GET    /traces/{id}        -> trace
- POST   /mcp                -> MCP streamable-http facade for the
                                goals surface (P3, 2026-11-13):
                                initialize / ping / tools/list /
                                tools/call with goals_list,
                                goals_create (source="chat"),
                                goals_add_entry (entry source=
                                "agent"), goals_update. Every call,
                                success or failure, writes one P0
                                trace before answering. The facade is
                                built and self-verified here, and is
                                registered into Hermes as
                                oneday-goals (`hermes mcp list` +
                                `hermes mcp test` verified,
                                2026-11-27).
- POST   /automation-mcp     -> MCP streamable-http facade for the
                                automation surface (P4+P5,
                                2026-11-13): cron_create / cron_list
                                / cron_delete (Hermes cron engine
                                via its Dashboard REST API; every
                                job owner-bound, runs echoed),
                                kanban_create_task / kanban_get_task
                                (oneday board via the kanban plugin
                                API; owner-bound, completions
                                echoed), reach_send (proactive
                                message on the existing notification
                                ledger; quiet hours 09:00-21:30
                                queue + flush). Every call writes
                                one P0 trace before answering; a
                                watcher folds runs / completions /
                                flushes into traces. Built and
                                verified here, and registered into
                                Hermes as oneday-automation
                                (verified 2026-11-27).
- POST   /library-mcp       -> MCP streamable-http facade for the
                                file library surface (1.0.73):
                                initialize / ping / tools/list /
                                tools/call with the single read-only
                                tool library_list -- a direct call
                                of the same _file_library_view the
                                App's file page reads (one admitted
                                set, one source of truth; optional
                                since filters on mtime and reports
                                sinceCount). Every call writes one
                                P0 trace before answering.
                                Registered into Hermes as
                                oneday-library, Authorization via
                                the global API_SERVER_KEY like the
                                other facades (verified 2026-11-27).

Storage: single JSON file (DATA_PATH), atomic tmp+replace writes,
file mode 0600. All mutations serialized under one lock.
Load-failure stop-bleed (audit F04/R1, 2026-11-10): if the data
file exists but fails to parse, the original is quarantined to
data.json.corrupt-<timestamp> (never deleted), the process starts
with an empty in-memory db in READ-ONLY DEGRADED mode (every
write is refused with 503, the empty db is NEVER written back over
the data file), and /health exposes degraded=true + the reason.

Auth: this companion-era copy used a single Bearer token
scoped to the bridge (ONEDAY_BRIDGE_KEY env, own key since
the 2026-11-10 F03 rotation), fail-closed when unset. That
key is retired: since the face moved into the gateway
(package 1.19.0) the live face authenticates with the
gateway API_SERVER_KEY, and since 2.19.0 the bridge surfaces
accept the Hermes session token directly -- the bridge key
survives only as a server-internal key, never a client
credential. /health is the only
unauthenticated route and returns no data. Exception since
1.0.59 (B-01): the /internal/cron/* callback routes take a
dedicated X-Cron-Callback-Key header (ONEDAY_CRON_CALLBACK_KEY)
instead of the Bearer key -- that key opens nothing else.
Access log: method/path/status only.
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
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, parse_qsl, urlencode, urlparse

import ledger as _ledger_mod

API_KEY = os.environ.get("ONEDAY_BRIDGE_KEY", "")
DATA_PATH = Path(os.environ.get("DATA_PATH", "/opt/oneday-data/data.json"))
#: The device sync copy lives in the device bridge's data dir
#: (same container, shared volume). This bridge only ever READS
#: it, through device_sync's own query path (ID-1); the env name
#: is deliberately distinct from the device bridge's DATA_DIR.
DEVICE_DATA_DIR = Path(os.environ.get(
    "DEVICE_DATA_DIR", "/opt/device-data"))
PORT = int(os.environ.get("ONEDAY_PORT", "8646"))
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
                f"数据文件解析失败（{e}）；原件已隔离至 {where}；"
                "桥以空库只读降级运行，禁止回写正式数据文件")
            print(f"DATA DEGRADED: {_degraded_reason}",
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
#: category_label: 「年会」「服务器运维」「Ai 培训」...). The
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




class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # keep stderr clean; we log our own
        pass

    def _send(self, status: int, obj: dict) -> None:
        raw = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
        print(f"{self.command} {urlparse(self.path).path} -> {status}",
              flush=True)

    def _authed(self) -> bool:
        hdr = self.headers.get("Authorization", "")
        if not hdr.startswith("Bearer "):
            return False
        return hmac.compare_digest(hdr[7:], API_KEY)

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
            print(f"cron callback error: {e!r}", file=sys.stderr,
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
            print(f"unhandled error: {e!r}", file=sys.stderr, flush=True)
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
            print(f"unhandled error: {e!r}", file=sys.stderr,
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
    #         print(f"unhandled error: {e!r}", file=sys.stderr,
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
            print(f"unhandled error: {e!r}", file=sys.stderr, flush=True)
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
            print(f"unhandled error: {e!r}", file=sys.stderr, flush=True)
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
            print(f"unhandled error: {e!r}", file=sys.stderr,
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
                item, seq = _ledger_mod.apply_app_report(
                    store, self._body(), tz=_sched_tz())
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
            print(f"unhandled error: {e!r}", file=sys.stderr,
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
                if which not in ("thumb", "cover"):
                    return self._send(404, {"error": "路径不存在"})
                if self.command != "GET":
                    return self._send(405, {"error": "方法不允许"})
                if _delivery_status(rec) == "gone":
                    return self._send(410, {"error": "文件已不存在"})
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
            print(f"unhandled error: {e!r}", file=sys.stderr,
                  flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    def _send_bytes(self, status: int, raw: bytes,
                    content_type: str,
                    etag: str | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(raw)))
        if etag:
            self.send_header("ETag", etag)
        self.send_header("Cache-Control",
                         "private, max-age=31536000, immutable")
        self.end_headers()
        self.wfile.write(raw)
        print(f"{self.command} {urlparse(self.path).path} -> {status}",
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
            print(f"unhandled error: {e!r}", file=sys.stderr,
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
                    health["ledger"] = {"error": repr(e)[:120]}
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
            print(f"unhandled error: {e!r}", file=sys.stderr, flush=True)
            return self._send(500, {"error": "服务器内部错误"})

    do_GET = _dispatch
    do_POST = _dispatch
    do_PATCH = _dispatch
    do_DELETE = _dispatch
    do_PUT = _dispatch


def main() -> int:
    if not API_KEY:
        print("ONEDAY_BRIDGE_KEY is unset; refusing to start (fail-closed)",
              file=sys.stderr)
        return 1
    _load()
    sched = threading.Thread(target=_reconcile_loop, daemon=True)
    sched.start()
    try:
        _cron_startup()
    except Exception as e:
        # Cron registration is reconcilable state: the reconcile
        # loop's ensure pass retries; a failed startup pass must
        # never take the bridge down.
        print(f"cron ensure not started: {e!r}", file=sys.stderr,
              flush=True)
    try:
        _ledger_start_collector()
    except Exception as e:
        # The ledger is a side book: its failure to start must
        # never take the bridge down. /health shows the gap.
        print(f"ledger collector not started: {e!r}",
              file=sys.stderr, flush=True)
    try:
        _sentinel_start()
    except Exception as e:
        # Same side-book rule as the ledger collector: the
        # sentinel must never take the bridge down.
        print(f"delivery sentinel not started: {e!r}",
              file=sys.stderr, flush=True)
    try:
        _automation_start()
    except Exception as e:
        # Same side-book rule: the automation watcher (cron run
        # echoes, kanban completion echoes, proactive queue
        # flush) must never take the bridge down; its absence is
        # visible in the module log instead.
        print(f"automation watcher not started: {e!r}",
              file=sys.stderr, flush=True)
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"oneday-bridge listening on {PORT}, data={DATA_PATH}",
          flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
