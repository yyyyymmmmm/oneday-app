# 断桥批三预制交卷 + 应用方案（包 1.13.0 候选）——只预制、未应用生产

基线事实：生产现行包 **1.10.0**（断桥批二，2026-11-24 01:55 应用，verify 齐 42／缺 0，基线 `/root/deploypkg-1.10.0-20261124/baseline/`）；部署包本体已合入 **1.11.0**（§439 记忆机制，应用线在途）；自设一期预订 **1.12.0／能力 #22**。本批变更集＝预制副本 `~/workspace/hermes-deploy-batch3/`（自本体 1.11.0 复制后增量施工），候选版本 **1.13.0**、能力 **#23（oneday 域面）／#24（overview）**、companion 镜像候选 **1.0.70**。**合并与应用序由主线终定**：若合并序调整（自设先行或本批先行），版本号/能力号按顺位顺延，变更内容不变。合并纪律同批二：只许增量叠加、严禁整文件覆盖（本批 api_server 为纯增量 +117/−0，已验）。

对象（普查图 bridge-retirement-spec-20261124 §3 行 10/11/12＋§6 批三）：companion **oneday 桥（8646）**整桥与 **overview 桥（8644）**迁入网关。批二三条经验已吸收：①改指地址按容器拓扑定（入关后调用方在 hermes 容器内，一律 `127.0.0.1:8642` 回环形态，宿主/容器名形态只留给仍在 companion 内的调用方）；②overview 的 write-gate 读路径已在网关侧（本批 overview 入关后其三源全为网关回环，不再按桥形态找 8643）；③verify 探针随退役对象同步改口径（§7 三口全改退役探针、§14 overview 静态探针改指网关模块、install 健康检查整段摘除 8643 探活——批二应用时它曾与「先停桥」冲突）。

## 一、预制交卷：变更清单（逐文件）

