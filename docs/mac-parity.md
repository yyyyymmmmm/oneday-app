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
