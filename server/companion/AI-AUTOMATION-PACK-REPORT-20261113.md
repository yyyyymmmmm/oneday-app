# AI 内部权限 P4 自动化包＋P5 触达包 — 完工报告（2026-11-13）

**已施工、已部署、已验活。** 伴生升 **1.0.42**：oneday 桥新增自动化门面
`POST /automation-mcp`（与 goals 门面同形的 MCP streamable-http JSON-RPC
面），共 6 个工具——P4 定时三件（cron_create / cron_list / cron_delete）、
P4 派活两件（kanban_create_task / kanban_get_task）、P5 触达一件
（reach_send）。每个调用先落 P0 留痕再回执；桥内 watcher 线程把定时
触发、任务完成、排队补发折成留痕。门面**未注册进 Hermes**——交付状态
＝「门面就绪待注册」，注册等收官窗口与 goals /mcp 一并办（见 §七）。
Hermes 全程未动、未重启（StartedAt 部署前＝部署后＝
`2026-11-10T14:21:47.024396739Z`）；App 仓库未碰；kanban 自动审核员
未动；现有定时任务未动（引擎 jobs 部署前后均为 0，探针任务验完即删）；
**P5 没有真发任何测试消息**（生产验证只走 dryRun，账本 agent_message
行数 0→0 实测）。

生产桥文件 md5 `768025085db063d166d6e8a47fd02ac7`，与工作区副本逐字
一致。改动文件：`modules/oneday_bridge.py`（新增一节门面＋三处集合
登记＋路由一行＋main 启动一行＋文件头端点清单）、
`tests/oneday_automation_selftest.py`（新增，已登记进
`tests/run_bridge_selftests.sh` 的 staging 名单）。

## 一、门面契约

- 路径 `POST /automation-mcp`，Bearer `<ONEDAY_BRIDGE_KEY>` 鉴权（与桥
  其余面同钥，fail-closed）；serverInfo name=`oneday-automation`。
- 上游通道：cron REST 与 kanban 插件 API 都是 Hermes **Dashboard**
  路由，走桥内既有的 cookie 登录通道（`HERMES_DASH_USER/PASSWORD`
  password-login，登录缓存复用、401 自动重登一次）——不是 Bearer API
  钥。此点施工前经服务器源码与生产探针双证实。
- 上游失败一律抛错进留痕（HTTP 状态＋detail 原文截断 300 字），不折
  成空数据、不假成功。

### P4 定时（cron_create / cron_list / cron_delete）

- 落 Hermes cron 引擎现行口径：桥只调 Dashboard
  `POST/GET/DELETE /api/cron/jobs`，不另造调度器；jobs 存储与触发
  语义全用引擎的。
- **归属硬要求**：`ownerSessionId` 必填（缺失直接拒＋failed 留痕）；
  `echoSessionId` 缺省＝归属会话。桥侧绑定表 `cronBindings`
  {jobId, name, ownerSessionId, echoSessionId, schedule, createdAt,
  seenLastRunAt} 持久化进桥 data.json。
- `deliver` 强制钉 `"local"`：引擎不得把触发产出推到任何外部通道；
  回响之家是留痕流（见下）。
- **删除纪律**：只删门面所建的任务；面板/命令行/系统的任务不在绑定
  表内，cron_delete 一律拒绝（自检与契约双证）。
- watcher（60 秒一轮）对每个绑定读引擎 job：`last_run_at` 变化即折
  一条 `cron.fired` 留痕（ok 按 last_status，failed 带 `last_error`
  原文），target 点达该 job、detail 带 ownerSessionId/echoSessionId，
  同一 run 只折一次；job 在引擎侧消失则折 `cron.orphaned` failed
  留痕并清绑定（不静默丢）。
- **与现行口径的边界（C1）**：只有「AI 经门面建＋带归属」的定时任务
  进绑定表、得会话回响；其余来源的定时任务（CLI/面板/系统）不进绑定
  表，其会话仍按现行口径归工作台账，本包不碰。

### P4 派活（kanban_create_task / kanban_get_task）

- 落 kanban 插件现行 API：`POST /api/plugins/kanban/tasks?board=oneday`
  （title 必填，body/assignee/priority/parents/idempotencyKey 透传），
  查走 `GET /tasks/{id}`。父子关系用插件原生 `parents` 字段。
- **归属硬要求**同 cron：`ownerSessionId` 必填；绑定表
  `kanbanBindings` {taskId, title, ownerSessionId, goalId, createdAt,
  lastStatus, doneTraced}。
- 带 `goalId` 时先验目标存在（不存在在建卡前拒），再复用既有
  `goalTaskLinks` 链挂卡——目标的「事实型完成进展」既有机制原样
  工作，本包不另造。
- watcher 用桥既有 `_fetch_kanban_tasks()` 读板：绑定卡进入完成态
  （`_KANBAN_DONE_STATUSES` 既有词表）即折 `kanban.completed` 留痕
  （target 点达卡、detail 带 ownerSessionId/goalId），只折一次。
- kanban 自动审核员保持现状，未动一行。

