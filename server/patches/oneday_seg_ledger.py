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
        "LEDGER_SKIP_SESSIONS",
        GEN_SESSION_ID + ",oneday-title-summary").split(",")
    if s}
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


# -- human headlines for run items (queue 173) -----------------------
#
# Run items are born from App reports whose titleSeed is the run's
# first input text. For the bridge's own generation rounds that text
# is the round's system instruction, so the book filled with prompt
# excerpts as titles (probe 172: one prompt family held 261 of the
# 404 served items, and title_human existed on exactly one). The
# App cannot know better; the server can: the run's session carries
# a real name in the Hermes state.db, and the rounds' instructions
# name their own task in their first line. This pass — same cadence
# and failure discipline as the monitor reconcile above — resolves
# a human headline (and, for settled runs, the activity summary
# from the session's last tool call) and stores it through
# update_fields, so the heal is an event in the log and survives
# restarts. Anything unresolvable stays untouched: a missing
# headline is honest, an invented one is not. This is a headline
# pass only — it never touches status, evidence or counts, so the
# C-4 "no reconciler" discipline for terminal states is intact.

_HUMANIZE_STATE_DB = Path(os.environ.get(
    "HUMANIZE_STATE_DB", str(DATA_PATH.parent.parent / "state.db")))
# Title healing is one batched session query plus one log event per
# healed item, so it runs over every target each pass; the per-item
# last-tool lookup for summaries is the expensive part and is capped
# per pass (the backlog drains over the first passes after deploy).
_HUMANIZE_SUMMARY_LOOKUPS_PER_PASS = 120

# The bridge rounds' instructions name their own task in the first
# line; the headline is that name, never the instruction body.
_HUMANIZE_ROUND_HEADS = (
    (("口味笔记整理者", "feed_reconcile"), "动态口味笔记整理"),
    (("动态报社宪法", "feed_constitution"), "动态报社宪法"),
    (("动态社交取材", "feed_social_material"), "动态社交取材"),
    (("动态取材", "feed_material"), "动态取材"),
    (("点子生成器", "ideas_gen"), "点子生成"),
    (("会话摘要器",), "会话摘要整理"),
)


def _humanize_round_name(title) -> str:
    text = title if isinstance(title, str) else ""
    for needles, name in _HUMANIZE_ROUND_HEADS:
        if any(n in text for n in needles):
            return name
    return ""


def _humanize_sane_session_title(title) -> str:
    """A session title is a usable headline only when it reads like
    a name for the task: even LLM-graded titles can be fragments
    ('{ #13', '**亲口** #6'); those fail this gate and the caller
    falls back to the round name or leaves the item untouched."""
    if not isinstance(title, str):
        return ""
    t = title.strip()
    if len(t) < 2 or len(t) > 80:
        return ""
    if t[0] in "{[#*\"'`>|-":
        return ""
    if "feed_" in t or "你是 OneDay" in t or "…" in t:
        return ""
    if not re.search(r"[一-鿿A-Za-z]{2,}", t):
        return ""
    return t


def _humanize_session_rows(session_ids):
    """{session_id: (title, title_source)} from the Hermes state.db,
    opened read-only (the write-gate anchor resolver's precedent).
    A missing db or missing rows are simply absent from the map."""
    import sqlite3
    out = {}
    ids = [s for s in dict.fromkeys(session_ids) if s]
    if not ids or not _HUMANIZE_STATE_DB.exists():
        return out
    try:
        con = sqlite3.connect(
            f"file:{_HUMANIZE_STATE_DB}?mode=ro", uri=True,
            timeout=5)
        try:
            for i in range(0, len(ids), 200):
                chunk = ids[i:i + 200]
                marks = ",".join("?" * len(chunk))
                for sid, title, src in con.execute(
                        "SELECT id, title, title_source FROM sessions"
                        f" WHERE id IN ({marks})", chunk):
                    out[sid] = (title, src)
        finally:
            con.close()
    except Exception:
        return out
    return out


