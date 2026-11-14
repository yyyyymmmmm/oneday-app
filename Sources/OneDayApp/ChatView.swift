import OneDayDesign
import OneDayCore
import Photos
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
/// 异构件才成卡，见 assistantBubble 注），填充泡口径作废。
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
    /// §153：顶栏模型分组选择面（sheet）开关
    @State private var showModelPicker = false
    /// 隐藏服务商待确认（§158）：点隐藏的组正是服务
    /// 端当前默认所在组时先弹后果确认（B6 收编口径：
    /// 仅有后果才弹），确认后才走 AppState 落账
    @State private var pendingHideGroup: ChatModelGroup?

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
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]

    @State private var currentThreadID: UUID?
    /// 留痕回响数据源（P2 会话包）：进页/切线程与每
    /// 轮生成落定时经 OneDayBridgeClient 拉桥侧留痕
    /// 账（主线全量、旁聊按 targetId），呈现收窄在
    /// Core TraceEchoPolicy；拉取失败保留旧值（见
    /// refreshEchoTraces）
    @State private var echoTraces: [BridgeTrace] = []
    @State private var input = ""
    /// 语音输入控制器（0.36.6，§71）：端上识别、录音
    /// 条占住发送舱；文本经 onTextChange 回写 input
    @State private var dictation = DictationController()
    /// 非 nil 表示正在生成：值是已累积的流式文本
    @State private var streamingText: String?
    /// 流式思考（reasoning）已发布快照（0.5.1，§32）：
    /// 非 nil 表示本轮已收到思考增量；思考原文经发布
    /// 闸合并后写入，呈现走直播区折叠单元（live-
    /// ReasoningBlock，0.36.10 起按事件序落位）
    @State private var streamingReasoning: String?
    /// 本轮首个思考增量的到达时刻（0.5.1）：折叠单元
    /// 实时计时与落盘 reasoningSeconds 的计时起点
    @State private var reasoningStartedAt: Date?
    /// 正文/思考两条通道的发布合并闸（0.5.1，§32，
    /// OneDayCore.StreamPublishGate）：增量先攒缓冲、
    /// 按 80ms 窗或 64 字阈值合并发布，与 streamFollow-
    /// Gate（管滚动）分工互不替代；run 驱动起止归零
    @State private var contentPublishGate = StreamPublishGate()
    @State private var reasoningPublishGate = StreamPublishGate()
    @State private var sendTask: Task<Void, Never>?
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
    /// 0.2.1：非错误提示条。§140 提示纪律起分档自消：
    /// 呈现状态与代号在 Core NoticePresentation，赋值
    /// 一律走 showNotice（中性 5s／重要 8s 自清）；错
    /// 误族走 errorMessage、常驻不动（动作位原注记
    /// 「归二包」，基础止血包 P2 已兑现：失败轮次的
    /// 横幅带「重新发送」，见 failedResendTarget）
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
                    appState.pendingSettingsRoute = .models
                    appState.settingsSheetRequested = true
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
    @State private var settleGeneration: Int?
    @State private var settleFallbackTask: Task<Void, Never>?
    /// 键盘帧落定标记（手感 A 档，键盘锚底事件驱
    /// 动）：Will 路置假（帧在途）、Did 路置真（帧
    /// 已落定）；静息（无键盘动画）恒真。锚底请求
    /// 据此分流：已落定当场滚、在途记挂账等落定兑
    /// 现——代旧 300ms 定时猜测，见
    /// anchorToBottomAfterKeyboard
    @State private var keyboardFrameSettled = true
    /// 键盘锚底挂账：帧在途时记一笔，DidChangeFrame
    /// 落定刻兑现（settleKeyboardAnchor）；失焦／切
    /// 线程即作废
    @State private var keyboardAnchorPending = false
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
    /// 流式跟随滚动节流闸（0.4.2，§27）：OneDayCore
    /// 纯逻辑记账，每 ≥40 字放行一次无动画贴底；流结
    /// 束与切换线程时归零（见 messageList 的 onChange）
    @State private var streamFollowGate = StreamFollowGate()
    /// 流式跟随贴底的结算挂账（割裂感 A 止血档 A3）：
    /// 代号每登记一次自增（新登记/流结束都令旧登记
    /// 作废），pending＝有一贴待结算后执行；执行口
    /// settleStreamFollow 双守卫消费（见 messageList
    /// 的 streamingText 与 composerBottomSpace 两处
    /// onChange）
    @State private var streamFollowSettleGeneration = 0
    @State private var streamFollowPending = false
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
    /// 列表可视高（0.3.5，§20）：onScrollGeometryChange
    /// 回写，喂消息内容栈的撑满 minHeight——点空白收键
    /// 盘的命中域（见 messageList 撑满注）
    @State private var listViewportHeight: CGFloat = 0
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
    /// 文件；纯内存、进程被杀即灭（条目已落盘的远端
    /// 路径在场时优先走路径、不经本格）
    @State private var failedFilePayloads:
        [UUID: [(name: String, data: Data)]] = [:]
    /// 基础止血包（P1/P2）：最近一轮失败的用户条目
    /// id——错误横幅据此出「重新发送」动作位（仅当
    /// 条目属当前线程且仍挂失败标记时呈现，呈现判定
    /// 在 errorBanner 调用点）
    @State private var failedResendEntryID: UUID?
    /// 基础止血包（P7）：本轮正处文件上传段的事实位
    /// ——等待呈现据此说上传中、不再冒充生成中；进
    /// 度百分比归上传正解包，本位只管文案分型
    @State private var isUploadingFiles = false
    /// 聊天可靠性包：发送准备失败被保留的待发条目，
    /// 其文件载荷只活在内存——按条目 id 暂存原待发
    /// 附件，供同一次运行内点按重发时重新上传；进程
    /// 重启后暂存不在，文件载荷无法复原（条目正文与
    /// 本地图仍在，重发退化为纯文本＋图片，见报告
    /// 边界节）
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
    // §152 修订二：附件面板内容实测高（面板经
    // PreferenceKey 回报），sheet detent 贴内容用
    @State private var attachPanelContentHeight: CGFloat = 0
    // §154 热修：detent 钳顶用的宿主真高——本页根
    // 层 onGeometryChange 回写（sheet 之外的呈现方
    // 几何）。§152 误用 sheet 内容内 GeometryReader
    // 所量（那是 detent 驱动的 sheet 自身高），钳顶
    // 按 0.75 倍自噬塌陷、面板等于没出现，自此只
    // 认本值；未回写（0）时 detent 决策回落默认档
    @State private var hostViewHeight: CGFloat = 0
    // §186（2026-11-12，承载换代）：输入舱顶→窗口底
    // 距离的实测回报（ComposerGuideHost 在布局拍回
    // 写）——消息列表底 contentMargins ＝本值＋
    // spacingS（§176 单点边距的现行落点，见列表侧
    // 注）。首报到达前以 168 兜底（现行形态静止总量
    // 的同档近似：坞 83＋舱高约 77＋边距 8），host
    // 首个布局拍即以实测覆盖、不留陈值
    @State private var composerBottomSpace: CGFloat = 168
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
    /// R1（修正）：键盘帧更新包的收件槽——由 Com-
    /// poserGuideHost 控制器（唯一解析点）在键盘事
    /// 件拍直写（帧顶已转窗口坐标），本页 onChange
    /// 以其动画参数原值整包写进快照（见 body 根的
    /// onChange(kbFrameUpdate)）。首版由本页 .onRe-
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
    /// 0.6.0：通知 sheet（顶栏铃铛点开，总览桥驱动）
    @State private var showNotifications = false
    /// 锚点点亮的条目 id（§165）：点达锚定行时置位，
    /// 行底色以 Palette.primaryTint 点亮、2.5 秒后清
    /// （沿 §123 枢纽聚焦同手法）；消费锚点请求的
    /// Task 持有清零，不叠加多行点亮
    @State private var anchorHighlightEntryID: UUID?
    /// 0.4.0（§3.4）：服务端会话导入进行中的 id（防重复
    /// 触发并发导入同一条会话）
    @State private var importingSessionID: String?
    /// 基础止血包（P6）：导入失败的重试上下文（会话
    /// id＋频道出处）——输入舱上方留一条重试行，点按
    /// 以原出处重走导入；导入成功/发起新导入/用户关
    /// 掉即清
    @State private var importRetryContext:
        (sessionID: String, channelID: String?)?
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
                appState.pendingFeedQuotesByThread[$0]
            }
        }
        nonmutating set {
            guard let currentThreadID else { return }
            if let newValue {
                appState.pendingFeedQuotesByThread[currentThreadID] =
                    newValue
            } else {
                appState.pendingFeedQuotesByThread
                    .removeValue(forKey: currentThreadID)
            }
        }
    }
    /// 0.7.0（M1 轻保活）：列表首个可见条目 id（滚动锚
    /// 记录用，由 onScrollTargetVisibilityChange 回写）
    @State private var topVisibleEntryID: UUID?
    /// 0.4.1：长按「选择」的纯文本 sheet 载荷
    @State private var selectionPayload: SelectionPayload?
    /// §152：正文选区在场的条目 id（选字期间关该行
    /// 右滑引用防拖柄误触）；消选经延迟清账（块间
    /// 切换选区时旧块先报消、新块后报选，立即清账
    /// 会误关新选区的行保护）
    @State private var activeSelectionEntryID: UUID?
    @State private var selectionClearTask: Task<Void, Never>?
    /// 0.8.0（P1 富内容）：图片全屏查看与文件 QuickLook
    /// 预览的呈现载荷；流式工具卡列（累积完成即入列、
    /// 本轮收尾落盘，见 driveRun）
    @State private var imageViewerSession: ImageViewerSession?
    /// §125：文件牌点开统一进中间页（FileOpenView
    /// sheet），旧「点牌直达 QL（filePreviewItem）/
    /// 不可预览直落分享单（fileShareItem）」两件套呈
    /// 现状态退役——分享单改由中间页内的动作触发
    @State private var fileOpenTarget: FileOpenTarget?
    @State private var liveToolCards: [ToolCard] = []
    /// 直播区事件序标记（0.36.10，诊断 D3-10）：思考/
    /// 工具/正文按首达顺序记位，渲染层（liveZone）据
    /// 此交错呈现——旧形态恒「卡列在前、思考正文在
    /// 后」，与事件真实先后倒序
    @State private var liveOrder: [LiveOrderItem] = []

    private enum LiveOrderItem: Equatable {
        case reasoning
        case text
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
              let mainID = appState.sideChats.mainThreadID else { return false }
        return SideChatClassifier.zone(localThreadID: thread.id, mainThreadID: mainID) == .main
    }

    private var isStreaming: Bool { streamingText != nil }

    // MARK: - §158 隐藏服务商（本面管理动作）

    /// 隐藏请求分流：组键取不到（具名组）不处理；组
    /// 里带默认标记＝服务端当前默认正走这组——先弹
    /// 后果确认（pendingHideGroup 的确认框在本面
    /// sheet 上声明）；其余直接落账隐藏。隐藏全程只
    /// 动本机呈现账（AppState），服务端与执行链零触碰
    private func requestHideProviderGroup(_ group: ChatModelGroup) {
        guard ProviderGroupVisibility.groupKey(for: group) != nil
        else { return }
        if ProviderGroupVisibility.containsDefault(group) {
            pendingHideGroup = group
        } else {
            commitHideProviderGroup(group)
        }
    }

    private func commitHideProviderGroup(_ group: ChatModelGroup) {
        guard let key = ProviderGroupVisibility.groupKey(for: group)
        else { return }
        appState.hideProviderGroup(key: key)
    }

    /// 本会话模型账的取键入参（§216 账合一派生）：
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
                && thread?.id == appState.sideChats.mainThreadID,
            mainServerSessionID: appState.sideChats.mainServerSessionID
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
        // §154 热修：宿主真高回写（附件面板 detent
        // 钳顶的唯一屏高来源，见 hostViewHeight 注；
        // 本页根几何独立于任何 sheet 呈现，不随
        // detent 变化）
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { _, newHeight in
            hostViewHeight = newHeight
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
        //（AppState.hubOpenRequested 置位—消费—清零，
        // 与 cronCreateRequested 同式）：抽屉先切聊天格
        // 再置位，本页在场消费、开枢纽 sheet
        .onChange(of: appState.hubOpenRequested) { _, requested in
            if requested {
                appState.hubOpenRequested = false
                showHub = true
            }
        }
        // 0.4.1：「选择」纯文本 sheet（长按菜单发起，
        // 选型见 DESIGN-V4 §26）
        .sheet(item: $selectionPayload) { payload in
            SelectableTextSheet(text: payload.text)
        }
        // 选择面使用唯一、稳定的宿主；胶囊全量/紧凑档
        // 与 safeAreaBar 的布局切换不再重建呈现锚点。
        .sheet(isPresented: $showModelPicker) {
            modelPickerSheet
        }
        // 0.8.0（P1）：图片点开全屏查看（本地图与历史
        // 服务端图共用一个查看器）；文件牌点开走系统
        // QuickLook（字节先经文件下载通道落临时目录）
        // 0.36.4：查看器换代——集合载荷（同线程图片序、
        // 可翻页）＋ImageViewerView 双态；呈现承载走
        // UIKit zoom 转场（本页无导航栈，见 Zoom-
        // TransitionCover 注）
        .fullScreenCover(item: $imageViewerSession) { session in
            ZoomTransitionCover {
                ImageViewerView(
                    items: session.items,
                    initialIndex: session.initialIndex
                )
            }
        }
        // §125：文件打开页（中间页）——聊天侧点牌的
        // 唯一落点（图片仍走上方全屏查看器、不经此页）
        // §129：失败页「让智能体重新发」的落点——预
        // 填直接落当前线程输入舱并聚焦（同线程不走
        // setDraft 的换线程加载路），发不发由用户点
        // 发送为准
        .sheet(item: $fileOpenTarget) { target in
            FileOpenView(
                target: target, origin: .conversation,
                onRequestResend: { prefill in
                    fileOpenTarget = nil
                    if currentThreadID != nil {
                        input = prefill
                        composerFocusHandle.focus()
                    }
                }
            )
        }
        // 0.4.1：引用是发送舱的临时态，切换线程即作废，
        // 不许跨线程带过去；0.7.0 两处增补——草稿轻保活
        // （M1）与分流种子转入（M4），见下
        .onChange(of: currentThreadID) { oldID, newID in
            // 0.30.0（落点记忆）：当前线程恒落盘——冷启/
            // 视图重建时由 ChatLandingResolution 恢复上
            // 次对话（页签不与主线绑定）；这是全仓唯一
            // 写入点，置空（删当前线程）即清记录
            appState.sideChats.setLastThreadID(newID)
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
                appState.pendingFeedQuotesByThread
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
            // 0.4.2：流式节流闸不跨线程带账
            streamFollowGate.reset()
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
        .onChange(of: appState.drawerThreadSelection) { _, id in
            if let id {
                appState.drawerThreadSelection = nil
                currentThreadID = id
            }
        }
        // §210：待发引用表变化（讨论写入/发送消费/
        // ✕ 摘除都经此表）时，若当前线程名下有引用
        // 在场就收口呈现侧动作——人已在目标线程内
        // 时写入即聚焦，不等切换事件（§208 种子制的
        // 本处理已随种子退役）
        .onChange(of: appState.pendingFeedQuotesByThread) { _, _ in
            applyPendingFeedQuoteIfNeeded()
        }
        // 0.4.5：抽屉删掉的正是当前线程时置空（计算属
        // 性随之落到最近线程，与旧版 deleteThread 内
        // 直改 currentThreadID 的语义一致）
        .onChange(of: appState.drawerDeletedThreadID) { _, id in
            if let id {
                appState.drawerDeletedThreadID = nil
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

    /// 聊天主面：顶栏是玻璃件＋身份胶囊（0.4.0 起渐隐
    /// 带 topFade 已删、见 chatSurface；0.4.3 起顶栏改
    /// 挂消息列表的 .safeAreaBar 注册，不再悬浮覆盖）；
    /// 底部发送区 0.2.6 起退出覆盖层、回到布局流——
    /// 消息列表以安全区 bar 承载发送舱（0.2.6–0.4.2 为
    /// .safeAreaInset，0.4.3 改 .safeAreaBar 注册，见
    /// messageList 与 §28）。换代原因：0.2.4/0.2.5
    /// 连着两版在覆盖式 ZStack 里跟键盘打架（键盘弹起态
    /// 发送舱膨胀成空玻璃泡，真机实证），根子是自研悬浮层
    /// 在跟系统的键盘布局通道抢地盘；调研 Exyte/Chat、
    /// Stream Chat SwiftUI、MessageKit 三家成熟方案后定案
    /// 走「列表＋发送区同处布局流」的系统通道（Exyte 与
    /// Stream 的共识结构，调研与取舍全文见 DESIGN-V4 §10）：
    /// 键盘升起时系统安全区把发送区整段顶到键盘上方、交互
    /// 收起跟随安全区动画，高度永远只由内容在单次布局里
    /// 决定，不再有全屏提议经覆盖层污染胶囊的链路。
    /// 取舍如实记：键盘收起态消息不再从发送舱背后流过
    /// （inset 是留位不是覆盖），换来键盘联动的系统级精确
    /// 与高度问题的整类消除；玻璃胶囊的长相不变（胶囊是
    /// 内容、不是布局机制）。（0.4.3 注：注册 safeAreaBar
    /// 后滚动内容可从条下穿过并被边缘效果化开——那是效
    /// 果层的穿过，布局留位与键盘通道不变，见 §28）
    /// 原 NavigationStack＋toolbar 在 0.2.4 已撤销：栈内无
    /// 任何 push 依赖（全仓核查），顶栏以悬浮覆盖层实现。
    /// （0.4.3 注：顶栏已改挂列表的 safeAreaBar 注册、不
    /// 再经本容器的 overlay 悬浮，见下）
    /// （§186 注，2026-11-12：底部发送区的承载再换代——
    /// 退出列表 safeAreaBar 注册，改由 ComposerGuideHost
    /// 以 UIKit keyboardLayoutGuide 在同层 ZStack 托管，
    /// 列表底留位改实测 contentMargins；换代原因与证据
    /// 见 ComposerGuideHost 文件头与 DESIGN §186。上文
    /// 0.2.6/0.4.3 的「回布局流」结论就此更新为「留前景
    /// 层级内、钉位改走引导线」：不在安全区栈里、也不回
    /// 覆盖层推算，两条旧路都不走）
    /// 输入舱宿主 overlay（自 chatSurface 抽出单
    /// 独成件：主链表达式过重、类型检查超时——拆
    /// 表达式是编译器给的处方，语义零改动）
    @ViewBuilder
    private func composerHostOverlay(
        _ proxy: ScrollViewProxy
    ) -> some View {
        ComposerGuideHost(
            bottomSpace: $composerBottomSpace,
            topSafe: $windowTopSafeInset,
            pocketHeight: $kbSnapshot.pocketHeight,
            dockTop: $kbSnapshot.dockTopInWindow,
            keyboardFrame: $kbFrameUpdate,
            windowHeight: $kbSnapshot.windowHeight,
            scrollHandle: listScrollHandle
        ) {
            bottomBar(proxy)
        }
    }

    /// 顶簇宿主 overlay（同上拆分）
    @ViewBuilder
    private var topBarHostOverlay: some View {
        TopBarGuideHost(
            barHeight: $topBarHeight,
            scrollHandle: listScrollHandle
        ) {
            topBarCluster
        }
    }

    private var chatSurface: some View {
        ScrollViewReader { proxy in
            // §186（2026-11-12，承载换代）：输入舱退出
            // 列表的 safeAreaBar 注册，改由 Composer-
            // GuideHost 托管（整栈仍在前景层级内、随抽屉前景滑
            // 动；列表与舱同树同 proxy，贴底四路的调用
            // 面一字不变，见 ComposerGuideHost 文件头
            // 与 messageList 的 §186 注）。回底钮不在
            // 此浮层（§124 三代落位，见下条沿革注）
            // §193（2026-11-13，用户拍板锚定式重构）：
            // 输入舱退出根层定尺寸——列表为根、舱改挂
            // .overlay 次级层（次级视图被提议主视图已
            // 定尺寸、不参加父级尺寸协商，OpenSwiftUI
            // 次级视图语义），舱帧内落位由其控制器以
            // UIKit 约束锚定（坞顶/窗口键盘引导线，
            // 见 ComposerGuideHost 文件头 §193）。根
            // ZStack 的「盒」自此不存在：列表与顶栏
            // 的位置只由列表自身的安全区体系决定，
            // 舱侧固有尺寸再飘也顶不动任何栏位。§192
            // 的 layoutPriority 断链被本式取代（同为
            // 退出协商，overlay 是结构性的）
            messageList(proxy)
                .overlay {
                    composerHostOverlay(proxy)
                }
                // §195：顶簇同挂本复合面的 overlay 次
                // 级层、由 TopBarGuideHost 以 UIKit 约
                // 束锚定窗口顶（落位只认窗口顶安全区，
                // 与本面/坞/键盘脱钩，详见该文件头）；
                // 与输入舱同层同式、互不承载
                .overlay {
                    topBarHostOverlay
                }
            // （§124 沿革注，本层与回底钮的关系）：回底
            // 钮三代浮层落位全败——0.41.0 挂发送区容器
            // overlay＋负偏移→命中被宿主 frame 剪枝（点
            // 不动）；0.46.1 迁 overlay＋PreferenceKey
            // 发布 frame 算落位→发布链真机未交付（整钮
            // 消失，§121）；0.47.1 改读宿主自身 safeArea-
            // Insets.bottom 推算→键盘态同一截键盘高被
            // frame 与 inset 两套参照扣两遍、钮高出一截
            // 键盘（§124 诊断）。三轮共同根因＝落位一直
            // 在不属于输入舱的坐标系里推算；§124 正修＝
            // 钮搬进发送区布局流本体（bottomBar 内输入
            // 舱上方一行），落位由构造保证、零推算。
            // §186 换代后此结论不变：钮仍在 bottomBar
            // 本体内（overlay 托管内容就是 bottomBar
            // 整栈），落位改由托管控制器的
            // 约束构造保证——仍是「在输入舱自己的坐标
            // 系里」，不回浮层推算
        }
        // §185：背景层穿到屏幕四边——上下栏纯色块修
        // 复，页面背景单独忽略安全区铺满整屏，栏下内
        // 容能流到位时边缘即由滚动效果化开
        .background {
            Palette.chatSurface
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
        .toolbar(
            kbSnapshot.isKeyboardUp ? .hidden : .visible,
            for: .tabBar
        )
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
        // Bridge 延拍口径）。§152 修订二：detent 自
        // .medium 改内容实测高（面板经 Preferen-
        // ceKey 回报、AttachmentPanelLayout 钳顶），
        // 高度贴内容不留死空；未授权态与确认行增减
        // 都经同一量测自适应。确认入条是终结动作不
        // 呈现下一层，直接收面板后批量取数入条（多
        // 选逐张走单张同一取数路，§152）。§154 热
        // 修：钳顶屏高与量测保真两处已改（见下方
        // sheet 本体的 §154 注），§152 的贴高/多选
        // 收益不动
        .sheet(isPresented: $showAttachPanel, onDismiss: {
            // §154 热修：收面板即清量测——下次打开恒
            // 自 .medium 兜底起、量到再贴合，不留跨
            // 次陈值喂 detent
            attachPanelContentHeight = 0
        }) {
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
                        DocumentPickerBridge.present { urls in
                            loadPickedFiles(urls: urls)
                        }
                    }
                },
                onAddVideo: {
                    afterAttachPanelDismiss { showVideoPicker = true }
                }
            )
            // §154 热修：量测取理想高——面板根挂
            // fixedSize 纵向保真，内容高不随 detent
            // 的提案伸缩（§152 旧构里横滑条会被撑满
            // 回灌与 sheet 等高的伪量测）
            .fixedSize(horizontal: false, vertical: true)
            .onPreferenceChange(AttachmentPanelHeightKey.self) { height in
                attachPanelContentHeight = height
            }
            // §154 热修：钳顶屏高改喂宿主真高（本页
            // 根层 onGeometryChange 回写，独立于
            // sheet）；未回写（0）时决策回落默认档，
            // 面板照常打开。§152 旧构把 Geometry-
            // Reader 套在 sheet 内容里量「屏高」——
            // 量到的是 sheet 自身高，钳顶自噬塌陷、
            // 点「+」等于没反应（0.50.16 真机报障）
            .presentationDetents(
                attachPanelDetents(screenHeight: hostViewHeight)
            )
            .presentationDragIndicator(.visible)
        }
        // 0.36.31（件二）：.fileImporter 已删——侧载
        // 设备类上其 coordinator 会死在被拆的呈现上
        // 下文里、点「打开」无反应（诊断 file-picker-
        // batch-diagnosis-20261111 定案）；文件选择
        // 改由 DocumentPickerBridge 自顶层 VC 命令
        // 式呈现，结果直喂 loadPickedFiles，不经本链
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
        // 0.4.0（§3.4）：消费待续聊会话（四处入口经
        // AppState.pendingChatSessionID 置位、ContentView
        // 切聊天格，本页导入历史后进聊天续聊）
        .onChange(of: appState.pendingChatSessionID) { _, id in
            if let id {
                Task { await consumePendingChatSession(id) }
            }
        }
        // §165（锚点包）：点达原对话的锚定行——枢纽记
        // 录行/通知回执置位 approvalAnchorRequest，本
        // 页消费：切线程（与抽屉切线同字段）→等条目
        // 进渲染→滚动定位＋点亮→清零；目标线程/条目
        // 找不到如实落空（不滚、不亮），不许假定位
        .onChange(of: appState.approvalAnchorRequest?.threadID) {
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
            }
        }
        // 0.36.15：离开聊天页关预热总闸并弃置产物
        .onDisappear {
            dictation.disarmPreheat()
        }
        .task(id: currentThreadID) {
            await resumeRunIfNeeded()
            // 0.36.21：进/切对话刷新待批（就地卡数据源，
            // 与枢纽共享同一 store）
            await appState.sharedHubStore().refreshApprovalForChat()
            // P2 会话包：进/切对话刷新留痕回响（主线/
            // 旁聊卡数据源，不走推送——P0 审计口径；
            // 生成落定沿另有一次补刷，见 isStreaming
            // 下降沿注）
            await refreshEchoTraces()
        }
        .onAppear {
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
            // §216.2：化石迁移的入参必须取对齐前的一
            // 对 id 副本——ensureMainThread 会把钦定线
            // 程绑定强制对齐到 store 副本，事后无从分
            // 辨分叉；裁决在落点后异步跑（须回读服务
            // 端会话行），与下方链接预热同批发
            let fossilPair = (
                threadBinding: appState.sideChats.mainThreadID
                    .flatMap { id in
                        threads.first { $0.id == id }?
                            .serverSessionID
                    },
                storeID: appState.sideChats.mainServerSessionID
            )
            let mainID = ensureMainThread()
            // 0.4.5：同理补消费抽屉线程选择（从其他格开
            // 抽屉选线程切过来时，本页可能尚未挂载、
            // onChange 不重放）
            if let id = appState.drawerThreadSelection {
                appState.drawerThreadSelection = nil
                currentThreadID = id
            } else if appState.pendingChatSessionID == nil {
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
            // 本页首次出现时若已有待续聊会话（如从其他格
            // 首次切入），onChange 可能先于挂载发生、在此补消费
            if let id = appState.pendingChatSessionID {
                Task { await consumePendingChatSession(id) }
            }
            // 0.27.0：主线链接预热（未链才走；失败原因
            // 落 SideChatStore 设置页可见、发送前还会
            // 再试——旧「失败静默」口径已作废）
            Task { await ensureMainLink() }
            // §216.2：主线模型化石一次性迁移（钦定键
            // 下若有 B 收口写进的化石存量且与线程账冲
            // 突，落地对齐后会成合一账唯一存量、三面
            // 全落化石——按线程账现值归一，规则见
            // Core MainlineModelFossilMigration）
            if let mainID {
                Task {
                    let action = await appState
                        .runMainlineModelFossilMigrationIfNeeded(
                            threadServerSessionID:
                                fossilPair.threadBinding,
                            threadID: mainID,
                            storeServerSessionID: fossilPair.storeID
                        )
                    if action != .keep {
                        ChatDiagTrace.record(
                            "主线模型化石迁移：钦定键存量与服务端会话行 model 一致且与线程账冲突，已按线程账现值归一（\(action)）"
                        )
                    }
                }
            }
            // 0.32.1（F05 止血）：原选模型已停用、选择
            // 被落回默认时的一次性如实提示——消费后落
            // 回值落盘、不再重现；已有提示在显时不抢占
            if let modelNotice = appState.modelFallbackNotice {
                if !noticePresentation.isPresenting {
                    showNotice(modelNotice)
                }
                appState.consumeModelFallbackNotice()
            }
        }
        // 0.7.0（D2 回告）：总览快照随前台 30 秒轮询换新
        // 时顺带拉新通知——回告卡与铃铛/通知 sheet 读
        // 同一份通知状态，不另开轮询
        .task(id: overviewStore?.snapshot?.generatedAt) {
            if let overviewStore {
                await overviewStore.loadNotifications(appState: appState)
            }
        }
        .task {
            await startDemoStreamIfNeeded()
        }
        .task {
            await appState.refreshModelCatalog()
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
            if appState.approvalAnchorRequest != nil {
                consumeApprovalAnchorRequest()
            } else if appState.hubDestinationRequest != nil {
                appState.hubOpenRequested = true
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
        .fullScreenCover(isPresented: $showHub) {
            AgentHubView(mode: .sheet, onApprovalChanged: {
                Task { await overviewStore?.refresh(appState: appState) }
            })
        }
        // 0.36.6：语音输入权限预备页（问前先讲用途，
        // 续编 S1–S4；点麦克风且权限未定时才出现）
        .sheet(isPresented: $dictation.showPrep) {
            DictationPrepSheet(controller: dictation)
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
    /// GuideHost 锚定托管、内容一字未动）：顶栏＋
    /// 进展胶囊。顶簇实高由宿主量测回报（见
    /// TopBarGuideHost），列表顶留位据此记账
    private var topBarCluster: some View {
        VStack(spacing: OneDayMetrics.rowInnerGap) {
            headerBar
            ProgressCapsuleView(
                currentSessionID: currentThread?.serverSessionID,
                onOpenSession: { sessionID in
                    appState.pendingChatSessionID = sessionID
                }
            )
        }
    }

    /// 顶栏（0.3.8 第 30/31 条布局，0.4.0 A 案改；0.4.3
    /// 起注册为消息列表的 .safeAreaBar(edge: .top)、脱
    /// 离悬浮覆盖，§28；§195 起注册退役、改由
    /// TopBarGuideHost 锚定托管，见 topBarCluster）：
    /// 中央组＝枢纽头像钮＋模型胶囊（§202 路线 B；
    /// 0.6.0–0.50.26 的一颗装双域身份胶囊退役）；
    /// 左右圆钮 0.23.0 起走系统玻璃（审计 T2，此前
    /// 为白浮纸、与胶囊玻璃并置两材质）。
    /// 左钮字形改汉堡线（第 31 条：与抽屉的隐喻对齐，
    /// 「分栏」图标 sidebar.left 退场）。顶栏总高约
    /// 40＋次行 18，比 0.3.7 的两行胶囊更紧凑（旧胶囊
    /// 167pt 宽纯文字、无头像无 Hermes 名——第 30 条点名）
    private var headerBar: some View {
        VStack(spacing: OneDayMetrics.rowInnerGap) {
            HStack(alignment: .center, spacing: 0) {
                Button {
                    // 0.4.5：开抽屉只写语义状态，壳层据
                    // drawerPresented 执行推式动画（并先
                    // 收键盘，见 ContentView.setDrawer）
                    appState.drawerPresented = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        // 两钮共用 HeaderButtonSpec（直径 40／
                        // 字形 20 regular）；0.3.8 画法换白浮
                        // 纸（odFloatPaper：近白＋发丝边＋柔影）
                        // 0.23.0（审计 T2）：圆钮白浮纸换系统
                        // 玻璃 .glassEffect(.regular)——与同
                        // 排身份胶囊同族（此前同排两材质并置
                        // 可辨）；视觉盘 40 不变，命中域外扩
                        // 44（命中域审计，视觉盘居中）
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

                Spacer(minLength: OneDayMetrics.spacingS)

                // 顶栏三件套之中（§202 路线 B）：中央组
                // ＝枢纽头像钮＋模型胶囊两个独立元素——
                // 0.6.0–0.50.26 的「一颗胶囊装双点按域」
                // （身份域开枢纽／模型域开选择面）整套退
                // 役：融域命中真机反复派错、0.50.26 终验
                // 判红，用户拍板拆开。头像钮独立开枢纽
                // （呈现仍在本页根 fullScreenCover）；模
                // 型胶囊整颗只开分组选择面（§153 本会话
                // 作用域，见 modelPickerSheet）。两元素
                // 间距 spacingS、命中域互不融接；短名时
                // 胶囊照常 hug 内容宽、长名尾部截断
                topBarCenterCluster

                Spacer(minLength: OneDayMetrics.spacingS)

                // 0.6.0 顶栏三件套之右：铃铛＋角标（角标＝
                // 未读通知＋待审批，总览桥聚合）。原右钮
                // 「新建会话」退场——新建入口在抽屉底条与
                // 抽屉空态行各有一处，不占顶栏三件套之位
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
                            // 0.23.0（审计 T2）：同左钮换系统
                            // 玻璃；角标与盘的相对位不变
                            .glassEffect(.regular, in: Circle())
                        if overviewBadgeCount > 0 {
                            Text("\(overviewBadgeCount)")
                                .font(.caption2.weight(.bold))
                                // 角标坐在 danger 面上，字恒白
                                // （0.6.1：onPrimary 已改深字口径、
                                // 不再借作白字）
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Palette.danger, in: Capsule())
                                .offset(x: 4, y: -4)
                                .accessibilityHidden(true)
                        }
                    }
                    // 0.23.0（命中域审计）：命中域外扩 44
                    // （视觉盘 40 居中、角标相对位不变）
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

            // （0.20.0 第五条，用户原话「状态栏下面不要显
            // 示当前对话的名字，就一个状态栏就行了」：胶
            // 囊之下的会话名次行整行撤销——第 30 条的弱行
            // 与 0.4.0 的会话信息入口一并退役；会话名只在
            // 抽屉旁聊区与管理页出现，会话详情经管理页
            // ServerSessionRow 进入、不失联。showSession-
            // Info 状态与 sheet 承载同轮拆除）
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    /// 顶簇中央组适配（§202 路线 B，本体 HubAvatar-
    /// Button／ModelCapsuleView 两件）：本处只作适
    /// 配——值与动作仍由本页单源派生，呈现宿主
    /// （枢纽 cover／模型面 sheet）留在本页根
    /// （§175），一件不多。两元素之间是一条 8pt
    /// 显式隔断（透明命中盾：吃掉间隙点、不触发
    /// 任何动作）——间隔由此按构造恒为死区，不靠
    /// 两侧命中域自觉收边（胶囊玻璃命中外扩的实
    /// 测教训见 ModelCapsuleView 文件头）；隔断宽
    /// ＝spacingS，不许压小
    private var topBarCenterCluster: some View {
        HStack(alignment: .center, spacing: 0) {
            HubAvatarButton(
                avatar: appState.agentAvatarImage,
                displayName: appState.agentDisplayName,
                statusWord: overviewStatusWord,
                statusColor: overviewStatusColor,
                avatarPointSize: avatarTier.capsulePointSize,
                onOpenHub: { showHub = true }
            )
            // 显式隔断（命中死区）：宽 16——动作门三
            // 轮实测（run 43378398732 探针点定界）：
            // 两钮的实际命中域都比无障碍帧外扩约
            // 4pt（平台命中宽容、与玻璃无关——无玻
            // 璃的头像钮同扩），8pt 间隔下两域在中
            // 点相接、无真死区；16pt 才留出中央
            // ≥7pt 死带。隔断自带空点按手势，在自
            // 己帧内吃点不触发（§202.6 补记）
            Color.clear
                .frame(
                    width: OneDayMetrics.spacingM,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
                .onTapGesture {}
            ModelCapsuleView(
                modelTriggerLabel: ModelDisplayNames.triggerLabel(
                    for: currentChoice.model
                ),
                modelAccessibilityLabel: "当前模型 \(displayModelName)，切换模型",
                onOpenModelPicker: { showModelPicker = true }
            )
        }
    }

    /// （模型触发钮本体在 ModelCapsuleView；§153 的
    /// 选面纪律注记并入下方 modelPickerSheet 注）

    /// 模型面只由稳定的聊天根呈现，不挂在 ViewThatFits
    /// 的两个候选按钮上；保留选择、隐藏确认和作用域逻辑。
    /// §153 B1/B2 纪律（随触发钮迁件自原 modelMenu 注
    /// 移入）：分组选择面取代旧原生 Menu＋Picker（写死
    /// 两项装不下服务商分组，新面准入四问①②见
    /// §153.4）；勾的纪律不回退——选择面是系统 List、
    /// 当前执行行由系统 checkmark 呈现、单选互斥由
    /// 「点行即落账关面」构造保证（FB16679936 的教训
    /// 是自绘勾被 UIKit 剥透明度，双勾源于自绘而非列
    /// 表形态本身）；选择只写本会话账（selectCurrent-
    /// Choice），不改服务端默认、不发网络请求
    private var modelPickerSheet: some View {
        ChatModelPickerView(
            groups: appState.pickerModelGroups,
            current: currentChoice,
            onSelect: { choice in
                selectCurrentChoice(choice)
                showModelPicker = false
            },
            onHideGroup: { group in
                requestHideProviderGroup(group)
            }
        )
        .confirmationDialog(
            "隐藏默认服务商？",
            isPresented: Binding(
                get: { pendingHideGroup != nil },
                set: { if !$0 { pendingHideGroup = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("隐藏服务商", role: .destructive) {
                if let group = pendingHideGroup {
                    commitHideProviderGroup(group)
                }
                pendingHideGroup = nil
            }
            Button("取消", role: .cancel) { pendingHideGroup = nil }
        } message: {
            Text("隐藏这家，服务端的新对话默认也会随之改走默认服务商。当前已经打开的对话不受影响。")
        }
    }

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

    private func bottomBar(_ proxy: ScrollViewProxy) -> some View {
        // 0.36.5（审计 bug 2 短修）：钮显隐走 Core 政
        // 策——当时是几何判定离底之外并入事实信号；
        // §135 改判几何单源（事实信号链退役，见
        // BottomFollowPolicy §135 注，迟滞带晚消失列
        // 真机待验）；显隐派生已提为全页单一出处
        // showsBackToBottomButton（本函数不再自算）；
        // 未读计数于 0.41.0 落地（AwayUnreadCounter），
        // 钮的宿主与落位于 §124 改归本区布局流（输
        // 入舱上方一行，见栈内钮行注）
        return VStack(spacing: OneDayMetrics.spacingS) {
            if let importRetryContext {
                importRetryBar(importRetryContext)
                    .transition(.opacity)
            }
            if let errorMessage {
                errorBanner(
                    errorMessage,
                    onResend: failedResendTarget.map { target in
                        { resendFailedEntry(target) }
                    }
                )
                    // 0.25.0（动效专包）：错误/提示条进出
                    // 原为无过渡硬入硬出（高度跳变）——补
                    // opacity 过渡，高度与淡入同走下方
                    // swap 容器动画（单调无过冲，与回到底
                    // 部钮同口径）
                    .transition(.opacity)
            }
            if let notice = noticePresentation.current {
                noticeBar(notice.text)
                    .transition(.opacity)
            }
            // 回底钮行（§124 三代落位）：输入舱正上方
            // 一行、右对齐承载——钮底缘与输入舱顶缘之
            // 间只隔本栈 spacingS（既有 gap 口径），整
            // 段随发送区被系统安全区顶起，键盘升/降两
            // 态落位由构造恒成立、零几何推算；命中域
            // 是布局流内的真实帧，恒在宿主 bounds 内
            // （P-20 正案）。显隐由本行的存在承载：行
            // 高（44 命中域）＋间距的变化随下方容器
            // swap 动画与错误/提示条同口径滑动；显隐
            // 抖动的护栏在判定层（迟滞双阈值，0.36.5
            // 钉死；末条事实信号已于 §135 退役、显隐
            // 改几何单源），不靠把钮逐出布局流——三
            // 轮浮层落位病史见 DESIGN §124
            if showsBackToBottomButton {
                HStack {
                    Spacer(minLength: 0)
                    scrollToBottomButton(proxy)
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.9)
                            )
                        )
                }
                .padding(.trailing, OneDayMetrics.spacingM)
            }
            inputBar
        }
        .fixedSize(horizontal: false, vertical: true)
        // 条 9（§14）动画口径沿革：本容器高度动画服
        // 务错误/提示条——0.4.2 起两键（errorMessage／
        // notice；§140 起提示条键改当前条代号 id，自清
        // 消失同走本动画）。回底钮的高度动画键两度退
        // 役又回归，
        // 如实记：0.41.0 钮浮层化时退役（当时的防摆
        // 手段是把钮逐出布局流）；§124 钮回到布局流，
        // 显隐键（showsBackToBottomButton）作第三键
        // 以同口径回归——防摆护栏改由判定层迟滞双阈
        // 值承担（0.36.5 钉死；末条事实信号已于 §135
        // 随信号链退役），三轮浮层落位的病史与取舍
        // 见 §124
        // 0.25.0（动效专包）：条本体淡入淡出、容器
        // 高度同步单调滑动，不再硬跳
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: importRetryContext?.sessionID
        )
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: errorMessage
        )
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: noticePresentation.current?.id
        )
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: showsBackToBottomButton
        )
    }

    /// 回到底部圆钮（0.2.4 曾换原生玻璃；0.3.8 第 28 条
    /// 浮件统一白浮纸——圆钮全体同画法；外壳结构包
    /// §178：本体材质由白浮纸改回系统玻璃
    /// .glassEffect(.regular)——与顶栏圆钮（本文件
    /// 1076/1122）同画法，属材质换代、与边缘溶化带
    /// 样式无关；34 视觉盘/44 命中域/角标层全不动）
    /// 0.41.0（收口批）：离底未读角标——计数出自 Core
    /// AwayUnreadCounter（displayText 封顶 99+），挂视
    /// 觉盘右上；点钮即清零（回底的 ingest 随后以在底
    /// 事实复核、水位推进，不双计）
    private func scrollToBottomButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            scrollToBottom(proxy)
            awayUnread.reset()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .glassEffect(.regular, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if let badge = awayUnread.displayText {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(
                                Palette.primaryFill, in: Capsule()
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

    // MARK: - 消息列表

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

    /// 落定条目渲染计划：连续工具卡条目 ≥2 收成一
    /// 组、单卡仍走 .entry 原路（bubble 内 ToolCard-
    /// View）。时间分隔走查只认会话条目、与本计划无
    /// 关（映射在 timelineDividers 独立计算）
    private enum EntryRenderItem: Identifiable {
        case entry(ChatEntry)
        case toolGroup([ChatEntry])

        var id: UUID {
            switch self {
            case .entry(let entry): return entry.id
            case .toolGroup(let entries): return entries[0].id
            }
        }
    }

    private func entryRenderItems(
        for entries: [ChatEntry]
    ) -> [EntryRenderItem] {
        var items: [EntryRenderItem] = []
        var run: [ChatEntry] = []
        func flush() {
            if run.count == 1 {
                items.append(.entry(run[0]))
            } else if run.count > 1 {
                items.append(.toolGroup(run))
            }
            run = []
        }
        for entry in entries {
            if entry.toolCard != nil {
                run.append(entry)
            } else {
                flush()
                items.append(.entry(entry))
            }
        }
        flush()
        return items
    }

    /// 渲染计划缓存（§135 B 案）：存上轮的分隔映射
    /// 与成组计划及命中键——引用型纯记账，不参与呈
    /// 现判定；键（Core ChatRenderPlanKey）由条目集
    /// 投影（id／工具卡数据有无／createdAt）＋线程
    /// ＋当日零点构成，任一失效条件变化即键变、计
    /// 划重算
    private final class RenderPlanCache {
        var key: ChatRenderPlanKey?
        var dividers: [UUID: String] = [:]
        var items: [EntryRenderItem] = []
    }

    /// 本帧渲染计划：先按键查缓存，未命中才走全量
    /// （sortedEntries 排序＋timelineDividers＋entry-
    /// RenderItems 三件一并缓存——只缓存其一、另一
    /// 件每帧现算等于没减负）。键的投影取 thread.
    /// entries 原始集（未排序）：投影不解码、不排序，
    /// 键内自带定序（见 Core make）
    private func renderPlan(
        for thread: ChatThread
    ) -> (dividers: [UUID: String], items: [EntryRenderItem]) {
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
        if renderPlanCache.key == key {
            return (renderPlanCache.dividers, renderPlanCache.items)
        }
        let sorted = thread.sortedEntries
        let dividers = timelineDividers(for: sorted)
        let items = entryRenderItems(for: sorted)
        renderPlanCache.key = key
        renderPlanCache.dividers = dividers
        renderPlanCache.items = items
        return (dividers, items)
    }

    /// 直播区渲染计划：按 liveOrder 标记交错思考/工
    /// 具/正文，连续工具标记 ≥2 收成组；标记外的卡
    /// （恢复回填等）按卡序殿后、正文标记缺失时殿后
    /// 补位——只重排呈现、不丢段
    private enum LiveRenderItem: Identifiable {
        case reasoning
        case text
        case tool(ToolCard)
        case toolGroup([ToolCard])

        var id: String {
            switch self {
            case .reasoning: return "live-reasoning"
            case .text: return "live-text"
            case .tool(let card): return "tool-\(card.id)"
            case .toolGroup(let cards):
                return "toolgroup-\(cards.first?.id ?? "none")"
            }
        }
    }

    private func liveRenderItems() -> [LiveRenderItem] {
        var items: [LiveRenderItem] = []
        var pendingTools: [ToolCard] = []
        var seenCardIDs: Set<String> = []
        func flushTools() {
            if pendingTools.count == 1 {
                items.append(.tool(pendingTools[0]))
            } else if pendingTools.count > 1 {
                items.append(.toolGroup(pendingTools))
            }
            pendingTools = []
        }
        for marker in liveOrder {
            switch marker {
            case .reasoning:
                flushTools()
                if streamingReasoning != nil {
                    items.append(.reasoning)
                }
            case .text:
                flushTools()
                if streamingText != nil {
                    items.append(.text)
                }
            case .tool(let id):
                if let card = liveToolCards.first(
                    where: { $0.id == id }
                ) {
                    pendingTools.append(card)
                    seenCardIDs.insert(id)
                }
            }
        }
        flushTools()
        let leftovers = liveToolCards.filter {
            !seenCardIDs.contains($0.id)
        }
        if leftovers.count == 1 {
            items.append(.tool(leftovers[0]))
        } else if leftovers.count > 1 {
            items.append(.toolGroup(leftovers))
        }
        if streamingText != nil, !liveOrder.contains(.text) {
            items.append(.text)
        }
        return items
    }

    @ViewBuilder
    private var liveZone: some View {
        ForEach(liveRenderItems()) { item in
            switch item {
            case .reasoning:
                liveReasoningBlock
            case .text:
                if let streamingText {
                    streamingBubble(streamingText)
                        .id("streaming")
                }
            case .tool(let card):
                ToolCardView(card: card)
                    .id("tool-\(card.id)")
            case .toolGroup(let cards):
                ToolCardGroupView(cards: cards)
                    .id("toolgroup-\(cards.first?.id ?? "none")")
            }
        }
    }

    private func messageList(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            // §176（2026-11-12，气泡间距收口）：尾锚移
            // 出 LazyVStack 的行距体系——旧形态锚是栈
            // 内最后一个子项，与末条之间照收一份
            // spacingL（24pt，诊断九环第 1 环）；改由
            // 外层 VStack(spacing: 0) 承载消息栈＋尾锚，
            // 行距只在消息之间生效、列表尾与行距脱钩
            // （spacingL 本值不动、消息间密度不变）。
            // 锚的 id 与全部 scrollTo 出口不变，§78/
            // §135 贴底四路的落点仍是它
            VStack(spacing: 0) {
                LazyVStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                    if let thread = currentThread {
                        // 0.30.0（聊天时间系统）：分隔条落点与
                        // 文案由 Core ChatTimeline 按会话条目
                        // 走查（工具卡条目不单独占分隔、也不
                        // 重置锚点——以所属回合时间为准）；流
                        // 式行/流内工具卡是当前回合的呈现层尾
                        // 巴、不另起分隔（本回合的分隔由其
                        // user 条目承担，见 timelineDividers）
                        // §135 B 案：渲染计划走缓存单口（排
                        // 序＋分隔＋成组三件一并按键复用），
                        // 不再每遍 body 对全线程现算两遍
                        let plan = renderPlan(for: thread)
                        ForEach(plan.items) { item in
                            switch item {
                            case .entry(let entry):
                                VStack(
                                    alignment: .leading,
                                    spacing: OneDayMetrics.spacingS
                                ) {
                                    if let dividerText
                                        = plan.dividers[entry.id] {
                                        timelineDivider(dividerText)
                                    }
                                    bubble(entry)
                                }
                                // §165：锚点点亮——点达请求命
                                // 中的锚定行以 primaryTint 底
                                // 色点亮（沿 §123 枢纽聚焦同
                                // 手法），消费侧 2.5 秒后清
                                .background(
                                    entry.id == anchorHighlightEntryID
                                        ? Palette.primaryTint
                                        : Color.clear,
                                    in: RoundedRectangle(
                                        cornerRadius:
                                            OneDayMetrics.containerCorner
                                    )
                                )
                                .id(entry.id)
                            case .toolGroup(let groupEntries):
                                // 连续工具卡 ≥2 成组（0.36.10，
                                // 诊断 D3-8）：组 id 借首条条目
                                // id，与 .entry 形态互斥不撞
                                ToolCardGroupView(
                                    cards: groupEntries
                                        .compactMap(\.toolCard)
                                )
                                .id(groupEntries[0].id)
                            }
                        }
                    }
                    // 直播区（0.36.10 重做）：思考/工具/正文
                    // 按事件到达序交错（liveOrder），连续工
                    // 具 ≥2 收成组；旧形态「卡列恒在前、正
                    // 文恒在后」与真实先后倒序（诊断 D3-10）
                    liveZone
                    // 0.7.0（D2 回告入线）：任务/审批等完成回告
                    // 以卡片只出现在主线——数据走总览桥通知、
                    // 在呈现层拼装呈现，绝不写入任何 Hermes
                    // 会话（红线 D4）；旁聊页经 ReportCard-
                    // Policy 恒为空。卡不入 SwiftData、不进发
                    // 送上下文（上下文只由 sortedEntries 组装、
                    // 构造上隔离）
                    if let overviewStore {
                        ForEach(
                            ReportCardPolicy.cards(
                                notifications: overviewStore.notifications,
                                isMainThread: isCurrentMainThread
                            )
                        ) { item in
                            reportCard(item, store: overviewStore)
                        }
                    }
                    // 留痕回响卡（P0 App 侧，P2 首链「自开
                    // 旁聊」）：AI 内部动作的留痕在呈现层拼
                    // 装（与回告卡同纪律：绝不写入任何
                    // Hermes 会话）；主线全量回响、旁聊只
                    // 出指向本会话者、失败与成功同级——范
                    // 围口径在 Core TraceEchoPolicy、卡面
                    // 走公用件 TraceEchoCard（其余动作包
                    // 的回响共用），点卡经既有续聊通道达
                    // 目标旁聊
                    ForEach(
                        TraceEchoPolicy.cards(
                            traces: echoTraces,
                            isMainThread: isCurrentMainThread,
                            currentServerSessionID: currentThread?
                                .serverSessionID
                        )
                    ) { trace in
                        TraceEchoCard(
                            trace: trace,
                            agentName: appState.agentDisplayName,
                            onOpenSession: { sessionID in
                                // 已在本会话里点自己的回响卡
                                // 不重复导入；其余置位待续聊
                                // id，由本页既有消费口导入/
                                // 切换（与管理页/频道页同路）
                                if sessionID != currentThread?
                                    .serverSessionID {
                                    appState.pendingChatSessionID =
                                        sessionID
                                }
                            }
                        )
                    }
                    // 就地审批（0.36.21，规格 §1/§3）：待批
                    // 写入在流末尾出卡——桥载荷无会话归属字
                    // 段，走退位形态（全部未决汇到当前流＋
                    // 枢纽兜底）；与回告卡同纪律：只在呈现
                    // 层拼装、绝不写入会话；store 与枢纽共
                    // 享同一份（AppState.sharedHubStore）
                    // §165（锚点包）：已在本机落锚的记录由
                    // 其锚定行承载（单源，规格 §4.3），本区
                    // 只出未锚记录；锚集随 store 刷新回写
                    // （ApprovalAnchorMaterialization）
                    ChatApprovalZone(
                        store: appState.sharedHubStore(),
                        anchoredRecordIDs: appState
                            .sharedHubStore().anchoredRecordIDs
                    )
                    if ChatEmptyState.shows(
                        threadIsNil: currentThread == nil,
                        entryCount: currentThread?.sortedEntries.count ?? 0,
                        isStreaming: isStreaming
                    ) {
                        // 空状态（DESIGN-V4 §5 两行字口径保
                        // 留）：0.26.0 起形象位由 SF 符号换三
                        // 狗头像、边长走形象档空态值（48/56/
                        // 68）——用户外观令点名的作用面
                        // 基础止血包（P9）：呈现判定并成一
                        // 条（Core ChatEmptyState）——已建
                        // 的零条目线程同出本面，不再白屏
                        VStack(spacing: OneDayMetrics.spacingS) {
                            // 0.36.22：空态形象同样读档案头像
                            appState.agentAvatarImage
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: avatarTier.emptyStatePointSize,
                                    height: avatarTier.emptyStatePointSize
                                )
                                .clipShape(Circle())
                                .overlay {
                                    Circle().stroke(
                                        Palette.hairline, lineWidth: 0.5
                                    )
                                }
                                .accessibilityHidden(true)
                            Text(L10n.format(
                                "和 %@ 聊聊", appState.agentDisplayName
                            ))
                                // 0.3.3 收编：手写 fontWeight 漂移
                                // 改走 sectionTitle 角色（阶梯账
                                // 见原字重账本，已废止）
                                .font(.callout)
                                .foregroundStyle(Palette.ink)
                            Text(L10n.string("消息经你自己的服务器发给 Agent，记录只存这台手机。"))
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, OneDayMetrics.spacingXL)
                        // 引导线（原型 chat 面）：空态建议条三
                        // 条，点按即发送（走现行 send() 全链，
                        // 不另建发送路）。文案与图标名单一出处
                        // 在 Core EmptyChatSuggestions
                        VStack(spacing: OneDayMetrics.spacingS) {
                            ForEach(
                                Array(EmptyChatSuggestions.texts.enumerated()),
                                id: \.offset
                            ) { index, suggestion in
                                Button {
                                    input = suggestion
                                    send()
                                } label: {
                                    HStack(spacing: OneDayMetrics.spacingSM) {
                                        Image(systemName: EmptyChatSuggestions.symbols[index])
                                            .font(.system(size: 15))
                                            .foregroundStyle(Palette.inkSecondary)
                                        Text(L10n.string(suggestion))
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
                        // §119：无任何可用模型时，空态下方出
                        // 引导卡（判定见 showsModelSetupCard；
                        // 有模型时永不出现）
                        if showsModelSetupCard {
                            modelSetupCard
                                .padding(.top, OneDayMetrics.spacingL)
                        }
                    }
                }
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
                    // 事实信号探针（手感 A 档，Core
                    // BottomFactCalibration）：尾锚是内
                    // 容的真末端（条目/直播/回告/审批全
                    // 部区段都在它上方），它完整落在列
                    // 表视口内＝屏幕上已无看不见的内容。
                    // 帧取列表自有坐标空间（下方
                    // coordinateSpace 命名）：锚的内容
                    // 坐标与滚动偏移同含视口上方未物化
                    // 行的估算高、屏幕帧里逐项抵消，故
                    // 本信号对 LazyVStack 总高估算免疫
                    // ——正是几何距底读数的病根所在。回
                    // 调只在布尔翻转时触发、写引用匣不
                    // 失效任何视图（§199 纪律），与
                    // §135 退役的可见集逐帧回写链不同
                    // 物：单锚、单布尔、无重算
                    .onGeometryChange(for: Bool.self) { proxy in
                        let frame = proxy.frame(
                            in: .named("chatListViewport")
                        )
                        let viewportHeight =
                            bottomDistanceRecorder.containerHeight
                        // 有效视口（评审合成条目 6）：底
                        // 边扣除底 inset 带——尾锚落进输
                        // 入舱遮挡带（留位区）内不算「在
                        // 屏可读」，事实信号只认扣除后的
                        // 可视区（带宽取 adjusted 实值、
                        // 经引用匣同拍读，见底 inset 订
                        // 阅）
                        let effectiveBottom = viewportHeight
                            - bottomDistanceRecorder.bottomInset
                        return viewportHeight > 0
                            && frame.minY >= -1
                            && frame.maxY <= effectiveBottom + 1
                    } action: { _, endVisible in
                        bottomDistanceRecorder
                            .contentEndVisible = endVisible
                        // R4：尾锚事实翻转是落定评估的
                        // 事件源之一（事实到场即评，不
                        // 等任何定时器）
                        evaluateSettleOnEvent(proxy)
                    }
            }
            // 0.7.0（M1 轻保活）：滚动目标布局登记——条目
            // 可见性按 UUID id 回报，喂滚动锚的存/取
            .scrollTargetLayout()
            // §213：列表本体登记锚——0 帧透明视图坐内
            // 容栈左上角，入层级即沿祖先链把 UIScroll-
            // View 本体登记进 listScrollHandle（两宿主
            // 的边缘效果注册靠它拿本体）；纯登记、不接
            // 命中、不占布局、不改命中域（contentShape
            // 在下方另行声明、辖区不变）
            .background(alignment: .topLeading) {
                ChatListScrollAnchor(handle: listScrollHandle)
                    .frame(width: 0, height: 0)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingS)
            // 命中域撑满（0.3.5，§20.2）：内容栈帧宽撑满、
            // 高至少撑到列表可视高（容器高 − 底 content-
            // Margins spacingS）。0.4.3 前顶栏是 overlay、
            // 容器高含其悬浮区、常数按 64 近似扣减；顶栏
            // 注册 safeAreaBar 后顶区由安全区自理、容器高
            // 已不含它，64 常数退役。§195 后顶区改由顶
            // contentMargins 让出、容器高口径不变
            // （adjustedContentInset 通道同源、静止总量
            // 122 不变）。0.3.4 前栈帧只裹住
            // 已有消息：消息不足一屏时下半屏空白、气泡两
            // 侧窄于栈宽的空白都落在栈外，点下去什么都不
            // 发生——「点空白不收键盘」的定因。内容超高
            // 时 minHeight 不起作用、原行为不变
            .frame(
                maxWidth: .infinity,
                minHeight: max(
                    0, listViewportHeight - OneDayMetrics.spacingS
                ),
                alignment: .topLeading
            )
            // 点空白收键盘·第五症修复（键盘整包，
            // 2026-11-13）：本栈上的祖先单击 tap（0.2.1
            // 起、0.19.0 以 contentShape 撑满命中域）整
            // 件退役，辖区迁到滚动视图本体的 UIKit 点
            // 按识别器（ScrollViewTapDismiss，装配点在
            // 下方 ScrollView 的 background）。旧式三
            // 处结构性病灶：①辖区只及栈帧——顶/底
            // contentMargins 带（122/197pt）在栈帧之
            // 外，点那两带的空白无任何手势接（「有时
            // 不灵」的位置相关性：恰是最常点的末条下
            // 方大空白）；②contentShape 全域命中把文
            // 字区也圈进祖先 tap 的辖区、无 failure-
            // requirement 仲裁——与选字会诊第一嫌疑
            // （祖先 tap 仲裁冲突）同体；③SwiftUI 手
            // 势竞技场与 UIKit 触摸/滚动手势的仲裁顺
            // 序不归本方管辖。新式：识别器只装在 UIS-
            // crollView 本体、辖区＝整个滚动视口（两
            // 带与行间全覆盖）；delegate 的 should-
            // Receive 按苹果 UIGestureRecognizer-
            // Delegate 官方口径过滤——触点落在任何
            // UITextView 子树内根本不进识别器（文字
            // 区归选字/链接/长按自家体系，顺带落实会
            // 诊建议修法 2）；cancelsTouchesInView＝
            // false 不吞任何触摸；拖动收起仍归系统
            // .scrollDismissesKeyboard（即 UIScroll-
            // View.keyboardDismissMode=.interactive
            // 的 SwiftUI 面，苹果文档口径）。0.2.7 当
            // 年不挂本体的两条顾虑已消失：发送舱早已
            // 退出列表安全区注册（§186，其命中域不在
            // 滚动视图子树内、识别器够不着）；聚焦吞
            // 噬是 SwiftUI 竞技场的病、UIKit 识别器
            // ＋不过滤文本视图的 Composer 本体不在
            // 其辖区内。栈帧撑满（minHeight）是布局
            // 不是手势、原样保留
            .background {
                // 装配点（修正）：桥视图挂本栈背景
                // ——内容在滚动视图子树内，安装器
                // ascend 一步直达 UIScrollView 本
                // 体；首版挂 ScrollView 自身的
                // background（兄弟位）靠窗口选面
                // 两度被同帧候选骗走，已废
                ScrollViewTapDismissInstaller(
                    focusHandle: composerFocusHandle
                )
            }
        }
        // §195（2026-11-13）：顶栏注册退役——顶簇迁
        // TopBarGuideHost 锚定托管（chatSurface 的
        // overlay，落位只认窗口顶安全区、与传播链
        // 脱钩），本列表顶缘自此与底缘同式：断顶安
        // 全区传播（下方 .ignoresSafeArea(edges:
        // .top)）＋实测 contentMargins 留位（下方
        // .contentMargins(.top)＝窗口顶安全区实测
        // ＋顶簇实高，两值均由宿主布局拍回写）。
        // 沿革：0.4.2 前 overlay 悬浮＋.content-
        // Margins(.top, 88) 代偿（§28.1 原因一）；
        // 0.4.3–§194 注册为本列表的 .safeAreaBar
        // (edge: .top)、首屏位置由安全区本体让出；
        // §194 真机落定帧实证：传播安全区被藏坞重
        // 算偷 49、顶簇随之撞状态栏（耦合路径与断
        // 链证据见 TopBarGuideHost 文件头）——注
        // 册形态与顶缘传播一并退出。顶栏不挂
        // background 的裁决（0.7.1）与顶缘 .soft
        // 留任均不变：.soft 作用区改由顶
        // contentMargins 区决定
        // §213 追记（2026-11-13）：本样式同时是两宿
        // 主注册容器（顶簇宿主视图/舱带容器）的效果
        // 样式来源——样式挂滚动视图的 edge effect、
        // 注册只塑造其在覆盖容器后的呈现（公开文档
        // 口径）；§200 常驻材质底衬三件同日退役
        .scrollEdgeEffectStyle(.soft, for: .top)
        // 底缘沿革：0.4.2 同挂柔效、0.4.3 注册后按发送
        // 舱高度发放（§28.1）；§170（用户 2026-11-11
        // 亲定）整条隐藏——注册承载下效果带正罩发送舱
        // 上方、回底钮行 52pt 基本透明而消息透过被糊，
        // 即当时点名撤掉的「输入框上方那条朦胧带」。
        // 割裂感 A 止血档接通（2026-11-13，用户 17:06
        // 问清机制后 17:11 亲点「那你做吧」，§170 隐藏
        // 口径就此被新拍板覆盖）：底缘改回系统 .soft。
        // 与 §170 当年形态的载体差异如实记：栏位已退
        // 注册改锚定托管（§186/§193/§195），效果作用
        // 区改由底 contentMargins 区决定（与顶缘 §195
        // 注同式）——即内容滚进输入舱/坞上方的留位带
        // 时由系统糊化其隔着浮件的像，阅读区本体不被
        // 擦淡；这与已作废的 §173 手搓渐变溶化是两回
        // 事（17:06 口径钉死：只许系统滚动边缘效果、
        // 禁自绘擦淡、禁私有 variableBlur）。同带内回
        // 底钮行区的衬已由 A2 撤除，那段的过渡自此由
        // 本效果承担；真机若证本带在新承载下重现 §170
        // 形态的过糊，回退动作只此一行改回 hidden、
        // 须用户复核后执行
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // 事实信号坐标空间（手感 A 档）：尾锚的几何回
        // 调以本列表为原点读帧（见栈内尾锚注）——只命
        // 名、不改任何布局与滚动行为
        .coordinateSpace(name: "chatListViewport")
        // 0.36.27（§97 件二，用户 03:48 点题「输入框
        // 上面有点大，小点就行」）：列表底边距收一档
        // spacingS 8 → spacingXS 4，与 inputBar 顶
        // padding 同步收（见 inputBar 注）；「末条消息
        // 底→发送舱卡顶」链总量 32 → 24（量账见 §97.2）
        // §176（2026-11-12）：本处定为这条链的唯一可
        // 调边距（单点所有权）——回 spacingS 8，
        // inputBar 顶 padding 同步归零（链上这一段的
        // 总量不变、记账只剩一处）；链写死总量 17、
        // 九环对账见 DESIGN §176
        // §186（2026-11-12，承载换代）：留位来源换代——
        // 输入舱退出安全区注册后，列表底留位＝舱顶→窗
        // 口底的实测距离（composerBottomSpace，Compo-
        // serGuideHost 布局拍回写）＋spacingS：本行仍是
        // 这条链的唯一记账点，spacingS 仍是唯一可调边
        // 距（8）；链的静止总量与 §176 定版一致（实测距
        // 离在静止帧＝坞高＋舱高，公式见 §186 对账）。
        // 键盘态距离随引导线实测走（升起＝键盘高＋舱
        // 高、交互收起逐拍跟随），不再经安全区扩张
        // §195（2026-11-13）：顶留位同式入账——顶簇
        // 迁锚定托管后，列表顶 contentMargins＝窗口
        // 顶安全区实测（windowTopSafeInset）＋顶簇
        // 实高（topBarHeight），两值均由宿主布局拍
        // 回写；顶留位记账自此只剩本处一处（沿革见
        // 列表顶缘 §195 注）
        .contentMargins(
            .top,
            windowTopSafeInset + topBarHeight,
            for: .scrollContent
        )
        // 键盘整包 R1（2026-11-13）：底留位改读键
        // 盘几何快照的派生值（kbSnapshot.bottom-
        // Space，Core 纯函数：键盘态＝键盘高＋栈
        // 高、静息态＝坞下段＋栈高，与 §186 实测回
        // 报同值同义）——留位的生产者自此只有快照
        // 一处：键盘事件拍整体替换、动画参数同载，
        // 下方 withAnimation 桥以通知自带时长/曲线
        // 推进本留位与舱的 UIKit 动画同拍（苹果文
        // 档：键盘通知 userInfo 载 frame/duration/
        // curve 供伴随动画——MessageKit/Stream 同
        // 式）；composerBottomSpace 实测回报降级为
        // 诊断读数、退出公式（D2）
        .contentMargins(
            .bottom,
            kbSnapshot.bottomSpace + OneDayMetrics.spacingS,
            for: .scrollContent
        )
        // 0.2.6 承载换代核心：发送区进列表的底部安全区
        // 留位——Exyte/Stream 式「列表＋发送区同处布局流」
        // （DESIGN-V4 §10）。键盘避让自此走系统安全区通道：
        // 键盘升起留位随安全区顶到键盘上方、交互收起跟随，
        // 发送舱高度只由内容决定（高度口径归 Composer-
        // Layout/ComposerTextMetrics 纯逻辑＋单测把守，§13）
        // 0.4.3（§28）：承载由 safeAreaInset 改 safeAreaBar
        // ——同一安全区布局族、不是覆盖层，差别只在注册：
        // 系统自此认它作 bar，滚动内容从其下方穿过并吃
        // 满底缘 scroll edge effect。键盘跟随仍由安全区
        // 驱动（键盘即安全区扩张），0.2.6/0.4.1 的键盘
        // 行为经构造＋代码审计＋单测复验，证据链见 §28.4
        // §186（2026-11-12，承载换代）：底部 safeAreaBar
        // 注册整段退役（0.2.6 进安全区、0.4.3 改注册的
        // 沿革到此为止）——输入舱改由 ComposerGuideHost
        // 以 keyboardLayoutGuide 托管（chatSurface 的
        // ZStack 同层），本列表改以 .ignoresSafeArea
        // (edges: .bottom) 退掉底部安全区传播：探针实
        // 证传播来的坞预留（83pt）在页帧已收于坞上方的
        // 嵌套里是双计、且键盘态正是「整栈重排顶坞」的
        // 通道；退掉后列表帧延伸到屏底、底留位全由上
        // 方 contentMargins 一处按实测记账。顶缘
        // safeAreaBar（顶栏注册）与底缘效果隐藏（§170）
        // 均不在本项范围、原样不动。0.6.1 的底缘带删
        // 除与背景同源主治（chatSurface 背景全出血）
        // 随承载换代继续成立（带本就已删、画布仍全出
        // 血），不因本项回潮
        // §195 更正（2026-11-13）：上文「顶缘 safe-
        // AreaBar（顶栏注册）原样不动」就此作废——
        // 顶栏注册已退役（见列表顶缘 §195 注），顶
        // 缘传播同步退掉（下一行）：列表两缘自此都
        // 不吃传播安全区，顶/底留位全走实测
        // contentMargins 一处记账
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(edges: .top)
        // （声明式锚 .defaultScrollAnchor 已于 §135
        // 退役：0.36.13 引入时注称「与 scrollTo 不冲
        // 突、只管首帧」——发送空屏诊断的外部实证与
        // 之相左（Apple Developer Forums thread/
        // 741406：LazyVStack＋defaultScrollAnchor＋命
        // 令式 scrollTo 并存是聊天类重入空白的经典组
        // 合；Tactic Remote 的 scrollTo livelock 受控
        // 复现），冲突时以外部实证为准、旧注作废。首
        // 帧落位由下方 .task 定版链单点承担（0.22.0：
        // 无存量滚动锚的线程出现一拍后无动画贴底））
        .scrollDismissesKeyboard(.interactively)
        // 距底距离回写（0.4.2，§27）：判定改迟滞双阈值
        // （OneDayCore.BottomProximity：进入 <96／退出
        // ≥176、带内保持原态）——0.4.1 前是 <140 单阈
        // 值即时翻转，距离在阈值附近游走时 isNearBottom
        // 逐帧翻转、连带「回到底部」钮显隐（底部 inset
        // 高度）与跟随滚动反复触发，是划到底抖动的放
        // 大器之一
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentSize.height - geometry.contentOffset.y
                - geometry.containerSize.height
        } action: { _, distance in
            // 0.36.13：原始读数另存一份喂落定评估
            // （见 bottomDistanceRecorder 注）
            // §135：回写加等值守卫——几何回调在滚动
            // 中逐帧到达，值未变的回写不许再触发一轮
            // body 重算（距底读数在静止期恒同值）
            // §199：原始读数改写引用匣——滚动中它逐帧
            // 必变、等值守卫挡不住、@State 写每帧触发
            // 全页重跑；匣写不失效任何视图，复核读到
            // 的仍是读时点最新值，判定语义零变更
            bottomDistanceRecorder.latest = distance
            applyBottomProximity(distance: distance)
            // R4：距底读数变化是落定评估的主事件源
            // （滚动/量实/留位结算都经此读数到场）
            evaluateSettleOnEvent(proxy)
        }
        // 列表可视高回写（0.3.5）：喂内容栈的撑满
        // minHeight（点空白收键盘命中域，见栈内撑满注）
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height
        } action: { _, newHeight in
            // §135：等值守卫——可视高只在键盘/旋转等场
            // 景变，逐帧同值回写纯属空转
            if listViewportHeight != newHeight {
                listViewportHeight = newHeight
            }
            // 手感 A 档：同值喂引用匣一份——尾锚事实回
            // 调判「完整可见」要读视口高，匣写不失效
            // 视图、与 @State 同源不分叉
            bottomDistanceRecorder.containerHeight = newHeight
        }
        // 底 inset 实值回写（R2 有效视口）：adjusted-
        // ContentInset.bottom 与距底读数同源（同一
        // ScrollGeometry 的 contentInsets 面）——喂
        // 引用匣供尾锚回调扣遮挡带，匣写不失效视图
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentInsets.bottom
        } action: { _, newInset in
            bottomDistanceRecorder.bottomInset = newInset
        }
        // 「点空白收键盘」手势在内容栈上（见 messageList 内注），
        // 不挂 ScrollView 本体——其命中域含发送舱 inset
        .onChange(of: currentThread?.sortedEntries.count) { _, _ in
            // 落定评估（R4 事件化）：条目落盘即流式落
            // 定事件（流结束的最后一贴本就由本路承
            // 担）——先以最新读数＋尾锚事实重跑一遍派
            // 生：流式中途单次大块增长可把距底顶出迟
            // 滞带误翻离底（自家审计 S3），落定刻尾行
            // 已量实、读数收敛或末端事实可见者在此校
            // 回在底，下方跟随贴底随之接续；用户真离
            // 底时读数与事实同向、派生不动
            applyBottomProximity(
                distance: bottomDistanceRecorder.latest
            )
            // 用户已上翻看历史时不强拉回底（0.2.2 交互专项）
            // 0.4.2（§27）：跟随贴底改无动画一步贴合——
            // 带 0.25s 动画的 scrollTo 追逐随内容生长移
            // 动的锚点、永远在追移动靶，是到底抖动的主
            // 因；人发起的滚动（回到底部钮/键盘锚底）仍
            // 走动画，见 scrollToBottom
            if isNearBottom {
                scrollToBottom(proxy, animated: false)
            }
            // （0.36.13 的事实信号重算已于 §135 随信
            // 号链退役：显隐改几何单源，本路不再重算
            // 任何可见集派生量）
            // 0.41.0：未读计数同路喂入（在底事实由几
            // 何派生，见 isAtBottomForUnread）
            feedAwayUnread()
        }
        // 0.7.0（M1 轻保活）：首个可见条目回写（UUID 型
        // id 只有消息条目持有，流式行/底部锚是字符串 id、
        // 不在此列）
        // §135 降权定版（发送空屏诊断 A 案）：可见集
        // 只余「滚动锚存取」一职——topVisibleEntryID
        // 供切线程时存锚（恢复走 currentThreadID 的
        // onChange）。0.36.5/0.36.13 的末条事实信号
        // （lastEntryVisible/refreshLastEntryVisible）
        // 与 0.41.0 的可见集喂未读两路均已退役：显隐
        // 与计数改几何单源（见 BottomFollowPolicy
        // §135 注）；回写加等值守卫，同值不再触发重
        // 算。scrollTargetLayout 本体保留——锚存取的
        // id 回报靠它
        .onScrollTargetVisibilityChange(idType: UUID.self) { ids in
            if topVisibleEntryID != ids.first {
                topVisibleEntryID = ids.first
            }
        }
        // 0.36.5（审计 bug 1）：发送贴底——send() 落盘
        // 且链接成功后递增令牌，本处执行两步：置真跟
        // 随态（Core 政策：自己发送无条件贴底，其后
        // 流式跟随与落定跟随自动接续）、经单一所有者
        // 即时无动画贴底。§135 前本处在所有者的内置
        // 复贴之外自外加一层 120ms 复贴——双层复贴
        // 连发是发送空屏的成因链之一，已删；复贴全
        // 局只剩所有者一层（BottomStickCoordinator）
        .onChange(of: sendPinToken) { _, _ in
            // 0.41.0：自发发送清未读账（Core 口径：发送
            // 无条件贴底、水位推到当前末条）
            awayUnread.noteOwnSend(
                entryIDs: currentThread?.sortedEntries.map(\.id) ?? []
            )
            isNearBottom = BottomFollowPolicy.nearBottomAfterOwnSend()
            scrollToBottom(proxy, animated: false)
        }
        // 0.7.0（M1 轻保活）：滚动位置随线程存锚——切走
        // 记当前锚（在底记 atBottom、否则记首个可见条目），
        // 切入按锚恢复。恢复为 best-effort：等一拍布局落
        // 定再滚，锚条目已删则 scrollTo 无效静默；恢复前
        // 先把 isNearBottom 对齐锚，防条目数变化事件的贴
        // 底跟随把恢复位置冲掉
        .onChange(of: currentThreadID) { oldID, newID in
            if let oldID, oldID != newID,
               threads.contains(where: { $0.id == oldID }) {
                appState.sideChats.setScrollAnchor(
                    SideChatScrollAnchor(
                        entryID: isNearBottom ? nil : topVisibleEntryID,
                        atBottom: isNearBottom
                    ),
                    for: oldID
                )
            }
            // §135：贴底在途状态与发送打点是上一线程
            // 的家当——切入先作废协调者、清落定观察
            // 挂账（R4 事件化后无任务可取消）、清打点
            // 标记，防旧线程的复贴与读数落到新线程头
            // 上（可见集状态已随信号链退役，不再有旧
            // 集可清）
            stickCoordinator.invalidate()
            settleMachine.cancel()
            settleGeneration = nil
            settleFallbackTask?.cancel()
            settleFallbackTask = nil
            sendFrameStartedAt = nil
            sendFrameRestickLogged = false
            // 手感 A 档同理清账：尾锚事实是上一线程的
            // 末端读数、新线程首帧未量前不许误校；键
            // 盘锚底挂账亦属上一线程的家当
            bottomDistanceRecorder.contentEndVisible = false
            keyboardAnchorPending = false
            // 0.41.0：未读账同属上一线程家当——水位与
            // 计数一并清零，新线程从零起算
            awayUnread.resetAll()
            guard let newID,
                  let anchor = appState.sideChats.scrollAnchor(for: newID)
            else { return }
            isNearBottom = anchor.atBottom
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard currentThreadID == newID else { return }
                if anchor.atBottom {
                    scrollToBottom(proxy, animated: false)
                } else if let entryID = anchor.entryID {
                    proxy.scrollTo(entryID, anchor: .top)
                }
            }
        }
        // 0.22.0（视觉审计 C1，用户 2026-11-10 00:09 实机
        // 点名）：冷开首屏首条气泡被顶栏压住、右上角让铃
        // 铛钮盖住一角——定因（代码层）：顶栏/发送舱以
        // safeAreaBar 注册，其顶 inset 在首帧布局之后才
        // 落定，ScrollView 的初始 contentOffset 按未落定
        // 的 inset（≈0）算出、首行直接贴到画框顶缘；此
        // 后长线程靠条目数变化的贴底跟随（isNearBottom
        // 默认 true）顺带把 offset 按已落定 inset 重新钳
        // 制、病被掩盖，短线程内容不可滚动且无等效再钳
        // 事件，压字态就此定格（内容栈 minHeight 的
        // listViewportHeight 首帧为 0、同属首帧未落定
        // 的一环，但它只管高度不管 offset）。修法：无存
        // 量滚动锚的线程（恢复链不接管者）在出现一拍后
        // 强制走一次无动画贴底——以已落定的 inset 重新
        // 钳制 offset：短线程首行落到顶栏下方、长线程
        // 仍开在底部；用户已上翻（isNearBottom=false）
        // 不强拉，与既有跟随口径一致
        .task(id: currentThreadID) {
            guard let id = currentThreadID,
                  appState.sideChats.scrollAnchor(for: id) == nil
            else { return }
            try? await Task.sleep(for: .milliseconds(80))
            guard currentThreadID == id, isNearBottom else { return }
            scrollToBottom(proxy, animated: false)
        }
        .onChange(of: streamingText) { _, newText in
            // 0.4.2（§27）：流式跟随加节流闸（OneDayCore
            // .StreamFollowGate）——0.4.1 前每个流式增量
            // 都触发一次贴底滚动，增量以每秒数十次到达、
            // 滚动动画无限重启追逐移动靶。本版每 ≥40 字
            // 放行一次无动画贴底；流结束（nil）归零闸门，
            // 最后一贴由上方条目数变化事件承担
            guard let newText else {
                streamFollowGate.reset()
                // A3：流结束作废未结算的挂账贴（最后一
                // 贴归条目数变化路，不许挂账尾随补贴）
                streamFollowSettleGeneration += 1
                streamFollowPending = false
                return
            }
            if isNearBottom,
               streamFollowGate.shouldFollow(
                   currentCount: newText.count
               ) {
                // A3（割裂感止血档，调研 §1.4 A3）：贴
                // 底改「登记—结算后执行」，不在文本变
                // 化的同拍直贴——同拍时底留位可能还按
                // 上一拍的舱高结算（舱帧回报走宿主布
                // 局拍→Preference→下一拍回写的状态
                // 链），按旧留位贴底会让流式末行在结算
                // 拍差里探进舱带区（调研 J3 的时序分
                // 量）。登记后两路任一到即消费：舱高变
                // 了走 composerBottomSpace 的结算拍（硬
                // 保证贴在其后）；舱高没变走让出一拍的
                // 兜底（与回报回写同为下一拍序）。代号
                // ＋挂账双守卫防过期与叠贴（执行口
                // settleStreamFollow）；贴底本体与 120ms
                // 落定观察机制零改动
                streamFollowSettleGeneration += 1
                streamFollowPending = true
                let generation = streamFollowSettleGeneration
                Task { @MainActor in
                    await Task.yield()
                    settleStreamFollow(
                        proxy, generation: generation
                    )
                }
            }
        }
        .onChange(of: composerBottomSpace) {
            // A3 结算拍：底留位刚按最新舱高重算——挂
            // 账中的流式跟随贴在此执行（贴底时留位已
            // 结算，见 streamingText 登记处）；非流式期
            // pending 恒假、本路无副作用（键盘升降/回
            // 底钮显隐引起的留位变化不触发任何贴底）
            settleStreamFollow(
                proxy,
                generation: streamFollowSettleGeneration
            )
        }
        // 0.3.3 键盘锚底（真机第 3 条）：点输入框时页面本
        // 在底部，键盘弹起后列表被安全区顶起、最后一条与
        // 输入框之间留白段——弹起前在底部（isNearBottom
        // 为弹起前的值）就在键盘动画落定后滚回锚点。触
        // 发两路：聚焦边沿＋聚焦中键盘帧变化（候选栏收
        // 展等）；用户主动上滑（isNearBottom=false）不
        // 强拉，回到底部钮保留原职
        .onChange(of: composerFocused) { _, focused in
            if focused {
                anchorToBottomAfterKeyboard(proxy)
            } else {
                // 失焦作废挂账：锚底只服务聚焦中的键
                // 盘场景（手感 A 档事件驱动口径）
                keyboardAnchorPending = false
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification
            )
        ) { notification in
            // R1（修正）：快照的键盘输入已收口到
            // ComposerGuideHost 控制器的解析点（帧
            // 顶转窗口坐标后经 kbFrameUpdate 包到
            // 达、body 根 onChange 整包入快照）——
            // 本订阅只余帧变化的挂账职责，不再解析
            // 帧值（首版在此存屏幕坐标原值、与快照
            // 窗口坐标不重合，已废）
            // 帧开始变（升起/候选栏收展/交互收起逐
            // 帧）：落定标记先撤——此后的锚底请求只
            // 记挂账，等帧落定事件兑现（手感 A 档）
            keyboardFrameSettled = false
            if composerFocused {
                anchorToBottomAfterKeyboard(proxy)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardDidChangeFrameNotification
            )
        ) { _ in
            // 帧落定事件：兑现挂账（无挂账只更新标
            // 记）；交互式收起的手势尾段同走本路（手
            // 势结束、帧落定即 Did）
            settleKeyboardAnchor(proxy)
        }
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

    /// 键盘锚底（事件驱动，手感 A 档——代 0.3.3 的
    /// 300ms 定时补一刀）：旧路靠固定睡眠覆盖键盘动
    /// 画时长，落定瞬间的一跳与键盘动画不连续、且等
    /// 待间隙里任何变数都只能靠执行时复查兜底。新路
    /// 只认键盘帧事件：帧已落定（无动画在途）即当场
    /// 锚；帧在途（升起/候选栏收展/交互收起中）只记
    /// 一笔挂账，DidChangeFrame 到达（＝帧落定事件
    /// 本身）时兑现。落定事实由 Will/Did 两路通知维
    /// 护（见 messageList 的键盘通知订阅），本函数不
    /// 持有任何计时器——双时钟尾巴的定时猜测自此退
    /// 役（§194 的键盘常数与宿主跟随曲线零改动，本
    /// 处只换「何时补锚」的触发源）。执行时复查
    /// isNearBottom 与聚焦态：在途期间用户上滑了、
    /// 或已失焦，挂账作废不拉
    private func anchorToBottomAfterKeyboard(_ proxy: ScrollViewProxy) {
        guard isNearBottom else { return }
        if keyboardFrameSettled {
            scrollToBottom(proxy)
        } else {
            keyboardAnchorPending = true
        }
    }

    /// 键盘帧落定兑现：DidChangeFrame 的消费口——帧
    /// 标记落定后，有挂账且仍合锚底条件才滚；挂账
    /// 无论兑现与否都在此清结（下一轮帧变化自会再
    /// 经 Will 路重记）
    private func settleKeyboardAnchor(_ proxy: ScrollViewProxy) {
        keyboardFrameSettled = true
        guard keyboardAnchorPending else { return }
        keyboardAnchorPending = false
        guard composerFocused, isNearBottom else { return }
        scrollToBottom(proxy)
    }

    /// A3 流式跟随贴的结算执行口：代号须仍是最新登
    /// 记（等待间来了更新增量或流结束，旧登记在此作
    /// 废）、挂账未被另一路消费过，才清账并执行一贴
    /// ——两路触发（留位结算拍/让一拍兜底）任一先到
    /// 者执行、后到者被双守卫挡下，不叠贴。执行时
    /// 复查 isNearBottom（等待间用户上滑了就不拉，
    /// 与键盘锚底同口径）
    private func settleStreamFollow(
        _ proxy: ScrollViewProxy, generation: Int
    ) {
        guard generation == streamFollowSettleGeneration,
              streamFollowPending
        else { return }
        streamFollowPending = false
        guard isNearBottom else { return }
        scrollToBottom(proxy, animated: false)
    }

    /// 滚到底部锚点——全列表唯一的贴底所有者（§135
    /// 收口，发送空屏诊断 A 案）：六路触发（条目数
    /// 变化／发送令牌／流式跟随／键盘两路／首帧定
    /// 版／线程恢复）与回底钮一律经此一口，不许直
    /// 呼 performScrollToBottom。animated=true 只给
    /// 人发起的滚动（回到底部钮、键盘锚底）：手感
    /// A 档起走回底弹簧（MotionTokens.scrollTo-
    /// BottomSpring：ζ＝1.0、响应按距缩放——代旧
    /// pageCrossfade 固定 0.25s 的距离无关甩动）；
    /// 内容跟随必须 animated=false 一步贴合当前底
    /// 部——带动画的 scrollTo 追逐随内容生长不断移
    /// 动的锚点，是划到底抖动的主因（0.4.2 定因，
    /// §27，口径不变）。弹簧滚动途中用户手势可直
    /// 接接管（系统滚动语义）：本口只发一贴、无循
    /// 环重发，用户接管后位置与判定全归 §135 派生
    /// 链，落定观察亦以「距底 ≥176 即放弃」防拽回
    /// （见下）。
    /// 所有者职责（判定在 Core BottomStickCoordi-
    /// nator，钉测把守）：同帧重复请求合并为一贴；
    /// 复贴全局只挂一笔——新贴底顶替旧复贴、复贴至
    /// 多消费一次、切线程作废。复贴本体沿 0.36.13
    /// 量实原理：贴底后按实测距底评估，尾行已量实后
    /// 距底仍 >7pt（Core BottomSettle，§176 自 24
    /// 收紧）才以无动画再贴一次；§135 前发送令牌路
    /// 在这一层之外自带第二层复贴（一次发送连发
    /// 3–5 贴），已删，现全局只此一层。
    /// 落定形态（键盘整包 R4，2026-11-13）：复核
    /// 不再是时钟——手感 A 档的 [120, 320, 640,
    /// 1100]ms 定时复核序列（BottomSettleRecheck）
    /// 整件退役：四个定时点与内容/键盘事件全无关
    /// 系，落定尾巴（≥1.1s 起步＋四程串行）即症
    /// ④。改事件化落定观察（Core BottomSettle-
    /// Evaluation）：贴底后挂一笔观察，几何事件
    /// （距底读数变化/尾锚事实翻转）到场即评——
    /// 运动未停只等、停稳未达标才复贴、末端事实
    /// 可见走校准收官、距底 ≥176 判用户已离底收
    /// 官。事件停即静默，不留尾巴、不设超时
    private func scrollToBottom(
        _ proxy: ScrollViewProxy, animated: Bool = true
    ) {
        switch stickCoordinator.requestStick(
            at: Date().timeIntervalSince1970
        ) {
        case .coalesced:
            // 同帧已贴、复贴挂账中：落点由挂账的落定
            // 观察校正，本路不再连发
            return
        case .perform(let generation):
            performScrollToBottom(proxy, animated: animated)
            // R4：状态机入观察——此后几何事件到场即
            // 评估（evaluateSettleOnEvent）；新贴底
            // 顶替本笔、切线程清账（见 currentThre-
            // adID 的 onChange）。有界兜底同拍布防：
            // 2 秒内无任何几何事件到场（贴底一步到
            // 位、几何面纹丝不动）才单发一评，正常
            // 路径下观察必先于它收官、它恒空转取消
            settleMachine.begin(animated: animated)
            settleGeneration = generation
            settleFallbackTask?.cancel()
            let pinnedThreadID = currentThreadID
            settleFallbackTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled,
                      currentThreadID == pinnedThreadID
                else { return }
                evaluateSettleFallback(proxy)
            }
        }
    }

    /// 落定评估的事件消费口（键盘整包 R4）：几何
    /// 事件（距底读数变化为主、尾锚事实翻转为辅）
    /// 到场即喂状态机一步——状态推进与判定全在
    /// Core BottomSettleMachine，本组函数只做协
    /// 调者对账（窥视/消费/解挂）与执行
    private func evaluateSettleOnEvent(
        _ proxy: ScrollViewProxy
    ) {
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
            step, proxy: proxy, generation: generation,
            distance: distance, viaFallback: false
        )
    }

    /// 有界单发兜底（评审合成条目 4 的口子）：观察
    /// 布防 2 秒仍无一几何事件到场——贴底已一步到
    /// 位且几何面静止，事件路无从触发；此时以当前
    /// 读数经 stepTimeout 喂回同一状态机（「无事
    /// 件」即静止证据，不另设判定）。单发、随收官
    /// /顶替/切线程取消，绝不循环、绝不自成落定
    /// 机制——正常路径下观察恒先收官、本路只空转
    private func evaluateSettleFallback(
        _ proxy: ScrollViewProxy
    ) {
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
            step, proxy: proxy, generation: generation,
            distance: distance, viaFallback: true
        )
    }

    /// 状态机一步结果的执行口：收官四值在此对账
    /// 协调者并落地（校准经单一派生点、复贴先清
    /// 账再执行防几何回调重入）；continue 无动作
    private func handleSettleStep(
        _ step: BottomSettleMachine.Step,
        proxy: ScrollViewProxy, generation: Int,
        distance: CGFloat, viaFallback: Bool
    ) {
        // §135 D 案打点：发送帧的首个落定评估读数
        // （距底＋是否复贴＋距发送耗时），每轮只记
        // 一笔——事件化后首评即旧首检的对应位（发
        // 送路恒无动画贴底、首个几何事件即落定读
        // 数，口径与旧读数可比）
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
            // 末端事实可见：经单一派生点校准在底
            // （钮随之消失），不复贴——屏幕上已无
            // 未见内容，复贴只会顶动
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
            performScrollToBottom(proxy, animated: false)
        case .continue:
            break
        }
    }

    /// 观察收官清账：代号与兜底任务一并落空（状态
    /// 机已在 step 内自回未观察态）
    private func closeSettleWatch() {
        settleGeneration = nil
        settleFallbackTask?.cancel()
        settleFallbackTask = nil
    }

    /// 贴底本体（不带落定观察）：scrollToBottom 的首贴与
    /// 复贴共用，复贴不经 scrollToBottom 以免自触发
    /// 再复核成环。animated 路的曲线＝回底弹簧（手
    /// 感 A 档）：响应按执行时点的实测距底缩放（引
    /// 用匣读数），落点与旧 pageCrossfade 路一致
    /// （同一 scrollTo 目标锚）
    private func performScrollToBottom(
        _ proxy: ScrollViewProxy, animated: Bool
    ) {
        if animated {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.scrollToBottomSpring(
                        distance: bottomDistanceRecorder.latest
                    ),
                    reduceMotion: reduceMotion
                )
            ) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
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
            ChatApprovalCard(store: store, record: record)
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
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
                Spacer()
                Text("已失效")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
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
        guard let request = appState.approvalAnchorRequest
        else { return }
        appState.approvalAnchorRequest = nil
        if appState.drawerThreadSelection != request.threadID {
            appState.drawerThreadSelection = request.threadID
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
                .foregroundStyle(Palette.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OneDayMetrics.spacingXS)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func bubble(_ entry: ChatEntry) -> some View {
        if entry.approvalKey != nil {
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
        } else if let card = entry.toolCard {
            // 0.8.0（P1）：工具卡条目（role="tool"）——
            // 不进气泡形态、不挂长按菜单、不进发送上下文
            ToolCardView(card: card)
        } else if entry.role == "user" {
            HStack {
                Spacer(minLength: OneDayMetrics.bubbleSideInset)
                // 基础止血包（P1/P2）：发送失败标记——
                // 红叹号挂气泡左侧（微信口径），点它以
                // 原条目重发；条目不删、不回退输入框，
                // 标记随重发成功落定清除
                if entry.sendFailed {
                    Button {
                        resendFailedEntry(entry)
                    } label: {
                        Image(systemName: "exclamationmark.circle.fill")
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
                }
                VStack(alignment: .trailing, spacing: OneDayMetrics.spacingXS) {
                    if let quote = entry.quote {
                        quoteBlock(quote)
                    } else if let feedQuote = entry.feedQuote {
                        feedQuoteBlock(feedQuote)
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
                        localImageRow(localImageDatas, entry: entry)
                    }
                    // 0.8.0（P1）：历史导入的服务端图片
                    // （标记路径）——缩略经文件下载通道
                    // 取回，点开同一个全屏查看器
                    ForEach(entry.remoteImagePaths, id: \.self) { path in
                        // §130：卡形由 ServerRemoteImage
                        // 本体承载（radiusCard），此处不再
                        // 外挂裁形（旧 spacingM 双重裁角）
                        ServerRemoteImage(path: path)
                            .onTapGesture {
                                openImageViewer(
                                    ChatImageViewerItem(
                                        source: .remotePath(path)
                                    )
                                )
                            }
                            // 0.43.0（A11Y-V2）：服务端图以
                            // 文件名为最低文本等价（A11yText
                            // 拼装）；动作与点按同一入口
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                A11yText.imageLabel(
                                    fileName: (path as NSString)
                                        .lastPathComponent
                                )
                            )
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(L10n.string("查看大图"))
                            .accessibilityAction {
                                openImageViewer(
                                    ChatImageViewerItem(
                                        source: .remotePath(path)
                                    )
                                )
                            }
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
                        SelectableInlineText(
                            paragraphs: [
                                .plain(
                                    TextShaping.prettyWrapDocument(
                                        entry.content
                                    )
                                )
                            ],
                            textStyle: .callout,
                            foreground: Palette.userBubbleText,
                            onSelectionChange: { active in
                                noteTextSelection(
                                    entryID: entry.id, active: active
                                )
                            }
                        )
                            .padding(.horizontal, OneDayMetrics.bubblePaddingH)
                            .padding(.vertical, OneDayMetrics.bubblePaddingV)
                            .background(
                                // 0.3.4 去染色（§19 变/不变表）：
                                // 用户气泡是表面容器、归中性，
                                // primaryTint 染色撤销
                                // 0.3.8 第 26 条：纯白 #FFFFFF
                                // 在 #FCFCFC 底上等于无气泡——
                                // 换中性浅灰 userBubbleFill，与
                                // 助手泡同家族拉开深浅、恒中性
                                Palette.userBubbleFill,
                                in: RoundedRectangle(cornerRadius: OneDayMetrics.bubbleCorner)
                            )
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
                    }
                    // 聊天可靠性包：待发条目的状态行——
                    // 消息留在原位不消失，状态只在气泡
                    // 下安静标明、点按即用同一条目重发
                    // （大厂口径：失败留痕＋一键重发，
                    // 不删不退回输入框）
                    if entry.isPendingSend {
                        Button {
                            resendPending(entry)
                        } label: {
                            HStack(spacing: 4) {
                                Image(
                                    systemName: "exclamationmark.circle"
                                )
                                Text(L10n.string("未发送 · 点按重发"))
                            }
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                        .disabled(isStreaming)
                        .accessibilityLabel(
                            L10n.string("未发送 · 点按重发")
                        )
                    }
                }
                .modifier(messageMenu(for: entry))
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
                        isStreaming: false
                    )
                }
                // 0.8.0（P1）：助手消息的服务端图片（历
                // 史导入形态）与用户侧同口径：缩略＋点开
                // 全屏
                ForEach(entry.remoteImagePaths, id: \.self) { path in
                    // §130：卡形由 ServerRemoteImage
                    // 本体承载（radiusCard），此处不再
                    // 外挂裁形（旧 spacingM 双重裁角）
                    ServerRemoteImage(path: path)
                        .onTapGesture {
                            openImageViewer(
                                ChatImageViewerItem(
                                    source: .remotePath(path)
                                )
                            )
                        }
                        // 0.43.0（A11Y-V2）：与用户侧同口
                        // 径——文件名最低文本等价＋同一
                        // 查看器入口
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            A11yText.imageLabel(
                                fileName: (path as NSString)
                                    .lastPathComponent
                            )
                        )
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(L10n.string("查看大图"))
                        .accessibilityAction {
                            openImageViewer(
                                ChatImageViewerItem(
                                    source: .remotePath(path)
                                )
                            )
                        }
                }
                // §136：MEDIA: 标记的图片行——存在性
                // 门在 AssistantMediaImage（与 §129
                // 文件牌同源三分判定：确证存在才出
                // 图，查无/查不成整行不显示、绝不露
                // 标记原文）
                ForEach(mediaSplit.imagePaths, id: \.self) { path in
                    AssistantMediaImage(path: path) {
                        openImageViewer(
                            ChatImageViewerItem(
                                source: .remotePath(path)
                            )
                        )
                    }
                }
                // §143：裸路径图片行——与 MEDIA 行同
                // 形态（AssistantMediaImage §130 定高
                // 卡），存在性门在视图本体
                ForEach(inlineImages, id: \.path) { ref in
                    AssistantMediaImage(path: ref.path) {
                        openImageViewer(
                            ChatImageViewerItem(
                                source: .remotePath(ref.path)
                            )
                        )
                    }
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
                        ServerRemoteImage(path: wholePathRef.path)
                            .onTapGesture {
                                openImageViewer(
                                    ChatImageViewerItem(
                                        source: .remotePath(
                                            wholePathRef.path
                                        )
                                    )
                                )
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                A11yText.imageLabel(
                                    fileName: (wholePathRef.path
                                        as NSString)
                                        .lastPathComponent
                                )
                            )
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(L10n.string("查看大图"))
                            .accessibilityAction {
                                openImageViewer(
                                    ChatImageViewerItem(
                                        source: .remotePath(
                                            wholePathRef.path
                                        )
                                    )
                                )
                            }
                    } else {
                        BarePathFileCard(path: wholePathRef.path) {
                            openChatFile(
                                wholePathRef.path,
                                anchor: wholePathRef.anchor
                            )
                        }
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
                    assistantBubble {
                        // §152：选区回报接行级记账（选
                        // 字期间关本行右滑引用）
                        MarkdownText(
                            displayText,
                            onSelectionChange: { active in
                                noteTextSelection(
                                    entryID: entry.id, active: active
                                )
                            }
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
                }
            }
            .modifier(messageMenu(for: entry))
            .modifier(swipeReply(for: entry))
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
        // §199：解码改走 LocalImageDecodeCache（同
        // 条目同图序只解一次、命中直取）；解码失败
        // 单张不出卡的旧口径不变（坏图不入缓存）
        let pairs: [(data: Data, image: UIImage)] =
            datas.enumerated().compactMap { index, data in
                guard let image = LocalImageDecodeCache.shared
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
        return ZStack {
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
        .onTapGesture {
            openImageViewer(
                ChatImageViewerItem(source: .data(data))
            )
        }
        // 0.43.0（A11Y-V2）：本地图最低文本等价——
        // 发送时刻（A11yText 拼装、Core 钉测）；动
        // 作与点按同一入口（openImageViewer）
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            A11yText.imageLabel(sentAt: entry.createdAt)
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L10n.string("查看大图"))
        .accessibilityAction {
            openImageViewer(
                ChatImageViewerItem(source: .data(data))
            )
        }
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
            showNotice(FileOpenFailure.invalidPath.message())
            return
        }
        fileOpenTarget = FileOpenTarget(path: path, anchor: anchor)
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
        composerFocusHandle.focus()
    }

    /// §152 选区在场记账：正文文本块（Selectable-
    /// InlineText）经 onSelectionChange 回报——选
    /// 区在场时该行右滑引用停用（拖选字手柄的横向
    /// 位移不许误触引用，DESIGN §152.3 第 4 条）；
    /// 消选延迟 350ms 清账，防同一条内换块选字时
    /// 旧块消选先于新块报选到达、把保护误清
    private func noteTextSelection(entryID: UUID, active: Bool) {
        if active {
            selectionClearTask?.cancel()
            selectionClearTask = nil
            activeSelectionEntryID = entryID
        } else if activeSelectionEntryID == entryID {
            selectionClearTask?.cancel()
            selectionClearTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                activeSelectionEntryID = nil
            }
        }
    }

    /// 气泡长按菜单挂载（0.4.1）：纯图片消息（正文空）
    /// 不挂——四项全是文本动作，空文本挂上只剩坏体验
    /// （引用摘要为空、复制/分享空串）
    private func messageMenu(for entry: ChatEntry) -> MessageMenuModifier {
        let text = plainText(for: entry)
        return MessageMenuModifier(
            isEnabled: !entry.content.isEmpty,
            plainText: text,
            onReply: {
                beginReply(to: entry)
            },
            onFork: {
                forkToSideChat(from: entry)
            },
            onSelect: {
                selectionPayload = SelectionPayload(text: text)
            }
        )
    }

    /// 右滑引用挂载（0.36.19，§84.3）：与长按菜单同门
    /// 控（纯图片消息不挂）——自己与对方的消息都可滑，
    /// 触发走 beginReply 同一入口；与长按菜单并存不
    /// 互斥（长按是静止按压、右滑是横向拖动，形态不
    /// 重叠）
    private func swipeReply(for entry: ChatEntry) -> SwipeReplyModifier {
        SwipeReplyModifier(
            // §152：本行正文有选区在场时停用——拖
            // 选字手柄与右滑引用同为横向拖动手势，
            // 选字优先（仲裁见 DESIGN §152.3 第 4
            // 条）；选区清空（延迟清账后）自动恢复
            isEnabled: !entry.content.isEmpty
                && activeSelectionEntryID != entry.id,
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
            appState.feedOpenPostRequest = quote.postID
            appState.mainTabSwitchRequest = .feed
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

    /// 助手消息行（0.2.5 曾定浅灰软填充泡＋圆角卡，见下
    /// 改判）：左对齐、右侧留白上限与用户泡的 44pt 让位
    /// 同逻辑，内外边距沿旧泡口径。
    /// 割裂感 A 止血档 A1 改判（2026-11-13，用户 17:02
    /// 拍板提队）：撤 bubbleFill 背景——散文直落
    /// chatSurface 大面，对齐 Muse／ChatGPT 的单一连
    /// 续底面语法（助手散文不成卡；代码块/表格/工具
    /// 卡/文件卡等异构件保留各自承载，本函数只包散文
    /// 与流式半截/等待点，两者同路落面）。泡内子件对
    /// 比账按调研 A1 逐项复核（WCAG 公式同式心算）：
    /// 次级文字 inkSecondaryOnFill 落面后浅档 #5F666B
    /// 对 #FCFCFC＝5.69:1（原泡面 #EEEEF0 上 5.04）、
    /// 暗档 secondaryLabel 压 #000 合成 6.36:1（原泡
    /// 面 5.29），两档均升；代码面 codeFill 与底面步
    /// 幅浅档 1.24:1（原 1.10）、暗档同级，子件无一
    /// 因落面跌破原账，令牌零改动。bubbleFill 令牌本
    /// 体保留（用户图卡底等其他消费点不动）；函数名
    /// 沿旧名以保调用点零改动与沿革可追。
    private func assistantBubble<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(alignment: .top) {
            content()
                .padding(.horizontal, OneDayMetrics.bubblePaddingH)
                .padding(.vertical, OneDayMetrics.bubblePaddingV)
            Spacer(minLength: OneDayMetrics.bubbleSideInset)
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
    /// 回响卡数据源刷新（P2 会话包）：主线拉近百条全
    /// 量（呈现收窄在 TraceEchoPolicy）、旁聊只拉指向
    /// 本会话的（桥侧 targetId 过滤）。拉取失败保留已
    /// 有卡、不清空不报错——回响是呈现层拼装，桥一时
    /// 不通不该在对话里另摆错误面，下次触发自会再拉；
    /// 但也不许拿空结果冒充「没有动作发生」。触发点
    /// 两处：进页/切线程（.task(id:)）、每轮生成落定
    /// （流式下降沿，2026-11-13 补——AI 的内部动作恰
    /// 在本轮内发生，只等切线程才刷等于当轮无卡）
    private func refreshEchoTraces() async {
        guard let config = appState.config else { return }
        let client = OneDayBridgeClient()
        do {
            if isCurrentMainThread {
                echoTraces = try await client.traces(
                    config: config, limit: 100
                )
            } else if let sessionID = currentThread?.serverSessionID {
                echoTraces = try await client.traces(
                    config: config, limit: 100, targetId: sessionID
                )
            }
        } catch {
            // 保留已有回响（见函数头注）
        }
    }

    private func reportCard(
        _ item: OverviewNotification, store: OverviewBridgeStore
    ) -> some View {
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
        // 0.17.0：回告卡点按与胶囊身份域同路——开枢纽
        // sheet（活动格撤销前的落点是切活动格）
        .onTapGesture { showHub = true }
    }

    /// 直播思考块（0.36.10 自 streamingRow 拆出）：
    /// 折叠单元独立成段、按 liveOrder 落位（诊断
    /// D3-10）；相位口径不变——正文已发布或工具卡已
    /// 到即思考期结束，折叠单元据此自动收起（硬规
    /// 格：正文起流后思考不许继续整屏展开）
    @ViewBuilder
    private var liveReasoningBlock: some View {
        if let reasoning = streamingReasoning {
            ReasoningBlock(
                text: reasoning,
                seconds: nil,
                isStreaming: true,
                startedAt: reasoningStartedAt,
                contentStarted: !(streamingText ?? "").isEmpty
                    || !liveToolCards.isEmpty
            )
        }
    }

    @ViewBuilder
    private func streamingBubble(_ text: String) -> some View {
        if text.isEmpty {
            assistantBubble {
                // 0.32.1（F05 止血）：Qwen 冷启「模型唤醒中」
                // 提示整路拆除——该模型已停用下线，不再有
                // 唤醒态；等待一律只剩打字点
                // 基础止血包（P7 文案半步）：文件上传段
                // 例外——如实说上传中，不许让等待点冒充
                // 生成中（进度百分比归上传正解包）
                if isUploadingFiles {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        TypingDots()
                        Text("正在上传文件…")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, OneDayMetrics.spacingXS)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("正在上传文件")
                } else {
                    TypingDots()
                        .padding(.vertical, OneDayMetrics.spacingXS)
                }
            }
        } else {
            assistantBubble {
                // 条 4（§14）：流式走渐显组件逐字入场；
                // Markdown 只在落盘成品上渲染
                StreamingText(text)
            }
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

    /// 错误横幅的「重新发送」目标（基础止血包 P2 横
    /// 幅动作位）：最近失败条目仍在当前线程且仍挂失
    /// 败标记时才有——§140 注记里欠的「动作位归二
    /// 包」在此兑现（气泡旁叹号是同一动作的另一入
    /// 口，两处同走 resendFailedEntry）
    private var failedResendTarget: ChatEntry? {
        guard let id = failedResendEntryID,
              let thread = currentThread,
              let entry = thread.entries.first(
                  where: { $0.id == id }
              ), entry.sendFailed else { return nil }
        return entry
    }

    private func errorBanner(
        _ message: String, onResend: (() -> Void)? = nil
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
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if let onResend {
                    Button {
                        onResend()
                    } label: {
                        Text("重新发送")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.primary)
                            .frame(
                                minHeight: OneDayMetrics.minTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
                Button {
                    errorMessage = nil
                    failedResendEntryID = nil
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

    /// 提示条赋值唯一口（§140 提示纪律第 3 条）：带档
    /// 位赋值即起自清计时（中性 5s／重要 8s，档位秒
    /// 数在 Core ChatNoticeTier）；换代先取消旧计时，
    /// 自清只清自己那一代（Core expire 代号判定），
    /// 手关后旧计时到期不复活。计时模式沿听写提示行
    /// 先例（DictationController.showNotice）
    private func showNotice(
        _ text: String, tier: ChatNoticeTier = .brief
    ) {
        let item = ChatNotice(text: text, tier: tier)
        noticePresentation.present(item)
        noticeDismissTask?.cancel()
        noticeDismissTask = Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(item.tier.autoDismissSeconds)
            )
            guard !Task.isCancelled else { return }
            noticePresentation.expire(id: item.id)
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
    /// 对位规格（0.2.8 改基数，§12.3）：正文行高实测 19.17
    /// （0.2.9 校准，§13.2）＋文本纵向边距 10＝文本侧约 30，
    /// 与 30pt 两键在 HStack(.bottom) 里同高（中心重合）；
    /// 多行时两键底边与 field 底边齐平，锚在最后一行。胶囊
    /// 单行总高＝30＋行纵向边距 16＝46（算术归 Composer-
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

    private var inputBar: some View {
        // §176（2026-11-12，气泡间距收口）：栈间距归
        // 零——旧 spacingS 下两层 SmoothExpand 折叠高
        // 为 0 也照收两份间距（16pt，诊断九环第 8
        // 环），且任一条展开时，隐藏的另一层仍在替它
        // 收费（单条展开时条→卡实距 16）。改法：间距
        // 改由展开条自带底边距承载（见两处条注），收
        // 起时随帧高 0 被裁剪、不计费；展开时恒隔
        // spacingS，与旧口径同值
        VStack(spacing: 0) {
            // 0.36.6（§71）：语音失败行与到限提示行——
            // 三段式文案（发生了什么＋影响＋怎么办），
            // 权限被拒在此给「去设置」降级路（续编 S4）
            // §176：底边距长在条本体上——SmoothExpand
            // 的实测高含它、展开帧高含它；收起帧高 0
            // 时一并裁掉（见栈头注）
            SmoothExpand(isExpanded: dictation.failure != nil) {
                if let failure = dictation.failure {
                    dictationFailureBar(failure)
                        .padding(.bottom, OneDayMetrics.spacingS)
                }
            }
            SmoothExpand(isExpanded: dictation.notice != nil) {
                if let notice = dictation.notice {
                    dictationNoticeBar(notice)
                        .padding(.bottom, OneDayMetrics.spacingS)
                }
            }
            // 输入舱卡（0.36.19 起引用块并入同卡，见
            // composerCard）：表面沿革——0.2.7 裸玻璃 →
            // 0.3.7 卡 19 撤玻璃改灰填充 → 0.3.8 第 28 条
            // 白浮纸（floatFill＋发丝边＋双环影）→ **0.4.1
            // 回系统玻璃**（用户 10:06/10:07 两点名：第 3
            // 修「输入栏与底部导航栏颜色不一致」＋第 7 修
            // 「改 Muse 本体形态：白色大圆角卡片」）：
            // .glassEffect(.regular) 与原生底栏同为 iOS 26
            // Liquid Glass 家族——同材质即同观感，不再自
            // 调灰阶对色。形态要素沿既有结构：圆角连续函
            // 数封顶 24（大圆角量级）、＋在卡内左下、发送
            // 圆形键在卡内右下、多行上文下钮（Composer-
            // BarLayout，0.3.4 定版）；自量高＋硬封顶（例
            // 外 E1）结构不动。白浮纸的发丝边与双环手搓
            // 影一并撤销（玻璃自带边缘折光与层级，§14 条
            // 2 的影口径随材质换代退役）
            composerCard
                // A2（割裂感止血档）：卡本体帧回报——与
                // 整栈帧（桥侧 ComposerBarFrameKey）同
                // 法同系，经托管树 Preference 上行喂
                // ComposerGuideHost 定底衬高：衬顶随卡
                // 顶、整栈其余段（回底钮行/条带）不再
                // 进衬。量点只读帧、不接命中、不改布局
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ComposerCardFrameKey.self,
                            value: proxy.frame(in: .global)
                        )
                    }
                }
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        // 0.36.27（§97 件二）：顶 padding 收一档
        // spacingS 8 → spacingXS 4（卡上外距，与列表
        // 底 contentMargins 同步，链总量 32 → 24）
        // §176：顶 padding 归零（本行删除）——气泡→
        // 输入舱卡顶的边距单点归列表底 contentMar-
        // gins 一处（见列表侧 §176 注），本处不再计量
        .padding(.bottom, OneDayMetrics.spacingS)
        // 提议链断环（0.2.5 根因注，§9）：本 VStack 的高度
        // 只认内容，不许把外层提议透传给胶囊
        .fixedSize(horizontal: false, vertical: true)
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
                // 0.36.9：失败行同挂诊断行（末阶段上
                // 屏，礼记同案后手——见 DictationViews）
                DictationStageDiagnosticLine()
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
                    .contentShape(Rectangle())
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
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(
                                cornerRadius: OneDayMetrics.codeCorner
                            ))
                    }
                }
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

    /// 输入舱卡（0.36.19 入舱，§84）：玻璃卡的承载层——
    /// 待发送引用块（有则显）、待发附件条（有则显）自
    /// 上而下各带一条发丝分隔线、输入行（composerRow，
    /// 标准行/录音条两态）在下，一张卡。
    /// 0.4.1–0.36.18 引用条是输入舱外的一张独立浮卡，
    /// 用户 2026-11-11 00:24 点题「一个在输入框里面，
    /// 一个在外面」不对——对照 Muse 本体：引用嵌在输
    /// 入舱内（引用块在上、分隔线、打字行在下）。
    /// 高度核算：舱高＝引用块＋分隔线＋输入行整卡实测
    /// （本层的 onGeometryChange 回写喂玻璃圆角连续半
    /// 径）；输入行内部的文本量测与 6 行封顶只管文本
    /// 域本身（ComposerLayout/ComposerBarLayout 口径
    /// 不变），引用块高计入舱高、不挤占打字行数
    private var composerCard: some View {
        VStack(spacing: 0) {
            // 引用块出现/消失走 SmoothExpand 平滑高度
            // （条 7）；分隔线随引用块同进同出；满宽
            // claim 落在本层（卡 VStack 的直接子层）——
            // P-13 续案口径与附件条同，见下方附件条注
            SmoothExpand(isExpanded: pendingQuote != nil || pendingFeedQuote != nil) {
                if let pendingQuote {
                    VStack(spacing: 0) {
                        quoteBar(pendingQuote)
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                            .padding(
                                .horizontal, OneDayMetrics.spacingSM
                            )
                    }
                } else if let pendingFeedQuote {
                    // §208：动态引用与消息引用共用本槽
                    // 位（至多一个在场），feed 变体渲染
                    VStack(spacing: 0) {
                        feedQuoteBar(pendingFeedQuote)
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                            .padding(
                                .horizontal, OneDayMetrics.spacingSM
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 待发附件条（0.36.19 入舱 §84.4；0.36.26
            // §95 移出量测层）：0.36.19 把满宽锚加在条
            // 内部两层、0.36.23 上移到卡直接子层，两
            // 轮真机居中分毫未动。调研裁决（produc-
            // tion-patterns-research-20261111 §2.3）：
            // 元凶是包着条的 SmoothExpand 量测层——
            // 它以实测内容理想尺寸为准定尺寸，条收到
            // 的宽度提议在到达条之前已被换成内容宽，
            // .frame(maxWidth:) 只能花提议到的宽
            // 度，两轮挪落点自然全数落空（同在该层下
            // 的引用块因自身近满宽把缺陷掩盖至今）。
            // 本轮按两家生产构造同构改（Stream
            // attachmentsTray／Exyte viewOnTop 同
            // 位）：条作卡根 VStack 的直接子级、条件
            // 包含显隐、链上三处 frame 补丁删尽；满
            // 宽由 ScrollView 对根栈提议的默认贪婪获
            // 得，左起由滚动内容自带横向 padding 获
            // 得。分隔线随条同进同出（挂同一直接子
            // 级的小 VStack 内）。引用块本轮不动
            // （仍在 SmoothExpand，最小范围）
            // 0.36.27 订正：上段「元凶是量测层」的单
            // 一归因已被 0.36.26 真机证伪（移出后仍居
            // 中）；0.36.27 续记的「包装层缺满宽 claim」
            // 说亦已被 0.36.28 真机证伪——第五轮定案
            // （0.36.29）：四轮共同死因是范畴错误，决
            // 定层是包装栈自身的 alignment 参数，修
            // 法见下方包装栈注与错题本 P-13；移出量测
            // 层本身保留（与生产构造同构、无回退理由）
            // 0.36.31 续记：第五轮修法真机再证伪，第
            // 六轮按呈报口径结构换代——条本体 Scroll-
            // View＋HStack 整类退役、改 Attachment-
            // FlowLayout 流式行（见 attachmentsStrip
            // 注与错题本 P-13 续案六）；包装栈与分隔
            // 线形态不动
            if !attachments.isEmpty {
                // 0.36.29（P-13 第五轮定案）：条的横向位
                // 置由本包装栈自身的 alignment 参数决
                // 定——四轮全灭皆因改的是 .frame 的
                // alignment（只管「栈整体在他处怎么
                // 放」、管不到栈内子视图），栈自身
                // alignment 四轮一直默认 .center 从未
                // 被改。此处改 .leading 一词落到决定
                // 层；第 4 轮挂的 frame claim 经定案属
                // 无效修饰、一并删除（详见错题本 P-13）
                VStack(alignment: .leading, spacing: 0) {
                    attachmentsStrip
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                        .padding(
                            .horizontal, OneDayMetrics.spacingSM
                        )
                }
                // 条内容只淡入淡出防闪现；高度变化由
                // 卡根 .animation(attachments.count)
                // 的事务插值承接（见 composerCard 尾注）
                .transition(.opacity)
            }
            composerRow
        }
        // 条显隐的高度动画（0.36.26 §95）：键原为
        // attachments.isEmpty（条高只在空↔非空之间
        // 变）；0.36.31 条改流式行多行化后，加/删筹
        // 码改行数同样改变条高，键扩为 attachments.
        // count——变化进动画事务后卡高（及安全区留白）
        // 同帧插值，不再靠 SmoothExpand 的实测回
        // 写；玻璃半径由卡层 onGeometryChange 的实
        // 测高连续函数逐帧跟随，无跳变源。动画令牌
        // 与 SmoothExpand 同源（MotionTokens.
        // swap、Reduce Motion 经 resolved 收口）
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: attachments.count
        )
        // 第 1 修（P0 键盘不弹）的聚焦保底层：整卡背景
        // 命中域内点按（文本区外的卡面空隙，含引用块
        // 段的空隙）经焦点句柄聚焦文本视图。根因与定
        // 位见 DESIGN-V4 §26.7：焦点机器代码 0.3.8→
        // 0.4.0 逐字未动（diff 实证），回归随底栏可见化
        // 同批出现——文本视图自身触摸成为单点故障，本
        // 层把「点输入栏必弹键盘」改成双通道构造（文本
        // 视图直触＋卡面点按），不再依赖单一路径的环境
        // 状态。0.4.1 起本层挂在 composerRow 上，0.36.19
        // 随玻璃施加点上移到卡层、命中域扩到整卡
        .background {
            Color.clear
                .contentShape(composerShape)
                .onTapGesture {
                    composerFocusHandle.focus()
                }
        }
        .glassEffect(.regular, in: composerShape)
        // 实测高在布局周期内回写（0.3.5，§20）：只喂玻
        // 璃圆角的连续半径（见 composerShape），高度本
        // 身不经任何动画——形态切换一帧落定。回写点
        // 0.4.1–0.36.18 在 composerRow 上（只量输入行），
        // 0.36.19 起上移卡层量整卡（引用块计入舱高）；
        // 0.2.6–0.3.4 的离散形状动画已整条撤销（理由见
        // standardComposerRow 沿革注）
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { _, newHeight in
            if abs(newHeight - composerCapsuleHeight) > 0.5 {
                composerCapsuleHeight = newHeight
            }
        }
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
    /// - 流式中：停止键（0.31.0 起走 requestRunStop 真取消）
    /// - 有可发送内容（文字或附件）：发送箭头
    /// - 空输入：裸麦克风符号占位（无圆盘底、无描边）
    /// 0.25.0（动效专包）：三态判定收敛 Core
    /// ComposerTrailingState（单测把守）；mic↔圆盘键的
    /// 切换原为两视图硬切——改同槽 ZStack 交叉淡化：
    /// 切换只发生在「空↔首字」「发送↔流式起止」的低
    /// 频边沿（非逐键），swap 0.2 淡化在频率预算内；
    /// 发送↔停止在圆盘键内部走 symbolEffect 形变（既
    /// 有）、不经本淡化。Reduce Motion 时 resolved 归
    /// 零、回硬切（瞬时）
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
        Button {
            if isStreaming {
                // 0.31.0：停止＝runs 真取消（requestRun-
                // Stop 发服务端 stop），不再是旧通道的
                // 本地断流假取消
                requestRunStop()
            } else {
                send()
            }
        } label: {
            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: isStreaming ? 12 : 13, weight: .bold))
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
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(isStreaming ? "停止生成" : "发送")
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
                .contentShape(Circle())
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
        // 行走 DocumentPickerBridge，P-18 桥不回退）
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
                .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("添加附件")
    }

    /// §152 修订二：附件面板 sheet 的 detent 集——
    /// 内容高已量得时单档贴内容；尚未量得（首帧）回
    /// 落 .medium 过渡，量到即换贴合高。§154 热修：
    /// screenHeight 只许传宿主真高（根层回写值），
    /// 且决策含可信下限——量测链任何一环坏掉都回
    /// 落 .medium 照常开，绝不再现塌陷
    private func attachPanelDetents(
        screenHeight: CGFloat
    ) -> Set<PresentationDetent> {
        if let height = AttachmentPanelLayout.detentHeight(
            measured: attachPanelContentHeight,
            screenHeight: screenHeight
        ) {
            return [.height(height)]
        }
        return [.medium]
    }

    /// §147：附件面板内动作的统一收尾——先收面板、
    /// 隔一拍再执行呈现型动作（相机全屏盖/选图器/
    /// 文件桥），不与 sheet 收起动画同帧抢呈现上下
    /// 文（同 DocumentPickerBridge 的延拍口径）
    private func afterAttachPanelDismiss(
        _ action: @escaping () -> Void
    ) {
        showAttachPanel = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            action()
        }
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
            showNotice(notices.joined(), tier: .extended)
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
            showNotice(notice, tier: .extended)
        }
    }

    /// 文件接入（0.36.31 件二＋件三重写）：入参自
    /// UIKit 桥 DocumentPickerBridge（asCopy 副本
    /// URL，落在 App 容器内——旧 .fileImporter 路
    /// 的安全作用域起停配对随桥退役，本函数直读）。
    /// 逐个先查 fileSize 再读数据：超限不整份读入
    /// 内存（旧链先读 82.8MB 才判闸）；被拒文件
    /// （超限/读失败）由 Core FileIntake 汇总点名
    /// 一条 notice，不再逐个写、后写覆盖先写只剩
    /// 最后一个名。大小闸 20MB → 100MB 与服务端
    /// 托管上传契约对齐（file-upload-contract-
    /// 20261111：解码后上限 100MiB）。出口有声口
    /// 径（P-18）保留：空数组明示、读失败点名汇总
    /// 并落诊断面
    private func loadPickedFiles(urls: [URL]) {
        guard !urls.isEmpty else {
            showNotice(
                "没有选到文件，未加入待发列表。", tier: .extended
            )
            return
        }
        var oversized: [String] = []
        var unreadable: [String] = []
        var transcodedNames: [String] = []
        var undecodableNames: [String] = []
        for url in urls {
            let name = url.lastPathComponent
            let declaredSize = (try? url.resourceValues(
                forKeys: [.fileSizeKey]
            ))?.fileSize
            if FileIntake.sizeVerdict(declaredSize: declaredSize)
                == .tooLarge {
                oversized.append(name)
                continue
            }
            guard let data = try? Data(contentsOf: url) else {
                unreadable.append(name)
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
                oversized.append(name)
                continue
            }
            // 转码账只记真入条的：被大小闸拒掉的文件
            // 不进转码提示名单，免得两份名单对不上
            switch upload.outcome {
            case .transcoded: transcodedNames.append(name)
            case .undecodable: undecodableNames.append(name)
            case .unchanged: break
            }
            attachments.append(
                PendingAttachment(
                    kind: .file(name: name, data: upload.data)
                )
            )
        }
        if !unreadable.isEmpty {
            ChatDiagTrace.record(
                "选文件读取失败 \(unreadable.count) 个："
                    + unreadable.joined(separator: "、")
            )
        }
        let summaries = [
            FileIntake.rejectionNotice(
                oversized: oversized, unreadable: unreadable
            ),
            FileIntake.transcodeNotice(
                transcoded: transcodedNames,
                undecodable: undecodableNames
            ),
        ].compactMap { $0 }
        if !summaries.isEmpty {
            showNotice(summaries.joined(), tier: .extended)
        }
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
    /// 「主线」、绑定本地生成并持久化的服务端会话 id、
    /// 写入钦定。服务端承载的实际存在性由
    /// ensureMainLink 异步链接，本函数纯本地
    @discardableResult
    private func ensureMainThread() -> UUID? {
        let store = appState.sideChats
        switch MainThreadDesignation.resolve(
            storedID: store.mainThreadID, existingIDs: threads.map(\.id)
        ) {
        case .existing(let id):
            if let main = threads.first(where: { $0.id == id }) {
                let sessionID = store.ensureMainServerSessionID()
                if main.serverSessionID != sessionID {
                    // §216：改绑前先迁账——旧绑定键下的
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
            thread.serverSessionID = store.ensureMainServerSessionID()
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

    /// 链接一条线程到它的自有服务端会话（0.27.0，
    /// 主线/旁聊共用）：desiredID 为目标会话 id（主
    /// 线＝钦定 id、旁聊＝已存自有 id 或新铸）。流程
    /// 先 GET 查存，按服务端现状与种子有无分三路：
    /// ①不存在：无种子走网关建会话（Bearer）、有种
    ///   子走 import 一次落行＋全量消息（围栏修订 0）；
    /// ②存在但空行且本地有种子：import 补种（围栏
    ///   修订取 GET 回的 runtime_revision）；
    /// ③存在且已有消息：服务端已持历史，直接认链。
    /// 任一步失败抛错（不许静默、不许回退无头发送）；
    /// 返回最终会话 id（建会话回执为准）
    private func performLink(
        desiredID: String, title: String?, model: String?,
        seedEntries: [SeedEntry]
    ) async throws -> String {
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
            if (existing.messageCount ?? 0) == 0, !seed.isEmpty {
                try await importSeed(
                    id: desiredID, title: title, model: model,
                    seed: seed,
                    expectedRevision: existing.runtimeRevision ?? 0
                )
            }
            return desiredID
        }
        if seed.isEmpty {
            if let model {
                let created = try await appState.client
                    .createLinkedServerSession(
                        config: requireConfig(), apiKey: apiKey,
                        id: desiredID, model: model
                    )
                return created.id
            }
            let created = try await appState.client.createServerSession(
                config: requireConfig(), apiKey: apiKey,
                id: desiredID, title: title
            )
            return created.id
        }
        try await importSeed(
            id: desiredID, title: title, model: model,
            seed: seed, expectedRevision: 0
        )
        return desiredID
    }

    /// import 种子一步（Dashboard cookie 通道）：
    /// request_id 每发新铸；落定不看回执——perform-
    /// Link 返回后由发送/回读链自然验证，此处 2xx
    /// 之外全抛
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
                config: config, requestID: UUID().uuidString,
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

    /// 主线链接（0.27.0，代旧 ensureMainServerSession）：
    /// 已链（确认＋种子双位）直接返 true；否则以钦
    /// 定 id＋主线本地条目走 performLink——成功置双
    /// 位并回写主线线程绑定，失败**不许静默**：原因
    /// 原文落 SideChatStore（设置页展示）、返 false，
    /// 调用方（进页预热或发送前链接）据此决定呈现。
    /// 旧口径「失败静默、发送走无状态重放不依赖本确
    /// 认」就此作废——那正是串话的存续条件
    /// seedSnapshot：发送路径必传（本轮条目落盘前
    /// 的快照——现取会把本轮新消息也导进种子、与随
    /// 后的尾条发送在服务端落两份）；进页预热传 nil
    /// 时现取主线全量条目（彼时无发送在飞）
    @discardableResult
    private func ensureMainLink(seedSnapshot: [SeedEntry]? = nil) async -> Bool {
        let store = appState.sideChats
        if store.mainServerConfirmed, store.mainServerSeeded {
            return true
        }
        guard appState.config != nil else { return false }
        let wantedID = store.ensureMainServerSessionID()
        let mainThread = store.mainThreadID.flatMap { id in
            threads.first { $0.id == id }
        }
        do {
            let linkedID = try await performLink(
                desiredID: wantedID, title: SideChatStore.mainTitle,
                model: nil,
                seedEntries: seedSnapshot
                    ?? mainThread.map(Self.seedEntries(of:)) ?? []
            )
            if linkedID != wantedID {
                // §216：改绑/收养落定先迁账（旧键存量选
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
                mainThread.serverSeeded = true
                try? modelContext.save()
            }
            store.markMainLinked()
            return true
        } catch {
            store.noteMainLinkError(
                (error as? HermesError)?.userMessage ?? "主线会话链接失败"
            )
            return false
        }
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
        if let origin = appState.channelViewingOrigin,
           currentThread?.serverSessionID == origin.sessionID {
            appState.currentDrawerObject = .channel(origin.channelID)
            return
        }
        if appState.channelViewingOrigin != nil {
            appState.channelViewingOrigin = nil
        }
        appState.currentDrawerObject =
            DrawerSelectionPolicy.object(
                forThreadID: currentThread?.id,
                mainThreadID: appState.sideChats.mainThreadID
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
        guard appState.pendingChatSessionID == id else { return }
        appState.pendingChatSessionID = nil
        let channelID = appState.pendingChatChannelID
        appState.pendingChatChannelID = nil
        await runImport(sessionID: id, channelID: channelID)
    }

    /// 导入执行体（消费口与失败重试行共用）：出处先
    /// 行落位、按结果收尾；失败除横幅外另记重试上下
    /// 文（基础止血包 P6——旧口径失败只剩一句横幅、
    /// 想重试只能回列表再点一次）
    private func runImport(
        sessionID id: String, channelID: String?
    ) async {
        importRetryContext = nil
        // 出处先行落位：导入途中 currentThreadID 变
        // 更触发的同步据此把对象引用派生成 .channel
        appState.channelViewingOrigin = channelID.map {
            ChannelViewingOrigin(channelID: $0, sessionID: id)
        }
        let outcome = await openServerSession(id)
        if let channelID {
            switch outcome {
            case .switchedExisting, .importedNew:
                // 落点已定：对象引用归频道行（导入途
                // 中的同步可能已派生过，此处收尾钉死）
                appState.currentDrawerObject = .channel(channelID)
                if outcome == .importedNew {
                    showNotice("已转入我的对话")
                }
            case .failed:
                // 没打开成（仍停在原线程）：出处作废、
                // 对象引用按当前线程回派，不许把胶囊
                // 挂到没在看的频道行上
                appState.channelViewingOrigin = nil
                syncDrawerObjectFromCurrentThread()
            }
        }
        if outcome == .failed {
            importRetryContext = (sessionID: id, channelID: channelID)
        }
    }

    /// 打开服务端会话的结果（0.36.29）：频道消费口
    /// 据此定出处与收养提示——切到既有线程与新建导
    /// 入都算落点已定，只有新建导入算「首次收养」
    private enum OpenServerSessionOutcome: Equatable {
        case switchedExisting
        case importedNew
        case failed
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
    private func openServerSession(
        _ id: String
    ) async -> OpenServerSessionOutcome {
        if let existing = threads.first(where: { $0.serverSessionID == id }) {
            currentThreadID = existing.id
            return .switchedExisting
        }
        guard importingSessionID == nil else { return .failed }
        importingSessionID = id
        defer { importingSessionID = nil }
        do {
            let session = try? await appState.performAdmin { client, config in
                try await client.serverSession(config: config, id: id)
            }
            let messages = try await appState.performAdmin { client, config in
                try await client.sessionMessages(config: config, id: id)
            }
            // 标题仍走旧口径（首条用户消息摘要同源）
            let titleEntries = SessionHistoryImport.importableEntries(
                from: messages
            )
            // 0.8.0（P1）：落盘改富内容导入——工具调用
            // 成卡、图片标记剥成路径，呈现层有卡有图；
            // 工具卡 role="tool" 不进发送上下文（send
            // 组装只取 user/assistant）
            let entries = SessionHistoryImport.richItems(
                from: messages
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
            if let started = session?.startedDate {
                thread.createdAt = started
            }
            thread.updatedAt = session?.endedDate
                ?? session?.startedDate ?? Date()
            modelContext.insert(thread)
            for entry in entries {
                let chatEntry = ChatEntry(
                    role: entry.role, content: entry.content,
                    thread: thread, toolCard: entry.toolCard,
                    remoteImagePaths: entry.imagePaths,
                    remoteFilePaths: entry.fileRefs
                )
                if let date = entry.date {
                    chatEntry.createdAt = date
                }
                modelContext.insert(chatEntry)
            }
            try? modelContext.save()
            currentThreadID = thread.id
            return .importedNew
        } catch {
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
            } else {
                errorMessage = (error as? HermesError)?.userMessage
                    ?? "会话导入失败，请稍后重试。"
            }
            return .failed
        }
    }

    /// FA-1：讨论信号待发判定——线程有待发关联、
    /// 且线程内尚无任何用户条目（本轮将落的即首
    /// 句）才返回帖 id；关联在但已有用户条目＝首句
    /// 时机已过（信号只认首句，过期不补发）
    private func feedDiscussSignalTarget(thread: ChatThread) -> String? {
        guard let postID = appState.sideChats.feedDiscussPostID(
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
        appState.sideChats.clearFeedDiscuss(forThreadID: threadID)
        guard let config = appState.config else { return }
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
        guard !isStreaming, !text.isEmpty || !pending.isEmpty else { return }
        // 0.3.2：发送起手不再挂触觉——触感挪到结果点
        // （run 完成 .success / 失败 .warning，见 driveRun）
        input = ""
        attachments = []
        pendingQuote = nil
        pendingQuoteIsFork = false
        pendingFeedQuote = nil
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
            return
        }
        // 0.31.0：本线程有未落定 run（切后台/杀进程遗
        // 留或对账预算耗尽）时不许叠发新轮——同会话
        // 同时至多一轮在飞（落定的段锚点靠它成立）；
        // 输入原样退回、先触发旧轮对账，落定后再发
        if appState.runLedger.entry(forThreadID: thread.id)
            != nil {
            input = text
            attachments = pending
            pendingQuote = quote
            pendingFeedQuote = feedQuote
            showNotice("上一条还在生成中，正在确认结果，确认完就能继续发送。")
            Task { await resumeRunIfNeeded() }
            return
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
            quote: quote, feedQuote: feedQuote
        )
        modelContext.insert(newEntry)
        // 0.7.0（M3）：主线标题恒「主线」、不被首条消息
        // 派生覆盖——主线线程标题在钦定落位时即为「主线」
        // 本就不进本分支，此守卫是双保险
        if thread.title == "新会话", thread.id != appState.sideChats.mainThreadID {
            thread.title = text.isEmpty ? "图片消息" : String(text.prefix(20))
        }
        thread.updatedAt = Date()
        try? modelContext.save()
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
        // 上下文组装走共用出口 outgoingContext（组装
        // 口径注在该函数；基础止血包起失败重发同走它，
        // 两路不许分叉）
        let context = outgoingContext(
            of: thread, tailEntry: newEntry, text: text, quote: quote,
            feedQuote: feedQuote
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
        feedQuote: FeedPostQuote?
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
                    feedQuote: $0.feedQuote
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
                    feedQuote: feedQuote
                ),
                imageDataURLs: urls
            )
        }
        return context
    }

    /// 一轮的网络半程（send 与失败重发共用）：上传待
    /// 发文件（或沿用已落盘的远端路径）→ 定发送形态
    /// （链接）→ driveRun。基础止血包（P1）改判失败
    /// 语义：上传/链接失败不再删本轮条目、不再把文
    /// 字退回输入框——条目留原地挂失败标记（mark-
    /// TurnFailed），用户点标记以原条目重发；链接窗
    /// 口内被用户停止仍按停止语义静默收尾（条目保
    /// 留、不挂标记，与旧口径一致）
    private func launchTurn(
        thread: ChatThread, userEntry: ChatEntry, text: String,
        filePayloads: [(name: String, data: Data)],
        presetFilePaths: [String],
        seedSnapshot: [SeedEntry], context: [ChatMessage]
    ) {
        streamingText = ""
        // 0.8.0：上一轮的流式工具卡列清空，从本轮累积
        liveToolCards = []
        // 0.36.10：事件序标记同步清零，从本轮重记
        liveOrder = []
        sendTask = Task {
            // 0.36.29（件四）：带文件时先逐个上传——
            // 任一失败整条拦下，不许丢下文件只发文本；
            // 全成才攒下回执路径，尾条拼装时拼 @file
            // 引用。基础止血包（P1）改判失败落点：旧
            // 「删本轮条目＋输入附件退回发送舱」作废，
            // 改 markTurnFailed（条目留原地挂标记、载
            // 荷暂存供重发补传）。重发且条目已有远端路
            // 径时整段跳过（文件已在服务端，路径即凭
            // 证），不重复上传
            var fileServerPaths: [String] = presetFilePaths
            if fileServerPaths.isEmpty, !filePayloads.isEmpty {
                // P7 文案分型：上传段全程挂真态位，等
                // 待呈现说「上传中」、不冒充生成中
                isUploadingFiles = true
                do {
                    fileServerPaths = try await
                        uploadPendingFiles(filePayloads)
                } catch let failure as FileUploadFailure {
                    isUploadingFiles = false
                    markTurnFailed(
                        entry: userEntry, filePayloads: filePayloads
                    )
                    errorMessage = "文件「\(failure.fileName)」没能上传，这条还没发出去："
                        + failure.reason
                        + "处理后点这条消息旁的感叹号重新发送。"
                    Haptics.error()
                    streamingText = nil
                    streamingReasoning = nil
                    reasoningStartedAt = nil
                    sendTask = nil
                    return
                } catch is CancellationError {
                    isUploadingFiles = false
                    streamingText = nil
                    streamingReasoning = nil
                    reasoningStartedAt = nil
                    sendTask = nil
                    return
                } catch {
                    // uploadPendingFiles 只抛 FileUpload-
                    // Failure/取消，此兜底防未知错误形态
                    // 被静默吞（有声口径）
                    isUploadingFiles = false
                    markTurnFailed(
                        entry: userEntry, filePayloads: filePayloads
                    )
                    errorMessage = "文件上传失败，这条还没发出去，请稍后再试。"
                    Haptics.error()
                    streamingText = nil
                    streamingReasoning = nil
                    reasoningStartedAt = nil
                    sendTask = nil
                    return
                }
                isUploadingFiles = false
                if Task.isCancelled {
                    streamingText = nil
                    streamingReasoning = nil
                    reasoningStartedAt = nil
                    sendTask = nil
                    return
                }
                // 上传已成：暂存载荷使命完成，清格防重
                // 发时误补传（此后凭条目远端路径为准）
                failedFilePayloads[userEntry.id] = nil
                // §121 题二 a（发送回填）：上传全成后
                // 立即把回执路径写回本地条目落盘——用
                // 户气泡文件牌的唯一数据源就是 entry.
                // remoteFilePaths，旧链只把路径拼进出
                // 站文本、本地条目恒空，刚发的消息在
                // 本地永远没牌（真机实证：助手牌正常、
                // 自己牌缺失）。落点在此（失败分支全
                // 已 return、走到这里即全成），流式期
                // 间牌就在
                if !fileServerPaths.isEmpty {
                    userEntry.remoteFilePathsData =
                        try? JSONEncoder().encode(fileServerPaths)
                    try? modelContext.save()
                    // §125（大小回填路①）：回执顺序与
                    // filePayloads 同序（uploadPending-
                    // Files 顺序上传），本地字节数按路
                    // 径记入元数据缓存——自发文件卡副行
                    // 的大小即时有数，不等列表回读
                    for (path, payload) in zip(
                        fileServerPaths, filePayloads
                    ) {
                        FileMetadataStore.shared.record(
                            path: path,
                            size: Int64(payload.data.count),
                            modifiedAt: nil
                        )
                    }
                }
            }
            // 0.21.0：出门前先定发送形态（判定与载荷取
            // 形是 Core 纯函数、网络动作在本页）。
            // 0.27.0：prepareSendShape 改为可抛——链接
            // 失败整轮不发（无头回退已删）、错误横幅明
            // 示原因；基础止血包（P1）改判失败落点：
            // 旧「删本轮条目＋输入退回发送舱」作废，改
            // markTurnFailed（条目留原地挂标记、点标记
            // 重发）；链接窗口内被用户停止仍按停止语
            // 义静默收尾（条目保留、不挂标记）
            let shape: (messages: [ChatMessage], sessionID: String?)
            do {
                shape = try await prepareSendShapeWithRetry(
                    thread: thread, fullContext: context,
                    seedEntries: seedSnapshot
                )
            } catch is CancellationError {
                streamingText = nil
                streamingReasoning = nil
                reasoningStartedAt = nil
                sendTask = nil
                return
            } catch {
                if Task.isCancelled {
                    streamingText = nil
                    streamingReasoning = nil
                    reasoningStartedAt = nil
                    sendTask = nil
                    return
                }
                markTurnFailed(entry: userEntry)
                errorMessage = "会话链接失败，这条还没发出去："
                    + ((error as? HermesError)?.userMessage
                        ?? "服务端会话建立失败")
                    + "。链接恢复后，点这条消息旁的感叹号重新发送。"
                // 失败改判 error（0.36.2，表 D 语义归位）
                Haptics.error()
                streamingText = nil
                streamingReasoning = nil
                reasoningStartedAt = nil
                sendTask = nil
                return
            }
            if Task.isCancelled {
                streamingText = nil
                streamingReasoning = nil
                reasoningStartedAt = nil
                sendTask = nil
                return
            }
            // 0.36.5（审计 bug 1）：链接已成、条目确定
            // 留下——递增发送贴底令牌，messageList 侧
            // 执行贴底两步。链接失败的回滚分支（上方
            // catch 删条目）与停止分支都到不了这里
            // §135 D 案打点：落盘→链接一段（链接成功
            // 才走到这里，读数只记成功轮）
            if let started = sendFrameStartedAt {
                ChatDiagTrace.record(
                    "发送打点 落盘→链接 "
                        + "\(Int(Date().timeIntervalSince(started) * 1000))ms"
                )
            }
            sendPinToken += 1
            // 0.31.0：发送通道迁 /v1/runs——会话模式的
            // 载荷只取尾条这点不变（历史在服务端会话
            // 里），变的只是投递与生成形态：提交得
            // run_id、生成脱离连接、断线走对账
            // 0.36.29（件四）：尾条定形——带文件时把
            // @file 引用拼进尾条文本尾（run 的 input
            // 即尾条文本，契约拼装口径；与引用拼装同
            // 层、只属本轮，不进本地落盘条目）
            let tail = FileSendAssembly.appendingFileRefs(
                to: shape.messages.last
                    ?? ChatMessage(role: "user", content: text),
                serverPaths: fileServerPaths
            )
            await driveRun(
                thread: thread,
                tail: tail,
                sessionID: shape.sessionID,
                userEntry: userEntry
            )
        }
    }

    /// 本轮失败的统一落点（基础止血包 P1/P2）：条目
    /// 留原地挂失败标记——不删条目、不回退输入框；
    /// 文件载荷在场时暂存供重发补传；横幅「重新发
    /// 送」动作位的目标 id 同步记账。成功落定清标记
    /// 在 applySettledTurn，重发启动清标记在 resend-
    /// FailedEntry
    private func markTurnFailed(
        entry: ChatEntry,
        filePayloads: [(name: String, data: Data)] = []
    ) {
        entry.sendFailed = true
        try? modelContext.save()
        if !filePayloads.isEmpty {
            failedFilePayloads[entry.id] = filePayloads
        }
        failedResendEntryID = entry.id
    }

    /// run 落定失败的标记落点（P2）：按账本里的用户
    /// 条目 id 回找条目挂标记——条目已不在（线程被
    /// 清）则静默跳过
    private func markRunFailure(
        entry: RunLedgerEntry, in thread: ChatThread
    ) {
        guard let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) else { return }
        markTurnFailed(entry: userEntry)
    }

    /// 失败条目重发（基础止血包 P1/P2，微信点感叹号
    /// 口径）：条目是线程末条时原地重走一轮（它本身
    /// 即尾条）；不是末条时把内容复制成新条目落到末
    /// 尾再发、旧失败条目随即删除——落定整段替换按
    /// 用户条目时刻清其后条目（deleteTurnPartial-
    /// Entries），原地重发中段条目会误伤其后已落定
    /// 的轮次，只能复制。两路都汇进 launchTurn 同一
    /// 链：新 run＋新幂等键由 driveRun 现铸、账本在
    /// 飞守卫防叠发（与 send() 同一道闸），成功落定
    /// 自动清标记、再失败由各失败分支重新挂上
    private func resendFailedEntry(_ entry: ChatEntry) {
        guard entry.sendFailed, !isStreaming,
              let thread = entry.thread else { return }
        // 同 send() 的在飞闸：本线程有未落定 run 时
        // 不许叠发，先触发旧轮对账
        guard appState.runLedger.entry(forThreadID: thread.id)
            == nil else {
            showNotice("上一条还在生成中，正在确认结果，确认完就能继续发送。")
            Task { await resumeRunIfNeeded() }
            return
        }
        errorMessage = nil
        if failedResendEntryID == entry.id {
            failedResendEntryID = nil
        }
        sendFrameStartedAt = Date()
        sendFrameRestickLogged = false
        let target: ChatEntry
        if thread.sortedEntries.last?.id == entry.id {
            target = entry
        } else {
            let copy = ChatEntry(
                role: "user", content: entry.content, thread: thread,
                imageDatas: entry.allImageDatas, quote: entry.quote
            )
            copy.remoteFilePathsData = entry.remoteFilePathsData
            modelContext.insert(copy)
            // 上传未成的载荷随复制转移（键随条目走）
            if let payloads = failedFilePayloads[entry.id] {
                failedFilePayloads[copy.id] = payloads
                failedFilePayloads[entry.id] = nil
            }
            modelContext.delete(entry)
            target = copy
        }
        target.sendFailed = false
        thread.updatedAt = Date()
        try? modelContext.save()
        // 种子快照剔除尾条本体（两路 target 恒为末
        // 条、种子与条目 1:1 同序）：链接导入的历史
        // 只含尾条之前，防尾条在服务端落两份——与
        // send() 落盘前取快照同义
        let seedSnapshot = Array(
            Self.seedEntries(of: thread).dropLast()
        )
        launchTurn(
            thread: thread, userEntry: target,
            text: target.content,
            filePayloads: failedFilePayloads[target.id] ?? [],
            presetFilePaths: target.remoteFilePaths,
            seedSnapshot: seedSnapshot,
            context: outgoingContext(
                of: thread, tailEntry: target,
                text: target.content, quote: target.quote,
                feedQuote: target.feedQuote
            )
        )
    }

    /// 待发条目重发（聊天可靠性包，2026-11-13）：
    /// 用户点按气泡下「未发送 · 点按重发」触发——
    /// 不新建条目，用同一条目再走一遍「上传（仅暂
    /// 存载荷还在且未传成时）→定形→driveRun」；受
    /// 理/转对账后待发标记由 driveRun 脱落，再失
    /// 败则标记保留、横幅如实报，可再试。与 send()
    /// 的互斥口径一致：本线程有未落定 run 时不叠
    /// 轮、先触发旧轮对账
    private func resendPending(_ entry: ChatEntry) {
        guard entry.isPendingSend, !isStreaming,
              let thread = entry.thread ?? currentThread
        else { return }
        if appState.runLedger.entry(forThreadID: thread.id)
            != nil {
            showNotice("上一条还在生成中，正在确认结果，确认完就能继续发送。")
            Task { await resumeRunIfNeeded() }
            return
        }
        errorMessage = nil
        dismissNotice()
        let stashed = pendingResendAttachments[entry.id] ?? []
        let filePayloads = stashed.compactMap(\.filePayload)
        let imageDatas = entry.allImageDatas
        // 种子在本条投递前取、且已排除全部待发条目
        // （含本条，见 seedEntries）——本条只以尾条
        // 身份进服务端，不在种子里先落一份
        let seedSnapshot = Self.seedEntries(of: thread)
        streamingText = ""
        liveToolCards = []
        liveOrder = []
        sendTask = Task {
            var fileServerPaths = entry.remoteFilePaths
            if !filePayloads.isEmpty, fileServerPaths.isEmpty {
                do {
                    fileServerPaths = try await
                        uploadPendingFiles(filePayloads)
                } catch let failure as FileUploadFailure {
                    errorMessage = "文件「\(failure.fileName)」还是没能上传："
                        + failure.reason
                        + "这条消息仍保存在本机，可稍后再试。"
                    Haptics.error()
                    streamingText = nil
                    streamingReasoning = nil
                    reasoningStartedAt = nil
                    sendTask = nil
                    return
                } catch {
                    errorMessage = "文件上传还是失败，这条消息仍保存在本机，可稍后再试。"
                    Haptics.error()
                    streamingText = nil
                    streamingReasoning = nil
                    reasoningStartedAt = nil
                    sendTask = nil
                    return
                }
                if !fileServerPaths.isEmpty {
                    entry.remoteFilePathsData =
                        try? JSONEncoder().encode(fileServerPaths)
                    try? modelContext.save()
                    for (path, payload) in zip(
                        fileServerPaths, filePayloads
                    ) {
                        FileMetadataStore.shared.record(
                            path: path,
                            size: Int64(payload.data.count),
                            modifiedAt: nil
                        )
                    }
                }
            }
            if Task.isCancelled {
                streamingText = nil
                streamingReasoning = nil
                reasoningStartedAt = nil
                sendTask = nil
                return
            }
            // 出站形态与 send() 同口径：引用拼装走
            // MessageQuote.outgoingContent、本地图走
            // 多模态 parts；上下文只喂本条（会话模式
            // 载荷恒取尾条，链接与否都只投这一条）
            var outgoing = ChatMessage(
                role: "user",
                content: MessageQuote.outgoingContent(
                    userText: entry.content, quote: entry.quote
                )
            )
            if !imageDatas.isEmpty {
                let urls = imageDatas.map {
                    "data:image/jpeg;base64,\($0.base64EncodedString())"
                }
                outgoing = ChatMessage(
                    role: "user",
                    text: MessageQuote.outgoingContent(
                        userText: entry.content, quote: entry.quote
                    ),
                    imageDataURLs: urls
                )
            }
            let shape: (messages: [ChatMessage], sessionID: String?)
            do {
                shape = try await prepareSendShapeWithRetry(
                    thread: thread, fullContext: [outgoing],
                    seedEntries: seedSnapshot
                )
            } catch is CancellationError {
                streamingText = nil
                streamingReasoning = nil
                reasoningStartedAt = nil
                sendTask = nil
                return
            } catch {
                if Task.isCancelled {
                    streamingText = nil
                    streamingReasoning = nil
                    reasoningStartedAt = nil
                    sendTask = nil
                    return
                }
                errorMessage = "还是没能连上，消息仍保存在本机："
                    + ((error as? HermesError)?.userMessage
                        ?? "服务端会话建立失败")
                    + "。恢复后可再点按重发。"
                Haptics.error()
                streamingText = nil
                streamingReasoning = nil
                reasoningStartedAt = nil
                sendTask = nil
                return
            }
            if Task.isCancelled {
                streamingText = nil
                streamingReasoning = nil
                reasoningStartedAt = nil
                sendTask = nil
                return
            }
            pendingResendAttachments[entry.id] = nil
            sendPinToken += 1
            let tail = FileSendAssembly.appendingFileRefs(
                to: shape.messages.last ?? outgoing,
                serverPaths: fileServerPaths
            )
            await driveRun(
                thread: thread, tail: tail,
                sessionID: shape.sessionID, userEntry: entry
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
        var paths: [String] = []
        for payload in payloads {
            let receipt: ManagedFileUploadReceipt
            do {
                receipt = try await appState.performAdmin {
                    client, cfg in
                    try await client.uploadAttachment(
                        config: cfg,
                        path: FileSendAssembly.uploadPath(
                            fileName: payload.name
                        ),
                        dataURL: FileSendAssembly.dataURL(
                            fileName: payload.name,
                            data: payload.data
                        )
                    )
                }
            } catch let error as HermesError {
                throw FileUploadFailure(
                    fileName: payload.name,
                    reason: error.userMessage
                )
            }
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
        let store = appState.sideChats
        let isMain = thread.id == store.mainThreadID
        let plan = isMain
            ? SideChatLink.sendPlan(
                serverSessionID: store.mainServerSessionID,
                serverSeeded: store.mainServerSeeded
            )
            : SideChatLink.sendPlan(
                serverSessionID: thread.serverSessionID,
                serverSeeded: thread.serverSeeded
            )
        switch plan {
        case .session(let sessionID):
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
                    // 目标 id：已存自有 id 沿用（补种子
                    // 路径），其余（无绑定/绑合并桶/绑
                    // 他方会话待解绑）一律新铸——合并桶
                    // 绑定在此被自有 id 覆盖、桶本体零
                    // 动作
                    let desiredID = thread.serverSessionID
                        .flatMap {
                            SideChatLink.isOwnSessionID($0)
                                ? $0 : nil
                        } ?? SideChatLink.newSessionID()
                    linkedID = try await performLink(
                        desiredID: desiredID, title: nil,
                        model: appState.chatModel(
                            serverSessionID: desiredID,
                            threadID: thread.id
                        ),
                        seedEntries: seedEntries
                    )
                    thread.serverSessionID = linkedID
                    thread.linkedModel = appState.chatModel(
                        serverSessionID: linkedID, threadID: thread.id
                    )
                    thread.serverSeeded = true
                    thread.linkFailureCount = 0
                    thread.linkLastError = nil
                    try? modelContext.save()
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
            streamingReasoning = nil
            reasoningStartedAt = nil
            errorMessage = HermesError.sessionExpired.userMessage
            // 基础止血包（P1）：连接态缺失同样是本轮
            // 失败——条目留痕挂标记，恢复连接后点标
            // 记重发（演示态不挂，种子条目不是用户真
            // 发送）
            if !demoMode {
                markTurnFailed(entry: userEntry)
            }
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
            sendTask = nil
            return
        }
        isDrivingRun = true
        defer { isDrivingRun = false }
        runMachine = RunTurnStateMachine()
        activeRunThreadID = thread.id
        lastEventSeq = -1
        livePartialEntryIDs = []
        terminalOutputHint = nil
        terminalStatusHint = nil
        contentPublishGate.reset()
        reasoningPublishGate.reset()
        streamingReasoning = nil
        reasoningStartedAt = nil
        // 输入组装：尾条纯文本走字符串形态、多模态走
        // 单元素消息形态（探针实测两形态均成立）
        let input: RunInput = tail.parts == nil
            ? .text(tail.content) : .message(tail)
        let choice = appState.sessionModelChoice(
            serverSessionID: sessionID, threadID: thread.id
        )
        let provider = choice.providerField
        var ledgerEntry = RunLedgerEntry(
            threadID: thread.id.uuidString,
            sessionID: sessionID ?? "",
            runID: nil,
            idempotencyKey: UUID().uuidString,
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
                if error.isTransient, attempts < 2 {
                    attempts += 1
                    try? await Task.sleep(
                        for: .milliseconds(1200)
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
                markTurnFailed(entry: userEntry)
            }
            errorMessage = submitError.userMessage
            finishRunPresentation(failed: true)
            return
        }
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

    /// events 订阅呈现：增量过发布闸、工具卡实时拼
    /// 装、思考预览（若服务端发出）同路；见到终态事
    /// 件记账返回，流自结束（断线/缓冲过期）按「未见
    /// 终态」进结果未知——不在此报错、不做失败分型
    private func followRunEvents(
        thread: ChatThread, entry: RunLedgerEntry,
        demoMode: Bool
    ) async {
        guard let runID = entry.runID,
              let config = appState.config,
              let apiKey = appState.apiKey else { return }
        // 发布巡查 ticker（旧 runStream 同制：40ms 一
        // 查，窗口到期把攒着的增量推给视图；订阅期外
        // 无增量可推，ticker 随订阅生灭）
        let publishTicker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                if Task.isCancelled { break }
                let now = ProcessInfo.processInfo.systemUptime
                if let snapshot = contentPublishGate
                    .collectDue(at: now) {
                    streamingText = snapshot
                }
                if let snapshot = reasoningPublishGate
                    .collectDue(at: now) {
                    streamingReasoning = snapshot
                }
            }
        }
        defer { publishTicker.cancel() }
        let stream = appState.client.runEvents(
            config: config, apiKey: apiKey,
            runID: runID, lastSeq: lastEventSeq
        )
        for await envelope in stream {
            if let seq = envelope.seq { lastEventSeq = seq }
            let now = ProcessInfo.processInfo.systemUptime
            switch envelope.event {
            case .contentDelta(let delta),
                 .interim(let delta):
                if !delta.isEmpty {
                    // 0.36.10：正文首达记位（事件序编排）
                    noteLiveOrder(.text)
                    if let snapshot = contentPublishGate
                        .offer(delta, at: now) {
                        streamingText = snapshot
                    }
                }
            case .reasoningPreview(let text):
                if reasoningStartedAt == nil {
                    reasoningStartedAt = Date()
                }
                // 0.36.10：思考首达记位（事件序编排）
                noteLiveOrder(.reasoning)
                if let snapshot = reasoningPublishGate
                    .offer(text, at: now) {
                    streamingReasoning = snapshot
                }
            case .toolStarted(let id, let name, let preview):
                appendLiveToolCard(
                    id: id, name: name, preview: preview
                )
            case .toolCompleted(
                let id, let name, let preview, let failed
            ):
                completeLiveToolCard(
                    id: id, name: name, preview: preview,
                    failed: failed
                )
            case .terminal(let kind, let output):
                terminalOutputHint = output
                runMachine.apply(.statusTerminal(kind))
                return
            case .other:
                continue
            }
        }
        // 流结束而未见终态：结果未知（非错误）。半截
        // 先落盘，进程被回收也不凭空消失
        if !runMachine.isSettled,
           case .generating(_) = runMachine.phase {
            runMachine.apply(.streamLost)
            persistRunPartials(thread: thread)
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
    private func reconcileRun(
        thread: ChatThread, entry: inout RunLedgerEntry,
        demoMode: Bool
    ) async {
        guard let config = appState.config,
              let apiKey = appState.apiKey else { return }
        if runMachine.phase == .unknown {
            runMachine.apply(.foregrounded)
        }
        let deadline = Date().addingTimeInterval(600)
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
                    // 从恢复，清账收尾
                    if !demoMode {
                        appState.runLedger.remove(
                            threadID: thread.id
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
                } catch {
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
            // 状态轮询
            let status = try? await appState.client.runStatus(
                config: config, apiKey: apiKey, runID: runID
            )
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
                // 状态记录查不到（过期/未持久化）：转
                // transcript 单独定性
                runMachine.apply(.statusMissing)
                if await settleRunFromTranscript(
                    thread: thread, entry: entry
                ) {
                    return
                }
                try? await Task.sleep(for: .seconds(3))
            }
            if Date() > deadline { break }
        }
        if !runMachine.isSettled {
            runMachine.apply(.settleExhausted)
            // 体面出口：生成仍在服务端进行（或结果待
            // 查），账本保留、下次进本线程自动续对账
            persistRunPartials(thread: thread)
            showNotice(
                "生成仍在服务器进行中，稍后回到本对话会自动补齐结果。",
                tier: .extended
            )
            finishRunPresentation(failed: false)
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
            feedQuote: userEntry.feedQuote
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
        let settled = RunTranscriptSettle.settle(
            messages: messages
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
            if !appState.isDemo {
                appState.runLedger.remove(threadID: thread.id)
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
                markRunFailure(entry: entry, in: thread)
            }
            errorMessage = failure.userMessage
            runMachine.apply(.transcriptSettled)
            finishRunPresentation(failed: true)
            return
        }
        let output = terminalStatusHint?.output
            ?? terminalOutputHint
        let fallbackText = contentPublishGate.fullText
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

    /// 落定入账：整段替换本轮半截条目（工具卡＋带思
    /// 考回填的助手正文），触感与标题回流沿旧口径，
    /// 账本清除
    private func applySettledTurn(
        thread: ChatThread, entry: RunLedgerEntry,
        settled: SettledRunTurn
    ) {
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
                appState.runLedger.remove(threadID: thread.id)
                markRunFailure(entry: entry, in: thread)
            }
            errorMessage = failure.userMessage
            finishRunPresentation(failed: true)
            return
        }
        // 基础止血包（P1/P2）：成功落定清本轮用户条目
        // 的失败标记——重发成功后旧标记不许残留（首
        // 发成功轮条目恒无标记，本支为空转）
        if !appState.isDemo,
           let userEntry = thread.entries.first(
               where: { $0.id.uuidString == entry.userEntryID }
           ), userEntry.sendFailed {
            userEntry.sendFailed = false
            try? modelContext.save()
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
        if let text = settled.finalText, !text.isEmpty {
            let assistantEntry = ChatEntry(
                role: "assistant", content: text,
                thread: thread, reasoning: settled.reasoning,
                reasoningSeconds: nil
            )
            assistantEntry.createdAt = endDate
                .addingTimeInterval(
                    Double(settled.toolCards.count) * 0.001
                        + 0.001
                )
            modelContext.insert(assistantEntry)
            thread.updatedAt = Date()
        }
        if !settled.toolCards.isEmpty
            || settled.finalText?.isEmpty == false {
            try? modelContext.save()
        }
        if !appState.isDemo {
            appState.runLedger.remove(threadID: thread.id)
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
            }
            // 标题回流触发（0.21.0 沿用）：已链接旁聊
            // 一轮完整落地后顶刷新令牌等服务端 AI 标题
            if thread.serverSessionID != nil,
               thread.id != appState.sideChats.mainThreadID {
                appState.noteLinkedSideChatTurnFinished()
            }
        } else if phase == .cancelled {
            showNotice("已停止生成。")
        }
        finishRunPresentation(failed: false)
    }

    /// 整段替换的删除面：已落盘的半截名单＋用户条目
    /// 之后落盘的全部条目（发送互斥保证其必属本轮）
    private func deleteTurnPartialEntries(
        thread: ChatThread, entry: RunLedgerEntry
    ) {
        deleteLivePartialEntries(in: thread)
        guard let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) else { return }
        for candidate in thread.entries
        where candidate.id != userEntry.id
            && candidate.createdAt > userEntry.createdAt {
            // §123（H1）：回响条目不属本轮——它可能恰在
            // 一轮进行中由目标详情侧落盘（跨面并发），
            // 「用户条目之后必属本轮」的发送互斥前提对
            // 它不成立，整段替换不许删它
            // §165：审批锚定条目同理（物化由 store 刷新
            // 触发、可在一轮进行中落盘），谓词同上统一
            guard !candidate.isSystemAnchored else { continue }
            // 聊天可靠性包：待发条目同理不删——它从未
            // 被服务端受理、不属任何一轮的半截；极端
            // 时序下（前一轮对账未落定时其 createdAt
            // 落在本轮用户条目之后）整段替换扫到它也
            // 必须跳过，用户消息不许陪葬
            guard !candidate.isPendingSend else { continue }
            modelContext.delete(candidate)
        }
        try? modelContext.save()
    }

    /// 结果未知时的半截落盘（进程被回收也不凭空消
    /// 失）：工具卡与已累积正文按条目落盘、记 id 供
    /// 落定时整段替换（与旧 interrupted 落盘同制）
    private func persistRunPartials(thread: ChatThread) {
        let flushNow = ProcessInfo.processInfo.systemUptime
        if let snapshot = contentPublishGate.flush(at: flushNow) {
            streamingText = snapshot
        }
        if let snapshot = reasoningPublishGate
            .flush(at: flushNow) {
            streamingReasoning = snapshot
        }
        deleteLivePartialEntries(in: thread)
        let accumulated = contentPublishGate.fullText
        let reasoningText = reasoningPublishGate.fullText
        let endDate = Date()
        let cards = liveToolCards
        var ids: [UUID] = []
        for (index, card) in cards.enumerated() {
            let cardEntry = ChatEntry(
                role: "tool", content: "", thread: thread,
                toolCard: card
            )
            cardEntry.createdAt = endDate.addingTimeInterval(
                Double(index) * 0.001
            )
            modelContext.insert(cardEntry)
            ids.append(cardEntry.id)
        }
        if !accumulated.isEmpty {
            let assistantEntry = ChatEntry(
                role: "assistant", content: accumulated,
                thread: thread,
                reasoning: reasoningText.isEmpty
                    ? nil : reasoningText,
                reasoningSeconds: nil
            )
            assistantEntry.createdAt = endDate
                .addingTimeInterval(
                    Double(cards.count) * 0.001 + 0.001
                )
            modelContext.insert(assistantEntry)
            thread.updatedAt = Date()
            ids.append(assistantEntry.id)
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
        streamingText = nil
        streamingReasoning = nil
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
    }

    /// 停止（0.31.0）：runs 通道真取消——发 stop 后
    /// 由订阅/对账链等终态落定、部分产物按 transcr-
    /// ipt 呈现；提交窗口内则取消本地提交任务（账本
    /// 已留停止意图，下次对账执行真停止）
    private func requestRunStop() {
        guard isStreaming else { return }
        if runMachine.phase == .submitting {
            sendTask?.cancel()
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
        runMachine = RunTurnStateMachine()
        if entry.runID != nil {
            runMachine.apply(.submitAccepted)
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
        contentPublishGate.reset()
        reasoningPublishGate.reset()
        streamingReasoning = nil
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
            let partials = thread.entries.filter {
                $0.id != userEntry.id
                    && $0.createdAt > userEntry.createdAt
                    && !$0.isSystemAnchored
            }
            livePartialEntryIDs = partials.map(\.id)
            liveToolCards = partials
                .filter { $0.role == "tool" }
                .compactMap(\.toolCard)
            if let partialText = partials
                .filter({ $0.role == "assistant" })
                .max(by: { $0.createdAt < $1.createdAt })?
                .content, !partialText.isEmpty {
                _ = contentPublishGate.offer(
                    partialText,
                    at: ProcessInfo.processInfo.systemUptime
                )
                streamingText = partialText
            } else {
                streamingText = ""
            }
        } else {
            streamingText = ""
        }
        // 0.36.10：恢复回填的事件序＝卡序在前、正文殿
        // 后（半截落盘的原始交错序已不可考，落定以
        // transcript 重建为准）
        liveOrder = liveToolCards.map { .tool($0.id) } + [.text]
        isDrivingRun = true
        var mutableEntry = entry
        await reconcileRun(
            thread: thread, entry: &mutableEntry,
            demoMode: false
        )
        isDrivingRun = false
    }

}

/// 消息长按菜单（0.4.1）：系统 contextMenu 四项——回复
/// ／复制／选择／分享，全系统件、禁自绘菜单。复制走
/// Pasteboard 收敛口径（与 CopyButton 同源一处）；分享
/// 走 ShareLink 系统分享单；选择打开纯文本 sheet。
/// isEnabled=false（纯图片消息）时不挂菜单，见
/// messageMenu(for:) 的口径注
private struct MessageMenuModifier: ViewModifier {
    let isEnabled: Bool
    let plainText: String
    let onReply: () -> Void
    /// 0.7.0（M4）：分流动作「在旁聊里接着问」
    let onFork: () -> Void
    let onSelect: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                Button(action: onReply) {
                    Label("回复", systemImage: MessageActionSymbols.reply)
                }
                Button(action: onFork) {
                    Label("在旁聊里接着问", systemImage: MessageActionSymbols.fork)
                }
                Button {
                    Pasteboard.copy(plainText)
                } label: {
                    Label("复制", systemImage: MessageActionSymbols.copy)
                }
                Button(action: onSelect) {
                    Label("选择", systemImage: MessageActionSymbols.select)
                }
                ShareLink(item: plainText) {
                    Label("分享", systemImage: MessageActionSymbols.share)
                }
            }
        } else {
            content
        }
    }
}

/// 右滑引用（0.36.19 立；0.36.26 §95 按生产同
/// 构整件重做）：气泡向右滑，横向拖动显出回复箭
/// 头，拖动途中过线即触发引用——与长按菜单「回
/// 复」同一动作（beginReply），两路并存不互斥
/// （长按是静止按压、右滑是横向拖动，形态不重
/// 叠）。
///
/// 构造（Stream Chat SwiftUI 现行生产代码逐行
/// 同构，调研报告 production-patterns-research-
/// 20261111 §1.2/§1.5）：行内容挂 `.simultane-
/// ousGesture(DragGesture(minimumDistance:
/// 30))`，onChanged 只消费横向分量写 offset
/// （判定全走 Core SwipeReplyMotion，阈值以
/// Stream 参数为单源：起滑 30/途中触发 60/显
/// 示封顶 90）；不设方向比值门、不做任何识别
/// 器编排——纵滑时横向分量≈0、offset 恒 0、气
/// 泡不动，纵滚完整归列表。0.36.20–0.36.23 的
/// UIKit 探针桥四轮真机全灭（P-15），整桥与诊
/// 断件本轮退役；第 1 轮同族构造的失败差异
/// （起滑 6/方向门/松手触发/封顶 76/无坐标空
/// 间与排除区）逐项按 Stream 销账，见 DESIGN
/// §95。
/// 起始点排除区（Stream 同款）：行内自有横向
/// 交互的子区（代码块/表格的横向滚动区）经
/// PreferenceKey 发布其在命名坐标空间内的
/// 帧，拖动起始点落在其中则整段忽略——那片
/// 区域的横滑归它自己。
/// 箭头在内容左缘下层：随显形进度淡入/缩放，
/// 越线转武装态，且触发与触觉在越线同一刻发
/// 生（途中触发，不等松手）；松手只做回位
/// §199：internal（原 private）——选字计数证死/回归
/// 测试须装配生产原物验证结构身份，不许在测试侧复
/// 制一份同形修饰符充数
struct SwipeReplyModifier: ViewModifier {
    let isEnabled: Bool
    let onReply: () -> Void

    @State private var dragOffset: CGFloat = 0
    /// 整段拖动只触发一次（越线当场置位、松手复位）
    @State private var hasTriggered = false
    /// 起始点排除帧（行内横向滚动子区发布，本层收集）
    @State private var excludedFrames: [CGRect] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            ZStack(alignment: .leading) {
                replyArrow
                content
                    // 命中域＝整条消息容器（Stream
                    // 行同款 contentShape）：行内空
                    // 区起手也能拖
                    .contentShape(Rectangle())
                    .coordinateSpace(name: "swipeToReply")
                    .offset(
                        x: SwipeReplyMotion.displayOffset(
                            for: dragOffset
                        )
                    )
                    .simultaneousGesture(swipeGesture)
                    .onPreferenceChange(
                        SwipeReplyExcludedFrameKey.self
                    ) { frames in
                        excludedFrames = frames
                    }
            }
        } else {
            content
        }
    }

    /// 右滑手势本体：只消费横向分量写 offset（判
    /// 定走 Core 单源）；起始点落在排除区整段忽
    /// 略；越线当场触发＋触觉（整段只一次）；松
    /// 手动画回位、不再判触发
    private var swipeGesture: some Gesture {
        DragGesture(
            minimumDistance: SwipeReplyMotion.minimumDistance,
            coordinateSpace: .named("swipeToReply")
        )
        .onChanged { value in
            if SwipeReplyMotion.isExcluded(
                startLocation: value.startLocation,
                frames: excludedFrames
            ) {
                return
            }
            let newOffset = SwipeReplyMotion.dragOffset(
                translationWidth: value.translation.width,
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
        .onEnded { _ in
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
    }

    /// 左缘回复箭头：显形进度驱动透明度与缩放，过
    /// 线武装态换主色盘（Palette.primary＋onPri-
    /// mary 箭头）——武装与触发同刻（途中触发口径）
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
                armed ? Palette.primary : Palette.fieldFill,
                in: Circle()
            )
            .opacity(progress)
            .scaleEffect(0.6 + 0.4 * progress)
            .padding(.leading, 4)
            .accessibilityHidden(true)
    }
}

/// 右滑引用排除帧（Stream SwipeToReplyExcluded-
/// FrameKey 同款）：行内子视图把自己在「swipeTo-
/// Reply」命名坐标空间里的帧发布上来，行修饰符
/// 收集后按拖动起始点判定整段忽略
struct SwipeReplyExcludedFrameKey: PreferenceKey {
    nonisolated static let defaultValue: [CGRect] = []

    static func reduce(
        value: inout [CGRect], nextValue: () -> [CGRect]
    ) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// 标记右滑引用排除区：本视图区域内的横滑归
    /// 它自己的横向交互（代码块/表格横滚），不触
    /// 发本行右滑引用（Stream 音频进度条同款落法：
    /// 背景 GeometryReader 在命名坐标空间发布帧）
    func swipeReplyExcluded() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: SwipeReplyExcludedFrameKey.self,
                        value: [
                            proxy.frame(
                                in: .named("swipeToReply")
                            )
                        ]
                    )
            }
        }
    }
}

/// 「选择」sheet 载荷（0.4.1）
private struct SelectionPayload: Identifiable {
    let id = UUID()
    let text: String
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

/// 三点指示：未出字时的等待信号（安静的弱色圆点错峰，
/// Reduce Motion 时静止）。0.2.5 起随助手消息一同入泡。
private struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: OneDayMetrics.iconTextGap) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Palette.inkMuted)
                        .frame(width: 6, height: 6)
                        .opacity(opacity(at: t, index: index))
                }
            }
        }
        .accessibilityLabel("正在生成")
    }

    private func opacity(at t: TimeInterval, index: Int) -> Double {
        if reduceMotion { return 0.6 }
        let wave = sin(t * 3.2 - Double(index) * 0.7)
        return 0.3 + 0.7 * max(0, wave) * max(0, wave)
    }
}

/// 流式光标已移至 StreamingText.swift（与流式渐显组件
/// 同文件，文末词元同流排布）。
