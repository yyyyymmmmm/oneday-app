# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_ideas_gen.py -- part of modules/oneday_gateway.py,
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




# --- idea generation (P1) ----------------------------------------------------
# The bridge's first model-backed pipeline: deterministic
# material assembly from read-only paths, one Hermes /v1/runs call
# per round, strict validation before anything is stored, and a
# persisted run ledger (meta.ideasGen.history) -- failures record
# and never produce cards.
#
# Scheduling: a Hermes cron job since 1.0.59 (B-01 convergence --
# the old "cron is prompt/agent-only" premise was re-checked
# against the deployed engine and voided; see oneday_seg_cron.py).
# The engine fires POST /internal/cron/rounds/ideas at 07:30
# Asia/Shanghai, which starts the round with trigger "schedule",
# so this pipeline's idempotency key and ledger are unchanged.
# The generation prompt below is the maintainable asset; it lives
# here, in the bridge source of record
# (~/workspace/hermes-deploy/oneday_bridge.py, IDEAS_GEN_PROMPT).

HERMES_BASE_URL = os.environ.get(
    "HERMES_BASE_URL", "https://hermes.example.com").rstrip("/")
#: Dashboard (9119) channel base (batch 3): the cookie-login
#: surfaces (/auth/*, /api/cron/*, /api/plugins/*) are a different
#: process than the gateway (8642) surfaces (/v1/*, /api/sessions).
#: One public base fronted both while the bridge lived outside;
#: in-gateway the two split into loopbacks. Unset -> falls back to
#: HERMES_BASE_URL, which reproduces the bridge's single-base
#: behavior exactly.
HERMES_DASH_BASE_URL = os.environ.get(
    "HERMES_DASH_BASE_URL", "").rstrip("/") or HERMES_BASE_URL

#: C-3 (batch 3, user-approved 2026-11-24): the Dashboard channel
#: authenticates with the deployment session token
#: (HERMES_DASHBOARD_SESSION_TOKEN, Hermes' own machine credential
#: for the 9119 surfaces) instead of logging in with the user's
#: Dashboard password. HERMES_DASH_AUTH_MODE=password remains as a
#: no-code-change fallback to the legacy cookie login; token mode
#: with no token configured falls back the same way rather than
#: hard-failing the channel.
HERMES_DASH_SESSION_TOKEN = os.environ.get(
    "HERMES_DASHBOARD_SESSION_TOKEN", "")
HERMES_DASH_AUTH_MODE = os.environ.get(
    "HERMES_DASH_AUTH_MODE", "token").strip().lower()


def _dash_token_mode() -> bool:
    return HERMES_DASH_AUTH_MODE != "password" \
        and bool(HERMES_DASH_SESSION_TOKEN)


def _dash_bearer_headers() -> dict:
    return {"Authorization":
            f"Bearer {HERMES_DASH_SESSION_TOKEN}"}
HERMES_API_KEY = os.environ.get("API_SERVER_KEY") or \
    os.environ.get("HERMES_API_KEY", "")
HERMES_DASH_USER = os.environ.get("HERMES_DASH_USER", "")
HERMES_DASH_PASSWORD = os.environ.get("HERMES_DASH_PASSWORD", "")
GEN_MODEL = os.environ.get("ONEDAY_GEN_MODEL", "claude-sonnet-4-6")
GEN_SESSION_ID = "oneday-ideas-gen"
GEN_HOUR, GEN_MINUTE = 7, 30          # daily round, Asia/Shanghai
GEN_POLL_SECONDS = 5
GEN_TIMEOUT_SECONDS = 600
GEN_APPROVAL_STALL_SECONDS = 60
GEN_HISTORY_KEEP = 30
GEN_MAX_CARDS = 3

IDEAS_GEN_PROMPT = """你是 OneDay 的点子生成器。OneDay 是用户自托管的 AI 助手 App；点子页是智能体向用户提议「我可以替你做这件事」的栏目。

根据下面给定的素材，为用户想 0 到 {MAX_CARDS} 个值得做的点子。宁缺毋滥：没有真正值得做的就输出空数组 []。

素材编号：S＝近 14 天会话（附摘要）、G＝目标（附近 14 天进展）、M＝监测变化、K＝任务板、R＝长期记忆摘录、C＝近期日程（手机日历同步副本，含日期、时间与临近程度）。

每张卡是一个 JSON 对象，字段：
- title：一句话提案，必须是「我可以……」式的可执行提议（有明确产出物或动作边界），不超过 40 字。
- detail：2-4 句，写清你会做什么、产出什么、边界是什么（哪些不做、哪些要先经用户确认），不超过 200 字。**正文前半段必须先织入依据对应的锚点事实**（日期/已拍板口径/红线/专名/数字，照素材原文写）；涉及状态变化的，写清旧状态→新状态。不许把具体事实只留在 evidence 里、正文只剩泛话——正文前半段与素材行没有共享锚点的卡会被机检丢弃。
- evidence：一句话依据，必须包含素材里的一个具体事实锚点——日期、专名或数字至少其一，不许泛泛而谈，不超过 80 字。
- evidenceRef：上条依据对应的素材编号（如 S3、G1、M2、K1、R2、C1），必填；没有可对应编号的点子不要输出。
- goalId：如果这个点子明显服务于素材中某个目标，填该目标的 id（素材里给出），否则填 null。
- category：这张卡归哪一类，必填，只能取七个值之一：health（健康）、relationships（人际关系）、finance（财务）、career（事业）、interest（兴趣）、efficiency（效率提升）、other（其他）。按卡的主题选最贴切的一类，实在归不进前六类才填 other。
- domain：这张卡所属领域，必填，只能取十二个值之一：personal_productivity（个人效率）、entertainment（娱乐）、shopping（购物）、finance（财务）、relationships（人际关系）、health（健康）、career（事业）、home_automation（智能家居）、connect_devices（设备连接）、creation_media（创作媒体）、family（家庭）、goal_scoped（目标相关）。按卡的主题选最贴切的一个；与某个目标直接相关的选 goal_scoped。
- categoryLabel：这张卡的自由分类标签，必填，用一个简短中文短语概括它具体是哪一摊事（如「年会」「服务器运维」「Ai 培训」「订阅选购」），不超过 12 个字。不要填 domain 的中文名，要填这张卡自己的主题。
- kind：这张卡的落点形态，必填，只能取三个值之一：chat（点开就是一次对话，我在对话里把事办了）、routine（点开建成一条定时例行，适合每天/每周重复发生的事）、goal（点开立为一个长期目标，适合要持续推进数周以上的事）。按这件事的真实形态选；一轮里以 chat 为主，routine 至多一张、goal 至多一张。
- emoji：按这个点子的内容选一个最贴切的 emoji（只给一个，如 📄、🎤、🛒、🏠），不要给文字或多个。
- deliverables：点开这张卡后「包含哪些内容」的交付物清单，1 到 3 项，每项 {"name": "交付物名（如 年会主持稿文档）", "summary": "一句话说明（如 可直接念的完整主持稿）"}；产出物说不清的卡不要输出。
- quality：你对这张卡的质量自评 {"relevance": 相关度, "novelty": 新颖度, "feasibility": 可行性}，各填 0 到 100 的整数。相关度看与用户近况的贴合、新颖度看是不是老调重弹、可行性看我能不能凭现有素材与工具真做成。照实打分，评分只影响排序、不决定卡的生死。

质量标杆（达不到这个具体程度的卡不要输出）：
1. 「把定稿主持稿做成年会当天包」——依据点名 10 月 29 日确认的主持稿原稿、12 月 18 日 14 时、阳光会议中心，产出物明确（一份当天包）。
2. 「扫清产品博客残留的旧版定价说法」——按 10 月 29 日新版口径逐篇改写旧文、补每月额度说明，边界明确。

硬规则：
- 只输出一个 JSON 数组，不要任何解释文字、不要 Markdown 代码围栏。
- 锚点门：evidence 没有日期/专名/数字的、evidenceRef 对不上素材编号的，一律不输出。
- 正文锚点门：detail 前半段必须出现素材行里的锚点事实（日期串/专名/数字至少其一，与 evidence 同源）；只在 evidence 里具体、正文泛泛的卡一律不输出。
- 动作门：资讯转述、感想、「建议你考虑……」式泛泛建议一律不输出；放之四海皆准的话（如「建议整理一下任务清单」）一律不输出。
- 日程门：C 的价值在时机——临近的日程做准备、刚过去的日程做跟进；订阅的公共节假日日历（如 US Holidays）条目不是用户本人的安排，单独不许作为出卡依据，只能作背景参照。
- 不要重复：与「已有卡片」「已忽略清单」标题重复或近义的不输出；同一素材编号已在已有卡片/已忽略/已办清单里出现过的，不要再用这个编号出卡（换角度必须换依据）。
- 如果给了「方向简报」，优先按简报的方向想；简报没覆盖的方面也可以想，但不要偏离太远。
- 不要提议违法、有害或替用户对外发送消息/付款/签约类动作；这类事最多提议「准备好材料供用户确认」。
- 只依据给定素材作答：不要调用工具，不要读写文件、记忆或网络。

素材：
"""

