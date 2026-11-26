#!/usr/bin/env python3
"""identity_gateway: the identity bridge's surface as an in-process
gateway module -- soul name read, the avatar store, and the /mcp
facade (6 identity tools).

Batch 4 of the bridge retirement (bridge-retirement-spec-20261124
section 3 row 13 + section 5.2): the companion identity bridge
(port 8648) moves into the gateway. api_server.py mounts this
module's dispatch on the canonical /v1/identity/{tail:.*} and the
shape-preserving /api/identity-bridge/{tail:.*} wildcards (all
methods), plus POST /mcp/identity for the canonical MCP face; the
Hermes mcp_servers.identity registration keeps its public shape
URL (/api/identity-bridge/mcp, Bearer ${API_SERVER_KEY}) -- nginx
repoints the location at the gateway and the registration itself
does not change.

Business functions below are carried verbatim from
companion/modules/identity_bridge.py (AST-checked at prefab time);
the registered differences are only the shell:

- auth is the gateway's single key (api_server @_require_auth);
  the bridge's own IDENTITY_BRIDGE_KEY retires with the bridge;
- the avatar store home moves to /opt/data/identity (the bridge's
  /opt/identity-data tree is carried over in place at rollout;
  AVATAR_DIR still wins when set);
- traces go to the gateway's own oneday shape face over loopback
  (ONEDAY_BASE default http://127.0.0.1:8642/api/oneday-bridge)
  with the single gateway key (ONEDAY_CLIENT_KEY: API_SERVER_KEY
  first, ONEDAY_BRIDGE_KEY only as an isolated-test fallback);
- POST /identity/name stays retired (NAME_WRITE_RETIRED_180,
  batch 1): dispatch falls through to 404 for it, exactly as the
  bridge did; the rename machinery lives on in-process because
  the MCP tool identity_set_name calls it directly.

Rebuilt 2026-11-25 onto the 1.23.0 baseline (see PREFAB-NOTES.md):
the 2026-11-24 prefab copy of this file was lost before the
rebase; this file reproduces its registered interface (dispatch
surface + selftest contract) from the bridge source, which the
original was itself a verbatim carry of.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets
import sys
import threading
import time
import urllib.request
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/opt/data"))
SOUL_PATH = Path(os.environ.get(
    "IDENTITY_SOUL_PATH", str(HERMES_HOME / "SOUL.md")))
AVATAR_DIR = Path(os.environ.get(
    "AVATAR_DIR",
    os.environ.get("IDENTITY_DATA_DIR", "/opt/data/identity")))
ONEDAY_BASE = os.environ.get(
    "ONEDAY_BASE", "http://127.0.0.1:8642/api/oneday-bridge")
# Batch 3 (gateway 1.19.0): the oneday face lives in the gateway
# now and authenticates with the single gateway key; the bridge
# key is retired, so the trace sink falls back to the gateway key.
ONEDAY_CLIENT_KEY = os.environ.get("API_SERVER_KEY", "") \
    or os.environ.get("ONEDAY_BRIDGE_KEY", "")
IDENTITY_GATEWAY_VERSION = os.environ.get(
    "IDENTITY_GATEWAY_VERSION", "1.0")

# Active server catalog. The companion implementation is retired by
# deployment package 2.0.0 (server/RULES.md and install.sh); keep the
# shipped gateway catalog here as the sole server-side validation source.
PRESET_IDS = (
    "partner", "paw", "sparkles", "atom",
    "blob-blue", "cat-violet", "bear-amber", "bot-cyan",
    "sprout-green", "star-pink", "blob-coral", "bot-slate",
)
MAX_IMAGE_BYTES = 2 * 1024 * 1024
NAME_FALLBACK = "Hermes"
NAME_PUNCT = set("。．.：:、，,；;！!？?")
NAME_STRUCTURAL = {
    "soul", "soul.md", "灵魂", "人设", "身份",
    "identity", "persona", "about", "profile",
}

_lock = threading.Lock()


def _print(*args, **kwargs):
    kwargs.setdefault("flush", True)
    print(*args, **kwargs)


class _Err(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


# ------------------------------------------------------------ name chain
# Line-for-line mirror of OneDayCore.AgentName.resolve: only the
# first H1 inside the first three non-empty lines can be the
# identity name; it must be <=20 chars, free of sentence
# punctuation, and not a structural heading. Anything else falls
# back to "Hermes" -- never guess.

def _parse_soul_name(text: str) -> str:
    content_lines = 0
    for raw in text.split("\n"):
        trimmed = raw.strip()
        if not trimmed:
            continue
        content_lines += 1
        if content_lines > 3:
            return NAME_FALLBACK
        if not trimmed.startswith("# "):
            continue
        candidate = trimmed[2:].strip()
        if (not candidate or len(candidate) > 20
                or any(ch in NAME_PUNCT for ch in candidate)
                or candidate.lower() in NAME_STRUCTURAL):
            return NAME_FALLBACK
        return candidate
    return NAME_FALLBACK


def _find_title_line(lines: list) -> int:
    """Index (into raw lines) of the first H1 inside the first
    three non-empty lines, or -1. This is the identity slot."""
    content_lines = 0
    for i, raw in enumerate(lines):
        trimmed = raw.strip()
        if not trimmed:
            continue
        content_lines += 1
        if content_lines > 3:
            return -1
        if trimmed.startswith("# "):
            return i
    return -1


def _validate_new_name(raw) -> str:
    if not isinstance(raw, str):
        raise _Err(400, "name 必须是字符串")
    name = raw.strip()
    if not name:
        raise _Err(400, "name 不能为空")
    if len(name) > 20:
        raise _Err(400, "name 超过 20 字（与 App 解析口径一致）")
    if any(ch in NAME_PUNCT for ch in name):
        raise _Err(400, "name 不能含句读标点（与 App 解析口径一致）")
    if name.lower() in NAME_STRUCTURAL:
        raise _Err(400, "name 不能是结构词（soul/人设/身份等）")
    if "#" in name or any(ord(ch) < 32 for ch in name):
        raise _Err(400, "name 含非法字符")
    return name


# ------------------------------------------------------------ traces (P0)

def _record_trace(action: str, target: dict, status: str, *,
                  actor: str = "agent", result=None, error=None,
                  detail=None) -> dict:
    """Write one five-element trace via the oneday face. On any
    failure, spill the same-shaped record locally and log loudly:
    the action still happened, so its trace must exist somewhere
    the main line can find and merge."""
    body = {"action": action, "actor": actor, "target": target,
            "status": status, "result": result, "error": error,
            "detail": detail}
    if ONEDAY_CLIENT_KEY:
        try:
            req = urllib.request.Request(
                ONEDAY_BASE.rstrip("/") + "/traces",
                data=json.dumps(body, ensure_ascii=False
                                ).encode("utf-8"),
                headers={"Authorization":
                         f"Bearer {ONEDAY_CLIENT_KEY}",
                         "Content-Type": "application/json"},
                method="POST")
            with urllib.request.urlopen(req, timeout=5) as resp:
                view = json.loads(resp.read().decode("utf-8"))
            return {"mode": "oneday", "id": view.get("id")}
        except Exception as e:
            _print(f"trace via oneday failed, spilling: {e!r}",
                   file=sys.stderr)
    rec = dict(body)
    rec["at"] = time.time()
    rec["spilled"] = True
    try:
        AVATAR_DIR.mkdir(parents=True, exist_ok=True)
        with open(AVATAR_DIR / "traces-spill.jsonl", "a",
                  encoding="utf-8") as fh:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception as e:
        _print(f"trace spill ALSO failed: {e!r}; record={rec!r}",
               file=sys.stderr)
    return {"mode": "spill", "id": None}


def _traced(action: str, target: dict, actor: str, fn):
    """Run fn() -> (payload, summary); trace ok/failed either way,
    then return payload or re-raise the failure verbatim."""
    try:
        payload, summary = fn()
    except _Err as e:
        _record_trace(action, target, "failed", actor=actor,
                      error=e.message, detail={"via": "identity"})
        raise
    except Exception as e:
        _print(f"{action} unhandled: {e!r}", file=sys.stderr)
        _record_trace(action, target, "failed", actor=actor,
                      error=f"{type(e).__name__}: {e}",
                      detail={"via": "identity"})
        raise _Err(500, "服务器内部错误")
    trace = _record_trace(action, target, "ok", actor=actor,
                          result=summary, detail={"via": "identity"})
    if isinstance(payload, dict):
        payload = dict(payload)
        payload["trace"] = trace
    return payload


# ------------------------------------------------------------ soul rename

def _soul_target(name: str) -> dict:
    return {"kind": "identity", "id": "soul-name", "label": name,
            "ref": "oneday://identity/name"}


def _name_state_path() -> Path:
    return AVATAR_DIR / "name-state.json"


def _load_name_state():
    """Last recorded name write: {name, updatedAt, source}.
    None when no write was ever recorded."""
    try:
        return json.loads(_name_state_path().read_text(
            encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def _record_name_state(name: str, source: str) -> None:
    """Stamp a name write with the server receipt time --
    the App's last-write-wins arbiter reads this back via
    GET /identity/name. Source is audit-only."""
    AVATAR_DIR.mkdir(parents=True, exist_ok=True)
    tmp = _name_state_path().with_suffix(".json.tmp")
    tmp.write_text(json.dumps(
        {"name": name, "updatedAt": time.time(), "source": source},
        ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, _name_state_path())


def _get_name() -> dict:
    try:
        text = SOUL_PATH.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise _Err(404, "SOUL.md 不存在")
    name = _parse_soul_name(text)
    state = _load_name_state()
    if state and state.get("name") == name:
        updated_at = state.get("updatedAt")
        source = state.get("source", "unknown")
    else:
        # No record for the name as it stands (it was written
        # before this ledger existed, or via another path such
        # as the App soul editor): fall back to the soul file's
        # mtime as the write-time approximation.
        updated_at = SOUL_PATH.stat().st_mtime
        source = "unknown"
    return {"soulName": name,
            "soulPath": str(SOUL_PATH),
            "updatedAt": updated_at,
            "source": source,
            "note": "生效名按末写胜裁决（App 侧 AgentNameLWW）："
                    "本机覆盖与 soul 名各带写入时刻，后写者胜"}


def _set_name(raw_name, dry_run: bool, actor: str) -> dict:
    target = _soul_target(raw_name if isinstance(raw_name, str)
                          else "")

    def fn():
        name = _validate_new_name(raw_name)
        with _lock:
            try:
                text = SOUL_PATH.read_text(encoding="utf-8")
            except FileNotFoundError:
                raise _Err(404, "SOUL.md 不存在")
            prev = _parse_soul_name(text)
            lines = text.split("\n")
            idx = _find_title_line(lines)
            if idx >= 0:
                mode = "replace"
                lines[idx] = f"# {name}"
            else:
                mode = "insert"
                lines.insert(0, f"# {name}")
            new_text = "\n".join(lines)
            if _parse_soul_name(new_text) != name:
                raise _Err(500, "改后解析不到新名，已放弃写入")
            if not dry_run:
                stat = SOUL_PATH.stat()
                backup_dir = AVATAR_DIR / "soul-backups"
                backup_dir.mkdir(parents=True, exist_ok=True)
                stamp = time.strftime("%Y%m%d-%H%M%S")
                (backup_dir / f"SOUL-{stamp}.md").write_text(
                    text, encoding="utf-8")
                tmp = SOUL_PATH.with_suffix(".md.identity-tmp")
                tmp.write_text(new_text, encoding="utf-8")
                os.chmod(tmp, stat.st_mode)
                try:
                    os.chown(tmp, stat.st_uid, stat.st_gid)
                except PermissionError:
                    pass
                os.replace(tmp, SOUL_PATH)
                written = SOUL_PATH.read_text(encoding="utf-8")
                if _parse_soul_name(written) != name:
                    raise _Err(500, "写入后回读解析不一致")
                _record_name_state(name, actor)
            summary = (f"智能体改名为「{name}」（{mode} 标题行，"
                       f"原 soul 名「{prev}」）"
                       + ("（dry-run 未落盘）" if dry_run else ""))
            return {"ok": True, "soulName": name,
                    "previousSoulName": prev, "mode": mode,
                    "dryRun": dry_run}, summary

    return _traced("identity.set_name", target, actor, fn)


# ------------------------------------------------------------ avatar store

def _index_path() -> Path:
    return AVATAR_DIR / "index.json"


def _load_index() -> dict:
    try:
        return json.loads(_index_path().read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {"currentId": None, "items": []}


def _save_index(idx: dict) -> None:
    AVATAR_DIR.mkdir(parents=True, exist_ok=True)
    tmp = _index_path().with_suffix(".json.tmp")
    tmp.write_text(json.dumps(idx, ensure_ascii=False, indent=1),
                   encoding="utf-8")
    os.replace(tmp, _index_path())


def _item_view(item: dict, current_id) -> dict:
    view = {"id": item["id"], "kind": item["kind"],
            "source": item.get("source", "ai"),
            "createdAt": item["createdAt"],
            "current": item["id"] == current_id}
    if item["kind"] == "preset":
        view["presetId"] = item["presetId"]
    else:
        view["contentType"] = item["contentType"]
        view["bytes"] = item["bytes"]
        view["sha256"] = item["sha256"]
    return view


def _get_avatar() -> dict:
    with _lock:
        idx = _load_index()
    current = next((it for it in idx["items"]
                    if it["id"] == idx["currentId"]), None)
    updated_at = idx.get("currentUpdatedAt")
    source = idx.get("currentSource")
    if updated_at is None and current is not None:
        # Ledger pre-dates the current-pointer stamp: the
        # current item's own creation time is when this
        # pointer last moved (items were made current at
        # creation back then).
        updated_at = current["createdAt"]
        source = current.get("source", "ai")
    return {"currentId": idx["currentId"],
            "currentUpdatedAt": updated_at,
            "currentSource": source,
            "items": [_item_view(it, idx["currentId"])
                      for it in idx["items"]]}


def _avatar_target(item_id: str, label: str) -> dict:
    return {"kind": "avatar", "id": item_id, "label": label,
            "ref": f"oneday://identity/avatar/{item_id}"
            if item_id else "oneday://identity/avatar"}


def _sniff_image(data: bytes):
    if data[:3] == b"\xff\xd8\xff":
        return "jpg", "image/jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png", "image/png"
    return None, None


def _add_avatar_image(raw_b64, source: str, make_current: bool,
                      actor: str) -> dict:
    item_id = "av_" + secrets.token_hex(6)
    target = _avatar_target(item_id, "AI 头像图")

    def fn():
        if not isinstance(raw_b64, str) or not raw_b64.strip():
            raise _Err(400, "imageBase64 不能为空")
        try:
            data = base64.b64decode(raw_b64, validate=True)
        except Exception:
            raise _Err(400, "imageBase64 不是合法 base64")
        if len(data) > MAX_IMAGE_BYTES:
            raise _Err(400, "图片超过 2MB 上限")
        ext, ctype = _sniff_image(data)
        if ext is None:
            raise _Err(400, "只收 JPEG/PNG 图片")
        with _lock:
            AVATAR_DIR.mkdir(parents=True, exist_ok=True)
            fname = f"{item_id}.{ext}"
            (AVATAR_DIR / fname).write_bytes(data)
            idx = _load_index()
            now = time.time()
            item = {"id": item_id, "kind": "image", "file": fname,
                    "contentType": ctype, "bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                    "source": source, "createdAt": now}
            idx["items"].append(item)
            if make_current:
                idx["currentId"] = item_id
                idx["currentUpdatedAt"] = now
                idx["currentSource"] = source
            _save_index(idx)
            view = _item_view(item, idx["currentId"])
        return view, f"头像仓新增图片 {item_id}（{len(data)} 字节" \
            + ("，已设为当前）" if make_current else "，未设当前）")

    return _traced("identity.set_avatar_image", target, actor, fn)


def _add_avatar_preset(preset_id, source: str, make_current: bool,
                       actor: str) -> dict:
    item_id = "av_" + secrets.token_hex(6)
    target = _avatar_target(item_id, f"预置头像 {preset_id}")

    def fn():
        if preset_id not in PRESET_IDS:
            raise _Err(400, f"presetId 不在目录内：{PRESET_IDS}")
        with _lock:
            idx = _load_index()
            now = time.time()
            item = {"id": item_id, "kind": "preset",
                    "presetId": preset_id, "source": source,
                    "createdAt": now}
            idx["items"].append(item)
            if make_current:
                idx["currentId"] = item_id
                idx["currentUpdatedAt"] = now
                idx["currentSource"] = source
            _save_index(idx)
            view = _item_view(item, idx["currentId"])
        return view, f"头像仓新增预置 {preset_id}" \
            + ("，已设为当前" if make_current else "，未设当前")

    return _traced("identity.set_avatar_preset", target, actor, fn)


def _select_avatar(item_id, actor: str) -> dict:
    target = _avatar_target(
        item_id if isinstance(item_id, str) else "", "切换当前头像")

    def fn():
        if not isinstance(item_id, str) or not item_id:
            raise _Err(400, "id 不能为空")
        with _lock:
            idx = _load_index()
            item = next((it for it in idx["items"]
                         if it["id"] == item_id), None)
            if item is None:
                raise _Err(404, "头像条目不存在")
            idx["currentId"] = item_id
            # Re-selecting an old item is still a fresh
            # write of the pointer: stamp it, or the App's
            # last-write-wins arbiter would judge it by the
            # item's ancient creation time and refuse it.
            idx["currentUpdatedAt"] = time.time()
            idx["currentSource"] = actor
            _save_index(idx)
            view = _item_view(item, item_id)
        label = (item.get("presetId") if item["kind"] == "preset"
                 else "图片")
        return view, f"当前头像切换为 {item_id}（{label}）"

    return _traced("identity.select_avatar", target, actor, fn)


def _read_avatar_image(item_id) -> tuple:
    with _lock:
        idx = _load_index()
        wanted = item_id or idx["currentId"]
        item = next((it for it in idx["items"]
                     if it["id"] == wanted), None)
    if item is None:
        raise _Err(404, "头像不存在")
    if item["kind"] != "image":
        raise _Err(400, "当前头像是预置引用，没有图片字节")
    data = (AVATAR_DIR / item["file"]).read_bytes()
    return data, item["contentType"]


# ------------------------------------------------------------ MCP facade

IDENTITY_TOOLS = [
    {"name": "identity_get_name",
     "description": "读取智能体当前的 soul 身份名",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "identity_set_name",
     "description": "给自己改名：只改 soul 的身份标题行，"
                    "不动 soul 其他内容（<=20 字、无句读）",
     "inputSchema": {"type": "object",
                     "properties": {
                         "name": {"type": "string"}},
                     "required": ["name"]}},
    {"name": "identity_get_avatar",
     "description": "查看头像仓：当前头像与历史",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "identity_set_avatar_preset",
     "description": "把头像换成预置形象",
     "inputSchema": {"type": "object",
                     "properties": {
                         "presetId": {"type": "string",
                                      "enum": list(PRESET_IDS)}},
                     "required": ["presetId"]}},
    {"name": "identity_set_avatar_image",
     "description": "把自己生成的图片存进头像仓并设为当前头像"
                    "（JPEG/PNG，base64，<=2MB）",
     "inputSchema": {"type": "object",
                     "properties": {
                         "imageBase64": {"type": "string"}},
                     "required": ["imageBase64"]}},
    {"name": "identity_select_avatar",
     "description": "把头像仓里已有的一条设为当前头像",
     "inputSchema": {"type": "object",
                     "properties": {
                         "id": {"type": "string"}},
                     "required": ["id"]}},
]


def _run_identity_tool(name: str, args: dict):
    """Returns (result_obj, is_error). Mutations trace inside the
    core functions; pure reads are traced here so every tools/call
    leaves one record, same as the goals facade."""
    try:
        if name == "identity_get_name":
            view = _get_name()
            _record_trace("identity.get_name",
                          _soul_target(view["soulName"]), "ok",
                          result=f"当前 soul 名「{view['soulName']}」",
                          detail={"via": "mcp"})
            return view, False
        if name == "identity_set_name":
            return _set_name(args.get("name"),
                             bool(args.get("dryRun")), "agent"), False
        if name == "identity_get_avatar":
            view = _get_avatar()
            _record_trace("identity.get_avatar",
                          _avatar_target(view["currentId"] or "", ""),
                          "ok",
                          result=f"头像仓 {len(view['items'])} 条，"
                                 f"当前 {view['currentId']}",
                          detail={"via": "mcp"})
            return view, False
        if name == "identity_set_avatar_preset":
            return _add_avatar_preset(args.get("presetId"), "ai",
                                       True, "agent"), False
        if name == "identity_set_avatar_image":
            return _add_avatar_image(args.get("imageBase64"), "ai",
                                     True, "agent"), False
        if name == "identity_select_avatar":
            return _select_avatar(args.get("id"), "agent"), False
        raise _Err(404, f"未知工具：{name}")
    except _Err as e:
        return {"error": e.message}, True
    except Exception as e:
        _print(f"identity tool {name} unhandled: {e!r}",
               file=sys.stderr)
        return {"error": "服务器内部错误"}, True


# ------------------------------------------------------------ dispatch
# The bridge's HTTP dispatch, transplanted: api_server's wildcard
# mounts hand us (method, path, headers, raw body) with the
# bridge-relative path (query string included) and pass the
# recorded (status, raw, headers) through untouched -- the
# oneday_gateway adapter shape. Auth already happened in
# api_server (@_require_auth, single gateway key).

def _send(status: int, obj) -> tuple:
    raw = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    return status, raw, {
        "Content-Type": "application/json; charset=utf-8",
        "Content-Length": str(len(raw))}


def _send_bytes(status: int, data: bytes, ctype: str) -> tuple:
    return status, data, {
        "Content-Type": ctype,
        "Content-Length": str(len(data))}


def _parse_body(raw: bytes) -> dict:
    if not raw:
        return {}
    return json.loads(raw.decode("utf-8"))


def dispatch(method: str, path: str, headers: dict,
             raw: bytes) -> tuple:
    parsed = urlparse(path)
    parts = [p for p in parsed.path.split("/") if p]
    query = parse_qs(parsed.query)
    try:
        if parts == ["health"]:
            return _send(200, {
                "ok": True, "module": "identity",
                "version": IDENTITY_GATEWAY_VERSION,
                "soulPath": str(SOUL_PATH),
                "avatarDir": str(AVATAR_DIR),
                "traceSink": "oneday" if ONEDAY_CLIENT_KEY
                             else "spill"})
        if parts == ["mcp"]:
            return _dispatch_mcp(method, raw)
        if parts == ["identity", "name"]:
            if method == "GET":
                return _send(200, _get_name())
            # NAME_WRITE_RETIRED_180: POST /identity/name was
            # retired in package 1.8.0 (bridge-retirement batch
            # 1) -- the App writes the name through the Dashboard
            # soul face since then; this HTTP write has no caller
            # and falls through to 404, exactly as the bridge
            # answered. _set_name lives on in-process: the MCP
            # tool identity_set_name calls it directly.
        if parts == ["identity", "avatar"]:
            if method == "GET":
                return _send(200, _get_avatar())
            if method == "POST":
                body = _parse_body(raw)
                actor = body.get("actor") or "app"
                make_current = body.get("makeCurrent", True)
                if body.get("kind") == "preset":
                    return _send(201, _add_avatar_preset(
                        body.get("presetId"),
                        body.get("source") or "ai",
                        make_current, actor))
                return _send(201, _add_avatar_image(
                    body.get("imageBase64"),
                    body.get("source") or "ai",
                    make_current, actor))
        if parts == ["identity", "avatar", "select"]:
            if method == "POST":
                body = _parse_body(raw)
                actor = body.get("actor") or "app"
                return _send(200, _select_avatar(
                    body.get("id"), actor))
        if parts == ["identity", "avatar", "image"]:
            if method == "GET":
                data, ctype = _read_avatar_image(
                    (query.get("id") or [None])[0])
                return _send_bytes(200, data, ctype)
        return _send(404, {"error": "路径不存在"})
    except _Err as e:
        return _send(e.status, {"error": e.message})
    except Exception as e:
        _print(f"unhandled error: {e!r}", file=sys.stderr)
        return _send(500, {"error": "服务器内部错误"})


def _dispatch_mcp(method: str, raw: bytes) -> tuple:
    if method != "POST":
        return _send(405, {"error": "方法不允许"})
    try:
        body = _parse_body(raw)
    except Exception as e:
        return _send(400, {"error": f"请求体不对：{e}"})
    rid = body.get("id")
    method_name = body.get("method", "")
    if rid is None:
        return _send(202, {})
    if method_name == "initialize":
        return _send(200, {
            "jsonrpc": "2.0", "id": rid, "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "oneday-identity",
                               "version": "0.1.0"}}})
    if method_name == "ping":
        return _send(200, {"jsonrpc": "2.0", "id": rid,
                       "result": {}})
    if method_name == "tools/list":
        tools = [{"name": t["name"],
                  "description": t["description"],
                  "inputSchema": t["inputSchema"]}
                 for t in IDENTITY_TOOLS]
        return _send(200, {"jsonrpc": "2.0", "id": rid,
                           "result": {"tools": tools}})
    if method_name == "tools/call":
        params = body.get("params") or {}
        result, is_error = _run_identity_tool(
            params.get("name", ""), params.get("arguments") or {})
        return _send(200, {
            "jsonrpc": "2.0", "id": rid, "result": {
                "content": [{"type": "text", "text": json.dumps(
                    result, ensure_ascii=False)}],
                "isError": is_error}})
    return _send(200, {
        "jsonrpc": "2.0", "id": rid, "error": {
            "code": -32601,
            "message": f"method not found: {method_name}"}})


def start() -> None:
    """Idempotent boot (api_server connect hook): make sure the
    avatar store home exists (the tree itself is carried over at
    rollout; a missing tree simply starts empty, exactly as the
    bridge behaved on first run)."""
    AVATAR_DIR.mkdir(parents=True, exist_ok=True)
