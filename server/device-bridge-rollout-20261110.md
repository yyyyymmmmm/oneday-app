# device-bridge 预建记录（2026-11-10）

性质：桥侧骨架预建＋mock 自测。**未注册进 Hermes 配置、未动 nginx、未动任何现行服务**（hermes/write-gate/overview/box/oneday 五个现行容器零接触）。设计依据：oneday-design-review/device-connectors-design-20261110.md（14:51 定版工具调用制）。

## 落位

- 服务器目录：`/www/dk_project/dk_app/device-bridge/`（device_bridge.py、docker-compose.yml、device-bridge.env、data/）
- 容器：`device-bridge`，镜像 nousresearch/hermes-agent:v0.23.0，`127.0.0.1:8647->8647`，mem_limit 256m，restart unless-stopped
- 密钥：device-bridge.env 只含 `WRITE_GATE_KEY` 一行（自 hermes/write-gate.env 服务器内提取，与四桥共用同一把 Bearer；值未出服务器）
- 本地档：hermes-deploy/device_bridge.py、device-bridge-docker-compose.yml、device-bridge-nginx-draft.conf（草案未生效）、device_bridge_selftest.py
- 部署前后内存：51.5% → 51.8%（红线 80% 内）

## 形态（与既有四桥对齐＋本桥新面）

- stdlib ThreadingHTTPServer 单文件桥；/health 免鉴权，其余全路由 Bearer、密钥未设时 fail-closed
- MCP 门面 `POST /mcp`（Streamable HTTP JSON-RPC：initialize/ping/tools/list/tools/call），工具 10 个：device_status（桥本地应答）＋读 5（calendar_list_events、reminders_list、contacts_search、health_daily_summary、home_status）＋写 4（calendar_create_event、calendar_update_event、reminders_create、reminders_complete，均带 idempotencyKey）
- 设备会话通道（REST）：POST /device/session（注册顶替旧会话）、POST /device/heartbeat、GET /device/poll（长轮询 ≤25s）、POST /device/respond、POST /device/disconnect；会话以最近心跳/poll ≤45s 判在线
- 调用引擎：离线→`device_offline`（零数据）、未授权→`permission_denied`（不惊动手机）、未提供工具→`tool_unavailable`、全程超时 30s（可配）→`device_timeout`，错误全结构化
- 写幂等：桥侧 write-keys.json（key→objectId，0600）同 key 重放不转发；App 侧 24h key 集为第二层（App 批次实现）
- 审计：data/audit.jsonl（0600），每调用一行元数据（ts/callId/tool/status/durationMs/errorCode/objectId），**不记参数与结果内容**；数据目录只有 audit.jsonl＋write-keys.json 两文件，无设备数据落盘（已查证）

## 自测证据（mock 设备整环，2026-11-10 15:00，容器重建后复跑）

`device_bridge_selftest.py` 11 项全 PASS（SELFTEST ALL PASS, exit=0）：

1. /health 免鉴权 200；设备通道无 Bearer → 401
2. MCP initialize 回 serverInfo=device-bridge；tools/list 全 10 工具
3. 注册前 device_status online=false；离线调 calendar_list_events → isError `device_offline`、无数据
4. mock 注册会话（health=denied，其余 granted）后 device_status online=true（含授权态全图）
5. calendar_list_events 整环：门面→桥队列→mock 长轮询领取→现读回 MOCK-EVENT-1＋readAt→门面返回（审计 durationMs=1、callId=call-cb21096bc6d6）
6. health_daily_summary（denied）→ `permission_denied` 且 <5s 返回（未转发手机）
7. calendar_create_event 同 idempotencyKey 连发两次：mock 实际执行 1 次，第二次回 idempotentReplay＋原 objectId
8. mock disconnect 后 reminders_list → 再次 `device_offline`
9. 泄漏查证：audit.jsonl 与 write-keys.json 中 grep "MOCK" 命中 0（数据内容零落盘）

## 待批/待办（App 批次接线前）

- nginx 两条路由启用（草案 device-bridge-nginx-draft.conf：/api/device-bridge/ 给 App、/api/device-mcp 给 Hermes 门面）＋Hermes config 注册 url 型 MCP 一条——生产变更，与批一 App 施工同批报批
- App 侧（P1 之后批次）：EventKit/Contacts 读取器与写执行器、设备会话客户端（注册/长轮询/回执）、逐件权限与「允许智能体调用」开关、App 侧 24h 幂等 key 集与回读验证
- 批二开工前：健康/家庭签名权益核查（付费开发者账号到位则自动解除）；APNs 到位后重估「App 在线」边界

## 回滚

`cd /www/dk_project/dk_app/device-bridge && docker compose down` 并删目录即净退；未注册未路由，无其他系统受影响。

## 追记 2026-11-10 16:4x：公网路由启用（OneDay 0.34.0 批一）

- nginx `hermes.example.com` 新增 `location /api/device-bridge/` → 127.0.0.1:8647，照 0.33.1 单钥入口同形（auth_request→8642 /v1/models 验 Hermes 登录钥→注入 DEVICE_BRIDGE_KEY 字面值，钥在服务器内从容器 env 直读直注）；proxy_read_timeout 120s＋proxy_buffering off。**严格单钥、无双模**（本桥唯一客户端是 0.34.0 App）。`/api/device-mcp` 未启用——与 Hermes config 注册同留收官窗口。
- 备份 hermes.example.com.conf.bak-20261110-devicebridge（0600）；nginx -t 过后 reload；内存 51.6% 前后不变。
- 公网验矩阵全绿：health 登录钥 200／错钥 401／无钥 401；会话全环冒烟（session 201→poll {call:null}→heartbeat ok→disconnect ok，断后 sessionOnline=false）。
