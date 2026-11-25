# oneday-bridge 上线记录（2026-11-09）

P4 目标包＋P5 点子包的服务端数据桥。Hermes 本体无目标/点子实体（施工图盘点 #24/#25），本桥是桥侧轻表：只存目标与点子两类实体，不做生成、不做调度（点子生成归 Hermes 提示层、采纳建任务归 P3 任务面，均不在本桥）。与 hermes 容器、其 config、既有 compose 工程完全隔离。

## 部署形态

- 服务器 118.24.41.52，目录 `/www/dk_project/dk_app/oneday-bridge/`（独立 compose 工程，本地副本 `oneday-bridge-docker-compose.yml`）
  - `oneday_bridge.py`（原件存本目录同名文件，351 行，纯 stdlib：http.server＋JSON 存储）
  - `docker-compose.yml`：image `nousresearch/hermes-agent:v0.23.0`、container `oneday-bridge`、entrypoint 用镜像内 venv 的 python3 跑桥脚本（脚本只读挂载 `/opt/bridge/oneday_bridge.py`）、数据挂载 `./data:/opt/oneday-data`、`mem_limit 256m`、restart unless-stopped
  - `oneday-bridge.env`（0600，服务器本地组装）：`WRITE_GATE_KEY` 自 hermes `write-gate.env` 复用同一把桥钥匙（64 字符，未新造第二把）
- 端口：仅绑 `127.0.0.1:8646`
- 存储：桥自有目录 `data/data.json` 单文件（0600，原子 tmp＋replace 写、全量变更串行锁；上线后为干净基线 `{"goals": [], "ideas": []}`）
- 公网入口：nginx 站点 hermes.example.com 追加自有段（备份 `hermes.example.com.conf.bak-20261109-onedaybridge`，`nginx -t` 通过后 reload）：
  `location /api/oneday-bridge/` → `proxy_pass http://127.0.0.1:8646/`（剥前缀、透传 Authorization、read_timeout 60s）
- fail-closed：`WRITE_GATE_KEY` 未设置拒启
- 内存实测：桥自身 13.26MiB / 上限 256MiB

## 契约（冻结，App 线对接以此为准）

基址：`https://hermes.example.com/api/oneday-bridge`，全部业务端点要求 `Authorization: Bearer <write-gate 桥钥匙>`（与 write-gate/overview/box 三桥同一把，App 已存的那把即可）。无/错 Bearer → 401（本机与公网均实测）。时间字段一律 epoch 秒（float，与 Hermes 消息同口径）。列表按 createdAt 升序。

| 端点 | 说明 |
|---|---|
| GET /goals | `{"items":[goal,...]}` |
| POST /goals `{title, note?, milestones?:[{title}]}` | 201 返回 goal 全形；里程碑 id 由服务端生成、done=false |
| PATCH /goals/{id} | title/note 可选改；milestones 给出即**全量替换**；200 返回更新后 goal |
| DELETE /goals/{id} | `{"ok":true}` |
| GET /ideas | `{"items":[idea,...]}` |
| POST /ideas `{title, detail?, goalId?}` | 201 返回 idea 全形 |
| DELETE /ideas/{id} | `{"ok":true}` |

goal 全形：`{id, title, note, milestones:[{id, title, done}], createdAt, updatedAt}`，id 前缀 `g_`、里程碑 `m_`。
idea 全形：`{id, title, detail, goalId, createdAt}`，id 前缀 `i_`，goalId 可为 null。
另有桥内 `GET /health` → `{"ok":true,"service":"oneday-bridge"}`（唯一免鉴权路由，不回任何数据）。

### 契约未明处，本桥的定版语义（App 线须知）

1. **PATCH 里程碑全量替换的条目形态**：条目带 `id` 则保留该 id（勾选状态靠它对齐），不带 id 则服务端新生成；`done` 缺省 false。实测样本见下。
2. **删目标联动**：删除 goal 时，指向它的 ideas 的 `goalId` 一律置 null（不留悬空引用），idea 本体不删。
3. **点子关联校验**：POST /ideas 的 goalId 为非 null 时必须指向现存目标，否则 400（人话「目标不存在，无法关联」）；goalId 省略或 null 则不关联。
4. **校验口径**：title 去首尾空白后为空 → 400 `{"error":"标题不能为空"}`（里程碑标题同理）；不存在的 id 做 PATCH/DELETE → 404；note/detail 传 null 按空字符串收；错误体统一 `{"error": 人话}`。

### 实测样本（2026-11-09 本机验收造数，已删净）

