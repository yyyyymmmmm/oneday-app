# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_briefings.py -- part of modules/oneday_gateway.py,
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




# --- goal weekly briefings (P2) ----------------------------------------------
# Same paradigm as idea generation: bridge-internal scheduling on
# the 20s tick, read-only material assembly, one /v1/runs call per
# goal, strict validation before storing, a persisted ledger
# (meta.briefGen.history). Differences: weekly cadence (Mondays
# 08:00 Asia/Shanghai), per-goal letters instead of one batch, and
# a goal with no material is SKIPPED and counted -- the pipeline
# never pads a quiet week into a letter (facts gate).

BRIEF_WEEKDAY = 0                     # Monday
BRIEF_HOUR, BRIEF_MINUTE = 8, 0       # Asia/Shanghai
BRIEF_HISTORY_KEEP = 30
BRIEF_GOALS_PER_ROUND = 20

GOAL_BRIEF_PROMPT = """你是 OneDay 的目标简报员。OneDay 是用户自托管的 AI 助手 App；目标页是用户长期目标的档案，你每周为其中一个目标写一封短信。

根据下面给定的素材，为这个目标写本周简报，输出一个 JSON 对象，字段：
- title：一句话标题，说清本周要点，不超过 40 字。
- body：正文，像一封短信：先说本周实际发生的进展（只用素材里的事实），再说当前状态（里程碑走到哪、关联任务什么状态、挂靠监测有没有变化），最后给一句下一步建议（只许建议，不许替用户做决定）。3 到 6 段、段落简短，总长不超过 600 字。

硬规则：
- 只输出一个 JSON 对象，不要任何解释文字、不要 Markdown 代码围栏。
- 只依据给定素材作答：素材里没有的事一个字都不许编——不许虚构完成、虚构日期、虚构用户做过的事。
- 素材单薄就如实写单薄（例如「本周只有一条进展记录」），不许注水凑篇幅。
- 不要调用工具，不要读写文件、记忆或网络。

素材：
"""

_briefing = False
_briefing_lock = threading.Lock()


def _brief_meta_locked() -> dict:
    gen = _db["meta"].setdefault("briefGen", {})
    gen.setdefault("lastRunAt", None)
    gen.setdefault("nextRunAt", None)
    gen.setdefault("history", [])
    return gen


def _brief_record_locked(rec: dict) -> None:
    gen = _brief_meta_locked()
    gen["history"].append(rec)
    gen["history"] = gen["history"][-BRIEF_HISTORY_KEEP:]
    gen["lastRunAt"] = rec["at"]
    _save_locked()
    _ledger_job_finish("briefing", rec)


def _next_brief_time(after_epoch: float) -> float:
    tz = _sched_tz()
    dt = datetime.fromtimestamp(after_epoch, tz=tz)
    cand = dt.replace(hour=BRIEF_HOUR, minute=BRIEF_MINUTE,
                      second=0, microsecond=0)
    delta = (BRIEF_WEEKDAY - cand.weekday()) % 7
    cand += timedelta(days=delta)
    if cand.timestamp() <= after_epoch:
        cand += timedelta(days=7)
    return cand.timestamp()


def _brief_period(at_epoch: float) -> str:
    iso = datetime.fromtimestamp(at_epoch, tz=_sched_tz()).isocalendar()
    return f"{iso[0]}-W{iso[1]:02d}"


_kanban_session_opener = None


def _kanban_parse(payload) -> tuple:
    """(tasks, saw_container): flatten a board payload into the
    id -> (title, status) map; saw_container records whether any
    tasks/columns container was recognised at all."""
    raw_tasks = []
    saw_container = False

    def _collect(node):
        nonlocal saw_container
        if isinstance(node, dict):
            t = node.get("tasks")
            if isinstance(t, list):
                saw_container = True
                raw_tasks.extend(x for x in t if isinstance(x, dict))
            for key in ("columns",):
                sub = node.get(key)
                if isinstance(sub, dict):
                    saw_container = True
                    for col in sub.values():
                        _collect(col)
                elif isinstance(sub, list):
                    saw_container = True
                    for col in sub:
                        _collect(col)

    _collect(payload)
    tasks = {}
    for t in raw_tasks:
        tid = t.get("id")
        if isinstance(tid, str) and tid:
            tasks[tid] = (str(t.get("title") or "")[:80],
                          str(t.get("status") or ""))
    return tasks, saw_container


