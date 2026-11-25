# 断桥批一＋自反应合并版应用方案（包 1.9.0）——已合入本体，待主线排窗应用，未应用生产

> 来源：副本 `~/workspace/hermes-deploy-batch1/bridge-batch1-rollout-20261124.md`（批一应用方案原件，保留不动）＋ `ai-self-reaction-skeleton-20261124.md` §7（1.8.0 应用前检查单）。2026-11-24 主线合并交卷：批一变更集已按并集口径合入部署包本体、落点版本 **1.9.0**；本文件是合并后的唯一应用方案正本（两变更集一次应用）。
> 用户已裁（2026-11-24 00:28）：device 整搬（后续批）、front 凭据托管降级只读（批四）、自反应做（已入 1.8.0）；00:44 增裁：**部署包凭据单源**（见 §三）。
> 主线已裁：identity 步 B 随批一应用走 companion 升 **1.0.68**；rendition 缓存应用时拷贝旧桥缓存继承热度。
> 服务器纪律：合并施工全程未碰服务器（仅包内文件操作）；应用时先查内存 <80%。

## 一、合并交卷：变更清单（逐文件）

**整取自批一副本**（自反应线未动，字节不变）：`patches/fileproc_gateway.py`（sha256 96654ddd…）、`services/nginx-batch1-fileproc-shape.conf`、`fileproc_gateway_selftest.py`、`companion/docker-compose.yml`、`companion/companion.env.example`、`companion/supervisor/modules.json`（摘 channels，8→7 模块）、`companion/modules/identity_bridge.py`（摘 POST /identity/name dispatch＋NAME_WRITE_RETIRED_180 标记）、`DEPLOYMENT-GUIDE.md`（头部批一注记；合并时另加凭据单源注记段）。

**删除**：`companion/modules/channels_bridge.py`（1424 行整文件退役）。

**并集合并**（逐文件三方比对：本体 1.8.0 现值 × 批一副本值 × 1.7.0 基线）：
- `patches/api_server.py`：机械验证两线零交叠——difflib opcodes：批一只在本体外 +78 行、自反应只在批一外 +7 行、replace 块 0。合并件 sha256 `ac675c40f7d9c7558470fd7453be3cd9343ca24d2125d34e36e8b7c3aff03ec9`，与批一预演参考值**逐字一致**；4886 行；对上游 diff **779 行**（基线 694＋78＋7，与 manifest 登记口径一致）；py_compile 通过。
- `manifest.yaml`：version 1.8.0→**1.9.0**；api_server 条目登记 merged 哈希/diff 779/provides 增 file-spreadsheet、media-rendition、summary 增 1.9.0 段；新增 fileproc_gateway 模块条目；hermes 服务 summary 增 1.9.0 挂载注；companion 服务条目：image→**1.0.68**、ports 摘 8649 与 8651->8652、summary 增批一注。
- `install.sh`：PATCHES 中 api_server 哈希→merged 值；MODULES 在 crash_reports 后增 fileproc_gateway 一条（＋注释行）；compose 挂载 specs 增 fileproc_gateway（锚 crash_reports 行后）；挂载侦测/写后校验 grep 各增一条。
- `verify.sh`：WANT_SHA api_server→merged 值、WANT_SHA_EXTRA/CPATH/§2 回读名单增 fileproc_gateway；§15 探针改指网关（rendition-route / rendition-shape-route / spreadsheet-route，均无钥 401 口径）；新增 §17 退役面探针（channels-retired、identity-name-write-retired）；companion-version 期望 1.0.67→**1.0.68**（overview-notification-kinds 失败文案同步）。
- `CAPABILITIES.md`：#8 改写（模块名单摘 channels/fileproc、镜像 1.0.68）；#18 改写为「文件加工（spreadsheet＋rendition）」网关落点；#19（自反应）本体原文不动。

**主线裁决落地**：`companion/Dockerfile` ARG COMPANION_VERSION 1.0.67→**1.0.68**（与 manifest/verify 期望三处齐）。

**模板一致性补齐**（批一副本未覆盖、合并时顺手对齐）：`services/companion-compose.template.yml` 摘 8649 与 8651:8652 端口行、COMPANION_VERSION→1.0.68；`services/env.template` 的 [channels] 两行改退役注记（CHANNELS_BRIDGE_KEY 作废）。

