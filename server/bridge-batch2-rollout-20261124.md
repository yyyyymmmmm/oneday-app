# 断桥批二合并版应用方案（包 1.10.0）——已合入本体，待主线排窗应用，未应用生产

基线事实：生产现行包 **1.9.0**（2026-11-24 01:09 应用、无回滚，verify 齐 37／缺 0，基线 `/root/deploypkg-1.9.0-20261124/baseline/`，应用记录 `verify-output-1.9.0-applied-20261124.txt`）。本批变更集＝批二预制副本 `~/workspace/hermes-deploy-batch2/`（只读）增量并入本体 `~/workspace/hermes-deploy/` 升 **1.10.0**。合并纪律：只许增量 hunk 叠加、严禁整文件覆盖；批二副本 `api_server_runs.py` 是旧基线、不带回本体。

## 一、合并交卷：变更清单（逐文件）

| 文件 | 处置 | 证据 |
|---|---|---|
| `patches/write_gate_gateway.py` | **新建**：批二预制模块逐字入包（1228 行，业务逻辑与桥 AST 对齐、监工验收过） | sha256 `321b66e8…a1d` 与批二登记值一致 |
| `patches/api_server.py` | **增量叠加**于 1.9.0 件：capability registry +12 行、路由表 +27 行（12 正口＋12 保形口）、handlers +173 行、connect() 启动钩子 +5 行、grants 注释 2→3 行；合计新增 220 行、删 2 行 | sha `ac675c40…c9`（1.9.0）→ `01508a8e…b0`（1.10.0）；并集验证：与批二副本 diff 仅剩本体独有块（fileproc 78 行＋自反应 7 行），writeGate 内容零差异；py_compile 通过 |
| `patches/api_server_runs.py` | **零改动**：批二副本经逐 hunk 核查零 writeGate 内容（全部差异均为本体 1.8.0 自反应件）；writeGate 接点只有 api_server.py 的 connect() 启动钩子，已按本体 1.9.0 锚点（grant_projection.start() 之后）手工接 | sha 不变 `6328ec5f…f3044` |
| `install.sh` | MODULES 增 write_gate_gateway 一行＋注释；compose 挂载 spec／两处 grep 校验增同名行；api_server.py 期望 sha 更新 | bash -n 通过 |
| `verify.sh` | 两张哈希表＋模块清单增 write_gate_gateway；新增**第 18 节**（status／rules／保形口／memories 四只读探针＋decide／propose 两未验项）；companion-version 期望升 1.0.69 | bash -n 通过 |
| `manifest.yaml` | version 1.9.0→**1.10.0**；api_server 条目 sha／diff_lines 779→999／provides 增 write-gate-routes、memories-routes／summary 增 1.10.0 段；新增 write_gate_gateway 模块条目（补丁条目 10→**11**）；hermes summary 增挂载注记；companion 条目升 1.0.69、ports 摘 8643、summary 增批二段 | YAML 解析通过 |
| `CAPABILITIES.md` | 新增 **#20 写闸治理＋记忆条目入关**；#6 行加批二注记（应用后 8643 形态退役、探针由 #20 接替）。注册表 18→**19 条**、编号至 #20（#21 已由自主设置权一期预订，不撞号） | — |
| `companion/supervisor/modules.json` | 摘 writeGate 注册（模块 7→6：overview／oneday／device／identity／front／fileproc）；write_gate_bridge.py 文件暂留（观察窗回滚源，同批一 fileproc 分期） | JSON 解析通过 |
| `companion/companion.env.example` | [write-gate] 段改退役注记（钥作废口径同批一 channels） | — |
| `companion/Dockerfile`、`companion/docker-compose.yml` | COMPANION_VERSION 1.0.68→**1.0.69**；EXPOSE 与 ports 摘 8643 | — |
| `services/companion-compose.template.yml`、`services/env.template` | 摘 8643 端口行；env 模板 write-gate 键加退役注记 | — |
| `services/nginx-batch2-writegate-shape.conf` | **新建**：/api/write-gate/ 改指网关 8642 保形模板（proxy_pass 不带 URI、Authorization 直传，口径同批一模板） | — |
| `DEPLOYMENT-GUIDE.md` | 头部增批二注记一段，正文不动（终局改写随批五 2.0.0） | — |

合并自测：write_gate_gateway 带桩冒烟复跑 **26／26 全过**（桩＝上游 write_approval／memory_tool／handle_pending_subcommand 替身＋临时 HERMES_HOME；覆盖 status／pending／decide 全环／rules 增删／memories 列表详情／propose 暂存与各 400／404 分支，状态三文件落盘实证）；fail-closed 复核：无桩导入 SUPPORTED=False、pending／propose／decide 回 409、rules 仍可读；sha 三方对账（manifest／install.sh／verify.sh 登记值 vs 包内实测）**11 文件全一致**。

