# AI 内部权限地基包报告：P0 留痕底座（桥侧）＋P3 目标门面（2026-11-13）

## 结论先行

**已施工、已部署、已验活。** 伴生升 **1.0.39**：oneday 桥新增 P0 留痕底座（`/traces` 写入/读取接口＋五要素数据契约）与 P3 目标门面（`/mcp` 四个 goals 工具，每个调用先落留痕再回执）。门面**未注册进 Hermes**——交付状态＝「门面就绪待注册」，注册按既定口径等收官窗口一次办。Hermes 全程未动、未重启，StartedAt 逐字未变；App 仓库未碰；生产真数据只读，验证用测试目标已删净。

规格依据注记：审计档 `ai-internal-powers-audit-20261113.md` 磁盘副本止于 §2.2（与深审档同类的截断），P0/P3 两节不在盘上；本包规格以派工简报＋主线盘点结论（13:22 回报口径）为准，五要素按简报原文落：**动作名／对象点达／时间／结果／失败原样呈现**。

## 一、做了什么

全部改动只在一个文件：`modules/oneday_bridge.py`（部署后 md5 `c0d61076086778b75aa9e4e33a63db33`，工作区副本与生产逐字一致）。

### P0 留痕底座（桥侧）

- **存储**：复用 oneday 桥既有数据面——`data.json` 新增 `traces` 集合，与 goals/ideas 同一套原子写（tmp+replace、0600）、同一把锁、同一降级纪律（数据文件损坏时全桥只读，留痕写入同样被总闸 503，不存在绕过降级的写入路径）。软保留上限 5000 条，超限删最旧（留痕是回响流，不是档案库）。
- **数据契约**（一条留痕的全部字段）：

| 字段 | 含义 | 纪律 |
|---|---|---|
| `id` | `trc_<hex>` | 桥生成 |
| `action` | 动作名（命名空间式，如 `goals.create`、`identity.rename`） | 必填 |
| `actor` | 执行者，默认 `agent`，可 `system`/`user` | — |
| `target` | 对象点达：`{kind, id, label, ref}`，ref 为 App 可解析的深链串（如 `oneday://goals/<id>`） | kind 必填，其余可空串 |
| `at` | 时间（epoch 秒，本桥全线house格式） | 缺省服务器当下 |
| `status` | `ok` / `failed` | 只此两值 |
| `result` | 结果摘要（人话一句，上限 500 字） | **ok 必填**，门口拒收无果之痕 |
| `error` | 失败原文（上限 2000 字，超长截断保头） | **failed 必填**，原样不转述 |
| `detail` | 可选对象（工具名等结构化补充） | 必须是对象 |

- **失败与成功同级**：失败留痕没有 error 原文一律 400 拒收；门面内部的留痕写入若自身失败，异常直接上抛（stderr 留大声标记），不存在静默吞。
- **复用面**：P1（身份）/P2（会话）/P4（自动化）/P5（触达）后续只需以自己的 action 命名空间调 `POST /traces`（或同进程 `_append_trace`），契约不变。本包自检已用一条 `identity.rename` 形状的通用留痕试写通过，证明底座不绑目标域。

### P3 目标门面

- **形态**：与 device 桥 `/mcp` 同形的 streamable-http JSON-RPC 门面，挂 oneday 桥 8646 的 `POST /mcp`，同一把桥钥鉴权（fail-closed 不变）。支持 initialize / ping / 通知（202）/ tools/list / tools/call；未知方法回 JSON-RPC -32601。
- **四个工具**（逐个接 P0 留痕，成功失败都记、记完再答）：

| 工具 | 动作 | 留痕 action |
|---|---|---|
| `goals_list` | 列目标，可按 status 过滤 | `goals.list` |
| `goals_create` | 建目标，写死 `source="chat"`（审计定的契约，App 按「对话所生」呈现） | `goals.create` |
| `goals_add_entry` | 写进展，写死条目 `source="agent"` | `goals.add_entry` |
| `goals_update` | 改标题/备注/状态 | `goals.update` |

- 门面执行体直接复用 REST 同一份内部函数（`_create_goal`/`_create_entry`/`_patch_goal`/`_list_goals`），校验与错误原文与 REST 逐字同源，不另起第二套逻辑。

## 二、接口清单（8646，Bearer 桥钥）

- `POST /traces` → 201 trace；五要素门口校验（ok 无 result / failed 无 error / status 非法 / target 缺 kind → 400）
- `GET /traces` → `{"items":[...]}` 最新在前；过滤 `?action=&status=&targetId=&since=<epoch>&limit=N`（默认 100、上限 500）
- `GET /traces/{id}` → trace；不存在 404
- `POST /mcp` → JSON-RPC 门面（如上）；非 POST 405
- 既有 REST 全部不变（自检含 goals REST 建/删回归各一条）

## 三、留痕样例（生产实测原样，第一批真留痕）

成功一条（验证时经门面建测试目标所留，目标已删、痕在）：

```json
{"id": "trc_7ae2a3dc90ea", "action": "goals.create", "actor": "agent",
 "target": {"kind": "goal", "id": "g_915e0a05474d",
            "label": "AI权限地基验证·20261113",
            "ref": "oneday://goals/g_915e0a05474d"},
 "at": 1794547932.6067934, "status": "ok",
 "result": "已创建目标「AI权限地基验证·20261113」",
 "error": null, "detail": {"tool": "goals_create"}}
```

失败一条（给不存在的目标写进展，错误原文与桥的拒绝逐字一致）：

