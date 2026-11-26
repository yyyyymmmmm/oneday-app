#!/usr/bin/env python3
# ⚠ 归档标注（2026-11-14，桥-3）：本文件是 2026-11-09 独立部署时代的
# 旧源副本，不在役（在役模块为 companion/modules/box_bridge.py，且已
# 定整模块退役、front 已解耦直连 Simular MCP）。勿据此文件判断现状，
# 防普查误读；在役口径见 oneday-design-review/bridge-23-retire-prep。
"""box-bridge: Simular Box browser/desktop capability as OneDay-consumable HTTP.

Sidecar #4 (after write-gate 8643, overview 8644). Binds 127.0.0.1:8645,
nginx exposes it at https://hermes.example.com/api/box-bridge/ -> /box/.

Design notes (from 2026-11-09 live probes, see box-bridge-rollout record):
- Box is reached DIRECTLY over MCP streamable-http at
  https://mcp.box.simular.ai/mcp with Authorization: Bearer <MCP_BOX_API_KEY>
  (same key Hermes uses, plugin mcp.json). No Hermes process involved.
- The Chrome window is bound to the MCP session AND to the official SDK
  client's persistent connection: a hand-rolled urllib client loses the
  window between calls (browser_snapshot: "no Chrome window open"), while
  the mcp SDK client keeps it. So this bridge holds ONE long-lived SDK
  ClientSession on a dedicated event-loop thread and serializes all tool
  calls through it. If the session dies it is re-created lazily; the
  browser window then resets (page becomes null) - documented behavior.
- The desktop is shared/single (the agent's Hermes session is a different
  MCP session with its own Chrome window; screenshots and computer_act
  act on the one shared desktop). Takeover mutual-exclusion is a product
  layer convention (build-program SS4.3), not enforced here.

Auth: single Bearer, this bridge's own scoped key (BOX_BRIDGE_KEY env;
per-bridge keys since the 2026-11-10 F03 rotation).
Fail-closed: refuses to start when either key is missing.
"""
import asyncio
import base64
import hmac
import json
import mimetypes
import os
import re
import struct
import sys
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

API_KEY = os.environ.get("BOX_BRIDGE_KEY", "")
BOX_KEY = os.environ.get("MCP_BOX_API_KEY", "")
PORT = int(os.environ.get("BOX_PORT", "8645"))
MCP_URL = os.environ.get("BOX_MCP_URL", "https://mcp.box.simular.ai/mcp")


def now_iso():
    return datetime.now(timezone.utc).isoformat()


# ---------------------------------------------------------------- MCP worker

