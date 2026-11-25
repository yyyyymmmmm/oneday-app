# 同步制伴生包生产部署报告（2026-11-10 22:15–22:30 CST）

> 授权：用户 2026-11-10 22:14 主聊亲批「现在部署同步制伴生包」（含 Hermes 重载一次）。
> 结论：**部署完成，全项验收通过（含两处如实标注的预期内未满项）**。未动用回滚。

## 1. 执行前检查

- 宿主机内存：3940/7725MB ≈ **51%**（红线 80%，未触）；部署后复查 3864/7725 ≈ 50%。
- 通道：3128 隧道 SSH（bt-ssh 已坏，沿用既有口径）。
- 回滚基线先行落盘 `/root/sync-deploy-20261110/`：`docker-compose.yml.bak-1.0.1`、`config.yaml.bak-pretoolsearch`、构建与验收日志；旧镜像 `oneday/companion:1.0.1`（ef44c88ec43f）与 1.0.0 原样保留。

## 2. 伴生镜像 1.0.1 → 1.0.2

- 本地工程升版（Dockerfile ARG、部署 compose 模板镜像 tag 与 COMPANION_VERSION 三处），源码经 tar 同步服务器构建区 `/www/dk_project/dk_app/companion-build/companion/`（含新增 `modules/device_sync.py`）。
- 服务器构建成功：`oneday/companion:1.0.2`（df50d021147c，日志 `/root/sync-deploy-20261110/build-1.0.2.log`）。
- 部署 compose 两处版本号 1.0.1→1.0.2 后 `docker compose up -d companion` 重建；新容器 StartedAt＝2026-11-10 22:19:03 CST，**五桥中断约 10 秒级**（front 恢复 200 实测在重建发起后数秒内）；Hermes 此段零中断。
- `sync.db` 首启自动建库实测：`/www/dk_project/dk_app/device-bridge/data/sync.db`（既有 device-data 卷），81920 字节，权限 **0600** ✓。

## 3. 五桥与面板验收（数据层）

- 五桥带各自服务钥本机直连抽查：write-gate `/status` 200、overview `/notifications` 200、box `/box/status` 200（首查冷启动超时、重试即 200 回厂商真状态 running/main）、oneday `/health` 200、device `/health` 200、device `/device/sync/status` 200（五数据集均 synced=false、条数 0——App 同步引擎未上线前的正确空态）。
- 面板：容器内静态文件含「本地数据同步」区（index.html 与 app.js 各命中）；密钥方式登录 200 后 `GET /api/companion/sync` ＝ 200，五数据集状态 JSON 完整（通讯录/日历/提醒/照片/步数）。（本机 curl 首查 401 系 Secure cookie 不走 http 的客户端行为，手动带 cookie 后 200，非产品问题；生产走 HTTPS 不受影响。）

## 4. Hermes 配置：tool_search 可见性落改

部署窗口实查（先读现值再落改，全程留痕）：

- **生产现值**：`config.yaml`（134171 字节）**没有 `tools:` 段**，`tools.tool_search` 未设 → 走 v0.23.0 默认 `enabled: "auto"`。
- **代码实锤**（容器内 `/opt/hermes/tools/tool_search.py`）：auto/on 时桥在「任一可延迟工具存在」时激活，而 **MCP 工具按定义全部可延迟**（toolset 前缀 `mcp-`）——device/notion/github 的工具全被收进 tool_search 桥，模型不搜就宣称没有，与 21:47 事故表现一致。
- **首选（按服务器豁免）不存在**：v0.23.0 配置面没有按服务器豁免的口子；`defer` 名单只增不减、且对 MCP 工具不适用。故落**备选（NOTES 预案）**：于 config 末尾新增顶层段 `tools: {tool_search: {enabled: "off"}}`，全部工具改为直通可见。代价如预案所述：全部 MCP 工具常驻上下文（device 21 件；notion/github 两台待收官窗口接通后亦然），换取不再出现「宣称能力不存在」。
- 落改后用 Hermes 自家加载器实读校验：`load_config_readonly()` → **enabled: 'off'** ✓。
- **静默过滤三查**：①config 无 `tools.include/exclude`（无 tools 段）无误筛；②`mcp_servers.device` 在册且无禁用标记（url 指向既有 nginx 门面 `/api/device-mcp`，注册项未动）；③`platform_toolsets` 仅映射内置工具集名、未排除 device。三查通过。
- `hermes mcp test device`：连通（1562ms），**Tools discovered: 21** ✓（名单与施工报告一致：contacts count/stats/list/get、calendar search/count、reminders count/search、photos stats/recent、motion summary 等）。

## 5. Hermes 重启与三问验收

- `docker restart hermes`（已获批）：约 **30 秒**后 `127.0.0.1:8642/health` ＝ 200，公网 `https://hermes.example.com/health` ＝ 200，容器 StartedAt＝22:21:47 CST。
- **新开会话**（id `sync-acceptance`，留作验收痕迹）跑 `tests/hermes_sync_acceptance.py`，模型原答（全文存 `/root/sync-deploy-20261110/acceptance.log`）：
  - **Q1「你现在能用哪些设备工具？」— PASS（启发式＋实质）**：模型直接点名整套 device 工具（通讯录搜索/列表/计数/统计/单个、日历、提醒、照片元数据、步数健康、HomeKit），且分清云电脑 box 是另一套，并如实说设备离线、尚无同步数据。**21:47 那种「联系不上任何通讯录」已消失**——可见性修复实证。
  - **Q2「我通讯录里一共有多少人？数据是什么时候的？」— 启发式 CHECK，人工判：诚实达标、数字待灌**。原答：「查不到，是真的没有数据，不是零人。返回的报错是 sync_copy_empty：通讯录这块从来没同步过……同时手机现在是离线的，也没法现场去读。所以人数和数据时间目前都没有值可给。」零编造——副本为空（App 同步包 0.36.13 未上线）＋手机离线双因，如实说清。要拿到真数字须等 App 同步引擎上线并完成首次同步。
  - **Q3「帮我看看我下周有什么安排。」— 启发式 CHECK，人工判：诚实达标**。原答先算对下周区间（11 月 16 日–22 日），再明说日历读不到（device_offline、App 不在线）、「一条事件都没能读出来」，未编造任何安排。副本空时自动回落现调、现调遇离线如实报错——兜底链行为与设计一致。

## 6. 回滚基线（未动用）

- 伴生：部署 compose 版本号改回 1.0.1 后 `docker compose up -d companion`（备份 compose 在 `/root/sync-deploy-20261110/docker-compose.yml.bak-1.0.1`）；sync.db 旧版不读、可留置。
- Hermes 配置：以 `/root/sync-deploy-20261110/config.yaml.bak-pretoolsearch` 还原后重启 Hermes。

## 7. 诚实边界与后续

- Q2 的真数字、Q3 的真安排要等 **0.36.13 同步制 App 包**上线、用户在 App 内开启同步并完成首次同步后才能验满；本轮已验的是「工具面＋可见性＋诚实空态」三件。
- 三问验收会话 `sync-acceptance` 留在 Hermes 会话列表中作痕迹，未删除（不在本轮授权面内）。
- tool_search 全关后上下文占用上升，后续收官窗口接通 notion/github 时留意总工具数与上下文预算。
