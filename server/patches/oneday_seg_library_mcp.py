# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_library_mcp.py -- part of
# modules/oneday_gateway.py, split out by the C-8 single-file split
# (2026-11-14).
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

# ------------------------------------------------------------------
# Library MCP facade (1.0.73): the agent-side read door for the
# file library. The App's file page reads GET /file-library,
# i.e. _file_library_view in the filelibrary segment; until now
# the agent had NO tool that could reach that surface -- asked
# "what is new in the library" it could only walk /opt/data with
# the generic file tools, which cannot reproduce the admission
# set (roots, admission, dedupe, source labels all live
# server-side) and answered with raw filesystem counts instead
# (probe report deliverables-agent-access-probe-20261124.md).
# This facade is the fourth MCP facade of this bridge, same
# shape as goals / sessions / automation: same process, same
# port, same bridge key, same nginx prefix. It carries exactly
# one read-only tool whose implementation is a direct call of
# _file_library_view -- the same function, the same admitted
# set, one source of truth; no second walk is written here.
# ------------------------------------------------------------------

LIBRARY_TOOLS = [
    {
        "name": "library_list",
        "description": "列出资源库（App 文件页）里的交付物：与 App "
                       "资源库页同一份聚合集（同一准入、去重、"
                       "mtime 倒序），只读。给 since（unix 秒）时"
                       "只回该时刻起的条目并带 sinceCount；"
                       "limit/offset 分页，total 恒为全集总数。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "since": {"type": "number",
                          "description": "unix 秒；只返回 mtime "
                                         "不早于此值的条目"},
                "limit": {"type": "integer",
                          "description": "最多返回条数；不给＝全部"},
                "offset": {"type": "integer",
                           "description": "跳过前 N 条，默认 0"},
            },
        },
    },
]


def _library_int_arg(args: dict, key: str, default):
    """Integer argument with the REST face's door discipline
    (int() coercion, bool refused, garbage is a 400)."""
    raw = args.get(key, default)
    if raw is None:
        return None
    if isinstance(raw, bool):
        raise _Err(400, f"{key} 必须是整数")
    try:
        return int(raw)
    except (TypeError, ValueError):
        raise _Err(400, f"{key} 必须是整数")


def _library_list(args: dict) -> dict:
    """library_list implementation. Without since this IS
    _file_library_view(offset, limit), returned untouched.
    With since, the full view is taken once and filtered on
    mtime in this layer; total stays the whole admitted
    count and sinceCount reports the filtered size, so the
    caller can answer both "how many in total" and "how
    many since T" off one call."""
    offset = _library_int_arg(args, "offset", 0)
    if offset < 0:
        raise _Err(400, "offset 不得为负")
    limit = _library_int_arg(args, "limit", None)
    if limit is not None and limit < 0:
        raise _Err(400, "limit 不得为负")
    since = args.get("since")
    if since is None:
        return _file_library_view(offset, limit)
    if isinstance(since, bool):
        raise _Err(400, "since 必须是 unix 秒数")
    try:
        since = float(since)
    except (TypeError, ValueError):
        raise _Err(400, "since 必须是 unix 秒数")
    full = _file_library_view(0, None)
    fresh = [i for i in full["items"]
             if (i.get("mtime") or 0) >= since]
    if limit is None:
        page = fresh[offset:]
    else:
        page = fresh[offset:offset + limit]
    return {"items": page, "total": full["total"],
            "sinceCount": len(fresh), "since": since,
            "offset": offset, "limit": limit,
            "truncated": False}


def _library_tool_call(name: str, args: dict):
    """Execute + trace one library tools/call. Returns
    (result_obj, is_error). The surface is read-only; the
    only write is the P0 trace itself, the same discipline
    as the goals / sessions / automation facades: every
    call, success or failure, books exactly one trace."""
    action = "library." + name.removeprefix("library_")
    target = {"kind": "library", "id": "",
              "label": "资源库", "ref": "oneday://library"}
    if name != "library_list":
        _append_trace(action, target, "failed",
                      error=f"未知工具：{name}",
                      detail={"tool": name})
        return {"error": f"未知工具：{name}"}, True
    try:
        view = _library_list(args or {})
    except _Err as e:
        _append_trace(action, target, "failed", error=e.message,
                      detail={"tool": name})
        return {"error": e.message}, True
    except Exception as e:  # trace carries the real failure
        _print(f"library tool {name} unhandled: {e!r}",
              file=sys.stderr, flush=True)
        _append_trace(action, target, "failed",
                      error=f"{type(e).__name__}: {e}",
                      detail={"tool": name})
        return {"error": "服务器内部错误"}, True
    summary = (f"资源库共 {view['total']} 条，"
               f"本次返回 {len(view['items'])} 条")
    if view.get("sinceCount") is not None:
        summary += f"，since 之后 {view['sinceCount']} 条"
    _append_trace(action, target, "ok", result=summary,
                  detail={"tool": name})
    return view, False
