# FEED-117-REPORT — §127 期一：动态质量环（编辑环＋口味笔记骨架＋点赞落盘）

- 版本：伴生 **1.0.17**（1.0.16 → 1.0.17），2026-11-11 部署上线
- 范围：规格 `three-pages-muse-alignment-spec-20261111.md` §127.2 期一，**仅伴生（动态）侧**；期二（版次二/小时线/A 级事件帖/meta.activity）、期三（点子池）未碰。App 包 A（点赞钮接线、why 呈现位）不在本单内，待 App 侧另行施工——桥侧契约已就绪（见下）。
- 回滚基线：`/root/companion-117-deploy-20261111/`（旧 compose、companion.env、data-before.json、inspect.json、memory-before.txt、oneday_bridge.py.116、build.log）；服务器构建树 `/root/build-117/`；回滚＝prod compose 与 companion.env 版本位改回 1.0.16 后 `docker compose up -d`（旧镜像 oneday/companion:1.0.16 保留在机）。

## 改了什么（仅 modules/oneday_bridge.py 一份源码）

1. **管线换代**：`_run_research_round` 重写为 派题（assignment）→ 方向并行调研/著帖（ThreadPoolExecutor ≤5，每方向一席）→ 候选池 → **编辑环** → 按编辑序落库。旧「逐方向直落＋RESEARCH_MAX_POSTS 截断」口径作废。
2. **派题桌**：方向上限 4→5；每方向带 angle（角度）/diff（与往期不同点）；至多 1 个方向可 dual（同方向双角度双候选）。派题提示词注入：简报执行层＋**stated 全文**（亲口口径硬约束）＋口味摘要（软 guidance）＋各方向近 7 天产量/被删数＋近 3 天已用角度＋近 30 天避让清单。
3. **编辑环**（新增 `RESEARCH_EDITOR_PROMPT`＋`_run_editor`/`_parse_editor_output`/`_editor_apply_repairs`）：1 次模型调用读全部候选（≤7）＋近 30 天标题＋近 3 版构成＋stated，产出 publish（按序）/repairs/drops，缺陷编号 **E1–E10** 按规格清单。可修边界只限 why 重写（10–200 字校验，不过按 E3 drop）/clamp（删小标题与分隔线后重走既有 clamp）/dropImage；编辑给的非法缺陷编号不认（候选转「未表态」）；编辑漏列的候选按代码门放行排末尾并记 `editorOmitted`；**代码再兜底 E6**（同方向只留第一帖）；编辑调用失败/产出不可解析＝全体候选代码门放行＋`editorNote` 明记（不静默装通过）。
4. **口味笔记骨架**（meta.tasteNotes）：{updatedAt, version, stated[], likes[], dislikes[], discussHints[], summary, dirty, lastRolledAt}，各列表留最近 100 条。折入点：like 新赞→likes；删帖→dislikes（via=delete）；signal discuss→discussHints；简报兴趣真变更→stated（PUT 分支同一锁内）。**Rollup**：每轮派题前 dirty 且有新信号（≤20 条）才跑 1 次模型调用折摘要（≤600 字，>15 天信号标「旧」、权重序 亲口＞讨论自述＞点赞/讨论＞删帖写进提示词）；失败保留旧摘要、不阻塞本轮、rec 记 tasteNote。只读（已读回写）永不折入——代码上无此路径。
5. **口味注入面收口**：摘要＋stated 只进派题提示词；著帖材料只加本篇 angle 一行，**不带口味**（自测 D6 双向断言）。
6. **新端点**：`POST /feed/{id}/like {liked:bool}`（幂等，likedAt 桥为真源，返回帖视图）；`POST /feed/{id}/signal {type:"discuss", note?}`（其余 type 回 400；note 为用户自述句，无 note 记弱信号模板句；讨论正文不进笔记）。
7. **帖视图与落盘**：`_feed_view` 增 likedAt/edition/angle 三键（旧帖 None 容忍）；发布落盘带 likedAt=None、angle、edition（schedule 轮＝`YYYYMMDD-A`，brief/manual 为 None）。
8. **轮次记录（rec）增账**：edition、candidates[{id,title,direction,angle}]、publish[ids 按序]、publishTitles、repairs、editorDrops[{id,defect}]、editorOmitted、editorNote、modelCalls、tavilyCalls（search＋extract＋firecrawl 合计）、tasteRollup。produced＝发布数，dropped＝著帖 drop＋编辑 drop＋超池 drop。

