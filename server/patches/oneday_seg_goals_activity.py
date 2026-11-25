# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_goals_activity.py -- part of modules/oneday_gateway.py,
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




# --- goal task assignment (1.0.65 single track) ----------------------------
#
# The goal<->kanban association carrier since 1.0.65: a task's
# goalId as a SINGLE-VALUED FIELD, held bridge-side in
# _db["taskGoals"] (taskId -> {goalId, milestoneId, assignedAt,
# delegateKey?}). Kanban cards cannot hold the field themselves
# (the Hermes tasks table is a fixed-column schema with no
# goalId and no generic metadata slot -- verified in 0.39.0 and
# re-verified for 1.0.65 against the v0.23.0 kanban_db schema),
# and Hermes is upstream, so the field lives with the goals
# domain's owner -- this bridge -- and every read face derives
# from this one store (the goal's task list is a read-time
# projection of the field, never a second record). The
# pre-1.0.65 goalTaskLinks collection is folded into this store
# once at load (see _migrate_goal_task_links) and never written
# again; the task-links HTTP faces survive one cycle as a thin
# compatibility projection over this store for the pre-1.0.65
# App, to be removed once that App is out of the field.
#
# The completion/stopped echoes' exactly-once state lives in
# _db["goalEchoState"] (taskId -> {completedEntryAt,
# completedGoalId, stoppedEntryAt, stoppedBucket,
# stoppedGoalId}) -- poll bookkeeping, NOT association data:
# it is never served as a field, and the echoes themselves are
# derived from task status transitions, exactly as the link
# stamps were, only the ledger moved off the association.

def _task_goal_view(task_id: str, a) -> dict:
    # G-6 (2026-11-24): milestoneId is always null -- the milestone
    # concept is removed; the key stays for one cycle so the
    # shipped App's link decoder keeps its shape.
    if a is None:
        return {"taskId": task_id, "goalId": None,
                "milestoneId": None, "assignedAt": None}
    return {"taskId": task_id, "goalId": a["goalId"],
            "milestoneId": None,
            "assignedAt": a["assignedAt"]}


def _assignments_for_goal_locked(gid: str) -> list:
    """(taskId, assignment) pairs of one goal, assignedAt asc."""
    pairs = [(tid, a) for tid, a in _db["taskGoals"].items()
             if a["goalId"] == gid]
    pairs.sort(key=lambda p: p[1]["assignedAt"])
    return pairs


def _set_task_goal_locked(task_id: str, goal_id, milestone_id,
                          delegate_key=None) -> dict:
    """Write the task's goalId field (under _lock). goal_id
    None clears the assignment (and its echo state, so a later
    re-assignment starts with a clean episode ledger). Setting
    the same goal again is idempotent and keeps the original
    assignedAt; moving a task to another goal resets its echo
    state -- the new goal has seen no echoes yet."""
    if goal_id is None:
        _db["taskGoals"].pop(task_id, None)
        _db["goalEchoState"].pop(task_id, None)
        _save_locked()
        return _task_goal_view(task_id, None)
    goal = _find_goal(goal_id)
    # G-6: milestone_id is accepted for wire compatibility and
    # ignored -- assignments no longer carry a milestone.
    milestone_id = None
    existing = _db["taskGoals"].get(task_id)
    if existing is not None and existing["goalId"] == goal_id:
        if existing.get("milestoneId") is not None:
            existing["milestoneId"] = None
            _save_locked()
        return _task_goal_view(task_id, existing)
    if existing is not None:
        _db["goalEchoState"].pop(task_id, None)
    a = {"goalId": goal_id, "milestoneId": None,
         "assignedAt": _now()}
    if delegate_key:
        a["delegateKey"] = delegate_key
    _db["taskGoals"][task_id] = a
    _save_locked()
    return _task_goal_view(task_id, a)


def _put_task_goal(task_id: str, body: dict) -> dict:
    """PUT /tasks/{taskId}/goal body (under _lock):
    {goalId: str | null, milestoneId?: str | null}. The one
    write face for the field outside delegation."""
    if not isinstance(task_id, str) or not task_id.strip():
        raise _Err(400, "taskId 不能为空")
    task_id = task_id.strip()
    if "goalId" not in body:
        raise _Err(400, "goalId 必填（null 表示取消归属）")
    goal_id = body.get("goalId")
    if goal_id is not None and not isinstance(goal_id, str):
        raise _Err(400, "goalId 必须是字符串或 null")
    milestone_id = body.get("milestoneId")  # G-6: ignored, see above
    return _set_task_goal_locked(task_id, goal_id, milestone_id)


