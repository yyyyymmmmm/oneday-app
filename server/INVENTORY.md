# 现行部署盘点（INVENTORY）

- 盘点时间：2026-11-22 约 13:15–13:30 CST
- 盘点对象：118.24.41.52，部署目录 `/www/dk_project/dk_app/hermes/`（compose 项目 `hermes`）与 `/www/dk_project/dk_app/companion/`（compose 项目 `companion`）
- 方法：全程只读（docker ps/inspect、sha256sum、cat、curl 本机回环探针）；未改任何文件、未重启、未应用补丁
- 盘点前内存实测：used 4338 / total 7725 MB ≈ **56%**，未触 80% 红线

## 1. 容器（运行态实查）

| 容器 | 镜像 | 状态 | 端口（均绑 127.0.0.1） | 作用一句话 |
|---|---|---|---|---|
| hermes | nousresearch/hermes-agent:v0.23.0 | Up 41h | 8642（网关 API）、9119（Web/Dashboard） | Hermes 本体，`gateway run`；版本与部署包 target 一致 ✔ |
| oneday-companion | oneday/companion:1.0.66 | Up 6d | 8643、8644、8646–8650、8651→8652 | OneDay 伴生服务：写闸/总览/设备/身份等模块的实际承载者 |

同宿其他容器（onenav、vaultwarden、newapi、metacubexd、uptime-kuma、allinssl、epay-mysql、openmuse）与本产品行为面无关，不在本包范围。

## 2. 补丁三件（产品行为核心，已收编入包 patches/，哈希逐一对齐）

| 文件（宿主） | 容器目标路径 | 大小 / mtime | sha256 | 作用一句话 |
|---|---|---|---|---|
| patches/api_server.py | /opt/hermes/gateway/platforms/api_server.py | 248,609 B / 2026-11-20 19:52 | `67359f294dd021487a821fb2503cf50b8eff2ac60a086f13e5fa024a2fed50fd` | 网关面：配对认领端点、反应写入端点、网关面 reactions 投影（对上游 diff 407 行） |
| patches/web_routers_sessions.py | /opt/hermes/hermes_cli/web_routers/sessions.py | 51,959 B / 2026-11-20 19:49 | `fe83de2e1cf48e0b38bb14c7bea530d7f2f0d38aefe60a7c3b117aeb93c21c15` | Web 面：历史消息 reactions 字段投影（对上游 diff 43 行） |
| patches/hermes_state_portability.py | /opt/hermes/hermes_state_portability.py | 55,099 B / 2026-11-18 15:09 | `6a93ecc83a8b5f059978bd3f2db1d63ea8a2ec30a5790028c89ec90c5b2a1d0c` | 状态层：会话导入撞 id 时的身份收养 `_adopt_session_identity`（对上游 diff 109 行） |

- 挂载方式：三件均为单文件 bind mount、`:ro`（docker-compose.yml 第 12–14 行＋docker inspect 双证）。
- **容器内回读哈希与宿主、与包内副本三方一致**（2026-11-22 docker exec sha256sum 实测）——补丁确实在运行容器生效，非假绿。
- 上游原版基线同目录留存：`*.orig`（api_server.py.orig sha256 `73175d66…`、web_routers_sessions.py.orig `542496f4…`、hermes_state_portability.py.orig `3eca7253…`），另有各代 `.bak-*`（pairing/reactions/metavalue 等），为回滚与升级对账资产，不入包。
- run 幂等（run_idempotency）经 diff 核对为**上游 v0.23.0 自带机制**（.orig 已含），不归补丁承载，注册表里如实标注。

## 3. compose 与服务定义

- 现行文件：`/www/dk_project/dk_app/hermes/docker-compose.yml`（2,319 B，mtime 2026-11-18 14:27；历史 .bak 最新 20261118）。
- 定义三服务：`hermes`（在运行）、`write-gate-bridge`、`overview-bridge`。
- **⚠️ 定义与运行态不一致（盘点发现）**：`write-gate-bridge` / `overview-bridge` 两服务**无对应容器**（docker ps -a 无此二名）；其端口 8643/8644 现由 oneday-companion 监听并应答（401 鉴权）。即 hermes compose 中这两段是 **legacy 定义**，宿主脚本仍在部署目录（write_gate_bridge.py sha256 `9f3d6a2a…`、overview_bridge.py sha256 `ebc1e72f…`，均 2026-11-10 后未变），但已不承载线上行为。包内模板已标注 legacy，新部署勿启用。
- hermes 服务关键定义：`./data:/opt/data` 数据挂载；环境开关 HERMES_DASHBOARD=1、API_SERVER_ENABLED=true；mem_limit 2g、shm 1g。凭据类环境变量共 4 项（Dashboard 密码/密钥/会话令牌、API_SERVER_KEY），只记键名，值不落盘（模板见 services/）。

