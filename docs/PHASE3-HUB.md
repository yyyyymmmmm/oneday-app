# 三期枢纽页施工记录（feat/phase3-hub）

> 基线：feat/phase2-split @ ec0f730。依据：phase3-hub-spec.md
> （43 行对照）、phase3-data-design.md、write-approval-bridge-plan.md §3。
> 用户定案 6 点全部遵守：①分段＝原生 segmented Picker；②StatusView
> 本线不碰；③页头圆钮照样板用系统玻璃圆钮（.glass）；④头像徽章/
> 活动圆盘/琥珀角标/身份双卡打包做；⑤身份编辑跳 ProfilesView；
> ⑥审核一期只上待批卡、无历史行。不升版本号（合并后统一发版）。

## 入口接线点（合并时由主线接，本线未动 ChatView/ContentView）

ChatView.swift 现有临时接线（0.4.0 注释已标明三期改道）：

1. 把 body 上的 `.sheet(isPresented: $showModelSettings)` 呈现内容
   从 `NavigationStack { ModelSettingsView() … }` 换成
   `AgentHubView()`——**不要再包 NavigationStack**（AgentHubView
   自带一层，见 AgentHubView.swift 文件头注）。
2. 胶囊 Button 的动作与 accessibilityLabel 文案相应改「打开智能
   体枢纽页」（现为 showModelSettings = true＋「打开模型设置」）。
   状态变量可直接改名 showHub 或沿用旧名，只换呈现内容亦可。
3. 活动行点按已在本线走既有通道：行点按置
   `appState.pendingChatSessionID` 并 dismiss 枢纽页，ChatView 的
   onChange 消费逻辑现成、无需改动；前提是枢纽页关闭后聊天格在
   前台（胶囊入口本就在聊天页，天然满足）。

## 新增文件清单

OneDayCore（纯模型/纯函数，全部有单测）：
- ProfileSoulModels.swift — ProfileSoulDocument 宽容解码＋SoulSectionParser
- HubCron.swift — HubCronKind/HubCronItem/CronHubClassifier
- HubActivity.swift — LogEventRecord/LogEventParser/HubActivityAssembler
- WriteApprovalModels.swift — 桥契约 DTO＋ApprovalSectionState＋WriteGateLabels
- ComputerUseModels.swift — ComputerUseStatus 宽容提取＋BrowserHubState

OneDayApp：
- AgentHubView.swift — 枢纽页本体（页头/模型常驻区/分段/活动段）
- AgentHubStore.swift — 按段懒加载数据中枢（失败隔离、profile 冻结复查）
- HubCronSection.swift / HubApprovalSection.swift /
  HubBrowserSection.swift / HubIdentitySection.swift — 四段视图
- WriteGateClient.swift — 桥客户端（独立 Bearer）＋DemoWriteGateClient 桩

改动既有文件（仅本线职责内）：
- HermesClient.swift — 协议＋实现补 profileSoul/updateProfileSoul/computerUseStatus
- DemoHermesClient.swift — 上三方法合成实现
- KeychainStore.swift — CredentialKey 加 writeGateKey（未并入 all，见未冻结项 3）

测试：HubCronTests（12）/HubSoulTests（8）/HubActivityTests（7）/
HubGateAndBrowserTests（8），共新增 35 个用例。

## 43 行销账（对照 phase3-hub-spec §1）