def _migrate_goal_task_links() -> None:
    """One-time fold of the retired goalTaskLinks collection
    into the taskGoals field store (1.0.65). Runs at the end of
    _load (startup context, before the server accepts traffic);
    idempotent -- a second boot finds an empty collection and
    does nothing. Per taskId the EARLIEST link wins the field
    (single-valued by construction; later duplicates count as
    conflicts). The links' echo stamps seed goalEchoState so
    already-written fact entries never re-fire. A failure here
    must never degrade the bridge: the fold is retried on the
    next boot because the collection is only cleared on
    success."""
    links = _db.get("goalTaskLinks") or []
    if not links:
        return
    try:
        goal_ids = {g["id"] for g in _db["goals"]}
        ordered = sorted(
            links, key=lambda l: l.get("createdAt") or 0)
        assigned = conflicts = dropped = 0
        for l in ordered:
            tid = l.get("taskId")
            gid = l.get("goalId")
            if not tid or not gid or gid not in goal_ids:
                dropped += 1
                continue
            if tid in _db["taskGoals"]:
                conflicts += 1
            else:
                _db["taskGoals"][tid] = {
                    "goalId": gid,
                    "milestoneId": l.get("milestoneId"),
                    "assignedAt": l.get("createdAt") or _now(),
                }
                assigned += 1
            st = _db["goalEchoState"].setdefault(tid, {})
            if l.get("completionEntryAt") is not None \
                    and st.get("completedEntryAt") is None:
                st["completedEntryAt"] = l["completionEntryAt"]
                st["completedGoalId"] = gid
            if l.get("stoppedEntryAt") is not None \
                    and st.get("stoppedEntryAt") is None:
                st["stoppedEntryAt"] = l["stoppedEntryAt"]
                st["stoppedBucket"] = l.get("stoppedEntryBucket")
                st["stoppedGoalId"] = gid
            if not st:
                _db["goalEchoState"].pop(tid, None)
        _db["goalTaskLinks"] = []
        _db.setdefault("meta", {})["taskGoalMigration"] = {
            "at": _now(), "links": len(links),
            "assigned": assigned, "conflicts": conflicts,
            "dropped": dropped,
        }
        _save_locked()
        _print(f"goalTaskLinks folded into taskGoals: "
              f"{assigned} assigned, {conflicts} conflicts, "
              f"{dropped} dropped (of {len(links)} links)",
              file=sys.stderr, flush=True)
    except Exception as e:  # never degrade the bridge over this
        _print(f"goalTaskLinks migration deferred: {e!r}",
              file=sys.stderr, flush=True)


# --- task-links compatibility projection (deprecated) ----------------------
#
# The pre-1.0.65 App's read/write faces, projected over the
# taskGoals field store: there is no link record any more, the
# "link" below is synthesized per request (id is derived from
# the taskId, createdAt is the field's assignedAt, the stamps
# are read from the poll's echo ledger). Writes go through
# _set_task_goal_locked, so the compat face inherits field
# semantics -- a POST for a task that already belongs to
# another goal MOVES it (the old collection would have kept
# two rows). Removal is registered as a follow-up, gated on
# the old App leaving the field.

def _task_link_view(task_id: str, a: dict) -> dict:
    st = _db["goalEchoState"].get(task_id) or {}
    gid = a["goalId"]
    return {
        "id": "gt_" + task_id,
        "goalId": gid,
        "taskId": task_id,
        "milestoneId": a.get("milestoneId"),
        "createdAt": a["assignedAt"],
        "completionEntryAt":
            st.get("completedEntryAt")
            if st.get("completedGoalId") == gid else None,
        "stoppedEntryAt":
            st.get("stoppedEntryAt")
            if st.get("stoppedGoalId") == gid else None,
    }


def _list_task_links(gid: str) -> list:
    _find_goal(gid)
    return [_task_link_view(tid, a)
            for tid, a in _assignments_for_goal_locked(gid)]


def _create_task_link(gid: str, body: dict) -> dict:
    goal = _find_goal(gid)
    task_id = body.get("taskId")
    if not isinstance(task_id, str) or not task_id.strip():
        raise _Err(400, "taskId 不能为空")
    task_id = task_id.strip()
    milestone_id = body.get("milestoneId")
    _validate_milestone_locked(goal, milestone_id)
    _set_task_goal_locked(task_id, gid, milestone_id)
    return _task_link_view(task_id, _db["taskGoals"][task_id])