#: ideas v2 (0.39.0, spec three-pages-mechanism-v2 ch.2): the S
#: source is two-stage -- one flash round first compresses the
#: last 14 days of main/side sessions into anchor-preserving
#: summaries, and only the summaries enter the generation
#: material. Titles alone were the root cause of the first
#: round's all-meta cards.
SESSION_DIGEST_PROMPT = """你是 OneDay 的会话摘要器。下面给出最近 14 天的若干段会话节选（编号 D）。

为每段会话写一句摘要（不超过 110 字）：谈了什么事、定了什么、留了什么尾巴。必须保留原文中的事实锚点——日期、专名（人名/项目名/地名）、数字——不许改写、不许编造。某段实在没有实质内容时 summary 填 ""。

只输出一个 JSON 数组：[{"ref":"D1","summary":"..."}]，不要任何解释文字、不要 Markdown 代码围栏。

会话节选：
"""

#: The action gate is a semantic judgement with no reliable
#: programmatic check; per the spec it is enforced by the
#: generation prompt above plus this self-check round, plus the
#: user's 『太泛』 feedback flowing into the avoidance material.
#: Ideas G (1.0.16, report muse-three-pages-essence-20261111
#: ch.3): the check round is no longer the model judging its own
#: cards from the card face alone -- each candidate arrives WITH
#: the material line its evidenceRef points at, and the checker
#: must verify every concrete claim (date / number / proper noun
#: / decided wording) against that line (entailment, G2). Cards
#: that fail get exactly one rewrite attempt fed with the check
#: issues (IDEAS_REWRITE_PROMPT); a rewrite that still fails is
#: dropped as "unsupported".
IDEAS_CHECK_PROMPT = """你是 OneDay 点子页的质检员。下面给出候选点子卡，每张卡附它依据的素材行原文。逐卡做两件事：

1. 事实蕴含检查：把标题、正文、依据里的具体断言（日期、数字、专名、已拍板口径、决定、对象）逐条抽出来，每条都必须能在对应素材行里找到原文支撑。素材行里没有的断言，哪怕听起来合理，也算无支撑。
2. 具体程度判断：标题是「我可以为你做 X」式的可执行提议（有明确产出物或动作边界），正文写清做什么、产出什么、边界是什么。资讯转述、感想、放之四海皆准的泛泛建议（如「建议你整理一下任务清单」）一律不合格。

标杆卡：
1. 《把定稿主持稿做成年会当天包》——依据点名 10 月 29 日确认的主持稿原稿、12 月 18 日 14 时、阳光会议中心，产出物是一份当天包。
2. 《扫清产品博客残留的旧版定价说法》——按 10 月 29 日新版口径逐篇改写旧文、补每月额度说明，边界明确。

只输出一个 JSON 数组：[{"title":"候选卡的原样标题","ok":true,"issues":""}]；不合格的 ok 填 false，issues 逐条写明问题——无支撑的断言把原句引出来（如：断言「11月20日发布」在素材行中无支撑），泛的指出泛在哪。不要任何解释文字、不要 Markdown 代码围栏。

候选卡与素材：
"""

#: Ideas G (1.0.16): the single rewrite attempt for cards the
#: entailment check failed. The rewrite is fed the failed card,
#: the checker's issues and the material line; it may only speak
#: from the material line. Output goes through the full parse
#: gates (incl. the G1 detail-anchor machine check) and one more
#: entailment check before it may land.
IDEAS_REWRITE_PROMPT = """你是 OneDay 点子的改写员。下面有几张没通过质检的点子卡，每张附质检指出的问题和它依据的素材行原文。逐卡改写：

- 只依据素材行说话：删掉或修正素材里没有的断言，不许新编日期、数字、专名、口径。
- 正文前半段先织入素材里的锚点事实（日期/已拍板口径/红线/专名/数字）；涉及状态变化的写清旧状态→新状态。
- 标题保持「我可以……」式可执行提议（可微调，不超过 40 字）；正文 2-4 句，写清做什么、产出什么、边界是什么，不超过 200 字；依据一句话，必须含素材里的锚点，不超过 80 字。
- evidenceRef 保持原卡编号不变，goalId/emoji/deliverables/category/domain/categoryLabel/kind 照原卡或按素材修正；素材实在撑不起这张卡的，不要输出这张卡。

字段与原卡相同：title/detail/evidence/evidenceRef/goalId/emoji/deliverables/category/domain/categoryLabel/kind/quality。只输出一个 JSON 数组，不要任何解释文字、不要 Markdown 代码围栏。

待改写的卡：
"""

#: an anchor ref as printed in the material: one source letter
#: (S/G/M/K/R/C) plus its 1-based index within the round
ANCHOR_REF_RE = re.compile(r"^[SGMKRC][0-9]+$")
_ANCHOR_DATE_RE = re.compile(
    r"\d{4}[-/年]\d{1,2}[-/月]\d{1,2}|\d{1,2}月\d{1,2}日")
_ANCHOR_REF_TOKEN_RE = re.compile(r"[SGMKRC][0-9]+")

GEN_SESSION_DAYS = 14           # S window (was 7, titles only)
GEN_SESSION_CAP = 12            # sessions listed per round
GEN_SESSION_SUMMARY_CAP = 8     # sessions summarised per round
GEN_SESSION_EXCERPT_CHARS = 4000
GEN_GOAL_ENTRY_DAYS = 14        # G progress entries window
GEN_KANBAN_CAP = 10             # K lines per round
GEN_MEMORY_DAYS = 30            # R recency window (file-level)
GEN_MEMORY_CAP = 10             # R lines per round
GEN_DIGEST_CACHE_KEEP = 48      # meta.sessionDigests cap
GEN_CAL_PAST_DAYS = 3           # C window: just-ended / ongoing side
GEN_CAL_FUTURE_DAYS = 14        # C window: upcoming side (== card
                                # lifetime, so a prep card cannot
                                # outlive the event it prepares for)
GEN_CAL_CAP = 10                # C lines per round
GEN_CAL_STALE_SECONDS = 24 * 3600   # copy older than this stops
                                # the whole C section (B3, 2026-11-24:
                                # a stale copy serves no lines at
                                # all, never holiday filler)

_generating = False
_generating_lock = threading.Lock()


def _gen_meta_locked() -> dict:
    gen = _db["meta"].setdefault("ideasGen", {})
    gen.setdefault("lastRunAt", None)
    gen.setdefault("nextRunAt", None)
    gen.setdefault("history", [])
    return gen


def _gen_record_locked(rec: dict) -> None:
    gen = _gen_meta_locked()
    gen["history"].append(rec)
    gen["history"] = gen["history"][-GEN_HISTORY_KEEP:]
    gen["lastRunAt"] = rec["at"]
    _save_locked()
    _ledger_job_finish("ideas", rec)


def _next_gen_time(after_epoch: float) -> float:
    tz = _sched_tz()
    dt = datetime.fromtimestamp(after_epoch, tz=tz)
    cand = dt.replace(hour=GEN_HOUR, minute=GEN_MINUTE,
                      second=0, microsecond=0)
    if cand.timestamp() <= after_epoch:
        cand += timedelta(days=1)
    return cand.timestamp()


