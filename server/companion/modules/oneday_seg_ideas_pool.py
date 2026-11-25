# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_ideas_pool.py -- part of modules/oneday_bridge.py,
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




# --- ideas pool (ID-2, spec three-pages-spec-rev2 ch.2) ---------------------
# Pool form: snapshot-based. Pending generated cards form a pool
# whose membership, grouping and order are settled by the
# generation loop into an immutable snapshot after each main
# round; readers take the active snapshot's order and never
# re-rank on their own (the App side lands with IA-1). This block
# owns: refill accounting (water level 15, per-round cap 5, +2 on
# the main round after terminal events), content-fingerprint +
# vector dual-path dedup with merge-instead-of-delete mapping,
# the three-dimension quality score, the fast/terminal feedback
# ledgers with the explore floor, anchor-liveness retirement and
# the built outcome for adopted cards.
#
# K-3 (measured 2026-11-14 against the production gateway
# api.laogou8.com, the New API relay Hermes runs on): no
# embedding channel exists for text-embedding-3-small,
# text-embedding-ada-002, bge-m3, text-embedding-v3, embedding-3
# or bge-large-zh-v1.5 -- every probe returned model_not_found.
# Per rev2 2.3's downgrade clause the vector path therefore runs
# OFF in production, every round record carries embedding="off",
# and dedup is fingerprint-only until a gateway with an embedding
# route is configured via ONEDAY_EMBED_* (no code change needed
# then). Never describe the pool as dual-path while state is off.

POOL_WATER_LEVEL = 15           # rev2 2.2: reviewed, held at 15
POOL_REFILL_CAP = 5             # per main round
POOL_EVENT_BONUS = 2            # next main round after terminal events
POOL_SNAPSHOTS_KEEP = 7
POOL_MERGE_LOOKBACK_SECONDS = 30 * 24 * 3600
QUALITY_POLICY_VERSION = "ideas_quality_oneday_v1"
QUALITY_WEIGHTS = (0.4, 0.3, 0.3)        # relevance/novelty/feasibility
POOL_SCORE_WEIGHTS = (0.5, 0.35, 0.15)   # composite/terminal/fast
VECTOR_MERGE_THRESHOLD = 0.92
EMBED_BASE_URL = os.environ.get(
    "ONEDAY_EMBED_BASE_URL", "").rstrip("/")
EMBED_API_KEY = os.environ.get("ONEDAY_EMBED_API_KEY", "")
EMBED_MODEL = os.environ.get("ONEDAY_EMBED_MODEL", "")

#: fast-channel rewards (rev2 2.5): opening a detail is weak
#: evidence, discussing is stronger, the user's own "too
#: generic" mark is the one negative fast signal. Terminal
#: rewards (adopt / built) are +1 each and outweigh fast by the
#: score weights above -- opening a card is not earning from it.
IDEA_FAST_REWARDS = {"open": 0.25, "discuss": 0.5,
                     "tooGeneric": -1.0}
IDEA_TERMINAL_REWARDS = {"adopt": 1.0, "built": 1.0}


def _pool_meta_locked() -> dict:
    pool = _db["meta"].setdefault("ideasPool", {})
    pool.setdefault("snapshots", [])
    pool.setdefault("activeSnapshotId", None)
    pool.setdefault("feedback", {"fast": {}, "terminal": {}})
    pool.setdefault("eventBonusPending", False)
    pool.setdefault("embeddingState", "off")
    pool.setdefault("config", {})
    return pool


def _idea_anchor_kind(idea: dict):
    aid = idea.get("anchorId") or ""
    if ":" in aid:
        return aid.split(":", 1)[0]
    return None


def _idea_dim_keys(idea: dict) -> tuple:
    """Feedback ledger keys for one card (rev2 2.5): anchorKind,
    category, and the pair. Cards carry no separate topic field,
    so the pair key is the finest grain the ledger keeps -- no
    topic book is invented. §459 adds the domain family (the
    Muse two-dimension classification): dom and the
    kind|domain pair ride along; the legacy keys keep their
    positions so the settled ledger stays comparable."""
    kind = _idea_anchor_kind(idea) or "-"
    cat = _clean_idea_category(idea.get("category"))
    dom = _clean_idea_domain(idea.get("domain"),
                             idea.get("category"))
    return (f"kind:{kind}", f"cat:{cat}", f"dom:{dom}",
            f"pair:{kind}|{cat}", f"paird:{kind}|{dom}")