### P5 触达（reach_send）

- 复用现行通知设施：往 oneday 桥既有的通知账本
  `monitor-notifications.jsonl`（overview 桥通知中心的读取源）追加
  记录，`kind="agent_message"`，字段与 monitor 记录同形（id/title/
  body/createdAt/read/refId/changeId）。overview 的
  `_make_monitor_notification` 对 kind/title/body 全透传（源码实查），
  故零改 overview 即上架通知中心；不新造第二套通知系统。
- **必带来源与落点**：`sourceAction` 必填（缺失拒绝）；`refSessionId`
  为回响/点达会话，进账本 refId 与留痕 target。
- **频度护栏**：主动时段口径 [09:00, 21:30)（Asia/Shanghai，左闭右
  开，纯函数 `_proactive_in_window` 自检钉死四个边界点）。窗内直送
  账本；**窗外入队** `proactiveQueue`（status=queued），watcher 在
  窗口打开后逐条补发（追加账本＋标 sent＋补 `reach.delivered`
  留痕），排队不丢；队列 sent 历史保留上限 200 条。
- `dryRun=true`：只落留痕（结果明写「干跑：未发送，仅留痕」），绝不
  写账本——生产验证即走此通道。
- 通知正文上限按 overview 呈现口径截 300 字（结果带
  bodyTruncated 标志，不静默截断）。

### 留痕（全动作接入 P0）

- 每个 tools/call 恰一条 P0 留痕、先痕后答：动作命名空间
  `cron.create / cron.list / cron.delete / kanban.create_task /
  kanban.get_task / reach.send`；watcher 另出 `cron.fired /
  cron.orphaned / kanban.completed / reach.delivered`。五要素照 P0
  契约（action/target 点达/时间/结果摘要/失败原文），失败与成功
  同级、未捕获异常落 `类型: 原文`。
- 生产实测留痕样例（部署后门面直调产生，现存于生产 /traces）：
  cron.create ok「定时任务《[selftest] 1.0.42 facade probe》已创
  建（0 9 * * *）」、cron.delete ok、kanban.create_task ok、
  reach.send ok「干跑：未发送，仅留痕（验证通道）」各一条。

## 二、自验（数据层，三层）

1. **本地自检 `tests/oneday_automation_selftest.py`：35/35 全绿。**
   stub Hermes（cookie 登录＋cron REST＋kanban 插件＋board）＋真桥
   HTTP 面＋可控时钟。覆盖：六工具清单；无归属建任务/建卡被拒＋
   failed 留痕；cron 建卡 payload 钉死 deliver=local 与默认时区；
   绑定落盘＋换进程重载仍在；cron_list/delete 纪律（拒删外来任务）；
   watcher 对同一 run 只折一次、失败 run 留痕带 last_error 原文、
   job 消失折 orphaned 并清绑定；kanban 完成折痕只一次；reach
   干跑零落账、窗内落账本（kind/refId 实查）、窗外排队、关窗不
   flush、开窗补发＋reach.delivered 留痕；窗口四边界点。
2. **同仓回归对跑**（staging 法）：P0 留痕/目标自检 34/34、P2 会话
   自检 28/28，拼接后零新增失败。（注：这两个自检必须经
   run_bridge_selftests.sh 的 staging 摆法运行，直接在 tests/ 下跑
   会因找不到同目录桥文件报 "bridge did not come up"，与代码无关，
   已实证。）
3. **生产实测**：
   - 上游原生探针（Dashboard API 直调）：cron 建（paused）→查→删→
     列表回 0；kanban 建（t_5cdf9f80）→查→删→查 404。验完清理。
   - 门面直调（生产桥 8646，钥自模块进程 environ 取）：tools/list
     六工具齐；cron_create 得 job `11871aad7821` → cron_list 含之
     → cron_delete 成功 → 引擎 jobs 回 **0**；kanban_create_task 得
     `t_05e11c4c`（status ready）→ kanban_get_task 对上 → 经插件
     API 删除（门面按设计不提供删卡）→查 404；reach_send dryRun
     回 delivered=false 且账本 agent_message 行数 **0→0**；四条留痕
     在生产 /traces 逐条读回（见 §一末）。
   - data.json 落盘实查：cronBindings 删后归 0、proactiveQueue 0、
     traces 累计 15 条（含量子线各包验证痕）。

## 三、部署记录（叠层法，沿 1.0.39 先例）——含一次同号撞车

- 构建目录：服务器 `/root/autopack-1041/`（Dockerfile＋桥文件留底）。
- 最终生产版本 **1.0.42**：`FROM oneday/companion:1.0.41`＋COPY 工作
  区 `oneday_bridge.py`；compose 与 companion.env 的
  COMPANION_VERSION 均 1.0.42；容器 StartedAt
  `2026-11-13T05:44:17Z`；部署后 90 秒＋全程复查，容器镜像/桥文件
  md5 稳定未再被覆盖；服务器内存全程约 57%（4402/7725 MB）。
