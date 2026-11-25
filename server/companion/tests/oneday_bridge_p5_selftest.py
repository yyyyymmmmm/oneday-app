#!/usr/bin/env python3
"""P5 self-test for oneday_bridge.py ideas v2 (0.39.0).

Phase A: HTTP contract against a subprocess bridge (no Hermes
key): the generated-needs-evidence hard gate still holds, a
generated evidenceRef must be anchor-shaped, dismissReason
"tooGeneric" settles only on dismissals, and idea views expose
anchorId/dismissReason.

Phase B: one full generation round in-process with stubbed
Dashboard/memory channels and queued model outputs: seven-source
assembly (S digests, G entries, K signals, R excerpts), the
anchor gate (unknown ref, fact-free evidence), anchor-level
dedup (adopted anchor, duplicate title), the action-gate
self-check drop, dropped-reason accounting, and the digest
cache (a second round does not re-run the digest).
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
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "oneday_bridge.py")
KEY = "p5-selftest-key"
PORT = 18749
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


def iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).isoformat()


def phase_a():
    tmp = tempfile.mkdtemp(prefix="p5a-")
    now = time.time()
    seed = {
        "goals": [{"id": "g_a", "title": "自测目标", "note": "",
                   "milestones": [], "createdAt": now - 86400,
                   "updatedAt": now - 86400, "status": "active",
                   "completedAt": None, "parentId": None,
                   "source": "manual"}],
        "ideas": [
            {"id": "i_adopted", "title": "已采纳卡", "detail": "d",
             "goalId": None, "createdAt": now - 86400,
             "source": "generated", "evidence": "任务已完成",
             "evidenceRef": "K1", "anchorId": "K:t_done1",
             "dismissReason": None, "status": "adopted",
             "taskId": "t_done1", "expiresAt": None},
            {"id": "i_dis", "title": "被标太泛的卡", "detail": "d",
             "goalId": None, "createdAt": now - 86400,
             "source": "generated", "evidence": "x",
             "evidenceRef": "R1", "anchorId": "R:mem_x",
             "dismissReason": "tooGeneric", "status": "dismissed",
             "statusAt": now - 3600, "taskId": None,
             "expiresAt": None},
        ],
        "monitors": [], "changes": [], "goalEntries": [],
        "briefings": [], "feedPosts": [], "meta": {},
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
        s, body = call("GET", "/ideas")
        items = {i["id"]: i for i in body["items"]}
        check("A view exposes anchorId + dismissReason",
              s == 200
              and items["i_adopted"]["anchorId"] == "K:t_done1"
              and items["i_dis"]["dismissReason"] == "tooGeneric",
              f"{s}")
        s, _ = call("POST", "/ideas",
                    {"title": "无依据生成卡", "detail": "d",
                     "source": "generated", "evidence": ""})
        check("A generated without evidence 400", s == 400, f"{s}")
        s, _ = call("POST", "/ideas",
                    {"title": "编号格式错", "detail": "d",
                     "source": "generated", "evidence": "有依据",
                     "evidenceRef": "X9"})
        check("A generated with misshaped ref 400", s == 400,
              f"{s}")
        s, body = call("POST", "/ideas",
                       {"title": "合规生成卡", "detail": "d",
                        "source": "generated",
                        "evidence": "目标在 11 月 1 日有进展",
                        "evidenceRef": "K1"})
        check("A generated with anchor ref 201 + null v2 fields",
              s == 201 and body["anchorId"] is None
              and body["dismissReason"] is None, f"{s} {body}")
        s, body = call("POST", "/ideas",
                       {"title": "手记一张", "detail": "d"})
        manual_id = body["id"]
        check("A manual create 201", s == 201, f"{s}")
        s, body = call("PATCH", f"/ideas/{manual_id}",
                       {"status": "dismissed",
                        "dismissReason": "tooGeneric"})
        check("A dismiss with tooGeneric settles",
              s == 200 and body["status"] == "dismissed"
              and body["dismissReason"] == "tooGeneric",
              f"{s} {body}")
        s, body = call("POST", "/ideas",
                       {"title": "手记二张", "detail": "d"})
        mid2 = body["id"]
        s, _ = call("PATCH", f"/ideas/{mid2}",
                    {"status": "dismissed",
                     "dismissReason": "bogus"})
        check("A bogus dismissReason 400", s == 400, f"{s}")
        s, _ = call("PATCH", f"/ideas/{mid2}",
                    {"status": "adopted",
                     "dismissReason": "tooGeneric"})
        check("A reason on non-dismiss 400", s == 400, f"{s}")
        s, body = call("PATCH", f"/ideas/{mid2}",
                       {"status": "dismissed"})
        check("A plain dismiss keeps reason null",
              s == 200 and body["dismissReason"] is None,
              f"{s} {body}")
    finally:
        proc.terminate()
        proc.wait(timeout=10)


def phase_b():
    tmp = tempfile.mkdtemp(prefix="p5b-")
    now = time.time()
    seed = {
        "goals": [{"id": "g_a", "title": "办好婚礼", "note": "",
                   "milestones": [{"id": "m1", "title": "定发言稿",
                                   "done": True}],
                   "createdAt": now - 30 * 86400,
                   "updatedAt": now - 2 * 86400, "status": "active",
                   "completedAt": None, "parentId": None,
                   "source": "manual"}],
        "ideas": [
            {"id": "i_done", "title": "已采纳的合同收尾",
             "detail": "d", "goalId": None,
             "createdAt": now - 2 * 86400, "source": "generated",
             "evidence": "任务 2 天前完成", "evidenceRef": "K1",
             "anchorId": "K:t_done1", "dismissReason": None,
             "status": "adopted", "taskId": "t_done1",
             "expiresAt": None},
            {"id": "i_dis", "title": "太泛的旧卡", "detail": "d",
             "goalId": None, "createdAt": now - 3 * 86400,
             "source": "generated", "evidence": "x",
             "evidenceRef": "R1", "anchorId": "R:mem_old1",
             "dismissReason": "tooGeneric", "status": "dismissed",
             "statusAt": now - 86400, "taskId": None,
             "expiresAt": None},
            {"id": "i_exist", "title": "已有卡片标题", "detail": "d",
             "goalId": None, "createdAt": now - 86400,
             "source": "manual", "evidence": "",
             "evidenceRef": None, "status": "pending",
             "taskId": None, "expiresAt": None},
        ],
        "monitors": [], "changes": [],
        "goalEntries": [{"id": "e1", "goalId": "g_a",
                         "body": "发言稿已定稿，全家都看过了",
                         "source": "user",
                         "createdAt": now - 2 * 86400}],
        "briefings": [{"id": "b1", "goalId": "g_a",
                       "period": "2026-W45", "title": "婚礼筹备周报",
                       "body": "x", "createdAt": now - 3 * 86400}],
        "feedPosts": [],
        "meta": {"brief": "关心婚礼与自托管"},
    }
    data_path = os.path.join(tmp, "data.json")
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(seed, f, ensure_ascii=False)
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = data_path
    os.environ["HERMES_API_KEY"] = "fake-key"
    os.environ["WRITE_GATE_BRIDGE_KEY"] = "wg-key"
    # ID-1: seed a device sync copy (through device_sync's own
    # write path) so the round's C source reads a healthy copy.
    dev_dir = os.path.join(tmp, "device-data")
    os.makedirs(dev_dir)
    os.environ["DEVICE_DATA_DIR"] = dev_dir
    from pathlib import Path as _Path
    _dspec = importlib.util.spec_from_file_location(
        "ds_p5", os.path.join(HERE, "device_sync.py"))
    _dsync = importlib.util.module_from_spec(_dspec)
    _dspec.loader.exec_module(_dsync)
    _dsync.init(_Path(dev_dir))
    _dsync.stage_batch("calendar", "p5-cal", [{
        "occurrenceId": "occ_rehearsal", "eventId": "ev_rehearsal",
        "title": "婚礼彩排", "start": iso(now + 2 * 86400),
        "end": iso(now + 2 * 86400 + 3600), "allDay": False,
        "calendarName": "个人", "location": "土基镇西故现村"}],
        mode="full")
    _dsync.complete("calendar", "p5-cal", 1,
                    permission_state="granted")
    spec = importlib.util.spec_from_file_location("ob_e", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()

    mod._ledger_sessions = lambda: [
        {"id": "sess-main-1", "title": "聊婚礼安排",
         "startedAt": now - 86400, "endedAt": None,
         "messageCount": 5, "source": "api"},
        {"id": "cron-1", "title": "定时任务会话",
         "startedAt": now - 3600, "endedAt": None,
         "messageCount": 9, "source": "cron"},
        {"id": "probe-x", "title": "探针会话",
         "startedAt": now - 3600, "endedAt": None,
         "messageCount": 3, "source": "api"},
        {"id": "sess-old", "title": "旧会话",
         "startedAt": now - 20 * 86400, "endedAt": None,
         "messageCount": 4, "source": "api"},
    ]
    mod._ledger_messages = lambda sid: [
        {"role": "user", "ts": now - 80000,
         "text": "婚礼发言 10 月 29 日定稿了，11 月 16 日 13 点"
                 "在土基镇西故现村办"},
        {"role": "assistant", "ts": now - 79900,
         "text": "记下了，当天流程还没排"},
        {"role": "tool", "ts": now - 79800, "text": "tool noise"},
    ] if sid == "sess-main-1" else []
    board = {"tasks": [
        {"id": "t_blocked", "title": "供应商合同确认",
         "status": "blocked", "body": "等对方回合同盖章",
         "updated_at": iso(now - 86400)},
        {"id": "t_done1", "title": "场地定金缴纳",
         "status": "done", "updated_at": iso(now - 86400)},
        {"id": "t_stale", "title": "整理旧照片", "status": "todo",
         "updated_at": iso(now - 10.5 * 86400)},
        {"id": "t_plain", "title": "买打印纸", "status": "todo",
         "updated_at": iso(now - 3600)},
    ]}
    mod._ledger_dash = type("Dash", (), {
        "get": staticmethod(
            lambda path: board if "kanban" in path else None)})()
    entries = {"entries": [
        {"id": "mem_wed", "target": "memory", "title": "婚礼发言定稿",
         "summary": "10 月 29 日确认的发言原稿，11 月 16 日 13 时"
                    "在土基镇西故现村举行婚礼",
         "updatedAt": now, "digest": "x"},
        {"id": "mem_old", "target": "memory", "title": "某次旧备份",
         "summary": "三年前的服务器备份记录",
         "updatedAt": now - 90 * 86400, "digest": "y"},
    ]}

    def fake_http_json(url, **kw):
        if url.endswith("/memories"):
            return 200, entries, ""
        raise AssertionError(f"unexpected http call {url}")

    mod._http_json = fake_http_json

    digest_out = json.dumps([{
        "ref": "D1",
        "summary": "谈了婚礼发言：10 月 29 日定稿，11 月 16 日"
                   " 13 时在土基镇西故现村举行，还留了当天流程"
                   "没排的尾巴"}], ensure_ascii=False)
    card_ok = {"title": "我可以替你催办卡住的合同确认",
               # G1 (1.0.16): the anchor lives in the detail's
               # first half, not only in evidence.
               "detail": "供应商合同确认还卡在对方盖章：我先把"
                         "合同要点整理成一页纸发你确认，你点头"
                         "后我再去联系对方催办，未经确认不外发。",
               "evidence": "任务板上「供应商合同确认」一直卡住，"
                           "等对方回合同盖章",
               "evidenceRef": "K1", "goalId": None}
    gen_round1 = json.dumps([
        card_ok,
        {"title": "我可以帮你看看那个会话", "detail": "x",
         "evidence": "据 S9 在 11 月 1 日的讨论",
         "evidenceRef": "S9", "goalId": None},
        {"title": "我可以陪你放松一下", "detail": "x",
         "evidence": "你最近挺忙的，可以考虑休息",
         "evidenceRef": "K4", "goalId": None},
        {"title": "我可以给场地定金做收尾确认", "detail": "x",
         "evidence": "场地定金任务 2 天前刚完成",
         "evidenceRef": "K2", "goalId": None},
        {"title": "我可以把发言原稿做成婚礼当天包",
         "detail": "长期记忆里 10 月 29 日确认的发言原稿还没"
                   "做成当天包，我把原稿加上 11 月 16 日的"
                   "流程整理成一份当天包发你。",
         "evidence": "长期记忆里记着 10 月 29 日确认的发言原稿",
         "evidenceRef": "R1", "goalId": "g_a"},
        {"title": "已有卡片标题", "detail": "x",
         "evidence": "目标在 11 月 1 日有进展",
         "evidenceRef": "G1", "goalId": None},
    ], ensure_ascii=False)
    # G2 (1.0.16): the first entailment check fails the 当天包
    # card; the rewrite (fed the issues + material line) fixes
    # it and the recheck passes it.
    check_out = json.dumps([
        {"title": "我可以替你催办卡住的合同确认", "ok": True,
         "issues": ""},
        {"title": "我可以把发言原稿做成婚礼当天包", "ok": False,
         "issues": "正文没有写清边界（哪些不做、哪一步先经"
                   "用户确认）"},
    ], ensure_ascii=False)
    check_out_rw = json.dumps([
        {"title": "我可以把发言原稿做成婚礼当天包", "ok": True,
         "issues": ""},
    ], ensure_ascii=False)
    rewrite_out = json.dumps([{
        "title": "我可以把发言原稿做成婚礼当天包",
        "detail": "按长期记忆里 10 月 29 日确认的发言原稿，"
                  "我把原稿和 11 月 16 日当天流程整理成一份"
                  "当天包发你确认，确认后不再改动。",
        "evidence": "长期记忆里记着 10 月 29 日确认的发言原稿",
        "evidenceRef": "R1", "goalId": "g_a"},
    ], ensure_ascii=False)
    gen_outputs = [gen_round1, json.dumps([card_ok],
                                          ensure_ascii=False)]
    submits = {"sum": 0, "gen": 0, "check": 0, "rewrite": 0}
    prompts = {}
    check_calls = {"n": 0}

    def fake_submit(prompt, idem):
        if idem.startswith("ideas-sum-"):
            submits["sum"] += 1
        elif idem.startswith("ideas-check-"):
            submits["check"] += 1
        elif idem.startswith("ideas-rewrite-"):
            submits["rewrite"] += 1
        else:
            submits["gen"] += 1
            prompts["gen"] = prompt
        return idem, None

    def fake_poll(run_id):
        if run_id.startswith("ideas-sum-"):
            return digest_out, None
        if run_id.startswith("ideas-check-"):
            check_calls["n"] += 1
            return (check_out if check_calls["n"] == 1
                    else check_out_rw), None
        if run_id.startswith("ideas-rewrite-"):
            return rewrite_out, None
        return gen_outputs.pop(0), None

    mod._hermes_submit_run = fake_submit
    mod._hermes_poll_run = fake_poll

    mod._run_generation_round("manual")
    with mod._lock:
        ideas = list(mod._db["ideas"])
        hist = list(mod._db["meta"]["ideasGen"]["history"])
    rec = hist[-1]
    check("B round lands good card + rewrite-rescued card (G2)",
          rec["produced"] == 2, f"{rec}")
    check("B dropped counted by reason",
          rec["dropped"] == 4
          and rec["droppedReasons"] == {
              "noAnchor": 2, "noAction": 0, "dupAnchor": 1,
              "noDetailAnchor": 1, "unsupported": 0,
              "other": 0}, f"{rec.get('droppedReasons')}")
    check("B exactly one rewrite attempt ran (G2)",
          submits["rewrite"] == 1, f"{submits}")
    new_cards = [i for i in ideas
                 if i["title"] == "我可以替你催办卡住的合同确认"]
    check("B stored card carries resolved anchorId",
          len(new_cards) == 1
          and new_cards[0]["anchorId"] == "K:t_blocked"
          and new_cards[0]["evidenceRef"] == "K1",
          f"{new_cards}")
    rescued = [i for i in ideas
               if i["title"] == "我可以把发言原稿做成婚礼当天包"]
    check("B rescued card stored with its anchor (G2)",
          len(rescued) == 1
          and rescued[0]["anchorId"] == "R:mem_wed"
          and "确认后不再改动" in rescued[0]["detail"],
          f"{rescued}")
    check("B no material notes when all sources read fine",
          "materialNotes" not in rec, f"{rec}")
    prompt = prompts.get("gen", "")
    check("B material carries S digest, not just titles",
          "摘要：谈了婚礼发言" in prompt)
    check("B material excludes cron/probe/old sessions",
          "定时任务会话" not in prompt
          and "探针会话" not in prompt
          and "旧会话" not in prompt)
    check("B material carries G entries + briefing",
          "发言稿已定稿" in prompt and "婚礼筹备周报" in prompt)
    check("B material carries K signals",
          "卡住" in prompt and "长期未动 10 天" in prompt)
    check("B material excludes done tasks entirely (B2, "
          "2026-11-24: no 已完成待收尾 signal, no done title)",
          "已完成待收尾" not in prompt
          and "场地定金缴纳" not in prompt)
    check("B material carries R excerpt, drops stale memory",
          "婚礼发言定稿" in prompt and "某次旧备份" not in prompt)
    check("B material marks tooGeneric dismissals",
          "〔太泛〕" in prompt)
    check("B material carries C calendar line (ID-1)",
          "近期日程" in prompt and "《婚礼彩排》" in prompt
          and "地点：土基镇西故现村" in prompt)

    mod._run_generation_round("manual")
    with mod._lock:
        hist = list(mod._db["meta"]["ideasGen"]["history"])
    rec2 = hist[-1]
    check("B digest cache: no second digest run",
          submits["sum"] == 1, f"{submits}")
    check("B second round: same card dropped as dup anchor/title",
          rec2["produced"] == 0
          and rec2["droppedReasons"].get("dupAnchor", 0) >= 1,
          f"{rec2}")


def main():
    phase_a()
    phase_b()
    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