class BoxMCP:
    """One long-lived MCP ClientSession on its own event-loop thread."""

    def __init__(self):
        self.loop = asyncio.new_event_loop()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.session = None
        self._cm_http = None
        self._cm_sess = None
        self._lock = None
        self.ready = threading.Event()
        self.last_state = None
        self.last_state_at = 0.0

    def start(self):
        self.thread.start()
        self.ready.wait(timeout=30)

    def _run(self):
        asyncio.set_event_loop(self.loop)
        self._lock = asyncio.Lock()
        try:
            self.loop.run_until_complete(self._connect())
        except Exception as e:  # lazy reconnect on first call instead
            print(f"[box-bridge] initial MCP connect failed: {e}", flush=True)
        self.ready.set()
        self.loop.run_forever()

    async def _connect(self):
        from mcp import ClientSession
        from mcp.client.streamable_http import (
            create_mcp_http_client,
            streamable_http_client,
        )
        http_client = create_mcp_http_client(
            headers={"Authorization": "Bearer " + BOX_KEY})
        self._cm_http = streamable_http_client(MCP_URL, http_client=http_client)
        read, write = await self._cm_http.__aenter__()
        self._cm_sess = ClientSession(read, write)
        self.session = await self._cm_sess.__aenter__()
        await self.session.initialize()
        print("[box-bridge] MCP session up", flush=True)

    async def _disconnect(self):
        for cm in (self._cm_sess, self._cm_http):
            try:
                if cm is not None:
                    await cm.__aexit__(None, None, None)
            except Exception:
                pass
        self._cm_sess = None
        self._cm_http = None
        self.session = None

    async def _call(self, name, args, timeout):
        async with self._lock:
            last_err = None
            for _ in range(2):
                try:
                    if self.session is None:
                        await self._connect()
                    return await asyncio.wait_for(
                        self.session.call_tool(name, args), timeout)
                except Exception as e:
                    last_err = e
                    await self._disconnect()
            raise RuntimeError(f"MCP call {name} failed: {last_err}")

    def call(self, name, args, timeout=60):
        fut = asyncio.run_coroutine_threadsafe(
            self._call(name, args, timeout), self.loop)
        return fut.result(timeout + 20)

    def ensure_running(self):
        """box_ensure if the box is not running (state cached 20s)."""
        import time
        if self.last_state == "running" and time.time() - self.last_state_at < 20:
            return
        st = tool_structured(self.call("box_status", {}, timeout=30))
        self._note_state(st)
        if not st or st.get("state") != "running":
            tool_result_or_raise(self.call("box_ensure", {"wait": True}, timeout=90))
            self.last_state = "running"
            self.last_state_at = time.time()

    def _note_state(self, st):
        import time
        if st and st.get("state"):
            self.last_state = st["state"]
            self.last_state_at = time.time()


MCP = BoxMCP()


# ------------------------------------------------------------- result parsing

def tool_texts(result):
    out = []
    for c in getattr(result, "content", []) or []:
        if getattr(c, "type", None) == "text":
            out.append(c.text)
    return out


def tool_structured(result):
    sc = getattr(result, "structured_content", None)
    if sc is None:
        sc = getattr(result, "structuredContent", None)
    if isinstance(sc, dict):
        return sc
    for t in tool_texts(result):
        try:
            v = json.loads(t)
            if isinstance(v, dict):
                return v
        except Exception:
            pass
    return None


def tool_error_text(result):
    texts = tool_texts(result)
    return (texts[0][:400] if texts else "tool error")


def tool_result_or_raise(result, tool="tool"):
    if getattr(result, "is_error", False):
        raise ToolError(tool, tool_error_text(result))
    return result


class ToolError(Exception):
    def __init__(self, tool, detail):
        super().__init__(detail)
        self.tool = tool
        self.detail = detail


def image_dims(raw):
    """(width, height) from PNG/JPEG bytes, or (None, None)."""
    try:
        if raw[:8] == b"\x89PNG\r\n\x1a\n":
            w, h = struct.unpack(">II", raw[16:24])
            return w, h
        if raw[:2] == b"\xff\xd8":
            i = 2
            while i + 9 < len(raw):
                if raw[i] != 0xFF:
                    i += 1
                    continue
                marker = raw[i + 1]
                if marker in (0xC0, 0xC1, 0xC2):
                    h, w = struct.unpack(">HH", raw[i + 5:i + 9])
                    return w, h
                seglen = struct.unpack(">H", raw[i + 2:i + 4])[0]
                i += 2 + seglen
    except Exception:
        pass
    return None, None


def extract_screenshot(result):
    """Pull the image block out of a screenshot/computer_act result."""
    for c in getattr(result, "content", []) or []:
        if getattr(c, "type", None) == "image":
            raw = base64.b64decode(c.data)
            w, h = image_dims(raw)
            if w is None:  # fall back to the tool's own size line
                for t in tool_texts(result):
                    m = re.search(r"(\d+)x(\d+)", t)
                    if m:
                        w, h = int(m.group(1)), int(m.group(2))
                        break
            mime = (getattr(c, "mime_type", None)
                    or getattr(c, "mimeType", None)
                    or "image/jpeg")
            return {
                "mime": mime,
                "width": w,
                "height": h,
                "bytes": len(raw),
                "imageBase64": c.data,
                "capturedAt": now_iso(),
            }
    return None


