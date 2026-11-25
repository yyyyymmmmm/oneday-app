# GOALS-GD1-REPORT（三页对标返工 · GD-1 目标活动状态派生）

日期：2026-11-12 ｜ 状态：**预制完成、自测全绿、未部署**（等主线审后部署）
规格依据：`three-pages-muse-parity-20261111.md` §4.3 GD-1（治 G-1/G-5 的派生部分）

## 一句话结论

`_goal_view` 新增读时派生字段 `activity`：目标页一次拉取即可拿到每个目标的
活动状态（在跑几件、卡住/失败几件、最近一条进展、最后活动时间），原料是
goalTaskLinks ＋ feed 轮询的 kanban 状态图，零网络、零落盘、零写数据。
160 个目标全量派生实测 7.7ms。

## 亲验结论（生产实数，只读查验，服务器内存 54%）

- **目标总数 1 个，且已 completed；goalTaskLinks ＝ 0 条；goalEntries ＝ 0 条。**
  link 只在「用户从目标详情页点委派」时产生，这条路生产上还没被用过——
  所以 GD-1 上线后，当前唯一目标派生为 idle/「暂无关联任务」，这是实情
  不是故障；link 稀缺是 GD-2（任务归组读面）的题，本包不越界造 link。
- kanban 快照健康：4 个任务全 done，轮询新鲜度 71 秒（300 秒一跳），
  kanbanNote 为 None；feed 事件环 14 条在账。
- 生产 `GET /goals` 基线：200，约 0.6–0.8ms/次（回环实测 3 次），
  现行字段 12 个（无 activity）。
- 工作区 `modules/oneday_bridge.py` 与生产 1.0.30 容器内文件 md5 逐字
  一致（f170ddee…）后才动工，diff 基线干净。

## 落法

- **派生位置**：`_goal_view` 末尾加 `activity`（列表/详情/创建/修改四条
  返回路径同源）；派生函数 `_goal_activity` 放在 goal-task-links 段末，
  与完成自动落账（既有一次锁）同区但完全只读。
- **原料**：`meta.feed` 的 `taskSnapshot`（taskId→原始状态）＋
  `taskTitles` ＋ `kanbanPolledAt` ＋事件环（近 7 天，装配时裁剪）——
  即规格指定的「复用 feed 轮询的 kanban 状态图」。请求路径不新增任何
  网络调用、不逐目标现查。
- **状态词**：规格四词 running/waiting/blocked/idle，不新造。原始 kanban
  状态按既有词表分桶：台账 `KANBAN_MAP` 键集（in_progress/doing/wip/
  review…→running；triage/backlog/todo/scheduled/ready→waiting）、桥内
  `_KANBAN_DONE_STATUSES`、`_KANBAN_BLOCKED_STATUSES`、FD-1 的
  `_FEED_TASK_FAILED_STATUSES`（failed/rejected）。**failed 折进 blocked
  状态词**（FD-1 已把 failed/blocked 作同一「停下」类分级），靠
  `failedCount` 与 focusTask 的原始状态透传保持可分辨。
- **决策优先级**：blocked（含 failed 且无 running）＞ running ＞
  waiting ＞ idle；blocked 与 running 并存时报 blocked（卡住是最响的
  事实，runningCount 仍在字段里，App 可并陈）。
- **`since` 是尽力而为**：取事件环里关联任务最近一次转入「驱动当前
  状态的桶」的时刻；环里没有就回 None，绝不回填猜测时间。
  `lastActivityAt` ＝ max（目标 updatedAt、最新条目、最新 link、
  关联任务最近事件）。
- **缺口不静默**：无 link→label「暂无关联任务」；link 不在快照→
  missingCount＋note；从未轮询→note「任务板状态尚未同步」；轮询失败→
  note 透传 kanbanNote；未识别原始状态→计数入 other 并在 note 注明。
- **契约登记**：STATUS-CONTRACT.md 新增第 9 面登记＋变更记账一行
  （R3：新状态面先登记）。

## 派生字段清单（`activity` 对象）