def _record_idea_feedback_locked(idea: dict, channel: str,
                                 event: str) -> None:
    rewards = IDEA_FAST_REWARDS if channel == "fast" \
        else IDEA_TERMINAL_REWARDS
    reward = rewards.get(event)
    if reward is None:
        return
    pool = _pool_meta_locked()
    book = pool["feedback"].setdefault(channel, {})
    for key in _idea_dim_keys(idea):
        cell = book.setdefault(key, {"events": 0, "rewardSum": 0.0})
        cell["events"] += 1
        cell["rewardSum"] = round(
            float(cell.get("rewardSum") or 0.0) + reward, 3)
    if channel == "terminal":
        # rev2 2.2: after eventful days the next main round may
        # refill two extra cards instead of opening a side round
        pool["eventBonusPending"] = True


def _dim_channel_score(book: dict, keys: tuple):
    """One channel's dimension score on 0..100 (50 = neutral),
    from the first key family that has any events; None when the
    channel has never heard of this card's dimensions."""
    for key in keys:
        cell = book.get(key)
        if cell and cell.get("events"):
            r = float(cell.get("rewardSum") or 0.0)
            return max(0.0, min(100.0,
                                50.0 + 50.0 * r / (abs(r) + 2.0)))
    return None


_FP_PREFIXES = ("我可以", "我来", "我能")
_FP_PUNCT_RE = re.compile(r"[，。、；：！？·,.!?;:\s]+")


def _idea_fingerprint(title: str, detail: str, anchor_id) -> str:
    """contentFingerprint (rev2 2.3): MD5 over the card's
    normalised content -- title with its sentence-pattern prefix
    stripped, the detail's anchor-bearing head, anchor kind and
    the anchor object id. Exact equality is a duplicate."""
    t = "".join(str(title or "").split())
    for p in _FP_PREFIXES:
        if t.startswith(p):
            t = t[len(p):]
            break
    t = _FP_PUNCT_RE.sub("", t)
    head = _FP_PUNCT_RE.sub("", "".join(str(detail or "").split()))
    kind = ""
    if anchor_id and ":" in str(anchor_id):
        kind = str(anchor_id).split(":", 1)[0]
    raw = f"{t}|{head[:60]}|{kind}|{anchor_id or ''}"
    return hashlib.md5(raw.encode("utf-8")).hexdigest()


def _quality_composite(q: dict) -> int:
    return int(round(
        q["relevance"] * QUALITY_WEIGHTS[0]
        + q["novelty"] * QUALITY_WEIGHTS[1]
        + q["feasibility"] * QUALITY_WEIGHTS[2]))


def _clean_quality(value):
    """The generator's self-scored quality triple, folded
    tolerantly like every other presentation field: a malformed
    or partial triple collapses to None (the card still lands;
    its pool score falls back to the neutral base)."""
    if not isinstance(value, dict):
        return None
    out = {}
    for k in ("relevance", "novelty", "feasibility"):
        v = value.get(k)
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            return None
        out[k] = max(0, min(100, int(round(v))))
    out["composite"] = _quality_composite(out)
    out["policy"] = QUALITY_POLICY_VERSION
    return out


def _embed_texts(texts: list):
    """One embeddings call against the configured gateway route;
    None on any failure or when unconfigured (K-3 downgrade).
    Network: never call under _lock."""
    if not (EMBED_BASE_URL and EMBED_API_KEY and EMBED_MODEL):
        return None
    status, payload, _ = _http_json(
        EMBED_BASE_URL + "/embeddings", method="POST",
        body={"model": EMBED_MODEL, "input": list(texts)},
        headers={"Authorization": f"Bearer {EMBED_API_KEY}"},
        timeout=30)
    if status != 200 or not isinstance(payload, dict):
        return None
    data = payload.get("data")
    if not isinstance(data, list) or len(data) != len(texts):
        return None
    out = []
    for row in data:
        vec = row.get("embedding") if isinstance(row, dict) \
            else None
        if not isinstance(vec, list) or not vec:
            return None
        try:
            out.append([float(x) for x in vec])
        except (TypeError, ValueError):
            return None
    return out


