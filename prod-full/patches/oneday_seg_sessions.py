# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_sessions.py -- part of modules/oneday_gateway.py,
# split out by the C-8 single-file split (2026-11-14).
#
# This file is NOT a standalone module and must never be imported:
# oneday_gateway.py exec-loads it in its OWN namespace at this
# segment's original position (see _load_segment there), so every
# name defined here lives in oneday_bridge's globals, in the
# original definition order, sharing the same _db, locks and
# monkeypatch seams the selftests use. Do not add imports of
# oneday_bridge here (that would build a second module instance);
# names from the core head and earlier segments are simply in
# scope, exactly as when this code lived in the single file.
# ---------------------------------------------------------------------




# ------------------------------------------------ AI sessions facade
# P2 会话包 (2026-11-13, AI 内部权限): the agent opens its own side
# chats. The birth certificate is the session id itself: this facade
# mints ids under AI_SESSION_PREFIX through the gateway's
# client-chosen-id contract (the same contract the App's own
# oneday-side- ids ride on), so the mark lives on the sessions
# surface -- queryable by anyone who can list sessions -- and never
# touches message bodies or titles. The rest of the birth (parent
# mainline, minted-at, brief-posted) is recorded in _db["aiSessions"]
# here in the bridge. The App classifier adopts ONLY this prefix
# (SessionClassification R3b); probes and other api_server sessions
# carry no such mark and keep their old buckets.
# Two doors, one core: POST /ai-sessions (REST, for scripts/tests)
# and the /mcp-sessions JSON-RPC facade (sessions_create) for the
# agent. Every creation attempt -- success or failure -- writes
# exactly one P0 trace BEFORE the answer goes out, the same
# discipline as the goals facade, enforced inside
# _create_ai_session_traced so neither door can skip it.
# NOT registered into Hermes: registration (mcp_servers entry +
# gateway route) waits for the closing window; until then this is
# "facade ready, awaiting registration", verified by direct calls.

AI_SESSION_PREFIX = "oneday-ai-"
AI_SESSION_KEEP = 500
AI_SESSION_TITLE_CAP = 120
AI_SESSION_BRIEF_CAP = 20000


def _ai_session_view(rec: dict) -> dict:
    return {
        "id": rec["sessionId"],
        "title": rec["title"],
        "parentSessionId": rec.get("parentSessionId"),
        "createdAt": rec["createdAt"],
        "briefPosted": bool(rec.get("briefPosted")),
        "runId": rec.get("runId"),
        "test": bool(rec.get("test")),
    }


def _ai_session_target(session_id: str, title: str) -> dict:
    return {"kind": "session", "id": session_id, "label": title,
            "ref": f"oneday://sessions/{session_id}" if session_id
                   else "oneday://sessions"}


def _resolve_mainline_session_id():
    """The App's mainline, found through the dashboard search
    surface (the same one the App's conversation manager
    searches through). The plain sessions list cannot be used:
    it is newest-first by started_at and production floods it
    with run_ machine sessions, pushing the mainline out of
    the newest 100 -- and limit>100 is refused (422). Both
    facts verified against production 2026-11-13; the search
    for "oneday-main" returns the mainline as its first hit.
    Read through the ledger's dashboard channel (_ledger_dash):
    the gateway's Bearer API key cannot read session lists at
    all (401, verified the same day). None when the mainline
    cannot be found: the caller fails loudly rather than
    minting an orphan whose parentage cannot be stated."""
    payload = _ledger_dash.get("/api/sessions/search?q=oneday-main")
    if not isinstance(payload, dict):
        return None
    rows = payload.get("results")
    if not isinstance(rows, list):
        return None
    candidates = []
    for s in rows:
        if not isinstance(s, dict) or s.get("archived"):
            continue
        sid = str(s.get("id") or "")
        if not sid.startswith("oneday-main-"):
            continue
        ts = _ledger_norm_ts(s.get("started_at")
                             or s.get("startedAt")
                             or s.get("created_at")) or 0
        candidates.append((ts, sid))
    if not candidates:
        return None
    # Stable sort: on a timestamp tie the search's own order
    # (its first hit is the live mainline) decides.
    candidates.sort(key=lambda c: c[0], reverse=True)
    return candidates[0][1]