PAGE_RE = re.compile(r"^Page:\s*(.*?)\s*\((https?://[^)]+)\)\s*$", re.M)


def parse_page(result):
    for t in tool_texts(result):
        m = PAGE_RE.search(t)
        if m:
            return {"title": m.group(1), "url": m.group(2)}
    return None


def first_line(result, limit=300):
    texts = tool_texts(result)
    if not texts:
        return ""
    return texts[0].splitlines()[0][:limit] if texts[0] else ""


# ------------------------------------------------------------------ handlers

# The vendor's browser-automation binding lapses quickly after a
# navigate (snapshot then reports "no Chrome window open") even though
# the page stays visible on the desktop. Keep the last page this bridge
# positively confirmed (via a navigate result or a live snapshot) so the
# status can report it, clearly labeled, next to the live read.
LAST_PAGE = {"page": None, "at": None}


def note_page(page):
    if page:
        LAST_PAGE["page"] = page
        LAST_PAGE["at"] = now_iso()


def get_status():
    res = tool_result_or_raise(MCP.call("box_status", {}, timeout=30), "box_status")
    st = tool_structured(res) or {}
    MCP._note_state(st)
    out = {
        "state": st.get("state"),
        "name": st.get("name"),
        "boxId": st.get("box_id"),
        "image": st.get("image"),
        "latestImage": st.get("latest_image"),
        "upgradeAvailable": st.get("upgrade_available"),
        "lastSavedAtMs": st.get("last_saved_at_ms"),
        "viewUrl": st.get("view_url"),
        "creditsLeft": None,
        "creditsNote": None,
        "page": None,
        "checkedAt": now_iso(),
    }
    # billing: on this plan it errors with "box plans are not enabled";
    # surface that honestly instead of inventing a credit figure.
    try:
        bres = MCP.call("billing", {}, timeout=20)
        if getattr(bres, "is_error", False):
            out["creditsNote"] = tool_error_text(bres)
        else:
            bs = tool_structured(bres) or {}
            for k in ("credits_left", "creditsLeft", "credits", "balance"):
                if isinstance(bs.get(k), (int, float)):
                    out["creditsLeft"] = bs[k]
                    break
            if out["creditsLeft"] is None:
                out["creditsNote"] = "no credit figure in billing response"
    except Exception as e:
        out["creditsNote"] = f"billing unavailable: {e}"[:200]
    # current page of THIS bridge session's Chrome window (desktop is
    # shared; the agent's own window is a different MCP session).
    # Observed live: a snapshot read can intermittently come back without
    # a page line (fast empty/error), so retry once before reporting null.
    if out["state"] == "running":
        import time as _time
        for attempt in (1, 2):
            try:
                snap = MCP.call("browser_snapshot", {}, timeout=30)
                if getattr(snap, "is_error", False):
                    print(f"[box-bridge] snapshot attempt {attempt} is_error: "
                          f"{tool_error_text(snap)[:120]}", file=sys.stderr)
                else:
                    out["page"] = parse_page(snap)
                    if out["page"] is not None:
                        note_page(out["page"])
                        break
                    print(f"[box-bridge] snapshot attempt {attempt}: "
                          f"no page line", file=sys.stderr)
            except Exception as e:
                print(f"[box-bridge] snapshot attempt {attempt} failed: "
                      f"{type(e).__name__}", file=sys.stderr)
                out["page"] = None
            if attempt == 1:
                _time.sleep(0.9)
    out["lastKnownPage"] = LAST_PAGE["page"]
    out["lastKnownPageAt"] = LAST_PAGE["at"]
    return out


def post_screenshot(body):
    max_edge = body.get("maxEdge") or body.get("max_edge") or 1024
    MCP.ensure_running()
    res = tool_result_or_raise(
        MCP.call("screenshot", {"max_edge": int(max_edge)}, timeout=60),
        "screenshot")
    shot = extract_screenshot(res)
    if shot is None:
        raise ToolError("screenshot", "no image block in result")
    return shot