def _delegate_goal_task(gid: str, body: dict) -> dict:
    """POST /goals/{id}/delegate (1.0.65): one-shot delegation.
    The bridge creates the kanban card itself through the
    Dashboard channel and writes the task's goalId field in the
    same operation, so a delegated card is never observable
    without its goal (the pre-1.0.65 App created the card, then
    wrote the link back as a second, failable step). NOT called
    under _lock: it takes the lock only for its short store
    reads/writes around the Dashboard round-trip. A client
    idempotencyKey makes a retried delegation return the
    original assignment instead of creating a second card (and
    is forwarded to kanban, whose create dedups on it too).
    Dispatch after creation is best-effort, mirroring the App's
    old flow -- the gateway's automatic tick dispatches anyway.
    """
    title = body.get("title")
    if not isinstance(title, str) or not title.strip():
        raise _Err(400, "任务标题不能为空")
    title = title.strip()[:200]
    milestone_id = body.get("milestoneId")
    idem = body.get("idempotencyKey")
    if idem is not None and not isinstance(idem, str):
        raise _Err(400, "idempotencyKey 必须是字符串")
    with _lock:
        goal = _find_goal(gid)
        _validate_milestone_locked(goal, milestone_id)
        if idem:
            for tid, a in _db["taskGoals"].items():
                if a["goalId"] == gid \
                        and a.get("delegateKey") == idem:
                    return {**_task_goal_view(tid, a),
                            "title": title}
        goal_title = goal["title"]
    card_body = {
        "title": title,
        "assignee": "default",
        "body": f"为目标《{goal_title}》安排的一件事。",
        "idempotency_key": idem or secrets.token_hex(16),
    }
    raw = _dash_json("/api/plugins/kanban/tasks?board=oneday",
                     method="POST", body=card_body)
    task = raw.get("task") if isinstance(raw, dict) else None
    if not isinstance(task, dict):
        task = raw if isinstance(raw, dict) else {}
    task_id = task.get("id")
    if not isinstance(task_id, str) or not task_id:
        raise _Err(502, "kanban 建卡未返回任务 id")
    try:
        _dash_json("/api/plugins/kanban/dispatch?board=oneday",
                   method="POST")
    except Exception:
        pass  # dispatch failure never unmakes the card
    with _lock:
        view = _set_task_goal_locked(
            task_id, gid, milestone_id, delegate_key=idem)
    return {**view, "title": title}


def _record_completed_task_entries_locked(tasks: dict,
                                          now: float) -> None:
    """Fact-only auto progress entries for delegated tasks
    (0.40.0, spec ch.3 3.1/3.4). Called under _lock from the
    feed kanban poll with the fresh id -> (title, status) map.
    A task whose goalId field is set and that now sits in a
    done state earns its goal exactly ONE entry; the
    exactly-once ledger is the poll's own goalEchoState (per
    task + goal), not a stamp on the association (1.0.65).
    The entry states only verifiable facts -- the task's title
    and id; no progress narrative is invented. Assignments
    whose goal is gone are skipped (goal deletion clears them,
    so this is only a belt-and-braces guard)."""
    if not _db["taskGoals"]:
        return
    goal_ids = {g["id"] for g in _db["goals"]}
    entry_ids = {e["id"] for e in _db["goalEntries"]}
    for task_id, a in _db["taskGoals"].items():
        gid = a["goalId"]
        if gid not in goal_ids:
            continue
        st = _db["goalEchoState"].get(task_id) or {}
        if st.get("completedEntryAt") is not None \
                and st.get("completedGoalId") == gid:
            continue
        found = tasks.get(task_id)
        if not found:
            continue
        title, state = found
        if str(state).lower() not in _KANBAN_DONE_STATUSES:
            continue
        st = _db["goalEchoState"].setdefault(task_id, {})
        st["completedEntryAt"] = now
        st["completedGoalId"] = gid
        if title:
            text = f"任务《{title[:60]}》已完成（任务号 {task_id}）"
        else:
            text = f"关联任务已完成（任务号 {task_id}）"
        _db["goalEntries"].append({
            "id": _new_id("e_", entry_ids),
            "goalId": gid,
            "body": text,
            "source": "agent",
            "createdAt": now,
        })