## 二、合并后包状态

- manifest 补丁条目 **11**；CAPABILITIES **19 条**（编号至 #20）；verify 命名探针：1.9.0 应用实测齐 37 的基础上，第 18 节新增 4 只读探针（write-gate-status-endpoint／write-gate-rules-endpoint／write-gate-shape-endpoint／memories-endpoint）＋2 未验（write-gate-decide／memory-propose，写型默认不跑、人工路径见 CAPABILITIES #20），patch-hash 回读 10→**11** 文件。
- **verify 干跑预期（应用后）**：齐 **41**／缺 **0**／未验 +2（两写型项）；companion-version 期望 1.0.69（步 B 后转绿，步 A 后、步 B 前报缺属预期挂账，同批一 identity 先例）。

## 三、凭据单源审计（批二分量）

- write_gate_gateway **零新增钥**：12 个 handler 全挂网关 `@_require_auth`（即 API_SERVER_KEY 本体钥），模块全文无钥类定义（合并时复核）。
- `WRITE_GATE_BRIDGE_KEY`（桥自有钥）随本批应用退役：删除点＝生产 companion.env [write-gate] 段（步 B），包内 env 模板已先行注记作废。
- ⚠️ **消费者口径（本批与批一的关键差异，步 0 必查）**：该钥同时是 companion 内部模块调 8643 的**客户端钥**——overview（读 /status／/decisions／/pending 生成通知）、oneday ledger／ideas（读 /memories 等）、front 面板均经 `WRITE_GATE_BASE`（env 可改指）＋此钥调用桥。删钥／停桥前必须先把这批调用方改指网关保形口（`http://127.0.0.1:8642/api/write-gate`，路径与桥根路径逐条对应）且呈钥改 API_SERVER_KEY 同值（经 modules.json env_from 改映射或模块代码改读 HERMES_API_KEY，改法于步 0 按生产容器内文件实况定）。改指未完成不许停桥、不许删钥。

## 四、应用方案

### 基线快照（应用前，缺一不开工）

落 `/root/deploypkg-1.10.0-<日期>/baseline/`：
1. 部署目录现行 `patches/api_server.py`＋`docker-compose.yml`（install.sh 自带 .bak 之外再留整包基线，同前例）；
2. 线上 nginx vhost conf 整份；
3. companion 镜像现行 tag `oneday/companion:1.0.68` 保留不删（镜像回滚源）＋生产 companion.env 整份＋companion-state 目录快照（supervisor 期望状态，writeGate 开关回滚用）；
4. 写闸状态三文件只读留影（`<HERMES_HOME>/write-gate/` 的 rules.json／decisions.jsonl／anchors.json）＋步 0 桥侧读数（规则数、pending 数）；
5. 部署包 1.9.0 目录整份留底。
数据面：本批零数据迁移、零格式变更——网关模块与桥共用同一状态目录原地读写，pending／rules／decisions 天然承接。

**与 fileproc 观察窗的关系（先到为准）**：批一观察窗在途（fileproc 桥进程 8652 待命、宿主 8651→8652 映射保留）。本批应用与窗满停桥互不阻塞、互不改写：批二先行时，基线按当时实况记录 fileproc 桥状态，观察窗在本包下继续，窗满停桥动作不变；停桥先行时，批二基线记录其已停事实即可。两窗的回滚源各自独立（nginx 指回＋各自进程／镜像）。

### 步 0 · 前置（只读，含停手条件）

1. 查服务器内存 <80%（118.24.41.52），超限即停。
2. 复核 1.9.0 应用后状态在位：verify-output-1.9.0-applied 在包、齐 37／缺 0；fileproc 观察窗状态按实况登记（见基线节）。
3. **8643 调用方盘点（本批新增，缺一不开工）**：在生产 companion 容器内 grep 全部模块的 `WRITE_GATE_BASE`／`8643`／`WRITE_GATE_BRIDGE_KEY` 引用，与本方案 §三名单（overview／oneday_seg_ledger／oneday_seg_ideas_gen／front）逐个对账；**发现名单外调用方即停**，先补改指方案再排窗。逐个比对包内 companion 副本与容器内同名文件 sha256（步 B 重建镜像的安全前提，同批一步 0）。
4. 桥侧读数：带桥钥 GET 8643 /status（gate 开关、pending 计数）、/rules（规则数）记录在案，供步 A 后网关读数逐项对账。
5. 留 §四基线快照。

### 步 A · 网关侧（writeGate 入关）

