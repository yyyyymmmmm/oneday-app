# 工作台账 · 伴生半施工报告（本地构建，未部署）

- 日期：2026-11-10
- 规格：`~/workspace/oneday-design-review/work-ledger-design-20261110.md`
- 工程：`~/workspace/hermes-deploy/companion`，本地版本 **1.0.3**（生产现行 1.0.2 未动；本报告只交构建与自测，部署另行报批）

## 1. 交付物清单

| 件 | 位置 | 说明 |
|---|---|---|
| 台账核心模块 | `modules/ledger.py`（1,468 行） | 纯逻辑：事件账存储、七态状态机、标题链、失败分类、双通道对账采集器；时钟与数据源全部可注入 |
| 桥接线 | `modules/oneday_bridge.py` | 路由、Hermes 数据源 providers、桥内作业自记钩子、采集线程、/health 扩展 |
| 面板只读位 | `front/front.py` + `front/static/index.html` + `front/static/app.js` | 总览页「工作台账」卡，只代理计数，不渲染任务明细 |
| 自测 | `tests/ledger_selftest.py`（60 项） | 已挂入 `tests/run_bridge_selftests.sh` |
| 版本 | Dockerfile ARG / docker-compose 镜像 tag 与 COMPANION_VERSION | 1.0.2 → 1.0.3（本地） |
| 配置说明 | `companion.env.example` [oneday] 段 | 注释版 LEDGER_* 与 WRITE_GATE_* 说明 |

## 2. 模块与接口

### 2.1 事件账（append-only JSONL）
- 文件：`ledger-events.jsonl`（默认与 DATA_PATH 同目录，env `LEDGER_PATH` 可改）。
- 坏行处理：整文件隔离为 `.corrupt-<时间戳>` 留底（不删），以可回放前缀建快照并置降级位；降级时拒写，绝不拿空账覆盖。
- 压实：终态条目保留 30 天，每日一次；非终态永不清理。
- 出生门（born_at）：台账上线前已落定的轮次不回溯补记；跨越出生时刻的轮次照常记。

### 2.2 七态状态机与证据规则
- 状态：queued / running / blocked_approval / completed / failed / cancelled / stale。
- 证据强度：inferred 1 ＜ board / run_status / app 2 ＜ decision / bridge_self / transcript 3。终态冲突时强者纠正弱者；弱者尝试纠正强者只留 conflict 痕，不改判。
- 僵尸阶梯：45 秒无新证据 → 标 evidenceLagging（状态不变、只标「最后确认时刻」龄）；10 分钟 → 定向核查（查 transcript 落定＋run 端点）；30 分钟且「无落定＋状态端点无此 run」→ 判 stale 停转。**无证据永不标完成**；run 状态端点只刷新证据、永不落定（它记的是流的命运，不是轮次的命运）。
- 迟到落定可把 stale 复活纠正为真终态，全程留痕。

### 2.3 双通道对账（采集器 15 秒一轮，env `LEDGER_COLLECTOR_SECONDS`）
五步：①会话列表 diff＋transcript 分段对账（endedAt 取落定消息时刻、不取发现时刻）；②run 状态对齐；③kanban 板 diff（流转留痕含同态流转；任务消失→failed/原因未明）；④审批：write-gate /pending 产生 blocked_approval 条目＋decisions.jsonl 游标增量读落裁决；⑤device audit.jsonl 游标增量读（时间窗内恰一条运行→并入其 toolCalls 计数；零条→独立 device 条目；多条→只计 ambiguousDeviceCalls，不猜）。
- 合并键：App 上报以 runId 为幂等键（条目 `run:<runId>`）；对账以会话＋轮次窗口（±90 秒）匹配同一自然键。
- **并入（adoption）**：采集器抢先建账时，App 上报并入既有对账条目并对齐 runId——一件工作永远一行账（自测 Part B 实证）。
- 桥内自记：点子生成／目标简报／动态晨报三作业与监控变更经钩子自记；全部钩子吞异常，台账是旁路、不许拖垮作业本体。

### 2.4 标题规则链（防编造）
服务端 llm/user 级标题 ＞ 用户原话首行摘录（≤30 字逐字截断加省略号）＞ 注册名（job_name/task_title）＞ 兜底「未命名任务 · HH:mm」。titleSource 另扩展 `fallback` 与审批摘要用的 `record_excerpt`。失败分类：被审批中止／用户停止（→cancelled）、执行被打断、超时、上游出错、原因未明，摘录 ≤160 字；中断以 transcript 的 interrupted 标记为证据（不靠文本关键词猜）。

