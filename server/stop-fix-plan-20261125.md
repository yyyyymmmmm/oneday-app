# stop 修法包 · 施工方案＋回滚基线（草案，待主线报批）

- 立项依据：`oneday-design-review/stop-button-server-rca-20261125.md`（等待框定性，2026-11-25 04:40–04:52 取证）＋`zombie-settle-20261125.md`（僵尸结算记录，遗留项 E 的出处）。
- 本文件性质：**只起草、不施工**。未改包内任何现行文件、未动服务器、未重启任何服务。施工须主线报用户批准后，按本包 RULES.md §1 铁序（先入包→递增版本→install.sh 应用→verify.sh 留档）执行。
- 一句话目标：让「失联（unknown）」从一条无出口的死状态，变成 stop 可处置、契约有指引、总览有露头、部署不留尸的正常状态面；顺带清掉僵尸结算遗留的幂等快照陈旧问题。

## 事故根因链（RCA 定版，方案逐件对位）

部署重启 drain 未跑满进程即非正常退出 → 在飞 run 变 unknown → 真人 run 的 unknown 无自动收尾、无告警露头（失联 1 小时 40 分无人知晓）→ stop 契约不覆盖 unknown 且 409 不带下一步指引（App 连打 150 次全 409）→ 投影把 unknown 当「还在生成」→ 用户看到等待框永远停不下来。另：resolve-unknown 结算不回写 runs_idempotency 快照，结算后快照仍停 `running`（僵尸结算如实记录在案）。

## 版本与能力登记建议

- 包版本：现行 **2.6.0 → 2.7.0**（minor：新增能力——stop 失联分支、409 契约增字段、总览新聚合源、部署 drain 机制；无能力退役、目标镜像不变）。
- CAPABILITIES.md 新增 **#45「stop 失联收尾＋unknown 露头」**（现行最大 #44），五件合并登记一行，探针列写本方案 §7 的自测与 verify 新节。
- manifest.yaml：version/released 更新；`api_server_runs.py`、`overview_gateway.py` 两条目 sha256 与 diff_lines 在施工后按合并结果重算登记；compose 模板变更在 services 条目注记。

---

## A. stop 覆盖失联态：命中 unknown 且所有者确已死亡 → fenced settle，不再只抛 409

**现状落点（已查实）**：`patches/api_server_runs.py` 的 `_handle_stop_run`（约 L2325）在 session_authority 在场时，把 stop 委托给上游模块 `gateway/platforms/api_server_authority_runs.py` 的 `stop_run`；该函数对 unknown 状态抛 `RuntimeStoreError('unknown_execution')`，handler 经 `store_error_response` 默认映射 409——在执行层之前就拒绝，150 次全灭于此。`resolve_unknown_run`（同上游模块）已含 fenced settle 全套语义（authority.resolve_unknown → resolve_unknown_session_input，fenced 事务内落 terminal/interrupted，僵尸结算已实证此路径），但只挂在独立的 resolve-unknown 端点上，stop 不经过它。

**改法（包内 handler 层分流，上游 authority 模块零改动）**：在 `_handle_stop_run` 的 authority 分支外包一层：

1. 先照旧调 `stop_run`；queued／started／terminal 的行为与现行逐字一致（queued 直接 cancel、started 走 hard interrupt、terminal 原样回执），本件不碰。
2. 捕获 `RuntimeStoreError` 且错误码为 `unknown_execution` 时，进入失联分支，**按硬证据判所有者存亡**（三条全满足才算「确已死亡」，照 RCA 风险口径，材料不足一律退回 B 的 409＋next_action，绝不猜死）：
   - admission 状态仍为 `unknown`；
   - admission 的 `owner_epoch` ＜ 当前 `runtime_epoch`（所有者 epoch 已被后续重启取代）；
   - 该会话 `worker_executions` 行数＝0（无任何活执行体）。
   证据读取走 handler 已持有的 session_authority／runtime store 读面（与 RCA 取证同源：state.db 的 session_admissions／worker_executions／runtime_epoch），只读。