## 4. companion（伴生服务）

- 部署：独立 compose 项目 `/www/dk_project/dk_app/companion/docker-compose.yml`，镜像 `oneday/companion:1.0.66`（COMPANION_API_LEVEL=1），mem_limit 1g，接外部网络 hermes_default。
- 挂载：hermes data（rw 与 ro 双挂）、overview-data、oneday-bridge/data、device-bridge/data、identity-bridge/data、companion-state、companion.env（单文件挂入）。
- 模块开关（companion.env 键名实查）：MODULE_WRITEGATE / OVERVIEW / BOX / ONEDAY / DEVICE / IDENTITY / FRONT_ENABLED；端口键：WRITE_GATE_PORT、OVERVIEW_PORT、ONEDAY_PORT、DEVICE_PORT、CHANNELS_PORT、FILEPROC_PORT。8646–8650 与 8651→8652 各模块的逐路对应**未逐项复核**（未读 env 值、未做鉴权后深探），注册表按「监听在位、深行为未验」登记。
- 探针实测：8643、8644 对 `/` 与 `/health` 均回 **401**（服务在位且鉴权生效）；深行为探针需桥 key，本轮未做。

## 5. 配置（产品行为面，只记结构）

- 主配置：`data/config.yaml`（部署目录下 data/，挂入容器 /opt/data）；同目录有 auth.json、gateway_state.json、kanban.db、cron/、enrollment/、pairing/ 等运行态数据，均属 instance 数据，不入包。
- 顶层键（34）：_config_version、database、runtime、attachments、plugins、model、kanban、cron、terminal、browser、tool_loop_guardrails、compression、prompt_caching、memory、max_concurrent_sessions、group_sessions_per_user、hosted_rooms、streaming、skills、agent、gateway、platform_toolsets、mcp_servers、stt、code_execution、delegation、display、telemetry、auth、updates、auxiliary、tools、providers、tts。
- 与产品行为直接相关的二级结构（键名实查，值未落盘）：
  - `model`：api_mode、base_url、default、provider；`providers`：Ailey、Gateway（两提供方）。
  - `mcp_servers`：device、github、identity、notion、oneday-automation、oneday-goals、oneday-sessions（7 个 MCP 面）。
  - `gateway`：含 api_server、delivery_ledger、multiplex_profiles、profile_routes、write_sessions_json 等 28 个二级键；**无 command_allowlist 键**（与批次备料结论一致）。
  - `memory`：含 write_approval；`skills`：含 write_approval（写闸审批在配置层的开关面）。
  - `agent`：max_turns、reasoning_effort、service_tier 等；`platform_toolsets`：cli、discord、qqbot、signal、slack、telegram、whatsapp、yuanbao。
- env 文件（只记键名，值未读未落盘）：部署目录 `write-gate.env`（WRITE_GATE_BRIDGE_KEY）、`overview-bridge.env`（HERMES_API_KEY、OVERVIEW_BRIDGE_KEY、WRITE_GATE_BRIDGE_KEY）；companion 目录 `companion.env`（约 50 个键，含各模块 key/端口/开关与第三方 API key 键名，全表见 services/env.template）。

## 6. 本轮探针基线（只读实测，详见 verify-baseline-20261122.txt 与报告）

- GET 8642 /v1/health → `{"status":"ok","platform":"hermes-agent","version":"0.23.0"}` ✔
- GET 8642 /v1/enrollment/claim → 405（路由在位）✔；GET /v1/reactions/{sid}/1 → 405 ✔；GET /v1/runs → 405 ✔
- reactions 行为投影（8642 面）：扫 15 会话 / 349 条消息，1 条带 reactions 键且非空——投影在行为层在位 ✔
- 9119：`/` → 302（Dashboard 在位）；/api/sessions 需登录 cookie（`no_cookie`），本轮两种登录姿势未拿到 cookie，**9119 面 reactions 投影行为未验**（代码哈希已对齐，行为待后续以正式登录流补验）
- 8643/8644 → 401（在位＋鉴权）✔

## 7. 未验事项（明示）

1. 9119 面 reactions 投影的行为级验证（需 Dashboard 登录 cookie 流）。
2. companion 8646–8652 各端口与模块的逐路对应及鉴权后深行为。
3. 公网入口（nginx 反代 example.com 面）本轮未查，不在本次盘点口径内下结论。
4. 本地工作区根目录另有一份 `docker-compose.yml`（2026-11-09 旧副本，1,956 B），与服务器现行版不一致，**勿当现行定义使用**；包内模板以服务器现行版为准。
