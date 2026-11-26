# Mac 对位表补全回填（地基棒产出，待并入仓库 docs/mac-parity.md）

- 产出：尚书省地基棒（队列 75），2026-11-26
- 基线：origin/main 尖 1e944ade（盘点时点）；提案基线 ed20da2b 之后客户端源码无新增面（服务端提交为主），盘点结论对现尖仍成立
- 用途：本文件是回填稿——仓库落点按拟案同步口径为 `docs/mac-parity.md`（活文档，随仓走）；因 Mac 侧检出触发执行风险检查、构建验证暂停，本稿先落任务区，批准后由施工方原样并入仓库 docs 并在拟案「盘不全明标」三处各加一行「已于地基棒补全，见 docs/mac-parity.md」。

## 补全一：OneDayCore 219 文件逐个盘点（原盘不全①）

方法：219 个 Swift 文件逐个提取类型声明＋文件头用途并分类（不是按名猜——每个文件都打开看了声明面）。结论：

- **216 个文件**全部对得上对位表第 1–100 件既有行，或属跨面基础设施（连接状态 ConnectionStatus/ConnectionStability、健康词表 ServiceHealth、错误口径 HermesError、本地化 AppLocale、服务端文案安全门 ServerErrorText/ServerLabels、加载态 StoreLoadState 等）——它们是逻辑层，Mac 共用 Core 即自动获得，不构成独立功能面，不单列行。
- **新发现 2 个功能面**（原表未点名，视图层在 OneDayApp 真实存在），新增行 101、102（见下）。
- **平台耦合只有 3 个文件**：ComposerLayout.swift／ComposerTextMetrics.swift（发送舱量测，UIFont/TextKit，互为一体）、RunLiveActivityAttributes.swift（ActivityKit）。地基棒已以 `#if os(iOS)` 整文件守卫处理（iOS 内容一字未动），其余 216 文件导入面全为 macOS 可用框架（Foundation 为主，另 CryptoKit、Compression、UniformTypeIdentifiers、CoreGraphics、os、swift-markdown）。
- 按域归属（供后续棒领活时查）：聊天逻辑层（BottomFollow/BottomStick/ChatListCore/流式四件 Stream*/Streaming*/SSEParser/RunTurn/RunFailure/提交与发件箱 SubmissionLane/OutboxAutoRetry/SendFailure/会话账 SessionRecord/SessionHistorySync/SessionMigration/旁聊 SideChat/SideChatLink/频道分类 SessionClassification 等）归第 13–33 件；文件层（File* 余件、Library*、DocumentReading、SensitiveFilePolicy）归第 5/37/38 件；目标想法动态（GoalCategory/GoalEcho/GoalTaskAssignment/IdeaAnchor/IdeaPresentation/FeedBrief/SourceQuote/BriefingPresentation）归第 2–4/34–36 件；枢纽管理模型（Hermes*Models 群、Ledger*、KanbanModels、Memory*Models、ToolsetModels、MessagingChannels、MonitorBridgeModels、PairingModels、Ops*、SettingsCatalog/SettingsRegistry、WriteApprovalModels、VaultRequestMarker、GrantsModels、ProfileSoulModels/ProfilePackage、ProviderRegistry、ReleaseGatesAndHealth、ServerVersionModels）归第 11/39–64/75 件；设备层（DeviceCalls/DevicePermissionFlow/DeviceSources/DeviceSync/Dictation）归第 27/53/96 件；设计逻辑（ChatTheme/TypeRoles/LegibilityWeightMapping/VisualRules/IconTokens/TabBarSymbols/HeaderButtonSpec/ListRowSpec）随 Design 层共用。

### 新增行（并入对位表 1.2/1.4 之间或续编）

| # | iOS 件 | 源码依据 | Mac 端形态 | 类 |
|---|--------|---------|-----------|----|
| 101 | 站内通知中心（通知列表＋详情：全部已读/筛选/按日分组/落点跳转） | NotificationsView（ChatView 唤出）＋Core：NotificationSummary/NotificationDetail/NotificationTier/NotificationIntakePolicy/NotificationDestination/OverviewBridgeModels | 工具栏铃铛面板或侧边栏一级项（施工棒按 HIG 定），列表＋详情同构；与 M3 系统通知分工：中心管回看与落点，系统通知管打扰 | 原生 |
| 102 | 聊天内嵌结构化卡：待办清单卡＋澄清提问卡 | InlineAgentCardsView（TodoChecklistCardView/ClarifyPromptCardView）＋Core InlineAgentCards 解析器 | 聊天流内嵌卡同构渲染，勾选/作答动作同 iOS | 原生 |

另注（不新增行、归既有行备注）：PushReadinessView（推送就绪面）归第 91 件备注——Mac 推送棒打开时连同就绪自检面一并落；DeviceEverydayExecutors 的 call_start（tel: 拨号确认面）归第 96 件执行器族，见补全三。

## 补全二：能力协商动态项定稿（原盘不全②）

以现尖源码为准，能力协商全集如下（判定单源＝Core CapabilityNegotiation；模型＝CapabilityModels.CapabilitiesResponse）。Mac 端口径：**判定逻辑全在 Core，Mac 共用即自动同口径；各功能棒的视图层必须消费同一份判定结论显隐/降级，不许 Mac 侧另写判定。**

有确定性判定的协商项（7 项）：
| 协商 id | 判据 | 缺失时表现（Mac 同） | 对位行 |
|---|---|---|---|
| enrollment 设备配对认领 | 路由探针 405/404 | 扫码配对不可用，退回手填连接信息 | 76/52 |
| reactionsWrite 消息反应写入 | 路由探针 405/200/404+message_not_found | 反应只在本机显示、刷新即丢 | 22 |
| runIdempotency 任务幂等 | features.runs_idempotency.supported | 断网重发可能双份回复 | 31 |
| clientMessageId 消息级幂等 | runs_idempotency.client_message_id 子旗标 | 跨轮重发去重不成立 | 31 |
| optionsCard 选择框 | features.options_card | 提问轮只能打字作答 | 21 |
| settingsRegistry 设置注册表 | features.settings_registry | 回落内置设置目录（行为不变） | 65–89 |
| selfReactions AI 自反应 | features.self_reactions | 助手不给用户消息贴反应 | 22 |

