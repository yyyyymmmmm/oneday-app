# 断桥批五·终局应用记录（部署包 2.0.0，2026-11-25）

授权：用户 2026-11-25 01:16 亲令——拆桥提至最前优先、「我们是测试环境，不要怕生产问题」；服务端全批授权在案。正本：batch5-precheck-20261125.md、server-next-prep-20261125.md 第 4 节、bridge-retirement-spec-20261124.md §4 C-1（device 整搬法）。

结论：**桥已拆完。** device 整搬入网关（device_gateway＋device_sync 两模块）、companion 整容器下线退役、单钥收敛完成、单容器终局达成。verify.sh 全量 **84 项齐、0 项缺**。

## 回滚基线

`/root/deploypkg-2.0.0-20261125/baseline/`（SHA256SUMS 已回读全过），含：device-bridge-data 全量快照（停机前在役三文件）、companion 双 compose、companion.env（600）、hermes compose、hermes-config.yaml、在役 nginx vhost（改前）、改前 patches/api_server.py、docker-images.txt；应用后另存 nginx-post-2.0.0.conf 与 hermes-docker-compose-post-2.0.0.yml 两份终局快照。companion 镜像保留标签 `oneday/companion:pre-2.0.0-baseline`（在役末代 1.0.77，id ed8063d5d329）。

## 施工（先入包，后应用）

包内变更（~/workspace/hermes-deploy，版本 1.23.0 → 2.0.0）：

- 新增 `patches/device_sync.py`：桥侧同步库逐字平移，sha256 `f2312d0caed820646a738c181b0e646c576ff22500b9c76d13f16960393bd838`，与退役前容器内在役件逐字节一致（注：前置材料里流转的 `f2312d0cf1a3…` 系截断误记，钉值已按实文件更正，install.sh/verify.sh 双边复核 41/40 条零不符）。
- 新增 `patches/device_gateway.py`（sha256 `41ec8246…`）：device_bridge 引擎逐字保留，只换三处——①传输层：删独立 HTTP 服务，代之以 `_GatewayHandler` shim 复用 Handler 全部路由方法（每条路由恰以一次 `_send` 收尾）＋`dispatch_sync()`，由 api_server 的 aiohttp 面经 `asyncio.to_thread` 在工作线程驱动，应答保桥的扁平 JSON 形；②鉴权改单钥 `API_SERVER_KEY`（桥钥 DEVICE_BRIDGE_KEY 退役，fail-closed 与 /health 免钥不变）；③数据目录 `DEVICE_DATA_DIR`、默认 `/opt/data/device`；导入即 start()（建目录、device_sync.init、审计文件 0600）。
  - **偏离登记**：C-1 施工图建议 asyncio.Event 驱动；本包用线程卸载保引擎逐字——§244 权限门/park 流全是 threading 语义，改写漂移风险高于线程方案，故偏离并在此登记。
- `patches/api_server.py`（sha256 `d2024ca6…`）：加 `GET/POST /api/device-bridge/{tail:.*}` 与 `POST /api/device-mcp` 两组路由（故意不挂 @_require_auth——模块自验单钥且 /health 免钥，同 cron 回调面分工）＋三分发 handler＋`features.device_bridge=true`。
- 新增 `device-mcp-config-patch.py`：只动 config.yaml 的 mcp_servers.device 一条（url→`http://127.0.0.1:8642/api/device-mcp`、Authorization→单钥），改前备份、断言各只替换一处、钥不打印；本地假配置试跑＋幂等复跑已验。
- 新增包内自测 `device_gateway_selftest.py`：临时数据目录＋测试单钥全环 19 项（health 免钥、401 双例、会话注册、MCP 握手、tools/list 与模块注册表一致、实时 poll/respond 全环、写幂等、同步写读往返、离线诚实、审计无内容）——**19/19 全过**。
- install.sh/verify.sh/manifest.yaml/CAPABILITIES.md（#35）/services 模板同步：MODULES 加两件与钉值、3b specs 加两挂载、device-data 挂载行改指 `./data/device:/opt/device-data:ro` 并收敛重复行、DEVICE_DATA_DIR 环境钉入、verify 第 26 节八探针、companion 组件标退役。
- DEPLOYMENT-GUIDE.md 终局改写（标题/§1/§3/§4/§5/§7/§9/§10 口径/§11/§12 全清 companion 在役形态）；nginx 终局两块收编为 services/nginx-batch5-device-shape.conf（只收片段，不收整 vhost——整份含其他 location 的钥字面值，不入包）。

**工具数口径更正**：施工图与旧指南写的「10 工具」是 2026-11-10 骨架期旧数；在役桥退役前实查注册表为 **53 个工具**（基线 bridge-live-state.json 逐名留档），本批验收口径＝53＝53 逐名一致。

## 应用（2026-11-25 01:35–01:55 CST，服务器 118.24.41.52）