**本体保留不动**（批一副本为旧值，不取）：`patches/api_server_runs.py`（1.8.0 件）、`patches/react_to_message_tool.py`、`patches/self_reaction_pending.py`、`ai-self-reaction-skeleton-20261124.md`（本体为入包定稿）。

**版本字样留痕说明**：批一工件内部的「1.8.0」字样（api_server 合并件内 docstring、fileproc_gateway docstring、identity 的 NAME_WRITE_RETIRED_180 标记名、env.example/nginx 模板/自测的注记）是变更集原拟号留痕——这些字节分别被 merged 参考哈希、fileproc 登记哈希与 verify 探针字符串依赖，故不改写；落点版本以 manifest/CAPABILITIES/verify/DEPLOYMENT-GUIDE 的 1.9.0 登记为准。

## 二、合并后包状态

- 版本 **1.9.0**（自 1.7.0 生产在役版起算：含 1.8.0 自反应＋1.9.0 断桥批一，未应用）。
- manifest 补丁/模块条目 **10**（全文件补丁 3＋模块通道 7）；services 4 条（hermes、companion 1.0.68、两条 legacy 未运行）。
- CAPABILITIES 登记 **18 条**（编号 #1–#19，#15 历史缺号；#19 自反应＝已入包待应用，#18 文件加工＝网关形态待应用）。
- verify.sh：**33 个命名探针＋10 项 patch-hash 容器内回读**；相对 1.7.0 应用口径新增/变更：patch-hash fileproc_gateway、rendition-route（改指）、rendition-shape-route、spreadsheet-route、channels-retired、identity-name-write-retired、self-reactions-capability、self-reactions-projection、self-reactions-behavior（未验档）、companion-version（期望值变更）。
- 一致性自检（合并时已跑）：manifest/install/verify 三处哈希与 10 个补丁文件实测**全一致**；全部 patches/*.py＋identity_bridge＋selftest py_compile 通过；install.sh/verify.sh `bash -n` 通过；manifest YAML 与 modules.json 解析通过；`fileproc_gateway_selftest.py` 在合并后本体复跑 **PASSED**（22 项行为断言）。自反应包内自测为该线本地/容器内执行记录（骨架 §6/§7），未随包附自测文件。

## 三、凭据单源审计（2026-11-24 用户定版：一个密码全通用）

口径：密码/密钥与 Hermes 本体同一个，`API_SERVER_KEY` 一把通全包；包内任何新面不许另设钥。全包 grep 密钥/凭据类配置项（名称级，不取值），逐项如下：

| 配置项 | 来源/落点 | 与 API_SERVER_KEY 同源？ |
|---|---|---|
| **API_SERVER_KEY** | Hermes 本体网关钥（instance env：data.env/compose environment；api_server.py:1280/1619 验钥） | **单源本体** |
| install.sh / verify.sh 的 `API_KEY` 变量 | 两脚本运行时从 hermes 容器环境回读 `API_SERVER_KEY`（install.sh:277、verify.sh:64） | 同源（同一把钥的脚本内变量名） |
| **HERMES_API_KEY**（companion.env） | companion 侧调网关的客户端钥；env.example 明注「与 Hermes 侧 API_SERVER_KEY 同值」 | 同源（服务端副本、同值，非第二把钥） |
| **批一新面：fileproc_gateway 两端点** | api_server handler 以 `@_require_auth` 验 API_SERVER_KEY；fileproc_gateway.py 本体**不读任何钥**（grep 仅命中文件名敏感词表与缓存锁，非凭据）；nginx 保形模板摘换钥行、Authorization 透传 | **同源 ✔（无第二把钥）** |
| **1.8.0 新面：react_to_message_tool / self_reaction_pending / api_server_runs attach** | 均在网关进程内，无独立端点、无钥读取（react 工具仅读 HERMES_SESSION_ID/HERMES_SESSION_KEY 会话标识，非凭据） | **同源 ✔（无第二把钥）** |
| CHANNELS_BRIDGE_KEY＋channels 段借用的 HERMES_DASHBOARD_SESSION_TOKEN | companion [channels] 段 | **已随批一作废**（env.example 与 services/env.template 均留退役注记，与单源口径一致） |
| FILEPROC_BRIDGE_KEY（存量） | companion fileproc 桥进程自有钥 | 非本两批引入；网关新面已不使用它。观察窗内桥进程待命期间仍在，窗满停桥后随之退役（批一收尾项） |
| companion 模块钥（存量）：WRITE_GATE_BRIDGE_KEY / OVERVIEW_BRIDGE_KEY / ONEDAY_BRIDGE_KEY / DEVICE_BRIDGE_KEY / IDENTITY_BRIDGE_KEY / COMPANION_SERVICE_KEY（nginx→front 内部跳钥）/ PANEL_PASSWORD_HASH（front 面板口令哈希） | companion 既有架构（桥-钥匙-rollout 2026-11-10 定版），非批一/1.8.0 引入 | 不同源——属断桥收敛对象：随各批模块入关/退役逐个消亡，终局（包 2.0.0）只剩 API_SERVER_KEY 一把。本审计不改动它们（改值属生产配置动作、且各模块退役时点已排期） |
| HERMES_DASHBOARD_BASIC_AUTH_USERNAME/PASSWORD/SECRET、HERMES_DASHBOARD_SESSION_TOKEN、HERMES_DASH_PASSWORD 等 | Hermes Dashboard（9119）上游自带登录面（instance env） | 上游本体面、非本包所设；包不改上游登录机制。部署者可与 API_SERVER_KEY 设同值，属 instance 配置选择 |
| 第三方服务钥：TAVILY_API_KEY / FIRECRAWL_API_KEY / NEWAPI_ADMIN_TOKEN / MCP_BOX_API_KEY（box 已退役、残留登记）等 | 部署者自备、对外部服务鉴权 | 不在「一把通」范围（不是包内面的钥） |
| credentials.txt（包根，历史留存） | 含 dashboard/api_server_key/write_gate_key 等**名称**条目（明文留存问题为既有安全旗标，待用户拍板 scrub＋轮换，不在本合并范围） | 记录文件、非配置面；不引入新钥 |

**审计结论**：批一与 1.8.0 两个变更集**零新增第二把钥**，新面全部走 API_SERVER_KEY 单源，无需改码、无待裁项。DEPLOYMENT-GUIDE 头部已增「凭据单源」注记段明写一个密码全通用。

## 四、合并版应用方案（两变更集一次应用）

### 基线快照（应用前，缺一不开工）

落 `/root/deploypkg-1.9.0-<日期>/baseline/`：
1. 部署目录现行 `patches/api_server.py`＋`patches/api_server_runs.py`＋`docker-compose.yml`（install.sh 自带 .bak 之外再留整包基线，同 1.7.0 先例）；
2. 线上 nginx vhost conf 整份（hermes.example.com.conf，宝塔现行版）；
3. companion 镜像现行 tag `oneday/companion:1.0.67` 保留不删（镜像回滚源）＋companion-state 目录快照（模块期望状态文件，channels 开关回滚用）；
4. 部署包 1.7.0 目录整份留底。
数据面：两变更集均零数据迁移、零格式变更；rendition 缓存属可再生数据，不入基线；已落库的 agent 反应不清理（回滚残留口径，见 §五）。

### 步 0 · 前置（只读）
查内存 <80%；复查 companion 日志窗内 channels/identity-name 调用（口径同副本方案 §二.2）；逐个比对包内 companion/modules/*.py 与生产容器内同名文件 sha256（作为步 B 镜像重建的安全前提）；留 §四基线。

### 步 A · 网关侧（自反应潜伏＋fileproc 入关，一次 install）
1. **instance config 先行一步**：`platform_toolsets.api_server` 增 `self_reactions`；**不置** `display.agent_self_reactions`（保持潜伏，翻闸是 App 出货后的独立一步，不与应用同批）。
2. `DRY_RUN=1 ./install.sh <部署目录>` 盘点——**预期**：补丁更新 1（api_server.py）＋模块更新 1（api_server_runs.py）＋模块新建 3（react_to_message_tool.py、self_reaction_pending.py、fileproc_gateway.py）＋compose 挂载变更 1。盘点不符即停。
3. `./install.sh <部署目录>` 应用 → 脚本内健康检查（8642 health/9119/8643＋容器内回读哈希全对齐）全过才算落地。
4. 直连 8642 行为验（带 API_SERVER_KEY）：真实 xlsx GET /v1/files/spreadsheet → 200 且 sheets 结构完整；真实图片 GET /v1/media/rendition?w=360 → 200 image/jpeg＋ETag、If-None-Match → 304、w=1080 与 360 尺寸不同；无钥四口（正口两＋保形口一＋capabilities 对照）口径：文件三口 401、capabilities 200 且 features.self_reactions=true。
5. **缓存继承（已裁：拷贝）**：把旧桥缓存（/opt/oneday-data/renditions/*.jpg）一次性拷入新目录 /opt/data/fileproc-cache（键含路径＋mtime＋size，拷贝后键仍命中）。
6. nginx：按 `services/nginx-batch1-fileproc-shape.conf` 替换 fileproc location，**同窗删 channels location**（公网面先断、进程稍后停）；`nginx -t` 后 reload。
7. 公网行为验（带登录钥，经 https://hermes.example.com）：/api/fileproc-bridge/files/spreadsheet 与 /api/fileproc-bridge/media/rendition 与步 4 同断言；/api/channels-bridge/* → 404（预期）。
8. App 冒烟（用户侧下一会话）：文件面开一个 xlsx、聊天/文件面图片出变体图（非原图全量）。

### 步 B · companion 侧（升 1.0.68：channels 停＋identity 写口关停）
1. channels 停用：经 supervisor 期望状态关 channels，确认 8649 无监听、进程表无 channels；verify 的 channels-retired 探针转绿。**此步不动镜像**（模块文件仍在镜像内，回滚即重新启用）。
2. 按包内 companion 副本重建镜像（COMPANION_VERSION 已在包内定为 1.0.68）并换容器——重建前已在步 0 验全模块哈希一致，故重建除 channels 删文件/modules.json 摘条/identity 写口关停外零行为差。
3. 换版后验：companion-version 探针（期望 1.0.68）转绿；identity GET /identity/name 200 保形、头像读/写/选/图四口照常、POST /identity/name → 404、identity-name-write-retired 探针转绿；MCP identity 六工具在位（agent 侧 tools/list 对账）；其余模块 health 全绿；front 面板模块名单无 channels。

### 步 C · 观察窗与收尾（≥7 天或至批二开工前）
- fileproc 桥进程保持在役待命（nginx 已切走、无流量）作回滚源；窗满后经 supervisor 关停，8651 宿主映射随下一次 compose 整理摘除，FILEPROC_BRIDGE_KEY 随之退役；包内 modules.json 的 fileproc 条目与 fileproc_bridge.py 在摘除同窗删除（本包暂留，属有意分期）。
- 跑全量 `./verify.sh`，输出存 `verify-output-1.9.0-applied-<日期>.txt` 入包。**全量期望**：patch-hash 10 文件齐；self-reactions-capability 齐；self-reactions-projection 报「未触发」（闸关预期，不作失败）；rendition/rendition-shape/spreadsheet 三探针齐；channels-retired 与 identity-name-write-retired 齐（步 B 后）；companion-version 齐（1.0.68）；汇总缺 0。

## 五、回滚步序（任一步失败即按此回）

1. **nginx**：vhost conf 还原基线整份＋`nginx -t`＋reload（fileproc 流量指回待命桥进程、channels 公网面恢复）。
2. **网关**：install.sh 失败自带自动回滚；人工回滚＝还原 baseline 三文件（api_server.py、api_server_runs.py、docker-compose.yml）＋删三新建模块文件（react_to_message_tool.py、self_reaction_pending.py、fileproc_gateway.py）及对应 compose 挂载行＋重启 hermes；instance config 的 `self_reactions` 名单项可留（无补丁时解析为空、无害）或随手摘除。
3. **companion**：镜像 tag 指回 `oneday/companion:1.0.67` 换回容器；channels 若已停，经 supervisor 期望状态重新启用（state 快照在基线内）。
4. 回滚后跑 `./verify.sh`（以 1.7.0 包口径）确认全齐，探针数按当时口径重算。
5. **残留口径**：已写入的 author="agent" 反应留在 display_metadata 不清理（合法反应数据，旧 App 走既有反应渲染）；新目录 /opt/data/fileproc-cache 可留（可再生缓存）；不为回滚动任何用户数据。
