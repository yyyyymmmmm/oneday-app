#!/usr/bin/env python3
"""device-bridge: tool-call facade between Hermes and the OneDay iOS app
(batch-1 skeleton, pre-built 2026-11-10; NOT yet registered in Hermes
config, nginx routes exist only as a draft).

Model (design: oneday-design-review/device-connectors-design-20261110.md
as amended by device-sync-design-20261110.md, user decisions
2026-11-10 21:52 + 21:58):
- Record-type datasets (contacts, calendar, reminders, photo index,
  per-day step aggregates) are SYNCED as field-minimised copies into
  device_sync's SQLite store on this service; the query tools answer
  from the copy and always carry its sync time plus a plain-language
  freshness sentence. Permission revoked => the copy stops serving
  entirely (2026-11-10 21:58 ruling).
- Realtime and action tools keep the original tool-call model:
  authorization and data stay on the phone, the app reads/writes
  live. Same-name query tools fall back to a live read when the copy
  has never been synced or was deleted, and say so in the result.
- On disk: the audit log (metadata, no payload content), the
  write-key store (idempotency key -> object id, no content), and
  the sync store (sync.db, the one sanctioned copy).

Surfaces (all but /health need this bridge's own Bearer,
DEVICE_BRIDGE_KEY env; fail-closed when unset):
- GET  /health                 -> {"ok": true, ...} (no auth, no data)
- POST /mcp                    -> MCP streamable-http facade (JSON-RPC):
                                  initialize / ping / tools/list /
                                  tools/call
- POST /device/session         -> app registers a session {deviceId,
                                  appVersion, permissions, tools}
- POST /device/heartbeat       -> {sessionId} keep-alive
- GET  /device/poll?sessionId= -> long-poll (<=25s) for the next call
- POST /device/respond         -> {sessionId, callId, status, result?,
                                  error?} completes a call
- POST /device/resume          -> {resumeToken} re-dispatches a parked
                                  call once (§244 permission flow)
- POST /device/park-state      -> {resumeToken} read-only park truth
                                  for card reconciliation (§261: exists,
                                  expiry, ask outcome; never consumes)
- POST /device/disconnect      -> {sessionId} drops the session
- POST /device/sync/batch      -> stage one sync batch (<=500 records)
- POST /device/sync/complete   -> confirm + atomically swap a batch in
- POST /device/sync/manifest   -> contacts id/fingerprint diff
- POST /device/sync/state      -> app reports permission/range changes
- POST /device/sync/delete     -> delete synced copies (one or all)
- GET  /device/sync/status     -> per-dataset sync state, no content

Call flow: tools/call -> session offline => structured error
device_offline (never stale data); source permission not granted =>
the §244 permission gate (see _permission_gate): never-asked
permissions are asked in the chat itself via a permission_ask
pseudo-call when the app supports it, decided/switch-blocked calls
are parked under a resumeToken and the facade answers
permission_required; otherwise the call is
queued, the app picks it up via poll, executes live, responds; the
facade returns the result. Whole-call timeout DEVICE_CALL_TIMEOUT_SEC
(default 30s) => device_timeout; the presence tools (camera_capture,
vision_document_scan, auth_biometric) wait on the user in person
and get DEVICE_PRESENCE_TIMEOUT_SEC (default 150s) instead
(DESIGN §114.5.4). The §115 batch adds six more presence tools to
that same tier (compose_sms, compose_email, share_sheet,
shortcut_run, file_preview, file_print — DESIGN §115.5.4);
shortcut_run's own app-side callback wait caps at 100s, inside
the 150s bridge tier.

Write tools carry an idempotencyKey (one user confirmation = one key).
A repeated key returns the stored outcome without re-forwarding to the
phone; the app keeps its own 24h key set as the second layer.

Audit: one JSONL line per call {ts, callId, tool, source, status,
durationMs, errorCode, objectId?} -- arguments and result content are
never written.

Gateway home (bridge-retirement batch 5, hermes-deploy 2.0.0):
this module now lives in the gateway process as device_gateway.
The engine below is the bridge's, verbatim; only the transport
changed -- the standalone ThreadingHTTPServer is replaced by the
dispatch adapter at the bottom of this file, driven from
api_server's aiohttp face (/api/device-bridge/* shape-preserving
mounts and /api/device-mcp) with the engine executing on worker
threads (asyncio.to_thread), so the session table, the
pending-call records and the section-244 park flow keep their
exact threading semantics in-process. Two instance bindings
changed with the move: the data dir defaults to /opt/data/device
(DEVICE_DATA_DIR override), and the accepted Bearer is the
deployment's single key (API_SERVER_KEY) -- the bridge's own
DEVICE_BRIDGE_KEY is retired with the bridge (single-key
endgame).
"""

from __future__ import annotations

import hmac
import io
import json
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

try:
    from gateway.platforms import device_sync
except ImportError:  # direct module load (selftest / tooling)
    import device_sync

API_KEY = os.environ.get("API_SERVER_KEY", "")  # single key (batch 5: the bridge-scoped DEVICE_BRIDGE_KEY is retired)
DATA_DIR = Path(os.environ.get("DEVICE_DATA_DIR", "/opt/data/device"))
PORT = int(os.environ.get("DEVICE_PORT", "8647"))
MAX_BODY = 1_048_576
CALL_TIMEOUT = float(os.environ.get("DEVICE_CALL_TIMEOUT_SEC", "30"))
# Presence tools (DESIGN §114.5.4) wait on a human standing at the
# phone — framing a photo, scanning several pages, answering a
# Face ID prompt: the default 30s would cut them off mid-gesture.
# Their per-tool timeout is 150s: the §114.5 floor of 120s plus
# headroom for multi-page scans and a biometric retry. Nothing
# else in this bridge caps a single call below that: the phone
# long-polls in <=25s cycles and re-polls, and a pending call
# record does not depend on poll cadence. The app closes its own
# UI and answers with an error if its wait is cancelled, so a
# longer bridge timeout cannot hang a call forever.
PRESENCE_TIMEOUT = float(os.environ.get(
    "DEVICE_PRESENCE_TIMEOUT_SEC", "150"))
