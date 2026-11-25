#!/usr/bin/env python3
"""settings_registry 自测（包 1.11.0，DESIGN §435 一期；
1.17.0 更新：种子 v2——surface 去前缀对齐 App 判据＋§450 增量，
断言基准同步 rel-05107 §450 已应用态，见 hermes-deploy-settingsfix）。

在隔离临时目录里对 patches/settings_registry.py 做行为级自测，并对
api_server.py 的接线做结构断言（一期硬验收：端点只读、无写路径）：

- 种子 v1 与现行设置面逐项对账：35 个 SettingsCatalog 目的地
  （rel-05104 树 SettingsCatalog.swift，2026-11-24 清点，本脚本内
  独立转录一份作对账基准）、4 个已知服务端键的默认值与 config 落点、
  中枢五格 surface 记录（3 活 2 待）。
- 快照覆盖层语义：只许载 value 与新记录，种子元数据保持权威；
  畸形快照回落种子不抛错。
- 只读结构：模块源码无任何写原语；api_server 只挂 GET 路由、
  handler 挂 @_require_auth、无写方法指向该路径。

本脚本随包走，应用前在本机或部署机跑：
python3 settings_registry_selftest.py，全过回 0。
"""

import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(tempfile.mkdtemp(prefix="settings-registry-selftest-"))
os.environ["SETTINGS_REGISTRY_DIR"] = str(ROOT / "settings")

PKG = Path(__file__).parent
sys.path.insert(0, str(PKG / "patches"))
import settings_registry as sr  # noqa: E402

FAILURES = []


def check(name, cond, detail=""):
    if cond:
        print(f"  ok {name}")
    else:
        print(f"FAIL {name} {detail}")
        FAILURES.append(name)


# ------------------------------------------------------------ 种子结构
seed = sr.seed_records()
check("seed-count", len(seed) == 43, f"(got {len(seed)})")
check("seed-version", sr.SEED_VERSION == 4)
check("seed-valid", sr.validate_records(seed) == [],
      str(sr.validate_records(seed)[:3]))
by_key = {r["key"]: r for r in seed}
check("seed-keys-unique", len(by_key) == len(seed))

# ------------------------------------------------- 与 SettingsCatalog 对账
# 独立转录基准：rel-05107 树 Sources/OneDayCore/SettingsCatalog.swift
# (id, group, title, showsInBrowse)，2026-11-24 清点（§450 已应用态：
# 改名 5／browse 关 4／serverSessions 条目已删）。
CATALOG = [
    ("identity", "top", "形象与名称", False),
    ("models", "agent", "模型与服务商", True),
    ("profiles", "agent", "档案", True),
    ("memory", "agent", "记忆", True),
    ("skills", "agent", "技能", True),
    ("toolsets", "agent", "工具", True),
    ("delegation", "agent", "任务委派", True),
    ("cron", "agent", "定时任务", True),
    ("server", "serverAndWorkspace", "当前服务器", True),
    ("addDevice", "serverAndWorkspace", "添加设备", False),
    ("pairing", "serverAndWorkspace", "设备配对", False),
    ("gateway", "serverAndWorkspace", "网关状态", True),
    ("logs", "serverAndWorkspace", "日志", False),
    ("usage", "serverAndWorkspace", "用量", False),
    ("connectionSelfCheck", "serverAndWorkspace", "连接自检", False),
    ("mainSession", "serverAndWorkspace", "主线对话", False),
    ("status", "serverAndWorkspace", "状态", False),
    ("computer", "serverAndWorkspace", "电脑", True),
    ("serverFiles", "serverAndWorkspace", "服务器文件", True),
    ("envVars", "serverAndWorkspace", "密钥", True),
    ("healthCheck", "serverAndWorkspace", "体检与存档", True),
    ("disconnect", "serverAndWorkspace", "断开连接", False),
    ("appearance", "preferences", "外观", True),
    ("voice", "preferences", "语音", True),
    ("notifications", "preferences", "通知", True),
    ("connectors", "preferences", "连接器", True),
    ("devicePermissions", "preferences", "设备与权限", True),
    ("approvalRules", "preferences", "审批规则", True),
    ("help", "support", "帮助与反馈", True),
    ("about", "support", "关于 OneDay", True),
    ("privacy", "support", "隐私政策", False),
    ("terms", "support", "用户协议", False),
    ("chatDiagnostics", "support", "聊天诊断", False),
    ("crashReports", "support", "崩溃报告", False),
]
check("catalog-count", len(CATALOG) == 34)
entry_keys = {k for k in by_key if k.startswith("settings.entry.")}
check("entry-keyset", entry_keys ==
      {f"settings.entry.{c[0]}" for c in CATALOG},
      str(entry_keys ^ {f"settings.entry.{c[0]}" for c in CATALOG}))
for eid, group, title, browse in CATALOG:
    rec = by_key[f"settings.entry.{eid}"]
    check(f"entry-{eid}", rec["type"] == "entry"
          and rec["surface"] == group
          and rec["title"] == title
          and rec["destination"] == eid
          and rec["shows_in_browse"] is browse
          and rec["source"] == "app_local"
          and rec["default"] is None,
          str(rec))

