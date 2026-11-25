# 总览桥（overview-bridge）上线记录（2026-11-09）

授权：用户 2026-11-09 14:39 拍板「根据他的 UI 做我们的 Hermes」方向，14:42 点选「按蓝图开第一期：五格壳＋总览桥＋活动格」。本桥为第一期服务端部分，契约与 App 侧冻结共用一份（字段名不得改）。
目标机 118.24.41.52；hermes 本体配置零改动、未重启；既有 12 个容器一个未碰（终态 13 个，新增仅 overview-bridge）。

## 形态（照 write-gate 桥先例）
- 容器 `overview-bridge`：同镜像 nousresearch/hermes-agent:v0.23.0，entrypoint 直跑 `/opt/bridge/overview_bridge.py`（纯 stdlib 单文件，脚本原件存本目录 `overview_bridge.py`，md5 9eae3eb627c136dd3c68bef56bd5a0be），restart unless-stopped，mem_limit 256m。
- 端口：宿主机仅绑 127.0.0.1:8644（勘察时该端口空闲）。
- 挂载：`./data:/opt/data:ro`（只读，仅读 write-gate/decisions.jsonl）、脚本只读挂载、`./overview-data:/opt/overview-data`（桥自身状态 state.json：通知表＋jsonl offset＋已处理行哈希）。
- 网络：与 hermes、write-gate-bridge 同 compose 网络（hermes_default），容器内以服务名直连 `hermes:8642` 与 `write-gate-bridge:8643`。
- 鉴权：复用 write-gate 桥同一把钥匙——compose env_file 直接共用 `./write-gate.env`（WRITE_GATE_KEY），未新造第二把；钥匙未设置时桥 fail-closed 拒绝启动。另 `./overview-bridge.env`（0600）只含 HERMES_API_KEY 一项（值＝网关 api_server_key，施工时在服务器本地从 compose 提取生成，未经聊天/日志 transit），供桥调 /api/sessions 用。
- nginx：hermes.example.com 站点新增一段 `location /api/overview-bridge/` → `proxy_pass http://127.0.0.1:8644/;`（带尾斜杠剥前缀，透传 Authorization），对外基址 https://hermes.example.com/api/overview-bridge。

## 字段口径（实查定案）
- `hermesUp`：GET hermes:8642/health == 200。（/api/status 在 8642 实查 404，不存在，不用。）
- `activeSessions`：GET /api/sessions?limit=500（Bearer 网关钥）返回 data 中 `ended_at` 为空的条数。实查 16 条会话 ended_at 全部为空（Hermes 未给这些会话写结束标记），故当前口径数值上等同服务端会话总数 16；口径定义不变，后续若 Hermes 开始写 ended_at 本数自动收窄为「未结束会话数」。
- `pendingApprovals`：write-gate 桥 GET /status 的 counts（memory＋skills），与桥自身同口径，经 compose 内网以同一把桥钥匙查询。上线时实测 0。
- `unreadNotifications`：本桥通知表未读数。
- 通知来源（一期仅此一种）：增量读 data/write-gate/decisions.jsonl（5 秒轮询），新增 approved/rejected 行生成 kind="write_gate_decision" 通知，title 按子系统×裁决译中文（记忆/技能写入已批准 / 已被驳回），body 用该行 summary（缺失时回落人话句）。offset＋行 sha1 哈希持久化，重启不重复生成；文件被截断时从头重扫、靠哈希去重。**首启口径**：offset 初始化为当时文件末尾——上线前已有的 4 条历史已决（今晨 write-gate 验收记录）不补发通知（它们已在 App 审核段可见），只通知上线后的新裁决。