功能面直读旗标（2 项）：short_lived_tokens（短时票据，归第 75 件）、credential_vault（凭据库显隐，归第 20/71 件）。

只展示不设门（16 项）：CapabilityFeatureCatalog.displayed 的 features 清单（chat_completions 起至 jobs_admin 止）只在连接自检面（第 82 件）以人话行展示，其中 admin_config_rw／jobs_admin／memory_write_api／audio_api／realtime_voice 五项在本部署恒假、按「服务器未开放」呈现——Mac 自检面照此口径。

版本门（version_gate）：capabilities 回文带 min_app_version／recommended_app_version（服务端今晨已补回，部署包待上线）——连接流硬门归第 12 件备注：Mac 登录链在 capabilities 到手后须比对自身版本，低于最低版本时按 iOS 同口径拦下并提示升级（地基棒壳层只读不拦，落到聊天主链棒时与 iOS 对齐执行）。

## 补全三：通话面定稿（原盘不全③）

现尖全仓源码核查结论：**无通话功能面**——Sources 全树无 CallKit、无 WebRTC、无任何厂商通话/活头像 SDK（Anam/Tavus/HeyGen/火山等关键词零命中），活头像已按 2026-11-25 皇上亲令作废且未在代码里复活。唯二沾边项均已归位：①设备执行器 call_start（DeviceEverydayExecutors：打开 tel: 系统拨号确认面，只交面不代发）属第 96 件设备执行器族——Mac 侧后续做执行器映射时以 NSWorkspace 打开 tel:/facetime: 等价落，不单独立行；②Dictation.swift 是听写（第 27 件），与通话无关。**定稿：Mac 端不对位通话面；iOS 若复活通话，按同步口径（对位表加行＋一版本周期内跟进）补。**

## 地基棒对位表销账（本棒名下）

| 行 | 状态 | 证据 |
|---|---|---|
| 12 连接页（首启连服务器） | ✅ 已落 | LoginView：地址＋面板密码一步制；SessionStore 登录链与 iOS connectWithPassword 同序；凭据进 Keychain（同 service/账户口径） |
| 90 凭据存储（Keychain） | ✅ 已落（登录三件套范围） | MacKeychain：service=site.didichou.oneday，账户 server.baseURL/auth.password/api.key 与 iOS 同名 |
| 1 聊天（一级项落点） | ◐ 壳已立 | 侧边栏一级项＋默认落点在位；聊天面本体归聊天主链棒 |
| 2/3/4/5/71/11 一级项（动态/想法/目标/文件/凭据库/枢纽） | ◐ 壳已立 | 侧边栏一级项与中栏/详情占位在位（占位明示棒次），功能归各后续棒 |
| 6/7/8 抽屉三区 → 侧边栏落点 | ◐ 壳已立 | 选项卡区并入侧边栏一级项；频道/旁聊为侧边栏可折叠分组占位（空态文案），数据归聊天主链棒 |
| 65/74/75 设置窗骨架（服务器节） | ◐ 骨架已立 | Settings 场景＋服务器节（连接信息＋断开）；全节归设置棒 |
| 97 网络路径/连接状态呈现（壳层部分） | ◐ 部分 | 侧边栏连接状态卡（已连接绿点＋host）；NWPathMonitor 口径归后续棒 |
| 100 多语言资源复用 | ◐ 随 Core | L10n 在 Core 内，Mac 已链接；壳层文案暂直写中文，逐面接入时按 iOS 同口径走 L10n |
| 101/102 新增行 | ☐ 已立行未施工 | 归聊天主链棒/枢纽棒排期 |

地基棒改动清单（Core/Design 平台适配，iOS 行为零变化）：
1. Project.swift：OneDayCore/OneDayDesign 改多平台（destinations +mac、deploymentTargets multiplatform iOS 26/macOS 26）；新增 OneDayMac 目标（bundleId site.didichou.oneday.mac）与 OneDayMac scheme。
2. Core 三文件 `#if os(iOS)` 整文件守卫：ComposerLayout.swift、ComposerTextMetrics.swift、RunLiveActivityAttributes.swift（iOS 专属面，内容一字未动）。
3. Design AccessibilitySupport.swift：DynamicTypeSize→UIContentSizeCategory 映射段 `#if os(iOS)` 守卫（量测交接是 iOS 发送舱专属），余部跨平台不动。
4. Design Components.swift：Pasteboard.copy 加 macOS 分支（NSPasteboard），iOS 分支原样。
5. Design Palette.swift：macOS 垫片——UIColor 别名 NSColor、语义色按角色映射 AppKit 语义色（windowBackground/controlBackground/label 色族/separatorColor 等）、omColor/appleColor/scrim 加 NSColor 动态供应者分支。角色等值映射，非逐值复刻；暗档 α 语义以动态 α 近似。视觉逐值对齐不在地基棒口径，后续棒按真机截图验。

## 棒 1 对位表销账（聊天主链 MVP，队列 127）

施工：尚书省分身，2026-11-26。基线 6c9ba954，本地尖 d5fda1e8（推送通道未通，只落本地分支）。提交链：e474df35 客户端端点段 → 496ea177 列表/会话两店 → d5fda1e8 视图批（列表/聊天/Markdown/输入/菜单栏/设置）。构建：tuist generate 后 workspace 口径 OneDayMac scheme BUILD SUCCEEDED、零 error。启动实证：App 真实启动常驻无崩溃（DiagnosticReports 无 OneDayMac 记录）；本机 Keychain 无登录三件套，未登录态按 RootView 落连接页（正登实测不在本棒口径内，现行密码未递达）；截图自验被 macOS 屏幕录制权限墙挡住（SSH 与 GUI 会话 LaunchAgent 两路均回 could not create image from display），以进程存活＋无崩溃＋代码路径确定性代偿，明示未达截图标准。