| 字段 | 含义 |
|---|---|
| `state` | running / waiting / blocked / idle |
| `label` | 代码模板拼装的事实句（如「1 件任务进行中，1 件待开始」「关联任务已全部完成」），非模型生成 |
| `since` | 当前状态驱动桶的最近观测转移时刻（事件环尽力而为，可为 null） |
| `focusTask` | 驱动当前状态的那件任务 `{id, title, status}`，status 为 kanban 原始状态原样透传；无则 null |
| `runningCount` / `blockedCount` / `failedCount` / `waitingCount` / `doneCount` / `cancelledCount` | 按桶计数 |
| `linkedCount` / `missingCount` | link 总数 / 不在当前快照里的 link 数 |
| `latestProgress` | 最新一条进展 `{text, at}`（与 latestEntry 同源同记录，非第二存储）；无条目为 null |
| `lastActivityAt` | 最后活动时间（见落法） |
| `polledAt` | 派生所读快照的轮询时刻（新鲜度，App 可明示） |
| `note` | 派生缺口注记；无缺口为 null |

## 与简报口径的一处偏差（待主线裁）

规格 §4.3 的 GD-1 还含「自动进展补两路」（关联任务转阻塞/失败落一条
事实进展、里程碑全勾完落一条）——那是**写** goalEntries 的路径，与本包
任务书「派生只读、不写不改」的硬口径冲突，本包**未施工**。建议单列
GD-1b：复用 `_record_completed_task_entries_locked` 的一次锁范式
（每 link 每类转移只落一条、防重复落账），与本包派生互不依赖。
注：里程碑全勾的 feed 事件已在 `_patch_goal` 侧发出（FD-1 A 级成帖在
用），GD-1b 主要是补目标进展条目这一路。

## 改动文件

- `modules/oneday_bridge.py`：`_goal_view` 加一行 activity；新增 GD-1
  派生段（`_kanban_bucket`、`_goal_activity`、三个桶集合常量），全在
  目标/关联区，其余零改动。
- `STATUS-CONTRACT.md`：登记第 9 面＋变更记账。
- `tests/oneday_bridge_p8_selftest.py`：新增（24 项）。
- `tests/run_bridge_selftests.sh`：注册 p8（cp 清单＋运行循环）。

## 自测

- **p8 24/24 全绿**：桶映射；四态（running/blocked 压 running/failed 折
  blocked/waiting）＋已完成目标全 done idle＋无 link idle＋cancelled；
  缺口五路（missing/未轮询/轮询失败注记透传/未识别状态/missing 不毒化
  在场任务）；latestProgress 按 createdAt 取最新（种子故意乱序）；
  lastActivityAt 真 max；只读证明（goals/entries/links/feedPosts 调用
  前后逐字一致）；性能（150 目标×3 link＋既有 10 目标，全量 7.7ms）。
- **HTTP 冒烟**（子进程真桥＋真 /goals）：activity 完整下发；时间戳用
  近实时值时 since/lastActivityAt 与 blocked 转移时刻逐秒对上。
  （首轮冒烟曾见 since=null，定因是夹具用了 2023 年固定纪元、被装配的
  7 天事件裁剪清掉——生产事件均为实时产生，不受影响；已换近实时夹具
  复验通过。）
- **全套对账**：改前/改后各跑一遍 `run_bridge_selftests.sh`，FAIL 集合
  逐字一致（三处既存红与本包无关）：p3 的
  「E adhoc opens at tier 1…」时间敏感存量红（与 FD-1/ID-1 报告记录
  一致）；device_sync「reminders count/list from copy」（两次仅时间戳
  不同）；rendition 503 出站环境红。p2/p4/p5/p6/p7＋新增 p8 全绿，
  p6 的完成落账一次锁回归无恙。

## 部署步骤与验收法（供主线审）

1. 同步 `modules/oneday_bridge.py`＋`tests/`（含 p8 与 runner）进镜像，
   重建 oneday-companion 容器；**无 env/配置/Hermes 改动、无数据迁移**；
   版本号请主线定（本地模板 COMPANION_VERSION 小账按主线口径一并对齐）。
   回滚＝单文件还原重部署。
2. 部署后验收：
   - 回环 `GET /goals`：现行唯一目标（completed、无 link）应回
     `activity.state == "idle"`、`label == "暂无关联任务"`、
     `linkedCount == 0`、`polledAt` 为近 300 秒内时刻；响应耗时与
     基线同量级（~1ms）。
   - 容器内 bridge 文件 md5 与工作区逐字一致；Hermes StartedAt 不变；
     内存回读。
   - 完整形态验收（G-A2 力学）：需一条真 link——在 App 目标详情页
     委派一件任务后，依次置任务 待跑/在跑/阻塞/完成 四态查
     `_goal_view.activity` 逐态对应（此步依赖 App 侧目标页消费字段，
     可与 GA 侧呈现包同窗验）。