POST /goals 201：
```json
{"id": "g_735c0a39eb9e", "title": "验收目标", "note": "验收备注",
 "milestones": [{"id": "m_020af9aa0107", "title": "第一步", "done": false},
                {"id": "m_d04190218c94", "title": "第二步", "done": false}],
 "createdAt": 1794217810.2546644, "updatedAt": 1794217810.2546644}
```
PATCH /goals/{id}（改名＋全量替换里程碑：一勾一新增）200：
```json
{"id": "g_735c0a39eb9e", "title": "验收目标·改", "note": "验收备注",
 "milestones": [{"id": "m_020af9aa0107", "title": "第一步", "done": true},
                {"id": "m_6d452802b335", "title": "第三步", "done": false}],
 "createdAt": 1794217810.2546644, "updatedAt": 1794217810.2589986}
```
POST /ideas 201：
```json
{"id": "i_0b42bb7dd610", "title": "验收点子", "detail": "细节",
 "goalId": "g_735c0a39eb9e", "createdAt": 1794217810.2639737}
```

## 验收实查（2026-11-09，本机 8646 与公网 https 各一整套，共 36 项全 PASS）

- 鉴权：无 Bearer → 401、错 Bearer → 401（两路各验）
- goals：建（201 全形断言：id 前缀/里程碑生成/done=false/createdAt=float 且与 updatedAt 相等）→ 列表读回 → PATCH 改名＋里程碑全量替换（旧 id 保留且 done=true、新条目新 id、note 未动、updatedAt 不倒退）→ 空标题 400（原文 `{"error": "标题不能为空"}`）→ 不存在 id PATCH/DELETE 各 404 → 删 200 `{"ok":true}`
- ideas：建关联（goalId 回填一致）→ 建不关联（goalId=null）→ 假 goalId 400 → 空标题 400 → 列表读回 → 删目标后关联点子 goalId 变 null（联动语义实测）→ 逐个删 200
- 清零复验：两路收尾 GET /goals 与 GET /ideas 均回基线（goals 0、ideas 0），验收造数无残留；服务器 /tmp 验收脚本已删
- 内存：动手前 used 3802/7725 ≈ 49.2% → 完工 3817/7725 ≈ 49.4%，全程远低于 80% 红线；容器数 14 → 15，既有 14 容器未动、未重启（hermes 本体与其 compose 工程零接触）

## 回滚基线

1. `cd /www/dk_project/dk_app/oneday-bridge && docker compose down`，删该目录（data/data.json 一并删即数据全退）；
2. nginx：删 hermes.example.com.conf 中 `# OneDay bridge` 段（或用备份 `.bak-20261109-onedaybridge` 还原），`nginx -t && nginx -s reload`。
两步后全退，不影响 hermes 与其他三桥。

---

## 监测扩展（P6，2026-11-09 晚追加）

按冻结契约 `~/workspace/oneday-design-review/monitor-bridge-contract-20261109.md` 在同一桥上扩展 /monitors 全套。脚本 351 行 → 888 行（md5 `389a627b80ca8c072ebe247888948633`，本地原件已同步）；存储仍为同一 data.json（新增 `monitors`/`changes` 两表），部署形态、端口、钥匙、nginx 段均未动，只重启了 oneday-bridge 容器本体（其余 14 容器未碰，hermes 本体与 config 零接触）。

### 端点与语义（契约逐条对齐）

| 端点 | 说明 |
|---|---|
| GET /monitors | `{"items":[monitor,...]}`，createdAt 升序（呈现排序归客户端） |
| POST /monitors | 201 返回 monitor 全形；建时立即抓取落**基线指纹**（只建基线、不报变化，lastResult/lastCheckedAt 保持 null）；基线抓取失败也建成功，lastResult="failed"＋lastError 记原因，下一次成功检查自动转基线 |
| GET /monitors/{id}/changes | detectedAt 倒序；监测不存在 → 404 |
| POST /monitors/{id}/changes/{cid}/read | 契约 §2.1 原口：单条已读，unreadChanges 按未读数重算 |
| POST /monitors/{id}/read | 整条已读（任务验收口）：其全部 changes 置已读、unreadChanges 归 0 |
| POST /monitors/{id}/check | 立即检查：抓取→指纹比对→三分落账；已暂停 → 409 `{"error":"监测已暂停，先恢复再检查"}` |
| POST /monitors/{id}/pause ｜ /resume | enabled 翻转（resume 时重算下一次运行时刻） |
| DELETE /monitors/{id} | 删监测＋其全部 changes |