def _http_json(url: str, *, method="GET", body=None, headers=None,
               opener=None, timeout=30):
    """One JSON HTTP call. Returns (status, parsed-or-None, raw)."""
    data = None
    hdrs = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=data, headers=hdrs,
                                 method=method)
    open_fn = opener.open if opener is not None else urllib.request.urlopen
    try:
        with open_fn(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", errors="replace")
            try:
                return r.status, json.loads(raw), raw
            except Exception:
                return r.status, None, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace") \
            if e.fp is not None else ""
        try:
            return e.code, json.loads(raw), raw
        except Exception:
            return e.code, None, raw


def _session_excerpt(messages: list) -> str:
    """One session's substance for the digest round: user/assistant
    text only (tool rows carry no decisions), most recent first
    until the char budget runs out, then restored to chrono
    order."""
    rows = []
    for m in messages or []:
        if m.get("role") not in ("user", "assistant"):
            continue
        text = " ".join(str(m.get("text") or "").split())
        if text:
            rows.append((m["role"], text[:600]))
    picked, budget = [], GEN_SESSION_EXCERPT_CHARS
    for role, text in reversed(rows):
        picked.append((role, text))
        budget -= len(text)
        if budget <= 0:
            break
    picked.reverse()
    return "\n".join(
        ("用户：" if role == "user" else "助手：") + text
        for role, text in picked)


def _digest_cache_get(sid: str, message_count: int):
    """Cached summary for (session, messageCount), or None on a
    miss. A cached "" is a real hit: the digest round found no
    substance in that session."""
    with _lock:
        cache = _db["meta"].get("sessionDigests") or {}
        entry = cache.get(sid)
    if isinstance(entry, dict) and entry.get("mc") == message_count:
        return entry.get("sum")
    return None


def _run_digest_round(queue: list) -> tuple:
    """(fresh, note): one flash run summarising the queued
    sessions. fresh maps session id -> (messageCount, summary);
    summary "" means the model found no substance. Any failure
    returns ({}, reason) and the round proceeds title-only."""
    parts = [SESSION_DIGEST_PROMPT]
    refs, usable = {}, []
    for n, s in enumerate(queue):
        messages = _ledger_messages(s["id"])
        excerpt = _session_excerpt(messages) if messages else ""
        if not excerpt:
            continue
        ref = f"D{n + 1}"
        refs[ref] = s["id"]
        usable.append(s)
        day = datetime.fromtimestamp(s["startedAt"], tz=_sched_tz())
        parts.append(f"## {ref}（{day.strftime('%m-%d')}）"
                     f"《{s['title'][:60]}》\n{excerpt}")
    if not usable:
        return {}, None
    # The digest key carries this round's start epoch, NOT a hash
    # of the queue contents (hermes-deploy 2.5.0). The old
    # content-addressed key (sha256 of "sid:messageCount" pairs)
    # collided across rounds whenever the same queue recurred with
    # a different payload -- a retitled session, a drifted excerpt
    # or a prompt change all produce a different body under the
    # same key, Hermes answers 409, and the key stays poisoned for
    # that queue forever. Same fix as the main generation key
    # above and the feed pipeline (oneday_seg_feed.py,
    # 2026-11-11): stable within one round (a genuine same-payload
    # retry still dedupes), unique across rounds.
    idem = f"ideas-sum-{int(_now())}"
    run_id, err = _hermes_submit_run("\n\n".join(parts), idem)
    if err:
        return {}, f"会话摘要轮提交失败：{err}"
    output, err = _hermes_poll_run(run_id)
    if err:
        return {}, f"会话摘要轮失败：{err}"
    text = output.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
    start, end = text.find("["), text.rfind("]")
    if start < 0 or end <= start:
        return {}, "会话摘要轮产出无法解析"
    try:
        items = json.loads(text[start:end + 1])
    except Exception:
        return {}, "会话摘要轮产出无法解析"
    if not isinstance(items, list):
        return {}, "会话摘要轮产出无法解析"
    fresh = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        sid = refs.get(str(item.get("ref") or ""))
        if sid:
            fresh[sid] = str(item.get("summary") or "").strip()[:200]
    by_id = {s["id"]: s for s in usable}
    return {sid: (by_id[sid]["messageCount"], fresh.get(sid, ""))
            for sid in by_id}, None


def _fetch_session_digests() -> tuple:
    """(sessions, note): the S source, two-stage (spec v2 ch.2).

    Stage one lists the last 14 days of main/side sessions via the
    ledger's cached Dashboard channel (cron, archived, probe and
    the generation session itself excluded). Stage two compresses
    each substantive session into one anchor-preserving summary,
    cached per (session, messageCount) in meta.sessionDigests so
    a same-day manual round reuses them. Failures degrade to
    title-only lines plus a note for the run record -- the gap is
    recorded, never hidden (the first round's note-in-material bug
    is why notes only ever go to the record)."""
    raw = _ledger_sessions()
    if raw is None:
        return [], "会话列表读取失败"
    cutoff = _now() - GEN_SESSION_DAYS * 24 * 3600
    sessions = []
    for s in raw:
        sid = s["id"]
        if s.get("source") == "cron" or sid == GEN_SESSION_ID \
                or "probe" in sid:
            continue
        # parity 2026-11-24 (§459): gateway run pseudo-sessions
        # (run_*) are pipeline seats -- feed material / writer /
        # editor runs and this line's own check runs -- not user
        # conversations. Left in, they flooded the S pool (42 of
        # 48 digest-cache entries) and ideas ended up anchored
        # to the feed pipeline's research leftovers instead of
        # the user's own sessions (Muse parity: ideas come
        # from the user's conversations).
        if sid.startswith("run_"):
            continue
        started_at = s.get("startedAt") or s.get("endedAt")
        if not started_at or started_at < cutoff:
            continue
        sessions.append({
            "id": sid,
            "title": s.get("title") or "",
            "startedAt": started_at,
            "messageCount": s["messageCount"]
            if isinstance(s.get("messageCount"), int) else 0,
            "summary": None,
        })
    sessions.sort(key=lambda x: -x["startedAt"])
    sessions = sessions[:GEN_SESSION_CAP]
    queue = []
    for s in sessions:
        if s["messageCount"] < 2:
            continue
        cached = _digest_cache_get(s["id"], s["messageCount"])
        if cached is not None:
            s["summary"] = cached or None
        elif len(queue) < GEN_SESSION_SUMMARY_CAP:
            queue.append(s)
    note = None
    if queue:
        fresh, note = _run_digest_round(queue)
        if fresh:
            with _lock:
                cache = _db["meta"].setdefault("sessionDigests", {})
                for sid, (mc, summary) in fresh.items():
                    cache[sid] = {"mc": mc, "sum": summary,
                                  "at": _now()}
                if len(cache) > GEN_DIGEST_CACHE_KEEP:
                    oldest = sorted(
                        cache.items(),
                        key=lambda kv: kv[1].get("at", 0))
                    for sid, _ in oldest[
                            :len(cache) - GEN_DIGEST_CACHE_KEEP]:
                        cache.pop(sid, None)
                _save_locked()
            for s in queue:
                if s["id"] in fresh:
                    s["summary"] = fresh[s["id"]][1] or None
    return sessions, note


_KANBAN_DONE_STATUSES = {"done", "completed", "complete",
                         "finished", "closed"}
_KANBAN_BLOCKED_STATUSES = {"blocked"}


def _task_ts(task: dict, *keys):
    for key in keys:
        value = task.get(key)
        ts = _ledger_parse_iso(value)
        if ts is None:
            ts = _ledger_norm_ts(value)
        if ts is not None:
            return ts
    return None


def _fetch_kanban_details() -> tuple:
    """(tasks, note): the K source -- oneday board tasks with
    substance (title + status + note/body excerpt + last
    activity) and a signal tag: 卡住 (blocked), 长期未动 N 天
    (no activity for 7+ days). Done tasks are NOT fed at all
    (B2, 2026-11-24): finished work cannot ground a new card,
    and six done lines round after round only taught the
    generator that everything is already done. Read via the
    ledger's Dashboard channel; fields the board does not
    carry degrade honestly (no timestamp -> no stale claim)."""
    payload = _ledger_dash.get(
        "/api/plugins/kanban/board?board=oneday")
    if not isinstance(payload, dict):
        return [], "任务板读取失败"
    raw_tasks, saw_container = [], False

    def _collect(node):
        nonlocal saw_container
        if isinstance(node, dict):
            t = node.get("tasks")
            if isinstance(t, list):
                saw_container = True
                raw_tasks.extend(
                    x for x in t if isinstance(x, dict))
            sub = node.get("columns")
            if isinstance(sub, dict):
                saw_container = True
                for col in sub.values():
                    _collect(col)
            elif isinstance(sub, list):
                saw_container = True
                for col in sub:
                    _collect(col)

    _collect(payload)
    if not raw_tasks:
        if saw_container:
            return [], "任务板为空"
        return [], "任务板格式不对"
    now = _now()
    tasks = []
    for t in raw_tasks:
        tid = t.get("id")
        if not isinstance(tid, str) or not tid:
            continue
        note_text = ""
        for key in ("body", "notes", "note", "description"):
            value = t.get(key)
            if isinstance(value, str) and value.strip():
                note_text = " ".join(value.split())[:120]
                break
        last = _task_ts(t, "updated_at", "updatedAt",
                        "modified_at") \
            or _task_ts(t, "created_at", "createdAt")
        status = str(t.get("status") or "")
        low = status.lower()
        if low in _KANBAN_DONE_STATUSES:
            continue
        signal = ""
        if low in _KANBAN_BLOCKED_STATUSES:
            signal = "卡住"
        elif last and now - last >= 7 * 24 * 3600:
            signal = f"长期未动 {int((now - last) // (24 * 3600))} 天"
        tasks.append({
            "id": tid,
            "title": str(t.get("title") or "")[:80],
            "status": status,
            "note": note_text,
            "lastAt": last,
            "signal": signal,
        })
    tasks.sort(key=lambda x: (0 if x["signal"] else 1,
                              -(x["lastAt"] or 0)))
    return tasks[:GEN_KANBAN_CAP], None


def _material_keywords(goals: list, tasks: list) -> list:
    """Keyword set for memory-excerpt selection: latin words and
    CJK runs/2-grams from goal and task titles. Selection is a
    heuristic (the spec admits misses); it only decides which
    excerpts enter the material, never what counts as evidence."""
    words = []

    def _add(text):
        words.extend(re.findall(r"[A-Za-z][A-Za-z0-9_-]{2,}", text))
        for run in re.findall(r"[一-鿿]+", text):
            if len(run) >= 2:
                words.append(run[:6])
            for i in range(len(run) - 1):
                words.append(run[i:i + 2])

    for g in goals:
        _add(str(g.get("title") or ""))
    for t in tasks:
        _add(str(t.get("title") or ""))
    seen, out = set(), []
    for w in words:
        if w not in seen:
            seen.add(w)
            out.append(w)
    return out[:60]


def _fetch_memory_excerpts(keywords: list) -> tuple:
    """(entries, note): the R source -- long-term memory excerpts
    through the write-gate bridge's GET /memories, the only
    sanctioned read surface in the memory-bridge contract
    (2026-11-09); this bridge never reads the memory files
    itself. Selection: the entry's file was updated within 30
    days (updatedAt is file-level per the contract, so recency
    is per-file, not per-entry) or the excerpt hits a goal/task
    keyword. Only the bridge-generated title+summary excerpt
    enters the material, never full text."""
    if not WRITE_GATE_BRIDGE_KEY:
        return [], "未配置记忆桥钥匙"
    status, payload, _ = _http_json(
        WRITE_GATE_BASE + "/memories",
        headers={"Authorization": f"Bearer {WRITE_GATE_BRIDGE_KEY}"},
        timeout=10)
    if status != 200 or not isinstance(payload, dict):
        return [], f"记忆条目读取失败（HTTP {status}）"
    raw = payload.get("entries")
    if not isinstance(raw, list):
        return [], "记忆条目格式不对"
    cutoff = _now() - GEN_MEMORY_DAYS * 24 * 3600
    picked = []
    for e in raw:
        if not isinstance(e, dict) or not e.get("id"):
            continue
        title = str(e.get("title") or "")
        summary = str(e.get("summary") or "")
        updated = e.get("updatedAt")
        updated = float(updated) if isinstance(
            updated, (int, float)) else 0.0
        hit = any(k in (title + summary) for k in keywords)
        if updated >= cutoff or hit:
            picked.append({
                "id": str(e["id"]),
                "target": str(e.get("target") or ""),
                "title": title[:60],
                "summary": summary[:120],
                "updatedAt": updated,
                "hit": hit,
            })
    picked.sort(key=lambda x: (0 if x["hit"] else 1,
                               -(x["updatedAt"] or 0)))
    return picked[:GEN_MEMORY_CAP], None


def _fetch_calendar_events() -> tuple:
    """(events, note): the C source (ID-1, parity spec ch.4.2) --
    the phone calendar's SYNC COPY, read through device_sync's
    own query path so the copy's serving rules are inherited,
    never re-implemented: never synced -> CopyEmpty; permission
    revoked -> SyncError(permission_revoked) and NOT ONE row is
    served (the 2026-11-10 stop-supply ruling -- the copy itself
    stays on disk, it simply stops answering). This bridge never
    opens the SQLite file directly and never calls the phone.
    Window: [now - GEN_CAL_PAST_DAYS, now + GEN_CAL_FUTURE_DAYS).
    The future side matches the generated cards' 14-day lifetime
    (a prep card must not outlive its event); the past side keeps
    just-ended / ongoing events for follow-ups (the copy carries
    no completion flag, so "unfinished" is approximated by
    recency). Ordering: ongoing/upcoming first, nearest first;
    then just-ended, newest first. Capped at GEN_CAL_CAP. A copy
    older than GEN_CAL_STALE_SECONDS serves no events at all
    (B3, 2026-11-24 -- see the stale branch below)."""
    try:
        import device_sync
    except Exception:
        return [], "日历同步模块不可用"
    if not (DEVICE_DATA_DIR / "sync.db").exists():
        return [], "日历副本尚未同步"
    now = _now()
    start = now - GEN_CAL_PAST_DAYS * 24 * 3600
    end = now + GEN_CAL_FUTURE_DAYS * 24 * 3600
    try:
        device_sync.init(DEVICE_DATA_DIR)
        raw, st = device_sync.calendar_copy_events(start, end)
    except device_sync.CopyEmpty:
        return [], "日历副本尚未同步"
    except device_sync.SyncError as e:
        if e.code == "permission_revoked":
            return [], "日历权限已撤销，同步副本停供"
        return [], f"日历副本读取失败：{e.message}"
    except Exception as e:  # copy unreadable: degrade, never crash
        return [], f"日历副本读取失败：{e}"
    events = []
    for ev in raw:
        s = device_sync._parse_ts(ev.get("start"))
        if s is None or not ev.get("occurrenceId"):
            continue
        events.append({
            "occurrenceId": str(ev["occurrenceId"]),
            "title": str(ev.get("title") or ""),
            "startTs": s,
            "endTs": device_sync._parse_ts(ev.get("end")),
            "allDay": bool(ev.get("allDay")),
            "calendarName": str(ev.get("calendarName") or ""),
            "location": str(ev.get("location") or ""),
        })
    events.sort(key=lambda e: (
        0 if (e["endTs"] or e["startTs"]) >= now else 1,
        e["startTs"] if (e["endTs"] or e["startTs"]) >= now
        else -e["startTs"]))
    events = events[:GEN_CAL_CAP]
    synced_at = st.get("synced_at") if isinstance(st, dict) else None
    if synced_at and now - synced_at > GEN_CAL_STALE_SECONDS:
        # B3 (2026-11-24): a stale copy serves NOTHING. The old
        # behaviour -- serve the rows and merely note the
        # staleness in the ledger -- left the material section
        # stocked with whatever the frozen copy still held (in
        # the 2026-11-24 drought: two US Holidays entries the
        # prompt itself forbids as sole evidence), so the C
        # section looked fed while being unusable. The section
        # now prints 无可用日程 and the reason rides the record.
        label = datetime.fromtimestamp(
            synced_at, tz=_sched_tz()).strftime("%m-%d %H:%M")
        return [], f"日历副本已过期（截至 {label}）"
    if not events:
        return events, "日程窗口内暂无条目"
    return events, None


def _calendar_proximity(ev: dict, tz) -> str:
    """Plain-words proximity label for a C material line: the
    butler value of a calendar entry is its timing, so the line
    says 今天/明天/N 天后/进行中/昨天 instead of leaving the
    model to do calendar arithmetic on raw stamps."""
    now = _now()
    start = datetime.fromtimestamp(ev["startTs"], tz=tz)
    end_ts = ev["endTs"] or ev["startTs"]
    end = datetime.fromtimestamp(end_ts, tz=tz)
    today = datetime.fromtimestamp(now, tz=tz).date()
    if ev["startTs"] <= now <= end_ts:
        return "进行中"
    if end_ts < now:
        d = (today - end.date()).days
        if d <= 0:
            return "今天早些时候"
        if d == 1:
            return "昨天"
        return f"{d} 天前"
    d = (start.date() - today).days
    if d <= 0:
        return "今天"
    if d == 1:
        return "明天"
    if d == 2:
        return "后天"
    return f"{d} 天后"


def _calendar_material_line(ref: str, ev: dict, tz) -> str:
    """One C material line: full date (a real G1 token, unlike a
    bare MM-DD stamp), time range, title, location / calendar
    name when present, proximity label. Summary only -- never a
    raw dump of the copy."""
    start = datetime.fromtimestamp(ev["startTs"], tz=tz)
    title = (ev["title"] or "（无标题）")[:60]
    if ev["allDay"]:
        when = start.strftime("%m月%d日") + " 全天"
    else:
        when = start.strftime("%m月%d日 %H:%M")
        if ev["endTs"]:
            end = datetime.fromtimestamp(ev["endTs"], tz=tz)
            if end.date() == start.date():
                when += end.strftime("–%H:%M")
            else:
                when += end.strftime("–%m月%d日 %H:%M")
    line = f"{ref}. {when} 《{title}》"
    if ev["location"]:
        line += f" 地点：{ev['location'][:40]}"
    if ev["calendarName"]:
        line += f"（日历：{ev['calendarName'][:20]}）"
    line += f"（{_calendar_proximity(ev, tz)}）"
    return line


def _assemble_material() -> tuple:
    """(prompt_text, notes, goal_ids, anchors): snapshot the world
    for one generation round (ideas v2: sources -- brief,
    S session digests, G goals with recent entries and latest
    briefing, M monitor changes, K kanban substance, R memory
    excerpts, C calendar sync copy (ID-1)). Network fetches happen outside _lock. notes maps
    source -> failure reason (record-only, never material).
    anchors maps every printed material ref (S1/G2/M1/K3/R2/C1) to
    the real object behind it; the anchor gate validates against
    this registry and stored cards keep the resolved anchorId so
    later rounds dedupe by object, not by round-relative ref.
    material_lines maps the same refs to the exact line printed
    for them; ideas G (1.0.16) feeds it to the G1 detail-anchor
    machine check and the G2 entailment check / rewrite, so both
    judge a card against the very text the generator saw."""
    sessions, session_note = _fetch_session_digests()
    tasks, kanban_note = _fetch_kanban_details()
    with _lock:
        brief = str(_db["meta"].get("brief", "") or "")
        goals = list(_db["goals"])
        entries = list(_db["goalEntries"])
        briefings = list(_db["briefings"])
        monitors = {m["id"]: m for m in _db["monitors"]}
        cutoff7 = _now() - 7 * 24 * 3600
        changes = [c for c in _db["changes"]
                   if c["detectedAt"] >= cutoff7]
        ideas = list(_db["ideas"])
    memories, memory_note = _fetch_memory_excerpts(
        _material_keywords(goals, tasks))
    cal_events, calendar_note = _fetch_calendar_events()
    tz = _sched_tz()
    anchors = {}
    material_lines = {}
    parts = [IDEAS_GEN_PROMPT]
    parts.append("## 方向简报（用户自定，可为空）\n"
                 + (brief.strip()[:1000] if brief.strip()
                    else "（空）"))
    # §459: the inspiration library rides as angle hints
    # only -- it is not material, carries no ref numbers,
    # and can never serve as a card's evidence anchor.
    with _lock:
        insp_lines = _inspiration_block_locked()
    if insp_lines:
        parts.append(
            "## 灵感库（只供想角度参考，不是素材、不能当依据；"
            "卡片仍必须以 S/G/M/K/R/C 编号素材为据）\n"
            + "\n".join(insp_lines))
    parts.append("## 近 14 天的会话（编号 S）")
    if sessions:
        for n, s in enumerate(sessions):
            ref = f"S{n + 1}"
            anchors[ref] = {"kind": "S", "objectId": s["id"],
                            "title": s["title"]}
            day = datetime.fromtimestamp(s["startedAt"], tz=tz)
            line = (f"{ref}. {day.strftime('%m-%d')} "
                    f"《{s['title'][:60]}》"
                    f"（{s['messageCount']} 条消息）")
            if s["summary"]:
                line += f"\n    摘要：{s['summary']}"
            parts.append(line)
            material_lines[ref] = line
    else:
        parts.append("（无）")
    parts.append("## 目标（编号 G，id 附后）")
    if goals:
        cutoff14 = _now() - GEN_GOAL_ENTRY_DAYS * 24 * 3600
        for n, g in enumerate(goals):
            ref = f"G{n + 1}"
            anchors[ref] = {"kind": "G", "objectId": g["id"],
                            "title": g["title"]}
            note = (g.get("note") or "").strip()[:80]
            line = (f"{ref}. 《{g['title'][:60]}》 id={g['id']}"
                    + (f" 备注：{note}" if note else ""))
            recent = [e for e in entries
                      if e["goalId"] == g["id"]
                      and e["createdAt"] >= cutoff14]
            for e in recent[-3:]:
                day = datetime.fromtimestamp(e["createdAt"], tz=tz)
                body = " ".join(str(e.get("body") or "").split())
                line += (f"\n    进展 {day.strftime('%m-%d')}："
                         f"{body[:70]}")
            goal_briefings = [b for b in briefings
                              if b["goalId"] == g["id"]]
            if goal_briefings:
                latest = max(goal_briefings,
                             key=lambda b: b["createdAt"])
                line += (f"\n    最近简报："
                         f"{str(latest.get('title') or '')[:60]}")
            parts.append(line)
            material_lines[ref] = line
    else:
        parts.append("（无）")
    parts.append("## 监测近 7 天变化（编号 M）")
    if changes:
        for n, c in enumerate(changes[:8]):
            ref = f"M{n + 1}"
            name = monitors.get(c["monitorId"], {}).get(
                "name", "监测")
            anchors[ref] = {"kind": "M", "objectId": c["id"],
                            "title": name}
            day = datetime.fromtimestamp(c["detectedAt"], tz=tz)
            line = (f"{ref}. {day.strftime('%m-%d')} "
                    f"《{name}》：{c['summary'][:80]}")
            parts.append(line)
            material_lines[ref] = line
    else:
        parts.append("（无）")
    parts.append("## 任务板（编号 K，id 附后）")
    if tasks:
        for n, t in enumerate(tasks):
            ref = f"K{n + 1}"
            anchors[ref] = {"kind": "K", "objectId": t["id"],
                            "title": t["title"]}
            line = (f"{ref}. 《{t['title']}》 id={t['id']}"
                    f" 状态：{t['status'] or '未知'}")
            if t["signal"]:
                line += f"（{t['signal']}）"
            if t["note"]:
                line += f"\n    备注：{t['note']}"
            parts.append(line)
            material_lines[ref] = line
    else:
        parts.append("（无）")
    parts.append("## 长期记忆摘录（编号 R）")
    if memories:
        for n, m in enumerate(memories):
            ref = f"R{n + 1}"
            anchors[ref] = {"kind": "R", "objectId": m["id"],
                            "title": m["title"]}
            src = {"memory": "长期记忆", "user": "用户档案"}.get(
                m["target"], "记忆")
            line = f"{ref}. [{src}] {m['title']}：{m['summary']}"
            parts.append(line)
            material_lines[ref] = line
    else:
        parts.append("（无）")
    parts.append("## 近期日程（编号 C，手机日历同步副本）")
    if cal_events:
        for n, ev in enumerate(cal_events):
            ref = f"C{n + 1}"
            anchors[ref] = {"kind": "C",
                            "objectId": ev["occurrenceId"],
                            "title": ev["title"]}
            line = _calendar_material_line(ref, ev, tz)
            parts.append(line)
            material_lines[ref] = line
    elif calendar_note and calendar_note.startswith("日历副本已过期"):
        # B3 (2026-11-24): say plainly in the material itself
        # that the section is empty because the copy is stale --
        # a bare （无） would read as "no events coming up".
        parts.append("（无可用日程：日历副本已过期）")
    else:
        parts.append("（无）")
    # B1 (2026-11-24): the two lists below print TITLES ONLY.
    # They used to carry each stored card's evidenceRef -- a
    # ROUND-RELATIVE number from the round that produced it.
    # Refs are re-numbered every round, so an old card's "S3"
    # collided literally with this round's unrelated S3 while
    # the prompt's own rule says a ref already named in these
    # lists must not be cited again -- most of this round's S
    # numbers read as spent. Dedup does not need the printed
    # refs: titles dedupe here in text, anchors dedupe in code
    # by anchorId (_anchor_block_sets).
    live = [i for i in ideas
            if i.get("status", "pending") in ("pending", "adopted")]
    parts.append("## 已有卡片（不要重复）")
    parts += [
        f"- {i['title']}"
        for i in live[:20]] or ["（无）"]
    cutoff30 = _now() - 30 * 24 * 3600
    dismissed = [i for i in ideas
                 if i.get("status") == "dismissed"
                 and (i.get("statusAt") or i["createdAt"]) >= cutoff30]
    parts.append("## 已忽略清单（30 天内不要再提；标『太泛』的"
                 "尤其不要换个说法重提）")
    parts += [
        f"- {i['title']}"
        + ("〔太泛〕" if i.get("dismissReason") == "tooGeneric"
           else "")
        for i in dismissed[:20]] or ["（无）"]
    done_titles = [i["title"] for i in live
                   if i.get("status") == "adopted" and i.get("taskId")]
    if done_titles:
        parts.append("## 已采纳在办（这些事已经在推进，不要再提）")
        parts += [f"- {t}" for t in done_titles[:20]]
    goal_ids = {g["id"] for g in goals}
    notes = {"sessions": session_note, "kanban": kanban_note,
             "memory": memory_note, "calendar": calendar_note}
    return ("\n\n".join(parts), notes, goal_ids, anchors,
            material_lines)



def _hermes_submit_run(prompt: str, idem_key: str) -> tuple:
    """(run_id, error): submit one generation run. Prefers a
    stateless run; if the gateway insists on a session, ensures the
    dedicated generation session exists and retries bound to it."""
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
            body={"id": GEN_SESSION_ID, "title": "点子生成（自动）"},
            headers={"Authorization": f"Bearer {HERMES_API_KEY}"},
            timeout=30)
        status, payload, raw = _http_json(
            HERMES_BASE_URL + "/v1/runs", method="POST",
            body={"input": prompt, "model": GEN_MODEL,
                  "session_id": GEN_SESSION_ID},
            headers=headers, timeout=60)
        if status in (200, 201, 202) and isinstance(payload, dict) \
                and payload.get("run_id"):
            return payload["run_id"], None
    return None, f"提交生成失败（HTTP {status}）{raw[:120]}"