```json
{"id": "trc_e757ea34a8ac", "action": "goals.add_entry", "actor": "agent",
 "target": {"kind": "goal", "id": "g_nope_missing", "label": "",
            "ref": "oneday://goals"},
 "at": 1794547932.6240575, "status": "failed",
 "result": null, "error": "目标不存在",
 "detail": {"tool": "goals_add_entry"}}
```

## 四、测试证据

- **新自检** `tests/oneday_bridge_traces_mcp_selftest.py`（34 项，已登记进 `run_bridge_selftests.sh`）：**34/34 全过**——含鉴权 401、握手四件、门面端到端（source=chat / source=agent 双契约）、三类失败回执、留痕五要素与逐字失败原文、每调必留一条的计数对账（8 调 8 痕）、通用留痕试写、门口五项拒收、REST 回归、**重启后留痕不丢**（data.json 往返）。
- **全套回归对跑定责**：全套自检中 p3 有 1 条 FAIL、rendition 整套 FAIL；把生产 1.0.38 **原版文件**（md5 与部署前逐字一致）同法对跑，**两处失败签名与改后完全相同**（p3 同一条 tier/hour 门检查、rendition 同一族 503——后者是本开发机内存口径触发的桥内繁忙保护）→ 均为既有问题，**本包零新增回归**；其余全套（overview/p2/p4–p9/device/write-gate 三套/device-sync/spreadsheet/delivery 等）全绿。

## 五、部署与验活（叠层法，沿 1.0.38 先例）

- 构建：服务器 `/root/aipowers-1039/`（Dockerfile＋新 oneday_bridge.py 留底），`FROM oneday/companion:1.0.38`＋COPY 单文件 → `oneday/companion:1.0.39`。未用已过期的 companion-build 目录。
- 配置两处：`docker-compose.yml`（image＋COMPANION_VERSION→1.0.39）、`companion.env`（COMPANION_VERSION→1.0.39）；`docker compose up -d` 重建伴生容器。无新增环境变量、无 modules.json 改动、无 supervisor 改动。
- 五层对齐验收：

| 层 | 实测 |
|---|---|
| 镜像 | 运行容器 image＝`oneday/companion:1.0.39` |
| compose | image 与 COMPANION_VERSION 均为 1.0.39 |
| companion.env（宿主机） | COMPANION_VERSION=1.0.39 |
| 进程 environ | supervisor(pid 1) COMPANION_VERSION=1.0.39（oneday 模块按其 env_from 本就不带此键，与 1.0.38 布局一致；桥钥从其进程 environ 实取成功） |
| 模块起服 | supervisor 日志六模块全 started；box/oneday/device /health 200、front / 200；writeGate/overview 的 /health 401 系其既有钥匙门（日志 listening 正常，非本包触碰面） |

- 接口/数据层验收（容器内直调 8646，钥匙只在服务器内从桥进程 environ 取、未出服务器未打印）：initialize 回 `oneday-goals`；tools/list 恰四件；goals_create→source=chat、goals_add_entry→source=agent；伪造目标写进展→isError 且 error＝「目标不存在」；GET /traces 得 4 条（建/写/败/列各一）；删测试目标后回读 data.json：**goals 回到 1（仅存量「吃东西」，未动）、entries 0、traces 4 条留存**。
- 红线核对：Hermes StartedAt 部署前＝部署后＝`2026-11-10T14:21:47.024396739Z`；未改 mcp_servers、未重启任何服务（伴生容器按自动部署口径重建属本包范围）；服务器内存全程约 57%（4383–4412/7725 MB）。

## 六、回滚基线

- 旧镜像保留：`oneday/companion:1.0.38`。
- 配置备份（服务器 `/www/dk_project/dk_app/companion/`）：`docker-compose.yml.bak-1.0.38-20261113`、`companion.env.bak-1.0.38-20261113`。
- 数据备份：`/www/dk_project/dk_app/oneday-bridge/data/data.json.bak-aipowers-20261113`（部署前快照：goals 1 / entries 0 / 无 traces 键）。
- 回滚动作：恢复两配置备份 → `docker compose up -d` 回 1.0.38。**注意**：1.0.38 的 `_load` 不认 `traces` 键，其首次保存会把留痕集合丢弃——若回滚时要保住上线后产生的留痕，先导出 data.json 的 traces 段（或整文件留档）再回滚；目标等真数据不受此影响（键集是其子集）。

## 七、待收官窗口注册清单（本包不做，届时一次办）

1. **网关路由**：给门面一条公网/内网可达路径（参照 device 的 `/api/device-mcp` 式 nginx 路由，如 `/api/oneday-mcp` → `127.0.0.1:8646/mcp`），或按 Hermes 所在网络直连 8646——注册时二选一并实测。
2. **mcp_servers 新增条目** `oneday-goals`（或并入既有命名口径），指向上述路径，钥匙走既有单钥网关/桥钥分发，不新发明凭据。
3. **重启 Hermes 一次**完成注册生效（用户 13:26 已授权「要重启，你重启就行」），同窗合并：设备桥 53 件复验、9B goals_create（本门面即其桥侧实体）、辅助模型写回热生效实测；PAT/GitHub 存了 Bitwarden 就同窗办、没存跳过不阻塞。
4. 注册后验收口径：AI 在真会话里调 goals_create 建目标 → App 目标页可见（source=chat 呈现）→ GET /traces 有同 id 留痕，三点齐才算通。
5. App 侧回响渲染（主线/旁聊里的回响卡）在 P2 线，本包只保证服务端数据契约稳定先行。

另注：工作区 `Dockerfile`/`docker-compose.yml` 模板的版本字面仍停在 1.0.37（自 1.0.38 起即如此，服务器侧文件为版本真源）——本次沿先例未动模板，仅在此记一笔，防后人误用工作区模板构建。
