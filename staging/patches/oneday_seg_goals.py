# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_goals.py -- part of modules/oneday_gateway.py,
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




# --- domain operations (all called under _lock) ----------------------------

def _list_goals() -> list:
    items = sorted(_db["goals"], key=lambda g: g["createdAt"])
    return [_goal_view(g) for g in items]


def _create_goal(body: dict) -> dict:
    title = _clean_title(body.get("title"))
    note = body.get("note", "")
    if note is None:
        note = ""
    if not isinstance(note, str):
        raise _Err(400, "note 必须是字符串")
    parent_id = body.get("parentId")
    _check_parent(None, parent_id, _db["goals"])
    source = body.get("source", "manual")
    if source not in GOAL_SOURCES:
        raise _Err(400, "source 不对")
    category = _clean_category(body.get("category"))
    gids = {g["id"] for g in _db["goals"]}
    ts = _now()
    goal = {
        "id": _new_id("g_", gids),
        "title": title,
        "note": note,
        "createdAt": ts,
        "updatedAt": ts,
        "status": "active",
        "completedAt": None,
        "parentId": parent_id,
        "source": source,
        "category": category,
    }
    _db["goals"].append(goal)
    _save_locked()
    return _goal_view(goal)


def _patch_goal(gid: str, body: dict) -> dict:
    goal = next((g for g in _db["goals"] if g["id"] == gid), None)
    if goal is None:
        raise _Err(404, "目标不存在")
    if "title" in body:
        goal["title"] = _clean_title(body.get("title"))
    if "note" in body:
        note = body.get("note")
        if note is None:
            note = ""
        if not isinstance(note, str):
            raise _Err(400, "note 必须是字符串")
        goal["note"] = note
    # G-6 (2026-11-24): milestones removed (Muse parity -- the
    # Muse data model has no milestones; decomposition goes
    # through subgoals + progress entries). A "milestones" key in
    # a PATCH body is ignored, and the all-done auto entry/event
    # that used to ride on it is gone with the concept.
    if "status" in body:
        new_status = body.get("status")
        if new_status not in GOAL_STATUSES:
            raise _Err(400, "status 不对（只许 active / completed）")
        cur = _goal_status(goal)
        if new_status != cur:
            # completedAt is settled here, on the transition, by
            # the bridge -- clients never write the timestamp.
            goal["status"] = new_status
            goal["completedAt"] = _now() \
                if new_status == "completed" else None
    if "parentId" in body:
        _check_parent(gid, body.get("parentId"), _db["goals"])
        goal["parentId"] = body.get("parentId")
    if "category" in body:
        # explicit null clears back to uncategorised; the user
        # picking a category in the edit sheet is the only way
        # an existing goal ever gains one (no inference)
        goal["category"] = _clean_category(body.get("category"))
    goal["updatedAt"] = _now()
    _save_locked()
    return _goal_view(goal)


def _delete_goal(gid: str) -> None:
    goal = next((g for g in _db["goals"] if g["id"] == gid), None)
    if goal is None:
        raise _Err(404, "目标不存在")
    # Sub-goals go with their parent (Muse caliber: deleting a
    # goal takes its sub-goals, history and briefings along);
    # ideas and monitors only unlink, they are not the goal's own.
    doomed = {gid} | {g["id"] for g in _db["goals"]
                      if g.get("parentId") == gid}
    _db["goals"] = [g for g in _db["goals"] if g["id"] not in doomed]
    _db["goalEntries"] = [e for e in _db["goalEntries"]
                          if e["goalId"] not in doomed]
    _db["briefings"] = [b for b in _db["briefings"]
                        if b["goalId"] not in doomed]
    # The tasks' goalId fields name this goal: they are the
    # goal's own association and clear with it (1.0.65). The
    # kanban tasks themselves are NOT the goal's property and
    # stay untouched on the board; their echo ledgers go too,
    # so a future goal reusing the task starts clean.
    for tid in [tid for tid, a in _db["taskGoals"].items()
                if a["goalId"] in doomed]:
        del _db["taskGoals"][tid]
        _db["goalEchoState"].pop(tid, None)
    for idea in _db["ideas"]:
        if idea.get("goalId") in doomed:
            idea["goalId"] = None
    for mon in _db["monitors"]:
        if mon.get("goalId") in doomed:
            mon["goalId"] = None
    _save_locked()


