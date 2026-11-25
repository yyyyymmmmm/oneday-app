# FEED-SOURCING-REPORT — 动态线检索源去付费依赖核查＋改造

- 日期：2026-11-11 晚
- 触发：用户否决为 Tavily 升额付费（原话「对接的模型呀，需要这个额度吗？开玩笑呢？」），
追加定调（原话「那 muse 怎么搞的？人家没有额度不活了？模型也可以抓呀」）：
主路线改定为「让智能体自己抓」。
- 范围：伴生 oneday 模块的动态生成线（版次线 schedule/schedule-b、小时线 hourly、
活跃触发 visit/adhoc）。Hermes 本体未动。

## 0. 结论先行

**已改造上线：伴生 1.0.28，检索主源改为 Hermes 智能体自抓。**

- 生成线的取材步不再默认调 Tavily：每个方向发 **1 次 Hermes run**，由智能体用自带
联网工具（搜索＋页面深读）完成检索与深读，只回结构化材料（标题/URL/发布日期/
正文摘录/图片）。这条路没有按次计费水表——run 走既有模型网关通道，与
plan/compose/editor 等生成席位同一本账。
- Tavily 降为**兜底**：智能体取材为空时才走搜索兜底、页面正文太薄时才走深读兜底；
Tavily 月预算用尽后兜底自动切换 Firecrawl（免费额内）。`tavilyCalls` 计数口径
已修正为只计真实 Tavily 调用（此前把 Firecrawl 也算进去，数字虚高误导）。
- **小时线与活跃触发不再被档位关门**：旧机制在 1000/月额度下算出「档 2」，直接把
小时线整条关掉、adhoc 在档 ≥1 时关闭——这正是「新动态推不动」的真凶。1.0.28 起
档位只给兜底定投影口径，任何档位都不关线。
- Serper 未实测：其凭据在 Bitwarden，本子任务无浏览器能力取不了钥——缺口如实
记在 §4，不充数。当前组合（智能体主源＋Tavily 兜底＋Firecrawl 二级兜底）已
闭环，不依赖 Serper。

## 1. 现行（改造前）feed 线 Tavily 用量构成

代码：`modules/oneday_bridge.py` 五步链 plan → search → extract → compose → 验真落库
（§1.9 链，FEED-106 落地）。

| 环节 | 调用 | 计数方式 | 单轮量 |
|---|---|---|---|
| 检索 | `_tavily_search` 每方向每 query 1 次（basic 深度、max_results=5） | ＋1/次 | 方向 ≤5 × query ≤2 ＝ ≤10 |
| 深读 | `_tavily_extract` 每方向 1 次批量（≤4 个 URL、带图） | ＋1/次（不按 URL 数） | ≤5 |
| 抽图兜底 | `_firecrawl_scrape`（单页、仅 og:image 与正文兜底） | **也被算进 `tavilyCalls`**（口径错误） | 按缺口页数 |

计数落账：每轮 rec["tavilyCalls"] 累加进 `meta.feedPolicy.monthCalls`；额度门
`FEED_TAVILY_MONTHLY_LIMIT` 默认 1000；档位表 (54, 48, 30)/日投影 → 1000 额度落
**档 2**，其政策理由串（生产实读）：「Tavily 月额度 1000：全量投影 1647/月、
关 adhoc 1464/月、保版次 915/月」。

档位实际效果（改造前生产实况，2026-11-11 22:1x 服务器实查）：

- `feedPolicy` ＝ {tier: 2, limit: 1000, monthKey: "2026-11", monthCalls: 12}。
- 小时线评估 `_hourly_evaluate`：tier ≥ 2 直接 skip 落日志——生产 hourlyLog 尾
5 条全是 `skipped / policy-tier2 / 降级档位：小时线关闭（保版次）`。
**小时线在生产从未真正开过火。**
- adhoc（读面打开触发）：tier ≥ 1 直接 return False，同样从未开火。
- 版次轮与小时轮另有硬门：monthCalls ≥ 1000 时整轮 skipped「Tavily 本月额度已用尽」。

真实消耗（同刻 Tavily 官方 usage 接口实查，GET api.tavily.com/usage）：
账号 Researcher 计划，**plan_usage 49 / 1000**（search 34、extract 15，其余 0）。
桥内 monthCalls 口径（12）与官方口径（49）不一致：桥只数自家五步链的调用，
官方还含其他来源（如既往探针）。两个数都远低于 1000——**额度从未真的紧过，
紧的是档位投影先把线关了**。