# ------------------------------------------------------- 服务端键对账
r = by_key["display.agent_self_reactions"]
check("key-self-reactions", r["type"] == "bool" and r["default"] is False
      and r["config_path"] == "display.agent_self_reactions"
      and r["capability"] == "features.self_reactions"
      and r["source"] == "config", str(r))
for k in ("memory.write_approval", "skills.write_approval"):
    r = by_key[k]
    check(f"key-{k}", r["type"] == "bool" and r["default"] is True
          and r["config_path"] == k and r["source"] == "config"
          and r["writable_by"] == "user"
          and r["surface"] == "machine", str(r))
r = by_key["platform_toolsets.api_server"]
check("key-toolsets", r["config_path"] == "platform_toolsets.api_server"
      and r["source"] == "config"
      and r["surface"] == "machine", str(r))

# --------------------------------------------------------- 中枢五格对账
surfaces = [r for r in seed if r["type"] == "surface"]
check("surface-count", len(surfaces) == 5, f"(got {len(surfaces)})")
check("surface-keys", [r["key"] for r in surfaces] == [
    "hub.surface.work", "hub.surface.audit", "hub.surface.identity",
    "hub.surface.computer", "hub.surface.mail"],
    str([r["key"] for r in surfaces]))
act = {r["key"]: r["activation"] for r in surfaces}
check("surface-activation",
      act["hub.surface.work"] == "live"
      and act["hub.surface.audit"] == "live"
      and act["hub.surface.identity"] == "live"
      and act["hub.surface.computer"] == "pending"
      and act["hub.surface.mail"] == "pending", str(act))

# ------------------------------------------------------------ 读路径
reg = sr.get_registry()
check("registry-shape", reg["object"] == "settings.registry"
      and reg["version"] == sr.SEED_VERSION
      and len(reg["records"]) == 43)
check("registry-values-resolved",
      all("value" in r and r["value"] == r["default"]
          for r in reg["records"]))

# ------------------------------------------------------------ 覆盖层
snap_dir = ROOT / "settings"
snap_dir.mkdir(parents=True)
overlay = {"records": [
    {"key": "display.agent_self_reactions", "value": True,
     "type": "string"},  # 试图改种子元数据：必须被无视
    {"key": "test.extra", "type": "bool", "default": False,
     "surface": "agent", "owner": "agent",
     "writable_by": "agent", "validation": {"kind": "bool"},
     "capability": None, "reversible": True, "value": True},
]}
(snap_dir / "registry.json").write_text(
    json.dumps(overlay), encoding="utf-8")
reg2 = sr.get_registry()
m = {r["key"]: r for r in reg2["records"]}
check("overlay-count", len(reg2["records"]) == 44)
check("overlay-value", m["display.agent_self_reactions"]["value"] is True)
check("overlay-seed-meta-authoritative",
      m["display.agent_self_reactions"]["type"] == "bool"
      and m["display.agent_self_reactions"]["default"] is False)
check("overlay-extra-appended",
      reg2["records"][-1]["key"] == "test.extra"
      and m["test.extra"]["value"] is True)
check("overlay-seed-untouched",
      by_key["display.agent_self_reactions"]["default"] is False)

# ------------------------------------------------------- 畸形快照回落
(snap_dir / "registry.json").write_text("{not json", encoding="utf-8")
reg3 = sr.get_registry()
check("malformed-snapshot-fallback", len(reg3["records"]) == 43
      and all(r["value"] == r["default"] for r in reg3["records"]))

# ------------------------------------------------------- 只读结构断言
src = (PKG / "patches" / "settings_registry.py").read_text(encoding="utf-8")
for token in ("write_text", ".write(", "os.replace", "json.dump",
              "os.remove", "unlink"):
    check(f"module-no-write-{token}", token not in src)
import inspect  # noqa: E402
fns = [n for n, _ in inspect.getmembers(sr, inspect.isfunction)]
bad_fns = [n for n in fns if n.startswith(
    ("set_", "register_", "delete_", "update_", "save_", "append_",
     "write_"))]
check("module-no-write-functions", bad_fns == [], str(bad_fns))

api_src = (PKG / "patches" / "api_server.py").read_text(encoding="utf-8")
check("api-route-get-only",
      api_src.count('"/v1/settings/registry"') == 2  # 路由表 + 能力端点表
      and '("GET", "/v1/settings/registry", self._handle_settings_registry)'
      in api_src)
for method in ("POST", "PUT", "DELETE", "PATCH"):
    check(f"api-no-{method.lower()}-route",
          f'("{method}", "/v1/settings/registry"' not in api_src)
check("api-feature-flag", '"settings_registry": True' in api_src)
hpos = api_src.index("async def _handle_settings_registry")
check("api-handler-require-auth",
      "@_require_auth" in api_src[max(0, hpos - 200):hpos])

print()
if FAILURES:
    print(f"SELFTEST FAILED: {len(FAILURES)} 项: {FAILURES}")
    sys.exit(1)
print("SELFTEST PASSED (全部行为断言通过)")
