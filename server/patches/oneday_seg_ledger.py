# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_ledger.py -- part of modules/oneday_gateway.py,
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




# --- HTTP layer --------------------------------------------------------------


# --- work ledger (work-ledger-design-20261110.md) -------------------
#
# The bridge's own book of work. Writers: the App's reports
# (POST /ledger/report), bridge-self job records (the _start_*
# and *_record_locked hooks above), monitor change records
# (the _ledger_monitor_change hook + the collector-cycle
# reconcile below -- A-05 single-stream, 1.0.64), and a
# collector thread that reconciles every
# LEDGER_COLLECTOR_SECONDS against the Hermes-side truth
# sources -- session list + transcripts (the only completion
# oracle), run status, the kanban board, write-gate
# decisions/pending and the device audit log. All
# state-machine / title-chain / zombie-ladder logic lives in
# ledger.py; this section is providers, views and plumbing only.

LEDGER_PATH = Path(os.environ.get(
    "LEDGER_PATH", str(DATA_PATH.parent / "ledger-events.jsonl")))
LEDGER_COLLECTOR_SECONDS = float(os.environ.get(
    "LEDGER_COLLECTOR_SECONDS", "15"))
LEDGER_DECISIONS_PATH = Path(os.environ.get(
    "LEDGER_DECISIONS_PATH", "/opt/data/write-gate/decisions.jsonl"))
LEDGER_DEVICE_AUDIT_PATH = Path(os.environ.get(
    "LEDGER_DEVICE_AUDIT_PATH", "/opt/device-data/audit.jsonl"))
LEDGER_SKIP_SESSIONS = {
    s for s in os.environ.get(
        "LEDGER_SKIP_SESSIONS", GEN_SESSION_ID).split(",") if s}
WRITE_GATE_BASE = os.environ.get(
    "WRITE_GATE_BASE", "http://127.0.0.1:8642/api/write-gate").rstrip("/")
WRITE_GATE_BRIDGE_KEY = os.environ.get("API_SERVER_KEY") or \
    os.environ.get("WRITE_GATE_BRIDGE_KEY", "")

_ledger_store = None
_ledger_collector = None
_ledger_init_lock = threading.Lock()
_ledger_jobs: dict = {}
_ledger_jobs_delivered: set = set()


def _ledger() -> "_ledger_mod.LedgerStore":
    global _ledger_store
    if _ledger_store is None:
        with _ledger_init_lock:
            if _ledger_store is None:
                _ledger_store = _ledger_mod.LedgerStore(
                    LEDGER_PATH, tz=_sched_tz())
    return _ledger_store


# -- bridge-self job records (spec coverage matrix #5) ---------------

_LEDGER_JOB_LABELS = {"ideas": ("点子生成", "ideas"),
                      "briefing": ("目标简报", "goals"),
                      # kind key kept for ledger history
                      # continuity; the job itself is the
                      # 0.38.0 research round now
                      "morning": ("动态调研", "feed")}


def _ledger_job_start(kind: str) -> None:
    """The execution point is the writing point: a bridge job
    can never be missed by its own ledger. Ledger failures must
    never break the round itself, so this swallows everything."""
    try:
        label, page = _LEDGER_JOB_LABELS[kind]
        started = _now()
        day = datetime.fromtimestamp(started, tz=_sched_tz())
        jid = f"job:{kind}:{int(started)}"
        _ledger().create_or_merge({
            "id": jid, "kind": "job", "source": "bridge",
            "title": f"{label} · {day.month}月{day.day}日",
            "titleSource": "job_name", "status": "running",
            "startedAt": started, "origin": "bridge_self",
            "link": {"kind": "page", "targetId": page},
            "by": "bridge"})
        _ledger_jobs[kind] = jid
    except Exception as e:
        _print(f"ledger job start failed: {e!r}",
              file=sys.stderr, flush=True)


def _ledger_job_delivered(kind: str, produced: int) -> None:
    """Delivery-point settlement (§475 part 2): called by a
    round at the moment its deliverables have ALL landed in
    the store (the publish/landing save is done). The job
    settles completed there, with the produced count -- the
    round's remaining bookkeeping is tail work and no longer
    holds the user's status at "running". Same contract as
    start/finish: ledger failures never break the round."""
    try:
        store = _ledger()
        jid = _ledger_jobs.get(kind)
        if not jid:
            # Same defensive fallback as finish: the start
            # was booked by a previous incarnation.
            prefix = f"job:{kind}:"
            candidates = [
                it for it in store.list_items()
                if it["id"].startswith(prefix)
                and it["status"] in ("queued", "running",
                                     "blocked_approval")]
            if not candidates:
                return
            jid = max(
                candidates,
                key=lambda it: it.get("startedAt") or 0)["id"]
        res = _ledger_mod.settle_job_delivered(
            store, jid, produced, now=_now())
        if res == "ok":
            _ledger_jobs_delivered.add(jid)
    except Exception as e:
        print(f"ledger job delivered-settle failed: {e!r}",
              file=sys.stderr, flush=True)