台账 6 轮历史（生产）：11-10 17:05 manual 产 1；11-11 06:11 brief 产 2；
06:14 brief skipped（简报为空）；08:30 schedule skipped（简报为空）；
12:36 brief 产 2；19:30 schedule-b **empty**（retr 12 / model 6 / dirs 4）——
即 19:30 版次事故轮：沙盒干跑用同组幂等键提交过副本载荷，真轮四席位同键异
载荷被 Hermes 判 409 全灭（已由 1.0.26 的 key_stamp 唯一化修复，此处只作
用量构成的背景）。

## 2. 历史原因：生成线当年为何绕开智能体工具

查 FEED-106-REPORT.md 与五步链代码注释，结论是**架构取向，不是试过不行**：

- 0.38.0 动态换代时，五步链在桥内 Python 从零写定。检索/深读被写成确定性 API
调用，因为验真门需要一份**可逐字对账的候选集**：候选 URL 集合＋每页
publishedAt＋正文，来源审计器（`_audit_candidate_sources`）逐项核对
「帖中链接 ⊆ 本轮候选集、正文有据、日期不超鲜」，候选集之外的链接整篇退回。
- Hermes run 只承担「席位」：plan（规划）、compose（著帖）、editor（选稿）、
picker、finish、reconcile——全是生成/裁决，没有一个席位被赋予取材职责。
- Hermes 容器环境里从未配置任何搜索服务商钥（实查：无 TAVILY/EXA/BRAVE/
FIRECRAWL/SERPER 变量）；但其 config.yaml 里 `web_extract` 工具与 browser 段
一直都在——**智能体的联网工具不依赖外部计费钥，是自带的**，只是生成线从没
调用过这条路。

## 3. 智能体自抓实证（决定性实验，2026-11-11 22:2x）

经伴生同款契约（POST /v1/runs，model=deepseek-flash，Idempotency-Key 带本轮
唯一段）提交探针 run `run_ffba62eb1ffc4dd0adf0657fdbf1217c`：指令智能体用自己
的联网工具以 2 个查询词检索「DeepSeek 最新模型发布」近 7 天、打开 2 个页面读
正文、只输出 JSON {results:[{title,url,publishedAt,excerpt≥400 字}]}、禁止编造 URL。

结果：**completed，总时长约 1.5–3 分钟**，输出合法 JSON 3388 字，2 条真实已读
页面（evalmap.ai/releases、ainewsandupdates.com/deepseek-news-updates），excerpt
为真实正文（具体日期与事实密度高）。两条 publishedAt 均为 null——页面未以可抓
形式自述日期；审计器对缺失日期的口径是「未知」而非「新鲜」，可接受。

契约/性能卡点逐条：

1. **耗时**：单方向取材 run 约 1.5–3 分钟；方向并行（线程池 5）后整轮取材墙钟
≈ 单方向时长，版次轮可接受；小时线单方向同理。比 API 直调慢，但不在用户
等待路径上（后台生成）。
2. **输出契约**：智能体自报的候选集自洽性弱于 API 实抓——URL 的真实性靠
「指令要求实开过」＋下游既有门补强（来源审计、HEAD 验活、成帖验真）。
这是本次改造如实保留的弱化点，见 §7。
3. **幂等键**：material run 的键为 `feed-material-{stamp}-{idx}`，stamp 已含
轮次唯一段（1.0.26 口径），满足同键同载荷纪律。
4. **计数归属**：material run 不计入 modelCalls（该字段历来只计生成席位，
且既有自测断言依赖此口径），单独记进 rec["retrieval"]["agent"]。

## 4. 免费替代逐个实测

| 候选 | 实测 | 额度口径 | 结论 |
|---|---|---|---|
| Hermes 智能体自带工具 | §3 探针 run 真实完成检索＋深读，JSON 契约成立 | 无按次水表，走既有网关模型通道 | **主源（已落地）** |
| Firecrawl（武装库现有 Free） | 从伴生容器内实测：GET /v1/team/credit-usage → remaining **1023**、plan 1000、计费期 2026-11-08→12-08；POST /v2/search 返回 5 条带摘要结果，**一次 search 扣 2 credits**（1023→1021）；/v1/scrape 此前已在生产作兜底 | 每期 1000 credits，未见绑卡要求（账号为既有武装库资产） | **二级兜底（已落地）**：新增 `_firecrawl_search`，Tavily 预算尽时接搜索；scrape 接深读 |
| Tavily（现行） | 官方 usage 实查 49/1000（§1） | Researcher 计划 1000/月免费 | 降为一级兜底（预算内优先于 Firecrawl，保 publishedAt 质量） |
| Serper | **未实测**：凭据在 Bitwarden，本子任务无浏览器能力，取不了钥 | 未知 | 缺口如实记录；当前组合已闭环，非必需；如需启用须由有浏览器能力的会话取钥后另行实测 |
| Browserbase | 总账记 Search/Fetch 各 1000 次/月免费（2026-12-08 重置） | 未实测 | 未纳入：主源＋双兜底已够，多一个源多一份维护；留作后备记录 |