3. 三条全满足 → 在**同一请求内**调用既有 `resolve_unknown_run` 的同一内部链（admission_id＋execution_generation 从 admission 行现取，即僵尸结算时人工传的那两个值改由服务端自取），fenced settle 为 `interrupted`，**绝不重放执行**（守住 unknown 防重放的设计意图，只是把「确认失联」从人工隐藏路径变成 stop 的内置分支）。回执照 resolve-unknown 既有形状：`{run_id, admission_id, sequence, status: "terminal", outcome: "interrupted", authority_epoch, execution_generation}`，另加一字段 `settled_via: "stop"` 供客户端与审计区分来源。
4. settle 成功后接 E 的快照刷新助手（同一函数，两条路径共用），再返回回执。
5. 分支内任何异常：吞掉 settle 尝试、回退到 B 的 409＋next_action 响应并 warning 留痕（带 run_id／admission_id／失败原因），不许让 stop 本身 500。

**动哪些文件**：仅 `patches/api_server_runs.py`（`_handle_stop_run` authority 分支增分流＋新增一个内部助手 `_settle_lost_run_via_stop` 与证据读取小函数）。上游 `api_server_authority_runs.py` 不新增全文件补丁（避免为一个分支多养一份上游全文件补丁；若施工时发现证据读面在 handler 层拿不到——例如 authority 对象未暴露 epoch／executions 读口——才启用备选：新增 `patches/api_server_authority_runs.py` 全文件补丁，照 web_routers_ops.py 先例登记 upstream_baseline_sha256，改动只限 `stop_run` 一处。此备选须在施工报告中明示触发原因。）

**验证**：自测以假 authority／假 store 注入四种形态——unknown＋三证据齐 → settle 被调、回执 terminal/interrupted；unknown＋任一证据缺 → 不 settle、走 B 响应；queued／started → 与现行路径逐字同（回归断言）；settle 抛异常 → 回退 409＋next_action 不 500。应用后行为验见 §7 复现实验。

## B. 409 响应带 next_action 指引（＋投影面补失联原因）

**现状落点**：`store_error_response`（上游）产出的 409 体只有错误码与文案，没有机器可读的下一步；App 不知道该转 resolve-unknown，只能盲目重试 stop。另 RCA 修法 B：GET 投影把 unknown 原样透传，App 无从知道「已失联、可丢弃」。

**改法（分两半，落点不同）**：

1. **409 增字段（本包必做，handler 层）**：`_handle_stop_run` 捕获 `unknown_execution` 且未走 A 的 settle（证据不足）时，不再裸抛 `store_error_response`，改为同形状 409 错误体＋增字段：
   - `next_action: "resolve_unknown"`；
   - `admission_id`、`execution_generation`（从 admission 行现取，App 转调 resolve-unknown 时原样带上，免它再猜）；
   - `resolve_endpoint: "POST /v1/runs/{run_id}/resolve-unknown"`；
   - `reason: "owner_lost"`（owner 存亡不明时写 `"owner_status_unconfirmed"`，与 A 的已证死严格区分）。
   字段挂在错误体的顶层并同步进 `error.details`（双写，兼容不同客户端的读取习惯）；旧客户端忽略增字段即可，向后兼容。A 分支 settle 失败回退时也走这同一响应构造函数（DRY，单源）。
2. **投影增字段（施工首步先定位，二选一落点）**：GET /v1/runs/{id} 对 unknown 的投影增 `status_reason: "owner_lost"` 与 `available_actions: ["resolve_unknown"]`（已证死时另含 `"stop"`，因 stop 已可直接处置）。投影构建点若在包内已补丁文件（如 api_server_runs 的状态读面）则就地加；若在上游 authority／projection 模块，则与 A 的备选合并为同一份上游全文件补丁，只动投影函数一处。**施工第一步先把投影构建点查实写进施工报告，再定落点，不许两处都改。**

**App 半边施工要点（不在本包，仅供 App 线另行施工）**：

- stop 收到 409 且体含 `next_action: "resolve_unknown"` → 用体内 admission_id＋execution_generation 自动转调 resolve-unknown，成功后刷新该 run 状态为终态，不再重试 stop。
- GET 投影 `status == "unknown"` → 呈现「任务已失联，可丢弃」，停止生成指示，不显示无限等待；`available_actions` 决定按钮面。
- 活跃状态呈现按会话隔离：旁会话的失联态不绑主对话的生成指示（RCA §1 坐实的呈现错位，服务端契约给足信息后 App 侧解绑）。

