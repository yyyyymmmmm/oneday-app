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