| # | 落地 | 备注 |
|---|---|---|
| 1 | ✅ | sheet 呈现归接线点；视图侧已备 .presentationDragIndicator |
| 2 | ✅ | ✕ 玻璃圆钮（.glass＋circle），用户定案③ |
| 3 | ✅ | 分享圆钮 ShareLink（名＋状态＋当前模型摘要） |
| 4 | ✅ | 110pt 圆面（chatSurface＋发丝边＋sparkles，与胶囊同源视觉；无服务端头像源） |
| 5 | ✅ | 36pt 铅笔徽章 → 跳本页身份段（规格 §2 推荐口径，本页内闭环） |
| 6 | ✅ | 名＝active profile 经 ServerLabels.profileName；.title＋bold 语义样式 |
| 7 | ✅ | 状态行降级拼装：网关态＋活跃会话数（endedAt 派生）；失败显「状态未确认」不给假离线 |
| 8 | ✅ | 模型常驻区：三行本地名单＋勾选＋服务端默认参考行跳 ModelSettingsView |
| 9 | ✅ | 原生 segmented Picker（用户定案①，案甲） |
| 10 | ✅ | 五段纯图标 SF Symbols（list.bullet/checkmark.shield/display/clock/touchid） |
| 11 | ✅ | 活动流日期组头（今天/昨天/M月d日，组装器分组） |
| 12 | ✅ | 活动圆盘 L4：石板灰蓝渐变（#8A90A6→#6E7488，暗色 #5A5F73→#484C5E）＋白色 glyph |
| 13 | ✅ | 活动行标题 semibold，人话化与抽屉同源（SessionDisplay） |
| 14 | ✅ | 副题＝日志人话 headline（LogEventParser＋LogDisplay），翻不出留空 |
| 15 | ✅ | 行时间 HH:mm、tertiary |
| 16 | ⏸ | 中断红点：无字段，不显、不造数据（规格原定） |
| 17 | ✅ | .listRowSeparator(.hidden) |
| 18 | ✅ | 审核段组头「审核记录」 |
| 19 | ✅ | 待批卡：徽标＋人话摘要（summary 优先、空时 action 兜底）＋来源行 |
| 20 | ✅ | diff 入口 → HubDiffView sheet（按需拉 detail，monospaced＋可选文本） |
| 21 | ✅ | 批准 borderedProminent／驳回 bordered＋confirmationDialog 二次确认 |
| 22 | ⏸ | 历史行：一期不上（用户定案⑥），无模型抓取、不拼装 |
| 23 | ✅ | 诚实状态卡三态：通道未接通／未启用／读取失败，文案分开 |
| 24 | ✅ | 浏览器组头计数：留口期不显（段内只有空态＋状态行） |
| 25 | ✅(缺席) | 留口期不放 + 钮（规格原定） |
| 26 | ⏸ | 任务缩略图：无数据源，二期 |
| 27 | ⏸ | 任务行：无数据源，二期 |
| 28 | ✅ | 留口占位：ContentUnavailableView＋computerUseStatus 三态状态行；不显示计数、不造任务行 |
| 29 | ✅ | 定时三组＋其他周期兜底组（分类器保守口径，数据设计 §3.3） |
| 30 | ✅ | 日历方片（圆角实色＋calendar glyph） |
| 31 | ✅ | 琥珀角标 L5：#E6B036（暗色 #C9962E）＋clock.fill 白 glyph |
| 32 | ✅ | 提醒行：标题＋日期行＋时间行（nextRunAt 绝对时刻） |
| 33 | ✅ | 每日行：标题＋时刻行 |
| 34 | ✅ | 间隔行时钟圆盘（细线描边圆＋clock glyph） |
| 35 | ✅ | 间隔行：标题＋「每 N 单位」人话＋上次运行相对时间（补拉 runs limit 1） |
| 36 | ✅ | 点行跳 CronJobsView（整页管理；CronJobsView 无单任务深链参数，跳整页） |
| 37 | ✅ | 身份段大名（左对齐 .title bold）＋52pt 小头像 |
| 38 | ✅ | 人设正文（soul 分段 persona，次级色） |
| 39 | ✅ | 「风格」caption＋风格正文（SoulSectionParser 按标题分段，无风格段时整块省略） |
| 40 | ✅ | 全宽编辑钮（.bordered）跳 ProfilesView，用户定案⑤ |
| 41 | ✅ | SOUL 卡 L6：暖灰矿物渐变＋白粗标题＋副题「人设全文」＋日期（有字段才显）＋heart glyph → 跳全文详情 |
| 42 | ✅ | 记忆卡 L6：紫调矿物渐变＋「记忆」＋副题「长期记忆」＋text.bubble glyph → 跳 MemoryView（日期无字段省略） |
| 43 | ✅ | 双卡 HStack 等宽、卡高 110 |

## 数据层落地要点

- soul：GET/PUT 客户端方法三处同补（协议/真实/Demo）；GET 按
  设计宽容解码（content→soul→text、日期三形态、顶层字符串）；
  profile 名按单 path segment 百分号编码，不复制既有插值缺口。
- 活动流：组装器全纯函数——会话主表、run 按 id 合并（小 job id
  先认领）、日志 ±60 秒窗＋精确窗优先/短窗优先关联、同分钟同
  标题去重、JSON/无时间戳/超长 token 行不作副题、活跃会话以
  开始时刻排序、截断 50 条、跨日分组。请求预算：sessions 1＋
  logs 1＋jobs 1＋runs（前 20 job、并发 4、每 job limit 3）。
- 审核：桥契约以桥方案 §3 为准（/api/write-gate 前缀、单独
  Bearer、status/pending/detail/approve/reject）；裁决不做乐观
  移除，404 移卡、409 保留＋提示＋刷新、未知子系统不开裁决口。
  origin 译表按后端实测可扩展口径：已知值给人话（assistant_tool
  →「智能体工具调用」、background*→「后台自检」等），未知值回
  落原始值诚实呈现，不丢卡。/status 已上线（两闸门 true、
  counts 实时），三态直接消费。
- 浏览器：computerUseStatus 宽容提取（布尔键→字符串键→指定
  嵌套键两层），unknown 不压成 notReady；BrowserTaskSummary
  只定边界不接数据。

## 未冻结项（合并/联调时处理）

1. **soul GET 真实回执未钉死**：宽容解码已按设计施工，但没有
   脱敏真实回执 fixture 前不宣称 soul 已接通——联调时拿一条真
   回执核对字段集（尤其正文键名与日期字段），必要时收紧候选。
2. **桥联调未做**：桥已上线、/status 可用；pending/detail/
   approve/reject 的全链要在合并后用一条真实 pending 记录验
   （含 404/409 路径与 decisions 日志落行核对）。
3. **WRITE_GATE_KEY 发放通道未定**：客户端从 Keychain
   `writegate.key` 读桥钥匙，读不到即审核段落「通道未接通」。
   钥匙如何发放进 App（随连接凭据一并录入？单独设置项？）与
   断开连接时是否清除（暂未并入 CredentialKey.all）待合并时
   与主线定。
4. **origin 枚举仍可扩展**：实测已见 assistant_tool；后续新
   取值出现时往 WriteGateLabels.originLabel 加译名，未知值
   当前回落原始值上屏（诚实呈现口径，非编造）。
5. **cron schedule 文法样本**：分类器以现有样本施工；真实
   jobs 全量样本复核后若发现 repeat/timezone 等顶层字段承载
   一次性语义，需回 HubCronClassifier 补规则。
6. **状态行本地生成态未接**：规格 §2 第一优先级「本地流式
   生成中」依赖 ChatView 内部状态，枢纽页（本线）拿不到，未
   接；如需，合并时在 AppState 加一个生成态标志由 ChatView 写。