| 行 | 状态 | 证据 |
|---|---|---|
| 1 聊天（一级项） | ✅ 已落 | 三栏做实：侧边栏选「聊天」→中栏会话列表→详情聊天面；侧边栏带未读总数徽标 |
| 9 会话列表 | ✅ 已落（逻辑同构说明） | 网关 /api/sessions 双段拉取（可见＋归档）、搜索/置顶/归档/改名/删除（右键菜单＋⌘F 聚焦搜索＋⌘⌫ 删选中）；写口全走服务端围栏（快照 revision＋request_id、409 重读重试、删除按 Core SessionDeleteDirective 分流）；已读账本地保存（UserDefaults mac.readCounts.v1）。与简报字面差异：Core 的 ChatStore/ArchiveStore 是 iOS 视图层状态店（绑 HermesClient 与 UI 状态），Mac 未直用，改以网关 API＋Core 纯逻辑件（SessionDeleteDirective 等）同构实现同一语义，不另立第二套口径 |
| 12 连接页 | ✅ 接通真实登录态 | 未登录落 LoginView、restore() 读 Keychain 三件套直达主窗、断开回落登录页；错密码报错路径地基棒已验；正登不在本棒 |
| 13 消息流 | ✅ 已落 | transcript 为唯一真源（开会话/落定一律回读）；Markdown 块级走 Core MarkdownParser、代码块 Core CodeHighlight 着色＋横向滚动＋复制钮、表格 Grid 对齐、思考过程折叠、工具调用名行、附件名行 |
| 14 流式与停止 | ✅ 已落 | /v1/runs 提交（client_message_id 与 Idempotency-Key 同值双带）＋SSE 事件流（Core RunEventParser）；流断未见终态走 runStatus 轮询对账（404 转 transcript 定性）；停止走 /v1/runs/{id}/stop 真取消（⌘. 与停止钮） |
| 15 输入框 | ✅ 已落 | NSTextView 原生多行：Return 发送/⇧Return 换行；草稿按会话存（mac.drafts.v1），存否判据走 Core DraftSavePolicy |
| 16 附件 | ✅ 已落 | 拖拽入窗（文件 URL/图片）、NSOpenPanel 多选、粘贴文件/图片三路；图片走多模态 data_url（Core FileSendAssembly）、文件先 /api/files/upload 再拼 @file: 引用 |
| 17 模型选择器 | ✅ 已落 | 工具栏弹出面板（⌘M），清单来自 /v1/models 与会话可用清单；切换走 POST /api/sessions/{id}/model 落锁、失败回滚 |
| 24 聊天内查找 | ✅ 已落 | ⌘F 查找条；匹配/定位走 Core ChatFind（normalizedQuery/matches/nearestMatchIndex），命中高亮＋上/下一条＋计数文案 |
| 30 未读分隔/已读账 | ✅ 已落 | Core UnreadDivider 锚点计算（水位 mac.readWatermark.v1）＋分隔行呈现；已读账与 #9 共用 mac.readCounts.v1 |
| 31 发送失败重发 | ✅ 已落（语义同构说明） | 提交段真失败才入发件箱（幂等键/尝试数/末错/manualOnly，对位 OutboxRetryStore 语义）；重发沿用同一幂等键防双跑（对位能力协商 runIdempotency/clientMessageId 两旗标）；本地持久化在 UserDefaults（mac.outbox.v1），图片以 data_url 随记录保存、文件字节不落盘（重发只带文本与图片，代码注释明示） |
| 65 通用节·身份 | ✅ 已落 | 设置窗通用节：智能体名（档案 soul 经 Core AgentName.resolve）＋当前档案名 |
| 74 当前服务器 | ✅ 已落 | 设置窗服务器节：host/地址/Hermes 版本/可用模型数 |
| 75 登录会话与短时票据 | ✅ 已落 | 登录方式明示（面板密码＋密钥存钥匙串）；短时票据按 Core CapabilitiesResponse.shortLivedTokensSupported 三态如实呈现（支持/未启用/未读取到） |
| 90 Keychain | ✅ 沿地基棒 | 本棒未改，登录三件套读写沿 MacKeychain 既有实现 |
| M1 菜单栏状态项 | ✅ 基础形态已落 | 状态点四态（Core ConnectionStatus/ConnectionPhase 呈现口径）＋待批数（/v1/approvals 计数）；小面板：状态摘要＋服务器＋智能体名＋打开主窗＋断开；30 秒轮询探活与待批 |

未落/遗留（明示）：①正登实测与真数据会话列表目视——等现行密码递达或后续棒在已登录态补验；②长会话滚动/流式跟随手感——已按贴底跟随＋上滑停跟＋回到底部钮实现（对位 Telegram Mac 口径），真机手感待已登录态实测，不以「能显示」冒充已验；③#19 反应、#21/#102 内嵌卡、#22 自反应等不在本棒范围，按拟案归后续棒。

## 棒 2 对位表销账（批准与凭据，队列 141）

施工：尚书省分身，2026-11-26。基线 7cf81306（棒 1 本地尖）。锚点定死（拟案棒 2 定义＋本表）：第 18、19、20、71 号＋M3、M5，及 M1 增强（小面板待批快捷裁决）。构建：tuist generate（DEVELOPER_DIR）后 workspace 口径 OneDayMac scheme BUILD SUCCEEDED、零 error。启动实证：App 真实启动存活跨一轮 30 秒轮询、无崩溃（DiagnosticReports 无 OneDayMac 记录）、已干净退出；本机 Keychain 无登录三件套，未登录态落连接页（正登不在本棒口径内）。