# --- goal entries & briefings (P2, all called under _lock) -----------------

def _entry_view(e: dict) -> dict:
    # G-2 (2026-11-24): title/origin leave the storage layer -- the
    # migrated Muse history carries both, and distilled bookkeeping
    # entries are written with them; a whitelist that hides them made
    # them invisible to the App (data zombie). Both stay optional:
    # entries written before G-2 simply read back null.
    title = e.get("title")
    origin = e.get("origin")
    return {
        "id": e["id"],
        "goalId": e["goalId"],
        "body": e["body"],
        "title": title if isinstance(title, str) and title else None,
        "origin": origin if isinstance(origin, str) and origin else None,
        "source": e.get("source")
        if e.get("source") in ENTRY_SOURCES else "user",
        "createdAt": e["createdAt"],
    }


_ENTRY_TITLE_CAP = 120
_ENTRY_ORIGIN_CAP = 40
_CST = timezone(timedelta(hours=8))  # Asia/Shanghai, no DST


def _entry_local_date(e: dict):
    """Local (Asia/Shanghai) calendar date of an entry, tolerating
    both epoch-float and ISO-string createdAt values."""
    ts = e.get("createdAt")
    try:
        if isinstance(ts, (int, float)):
            return datetime.fromtimestamp(ts, tz=_CST).date()
        if isinstance(ts, str):
            return datetime.fromisoformat(
                ts.replace("Z", "+00:00")).astimezone(_CST).date()
    except (ValueError, OverflowError, OSError):
        return None
    return None


def _find_goal(gid: str) -> dict:
    goal = next((g for g in _db["goals"] if g["id"] == gid), None)
    if goal is None:
        raise _Err(404, "目标不存在")
    return goal


def _list_entries(gid: str) -> list:
    _find_goal(gid)
    items = [e for e in _db["goalEntries"] if e["goalId"] == gid]
    items.sort(key=lambda e: e["createdAt"])
    return [_entry_view(e) for e in items]


def _create_entry(gid: str, body: dict) -> dict:
    _find_goal(gid)
    text = body.get("body")
    if not isinstance(text, str) or not text.strip():
        raise _Err(400, "进展内容不能为空")
    text = text.strip()
    if len(text) > ENTRY_BODY_CAP:
        raise _Err(400, f"进展内容太长（上限 {ENTRY_BODY_CAP} 字）")
    source = body.get("source", "user")
    if source not in ENTRY_SOURCES:
        raise _Err(400, "source 不对")
    # G-2: optional title ( Muse-style layered entries) and
    # origin (provenance: migration / bookkeeping / ...). Both are
    # stored only when well-formed; the view above returns them.
    title = body.get("title")
    if title is not None:
        if not isinstance(title, str):
            raise _Err(400, "title 不对")
        title = title.strip()[:_ENTRY_TITLE_CAP] or None
    origin = body.get("origin")
    if origin is not None:
        if not isinstance(origin, str):
            raise _Err(400, "origin 不对")
        origin = origin.strip()[:_ENTRY_ORIGIN_CAP] or None
    if origin == "bookkeeping":
        # Anti-flood, enforced server-side so no caller discipline is
        # required: at most one distilled bookkeeping entry per goal
        # per local day (Muse parity rule, audit G-2).
        today = datetime.fromtimestamp(_now(), tz=_CST).date()
        for e in _db["goalEntries"]:
            if (e["goalId"] == gid and e.get("origin") == "bookkeeping"
                    and _entry_local_date(e) == today):
                raise _Err(409, "该目标今日已有一条提炼进展，不重复记账")
    entry = {
        "id": _new_id("e_", {e["id"] for e in _db["goalEntries"]}),
        "goalId": gid,
        "body": text,
        "source": source,
        "createdAt": _now(),
    }
    if title:
        entry["title"] = title
    if origin:
        entry["origin"] = origin
    _db["goalEntries"].append(entry)
    _save_locked()
    return _entry_view(entry)


def _delete_entry(gid: str, eid: str) -> None:
    _find_goal(gid)
    if not any(e["id"] == eid and e["goalId"] == gid
               for e in _db["goalEntries"]):
        raise _Err(404, "进展条目不存在")
    _db["goalEntries"] = [e for e in _db["goalEntries"]
                          if e["id"] != eid]
    _save_locked()