def _humanize_last_tool(session_id):
    """(tool_name, preview) of the session's last tool call from
    state.db messages, or None. The preview is the call's primary
    argument — the same (tool, preview) pair the App-reported
    activity derivation consumes."""
    import sqlite3
    if not session_id or not _HUMANIZE_STATE_DB.exists():
        return None
    try:
        con = sqlite3.connect(
            f"file:{_HUMANIZE_STATE_DB}?mode=ro", uri=True,
            timeout=5)
        try:
            row = con.execute(
                "SELECT tool_calls FROM messages WHERE session_id=?"
                " AND tool_calls IS NOT NULL ORDER BY id DESC"
                " LIMIT 1", (session_id,)).fetchone()
        finally:
            con.close()
    except Exception:
        return None
    if not row or not row[0]:
        return None
    try:
        calls = json.loads(row[0])
    except Exception:
        return None
    if not isinstance(calls, list) or not calls:
        return None
    fn = (calls[-1] or {}).get("function") or {}
    name = fn.get("name")
    if not isinstance(name, str) or not name:
        return None
    args = fn.get("arguments")
    preview = ""
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except Exception:
            args = None
    if isinstance(args, dict):
        for key in ("path", "file_path", "query", "url", "command",
                    "pattern", "name", "title", "prompt", "text",
                    "input"):
            val = args.get(key)
            if isinstance(val, str) and val.strip():
                preview = val.strip()
                break
        if not preview:
            for val in args.values():
                if isinstance(val, str) and val.strip():
                    preview = val.strip()
                    break
    return name, preview


def _ledger_humanize_reconcile() -> int:
    """Fill missing human headlines / activity summaries on run
    items from state.db session facts. Idempotent: an item is only
    written when a field actually changes."""
    healed = 0
    try:
        store = _ledger()
        targets = []
        for item in store.list_items():
            if item.get("kind") != "run":
                continue
            need_title = not str(
                item.get("title_human") or "").strip()
            need_summary = (
                item.get("status") in _ledger_mod.TERMINAL
                and not str(item.get("summary") or "").strip())
            if need_title or need_summary:
                targets.append((item, need_title, need_summary))
        if not targets:
            return 0
        rows = _humanize_session_rows(
            [i.get("sessionId") for i, _, _ in targets])
        lookups = 0
        for item, need_title, need_summary in targets:
            fields = {}
            if need_title:
                title = item.get("title") or ""
                round_name = _humanize_round_name(title)
                sess = rows.get(item.get("sessionId") or "")
                sane = _humanize_sane_session_title(sess[0]) \
                    if sess and sess[1] in ("llm", "user") else ""
                if round_name:
                    # An instruction excerpt is never the headline:
                    # prefer the session's own sane name, else the
                    # round's name from its own first line.
                    fields["title_human"] = sane or round_name
                elif item.get("titleSource") == "user_excerpt" \
                        and sane and sane != title:
                    fields["title_human"] = sane
            if need_summary and lookups < \
                    _HUMANIZE_SUMMARY_LOOKUPS_PER_PASS:
                lookups += 1
                last = _humanize_last_tool(item.get("sessionId"))
                if last:
                    summary = _ledger_mod.derive_activity_summary(
                        last[0], last[1])
                    if summary:
                        fields["summary"] = summary
            if fields:
                store.update_fields(item["id"], fields,
                                    by="collector")
                healed += 1
    except Exception as e:
        _print(f"ledger humanize failed: {e!r}",
               file=sys.stderr, flush=True)
    return healed


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
    # Queue 193: the title engine's worker drains its queue on
    # its own thread; starting it here ties its life to the
    # collector's without sharing the collector's cadence.
    _title_start_worker()

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
            # Queue 173 headline pass: same cadence again, own
            # failure line inside the pass itself.
            _ledger_humanize_reconcile()
            # Queue 176 activity classification pass: same
            # cadence again, own failure line inside the pass.
            _ledger_activity_reconcile()
            # Queue 193 title engine: enqueue newly closed
            # threads for model summarising, same cadence, own
            # failure line inside the pass. The worker thread
            # (started below) drains the queue asynchronously --
            # this loop never waits on the model.
            _title_enqueue_reconcile()
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
    view["titleEngine"] = _title_engine_stats()
    if _ledger_collector is not None:
        view["collector"] = {
            "lastRunAt": _ledger_collector.state.get("lastRunAt"),
            "sources": _ledger_collector.state.get("sources", {}),
            "ambiguousDeviceCalls": _ledger_collector.state.get(
                "ambiguousDeviceCalls", 0)}
    return view


def _ledger_is_system_run(item) -> bool:
    """A bridge-self system round's run record (queue 155,
    identity-page alignment contract sec.5): the job items are
    booked by _ledger_job_start for the bridge's own system
    rounds (morning/ideas/briefing -- the rounds sj-05's
    is_system classification covers). They are scheduled-task
    run history, not session/work events, so the activity
    stream must not carry them."""
    return item.get("kind") == "job" \
        and item.get("origin") == "bridge_self"