### 2.5 给 App 的读面（oneday 模块，单钥鉴权后）
| 路由 | 用途 |
|---|---|
| `POST /ledger/report` | App 上报：开始／心跳（stillRunning）／终态；缺 runId 回 400 |
| `GET /ledger` | 列表；`?since=<seq>` 增量 |
| `GET /ledger/summary` | 计数（正在进行／待审批／失联待核／今日完成／今日失败＋采集器心跳） |
| `GET /ledger/{id}` | 下钻详情（含 history 流转痕） |

/health 扩展：`ledger{degraded, items}`＋`collector{lastRunAt, lagSeconds}`。

### 2.6 面板呈现位
`GET /api/companion/ledger`（front 代理 oneday 的 /ledger/summary）：总览页只显计数与采集器心跳；自测 Part C 断言载荷内无 `title` 键、无任何任务标题文本泄漏。

### 2.7 新增 env（均有默认值，可不配）
`LEDGER_PATH`、`LEDGER_COLLECTOR_SECONDS=15`、`LEDGER_DECISIONS_PATH=/opt/data/write-gate/decisions.jsonl`、`LEDGER_DEVICE_AUDIT_PATH=/opt/device-data/audit.jsonl`、`LEDGER_SKIP_SESSIONS`（默认生成会话，防桥作业与其生成会话双记）、`WRITE_GATE_BASE=http://127.0.0.1:8643`、`WRITE_GATE_BRIDGE_KEY`（不填则审批「产生」面降级为裁决时补记）。

## 3. 自测数字（2026-11-10 本地实跑）

| 套件 | 结果 |
|---|---|
| `tests/ledger_selftest.py` | **60 过 / 0 挂** |
| `tests/run_bridge_selftests.sh`（overview＋oneday p2/p3＋device＋device_sync＋ledger） | **6/6 OK** |
| `tests/front_selftest.py` | 29 过 / 0 挂 |
| `tests/run_local_stack.py` | 18 过 / 0 挂 |

ledger_selftest 覆盖：A1 双写一致；A2 终态上报丢失由对账落定（endedAt 为消息时刻）；A3 采集器独有发现＋出生门不回溯；A4 冲突三向（App 失败被 transcript 纠正为完成／App 完成被 interrupted 纠正为失败／弱证据动不了强终态只留痕）；A5 僵尸阶梯逐级（+46s 标龄→+601s 核查不判失联→+1801s stale→迟到落定复活）＋A5b 端点报 completed 永不落定；A6 标题链与分类器；A7 kanban 建条/流转/消失；A8 审批双路与游标不重读；A9 设备调用相关性三态；A10 坏行隔离降级；A11 压实；A12 summary/changes_since；A13 上报形态与 400；B 真桥子进程 HTTP 冒烟（401、并入去重、落定、kanban 条目、since 增量静默）；C 面板代理只计数不泄题。

施工中修掉的真缺陷一条：采集器抢先建账与 App 上报的双记竞态（见 2.3 并入）。

## 4. 与规格的偏差（如实列）

1. **兜底标题**：用「未命名任务 · HH:mm」，未用规格 §5.2-4 的「接口调用 · 〈会话短 id〉」——前者对用户更可读，且短 id 属行话（界面禁用词口径）。请主线确认。
2. **titleSource 枚举扩展**：新增 `fallback`（兜底标题）与 `record_excerpt`（审批摘要摘录），规格枚举之外。
3. **未对生产实测的字段口径**（防御性多键归一，上线后需以真数据复核——规格 §6 同列未证项）：
   - Dashboard sessions/messages 的真实字段名（title_source / message_count / created_at 等多键兼容）；
   - kanban 状态字符串映射为防御表，未知值新条目落 queued 并留痕；
   - write-gate /pending 的 records 字段（id / created_at / summary）按 write_gate_bridge 源码 `_norm_record` 口径取用。
4. **decisions.jsonl 与 audit.jsonl 的路径可见性**以伴生单容器内挂载为准（/opt/data、/opt/device-data）；本地自测以临时文件代之。

## 5. 部署变更清单（草案 · 待主线报批，本分身未执行任何生产操作）