ACT_DESKTOP = {
    "click", "double_click", "right_click", "triple_click", "type", "key",
    "hotkey", "scroll", "drag", "wait", "launch_app", "locate",
}
ACT_FIELDS = {
    "element", "x", "y", "to_x", "to_y", "text", "key", "keys", "direction",
    "amount", "button", "app", "seconds", "foreground", "target", "max_edge",
}


def post_act(body):
    action = body.get("action")
    if not action or not isinstance(action, str):
        raise ValueError("missing action")
    MCP.ensure_running()
    if action == "navigate":
        url = body.get("url") or ""
        if not re.match(r"^https?://", url):
            raise ValueError("navigate requires an http(s) url")
        args = {"url": url, "front": bool(body.get("front", True))}
        res = tool_result_or_raise(
            MCP.call("browser_navigate", args, timeout=60), "browser_navigate")
        shot = extract_screenshot(res) or post_screenshot({})
        nav_page = parse_page(res)
        note_page(nav_page)
        return {
            "ok": True,
            "action": "navigate",
            "tool": "browser_navigate",
            "page": nav_page,
            "summary": first_line(res),
            "screenshot": shot,
        }
    if action in ACT_DESKTOP:
        args = {"action": action}
        for k in ACT_FIELDS:
            if k in body:
                args[k] = body[k]
        res = tool_result_or_raise(
            MCP.call("computer_act", args, timeout=90), "computer_act")
        shot = extract_screenshot(res) or post_screenshot({})
        return {
            "ok": True,
            "action": action,
            "tool": "computer_act",
            "summary": first_line(res),
            "screenshot": shot,
        }
    raise ValueError(f"unsupported action: {action}")


# ------------------------------------------------------------- shell (exec)

# Terminal face over the vendor's persistent `shell` tool (contract:
# oneday-design-review/box-shell-contract-20261109.md). The command is
# the user's own, typed in the App and passed through verbatim - the
# bridge adds nothing, rewrites nothing and filters nothing; the
# execution domain is the Box sandbox, never the host shell. The
# vendor result is a text block whose tail carries an
# "[exit status N]" trailer (same shape the files face already parses
# in _read_file_bytes_shell); the trailer is stripped and surfaced as
# exitCode. Output is capped bridge-side; truncation is flagged and
# noted inside the output itself, never silent.
SHELL_TIMEOUT = 90
SHELL_OUTPUT_LIMIT = 32768
EXIT_STATUS_RE = re.compile(r"\[exit status (-?\d+)\]\s*$")


def post_shell(body):
    command = body.get("command")
    if not isinstance(command, str) or not command.strip():
        raise ValueError("command is required")
    MCP.ensure_running()
    try:
        res = MCP.call("shell", {"command": command}, timeout=SHELL_TIMEOUT)
    except Exception as e:
        if "timeout" in (type(e).__name__ + str(e)).lower():
            raise HttpError(504, {"error": "shell_timeout",
                                  "detail": "command timed out"})
        raise ToolError("shell", str(e)[:300])
    texts = tool_texts(res)
    text = texts[0] if len(texts) == 1 else "\n".join(texts)
    exit_code = None
    m = EXIT_STATUS_RE.search(text)
    if m:
        exit_code = int(m.group(1))
        text = text[:m.start()]
        if text.endswith("\n"):
            text = text[:-1]  # separator newline before the trailer
    elif getattr(res, "is_error", False):
        # Vendor-side failure with no exit status to report: 502 with
        # the vendor's own words, per contract SS3.
        raise ToolError("shell", tool_error_text(res))
    truncated = False
    if len(text) > SHELL_OUTPUT_LIMIT:
        text = (text[:SHELL_OUTPUT_LIMIT]
                + f"\n[box-bridge: output truncated at "
                  f"{SHELL_OUTPUT_LIMIT} characters]")
        truncated = True
    return {
        "ok": exit_code == 0 if exit_code is not None else True,
        "output": text,
        "exitCode": exit_code,
        "truncated": truncated,
    }