| 文件 | 处置 | 证据 |
|---|---|---|
| `patches/oneday_gateway.py` | **新建**：oneday 桥核心文件拆壳入关——HTTP 壳（BaseHTTPRequestHandler）换请求上下文适配（api_server 通配 handler 建上下文，模块内 `_dispatch` 总闸与全部分发器不变）；`main()` 换 `start()`（桥启动序镜像：_load→reconcile 线程→cron ensure→台账采集→交付哨兵→自动化 watcher，逐个失败隔离）＋`dispatch()` 入口；`_authed()` 改恒真（鉴权归 api_server，cron 口在总闸内先行自查回调钥）；DATA_PATH 默认改 `/opt/data/oneday/data.json`；删桥钥全局与 PORT | sha256 `bbf85cf1…3ef8`；AST 对账见 §三 |
| `patches/oneday_seg_*.py`（15 分段） | **逐字平移** companion 分段（goals/traces/goals_facade/sessions/automation/goals_activity/ideas_pool/monitors/ideas_gen/briefings/feed/ledger/delivery/filelibrary/cron），与核心同目录、由 `_load_segment` 按原序 exec 同命名空间。差异仅：print→logger 通道改名（合计 33 处）；文件头加载方注释改注 oneday_gateway.py；下列耦合改指 10 处（见 §四） | 逐文件 sha 登记于 install.sh MODULES／verify.sh WANT_SHA_EXTRA／manifest 分段条目 |
| `patches/oneday_ledger_lib.py` | **逐字节平移** companion `modules/ledger.py`（工作台账存储库，零改动）；核心以 `oneday_ledger_lib` 导入（原名 ledger） | sha256 `5a2254cd…2a41` |
| `patches/NotoSansSC-subset.ttf` | **平移** companion 字体资产（交付文字封面渲染）；包内扁平存放，install 挂到容器 `gateway/platforms/assets/`——分段 `_DELIVERY_FONT_PATH` 默认按同目录 assets/ 解析，原位命中、零 env 改动 | sha256 `695c95a1…ed6e` |
| `patches/overview_gateway.py` | **新建**：overview 桥拆壳入关（同批二 write_gate 拆壳法）——三个公开函数 `get_overview/get_notifications/mark_read` 对应桥三条路由；`start()` 幂等加载 state；三源基址全改网关回环、三把客户端钥收敛 API_SERVER_KEY（旧 env 名留作隔离测试回落）；STATE_DIR 默认改 `/opt/data/overview`；500 文案去内部细节（桥原文回异常类型＋信息，网关回「服务器内部错误」，状态码与体形不变） | sha256 `2b0c6530…be2`；AST 对账：业务函数 **0 差异** |
| `patches/api_server.py` | **增量叠加**于 1.11.0 件：能力端点表 +8 行、路由表 +18 行（oneday 通配正口/保形口各 5 方法、cron 回调口 2 行（无 `@_require_auth`、模块内自查）、overview 正口/保形口各 3 行）、handlers +6 个（`_oneday_dispatch` 共用管道＋`_handle_oneday_bridge`＋`_handle_oneday_cron_callback`＋overview 三个） | sha `e2e786d6…a8`（1.11.0）→ `ddcea876…7c9`；与本体 diff **+117/−0** 纯增量；py_compile 通过 |
| `install.sh` | MODULES +19 条（两网关模块＋台账库＋15 分段＋字体）＋注释；compose 挂载 greps/specs/写后校验各 +20（19 文件＋device-data 只读挂载行 `../device-bridge/data:/opt/device-data:ro`）；**健康检查摘除 8643 探活整段**（三桥面均退役后无 companion 探活项） | bash -n 通过；登记 sha 与包内实测三方一致（脚本自检） |
| `verify.sh` | 两张哈希表＋CPATH +19、patch-hash 回读名单 +20（含补上 oneday_memory）；**§7 改为 8643/8644/8646 三口退役探针**（8643 沿批二口径并入同节）；§14 companion-version 期望升 1.0.70、overview-notification-kinds 改查网关模块；**新增 §20**（oneday/overview 网关面 8 只读探针＋2 未验写型项） | bash -n 通过 |
| `manifest.yaml` | version →1.13.0（候选注记）；api_server 条目 sha/diff_lines 1111→1228/provides/summary 更新；新增 oneday_gateway／分段集／oneday_ledger_lib／字体／overview_gateway 五条目；hermes summary 增批三挂载注记；companion 条目升 1.0.70、ports 摘 8644/8646、summary 增批三段；data_files 增 oneday-domain-data 与 overview-state 两条 | YAML 解析通过 |
| `CAPABILITIES.md` | 新增 **#23 OneDay 域面入关**、**#24 总览聚合入关**；#7 改指网关依赖与 §20 探针；#8 更新 companion 余部（1.0.70、仅 device/identity/front＋fileproc 待命） | — |
| `companion/supervisor/modules.json` | 摘 overview、oneday 注册（模块 6→4：device／identity／front／fileproc）；桥模块文件暂留镜像内（观察窗回滚源，同批一/批二分期） | JSON 解析通过 |
| `companion/supervisor/supervisor.py` | front 钥注入名单收敛为 `("device",)`（write-gate/overview/oneday 段均已退役，注入自退役段取值本就是空操作，本批一并清理） | py_compile 通过 |
| `companion/front/front.py` | 摘 overview/oneday 的 MODULE_KEYS/MODULE_META/probe 分支/build_info 特例（同 writeGate 批二先例）；`_ledger_view` 改直调网关正口 `HERMES_BASE/v1/oneday/ledger/summary`＋HERMES_API_KEY（凭据单源）；ONEDAY_DATA_PATH 默认与 DIR_SIZES 两行改指 `/opt/data/oneday`、`/opt/data/overview`（companion 已挂 hermes 数据目录于 /opt/data，读路径不断） | py_compile 通过 |
| `companion/companion.env.example` | [overview]、[oneday] 两段改退役注记（钥作废、状态/数据迁移去向、运行参数迁 hermes env 口径） | — |
| `companion/Dockerfile`、`companion/docker-compose.yml` | COMPANION_VERSION 1.0.69→**1.0.70**；EXPOSE 与 ports 摘 8644/8646 | — |
| `services/companion-compose.template.yml`、`services/env.template` | 镜像/版本位升 1.0.70、摘 8644/8646 端口行；env 模板 overview/oneday 两段与 ONEDAY_BASE 改退役注记、overview-bridge.env 段作废注记 | — |
| `services/hermes-compose.template.yml` | hermes 服务补齐批三挂载行（两模块＋分段＋台账库＋字体＋device-data 只读挂载）与网关模块运行参数 env 块（原 [oneday] 段迁入、键名不变）；头部注记更新断桥进度 | — |
| `services/nginx-batch3-oneday-shape.conf`、`services/nginx-batch3-overview-shape.conf` | **新建**：两保形前缀改指网关 8642 模板（proxy_pass 不带 URI、Authorization 直传、整段替换现行 auth_request 换钥块） | — |
| `DEPLOYMENT-GUIDE.md` | 头部增批三注记一段，正文不动（终局改写随批五 2.0.0） | — |
| `oneday_gateway_selftest.py` | **新建**：带桩冒烟（桩 HERMES_HOME＋桩数据文件＋overview 桩源），见 §三 | 49/49 全过 |