def _record_stopped_task_entries_locked(tasks: dict,
                                        now: float) -> None:
    """Fact-only auto progress entries when a delegated task
    stops (GD-1b path one, user ruling 2026-11-12: the bridge
    writes goalEntries). Called under _lock from the feed
    kanban poll with the fresh id -> (title, status) map,
    right after the completion recorder. A task with a goalId
    in a blocked/failed state earns its goal ONE entry per
    stopped episode, tracked in the poll's goalEchoState
    (stoppedBucket per task + goal; 1.0.65, formerly a stamp
    on the link): staying stopped across polls does not
    re-fire, moving blocked -> failed is a new fact and
    fires again, and leaving the stopped states clears the
    episode so a later re-stop earns a fresh entry. The entry
    states only verifiable facts -- the task's title, id and
    the stopped state word; no narrative is invented.
    Assignments whose goal is gone are skipped (goal deletion
    clears them, so this is only a belt-and-braces guard,
    same as the completion recorder)."""
    if not _db["taskGoals"]:
        return
    goal_ids = {g["id"] for g in _db["goals"]}
    entry_ids = {e["id"] for e in _db["goalEntries"]}
    for task_id, a in _db["taskGoals"].items():
        gid = a["goalId"]
        if gid not in goal_ids:
            continue
        found = tasks.get(task_id)
        if not found:
            continue
        title, state = found
        bucket = _kanban_bucket(state)
        st = _db["goalEchoState"].get(task_id) or {}
        if bucket not in ("blocked", "failed"):
            if st.get("stoppedBucket") is not None \
                    and st.get("stoppedGoalId") == gid:
                st["stoppedEntryAt"] = None
                st["stoppedBucket"] = None
                st["stoppedGoalId"] = None
            continue
        if st.get("stoppedBucket") == bucket \
                and st.get("stoppedGoalId") == gid:
            continue
        st = _db["goalEchoState"].setdefault(task_id, {})
        st["stoppedEntryAt"] = now
        st["stoppedBucket"] = bucket
        st["stoppedGoalId"] = gid
        word = "被阻塞" if bucket == "blocked" else "失败"
        if title:
            text = f"任务《{title[:60]}》{word}（任务号 {task_id}）"
        else:
            text = f"关联任务{word}（任务号 {task_id}）"
        _db["goalEntries"].append({
            "id": _new_id("e_", entry_ids),
            "goalId": gid,
            "body": text,
            "source": "agent",
            "createdAt": now,
        })


# --- goal activity derivation (GD-1, parity spec ch.4.3) --------------
#
# Read-time only: this section never writes goal, entry or
# assignment records (the entry write paths are the completion
# recorder and the GD-1b stopped recorder above, each under
# its own exactly-once-per-episode ledger). The raw
# material is the goal<->kanban assignment field (taskGoals,
# 1.0.65; formerly the goalTaskLinks collection) plus the
# feed poll's kanban state graph (meta.feed
# taskSnapshot/taskTitles, refreshed every
# FEED_POLL_SECONDS), so a goals read costs no
# network and no per-goal fetch -- one pass over in-memory
# dicts per goal. State words are the parity spec's own four
# (running/waiting/blocked/idle); raw kanban states are bucketed
# with the vocabularies already in force (the ledger's
# KANBAN_MAP key set, the bridge's done/blocked sets and the
# feed's failed set), and a linked task's raw state passes
# through verbatim in focusTask. A failed task folds into the
# "blocked" state word (FD-1 already grades failed/blocked as
# one stopped class) and stays distinguishable via failedCount.
# Derivation gaps are stated in `note`, never silently zeroed.

_KANBAN_RUNNING_STATES = {"in_progress", "running", "doing",
                          "wip", "review", "in_review"}
_KANBAN_WAITING_STATES = {"triage", "backlog", "todo",
                          "scheduled", "ready", "queued"}
_KANBAN_CANCELLED_STATES = {"cancelled", "canceled"}


def _kanban_bucket(state) -> str:
    low = str(state or "").lower()
    if low in _KANBAN_RUNNING_STATES:
        return "running"
    if low in _KANBAN_BLOCKED_STATUSES:
        return "blocked"
    if low in _FEED_TASK_FAILED_STATUSES:
        return "failed"
    if low in _KANBAN_DONE_STATUSES:
        return "done"
    if low in _KANBAN_WAITING_STATES:
        return "waiting"
    if low in _KANBAN_CANCELLED_STATES:
        return "cancelled"
    return "other"


