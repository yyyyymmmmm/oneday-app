# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_goals_facade.py -- part of modules/oneday_bridge.py,
# split out by the C-8 single-file split (2026-11-14).
#
# This file is NOT a standalone module and must never be imported:
# oneday_bridge.py exec-loads it in its OWN namespace at this
# segment's original position (see _load_segment there), so every
# name defined here lives in oneday_bridge's globals, in the
# original definition order, sharing the same _db, locks and
# monkeypatch seams the selftests use. Do not add imports of
# oneday_bridge here (that would build a second module instance);
# names from the core head and earlier segments are simply in
# scope, exactly as when this code lived in the single file.
# ---------------------------------------------------------------------




# ------------------------------------------------------- goals MCP facade
# P3 目标门面 (2026-11-13): the goals REST surface above has existed
# for the App; what was missing is the MCP facade the agent calls.
# Same streamable-http JSON-RPC shape as the device bridge's /mcp.
# Facade-created goals carry source="chat" (the contract the App
# already renders as conversation-born) and facade-written entries
# carry source="agent". Every tools/call -- success or failure --
# writes one P0 trace BEFORE the answer goes out.
# Registered into Hermes as oneday-goals: the mcp_servers entry
# and gateway route are in place, `hermes mcp list` shows it
# enabled and `hermes mcp test` passes (verified 2026-11-27).
GOAL_TOOLS = [
    {
        "name": "goals_list",
        "description": "列出目标，可按状态过滤",
        "inputSchema": {
            "type": "object",
            "properties": {
                "status": {"type": "string",
                           "enum": ["active", "completed"]},
            },
        },
    },
    {
        "name": "goals_create",
        "description": "新建一个目标（来源记为 chat）",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "note": {"type": "string"},
                "category": {"type": "string"},
                "parentId": {"type": "string"},
            },
            "required": ["title"],
        },
    },
    {
        "name": "goals_add_entry",
        "description": "给目标写一条进展（来源记为 agent；title 可选，"
                       "是条目的分层标题；origin 可选，记来源出处，"
                       "后台提炼记账传 bookkeeping——同目标同日只许一条）",
        "inputSchema": {
            "type": "object",
            "properties": {
                "goalId": {"type": "string"},
                "body": {"type": "string"},
                "title": {"type": "string"},
                "origin": {"type": "string"},
            },
            "required": ["goalId", "body"],
        },
    },
    {
        "name": "goals_update",
        "description": "更新目标的标题、备注或状态",
        "inputSchema": {
            "type": "object",
            "properties": {
                "goalId": {"type": "string"},
                "title": {"type": "string"},
                "note": {"type": "string"},
                "status": {"type": "string",
                           "enum": ["active", "completed"]},
            },
            "required": ["goalId"],
        },
    },
]


def _goal_target(goal_id: str, label: str) -> dict:
    return {"kind": "goal", "id": goal_id, "label": label,
            "ref": f"oneday://goals/{goal_id}" if goal_id else
                   "oneday://goals"}


def _run_goal_tool(name: str, args: dict):
    """Run one goals tool; returns (result_obj, target, summary).
    Raises _Err with the verbatim failure on any refusal.
    Caller holds no lock; each branch takes it."""
    if name == "goals_list":
        with _lock:
            items = _list_goals()
        status = args.get("status")
        if status:
            items = [g for g in items if g["status"] == status]
        target = {"kind": "goals", "id": "", "label": "目标列表",
                  "ref": "oneday://goals"}
        return {"items": items}, target, f"列出 {len(items)} 个目标"
    if name == "goals_create":
        body = {"title": args.get("title"), "source": "chat"}
        for key in ("note", "category", "parentId"):
            if args.get(key) is not None:
                body[key] = args[key]
        with _lock:
            view = _create_goal(body)
        return view, _goal_target(view["id"], view["title"]), \
            f"已创建目标「{view['title']}」"
    if name == "goals_add_entry":
        gid = args.get("goalId")
        if not isinstance(gid, str) or not gid:
            raise _Err(400, "goalId 不能为空")
        payload = {"body": args.get("body"), "source": "agent"}
        for key in ("title", "origin"):
            if args.get(key) is not None:
                payload[key] = args[key]
        with _lock:
            view = _create_entry(gid, payload)
            label = _find_goal(gid)["title"]
        return view, _goal_target(gid, label), \
            f"已给目标「{label}」写入一条进展"
    if name == "goals_update":
        gid = args.get("goalId")
        if not isinstance(gid, str) or not gid:
            raise _Err(400, "goalId 不能为空")
        body = {k: args[k] for k in ("title", "note", "status")
                if args.get(k) is not None}
        with _lock:
            view = _patch_goal(gid, body)
        return view, _goal_target(view["id"], view["title"]), \
            f"已更新目标「{view['title']}」"
    raise _Err(404, f"未知工具：{name}")


def _goal_tool_call(name: str, args: dict):
    """Execute + trace one goals tools/call. Returns (result_obj,
    is_error). The trace is written for EVERY call: ok with its
    result summary, failed with the error text verbatim."""
    action = "goals." + name.removeprefix("goals_")
    try:
        result, target, summary = _run_goal_tool(name, args)
    except _Err as e:
        target = {"kind": "goal",
                  "id": args.get("goalId") or "",
                  "label": args.get("title") or "",
                  "ref": "oneday://goals"}
        _append_trace(action, target, "failed", error=e.message,
                      detail={"tool": name})
        return {"error": e.message}, True
    except Exception as e:  # trace carries the real failure verbatim
        print(f"goals tool {name} unhandled: {e!r}",
              file=sys.stderr, flush=True)
        target = {"kind": "goal",
                  "id": args.get("goalId") or "",
                  "label": args.get("title") or "",
                  "ref": "oneday://goals"}
        _append_trace(action, target, "failed",
                      error=f"{type(e).__name__}: {e}",
                      detail={"tool": name})
        return {"error": "服务器内部错误"}, True
    _append_trace(action, target, "ok", result=summary,
                  detail={"tool": name})
    return result, False