关键口径（施工中实查定版）：
- 写闸批准的现行服务端面是**网关原生 /v1/write-gate/\***（桥退役批 2 并入 write_gate_gateway，与桥同形同状态口径，Bearer 用登录密钥）；iOS 现行客户端仍走已退役的 /api/write-gate 桥前缀（nginx 形状保持镜像另案），Mac 按现行网关面直连，零新后端。模型与文案全用 Core 单源（WriteGateRecord/ApprovalCardCopy/ApprovalCardSpec/GrantsModels），不另立第二套。
- 执行批准逐条记录服务端以 /v1/approvals 回全量记录（approvals＋pending_count＋ledger_degraded），Core 只有计数模型，逐条模型按服务端 approval_projection._public 原形在 Mac 端建模（MacExecApproval）；裁决钮只渲染记录自带 choices。
- 凭据库回包只有元数据（值永不回客户端，与 iOS 详情同口径）：「查看」＝元数据面；值只在创建/替换/兑现表单里由用户输入直送服务端，不落盘不进日志。

| 行 | 状态 | 证据 |
|---|---|---|
| 18 批准卡（停靠区形态） | ✅ 已落 | 聊天详情区输入栏上方停靠区：固定槽位、顶部待批进度（总数＋写入/命令构成）、一次只活一张（写闸走 Core 同序先进先审、执行批准同法），裁决后下一条原地顶上；写闸卡面文案/钮栈全走 Core（ApprovalCardCopy/ApprovalCardSpec：批准主钮／总是允许这一类次钮／驳回文字级；防呆死单只留驳回、高风险不给总是允许；reason 防呆行同口径）；执行批准卡按记录 choices 渲染（批准/本次会话内总是允许/总是允许/拒绝），无等待者只看不批；另有批准面独立窗（待批全量/已决回看）从停靠区与菜单栏打开 |
| 19 授权（grants）管理 | ✅ 已落 | 批准面独立窗「授权」段：/v1/grants 统一清单（命令授权可撤销——成败以事后清单回读为终局，Core GrantRevokeDirective/GrantReadback 同口径；写闸条目只读呈现并指路规则区）＋「总是允许」规则区（/v1/write-gate/rules 可查可撤销）；partial/降级如实呈现，查不到的时间显「未记录」不编造 |
| 20 凭据请求卡（聊天内嵌） | ✅ 已落 | 助手正文 [[vreq:…]] 标记经 Core VaultRequestMarker 摘行、正文摘净后渲染，卡按号取元数据：待处理给逐字段兑现表单（密码类安全输入、完备判据与 iOS 同）＋拒绝，处理完原地收成状态行；查无此号落回纯文本标记、不摆假卡。凭据库面另有请求待办段（列表＋详情兑现/拒绝）同链 |
| 71 密码与安全凭证（凭据库一级项） | ✅ 已落 | 侧边栏一级项做实：中栏条目/请求两段列表，详情区条目元数据面（值不回端、明示口径）＋新建/编辑（整条替换、字段行可增删、值保存即弃）/删除（确认弹窗）全链；请求段列表＋详情兑现/拒绝。能力门与 iOS 同口径（features.credential_vault 未广告即按未启用呈现） |
| M1 菜单栏状态项 | ✅ 增强已落 | 棒 1 基础形态上加：队首待批快捷批准/驳回（写闸）与批准/拒绝（执行）＋「打开批准面」入口；待批数改真口径（见下「顺手修正」） |
| M3 系统通知 | ✅ 已落（保底段） | UNUserNotificationCenter 本地通知：状态轮询检出新待批才发（已见集落盘防重发），批准类带动作按钮（执行＝批准/拒绝、写闸＝批准/驳回），点了直调网关裁决（凭据只读 Keychain 自组客户端）；授权在首次真有待批时才请求（HIG 口径），首启不索要；前台呈横幅 |
| M5 Dock 角标 | ✅ 已落 | 待批总数（两族）＋未读总数合成 NSApp.dockTile 角标，归零即撤 |

顺手修正（留痕）：棒 1 菜单栏待批数走宽容提取，把 /v1/approvals 回包里已决记录也算进「待批」——棒 2 改逐条记录按 status 过滤的真口径，菜单栏与 Dock 共用。

未落/遗留（明示）：①拟案棒 2 销账行曾含第 21（选项卡）、22（表情反应）号——本棒施工单范围定死为批准/凭据/凭据请求三面，两件未落，归后续棒排期，不在本棒冒充；②正登实测与真数据全链（服务端发起待批→Mac 通知弹出→通知内批准→服务端状态翻转回读一致）未验——等现行密码递达后在已登录态补验（与棒 1 遗留①同门）；③截图自验仍被 macOS 屏幕录制权限墙挡住（同棒 1 口径），以构建零 error＋启动存活无崩溃＋代码路径确定性代偿；④写闸详情的改动对照（review diff）已接 /v1/write-gate/pending/{subsystem}/{id}，真数据呈现待已登录态验。

## 棒 3 对位表销账（五格补全，队列 153）

施工：尚书省分身，2026-11-26。基线 7d5bb4ab（棒 2 本地尖）。锚点定死（拟案棒 3 定义＋本表）：第 2、3、4、5、10、34、35、36、37、38 号＋M2。构建：tuist generate（DEVELOPER_DIR）后 workspace 口径 OneDayMac scheme BUILD SUCCEEDED、零 error。启动实证：App 真实启动存活、无崩溃（DiagnosticReports 无 OneDayMac 记录）、已干净退出；本机 Keychain 无登录三件套，未登录态落连接页（正登不在本棒口径内，同棒 1/2 外因）。