# §115.5.4: the batch-four presence tools wait on the user working
# a system surface (composing, sharing, reading a preview) or on
# an x-callback receipt (shortcut_run, whose app-side wait itself
# caps at 100s), so they share this tier. call_start is NOT here:
# it only opens the system dial prompt and answers "initiated"
# at once — it never waits for the call to happen. The batch-four
# live reads (location_*, media_*, device_info) answer on the
# spot and stay on the default timeout.
TOOL_TIMEOUTS = {"camera_capture": PRESENCE_TIMEOUT,
                 "vision_document_scan": PRESENCE_TIMEOUT,
                 "auth_biometric": PRESENCE_TIMEOUT,
                 "compose_sms": PRESENCE_TIMEOUT,
                 "compose_email": PRESENCE_TIMEOUT,
                 "share_sheet": PRESENCE_TIMEOUT,
                 "shortcut_run": PRESENCE_TIMEOUT,
                 "file_preview": PRESENCE_TIMEOUT,
                 "file_print": PRESENCE_TIMEOUT}
POLL_MAX_WAIT = 25.0
SESSION_TTL = 45.0  # seconds since last heartbeat/poll => offline
# §244 permission flow (in-chat authorization, spec
# permission-system-redesign-20261113): when a tool call hits a
# never-asked permission, the bridge asks in the chat itself through
# a permission_ask pseudo-call and waits this long for the user's
# answer before parking the call; parked calls live 24h (the card in
# the chat mirrors the same horizon), single-use resume tokens.
ASK_TIMEOUT = float(os.environ.get("DEVICE_ASK_TIMEOUT_SEC", "120"))
PARK_TTL = 24 * 3600.0
PERMISSION_ASK_TOOL = "permission_ask"
PERMISSION_ASK_CAPABILITY = "permission_ask_v1"

try:
    from gateway.platforms.device_gateway_catalog import (
        NEVER_REPLAY_TOOLS,
        NO_PERMISSION_SOURCES,
        TOOL_BY_NAME,
        TOOLS,
        WRITE_TOOLS,
    )
except ImportError:
    from device_gateway_catalog import (
        NEVER_REPLAY_TOOLS,
        NO_PERMISSION_SOURCES,
        TOOL_BY_NAME,
        TOOLS,
        WRITE_TOOLS,
    )

# ---------------------------------------------------------------- state
device_sync.init(DATA_DIR)
_cond = threading.Condition()
_session: dict | None = None          # current device session (single)
_pending: dict[str, dict] = {}        # callId -> call record
_write_keys_path = DATA_DIR / "write-keys.json"
_audit_path = DATA_DIR / "audit.jsonl"


def _now() -> float:
    return time.time()


def _session_online_locked() -> bool:
    return (_session is not None
            and _now() - _session["lastSeen"] <= SESSION_TTL)


