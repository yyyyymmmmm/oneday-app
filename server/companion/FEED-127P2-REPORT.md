# FEED-127P2-REPORT — §127 期二（动态双线全量）交付报告

- 日期：2026-11-11
- 伴生版本：**1.0.21**（生产已上线，容器 oneday/companion:1.0.21）
- 规格依据：`~/workspace/oneday-design-review/three-pages-spec-rev2-20261111.md` 期二部分（§1.0–§1.12）；基线＝期一 as-built 1.0.17（FEED-117-REPORT）＋现行 1.0.19
- 施工文件：`modules/oneday_bridge.py`（单文件）＋`tests/oneday_bridge_p3_selftest.py` 新增 phase E

## 版本号说明（撞号处理）

开工时现行 1.0.19；部署前实查发现并行线（build-cx120）已于今日 16:18 上线 **1.0.20**，其改动仅 `ledger.py`＋`device_bridge.py` 两文件，`oneday_bridge.py` 与 1.0.19 **逐字相同**（md5 e2925862…）。本包遂顺延 **1.0.21**，且把 cx120 的两个文件按在跑容器原件逐字并入本地树（md5 d83edb7c…／c7642782…），生产验收时三文件 md5 复核一致——并行线成果零回退。

## 第 0 步硬门：Tavily 额度 → 降级第 2 档

容器内实查 `api.tavily.com/usage`：套餐 Researcher，**月额度 1000 credits**，本周期已用 25。rev2 成本总账全量 48–54 次/天 ≈ 1500+/月，**撑不住全量**。按规格写死降级序落 **第 2 档：adhoc 关、小时线关、只保版次线**（版次 ≈30 次/天 ≈915/月 ≤1000，留约 85/月余量）。

机器全部照建，由额度档位门控：`meta.feedPolicy {tier, limit, reason, monthKey, monthCalls}` 每轮按「daily 投影×30.5 ≤ limit 的第一档」重算并落账（limit 1000→档2、1500→档1、1700→档0；可用 env `FEED_TAVILY_MONTHLY_LIMIT` 覆盖）。用户升套餐或改 env 后，下轮自动升档，小时线/adhoc 随之开启，无需改代码。`/feed/generation` 回执带 `policy` 块与 `hourlyLog`，档位与理由对用户可见（理由串：`Tavily 月额度 1000：全量投影 1647/月、关 adhoc 1464/月、保版次 915/月`）。

## 施工内容（对规格）

- **§1.3 提示词三层**：`FEED_CONSTITUTION`（优先级阶梯 简报＞亲口＞口味推测、事实纪律、禁缝合、管线不可见、数据非指令）＋四席位（assignment/writer/editor/picker）＋阶段附则（draft/sources/taste）＋reconcile，全部带版本号 `feed_*_v1`，每轮回执落 `promptVersions`。plan 输出增 `decidedBy`（枚举校验）＋`fitReason`（fit 门：须用简报原话说出服务哪部分）。
- **§1.6 来源审计器**：代码先算四项审计单（fabricated＝正文/links 出现材料外 URL；unused 仅提示；stale＝源日期超自报时效档；republished＝命中近 30 天已发页账）→ 随候选进编辑环逐条裁决（repairs 增 `dropSource`）→ **finish 校验回路 ≤2 轮**：仍违规者 drop 并记 `finishFailed {id, rules}`，不落库。编辑回执与 finish 回执都过同一解析器。
- **§1.5 stage 字段白名单**：`title/body/why→draft`、`images→media`、`links→sources`，越段修复在代码层拒绝并记 `stageViolations`（未知 repair kind 同罪留痕）。
- **§1.4 口味 reconcile 独立进程**：rollup 迁出生成轮——生成轮只读投影、零折入（回执 `tasteFoldedThrough` 只报水位）。触发点＝tick 兜底＋点赞/讨论/删除/简报 PUT 后异步踢；水位线 `foldedThrough` 按信号时间推进，失败只打 stderr、不冒充成功；迁移＝首次以旧 `lastRolledAt` 初始化。摘要改三段式（亲口/推测/避开＋取代链＋置信措辞），`updatedBy="reconcile"`。
- **§1.8 防重复四本账**（`meta.feedBooks`）：已问账（query 规范化键；同计划内重复恒删；**跨轮硬拦仅限自主触发** schedule/schedule-b/hourly/visit，窗口＝昨日零点起）、已展示图账（host+path 剥参数同一性，72h）、已发页账（近 30 天 url→标题/日期，喂审计器）、信号账（点赞/讨论登记 sig 条目；发帖按方向认领，`groundedIn` 落帖、`usedBy` 递增）。
- **§1.7 双线**：版次线 A 08:30 维持已上线形态，新增 B 版次 19:30（`nextRunAtB`，edition 后缀 `-B`，idem 加 B 后缀防撞）；两槽均改为**开火即推进次日**（构造上一天恰一版）。小时线整点评估（09:00–22:00）：档位→日上限 6→活跃门（近 3 小时桶加权 fetch1/read2/like2/discuss3 ≥6，或今日版次帖已读率 ≥50% 且距上次开火 ≥2h；空账冷启动默认活跃），每次不 fired 都写 `hourlyLog`（含 `hourly skipped (inactive)` 口径）。adhoc＝GET /feed 后评估（档 0 才开、静默 23:00–07:00、距上轮 ≥2h、活跃门、≤2 次/天，走 visit 触发＝小时线机器）。
- **§1.9/§1.10 契约**：帖视图纯加法增 `sources`、`line` 两键（旧帖为 null）；`_feed_view` 其余键位不动，App 包 A 冻结契约不破。