def _ledger_job_finish(kind: str, rec: dict) -> None:
    try:
        jid = _ledger_jobs.pop(kind, None)
        store = _ledger()
        if jid and jid in _ledger_jobs_delivered:
            # Settled at the delivery point already (§475
            # part 2). The round-end record still lands in
            # the round's own history via the *_record_locked
            # caller, but its outcome must not move the job:
            # without this guard a tail failure would ride
            # set_status's terminal-correction path and flip
            # a delivered job to failed. A tail outcome that
            # disagrees with delivery is logged, only.
            _ledger_jobs_delivered.discard(jid)
            raw = str(rec.get("status") or "")
            if raw not in \
                    _ledger_mod.DELIVERY_CONSISTENT_STATUSES:
                print(f"ledger job {jid}: round tail ended "
                      f"{raw!r} after delivery settlement; "
                      f"job status kept completed",
                      file=sys.stderr, flush=True)
            return
        if not jid:
            # The in-process slot is empty -- the start was
            # booked by a previous incarnation (restart
            # mid-round) or overwritten. Fall back to the
            # newest still-active job item of this kind so
            # the finish lands on a real line instead of
            # vanishing (2026-11-24, §475).
            prefix = f"job:{kind}:"
            candidates = [
                it for it in store.list_items()
                if it["id"].startswith(prefix)
                and it["status"] in ("queued", "running",
                                     "blocked_approval")]
            if not candidates:
                return
            jid = max(
                candidates,
                key=lambda it: it.get("startedAt") or 0)["id"]
        raw = str(rec.get("status") or "")
        err = rec.get("error")
        if raw in _ledger_mod.DELIVERY_CONSISTENT_STATUSES:
            store.set_status(jid, "completed", by="bridge",
                             ended_at=_now())
            return
        if raw == "skipped":
            store.set_status(
                jid, "failed", by="bridge",
                ended_at=_now(),
                fail_reason={"category": "原因未明",
                             "excerpt": str(
                                 err or "本轮未执行")[:160]})
            return
        to, fail_reason = _ledger_mod.classify_failure(err)
        store.set_status(jid, to, by="bridge",
                         ended_at=_now(),
                         fail_reason=fail_reason)
    except Exception as e:
        _print(f"ledger job finish failed: {e!r}",
              file=sys.stderr, flush=True)


def _ledger_monitor_item(monitor: dict, change: dict) -> dict:
    """The canonical ledger line for one monitor change -- the
    exact shape the App's retired client synthesis (sec.217,
    LedgerMonitorSynthesis) used to build from the /monitors
    read faces, now supplied by the server as the single
    source (A-05 single-stream, 1.0.64): kind=monitor so the
    App's event presentation applies (never a fake 'completed
    work' row), id in the `monitor-change:` space the App's
    deep-link focus resolves, title = the change's own
    summary, falling back to the monitor's name -- never
    invented text."""
    summary = str(change.get("summary") or "").strip()
    at = change.get("detectedAt") or _now()
    return {
        "id": f"monitor-change:{change['id']}", "kind": "monitor",
        "source": "bridge",
        "title": summary or str(monitor.get("name") or ""),
        "titleSource": "monitor_change", "status": "completed",
        "startedAt": at, "endedAt": at, "lastEvidenceAt": at,
        "origin": "bridge_self",
        "link": {"kind": "monitor",
                 "targetId": monitor.get("id")},
        "by": "bridge"}


def _ledger_monitor_change(monitor: dict, change: dict) -> None:
    """Monitor 'found change' events are work worth a line in
    the book (spec 5.3); the minute-level checks themselves are
    explicitly not. Write-time hook: the line lands in the same
    pass that records the change."""
    try:
        _ledger().create_or_merge(
            _ledger_monitor_item(monitor, change))
    except Exception as e:
        _print(f"ledger monitor change failed: {e!r}",
              file=sys.stderr, flush=True)


