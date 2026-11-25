# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_automation.py -- part of modules/oneday_bridge.py,
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





# ------------------------------------------------- automation MCP facade
# AI internal powers P4 (automation) + P5 (reach), 2026-11-13.
# One MCP-shaped facade at POST /automation-mcp (same
# streamable-http JSON-RPC shape as the device bridge and the
# goals facade above) exposing six tools in three groups:
#
# cron_create / cron_list / cron_delete -- the agent's own
#   timers, built ON TOP of the Hermes cron engine through its
#   Dashboard REST API: no second scheduler is built here, jobs
#   land in the engine's own store and fire with its semantics.
#   Every facade-created job MUST carry an owner session: the
#   bridge keeps a binding (jobId -> ownerSessionId /
#   echoSessionId) and the watcher below folds each new run
#   into a P0 trace aimed back at that session, so an AI timer
#   can never become an ownerless machine session with no echo
#   (closure rule, 2026-11-11). Boundary with the standing
#   classification (C1): timers created elsewhere (CLI /
#   Dashboard panel / system jobs) are NOT in the binding
#   table -- their sessions stay system sessions filed under
#   the work ledger, untouched here; only facade-created,
#   owner-bound timers earn session echoes. deliver is pinned
#   to "local": the engine must not push cron output to any
#   external channel on the agent's behalf; the echo home is
#   the trace stream (and, once the App renders P0 echoes into
#   sessions, the owner session itself).
#
# kanban_create_task / kanban_get_task -- dispatch work on the
#   oneday board through the kanban plugin's Dashboard API (the
#   same board the ledger and the feed already read). A card
#   MUST name its owner session; the binding lets the watcher
#   book a completion trace against that session when the card
#   reaches a done state (P2 parity: the card is the parent
#   record, sessions the dispatcher spawns from it are its
#   children -- the child session id is recorded in the trace
#   detail when the board reports it). A card created with a
#   goalId ALSO sets the task's goalId field (the single
#   goal<->task association since 1.0.65), so the goal's
#   fact-only completion entry keeps working unchanged.
#   The kanban auto-reviewer is not touched.
#
# reach_send -- a proactive message to the user (P5). It rides
#   the EXISTING notification ledger (monitor-notifications
#   .jsonl, the overview bridge's notification feed) with kind
#   "agent_message"; no second notification system is built.
#   Every send names its sourceAction (the action that produced
#   it) and may name an echo session (refSessionId). Quiet-
#   hours guard (the Muse-side proactive window, Asia/Shanghai
#   [09:00, 21:30)): outside the window the message is QUEUED
#   in the bridge store and flushed by the watcher when the
#   window opens -- queued, never dropped. dryRun=true books
#   the trace only and never writes the ledger.
#
# Every tools/call writes exactly one P0 trace before answering
# (action namespaces cron.* / kanban.* / reach.*); the watcher
# adds cron.fired / cron.orphaned / kanban.completed /
# reach.delivered traces. Like the goals facade, this surface
# is built and verified here but NOT registered into Hermes --
# registration waits for the closing window.

AUTO_BOARD = "oneday"
AUTO_TICK_SECONDS = 60
#: proactive window [09:00, 21:30) in the scheduler timezone
PROACTIVE_OPEN_MIN = 9 * 60
PROACTIVE_CLOSE_MIN = 21 * 60 + 30
NOTIFY_TITLE_CAP = 120
NOTIFY_BODY_CAP = 300
PROACTIVE_QUEUE_KEEP = 200

# --- Hermes Dashboard channel (cookie login, cached) ----------
# The cron REST API and the kanban plugin API are Dashboard
# routes: they ride the same password-login cookie channel the
# board reader above already uses (HERMES_DASH_USER /
# HERMES_DASH_PASSWORD), NOT the Bearer API key. One login is
# cached and shared; a 401 earns exactly one re-login retry.
_dash_lock = threading.Lock()
_dash_opener = None


def _dash_login():
    global _dash_opener
    if not HERMES_DASH_USER or not HERMES_DASH_PASSWORD:
        raise _Err(503, "未配置 Dashboard 凭据，自动化门面待接通")
    import http.cookiejar
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar))
    status, _, _ = _http_json(
        HERMES_BASE_URL + "/auth/password-login",
        method="POST",
        body={"provider": "basic",
              "username": HERMES_DASH_USER,
              "password": HERMES_DASH_PASSWORD,
              "next": "/"},
        opener=opener)
    if status != 200:
        raise _Err(502, f"Dashboard 登录失败（HTTP {status}）")
    _dash_opener = opener
    return opener