## 一处实现口径说明（请主线知悉）

规格 §127.2 写「编辑定序以 createdAt 依次递增落盘」。App 动态流按 createdAt **倒序**呈现（新在前），若字面递增落盘，编辑排第一的帖会沉到本版最末——与「编辑定序即呈现序」的意图相反。本单实现为：发布序第一帖 createdAt 最大、依次递减偏移（编辑序＝流内序），报告在此明记，验收以流内序为准。

## 自测（全套两轮＋终局一轮，全绿）

- p3 29→**46**：phase B 改按 run-id 前缀分发 fake（plan/compose/editor/rollup），保留原三断言（集外链接整帖 drop、无候选时编辑不调用、skip 诚实空轮）＋断言 likedAt=None 与 rec 候选账/modelCalls=3；**新增 phase D 七组**：D1 编辑 drop E1＋why 修复只落一帖、D2 编辑序与 createdAt 序一致、D3 双候选同方向代码 E6 兜底、D4 like/signal/delete 三路折入＋like 幂等＋坏 type 400、D5 rollup 落摘要＋version+1＋二次 no-op、D6 派题 prompt 含 summary 与 stated 且著帖 prompt 不含口味、D7 编辑基础设施失败回退放行＋editorNote。
- p4 19→**20**：旧断言「方向上限 4」按规格新口径改 5，并新增 angle/diff/dual 上限解析断言。此为本次唯一的既有断言口径变更，源于规格 §127.2 明确的 ≤5 方向，非回归。
- 其余与 1.0.16 基线一致或增：overview 8／p2 34／p5 23／p6 53／write-gate 22／ledger 60／spreadsheet 20／device OK／device_sync OK／model-combos OK。

## 沙盒干跑（上生产前，生产 data.json 副本＋容器内真环境真模型）

- schedule 轮全程 71.6 秒：status=ok，**edition=20261111-A**，modelCalls=6（≤9 ✓）、tavilyCalls=9（≤16 ✓）。
- 编辑环真实工作：1 候选（搞钱和副业）经 **clamp 修复**后发布；另两方向（GitHub 热门、AI 进展）写手以「材料撑不起角度、不编造」honest skip 并留长理由——事实纪律在新管线下照常生效，非故障。
- 发布帖 why 非空、angle 落盘、likedAt=null ✓；对该帖 like＋signal 后 tasteNotes likes=1、discussHints=1、dirty=true ✓。
- 干跑产物在副本上，未触生产数据；干跑目录与密钥文件已清理（容器 /tmp/dry117、宿主机 /tmp/dryrun117 均删，keys.env 已 shred）。

## 部署验收（生产实查）

- 内存：部署前 51%、部署后 3945/7725MB ≈51%（红线 80% 未近）。
- 版本对齐：镜像 oneday/companion:1.0.17；prod compose image＋env、companion.env 三处均为 1.0.17；运行中进程环境 COMPANION_VERSION=1.0.17。
- 五模块进程全在（write-gate/overview/box/oneday/device＋front）；oneday /health：ok、**degraded=false**、ledger degraded=false、collector lag 9s。
- Hermes StartedAt `2026-11-10T14:21:47.024396739Z`，与全天基线逐字一致，未动。
- 生产数据完好：ideas 6 条、feedPosts 2 条（与部署前一致）；tasteNotes 尚未建（懒建，首个折入事件或下轮 rollup 时生成，干跑已证）。
- 新路由生产探活：POST /feed/f_nope/like → 404「帖子不存在」；POST /feed/f_nope/signal {type:bogus} → 400「暂不支持的信号类型」；GET /feed、/feed/generation 正常。

## 首验点与遗留

- **2026-11-12 08:30 自然轮**＝期一生产首验：应带 edition=20261112-A、四账齐全、why 非空。规格「连续 3 版 drops+repairs 合计 >0」的观察从此轮起数（干跑已先证 repairs 真实发生 1 次）。
- 点赞端到端（杀 App 重开状态仍在）须等 App 包 A 接线后验，桥侧已就绪。
- 期二注意：daily 模型账将升至规格 §127.5 的量级，上线前按规格复核 Tavily 额度（本期一单版实测 Tavily 9 次，远低于期二全天上限 55）。