def _goal_activity(g: dict, latest) -> dict:
    """One goal's derived activity (GD-1). Called under _lock
    from _goal_view; `latest` is the goal's newest entry record
    (or None) -- the same record latestEntry renders from."""
    feed = _feed_meta_locked()
    snap = feed.get("taskSnapshot") or {}
    titles = feed.get("taskTitles") or {}
    polled_at = feed.get("kanbanPolledAt") or 0
    links = _assignments_for_goal_locked(g["id"])
    counts = {"running": 0, "blocked": 0, "failed": 0,
              "waiting": 0, "done": 0, "cancelled": 0, "other": 0}
    present = []  # (taskId, assignment, raw state, bucket)
    missing = 0
    for tid, a in links:
        raw = snap.get(tid)
        if raw is None:
            missing += 1
            continue
        bucket = _kanban_bucket(raw)
        counts[bucket] += 1
        present.append((tid, a, raw, bucket))
    # The snapshot carries no timestamps; the feed event ring
    # (state transitions of board tasks) is the only in-bridge
    # record of WHEN a linked task last changed state.
    linked_ids = {tid for tid, _a in links}
    last_event_at = None
    bucket_since = {}
    for e in reversed(feed.get("events") or []):
        refs = [r.get("id") for r in e.get("refs") or []
                if isinstance(r, dict)
                and r.get("type") == "task"]
        if not any(t in linked_ids for t in refs):
            continue
        at = e.get("at")
        if not isinstance(at, (int, float)):
            continue
        if last_event_at is None:
            last_event_at = at
        if e.get("state") is not None:
            bucket_since.setdefault(
                _kanban_bucket(e["state"]), at)
    # State decision: a stopped task is the loudest fact, then
    # live work, then queued work; anything else is idle.
    if counts["blocked"] or (counts["failed"]
                             and not counts["running"]):
        state = "blocked"
        drive = "blocked" if counts["blocked"] else "failed"
    elif counts["running"]:
        state, drive = "running", "running"
    elif counts["waiting"]:
        state, drive = "waiting", "waiting"
    else:
        state, drive = "idle", None
    # focusTask: the task that drives the state -- the one a
    # tap should land on. Newest observed transition wins,
    # else the most recently linked candidate.
    focus = None
    if drive:
        cands = {tid: (a, raw)
                 for tid, a, raw, b in present if b == drive}
        picked = None
        for e in reversed(feed.get("events") or []):
            for r in e.get("refs") or []:
                if isinstance(r, dict) \
                        and r.get("id") in cands:
                    picked = r["id"]
                    break
            if picked:
                break
        if picked is None:
            # newest-assigned candidate drives when the ring
            # holds no transition for any of them
            picked = max(cands.items(),
                         key=lambda kv: kv[1][0]["assignedAt"])[0]
        focus = {"id": picked,
                 "title": titles.get(picked) or "",
                 "status": cands[picked][1]}
    # `since` is best-effort by construction (event ring is
    # bounded): the newest observed transition into the bucket
    # that drives the state; None when the ring holds none --
    # never back-filled with a guessed time.
    since = bucket_since.get(drive) if drive else None
    all_done = bool(links) and not missing and len(present) \
        and counts["done"] == len(present)
    if state == "idle" and all_done:
        since = bucket_since.get("done")
    if state == "blocked":
        bits = []
        if counts["blocked"]:
            bits.append(f"{counts['blocked']} 件关联任务被阻塞")
        if counts["failed"]:
            bits.append(f"{counts['failed']} 件关联任务失败")
        label = "、".join(bits)
    elif state == "running":
        label = f"{counts['running']} 件任务进行中"
        if counts["waiting"]:
            label += f"，{counts['waiting']} 件待开始"
        if counts["failed"]:
            label += f"，{counts['failed']} 件失败"
    elif state == "waiting":
        label = f"{counts['waiting']} 件任务待开始"
    elif not links:
        label = "暂无关联任务"
    elif all_done:
        label = "关联任务已全部完成"
    elif missing == len(links):
        label = "关联任务状态暂不可用"
    else:
        label = "暂无进行中的关联任务"
    notes = []
    if links and not polled_at:
        notes.append("任务板状态尚未同步")
    elif missing:
        if feed.get("kanbanNote"):
            notes.append(str(feed["kanbanNote"]))
        notes.append(f"{missing} 件关联任务不在当前任务板上")
    if counts["other"]:
        notes.append(f"{counts['other']} 件关联任务状态未识别")
    stamps = [g["updatedAt"]]
    if latest:
        stamps.append(latest["createdAt"])
    if links:
        stamps.append(max(a["assignedAt"] for _tid, a in links))
    if last_event_at:
        stamps.append(last_event_at)
    return {
        "state": state,
        "label": label,
        "since": since,
        "focusTask": focus,
        "runningCount": counts["running"],
        "blockedCount": counts["blocked"],
        "failedCount": counts["failed"],
        "waitingCount": counts["waiting"],
        "doneCount": counts["done"],
        "cancelledCount": counts["cancelled"],
        "linkedCount": len(links),
        "missingCount": missing,
        "latestProgress": (
            {"text": latest["body"], "at": latest["createdAt"]}
            if latest else None),
        "lastActivityAt": max(stamps),
        "polledAt": polled_at,
        "note": "；".join(notes) if notes else None,
    }