monitor 全形＝契约 §2.2 字段集（内部字段 cron/intervalSeconds/snapshotText/snapshotFp/nextRunAt 只存不出）。change 全形＝契约 §2.3。校验：name 空 → 400；target 空或非 http(s) → 400；cron 表达式非法 → 400；intervalSeconds <60 → 400；不存在的 id → 404；错误体统一 `{"error": 人话}`。

### 检查引擎

- 抓取：urllib，超时 15s，跟随重定向，正文上限 2MB，UTF-8 容错解码；HTTP ≥400 与网络异常都归 failed 并记人话原因（快照不更新）。
- 指纹：对快照文本（上限 32,768 字符，超长截断——** cap 之外的变化检不出，明示**）取 SHA-256；与存量指纹比对得 changed/unchanged/failed 三分。
- changed 落 MonitorChange：before/after 各存变化前后快照原文上限 4,000 字符；summary 人话取首个不同行（截 60 字符），如「内容发生变化：<该行>」；每监测保留最近 100 条 changes；unreadChanges＋1、latestChangeSummary/At 同步。

### 调度选型（与契约 §2.4 的偏差，定案记录）

契约原设计为「Hermes cron 做调度底座」，实查三条硬伤做不到，改**桥内自带调度**：

1. **无触发通道**：Hermes cron job 是 prompt 型 agent 任务（OpenAPI CronJobCreate 只有 prompt/schedule/deliver 等字段），没有 webhook/无 agent 的执行模式；cron 到点只能起一条 agent 会话，没有任何机制能「触发桥的检查逻辑」。
2. **钥匙纪律**：硬要 agent 会话代打桥的 /check 端点，就必须把桥钥匙写进 cron prompt——钥匙会落进 job 记录与会话转录，违反凭据纪律；且每次定时检查烧一条 agent 会话、执行还不确定。
3. **网络隔离**：oneday-bridge 在自己的 compose 网络里，与 hermes 容器互不可达（服务名不通）；为建 cron 还得把桥并入 hermes 网络并塞入网关钥匙，扩大耦合面却换不来触发能力。

落地形态：桥内调度线程每 20 秒扫一遍到期监测串行执行检查。POST /monitors 入参由桥定为 `{name, target, scheduleText?, cron?, intervalSeconds?}`——scheduleText 只存显示串原样透出（客户端不解析，契约口径不变）；机器调度认 `cron`（5 字段标准式，含步进/范围/列表、dom/dow 的 Vixie 规则）或 `intervalSeconds`（≥60），两者都有时 cron 优先；**两者都不给 = 手动检查型监测**（不会自己跑，scheduleText 缺省显示「手动检查」）。cron 求值时区固定 **Asia/Shanghai**（容器本身是 UTC，按用户口径求值；时间戳仍是 epoch 秒）。代价（如实）：①进程重启后靠 data.json 里持久化的 nextRunAt 恢复，停机期间错过的点位只补跑一次、不逐个补；②调度精度 ±20 秒（扫描周期）；③`cronJobId` 恒为 null（契约允许「未建为 null」），Hermes cron 列表里不会出现监测任务。

### 通知（等价法与限制，明示）

overview-bridge 的通知只源于 write-gate 的 decisions.jsonl（仅 (memory|skills)×(approved|rejected) 生成，标题映射写死），**没有通用注入通道**。往 decisions.jsonl 塞监测行被否决：那是写入审批的审计账，其行会原样出现在 App 审核历史里，且标题只会落成兜底的「写入审批已处理」。等价法：changed 时按 overview 的同一落盘口径——append-only JSONL、同记录形状 `{id:"mon-…", kind:"monitor_change", title:"监测有变化：<名>", body:summary, createdAt:ISO-Z, read:false}`——追加到桥数据目录的 `monitor-notifications.jsonl`。**限制**：overview-bridge 目前不读这个账本，监测变化暂不进 App 的 /notifications 通知流（App 侧靠监测段 unreadChanges 呈现，本契约 §3 已定）；将来要并入通知流，只需给 overview-bridge 加一个同口径的轮询源（小改，另包）。

### 验收实查（2026-11-09）

