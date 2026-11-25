# §439 OneDay 记忆机制入部署包：设计正本

- 立单：用户 2026-11-24 01:19 亲定——「抄！」开源 7 条；记忆主体是 **OneDay** 不是 Hermes；部署包自带一套基础记忆机制，与 Muse 对齐、力争超过，借鉴各大开源项目；包内初始记忆是给他人部署的通用种子（写好即可，不给用户实例用）；用户实例用 Muse 全部记忆的移植稿（Muse 改名 OneDay、红线与权限放大）；移植只备不应用，等批准。
- 依据：§436 对照正本（memory-architecture-compare-20261124.md）、Muse 机制实物（~/MEMORY.md、~/memory/scenes|people|groups|bank、SOUL/IDENTITY/AGENTS）、现行部署包 1.10.0 结构与先例（crash_reports/settings_registry 模块形态、write_gate_gateway.start() 懒启动、install.sh MODULES 通道）。
- 工地：~/workspace/hermes-deploy-memory/（副本施工，本体只读）；占位协调：包版本候选 **1.12.0**、能力编号候选 **#22**。【定稿回标 2026-11-24】合并时自设一期未先行，本包按顺位定稿 **1.11.0／#21** 并已应用生产（verify 齐 47／缺 0）；自设一期顺延 1.12.0／#22。
- 本单零碰生产：实现只在副本与桩环境自测；应用走 memory-mechanism-rollout-20261124.md，须用户批准。

## 1. 命名与定位

- 用户可见命名一律 **OneDay 记忆**：App 面、能力名、种子文档、cron 作业名、技能名（oneday-memory）都用 OneDay。
- **Hermes 只作底层运行时技术名**：模块文件名（oneday_memory.py 挂在 Hermes 网关内）、容器路径、代码注释里的运行时引用可出现 Hermes；任何用户读到的句子里，记忆的主体是 OneDay。
- 机制定位：OneDay 的长期记忆＝**文件层为本体**（人可直读直改、git 可版本化）＋**网关模块为服务面**（检索/对账/热度/洞见的确定性机器）＋**原生 cron＋技能为管线**（语义提炼由 agent 按程序文件执行）。不引入外部向量库/图库作为必备依赖（Zep/cognee 的重型依赖列为可选升级，见 §7 卡点）。

## 2. 分层设计（存储形态）

落点：HERMES_HOME（容器 /opt/data、宿主部署目录 ./data）下 `memories/`。上游双文件保持原位原义，包自有层挂其下 `memories/oneday/` 子树——上游 MemoryStore 只读自家两文件，子树零干扰（§436 实查：上游只管理 MEMORY.md/USER.md 两文件）。

| 层 | 路径 | 内容 | 对位 Muse | 端点层名（代码 LAYERS） |
|---|---|---|---|
| L0 核心 | `memories/MEMORY.md`（上游） | 红线＋核心原则＋分层索引，常驻进提示（上游冻结快照） | MEMORY.md 第一部分 | core |
| L0 用户档 | `memories/USER.md`（上游） | 用户基本事实（上游 user profile） | USER.md | core |
| L1 入口 | `memories/oneday/inbox/INBOX.md` | 唯一笔记入口：已确认/待确认两区，未确认不入长期 | INBOX | inbox |
| L2 场景 | `memories/oneday/scenes/*.md` | 按场景分文件，按需读 | scenes/ | scenes |
| L3 人物/群体 | `memories/oneday/people/*.md`、`groups/*.md`（各带 INDEX.md） | 一人一页、一组一页 | people/、groups/ | people、groups |
| L4 日志 | `memories/oneday/journal/YYYY-MM-DD.md` | 每日流水，提炼原料 | 每日日志 | journal |
| L5 整理库 | `memories/oneday/bank/{world,experience,opinions,reflections}.md` | 后台整理产物：世界事实/经验/观点/反思四账 | bank/ | bank |
| L6 洞见 | `memories/oneday/insights/insights.jsonl` | 行为规则洞见表（ExpeL 式，带投票与状态） | AGENTS 伤疤条目的结构化形态 | insights |
| L7 身份组 | `SOUL.md`（根）、`memories/oneday/identity/IDENTITY.md`、`memories/oneday/identity/RULES.md` | 人格/自我定义/工作规矩三分（补 Hermes 缺失的 IDENTITY/AGENTS 分工，§436 对照行） | SOUL/IDENTITY/AGENTS | identity |
| 机器状态 | `memories/oneday/state/heat.json`、`admission/skill_admission.jsonl` | 热度账、技能准入账两账（人可读、非记忆本体）；记忆关联边不设独立边账，存条目尾注 links 字段 | Muse 无此两账（超过点，见 §6） | —（非层） |