关键口径（施工中实查定版）：
- 四面数据全走现行 oneday-bridge（/api/oneday-bridge 前缀、Bearer 登录密钥一把、DTO 全用 Core 单源 Bridge* 形），与 iOS OneDayBridgeClient 同路径同契约，零新后端；文件字节走网关 GET /api/files/download（与 iOS 同路）。
- 动态「讨论」按现行 §208 引用化落：FeedPostQuote 值快照挂发送舱（永不进草稿落盘、切线程作废），发送拼装走 Core FeedPostQuote.outgoingContent（引用块在前、亲笔在后），发送后发 discuss 信号（契约 rev2 §1.9）；已退役的 FeedDiscussPrefill 草稿预填不复活。
- 点赞/已读以桥回执全形为唯一真源（likedAt/readAt 桥落字），不本地拼装；目标写口回执整行替换；简报打开走 POST briefings/{id}/opened 记打开时刻。
- 文件置顶与打开历史是本机账（UserDefaults mac.filePins.v1／mac.fileHistory.v1），与 iOS FilePinStore/FileOpenHistoryStore 同义；文件字节落本机缓存（临时目录，按路径＋mtime 命名）供预览/打开/导出三路共用。

| 行 | 状态 | 证据 |
|---|---|---|
| 2 动态（一级项） | ✅ 已落 | 侧边栏一级项做实：中栏帖流＋详情两栏；侧边栏未读徽标（与聊天共用徽标形态） |
| 3 想法（一级项） | ✅ 已落 | 中栏两段列表（待阅/已处理）＋详情；新建/忽略/删除全链 |
| 4 目标（一级项） | ✅ 已落 | 中栏两段列表（进行中/已完成）＋详情（进展/简报） |
| 5 文件（一级项） | ✅ 已落 | 中栏聚合列表（置顶段＋全部＋打开历史）＋详情预览区 |
| 10 全局搜索 | ✅ 已落（一段待补） | ⌘K 命令面板（菜单命令＋面板式 sheet）：会话段走服务端 /api/sessions/search（450ms 防抖，与 iOS 同口径）、文件段走文件库本地过滤、设置段走 Core SettingsCatalog.search（命中开设置窗）；命中落点齐（会话→聊天面打开、文件→文件面选中）。定时任务段未落：其数据源（Cron 面）归枢纽棒，Mac 暂无此店，不假装有 |
| 34 动态流 | ✅ 已落 | 近 30 天帖流：晨报（morning）＋汇编（digest）双生产者同流、kind 徽标分型（另含调研/事件）；详情全文 Markdown＋why＋链接＋配图；点赞/已读桥回执落字；简报查看/编辑（PUT /meta/brief 单层口径）＋立即生成（POST /feed/generate，409 文案原样上呈）；引用到聊天见关键口径 |
| 35 想法列表与详情 | ✅ 已落 | 两栏呈现：列表分段＋生成管道账面页脚（上次/下次/运行中，旧桥无账面整段不出现）；详情全文＋依据＋交付物清单；新建（POST /ideas）、忽略（PATCH dismissed，桥状态机把关）、删除全链。**采纳未落**：采纳＝看板建卡＋回写 taskId 的复合链，任务板（看板 #58）归枢纽棒、Mac 尚无看板客户端，详情面已明示不摆假按钮，随枢纽棒一并落 |
| 36 目标 CRUD＋简报 | ✅ 已落 | 列表＋详情；新建/编辑走 Sheet（Core .make/.edited 表单口径）、子目标创建（parentId）、状态流转（完成/重开，PATCH {status}）、删除（确认弹窗）；详情含进展时间线（手记追加＋删条纠错，右键菜单）与简报信件（点开展开全文＋桥记打开时刻，未打开信封徽标区分） |
| 37 文件库 | ✅ 已落 | 聚合读面单流消费（服务端走查/准入/去重/排序）；详情预览按类型原生呈现（图片滚动查看/文本等宽全文/PDF 走 PDFKit）；打开＝本地副本交系统默认应用、导出＝NSSavePanel 落盘、置顶＝本机账段置顶、打开历史记账并可回跳选中——四动作代码路径齐备（真数据实测待已登录态，见未验项） |
| 38 文件失败兜底页 | ✅ 已落 | 下载/预览失败落兜底面：失败原因（网关人话口径）＋重试（强制重取）；类型不支持内预览时给「打开/导出」出路，不白屏 |
| M2 速记窗 | ◐ 已落（改键未落） | ⌥Space 全局热键（Carbon RegisterEventHotKey，系统级注册）唤出置顶小窗：写一句话发送即建新会话并提交一轮（服务端续跑），成功态给「在主窗打开」落点（通知直达该会话）；Esc 收起、失活自动隐藏。**热键改键（录制器）未落**：现为固定 ⌥Space，拟案标「可改」——录制器属设置棒细项，本棒明示顺延 |

未落/遗留（明示）：①第 21（选项卡）、22（表情反应）号**不归本棒**——拟案分棒表把两件列在棒 2 销账行，棒 2 施工单范围定死为批准/凭据三面而顺延；棒 3 定义（五格补全）不含聊天内嵌卡，两件现无棒承接，建议随枢纽棒或聊天补全小棒补落，本棒不冒领；②正登实测与四面真数据全链未验——等现行密码递达后在已登录态补验（与棒 1/2 遗留同门），文件面打开/预览/导出/置顶的真数据实测同在此列；③截图自验仍被 macOS 屏幕录制权限墙挡住（同棒 1/2 口径），以构建零 error＋启动存活无崩溃＋代码路径确定性代偿；④全局搜索会话命中的打开落点以会话列表已载行为限（命中未在已载列表时先回读列表再选中，列表分页外的极旧会话可能选不中——与棒 1 列表分页口径同限，不另立第二套打开链）。

## 棒次表改记（2026-11-26 17:39 司礼监裁定，棒 4 施工同趟落）

第 21（选项卡）、22（表情反应）两件**不归枢纽棒**（枢纽棒是管理面，别混面），新立一棒「聊天补全小棒」专承接，排枢纽棒之后、设置棒之前；账本侧已立 mac-09 与本表对齐。现行棒次序：