**验证**：自测断言 409 体四字段齐、形状与旧错误体兼容（旧字段不丢）；投影断言 unknown 带 reason／actions、其余状态不带。应用后以 §7 复现实验中「证据不足」形态验一次真实 409 体。

## C. 真人 run 失联超时在总览露头告警

**现状落点**：`patches/overview_gateway.py` 已有 G1 读时聚合源先例（2.4.0 的 `cron_failed`／`kanban_failed`：读时聚合、born unread、计入 /overview 未读数、since 基线防回灌、error 只投影一行去敏摘要）。unknown 失联目前无任何源消费它——本次失联 1 小时 40 分钟无人知晓，直到人工取证。

**改法（照 G1 同式新增第三类任务侧源 `run_unknown`）**：

- 数据源：只读打开 `/opt/data/state.db`（`file:...?mode=ro`），查 `session_admissions` 中 `status='unknown'` 的行；与 cron 源同纪律——只读消费，不写 state.db、不代为 settle（处置权留给 stop／resolve-unknown，露头只负责让人看见）。
- 产条目条件：失联时长（now − admission 入 unknown 的时刻，以行内时间字段为准；字段口径施工时按 state.db 实际 schema 定，取 updated_at／created_at 中能代表入态时刻者并在施工报告注明）**＞ 10 分钟**（常量 `RUN_UNKNOWN_ALERT_MIN_AGE_S = 600`，写死在模块顶部、注记可调）。阈值理由：无人值守来源的 unknown 会被系统自动 settle（RCA 定性 5），10 分钟足够避开正常收尾竞态；真人 run 超过 10 分钟仍 unknown 即非正常。
- 条目形状：一条 admission 一条（稳定条目 id 由 admission_id 派生，重复轮询不增殖）；born unread、计入未读数（与 cron_failed／kanban_failed 同口径，与 pending 不计的口径区别照 G1 §4.3 先例）；正文只投影一行摘要（run_id 短形、会话短形、失联时长、owner_epoch 与当前 epoch），不带任何 payload／消息内容；附处置动作描述符（指向 stop／resolve-unknown，供总览面渲染一键处置入口，实际处置仍走 A／既有端点鉴权）。
- 基线防回灌：新增 `run_unknown_since` 基线（照 cron_since／kanban_since 同式），首启写基线、上线前存量 unknown 不补发（本件应用时若僵尸已结算、存量应为 0，仍按式落基线防未来回灌误报）。
- 消音：admission 一旦 settle（不再 unknown），下一轮聚合自然不再产出（照 resolved incidents 静默同式），不留残条。

**动哪些文件**：仅 `patches/overview_gateway.py`（新增一个聚合源函数＋源登记＋基线键）。不动 oneday_gateway／台账面。

**验证**：自测以 fixture state.db 造三行——unknown 20 分钟（应产 1 条、born unread、未读数 +1）、unknown 2 分钟（不产）、已 settle 的旧 unknown（不产）；基线前存量不回灌；同 admission 二轮仍一条。应用后活验：§7 复现实验产生的 unknown 等过阈值（或临时以 fixture 行验）→ /overview 出现条目 → settle 后消失。

## D. 部署 drain 纪律落成机制

**现状证据（已查实，含一个此前未点透的机制差）**：

- 网关侧 drain 上限 30 秒（RCA 日志：「waiting up to 30s」）；当晚旧进程 SIGTERM 03:08:42 → 03:09:02 即记 `exited UNCLEANLY, no exit path ran`，drain 没跑满就死了。
- **包内 compose 模板 `services/hermes-compose.template.yml` 与现行 compose 均无 `stop_grace_period`** → Docker 在 SIGTERM 后默认只等 **10 秒**就 SIGKILL。30 秒的 drain 装在 10 秒的容器停机窗里，必然被砍——这是 drain 未满的头号嫌疑机制（与时间线吻合：约 20 秒内含 compose 侧开销后进程非正常退出）。install.sh 的重启走 `docker compose up -d --force-recreate hermes`（约 L750）与 `docker restart hermes`（回滚路径 L162、正路 L752），两路都受 compose 的 stop_grace_period 约束（docker restart 同样读该值）。