注：本机 VM 直连 api.firecrawl.dev 超时（出站被透明拦截），Firecrawl 实测与
生产调用都从服务器/容器侧发——生产链路本来就在容器内，不受影响。

## 5. 改造内容（伴生 1.0.28）

`modules/oneday_bridge.py`：

1. **新增 `_agent_material(queries, stamp, idx)`**：每方向 1 次 Hermes run
（提示词版本 `feed_material_v1` 登记进 FEED_PROMPT_VERSIONS），指令智能体用
自有工具检索给定 queries、打开头部页面、只回 JSON
{candidates:[{title,url,publishedAt,content,images}]}（content 摘录优先
≥1500 字、截断约 6000–8000；candidates ≤8；URL 必须实开过）；桥侧用
`_extract_json_object` 解析、`_norm_url` 归一；任何失败/空 → ([], {}) 走
兜底，绝不抛异常。
2. **`_research_direction_work` 改序**：先智能体取材（候选经原 avoid/dedupe
过滤、正文直接播种 extracts）；正文薄/缺的候选才按原链补深读（Tavily
extract 批量 → Firecrawl scrape 逐页）；智能体零候选时才走搜索兜底
（Tavily 预算内优先、预算尽走 Firecrawl search）。返回计数改 dict
{agent, tavilySearch, tavilyExtract, firecrawl}；**rec["tavilyCalls"] 只累加
真实 Tavily 两项**，rec 新增 "retrieval" 明细（两个 rec 模板都加），方向
记录 drec 同带 retrieval。
3. **拆硬门**：版次轮/小时轮的「额度用尽整轮 skipped」两处删除，改为把
`tavily_budget` 标志传进方向工；`_hourly_evaluate` 删除 tier≥2 skip 块；
`_feed_maybe_adhoc` 删除 tier≥1 关门。
4. **档位表改义**：FEED_TIER_DAILY_CALLS ＝ (54, 30, 0)，读法：档 0＝兜底单独
能扛满月；档 1＝预算门控混合（Tavily 用尽后 Firecrawl 接）；档 2＝额度太小
不作规划、智能体＋Firecrawl 扛。1000 额度落档 1。政策理由串改写为
「检索主源＝智能体自抓（无按次额度）；Tavily 仅作兜底…」，pol 新增
"sourcing": "agent-first"。
5. **验真/审计/finish 门全部不动**：候选集改由智能体产出，代码对账逻辑不变。

自测（tests/oneday_bridge_p3_selftest.py）配套改动，逐项说明：

- 三处 fake_poll 各加 `feed-material-` 分支（须在 compose 兜底 pop 之前）：
phase B 回两条带正文＋图的候选（保 B 全部断言，含 modelCalls==3——material
不计 modelCalls 是关键）；phase D 按 batch 回两条候选；_load_e 回空候选，
使 E/F/小时线全部走 API 兜底链、原断言基本不变。
- **改断言 2 处，均因政策本身被用户否决**：① E-quota `_feed_quota_tier(1000)`
期望 2 → **1**（新档位表语义；1500→1、1700→0 不变），政策 tier 期望随之
2 → 1 并加 sourcing 断言。② 「E adhoc is closed at tier >= 1」作废，改写为
正向验证：活动门打桩放行＋启动器打桩记录时，`_feed_maybe_adhoc()` 在档 1
应开火（期望随当前小时的静默时段口径分支）。

自测结果：全套 `run_bridge_selftests.sh` 全绿——overview 15／p2 34／
**p3 98**／p4 20／p5 23／p6 53／rules 22／anchor 13／spreadsheet 20／
ledger 60／delivery＋sentinel OK／device 系 OK。唯一红：rendition 自测
（503 繁忙门）——本机内存实测 93.5%，是 rendition 的内存护栏
（`_mem_used_percent() > 85`）在本机满载时触发；1.0.26/1.0.27 报告同因
同记，与本次改动路径无关，生产 rendition 不受影响。

