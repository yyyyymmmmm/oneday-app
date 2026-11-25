# 部署包骨架变更清单 — AI 自反应（1.8.0）

> 状态：**已入包（2026-11-24），待主线复核；未应用生产**。依据施工图 `~/workspace/oneday-design-review/ai-self-reaction-spec-20261124.md`（2026-11-24，含口径变更记录：attach 目标终版＝触发用户消息、工具轮硬过滤）。应用须逐次批准（RULES §1）。
> 版本判定：1.7.0 → **1.8.0**（minor：新增能力＋新补丁文件＋既有补丁修订，RULES §2）。
> 入包实况与应用前检查单见 §7。

## 1. 新增文件（2）

| 文件 | 通道 | container_path | 基线 | 内容要点 |
|---|---|---|---|---|
| `patches/react_to_message_tool.py` | MODULES 通道落地（全量补丁、同 api_server_runs 先例） | `/opt/hermes/tools/react_to_message_tool.py` | 已回读登记：`8b4a14de…7598` | 桌面 handler/schema/check 逐字保留；单一注册改归 `self_reactions`（R3 退路）、handler 按面分发、api_server 面 schema 经 dynamic override 收窄、check 合并两闸 OR＋handler 按面复查；handler 写 pending 不直写库 |
| `patches/self_reaction_pending.py` | MODULES（包自有） | `/opt/hermes/gateway/platforms/self_reaction_pending.py` | null（无上游对应物） | 进程内 pending 字典＋锁；表情盘常量单源（👍❤️🤔😂🎉👀）；put/pop/discard 接口 |

## 2. 修订文件（包内，4）

| 文件 | 变更 |
|---|---|
| `patches/api_server_runs.py` | ①`_execute_run._finish` 在 completed 终态对外可见前同步 attach：pending→**触发用户消息行** `set_message_reaction(author="agent")`（run_key 绑定校验、**工具轮硬过滤**、盘内二次校验、先读守卫防 toggle 误删、全程吞异常）②`_make_run_event_callback` 抑制 `react_to_message` 工具事件转发并标记其他工具使用（`_run_tool_use`）；sha256/diff_lines 已重算（203） |
| `patches/api_server.py` | capabilities features 增 `self_reactions: true` 一行（骨架初稿未列、入包时据实补列：features 字典在此文件）；sha256/diff_lines 已重算（701） |
| `manifest.yaml` | version → 1.8.0；新增两条目（上表）；api_server_runs 条目 provides 增 `self-reactions-attach`、api_server 条目增 `self-reactions-capability` |
| `install.sh` | MODULES 数组加 react_to_message_tool.py 与 self_reaction_pending.py 两行＋compose 挂载 specs/校验各加两行；PATCHES 的 api_server.py 与 MODULES 的 api_server_runs.py 期望哈希同步为新值 |
| `verify.sh` | WANT_SHA/CPATH/哈希回读名单同步四文件新哈希；新增 §16 三探针（见 §3） |
| `CAPABILITIES.md` | 新增 **#19 AI 自反应**：服务端依赖＝补丁 react_to_message_tool.py＋模块 self_reaction_pending.py＋补丁 api_server_runs.py（终态 attach）＋补丁 api_server.py（capabilities 位）；App 侧缺失时表现＝角标不显、开关行不出（能力探知），其余零影响 |

## 3. verify.sh 新增探针（4）

| 探针名 | 级别 | 判据 |
|---|---|---|
| self-reactions-hashes | 静态 | 三文件容器内哈希与 manifest 全合 |
| self-reactions-capability | 路由/只读 | GET /v1/capabilities → features.self_reactions == true |
| self-reactions-projection | 行为/只读 | 扫最近会话统计 author=="agent" 反应条目；命中 ≥1 = found，未命中且样本不足报「未触发」（沿 #3 探针 1.6.0 修正口径） |
| self-reactions-behavior | 写型（--with-mutating 才跑） | 一次性会话：纯聊天轮 → **触发用户消息行** agent 反应 ≤1 且 ∈ 盘；工具轮/失败轮 → 无 agent 反应；各轮正文无标记文本 |