def get_view_token():
    res = tool_result_or_raise(
        MCP.call("box_view_token", {}, timeout=30), "box_view_token")
    parsed = tool_structured(res)
    st = tool_structured(tool_result_or_raise(
        MCP.call("box_status", {}, timeout=30), "box_status")) or {}
    return {
        "view": parsed if parsed is not None else (
            tool_texts(res)[0] if tool_texts(res) else None),
        "viewUrl": st.get("view_url"),
        "fetchedAt": now_iso(),
    }


# ------------------------------------------------------------- files (read)

# Read-only file face over the vendor's list_dir / read_file tools
# (contract: oneday-design-review/box-files-contract-20261109.md).
# Vendor shapes, probed live 2026-11-09:
# - list_dir works while the box hibernates and returns plain text:
#   a header line "<abspath>:" then one line per entry - "name/" for
#   directories, "name  (N bytes)" for files. No mtime is exposed, so
#   entries report mtime=null rather than inventing one.
# - read_file returns text with a "%6d\t" line-number prefix per line,
#   hard-capped at 2000 lines per call ("[showing lines ...]" trailer),
#   truncates lines over 2000 chars (" [line cut: ...]"), reports empty
#   or past-end reads as "<abspath> has N lines; nothing at offset M",
#   and binary files as "<abspath> is a binary file of N bytes".
#   Text is reassembled by paging offsets and stripping prefixes; when
#   the vendor text would be lossy (binary marker or a cut line) the
#   bridge falls back to base64 via shell for exact bytes - that call
#   wakes the box, same as screenshot/act already do.
WORKSPACE_ROOT = "/workspace"
MAX_LIST_ENTRIES = 500
MAX_READ_BYTES = 16 * 1024 * 1024
MAX_SHELL_READ_BYTES = 8 * 1024 * 1024
READ_PAGE_LINES = 2000
MAX_READ_LINES = 200000


class HttpError(Exception):
    def __init__(self, code, payload):
        super().__init__(payload.get("error", "error"))
        self.code = code
        self.payload = payload


def clean_rel_path(raw, allow_empty=True):
    """Validate a client-supplied path as relative to /workspace.

    Absolute paths, backslashes, NULs and any empty/dot/dotdot segment
    are rejected (ValueError -> 400) before anything reaches the vendor
    tools, per contract SS3.
    """
    if raw is None:
        raw = ""
    p = raw.strip()
    while p.endswith("/"):
        p = p[:-1]
    if p == "":
        if allow_empty:
            return ""
        raise ValueError("path is required")
    if p.startswith("/") or "\\" in p or "\x00" in p:
        raise ValueError("path must be relative to the workspace")
    parts = p.split("/")
    for seg in parts:
        if seg in ("", ".", ".."):
            raise ValueError("path escapes the workspace")
    return "/".join(parts)


SIZE_SUFFIX_RE = re.compile(r"^(.*)  \((\d+) bytes\)$")


