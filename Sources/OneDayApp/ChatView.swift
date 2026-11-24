import NukeUI
import OneDayDesign
import OneDayCore
import Photos
import QuickLook
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// 聊天页：本地会话（SwiftData）＋ /v1/chat/completions 流式。
/// 上下文取当前会话最近 20 条；停止生成保留已生成的半截回复。
/// v2 视觉（docs/DESIGN-V2.md §3.5）：用户是浅染气泡、输入区
/// 是浮空胶囊，流式光标是本页的签名细节。助手消息形态三度
/// 易稿：v2 定为裸排（学 ChatGPT/Claude），0.2.5 按用户真机
/// 对照 Muse 推翻改浅灰软填充泡（DESIGN-V4 §9 追记），
/// 2026-11-13 割裂感 A 止血档再改判回落面（散文直落大面、
/// 异构件才成卡，见 assistantBubble 注），填充泡口径一度
/// 作废；2026-11-14 §225 用户点选三项全改恢复气泡（中性
/// 浅灰容器＋纯文字内容，A1 撤泡口径作废，见 §225.2）。
/// 0.1.3 导航（§7）：会话历史改左侧抽屉（顶栏左键＋左缘手势
/// 唤出），顶栏中 = 会话名＋模型名副题，右 = 新建会话。

/// 距底原始读数匣（§199）：滚动几何回调逐帧写、
/// 落定评估（R4 事件化后为事件到场即读）的原始距
/// 底——旧形态
/// 存 @State，滚动中读数逐帧变、等值守卫挡不住，
/// 等于每帧触发一次全页 body 重跑（审计 §2.1 的放
/// 大器一半）。改存引用匣：写不触发任何视图失效，
/// 读到的恒是读时点的最新值——消费者（落定评估
/// 与同点打点）在读时点上与旧 @State
/// 读数逐字相等，判定阈值与语义零变更，只降回写
/// 频次（§199 包 1 第三件）。经 @State 持实例（初
/// 值只用一次），跨 body 重建恒为同一匣
private final class BottomDistanceRecorder {
    var latest: CGFloat = 0
    /// 内容末端（栈尾锚）是否完整落在可视区内（手感
    /// A 档事实信号，见 Core BottomFactCalibration
    /// 注）：由尾锚自身的几何回调写本匣——与 latest
    /// 同纪律，写不失效任何视图，只在派生点与评估
    /// 点被读；切线程时由线程切换路清零，防旧线程
    /// 的末端事实误校新线程首帧
    var contentEndVisible = false
    /// 列表容器高（与 latest 同源的几何读数）：喂尾
    /// 锚事实回调判「完整可见」的视口高——@State 的
    /// listViewportHeight 只供内容栈撑满，两处同源
    /// 不分叉，本匣是事实回调的读口
    var containerHeight: CGFloat = 0
    /// 列表底 inset 实值（adjustedContentInset.
    /// bottom 的同拍读数）：喂尾锚回调的有效视口
    /// 判定——视口高须扣除本带（＝输入舱遮挡带，
    /// 尾锚落在带内不算「在屏可读」）；与 latest
    /// 同纪律、写不失效任何视图
    var bottomInset: CGFloat = 0
}

struct ChatView: View {
    // （0.4.5 删：onOpenServerSession／onSelectTab 两注
    // 入闭包——它们唯一的调用方是抽屉，抽屉已提到壳
    // 层并自带通道（DrawerView），本页不再需要）
    /// 0.6.0：总览桥状态（壳层持有）：顶栏状态行与铃铛
    /// 角标的数据源；nil 时状态行落「暂时联系不上」
    var overviewStore: OverviewBridgeStore?
    /// 0.17.0（真机五修⑤）：枢纽 sheet 开合——底栏活
    /// 动格撤销后，身份胶囊身份域与回告卡点按改开本
    /// sheet（AgentHubView .activity 四段，自带导航栈；
    /// 0.6.0 的 onOpenActivity 切格注入自此退役）
    @State private var showHub = false
    /// 中枢 zoom 转场命名空间（§434）：源＝顶簇居
    /// 中大头像（headerIdentityHero 挂 matched-
    /// TransitionSource），目标＝中枢页（呈现点挂
    /// navigationTransition）
    @Namespace private var hubZoomNamespace
    private static let hubZoomSourceID = "hubHero"
    // （§449 退役：顶栏模型选择面开关 showModel-
    // Picker 与隐藏服务商待确认 pendingHideGroup
    // 随顶栏模型胶囊整件删除——模型入口唯一收中
    // 枢、隐藏服务商整套迁中枢选择面，见 Agent-
    // HubView 与 DESIGN §449.2）

    @Environment(AppState.self) private var appState
    /// 锚点物化落盘口（§165）：store 刷新回调经它落盘
    /// （物化方 ApprovalAnchorMaterialization 用环境
    /// context，与 GoalEcho 物化同一落盘面）
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 字号档（0.43.0，A11Y-D1）：发送舱量测按档贯穿
    /// ——经 OneDayDesign 映射交给 ComposerBarLayout，
    /// 与文本视图自身 trait 档同源（量测≡排版）
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 0.20.0 恢复链：本页自此观察前后台（此前全页无
    /// scenePhase 观察——切后台杀流后回前台无人对账，
    /// 是「显示无网络」误报的生命周期半侧定因）
    @Environment(\.scenePhase) private var scenePhase
    /// R3（§295）：原生散文规格的拼装环境——全环
    /// 境值（颜色 resolve 与字号/字重档的同源读
    /// 口，与 SelectableInlineText 的 @Environ-
    /// ment(\.self) 同式）＋链接出口（原生文本委
    /// 托的 openURL 与托管形态同一环境动作）
    @Environment(\.self) private var environment
    @Environment(\.openURL) private var openURL
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]

    @State private var currentThreadID: UUID?
    /// 留痕回响拉取缓冲（P2 会话包；§229 起只作
    /// 物化输入）：进页/切线程与每轮生成落定时经
    /// OneDayBridgeClient 拉桥侧留痕账（主线全量、
    /// 旁聊按 targetId），拉成即经 TraceEchoMate-
    /// rializationRunner 物化为真条目进消息流——
    /// 呈现不再读本缓冲（回响行读条目自带快照）；
    /// 拉取失败保留旧值（见 refreshEchoTraces）
    @State private var echoTraces: [BridgeTrace] = []
    @State private var input = ""
    /// 语音输入控制器（0.36.6，§71）：端上识别、录音
    /// 条占住发送舱；文本经 onTextChange 回写 input
    @State private var dictation = DictationController()
    /// 在飞旗（§409 步 A 语义收口）：非 nil＝本轮
    /// 生成在飞、nil＝不在飞——只承载生命周期，
    /// 不再承载正文快照（生成期呈现只有 §407 占位
    /// 行；正文/思考全文只在装配器与思考累积器里
    /// 累积，落盘与落定兜底直读、不经视图状态）
    @State private var streamingText: String?
    /// 本轮首个思考增量的到达时刻（0.5.1）：落盘
    /// reasoningSeconds 的计时起点（直播思考块已
    /// 随 §409 步 A 退役，呈现侧无读者，计时口径
    /// 保留待 S3 过程行）
    @State private var reasoningStartedAt: Date?
    /// 正文分段装配器（第 93 条，OneDayCore.Stream-
    /// SegmentAssembler）：§409 起纯数据面——工具
    /// 边界封段、新段新缓冲，fullSegments/merged-
    /// FullText 喂半截落盘与落定兜底（第 93 条账
    /// 本口径不变）；封存段真值在本体内，视图侧
    /// 镜像（旧 sealedStreamSegments）已退役
    @State private var streamAssembler = StreamSegmentAssembler()
    /// §494：流式发布门（呈现节流的单点裁定，
    /// Core StreamingPublishGate）＋已发布快照
    /// 与代次——装配器只管精确累积、发布归本门，
    /// §409 步 A 拆掉的「发布」一环在此接回
    @State private var streamPublishGate = StreamingPublishGate()
    @State private var livePublishedText = ""
    @State private var livePublishGeneration = 0
    /// §494：直播行武装位——只许 driveRun 新发
    /// 轮置真（恢复轮半截条目已在屏、再挂直播
    /// 行必双份，见 liveStreamingRow 守卫）
    @State private var streamPresentationArmed = false
    /// 思考通道累积器（0.5.1 发布闸，§409 步 E 瘦
    /// 身为纯累积器）：fullText 是落盘推理文本的
    /// 源头、hasContent 喂占位行思考相判定，run
    /// 驱动起止归零
    @State private var reasoningPublishGate = StreamPublishGate()
    @State private var sendTask: Task<Void, Never>?
    /// 发件箱自动重排在飞标记（台账 154，DESIGN
    /// §336）：drain 重入闸——多触发点（回前台/网
    /// 络恢复/切线程/进页）同拍到达只跑一趟，趟内
    /// 串行逐条、await 发送任务收尾再看下一条
    @State private var outboxDraining = false
    /// §451 提交泵：在跑线程集与任务句柄（同线程串
    /// 行 POST；提交窗停止时按线程取消泵任务）
    @State private var submitPumpThreads: Set<UUID> = []
    @State private var submitPumpTasks:
        [UUID: Task<Void, Never>] = [:]
    /// §451 消费环任务（单例防重入）：按提交序逐轮
    /// 驱动当前线程已受理未落定轮次
    @State private var consumeTask: Task<Void, Never>?
    /// §451 泵内正在提交的条目集（准备/提交段在
    /// 飞）：编辑/撤回/孤儿浮现对本条让路
    @State private var pumpInFlightEntryIDs: Set<UUID> = []
    /// §451 提交工单：send/重发登记时捕获的出站形
    /// 态（进程重启后无工单的条目由泵按重发口径现
    /// 组，见 rebuiltSubmitJob）
    @State private var submitJobs: [UUID: SubmitJob] = [:]

    /// §451 提交工单（与 launchTurn 旧签名同集＋发
    /// 送打点起点：打点归工单自带，不再借全局起点
    /// 串到别条头上）
    private struct SubmitJob {
        var thread: ChatThread
        var userEntry: ChatEntry
        var text: String
        var filePayloads: [(name: String, data: Data)]
        var presetFilePaths: [String]
        var seedSnapshot: [SeedEntry]
        var context: [ChatMessage]
        var frameStartedAt: Date?
    }

    /// §451 提交结果（泵的堵/通判定面）：accepted
    /// 含「结果未知交对账」；rejected/prepareFailed
    /// 是未受理失败、堵泵；offlineParked 折回待发
    /// 巷不堵（等下一次触发）；stopped 静默收尾
    private enum SubmissionOutcome {
        case accepted
        case rejected
        case prepareFailed
        case offlineParked
        /// 限流停泊（发送失败机制包·等待门）：服务
        /// 端明示等待时长，条目折回待发、唤醒钟已
        /// 在停泊点排好，到点自动续——不是失败
        case rateLimitedParked
        case stopped
    }
    /// 本轮 run 的状态机（0.31.0）：相位与终态证据的
    /// 单一出处（Core RunTurnStateMachine），驱动见
    /// driveRun/reconcileRun。0.20.0 的切后台记账＋待
    /// 恢复账（内存版）就此退役——记账改走持久账本
    /// （AppState.runLedger），恢复不再靠「是否经历
    /// 过后台」分型：断线恒为结果未知、恒走对账
    @State private var runMachine = RunTurnStateMachine()
    /// 正在驱动/对账的 run 所属线程（呈现状态只对它
    /// 有意义；切线程时旧轮在后台任务里继续落定）
    @State private var activeRunThreadID: UUID?
    /// events 重挂的续传位（Last-Event-ID）
    @State private var lastEventSeq = -1
    /// 驱动在途标记（防 resume 与 send 双驱同一轮）
    @State private var isDrivingRun = false
    /// 已落盘的半截条目 id（落定时整段替换的名单）
    @State private var livePartialEntryIDs: [UUID] = []
    /// 终态事件携带的 output（transcript 滞后时的合
    /// 成落定兜底；failed 时是服务端说明原文）
    @State private var terminalOutputHint: String?
    /// 终态状态回执（合成落定与失败文案的证据源）
    @State private var terminalStatusHint: RunStatusResponse?

    /// 外观·聊天主题/形象大小（0.26.0）：本页观察两
    /// 键——主题变更即重渲本页（气泡/强调重新求值）、
    /// 形象档喂胶囊头像与空态形象边长。键名单一出处
    /// ＝Core AppearanceStorageKeys
    @AppStorage(AppearanceStorageKeys.chatTheme)
    private var chatThemeID = ChatThemes.defaultID
    @AppStorage(AppearanceStorageKeys.avatarSize)
    private var avatarSizeRaw = AvatarSizeTier.medium.rawValue

    /// 当前形象档（脏值回中档，与 Appearance-
    /// Preferences 同口径）
    private var avatarTier: AvatarSizeTier {
        AvatarSizeTier(rawValue: avatarSizeRaw) ?? .medium
    }

    @State private var errorMessage: String?
    /// G-03（§389）：错误横幅的诊断详情与发生时
    /// 刻——技术原文（状态码/接口名/错误码）只许
    /// 随 HermesError.diagnosticDetail 进横幅的
    /// 「详情」展开，主文案恒人话；时刻由
    /// presentError 同点记下（字面赋值点由
    /// errorMessage 变化观察补记，见 bottomBar
    /// 组装口）
    @State private var errorDetail: String?
    @State private var errorOccurredAt: Date?
    @State private var errorDetailExpanded = false
    /// 0.2.1：非错误提示条。§140 提示纪律起分档自消：
    /// 呈现状态与代号在 Core NoticePresentation，赋值
    /// 一律走 showNotice（中性 5s／重要 8s 自清）；错
    /// 误族走 errorMessage、常驻不动。发送失败机制
    /// 包（语义 5）起横幅只投影全局状况（凭据失效/
    /// 服务不可用）、无重发动作位——单条失败的呈
    /// 现与恢复全在条目行内（叹号）＋小提示，见
    /// presentSendFailure
    @State private var noticePresentation = NoticePresentation()
    @State private var noticeDismissTask: Task<Void, Never>?
    /// §119 未配模型引导卡：「先等等」点过后本次不再
    /// 显示（判定本体在 Core ModelSetupGuidance，有
    /// 任何可用模型时永不出现、生产恒不误报）
    @State private var modelSetupCardDismissed = false

    private var showsModelSetupCard: Bool {
        currentThread == nil
            && !modelSetupCardDismissed
            && ModelSetupGuidance.needsSetup(
                gatewayModels: appState.availableModels,
                providerModelTotal: appState.providerModelTotal
            )
    }

    /// 未配模型引导卡（空态处）：去设置直达服务商
    /// 管理页（pendingSettingsRoute 现成通道）
    private var modelSetupCard: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text("还没配置模型")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text("先去加一家服务商、选好模型，回来就能聊。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            HStack(spacing: OneDayMetrics.spacingM) {
                Button("先等等") {
                    modelSetupCardDismissed = true
                }
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
                Button("去设置") {
                    appState.router.pendingSettingsRoute = .models
                    appState.router.settingsSheetRequested = true
                }
                .font(.callout)
                .foregroundStyle(Palette.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OneDayMetrics.spacingM)
        .odGroup()
    }
    // （0.4.5 迁出：抽屉开合/跟手/搜索/重命名/服务端会
    // 话组状态随抽屉本体迁往 DrawerView 与壳层
    // ContentView，见 §30）
    /// 消息区是否贴近底部：决定自动跟随滚动与「回到底部」钮
    @State private var isNearBottom = true
    /// 发送贴底令牌（0.36.5，聊天审计 bug 1）：send()
    /// 的条目落盘且链接成功（条目确定留下）后递增，
    /// messageList 的 onChange 消费它执行贴底三步——
    /// send() 本体没有 ScrollViewProxy，滚动只能经
    /// 令牌通道回到列表作用域执行；链接失败回滚删条
    /// 目的分支不递增、不贴底
    @State private var sendPinToken = 0
    /// （最后一条可见事实信号与最近可见集已于 §135
    /// 退役，发送空屏诊断 A 案：回底钮显隐改几何单
    /// 源派生，可见集只余 topVisibleEntryID 一职喂
    /// 滚动锚存取，见 messageList 的可见性回调注）
    /// 贴底单一所有者记账（§135）：一切贴底请求经
    /// scrollToBottom 单口裁决（同帧合并＋全局唯一
    /// 复贴），判定在 Core BottomStickCoordinator
    @State private var stickCoordinator = BottomStickCoordinator()
    /// 落定状态机（键盘整包 R4；Core BottomSettle-
    /// Machine，五量事件源与转移在 Core 钉死）＋本
    /// 笔观察的协调者代号＋有界单发兜底任务。旧形
    /// 态 [120, 320, 640, 1100]ms 定时复核序列
    /// （症④的落定尾巴本体）整件退役；兜底任务是
    /// 评审口径留的口子——2 秒单发、只把当前读数
    /// 喂回同一判定、不循环、不自成机制（见 eva-
    /// luateSettleFallback）
    @State private var settleMachine = BottomSettleMachine()
    /// §329 行状态账本：行内展开态（推理块/工具
    /// 卡/组）与审批详情四态的跨视图单源——托管
    /// cell 重建不丢、行高合成器同步可读（.abso-
    /// lute 回喂的前提，见 ChatRowStateLedger）
    @State private var rowStateLedger = ChatRowStateLedger()
    /// §331 后台量测台（题 3 根治）：行高未就绪
    /// 时投单后台量测、回填后经发布代次重喂列表
    @State private var rowMeasureDesk =
        ChatNativeRowMeasureDesk()
    /// 2026-11-20 卡顿修复包：行描述备忘——未变
    /// 行整行复用上趟描述（喂入层增量化，见
    /// ChatNativeRowDescriptorMemo）
    @State private var nativeRowMemo =
        ChatNativeRowDescriptorMemo()
    /// §362（流畅度专项 S2）：行构建增量备忘——
    /// 未变行免 entryBase 全文哈希与 facet 扫描键
    /// 组装（见 ChatEntryRowBuildMemo）
    @State private var rowBuildMemo =
        ChatEntryRowBuildMemo()
    /// §374（换引擎步骤 1/2）：增量喂入开关
    /// （Core ChatListIncrementalFeature，缺省开；
    /// 设置页实验区同键同源）与变更集追踪器——开
    /// 时逐趟产出变更集＋行值缓存并实际交付控制
    /// 器 applyChanges（步骤 2 转正；影子账对账
    /// 保留作过渡期交叉核验），关时本视图行为与
    /// 现行逐字一致（追踪器零调用、零状态、喂入
    /// 走旧路 apply 全量对账）
    @AppStorage(ChatListIncrementalFeature.defaultsKey)
    private var chatListIncrementalEnabled = true
    @State private var feedChangeTracker =
        ChatFeedChangeTracker()
    @State private var settleGeneration: Int?
    @State private var settleFallbackTask: Task<Void, Never>?
    /// 渲染计划缓存（§135 B 案）：按键（Core Chat-
    /// RenderPlanKey）命中即复用上轮的排序＋分隔＋
    /// 成组结果，无关状态写入不再全线程重算
    @State private var renderPlanCache = RenderPlanCache()
    /// 发送帧打点（§135 D 案）：本轮发送的起手时刻
    /// ——落盘→链接、首帧复核、发送→落定三段读数经
    /// ChatDiagTrace 留痕供真机复验对读数；无在飞
    /// 发送时为 nil、不留痕
    @State private var sendFrameStartedAt: Date?
    /// 发送帧首帧复核读数是否已留痕（每轮只记一笔）
    @State private var sendFrameRestickLogged = false
    /// 最近一次实测距底（0.36.13，修法 1 落定复贴）：
    /// 与 isNearBottom 同出 onScrollGeometryChange
    /// 一路——迟滞判定消费它之外，原始读数另存一份
    /// 喂贴底后的复核（仍 >7pt 才补贴，§176 阈值
    /// 24 → 7 收紧，Core BottomSettle 钉死）
    /// §199：原始读数改存 BottomDistanceRecorder 引
    /// 用匣（见文件头注），不再走 @State 逐帧回写
    @State private var bottomDistanceRecorder =
        BottomDistanceRecorder()
    /// 离底未读计数（0.41.0 收口批，台账 H 节正修）：
    /// Core AwayUnreadCounter 记账——条目变化与可见
    /// 集变化两路喂 ingest（见 messageList 两处
    /// onChange）、发送走 noteOwnSend、切线程 resetAll；
    /// 呈现只读 count/displayText（回底钮角标）
    @State private var awayUnread = AwayUnreadCounter()
    /// （回底钮落位三轮沿革见 §124：发送区 frame 发
    /// 布链（§121）与宿主安全区推算（0.47.1）均已退
    /// 役——钮现居发送区布局流内（bottomBar 输入舱
    /// 上方一行），无跨树状态、无几何推算）

    /// 计数口径的「在底」事实：与回底钮显隐同一政策
    /// 派生（BottomFollowPolicy）——钮不显即在底，两
    /// 处判定永不分叉
    private var isAtBottomForUnread: Bool {
        !BottomFollowPolicy.showsScrollToBottomButton(
            isNearBottom: isNearBottom
        )
    }

    /// 回底钮显隐（单一出处：bottomBar 钮行的存在与
    /// 未读计数的「在底」事实共用同一派生，不许两处
    /// 各算一遍分叉）——无现线程恒不显；政策本体在
    /// Core BottomFollowPolicy
    private var showsBackToBottomButton: Bool {
        currentThread != nil
            && BottomFollowPolicy.showsScrollToBottomButton(
                isNearBottom: isNearBottom
            )
    }

    /// 未读计数喂入（条目/可见集两路共用一处，口径不
    /// 分叉）：当前线程有序条目 id 全表＋在底事实
    private func feedAwayUnread() {
        awayUnread.ingest(
            entryIDs: currentThread?.sortedEntries.map(\.id) ?? [],
            isAtBottom: isAtBottomForUnread
        )
    }
    /// 演示模式自动开流只跑一次（演示态展示流式效果用）
    @State private var demoStreamStarted = false
    /// 0.2.1 附件与键盘：待发附件、三种选择器开关、输入焦点
    @State private var attachments: [PendingAttachment] = []
    /// 基础止血包（P4）：待发附件按线程分格暂存——
    /// attachments 只持当前线程的工作集，切线程时整
    /// 格存回/取出（Core ThreadBoundStash），附件不
    /// 许再跟着人串到别的会话里呈现或被发送
    @State private var attachmentStash =
        ThreadBoundStash<[PendingAttachment]>()
    /// 落地态（当前无线程）附件格的固定键：落地页选
    /// 的附件不属任何会话，用本键单独收纳、回到落地
    /// 态时原样恢复，不与任何真线程 id 相撞
    private static let landingAttachmentStashID =
        UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    /// 基础止血包（P1）：上传失败轮次的文件载荷暂存
    /// （条目 id → 载荷）——失败条目点重发时补传这批
    /// 文件；同一次运行内的快速通道，进程级持久真
    /// 源是 §237 的磁盘暂存（stagedSendStore）——本
    /// 格未命中时按条目 id 回磁盘重建，进程被杀后
    /// 重发不许退化成纯文本（条目已落盘的远端路径
    /// 在场时优先走路径、两格都不经）
    @State private var failedFilePayloads:
        [UUID: [(name: String, data: Data)]] = [:]
    /// §407（预排版步骤 1·预定高）：本会话亲手发
    /// 出的条目 id 集（send/编辑重发两处登记）——
    /// nativeEntryRow 对集内用户行在入列首趟就地
    /// 同步量测（measureNow），入列即确定终态高、
    /// 不走「兜底 120→后台回填换高」的临界路；
    /// 历史行不入集（冷开长会话全表同步量测会把
    /// 成本压回主线程、正是量测台要避的）。集随
    /// 视图生命周期、量级＝本会话发送数
    @State private var sessionSentEntryIDs:
        Set<UUID> = []
    /// §237（基础正解批 P1）：待发文件载荷的持久暂
    /// 存口——发送起手即按条目 id 落盘（文件名＋字节
    /// ＋清单原子换入），失败/待发重发时凭条目 id 重
    /// 建；上传全成并写回远端路径后删除
    private var stagedSendStore: StagedSendAttachmentStore {
        StagedSendAttachmentStore.defaultStore()
    }
    /// 发送失败机制包：退避/等待门唤醒钟——退避只
    /// 有闸没有钟是弱环 B3（到点靠偶然触发），本钟
    /// 由提交泵在判退避/停泊时排下、到期踢泵续发；
    /// 只留最早一记（更早的到期点后排者不覆盖）
    @State private var outboxWakeTask: Task<Void, Never>?
    @State private var outboxWakeAt: Date?
    /// 发送失败机制包：App 启动排空发件箱的一次性
    /// 标记——触发源正确集合（语义 4）里「进/切线
    /// 程」只许对账、不许触发提交轴重投，drain 只
    /// 在启动首拍与回前台/网络恢复走
    @State private var launchDrainedThreadIDs: Set<UUID> = []
    /// 基础止血包（P7）：本轮正处文件上传段的事实位
    /// ——等待呈现据此说上传中、不再冒充生成中
    @State private var isUploadingFiles = false
    /// §237（基础正解批 P7）：本轮上传的真实聚合进
    /// 度（0...1）——源头是 URLSession 实报的已发送
    /// 字节（HermesClient 带进度版上传＋Core 聚合
    /// 器），非上传段为 nil；呈现只读它显示百分比，
    /// 不许任何地方再拿菊花冒充进度
    @State private var uploadProgressFraction: Double?
    /// 聊天可靠性包：发送准备失败被保留的待发条目，
    /// 其附件在同一次运行内按条目 id 暂存供点按重
    /// 发；§237 起发送起手已同步落磁盘暂存，进程重
    /// 启后本格为空时由 resendPending 回磁盘重建文
    /// 件载荷（图片仍走条目本体落盘数据），不再退
    /// 化为纯文本
    @State private var pendingResendAttachments:
        [UUID: [PendingAttachment]] = [:]
    // 0.36.23 起选图多选（用户 03:02 点题）：绑数
    // 组、一次可选多张；旧单 PhotosPickerItem 绑定
    // 天然单选，数据侧 attachments 本就支持多个
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    // §147 附件面板改版：「+」改开底部附件面板
    // sheet（旧浮窗小卡 Menu 退役）；视频走独立
    // PhotosUI 选图器（视频过滤、与图片选图器分开
    // 两套绑定，互不串扰）
    @State private var showAttachPanel = false
    /// §317：面板行动作的收起后接力槽——afterAttach-
    /// PanelDismiss 只登记、sheet 的 onDismiss（收起
    /// 真完成信号）才执行（废 §147 固定 450ms 睡眠
    /// 竞速，见 afterAttachPanelDismiss 注）
    @State private var attachPanelPendingAction:
        (() -> Void)?
    /// §317：文件选择器状态旗——与相机行 showCamera
    /// 同制，DocumentPickerView（representable）经
    /// fullScreenCover 由框架排队呈现（命令式文件桥
    /// 退役，见 DocumentPickerView 头注）
    @State private var showDocumentPicker = false
    // §303（A-08 收口）：面板定高改走呈现控制器
    // custom detent 单源求解（见 sheet 本体注），
    // §152 的内容实测高状态与 §154 的宿主真高回
    // 写随量测回路一并退役、本页不再持有任何面
    // 板高度状态
    // §186（2026-11-12，承载换代）：输入舱顶→窗口底
    // 距离的实测回报（ComposerGuideHost 在布局拍回
    // 写）——消息列表底 contentMargins ＝本值＋
    // spacingS（§176 单点边距的现行落点，见列表侧
    // 注）。首报到达前以 168 兜底（现行形态静止总量
    // 的同档近似：坞 83＋舱高约 77＋边距 8），host
    // 首个布局拍即以实测覆盖、不留陈值
    /// 键盘几何单一快照（键盘整包 R1，2026-11-13；
    /// 值类型在 Core KeyboardGeometrySnapshot）：
    /// 列表底留位与坞显隐自此只读本快照——键盘顶
    /// 与动画参数由键盘通知在事件拍直写（见 mes-
    /// sageList 的 WillChangeFrame 订阅），栈高/坞
    /// 顶由 ComposerGuideHost 的离散回报喂入，窗
    /// 口高随本页根几何同步。种子（874/791/105）
    /// 与 composerBottomSpace 的 168 同纪律：本机
    /// 型同档近似、首个布局拍即被实测覆盖。
    /// composerBottomSpace 自此降级：只余 A3 流式
    /// 跟随的结算拍触发与诊断读数两职，不再进留
    /// 位公式（D2：回报链退出控制环）
    @State private var kbSnapshot = KeyboardGeometrySnapshot(
        windowHeight: 874, dockTopInWindow: 791,
        pocketHeight: 105
    )
    /// R1（修正）：键盘帧更新包的收件槽——由当前
    /// 在场面的控制器（唯一解析点）在键盘事件拍
    /// 直写（帧顶已转窗口坐标），本页 onChange
    /// 以其动画参数原值整包写进快照（见 body 根的
    /// onChange(kbFrameUpdate)）。解析点按面收口：
    /// 旧面/gen3 面＝ComposerGuideHost 控制器，
    /// 原生面＝ChatRootViewController（§302 同源
    /// 收口）——三面互斥在场、同一时刻只有一个解
    /// 析点在写，快照本体恒一份。首版由本页 .onRe-
    /// ceive 自行解析通知：屏幕坐标原值与快照窗口
    /// 坐标不重合、锚恒偏——解析自此不归本页
    @State private var kbFrameUpdate: KeyboardFrameUpdate?
    /// §195：窗口顶安全区实测（ComposerGuideHost 在
    /// 布局拍回写；种子 62＝本机型不变量、首个布局
    /// 拍即被实测覆盖，与 composerBottomSpace 的
    /// 168 种子同纪律）——消息列表顶 contentMar-
    /// gins 的唯一顶距来源（＋顶簇实高）。顶簇落位
    /// 本身不读本值（由 TopBarGuideHost 在 UIKit
    /// 侧直读窗口），本值只管列表留位记账
    @State private var windowTopSafeInset: CGFloat = 62
    /// §195：顶簇实高（TopBarGuideHost 回写；种子
    /// 60＝顶栏单行高、进展胶囊出现/消失随实测跟进）
    @State private var topBarHeight: CGFloat = 60
    /// §321：顶簇底缘窗口坐标（TopBarGuideHost 以
    /// 活帧 convert 回写；种子 0＝未量得，新面顶
    /// inset 喂入未量得时回落 §195 相加口径、量得
    /// 后认本值单源——列表顶留位与顶簇真实底边
    /// 由构造恒等，不再靠两个独立种子数相加对齐）
    @State private var topClusterBottomInWindow: CGFloat = 0
    @State private var videoItems: [PhotosPickerItem] = []
    @State private var showVideoPicker = false
    // 文件选择自 0.36.31 起走 UIKit 桥 Document-
    // PickerBridge 命令式呈现，不再有 SwiftUI 呈现
    // 状态（旧 showFileImporter 随 .fileImporter
    // 一并退役，见 attachButton「选文件」项）
    /// 0.2.8 拆桥（DESIGN-V4 §12）：焦点不再经 @FocusState
    /// 把关——本状态只是 delegate 回调的观察回写（当前无
    /// 视图据它分支，留作事实通道）；程序化收起/聚焦经
    /// composerFocusHandle 直达文本视图本体
    @State private var composerFocused = false
    @State private var composerFocusHandle = ComposerFocusHandle()
    /// §213：聊天列表 UIScrollView 本体的交接句柄
    /// （与 composerFocusHandle 同式被动登记匣）：
    /// 列表内容栈的登记锚上行登记本体，两宿主据此
    /// 把滚动边缘效果注册到各自覆盖容器（见
    /// ScrollEdgeRegistration）
    @State private var listScrollHandle = ChatListScrollViewHandle()
    @State private var nativeHandle = ChatNativeListHandle()

    /// 当前面命令分发（§291 收口；§374.9 步骤 6
    /// 再收口）：旧承载退役后在场面恒为原生面——跟
    /// 随/落定/锚恢复链只经本组分发器下达原生句柄，
    /// 链本体不为承载再分叉（分发器壳保留、调用点
    /// 不动）
    private func surfaceScrollToBottom(animated: Bool) {
        nativeHandle.scrollToBottom(animated: animated)
    }

    private func surfaceCaptureAnchor() -> ChatListAnchor? {
        nativeHandle.captureAnchor()
    }

    private func surfaceRestore(_ anchor: ChatListAnchor) {
        nativeHandle.restore(anchor)
    }

    private func surfaceScrollToEntry(
        _ id: UUID, animated: Bool
    ) {
        nativeHandle.scrollToEntry(id, animated: animated)
    }

    /// 搜索落点分发（台账 150）：原生面收敛式落
    /// 点（多次重滚＋漂移容差）
    private func surfaceFocusEntry(_ id: UUID) {
        nativeHandle.focusEntry(id)
    }
    /// §247（换代包 4）：流式呈现开关（Core Chat-
    /// StreamingFeature，缺省 true＝块级增量新
    /// 路；关＝流式行回 TokenFlow 逐词渐显旧路，
    /// 回滚口、包 6 清理）与落定行键映射（流式行
    /// 键→落定条目的同键沿用记账，会话内不落盘）
    @AppStorage(ChatStreamingFeature.defaultsKey)
    private var gen4StreamingEnabled = true
    /// §494：打字动画开关读口（设置→外观写、本
    /// 页直播行入场计划读；Core StreamingType-
    /// writerFeature 单源，§409 后一度无消费方）
    @AppStorage(StreamingTypewriterFeature.defaultsKey)
    private var typewriterEnabled = true
    /// 反应浮排开关（DESIGN §343；Core ChatReactions-
    /// FloatingBarFeature 单一事实源，缺省开）：设置
    /// →外观→回复呈现写、本页 messageMenu 读；关＝
    /// 长按回 0.50.80 系统菜单子菜单形态
    @AppStorage(ChatReactionsFloatingBarFeature.defaultsKey)
    private var floatingBarEnabled = true
    /// AI 反应开关（DESIGN §432；Core ChatReactions-
    /// AISelfFeature 单一事实源，缺省开）：设置→外
    /// 观→回复呈现写、本页角标判定读；关＝角标只在
    /// 本机隐藏（数据不删、重开全量回来）。翻转经
    /// nativeRowStyleKey 折入行修订，行高预留同步
    /// 失效重算（快照侧同读本键，见 ChatEntry-
    /// HeightSnapshot.aiSelfReactionsEnabled）
    @AppStorage(ChatReactionsAISelfFeature.defaultsKey)
    private var aiSelfReactionsEnabled = true
    /// 反应浮排会话（一次长按一份；nil＝无浮排）
    @State private var reactionBarSession: ReactionBarSession?
    /// §471 浮排动画三段状态（参数全走 Reaction-
    /// BarMotion＝Exyte 原文）：背景／快照／药丸卡
    /// 分别驱动入场，收起逆序；dismissing 防收起
    /// 途中重入（点按连发不双摘会话）
    @State private var reactionBarBgShown = false
    @State private var reactionBarSnapshotShown = false
    @State private var reactionBarChromeShown = false
    @State private var reactionBarDismissing = false
    @State private var streamSettleMap = StreamingSettleMap()
    /// 0.6.0：通知 sheet（顶栏铃铛点开，总览桥驱动）
    @State private var showNotifications = false
    /// D9：对话内查找状态
    @State private var showFind = false
    @State private var findQuery = ""
    /// §503：命中集＋当前下标收进 Core ChatFind-
    /// Session 状态机（重算/翻页的落点目标由它返
    /// 回、视图层一处赋值）；旧 findMatches/find-
    /// CurrentIndex 两散状态与只写不读的 findScroll-
    /// Trigger 死触发器一并退役（审计定因：触发器
    /// 全仓无消费者、算完命中列表纹丝不动）
    @State private var findSession = ChatFindSession()
    /// §503：查找栏自己的焦点句柄（打开即聚焦、
    /// 键盘升起；不借 composer 的焦点基建）
    @FocusState private var findFieldFocused: Bool
    /// §503：查找补窗的在飞令牌与已猎取键（线程＋
    /// 查询）——同键只猎一次、新猎取置新令牌旧者
    /// 作废（与全局链 searchHuntToken 分开记账，
    /// 两条链互不作废）
    @State private var findHuntToken: UUID?
    @State private var findHuntedKey: String?
    /// D9 补全：查找命中高亮的条目 id（§503 起真
    /// 赋值：落点时置位、2.5 秒后自动清，与全局落
    /// 点链 anchorHighlightEntryID 同口径）
    @State private var findHighlightEntryID: UUID?
    /// 锚点点亮的条目 id（§165）：点达锚定行时置位，
    /// 行底色以 Palette.primaryTint 点亮、2.5 秒后清
    /// （沿 §123 枢纽聚焦同手法）；消费锚点请求的
    /// Task 持有清零，不叠加多行点亮
    @State private var anchorHighlightEntryID: UUID?
    /// 台账 161：搜索落点窗口猎取的在飞令牌——新猎
    /// 取置新令牌、旧猎取据令牌作废（与线程切换守
    /// 卫叠用，防迟到的窗口落进别的线程）
    @State private var searchHuntToken: UUID?
    /// 台账 148：NEW 未读分界线的水位店与本次观看
    /// 的定格锚——打开线程时以水位解析一次锚（见
    /// refreshUnreadAnchor）、随即推进水位，锚在
    /// 本次观看内不动、新消息到达不移位
    @State private var readMarkStore = ThreadReadMarkStore()
    @State private var unreadAnchorEntryID: UUID?
    /// 0.4.0（§3.4）：服务端会话导入进行中的 id（防重复
    /// 触发并发导入同一条会话）
    @State private var importingSessionID: String?
    /// §237（基础正解批 P6）：分页导入已落盘条数——
    /// 等待卡据实显示（第一页落盘后即从首屏切换走、
    /// 本数只在首屏前短暂在场），不许整表载入后才
    /// 有第一个数字
    @State private var importingLoadedCount: Int?
    /// 基础止血包（P6）：导入失败的重试上下文（会话
    /// id＋频道出处）——输入舱上方留一条重试行，点按
    /// 以原出处重走导入；导入成功/发起新导入/用户关
    /// 掉即清
    @State private var importRetryContext:
        (sessionID: String, channelID: String?)?
    /// §331（根治版包 2）：历史回补/种子同步的在飞
    /// 任务登记（按线程 id）——同线程同时只许一轮，
    /// 调度入口先查登记再起任务，落定自动注销
    @State private var historyBackfillTasks:
        [UUID: Task<Void, Never>] = [:]
    @State private var seedSyncTasks:
        [UUID: Task<Void, Never>] = [:]
    /// （showSessionInfo 已于 0.20.0 第五条随会话名次
    /// 行一并拆除：聊天页不再有会话详情入口，管理页
    /// ServerSessionRow 承接）
    /// 0.4.1：长按「回复」待发送的引用（值快照，不持
    /// SwiftData 对象）；发送/取消/切换线程时清除
    @State private var pendingQuote: MessageQuote?
    /// 0.7.0（M4 分流动作）：「在旁聊里接着问」的引用种子
    /// 暂存——新建旁聊的线程切换会触发 onChange 清引用，
    /// 种子经此暂存一道、切换落定后转入 pendingQuote
    @State private var pendingForkQuote: MessageQuote?
    /// 0.7.0：当前待发送引用是否为分流种子（引用条文案分流）
    @State private var pendingQuoteIsFork = false
    /// D3（DESIGN §352）：编辑已发消息的武装态——只
    /// 钉目标条目 id＋服务端行 id；target 起条目名
    /// 单在发送时刻按 sortedEntries 现算（Rewind-
    /// TurnSlicing 单点切分），不在此持名单防过期
    @State private var editSentTarget: EditSentTarget?
    /// §414（修复包一·路三）：未发送条目原位编辑的
    /// 武装目标——editUnsentEntry 只装载发送舱并记
    /// 目标 id、不删原条目；send() 在目标所在线程
    /// 发送时把新内容写回原条目本体再走发件箱重
    /// 发口（performUnsentEditSend）
    @State private var unsentEditTargetID: UUID?
    /// 武装时文件面是否由发送舱完整代表：文件载
    /// 荷可回载（或条目本无远端文件）为 true；文
    /// 件已上传、载荷不在本机而远端路径在场时为
    /// false——该形态下文件面不归编辑管辖、远端
    /// 路径原样保留
    @State private var unsentEditFilesRepresented = false
    /// D3 破坏性确认的待发稿快照：非末轮编辑点发送
    /// 时暂存——确认期间发送舱原样不动，确认后经
    /// performEditSend 发出、取消即弃
    @State private var pendingEditSend: EditSendDraft?
    /// D3/D2 乐观隐藏集（仅显示层，renderPlan 消
    /// 费）：rewind 在飞期间 target 起条目（D3）/
    /// 本轮助手段（D2）不呈现，存储一字不动；成→
    /// 真删后清空、败→直接清空全复原
    @State private var rewindHiddenEntryIDs: Set<UUID> = []
    /// D3/D2 的 rewind 驱动任务（发送管线另管
    /// sendTask，本任务只辖 rewind 段与回滚）
    @State private var rewindTask: Task<Void, Never>?
    /// §208：动态讨论的待发送引用（FeedPostQuote 值
    /// 快照）——与 pendingQuote 共用发送舱同一引用
    /// 槽位：至多一个在场，后入覆盖先入。同守引用
    /// 生命周期：发送/点 ✕/切换线程即清，永不落盘、
    /// 不进草稿账。
    /// §210 改挂：真身在 AppState.pendingFeedQuotes-
    /// ByThread 按线程寻址，本处只是当前线程的派生
    /// 读写视图（读写点全数沿用：槽位呈现/✕/begin-
    /// Reply 挤掉/send 快照与失败回滚）——状态不再
    /// 是视图本地 @State，视图重建/重现不丢、切线
    /// 程由 onChange 按离开线程定点作废（见该处）
    private var pendingFeedQuote: FeedPostQuote? {
        get {
            currentThreadID.flatMap {
                appState.pendingQuotes.feedQuotesByThread[$0]
            }
        }
        nonmutating set {
            guard let currentThreadID else { return }
            if let newValue {
                appState.pendingQuotes.feedQuotesByThread[currentThreadID] =
                    newValue
            } else {
                appState.pendingQuotes.feedQuotesByThread
                    .removeValue(forKey: currentThreadID)
            }
        }
    }
    /// §219：点子／文件待发引用（SourceQuote 统一载
    /// 荷的 .idea／.file 两族）——与 pendingFeedQuote
    /// 同型：真身在 AppState.pendingSourceQuotesBy-
    /// Thread 按线程寻址，本处是当前线程的派生读写
    /// 视图（槽位呈现/✕/beginReply 挤掉/send 快照与
    /// 失败回滚读写点沿用）。与消息引用、动态引用
    /// 共用发送舱同一槽位：至多一个在场、后入覆盖
    /// （跨族覆盖经两处呈现侧收口函数交叉清理两表
    /// 兑现，见 applyPendingFeedQuoteIfNeeded 与
    /// applyPendingSourceQuoteIfNeeded）
    private var pendingSourceQuote: SourceQuote? {
        get {
            currentThreadID.flatMap {
                appState.pendingQuotes.sourceQuotesByThread[$0]
            }
        }
        nonmutating set {
            guard let currentThreadID else { return }
            if let newValue {
                appState.pendingQuotes.sourceQuotesByThread[currentThreadID] =
                    newValue
            } else {
                appState.pendingQuotes.sourceQuotesByThread
                    .removeValue(forKey: currentThreadID)
            }
        }
    }
    /// 0.7.0（M1 轻保活）：列表首个可见条目 id（滚动锚
    /// 记录用，由 onScrollTargetVisibilityChange 回写）
    @State private var topVisibleEntryID: UUID?
    /// 0.4.1：长按「选择」的纯文本 sheet 载荷
    @State private var selectionPayload: SelectionPayload?
    /// §330：原生面 UIKit 行菜单「分享」的分享单
    /// 状态口（见 MessageSharePayload）
    @State private var messageSharePayload: MessageSharePayload?
    /// §152 的选区在场记账已迁 ChatRowStateLedger
    /// （141/142 根治：选区永不进 @State/行修订，
    /// 见 noteTextSelection 与账本注）
    /// 0.8.0（P1 富内容）：图片全屏查看与文件 QuickLook
    /// 预览的呈现载荷；流式工具卡列（累积完成即入列、
    /// 本轮收尾落盘，见 driveRun）
    @State private var imageViewerSession: ImageViewerSession?
    /// §125：文件牌点开统一进中间页（FileOpenView
    /// sheet），旧「点牌直达 QL（filePreviewItem）/
    /// 不可预览直落分享单（fileShareItem）」两件套呈
    /// 现状态退役——分享单改由中间页内的动作触发
    @State private var fileOpenTarget: FileOpenTarget?
    /// §452.6：聊天侧 QuickLook 直达呈示项
    @State private var chatQuickLookItem: ChatQuickLookItem?
    /// §452.6：聊天侧兜底页呈示目标
    @State private var chatFallbackTarget: FileOpenTarget?
    @State private var liveToolCards: [ToolCard] = []
    /// 直播区事件序标记（0.36.10，诊断 D3-10）：思考/
    /// 工具/正文按首达顺序记位，渲染层（liveZone）据
    /// 此交错呈现——旧形态恒「卡列在前、思考正文在
    /// 后」，与事件真实先后倒序
    @State private var liveOrder: [LiveOrderItem] = []

    private enum LiveOrderItem: Equatable {
        case reasoning
        case text
        /// 已封存正文段（第 93 条）：下标＝sealed-
        /// StreamSegments 的段序；封段时由 .text 标
        /// 记原位换成此标记（位置即段的事件位），新
        /// 段的 .text 标记在新段首增量到达时另记
        case sealedText(Int)
        case tool(String)
    }

    private func noteLiveOrder(_ item: LiveOrderItem) {
        if !liveOrder.contains(item) {
            liveOrder.append(item)
        }
    }

    /// 0.2.7：发送舱玻璃直接施加在行本体上，0.2.4–0.2.6 的
    /// GlassEffectContainer＋union 撤销（§11：容器在新承载
    /// 下不再承担布局，且 Session 219 忌玻璃叠玻璃）
    /// 发送舱实测高（0.3.5，§20）：由卡层（composer-
    /// Card，0.36.19 前为 composerRow）的 onGeometry-
    /// Change 在布局周期内回写，只喂玻璃圆角的连续半
    /// 径函数（ComposerLayout.cornerRadius）。0.36.19
    /// 起量整卡高（引用块并入后计入舱高）
    /// 0.2.6–0.3.4 的离散形态状态 composerMultiline 已
    /// 撤销——它由 Layout 内异步回写、滞后布局一拍，是
    /// 0.3.4 真机回车重影的定因（见 §20.1）
    @State private var composerCapsuleHeight: CGFloat = 46
    // （0.6.1 删残：composerBarHeight 随底缘 E11 带删
    // 除失去唯一消费者——它当年由 bottomBar 实测回写
    // 只喂带长计算，带删后状态与回写一并撤）
    // （0.3.8 删残：tabBarZone 本地副本随抽屉钉底删除——
    // 它唯一的用途是抽屉面板底部占位，第 22 条已废）

    /// 当前线程（0.27.0 硬化）：只认 currentThreadID
    /// 精确命中（Core CurrentThreadResolution）——旧
    /// 「失配静默回落最近活跃线程」就此删除：显示与
    /// 发送落点不许悄悄换到另一条线程，失配即空态、
    /// 发送在 ensureThread 处显式报错
    private var currentThread: ChatThread? {
        guard let resolved = CurrentThreadResolution.resolve(
            currentID: currentThreadID, existingIDs: threads.map(\.id)
        ) else { return nil }
        return threads.first { $0.id == resolved }
    }

    /// 0.7.0：当前线程是否钦定主线——回告卡入线判定
    /// （判定纯函数在 Core；0.7.0 起同用此口径的标题行
    /// 「旁聊」标识已于 0.19.0 随用户点名删除）
    private var isCurrentMainThread: Bool {
        guard let thread = currentThread,
              let mainID = appState.sessionLedger.mainThreadID else { return false }
        return SideChatClassifier.zone(localThreadID: thread.id, mainThreadID: mainID) == .main
    }

    private var isStreaming: Bool { streamingText != nil }

    // MARK: - §158 隐藏服务商（§449 迁中枢选择面）

    /// （分流/确认/落账三件已随顶栏选择面退役整套
    /// 迁入 AgentHubView 的中枢选择面——全 App 只
    /// 剩那一处，口径逐字不变，见 DESIGN §449.2）

    /// 本会话模型账的取键入参（§227 账合一派生）：
    /// 胶囊读/写与枢纽共用 Core SessionModelAccount
    /// 一条派生链——线程实际绑定优先，钦定主线未绑
    /// 定时回落 SideChatStore 的钦定 id（派生缓存、
    /// 非独立事实源）；不许再在各面内联拼这条回落链
    private var currentModelAccountIDs:
        (serverSessionID: String?, threadID: UUID?)
    {
        let thread = currentThread
        return SessionModelAccount.accountIDs(
            threadServerSessionID: thread?.serverSessionID,
            threadID: thread?.id,
            isMainThread: thread != nil
                && thread?.id == appState.sessionLedger.mainThreadID,
            mainServerSessionID: appState.sessionLedger.mainServerSessionID
        )
    }

    /// 本会话的执行选择（§153 B2）：顶栏触发器、发送
    /// 链、枢纽模型区共用此一口——显示与执行同源。
    /// 会话键：线程的服务端会话 id 优先（主线读
    /// SideChatStore 的主线 id），未链接时线程 id，
    /// 无线程（空态）落主线缺省键
    private var currentChoice: ChatModelChoice {
        let ids = currentModelAccountIDs
        return appState.sessionModelChoice(
            serverSessionID: ids.serverSessionID,
            threadID: ids.threadID
        )
    }

    /// 本会话选择的写入（§153）：与 currentChoice 同键
    private func selectCurrentChoice(_ choice: ChatModelChoice) {
        let ids = currentModelAccountIDs
        appState.selectSessionModel(
            choice, serverSessionID: ids.serverSessionID,
            threadID: ids.threadID
        )
    }

    /// 顶栏展示的模型名（§153 B4）：恒为本会话实际执
    /// 行值的显示名——别名先经单源归一（canonicalID）
    /// 再取名单源显示名，与逐请求发出的模型同物同名；
    /// 服务端默认（defaultModel）是设置页管理面口径，
    /// 不冒充本会话执行值
    private var displayModelName: String {
        let model = currentChoice.model
        return ModelDisplayNames.displayName(for: model) ?? model
    }

    var body: some View {
        chatScaffold
        .onAppear { handleChatAppear() }
        // 0.7.0（D2 回告）：总览快照随前台 30 秒轮询换新
        // 时顺带拉新通知——回告卡与铃铛/通知 sheet 读
        // 同一份通知状态，不另开轮询
        .task(id: overviewStore?.snapshot?.generatedAt) {
            if let overviewStore {
                // §426（缺陷二）：本页正打开的会话作
                // 为前台会话传给消账判定——本会话的
                // 运行终态已在聊天里当面呈现，其通
                // 知不再弹卡/占角标（记录保留）
                await overviewStore.loadNotifications(
                    appState: appState,
                    foregroundServerSessionID:
                        currentThread?.serverSessionID,
                    // §454：本机线程会话链一并传给入
                    // 账判定——前台会话的正常完成不
                    // 进铃铛（三级），失败照旧在账
                    userSessionIDs: ChatSessionScope
                        .userSessionIDs(from: modelContext)
                )
            }
        }
        .task {
            await startDemoStreamIfNeeded()
        }
        // §232：乐观删除启动续跑——盘上待删队列逐
        // 条重演隐藏并重跑后台删除（进程被杀/重启
        // 的兜底；已落定条经回查自然收口，续跑失败
        // 同样恢复＋提醒）。协调器内在飞去重＋队列
        // 排空后为空操作，重复触发无副作用
        .task {
            appState.sessionDeletions.resumePending(
                appState: appState, modelContext: modelContext
            )
        }
        // §232：乐观删除最终失败的恢复提醒——协调
        // 器置位即经聊天页提示条呈现（重要档），消
        // 费后清位防重报（冷启动已置位者亦在此消费）
        .onChange(
            of: appState.sessionDeletionFailureNotice
        ) { _, notice in
            if let notice {
                if !noticePresentation.isPresenting {
                    // OB-I3（§391）：删除失败是需要人知
                    // 道的失败——常驻、手关才退场
                    showNotice(notice, tier: .persistent)
                }
                appState.consumeSessionDeletionFailureNotice()
            }
        }
        .task {
            await appState.refreshModelCatalog()
        }
        // §237 P1：待发暂存清扫——条目已删除的暂存目
        // 录随聊天页首启清掉，防只进不出积压；仍在
        // 的条目（含失败/待发待重发）一律保留
        .task {
            let validIDs = Set(
                threads.flatMap { $0.entries }.map(\.id)
            )
            try? stagedSendStore.prune(keeping: validIDs)
        }
        // 身份名全局解析（0.6.1）：聊天页是默认格、首
        // 先出现，在此触发一次（AppState 内幂等）；胶
        // 囊/抽屉/活动页三处显示名共用解析结果
        .task {
            await appState.resolveIdentityNameIfNeeded()
        }
        // 0.6.0（蓝图 §4 一期）：枢纽内容曾转正为活动格
        // （AgentHubView 的 .activity 模式，全 App 只此
        // 一份实现）；**0.17.0（真机五修⑤，用户点名）：
        // 活动格撤销、枢纽回归 sheet**——身份胶囊点按与
        // 回告卡点按开下方 showHub sheet（四段原样、枢
        // 纽自带导航栈），换模型仍走胶囊内模型段 Menu
        // （见 modelMenu）。本 sheet 是顶栏铃铛的通知面
        // （总览桥驱动）
        // §123（H2）：通知条目点达对象时先关本 sheet、
        // 再开枢纽——两个呈现不能同帧抢，枢纽开启在此
        // onDismiss 接力（落点字段已由通知行落 AppState）
        // §165：锚点落点（approvalAnchorRequest 在位）不
        // 开枢纽——落点在原对话里，本 sheet 关闭后由本
        // 页消费请求切线程定位（onChange/onAppear 双触
        // 发，此处补第三路防 sheet 关闭吞掉变更）
        .sheet(isPresented: $showNotifications, onDismiss: {
            if appState.router.approvalAnchorRequest != nil {
                consumeApprovalAnchorRequest()
            } else if appState.router.hubDestinationRequest != nil {
                appState.router.hubOpenRequested = true
            }
        }) {
            if let overviewStore {
                NotificationsView(store: overviewStore)
                    // §166：底部大面板——.large detent＝上缘
                    // 留距的大 sheet 口径（原型同），内容内
                    // NavigationStack 承载列表→详情推入
                    .presentationDetents([.large])
            }
        }
        // 0.17.0：枢纽 sheet（承载与 0.6.0–0.16.0 的活动
        // 格本体逐字一致：同一 AgentHubView .activity＋
        // 审批终态回调刷新总览桥、顶栏角标不等下一轮轮
        // 询——原 ActivityView 包装层随活动格一并退役）
        // 0.36.22（枢纽页对齐包）：呈现改整页 full-
        // ScreenCover（用户学 Muse 智能体页：整页进、
        // 左边缘右滑回、✕ 关闭）——内容与回调原样；呈
        // 现机制取舍（cover 而非导航推入）见 §89
        // §155（HUB-1）：呈现改 .sheet 全量形态（七段＋
        // 模型常驻区、默认活动段），.activity 四段形态
        // 退役无入口；审批终态回调保留（裁决自聊天就地
        // 卡发生、经共享 store 触发同一回调）
        // §217（2026-11-13，用户拍板对齐 Muse 枢纽
        // 录屏）：呈现改系统 sheet 卡片式——大 detent
        // 圆角卡浮起（初态四周留边、后景压暗、落定近
        // 全屏），关闭反向回缩淡出，动画全走系统弹簧
        // （hubSheetPresentation 一处收口）；fullScreen-
        // Cover 的硬切感就此退场。枢纽内自带 sheet（分
        // 享/模型/档案编辑）是嵌套呈现、照常工作；左
        // 缘右滑与 ✕ 关闭口径不变
        // §434（2026-11-24，用户亲点）：呈现改导航
        // push＋系统 zoom 转场——§217 的 sheet 卡片
        // 式（hubSheetPresentation）就此退役；宿主
        // NavigationStack 在 ContentView 聊天格（本
        // 页在栈内注册目的地）。结构归位包「枢纽不
        // 读当前会话」的口径由本节按用户新令覆盖：
        // 中枢「选择模型」入口注入本会话模型账
        // （§153 同组件同数据源），枢纽本体仍不自
        // 拉模型账、只消费注入包
        .navigationDestination(isPresented: $showHub) {
            hubDestination
        }
        // 0.36.6：语音输入权限预备页（问前先讲用途，
        // 续编 S1–S4；点麦克风且权限未定时才出现）
        .sheet(isPresented: $dictation.showPrep) {
            DictationPrepSheet(controller: dictation)
        }
    }

    /// body 链前段（基视图＋首启 task 群）抽为
    /// 独立属性：整链单表达式令类型检查器超时
    /// （CI 三轮实证 2026-11-20），拆段各自求解；
    /// 修饰顺序与语义逐字不变
    private var chatScaffold: some View {
        // 0.4.5（§30）：抽屉覆盖层退役——抽屉承载已提
        // 到壳层（ContentView 根的推式结构），本页只剩
        // 聊天主面本体；旧结构里的 GeometryReader/ZStack
        // /drawerOverlay 与「开抽屉藏底栏」的 toolbar-
        // Visibility 绑定（0.4.1 第 8 修）一并撤销：推
        // 式下底栏坞是页卡的一部分、随卡同走，不需要
        // 也不应该再隐藏（口径变化见 §30）
        chatSurface
        // 基础止血包（P6）：服务端会话导入的等待呈现
        // ——旧口径 importingSessionID 只作防重入闸、
        // 无任何视图消费，导入期间页面零反馈（停在
        // 旧对话干等、弱网像点不动）；导入中挂一张安
        // 静的载入卡（不挡操作、尺寸恒定）
        .overlay {
            if importingSessionID != nil {
                importingOverlay
                    .transition(.opacity)
            }
        }
        // R1（修正）：键盘帧更新包到达即整包入快照
        // ——动画以通知参数原值推进（曲线映射见
        // keyboardSnapshotAnimation）；快照的窗口
        // 高由宿主回报喂入（window.bounds 真值），
        // 本页根几何高是页内可用高、不是窗口高，
        // 不许再喂（首版误喂 729≠874、留位整体偏
        // 移，验收轮实测坐实）
        .onChange(of: kbFrameUpdate) { _, update in
            guard let update else { return }
            withAnimation(
                keyboardSnapshotAnimation(
                    duration: update.duration,
                    curveRaw: update.curveRawValue
                )
            ) {
                kbSnapshot.keyboardTopInWindow =
                    update.topInWindow
                kbSnapshot.animationDuration =
                    update.duration
                kbSnapshot.animationCurveRawValue =
                    update.curveRawValue
            }
        }
        // 0.19.0：抽屉「枢纽」导航行的开枢纽请求通道
        //（AppState.router.hubOpenRequested 置位—消费—清零，
        // 与 cronCreateRequested 同式）：抽屉先切聊天格
        // 再置位，本页在场消费、开枢纽 sheet
        .onChange(of: appState.router.hubOpenRequested) { _, requested in
            if requested {
                appState.router.hubOpenRequested = false
                showHub = true
            }
        }
        // 0.4.1：「选择」纯文本 sheet（长按菜单发起，
        // 选型见 DESIGN-V4 §26）
        .sheet(item: $selectionPayload) { payload in
            SelectableTextSheet(text: payload.text)
        }
        // §330：原生面 UIKit 行菜单「分享」的系统
        // 分享单（与「选择」sheet 同排）
        .sheet(item: $messageSharePayload) { payload in
            MessageShareSheet(text: payload.text)
        }
        // D3 破坏性确认与线程作废纪律（DESIGN §352）
        // 0.50.88 迁位：确认框改挂 bottomBar 子树、作废
        // 三行并入下方既有 currentThreadID 处理器——本
        // 根链不再为 D3 多裹两层类型（真机启动崩溃热修，
        // 见 DESIGN §354）
        // （§449 退役：顶栏模型选择面 sheet 随顶栏
        // 模型胶囊整件删除——选择面唯一宿主改中枢
        // 页内 modelEntryRow 的 sheet，见 AgentHub-
        // View）
        // 0.8.0（P1）：图片点开全屏查看（本地图与历史
        // 服务端图共用一个查看器）；文件牌点开走系统
        // QuickLook（字节先经文件下载通道落临时目录）
        // 0.36.4：查看器换代——集合载荷（同线程图片序、
        // 可翻页）＋ImageViewerView 双态；呈现承载走
        // UIKit zoom 转场（本页无导航栈，见 Zoom-
        // TransitionCover 注）
        .fullScreenCover(item: $imageViewerSession) { session in
            // §247.2 试点：起始页条目 id 作 zoom 源键，
            // 消息流图片两主面已挂 ZoomSourceAnchor
            ZoomTransitionCover(
                sourceID: session.items.indices.contains(
                    session.initialIndex
                )
                    ? session.items[session.initialIndex].id
                    : nil
            ) {
                ImageViewerView(
                    items: session.items,
                    initialIndex: session.initialIndex
                )
            }
        }
        // 反应浮排（DESIGN §343／§346）：长按一次
        // 呈现三层——药丸排＋快照＋动作卡同呈（动作
        // 集走 actionItems 单源、项/序/图标/危险色
        // 逐项同系统菜单）；点药丸/卡条目即执行并
        // 收起、点快照/空白收起。§343 的转交动作表
        // （confirmationDialog）随 §346 同呈退役
        .fullScreenCover(item: $reactionBarSession) { session in
            reactionBarOverlay(session)
        }
        // §471：系统 cover 转场（滑入硬切、三层互叠
        // 重影的来源之一）摘除——呈现/收起的动画全
        // 归浮排内部 ReactionBarMotion 时钟（Exyte
        // 参数），cover 只作承载
        .transaction(value: reactionBarSession?.id) { transaction in
            transaction.disablesAnimations = true
        }
        // §125：文件打开页（中间页）——聊天侧点牌的
        // 唯一落点（图片仍走上方全屏查看器、不经此页）
        // §129 落点、§219 改通道：失败页「让智能体重
        // 新发」改走引用槽位——文件引用挂进当前线程
        // 发送舱（FileOpenView 回的是 FileQuote 值、
        // 不再是整段机器文直写 input），发不发由用户
        // 点发送为准；宿主不在的落点见 FileOpenView
        // §452.6：聊天侧 QuickLook 直达（全屏，QL 自
        // 带分享出口）与兜底页两呈示面，与下方中间页
        // sheet 分工：中间页只剩文件引用块重开一途
        .fullScreenCover(item: $chatQuickLookItem) { item in
            NavigationStack {
                QuickLookPreview(url: item.url)
                    .ignoresSafeArea()
                    .navigationTitle(item.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") {
                                chatQuickLookItem = nil
                            }
                        }
                    }
            }
        }
        .sheet(item: $chatFallbackTarget) { target in
            FileFallbackView(target: target)
        }
        .sheet(item: $fileOpenTarget) { target in
            FileOpenView(
                target: target, origin: .conversation,
                onRequestResend: { quote in
                    fileOpenTarget = nil
                    if currentThreadID != nil {
                        // 引用槽位单一在场：文件引用入
                        // 槽即挤掉消息引用与动态引用
                        // （后入覆盖，与呈现侧收口同律）；
                        // 线程在场守卫沿 §129
                        pendingSourceQuote = .file(quote)
                        pendingQuote = nil
                        pendingQuoteIsFork = false
                        pendingFeedQuote = nil
                        composerFocusHandle.focus()
                    }
                }
            )
        }
        // 0.4.1：引用是发送舱的临时态，切换线程即作废，
        // 不许跨线程带过去；0.7.0 两处增补——草稿轻保活
        // （M1）与分流种子转入（M4），见下
        .onChange(of: currentThreadID) { oldID, newID in
            // D3/D2（DESIGN §352；0.50.88 自根链迁入本处）：
            // 编辑武装与乐观隐藏是当前线程临时态，切线程即作废
            editSentTarget = nil
            pendingEditSend = nil
            rewindHiddenEntryIDs = []
            // 0.30.0（落点记忆）：当前线程恒落盘——冷启/
            // 视图重建时由 ChatLandingResolution 恢复上
            // 次对话（页签不与主线绑定）；这是全仓唯一
            // 写入点，置空（删当前线程）即清记录
            appState.sideChats.setLastThreadID(newID)
            // 台账 148：切入线程即解析一次未读分界锚
            // 并推进水位（锚定格本次观看，见 refresh-
            // UnreadAnchor）
            if oldID != newID {
                refreshUnreadAnchor()
            }
            // 0.7.0（M1 轻保活）：切走前把输入框草稿存回
            // 旁聊状态、切入后恢复目标线程的草稿（发送后
            // 的空串存回即删草稿）；线程已被删的切走不回
            // 存（threads 名单已无此 id，防死键残留）
            if let oldID, oldID != newID,
               threads.contains(where: { $0.id == oldID }) {
                appState.sideChats.setDraft(input, for: oldID)
            }
            input = newID.flatMap { appState.sideChats.draft(for: $0) } ?? ""
            // 基础止血包（P4）：待发附件随线程分格——
            // 切走前把工作集存回旧线程格（旧线程已删
            // 则整格丢弃，与草稿死键纪律一致；无线程
            // 的落地态用落地格收纳），切入后取目标线
            // 程格作新工作集；附件从此只在所属会话里
            // 呈现与发送，不再串带
            if oldID != newID {
                if let oldID {
                    if threads.contains(where: { $0.id == oldID }) {
                        attachmentStash.store(attachments, for: oldID)
                    }
                } else {
                    attachmentStash.store(
                        attachments, for: Self.landingAttachmentStashID
                    )
                }
                attachments = attachmentStash.take(
                    for: newID ?? Self.landingAttachmentStashID
                ) ?? []
            }
            // §210：离开的线程名下若有待发动态引用，
            // 在此定点作废（规格 §3.3：切换线程即清）
            // ——只清离开者；新落点线程名下的待发引用
            // 由派生呈现自动接上，不再被本次清理追毁
            // （§208 种子制下清理是全局的、落位后任一
            // 再变更即误杀，定因见 §210 报告）
            if let oldID, oldID != newID {
                appState.pendingQuotes.feedQuotesByThread
                    .removeValue(forKey: oldID)
                // §219：点子／文件待发引用同律定点作废
                appState.pendingQuotes.sourceQuotesByThread
                    .removeValue(forKey: oldID)
            }
            // 0.7.0（M4）：分流种子经 pendingForkQuote 暂存
            // 穿过本次清理、转入新旁聊的待发送引用
            if let fork = pendingForkQuote {
                pendingQuote = fork
                pendingForkQuote = nil
                pendingQuoteIsFork = true
            } else {
                pendingQuote = nil
                pendingQuoteIsFork = false
            }
            // §210：落点线程名下有待发动态引用时，收
            // 口呈现侧动作（挤掉消息引用＋聚焦）；引
            // 用本体已在 AppState 表内、呈现是派生，
            // 无「消费」一说（见 applyPendingFeedQuote-
            // IfNeeded）
            applyPendingFeedQuoteIfNeeded()
            // §219：点子／文件待发引用同式收口（落点线
            // 程名下有引用在场时挤掉消息引用＋聚焦）
            applyPendingSourceQuoteIfNeeded()
            // 0.36.7（频道规格 §10.3）：当前线程同步为
            // 抽屉当前对象引用——落点解析/抽屉改道/新
            // 建/导入最终都汇到 currentThreadID 变更、
            // 在此一处派生，抽屉胶囊只问单一政策
            // （DrawerSelectionPolicy）；0.4.5 的
            // activeThreadID 回写退役。0.36.29：派生
            // 改经 syncDrawerObjectFromCurrentThread
            // （频道出处优先于线程派生，见该函数注）
            syncDrawerObjectFromCurrentThread()
        }
        // 0.4.5：消费抽屉的线程选择（DrawerView 点行/
        // 新建时置位；与 pendingChatSessionID 同模式：
        // 消费即清零，防重入）
        .onChange(of: appState.router.drawerThreadSelection) { _, id in
            if let id {
                appState.router.drawerThreadSelection = nil
                currentThreadID = id
            }
        }
        // §210：待发引用表变化（讨论写入/发送消费/
        // ✕ 摘除都经此表）时，若当前线程名下有引用
        // 在场就收口呈现侧动作——人已在目标线程内
        // 时写入即聚焦，不等切换事件（§208 种子制的
        // 本处理已随种子退役）
        .onChange(of: appState.pendingQuotes.feedQuotesByThread) { _, _ in
            applyPendingFeedQuoteIfNeeded()
        }
        // §219：点子／文件待发引用表变化时同式收口
        // （点子/文件写入都经此表）——人已在目标线程
        // 内时写入即聚焦，不等切换事件
        .onChange(of: appState.pendingQuotes.sourceQuotesByThread) { _, _ in
            applyPendingSourceQuoteIfNeeded()
        }
        // 0.4.5：抽屉删掉的正是当前线程时置空（计算属
        // 性随之落到最近线程，与旧版 deleteThread 内
        // 直改 currentThreadID 的语义一致）
        .onChange(of: appState.router.drawerDeletedThreadID) { _, id in
            if let id {
                appState.router.drawerDeletedThreadID = nil
                // 0.7.0：被删线程的草稿与滚动锚一并清掉，
                // 不在轻保活账上留死键
                appState.sideChats.setDraft("", for: id)
                appState.sideChats.setScrollAnchor(nil, for: id)
                // 基础止血包（P4）：附件格同清死键
                attachmentStash.remove(for: id)
                if id == currentThreadID {
                    currentThreadID = nil
                }
            }
        }
    }

    // MARK: - 主面（0.2.6 承载换代：发送区回到布局流）


    /// 顶簇宿主 overlay（同上拆分）
    @ViewBuilder
    private var topBarHostOverlay: some View {
        TopBarGuideHost(
            barHeight: $topBarHeight,
            barBottom: $topClusterBottomInWindow,
            scrollHandle: listScrollHandle
        ) {
            topBarCluster
        }
    }

    /// §321：新面列表顶 inset 喂入——量得顶簇底缘
    /// （窗口坐标）即认本值（列表视图同在窗口系
    /// 全幅、原点同源）；未量得（首拍前）回落
    /// §195 相加口径（窗口顶安全区实测＋顶簇实
    /// 高），量级同档、无悬空帧
    private var nativeFedTopInset: CGFloat {
        topClusterBottomInWindow > 0
            ? topClusterBottomInWindow
            : windowTopSafeInset + topBarHeight
    }

    /// §251 预热条目组装（§257 起自 .task 链抽为
    /// 独立函数：承载分叉后视图链更重，内联多语句
    /// 闭包在链上触发类型检查超时；组装口径与原内
    /// 联版逐字一致——用户条目直取原文、助手条目
    /// 过工具/留痕/回响/审批四闸后取摘记文本）
    private func preheatEntries(
        for thread: ChatThread
    ) -> [LayoutProductService.PreheatEntry] {
        thread.sortedEntries.compactMap { entry in
            if entry.role == "user" {
                return LayoutProductService.PreheatEntry(
                    entryID: entry.id,
                    renderedText: entry.content,
                    isUser: true
                )
            }
            guard entry.role == "assistant",
                  entry.toolCard == nil,
                  entry.traceKey == nil,
                  entry.echoKey == nil,
                  entry.approvalKey == nil
            else { return nil }
            // §335：预热文本改与呈现/量测同文——
            // displayText 单源助手＋活读存在性（与
            // 气泡 body 同源同拍）；旧 media 摘记
            // 文本口径作废（有确证摘行时与呈现分
            // 家、产物永远查不中）
            let scans = EntryScanMemo.scans(
                entryID: entry.id,
                content: entry.content,
                remoteImagePaths: entry.remoteImagePaths
            )
            return LayoutProductService.PreheatEntry(
                entryID: entry.id,
                renderedText: ChatNativeRowHeightComposer
                    .assistantDisplayText(
                        entryID: entry.id, scans: scans
                    ) {
                        FileMetadataStore.shared
                            .existence(for: $0) == .exists
                    },
                isUser: false
            )
        }
    }


    /// 聊天主面（§257 承载分叉）：列表面按特性开关
    /// 二选一（开＝carrierListSurface 新承载／关＝
    /// legacyListSurface 旧承载），下方页面级修饰
    /// 链（背景/坞显隐/选图器/附件面板/生命周期/
    /// 数据刷新）两承载共享、不因分叉而异——两承
    /// 载的页面行为差只许出在列表与回底钮两处承载
    /// 本身
    private var chatSurface: some View {
        chatSurfaceLifecycle(
            chatSurfacePresentation(
                Group {
                    nativeListSurface
                }
                // §185：背景层穿到屏幕四边——上下栏纯色块修
                // 复，页面背景单独忽略安全区铺满整屏，栏下内
                // 容能流到位时边缘即由滚动效果化开
                .background {
                    // 台账 179（§391）：背景走个性化读口
                    // ——默认档与 chatSurface 逐值相同，
                    // 改选只动本层（抽屉等共用 chatSur-
                    // face 的面不跟随）
                    Palette.chatBackground
                        .ignoresSafeArea()
                }
                // §186 配套（诊断 K1）：聚焦打字时隐藏导航坞——
                // TabView 的安全区预留不因输入舱退出安全区栈而
                // 消失，键盘升起时坞仍会骑到键盘顶、与舱的下段
                // 带重叠（「坞被键盘窗自然覆盖」在 SwiftUI Tab-
                // View 下不成立，机制见诊断 3.1 与 Composer-
                // GuideHost 文件头）；键盘态藏坞、落下恢复，坞
                // 在键盘态彻底退出画面，舱直接坐在键盘上。
                // 键盘整包 R5（2026-11-13）：显隐输入由聚焦
                // 状态改键盘几何快照的在场位——快照在 Will-
                // ChangeFrame 事件拍翻转（与 §194 舱常量同
                // 源同拍），旧路 composerFocused 是 delegate
                // 回调的观察回写、与键盘事件不同拍，坞的退
                // 场/归位因此总慢键盘半拍（症⑤坞鬼影的时序
                // 分量）；聚焦态自此退出坞显隐派生。本修饰
                // 只挂聊天格内容根、逐格生效，切到其他格时
                // 由该格自身口径接管（恒可见）
                // §449 第 5 条定因（实验 K）：本根旧
                // 式在键盘落下时显式断言 .visible，与
                // push 页（如中枢 hubFullPageChrome）
                // 的 .hidden 在同栈正面对撞、根断言
                // 胜出，push 页藏栏永不生效（A/B/C/
                // D/G 五式排除后坐实）。改 .automatic：
                // 根只在键盘升起时断言 .hidden，其余
                // 不表态、由栈顶页自决——键盘坞行为
                // 不变（升起仍藏、落下默认可见）
                .toolbar(
                    kbSnapshot.isKeyboardUp ? .hidden : .automatic,
                    for: .tabBar
                )
            )
        )
    }

    /// §373 结构性减深：chatSurface 修饰链中段
    /// （选择器/呈现/锚点组）——自原单表达式链拆
    /// 出的泛型辅助段：自成不透明返回类型、链深与
    /// chatSurface 本体分开求值（§373.3）；修饰顺
    /// 序、值与闭包逐字沿原链，本段只搬不改
    private func chatSurfacePresentation<Content: View>(
        _ content: Content
    ) -> some View {
        content
        // 0.4.3（§28）：顶栏 headerBar 已收编——不再走
        // 本容器的 .overlay 悬浮（未注册的覆盖层不在系
        // 统边缘效果体系内，WWDC25-323／Adopting
        // Liquid Glass），改挂消息列表 ScrollView 的
        // .safeAreaBar(edge: .top) 注册为系统认可的自
        // 定义 bar（见 messageList）；overlay 层随之撤
        // 销。0.4.0 删 topFade 的前置至此才真正补完
        // §195（2026-11-13）：顶栏注册再退役——顶簇
        // 回到本容器的 overlay 层（见 chatSurface），
        // 但不再是「未注册的覆盖层」：由 TopBar-
        // GuideHost 以 UIKit 约束锚定托管，落位只认
        // 窗口顶安全区；注册口径让位于落位不变量，
        // 顶缘 .soft 改由列表顶 contentMargins 区
        // 决定（见 messageList §195 注）
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            // 先清空再异步加载：清空触发的空数组回调
            // 被上面的 guard 挡下，防 onChange 重入
            photoItems = []
            Task { await loadPickedPhotos(items) }
        }
        // §152：视频选图器（面板「添加视频」开；视频
        // 过滤、入条走文件路——视频是文件不是多模态
        // 图片 part，命名与大小闸走 Core/FileIntake）
        .photosPicker(
            isPresented: $showVideoPicker,
            selection: $videoItems,
            matching: .videos
        )
        .onChange(of: videoItems) { _, items in
            guard !items.isEmpty else { return }
            videoItems = []
            Task { await loadPickedVideos(items) }
        }
        // §147：附件面板 sheet 本体（形态见 Attach-
        // mentPanelView）；面板内各动作先收面板、隔一
        // 拍再呈现下一层（相机/选图器/文件桥），不与
        // sheet 收起同帧抢呈现（同 DocumentPicker-
        // Bridge 延拍口径）。确认入条是终结动作不
        // 呈现下一层，直接收面板后批量取数入条（多
        // 选逐张走单张同一取数路，§152）。
        // §303（A-08 定高收口）：定高自 §152 的内容
        // 实测 detent 改走 UIKit custom detent 在呈
        // 现控制器内单源求解（面板内 Attachment-
        // SheetDetentBridge，未授权态与确认行增减
        // 经指纹触发重解）；§152/§154 的量测回路整
        // 套退役：PreferenceKey 回报、宿主实测高/真
        // 高两状态、Core 定高决策（可信下限＋75%
        // 钳顶）、fixedSize 保真一并删除
        // §327（小修批①）：custom detent 精确贴合整
        // 套再退役——桥本体删除，定高改系统 detent
        // 档位 [.medium, .large]（attachmentPanel-
        // Presentation 单源），确认行增减不再改高。
        // D5（台账 11）修订：定高条改系统 .height()
        // 档＋常量纯算贴合（AttachmentPanelView 内施
        // 加，ChatView 只留 .sheet() 本体不再调口径
        // 配方），确认行增减仅当停在贴合档才跟随
        .sheet(
            isPresented: $showAttachPanel,
            onDismiss: {
                // §317：收起真完成信号——登记的面板行
                // 动作在此刻才执行，呈现型动作（相机/
                // 选图/文件桥）不再与收起动画竞速
                let action = attachPanelPendingAction
                attachPanelPendingAction = nil
                action?()
                // 台账 182：面板收起真完成点——原生
                // 面静息锚离散重解析（呈现期间 TabView
                // 层级/变换态变化是锚失真触发条件，须
                // 在恢复后的层级上立即重算）
                nativeHandle.reresolveAnchorsAfterPresentation()
            }
        ) {
            AttachmentPanelView(
                onCamera: {
                    afterAttachPanelDismiss { showCamera = true }
                },
                onConfirmPhotos: { assetIDs in
                    showAttachPanel = false
                    Task { await loadStripPhotos(assetIDs: assetIDs) }
                },
                onViewAll: {
                    afterAttachPanelDismiss { showPhotoPicker = true }
                },
                onAddFile: {
                    afterAttachPanelDismiss {
                        showDocumentPicker = true
                    }
                },
                onAddVideo: {
                    afterAttachPanelDismiss { showVideoPicker = true }
                }
            )
        }
        // 0.36.31（件二）：.fileImporter 已删——侧载
        // 设备类上其 coordinator 会死在被拆的呈现上
        // 下文里、点「打开」无反应（诊断 file-picker-
        // batch-diagnosis-20261111 定案）。文件选择先
        // 走命令式桥、§317 再换代为 DocumentPicker-
        // View 状态旗排队呈现（见下 fullScreenCover
        // 与 DocumentPickerView 头注），结果直喂
        // loadPickedFiles，不经本链
        .fullScreenCover(isPresented: $showDocumentPicker) {
            DocumentPickerView(
                onPick: { urls in
                    showDocumentPicker = false
                    loadPickedFiles(urls: urls)
                },
                onCancel: { showDocumentPicker = false }
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onImage: { data in
                    showCamera = false
                    appendImage(data)
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        // 台账 182：其余覆盖层（照片/视频选择器、文
        // 件选择器、相机）的呈现与收起两边沿同走离
        // 散重解析——呈现型覆盖层无 onDismiss 口，
        // 以呈现旗两边沿为完成点（与附件面板
        // onDismiss 同列触发点）
        .onChange(of: showPhotoPicker) { _, _ in
            nativeHandle.reresolveAnchorsAfterPresentation()
        }
        .onChange(of: showVideoPicker) { _, _ in
            nativeHandle.reresolveAnchorsAfterPresentation()
        }
        .onChange(of: showDocumentPicker) { _, _ in
            nativeHandle.reresolveAnchorsAfterPresentation()
        }
        .onChange(of: showCamera) { _, _ in
            nativeHandle.reresolveAnchorsAfterPresentation()
        }
        .onChange(of: showAttachPanel) { _, presented in
            // 面板呈现边沿（收起边沿由上方 onDismiss
            // 真完成点承担，此处只补呈现侧）
            if presented {
                nativeHandle.reresolveAnchorsAfterPresentation()
            }
        }
        // 0.4.0（§3.4）：消费待续聊会话（四处入口经
        // AppState.router.pendingChatSessionID 置位、ContentView
        // 切聊天格，本页导入历史后进聊天续聊）
        .onChange(of: appState.router.pendingChatSessionID) { _, id in
            if let id {
                Task { await consumePendingChatSession(id) }
            }
        }
        // §165（锚点包）：点达原对话的锚定行——枢纽记
        // 录行/通知回执置位 approvalAnchorRequest，本
        // 页消费：切线程（与抽屉切线同字段）→等条目
        // 进渲染→滚动定位＋点亮→清零；目标线程/条目
        // 找不到如实落空（不滚、不亮），不许假定位
        .onChange(of: appState.router.approvalAnchorRequest?.threadID) {
            _, _ in
            consumeApprovalAnchorRequest()
        }
        .onAppear {
            consumeApprovalAnchorRequest()
            // §210：待发引用的呈现侧收口兜底——本页重
            // 现时当前线程名下有引用在场就补收口（挤
            // 掉消息引用＋聚焦）。§208 此处原为种子兜
            // 底消费；改挂派生后引用本体不依赖消费、
            // 视图重现自动呈现，此处只补呈现侧动作
            applyPendingFeedQuoteIfNeeded()
            // §165（锚点包）：物化回调接线（幂等赋值；
            // 全 App 只有聊天页持有 modelContext 落盘
            // 面，与枢纽经 AgentHubView 注入审批终态回
            // 调的分工同构）——store 每次审批刷新成功
            // 后经它落锚定条目
            let hubStore = appState.sharedHubStore()
            if hubStore.onAnchorDataRefreshed == nil {
                hubStore.onAnchorDataRefreshed = {
                    ApprovalAnchorMaterialization.run(
                        store: hubStore, context: modelContext
                    )
                }
            }
        }
    }

    /// §373 结构性减深：chatSurface 修饰链尾段
    /// （生命周期/落定组）——同上拆分；§371 的
    /// drawerPresented 处理器仍在本段链尾（.task
    /// 之后），落点口径与 §371 钉测不变
    private func chatSurfaceLifecycle<Content: View>(
        _ content: Content
    ) -> some View {
        content
        // 0.31.0 恢复链（取代 0.20.0）：生成与连接分
        // 家后切后台什么都不用记——events 流断了就是
        // 结果未知，run 在服务端照常跑完；要做的只有
        // 回前台/进线程时消费持久账本续对账（resume-
        // RunIfNeeded，无账本即空转返回）
        .onChange(of: scenePhase) { _, phase in
            // 基础止血包（P3）：离开活动态先把当前输入
            // 存回当前线程草稿——旧口径只有切线程一刻
            // 落盘，切后台接电话、进程被系统杀掉（都
            // 不触发切线程）时打了一半的字就此丢失；
            // 落盘判定走 Core DraftSavePolicy（有当前
            // 线程且线程仍在名单内才存，防死键）
            if phase != .active, let id = currentThreadID,
               DraftSavePolicy.shouldSaveOnLeavingActive(
                   hasCurrentThread: true,
                   threadStillExists: threads.contains { $0.id == id }
               ) {
                appState.sideChats.setDraft(input, for: id)
            }
            if phase == .active {
                // 0.36.15：回前台重备语音分析器（退后
                // 台时已弃置产物，见下方 background 分支）
                dictation.armPreheat()
                Task { await resumeRunIfNeeded() }
                // 台账 154（DESIGN §336）：回前台同拍
                // 排发件箱（对账之后——drain 内查账本
                // 为空才动，与本处先后无关、双保险）
                Task { drainOutboxIfNeeded() }
                // 0.36.21：回前台刷新待批（就地卡）
                Task {
                    await appState.sharedHubStore()
                        .refreshApprovalForChat()
                }
            } else if phase == .background {
                // 0.36.15：退后台弃置已备分析器——不在
                // 后台占着系统语音资源；录音中的分析器
                // 不在此列（走中断/收尾原有路径）
                dictation.suspendPreheat()
            }
        }
        // 0.36.20（§86.4）：网络路径恢复/切换即刻续对
        // 账——与回前台同一入口（resumeRunIfNeeded），
        // 路径信号只做触发器、不预判成败
        .onChange(of: appState.networkPathEpoch) {
            Task { await resumeRunIfNeeded() }
            // 台账 154（DESIGN §336）：网络恢复同拍
            // 排发件箱——离线失败条目的主复活点
            Task { drainOutboxIfNeeded() }
            // 0.36.21：网络恢复同样刷新待批
            Task {
                await appState.sharedHubStore().refreshApprovalForChat()
            }
        }
        // 0.36.21：生成结束（流式下降沿）刷新待批——
        // 写入恰在这轮生成里被暂存的概率最高，静默刷
        // 新把新卡顶到流末尾
        // 2026-11-13（P2 真机判红修复）：同沿补刷留痕
        // 回响——AI 自开旁聊恰发生在本轮生成里，旧口
        // 径回响只在进页/切线程时拉取，用户守在主线
        // 等回复时流尾不出卡（工具调用卡＋文字回复之
        // 外无点达入口，与真机截图合）；与待批同点同
        // 静默口径，拉取失败保留旧卡（见 refreshEcho-
        // Traces 注）
        .onChange(of: isStreaming) { wasStreaming, nowStreaming in
            if !wasStreaming && nowStreaming {
                // §385（总表 163）：流式上升沿——实时
                // 活动切「生成中」阶段
                Task {
                    await RunLiveActivityCenter.shared.update(phase: .generating)
                }
            }
            if wasStreaming && !nowStreaming {
                // 0.43.0（A11Y-S6）：VO 运行时播报生成
                // 完成——同一下降沿、同等静默（VO 关时
                // 无声，见 A11yAnnouncer）
                A11yAnnouncer.generationCompleted()
                Task {
                    await appState.sharedHubStore()
                        .refreshApprovalForChat()
                }
                Task {
                    await refreshEchoTraces()
                }
                // 发送失败机制包（语义 4）：落定同沿
                // 的 drain 删除——它是死循环的自激触
                // 发源（落定失败→下降沿→drain 踢泵→
                // 重投→再落定失败）；触发源只剩用户
                // 手点、网络恢复、回前台、退避唤醒钟
            }
        }
        // 0.36.15：离开聊天页关预热总闸并弃置产物
        .onDisappear {
            dictation.disarmPreheat()
            // H2-a：离开页面停播（施工图 3.3 播放态
            // 管理口径）
            SpeechPlayer.shared.stop()
        }
        // H2-a：朗读态呈现——失败经既有通知口给人话
        // （一次，不许静默吞）；开始播放给 Voice-
        // Over 一句播报（VO 关时无声，同 A11y 口径）
        .onChange(of: SpeechPlayer.shared.machine.state) {
            _, newState in
            switch newState {
            case .failed(_, let message):
                showNotice(message, tier: .persistent)
            case .playing:
                A11yAnnouncer.announce(
                    L10n.string("正在朗读")
                )
            case .idle, .requesting, .paused:
                break
            }
        }
        .task(id: currentThreadID) {
            await resumeRunIfNeeded()
            // 台账 154（DESIGN §336）：进/切对话排本
            // 线程发件箱。发送失败机制包（语义 4）：
            // 收敛为每线程每会话一次——旧口径每次触
            // 发都全量 drain（触发源之一），积压续发
            // 改由提交泵＋唤醒钟＋网络/前台事件驱动。
            // 一次性按线程 id 记账且只在真有当前线程
            // 时落记：挂载初期视图先以无线程态触发过
            // 一次 .task，无线程的空触发不许把额度耗
            // 掉（钉测实证：额度被空触发吃掉后线程打
            // 开再不 drain、泵永不启动）
            if let thread = currentThread,
               !launchDrainedThreadIDs.contains(thread.id) {
                launchDrainedThreadIDs.insert(thread.id)
                drainOutboxIfNeeded()
            }
            // 0.36.21：进/切对话刷新待批（就地卡数据源，
            // 与枢纽共享同一 store）
            await appState.sharedHubStore().refreshApprovalForChat()
            // P2 会话包：进/切对话刷新留痕回响（不走
            // 推送——P0 审计口径；§229 起拉成即物化
            // 为真条目；生成落定沿另有一次补刷，见
            // isStreaming 下降沿注）
            await refreshEchoTraces()
            // §251（换代包 2）：排版产物预热——进/切
            // 线程时对已载条目在后台预产产物。文本宽走
            // LayoutProductService.textWidth 单源（§263：
            // 用户泡旧账 W−76、助手正文屏宽×文宽占屏
            // 比，与气泡几何同账）；助手文本§335 起改
            // 走 displayText 单源（preheatEntries 内以
            // 活读存在性派生、与呈现/量测同文）——旧
            // media 摘记文本口径作废：彼时产物与呈现
            // 在有确证摘行时分家、呈现查不中产物；
            // §335 起产物是呈现与预计算的共同单源
            if let thread = currentThread {
                LayoutProductService.shared.preheat(
                    entries: preheatEntries(for: thread),
                    screenWidth: UIScreen.main.bounds.width,
                    style: LayoutStyleContext(
                        sizeCategory:
                            dynamicTypeSize.contentSizeCategory,
                        boldText: UIAccessibility
                            .isBoldTextEnabled
                    )
                )
            }
        }
        // §366：抽屉开合翻转→运动窗终点记入原生面
        // 句柄（弹簧 response＋落定余量 0.08）：落定
        // 拍在窗内冻结施工、窗末合并一拍。信号只写
        // 记账——抽屉执行本体在壳层容器、本页不参
        // 与；跟手拖拽期不翻转本值、不在本窗覆盖内
        // （进度事实只在容器桥，§366.4 登记）
        // §371：本处理器原挂 chatScaffold 根链——
        // 0.50.92 真机启动闪退定罪即此层根链包裹
        // （§354 同病），迁至 chatSurface 子树链
        // 尾：包裹面自整棵 scaffold 缩为本子树，
        // 观察值／写入式／触发时机一字不变
        // （chatSurface 是 scaffold 唯一内容、三
        // 承载同在本面 Group 内，覆盖面等价）
        .onChange(of: appState.router.drawerPresented) { _, _ in
            nativeHandle.drawerMotionDeadline =
                CACurrentMediaTime()
                + CFTimeInterval(DrawerSpringTiming.response)
                + 0.08
        }
    }

    /// （顶部渐隐带 topFade 已于 0.4.0 删除，审计 §1.1／
    /// §6.1：自加实色渐变带是「白底上边缘模糊不可感」的
    /// 疑因之一，删后滚动边缘模糊回归系统 .scrollEdge-
    /// EffectStyle(.soft) 单独承担；顶栏收编系统通道与
    /// 玻璃换装归二期材质批）

    /// 顶栏状态行（0.6.0 立；0.6.1 改短词；0.7.0 通道
    /// 口径修正）：词由 OneDayCore.OverviewStatusLine
    /// 对「桥快照＋Hermes 通道探活」双输入纯派生，只报
    /// 可证事实短词（联系不上／待审批 N／在线）——
    /// 「联系不上」只认通道探活，桥挂不许冒充整机离线
    /// （口径全文见 OverviewBridgeModels）；完整状态句
    /// 在活动页页头，本行不许再回长句（0.6.0 的「有 N
    /// 条待你审批」等长句在胶囊里必被截成「…」，见
    /// identityCapsule 根修注）。
    /// 0.3.8 的本地三态（未连接/唤醒中/生成中/在线）
    /// 早已退役——生成中/唤醒中在本页消息区自有呈现，
    /// 不占顶栏状态行
    private var overviewStatusWord: String {
        overviewStore?.statusLine ?? "联系不上"
    }

    /// 状态点色（0.19.0 改同源）：与状态词共用 Core 的
    /// classify 一处判定（OverviewBridgeStore.status-
    /// Tone）——在线绿／待审批橙／联系不上弱灰。旧实现
    /// 只认桥快照（snapshot 缺失或 hermesUp 假即落灰），
    /// 与词的通道口径分叉：桥挂（未粘钥匙/401）＋通道在
    /// 时词报「在线」、点却是灰（用户 22:26 真机点名
    /// 「状态指示灯改绿色」的定因），自此两源归一
    private var overviewStatusColor: Color {
        switch overviewStore?.statusTone {
        case .online: return Palette.success
        case .attention: return Palette.warning
        case .offline, nil: return Palette.inkMuted
        }
    }

    private var overviewBadgeCount: Int {
        overviewStore?.badgeCount ?? 0
    }

    /// 顶簇本体（§195 前为消息列表 .safeAreaBar
    /// (edge: .top) 的注册内容，195 起迁 TopBar-
    /// GuideHost 锚定托管、内容一字未动）：顶栏
    /// （进展胶囊已随 §474 撤除）。顶簇实高由宿主
    /// 量测回报（见
    /// D9：对话内查找栏（对标 iOS Messages）
    private var findBar: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            TextField("查找", text: $findQuery)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($findFieldFocused)
                .onSubmit {
                    performFind()
                }
            
            if !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if findSession.matches.isEmpty {
                    Text("无结果")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    Text("\(findSession.currentIndex + 1)/\(findSession.matches.count)")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .monospacedDigit()
                }
            }
            
            Button {
                navigateToPreviousMatch()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 32, height: 32)
            }
            .disabled(findSession.matches.isEmpty)
            .buttonStyle(.odPressable)
            
            Button {
                navigateToNextMatch()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 32, height: 32)
            }
            .disabled(findSession.matches.isEmpty)
            .buttonStyle(.odPressable)
            
            Button("完成") {
                closeFind()
            }
            .font(.body)
            .buttonStyle(.odPressable)
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(.ultraThinMaterial)
        // §503（第 5 件·打开自动聚焦）：查找栏入场
        // 即把焦点交给输入框、键盘随之升起——旧形
        // 态裸 TextField 无焦点句柄，点放大镜后还要
        // 再点一次输入框
        .onAppear {
            findFieldFocused = true
        }
        // §503（第 4 件·输入即搜）：停打 200ms 后以
        // 当前查询重算命中（任务随 id 变自动取消、
        // 只落最后一拍），计数随打随变；空查询即时
        // 清集不等防抖（栏内呈现同步归零）
        .task(id: findQuery) {
            guard showFind else { return }
            guard ChatFind.normalizedQuery(findQuery) != nil
            else {
                clearFindMatches()
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            recomputeFind()
        }
    }

    /// 中枢目的地（§434）：zoom 与标准 push 二选一
    /// 由 ZoomTransitionPolicy 裁决（§247.2 单源：
    /// Reduce Motion→标准；源＝顶簇居中大头像、
    /// 常驻不滚走故恒可用）。审批终态回调与模型
    /// 入口注入在此一处收口（三处 showHub 置位点
    /// 共用同一目的地）
    @ViewBuilder
    private var hubDestination: some View {
        let hub = AgentHubView(
            onApprovalChanged: {
                Task { await overviewStore?.refresh(appState: appState) }
            },
            modelEntry: HubModelEntry(
                groups: appState.pickerModelGroups,
                current: currentChoice,
                currentLabel: ModelDisplayNames.triggerLabel(
                    for: currentChoice.model
                ),
                onSelect: { choice in
                    selectCurrentChoice(choice)
                }
            )
        )
        .hubFullPageChrome()
        if ZoomTransitionPolicy.decide(
            reduceMotion: reduceMotion,
            sourceAvailable: true
        ) == .zoom {
            hub.navigationTransition(
                .zoom(
                    sourceID: Self.hubZoomSourceID,
                    in: hubZoomNamespace
                )
            )
        } else {
            hub
        }
    }

    /// TopBarGuideHost），列表顶留位据此记账
    private var topBarCluster: some View {
        VStack(spacing: OneDayMetrics.rowInnerGap) {
            // §449（六报之 1/2/3）：顶簇改单带——旧
            // 两段式（headerBar 整行＋其下身份区）退
            // 役：顶栏模型胶囊整件删除、汉堡/铃两钮
            // 与居中身份区同带（topBand）；放大镜钮
            // §500 按总表 150 原文恢复（见 topBand 注）；
            // 查找栏的次序不变（进展胶囊已随 §474 撤除）
            topBand
            // §474（用户 2026-11-24 亲令）：进展胶囊
            // 撤除——聊天面不许有第二胶囊；他会话／
            // 后台活动统一归中枢（状态行 hubActivity-
            // Line 与台账段同源 ProgressCapsule.
            // derive 已在彼呈现，本面不再悬浮复读）
            if showFind {
                findBar
            }
        }
    }

    /// 顶带（§449，用户 03:08 六报之 1/2/3 定版，
    /// 取代 §202/§434 的两段式顶簇）：汉堡/铃两钮
    /// 与居中身份区同带——ZStack 顶对齐，钮行顶距
    /// spacingS 使钮心落在头像心上方 ≈8pt（参照聊
    /// 天页量测 Δ≈4–15、取栅格值 8，见 DESIGN
    /// §449.3）；顶栏模型胶囊（第 2 条）整件退役、
    /// 模型切换唯一入口收中枢（§449.2）。放大镜钮
    /// 沿革：§449.1 曾随第 1 条退役、查找下沉身份
    /// 胶囊长按菜单——§500 按总表 150 原文「删钮同
    /// 时安置为直达放大镜钮」恢复直达钮（长按菜单
    /// 入口保留、双入口并存，偏离登记见 §500）。
    /// 两钮本体自旧
    /// headerBar 逐字迁入（盘/字形/命中域/角标不
    /// 变），仅承载行由独立行改同带叠放；旧行尾的
    /// 「会话名次行已撤销」注记随行退役（口径在
    /// §449 与 git 史里）
    private var topBand: some View {
        ZStack(alignment: .top) {
            headerIdentityHero
            HStack(alignment: .center, spacing: 0) {
                drawerButton
                Spacer(minLength: OneDayMetrics.spacingS)
                HStack(spacing: OneDayMetrics.spacingS) {
                    findButton
                    bellButton
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingS)
        }
    }

    /// 左钮：汉堡（开抽屉）。本体自旧 headerBar 迁
    /// 入、规格一字未动（HeaderButtonSpec 直径 40／
    /// 字形 20 regular、0.23.0 起系统玻璃、命中域
    /// 外扩 44）；字形取汉堡线与抽屉隐喻对齐（第
    /// 31 条，「分栏」图标 sidebar.left 已退场）
    private var drawerButton: some View {
        Button {
            // 0.4.5：开抽屉只写语义状态，壳层据
            // drawerPresented 执行推式动画（并先
            // 收键盘，见 ContentView.setDrawer）
            appState.router.drawerPresented = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(
                    size: HeaderButtonSpec.glyphPointSize,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
                .frame(
                    width: HeaderButtonSpec.diameter,
                    height: HeaderButtonSpec.diameter
                )
                .glassEffect(.regular, in: Circle())
                .frame(
                    width: OneDayMetrics.minTapTarget,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("会话列表")
        .accessibilityIdentifier("drawer.open")
    }

    /// 查找钮（总表 150／§500）：会话内查找的直达
    /// 入口。⊙「更多」菜单已删（§434 清点实证：菜
    /// 单内仅「在对话中查找」一项且系独一份入口）；
    /// 安置回总表原文的直达放大镜钮——点按即展开
    /// 现行 findBar，行为零变化。规格与汉堡/铃同族
    /// （HeaderButtonSpec 玻璃盘 40／字形 20／命中
    /// 域外扩 44）。身份胶囊长按菜单内的同名入口保
    /// 留（§449.1，双入口并存）
    private var findButton: some View {
        Button {
            showFind = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(
                    size: HeaderButtonSpec.glyphPointSize,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
                .frame(
                    width: HeaderButtonSpec.diameter,
                    height: HeaderButtonSpec.diameter
                )
                .glassEffect(.regular, in: Circle())
                .frame(
                    width: OneDayMetrics.minTapTarget,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("在对话中查找")
        .accessibilityIdentifier("topbar.find")
    }

    /// 右钮：铃铛＋角标（角标＝未读通知＋待审批，
    /// 总览桥聚合）。本体自旧 headerBar 迁入、规
    /// 格一字未动（玻璃盘 40、命中域 44、角标
    /// dangerFill 白字压右上）
    private var bellButton: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(
                        size: HeaderButtonSpec.glyphPointSize,
                        weight: .regular
                    ))
                    .foregroundStyle(Palette.ink)
                    .frame(
                        width: HeaderButtonSpec.diameter,
                        height: HeaderButtonSpec.diameter
                    )
                    .glassEffect(.regular, in: Circle())
                if overviewBadgeCount > 0 {
                    Text("\(overviewBadgeCount)")
                        .font(.caption2.weight(.bold))
                        // 角标坐在 dangerFill 面上，字恒白
                        // （第 85 条 BC-6：dangerFill 暗档
                        // 深红实算 4.87、白字可读）
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Palette.dangerFill, in: Capsule())
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
            }
            .frame(
                width: OneDayMetrics.minTapTarget,
                height: OneDayMetrics.minTapTarget
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(
            overviewBadgeCount > 0
                ? "通知，\(overviewBadgeCount) 条待处理"
                : "通知"
        )
    }

    /// 居中身份区（§434，对位 Muse 聊天页页头量
    /// 测）：大头像 67pt 居中＋名/状态身份胶囊压其
    /// 下沿（胶囊高 44、与头像重叠 ≈8）——两者点
    /// 按同入中枢页；头像是 zoom 转场的源（mat-
    /// chedTransitionSource），胶囊同路触发同一
    /// push（源恒为头像，两源同 id 系统行为未定
    /// 不冒进，见 spec 第三节）。名/状态数据源与
    /// 旧顶簇头像钮同源（agentDisplayName＋over-
    /// viewStatusWord），不新造
    private var headerIdentityHero: some View {
        ZStack(alignment: .bottom) {
            HubAvatarButton(
                avatar: appState.agentAvatarImage,
                livingAvatar: appState.livingAvatar,
                displayName: appState.agentDisplayName,
                statusWord: overviewStatusWord,
                statusColor: overviewStatusColor,
                avatarPointSize: OneDayMetrics.avatarChatHero,
                onOpenHub: { showHub = true }
            )
            .matchedTransitionSource(
                id: Self.hubZoomSourceID, in: hubZoomNamespace
            )
            .padding(.bottom, 36)

            // §449：胶囊本体抽为独立件 HubIdentity-
            // Capsule（顶带复刻 rig 同件复用）；名/状
            // 态数据源与旧顶簇头像钮同源（agentDis-
            // playName＋overviewStatusWord），不新造
            HubIdentityCapsule(
                displayName: appState.agentDisplayName,
                // §449.9 立源、§474 收口：第二行＝当前
                // 工具活动短语（与中枢状态行同读
                // AppState.liveActivityPhrase、同源同
                // 口径）；§474 起无活动不回落连接状态
                // 词——第二行留空（用户亲令删「在线」、
                // 小字只许工作状态）
                statusWord: appState.liveActivityPhrase,
                onOpenHub: { showHub = true },
                onFindInConversation: { showFind = true }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, OneDayMetrics.spacingXS)
    }

    // （§449 退役：顶栏模型选择面 modelPickerSheet
    // 随顶栏模型胶囊整件删除——§153 选择面本体
    // （ChatModelPickerView）不退役，唯一宿主改中
    // 枢选择面；隐藏服务商的 §158 分流/确认/落账
    // 随迁 AgentHubView，见 DESIGN §449.2）

    /// 底部发送区（0.2.6 起由消息列表的安全区承载、不
    /// 再是覆盖层；0.2.6–0.4.2 为 .safeAreaInset，0.4.3
    /// 改 .safeAreaBar 注册，§28；**§186 起改由 Comp-
    /// oserGuideHost 以 keyboardLayoutGuide 托管**——
    /// 本函数产出的整栈视图改经 chatSurface 的托管桥
    /// 落位，栈本体、内部排布与高度口径一字不变，见
    /// ComposerGuideHost 文件头）：错误/提示条＋发送
    /// 舱（回底钮 §124 起回到本区布局流：输入舱上方
    /// 一行右对齐承载，落位由构造保证；三轮浮层落位
    /// 的病史见 §124）＋发送
    /// 舱，自下而上排在列表下方的安全区留位里。键盘收起时
    /// 留位贴原生底栏上方；键盘升起时系统安全区扩张、整段
    /// 被顶到键盘上方（系统通道，见 chatSurface 换代注）。
    /// 高度只认内容：本 VStack 与发送舱各环保留 fixedSize
    /// 断环（0.2.5），在布局流里是双保险。
    /// （0.4.0 删，审计 §3.2 影响面 2：自绘栏时代手算的
    /// tabBarClearance 避让——原生底栏回来后底部留位回
    /// safeAreaInset 系统通道，发送舱在布局流内、安全区
    /// 自理，不再手算补高）

    /// 发送区整栈（§257 起两承载共用本构建）：回底
    /// 钮行的有无与点按动作由调用方注入——旧承载＝
    /// 行在栈内＋proxy 贴底（§124 定版）；新承载＝
    /// 栈内无钮行，钮归容器 overlay 浮层（见
    /// ChatListCarrier.swift），动作走句柄贴底
    /// §373 结构性减深：整栈本体已提取为独立结构体
    /// ChatBottomBarView（ChatBottomBarViews.swift，
    /// 连同 ChatInputBarView/ChatComposerCardView）；
    /// 本函数只做依赖组装——ChatView 构建的子条经
    /// AnyView 擦除边界交付、状态以值/绑定/闭包注
    /// 入，返回类型即该结构体一个具名叶子，不再把
    /// 整栈组合类型内联进 ChatView（0.50.92/93 真机
    /// 启动闪退 §371/§373：单类型内泛型嵌套贴悬崖、
    /// 单点迁层只挪耗尽点）。组装求值点与原内联版
    /// 相同（同在三处调用点求值本函数），子条构建
    /// 时机/条件逐字对应原 body 内条件。
    private func bottomBar(
        showsArrowRow: Bool,
        onScrollToBottom: @escaping () -> Void
    ) -> some View {
        ChatBottomBarView(
            showsArrowRow: showsArrowRow,
            onScrollToBottom: onScrollToBottom,
            importRetryBarView: importRetryContext.map {
                AnyView(importRetryBar($0))
            },
            importRetrySessionID: importRetryContext?.sessionID,
            historySyncBarView: AnyView(historySyncBar),
            errorBannerView: errorMessage.map { message in
                AnyView(errorBanner(message))
            },
            errorMessageValue: errorMessage,
            noticeBarView: noticePresentation.current.map {
                AnyView(noticeBar($0.text))
            },
            noticeID: noticePresentation.current?.id,
            showsBackToBottomButton: showsBackToBottomButton,
            scrollToBottomButtonView:
                showsArrowRow && showsBackToBottomButton
                ? AnyView(
                    scrollToBottomButton(action: onScrollToBottom)
                ) : nil,
            speechBarVisible: SpeechPlayer.shared.machine
                .showsPlaybackBar,
            speechPlaybackBarView: SpeechPlayer.shared.machine
                .showsPlaybackBar
                ? AnyView(speechPlaybackBar) : nil,
            dictation: dictation,
            dictationFailureBarView: dictation.failure.map {
                AnyView(
                    dictationFailureBar($0)
                        .padding(.bottom, OneDayMetrics.spacingS)
                )
            },
            dictationNoticeBarView: dictation.notice.map {
                AnyView(
                    dictationNoticeBar($0)
                        .padding(.bottom, OneDayMetrics.spacingS)
                )
            },
            editBannerArmed: editSentTarget != nil,
            onCancelEditSent: cancelEditSent,
            quoteBarView: pendingQuote.map {
                AnyView(quoteBar($0))
            },
            feedQuoteBarView: pendingFeedQuote.map {
                AnyView(feedQuoteBar($0))
            },
            sourceQuoteBarView: pendingSourceQuote.map {
                AnyView(sourceQuoteBar($0))
            },
            attachmentsCount: attachments.count,
            attachmentsStripView: attachments.isEmpty
                ? nil : AnyView(attachmentsStrip),
            quoteSlotOccupied: pendingQuote != nil
                || pendingFeedQuote != nil
                || pendingSourceQuote != nil
                || editSentTarget != nil,
            composerRowView: AnyView(composerRow),
            composerShape: composerShape,
            onComposerTap: { composerFocusHandle.focus() },
            composerCapsuleHeight: $composerCapsuleHeight,
            editConfirmPresented: Binding(
                get: { pendingEditSend != nil },
                set: { if !$0 { pendingEditSend = nil } }
            ),
            editConfirmMessage: editSendConfirmMessage,
            onConfirmEditSend: {
                if let draft = pendingEditSend,
                   let target = editSentTarget {
                    performEditSend(draft: draft, target: target)
                }
                pendingEditSend = nil
            },
            onCancelEditSend: { pendingEditSend = nil }
        )
        .onChange(of: errorMessage) { _, newValue in
            // G-03（§389）：横幅详情/时刻与
            // errorMessage 同生命周期——字面赋值点
            // （未走 presentError）在此补记出现时
            // 刻；presentError 同点已记者不覆写；
            // 清空时详情/时刻/展开态一并清，不许
            // 上一条的详情残挂到下一条上
            if newValue != nil {
                if errorOccurredAt == nil {
                    errorOccurredAt = Date()
                }
            } else {
                errorDetail = nil
                errorOccurredAt = nil
                errorDetailExpanded = false
            }
        }
    }

    /// body 的 onAppear 闭包体（整段抽出为方法：
    /// 巨链上只留一行调用——闭包内联百行语句曾
    /// 令类型检查器在链上超时，CI 实证 2026-11-20）
    private func handleChatAppear() {
        // H2-a：进对话页刷新朗读可用性（节流在播
        // 放器内；拉不到保持未知、菜单先按未确认
        // 处理，不造假）
        SpeechPlayer.shared.refreshAvailabilityOnAppear(
            appState: appState
        )
        // 0.36.6：语音控制器回调接线——识别文本回
        // 写 input（落稿后即普通草稿、可改可发）；
        // 预备页选键盘听写时聚焦输入框
        dictation.onTextChange = { text, _ in
            input = text
        }
        // 0.36.17：听写发送钮——控制器保证先落稿
        // 回写 input、后触发本回调，本处只管走正
        // 常发送路（send 自带空文/在飞守卫）
        dictation.onSendRequest = {
            send()
        }
        dictation.onUseKeyboardDictation = {
            composerFocusHandle.focus()
        }
        // 0.36.15：进聊天页即预热语音分析器（背
        // 景构造＋资产确保＋prepareToAnalyze），
        // 点麦克风时只剩开录与喂入——首结果 10
        // 秒迟到的对症面（DESIGN-V4 §80）
        dictation.armPreheat()
        // 0.7.0（D1 主线钦定）：先落钦定——存量钦定且
        // 线程还在则沿用，否则新建本地主线并钦定。
        // （0.30.0 注：0.7.0 的「冷启落点永远先落主
        // 线」已被用户 12:56 录屏纠正作废——落点改
        // 走下方 ChatLandingResolution 恢复上次线
        // 程，本步只保证钦定主线存在、供解析兜底）
        let mainID = ensureMainThread()
        // 0.4.5：同理补消费抽屉线程选择（从其他格开
        // 抽屉选线程切过来时，本页可能尚未挂载、
        // onChange 不重放）
        if let id = appState.router.drawerThreadSelection {
            appState.router.drawerThreadSelection = nil
            currentThreadID = id
        } else if appState.router.pendingChatSessionID == nil {
            // 0.30.0（用户 12:56 录屏点名 Muse 模
            // 型，取代 0.7.0「冷启永远先落主线」）：
            // 落点走 Core ChatLandingResolution——
            // 进程内已在某线程（页签切回）保持、冷
            // 启恢复上次线程、记录失效回主线；显式
            // 回主线只剩抽屉「主线聊天」行一个入口
            switch ChatLandingResolution.landing(
                currentID: currentThreadID,
                lastThreadID: appState.sideChats.lastThreadID,
                existingIDs: threads.map(\.id),
                mainThreadID: mainID
            ) {
            case .keep(let id), .restore(let id), .main(let id):
                if currentThreadID != id {
                    currentThreadID = id
                }
            case .none:
                // 当前/上次/主线均不在名单（钦定失败
                // 的极端情形）：沿旧兜底落第一条
                if currentThread == nil {
                    currentThreadID = threads.first?.id
                }
            }
        }
        // 0.36.7：当前线程初始同步为抽屉当前对象
        // 引用（口径同 currentThreadID 变更点；
        // 0.36.29 改经同一同步函数、含频道出处）
        syncDrawerObjectFromCurrentThread()
        // 台账 148：首现线程同口径解析未读分界锚
        // （onChange 只管其后的切换）
        refreshUnreadAnchor()
        // 本页首次出现时若已有待续聊会话（如从其他格
        // 首次切入），onChange 可能先于挂载发生、在此补消费
        if let id = appState.router.pendingChatSessionID {
            Task { await consumePendingChatSession(id) }
        }
        // 0.27.0：主线链接预热（未链才走；失败原因
        // 落 SideChatStore 设置页可见、发送前还会
        // 再试——旧「失败静默」口径已作废）
        Task { await ensureMainLink() }
        // 0.32.1（F05 止血）：原选模型已停用、选择
        // 被落回默认时的一次性如实提示——消费后落
        // 回值落盘、不再重现；已有提示在显时不抢占
        if let modelNotice = appState.modelFallbackNotice {
            if !noticePresentation.isPresenting {
                showNotice(modelNotice)
            }
            appState.consumeModelFallbackNotice()
        }
        // §232：恢复提醒若在本页出现前已置位（续
        // 跑失败等），onChange 不补发——在此与模型
        // 落回提示同口消费一次
        if let deletionNotice =
            appState.sessionDeletionFailureNotice {
            if !noticePresentation.isPresenting {
                showNotice(deletionNotice, tier: .persistent)
            }
            appState.consumeSessionDeletionFailureNotice()
        }
    }

    /// 朗读播放条（台账 183；D1 台账 5 补暂停/继
    /// 续）：形态沿本页条族画法（发丝线＋pageBG＋
    /// gutter 横距，与 noticeBar 同族）；参照
    /// OpenBot voice-call-bar「声音正在出声时、控
    /// 制面就长在输入舱上」——文案（Core 派生）＋
    /// 主钮＋停止次钮常驻可见。主钮随状态机态切
    /// 换：播放中＝暂停、已暂停＝继续（引擎 pause/
    /// play 保断点）；请求中尚无音频实例、无可暂
    /// 停之物，主钮不显、只留停止。停止走 Speech-
    /// Player.stop() 既有出口（与离页/发送/听写共
    /// 用同一停因口）。分工裁定（D1 对位表）：暂
    /// 停/继续只住本条，长按菜单的朗读项保持朗读/
    /// 停止朗读二义，不加第三义
    private var speechPlaybackBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: MessageActionSymbols.speak)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
                Text(
                    SpeechPlayer.shared.machine
                        .playbackBarText ?? ""
                )
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                Spacer()
                // 主钮（D1）：暂停/继续随态切换——播
                // 放中显暂停、已暂停显继续；请求中不
                // 显主钮（见函数头注）
                switch SpeechPlayer.shared.machine.state {
                case .playing:
                    speechBarButton(
                        symbol: MessageActionSymbols.speakPause,
                        title: "暂停", label: "暂停朗读",
                        style: Palette.ink
                    ) { SpeechPlayer.shared.pause() }
                case .paused:
                    speechBarButton(
                        symbol: MessageActionSymbols.speakResume,
                        title: "继续", label: "继续朗读",
                        style: Palette.ink
                    ) { SpeechPlayer.shared.resume() }
                case .requesting, .idle, .failed:
                    EmptyView()
                }
                // 次钮：停止（放弃本次朗读）
                speechBarButton(
                    symbol: MessageActionSymbols.speakStop,
                    title: "停止", label: "停止朗读",
                    style: Palette.inkSecondary
                ) { SpeechPlayer.shared.stop() }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.vertical, OneDayMetrics.spacingXS)
        }
        .background(Palette.pageBG)
    }

    /// 播放条按钮画法（D1：主钮/停止钮同族单源）：
    /// 图标＋文案横排，命中域 44（条族审计口径）——
    /// 字形行高不变、命中纵向撑满条高
    private func speechBarButton(
        symbol: String, title: String, label: String,
        style: some ShapeStyle, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingXS) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                Text(title)
                    .font(.subheadline)
            }
            .foregroundStyle(style)
            .frame(minHeight: OneDayMetrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .buttonStyle(.odPressable)
    }

    /// 回到底部圆钮（0.2.4 曾换原生玻璃；0.3.8 第 28 条
    /// 浮件统一白浮纸——圆钮全体同画法；外壳结构包
    /// §178：本体材质由白浮纸改回系统玻璃
    /// .glassEffect(.regular)——与顶栏圆钮（本文件
    /// 1076/1122）同画法，属材质换代、与边缘溶化带
    /// 样式无关；34 视觉盘/44 命中域/角标层全不动）
    /// 台账 197（§335，2026-11-21）：盘面材质再改
    /// 判——primaryPale 实填（对齐 Muse 样板回底
    /// 钮实填圆盘），§178 玻璃统一在此一处例外；
    /// 字形与角标、尺寸口径全不动
    /// 0.41.0（收口批）：离底未读角标——计数出自 Core
    /// AwayUnreadCounter（displayText 封顶 99+），挂视
    /// 觉盘右上；点钮即清零（回底的 ingest 随后以在底
    /// 事实复核、水位推进，不双计）
    private func scrollToBottomButton(
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            awayUnread.reset()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                // 台账 197（§335）：盘面由系统玻璃改
                // primaryPale 实填（样板 Muse 回底
                // 钮为浅蓝实填圆盘＋黑箭头）——§178
                // 「浮件统一系统玻璃」在此一处例外改
                // 判，顶栏圆钮/顶簇/状态胶囊维持玻璃
                // 不扩围；字形 ink、角标配对、34 盘/
                // 44 命中域全不动
                .background(Palette.primaryPale, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if let badge = awayUnread.displayText {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            // 第 85 条（BC-1）：角标改走主钮
                            // 正道配对 primaryPale＋onPrimary
                            // （旧白字压 primaryFill 暗档 2.33）
                            .foregroundStyle(Palette.onPrimary)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(
                                Palette.primaryPale, in: Capsule()
                            )
                            .offset(x: 5, y: -5)
                            .accessibilityHidden(true)
                    }
                }
                // 0.23.0（命中域审计）：视觉盘 34 不变、
                // 命中域外扩 44（与顶栏圆钮同口径）
                .frame(
                    width: OneDayMetrics.minTapTarget,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(
            awayUnread.count > 0
                ? "回到底部，\(awayUnread.count) 条新消息"
                : "回到底部"
        )
    }

    // MARK: - 新承载（§257 换代包 3）


    // MARK: - 原生重建面（§291 R1）

    /// 原生面列表：根容器（ChatNativeListView，
    /// R2 起输入舱收编入容器子托管、落位 §302
    /// 起回 §194 通知帧顶常量形态）＋顶簇宿主 overlay
    /// （§195 不变）＋跟随处理链（与 gen3 面同一
    /// 条链——链内命令经 surface* 分发器派生到当
    /// 前面，见各共享函数）。页面级修饰在
    /// chatSurface 链上共享，本面只管列表本体与回
    /// 底钮浮层
    private var nativeListSurface: some View {
        // §331：量测台发布代次入 body 依赖——后台
        // 量测回填缓存后 bump、本面以确定高重喂
        _ = rowMeasureDesk.publishedRevision
        let fedRows = nativeRows()
        return ChatNativeListView(
            rows: fedRows,
            // §374 步骤 2 转正：开关开时本趟变更集
            // （nativeRows 内追踪器 ingest 刚产出、
            // 存 lastChangeSet）一并交付控制器走
            // applyChanges；关时 nil、旧路 apply
            changeSet: chatListIncrementalEnabled
                ? feedChangeTracker.lastChangeSet
                : nil,
            layout: ChatNativeLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: OneDayMetrics.spacingS,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            // 喂入（§293 R2 收口）：顶留位＝窗口顶
            // 安全区实测＋顶簇实高（§195 记账不
            // 变）；底侧不再喂数——舱内容本体交容
            // 器子托管（落位由容器内 §302 通知帧
            // 顶常量驱动），底 inset 由容器以舱实
            // 测帧派生。§194 快照（kbSnapshot）自
            // §302 起在本面同源供数：容器内同一通
            // 知解析点经 keyboardFrame 绑定喂本页
            // kbFrameUpdate（与旧面 ComposerGuide-
            // Host 同一口径、同一份快照）——R2 期
            // 「快照与本面脱钩」就此收口（定因 K2）
            // §321：顶留位改认顶簇底缘实测单源
            // （nativeFedTopInset：量得即认顶簇在窗
            // 口里的真实底边、未量得回落上方 §195
            // 相加口径）——治 .65 真机录屏「列表顶
            // 部滑到浮动顶栏下被遮」：旧相加口径的
            // 两个种子数在本面无同源实测兜底（顶安
            // 全区种子在本面无回写者），与顶簇真实
            // 底边可差一整段安全区量级
            topInset: nativeFedTopInset,
            bottomMargin: OneDayMetrics.spacingM,
            composerView: AnyView(
                bottomBar(
                    showsArrowRow: false,
                    onScrollToBottom: {
                        scrollToBottom(
                            animated: true
                        )
                    }
                )
            ),
            keyboardFrame: $kbFrameUpdate,
            arrowView: surfaceArrowView,
            handle: nativeHandle,
            callbacks: nativeCallbacks,
            edgeScrollHandle: listScrollHandle,
            // 台账 190②：就地量测口——布局提供者
            // 对将入视口的临界行经此同步取确定高
            // （量测台 measureNow，单行毫秒级）
            exactHeightProvider: { rowKey in
                rowMeasureDesk.measureNow(rowKey: rowKey)
            }
        )
        .ignoresSafeArea(edges: [.top, .bottom])
        .overlay { topBarHostOverlay }
        .onChange(of: currentThread?.sortedEntries.count) { _, _ in
            applyBottomProximity(
                distance: bottomDistanceRecorder.latest
            )
            if isNearBottom {
                scrollToBottom(animated: false)
            }
            feedAwayUnread()
        }
        .onChange(of: sendPinToken) { _, _ in
            awayUnread.noteOwnSend(
                entryIDs: currentThread?.sortedEntries.map(\.id) ?? []
            )
            isNearBottom = BottomFollowPolicy.nearBottomAfterOwnSend()
            scrollToBottom(animated: false)
        }
        .onChange(of: currentThreadID) { oldID, newID in
            handleThreadSwitch(oldID: oldID, newID: newID)
        }
        // §293（R2／H8）→§302：本面在 ChatView 侧
        // 仍不订阅键盘通知、不走键盘锚定挂账链
        // （anchorToBottomAfterKeyboardCarrier 一
        // 族是 §194 时代的补偿机制）——键盘升降
        // 的跟随由容器内通知链承接：容器自持订阅
        // 以帧顶常量驱动舱帧（§302 回 §194 形
        // 态）→容器布局拍逐帧对账 inset→在底同拍
        // 钉底（ChatRootViewController viewDid-
        // LayoutSubviews）。快照供数同出容器内解
        // 析点（keyboardFrame 绑定，见上方喂入
        // 注），本页根 onChange(kbFrameUpdate) 整
        // 包入快照与旧面共用、不分面。gen3 面同
        // 链照旧（其订阅在 gen3 面内）
        .task(id: currentThreadID) {
            guard let id = currentThreadID else { return }
            if ChatListAnchorStore.anchor(for: id) != nil
                || appState.sideChats.scrollAnchor(for: id) != nil {
                restoreThreadPosition(for: id)
            } else {
                firstFrameSettle(for: id)
            }
        }
    }

    /// 原生面回调：与 carrierCallbacks 同式——几何
    /// 读数先同步进引用匣、判定推下一拍；读数源换
    /// 原生句柄
    private var nativeCallbacks: ChatNativeListCallbacks {
        ChatNativeListCallbacks(
            onScrollGeometry: {
                bottomDistanceRecorder.latest =
                    nativeHandle.latestDistance
                bottomDistanceRecorder.contentEndVisible =
                    nativeHandle.contentEndVisible
                bottomDistanceRecorder.containerHeight =
                    nativeHandle.containerHeight
                bottomDistanceRecorder.bottomInset =
                    nativeHandle.bottomInset
                DispatchQueue.main.async {
                    applyBottomProximity(
                        distance: bottomDistanceRecorder.latest
                    )
                    evaluateSettleOnEvent()
                }
            },
            onTopVisibleEntry: { entryID in
                // 台账 190①：顶可见行锚同步报量测
                // 台（方向感知投单的输入；只记账、
                // 不触发重渲，与本回调的几何读数同
                // 纪律）；行键与 nativeEntryRow 同源
                if let entryID {
                    rowMeasureDesk.noteTopVisible(
                        rowKey: streamSettleMap.rowKey(
                            for: entryID
                        ) ?? "entry-\(entryID.uuidString)"
                    )
                }
                DispatchQueue.main.async {
                    if topVisibleEntryID != entryID {
                        topVisibleEntryID = entryID
                    }
                }
            },
            onBlankTap: {
                composerFocusHandle.dismiss()
            }
        )
    }


    /// 容器 overlay 回底钮的视图供给：显隐与角标与
    /// 旧承载同一派生（showsBackToBottomButton＋
    /// AwayUnreadCounter），钮本体与旧承载共用同一
    /// 构建（scrollToBottomButton），只有承载与动
    /// 作口换
    private var surfaceArrowView: AnyView? {
        guard showsBackToBottomButton else { return nil }
        return AnyView(
            scrollToBottomButton(action: {
                scrollToBottom(animated: true)
            })
        )
    }


    // MARK: 新承载行构建


    // MARK: 原生面行构建（§291 R1）

    /// 原生面行集组装：落定行全集与 carrierRows()
    /// 同源同序（渲染计划条目/工具组→直播区→回
    /// 告卡→审批区→空状态）。直播区自 R2 起逐项
    /// 入快照（§293，见 nativeLiveRow）；R1 期曾
    /// 整段一块以 live-zone 不透明 item 喂入，该
    /// 形态自此退役。§325 起修订值口径换结构化
    /// 派生（条目快照/卡与通知编码本体/锚定集本
    /// 体逐值入账），不再复用 gen3 的版本与估算
    private func nativeRows() -> [ChatNativeRow] {
        // 卡顿探针（2026-11-20）：每趟喂入耗时＋行
        // 构建/复用数——只记账、无行为影响
        let probeToken = ChatLagProbe.beginFeedPass()
        let probeBuildBase = nativeRowMemo.buildCount
        let probeReuseBase = nativeRowMemo.reuseCount
        defer {
            ChatLagProbe.endFeedPass(
                probeToken,
                built: nativeRowMemo.buildCount
                    - probeBuildBase,
                reused: nativeRowMemo.reuseCount
                    - probeReuseBase,
                streaming: isStreaming
            )
        }
        var rows: [ChatNativeRow] = []
        // §329：行高合成器（每趟行构建现建——环境
        // 口径[字阶/粗体/屏宽]与本趟同值；账本为
        // 本视图 @State、跨趟同实例）
        let composer = ChatNativeRowHeightComposer(
            screenWidth: UIScreen.main.bounds.width,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: dynamicTypeSize
                .contentSizeCategory,
            boldText: environment.legibilityWeight == .bold,
            displayScale: UIScreen.main.scale,
            ledger: rowStateLedger,
            hubStore: appState.sharedHubStore(),
            agentDisplayName: appState.agentDisplayName,
            emptyStateAvatarSize: avatarTier
                .emptyStatePointSize
        )
        // 样式键每趟只算一份（旧形态逐行重算）：行
        // 修订与备忘戳共用本值
        let styleKey = nativeRowStyleKey
        // §362：本趟在席条目集（行构建备忘趟末清账用）
        var seenEntryIDs: Set<UUID> = []
        if let thread = currentThread {
            let plan = renderPlan(for: thread)
            for item in plan.items {
                switch item {
                case .entry(let entry):
                    seenEntryIDs.insert(entry.id)
                    rows.append(
                        nativeEntryRow(
                            entry,
                            dividerText: plan.dividers[entry.id],
                            sources: plan.sources[entry.id] ?? [],
                            optionsCard: optionsCardHeightInput(
                                for: entry, in: thread
                            ),
                            composer: composer,
                            styleKey: styleKey
                        )
                    )
                }
            }
        }
        // §407（预排版步骤 1·A 案简化模型）：直播
        // 区收成一行定高占位行——生成中只显状态、
        // 回复成型后整条以终态高落定（落定条目行
        // 走既有条目路入列、占位行同趟移除，offset
        // 修正只走既有锚定路径）。§293 的逐项直播
        // 行（思考/封存段/打开段/工具卡逐项成行、
        // 高度随内容生长）自此退出原生喂入；
        // nativeLiveRow 本体已随 §409 步 A 删除。
        // 在飞判定：sendTask 在席（起手至落定全
        // 程，含首词元前的上传/等待段）∨ active-
        // RunThreadID 在席（对账恢复等无 sendTask
        // 的在飞形态，§409 步 A 改判——旧「直播项
        // 非空」随直播呈现退役失去来源）
        if sendTask != nil || activeRunThreadID != nil {
            // §494：首个发布快照到达后占位行原位
            // 换直播正文行（同键落定不换装，见
            // liveStreamingRow）；未到/未武装/半
            // 截在屏时仍走占位行（§407 形态不变）
            if let liveRow = liveStreamingRow(
                composer: composer
            ) {
                rows.append(liveRow)
            } else {
                rows.append(
                    livePlaceholderRow(composer: composer)
                )
            }
        }
        if let overviewStore {
            for item in ReportCardPolicy.cards(
                notifications: overviewStore.notifications,
                isMainThread: isCurrentMainThread
            ) {
                var reportRevision = ChatNativeRowRevision()
                reportRevision.addData(
                    try? JSONEncoder().encode(item)
                )
                // §331：回告卡行高同走量测台
                let reportMemoKey =
                    composer.reportMemoKey(item)
                let reportRowKey = "report-\(item.id)"
                let reportResolved =
                    rowMeasureDesk.resolve(
                        memoKey: reportMemoKey,
                        rowKey: reportRowKey,
                        fallback:
                            ChatNativeRowHeightComposer
                                .fallbackHeight
                    )
                if reportResolved.needsJob {
                    rowMeasureDesk.collect(
                        composer.makeReportMeasureJob(
                            item, memoKey: reportMemoKey,
                            rowKey: reportRowKey
                        )
                    )
                }
                rows.append(
                    ChatNativeRow(
                        key: "report-\(item.id)",
                        entryID: nil,
                        revision: reportRevision,
                        height: reportResolved.height,
                        heightIsProvisional:
                            !reportResolved.isExact,
                        makeView: {
                            AnyView(
                                reportCard(
                                    item, store: overviewStore
                                )
                            )
                        }
                    )
                )
            }
        }
        var approvalRevision = ChatNativeRowRevision()
        for recordID in appState.sharedHubStore()
            .anchoredRecordIDs.sorted() {
            approvalRevision.addText(recordID)
        }
        // §331：审批区行高同走量测台；但非 ready
        // 态高恒 0、无文本量测可言——同步确知，不
        // 走兜底高（免冷开时列表尾凭空闪 120 空行）
        let zoneHeight: CGFloat
        var zoneIsProvisional = false
        if case .ready = appState.sharedHubStore()
            .approvalState {
            let zoneMemoKey = composer.zoneMemoKey()
            let zoneResolved = rowMeasureDesk.resolve(
                memoKey: zoneMemoKey,
                rowKey: "approval-zone",
                fallback: ChatNativeRowHeightComposer
                    .fallbackHeight
            )
            zoneIsProvisional = !zoneResolved.isExact
            if zoneResolved.needsJob {
                rowMeasureDesk.collect(
                    composer.makeZoneMeasureJob(
                        memoKey: zoneMemoKey,
                        rowKey: "approval-zone"
                    )
                )
            }
            zoneHeight = zoneResolved.height
        } else {
            zoneHeight = composer.approvalZoneHeight()
        }
        rows.append(
            ChatNativeRow(
                key: "approval-zone",
                entryID: nil,
                revision: approvalRevision,
                height: zoneHeight,
                heightIsProvisional: zoneIsProvisional,
                makeView: { [rowStateLedger] in
                    AnyView(
                        ChatApprovalZone(
                            store: appState.sharedHubStore(),
                            anchoredRecordIDs: appState
                                .sharedHubStore().anchoredRecordIDs,
                            ledger: rowStateLedger
                        )
                    )
                }
            )
        )
        if ChatEmptyState.shows(
            threadIsNil: currentThread == nil,
            entryCount: currentThread?.sortedEntries.count ?? 0,
            isStreaming: isStreaming
        ) {
            rows.append(
                ChatNativeRow(
                    key: "empty-suggestions",
                    entryID: nil,
                    height: composer.emptySuggestionsHeight(texts: StarterSuggestionsAssembly.currentSuggestions(appState: appState).map(\.text)),
                    makeView: { AnyView(emptyStateSuggestions) }
                )
            )
            if showsModelSetupCard {
                rows.append(
                    ChatNativeRow(
                        key: "empty-modelsetup",
                        entryID: nil,
                        height: composer.modelSetupCardHeight(),
                        makeView: {
                            AnyView(
                                modelSetupCard.padding(
                                    .top, OneDayMetrics.spacingL
                                )
                            )
                        }
                    )
                )
            }
        }
        // §331：本趟收集的量测工单统一投递（逆序
        // ——最新行先量先就绪）
        rowMeasureDesk.flushCollected()
        // 行描述备忘趟末清账：只留本趟在席行键
        nativeRowMemo.prune(
            keeping: Set(rows.map(\.key))
        )
        // §362：行构建备忘同趟清账（只留在席条目）
        rowBuildMemo.prune(keeping: seenEntryIDs)
        // §374 影子比对（开关开时）：新路变更集与
        // 旧路修订差集逐趟对账入影子账；喂入仍走
        // 本行数组旧路、控制器一行不动
        if chatListIncrementalEnabled {
            feedChangeTracker.ingest(rows: rows)
        }
        return rows
    }

    /// 原生面条目行：与 carrierEntryRow 同键（落
    /// 定映射命中沿用流式行键），只换行描述类型。
    /// §325（B 档）：单渲染路径——全体落定行统一
    /// 托管（R3 散文规格/原生 cell 退役，资格判定
    /// nativeProseSpec 整件删除）；修订值由条目模
    /// 型全字段快照结构化派生（ChatNativeRowRevi-
    /// sion.entry 单点），环境侧输入（分隔/点亮/
    /// 选区/样式键）同列入账——不再有手折版本哈
    /// 希与产物层行高估算
    private func nativeEntryRow(
        _ entry: ChatEntry, dividerText: String?,
        sources: [MessageSource],
        optionsCard: OptionsCardHeightInput? = nil,
        composer: ChatNativeRowHeightComposer,
        styleKey: String
    ) -> ChatNativeRow {
        let settledKey = streamSettleMap.rowKey(for: entry.id)
        let key = settledKey ?? "entry-\(entry.id.uuidString)"
        // 台账 148：NEW 分界线只挂未读锚条目（本次
        // 观看定格，见 refreshUnreadAnchor）
        let showsUnread = entry.id == unreadAnchorEntryID
        // 2026-11-20 卡顿修复包：修订基段每趟只建
        // 一遍——量测键与行修订共用同一基段（旧形
        // 态两路各建一份全量快照、是每遍双构建的
        // 一半）；行修订＝基段＋点亮/样式键尾段
        // §362：基段走行构建增量备忘——快照验证命
        // 中直取账面前缀（未变行免全文哈希）；Prod-
        // ucts 穿线给下方备忘键组装（facet 扫描派
        // 生同账），本趟本行只验证一次
        let buildProducts = rowBuildMemo.products(for: entry)
        var baseRevision = rowBuildMemo.baseRevision(
            products: buildProducts,
            dividerText: dividerText,
            showsUnreadDivider: showsUnread
        )
        // D4 (§349): the source set folds into the
        // shared base revision -- the measure key and
        // the row revision share this base, so a
        // changed source set re-keys both the measure
        // job and the row description in the same pass
        for source in sources {
            baseRevision.addText(source.url)
            baseRevision.addText(source.title)
        }
        // §331：行高先查整行备忘（命中＝确定高）；
        // 未命中投量测台后台预排版、当趟用上次高/
        // 兜底高，回填后经发布代次以确定高重喂
        let memoKey = composer.entryMemoKey(
            baseRevision: baseRevision, entry: entry,
            buildProducts: buildProducts,
            optionsCard: optionsCard
        )
        let resolved = rowMeasureDesk.resolve(
            memoKey: memoKey, rowKey: key,
            fallback: ChatNativeRowHeightComposer
                .fallbackHeight
        )
        if resolved.needsJob {
            rowMeasureDesk.collect(
                composer.makeEntryMeasureJob(
                    for: entry,
                    dividerText: dividerText,
                    showsUnreadDivider: showsUnread,
                    sources: sources,
                    optionsCard: optionsCard,
                    memoKey: memoKey, rowKey: key
                )
            )
        }
        // §407（预排版步骤 1·预定高）：本会话刚发
        // 出的用户行不等后台回填——工单已收集/在飞
        // 时就地同步量测（measureNow 同口：单行毫
        // 秒级、与量测台同源同值），入列即确定终
        // 态高；台上无单可量（极端时序）时回落既有
        // 预计算/兜底口径。作用域只限本会话新行：
        // 历史行同步量测会把成本压回主线程、正是
        // 量测台要避的，故不扩围
        var feedIsExact = resolved.isExact
        var urgentHeight: CGFloat? = nil
        if !resolved.isExact, entry.role == "user",
           sessionSentEntryIDs.contains(entry.id) {
            urgentHeight = rowMeasureDesk.measureNow(
                rowKey: key
            )
            if urgentHeight != nil {
                feedIsExact = true
            }
        }
        let highlighted = entry.id == anchorHighlightEntryID || entry.id == findHighlightEntryID
        // 台账 190 留账·nanoMuse 三件②（§335）：量
        // 测未就绪时先问预计算——产物段高＋合成器
        // facet 公式合成的近确值（与本行当前内容
        // 同文、文本段是真量测值），优先于上次高/
        // 兜底 120；产物缺失/不适用（用户行宽口径
        // 闸、非条目行无产物）保持旧口径。喂入高
        // 仍标临界（heightIsProvisional 不变）：确
        // 值回填后经发布代次以确高重喂、本行终态
        // 口径零变
        var feedHeight = resolved.height
        if let urgentHeight {
            feedHeight = urgentHeight
        } else if !resolved.isExact,
           let product = entryLayoutProduct(entry),
           let precomputed = composer
            .precomputedEntryHeight(
                for: entry, dividerText: dividerText,
                showsUnreadDivider: showsUnread,
                sources: sources,
                optionsCard: optionsCard,
                product: product
            ) {
            feedHeight = precomputed
        }
        // 行描述备忘戳：构建输入全量（量测键含修订
        // 基段摘要＋facet 摘要＋环境指纹；落定高；
        // 点亮；样式键）——戳不变整行复用上趟描述，
        // makeView/行菜单（含 plainText 提取）只在
        // 戳变时重建。戳内高用最终喂入高（§335：
        // 预计算值变即戳变、行描述随之重建）
        // §503：查找着色口同折入戳——命中行带查询
        // 字面、非命中行恒 "-"，查询/命中集一变命
        // 中行戳变重建（着色增减的唯一失效路）
        let findHL = findHighlightQuery(for: entry.id)
        let stamp = "\(memoKey)|\(feedHeight)"
            + "|\(highlighted ? "1" : "0")|\(styleKey)"
            + "|F:\(findHL ?? "-")"
        // §374 影子记账（开关开时）：本行验证基入
        // 追踪器账——快照取本趟已验证的 Products
        // （本行只验证一次的穿线纪律不变）、环境
        // 尾段与喂入高取本行现值；关时零记账
        if chatListIncrementalEnabled {
            feedChangeTracker.noteEntryBasis(
                ChatFeedEntryBasis(
                    entryID: entry.id,
                    snapshot: buildProducts.snapshot,
                    dividerText: dividerText,
                    showsUnreadDivider: showsUnread,
                    sources: sources,
                    highlighted: highlighted,
                    styleKey: styleKey,
                    feedHeight: feedHeight,
                    heightIsProvisional: !feedIsExact
                )
            )
        }
        return nativeRowMemo.row(key: key, stamp: stamp) {
            var revision = baseRevision
            revision.addFlag(highlighted)
            revision.addText(styleKey)
            revision.addText(findHL.map { "find:\($0)" })
            return ChatNativeRow(
                key: key,
                entryID: entry.id,
                revision: revision,
                height: feedHeight,
                // 台账 190②：非确定高（未量测/上次
                // 高顶替）标临界——布局提供者对将入
                // 视口的临界行就地量测给确定高
                heightIsProvisional: !feedIsExact,
                makeView: {
                    AnyView(
                        entryRowContent(
                            entry, dividerText: dividerText,
                            showsUnreadDivider: showsUnread,
                            sources: sources
                        )
                    )
                },
            )
        }
    }

    /// 条目菜单数据（台账 187 立制；台账 200 拆
    /// 换后供系统上下文菜单）：与旧 nativeRow-
    /// ContextMenu 同门控同动作——动作闭包逐项复
    /// 用既有入口（beginReply/forkToSideChat/朗
    /// 读求值）；选择/分享再呈一层 sheet、经一拍
    /// 主队列延后避开菜单收起竞态；反应排数据
    /// （canReact/现反应）以呈现时刻的条目状态
    /// 为准
    private func actionSheetData(
        for entry: ChatEntry
    ) -> ChatRowActionSheetData {
        let text = plainText(for: entry)
        // 台账 154（DESIGN §336）：发件箱条目的动作
        // 面换发件箱项集——三项闭包只对未发送条目注
        // 入（判定走 isOutboxEntry 单点），落定条目
        // 恒 nil、项集逐项旧样。编辑/撤回经 defer-
        // SheetAction 等本面关净后再执行（编辑要抢
        // 输入舱焦点、撤回要删本行，都不许与关面动
        // 画同拍打架）
        let inOutbox = isOutboxEntry(entry)
        return ChatRowActionSheetData(
            plainText: text,
            canReact: entry.canReact,
            ownEmoji: MessageReactions.ownEmoji(
                in: entry.reactions
            ),
            onPickReaction: { emoji in
                toggleReaction(emoji, for: entry)
            },
            onReply: {
                beginReply(to: entry)
            },
            onFork: {
                forkToSideChat(from: entry)
            },
            onSelect: {
                // 台账 200 拆换：自绘面退役后无 sheet
                // 可等——菜单收起与再呈 sheet 的竞态
                // 以一拍主队列延后避开（原 defer-
                // SheetAction 的意图保留、承载删除）
                DispatchQueue.main.async {
                    selectionPayload = SelectionPayload(
                        text: text
                    )
                }
            },
            onShare: {
                DispatchQueue.main.async {
                    messageSharePayload = MessageSharePayload(
                        text: text
                    )
                }
            },
            onResend: inOutbox ? {
                resumeOutboxEntry(entry)
            } : nil,
            onEditUnsent: inOutbox ? {
                // 合流对账（154×200）：deferSheetAction
                // 已随自绘面退役删除，与上文选择/分享同
                // 口径改一拍主队列延后（意图保留）
                DispatchQueue.main.async {
                    editUnsentEntry(entry)
                }
            } : nil,
            onWithdrawUnsent: inOutbox ? {
                DispatchQueue.main.async {
                    withdrawUnsentEntry(entry)
                }
            } : nil,
            onWithdrawAccepted: acceptedWithdrawAvailable(
                for: entry
            ) ? {
                DispatchQueue.main.async {
                    withdrawAcceptedEntry(entry)
                }
            } : nil,
            onEditSent: editSentAvailable(for: entry) ? {
                DispatchQueue.main.async {
                    editSentEntry(entry)
                }
            } : nil,
            onRegenerate: regenerateAvailable(for: entry) ? {
                DispatchQueue.main.async {
                    regenerateLastTurn(from: entry)
                }
            } : nil,
            makeSpeakItem: {
                speakMenuItem(for: entry)
            }
        )
    }

    /// D3 入口在否（DESIGN §352）：条目级谓词
    /// （canEditSent）＋线程级条件在呈现时刻一并求
    /// 值——已绑服务端会话（rewind 有的放矢）、当
    /// 前线程、无在飞 run/流式
    private func editSentAvailable(for entry: ChatEntry) -> Bool {
        guard entry.canEditSent,
              let thread = entry.thread,
              thread.id == currentThreadID,
              thread.serverSessionID != nil,
              !isStreaming, !isDrivingRun,
              appState.runLedger.entry(forThreadID: thread.id)
                == nil
        else { return false }
        return true
    }

    /// D2 入口在否（DESIGN §352）：本条即本线程最
    /// 后一条已落定助手条目、且其轮可切分（user
    /// 行已钉桩），线程级条件同 D3
    private func regenerateAvailable(
        for entry: ChatEntry
    ) -> Bool {
        guard entry.canRegenerateCandidate,
              let thread = entry.thread,
              thread.id == currentThreadID,
              thread.serverSessionID != nil,
              !isStreaming, !isDrivingRun,
              appState.runLedger.entry(forThreadID: thread.id)
                == nil
        else { return false }
        let entries = thread.sortedEntries
        guard RewindTurnSlicing.lastSettledAssistant(
                  in: entries
              )?.id == entry.id,
              RewindTurnSlicing.regenerationTurn(
                  assistant: entry.id, in: entries
              ) != nil
        else { return false }
        return true
    }

    /// D3 确认弹窗正文（DESIGN §352 §五）：N＝将被
    /// 删除的轮数、呈现时刻实算
    private var editSendConfirmMessage: String {
        let rounds = editSentTarget.flatMap { target in
            currentThread.map {
                RewindTurnSlicing.roundsAfter(
                    target: target.entryID,
                    in: $0.sortedEntries
                )
            }
        } ?? 0
        return "发送后，这条之后的所有对话（共 \(rounds) 轮）都会被删除，包括其中的图片和文件。删掉的内容无法恢复。"
    }

    /// 编辑已发消息（D3，DESIGN §352）：内容回收进
    /// 发送舱＋武装编辑态——与 editUnsentEntry 的
    /// 差别只在原条目去留：已发条目是服务端历史的
    /// 一行，回收时一字不动（不删、不改显），删除
    /// 只发生在发送时 rewind 成功之后。守卫同未发
    /// 编辑口径（发送舱占用先拦、run 在飞先拦）
    private func editSentEntry(_ entry: ChatEntry) {
        guard entry.canEditSent,
              let rowID = entry.serverRowID,
              let thread = entry.thread,
              thread.id == currentThreadID,
              thread.serverSessionID != nil,
              !isStreaming, !isDrivingRun
        else { return }
        guard appState.runLedger.entry(
            forThreadID: thread.id
        ) == nil else {
            showNotice(ledgerBusyNotice(threadID: thread.id))
            return
        }
        guard input.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty,
              attachments.isEmpty, pendingQuote == nil,
              pendingFeedQuote == nil,
              pendingSourceQuote == nil
        else {
            showNotice("输入框里还有没发完的内容，先发掉或清空，再来编辑这条。")
            return
        }
        // 回收：正文/图片/引用走未发编辑同款口；文
        // 件无本地字节可回收（落定轮次的暂存已
        // 清），发送时凭 target 的 remoteFilePaths
        // 预置路径随行（见 performEditSend）
        input = entry.content
        attachments = entry.allImageDatas.map {
            PendingAttachment(kind: .image($0))
        }
        pendingQuote = entry.quote
        switch entry.sourceQuote {
        case .feed(let feedQuote):
            pendingFeedQuote = feedQuote
        case .idea, .file, .goal:
            pendingSourceQuote = entry.sourceQuote
        case nil:
            break
        }
        editSentTarget = EditSentTarget(
            entryID: entry.id, rowID: rowID
        )
        composerFocusHandle.focus()
    }

    /// 解除编辑态（横幅 ✕）：回收稿只是副本、原条
    /// 目在列表里一字未动，清舱无损、无副作用
    private func cancelEditSent() {
        editSentTarget = nil
        input = ""
        attachments = []
        pendingQuote = nil
        pendingFeedQuote = nil
        pendingSourceQuote = nil
    }

    /// D3 发送段（DESIGN §352）：待发条目落盘→乐
    /// 观隐藏 target 起条目→rewind→成功真删旧段
    /// 并汇入既有发送管线（launchTurn，幂等键由
    /// driveRun 现铸）；失败全回滚——服务端未动
    /// （rewind 未成）、用户改过的字回填发送舱一
    /// 字不丢。rewind 成功后禁止回滚：其后失败走
    /// 既有失败标记＋重发链（不再重复 rewind）
    private func performEditSend(
        draft: EditSendDraft, target: EditSentTarget
    ) {
        guard let thread = currentThread,
              let targetEntry = thread.sortedEntries.first(
                  where: { $0.id == target.entryID }
              ),
              let sessionID = thread.serverSessionID
        else {
            editSentTarget = nil
            return
        }
        SpeechPlayer.shared.stop()
        input = ""
        attachments = []
        pendingQuote = nil
        pendingQuoteIsFork = false
        pendingFeedQuote = nil
        pendingSourceQuote = nil
        errorMessage = nil
        dismissNotice()
        let combinedSourceQuote = draft.sourceQuote
            ?? draft.feedQuote.map(SourceQuote.feed)
        let entries = thread.sortedEntries
        let tail = RewindTurnSlicing.tail(
            from: target.entryID, in: entries
        )
        let predecessor = RewindTurnSlicing
            .predecessorRowID(
                before: target.entryID, in: entries
            )
        let imageDatas = draft.attachments.compactMap(
            \.imageData
        )
        let filePayloads = draft.attachments.compactMap(
            \.filePayload
        )
        sendFrameStartedAt = Date()
        sendFrameRestickLogged = false
        let newEntry = ChatEntry(
            role: "user", content: draft.text, thread: thread,
            imageData: imageDatas.first,
            imageDatas: imageDatas,
            quote: draft.quote,
            sourceQuote: combinedSourceQuote
        )
        modelContext.insert(newEntry)
        sessionSentEntryIDs.insert(newEntry.id)
        Haptics.impact(.light)
        thread.updatedAt = Date()
        try? modelContext.save()
        newEntry.markSendState(.queued, in: modelContext)
        if !filePayloads.isEmpty {
            stagedSendStore.stageDetached(
                entryID: newEntry.id,
                payloads: filePayloads.map {
                    StagedSendPayload(
                        name: $0.name, data: $0.data
                    )
                }
            )
        }
        appState.sideChats.setDraft("", for: thread.id)
        editSentTarget = nil
        rewindHiddenEntryIDs = Set(tail.map(\.id))
        // target 本轮文件凭服务端回执路径随行（落
        // 定条目文件牌的唯一数据源即 remoteFile-
        // Paths，resendFailedEntry 同路）：新加文件
        // 走 filePayloads 上传——两路在 launchTurn
        // 的既有口径下预置路径优先
        let presetFilePaths = targetEntry.remoteFilePaths
        rewindTask = Task {
            do {
                _ = try await appState.performAdmin {
                    client, config in
                    try await client.rewindSession(
                        config: config, id: sessionID,
                        targetMessageID: target.rowID,
                        predecessorRowID: predecessor
                    )
                }
            } catch {
                modelContext.delete(newEntry)
                try? stagedSendStore.remove(
                    entryID: newEntry.id
                )
                try? modelContext.save()
                rewindHiddenEntryIDs = []
                input = draft.text
                attachments = draft.attachments
                pendingQuote = draft.quote
                pendingFeedQuote = draft.feedQuote
                pendingSourceQuote = draft.sourceQuote
                showNotice(rewindFailureCopy(
                    error,
                    invalidTarget: "这条消息太早了，没法再编辑。",
                    conflict: "对话刚刚有新变化，这次编辑没生效，原来的对话没有动。再试一次就行。",
                    fallback: "这次编辑没生效，原来的对话没有动。再试一次就行。"
                ), tier: .persistent)
                Haptics.error()
                return
            }
            for entry in tail {
                modelContext.delete(entry)
            }
            try? modelContext.save()
            rewindHiddenEntryIDs = []
            let seedSnapshot = thread.sortedEntries
                .filter {
                    !$0.isPendingSend && $0.id != newEntry.id
                }
                .map {
                    SeedEntry(
                        role: $0.role, content: $0.content,
                        timestamp: $0.createdAt
                            .timeIntervalSince1970
                    )
                }
            let context = outgoingContext(
                of: thread, tailEntry: newEntry,
                text: draft.text, quote: draft.quote,
                sourceQuote: combinedSourceQuote
            )
            launchTurn(
                thread: thread, userEntry: newEntry,
                text: draft.text,
                filePayloads: filePayloads,
                presetFilePaths: presetFilePaths,
                seedSnapshot: seedSnapshot, context: context
            )
        }
    }

    /// 重新生成（D2，DESIGN §352）：一键、不确
    /// 认、不进发送舱——乐观隐藏本轮助手段→
    /// rewind 到本轮 user 行→成功真删助手段、以
    /// 原输入重提（新轮整段替换旧段）；失败显示
    /// 复原＋人话，服务端零残留
    private func regenerateLastTurn(
        from assistantEntry: ChatEntry
    ) {
        guard assistantEntry.canRegenerateCandidate,
              let thread = assistantEntry.thread,
              thread.id == currentThreadID,
              let sessionID = thread.serverSessionID,
              !isStreaming, !isDrivingRun
        else { return }
        guard appState.runLedger.entry(
            forThreadID: thread.id
        ) == nil else {
            showNotice(ledgerBusyNotice(threadID: thread.id))
            Task { await resumeRunIfNeeded() }
            return
        }
        let entries = thread.sortedEntries
        guard let turn = RewindTurnSlicing.regenerationTurn(
                  assistant: assistantEntry.id, in: entries
              ),
              let targetRowID = turn.user.serverRowID
        else { return }
        let userEntry = turn.user
        let segment = turn.segment
        let predecessor = RewindTurnSlicing
            .predecessorRowID(
                before: userEntry.id, in: entries
            )
        errorMessage = nil
        dismissNotice()
        sendFrameStartedAt = Date()
        sendFrameRestickLogged = false
        rewindHiddenEntryIDs = Set(segment.map(\.id))
        rewindTask = Task {
            do {
                _ = try await appState.performAdmin {
                    client, config in
                    try await client.rewindSession(
                        config: config, id: sessionID,
                        targetMessageID: targetRowID,
                        predecessorRowID: predecessor
                    )
                }
            } catch {
                rewindHiddenEntryIDs = []
                showNotice(rewindFailureCopy(
                    error,
                    invalidTarget: "重新生成没成功，原来的回答没有动。再试一次就行。",
                    conflict: "重新生成没成功，原来的回答没有动。再试一次就行。",
                    fallback: "重新生成没成功，原来的回答没有动。再试一次就行。"
                ), tier: .persistent)
                Haptics.error()
                return
            }
            // rewind 已成：助手段真删、user 条目原位
            // 保留。此后禁止回滚——先给 user 条目预
            // 置失败标记作崩溃守卫（rewind 成功至新
            // 轮落定之间被杀：重启后 .failed 走手点
            // 重发链、.queued 走发件箱自动接管，两
            // 路都不重复 rewind），随即按 resend-
            // FailedEntry 同式清标记进队列态、由
            // launchTurn 接管推进
            for entry in segment {
                modelContext.delete(entry)
            }
            userEntry.markSendState(.failed, in: modelContext)
            userEntry.sendFailed = false
            userEntry.markSendState(.queued, in: modelContext)
            rewindHiddenEntryIDs = []
            let filePayloads = resendFilePayloads(
                entryID: userEntry.id
            )
            let seedSnapshot = Array(
                Self.seedEntries(of: thread).dropLast()
            )
            launchTurn(
                thread: thread, userEntry: userEntry,
                text: userEntry.content,
                filePayloads: filePayloads,
                presetFilePaths: userEntry.remoteFilePaths,
                seedSnapshot: seedSnapshot,
                context: outgoingContext(
                    of: thread, tailEntry: userEntry,
                    text: userEntry.content,
                    quote: userEntry.quote,
                    sourceQuote: userEntry.sourceQuote
                )
            )
        }
    }

    /// rewind 失败的人话分流（DESIGN §352 §五）：
    /// 定性两类走调用方专属句（D3/D2 各一份），其
    /// 余走 HermesError 人话体系（登录/服务异常/
    /// busy 各归其类），不露英文码与状态数
    private func rewindFailureCopy(
        _ error: Error, invalidTarget: String,
        conflict: String, fallback: String
    ) -> String {
        if let rewindError = error as? RewindError {
            switch rewindError {
            case .invalidTarget:
                return invalidTarget
            case .conflictExhausted:
                return conflict
            }
        }
        if let hermesError = error as? HermesError {
            return hermesError.userMessage
        }
        return fallback
    }

    /// 点反应（台账 187，toggle 单点）：点自己已点
    /// 的 emoji＝撤回、点别的＝替换/新点——与服务端
    /// Tapback 同点取消同构；写口只有 applyReaction
    private func toggleReaction(
        _ emoji: String, for entry: ChatEntry
    ) {
        let own = MessageReactions.ownEmoji(
            in: entry.reactions
        )
        applyReaction(own == emoji ? nil : emoji, for: entry)
    }

    /// 反应写口（台账 187）：乐观先行改镜像（行高
    /// facet 与 pill 同拍翻）→端点回执覆写自愈→失
    /// 败回滚＋人话提醒（showNotice 既有口）。凭据
    /// 只读既有真源（当前连接配置＋登录密钥，与认
    /// 领出码同路、不走 performAdmin 的面板会话通
    /// 道——反应端点是网关 Bearer 面）；坐标/凭据缺
    /// 一即不发（门控谓词 canReact 已先拦，此处是
    /// 写口自守，不许乐观改了却无处落定）
    private func applyReaction(
        _ emoji: String?, for entry: ChatEntry
    ) {
        guard entry.canReact,
              let rowID = entry.serverRowID,
              let sessionID = entry.thread?.serverSessionID
                ?? currentThread?.serverSessionID,
              let config = appState.config,
              let apiKey = appState.apiKey
        else { return }
        let previous = entry.reactions
        entry.applyReactions(
            MessageReactions.applying(
                own: emoji, to: previous,
                at: Date().timeIntervalSince1970
            )
        )
        try? modelContext.save()
        let client = appState.client
        Task { @MainActor in
            do {
                let update: ReactionUpdate
                if let emoji {
                    update = try await client.setReaction(
                        config: config, apiKey: apiKey,
                        sessionID: sessionID, rowID: rowID,
                        emoji: emoji
                    )
                } else {
                    update = try await client.clearReaction(
                        config: config, apiKey: apiKey,
                        sessionID: sessionID, rowID: rowID
                    )
                }
                // 回执覆写自愈：服务端全集为准（乐观
                // 组装与服务端 Tapback 结果同构、此覆
                // 写通常同值不落写）
                entry.applyReactions(update.reactions)
                try? modelContext.save()
            } catch let error as HermesError {
                entry.applyReactions(previous)
                try? modelContext.save()
                showNotice(error.userMessage, tier: .persistent)
            } catch {
                entry.applyReactions(previous)
                try? modelContext.save()
                showNotice(
                    L10n.string("反应没发出去，请稍后再试。"),
                    tier: .persistent
                )
            }
        }
    }

    /// 朗读菜单项（H2-a，台账 159）：双承载共用的
    /// 门控与求值——只给助手落定回复（工具卡/回响/
    /// 锚定条目不是助手发言，用户消息不在此列），
    /// 可用性已被实调证伪（未开通）时不出项（施工
    /// 图失败降级表）；标题/图符按求值时刻的播放
    /// 态（原生面＝呈现时刻、SwiftUI 面＝body 时刻）
    private func speakMenuItem(
        for entry: ChatEntry
    ) -> ChatRowSpeakItem? {
        guard entry.role == "assistant",
              !entry.content.isEmpty,
              entry.toolCardData == nil,
              entry.echoKey == nil,
              entry.approvalKey == nil else { return nil }
        let player = SpeechPlayer.shared
        guard player.availability != .unavailable
        else { return nil }
        let entryID = entry.id
        let content = entry.content
        return ChatRowSpeakItem(
            title: player.machine.menuTitle(for: entryID),
            systemImage: player.machine.isActive(
                entryID: entryID
            ) ? MessageActionSymbols.speakStop
                : MessageActionSymbols.speak,
            action: {
                player.toggle(
                    entryID: entryID, content: content,
                    appState: appState
                )
            }
        )
    }

    /// 行样式键（§325 前身为 R3 散文拼装键）：与
    /// SelectableInlineText 的拼装缓存键同因子
    /// （字阶/字号档/粗体/前景与次级墨的解析
    /// 值）——环境一变键即变、行修订值随之翻新、
    /// 托管行原位重渲
    private var nativeRowStyleKey: String {
        func components(_ color: Color) -> String {
            color.resolve(in: environment).cgColor
                .components?
                .map { "\($0)" }.joined(separator: ",")
                ?? ""
        }
        return [
            dynamicTypeSize.contentSizeCategory.rawValue,
            environment.legibilityWeight == .bold
                ? "b" : "r",
            components(Palette.bodyInk),
            components(Palette.inkSecondaryOnFill),
            components(Palette.userBubbleText),
            aiSelfReactionsEnabled ? "ai1" : "ai0",
        ].joined(separator: "|")
    }

    /// 直播占位行（§407）：键恒定、高＝合成器常
    /// 量 livePlaceholderHeight，修订只折状态文
    /// 案——阶段切换原地重配、高度逐值不变；落
    /// 定拍本行移除＋落定条目行入列（变更集由既
    /// 有追踪器派生、offset 走既有锚定路径）
    /// §494 直播正文行：键＝本轮流式行键（落定
    /// 条目同键建行、承载侧原位 reconfigure＝落
    /// 定不换装，§247 身份桥）；高＝逐块估算
    /// （闭合块备忘命中、只尾块新算，见 Stream-
    /// ingLiveText.estimatedHeight）＋气泡纵内
    /// 距，标临界走布局量实回填（估算起步＋量
    /// 实覆盖，§247 行高口径）。出 Nil 的四种
    /// 情形：gen4 开关关（回占位行旧形态＝天然
    /// 回滚路）／未武装（恢复轮）／尚无发布快
    /// 照（首增量未到）／半截条目在屏（防双份）
    private func liveStreamingRow(
        composer: ChatNativeRowHeightComposer
    ) -> ChatNativeRow? {
        guard gen4StreamingEnabled,
              streamPresentationArmed,
              !livePublishedText.isEmpty,
              livePartialEntryIDs.isEmpty
        else { return nil }
        let text = livePublishedText
        var revision = ChatNativeRowRevision()
        revision.addText(text)
        revision.addCount(livePublishGeneration)
        return ChatNativeRow(
            key: liveStreamRowKey(),
            entryID: nil,
            revision: revision,
            height: StreamingLiveText.estimatedHeight(
                    for: text, composer: composer
                )
                + OneDayMetrics.bubblePaddingV * 2,
            heightIsProvisional: true,
            makeView: {
                AnyView(liveStreamingContent(text: text))
            }
        )
    }

    /// 本轮流式行键：账本在席取本轮用户条目 id
    /// 派生（与 applySettledTurn 落定登记同源同
    /// 值）；账本缺位（演示种子轮等）回落线程键
    /// （StreamingRowIdentity 既有回落口径）
    private func liveStreamRowKey() -> String {
        let ledger = (activeRunThreadID ?? currentThread?.id)
            .flatMap {
                appState.runLedger.entry(forThreadID: $0)
            }
        if let ledger {
            return StreamingRowIdentity.streamRowKey(
                userEntryID: ledger.userEntryID
            )
        }
        if let threadID = currentThread?.id {
            return StreamingRowIdentity
                .fallbackStreamRowKey(threadID: threadID)
        }
        return "stream-live"
    }

    /// 直播行视图：助手泡（不传 menuEntry——流
    /// 式泡无菜单、形态与落定泡逐字同，见 assi-
    /// stantBubble 注）＋块级正文；入场计划按发
    /// 布门拍数单点裁定（首批＝首拍、直显）
    private func liveStreamingContent(
        text: String
    ) -> some View {
        assistantBubble {
            StreamingLiveText(
                text: text,
                entrancePlan: StreamingEntrance.plan(
                    typewriterEnabled: typewriterEnabled,
                    reduceMotion: reduceMotion,
                    isFirstBatchOfGeneration:
                        streamPublishGate.publishCount <= 1
                ),
                publishGeneration: livePublishGeneration
            )
        }
    }

    // MARK: - §494 发布接线

    /// 发布快照上屏单点：等值不重写（防无谓重
    /// 喂行集），代次随真发布递增（入场计划与
    /// 行修订同源）
    private func noteStreamPublish(_ snapshot: String?) {
        guard let snapshot,
              snapshot != livePublishedText
        else { return }
        livePublishedText = snapshot
        livePublishGeneration += 1
    }

    /// 增量到达拍：装配器最新全文喂发布门、到
    /// 拍即上屏（首拍直发＝首字延迟 ≤1 拍）
    private func offerStreamPublish() {
        guard streamPresentationArmed else { return }
        noteStreamPublish(
            streamPublishGate.offer(
                streamAssembler.mergedFullText,
                now: Date().timeIntervalSince1970
            )
        )
    }

    /// 心跳拍（driveRun 期 50ms 驱动）：无新事
    /// 件时排空积压——工具间隙里尾巴不许滞留
    private func tickStreamPublish() {
        guard streamPresentationArmed else { return }
        noteStreamPublish(
            streamPublishGate.tick(
                now: Date().timeIntervalSince1970
            )
        )
    }

    /// 边界/终态全量发布：封段拍与终态拍调——
    /// 已累积全文立即全量上屏（落定前的最后
    /// 一帧与装配器兜底全文逐字一致）
    private func flushStreamPublish() {
        guard streamPresentationArmed else { return }
        noteStreamPublish(streamPublishGate.flush())
    }

    /// 发布态整清（新轮起点/恢复轮/落定收尾共
    /// 用）：门、快照、代次、武装位一并归零
    private func resetStreamPresentation() {
        streamPublishGate.reset()
        livePublishedText = ""
        livePublishGeneration = 0
        streamPresentationArmed = false
    }

    private func livePlaceholderRow(
        composer: ChatNativeRowHeightComposer
    ) -> ChatNativeRow {
        var revision = ChatNativeRowRevision()
        revision.addText(livePlaceholderStatusText())
        return ChatNativeRow(
            key: "live-placeholder",
            entryID: nil,
            revision: revision,
            height: composer.livePlaceholderHeight,
            makeView: {
                AnyView(livePlaceholderContent())
            }
        )
    }

    /// §426（缺陷一）发送呈现读数单源：气泡浅色
    /// 与气泡旁标记的取值只许在此算——谓词（条目
    /// isUnconfirmedSend/sendFailed）是事实、读数
    /// 是呈现，两层分开钉：呈现层钉测读本函数输
    /// 出（opacity/标记种类），不许只测状态字段
    enum SendStateMarkKind: Equatable {
        /// 红叹号（点按原位重发）
        case failure
        /// 时钟（未确认送达）
        case clock
        /// 无标记（已确认送达）
        case none
    }

    /// 标记种类：失败优先（与 sendStateMark 旧分
    /// 支同序），未确认次之，已确认无标记
    static func sendStateMarkKind(
        sendFailed: Bool, isUnconfirmedSend: Bool
    ) -> SendStateMarkKind {
        if sendFailed { return .failure }
        if isUnconfirmedSend { return .clock }
        return .none
    }

    /// 用户泡体透明度：未确认 0.45、已确认 1
    /// （§414 规格 5.3 的读数本体）
    static func userBubbleOpacity(
        isUnconfirmedSend: Bool
    ) -> Double {
        isUnconfirmedSend ? 0.45 : 1
    }

    /// §426（缺陷四）占位行视觉形态：已受理（生
    /// 成相/已确立的结果未知相）＝纯三点动态、无
    /// 文字（iMessage 输入指示器形态）；未受理
    /// （含上传段）＝状态文字在席、三点不在席。
    /// 与 placeholderStatusText 同判定源：三点只
    /// 许出现在 .submitAccepted 之后，「等待发
    /// 送…」是未送达状态的事实文案、非装饰，保
    /// 留文字（0.50.103 断网 P0 verdict 绑定）
    enum PlaceholderVisual: Equatable {
        case typingDots
        case statusText
    }

    /// 占位行视觉形态判定（纯函数、钉测逐相把
    /// 守，并与文案单源做全组合一致性对账：三点
    /// 恰对应文案的已受理四文案）
    static func placeholderVisual(
        phase: RunTurnPhase,
        runIDEstablished: Bool,
        tailSendState: ChatSendState?,
        isUploading: Bool
    ) -> PlaceholderVisual {
        if isUploading { return .statusText }
        if case .generating = phase { return .typingDots }
        if !runIDEstablished { return .statusText }
        if phase == .unknown || phase == .reconciling {
            return .typingDots
        }
        return .statusText
    }

    /// 占位行状态文案单源（§407 立制；§414 增补
    /// 按断网规格 5.1 改判）：判定源＝runMachine
    /// 相位＋本轮 run 确立与否＋尾条发送状态，优
    /// 先级——上传段 → 生成相三文案（思考/工具/
    /// 生成）→ 未受理段「等待发送…」→ 已受理的
    /// 结果未知「正在确认结果…」。铁则：「正在
    /// 生成…」只许在 .submitAccepted 之后（相位
    /// == .generating）出现；run 未确立前只许报
    /// 等待/确认类文案——旧四相无未受理相，断网
    /// 提交未出设备时全程冒充「正在生成…」即此
    /// 病灶。纯函数（钉测逐相把守），文案变化不
    /// 影响行高（合成器常量把守、钉测在案）
    static func placeholderStatusText(
        phase: RunTurnPhase,
        runIDEstablished: Bool,
        tailSendState: ChatSendState?,
        isUploading: Bool,
        uploadFraction: Double?,
        hasReasoning: Bool,
        hasToolCards: Bool
    ) -> String {
        if isUploading {
            if let uploadFraction {
                return "正在上传文件 \(Int((uploadFraction * 100).rounded()))%…"
            }
            return "正在上传文件…"
        }
        if case .generating = phase {
            if hasReasoning {
                return "正在思考…"
            }
            if hasToolCards {
                return "正在调用工具…"
            }
            return "正在生成…"
        }
        // 未受理段：提交相／结果未知相／对账相且
        // run 从未确立，或尾条仍在队列三态——run
        // 没成立过，不许报生成、也不许报确认（无
        // 可确认之物），只报等待发送（网络恢复后
        // 由发件箱 drain 续发，见 driveRun 未发出
        // 分型落点）
        let tailInQueue = tailSendState == .queued
            || tailSendState == .linking
            || tailSendState == .sending
        if !runIDEstablished,
           phase == .submitting || phase == .unknown
            || phase == .reconciling || tailInQueue {
            return "等待发送…"
        }
        if phase == .unknown || phase == .reconciling {
            // 已受理但结果未知：真对账语义
            return "正在确认结果…"
        }
        // 提交相（runID 已确立在此不可达）与落定
        // 相（占位行本不该在席）：兜底不报生成
        return "等待发送…"
    }

    /// 占位行状态文案的实例取数口：相位读状态
    /// 机、run 确立与尾条状态读本轮账本与条目，
    /// 判定全在 placeholderStatusText 单源
    private func livePlaceholderStatusText() -> String {
        let ledger = (activeRunThreadID ?? currentThread?.id)
            .flatMap {
                appState.runLedger.entry(forThreadID: $0)
            }
        let tailSendState = ledger.flatMap { entry in
            currentThread?.entries.first(
                where: { $0.id.uuidString == entry.userEntryID }
            )?.sendState
        }
        return Self.placeholderStatusText(
            phase: runMachine.phase,
            runIDEstablished: ledger?.runID != nil,
            tailSendState: tailSendState,
            isUploading: isUploadingFiles,
            uploadFraction: uploadProgressFraction,
            hasReasoning: reasoningPublishGate.hasContent,
            hasToolCards: !liveToolCards.isEmpty
        )
    }

    /// §426（缺陷四）：占位行视觉形态的实例取数
    /// 口——与 livePlaceholderStatusText 同源同读
    /// （账本＋尾条状态＋相位＋上传态），判定全在
    /// placeholderVisual 单源
    private func livePlaceholderVisual() -> PlaceholderVisual {
        let ledger = (activeRunThreadID ?? currentThread?.id)
            .flatMap {
                appState.runLedger.entry(forThreadID: $0)
            }
        let tailSendState = ledger.flatMap { entry in
            currentThread?.entries.first(
                where: { $0.id.uuidString == entry.userEntryID }
            )?.sendState
        }
        return Self.placeholderVisual(
            phase: runMachine.phase,
            runIDEstablished: ledger?.runID != nil,
            tailSendState: tailSendState,
            isUploading: isUploadingFiles
        )
    }

    /// 占位行视图（§407）：助手侧状态泡——等待
    /// 点＋一行状态文案，与流式等待泡同形态同几
    /// 何（内容纵内距 spacingXS、气泡纵内距
    /// bubblePaddingV，与合成器
    /// livePlaceholderHeight 逐项同值）
    /// §426（缺陷四）：分相显隐——已受理只显三
    /// 点（无文字）、未受理只显文字（无三点），
    /// 分工见 placeholderVisual；行恒高口径不变
    /// （合成器常量不读内容形态）
    private func livePlaceholderContent() -> some View {
        assistantBubble {
            HStack(spacing: OneDayMetrics.spacingS) {
                if livePlaceholderVisual() == .typingDots {
                    TypingDots()
                } else {
                    Text(livePlaceholderStatusText())
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingXS)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                livePlaceholderStatusText()
            )
        }
    }

    /// 文件牌组估算高（§320）：托管行用户泡下方
    /// FileChip 卡组的占位高。几何与 FileChip 本
    /// 体同源：卡高＝纵内边距 10×2＋max(图标盒
    /// 40, 名列高)；名列＝名行数×正文规格行高＋
    /// spacingXS＋副行 caption 规格行高；名行数
    /// 按文件名以 .body semibold 实测宽对牌内文
    /// 宽折算（至多 2 行，与本体 lineLimit 同
    /// 顶）；组高＝Σ卡高＋牌间 spacingXS×(n−1)，
    /// 上方有正文泡或图片行时另加行内 spacingS
    /// 一段。牌宽随气泡宽（屏宽−bubbleSide-
    /// Inset），牌内文宽再减左内边距 spacingSM、
    /// 图标盒 40 与其后 spacingSM、右侧「···」
    /// 钮 44。本估算只作量实到达前的占位（同
    /// provisionalRowHeight 纪律：产物/量实到达
    /// 即被覆盖，不冒充量实）
    private func fileChipStackEstimate(
        for entry: ChatEntry, style: LayoutStyleContext
    ) -> CGFloat {
        let paths = entry.remoteFilePaths
        guard !paths.isEmpty else { return 0 }
        let bodyLine = InlineTextFonts.specLineHeight(
            textStyle: .body,
            category: style.sizeCategory,
            boldText: style.boldText
        )
        let captionLine = InlineTextFonts.specLineHeight(
            textStyle: .caption1,
            category: style.sizeCategory,
            boldText: style.boldText
        )
        let chipWidth = UIScreen.main.bounds.width
            - OneDayMetrics.bubbleSideInset
        let nameColumnWidth = max(
            1,
            chipWidth - OneDayMetrics.spacingSM - 40
                - OneDayMetrics.spacingSM - 44
        )
        let nameFont = UIFont.systemFont(
            ofSize: UIFont.preferredFont(
                forTextStyle: .body,
                compatibleWith: UITraitCollection(
                    preferredContentSizeCategory:
                        style.sizeCategory
                )
            ).pointSize,
            weight: .semibold
        )
        var total: CGFloat = 0
        for (index, rawPath) in paths.enumerated() {
            let name = (
                FileLineAnchor.split(
                    pathWithAnchor: rawPath
                ).path as NSString
            ).lastPathComponent
            let measured = (name as NSString).size(
                withAttributes: [.font: nameFont]
            ).width
            let lines = min(
                2,
                max(1, Int(ceil(measured / nameColumnWidth)))
            )
            let column = max(
                40,
                CGFloat(lines) * bodyLine
                    + OneDayMetrics.spacingXS + captionLine
            )
            total += 20 + column
            if index > 0 { total += OneDayMetrics.spacingXS }
        }
        if !entry.content.isEmpty
            || !entry.remoteImagePaths.isEmpty {
            total += OneDayMetrics.spacingS
        }
        return total
    }

    /// 产物缓存同步直读（键与服务/预热同构：条目
    /// id×内容哈希×宽×样式键）——只读不产，产归
    /// 预热与服务异步路
    private func cachedLayoutProduct(
        entryID: UUID,
        renderedText: String,
        width: CGFloat,
        style: LayoutStyleContext
    ) -> LayoutProduct? {
        guard !renderedText.isEmpty, width > 0 else {
            return nil
        }
        let key = LayoutProductKey(
            entryID: entryID,
            content: renderedText,
            width: Double(width),
            style: style.coreKey
        )
        return LayoutProductStore.cache.product(for: key)
    }

    /// 条目排版产物（台账 190 留账②·§335）：呈现
    /// 与预计算共用的查口——按键同步直读产物账
    /// （查键与生产方逐字同构：条目 id×呈现文本×
    /// LayoutProductService.textWidth 单源宽×当前
    /// 环境样式快照）；未命中回 nil（呈现走 §168
    /// 回落、预计算让位旧口径），产物由预热/量测
    /// 副产随后补齐、下趟重喂自然命中
    private func entryLayoutProduct(
        _ entry: ChatEntry
    ) -> LayoutProduct? {
        let style = LayoutStyleContext(
            sizeCategory:
                dynamicTypeSize.contentSizeCategory,
            boldText: UIAccessibility.isBoldTextEnabled
        )
        let screenWidth = UIScreen.main.bounds.width
        if entry.role == "user" {
            return cachedLayoutProduct(
                entryID: entry.id,
                renderedText: entry.content,
                width: LayoutProductService.textWidth(
                    isUser: true, screenWidth: screenWidth
                ),
                style: style
            )
        }
        guard entry.role == "assistant",
              entry.toolCard == nil,
              entry.traceKey == nil,
              entry.echoKey == nil,
              entry.approvalKey == nil
        else { return nil }
        let scans = EntryScanMemo.scans(
            entryID: entry.id,
            content: entry.content,
            remoteImagePaths: entry.remoteImagePaths
        )
        return cachedLayoutProduct(
            entryID: entry.id,
            renderedText: ChatNativeRowHeightComposer
                .assistantDisplayText(
                    entryID: entry.id, scans: scans
                ) {
                    FileMetadataStore.shared
                        .existence(for: $0) == .exists
                },
            width: LayoutProductService.textWidth(
                isUser: false, screenWidth: screenWidth
            ),
            style: style
        )
    }

    /// 条目产物段串（§335 呈现注入）：命中回段下
    /// 标→属性串表供 MarkdownText/Selectable-
    /// InlineText 直贴；未命中回 nil
    private func entrySegmentProducts(
        _ entry: ChatEntry
    ) -> [Int: NSAttributedString]? {
        guard let product = entryLayoutProduct(entry)
        else { return nil }
        let strings = product
            .presentationSegmentStrings()
        return strings.isEmpty ? nil : strings
    }

    /// 暂定整行高（产物未就绪时）：按文本长度粗估
    /// 行数（每行约 18 字、CJK/英文混排中位口
    /// 径）——只决定未量实行在滚动几何中的占位，
    /// 产物/量实到达即被覆盖，不冒充量实
    private func provisionalRowHeight(
        for entry: ChatEntry, lineFloor: CGFloat
    ) -> CGFloat {
        let chars = max(entry.content.count, 1)
        let lines = min(
            40, max(1, Int(ceil(Double(chars) / 18.0)))
        )
        return CGFloat(lines) * lineFloor
            + OneDayMetrics.bubblePaddingV * 2
    }

    // MARK: - 消息列表

    /// NEW 未读分界锚解析（台账 148）：打开/切入线
    /// 程时执行一次——以持久水位经 Core Unread-
    /// Divider 解析锚（第一条未读消息），随即把水
    /// 位推进到当前末条：锚在本次观看内定格（新消
    /// 息到达不移位、只演一次），下次打开水位已在
    /// 末条、无锚不画线。无线程/空线程只清锚
    private func refreshUnreadAnchor() {
        guard let thread = currentThread else {
            unreadAnchorEntryID = nil
            return
        }
        let entries = thread.sortedEntries
        unreadAnchorEntryID = UnreadDivider.anchorEntryID(
            entries: entries.map {
                UnreadDivider.EntryStub(
                    id: $0.id, role: $0.role,
                    createdAt: $0.createdAt,
                    isToolCard: $0.toolCard != nil
                )
            },
            watermark: readMarkStore.watermark(for: thread.id)
        )
        if let last = entries.last {
            readMarkStore.advance(
                for: thread.id, entryID: last.id,
                date: last.createdAt
            )
        }
    }

    /// 时间分隔条落点（0.30.0，Core ChatTimeline）：只
    /// 对会话条目走查——工具卡条目（toolCard 非 nil）
    /// 不单独占分隔、也不重置锚点，以其所属回合的会
    /// 话条目时间为准；返回 条目 id → 分隔条文案
    private func timelineDividers(
        for entries: [ChatEntry]
    ) -> [UUID: String] {
        let conversational = entries.filter { $0.toolCard == nil }
        let indices = ChatTimeline.dividerIndices(
            dates: conversational.map(\.createdAt)
        )
        var result: [UUID: String] = [:]
        let now = Date()
        for index in indices {
            let entry = conversational[index]
            result[entry.id] = ChatTimeline.dividerText(
                for: entry.createdAt, now: now
            )
        }
        return result
    }

    /// NEW 未读分界线（台账 148）：挂在未读锚条目
    /// 的气泡上方、时间分隔条之下；入场只演一次
    /// （账本记账、键由 ChatRowStateKeys 单点派生，
    /// 节拍与形态见 ChatUnreadDividerView）
    private func unreadDivider(for entry: ChatEntry) -> some View {
        let key = ChatRowStateKeys.unreadDivider(entry.id)
        return ChatUnreadDividerView(
            arrived: rowStateLedger.hasAnimatedUnreadDivider(
                forKey: key
            ),
            onArrive: { [rowStateLedger] in
                rowStateLedger.markUnreadDividerAnimated(
                    forKey: key
                )
            }
        )
    }

    /// 时间分隔条（0.30.0，微信式素字）：居中、Foot-
    /// note 级（meta 角色）灰字、无气泡无底色块；文
    /// 案与落点全由 Core ChatTimeline 计算、本视图
    /// 只渲染
    private func timelineDivider(_ text: String) -> some View {
        Text(text)
            .font(.meta)
            .foregroundStyle(Palette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("时间 \(text)")
    }

    // MARK: - 工具卡成组与直播区（0.36.10，诊断 D3-8/D3-10）

    /// 落定条目渲染计划（§449.9 起）：工具条目不进
    /// 本计划——活动呈现归页头胶囊活动行/直播占位
    /// 行，流内不再有工具卡（组卡形态随之退役）；时
    /// 间分隔走查只认会话条目、与本计划无关（映射在
    /// timelineDividers 独立计算）
    private enum EntryRenderItem: Identifiable {
        case entry(ChatEntry)

        var id: UUID {
            switch self {
            case .entry(let entry): return entry.id
            }
        }
    }

    private func entryRenderItems(
        for entries: [ChatEntry]
    ) -> [EntryRenderItem] {
        // §449.9：工具条目在计划层过滤（数据层条目
        // 原样保留——来源聚合/历史回放/台账详情照旧
        // 读），两承载（原生行/旧 Lazy 承载）同效
        entries
            .filter { $0.toolCard == nil }
            .map(EntryRenderItem.entry)
    }

    /// 渲染计划缓存（§135 B 案）：存上轮的分隔映射
    /// 与成组计划及命中键——引用型纯记账，不参与呈
    /// 现判定；键（Core ChatRenderPlanKey）由条目集
    /// 投影（id／工具卡数据有无／createdAt）＋线程
    /// ＋当日零点构成，任一失效条件变化即键变、计
    /// 划重算
    private final class RenderPlanCache {
        var key: ChatRenderPlanKey?
        /// D3/D2 乐观隐藏集戳（DESIGN §352）：与
        /// key 并列比对，隐藏集变化即计划失效
        var hiddenStamp: Set<UUID> = []
        var dividers: [UUID: String] = [:]
        var items: [EntryRenderItem] = []
        var sources: [UUID: [MessageSource]] = [:]
    }

    /// 本帧渲染计划：先按键查缓存，未命中才走全量
    /// （sortedEntries 排序＋timelineDividers＋entry-
    /// RenderItems 三件一并缓存——只缓存其一、另一
    /// 件每帧现算等于没减负）。键的投影取 thread.
    /// entries 原始集（未排序）：投影不解码、不排序，
    /// 键内自带定序（见 Core make）
    private func renderPlan(
        for thread: ChatThread
    ) -> (
        dividers: [UUID: String], items: [EntryRenderItem],
        sources: [UUID: [MessageSource]]
    ) {
        let key = ChatRenderPlanKey.make(
            threadID: thread.id,
            entries: thread.entries.map {
                ChatRenderPlanKey.EntryStub(
                    id: $0.id,
                    hasToolCardData: $0.toolCardData != nil,
                    createdAt: $0.createdAt
                )
            },
            dayStamp: Calendar.current.startOfDay(for: Date())
        )
        if renderPlanCache.key == key,
           renderPlanCache.hiddenStamp == rewindHiddenEntryIDs {
            return (
                renderPlanCache.dividers, renderPlanCache.items,
                renderPlanCache.sources
            )
        }
        // D3/D2（DESIGN §352）：乐观隐藏集只在本计
        // 划层过滤（存储一字不动）；隐藏集入缓存戳
        // 比对，集变即计划重算、不许吃旧计划
        let sorted = thread.sortedEntries.filter {
            !rewindHiddenEntryIDs.contains($0.id)
        }
        let dividers = timelineDividers(for: sorted)
        let items = entryRenderItems(for: sorted)
        // D4 (§349): turn-level source aggregation,
        // derived in the same pass as dividers/items
        // -- entries map to segments (user = turn
        // boundary, tool entries carry their card,
        // finalized assistant entries receive), the
        // result is keyed back by entry id. Derived
        // only, never persisted: the tool rows' raw
        // payloads stay the single source of truth,
        // so history replay gains strips for free
        let segments = sorted.map {
            entry -> TurnSourceAggregation.SegmentItem in
            if entry.role == "user" {
                return .init(kind: .userMessage)
            }
            if let card = entry.toolCard {
                return .init(kind: .toolCard, card: card)
            }
            if entry.role == "assistant",
               entry.echoKey == nil,
               entry.approvalKey == nil,
               entry.traceKey == nil,
               !entry.content.trimmingCharacters(
                   in: .whitespacesAndNewlines
               ).isEmpty {
                return .init(kind: .assistantMessage)
            }
            return .init(kind: .other)
        }
        var sources: [UUID: [MessageSource]] = [:]
        for (index, list) in TurnSourceAggregation
            .sourcesByAssistantIndex(items: segments) {
            sources[sorted[index].id] = list
        }
        renderPlanCache.key = key
        renderPlanCache.hiddenStamp = rewindHiddenEntryIDs
        renderPlanCache.dividers = dividers
        renderPlanCache.items = items
        renderPlanCache.sources = sources
        return (dividers, items, sources)
    }

    /// 在底判定单一派生点（§135 几何单源；键盘整
    /// 包 R2 定版，2026-11-13）：一切 isNearBottom
    /// 的重算只许经此一处，判定口径收进 Core
    /// BottomArrowVisibility——尾条在屏（事实）∨
    /// 距底 ≤7pt → 在底；距底 ≥176pt → 离底；中
    /// 段保持上一判定。旧口径（几何迟滞带 ≤96 进
    /// ＋事实覆盖）退役：96 进带喂的是估算总高、带
    /// 内误判正是症②（末条全文在屏而箭头不消）的
    /// 公式面。事实信号的单向性不变（只证在底、
    /// 不反证离底，原理见 Core BottomFactCalibra-
    /// tion 注）。消费方同源：滚动几何回调逐帧、
    /// 落定评估的校准收官。写加等值守卫，同值不
    /// 重算
    private func applyBottomProximity(distance: CGFloat) {
        let calibrated = BottomArrowVisibility.isNearBottom(
            distance: distance,
            contentEndVisible: bottomDistanceRecorder
                .contentEndVisible,
            wasNearBottom: isNearBottom
        )
        if calibrated != isNearBottom {
            isNearBottom = calibrated
        }
    }

    /// 键盘动画参数的 SwiftUI 映射（R1）：时长取
    /// 通知原值；曲线 raw 0/1/2/3 依次对应 ease-
    /// InOut/easeIn/easeOut/linear，键盘自家曲线
    /// （raw 7）无公开 SwiftUI 等价、以 easeInOut
    /// 近似——视觉主导是舱本体的 UIView 动画（真
    /// 曲线、§194），留位侧的曲线差只在动画中段
    /// 产生亚帧级间距差、落定帧两路同值归零
    private func keyboardSnapshotAnimation(
        duration: TimeInterval, curveRaw: Int
    ) -> Animation {
        switch curveRaw {
        case 1: return .easeIn(duration: duration)
        case 2: return .easeOut(duration: duration)
        case 3: return .linear(duration: duration)
        default: return .easeInOut(duration: duration)
        }
    }




    // MARK: 新承载跟随链（旧链的执行双胞胎）

    /// 新承载贴底所有者：与 scrollToBottom 同一协调
    /// 者（BottomStickCoordinator 合并/复贴单
    /// 点）、同一落定观察（BottomSettleMachine＋
    /// 事件化评估＋2 秒有界兜底），只换执行口（句
    /// 柄→容器）。判定与状态机零改——两承载共用
    /// 同一份 stickCoordinator/settleMachine 状态，
    /// 切换承载不重置跟随账
    private func scrollToBottom(
        animated: Bool = true
    ) {
        switch stickCoordinator.requestStick(
            at: Date().timeIntervalSince1970
        ) {
        case .coalesced:
            return
        case .perform(let generation):
            performScrollToBottom(animated: animated)
            settleMachine.begin(animated: animated)
            settleGeneration = generation
            settleFallbackTask?.cancel()
            let pinnedThreadID = currentThreadID
            settleFallbackTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled,
                      currentThreadID == pinnedThreadID
                else { return }
                evaluateSettleFallback()
            }
        }
    }

    /// 新承载贴底本体（不带落定观察，与旧承载
    /// performScrollToBottom 对位）
    private func performScrollToBottom(
        animated: Bool
    ) {
        surfaceScrollToBottom(animated: animated)
    }

    /// 落定评估的新承载事件口：读数出自句柄引用匣
    /// （已由 carrierCallbacks 同步进 bottomDis-
    /// tanceRecorder），状态机与旧链同一台
    private func evaluateSettleOnEvent() {
        guard settleMachine.isWatching,
              let generation = settleGeneration
        else { return }
        let distance = bottomDistanceRecorder.latest
        let step = settleMachine.step(
            distance: distance,
            contentEndVisible: bottomDistanceRecorder
                .contentEndVisible,
            restickArmed: stickCoordinator.isRestickArmed(
                generation: generation
            )
        )
        handleSettleStep(
            step, generation: generation,
            distance: distance, viaFallback: false
        )
    }

    private func evaluateSettleFallback() {
        guard settleMachine.isWatching,
              let generation = settleGeneration
        else { return }
        let distance = bottomDistanceRecorder.latest
        let step = settleMachine.stepTimeout(
            distance: distance,
            contentEndVisible: bottomDistanceRecorder
                .contentEndVisible,
            restickArmed: stickCoordinator.isRestickArmed(
                generation: generation
            )
        )
        handleSettleStep(
            step, generation: generation,
            distance: distance, viaFallback: true
        )
    }

    /// 落定一步的执行（新承载版）：与 handleSettle-
    /// Step 逐值同义（打点/收官/校准/复贴），只换
    /// 复贴执行口
    private func handleSettleStep(
        _ step: BottomSettleMachine.Step,
        generation: Int,
        distance: CGFloat, viaFallback: Bool
    ) {
        if let started = sendFrameStartedAt,
           !sendFrameRestickLogged {
            sendFrameRestickLogged = true
            ChatDiagTrace.record(
                "发送打点 首评 距底 \(Int(distance))pt"
                    + " 复贴 \(step == .restick)"
                    + (viaFallback ? " 经兜底" : "")
                    + " 距发送 "
                    + "\(Int(Date().timeIntervalSince(started) * 1000))ms"
            )
        }
        switch step {
        case .settled, .exhausted:
            stickCoordinator.disarmRestick(
                generation: generation
            )
            closeSettleWatch()
        case .calibrated:
            applyBottomProximity(distance: distance)
            stickCoordinator.disarmRestick(
                generation: generation
            )
            closeSettleWatch()
        case .restick:
            closeSettleWatch()
            guard stickCoordinator.consumeRestick(
                generation: generation
            ) else { return }
            performScrollToBottom(animated: false)
        case .continue:
            break
        }
    }

    /// 切线程的新承载版（与旧承载 currentThreadID
    /// 的 onChange 逐项对位）：存锚双写（扩展锚＋
    /// 旧锚，回落一致）、贴底在途状态全清、未读清
    /// 零、入线程按锚恢复
    private func handleThreadSwitch(
        oldID: UUID?, newID: UUID?
    ) {
        if let oldID, oldID != newID,
           threads.contains(where: { $0.id == oldID }) {
            if let anchor = surfaceCaptureAnchor() {
                ChatListAnchorStore.setAnchor(
                    anchor, for: oldID
                )
            }
            appState.sideChats.setScrollAnchor(
                SideChatScrollAnchor(
                    entryID: isNearBottom
                        ? nil : topVisibleEntryID,
                    atBottom: isNearBottom
                ),
                for: oldID
            )
        }
        stickCoordinator.invalidate()
        settleMachine.cancel()
        settleGeneration = nil
        settleFallbackTask?.cancel()
        settleFallbackTask = nil
        sendFrameStartedAt = nil
        sendFrameRestickLogged = false
        bottomDistanceRecorder.contentEndVisible = false
        awayUnread.resetAll()
        guard let newID else { return }
        restoreThreadPosition(for: newID)
    }

    /// 入线程恢复（新承载）：扩展锚（条目 id＋条内
    /// 偏移）优先、旧锚回落；等一拍布局落定再滚
    /// （与旧承载恢复同拍口径）
    private func restoreThreadPosition(for threadID: UUID) {
        if let anchor = ChatListAnchorStore.anchor(
            for: threadID
        ) {
            isNearBottom = anchor.atBottom
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard currentThreadID == threadID else {
                    return
                }
                surfaceRestore(anchor)
            }
            return
        }
        guard let legacy = appState.sideChats.scrollAnchor(
            for: threadID
        ) else { return }
        isNearBottom = legacy.atBottom
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard currentThreadID == threadID else { return }
            if legacy.atBottom {
                surfaceScrollToBottom(animated: false)
            } else if let entryID = legacy.entryID {
                surfaceScrollToEntry(
                    entryID, animated: false
                )
            }
        }
    }

    /// 冷开首屏定版的新承载版（与旧承载 .task 定
    /// 版链同口径）：无任何存量锚的线程出现一拍后
    /// 无动画贴底，以已落定 inset 重新钳制 offset
    private func firstFrameSettle(for threadID: UUID) {
        guard ChatListAnchorStore.anchor(for: threadID) == nil,
              appState.sideChats.scrollAnchor(for: threadID) == nil
        else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard currentThreadID == threadID,
                  isNearBottom
            else { return }
            surfaceScrollToBottom(animated: false)
        }
    }


    // MARK: - D9 对话内查找（§503 全件接线）

    /// 执行查找（键盘「搜索」键）：与输入即搜同一
    /// 条重算路，只是免防抖即时落
    private func performFind() {
        recomputeFind()
    }

    /// 重算命中（§503 第 1/4/6/7 件）：判定全在
    /// Core ChatFind——本地已物化集算命中（范围口
    /// 径与 D9 旧实现逐字一致：普通消息正文、工具
    /// 卡/trace/回响/审批跳过）、起点取离当前阅读
    /// 位置（顶可见行）最近一条、落座后经 apply-
    /// FindTarget 直调收敛落点＋点亮；本地落空且
    /// 允许补窗时走 huntFindWindow 服务端补窗后
    /// 重算（补窗回来关补窗旗防自猎循环）
    private func recomputeFind(allowHunt: Bool = true) {
        guard let thread = currentThread,
              let query = ChatFind.normalizedQuery(findQuery)
        else {
            clearFindMatches()
            return
        }
        let stubs = thread.sortedEntries.map { entry in
            ChatFind.EntryStub(
                id: entry.id, content: entry.content,
                isSearchable: entry.toolCard == nil
                    && entry.traceKey == nil
                    && entry.echoKey == nil
                    && entry.approvalKey == nil
            )
        }
        let found = ChatFind.matches(entries: stubs, query: query)
        guard !found.isEmpty else {
            clearFindMatches()
            if allowHunt {
                huntFindWindow(query: query, thread: thread)
            }
            return
        }
        let anchorPosition = topVisibleEntryID.flatMap { anchorID in
            stubs.firstIndex { $0.id == anchorID }
        }
        let startIndex = ChatFind.nearestMatchIndex(
            matchPositions: found.map(\.position),
            anchorPosition: anchorPosition
        )
        var session = findSession
        let target = session.recompute(
            matches: found.map(\.id), startIndex: startIndex
        )
        findSession = session
        if let target {
            applyFindTarget(target)
        }
    }

    /// 清集：会话与点亮一并归零（查询清空/本地无
    /// 命中/收栏共用）；已猎取键随之作废——同一查
    /// 询下次再搜可重新补窗
    private func clearFindMatches() {
        var session = findSession
        session.reset()
        findSession = session
        findHighlightEntryID = nil
        findHuntedKey = nil
    }

    /// 落点＋点亮（§503 第 1/2 件）：与全局落点链
    /// landSearchFocus 同口——收敛滚动经面分发器
    /// surfaceFocusEntry（Core SearchFocusConver-
    /// gence：多次重滚＋漂移容差＋用户拖动弃权）、
    /// 点亮经 findHighlightEntryID 置位、2.5 秒后
    /// 值比对自清（连翻时新目标不被旧任务误清）。
    /// 与全局链的差别只在免 350ms 等待：查找命中
    /// 恒在已物化行集内、不待条目进行集
    private func applyFindTarget(_ targetID: UUID) {
        findHighlightEntryID = targetID
        surfaceFocusEntry(targetID)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if findHighlightEntryID == targetID {
                findHighlightEntryID = nil
            }
        }
    }

    /// 查找着色口（§503 第 3 件）：查找激活且本行
    /// 在命中集内 → 喂正文着色查询（归一后的原字
    /// 面）；其余 nil。行重建由 nativeEntryRow 把
    /// 本值折入 stamp/revision 保证——查询变/命中
    /// 集变即重建该行、着色随之增减
    private func findHighlightQuery(for entryID: UUID) -> String? {
        guard showFind,
              findSession.matches.contains(entryID)
        else { return nil }
        return ChatFind.normalizedQuery(findQuery)
    }

    /// 下一条（环绕）：会话返回目标即落点＋点亮
    private func navigateToNextMatch() {
        var session = findSession
        guard let target = session.moveNext() else { return }
        findSession = session
        applyFindTarget(target)
    }

    /// 上一条（环绕）：同上
    private func navigateToPreviousMatch() {
        var session = findSession
        guard let target = session.movePrevious() else { return }
        findSession = session
        applyFindTarget(target)
    }

    /// 收栏清账（「完成」）：查询/会话/点亮/补窗令
    /// 牌一并清——在飞补窗据令牌作废、不落别人线程
    private func closeFind() {
        showFind = false
        findQuery = ""
        findHuntToken = nil
        clearFindMatches()
    }

    /// 查找补窗（§503 第 7 件）：本地已物化集搜不
    /// 到时，复用全局落点链的服务端补窗机制——
    /// timeline 分页寻址（上限 10 页）＋around 逐
    /// 轮取窗＋insertHuntedWindow 同口落盘，命中
    /// 窗落盘后本地重算接管。判定谓词与本地查找
    /// 同口（正文大小写不敏感包含），不借 Search-
    /// TargetResolution 的摘要针（短词与大小写口
    /// 径不同、借来会出「猎到窗却重算落空」）；同
    /// 线程同查询只猎一次，任一步线程被切/查询已
    /// 改/令牌作废即静默收官（栏内仍显无结果、不
    /// 假装定位——与 150 落空口径一致）
    private func huntFindWindow(
        query: String, thread: ChatThread
    ) {
        guard let sessionID = thread.serverSessionID,
              !sessionID.isEmpty
        else { return }
        let huntKey = "\(thread.id.uuidString)|\(query)"
        guard findHuntedKey != huntKey else { return }
        findHuntedKey = huntKey
        let threadID = thread.id
        let token = UUID()
        findHuntToken = token
        let folded = query.lowercased()
        Task { @MainActor in
            var entries: [SessionTimelineEntry] = []
            var cursor: Int64?
            for _ in 0..<10 {
                let afterCursor = cursor
                guard let page = try? await appState.performAdmin(
                    { client, config in
                        try await client.sessionTimeline(
                            config: config, id: sessionID,
                            afterRowID: afterCursor,
                            limit: AroundWindowHunt.timelineLimit
                        )
                    }
                ) else {
                    // 首面就失败 → 无从寻址、收官；中途
                    // 失败 → 已拉条目照常进探针
                    if entries.isEmpty { return }
                    break
                }
                entries.append(contentsOf: page.entries)
                guard currentThreadID == threadID,
                      findHuntToken == token,
                      let next = page.nextCursor, next != cursor
                else { break }
                cursor = next
            }
            guard currentThreadID == threadID,
                  findHuntToken == token,
                  ChatFind.normalizedQuery(findQuery) == query
            else { return }
            let direct = entries.first { entry in
                entry.text?.lowercased().contains(folded) == true
            }?.rowID
            let order = AroundWindowHunt.probeOrder(
                promptRowIDs: entries.map(\.rowID),
                directRowID: direct
            )
            for rowID in order {
                guard currentThreadID == threadID,
                      findHuntToken == token,
                      ChatFind.normalizedQuery(findQuery) == query
                else { return }
                guard let page = try? await appState.performAdmin(
                    { client, config in
                        try await client.sessionMessagesAround(
                            config: config, id: sessionID,
                            rowID: rowID,
                            limit: AroundWindowHunt.pageLimit
                        )
                    }
                ) else { continue }
                guard page.messages.contains(where: { message in
                    message.content.lowercased().contains(folded)
                }) else { continue }
                insertHuntedWindow(page.messages, into: thread)
                recomputeFind(allowHunt: false)
                return
            }
        }
    }




    /// 观察收官清账：代号与兜底任务一并落空（状态
    /// 机已在 step 内自回未观察态）
    private func closeSettleWatch() {
        settleGeneration = nil
        settleFallbackTask?.cancel()
        settleFallbackTask = nil
    }


    /// 审批锚定行（§165，规格 §4.3）：锚定条目按记录
    /// 在桥两集的现态出三形态——待批＝与流末尾区同一
    /// 张完整卡（共用 ChatApprovalCard、同一裁决路
    /// 径）；已决＝结论行（与枢纽历史行同句式：结论
    /// 图标＋标题＋结果措辞＋按规则后缀）；两处皆无
    /// 且缺席满两轮＝「已失效」灰行（标题取物化时落
    /// 盘的快照）。呈现判定全走 Core（rowState＋store
    /// 的缺席计数），本视图只渲染
    @ViewBuilder
    private func approvalAnchorRow(_ entry: ChatEntry) -> some View {
        let store = appState.sharedHubStore()
        let recordID = ApprovalAnchor.recordID(
            fromKey: entry.approvalKey ?? ""
        ) ?? ""
        switch store.anchorRowState(recordID: recordID) {
        case .pending(let record):
            ChatApprovalCard(
                store: store, record: record,
                ledger: rowStateLedger
            )
        case .decided(let item):
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: item.isApproved
                    ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(item.isApproved
                        ? Palette.success : Palette.danger)
                Text(item.headline)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer()
                Text(item.isRuleApproved
                    ? L10n.string("已按规则放行")
                    : item.decisionLabel)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .background(
                Palette.surface,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.containerCorner
                )
            )
        case .stale:
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Palette.inkMuted)
                Text(entry.content)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                Spacer()
                Text("已失效")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .accessibilityElement(children: .combine)
        case .loading:
            // 审批数据还没拉到：行位占住、只给转圈，不
            // 提前判待批/已决/失效中的任何一种
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text(entry.content)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
        }
    }

    /// 锚点点达消费（§165）：请求在位时执行一次并清
    /// 零——切到目标线程后等一拍让条目进渲染，再滚
    /// 动定位＋点亮；目标条目不在该线程里（数据已变）
    /// 如实落空：停在该线程顶部附近、不滚不亮。请求
    /// 无键（threadOnly）只切线程
    private func consumeApprovalAnchorRequest() {
        guard let request = appState.router.approvalAnchorRequest
        else { return }
        appState.router.approvalAnchorRequest = nil
        if appState.router.drawerThreadSelection != request.threadID {
            appState.router.drawerThreadSelection = request.threadID
        }
        guard let key = request.approvalKey,
              let thread = threads.first(
                  where: { $0.id == request.threadID }
              ),
              let entry = thread.entries.first(
                  where: { $0.approvalKey == key }
              )
        else { return }
        let entryID = entry.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard currentThreadID == request.threadID else { return }
            anchorHighlightEntryID = entryID
            try? await Task.sleep(for: .seconds(2.5))
            if anchorHighlightEntryID == entryID {
                anchorHighlightEntryID = nil
            }
        }
    }

    /// 目标委派回响行（§123 H1）：居中安静一行——小
    /// 图标＋事实正文＋时刻；不带气泡底、不挂长按菜单
    /// （它不是谁发的言）。入口四问备注：入口＝目标详
    /// 情「安排一件事」绑定的线程本身；形态与聊天流里
    /// 的系统性提示同族（居中、次级色），不新建视觉件
    private func echoRow(_ entry: ChatEntry) -> some View {
        HStack(spacing: OneDayMetrics.spacingXS) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 11))
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityHidden(true)
            Text(entry.content)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
            Text(entry.createdAt, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OneDayMetrics.spacingXS)
        .accessibilityElement(children: .combine)
    }

    /// 留痕回响行（§229 物化归位）：流内紧凑形态——
    /// 主句一行＋对象行（会话类可点达、整行点达走既
    /// 有续聊通道）＋结果行（失败原文照上、danger
    /// 色，P0 契约：失败与成功同级、不折叠）。数据
    /// 读条目自带快照（entry.traceEcho，落盘时定
    /// 格），快照缺失降级为 content 主句一行。几何
    /// 承旧回响卡同族（surface 底＋hairline 边＋
    /// containerCorner），只收紧内距与字阶——它现
    /// 在是消息流里的一条，不再是流尾大卡
    private func traceEchoRow(_ entry: ChatEntry) -> some View {
        let snapshot = entry.traceEcho
        let isFailed = snapshot?.isFailed ?? false
        let openableSessionID = snapshot?.openableSessionID
        let row = HStack(
            alignment: .top, spacing: OneDayMetrics.spacingS
        ) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(
                    isFailed ? Palette.danger
                        : Palette.inkSecondary
                )
                .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(snapshot?.headline ?? entry.content)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink)
                if let label = snapshot?.targetLabel,
                   !label.isEmpty {
                    HStack(spacing: OneDayMetrics.spacingMicro) {
                        Text(label)
                            .font(.footnote)
                            .foregroundStyle(
                                openableSessionID != nil
                                    ? Palette.primary
                                    : Palette.inkSecondary
                            )
                            .lineLimit(1)
                        if openableSessionID != nil {
                            Image(systemName: "chevron.right")
                                .font(
                                    .system(size: 10, weight: .semibold)
                                )
                                .foregroundStyle(Palette.primary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                if let outcome = snapshot?.outcome,
                   !outcome.isEmpty {
                    Text(outcome)
                        .font(.footnote)
                        .foregroundStyle(
                            isFailed ? Palette.danger
                                : Palette.inkSecondary
                        )
                        .lineLimit(isFailed ? 4 : 3)
                }
            }
            Spacer(minLength: 0)
            Text(traceEchoTimeText(entry.createdAt))
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner
            )
            .strokeBorder(
                isFailed ? Palette.danger : Palette.hairline,
                lineWidth: 1
            )
        }
        .contentShape(Rectangle())
        // 点达：整行可点（承旧回响卡同手法），仅会话
        // 类目标接出口；点不达的行无动作、不装可点
        .accessibilityElement(children: .combine)
        // §379：点达行迁原生 Button（原点按手势＋自研
        // 按压修饰退役）；无会话目标的行保持纯展示——
        // 无动作不装可点、连反馈也不给（原 enabled 旗
        // 语义逐字保留）
        return Group {
            if let openableSessionID {
                Button {
                    openEchoSession(openableSessionID)
                } label: {
                    row
                }
                .buttonStyle(.odPressable)
            } else {
                row
            }
        }
    }

    /// 回响行时间要素：今天只给时刻、跨日带月日（与
    /// 旧回响卡同口径；时刻取条目 createdAt——§229
    /// 起它就是事件时间本身，不再是另一处存的时间）
    private func traceEchoTimeText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(
            .dateTime.month().day().hour().minute())
    }

    /// 回响点达出口（承旧回响卡 onOpenSession 口
    /// 径）：已在本会话里点指向自己的回响不重复导
    /// 入；其余置位待续聊 id，由本页既有消费口导
    /// 入/切换（与管理页/频道页同路）
    private func openEchoSession(_ sessionID: String) {
        if sessionID != currentThread?.serverSessionID {
            appState.router.pendingChatSessionID = sessionID
        }
    }

    /// 空态建议条段（§457 起为空态唯一构成）：§455 起建
    /// 议不再写死——StarterSuggestionsAssembly 以当
    /// 下已同步真数据（待批/目标/定时/资源库）现算
    /// 现排，凑不出才回落 EmptyChatSuggestions 冷启
    /// 池；点按即发送（走现行 send() 全链，不另建发
    /// 送路），点过即记账、短期内不重复出
    @ViewBuilder
    private var emptyStateSuggestions: some View {
        let suggestions = StarterSuggestionsAssembly
            .currentSuggestions(appState: appState)
        VStack(spacing: OneDayMetrics.spacingS) {
            ForEach(suggestions) { suggestion in
                Button {
                    StarterSuggestionsAssembly.markUsed(suggestion)
                    input = suggestion.text
                    send()
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Image(systemName: suggestion.symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.inkSecondary)
                        Text(L10n.string(suggestion.text))
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: 50)
                    .background(
                        Palette.surface,
                        in: RoundedRectangle(
                            cornerRadius: OneDayMetrics.fieldCorner,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, OneDayMetrics.spacingL)
        .task {
            await StarterSuggestionsAssembly
                .loadContextIfNeeded(appState: appState)
        }
    }

    /// 条目行内容（§257 起两承载共用同一构建，防两
    /// 承载行内容分叉）：分隔条（有则）＋气泡本体，
    /// §165 锚点点亮底色同在此处——旧承载挂 Lazy-
    /// VStack、新承载托管进容器 cell，行内容只有
    /// 本一处出处
    @ViewBuilder
    private func entryRowContent(
        _ entry: ChatEntry, dividerText: String?,
        showsUnreadDivider: Bool = false,
        sources: [MessageSource] = []
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: OneDayMetrics.spacingS
        ) {
            if let dividerText {
                timelineDivider(dividerText)
            }
            if showsUnreadDivider {
                unreadDivider(for: entry)
            }
            // §471（病二）：本条浮排在场期间原泡摘
            // 除——快照在原位独呈，杜绝「原泡压暗＋
            // 复刻盖上」的双份叠印（Exyte 本体抽出
            // 语义的过渡实现：几何/命中不动、只摘
            // 渲染）。快照走 bubble(entry) 直调、不
            // 经本行构建，不受此摘除影响
            bubble(entry)
                .opacity(
                    reactionBarSession?.entryID == entry.id
                        ? 0 : 1
                )
            if !sources.isEmpty {
                // D4 (§349): the source strip is a
                // sibling slot of the bubble, not part
                // of bubble() itself (the floating-bar
                // snapshot replays bubble geometry; the
                // strip must not enter it). The slot gap
                // is this VStack's spacingS, matching
                // the composer's sourceStripSlot. No
                // messageMenu here: the strip is a
                // disclosure/link control; the menu
                // surface stays on the bubble chrome
                MessageSourceStripView(
                    sources: sources,
                    expansionKey: ChatRowStateKeys
                        .sourcesEntry(entry.id),
                    ledger: rowStateLedger
                )
            }
        }
        // §165：锚点点亮——点达请求命中的锚定行以
        // primaryTint 底色点亮（沿 §123 枢纽聚焦同
        // 手法），消费侧 2.5 秒后清
        .background(
            entry.id == anchorHighlightEntryID || entry.id == findHighlightEntryID
                ? Palette.primaryTint
                : Color.clear,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner
            )
        )
    }

    /// 发送状态标记（§407）：失败＝红叹号钮（点
    /// 按原条目重发）、待发＝时钟钮（点按同条目
    /// 重发）——微信口径的气泡旁小标记，两态互
    /// 斥、失败优先；由 bubble 以 overlay 挂正文
    /// 列左侧让位区呈现，不占列宽、不进行高（旧
    /// 形态：失败钮在 HStack 内扣列宽、待发状态
    /// 行在列内加槽——皆为状态翻转换高源，已退
    /// 役）。待发文案保留在无障碍标签里，点达面
    /// 的整行菜单另有发件箱动作面承接
    /// §414 增补（断网规格 5.3）：时钟条件改挂发
    /// 送状态机谓词 isUnconfirmedSend（与气泡浅
    /// 色态同口），不再读 deliveryState——首发在
    /// 飞全程（queued→sending）时钟在席（在飞期
    /// 钮由 isStreaming 禁用、落定/折回待发后可
    /// 点），旧读口下首发从第一帧到落定无任何标
    /// 记即此病灶；点按动作仍走 resendPending 的
    /// isPendingSend 守卫（真待发条目才重发）
    @ViewBuilder
    private func sendStateMark(
        for entry: ChatEntry
    ) -> some View {
        let markKind = Self.sendStateMarkKind(
            sendFailed: entry.sendFailed,
            isUnconfirmedSend: entry.isUnconfirmedSend
        )
        if markKind == .failure {
            Button {
                resendFailedEntry(entry)
            } label: {
                Image(
                    systemName: "exclamationmark.circle.fill"
                )
                .font(.system(size: 20))
                .foregroundStyle(Palette.danger)
                .frame(
                    width: OneDayMetrics.minTapTarget,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("发送失败，点按重新发送")
        } else if markKind == .clock {
            Button {
                resendPending(entry)
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .disabled(isStreaming)
            .accessibilityLabel(
                L10n.string("未发送 · 点按重发")
            )
        }
    }

    @ViewBuilder
    private func bubble(_ entry: ChatEntry) -> some View {
        if entry.traceKey != nil {
            // §229（回响物化归位）：留痕回响条目——流
            // 内紧凑回响行，不是气泡、不冒充任何一方
            // 发言（回响是 App 按桥侧留痕真源落的事实
            // 记录，见 TraceEchoMaterialization）
            traceEchoRow(entry)
        } else if entry.approvalKey != nil {
            // §165（锚点包）：审批锚定条目——按记录在
            // 桥两集里的现态渲染（待批＝完整卡、已决＝
            // 已决行、两处皆无过两轮＝失效灰行），状态
            // 判定走 Core ApprovalAnchor.rowState 单源；
            // 不是气泡、不冒充任何一方发言
            approvalAnchorRow(entry)
        } else if entry.echoKey != nil {
            // §123（H1）：目标委派回响条目——居中通知
            // 行，不是气泡、不冒充任何一方发言（回响
            // 是 App 按真源落的事实记录，见 GoalEcho）
            echoRow(entry)
        } else if entry.toolCard != nil {
            // §449.9（2026-11-24 用户令）：工具条目不
            // 再成卡进流——活动归页头胶囊活动行；渲染
            // 计划层已过滤，本支是其余直调（长按快照
            // 等）的兜底，恒空；条目数据层不动、仍不
            // 进发送上下文（0.8.0 口径不变）
            EmptyView()
        } else if entry.role == "user" {
            HStack {
                Spacer(minLength: OneDayMetrics.bubbleSideInset)
                VStack(alignment: .trailing, spacing: OneDayMetrics.spacingXS) {
                    if let quote = entry.quote {
                        // §265（S3）：引用块是纯 Text 铬
                        // 件（无文本交互）——整行菜单挂载
                        // 面之一（源引用块含可点按钮、不
                        // 在此列，见 §265 报告登记）
                        quoteBlock(quote)
                            .modifier(messageMenu(for: entry))
                    } else if let sourceQuote = entry.sourceQuote {
                        sourceQuoteBlock(sourceQuote)
                    }
                    // §152：本地图走全集（allImage-
                    // Datas）成行——多图并排同高、单
                    // 图与旧单图块同形（卡尺寸同出
                    // rowCardSizes、单张逐字等于
                    // cardSize，卡体抽共用函数
                    // localImageCard）；旧单槽
                    // imageData 只取首图的呈现口径
                    // 随单槽落盘一并作废（见 Chat-
                    // Entry.imageDatasData）
                    let localImageDatas = entry.allImageDatas
                    if !localImageDatas.isEmpty {
                        // §265（S3）：图片行是铬件——整
                        // 行菜单挂载面之一
                        localImageRow(localImageDatas, entry: entry)
                            .modifier(messageMenu(for: entry))
                    }
                    // 0.8.0（P1）：历史导入的服务端图片
                    // （标记路径）——缩略经文件下载通道
                    // 取回，点开同一个全屏查看器
                    ForEach(entry.remoteImagePaths, id: \.self) { path in
                        // §130：卡形由 ServerRemoteImage
                        // 本体承载（radiusCard），此处不再
                        // 外挂裁形（旧 spacingM 双重裁角）
                        Button {
                            openImageViewer(
                                ChatImageViewerItem(
                                    source: .remotePath(path)
                                )
                            )
                        } label: {
                            ServerRemoteImage(path: path)
                                // §247.2 试点：同位挂 zoom 源
                                // 锚点（点开大图自此图长出）
                                .overlay {
                                    ZoomSourceAnchor(
                                        sourceID: ChatImageViewerItem(
                                            source: .remotePath(path)
                                        ).id
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity
                                    )
                                    .allowsHitTesting(false)
                                }
                        }
                        .buttonStyle(.odPressable)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            A11yText.imageLabel(
                                fileName: (path as NSString)
                                    .lastPathComponent
                            )
                        )
                        .accessibilityHint(L10n.string("查看大图"))
                            // §265（S3）：图片卡是铬件——
                            // 整行菜单挂载面之一
                            .modifier(messageMenu(for: entry))
                    }
                    if !entry.content.isEmpty {
                        // 条 8（§14）：段落渲染前过断行整形
                        // （尾行孤字防护，TextShaping 纯函数）
                        // §152：正文改走 SelectableInline-
                        // Text 原地可选（plainRuns 不解析
                        // markdown、原文逐字呈现，与旧裸
                        // Text 一致）；字阶角色与旧口径同
                        // ——0.3.8 第 29 条 .callout 基准
                        // （0.4.4 定 16）由 textStyle 承
                        // 担、0.26.0 主题泡字色由 fore-
                        // ground 承担（默认行浅档与
                        // bodyInk 同值、暗档见 Palette 注）
                        // §263：字阶随正文单源升 .body
                        // （用户/助手同档，见 LayoutStyle-
                        // Context.coreKey 注）
                        SelectableInlineText(
                            paragraphs: [
                                // §271：整形后移 run 层
                                // （plainRuns 不解析、整形
                                // 只在产出 run 上施加尾行
                                // 绑定；数字串内部不插符、
                                // 检测令牌不断裂）
                                InlineTextParagraph(
                                    runs: TextShaping.shapeRuns(
                                        InlineRunBuilder.plainRuns(
                                            entry.content
                                        )
                                    )
                                )
                            ],
                            textStyle: .body,
                            foreground: Palette.userBubbleText,
                            onSelectionChange: { active in
                                noteTextSelection(
                                    entryID: entry.id, active: active
                                )
                            },
                            // §471（病一）：列表态禁直
                            // 接选字——长按归浮排/菜
                            // 单，选字只从菜单「选择」
                            // 行进 sheet
                            allowsDirectSelection: false,
                            // §335：用户正文产物段串直
                            // 贴（产物 plain 段与本段同
                            // 源同式——同整形拼装 §271、
                            // 同前景令牌）；未命中走
                            // §168 拼装回落
                            prebuiltAttributed:
                                entrySegmentProducts(entry)?[0],
                            // §503：查找着色（命中行正
                            // 文命中词加底；非命中行 nil）
                            searchHighlightQuery:
                                findHighlightQuery(for: entry.id)
                        )
                            .padding(.horizontal, OneDayMetrics.bubblePaddingH)
                            .padding(.vertical, OneDayMetrics.bubblePaddingV)
                            .background {
                                // 0.3.4 去染色（§19 变/不变表）：
                                // 用户气泡是表面容器、归中性，
                                // primaryTint 染色撤销
                                // 0.3.8 第 26 条：纯白 #FFFFFF
                                // 在 #FCFCFC 底上等于无气泡——
                                // 换中性浅灰 userBubbleFill，与
                                // 助手泡同家族拉开深浅、恒中性
                                // §265（换代包 5·S3）：整行菜单
                                // 挂载面下移到本背景层（气泡背
                                // 景＋内边距带）——背景层不是文
                                // 本视图的祖先，长按文本归
                                // UITextView 原生选字＋编辑菜
                                // 单；长按落在背景/边距带上仍
                                // 出整行菜单（DESIGN §265）
                                RoundedRectangle(
                                    cornerRadius: OneDayMetrics.bubbleCorner
                                )
                                .fill(Palette.userBubbleFill)
                            }
                            // §414 增补（断网规格 5.3）：未
                            // 确认发送的泡体浅色态——谓词
                            // isUnconfirmedSend 在途时整泡
                            // （字色与填充同体）降至 0.45，
                            // 服务端确认（delivered/落定）
                            // 后 0.2s 过渡回全色（Muse 形
                            // 态）；只改呈现不改几何——行
                            // 高合成器不感知颜色，翻转前后
                            // 行高逐值不变（§407 钉测把守）
                            .opacity(
                                Self.userBubbleOpacity(
                                    isUnconfirmedSend:
                                        entry.isUnconfirmedSend
                                )
                            )
                            .animation(
                                .easeInOut(duration: 0.2),
                                value: entry.isUnconfirmedSend
                            )
                            .modifier(messageMenu(for: entry))
                    }
                    // 0.46.1（§116）：用户附件文件牌——
                    // 展开块剥出的非图片附件（导入/补缺
                    // 落盘 remoteFilePaths）挂正文泡下方
                    // 同列，与助手侧同构（同一 FileChip、
                    // 同一 openChatFile 打开链；§125 起
                    // 牌升卡、点开落文件打开页中间页）；
                    // 图片已由上方图片行承接，不到这里
                    if !entry.remoteFilePaths.isEmpty {
                        VStack(
                            alignment: .trailing,
                            spacing: OneDayMetrics.spacingXS
                        ) {
                            ForEach(
                                entry.remoteFilePaths, id: \.self
                            ) { rawPath in
                                // 路径尾可能带 #L 锚点
                                // （网关引用形态）：拆开再
                                // 构造牌，锚点透传打开页
                                let split = FileLineAnchor.split(
                                    pathWithAnchor: rawPath
                                )
                                FileChip(path: split.path) {
                                    openChatFile(
                                        split.path,
                                        anchor: split.anchor
                                    )
                                }
                            }
                        }
                        // §265（S3）：文件牌组是铬件——整
                        // 行菜单挂载面之一
                        .modifier(messageMenu(for: entry))
                    }
                }
                // §265（S3）：整行菜单自此不在行根挂载
                // （旧挂法罩住文本面、长按文本先出整行
                // 菜单——已下移到各铬件面，见上）
                // 台账 187：反应 pill 压气泡底角·朝中线
                // 侧（用户行左下，§334 正名），半身悬出
                // ——悬出净深由行高合成器的 reactionReserve
                // 同步预留（ChatReactionMetrics 单源）
                .overlay(alignment: .bottomLeading) {
                    reactionChrome(for: entry)
                        .offset(
                            x: ChatReactionMetrics.cornerInset,
                            y: ChatReactionMetrics.hangDepth
                        )
                }
                // §407（预排版步骤 1）：发送状态标记
                // overlay 挂正文列左侧让位区——失败
                // 红叹号/待发时钟（sendStateMark），
                // 落点与旧 HStack 内钮同位（列左
                // spacingS 间隙外 44 钮身），不占列
                // 宽、不进高度：状态翻转只换标记、
                // 行高逐值不变（合成器已摘状态项）
                .overlay(alignment: .leading) {
                    sendStateMark(for: entry)
                        .offset(
                            x: -(OneDayMetrics.minTapTarget
                                + OneDayMetrics.spacingS)
                        )
                }
                .modifier(swipeReply(for: entry))
            }
        } else {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                // §152：登记交付标记先拆（Core 纯函
                // 数）——`[[deliver:dlv_…]]` 独立行
                // 从正文摘除、走下方交付项呈现（按
                // 号取登记 meta 渲染，见 Delivery-
                // Views）；裸路径兜底（§129/§136）
                // 只管拆剩的正文，两层不打架
                // §199：本组派生扫描改条目级备忘（Core
                // EntryScanMemo，键＝条目 id×内容哈希）
                // ——同内容第二遍起零重扫、产出与逐遍
                // 现算逐字相等；各扫描的口径仍以其各
                // 自来源注（§152/§136/§143/§154）为准
                let scans = EntryScanMemo.scans(
                    entryID: entry.id,
                    content: entry.content,
                    remoteImagePaths: entry.remoteImagePaths
                )
                let deliverySplit = scans.delivery
                // §136：MEDIA: 图片标记拆分（Core 纯
                // 函数）——独立成行的图片标记从正文
                // 摘除、走下方图片行出图，正文只喂摘
                // 除后的文本（标记原文不再漏进气泡）
                let mediaSplit = scans.media
                // 聊天可靠性包（2026-11-13）：整条消息
                // 就是一条裸路径（形态判定在 Core
                // wholeMessagePath）——那是 AI 把文件
                // 当整条回复交付（实案：只回 /opt/
                // data/cache/scratch/avatar_small.
                // png、两次）。此形态不走 §129/§143
                // 的存在性门降级路（门一失败路径就原
                // 样躺回正文、用户读作「还是目录」）：
                // 路径行无条件从正文摘除、改走下方附
                // 件区直取字节——图片走 ServerRemote-
                // Image（自带加载/失败占位卡）、文件
                // 走 BarePathFileCard（确证不在出失效
                // 卡）；两处候选集里同步排除它、不重
                // 复成牌。多行正文里的路径提及仍归
                // §129/§143，本口只认整条消息
                let wholePathRef = FileRefDetector
                    .wholeMessagePath(in: mediaSplit.text)
                // §143：裸路径图片内联——独立成行/段内
                // 单独成词的图片路径（形态判定在
                // Core）不再降为文件牌：走下方图片行
                // 出图（AssistantMediaImage 的存在性
                // 门把关，未确证不出图、查无不露牌）；
                // 独立成行且已确证存在的，把路径行从
                // 气泡正文摘除（只剩图、不剩生路径一
                // 行）；未确证/查无的正文维持原样纯文
                // 本（§129 降级口径，内容不消失）
                let inlineImages = scans.inlineCandidates
                    .filter { $0.path != wholePathRef?.path }
                // §154 热修：摘行集补 §136 已承接的
                // 图——同一路径既写了 MEDIA: 行、又在
                // 正文裸写独立成行时，§143 候选被排除
                // 集挡住（excluding 含 mediaSplit
                // .imagePaths）、裸行没人摘：图已在上
                // 方出，气泡里还留一行生路径（生产实
                // 证消息 1878：cloud_pc_small.jpg 哨
                // 兵已登记、图已出，正文仍留路径行，
                // 用户读作「还是纯文本没出图」）。摘
                // 除条件与 §143 逐字同口径：独立成行
                // ＋存在性确证 .exists 才摘；查无/未
                // 确证正文原样保留、内容不消失
                let mediaStandalonePaths = Set(
                    scans.standalonePaths
                )
                // §199：摘行扫描同走备忘——摘行集由存
                // 在性派生、签名入键，存在性翻转即重
                // 算，语义与逐遍现算恒等
                let displayText = EntryScanMemo.displayText(
                    entryID: entry.id,
                    mediaText: mediaSplit.text,
                    stripPaths: Set(
                            inlineImages.filter {
                                $0.isStandaloneLine
                                    && FileMetadataStore.shared
                                        .existence(for: $0.path)
                                        == .exists
                            }.map(\.path)
                        ).union(
                            mediaSplit.imagePaths.filter {
                                mediaStandalonePaths
                                    .contains($0)
                                    && FileMetadataStore.shared
                                        .existence(for: $0)
                                        == .exists
                            }
                        ).union(
                            // 可靠性包：整条裸路径无条件
                            // 摘行——附件区直取字节接管
                            // 呈现（含取不到时的失效
                            // 态），正文永不退回生路径
                            wholePathRef.map { [$0.path] } ?? []
                        )
                    )
                // 0.5.1（§32）：思考折叠单元挂在正文泡
                // 上方同一列——有落盘思考才出现，默认折
                // 叠、点开看原文（ReasoningBlock）
                if let reasoning = entry.reasoning, !reasoning.isEmpty {
                    ReasoningBlock(
                        text: reasoning,
                        seconds: entry.reasoningSeconds,
                        isStreaming: false,
                        expansionKey: ChatRowStateKeys
                            .reasoningEntry(entry.id),
                        ledger: rowStateLedger
                    )
                }
                // 0.8.0（P1）：助手消息的服务端图片（历
                // 史导入形态）与用户侧同口径：缩略＋点开
                // 全屏
                ForEach(entry.remoteImagePaths, id: \.self) { path in
                    // §130：卡形由 ServerRemoteImage
                    // 本体承载（radiusCard），此处不再
                    // 外挂裁形（旧 spacingM 双重裁角）
                    Button {
                        openImageViewer(
                            ChatImageViewerItem(
                                source: .remotePath(path)
                            )
                        )
                    } label: {
                        ServerRemoteImage(path: path)
                    }
                    .buttonStyle(.odPressable)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        A11yText.imageLabel(
                            fileName: (path as NSString)
                                .lastPathComponent
                        )
                    )
                    .accessibilityHint(L10n.string("查看大图"))
                }
                // §136：MEDIA: 标记的图片行——存在性
                // 门在 AssistantMediaImage（与 §129
                // 文件牌同源三分判定：确证存在才出
                // 图，查无/查不成整行不显示、绝不露
                // 标记原文）
                ForEach(mediaSplit.imagePaths, id: \.self) { path in
                    // §265（S3）：图片卡是铬件——整行菜单
                    // 挂载面之一
                    AssistantMediaImage(path: path) {
                        openImageViewer(
                            ChatImageViewerItem(
                                source: .remotePath(path)
                            )
                        )
                    }
                    .modifier(messageMenu(for: entry))
                }
                // §143：裸路径图片行——与 MEDIA 行同
                // 形态（AssistantMediaImage §130 定高
                // 卡），存在性门在视图本体
                ForEach(inlineImages, id: \.path) { ref in
                    // §265（S3）：图片卡是铬件——整行菜单
                    // 挂载面之一
                    AssistantMediaImage(path: ref.path) {
                        openImageViewer(
                            ChatImageViewerItem(
                                source: .remotePath(ref.path)
                            )
                        )
                    }
                    .modifier(messageMenu(for: entry))
                }
                // §146（原分支 §142）：登记交付项——
                // 呈现位与 §136 图片行同口径（正文摘
                // 除后在此成卡/成图）；图片点开进查
                // 看器、文件点开落 §125 打开页，都以
                // 登记 meta 的 path 走既有通道
                // （AssistantDeliveryItem 内部按
                // kind 分流）
                ForEach(
                    deliverySplit.deliveryIDs, id: \.self
                ) { deliveryID in
                    // §265（S3）：交付项是铬件——整行菜单
                    // 挂载面之一
                    AssistantDeliveryItem(
                        id: deliveryID,
                        onOpenImage: { meta in
                            openImageViewer(
                                ChatImageViewerItem(
                                    source: .remotePath(meta.path)
                                )
                            )
                        },
                        onOpenFile: { meta in
                            openChatFile(meta.path)
                        }
                    )
                    .modifier(messageMenu(for: entry))
                }
                // 聊天可靠性包：整条裸路径的附件区——
                // 呈现与 remoteImagePaths 行同口径（图
                // 片 ServerRemoteImage 定高卡＋点开查
                // 看器，加载失败自带诚实占位卡；文件
                // BarePathFileCard，确证不在出失效
                // 卡）；正文已在上方无条件摘行，这里
                // 是这条消息唯一的呈现
                if let wholePathRef {
                    if FileRefDetector.isImagePath(
                        wholePathRef.path
                    ) {
                        Button {
                            openImageViewer(
                                ChatImageViewerItem(
                                    source: .remotePath(
                                        wholePathRef.path
                                    )
                                )
                            )
                        } label: {
                            ServerRemoteImage(path: wholePathRef.path)
                        }
                        .buttonStyle(.odPressable)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            A11yText.imageLabel(
                                fileName: (wholePathRef.path
                                    as NSString)
                                    .lastPathComponent
                            )
                        )
                        .accessibilityHint(L10n.string("查看大图"))
                            // §265（S3）：整条裸路径图卡是
                            // 铬件——整行菜单挂载面之一
                            .modifier(messageMenu(for: entry))
                    } else {
                        // §265（S3）：整条裸路径文件卡是
                        // 铬件——整行菜单挂载面之一
                        BarePathFileCard(path: wholePathRef.path) {
                            openChatFile(
                                wholePathRef.path,
                                anchor: wholePathRef.anchor
                            )
                        }
                        .modifier(messageMenu(for: entry))
                    }
                }
                // 正文只剩标记行被摘空时不渲染空气泡；
                // 无标记的旧消息行为逐字不变。§143：
                // 正文喂摘除已确证独立行图片后的
                // displayText；整条只剩图片/交付项时
                // 同理不渲染空气泡（可靠性包：整条裸
                // 路径已由附件区承接、同入此判据）
                if !displayText.isEmpty
                    || (mediaSplit.imagePaths.isEmpty
                        && inlineImages.isEmpty
                        && deliverySplit.deliveryIDs.isEmpty
                        && wholePathRef == nil) {
                    assistantBubble(menuEntry: entry) {
                        // §152：选区回报接行级记账（选
                        // 字期间关本行右滑引用）
                        // §335：产物段串注入——命中段
                        // 直贴产物串（与量测同源）、未
                        // 命中段走 §168 拼装回落
                        MarkdownText(
                            displayText,
                            onSelectionChange: { active in
                                noteTextSelection(
                                    entryID: entry.id, active: active
                                )
                            },
                            // §471（病一）：列表态禁直
                            // 接选字（同用户泡口径）
                            segmentProducts:
                                entrySegmentProducts(entry),
                            allowsDirectSelection: false,
                            // §503：查找着色（命中行正
                            // 文命中词加底；非命中行 nil）
                            searchHighlightQuery:
                                findHighlightQuery(for: entry.id)
                        )
                    }
                }
                // 0.8.0（P1）：正文里的服务端文件路径出
                // 文件牌（探测纯函数在 Core，标记图片路
                // 径已由上面的图片行承接、此处排除）；
                // §125 起点开落文件打开页中间页，图片
                // 扩展名仍直接进图片查看器
                // §125：锚点感知探测——路径带 `#L12-
                // L20` 时牌透传锚点，打开页进阅读页
                // 定位高亮（仅 text 类消费）
                // §129：成牌收紧——改走 detectStand-
                // aloneAnchored（只有单独成行的路径才
                // 成牌、且须在下载根内；行内提及的拟
                // 议/举例路径一律纯文本），呈现走
                // AssistantFileChip 的存在性门（校验
                // 确证存在才出牌，查无此文件降纯文
                // 本；诊断 file-ref-404-diagnosis-
                // 20261111：旧口径约 38% 助手侧牌点
                // 开必 404）
                // §136：MEDIA: 图片路径已由图片行承
                // 接，一并排除、不再重复成文件牌
                // §143：裸路径图片候选同理排除——图
                // 片永不降为文件卡（查无此图时正文纯
                // 文本就是它的降级形态）
                let fileRefs = FileRefDetector.detectStandaloneAnchored(
                    in: entry.content,
                    excluding: entry.remoteImagePaths
                        + mediaSplit.imagePaths
                        + inlineImages.map(\.path)
                        + (wholePathRef.map { [$0.path] } ?? [])
                )
                if !fileRefs.isEmpty {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingXS
                    ) {
                        ForEach(fileRefs, id: \.path) { ref in
                            AssistantFileChip(path: ref.path) {
                                openChatFile(
                                    ref.path, anchor: ref.anchor
                                )
                            }
                        }
                    }
                    // §265（S3）：文件牌组是铬件——整行
                    // 菜单挂载面之一
                    .modifier(messageMenu(for: entry))
                }
                // §441：选择框挂气泡下方随行滚动（与
                // 审批卡的输入栏上方固定面分工不同）；
                // 无卡/非尾位/演示态恒不出（状态派生
                // 见 optionsCardState），行高由合成器
                // optionsCardSlot 同值预留
                optionsCard(for: entry)
            }
            // §265（S3）：整行菜单自此不在行根挂载（已
            // 下移到气泡背景层与各铬件面，见上）
            // 台账 187：反应 pill 压气泡底角·朝中线
            // 侧（AI 行右下，§334 正名），余口径同用户支
            .overlay(alignment: .bottomTrailing) {
                reactionChrome(for: entry)
                    .offset(
                        x: -ChatReactionMetrics.cornerInset,
                        y: ChatReactionMetrics.hangDepth
                    )
            }
            .modifier(swipeReply(for: entry))
        }
    }

    /// 选择框状态派生（§441）：覆盖层卡与本条目
    /// 钉桩对上才有资格，再按线程尾位/在飞/演示
    /// 态过 Core 纯派生（OptionsCardLogic）
    private func optionsCardState(
        for entry: ChatEntry, in thread: ChatThread
    ) -> OptionsCardState {
        guard let card = appState.optionsOverlay
                .card(for: thread.id),
              entry.serverRowID == card.serverRowID
        else { return .hidden }
        let entries = thread.sortedEntries
        let isTail = entries.last(where: {
            $0.role == "assistant" && $0.toolCard == nil
        })?.id == entry.id
        let hasUserAfter: Bool = {
            guard let index = entries.firstIndex(
                where: { $0.id == entry.id }
            ) else { return false }
            return entries[(index + 1)...].contains {
                $0.role == "user"
            }
        }()
        return OptionsCardLogic.state(
            card: card,
            isTailAssistant: isTail,
            hasUserAfter: hasUserAfter,
            runInFlight: isStreaming || isDrivingRun,
            isDemo: appState.isDemo
        )
    }

    /// 选择框行高输入（§441）：状态非 hidden 才成
    /// facet（行高合成器 optionsCardSlot 消费）
    private func optionsCardHeightInput(
        for entry: ChatEntry, in thread: ChatThread
    ) -> OptionsCardHeightInput? {
        let state = optionsCardState(for: entry, in: thread)
        guard state != .hidden,
              let card = appState.optionsOverlay
                .card(for: thread.id)
        else { return nil }
        return OptionsCardHeightInput(
            state: state,
            optionCount: card.options.options.count
        )
    }

    /// 选择框呈现（§441）：状态 hidden 恒不出行
    @ViewBuilder
    private func optionsCard(for entry: ChatEntry) -> some View {
        if let thread = currentThread {
            let state = optionsCardState(
                for: entry, in: thread
            )
            if state != .hidden,
               let card = appState.optionsOverlay
                .card(for: thread.id) {
                OptionsCardView(
                    state: state,
                    options: card.options.options,
                    onSelect: { option in
                        sendOption(option, in: thread)
                    }
                )
            }
        }
    }

    /// 点选即发（§441）：点任一项＝把该项 sendText
    /// 经既有发送链发出（与键盘发送同路、含 §419
    /// drain 排队）；编辑态/引用/附件在席时忽略点
    /// 选（卡保持 live），不许借道改掉用户正在编
    /// 的发送。点选即消费：先记已选（卡收起为回
    /// 执行），发送失败走 §414 发件箱原位重试、
    /// 卡不复活防双发
    private func sendOption(
        _ option: MessageOption, in thread: ChatThread
    ) {
        guard unsentEditTargetID == nil, attachments.isEmpty,
              pendingQuote == nil, pendingFeedQuote == nil,
              pendingSourceQuote == nil
        else { return }
        appState.optionsOverlay.markSelected(
            threadID: thread.id, label: option.label
        )
        input = option.sendText
        send()
    }

    /// 反应铬件（台账 187＋§432 分工）：镜像非空才
    /// 在场——构建时同步已知（导入/回补/乐观写都
    /// 先落镜像），无异步翻转。按 author 分型两
    /// 面：自己的段走 pill（点段＝撤回，apply-
    /// Reaction 单写口），助手的段走气泡角小角标
    /// （AgentReactionBadgeView，在场判定 Core
    /// AISelfReactionDecision 单点——开关关即不
    /// 在场），两面同角并排、永不合并。视图本体
    /// 在 ChatReactionViews（用户/助手两支共用一
    /// 份形态与挂载几何）
    @ViewBuilder
    private func reactionChrome(for entry: ChatEntry) -> some View {
        let own = MessageReactions.ownReactions(
            in: entry.reactions
        )
        let badge = AISelfReactionDecision.badgeEmoji(
            reactions: entry.reactions,
            featureEnabled: aiSelfReactionsEnabled
        )
        if !own.isEmpty || badge != nil {
            HStack(spacing: 6) {
                if !own.isEmpty {
                    ReactionPillView(
                        reactions: own,
                        onClearOwn: {
                            applyReaction(nil, for: entry)
                        }
                    )
                }
                if let badge {
                    AgentReactionBadgeView(emoji: badge)
                }
            }
        }
    }

    /// 本地图成行（§152）：一条消息的全部本地图并
    /// 排成一行、每张一张 §130 固定高卡——对齐
    /// Muse 多图用户消息形态（并排、同高，用户
    /// 19:11 截图点题）。卡尺寸走 Core ChatImage-
    /// Sizing.rowCardSizes（成行收窄口径单源、钉
    /// 测覆盖）；解码失败的单张不出卡（与旧单图块
    /// 的 UIImage(data:) 守卫同口径），其余照显
    private func localImageRow(
        _ datas: [Data], entry: ChatEntry
    ) -> some View {
        // §199：解码改走本地图解码口（§418 起为
        // LocalImageStore：同条目同图序只解一次、命
        // 中直取）；解码失败单张不出卡的旧口径不变
        // （坏图不入缓存）
        let pairs: [(data: Data, image: UIImage)] =
            datas.enumerated().compactMap { index, data in
                guard let image = LocalImageStore.shared
                    .image(
                        entryID: entry.id, index: index,
                        data: data
                    )
                else { return nil }
                return (data: data, image: image)
            }
        let cardSizes = ChatImageSizing.rowCardSizes(
            for: pairs.map { $0.image.size },
            spacing: OneDayMetrics.spacingS
        )
        return HStack(spacing: OneDayMetrics.spacingS) {
            ForEach(
                Array(zip(pairs, cardSizes).enumerated()),
                id: \.offset
            ) { _, item in
                localImageCard(
                    data: item.0.data, image: item.0.image,
                    cardSize: item.1, entry: entry
                )
            }
        }
    }

    /// 本地图单卡（§130 固定高卡体，§152 自气泡内
    /// 联块抽出、单图与多图成行共用）：卡高恒定
    /// 190、卡宽由调用方经 rowCardSizes 给定（单
    /// 图时等于 cardSize），图居中完整显示不裁
    /// 切、图窄于卡时两侧露 bubbleFill 底；点开
    /// 查看器（0.36.4 集合载荷、同线程可翻页）
    private func localImageCard(
        data: Data, image: UIImage, cardSize: CGSize,
        entry: ChatEntry
    ) -> some View {
        let fittedSize = ChatImageSizing.fittedSize(
            for: image.size, in: cardSize
        )
        return Button {
            openImageViewer(
                ChatImageViewerItem(source: .data(data))
            )
        } label: {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(
                        width: fittedSize.width,
                        height: fittedSize.height
                    )
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .background(
                Palette.bubbleFill,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusCard
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusCard
                )
            )
            // §247.2 试点：同位挂 zoom 源锚点（点开大图
            // 自此卡长出）
            .overlay {
                ZoomSourceAnchor(
                    sourceID: ChatImageViewerItem(
                        source: .data(data)
                    ).id
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
        .buttonStyle(.odPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            A11yText.imageLabel(sentAt: entry.createdAt)
        )
        .accessibilityHint(L10n.string("查看大图"))
    }

    /// 打开图片查看器（0.36.4）：集合＝同线程全部图
    /// 片（本地图 allImageDatas 全集＋远端图 remote-
    /// ImagePaths，按消息时间序、工具卡不占位）；
    /// 点中项不在集合内（如正文文件牌探测出的图）
    /// 时回落单图集合，不假装它在会话图片序里
    private func openImageViewer(_ item: ChatImageViewerItem) {
        var collected: [ChatImageViewerItem] = []
        if let thread = currentThread {
            for entry in thread.sortedEntries
            where entry.toolCard == nil {
                // §152：本地图按全集逐张入集合
                // （旧口径只取 imageData 首图，多
                // 图消息在查看器里同样丢张）
                for data in entry.allImageDatas {
                    collected.append(
                        ChatImageViewerItem(source: .data(data))
                    )
                }
                for path in entry.remoteImagePaths {
                    collected.append(
                        ChatImageViewerItem(source: .remotePath(path))
                    )
                }
            }
        }
        if let index = collected.firstIndex(of: item) {
            imageViewerSession = ImageViewerSession(
                items: collected, initialIndex: index
            )
        } else {
            imageViewerSession = ImageViewerSession(
                items: [item], initialIndex: 0
            )
        }
    }

    /// 文件牌点开（§125 改道）：图片仍直达全屏图片
    /// 查看器（不经中间页，用户认可口径）；非法路径
    /// 仍走 §121 五分 notice 即时拦；其余一律落文件
    /// 打开页（FileOpenView 中间页）——文件头/主钮/
    /// 下载进度/失败态都在页内，取代旧「点牌静默下
    /// 载→直达 QL 或分享单」。§121 的 QL 资格门与五
    /// 分文案机制不变、落点升级进中间页（见 DESIGN
    /// §125 修订声明）
    private func openChatFile(
        _ path: String, anchor: FileLineAnchor? = nil
    ) {
        if FileRefDetector.isImagePath(path) {
            openImageViewer(
                ChatImageViewerItem(source: .remotePath(path))
            )
            return
        }
        if FileOpenFailure.isInvalidPath(path) {
            showNotice(
                FileOpenFailure.invalidPath.message(),
                tier: .persistent
            )
            return
        }
        // §452.6：聊天侧两路直达——可预览走 QuickLook
        // 全屏、不可预览走兜底页，不再经 FileOpenView
        // 中间页（§125 两段式仅文件页侧与引用块重开
        // 保留）；未落盘的先经 ChatFileStore 下载
        // （卡面同源状态），失败落兜底页由其主按钮
        // 承接重试；敏感文件直达兜底页锁定变体
        let target = FileOpenTarget(path: path, anchor: anchor)
        if FileOpenRoute.resolve(target: target) == .locked {
            chatFallbackTarget = target
            return
        }
        if let localURL = ChatFileStore.shared
            .localURL(for: path) {
            presentChatFileRoute(target, localURL: localURL)
            return
        }
        Task {
            do {
                let url = try await ChatFileStore.shared
                    .download(path: path, appState: appState)
                presentChatFileRoute(target, localURL: url)
            } catch {
                chatFallbackTarget = target
            }
        }
    }

    /// 路由呈示（§452.6）：FileOpenRoute 单源判定；
    /// QL 资格以本地文件 canPreview 实测为准——判
    /// quickLook 而 QL 不认、或判 infoOnly 而 QL 能
    /// 认（未知格式），都按实测改道，不按扩展名硬判
    private func presentChatFileRoute(
        _ target: FileOpenTarget, localURL: URL
    ) {
        let qlOK = QLPreviewController.canPreview(
            localURL as NSURL
        )
        switch FileOpenRoute.resolve(target: target) {
        case .imageViewer:
            openImageViewer(
                ChatImageViewerItem(source: .remotePath(target.path))
            )
        case .quickLook:
            if qlOK {
                chatQuickLookItem = ChatQuickLookItem(
                    url: localURL, name: target.name
                )
            } else {
                chatFallbackTarget = target
            }
        case .infoOnly:
            if qlOK {
                chatQuickLookItem = ChatQuickLookItem(
                    url: localURL, name: target.name
                )
            } else {
                chatFallbackTarget = target
            }
        case .saveOnly, .locked:
            chatFallbackTarget = target
        }
    }

    /// 长按菜单的文本口径（0.4.1）：助手消息剥 Markdown
    /// 标记符号成可读文本（MessagePlainText 纯函数），
    /// 用户消息原文即纯文本
    private func plainText(for entry: ChatEntry) -> String {
        // §199：助手侧走条目级备忘（同内容不重剥，
        // Core EntryScanMemo）；用户侧原文直用不变
        entry.role == "assistant"
            ? EntryScanMemo.plainText(
                entryID: entry.id, content: entry.content
            )
            : entry.content
    }

    /// 回复动作（0.4.1 长按菜单立制，0.36.19 起右滑引
    /// 用共用同一入口——两路触发的落点逐字一致：设待
    /// 发送引用、清分流种子标、聚焦输入舱）
    private func beginReply(to entry: ChatEntry) {
        pendingQuote = MessageQuote(
            role: entry.role, content: entry.content
        )
        pendingQuoteIsFork = false
        // §208：引用槽位单一在场——消息引用入槽即
        // 挤掉动态引用（后入覆盖，与讨论写入同律）
        pendingFeedQuote = nil
        // §219：点子／文件引用同槽同律、一并挤掉
        pendingSourceQuote = nil
        composerFocusHandle.focus()
    }

    /// §210：待发动态引用的呈现侧收口——当前线程名
    /// 下有引用在场（AppState 表派生）时：挤掉消息
    /// 引用（槽位单一在场、后入覆盖，与 beginReply
    /// 对动态引用的挤掉同律）、聚焦输入舱（讨论进
    /// 来即可直接打字）。引用本体不在此搬动：它已
    /// 按线程寻址存于 AppState，呈现是派生——§208
    /// 的种子消费（tryApplyFeedSeed）至此退役
    private func applyPendingFeedQuoteIfNeeded() {
        guard pendingFeedQuote != nil else { return }
        pendingQuote = nil
        pendingQuoteIsFork = false
        // §219：槽位单一在场、后入覆盖跨族同律——动
        // 态引用在场收口时，同线程的点子／文件待发引
        // 用一并让位（两表分存、互斥靠收口交叉清理）
        if let currentThreadID {
            appState.pendingQuotes.sourceQuotesByThread
                .removeValue(forKey: currentThreadID)
        }
        composerFocusHandle.focus()
    }

    /// §219：待发点子／文件引用的呈现侧收口——与
    /// applyPendingFeedQuoteIfNeeded 同式：当前线程
    /// 名下有引用在场时挤掉消息引用、让位同线程的
    /// 动态待发引用（后入覆盖）、聚焦输入舱。引用
    /// 本体已按线程寻址存于 AppState，呈现是派生
    private func applyPendingSourceQuoteIfNeeded() {
        guard pendingSourceQuote != nil else { return }
        pendingQuote = nil
        pendingQuoteIsFork = false
        pendingFeedQuote = nil
        composerFocusHandle.focus()
    }

    /// §152 选区在场记账（141/142 根治后形态）：
    /// 正文文本块（SelectableInlineText）经 onSe-
    /// lectionChange 回报——记账只落 ChatRowState-
    /// Ledger（永不进 @State：@State 写触发 body
    /// 重算、旧制还把选区折进行修订，选区一形成
    /// 该行即被重配换代、文本视图本体被拆，选区/
    /// 编辑菜单当场被冲——141/142 的共同病根）。
    /// 两个消费方都在事件时刻直读账本/句柄，不经
    /// 渲染管线：①右滑引用在 pan 回调时刻查账本
    /// 停用（SwipeReplyModifier.isSuppressed）；
    /// ②原生面把选区行键同步给句柄，控制器分流
    /// 据此暂存该行重配（选区清账后 flush）。消选
    /// 延迟 350ms 清账在账本内（防同条换块选字时
    /// 旧块消选先于新块报选到达、把保护误清）
    private func noteTextSelection(entryID: UUID, active: Bool) {
        rowStateLedger.noteTextSelection(
            entryID: entryID, active: active,
            onProtectionEnded: { [nativeHandle] in
                nativeHandle.selectionActiveRowKey = nil
                nativeHandle.noteSelectionProtectionEnded()
            }
        )
        if active {
            nativeHandle.selectionActiveRowKey =
                streamSettleMap.rowKey(for: entryID)
                ?? "entry-\(entryID.uuidString)"
        }
    }

    /// 反应浮排呈现场（DESIGN §343）：挂钩自长按挂
    /// 载点回调用——呈现时刻组装菜单数据（与系统菜
    /// 单同一 actionSheetData 单源）、记挂载帧作快
    /// 照原位对齐原点
    private func presentReactionBar(
        for entry: ChatEntry, frame: CGRect
    ) {
        // 选字在场让行（§152 同口径：选区优先、浮
        // 排不抢本行正在进行的选字）
        guard rowStateLedger.textSelectionEntryID != entry.id
        else { return }
        // §471：动画三段状态复位（入场由 overlay 的
        // onAppear 按 ReactionBarMotion 时序推进）
        reactionBarBgShown = false
        reactionBarSnapshotShown = false
        reactionBarChromeShown = false
        reactionBarDismissing = false
        reactionBarSession = ReactionBarSession(
            entryID: entry.id,
            data: actionSheetData(for: entry),
            sourceFrame: frame,
            alignsTrailing: entry.role == "user"
        )
    }

    /// §471 浮排入场时序（Exyte 三段：背景与快照
    /// 同拍起、药丸/卡延迟 0.33D 后以 bouncy 入
    /// 场）：各段独立 withAnimation、各用各的曲线
    /// （ReactionBarMotion），同一时钟不混曲线
    private func beginReactionBarEntrance() {
        withAnimation(ReactionBarMotion.backgroundIn) {
            reactionBarBgShown = true
        }
        withAnimation(ReactionBarMotion.messageIn) {
            reactionBarSnapshotShown = true
        }
        Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(ReactionBarMotion.stageDelay)
            )
            guard reactionBarSession != nil,
                  !reactionBarDismissing else { return }
            withAnimation(ReactionBarMotion.chromeIn) {
                reactionBarChromeShown = true
            }
        }
    }

    /// §471 浮排收起（全 overlay 内收起路单点）：
    /// 药丸/卡/快照先以 snappy(0.2) 退场、背景延
    /// 迟 0.33D 后 easeOut 淡出，全程走完才摘会
    /// 话——不再 session=nil 整组瞬时消失。投递
    /// 路（pick/pickAction 成功后）同走本路
    private func dismissReactionBar() {
        guard reactionBarSession != nil,
              !reactionBarDismissing else { return }
        reactionBarDismissing = true
        withAnimation(ReactionBarMotion.chromeOut) {
            reactionBarChromeShown = false
            reactionBarSnapshotShown = false
        }
        withAnimation(ReactionBarMotion.backgroundOut) {
            reactionBarBgShown = false
        }
        Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(ReactionBarMotion.dismissalTotal)
            )
            reactionBarSession = nil
            reactionBarDismissing = false
        }
    }

    /// 浮排 overlay（DESIGN §343／§346／§440）：
    /// 一次呈现三层——压暗＋原消息快照＋药丸排在
    /// 上＋动作卡在下，定位全走 ReactionBar-
    /// Placement.layout 的整摞契约（§440：药丸贴
    /// 带上、卡贴带下、整摞平移进安全区视口）。
    /// 快照＝bubble 本体活复刻（allowsHitTesting
    /// 关、渲染走原单源不另抄样式），按可见带钳
    /// 高、裁切边渐隐，落位走 layout 的
    /// snapshotPlacementY；点快照/点空白/在压暗
    /// 区拖动（滚动意图）同路收起（§440 补拖动
    /// 路——点外即散不分轻点还是拖动）
    /// §471（病二）：背景改 Exyte 双层——.ultra-
    /// ThinMaterial 虚化＋.primary.opacity(0.1)
    /// 压暗（代原 Color.black 0.32 单层平压）；原
    /// 泡由 entryRowContent 在浮排期间摘除
    /// （opacity 0），快照原位独呈、不再双份叠印
    /// §471（病三）：入/出场全走 ReactionBar-
    /// Motion 时钟（背景/快照/药丸卡三段状态），
    /// 收起一律经 dismissReactionBar 逆序退场
    @ViewBuilder
    private func reactionBarOverlay(
        _ session: ReactionBarSession
    ) -> some View {
        GeometryReader { screen in
            let frame = session.sourceFrame
            // §440：视口 insets 走 key window 实读单
            // 源——根 GeometryReader 挂 ignoresSafe-
            // Area（保全屏坐标原点、快照与原消息同
            // 系）时其 safeAreaInsets 恒为零，旧写法
            // 视口因此退化成全屏（H0 定因）；反之摘
            // 掉根修饰又会把整个浮层坐标原点压进安
            // 全区（实测整摞下移 62、快照与原消息
            // 错位）。两头都不行：原点归全屏、insets
            // 归 window，两量分开取
            let insets = Self.keyWindowSafeAreaInsets
            let viewport = CGRect(
                x: insets.leading,
                y: insets.top,
                width: screen.size.width
                    - insets.leading - insets.trailing,
                height: screen.size.height
                    - insets.top - insets.bottom
            )
            let items = session.data.actionItems()
            let layout = ReactionBarPlacement.layout(
                sourceFrame: frame,
                alignsTrailing: session.alignsTrailing,
                viewport: viewport,
                itemCount: items.count
            )
            ZStack(alignment: .topLeading) {
                // §471 病二背景双层（Exyte 原文参数）：
                // 材料虚化＋主色 10% 压暗；整体随
                // reactionBarBgShown 淡入/淡出
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                }
                .ignoresSafeArea()
                .opacity(reactionBarBgShown ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissReactionBar()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { _ in
                            dismissReactionBar()
                        }
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(
                    L10n.string("关闭")
                )
                .accessibilityAction {
                    dismissReactionBar()
                }
                if let entry = currentThread?.sortedEntries
                    .first(where: { $0.id == session.entryID }) {
                    reactionSnapshot(
                        entry, frame: frame, layout: layout
                    )
                    Color.clear
                        .frame(
                            width: layout.snapshotVisibleRect.width,
                            height: layout.snapshotVisibleRect.height
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissReactionBar()
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { _ in
                                    dismissReactionBar()
                                }
                        )
                        .offset(
                            x: layout.snapshotVisibleRect.minX,
                            y: layout.snapshotPlacementY
                        )
                }
                ReactionFloatingBarView(
                    ownEmoji: session.data.ownEmoji
                ) { emoji in
                    if session.pick(emoji) {
                        dismissReactionBar()
                    }
                }
                // §471 病三：药丸随 chrome 段入场
                // （bouncy＋下移 8pt 回位＋淡入），
                // 收起同段逆放
                .opacity(reactionBarChromeShown ? 1 : 0)
                .offset(
                    x: layout.barOrigin.x,
                    y: layout.barOrigin.y
                        + (reactionBarChromeShown ? 0 : 8)
                )
                ReactionActionCardView(items: items) { item in
                    if session.pickAction(item) {
                        dismissReactionBar()
                    }
                }
                .frame(
                    width: layout.cardSize.width,
                    height: layout.cardSize.height
                )
                // §471 病三：动作卡随 chrome 段入场
                // （与药丸同一 bouncy 时钟）
                .opacity(reactionBarChromeShown ? 1 : 0)
                .offset(
                    x: layout.cardOrigin.x,
                    y: layout.cardOrigin.y
                        + (reactionBarChromeShown ? 0 : 8)
                )
            }
            .frame(
                width: screen.size.width,
                height: screen.size.height
            )
        }
        .ignoresSafeArea()
        .onAppear { beginReactionBarEntrance() }
    }

    /// §440：key window 的安全区 insets（浮排视口
    /// 单源）。取路与 DeviceTopmostPresenter 同
    /// （connectedScenes→keyWindow）；浮排根
    /// GeometryReader 的 safeAreaInsets 因根挂
    /// ignoresSafeArea 恒为零、不可作数
    private static var keyWindowSafeAreaInsets: EdgeInsets {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let keyWindow = windows.first { $0.isKeyWindow }
            ?? windows.first
        let ui = keyWindow?.safeAreaInsets ?? .zero
        return EdgeInsets(
            top: ui.top,
            leading: ui.left,
            bottom: ui.bottom,
            trailing: ui.right
        )
    }

    /// 浮排快照（DESIGN §346）：无裁切＝原位全帧
    /// 复刻（与第一步同路）；有裁切＝可见带容器内
    /// 按原帧偏移、clipped＋裁切边渐隐 mask。可见
    /// 带高 0（极端贴边行）整快照不出
    @ViewBuilder
    private func reactionSnapshot(
        _ entry: ChatEntry,
        frame: CGRect,
        layout: ReactionBarLayout
    ) -> some View {
        let visible = layout.snapshotVisibleRect
        if visible.height > 0 {
            if layout.clipsTop || layout.clipsBottom {
                bubble(entry)
                    .frame(
                        width: frame.width,
                        alignment: .topLeading
                    )
                    .allowsHitTesting(false)
                    .shadow(
                        color: .black.opacity(0.22),
                        radius: 16, y: 6
                    )
                    // §471 病三：就位动画——快照自原
                    // 位 1.0 升至抬起 1.02（Exyte
                    // messageIn easeInOut 0.4 驱动
                    // reactionBarSnapshotShown），兼
                    // 作长按识别时刻的按下反馈
                    .scaleEffect(
                        reactionBarSnapshotShown ? 1.02 : 1.0
                    )
                    .opacity(reactionBarSnapshotShown ? 1 : 0)
                    .offset(y: frame.minY - visible.minY)
                    .frame(
                        width: visible.width,
                        height: visible.height,
                        alignment: .topLeading
                    )
                    .clipped()
                    .mask(snapshotFadeMask(layout))
                    .offset(
                        x: visible.minX,
                        y: layout.snapshotPlacementY
                    )
            } else {
                bubble(entry)
                    .frame(
                        width: frame.width,
                        alignment: .topLeading
                    )
                    .allowsHitTesting(false)
                    .shadow(
                        color: .black.opacity(0.22),
                        radius: 16, y: 6
                    )
                    // §471 病三：就位动画（同裁切支）
                    .scaleEffect(
                        reactionBarSnapshotShown ? 1.02 : 1.0
                    )
                    .opacity(reactionBarSnapshotShown ? 1 : 0)
                    .offset(
                        x: frame.minX,
                        y: layout.snapshotPlacementY
                    )
            }
        }
    }

    /// 快照裁切边渐隐 mask（DESIGN §346）：仅裁切
    /// 边生效——28pt 线性淡出（带高不足时按比收
    /// 窄），未裁切边实色直通
    private func snapshotFadeMask(
        _ layout: ReactionBarLayout
    ) -> LinearGradient {
        let height = layout.snapshotVisibleRect.height
        let fade = height > 56 ? 28 / height : 0.25
        var stops: [Gradient.Stop] = [
            .init(
                color: layout.clipsTop ? .clear : .black,
                location: 0
            ),
        ]
        if layout.clipsTop {
            stops.append(
                .init(color: .black, location: fade)
            )
        }
        if layout.clipsBottom {
            stops.append(
                .init(color: .black, location: 1 - fade)
            )
        }
        stops.append(
            .init(
                color: layout.clipsBottom ? .clear : .black,
                location: 1
            )
        )
        return LinearGradient(
            stops: stops,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 气泡长按动作面挂载（0.4.1 立制；台账 187 换
    /// 代）：门控与原生面同口径（台账 186——纯图片
    /// 条目同挂、长按没反应的旧口径已废；文本依赖
    /// 项在面内按 plainText 有无组装）
    /// §265（S3）：本修饰符只许挂非文本面（气泡背景
    /// 层与铬件），挂载点清单见 DESIGN §265；长按
    /// 只置呈现状态，动作集在呈现时刻组装（action-
    /// SheetData），两面同开系统上下文菜单
    /// §471 口径变更：§265「文本区长按归 UITextView
    /// 原生选字」一句作废——列表态正文已关直接选
    /// 字（SelectableInlineText allowsDirect-
    /// Selection=false），长按一切落点归本菜单/浮
    /// 排，选字唯一入口＝菜单「选择」行（iMessage
    /// iOS 26 同构）；挂载面纪律本身不变
    private func messageMenu(for entry: ChatEntry) -> MessageMenuModifier {
        MessageMenuModifier(
            isEnabled: !entry.content.isEmpty
                || !entry.allImageDatas.isEmpty
                || !entry.remoteImagePaths.isEmpty,
            floatingBarHook: ReactionBarRouting.route(
                flagEnabled: floatingBarEnabled,
                canReact: entry.canReact
            ) == .floatingBar
                ? { frame in
                    presentReactionBar(for: entry, frame: frame)
                }
                : nil,
            menuSuppressed: reactionBarSession?.entryID
                == entry.id,
            makeData: { actionSheetData(for: entry) }
        )
    }

    /// 右滑引用挂载（0.36.19，§84.3）：与长按菜单同门
    /// 控（纯图片消息不挂）——自己与对方的消息都可滑，
    /// 触发走 beginReply 同一入口；与长按菜单并存不
    /// 互斥（长按是静止按压、右滑是横向拖动，形态不
    /// 重叠）
    private func swipeReply(for entry: ChatEntry) -> SwipeReplyModifier {
        SwipeReplyModifier(
            // §152 的选区停用自 141/142 根治起不再
            // 走 isEnabled（结构翻转＝行重渲染＝原
            // 生面托管换代、冲选区）：改经 isSup-
            // pressed 在 pan 回调时刻直读账本停用
            // （选字优先，DESIGN §152.3 第 4 条）；
            // isEnabled 只余「空文本不挂」的稳定口径
            isEnabled: !entry.content.isEmpty,
            isSuppressed: { [rowStateLedger] in
                rowStateLedger.textSelectionEntryID
                    == entry.id
            },
            onReply: {
                beginReply(to: entry)
            }
        )
    }

    /// 分流动作（0.7.0，M4 超越位）：以这条消息为引用种
    /// 子新建一条旁聊并切过去——原线程上下文不带过去，
    /// 种子经 pendingForkQuote 穿过切换时的引用清理转入
    /// 新旁聊待发送引用（见 body 的 onChange）；新旁聊标
    /// 题走既有首句派生（send() 的「新会话」定题）
    private func forkToSideChat(from entry: ChatEntry) {
        let thread = ChatThread()
        modelContext.insert(thread)
        try? modelContext.save()
        pendingForkQuote = MessageQuote(
            role: entry.role, content: entry.content
        )
        currentThreadID = thread.id
        composerFocusHandle.focus()
    }

    /// 已发送消息顶部的引用块（0.4.1）：小字、次级色、
    /// 左细线——只作回指，不抢正文层级；摘要与引用条
    /// 共用 MessageQuote.summary 同一口径
    private func quoteBlock(_ quote: MessageQuote) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Rectangle()
                .fill(Palette.inkMuted)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                // 0.36.22：引用标签的助手称呼跟随档案名
                Text(MessageQuote.speakerName(
                    for: quote.role,
                    assistantName: appState.agentDisplayName
                ))
                    // 0.4.1 第 9 修：引用块在消息流内、
                    // 其标签同守 regular 基准（旧 caption2
                    // semibold 撤销，层级靠色与字号）
                    // 0.23.0（审计 G6）：caption2（11）退
                    // 出文字位，升 caption 档（12）——说话
                    // 人名签属微标签，与总览微标签同组登记
                    // （§50），不走 badgeOnly 角色
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                Text(quote.summary(maxLength: 80))
                    .font(.caption)
                    // 0.4.4（§29）：摘要是被引的正文本
                    // 身、墨随正文换 bodyInk；说话人名
                    // 是标签、仍 inkSecondary（层级靠字
                    // 号＋左细线＋底垫，不靠墨深）
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
            }
        }
        .padding(OneDayMetrics.spacingS)
        .background(
            Palette.fieldFill,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
        )
    }

    /// 已发送消息顶部的动态引用块（§208）：几何与
    /// quoteBlock 同（左细线＋底垫＋小字），内容＝帖
    /// 标题行＋正文摘要一行；整块可点回跳动态原帖
    /// （feedOpenPostRequest 置位＋切动态格，FeedView
    /// 消费定位；帖已不在时 FeedView 给诚实提示，
    /// 本块快照内容不受影响仍可读）
    private func feedQuoteBlock(_ quote: FeedPostQuote) -> some View {
        Button {
            appState.router.feedOpenPostRequest = quote.postID
            appState.router.mainTabSwitchRequest = .feed
        } label: {
            HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                Rectangle()
                    .fill(Palette.inkMuted)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(quote.mark.isEmpty
                        ? quote.title
                        : "\(quote.mark) \(quote.title)")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    Text(quote.summary(maxLength: 80))
                        .font(.caption)
                        .foregroundStyle(Palette.bodyInk)
                        .lineLimit(2)
                }
            }
            .padding(OneDayMetrics.spacingS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Palette.fieldFill,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到动态原帖")
    }

    /// 已发送消息顶部的来源引用块分发（§219）：
    /// 三族共用消息行槽位，按族渲染各自块形态
    /// （几何同源：左细线＋底垫＋小字两行）
    @ViewBuilder
    private func sourceQuoteBlock(
        _ quote: SourceQuote
    ) -> some View {
        switch quote {
        case .feed(let feedQuote):
            feedQuoteBlock(feedQuote)
        case .idea(let ideaQuote):
            ideaQuoteBlock(ideaQuote)
        case .file(let fileQuote):
            fileQuoteBlock(fileQuote)
        case .goal(let goalQuote):
            goalQuoteBlock(goalQuote)
        }
    }

    /// 已发送消息顶部的点子引用块（§219）：几何与
    /// feedQuoteBlock 同，内容＝点子标题行＋载荷摘
    /// 要一行；整块可点回跳点子详情（ideaOpen-
    /// Request 置位＋切点子格，IdeasView 消费定位；
    /// 点子已不在时 IdeasView 给诚实提示，本块快
    /// 照内容不受影响仍可读）
    private func ideaQuoteBlock(_ quote: IdeaQuote) -> some View {
        Button {
            appState.router.ideaOpenRequest = quote.ideaID
            appState.router.mainTabSwitchRequest = .ideas
        } label: {
            HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                Rectangle()
                    .fill(Palette.inkMuted)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(quote.mark.isEmpty
                        ? quote.title
                        : "\(quote.mark) \(quote.title)")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    Text(quote.summary(maxLength: 80))
                        .font(.caption)
                        .foregroundStyle(Palette.bodyInk)
                        .lineLimit(2)
                }
            }
            .padding(OneDayMetrics.spacingS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Palette.fieldFill,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到点子")
    }

    /// 已发送消息顶部的文件引用块（§219）：几何同
    /// 族，内容＝文件名行＋原路径摘要一行；整块可
    /// 点以快照路径直接重开文件页（fileOpenTarget
    /// 既有通道，不切格）；文件已被移走时文件页本
    /// 身如实呈现打不开，不在此假装
    private func fileQuoteBlock(_ quote: FileQuote) -> some View {
        Button {
            fileOpenTarget = quote.target
        } label: {
            HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                Rectangle()
                    .fill(Palette.inkMuted)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(quote.name)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    Text(quote.summary(maxLength: 80))
                        .font(.caption)
                        .foregroundStyle(Palette.bodyInk)
                        .lineLimit(2)
                }
            }
            .padding(OneDayMetrics.spacingS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Palette.fieldFill,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开文件")
    }

    /// 已发送消息顶部的目标创建引用块（§238）：几何
    /// 同族，内容＝「新建目标：类名」行＋介绍首句摘
    /// 要一行；整块可点回目标格（目标在对话里聊定后
    /// 由智能体落桥、出现在目标页；还没聊定时目标页
    /// 自然还没有它，本块快照内容不受影响仍可读）
    private func goalQuoteBlock(_ quote: GoalQuote) -> some View {
        Button {
            appState.router.mainTabSwitchRequest = .goals
        } label: {
            HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                Rectangle()
                    .fill(Palette.inkMuted)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(quote.title)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    Text(quote.summary(maxLength: 80))
                        .font(.caption)
                        .foregroundStyle(Palette.bodyInk)
                        .lineLimit(2)
                }
            }
            .padding(OneDayMetrics.spacingS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Palette.fieldFill,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到目标")
    }

    /// 助手消息行（0.2.5 曾定浅灰软填充泡＋圆角卡，见下
    /// 改判沿革）：左对齐、右侧留白上限与用户泡的 44pt
    /// 让位同逻辑，内外边距沿旧泡口径。
    /// 割裂感 A 止血档 A1 改判（2026-11-13，用户 17:02
    /// 拍板提队）：撤 bubbleFill 背景——散文直落
    /// chatSurface 大面（助手散文不成卡；代码块/表格/
    /// 工具卡/文件卡等异构件保留各自承载，本函数只包
    /// 散文与流式半截/等待点，两者同路落面）。泡内子件
    /// 对比账当时按调研 A1 逐项复核：次级文字落面后两
    /// 档均升（原泡面 #EEEEF0 上 5.04／5.29），子件无
    /// 一因落面跌破原账，令牌零改动。
    /// §225 再改判（2026-11-14，用户 09:46 点选三项
    /// 全改＋亲口澄清形态）：**恢复气泡**——A1 撤泡口
    /// 径作废。用户原话钉死形态：「气泡的内容是纯文
    /// 字，不是把气泡颜色改没」：泡只是中性浅灰容
    /// 器，正文维持现行纯文字呈现与排版，不做彩色
    /// 卡、不加描边/阴影、不改字色字阶。落法＝恢复
    /// A1 撤销的背景层（bubbleFill＋assistantBubble-
    /// Corner 22），几何与 A1 前逐字一致；填充
    /// #EEEEF0 与 Muse 真机实测 #E9EAEC 仅 Δ≈4–5
    /// （muse-color-drawer-diff-20261114.md），用库
    /// 存令牌不新造色。泡内子件对比回位 A1 前原账
    /// （inkSecondaryOnFill 对 #EEEEF0＝5.04:1）。波
    /// 及面：代码块/表格在 MarkdownText 内部以自身次
    /// 档填充渲染、零改动，只随正文一同被泡面包住；
    /// 异构件在本函数之外、不受影响。函数名沿旧名
    /// 以保调用点零改动与沿革可追。
    /// §321 三度改判（2026-11-17，用户真机录屏实报
    /// 「回复消息怎么还是这种？大厂怎么做的？和大
    /// 厂对齐」）：§225 恢复气泡口径**作废**——助手
    /// 回复对齐 Muse/Muse 式无气泡呈现：撤
    /// bubbleFill 填充，散文直落 chatSurface（与 A1
    /// 同形），§225「内容是纯文字」的本意保留（正
    /// 文排版/字阶/字色逐字不动，被撤的只是承载
    /// 面）。与 A1 的差别：§265 整行菜单的宿主背
    /// 景层保留（填充改 .clear——菜单挂载面与内边
    /// 距带命中不依赖填充色），几何 §263 逐值不动
    /// （列宽/左缘/内边距全保留，量测喂入同值、行
    /// 高产物零失效）；代码块/表格等异构件自有填
    /// 充逐字不动、只不再被泡面包住。原生散文
    /// cell 当时同步撤填充（§321 注）；§325 起散
    /// 文 cell 整件退役、本函数即唯一呈现口径。
    /// 全档 reply-rendering-alignment-20261117.md。
    /// §334 四度改判（2026-11-21，台账 191，用户
    /// 00:36 纠正＋00:38 拍板「AI 气泡也上底色、
    /// 双边都有泡」）：§321 无气泡口径**作废**——
    /// 背景层填充恢复 Palette.bubbleFill（浅
    /// #EEEEF0／暗 #2C2C2E，令牌本体零改动、本函
    /// 数是助手正文唯一填充口：落定/流式/等待点
    /// 四态同宿主，grep 全量核对无第二填充口）。
    /// §321 的正文排版口径（17/22、段距 16、字阶
    /// 字色）保留不动、只改判容器；§263 几何逐值
    /// 不动（列宽/左缘/内边距），行高产物零失效；
    /// 进泡＝正文/引用/代码块（泡内 codeFill 次
    /// 档）/表格（泡内横滚），推理块/工具卡/图
    /// 片/文件牌/交付项维持独立承载。AI 泡对比走
    /// 新立闸⑧（字/泡 ≥4.5、泡/页 ∈[1.10,1.60]，
    /// 与用户泡闸⑦成套）；登记 DESIGN §334，出
    /// 图 pkg-191-ai-bubble-design-20261121.md。
    private func assistantBubble<Content: View>(
        menuEntry: ChatEntry? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        // §263：正文列几何对齐 Muse 同机实测——左缘
        // ＝屏宽×左缘占屏比（402pt 屏上 33pt）、文宽
        // ＝屏宽×文宽占屏比（≈309pt）。旧账左缘＝
        // pageGutter＋bubblePaddingH＝36、列宽被侧让
        // 位 44 封在 W−116；新落法：左缘差额以负
        // leading 收（按比例、随屏宽变），列宽以气
        // 泡 maxWidth 封顶（短文仍可抱合、长文封顶
        // 换行），量测喂入同值（LayoutProductService
        // .textWidth 单源）。用户泡几何不动
        let screenWidth = UIScreen.main.bounds.width
        let columnCap = screenWidth
            * OneDayMetrics.assistantTextWidthFraction
            + OneDayMetrics.bubblePaddingH * 2
        let leading = screenWidth
            * OneDayMetrics.assistantTextLeadingFraction
            - OneDayMetrics.pageGutter
            - OneDayMetrics.bubblePaddingH
        let base = HStack(alignment: .top) {
            content()
                .padding(.horizontal, OneDayMetrics.bubblePaddingH)
                .padding(.vertical, OneDayMetrics.bubblePaddingV)
                .background {
                    // §265（换代包 5·S3）：落定行传
                    // menuEntry 时整行菜单挂本背景层
                    // （气泡背景＋内边距带）——与用户泡
                    // 同口径：背景层不是文本视图的祖
                    // 先，长按文本归 UITextView 原生；
                    // 流式泡不传（无菜单、形态逐字不变）
                    // §321：填充改 .clear——本层自此只
                    // 作菜单宿主、不再是可见气泡面（助
                    // 手散文直落 chatSurface）；形状与
                    // 挂载点逐字不动，菜单命中带不变
                    // §334（台账 191）：填充恢复
                    // Palette.bubbleFill——双边都有泡；
                    // 本层仍是 §265 菜单宿主，形状/挂载
                    // 点/命中带逐字不动，只恢复填充
                    RoundedRectangle(
                        cornerRadius:
                            OneDayMetrics.assistantBubbleCorner
                    )
                    .fill(Palette.bubbleFill)
                }
                .frame(maxWidth: columnCap, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.leading, leading)

        if let menuEntry {
            return AnyView(base.modifier(messageMenu(for: menuEntry)))
        } else {
            return AnyView(base)
        }
    }

    @ViewBuilder
    /// 回告卡（0.7.0，D2）：总览桥通知在主线消息流末尾的
    /// 呈现层卡片。点卡身开枢纽 sheet 看全量（0.17.0 改
    /// 道、此前是跳活动格）；点叉＝标已读
    /// （走 OverviewBridgeStore.markRead：桥确认成功才改
    /// 本地态，卡随未读过滤消失，与铃铛/通知 sheet 同一
    /// 已读口径）。卡是纯 View：不入 SwiftData、不参与
    /// 发送上下文组装
    /// 回响数据源刷新（P2 会话包）：主线拉近百条全
    /// 量（物化窗口收窄在 Core 规划）、旁聊只拉指向
    /// 本会话的（桥侧 targetId 过滤）。拉取失败保留已
    /// 有值、不清空不报错——桥一时不通不该在对话里
    /// 另摆错误面，下次触发自会再拉；但也不许拿空结
    /// 果冒充「没有动作发生」。触发点两处：进页/切线
    /// 程（.task(id:)）、每轮生成落定（流式下降沿，
    /// 2026-11-13 补——AI 的内部动作恰在本轮内发生，
    /// 只等切线程才刷等于当轮无回响）。
    /// §229：拉成后同轮物化——留痕落成真条目（事件
    /// 时间归位），呈现层流尾拼装自此退役；物化目标
    /// 是拉取发起时的线程，拉取在途切了线程则本轮
    /// 只更新缓冲、不落盘（新线程的 .task 会自带一
    /// 轮刷新，不许把甲线程的回响落进乙线程）
    private func refreshEchoTraces() async {
        guard let config = appState.config else { return }
        guard let thread = currentThread else { return }
        let threadID = thread.id
        let isMain = isCurrentMainThread
        let client = OneDayBridgeClient()
        do {
            let fetched: [BridgeTrace]
            if isMain {
                fetched = try await client.traces(
                    config: config, limit: 100
                )
            } else if let sessionID = thread.serverSessionID {
                fetched = try await client.traces(
                    config: config, limit: 100,
                    targetId: sessionID
                )
            } else {
                return
            }
            echoTraces = fetched
            guard currentThread?.id == threadID else { return }
            TraceEchoMaterializationRunner.run(
                traces: fetched,
                thread: thread,
                isMainThread: isMain,
                agentName: appState.agentDisplayName,
                context: modelContext
            )
        } catch {
            // 保留已有回响（见函数头注）
        }
    }

    private func reportCard(
        _ item: OverviewNotification, store: OverviewBridgeStore
    ) -> some View {
        // §379：整卡迁原生 Button（原点按手势＋自研按压
        // 修饰退役）；点按落点不变——开枢纽 sheet
        // （0.17.0 口径）。卡内 ✕ 本就是真 Button、不能
        // 嵌 Button，按 §363 文件卡先例改同位覆盖层兄弟
        // 件：原布局盒留同值占位保文本列宽，✕ 以卡内边距
        // 同位覆盖；已知差同 §363——按压缩放只作用卡体、
        // ✕ 不随动
        ZStack(alignment: .topTrailing) {
            Button {
                showHub = true
            } label: {
                HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Palette.inkSecondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                        if !item.body.isEmpty {
                            Text(item.body)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(3)
                        }
                    }
                    Spacer(minLength: 0)
                    // ✕ 占位：与覆盖层 ✕ 的布局盒同值
                    Color.clear
                        .frame(
                            width: OneDayMetrics.minTapTarget,
                            height: OneDayMetrics.minTapTarget
                        )
                }
                .padding(OneDayMetrics.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Palette.surface,
                    in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            Button {
                Task { await store.markRead(appState: appState, id: item.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .regular))
                    // 0.23.0：功能字形随条内 ✕ 同档归
                    // inkSecondary（原 inkMuted）
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 24, height: 24)
                    // 0.23.0（命中域审计）：视觉 24 不变、
                    // 命中域外扩 44（CopyButton 同款两层帧）
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("标为已读")
            .padding(OneDayMetrics.spacingM)
        }
    }

    // MARK: - 输入与错误

    /// 导入等待卡（基础止血包 P6）：菊花＋一行人话，
    /// 居中偏上、卡面沿既有表面件（surface＋hairline
    /// 描边，与引导卡同族）；不挡操作（allowsHit-
    /// Testing false）——导入防重入由 importing-
    /// SessionID 闸自理，呈现只管让人知道在动
    private var importingOverlay: some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            ProgressView()
            Text(L10n.string("正在载入这段对话…"))
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
            // §237 P6：分页导入的已落盘计数——首批
            // 到手即有数字，不等全量
            if let loaded = importingLoadedCount, loaded > 0 {
                Text("已载入 \(loaded) 条")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .monospacedDigit()
            }
        }
        .padding(OneDayMetrics.spacingL)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner
            )
            .strokeBorder(Palette.hairline, lineWidth: 1)
        }
        .frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: .top
        )
        .padding(.top, 140)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("正在载入这段对话"))
    }

    /// 导入失败重试行（基础止血包 P6）：与错误横幅
    /// 同族形态（hairline 顶线＋pageBG），文案在横幅
    /// 里（服务端原因已由 openServerSession 写进
    /// errorMessage），本行只承动作：重试（以原出处
    /// 重走 runImport）与关闭
    /// 同步状态行（§331，会话头安静标记）：当前线
    /// 程历史未同步完/种子有欠账时在发送区上方给
    /// 一行小字——事实可见、不弹窗、不带按钮（重
    /// 试由后台调度自理，用户无事可做就不许给动
    /// 作）。文案口径：未同步完带进度（已载入 N/
    /// 共 M 条，M 未知时只报 N）；种子仅文本落定
    /// 是这条线程的长久事实、常驻呈现，不许把「仅
    /// 文本」冒充全量同步。2026-11-22 抽屉量测对
    /// 齐包订正：仅本地保留（.localOnly）的常驻文
    /// 案「部分早期历史仅保存在本机」按用户亲令整
    /// 句删除——该状态用户同样无事可做、常驻一行
    /// 只是长期占位（状态与同步逻辑本体不动，落
    /// 定时的一次性通知保留）
    @ViewBuilder
    private var historySyncBar: some View {
        if let thread = currentThread,
           let text = historySyncText(for: thread) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .transition(.opacity)
        }
    }

    private func historySyncText(for thread: ChatThread) -> String? {
        if thread.historyUnsynced {
            return "历史未同步完 · "
                + SessionHistorySync.progressText(
                    loaded: thread.historyLoadedCount,
                    serverTotal: thread.historyServerCount
                )
        }
        switch thread.seedSyncState {
        case .pending, .importing:
            return "本地历史同步中…"
        case .failed:
            return "本地历史同步失败，稍后自动重试"
        case .localOnly:
            // 2026-11-22：常驻文案按用户亲令删除
            // （见 historySyncBar 注）——状态本体与
            // 同步逻辑不动，本行只是不再呈现
            return nil
        case .syncedTextOnly:
            return "本地历史已同步（仅文本）"
        case .notOwed, .serverHeld:
            return nil
        }
    }

    private func importRetryBar(
        _ context: (sessionID: String, channelID: String?)
    ) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
                Text("这段对话没能载入")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button {
                    importRetryContext = nil
                    Task {
                        await runImport(
                            sessionID: context.sessionID,
                            channelID: context.channelID
                        )
                    }
                } label: {
                    Text("重试")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.primary)
                        .frame(minHeight: OneDayMetrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                Button {
                    importRetryContext = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(
                            width: OneDayMetrics.minTapTarget,
                            height: OneDayMetrics.minTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("关闭")
                .buttonStyle(.odPressable)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.vertical, OneDayMetrics.spacingS)
        }
        .background(Palette.pageBG)
    }

    /// G-03 错误横幅赋值口（§389）：HermesError 驱
    /// 动的失败一律走此口——主文案＝userMessage
    /// （人话、无状态码/子系统名）、详情＝
    /// diagnosticDetail（技术原文只许在此，缺省
    /// nil 时横幅不显详情钮）、时刻＝当下。字面文
    /// 案赋值点不走此口（本就人话、无技术原文可
    /// 收），其时刻由组装口 onChange 补记。
    /// 发送失败机制包补同文去抖：同文案同详情已在
    /// 席时不刷新时刻不重建——旧口径无条件覆写，
    /// 失败环里横幅以失败周期整条重建（录屏叠字
    /// 的呈现一环）
    private func presentError(_ error: HermesError) {
        if errorMessage == error.userMessage,
           errorDetail == error.diagnosticDetail {
            return
        }
        errorMessage = error.userMessage
        errorDetail = error.diagnosticDetail
        errorOccurredAt = Date()
        errorDetailExpanded = false
    }

    /// 发送失败呈现投影（发送失败机制包·语义 5，
    /// 单一数据源）：发送链的失败呈现只许走本口，
    /// 投影规则只认成因 kind——全局状况（kind.
    /// presentsGlobally：凭据失效/服务不可用）进横
    /// 幅（无重发钮、无单条指向）；单条失败不进横
    /// 幅：行内叹号（状态投影）＋一条常驻小提示承
    /// 载文案（单槽换代、不叠字）。旧形态是调用点
    /// 各自直写 errorMessage＋横幅单槽指向最近失败
    /// 条（B6：连环失败时重发钮指错条），呈现与成
    /// 因两本账
    private func presentSendFailure(
        kind: SendFailureKind,
        message: String? = nil,
        detail: String? = nil
    ) {
        let copy = message ?? SendFailureCopy.message(kind: kind)
        if kind.presentsGlobally {
            if errorMessage == copy, errorDetail == detail {
                return
            }
            errorMessage = copy
            errorDetail = detail
            errorOccurredAt = Date()
            errorDetailExpanded = false
        } else {
            showNotice(copy, tier: .persistent)
        }
    }

    /// 错误横幅（发送失败机制包·语义 5 后形态）：
    /// 只投影全局状况——无「重新发送」动作位（单
    /// 条失败的恢复只在条目行内，旧横幅重发钮指向
    /// 最近失败条、连环失败时指错条，B6 退役）
    private func errorBanner(
        _ message: String
    ) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.danger)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                    // G-03 恢复三件之时间戳（§389）：本
                    // 条错误的发生时刻小字在位，只报时
                    // 刻不报技术细节
                    if let errorOccurredAt {
                        Text(errorOccurredAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer()
                // G-03 恢复三件之详情（§389）：技术原
                // 文（状态码/接口名/错误码）只许在展
                // 开区出现，主文案永不带；无详情的错
                // 误不显此钮
                if errorDetail != nil {
                    Button {
                        errorDetailExpanded.toggle()
                    } label: {
                        Text("详情")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.primary)
                            .frame(
                                minHeight: OneDayMetrics.minTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                    .accessibilityLabel("错误详情")
                }
                Button {
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.inkSecondary)
                        // 0.23.0（命中域审计）：字形不变、命
                        // 中域外扩 44（条高随之由内容撑至 44）
                        .frame(
                            width: OneDayMetrics.minTapTarget,
                            height: OneDayMetrics.minTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("关闭")
                .buttonStyle(.odPressable)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.vertical, OneDayMetrics.spacingS)
            if errorDetailExpanded, let errorDetail {
                Text(errorDetail)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.bottom, OneDayMetrics.spacingS)
            }
        }
        .background(Palette.pageBG)
    }

    /// 账本忙碌提示的 runID 分型（§414 增补，断网
    /// 规格 5.1 连带修正）：账本在席但 run 从未确
    /// 立（runID == nil）时不许说「还在生成中」——
    /// 那条根本没发出去；五处守卫提示（编辑已发
    /// 送/重新生成/失败重发/待发重发/编辑未发送）
    /// 共用本口，不许各写一份
    private func ledgerBusyNotice(threadID: UUID) -> String {
        if let entry = appState.runLedger.entry(
            forThreadID: threadID
        ), entry.runID == nil {
            return "上一条还没发出去，正在确认结果，确认完就能继续发送。"
        }
        return "上一条还在生成中，正在确认结果，确认完就能继续发送。"
    }

    /// 提示条赋值唯一口（§140 提示纪律第 3 条）：带档
    /// 位赋值即起自清计时（中性 5s／重要 8s，档位秒
    /// 数在 Core ChatNoticeTier）；常驻档（失败类，
    /// OB-I3/§391）不起计时、只许手关。换代先取消旧
    /// 计时，自清只清自己那一代（Core expire 代号判
    /// 定），手关后旧计时到期不复活。计时模式沿听写
    /// 提示行先例（DictationController.showNotice）
    private func showNotice(
        _ text: String, tier: ChatNoticeTier = .brief
    ) {
        let item = ChatNotice(text: text, tier: tier)
        noticePresentation.present(item)
        noticeDismissTask?.cancel()
        noticeDismissTask = nil
        if let seconds = item.tier.autoDismissSeconds {
            noticeDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                noticePresentation.expire(id: item.id)
            }
        }
    }

    /// 提示条关闭唯一口（✕／发送起手）：即清并废掉
    /// 在途计时，防自清把已关条的后续状态搅乱
    private func dismissNotice() {
        noticeDismissTask?.cancel()
        noticeDismissTask = nil
        noticePresentation.dismiss()
    }

    private func noticeBar(_ message: String) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                Button {
                    dismissNotice()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.inkSecondary)
                        // 0.23.0（命中域审计）：字形不变、命
                        // 中域外扩 44（条高随之由内容撑至 44）
                        .frame(
                            width: OneDayMetrics.minTapTarget,
                            height: OneDayMetrics.minTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("关闭")
                .buttonStyle(.odPressable)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.vertical, OneDayMetrics.spacingS)
        }
        .background(Palette.pageBG)
    }

    // MARK: - 输入区（0.2.2 定版：＋键与发送键同径 36pt 圆形；
    // 0.2.5 去嵌套与右端状态机，见 trailingControl）

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    /// 发送舱（0.2.4 定形，DESIGN-V4 §8；承载沿革见 §10/§11）：
    /// 一颗完整的系统玻璃胶囊——＋键裸符号坐在胶囊内左、右端
    /// 状态机在胶囊内右；附件条在胶囊上方、实色小件，不入玻璃。
    /// 对位规格（0.2.8 改基数，§12.3）：正文行高实测 20.37
    /// （0.2.9 校准，§13.2）＋文本纵向边距 10＝文本侧约 30，
    /// 与 30pt 两键在 HStack(.bottom) 里同高（中心重合）；
    /// 多行时两键底边与 field 底边齐平，锚在最后一行。胶囊
    /// 单行总高＝30＋行纵向边距 16＝46.37（算术归 Composer-
    /// Layout 单一口径）。
    /// 0.2.7 高度权威换代（§11）：纵向 TextField 换自量高
    /// UITextView（ComposerTextView），高度只由文本布局决定；
    /// 玻璃改裸 glassEffect 施加在行本体（容器/union 撤销）。
    /// 形状（0.3.5 改定，§20）：圆角半径＝胶囊实测高
    /// 的连续函数（单行与 Capsule 几何等价、多行封顶
    /// composerCorner）；旧「单行 Capsule／多行固定圆
    /// 角矩形」的离散两态已废——它滞后布局一拍出重影。
    private var composerShape: AnyShape {
        AnyShape(RoundedRectangle(
            cornerRadius: ComposerLayout.cornerRadius(
                forCapsuleHeight: composerCapsuleHeight,
                cap: OneDayMetrics.composerCorner
            ),
            style: .continuous
        ))
    }

    /// 语音失败行（0.36.6）：左警示图标＋三段式文案
    /// ＋右端 ✕；权限类多一个「去设置」文字动作
    private func dictationFailureBar(
        _ failure: DictationFailure
    ) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(Palette.warning)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(dictationFailureMessage(failure))
                    .font(.caption)
                    .foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
            if failure == .permissionDenied {
                Button("去设置") {
                    if let url = URL(
                        string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.primary)
                .buttonStyle(.odPressable)
            }
            Button {
                dictation.clearFailure()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 24, height: 24)
                    // 第 83 条（命中域收口）：视觉 24 不变、
                    // 命中域外扩 44（与同文件回告卡 ✕ 同款
                    // 两层帧）；负内边距抵消外扩、失败条的
                    // 行高布局不动
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
                    .padding(-(OneDayMetrics.minTapTarget - 24) / 2)
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(
            Palette.fieldFill,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
        )
    }

    /// 语音到限提示行（0.36.6）：非失败类告知（已自
    /// 动落稿保内容），控制器 5 秒后自清
    private func dictationNoticeBar(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, 1)
            Text(notice)
                .font(.caption)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(
            Palette.fieldFill,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
        )
    }

    /// 引用块（0.4.1 立制、0.36.19 入舱改形，§84）：输
    /// 入舱卡内的上段——左细线＋两行（正在回复 X／摘
    /// 要一行截断）＋右上 ✕ 取消，下接发丝分隔线与输
    /// 入行（见 composerCard）。0.4.1–0.36.18 它是输入
    /// 舱外一张带 fieldFill 底垫的独立浮卡；入舱后底
    /// 垫撤销（卡面即玻璃，不卡上叠卡），✕ 自右中改
    /// 右上贴首行。发送后由 send() 清除、点 ✕ 即时清
    /// 除、切换线程经 onChange 清除（见 body）
    private func quoteBar(_ quote: MessageQuote) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Rectangle()
                .fill(Palette.inkMuted)
                .frame(width: 2, height: 30)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                // 0.7.0（M4）：分流种子的引用条改报去向——
                // 这条引用不在原线程回复、是新旁聊的开场
                Text(pendingQuoteIsFork
                    ? "在旁聊里接着问 \(MessageQuote.speakerName(for: quote.role, assistantName: appState.agentDisplayName))"
                    : (quote.role == "user"
                        ? "正在回复我的消息"
                        : "正在回复 \(MessageQuote.speakerName(for: quote.role, assistantName: appState.agentDisplayName))"))
                    // 0.4.1 第 9 修：引用条标签同守
                    // regular 基准（旧 caption semibold
                    // 撤销，与消息正文同一字重纪律）
                    .font(.caption)
                    .foregroundStyle(Palette.ink)
                Text(quote.summary())
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                pendingQuote = nil
                pendingQuoteIsFork = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 28, height: 28)
                    // 0.23.0（审计 C3）：视觉 28 不变、命
                    // 中域外扩 44（两层帧，CopyButton 同款）
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("取消引用")
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    /// 发送舱的动态引用条（§208）：与 quoteBar 同
    /// 槽位同几何（左轨＋两行＋右上 ✕，视觉 28、命
    /// 中域 44），内容换帖面：首行＝行首标识＋帖标
    /// 题（一行截断，不挂「正在回复」式标签行——帖
    /// 不是某人的消息）、次行＝来源行＋正文摘要一
    /// 行；有图帖右端带小缩略图（feed 变体与消息
    /// 引用条唯一的形态差，图加载失败整块不显、不
    /// 占位）。点 ✕ 即清、无任何落盘
    private func feedQuoteBar(_ quote: FeedPostQuote) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Rectangle()
                .fill(Palette.inkMuted)
                .frame(width: 2, height: 30)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(quote.mark.isEmpty
                    ? quote.title
                    : "\(quote.mark) \(quote.title)")
                    .font(.caption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(feedQuoteSecondLine(quote))
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let imageURL = quote.imageURL,
               let url = URL(string: imageURL) {
                // §418：取图换 Nuke LazyImage（统一管
                // 线）；失败整块不显、不占位的旧口径由
                // success-only 闭包等价实现；.id(url) 保
                // 引用切换时换图（LazyImage 不随请求自变）
                LazyImage(
                    request: RemoteImageRequestFactory
                        .publicRequest(
                            url: url, longEdgeCap: 160)
                ) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(
                                cornerRadius: OneDayMetrics.codeCorner
                            ))
                    }
                }
                .pipeline(OneDayImagePipelines.remote)
                .id(url)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            }
            Button {
                pendingFeedQuote = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 28, height: 28)
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("取消引用")
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    /// 动态引用条次行（§208）：来源行＋正文摘要以
    /// 「·」相连，任一为空只显另一个（来源缺失不编
    /// 造、正文为空只报来源）
    private func feedQuoteSecondLine(_ quote: FeedPostQuote) -> String {
        let summary = quote.summary()
        guard !quote.sourceLine.isEmpty else { return summary }
        guard !summary.isEmpty else { return quote.sourceLine }
        return "\(quote.sourceLine) · \(summary)"
    }

    /// 发送舱的来源引用条分发（§219；§238 增目标
    /// 族）：点子／文件／目标三族共用本槽位，按族渲
    /// 染各自条形态（几何同源：左轨＋两行＋右上
    /// ✕）。feed 族沿既有 feedQuoteBar 在上一分支
    /// 渲染，本分发只在其余三族在场时被走到（.feed
    /// 分支为枚举完备性保留、同渲染）
    @ViewBuilder
    private func sourceQuoteBar(
        _ quote: SourceQuote
    ) -> some View {
        switch quote {
        case .feed(let feedQuote):
            feedQuoteBar(feedQuote)
        case .idea(let ideaQuote):
            ideaQuoteBar(ideaQuote)
        case .file(let fileQuote):
            fileQuoteBar(fileQuote)
        case .goal(let goalQuote):
            goalQuoteBar(goalQuote)
        }
    }

    /// 发送舱的点子引用条（§219）：与 feedQuoteBar
    /// 同槽位同几何（左轨＋两行＋右上 ✕，视觉 28、
    /// 命中域 44），内容换点子面：首行＝行首标识＋
    /// 点子标题（一行截断）、次行＝载荷摘要一行
    /// （载荷为空即空行、与 feed 条次行同口径，不
    /// 编占位文）。点 ✕ 即清、无任何落盘
    private func ideaQuoteBar(_ quote: IdeaQuote) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Rectangle()
                .fill(Palette.inkMuted)
                .frame(width: 2, height: 30)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(quote.mark.isEmpty
                    ? quote.title
                    : "\(quote.mark) \(quote.title)")
                    .font(.caption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(quote.summary())
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                pendingSourceQuote = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 28, height: 28)
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("取消引用")
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    /// 发送舱的文件引用条（§219）：同槽位同几何，
    /// 内容换文件面：首行＝文件名（一行截断）、次
    /// 行＝服务端原路径摘要一行。点 ✕ 即清、无任
    /// 何落盘
    private func fileQuoteBar(_ quote: FileQuote) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Rectangle()
                .fill(Palette.inkMuted)
                .frame(width: 2, height: 30)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(quote.name)
                    .font(.caption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(quote.summary())
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                pendingSourceQuote = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 28, height: 28)
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("取消引用")
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    /// 发送舱的目标创建引用条（§238）：同槽位同几
    /// 何，内容换目标面：首行＝「新建目标：类名」、
    /// 次行＝介绍首句摘要一行。点 ✕ 即清、无任何
    /// 落盘
    private func goalQuoteBar(_ quote: GoalQuote) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Rectangle()
                .fill(Palette.inkMuted)
                .frame(width: 2, height: 30)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(quote.title)
                    .font(.caption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(quote.summary())
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                pendingSourceQuote = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 28, height: 28)
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("取消引用")
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    /// 发送舱内容（0.3.3 上文下钮，DESIGN-V4 §18）：自研
    /// Layout 排三件子视图（＋键／文本／右端状态机）——
    /// 单行形态与旧 HStack 几何逐项等价（总高 46、两键
    /// 夹文字、全部底对齐，0.2.8 定版尺寸不动）；多行形
    /// 态文字区全宽在上随行生长、按钮行钉在胶囊底部行
    /// （学 Muse/ChatGPT 本体与 Exyte/Stream Composer
    /// 的成熟结构）。形态判据恒以窄宽量测为准、只活在
    /// Layout 内部决定子视图落位，不外泄为视图状态；
    /// 玻璃形状不读形态、只读实测高的连续半径（0.3.5，
    /// §20）；Layout 保持子视图身份，形态切换不重建
    /// UITextView、焦点不丢。高度全走
    /// ComposerLayout.capsuleHeight(narrow:full:) 纯函数
    /// 发送舱行总装（0.36.6 分流）：录音态（准备中/
    /// 录音中/收尾）由 DictationBar 占住同一玻璃胶囊
    /// （0.36.17 起只剩控制行，录时零文字），其余时候
    /// 是标准三件行；玻璃与实测高回写挂在卡层，两态
    /// 共用（见 composerCard 的 glassEffect 施加点）
    private var composerRow: some View {
        Group {
            if dictation.isActive {
                // 0.36.17 改判：录音条只剩控制行（废弃
                // ／音波＋计时／停／发送），不再带文本
                // 视图——文本只在落稿时经 onTextChange
                // 一次性回写 input
                DictationBar(
                    controller: dictation,
                    reduceMotion: reduceMotion
                )
            } else {
                standardComposerRow
            }
        }
        // 实测高回写已上移到 composerCard 卡层（0.36.19，
        // §84：整卡实测、引用块计入舱高）
    }

    private var standardComposerRow: some View {
        ComposerBarLayout(
            contentSizeCategory: dynamicTypeSize.contentSizeCategory
        ) {
            attachButton
            // 0.2.7：SwiftUI 纵向 TextField 换自量高
            // UITextView（ComposerTextView）——高度由
            // 文本布局单方决定（§11）；0.3.3 起视图由
            // ComposerTextMetrics.makeTextView 工厂以显
            // 式 TextKit-1 栈构造（与量测同源，治光标
            // 逃逸/换行不对齐，见该文件几何节）；占位符
            // 由文本视图内部的子标签承担
            ComposerTextView(
                text: $input,
                focusHandle: composerFocusHandle,
                onFocusChange: { focused in
                    composerFocused = focused
                },
                // caret 跟主题走（§19 变表）：强调色令牌
                caretColor: UIColor(Palette.primary)
            )
            trailingControl
        }
        .fixedSize(horizontal: false, vertical: true)
        // 实测高回写已上移到 composerRow 总装层（0.36.6
        // 两态共用）；0.2.6–0.3.4 的离散形状动画撤销史
        // 见 §20.1，不在此复述
    }

/// 发送舱布局（0.3.3 上文下钮）：子视图序固定为
/// [＋键, 文本, 右端状态机]。几何全读 ComposerLayout
/// 常数（行边距 8、字段边距 8/5、键 30），与
/// horizontalChrome 的扣减表逐项同源：
/// - 单行（总高 46，与旧 HStack(.bottom) 逐项等价）：
///   ＋键 x=行左+8、底对齐；文本 x=行左+54、宽=行宽
///   −108（≡容器宽−132 的窄宽）、底距 13（行边距 8＋
///   字段纵距 5）；右键右贴、底对齐
/// - 多行：文本 x=行左+16、宽=行宽−32（≡容器宽−56
///   的全宽）、顶距 13；按钮行钉底（y=总高−8−30）；
///   文本底与按钮行顶之间 9（字段纵距 5＋行距 4），
///   总高与 capsuleHeight 的分解逐项对上
/// 形态判据恒以窄宽量测走 isMultiline、总高走
/// capsuleHeight(narrow:full:)；形态只活在布局内部
/// （0.3.5 起不再回写任何视图状态，§20.1）；Layout 保
/// 持子视图身份，切换不重建 UITextView、焦点不丢
private struct ComposerBarLayout: Layout {
    // 0.3.5（§20.1）：形态回写通道（onModeChange＋
    // Cache＋主队列异步派发）整条撤销——异步回写滞后
    // 布局一拍，是回车重影的合谋者

    /// 当前字号档（0.43.0，A11Y-D1）：由 ChatView 从
    /// 环境注入——Layout 协议无环境直读口，档位经
    /// 本属性显式贯穿量测链，与文本视图 trait 档同
    /// 源；档位变更即值变更、布局自然重算
    var contentSizeCategory: UIContentSizeCategory = .large

    /// 量测：文本子视图在窄宽/全宽各 sizeThatFits 一次
    /// （ComposerTextView 的 sizeThatFits 以提议宽返回封
    /// 顶后的纯文本高，与 ComposerLayout 口径同源）
    private func metrics(
        rowWidth: CGFloat, subviews: Subviews
    ) -> (multiline: Bool, totalHeight: CGFloat) {
        let containerWidth = rowWidth + ComposerLayout.inputBarChrome
        let narrowTextH = subviews[1].sizeThatFits(
            ProposedViewSize(
                width: ComposerLayout.textWidth(
                    forContainerWidth: containerWidth
                ),
                height: nil
            )
        ).height
        let fullTextH = subviews[1].sizeThatFits(
            ProposedViewSize(
                width: ComposerLayout.textWidth(
                    forContainerWidth: containerWidth, multiline: true
                ),
                height: nil
            )
        ).height
        return (
            multiline: ComposerLayout.isMultiline(
                measured: narrowTextH, category: contentSizeCategory
            ),
            totalHeight: ComposerLayout.capsuleHeight(
                narrowMeasured: narrowTextH, fullMeasured: fullTextH,
                category: contentSizeCategory
            )
        )
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let rowWidth = proposal.width ?? 0
        let m = metrics(rowWidth: rowWidth, subviews: subviews)
        return CGSize(width: rowWidth, height: m.totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let containerWidth = bounds.width + ComposerLayout.inputBarChrome
        let m = metrics(rowWidth: bounds.width, subviews: subviews)
        let pad: CGFloat = 8
        let btn = ComposerLayout.buttonHeight
        let textInset = pad + ComposerLayout.textVerticalInsets / 2 // 13
        if m.multiline {
            let fullWidth = ComposerLayout.textWidth(
                forContainerWidth: containerWidth, multiline: true
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + pad + 8, y: bounds.minY + textInset),
                proposal: ProposedViewSize(width: fullWidth, height: nil)
            )
            let rowY = bounds.maxY - pad - btn
            subviews[0].place(
                at: CGPoint(x: bounds.minX + pad, y: rowY),
                proposal: ProposedViewSize(width: btn, height: btn)
            )
            subviews[2].place(
                at: CGPoint(x: bounds.maxX - pad - btn, y: rowY),
                proposal: ProposedViewSize(width: btn, height: btn)
            )
        } else {
            let narrowWidth = ComposerLayout.textWidth(
                forContainerWidth: containerWidth
            )
            let textProposal = ProposedViewSize(
                width: narrowWidth, height: nil
            )
            let textSize = subviews[1].sizeThatFits(textProposal)
            subviews[1].place(
                at: CGPoint(
                    x: bounds.minX + pad + btn + pad + 8,
                    y: bounds.maxY - textInset - textSize.height
                ),
                proposal: textProposal
            )
            subviews[0].place(
                at: CGPoint(
                    x: bounds.minX + pad, y: bounds.maxY - pad - btn
                ),
                proposal: ProposedViewSize(width: btn, height: btn)
            )
            subviews[2].place(
                at: CGPoint(
                    x: bounds.maxX - pad - btn, y: bounds.maxY - pad - btn
                ),
                proposal: ProposedViewSize(width: btn, height: btn)
            )
        }
    }
}

    /// 发送舱右端状态机（0.2.5，对照 Muse 输入区）：胶囊内
    /// 的元素都是裸符号或单一小圆盘，不套圈不描边。
    /// §446（用户 2026-11-24 亲裁）单槽位按内容切换：
    /// - 有可发送内容（文字或附件）：发送箭头（流式中
    ///   点按走 §419 排队落位）
    /// - 流式中且空输入：停止键（0.31.0 起走
    ///   requestRunStop 真取消）
    /// - 空输入：裸麦克风符号占位（无圆盘底、无描边）
    private var trailingState: ComposerTrailingState {
        ComposerTrailingState.resolve(
            isStreaming: isStreaming, canSend: canSend
        )
    }

    private var trailingControl: some View {
        ZStack {
            if trailingState.isDiscKey {
                sendStopButton
                    .transition(.opacity)
            } else {
                micButton
                    .transition(.opacity)
            }
        }
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: trailingState
        )
    }

    /// 发送↔停止变形键（0.3.0 动效包，animated-icons 技
    /// 能规则 1 的原生等价——白名单位置）：两态在同一按
    /// 钮内以 SF Symbol replace 过渡形变切换，不再是两
    /// 个按钮硬切；系统「减少动态效果」开启时符号过渡
    /// 自动降级。圆盘与字号口径沿旧两键（直径
    /// ComposerLayout.buttonHeight、停止 12/发送 13）
    private var sendStopButton: some View {
        // §446：圆盘键语义由 trailingState 裁决，
        // 不再直读 isStreaming——.stop 态出停止；
        // .send 态出发送（流式中有字时点按走 §419
        // 排队落位）；符号形变仍在本键内走
        // symbolEffect（0.3.0 口径不变）
        let isStopDisc = trailingState == .stop
        return Button {
            if isStopDisc {
                // 0.31.0：停止＝runs 真取消（requestRun-
                // Stop 发服务端 stop），不再是旧通道的
                // 本地断流假取消
                requestRunStop()
            } else {
                send()
            }
        } label: {
            Image(systemName: isStopDisc ? "stop.fill" : "arrow.up")
                .font(.system(size: isStopDisc ? 12 : 13, weight: .bold))
                // 0.6.1：发送钮改 OpenMuse 原貌——浅蓝圆
                // primaryPale＋深墨箭头 onPrimary（chat.tsx:
                // 985/996），取代旧深蓝圆＋白箭头
                .foregroundStyle(Palette.onPrimary)
                .frame(
                    width: ComposerLayout.buttonHeight,
                    height: ComposerLayout.buttonHeight
                )
                .background(Palette.primaryPale, in: Circle())
                .contentTransition(.symbolEffect(.replace))
                // 第 83 条（命中域收口）：视觉盘 30 不变、
                // 命中域外扩 44（与顶栏圆钮同口径）；负内
                // 边距抵消外扩、布局仍按 30 走（Composer-
                // BarLayout 的量测口径不动）
                .frame(
                    width: OneDayMetrics.minTapTarget,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
                .padding(
                    -(OneDayMetrics.minTapTarget
                        - ComposerLayout.buttonHeight) / 2
                )
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(isStopDisc ? "停止生成" : "发送")
    }

    /// （旧发送/停止两键已合并为 sendStopButton 变形键，见上。）

    /// 语音输入入口（0.2.5 占位 → 0.36.6 接入，§71）：
    /// 裸麦克风符号——无圆盘底、无描边，与 Muse 空输
    /// 入态的右端形态一致（形态自 0.2.5 未动）。点按
    /// 先收键盘、再交语音控制器走权限门/开录（点按切
    /// 换、非按住；录音中本键被录音条取代不再出现）
    private var micButton: some View {
        Button {
            composerFocusHandle.dismiss()
            // H2-a：开始听写即停朗读（施工图 3.3——
            // 录音与出声共用音频会话，先停后录）
            SpeechPlayer.shared.stop()
            dictation.handleMicTap(baseDraft: input)
        } label: {
            Image(systemName: "mic")
                // 0.3.8 第 32 条：字形 16→15（笔画约 2.5→
                // 1.8pt 目标），数值走 FrameworkIcon 令牌
                .font(.system(
                    size: FrameworkIcon.composerGlyphSize,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
                .frame(
                    width: ComposerLayout.buttonHeight,
                    height: ComposerLayout.buttonHeight
                )
                // 第 83 条（命中域收口）：字形不变、命中
                // 域外扩 44（外层矩形取代旧 30 圆命中形）；
                // 负内边距抵消外扩、布局仍按 30 走
                .frame(
                    width: OneDayMetrics.minTapTarget,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
                .padding(
                    -(OneDayMetrics.minTapTarget
                        - ComposerLayout.buttonHeight) / 2
                )
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("语音输入")
    }

    private var attachButton: some View {
        // §147 改版：点「+」开底部附件面板 sheet（资
        // 源库照片条＋添加文件/视频动作行，见 Attach-
        // mentPanelView；§152 修订照片条多选＋定高贴
        // 内容）；旧浮窗小卡 Menu（三行：拍
        // 照/相册选图/选文件）整套退役——三条路全部
        // 由面板承接（相机格/查看全部选图器/添加文件
        // 行走 DocumentPickerView，§317 状态旗呈现）
        Button {
            showAttachPanel = true
        } label: {
            // 0.2.5：裸符号——撤掉 0.2.4 的玻璃圆外圈与 union
            // 融合（胶囊玻璃里再套一圈圆是嵌套毛病）；＋号
            // 直接坐在发送舱胶囊的玻璃里，与 Muse 一致
            Image(systemName: "plus")
                // 0.3.8 第 32 条：与麦克风同档 15（笔画目标
                // 约 1.8pt），FrameworkIcon.composerGlyphSize
                .font(.system(
                    size: FrameworkIcon.composerGlyphSize,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
                .frame(
                    width: ComposerLayout.buttonHeight,
                    height: ComposerLayout.buttonHeight
                )
                // 第 83 条（命中域收口）：字形不变、命中
                // 域外扩 44（外层矩形取代旧 30 圆命中形）；
                // 负内边距抵消外扩、布局仍按 30 走
                .frame(
                    width: OneDayMetrics.minTapTarget,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
                .padding(
                    -(OneDayMetrics.minTapTarget
                        - ComposerLayout.buttonHeight) / 2
                )
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("添加附件")
    }

    /// §147→§317：附件面板内动作的统一收尾——登记
    /// 动作并收面板，动作由 sheet 的 onDismiss 在收
    /// 起动画真完成后执行（呈现点见 chatSurface 的
    /// sheet 注）。旧形态（§147）写死睡 450ms 猜收
    /// 起完成：iOS 26 sheet 收起时长非常量，睡醒时
    /// 收起未完、对 dismissing 中的 VC 调 present
    /// 被 UIKit 静默丢弃——「添加文件」面板收了选
    /// 择器永不来（诊断 attach-noresponse-diagno-
    /// sis-20261117 定案，病自 0.36.31 换桥即在）。
    /// 相机/选图两行同走本口：其 SwiftUI 状态旗原靠
    /// 框架排队呈现，改由完成信号驱动时序更确凿、
    /// 行为不变
    private func afterAttachPanelDismiss(
        _ action: @escaping () -> Void
    ) {
        attachPanelPendingAction = action
        showAttachPanel = false
    }

    /// 待发附件条：图片出缩略图、文件出名牌，都可单独
    /// 移除。0.36.31（件一，P-13 第六轮结构换代）：
    /// 本体自 ScrollView＋HStack 换为 Attachment-
    /// FlowLayout 筹码流式行（OpenMuse 式）——左
    /// 起逐个排、放不下换行、不滚动。五轮补丁（条
    /// 内 frame／调用点 claim／移出量测层／包装栈
    /// frame／包装栈 alignment）全灭于 ScrollView
    /// 的量测与对齐纠缠，本轮整类退役该结构：Lay-
    /// out 协议下筹码按理想尺寸自定位、左缘即条左
    /// 缘，无滚动轴、无内容宽收缩、无栈对齐可乘之
    /// 机。横向内边距 spacingSM（与卡内引用块/分
    /// 隔线同一起点）、纵向 spacingXS 沿旧条口径
    private var attachmentsStrip: some View {
        AttachmentFlowLayout(
            horizontalSpacing: OneDayMetrics.spacingS,
            verticalSpacing: OneDayMetrics.spacingSM
        ) {
            ForEach(attachments) { attachment in
                attachmentChip(attachment)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    @ViewBuilder
    private func attachmentChip(_ attachment: PendingAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            switch attachment.kind {
            case .image(let data):
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(
                            RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
                        )
                }
            case .file(let name, let data):
                HStack(spacing: OneDayMetrics.spacingS) {
                    // §125：待发筹码图标与文件卡/打开页
                    // 同源（FileIconBox 类型表）——不再
                    // 一律通用 doc 字形
                    FileIconBox(name: name, size: 36)
                    // 0.46.1 扩围 D：待发牌补大小（此前
                    // 只有名＋可删、大小缺位）——名主行、
                    // 大小副行，与文件页 ByteCountFormatter
                    // .file 同制
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .frame(
                                maxWidth: 140, alignment: .leading
                            )
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount: Int64(data.count),
                                countStyle: .file
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                // 0.43.0（A11Y-D3）：定高改最小高——默认
                // 档内容高 54 不变，大字档下文件名行随
                // 字号长高、不被 54 硬顶截断（本包唯一
                // 固定高改动，视觉数值变更清单已记）
                .frame(minHeight: 54)
                .background(
                    Palette.surface,
                    in: RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
                )
                // 0.4.0（§1.1 Elevation 整表废止）：附件牌
                // 的手搓阴影随表退役，系统层级自理
            }
            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.inkMuted, Palette.surface)
                    // 0.23.0（命中域审计）：命中域外扩 44；
                    // offset 补偿 13.5 使字形中心与旧 17 帧
                    // 时同位（视觉零位移、只扩命中）
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .offset(x: 18.5, y: -18.5)
            .accessibilityLabel("移除附件")
        }
    }

    /// 附件筹码流式布局（0.36.31 件一）：左到右逐个
    /// 排筹码、一行放不下换行，行高取该行最高筹码。
    /// 排布算法与 StreamingText 的 TokenFlow 同构
    /// （sizeThatFits 与 placeSubviews 共用一份
    /// arrange，尺寸与落位不打架）；与 TokenFlow 的
    /// 差别只在间距双值（横向/行距分开）与宽度口径
    /// （认父级提议满宽——条在包装栈 .leading 下本
    /// 就满宽，左起由排布本身保证，不靠任何对齐修
    /// 饰）。筹码一律按理想尺寸落位（图片 54×54、
    /// 文件名牌自然宽），落位提议 .unspecified 与
    /// 旧 HStack 口径一致
    private struct AttachmentFlowLayout: Layout {
        /// 筹码横向间距（与旧 HStack spacing 同值）
        var horizontalSpacing: CGFloat = OneDayMetrics.spacingS
        /// 换行后的行距
        var verticalSpacing: CGFloat = OneDayMetrics.spacingSM

        private func arrange(
            subviews: Subviews, width: CGFloat
        ) -> (size: CGSize, origins: [CGPoint]) {
            var origins: [CGPoint] = []
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxX: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x > 0, x + size.width > width {
                    x = 0
                    y += lineHeight + verticalSpacing
                    lineHeight = 0
                }
                origins.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width
                maxX = max(maxX, x)
                x += horizontalSpacing
            }
            return (
                CGSize(width: maxX, height: y + lineHeight), origins
            )
        }

        func sizeThatFits(
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) -> CGSize {
            let arranged = arrange(
                subviews: subviews,
                width: proposal.width ?? .greatestFiniteMagnitude
            )
            // 宽度认父级提议（满宽）；提议未定宽时回
            // 落内容宽（全部筹码单行排开的自然宽）
            return CGSize(
                width: proposal.width ?? arranged.size.width,
                height: arranged.size.height
            )
        }

        func placeSubviews(
            in bounds: CGRect,
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) {
            let result = arrange(subviews: subviews, width: bounds.width)
            for (index, subview) in subviews.enumerated() {
                let origin = result.origins[index]
                subview.place(
                    at: CGPoint(
                        x: bounds.minX + origin.x,
                        y: bounds.minY + origin.y
                    ),
                    proposal: .unspecified
                )
            }
        }
    }

    // MARK: - 附件接入

    /// 图片统一转 JPEG 再入列：data URL 的 mime 恒为
    /// image/jpeg，多模态编码不说谎
    private func appendImage(_ rawData: Data) {
        if let image = UIImage(data: rawData), let jpeg = image.jpegData(compressionQuality: 0.85) {
            attachments.append(PendingAttachment(kind: .image(jpeg)))
        } else {
            attachments.append(PendingAttachment(kind: .image(rawData)))
        }
    }

    /// 多选批量加载（0.36.23）：按用户点选顺序逐个
    /// 载入并 append，顺序不乱序；单张超 20MB 只报
    /// 不收、不影响其余，超限张数汇总一条 notice
    /// 明示（图片闸独立于文件路：图片走多模态 parts
    /// 内嵌发送、不经文件上传契约，0.36.31 文件闸
    /// 抬 100MB 不牵动本闸）
    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        var dataList: [Data?] = []
        for item in items {
            dataList.append(
                try? await item.loadTransferable(type: Data.self)
            )
        }
        ingestPhotoData(dataList)
    }

    /// 图片入条共用口（§152 收编）：选图器与附件面
    /// 板照片条两条取图路在此合流——同一大小闸
    /// （Core AttachmentPanel.photoFits）、同一汇总
    /// 口径（超限/失败各一条 notice、不静默吞，P-18）；
    /// §152 照片条改多选后整批一次汇入此处，口径不变
    private func ingestPhotoData(_ dataList: [Data?]) {
        var oversized = 0
        var failed = 0
        for data in dataList {
            guard let data else {
                failed += 1
                continue
            }
            guard AttachmentPanel.photoFits(byteCount: data.count) else {
                oversized += 1
                continue
            }
            appendImage(data)
        }
        let notices = [
            AttachmentPanel.oversizedPhotosNotice(count: oversized),
            AttachmentPanel.failedPhotosNotice(count: failed),
        ].compactMap { $0 }
        if !notices.isEmpty {
            showNotice(notices.joined(), tier: .persistent)
        }
    }

    /// 附件面板照片取数（§147 立、§152 改多选批
    /// 量）：逐张按资产 id 取原图数据（允许 iCloud
    /// 下载），整批数据一次汇入共用口 ingestPhoto-
    /// Data——与选图器同闸同汇总口径（20MB 闸/超限
    /// 与失败各一条汇总 notice、不静默吞，P-18），
    /// 批量不另开一套
    private func loadStripPhotos(assetIDs: [String]) async {
        var dataList: [Data?] = []
        for assetID in assetIDs {
            dataList.append(await loadStripPhotoData(assetID: assetID))
        }
        ingestPhotoData(dataList)
    }

    /// 单张取数本体（§147 原 loadStripPhoto 的取数
    /// 段）：资产已删/取不到回 nil，计数与出声归批
    /// 量汇入口，不在此自报
    private func loadStripPhotoData(assetID: String) async -> Data? {
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetID], options: nil
        )
        guard let asset = result.firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: options
            ) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// 选视频入条（§152）：视频是文件不是图片 part
    /// ——以文件形态入条（名由 Core 拼装、大小走
    /// FileIntake 同闸、被拒点名汇总），后续上传与
    /// 发送拼装与普通文件完全同路
    private func loadPickedVideos(_ items: [PhotosPickerItem]) async {
        var oversized: [String] = []
        var unreadable: [String] = []
        for item in items {
            let name = AttachmentPanel.videoFileName(
                preferredExtension: item.supportedContentTypes
                    .first?.preferredFilenameExtension
            )
            guard let data = try? await item.loadTransferable(
                type: Data.self
            ) else {
                unreadable.append(name)
                continue
            }
            guard !FileIntake.isOversized(byteCount: data.count) else {
                oversized.append(name)
                continue
            }
            attachments.append(
                PendingAttachment(kind: .file(name: name, data: data))
            )
        }
        if let notice = FileIntake.rejectionNotice(
            oversized: oversized, unreadable: unreadable
        ) {
            showNotice(notice, tier: .persistent)
        }
    }

    /// 选文件回调（§410 改异步）：读盘＋转码整段下主
    /// 线程——旧链在选择器回调里同步直读，点「确定」即
    /// 冻界面到读完为止；现后台读完再回主线入条与汇总
    /// 提示，名单/文案/入条顺序与旧链逐字一致
    private func loadPickedFiles(urls: [URL]) {
        guard !urls.isEmpty else {
            showNotice(
                "没有选到文件，未加入待发列表。", tier: .extended
            )
            return
        }
        Task {
            let outcome = await Self.loadPickedFilesDetached(
                urls: urls
            )
            for file in outcome.accepted {
                attachments.append(
                    PendingAttachment(
                        kind: .file(name: file.name, data: file.data)
                    )
                )
            }
            if !outcome.unreadable.isEmpty {
                ChatDiagTrace.record(
                    "选文件读取失败 \(outcome.unreadable.count) 个："
                        + outcome.unreadable.joined(separator: "、")
                )
            }
            let summaries = [
                FileIntake.rejectionNotice(
                    oversized: outcome.oversized,
                    unreadable: outcome.unreadable
                ),
                FileIntake.transcodeNotice(
                    transcoded: outcome.transcoded,
                    undecodable: outcome.undecodable
                ),
            ].compactMap { $0 }
            if !summaries.isEmpty {
                showNotice(summaries.joined(), tier: .persistent)
            }
        }
    }

    /// §410：选文件读盘段的离主线程入口（钉测与生产共
    /// 用）：独立任务里跑同步本体，主线只收汇总产物
    static func loadPickedFilesDetached(
        urls: [URL]
    ) async -> PickedFilesLoadOutcome {
        await Task.detached(priority: .userInitiated) {
            Self.loadPickedFilesSync(urls: urls)
        }.value
    }

    /// 文件接入（0.36.31 件二＋件三重写）：入参自
    /// DocumentPickerView（asCopy 副本 URL，落在
    /// App 容器内——旧 .fileImporter 路的安全作用
    /// 域起停配对随之退役，本函数直读）。
    /// 逐个先查 fileSize 再读数据：超限不整份读入
    /// 内存（旧链先读 82.8MB 才判闸）；被拒文件
    /// （超限/读失败）由 Core FileIntake 汇总点名
    /// 一条 notice，不再逐个写、后写覆盖先写只剩
    /// 最后一个名。大小闸 20MB → 100MB 与服务端
    /// 托管上传契约对齐（file-upload-contract-
    /// 20261111：解码后上限 100MiB）。出口有声口
    /// 径（P-18）保留：空数组明示、读失败点名汇总
    /// 并落诊断面
    /// §410：本函数是同步本体，只在后台任务里跑
    /// （loadPickedFilesDetached），主线不直调
    /// §410 接管修：nonisolated——纯函数（读盘＋
    /// FileIntake＋组汇总产物），ChatView 的 actor
    /// 隔离会让独立任务里的调用无法过编译
    nonisolated static func loadPickedFilesSync(
        urls: [URL]
    ) -> PickedFilesLoadOutcome {
        var outcome = PickedFilesLoadOutcome()
        for url in urls {
            let name = url.lastPathComponent
            let declaredSize = (try? url.resourceValues(
                forKeys: [.fileSizeKey]
            ))?.fileSize
            if FileIntake.sizeVerdict(declaredSize: declaredSize)
                == .tooLarge {
                outcome.oversized.append(name)
                continue
            }
            guard let data = try? Data(contentsOf: url) else {
                outcome.unreadable.append(name)
                continue
            }
            // 编码归一（0.46.1 扩围 C）：文本类旧编码
            // （GBK 族）先转 UTF-8 再入条——网关按
            // UTF-8 硬读、原样上传会在服务端解码失败
            // 智能体读不到；转码后的字节才是上传载荷，
            // 手机上的原文件不动
            let upload = FileIntake.transcodedForUpload(
                fileName: name, data: data
            )
            // 大小查不到（.unknownSize）时以实读字节
            // 兜底二次判，同闸值；判的是转码后的最终
            // 载荷（GBK→UTF-8 中文每字 2B 变 3B 会变大）
            guard !FileIntake.isOversized(byteCount: upload.data.count)
            else {
                outcome.oversized.append(name)
                continue
            }
            // 转码账只记真入条的：被大小闸拒掉的文件
            // 不进转码提示名单，免得两份名单对不上
            switch upload.outcome {
            case .transcoded: outcome.transcoded.append(name)
            case .undecodable: outcome.undecodable.append(name)
            case .unchanged: break
            }
            outcome.accepted.append(
                PickedFilePayload(name: name, data: upload.data)
            )
        }
        return outcome
    }

    // （会话抽屉本体已于 0.4.5 迁至 DrawerView.swift、
    // 承载提到壳层 ContentView，见 DESIGN-V4 §30；
    // 本页只经 AppState 通道与抽屉互通）

    // MARK: - 发送

    /// 发送落点解析（0.27.0 硬化，与 currentThread
    /// 同口径）：命中用现线程；从未选过（current-
    /// ThreadID 为 nil）新建——正常首启路径；id 已
    /// 选但线程不存在＝定位失败，置可见错误并返
    /// nil，调用方整轮不发——不许再回落最近线程把
    /// 消息写进别人的对话
    private func ensureThread() -> ChatThread? {
        switch CurrentThreadResolution.ensureDecision(
            currentID: currentThreadID, existingIDs: threads.map(\.id)
        ) {
        case .useExisting:
            return currentThread
        case .createFresh:
            let thread = ChatThread()
            modelContext.insert(thread)
            currentThreadID = thread.id
            return thread
        case .mismatch:
            errorMessage = "当前会话定位失败：界面选中的会话在本地已不存在，本条未发送。请从抽屉重新打开会话。"
            return nil
        }
    }

    private func newThread() {
        let thread = ChatThread()
        modelContext.insert(thread)
        try? modelContext.save()
        currentThreadID = thread.id
    }

    // MARK: - 主线钦定（0.7.0，D1/M2）

    /// 主线钦定落位：解析走 Core MainThreadDesignation——
    /// 存量钦定且线程还在则沿用（并把服务端绑定对齐到
    /// 持久的钦定会话 id）；否则新建本地主线：标题恒
    /// 「主线」、写入钦定。服务端绑定只对齐已知的钦
    /// 定 id（§330：不在此铸造）。服务端承载的实际
    /// 存在性由 ensureMainLink 异步链接，本函数纯本地
    @discardableResult
    private func ensureMainThread() -> UUID? {
        let store = appState.sessionLedger
        switch MainThreadDesignation.resolve(
            storedID: store.mainThreadID, existingIDs: threads.map(\.id)
        ) {
        case .existing(let id):
            if let main = threads.first(where: { $0.id == id }) {
                // §330：绑定只对齐已知的钦定 id——本地
                // 无 id 时不在此铸造（认领是登录后第一
                // 动作）；对齐与迁账在认领/链接落定后
                // 由 ensureMainLink 同拍完成
                if let sessionID = store.mainServerSessionID,
                   main.serverSessionID != sessionID {
                    // §227：改绑前先迁账——旧绑定键下的
                    // 存量选择跟到钦定键下，不许留旧账发霉
                    appState.migrateSessionModelChoice(
                        fromServerSessionID: main.serverSessionID,
                        toServerSessionID: sessionID
                    )
                    main.serverSessionID = sessionID
                    try? modelContext.save()
                }
                if main.title != SideChatStore.mainTitle {
                    main.title = SideChatStore.mainTitle
                    try? modelContext.save()
                }
            }
            return id
        case .needsCreation:
            let thread = ChatThread()
            thread.title = SideChatStore.mainTitle
            // §330：绑定先取已知的钦定 id（可为 nil）；
            // 认领/冷启动落定后由 ensureMainLink 回写
            thread.serverSessionID = store.mainServerSessionID
            modelContext.insert(thread)
            try? modelContext.save()
            store.designateMainThread(thread.id)
            return thread.id
        }
    }

    /// 线程本地条目 → 种子快照（链接导入用）：只取
    /// user/assistant（过滤口径在 Core seedTranscript，
    /// 此处先把条目拍平成 Core 的 SeedEntry 形态，
    /// 时间戳带本地落盘时刻）
    private static func seedEntries(of thread: ChatThread) -> [SeedEntry] {
        // 聊天可靠性包：待发条目（服务端尚未受理）不
        // 进种子——种子是「服务端应有的历史」，待发
        // 消息只能由它自己的（重）发送轮作尾条投递，
        // 混进种子会绕过投递状态、在服务端落一份本
        // 地却仍标待发的双账
        thread.sortedEntries.filter { !$0.isPendingSend }.map {
            SeedEntry(
                role: $0.role, content: $0.content,
                timestamp: $0.createdAt.timeIntervalSince1970
            )
        }
    }

    /// 链接一轮的结局（§331）：最终会话 id（建会话
    /// 回执为准）＋种子记账两旗——seedLanded＝本轮
    /// import 已落（种子义务结清、且落的是仅文本转
    /// 录）；serverHeldHistory＝服务端先已持有历史
    /// （③路/收养持有人有消息，种子义务消解）。两
    /// 旗皆假且本地有种子＝种子转后台待导入。调用
    /// 方据此落线程 seedSyncState，不许再靠猜
    private struct LinkOutcome {
        let sessionID: String
        let seedLanded: Bool
        let serverHeldHistory: Bool
    }

    /// 链接一条线程到它的自有服务端会话（0.27.0，
    /// 主线/旁聊共用）：desiredID 为目标会话 id（主
    /// 线＝钦定 id、旁聊＝已存自有 id 或新铸）。流程
    /// 先 GET 查存，按服务端现状与种子有无分三路：
    /// ①不存在：无种子走网关建会话（Bearer）、有种
    ///   子走 import 一次落行＋全量消息（围栏修订 0）；
    /// ②存在但空行且本地有种子：import 补种（围栏
    ///   修订取 GET 回的 runtime_revision）；
    /// ③存在且已有消息：服务端已持历史，直接认链。
    /// 任一步失败抛错（不许静默、不许回退无头发送）
    /// adoptsOnTitleConflict（§220，主线专用）：建会话
    /// 撞 400 invalid_title 时按标题反查既有会话走收
    /// 养（判定走 Core MainlineAdoptionDirective）——
    /// 本地绑定脱钩（钦定 id 不存在＋标题被休眠旧会
    /// 话占着）不再是死路；旁聊调用恒 false，口径不变
    private func performLink(
        desiredID: String, title: String?, model: String?,
        seedEntries: [SeedEntry], adoptsOnTitleConflict: Bool = false
    ) async throws -> LinkOutcome {
        guard let apiKey = appState.apiKey else {
            throw HermesError.sessionExpired
        }
        let seed = SideChatLink.seedTranscript(from: seedEntries)
        let existing: ServerSession?
        do {
            existing = try await appState.performAdmin { client, config in
                try await client.serverSession(config: config, id: desiredID)
            }
        } catch let error as HermesError {
            if case .unexpectedStatus(_, let status) = error, status == 404 {
                existing = nil
            } else {
                throw error
            }
        }
        if let existing {
            let heldHistory = (existing.messageCount ?? 0) > 0
            if !heldHistory, !seed.isEmpty {
                try await importSeed(
                    id: desiredID, title: title, model: model,
                    seed: seed,
                    expectedRevision: existing.runtimeRevision ?? 0
                )
                return LinkOutcome(
                    sessionID: desiredID, seedLanded: true,
                    serverHeldHistory: false
                )
            }
            return LinkOutcome(
                sessionID: desiredID, seedLanded: false,
                serverHeldHistory: heldHistory
            )
        }
        do {
            if seed.isEmpty {
                if let model {
                    let created = try await appState.client
                        .createLinkedServerSession(
                            config: requireConfig(), apiKey: apiKey,
                            id: desiredID, model: model
                        )
                    return LinkOutcome(
                        sessionID: created.id, seedLanded: false,
                        serverHeldHistory: false
                    )
                }
                let created = try await appState.client.createServerSession(
                    config: requireConfig(), apiKey: apiKey,
                    id: desiredID, title: title
                )
                return LinkOutcome(
                    sessionID: created.id, seedLanded: false,
                    serverHeldHistory: false
                )
            }
            try await importSeed(
                id: desiredID, title: title, model: model,
                seed: seed, expectedRevision: 0
            )
            return LinkOutcome(
                sessionID: desiredID, seedLanded: true,
                serverHeldHistory: false
            )
        } catch {
            // §220 收养兜底：仅主线流程、仅 400 invalid_
            // title 触发；判定不成立（口径外错误/零匹配/
            // 名单拉不到）一律把原错误照抛，不许收养掩
            // 盖真故障、更不许静默
            guard adoptsOnTitleConflict, let title,
                  let adopted = try await adoptOnTitleConflict(
                      failed: error, title: title, model: model, seed: seed
                  )
            else { throw error }
            return adopted
        }
    }

    /// 标题冲突收养（§220）：拉服务端全量名单（归档包
    /// 含——占名者可能已归档，漏了就只剩原样抛错一
    /// 途），投影交 Core 纯函数判定；判到收养则改认
    /// 既有会话为链接目标：它已有消息直接认链（与既
    /// 存③路同义），空行且本地有种子则按其围栏修订
    /// 补种（与既存②路同义）。收养事件留痕（含多条
    /// 匹配的候选数），多条的取舍口径在纯函数内。
    /// 返回 nil＝不收养（调用方照抛原错误）
    private func adoptOnTitleConflict(
        failed error: Error, title: String, model: String?,
        seed: [SeedEntry]
    ) async throws -> LinkOutcome? {
        guard let hermesError = error as? HermesError,
              case .serverError(_, let status, let code) = hermesError
        else { return nil }
        // 名单只用于候选检索（判定不成立照抛原错
        // 误）：不完整至多漏掉候选、回落不收养，方
        // 向保守，不需完整性闸（B-1 防护盘点在案）。
        // 第 67 条包一：名单改读账本（含已归档段；
        // 账本未齐全时账本内回落现拉 include 全量）
        guard let sessions = await appState.sessionLedger
            .adoptionSessions(appState: appState)
        else { return nil }
        let candidates = sessions.map {
            MainlineAdoptionCandidate(
                id: $0.id, title: $0.serverTitle,
                lastActivityAt: $0.endedAt ?? $0.startedAt
            )
        }
        let adoptedID: String
        switch MainlineAdoptionDirective.directive(
            status: status, serverCode: code, title: title,
            candidates: candidates
        ) {
        case .notApplicable, .noCandidate:
            return nil
        case .adopt(let id):
            adoptedID = id
            ChatDiagTrace.record(
                "主线收养：建会话撞 invalid_title，标题「\(title)」既有会话 \(id) 认链"
            )
        case .adoptAmongMultiple(let id, let matchCount):
            adoptedID = id
            ChatDiagTrace.record(
                "主线收养：标题「\(title)」多条匹配 \(matchCount) 条，按 oneday-main- 前缀＋最近活动选定 \(id) 认链"
            )
        }
        if let holder = sessions.first(where: { $0.id == adoptedID }) {
            let heldHistory = (holder.messageCount ?? 0) > 0
            if !heldHistory, !seed.isEmpty {
                try await importSeed(
                    id: adoptedID, title: title, model: model,
                    seed: seed,
                    expectedRevision: holder.runtimeRevision ?? 0
                )
                return LinkOutcome(
                    sessionID: adoptedID, seedLanded: true,
                    serverHeldHistory: false
                )
            }
            return LinkOutcome(
                sessionID: adoptedID, seedLanded: false,
                serverHeldHistory: heldHistory
            )
        }
        return LinkOutcome(
            sessionID: adoptedID, seedLanded: false,
            serverHeldHistory: false
        )
    }

    /// import 种子一步（Dashboard cookie 通道）：
    /// request_id §331 改稳定派生（SideChatLink.
    /// seedRequestID——同一份种子重试恒同 id，围栏
    /// 收据重放防二次落种；旧「每发新铸」作废）；
    /// 落定不看回执——performLink 返回后由发送/回
    /// 读链自然验证，此处 2xx 之外全抛
    private func importSeed(
        id: String, title: String?, model: String?,
        seed: [SeedEntry], expectedRevision: Int
    ) async throws {
        let body = SideChatLink.importSessionBody(
            id: id, title: title, model: model, messages: seed,
            lockUpdatedAt: Date().timeIntervalSince1970
        )
        try await appState.performAdmin { client, config in
            try await client.importServerSession(
                config: config,
                requestID: SideChatLink.seedRequestID(
                    sessionID: id, messages: seed
                ),
                expectedRevision: expectedRevision, sessionBody: body
            )
        }
    }

    /// 当前连接配置（链接动作的网关面直发用；未连接
    /// 时以 sessionExpired 抛——与 driveRun 的未连
    /// 接处理同错误面）
    private func requireConfig() throws -> ServerConfig {
        guard let config = appState.config else {
            throw HermesError.sessionExpired
        }
        return config
    }

    /// 主线链接（0.27.0 立；§331 解门）：id 已知直
    /// 接返 true（发送闸见 SessionLedger.mainSend-
    /// Gate）；id 未知才走认领→performLink 建立——
    /// 成功回写主线线程绑定与种子记账，链接本体失
    /// 败先走回读探针恢复（锚点在即已链、种子转后
    /// 台），探针也失败才**不许静默**地留痕返 false，
    /// 调用方（进页预热或发送前建立）据此决定呈现。
    /// 旧口径两条一并作废：「确认＋种子双位齐才算
    /// 链」（§331 废除——种子不再是发送前置）与更
    /// 早的「失败静默、发送走无状态重放」（串话的
    /// 存续条件，0.27.0 已废）
    /// seedSnapshot：发送路径必传（本轮条目落盘前
    /// 的快照——现取会把本轮新消息也导进种子、与随
    /// 后的尾条发送在服务端落两份）；进页预热传 nil
    /// 时现取主线全量条目（彼时无发送在飞）
    @discardableResult
    private func ensureMainLink(seedSnapshot: [SeedEntry]? = nil) async -> Bool {
        let store = appState.sessionLedger
        // §332：本地状态解码失败的自愈对账排在最前
        // ——标记在册时先向服务端重新发现对账（一
        // 轮只消费一次，账本内守恒）；对账不拦发送：
        // 现任指针有效则下方快路照常，失效才在对账
        // 里改认；目录不可达留痕待下次，不许因侧账
        // 损坏静默清零后本地铸造新 id
        if store.stateReadFailurePendingRediscovery {
            await store.rediscoverAfterStateReadFailure(
                appState: appState
            )
        }
        // §331 快路：id 已知（认领落存/此前铸造）即已
        // 链——种子与历史回补都是后台义务、不再作进
        // 页与发送的闸（旧「confirmed && seeded 双位
        // 齐才算链」口径废除：2026-11-18 三连的爆炸
        // 半径正是此门）。顺带推进后台同步即返
        if case .ready = store.mainSendGate() {
            scheduleMainBackgroundSync()
            return true
        }
        guard appState.config != nil else { return false }
        // §330 认领第一动作：本地无 id 时先向服务端发
        // 现——认领到既有主线以认领 id 链接；目录确认
        // 无主线才落下方铸造冷启动；目录不可达不许铸
        // 造（铸了就是分叉），留痕返 false 待下次重试
        if store.mainServerSessionID == nil {
            let claimOutcome = await store.discoverAndClaimMainline(
                appState: appState
            )
            if claimOutcome == .directoryUnavailable {
                store.noteMainLinkError(
                    "未能向服务器确认主线（目录拉取失败），已暂缓新建——请检查连接后重试"
                )
                return false
            }
        }
        let wantedID = store.ensureMainServerSessionID()
        let mainThread = store.mainThreadID.flatMap { id in
            threads.first { $0.id == id }
        }
        // §331：认领记录里的服务端条数多于本地所持
        // → 历史待回补先记账（回补由后台调度推进，
        // 不等它齐、不拦发送）
        if let mainThread, let record = store.mainClaimRecord,
           record.sessionID == wantedID,
           (record.messageCount ?? 0) > mainThread.entries.count {
            mainThread.historyUnsynced = true
            mainThread.historyServerCount = record.messageCount ?? 0
            mainThread.historyLoadedCount = mainThread.entries.count
            try? modelContext.save()
        }
        let seed = seedSnapshot
            ?? mainThread.map(Self.seedEntries(of:)) ?? []
        do {
            let outcome = try await performLink(
                desiredID: wantedID, title: SideChatStore.mainTitle,
                model: nil, seedEntries: seed,
                adoptsOnTitleConflict: true
            )
            let linkedID = outcome.sessionID
            if linkedID != wantedID {
                // §227：改绑/收养落定先迁账（旧键存量选
                // 择跟到新键），再改存钦定副本——副本与
                // 下方线程绑定在本函数内一并对齐同值
                appState.migrateSessionModelChoice(
                    fromServerSessionID: wantedID,
                    toServerSessionID: linkedID
                )
                store.setMainServerSessionID(linkedID)
            }
            if let mainThread {
                if mainThread.serverSessionID != linkedID {
                    mainThread.serverSessionID = linkedID
                }
                applySeedOutcome(
                    outcome, to: mainThread, seed: seed
                )
                try? modelContext.save()
            }
            store.markMainLinked()
            // §330：认领时保持的归档态在打开（链接落
            // 定）时解档，一次性、落定即清位
            await store.unarchiveClaimedMainlineIfNeeded(
                appState: appState
            )
            await reconcileMainlineModelFromServer(
                linkedID: linkedID, mainThread: mainThread
            )
            scheduleMainBackgroundSync()
            return true
        } catch {
            // §331 恢复探针：链接失败多半死在种子导入
            // 一步——回读服务端现状，锚点在（或可空
            // 建）即视为已链、种子转后台待导入；探针
            // 也失败才按原错误留痕返 false（会话本体
            // 都确认不了时发送无从谈起，仍旧实拦）
            if let recoveredID = await recoverLinkByProbe(
                desiredID: wantedID,
                title: SideChatStore.mainTitle, model: nil
            ) {
                if recoveredID != wantedID {
                    appState.migrateSessionModelChoice(
                        fromServerSessionID: wantedID,
                        toServerSessionID: recoveredID
                    )
                    store.setMainServerSessionID(recoveredID)
                }
                if let mainThread {
                    if mainThread.serverSessionID != recoveredID {
                        mainThread.serverSessionID = recoveredID
                    }
                    mainThread.seedSyncState =
                        SideChatLink.seedTranscript(from: seed).isEmpty
                        ? .notOwed : .pending
                    try? modelContext.save()
                }
                store.markMainLinked()
                await store.unarchiveClaimedMainlineIfNeeded(
                    appState: appState
                )
                scheduleMainBackgroundSync()
                return true
            }
            store.noteMainLinkError(
                (error as? HermesError)?.userMessage ?? "主线会话链接失败"
            )
            return false
        }
    }

    /// 链接结局 → 线程种子记账（§331）：落了记仅文
    /// 本已同步、服务端已持历史记义务消解、两者皆
    /// 非且本地有种子记待导入（后台同步器接手）；旧
    /// serverSeeded 位在义务结清时同步置真（记账面
    /// 保留、发送判据已不读它）
    private func applySeedOutcome(
        _ outcome: LinkOutcome, to thread: ChatThread,
        seed: [SeedEntry]
    ) {
        if outcome.seedLanded {
            thread.serverSeeded = true
            thread.seedSyncState = .syncedTextOnly
        } else if outcome.serverHeldHistory {
            thread.serverSeeded = true
            thread.seedSyncState = .serverHeld
        } else if !SideChatLink.seedTranscript(from: seed).isEmpty {
            thread.seedSyncState = .pending
        } else if thread.seedSyncState == .pending {
            thread.seedSyncState = .notOwed
        }
    }

    /// 链接失败后的回读恢复探针（§331）：按服务端
    /// 现状定生死——会话已存在（任一计数）即锚点
    /// 在、返回其 id；不存在则空建会话保住存在性
    /// （种子留待后台）；探针自身失败（回读不到/
    /// 建不出）回 nil，调用方按原错误收口
    private func recoverLinkByProbe(
        desiredID: String, title: String?, model: String?
    ) async -> String? {
        let existing: ServerSession?
        do {
            existing = try await appState.performAdmin { client, config in
                try await client.serverSession(config: config, id: desiredID)
            }
        } catch let error as HermesError {
            if case .unexpectedStatus(_, let status) = error,
               status == 404 {
                existing = nil
            } else {
                return nil
            }
        } catch {
            return nil
        }
        if existing != nil { return desiredID }
        guard let apiKey = appState.apiKey,
              let config = appState.config else { return nil }
        do {
            if let model {
                let created = try await appState.client
                    .createLinkedServerSession(
                        config: config, apiKey: apiKey,
                        id: desiredID, model: model
                    )
                return created.id
            }
            let created = try await appState.client.createServerSession(
                config: config, apiKey: apiKey,
                id: desiredID, title: title
            )
            return created.id
        } catch {
            return nil
        }
    }

    // MARK: - 历史/种子后台同步调度（§331）

    /// 旧账派生（§331）：自有 id 已绑、种子位未置、
    /// 种子态仍是缺省 notOwed、本地有条目＝0.27.0
    /// 时代没走完链接的线程（链接落定过的线程种子
    /// 位恒真——旧发送路落定即置位，不入此路）：
    /// 种子义务按实情补记 pending，落不落由同步器
    /// 回读定夺，不许升级一次就静默丢账
    private func deriveLegacySeedObligation(_ thread: ChatThread) {
        guard thread.seedSyncState == .notOwed,
              !thread.serverSeeded,
              let id = thread.serverSessionID,
              SideChatLink.isOwnSessionID(id),
              !thread.entries.isEmpty
        else { return }
        thread.seedSyncState = .pending
        try? modelContext.save()
    }

    /// 主线后台同步推进：主线线程的种子欠账与历史
    /// 未同步各排一轮（防重入在各调度器内）；快照
    /// 刷新给设置页呈现。触发点：ensureMainLink 快
    /// 路/落定后、主线发送前——都是顺带推进、从不
    /// 等待、从不拦路
    private func scheduleMainBackgroundSync() {
        let store = appState.sessionLedger
        guard let mainThread = store.mainThreadID.flatMap({ id in
            threads.first { $0.id == id }
        }) else { return }
        // 认领落定的主线：服务端已持历史——种子义
        // 务按 serverHeld 结清（包 1 认领不碰种子记
        // 账，本包在此收口）；其余旧账走通用派生
        if mainThread.seedSyncState == .notOwed,
           store.mainClaimRecord?.sessionID
               == store.mainServerSessionID {
            mainThread.serverSeeded = true
            mainThread.seedSyncState = .serverHeld
            try? modelContext.save()
        } else {
            deriveLegacySeedObligation(mainThread)
        }
        refreshMainSyncStatus(mainThread)
        if mainThread.seedSyncState.needsSyncAttempt {
            scheduleSeedSync(thread: mainThread, seedSnapshot: nil)
        }
        if mainThread.historyUnsynced {
            scheduleHistoryBackfillIfNeeded(thread: mainThread)
        }
    }

    /// 主线同步快照回写（呈现面单点：ChatView 的同
    /// 步动作落点统一经此刷新账本快照，设置页只读）
    private func refreshMainSyncStatus(_ thread: ChatThread) {
        guard thread.id == appState.sessionLedger.mainThreadID
        else { return }
        appState.sessionLedger.updateMainSyncStatus(
            historyUnsynced: thread.historyUnsynced,
            historyLoaded: thread.historyLoadedCount,
            historyTotal: thread.historyServerCount,
            seedState: thread.seedSyncState
        )
    }

    /// 历史回补调度：未同步且未在飞才起任务；一轮
    /// 不齐按退避再续两轮，仍不齐就留在未同步态等
    /// 下个触发点（打开线程/发送/进页），不许无限
    /// 空转
    private func scheduleHistoryBackfillIfNeeded(
        thread: ChatThread
    ) {
        guard thread.historyUnsynced,
              thread.serverSessionID != nil,
              historyBackfillTasks[thread.id] == nil
        else { return }
        let threadID = thread.id
        historyBackfillTasks[threadID] = Task {
            defer { historyBackfillTasks[threadID] = nil }
            let backfiller = SessionHistoryBackfiller(
                appState: appState
            )
            var attempts = 0
            while attempts < 3 {
                let outcome = await backfiller.backfill(
                    thread: thread, context: modelContext
                )
                refreshMainSyncStatus(thread)
                if outcome == .complete { break }
                attempts += 1
                if attempts < 3 {
                    let wait = RetryBackoff.delay(
                        afterFailure: attempts,
                        jitterUnit: Double.random(in: 0...1)
                    )
                    if wait > 0 {
                        try? await Task.sleep(for: .seconds(wait))
                    }
                }
            }
        }
    }

    /// 种子同步调度：欠账且未在飞才起任务；失败按
    /// 退避续两轮，仍失败留在 failed 态等下个触发
    /// 点。落定（仅文本/仅本地）时若用户正看着这条
    /// 线程，给一记安静提示——事实要可见，但不弹窗
    /// 不拦路
    private func scheduleSeedSync(
        thread: ChatThread, seedSnapshot: [SeedEntry]?
    ) {
        guard thread.seedSyncState.needsSyncAttempt,
              seedSyncTasks[thread.id] == nil
        else { return }
        let seed = seedSnapshot ?? Self.seedEntries(of: thread)
        guard !SideChatLink.seedTranscript(from: seed).isEmpty
        else {
            thread.seedSyncState = .notOwed
            try? modelContext.save()
            refreshMainSyncStatus(thread)
            return
        }
        let threadID = thread.id
        let title = threadID == appState.sessionLedger.mainThreadID
            ? SideChatStore.mainTitle : thread.title
        seedSyncTasks[threadID] = Task {
            defer { seedSyncTasks[threadID] = nil }
            let syncer = SessionSeedSyncer(appState: appState)
            var attempts = 0
            while attempts < 3 {
                let state = await syncer.syncSeed(
                    thread: thread, seed: seed, title: title,
                    model: thread.linkedModel,
                    context: modelContext
                )
                refreshMainSyncStatus(thread)
                if !state.needsSyncAttempt {
                    if threadID == currentThreadID {
                        if state == .syncedTextOnly {
                            showNotice("本地历史已同步到服务器（仅文本）")
                        } else if state == .localOnly {
                            showNotice("这段对话的部分早期历史仅保存在本机")
                        }
                    }
                    break
                }
                attempts += 1
                if attempts < 3 {
                    let wait = RetryBackoff.delay(
                        afterFailure: attempts,
                        jitterUnit: Double.random(in: 0...1)
                    )
                    if wait > 0 {
                        try? await Task.sleep(for: .seconds(wait))
                    }
                }
            }
        }
    }

    /// 切入线程时的欠账推进（syncDrawerObject 钩子
    /// 调用）：当前线程有未同步历史/待导入种子各排
    /// 一轮——打开即补、不用等发送
    private func scheduleSyncForCurrentThread() {
        guard let thread = currentThread else { return }
        deriveLegacySeedObligation(thread)
        if thread.historyUnsynced {
            scheduleHistoryBackfillIfNeeded(thread: thread)
        }
        if thread.seedSyncState.needsSyncAttempt {
            scheduleSeedSync(thread: thread, seedSnapshot: nil)
        }
        refreshMainSyncStatus(thread)
    }

    /// 主线模型回读比对（§220 立项、§227 组版改只读）：
    /// 链接确立后回读服务端会话的 model 字段，只与本
    /// 地解析执行值做只读比对——服务端字段是创建时代
    /// 化石、对主线无执行效力，**永不据此写账**（§227
    /// 冻结字段裁决：服务端 model 字段永不写入本地选
    /// 择账；B 原「服务端压本地、经 selectSessionModel
    /// 写账」的收口形态于 0.50.38 组版退役，化石入账
    /// 的唯一写点就此关闭）。不一致时只经 ChatDiag-
    /// Trace 留痕，执行值保持 SessionModelResolution
    /// 解析链原样；服务端无 model/回读失败/两者一致
    /// 时无痕不动。存量主线账由 sessionModelChoice
    /// 在读时与同步目录行比较；匹配的创建时代化石只
    /// 在该次解析中视作未设置，不改写持久化账本。
    private func reconcileMainlineModelFromServer(
        linkedID: String, mainThread: ChatThread?
    ) async {
        guard let session = try? await appState.performAdmin({ client, config in
            try await client.serverSession(config: config, id: linkedID)
        }) else { return }
        let key = AppState.sessionModelKey(
            serverSessionID: linkedID, threadID: mainThread?.id
        )
        let reading = SessionModelTruth.reading(
            stored: appState.sessionModelChoices[key],
            groups: appState.chatModelGroups,
            serverDefault: SessionModelResolution.serverDefaultChoice(
                in: appState.chatModelGroups,
                defaultModel: appState.defaultModel
            ),
            serverReportedModel: session.model
        )
        guard reading.serverReportDisagrees,
              let execution = reading.execution else { return }
        ChatDiagTrace.record(
            "主线模型回读比对：服务端会话报告 \(session.model ?? "") 与本地执行值 \(execution.model) 不一致——服务端字段为化石值、只留痕不写账（会话 \(linkedID)）"
        )
    }

    // MARK: - 服务端会话续聊（0.4.0，审计 §3.4）

    /// 当前线程 → 抽屉当前对象引用的同步（0.36.7 立、
    /// 0.36.29 扩频道出处）：落点/切换/新建/导入的所
    /// 有 currentThreadID 变更点与 onAppear 初始同步
    /// 共用本函数一处派生。频道出处（channelViewing-
    /// Origin）与当前线程的关联会话对得上时，对象引
    /// 用维持 .channel——经频道页点开的会话即便已被
    /// 收养导入成本地线程渲染，呈现期间胶囊仍归频
    /// 道行（频道规格 §10.2：分类归属与选择归属是
    /// 两件事）；对不上（切了别的线程/新建/线程未
    /// 关联）即出处作废清零、回普通线程派生（主线
    /// →.main、其余→.side）。从旁聊区重进同一条收
    /// 养线程的场合（§10.4-⑤），出处由抽屉旁聊行点
    /// 按先行清零，本函数随之派生 .side，不在此处
    /// 特殊处理
    private func syncDrawerObjectFromCurrentThread() {
        // §331：切入线程顺带推进历史/种子欠账（打开
        // 即补；调度器自带防重入，本钩子高频调用无害）
        scheduleSyncForCurrentThread()
        if let origin = appState.router.channelViewingOrigin,
           currentThread?.serverSessionID == origin.sessionID {
            appState.router.currentDrawerObject = .channel(origin.channelID)
            return
        }
        if appState.router.channelViewingOrigin != nil {
            appState.router.channelViewingOrigin = nil
        }
        appState.router.currentDrawerObject =
            DrawerSelectionPolicy.object(
                forThreadID: currentThread?.id,
                mainThreadID: appState.sessionLedger.mainThreadID
            )
    }

    /// 消费待续聊 id：先清 AppState 再导入（防 onChange
    /// 与 onAppear 双通道重复消费同一条）
    /// 0.36.29（频道规格 §10.3/§4.2）：与 id 同行的
    /// 频道来源标记在此定形出处——带标记（频道页点
    /// 开）→ 落 channelViewingOrigin、对象引用置
    /// .channel；无标记（管理页/状态页等其他入口）
    /// → 旧出处清零。首次收养（本次新建导入线程）
    /// 给一行 notice「已转入我的对话」让去向可知
    /// （呈现层拼装、不写入任何会话，沿回告卡 D4
    /// 红线精神）
    private func consumePendingChatSession(_ id: String) async {
        guard appState.router.pendingChatSessionID == id else { return }
        appState.router.pendingChatSessionID = nil
        let channelID = appState.router.pendingChatChannelID
        appState.router.pendingChatChannelID = nil
        // 台账 150：搜索落点请求同行消费（置位—消费
        // —清零同式）；失败重试行不带落点（runImport
        // 默认参数 nil），重试只开会话不落点
        let focusSnippet = appState.router.pendingSearchFocusSnippet
        let focusRole = appState.router.pendingSearchFocusRole
        appState.router.pendingSearchFocusSnippet = nil
        appState.router.pendingSearchFocusRole = nil
        await runImport(
            sessionID: id, channelID: channelID,
            focusSnippet: focusSnippet, focusRole: focusRole
        )
    }

    /// 导入执行体（消费口与失败重试行共用）：出处先
    /// 行落位、按结果收尾；失败除横幅外另记重试上下
    /// 文（基础止血包 P6——旧口径失败只剩一句横幅、
    /// 想重试只能回列表再点一次）
    private func runImport(
        sessionID id: String, channelID: String?,
        focusSnippet: String? = nil, focusRole: String? = nil
    ) async {
        importRetryContext = nil
        // 出处先行落位：导入途中 currentThreadID 变
        // 更触发的同步据此把对象引用派生成 .channel
        appState.router.channelViewingOrigin = channelID.map {
            ChannelViewingOrigin(channelID: $0, sessionID: id)
        }
        let outcome = await openServerSession(id)
        if let channelID {
            switch outcome {
            case .switchedExisting, .importedNew:
                // 落点已定：对象引用归频道行（导入途
                // 中的同步可能已派生过，此处收尾钉死）
                appState.router.currentDrawerObject = .channel(channelID)
                if outcome == .importedNew {
                    showNotice("已转入我的对话")
                }
            case .failed, .missing:
                // 没打开成（仍停在原线程）：出处作废、
                // 对象引用按当前线程回派，不许把胶囊
                // 挂到没在看的频道行上
                appState.router.channelViewingOrigin = nil
                syncDrawerObjectFromCurrentThread()
            }
        }
        if outcome == .failed {
            importRetryContext = (sessionID: id, channelID: channelID)
        }
        // 台账 150：落点已定的打开才排搜索落点（失
        // 败/已删不落点——人还停在原线程）
        if outcome == .switchedExisting
            || outcome == .importedNew,
           let focusSnippet {
            scheduleSearchFocus(
                snippet: focusSnippet, role: focusRole
            )
        }
    }

    /// 搜索落点排期（台账 150＋161）：先在已落盘条
    /// 目里按摘要回找目标（Core SearchTargetResolu-
    /// tion）——找到即排落点（点亮＋收敛，见 land-
    /// SearchFocus）；找不到不再直接落空，转台账
    /// 161 的窗口猎取（timeline＋around 取窗落盘后
    /// 再解析），猎取也无果才如实落空（会话照常开
    /// 着、不假装定位）。线程在等待间被切走即作废
    private func scheduleSearchFocus(
        snippet: String, role: String?
    ) {
        guard let thread = currentThread else { return }
        if let targetID = resolveSearchTarget(
            in: thread, snippet: snippet, role: role
        ) {
            landSearchFocus(on: targetID, threadID: thread.id)
        } else {
            // 台账 161：本地未落区（目标还在未回补的
            // 历史深处）不再直接落空——转窗口猎取：
            // timeline 寻址＋around 取窗落盘后再解析
            huntSearchWindow(
                thread: thread, snippet: snippet, role: role
            )
        }
    }

    /// 搜索落点目标解析（台账 150 口径不变）：在已
    /// 落盘条目里按摘要回找目标条目 id
    private func resolveSearchTarget(
        in thread: ChatThread, snippet: String, role: String?
    ) -> UUID? {
        SearchTargetResolution.targetEntryID(
            entries: thread.sortedEntries.map {
                SearchTargetResolution.EntryStub(
                    id: $0.id, role: $0.role,
                    content: $0.content
                )
            },
            snippet: snippet, role: role
        )
    }

    /// 落点执行（台账 150 原拍不变）：等一拍让条目
    /// 进行集，点亮目标行＋经面分发器下达收敛落点；
    /// 线程在等待间被切走即作废
    private func landSearchFocus(on targetID: UUID, threadID: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard currentThreadID == threadID else { return }
            anchorHighlightEntryID = targetID
            surfaceFocusEntry(targetID)
            try? await Task.sleep(for: .seconds(2.5))
            if anchorHighlightEntryID == targetID {
                anchorHighlightEntryID = nil
            }
        }
    }

    /// 窗口猎取（台账 161）：本地解析落空时的服务
    /// 端正解——拉 timeline 拿 prompt 行号列（分页
    /// 上限 10 页防失控），直达快路（条目文本命中）
    /// 优先、其余自最近一轮起逐轮 around 探针（预
    /// 算 AroundWindowHunt.maxProbes）；命中页按回
    /// 补同款指纹去重落盘，再走本地解析落点。全程
    /// 任一步失败/线程被切走即静默收官——会话照常
    /// 开着、回补仍在后台补齐，不假装定位（150 落
    /// 空口径不变）
    private func huntSearchWindow(
        thread: ChatThread, snippet: String, role: String?
    ) {
        guard let sessionID = thread.serverSessionID,
              !sessionID.isEmpty
        else { return }
        let threadID = thread.id
        let token = UUID()
        searchHuntToken = token
        Task { @MainActor in
            var entries: [SessionTimelineEntry] = []
            var cursor: Int64?
            for _ in 0..<10 {
                let afterCursor = cursor
                guard let page = try? await appState.performAdmin(
                    { client, config in
                        try await client.sessionTimeline(
                            config: config, id: sessionID,
                            afterRowID: afterCursor,
                            limit: AroundWindowHunt.timelineLimit
                        )
                    }
                ) else {
                    // 首面就失败 → 无从寻址、收官；中途
                    // 失败 → 已拉条目照常进探针（部分时
                    // 间线也够定最近若干轮的坐标）
                    if entries.isEmpty { return }
                    break
                }
                entries.append(contentsOf: page.entries)
                guard currentThreadID == threadID,
                      searchHuntToken == token,
                      let next = page.nextCursor, next != cursor
                else { break }
                cursor = next
            }
            guard currentThreadID == threadID,
                  searchHuntToken == token
            else { return }
            let direct = AroundWindowHunt.directPromptRowID(
                entries: entries, snippet: snippet, role: role
            )
            let order = AroundWindowHunt.probeOrder(
                promptRowIDs: entries.map(\.rowID),
                directRowID: direct
            )
            for rowID in order {
                guard currentThreadID == threadID,
                      searchHuntToken == token
                else { return }
                guard let page = try? await appState.performAdmin(
                    { client, config in
                        try await client.sessionMessagesAround(
                            config: config, id: sessionID,
                            rowID: rowID,
                            limit: AroundWindowHunt.pageLimit
                        )
                    }
                ) else { continue }
                let stubs: [AroundWindowHunt.MessageStub] =
                    page.messages.compactMap { message
                        -> AroundWindowHunt.MessageStub? in
                    guard message.id > 0,
                          let row = Int64(exactly: message.id)
                    else { return nil }
                    return AroundWindowHunt.MessageStub(
                        rowID: row, role: message.role,
                        content: message.content
                    )
                }
                guard AroundWindowHunt.targetRowID(
                    in: stubs, snippet: snippet, role: role
                ) != nil else { continue }
                insertHuntedWindow(page.messages, into: thread)
                if let targetID = resolveSearchTarget(
                    in: thread, snippet: snippet, role: role
                ) {
                    landSearchFocus(on: targetID, threadID: threadID)
                }
                return
            }
        }
    }

    /// 猎取命中页落盘：与后台回补同一套组装/去重口
    /// 径（§331 SessionHistoryInserter＋指纹未见过
    /// 滤），已落条目不重复落、反应先对账
    private func insertHuntedWindow(
        _ messages: [SessionMessage], into thread: ChatThread
    ) {
        let ordered = SessionHistoryPagePlanner.chronological(messages)
        let items = SessionHistoryImport.richItems(from: ordered)
        SessionHistoryInserter.reconcileReactions(
            items: items, entries: thread.entries
        )
        let existing = Set(thread.entries.map {
            SessionHistoryInserter.fingerprint(of: $0)
        })
        let unseen = SessionHistorySync.unseenItems(
            items, existing: existing
        )
        SessionHistoryInserter.insert(
            items: unseen, into: thread, context: modelContext
        )
        try? modelContext.save()
    }

    /// 打开服务端会话的结果（0.36.29）：频道消费口
    /// 据此定出处与收养提示——切到既有线程与新建导
    /// 入都算落点已定，只有新建导入算「首次收养」；
    /// .missing（§223）＝会话已不在服务器上、本地残
    /// 留已就地清理，与 .failed 的别只在不挂重试条
    private enum OpenServerSessionOutcome: Equatable {
        case switchedExisting
        case importedNew
        case failed
        case missing
    }

    /// 打开服务端会话续聊：已有 serverSessionID 关联线
    /// 程直接切换（不重复导入）；否则拉元信息＋消息历
    /// 史导入新线程。导入口径（0.8.0 更新）：user/
    /// assistant 有正文或带图者＋工具调用卡进线程呈现
    /// （SessionHistoryImport.richItems）；工具卡与图
    /// 片只呈现、不进上下文重放（组装只取 user/
    /// assistant 正文，见 send）。
    /// R1 结案（0.21.0）：导入线程自带 serverSessionID，
    /// 发送走 SideChatLink 的会话模式（X-Hermes-
    /// Session-Id 头＋仅本轮新消息）——续聊回合按研
    /// 究档实测链回写同一条服务端会话，不再另起记
    /// 录；旧「无状态重放续聊」口径就此作废。
    /// §237 P6：一页消息落盘（分页导入共用）——
    /// 0.8.0（P1）富内容口径不变：工具调用成卡、图
    /// 片标记剥成路径，呈现层有卡有图；工具卡
    /// role="tool" 不进发送上下文（send 组装只取
    /// user/assistant）
    private func insertImportedEntries(
        _ messages: [SessionMessage], into thread: ChatThread
    ) {
        // §331：组装单点收口 SessionHistoryInserter
        // （导入首开与后台回补共用一份，见该文件）
        SessionHistoryInserter.insert(
            messages: messages, into: thread, context: modelContext
        )
    }

    private func openServerSession(
        _ id: String
    ) async -> OpenServerSessionOutcome {
        if let existing = threads.first(where: { $0.serverSessionID == id }) {
            currentThreadID = existing.id
            return .switchedExisting
        }
        guard importingSessionID == nil else { return .failed }
        importingSessionID = id
        defer {
            importingSessionID = nil
            importingLoadedCount = nil
        }
        do {
            let session = try? await appState.performAdmin { client, config in
                try await client.serverSession(config: config, id: id)
            }
            // §237（基础正解批 P6）：导入改分页——
            // limit/offset/order=latest 取最新一页
            // （100 条）先落盘、先建线程、先切换，首
            // 屏不等全量；其后逐页向前补全（offset 只
            // 前进、按消息 id 去重），不许再整表一次
            // 性载入（旧 sessionMessages 全量口径退役
            // 于此路——§331 起它只作分页失败时的降级
            // 二级，见下方首屏取数）
            let pageSize = SessionHistoryPagePlanner.pageSize
            // §331 首屏取数（降级链一级→二级）：分页
            // 失败（非不存在）不许整段「载入失败」——
            // 降级无参全量拉取；全量也失败则走空开
            // （三级，见 catch 内分支前的 openEmpty 分
            // 支）。不存在（404）不降级：直抛外层走
            // §223 .missing 清理
            let firstPage: [SessionMessage]
            var historyComplete = false
            do {
                firstPage = try await appState.performAdmin {
                    client, config in
                    try await client.sessionMessagesPage(
                        config: config, id: id,
                        limit: pageSize, offset: 0
                    )
                }
            } catch let pageError {
                if let hermesError = pageError as? HermesError,
                   hermesError.isSessionNotFound {
                    throw pageError
                }
                do {
                    firstPage = try await appState.performAdmin {
                        client, config in
                        try await client.sessionMessages(
                            config: config, id: id
                        )
                    }
                    historyComplete = true
                } catch let fullError {
                    if let hermesError = fullError as? HermesError,
                       hermesError.isSessionNotFound {
                        throw fullError
                    }
                    // 降级三级：会话本体在目录里存在
                    // （用户亲手点开的）——空线程先开、
                    // 先可读可发，历史记未同步、后台回
                    // 补接手；整段失败呈现就此退役
                    let thread = ChatThread(
                        title: SessionHistoryImport.threadTitle(
                            session: session, entries: []
                        )
                    )
                    thread.serverSessionID = id
                    thread.serverSeeded = true
                    thread.seedSyncState = .serverHeld
                    thread.historyUnsynced = true
                    thread.historyServerCount =
                        session?.messageCount ?? 0
                    thread.historyLoadedCount = 0
                    if let started = session?.startedDate {
                        thread.createdAt = started
                    }
                    thread.updatedAt = session?.endedDate
                        ?? session?.startedDate ?? Date()
                    modelContext.insert(thread)
                    try? modelContext.save()
                    currentThreadID = thread.id
                    scheduleHistoryBackfillIfNeeded(thread: thread)
                    return .importedNew
                }
            }
            let firstChronological =
                SessionHistoryPagePlanner.chronological(firstPage)
            // 标题仍走旧口径（首条用户消息摘要同源；
            // 取数范围改为第一页——有服务端标题时恒
            // 以服务端为准，不受影响）
            let titleEntries = SessionHistoryImport.importableEntries(
                from: firstChronological
            )
            let thread = ChatThread(
                title: SessionHistoryImport.threadTitle(
                    session: session, entries: titleEntries
                )
            )
            thread.serverSessionID = id
            // 0.27.0：导入线程出生即带服务端历史——种
            // 子位直接置真，发送计划走会话模式（绑合
            // 并桶的两条 id 例外：sendPlan 对桶恒判先
            // 链接解绑，见 SideChatLink）
            thread.serverSeeded = true
            thread.seedSyncState = .serverHeld
            thread.historyServerCount = session?.messageCount ?? 0
            if let started = session?.startedDate {
                thread.createdAt = started
            }
            thread.updatedAt = session?.endedDate
                ?? session?.startedDate ?? Date()
            modelContext.insert(thread)
            insertImportedEntries(firstChronological, into: thread)
            try? modelContext.save()
            importingLoadedCount = firstPage.count
            currentThreadID = thread.id
            // 后续页逐页补全：条目自带服务端时刻、
            // 呈现按时刻排序，后到的旧页落位不乱序；
            // §331：中途失败不再整段报错——已落盘部
            // 分保留、线程记未同步、后台回补续拉（缺
            // 的只是更早的历史，会话照常可读可发）
            var seenIDs = Set(firstPage.map(\.id))
            var nextOffset = historyComplete
                ? nil
                : SessionHistoryPagePlanner.nextOffset(
                    currentOffset: 0, receivedCount: firstPage.count
                )
            while let offset = nextOffset {
                let page: [SessionMessage]
                do {
                    page = try await appState.performAdmin {
                        client, config in
                        try await client.sessionMessagesPage(
                            config: config, id: id,
                            limit: pageSize, offset: offset
                        )
                    }
                } catch {
                    thread.historyUnsynced = true
                    thread.historyLoadedCount = thread.entries.count
                    try? modelContext.save()
                    scheduleHistoryBackfillIfNeeded(thread: thread)
                    return .importedNew
                }
                let fresh = SessionHistoryPagePlanner.unseen(
                    page, seenIDs: seenIDs
                )
                seenIDs.formUnion(page.map(\.id))
                if !fresh.isEmpty {
                    insertImportedEntries(
                        SessionHistoryPagePlanner.chronological(fresh),
                        into: thread
                    )
                    try? modelContext.save()
                    importingLoadedCount = seenIDs.count
                }
                nextOffset = SessionHistoryPagePlanner.nextOffset(
                    currentOffset: offset, receivedCount: page.count
                )
            }
            // 拉齐记账：处理量对齐已知总数（或总数未
            // 知而分页已尽）才清未同步位；未对齐保持
            // 位置并排后台回补
            thread.historyLoadedCount = thread.entries.count
            if thread.historyServerCount == 0
                || seenIDs.count >= thread.historyServerCount {
                thread.historyUnsynced = false
            } else {
                thread.historyUnsynced = true
                scheduleHistoryBackfillIfNeeded(thread: thread)
            }
            try? modelContext.save()
            return .importedNew
        } catch {
            // §223：会话已不在服务器上（他处已删、本
            // 地残留行被点开）——清侧账与目录行让残留
            // 行就地消失，文案只给人话、不许状态码原
            // 文上屏（旧路 HermesError.userMessage 把
            // 「404」直甩用户即此病）；走 .missing、
            // 不挂重试条（删都删了，重试无义）
            if let hermesError = error as? HermesError,
               hermesError.isSessionNotFound {
                appState.sessionLedger
                    .noteOpenedSessionMissing(
                        sessionID: id, appState: appState
                    )
                errorMessage = L10n.string(
                    "这条会话已不在服务器上，本地列表已同步清理。"
                )
                return .missing
            }
            // 聊天可靠性包：网络类失败与业务失败分开
            // 说——这条会话本机还没有副本（导入从未
            // 成功过），断网时不是「记录丢了」、是
            // 「还没存到本机」，文案照实说、别让用户
            // 以为记录被清
            if let hermesError = error as? HermesError,
               hermesError.isTransient {
                errorMessage = "网络不可用，这条会话还没存到本机，联网后就能打开。"
            } else if error is URLError {
                errorMessage = "网络不可用，这条会话还没存到本机，联网后就能打开。"
            } else if let hermesError = error as? HermesError {
                presentError(hermesError)
            } else {
                errorMessage = "会话导入失败，请稍后重试。"
            }
            return .failed
        }
    }

    /// FA-1：讨论信号待发判定——线程有待发关联、
    /// 且线程内尚无任何用户条目（本轮将落的即首
    /// 句）才返回帖 id；关联在但已有用户条目＝首句
    /// 时机已过（信号只认首句，过期不补发）
    private func feedDiscussSignalTarget(thread: ChatThread) -> String? {
        guard let postID = appState.sessionLedger.feedDiscussPostID(
            forThreadID: thread.id
        ) else { return nil }
        guard !thread.sortedEntries.contains(where: {
            $0.role == "user"
        }) else { return nil }
        return postID
    }

    /// FA-1：发一记 discuss 信号——先销账（只报一
    /// 次，防第二句重复触发），再尽力上报；失败静
    /// 默（弱回执，不在聊天里摆错误面）。note 经
    /// Core FeedDiscussSignal 只取首句中的自述偏好
    /// 句，无自述则不带、桥按弱信号记账
    /// §208：firstText 入参恒为用户亲笔正文（send
    /// 的 text 快照）——引用块只活在 outgoingContent
    /// 拼装里、永不回流本入参。§208 前预填整段进
    /// input 时，原帖正文随首句被标记词扫描误提偏
    /// 好（诊断 §1.4）；注入通道退役后此面自动收
    /// 净，本注钉死：不许改传组装后文本
    private func fireFeedDiscussSignal(
        postID: String, threadID: UUID, firstText: String
    ) {
        appState.sessionLedger.clearFeedDiscuss(forThreadID: threadID)
        // FA-2：种子帖不在桥上，讨论信号短路（不拿本地
        // id 打桥的 /feed/{id}/signal）
        guard !FeedSeedPosts.isSeed(postID),
              let config = appState.config else { return }
        let note = FeedDiscussSignal.preferenceNote(in: firstText)
        Task {
            _ = try? await OneDayBridgeClient().sendFeedDiscussSignal(
                config: config, id: postID, note: note
            )
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = attachments
        // 0.4.1：引用随本条发送，起手先快照、随即清除
        // 引用条（发送即消费，不残留到下一条）
        let quote = pendingQuote
        // §208：动态引用同槽同纪律——一并快照/清除，
        // 失败退回路径一并恢复（各恢复点与 quote 同行）
        let feedQuote = pendingFeedQuote
        // §219：点子／文件引用同槽同纪律——一并快照/
        // 清除，失败退回路径一并恢复（与 feedQuote 同
        // 行）；两快照至多一个非空（槽位互斥由写入侧
        // 收口保证），拼装口合并见 outgoingContext
        let sourceQuote = pendingSourceQuote
        // §219：拼装口统一载荷——点子／文件快照优先，
        // 动态快照包成 .feed 族（两快照互斥、合并无
        // 损）；落盘构造与上下文拼装共用本值
        let combinedSourceQuote = sourceQuote
            ?? feedQuote.map(SourceQuote.feed)
        // 修复包二锁二（§419）：守卫只把内容总闸——
        // !isStreaming 摘除：流式中发送同路走下方构
        // 造段，账本在席（在飞轮）时由 §414 账本分
        // 支落位待发、轮终 drain 串行派发；「同会话
        // 至多一轮在飞」改由出口 drain 守卫把守，
        // 入口不再禁止
        guard !text.isEmpty || !pending.isEmpty else { return }
        // D3（DESIGN §352）：编辑态在武装时发送分
        // 流——target 之后还有已落定轮次（rounds-
        // After>0）先弹破坏性确认：稿快照暂存、发
        // 送舱原样不动，取消即回编辑态；末轮直走
        // performEditSend。快照口径与下方正常发送
        // 同（text/pending/quote/feedQuote/source-
        // Quote 四件已在本函数起手取齐）
        if let target = editSentTarget {
            let draft = EditSendDraft(
                text: text, attachments: pending,
                quote: quote, feedQuote: feedQuote,
                sourceQuote: sourceQuote
            )
            if let thread = currentThread,
               RewindTurnSlicing.roundsAfter(
                   target: target.entryID,
                   in: thread.sortedEntries
               ) > 0 {
                pendingEditSend = draft
                return
            }
            performEditSend(draft: draft, target: target)
            return
        }
        // H2-a：发送新消息即停播（施工图 3.3 播放态
        // 管理口径）——只在真发送的路径上停，守卫退
        // 回的空发不打扰正在听的朗读
        SpeechPlayer.shared.stop()
        // 触感口径（2026-11-14 定版，覆盖 0.3.2「发送
        // 起手不挂触感」）：发送动作补最轻档 impact
        // .light，落点在条目落盘上屏处（见下方 insert
        // 后）——前置校验退回路径（定位失败）不许
        // 响，响必须与「消息真发出了」同因果；§414
        // 起旧轮未落定不再退回：条目落位待发、同落
        // 盘点响；结果点不变：完成 .success / 失败
        // .error
        input = ""
        attachments = []
        pendingQuote = nil
        pendingQuoteIsFork = false
        pendingFeedQuote = nil
        pendingSourceQuote = nil
        errorMessage = nil
        dismissNotice()
        guard let thread = ensureThread() else {
            // 0.27.0：定位失败整轮不发——输入与附件原
            // 样退回发送舱（错误文案已由 ensureThread
            // 置好），不许把消息落进别的线程
            input = text
            attachments = pending
            pendingQuote = quote
            pendingFeedQuote = feedQuote
            pendingSourceQuote = sourceQuote
            return
        }
        // §414（修复包一·路三）：未发送条目原位编辑
        // 的武装在本线程发送时消费——新内容写回原条
        // 目本体（同 id、同位置、不删条重建）再走发
        // 件箱统一重发口；目标已落定/已撤回则武装过
        // 期作废、走正常发送；目标在别的线程时不消
        // 费（回其线程发送才轮到它），目标已不存在
        // 时武装作废
        if let targetID = unsentEditTargetID {
            if let target = thread.entries.first(
                where: { $0.id == targetID }
            ) {
                let filesRepresented =
                    unsentEditFilesRepresented
                unsentEditTargetID = nil
                unsentEditFilesRepresented = false
                if isOutboxEntry(target) {
                    performUnsentEditSend(
                        target: target, thread: thread,
                        text: text, pending: pending,
                        quote: quote,
                        combinedSourceQuote: combinedSourceQuote,
                        filesRepresented: filesRepresented
                    )
                    return
                }
            } else if !threads.contains(where: {
                $0.entries.contains { $0.id == targetID }
            }) {
                unsentEditTargetID = nil
                unsentEditFilesRepresented = false
            }
        }
        // FA-1：动态讨论信号的待发判定要在本轮条目
        // 落盘前算——本线程若由动态「讨论」建聊而来
        // 且从未发过用户消息，本条即首句（信号 note
        // 只许取首句，契约 rev2 §1.9）；判定收口在
        // feedDiscussSignalTarget，落盘后据此发信号
        let feedDiscussPostID = feedDiscussSignalTarget(thread: thread)
        // 0.27.0：种子快照要在本轮条目落盘前取——链
        // 接时的历史导入只含既往条目，本轮新消息由
        // 随后的会话模式发送单独投递，不许在服务端
        // 落两份
        let seedSnapshot = Self.seedEntries(of: thread)
        let imageDatas = pending.compactMap(\.imageData)
        let filePayloads = pending.compactMap(\.filePayload)
        // §135 D 案打点：发送帧起手时刻（条目落盘前）
        // ——落盘→链接、首帧复核、发送→落定三段读数
        // 以此为零点（记账点见 sendPinToken 递增处、
        // 复贴复核点与 applySettledTurn 入口）
        sendFrameStartedAt = Date()
        sendFrameRestickLogged = false
        let newEntry = ChatEntry(
            role: "user", content: text, thread: thread,
            imageData: imageDatas.first, imageDatas: imageDatas,
            quote: quote, sourceQuote: combinedSourceQuote
        )
        modelContext.insert(newEntry)
        sessionSentEntryIDs.insert(newEntry.id)
        // 发送触感（2026-11-14 定版）：消息落盘上屏
        // 同帧补最轻档 impact——「把球交出去」一下轻
        // 震；自动重发/队列补发不经本函数、不许响
        Haptics.impact(.light)
        // 0.7.0（M3）：主线标题恒「主线」、不被首条消息
        // 派生覆盖——主线线程标题在钦定落位时即为「主线」
        // 本就不进本分支，此守卫是双保险
        if thread.title == "新会话", thread.id != appState.sessionLedger.mainThreadID {
            thread.title = text.isEmpty ? "图片消息" : String(text.prefix(20))
        }
        thread.updatedAt = Date()
        try? modelContext.save()
        // §237（P1）：发送状态入队＋文件载荷起手落盘
        // 暂存——进程在此后任何时点被杀，重启后凭条
        // 目 id 能把文件名与字节原样重建，重发不许退
        // 化成纯文本；暂存写失败不拦发送（同次运行仍
        // 有内存格兜底），上传全成后在 launchTurn 清
        // §410：暂存写盘改后台（stageDetached）——点
        // 发送不再同步付全量字节写盘；读侧由店内在飞
        // 登记等落定，被杀语义不变（原子换入、manifest
        // 最后写，中途被杀只留无 manifest 临时目录）
        newEntry.markSendState(.queued, in: modelContext)
        if !filePayloads.isEmpty {
            stagedSendStore.stageDetached(
                entryID: newEntry.id,
                payloads: filePayloads.map {
                    StagedSendPayload(name: $0.name, data: $0.data)
                }
            )
        }
        // §208（规格 §3.3 顺手项）：发送即显式清本线
        // 程草稿键——旧口径 send() 只清内存 input、
        // 账上删键靠之后切线程回存空串，「发送后不切
        // 线程即杀进程」时冷启会把已发出的旧草稿再
        // 装回来（诊断 §1.2 注的推演口子）；本条已
        // 落盘，草稿使命结束，当场销账
        appState.sideChats.setDraft("", for: thread.id)
        // FA-1：首句已落盘——发讨论信号（销账先行、
        // 只报一次；note 只取首句里的自述偏好句，
        // 无则不带、桥记弱信号）
        if let feedDiscussPostID {
            fireFeedDiscussSignal(
                postID: feedDiscussPostID, threadID: thread.id,
                firstText: text
            )
        }
        // §414（修复包一·路一）：本线程有未落定 run
        // 账本（切后台/杀进程遗留或对账未完）时不再
        // 整轮弹回——条目已按上方正常口径落盘，本
        // 处只改投递时机：挂待发标记原位呈现（时钟
        // 标记＋发件箱成员资格；待发身份另受整段替
        // 换与半截回填的候选界保护、不陪葬，种子口
        // 径亦排除待发、不双账），先触发旧轮对账；
        // 旧轮落定后由发件箱 drain 按落盘序自动真
        // 发（派发钩子在 launchTurn/resendPending 的
        // driveRun 收尾与 resumeRunIfNeeded 出口）。
        // 0.31.0「同会话同时至多一轮在飞」的互斥不
        // 变——改的是投递面（落位排队），不是取消
        // 互斥
        // §451（发送机制换代）：账本停车分支退役——
        // 本条不再等上一轮落定：下方 launchTurn 登
        // 记工单入提交泵，本条立即提交、服务端 FIFO
        // 排班（§419 的客户端排队形态就此作废）；变
        // 色只挂受理回执（markAcceptedEntryAccepted
        // 在 POST 202 同点），上一轮还在生成不挡本
        // 条满色
        // 上下文组装走共用出口 outgoingContext（组装
        // 口径注在该函数；基础止血包起失败重发同走它，
        // 两路不许分叉）
        let context = outgoingContext(
            of: thread, tailEntry: newEntry, text: text, quote: quote,
            sourceQuote: combinedSourceQuote
        )
        // 文件真发送（0.36.29，契约实测冻结后开放）：
        // 待发文件在轮次起手逐个上传到服务端
        // attachments/，回执路径拼进尾条 input 的
        // @file 引用（见 launchTurn 内）；原「尚未开
        // 放」notice 随本版退役
        launchTurn(
            thread: thread, userEntry: newEntry, text: text,
            filePayloads: filePayloads, presetFilePaths: [],
            seedSnapshot: seedSnapshot, context: context
        )
    }

    /// 出站上下文组装（send 与失败重发共用出口）：
    /// 0.4.1 起走 MessageQuote.outgoingContent——带引
    /// 用的消息（含本轮新消息与历史回放）把引用块拼
    /// 进 content，引用在每轮重放里持续在场；无引用
    /// 的消息原样（纯函数保证）。0.8.0：先滤角色再取
    /// 尾 20——工具卡条目（role="tool"）只呈现、永不
    /// 进重放上下文；§123/§165：系统锚定条目（回响＋
    /// 审批锚定，isSystemAnchored）同样只呈现、永不
    /// 进上下文。尾条带图时最后一条用户消息改多模态
    /// parts 编码（图片走 OpenAI image_url + data:
    /// base64；服务端/模型不支持时错误经 errorBanner
    /// 如实呈现，不假装发过）——图片全集取尾条条目
    /// 本体（send 落盘时即全集入条目、重发时条目即
    /// 事实源，两路同值）
    private func outgoingContext(
        of thread: ChatThread, tailEntry: ChatEntry,
        text: String, quote: MessageQuote?,
        sourceQuote: SourceQuote?
    ) -> [ChatMessage] {
        var context = thread.sortedEntries
            .filter {
                ($0.role == "user" || $0.role == "assistant")
                    && !$0.isSystemAnchored
            }
            .suffix(20).map {
            ChatMessage(
                role: $0.role,
                content: MessageQuote.outgoingContent(
                    userText: $0.content, quote: $0.quote,
                    sourceQuote: $0.sourceQuote
                )
            )
        }
        let imageDatas = tailEntry.allImageDatas
        if !imageDatas.isEmpty, let last = context.last, last.role == "user" {
            let urls = imageDatas.map {
                "data:image/jpeg;base64,\($0.base64EncodedString())"
            }
            context[context.count - 1] = ChatMessage(
                role: "user",
                text: MessageQuote.outgoingContent(
                    userText: text, quote: quote,
                    sourceQuote: sourceQuote
                ),
                imageDataURLs: urls
            )
        }
        return context
    }

    /// 一轮的投递登记（send 与失败重发共用）：§451
    /// 起只登记提交工单＋踢提交泵——上传/定形/POST
    /// 由泵按线程内序串行执行（performSubmission/
    /// performSubmit），受理后的事件消费与对账由消
    /// 费环按提交序逐轮接（kickConsumer）。旧形态
    /// （本函数内联「上传→定形→driveRun 一条龙＋
    /// sendTask 承载」）退役：它把投递与消费焊死，
    /// 是「同会话至多一轮在飞」客户端排队的结构根
    /// 源。回滚路见 DESIGN §451（不设旗开关、
    /// revert 本包提交、无数据迁移）
    private func launchTurn(
        thread: ChatThread, userEntry: ChatEntry, text: String,
        filePayloads: [(name: String, data: Data)],
        presetFilePaths: [String],
        seedSnapshot: [SeedEntry], context: [ChatMessage]
    ) {
        submitJobs[userEntry.id] = SubmitJob(
            thread: thread, userEntry: userEntry, text: text,
            filePayloads: filePayloads,
            presetFilePaths: presetFilePaths,
            seedSnapshot: seedSnapshot, context: context,
            frameStartedAt: sendFrameStartedAt
        )
        kickSubmitPump(thread: thread)
    }

    /// 本轮失败的统一落点（基础止血包 P1/P2）：条目
    /// 留原地挂失败标记——不删条目、不回退输入框；
    /// 文件载荷在场时暂存供重发补传。成功落定清标记
    /// 在 applySettledTurn，重发启动清标记在 resend-
    /// FailedEntry。
    /// 发送失败机制包：成因同点落账（outboxRetry.
    /// setFailureKind）——政策准入与呈现投影的唯一
    /// 材料；旧落点不记成因，成因只活在各出口的局
    /// 部变量里，政策只能看状态、呈现只能拼整句。
    /// 横幅单槽指向（failedResendEntryID）随语义 5
    /// 退役：横幅不再指向任何单条
    private func markTurnFailed(
        entry: ChatEntry,
        filePayloads: [(name: String, data: Data)] = [],
        failureKind: SendFailureKind
    ) {
        // §237：失败标记走统一状态写口（sendStateRaw
        // 与 sendFailed 同步落盘，不许再散写）
        entry.markSendState(.failed, in: modelContext)
        appState.outboxRetry.setFailureKind(
            entryID: entry.id, kind: failureKind
        )
        if !filePayloads.isEmpty {
            failedFilePayloads[entry.id] = filePayloads
            // §237 P1：载荷同步落盘暂存——进程重启后
            // 内存格不在，凭条目 id 仍能重建补传
            stagedSendStore.stageDetached(
                entryID: entry.id,
                payloads: filePayloads.map {
                    StagedSendPayload(name: $0.name, data: $0.data)
                }
            )
        }
    }

    /// §237 P1：重发载荷的统一取数——同次运行先查
    /// 内存格，未命中回磁盘暂存按条目 id 重建（进程
    /// 重启后的唯一出处）；磁盘也无（从未带文件/已
    /// 上传清格）返回空，调用方按远端路径口径走
    private func resendFilePayloads(
        entryID: UUID
    ) -> [(name: String, data: Data)] {
        if let inMemory = failedFilePayloads[entryID] {
            return inMemory
        }
        guard let staged = try? stagedSendStore.loadPayloads(
            entryID: entryID
        ) else { return [] }
        return staged.map { (name: $0.name, data: $0.data) }
    }

    /// run 落定失败的标记落点（P2）：按账本里的用户
    /// 条目 id 回找条目挂标记——条目已不在（线程被
    /// 清）则静默跳过。成因走运行面分类（语义 3：
    /// 生成失败永不自动重发，kind 落账即钉死）
    private func markRunFailure(
        entry: RunLedgerEntry, in thread: ChatThread,
        failure: HermesError
    ) {
        guard let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) else { return }
        markTurnFailed(
            entry: userEntry,
            failureKind: SendFailureKind.classify(run: failure)
        )
    }

    /// 失败条目重发（基础止血包 P1/P2，微信点感叹号
    /// 口径；§414 改判原位）：恒以原条目本体再走一
    /// 轮——同 id、同位置、clientMessageID 不动（服
    /// 务端凭幂等键回原 run 不双跑，§383）。旧「非
    /// 末条复制到末尾＋删原条」作废：复制的唯一理
    /// 由是落定整段替换按用户条目时刻清其后条目、
    /// 会误伤其后已落定轮次；§414 已给整段替换与
    /// 半截回填装上「下一轮用户条目」界（turnPar-
    /// tialCandidates），中段原位重发的落定只清本
    /// 轮半截、其后轮次免于陪葬，复制删条失去存
    /// 在理由。出站只喂本条（与 resendPending 同口
    /// 径：会话载荷恒取尾条、本条即尾条，本条在
    /// 线程中的位置与出站形态无关）；种子按非待
    /// 发序位剔除本条自身、其余历史原样。账本在
    /// 飞守卫防叠发（与 send() 同一道闸），成功落
    /// 定自动清标记、再失败由各失败分支重新挂上
    private func resendFailedEntry(_ entry: ChatEntry) {
        guard entry.sendFailed,
              let thread = entry.thread else { return }
        // §451：在飞闸退役——重发只登记工单入泵，
        // 同线程有未落定轮次不再挡（服务端 FIFO 排
        // 班），本条按线程内序位提交；若本条正是堵
        // 泵的失败头条，手点重发即解堵口。发送失败
        // 机制包：手点重发不清重试记账（清账点全集
        // 只有落定成功/撤回/编辑重投——预算是条目
        // 一生的账，用户意志重置只认编辑重投）
        errorMessage = nil
        sendFrameStartedAt = Date()
        sendFrameRestickLogged = false
        entry.sendFailed = false
        // §237：重发启动即回待发队列态（与清失败标
        // 记同点，状态原值不许残留 failed）
        entry.markSendState(.queued, in: modelContext)
        thread.updatedAt = Date()
        try? modelContext.save()
        // 种子与出站组装走 resendJobParts 共用口
        // （种子按非待发序位摘除本条自身、出站只喂
        // 本条；与泵的无工单重组同一份，不许分叉）
        let parts = resendJobParts(thread: thread, entry: entry)
        launchTurn(
            thread: thread, userEntry: entry,
            text: entry.content,
            // §237 P1：载荷取数走统一口——内存未命中
            // 回磁盘暂存重建，重启后不退化纯文本；原
            // 位重发后键恒为本条 id，不再有复制转移
            filePayloads: resendFilePayloads(entryID: entry.id),
            presetFilePaths: entry.remoteFilePaths,
            seedSnapshot: parts.seedSnapshot,
            context: [parts.outgoing]
        )
    }

    /// 待发条目重发（聊天可靠性包，2026-11-13）：
    /// 用户点按气泡旁待发时钟标记（§407）触发——
    /// 不新建条目，用同一条目再投一次。§451 起只组
    /// 装工单入泵（launchTurn）：旧「本页复刻上传＋
    /// 定形＋driveRun 一条龙」退役，上传/定形/提交
    /// 由泵按同口径执行（上传回填远端路径、暂存清
    /// 理、大小记账都在泵的提交段同点处理）；与
    /// send() 的互斥口径同步退役——同线程未落定
    /// 轮次不再挡重发（服务端 FIFO 排班），本条按
    /// 线程内序位提交
    private func resendPending(_ entry: ChatEntry) {
        guard entry.isPendingSend,
              let thread = entry.thread ?? currentThread
        else { return }
        errorMessage = nil
        dismissNotice()
        var stashed = pendingResendAttachments[entry.id] ?? []
        // §237 P1：内存暂存不在（进程重启后）时回磁
        // 盘暂存重建文件附件——图片本就在条目落盘数
        // 据里、不经此路；重建不出才真是纯文本重发
        if stashed.isEmpty {
            let staged = (try? stagedSendStore.loadPayloads(
                entryID: entry.id
            )) ?? []
            stashed = staged.map {
                PendingAttachment(
                    kind: .file(name: $0.name, data: $0.data)
                )
            }
        }
        let filePayloads = stashed.compactMap(\.filePayload)
        let parts = resendJobParts(thread: thread, entry: entry)
        launchTurn(
            thread: thread, userEntry: entry,
            text: entry.content,
            filePayloads: filePayloads,
            presetFilePaths: entry.remoteFilePaths,
            seedSnapshot: parts.seedSnapshot,
            context: [parts.outgoing]
        )
    }

    // MARK: - 发件箱（台账 154／G-04，DESIGN §336）

    /// 发件箱成员判定（单点）：本条用户消息还没落
    /// 定在服务端——失败（sendFailed）、待发（de-
    /// liveryState=pending）、准备段瞬态被进程中断
    /// （queued/uploading/linking 落盘后无人接管）、
    /// 提交段孤儿（sending 但 run 账本无此轮且泵未
    /// 在提交本条）。呈现（动作面项集）、手动入口
    /// （重发/编辑/撤回）与提交泵共用本判定，不许
    /// 各写一份
    private func isOutboxEntry(_ entry: ChatEntry) -> Bool {
        guard entry.role == "user", !entry.isSystemAnchored,
              entry.toolCardData == nil else { return false }
        if entry.sendFailed || entry.isPendingSend {
            return true
        }
        guard let state = entry.sendState else { return false }
        switch state {
        case .queued, .uploading, .linking, .failed:
            return true
        case .sending:
            // §451：逐条核账——本条无账本且泵未在提
            // 交本条，才是提交段孤儿（多轮并存后「整
            // 线程账本判空＋无流在跑」的旧口径作废：
            // 别的轮次在飞不该把本条的孤儿身份藏起
            // 来）
            return appState.runLedger.entry(
                forUserEntryID: entry.id
            ) == nil
                && !pumpInFlightEntryIDs.contains(entry.id)
        case .accepted:
            // 发送失败机制包（双轴语义）：已受理条目
            // 恒有账本、对账链管辖，不进发件箱动作
            // 面；账本缺失的受理态是孤儿变体（账本被
            // 异常清走）——浮回发件箱面交用户裁决，
            // 不许无声卡死
            return appState.runLedger.entry(
                forUserEntryID: entry.id
            ) == nil
        case .delivered:
            return false
        }
    }

    /// 发件箱条目的统一重发口（动作面与提交泵共
    /// 用）：失败条目走既有 resendFailedEntry；待
    /// 发与准备段中断条目先折回待发巷（markPend-
    /// ingSend——获得「未发送」可见标记与 resend-
    /// Pending 的入场资格）再走 resendPending。不
    /// 新建发送链、与手点同一条路
    private func resumeOutboxEntry(_ entry: ChatEntry) {
        // §451：在飞守卫退役——重发只登记工单入
        // 泵、与任何在飞轮次共存（泵按序位提交）；
        // 旧守卫防的是 launchTurn 直驱叠发，入泵后
        // 无此患
        guard isOutboxEntry(entry) else { return }
        if entry.sendFailed {
            resendFailedEntry(entry)
            return
        }
        if !entry.isPendingSend {
            entry.markPendingSend(in: modelContext)
        }
        resendPending(entry)
    }

    /// 撤回未发送条目（台账 154）：本条从未在服务
    /// 端落定（失败/待发/中断态），撤回是纯本地动
    /// 作——删条目、清暂存载荷（内存格＋磁盘暂
    /// 存）、清自动重试记账、清指向本条的失败横幅
    /// 账。服务端无此条、不发任何请求
    private func withdrawUnsentEntry(_ entry: ChatEntry) {
        // 在飞守卫（与 editUnsentEntry 同口径）：正
        // 被 launchTurn/driveRun 驱动的条目（发送在
        // 飞的 queued/uploading 本体）不许删——驱动
        // 链持其引用继续走，删之即与落定写口相撞。
        // 孤儿态条目无流在跑、恒可撤
        guard isOutboxEntry(entry),
              appState.runLedger.entry(
                  forUserEntryID: entry.id
              ) == nil,
              !pumpInFlightEntryIDs.contains(entry.id)
        else { return }
        let entryID = entry.id
        // §414：撤回的若是原位编辑的武装目标，武装
        // 同点作废（条目已删、写回无从谈起）
        if unsentEditTargetID == entryID {
            unsentEditTargetID = nil
            unsentEditFilesRepresented = false
        }
        failedFilePayloads[entryID] = nil
        pendingResendAttachments[entryID] = nil
        try? stagedSendStore.remove(entryID: entryID)
        appState.outboxRetry.clear(entryID: entryID)
        modelContext.delete(entry)
        try? modelContext.save()
    }

    /// 编辑未发送条目（台账 154；§414 改判原位）：
    /// 把内容与附件装载进发送舱并武装目标——装载
    /// 走既有载荷口径（图片全集在条目本体、文件
    /// 凭条目 id 回暂存重建、引用两槽按 send() 快
    /// 照的同款互斥回填）；原条目不删、不动，用户
    /// 改完点发送时由 send() 把新内容写回原条目
    /// 本体原位重发（performUnsentEditSend，同
    /// id/同位置）。旧「回收删条＋新条目新一轮」
    /// 作废：删条重建让失败消息在编辑一次后换位
    /// 换身份，与失败不消失定版相悖；旧虑「原地
    /// 改字让已拼装出站形态与条目分叉」由写回后
    /// 重走发件箱重发口消解（出站形态在重发时按
    /// 新条目内容现拼，不存在先拼后改）
    private func editUnsentEntry(_ entry: ChatEntry) {
        guard isOutboxEntry(entry),
              let thread = entry.thread,
              thread.id == currentThreadID else { return }
        // §451：账本在飞不再挡编辑（本条未受理、编
        // 辑后由 send() 写回原位再入泵）；只挡泵正
        // 在提交本条的瞬时窗（写回会与提交段相撞）
        guard !pumpInFlightEntryIDs.contains(entry.id)
        else {
            showNotice("这条正在发送中，稍等一下再编辑。")
            return
        }
        // 发送舱有未发完的内容时不许回收覆盖（用户
        // 亲笔优先）：正文/附件/引用槽任一在场都算
        // 占用，先请用户处理完
        guard input.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty,
              attachments.isEmpty, pendingQuote == nil,
              pendingFeedQuote == nil,
              pendingSourceQuote == nil
        else {
            showNotice("输入框里还有没发完的内容，先发掉或清空，再来编辑这条。")
            return
        }
        let text = entry.content
        let imageDatas = entry.allImageDatas
        let filePayloads = resendFilePayloads(
            entryID: entry.id
        )
        let quote = entry.quote
        let sourceQuote = entry.sourceQuote
        // §414：只武装＋装载，原条目原样留列（失败/
        // 待发标记、暂存、远端路径全不动）；文件面
        // 管辖按载荷可代表性记账（载荷不在而远端路
        // 径在场＝文件已在服务端，编辑只管正文/图
        // 片/引用，文件面在写回时原样保留）
        unsentEditTargetID = entry.id
        unsentEditFilesRepresented = !filePayloads.isEmpty
            || entry.remoteFilePaths.isEmpty
        input = text
        attachments = imageDatas.map {
            PendingAttachment(kind: .image($0))
        } + filePayloads.map {
            PendingAttachment(
                kind: .file(name: $0.name, data: $0.data)
            )
        }
        pendingQuote = quote
        switch sourceQuote {
        case .feed(let feedQuote):
            pendingFeedQuote = feedQuote
        case .idea, .file, .goal:
            pendingSourceQuote = sourceQuote
        case nil:
            break
        }
        composerFocusHandle.focus()
    }

    /// §414（修复包一·路三）：未发送编辑的发送落点
    /// ——新内容写回原条目本体（applyUnsentEdit：
    /// 同 id、同时刻、同位置，发送状态不动），附
    /// 件面按武装时的可代表性分工：可代表时以发
    /// 送舱快照重建——旧暂存（内存格＋磁盘）全
    /// 清、新载荷重暂存、远端路径作废待重传（上
    /// 传同名覆盖、口径见 uploadPendingFiles）；
    /// 不可代表时（文件已在服务端、载荷不在本
    /// 机）文件面一字不动、只改正文/图片/引用。
    /// 写回后走发件箱统一重发口 resumeOutbox-
    /// Entry（失败/待发/准备段中断三态同口分
    /// 发），标记与状态由重发链自理
    private func performUnsentEditSend(
        target: ChatEntry, thread: ChatThread, text: String,
        pending: [PendingAttachment], quote: MessageQuote?,
        combinedSourceQuote: SourceQuote?,
        filesRepresented: Bool
    ) {
        let imageDatas = pending.compactMap(\.imageData)
        let filePayloads = pending.compactMap(\.filePayload)
        target.applyUnsentEdit(
            content: text, imageDatas: imageDatas,
            quote: quote, sourceQuote: combinedSourceQuote,
            in: modelContext
        )
        if filesRepresented {
            failedFilePayloads[target.id] = nil
            pendingResendAttachments[target.id] = nil
            try? stagedSendStore.remove(entryID: target.id)
            if !filePayloads.isEmpty {
                try? stagedSendStore.stage(
                    entryID: target.id,
                    payloads: filePayloads.map {
                        StagedSendPayload(
                            name: $0.name, data: $0.data
                        )
                    }
                )
            }
            target.remoteFilePathsData = nil
            try? modelContext.save()
        }
        // 发送失败机制包（语义 1 清账点③）：编辑重
        // 投＝用户显式新尝试——重试记账在此清零（预
        // 算由用户意志重置）；手点原样重发不清（见
        // resendFailedEntry 注）
        appState.outboxRetry.clear(entryID: target.id)
        resumeOutboxEntry(target)
    }

    // MARK: - §451 发送机制换代（提交泵＋消费环）

    /// 重发口组装（resendFailedEntry/resendPending/
    /// 泵的无工单重组共用）：种子按非待发序位摘除
    /// 本条自身（本条只以尾条身份经 run 投递、不许
    /// 在种子里先落一份）、出站只喂本条（引用拼装
    /// ＋本地图多模态，与 send() 尾条同口径）
    private func resendJobParts(
        thread: ChatThread, entry: ChatEntry
    ) -> (seedSnapshot: [SeedEntry], outgoing: ChatMessage) {
        let nonPendingIDs = thread.sortedEntries
            .filter { !$0.isPendingSend }
            .map(\.id)
        var seedSnapshot = Self.seedEntries(of: thread)
        if let seedIndex = nonPendingIDs.firstIndex(
            of: entry.id
        ), seedIndex < seedSnapshot.count {
            seedSnapshot.remove(at: seedIndex)
        }
        var outgoing = ChatMessage(
            role: "user",
            content: MessageQuote.outgoingContent(
                userText: entry.content, quote: entry.quote,
                sourceQuote: entry.sourceQuote
            )
        )
        let entryImageDatas = entry.allImageDatas
        if !entryImageDatas.isEmpty {
            outgoing = ChatMessage(
                role: "user",
                text: MessageQuote.outgoingContent(
                    userText: entry.content, quote: entry.quote,
                    sourceQuote: entry.sourceQuote
                ),
                imageDataURLs: entryImageDatas.map {
                    "data:image/jpeg;base64,\($0.base64EncodedString())"
                }
            )
        }
        return (seedSnapshot, outgoing)
    }

    /// 泵的无工单重组（进程重启后的存量待发/失败条
    /// 目）：与手点重发同一组装口＋载荷回暂存重建
    private func rebuiltSubmitJob(
        thread: ChatThread, entry: ChatEntry
    ) -> SubmitJob {
        let parts = resendJobParts(thread: thread, entry: entry)
        return SubmitJob(
            thread: thread, userEntry: entry,
            text: entry.content,
            filePayloads: resendFilePayloads(entryID: entry.id),
            presetFilePaths: entry.remoteFilePaths,
            seedSnapshot: parts.seedSnapshot,
            context: [parts.outgoing],
            frameStartedAt: nil
        )
    }

    /// 提交泵踢动口：同线程单泵防重入（泵内串行
    /// POST，跨线程各跑各的泵）
    private func kickSubmitPump(thread: ChatThread) {
        guard !appState.isDemo else { return }
        let threadID = thread.id
        guard !submitPumpThreads.contains(threadID)
        else { return }
        submitPumpThreads.insert(threadID)
        submitPumpTasks[threadID] = Task {
            await runSubmitPump(thread: thread)
            submitPumpThreads.remove(threadID)
            submitPumpTasks[threadID] = nil
        }
    }

    /// §451 提交泵（App-1）：逐条按 SubmissionLane
    /// 车道判定取下一条提交，受理即走（不等落定，
    /// 消费环另接）；未受理失败堵泵（严格保序，用
    /// 户 2026-11-24 亲选）——停在失败条上、后续不
    /// 越过，等其自动重试到点（后续触发重跑本泵）
    /// 或用户手点重发解堵；离线折回待发巷同停泵
    /// （网络恢复等触发再跑）
    private func runSubmitPump(thread: ChatThread) async {
        guard appState.config != nil, appState.apiKey != nil
        else { return }
        while !Task.isCancelled {
            surfaceSendingOrphans(in: thread)
            let ledgerIDs = Set(
                appState.runLedger.entries(
                    forThreadID: thread.id
                ).map(\.userEntryID)
            )
            var laneEntries: [SubmissionLane.Entry] = []
            var byID: [UUID: ChatEntry] = [:]
            // 本趟见到的最早退避到期点：泵退出时排唤
            // 醒钟（语义 4——闸与钟同源，B3 关账）
            var earliestBackoff: Date?
            for entry in thread.sortedEntries
            where isOutboxEntry(entry)
                || ledgerIDs.contains(entry.id.uuidString) {
                byID[entry.id] = entry
                let record = appState.outboxRetry.record(
                    for: entry.id
                )
                let policy = OutboxAutoRetryPolicy.decision(
                    state: entry.sendState, record: record,
                    now: Date()
                )
                if case .backoff(let until) = policy {
                    earliestBackoff = min(
                        earliestBackoff ?? until, until
                    )
                }
                let hasLedger = ledgerIDs.contains(
                    entry.id.uuidString
                )
                let failed = entry.sendState == .failed
                    && !hasLedger
                // 准备段条目在退避中（P1-2 记账后）：与
                // 未受理失败同格堵泵等到点——不许被车
                // 道当残影跳过、更不许越过它先发后条
                // （严格保序）；有登记工单（用户编辑重
                // 投/手点）在场时不走此格、走提交格
                let prepInBackoff = !hasLedger && !failed
                    && submitJobs[entry.id] == nil
                    && (entry.sendState == .queued
                        || entry.sendState == .uploading
                        || entry.sendState == .linking)
                    && policy != .autoNow
                    && policy != .manualOnly
                    && policy != .notInQueue
                laneEntries.append(SubmissionLane.Entry(
                    entryID: entry.id,
                    hasLedgerEntry: hasLedger,
                    // 登记工单在场＝用户显式意志（手点
                    // 重发/编辑重投）：压过政策的人工接
                    // 管与成因钉死——否则钉死类成因的
                    // 条目点重发会被车道先堵死、工单永
                    // 不消费（钉测实证的生产缺陷）
                    manualOnly: policy == .manualOnly
                        && submitJobs[entry.id] == nil,
                    unacceptedFailure: failed || prepInBackoff,
                    failureRetryDue: failed
                        && (policy == .autoNow
                            || submitJobs[entry.id] != nil),
                    awaitingSubmission: !hasLedger && !failed
                        && entry.sendState != .sending
                        && entry.sendState != .accepted
                        && (submitJobs[entry.id] != nil
                            || policy == .autoNow)
                ))
            }
            switch SubmissionLane.decision(
                entries: laneEntries
            ) {
            case .submit(let entryID):
                guard let entry = byID[entryID] else { return }
                let registeredJob = submitJobs[entryID]
                let job = registeredJob
                    ?? rebuiltSubmitJob(
                        thread: thread, entry: entry
                    )
                submitJobs[entryID] = nil
                let outcome = await performSubmission(job: job)
                // 自动重投记账（语义 2）：无登记工单的
                // 提交＝策略批准的自动重投，执行完毕才
                // 记一笔（与成因同落——成因已在失败落
                // 点写入）；登记工单（本会话主动发送/
                // 手点重发/编辑重投）不计。离线停泊（没
                // 出门）与停止不计。旧口径执行前记账＋
                // 受理清账，两头夹击把账扫没
                if registeredJob == nil {
                    switch outcome {
                    case .accepted, .rejected, .prepareFailed:
                        appState.outboxRetry.noteAutoAttempt(
                            entryID: entryID, at: Date()
                        )
                    case .offlineParked, .rateLimitedParked,
                         .stopped:
                        break
                    }
                }
                switch outcome {
                case .accepted:
                    // 受理不清账（语义 1）：重试账活到
                    // run 真终态——落定成功在 applySet-
                    // tledTurn 清、落定失败留账钉死。
                    // 旧口径在此整线程扫清非发件箱条目
                    // 的账，是死循环的清账入口之一
                    kickConsumer()
                case .rejected, .prepareFailed,
                     .offlineParked, .rateLimitedParked,
                     .stopped:
                    armOutboxWake(
                        earliestBackoff, threadID: thread.id
                    )
                    return
                }
            case .blocked, .blockedManual, .idle:
                armOutboxWake(
                    earliestBackoff, threadID: thread.id
                )
                return
            }
        }
    }

    /// 退避唤醒钟排布（语义 4）：泵退出时若本线程有
    /// 条目在退避中，把最早到期点排给调度器——到期
    /// 由 scheduleOutboxWake 踢泵续发，不许有闸无钟
    /// 靠下一次偶然触发（B3）
    private func armOutboxWake(
        _ earliestBackoff: Date?, threadID: UUID
    ) {
        guard let earliestBackoff else { return }
        scheduleOutboxWake(at: earliestBackoff, threadID: threadID)
    }

    /// 唤醒调度器：只留最早一记（已有更早的到期点
    /// 在排时不覆盖）；到期先踢本线程提交泵、在看
    /// 线程同走 drain 记账卫生。回前台/网络恢复仍
    /// 是触发源（drain），本钟只补退避/等待门到期
    /// 这一类「时间到了」的事件
    private func scheduleOutboxWake(
        at date: Date, threadID: UUID
    ) {
        if let scheduled = outboxWakeAt, scheduled <= date {
            return
        }
        outboxWakeTask?.cancel()
        outboxWakeAt = date
        outboxWakeTask = Task { @MainActor in
            let delay = date.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            outboxWakeAt = nil
            guard let thread = threads.first(
                where: { $0.id == threadID }
            ) else { return }
            kickSubmitPump(thread: thread)
            if thread.id == currentThreadID {
                drainOutboxIfNeeded()
            }
        }
    }

    /// §451 提交段（泵内单条）：上传待发文件（或沿
    /// 用已落盘远端路径）→ 定发送形态 → POST。失败
    /// 落点与旧 launchTurn 一字同：上传/链接失败
    /// markTurnFailed 原位挂标记（§414 路一）；上传
    /// 进度 UI 只写当前线程（他线程条目后台提交不
    /// 许污染在看线程的占位呈现）
    private func performSubmission(
        job: SubmitJob
    ) async -> SubmissionOutcome {
        let thread = job.thread
        let userEntry = job.userEntry
        pumpInFlightEntryIDs.insert(userEntry.id)
        defer { pumpInFlightEntryIDs.remove(userEntry.id) }
        let showsUploadUI = thread.id == currentThreadID
        var fileServerPaths: [String] = job.presetFilePaths
        if fileServerPaths.isEmpty, !job.filePayloads.isEmpty {
            if showsUploadUI { isUploadingFiles = true }
            userEntry.markSendState(
                .uploading, in: modelContext
            )
            if showsUploadUI { uploadProgressFraction = 0 }
            do {
                fileServerPaths = try await uploadPendingFiles(
                    job.filePayloads
                )
            } catch let failure as FileUploadFailure {
                if showsUploadUI { isUploadingFiles = false }
                markTurnFailed(
                    entry: userEntry,
                    filePayloads: job.filePayloads,
                    failureKind: .prepareFailed
                )
                // 拼接走收尾归一（P2-2）：reason 是服
                // 务端/系统自由文本、自带尾标点时旧拼
                // 法出双句号
                presentSendFailure(
                    kind: .prepareFailed,
                    message: SendFailureCopy.joiningReason(
                        head: "文件「\(failure.fileName)」没能上传，这条还没发出去：",
                        reason: failure.reason,
                        tail: "处理后点这条消息旁的感叹号重新发送。"
                    )
                )
                Haptics.error()
                return .prepareFailed
            } catch is CancellationError {
                if showsUploadUI { isUploadingFiles = false }
                return .stopped
            } catch {
                if showsUploadUI { isUploadingFiles = false }
                // 未知上传异常的文案也走分类（P5-1）：
                // 旧口径一句「文件上传失败…请稍后再
                // 试」包打天下，网络/服务端/解码不分。
                // 成因落账恒 .prepareFailed（语义 3：
                // 准备段失败钉死），分类只供呈现取词
                let presentKind = (error as? HermesError).map {
                    SendFailureKind.classify(submit: $0)
                } ?? .prepareFailed
                markTurnFailed(
                    entry: userEntry,
                    filePayloads: job.filePayloads,
                    failureKind: .prepareFailed
                )
                presentSendFailure(kind: presentKind)
                Haptics.error()
                return .prepareFailed
            }
            if showsUploadUI {
                isUploadingFiles = false
                uploadProgressFraction = nil
            }
            if Task.isCancelled { return .stopped }
            failedFilePayloads[userEntry.id] = nil
            try? stagedSendStore.remove(entryID: userEntry.id)
            userEntry.markSendState(.linking, in: modelContext)
            if !fileServerPaths.isEmpty {
                userEntry.remoteFilePathsData =
                    try? JSONEncoder().encode(fileServerPaths)
                try? modelContext.save()
                for (path, payload) in zip(
                    fileServerPaths, job.filePayloads
                ) {
                    FileMetadataStore.shared.record(
                        path: path,
                        size: Int64(payload.data.count),
                        modifiedAt: nil
                    )
                }
            }
        }
        let shape: (messages: [ChatMessage], sessionID: String?)
        do {
            shape = try await prepareSendShapeWithRetry(
                thread: thread, fullContext: job.context,
                seedEntries: job.seedSnapshot
            )
        } catch is CancellationError {
            return .stopped
        } catch {
            if Task.isCancelled { return .stopped }
            markTurnFailed(
                entry: userEntry, failureKind: .prepareFailed
            )
            // 拼接走收尾归一（P2-1）：userMessage 自
            // 带「。」时旧拼出「请稍后再试。。链接恢
            // 复后…」双句号叠字
            presentSendFailure(
                kind: .prepareFailed,
                message: SendFailureCopy.joiningReason(
                    head: "会话链接失败，这条还没发出去：",
                    reason: (error as? HermesError)?.userMessage
                        ?? "服务端会话建立失败",
                    tail: "链接恢复后，点这条消息旁的感叹号重新发送。"
                )
            )
            Haptics.error()
            return .prepareFailed
        }
        if Task.isCancelled { return .stopped }
        // §135 D 案打点：落盘→链接一段（起点归工单
        // 自带——泵内后条不许借前条的起点串账）
        if let started = job.frameStartedAt {
            ChatDiagTrace.record(
                "发送打点 落盘→链接 "
                    + "\(Int(Date().timeIntervalSince(started) * 1000))ms"
            )
        }
        sendPinToken += 1
        let tail = FileSendAssembly.appendingFileRefs(
            to: shape.messages.last
                ?? ChatMessage(role: "user", content: job.text),
            serverPaths: fileServerPaths
        )
        userEntry.markSendState(.sending, in: modelContext)
        return await performSubmit(
            thread: thread, tail: tail,
            sessionID: shape.sessionID, userEntry: userEntry
        )
    }

    /// §451 POST 提交段：账本先落（runID 后补）、得
    /// 202 即受理——照 driveRun 提交段同口径：瞬态
    /// 有界重试（同 key 重演回原 run）、结果未知归
    /// 对账（账本留席交消费环）、明确拒绝定失败、
    /// 离线折回待发巷。154 幂等键与 driveRun 同铸
    /// 法（ensureIdempotencyKey：条目既有键恒沿用、
    /// 缺时铸造落盘），同条重投恒同 key、不双跑
    private func performSubmit(
        thread: ChatThread, tail: ChatMessage,
        sessionID: String?, userEntry: ChatEntry
    ) async -> SubmissionOutcome {
        guard let config = appState.config,
              let apiKey = appState.apiKey, !apiKey.isEmpty
        else {
            markTurnFailed(
                entry: userEntry, failureKind: .authRejected
            )
            presentSendFailure(kind: .authRejected)
            return .rejected
        }
        let input: RunInput = tail.parts == nil
            ? .text(tail.content) : .message(tail)
        let choice = appState.sessionModelChoice(
            serverSessionID: sessionID, threadID: thread.id
        )
        let idempotencyKey = ensureIdempotencyKey(
            for: userEntry
        )
        appState.runLedger.upsert(RunLedgerEntry(
            threadID: thread.id.uuidString,
            sessionID: sessionID ?? "",
            runID: nil,
            idempotencyKey: idempotencyKey,
            userEntryID: userEntry.id.uuidString,
            submittedAt: Date()
        ))
        var attempt = 0
        var unknownAttempts = 0
        var gateWaits = 0
        while true {
            attempt += 1
            do {
                let response = try await appState.client
                    .submitRun(
                        config: config, apiKey: apiKey,
                        sessionID: sessionID ?? "",
                        input: input, model: choice.model,
                        provider: choice.providerField,
                        idempotencyKey: idempotencyKey
                    )
                appState.runLedger.upsert(RunLedgerEntry(
                    threadID: thread.id.uuidString,
                    sessionID: sessionID ?? "",
                    runID: response.runID,
                    idempotencyKey: idempotencyKey,
                    userEntryID: userEntry.id.uuidString,
                    submittedAt: Date()
                ))
                markAcceptedEntryAccepted(
                    thread: thread,
                    userEntryID: userEntry.id.uuidString
                )
                clearPendingDeliveryMark(entry: userEntry)
                return .accepted
            } catch let submitError {
                if Task.isCancelled {
                    markLedgerStopRequested(
                        userEntryID: userEntry.id
                    )
                    return .stopped
                }
                // 限流等待门（语义 3）：服务端明示等
                // 多久就等多久——不落失败、不计账；门
                // 内等满两轮仍被限，折回待发停泊＋排
                // 唤醒钟，到点自动续（仍不是失败）
                if let hermesError = submitError as? HermesError,
                   case .rateLimited(let retryAfter) = hermesError {
                    if gateWaits < 2 {
                        gateWaits += 1
                        try? await Task.sleep(
                            for: .seconds(min(retryAfter ?? 1, 30))
                        )
                        if Task.isCancelled {
                            markLedgerStopRequested(
                                userEntryID: userEntry.id
                            )
                            return .stopped
                        }
                        continue
                    }
                    appState.runLedger.remove(
                        userEntryID: userEntry.id
                    )
                    userEntry.markPendingSend(
                        in: modelContext
                    )
                    scheduleOutboxWake(
                        at: Date().addingTimeInterval(
                            min(retryAfter ?? 1, 300)
                        ),
                        threadID: thread.id
                    )
                    return .rateLimitedParked
                }
                switch RunSubmitRetry.classify(submitError) {
                case .notSentOffline:
                    appState.runLedger.remove(
                        userEntryID: userEntry.id
                    )
                    userEntry.markPendingSend(
                        in: modelContext
                    )
                    return .offlineParked
                case .transient:
                    if attempt
                        <= RunSubmitRetry.maxTransientRetries {
                        // 间隔走 RetryBackoff 同源退避＋
                        // 全抖动（P1-1）：旧固定 1.2s 无抖
                        // 动，多条同拍重撞
                        try? await Task.sleep(
                            for: .seconds(RetryBackoff.delay(
                                afterFailure: attempt,
                                jitterUnit: Double.random(
                                    in: 0...1
                                )
                            ))
                        )
                        if Task.isCancelled {
                            markLedgerStopRequested(
                                userEntryID: userEntry.id
                            )
                            return .stopped
                        }
                        continue
                    }
                    // 瞬态耗尽：结果未知——账本留席、待
                    // 发标记清，消费环对账同 key 重演取
                    // 回（不定性为错误、不双跑）
                    clearPendingDeliveryMark(entry: userEntry)
                    return .accepted
                case .unknown:
                    // 判不出成因（P1-1）：只许再试 1
                    // 次，耗尽同走结果未知交对账——旧
                    // 口径非 HermesError 一律判瞬态全额
                    // 重试，把未知错误当网络抖动
                    unknownAttempts += 1
                    if unknownAttempts
                        <= RunSubmitRetry.maxUnknownRetries {
                        try? await Task.sleep(
                            for: .seconds(RetryBackoff.delay(
                                afterFailure: unknownAttempts,
                                jitterUnit: Double.random(
                                    in: 0...1
                                )
                            ))
                        )
                        if Task.isCancelled {
                            markLedgerStopRequested(
                                userEntryID: userEntry.id
                            )
                            return .stopped
                        }
                        continue
                    }
                    clearPendingDeliveryMark(entry: userEntry)
                    return .accepted
                case .rejected:
                    appState.runLedger.remove(
                        userEntryID: userEntry.id
                    )
                    let hermesError =
                        (submitError as? HermesError)
                        ?? .unreachable(
                            submitError.localizedDescription
                        )
                    if hermesError.isSessionNotFound {
                        // 会话已在服务端消失（§223）：按
                        // 凭据面收口呈现，成因记 auth
                        markTurnFailed(
                            entry: userEntry,
                            failureKind: .authRejected
                        )
                        presentSendFailure(kind: .authRejected)
                    } else {
                        // 成因落账＋分类呈现（语义 3/5）：
                        // 旧口径落 .failed 时成因只剩一句
                        // 兜底文案，政策无从分档
                        let kind = SendFailureKind.classify(
                            submit: hermesError
                        )
                        markTurnFailed(
                            entry: userEntry, failureKind: kind
                        )
                        presentSendFailure(
                            kind: kind,
                            detail: hermesError.diagnosticDetail
                        )
                    }
                    return .rejected
                }
            }
        }
    }

    /// 154 幂等键铸法（与 driveRun 同口径单源）：条
    /// 目 clientMessageID 在席恒沿用，缺时铸造并落
    /// 盘——首投/自动重试/手点重发/中段原位重发跨
    /// 链恒同 key
    private func ensureIdempotencyKey(
        for userEntry: ChatEntry
    ) -> String {
        if let existing = userEntry.clientMessageID {
            return existing
        }
        let minted = UUID().uuidString
        userEntry.clientMessageID = minted
        try? modelContext.save()
        return minted
    }

    /// 受理同点清待发标记（driveRun 旧口径：非失败
    /// 出口 deliveryState 清零，条目出待发巷）
    private func clearPendingDeliveryMark(
        entry: ChatEntry
    ) {
        if entry.deliveryState != nil {
            entry.deliveryState = nil
            try? modelContext.save()
        }
    }

    /// 提交窗内停止：账本本条记停止意图，消费环接
    /// 管后对账先行真停止（driveRun 旧口径同）
    private func markLedgerStopRequested(
        userEntryID: UUID
    ) {
        guard var ledgerEntry = appState.runLedger.entry(
            forUserEntryID: userEntryID
        ) else { return }
        ledgerEntry.stopRequested = true
        appState.runLedger.upsert(ledgerEntry)
    }

    /// 消费环踢动口：单例防重入
    private func kickConsumer() {
        guard !appState.isDemo, consumeTask == nil
        else { return }
        consumeTask = Task {
            await runConsumerLoop()
            consumeTask = nil
        }
    }

    /// §451 消费环（App-3）：当前线程已受理未落定
    /// 轮次按提交序逐轮驱动——一轮落定才接下一轮
    /// （streamAssembler/轮次状态机单轮假设不动）。
    /// 驱动后本条仍在账（对账预算耗尽未落定）即停
    /// 环：留待回前台/进线程的 resumeRunIfNeeded
    /// 续，不许空转重试
    private func runConsumerLoop() async {
        while !Task.isCancelled {
            guard scenePhase == .active,
                  let thread = currentThread,
                  let head = appState.runLedger.entries(
                      forThreadID: thread.id
                  ).first
            else { return }
            await driveAcceptedTurn(
                thread: thread, entry: head
            )
            if let uid = UUID(uuidString: head.userEntryID),
               appState.runLedger.entry(
                   forUserEntryID: uid
               ) != nil {
                return
            }
        }
    }

    /// §451 单轮驱动：已受理一轮的呈现重置＋半截回
    /// 填＋对账落定——本体即原 resumeRunIfNeeded 的
    /// 驱动段（参数化出账本条目），恢复与消费环共
    /// 用一份，不许两处分叉
    private func driveAcceptedTurn(
        thread: ChatThread, entry: RunLedgerEntry
    ) async {
        runMachine = RunTurnStateMachine()
        if entry.runID != nil {
            runMachine.apply(.submitAccepted)
            // §426（缺陷一）：runID 在上一进程生命
            // 周期已确立＝服务器早已确认收到——恢
            // 复同点补记送达，不许条目在本进程里继
            // 续挂未确认态
            markAcceptedEntryAccepted(
                thread: thread,
                userEntryID: entry.userEntryID
            )
            runMachine.apply(.streamLost)
        } else {
            runMachine.apply(.submitAmbiguous)
        }
        if entry.stopRequested {
            runMachine.apply(.stopRequested)
        }
        activeRunThreadID = thread.id
        lastEventSeq = -1
        terminalOutputHint = nil
        terminalStatusHint = nil
        streamAssembler.reset()
        reasoningPublishGate.reset()
        resetStreamPresentation()
        reasoningStartedAt = nil
        // 半截呈现回填：上次落盘的本轮条目即当前可见
        // 内容（落定时以 transcript 整段替换）
        liveToolCards = []
        liveOrder = []
        livePartialEntryIDs = []
        if let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) {
            // §123（H1）：回响条目（echoKey 非空）不是
            // 本轮半截——不进半截名单、正文回填也不许
            // 把它当作助手半截正文吞进流式区
            // §165：审批锚定条目同族同守（谓词统一）
            // §414：候选面收口到 turnPartialCandidates
            // ——补待发豁免（账本滞留期落位的待发条目
            // 不许被当作本轮半截吞掉/删掉）与下一轮界
            // （中段重发轮之后已落定轮次不进半截名单）
            let partials = Self.turnPartialCandidates(
                in: thread, userEntry: userEntry
            )
            livePartialEntryIDs = partials.map(\.id)
            liveToolCards = partials
                .filter { $0.role == "tool" }
                .compactMap(\.toolCard)
            // 第 93 条：半截按段回填——落盘条目按时
            // 序走查，工具卡与助理段各自归位重建事件
            // 序；时序最末一条若是助理段，它就是断线
            // 时打开着的段（重挂后的增量只许拼进它），
            // 其余助理段一律封存只读。旧形态只取最末
            // 一段正文吞回单一缓冲：多段半截的前段就
            // 此从呈现消失、且与打开段混存。旧版落盘
            // 的单条合并半截（一段到底）在此即整条作
            // 打开段，行为与旧形态一致
            let ordered = partials.sorted {
                $0.createdAt < $1.createdAt
            }
            let openEntryID = ordered.last?.id
            var sealedTexts: [String] = []
            var openText = ""
            var rebuiltOrder: [LiveOrderItem] = []
            for partial in ordered {
                if partial.role == "tool",
                   let card = partial.toolCard {
                    rebuiltOrder.append(.tool(card.id))
                } else if partial.role == "assistant",
                          !partial.content.isEmpty {
                    if partial.id == openEntryID {
                        openText = partial.content
                        rebuiltOrder.append(.text)
                    } else {
                        rebuiltOrder.append(
                            .sealedText(sealedTexts.count)
                        )
                        sealedTexts.append(partial.content)
                    }
                }
            }
            if !rebuiltOrder.contains(.text) {
                rebuiltOrder.append(.text)
            }
            streamAssembler.restore(
                sealed: sealedTexts, current: openText
            )
            liveOrder = rebuiltOrder
            streamingText = ""
        } else {
            streamingText = ""
            // 0.36.10：无半截可回填时事件序仍立正文位
            // （卡列恒空、只剩 .text 一记）
            liveOrder = [.text]
        }
        // §385（总表 163）：续接在跑的一轮同起实时
        // 活动，落定即收（与 driveRun 同口径）
        await RunLiveActivityCenter.shared.begin(
            taskName: thread.title
        )
        isDrivingRun = true
        var mutableEntry = entry
        await reconcileRun(
            thread: thread, entry: &mutableEntry,
            demoMode: false
        )
        isDrivingRun = false
        await RunLiveActivityCenter.shared.end()
        // 发送失败机制包（语义 4）：对账收尾的全
        // 量 drain 删除（触发源收敛），只留定向踢
        // 泵一脚——泵已退出时排进来的条目要等本轮
        // 落定才成车道头条，没有这一脚只能等无关
        // 的外部事件。这一脚不可能自激成环：落定
        // 失败的头条在新记账口径下被车道堵住等手
        // 点（准入看成因＋退避带钟），踢泵只让车道
        // 重新判定一次、不会把失败条重投出去（死
        // 循环的必要条件是清账重置、已在语义 1/2
        // 切断；钉测 ChatFailKeepPinTests 钉此面）
        kickSubmitPump(thread: thread)
    }

    /// §451（App-4）落定锚解析：条目已钉 server-
    /// RowID 直用；未钉（本进程新发条目落定前恒未
    /// 钉）走 Core 配对图按本地序位查（与落定补缺
    /// 同一配对、判同口径单源）。解析不到回 nil，
    /// 由 settleRunFromTranscript 按在账轮数裁决
    /// （多轮并存时不许走无锚口径）
    private func transcriptAnchorRowID(
        thread: ChatThread, entry: RunLedgerEntry,
        messages: [SessionMessage]
    ) -> Int? {
        guard let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) else { return nil }
        if let pinned = userEntry.serverRowID {
            return pinned
        }
        let localUsers = thread.entries.filter {
            $0.role == "user"
        }
        guard let position = localUsers.firstIndex(
            where: { $0.id == userEntry.id }
        ) else { return nil }
        let pairs = RunTranscriptSettle.pairedRowIDs(
            messages: messages,
            localUserEntries: localUsers.map {
                (content: $0.content,
                 createdAt: $0.createdAt,
                 filePaths: $0.remoteFilePaths,
                 imagePaths: $0.remoteImagePaths)
            }
        )
        return pairs[position]
    }

    /// §451（App-6）：已受理未执行谓词——账本在
    /// 席、有 runID、且不是本线程最早未落定条（队
    /// 首可能已在服务端执行中、撤它走停止语义；非
    /// 队首必在服务端 FIFO 里排队未开轮）。消费环
    /// 恒驱动队首，谓词与驱动天然互斥
    private func acceptedWithdrawAvailable(
        for entry: ChatEntry
    ) -> Bool {
        guard entry.role == "user",
              let thread = entry.thread,
              let ledgerEntry = appState.runLedger.entry(
                  forUserEntryID: entry.id
              ),
              ledgerEntry.runID != nil,
              let head = appState.runLedger.entries(
                  forThreadID: thread.id
              ).first,
              head.userEntryID != entry.id.uuidString
        else { return false }
        return true
    }

    /// §451（App-6）撤回已受理未执行条目：服务端
    /// stop（排队中的 admission 走 cancel_queued、
    /// 不会开轮）→ 摘本轮账本 → 删本地条目＋清暂
    /// 存/重试记账（与 withdrawUnsentEntry 同尾）。
    /// 极小竞态下若已开轮，stop 即中断该轮、其服
    /// 务端行按既有补缺口径回补呈现，本动作的保证
    /// 是「不再继续执行」
    private func withdrawAcceptedEntry(_ entry: ChatEntry) {
        guard acceptedWithdrawAvailable(for: entry),
              let thread = entry.thread,
              let ledgerEntry = appState.runLedger.entry(
                  forUserEntryID: entry.id
              ),
              let runID = ledgerEntry.runID,
              let config = appState.config,
              let apiKey = appState.apiKey
        else { return }
        let entryID = entry.id
        Task {
            try? await appState.client.stopRun(
                config: config, apiKey: apiKey, runID: runID
            )
        }
        appState.runLedger.remove(userEntryID: entryID)
        if unsentEditTargetID == entryID {
            unsentEditTargetID = nil
            unsentEditFilesRepresented = false
        }
        failedFilePayloads[entryID] = nil
        pendingResendAttachments[entryID] = nil
        try? stagedSendStore.remove(entryID: entryID)
        appState.outboxRetry.clear(entryID: entryID)
        modelContext.delete(entry)
        try? modelContext.save()
        kickSubmitPump(thread: thread)
        kickConsumer()
    }

    /// 发件箱触发口（台账 154／G-04）：回前台/网络
    /// 恢复/切线程/进页四处同调本口。§451 起 drain
    /// 退役投递职责（旧 drainOutboxLoop 的串行派发
    /// 整条删除）——本口只剩记账卫生＋踢提交泵/消
    /// 费环：投递归泵（落盘即提交、严格保序）、已
    /// 受理轮次的驱动归消费环；连接配置缺失时不踢
    /// （没连上时尝试只会白烧重试次数）
    private func drainOutboxIfNeeded() {
        guard !appState.isDemo,
              appState.config != nil, appState.apiKey != nil,
              let thread = currentThread
        else { return }
        outboxHousekeeping(in: thread)
        kickSubmitPump(thread: thread)
        kickConsumer()
    }

    /// 记账卫生（原 drain 趟首两件）：只清条目已不
    /// 存在的残账。
    /// 发送失败机制包（语义 1）：旧第二件「已落定
    /// 条目的旧重试账同清」（clearDeliveredOutbox-
    /// Records）整体退役——它按 !isOutboxEntry 在
    /// 受理后立刻把在飞条目的账扫掉，是 B1 清账错
    /// 位与死循环的一环；清账点全集只剩三处：落
    /// 定成功（applySettledTurn 按条）、用户撤
    /// 回、编辑重投
    private func outboxHousekeeping(in thread: ChatThread) {
        let validIDs = Set(
            threads.flatMap {
                $0.entries.map { $0.id.uuidString }
            }
        )
        appState.outboxRetry.prune(validEntryIDs: validIDs)
    }

    /// 提交段孤儿浮现（DESIGN §336）：状态 sending
    /// 但 run 账本无此轮的条目——落账与提交之间极
    /// 小窗口内进程身亡所致，服务端是否受理不可
    /// 知。处置只两步：折回待发巷让它可见（未发送
    /// 行）、打人工接管标记让自动链永不重发它，
    /// 是否重发由用户看内容裁决。有账本在飞或正
    /// 在驱动的 sending 不在此列（对账链管辖）
    private func surfaceSendingOrphans(in thread: ChatThread) {
        for entry in thread.sortedEntries
        where entry.sendState == .sending
            && !entry.sendFailed && !entry.isPendingSend {
            // §451：逐条核账——本条有账本＝对账链管
            // 辖（多轮并存后「整线程账本为空＋无流在
            // 跑」的旧守卫作废：别的轮次在飞不该把本
            // 条的孤儿身份藏起来）；泵正在提交本条
            // （.sending 已写、账本未落的瞬时窗）同
            // 跳过
            if appState.runLedger.entry(
                forUserEntryID: entry.id
            ) != nil { continue }
            if pumpInFlightEntryIDs.contains(entry.id) {
                continue
            }
            entry.markPendingSend(in: modelContext)
            appState.outboxRetry.markManualOnly(
                entryID: entry.id
            )
        }
    }

    /// 待发文件逐个上传（0.36.29，件四）：顺序即待
    /// 发顺序（@file 拼装顺序从它）；逐个经 9119
    /// 文件通道写 attachments/<文件名>（overwrite
    /// 覆盖同名）、取回执绝对路径；任一失败或回执
    /// 无落点即抛 FileUploadFailure 点名该文件——
    /// 整条拦下在 send 侧，不在此处吞单个文件。
    /// 服务端 attachments/ 副本无自动过期，本轮只
    /// 记账不做清理策略（契约报告边界口径）
    private func uploadPendingFiles(
        _ payloads: [(name: String, data: Data)]
    ) async throws -> [String] {
        // §237 P7：进度聚合按原始字节计（data_url 在
        // 客户端内的比例与原始字节同比例放大、比值
        // 不变）；tracker 线程安全，URLSession 回调
        // 队列直接写、呈现读聚合值。401 重登整传重试
        // 时单文件比例会从 0 重报，聚合峰值口径保证
        // 界面百分比不倒退
        let tracker = UploadProgressTracker(
            fileSizes: payloads.map(\.data.count)
        )
        var paths: [String] = []
        for payload in payloads {
            tracker.beginFile(size: payload.data.count)
            let receipt: ManagedFileUploadReceipt
            do {
                receipt = try await appState.performAdmin {
                    client, cfg in
                    // §410：只递原始字节——data_url 与请
                    // 求体组包在客户端内后台完成（流式写
                    // 临时文件），主 actor 不再同步付
                    // base64＋JSON 体的成形成本与内存峰值
                    try await client.uploadAttachment(
                        config: cfg,
                        path: FileSendAssembly.uploadPath(
                            fileName: payload.name
                        ),
                        fileName: payload.name,
                        data: payload.data,
                        onProgress: { fileFraction in
                            let aggregate = tracker
                                .updateCurrentFile(
                                    fraction: fileFraction
                                )
                            Task { @MainActor in
                                uploadProgressFraction = aggregate
                            }
                        }
                    )
                }
            } catch let error as HermesError {
                throw FileUploadFailure(
                    fileName: payload.name,
                    reason: error.userMessage
                )
            }
            tracker.finishCurrentFile()
            uploadProgressFraction = tracker.fractionCompleted
            guard let serverPath = receipt.serverPath else {
                throw FileUploadFailure(
                    fileName: payload.name,
                    reason: "服务端没有返回文件落点。"
                )
            }
            paths.append(serverPath)
        }
        return paths
    }

    /// 本轮出门形态（0.27.0 重写，状态机见 OneDayCore
    /// .SideChatLink）：全线程同口径两路——
    /// ①已链接（绑定非桶＋种子已落；主线的绑定/种
    ///   子位读 SideChatStore 双位）：会话模式——载
    ///   荷只取尾条＋会话头；旁聊锁模型与胶囊不一致
    ///   （且锁为我方所设）时先推一次会话内切换（尽
    ///   力而为：失败不挡发送、下轮再试——该端点的
    ///   公网送达缺口登记于 §54，属已知残留）；
    /// ②未链接：先走 performLink（建会话或 import
    ///   种子，seedEntries 为本轮条目落盘前的快照）
    ///   ——成功落绑定/种子位/锁模型、失败计数清零，
    ///   本轮随即以会话模式发出；**失败抛错整轮不
    ///   发**（0.21.0 的「失败回退无状态重放」整类
    ///   删除：无头发送在服务端按开头合并落库、是
    ///   串话入口，诊断档判死）；失败计数＋1、原因
    ///   留痕（旁聊落线程、主线落 SideChatStore）由
    ///   本函数记账，呈现与条目回滚在 send() 的
    ///   catch。用户在链接窗口内主动停止抛
    ///   CancellationError、不留痕（send 按停止语义
    ///   静默收尾）。
    /// 发送链接步退避重试（0.36.20，§86.3，治审计
    /// R2）：prepareSendShape 此前单发无重试——点发送
    /// 撞上瞬断即整轮不发＋弹横幅，是全发送链重试覆盖
    /// 最薄一环。本包装只对瞬断类失败（HermesError.
    /// isTransient，既有失败分型）做有界退避重试：总
    /// 尝试与提交步同量级（Core RetryBackoff.max-
    /// Attempts＝首发＋2 次）、全抖动退避同源；鉴权/
    /// 业务失败不重试、原样上抛走既有失败分支。重试
    /// 期间不产任何新文案（§86.5 呈现一档：静默期），
    /// 耗尽后才由调用方既有分支出失败横幅——本条消息
    /// 从未进入提交步，「未发送」口径属实。重试语义与
    /// 用户手动重按发送完全一致（主线是 ensure 幂等；
    /// 旁聊每次尝试内现铸定 id，极端时序下可能在服务
    /// 端多留一个空会话——无消息落入、与手按重发同
    /// 性质，不为此另造跨尝试 id 托管）
    private func prepareSendShapeWithRetry(
        thread: ChatThread, fullContext: [ChatMessage],
        seedEntries: [SeedEntry]
    ) async throws -> (messages: [ChatMessage], sessionID: String?) {
        var attempts = 0
        while true {
            attempts += 1
            do {
                return try await prepareSendShape(
                    thread: thread, fullContext: fullContext,
                    seedEntries: seedEntries
                )
            } catch let error as HermesError {
                if Task.isCancelled {
                    throw CancellationError()
                }
                guard error.isTransient,
                      RetryBackoff.shouldRetry(afterAttempts: attempts)
                else { throw error }
                let wait = RetryBackoff.delay(
                    afterFailure: attempts,
                    jitterUnit: Double.random(in: 0...1)
                )
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                if Task.isCancelled {
                    throw CancellationError()
                }
            }
        }
    }

    private func prepareSendShape(
        thread: ChatThread, fullContext: [ChatMessage],
        seedEntries: [SeedEntry]
    ) async throws -> (messages: [ChatMessage], sessionID: String?) {
        let store = appState.sessionLedger
        let isMain = thread.id == store.mainThreadID
        // §331 改判：计划只看绑定 id（主线代入钦定
        // id）——种子位退出判据：自有会话种子未落也
        // 直发、种子转后台义务（欠账在本分支顺带排
        // 调度，不拦本轮）；id 未知才走建立路
        let plan = isMain
            ? SideChatLink.sendPlan(
                serverSessionID: store.mainServerSessionID
            )
            : SideChatLink.sendPlan(
                serverSessionID: thread.serverSessionID
            )
        switch plan {
        case .session(let sessionID):
            if isMain {
                scheduleMainBackgroundSync()
            }
            if !isMain, SideChatLink.needsModelRelock(
                linkedModel: thread.linkedModel,
                capsuleModel: appState.chatModel(
                    serverSessionID: thread.serverSessionID,
                    threadID: thread.id
                )
            ) {
                let capsule = appState.chatModel(
                    serverSessionID: thread.serverSessionID,
                    threadID: thread.id
                )
                var pushed = false
                do {
                    try await appState
                        .performAdmin { client, config in
                            try await client
                                .updateServerSessionModel(
                                    config: config, id: sessionID,
                                    model: capsule
                                )
                        }
                    pushed = true
                } catch {
                    pushed = false
                }
                if pushed {
                    thread.linkedModel = capsule
                    try? modelContext.save()
                }
            }
            if !isMain {
                // §331：种子/回补欠账顺带排后台（防重
                // 入在调度器；本轮发送不等待、不受其
                // 成败影响）；旧账先派生再判欠账
                deriveLegacySeedObligation(thread)
                if thread.seedSyncState.needsSyncAttempt {
                    scheduleSeedSync(
                        thread: thread, seedSnapshot: seedEntries
                    )
                }
                if thread.historyUnsynced {
                    scheduleHistoryBackfillIfNeeded(thread: thread)
                }
            }
            return (
                SideChatLink.payload(
                    plan: plan, fullContext: fullContext
                ),
                sessionID
            )
        case .linkAndSeed:
            do {
                let linkedID: String
                if isMain {
                    guard await ensureMainLink(
                        seedSnapshot: seedEntries
                    ) else {
                        throw HermesError.unreachable(
                            store.mainLinkLastError
                                ?? "主线会话链接失败"
                        )
                    }
                    linkedID = store.ensureMainServerSessionID()
                } else {
                    // 目标 id：已存自有 id 沿用，其余（无
                    // 绑定/绑合并桶/绑他方会话待解绑）一
                    // 律新铸——合并桶绑定在此被自有 id
                    // 覆盖、桶本体零动作
                    let desiredID = thread.serverSessionID
                        .flatMap {
                            SideChatLink.isOwnSessionID($0)
                                ? $0 : nil
                        } ?? SideChatLink.newSessionID()
                    let linkModel = appState.chatModel(
                        serverSessionID: desiredID,
                        threadID: thread.id
                    )
                    do {
                        let outcome = try await performLink(
                            desiredID: desiredID, title: nil,
                            model: linkModel,
                            seedEntries: seedEntries
                        )
                        linkedID = outcome.sessionID
                        applySeedOutcome(
                            outcome, to: thread, seed: seedEntries
                        )
                    } catch let linkError {
                        // §331 探针恢复：链接多半死在种
                        // 子导入一步——回读确认锚点在
                        // （或空建保住存在性）即按已链
                        // 发送，种子转待导入由后台补；
                        // 探针也失败才按原错误整轮不发
                        guard let recoveredID =
                            await recoverLinkByProbe(
                                desiredID: desiredID, title: nil,
                                model: linkModel
                            )
                        else { throw linkError }
                        linkedID = recoveredID
                        thread.seedSyncState = SideChatLink
                            .seedTranscript(from: seedEntries).isEmpty
                            ? .notOwed : .pending
                    }
                    thread.serverSessionID = linkedID
                    thread.linkedModel = appState.chatModel(
                        serverSessionID: linkedID, threadID: thread.id
                    )
                    thread.linkFailureCount = 0
                    thread.linkLastError = nil
                    try? modelContext.save()
                    if thread.seedSyncState.needsSyncAttempt {
                        scheduleSeedSync(
                            thread: thread, seedSnapshot: seedEntries
                        )
                    }
                }
                return (
                    SideChatLink.payload(
                        plan: .session(sessionID: linkedID),
                        fullContext: fullContext
                    ),
                    linkedID
                )
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                if !isMain {
                    thread.linkFailureCount = SideChatLink
                        .failureCount(
                            afterFailure: thread.linkFailureCount
                        )
                    thread.linkLastError =
                        (error as? HermesError)?.userMessage
                        ?? "建会话失败"
                    try? modelContext.save()
                }
                throw error
            }
        }
    }

    /// 演示模式：种子对话的最后一句用户消息由假客户端
    /// 的 run 通道回完（0.31.0：演示也走 run 驱动——假
    /// 客户端 submitRun/runEvents 产定稿回复，落定走
    /// 状态 output 合成路径，不碰账本与 transcript）。
    /// 正常模式直接返回，零影响。
    private func startDemoStreamIfNeeded() async {
        guard DemoMode.current.isDemo, !demoStreamStarted else {
            return
        }
        // 演示流稳健性（DESIGN-V4 §11.6 历史）：等待改有界
        // 长预算（线程与连接态齐备才开流，上限 20s），演示
        // 专用路径，正常模式第一行已返回
        for _ in 0..<80 where currentThread == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let thread = currentThread else {
            return
        }
        demoStreamStarted = true
        // 等种子渲染落稳再开流，截图窗口对齐流式中段
        try? await Task.sleep(for: .seconds(1))
        guard let userEntry = thread.sortedEntries
            .last(where: { $0.role == "user" }) else { return }
        streamingText = ""
        await driveRun(
            thread: thread,
            tail: ChatMessage(role: "user", content: userEntry.content),
            sessionID: nil, userEntry: userEntry, demoMode: true
        )
    }

    // MARK: - Run 驱动（0.31.0，任务制生成）

    /// 一轮 run 的全程驱动：提交（Idempotency-Key 同
    /// key 重演兜底）→ events 订阅呈现 → 断线转对账
    /// （状态轮询＋events 重挂＋transcript 落定）。旧
    /// runStream（chat completions 单连接流）与 0.20.0
    /// 的对账恢复（删半截以原上下文自动重发）整类退
    /// 役：生成与连接分家后，断线只是「结果未知」，
    /// 永不映射网络错误、永不自动重发（§58 铁律）。
    private func driveRun(
        thread: ChatThread, tail: ChatMessage,
        sessionID: String?, userEntry: ChatEntry,
        demoMode: Bool = false
    ) async {
        guard let config = appState.config,
              let apiKey = appState.apiKey else {
            streamingText = nil
            resetStreamPresentation()
            reasoningStartedAt = nil
            presentSendFailure(kind: .authRejected)
            // 基础止血包（P1）：连接态缺失同样是本轮
            // 失败——条目留痕挂标记，恢复连接后点标
            // 记重发（演示态不挂，种子条目不是用户真
            // 发送）
            if !demoMode {
                markTurnFailed(
                    entry: userEntry, failureKind: .authRejected
                )
            }
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
            sendTask = nil
            return
        }
        isDrivingRun = true
        // §385（总表 163）：实时活动随一轮起落——起
        // 跑沿启动、退出沿（defer 覆盖失败/取消一切
        // 出口）收
        await RunLiveActivityCenter.shared.begin(
            taskName: thread.title
        )
        defer {
            isDrivingRun = false
            Task { await RunLiveActivityCenter.shared.end() }
        }
        runMachine = RunTurnStateMachine()
        activeRunThreadID = thread.id
        lastEventSeq = -1
        livePartialEntryIDs = []
        terminalOutputHint = nil
        terminalStatusHint = nil
        streamAssembler.reset()
        reasoningPublishGate.reset()
        resetStreamPresentation()
        // §494：直播行只在新发轮武装（恢复轮走
        // resumeActiveRun、不经此点）
        streamPresentationArmed = true
        reasoningStartedAt = nil
        // 输入组装：尾条纯文本走字符串形态、多模态走
        // 单元素消息形态（探针实测两形态均成立）
        let input: RunInput = tail.parts == nil
            ? .text(tail.content) : .message(tail)
        let choice = appState.sessionModelChoice(
            serverSessionID: sessionID, threadID: thread.id
        )
        let provider = choice.providerField
        // 台账 154（DESIGN §383）：消息级幂等身份——
        // 账本幂等键自此取条目的 clientMessageID：首
        // 轮铸造并落盘，之后发件箱自动重试/手点重发/
        // 中段原位重发（§414）跨 driveRun 复用同一
        // id，服务
        // 端按此 id 回原 run（hermes-deploy 1.5.0 的
        // client_message_id 语义，头＋body 同值双带）；
        // 单轮内账本重演口径不变。demo 无服务端、键
        // 只在内存账本里用，仍现铸不落盘。
        let idempotencyKey: String
        if demoMode {
            idempotencyKey = UUID().uuidString
        } else if let existing = userEntry.clientMessageID {
            idempotencyKey = existing
        } else {
            idempotencyKey = UUID().uuidString
            userEntry.clientMessageID = idempotencyKey
            try? modelContext.save()
        }
        var ledgerEntry = RunLedgerEntry(
            threadID: thread.id.uuidString,
            sessionID: sessionID ?? "",
            runID: nil,
            idempotencyKey: idempotencyKey,
            userEntryID: userEntry.id.uuidString,
            submittedAt: Date()
        )
        if !demoMode {
            // 提交前先落账：进程在此后任何时点被杀，回
            // 来靠账本＋同 key 重演取回本轮（不双跑）
            appState.runLedger.upsert(ledgerEntry)
        }
        // 提交：瞬断同 key 重试至多两次（受理回执丢失
        // 时重演回原 run）；明确拒绝才是真失败；耗尽
        // 仍不明＝结果未知，进对账不定性为错误
        var submitError: HermesError?
        var attempts = 0
        var gateWaits = 0
        while true {
            do {
                let response = try await appState.client.submitRun(
                    config: config, apiKey: apiKey,
                    sessionID: sessionID ?? "",
                    input: input, model: choice.model,
                    provider: provider,
                    idempotencyKey: ledgerEntry.idempotencyKey
                )
                ledgerEntry.runID = response.runID
                if !demoMode {
                    appState.runLedger.upsert(ledgerEntry)
                }
                runMachine.apply(.submitAccepted)
                if !demoMode {
                    markAcceptedEntryAccepted(
                        thread: thread,
                        userEntryID: userEntry.id.uuidString
                    )
                }
                submitError = nil
                break
            } catch let error as HermesError {
                if Task.isCancelled {
                    // 提交窗口内被停止：账本留停止意图、
                    // 本地静默收尾；下次进本线程时对账链
                    // 重演取回 run 并真停止（resumeRun-
                    // IfNeeded），不在此处假装已取消
                    ledgerEntry.stopRequested = true
                    if !demoMode {
                        appState.runLedger.upsert(ledgerEntry)
                    }
                    runMachine.apply(.stopRequested)
                    finishRunPresentation(failed: false)
                    return
                }
                if case .notSentOffline = error {
                    // §414 增补（断网规格 5.2）：设备明
                    // 确无网、请求根本没出设备——不是
                    // 结果未知：不重试、不判 ambiguous、
                    // 不进对账。折回待发巷（待发标记＋
                    // queued 态、mayAutoResume）、清账
                    // 本、收尾呈现（占位行随 sendTask
                    // 收尾撤）；网络恢复/回前台后由发
                    // 件箱 drain 自动续发（同 key 幂等
                    // 不变）。真未知（回执丢失）仍走下
                    // 方瞬态重试→ambiguous→对账全套，
                    // 154 幂等本体不动
                    if !demoMode {
                        appState.runLedger.remove(
                            threadID: thread.id
                        )
                        userEntry.markPendingSend(
                            in: modelContext
                        )
                    }
                    finishRunPresentation(failed: false)
                    return
                }
                if case .rateLimited(let retryAfter) = error,
                   gateWaits < 2 {
                    // 限流等待门（语义 3，与提交泵同
                    // 规）：按服务端等待值等、不落失
                    // 败；等满两轮仍被限才落下方拒绝
                    // 收口（成因 .rateLimited 钉死）
                    gateWaits += 1
                    try? await Task.sleep(
                        for: .seconds(min(retryAfter ?? 1, 30))
                    )
                    if Task.isCancelled {
                        ledgerEntry.stopRequested = true
                        if !demoMode {
                            appState.runLedger.upsert(ledgerEntry)
                        }
                        runMachine.apply(.stopRequested)
                        finishRunPresentation(failed: false)
                        return
                    }
                    continue
                }
                if error.isTransient, attempts < 2 {
                    attempts += 1
                    // 间隔走 RetryBackoff 同源退避
                    // （P1-1，与提交泵同口径）
                    try? await Task.sleep(
                        for: .seconds(RetryBackoff.delay(
                            afterFailure: attempts,
                            jitterUnit: Double.random(in: 0...1)
                        ))
                    )
                    continue
                }
                submitError = error
                runMachine.apply(
                    error.isTransient
                        ? .submitAmbiguous : .submitRejected
                )
                break
            } catch {
                submitError = .unreachable("网络错误")
                runMachine.apply(.submitAmbiguous)
                break
            }
        }
        // 聊天可靠性包：重发轮的待发标记在此脱落——
        // 提交被受理、或结果未知转对账（.unknown 系），
        // 本轮自此归 run 账本/对账链负责，条目不再是
        // 「未发送」；只有明确拒绝（.failed）保持待
        // 发，让用户还能点按再试（拒绝横幅在下方分支
        // 照旧如实报）
        if userEntry.isPendingSend, runMachine.phase != .failed {
            userEntry.deliveryState = nil
            try? modelContext.save()
        }
        if let submitError, runMachine.phase == .failed {
            // 提交被明确拒绝（真失败）：本轮从未在服务
            // 端成立——消息留痕、横幅照实报、账本清除
            // 基础止血包（P1/P2）：留痕之外补失败标记
            // 与重发入口（旧口径只有横幅、再试只能重打）
            if !demoMode {
                appState.runLedger.remove(threadID: thread.id)
                markTurnFailed(
                    entry: userEntry,
                    failureKind: SendFailureKind.classify(
                        submit: submitError
                    )
                )
            }
            presentSendFailure(
                kind: SendFailureKind.classify(
                    submit: submitError
                ),
                detail: submitError.diagnosticDetail
            )
            finishRunPresentation(failed: true)
            return
        }
        // §494：发布心跳——50ms 一拍问发布门排
        // 空积压，与本轮同生共死（defer 取消）；
        // 未武装/无积压时 tick 恒空转、无副作用
        let publishTicker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .milliseconds(50)
                )
                if Task.isCancelled { break }
                tickStreamPublish()
            }
        }
        defer { publishTicker.cancel() }
        if case .generating(_) = runMachine.phase {
            await followRunEvents(
                thread: thread, entry: ledgerEntry,
                demoMode: demoMode
            )
        }
        if !runMachine.isSettled {
            await reconcileRun(
                thread: thread, entry: &ledgerEntry,
                demoMode: demoMode
            )
        }
    }

    /// events 订阅：增量入装配器/思考累积器（数据
    /// 面）、§494 起增量同点喂发布门出呈现快照
    /// （§409 步 A「不再发布呈现快照」口径作废）、
    /// 工具卡
    /// 实时拼装、思考预览（若服务端发出）同路；见
    /// 到终态事件记账返回，流自结束（断线/缓冲过
    /// 期）按「未见终态」进结果未知——不在此报错、
    /// 不做失败分型
    private func followRunEvents(
        thread: ChatThread, entry: RunLedgerEntry,
        demoMode: Bool
    ) async {
        // §449.9：新一轮跟随起手先清活动短语（上一轮
        // 残值不许串轮）；工具在飞栈为本趟局部账
        appState.liveActivityPhrase = nil
        // §479：活头像状态机同位喂食（与活动短语
        // 同源同点，本函数内下同）
        appState.livingAvatar.note(.runStarted)
        var liveToolStack: [(id: String, phrase: String)] = []
        guard let runID = entry.runID,
              let config = appState.config,
              let apiKey = appState.apiKey else { return }
        let stream = appState.client.runEvents(
            config: config, apiKey: apiKey,
            runID: runID, lastSeq: lastEventSeq
        )
        for await envelope in stream {
            if let seq = envelope.seq { lastEventSeq = seq }
            switch envelope.event {
            case .contentDelta(let delta),
                 .interim(let delta):
                if !delta.isEmpty {
                    appState.livingAvatar.note(.textDelta)
                    // 0.36.10：正文首达记位（事件序编排）
                    // 第 93 条：封段后 .text 标记已被换成
                    // .sealedText，新段首增量在此重新记位
                    // ——位置即新段的事件位（工具卡之后）
                    noteLiveOrder(.text)
                    // §409 步 A/E：增量只入装配器累
                    // 积（纯累积器）；§494：同点把装
                    // 配器全文喂发布门、到拍出快照
                    streamAssembler.offer(delta)
                    offerStreamPublish()
                }
            case .reasoningPreview(let text):
                appState.livingAvatar.note(.reasoning)
                if reasoningStartedAt == nil {
                    reasoningStartedAt = Date()
                }
                // 0.36.10：思考首达记位（事件序编排）
                noteLiveOrder(.reasoning)
                // §409 步 A/E：思考增量只入累积器
                // （落盘源头），不再发布快照
                reasoningPublishGate.offer(text)
            case .toolStarted(let id, let name, let preview):
                appState.livingAvatar.note(
                    .toolStarted(
                        LivingToolFamilyClassifier.classify(
                            toolName: name
                        )
                    )
                )
                // 第 93 条：工具开始＝服务端段边界——
                // 先封当前正文段再落卡，卡后的新段增量
                // 进新缓冲，不许再拼回本段
                sealStreamSegment()
                appendLiveToolCard(
                    id: id, name: name, preview: preview
                )
                // §449.9：活动短语入 AppState 单源（胶
                // 囊第二行/中枢状态行同读）；短语由
                // Core 映射表单点派生
                liveToolStack.append((
                    id: id,
                    phrase: ToolCardClassifier.activityPhrase(
                        forToolName: name
                    )
                ))
                appState.liveActivityPhrase =
                    liveToolStack.last?.phrase
            case .toolCompleted(
                let id, let name, let preview, let failed
            ):
                appState.livingAvatar.note(
                    .toolCompleted(
                        family: LivingToolFamilyClassifier
                            .classify(toolName: name),
                        failed: failed
                    )
                )
                completeLiveToolCard(
                    id: id, name: name, preview: preview,
                    failed: failed
                )
                liveToolStack.removeAll { $0.id == id }
                appState.liveActivityPhrase =
                    liveToolStack.last?.phrase
            case .terminal(let kind, let output):
                appState.liveActivityPhrase = nil
                switch kind {
                case .completed:
                    appState.livingAvatar.note(
                        .terminalCompleted
                    )
                case .failed:
                    appState.livingAvatar.note(
                        .terminalFailed
                    )
                default:
                    appState.livingAvatar.note(
                        .terminalCancelled
                    )
                }
                terminalOutputHint = output
                // §494：终态拍全量发布——对账落定
                // 前直播行先呈全文（与装配器兜底逐
                // 字一致），落定同键换装无跳变
                flushStreamPublish()
                runMachine.apply(.statusTerminal(kind))
                return
            case .other(let name):
                // 子智能体起落是干活·委派族的独立事
                // 件名（规格 §1.2 W4）；其余 .other 不喂
                if name == "subagent.start" {
                    appState.livingAvatar.note(
                        .toolStarted(.delegate)
                    )
                } else if name == "subagent.complete" {
                    appState.livingAvatar.note(
                        .toolCompleted(
                            family: .delegate, failed: false
                        )
                    )
                }
                continue
            }
        }
        // 流结束而未见终态：结果未知（非错误）。半截
        // 先落盘，进程被回收也不凭空消失
        appState.liveActivityPhrase = nil
        appState.livingAvatar.note(.streamLost)
        if !runMachine.isSettled,
           case .generating(_) = runMachine.phase {
            runMachine.apply(.streamLost)
            // §494：半截落盘接管呈现前先全量发布
            // （落盘条目与直播行同文、换装无回退）
            flushStreamPublish()
            persistRunPartials(thread: thread)
        }
    }

    /// 封段（第 93 条）：工具边界到达时把当前正文段
    /// 在装配器内定稿入封存列——liveOrder 的 .text
    /// 标记原位换成 .sealedText（段的事件位不动，
    /// 半截落盘按此序成条）。§494：封段拍同点全
    /// 量发布（段已定稿、呈现不许等下一增量才追
    /// 上封存段）。当前段为空（工具先行/并行工
    /// 具连发边界）时装配器无段可封，此处整件空转
    private func sealStreamSegment() {
        guard streamAssembler
            .sealCurrentSegment() != nil
        else { return }
        flushStreamPublish()
        let marker = LiveOrderItem.sealedText(
            streamAssembler.sealedSegments.count - 1
        )
        if let textIndex = liveOrder.firstIndex(of: .text) {
            liveOrder[textIndex] = marker
        } else {
            noteLiveOrder(marker)
        }
    }

    private func appendLiveToolCard(
        id: String, name: String, preview: String
    ) {
        let cardID = id.isEmpty ? "live-\(lastEventSeq)" : id
        guard !liveToolCards.contains(
            where: { $0.id == cardID }
        ) else { return }
        // 0.36.10（诊断 D3-3/D3-4）：标题回落改中文类
        // 名（旧实现英文短名直出卡面）；摘要过净化与
        // 落定同口径。events 通道不带参数分片，靠参数
        // 分形的标题（memory/skill 动作形）直播期用泛
        // 称、落定以 transcript 真参数重建修正——两期
        // 形态差异只在标题粒度，落定为准
        let title = ToolCardClassifier.title(
            forToolName: name, arguments: ""
        ) ?? ToolCardClassifier.fallbackTitle(forToolName: name)
        liveToolCards.append(ToolCard(
            id: cardID, toolName: name,
            category: ToolCardClassifier.category(
                forToolName: name
            ),
            title: title,
            summary: ToolCardClassifier.sanitizedSummary(preview),
            result: nil, resultFailed: false
        ))
        noteLiveOrder(.tool(cardID))
    }

    private func completeLiveToolCard(
        id: String, name: String, preview: String,
        failed: Bool
    ) {
        let cardID = id.isEmpty ? "live-\(lastEventSeq)" : id
        guard let index = liveToolCards.firstIndex(
            where: { $0.id == cardID }
        ) else {
            appendLiveToolCard(id: id, name: name, preview: "")
            completeLiveToolCard(
                id: id, name: name, preview: preview,
                failed: failed
            )
            return
        }
        let old = liveToolCards[index]
        // 0.36.10（诊断 D3-6）：直播结果先过 unwrap 与
        // 落定同口径——旧实现 preview 原文直存，与落
        // 定的剥包裹/分型形态前后两套，同一卡直播与
        // 落定可能长得不一样；失败标记取事件信号与
        // 结果自带信号的并集，落定时再以 transcript
        // 信号为准重算（D3-9）
        let unwrapped = ToolResultUnwrap.unwrap(preview)
        liveToolCards[index] = ToolCard(
            id: old.id, toolName: old.toolName,
            category: old.category, title: old.title,
            summary: old.summary, result: unwrapped.text,
            resultFailed: failed || unwrapped.failed
        )
    }

    /// 对账：以服务端为准把本轮落定。链路＝（缺
    /// runID 时同 key 重演取回）→（停止意图先行发
    /// stop）→ 状态轮询＋events 重挂＋transcript 落
    /// 定（状态只报命运、transcript 才是成品；状态
    /// 记录缺失时 transcript 单独定性）。预算（10 分
    /// 钟）耗尽停在未知：账本保留、下次进本线程续对
    /// 账，不报错、不重发。
    /// run 丢失的访问记账＋终局裁决（发送失败机制
    /// 包·语义 6）：记一次「查无此 run」的访问——计
    /// 数＋首查时刻回写账本（跨访问累计，旧口径每
    /// 次访问从零磨 600s、账本永不终局）；累计达
    /// 标（访问 ≥3 次或首查距今 ≥24h，双闸取或，RunLedger.
    /// missingRunIsLost）→ 摘账本＋条目判失败可重
    /// 发（成因 .runResultLost 落账钉死、不自动重
    /// 发）＋终局呈现，返回 true；未达标返回 false
    /// （账本保留、下次访问续查）。极少数同访双记
    /// （观察窗与耗尽段同访各记一次）至多让次数闸
    /// 提前一次访问触发——run 持续查不到本身已是
    /// 强证据，口径可接受
    private func recordMissingRunVisit(
        thread: ChatThread, entry: inout RunLedgerEntry,
        demoMode: Bool
    ) -> Bool {
        entry.missingReconcileCount += 1
        if entry.firstMissingAt == nil {
            entry.firstMissingAt = Date()
        }
        if !demoMode {
            appState.runLedger.upsert(entry)
        }
        guard RunLedger.missingRunIsLost(
            missingCount: entry.missingReconcileCount,
            firstMissingAt: entry.firstMissingAt,
            now: Date()
        ) else { return false }
        if !demoMode,
           let uid = UUID(uuidString: entry.userEntryID) {
            appState.runLedger.remove(userEntryID: uid)
        }
        if let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) {
            markTurnFailed(
                entry: userEntry, failureKind: .runResultLost
            )
        }
        presentSendFailure(kind: .runResultLost)
        Haptics.error()
        return true
    }

    private func reconcileRun(
        thread: ChatThread, entry: inout RunLedgerEntry,
        demoMode: Bool
    ) async {
        guard let config = appState.config,
              let apiKey = appState.apiKey else { return }
        if runMachine.phase == .unknown {
            runMachine.apply(.foregrounded)
        }
        var deadline = Date().addingTimeInterval(600)
        // 对账分型（发送失败机制包·语义 7）：查询失
        // 败＝无证据，不烧 600s 预算——每次无证据轮
        // 询顺延期限，总顺延封顶 600s 防死服务端无
        // 限续命
        var deadlineExtensions: TimeInterval = 0
        // 本次访问首次见真 missing（状态端点 404）
        // 的时刻：持续 60s 仍无 transcript 证据才记
        // 一次「丢失访问」（跨访问累计见 RunLedger-
        // Entry.missingReconcileCount）
        var missingPollsStartedAt: Date?
        // §153：重演取回用本会话当前执行选择（与首提同源）
        let replayChoice = appState.sessionModelChoice(
            serverSessionID: entry.sessionID, threadID: thread.id
        )
        var transcriptMisses = 0
        while !runMachine.isSettled {
            if Task.isCancelled { return }
            // runID 缺失（受理回执丢失/提交窗口被杀）：
            // 同 key 重演取回——服务端幂等保证不双跑
            if entry.runID == nil {
                guard let replayInput = runReplayInput(
                    thread: thread, entry: entry
                ) else {
                    // 用户条目已不在（线程被清）：本轮无
                    // 从恢复，清账收尾（§451：只清本轮
                    // 这条，同线程其他未落定轮不许牵连）
                    if !demoMode,
                       let uid = UUID(
                           uuidString: entry.userEntryID
                       ) {
                        appState.runLedger.remove(
                            userEntryID: uid
                        )
                    }
                    finishRunPresentation(failed: false)
                    return
                }
                do {
                    let response = try await appState.client
                        .submitRun(
                            config: config, apiKey: apiKey,
                            sessionID: entry.sessionID,
                            input: replayInput,
                            model: replayChoice.model,
                            provider: replayChoice.providerField,
                            idempotencyKey: entry.idempotencyKey
                        )
                    entry.runID = response.runID
                    if !demoMode {
                        appState.runLedger.upsert(entry)
                    }
                    runMachine.apply(.submitAccepted)
                    if !demoMode {
                        markAcceptedEntryAccepted(
                            thread: thread,
                            userEntryID: entry.userEntryID
                        )
                    }
                } catch {
                    // 重演提交抛错同属无证据（传输/服务
                    // 端问题）：顺延期限、不烧预算
                    if deadlineExtensions < 600 {
                        deadline = deadline
                            .addingTimeInterval(3)
                        deadlineExtensions += 3
                    }
                    if Date() > deadline { break }
                    try? await Task.sleep(for: .seconds(3))
                    continue
                }
            }
            guard let runID = entry.runID else { continue }
            // 停止意图先行（账本/机器任一置位）
            if runMachine.stopRequested || entry.stopRequested {
                if !runMachine.stopRequested {
                    runMachine.apply(.stopRequested)
                }
                try? await appState.client.stopRun(
                    config: config, apiKey: apiKey, runID: runID
                )
            }
            // 已有终态证据（events 先行到达）：trans-
            // cript 落定；迟迟不落（或演示态无 trans-
            // cript）以状态 output 合成落定
            if runMachine.terminalKind != nil {
                if !demoMode,
                   await settleRunFromTranscript(
                       thread: thread, entry: entry
                   ) {
                    return
                }
                transcriptMisses += 1
                if demoMode || transcriptMisses >= 2 {
                    settleRunFromStatusOutput(
                        thread: thread, entry: entry
                    )
                    return
                }
                try? await Task.sleep(for: .milliseconds(1500))
                continue
            }
            // 状态轮询（对账分型，语义 7）：抛错＝查
            // 询失败＝无证据——旧口径 try? 把抛错与
            // 404 一并压成 nil 判 missing，网络抖动/
            // 鉴权失败/5xx 全被记成「run 不见了」，
            // 600s 磨完给假终局；现只有客户端明确
            // 404（runStatus 返 nil）才是真 missing
            let status: RunStatusResponse?
            do {
                status = try await appState.client.runStatus(
                    config: config, apiKey: apiKey, runID: runID
                )
            } catch {
                if deadlineExtensions < 600 {
                    deadline = deadline.addingTimeInterval(3)
                    deadlineExtensions += 3
                }
                try? await Task.sleep(for: .seconds(3))
                continue
            }
            switch status {
            case .some(let value) where value.status.isTerminal:
                terminalStatusHint = value
                runMachine.apply(.statusTerminal(value.status))
            case .some(let value) where value.status.isActive:
                runMachine.apply(.statusRunning)
                // 仍在生成：重挂 events 续看（缓冲还在
                // 能接上直播；已扫则流立即结束回轮询）
                await followRunEvents(
                    thread: thread, entry: entry,
                    demoMode: demoMode
                )
                if runMachine.terminalKind != nil { continue }
                // 缓冲已扫时 events 会立即空转返回：轮询
                // 必须带间隔，防忙循环空烧
                try? await Task.sleep(for: .seconds(2))
                if Date() > deadline { break }
            case .some:
                // 状态词无法归类：无证据，继续轮询
                try? await Task.sleep(for: .seconds(3))
            case .none:
                // 真 missing（状态端点 404）：转 trans-
                // cript 单独定性；transcript 也无证据且
                // missing 持续 60s → 本次访问记账＋裁
                // 决（终局判失败，或留账下次续查）
                if missingPollsStartedAt == nil {
                    missingPollsStartedAt = Date()
                }
                runMachine.apply(.statusMissing)
                if await settleRunFromTranscript(
                    thread: thread, entry: entry
                ) {
                    return
                }
                if let started = missingPollsStartedAt,
                   Date().timeIntervalSince(started) > 60 {
                    if recordMissingRunVisit(
                        thread: thread, entry: &entry,
                        demoMode: demoMode
                    ) {
                        finishRunPresentation(failed: true)
                    } else {
                        showNotice(
                            "这条的生成结果暂时没查到，稍后回到本对话会继续确认。",
                            tier: .extended
                        )
                        finishRunPresentation(failed: false)
                    }
                    return
                }
                try? await Task.sleep(for: .seconds(3))
            }
            if Date() > deadline { break }
        }
        if !runMachine.isSettled {
            runMachine.apply(.settleExhausted)
            persistRunPartials(thread: thread)
            if entry.runID == nil {
                // §414 增补（断网规格 5.2）：本轮从未
                // 被服务端受理（runID 恒 nil）却磨满
                // 预算——「生成仍在服务器进行中」对
                // 它是假话。折回待发巷（待发标记＋
                // queued 态）、清账本（账本留着只会
                // 让后续发送全撞忙碌守卫、条目永无标
                // 记），提示照实说还没发出去；网络恢
                // 复后 drain 自动续发
                if !demoMode,
                   let userEntry = thread.entries.first(
                       where: {
                           $0.id.uuidString == entry.userEntryID
                       }
                   ) {
                    userEntry.markPendingSend(
                        in: modelContext
                    )
                    // §451：清账只清本轮这条
                    if let uid = UUID(
                        uuidString: entry.userEntryID
                    ) {
                        appState.runLedger.remove(
                            userEntryID: uid
                        )
                    }
                }
                showNotice(
                    "这条还没发出去，网络恢复后会自动发送，也可以点按消息旁的时钟重发。",
                    tier: .extended
                )
                finishRunPresentation(failed: false)
            } else if missingPollsStartedAt != nil {
                // 本次访问见过真 missing、预算先磨完
                // （未满 60s 观察窗）：同样记一次访问
                // ＋裁决，不许带「还在生成」的假话退
                // 场（语义 6）
                if recordMissingRunVisit(
                    thread: thread, entry: &entry,
                    demoMode: demoMode
                ) {
                    finishRunPresentation(failed: true)
                } else {
                    showNotice(
                        "这条的生成结果暂时没查到，稍后回到本对话会继续确认。",
                        tier: .extended
                    )
                    finishRunPresentation(failed: false)
                }
            } else {
                // 体面出口：生成仍在服务端进行（或结
                // 果待查），账本保留、下次进本线程自
                // 动续对账——runID 在席时这句是真话，
                // 保留现行语义
                showNotice(
                    "生成仍在服务器进行中，稍后回到本对话会自动补齐结果。",
                    tier: .extended
                )
                finishRunPresentation(failed: false)
            }
        }
    }

    /// 同 key 重演提交的输入重建：源头是本地用户条目
    /// 本身（正文＋引用折叠＋图片），不另存载荷副本
    private func runReplayInput(
        thread: ChatThread, entry: RunLedgerEntry
    ) -> RunInput? {
        guard let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) else { return nil }
        let text = MessageQuote.outgoingContent(
            userText: userEntry.content, quote: userEntry.quote,
            sourceQuote: userEntry.sourceQuote
        )
        // §152：重演源头是本地条目全集——旧口径只
        // 取 imageData 首图，同 key 重演（提交回执
        // 丢失时）会把多图消息在服务端降成单图
        let localImages = userEntry.allImageDatas
        if !localImages.isEmpty {
            return .message(ChatMessage(
                role: "user", text: text,
                imageDataURLs: localImages.map {
                    "data:image/jpeg;base64,"
                        + $0.base64EncodedString()
                }
            ))
        }
        return .text(text)
    }

    /// transcript 落定：拉服务端会话历史、提取本轮段
    /// （Core RunTranscriptSettle）、整段替换本地半
    /// 截。段已落定返回 true；尚未出现（服务端还没
    /// flush 完）返回 false 由对账重试
    private func settleRunFromTranscript(
        thread: ChatThread, entry: RunLedgerEntry
    ) async -> Bool {
        guard let messages = try? await appState
            .performAdmin({ client, cfg in
                try await client.sessionMessages(
                    config: cfg, id: entry.sessionID
                )
            }) else { return false }
        // 0.36.29（题 B 自愈）：段落定之前先对账补
        // 缺——存档有、本地缺的 user 条目补回（定
        // 案与口径见 healMissingUserEntries），补完
        // 再走既有落定，助手条目不归此路补造
        healMissingUserEntries(
            thread: thread, sessionID: entry.sessionID,
            messages: messages
        )
        // §451（App-4 硬门）：落定提取改锚本轮
        // serverRowID——多轮已受理时旧「末条 user
        // 行」锚会把后轮的段落到本轮头上（串段）。
        // 锚解析不到且同线程还有别的未落定轮时不许
        // 走无锚口径：本轮按未落定回对账重试（终态
        // 证据在席时对账自会转状态合成落定兜底——
        // 那条路按 runID 取数、不串段）
        let anchorRowID = transcriptAnchorRowID(
            thread: thread, entry: entry, messages: messages
        )
        if anchorRowID == nil,
           appState.runLedger.entries(
               forThreadID: thread.id
           ).count > 1 {
            runMachine.apply(.transcriptPending)
            return false
        }
        let settled = RunTranscriptSettle.settle(
            messages: messages, anchorRowID: anchorRowID
        )
        guard settled.found else {
            runMachine.apply(.transcriptPending)
            return false
        }
        // transcript-only 定性（无状态证据）时先把段的
        // 性质喂给状态机：失败段＝failed；停止意图在
        // 场＝cancelled；其余＝completed
        if runMachine.terminalKind == nil {
            if settled.failed {
                runMachine.apply(.statusTerminal(.failed))
            } else if runMachine.stopRequested
                        || entry.stopRequested {
                runMachine.apply(.statusTerminal(.cancelled))
            } else {
                runMachine.apply(.statusTerminal(.completed))
            }
        }
        applySettledTurn(
            thread: thread, entry: entry, settled: settled
        )
        return true
    }

    /// 落定对账补缺（0.36.29，题 B 自愈）：新建旁聊
    /// 首发出现过「服务端存档完好、本地线程只剩助
    /// 手回复」的首句消失——静态审计已排除发送/落
    /// 盘/导入/落定四链的删除与过滤路径，剩余嫌疑
    /// 在新建＋切换＋首发同瞬间的本地时序缝（未证
    /// 死，定案等级中）。修法不赌竞态细节：以已拉
    /// 取的 transcript 为锚，Core 对账判缺（内容＋
    /// 时间窗、只认 user 条目），缺的补回呈现层；
    /// 发送链与落盘删除面一律不动。补缺发生时记
    /// 一条诊断读数（会话 id＋补回条数）留证，供
    /// 后续升格定案
    private func healMissingUserEntries(
        thread: ChatThread, sessionID: String,
        messages: [SessionMessage]
    ) {
        let localUsers = thread.entries
            .filter { $0.role == "user" }
            .map {
                (content: $0.content, createdAt: $0.createdAt,
                 filePaths: $0.remoteFilePaths,
                 imagePaths: $0.remoteImagePaths)
            }
        let reconcile = RunTranscriptSettle.reconcileUserMessages(
            messages: messages, localUserEntries: localUsers
        )
        // §121 题二 a（对账回填）：配上对但本地条目缺
        // 服务端附件路径的，把路径集回填落盘——发送
        // 回填（sendTask）管新消息，本路管存量（发送
        // 回填上线前已发的消息在本线程下一次落定自
        // 动补牌）。定位键＝规范正文＋createdAt（与
        // Core 配对同锚）；回填只补缺字段、不动正文
        if !reconcile.pathBackfills.isEmpty {
            var backfilled = 0
            for backfill in reconcile.pathBackfills {
                guard let entry = thread.entries.first(where: {
                    $0.role == "user"
                        && $0.createdAt == backfill.createdAt
                        && SessionHistoryImport
                            .normalizedUserContent($0.content)
                            .text.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ) == backfill.text
                }) else { continue }
                if !backfill.filePaths.isEmpty,
                   entry.remoteFilePaths.isEmpty {
                    entry.remoteFilePathsData =
                        try? JSONEncoder().encode(backfill.filePaths)
                    backfilled += 1
                }
                if !backfill.imagePaths.isEmpty,
                   entry.remoteImagePaths.isEmpty {
                    entry.remoteImagePathsData =
                        try? JSONEncoder().encode(backfill.imagePaths)
                    backfilled += 1
                }
            }
            if backfilled > 0 {
                try? modelContext.save()
                ChatDiagTrace.record(
                    "落定回填附件路径 session=\(sessionID) fields=\(backfilled)"
                )
            }
        }
        let missing = reconcile.missing
        guard !missing.isEmpty else { return }
        for message in missing {
            // 0.46.1（§116）：补回也走规范化——展开块
            // 还原成干净正文＋附件路径落盘，不把给模型
            // 的脚手架原文补进气泡
            let normalized = SessionHistoryImport
                .normalizedUserContent(message.content)
            let healed = ChatEntry(
                role: "user", content: normalized.text,
                thread: thread,
                remoteImagePaths: normalized.imagePaths,
                remoteFilePaths: normalized.fileRefs
            )
            // 时刻以服务端存档为准（排序锚）；存档
            // 无时刻时保留插入时刻（落定助手条目随
            // 后以当前时刻落位，相对序仍成立）
            if let date = message.date {
                healed.createdAt = date
            }
            // 台账 187：补回条目出自服务端行——同点
            // 钉桩＋镜像（与导入落盘同口径）
            if message.id > 0 {
                healed.serverRowID = Int(exactly: message.id)
            }
            healed.applyReactions(message.reactions)
            modelContext.insert(healed)
        }
        try? modelContext.save()
        ChatDiagTrace.record(
            "落定补缺 session=\(sessionID) healed=\(missing.count)"
        )
    }

    /// 状态 output 合成落定（transcript 迟迟不落或演
    /// 示态）：终局文本取状态/事件 output，工具卡用
    /// 直播拼装的现成品——只作兜底，正常轮次以
    /// transcript 为准
    private func settleRunFromStatusOutput(
        thread: ChatThread, entry: RunLedgerEntry
    ) {
        if runMachine.terminalKind == .failed {
            deleteTurnPartialEntries(
                thread: thread, entry: entry
            )
            if !appState.isDemo,
               let uid = UUID(uuidString: entry.userEntryID) {
                // §451：清账只清本轮这条
                appState.runLedger.remove(userEntryID: uid)
            }
            // 基础止血包（P5/P2）：服务端原文只作分型
            // 输入与诊断留痕，界面只呈现 HermesError
            // 人话档（RunFailureClassifier）；本轮用户
            // 条目挂失败标记、点标记重发
            let failure = RunFailureClassifier.classify(
                errorText: terminalStatusHint?.error,
                outputText: terminalStatusHint?.output
                    ?? terminalOutputHint
            )
            ChatDiagTrace.record(
                "run 失败分型（状态合成落定）kind=\(failure)"
                    + " run=\(entry.runID ?? "-")"
            )
            if !appState.isDemo {
                markRunFailure(
                    entry: entry, in: thread, failure: failure
                )
            }
            presentSendFailure(
                kind: SendFailureKind.classify(run: failure),
                detail: failure.diagnosticDetail
            )
            runMachine.apply(.transcriptSettled)
            finishRunPresentation(failed: true)
            return
        }
        let output = terminalStatusHint?.output
            ?? terminalOutputHint
        // 第 93 条：兜底全文走装配器合并口径（各段
        // 以 "\n\n" 连接，与 transcript 落定拼接同
        // 制）——旧单闸全文是跨段直接拼接，与落库
        // 形态不一致
        let fallbackText = streamAssembler.mergedFullText
        let settled = SettledRunTurn(
            found: true,
            toolCards: liveToolCards,
            reasoning: nil,
            finalText: (output?.isEmpty == false)
                ? output
                : (fallbackText.isEmpty ? nil : fallbackText),
            failed: false, failureText: nil
        )
        applySettledTurn(
            thread: thread, entry: entry, settled: settled
        )
    }

    /// §426（缺陷一）：提交受理同点把本轮用户条
    /// 目标记送达——服务器确认收到＝发送成功，气
    /// 泡即刻回全色、时钟离席，不等整轮落定。旧
    /// 链 delivered 唯一写点在 applySettledTurn
    /// （落定），受理后整段生成期条目恒挂未确认
    /// 态（用户真机截图钉死）。三受理点（首提/
    /// 对账重演/恢复确立）与占位文案相位门共用
    /// .submitAccepted 同一信号、不新造第二信
    /// 号；落定点的既有写点保留作兜底（幂等同
    /// 值）。已送达/无状态条目不动（remainsIn-
    /// Queue 守卫），失败态条目在重发受理时经此
    /// 清失败标记（markSendState 的 accepted/
    /// delivered 同组语义自带）
    private func markAcceptedEntryAccepted(
        thread: ChatThread, userEntryID: String
    ) {
        guard let userEntry = thread.entries.first(
                  where: { $0.id.uuidString == userEntryID }
              ),
              userEntry.sendState?.remainsInQueue == true
        else { return }
        // 发送失败机制包（语义 1 双轴）：内部状态落
        // .accepted 而非 .delivered——呈现与 §426 不
        // 变（markSendState 的 accepted 组合同 deliv-
        // ered：清失败标记＋送达投影，气泡全色、时钟
        // 离席），但条目在 run 真终态前不脱离发件箱
        // 语义：重试记账活到落定、发件箱判定不再把
        // 在飞条目当已完成（B1 清账错位的根）
        userEntry.markSendState(.accepted, in: modelContext)
    }

    /// 落定入账：整段替换本轮半截条目（工具卡＋带思
    /// 考回填的助手正文），触感与标题回流沿旧口径，
    /// 账本清除
    private func applySettledTurn(
        thread: ChatThread, entry: RunLedgerEntry,
        settled: SettledRunTurn
    ) {
        // H2-a 自动朗读的在场判读：本轮是不是用户在
        // 本页亲手发出并看着落定的（发送打点起点只
        // 在这种轮有；恢复轮/后台轮无起点）——必须
        // 在下方打点消费清零之前先记下来
        let watchedTurn = sendFrameStartedAt != nil
        // §135 D 案打点：发送→落定全程一段（仅用户
        // 在飞发送的落定轮有起点；恢复轮与后台轮无
        // 起点、不记）。入口先记先清：失败分支同样
        // 消费读数，不许残留起点污染下一轮
        if entry.threadID == thread.id.uuidString,
           let started = sendFrameStartedAt {
            ChatDiagTrace.record(
                "发送打点 发送→落定 "
                    + "\(Int(Date().timeIntervalSince(started) * 1000))ms"
            )
            sendFrameStartedAt = nil
            sendFrameRestickLogged = false
        }
        runMachine.apply(.transcriptSettled)
        let phase = runMachine.phase
        deleteTurnPartialEntries(thread: thread, entry: entry)
        if settled.failed {
            // 基础止血包（P5/P2）：同状态合成落定——
            // 原文（终态回执＋段失败文本）只作分型输
            // 入，界面只呈现人话档；用户条目挂失败标
            // 记、点标记重发
            let failure = RunFailureClassifier.classify(
                errorText: terminalStatusHint?.error,
                outputText: terminalStatusHint?.output
                    ?? settled.failureText
            )
            ChatDiagTrace.record(
                "run 失败分型（落定）kind=\(failure)"
                    + " run=\(entry.runID ?? "-")"
            )
            if !appState.isDemo {
                // §451：清账只清本轮这条
                if let uid = UUID(
                    uuidString: entry.userEntryID
                ) {
                    appState.runLedger.remove(
                        userEntryID: uid
                    )
                }
                markRunFailure(
                    entry: entry, in: thread, failure: failure
                )
            }
            presentSendFailure(
                kind: SendFailureKind.classify(run: failure),
                detail: failure.diagnosticDetail
            )
            finishRunPresentation(failed: true)
            return
        }
        // 基础止血包（P1/P2）：成功落定清本轮用户条目
        // 的失败标记——重发成功后旧标记不许残留（首
        // 发成功轮条目恒无标记，本支为空转）；§237：
        // 同点把发送状态落到 delivered（统一写口同
        // 步清 sendFailed 与 deliveryState），队列态
        // 至此出列、不许残留 sending/failed 旧值
        if !appState.isDemo,
           let userEntry = thread.entries.first(
               where: { $0.id.uuidString == entry.userEntryID }
           ) {
            // 台账 187：落定同点钉桩——本轮锚点 user
            // 行的服务端行 id 钉进本地条目（反应寻址
            // 坐标）；已钉不覆（坐标恒定、覆写无义）
            if let rowID = settled.userRowID,
               userEntry.serverRowID == nil {
                userEntry.serverRowID = rowID
            }
            userEntry.markSendState(.delivered, in: modelContext)
            // 发送失败机制包（语义 1 清账点①）：run
            // 真终态落定成功——本条重试记账在此单点
            // 清（按条目 id、不扫线程）；失败支不许
            // 清（账留着钉死准入）
            appState.outboxRetry.clear(entryID: userEntry.id)
        }
        let endDate = Date()
        for (index, card) in settled.toolCards.enumerated() {
            let cardEntry = ChatEntry(
                role: "tool", content: "", thread: thread,
                toolCard: card
            )
            cardEntry.createdAt = endDate.addingTimeInterval(
                Double(index) * 0.001
            )
            modelContext.insert(cardEntry)
        }
        // H2-a：本轮落定的助手条目（自动朗读的取材
        // 口，与下方 finished 分支的触感同点消费）
        var landedAssistantEntry: ChatEntry?
        if let text = settled.finalText, !text.isEmpty {
            let assistantEntry = ChatEntry(
                role: "assistant", content: text,
                thread: thread, reasoning: settled.reasoning,
                reasoningSeconds: nil
            )
            landedAssistantEntry = assistantEntry
            // 台账 187：正文恰出自单条服务端行时同点
            // 钉桩（多行拼接成文恒 nil、不钉错行——
            // 见 SettledRunTurn.assistantRowID 口径）
            assistantEntry.serverRowID = settled.assistantRowID
            // §441：多行拼接成文时 assistantRowID 恒
            // nil——本条目即段内拼接体、其末行正是
            // 选择框 attach 的落点行，改钉 options-
            // RowID 使卡有行可挂（寻址语义＝段末行）
            if assistantEntry.serverRowID == nil,
               let optionsRowID = settled.optionsRowID {
                assistantEntry.serverRowID = optionsRowID
            }
            if let options = settled.options,
               let optionsRowID = settled.optionsRowID {
                appState.optionsOverlay.seed(
                    threadID: thread.id,
                    card: .init(
                        serverRowID: optionsRowID,
                        options: options
                    )
                )
            }
            assistantEntry.createdAt = endDate
                .addingTimeInterval(
                    Double(settled.toolCards.count) * 0.001
                        + 0.001
                )
            modelContext.insert(assistantEntry)
            // §247（包 4）：落定映射登记——本条目在
            // 新承载里沿用本轮流式行键建行（同键换
            // 代＝落定不换装）；映射只记账不判事，
            // 旧承载与未开新路时均无消费方、无副作用
            streamSettleMap.record(
                entryID: assistantEntry.id,
                streamRowKey: StreamingRowIdentity
                    .streamRowKey(userEntryID: entry.userEntryID)
            )
            thread.updatedAt = Date()
        }
        if !settled.toolCards.isEmpty
            || settled.finalText?.isEmpty == false {
            try? modelContext.save()
        }
        if !appState.isDemo,
           let uid = UUID(uuidString: entry.userEntryID) {
            // §451：清账只清本轮这条——同线程后轮的账
            // 本还等着消费环逐轮驱动
            appState.runLedger.remove(userEntryID: uid)
        }
        // 结果触感与收尾（旧 runStream 同口径）：完成
        // 有正文给 .success；真取消给「已停止生成」
        // （5 秒自消）；失败已在上分支处理。断线/切后
        // 台恢复后落定成功全程静默（§140 提示纪律第
        // 1 条「成功不报」——旧「已重新连接，回复已
        // 补齐。」播报与 runWasDetached 旗已整条摘除）
        if phase == .finished {
            if settled.finalText?.isEmpty == false {
                Haptics.success()
                // §411 自动朗读：只读用户在场看完的
                // 本轮——恢复/后台落定沿 §140 静默口
                // 径不出声；开关判读（默认关）收在播
                // 放器 autoReadIfEnabled 内，落定点不
                // 再读偏好；未开通、正在听别条时播放
                // 器内部自拒
                if watchedTurn, let landedAssistantEntry {
                    SpeechPlayer.shared.autoReadIfEnabled(
                        entryID: landedAssistantEntry.id,
                        content: landedAssistantEntry.content,
                        appState: appState
                    )
                }
            }
            // 标题回流触发（0.21.0 沿用）：已链接旁聊
            // 一轮完整落地后顶刷新令牌等服务端 AI 标题
            if thread.serverSessionID != nil,
               thread.id != appState.sessionLedger.mainThreadID {
                appState.noteLinkedSideChatTurnFinished()
            }
        } else if phase == .cancelled {
            showNotice("已停止生成。")
        }
        finishRunPresentation(failed: false)
    }

    /// 本轮半截候选的单点谓词（§414 抽出，整段替换
    /// 与半截回填共用）：用户条目之后、下一轮用户
    /// 条目之前的非锚定非待发条目。「下一轮」界＝
    /// 其后首个非待发的用户条目（待发条目未被服
    /// 务端受理、不构成轮次边界，其自身另有待发
    /// 豁免）。旧口径只有「用户条目之后必属本轮」
    /// 一条（发送互斥下成立）；§414 中段条目原位
    /// 重发后该前提失效——本轮用户条目之后可以躺
    /// 着已落定的后续轮次，靠本界免于陪葬。常规
    /// 轮（用户条目居末）无下一轮、界不生效，行
    /// 为与旧口径逐字同。既有豁免并入谓词：§123/
    /// §165 系统锚定条目（跨面并发落盘、不属本
    /// 轮）、待发条目（从未被服务端受理、不属任
    /// 何一轮的半截，用户消息不许陪葬）
    static func turnPartialCandidates(
        in thread: ChatThread, userEntry: ChatEntry
    ) -> [ChatEntry] {
        let nextTurnStart = thread.sortedEntries.first(
            where: {
                $0.id != userEntry.id
                    && $0.createdAt > userEntry.createdAt
                    && $0.role == "user"
                    && !$0.isPendingSend
            }
        )?.createdAt
        return thread.entries.filter {
            $0.id != userEntry.id
                && $0.createdAt > userEntry.createdAt
                && !$0.isSystemAnchored
                && !$0.isPendingSend
                && (nextTurnStart == nil
                    || $0.createdAt < nextTurnStart!)
        }
    }

    /// 整段替换的删除面：已落盘的半截名单＋本轮半
    /// 截候选（turnPartialCandidates，含下一轮界）
    private func deleteTurnPartialEntries(
        thread: ChatThread, entry: RunLedgerEntry
    ) {
        deleteLivePartialEntries(in: thread)
        guard let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) else { return }
        for candidate in Self.turnPartialCandidates(
            in: thread, userEntry: userEntry
        ) {
            modelContext.delete(candidate)
        }
        try? modelContext.save()
    }

    /// 结果未知时的半截落盘（进程被回收也不凭空消
    /// 失）：工具卡与已累积正文按条目落盘、记 id 供
    /// 落定时整段替换（与旧 interrupted 落盘同制）。
    /// 第 93 条：正文按段成条——封存段与当前段各成
    /// 一条助理条目、按 liveOrder 的事件序与工具卡
    /// 交错落盘（时序即恢复回填的段序凭据）；旧形态
    /// 把整轮正文拼成一条，跨段混存正是串字在落盘
    /// 侧的同根形态（回填只能整段吞回单一缓冲、前
    /// 段与后段就此混为一谈）。标记外的卡/段（回填
    /// 重挂等）按卡序/段序殿后补齐，不丢件
    private func persistRunPartials(thread: ChatThread) {
        // §409 步 E：装配器/累积器已是纯累积形态，
        // fullSegments/fullText 每拍恒精确——旧
        // flush 定稿两行随发布语义退役删除，落盘
        // 直读两口径（条目写入逻辑逐字不变）
        deleteLivePartialEntries(in: thread)
        let reasoningText = reasoningPublishGate.fullText
        let segments = streamAssembler.fullSegments
        let sealedCount = streamAssembler
            .sealedSegments.count
        let endDate = Date()
        var ids: [UUID] = []
        var slot = 0
        var insertedAssistant = false
        func persistCard(_ card: ToolCard) {
            let cardEntry = ChatEntry(
                role: "tool", content: "", thread: thread,
                toolCard: card
            )
            cardEntry.createdAt = endDate.addingTimeInterval(
                Double(slot) * 0.001
            )
            slot += 1
            modelContext.insert(cardEntry)
            ids.append(cardEntry.id)
        }
        func persistSegment(_ text: String) {
            // 思考挂第一条助理条目：思考是本轮的单一
            // 折叠单元、不按段拆（与落定口径同）
            let assistantEntry = ChatEntry(
                role: "assistant", content: text,
                thread: thread,
                reasoning: !insertedAssistant
                    && !reasoningText.isEmpty
                    ? reasoningText : nil,
                reasoningSeconds: nil
            )
            assistantEntry.createdAt = endDate
                .addingTimeInterval(Double(slot) * 0.001)
            slot += 1
            modelContext.insert(assistantEntry)
            insertedAssistant = true
            ids.append(assistantEntry.id)
        }
        var persistedCardIDs: Set<String> = []
        var persistedSegments: Set<Int> = []
        for marker in liveOrder {
            switch marker {
            case .reasoning:
                continue
            case .sealedText(let index):
                if segments.indices.contains(index) {
                    persistSegment(segments[index])
                    persistedSegments.insert(index)
                }
            case .text:
                // 当前段在 fullSegments 中的下标恒为封
                // 存段数（有内容才在列）
                if streamAssembler.hasCurrentContent,
                   segments.indices.contains(sealedCount) {
                    persistSegment(segments[sealedCount])
                    persistedSegments.insert(sealedCount)
                }
            case .tool(let id):
                if let card = liveToolCards.first(
                    where: { $0.id == id }
                ) {
                    persistCard(card)
                    persistedCardIDs.insert(id)
                }
            }
        }
        for card in liveToolCards
        where !persistedCardIDs.contains(card.id) {
            persistCard(card)
        }
        for (index, text) in segments.enumerated()
        where !persistedSegments.contains(index) {
            persistSegment(text)
        }
        if insertedAssistant {
            thread.updatedAt = Date()
        }
        if !ids.isEmpty {
            try? modelContext.save()
        }
        livePartialEntryIDs = ids
    }

    private func deleteLivePartialEntries(
        in thread: ChatThread
    ) {
        guard !livePartialEntryIDs.isEmpty else { return }
        for candidate in thread.entries
        where livePartialEntryIDs.contains(candidate.id) {
            modelContext.delete(candidate)
        }
        livePartialEntryIDs = []
    }

    /// 呈现收尾：清流式状态与在途标记（触感由各落定
    /// 分支自理，此处只在失败时补 .error——调用方
    /// 已给触感的路径传 failed=false 防双响；0.36.2
    /// 失败触感自 .warning 改判 .error，表 D 归位）
    private func finishRunPresentation(failed: Bool) {
        if failed {
            Haptics.error()
        }
        // §494：全部落定/失败/取消出口共用收尾
        // ——发布态同点整清，直播行随占位条件消
        // 失、落定条目同键接位
        resetStreamPresentation()
        streamingText = nil
        reasoningStartedAt = nil
        sendTask = nil
        activeRunThreadID = nil
        // 0.36.10（诊断 D2 补根）：直播区至此必须清
        // 空——旧实现漏清 liveToolCards，落定条目已
        // 入列后残留直播卡仍在列表尾同屏渲染、且挂
        // 「进行中」，正是判词 5 截图底部那截残影。
        // 本函数是全部落定/失败/取消出口的共用收尾，
        // 清在此处不误伤对账中途（persistRunPartials
        // 在调用本函数之前已把半截转入条目）
        liveToolCards = []
        liveOrder = []
        // 第 93 条：封存段真值在装配器本体内，下
        // 一轮 driveRun 起点归零，视图侧无镜像可清
    }

    /// 停止（0.31.0）：runs 通道真取消——发 stop 后
    /// 由订阅/对账链等终态落定、部分产物按 transcr-
    /// ipt 呈现；提交窗口内则取消本地提交任务（账本
    /// 已留停止意图，下次对账执行真停止）
    private func requestRunStop() {
        guard isStreaming else { return }
        if runMachine.phase == .submitting {
            sendTask?.cancel()
            // §451：提交窗已迁提交泵——同点取消当前
            // 线程的泵任务（泵内 performSubmit 的取
            // 消支路记账本停止意图、静默收尾）
            if let threadID = activeRunThreadID
                ?? currentThreadID {
                submitPumpTasks[threadID]?.cancel()
            }
            return
        }
        runMachine.apply(.stopRequested)
        guard let threadID = activeRunThreadID,
              var entry = appState.runLedger.entry(
                  forThreadID: threadID
              ) else { return }
        entry.stopRequested = true
        appState.runLedger.upsert(entry)
        guard let runID = entry.runID,
              let config = appState.config,
              let apiKey = appState.apiKey else { return }
        Task {
            try? await appState.client.stopRun(
                config: config, apiKey: apiKey, runID: runID
            )
        }
    }

    /// 进线程/回前台时恢复未落定 run（杀进程/切后台/
    /// 预算耗尽遗留）：半截呈现回填＋对账落定。无账
    /// 本或驱动在途即返回
    private func resumeRunIfNeeded() async {
        guard !appState.isDemo, !isDrivingRun,
              scenePhase == .active,
              let thread = currentThread,
              let entry = appState.runLedger.entry(
                  forThreadID: thread.id
              ) else { return }
        await driveAcceptedTurn(thread: thread, entry: entry)
    }

}

/// 原生面行菜单承载开关（§330，0.50.70 热修题
/// 2；§332 换代；台账 187 再换代）：原生面动作
/// 面改由控制器长按识别器承载（ChatNative-
/// List），托管内容内的 SwiftUI 长按须在本面关
/// 闭——两承载同挂会双出面、且 SwiftUI 承载正
/// 是 .69 真机长按全灭的当事层。仅原生面行构
/// 造点置 false；gen3 面无此环境值、默认 true
/// 消息长按菜单挂载（0.4.1 立制；台账 200 拆
/// 换，2026-11-21 用户拍板）：回归系统上下文菜
/// 单——0.4.1 旧制本就是系统 contextMenu，台账
/// 187 改自绘动作面（自家长按识别器＋hitTest
/// 分工＋自绘 sheet）后长按在真机与测试环境双
/// 双失灵，拍板整套退役：本修饰符只挂菜单数
/// 据，识别/呈面/消失全归系统。
/// §265 挂载面纪律不变：只许落在非文本层——气
/// 泡背景层（背景＋内边距带）与行内铬件（图片
/// 卡/文件牌/交付项/引用块/状态行）；不许挂行
/// 内容根。§471 口径变更：「文本区长按归
/// UITextView 原生选字」作废——列表态正文关
/// 直接选字，长按一切落点归菜单/浮排，选字只
/// 从菜单「选择」行进入（141/142 承载本体不动）。
/// 动作集单源不变：呈现时刻经 makeData 组装
/// （ChatView.actionSheetData）——反应走「添加
/// 反应」子菜单，动作项走 actionItems() 逐项搬
/// 家。反应排沿革：台账 187 起走菜单顶部内联
/// ControlGroup，0.50.79 真机被系统拆成逐行陈
/// 列（首行三枚、余者各占一整行）、形态全毁，
/// 0.50.80 热修改子菜单原生陈列；Muse 式浮排
/// 反应条（预览上方独立药丸）另包施工
struct MessageMenuModifier: ViewModifier {
    let isEnabled: Bool
    /// 反应浮排挂钩（DESIGN §343）：非 nil＝本挂载
    /// 点长按先走浮排（开关开＋本条可反应，路由在
    /// ChatView.messageMenu 单点裁定）；nil＝纯系
    /// 统菜单形态（0.50.80 口径逐字不变）
    var floatingBarHook: ((CGRect) -> Void)? = nil
    /// 浮排在场时本条菜单摘除（长按竞速护栏：自家
    /// 手势 0.35s 先行呈浮排并置本旗、系统识别器
    /// 约 0.5s 拍到时无菜单可呈，杜绝双面同呈；浮
    /// 排关后自动复位。VoiceOver 呈菜单走系统路
    /// 径、不经触摸长按，摘除只在浮排在场期间、
    /// 与其互斥不亏入口）
    var menuSuppressed: Bool = false
    /// 呈现时刻组装菜单数据（动作集单源）
    let makeData: () -> ChatRowActionSheetData

    /// 测试装配钉：浮排序由是否在本修饰符生效
    var usesFloatingBar: Bool { floatingBarHook != nil }

    /// 挂载点全局帧（背景 GeometryReader 发布、长
    /// 按触发时刻读——快照原位对齐的定位原点）
    @State private var mountFrame: CGRect = .zero

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            if let floatingBarHook {
                floatingBarBody(content, hook: floatingBarHook)
            } else {
                content.contextMenu { menuContent() }
            }
        } else {
            content
        }
    }

    /// 浮排形态：系统菜单照旧在位（VoiceOver 与未
    /// 触发浮排时的完整入口），另加同位长按手势
    /// （0.35s、与既有手势同时识别不夺触摸——行
    /// 级仲裁〔右滑 pan/滚动/选字〕一律不碰）＋挂
    /// 载帧发布
    @ViewBuilder
    private func floatingBarBody(
        _ content: Content,
        hook: @escaping (CGRect) -> Void
    ) -> some View {
        Group {
            if menuSuppressed {
                content
            } else {
                content.contextMenu { menuContent() }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MessageMenuFrameKey.self,
                    value: proxy.frame(in: .global)
                )
            }
            .onPreferenceChange(
                MessageMenuFrameKey.self
            ) { frame in
                mountFrame = frame
            }
        }
        .simultaneousGesture(
            LongPressGesture(
                minimumDuration: 0.35, maximumDistance: 10
            ).onEnded { _ in
                hook(mountFrame)
            }
        )
    }

    /// 系统菜单内容（单源，两形态共用）：反应走
    /// 「添加反应」子菜单、动作走 actionItems()
    /// 逐项搬家
    @ViewBuilder
    private func menuContent() -> some View {
        let data = makeData()
        if data.canReact {
            Menu {
                ForEach(
                    MessageReactions.palette,
                    id: \.self
                ) { emoji in
                    Button {
                        data.onPickReaction(emoji)
                    } label: {
                        if emoji == data.ownEmoji {
                            Label(
                                emoji,
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(emoji)
                        }
                    }
                }
            } label: {
                Label(
                    "添加反应",
                    systemImage: MessageActionSymbols
                        .react
                )
            }
        }
        ForEach(data.actionItems()) { item in
            Button(
                role: item.isDestructive
                    ? .destructive : nil
            ) {
                item.action()
            } label: {
                Label(
                    item.title,
                    systemImage: item.systemImage
                )
            }
        }
    }
}

/// 挂载点帧发布键（DESIGN §343）：MessageMenu-
/// Modifier 的背景 GeometryReader 发布其在
/// .global 的帧、修饰符自身在背景子树内订阅
/// （订阅点不罩内容子树，嵌套挂载点的帧不串扰）
private struct MessageMenuFrameKey: PreferenceKey {
    nonisolated static let defaultValue: CGRect = .zero
    static func reduce(
        value: inout CGRect, nextValue: () -> CGRect
    ) {
        value = nextValue()
    }
}

/// 右滑引用（0.36.19 立；0.36.26 §95 按生产同
/// 构整件重做）：气泡向右滑，横向拖动显出回复箭
/// 头，拖动途中过线即触发引用——与长按菜单「回
/// 复」同一动作（beginReply），两路并存不互斥
/// （长按是静止按压、右滑是横向拖动，形态不重
/// 叠）。
///
/// 数值口径（沿 §95 定版、Stream 参数单源）：判
/// 定全走 Core SwipeReplyMotion——起滑 30/途中
/// 触发 60/显示封顶 90；起始点排除区（行内自有
/// 横向交互的子区——代码块/表格的横向滚动区）
/// 经 PreferenceKey 发布其在命名坐标空间内的
/// 帧，起始点落在其中则整段忽略。
///
/// 识别层沿革：0.36.26–§264 是 Stream 同构的
/// SwiftUI `.simultaneousGesture(DragGesture)`
/// （0.36.20–0.36.23 的 UIKit 探针桥四轮真机全
/// 灭后退役，P-15）。§265（换代包 5）按用户
/// 2026-11-14 亲令大厂机制③换代：双审计定性
/// simultaneousGesture 的跟踪消耗文本视图触摸
/// 序列、双击选字被截流——识别改走 UIKit 识别
/// 器桥（SwipeReplyPanBridge：UIPanGesture-
/// Recognizer 装宿主滚动视图，方向门＝识别器
/// 子类 began 前位移锁（换代包 8）＋纵滚
/// require(toFail:) 让行），本修饰符只持拖动
/// 状态、经桥的两条回调消费位移/收尾。与桥时
/// 代（0.36.20）的差别：装配走 ScrollViewTap-
/// Dismiss 已验的 ascend 寻面、判据只两条明路
/// （速度门＋失败依赖）、数值口径零自创。
/// 箭头在内容左缘下层：随显形进度淡入/缩放，
/// 越线转武装态，且触发与触觉在越线同一刻发
/// 生（途中触发，不等松手）；松手只做回位
/// §199：internal（原 private）——选字计数证死/回归
/// 测试须装配生产原物验证结构身份，不许在测试侧复
/// 制一份同形修饰符充数
struct SwipeReplyModifier: ViewModifier {
    let isEnabled: Bool
    /// 选区抑制（141/142 根治）：pan 回调时刻直读
    /// （账本选区在场即抑制）——不经 body 重算、
    /// 不翻结构，托管视图零换代（与 OB selecting
    /// 态只切手势 enabled 同构）。默认不抑制
    var isSuppressed: () -> Bool = { false }
    let onReply: () -> Void

    @State private var dragOffset: CGFloat = 0
    /// 整段拖动只触发一次（越线当场置位、松手复位）
    @State private var hasTriggered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            ZStack(alignment: .leading) {
                replyArrow
                content
                    // 命中域＝整条消息容器（Stream
                    // 行同款 contentShape）：行内空
                    // 区起手也能拖（§265 后命中圈定
                    // 由桥的 shouldReceive 按行帧判，
                    // 本 contentShape 只管行内 SwiftUI
                    // 命中形态、语义不变）
                    .contentShape(Rectangle())
                    // §265：UIKit 识别器桥挂行内容
                    // background（零尺寸语义外的全帧
                    // 背景视图、isUserInteractionEna-
                    // bled=false 不夺命中；识别器本
                    // 体装在宿主滚动视图上，见
                    // SwipeReplyPanBridge）
                    .background {
                        SwipeReplyPanInstaller(
                            onPanChanged: { translationX in
                                handlePanChanged(translationX)
                            },
                            onPanEnded: {
                                handlePanEnded()
                            }
                        )
                    }
                    .offset(
                        x: SwipeReplyMotion.displayOffset(
                            for: dragOffset
                        )
                    )
            }
        } else {
            content
        }
    }

    /// 桥回调·拖动中：只消费横向位移写 offset
    /// （判定走 Core 单源）；越线当场触发＋触觉
    /// （整段只一次）。起始点排除已由桥在 sho-
    /// uldBegin 判死（识别器根本不开始），本处
    /// 不再复查
    /// 选区抑制在场时整段不消费：位移归零待命
    /// （拖选字手柄的横移不许把行拖出引用位）
    private func handlePanChanged(_ translationX: CGFloat) {
        if isSuppressed() {
            if dragOffset != 0 { dragOffset = 0 }
            return
        }
        let newOffset = SwipeReplyMotion.dragOffset(
            translationWidth: translationX,
            currentOffset: dragOffset
        )
        dragOffset = newOffset
        if !hasTriggered,
           SwipeReplyMotion.shouldTrigger(
               offset: newOffset
           ) {
            hasTriggered = true
            // 轻触觉（动效宪法表 D，impact
            // .light 落点不变）：与引用落定同
            // 一因果链，只震这一次
            Haptics.impact(.light)
            onReply()
        }
    }

    /// 桥回调·收尾：松手/取消/失败同口——复位触
    /// 发标记、动画回位、不再判触发。选区抑制在
    /// 场时同样只复位（抑制中不判触发，见
    /// handlePanChanged）
    private func handlePanEnded() {
        hasTriggered = false
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.swap,
                reduceMotion: reduceMotion
            )
        ) {
            dragOffset = 0
        }
    }

    /// 左缘回复箭头：显形进度驱动透明度与缩放，过
    /// 线武装态换主色盘（Palette.primaryPale＋onPri-
    /// mary 箭头——2026-11-15 第 85 条 BC-1 同类收
    /// 口：onPrimary 的配对面恒是 primaryPale，旧
    /// primary 盘暗档实算 2.33）——武装与触发同刻
    /// （途中触发口径）
    private var replyArrow: some View {
        let progress = SwipeReplyMotion.revealProgress(
            offset: dragOffset
        )
        let armed = SwipeReplyMotion.shouldTrigger(
            offset: dragOffset
        )
        return Image(systemName: MessageActionSymbols.reply)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(
                armed ? Palette.onPrimary : Palette.inkSecondary
            )
            .frame(width: 30, height: 30)
            .background(
                armed ? Palette.primaryPale : Palette.fieldFill,
                in: Circle()
            )
            .opacity(progress)
            .scaleEffect(0.6 + 0.4 * progress)
            .padding(.leading, 4)
            .accessibilityHidden(true)
    }
}

extension View {
    /// 标记右滑引用排除区：本视图区域内的横滑归
    /// 它自己的横向交互（代码块/表格横滚），不触
    /// 发本行右滑引用。形态沿革：0.36.26 §95 初版
    /// 为背景 GeometryReader 在命名坐标空间经偏
    /// 好键发布帧、行修饰符 @State 收集——行内协
    /// 商型构件兼作手势仲裁、布局期反哺状态，与
    /// 列表行「尺寸确定」通则相悖（大厂差距审计
    /// G-07）；2026-11-23 收口改贴 UIKit 标记视图
    /// （SwipeReplyExcludedMarker），帧由识别器
    /// 桥在判定时刻自 cell 视图层级直算，行内不
    /// 再有布局反哺点
    func swipeReplyExcluded() -> some View {
        background { SwipeReplyExcludedMarker() }
    }
}

/// D3 编辑武装目标（DESIGN §352）：值快照、不持
/// SwiftData 对象（与 SelectionPayload 同律）
private struct EditSentTarget {
    let entryID: UUID
    let rowID: Int
}

/// D3 待确认发稿快照（DESIGN §352）：send() 起手
/// 的快照四件（正文/附件/引用两槽）整包暂存，确
/// 认与取消都不回读发送舱现值
private struct EditSendDraft {
    let text: String
    let attachments: [PendingAttachment]
    let quote: MessageQuote?
    let feedQuote: FeedPostQuote?
    let sourceQuote: SourceQuote?
}

/// D3 编辑横幅槽（DESIGN §352；0.50.88 自 composerCard
/// 抽出独立成型）：武装条件在本槽内求值，宿主卡的组
/// 合类型不随编辑态多一层条件包装（真机启动崩溃热修，
/// 见 DESIGN §354）。形态与引用块同位同式：横幅本体
/// （铅笔＋一行说明＋尾 ✕ 取消——解武装清舱、原条目
/// 无损）＋发丝分隔线同进同出
struct EditSentBannerSlot: View {
    let isArmed: Bool
    let onCancel: () -> Void

    var body: some View {
        if isArmed {
            VStack(spacing: 0) {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                    Text("正在编辑较早的一条消息")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 28, height: 28)
                            .frame(
                                width: OneDayMetrics.minTapTarget,
                                height: OneDayMetrics.minTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                    .accessibilityLabel("取消编辑")
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .padding(.vertical, OneDayMetrics.spacingS)
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, OneDayMetrics.spacingSM)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }
}

/// 「选择」sheet 载荷（0.4.1）
private struct SelectionPayload: Identifiable {
    let id = UUID()
    let text: String
}

/// 分享载荷（§330）：原生面 UIKit 行菜单的「分
/// 享」动作落点——ShareLink 是 SwiftUI 视图、
/// UIKit 菜单内无处安放，改经本状态口开系统分
/// 享单（与 gen3 面 ShareLink 同为系统分享件、
/// 同载荷）
private struct MessageSharePayload: Identifiable {
    let id = UUID()
    let text: String
}

/// 系统分享单承载（§330）：UIActivityViewCon-
/// troller 薄包装，与 FilesView 的 FileShare-
/// Sheet 同式（彼以文件 URL、本以消息纯文本）
private struct MessageShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}

/// 「选择」承载页（0.4.1 立、§152 升级）：整条消息
/// 的纯文本在系统 sheet 里跨段划选任意部分——气
/// 泡内选字粒度是单个文本块（§152.3），跨块任意
/// 选段的口子保留在本页。0.4.1 时本页用 SwiftUI
/// Text＋.textSelection（iOS 26 下只有整段菜单），
/// §152 起换 SelectableInlineText（UITextView 真
/// 选段：双击选词／拖柄扩选／系统编辑菜单），与气
/// 泡内同源同口径
private struct SelectableTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SelectableInlineText(
                    paragraphs: [.plain(text)],
                    textStyle: .body,
                    foreground: Palette.bodyInk
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OneDayMetrics.pageGutter)
            }
            .navigationTitle("选择文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

/// 待发附件（0.2.1）：图片已统一转 JPEG（见 appendImage）；
/// 文件只存名与数据——直发未开放，发送时如实提示（见 send()）
/// §410：选文件接入的汇总产物——后台读盘段
/// （ChatView.loadPickedFilesSync）与主线入条段之间
/// 传递；名单与 FileIntake 汇总函数一一对应
struct PickedFilesLoadOutcome: Sendable {
    var accepted: [PickedFilePayload] = []
    var oversized: [String] = []
    var unreadable: [String] = []
    var transcoded: [String] = []
    var undecodable: [String] = []
}

/// §410：单个已接入文件的上传载荷（转码后字节）
struct PickedFilePayload: Sendable {
    let name: String
    let data: Data
}

private struct PendingAttachment: Identifiable {
    let id = UUID()

    enum Kind {
        case image(Data)
        case file(name: String, data: Data)
    }

    let kind: Kind

    var imageData: Data? {
        if case .image(let data) = kind { return data }
        return nil
    }

    var fileName: String? {
        if case .file(let name, _) = kind { return name }
        return nil
    }

    /// 文件真发送载荷（0.36.29）：名＋数据成对取，
    /// 上传与拼装只认它，不再只取名字
    var filePayload: (name: String, data: Data)? {
        if case .file(let name, let data) = kind {
            return (name, data)
        }
        return nil
    }
}

/// 文件上传失败（0.36.29）：点名文件＋人话原因，
/// send 整条拦下时拼报错文案用，不静默吞单个文件
private struct FileUploadFailure: Error {
    let fileName: String
    let reason: String
}

/// 系统相机包装：模拟器无相机，入口在附件菜单里已按可用性禁用
private struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (Data) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ controller: UIImagePickerController, context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.85) {
                parent.onImage(data)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

/// 三点指示：已受理未出字时的等待信号（iMessage
/// 输入指示器形态，§426 缺陷四按参照口径落数：
/// 点径 8、点距 4、周期 1.4s、错峰 0.22s、透明
/// 度 0.3↔1.0 正弦脉动；Reduce Motion 时静止）。
/// 0.2.5 起随助手消息一同入泡。相位函数为钉测
/// 读口（测动画状态、不测像素）
struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let dotDiameter: CGFloat = 8
    static let dotSpacing: CGFloat = 4
    static let cycleDuration: Double = 1.4
    static let stagger: Double = 0.22

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: Self.dotSpacing) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Palette.inkMuted)
                        .frame(
                            width: Self.dotDiameter,
                            height: Self.dotDiameter
                        )
                        .opacity(
                            Self.opacity(
                                at: t, index: index,
                                reduceMotion: reduceMotion
                            )
                        )
                }
            }
        }
        .accessibilityLabel("正在生成")
    }

    /// 逐点透明度：正弦波错峰——第 i 点相位滞后
    /// i×stagger 秒，波形平方收峰（亮段短、暗段
    /// 长，与参照指示器的呼吸感同族）
    static func opacity(
        at t: TimeInterval, index: Int, reduceMotion: Bool
    ) -> Double {
        if reduceMotion { return 0.6 }
        let speed = 2 * Double.pi / cycleDuration
        let wave = sin(
            t * speed - Double(index) * stagger * speed
        )
        return 0.3 + 0.7 * max(0, wave) * max(0, wave)
    }
}

/// 流式光标已移至 StreamingText.swift（与流式渐显组件
/// 同文件，文末词元同流排布）。