- **撞车实录（请主线周知各线）**：我先以 1.0.41 构建部署（05:41:18
  容器启动、验活通过），16 秒后（05:41:34）另一条线以**同一版本号
  1.0.41** 重建镜像并重起容器——其构建上下文里的 oneday_bridge.py
  是 1.0.39 时代的旧副本，桥文件被整体回滚（门面路由消失、直调
  404，据此定性）。逐文件 md5 对账确认：对方载荷（identity 等其余
  模块）与工作区逐字一致、回滚只伤桥文件本身。故我改以 **1.0.42**
  从当时的 1.0.41 镜像重叠部署，对方载荷零损失、桥文件恢复为工作
  区全量版（P0/P3＋P2 aiSessions＋本包门面）。**后续各线构建务必以
  当前工作区 oneday_bridge.py 为源、勿用旧构建目录副本，版本号
  先占先得、勿同号重建。**
- 顺带说明：生产桥文件现含 P2 线的 aiSessions 面（REST＋
  /mcp-sessions 门面，其自检 28/28 已随本包对跑）——它随工作区全量
  文件一并上线，P2 线后续部署同文件即无差异。

## 四、回滚

- 配置备份（服务器 `/www/dk_project/dk_app/companion/`）：
  `docker-compose.yml.bak-1.0.40-20261113`、
  `companion.env.bak-1.0.40-20261113`、以及 1.0.42 部署时的
  `.bak-1.0.41-20261113` 两件；数据备份
  `/www/dk_project/dk_app/oneday-bridge/data/data.json.bak-autopack-20261113`。
- 回滚动作：恢复目标版本的 compose/env 备份 → `docker compose up -d`。
  **注意**：回滚到 1.0.41/1.0.40 的桥不认 cronBindings /
  kanbanBindings / proactiveQueue 三个新集合，其首次保存会丢弃这
  三个集合（量级小：绑定与排队数据；traces 集合自 1.0.39 起已认，
  留痕不丢）。如需保住队列/绑定，先导出 data.json 对应段再回滚。

## 五、诚实边界与待对齐项

1. **回响落点**：触发/完成/补发的回响目前落 **P0 留痕流**（target
   点达归属会话/任务，可达可查）；「往归属会话内直接发帖呈现」依赖
   P0-App 回响渲染与 P2 的会话口径，未在本包实现，不冒充已通。
2. **派生会话父子关联（待 P2 对齐）**：卡→归属会话的绑定与完成回响
   已按审计口径先行；卡派生的执行会话 id 目前仅在板面任务对象给出
   时透传记录（`_kanban_task_view` 预留 sessionId），板面未稳定提供
   该字段，待 P2 出生证明口径定稿后对齐补齐。
3. **已删卡的绑定残留（小缺口）**：生产 data.json 现留一条本包自检
   绑定（kanbanBindings 中 taskId `t_05e11c4c`，卡已删、ownerSessionId
   `selftest-1042`）——watcher 目前只折完成、不清「板面已删卡」的绑
   定（cron 侧有 orphan 清理、kanban 侧未补）。该行仅内部记账、不
   产生任何回响与用户可见数据；建议后续小包按 `kanban.orphaned`
   同口径补齐清理，本包如实留痕于此。
4. **App 渲染未验**：通知中心对 `kind="agent_message"` 的呈现（图
   标/点达跳转）未在本包验证——账本契约与 overview 透传已源码级证
   实，App 侧渲染归 P0-App/P2 线验收范围。
5. **cron 回执字段**：引擎创建回执不回显 `paused`（生产实测），门面
   视图的 paused 以随后 GET 读回为准；不影响调度语义（探针任务以
   paused 建、未触发、已删净）。
6. 窗口外排队消息的补发依赖 watcher 存活；watcher 异常只打模块日
   志（与交付哨兵同纪律，不拖垮桥），其存活可由容器日志
   "automation watcher started" 与补发留痕侧证。

## 六、红线核对

- 未注册进 Hermes、未改 mcp_servers、未重启 Hermes（StartedAt 逐字
  未变）；伴生容器重建属自动部署既有口径。
- 未真发测试消息：P5 生产验证仅 dryRun（账本行数 0→0 实查）；窗内
  直送与窗外排队/补发均在本地 stub 环境验通，未拿真用户通道试。
- 未动现有定时任务（jobs 0→0）、未动 kanban 自动审核员、未删改
  任何真实目标/任务数据；探针任务与卡均验完删除（绑定残留一条见
  §五.3，如实登记）。
- App 仓库零改动（本包无 App 接线需求）。

## 七、待收官窗口注册项（给主线）

- Hermes `mcp_servers` 新增自动化门面一项：指向桥
  `POST /automation-mcp`（与 goals 的 `/mcp` 同窗注册、同钥口径），
  注册后按设备桥复验纪律实查工具数＝6 并逐个冒烟（cron 造删一条、
  kanban 造删一张、reach 只干跑）。
- 注册时一并核前置路由（nginx/front）是否需放行 `/automation-mcp`
  到 oneday 模块 8646（桥内路由已就绪，生产本机直调已通）。