## 4. instance config 要求（不入包，rollout 记录登记）

- `platform_toolsets.api_server` 增 `self_reactions`。
- `display.agent_self_reactions`：入包/应用时**不置**（保持关＝潜伏）；App 包出货后翻闸置 true，并跑写型探针实测一轮。

## 5. 回滚基线口径

- 应用前留 `/root/deploypkg-1.8.0-<日期>/baseline/`：api_server_runs.py 与 api_server.py 现行版＋docker-compose.yml（同 1.7.0 先例）。
- 回滚动作：撤两新文件挂载、还原 runs/api_server 两补丁、重启 hermes 容器、verify 回 1.7.0 全齐（探针数按当时口径重算）。
- 残留明示：已写入的 author="agent" 反应留在 `display_metadata` 不清理（合法反应数据；旧 App 走既有反应渲染），不为回滚动用户数据。

## 6. 施工前置验证（已完成，2026-11-24）

- R3：**双注册不可行**——容器内实测第二次同名注册被 REJECTED（registry 按 name 单键＋跨工具集 shadow 拒绝，保留 desktop_ui 原条目）。已走退路：单一注册改归 `self_reactions`＋handler 按 `HERMES_SESSION_PLATFORM` 分发；退路三点实测全通：①`resolve_toolset("self_reactions")` 经 registry-only 解析出该工具 ②生产 config 名单加 `self_reactions` 后 `_get_platform_tools` passthrough 放行 ③桌面 `resolve_toolset("desktop_ui")` 静态名单仍按名命中该工具（**无需 tui_gateway 补丁**，比原退路少一个补丁文件）。
- pending 模块 import 链实测：容器内以包内源码在进程加载 react 工具模块与 runs 模块，`gateway.platforms.self_reaction_pending` 双侧引用同一模块实例通过；attach 函数实测（happy path 落 agent 反应于用户行、工具轮丢弃、target 兜底重取）通过。
- 包内自测（本地 stub 全场景 25 项＋容器内真码 7 项）全过，明细见入包交卷。

## 7. 入包实况与应用前检查单（待主线复核）

入包实况（sha256）：react_to_message_tool.py `d36dafd6…b69`（上游基线 `8b4a14de…7598`、diff 137 行）；self_reaction_pending.py `705c14cf…70f`；api_server_runs.py `6328ec5f…044`（diff 135→203）；api_server.py `0664a5cf…2bb`（diff 694→701）。manifest/install/verify 三处哈希已交叉对账一致；install.sh compose 挂载插入逻辑本地假文件实测幂等。

应用前检查单（应用时逐项执行，本单不执行）：
1. 基线快照：`mkdir -p /root/deploypkg-1.8.0-<日期>/baseline`，拷入部署目录现行 `patches/api_server.py`、`patches/api_server_runs.py`、`docker-compose.yml`（install.sh 自带 .bak 备份之外再留一份整包基线，同 1.7.0 先例）。
2. 应用前内存复查（118.24.41.52 <80%）＋`DRY_RUN=1 ./install.sh <部署目录>` 先行盘点（应报：补丁 1（api_server.py）＋模块更新 1（api_server_runs.py）＋模块新建 2＋compose 挂载变更 1）。
3. instance config 两步分开：先只加 `platform_toolsets.api_server` 增 `self_reactions`（**不置** display.agent_self_reactions＝保持潜伏），随应用一并生效；翻闸是 App 出货后的独立一步，不与应用同批。
4. `./install.sh <部署目录>` 应用 → 脚本内健康检查（8642 health/9119/8643＋容器内回读哈希）全过才算落地。
5. `./verify.sh` 全量：期望 patch-hash 四文件新条目齐、self-reactions-capability 齐、self-reactions-projection 报「未触发」（闸关预期）、汇总缺 0。
6. 回滚：install.sh 失败自动回滚；人工回滚＝还原 baseline 三文件＋删两新建模块文件与对应 compose 挂载行＋重启 hermes＋verify 回 1.7.0 全齐（探针数按当时口径重算）。残留口径：已落库的 agent 反应不清理（合法数据），config 的 self_reactions 名单项可留（无补丁时解析为空、无害）或随手摘除。
