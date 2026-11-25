#!/usr/bin/env python3
"""settings_registry 契约自检（hermes-deploy 1.17.0 预制，S5-01/S5-02）。

防的是五面轮审 S5-01 那一跤：生产种子 surface 带 `settings.` 前缀，
App 合并引擎判据是无前缀 SettingsGroupID.rawValue，生产每组有效记录
恒 0、设置根页 100% 回落内置，而 §437 的 App 侧 fixture 用无前缀形态
故测试全绿、生产从未点亮。本脚本在服务端复刻 App 判据
（rel-05107 树 Sources/OneDayCore/SettingsRegistry.swift 的
validRecords：surface == group.rawValue；目的地记录须按 id 锚回本组
内置条目并按 destination 去重；值记录须 type/key/title 齐备并按 key
去重），对两份材料跑同一判据：

- fixtures/registry-production-form.json（生产形态：基线模块
  get_registry() 输出，即生产 GET /v1/settings/registry 的实际响应
  形状）——断言五组有效数全 0，证明本检能抓住 S5-01 的失败签名；
- 本包新种子——断言五组有效数与预期逐组相等（形态再漂移即红）。

外加字段守恒机检：新种子相对生产基线，只许 surface 去前缀、
§450 登记的 5 条改名、4 条 shows_in_browse 关、删 serverSessions
一条，其余字段逐字一致、记录序不变、key 与值语义零改动。

跑法：python3 settings_registry_contract_selftest.py，全过回 0。
"""

import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
os.environ["SETTINGS_REGISTRY_DIR"] = str(
    Path(tempfile.mkdtemp(prefix="settings-contract-")) / "nope")

FAILURES = []


def check(name, cond, detail=""):
    if cond:
        print(f"  ok {name}")
    else:
        print(f"FAIL {name} {detail}")
        FAILURES.append(name)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


base = load("baseline_sr", HERE / "baseline" / "settings_registry.py")
new = load("new_sr", HERE / "patches" / "settings_registry.py")

# ------------------------------------------- App 判据等价复刻（validRecords）
# 内置条目锚表：rel-05107 树 SettingsCatalog.swift（§450 已应用态：
# serverSessions 内置条目已删），destination id -> group rawValue。
# 基准转录自包内 settings_registry_selftest.py 的 rel-05104 清点表，
# 按 §450 App 侧同批变更删 serverSessions 一行。
GROUPS = ["top", "agent", "serverAndWorkspace", "preferences", "support"]
ANCHORS = {
    "identity": "top",
    "models": "agent", "profiles": "agent", "memory": "agent",
    "skills": "agent", "toolsets": "agent", "delegation": "agent",
    "cron": "agent",
    "server": "serverAndWorkspace", "addDevice": "serverAndWorkspace",
    "pairing": "serverAndWorkspace", "gateway": "serverAndWorkspace",
    "logs": "serverAndWorkspace", "usage": "serverAndWorkspace",
    "connectionSelfCheck": "serverAndWorkspace",
    "mainSession": "serverAndWorkspace", "status": "serverAndWorkspace",
    "computer": "serverAndWorkspace", "serverFiles": "serverAndWorkspace",
    "envVars": "serverAndWorkspace", "healthCheck": "serverAndWorkspace",
    "disconnect": "serverAndWorkspace",
    "appearance": "preferences", "voice": "preferences",
    "notifications": "preferences", "connectors": "preferences",
    "devicePermissions": "preferences", "approvalRules": "preferences",
    "help": "support", "about": "support", "privacy": "support",
    "terms": "support", "chatDiagnostics": "support",
    "crashReports": "support",
}


def valid_records(records, group):
    """SettingsRegistry.swift validRecords 的记录级等价实现。"""
    seen_dest, seen_keys, picked = set(), set(), []
    for rec in records:
        if rec.get("surface") != group:
            continue
        dest = rec.get("destination")
        if dest is not None:
            if ANCHORS.get(dest) != group or dest in seen_dest:
                continue
            seen_dest.add(dest)
            picked.append(rec)
        else:
            if not rec.get("type") or not rec.get("key") \
                    or not rec.get("title"):
                continue
            if rec["key"] in seen_keys:
                continue
            seen_keys.add(rec["key"])
            picked.append(rec)
    return picked


# ------------------------------------------- 1) 生产形态：必须判出全 0
fixture = json.loads(
    (HERE / "fixtures" / "registry-production-form.json").read_text(
        encoding="utf-8"))
prod_records = fixture["response"]["records"]
check("fixture-count", len(prod_records) == 44,
      f"(got {len(prod_records)})")
