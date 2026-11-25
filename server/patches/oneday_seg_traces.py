# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_traces.py -- part of modules/oneday_gateway.py,
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




# ---------------------------------------------------------------- traces
# P0 留痕底座 (AI internal powers, 2026-11-13): the server-side home
# of the "resident, not guest" house rule -- every autonomous in-app
# action the agent takes leaves one append-only trace record here,
# so the user can afterwards see what was done, when, and how it
# ended, and pick the thread back up. A record carries the five
# echo elements:
#   action  -- what was done (namespaced name, e.g. "goals.create")
#   target  -- the object it landed on, pointable:
#              {kind, id, label, ref} (ref is a deep-link string the
#              App can resolve later; kind/id alone always suffice)
#   at      -- when (epoch seconds, this bridge's house format)
#   result  -- how it ended, a short human summary (ok records)
#   error   -- the failure text VERBATIM (failed records); a failed
#              record without error text is refused at the door --
#              failures are first-class records, never dropped.
# Later packages (P1 identity / P2 sessions / P4 automation /
# P5 reach-out) write through POST /traces or _append_trace with
# their own action namespaces; the contract does not change.
#: Soft retention cap: the log is a JSON-file store, so appends trim
#: the oldest records beyond this many (traces are an echo feed,
#: not an archive of record).
TRACE_KEEP = 5000
TRACE_RESULT_CAP = 500
TRACE_ERROR_CAP = 2000
TRACE_LIST_DEFAULT = 100
TRACE_LIST_CAP = 500


def _trace_view(t: dict) -> dict:
    return {
        "id": t["id"],
        "action": t["action"],
        "actor": t.get("actor") or "agent",
        "target": t.get("target") or {},
        "at": t["at"],
        "status": t["status"],
        "result": t.get("result"),
        "error": t.get("error"),
        "detail": t.get("detail"),
    }


def _clean_trace_target(value) -> dict:
    if not isinstance(value, dict):
        raise _Err(400, "target 必须是对象")
    kind = value.get("kind")
    if not isinstance(kind, str) or not kind.strip():
        raise _Err(400, "target.kind 不能为空")
    out = {"kind": kind.strip()[:40]}
    for key, cap in (("id", 120), ("label", 200), ("ref", 300)):
        v = value.get(key)
        if v is None:
            out[key] = ""
        elif isinstance(v, str):
            out[key] = v[:cap]
        else:
            raise _Err(400, f"target.{key} 必须是字符串")
    return out


def _record_trace_locked(action: str, actor: str, target: dict,
                         status: str, result=None, error=None,
                         detail=None, at=None) -> dict:
    """Append one trace; caller must hold _lock. Saves the db."""
    rec = {
        "id": _new_id("trc_", {t["id"] for t in _db["traces"]}),
        "action": action,
        "actor": actor or "agent",
        "target": target,
        "at": at if isinstance(at, (int, float)) else _now(),
        "status": status,
        "result": (result[:TRACE_RESULT_CAP]
                   if isinstance(result, str) else result),
        "error": (error[:TRACE_ERROR_CAP]
                  if isinstance(error, str) else error),
        "detail": detail,
    }
    _db["traces"].append(rec)
    if len(_db["traces"]) > TRACE_KEEP:
        del _db["traces"][:len(_db["traces"]) - TRACE_KEEP]
    _save_locked()
    return _trace_view(rec)


def _append_trace(action: str, target: dict, status: str, *,
                  actor: str = "agent", result=None, error=None,
                  detail=None) -> dict:
    """Record a trace for an action that already ran (its own save
    is done). If the recording itself fails, that is LOUD: the
    exception propagates -- a trace must never fail silently."""
    with _lock:
        return _record_trace_locked(action, actor, target, status,
                                    result=result, error=error,
                                    detail=detail)


def _create_trace(body: dict) -> dict:
    """POST /traces: validate the five elements at the door."""
    action = body.get("action")
    if not isinstance(action, str) or not action.strip():
        raise _Err(400, "action 不能为空")
    actor = body.get("actor", "agent")
    if not isinstance(actor, str) or not actor.strip():
        raise _Err(400, "actor 不对")
    target = _clean_trace_target(body.get("target"))
    status = body.get("status")
    if status not in ("ok", "failed"):
        raise _Err(400, "status 必须是 ok 或 failed")
    result = body.get("result")
    error = body.get("error")
    if status == "ok":
        if not isinstance(result, str) or not result.strip():
            raise _Err(400, "成功留痕必须带 result 结果摘要")
        error = None
    else:
        if not isinstance(error, str) or not error.strip():
            raise _Err(400, "失败留痕必须带 error 失败原文")
        result = None
    detail = body.get("detail")
    if detail is not None and not isinstance(detail, dict):
        raise _Err(400, "detail 必须是对象")
    at = body.get("at")
    if at is not None and not isinstance(at, (int, float)):
        raise _Err(400, "at 必须是 epoch 数字")
    with _lock:
        return _record_trace_locked(action.strip()[:80],
                                    actor.strip()[:20], target, status,
                                    result=result, error=error,
                                    detail=detail, at=at)


def _list_traces(query: dict) -> list:
    items = list(_db["traces"])
    action = (query.get("action") or [None])[0]
    if action:
        items = [t for t in items if t["action"] == action]
    status = (query.get("status") or [None])[0]
    if status:
        items = [t for t in items if t["status"] == status]
    target_id = (query.get("targetId") or [None])[0]
    if target_id:
        items = [t for t in items
                 if (t.get("target") or {}).get("id") == target_id]
    since_raw = (query.get("since") or [None])[0]
    if since_raw:
        try:
            since = float(since_raw)
        except ValueError:
            raise _Err(400, "since 必须是 epoch 数字")
        items = [t for t in items if t["at"] >= since]
    try:
        limit = int((query.get("limit") or [TRACE_LIST_DEFAULT])[0])
    except ValueError:
        raise _Err(400, "limit 必须是整数")
    limit = max(1, min(limit, TRACE_LIST_CAP))
    items.sort(key=lambda t: t["at"], reverse=True)
    return [_trace_view(t) for t in items[:limit]]


def _get_trace(tid: str) -> dict:
    rec = next((t for t in _db["traces"] if t["id"] == tid), None)
    if rec is None:
        raise _Err(404, "留痕不存在")
    return _trace_view(rec)