def _hermes_poll_run(run_id: str) -> tuple:
    """(output, error): poll run status to a terminal state."""
    headers = {"Authorization": f"Bearer {HERMES_API_KEY}"}
    deadline = _now() + GEN_TIMEOUT_SECONDS
    stalled = 0.0
    while _now() < deadline:
        status, payload, _ = _http_json(
            HERMES_BASE_URL + f"/v1/runs/{run_id}",
            headers=headers, timeout=30)
        if status == 200 and isinstance(payload, dict):
            state = str(payload.get("status", ""))
            if state == "completed":
                return str(payload.get("output") or ""), None
            if state in ("failed", "cancelled", "interrupted"):
                err = payload.get("error") or payload.get("output") \
                    or state
                return None, f"生成{state}：{str(err)[:160]}"
            if state == "waiting_for_approval":
                stalled += GEN_POLL_SECONDS
                if stalled >= GEN_APPROVAL_STALL_SECONDS:
                    _http_json(
                        HERMES_BASE_URL + f"/v1/runs/{run_id}/stop",
                        method="POST", body={}, headers=headers,
                        timeout=30)
                    return None, "生成触发了待审批动作，已中止本轮"
            else:
                stalled = 0.0
        time.sleep(GEN_POLL_SECONDS)
    return None, f"生成超时（{GEN_TIMEOUT_SECONDS} 秒）"