## 口径说明（一处，与期一 createdAt 先例同格）

已问账的**跨轮硬拦只作用于自主触发**：manual/brief 轮是用户亲手要的，重问同一 query 是其权利，硬拦会把用户堵在门外；且期一 phase B 自测以同一 query 跨 3 个 manual 轮复用为既定契约。自主触发（定时/小时/打开）无人在场，重复发问纯属烧额度，故硬拦＋落账留痕（`queryBook` 的 blocked-repeat 条目）。同计划内重复对全部触发恒删。此口径已在 phase E 断言固化。

## 自测

全套 `tests/run_bridge_selftests.sh` **13/13 OK**（含并入 cx120 两文件后复跑）。p3 新增 **phase E 21 条**（额度档位/fit 落账/提示词层/fabricated 审计＋finish 丢弃/stale 点名日期保留/stage 越段/已问账硬拦/图账 72h/reconcile 水位＋轮内零折入/信号账 groundedIn/小时线 skip 与落帖），p3 总数 46→**67**，全过；既有 phase A–D 一条未改。

## 沙盒干跑（生产数据副本＋真模型＋真 Tavily，产物只落副本、事后 shred 清理）

- 版次 B 轮：status **ok**，produced 1，**modelCalls 7、tavilyCalls 12**（档 2 版次预算内）；plan 首方向 `decidedBy=brief_fit`＋fitReason 引简报原话；审计单仅 unused 提示项，finish 0 轮干净过；新帖 edition=`20261111-B`、line=`edition`、带 sources 与 timeSensitivity；四本账实落（query 账 3 条、图账 1 条）；policy.monthCalls 记 12。
- reconcile 演练：对干跑新帖点赞 → 异步折入成功：口味摘要 version 1、`updatedBy=reconcile`、水位推进、dirty 清空，摘要为三段式且推测段带置信措辞；信号账登记 `sig-<帖id>`。
- 干跑插曲（如实记）：先以 A 槽试跑得 409——当日计划步 idem 键已被生产 12:36 旧提示词轮占用，新提示词同键异载荷被 Hermes 拒。改走 B 槽（键带 B 后缀）即通。**生产影响评估**：明日 A 轮用新日期键、今晚 B 轮用 B 键，均为新键不受影响；仅「今日内再手动触发一轮 brief/manual」可能撞一次 409，明日自愈。idem 键格式受期一自测逐字约束，未改。

## 部署与验收（2026-11-11 约 17:0x）

- 备份：`/root/companion-121-deploy-20261111/`（旧 compose、companion.env、data-before.json、inspect-before.json、oneday_bridge.py.before）。
- 构建：`/root/build-121/` 打镜像 oneday/companion:1.0.21（模块 md5 与本地逐字一致）；prod compose＋env 版本位 1.0.20→1.0.21 后 `docker compose up -d` 只重建 companion。
- 验收实测：内存 4017/7725MB ≈ **52%**（红线 80% 内）；**Hermes StartedAt `2026-11-10T14:21:47.024396739Z` 逐字不变**；生产数据 feedPosts 2→2、ideas 6→6 完好；五模块端口均响应、front 200；`GET /feed/generation` 带 policy（tier 2／limit 1000）、nextRunAt＝明日 08:30、nextEditionBAt＝**今日 19:30**（B 版次今晚上线首发）、hourlyLog 已开始记档位 skip；`GET /feed` 帖面带 sources/line 键。
- 回滚：备份目录 compose/env 版本改回 1.0.20 重建即可（旧镜像在机；注意 1.0.20＝cx120 线，其 oneday_bridge 与 1.0.19 相同，回滚不丢期一功能，但会失去本包全部新机制）。

## 遗留与下一步

- 档位升档取决于 Tavily 套餐（1000/月）；若用户升到 ≥1500/月，次月自动进第 1 档（小时线开），≥1700 进第 0 档（adhoc 开）——建议在周复盘里带一眼 Tavily 用量。
- App 包 A（点赞接线＋why 呈现）契约已按 1.0.17 as-built 冻结，本包未动其面，可按原排期开工；帖面新增 sources/line 为纯加法，App 可择机消费（来源呈现）。