def _ledger_monitor_reconcile() -> int:
    """Collector-side monitor source (A-05): every change in
    the bridge's own change store earns its ledger line. The
    hook above gives immediacy; this pass, on the collector
    cadence, heals a swallowed hook failure and backfills
    changes recorded before the server source existed.
    Idempotent -- create_or_merge folds by item id, so a
    no-change pass appends nothing. Returns lines created."""
    try:
        store = _ledger()
        with _lock:
            monitors = {m["id"]: m for m in _db["monitors"]}
            changes = list(_db["changes"])
        created = 0
        for change in changes:
            monitor = monitors.get(change.get("monitorId"))
            if monitor is None:
                continue
            _, was_created = store.create_or_merge(
                _ledger_monitor_item(monitor, change))
            created += 1 if was_created else 0
        return created
    except Exception as e:
        _print(f"ledger monitor reconcile failed: {e!r}",
              file=sys.stderr, flush=True)
        return 0


# -- Dashboard channel helpers (facade data reads) --------------------
# (Pre-C-4 these also fed the ledger collector as its state
# providers; the collector no longer reads Hermes-side state.
# The channel itself stays: the sessions facade and the idea
# generation digests read through it.)

class _LedgerDash:
    """Dashboard channel. C-3 default: per-request Bearer
    credentials (session token / gateway key by surface), no
    login at all. Legacy mode (HERMES_DASH_AUTH_MODE=password):
    cookie channel with a cached login -- the collector runs
    every 15 s and must not re-login per cycle; one re-login
    retry on 401."""

    def __init__(self):
        self._opener = None
        self._lock = threading.Lock()

    def _login(self):
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
        return opener if status == 200 else None

    def get(self, path):
        if _dash_token_mode():
            # C-3: plugin surfaces ride the Dashboard base with
            # the deployment session token; session surfaces ride
            # the gateway base with the gateway key (both are
            # in-container machine credentials, verified live at
            # rollout: 9119 + token -> 200, 8642 + key -> 200).
            if path.startswith("/api/plugins/"):
                base, headers = HERMES_DASH_BASE_URL, \
                    _dash_bearer_headers()
            else:
                base, headers = HERMES_BASE_URL, \
                    {"Authorization": f"Bearer {HERMES_API_KEY}"}
            status, payload, _ = _http_json(
                base + path, headers=headers)
            return payload if status == 200 else None
        if not HERMES_DASH_USER or not HERMES_DASH_PASSWORD:
            return None
        with self._lock:
            if self._opener is None:
                self._opener = self._login()
            if self._opener is None:
                return None
            # Batch 3: plugin surfaces ride the Dashboard base,
            # session surfaces the gateway base (one public base
            # fronted both while the bridge lived outside).
            base = HERMES_DASH_BASE_URL \
                if path.startswith("/api/plugins/") \
                else HERMES_BASE_URL
            status, payload, _ = _http_json(
                base + path, opener=self._opener)
            if status == 401:
                self._opener = self._login()
                if self._opener is None:
                    return None
                status, payload, _ = _http_json(
                    base + path, opener=self._opener)
            return payload if status == 200 else None


_ledger_dash = _LedgerDash()


def _ledger_norm_ts(value):
    if isinstance(value, (int, float)):
        return float(value) / 1000 if value > 1e11             else float(value)
    return None


def _ledger_sessions():
    payload = _ledger_dash.get("/api/sessions?limit=100")
    if not isinstance(payload, dict):
        return None
    items = payload.get("sessions")
    if not isinstance(items, list):
        return None
    out = []
    for s in items:
        if not isinstance(s, dict) or s.get("archived"):
            continue
        sid = str(s.get("id") or "")
        if not sid or sid in LEDGER_SKIP_SESSIONS:
            continue
        grade_raw = str(s.get("title_source")
                        or s.get("titleSource")
                        or s.get("title_kind") or "").lower()
        grade = grade_raw if grade_raw in ("llm", "user") else (
            "derived" if grade_raw == "derived" else None)
        src_raw = str(s.get("source") or s.get("platform")
                      or "").lower()
        if "cron" in src_raw or sid.startswith("cron"):
            source = "cron"
        elif "dash" in src_raw or "web" in src_raw:
            source = "dashboard"
        else:
            source = "api"
        out.append({
            "id": sid,
            "title": (s.get("title") or s.get("display_name")
                      or "").strip(),
            "titleGrade": grade,
            "startedAt": _ledger_norm_ts(
                s.get("started_at") or s.get("startedAt")
                or s.get("created_at")),
            "endedAt": _ledger_norm_ts(
                s.get("ended_at") or s.get("endedAt")),
            "messageCount": s.get("message_count")
            if isinstance(s.get("message_count"), int)
            else s.get("messageCount"),
            "source": source,
        })
    return out


def _ledger_message_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for part in content:
            if isinstance(part, dict):
                t = part.get("text") or part.get("content")
                if isinstance(t, str):
                    parts.append(t)
            elif isinstance(part, str):
                parts.append(part)
        return "".join(parts)
    return ""