def _dash_json(path: str, *, method: str = "GET", body=None):
    """One Dashboard API call on the cookie channel. Returns the
    parsed payload on 2xx; raises _Err with the upstream status
    (and its detail text, verbatim-capped) on anything else --
    failures surface, they are never folded into empty data."""
    with _dash_lock:
        opener = _dash_opener if _dash_opener is not None \
            else _dash_login()
        status, payload, _ = _http_json(
            HERMES_BASE_URL + path, method=method, body=body,
            opener=opener)
        if status == 401:
            opener = _dash_login()
            status, payload, _ = _http_json(
                HERMES_BASE_URL + path, method=method, body=body,
                opener=opener)
    if status not in (200, 201, 202):
        detail = ""
        if isinstance(payload, dict):
            detail = str(payload.get("detail")
                         or payload.get("error") or "")[:300]
        raise _Err(502, f"Hermes Dashboard {method} {path} 失败"
                        f"（HTTP {status}）"
                        + (f"：{detail}" if detail else ""))
    return payload


def _req_str(args: dict, key: str, label: str, cap: int) -> str:
    v = args.get(key)
    if not isinstance(v, str) or not v.strip():
        raise _Err(400, f"{label}不能为空")
    return v.strip()[:cap]


def _opt_str(args: dict, key: str, cap: int):
    v = args.get(key)
    if v is None:
        return None
    if not isinstance(v, str):
        raise _Err(400, f"{key} 必须是文本")
    return v.strip()[:cap] or None


# --- cron facade (P4 timers) -----------------------------------

def _cron_job_id(job: dict):
    jid = job.get("id") or job.get("job_id")
    return jid if isinstance(jid, str) and jid else None


def _cron_job_view(job: dict) -> dict:
    sched = job.get("schedule")
    return {
        "jobId": _cron_job_id(job),
        "name": job.get("name"),
        "schedule": sched,
        "prompt": str(job.get("prompt") or "")[:200],
        "paused": bool(job.get("paused")),
        "nextRunAt": job.get("next_run_at"),
        "lastRunAt": job.get("last_run_at"),
        "lastStatus": job.get("last_status"),
    }


def _auto_cron_create(args: dict):
    name = _req_str(args, "name", "任务名", 120)
    schedule = _req_str(args, "schedule", "schedule", 200)
    prompt = _req_str(args, "prompt", "prompt", 4000)
    owner = _req_str(args, "ownerSessionId", "归属会话 ownerSessionId",
                     200)
    echo = _opt_str(args, "echoSessionId", 200) or owner
    payload = {"name": name, "schedule": schedule,
               "prompt": prompt, "deliver": "local",
               "timezone": _opt_str(args, "timezone", 60)
               or "Asia/Shanghai"}
    repeat = args.get("repeat")
    if repeat is not None:
        payload["repeat"] = repeat
    if args.get("paused") is True:
        payload["paused"] = True
    raw = _dash_json("/api/cron/jobs", method="POST", body=payload)
    job = raw.get("job") if isinstance(raw, dict) else None
    if not isinstance(job, dict):
        job = raw if isinstance(raw, dict) else {}
    job_id = _cron_job_id(job)
    if not job_id:
        raise _Err(502, "Hermes cron 创建未返回任务 id")
    binding = {"jobId": job_id, "name": name,
               "ownerSessionId": owner, "echoSessionId": echo,
               "schedule": schedule, "createdAt": _now(),
               "seenLastRunAt": job.get("last_run_at")}
    with _lock:
        _db["cronBindings"].append(binding)
        _save_locked()
    view = _cron_job_view(job)
    view["ownerSessionId"] = owner
    view["echoSessionId"] = echo
    target = {"kind": "cron_job", "id": job_id, "label": name,
              "ref": f"hermes://cron/{job_id}"}
    return view, target, f"定时任务《{name}》已创建（{schedule}）"