0. **先停桥**：经 supervisor 期望状态关 writeGate（8643 无流量后确认无监听）。理由：桥与网关模块共用状态目录且各自带 5 秒清扫线程，同跑存在双清扫重复裁决竞态（后果限于 decisions.jsonl 重复记账，但不必冒）；停桥期间 App 写闸面短暂不可用，待批暂存于 Hermes 本体 pending 机器、零丢失。回滚即重新启用（基线 state 快照在手）。
1. `DRY_RUN=1 ./install.sh <部署目录>` 盘点——**预期**：补丁更新 1（api_server.py）＋模块新建 1（write_gate_gateway.py）＋compose 挂载变更 1。**不符即停**。
2. `./install.sh <部署目录>` 应用 → 脚本内健康检查（8642 health／9119＋容器内回读哈希 11 文件全对齐）全过才算落地。
3. 直连 8642 行为验（带 API_SERVER_KEY）：GET /v1/write-gate/status → 200 且 supported=true、counts 与步 0 桥侧读数一致；GET /v1/write-gate/rules → 200 且规则数一致；GET /v1/memories → 200；GET /api/write-gate/status（直连保形口）→ 200；四口无钥 → 401 对照。
4. nginx：按 `services/nginx-batch2-writegate-shape.conf` 整段替换 /api/write-gate/ 块；`nginx -t` 后 reload。
5. 公网行为验（带登录钥，经 https://hermes.example.com）：/api/write-gate/status → 200、/api/write-gate/rules → 200（与直连读数一致）。

### 步 B · companion 侧（升 1.0.69：writeGate 注册摘除＋消费者改指＋删钥）

1. 按包内 companion 副本重建镜像（COMPANION_VERSION 已定 1.0.69：modules.json 已摘 writeGate 注册、EXPOSE／ports 已摘 8643）并换容器；重建前已在步 0 验全模块哈希一致，故重建除本批变更外零行为差。write_gate_bridge.py 仍在镜像内（回滚源）。
2. **消费者改指**（与换容器同窗）：按步 0 定案改 overview／oneday 的 `WRITE_GATE_BASE` → `http://127.0.0.1:8642/api/write-gate`、呈钥改 API_SERVER_KEY 同值；front 面板 writeGate 条目按实况摘除或改指。改后实证：overview 通知面 write_gate 类 kind 仍产出（对照网关 /status counts 与 overview pendingApprovals 一致）、oneday 记忆面可读。
3. **删钥**（改指实证通过后才执行）：生产 companion.env 删 [write-gate] 段 `WRITE_GATE_BRIDGE_KEY`／`WRITE_GATE_PORT` 值（整份 env 已在基线内）；重启 companion 后复验 §三各调用方无鉴权失败日志。
4. 换版后验：companion-version 探针（1.0.69）转绿；8643 无监听；其余模块 health 全绿；跑全量 `./verify.sh`，输出存 `verify-output-1.10.0-applied-<日期>.txt` 入包——**全量期望：齐 41／缺 0／未验含 write-gate-decide、memory-propose 两写型项**（人工验收路径见 CAPABILITIES #20）。

### 步 C · 观察窗与收尾（≥7 天或至批三开工前）

- writeGate 桥回滚源＝镜像内 write_gate_bridge.py＋基线 modules.json／env／state 快照：窗内回滚＝恢复注册与 env 段、supervisor 重新启用、nginx 指回 8643（见 §五）。
- 窗满收尾：自包内 companion 副本删除 write_gate_bridge.py（同 fileproc 收尾分期）；`WRITE_GATE_BRIDGE_KEY` 至此全包退役完毕（凭据单源审计随批五 2.0.0 汇总）。
- App 侧清理（后续独立项，不属本批）：App 改走 /v1 正口后，保形口 /api/write-gate/* 自包内摘除。

### 停手机制（任一触发即停、按 §五回滚退净再报）

内存 >80%；DRY_RUN 盘点与预期不符；步 0 盘点发现名单外 8643 调用方或包内外模块哈希不一致；步 A／B 后 verify 出现预期外「缺」；消费者改指后 overview／oneday 任一面鉴权失败。

## 五、回滚步序（任一步失败即按此回）

1. **nginx**：vhost conf 还原基线整份＋`nginx -t`＋reload（公网 /api/write-gate/ 指回 8643 桥）。
2. **网关**：install.sh 失败自带自动回滚；人工回滚＝还原 baseline 的 api_server.py＋docker-compose.yml、删 patches/write_gate_gateway.py 及 compose 对应挂载行、重启 hermes。
3. **companion**：镜像 tag 指回 `oneday/companion:1.0.68` 换回容器；companion.env 还原基线整份；writeGate 若已停，经 supervisor 期望状态重新启用（state 快照在基线内），8643 恢复监听后按桥口径复验 /status。
4. 回滚后跑 `./verify.sh`（以 1.9.0 包口径）确认齐 37／缺 0。
5. **残留口径**：网关在役期间经其裁决的 decisions 已 append 入共享 decisions.jsonl、规则增删已落共享 rules.json——桥读同一状态目录、语义逐字同构，回滚后照常成立，**不清理、不回滚数据**；pending 暂存于 Hermes 本体机器，与桥／网关形态无关，零影响。