# --- goal task read faces (GD-2, parity spec ch.4 GD-2) ----------------
#
# Two read-only faces over the same in-memory state graph the
# GD-1 activity derivation already reads (taskGoals + the
# feed poll's taskSnapshot/taskTitles/event ring), so a read
# costs no network and no per-goal fetch:
#
# 1. _goal_tasks_view: one goal's linked tasks as live rows
#    (title / raw status / bucket / updatedAt). updatedAt is
#    the newest event-ring transition observed for the task;
#    the ring is bounded, so a task with no observed transition
#    reads null -- never back-filled with a guessed time.
#
# 2. _ungrouped_tasks_view: board tasks of the USER-INITIATED
#    classes whose goalId field is unset, offered for one-tap
#    grouping (grouping = the PUT /tasks/{taskId}/goal write;
#    this face moves no data and groups nothing by itself).
#    Classes follow the parity spec ch.3 harmonised reading
#    (goals own "tasks the user cares about: delegated,
#    idea-adopted, conversation-dispatched"; pure system /
#    scheduled / probe work stays in the work ledger):
#      - "adopted": the task is an idea's taskId and the idea
#        itself carries no goalId (an idea WITH a goalId groups
#        its task through the idea already);
#      - "chat": the task has a kanbanBindings row with no
#        goalId, i.e. it was dispatched from a named owner
#        session through the automation facade.
#    A card the bridge holds no origin record for (created
#    directly on the board, by cron machinery, by probes) is
#    NOT user-initiated evidence and never enters this face.
#    Only tasks present in the latest board snapshot are
#    offered: a card that left the board must not earn a link.

def _task_last_event_at(feed: dict, task_id: str):
    """Newest event-ring timestamp for one task, or None."""
    for e in reversed(feed.get("events") or []):
        at = e.get("at")
        if not isinstance(at, (int, float)):
            continue
        for r in e.get("refs") or []:
            if isinstance(r, dict) and r.get("type") == "task" \
                    and r.get("id") == task_id:
                return at
    return None


def _goal_tasks_view(gid: str) -> list:
    """GD-2 face 1: the goal's assigned tasks, live (under
    _lock). Rows are the read-time projection of the taskGoals
    field (1.0.65): goalId rides on every row as the field's
    own value; linkId/linkedAt keep their pre-1.0.65 wire
    shape for the old App (linkId is derived from the taskId,
    linkedAt is the field's assignedAt)."""
    _find_goal(gid)
    feed = _feed_meta_locked()
    snap = feed.get("taskSnapshot") or {}
    titles = feed.get("taskTitles") or {}
    items = []
    for tid, a in _assignments_for_goal_locked(gid):
        raw = snap.get(tid)
        # The bridge's completion stamp for THIS goal, exposed
        # read-only: the App's echo planner fires its
        # "completed" echo only once the bridge-side fact
        # entry exists (stamp and this row's bucket are
        # written by the same poll round) -- exactly the
        # pre-1.0.65 link-stamp discipline.
        echo = _db["goalEchoState"].get(tid) or {}
        completion_at = (echo.get("completedEntryAt")
                         if echo.get("completedGoalId") == gid
                         else None)
        items.append({
            "taskId": tid,
            "goalId": gid,
            "linkId": "gt_" + tid,
            "title": titles.get(tid) or "",
            "status": raw,
            "bucket": _kanban_bucket(raw) if raw is not None
                      else None,
            "updatedAt": _task_last_event_at(feed, tid),
            "linkedAt": a["assignedAt"],
            "assignedAt": a["assignedAt"],
            "completionEntryAt": completion_at,
            "milestoneId": a.get("milestoneId"),
        })
    return items


def _ungrouped_tasks_view() -> dict:
    """GD-2 face 2: ungrouped user-initiated tasks (under _lock)."""
    feed = _feed_meta_locked()
    snap = feed.get("taskSnapshot") or {}
    titles = feed.get("taskTitles") or {}
    linked = set(_db["taskGoals"])
    adopted = {}
    for i in _db["ideas"]:
        tid = i.get("taskId")
        if tid and not i.get("goalId") \
                and i.get("status") in ("adopted", "built"):
            adopted[tid] = i
    dispatched = {}
    for b in _db["kanbanBindings"]:
        if b.get("taskId") and not b.get("goalId"):
            dispatched[b["taskId"]] = b
    items = []
    for tid in (set(adopted) | set(dispatched)) - linked:
        raw = snap.get(tid)
        if raw is None:
            continue  # not on the current board snapshot
        if tid in adopted:
            src = adopted[tid]
            origin, ref = "adopted", {"ideaId": src["id"]}
            created = src.get("createdAt") or 0
        else:
            src = dispatched[tid]
            origin = "chat"
            ref = {"ownerSessionId": src.get("ownerSessionId")}
            created = src.get("createdAt") or 0
        items.append({
            "taskId": tid,
            "title": titles.get(tid) or src.get("title") or "",
            "status": raw,
            "bucket": _kanban_bucket(raw),
            "origin": origin,
            **ref,
            "createdAt": created,
            "updatedAt": _task_last_event_at(feed, tid),
        })
    items.sort(key=lambda x: x["createdAt"], reverse=True)
    return {"items": items,
            "polledAt": feed.get("kanbanPolledAt") or 0}


