#!/usr/bin/env python3
"""hub_fields_selftest.py -- hermes-deploy 1.23.0 中枢数据四件包内自测。

覆盖:
  1. 台账 summary 结算链: App 终态上报带 summary -> item_view 通传;
     事件账回放后仍在; 无 summary 上报 -> 字段为空; 终态纠正带新
     summary -> 覆写; derive_activity_summary / clean_summary 口径。
  2. 写闸 _structured_fields: memory batch 提取 op_count/op_kinds/
     content_preview/mem_target; memory 单条 add/patch/remove 不回归;
     skills batch 不回归。
  3. 决策台账 title_human 派生与事件回放；cron 全量列表 is_system 投影。

跑法: python3 hub_fields_selftest.py (退出码 0 = 全过)
"""
import importlib.util
import json
import sys
import tempfile
import time
from pathlib import Path

PKG = Path(__file__).resolve().parent
FAILS = []


def check(name, cond, extra=""):
    if cond:
        print(f"  ok {name}")
    else:
        print(f"  FAIL {name} {extra}")
        FAILS.append(name)


def load(mod_name, rel):
    spec = importlib.util.spec_from_file_location(mod_name, PKG / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


print("== ledger summary ==")
led = load("oneday_ledger_lib", "patches/oneday_ledger_lib.py")

# derive / clean 口径
check("derive verb+object",
      led.derive_activity_summary("web_search", "西安天气")
      == "搜索 西安天气")
long_obj = "x" * 50
out = led.derive_activity_summary("read_file", long_obj)
check("derive object cap 30", out == "读取 " + "x" * 30 + "…", out)
check("derive verb only",
      led.derive_activity_summary("web_search", "") == "搜索")
check("derive preview only",
      led.derive_activity_summary("mcp_tool_x", "某对象") == "某对象")
check("derive empty", led.derive_activity_summary("", "") == "")
check("derive ws collapse",
      led.derive_activity_summary("terminal", "ls  -la\n/tmp")
      == "运行 ls -la /tmp")
check("clean cap", len(led.clean_summary("a " * 200)) <= 120)
check("clean empty", led.clean_summary(None) == "")

tmp = Path(tempfile.mkdtemp())
store = led.LedgerStore(tmp / "ledger-events.jsonl")
now = time.time()

# start + terminal with App summary
led.apply_app_report(store, {
    "runId": "run_t1", "sessionId": "s1", "titleSeed": "测试一",
    "startedAt": now - 5})
item, _ = led.apply_app_report(store, {
    "runId": "run_t1", "terminal": "completed", "endedAt": now,
    "summary": "搜索 西安天气"})
view = led.item_view(item, detail=True)
check("app summary stored", view.get("summary") == "搜索 西安天气",
      repr(view.get("summary")))
lst = led.item_view(item)
check("app summary in list view", lst.get("summary") == "搜索 西安天气")

# terminal without summary -> stays empty
led.apply_app_report(store, {
    "runId": "run_t2", "startedAt": now - 5})
item2, _ = led.apply_app_report(store, {
    "runId": "run_t2", "terminal": "completed", "endedAt": now})
check("no summary stays empty", not item2.get("summary"),
      repr(item2.get("summary")))

# server-derived summary lands through the same field
derived = led.derive_activity_summary("read_file", "/opt/data/SOUL.md")
led.apply_app_report(store, {
    "runId": "run_t3", "startedAt": now - 5})
item3, _ = led.apply_app_report(store, {
    "runId": "run_t3", "terminal": "failed", "endedAt": now,
    "error": "boom", "summary": derived})
check("derived summary stored",
      item3.get("summary") == "读取 /opt/data/SOUL.md",
      repr(item3.get("summary")))

# correction: completed -> failed with a new summary overwrites
store.set_status("run:run_t1", "failed", by="app",
                 fail_reason={"category": "原因未明"},
                 summary="运行 后置校验")
check("correction summary overwrite",
      store.get("run:run_t1").get("summary") == "运行 后置校验")

# replay from the event log: summary survives
store2 = led.LedgerStore(tmp / "ledger-events.jsonl")
check("replay keeps summary",
      store2.get("run:run_t1").get("summary") == "运行 后置校验")
check("replay keeps derived",
      store2.get("run:run_t3").get("summary")
      == "读取 /opt/data/SOUL.md")

# Structured decision facts create a separate human title. The legacy title
# remains the same truncated excerpt, while the object name stays complete.
long_name = "OneDay 的聊天页文件" + "-" * 48
decision_path = tmp / "decisions.jsonl"
decision_path.write_text(json.dumps({
    "id": "decision-human-title", "decision": "approved",
    "summary": "batch(1 ops: patch) on " + long_name,
    "op": "patch", "op_kinds": ["patch"],
    "target_name": long_name, "created_at": now - 1,
    "decided_at": now,
}, ensure_ascii=False) + "\n", encoding="utf-8")
decision_store = led.LedgerStore(tmp / "decision-ledger.jsonl")
collector = led.Collector(decision_store, decisions_path=decision_path,
                          now_fn=lambda: now)
collector.cycle()
decision = decision_store.get("appr:decision-human-title")
check("approval title_human keeps long object",
      decision.get("title_human") == "修改了 " + long_name,
      repr(decision.get("title_human")))
check("title_human reaches list projection",
      led.item_view(decision).get("title_human") == "修改了 " + long_name)
check("legacy approval title still excerpt",
      decision.get("title").endswith("…")
      and len(decision.get("title")) == 31, repr(decision.get("title")))
decision_replay = led.LedgerStore(tmp / "decision-ledger.jsonl")
check("title_human survives ledger replay",
      decision_replay.get("appr:decision-human-title").get("title_human")
      == "修改了 " + long_name)

print("== write-gate structured fields ==")
wg = load("write_gate_gateway", "patches/write_gate_gateway.py")
sf = wg._structured_fields

batch = {"action": "batch", "payload": {
    "action": "batch", "target": "user",
    "operations": [
        {"action": "add", "content": "位于西安，使用天然气服务"},
        {"action": "add", "content": "使用iCost记账"},
        {"action": "remove", "old_text": "旧条目"},
    ]}}
out = sf("memory", batch)
check("batch op_count", out.get("op_count") == 3, repr(out))
check("batch op_kinds",
      out.get("op_kinds") == ["add", "add", "remove"], repr(out))
check("batch mem_target", out.get("mem_target") == "user")
check("batch content_preview",
      out.get("content_preview") == "位于西安，使用天然气服务",
      repr(out.get("content_preview")))

single = {"action": "add", "payload": {
    "action": "add", "target": "memory", "content": "一条新记忆"}}
out = sf("memory", single)
check("single add preview", out.get("content_preview") == "一条新记忆")
check("single add no op_count", "op_count" not in out)

patch = {"action": "patch", "payload": {
    "action": "patch", "target": "memory", "new_text": "改后的文本",
    "old_text": "原文"}}
out = sf("memory", patch)
check("single patch preview", out.get("content_preview") == "改后的文本",
      repr(out))

rem = {"action": "remove", "payload": {
    "action": "remove", "target": "user", "old_text": "要删的"}}
out = sf("memory", rem)
check("single remove preview", out.get("content_preview") == "要删的")

sk = {"action": "batch", "payload": {
    "action": "batch", "name": "s",
    "operations": [{"action": "patch"}, {"action": "create"}]}}
out = sf("skills", sk)
check("skills batch unchanged",
      out.get("op_count") == 2
      and out.get("op_kinds") == ["patch", "create"], repr(out))

print("== cron system projection ==")
cron_proj = load("cron_projection", "patches/cron_projection.py")
cron_names = [
    "OneDay 系统轮·动态调研 A 版",
    "OneDay 系统轮·动态调研 B 版",
    "OneDay 系统轮·动态小时评估",
    "OneDay 系统轮·点子到期清理",
    "OneDay 记忆日结",
    "OneDay 记忆周体检",
    "OneDay 目标日结提炼",
]
cron_source = ([{"name": n, "schedule": "0 8 * * *"}
                for n in cron_names]
               + [{"name": "OneDay 记忆类·月末压缩"},
                  {"name": "OneDay 目标提炼类·阶段总结"}]
               + [{"name": "用户的每日日程", "schedule": "0 9 * * *"}])
projected = cron_proj.project_jobs(cron_source)
check("known OneDay system name patterns",
      all(item["is_system"] for item in projected[:7]))
check("memory/goal family modes cover unlisted jobs",
      all(item["is_system"] for item in projected[7:9]))
check("unknown user cron remains non-system",
      projected[9]["is_system"] is False)
check("cron projection preserves source object",
      all("is_system" not in item for item in cron_source))
check("cron script source identifies system job",
      cron_proj.is_system_job({"name": "后台任务",
                               "script": "/opt/data/scripts/oneday-round-ideas.py"}))

print()
if FAILS:
    print(f"FAILED: {len(FAILS)} 项: {FAILS}")
    sys.exit(1)
print("ALL PASS")