| 棒 | 内容 | 状态 |
|---|---|---|
| 棒 0 地基 | 多平台化＋登录链＋壳 | ✅ 关账（mac-02 残留外因见该节） |
| 棒 1 聊天主链 | 会话/消息/输入/附件/模型 | ✅ 关账 |
| 棒 2 批准与凭据 | 批准卡/授权/凭据请求/凭据库＋M3/M5 | ✅ 关账 |
| 棒 3 五格补全 | 动态/想法/目标/文件＋全局搜索＋速记窗 | ✅ 关账 |
| 棒 4 枢纽 | 管理面 24 面（#11/#39–#64）＋顺延两件（#10 定时段、#35 采纳） | ✅ 本节关账 |
| 聊天补全小棒 | 第 21（选项卡）、22（表情反应）号 | ☐ 未开工（账本 mac-09，触发＝棒 4 关账后派工） |
| 棒 5 设置 | 设置全节（#65–#89）＋M2 热键改键录制器 | ☐ 未开工（账本 mac-07） |
| 棒 6 推送 | APNs 条件棒（保底已由棒 2 M3 落） | ☐ 条件棒（账本 mac-08，不产生新付费） |

## 棒 4 对位表销账（枢纽，队列 159）

施工：尚书省分身，2026-11-26。基线 4cd05ff0（棒 3 本地尖），本地尖 95b1963d（推送通道未通，只落本地分支）。提交链：85cdb368 客户端枢纽端点段 → 23dfaa61 枢纽状态店与面注册表 → c00fac8f 枢纽视图批＋壳层接线＋全局搜索定时段＋想法采纳 → 95b1963d 视图按面拆分单文件 → 本节入仓。构建：tuist generate（DEVELOPER_DIR）后 workspace 口径 OneDayMac scheme BUILD SUCCEEDED、零 error（拆分前后各一轮）。启动实证：App 真实启动存活（两轮，pid 33374/33723）、DiagnosticReports 无 OneDayMac 崩溃记录、已干净退出；本机 Keychain 无登录三件套，未登录态落连接页（正登不在本棒口径内，同棒 1–3 外因）。

锚点定死（开工自拟案棒 4 定义＋本表逐件列死）：第 11 号（枢纽入口）＋第 39–64 号逐件＋棒 3 顺延两件（第 10 号全局搜索定时任务段、第 35 号想法采纳）。21/22 不归本棒（见上棒次表改记）。

关键口径（施工中实查定版）：
- 只复用现行网关 API、零新后端：桥面走 /api/oneday-bridge（台账/监控/预设）、网关原生面走 /v1（工具集/写闸/授权）、面板面走 /api（cron/skills/mcp/delegation/kanban/pairing/analytics 等），全部路径逐条对 iOS HermesClient 协议声明与实现核过，未猜一条；凭据一把（Bearer 登录密钥＋共享 cookie 双通道，与 iOS 同）。
- 一切写动作走「发出→回读该面→以回读为终局」，不认回执自报（MacHubStore.settle 统一收尾）；先读后改两处：委派模型/档案路线设默认（拿原始 routing 文档只换 default、余字段原样带回）、预设模型组合增删（整档 PUT、未知键保留）。
- 审计面不另立第二份状态：已决/规则/授权直接复用棒 2 的 MacApprovalStore（同一份状态、同一套撤销口径），枢纽内是它的落点。
- 身份头像廊：image 类逐张走 identity-bridge 图片口拉字节，preset 类无字节以符号格呈现（与网页端 2.17.1 修法同口径），不摆假图。
- 想法采纳链：看板建卡（幂等键 idea-adopt-<想法 id> 防双卡）→ 桥 PATCH 回写 status=adopted＋taskId → 回执整行替换；taskId 是「已转任务」的服务端真源（Core BridgeIdea 口径）。