def _audit(entry: dict) -> None:
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        with open(_audit_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as e:
        print(f"[device-bridge] audit write failed: {e}", flush=True)


def _load_write_keys() -> dict:
    try:
        return json.loads(_write_keys_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save_write_key(key: str, tool: str, object_id) -> None:
    keys = _load_write_keys()
    keys[key] = {"tool": tool, "objectId": object_id, "ts": _now()}
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        tmp = _write_keys_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(keys, ensure_ascii=False),
                       encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(_write_keys_path)
    except OSError as e:
        print(f"[device-bridge] write-key save failed: {e}", flush=True)


# ---------------------------------------------------------------- engine
class CallError(Exception):
    def __init__(self, code: str, message: str, fields: dict | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.call_id = None  # set when a call record was created
        # §244 P-1: structured payload for permission-class failures
        # ({source, state, blockerLayer, nextAction, resumeToken?}),
        # merged verbatim into the MCP error object. The message is
        # Chinese human copy produced here -- one source of truth, the
        # app and the model never re-word it.
        self.fields = fields or {}


# ------------------------------------------------- §244 permission flow
# Parked calls: a tool call blocked on authorization lives here under
# a single-use resume token until the user authorizes (in-chat ask,
# settings round-trip, or agent-call switch) and the app calls
# POST /device/resume. Arguments are kept because re-dispatch needs
# them (write calls keep their original idempotencyKey, so a resumed
# write is still one user confirmation = one execution). The file
# sits in the device data dir under the same 0600 discipline as the
# write-key ledger; entries expire after PARK_TTL and are pruned on
# every load. Audit lines never include arguments -- parks are
# operational state, not audit.
_parks_path = DATA_DIR / "permission-parks.json"
_parks_lock = threading.Lock()

_SOURCE_LABELS = {
    "calendar": "日历", "contacts": "通讯录", "reminders": "提醒事项",
    "photos": "照片", "motion": "步数", "alarm": "闹钟",
    "notifications": "通知", "camera": "相机", "location": "定位",
    "media": "媒体库", "health": "健康", "home": "家庭",
    "clipboard": "剪贴板", "files": "文件", "opener": "打开目标",
    "vision": "视觉识别", "translate": "翻译", "ondevice": "端上智能",
    "biometric": "本人确认", "compose": "撰写", "shortcuts": "快捷指令",
    "deviceinfo": "设备信息",
}
_STATE_LABELS = {
    "notDetermined": "还没授权过", "denied": "已被拒绝",
    "restricted": "被系统限制", "writeOnly": "只有写入权限",
    "granted": "已授权",
}


def _source_label(source: str) -> str:
    return _SOURCE_LABELS.get(source, source)


def _load_parks() -> dict:
    try:
        parks = json.loads(_parks_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    now = _now()
    return {t: p for t, p in parks.items()
            if isinstance(p, dict) and p.get("expiresAt", 0) > now}


def _save_parks(parks: dict) -> None:
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        tmp = _parks_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(parks, ensure_ascii=False),
                       encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(_parks_path)
    except OSError as e:
        print(f"[device-bridge] park save failed: {e}", flush=True)


def _park_call(tool: str, arguments: dict, source: str,
               layer: str, kind: str = "live") -> str:
    token = "park-" + secrets.token_hex(8)
    with _parks_lock:
        parks = _load_parks()
        parks[token] = {"tool": tool, "arguments": arguments,
                        "source": source, "blockerLayer": layer,
                        "kind": kind, "createdAt": _now(),
                        "expiresAt": _now() + PARK_TTL,
                        # §261: how the in-chat ask round ended
                        # (unanswered / deferred / undeliverable);
                        # None until an ask round concludes.
                        "askOutcome": None}
        _save_parks(parks)
    return token


def _mark_park_ask_outcome(token: str, outcome: str) -> None:
    """Record how the ask round for a park ended (§261: the
    bridge states it explicitly instead of folding timeout
    and user-deferred into the same silent 'parked')."""
    with _parks_lock:
        parks = _load_parks()
        park = parks.get(token)
        if park is not None:
            park["askOutcome"] = outcome
            _save_parks(parks)


def _peek_park(token: str) -> dict | None:
    with _parks_lock:
        return _load_parks().get(token)


def _drop_park(token: str) -> None:
    with _parks_lock:
        parks = _load_parks()
        if token in parks:
            del parks[token]
            _save_parks(parks)


def _consume_park(token: str) -> dict | None:
    with _parks_lock:
        parks = _load_parks()
        park = parks.pop(token, None)
        if park is not None:
            _save_parks(parks)
        return park


def _permission_fields(source: str, state: str, layer: str,
                       next_action: str, token: str | None = None,
                       asked: bool = False) -> dict:
    fields = {"source": source, "state": state,
              "blockerLayer": layer, "nextAction": next_action}
    if token:
        fields["resumeToken"] = token
        park = _peek_park(token)
        if park is not None:
            # §261: the park's own stamps ride along so any
            # card built from these fields starts its 24h
            # clock at park time, same origin as this side.
            fields["parkedAt"] = park.get("createdAt")
            fields["expiresAt"] = park.get("expiresAt")
            # Surface the ask outcome explicitly when the
            # park recorded one (e.g. unanswered after a
            # timeout) instead of folding it into silence.
            if park.get("askOutcome"):
                fields["askOutcome"] = park["askOutcome"]
    if asked:
        fields["askedAndDenied"] = True
    return fields


def _ask_permission(source: str, tool_name: str, token: str) -> str:
    """Deliver a permission_ask pseudo-call over the poll channel and
    wait for the user's in-chat answer. Returns granted / denied /
    parked (the user deferred, or the ask could not be presented).
    The pseudo-call carries the pre-created resume token, so the card
    the app shows can resume the parked call whatever happens next."""
    call_id = "call-" + secrets.token_hex(6)
    # §261: the card's 24h clock starts at park time on this
    # side; carry both stamps so the app card adopts the same
    # origin instead of re-starting its own clock on receipt.
    park = _peek_park(token) or {}
    rec = {"callId": call_id, "tool": PERMISSION_ASK_TOOL,
           "kind": "permission_ask",
           "arguments": {"source": source, "tool": tool_name,
                         "resumeToken": token,
                         "parkedAt": park.get("createdAt"),
                         "expiresAt": park.get("expiresAt")},
           "createdAt": _now(), "delivered": False,
           "event": threading.Event(), "response": None,
           "sessionId": _session["sessionId"]}
    with _cond:
        _pending[call_id] = rec
        _cond.notify_all()
    if not rec["event"].wait(ASK_TIMEOUT):
        with _cond:
            _pending.pop(call_id, None)
        # §261: a timeout is not the user deferring -- say so
        # on the park so the app card can align explicitly.
        _mark_park_ask_outcome(token, "unanswered")
        return "parked"
    with _cond:
        _pending.pop(call_id, None)
    resp = rec["response"] or {}
    if resp.get("status") == "error":
        # Session replaced / device went away mid-ask: the park and
        # the card both survive; the user can still resume later.
        _mark_park_ask_outcome(token, "undeliverable")
        return "parked"
    decision = (resp.get("result") or {}).get("decision")
    if decision == "parked":
        _mark_park_ask_outcome(token, "deferred")
    return decision if decision in ("granted", "denied", "parked") \
        else "parked"


def _permission_gate(name: str, tool: dict, arguments: dict,
                     resume: bool = False) -> None:
    """§244 gate, run before a live call is queued. Raises CallError
    for every blocked layer, in the fixed order of spec §7.4:
    system permission -> agent-call switch -> wiring. Returns None
    when the call may proceed (the phone re-checks live state at
    execution time regardless -- this gate only decides whether the
    phone needs waking and what the user must be asked first).

    resume=True is the /device/resume path: the app initiates it
    after its own fresh on-device read, so the snapshot permission
    and switch checks are skipped on purpose (a settings round-trip
    makes the snapshot stale by construction); the wiring check and
    the phone's live re-check still apply."""
    source = tool["source"]
    with _cond:
        if not _session_online_locked():
            raise CallError(
                "device_offline",
                "the phone app is not online; no data was read and "
                "nothing was written")
        perms = _session["permissions"]
        agent_call = _session.get("agentCall") or {}
        caps = _session.get("capabilities") or set()
        offered = _session["tools"]
    if resume:
        if name not in offered:
            raise CallError(
                "tool_unavailable",
                f"the app did not offer tool {name} in this session",
                _permission_fields(source, "granted", "wiring", "none"))
        return
    if source not in NO_PERMISSION_SOURCES:
        state = perms.get(source, "notDetermined")
        if state != "granted":
            label = _source_label(source)
            if state == "notDetermined" \
                    and PERMISSION_ASK_CAPABILITY in caps:
                token = _park_call(name, arguments, source, "permission")
                decision = _ask_permission(source, name, token)
                if decision == "granted":
                    _drop_park(token)
                    return  # proceed; phone re-checks live anyway
                if decision == "denied":
                    raise CallError(
                        "permission_denied",
                        f"刚才在对话里问过一次，「{label}」的权限没有给。"
                        "卡片还留在对话里，去设置里打开后回来，"
                        "这件事会自动接着办。",
                        _permission_fields(
                            source, "denied", "permission",
                            "open_settings", token, asked=True))
                raise CallError(
                    "permission_required",
                    f"「{label}」还没授权过，我在对话里放了一张授权卡，"
                    "点一下就能当场给；给了之后这件事会自动接着办，"
                    "不用再说一遍。",
                    _permission_fields(
                        source, state, "permission", "ask_in_chat",
                        token))
            if state == "notDetermined":
                # App without ask support: pre-§244 behaviour, but
                # structured and in Chinese like every other message.
                raise CallError(
                    "permission_denied",
                    f"「{label}」还没授权过，手机这边没有弹窗问过，"
                    "这次先没办成。",
                    _permission_fields(
                        source, state, "permission", "none"))
            token = _park_call(name, arguments, source, "permission")
            raise CallError(
                "permission_required",
                f"「{label}」的权限现在是「{_STATE_LABELS.get(state, state)}」，"
                "系统不允许再弹窗问。我在对话里放了一张卡，"
                "去设置里打开后回到对话，这件事会自动接着办。",
                _permission_fields(
                    source, state, "permission", "open_settings",
                    token))
    if source in agent_call and not agent_call[source]:
        token = _park_call(name, arguments, source, "agentSwitch")
        raise CallError(
            "permission_required",
            f"「{_source_label(source)}」的权限已经开着，差的是这一件的"
            "智能体调用开关还没打开。我在对话里放了一张卡，"
            "点「打开并继续」就能接着办。",
            _permission_fields(
                source, "granted", "agentSwitch", "open_switch",
                token))
    if name not in offered:
        raise CallError(
            "tool_unavailable",
            f"the app did not offer tool {name} in this session",
            _permission_fields(source, "granted", "wiring", "none"))


# ------------------------------------------------------- sync dispatch
# Query tools served from the synced copy. Same-name tools with a live
# equivalent fall back to a live read when the copy is empty; the
# fallback result is stamped so freshness claims stay honest.
_SYNC_ONLY = {
    "contacts_count": lambda a: device_sync.contacts_count(),
    "contacts_stats": lambda a: device_sync.contacts_stats(),
    "contacts_list": lambda a: device_sync.contacts_list(
        a.get("limit", 50), a.get("offset", 0)),
    "contacts_get": lambda a: device_sync.contacts_get(
        a.get("contactId", "")),
    "calendar_search": lambda a: device_sync.calendar_search(
        a.get("query", "")),
    "calendar_count": lambda a: device_sync.calendar_count(
        device_sync._parse_ts(a.get("start")),
        device_sync._parse_ts(a.get("end"))),
    "reminders_count": lambda a: device_sync.reminders_count(),
    "reminders_search": lambda a: device_sync.reminders_search(
        a.get("query", "")),
    "photos_stats": lambda a: device_sync.photos_stats(),
    "photos_recent": lambda a: device_sync.photos_recent(
        a.get("limit", 50)),
    "motion_steps_summary": lambda a: device_sync.motion_summary(
        a.get("days", 7)),
}
_FALLBACK_NOTE = "这次是现查的，副本里还没有这份数据"


def _sync_call(name: str, arguments: dict):
    """Serve from the copy. Returns the result dict, or None when the
    copy is empty and the caller should try the live path."""
    try:
        return _SYNC_ONLY[name](arguments)
    except device_sync.CopyEmpty:
        return None
    except device_sync.SyncError as e:
        if e.code == "permission_revoked":
            # §244 P-5: the copy is stop-supplied because the
            # permission is off -- that is an authorization blocker,
            # not a data error. Park the query so it resumes once
            # the user re-grants and the app re-syncs.
            dataset = TOOL_BY_NAME[name]["source"]
            token = _park_call(name, arguments, dataset, "permission",
                               kind="sync")
            raise CallError(
                "permission_required",
                f"「{_source_label(dataset)}」的权限已经关了，"
                "同步副本暂停提供。我在对话里放了一张卡，"
                "去设置里打开、等它同步好，这条查询会自动接着办。",
                _permission_fields(
                    dataset, "denied", "permission", "open_settings",
                    token))
        raise CallError(e.code, e.message)


def _raise_copy_empty(name: str, arguments: dict):
    """An empty-copy sync query: decide whether the real blocker is
    authorization (§244 P-5) or simply a copy that was never made.
    Always raises."""
    dataset = TOOL_BY_NAME[name]["source"]
    with _cond:
        online = _session_online_locked()
        snap = _session["permissions"].get(dataset) \
            if online and _session else None
        caps = _session.get("capabilities") \
            if online and _session else set()
    label = _source_label(dataset)
    if online and snap == "notDetermined" \
            and PERMISSION_ASK_CAPABILITY in (caps or set()):
        token = _park_call(name, arguments, dataset, "permission",
                           kind="sync")
        decision = _ask_permission(dataset, name, token)
        if decision == "granted":
            # Permission is in hand; the copy lands when the app
            # runs its first sync, then the app resumes this query.
            raise CallError(
                "permission_required",
                f"「{label}」的权限已经给好了，手机正在把数据同步过来，"
                "同步完这条查询会自动接着办，不用再问一遍。",
                _permission_fields(
                    dataset, "granted", "permission", "ask_in_chat",
                    token))
        if decision == "denied":
            raise CallError(
                "permission_denied",
                f"刚才在对话里问过一次，「{label}」的权限没有给。"
                "卡片还留在对话里，去设置里打开后回来，"
                "这条查询会自动接着办。",
                _permission_fields(
                    dataset, "denied", "permission", "open_settings",
                    token, asked=True))
        raise CallError(
            "permission_required",
            f"「{label}」还没授权过，我在对话里放了一张授权卡，"
            "点一下就能当场给；给了之后这条查询会自动接着办。",
            _permission_fields(
                dataset, snap, "permission", "ask_in_chat", token))
    if online and snap in ("denied", "restricted", "writeOnly"):
        token = _park_call(name, arguments, dataset, "permission",
                           kind="sync")
        raise CallError(
            "permission_required",
            f"「{label}」的权限现在是「{_STATE_LABELS.get(snap, snap)}」，"
            "系统不允许再弹窗问。我在对话里放了一张卡，"
            "去设置里打开后回到对话，这条查询会自动接着办。",
            _permission_fields(
                dataset, snap, "permission", "open_settings", token))
    try:
        st = device_sync.dataset_state(dataset)
    except Exception:
        st = None
    if st is not None and st.get("permission_state") == "revoked":
        token = _park_call(name, arguments, dataset, "permission",
                           kind="sync")
        raise CallError(
            "permission_required",
            f"「{label}」的权限已经关了，同步副本暂停提供。"
            "我在对话里放了一张卡，去设置里打开、等它同步好，"
            "这条查询会自动接着办。",
            _permission_fields(
                dataset, "denied", "permission", "open_settings",
                token))
    raise CallError(
        "sync_copy_empty",
        f"「{label}」还没有同步到服务器，暂时答不了；"
        "打开 App 让它同步一次，就能查了。",
        _permission_fields(dataset, snap or "granted", "sync",
                           "none"))


def _calendar_list_events(arguments: dict):
    """Copy only when its coverage fully contains the window;
    otherwise one whole live call for the full window.

    Complexity audit 2026-11-11 item 2: the old hybrid stitched
    copy + live segments together (segment arithmetic plus an
    "uncovered" ledger). That whole calculus is gone -- a window
    the copy cannot vouch for end to end is re-asked whole, so a
    result is never a stitched mix of two sources."""
    start_ts = device_sync._parse_ts(arguments.get("start"))
    end_ts = device_sync._parse_ts(arguments.get("end"))
    if start_ts is None or end_ts is None or end_ts <= start_ts:
        raise CallError("bad_arguments",
                        "start/end must be ISO 8601 with end after start")
    copy_seen = False
    try:
        st = device_sync.dataset_state("calendar")
        if st is None or st["synced_at"] is None:
            raise device_sync.CopyEmpty("calendar")
        copy_seen = True
        cov_start, cov_end = device_sync.calendar_coverage_epochs(st)
        if cov_start is not None and cov_end is not None \
                and cov_start <= start_ts and end_ts <= cov_end:
            events, st = device_sync.calendar_copy_events(
                start_ts, end_ts)
            result = device_sync.envelope("calendar", st)
            result.update({"events": events,
                           "servedBy": "sync_copy"})
            return result, None, None
    except device_sync.CopyEmpty:
        pass  # no copy at all: fall through to the whole live call
    except device_sync.SyncError as e:
        raise CallError(e.code, e.message)
    result, object_id, call_id = _live_tool_call(
        "calendar_list_events", arguments)
    if isinstance(result, dict):
        result = dict(result)
        result["servedBy"] = "live_fallback"
        result["note"] = ("副本覆盖不到这个时间段，这次是整段现查的"
                          if copy_seen else _FALLBACK_NOTE)
    return result, object_id, call_id


def run_tool_call(name: str, arguments: dict):
    """Execute one tool call. Returns (result_obj, object_id, call_id).
    Raises CallError with a structured code on any honest failure."""
    tool = TOOL_BY_NAME.get(name)
    if tool is None:
        raise CallError("unknown_tool", f"no such tool: {name}")
    if name == "device_status":
        sync = device_sync.status_all()
        with _cond:
            if _session is None:
                return {"online": False, "sync": sync}, None, None
            return {"online": _session_online_locked(),
                    "deviceId": _session["deviceId"],
                    "appVersion": _session["appVersion"],
                    "lastSeen": _session["lastSeen"],
                    "permissions": _session["permissions"],
                    "tools": sorted(_session["tools"]),
                    "sync": sync}, None, None

    if name in _SYNC_ONLY:
        result = _sync_call(name, arguments)
        if result is None:
            _raise_copy_empty(name, arguments)
        return result, None, None
    if name == "calendar_list_events":
        return _calendar_list_events(arguments)
    if name in ("contacts_search", "reminders_list"):
        dataset = "contacts" if name == "contacts_search" \
            else "reminders"
        try:
            if name == "contacts_search":
                result = device_sync.contacts_search(
                    arguments.get("query", ""))
            else:
                result = device_sync.reminders_list(
                    arguments.get("listName"))
            return result, None, None
        except device_sync.CopyEmpty:
            pass  # fall through to the live path below
        except device_sync.SyncError as e:
            raise CallError(e.code, e.message)
        result, object_id, call_id = _live_tool_call(name, arguments)
        if isinstance(result, dict):
            result = dict(result)
            result["servedBy"] = "live_fallback"
            result["note"] = _FALLBACK_NOTE
        return result, object_id, call_id

    result, object_id, call_id = _live_tool_call(name, arguments)
    dataset = device_sync.WRITE_DATASET.get(name)
    if dataset and isinstance(result, dict) \
            and not result.get("idempotentReplay"):
        device_sync.mark_pending_write(dataset)
    return result, object_id, call_id


def _live_tool_call(name: str, arguments: dict, resume: bool = False):
    tool = TOOL_BY_NAME.get(name)
    # Replay eligibility is decided by the registry alone:
    # NEVER_REPLAY_TOOLS are simply absent from WRITE_TOOLS
    # (complexity audit item 2 removed the second hard exclusion
    # that used to sit here as a duplicate line of defence).
    idem = arguments.get("idempotencyKey") \
        if name in WRITE_TOOLS \
        else None
    if idem:
        stored = _load_write_keys().get(idem)
        if stored is not None:
            return {"idempotentReplay": True, "tool": name,
                    "objectId": stored.get("objectId")}, stored.get(
                        "objectId"), None

    # §244: authorization layers are decided by the gate (it may
    # wait on an in-chat permission_ask); the queueing below only
    # re-checks liveness, the phone re-checks everything live at
    # execution time.
    _permission_gate(name, tool, arguments, resume=resume)

    with _cond:
        if not _session_online_locked():
            raise CallError(
                "device_offline",
                "the phone app is not online; no data was read and "
                "nothing was written")
        call_id = "call-" + secrets.token_hex(6)
        rec = {"callId": call_id, "tool": name, "arguments": arguments,
               "createdAt": _now(), "delivered": False,
               "event": threading.Event(), "response": None,
               "sessionId": _session["sessionId"]}
        _pending[call_id] = rec
        _cond.notify_all()

    timeout = TOOL_TIMEOUTS.get(name, CALL_TIMEOUT)
    if not rec["event"].wait(timeout):
        with _cond:
            _pending.pop(call_id, None)
        err = CallError(
            "device_timeout",
            f"the phone did not answer within {timeout:.0f}s")
        err.call_id = call_id
        raise err
    with _cond:
        _pending.pop(call_id, None)
    resp = rec["response"] or {}
    if resp.get("status") == "error":
        err = resp.get("error") or {}
        cerr = CallError(err.get("code", "device_error"),
                         err.get("message", "device returned an error"))
        if err.get("code") == "permission_denied":
            # §244 P-1: the phone reports the live state it just
            # read; pass it through structured like every other
            # permission failure.
            cerr.fields = _permission_fields(
                tool["source"], err.get("state") or "denied",
                "permission", "none")
        cerr.call_id = call_id
        raise cerr
    result = resp.get("result") or {}
    object_id = result.get("objectId") if isinstance(result, dict) \
        else None
    if idem:
        _save_write_key(idem, name, object_id)
    return result, object_id, call_id


# ---------------------------------------------------------------- http
def _mcp_result_text(obj) -> list:
    return [{"type": "text",
             "text": json.dumps(obj, ensure_ascii=False)}]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # access log: method/path/status
        print(f"[device-bridge] {self.command} {self.path} "
              f"-> {args[1] if len(args) > 1 else ''}", flush=True)

    # -- plumbing ------------------------------------------------------
    def _send(self, code: int, obj=None, raw: bytes | None = None):
        body = raw if raw is not None else (
            json.dumps(obj, ensure_ascii=False).encode("utf-8")
            if obj is not None else b"")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_BODY:
            raise ValueError("body too large")
        raw = self.rfile.read(n) if n else b""
        return json.loads(raw.decode("utf-8")) if raw else {}

    def _authed(self) -> bool:
        if not API_KEY:
            return False  # fail closed
        got = self.headers.get("Authorization") or ""
        return hmac.compare_digest(got, f"Bearer {API_KEY}")

    # -- device channel --------------------------------------------------
    def _device_session(self):
        global _session
        body = self._body()
        sid = "sess-" + secrets.token_hex(6)
        with _cond:
            old = _session
            if old is not None:  # new registration replaces the old one
                for rec in _pending.values():
                    if rec["sessionId"] == old["sessionId"] \
                            and not rec["event"].is_set():
                        rec["response"] = {
                            "status": "error",
                            "error": {"code": "device_offline",
                                      "message": "session replaced"}}
                        rec["event"].set()
            _session = {"sessionId": sid,
                        "deviceId": body.get("deviceId", ""),
                        "appVersion": body.get("appVersion", ""),
                        "permissions": body.get("permissions") or {},
                        "agentCall": body.get("agentCall") or {},
                        "capabilities":
                            set(body.get("capabilities") or []),
                        "tools": set(body.get("tools") or []),
                        "connectedAt": _now(), "lastSeen": _now()}
            _cond.notify_all()
        self._send(201, {"sessionId": sid, "pollWaitSec": POLL_MAX_WAIT,
                         "callTimeoutSec": CALL_TIMEOUT,
                         "sessionTtlSec": SESSION_TTL})

    def _device_touch(self, body) -> bool:
        with _cond:
            if _session is None \
                    or body.get("sessionId") != _session["sessionId"]:
                return False
            _session["lastSeen"] = _now()
            return True

    def _device_poll(self, qs):
        sid = (qs.get("sessionId") or [""])[0]
        wait = min(float((qs.get("wait") or [POLL_MAX_WAIT])[0]),
                   POLL_MAX_WAIT)
        deadline = _now() + wait
        with _cond:
            while True:
                if _session is None or _session["sessionId"] != sid:
                    self._send(409, {"error": "unknown_session"})
                    return
                _session["lastSeen"] = _now()
                for rec in _pending.values():
                    if rec["sessionId"] == sid and not rec["delivered"]:
                        rec["delivered"] = True
                        self._send(200, {"call": {
                            "callId": rec["callId"], "tool": rec["tool"],
                            "kind": rec.get("kind", "tool"),
                            "arguments": rec["arguments"],
                            "createdAt": rec["createdAt"]}})
                        return
                remain = deadline - _now()
                if remain <= 0:
                    self._send(200, {"call": None})
                    return
                _cond.wait(timeout=remain)

    def _device_respond(self):
        body = self._body()
        with _cond:
            rec = _pending.get(body.get("callId") or "")
            if rec is None or _session is None \
                    or body.get("sessionId") != _session["sessionId"]:
                self._send(404, {"error": "unknown_call"})
                return
            _session["lastSeen"] = _now()
            if not rec["event"].is_set():
                rec["response"] = {
                    "status": body.get("status", "error"),
                    "result": body.get("result"),
                    "error": body.get("error")}
                rec["event"].set()
            _cond.notify_all()
        self._send(200, {"ok": True})

    def _device_resume(self):
        """§244 P-4: the app calls this after the user authorized
        (settings round-trip, switch flip, or first sync done). The
        parked call is re-dispatched once -- the token is consumed
        only when the dispatch actually happens -- and the tool
        result (or a structured error) returns in this response, so
        the card in the chat can show the outcome. The phone
        re-checks live state at execution; the bridge only waits
        briefly for the tool to be offered again (the app
        re-registers after a settings round-trip)."""
        body = self._body()
        token = body.get("resumeToken") or ""
        park = _peek_park(token)
        if park is None:
            self._send(404, {"ok": False,
                             "error": "unknown_or_expired_token"})
            return
        started = _now()
        entry = {"ts": started, "callId": None, "tool": park["tool"],
                 "source": "resume", "status": "", "durationMs": 0,
                 "errorCode": None}
        deadline = _now() + 5
        while True:
            with _cond:
                online = _session_online_locked()
                offered = bool(online) \
                    and park["tool"] in _session["tools"]
            if offered or _now() > deadline:
                break
            time.sleep(0.25)
        if not online:
            entry["status"] = "error"
            entry["errorCode"] = "device_offline"
            entry["durationMs"] = int((_now() - started) * 1000)
            _audit(entry)
            self._send(409, {"ok": False, "error": "device_offline",
                             "message": "手机现在不在线，等它回到前台再试"})
            return
        _consume_park(token)  # single use, from here on it is spent
        try:
            if park.get("kind") == "sync":
                result = _sync_call(park["tool"], park["arguments"])
                if result is None:
                    raise CallError(
                        "sync_copy_empty",
                        "副本还没同步好，再等同步完成试一次。",
                        _permission_fields(
                            park["source"], "granted", "sync", "none"))
            else:
                result, _oid, call_id = _live_tool_call(
                    park["tool"], park["arguments"], resume=True)
                entry["callId"] = call_id
            entry["status"] = "ok"
            self._send(200, {"ok": True, "result": result})
        except CallError as e:
            entry["status"] = "error"
            entry["errorCode"] = e.code
            entry["callId"] = e.call_id
            payload = {"ok": False, "error": e.code,
                       "message": e.message}
            payload.update(e.fields)
            self._send(200, payload)
        entry["durationMs"] = int((_now() - started) * 1000)
        _audit(entry)

    def _device_park_state(self):
        """§261: the bridge is the single source of truth for
        whether a parked call still exists. The app reconciles
        its local permission cards against this read face --
        gone means gone (expired/consumed/dropped), and the
        park's own expiresAt is the one 24h clock both sides
        read. Read-only: peeking never consumes the token.
        Arguments are never returned (they stay bridge-side
        operational state, as with the parks file itself)."""
        body = self._body()
        wanted = body.get("resumeToken") or ""
        park = _peek_park(wanted) if wanted else None
        if park is None:
            self._send(200, {"ok": True, "exists": False})
            return
        self._send(200, {"ok": True, "exists": True, "park": {
            "source": park.get("source"),
            "tool": park.get("tool"),
            "blockerLayer": park.get("blockerLayer"),
            "kind": park.get("kind"),
            "createdAt": park.get("createdAt"),
            "expiresAt": park.get("expiresAt"),
            "askOutcome": park.get("askOutcome"),
        }})

    def _device_disconnect(self):
        global _session
        body = self._body()
        with _cond:
            if _session is not None \
                    and body.get("sessionId") == _session["sessionId"]:
                for rec in _pending.values():
                    if rec["sessionId"] == _session["sessionId"] \
                            and not rec["event"].is_set():
                        rec["response"] = {
                            "status": "error",
                            "error": {"code": "device_offline",
                                      "message": "device disconnected"}}
                        rec["event"].set()
                _session = None
                _cond.notify_all()
        self._send(200, {"ok": True})

    # -- sync channel ----------------------------------------------------
    def _sync_batch(self):
        body = self._body()
        try:
            out = device_sync.stage_batch(
                body.get("dataset", ""), body.get("batchId", ""),
                body.get("records") or [], body.get("mode", "full"),
                body.get("meta"))
        except device_sync.SyncError as e:
            self._send(400, {"error": e.code, "message": e.message})
            return
        self._send(200, out)

    def _sync_complete(self):
        body = self._body()
        started = _now()
        try:
            out = device_sync.complete(
                body.get("dataset", ""), body.get("batchId", ""),
                body.get("expectedTotal", -1),
                body.get("deviceCompletedAt"), body.get("mode"),
                body.get("coverage"), body.get("aggregates"),
                body.get("removedIds"), body.get("authRange"),
                body.get("rangeNote"), body.get("permissionState"))
        except device_sync.SyncError as e:
            _audit({"ts": started, "callId": None,
                    "tool": f"sync:{body.get('dataset')}",
                    "source": "sync", "status": "error",
                    "durationMs": int((_now() - started) * 1000),
                    "errorCode": e.code})
            code = 409 if e.code == "sync_count_mismatch" else 400
            self._send(code, {"error": e.code, "message": e.message})
            return
        _audit({"ts": started, "callId": None,
                "tool": f"sync:{out['dataset']}", "source": "sync",
                "status": "ok",
                "durationMs": int((_now() - started) * 1000),
                "errorCode": None, "count": out["total_in_store"]})
        self._send(200, out)

    def _sync_manifest(self):
        body = self._body()
        try:
            out = device_sync.manifest_compare(
                body.get("dataset", ""), body.get("entries") or [])
        except device_sync.SyncError as e:
            self._send(400, {"error": e.code, "message": e.message})
            return
        self._send(200, out)

    def _sync_state(self):
        body = self._body()
        try:
            out = device_sync.report_state(
                body.get("dataset", ""), body.get("permissionState"),
                body.get("authRange"), body.get("rangeNote"))
        except device_sync.SyncError as e:
            self._send(400, {"error": e.code, "message": e.message})
            return
        self._send(200, out)

    def _sync_delete(self):
        body = self._body()
        dataset = body.get("dataset")
        targets = [dataset] if dataset else None
        if targets and targets[0] not in device_sync.DATASETS:
            self._send(400, {"error": "unknown_dataset"})
            return
        out = device_sync.delete_copies(targets)
        _audit({"ts": _now(), "callId": None, "tool": "sync:delete",
                "source": "sync", "status": "ok", "durationMs": 0,
                "errorCode": None,
                "count": len(out["deleted"])})
        self._send(200, out)

    def _sync_status(self):
        self._send(200, {"datasets": device_sync.status_all()})

    # -- MCP facade ------------------------------------------------------
    def _mcp(self):
        body = self._body()
        rid = body.get("id")
        method = body.get("method", "")
        if rid is None:  # notification
            self._send(202)
            return
        if method == "initialize":
            self._send(200, {"jsonrpc": "2.0", "id": rid, "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "device-bridge",
                               "version": "0.1.0"},
                "instructions": (
                    "When a device tool returns permission_required "
                    "or permission_denied, an authorization card is "
                    "already waiting in the user's chat: say the fact "
                    "in one short sentence and point to the card. "
                    "Never write settings tutorials and never guess "
                    "at causes. When a tool returns device_timeout, "
                    "say only that the phone did not answer this time "
                    "and offer to retry; do not list possible "
                    "reasons.")}})
            return
        if method == "ping":
            self._send(200, {"jsonrpc": "2.0", "id": rid, "result": {}})
            return
        if method == "tools/list":
            tools = [{"name": t["name"], "description": t["description"],
                      "inputSchema": t["inputSchema"]} for t in TOOLS]
            self._send(200, {"jsonrpc": "2.0", "id": rid,
                             "result": {"tools": tools}})
            return
        if method == "tools/call":
            params = body.get("params") or {}
            name = params.get("name", "")
            arguments = params.get("arguments") or {}
            started = _now()
            entry = {"ts": started, "callId": None, "tool": name,
                     "source": "mcp", "status": "", "durationMs": 0,
                     "errorCode": None}
            try:
                result, object_id, call_id = run_tool_call(name, arguments)
                entry["status"] = "ok"
                entry["callId"] = call_id
                if object_id:
                    entry["objectId"] = object_id
                payload = {"jsonrpc": "2.0", "id": rid, "result": {
                    "content": _mcp_result_text(result),
                    "isError": False}}
            except CallError as e:
                entry["status"] = "error"
                entry["errorCode"] = e.code
                entry["callId"] = e.call_id
                error_obj = {"error": e.code, "message": e.message}
                error_obj.update(e.fields)
                payload = {"jsonrpc": "2.0", "id": rid, "result": {
                    "content": _mcp_result_text(error_obj),
                    "isError": True}}
            entry["durationMs"] = int((_now() - started) * 1000)
            _audit(entry)
            self._send(200, payload)
            return
        self._send(200, {"jsonrpc": "2.0", "id": rid, "error": {
            "code": -32601, "message": f"method not found: {method}"}})

    # -- routing ---------------------------------------------------------
    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/health":
            with _cond:
                online = _session_online_locked()
            self._send(200, {"ok": True, "service": "device-bridge",
                             "sessionOnline": online})
            return
        if not self._authed():
            self._send(401, {"error": "unauthorized"})
            return
        if u.path == "/device/poll":
            self._device_poll(parse_qs(u.query))
            return
        if u.path == "/device/sync/status":
            self._sync_status()
            return
        self._send(404, {"error": "not_found"})

    def do_POST(self):
        u = urlparse(self.path)
        if not self._authed():
            self._send(401, {"error": "unauthorized"})
            return
        try:
            if u.path == "/device/session":
                self._device_session()
            elif u.path == "/device/heartbeat":
                ok = self._device_touch(self._body())
                self._send(200 if ok else 404,
                           {"ok": ok} if ok else
                           {"error": "unknown_session"})
            elif u.path == "/device/respond":
                self._device_respond()
            elif u.path == "/device/resume":
                self._device_resume()
            elif u.path == "/device/park-state":
                self._device_park_state()
            elif u.path == "/device/disconnect":
                self._device_disconnect()
            elif u.path == "/device/sync/batch":
                self._sync_batch()
            elif u.path == "/device/sync/complete":
                self._sync_complete()
            elif u.path == "/device/sync/manifest":
                self._sync_manifest()
            elif u.path == "/device/sync/state":
                self._sync_state()
            elif u.path == "/device/sync/delete":
                self._sync_delete()
            elif u.path == "/mcp":
                self._mcp()
            else:
                self._send(404, {"error": "not_found"})
        except (ValueError, json.JSONDecodeError) as e:
            self._send(400, {"error": f"bad_request: {e}"})


# ------------------------------------------------------- gateway transport
# Batch 5 transport adapter: api_server's aiohttp face collects
# (method, path, headers, body) and calls dispatch_sync on a worker
# thread; the bridge Handler above runs verbatim against the
# in-memory shim, and the single _send() every route ends in lands
# in the capture buffer. The standalone HTTP server is gone -- the
# gateway process is the only host now.

class _GatewayHandler(Handler):
    """The bridge Handler running against an in-memory request."""

    def __init__(self, method: str, path: str, headers: dict,
                 body: bytes):
        self.command = method
        self.path = path
        self.headers = headers
        self.rfile = io.BytesIO(body)
        self.wfile = io.BytesIO()
        self._status = 200

    def send_response(self, code, message=None):
        self._status = code

    def send_header(self, key, value):
        pass

    def end_headers(self):
        pass

    def log_message(self, fmt, *args):
        pass


def dispatch_sync(method: str, path: str, headers: dict,
                  body: bytes):
    """Run one request through the bridge engine. Returns
    (status, raw_body). Blocking by design (poll waits, call
    timeouts) -- callers run it on a worker thread."""
    handler = _GatewayHandler(method, path, headers, body)
    if method == "GET":
        handler.do_GET()
    elif method == "POST":
        handler.do_POST()
    else:
        return 405, b'{"error": "method_not_allowed"}'
    return handler._status, handler.wfile.getvalue()


def start() -> None:
    """Gateway start hook (the bridge main()'s setup half): the
    data-dir discipline, plus a loud line when the single key is
    missing (authed routes then fail closed, as on the bridge)."""
    if not API_KEY:
        print("[device-gateway] API_SERVER_KEY unset; all authed "
              "routes will fail closed", flush=True)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    device_sync.init(DATA_DIR)
    _audit_path.touch(exist_ok=True)
    os.chmod(_audit_path, 0o600)  # device data dir discipline: 0600
    print(f"[device-gateway] ready, data dir {DATA_DIR}", flush=True)


start()