## 验收证据（全部实查）
- 本机 127.0.0.1:8644：GET /overview → 200 `{"hermesUp": true, "activeSessions": 16, "pendingApprovals": 0, "unreadNotifications": 0, "generatedAt": "2026-11-09T06:47:26Z"}`（字段与冻结契约逐个对齐）；GET /notifications → 200 `{"items": []}`；无 Bearer → 401；错 Bearer → 401；POST 未知 id /read → 404。
- 公网 https://hermes.example.com/api/overview-bridge/overview → 200 同载荷；/notifications → 200；无 Bearer → 401。
- 通知全链：向 decisions.jsonl 按 write-gate 同格式追加一条测试已决行（id=ovtest01、memory/approved）→ 约 5 秒内 GET /notifications 出现条目（id wg-bddf5eee83fd、kind=write_gate_decision、title=「记忆写入已批准」、read=false），/overview unreadNotifications 0→1；POST /notifications/wg-bddf5eee83fd/read → `{"ok": true}`，未读回 0、该条 read=true。
- 测试数据清理（已完成并注明）：停桥后删除 decisions.jsonl 中 ovtest01 行并删除桥状态文件（重启按首启口径重建），decisions.jsonl 回到 4 行、md5 与测试前基线一致（969fdb2c56d00b43e5048d61673cbaa9）；重启后通知仍为空、未读 0。再做一次 compose restart 复验：持久化状态加载正常、无重复生成、日志只有 method/path/status 行。
- 内存：施工前 used 3735/7725 MB ≈ 48.3%；完工后 3760/7725 ≈ 48.7%（增量即新容器自身）。全程远低于 80% 红线。容器数 12 → 13；hermes（Up 11h）、write-gate-bridge（Up 3h）、openmuse 等既有容器 uptime 未变、未重启。

## 基线与备份（回滚锚点）
- 服务器项目目录 /www/dk_project/dk_app/hermes：`docker-compose.yml.bak-20261109-overview`（加服务段前）；nginx conf 备份 `/www/server/panel/vhost/nginx/hermes.example.com.conf.bak-20261109-overview`（加 location 前）。
- 本地 hermes-deploy 副本已同步：docker-compose.yml 追加 overview-bridge 服务段、hermes.example.com.conf 追加 location 段、overview_bridge.py 原件在册。overview-bridge.env 与 write-gate.env 不在本地留副本，迁移/重建时分别按 credentials.txt 的 api_server_key 与 write_gate_key 重新生成。

## 回滚一键步骤
1. `cd /www/dk_project/dk_app/hermes && docker compose stop overview-bridge && docker compose rm -f overview-bridge`；
2. compose 删 overview-bridge 服务段（或还原 docker-compose.yml.bak-20261109-overview），删 overview_bridge.py、overview-bridge.env、overview-data/；
3. nginx 删 /api/overview-bridge/ location 段（或还原 conf 备份）→ `nginx -t && nginx -s reload`，公网验该路径回落 Dashboard 兜底；
4. 终态核对：容器数回 12、8644 无监听、hermes 与 write-gate-bridge 状态不变、decisions.jsonl md5 仍为 969fdb2c56d00b43e5048d61673cbaa9。

## 增补（2026-11-09 晚）：第二轮询源——监测变化通知账本（P6 收尾）

背景：oneday-bridge 的监测引擎在变化命中时按同口径往其数据目录写 append-only 的 `monitor-notifications.jsonl`（记录形状 `{id:"mon-…", kind:"monitor_change", title:"监测有变化：<名>", body:summary, createdAt:ISO-Z, read:false}`，见 oneday-bridge 上线记录监测节），当时 overview 不读该账本、监测变化不进 /notifications。本包给 overview 加第二个轮询源，两源并入同一通知表。