**改法（三件，机制＋检查项）**：

1. **停机宽限对齐 drain**：compose 给 hermes 服务加 `stop_grace_period: 45s`（drain 30s＋退出路径与落盘余量 15s）。落点：包内 `services/hermes-compose.template.yml` 模板同步＋现行部署目录 docker-compose.yml 经 install.sh 的 compose 变更通道改（留 `.bak-YYYYMMDD-stopfix`，原地改写保 inode 口径照 RULES §5）。此后任何路径的重启都先等满 drain 再谈强杀。
2. **重启前在飞 run 检查（install.sh 前置检查项）**：在 install.sh 的重启步之前加一段只读检查——容器内查 state.db 非终态 admission 计数（status ∈ started／queued／unknown 分开报数）。有在飞（started／queued）时：打印醒目警告＋计数，先等一轮（每 10 秒复查、最长 60 秒）等其自然收尾；超时仍有在飞，则中止应用并提示改期，或由操作者显式设 `DEPLOY_ALLOW_ACTIVE_RUNS=1` 强行继续（强行时把计数与时刻写进应用记录——留痕口径）。unknown 存量单列提示（不拦重启，但提示先 settle 或重启后经 C 面处置）。
3. **重启后失联对账（install.sh 收尾＋verify.sh 探针）**：重启完成、health ok 后，数一遍 `status='unknown'` 且 owner_epoch ＜ 当前 runtime_epoch 的 admission 条数，写进 install 输出与应用记录；＞0 时输出醒目行（run_id 清单），与 C 的总览露头互为双保险。verify.sh 新增对应探针（见 §7）。

**检查项清单（写进应用记录模板，逐项打勾）**：重启前内存检查过／在飞计数已查且处置方式已选／SIGTERM 时刻、drain 完成日志行、旧进程退出路径日志行三件已摘录／重启后 unknown 对账数已记。

**验证**：静态——模板与现行 compose 含 stop_grace_period、install.sh 含检查段标记；行为——§7 复现实验中在有在飞 run 时走一次完整 install 重启，验 drain 日志跑满、旧进程走正常退出路径（无 UNCLEANLY）、在飞 run 或完成或被显式 settle，不再无声变僵尸。

## E. runs_idempotency 快照在结算后刷新为终态

**现状落点（僵尸结算记录已查实机制）**：runs_idempotency.db 的 status_json 快照只由属主进程的活体状态机驱动——`patches/api_server_runs.py` 的 `_set_run_status`（L1051）在状态变更时经 `self._run_idempotency_store.update_status(run_id, current)` 落盘（L1073）。属主进程死亡后，resolve-unknown 走的是 authority／state.db 一侧，**根本不经过 runs 层**，故结算后快照仍停在提交时的 `running`（updated_at 未变）。它只是原 POST 的防重放凭据、不参与 FIFO 与 GET 投影，但陈旧 `running` 会误导一切读快照的诊断与未来的重放回执（重放时「状态取当前 durable 状态」取的正是它）。

**改法（runs 层补一条结算后刷新，两条结算路径共用）**：

- 在 `patches/api_server_runs.py` 新增助手 `_refresh_idempotency_snapshot_after_settle(run_id, outcome)`：构造与 `_set_run_status` 同形状的终态记录（`status: "interrupted"`、`last_event: "run.interrupted"`、`error: "Run owner lost; settled as interrupted."`、updated_at=now；outcome／终态映射与 GET 投影口径一致——投影层把 terminal/interrupted 呈为 cancelled，快照存 runs 层原生词 `interrupted`，与 `_mark_shutdown_interrupted_runs` 的既有写法同词），直接调 `self._run_idempotency_store.update_status(run_id, record)` 落盘。
- 调用点两处：①`_handle_resolve_unknown_run`（约 L2360）在 `resolve_unknown_run` 成功返回后；②A 的 stop 内置 settle 成功后。两处共用同一助手，单源。
- **失败不拦结算**：刷新全程 try/except，失败只 warning 留痕（带 run_id），绝不让快照问题把已经成功的 settle 回执翻成错误（结算本身在 state.db 已落终态，那是真源）。
- 存量不回刷：已结算的僵尸 run_136 快照保持原样留痕（其结算记录已如实登记该陈旧状态；本件只保证今后每笔结算当场刷新，不写一次性回刷脚本动存量）。
- 注意 `_set_run_status` 的既有门（run_id 须在 `_run_idempotency_ids` 且 should_persist）对死主 run 在新进程里不成立——这正是不能复用 `_set_run_status` 、必须直调 store 的原因，施工时在助手注释里写明。