check("fixture-is-prefixed-form",
      sum(1 for r in prod_records
          if str(r.get("surface", "")).startswith("settings.")) == 38)
for g in GROUPS:
    check(f"fixture-group-{g}-zero", valid_records(prod_records, g) == [],
          f"(got {len(valid_records(prod_records, g))})")

# ------------------------------------------- 2) 新种子：五组逐组对数
seed = new.seed_records()
check("new-count", len(seed) == 43, f"(got {len(seed)})")
check("new-version", new.SEED_VERSION == 4)
check("new-validate", new.validate_records(seed) == [],
      str(new.validate_records(seed)[:3]))
check("new-no-prefixed-surface",
      not any(str(r.get("surface", "")).startswith("settings.")
              for r in seed))
EXPECTED = {"top": 1, "agent": 7, "serverAndWorkspace": 14,
            "preferences": 6, "support": 6}
for g in GROUPS:
    got = valid_records(seed, g)
    check(f"new-group-{g}", len(got) == EXPECTED[g],
          f"(got {len(got)}, want {EXPECTED[g]})")
reg = new.get_registry()
check("new-registry-shape", reg["version"] == 4
      and len(reg["records"]) == 43
      and all("value" in r for r in reg["records"]))
# 种子 v4（包 1.22.0，设置目标树落码）：三条 config-backed 记录
# surface 改离 agent -> machine，退出一切浏览组、只留机器消费面。
SURFACE_OFF = {"platform_toolsets.api_server", "memory.write_approval",
               "skills.write_approval"}
for key in SURFACE_OFF:
    rec = next(r for r in seed if r["key"] == key)
    check(f"surface-off-{key}", rec["surface"] == "machine",
          str(rec.get("surface")))
    check(f"surface-off-{key}-not-browsable",
          all(rec not in valid_records(seed, g) for g in GROUPS))

# ------------------------------------------- 3) 字段守恒（对生产基线）
RENAMES = {
    "settings.entry.profiles": "档案",
    "settings.entry.toolsets": "工具",
    "settings.entry.delegation": "任务委派",
    "settings.entry.pairing": "设备配对",
    "settings.entry.mainSession": "主线对话",
}
BROWSE_OFF = {"settings.entry.addDevice", "settings.entry.pairing",
              "settings.entry.logs", "settings.entry.connectionSelfCheck",
              # batch 3 ride-along (section-470 server tail): the
              # three pure-status entries leave browse, search-only
              "settings.entry.usage", "settings.entry.mainSession",
              "settings.entry.status"}
DELETED = {"settings.entry.serverSessions"}

bseed = base.seed_records()
bmap = {r["key"]: r for r in bseed}
nmap = {r["key"]: r for r in seed}
check("keyset-delta", set(nmap) == set(bmap) - DELETED,
      str(set(nmap) ^ (set(bmap) - DELETED)))
check("order-preserved",
      [r["key"] for r in seed]
      == [r["key"] for r in bseed if r["key"] not in DELETED])
problems = []
for key, nrec in nmap.items():
    brec = bmap[key]
    for field in set(brec) | set(nrec):
        bv, nv = brec.get(field), nrec.get(field)
        if bv == nv:
            continue
        if field == "surface" and bv == f"settings.{nv}":
            continue
        if field == "surface" and key in SURFACE_OFF \
                and bv == "settings.agent" and nv == "machine":
            continue
        if field == "title" and RENAMES.get(key) == nv:
            continue
        if field == "shows_in_browse" and key in BROWSE_OFF \
                and bv is True and nv is False:
            continue
        problems.append(f"{key}.{field}: {bv!r} -> {nv!r}")
check("field-conservation", problems == [], "; ".join(problems[:5]))
for key, title in RENAMES.items():
    check(f"rename-{key}", nmap[key]["title"] == title)
for key in BROWSE_OFF:
    check(f"browse-off-{key}", nmap[key]["shows_in_browse"] is False)
check("deleted-absent", "settings.entry.serverSessions" not in nmap)
# chat / hub 两面从未带前缀，必须逐字未动
for key in ("display.agent_self_reactions", "hub.surface.work",
            "hub.surface.audit", "hub.surface.identity",
            "hub.surface.computer", "hub.surface.mail"):
    check(f"untouched-{key}", nmap[key] == bmap[key])

print()
if FAILURES:
    print(f"CONTRACT SELFTEST FAILED: {len(FAILURES)} 项: {FAILURES}")
    sys.exit(1)
print("CONTRACT SELFTEST PASSED (生产形态判红签名成立、新种子五组全亮、字段守恒)")
