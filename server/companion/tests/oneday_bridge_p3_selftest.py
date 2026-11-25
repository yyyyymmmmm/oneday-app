#!/usr/bin/env python3
"""P3 self-test for oneday_bridge.py feed changes.

Phase A: HTTP contract against a subprocess bridge (temp data
preseeded with one idea + one briefing + one monitor change from
"today", plus one legacy digest post and one legacy event post,
no Hermes key): feed purity (2026-11-12) -- the segment-one
assembler still collects the day's events into the ledger but
posts nothing, and archives the two legacy posts in place;
read/delete/generate endpoints behave; a research round
without HERMES_API_KEY records itself as skipped, never as
a post.
Phase B: in-process research round with stubbed search/extract/
HEAD and model outputs dispatched by run id: a link outside the
candidate set drops the whole post, {"skip": true} records an
honest empty round, and a valid output lands as kind=research
through the editor ring (publish-all verdict).
Phase D: spec §127 phase 1 -- editor drop/repair/order, the
code-level E6 backstop on a dual direction, taste folding
(like/signal/delete/stated), the rollup, assignment-only taste
injection, and the editor-infrastructure-failure fallback.
Phase E: spec rev2 phase 2 -- quota tiers, fit-gate plan
bookkeeping, the code source auditor + finish gate (fabricated
drop, stale adjudication), stage-whitelist violations, the
asked-queries book, the shown-images book, the reconcile
watermark (no folding inside a round), the signals book, and
the hourly line.
"""
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "oneday_bridge.py")
KEY = "p3-selftest-key"
PORT = 18747
BASE = f"http://127.0.0.1:{PORT}"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def call(method, path, body=None, key=KEY):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def phase_a():
    tmp = tempfile.mkdtemp(prefix="p3a-")
    now = time.time()
    legacy_digest = {
        "id": "f_legacy_digest", "kind": "digest",
        "title": "今日小结 · 3 件", "body": "## 新点子\n- x",
        "refs": [], "links": [], "why": None, "emoji": "💡",
        "createdAt": now - 3600,
        "expiresAt": now + 29 * 86400, "readAt": None}
    legacy_event = {
        "id": "f_legacy_event", "kind": "event",
        "title": "有 1 项待审批（记忆/技能写入），等待处理",
        "body": "新的写入在等你决定。",
        "refs": [], "links": [],
        "why": "这是你自己的事——来自你站内的任务、监测与审批。",
        "emoji": "✍️", "createdAt": now - 1800,
        "expiresAt": now + 29 * 86400, "readAt": None}
    seed = {
        "goals": [{"id": "g_t1", "title": "自测目标", "note": "",
                   "milestones": [], "createdAt": now - 86400,
                   "updatedAt": now - 86400, "status": "active",
                   "completedAt": None, "parentId": None,
                   "source": "manual"}],
        "ideas": [{"id": "i_t1", "title": "自测点子", "detail": "d",
                   "goalId": None, "createdAt": now, "source": "manual",
                   "evidence": None, "evidenceRef": None,
                   "status": "pending", "taskId": None,
                   "expiresAt": None}],
        "monitors": [{"id": "m_t1", "name": "自测监测",
                      "target": "https://example.com",
                      "enabled": False, "nextRunAt": None,
                      "createdAt": now - 86400, "updatedAt": now}],
        "changes": [{"id": "c_t1", "monitorId": "m_t1",
                     "detectedAt": now, "summary": "页面变了",
                     "before": "a", "after": "b", "read": False}],
        "goalEntries": [],
        "briefings": [{"id": "b_t1", "goalId": "g_t1",
                       "period": "2026-W46", "title": "自测简报",
                       "body": "x", "createdAt": now}],
        "feedPosts": [legacy_digest, legacy_event],
        "meta": {},
    }
    with open(os.path.join(tmp, "data.json"), "w",
              encoding="utf-8") as f:
        json.dump(seed, f, ensure_ascii=False)
    env = dict(os.environ, ONEDAY_BRIDGE_KEY=KEY,
               DATA_PATH=os.path.join(tmp, "data.json"),
               ONEDAY_PORT=str(PORT))
    env.pop("HERMES_API_KEY", None)
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                s, _ = call("GET", "/health", key=None)
                if s == 200:
                    break
            except Exception:
                pass
            time.sleep(0.2)
        s, body = call("GET", "/feed", key="wrong")
        check("A feed requires auth", s == 401, f"{s}")
        # wait for an assembly tick: the ledger must still count
        # the day's 3 local events, and the purity sweep must
        # have archived both legacy posts
        gen = {}
        settled = False
        for _ in range(40):
            s, gen = call("GET", "/feed/generation")
            if s == 200 \
                    and gen["assembly"]["eventsToday"] == 3 \
                    and gen["assembly"]["purityArchived"] == {
                        "digest": 1, "event": 1}:
                settled = True
                break
            time.sleep(2)
        check("A ledger collects events, sweep archives legacy",
              settled, f"{gen.get('assembly') if s == 200 else s}")
        s, body = call("GET", "/feed")
        # §459 reversal (2026-11-24): the day's substantive
        # local events DO become standalone posts now; the
        # legacy digest/event posts stay out (archived).
        items = body.get("items") or []
        check("A flow lists the day's event posts (§459)",
              s == 200 and len(items) == 3
              and all(i.get("kind") == "event" for i in items)
              and {i["refs"][0]["type"] for i in items}
              == {"idea", "briefing", "monitor"},
              f"{s} {items}")
        s, got = call("GET", "/feed/f_legacy_digest")
        check("A archived digest kept, readable by id",
              s == 200 and got.get("archivedAt") is not None,
              f"{s}")
        s, got = call("GET", "/feed/f_legacy_event")
        check("A archived event kept, readable by id",
              s == 200 and got.get("archivedAt") is not None,
              f"{s}")
        s, read = call("POST", "/feed/f_legacy_event/read")
        check("A read on archived record still settles",
              s == 200 and read["readAt"] is not None, f"{s}")
        s, gen = call("GET", "/feed/generation")
        check("A unread counts event posts, excludes archived",
              s == 200 and gen["unread"] == 3, f"{s} {gen}")
        check("A generation view has no morning key (cx item 1)",
              "morning" not in gen, f"{sorted(gen)}")
        s, _ = call("POST", "/feed/generate")
        check("A manual research trigger accepted", s == 202,
              f"{s}")
        skipped = False
        for _ in range(30):
            s, gen = call("GET", "/feed/generation")
            hist = gen["research"]["history"]
            if hist and hist[-1]["status"] == "skipped":
                skipped = True
                break
            time.sleep(1)
        check("A research without key records skipped", skipped)
        s, body = call("GET", "/feed")
        check("A skipped round made no research post",
              s == 200 and len(body.get("items") or []) == 3
              and all(i.get("kind") == "event"
                      for i in body.get("items") or []))
        s, _ = call("DELETE", "/feed/f_legacy_digest")
        check("A delete of archived record ok", s == 200, f"{s}")
        s, _ = call("GET", "/feed/f_legacy_digest")
        check("A deleted post 404s", s == 404, f"{s}")
        s, _ = call("GET", "/feed/nope")
        check("A unknown post 404s", s == 404, f"{s}")
    finally:
        proc.terminate()
        proc.wait(timeout=10)