def _ledger_messages(sid):
    payload = _ledger_dash.get(f"/api/sessions/{sid}/messages")
    raw = None
    if isinstance(payload, dict):
        raw = payload.get("messages") or payload.get("data")
    elif isinstance(payload, list):
        raw = payload
    if not isinstance(raw, list):
        return None
    out = []
    for m in raw:
        if not isinstance(m, dict):
            continue
        role = str(m.get("role") or m.get("type") or "")
        if role == "human":
            role = "user"
        if role not in ("user", "assistant", "tool"):
            continue
        meta = m.get("display_metadata") or m.get("metadata")             or {}
        interrupted = bool(
            m.get("interrupted")
            or (isinstance(meta, dict) and meta.get("interrupted")))
        tool_calls = m.get("tool_calls") or m.get("toolCalls")             or []
        out.append({
            "role": role,
            "ts": _ledger_norm_ts(m.get("created_at")
                                  or m.get("ts")
                                  or m.get("timestamp")
                                  or m.get("time")) or 0,
            "text": _ledger_message_text(m.get("content")),
            "interrupted": interrupted,
            "toolCalls": len(tool_calls)
            if isinstance(tool_calls, list) else 0,
        })
    return out


def _ledger_parse_iso(value):
    if isinstance(value, (int, float)):
        return _ledger_norm_ts(value)
    if isinstance(value, str) and value:
        try:
            return datetime.fromisoformat(
                value.replace("Z", "+00:00")).timestamp()
        except Exception:
            return None
    return None


# -- boot-time orphan settlement (2026-11-24, §475) ------------
#
# The live finish path above is a round thread calling home
# inside its own process. When the process dies mid-round
# (every hermes restart does this), the finish is lost
# with it and the item would sit in running until the
# zombie ladder's stale mark -- a non-terminal shrug the
# App renders as forever-running. At boot the new process
# KNOWS the old one is gone, so it settles the orphans
# itself, from the rounds' own history records.

_LEDGER_JOB_HISTORY_KEYS = {"morning": "feedGen",
                            "ideas": "ideasGen",
                            "briefing": "briefGen"}


def _ledger_reconcile_orphan_jobs() -> None:
    try:
        with _lock:
            meta = _db["meta"]
            histories = {}
            for kind, key in _LEDGER_JOB_HISTORY_KEYS.items():
                gen = meta.get(key) or {}
                histories[kind] = list(gen.get("history") or [])
        settled = _ledger_mod.settle_orphan_jobs(
            _ledger(), histories, now=_now())
        if settled:
            print(f"ledger orphan jobs settled at boot: "
                  f"{settled}", file=sys.stderr, flush=True)
    except Exception as e:
        print(f"ledger orphan reconcile failed: {e!r}",
              file=sys.stderr, flush=True)


def _ledger_start_collector() -> None:
    global _ledger_collector
    store = _ledger()
    _ledger_reconcile_orphan_jobs()
    # C-4 convergence: the collector takes no state providers --
    # it ingests the two event files and runs the zombie ladder.
    _ledger_collector = _ledger_mod.Collector(
        store, tz=_sched_tz(),
        decisions_path=LEDGER_DECISIONS_PATH,
        device_audit_path=LEDGER_DEVICE_AUDIT_PATH)

    def loop():
        while True:
            try:
                _ledger_collector.cycle()
            except Exception as e:
                _print(f"ledger collector failed: {e!r}",
                      file=sys.stderr, flush=True)
            # A-05 monitor source: same cadence, own failure
            # line -- a monitor-pass failure must not stall
            # the collector's zombie ladder above.
            _ledger_monitor_reconcile()
            time.sleep(LEDGER_COLLECTOR_SECONDS)

    threading.Thread(target=loop, daemon=True).start()


def _ledger_counts_view() -> dict:
    store = _ledger()
    now = _now()
    view = store.summary(now)
    view["collectorHeartbeatAt"] = store.collector_heartbeat_at
    view["ledgerUpdatedAt"] = store.last_event_at
    view["serverNow"] = now
    view["degraded"] = bool(store.degraded_reason)
    if _ledger_collector is not None:
        view["collector"] = {
            "lastRunAt": _ledger_collector.state.get("lastRunAt"),
            "sources": _ledger_collector.state.get("sources", {}),
            "ambiguousDeviceCalls": _ledger_collector.state.get(
                "ambiguousDeviceCalls", 0)}
    return view


def _ledger_list_view(since) -> dict:
    store = _ledger()
    now = _now()
    items = store.list_items() if since is None         else store.changes_since(since)
    return {"items": items, "snapshotSeq": store.seq,
            "ledgerUpdatedAt": store.last_event_at,
            "collectorHeartbeatAt": store.collector_heartbeat_at,
            "serverNow": now, "counts": store.summary(now)}