def _kanban_board_fetch(opener=None, headers=None):
    return _http_json(
        HERMES_DASH_BASE_URL + "/api/plugins/kanban/board?board=oneday",
        opener=opener, headers=headers)


def _fetch_kanban_tasks() -> tuple:
    """(tasks, note): current oneday-board task states via the
    Dashboard cookie channel (same login contract as the ledger
    Dashboard channel). tasks maps task id -> (title, status).
    Read-only; on failure returns ({}, reason) and the round notes
    the gap in its ledger -- task titles still come from the
    bridge's own idea records, states are then omitted rather
    than guessed.

    G-3b (2026-11-24): the Dashboard session is cached and reused
    across polls (the poll interval dropped from 300 s to 15 s;
    logging in on every poll would churn a login each round). A
    cached session that stops yielding a recognisable board falls
    back to exactly one fresh login, and every failure note keeps
    its pre-G-3b wording."""
    global _kanban_session_opener
    if _dash_token_mode():
        # C-3: token mode needs no session at all.
        status, payload, _ = _kanban_board_fetch(
            headers=_dash_bearer_headers())
        if status != 200 or not isinstance(payload, dict):
            return {}, f"任务板读取失败（HTTP {status}）"
        tasks, saw_container = _kanban_parse(payload)
        if not tasks:
            if saw_container:
                return {}, "任务板为空"
            return {}, "任务板格式不对"
        return tasks, None
    if not HERMES_DASH_USER or not HERMES_DASH_PASSWORD:
        return {}, "未配置 Dashboard 凭据"
    if _kanban_session_opener is not None:
        status, payload, _ = _kanban_board_fetch(
            _kanban_session_opener)
        if status == 200 and isinstance(payload, dict):
            tasks, saw_container = _kanban_parse(payload)
            if saw_container:
                if not tasks:
                    return {}, "任务板为空"
                return tasks, None
        _kanban_session_opener = None
    import http.cookiejar
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar))
    status, _, _ = _http_json(
        HERMES_DASH_BASE_URL + "/auth/password-login",
        method="POST",
        body={"provider": "basic",
              "username": HERMES_DASH_USER,
              "password": HERMES_DASH_PASSWORD,
              "next": "/"},
        opener=opener)
    if status != 200:
        return {}, f"Dashboard 登录失败（HTTP {status}）"
    _kanban_session_opener = opener
    status, payload, _ = _kanban_board_fetch(opener)
    if status != 200 or not isinstance(payload, dict):
        return {}, f"任务板读取失败（HTTP {status}）"
    tasks, saw_container = _kanban_parse(payload)
    if not tasks:
        if saw_container:
            return {}, "任务板为空"
        return {}, "任务板格式不对"
    return tasks, None


def _assemble_brief_material(goal: dict, snap: dict,
                             tasks: dict) -> tuple:
    """(prompt_text, has_material): one goal's read-only material.
    snap carries the db slices taken under the lock; tasks is the
    kanban id->(title,status) map fetched outside it."""
    tz = _sched_tz()
    cutoff = _now() - 7 * 24 * 3600
    gid = goal["id"]
    entries = [e for e in snap["entries"]
               if e["goalId"] == gid
               and e["createdAt"] >= cutoff]
    entries.sort(key=lambda e: e["createdAt"])
    adopted = [i for i in snap["ideas"]
               if i.get("goalId") == gid and i.get("taskId")]
    monitors = {m["id"]: m for m in snap["monitors"]
                if m.get("goalId") == gid}
    changes = [c for c in snap["changes"]
               if c["monitorId"] in monitors
               and c["detectedAt"] >= cutoff]
    changes.sort(key=lambda c: c["detectedAt"])
    has_material = bool(entries or adopted or changes)
    # GD-3: the letter's material composition, counted from
    # the very slices above -- the briefing record's `note`
    # is assembled from these numbers by code, so the note
    # can never disagree with the material the letter used.
    counts = {"entries": len(entries), "tasks": len(adopted),
              "changes": len(changes)}

    # G-6 (2026-11-24): milestones removed -- the letter's goal
    # header no longer carries a milestone count line.
    parts = [GOAL_BRIEF_PROMPT]
    parts.append("## 目标")
    parts.append(f"《{goal['title'][:80]}》")
    note = (goal.get("note") or "").strip()
    if note:
        parts.append(f"备注：{note[:120]}")
    parts.append("## 近 7 天进展条目（逐条记的事实）")
    if entries:
        for e in entries[:12]:
            day = datetime.fromtimestamp(e["createdAt"], tz=tz)
            who = "用户" if e.get("source") == "user" else "智能体"
            parts.append(f"- {day.strftime('%m-%d')} [{who}] "
                         f"{e['body'][:200]}")
    else:
        parts.append("（无）")
    parts.append("## 关联任务（由本目标下的点子采纳生成）")
    if adopted:
        for i in adopted[:8]:
            title, state = tasks.get(i["taskId"], (None, None))
            label = title or i["title"][:60]
            parts.append(f"- 《{label}》"
                         + (f"：状态 {state}" if state
                            else "：（任务板状态未取到）"))
    else:
        parts.append("（无）")
    parts.append("## 挂靠监测近 7 天变化")
    if changes:
        for c in changes[:8]:
            day = datetime.fromtimestamp(c["detectedAt"], tz=tz)
            name = monitors.get(c["monitorId"], {}).get(
                "name", "监测")
            parts.append(f"- {day.strftime('%m-%d')} 《{name}》："
                         f"{c['summary'][:80]}")
    else:
        parts.append("（无）")
    return "\n\n".join(parts), has_material, counts