- 本地预冒烟（新脚本＋本地测试页）：41 项断言全过（鉴权/基线静默/unchanged/changed/前后原文/单条 read/整条 read/pause 409/404 目标与不可达双 failed/入参 400 四例/404 两例/goals·ideas 回归），通知账本 2 条形状核对过，cron `* * * * *` 由调度器在整分钟边界真触发（lastResult=unchanged），DELETE 后 changes 转 404。
- 生产本机（127.0.0.1:8646）与公网（https://hermes.example.com/api/oneday-bridge）各一整套 30 项、全 PASS：401 双验（无钥/错钥）→建监测（自控测试页，托管于宿主机仅绑 docker 网关 172.24.0.1:8899、桥经网关抓取）→基线→check unchanged→改页→check changed＋change 记录含 version-one/version-two 前后原文→read 后未读归零→pause 后 check 409→resume→404 目标 failed 三分→DELETE 清零→goals/ideas 读写回归＋计数还原。
- 收尾：测试监测全删（data.json 终态 goals/ideas/monitors/changes 均 0 条，与动手前基线一致，新增的只是两个空表键）；测试页服务器已杀、/tmp 验收脚本与页面全删；通知账本里仅有 2 条验收记录，整文件已删（无真实监测数据）；overview /notifications 复查仍为空、未受影响。
- 内存：动手前 used 3814/7725 ≈ 49.4% → 完工 3834/7725 ≈ 49.6%，全程远低于 80% 红线；桥自身 16.53MiB / 256MiB。

### 本包备份与回滚

- 改前备份（服务器桥目录内）：`oneday_bridge.py.bak-20261109-monitors`（md5 a1fef64f…，与改前原件一致）、`data/data.json.bak-20261109-monitors`（md5 5619c176…）。
- 回滚：还原脚本备份 → `docker compose restart oneday-bridge` 即退回 /monitors 未开通态（集合端点转 404，客户端按契约露「监测数据源未开通」）。注意只还原脚本时，旧版会在下一次写入时把 data.json 里的 monitors/changes 两表丢弃（旧 _load 不认新键）——监测数据不要了才可这么退；要连数据一起退则同时还原 data.json 备份（会覆盖备份点之后新增的 goals/ideas）。

## 附录：P1 点子生成管道（2026-11-10，0.32.0 配套）

- **端点增补**：PATCH /ideas/{id}（status/taskId 回写，状态机 pending→adopted/dismissed、expired 终态）；POST /ideas 接受 source/evidence（generated 无 evidence 回 400）；GET/PUT /meta/brief；GET /ideas/generation；POST /ideas/generate（手动触发，运行中 409）。
- **字段**：idea 加 source/evidence/evidenceRef/status/taskId/expiresAt（生成卡 +14 天）；_db 加 meta 键（brief＋ideasGen 账：lastRunAt/nextRunAt/history≤30）。
- **调度**：桥内 20 秒 tick 每日 07:30 Asia/Shanghai 一轮；过期＝tick 清扫落盘（非读时判定）。
- **生成链**：素材＝brief＋目标＋监测 7 天变化＋忽略避让清单＋Dashboard 会话近 7 天（登录四字段 {provider:"basic",username,password,next:"/"}，缺 provider 回 422）；调用 POST /v1/runs（deepseek-flash、无 session_id 优先、Idempotency-Key 按轮、轮询 600s、waiting_for_approval 滞留 60s 即 stop）；校验 JSON 数组逐卡（标题/正文/evidence 非空＋去重＋上限 3）才落库；失败注记只进 history 的 materialNote，绝不进素材正文（首轮曾泄漏凑卡、已修并删卡）。
- **env 增补**（oneday-bridge.env，0600；只记键名）：HERMES_API_KEY、HERMES_DASH_USER、HERMES_DASH_PASSWORD；HERMES_BASE_URL 未设默认 https://hermes.example.com。注意：`docker compose restart` 不重读 env_file，改 env 必须 `up -d` 重建容器。
- **备份**：桥目录 oneday_bridge.py.bak-20261110-ideasgen、data/data.json.bak-20261110-ideasgen。回滚＝还原两文件＋up -d（旧版 _load 会丢 meta 键、ideas 五字段呈现退化但盘上数据在，升回即恢复）。
- **首轮实录**：手动触发第三跑 status=ok produced=3 dropped=0（run_2e593f5fb9c94882a8216b75300be1df）：i_27cbb91097f0（S5 复盘摘要）、i_1fc473855d85（S1 登录 422 自查清单）、i_3076b62405cc（S11 P3TEST 验收汇总）；公网契约实测 13/13 PASS；下一轮 2026-11-11 07:30。
- **提示词资产**：桥源码 IDEAS_GEN_PROMPT 常量（~/workspace/hermes-deploy/oneday_bridge.py），单一真源。

## 附录：P2 目标补深（2026-11-10，0.33.0 配套）