def _ledger_list_view(since) -> dict:
    store = _ledger()
    now = _now()
    items = store.list_items() if since is None         else store.changes_since(since)
    # Feed source swap (queue 155): the list exit serves the
    # session-and-work event stream only. System-task runs are
    # filtered HERE, at the server exit -- the items stay in
    # the store (scheduled faces, job detail and the boot-time
    # orphan settle still read them), clients just render.
    # Activity positioning (queue 176): the same exit also
    # drops every item the classification pass has stamped
    # activityExcluded (platform rounds, monitor self-checks,
    # anything with no traceable user intent). The stamp is
    # written by _ledger_activity_reconcile on this bridge's
    # collector cadence; the system-run predicate above stays
    # as the always-on first gate so bridge rounds never wait
    # for a stamp.
    items = [it for it in items
             if not _ledger_is_system_run(it)
             and not it.get("activityExcluded")]
    return {"items": items, "snapshotSeq": store.seq,
            "ledgerUpdatedAt": store.last_event_at,
            "collectorHeartbeatAt": store.collector_heartbeat_at,
            "serverNow": now, "counts": store.summary(now)}


# -- activity feed: classification marks + threads (queue 176) -----
#
# The identity page's stream is the assistant's ACTIVITY (positioning
# contract, briefs/identity-feed-positioning.md): one thread per
# piece of work done FOR the user. The ledger stays the full audit
# book -- nothing is deleted or hidden from it; the classification
# in activity_feed.py decides what the activity exits may carry,
# and this pass stamps the excluded items in the book itself
# (activityExcluded + activityReason) so the verdict is auditable
# and back-traceable from the audit faces. The pass is pure
# bookkeeping: it never touches status, evidence or counts (the
# C-4 discipline), and it is idempotent -- a steady-state pass
# appends nothing.

def _ledger_activity_reconcile() -> int:
    """Stamp activityExcluded/activityReason on every item whose
    classification disagrees with its current stamp. Returns the
    number of items (re)stamped."""
    marked = 0
    try:
        store = _ledger()
        for item in list(store.items.values()):
            excluded, reason, _proto = _activity_mod.classify_item(
                item, LEDGER_SKIP_SESSIONS)
            if excluded:
                if item.get("activityExcluded") is not True \
                        or item.get("activityReason") != reason:
                    store.update_fields(
                        item["id"],
                        {"activityExcluded": True,
                         "activityReason": reason},
                        by="collector")
                    marked += 1
            elif item.get("activityExcluded"):
                store.update_fields(
                    item["id"],
                    {"activityExcluded": False,
                     "activityReason": None},
                    by="collector")
                marked += 1
    except Exception as e:
        _print(f"ledger activity classify failed: {e!r}",
               file=sys.stderr, flush=True)
    return marked


def _ledger_threads_view(cursor, limit) -> dict:
    """The activity feed as threads: included items grouped by
    the deterministic identity keys in activity_feed.py,
    in-progress threads pinned first, then endedAt descending,
    keyset-paginated. Assembly is a pure function of the book,
    so the same book always yields the same threads."""
    store = _ledger()
    items = [_ledger_mod.item_view(it)
             for it in store.items.values()]
    threads = _activity_mod.assemble_threads(
        items, LEDGER_SKIP_SESSIONS)
    page, next_cursor = _activity_mod.paginate_threads(
        threads, cursor, limit)
    return {"threads": page, "nextCursor": next_cursor,
            "totalThreads": len(threads),
            "inProgress": sum(1 for t in threads
                               if t["inProgress"]),
            "snapshotSeq": store.seq,
            "ledgerUpdatedAt": store.last_event_at,
            "serverNow": _now()}