- **路径解法（与 decisions 同办法）**：宿主机账本路径 `/www/dk_project/dk_app/oneday-bridge/data/monitor-notifications.jsonl`；overview 的 compose 新增只读 bind mount `/www/dk_project/dk_app/oneday-bridge/data:/opt/oneday-data:ro`，脚本以 env `MONITOR_PATH=/opt/oneday-data/monitor-notifications.jsonl` 定位（脚本内默认同值）。动手时该账本文件尚不存在（oneday 侧验收后整文件已删、无真实监测落账），桥对缺文件按源 no-op、文件出现后自 offset 起读。
- **脚本改动**（overview_bridge.py，md5 `9eae3eb6…` → `a7569a9ce196d310260ab5939292a3f8`，本地原件已同步）：轮询泛化为双源——每源独立 offset（`offset`/`mon_offset`）＋独立行哈希集（`seen`/`mon_seen`），同一把状态锁、同一 5 秒轮询、同一 seq 排序；监测记录的 id/kind/title/body/createdAt **原值透传**（缺 id 时回落 `mon-`＋行哈希前 12 位），read 由本桥状态维护（账本里的 read 字段不读）。**基线纪律与 decisions 一致**：state.json 已存在但无 mon 键时（本次生产的实际情形）按「源首启」处理——mon_offset 置当时文件末尾、既有行哈希入 mon_seen、历史不补发，decisions 的 offset/seen/通知表原样不动；全新首启则两源同此办理。文件被截断时该源 offset 归零重扫、靠哈希去重（与 decisions 同语义）。上线前本地已做三阶段自测（全新首启基线/旧 state 迁移/双源各追加一行/重复轮询不重发/账本缺文件容错）全过才动生产。
- **生产迁移实查**：重建后 state.json 自动长出 `mon_offset: 0, mon_seen: []`（账本缺文件故基线为 0），decisions offset 仍 1283、4 个 seen 哈希与通知表（空）分毫未动；容器内 `ls /opt/oneday-data` 可见 oneday 数据目录，挂载生效。
- **备份（服务器 /www/dk_project/dk_app/hermes 内）**：`overview_bridge.py.bak-20261109-monitorsrc`（md5 与改前原件一致 9eae3eb6…）、`docker-compose.yml.bak-20261109-monitorsrc`、`state.json.bak-20261109-monitorsrc`（改前状态快照）。部署只重建 overview-bridge 一个容器（`docker compose up -d overview-bridge`），其余 14 容器未碰，hermes 本体与 config 零接触。
- **验收证据（全部实查，本机 127.0.0.1:8644＋公网各验）**：动手前基线 /overview unread=0、/notifications 空。①监测链：往账本追加一条测试变化记录（id=mon-ovtest110901、title=「监测有变化：验收测试页」、body=「总览桥监测源验收测试变化摘要（ovtest）」）→ 一个轮询周期内 GET /notifications 出现该条，id/kind/title/body/createdAt 与账本原值逐字一致、read=false，/overview 未读 0→1；POST /notifications/mon-ovtest110901/read → `{"ok": true}`，未读回 0、该条 read=true。②decisions 回归：往 decisions.jsonl 追加测试裁决行（id=ovtest02、memory/approved）→ 生成 kind=write_gate_decision、title=「记忆写入已批准」通知，与监测条同表按时间倒序，标题映射与未读计数无回归。③终态：本机与公网 /notifications 均空、未读 0、无 Bearer 仍 401。
- **测试数据清理（已完成并注明影响面）**：停桥后删除 decisions.jsonl 中 ovtest02 行（md5 回基线 `969fdb2c56d00b43e5048d61673cbaa9`、4 行）；监测账本为本次验收新建（动手前不存在、无真实数据），整文件删除，oneday 数据目录回到动手前原样（仅 data.json 与其备份）；桥 state.json 以改前快照复原 decisions 侧并补 mon 基线（mon_offset=0、mon_seen=[]、notifications 空、seq 0），与两账本终态一致——影响面仅限本次两条测试记录，不触任何真实数据。重启后复验通知为空、未读 0、无重复生成。
- **内存**：施工前 used 3815/7725 MB ≈ 49.4%；完工后 3820/7725 ≈ 49.5%（桥自身增量可忽略），全程远低于 80% 红线。容器数 15 不变（期间 oneday-bridge 的一次重启为其他施工线所为、非本包）。
- **回滚**：还原 `overview_bridge.py.bak-20261109-monitorsrc` 与 `docker-compose.yml.bak-20261109-monitorsrc` → `docker compose up -d overview-bridge` 即退回单源态；state.json 里多出的 mon_offset/mon_seen 两键旧版不读、无副作用（要极致干净可同时还原 state.json.bak-20261109-monitorsrc，但会丢回滚点之后新生成的 decisions 通知，默认不还原）。