def _evidence_has_anchor(evidence: str, anchor: dict) -> bool:
    """Anchor gate, pattern level (spec v2 ch.2): the evidence
    sentence must carry at least one concrete fact -- a date, a
    number, the anchored object's id, or a distinctive token of
    the anchored object's title. Ref tokens themselves (S3, K1...)
    are stripped before the number check so merely citing the ref
    cannot fake a fact."""
    oid = anchor.get("objectId") or ""
    if oid and oid in evidence:
        return True
    stripped = _ANCHOR_REF_TOKEN_RE.sub("", evidence)
    if _ANCHOR_DATE_RE.search(stripped) \
            or re.search(r"\d", stripped):
        return True
    title = anchor.get("title") or ""
    tokens = re.findall(r"[一-鿿]{3,}|[A-Za-z]{4,}", title)
    return any(tok in evidence for tok in tokens)


def _anchor_tokens(text: str, anchor: dict = None) -> set:
    """Concrete-fact tokens of a material line (ideas G1, 1.0.16):
    full dates, multi-digit numbers, latin proper nouns / ids,
    《》-quoted names, and the anchored object's title tokens
    (CJK runs of 3+ plus their 4-char windows). The line's own
    ref prefix and its MM-DD day stamp are stripped first so the
    round-relative scaffolding cannot masquerade as a fact."""
    t = str(text or "")
    t = re.sub(r"^[SGMKRC]\d+[.、．]\s*", "", t)
    t = re.sub(r"^\d{2}-\d{2}\s+", "", t)
    tokens = set()
    tokens.update(_ANCHOR_DATE_RE.findall(t))
    tokens.update(re.findall(r"\d{2,}(?:\.\d+)?", t))
    tokens.update(re.findall(r"[A-Za-z][A-Za-z0-9_-]{2,}", t))
    tokens.update(x.strip() for x in
                  re.findall(r"《([^》]{2,})》", t))
    # Proper nouns living in the prose (a village name, a decided
    # phrase) surface as shared 4-char CJK windows; 2-3 char
    # generic words deliberately do not qualify.
    for run in re.findall(r"[一-鿿]{4,}", t):
        for i in range(len(run) - 3):
            tokens.add(run[i:i + 4])
    if anchor:
        for run in re.findall(r"[一-鿿]{3,}",
                              str(anchor.get("title") or "")):
            tokens.add(run)
            for i in range(len(run) - 3):
                tokens.add(run[i:i + 4])
    return {re.sub(r"\s+", "", x) for x in tokens if x.strip()}