# -- title engine: model headlines at thread close (queue 193) --
#
# Bar 2 of the activity-feed rework (proposal sec.3). When a
# thread closes, its on-record material is queued and the
# instance's default model writes the thread's headline
# asynchronously. The model is NEVER named in this code and the
# engine has no model key of its own (user-ruled 2026-11-26
# 19:38): submissions carry GEN_MODEL, the generation chain's
# own variable, read from the instance configuration
# (ONEDAY_GEN_MODEL) exactly as the rounds read it -- retune
# the instance and the engine follows. The exits never wait: the
# thread shelves with its rule-derived headline (173/183, now
# the standing fallback) and is renamed in place when the
# summary lands (titleHumanSource="model" on the written member;
# assemble_threads prefers it). The pure half -- prompt, output
# gates, fingerprint, queue state machine -- is title_engine.py
# (_title_mod); this section is the gateway-bound half: queue
# persistence, material assembly, the /v1/runs submission (the
# generation rounds' own route), the write-back and the worker.
#
# Cost + failure discipline (all enforced in _title_mod):
# one summary per close (queue key = threadId + close
# fingerprint); bounded attempts per enqueue, bounded requeues
# after a cooldown; a dead channel degrades to the rule headline
# with the entry resting as failed -- never a blank title, never
# a blocked exit. Submissions/successes/failures are cumulative
# counters in the queue file and surface on the counts view.

TITLE_SESSION_ID = "oneday-title-summary"
TITLE_QUEUE_PATH = Path(os.environ.get(
    "TITLE_QUEUE_PATH",
    str(LEDGER_PATH.parent / "title-summary-queue.json")))
TITLE_POLL_SECONDS = 5
TITLE_TIMEOUT_SECONDS = 240
TITLE_ENQUEUE_PER_PASS = 20
TITLE_WORKER_IDLE_SECONDS = 5
TITLE_RETRY_PAUSE_SECONDS = 30

_title_queue_lock = threading.Lock()
_title_queue_state = None
_title_worker_started = False


def _title_queue_load() -> dict:
    """The persisted queue state, loaded once and kept in
    memory; every mutation saves through _title_queue_save.
    A missing or corrupt file starts a fresh state -- the
    engineStartedAt stamp it records is what keeps pre-engine
    closes out of this bar (the stock backfill is bar 3)."""
    global _title_queue_state
    if _title_queue_state is not None:
        return _title_queue_state
    state = None
    try:
        raw = TITLE_QUEUE_PATH.read_text(encoding="utf-8")
        parsed = json.loads(raw)
        if isinstance(parsed, dict) \
                and isinstance(parsed.get("entries"), dict) \
                and isinstance(parsed.get("counters"), dict):
            state = parsed
    except Exception:
        state = None
    if state is None:
        state = _title_mod.new_state(_now())
        _title_queue_state = state
        _title_queue_save()
    else:
        _title_queue_state = state
    return _title_queue_state