## 二、包状态（合并后预期）

- manifest 补丁/模块条目：11 → **16**（+oneday_gateway、分段集、台账库、字体、overview_gateway）；install MODULES 9 → **28 条**；verify patch-hash 回读 11 → **31 文件**。
- verify 干跑预期（应用后）：在 1.11.0 应用后基线之上，§7 新增齐 +2（8644/8646 退役探针；8643 已在册）、§20 新增齐 +8（oneday-health/oneday-shape/oneday-goals/oneday-auth-gate/oneday-cron-callback-gate/overview/overview-shape/overview-notifications）、§14 companion-version 转绿（步 B 后）、未验 +2（oneday-cron-round-trip、oneday-delivery-register，写型默认不跑）。**具体齐数以应用时 verify-output 存档为准，出现预期外「缺」即停**（同前批口径）。

## 三、对账证据

**AST 逐函数对账**（桥源 vs 网关副本，规范化 print/_print 并剥 docstring 后逐函数比对）：
- oneday：函数集差异仅壳——桥侧独有 `main`、`Handler.log_message`；网关侧新增 `start`、`dispatch`、`Handler.__init__`、`_Headers.get`、`_print`（均为登记在案的壳件）。AST 差异函数共 **8 个，全部在登记内**：`Handler._authed/_send/_send_bytes`（壳）、`_dash_login/_dash_json`（automation，dash 基址）、`_fetch_kanban_tasks`（briefings，dash 基址）、`_LedgerDash._login/.get`（ledger，dash 基址＋分流）。模块级赋值差异仅：删 `API_KEY`/`PORT`、增 `HERMES_DASH_BASE_URL` 与启动状态位。其余全部函数（含 15 分段的生成轮、监测、台账、交付、哨兵、自动化 watcher）AST 全等。
- overview：业务函数 AST **0 差异**；差异仅壳函数（Handler/main 摘除、公开函数新增）与模块级赋值的值（基址/钥源/状态目录）。
- 对账中曾抓到并已修复一处真缺陷：feed 分段 OVERVIEW_URL 定义行被变换误吞（赋值名集对账报警），已恢复并复验。

**路由逐条对账表**：桥路由共 **63 条**（method×path）＋overview **3 条**，全部由同一 handler 挂正口＋保形口，已发货 App、Hermes MCP 注册（config.yaml 三条公网保形口）与 SOUL 交付登记纪律**零改动**。oneday 正口＝`/v1/oneday`＋桥路径，保形口＝`/api/oneday-bridge`＋桥路径（api_server 通配挂载 5 方法×2 前缀）；cron 3 条同前缀但走无网关钥 handler（模块内回调钥自查）。