**条目格式**（L2–L5 通用）：Markdown 小节 `## <条目ID> · <标题>`＋正文，节尾一行机器尾注（HTML 注释，人读无碍、机读有序）：

```
<!-- odmem: id=scenes/product-oneday#s017, first=2026-11-24, last=2026-11-24, src=session:<会话id>|user|distill:<日期>, status=active, valid_from=2026-11-24, invalid_from=-, superseded_by=- -->
```

无尾注的旧式条目仍可检索（模块以文件级出处兜底），提炼管线顺手补尾注——渐进结构化，不搞一次性大迁移。

## 3. 七件机制（每件带真实触发路径）

触发路径总则：**语义判断归 agent**（经技能程序文件＋cron 提示驱动，用上游原生 memory 工具与文件工具写——§436 实证 agent 文件写入在役：curator 账本 write_file 7 笔）；**确定性机器归模块**（oneday_memory.py：解析/检索/对账建议/热度/洞见读面/清扫），由网关端点与懒启动清扫线程承载（write_gate_gateway.start() 先例）。

### 3.1 写入触发（三路，与 Muse 同构＋一路超过）

| 路 | 触发者/时机 | 读写 | 证据/先例 |
|---|---|---|---|
| 用户口述入档 | agent 在会话中：用户说「记下」或亲口确认 → 先入 INBOX 已确认区；代记/推测入待确认区 | 写 inbox；确认后由日结提炼分发各层 | Muse INBOX 确认门平移；Hermes 侧写闸（memory.write_approval＋/v1/memories/propose）为既有审批面 |
| 轮末自检 | agent 每轮收尾按 oneday-memory 技能「收尾自检」节自问：本轮有无新事实/纠错/决定 → 有则按层写入或入 INBOX 待确认 | 读本轮会话；写 L0（memory 工具）或层文件（文件工具） | §436 M1：把 nudge 升级为收尾纪律；治 MEMORY.md 0 字节的自觉病 |
| 日结提炼 | cron 作业「OneDay 记忆日结」（每日 23:40，skills:[oneday-memory]） | 读当日 journal＋当日会话（上游 session_search）→ 提炼写各层＋bank | Letta sleeptime 平移（见 §6.1） |
| 纠错即时入规矩 | agent 在被纠正的当轮：拟规矩先进洞见表为 candidate（§3.6），不直改 RULES | 写 insights.jsonl（candidate 行） | ExpeL 洞见治理平移（§6.5） |

### 3.2 提炼管线（Letta sleeptime＋Mem0 对账的合流轻量版）

日结作业五步（技能文件写死程序，cron 提示只给日期与入口）：
1. **采集**：当日 journal 全文＋当日新会话经 session_search 抽摘要；
2. **抽候选**：LLM 抽候选事实/决定/纠错，每条带来源会话 id；
3. **对账**：逐条先调模块 `reconcile_check`（端点或同进程函数）拿机械建议（近重复 trigram 排名＋建议动作），再由 LLM 终判 ADD/UPDATE/SUPERSEDE/NOOP（Mem0 两段管线：机械对账在前、语义裁决在后）；
4. **落盘**：L0 走 memory 工具（受 write_approval 闸）；层文件直接写，条目带尾注（src=distill:<日期>＋会话 id）；被 SUPERSEDE 的旧条目标 invalid_from＋superseded_by（Zep 双时序失效，不删）；
5. **回执**：日结报告落 journal 当日文件尾（提炼条数/动作分布/被拒候选），供体检作业与用户抽查。