def _list_ideas() -> list:
    # ID-2: merged cards leave the list (their canonical stands
    # in for them); pending pool cards follow the active
    # snapshot's settled positions, everything else keeps the
    # createdAt order after them
    items = [i for i in _db["ideas"]
             if i.get("status") != "merged"]
    pool = _pool_meta_locked()
    snap = next((s for s in pool.get("snapshots") or []
                 if s.get("snapshotId")
                 == pool.get("activeSnapshotId")), None)
    if snap:
        pos = snap.get("positions") or {}
        items.sort(key=lambda i: (0, pos[i["id"]])
                   if i["id"] in pos else (1, i["createdAt"]))
    else:
        items.sort(key=lambda i: i["createdAt"])
    return [_idea_view(i) for i in items]


def _create_idea(body: dict) -> dict:
    title = _clean_title(body.get("title"))
    detail = body.get("detail", "")
    if detail is None:
        detail = ""
    if not isinstance(detail, str):
        raise _Err(400, "detail 必须是字符串")
    goal_id = body.get("goalId")
    if goal_id is not None:
        if not isinstance(goal_id, str):
            raise _Err(400, "goalId 必须是字符串或 null")
        if not any(g["id"] == goal_id for g in _db["goals"]):
            raise _Err(400, "目标不存在，无法关联")
    source = body.get("source", "manual")
    if source not in IDEA_SOURCES:
        raise _Err(400, "source 不对")
    evidence = body.get("evidence", "")
    if evidence is None:
        evidence = ""
    if not isinstance(evidence, str):
        raise _Err(400, "evidence 必须是字符串")
    evidence = evidence.strip()
    if source == "generated" and not evidence:
        # Hard gate (design 1.4): a generated card without evidence
        # never lands. Manual notes carry no such requirement.
        raise _Err(400, "生成的点子必须带依据（evidence）")
    evidence_ref = body.get("evidenceRef")
    if evidence_ref is not None and not isinstance(evidence_ref, str):
        raise _Err(400, "evidenceRef 必须是字符串或 null")
    if source == "generated" and evidence_ref is not None \
            and not ANCHOR_REF_RE.match(evidence_ref.strip()):
        # A generated card's ref must at least be shaped like a
        # material anchor (S/G/M/K/R/C + number). Resolvability to a
        # live object is enforced in the generation pipeline itself,
        # whose anchor registry is built from that round's fetches.
        raise _Err(400, "evidenceRef 必须是素材编号（如 S1、G2、K1）")
    anchor_id = body.get("anchorId")
    if anchor_id is not None and not isinstance(anchor_id, str):
        raise _Err(400, "anchorId 必须是字符串或 null")
    iids = {i["id"] for i in _db["ideas"]}
    ts = _now()
    idea = {
        "id": _new_id("i_", iids),
        "title": title,
        "detail": detail,
        # 0.47.0 (§117): optional on create, same cleaning
        # as the generation path
        "emoji": _clean_emoji(body.get("emoji")),
        # 1.0.34: the create surface takes a category key
        # (the App's new-card Picker always sends one); a
        # legacy call without the key -- or with an illegal
        # value -- folds to "other", never a 400.
        "category": _clean_idea_category(body.get("category")),
        # §459: the Muse two-dimension classification and
        # the landing kind ride the create surface tolerantly
        # the same way (fold, never 400).
        "domain": _clean_idea_domain(body.get("domain"),
                                     body.get("category")),
        "categoryLabel": _clean_category_label(
            body.get("categoryLabel")),
        "kind": _clean_idea_kind(body.get("kind")),
        "deliverables": _clean_deliverables(
            body.get("deliverables")),
        "goalId": goal_id,
        "createdAt": ts,
        "source": source,
        "evidence": evidence,
        "evidenceRef": evidence_ref,
        "anchorId": anchor_id,
        "dismissReason": None,
        "status": "pending",
        "taskId": None,
        # ID-2: every stored card carries its dedup fingerprint
        # from birth; pool fields settle at snapshot time
        "contentFingerprint": _idea_fingerprint(
            title, detail, anchor_id),
        "quality": None,
        "poolScore": None,
        "scoreWhy": None,
        "mergedInto": None,
        "mergeReason": None,
        "origin": "native" if source == "generated" else "manual",
        "expiresAt": ts + IDEA_EXPIRE_SECONDS
        if source == "generated" else None,
    }
    _db["ideas"].append(idea)
    _save_locked()
    return _idea_view(idea)