def _briefing_note(counts: dict):
    """GD-3 short note (rev2 ch.3 item 3): the letter's
    material composition in one quiet line, assembled BY CODE
    from the material counts -- never model-written. Fixed
    template: 「依据近 7 天 X 条进展、Y 项任务变化、Z 条监测
    变化」; a class is named only when its count is non-zero,
    and the note is null when all three are zero (such a
    letter is not produced in the first place -- the material
    gate skips it -- so null is the belt-and-braces case)."""
    bits = []
    if counts.get("entries"):
        bits.append(f"{counts['entries']} 条进展")
    if counts.get("tasks"):
        bits.append(f"{counts['tasks']} 项任务变化")
    if counts.get("changes"):
        bits.append(f"{counts['changes']} 条监测变化")
    if not bits:
        return None
    return "依据近 7 天" + "、".join(bits)


def _parse_briefing(output: str) -> tuple:
    """(letter, error): strict-fold one briefing run's output."""
    text = output.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None, "产出不是 JSON 对象"
    try:
        item = json.loads(text[start:end + 1])
    except Exception:
        return None, "产出 JSON 解析失败"
    if not isinstance(item, dict):
        return None, "产出不是 JSON 对象"
    title = str(item.get("title") or "").strip()
    body = str(item.get("body") or "").strip()
    if not title or not body:
        return None, "产出缺标题或正文"
    return {"title": title[:120], "body": body[:4000]}, None