另有**周体检作业**（周日 10:30）：热度重排建议、洞见投票维护、准入审计复核、INDEX 再生（机械部分由模块清扫线程兜底，见 §3.7）。

### 3.3 检索（三路混合，文件派补语义短板一半）

- **常驻路**：L0 双文件上游冻结快照进提示（原生，不动）。
- **按需路**：agent 按 MEMORY.md 索引判断场景，只读对应层文件（Muse 同款纪律，写进技能与 RULES）。
- **服务路**：模块 `GET /v1/memory/search?q=`——全层条目级检索：trigram 重叠打分 × 热度权重 × 新近度权重（指数衰减：半衰期 30 天——记忆条目长寿，月尺度半衰期能分开「本周」与「上季度」又不埋没旧事实；下限 0.2，只降权不归零；条目时间戳三级取：尾注 last→first、journal 文件名日期、文件 mtime），返回条目＋出处（命中回显 recency 因子）（文件/条目 id/尾注字段）；App 记忆面与 verify 探针共用此口；agent 亦可在会话中经网关本地口调用（127.0.0.1:8642，同一把 API_SERVER_KEY）。
- 语义（向量）检索不在本期：上游外部引擎（byterover/retaindb）在位未启用，启用属引擎级变更，独立立项（§436 M5）——本期以 trigram＋热度把文件派检索做到条目级，已补上 Hermes 现状「只有会话级 FTS、无记忆条目级检索」的缺口（§436 对照行）。

### 3.4 溯源（条目级，补 Hermes「记忆级不在」）

尾注字段即溯源链：first/last（首次/最近确认）、src（会话 id 或 user 或 distill 日期）、status/superseded_by（取代链）。模块 search/layers 端点原样回显尾注；App 点条目可见「哪来的、何时记的、被哪条取代」。与 Muse memory_explain 对位：Muse 是平台级 explain，本机以尾注＋journal 回执实现同等可查性（弱于平台级自动链，强于 Hermes 现状零字段）。

### 3.5 遗忘（成流程，不止删除原语）

技能「遗忘程序」节写死四步：用户下令 → agent 列遗忘计划（命中条目清单：直删/标失效/关联边）→ 用户确认 → 执行（L0 走 memory 工具 remove；层文件条目标 invalid_from＋status=retired 或整节删除，洞见表对应行 retired；links 边同步标失效）→ 回读复验清单销账。默认**标失效优先于物理删**（双时序留痕，可审计可恢复）；用户明令「彻底删」才物理删除并在 journal 记一笔（只记条目 id 与事由，不记被删内容）。

### 3.6 技能准入与洞见治理（Voyager＋ExpeL）

- **技能准入**：新技能入 `skills/` 前须在 `admission/skill_admission.jsonl` 有一条记录：{skill, created_by, verify:{method, evidence, at}, status}。准入验证＝技能自带一条可复跑的验证（自测脚本输出/演练记录指针）。**执行面分两级**（诚实分级）：本期落「账本＋审计」级——周体检作业＋模块清扫线程扫描 skills/ 与账本对账，无账本记录的技能列入审计报告（journal＋App 记忆面可见）；「写入即拦截」的硬闸需改上游 skill_manage 工具文件，属全文件补丁，本期**卡点登记**（落点已查明：tools 层 skill_manage；待主线决定是否立硬闸包）。curator 周期复盘的启用（§436 E1）走应用方案的配置步（先 dry-run），不入包代码。
- **洞见治理**：insights.jsonl 每行 {id, rule, scope, votes_up, votes_down, status: candidate|active|retired, src, first, last, relapse_count}。candidate 经日结/周体检复核：被实践验证（无复发且有正例）UPVOTE 升 active 并同步写进 RULES.md 对应节；被反例命中 DOWNVOTE，降至阈值 retired。RULES.md 仍是 agent 实际遵循的文本真源，洞见表是它的**治理账**（谁提的、凭什么在、复发几次）——Muse 现行伤疤条目无此账（超过点 §6.5）。