1. 构建镜像 `oneday/companion:1.0.3`，替换现行 1.0.2 容器（单容器切换，五模块短暂中断，量级同 1.0.2 上线时的约 10 秒；Hermes 本体不动）。
2. 新增数据文件：oneday 数据目录下 `ledger-events.jsonl`（运行时自动创建，无需预建；建议确认该目录备份口径是否纳入）。
3. env：默认值即可运行；如需审批「产生」面完整工作，确认伴生 env 中 `WRITE_GATE_BRIDGE_KEY` 已配（与 write-gate 模块同钥）。
4. 回滚基线：保留 1.0.2 镜像，异常时切回旧 tag 重启伴生容器即可；ledger-events.jsonl 为新增文件，切回旧版不影响其余模块。
5. 部署后验收建议：/health 看 collector 心跳与 ledger.degraded=false；面板总览看台账卡计数；App 侧待 0.36.15 读面接入后做端到端一问。
6. 红线自查：部署前查 118 内存（超 80% 停手）；不动 Hermes 与其他业务容器。

## 6. 1.0.4 变更与部署记账（2026-11-11）

**版本**：oneday/companion:1.0.4（镜像 694790f25872）。授权口径：用户 2026-11-11 05:17 拍板「伴生自动修复自动部署，不要我批」，本版为首单，施工＋部署一次执行到底。

**变更内容**（定案与方案见 oneday-design-review/ledger-kanban-source-check-20261111.md）：
1. `oneday_bridge.py` `_fetch_kanban_tasks`：`_collect` 新增 `saw_container` 旗（见到 tasks 列表或 columns 容器即置位）；结尾拆分——见到容器但任务为 0 → `({}, "任务板为空")`（成功性质）；连容器都没见到 → `({}, "任务板格式不对")`（失败性质）。
2. `oneday_bridge.py` feed 特判（原 2316）：比对串由 `"任务板为空或格式不对"` 改为 `"任务板为空"`，显示文案不动。
3. `oneday_bridge.py` `_ledger_kanban`：注记为 None 或 `"任务板为空"` 时返回 tasks（空板返回 `{}`），其余返回 None——空板不再被压成「读取失败」，且看板任务删光后消失条目可正常落定。
4. `ledger.py` KANBAN_MAP 补两值：`scheduled → queued`、`blocked → running`（流转 note 保留原始状态串，账面不失真）。
5. 版本位三处同步：Dockerfile ARG、docker-compose.yml image 与 COMPANION_VERSION 均 1.0.4。

**本地自测（部署前实跑）**：run_bridge_selftests.sh 6/6 OK（内含 ledger_selftest 60 过 / 0 挂）；front_selftest 29 过 / 0 挂；run_local_stack 18 过 / 0 挂——与 1.0.3 基线持平。另加定向核验三项全过：生产形态空板 → 注记「任务板为空」且 `_ledger_kanban() == {}`；无容器载荷 → 注记「任务板格式不对」且返回 None；带 blocked 任务取数正常且映射两值就位。

**部署**：2026-11-11 05:20–05:27 CST。动手前内存 51%（7725MB 总量，红线内）。回滚基线 `/root/companion-104-deploy-20261111/`（旧 compose＋env 快照、companion/hermes inspect、镜像清单、1.0.4 构建上下文与 build.log、compose-up.log）；1.0.3 镜像（3437bd95e8db）保留在服务器，回滚＝基线内 docker-compose.yml 拷回部署目录后 `docker compose up -d`。部署方式与 1.0.3 同路：本地源码打包上传（改动两文件 md5 与本地逐字一致）、服务器 docker build、compose 只改 image 与 COMPANION_VERSION 两处、只重建 companion 容器。Hermes 本体零触碰：StartedAt 部署前后同为 2026-11-10T14:21:47.024396739Z。

**部署后验收（五步全过）**：
1. kanban 空板红灯消除：`/ledger/summary` 的 collector.sources.kanban = `{ok: true, note: null}`（修复前为 ok:false「读取失败」）；sessions 源同为 ok。
2. `/ledger` 列表 200；`/ledger/summary` 正常：total 25（completed 20 / cancelled 5）、degraded=false、台账条目 25。
3. collector 推进：lastRunAt 三次采样 1794345780.06 → 1794345825.33 → 1794345840.53，按 15 秒节拍推进。
4. device `/health`：`{ok: true, service: device-bridge}`（sessionOnline: false 为手机不在前台的正常态）。
5. front 首页 200。部署后内存 51%。