def _run_briefing_round(trigger: str) -> None:
    """One weekly round, on its own thread (never under _lock)."""
    global _briefing
    started = _now()
    period = _brief_period(started)
    rec = {"at": started, "trigger": trigger, "period": period,
           "status": "failed", "produced": 0, "skippedNoMaterial": 0,
           "alreadyExists": 0, "skippedGoalGone": 0,
           "outcomes": [], "error": None}
    try:
        if not HERMES_API_KEY:
            rec["status"] = "skipped"
            rec["error"] = "未配置 HERMES_API_KEY，简报管道待接通"
            return
        with _lock:
            snap = {
                "goals": [dict(g) for g in _db["goals"]
                          if _goal_status(g) == "active"
                          and not g.get("parentId")],
                "entries": list(_db["goalEntries"]),
                "ideas": list(_db["ideas"]),
                "monitors": list(_db["monitors"]),
                "changes": list(_db["changes"]),
                "briefings": list(_db["briefings"]),
            }
        tasks, task_note = _fetch_kanban_tasks()
        if task_note:
            # Ledger-only, never into material (P1 lesson).
            rec["materialNote"] = task_note
        done_pairs = {(b["goalId"], b["period"])
                      for b in snap["briefings"]}
        errors = 0
        for goal in snap["goals"][:BRIEF_GOALS_PER_ROUND]:
            gid = goal["id"]
            outcome = {"goalId": gid, "result": ""}
            if (gid, period) in done_pairs:
                outcome["result"] = "already-exists"
                rec["alreadyExists"] += 1
                rec["outcomes"].append(outcome)
                continue
            prompt, has_material, mat_counts = \
                _assemble_brief_material(goal, snap, tasks)
            if not has_material:
                outcome["result"] = "skipped-no-material"
                rec["skippedNoMaterial"] += 1
                rec["outcomes"].append(outcome)
                continue
            run_id, err = _hermes_submit_run(
                prompt, f"goal-brief-{period}-{gid}")
            if err:
                outcome["result"] = "failed"
                outcome["error"] = err
                errors += 1
                rec["outcomes"].append(outcome)
                continue
            output, err = _hermes_poll_run(run_id)
            if err:
                outcome["result"] = "failed"
                outcome["error"] = err
                errors += 1
                rec["outcomes"].append(outcome)
                continue
            letter, perr = _parse_briefing(output)
            if perr:
                outcome["result"] = "failed"
                outcome["error"] = perr
                errors += 1
                rec["outcomes"].append(outcome)
                continue
            with _lock:
                # Re-check under the lock: a parallel manual round
                # cannot double-write the same (goal, period).
                # GD-4 cascade check (2026-11-14): the goal may
                # have been deleted while this round was in
                # flight (the snapshot was taken at round
                # start); its briefings were cascade-removed
                # with it, so landing a fresh one now would
                # orphan a briefing row on a dead goal -- skip.
                if not any(g["id"] == gid for g in _db["goals"]):
                    outcome["result"] = "skipped-goal-gone"
                    rec["skippedGoalGone"] += 1
                elif any(b["goalId"] == gid
                         and b["period"] == period
                         for b in _db["briefings"]):
                    outcome["result"] = "already-exists"
                    rec["alreadyExists"] += 1
                else:
                    _db["briefings"].append({
                        "id": _new_id(
                            "b_", {b["id"] for b in _db["briefings"]}),
                        "goalId": gid,
                        "period": period,
                        "title": letter["title"],
                        "body": letter["body"],
                        "createdAt": _now(),
                        # GD-3: code-counted material note +
                        # opened stamp (null until the App
                        # opens the letter).
                        "note": _briefing_note(mat_counts),
                        "lastOpenedAt": None,
                    })
                    _save_locked()
                    outcome["result"] = "produced"
                    rec["produced"] += 1
            rec["outcomes"].append(outcome)
        # §475 part 2: the roster is exhausted -- every
        # briefing this round will ever land has landed and
        # saved (each goal lands inside the loop above; the
        # loop exit IS this round's delivery-complete point).
        # Settle here unless the round is a pure failure
        # (nothing landed AND at least one goal errored):
        # that outcome belongs to the finish path, which
        # books it failed. produced > 0 with some goals
        # errored is "partial", which settles completed.
        if rec["produced"] or not errors:
            _ledger_job_delivered("briefing", rec["produced"])
        if rec["produced"]:
            rec["status"] = "partial" if errors else "ok"
        elif errors:
            rec["status"] = "failed"
            rec["error"] = f"{errors} 个目标生成失败（见 outcomes）"
        else:
            rec["status"] = "empty"
    except Exception as e:  # a round must never kill the scheduler
        rec["error"] = f"{type(e).__name__}: {e}"[:200]
    finally:
        with _lock:
            _brief_record_locked(rec)
            if trigger == "schedule":
                _brief_meta_locked()["nextRunAt"] = \
                    _next_brief_time(_now())
                _save_locked()
        with _briefing_lock:
            _briefing = False
        _print(f"goal briefings ({trigger}): {rec['status']} "
              f"produced={rec['produced']} "
              f"skipped={rec['skippedNoMaterial']} "
              f"error={rec['error']}", flush=True)


def _start_briefing(trigger: str) -> bool:
    """Start a briefing round on a thread; False when one is live."""
    global _briefing
    with _briefing_lock:
        if _briefing:
            return False
        _briefing = True
    _ledger_job_start("briefing")
    t = threading.Thread(target=_run_briefing_round,
                         args=(trigger,), daemon=True)
    t.start()
    return True


# _briefing_tick retired in 1.0.59 (B-01): the Hermes cron
# engine fires the weekly round via /internal/cron/rounds/briefing;
# meta.briefGen.nextRunAt is display bookkeeping that the round
# itself advances in its finally block (trigger == "schedule").


def _briefing_ledger_view() -> dict:
    with _lock:
        gen = _brief_meta_locked()
        return {
            "lastRunAt": gen["lastRunAt"],
            "nextRunAt": gen["nextRunAt"],
            "running": _briefing,
            "history": list(gen["history"]),
        }