**顺带修复一处 FD-1 既有测试死锁（与本次改动无关，但堵住自测门）**：
phase_g 在 `with mod._lock:` 内调用 `_delete_feed_post(pid)`，而该函数
自带 `with _lock` 且 `_lock` 为普通 Lock → 自死锁、0 CPU 永久挂起
（faulthandler 实证挂点 oneday_bridge.py `_delete_feed_post`）。修法只动
测试：删帖调用移出锁外、其余断言不变。此外本机当时另有两个同因挂死
的 p3 进程（非本任务所启，PID 2761/3679，已挂 25 分钟以上）佐证此坑
与本次改动无关；其归属方应自行清理。

## 6. 部署与生产回读验证

部署（FEED-106/NOTIF-127 定式，2026-11-11 晚）：

- 版本：伴生 **1.0.28**，镜像 oneday/companion:1.0.28
  （sha256 5bac70c7feab…）；构建目录 /root/build-1.0.28（克隆
  build-1.0.27 后替换 modules/oneday_bridge.py＋Dockerfile，md5 与本地
  逐字一致：模块 529e2f94…、Dockerfile cdcace27…；运行容器内模块 md5
  复核同值）。
- 回滚点：/root/companion-128-deploy-20261111/docker-compose.yml.1.0.27
  （还原到现行目录后 up -d 即回 1.0.27，旧镜像在机）。
- 部署前后：内存 52%→52%；Hermes StartedAt 逐字不变
  （2026-11-10T14:21:47.024396739Z）；只重建 companion 容器；
  8646 /health ok、degraded=false、哨兵 lastError=null。
- 政策落账（部署后首轮自动改写）：feedPolicy tier 2 → **1**、
  sourcing=**agent-first**、reason 已换新串（§5.4）。

生产回读验证（正式入口 POST /feed/generate 触发 manual 轮，两次
独立回读结果一致）：

- 第 7 轮落账：**status ok、produced 3、dropped 2**；
  modelCalls 9（plan＋4×compose＋editor＋finish 等席位）；
  **tavilyCalls ＝ 0**；**retrieval ＝ {agent: 4, tavilySearch: 0,
  tavilyExtract: 0, firecrawl: 0}**——四个方向（GitHub 本周新入榜
  项目／AI 工具与 Agent 实测／开源权重模型与 API 可用性／副业与变现
  真实复盘）全部由智能体自抓取材且均 produced；
  keyStamp=20261111-1794408739。
- **monthCalls 纹丝不动：12 → 12**。整轮零 Tavily 消耗——去付费依赖的
  核心断言在生产成立。
- 新帖已落库 3 篇：《Kanzo：人机共用一块看板，两周内发了 10 个版本》、
  《LongCat-2.5 开源，K-EXAONE 免费》、《被裁后做到百万美金年入：
  Marc Lou 的收入复盘》。
- 整轮在触发后约 10 分钟内完成落账（观察口径：触发后约 6 分钟时
  生成视图仍 running，其后一次回读已落账）；取材 run 并行＋生成席位
  串行的墙钟慢于探针单 run 估算（§3）。版次/小时线均为后台运行，
  不在用户等待路径上，但小时线整点评估的节奏余量变小，列入观察。



## 7. 残余风险与缺口（如实）

1. **审计弱化点**：候选集由智能体自报，其「URL 确实打开过」无法像 API 实抓
那样由调用本身担保；现有补强＝来源审计＋HEAD 验活＋成帖验真（候选集外
链接整篇退回）照旧。若日后出现智能体编造 URL 的实证，应收紧 material
契约（如要求回传页面原文指纹段供抽查）。
2. **极端叠加**：智能体路径整月不可用（网关故障级）＋月底 Tavily 预算与
Firecrawl credits 先后用尽时，轮次会产空并落账（status=empty 有记录，
不是静默降质）——发生概率低，且届时缺的是整个模型通道，非检索源问题。
3. **publishedAt 覆盖下降**：智能体取材的日期自述率低于 Tavily（探针 2 条
均为 null）；审计器把缺失当未知处理，不会误判新鲜，但「按日期排序/超鲜
拦截」的精度下降，靠 Tavily 深读兜底补一部分。
4. **Serper 未实测**（§4）：凭据在 Bitwarden、本子任务无浏览器能力。
当前组合不依赖它；若后续要加，须先取钥实测再入链。
5. **耗时**：单方向取材 1.5–3 分钟（API 直调为秒级）；版次/小时线均后台
运行，不在用户等待路径上，但整轮墙钟变长，调度间隔（小时线整点评估）
仍够用。