**验证**：自测以假 idempotency store 断言——resolve 成功后 update_status 被以终态记录调用恰一次；store 抛异常时 resolve 回执仍 200 且 warning 留痕；未带幂等键的 run（store 无此行）调用为无害 no-op 或按 store 既有语义跳过。应用后活验：§7 复现实验结算后回读 runs_idempotency.db，该 run 快照为终态、updated_at 为结算时刻。

---

## 施工序（批准后执行，本草案不执行）

1. **入包**：改 `patches/api_server_runs.py`（A／B-409／E）、`patches/overview_gateway.py`（C）、`services/hermes-compose.template.yml` 与 `install.sh`（D）；B 的投影半边先定位构建点再定落点（见 B-2）。新增包内自测 `stop_fix_selftest.py`（覆盖 A 分流四形态、B 响应形状、C 聚合三形态、E 刷新与容错、D 静态标记），全绿才继续。
2. **登记**：manifest.yaml 版本 2.6.0 → **2.7.0**、两补丁 sha256／diff_lines 重算、CAPABILITIES.md 新增 #45。
3. **应用前基线**：在服务器建 `/root/deploypkg-2.7.0-<日期>/baseline/`（见回滚基线节），内存检查过线后才许跑 install.sh。
4. **应用**：`install.sh <部署目录>`（含 compose 的 stop_grace_period 变更与重启；重启步执行 D 的检查项清单）。
5. **验证**：`verify.sh` 全量＋新增第 30 节（见 §7），结果留档 `verify-output-2.7.0-applied-<日期>.txt`；行为复现实验（§7）做完才算关账。
6. **记录**：应用记录 `stop-fix-rollout-<日期>.md`（照既有 rollout 体例：动了什么、哈希、基线路径、D 检查项打勾、复现实验结果）。

## 回滚基线

**改前备份（应用前在服务器落 `/root/deploypkg-2.7.0-<日期>/baseline/`，照历版惯例）**：

- 现行 `patches/api_server_runs.py`（含 sha256，与 manifest 2.6.0 登记值 bc5a5b36… 对账一致才许动手）；
- 现行 `patches/overview_gateway.py`（同上对账）；
- 现行部署目录 `docker-compose.yml`（stop_grace_period 变更前件）；
- 现行 `install.sh`（部署目录件，若与包内件有别以部署目录件为准）；
- 参考快照（只读留证、不作恢复源）：state.db 中 unknown admission 计数、runs_idempotency 中涉事形态计数——本包**无数据迁移、无 schema 变更**，数据面不需要恢复件。

**回滚步骤**：

1. 停手并记录触发原因；先查内存（见红线节），过线才动手。
2. 用 baseline 件覆回部署目录对应文件（原地改写保 inode，`cat baseline > 目标`，照 RULES §5 与 install.sh rollback() 同式）；compose 同法覆回（stop_grace_period 随之消失——注意此时重启又回到 10 秒默认窗，回滚重启前更要先确认无在飞 run，查法照 D-2）。
3. `docker restart hermes`，等 health ok。
4. 若应用中途失败，install.sh 自带 rollback() 已 armed（恢复已改文件＋删新建文件＋重启），优先让它自滚，再人工复核。

**回滚验证（回读实证，缺一不算回滚完成）**：