- **契约增补**：goal 加 status（active|completed，流转时桥落 completedAt）/parentId（子目标一层，深度校验四条）/source（manual|chat）；goal 视图嵌 latestEntry（只读穿）。新增集合 goalEntries（GET/POST /goals/{id}/entries、DELETE …/entries/{eid}，append-only、source user|agent、正文上限 2000）与 briefings（GET /goals/{id}/briefings 降序；POST /goals/briefings/generate 手动触发 202/409；GET /goals/briefings 账面）。monitor 加可选 goalId（建单校验、删目标置 null）；删目标级联子目标/条目/简报，点子/监测只解绑。
- **简报管道**：桥内 20 秒 tick 每周一 08:00 Asia/Shanghai 一轮（meta.briefGen 账 ≤30 轮）；仅 active 顶层目标；素材＝近 7 天条目＋关联任务（点子采纳的 kanban 任务经 Dashboard cookie 通道读板现值）＋挂靠监测 7 天变化；无素材跳过记 skippedNoMaterial（不硬凑）；每目标一次 /v1/runs（deepseek-flash，Idempotency-Key＝goal-brief-<ISO 周>-<goalId>），严格解析 {"title","body"} 才落库；(goalId, period) 唯一、重跑记 already-exists；失败注记只进账面 materialNote 不进素材（P1 教训）；单轮上限 20 目标。提示词资产＝桥源码 GOAL_BRIEF_PROMPT 常量。
- **部署**：备份 oneday_bridge.py.bak-20261110-p2（md5 ae6b2c3…＝P2 前版）、data/data.json.bak-20261110-p2；只重启 oneday-bridge 本体；内存全程 ≈51%。回滚＝还原两备份＋restart（旧版 _load 不认 goalEntries/briefings 两表，升回即恢复；回滚窗口内新写的条目/简报会在旧版下次写入时被丢弃，连数据退须同时还原 data.json 备份）。
- **验证**：本地自测 oneday_bridge_p2_selftest.py 34/34（HTTP 契约 25＋进程内桩测整轮 9：素材门/落库/幂等/注记不进素材/latestEntry 嵌入）。生产公网契约全过＋手动一轮真产 1 封（临时目标＋临时条目，period 2026-W46，信体如实反映单薄素材），验后临时目标/子目标/条目/简报全删净，生产终态 goals 0、ideas 3、monitors 0 与动手前一致；账面留 2 条 manual 轮记录（1 次首验＋1 次复验，属实记录不删）。
- **施工中真 bug 一例**：简报 DTO 视图 `_briefing_view(b)` 与账面视图同名互相遮蔽，GET /goals/{id}/briefings 首验 500；已改名 `_briefing_ledger_view` 分立并补回归测（自测 B 段 list/ledger 双查），复验 200 落信可读。另注：验收时任务板实查为空（total 0），账面 materialNote「任务板为空或格式不对」属实——关联任务素材在有采纳任务时才有料。
- **9B 桥侧面**：goal.source=chat 已可落字校验，但智能体侧无桥写路径（Hermes mcp_servers 仅 notion/github，桥钥不在智能体侧），App 对话式创建入口未开；替代方案＝桥加 MCP 门面随 Hermes 收官窗口注册（详 DESIGN-V4 §61.4）。


## 2026-11-10 P3 动态（feed）上线

- 变更：oneday_bridge.py 加 /feed 数据面＋双生产者（段一确定性汇编 tick＋段二晨报每日 08:30 /v1/runs flash）；App 0.35.0 动态页＋底栏五格（仓内 DESIGN-V4 §64）。
- 备份：oneday_bridge.py.bak-20261110-p3、data/data.json.bak-20261110-p3（同目录）；回滚＝覆盖回备份文件＋docker restart oneday-bridge。
- 部署：scp 新文件→docker restart oneday-bridge（只重启桥本体）；内存约 51.6%。
- 自测：oneday_bridge_p3_selftest.py 25/25（HTTP 契约/段二桩轮三态/轮询 diff 基线与只增口径）。
- 首轮生产实测：段一汇编《今日动态 · 3 件》（P1 三张生成卡）；段二手动一轮 ok/produced=1（run_9a824d76edb24a28bb1ab60809ae60f5），晨报《自托管助手的三件新事：发布通道、沙箱底座、密钥护栏》（refs 真 idea×1、links 真返×6）。生产终态帖 2/未读 2；晨报自动轮次日 08:30。
- 通道实情：kanban 板现为空板（8 列 0 任务，任务事件基线已立、待有任务自然生效）；待审批经 /api/write-gate/status 读计数（基线 0，59ba48f2 已不在待批列）；write-gate 路径口径是 /api/write-gate（初版误写 /writegate 已修）。