def _detail_anchor_ok(detail: str, source_text: str,
                      anchor: dict) -> bool:
    """G1 machine check: the FIRST HALF of detail must share at
    least one concrete anchor token with the material line the
    card cites (fallback: the evidence sentence itself, for
    callers without the line). A card whose facts live only in
    evidence while the body stays generic fails here -- the
    field-split gap named in the essence report ch.3."""
    head = detail[:max(1, len(detail) // 2)]
    head = re.sub(r"\s+", "", head)
    if not head:
        return False
    return any(tok and tok in head
               for tok in _anchor_tokens(source_text, anchor))


def _anchor_block_sets(ideas: list) -> tuple:
    """(live, dismissed) anchorId sets for anchor-level dedup: an
    object with a pending/adopted card is never re-proposed from
    the same anchor (adopted + taskId means the work is already
    in flight or done -- that anchor stays blocked while the card
    stands); a dismissed anchor rests 30 days. Cards predating
    ideas v2 carry no anchorId and take part through the title
    layer only."""
    live, dismissed = set(), set()
    cutoff30 = _now() - 30 * 24 * 3600
    for i in ideas:
        aid = i.get("anchorId")
        if not aid:
            continue
        status = i.get("status", "pending")
        if status in ("pending", "adopted"):
            live.add(aid)
        elif status == "dismissed" \
                and (i.get("statusAt") or i["createdAt"]) >= cutoff30:
            dismissed.add(aid)
    return live, dismissed


def _parse_generated_cards(output: str, goal_ids: set,
                           anchors: dict, ideas: list,
                           material_lines: dict = None,
                           max_cards: int = None) -> tuple:
    """(cards, dropped, reasons, error): strict-fold the model's
    JSON through the gates (ideas v2). Per card, in order: shape
    -> title dedup against all stored cards (the second dedup
    layer) -> anchor gate (evidenceRef must resolve in this
    round's registry and the evidence must carry a concrete
    fact) -> G1 detail gate (ideas G, 1.0.16: the first half of
    detail must share a concrete anchor with the cited material
    line) -> anchor dedup. A goalId the bridge does not know is
    nulled, not trusted."""
    text = output.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
    start, end = text.find("["), text.rfind("]")
    if start < 0 or end <= start:
        return [], 0, {}, "产出不是 JSON 数组"
    try:
        items = json.loads(text[start:end + 1])
    except Exception:
        return [], 0, {}, "产出 JSON 解析失败"
    if not isinstance(items, list):
        return [], 0, {}, "产出不是 JSON 数组"
    seen = {" ".join(i["title"].split()).lower() for i in ideas}
    live_anchors, dismissed_anchors = _anchor_block_sets(ideas)
    used_anchors = set()
    # §459 kind ratio (ledger item 30): chat dominates; at
    # most one routine and one goal per round -- excess cards
    # fold to chat, they are never dropped over their kind.
    kind_used = {"routine": 0, "goal": 0}
    cards, dropped = [], 0
    reasons = {"noAnchor": 0, "noAction": 0, "dupAnchor": 0,
               "noDetailAnchor": 0, "unsupported": 0, "other": 0}

    def _drop(reason):
        nonlocal dropped
        dropped += 1
        reasons[reason] += 1

    for idx, item in enumerate(items):
        if not isinstance(item, dict):
            _drop("other")
            continue
        title = str(item.get("title") or "").strip()
        detail = str(item.get("detail") or "").strip()
        evidence = str(item.get("evidence") or "").strip()
        key = " ".join(title.split()).lower()
        if not title or not detail or not evidence:
            _drop("other")
            continue
        if key in seen:
            _drop("dupAnchor")
            continue
        ref = item.get("evidenceRef")
        ref = str(ref).strip() if isinstance(ref, str) else ""
        anchor = anchors.get(ref)
        if anchor is None \
                or not _evidence_has_anchor(evidence, anchor):
            _drop("noAnchor")
            continue
        source_line = (material_lines or {}).get(ref) or evidence
        if not _detail_anchor_ok(detail, source_line, anchor):
            _drop("noDetailAnchor")
            continue
        anchor_id = f"{anchor['kind']}:{anchor['objectId']}"
        if anchor_id in live_anchors \
                or anchor_id in dismissed_anchors \
                or anchor_id in used_anchors:
            _drop("dupAnchor")
            continue
        gid = item.get("goalId")
        kind = _clean_idea_kind(item.get("kind"))
        if kind in kind_used:
            if kind_used[kind] >= 1:
                kind = IDEA_DEFAULT_KIND
            else:
                kind_used[kind] += 1
        cards.append({
            "title": title[:80],
            "detail": detail[:600],
            "evidence": evidence[:300],
            "evidenceRef": ref,
            "anchorId": anchor_id,
            "goalId": gid if gid in goal_ids else None,
            # 0.47.0 (§117): presentation fields ride along
            # tolerantly -- a card is never dropped over them
            "emoji": _clean_emoji(item.get("emoji")),
            # 1.0.34: category folds tolerantly the same way --
            # missing/illegal becomes "other", never a drop
            "category": _clean_idea_category(
                item.get("category")),
            # §459: the Muse two-dimension classification
            # and the landing kind fold tolerantly the same
            # way (domain derives from the legacy category
            # when the model omits it)
            "domain": _clean_idea_domain(
                item.get("domain"), item.get("category")),
            "categoryLabel": _clean_category_label(
                item.get("categoryLabel")),
            "kind": kind,
            "deliverables": _clean_deliverables(
                item.get("deliverables")),
            # ID-2: the quality triple rides along tolerantly
            # the same way (rev2 2.4: scored in the same pass,
            # no extra model call); malformed -> None
            "quality": _clean_quality(item.get("quality")),
        })
        seen.add(key)
        used_anchors.add(anchor_id)
        if len(cards) >= (max_cards if max_cards is not None
                          else GEN_MAX_CARDS):
            rest = len(items) - idx - 1
            if rest > 0:
                dropped += rest
                reasons["other"] += rest
            break
    return cards, dropped, reasons, None


def _self_check_cards(cards: list, idem_suffix: str,
                      material_lines: dict = None) -> tuple:
    """(kept, failed, note): the G2 entailment check (1.0.16) --
    each candidate is judged TOGETHER WITH the material line its
    evidenceRef cites: every concrete claim in title/detail/
    evidence must be supported by that line, on top of the
    benchmark specificity judgement. failed is a list of
    (card, issues) feeding the one rewrite attempt. Infra
    failure keeps the cards and only notes the gap (the anchor
    and hard gates are the hard ones); a parseable verdict list
    is honoured as given, an unparseable one is not. A card the
    checker stays silent on counts as failed, never as passed."""
    if not cards:
        return cards, [], None
    parts = [IDEAS_CHECK_PROMPT]
    for c in cards:
        line = (material_lines or {}).get(c["evidenceRef"])
        parts.append(
            f"- 标题：{c['title']}\n  内容：{c['detail']}"
            f"\n  依据：{c['evidence']}（{c['evidenceRef']}）"
            f"\n  素材行：{line if line else '（缺失）'}")
    run_id, err = _hermes_submit_run(
        "\n".join(parts), f"ideas-check-{idem_suffix}")
    if err:
        return cards, [], f"自检轮提交失败：{err}"
    output, err = _hermes_poll_run(run_id)
    if err:
        return cards, [], f"自检轮失败：{err}"
    text = output.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
    start, end = text.find("["), text.rfind("]")
    verdicts = {}
    if start >= 0 and end > start:
        try:
            items = json.loads(text[start:end + 1])
        except Exception:
            items = None
        if isinstance(items, list):
            for item in items:
                if isinstance(item, dict) \
                        and isinstance(item.get("title"), str):
                    verdicts[" ".join(
                        item["title"].split()).lower()] = (
                        item.get("ok") is True,
                        str(item.get("issues") or "").strip())
    if not verdicts:
        return cards, [], "自检轮产出无法解析"
    kept, failed = [], []
    for c in cards:
        verdict = verdicts.get(
            " ".join(c["title"].split()).lower())
        if verdict and verdict[0]:
            kept.append(c)
        else:
            failed.append((c, verdict[1] if verdict
                           else "自检未给出结论"))
    return kept, failed, None


def _rewrite_cards(failed: list, goal_ids: set, anchors: dict,
                   ideas: list, material_lines: dict,
                   idem_suffix: str) -> tuple:
    """(cards, dropped, reasons, note): the ONE rewrite attempt
    for entailment-check failures (ideas G2, 1.0.16). The model
    gets each failed card with the checker's issues and the
    material line, and may only speak from the material. Output
    re-enters through the full parse gates (shape / dedup /
    anchor / G1 detail gate) against `ideas` -- the round's
    snapshot plus the cards that already passed, so a rewrite
    cannot re-spend a kept card's anchor or title. Infra failure
    returns no cards plus a note; the caller then books the
    unrescued failures as unsupported."""
    if not failed:
        return [], 0, {}, None
    parts = [IDEAS_REWRITE_PROMPT]
    for c, issues in failed:
        line = (material_lines or {}).get(c["evidenceRef"])
        parts.append(
            f"- 标题：{c['title']}\n  内容：{c['detail']}"
            f"\n  依据：{c['evidence']}"
            f"\n  evidenceRef：{c['evidenceRef']}"
            f"\n  category：{c.get('category') or 'other'}"
            f"\n  domain：{c.get('domain') or ''}"
            f"\n  categoryLabel：{c.get('categoryLabel') or ''}"
            f"\n  kind：{c.get('kind') or 'chat'}"
            f"\n  质检问题：{issues or '未说明'}"
            f"\n  素材行：{line if line else '（缺失）'}")
    run_id, err = _hermes_submit_run(
        "\n".join(parts), f"ideas-rewrite-{idem_suffix}")
    if err:
        return [], 0, {}, f"改写轮提交失败：{err}"
    output, err = _hermes_poll_run(run_id)
    if err:
        return [], 0, {}, f"改写轮失败：{err}"
    cards, dropped, reasons, perr = _parse_generated_cards(
        output, goal_ids, anchors, ideas, material_lines,
        max_cards=99)
    if perr:
        return [], 0, {}, f"改写轮产出不可用：{perr}"
    return cards, dropped, reasons, None



def _run_generation_round(trigger: str) -> None:
    """One full round, on its own thread (never under _lock)."""
    global _generating
    started = _now()
    rec = {"at": started, "trigger": trigger, "status": "failed",
           "produced": 0, "dropped": 0, "runId": None, "error": None}
    try:
        if not HERMES_API_KEY:
            rec["status"] = "skipped"
            rec["error"] = "未配置 HERMES_API_KEY，生成管道待接通"
            return
        prompt, notes, goal_ids, anchors, material_lines = \
            _assemble_material()
        # ID-2 refill rule (rev2 2.2): this round's target is
        # the water-level gap, capped per round (cap +2 when a
        # terminal event landed since the last main round). A
        # full pool skips the model call entirely.
        with _lock:
            pool = _pool_meta_locked()
            pending_before = sum(
                1 for i in _db["ideas"]
                if i.get("source") == "generated"
                and i.get("status", "pending") == "pending")
            cap = POOL_REFILL_CAP + (
                POOL_EVENT_BONUS if pool.get("eventBonusPending")
                else 0)
            target = min(max(0, POOL_WATER_LEVEL - pending_before),
                         cap)
            if pool.get("eventBonusPending"):
                pool["eventBonusPending"] = False
                _save_locked()
        rec["target"] = target
        rec["embedding"] = "off"
        if target <= 0:
            rec["status"] = "full"
            rec["shortfall"] = 0
            return
        prompt = prompt.replace("{MAX_CARDS}", str(target))
        material_notes = {k: v for k, v in notes.items() if v}
        if material_notes:
            rec["materialNotes"] = material_notes
        if notes.get("sessions"):
            rec["materialNote"] = notes["sessions"]
        day = datetime.fromtimestamp(started, tz=_sched_tz())
        # The schedule key carries this round's start epoch, not
        # the bare day stamp: a day-granular key is shared by every
        # invocation that day, so a daytime test round submitting a
        # different payload under the same key made Hermes answer
        # the real 07:30 round with 409 and the round produced
        # nothing (2026-11-24). Same fix as the feed pipeline
        # (oneday_seg_feed.py, 2026-11-11): keys stay stable WITHIN
        # one round, so a genuine same-payload retry still dedupes,
        # and the derived check/rewrite keys inherit the epoch.
        idem = f"ideas-gen-{day.strftime('%Y%m%d')}-{int(started)}" \
            if trigger == "schedule" \
            else f"ideas-gen-manual-{int(started)}"
        run_id, err = _hermes_submit_run(prompt, idem)
        if err:
            rec["error"] = err
            return
        rec["runId"] = run_id
        output, err = _hermes_poll_run(run_id)
        if err:
            rec["error"] = err
            return
        with _lock:
            ideas_snapshot = list(_db["ideas"])
        cards, dropped, reasons, perr = _parse_generated_cards(
            output, goal_ids, anchors, ideas_snapshot,
            material_lines, max_cards=target)
        rec["dropped"] = dropped
        if perr:
            rec["error"] = perr
            rec["outputHead"] = output[:200]
            return
        # G2 (1.0.16): entailment check against the cited
        # material lines; failures get exactly one rewrite
        # attempt, and a rewrite must pass the same check again
        # before it may land -- otherwise it is booked as
        # unsupported, never silently kept.
        cards, failed, check_note = _self_check_cards(
            cards, idem, material_lines)
        if check_note:
            rec["selfCheckNote"] = check_note
        if failed:
            rewritten, rw_dropped, rw_reasons, rw_note = \
                _rewrite_cards(failed, goal_ids, anchors,
                               ideas_snapshot + cards,
                               material_lines, idem)
            if rw_note:
                rec["rewriteNote"] = rw_note
            rec["dropped"] += rw_dropped
            for k, v in rw_reasons.items():
                reasons[k] = reasons.get(k, 0) + v
            rescued = {c["anchorId"] for c in rewritten}
            for c, _issues in failed:
                if c["anchorId"] not in rescued:
                    reasons["unsupported"] += 1
                    rec["dropped"] += 1
            if rewritten:
                kept2, failed2, note2 = _self_check_cards(
                    rewritten, idem + "-rw", material_lines)
                if note2:
                    rec["rewriteNote"] = (
                        rec.get("rewriteNote", "")
                        + f"复检：{note2}").strip()
                cards += kept2
                for _c, _i in failed2:
                    reasons["unsupported"] += 1
                    rec["dropped"] += 1
        rec["droppedReasons"] = reasons
        # ID-2 vector path (rev2 2.3): embed the surviving cards
        # in one call, off-lock. K-3 downgrade: with no embedding
        # route configured this returns None and the round books
        # embedding="off" -- fingerprint-only, honestly labelled.
        vectors = None
        if cards:
            vectors = _embed_texts(
                [c["title"] + "\n" + c["detail"] for c in cards])
        rec["embedding"] = "on" if vectors else "off"
        ts = _now()
        landed, merged_count = [], 0
        with _lock:
            _pool_meta_locked()["embeddingState"] = rec["embedding"]
            iids = {i["id"] for i in _db["ideas"]}
            for idx, card in enumerate(cards):
                fp = _idea_fingerprint(card["title"],
                                       card["detail"],
                                       card["anchorId"])
                vec = vectors[idx] if vectors else None
                canon, merge_reason = _merge_target_locked(fp, vec)
                record = {
                    "id": _new_id("i_", iids),
                    "title": card["title"],
                    "detail": card["detail"],
                    "emoji": card.get("emoji"),
                    "category": _clean_idea_category(
                        card.get("category")),
                    # §459: two-dimension classification +
                    # landing kind land with the card
                    "domain": _clean_idea_domain(
                        card.get("domain"), card.get("category")),
                    "categoryLabel": _clean_category_label(
                        card.get("categoryLabel")),
                    "kind": _clean_idea_kind(card.get("kind")),
                    "deliverables": card.get(
                        "deliverables", []),
                    "goalId": card["goalId"],
                    "createdAt": ts,
                    "source": "generated",
                    "evidence": card["evidence"],
                    "evidenceRef": card["evidenceRef"],
                    "anchorId": card["anchorId"],
                    "dismissReason": None,
                    "status": "pending",
                    "taskId": None,
                    "contentFingerprint": fp,
                    "quality": card.get("quality"),
                    "poolScore": None,
                    "scoreWhy": None,
                    "mergedInto": None,
                    "mergeReason": None,
                    "origin": "native",
                    "embedding": vec,
                    "expiresAt": ts + IDEA_EXPIRE_SECONDS,
                }
                if canon is not None:
                    # rev2 2.3: duplicates map onto the
                    # canonical card, they are never deleted
                    # and never count toward pool depth
                    record["status"] = "merged"
                    record["mergedInto"] = canon["id"]
                    record["mergeReason"] = merge_reason
                    record["mergedAt"] = ts
                    record["expiresAt"] = None
                    merged_count += 1
                else:
                    landed.append(record["id"])
                _db["ideas"].append(record)
                iids.add(record["id"])
            if cards:
                snap = _build_ideas_snapshot_locked(
                    trigger, new_ids=landed)
                rec["snapshotId"] = snap["snapshotId"]
                _save_locked()
        # §475 part 2: the surviving cards and the pool
        # snapshot are in the store and saved (the block
        # above is the round's only landing action) --
        # delivery is complete HERE. produced counts
        # pool-landed cards only, the same definition the
        # record below uses. The distribution tallies and
        # the record in finally are tail work. A zero-card
        # round lands here with len(landed) == 0: every
        # seat (generation, self-check, rewrite, re-check)
        # has terminated, so it settles at the same point.
        _ledger_job_delivered("ideas", len(landed))
        rec["merged"] = merged_count
        if cards:
            # 1.0.34: the round's category distribution rides
            # the ledger record, so a parity audit can see
            # where the cards landed without opening the store
            dist: dict = {}
            for card in cards:
                key = _clean_idea_category(card.get("category"))
                dist[key] = dist.get(key, 0) + 1
            rec["categoryDist"] = dist
            # §459: the same for the two new dimensions
            ddist: dict = {}
            kdist: dict = {}
            for card in cards:
                dkey = _clean_idea_domain(
                    card.get("domain"), card.get("category"))
                ddist[dkey] = ddist.get(dkey, 0) + 1
                kkey = _clean_idea_kind(card.get("kind"))
                kdist[kkey] = kdist.get(kkey, 0) + 1
            rec["domainDist"] = ddist
            rec["kindDist"] = kdist
        # ID-2: produced counts pool-landed cards only (merged
        # mappings are booked separately above); shortfall is
        # the unfilled part of this round's refill target
        rec["produced"] = len(cards) - merged_count
        rec["shortfall"] = max(0, target - rec["produced"])
        rec["status"] = "ok" if rec["produced"] else "empty"
    except Exception as e:  # a round must never kill the scheduler
        rec["error"] = f"{type(e).__name__}: {e}"[:200]
    finally:
        with _lock:
            _gen_record_locked(rec)
            if trigger == "schedule":
                _gen_meta_locked()["nextRunAt"] = \
                    _next_gen_time(_now())
                _save_locked()
        with _generating_lock:
            _generating = False
        _print(f"ideas generation ({trigger}): {rec['status']} "
              f"produced={rec['produced']} dropped={rec['dropped']} "
              f"error={rec['error']}", flush=True)


def _start_generation(trigger: str) -> bool:
    """Start a round on a thread; False when one is already live."""
    global _generating
    with _generating_lock:
        if _generating:
            return False
        _generating = True
    _ledger_job_start("ideas")
    t = threading.Thread(target=_run_generation_round,
                         args=(trigger,), daemon=True)
    t.start()
    return True


# _generation_tick retired in 1.0.59 (B-01): the Hermes cron
# engine fires the daily round via /internal/cron/rounds/ideas;
# meta.ideasGen.nextRunAt is display bookkeeping that the round
# itself advances in its finally block (trigger == "schedule").


def _generation_view() -> dict:
    with _lock:
        gen = _gen_meta_locked()
        return {
            "lastRunAt": gen["lastRunAt"],
            "nextRunAt": gen["nextRunAt"],
            "running": _generating,
            "history": list(gen["history"]),
        }