# --- brief: two layers (0.38.0, spec v2 addendum) ---------------------------
# meta.brief has always been the shared direction text the
# generation pipelines consume; the two-layer brief makes it
# the EXECUTION layer. The user writes only their interests in
# their own words (meta.briefInterest); an expansion run then
# maintains the execution prompt from them. The layers are
# stored and shown separately; the execution layer stays
# directly editable (a PUT {"brief": ...} sets it verbatim and
# counts as a true brief change). Saving a truly-changed
# interest starts an expansion; when the expansion lands a
# changed execution prompt, a research round follows at once
# (the spec's "change the brief, get a post" beat).
#
# Single-layer ruling (user, 2026-11-24 04:36, DESIGN §459):
# what the user SAVES is stored verbatim -- the save itself
# never rewrites anything; the background expansion then
# polishes it, and the polished text is written back
# (meta.briefPolished, keyed to the exact interest text it was
# expanded from). The document's "text" field is the ONE
# user-facing layer: the polished text once the expansion for
# the current interest has landed, the user's own words until
# then -- never a polished text presented as if it existed
# before it landed, and never the original dressed up as
# polished. The two stored layers stay as the audit trail
# (the user's words are never overwritten by the polish).

BRIEF_INTEREST_LIMIT = 2000
BRIEF_PROMPT_LIMIT = 4000

BRIEF_EXPAND_PROMPT = """你是 OneDay 的简报整理者。用户用自己的话写下了他感兴趣什么（可能粗略、口语化）；你要把它扩写、维护成一份给调研生成链执行的正式简报（执行提示词）。

要求：
- 保留用户写下的全部方向与口径（语言、取舍标准、明确不要的东西），一个方向都不许丢，也不许自创用户没写的方向。
- 每个方向补齐：具体关注什么、什么样算有实质进展、什么样的内容不要（营销号／割韭菜类按用户口径排除）。
- 若给了上一版执行简报，在它基础上维护：用户新增的方向补进去，删掉的方向移除，口径变化按新的来。
- 只输出简报正文本身，不要标题、不要解释、不要 Markdown 代码围栏。

用户兴趣原文：
"""

_brief_expanding = False
_brief_expand_lock = threading.Lock()


def _brief_text_locked() -> tuple:
    """(text, polished, polish_state): the single user-facing
    brief text under the 2026-11-24 ruling. The polished text
    is served only when the landed expansion was expanded
    from EXACTLY the current interest text; any re-edit makes
    the polish stale and the user's own words come back until
    the new expansion lands. With no interest layer in play
    (execution layer set directly), the execution text is the
    user's text and counts as final."""
    meta = _db["meta"]
    interest = str(meta.get("briefInterest", "") or "")
    brief = str(meta.get("brief", "") or "")
    if not interest.strip():
        return brief, bool(brief.strip()), "idle"
    polished = meta.get("briefPolished") or {}
    if polished.get("forInterest") == interest \
            and str(polished.get("text") or "").strip():
        return str(polished["text"]), True, "done"
    if _brief_expanding:
        return interest, False, "pending"
    expand = meta.get("briefExpand") or {}
    if expand.get("lastError"):
        return interest, False, "error"
    # Batch 3 semantics split: "pending" means an expansion is
    # actually in flight (the _brief_expanding case above). An
    # interest layer that was never expanded for its current
    # text -- e.g. written directly by the section-459 data
    # migration, which does not pass the save path -- is NOT
    # pending: nothing is running, the user's own words are
    # simply the current text ("idle"), and the reconcile
    # backstop (_brief_polish_backstop) starts the expansion.
    return interest, False, "idle"


def _brief_doc_locked() -> dict:
    meta = _db["meta"]
    expand = meta.get("briefExpand") or {}
    text, polished, polish_state = _brief_text_locked()
    return {
        "brief": str(meta.get("brief", "") or ""),
        "interest": str(meta.get("briefInterest", "") or ""),
        # §459 single-layer surface: "text" is what the
        # editor shows and what a save writes back (as the
        # interest layer, verbatim); "polished" says whether
        # it is already the background-polished version.
        "text": text,
        "polished": polished,
        "polishState": polish_state,
        "briefUpdatedAt": meta.get("briefUpdatedAt"),
        "interestUpdatedAt": meta.get("briefInterestUpdatedAt"),
        "expanding": _brief_expanding,
        "expandError": expand.get("lastError"),
    }