def _auto_cron_list(args: dict):
    with _lock:
        bindings = [dict(b) for b in _db["cronBindings"]]
    items = []
    for b in bindings:
        item = {"jobId": b["jobId"], "name": b["name"],
                "schedule": b.get("schedule"),
                "ownerSessionId": b["ownerSessionId"],
                "echoSessionId": b.get("echoSessionId"),
                "createdAt": b.get("createdAt"), "missing": False}
        try:
            job = _dash_json(f"/api/cron/jobs/{b['jobId']}")
            if isinstance(job, dict):
                item.update(_cron_job_view(job))
        except _Err:
            item["missing"] = True
        items.append(item)
    target = {"kind": "cron_job", "id": "list",
              "label": "AI 定时任务", "ref": "hermes://cron"}
    return {"items": items, "count": len(items)}, target, \
        f"共 {len(items)} 个 AI 定时任务"


def _auto_cron_delete(args: dict):
    job_id = _req_str(args, "jobId", "jobId", 200)
    with _lock:
        binding = next((b for b in _db["cronBindings"]
                        if b["jobId"] == job_id), None)
    if binding is None:
        # The facade only ever deletes what it created: engine
        # jobs owned by the panel / CLI / system are out of its
        # reach by design (C1 boundary).
        raise _Err(400, "该定时任务不是 AI 门面所建，门面不代删")
    _dash_json(f"/api/cron/jobs/{job_id}", method="DELETE")
    with _lock:
        _db["cronBindings"] = [b for b in _db["cronBindings"]
                               if b["jobId"] != job_id]
        _save_locked()
    target = {"kind": "cron_job", "id": job_id,
              "label": binding["name"],
              "ref": f"hermes://cron/{job_id}"}
    return {"jobId": job_id, "deleted": True}, target, \
        f"定时任务《{binding['name']}》已删除"


# --- kanban facade (P4 dispatch) -------------------------------

def _kanban_task_view(task: dict) -> dict:
    return {
        "taskId": task.get("id"),
        "title": task.get("title"),
        "status": task.get("status"),
        "assignee": task.get("assignee"),
        "priority": task.get("priority"),
        "createdAt": task.get("created_at") or task.get("createdAt"),
        "sessionId": task.get("session_id")
        or task.get("sessionId"),
    }


def _auto_kanban_create(args: dict):
    title = _req_str(args, "title", "任务标题", 200)
    owner = _req_str(args, "ownerSessionId", "归属会话 ownerSessionId",
                     200)
    body = {"title": title}
    text = _opt_str(args, "body", 8000)
    if text:
        body["body"] = text
    assignee = _opt_str(args, "assignee", 120)
    if assignee:
        body["assignee"] = assignee
    prio = args.get("priority")
    if prio is not None:
        if not isinstance(prio, int) or isinstance(prio, bool):
            raise _Err(400, "priority 必须是整数")
        body["priority"] = prio
    parents = args.get("parents")
    if parents is not None:
        if not isinstance(parents, list) or not all(
                isinstance(p, str) and p for p in parents):
            raise _Err(400, "parents 必须是任务 id 数组")
        body["parents"] = parents
    idem = _opt_str(args, "idempotencyKey", 200)
    if idem:
        body["idempotency_key"] = idem
    goal_id = _opt_str(args, "goalId", 200)
    if goal_id:
        _find_goal(goal_id)  # refuse BEFORE the card exists
    raw = _dash_json(
        f"/api/plugins/kanban/tasks?board={AUTO_BOARD}",
        method="POST", body=body)
    task = raw.get("task") if isinstance(raw, dict) else None
    if not isinstance(task, dict):
        task = raw if isinstance(raw, dict) else {}
    task_id = task.get("id")
    if not isinstance(task_id, str) or not task_id:
        raise _Err(502, "kanban 建卡未返回任务 id")
    binding = {"taskId": task_id, "title": title,
               "ownerSessionId": owner, "goalId": goal_id,
               "createdAt": _now(),
               "lastStatus": task.get("status"),
               "doneTraced": False}
    with _lock:
        _db["kanbanBindings"].append(binding)
        if goal_id:
            # Ride the standing goal<->task chain so the
            # goal's fact-only completion entry keeps working:
            # since 1.0.65 that chain is the task's goalId
            # field itself (the link collection is retired).
            _set_task_goal_locked(task_id, goal_id, None)
        _save_locked()
    view = _kanban_task_view(task)
    view["ownerSessionId"] = owner
    view["board"] = AUTO_BOARD
    target = {"kind": "kanban_task", "id": task_id, "label": title,
              "ref": f"hermes://kanban/{AUTO_BOARD}/{task_id}"}
    return view, target, f"任务卡《{title}》已派到 {AUTO_BOARD} 板"