def _cosine(a: list, b: list) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(y * y for y in b) ** 0.5
    if not na or not nb:
        return 0.0
    return dot / (na * nb)


def _pool_vector_threshold_locked() -> float:
    cfg = _pool_meta_locked().get("config") or {}
    v = cfg.get("vectorThreshold")
    if isinstance(v, (int, float)) and 0 < v <= 1:
        return float(v)
    return VECTOR_MERGE_THRESHOLD


def _merge_target_locked(fingerprint, vector):
    """(canonical idea, reason) when a new card duplicates an
    existing one (rev2 2.3): fingerprint exact match first, then
    the vector path when embeddings are live. Candidates are the
    live pool plus retired cards from the last 30 days. A merged
    card itself is never a canonical."""
    cutoff = _now() - POOL_MERGE_LOOKBACK_SECONDS
    cands = [i for i in _db["ideas"]
             if i.get("source") == "generated"
             and i.get("status") != "merged"
             and (i.get("status") in ("pending", "adopted", "built")
                  or (i.get("createdAt") or 0) >= cutoff)]
    if fingerprint:
        for i in cands:
            fp = i.get("contentFingerprint")
            if fp is None:
                fp = _idea_fingerprint(i.get("title", ""),
                                       i.get("detail", ""),
                                       i.get("anchorId"))
            if fp == fingerprint:
                return i, "fingerprint"
    if vector:
        threshold = _pool_vector_threshold_locked()
        best, best_sim = None, 0.0
        for i in cands:
            v = i.get("embedding")
            if isinstance(v, list) and v:
                s = _cosine(vector, v)
                if s > best_sim:
                    best, best_sim = i, s
        if best is not None and best_sim >= threshold:
            return best, "vector"
    return None, None


def _idea_pool_score_locked(idea: dict, pool: dict) -> tuple:
    """poolScore (rev2 2.5): the card's own quality composite
    dominates, the terminal channel out-weighs the fast channel,
    and a small freshness nudge keeps new cards visible. Missing
    signals read as neutral 50, never as zero. scoreWhy is one
    human sentence that can tell a terminal-driven rank ("you
    adopted its kind before") from an explore slot."""
    q = idea.get("quality") or {}
    composite = q.get("composite")
    base = float(composite) if isinstance(composite, (int, float)) \
        else 50.0
    keys = _idea_dim_keys(idea)
    # pair, kind|domain pair, kind, category, domain
    lookup = (keys[3], keys[4], keys[0], keys[1], keys[2])
    fb = pool.get("feedback") or {}
    t = _dim_channel_score(fb.get("terminal") or {}, lookup)
    f = _dim_channel_score(fb.get("fast") or {}, lookup)
    w = POOL_SCORE_WEIGHTS
    score = base * w[0] \
        + (t if t is not None else 50.0) * w[1] \
        + (f if f is not None else 50.0) * w[2]
    age_days = max(0.0, (_now() - float(idea.get("createdAt")
                                        or _now())) / 86400.0)
    score += max(0.0, 5.0 - age_days)
    score = round(max(0.0, min(100.0, score)), 1)
    if idea.get("poolExplore"):
        why = "新方向试探：这类素材以前没怎么推过，先放一张看看。"
    elif t is not None and t > 60:
        why = "因为你采纳过同类点子，这张优先推给你。"
    elif f is not None and f > 60:
        why = "你最近常看这类提议，这张排在前面。"
    else:
        why = "结合你近来的素材新想的提议。"
    return score, why