def _create_ai_session_core(body: dict) -> dict:
    """Mint one AI side chat end to end; returns its view. Raises
    _Err with the verbatim failure at whichever step breaks (the
    exception carries .session_id once a session exists). A session
    that WAS minted keeps its birth record even when the brief
    submission fails after it -- briefPosted=False on the record
    says so, nothing pretends the deed completed."""
    brief = body.get("taskBrief")
    if not isinstance(brief, str) or not brief.strip():
        raise _Err(400, "taskBrief 不能为空（新旁聊的首帖任务简报）")
    brief = brief.strip()
    if len(brief) > AI_SESSION_BRIEF_CAP:
        raise _Err(400, "taskBrief 太长")
    title = body.get("title")
    if title is not None and not isinstance(title, str):
        raise _Err(400, "title 必须是字符串")
    title = (title or "").strip()[:AI_SESSION_TITLE_CAP]
    if not title:
        # Audit-mandated fallback (P2): the agent should always
        # title its chats; when it does not, the minted title says
        # what the chat is and when it was born.
        title = "AI 任务 · " + datetime.now(_sched_tz()).strftime("%H:%M")
    parent = body.get("parentSessionId")
    if parent is not None and (not isinstance(parent, str)
                               or not parent.strip()):
        raise _Err(400, "parentSessionId 不对")
    if not parent:
        parent = _resolve_mainline_session_id()
    if not parent:
        raise _Err(502, "找不到主线会话（oneday-main-*），"
                        "无法给新旁聊挂父会话，已拒绝创建")
    session_id = AI_SESSION_PREFIX + secrets.token_hex(16)
    status, payload, raw = _http_json(
        HERMES_BASE_URL + "/api/sessions", method="POST",
        body={"id": session_id, "title": title},
        headers={"Authorization": f"Bearer {HERMES_API_KEY}"},
        timeout=30)
    if status not in (200, 201):
        raise _Err(502, f"在 Hermes 建会话失败（HTTP {status}）"
                        f"{raw[:160]}")
    if isinstance(payload, dict) and payload.get("id") \
            and str(payload["id"]) != session_id:
        # The gateway reassigning the id would silently strip the
        # birth certificate (the App adopts by prefix). Refuse
        # loudly instead of shipping an unmarked chat.
        raise _Err(502, f"Hermes 改派了会话 id（{payload['id']}），"
                        "出生证明会失效，已拒绝采用")
    rec = {"sessionId": session_id, "origin": "ai", "title": title,
           "parentSessionId": parent, "createdAt": _now(),
           "briefPosted": False, "runId": None,
           "test": bool(body.get("test"))}
    with _lock:
        _db["aiSessions"].append(rec)
        if len(_db["aiSessions"]) > AI_SESSION_KEEP:
            del _db["aiSessions"][:len(_db["aiSessions"])
                                   - AI_SESSION_KEEP]
        _save_locked()
    status, payload, raw = _http_json(
        HERMES_BASE_URL + "/v1/runs", method="POST",
        body={"input": brief, "session_id": session_id},
        headers={"Authorization": f"Bearer {HERMES_API_KEY}",
                 "Idempotency-Key": f"ai-session-{session_id}"},
        timeout=60)
    run_id = payload.get("run_id") if isinstance(payload, dict) else None
    if status not in (200, 201, 202) or not run_id:
        err = _Err(502, f"会话已建但任务简报提交失败（HTTP {status}）"
                        f"{raw[:160]}")
        err.session_id = session_id
        raise err
    with _lock:
        rec["briefPosted"] = True
        rec["runId"] = run_id
        _save_locked()
    return _ai_session_view(rec)


def _create_ai_session_traced(body: dict) -> dict:
    """Create + trace: exactly one sessions.create trace per
    attempt -- ok with its summary, failed with the verbatim
    error -- written before the answer goes out (P0 discipline,
    shared by the REST door and the MCP facade)."""
    if not isinstance(body, dict):
        body = {}
    title_hint = body.get("title")
    if not isinstance(title_hint, str):
        title_hint = ""
    try:
        view = _create_ai_session_core(body)
    except _Err as e:
        _append_trace(
            "sessions.create",
            _ai_session_target(getattr(e, "session_id", "") or "",
                               title_hint[:AI_SESSION_TITLE_CAP]),
            "failed", error=e.message, detail={"via": "ai-sessions"})
        raise
    except Exception as e:  # trace carries the real failure verbatim
        _print(f"ai session create unhandled: {e!r}",
              file=sys.stderr, flush=True)
        _append_trace(
            "sessions.create",
            _ai_session_target("", title_hint[:AI_SESSION_TITLE_CAP]),
            "failed", error=f"{type(e).__name__}: {e}",
            detail={"via": "ai-sessions"})
        raise _Err(500, "服务器内部错误")
    trace = _append_trace(
        "sessions.create",
        _ai_session_target(view["id"], view["title"]), "ok",
        result=f"已新开旁聊「{view['title']}」并发出任务简报",
        detail={"via": "ai-sessions",
                "parentSessionId": view["parentSessionId"],
                "test": view["test"]})
    return view | {"traceId": trace["id"]}


def _list_ai_sessions(limit_raw) -> list:
    """Birth records, newest first (verification / cleanup door)."""
    if limit_raw is None:
        limit = 50
    else:
        try:
            limit = int(limit_raw)
        except (TypeError, ValueError):
            raise _Err(400, "limit 必须是整数")
    limit = max(1, min(limit, 200))
    with _lock:
        items = [_ai_session_view(r) for r in _db["aiSessions"]]
    items.sort(key=lambda v: v["createdAt"], reverse=True)
    return items[:limit]


SESSION_TOOLS = [
    {
        "name": "sessions_create",
        "description": "新开一个旁聊并把任务简报作为首帖发进去；"
                       "新会话带 AI 出生标记，会出现在用户的旁聊"
                       "列表里，创建动作会留痕回响到主线",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {"type": "string",
                          "description": "旁聊标题；不给则用"
                                         "「AI 任务 · HH:MM」兜底"},
                "taskBrief": {"type": "string",
                              "description": "任务简报，作为新旁聊"
                                             "的首帖发给接手的会话"},
            },
            "required": ["taskBrief"],
        },
    },
]


def _session_tool_call(name: str, args: dict):
    """Execute one sessions tools/call. Returns (result_obj,
    is_error). The trace is written inside _create_ai_session_
    traced for every attempt (P0 discipline), so this layer only
    translates the outcome into MCP shape."""
    if name != "sessions_create":
        _append_trace(
            "sessions." + name.removeprefix("sessions_"),
            _ai_session_target("", ""), "failed",
            error=f"未知工具：{name}", detail={"tool": name})
        return {"error": f"未知工具：{name}"}, True
    try:
        view = _create_ai_session_traced(args or {})
    except _Err as e:
        return {"error": e.message}, True
    return view, False