def _run_brief_expand(interest: str) -> None:
    """One expansion run, on its own thread. Lands only when
    the interest it expanded is still the current one (the
    user may have re-edited meanwhile); a landed CHANGE of the
    execution prompt triggers a research round."""
    global _brief_expanding
    try:
        with _lock:
            expand = _db["meta"].setdefault("briefExpand", {})
            expand["forInterest"] = interest
            expand["lastRunAt"] = _now()
            _save_locked()
        if not HERMES_API_KEY:
            with _lock:
                expand = _db["meta"].setdefault("briefExpand", {})
                expand["lastError"] = \
                    "未配置 HERMES_API_KEY，简报整理待接通"
                expand["lastRunAt"] = _now()
                _save_locked()
            return
        with _lock:
            prev = str(_db["meta"].get("brief", "") or "")
        prompt = BRIEF_EXPAND_PROMPT \
            + interest.strip()[:BRIEF_INTEREST_LIMIT]
        if prev.strip():
            prompt += "\n\n上一版执行简报：\n" \
                + prev.strip()[:BRIEF_PROMPT_LIMIT]
        run_id, err = _hermes_submit_run(
            prompt, f"feed-brief-expand-{int(_now())}")
        if err:
            raise RuntimeError(err)
        output, err = _hermes_poll_run(run_id)
        if err:
            raise RuntimeError(err)
        text = (output or "").strip()
        if text.startswith("```"):
            text = text.strip("`").strip()
        text = text[:BRIEF_PROMPT_LIMIT]
        if not text:
            raise RuntimeError("整理产出为空")
        changed = False
        with _lock:
            if str(_db["meta"].get("briefInterest", "")
                   or "") == interest:
                changed = text != str(
                    _db["meta"].get("brief", "") or "")
                _db["meta"]["brief"] = text
                _db["meta"]["briefUpdatedAt"] = _now()
                # §459 write-back: the polished text lands
                # keyed to the interest it was expanded from,
                # so the next open serves the professional
                # version (see _brief_text_locked). The user's
                # own words in briefInterest are NOT touched.
                _db["meta"]["briefPolished"] = {
                    "text": text, "forInterest": interest,
                    "at": _now()}
                expand = _db["meta"].setdefault("briefExpand", {})
                expand["lastError"] = None
                expand["lastRunAt"] = _now()
                _save_locked()
        if changed:
            _start_research("brief")
    except Exception as e:  # expansion must never kill anything
        with _lock:
            expand = _db["meta"].setdefault("briefExpand", {})
            expand["lastError"] = redact(e)
            expand["lastRunAt"] = _now()
            _save_locked()
    finally:
        with _brief_expand_lock:
            _brief_expanding = False


def _start_brief_expand(interest: str) -> bool:
    """Start an expansion run; False when one is already live."""
    global _brief_expanding
    with _brief_expand_lock:
        if _brief_expanding:
            return False
        _brief_expanding = True
    threading.Thread(target=_run_brief_expand, args=(interest,),
                     daemon=True).start()
    return True


_BRIEF_BACKSTOP_INTERVAL = 300.0
_brief_backstop_last = 0.0


def _brief_polish_backstop() -> None:
    """Reconcile backstop (batch 3): the expansion normally
    starts on the PUT /meta/brief save path. Interest text that
    landed any other way (the section-459 migration wrote the
    layer directly) never triggered one, and the brief doc then
    sat unpolished indefinitely. Called from the reconcile loop
    (and thus once at startup); self-throttled to one check per
    interval, single-flight via _start_brief_expand, and an
    attempt for the current text suppresses retries for 10
    minutes (errored attempts included), so a persistently
    failing expansion cannot hot-loop."""
    global _brief_backstop_last
    now = _now()
    if now - _brief_backstop_last < _BRIEF_BACKSTOP_INTERVAL:
        return
    _brief_backstop_last = now
    try:
        with _lock:
            meta = _db["meta"]
            interest = str(meta.get("briefInterest", "") or "")
            if not interest.strip():
                return
            polished = meta.get("briefPolished") or {}
            if polished.get("forInterest") == interest and str(
                    polished.get("text") or "").strip():
                return
            expand = meta.get("briefExpand") or {}
            if expand.get("forInterest") == interest and now - float(
                    expand.get("lastRunAt") or 0) < 600:
                return
        _start_brief_expand(interest)
    except Exception:
        pass