def get_files(raw_path):
    rel = clean_rel_path(raw_path)
    abspath = WORKSPACE_ROOT + ("/" + rel if rel else "")
    try:
        res = tool_result_or_raise(
            MCP.call("list_dir", {"path": abspath}, timeout=60), "list_dir")
    except ToolError as e:
        if "No such file or directory" in e.detail:
            raise HttpError(404, {"error": "not_found", "detail": e.detail})
        raise
    texts = tool_texts(res)
    text = texts[0] if texts else ""
    lines = text.split("\n")
    header = lines[0] if lines else ""
    if not header.endswith(":"):
        raise ToolError("list_dir", "unexpected list_dir output")
    resolved = header[:-1]
    if resolved == WORKSPACE_ROOT + "/.":
        resolved = WORKSPACE_ROOT
    if not (resolved == WORKSPACE_ROOT
            or resolved.startswith(WORKSPACE_ROOT + "/")):
        # A symlink inside the workspace resolved outside it.
        raise ValueError("path escapes the workspace")
    entries = []
    truncated = False
    for line in lines[1:]:
        if not line:
            continue
        if line.endswith("/"):
            name, is_dir, size = line[:-1], True, None
        else:
            m = SIZE_SUFFIX_RE.match(line)
            if m:
                name, size = m.group(1), int(m.group(2))
            else:
                name, size = line, None
            is_dir = False
        if name in (".", ".."):
            continue
        if len(entries) >= MAX_LIST_ENTRIES:
            truncated = True
            break
        entries.append({
            "name": name,
            "path": (rel + "/" + name) if rel else name,
            "is_directory": is_dir,
            "size": size,
            "mtime": None,
            "mime_type": None if is_dir else mimetypes.guess_type(name)[0],
        })
    parent = None
    if rel:
        parent = rel.rsplit("/", 1)[0] if "/" in rel else ""
    out = {
        "path": rel,
        "parent": parent,
        "root": WORKSPACE_ROOT,
        "locked_root": WORKSPACE_ROOT,
        "can_change_path": False,
        "entries": entries,
    }
    if truncated:
        out["truncated"] = True
    return out


NOTHING_RE = re.compile(r" has \d+ lines; nothing at offset \d+$")
BINARY_RE = re.compile(r" is a binary file of \d+ bytes$")
LINE_PREFIX_RE = re.compile(r"^\s*\d+\t")
LINE_CUT_RE = re.compile(r" \[line cut: \d+ of \d+ characters shown\]$")
SHOWING_RE = re.compile(r"^\[showing lines \d+-\d+; pass offset to read more\]$")


def _read_file_lines(abspath):
    """Page read_file and strip its line-number prefixes.

    Returns the file's lines, or None when the vendor says the file is
    binary. Raises HttpError(404) / ValueError / ToolError otherwise.
    A trailing newline in the original is not recoverable from the
    vendor's line view and is dropped - documented in the rollout.
    """
    lines = []
    total_chars = 0
    offset = 1
    while True:
        res = MCP.call("read_file", {
            "path": abspath, "offset": offset, "limit": READ_PAGE_LINES,
        }, timeout=60)
        if getattr(res, "is_error", False):
            detail = tool_error_text(res)
            if "No such file or directory" in detail:
                raise HttpError(404, {"error": "not_found", "detail": detail})
            if "Is a directory" in detail:
                raise ValueError("path is a directory")
            raise ToolError("read_file", detail)
        texts = tool_texts(res)
        text = texts[0] if texts else ""
        body = text.rstrip("\n")
        if "\n" not in body and NOTHING_RE.search(body):
            break  # empty file, or offset landed exactly at EOF
        if offset == 1 and "\n" not in body and BINARY_RE.search(body):
            return None
        raw_lines = body.split("\n") if body else []
        more = False
        if raw_lines and SHOWING_RE.match(raw_lines[-1]):
            more = True
            raw_lines.pop()
        for rl in raw_lines:
            m = LINE_PREFIX_RE.match(rl)
            if not m:
                raise ToolError("read_file",
                                "unexpected read_file output format")
            content = rl[m.end():]
            lines.append(content)
            total_chars += len(content)
        if len(lines) > MAX_READ_LINES or total_chars > MAX_READ_BYTES:
            raise ToolError("read_file", "file too large for read endpoint")
        if not more and len(raw_lines) < READ_PAGE_LINES:
            break
        offset += READ_PAGE_LINES
    return lines