def _patch_idea(iid: str, body: dict) -> dict:
    """Client-writable slice of an idea: status and/or taskId only.

    Rules (design 1.4 state machine): pending -> adopted/dismissed;
    adopted/dismissed/expired are terminal for status. Setting a
    taskId implies adopted (the kanban card exists, adoption is a
    fact); patching taskId on a non-pending, non-adopted idea is a
    conflict. Unknown keys are ignored, like _patch_goal.

    ideas v2: a dismissal may carry dismissReason="tooGeneric"
    (the user's 『太泛』 mark) -- the generator counts it into the
    next rounds' avoidance. statusAt records when the current
    status was settled; the dismissed-anchor 30-day window reads
    it (older cards without it fall back to createdAt)."""
    idea = next((i for i in _db["ideas"] if i["id"] == iid), None)
    if idea is None:
        raise _Err(404, "点子不存在")
    if idea.get("status") == "merged" and idea.get("mergedInto"):
        # ID-2 (rev2 2.3): reads/writes addressed to a merged
        # card resolve to its canonical card
        canon = next((i for i in _db["ideas"]
                      if i["id"] == idea["mergedInto"]), None)
        if canon is not None:
            idea = canon
    cur = idea.get("status", "pending")
    new_status = body.get("status")
    if new_status is not None:
        if new_status not in IDEA_STATUSES:
            raise _Err(400, "status 不对")
        if new_status != cur and \
                new_status not in IDEA_PATCH_TRANSITIONS.get(cur, set()):
            raise _Err(400, f"点子已是「{cur}」，不能改成「{new_status}」")
    task_id = body.get("taskId")
    if "taskId" in body:
        if task_id is not None and not isinstance(task_id, str):
            raise _Err(400, "taskId 必须是字符串或 null")
        if task_id:
            if cur not in ("pending", "adopted"):
                raise _Err(400, f"点子已是「{cur}」，不能再关联任务")
            idea["taskId"] = task_id
            idea["status"] = "adopted"
    if new_status is not None:
        idea["status"] = new_status
    if "dismissReason" in body:
        reason = body.get("dismissReason")
        if reason is not None and reason not in IDEA_DISMISS_REASONS:
            raise _Err(400, "dismissReason 不对")
        if reason is not None and idea["status"] != "dismissed":
            raise _Err(400, "只有忽略时可以标原因")
        idea["dismissReason"] = reason
    if idea.get("status", "pending") != cur:
        idea["statusAt"] = _now()
        # ID-2 (rev2 2.5): user outcomes feed the pool ledgers --
        # adoption is a terminal reward; a "too generic"
        # dismissal is the fast channel's negative signal
        if idea["status"] == "adopted":
            _record_idea_feedback_locked(idea, "terminal", "adopt")
        elif idea["status"] == "dismissed" \
                and idea.get("dismissReason") == "tooGeneric":
            _record_idea_feedback_locked(idea, "fast", "tooGeneric")
    _save_locked()
    return _idea_view(idea)


def _expire_ideas_locked() -> int:
    """Mark overdue generated pending cards expired (lock held).

    Expiry is settled here, on the reconcile tick, and persisted --
    not computed at read time -- so the stored status is the single
    truth the App mirrors. adopted/manual cards never expire."""
    now = _now()
    n = 0
    for idea in _db["ideas"]:
        if idea.get("status", "pending") == "pending" \
                and idea.get("expiresAt") is not None \
                and idea["expiresAt"] <= now:
            idea["status"] = "expired"
            idea["statusAt"] = now
            n += 1
    # ID-2: dead-anchor cards retire in the same tick sweep
    n += _retire_dead_anchor_ideas_locked()
    # ID-2 migration (rev2 2.11): a pool that predates snapshots
    # gets its first one here, so existing cards join the pool
    # form without waiting for the next generation round
    pool = _pool_meta_locked()
    bootstrapped = False
    if pool.get("activeSnapshotId") is None and any(
            i.get("source") == "generated"
            and i.get("status", "pending") == "pending"
            for i in _db["ideas"]):
        _build_ideas_snapshot_locked("bootstrap")
        bootstrapped = True
    if n or bootstrapped:
        _save_locked()
    return n


def _delete_idea(iid: str) -> None:
    if not any(i["id"] == iid for i in _db["ideas"]):
        raise _Err(404, "点子不存在")
    _db["ideas"] = [i for i in _db["ideas"] if i["id"] != iid]
    _save_locked()