def phase_b():
    """Research round in-process: stubbed search/extract/HEAD
    and queued model outputs -- a foreign link drops the whole
    post, a compose skip records an honest empty direction, and
    a valid compose lands as kind=research with HEAD-verified
    images (dead ones dropped, live ones keep their source)."""
    tmp = tempfile.mkdtemp(prefix="p3b-")
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    os.environ["HERMES_API_KEY"] = "fake-key"
    spec = importlib.util.spec_from_file_location("ob_b", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    with mod._lock:
        mod._db["meta"]["brief"] = "关心自托管工具与开源项目"
        mod._save_locked()
    mod._tavily_search = lambda q: ([
        {"title": "甲文", "url": "https://example.com/a",
         "snippet": "s"},
        {"title": "乙文", "url": "https://example.com/b",
         "snippet": "s"}], None)
    mod._tavily_extract = lambda urls: {
        "https://example.com/a": {
            "content": "正" * 450,
            "images": ["https://img.example.com/a.png",
                       "https://img.example.com/dead.png"]},
        "https://example.com/b": {
            "content": "正" * 450, "images": []}}
    mod._http_head_ok = lambda u: "dead" not in u
    mod._github_card = lambda u: None
    outputs = []
    prompts = {}

    def fake_submit(prompt, idem):
        prompts[idem] = prompt
        return idem, None

    def fake_poll(run_id):
        if run_id.startswith("feed-material-"):
            # 1.0.28: the agent-fetch seat answers with the
            # same two fixture pages the old Tavily stubs
            # served, contents and images included
            return json.dumps({"candidates": [
                {"title": "甲文", "url": "https://example.com/a",
                 "publishedAt": None, "content": "正" * 450,
                 "images": ["https://img.example.com/a.png",
                            "https://img.example.com/dead.png"]},
                {"title": "乙文", "url": "https://example.com/b",
                 "publishedAt": None, "content": "正" * 450,
                 "images": []}]}, ensure_ascii=False), None
        if run_id.startswith("feed-social-"):
            # §459 social road: walked, found nothing
            return json.dumps({"candidates": []}), None
        if run_id.startswith("feed-research-plan-"):
            return plan, None
        if run_id.startswith("feed-editor-"):
            ids = re.findall(r'"id": "(f_[^"]+)"',
                             prompts[run_id])
            return json.dumps({"publish": ids, "repairs": [],
                               "drops": []}), None
        if run_id.startswith("taste-rollup-"):
            return "口味摘要占位。", None
        return outputs.pop(0), None

    mod._github_material = lambda *a, **k: ([], {}, None)
    # feedfix seams: the A1 audit reads back a verified
    # tool-call count, the A2 screen sees live URLs -- the
    # fake material below is meant to flow through both.
    mod._run_tool_call_count = lambda run_id: 3
    mod._material_url_status = lambda url: 200
    mod._hermes_submit_run = fake_submit
    mod._hermes_poll_run = fake_poll

    plan = json.dumps({"directions": [
        {"name": "自托管", "queries": ["self hosted tools"]}]},
        ensure_ascii=False)

    def history():
        with mod._lock:
            return list(mod._db["meta"]["feedGen"]["history"])

    def posts():
        with mod._lock:
            return list(mod._db["feedPosts"])

    outputs.append(json.dumps({
        "title": "集外链接帖", "body": "正文", "why": "理由",
        "links": [{"title": "外站",
                   "url": "https://evil.example.com/x"}],
        "images": [], "refs": []}, ensure_ascii=False))
    mod._run_research_round("manual")
    check("B foreign link drops whole post",
          len(posts()) == 0 and history()[-1]["status"] == "empty"
          and history()[-1]["dropped"] == 1
          and "候选集之外" in (history()[-1]["error"] or ""),
          f"{history()[-1] if history() else None}")

    outputs.append(json.dumps({"skip": True, "reason": "没新东西"},
                              ensure_ascii=False))
    mod._run_research_round("manual")
    check("B compose skip records honest empty round",
          len(posts()) == 0 and history()[-1]["status"] == "empty"
          and history()[-1]["directions"][0]["note"] == "没新东西",
          f"{history()[-1]}")

    outputs.append(json.dumps({
        "title": "真调研", "body": "正文内容", "why": "因为值得",
        "links": [{"title": "甲文",
                   "url": "https://example.com/a"}],
        "images": ["https://img.example.com/a.png",
                   "https://img.example.com/dead.png"],
        "refs": []}, ensure_ascii=False))
    mod._run_research_round("manual")
    ps = posts()
    check("B valid output lands as research",
          len(ps) == 1 and ps[0]["kind"] == "research"
          and history()[-1]["status"] == "ok", f"{ps}")
    if ps:
        check("B links settled from candidate set",
              ps[0]["links"] == [{"title": "甲文",
                                  "url": "https://example.com/a"}],
              f"{ps[0]['links']}")
        check("B dead image dropped, live image keeps source",
              ps[0]["images"] == [{
                  "url": "https://img.example.com/a.png",
                  "sourceUrl": "https://example.com/a"}],
              f"{ps[0]['images']}")
        check("B post direction/why/expiry settled",
              ps[0]["direction"] == "自托管"
              and ps[0]["why"] == "因为值得"
              and ps[0]["expiresAt"] > ps[0]["createdAt"]
              and ps[0]["readAt"] is None)
        check("B post carries likedAt=None (§127)",
              ps[0].get("likedAt") is None
              and "likedAt" in ps[0])
        rec = history()[-1]
        check("B round record carries candidate/editor ledger",
              len(rec["candidates"]) == 1
              and rec["publish"] == [ps[0]["id"]]
              and rec["editorDrops"] == []
              and rec["modelCalls"] == 3,
              f"{rec}")


def phase_c():
    """Remote-poll diffs: kanban baseline stays silent, a status
    change + a new task become events; approvals only speak up
    on increases."""
    tmp = tempfile.mkdtemp(prefix="p3c-")
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    os.environ["HERMES_API_KEY"] = "fake-key"
    os.environ["OVERVIEW_BRIDGE_KEY"] = "fake-overview-key"
    spec = importlib.util.spec_from_file_location("ob_c", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    boards = [({"t1": ("任务一", "todo")}, None),
              ({"t1": ("任务一", "done"),
                "t2": ("任务二", "todo")}, None)]
    mod._fetch_kanban_tasks = lambda: boards.pop(0)
    counts = [1, 2, 1]
    mod._http_json = lambda url, **kw: (
        200, {"pendingApprovals": counts.pop(0)}, "")
    mod._feed_poll_remote()
    with mod._lock:
        feed = mod._feed_meta_locked()
        ev1 = list(feed["events"])
    check("C baseline poll silent",
          ev1 == [] and feed["approvalTotal"] == 1
          and feed["taskSnapshot"] == {"t1": "todo"}, f"{ev1}")
    mod._feed_poll_remote()
    with mod._lock:
        feed = mod._feed_meta_locked()
        kinds = sorted(e["kind"] for e in feed["events"])
        texts = " ".join(e["text"] for e in feed["events"])
    check("C changes become events",
          kinds == ["approval", "task", "task"], f"{kinds}")
    check("C event texts carry facts",
          "状态变为 done" in texts and "新任务" in texts
          and "2 项待审批" in texts, texts)
    boards.append(({"t1": ("任务一", "done"),
                    "t2": ("任务二", "todo")}, None))
    mod._feed_poll_remote()
    with mod._lock:
        n = len(mod._feed_meta_locked()["events"])
    check("C approval decrease stays silent", n == 3, f"{n}")


def phase_d():
    """Spec §127 phase 1: editor ring + taste notes, in-process
    with the same retrieval stubs as phase B and model outputs
    dispatched by run id (plan/editor verdicts are functions of
    a mode variable; compose outputs are queued)."""
    tmp = tempfile.mkdtemp(prefix="p3d-")
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    os.environ["HERMES_API_KEY"] = "fake-key"
    spec = importlib.util.spec_from_file_location("ob_d", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    with mod._lock:
        mod._db["meta"]["brief"] = "关心自托管工具与开源项目"
        mod._save_locked()
    # published posts' link URLs enter the 30-day avoid set,
    # so each round needs a fresh batch of source URLs
    state = {"plan": None, "editor_mode": "all",
             "compose": [], "prompts": {}, "batch": 0}

    def fake_search(q):
        b = state["batch"]
        return ([{"title": f"甲文{b}",
                  "url": f"https://example.com/{b}a",
                  "snippet": "s"},
                 {"title": f"乙文{b}",
                  "url": f"https://example.com/{b}b",
                  "snippet": "s"}], None)

    def fake_extract(urls):
        return {u: {"content": "正" * 450, "images": []}
                for u in urls}

    mod._tavily_search = fake_search
    mod._tavily_extract = fake_extract
    mod._http_head_ok = lambda u: True
    mod._github_card = lambda u: None
    NEW_WHY = "新理由：与你正在推进的自托管迁移直接相关，值得先看。"

    def editor_reply(prompt):
        blocks = re.findall(
            r'"id": "(f_[^"]+)", "direction": "([^"]+)"', prompt)
        mode = state["editor_mode"]
        if mode == "all":
            return json.dumps({
                "publish": [b[0] for b in blocks],
                "repairs": [], "drops": []}), None
        if mode == "reverse":
            return json.dumps({
                "publish": [b[0] for b in reversed(blocks)],
                "repairs": [], "drops": []}), None
        if mode == "d1":
            keep = next(b for b in blocks if b[1] == "自托管")
            drop = next(b for b in blocks if b[1] == "开源")
            return json.dumps({
                "publish": [keep[0]],
                "repairs": [{"id": keep[0], "kind": "why",
                             "detail": NEW_WHY}],
                "drops": [{"id": drop[0], "defect": "E1"}]},
                ensure_ascii=False), None
        raise AssertionError(mode)

    def fake_submit(prompt, idem):
        state["prompts"][idem] = prompt
        return idem, None

    def fake_poll(run_id):
        if run_id.startswith("feed-material-"):
            # 1.0.28 agent-fetch seat: the current batch's
            # two fixture pages, full text included
            b = state["batch"]
            return json.dumps({"candidates": [
                {"title": f"甲文{b}",
                 "url": f"https://example.com/{b}a",
                 "publishedAt": None, "content": "正" * 450,
                 "images": []},
                {"title": f"乙文{b}",
                 "url": f"https://example.com/{b}b",
                 "publishedAt": None, "content": "正" * 450,
                 "images": []}]}, ensure_ascii=False), None
        if run_id.startswith("feed-social-"):
            # §459 social road: walked, found nothing
            return json.dumps({"candidates": []}), None
        if run_id.startswith("feed-research-plan-"):
            return state["plan"], None
        if run_id.startswith("feed-editor-"):
            if state["editor_mode"] == "fail":
                return None, "编辑服务不可用"
            return editor_reply(state["prompts"][run_id])
        if run_id.startswith("taste-rollup-"):
            return "多看自托管与开源项目，少看部署教程。", None
        return state["compose"].pop(0), None

    mod._github_material = lambda *a, **k: ([], {}, None)
    # feedfix seams: the A1 audit reads back a verified
    # tool-call count, the A2 screen sees live URLs -- the
    # fake material below is meant to flow through both.
    mod._run_tool_call_count = lambda run_id: 3
    mod._material_url_status = lambda url: 200
    mod._hermes_submit_run = fake_submit
    mod._hermes_poll_run = fake_poll

    def plan_of(*dirs):
        return json.dumps({"directions": list(dirs)},
                          ensure_ascii=False)

    def compose_of(title, page="a"):
        b = state["batch"]
        page_title = "甲文" if page == "a" else "乙文"
        return json.dumps({
            "title": title, "body": "正文内容，足够长度。",
            "why": "原始理由",
            "links": [{"title": f"{page_title}{b}",
                       "url": f"https://example.com/{b}{page}"}],
            "images": [], "refs": []}, ensure_ascii=False)

    def history():
        with mod._lock:
            return list(mod._db["meta"]["feedGen"]["history"])

    def posts():
        with mod._lock:
            return list(mod._db["feedPosts"])

    def taste():
        with mod._lock:
            n = mod._taste_notes_locked()
            return {k: (list(v) if isinstance(v, list) else v)
                    for k, v in n.items()}

    # D1: editor drops with E1 and repairs why; only the kept
    # candidate lands, with the editor's why
    state["batch"] += 1
    state["plan"] = plan_of(
        {"name": "自托管", "angle": "角度一",
         "queries": ["q1"]},
        {"name": "开源", "angle": "角度二",
         "queries": ["q2"]})
    state["compose"] = [compose_of("自托管帖"), compose_of("开源帖")]
    state["editor_mode"] = "d1"
    mod._run_research_round("manual")
    ps, rec = posts(), history()[-1]
    check("D1 editor drop+why repair lands one post",
          len(ps) == 1 and ps[0]["direction"] == "自托管"
          and ps[0]["why"] == NEW_WHY, f"{ps} {rec}")
    check("D1 round ledger carries drops/repairs",
          len(rec["editorDrops"]) == 1
          and rec["editorDrops"][0]["defect"] == "E1"
          and any(r["kind"] == "why" for r in rec["repairs"])
          and rec["produced"] == 1 and len(rec["candidates"]) == 2,
          f"{rec}")

    # D2: editor order is the flow order (createdAt desc)
    state["batch"] += 1
    state["plan"] = plan_of(
        {"name": "自托管", "angle": "角度三",
         "queries": ["q1"]},
        {"name": "开源", "angle": "角度四",
         "queries": ["q2"]})
    state["compose"] = [compose_of("自托管帖二"),
                         compose_of("开源帖二")]
    state["editor_mode"] = "reverse"
    before = {p["id"] for p in posts()}
    mod._run_research_round("manual")
    new = [p for p in posts() if p["id"] not in before]
    by_created = sorted(new, key=lambda p: -p["createdAt"])
    rec = history()[-1]
    check("D2 editor order preserved in flow",
          [p["direction"] for p in by_created] == ["开源", "自托管"]
          and rec["publish"] == [p["id"] for p in by_created],
          f"{by_created} {rec.get('publish')}")

    # D3: dual direction, editor publishes both -> code E6
    # backstop keeps exactly one
    state["batch"] += 1
    state["plan"] = plan_of(
        {"name": "自托管", "angle": "角度五", "dual": True,
         "angle2": "角度六", "queries": ["q1"]})
    state["compose"] = [compose_of("双候选甲"),
                         compose_of("双候选乙", "b")]
    state["editor_mode"] = "all"
    before = {p["id"] for p in posts()}
    mod._run_research_round("manual")
    new = [p for p in posts() if p["id"] not in before]
    rec = history()[-1]
    check("D3 E6 backstop keeps one post per direction",
          len(new) == 1
          and any(d["defect"] == "E6"
                  for d in rec["editorDrops"]),
          f"{new} {rec.get('editorDrops')}")

    # D4: taste folding -- like (idempotent), discuss signal,
    # bad signal type, delete, stated
    target = new[0]
    view = mod._like_feed_post(target["id"], True)
    t = taste()
    check("D4 like settles likedAt and folds once",
          view["likedAt"] is not None and len(t["likes"]) == 1
          and t["dirty"] is True, f"{view} {t}")
    mod._like_feed_post(target["id"], True)
    check("D4 re-like folds nothing twice",
          len(taste()["likes"]) == 1)
    mod._signal_feed_post(target["id"], "discuss", "少看部署教程")
    t = taste()
    check("D4 discuss signal folds the stated sentence",
          t["discussHints"][-1]["text"] == "少看部署教程",
          f"{t['discussHints']}")
    try:
        mod._signal_feed_post(target["id"], "bogus", None)
        bad_ok = False
    except mod._Err as e:
        bad_ok = e.status == 400
    check("D4 unknown signal type 400s", bad_ok)
    mod._delete_feed_post(target["id"])
    t = taste()
    check("D4 delete folds a dislike",
          len(t["dislikes"]) == 1
          and t["dislikes"][0]["via"] == "delete", f"{t}")
    with mod._lock:
        mod._taste_add_stated_locked("多看开源项目动态", "brief")
        mod._save_locked()
    t = taste()
    check("D4 stated recorded verbatim",
          t["stated"][-1]["text"] == "多看开源项目动态"
          and t["stated"][-1]["source"] == "brief", f"{t}")

    # D3b (feedfix B2): dual direction whose two drafts cite
    # the exact same link set -> the direction seat keeps one
    # candidate in code and notes it, before the editor
    # convenes; exactly one post lands
    state["batch"] += 1
    state["plan"] = plan_of(
        {"name": "自托管", "angle": "角度五", "dual": True,
         "angle2": "角度六", "queries": ["q1"]})
    state["compose"] = [compose_of("双稿甲"),
                         compose_of("双稿乙")]
    state["editor_mode"] = "all"
    before2 = {p["id"] for p in posts()}
    mod._run_research_round("manual")
    new2 = [p for p in posts() if p["id"] not in before2]
    rec2 = history()[-1]
    drec2 = next(d for d in rec2["directions"]
                 if d["name"] == "自托管")
    check("D3b B2 twin-link dual keeps one, noted in record",
          len(new2) == 1
          and "双稿同料" in (drec2.get("note") or ""),
          f"{new2} {drec2.get('note')}")

    # D5: rollup folds signals into the summary once
    rolled, note = mod._taste_rollup()
    t = taste()
    check("D5 rollup lands summary and bumps version",
          rolled and note is None
          and t["summary"] == "多看自托管与开源项目，少看部署教程。"
          and t["version"] == 1 and t["dirty"] is False,
          f"{rolled} {note} {t}")
    rolled2, _ = mod._taste_rollup()
    check("D5 second rollup is a no-op", rolled2 is False)

    # D6: taste reaches the assignment prompt only -- stated in
    # full + summary; the compose prompt never sees the summary
    state["batch"] += 1
    state["plan"] = plan_of(
        {"name": "自托管", "angle": "角度七",
         "queries": ["q1"]})
    state["compose"] = [compose_of("注入验证帖")]
    state["editor_mode"] = "all"
    mod._run_research_round("manual")
    plan_prompts = [v for k, v in state["prompts"].items()
                    if k.startswith("feed-research-plan-")]
    compose_prompts = [v for k, v in state["prompts"].items()
                       if k.startswith("feed-research-")
                       and not k.startswith("feed-research-plan-")]
    check("D6 assignment prompt carries summary + stated",
          any("多看自托管与开源项目，少看部署教程。" in p
              and "多看开源项目动态" in p
              for p in plan_prompts),
          f"{len(plan_prompts)} plan prompts")
    check("D6 compose prompt never sees taste",
          compose_prompts and all(
              "多看自托管与开源项目，少看部署教程。" not in p
              for p in compose_prompts))

    # D7: editor infrastructure failure -> code-gate fallback
    # release, announced in the round record
    state["batch"] += 1
    state["plan"] = plan_of(
        {"name": "开源", "angle": "角度八",
         "queries": ["q2"]})
    state["compose"] = [compose_of("编辑故障帖")]
    state["editor_mode"] = "fail"
    before = {p["id"] for p in posts()}
    mod._run_research_round("manual")
    new = [p for p in posts() if p["id"] not in before]
    rec = history()[-1]
    check("D7 editor failure falls back with a ledger note",
          len(new) == 1 and "编辑环失败" in
          (rec.get("editorNote") or ""), f"{new} {rec}")



def _load_e(name, brief="关心自托管工具与开源项目动态"):
    tmp = tempfile.mkdtemp(prefix=name)
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    os.environ["HERMES_API_KEY"] = "fake-key"
    spec = importlib.util.spec_from_file_location(
        "ob_e_" + name, BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    with mod._lock:
        mod._db["meta"]["brief"] = brief
        mod._save_locked()
    state = {"plan": None, "editor_mode": "all", "compose": [],
             "prompts": {}, "search_calls": [], "batch": 0,
             "published": None, "picker": None,
             "finish_mode": "noop"}

    def fake_search(q):
        state["search_calls"].append(q)
        b = state["batch"]
        return ([{"title": f"甲文{b}",
                  "url": f"https://example.com/{b}a",
                  "snippet": "s",
                  "publishedAt": state["published"]},
                 {"title": f"乙文{b}",
                  "url": f"https://example.com/{b}b",
                  "snippet": "s",
                  "publishedAt": state["published"]}], None)

    def fake_extract(urls):
        return {u: {"content": "正" * 450,
                    "images": list(state.get("images") or [])}
                for u in urls}

    mod._tavily_search = fake_search
    mod._tavily_extract = fake_extract
    mod._http_head_ok = lambda u: True
    mod._github_card = lambda u: None

    def editor_reply(prompt):
        ids = re.findall(r'"id": "(f_[^"]+)"', prompt)
        if state["editor_mode"] == "bad-repair":
            return json.dumps({
                "publish": ids,
                "repairs": [{"id": ids[0], "kind": "title",
                             "detail": "越段改标题"}],
                "drops": []}), None
        return json.dumps({"publish": ids, "repairs": [],
                           "drops": []}), None

    def finish_reply(prompt):
        ids = re.findall(r'"id": "(f_[^"]+)"', prompt)
        if state["finish_mode"] == "fix-why":
            return json.dumps({
                "publish": ids,
                "repairs": [{
                    "id": ids[0], "kind": "why",
                    "detail": "该源发布于2020年1月5日，"
                              "虽已过时效，但其结论至今"
                              "仍被引用，值得对照今昔。"}],
                "drops": []}, ensure_ascii=False), None
        return json.dumps({"publish": ids, "repairs": [],
                           "drops": []}), None

    def fake_submit(prompt, idem):
        state["prompts"][idem] = prompt
        return idem, None

    def fake_poll(run_id):
        if run_id.startswith("feed-material-"):
            # 1.0.28: agent-fetch returns NOTHING here, so
            # every E/F/hourly phase exercises the API
            # fallback chain exactly as before
            return json.dumps({"candidates": []}), None
        if run_id.startswith("feed-social-"):
            # §459 social road: walked, found nothing
            return json.dumps({"candidates": []}), None
        if run_id.startswith("feed-research-plan-"):
            return state["plan"], None
        if run_id.startswith("feed-editor-"):
            return editor_reply(state["prompts"][run_id])
        if run_id.startswith("feed-finish-"):
            return finish_reply(state["prompts"][run_id])
        if run_id.startswith("feed-picker-"):
            return state["picker"], None
        if run_id.startswith("taste-rollup-"):
            return "亲口：多看自托管。推测：有迹象偏好开源工具。", None
        return state["compose"].pop(0), None

    mod._github_material = lambda *a, **k: ([], {}, None)
    # feedfix seams: the A1 audit reads back a verified
    # tool-call count, the A2 screen sees live URLs -- the
    # fake material below is meant to flow through both.
    mod._run_tool_call_count = lambda run_id: 3
    mod._material_url_status = lambda url: 200
    mod._hermes_submit_run = fake_submit
    mod._hermes_poll_run = fake_poll
    return mod, state


def _plan_of(*dirs):
    return json.dumps({"directions": list(dirs)},
                      ensure_ascii=False)


def _compose_of(title, b, **kw):
    body = {"title": title, "body": kw.get("body", "正文内容，足够长度。"),
            "why": kw.get("why", "原始理由"),
            "links": [{"title": f"甲文{b}",
                       "url": f"https://example.com/{b}a"}],
            "images": kw.get("images", []), "refs": []}
    if "band" in kw:
        body["timeSensitivity"] = kw["band"]
    return json.dumps(body, ensure_ascii=False)


def _hist(mod):
    with mod._lock:
        return list(mod._db["meta"]["feedGen"]["history"])


def _posts(mod):
    with mod._lock:
        return list(mod._db["feedPosts"])


def phase_e():
    # E-quota: the fallback tier ladder against the real
    # plan limit (1.0.28: tiers size the Tavily safety net
    # under agent-first sourcing; they gate no line)
    mod, st = _load_e("p3e-quota-")
    check("E fallback tier ladder (agent-first sourcing)",
          mod._feed_quota_tier(1000) == 1
          and mod._feed_quota_tier(1500) == 1
          and mod._feed_quota_tier(1700) == 0)
    with mod._lock:
        pol = mod._feed_policy_locked()
    check("E policy records tier + reason",
          pol["tier"] == 1 and "1000" in pol["reason"]
          and pol.get("sourcing") == "agent-first", f"{pol}")
    # adhoc is no longer tier-gated: with the activity gate
    # stubbed open and the starter recorded, the door opens
    # at the 1000/mo tier; quiet hours still bind, so the
    # expectation follows the clock
    fired = []
    mod._activity_gate_locked = lambda: (True, "test gate")
    _orig_start = mod._start_research
    mod._start_research = \
        lambda t: fired.append(t) or True
    try:
        adhoc_got = mod._feed_maybe_adhoc()
    finally:
        mod._start_research = _orig_start
    _hour = time.localtime(mod._now()).tm_hour
    _expect = not (_hour >= 23 or _hour < 7)
    check("E adhoc opens at tier 1 when gates pass "
          "(tiers no longer gate lines)",
          adhoc_got is _expect
          and (not _expect or fired == ["visit"]),
          f"hour={_hour} got={adhoc_got} fired={fired}")

    # E-fit: plan bookkeeping + prompt layers in the round
    mod, st = _load_e("p3e-fit-")
    st["batch"] = 1
    st["plan"] = _plan_of(
        {"name": "自托管", "angle": "角度一",
         "decidedBy": "brief_fit",
         "fitReason": "简报原话「自托管工具」",
         "queries": ["fitq"]})
    st["compose"] = [_compose_of("合题帖", 1)]
    mod._run_research_round("manual")
    rec = _hist(mod)[-1]
    check("E fit gate bookkeeping lands in the record",
          rec["plan"] and rec["plan"][0]["decidedBy"] == "brief_fit"
          and "自托管工具" in rec["plan"][0]["fitReason"],
          f"{rec.get('plan')}")
    check("E prompt versions ride the record",
          rec["promptVersions"]["constitution"]
          == "feed_constitution_v1", f"{rec['promptVersions']}")
    plan_prompt = next(v for k, v in st["prompts"].items()
                       if k.startswith("feed-research-plan-"))
    check("E assignment prompt carries constitution + fit gate",
          "优先级阶梯" in plan_prompt and "fit 门" in plan_prompt)

    # E-audit: a fabricated body url is audited in code, the
    # editor publishes anyway, the finish gate drops it after
    # two unproductive repair rounds
    mod, st = _load_e("p3e-audit-")
    st["batch"] = 2
    st["plan"] = _plan_of(
        {"name": "自托管", "angle": "角度二", "queries": ["aq"]})
    st["compose"] = [_compose_of(
        "铸造帖", 2,
        body="新版本发布，详见 https://fake.example.com/x 的说明页。")]
    mod._run_research_round("schedule")
    rec = _hist(mod)[-1]
    check("E fabricated url is caught by the code auditor",
          any(f["type"] == "fabricated"
              for f in list(rec["sourceAudit"].values())[0]),
          f"{rec['sourceAudit']}")
    check("E finish gate drops what the editor would not fix",
          len(_posts(mod)) == 0 and rec["finishRounds"] == 2
          and rec["finishFailed"]
          and rec["finishFailed"][0]["rules"] == ["fabricated"],
          f"{rec['finishFailed']} rounds={rec['finishRounds']}")

    # E-stale: an over-band source is kept only with its date
    # named in the why -- via one finish repair round
    mod, st = _load_e("p3e-stale-")
    st["batch"] = 3
    st["published"] = "2020-01-05"
    st["finish_mode"] = "fix-why"
    st["plan"] = _plan_of(
        {"name": "自托管", "angle": "角度三", "queries": ["sq"]})
    st["compose"] = [_compose_of("老源帖", 3, band="recent_3d")]
    mod._run_research_round("schedule")
    rec = _hist(mod)[-1]
    ps = _posts(mod)
    check("E stale source audited against the declared band",
          any(f["type"] == "stale"
              for f in list(rec["sourceAudit"].values())[0]),
          f"{rec['sourceAudit']}")
    check("E stale kept only with the date named in why",
          len(ps) == 1 and "2020年1月5日" in ps[0]["why"]
          and rec["finishRounds"] == 1
          and ps[0]["sources"] == ["https://example.com/3a"],
          f"{ps} rounds={rec['finishRounds']}")

    # E-stage: an out-of-whitelist repair kind is refused and
    # recorded; the post lands untouched by it
    mod, st = _load_e("p3e-stage-")
    st["batch"] = 4
    st["editor_mode"] = "bad-repair"
    st["plan"] = _plan_of(
        {"name": "自托管", "angle": "角度四", "queries": ["tq"]})
    st["compose"] = [_compose_of("原标题帖", 4)]
    mod._run_research_round("manual")
    rec = _hist(mod)[-1]
    ps = _posts(mod)
    check("E out-of-stage repair refused + recorded",
          any(v["rule"] == "stage-whitelist"
              for v in rec["stageViolations"])
          and len(ps) == 1 and ps[0]["title"] == "原标题帖",
          f"{rec['stageViolations']} {ps}")

    # E-querybook: an autonomous round may not re-ask what
    # was already asked today/yesterday
    mod, st = _load_e("p3e-book-")
    st["batch"] = 5
    st["plan"] = _plan_of(
        {"name": "自托管", "angle": "角度五", "queries": ["qqx"]})
    st["compose"] = [_compose_of("第一问帖", 5)]
    mod._run_research_round("schedule")
    check("E first ask lands", len(_posts(mod)) == 1)
    st["batch"] = 6
    st["compose"] = [_compose_of("不该出现帖", 6)]
    mod._run_research_round("schedule")
    rec = _hist(mod)[-1]
    check("E repeat ask blocked by the book, with a trace",
          st["search_calls"].count("qqx") == 1
          and any(e["action"] == "blocked-repeat"
                  for e in rec["queryBook"])
          and len(_posts(mod)) == 1,
          f"{st['search_calls']} {rec['queryBook']}")

    # E-imagebook: the same image under different params is
    # the same image for 72h
    mod, st = _load_e("p3e-img-")
    st["batch"] = 7
    st["images"] = ["https://img.example.com/pic.png?w=100"]
    st["plan"] = _plan_of(
        {"name": "自托管", "angle": "角度六", "queries": ["iq"]})
    st["compose"] = [_compose_of(
        "首图帖", 7,
        images=["https://img.example.com/pic.png?w=100"])]
    mod._run_research_round("manual")
    first = _posts(mod)
    st["batch"] = 8
    st["images"] = ["https://img.example.com/pic.png?w=200"]
    st["compose"] = [_compose_of(
        "重图帖", 8,
        images=["https://img.example.com/pic.png?w=200"])]
    mod._run_research_round("manual")
    ps = _posts(mod)
    check("E same image (params differ) shown once per 72h",
          len(first) == 1 and len(first[0]["images"]) == 1
          and len(ps) == 2 and ps[-1]["images"] == [],
          f"{first} {ps}")

    # E-reconcile: the watermark advances on reconcile; a
    # generation round never folds; the signals book grounds
    # the next post in the liked direction
    mod, st = _load_e("p3e-rec-")
    with mod._lock:
        mod._db["feedPosts"].append({
            "id": "f_seed1", "kind": "research",
            "title": "种子帖", "body": "x", "refs": [],
            "links": [], "why": "w", "images": [],
            "emoji": None, "sourceCard": None,
            "direction": "自托管", "angle": "种子角度",
            "edition": None, "likedAt": None,
            "createdAt": time.time() - 3600,
            "expiresAt": time.time() + 86400, "readAt": None})
        mod._save_locked()
    view = mod._like_feed_post("f_seed1", True)
    check("E like registers a signal in the book",
          view["likedAt"] is not None)
    with mod._lock:
        books = mod._feed_books_locked()
        sig = books["signals"].get("sig-f_seed1") or {}
        notes = mod._taste_notes_locked()
        like_at = notes["likes"][-1]["at"]
    check("E signal book entry starts unused",
          sig.get("usedBy") == 0 and sig.get("kind") == "like",
          f"{sig}")
    rolled, note = mod._taste_rollup()
    with mod._lock:
        notes = mod._taste_notes_locked()
    check("E reconcile advances the watermark to the signal",
          rolled and notes["foldedThrough"] == like_at
          and notes["updatedBy"] == "reconcile"
          and notes["version"] == 1,
          f"{rolled} {notes.get('foldedThrough')} vs {like_at}")
    st["batch"] = 9
    st["plan"] = _plan_of(
        {"name": "自托管", "angle": "角度七", "queries": ["rq"]})
    st["compose"] = [_compose_of("站信号帖", 9)]
    before = {k for k in st["prompts"]}
    mod._run_research_round("manual")
    rec = _hist(mod)[-1]
    new_keys = {k for k in st["prompts"]} - before
    with mod._lock:
        books = mod._feed_books_locked()
        sig = books["signals"].get("sig-f_seed1") or {}
    landed = [p for p in _posts(mod) if p["id"] != "f_seed1"]
    check("E rounds never fold taste (no rollup call, 3 calls)",
          not any(k.startswith("taste-rollup-") for k in new_keys)
          and rec["modelCalls"] == 3, f"{new_keys} {rec}")
    check("E next post grounds on the signal, usedBy rises",
          len(landed) == 1
          and landed[0].get("groundedIn") == ["sig-f_seed1"]
          and sig.get("usedBy") == 1,
          f"{landed} {sig}")

    # E-hourly: picker skip records a skip; a confirmed pick
    # lands one hourly post through the code gates
    mod, st = _load_e("p3e-hourly-")
    with mod._lock:
        mod._db["feedPosts"].append({
            "id": "f_seed2", "kind": "research",
            "title": "昨天的帖", "body": "x", "refs": [],
            "links": [], "why": "w", "images": [],
            "emoji": None, "sourceCard": None,
            "direction": "自托管", "angle": "旧角度",
            "edition": None, "likedAt": None,
            "createdAt": time.time() - 86400,
            "expiresAt": time.time() + 86400, "readAt": None})
        mod._save_locked()
    st["picker"] = json.dumps({"skip": True,
                               "reason": "没有差异点"},
                              ensure_ascii=False)
    mod._run_hourly_round("hourly")
    rec = _hist(mod)[-1]
    check("E hourly picker skip is a recorded skip",
          rec["status"] == "skipped"
          and "不开火" in (rec["error"] or "")
          and len(_posts(mod)) == 1, f"{rec}")
    st["batch"] = 10
    st["picker"] = json.dumps({
        "direction": "自托管", "angle": "小时角度",
        "diff": "与今日已发不同", "decidedBy": "reader_signal",
        "fitReason": "简报原话", "queries": ["hq"]},
        ensure_ascii=False)
    st["compose"] = [_compose_of("小时帖", 10)]
    mod._run_hourly_round("hourly")
    rec = _hist(mod)[-1]
    ps = [p for p in _posts(mod) if p["id"] != "f_seed2"]
    check("E hourly pick lands one post on the hourly line",
          rec["status"] == "ok" and len(ps) == 1
          and ps[0]["line"] == "hourly"
          and ps[0]["edition"] is None, f"{rec} {ps}")


def phase_f():
    # F-keys: two invocations of the SAME edition must not
    # share a single seat idempotency key. 2026-11-11: a
    # daytime dry run submitted copy payloads under the
    # edition-only keys (date + edition suffix, nothing
    # round-unique); the real evening round's different
    # payloads then got Hermes 409s on the compose seat and
    # all four directions dropped. Keys now carry the
    # round's own start epoch (rec["keyStamp"]).
    mod, st = _load_e("p3f-keys-")
    base = 1794396600.0  # 2026-11-11 19:30 Asia/Shanghai
    # invocation 1 -- the "dry run": a stale source forces
    # a finish repair round too, so the finish seat's key
    # is exercised alongside plan / compose / editor
    st["batch"] = 1
    st["published"] = "2020-01-05"
    st["finish_mode"] = "fix-why"
    st["plan"] = _plan_of(
        {"name": "自托管", "angle": "角度", "queries": ["kq1"]})
    st["compose"] = [_compose_of("干跑帖", 1, band="recent_3d")]
    mod._now = lambda: base
    mod._run_research_round("schedule-b")
    keys1 = set(st["prompts"])
    rec1 = _hist(mod)[-1]
    # invocation 2 -- the "real round", ten minutes later:
    # same edition, different payload, must own fresh keys
    st["prompts"] = {}
    st["batch"] = 2
    st["published"] = None
    st["finish_mode"] = "noop"
    st["plan"] = _plan_of(
        {"name": "自托管", "angle": "角度", "queries": ["kq2"]})
    st["compose"] = [_compose_of("真轮帖", 2)]
    mod._now = lambda: base + 600
    mod._run_research_round("schedule-b")
    keys2 = set(st["prompts"])
    rec2 = _hist(mod)[-1]
    check("F both invocations carry the same edition",
          rec1["edition"] == rec2["edition"] == "20261111-B",
          f"{rec1.get('edition')} vs {rec2.get('edition')}")
    check("F key stamps are round-unique and recorded",
          rec1["keyStamp"] == f"20261111B-{int(base)}"
          and rec2["keyStamp"] == f"20261111B-{int(base + 600)}",
          f"{rec1.get('keyStamp')} vs {rec2.get('keyStamp')}")
    seats = ("feed-research-plan-", "feed-research-",
             "feed-editor-")
    check("F no seat key collides across invocations",
          not (keys1 & keys2)
          and all(any(k.startswith(s) for k in keys1)
                  for s in seats)
          and all(any(k.startswith(s) for k in keys2)
                  for s in seats),
          f"{sorted(keys1)} vs {sorted(keys2)}")
    check("F finish seat key carries the suffix too",
          any(k.startswith(f"feed-finish-20261111B-{int(base)}-")
              for k in keys1), f"{sorted(keys1)}")


def _load_mod(name, tmp):
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    os.environ.pop("HERMES_API_KEY", None)
    spec = importlib.util.spec_from_file_location(name, BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    return mod


def phase_g():
    """Feed purity, as amended by the §459 reversal (user
    ruling 2026-11-24; the 2026-11-12 purity ruling below it):
    the digest NEVER becomes a post and approval events never
    do, but the day's substantive local events (idea /
    briefing / monitor / task) DO become standalone posts,
    one per event, capped per day; legacy digest/event posts
    in the store are archived in place by the assembler
    (archivedAt stamp, excluded from the flow listing, record
    kept and still readable/deletable by id); the source
    transitions (milestone all-done, monitor turning
    unreachable) still fire into the ledger exactly once."""
    from datetime import datetime as _dt
    now = time.time()
    # --- G1: events post nothing; legacy posts archived -------
    tmp = tempfile.mkdtemp(prefix="p3g1-")
    mod = _load_mod("ob_g1", tmp)
    with mod._lock:
        feed = mod._feed_meta_locked()
        feed["taskSnapshot"] = {"t_f1": "failed", "t_f2": "done"}
        feed["taskTitles"] = {"t_f1": "自测任务甲",
                              "t_f2": "自测任务乙"}
        # pin the day fields so the rollover cannot mask the
        # sweep's own digest-bookkeeping settlement
        today = _dt.fromtimestamp(now, tz=mod._sched_tz()) \
            .strftime("%Y-%m-%d")
        feed["digestDate"] = today
        feed["digestPostId"] = "f_old_digest"
        feed["digestEventKeys"] = ["idea:x1"]
        feed["eventDay"] = today
        feed["events"] = [
            {"key": "approval:1", "at": now - 900,
             "kind": "approval",
             "text": "有 1 项待审批（记忆/技能写入），等待处理",
             "refs": []},
            {"key": "approval:2", "at": now - 600,
             "kind": "approval",
             "text": "有 2 项待审批（记忆/技能写入），等待处理",
             "refs": []},
            {"key": "task:t_f1:1", "at": now - 500, "kind": "task",
             "text": "任务《自测任务甲》状态变为 failed",
             "state": "failed", "taskTitle": "自测任务甲",
             "refs": [{"type": "task", "id": "t_f1"}]},
            {"key": "task:t_f2:1", "at": now - 400, "kind": "task",
             "text": "任务《自测任务乙》状态变为 done",
             "state": "done", "taskTitle": "自测任务乙",
             "refs": [{"type": "task", "id": "t_f2"}]},
            {"key": "idea:x1", "at": now - 300, "kind": "idea",
             "text": "《自测点子》",
             "refs": [{"type": "idea", "id": "i_x1"}]},
        ]
        mod._db["ideas"].append(
            {"id": "i_x1", "title": "自测点子"})
        mod._db["feedPosts"] = [
            {"id": "f_old_digest", "kind": "digest",
             "title": "今日小结 · 6 件", "body": "x",
             "refs": [], "links": [], "why": None,
             "emoji": "💡", "createdAt": now - 3600,
             "expiresAt": now + 29 * 86400, "readAt": None},
            {"id": "f_old_event", "kind": "event",
             "title": "有 1 项待审批（记忆/技能写入），等待处理",
             "body": "x", "refs": [], "links": [],
             "why": "w", "emoji": "✍️", "createdAt": now - 1800,
             "expiresAt": now + 29 * 86400,
             "readAt": now - 100},
            {"id": "f_keep_research", "kind": "research",
             "title": "兴趣内容帖", "body": "x", "refs": [],
             "links": [], "why": "w", "images": [],
             "emoji": "🧩", "sourceCard": None,
             "direction": "自托管", "angle": "a",
             "edition": None, "likedAt": None,
             "createdAt": now - 600,
             "expiresAt": now + 29 * 86400, "readAt": None},
        ]
        mod._feed_assemble_locked()
        posts = list(mod._db["feedPosts"])
        feed = mod._feed_meta_locked()
    # §459: task x2 + idea become posts; the two approval
    # events never do -> 3 legacy + 3 new
    new_posts = [p for p in posts if p.get("eventKey")]
    check("G1 substantive events become posts (§459)",
          len(posts) == 6 and len(new_posts) == 3
          and {p["eventKey"] for p in new_posts}
          == {"task:t_f1:1", "task:t_f2:1", "idea:x1"},
          f"{len(posts)} {[p.get('eventKey') for p in posts]}")
    by_id = {p["id"]: p for p in posts}
    check("G1 legacy digest archived in place",
          by_id["f_old_digest"].get("archivedAt") is not None)
    check("G1 legacy event archived in place",
          by_id["f_old_event"].get("archivedAt") is not None)
    check("G1 archived stamps keep readAt untouched",
          by_id["f_old_event"].get("readAt") == now - 100
          and by_id["f_old_digest"].get("readAt") is None)
    check("G1 research post untouched",
          by_id["f_keep_research"].get("archivedAt") is None)
    check("G1 archive counts by kind",
          feed["purityArchived"] == {"digest": 1, "event": 1},
          f"{feed['purityArchived']}")
    check("G1 digest bookkeeping settled by the sweep",
          feed["digestPostId"] is None
          and feed["digestEventKeys"] == [],
          f"{feed['digestPostId']} {feed['digestEventKeys']}")
    check("G1 ledger still counts today's events",
          feed["lastEventCount"] == 5,
          f"{feed['lastEventCount']}")
    listed = mod._list_feed(7)
    check("G1 flow lists research + the 3 event posts",
          {p["id"] for p in listed}
          == {"f_keep_research"}
          | {p["id"] for p in new_posts},
          f"{[p['id'] for p in listed]}")
    got = mod._get_feed_post("f_old_event")
    check("G1 archived record readable by id, stamp exposed",
          got.get("archivedAt") is not None)
    # more events arrive; a second assembly changes nothing
    with mod._lock:
        feed = mod._feed_meta_locked()
        feed["events"].append(
            {"key": "approval:9", "at": now - 10,
             "kind": "approval",
             "text": "有 9 项待审批（记忆/技能写入），等待处理",
             "refs": []})
        mod._feed_assemble_locked()
        posts2 = list(mod._db["feedPosts"])
        feed = mod._feed_meta_locked()
    check("G1 second assembly is a no-op for the store",
          len(posts2) == 6
          and feed["purityArchived"] == {"digest": 1, "event": 1},
          f"{len(posts2)} {feed['purityArchived']}")
    # the delete path is unchanged: an archived record can
    # still be removed outright by the user, and stays gone
    mod._delete_feed_post("f_old_digest")
    with mod._lock:
        left = sorted(p["id"] for p in mod._db["feedPosts"])
    check("G1 archived record deletable, stays gone",
          left == sorted(["f_keep_research", "f_old_event"]
                         + [p["id"] for p in new_posts]),
          f"{left}")

    # --- G2: source transitions fire into the ledger; the
    # monitor one also posts under §459 -----------------------
    tmp = tempfile.mkdtemp(prefix="p3g2-")
    mod = _load_mod("ob_g2", tmp)
    with mod._lock:
        # G-6 (1.0.71, live): milestones were removed whole --
        # the milestone ledger-event checks that stood here
        # tested a retired feature and are gone with it.
        mon = {"id": "mon_g2", "name": "自测监测",
               "target": "https://example.com", "enabled": True,
               "scheduleText": "", "cronJobId": None,
               "lastCheckedAt": None, "lastResult": "unchanged",
               "lastError": None, "unreadChanges": 0,
               "latestChangeSummary": None, "latestChangeAt": None,
               "createdAt": now - 1000, "updatedAt": now - 1000,
               "cron": None, "intervalSeconds": 3600,
               "goalId": None, "snapshotText": "x",
               "snapshotFp": "fp", "nextRunAt": None}
        mod._db["monitors"].append(mon)
        r1 = mod._record_check_locked(mon, None, "连接超时",
                                      is_baseline=False)
        r2 = mod._record_check_locked(mon, None, "连接超时",
                                      is_baseline=False)
        feed = mod._feed_meta_locked()
        down = [e for e in feed["events"]
                if e.get("alert") == "down"]
        check("G2 monitor turning unreachable emits once",
              r1 == "failed" and r2 == "failed" and len(down) == 1,
              f"{len(down)}")
        mod._feed_assemble_locked()
        posts = list(mod._db["feedPosts"])
    # §459: the monitor-down event posts (monitor is one of
    # the four postable kinds)
    check("G2 monitor event posts (§459)",
          len(posts) == 1
          and posts[0].get("kind") == "event"
          and (posts[0].get("eventKey") or "")
              .startswith("monitor-down:"),
          f"{posts}")
    with mod._lock:
        feed = mod._feed_meta_locked()
        feed["taskSnapshot"] = {"t_g9": "failed"}
        feed["events"].append(
            {"key": "approval:g2", "at": time.time() - 30,
             "kind": "approval",
             "text": "有 1 项待审批（记忆/技能写入），等待处理",
             "refs": []})
        feed["events"].append(
            {"key": "task:t_ghost:1", "at": time.time() - 20,
             "kind": "task",
             "text": "任务《溢出任务》状态变为 failed",
             "state": "failed", "taskTitle": "溢出任务",
             "refs": [{"type": "task", "id": "t_ghost"}]})
        mod._feed_assemble_locked()
        posts = list(mod._db["feedPosts"])
    # the approval event never posts; the hand-appended task
    # event names a task outside the kanban snapshot, so its
    # ref does not resolve and it is ledgered without a post
    # -- the store still holds only the G2 monitor post
    check("G2 approval never posts; unresolvable ref skips",
          len(posts) == 1, f"{posts}")


if __name__ == "__main__":
    phase_a()
    phase_b()
    phase_c()
    phase_d()
    phase_e()
    phase_f()
    phase_g()
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