| 族 | 桥路由（method path） | 条数 |
|---|---|---|
| 健康 | GET /health | 1 |
| cron 回调 | POST /internal/cron/ping、POST /internal/cron/rounds/{name}、POST /internal/cron/monitors/{id}/check | 3 |
| 留痕 | GET/POST /traces、GET /traces/{id} | 3 |
| MCP 门面 | POST /mcp、POST /mcp-sessions、POST /automation-mcp | 3 |
| 监测 | GET /monitors/notifications、GET/POST /monitors、DELETE /monitors/{id}、GET /monitors/{id}/changes、POST /monitors/{id}/check·pause·resume·read、POST /monitors/{id}/changes/{cid}/read | 10 |
| 目标深度 | POST /goals/briefings/generate、GET /goals/briefings、GET/POST /goals/{id}/entries、DELETE /goals/{id}/entries/{eid}、GET /goals/{id}/briefings、POST /goals/{id}/briefings/{bid}/opened、GET /goals/{id}/tasks、GET/POST /goals/{id}/task-links、POST /goals/{id}/delegate、PUT /tasks/{id}/goal | 11 |
| 目标/点子基本面 | GET/POST /goals、GET /goals/ungrouped-tasks、PATCH/DELETE /goals/{id}、GET/POST /ideas、POST /ideas/{id}/signal、PATCH/DELETE /ideas/{id} | 10 |
| 生成/画像 | POST /ideas/generate、GET /ideas/generation、GET/PUT /meta/brief | 4 |
| 动态 | GET /feed、POST /feed/generate、GET /feed/generation、GET/DELETE /feed/{id}、POST /feed/{id}/read·like·signal | 8 |
| 交付 | POST /deliveries、GET /deliveries/by-message、GET /deliveries/{id}、GET /deliveries/{id}/thumb、GET /deliveries/{id}/cover | 5 |
| 文件库 | GET /file-library | 1 |
| 台账 | POST /ledger/report、GET /ledger/summary、GET /ledger、GET /ledger/{id} | 4 |
| overview | GET /overview、GET /notifications、POST /notifications/{id}/read（正口 /v1/overview[/notifications[/{id}/read]]、保形口 /api/overview-bridge/*） | 3 |

**带桩冒烟**：`oneday_gateway_selftest.py` **49/49 全过**（桩 HERMES_HOME＋桩 DATA_PATH＋固定回调钥＋overview 四源桩答）：health/goals 增删读/entries/ideas/meta brief/feed/monitors/ledger/traces/deliveries 登记＋meta＋封面字节/by-message/file-library/三 MCP 门面 initialize＋tools/list/cron ping 三态（无钥 401·对钥 200·错钥 401）/404；cron ensure 在桩 dash 通道下真写四轮脚本＋回调钥文件且脚本内嵌新回调基址；overview 聚合五值（hermesUp/活跃会话 2/待批 3=2+1/未读 2=监测 1＋run 1、待批不入未读）与四类通知（born-read/born-unread）＋mark_read 全环＋state 落盘。sha 三方对账（install/verify 登记值 vs 包内实测）全一致。

## 四、差异登记（壳变换＋耦合改指全表）

壳变换（行为不变）：①Handler 改请求上下文适配（_send/_send_bytes 改记录响应，含 ETag/Cache-Control 透传）；②main→start/dispatch，删桥钥 fail-closed 门（鉴权归网关）；③print→logger 通道（核心 15＋分段 33＋overview 9 处改名，文本不变）；④overview Handler/main→三公开函数，500 文案去内部细节；⑤分段文件头加载方注释改注（仅注释）。

耦合改指（全部「默认值改、env 可覆盖」，生产由 hermes 部署 env 显式落值）：
1. **cron 回调**：`ONEDAY_CALLBACK_BASE` 默认 `http://oneday-companion:8646` → `http://127.0.0.1:8642/api/oneday-bridge`（模块全局＋生成脚本模板内嵌默认各 1 处）。脚本在 hermes 容器内运行、回环直达；ensure 每轮重写脚本与任务登记，迁移自愈。
2. **feed→overview**：`OVERVIEW_BASE` 默认 `http://127.0.0.1:8644` → `http://127.0.0.1:8642/api/overview-bridge`，钥 `OVERVIEW_BRIDGE_KEY` 改 API_SERVER_KEY 优先（feed 分段）。
3. **ledger/ideas→write-gate**：`WRITE_GATE_BASE` 默认 `http://127.0.0.1:8643` → `http://127.0.0.1:8642/api/write-gate`（批二已在网关侧，本批随模块迁入落定），钥同上收敛（ledger 分段定义、ideas_gen 共用同一全局）。
4. **overview 三源**：`HERMES_BASE` 默认 `http://hermes:8642` → `http://127.0.0.1:8642`；`WRITE_GATE_BASE` 默认（陈旧的 write-gate-bridge:8643）→ `http://127.0.0.1:8642/api/write-gate`；`ONEDAY_BASE` 默认 `http://127.0.0.1:8646` → `http://127.0.0.1:8642/api/oneday-bridge`；三把客户端钥全改 API_SERVER_KEY 优先。
5. **Dashboard 通道拆分**（本批新机制，普查图 C-3 的落地形）：新增 `HERMES_DASH_BASE_URL`（ideas_gen 定义，默认回落 HERMES_BASE_URL＝桥的单基址行为）；dash 调用点改指它——automation `_dash_login`/`_dash_json`（3 处）、briefings `_fetch_kanban_tasks`（2 处）、ledger `_LedgerDash._login`（1 处）与 `.get` 的插件面分流（/api/plugins/* 走 dash 基址、/api/sessions* 走网关基址）。生产落值：`HERMES_BASE_URL=http://127.0.0.1:8642`、`HERMES_DASH_BASE_URL=http://127.0.0.1:9119`。凭据仍为 Dashboard basic auth 同源值（HERMES_DASH_USER/PASSWORD 自部署 .env 的 HERMES_DASHBOARD_BASIC_AUTH_* 映射），**不新增凭据**；C-3 所议「服务凭据替代用户密码登录」属凭据面变更、不在预制擅动，留主线/用户裁决（现行登录通道为生产在役形态，行为保持）。
6. **数据路径**：oneday DATA_PATH 默认 → `/opt/data/oneday/data.json`（同目录账本群——deliveries.jsonl、deliveries/ 封面、delivery-sentinel.json、cron-callback-key、ledger-events.jsonl、monitor-notifications.jsonl——全部按 DATA_PATH.parent 派生，自动随迁）；overview STATE_DIR 默认 → `/opt/data/overview`；交付哨兵 DB 默认 `/opt/data/state.db` 在网关内天然成立；台账 decisions 路径默认 `/opt/data/write-gate/decisions.jsonl` 天然成立；**设备面两读路径**（DEVICE_DATA_DIR `/opt/device-data` 设备同步副本、LEDGER_DEVICE_AUDIT_PATH `/opt/device-data/audit.jsonl`）靠新增只读挂载承接（见 §六步 A）。

## 五、调用方改指清单（容器拓扑口径）

| 调用方 | 原形态 | 新形态 | 归属 |
|---|---|---|---|
| Hermes cron 脚本（4 轮＋每监测 1） | 脚本内嵌默认 `http://oneday-companion:8646`＋回调钥文件 | 网关 ensure 以新模板重写：内嵌默认 `http://127.0.0.1:8642/api/oneday-bridge`；钥文件随数据迁移承接、0644 落 scripts 目录口径不变 | 包内已落（模板）；应用步验收 ping |
| Hermes config.yaml MCP 三注册 | 公网 `https://hermes.example.com/api/oneday-bridge/mcp*`＋Bearer 登录钥 | **不变**（保形口承接、网关自验同一把钥） | 零动作 |
| 智能体交付登记（SOUL 纪律） | POST 公网 `/api/oneday-bridge/deliveries`＋登录钥 | **不变**（保形口承接） | 零动作（deliveries 前置补查结论：无登记脚本，登记即此纪律＋哨兵尾读，迁法＝保形口保住） |
| oneday feed 轮询 overview | companion 内 `127.0.0.1:8644`＋OVERVIEW_BRIDGE_KEY | 网关内 `127.0.0.1:8642/api/overview-bridge`＋API_SERVER_KEY | 包内已落（§四.2） |
| oneday ledger/ideas 读 write-gate | `127.0.0.1:8643`（批二后生产 env 已改指网关保形口） | 网关内 `127.0.0.1:8642/api/write-gate`＋API_SERVER_KEY（默认值落定，不再依赖 env 改指） | 包内已落（§四.3） |
| overview 三源 | hermes:8642／127.0.0.1:8643（env 陈旧默认 write-gate-bridge:8643）／127.0.0.1:8646＋三把桥钥 | 全 `127.0.0.1:8642` 回环（本体直口＋write-gate 保形口＋oneday 保形口）＋API_SERVER_KEY | 包内已落（§四.4） |
| oneday 各轮调 Hermes 本体 | 公网基址 `https://hermes.example.com`（/v1/runs、/api/sessions）＋Dashboard 公网同基址（/auth、/api/cron、/api/plugins） | 双回环拆分：`HERMES_BASE_URL=127.0.0.1:8642`、`HERMES_DASH_BASE_URL=127.0.0.1:9119` | 包内已落机制（§四.5）；应用步落 env |
| front 台账计数代理 | companion 内 `127.0.0.1:8646/ledger/summary`＋桥钥 | companion 内直调 `http://hermes:8642/v1/oneday/ledger/summary`＋HERMES_API_KEY（容器拓扑：front 仍在 companion，走容器名形态） | 包内已落（front.py） |
| front 数据目录/数据文件读 | /opt/oneday-data、/opt/overview-data | /opt/data/oneday、/opt/data/overview（companion 既有 /opt/data 挂载内） | 包内已落（front.py） |
| identity 桥（批四对象） | env_from 注入 ONEDAY_BRIDGE_KEY 作客户端钥 | 本批不动：批三应用删 [oneday] 段后该注入为空值——identity 对 oneday 的实际调用面在批四步 0 盘点时核清（预制期只读盘点未见 identity 模块代码内对 8646 的 HTTP 调用，风险低、列入步 0 复查） | 步 0 复查 |

## 六、凭据单源审计（批三分量）

- 两网关模块**零自有钥**：oneday_gateway 删桥钥全局、鉴权全归 api_server `@_require_auth`（API_SERVER_KEY）；overview_gateway 同。api_server 侧除 cron 回调 handler 外全部新 handler 挂 `@_require_auth`（已逐个核）。
- 唯一例外＝cron 回调钥（ONEDAY_CRON_CALLBACK_KEY／数据目录 cron-callback-key 文件）：B-01 既有契约（只开 /internal/cron/*、与登录钥分离、脚本可见面最小），入关后机制逐字保留、模块内自查、fail-closed（冒烟三态已验）。它不是第二把全包钥——普查图与批一/批二口径均将其列为回调专用钥存续，本批登记在案、不擅自变更其形态。
- 客户端钥收敛：feed→overview、ledger/ideas→write-gate、overview 三源共 5 处钥源全改 API_SERVER_KEY 优先（旧 env 名仅作隔离测试回落，生产 env 不再提供旧钥后回落为空、与未配置同效）；ideas_gen 的 HERMES_API_KEY 与 hermes 部署 env 的同名项均由部署 .env 以 API_SERVER_KEY 同值落（单源同值副本、非第二把钥，同批二口径）。
- **退役钥清单**：`ONEDAY_BRIDGE_KEY`、`OVERVIEW_BRIDGE_KEY` 随本批应用作废（删除点＝生产 companion.env [oneday]/[overview] 段，步 B；包内 env 模板已先行注记）。`ONEDAY_CRON_CALLBACK_KEY` 若生产曾显式设置，其值迁 hermes 部署 env（键名不变）；未显式设置时钥在数据文件内随迁，无动作。

## 七、应用方案

### 子批序的落地形态（先说清）

普查图把批三分为 3a 核心／3b feed·monitors＋cron／3c ledger·deliveries·file-library、overview 随 3c 后。桥与网关模块都是**单进程＋单数据文件**：分段共享同一 `_db` 与总闸，物理上不存在「半个桥在 companion、半个在网关」的稳态（双写者同写 data.json 即数据事故，普查图风险 1 明禁）。故本方案的落地形态是**一次切换、四段验收**：停桥→数据整迁→网关起→按 3a→3b→3c→overview 顺序逐段验收，前一段不过不进下一段、任一段不过按 §八整体回滚。子批序的风险隔离目的（核心先行、cron 单独实测、台账交付最后对账）由验收序完整承接。

### 基线快照（应用前，缺一不开工）

落 `/root/deploypkg-1.13.0-<日期>/baseline/`（版本号按合并终定调整）：
1. 部署目录现行 `patches/api_server.py`＋`docker-compose.yml`＋部署 `.env` 整份；
2. 线上 nginx vhost conf 整份；
3. companion 镜像现行 tag `oneday/companion:1.0.69` 保留不删＋生产 companion.env 整份＋companion-state 目录快照（supervisor 期望状态，回滚用）；
4. **oneday-data 源目录整份只读留影**（/www/dk_project/dk_app/oneday-bridge/data）＋**overview-data 源目录整份**（/www/dk_project/dk_app/hermes/overview-data）；
5. 步 0 桥侧读数记录（见下）；
6. 部署包上一版目录整份留底。

### 步 0 · 前置（只读，含停手条件）

1. 查服务器内存 <80%（118.24.41.52），超限即停。
2. 复核上一版应用后状态在位（verify-output 存档齐数与当时基线一致）；fileproc／writeGate 两观察窗状态按实况登记（与本批互不阻塞、互不改写，同批二先例）。
3. **调用方盘点**：在生产 hermes 容器 /opt/data（config.yaml、SOUL.md、skills、scripts、cron）与 companion 容器内 grep `oneday-bridge`、`overview-bridge`、`8646`、`8644`、`ONEDAY_BRIDGE_KEY`、`OVERVIEW_BRIDGE_KEY`，与 §五名单逐个对账；**发现名单外调用方即停**。逐个比对包内 companion 副本与容器内同名文件 sha256（步 B 重建镜像的安全前提，同前批先例）；identity 模块对 oneday 的调用面在此核清（见 §五末行）。
4. **桥侧读数（切换后对账基线）**：oneday GET /health（degraded、ledger items、collector lag、sentinel 状态）、/goals、/ideas、/monitors、/feed 计数、/ledger/summary 计数、cron 任务登记表（经 Dashboard 列 OneDay 前缀任务：名称/schedule/script 全量）；overview GET /overview 五值＋/notifications 条数与首条 id。
5. hermes 容器 env 现况盘点：确认 §六 env 迁入清单的落点（compose environment 还是部署 .env），companion.env [oneday] 段各运行参数的非空项清单（只记键名与有无、不落值）。
6. 留 §基线快照。

### 步 A · 网关侧（oneday＋overview 入关，一次切换）

0. **先停桥**：经 supervisor 期望状态关 oneday 与 overview 两模块（8646/8644 无流量后确认无监听）。理由：data.json 单写者纪律——桥与网关模块绝不许同写一族（普查图风险 1）；停桥期间 App 的目标/点子/动态/总览面短暂不可用（分钟级），Hermes 本体与其余面不受影响。回滚即重新启用（基线快照在手）。
1. **数据整迁**（停桥后、网关起前）：oneday-data 源目录整份拷入 hermes 数据目录 `oneday/` 子目录（data.json 及全部同目录文件/子目录，保权限），逐文件 sha256 对账（文件数与总字节与源一致）；overview-data/state.json 拷入 `overview/state.json`。源目录**不动**（观察窗回滚源）。
2. **hermes env 落值**：按 §六清单把 [oneday] 段运行参数迁入 hermes 部署 env（键名不变、值自 companion.env 搬运不落文档），另落 `HERMES_BASE_URL/HERMES_DASH_BASE_URL/HERMES_API_KEY/ONEDAY_CALLBACK_BASE` 四项拓扑值（模板见 services/hermes-compose.template.yml）。
3. `DRY_RUN=1 ./install.sh <部署目录>` 盘点——**预期：补丁更新 1（api_server.py）＋模块新建 19＋compose 挂载变更 1（19 模块挂载行＋device-data 只读挂载行）＋记忆资产待铺 0**（资产数按当时本体状态在步 0 复核后修正预期）。**不符即停**。
4. `./install.sh <部署目录>` 应用 → 脚本内健康检查（8642 health／9119＋容器内回读哈希 31 文件全对齐）全过才算落地。install 重启 hermes 后，网关模块在首个 oneday/overview 请求时懒启动（start() 幂等：_load 读新数据文件、ensure 重写 cron 脚本与任务登记、采集/哨兵/watcher 线程起）。
5. **四段验收**（直连 8642，带 API_SERVER_KEY；每段与步 0 桥侧读数逐项对账）：
   - **3a 核心**：GET /v1/oneday/health（degraded=false、ledger/collector/sentinel 与桥侧一致）、/goals、/ideas、/meta/brief、/traces 回读计数一致；保形口 GET /api/oneday-bridge/health 同值；无钥 401 对照；MCP 三门面 initialize＋tools/list 经保形口各一发。
   - **3b feed/monitors＋cron**：GET /feed、/monitors、/monitors/notifications 计数一致；**cron 实测**：查 Dashboard 任务登记表（四轮＋监测任务的名称/schedule 与桥侧一致、脚本已按新模板重写且内嵌新基址）；手动 POST 保形口 /internal/cron/ping（带回调钥，钥自数据目录文件读、不落文档）→ 200 pong；触发一轮 feed-a 回调（POST /internal/cron/rounds/feed-a 带钥）→ 轮次落账可查（feed generation 账更新）。
   - **3c ledger/deliveries/file-library**：GET /ledger/summary、/ledger 计数与桥侧一致；台账采集心跳在 health 中推进（lag 收敛）；**交付登记全环**：在 /opt/data 落一份真实测试文件 → 经公网保形口 POST /deliveries 登记（智能体纪律同路）→ marker 回执 → GET meta/cover 回读 → 测试登记留痕可查（deliveries.jsonl 新增行）；GET /file-library 200 且条目数与桥侧同量级（设备面读路径经 device-data 挂载在位：容器内 /opt/device-data 可读断言先行）。
   - **overview**：GET /v1/overview 五值与桥侧基线同口径（pendingApprovals 与网关 /v1/write-gate/status counts 对账）、/notifications 条数与首条 id 一致、保形口同值；POST 一条监测类通知 mark-read → 回读已读（state.json 落新目录）。
6. nginx：按两份 batch3 模板整段替换 /api/oneday-bridge/ 与 /api/overview-bridge/ 两块（摘 auth_request 换钥注入）；`nginx -t` 后 reload。
7. 公网行为验（带登录钥，经 https://hermes.example.com）：/api/oneday-bridge/health、/api/oneday-bridge/goals、/api/overview-bridge/overview 各 200 且与直连读数一致；Hermes MCP 三注册实调一发（经智能体或 curl initialize）。

### 步 B · companion 侧（升 1.0.70：两模块注册摘除＋删钥）

1. 按包内 companion 副本重建镜像（COMPANION_VERSION 已定 1.0.70：modules.json 已摘两注册、EXPOSE/ports 已摘两口）并换容器；重建前已在步 0 验全模块哈希一致，故重建除本批变更外零行为差。桥模块文件仍在镜像内（回滚源）。
2. **删钥与段退役**（步 A 验收全过后才执行）：生产 companion.env 删 [overview]、[oneday] 两段的钥与端口键（OVERVIEW_BRIDGE_KEY／ONEDAY_BRIDGE_KEY／OVERVIEW_PORT／ONEDAY_PORT／DATA_PATH 等桥专属键）；[oneday] 段的运行参数已在步 A.2 迁 hermes env，删段前逐键核对迁入清单无遗漏。重启 companion 后复验各余部模块 health 与 front 面板（模块表仅剩 device/identity/front/fileproc、台账计数卡经网关正口回数）。
3. 换版后验：companion-version 探针（1.0.70）转绿；8644/8646 无监听；跑全量 `./verify.sh`，输出存 `verify-output-1.13.0-applied-<日期>.txt` 入包——期望见 §二（预期外缺即停、按 §八回滚）。

### 步 C · 观察窗与收尾（≥7 天或至批四开工前，先到为准）

- 回滚源：镜像内桥模块文件＋基线 modules.json/env/state 快照＋**oneday-data/overview-data 源目录**（窗内只读保留、严禁写入——网关期新数据只在 data/oneday 与 data/overview）。
- 窗满收尾：自包内 companion 副本删除 oneday_bridge.py＋15 分段＋overview_bridge.py＋ledger.py；`ONEDAY_BRIDGE_KEY`、`OVERVIEW_BRIDGE_KEY` 至此全包退役完毕（凭据单源审计随批五 2.0.0 汇总）；源数据目录经用户/主线确认后归档。
- App 侧清理（后续独立项，不属本批）：App 改走 /v1 正口后，保形口 /api/oneday-bridge/*、/api/overview-bridge/* 自包内摘除。
- 网关内存基线：步 A 后 24 小时内记录 hermes 容器内存曲线（docker stats）存 rollout 执行记录——oneday 数据面与生成轮转入网关进程后内存增量以实测为准；rendition 内存闸（主机口径 85%）改容器口径一事按普查图风险 2 另立项，不在本批。

### 停手机制（任一触发即停、按 §八回滚退净再报）

内存 >80%；DRY_RUN 盘点与预期不符；步 0 发现名单外调用方或包内外模块哈希不一致；数据整迁 sha 对账不符；四段验收任一段计数与桥侧基线对不上；cron 登记表与桥侧不一致或 ping 实测不通；步 B 后 verify 出现预期外「缺」。

## 八、回滚步序（任一步失败即按此回）

1. **nginx**：vhost conf 还原基线整份＋`nginx -t`＋reload（公网两前缀指回 8646/8644 桥）。
2. **数据反向同步**（关键）：网关在役期间的新数据只在 `data/oneday/` 与 `data/overview/`——回滚前先停 hermes（或停网关面流量），把两目录整份反向拷回 oneday-data/overview-data 源目录（逐文件 sha 对账），再启桥。**不做此步直接启桥＝网关期数据丢失，严禁。** cron 脚本与任务登记无需手动回：桥 ensure 启动后按桥模板自愈重写（其内嵌默认仍为 companion:8646 形态）；若 hermes env 已落 ONEDAY_CALLBACK_BASE 新值，回滚时须一并摘除该 env（否则脚本 env 路径覆盖模板默认、回调仍指网关）。
3. **网关**：install.sh 失败自带自动回滚；人工回滚＝还原 baseline 的 api_server.py＋docker-compose.yml＋部署 .env、删 19 个新模块文件及 compose 对应挂载行（含 device-data 行）、重启 hermes。
4. **companion**：镜像 tag 指回 `oneday/companion:1.0.69` 换回容器；companion.env 还原基线整份；oneday/overview 若已停，经 supervisor 期望状态重新启用，8644/8646 恢复监听后按桥口径复验（health/overview/读数与步 0 基线一致）。
5. 回滚后跑 `./verify.sh`（以上一版包口径）确认回到应用前基线齐数。
6. **残留口径**：网关期经其产生的决定/登记/留痕已随数据反向同步回桥数据目录、格式逐字同构，桥照常成立，**不清理、不回滚数据**；overview 已读标记同理随 state.json 回迁。

---

预制交卷计数汇总：网关新模块 2＋分段 15＋台账库 1＋字体 1；api_server +117/−0；路由对账 66 条（桥 63＋overview 3）；AST 差异函数 8（全登记）＋overview 0；冒烟 49/49；改指清单 10 行（2 行零动作）；退役钥 2 把；verify 新增探针齐 +10／未验 +2。