def _title_queue_save() -> None:
    """Atomic write (tmp + rename, 0600) -- same discipline as
    the vault's stores. Caller holds _title_queue_lock."""
    try:
        TITLE_QUEUE_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = TITLE_QUEUE_PATH.with_suffix(".json.tmp")
        tmp.write_text(
            json.dumps(_title_queue_state, ensure_ascii=False),
            encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(TITLE_QUEUE_PATH)
    except Exception as e:
        _print(f"title queue save failed: {e!r}",
               file=sys.stderr, flush=True)


def _title_first_user_text(session_id) -> str:
    """The session's first user message from state.db (read-only,
    the humanize pass's precedent) -- the intent of record for a
    run thread. Empty when the session or its messages are gone:
    an absent intent is honest, an invented one is not."""
    import sqlite3
    if not session_id or not _HUMANIZE_STATE_DB.exists():
        return ""
    try:
        con = sqlite3.connect(
            f"file:{_HUMANIZE_STATE_DB}?mode=ro", uri=True,
            timeout=5)
        try:
            row = con.execute(
                "SELECT content FROM messages WHERE session_id=?"
                " AND role='user' ORDER BY id LIMIT 1",
                (session_id,)).fetchone()
        finally:
            con.close()
    except Exception:
        return ""
    if not row or row[0] is None:
        return ""
    content = row[0]
    if isinstance(content, str) and content.lstrip().startswith("["):
        try:
            content = json.loads(content)
        except Exception:
            pass
    return _ledger_message_text(content).strip()


def _title_step_line(step) -> str:
    """One condensed step line for the prompt: verb + object,
    with the failure mark where the record carries one. Shapes
    are _ledger_thread_steps' own (run tool calls, approval ops,
    history transitions)."""
    if not isinstance(step, dict):
        return ""
    if step.get("tool"):
        line = str(step["tool"])
        preview = str(step.get("preview") or "").strip()
        if preview:
            line += "：" + preview[:60]
        if step.get("ok") is False:
            line += "（失败）"
        if step.get("failReason"):
            line += "（失败）"
        return line
    if step.get("action"):
        line = str(step["action"])
        if step.get("object"):
            line += " " + str(step["object"])
        if step.get("result"):
            line += f"（{step['result']}）"
        return line
    if step.get("summary"):
        return str(step["summary"])
    return ""


def _title_thread_material(thread, store):
    """(intent, step_lines, outcome, write_target_id) for one
    closed thread, assembled only from data already on record
    (proposal sec.3 inputs). The write target is the member the
    assembly's representative rule would pick (latest end, then
    id) -- the engine writes its two fields onto that one member
    and assemble_threads prefers the model-carrying member from
    then on."""
    members = []
    for iid in thread.get("itemIds") or []:
        detail = store.detail(iid)
        if detail is not None:
            members.append(detail)
    if not members:
        return "", [], "", None
    target = max(members, key=lambda m: (
        m.get("endedAt") or m.get("startedAt") or 0,
        str(m.get("id") or "")))
    proto = thread.get("prototype")
    intent = ""
    if proto == "run":
        for m in members:
            intent = _title_first_user_text(m.get("sessionId"))
            if intent:
                break
        if not intent:
            seed = str(target.get("title") or "")
            if seed and not _activity_mod.is_instruction_head(seed):
                intent = seed
    elif proto == "approval":
        intent = str(target.get("title_human")
                     or target.get("title") or "")
    else:
        intent = str(target.get("title") or "")
    step_lines = []
    for m in members:
        for step in _ledger_thread_steps(m):
            line = _title_step_line(step)
            if line:
                step_lines.append(line)
            if len(step_lines) >= _title_mod.STEP_LINES_CAP:
                break
        if len(step_lines) >= _title_mod.STEP_LINES_CAP:
            break
    status = str(thread.get("status") or "")
    outcome = {"completed": "成功完成", "failed": "失败",
               "cancelled": "已取消"}.get(status, status or "已结束")
    for m in members:
        if m.get("failReason"):
            outcome += f"；失败原因：{m['failReason']}"
            break
    return intent, step_lines, outcome, target.get("id")


def _title_submit_run(prompt: str, idem_key: str) -> tuple:
    """(run_id, error): submit one title summary run on the
    generation rounds' own route (/v1/runs), carrying the
    instance default model (GEN_MODEL, the rounds' own source).
    Stateless first; if the gateway
    insists on a session, the dedicated title session is ensured
    and the submit retried bound to it (that session is in
    LEDGER_SKIP_SESSIONS, so its own ledger record classifies
    as a system round and never enters the feed)."""
    headers = {"Authorization": f"Bearer {HERMES_API_KEY}",
               "Idempotency-Key": idem_key}
    status, payload, raw = _http_json(
        HERMES_BASE_URL + "/v1/runs", method="POST",
        body={"input": prompt, "model": GEN_MODEL},
        headers=headers, timeout=60)
    if status in (200, 201, 202) and isinstance(payload, dict) \
            and payload.get("run_id"):
        return payload["run_id"], None
    if status == 400 and "session" in raw.lower():
        _http_json(
            HERMES_BASE_URL + "/api/sessions", method="POST",
            body={"id": TITLE_SESSION_ID,
                  "title": "活动标题汇总（自动）"},
            headers={"Authorization": f"Bearer {HERMES_API_KEY}"},
            timeout=30)
        status, payload, raw = _http_json(
            HERMES_BASE_URL + "/v1/runs", method="POST",
            body={"input": prompt, "model": GEN_MODEL,
                  "session_id": TITLE_SESSION_ID},
            headers=headers, timeout=60)
        if status in (200, 201, 202) \
                and isinstance(payload, dict) \
                and payload.get("run_id"):
            return payload["run_id"], None
    return None, f"提交标题汇总失败（HTTP {status}）{raw[:120]}"


def _title_poll_run(run_id: str) -> tuple:
    """(output, error): poll a title run to a terminal state,
    the ideas rounds' poll shape with the title budget."""
    headers = {"Authorization": f"Bearer {HERMES_API_KEY}"}
    deadline = _now() + TITLE_TIMEOUT_SECONDS
    while _now() < deadline:
        status, payload, _ = _http_json(
            HERMES_BASE_URL + f"/v1/runs/{run_id}",
            headers=headers, timeout=30)
        if status == 200 and isinstance(payload, dict):
            state = str(payload.get("status", ""))
            if state == "completed":
                return str(payload.get("output") or ""), None
            if state in ("failed", "cancelled", "interrupted"):
                return None, f"标题汇总运行终态 {state}"
        time.sleep(TITLE_POLL_SECONDS)
    return None, f"标题汇总运行超时（>{TITLE_TIMEOUT_SECONDS}s）"


def _title_enqueue_reconcile() -> int:
    """Enqueue newly closed threads for model summarising.
    Runs on the collector cadence with its own failure line.
    Only closes at/after the engine's first boot are enqueued
    (older stock is bar 3's backfill, by the proposal's own
    staging); in-progress threads wait for their close."""
    enqueued = 0
    try:
        store = _ledger()
        state = _title_queue_load()
        started = state.get("engineStartedAt") or 0
        items = [_ledger_mod.item_view(it)
                 for it in store.items.values()]
        by_id = {it.get("id"): it for it in items}
        threads = _activity_mod.assemble_threads(
            items, LEDGER_SKIP_SESSIONS)
        with _title_queue_lock:
            for thread in threads:
                if enqueued >= TITLE_ENQUEUE_PER_PASS:
                    break
                if thread["inProgress"] \
                        or not thread.get("endedAt"):
                    continue
                if thread["endedAt"] < started:
                    continue
                fp = _title_mod.fingerprint(thread)
                members = [by_id.get(iid) for iid in
                           thread.get("itemIds") or []]
                if any(m and m.get("titleHumanSource") == "model"
                       and m.get("titleFingerprint") == fp
                       for m in members):
                    continue
                if _title_mod.enqueue(
                        state, thread["threadId"], fp, _now()):
                    enqueued += 1
            if enqueued:
                _title_queue_save()
    except Exception as e:
        _print(f"title enqueue failed: {e!r}",
               file=sys.stderr, flush=True)
    return enqueued


def _title_worker_loop() -> None:
    """Drain the summary queue, newest close first. One entry at
    a time: submit, poll, gate-check, write back onto the target
    member. Every failure path lands in the queue state (bounded
    attempts, then rested) -- the loop itself never dies on a
    bad entry, and the exits never wait on it."""
    while True:
        try:
            state = _title_queue_load()
            with _title_queue_lock:
                _title_mod.sweep_requeues(state, _now())
                entry = _title_mod.pick_next(state)
                if entry is not None:
                    _title_queue_save()
            if entry is None:
                time.sleep(TITLE_WORKER_IDLE_SECONDS)
                continue
            key = entry["key"]
            store = _ledger()
            items = [_ledger_mod.item_view(it)
                     for it in store.items.values()]
            threads = _activity_mod.assemble_threads(
                items, LEDGER_SKIP_SESSIONS)
            thread = None
            for cand in threads:
                if cand["threadId"] == entry["threadId"]:
                    thread = cand
                    break
            if thread is None or thread["inProgress"] \
                    or _title_mod.fingerprint(thread) \
                    != entry["fingerprint"]:
                # The close this entry was queued for is gone or
                # has moved on (new members, reopened): the entry
                # is superseded, not failed. A newer close
                # enqueues under its own fingerprint.
                with _title_queue_lock:
                    _title_mod.record_success(state, key, _now())
                    _title_queue_save()
                continue
            intent, step_lines, outcome, target_id = \
                _title_thread_material(thread, store)
            if target_id is None:
                with _title_queue_lock:
                    _title_mod.record_failure(
                        state, key, "线程成员已不在账", _now())
                    _title_queue_save()
                continue
            prompt = _title_mod.build_prompt(
                intent, step_lines, outcome)
            run_id, err = _title_submit_run(prompt, key)
            if run_id is None:
                with _title_queue_lock:
                    _title_mod.record_failure(
                        state, key, err or "提交失败", _now())
                    _title_queue_save()
                time.sleep(TITLE_RETRY_PAUSE_SECONDS)
                continue
            with _title_queue_lock:
                _title_mod.record_attempt(state, key, run_id,
                                          _now())
                _title_queue_save()
            output, err = _title_poll_run(run_id)
            parsed = None
            if err is None:
                parsed = _title_mod.parse_summary_output(output)
                if parsed is None:
                    err = "模型输出未过三关机械检"
            if parsed is None:
                with _title_queue_lock:
                    _title_mod.record_failure(
                        state, key, err or "汇总失败", _now())
                    _title_queue_save()
                time.sleep(TITLE_RETRY_PAUSE_SECONDS)
                continue
            title, summary = parsed
            store.update_fields(
                target_id,
                {"title_human": title, "summary": summary,
                 "titleHumanSource": "model",
                 "titleFingerprint": entry["fingerprint"],
                 "titleModel": GEN_MODEL,
                 "titleSummarizedAt": _now()},
                by="title-engine")
            with _title_queue_lock:
                _title_mod.record_success(state, key, _now())
                _title_queue_save()
        except Exception as e:
            _print(f"title worker failed: {e!r}",
                   file=sys.stderr, flush=True)
            time.sleep(TITLE_WORKER_IDLE_SECONDS)


def _title_start_worker() -> None:
    global _title_worker_started
    if _title_worker_started:
        return
    _title_worker_started = True
    _title_queue_load()
    threading.Thread(target=_title_worker_loop, daemon=True).start()


def _title_engine_stats() -> dict:
    """The monitoring face's window on the engine: configured
    model, queue depth by state, cumulative submission audit
    counters (queue 193 acceptance: 调用量与失败数入审计可查)."""
    try:
        state = _title_queue_load()
        out = _title_mod.stats(state)
    except Exception:
        out = {"submitted": 0, "succeeded": 0, "failedAttempts": 0,
               "pending": 0, "done": 0, "failed": 0, "awaiting": 0}
    out["model"] = GEN_MODEL
    return out



def _thread_call_parts(call):
    """(tool_name, preview) from one state.db tool_calls entry --
    the same extraction _humanize_last_tool performs for the
    session's last call, factored for sequence walks."""
    fn = (call or {}).get("function") or {}
    name = fn.get("name")
    if not isinstance(name, str) or not name:
        return None
    args = fn.get("arguments")
    preview = ""
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except Exception:
            args = None
    if isinstance(args, dict):
        for key in ("path", "file_path", "query", "url", "command",
                    "pattern", "name", "title", "prompt", "text",
                    "input"):
            val = args.get(key)
            if isinstance(val, str) and val.strip():
                preview = val.strip()
                break
        if not preview:
            for val in args.values():
                if isinstance(val, str) and val.strip():
                    preview = val.strip()
                    break
    return name, preview


def _thread_result_failed(content) -> bool:
    """A tool result counts as failed only on its own structured
    say-so (a top-level error payload); prose mentioning errors
    is not a verdict."""
    text = content if isinstance(content, str) else ""
    text = text.strip()
    if not text:
        return False
    if text.startswith("{"):
        try:
            obj = json.loads(text)
        except Exception:
            return False
        if isinstance(obj, dict):
            if obj.get("error") or obj.get("is_error") \
                    or obj.get("isError"):
                return True
    return False


def _ledger_run_tool_steps(session_id):
    """The session's tool-call sequence from state.db messages:
    (tool, preview, ok) per call, in message order. ok is set
    only when the paired tool result is on record. Returns
    (steps, total_calls)."""
    import sqlite3
    if not session_id or not _HUMANIZE_STATE_DB.exists():
        return [], 0
    try:
        con = sqlite3.connect(
            f"file:{_HUMANIZE_STATE_DB}?mode=ro", uri=True,
            timeout=5)
        try:
            rows = con.execute(
                "SELECT role, content, tool_call_id, tool_calls"
                " FROM messages WHERE session_id=?"
                " ORDER BY id LIMIT 800",
                (session_id,)).fetchall()
        finally:
            con.close()
    except Exception:
        return [], 0
    results = {}
    calls = []
    for role, content, call_id, tool_calls in rows:
        if role == "tool" and call_id:
            results[call_id] = _thread_result_failed(content)
        if role == "assistant" and tool_calls:
            try:
                parsed = json.loads(tool_calls)
            except Exception:
                continue
            if not isinstance(parsed, list):
                continue
            for call in parsed:
                parts = _thread_call_parts(call)
                if parts is None:
                    continue
                calls.append((call.get("id"), parts[0], parts[1]))
    steps = []
    for call_id, name, preview in calls:
        step = {"tool": name, "preview": preview}
        if call_id in results:
            step["ok"] = not results[call_id]
        steps.append(step)
    return steps, len(calls)


def _ledger_decision_line(pid):
    """The write-gate decision line for one approval id, or None
    when the line has rotated away (the object is then
    unrecoverable and steps fall back to the item's history --
    never guessed)."""
    if not pid:
        return None
    try:
        raw = LEDGER_DECISIONS_PATH.read_text(encoding="utf-8")
    except Exception:
        return None
    found = None
    for chunk in raw.splitlines():
        chunk = chunk.strip()
        if not chunk:
            continue
        try:
            line = json.loads(chunk)
        except Exception:
            continue
        if str(line.get("id") or "") == str(pid):
            found = line
    return found


def _ledger_approval_steps(item):
    """One step per decided op: verb + object + the decision
    itself. The ops' facts live in the decision line (the same
    source derive_title_human reads); a rotated-away line leaves
    the history fallback to the caller."""
    link = item.get("link") or {}
    pid = link.get("targetId") or ""
    line = _ledger_decision_line(pid)
    if line is None:
        return []
    decision = str(line.get("decision") or "")
    result = {"approved": "已批准", "rejected": "已驳回"}.get(
        decision, decision)
    summary = line.get("summary")
    steps = []
    parsed = _ledger_mod._parse_batch_summary(
        summary if isinstance(summary, str) else "")
    if parsed is not None:
        kinds, slugs = parsed
        obj = _ledger_mod._join_slugs(slugs)
        for kind in kinds:
            steps.append({
                "action": _ledger_mod._human_verb([kind]) or kind,
                "object": obj, "result": result})
        return steps
    m = _ledger_mod._APPLY_SUMMARY_RE.match(
        summary if isinstance(summary, str) else "")
    if m:
        where = m.group(1).strip().lower()
        obj = "用户档案" if "user" in where else (
            "长期记忆" if ("memory" in where or "profile" in where)
            else "")
        if obj:
            return [{"action": _ledger_mod._human_verb(
                        [m.group(2)]) or m.group(2),
                     "object": obj, "result": result}]
    kinds = line.get("op_kinds")
    if not isinstance(kinds, list) or not kinds:
        kinds = [line.get("op")]
    kinds = [str(k).strip() for k in kinds if k]
    obj = ""
    if line.get("mem_target") in ("memory", "user"):
        obj = "长期记忆" if line["mem_target"] == "memory" \
            else "用户档案"
    elif isinstance(line.get("target_name"), str) \
            and line["target_name"].strip():
        obj = line["target_name"].strip()
    for kind in kinds:
        steps.append({
            "action": _ledger_mod._human_verb([kind]) or kind,
            "object": obj, "result": result})
    return steps


def _ledger_history_steps(item):
    steps = []
    for entry in item.get("history") or []:
        if not isinstance(entry, dict):
            continue
        frm, to = entry.get("from"), entry.get("to")
        if to is None:
            continue
        step = {"action": f"{frm or '∅'} → {to}",
                "at": entry.get("at"), "by": entry.get("by")}
        if entry.get("note"):
            step["note"] = entry["note"]
        steps.append(step)
    return steps


_LEDGER_THREAD_STEP_CAP = 50


def _ledger_thread_steps(item):
    """Assemble one member item's steps from data already on
    record -- no new collection (proposal sec.2)."""
    kind = item.get("kind")
    if kind == "run":
        steps, _total = _ledger_run_tool_steps(
            item.get("sessionId"))
        if steps:
            return steps
        return _ledger_history_steps(item)
    if kind == "approval":
        steps = _ledger_approval_steps(item)
        if steps:
            return steps
        return _ledger_history_steps(item)
    if kind == "device":
        link = item.get("link") or {}
        step = {"tool": link.get("targetId") or "",
                "result": item.get("status")}
        if item.get("failReason"):
            step["failReason"] = item["failReason"]
        return [step]
    if kind == "kanban":
        return _ledger_history_steps(item)
    return _ledger_history_steps(item)


def _ledger_thread_detail(thread_id):
    """One thread with its steps (capped at 50, with the total
    and a counts tail when truncated) and its member items."""
    store = _ledger()
    items = [_ledger_mod.item_view(it)
             for it in store.items.values()]
    threads = _activity_mod.assemble_threads(
        items, LEDGER_SKIP_SESSIONS)
    thread = None
    for cand in threads:
        if cand["threadId"] == thread_id:
            thread = cand
            break
    if thread is None:
        return None
    out = dict(thread)
    members = []
    steps = []
    for iid in thread["itemIds"]:
        detail = store.detail(iid)
        if detail is None:
            continue
        members.append(detail)
        steps.extend(_ledger_thread_steps(detail))
    total = len(steps)
    if total > _LEDGER_THREAD_STEP_CAP:
        steps = steps[:_LEDGER_THREAD_STEP_CAP]
        steps.append({
            "summary": f"共 {total} 步，仅显示前 "
                       f"{_LEDGER_THREAD_STEP_CAP} 步"})
    out["steps"] = steps
    out["stepsTotal"] = total
    out["items"] = members
    return out
