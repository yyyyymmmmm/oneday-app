# 伴生状态契约表（STATUS-CONTRACT）

立于 1.0.22（2026-11-11，复杂化全清第 1 项）。此前伴生 8 个状态面
各用各的字段名与新鲜度语义，且同一数字有两处各自计算（待审批总数
被 overview 与 oneday 两桥分别向 write-gate 求和、动态生成历史同值
双键）。本表是各状态面的唯一登记处：新状态面先登记再上线；同一
数字只许一个出处，其余面只能消费。

## 红线规则

- **R1 待审批总数只许 overview 求和**：`pendingApprovals` 是唯一
  求和结果（overview 以 write-gate 自家钥读其 `/status` 的 counts
  并求和）。任何其他桥不得再对 write-gate counts 自行求和；
  oneday 的 `assembly.approvalTotal` 是对该结果的消费（经回环
  `GET /overview`），不是第二出处。
- **R2 同一账本只许一个键**：动态生成历史只以 `research` 键返回；
  pre-0.38.0 的 `morning` 同值别名已于 1.0.22 删除。
- **R3 字段名与新鲜度语义以本表为准**：改字段名/语义先改本表，
  并在对应桥的记账里留痕。

## 状态面登记（8 面）

| # | 面 | 属主（文件/端口） | 字段 | 新鲜度语义 |
|---|---|---|---|---|
| 1 | `GET /overview` | overview_bridge.py / 8644 | `hermesUp`, `activeSessions`, `pendingApprovals`, `unreadNotifications`, `generatedAt` | 请求时同步现算，无缓存；`pendingApprovals` 为全系统待审批总数的唯一出处（R1） |
| 2 | `GET /status`（write-gate） | write_gate_bridge.py / 8643 | `counts{memory, skills}` 等 | 暂存记录的实时计数，是 R1 求和的原始账；除 overview 外无人可对 counts 求和 |
| 3 | `GET /pending`、`GET /decisions`（write-gate） | write_gate_bridge.py / 8643 | 记录本体＋可选 `anchor{sessionId, tier}` | anchor 为时序关联的尽力判定：T1 暂存调用在场、T3 background_review 最近活跃会话；T2 已删（2026-11-11 第 3 项，生产命中 0/25），无锚即 null、走降级形态 |
| 4 | `GET /device/sync/status`＋`device_status` 工具 | device_bridge.py / 8647 | 逐数据集同步状态（仅状态、无内容） | 以各数据集 `synced_at` 戳为准；副本空/过期如实标注，不冒充实时 |
| 5 | ledger `summary()` / `health()` | ledger.py（经 oneday 8646 读面） | summary：`inProgress`, `blockedApproval`, `stale`, `todayCompleted/Failed/Cancelled`, `byStatus`, `total`；health：`degraded`, `degradedReason`, `collectorHeartbeatAt`, `ledgerUpdatedAt`, `items`, `seq` | 读时由 append-only 账本现算；僵尸判级以 health 的心跳与事件戳为据，无证据不标完成 |
| 6 | `GET /ideas/generation` | oneday_bridge.py `_generation_view` / 8646 | `lastRunAt`, `nextRunAt`, `history` | 点子生成账本在最后一轮落定时的状态 |
| 7 | `GET /feed/generation` | oneday_bridge.py `_feed_generation_view` / 8646 | `assembly{date, digestPostId, purityArchived{digest, event}, eventsToday, lastAssemblyAt, kanbanPolledAt, kanbanNote, approvalTotal, approvalsNote}`, `research{lastRunAt, nextRunAt, nextEditionBAt, running, history}`, `policy`, `hourlyLog`, `unread` | `research` 单键（R2）；`approvalTotal` 为远程轮询（300 秒一跳）消费 overview 的快照，可滞后 ≤ 一跳，失败只落 `approvalsNote`、不编数；`purityArchived` 为动态纯化（1.0.32）的累计封存数（装配器原地封存 digest/event 存量帖），`digestPostId` 自纯化起恒为 null（digest 已停建）、`eventsToday` 只记账本事件数（事件不再成帖）、`unread` 不计已封存帖 |
| 8 | `GET /goals/briefing`（简报台账）＋ box `get_status()` | oneday_bridge.py `_briefing_ledger_view` / 8646；box_bridge.py / 8645 | 简报：逐目标最近简报与生成账；box：三连查拼装的机器状态 | 简报以台账落盘为准；box 为查询时拼装、无独立账本 |
| 9 | `GET /goals`、`GET /goals/{id}` 的 `activity` 派生字段（GD-1） | oneday_bridge.py `_goal_activity` / 8646 | `state`（running/waiting/blocked/idle）、`label`、`since`、`focusTask{id,title,status}`、六类计数、`linkedCount`、`missingCount`、`latestProgress{text,at}`、`lastActivityAt`、`polledAt`、`note` | 读时派生、不落存储：原料＝goalTaskLinks＋动态轮询的 kanban 状态图（`meta.feed` 快照，新鲜度＝`polledAt`，≤300 秒一跳）；原始任务状态在 `focusTask.status` 原样透传，桶映射用台账 KANBAN_MAP 与桥内 done/blocked/failed 既有集合，不新造状态词；派生缺口写入 `note`，不静默 |