- 容器内回读两补丁文件 sha256 与 baseline／manifest 2.6.0 登记值逐字一致；
- `verify.sh` 按 2.6.0 口径复跑全绿（第 30 节探针随回滚失效属预期，在记录中注明）；
- 行为抽验：正常 run 的 stop（started）行为与现行一致；resolve-unknown 独立端点仍可用（回滚不伤既有正规路径）；/overview 四源（pending／cron_failed／kanban_failed 等现行源）形状与未读计数无回归；
- 已由 A 路径 settle 的 run 不受回滚影响（结算是 state.db 终态登记，回滚代码不回滚数据，既 settled 者保持终态——这正是要的语义）。

## 内存红线检查点（118.24.41.52，RULES §5，全程适用）

- **三个必查点**：①应用开始前（跑 install.sh 之前）；②重启步之前（install 内 D 检查项一并执行）；③应用后验证开始前。任一检查点内存 used **≥80% 立即停一切操作**，不应用、不重启、不回滚（回滚本身也要重启，同样受此限），先报主线。
- 查法：服务器 `free -m`（或既有巡检同口径），数值写进应用记录。参考：RCA 取证时约 51%、2.6.0 应用时约 51%，正常水位远低于红线；异常高位本身即是先行排查信号。
- 本包改动均为网关进程内代码与 compose 一行，不新增容器、不新增常驻进程，内存面无新增占用预期。

## §7 验证总表（施工后关账门）

**包内自测** `stop_fix_selftest.py`（新文件，照既有 *_selftest.py 体例，本地＋合并树各跑一轮）：

| 件 | 用例要点 |
|---|---|
| A | unknown＋三证据齐 → settle 调用、回执 terminal/interrupted＋settled_via=stop；证据缺任一 → 不 settle；queued／started 路径回归同现行；settle 异常 → 回退 409＋next_action |
| B | 409 体含 next_action／admission_id／execution_generation／resolve_endpoint／reason 五字段且旧错误字段不丢；投影 unknown 带 status_reason／available_actions、他状态不带 |
| C | fixture state.db：unknown 20 分钟产 1 条 born unread、2 分钟不产、已 settle 不产；基线前存量不回灌；二轮不增殖；settle 后消音 |
| D | 静态：模板与 install.sh 含 stop_grace_period／在飞检查／重启后对账三标记 |
| E | resolve 成功 → update_status 以终态记录被调恰一次；store 异常 → 回执仍成功＋warning；无幂等行 → no-op |

**verify.sh 新增第 30 节探针**（照历版体例）：两补丁容器内哈希对 manifest 2.7.0 登记值；compose 含 stop_grace_period: 45s；overview 源表含 run_unknown；重启后 unknown 对账查询可跑通（计数输出，不作红绿门、作留痕）。

**应用后行为复现实验（RCA 验收口径，本包关账门）**：

1. 起一条真 run，执行中走完整部署重启（带新 grace period）→ drain 日志跑满、旧进程正常退出（无 UNCLEANLY）；
2. 该 run 进 unknown 后，客户端发 stop → 得到「已处置为 interrupted」回执（A 路径），不再无限 409；
3. 构造证据不足形态（如同 epoch 内刚失联、executions 未清）发 stop → 409 带 next_action 全字段，按指引调 resolve-unknown 成功结算；
4. 结算后回读 runs_idempotency.db：快照为终态、updated_at＝结算时刻（E）；
5. unknown 存续过阈值期间 /overview 出现 run_unknown 条目，结算后消失（C）；
6. 正常路径回归：queued／started 的 stop、resolve-unknown 防重放语义（settle 后该 admission 不被任何路径重新执行）与现行一致。

## 待主线裁决点（起草者留给报批环节）

1. A 的落点：首选 handler 层分流（不动上游 authority）；备选新增上游全文件补丁的触发条件已写明，是否接受备选存在本身，请报批时一并确认。
2. B-2 投影落点须施工首步定位后才能定，可能与 A 备选合并为同一份上游补丁——若定位结果是上游落点，是否仍在本包范围内一次做完，或拆下一包。
3. C 的阈值 10 分钟与「只露头不自动 settle 真人 run」的边界（自动 settle 真人 run 涉及防重放设计意图，本包刻意不碰；若用户想更进一步，需另行裁决）。
4. D-2 的强行继续开关 `DEPLOY_ALLOW_ACTIVE_RUNS=1`：默认「等 60 秒后中止应用」是否符合部署习惯，或改为默认强行＋留痕。
