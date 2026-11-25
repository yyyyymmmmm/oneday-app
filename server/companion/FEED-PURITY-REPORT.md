# FEED-PURITY 报告：动态流纯化——只剩兴趣内容帖（2026-11-12）

用户 2026-11-12 02:12 亲定：动态不许「今天/昨天」时间分组、帖面
不许单独设色、**审批不要进动态、今日小结也不要进——和 Muse
一模一样**。本包否决 FD-1 的 digest/事件入动态设计：动态流只剩
兴趣内容帖（research），digest 帖与四类 A 级事件帖（待批新增／
监测转异常／目标里程碑／任务转 failed·rejected·blocked）退出
动态流。伴生 1.0.31 → **1.0.32**。

## 改了什么

只动 `modules/oneday_bridge.py`（另加测试、契约与版本面对齐）：

1. **停建（结构性，不是关开关）**：`_feed_assemble_locked` 重写
   为「事件账本维护＋存量封存扫」——不再分级、不再建帖。FD-1
   的成帖机器整段删除：`_feed_event_grade`、`_feed_event_category`、
   `_feed_event_object_key`、`_feed_event_post_content`、
   `_feed_event_post_upsert_locked`、`_feed_event_posts_locked`
   及 `FEED_EVENT_DAILY_CAP`、`FEED_EVENT_MERGE_SECONDS`、
   `_FEED_EVENT_WHY/PRIORITY/EMOJI`、`_FEED_DIGEST_EMOJI`、
   `_FEED_KIND_HEADS`。digest/event 在桥内已无任何创建路径
   （全仓复核：feedPosts 的 append 点只剩 research 两处与本包
   的封存标记）。
2. **事件账本保留**：事件源头全部不动——本地事件（点子/简报/
   监测变化）、远程轮询（kanban diff、审批增量）、监测转异常
   边沿（`_record_check_locked`）、里程碑全勾（`_patch_goal`）
   照旧入 `meta.feed.events` 账本，只喂 `eventsToday` 计数与
   kanban 快照的既有消费者（GD-1 的 `taskSnapshot` 等）。生产者
   注释已改口径（原「assembler turns it into a post」等表述
   清除）。`_FEED_TASK_FAILED_STATUSES` 保留（GD-1 `_kanban_bucket`
   共用）。
3. **存量封存（软删）**：新增 `_feed_archive_impure_locked`，
   装配器每跳（20 秒）扫一遍：kind ∈ {digest, event} 且未封存
   的帖原地打 `archivedAt` 戳，累计计数入 `meta.feed.purityArchived
   {digest, event}`；封存到当日 digest 时同步结清 `digestPostId`
   与 `digestEventKeys`（与用户删除时的结清口径一致）。帖子记录
   不删、按 id 仍可读（`_feed_view` 新增 `archivedAt` 字段透出）、
   用户删除路径不变（仍可彻底删除且删后不复活——复活机器已
   随 FD-1 成帖代码删除，结构上不可能再建）。
4. **流与计数排除封存帖**：`_list_feed`（GET /feed）过滤
   `archivedAt`；`_feed_generation_view` 的 `unread` 同步排除，
   assembly 视图新增 `purityArchived` 键（STATUS-CONTRACT 第 7
   面已登记，`digestPostId` 自纯化起恒 null）。
5. **零触碰**：兴趣内容帖生成链（agent-first 抓取、keyStamp、
   readAt 语义）一行未动；通知通道（overview 的
   `_make_notification` 与通知存储）与聊天审批卡本就不经
   feed 存储，本包亦未动——审批照常只走通知与聊天卡。

## 自测（改前/改后对账）

- p3 改写：Phase A 由「装配出 digest」改为纯化口径（种子带
  1 digest＋1 event 存量帖：账本仍记 3 事件、两帖被封存且
  按 id 可读、流列表为空、unread 不计封存帖、删除封存帖
  照常）；Phase G 整段替换（原 FD-1 25 项 → 纯化 17 项：
  A/B 级事件均不产帖、存量按 kind 计数封存、二次装配幂等、
  封存不改 readAt、里程碑/监测边沿仍只入账本一次）。
  Phase A 14/14、Phase G 17/17 全过。
- 全套 FAIL 集合改前/改后逐项一致（三组存量红，与本包无关）：
  ① p3 Phase E「adhoc opens at tier 1…」（Tavily 档位时间敏感，
  FD-2/K-2 领地）；② device_sync reminders count/list（夹具
  时间戳过期，载荷除 `synced_at` 时间值外逐字同）；③ rendition
  7 项 503（既存出站问题）。其余全绿（overview、p2、p4、p5、
  p6、p7 26/26、p8、device、write-gate 三套、spreadsheet、
  delivery、sentinel、ledger）。

## 部署与生产实证

- 部署前：内存 54%（红线 80% 内）；Hermes StartedAt
  `2026-11-10T14:21:47.024396739Z`，部署后逐字不变。回滚点
  `/root/companion-132-deploy-20261112/`（compose/env/
  oneday_bridge.py 三件 1.0.31 备份＋镜像 `oneday/companion:1.0.31`
  保留）；构建目录 `/root/companion-132-build`。
- 版本四处对齐 1.0.32：生产 compose image＋env、companion.env、
  容器内回读、front 进程 environ 回读均为 1.0.32；本地模板
  compose（image＋env）与 Dockerfile ARG 同步（模板 image
  标记此前滞留 1.0.29，本次一并归正）。容器内 bridge md5
  `7367b0bf727dd29ba895062fcf67bf85` 与工作区逐字一致。
- **存量移出（生产实数）**：部署前流内 9 帖（digest 3、event 3、
  research 3）。首跳封存 **digest 3**（含 1 帖 pre-FD-1 的
  「今日动态 · 3 件」与 2 帖「今日小结」）＋**event 3**（均为
  待批事件帖）；`purityArchived={digest: 3, event: 3}`，
  `digestPostId=null`，9 帖记录全数留账（封存后存储内仍 9 帖）。
- **手动轮验收**：POST /feed/generate → 202 started；本轮
  rec：trigger=manual、status=ok、produced 3、dropped 0、
  keyStamp=`20261112-1794421497`（新戳，非重放）。轮后存储
  12 帖：research 6（新增《榜首 Astryx 涨星背后有真组件和
  安装入口》《Agents SDK 的 Runner 怎么跑、在哪失败》
  《零预算30天：512用户里28人付费的获客拆解》）、digest/event
  仍各 3 且全封存、计数不变。
- **GET /feed 回读（终态，逐帖 kind 清单）**：6 帖全 research
  ——f_9a4226bc984c、f_7b2e9b58f39a、f_3d38afe3e3f4、
  f_531413d0dea3、f_6b47605a0297、f_054aa78e8b4d。动态流内
  digest/event 为 0。unread=3（即 3 帖新内容帖，口径正确）。

## 备注

- App 侧配套（动态不做「今天/昨天」分组、帖面不单独设色）
  不在本包范围（伴生侧无分组/设色概念，流顺序仍纯时间倒序），
  由 App 线按用户同条口径处理。
- FD-1 报告中「②③④三路待真实事件复核」一项随设计退役自动
  关闭：三路事件今后只入账本，可由 `eventsToday` 与账本记录
  复核，不再有成帖形态可验。