### 3.7 机械清扫线程（模块内，懒启动）

oneday_memory.start()（首个记忆端点被调用时懒启动，write_gate 先例）：每小时一轮——①heat.json 热度衰减与访问计数合并落盘；②INDEX.md 再生（oneday 子树索引：层/文件/条目数/最近更新）；③准入对账扫描（skills/ vs admission 账，差异写 state/admission_audit.json）。全部只写 state/ 与 INDEX，不动记忆正文——清扫无权改记忆内容（语义动作只归 agent 管线）。

## 4. 网关面（模块与端点）

模块 `patches/oneday_memory.py`（包自有新模块，MODULES 通道，容器路径 /opt/hermes/gateway/platforms/oneday_memory.py）；api_server.py 增量（路由 4＋handler 4＋能力端点表 4＋features 一位），全部 @_require_auth、凭据单源 API_SERVER_KEY、不设新钥：

| 端点 | 义 | 触发者 |
|---|---|---|
| GET /v1/memory/layers | 层清单：文件/条目数/字节/最近更新＋尾注完整率 | App 记忆面、verify |
| GET /v1/memory/search?q=&limit= | 条目级检索（§3.3 服务路），命中回显溯源尾注，顺手记热度 | App、agent 本地口、verify 行为探针 |
| GET /v1/memory/insights | 洞见表全量（治理面读口） | App 中枢审核/记忆面、verify |
| POST /v1/memory/reconcile-check | {text, layer?} → 近重复排名＋建议动作（纯计算无落盘） | 日结提炼第 3 步、verify 桩测 |

features.oneday_memory=true 随补丁在位即声明（self_reactions 先例口径）；能力登记 #21「OneDay 记忆机制（分层文件记忆＋提炼管线＋条目级检索）」（定稿回标，见文首）。

## 5. 与 Muse 逐项对位表