def _auto_kanban_get(args: dict):
    task_id = _req_str(args, "taskId", "taskId", 200)
    raw = _dash_json(
        f"/api/plugins/kanban/tasks/{task_id}?board={AUTO_BOARD}")
    task = raw.get("task") if isinstance(raw, dict) else None
    if not isinstance(task, dict):
        task = raw if isinstance(raw, dict) else {}
    if not task:
        raise _Err(404, "任务不存在")
    return _kanban_task_view(task), {
        "kind": "kanban_task", "id": task_id,
        "label": str(task.get("title") or task_id),
        "ref": f"hermes://kanban/{AUTO_BOARD}/{task_id}"}, \
        f"任务卡状态：{task.get('status')}"


# --- reach facade (P5 proactive messages) ----------------------

def _proactive_in_window(ts: float) -> bool:
    """Quiet-hours guard: [09:00, 21:30) in the scheduler
    timezone (Asia/Shanghai). Pure function of ts so the
    boundary is selftest-pinnable."""
    dt = datetime.fromtimestamp(ts, _sched_tz())
    minutes = dt.hour * 60 + dt.minute
    return PROACTIVE_OPEN_MIN <= minutes < PROACTIVE_CLOSE_MIN


def _append_agent_notification_locked(title: str, body: str,
                                      ref_session_id,
                                      record_id: str) -> None:
    """Append one agent_message record to the EXISTING
    notification ledger (the file the overview bridge reads).
    Overview's reader passes kind/title/body/id/createdAt
    through verbatim, so an agent message surfaces in the same
    notification center with no second system. Called under
    _lock (same discipline as _notify_locked); a failed append
    raises -- a send that cannot reach the ledger must fail
    loudly, never pretend delivery."""
    now = _now()
    digest = hashlib.sha256(
        f"{record_id}|{now}|{title}|{body}".encode("utf-8")
    ).hexdigest()[:12]
    record = {
        "id": f"msg-{digest}",
        "kind": "agent_message",
        "title": title[:NOTIFY_TITLE_CAP],
        "body": body[:NOTIFY_BODY_CAP],
        "createdAt": datetime.fromtimestamp(
            now, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "read": False,
        "refId": ref_session_id,
        "changeId": record_id,
    }
    path = DATA_PATH.parent / "monitor-notifications.jsonl"
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")


def _auto_reach_send(args: dict):
    text = _req_str(args, "text", "消息正文", 4000)
    source = _req_str(args, "sourceAction", "来源动作 sourceAction",
                      120)
    title = _opt_str(args, "title", NOTIFY_TITLE_CAP) or "Hermes"
    ref_session = _opt_str(args, "refSessionId", 200)
    record_id = _new_id("pq_", {q["id"] for q in _db["proactiveQueue"]}
                        | {t["id"] for t in _db["traces"]})
    if ref_session:
        target = {"kind": "session", "id": ref_session,
                  "label": title,
                  "ref": f"oneday://sessions/{ref_session}"}
    else:
        target = {"kind": "notification", "id": record_id,
                  "label": title, "ref": "oneday://notifications"}
    if args.get("dryRun") is True:
        return {"delivered": False, "dryRun": True,
                "queued": False, "recordId": record_id}, target, \
            "干跑：未发送，仅留痕（验证通道）"
    now = _now()
    if _proactive_in_window(now):
        with _lock:
            _append_agent_notification_locked(
                title, text, ref_session, record_id)
        return {"delivered": True, "queued": False,
                "recordId": record_id,
                "bodyTruncated": len(text) > NOTIFY_BODY_CAP}, \
            target, "主动消息已送达通知中心"
    with _lock:
        queue = _db["proactiveQueue"]
        queue.append({"id": record_id, "title": title,
                      "body": text[:NOTIFY_BODY_CAP],
                      "sourceAction": source,
                      "refSessionId": ref_session,
                      "queuedAt": now, "status": "queued",
                      "sentAt": None})
        sent = [q for q in queue if q.get("status") == "sent"]
        if len(sent) > PROACTIVE_QUEUE_KEEP:
            drop = {q["id"] for q in
                    sent[:len(sent) - PROACTIVE_QUEUE_KEEP]}
            _db["proactiveQueue"] = [
                q for q in queue if q["id"] not in drop]
        _save_locked()
    return {"delivered": False, "queued": True,
            "recordId": record_id}, target, \
        "静默时段（09:00–21:30 之外）：主动消息已排队，窗口开启后补发"


# --- automation watcher: run folds + queue flush ----------------
# One daemon thread, AUTO_TICK_SECONDS cadence. Network reads
# happen outside _lock; state folds under it. A tick failure is
# printed and the loop carries on (same discipline as the
# delivery sentinel): a dead watcher would silently break the
# closure promise, so it must be noisy, never fatal.

def _automation_tick() -> None:
    now = _now()
    # 1) flush queued proactive messages once the window opens
    if _proactive_in_window(now):
        with _lock:
            pending = [dict(q) for q in _db["proactiveQueue"]
                       if q.get("status") == "queued"]
        pending.sort(key=lambda q: q.get("queuedAt") or 0)
        for q in pending:
            with _lock:
                _append_agent_notification_locked(
                    q["title"], q["body"], q.get("refSessionId"),
                    q["id"])
                for row in _db["proactiveQueue"]:
                    if row["id"] == q["id"]:
                        row["status"] = "sent"
                        row["sentAt"] = now
                _save_locked()
            if q.get("refSessionId"):
                target = {"kind": "session",
                          "id": q["refSessionId"],
                          "label": q["title"],
                          "ref": "oneday://sessions/"
                                 + q["refSessionId"]}
            else:
                target = {"kind": "notification", "id": q["id"],
                          "label": q["title"],
                          "ref": "oneday://notifications"}
            _append_trace(
                "reach.delivered", target, "ok",
                result="静默时段排队的主动消息已补发",
                detail={"queueId": q["id"],
                        "sourceAction": q.get("sourceAction"),
                        "queuedAt": q.get("queuedAt")})
    # 2) cron bindings: fold each job's newest run into a trace
    with _lock:
        bindings = [dict(b) for b in _db["cronBindings"]]
    for b in bindings:
        try:
            raw = _dash_json(f"/api/cron/jobs/{b['jobId']}")
        except _Err as e:
            if "HTTP 404" in e.message:
                with _lock:
                    _db["cronBindings"] = [
                        x for x in _db["cronBindings"]
                        if x["jobId"] != b["jobId"]]
                    _save_locked()
                _append_trace(
                    "cron.orphaned",
                    {"kind": "cron_job", "id": b["jobId"],
                     "label": b["name"],
                     "ref": f"hermes://cron/{b['jobId']}"},
                    "failed",
                    error="Hermes cron 任务不存在（可能已在面板"
                          "删除），绑定已清除",
                    detail={"ownerSessionId": b["ownerSessionId"]})
            else:
                print(f"automation: cron poll {b['jobId']} failed:"
                      f" {e.message}", file=sys.stderr)
            continue
        job = raw.get("job") if isinstance(raw, dict) else None
        if not isinstance(job, dict):
            job = raw if isinstance(raw, dict) else {}
        last_run = job.get("last_run_at")
        if not last_run or last_run == b.get("seenLastRunAt"):
            continue
        status = str(job.get("last_status") or "")
        target = {"kind": "cron_job", "id": b["jobId"],
                  "label": b["name"],
                  "ref": f"hermes://cron/{b['jobId']}"}
        detail = {"ownerSessionId": b["ownerSessionId"],
                  "echoSessionId": b.get("echoSessionId"),
                  "lastRunAt": last_run,
                  "nextRunAt": job.get("next_run_at"),
                  "lastStatus": status}
        if status == "ok":
            _append_trace("cron.fired", target, "ok",
                          result=f"定时任务《{b['name']}》已触发"
                                 f"（{last_run}）",
                          detail=detail)
        else:
            err = job.get("last_error") or job.get("error") \
                or f"运行状态 {status or '未知'}"
            _append_trace("cron.fired", target, "failed",
                          error=str(err)[:TRACE_ERROR_CAP],
                          detail=detail)
        with _lock:
            for row in _db["cronBindings"]:
                if row["jobId"] == b["jobId"]:
                    row["seenLastRunAt"] = last_run
            _save_locked()
    # 3) kanban bindings: fold completions into traces
    with _lock:
        kbindings = [dict(b) for b in _db["kanbanBindings"]
                     if not b.get("doneTraced")]
    if kbindings:
        tasks, _note = _fetch_kanban_tasks()
        for b in kbindings:
            found = tasks.get(b["taskId"])
            if not found:
                continue
            title, state = found
            if str(state).lower() not in _KANBAN_DONE_STATUSES:
                continue
            _append_trace(
                "kanban.completed",
                {"kind": "kanban_task", "id": b["taskId"],
                 "label": title or b["title"],
                 "ref": f"hermes://kanban/{AUTO_BOARD}/"
                        f"{b['taskId']}"},
                "ok",
                result=f"任务《{title or b['title']}》已完成",
                detail={"ownerSessionId": b["ownerSessionId"],
                        "goalId": b.get("goalId"),
                        "status": state})
            with _lock:
                for row in _db["kanbanBindings"]:
                    if row["taskId"] == b["taskId"]:
                        row["doneTraced"] = True
                        row["lastStatus"] = state
                _save_locked()


def _automation_loop() -> None:
    while True:
        time.sleep(AUTO_TICK_SECONDS)
        try:
            _automation_tick()
        except Exception as e:
            print(f"automation tick failed: "
                  f"{type(e).__name__}: {e}", file=sys.stderr)


def _automation_start() -> None:
    threading.Thread(target=_automation_loop, name="automation",
                     daemon=True).start()
    print("automation watcher started", file=sys.stderr)


AUTOMATION_TOOLS = [
    {"name": "cron_create",
     "description": "新建一个 AI 定时任务（落在 Hermes cron 引擎上，"
                    "不是另造的调度器）。归属会话必填：任务每次触发"
                    "都会在留痕流里回响到归属会话，不产生无主的机器"
                    "会话。schedule 用引擎口径：cron 表达式（如 "
                    "0 9 * * 1）、间隔（如 every 2h）或一次性时间。",
     "inputSchema": {
         "type": "object",
         "properties": {
             "name": {"type": "string", "description": "任务名"},
             "schedule": {"type": "string",
                          "description": "cron 表达式 / every 间隔"
                                         " / 一次性时间"},
             "prompt": {"type": "string",
                        "description": "触发时执行的指令"},
             "ownerSessionId": {"type": "string",
                                "description": "归属会话 id（必填，"
                                               "回响落点）"},
             "echoSessionId": {"type": "string",
                               "description": "回响会话 id（缺省="
                                              "归属会话）"},
             "repeat": {"description": "重复次数：整数或 once / "
                                       "forever（缺省不限）"},
             "timezone": {"type": "string",
                          "description": "IANA 时区（缺省 "
                                         "Asia/Shanghai）"},
             "paused": {"type": "boolean",
                        "description": "建后先暂停（缺省 false）"}},
         "required": ["name", "schedule", "prompt",
                      "ownerSessionId"]}},
    {"name": "cron_list",
     "description": "列出 AI 门面所建的全部定时任务（含下次/上次"
                    "运行状态）。面板或命令行建的任务不在此列。",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "cron_delete",
     "description": "删除一个 AI 门面所建的定时任务。不是门面所建"
                    "的任务会被拒绝（不代删他人/系统任务）。",
     "inputSchema": {
         "type": "object",
         "properties": {
             "jobId": {"type": "string", "description": "任务 id"}},
         "required": ["jobId"]}},
    {"name": "kanban_create_task",
     "description": "在 oneday 任务板上派一张活卡。归属会话必填："
                    "卡完成时回响到归属会话。带 goalId 时同时挂进"
                    "目标的任务关联链（完成自动记一条目标进展）。",
     "inputSchema": {
         "type": "object",
         "properties": {
             "title": {"type": "string", "description": "任务标题"},
             "body": {"type": "string", "description": "任务说明"},
             "assignee": {"type": "string",
                          "description": "执行者（缺省由调度分派）"},
             "priority": {"type": "integer", "description": "优先级"},
             "parents": {"type": "array",
                         "items": {"type": "string"},
                         "description": "父任务 id（父子关系）"},
             "ownerSessionId": {"type": "string",
                                "description": "归属会话 id（必填，"
                                               "回响落点）"},
             "goalId": {"type": "string",
                        "description": "关联目标 id（可选）"},
             "idempotencyKey": {"type": "string",
                                "description": "幂等键（重试不建重卡"
                                               "时传）"}},
         "required": ["title", "ownerSessionId"]}},
    {"name": "kanban_get_task",
     "description": "查一张任务卡的当前状态。",
     "inputSchema": {
         "type": "object",
         "properties": {
             "taskId": {"type": "string", "description": "任务 id"}},
         "required": ["taskId"]}},
    {"name": "reach_send",
     "description": "给用户发一条主动消息（进通知中心）。必带来源"
                    "动作 sourceAction。主动时段 09:00–21:30 之外"
                    "自动排队、窗口开启补发，不丢。dryRun=true 只"
                    "留痕不发送（验证用）。正文在通知里最多显示 "
                    "300 字。",
     "inputSchema": {
         "type": "object",
         "properties": {
             "text": {"type": "string", "description": "消息正文"},
             "title": {"type": "string",
                       "description": "标题（缺省 Hermes）"},
             "sourceAction": {"type": "string",
                              "description": "来源动作（必填，如 "
                                             "cron.fired / 目标巡检）"},
             "refSessionId": {"type": "string",
                              "description": "回响/点达会话 id"},
             "dryRun": {"type": "boolean",
                        "description": "只留痕不发送"}},
         "required": ["text", "sourceAction"]}},
]

_AUTOMATION_RUNNERS = {
    "cron_create": ("cron.create", _auto_cron_create),
    "cron_list": ("cron.list", _auto_cron_list),
    "cron_delete": ("cron.delete", _auto_cron_delete),
    "kanban_create_task": ("kanban.create_task",
                           _auto_kanban_create),
    "kanban_get_task": ("kanban.get_task", _auto_kanban_get),
    "reach_send": ("reach.send", _auto_reach_send),
}


def _automation_tool_call(name, args) -> dict:
    """Execute one automation tool and ALWAYS book its P0 trace
    before answering (same law as the goals facade): success
    books the summary sentence, failure books the error text
    verbatim. A trace that itself fails raises -- the caller
    turns it into a visible error, never a silent success."""
    entry = _AUTOMATION_RUNNERS.get(name)
    if entry is None:
        return {"content": [{"type": "text",
                             "text": f"未知工具：{name}"}],
                "isError": True}
    action, runner = entry
    try:
        result, target, summary = runner(args)
    except _Err as e:
        _append_trace(action, None, "failed", error=e.message,
                      detail={"tool": name})
        return {"content": [{"type": "text", "text": e.message}],
                "isError": True}
    except Exception as e:  # keep the verbatim cause in the trace
        print(f"automation tool {name} crashed: "
              f"{type(e).__name__}: {e}", file=sys.stderr)
        _append_trace(action, None, "failed",
                      error=f"{type(e).__name__}: {e}",
                      detail={"tool": name})
        return {"content": [{"type": "text",
                             "text": "服务器内部错误"}],
                "isError": True}
    _append_trace(action, target, "ok", result=summary,
                  detail={"tool": name})
    return {"content": [{"type": "text", "text": json.dumps(
        result, ensure_ascii=False)}]}


def _briefing_view(b: dict) -> dict:
    return {
        "id": b["id"],
        "goalId": b["goalId"],
        "period": b["period"],
        "title": b["title"],
        "body": b["body"],
        "createdAt": b["createdAt"],
        # GD-3: pre-GD-3 records carry neither key; read as
        # null, never back-filled with a guess.
        "note": b.get("note"),
        "lastOpenedAt": b.get("lastOpenedAt"),
    }


def _list_briefings(gid: str) -> list:
    _find_goal(gid)
    items = [b for b in _db["briefings"] if b["goalId"] == gid]
    items.sort(key=lambda b: b["createdAt"], reverse=True)
    return [_briefing_view(b) for b in items]


def _mark_briefing_opened(gid: str, bid: str) -> dict:
    """GD-3: the App opened one letter -> stamp lastOpenedAt.

    Ledger visibility only ("written but never read" is a fact
    the work ledger may show); this stamp drives no badge, no
    unread count and no nag anywhere. Re-opening re-stamps: the
    field means "last opened at", verbatim."""
    _find_goal(gid)
    rec = next((b for b in _db["briefings"]
                if b["id"] == bid and b["goalId"] == gid), None)
    if rec is None:
        raise _Err(404, "简报不存在")
    rec["lastOpenedAt"] = _now()
    _save_locked()
    return _briefing_view(rec)