def _read_file_bytes_shell(abspath):
    """Exact bytes via base64 in the box shell (wakes the box)."""
    q = "'" + abspath.replace("'", "'\\''") + "'"
    cmd = (f"s=$(stat -c %s -- {q}); "
           f"if [ \"$s\" -gt {MAX_SHELL_READ_BYTES} ]; "
           f"then echo __TOOBIG__ $s; "
           f"else base64 -w 0 -- {q}; fi")
    res = MCP.call("shell", {"command": cmd}, timeout=120)
    if getattr(res, "is_error", False):
        raise ToolError("shell", tool_error_text(res))
    texts = tool_texts(res)
    text = texts[0] if texts else ""
    m = re.search(r"\n?\[exit status (\d+)\]\s*$", text)
    if not m or m.group(1) != "0":
        if "No such file" in text:
            raise HttpError(404, {"error": "not_found",
                                  "detail": text[:200]})
        raise ToolError("shell", "shell read failed: " + text[:200])
    body = text[:m.start()].strip()
    if body.startswith("__TOOBIG__"):
        raise ToolError(
            "shell",
            f"file too large for read endpoint ({body.split()[-1]} bytes)")
    try:
        return base64.b64decode(body, validate=True)
    except Exception:
        raise ToolError("shell", "base64 decode failed")


def get_file_bytes(raw_path):
    rel = clean_rel_path(raw_path, allow_empty=False)
    abspath = WORKSPACE_ROOT + "/" + rel
    lines = _read_file_lines(abspath)
    if lines is None or any(LINE_CUT_RE.search(l) for l in lines):
        raw = _read_file_bytes_shell(abspath)
    else:
        raw = "\n".join(lines).encode("utf-8")
    ctype = mimetypes.guess_type(rel)[0] or "application/octet-stream"
    return ctype, raw


# ------------------------------------------------------------------ HTTP API

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quieter logs
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _auth(self):
        header = self.headers.get("Authorization", "")
        return bool(API_KEY) and hmac.compare_digest(
            header, f"Bearer {API_KEY}")

    def _send(self, code, payload):
        if isinstance(payload, tuple) and payload and payload[0] == "raw":
            _, ctype, data = payload
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        data = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _read_body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return {}

    def _dispatch(self, method):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = parse_qs(parsed.query)
        if path == "/health":
            return 200, {"ok": True, "service": "box-bridge",
                         "mcpSession": "up" if MCP.session else "down"}
        if not path.startswith("/box/"):
            return 404, {"error": "not_found", "path": path}
        if not self._auth():
            return 401, {"error": "unauthorized"}
        try:
            if method == "GET" and path == "/box/status":
                return 200, get_status()
            if method == "GET" and path == "/box/view-token":
                return 200, get_view_token()
            if method == "GET" and path == "/box/files":
                return 200, get_files(query.get("path", [None])[0])
            if method == "GET" and path == "/box/files/read":
                ctype, raw = get_file_bytes(query.get("path", [None])[0])
                return 200, ("raw", ctype, raw)
            if method == "POST" and path == "/box/screenshot":
                return 200, post_screenshot(self._read_body())
            if method == "POST" and path == "/box/act":
                return 200, post_act(self._read_body())
            if method == "POST" and path == "/box/shell":
                return 200, post_shell(self._read_body())
            return 404, {"error": "not_found", "path": path}
        except HttpError as e:
            return e.code, e.payload
        except ValueError as e:
            return 400, {"error": "bad_request", "detail": str(e)}
        except ToolError as e:
            return 502, {"error": "box_tool_error", "tool": e.tool,
                         "detail": e.detail}
        except Exception as e:
            return 503, {"error": "mcp_unavailable", "detail": str(e)[:300]}

    def do_GET(self):
        code, payload = self._dispatch("GET")
        self._send(code, payload)

    def do_POST(self):
        code, payload = self._dispatch("POST")
        self._send(code, payload)


def main():
    if not API_KEY:
        print("BOX_BRIDGE_KEY missing - refusing to start", flush=True)
        sys.exit(1)
    if not BOX_KEY:
        print("MCP_BOX_API_KEY missing - refusing to start", flush=True)
        sys.exit(1)
    MCP.start()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[box-bridge] listening on :{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