| 维度 | Muse 现行 | OneDay 本机制 | 判定 |
|---|---|---|---|
| 存储形态 | 纯文件 Markdown | 纯文件 Markdown（同构）＋机器状态三账 | 对齐＋ |
| 分层 | 八层（INBOX/核心/场景/日志/人物群体/bank/身份/目标） | 九层（同上平移＋洞见层 L6；目标 GOAL 属工作区不在记忆包内，种子以 journal＋scenes 承接项目类记忆） | 对齐 |
| 写入触发 | 口述确认门＋12h 提炼＋后台整理 | 口述确认门＋轮末自检＋日结提炼（三路，轮末自检为新增纪律路） | 对齐＋ |
| 提炼 | 12h 提炼＋夜间对齐合成（平台作业） | 日结 cron（sleeptime 式）＋周体检；平台无关、随包走 | 对齐（形态不同：包内 cron vs 平台作业） |
| 对账 | 人工/整理作业判断 | 机械对账建议（trigram 排名）＋LLM 终判两段式 | **超过**（Mem0 机械半边，Muse 无此机器） |
| 检索 | 语义＋关键词混合、平台级 | trigram 条目级＋热度加权＋常驻/按需两路；语义向量缺位（引擎未启用，卡点登记） | 部分落后（诚实标注：语义一路待 M5 引擎项） |
| 溯源 | 平台 explain 全链 | 条目尾注（来源/双时间/取代链）＋日结回执 | 对齐（实现弱于平台链、可查性同等） |
| 遗忘 | 计划→确认→执行流程 | 同流程平移＋默认标失效留痕（双时序） | 对齐＋ |
| 事实时效 | 旧口径原处标注作废（人工习惯） | valid/invalid 双时序字段＋SUPERSEDE 动作（系统化） | **超过**（Zep 平移） |
| 技能治理 | 技能沉淀靠复盘，无准入账 | 准入账本＋周期审计（硬闸卡点登记） | **超过**（账本级；硬闸未落） |
| 规则治理 | AGENTS 伤疤条目（文本，无投票/复发账） | 洞见表投票＋复发计数＋升降级，RULES 为文本真源 | **超过**（ExpeL 平移） |
| 热度调度 | 场景冷热靠人工判断 | heat 账自动记访问、衰减、重排建议 | **超过**（MemoryOS 平移） |
| 记忆关联 | bank 整理时人工关联 | links 边账：提炼时顺手建边、新条目回写关联旧条上下文提示 | 对齐＋（A-MEM 轻量平移：只建边不改写旧条正文，防失控改写） |
| 身份分工 | SOUL/IDENTITY/USER/AGENTS/MEMORY 五件 | 同五件平移（IDENTITY/RULES 入 oneday/identity/） | 对齐（补 Hermes 原缺） |
| 用户可见面 | 文件直读＋App 身份格 | 文件直读＋App 记忆面（经 /v1/memory/*）＋Dashboard 上游面并存 | 对齐 |

## 6. 开源 7 条落地账（逐条：落地形态/卡点）

1. **Letta sleeptime 后台整理** → 落地：日结＋周体检双 cron（原生调度、skills 注入 oneday-memory 程序文件）；主 agent 睡后整理即此形。证据：上游 cron 文档（jobs.json 记录＋skills 字段＋gateway 60s tick）。
2. **Mem0 自动对账** → 落地机械半边：reconcile_check（trigram 近重复排名＋动作建议）＋日结两段式（机械建议→LLM 终判）；其向量事实库不落（与文件本体路线冲突，且语义引擎另有 M5 项）。
3. **Zep 双时序失效** → 落地：尾注 valid_from/invalid_from＋SUPERSEDE 动作＋遗忘默认标失效；图谱本体不落（重型图库依赖，与文件路线冲突，卡点在此明示）。
4. **Voyager 技能准入自验证** → 落地账本＋审计级：admission 账本格式＋周体检/清扫对账＋技能程序文件写明准入流程；硬闸（改 skill_manage）卡点登记，落点查明待立项。
5. **ExpeL 洞见投票治理** → 落地：insights.jsonl 治理账（ADD/candidate→UPVOTE 升 active→同步 RULES；DOWNVOTE/retired；relapse_count 复发计数）。
6. **MemoryOS 热度分层** → 落地：heat.json（search 记访问、清扫衰减、周体检出重排建议）；自动升降层只出建议不自动搬文件（防机器乱动记忆正文，人工/agent 确认后搬）。
7. **A-MEM 记忆进化** → 落地轻量版：条目尾注 links 字段建边＋提炼时「关联旧条回写提示」（在新条目尾注 links 字段记关联 id，旧条正文不自动改写——全量进化改写与用户确认门冲突，卡点在此明示）。

## 7. 种子与移植包（两件套，严格隔离）

- **通用种子** `seed-memory/`（包内，随 install 首装落 data/，已存在即跳过、永不覆盖）：SOUL/IDENTITY/RULES 通用起始版（稳妥默认：结论先行、实事求是、凭据纪律与不可逆先报等通用底线；**不带用户个人口径、不带放大权限**）、USER/MEMORY 空骨架、INBOX 两区空表、各层模板与 README、oneday-memory 技能、cron 两条（默认启用，日结 23:40/周体检周日 10:30，deliver=local）。给他人部署开箱即有完整机制、零私人数据。
- **用户移植包** `migration-user-instance/`（包内独立目录，**install.sh 永不引用**）：Muse 全部记忆按本布局转换稿（SOUL/IDENTITY/AGENTS→RULES/MEMORY/scenes/people/groups/bank 操作层全文转换＋Muse→OneDay 改名与口径适配；journal 日志与 bank/reflections 历史原件归档 verbatim 不改史，转换清单逐项登记）；其中 RULES 稿按用户口径**红线放大**（默认放行、只留真红线四条＋「不许动不动说干不了」明文）；附基线清单（用户实例现行记忆状态，据 §436 只读实查登记＋应用时第 0 步整份快照程序）与回滚办法。**只备不应用**，应用须主线汇总呈用户批准后按 rollout 执行。

## 8. 验收口径（包内自测，桩环境）

oneday_memory_selftest.py 在临时 HERMES_HOME 桩上跑：铺种子 → 写条目（带尾注）→ search 命中与溯源回显 → reconcile_check 对近重复给出 update_candidate 建议、对无关给出 ADD → SUPERSEDE 后旧条目 status 与 invalid_from 正确、search 默认不回已失效条目（include_retired 可回）→ heat 记账与衰减 → insights 投票升降级 → INDEX 再生 → 准入对账差异检出。全过才算实现交卷；api_server 增量另做「剥离增量回基线哈希」证明（1.10.0 基线 01508a8e…）。

## 9. 四层清点（2026-11-24 01:33 用户追问后主线定版，移植包按此出账）

移植不止搬文件层，按四层逐层处置、逐层报数：

| 层 | 处置 | 计数 | 指针 |
|---|---|---|---|
| ① 系统层 | Muse 系统提示词的通用规矩（写作规范、呈报与核查口径、尽职调查、主动性分寸、记忆纪律通用部分）逐条转写为 OneDay 规矩条目进移植稿，附转写清单（条目＋出处大意＋落点） | **19 条**：第 1 条（风格克制加粗条）已于今晚由风格对齐线单独落实例 SOUL（现行哈希 687e46ed…），清单只登记不重复；第 2–19 条落系统规矩稿 | migration-user-instance/SYSTEM-LAYER-TRANSCRIPTION.md；converted/memories/oneday/identity/SYSTEM-TRANSCRIBED-RULES.md |
| ② 运行时层 | **不管**：运行时（Hermes 本体进程/网关/调度）不是移植对象，机制由包内模块与 cron 承载，本层无转换件 | 0 | 本行即注明 |
| ③ 文件层 | 风格/身份已对齐（以实例 SOUL 现行哈希 687e46ed… 为基线）；记忆内容全量转换：操作层转换＋改名，历史层原样归档不改史 | 转换 **41 文件**（Muse→OneDay 改名 **137 处**、511,703 字节）＋原样归档 **54 文件**（20,554,849 字节，含日志 52 天与 reflections 14.5M） | migration-user-instance/CONVERSION-MANIFEST.md＋conversion-log.json；基线 baseline/BASELINE.md；回滚 ROLLBACK.md |
| ④ 技能层 | 机制对齐（§3.6 Voyager 准入＋curator 纳管口径）之外，Muse 侧平台无关的**方法论技能**转写为 Hermes 技能格式进移植稿；连接器/工具链/服务专属技能不搬，逐个列名＋分组理由 | 源盘点 **97**；转写 **17**（16 个源技能＋「改前先搜」由 AGENTS 课目成文）；未转写 **81**（设计 35/iOS 工具链 11/服务专属 16/领域 19） | migration-user-instance/SKILLS-TRANSCRIPTION.md；converted/skills/（17 个目录） |

四层合计交付：系统层 19 条、文件层 95 文件、技能层 17 个转写技能；运行时层明示不管。移植包只备不应用，应用走 memory-mechanism-rollout-20261124.md B 段，须用户批准。