def _build_ideas_snapshot_locked(reason: str, new_ids=()) -> dict:
    """Settle the pool into a new active snapshot (rev2 2.1):
    sections by category in the goal-category order, cards
    ordered by poolScore inside each section, positions flat.
    The explore floor (rev2 2.5) marks at least a third of this
    round's new cards -- chosen from the least-covered
    kind|category pairs -- and no score ordering can push them
    out: every pending card is in the snapshot by construction,
    so each non-empty category structurally keeps >= 1 card.
    Only the newest batch carries explore flags."""
    pool = _pool_meta_locked()
    pending = [i for i in _db["ideas"]
               if i.get("source") == "generated"
               and i.get("status", "pending") == "pending"]
    new_set = set(new_ids or ())
    for i in pending:
        i["poolExplore"] = False
    explore_count = 0
    if new_set:
        fb = pool.get("feedback") or {}

        def _coverage(idea):
            key = _idea_dim_keys(idea)[3]
            ev = 0
            for ch in ("fast", "terminal"):
                cell = (fb.get(ch) or {}).get(key)
                if cell:
                    ev += int(cell.get("events") or 0)
            return ev

        news = [i for i in pending if i["id"] in new_set]
        news.sort(key=lambda i: (_coverage(i), i["createdAt"]))
        need = max(1, -(-len(news) // 3)) if news else 0
        for i in news[:need]:
            i["poolExplore"] = True
            explore_count += 1
    for i in pending:
        score, why = _idea_pool_score_locked(i, pool)
        i["poolScore"] = score
        i["scoreWhy"] = why
    sections, positions = [], {}
    order = 0
    # §459: sections settle by DOMAIN (the Muse two-dimension
    # classification), in Muse's domain order; the free
    # categoryLabel rides the card, not the section. Pre-§459
    # snapshots in the store keep their {"category": ...}
    # sections -- history is not rewritten.
    for dom in IDEAS_DOMAINS:
        group = [i for i in pending
                 if _clean_idea_domain(i.get("domain"),
                                       i.get("category")) == dom]
        if not group:
            continue
        group.sort(key=lambda i: (-(i.get("poolScore") or 0),
                                  i["createdAt"]))
        sections.append({"domain": dom,
                         "cardIds": [i["id"] for i in group]})
        for i in group:
            positions[i["id"]] = order
            order += 1
    snap = {"snapshotId": f"snap_{int(_now() * 1000)}",
            "createdAt": _now(), "reason": reason,
            "sections": sections, "positions": positions,
            "exploreCount": explore_count}
    snaps = (pool.get("snapshots") or []) + [snap]
    pool["snapshots"] = snaps[-POOL_SNAPSHOTS_KEEP:]
    pool["activeSnapshotId"] = snap["snapshotId"]
    return snap


def _active_snapshot_view_locked():
    pool = _pool_meta_locked()
    for s in pool.get("snapshots") or []:
        if s.get("snapshotId") == pool.get("activeSnapshotId"):
            return {"snapshotId": s["snapshotId"],
                    "createdAt": s["createdAt"],
                    "sections": s["sections"]}
    return None


def _retire_dead_anchor_ideas_locked() -> int:
    """Anchor-liveness retirement (rev2 2.7): a pending card
    whose goal was completed/deleted or whose monitor was
    removed/disabled leaves the pool as expired(anchorGone)
    instead of recommending against a dead anchor. Session /
    memory / calendar anchors have no liveness object to check
    and are left to the 14-day age rule."""
    goals = {g["id"]: g for g in _db["goals"]}
    monitors = {m["id"]: m for m in _db["monitors"]}
    n = 0
    for idea in _db["ideas"]:
        if idea.get("source") != "generated" \
                or idea.get("status", "pending") != "pending":
            continue
        aid = idea.get("anchorId") or ""
        if ":" not in aid:
            continue
        kind, oid = aid.split(":", 1)
        dead = False
        if kind == "G":
            g = goals.get(oid)
            dead = g is None or g.get("status") == "completed"
        elif kind == "M":
            m = monitors.get(oid)
            dead = m is None or not m.get("enabled", True)
        if dead:
            idea["status"] = "expired"
            idea["statusAt"] = _now()
            idea["expireReason"] = "anchorGone"
            n += 1
    return n


def _record_idea_task_outcomes_locked(tasks: dict, now: float) -> None:
    """Built outcome (rev2 2.7): an adopted card whose kanban
    task reaches a done state settles as built and earns its
    dimensions a terminal reward. Called from the feed poll,
    which owns the fresh task map."""
    changed = False
    for idea in _db["ideas"]:
        if idea.get("status") != "adopted" or not idea.get("taskId"):
            continue
        found = tasks.get(idea["taskId"])
        if not found:
            continue
        _title, state = found
        if str(state).lower() in _KANBAN_DONE_STATUSES:
            idea["status"] = "built"
            idea["statusAt"] = now
            _record_idea_feedback_locked(idea, "terminal", "built")
            # §459: a built card also feeds the inspiration
            # library -- what actually got built is the
            # strongest angle evidence the library can hold.
            _inspiration_note_built_locked(idea)
            changed = True
    if changed:
        _save_locked()


def _idea_signal_locked(iid: str, body: dict) -> dict:
    """Fast-channel signal intake (rev2 2.5): the App reports
    detail opens and discussions here; rewards live in
    IDEA_FAST_REWARDS. Caller holds _lock (dispatch)."""
    idea = next((i for i in _db["ideas"] if i["id"] == iid), None)
    if idea is None:
        raise _Err(404, "点子不存在")
    typ = body.get("type")
    if typ not in IDEA_FAST_REWARDS:
        raise _Err(400, "type 不对")
    _record_idea_feedback_locked(idea, "fast", typ)
    _save_locked()
    return {"ok": True}


# --- inspiration library (§459, 2026-11-24) --------------------------------
# Self-built equivalent of Muse's idea discovery pool (local
# corpus retrieval + a starter catalog carrying adoption
# counts) -- an EQUIVALENT BUILT HERE, not Muse's corpus:
# the seed below is written for this deployment, and the
# accumulated entries come from this user's own built cards
# and liked feed posts. Entries are ANGLE evidence only: they
# are shown to the generator as directions worth considering,
# they never become evidence anchors -- every card still has
# to ground in the round's S/G/M/K/R/C material and pass the
# anchor gates. The store lives in meta.inspiration; the cap
# sheds oldest accumulated entries first, seed entries shed
# last.

INSPIRATION_KEEP = 200
INSPIRATION_BLOCK_LIMIT = 8

#: the starter catalog: angle patterns in the shape Muse's
#: catalog carries (a doable thing + its classification),
#: written generically -- no user facts in any seed.
INSPIRATION_SEED = [
    {"title": "把最近定稿的文档做成一份当天可用包",
     "domain": "creation_media", "categoryLabel": "交付整理"},
    {"title": "给临近的重要日程做一份准备清单",
     "domain": "personal_productivity", "categoryLabel": "日程准备"},
    {"title": "把一个在办目标的下一步拆成今天能做完的一件小事",
     "domain": "goal_scoped", "categoryLabel": "目标推进"},
    {"title": "把订阅与会员的到期和续费口径做成一页核对表",
     "domain": "finance", "categoryLabel": "订阅选购"},
    {"title": "给服务器与证书做一次到期巡检清单",
     "domain": "connect_devices", "categoryLabel": "服务器运维"},
    {"title": "把本周会议结论整理成纪要并标出待办",
     "domain": "personal_productivity", "categoryLabel": "会议纪要"},
    {"title": "给家人准备一份节日提醒与礼物清单",
     "domain": "family", "categoryLabel": "家庭日常"},
    {"title": "把散落的课程资料整理成一条学习路径",
     "domain": "career", "categoryLabel": "学习整理"},
    {"title": "把健康复查与预约的时机做成提醒清单",
     "domain": "health", "categoryLabel": "健康随访"},
    {"title": "把正在比价的东西做成一页选购核对清单",
     "domain": "shopping", "categoryLabel": "购物指南"},
    {"title": "把下一次出行的行程单与打包清单先备好",
     "domain": "entertainment", "categoryLabel": "出行准备"},
    {"title": "把每周重复出现的手工流程做成一条定时例行",
     "domain": "personal_productivity", "categoryLabel": "例行自动化"},
    {"title": "把名下账号与设备做一次清单盘点",
     "domain": "connect_devices", "categoryLabel": "设备连接"},
    {"title": "给一篇要发布的文案先做口径与合规检查",
     "domain": "creation_media", "categoryLabel": "内容合规"},
    {"title": "把本月家庭账单做一次汇总与异常标注",
     "domain": "finance", "categoryLabel": "家庭账单"},
    {"title": "把收藏的文章提炼成一张要点卡存档",
     "domain": "entertainment", "categoryLabel": "收藏提炼"},
]


def _inspiration_meta_locked() -> dict:
    """The library store; the seed catalog lands on first
    access so a fresh deployment starts with the same starter
    set Muse's catalog gives its generator."""
    lib = _db["meta"].setdefault("inspiration", {})
    entries = lib.setdefault("entries", [])
    if not lib.get("seededAt"):
        have = {" ".join(str(e.get("title") or "").split())
                for e in entries}
        ts = _now()
        ids = {e.get("id") for e in entries}
        for s in INSPIRATION_SEED:
            if " ".join(s["title"].split()) in have:
                continue
            entries.append({
                "id": _new_id("insp_", ids),
                "title": s["title"], "domain": s["domain"],
                "categoryLabel": s["categoryLabel"],
                "origin": "seed", "adoptions": 0,
                "addedAt": ts, "lastAt": ts})
            ids.add(entries[-1]["id"])
        lib["seededAt"] = ts
    return lib


def _inspiration_add_locked(title: str, domain=None,
                            category_label=None, origin="built",
                            bump_adoptions=False) -> None:
    """Add or refresh one entry. Dedup is by normalised
    title; a repeat of a built pattern raises its adoption
    count (the catalog's evidence of what actually lands)."""
    title = " ".join(str(title or "").split())[:80]
    if not title:
        return
    lib = _inspiration_meta_locked()
    entries = lib["entries"]
    for e in entries:
        if " ".join(str(e.get("title") or "").split()) == title:
            e["lastAt"] = _now()
            if bump_adoptions:
                e["adoptions"] = int(e.get("adoptions") or 0) + 1
            return
    entries.append({
        "id": _new_id("insp_", {e.get("id") for e in entries}),
        "title": title,
        "domain": _clean_idea_domain(domain),
        "categoryLabel": _clean_category_label(category_label),
        "origin": origin,
        "adoptions": 1 if bump_adoptions else 0,
        "addedAt": _now(), "lastAt": _now()})
    if len(entries) > INSPIRATION_KEEP:
        # shed oldest accumulated entries first: sort seed
        # entries LAST so the tail cut keeps them
        entries.sort(key=lambda e: (
            1 if e.get("origin") == "seed" else 0,
            e.get("addedAt") or 0))
        lib["entries"] = entries[-INSPIRATION_KEEP:]


def _inspiration_note_built_locked(idea: dict) -> None:
    """Accumulation path one: an adopted card that reached
    built settles its pattern into the library with an
    adoption count."""
    _inspiration_add_locked(
        idea.get("title"), idea.get("domain"),
        idea.get("categoryLabel"), origin="built",
        bump_adoptions=True)


def _inspiration_note_feed_like_locked(post: dict) -> None:
    """Accumulation path two: a feed post the user liked --
    its angle is worth proposing from again. The entry keeps
    the post's title and category; it is angle evidence, the
    post's facts do not travel with it."""
    _inspiration_add_locked(
        post.get("title"), None,
        post.get("category") or post.get("direction"),
        origin="feed")


def _inspiration_block_locked(limit: int =
                              INSPIRATION_BLOCK_LIMIT) -> list:
    """The generator-facing slice: adoption-proven entries
    first, then the freshest -- formatted as angle hints.
    These lines are explicitly NOT material: no ref numbers,
    no anchors."""
    lib = _inspiration_meta_locked()
    entries = sorted(
        lib["entries"],
        key=lambda e: (-(int(e.get("adoptions") or 0)),
                       -(e.get("lastAt") or 0)))
    lines = []
    for e in entries[:limit]:
        label = e.get("categoryLabel") \
            or DOMAIN_LABELS.get(e.get("domain") or "", "")
        lines.append(f"- {e['title']}"
                     + (f"（{label}）" if label else "")
                     + (f"〔已建成 {e['adoptions']} 次〕"
                        if e.get("adoptions") else ""))
    return lines
