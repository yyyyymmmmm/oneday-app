#!/usr/bin/env python3
"""P6 self-test for oneday_bridge.py goal categories +
task-links (0.40.0, spec three-pages v2 ch.3).

Phase A: HTTP contract against a subprocess bridge: category
is validated on POST/PATCH (enum or null, else 400), legacy
goals without the field read back null (never inferred),
task-links create/list with milestone validation, duplicate
links are idempotent, and deleting a goal cascade-removes
its links while only unlinking ideas/monitors.

Phase B: in-process: the feed kanban poll writes exactly one
fact-only agent entry when a linked task shows done, and
never a second one on later polls.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "oneday_bridge.py")
KEY = "p6-selftest-key"
PORT = 18750
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


def seed_base(now):
    return {
        "goals": [
            {"id": "g_a", "title": "带里程碑的目标", "note": "",
             "milestones": [{"id": "ms1", "title": "第一步",
                             "done": False}],
             "createdAt": now - 86400, "updatedAt": now - 86400,
             "status": "active", "completedAt": None,
             "parentId": None, "source": "manual"},
            {"id": "g_legacy", "title": "旧目标无类别字段",
             "note": "", "milestones": [],
             "createdAt": now - 90000, "updatedAt": now - 90000,
             "status": "active", "completedAt": None,
             "parentId": None, "source": "manual"},
        ],
        "ideas": [
            {"id": "i_link", "title": "挂靠点子", "detail": "d",
             "goalId": "g_a", "createdAt": now - 3600,
             "source": "manual", "evidence": "",
             "evidenceRef": None, "status": "pending",
             "taskId": None, "expiresAt": None},
        ],
        "monitors": [
            {"id": "mon_a", "name": "挂靠监测",
             "target": "https://example.com", "scheduleText": "",
             "cronJobId": None, "enabled": True,
             "lastCheckedAt": None, "lastResult": None,
             "lastError": None, "unreadChanges": 0,
             "latestChangeSummary": None, "latestChangeAt": None,
             "createdAt": now - 86400, "updatedAt": now - 86400,
             "goalId": "g_a"},
        ],
        "changes": [], "goalEntries": [], "briefings": [],
        "feedPosts": [], "goalTaskLinks": [], "meta": {},
    }


def phase_a():
    tmp = tempfile.mkdtemp(prefix="p6a-")
    now = time.time()
    with open(os.path.join(tmp, "data.json"), "w",
              encoding="utf-8") as f:
        json.dump(seed_base(now), f, ensure_ascii=False)
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
        s, body = call("GET", "/goals")
        items = {g["id"]: g for g in body["items"]}
        check("A legacy + unset goals read category null",
              s == 200 and items["g_a"]["category"] is None
              and items["g_legacy"]["category"] is None, f"{s}")
        s, body = call("POST", "/goals",
                       {"title": "财务目标", "category": "finance"})
        gid_fin = body.get("id")
        check("A create with category 201 + stored",
              s == 201 and body["category"] == "finance", f"{s} {body}")
        s, _ = call("POST", "/goals",
                    {"title": "坏类别", "category": "bogus"})
        check("A create bogus category 400", s == 400, f"{s}")
        s, _ = call("POST", "/goals",
                    {"title": "数字类别", "category": 123})
        check("A create non-string category 400", s == 400, f"{s}")
        s, body = call("POST", "/goals", {"title": "无类别目标"})
        gid_plain = body.get("id")
        check("A create without category reads null",
              s == 201 and body["category"] is None, f"{s} {body}")
        s, body = call("PATCH", f"/goals/{gid_fin}",
                       {"category": "health"})
        check("A patch category settles",
              s == 200 and body["category"] == "health", f"{s} {body}")
        s, _ = call("PATCH", f"/goals/{gid_fin}",
                    {"category": "bogus"})
        check("A patch bogus category 400", s == 400, f"{s}")
        s, body = call("PATCH", f"/goals/{gid_fin}",
                       {"category": None})
        check("A patch category null clears",
              s == 200 and body["category"] is None, f"{s} {body}")

        s, body = call("POST", "/goals/g_a/task-links",
                       {"taskId": "t_1"})
        link1 = body.get("id")
        check("A link create 201 + shape",
              s == 201 and body["goalId"] == "g_a"
              and body["taskId"] == "t_1"
              and body["milestoneId"] is None
              and body["completionEntryAt"] is None,
              f"{s} {body}")
        s, body = call("POST", "/goals/g_a/task-links",
                       {"taskId": "t_1"})
        check("A duplicate link idempotent (same id)",
              s == 201 and body["id"] == link1, f"{s} {body}")
        s, body = call("GET", "/goals/g_a/task-links")
        check("A link list still one row",
              s == 200 and len(body["items"]) == 1, f"{s} {body}")
        s, body = call("POST", "/goals/g_a/task-links",
                       {"taskId": "t_2", "milestoneId": "ms1"})
        check("A link with real milestone 201",
              s == 201 and body["milestoneId"] == "ms1",
              f"{s} {body}")
        s, _ = call("POST", "/goals/g_a/task-links",
                    {"taskId": "t_3", "milestoneId": "nope"})
        check("A link bogus milestone 400", s == 400, f"{s}")
        s, _ = call("POST", "/goals/g_a/task-links",
                    {"taskId": "  "})
        check("A link blank taskId 400", s == 400, f"{s}")
        s, _ = call("POST", "/goals/g_a/task-links", {})
        check("A link missing taskId 400", s == 400, f"{s}")
        s, _ = call("POST", "/goals/nope/task-links",
                    {"taskId": "t_x"})
        check("A link on missing goal 404", s == 404, f"{s}")
        s, _ = call("GET", "/goals/nope/task-links")
        check("A link list on missing goal 404", s == 404, f"{s}")

        s, _ = call("DELETE", "/goals/g_a")
        check("A delete goal 200", s == 200, f"{s}")
        s, _ = call("GET", "/goals/g_a/task-links")
        check("A links gone with goal (404)",
              s == 404, f"{s}")
        with open(os.path.join(tmp, "data.json"),
                  encoding="utf-8") as f:
            stored = json.load(f)
        check("A stored links cascade-removed",
              stored["goalTaskLinks"] == [], f"{stored['goalTaskLinks']}")
        s, body = call("GET", "/ideas")
        idea = {i["id"]: i for i in body["items"]}["i_link"]
        check("A idea unlinked not deleted",
              idea["goalId"] is None, f"{idea}")
        s, body = call("GET", "/monitors")
        mon = {m["id"]: m for m in body["items"]}["mon_a"]
        check("A monitor unlinked not deleted",
              mon["goalId"] is None, f"{mon}")
    finally:
        proc.terminate()
        proc.wait(timeout=10)


def phase_b():
    tmp = tempfile.mkdtemp(prefix="p6b-")
    now = time.time()
    seed = seed_base(now)
    seed["goalTaskLinks"] = [
        {"id": "gl_1", "goalId": "g_a", "taskId": "t_done",
         "milestoneId": None, "createdAt": now - 3600,
         "completionEntryAt": None},
        {"id": "gl_2", "goalId": "g_a", "taskId": "t_open",
         "milestoneId": "ms1", "createdAt": now - 3600,
         "completionEntryAt": None},
    ]
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(seed, f, ensure_ascii=False)
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = data_path
    os.environ.pop("HERMES_API_KEY", None)
    spec = importlib.util.spec_from_file_location("ob_f", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    board = {"t_done": ("写完发言稿", "done"),
             "t_open": ("买请柬", "todo")}
    mod._fetch_kanban_tasks = lambda: (dict(board), None)
    mod._feed_poll_remote()
    entries = [e for e in mod._db["goalEntries"]
               if e["goalId"] == "g_a"]
    check("B done linked task earns one fact entry",
          len(entries) == 1
          and entries[0]["source"] == "agent"
          and "写完发言稿" in entries[0]["body"]
          and "t_done" in entries[0]["body"],
          f"{entries}")
    links = {l["id"]: l for l in mod._db["goalTaskLinks"]}
    echo = mod._db["goalEchoState"]
    check("B seed links folded into the field store (1.0.65)",
          links == {}
          and mod._db["taskGoals"]["t_done"]["goalId"] == "g_a"
          and mod._db["taskGoals"]["t_open"]["milestoneId"]
          == "ms1",
          f"{mod._db['taskGoals']}")
    check("B completion stamped only on done task",
          echo.get("t_done", {}).get("completedEntryAt")
          is not None
          and echo.get("t_open", {}).get("completedEntryAt")
          is None,
          f"{echo}")
    mod._feed_poll_remote()
    entries = [e for e in mod._db["goalEntries"]
               if e["goalId"] == "g_a"]
    check("B second poll adds no second entry",
          len(entries) == 1, f"{entries}")
    board["t_open"] = ("买请柬", "completed")
    mod._fetch_kanban_tasks = lambda: (dict(board), None)
    mod._feed_poll_remote()
    entries = [e for e in mod._db["goalEntries"]
               if e["goalId"] == "g_a"]
    check("B later completion earns its own entry",
          len(entries) == 2
          and "买请柬" in entries[-1]["body"],
          f"{entries}")


def phase_c():
    # §117 (0.47.0): generated ideas carry emoji +
    # deliverables tolerantly; feed image candidates are
    # ordered meta > extractor list > body image.
    tmp = tempfile.mkdtemp(prefix="p6c-")
    now = time.time()
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(seed_base(now), f, ensure_ascii=False)
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = data_path
    os.environ.pop("HERMES_API_KEY", None)
    spec = importlib.util.spec_from_file_location("ob_g", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    anchors = {"S1": {"kind": "S", "objectId": "sess_x",
                      "title": "聊了年会主持稿定稿"}}
    output = json.dumps([{
        "title": "我可以把定稿主持稿存成文件",
        # detail carries the anchor in its first half (G1,
        # 1.0.16): the pre-G fixture body was generic-with-the-
        # fact-only-in-evidence, exactly what the new gate drops.
        "detail": "把 10 月 29 日定稿的主持稿原文存成一份文件，"
                  "11 月 16 日年会当天直接打开就能念，"
                  "不用再翻聊天记录找版本。",
        "evidence": "10月29日定稿的主持稿还没落盘",
        "evidenceRef": "S1",
        "goalId": None,
        "emoji": "💍",
        "deliverables": [
            {"name": "年会主持稿稿文档",
             "summary": "可直接念的完整发言稿"},
            {"name": "", "summary": "无名条目应丢"},
            "not-a-dict",
        ],
    }], ensure_ascii=False)
    cards, dropped, reasons, perr = mod._parse_generated_cards(
        output, set(), anchors, [])
    check("C card lands with emoji (§117)",
          len(cards) == 1 and cards[0]["emoji"] == "💍",
          f"{cards} err={perr}")
    check("C deliverables cleaned (§117)",
          len(cards) == 1 and cards[0]["deliverables"] == [
              {"name": "年会主持稿稿文档",
               "summary": "可直接念的完整发言稿"}],
          f"{cards}")
    check("C bad emoji collapses (§117)",
          mod._clean_emoji(123) is None
          and mod._clean_emoji("x" * 40) is None
          and mod._clean_emoji(" 📄 ") == "📄")
    mod._page_meta_image = lambda url: "https://ex.com/og.png"
    extract = {"content": "正文 ![图](https://ex.com/body.png) 继续",
               "images": ["https://ex.com/list.png",
                          "https://ex.com/og.png"]}
    ordered = mod._ordered_page_images("https://ex.com/post",
                                       extract)
    check("C image order meta>list>body (§117)",
          ordered == ["https://ex.com/og.png",
                      "https://ex.com/list.png",
                      "https://ex.com/body.png"], f"{ordered}")
    mod._page_meta_image = lambda url: None
    ordered = mod._ordered_page_images("https://ex.com/post",
                                       extract)
    check("C image order without meta (§117)",
          ordered == ["https://ex.com/list.png",
                      "https://ex.com/og.png",
                      "https://ex.com/body.png"], f"{ordered}")


def phase_d():
    # §122 (1.0.13): landing-side feed discipline -- an
    # over-long body is clamped at a sentence boundary;
    # tall-screenshot and low-res candidate images drop at
    # verify, a normal og image survives.
    tmp = tempfile.mkdtemp(prefix="p6d-")
    now = time.time()
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(seed_base(now), f, ensure_ascii=False)
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = data_path
    os.environ.pop("HERMES_API_KEY", None)
    spec = importlib.util.spec_from_file_location("ob_h", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()

    def png(w, h):
        return (b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\x0dIHDR"
                + w.to_bytes(4, "big") + h.to_bytes(4, "big")
                + b"\x08\x06\x00\x00\x00")

    check("D png dims parsed (§122)",
          mod._parse_image_dimensions(png(1200, 675))
          == (1200, 675))
    check("D unknown bytes unmeasured (§122)",
          mod._parse_image_dimensions(b"not an image") is None)
    tall = "https://ex.com/tall.png"
    small = "https://ex.com/small.png"
    good = "https://ex.com/og.png"
    dims = {tall: (900, 2400), small: (300, 200),
            good: (1200, 675)}
    mod._image_dimensions = lambda url: dims.get(url)
    check("D tall screenshot dropped (§122)",
          mod._image_shape_ok(tall) is False)
    check("D low-res thumbnail dropped (§122)",
          mod._image_shape_ok(small) is False)
    check("D normal og kept (§122)",
          mod._image_shape_ok(good) is True)
    check("D unmeasured image kept (§122)",
          mod._image_shape_ok("https://ex.com/mystery.png")
          is True)
    mod._http_head_ok = lambda url: True
    pool = {u: "https://ex.com/post" for u in dims}
    titles = {"https://ex.com/post": "来源页"}
    item = {"title": "短帖",
            "body": "发生了新事。值得一看。来源见链接。",
            "why": "与简报方向相关",
            "links": [{"title": "来源页",
                       "url": "https://ex.com/post"}],
            "images": [tall, good], "refs": [], "emoji": "📌"}
    post, err = mod._verify_research_post(item, titles, pool, {})
    check("D verify drops tall, keeps og (§122)",
          err is None and post["images"] == [
              {"url": good, "sourceUrl": "https://ex.com/post"}],
          f"{post} err={err}")
    item2 = dict(item, images=[tall, small])
    post2, err2 = mod._verify_research_post(
        item2, titles, pool, {})
    check("D all-bad images land imageless (§122)",
          err2 is None and post2["images"] == [], f"{post2}")
    long_body = "".join(f"第{i}句讲一件事。"
                        for i in range(80))
    clamped = mod._clamp_feed_body(long_body)
    check("D over-long body clamped at sentence (§122)",
          0 < len(clamped) <= 260 and clamped.endswith("。")
          and long_body.startswith(clamped),
          f"len={len(clamped)}")
    short = "短正文。就这样。"
    check("D short body untouched (§122)",
          mod._clamp_feed_body(short) == short)
    check("D short title untouched (§122)",
          mod._clamp_feed_title("短标题") == "短标题")
    sep_title = "个人开发者卖 AI 技能变现，扣子是目前唯一能直接收钱的通道之一"
    check("D long title cut at word boundary (§122)",
          mod._clamp_feed_title(sep_title)
          == "个人开发者卖 AI 技能变现",
          f"{mod._clamp_feed_title(sep_title)}")
    hard_title = ("这是一个没有任何分隔符的超长标题专门用来"
                  "测试硬截断行为边界继续延伸")
    check("D separator-less title hard-cut (§122)",
          mod._clamp_feed_title(hard_title)
          == hard_title[:30])
    item3 = dict(item, title=sep_title, images=[good])
    post3, err3 = mod._verify_research_post(
        item3, titles, pool, {})
    check("D verify clamps long title (§122)",
          err3 is None
          and post3["title"] == "个人开发者卖 AI 技能变现",
          f"{post3} err={err3}")


def phase_e():
    # Ideas G (1.0.16): G1 detail-anchor machine gate (facts
    # must live in the body's first half, not only in evidence)
    # and G2 entailment check (card judged WITH its material
    # line) plus the single rewrite attempt.
    tmp = tempfile.mkdtemp(prefix="p6e-")
    now = time.time()
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(seed_base(now), f, ensure_ascii=False)
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = data_path
    os.environ.pop("HERMES_API_KEY", None)
    spec = importlib.util.spec_from_file_location("ob_i", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()

    anchors = {
        "S1": {"kind": "S", "objectId": "sess_wed",
               "title": "聊了年会主持稿定稿"},
        "R1": {"kind": "R", "objectId": "mem_xdun",
               "title": "产品博客口径"},
        "G1": {"kind": "G", "objectId": "g_wed",
               "title": "把年会办好"},
    }
    lines = {
        "S1": ("S1. 10-29 《聊了年会主持稿定稿》（12 条消息）\n"
               "    摘要：10月29日确认发言定稿，11月16日13时在"
               "青云镇白杨村举行年会，主持稿还没落盘成文件"),
        "R1": ("R1. [长期记忆] 产品博客口径：会员方案已于"
               "10 月 29 日改为新版口径，旧文仍有旧说法待清"),
        "G1": ("G1. 《把年会办好》 id=g_wed（里程碑 2/5）\n"
               "    进展 11-02：发言稿已定稿，11月16日13时"
               "青云镇白杨村"),
    }
    toks = mod._anchor_tokens(lines["S1"], anchors["S1"])
    check("E tokens carry date + prose proper noun (G1)",
          "10月29日" in toks and "11月16日" in toks
          and "青云镇白" in toks, f"{sorted(toks)[:12]}")

    good = {
        "title": "我可以把定稿主持稿存成文件",
        "detail": "把 10 月 29 日定稿的主持稿原文存成一份文件，"
                  "11 月 16 日年会当天直接打开就能念，"
                  "不用再翻聊天记录找版本。",
        "evidence": "10月29日定稿的主持稿还没落盘",
        "evidenceRef": "S1", "goalId": None,
    }
    generic = {
        "title": "我可以清掉站里的旧说法",
        "detail": "我把站里的旧文章逐篇检查一遍，该改的地方"
                  "都改过来，改完给你一份清单确认。",
        "evidence": "10月29日新版口径已定，旧文旧说法还没清",
        "evidenceRef": "R1", "goalId": None,
    }
    late_anchor = {
        "title": "我可以核对年会当天安排",
        "detail": "先把流程和名单都核对一遍，确认每桌安排"
                  "都没有遗漏，最后再把 11 月 16 日的时间"
                  "写进提醒里。",
        "evidence": "进展记 11月16日13时举行年会",
        "evidenceRef": "G1", "goalId": "g_wed",
    }
    out = json.dumps([good, generic, late_anchor],
                     ensure_ascii=False)
    cards, dropped, reasons, perr = mod._parse_generated_cards(
        out, {"g_wed"}, anchors, [], lines)
    check("E anchored-detail card lands (G1)",
          perr is None and len(cards) == 1
          and cards[0]["title"] == good["title"],
          f"{cards} err={perr}")
    check("E generic + late-anchor details dropped (G1)",
          dropped == 2 and reasons["noDetailAnchor"] == 2,
          f"dropped={dropped} reasons={reasons}")

    # --- G2: check sees the material line; failure -> rewrite
    card_b = {
        "title": "我可以扫清 产品博客残留的旧说法",
        "detail": "按 10 月 29 日新版口径逐篇改写旧文；另据"
                  "消息，Pro 将在 12 月 1 日再次调整额度，"
                  "我一并把说明补上。",
        "evidence": "10月29日新版口径已定，旧文仍有旧说法",
        "evidenceRef": "R1", "anchorId": "R:mem_xdun",
        "goalId": None, "emoji": None, "deliverables": [],
    }
    card_a = dict(cards[0])
    canned = {}
    prompts = []

    def fake_submit(prompt, idem_key):
        prompts.append((idem_key, prompt))
        return canned[("run", idem_key)], None

    def fake_poll(run_id):
        return canned[("out", run_id)], None

    mod._hermes_submit_run = fake_submit
    mod._hermes_poll_run = fake_poll
    canned[("run", "ideas-check-e1")] = "run-ck1"
    canned[("out", "run-ck1")] = json.dumps([
        {"title": card_a["title"], "ok": True, "issues": ""},
        {"title": card_b["title"], "ok": False,
         "issues": "断言「12 月 1 日再次调整额度」在素材行中"
                   "无支撑"}], ensure_ascii=False)
    kept, failed, note = mod._self_check_cards(
        [card_a, card_b], "e1", lines)
    check("E entailment keeps supported, fails unsupported (G2)",
          note is None and kept == [card_a]
          and len(failed) == 1 and failed[0][0] is card_b
          and "12 月 1 日" in failed[0][1],
          f"kept={kept} failed={failed} note={note}")
    check("E check prompt carries the material line (G2)",
          any("旧文仍有旧说法待清" in p
              for _k, p in prompts),
          f"{[k for k, _p in prompts]}")

    fixed_b = {
        "title": card_b["title"],
        "detail": "按 10 月 29 日新版口径，逐篇改写 产品博客"
                  "旧文里残留的旧说法，改完列一份清单给你"
                  "确认，不动其他文章。",
        "evidence": "10月29日新版口径已定，旧文仍有旧说法",
        "evidenceRef": "R1", "goalId": None,
    }
    canned[("run", "ideas-rewrite-e1")] = "run-rw1"
    canned[("out", "run-rw1")] = json.dumps(
        [fixed_b], ensure_ascii=False)
    rw, rw_dropped, rw_reasons, rw_note = mod._rewrite_cards(
        failed, set(), anchors, [card_a], lines, "e1")
    check("E rewrite lands through full gates (G2)",
          rw_note is None and len(rw) == 1
          and "12 月 1 日" not in rw[0]["detail"],
          f"{rw} note={rw_note} reasons={rw_reasons}")
    canned[("run", "ideas-check-e1-rw")] = "run-ck2"
    canned[("out", "run-ck2")] = json.dumps(
        [{"title": fixed_b["title"], "ok": True, "issues": ""}],
        ensure_ascii=False)
    kept2, failed2, note2 = mod._self_check_cards(
        rw, "e1-rw", lines)
    check("E rewritten card passes recheck (G2)",
          note2 is None and kept2 == rw and failed2 == [],
          f"kept2={kept2} failed2={failed2}")

    # A rewrite that STILL invents facts fails the recheck and
    # stays failed (the round books it as unsupported).
    still_bad = dict(fixed_b)
    still_bad["detail"] = ("按 10 月 29 日新版口径改写旧文；"
                           "顺带把 12 月 1 日的新额度说明也"
                           "写进去，免得再改一遍。")
    canned[("run", "ideas-rewrite-e2")] = "run-rw2"
    canned[("out", "run-rw2")] = json.dumps(
        [still_bad], ensure_ascii=False)
    failed_b = [(card_b, "断言「12 月 1 日」无支撑")]
    rw2, _d2, _r2, _n2 = mod._rewrite_cards(
        failed_b, set(), anchors, [], lines, "e2")
    canned[("run", "ideas-check-e2-rw")] = "run-ck3"
    canned[("out", "run-ck3")] = json.dumps(
        [{"title": still_bad["title"], "ok": False,
          "issues": "断言「12 月 1 日的新额度说明」在素材行中"
                    "无支撑"}], ensure_ascii=False)
    kept3, failed3, _note3 = mod._self_check_cards(
        rw2, "e2-rw", lines)
    check("E still-unsupported rewrite stays failed (G2)",
          kept3 == [] and len(failed3) == 1,
          f"kept3={kept3} failed3={failed3}")


def main():
    phase_a()
    phase_b()
    phase_c()
    phase_d()
    phase_e()
    print(f"p6 selftest: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