| 行 | 状态 | 证据 |
|---|---|---|
| 11 枢纽（一级项） | ✅ 已落 | 侧边栏枢纽做实：中栏 24 面清单（带对位号）＋详情按面渲染，壳层占位已摘除 |
| 39 工作台账 | ✅ 已落 | 桥 /ledger/summary＋/ledger＋/ledger/{id}：汇总＋条目列＋条目详情 |
| 40 审计 | ✅ 已落 | 已决记录＋总是允许规则（可撤销）＋统一授权（可撤销），状态归 MacApprovalStore（棒 2 同一份） |
| 41 电脑 | ◐ 部分 | 电脑操控状态＋出口状态两段已落（/api/tools/computer-use/status、/api/egress/status）；桌面/文件/终端的远程操控交互面未落——iOS 走盒桥交互会话，Mac 归后续棒，本棒不冒领 |
| 42 身份 | ✅ 已落 | 身份全档＋头像廊（image 拉字节/preset 符号格/当前标注） |
| 43 邮件 | ◐ 部分（无数据源） | 服务端无邮件数据源、iOS 注册表此格未长出前同样不可达；Mac 如实呈现未启用态、不摆假数据，数据源长出后两端同步接 |
| 44 档案 | ✅ 已落 | 档案清单＋切换激活＋Soul 查看/编辑写回（回读对账） |
| 45 记忆 | ✅ 已落 | 记忆状态（provider/内置文件）＋分层摘要＋学习图谱节点全文编辑/删除（服务端语义分流确认文案） |
| 46 技能 | ✅ 已落 | 清单启停/锁定＋全文编辑＋市集搜索/安装 |
| 47 工具集 | ✅ 已落 | /v1/toolsets 平台真值清单＋启停（回读为准） |
| 48 委派 | ✅ 已落 | 路由全量呈现＋后端切换＋模型/档案路线设默认（先读后改＋回读） |
| 49 定时任务 | ✅ 已落 | 清单（系统任务如实标注）＋暂停/恢复/立即跑/删除＋新建表单＋蓝图目录 |
| 50 MCP | ✅ 已落 | 服务器启停/测试＋可安装目录安装；插件预置条目开关服务端锁定、面内明示 |
| 51 连接器 | ✅ 已落 | Core 静态目录单源（八家＋接入说明）＋已连接＝端点在册 MCP 服务器（ConnectedConnector 同口径） |
| 52 频道 | ✅ 已落 | 消息平台全量＋网关频道两段状态呈现 |
| 53 设备 | ✅ 已落 | 设备会话/同步状态（device-bridge 既有口） |
| 54 监控 | ✅ 已落 | 清单＋变化记录展开＋新建/删除（桥 /monitors 系） |
| 55 Webhooks | ✅ 已落 | 平台开关＋订阅启停/删除＋新建（一次性密钥只当次呈现不落盘） |
| 56 预设 | ✅ 已落 | 模型组合清单＋增删（整档先读后改写回） |
| 57 环境变量 | ✅ 已落 | 清单只显遮蔽值；明文经 reveal 当次取回不落盘；设值/删除后回读 |
| 58 看板 | ✅ 已落 | 板切换＋按列分组卡清单＋建卡/改状态/删卡/催派（kanban 插件口） |
| 59 网关状态 | ✅ 已落 | 服务端状态（版本/网关运行态/平台连接）＋启动/重启/停止（确认后执行、回读对账） |
| 60 服务器详情/会话 | ✅ 已落 | 网关面承接服务器详情（版本/状态/平台）；登录会话清单在设备面（/v1/auth/sessions），会话浏览本体归棒 1 第 9 号 |
| 61 主会话 | ✅ 已落 | device-bridge 停泊态/设备会话段呈现（与 iOS MainSessionView 同源） |
| 62 配对管理 | ✅ 已落 | 待批批准/清空＋已配对撤销（面板 /api/pairing，cookie 同路） |
| 63 模型与服务商 | ✅ 已落 | 可选模型清单＋设主模型（确认后执行）＋辅助模型/MoA 配置呈现 |
| 64 用量 | ✅ 已落 | 近 30 天总量＋按日＋按模型（Token＝入＋出，Core 口径） |
| 10 全局搜索·定时任务段（棒 3 顺延） | ✅ 已落 | ⌘K 面板加定时段：Cron 数据源本地过滤（名/提示词），命中直达枢纽定时任务面 |
| 35 想法采纳（棒 3 顺延） | ✅ 已落 | 详情面采纳钮接通：看板建卡→回写 taskId→回执替换；已转任务在详情明示任务 id |

未落/遗留（明示）：①第 41 号电脑操控交互面（桌面/文件/终端远程操控）未落，见该行；②第 43 号邮件面无数据源（服务端未长出，iOS 同），见该行；③正登实测与 24 面真数据全链未验——等现行密码递达后在已登录态补验（与棒 1–3 遗留同门；本棒各面在未登录态按连接页落点，未假装验过）；④截图自验仍被 macOS 屏幕录制权限墙挡住（同棒 1–3 口径），以构建零 error＋启动存活无崩溃＋代码路径确定性代偿；⑤本地尖 95b1963d 起 Mac 线全部提交仍待 Mac git 推送通道打通后推送（osxkeychain 非交互读不到，同前棒）。

## UI 量测对位表（mac-09 聊天补全＋棒 5 mac-07 设置全集，动工基线）

对照标杆：macOS 系统设置（Sequoia/Tahoe 双栏 Grouped Form）、Telegram macOS 与用户提供的桌面端参考图。

| 界面要素 | 字号 / 字重 | 间距 / 尺寸 / 圆角 | 颜色 / 对比度（WCAG AA ≥ 4.5:1） |
|---|---|---|---|
| 聊天助手消息卡片 | 正文 14pt Regular（Markdown 走 MacMarkdownView） | 宽上限 740pt；内边距 14H / 12V；圆角 16pt；行间 14pt | 底 `Palette.bubbleFill`（浅 `#E9EAEC` / 暗 `#2C2C2E`），主墨 `Palette.ink`（浅 `#11191C` 对比 >14:1 / 暗 `#FFFFFF` >13:1） |
| 聊天用户气泡 | 正文 14pt Regular | 左留白 ≥60pt；内边距 14H / 10V；圆角 16pt | 底 `Palette.userBubbleFill`，字 `Palette.userBubbleText`（均过 4.5:1 对比度闸） |
| 气泡旁悬停动作条 | 图标 12–13pt Regular | 胶囊高 30pt；按钮热区 26×26pt；与气泡间距 8pt | 底 `Palette.surface @ 95%`，描边 `Palette.separator @ 45%` 0.5pt，图标 `Palette.inkSecondary`（≥5.2:1） |
| 反应药丸 / AI 角标 | Emoji 13pt（pill）/ 12pt（角标） | pill 高 26pt、角标高 22pt；底角悬出 14pt；行底预留 12pt | 底 `Palette.surface`，描边 `Palette.pageBG` 1.5pt，自选态轻染 `Palette.primaryTint` |
| 聊天内嵌选项卡 | 项文 13pt Medium；回执 12pt Regular | 项高 ≥36pt；项间 6pt；圆角 12pt；最大宽 420pt | 底 `Palette.surface`（悬停 `Palette.primaryTint`），主墨 `Palette.ink`，次墨 `Palette.inkSecondary`（≥4.85:1） |
| 底部悬浮胶囊输入舱 | 输入正文 14pt Regular | 外胶囊圆角 22pt；内边距 12H / 6V；左右圆钮 30×30pt；外边距 18H / 14B | 底 `Palette.surface`，描边 `Palette.separator @ 45%` 0.75pt，软影 `black @ 6%` r8 y2 |
| 设置窗双栏骨架 | 侧栏项 13pt Regular；分组表单项 13pt；页脚说明 11pt | 窗口 740×540pt 起；左侧栏 196pt（184–230pt）；图标块 22×22pt 圆角 5pt | 原生 `.listStyle(.sidebar)` + `.formStyle(.grouped)`，全系统语义色与 `Palette` 同步 |

## 聊天补全小棒对位表销账（mac-09：#21 选项卡＋#22 表情反应）