## 变更记账

- 2026-11-24（1.0.73 已应用）：新增智能体读面登记——
  oneday_bridge 第四个 MCP 门面 `POST /library-mcp`（8646，
  段文件 oneday_seg_library_mcp.py），只读工具
  `library_list{since?, limit?, offset?}`；数据源＝
  `_file_library_view`，与 App 资源库页 `GET /file-library`
  同一函数、同一准入集——不新增状态面、不另立计数出处，
  本表 8+1 面登记不变。Hermes 注册名 `oneday-library`，
  鉴权引全局 API_SERVER_KEY（nginx 验后换桥内钥，与
  goals/sessions/automation 三门面同口径）。预制原号
  1.0.72 因 §459 先行占用顺延 1.0.73；断桥批三搬 oneday
  面时随面搬、工具名与契约不变。回滚＝摘注册＋删段文件
  ＋桥恢复 1.0.72 基线。

- 2026-11-24（§459 二阶段，仓库已落码、待主线排部署）：多处
  契约增补，旧字段全部保留、已发货 App 不受影响。①简报：
  `GET /meta/brief` 文档新增 `text`（用户面单层文本）、
  `polished`（bool）、`polishState`（done/pending/error/
  idle）——单层规则＝润色稿的 `forInterest` 与当前
  `briefInterest` 逐字相等才出润色稿，否则出用户原文；
  `PUT /meta/brief` 新增接受 `{"text": ...}`（折为 interest
  保存；`interest` 显式给出时优先）。润色落地写
  `meta.briefPolished{text, forInterest, at}`，`briefInterest`
  永不被润色覆盖。②点子两维：`GET /ideas` 每卡新增
  `domain`（Muse 十二值枚举，恒非 null，存量由旧 category
  折算）、`categoryLabel`（自由短语，可 null）、`kind`
  （chat/routine/goal，存量恒 chat）；旧 `category` 照旧出。
  池快照分节键由 `category` 改为 `domain`（节序＝
  IDEAS_DOMAINS 序）；生成轮 rec 新增 `domainDist`、
  `kindDist`。③动态：`GET /feed` 每帖新增 `category`
  （＝方向原文，事件/小结帖为 null）与 `usefulness`
  （有用度分：点赞 50＋讨论 15×min(次数,3)＋已读 10＋
  新鲜度 max(0, 20−5×天龄)）；列表排序改近三日按
  (usefulness, createdAt) 降序、窗外纯时间序。④本地事件
  成帖复活（翻 2026-11-12 纯化裁定之半）：装配器把当日
  idea/briefing/monitor/task 四类事件各成一帖（kind=event、
  带 `eventKey`、每日上限 5），approval 永不成帖、digest
  恒封存；`purityArchived` 语义不变（仅计旧制帖），第 7 面
  assembly 记账里「事件不再成帖」一句自本条起作废。
  ⑤取材新增两路（轮账 `retrieval` 新增 `social`、
  `github` 计数键）：社交专路（Hermes run，提示词版本
  `feed_social_material_v1`）与 GitHub API 路（仓库搜索＋
  README），均只在通用路留缺口时走。⑥灵感库（等价自建、
  非 Muse 同一语料）：`meta.inspiration{entries}`，种子
  16 条＋建成/点赞回流积累，生成材料以无编号角度行注入。
  存量回填脚本 `parity2_migrate.py`（部署窗口内一次性
  执行，幂等、带备份与逐卡账）。
- 2026-11-12（1.0.34，点子分类）：`GET /ideas` 每卡新增
  `category`（与目标创建流同表七类枚举 GOAL_CATEGORIES，桥为
  单一真源，恒非 null——存量无值读 "other"）；第 6 面 history
  每轮 rec 新增 `categoryDist`（本轮落卡的分类分布，有落卡
  才有此键）。存量未终态卡已由一次性回填逐张定分类（模型→
  规则→其他三路，账在 data.json 的 meta.ideasCategoryBackfill）。
  详见 IDEAS-CATEGORY-134-REPORT.md。
- 2026-11-12（1.0.32，动态纯化，用户亲定）：第 7 面 assembly
  新增 `purityArchived{digest, event}` 累计封存计数；动态流停
  建 digest/event 帖（FD-1 设计退役），事件只入账本；`unread`
  排除已封存帖。详见 FEED-PURITY-REPORT.md。
- 2026-11-12（GD-1 预制待部署，版本号由主线定）：登记第 9 面
  ——`activity` 目标活动状态派生（`_goal_view` 读时派生，
  原料为 goalTaskLinks＋feed 轮询 kanban 状态图）。
- 2026-11-11（1.0.22，复杂化第 1 项）：立表；R1 落地（oneday
  `_feed_poll_remote` 改消费 overview `pendingApprovals`，自家
  求和删除）；R2 落地（`_feed_generation_view` 删 `morning` 双键）。
