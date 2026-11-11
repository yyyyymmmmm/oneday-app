import OneDayDesign
import OneDayCore
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
/// 是浮空胶囊，流式光标是本页的签名细节。助手消息形态两度
/// 易稿：v2 定为裸排（学 ChatGPT/Claude），0.2.5 按用户真机
/// 对照 Muse 推翻——改浅灰软填充泡（见 assistantBubble 与
/// DESIGN-V4 §9 追记），裸排口径自此作废。
/// 0.1.3 导航（§7）：会话历史改左侧抽屉（顶栏左键＋左缘手势
/// 唤出），顶栏中 = 会话名＋模型名副题，右 = 新建会话。
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

    @Environment(AppState.self) private var appState
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
    /// 本轮是否经历过断线（落定时给「已重新连接」
    /// 中性提示）
    @State private var runWasDetached = false
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
    /// 0.2.1：非错误提示（如文件附件未发送说明），可关闭
    @State private var notice: String?
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
    /// 最后一条条目是否在可见集内（0.36.5，审计
    /// bug 2）：onScrollTargetVisibilityChange 回写
    /// 的事实信号，只参与回底钮显隐（Core Bottom-
    /// FollowPolicy），不改跟随门控——距底距离取自
    /// LazyVStack 估算总高、长线程可驻留迟滞带，事
    /// 实信号是它的纠偏源
    @State private var lastEntryVisible = false
    /// 最近一次可见集（0.36.13，诊断 chat-bottom-
    /// geometry §2.3 堵洞 3）：旧实现只在可见集变化
    /// 时顺带算 lastEntryVisible，末条落盘后可见集
    /// 不再变则持旧值、无复核时机。本状态存下最近
    /// 可见集，条目数变化时由 refreshLastEntryVisible
    /// 用存量集主动重算
    @State private var lastVisibleEntryIDs: Set<UUID> = []
    /// 最近一次实测距底（0.36.13，修法 1 落定复贴）：
    /// 与 isNearBottom 同出 onScrollGeometryChange
    /// 一路——迟滞判定消费它之外，原始读数另存一份
    /// 喂贴底后的复核（仍 >24pt 才补贴，Core
    /// BottomSettle 钉死）
    @State private var lastBottomDistance: CGFloat = 0
    /// 流式跟随滚动节流闸（0.4.2，§27）：OneDayCore
    /// 纯逻辑记账，每 ≥40 字放行一次无动画贴底；流结
    /// 束与切换线程时归零（见 messageList 的 onChange）
    @State private var streamFollowGate = StreamFollowGate()
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
            isNearBottom: isNearBottom,
            lastEntryVisible: lastEntryVisible
        )
    }

    /// 回底钮显隐（单一出处：bottomBar 钮行的存在与
    /// 未读计数的「在底」事实共用同一派生，不许两处
    /// 各算一遍分叉）——无现线程恒不显；政策本体在
    /// Core BottomFollowPolicy
    private var showsBackToBottomButton: Bool {
        currentThread != nil
            && BottomFollowPolicy.showsScrollToBottomButton(
                isNearBottom: isNearBottom,
                lastEntryVisible: lastEntryVisible
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
    // 0.36.23 起选图多选（用户 03:02 点题）：绑数
    // 组、一次可选多张；旧单 PhotosPickerItem 绑定
    // 天然单选，数据侧 attachments 本就支持多个
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
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
    /// 0.6.0：通知 sheet（顶栏铃铛点开，总览桥驱动）
    @State private var showNotifications = false
    /// 0.4.0（§3.4）：服务端会话导入进行中的 id（防重复
    /// 触发并发导入同一条会话）
    @State private var importingSessionID: String?
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
    /// 0.7.0（M1 轻保活）：列表首个可见条目 id（滚动锚
    /// 记录用，由 onScrollTargetVisibilityChange 回写）
    @State private var topVisibleEntryID: UUID?
    /// 0.4.1：长按「选择」的纯文本 sheet 载荷
    @State private var selectionPayload: SelectionPayload?
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

    /// 顶栏/抽屉展示的模型名（0.3.0 接线，§15）：展示本地
    /// 聊天选择（ChatModels 写死三项的展示名）——顶栏选的
    /// 就是逐请求发出的那个模型，名实一致；服务端默认
    /// （defaultModel）是设置页管理面口径，不再冒充聊天
    /// 模型展示
    private var displayModelName: String {
        ChatModels.displayName(for: appState.chatModel)
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
    private var chatSurface: some View {
        ScrollViewReader { proxy in
            messageList(proxy)
                // 回底钮已不在此浮层（§124 三代落位）：
                // 0.41.0 挂发送区容器 overlay＋负偏移→
                // 命中被宿主 frame 剪枝（点不动）；
                // 0.46.1 迁此 overlay＋PreferenceKey 发
                // 布 frame 算落位→发布链真机未交付（整
                // 钮消失，§121）；0.47.1 改读宿主自身
                // safeAreaInsets.bottom 推算→键盘态同
                // 一截键盘高被 frame 与 inset 两套参照
                // 扣两遍、钮高出一截键盘（§124 诊断）。
                // 三轮共同根因＝落位一直在不属于输入
                // 舱的坐标系里推算；三代正修：钮搬进
                // 发送区布局流本体（bottomBar 内输入
                // 舱上方一行），落位由构造保证、零推
                // 算，见 bottomBar 与 DESIGN §124
        }
        // 0.7.1（chrome 裁决档 §3.2，背景同源主治）：背
        // 景层穿过底部安全区直达屏底——0.6.1 截图底部
        // 白带的病根是交界处三个不同来源的「白」同框
        // （画布 252／发送舱玻璃采样／底栏背后的系统
        // 白 255，§1.2 量测）；画布全出血贯通到屏底
        // 后，发送舱玻璃与底栏玻璃采样同一 canvas，
        // 交界不再有亮度台阶。顶向由壳层 ZStack 兜底
        // 画布覆盖（DrawerShell），本层只管底向
        .background {
            Palette.chatSurface
                .ignoresSafeArea(edges: .bottom)
        }
        // 0.4.3（§28）：顶栏 headerBar 已收编——不再走
        // 本容器的 .overlay 悬浮（未注册的覆盖层不在系
        // 统边缘效果体系内，WWDC25-323／Adopting
        // Liquid Glass），改挂消息列表 ScrollView 的
        // .safeAreaBar(edge: .top) 注册为系统认可的自
        // 定义 bar（见 messageList）；overlay 层随之撤
        // 销。0.4.0 删 topFade 的前置至此才真正补完
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
        // 0.31.0 恢复链（取代 0.20.0）：生成与连接分
        // 家后切后台什么都不用记——events 流断了就是
        // 结果未知，run 在服务端照常跑完；要做的只有
        // 回前台/进线程时消费持久账本续对账（resume-
        // RunIfNeeded，无账本即空转返回）
        .onChange(of: scenePhase) { _, phase in
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
            // 0.32.1（F05 止血）：原选模型已停用、选择
            // 被落回默认时的一次性如实提示——消费后落
            // 回值落盘、不再重现；已有提示在显时不抢占
            if let modelNotice = appState.modelFallbackNotice {
                if notice == nil {
                    notice = modelNotice
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
        .sheet(isPresented: $showNotifications, onDismiss: {
            if appState.hubDestinationRequest != nil {
                appState.hubOpenRequested = true
            }
        }) {
            if let overviewStore {
                NotificationsView(store: overviewStore)
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
        .fullScreenCover(isPresented: $showHub) {
            AgentHubView(mode: .activity, onApprovalChanged: {
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

    /// 顶栏（0.3.8 第 30/31 条布局，0.4.0 A 案改；0.4.3
    /// 起注册为消息列表的 .safeAreaBar(edge: .top)、脱
    /// 离悬浮覆盖，§28）：
    /// 身份胶囊一颗装头像＋Hermes＋状态＋模型（§3.3，
    /// 小模型胶囊撤除），会话名退到胶囊下方次行居中呈
    /// 现；左右圆钮 0.23.0 起走系统玻璃（审计 T2，此前
    /// 为白浮纸、与胶囊玻璃并置两材质）。
    /// 左钮字形改汉堡线（第 31 条：与抽屉的隐喻对齐，
    /// 「分栏」图标 sidebar.left 退场）。顶栏总高约
    /// 40＋次行 18，比 0.3.7 的两行胶囊更紧凑（旧胶囊
    /// 167pt 宽纯文字、无头像无 Hermes 名——第 30 条点名）
    private var headerBar: some View {
        VStack(spacing: OneDayMetrics.rowInnerGap) {
            HStack(alignment: .center, spacing: OneDayMetrics.spacingS) {
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

                Spacer()

                // 0.6.0 顶栏三件套之中（蓝图 §4 一期＋追加
                // 硬规格 2）：胶囊仍一颗装头像＋名＋状态＋
                // 模型，但拆两个点按域——身份域（头像/名/
                // 总览桥状态行）点按开枢纽 sheet（0.17.0
                // 改道，0.6.0–0.16.0 是跳活动格）；模型域（分隔
                // 线＋短名＋chevron）是原生 Menu，点开换三
                // 模型（selectChatModel＋会话锁机制原样，
                // 不许埋掉或降级）。头像换三狗搭档款定版图
                identityCapsule
                    // 0.4.1：胶囊在顶栏 HStack 里优先保宽
                    .layoutPriority(1)

                Spacer()

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

    /// 身份胶囊（0.6.0；0.6.1 布局根修）：一颗胶囊，左
    /// 域＝三狗头像＋身份名＋状态点/状态词（0.17.0 起点
    /// 按开枢纽 sheet——活动格撤销前的落点是切活动格），
    /// 右域＝模型 Menu（分隔线＋短名＋chevron）。点按分
    /// 工与一颗装口径沿 0.6.0 不变。
    /// 0.17.0（真机五修②，用户点名「漏字透明、要朦胧
    /// 感玻璃感」）：本体材质由白浮纸（odFloatPaper：
    /// 实填充＋发丝边、无 backdrop 采样）换系统玻璃
    /// .glassEffect(.regular)——调研报告 §6.1/6.6 定案：
    /// 浮件本体必须自带 backdrop 模糊与明度调整（带由
    /// 列表的 scroll edge effect 负责、件由 glass 负责，
    /// 缺一不可）；.clear 档是为「让内容透出」设计的、
    /// 聊天页禁用，.regular 是系统 bar/浮件的默认档。
    /// 0.6.0 真机缺陷根源（用户点名「Hermes ● …」）：
    /// 胶囊内只有状态 Text 一个可压缩元素，状态长句
    /// 必被压成省略号——名字/模型短名都 fixedSize、独
    /// 它扛全部收缩。本版双管齐下：状态词语义先改短
    /// （OverviewStatusLine 可证事实短词，Core）；布局
    /// 改 ViewThatFits 两档——全量档（头像＋名＋状态＋
    /// 模型）宽度不够时整档换紧凑档（只去名字），每
    /// 档内全部文字 fixedSize 不许截断，任何宽度下都
    /// 不出现裸「…」
    private var identityCapsule: some View {
        ViewThatFits(in: .horizontal) {
            capsuleRow(showName: true)
            capsuleRow(showName: false)
        }
    }

    private func capsuleRow(showName: Bool) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Button {
                showHub = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    // 0.36.22：头像读本地档案（AppState
                    // 单一出口），改名换头像此处同步
                    appState.agentAvatarImage
                        .resizable()
                        .scaledToFill()
                        // 0.26.0：边长走形象档（小 24/
                        // 中 28/大 34；中档＝旧值）——
                        // 名字 fixedSize＋最高优先、胶囊
                        // hug 宽随内容，±6 不挤断名字
                        .frame(
                            width: avatarTier.capsulePointSize,
                            height: avatarTier.capsulePointSize
                        )
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    if showName {
                        // 0.36.22：显示名收敛档案出口
                        // （档案覆盖→soul 名→Hermes）
                        Text(appState.agentDisplayName)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    HStack(spacing: OneDayMetrics.iconTextGap) {
                        StatusDot(color: overviewStatusColor)
                        Text(overviewStatusWord)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("\(appState.agentDisplayName)，\(overviewStatusWord)，打开枢纽")

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 0.5, height: 18)

            modelMenu
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, 7)
        // 0.17.0：白浮纸退役、本体换 .glassEffect
        // (.regular)（定案见 identityCapsule 注）
        .glassEffect(.regular, in: Capsule())
    }

    /// 模型域（硬规格 2）：原生 Menu 点开三模型，当前项
    /// 带勾；选择走 AppState.selectChatModel（本地持久化
    /// ＋逐请求 provider=custom，会话锁机制不变）。Menu
    /// 是系统件：呈现、勾选、关闭全走系统行为。
    /// 0.36.13（用户 22:11 真机双勾，诊断 model-menu-
    /// checkmark-diagnosis）：菜单改系统 Picker 承载
    /// （同外观页虚拟形象大小的既有形态）——0.36.4 的
    /// 等宽对号槽＋.opacity 藏勾在 Menu→UIKit 转换时
    /// 透明度被剥掉、每行对勾图标原样提取，双勾同显；
    /// 状态与生效链本无恙（判定单源 chatModel、点谁真
    /// 走谁），坏的只是自绘勾的渲染通道。改 Picker 后
    /// 勾由系统绘制、单选互斥由 UIKit 保证（苹果反馈
    /// FB16679936：菜单带勾正道只有 Toggle/Picker；
    /// 外部核查 community-solutions-check 第 1 题一
    /// 致）。「哪行带勾」的语义口径收进 Core 的
    /// ModelMenuSelection.checkedID 钉测：喂 Picker
    /// 的 selection 先经它过——清单内才有勾、未知 id
    /// 零勾；渲染通道本身单测钉不住，验收靠真机展开
    /// 菜单看一勾（DESIGN-V4 §78）。ModelMenuSpec
    /// 对号槽常数随旧形态退役。
    private var modelMenu: some View {
        Menu {
            Picker("模型", selection: chatModelPickerBinding) {
                ForEach(ChatModels.items, id: \.id) { item in
                    Text(item.displayName).tag(item.id)
                }
            }
        } label: {
            HStack(spacing: OneDayMetrics.stackGap) {
                Text(ChatModels.shortDisplayName(for: appState.chatModel))
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    // 0.23.0（审计 G6）：9pt 字形升 caption2
                    // 角色（默认 11 视觉当量、随 Dynamic
                    // Type 缩放），与胶囊内同件同口径
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("当前模型 \(displayModelName)，切换模型")
    }

    /// 模型 Picker 的 selection 桥（0.36.13）：读经
    /// Core 判定口径过一遍（清单外 id 不喂给 Picker
    /// 冒充有勾——回退原值时无任何行命中、零勾，与
    /// checkedID 的零勾语义同口径）；写直达唯一写入
    /// 口 selectChatModel，不动 AppState/发送链
    private var chatModelPickerBinding: Binding<String> {
        Binding(
            get: {
                ModelMenuSelection.checkedID(
                    itemIDs: ChatModels.items.map(\.id),
                    selected: appState.chatModel
                ) ?? appState.chatModel
            },
            set: { appState.selectChatModel($0) }
        )
    }

    /// 底部发送区（0.2.6 起由消息列表的安全区承载、不
    /// 再是覆盖层；0.2.6–0.4.2 为 .safeAreaInset，0.4.3
    /// 改 .safeAreaBar 注册，§28）：错误/提示条＋发送
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
        // 策——几何判定离底之外并入事实信号（最后一
        // 条已可见即在底），治估算距离驻留迟滞带的永
        // 不消失；显隐派生已提为全页单一出处 shows-
        // BackToBottomButton（本函数不再自算）；未读
        // 计数于 0.41.0 落地（AwayUnreadCounter），
        // 钮的宿主与落位于 §124 改归本区布局流（输
        // 入舱上方一行，见栈内钮行注）
        return VStack(spacing: OneDayMetrics.spacingS) {
            if let errorMessage {
                errorBanner(errorMessage)
                    // 0.25.0（动效专包）：错误/提示条进出
                    // 原为无过渡硬入硬出（高度跳变）——补
                    // opacity 过渡，高度与淡入同走下方
                    // swap 容器动画（单调无过冲，与回到底
                    // 部钮同口径）
                    .transition(.opacity)
            }
            if let notice {
                noticeBar(notice)
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
            // 抖动的护栏在判定层（迟滞双阈值＋末条事
            // 实信号，0.36.5 钉死），不靠把钮逐出布局
            // 流——三轮浮层落位病史见 DESIGN §124
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
        // notice）。回底钮的高度动画键两度退役又回归，
        // 如实记：0.41.0 钮浮层化时退役（当时的防摆
        // 手段是把钮逐出布局流）；§124 钮回到布局流，
        // 显隐键（showsBackToBottomButton）作第三键
        // 以同口径回归——防摆护栏改由判定层迟滞双阈
        // 值＋末条事实信号承担（0.36.5 钉死），三轮
        // 浮层落位的病史与取舍见 §124
        // 0.25.0（动效专包）：条本体淡入淡出、容器
        // 高度同步单调滑动，不再硬跳
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
            value: notice
        )
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: showsBackToBottomButton
        )
    }

    /// 回到底部圆钮（0.2.4 曾换原生玻璃；0.3.8 第 28 条
    /// 浮件统一白浮纸——圆钮全体同画法）
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
                .odFloatPaper(in: Circle())
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
            LazyVStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                if let thread = currentThread {
                    // 0.30.0（聊天时间系统）：分隔条落点与
                    // 文案由 Core ChatTimeline 按会话条目
                    // 走查（工具卡条目不单独占分隔、也不
                    // 重置锚点——以所属回合时间为准）；流
                    // 式行/流内工具卡是当前回合的呈现层尾
                    // 巴、不另起分隔（本回合的分隔由其
                    // user 条目承担，见 timelineDividers）
                    let dividers = timelineDividers(
                        for: thread.sortedEntries
                    )
                    ForEach(
                        entryRenderItems(for: thread.sortedEntries)
                    ) { item in
                        switch item {
                        case .entry(let entry):
                            VStack(
                                alignment: .leading,
                                spacing: OneDayMetrics.spacingS
                            ) {
                                if let dividerText
                                    = dividers[entry.id] {
                                    timelineDivider(dividerText)
                                }
                                bubble(entry)
                            }
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
                // 就地审批（0.36.21，规格 §1/§3）：待批
                // 写入在流末尾出卡——桥载荷无会话归属字
                // 段，走退位形态（全部未决汇到当前流＋
                // 枢纽兜底）；与回告卡同纪律：只在呈现
                // 层拼装、绝不写入会话；store 与枢纽共
                // 享同一份（AppState.sharedHubStore）
                ChatApprovalZone(store: appState.sharedHubStore())
                if currentThread == nil && !isStreaming {
                    // 空状态（DESIGN-V4 §5 两行字口径保
                    // 留）：0.26.0 起形象位由 SF 符号换三
                    // 狗头像、边长走形象档空态值（48/56/
                    // 68）——用户外观令点名的作用面
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
                        Text("和你的 Hermes 聊聊")
                            // 0.3.3 收编：手写 fontWeight 漂移
                            // 改走 sectionTitle 角色（阶梯账
                            // 见原字重账本，已废止）
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                        Text("消息经你自己的服务器发给 Agent，记录只存这台手机。")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, OneDayMetrics.spacingXL)
                }
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            // 0.7.0（M1 轻保活）：滚动目标布局登记——条目
            // 可见性按 UUID id 回报，喂滚动锚的存/取
            .scrollTargetLayout()
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingS)
            // 命中域撑满（0.3.5，§20.2）：内容栈帧宽撑满、
            // 高至少撑到列表可视高（容器高 − 底 content-
            // Margins spacingS）。0.4.3 前顶栏是 overlay、
            // 容器高含其悬浮区、常数按 64 近似扣减；顶栏
            // 注册 safeAreaBar 后顶区由安全区自理、容器高
            // 已不含它，64 常数退役。0.3.4 前栈帧只裹住
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
            // 0.19.0：命中形状补全——0.3.5 只把帧撑满，
            // LazyVStack 的命中测试仍只认子视图实形：
            // 消息行之间的纵向空隙、空状态之外的空白
            // 都不在任何子视图里，帧再大也点不中（用户
            // 22:26 真机再次点名「点空白收回键盘」的残
            // 洞）。contentShape 令栈帧全域可命中，下方
            // 既有 onTapGesture 的辖区才真正等于撑满帧；
            // 子视图（气泡/按钮/链接/长按菜单）仍先命中
            // 自己，既有仲裁关系不动
            .contentShape(Rectangle())
            // 点消息区空白收键盘（0.2.1 缺陷修复；滚动拖动
            // 收起由 scrollDismissesKeyboard 承接）。0.2.7 起
            // 本手势只挂内容栈、不再挂 ScrollView 本体：
            // ScrollView 的命中域含底部 safeAreaInset（发送
            // 舱所在），挂本体时点发送舱也被判成「点空白」，
            // 且 SwiftUI 手势竞技场会先于 UIKit 触摸裁决——
            // SwiftUI TextField 时代靠焦点系统自带手势过关，
            // 换自量高 UITextView 后点按被本手势吞掉、聚焦
            // 不能（CI 三轮实证）。发送舱不是消息区，本就不
            // 该由它管辖
            // 0.3.5：手势类型与挂点不变（与行内按钮/链接的
            // 既有仲裁关系不动、不误收），只补命中域——
            // 见上方撑满注（§20.2）
            .onTapGesture {
                // 0.2.8：收键盘经焦点句柄直达文本视图本体
                //（resignFirstResponder），不写任何 SwiftUI
                // 焦点状态；失焦事实由 delegate 回调回写
                composerFocusHandle.dismiss()
            }
        }
        // 滚动边距：顶部不再设 contentMargins——顶栏已
        // 注册为本列表的 safeAreaBar、首屏位置由安全区
        // 本体让出（0.4.2 前是 overlay 悬浮＋.content-
        // Margins(.top, 88) 代偿，§28.1 原因一即出在此）；
        // 底只留与发送舱的小间隙，发送区本体已由下方
        // safeAreaBar 注册留位（0.4.3），不按悬浮层实测
        // 高度给边距。
        // 0.4.0（审计 §6.1／§1.1）：topFade 渐隐带已删
        // （实色带干扰＋作用区错位），滚动边缘模糊走系
        // 统 .scrollEdgeEffectStyle(.soft)；0.4.3 起两
        // 缘的 bar 均已注册（顶 headerBar／底 bottom-
        // Bar，同挂 safeAreaBar），效果作用区由 bar 高
        // 度决定（WWDC25-219/323、Adopting Liquid
        // Glass 的自定义 bar 注册口径）
        .safeAreaBar(edge: .top) {
            // 0.7.1（chrome 裁决全案）：顶缘 E11 渐进
            // 模糊带整段拆除、例外 E11 注销——0.4.4 起
            // 挂在此处的 background 溢出带（上探状态区
            // 60pt、带长 176）经 0.6.1 真机量测坐实是
            // 顶部两色接缝带的本体：对平色背景 backdrop
            // 模糊输出恒等于材质 tint，静止时「朦胧」
            // 不存在、只剩一块带硬边的灰片（245 vs 画
            // 布 252，裁决档 §1.1）；且 WWDC25-323 明
            // 文 bar 后自加背景层会干扰系统边缘效果。
            // 顶栏自此不挂任何 background：静止态直接
            // 坐在画布上同色无缝，滚动态由下方 .soft
            // 在栏高内柔化（官方结构，§3.1）
            // 0.37.0（模型包·进展胶囊）：身份胶囊下方
            // 同 bar 内加进展胶囊一颗——他聊/后台有进
            // 行中工作时才出现（派生在 Core
            // ProgressCapsule，数据源与台账同源）；胶
            // 囊本体自带玻璃，是内容不是背景层，不犯
            // 上方「bar 后不挂 background」的裁决
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
        .scrollEdgeEffectStyle(.soft, for: .top)
        // 0.4.2（用户 10:54 圈图点名，二期 M3 卡提前落
        // 地）：底缘同挂柔效；0.4.3 注册后系统才真正按
        // 发送舱高度发放本效果——0.4.2 时发送舱还在
        // safeAreaInset 里，按 Grow 出货应用的实测记录
        // 该挂法等于关掉底部边缘效果（§28.1 原因二
        // 实锤），全页无实色遮罩残留（topFade 已于
        // 0.4.0 整层删除）
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // 0.36.27（§97 件二，用户 03:48 点题「输入框
        // 上面有点大，小点就行」）：列表底边距收一档
        // spacingS 8 → spacingXS 4，与 inputBar 顶
        // padding 同步收（见 inputBar 注）；「末条消息
        // 底→发送舱卡顶」链总量 32 → 24（量账见 §97.2）
        .contentMargins(.bottom, OneDayMetrics.spacingXS, for: .scrollContent)
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
        .safeAreaBar(edge: .bottom, spacing: 0) {
            // 0.6.1（用户第二轮真机点名，底部白块 P0）：
            // 发送区底缘 E11 渐进模糊带整段删除——它是
            // 聊天页底部唯一的自绘全宽乳白层（system-
            // Material 满幅横在发送区与底栏之间，0.4.5
            // 虽已把带底收齐到舱底缘，带身仍横贯页底、
            // 与玻璃底栏叠读成一块白块）；删后发送区下
            // 方零自绘层：消息自发送舱下缘起由系统
            // .scrollEdgeEffectStyle(.soft, for: .bottom)
            // 柔化（上方已挂），玻璃底栏直接浮在内容
            // 上。（0.7.1 续：当时保留的顶缘带已随 E11
            // 注销一并拆除，见上方顶栏 safeAreaBar 注；
            // 底部交界残余白带的病根经裁决档 §1.2 定
            // 为背景不同源，主治在 chatSurface 的背景
            // 全出血，见彼处注）
            bottomBar(proxy)
        }
        // 初始落位兜底（0.36.13，外部核查 community-
        // solutions-check 第 2 题吸收 vellum PR #21760）：
        // 声明式锚只管内容首次布局的落点——命令式
        // scrollTo 在新内容量实前触发会落错位置，无锚
        // 兜底时首帧可停在顶部。与 scrollTo 不冲突（锚
        // 只定初始位、后续滚动全归命令式与 .task 定版
        // 链）；键盘升起/流式跟随的落点误差不归它管、
        // 仍以 scrollToBottom 的落定复贴为主治
        .defaultScrollAnchor(.bottom)
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
            // 0.36.13：原始读数另存一份喂落定复贴复核
            // （见 lastBottomDistance 注）
            lastBottomDistance = distance
            isNearBottom = BottomProximity.update(
                distance: distance, wasNearBottom: isNearBottom
            )
        }
        // 列表可视高回写（0.3.5）：喂内容栈的撑满
        // minHeight（点空白收键盘命中域，见栈内撑满注）
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height
        } action: { _, newHeight in
            listViewportHeight = newHeight
        }
        // 「点空白收键盘」手势在内容栈上（见 messageList 内注），
        // 不挂 ScrollView 本体——其命中域含发送舱 inset
        .onChange(of: currentThread?.sortedEntries.count) { _, _ in
            // 用户已上翻看历史时不强拉回底（0.2.2 交互专项）
            // 0.4.2（§27）：跟随贴底改无动画一步贴合——
            // 带 0.25s 动画的 scrollTo 追逐随内容生长移
            // 动的锚点、永远在追移动靶，是到底抖动的主
            // 因；人发起的滚动（回到底部钮/键盘锚底）仍
            // 走动画，见 scrollToBottom
            if isNearBottom {
                scrollToBottom(proxy, animated: false)
            }
            // 0.36.13（诊断 §2.3 堵洞 3）：条目变化时用
            // 存量可见集主动重算事实信号——末条刚落盘
            // 而可见集未再变化时，旧实现持上一条的判定
            // 不动，钮显隐可长期错位
            refreshLastEntryVisible()
            // 0.41.0：未读计数同路喂入（先刷新事实信号、
            // 再按新判定计账，顺序不可反）
            feedAwayUnread()
        }
        // 0.7.0（M1 轻保活）：首个可见条目回写（UUID 型
        // id 只有消息条目持有，流式行/底部锚是字符串 id、
        // 不在此列）
        // 0.36.5（审计 bug 2）：同批回写事实信号——最
        // 后一条条目在不在可见集内（喂回底钮政策判定，
        // 见 topVisibleEntryID 同处与 BottomFollow-
        // Policy）；线程为空时恒 false
        // 0.36.13（诊断 §2.3 堵洞 1＋3）：判定改查「最
        // 后一个渲染项的滚动目标 id」（Core LastScroll-
        // Target，与渲染成组同构——末条在工具组内时目
        // 标是组首条，旧实现拿末条 id 比可见集永假）；
        // 可见集先存档，事实信号由 refreshLastEntry-
        // Visible 单点算（可见集变化与条目变化两路共用）
        .onScrollTargetVisibilityChange(idType: UUID.self) { ids in
            topVisibleEntryID = ids.first
            lastVisibleEntryIDs = Set(ids)
            refreshLastEntryVisible()
            // 0.41.0：可见集变化是在底事实的另一路输入
            // （用户手动滚回底部即清零、滚离即冻结水位）
            feedAwayUnread()
        }
        // 0.36.5（审计 bug 1）：发送贴底——send() 落盘
        // 且链接成功后递增令牌，本处执行三步：置真跟
        // 随态（Core 政策：自己发送无条件贴底，其后
        // 流式跟随与落定跟随自动接续）、即时无动画贴
        // 底、120ms 延迟复贴一次（等发送舱塌缩动画与
        // LazyVStack 布局落定后校正落点，与本文件既
        // 有 80/120/300ms 复贴模式同族）
        .onChange(of: sendPinToken) { _, _ in
            // 0.41.0：自发发送清未读账（Core 口径：发送
            // 无条件贴底、水位推到当前末条）
            awayUnread.noteOwnSend(
                entryIDs: currentThread?.sortedEntries.map(\.id) ?? []
            )
            isNearBottom = BottomFollowPolicy.nearBottomAfterOwnSend()
            scrollToBottom(proxy, animated: false)
            let pinnedThreadID = currentThreadID
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard currentThreadID == pinnedThreadID else { return }
                scrollToBottom(proxy, animated: false)
            }
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
            // 0.36.13：可见集与事实信号是上一线程的家
            // 当——切入先清零，新线程的可见性回调随布
            // 局落定自会重填，不拿旧集判新线程的末条
            lastVisibleEntryIDs = []
            lastEntryVisible = false
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
                return
            }
            if isNearBottom,
               streamFollowGate.shouldFollow(
                   currentCount: newText.count
               ) {
                scrollToBottom(proxy, animated: false)
            }
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
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification
            )
        ) { _ in
            if composerFocused {
                anchorToBottomAfterKeyboard(proxy)
            }
        }
    }

    /// 键盘动画后锚底：等键盘帧落定（300ms 覆盖系统键盘
    /// 动画时长）再滚；执行时复查 isNearBottom，用户在等
    /// 待间隙里上滑了就不拉
    private func anchorToBottomAfterKeyboard(_ proxy: ScrollViewProxy) {
        guard isNearBottom else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if isNearBottom {
                scrollToBottom(proxy)
            }
        }
    }

    /// 事实信号单点重算（0.36.13，诊断 chat-bottom-
    /// geometry §2.3）：以最后一个渲染项的滚动目标
    /// id（Core LastScrollTarget，与 entryRenderItems
    /// 的成组规则同构）查存量可见集——可见集变化与
    /// 条目数变化两路都经此一处，判定口径不再分叉；
    /// 线程为空/无条目恒 false
    private func refreshLastEntryVisible() {
        guard let entries = currentThread?.sortedEntries,
              let lastID = LastScrollTarget.lastScrollTargetID(
                  entries: entries.map {
                      LastScrollTarget.EntryStub(
                          id: $0.id, isToolCard: $0.toolCard != nil
                      )
                  }
              )
        else {
            lastEntryVisible = false
            return
        }
        lastEntryVisible = lastVisibleEntryIDs.contains(lastID)
    }

    /// 滚到底部锚点。animated=true 只给人发起的滚动
    /// （回到底部钮、键盘锚底）：走页面过渡曲线滑过
    /// 去；内容跟随（新条目落地、流式生长）必须
    /// animated=false 一步贴合当前底部——0.4.2 定因：
    /// 带动画的 scrollTo 追逐随内容生长不断移动的锚
    /// 点，是划到底抖动的主因（§27）
    /// 0.36.13（诊断修法 1，落定复贴收口）：一切出口
    /// 在贴底后一拍（120ms，与发送路径既有复贴同
    /// 延迟）复核实测距底——LazyVStack 按估算总高落
    /// 点、尾行未量实时落点离真底可差数十 pt；一拍
    /// 后尾行已被量实，距底仍 >24pt（Core Bottom-
    /// Settle）才以无动画再贴一次（只贴一次、不成
    /// 环）。键盘锚底、条目/流式跟随、发送贴底、线
    /// 程恢复、首屏定版全经此一处收口受益；线程在
    /// 等待间隙被切走则作废
    private func scrollToBottom(
        _ proxy: ScrollViewProxy, animated: Bool = true
    ) {
        performScrollToBottom(proxy, animated: animated)
        let pinnedThreadID = currentThreadID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard currentThreadID == pinnedThreadID else { return }
            guard BottomSettle.shouldRestick(
                distance: lastBottomDistance
            ) else { return }
            performScrollToBottom(proxy, animated: false)
        }
    }

    /// 贴底本体（不带复核）：scrollToBottom 的首贴与
    /// 复贴共用，复贴不经 scrollToBottom 以免自触发
    /// 再复核成环
    private func performScrollToBottom(
        _ proxy: ScrollViewProxy, animated: Bool
    ) {
        if animated {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.pageCrossfade, reduceMotion: reduceMotion
                )
            ) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
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
        if entry.echoKey != nil {
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
                VStack(alignment: .trailing, spacing: OneDayMetrics.spacingXS) {
                    if let quote = entry.quote {
                        quoteBlock(quote)
                    }
                    if let data = entry.imageData, let image = UIImage(data: data) {
                        // 0.36.19（§84.5）：已发图宽高双封
                        // 盒（Core ChatImageSizing，220×240
                        // 只缩不放大）——旧只封宽 220，竖长
                        // 截图要长到约 477pt 高吃半屏
                        let displaySize = ChatImageSizing.displaySize(
                            for: image.size
                        )
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: displaySize.width,
                                height: displaySize.height
                            )
                            .clipShape(
                                RoundedRectangle(cornerRadius: OneDayMetrics.spacingM)
                            )
                            // 点开查看器（0.36.4：集合
                            // 载荷、同线程可翻页）
                            .onTapGesture {
                                openImageViewer(
                                    ChatImageViewerItem(
                                        source: .data(data)
                                    )
                                )
                            }
                            // 0.43.0（A11Y-V2）：本地图最低
                            // 文本等价——发送时刻（A11yText
                            // 拼装、Core 钉测）；动作与点按
                            // 同一入口（openImageViewer）
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                A11yText.imageLabel(sentAt: entry.createdAt)
                            )
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(L10n.string("查看大图"))
                            .accessibilityAction {
                                openImageViewer(
                                    ChatImageViewerItem(
                                        source: .data(data)
                                    )
                                )
                            }
                    }
                    // 0.8.0（P1）：历史导入的服务端图片
                    // （标记路径）——缩略经文件下载通道
                    // 取回，点开同一个全屏查看器
                    ForEach(entry.remoteImagePaths, id: \.self) { path in
                        ServerRemoteImage(path: path)
                            .clipShape(
                                RoundedRectangle(cornerRadius: OneDayMetrics.spacingM)
                            )
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
                        Text(TextShaping.prettyWrapDocument(entry.content))
                            // 0.3.8 第 29 条：气泡正文走显式
                            // 角色，与助手侧 MarkdownText/
                            // StreamingText 同口径。0.4.4
                            // （§29）：基准 17→16（.callout
                            // 语义载体）＋墨换 bodyInk
                            // （#262626），四处正文同改
                            .font(.callout)
                            // 0.26.0：泡上字改走主题泡字色
                            // （默认行浅档与 bodyInk 同值、
                            // 暗档修正见 Palette 注）
                            .foregroundStyle(Palette.userBubbleText)
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
                }
                .modifier(messageMenu(for: entry))
                .modifier(swipeReply(for: entry))
            }
        } else {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
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
                    ServerRemoteImage(path: path)
                        .clipShape(
                            RoundedRectangle(cornerRadius: OneDayMetrics.spacingM)
                        )
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
                assistantBubble {
                    MarkdownText(entry.content)
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
                let fileRefs = FileRefDetector.detectStandaloneAnchored(
                    in: entry.content,
                    excluding: entry.remoteImagePaths
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

    /// 打开图片查看器（0.36.4）：集合＝同线程全部图
    /// 片（本地图 imageData＋远端图 remoteImagePaths，
    /// 按消息时间序、工具卡不占位）；点中项不在集合
    /// 内（如正文文件牌探测出的图）时回落单图集合，
    /// 不假装它在会话图片序里
    private func openImageViewer(_ item: ChatImageViewerItem) {
        var collected: [ChatImageViewerItem] = []
        if let thread = currentThread {
            for entry in thread.sortedEntries
            where entry.toolCard == nil {
                if let data = entry.imageData {
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
            notice = FileOpenFailure.invalidPath.message()
            return
        }
        fileOpenTarget = FileOpenTarget(path: path, anchor: anchor)
    }

    /// 长按菜单的文本口径（0.4.1）：助手消息剥 Markdown
    /// 标记符号成可读文本（MessagePlainText 纯函数），
    /// 用户消息原文即纯文本
    private func plainText(for entry: ChatEntry) -> String {
        entry.role == "assistant"
            ? MessagePlainText.make(from: entry.content)
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
        composerFocusHandle.focus()
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
            isEnabled: !entry.content.isEmpty,
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

    /// 助手消息泡（0.2.5，对照 Muse 的助手形态）：浅灰软
    /// 填充（Palette.bubbleFill）＋18pt 圆角，左对齐、右侧留
    /// 白上限与用户泡的 44pt 让位同逻辑；泡内代码块沿用
    /// fieldFill 填充、比泡面深一阶，层级不打架。流式半截
    /// 与等待点同样入泡，内容不溢出泡外。此形态推翻
    /// DESIGN-V2 §3.5 的裸排决定，追记在 DESIGN-V4 §9。
    private func assistantBubble<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(alignment: .top) {
            content()
                .padding(.horizontal, OneDayMetrics.bubblePaddingH)
                .padding(.vertical, OneDayMetrics.bubblePaddingV)
                .background(
                    Palette.bubbleFill,
                    in: RoundedRectangle(
                        cornerRadius: OneDayMetrics.assistantBubbleCorner
                    )
                )
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
                TypingDots()
                    .padding(.vertical, OneDayMetrics.spacingXS)
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

    private func errorBanner(_ message: String) -> some View {
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
        }
        .background(Palette.pageBG)
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
                    notice = nil
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
        VStack(spacing: OneDayMetrics.spacingS) {
            // 0.36.6（§71）：语音失败行与到限提示行——
            // 三段式文案（发生了什么＋影响＋怎么办），
            // 权限被拒在此给「去设置」降级路（续编 S4）
            SmoothExpand(isExpanded: dictation.failure != nil) {
                if let failure = dictation.failure {
                    dictationFailureBar(failure)
                }
            }
            SmoothExpand(isExpanded: dictation.notice != nil) {
                if let notice = dictation.notice {
                    dictationNoticeBar(notice)
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
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        // 0.36.27（§97 件二）：顶 padding 收一档
        // spacingS 8 → spacingXS 4（卡上外距，与列表
        // 底 contentMargins 同步，链总量 32 → 24）
        .padding(.top, OneDayMetrics.spacingXS)
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
            SmoothExpand(isExpanded: pendingQuote != nil) {
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
        Menu {
            Button {
                showCamera = true
            } label: {
                Label("拍照", systemImage: "camera")
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            Button {
                showPhotoPicker = true
            } label: {
                Label("相册选图", systemImage: "photo.on.rectangle")
            }
            Button {
                // 0.36.31（件二）：走 UIKit 桥呈现（桥
                // 内延一拍避开本 Menu 的收起瞬间、回
                // 调先 dismiss 再喂回 loadPickedFiles）
                DocumentPickerBridge.present { urls in
                    loadPickedFiles(urls: urls)
                }
            } label: {
                Label("选文件", systemImage: "doc")
            }
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
        .accessibilityLabel("添加附件")
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
        var oversized = 0
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self)
            else { continue }
            guard data.count <= 20 * 1024 * 1024 else {
                oversized += 1
                continue
            }
            appendImage(data)
        }
        if oversized > 0 {
            notice = "有 \(oversized) 张图片超过 20MB，未加入待发列表。"
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
            notice = "没有选到文件，未加入待发列表。"
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
            notice = summaries.joined()
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
        thread.sortedEntries.map {
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
                    notice = "已转入我的对话"
                }
            case .failed:
                // 没打开成（仍停在原线程）：出处作废、
                // 对象引用按当前线程回派，不许把胶囊
                // 挂到没在看的频道行上
                appState.channelViewingOrigin = nil
                syncDrawerObjectFromCurrentThread()
            }
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
            errorMessage = (error as? HermesError)?.userMessage
                ?? "会话导入失败，请稍后再试。"
            return .failed
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = attachments
        // 0.4.1：引用随本条发送，起手先快照、随即清除
        // 引用条（发送即消费，不残留到下一条）
        let quote = pendingQuote
        guard !isStreaming, !text.isEmpty || !pending.isEmpty else { return }
        // 0.3.2：发送起手不再挂触觉——触感挪到结果点
        // （run 完成 .success / 失败 .warning，见 driveRun）
        input = ""
        attachments = []
        pendingQuote = nil
        pendingQuoteIsFork = false
        errorMessage = nil
        notice = nil
        guard let thread = ensureThread() else {
            // 0.27.0：定位失败整轮不发——输入与附件原
            // 样退回发送舱（错误文案已由 ensureThread
            // 置好），不许把消息落进别的线程
            input = text
            attachments = pending
            pendingQuote = quote
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
            notice = "上一条还在生成中，正在确认结果，落定后可继续发送。"
            Task { await resumeRunIfNeeded() }
            return
        }
        // 0.27.0：种子快照要在本轮条目落盘前取——链
        // 接时的历史导入只含既往条目，本轮新消息由
        // 随后的会话模式发送单独投递，不许在服务端
        // 落两份
        let seedSnapshot = Self.seedEntries(of: thread)
        let imageDatas = pending.compactMap(\.imageData)
        let filePayloads = pending.compactMap(\.filePayload)
        let newEntry = ChatEntry(
            role: "user", content: text, thread: thread,
            imageData: imageDatas.first, quote: quote
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
        // 0.4.1：上下文组装走 MessageQuote.outgoingContent
        // ——带引用的消息（含本轮新消息与历史回放）把引
        // 用块拼进 content，引用在每轮重放里持续在场；
        // 无引用的消息原样（纯函数保证）
        // 0.8.0：先滤角色再取尾 20——工具卡条目（role=
        // "tool"）只呈现、永不进重放上下文
        // §123（H1）：回响条目（echoKey 非空，role 借
        // "assistant" 落盘）同样只呈现、永不进上下文——
        // 它是 App 的事实记录，不是智能体说过的话
        var context = thread.sortedEntries
            .filter {
                ($0.role == "user" || $0.role == "assistant")
                    && $0.echoKey == nil
            }
            .suffix(20).map {
            ChatMessage(
                role: $0.role,
                content: MessageQuote.outgoingContent(
                    userText: $0.content, quote: $0.quote
                )
            )
        }
        // 本条若带图：最后一条用户消息改多模态 parts 编码
        // （图片走 OpenAI image_url + data: base64；服务端/模型
        // 不支持时错误经 errorBanner 如实呈现，不假装发过）
        if !imageDatas.isEmpty, let last = context.last, last.role == "user" {
            let urls = imageDatas.map {
                "data:image/jpeg;base64,\($0.base64EncodedString())"
            }
            context[context.count - 1] = ChatMessage(
                role: "user",
                text: MessageQuote.outgoingContent(
                    userText: text, quote: quote
                ),
                imageDataURLs: urls
            )
        }
        // 文件真发送（0.36.29，契约实测冻结后开放）：
        // 待发文件在 sendTask 起手逐个上传到服务端
        // attachments/，回执路径拼进尾条 input 的
        // @file 引用（见 sendTask 内）；原「尚未开
        // 放」notice 随本版退役
        streamingText = ""
        // 0.8.0：上一轮的流式工具卡列清空，从本轮累积
        liveToolCards = []
        // 0.36.10：事件序标记同步清零，从本轮重记
        liveOrder = []
        sendTask = Task {
            // 0.36.29（件四）：带文件时先逐个上传——
            // 任一失败整条拦下（与链接失败同舞步：删
            // 本轮条目、输入与附件原样退回、报错点名
            // 文件），不许丢下文件只发文本；全成才攒
            // 下回执路径，尾条拼装时拼 @file 引用
            var fileServerPaths: [String] = []
            if !filePayloads.isEmpty {
                do {
                    fileServerPaths = try await
                        uploadPendingFiles(filePayloads)
                } catch let failure as FileUploadFailure {
                    modelContext.delete(newEntry)
                    try? modelContext.save()
                    input = text
                    attachments = pending
                    pendingQuote = quote
                    errorMessage = "文件「\(failure.fileName)」没能上传，本条未发送："
                        + failure.reason
                        + "处理后重新发送即可。"
                    Haptics.error()
                    streamingText = nil
                    streamingReasoning = nil
                    reasoningStartedAt = nil
                    sendTask = nil
                    return
                } catch is CancellationError {
                    streamingText = nil
                    streamingReasoning = nil
                    reasoningStartedAt = nil
                    sendTask = nil
                    return
                } catch {
                    // uploadPendingFiles 只抛 FileUpload-
                    // Failure/取消，此兜底防未知错误形态
                    // 被静默吞（有声口径）
                    modelContext.delete(newEntry)
                    try? modelContext.save()
                    input = text
                    attachments = pending
                    pendingQuote = quote
                    errorMessage = "文件上传失败，本条未发送，请稍后再试。"
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
                // §121 题二 a（发送回填）：上传全成后
                // 立即把回执路径写回本地条目落盘——用
                // 户气泡文件牌的唯一数据源就是 entry.
                // remoteFilePaths，旧链只把路径拼进出
                // 站文本、本地条目恒空，刚发的消息在
                // 本地永远没牌（真机实证：助手牌正常、
                // 自己牌缺失）。落点在此（失败分支全
                // 已 return、走到这里即全成），流式期
                // 间牌就在；其后发送形态失败删条目的
                // 既有路径不受影响
                if !fileServerPaths.isEmpty {
                    newEntry.remoteFilePathsData =
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
            // 失败整轮不发（无头回退已删）：删本轮条
            // 目、输入原样退回发送舱、错误横幅明示原
            // 因；链接窗口内被用户停止仍按停止语义静
            // 默收尾（条目保留、与旧口径一致）
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
                modelContext.delete(newEntry)
                try? modelContext.save()
                input = text
                attachments = pending
                pendingQuote = quote
                errorMessage = "会话链接失败，本条未发送："
                    + ((error as? HermesError)?.userMessage
                        ?? "服务端会话建立失败")
                    + "。链接恢复后重新发送即可。"
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
            // 执行贴底三步。链接失败的回滚分支（上方
            // catch 删条目）与停止分支都到不了这里
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
                userEntry: newEntry
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
                capsuleModel: appState.chatModel
            ) {
                let capsule = appState.chatModel
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
                        model: appState.chatModel,
                        seedEntries: seedEntries
                    )
                    thread.serverSessionID = linkedID
                    thread.linkedModel = appState.chatModel
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
        runWasDetached = false
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
        let provider = ChatModels.providerField(
            for: appState.chatModel
        )
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
                    input: input, model: appState.chatModel,
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
        if let submitError, runMachine.phase == .failed {
            // 提交被明确拒绝（真失败）：本轮从未在服务
            // 端成立——消息留痕、横幅照实报、账本清除
            if !demoMode {
                appState.runLedger.remove(threadID: thread.id)
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
            runWasDetached = true
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
                            model: appState.chatModel,
                            provider: ChatModels.providerField(
                                for: appState.chatModel
                            ),
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
            notice = "生成仍在服务器进行中，稍后回到本对话会自动补齐结果。"
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
            userText: userEntry.content, quote: userEntry.quote
        )
        if let imageData = userEntry.imageData {
            return .message(ChatMessage(
                role: "user", text: text,
                imageDataURLs: [
                    "data:image/jpeg;base64,"
                        + imageData.base64EncodedString()
                ]
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
            errorMessage = terminalStatusHint?.output
                ?? terminalStatusHint?.error
                ?? terminalOutputHint
                ?? "生成失败，请稍后再试。"
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
        runMachine.apply(.transcriptSettled)
        let phase = runMachine.phase
        deleteTurnPartialEntries(thread: thread, entry: entry)
        if settled.failed {
            errorMessage = terminalStatusHint?.output
                ?? terminalStatusHint?.error
                ?? settled.failureText
                ?? "生成失败，请稍后再试。"
            if !appState.isDemo {
                appState.runLedger.remove(threadID: thread.id)
            }
            finishRunPresentation(failed: true)
            return
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
        // 有正文给 .success；断线后补齐给中性提示；真
        // 取消给「已停止生成」；失败已在上分支处理
        if phase == .finished {
            if settled.finalText?.isEmpty == false {
                Haptics.success()
            }
            if runWasDetached {
                notice = "已重新连接，回复已补齐。"
            }
            // 标题回流触发（0.21.0 沿用）：已链接旁聊
            // 一轮完整落地后顶刷新令牌等服务端 AI 标题
            if thread.serverSessionID != nil,
               thread.id != appState.sideChats.mainThreadID {
                appState.noteLinkedSideChatTurnFinished()
            }
        } else if phase == .cancelled {
            notice = "已停止生成。"
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
            guard candidate.echoKey == nil else { continue }
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
        runWasDetached = true
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
            let partials = thread.entries.filter {
                $0.id != userEntry.id
                    && $0.createdAt > userEntry.createdAt
                    && $0.echoKey == nil
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
private struct SwipeReplyModifier: ViewModifier {
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

/// 「选择」承载页（0.4.1）：整条消息的纯文本在系统
/// sheet 里以 .textSelection(.enabled) 呈现——选择
/// 手柄、长按拷贝菜单全是系统行为，可跨段划选任意
/// 部分。选型理由（为何不直接在气泡上划选）见
/// DESIGN-V4 §26
private struct SelectableTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .font(.body)
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