1. 开工复查：整机内存 4299/7725 ≈ 55.7%（红线 80% 未触）；`permission-parks.json` 全盘零命中——该文件不存在、按需生成，搬迁无此文件、网关侧按需新建。
2. DRY_RUN 先行：计划恰为「补丁 1（api_server.py）＋新建模块 2＋compose 变更 1」，无其他漂移才真跑。
3. 停 oneday-companion（切换窗开始）→ device 数据 `cp -a` 至 hermes/data/device/，三文件与停机后源逐一同哈希（sync.db e763040c…、write-keys.json 7d6b1bf3…、audit.jsonl b604f62b…；比基线快照新是停机前桥侧正常写入，迁的是最新态）。
4. 配置补丁器应用：device 条目 url 与钥一次替换到位，备份 config.yaml.bak-20261125013751。
5. install.sh 真应用：中途 SSH 断线一次（broken pipe）——未假设、未重跑，先查实：三文件已落目标哈希、compose 已改、hermes 已服务级重启、.bak 齐全，判定应用已完成、仅其自带健康检查被断线截断，由本记录的冒烟补齐。
6. **冒烟首轮 device 面 503 定因修复**：模块在 root 的 docker exec 里导入正常、在网关进程里失败——网关进程以 uid 10000（hermes 用户）运行，而拷入的 device 三文件是 root:root 0600，device_sync.init 打不开库。`chown -R 10000:10000 data/device/` 后 health 立即转 ok。此坑已写入 DEPLOYMENT-GUIDE §3（root 拷贝后必须 chown）。
7. nginx：在役 vhost 两条 location 按 fileproc 先例改指 8642（device-bridge 摘 auth_request＋换钥、透传单钥、保形全路径；device-mcp 改指 8642/api/device-mcp），沿革注释里的字面 8647 一并清零，`nginx -t` 过、reload 完成。改前整份备份在基线（nginx-pre-batch5-edit.conf）。
8. companion 收尾：`docker rm oneday-companion`；其 compose 换墓碑空定义（原文在基线）；在役 companion.env 删除（基线有 600 副本）。注：companion 目录内历史 companion.env.bak-* 若干份未动（历次回滚留档，是否清理请主线另裁）。
9. `agitated_tesla`（同镜像一次性诊断残留、无端口绑定、不碰 device 数据）按前置结论留置未动。

## 验收（回读实证，逐项）

- 8642 `/v1/health` → ok、version 0.23.0；9119 → 302（Dashboard 登录跳转，正常）。
- 容器内回读哈希：api_server.py / device_gateway.py / device_sync.py 三件与包钉值一致。
- `/api/device-bridge/health`（免钥，回环与公网各一）→ `{ok:true, service:"device-bridge", sessionOnline:false}`，与退役前桥 health 逐字一致。
- `/api/device-mcp` tools/list（回环与公网各一）→ **53 个工具、与基线名单逐名相同**；无钥 → 401。
- 全环冒烟（假会话）：注册 201 → device_status 在线 → device_info 经 poll/respond 实时全环返回 → disconnect → 离线如实 device_offline。
- 同步面对账：五数据集计数与退役前基线全等（contacts 0 / calendar 20 / reminders 1 / photos 1237 / motion 16），auth_range 全等；synced_at 统一由 16:01 前进到 17:35（停机前桥侧一次统一状态触碰，计数未变，非迁移丢失）。
- OneDay 关键读面（8642）：台账 200（500 条）、动态 200（27 条）、目标 200（41 条）；capabilities 三位 oneday_bridge/overview_bridge/device_bridge 全 true。
- verify.sh 全量：**84 齐 / 0 缺**，第 26 节八探针（companion-retired、双哈希、8647 无监听、device health、tools=53、能力位、config 指网关）全绿。
- 残留引用清查：hermes compose 与 nginx vhost 对 `8647` 均 **0 命中**；companion 容器不存在（docker ps -a 无）。
- 整机内存应用后 3897/7725 ≈ 50.4%（companion 释放约 97MiB）。

## 已知后果（批五抢跑批四，用户令下接受）

- **identity（8648）与 front 伴生面板（8650）随 companion 下线暂停**：其 nginx location 按本批范围未动、upstream 已死呈 502，待批四应用入关后恢复。末代 companion 注册表仅四模块（device/identity/front/fileproc），box 不在其中、无连带（App 电脑面走 Hermes 侧 Box MCP，不受影响）。
- fileproc 桥口（8652）随容器消失，其职能自批一起即在网关 fileproc_gateway，零影响；旧文件桥代码路径至此全退役（回滚源在基线内，按用户令不留观察窗）。
- 网关启动瞬间 hermes 内 MCP 客户端连 8642 未就绪会把 device 条目 park、按需重连——与既有各 MCP 服务器同一既有口径，非本批新问题。
- 原 device-bridge 数据目录 `/www/dk_project/dk_app/device-bridge/data/` 留盘未删（迁移源，回滚可用），无任何挂载再指向它。

## 回滚法

1. 数据：停 hermes 后以基线 device-bridge-data 快照覆回 `/www/dk_project/dk_app/device-bridge/data/`（或直接用留盘的迁移源目录，其内容即停机时最新态）。
2. companion：基线 companion-docker-compose.yml 与 companion.env 覆回 `/www/dk_project/dk_app/companion/`，镜像用 `oneday/companion:pre-2.0.0-baseline` 标签，`docker compose up -d` 拉起。
3. 网关：基线 patches-api_server.py 覆回部署目录 patches/、删 device_gateway.py/device_sync.py 两新文件、hermes compose 与 config.yaml、nginx vhost 各以基线覆回，服务级 `docker compose up -d hermes`＋`nginx -s reload`。
4. 复验：8647 health/tools=53 恢复、8642 health ok、verify.sh 回到 1.23.0 口径（用基线包或 git 旧版脚本）。