基线：`main @ 3ce107bc`，分支：`feat/mac-batons-5-9`。

| 行 | 状态 | 证据 |
|---|---|---|
| 21 选择框（选项卡） | ✅ 代码已落（待本机真构建＋正登补验） | `MacOptionsCardView.swift` + `MacConversationStore` 复用 Core `OptionsCardOverlay`/`OptionsCardLogic`/`OptionsCardState` 单源；受 `CapabilityNegotiation.optionsCardAvailability` 门控；支持 live 点选提交 `sendText`、selected 单行回执、expired 置灰摘要 |
| 22 表情反应＋AI 自反应 | ✅ 代码已落（待本机真构建＋正登补验） | `MacReactionViews.swift` + `MacMessageRow.swift` + `HermesMacClient`（`PUT/DELETE /v1/reactions/{session_id}/{row_id}`＋`routeProbe`）；复用 Core `MessageReactions`/`ReactionEmojiCatalog`/`AISelfReactionDecision`；桌面悬停浮条（受 `ChatReactionsFloatingBarFeature` 开关门控）＋右键子菜单双入口；用户药丸点按撤回、AI 角标（受 `ChatReactionsAISelfFeature` 门控）不可点；服务端未开放 404/405 时按能力协商降级为本机显示并明示 |

## 棒 5 对位表销账（mac-07：设置全集与诊断＋M2 热键录制器）

基线：`main @ 3ce107bc`，分支：`feat/mac-batons-5-9`。凭据纪律核查：全包只用 `MacKeychain` 一把主钥，设置与诊断任何界面均不展示明文密码/密钥（全掩码 `••••••••••••`）。

| 行 | 状态 | 证据 |
|---|---|---|
| 65/66 通用与语言 | ✅ 代码已落（待本机真构建＋正登补验） | `MacSettingsView.swift` 升级为 macOS 原生双栏 `NavigationSplitView` + `SettingsCatalog.search` 顶部搜索；通用页含身份卡、语言四档（直绑 `LanguageStorageKeys.appLanguage`，`OneDayMacApp` 根层注入 `.locale` 即时生效） |
| M2 速记窗热键改键录制器 | ✅ 代码已落（待本机真构建＋实测） | `MacQuickEntry.swift` 新增 `MacHotKeyBinding` 持久化与热重绑；`MacHotKeyRecorderRow` 通过原生 `NSEvent.addLocalMonitorForEvents` 录制修饰键组合并支持一键恢复 `⌥Space` |
| 67 外观 | ✅ 代码已落（待本机真构建） | `MacSettingsAppearancePane.swift` 直绑 Core `AppearanceStorageKeys` 全五键（外观模式/聊天主题/强调色/背景/文字大小）＋单数据源实时预览；`OneDayMacApp` 根层应用 `.preferredColorScheme` 即时生效 |
| 68/69/70/91 通知、互动、语音与推送就绪 | ✅ 代码已落（待本机真构建＋正登补验） | `MacSettingsNotificationsPane.swift` 接 Core `NotificationTier` 四开关（联动 `MacNotifier.swift`）、本机通知授权状态与 APNs 现状、互动两开关（AI 自反应受 `SelfReactionsSettingsRowPolicy` 能力门控）、语音自动朗读与 `/api/audio/voice-config` 状态 |
| 74/75/76 服务器、登录会话与添加设备 | ✅ 代码已落（待本机真构建＋正登补验） | `MacSettingsServerPane.swift` 展示服务器信息、全掩码凭据、短时票据能力位、`/v1/auth/sessions` 清单与撤销、`/v1/enrollment/codes` 一次性认领码签发、二次确认断开连接 |
| 82/83/84/85/86 诊断与日志全集 | ✅ 代码已落（待本机真构建＋正登补验） | `MacSettingsDiagnosticsPane.swift` 含连接自检（复用 Core `SelfCheckReportBuilder` 并发只读探活）、运维体检与存档（doctor/security-audit/backup/checkpoints）、系统日志（`/api/logs` 筛选/搜索/复制）、聊天与能力协商诊断＋脱敏摘要复制、设置注册表只读检视 |
| 87/88/89 帮助、关于与法律文档 | ✅ 代码已落（待本机真构建） | `MacSettingsAboutPane.swift` 含连接帮助、GitHub 外链、Core `ReleaseNotes` 更新说明、直读 `Bundle.main` 真版本号、隐私政策与用户协议全文 Sheet |

## 棒 6 核查结论（mac-08：推送增强·条件棒）

1. **服务端推送发送面核查结论：已原生支持 macOS，无需改服务端代码。**
   - `server/patches/push_tokens.py`（`POST /v1/push/tokens`）接受任意非空 `bundle_id`（上限 160 字符）与 `environment`（`sandbox`/`production`），天然兼容 `site.didichou.oneday.mac`。
   - `server/patches/push_sender.py:147` 发送 APNs 时动态读取每条已登记 token 自带的 `bundle_id` 作为 `apns-topic`（`"apns-topic": str(row.get("bundle_id") or cfg["topic"])`），并非硬编码 iOS bundleId。
2. **红线阻断结论（停工报结论，不自行开通）：**
   - `server/patches/push_sender.py:13-16` 明载服务端发送 APNs 需配置 Apple `.p8` 私钥（`APNS_KEY_PATH`/`APNS_KEY_ID`/`APNS_TEAM_ID`），且 macOS 客户端申请 APNs deviceToken 必须具备含 `com.apple.developer.aps-environment` 权益的签名描述文件——两者均**强制依赖付费 Apple Developer Program 账号**（$99/年）。
   - 依「不许花钱、不许绑卡」红线，**棒 6 暂不开工、不改签名权益**；Mac 端继续由棒 2 已落地的 **M3 本地通知（带批准/拒绝动作按钮）** 保底，并在棒 5「设置 → 通知与互动 → 推送就绪状态」中如实呈现。

