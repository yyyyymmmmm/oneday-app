# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_monitors.py -- part of modules/oneday_gateway.py,
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




# --- monitors (P6) -----------------------------------------------------------
# monitor = bridge-side change detection: fetch target -> fingerprint ->
# diff against the stored snapshot -> changed/unchanged/failed tri-state.
#
# Scheduling history: the rollout decision record kept scheduling
# bridge-internal because Hermes cron was prompt/agent-only, the
# bridge was not on the hermes docker network, and a trigger would
# have needed the bridge key inside a cron prompt. All three
# premises were re-checked and voided on 2026-11-15 (sweep B-01):
# the deployed engine runs no_agent script jobs, both containers
# share the hermes_default network, and the callback uses a
# dedicated key that lives in a script-side file, never in a
# prompt. Since 1.0.59 every scheduled monitor owns a real Hermes
# cron job (see oneday_seg_cron.py); cronJobId is that job's id.
# The hand-rolled cron arithmetic below survives ONLY as
# create-time expression validation and as the gate for
# sub-minute intervals (the engine's granularity is one minute).
#
# On "changed", a notification record in overview-bridge's exact shape
# is appended to an append-only JSONL ledger next to the data file --
# the same append-only caliber overview-bridge consumes for its own
# source ledger (decisions.jsonl). Writing monitor events INTO
# decisions.jsonl was rejected: that file is the write-gate audit
# ledger, its lines surface in the approval history, and the overview
# title map only knows (memory|skills) x (approved|rejected).

MON_FETCH_TIMEOUT = 15        # seconds per fetch
MON_MAX_BYTES = 2_000_000     # hard cap on fetched body bytes
MON_SNAPSHOT_CAP = 32_768     # chars of snapshot text kept for diffing
MON_TEXT_CAP = 4_000          # chars of before/after kept per change
MON_CHANGES_KEEP = 100        # change records kept per monitor
MON_SCHED_TICK = 20           # reconcile loop interval, seconds
MON_UA = "OneDayMonitor/1.0 (+oneday-bridge)"

_checking: set = set()


def _sched_tz():
    # Monitor schedules are evaluated in the user's timezone; the
    # container itself runs UTC. China has no DST, the fixed-offset
    # fallback is exact.
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo("Asia/Shanghai")
    except Exception:
        return timezone(timedelta(hours=8))


def _fetch_target(url: str):
    """Return (text, None) on success, else (None, human error)."""
    req = urllib.request.Request(url, headers={
        "User-Agent": MON_UA, "Accept": "*/*",
        "Accept-Encoding": "identity"})
    try:
        with urllib.request.urlopen(req, timeout=MON_FETCH_TIMEOUT) as r:
            raw = r.read(MON_MAX_BYTES + 1)
    except urllib.error.HTTPError as e:
        return None, f"目标返回 HTTP {e.code}"
    except Exception as e:
        return None, f"抓取失败（{type(e).__name__}: {e}）"[:160]
    if len(raw) > MON_MAX_BYTES:
        raw = raw[:MON_MAX_BYTES]
    return raw.decode("utf-8", errors="replace"), None


def _fingerprint(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _first_diff(before: str, after: str) -> str:
    bl = before.splitlines()
    al = after.splitlines()
    for i in range(max(len(bl), len(al))):
        b = bl[i] if i < len(bl) else None
        a = al[i] if i < len(al) else None
        if b != a:
            return a if a is not None else (b or "")
    return ""


def _change_summary(before: str, after: str) -> str:
    diff = _first_diff(before, after).strip()
    if diff:
        if len(diff) > 60:
            diff = diff[:60] + "…"
        return f"内容发生变化：{diff}"
    return "内容发生变化"


def _monitor_view(m: dict) -> dict:
    return {
        "id": m["id"],
        "name": m["name"],
        "target": m["target"],
        "scheduleText": m.get("scheduleText", ""),
        "cronJobId": m.get("cronJobId"),
        "enabled": bool(m.get("enabled", True)),
        "lastCheckedAt": m.get("lastCheckedAt"),
        "lastResult": m.get("lastResult"),
        "lastError": m.get("lastError"),
        "unreadChanges": int(m.get("unreadChanges", 0)),
        "latestChangeSummary": m.get("latestChangeSummary"),
        "latestChangeAt": m.get("latestChangeAt"),
        "createdAt": m["createdAt"],
        "updatedAt": m["updatedAt"],
        "goalId": m.get("goalId"),
    }


def _change_view(c: dict) -> dict:
    return {
        "id": c["id"],
        "monitorId": c["monitorId"],
        "detectedAt": c["detectedAt"],
        "summary": c["summary"],
        "before": c.get("before"),
        "after": c.get("after"),
        "read": bool(c.get("read")),
    }


def _notify_locked(monitor: dict, change: dict) -> None:
    """Append one overview-shaped notification record (lock held).

    1.0.14 (§123 H2): carry refId=monitor id + changeId so the
    app's notification list can deep-link to the exact monitor
    and change; records written before 1.0.14 lack both fields
    and the app degrades those to the monitors section only."""
    rec = {
        "id": "mon-" + change["id"][4:16],
        "kind": "monitor_change",
        "title": f"监测有变化：{monitor['name']}",
        "body": change["summary"],
        "createdAt": datetime.fromtimestamp(
            change["detectedAt"], tz=timezone.utc
        ).isoformat().replace("+00:00", "Z"),
        "read": False,
        "refId": monitor["id"],
        "changeId": change["id"],
    }
    try:
        path = DATA_PATH.parent / "monitor-notifications.jsonl"
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError as e:
        _print(f"monitor notify append failed: {e}", file=sys.stderr)


def _list_monitor_notifications(limit: int) -> list:
    """Newest-first raw records from the monitor notification
    ledger (B-03, companion 1.0.63): the ledger's HTTP read
    surface for the overview bridge, which since 1.0.63
    aggregates notifications at read time from the owner
    modules instead of tailing this file. Records pass through
    exactly as written -- monitor changes and automation agent
    messages share this one ledger and this one read path."""
    path = DATA_PATH.parent / "monitor-notifications.jsonl"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    out = []
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if isinstance(rec, dict):
            out.append(rec)
            if len(out) >= limit:
                break
    return out


def _record_check_locked(m: dict, text, err, *, is_baseline: bool) -> str:
    """Fold one fetch outcome into monitor m (lock held).

    Returns 'baseline' | 'changed' | 'unchanged' | 'failed'.
    A baseline fetch only seeds the snapshot; it never reports a change
    and (on success) is not counted as a check."""
    now = _now()
    m["updatedAt"] = now
    if err is not None:
        prev_result = m.get("lastResult")
        m["lastCheckedAt"] = now
        m["lastResult"] = "failed"
        m["lastError"] = err
        if not is_baseline and prev_result != "failed":
            # The monitor's state just turned abnormal -- it
            # was reachable, now the fetch fails. That
            # transition (not each repeated failure) is a
            # feed-ledger event (FD-1 once graded it A; feed
            # purity 2026-11-12 keeps it ledger-only, never a
            # post; the monitor's own notify line is separate).
            feed = _feed_meta_locked()
            feed["events"].append({
                "key": f"monitor-down:{m['id']}:{int(now)}",
                "at": now, "kind": "monitor", "grade": "A",
                "alert": "down",
                "text": f"监测《{m['name'][:40]}》抓取失败："
                        f"{str(err)[:60]}",
                "refs": [{"type": "monitor", "id": m["id"]}],
            })
            feed["events"] = feed["events"][-FEED_EVENT_KEEP:]
        return "failed"
    new_snap = text[:MON_SNAPSHOT_CAP]
    new_fp = _fingerprint(new_snap)
    if m.get("snapshotText") is None:
        m["snapshotText"] = new_snap
        m["snapshotFp"] = new_fp
        if not is_baseline:
            m["lastCheckedAt"] = now
            m["lastResult"] = "unchanged"
            m["lastError"] = None
        return "baseline"
    if new_fp == m.get("snapshotFp"):
        m["lastCheckedAt"] = now
        m["lastResult"] = "unchanged"
        m["lastError"] = None
        return "unchanged"
    change = {
        "id": _new_id("chg_", {c["id"] for c in _db["changes"]}),
        "monitorId": m["id"],
        "detectedAt": now,
        "summary": _change_summary(m["snapshotText"], new_snap),
        "before": m["snapshotText"][:MON_TEXT_CAP],
        "after": new_snap[:MON_TEXT_CAP],
        "read": False,
    }
    _db["changes"].append(change)
    mine = [c for c in _db["changes"] if c["monitorId"] == m["id"]]
    if len(mine) > MON_CHANGES_KEEP:
        drop = {c["id"] for c in mine[:-MON_CHANGES_KEEP]}
        _db["changes"] = [c for c in _db["changes"] if c["id"] not in drop]
    m["snapshotText"] = new_snap
    m["snapshotFp"] = new_fp
    m["lastCheckedAt"] = now
    m["lastResult"] = "changed"
    m["lastError"] = None
    m["unreadChanges"] = int(m.get("unreadChanges", 0)) + 1
    m["latestChangeSummary"] = change["summary"]
    m["latestChangeAt"] = now
    _notify_locked(m, change)
    _ledger_monitor_change(m, change)
    return "changed"


def _run_check(mid: str, *, is_baseline: bool = False):
    """Fetch outside the lock; fold the result in under the lock."""
    with _lock:
        m = next((x for x in _db["monitors"] if x["id"] == mid), None)
        if m is None:
            return None
        target = m["target"]
    text, err = _fetch_target(target)
    with _lock:
        m = next((x for x in _db["monitors"] if x["id"] == mid), None)
        if m is None:
            return None
        result = _record_check_locked(m, text, err, is_baseline=is_baseline)
        _compute_next_locked(m)
        _save_locked()
        return result


# --- monitor schedule arithmetic (validation + sub-minute gate) ------------
# Scheduling itself belongs to the Hermes cron engine since
# 1.0.59 (B-01); this arithmetic remains only to validate cron
# expressions at create time and to gate sub-minute intervals
# whose cadence the engine cannot express (see oneday_seg_cron).

def _parse_cron_field(spec: str, lo: int, hi: int) -> set:
    vals = set()
    for part in spec.split(","):
        part = part.strip()
        if not part:
            raise ValueError("empty cron field part")
        step = 1
        if "/" in part:
            part, s = part.split("/", 1)
            step = int(s)
            if step <= 0:
                raise ValueError("bad cron step")
        if part == "*":
            a, b = lo, hi
        elif "-" in part:
            x, y = part.split("-", 1)
            a, b = int(x), int(y)
        else:
            a = b = int(part)
        if a < lo or b > hi or a > b:
            raise ValueError("cron value out of range")
        vals.update(range(a, b + 1, step))
    return vals


def _parse_cron(expr: str) -> dict:
    fields = expr.split()
    if len(fields) != 5:
        raise ValueError("cron needs 5 fields")
    return {
        "minute": _parse_cron_field(fields[0], 0, 59),
        "hour": _parse_cron_field(fields[1], 0, 23),
        "dom": _parse_cron_field(fields[2], 1, 31),
        "month": _parse_cron_field(fields[3], 1, 12),
        "dow": _parse_cron_field(fields[4], 0, 7),  # 0 and 7 = Sunday
        "dom_star": fields[2] == "*",
        "dow_star": fields[4] == "*",
    }


def _cron_match(spec: dict, dt) -> bool:
    if dt.minute not in spec["minute"] or dt.hour not in spec["hour"] \
            or dt.month not in spec["month"]:
        return False
    dom_ok = dt.day in spec["dom"]
    dow = (dt.weekday() + 1) % 7  # python Mon=0..Sun=6 -> cron Sun=0
    dow_ok = dow in spec["dow"] or (dow == 0 and 7 in spec["dow"])
    if spec["dom_star"] and spec["dow_star"]:
        return True
    if spec["dom_star"]:
        return dow_ok
    if spec["dow_star"]:
        return dom_ok
    return dom_ok or dow_ok  # Vixie rule: both restricted -> either


def _cron_next(expr: str, after_epoch: float):
    try:
        spec = _parse_cron(expr)
    except Exception:
        return None
    tz = _sched_tz()
    dt = datetime.fromtimestamp(after_epoch, tz=tz)
    dt = dt.replace(second=0, microsecond=0) + timedelta(minutes=1)
    for _ in range(366 * 24 * 60):
        if _cron_match(spec, dt):
            return dt.timestamp()
        dt += timedelta(minutes=1)
    return None


def _compute_next_locked(m: dict, after: float = None) -> None:
    after = after or _now()
    nxt = None
    if m.get("cron"):
        nxt = _cron_next(m["cron"], after)
    if nxt is None and m.get("intervalSeconds"):
        nxt = after + float(m["intervalSeconds"])
    m["nextRunAt"] = nxt


def _derive_schedule_text(cron, interval) -> str:
    if interval:
        if interval % 3600 == 0:
            return f"每 {int(interval // 3600)} 小时"
        if interval % 60 == 0:
            return f"每 {int(interval // 60)} 分钟"
        return f"每 {int(interval)} 秒"
    if cron:
        return cron
    return "手动检查"


# The scheduler loop that used to live here (monitor due-scan +
# generation/briefing/feed ticks) retired in 1.0.59 (B-01): the
# Hermes cron engine fires monitors and rounds now. The remaining
# 20 s loop is _reconcile_loop in oneday_seg_cron.py.


# --- monitor domain operations ----------------------------------------------

def _find_monitor(mid: str):
    return next((x for x in _db["monitors"] if x["id"] == mid), None)


def _list_monitors() -> list:
    with _lock:
        items = sorted(_db["monitors"], key=lambda m: m["createdAt"])
        return [_monitor_view(m) for m in items]


def _create_monitor(body: dict) -> dict:
    name = _clean_title(body.get("name"), "名称")
    target = body.get("target")
    if not isinstance(target, str) or not target.strip():
        raise _Err(400, "target 不能为空")
    target = target.strip()
    if not (target.startswith("http://") or target.startswith("https://")):
        raise _Err(400, "target 必须是 http(s) 链接")
    cron = body.get("cron")
    if cron is not None:
        if not isinstance(cron, str) or not cron.strip():
            raise _Err(400, "cron 表达式不对")
        cron = cron.strip()
        try:
            _parse_cron(cron)
        except Exception:
            raise _Err(400, "cron 表达式不对")
    interval = body.get("intervalSeconds")
    if interval is not None:
        if not isinstance(interval, (int, float)) \
                or isinstance(interval, bool) or interval < 60:
            raise _Err(400, "intervalSeconds 至少 60")
        interval = float(interval)
    goal_id = body.get("goalId")
    if goal_id is not None:
        if not isinstance(goal_id, str):
            raise _Err(400, "goalId 必须是字符串或 null")
        with _lock:
            known = any(g["id"] == goal_id for g in _db["goals"])
        if not known:
            raise _Err(400, "目标不存在，无法关联")
    schedule_text = body.get("scheduleText")
    if schedule_text is not None and not isinstance(schedule_text, str):
        raise _Err(400, "scheduleText 必须是字符串")
    if not schedule_text:
        schedule_text = _derive_schedule_text(cron, interval)
    text, err = _fetch_target(target)  # baseline fetch, outside the lock
    ts = _now()
    with _lock:
        m = {
            "id": _new_id("mon_", {x["id"] for x in _db["monitors"]}),
            "name": name,
            "target": target,
            "scheduleText": schedule_text,
            "cronJobId": None,
            "enabled": True,
            "lastCheckedAt": None,
            "lastResult": None,
            "lastError": None,
            "unreadChanges": 0,
            "latestChangeSummary": None,
            "latestChangeAt": None,
            "createdAt": ts,
            "updatedAt": ts,
            "cron": cron,
            "intervalSeconds": interval,
            "goalId": goal_id,
            "snapshotText": None,
            "snapshotFp": None,
            "nextRunAt": None,
        }
        _db["monitors"].append(m)
        _record_check_locked(m, text, err, is_baseline=True)
        _compute_next_locked(m, after=ts)
        _save_locked()
    # Engine registration is network I/O: outside the lock, and
    # best-effort -- a Dashboard outage leaves cronJobId null and
    # the cron ensure pass registers it later (B-01).
    _cron_register_monitor(m)
    with _lock:
        cur = _find_monitor(m["id"])
        return _monitor_view(cur if cur is not None else m)


def _list_changes(mid: str) -> list:
    with _lock:
        if _find_monitor(mid) is None:
            raise _Err(404, "监测不存在")
        items = [c for c in _db["changes"] if c["monitorId"] == mid]
        items.sort(key=lambda c: c["detectedAt"], reverse=True)
        return [_change_view(c) for c in items]


def _check_monitor(mid: str) -> dict:
    with _lock:
        m = _find_monitor(mid)
        if m is None:
            raise _Err(404, "监测不存在")
        if not m.get("enabled", True):
            raise _Err(409, "监测已暂停，先恢复再检查")
    _run_check(mid)
    with _lock:
        return _monitor_view(_find_monitor(mid))


def _set_enabled(mid: str, enabled: bool) -> dict:
    with _lock:
        m = _find_monitor(mid)
        if m is None:
            raise _Err(404, "监测不存在")
        m["enabled"] = enabled
        m["updatedAt"] = _now()
        if enabled:
            _compute_next_locked(m)
        _save_locked()
        snapshot = dict(m)
    _cron_sync_monitor_enabled(snapshot)
    with _lock:
        cur = _find_monitor(mid)
        return _monitor_view(cur if cur is not None else snapshot)


def _read_monitor(mid: str) -> None:
    with _lock:
        m = _find_monitor(mid)
        if m is None:
            raise _Err(404, "监测不存在")
        for c in _db["changes"]:
            if c["monitorId"] == mid:
                c["read"] = True
        m["unreadChanges"] = 0
        m["updatedAt"] = _now()
        _save_locked()


def _read_change(mid: str, cid: str) -> None:
    with _lock:
        m = _find_monitor(mid)
        if m is None:
            raise _Err(404, "监测不存在")
        c = next((x for x in _db["changes"]
                  if x["id"] == cid and x["monitorId"] == mid), None)
        if c is None:
            raise _Err(404, "变化记录不存在")
        c["read"] = True
        m["unreadChanges"] = sum(
            1 for x in _db["changes"]
            if x["monitorId"] == mid and not x.get("read"))
        m["updatedAt"] = _now()
        _save_locked()


def _delete_monitor(mid: str) -> None:
    with _lock:
        m = _find_monitor(mid)
        if m is None:
            raise _Err(404, "监测不存在")
        snapshot = dict(m)
        _db["monitors"] = [x for x in _db["monitors"] if x["id"] != mid]
        _db["changes"] = [c for c in _db["changes"]
                           if c["monitorId"] != mid]
        _save_locked()
    _cron_unregister_monitor(snapshot)
