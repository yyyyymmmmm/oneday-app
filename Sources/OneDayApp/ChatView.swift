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

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]

    @State private var currentThreadID: UUID?
    @State private var input = ""
    /// 非 nil 表示正在生成：值是已累积的流式文本
    @State private var streamingText: String?
    /// 流式思考（reasoning）已发布快照（0.5.1，§32）：
    /// 非 nil 表示本轮已收到思考增量；思考原文经发布
    /// 闸合并后写入，呈现走 streamingRow 内的折叠单元
    @State private var streamingReasoning: String?
    /// 本轮首个思考增量的到达时刻（0.5.1）：折叠单元
    /// 实时计时与落盘 reasoningSeconds 的计时起点
    @State private var reasoningStartedAt: Date?
    /// 正文/思考两条通道的发布合并闸（0.5.1，§32，
    /// OneDayCore.StreamPublishGate）：增量先攒缓冲、
    /// 按 80ms 窗或 64 字阈值合并发布，与 streamFollow-
    /// Gate（管滚动）分工互不替代；runStream 起止归零
    @State private var contentPublishGate = StreamPublishGate()
    @State private var reasoningPublishGate = StreamPublishGate()
    /// Qwen 冷启唤醒重试中（0.3.0 接线，§15）：等待行亮
    /// 「模型唤醒中」提示
    @State private var isWakingModel = false
    @State private var sendTask: Task<Void, Never>?
    @State private var errorMessage: String?
    /// 0.2.1：非错误提示（如文件附件未发送说明），可关闭
    @State private var notice: String?
    // （0.4.5 迁出：抽屉开合/跟手/搜索/重命名/服务端会
    // 话组状态随抽屉本体迁往 DrawerView 与壳层
    // ContentView，见 §30）
    /// 消息区是否贴近底部：决定自动跟随滚动与「回到底部」钮
    @State private var isNearBottom = true
    /// 流式跟随滚动节流闸（0.4.2，§27）：OneDayCore
    /// 纯逻辑记账，每 ≥40 字放行一次无动画贴底；流结
    /// 束与切换线程时归零（见 messageList 的 onChange）
    @State private var streamFollowGate = StreamFollowGate()
    /// 列表可视高（0.3.5，§20）：onScrollGeometryChange
    /// 回写，喂消息内容栈的撑满 minHeight——点空白收键
    /// 盘的命中域（见 messageList 撑满注）
    @State private var listViewportHeight: CGFloat = 0
    /// 演示模式自动开流只跑一次（演示态展示流式效果用）
    @State private var demoStreamStarted = false
    /// 0.2.1 附件与键盘：待发附件、三种选择器开关、输入焦点
    @State private var attachments: [PendingAttachment] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showFileImporter = false
    /// 0.2.8 拆桥（DESIGN-V4 §12）：焦点不再经 @FocusState
    /// 把关——本状态只是 delegate 回调的观察回写（当前无
    /// 视图据它分支，留作事实通道）；程序化收起/聚焦经
    /// composerFocusHandle 直达文本视图本体
    @State private var composerFocused = false
    @State private var composerFocusHandle = ComposerFocusHandle()
    /// 0.2.2：模型选择器（顶栏副题点开，列表服务端拉取）
    @State private var showHub = false
    /// 0.4.0（§3.4）：服务端会话导入进行中的 id（防重复
    /// 触发并发导入同一条会话）
    @State private var importingSessionID: String?
    /// 0.4.0（§3.4）：「会话信息」sheet（详情页降级后的
    /// 次级入口，仅已关联服务端会话的线程可开）
    @State private var showSessionInfo = false
    /// 0.4.1：长按「回复」待发送的引用（值快照，不持
    /// SwiftData 对象）；发送/取消/切换线程时清除
    @State private var pendingQuote: MessageQuote?
    /// 0.4.1：长按「选择」的纯文本 sheet 载荷
    @State private var selectionPayload: SelectionPayload?
    /// 0.2.7：发送舱玻璃直接施加在行本体上，0.2.4–0.2.6 的
    /// GlassEffectContainer＋union 撤销（§11：容器在新承载
    /// 下不再承担布局，且 Session 219 忌玻璃叠玻璃）
    /// 发送舱实测高（0.3.5，§20）：由 composerRow 的
    /// onGeometryChange 在布局周期内回写，只喂玻璃圆角
    /// 的连续半径函数（ComposerLayout.cornerRadius）。
    /// 0.2.6–0.3.4 的离散形态状态 composerMultiline 已
    /// 撤销——它由 Layout 内异步回写、滞后布局一拍，是
    /// 0.3.4 真机回车重影的定因（见 §20.1）
    @State private var composerCapsuleHeight: CGFloat = 46
    /// 发送区（safeAreaBar 内容）实测总高（0.4.5）：由
    /// bottomBar 的 onGeometryChange 回写，喂底缘 E11
    /// 模糊带的带长——带底必须收在发送区底缘、不许再
    /// 向下延到导航坞下方（用户 11:47 点名，§30）
    @State private var composerBarHeight: CGFloat = 62
    // （0.3.8 删残：tabBarZone 本地副本随抽屉钉底删除——
    // 它唯一的用途是抽屉面板底部占位，第 22 条已废）

    private var currentThread: ChatThread? {
        threads.first { $0.id == currentThreadID } ?? threads.first
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
        // 0.4.1：「选择」纯文本 sheet（长按菜单发起，
        // 选型见 DESIGN-V4 §26）
        .sheet(item: $selectionPayload) { payload in
            SelectableTextSheet(text: payload.text)
        }
        // 0.4.1：引用是发送舱的临时态，切换线程即作废，
        // 不许跨线程带过去
        .onChange(of: currentThreadID) { _, _ in
            pendingQuote = nil
            // 0.4.2：流式节流闸不跨线程带账
            streamFollowGate.reset()
            // 0.4.5：当前线程回写壳层抽屉（高亮当前位
            // 与删当前线程的判定都读它，见 DrawerView）
            appState.activeThreadID = currentThread?.id
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
        }
        .background(Palette.chatSurface)
        // 0.4.3（§28）：顶栏 headerBar 已收编——不再走
        // 本容器的 .overlay 悬浮（未注册的覆盖层不在系
        // 统边缘效果体系内，WWDC25-323／Adopting
        // Liquid Glass），改挂消息列表 ScrollView 的
        // .safeAreaBar(edge: .top) 注册为系统认可的自
        // 定义 bar（见 messageList）；overlay 层随之撤
        // 销。0.4.0 删 topFade 的前置至此才真正补完
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItem,
            matching: .images
        )
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await loadPickedPhoto(item) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            loadPickedFiles(result)
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
        // 0.4.0（§3.4）：消费待续聊会话（四处入口经
        // AppState.pendingChatSessionID 置位、ContentView
        // 切聊天格，本页导入历史后进聊天续聊）
        .onChange(of: appState.pendingChatSessionID) { _, id in
            if let id {
                Task { await consumePendingChatSession(id) }
            }
        }
        .sheet(isPresented: $showSessionInfo) {
            if let serverID = currentThread?.serverSessionID {
                NavigationStack {
                    ServerSessionDetailView(sessionID: serverID)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("关闭") { showSessionInfo = false }
                            }
                        }
                }
            }
        }
        .onAppear {
            if currentThreadID == nil {
                currentThreadID = threads.first?.id
            }
            // 0.4.5：同理补消费抽屉线程选择（从其他格开
            // 抽屉选线程切过来时，本页可能尚未挂载、
            // onChange 不重放）
            if let id = appState.drawerThreadSelection {
                appState.drawerThreadSelection = nil
                currentThreadID = id
            }
            // 0.4.5：当前线程初始回写（抽屉高亮当前位）
            appState.activeThreadID = currentThread?.id
            // 本页首次出现时若已有待续聊会话（如从其他格
            // 首次切入），onChange 可能先于挂载发生、在此补消费
            if let id = appState.pendingChatSessionID {
                Task { await consumePendingChatSession(id) }
            }
        }
        .task {
            await startDemoStreamIfNeeded()
        }
        .task {
            await appState.refreshModelCatalog()
        }
        // 0.5.0（§31 合并列车接线）：点身份胶囊开智能体
        // 枢纽页——0.4.0 的临时接线（sheet 内开
        // ModelSettingsView）按审计 §5 改道至此；
        // AgentHubView 自带 NavigationStack 与关闭钮，
        // 此处不再外包
        .sheet(isPresented: $showHub) {
            AgentHubView()
        }
    }

    /// （顶部渐隐带 topFade 已于 0.4.0 删除，审计 §1.1／
    /// §6.1：自加实色渐变带是「白底上边缘模糊不可感」的
    /// 疑因之一，删后滚动边缘模糊回归系统 .scrollEdge-
    /// EffectStyle(.soft) 单独承担；顶栏收编系统通道与
    /// 玻璃换装归二期材质批）

    /// 身份状态（0.3.8 第 30 条）：胶囊状态位只报属实的
    /// 三态——未连接/唤醒中/生成中/在线，词与点同源
    private var identityStatus: (word: String, color: Color) {
        if appState.config == nil { return ("未连接", Palette.inkMuted) }
        if isWakingModel { return ("唤醒中", Palette.warning) }
        if isStreaming { return ("生成中", Palette.success) }
        return ("在线", Palette.success)
    }

    /// 顶栏（0.3.8 第 30/31 条布局，0.4.0 A 案改；0.4.3
    /// 起注册为消息列表的 .safeAreaBar(edge: .top)、脱
    /// 离悬浮覆盖，§28）：
    /// 身份胶囊一颗装头像＋Hermes＋状态＋模型（§3.3，
    /// 小模型胶囊撤除），会话名退到胶囊下方次行居中呈
    /// 现；左右圆钮走白浮纸画法。
    /// 左钮字形改汉堡线（第 31 条：与抽屉的隐喻对齐，
    /// 「分栏」图标 sidebar.left 退场）。顶栏总高约
    /// 40＋次行 18，比 0.3.7 的两行胶囊更紧凑（旧胶囊
    /// 167pt 宽纯文字、无头像无 Hermes 名——第 30 条点名）
    private var headerBar: some View {
        VStack(spacing: 6) {
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
                        .font(.system(
                            size: HeaderButtonSpec.glyphPointSize,
                            weight: .regular
                        ))
                        .foregroundStyle(Palette.ink)
                        .frame(
                            width: HeaderButtonSpec.diameter,
                            height: HeaderButtonSpec.diameter
                        )
                        .odFloatPaper(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("会话列表")

                Spacer()

                // 0.4.0 A 案（审计 §3.3，用户点选）：右侧小
                // 模型胶囊撤除，模型并入 IdentityAnchor 一
                // 颗（头像＋Hermes＋状态＋分隔＋模型名＋
                // chevron）；点整颗胶囊开智能体枢纽页
                // （0.5.0 接线，见 body 的 sheet 注释）
                Button {
                    showHub = true
                } label: {
                    IdentityAnchor(
                        name: "Hermes",
                        statusWord: identityStatus.word,
                        statusColor: identityStatus.color,
                        modelName: displayModelName,
                        modelShortName: ChatModels.shortDisplayName(
                            for: appState.chatModel
                        )
                    )
                }
                .buttonStyle(.plain)
                // 0.4.1：胶囊在顶栏 HStack 里优先保宽
                // （0.4.0 真机截图里被两侧圆钮＋Spacer
                // 挤压——组件内 ViewThatFits 三档降级是
                // 主修，此处再给整颗胶囊布局优先权）
                .layoutPriority(1)
                .accessibilityLabel("Hermes，\(identityStatus.word)，当前模型 \(displayModelName)，打开智能体枢纽页")

                Spacer()

                Button {
                    newThread()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(
                            size: HeaderButtonSpec.glyphPointSize,
                            weight: .regular
                        ))
                        .foregroundStyle(Palette.ink)
                        .frame(
                            width: HeaderButtonSpec.diameter,
                            height: HeaderButtonSpec.diameter
                        )
                        .odFloatPaper(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建会话")
            }

            // 会话名次行（第 30 条）：退居中弱行，不再占胶囊。
            // 0.4.0（§3.4）：已关联服务端会话的线程，点次行
            // 开「会话信息」（详情页降级后的次级入口）
            if let thread = currentThread, thread.serverSessionID != nil {
                Button {
                    showSessionInfo = true
                } label: {
                    HStack(spacing: 4) {
                        Text(thread.title)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Palette.inkMuted)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("会话信息")
            } else {
                Text(currentThread?.title ?? "新会话")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    /// 底部发送区（0.2.6 起由消息列表的安全区承载、不
    /// 再是覆盖层；0.2.6–0.4.2 为 .safeAreaInset，0.4.3
    /// 改 .safeAreaBar 注册，§28）：回到底部钮＋错误/提示条＋发送
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
        VStack(spacing: OneDayMetrics.spacingS) {
            if !isNearBottom && currentThread != nil {
                HStack {
                    Spacer()
                    scrollToBottomButton(proxy)
                }
                .padding(.trailing, OneDayMetrics.spacingM)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
            if let errorMessage {
                errorBanner(errorMessage)
            }
            if let notice {
                noticeBar(notice)
            }
            inputBar
        }
        .fixedSize(horizontal: false, vertical: true)
        // 0.4.5：实测高回写（喂底缘 E11 带长，见
        // composerBarHeight 与 messageList 的 safeAreaBar
        // 注）；只读高度、不参与本容器布局，无回环
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { _, height in
            composerBarHeight = height
        }
        // 条 9（§14）动画口径 0.4.2 收紧（§27）：本容
        // 器的高度就是消息列表的底部 inset——回到底部
        // 钮显隐时容器高度随之增减，列表的底部锚点骑
        // 在这个高度上。原用 microSpring（380/18、ζ≈
        // 0.46 欠阻尼、令牌册自注「微弹」）动画这段高
        // 度，过冲使锚点随弹簧来回摆——划到底抖动的
        // 一环。改走 swap（easeInOut 0.2、单调无过冲）：
        // 钮的出入观感仍在，高度只单调滑到终点；钮本
        // 体的点按反馈不经此处、不受影响。0.3.2 统一经
        // resolved 出口（Reduce Motion 时瞬时）不变
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: isNearBottom
        )
    }

    /// 回到底部圆钮（0.2.4 曾换原生玻璃；0.3.8 第 28 条
    /// 浮件统一白浮纸——圆钮全体同画法）
    private func scrollToBottomButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            scrollToBottom(proxy)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .odFloatPaper(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到底部")
    }

    // MARK: - 消息列表

    private func messageList(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                if let thread = currentThread {
                    ForEach(thread.sortedEntries) { entry in
                        bubble(entry)
                            .id(entry.id)
                    }
                }
                if let streamingText {
                    streamingRow(streamingText)
                        .id("streaming")
                }
                if currentThread == nil && !isStreaming {
                    // 空状态收敛（DESIGN-V4 §5）：小图标＋
                    // 两行字，不占大块视觉重量
                    VStack(spacing: OneDayMetrics.spacingS) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Palette.inkMuted)
                        Text("和你的 Hermes 聊聊")
                            // 0.3.3 收编：手写 fontWeight 漂移
                            // 改走 sectionTitle 角色（阶梯账
                            // 见原字重账本，已废止）
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                        Text("消息经你自己的服务器发给 Agent，记录只存这台手机。")
                            .font(.caption)
                            .foregroundStyle(Palette.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, OneDayMetrics.spacingXL)
                }
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
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
            headerBar
                // 0.4.4（§29，例外 E11）：顶缘渐进模糊
                // 层——作顶栏 background 向上溢出 60pt
                // 盖状态区、向下延出栏外约 45pt，把
                // .soft 只等于栏高的作用区放大成带；
                // 顶栏本体在层上保持锐利，background
                // 不参与布局、不接命中
                .background(alignment: .top) {
                    EdgeProgressiveBlur(stops: EdgeProgressiveBlur.chatTop)
                        .frame(height: 176)
                        .offset(y: -60)
                        .allowsHitTesting(false)
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
        .contentMargins(.bottom, OneDayMetrics.spacingS, for: .scrollContent)
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
            bottomBar(proxy)
                // 0.4.4（§29，例外 E11）＋0.4.5 收下延
                // （§30，用户 11:47 点名）：带仍作发送区
                // background、自舱上 56pt 渐入、穿舱体，
                // 但带底到此为止——0.4.4 的带固定 216pt
                // 长、向下延出发送区约 96pt 与底栏坞「衔
                // 接成一片」，构造复核实锤：那段满 alpha
                // 模糊越过发送区底缘、盖住坞身并垂到坞
                // 下方的 home indicator 区，在坞的悬浮
                // 间隙里显成独立一坨（§30 核查结论）。本
                // 版带长改「56＋发送区实测高」（composer-
                // BarHeight），带底恰与发送区底缘齐平：
                // 坞上方渐入段分毫不变、坞下方零残留；
                // 停点按绝对锚重算（见 EdgeProgressiveBlur
                // .chatBottom(bandHeight:)）；挂 bar back-
                // ground 随安全区与键盘同通道升降、back-
                // ground 不改 bar 尺寸、发送舱自量高链零
                // 影响、不接命中，均不变
                .background(alignment: .top) {
                    EdgeProgressiveBlur(stops: EdgeProgressiveBlur.chatBottom(
                        bandHeight: Double(56 + composerBarHeight)
                    ))
                    .frame(height: 56 + composerBarHeight)
                    .offset(y: -56)
                    .allowsHitTesting(false)
                }
        }
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

    /// 滚到底部锚点。animated=true 只给人发起的滚动
    /// （回到底部钮、键盘锚底）：走页面过渡曲线滑过
    /// 去；内容跟随（新条目落地、流式生长）必须
    /// animated=false 一步贴合当前底部——0.4.2 定因：
    /// 带动画的 scrollTo 追逐随内容生长不断移动的锚
    /// 点，是划到底抖动的主因（§27）
    private func scrollToBottom(
        _ proxy: ScrollViewProxy, animated: Bool = true
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

    @ViewBuilder
    private func bubble(_ entry: ChatEntry) -> some View {
        if entry.role == "user" {
            HStack {
                Spacer(minLength: OneDayMetrics.bubbleSideInset)
                VStack(alignment: .trailing, spacing: OneDayMetrics.spacingXS) {
                    if let quote = entry.quote {
                        quoteBlock(quote)
                    }
                    if let data = entry.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220)
                            .clipShape(
                                RoundedRectangle(cornerRadius: OneDayMetrics.spacingM)
                            )
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
                            .foregroundStyle(Palette.bodyInk)
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
                }
                .modifier(messageMenu(for: entry))
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
                assistantBubble {
                    MarkdownText(entry.content)
                }
            }
            .modifier(messageMenu(for: entry))
        }
    }

    /// 长按菜单的文本口径（0.4.1）：助手消息剥 Markdown
    /// 标记符号成可读文本（MessagePlainText 纯函数），
    /// 用户消息原文即纯文本
    private func plainText(for entry: ChatEntry) -> String {
        entry.role == "assistant"
            ? MessagePlainText.make(from: entry.content)
            : entry.content
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
                pendingQuote = MessageQuote(
                    role: entry.role, content: entry.content
                )
                composerFocusHandle.focus()
            },
            onSelect: {
                selectionPayload = SelectionPayload(text: text)
            }
        )
    }

    /// 已发送消息顶部的引用块（0.4.1）：小字、次级色、
    /// 左细线——只作回指，不抢正文层级；摘要与引用条
    /// 共用 MessageQuote.summary 同一口径
    private func quoteBlock(_ quote: MessageQuote) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Rectangle()
                .fill(Palette.inkMuted)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(MessageQuote.speakerName(for: quote.role))
                    // 0.4.1 第 9 修：引用块在消息流内、
                    // 其标签同守 regular 基准（旧 caption2
                    // semibold 撤销，层级靠色与字号）
                    .font(.caption2)
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
    private func streamingRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            // 0.5.1（§32）：思考先于正文到达时，折叠单
            // 元在等待泡/流式泡上方展开呈现（恒展开＋
            // 实时计时，ReasoningBlock 流式态）
            if let reasoning = streamingReasoning {
                ReasoningBlock(
                    text: reasoning,
                    seconds: nil,
                    isStreaming: true,
                    startedAt: reasoningStartedAt
                )
            }
            streamingBubble(text)
        }
    }

    @ViewBuilder
    private func streamingBubble(_ text: String) -> some View {
        if text.isEmpty {
            assistantBubble {
                if isWakingModel {
                    // Qwen 冷启唤醒中（0.3.0 接线，§15）：明示
                    // 状态，不让用户对着三个点干等
                    HStack(spacing: OneDayMetrics.spacingS) {
                        TypingDots()
                        Text("模型唤醒中，冷启动约 1–3 分钟…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, OneDayMetrics.spacingXS)
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
                }
                .accessibilityLabel("关闭")
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
                }
                .accessibilityLabel("关闭")
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
            // 0.4.1：引用条（长按「回复」发起）——出现/
            // 消失与附件条同走 SmoothExpand 平滑高度
            SmoothExpand(isExpanded: pendingQuote != nil) {
                if let pendingQuote {
                    quoteBar(pendingQuote)
                }
            }
            // 条 7（§14）：附件条的出现/消失走平滑高度
            // 动画（SmoothExpand，0fr→1fr 等价），禁跳变
            SmoothExpand(isExpanded: !attachments.isEmpty) {
                attachmentsStrip
            }
            // 表面沿革：0.2.7 裸玻璃 → 0.3.7 卡 19 撤玻璃
            // 改灰填充 → 0.3.8 第 28 条白浮纸（floatFill＋
            // 发丝边＋双环影）→ **0.4.1 回系统玻璃**（用户
            // 10:06/10:07 两点名：第 3 修「输入栏与底部导
            // 航栏颜色不一致」＋第 7 修「改 Muse 本体形
            // 态：白色大圆角卡片」）：.glassEffect(.regular)
            // 与原生底栏同为 iOS 26 Liquid Glass 家族——
            // 同材质即同观感，不再自调灰阶对色。形态要素
            // 沿既有结构：圆角连续函数封顶 24（大圆角量
            // 级）、＋在卡内左下、发送圆形键在卡内右下、
            // 多行上文下钮（ComposerBarLayout，0.3.4 定
            // 版）；自量高＋硬封顶（例外 E1）结构不动。
            // 白浮纸的发丝边与双环手搓影一并撤销（玻璃自
            // 带边缘折光与层级，§14 条 2 的影口径随材质
            // 换代退役）
            composerRow
                // 第 1 修（P0 键盘不弹）的聚焦保底层：整卡
                // 背景命中域内点按（文本区外的卡面空隙）经
                // 焦点句柄聚焦文本视图。根因与定位见
                // DESIGN-V4 §26.7：焦点机器代码 0.3.8→
                // 0.4.0 逐字未动（diff 实证），回归随底栏
                // 可见化同批出现——文本视图自身触摸成为单
                // 点故障，本层把「点输入栏必弹键盘」改成
                // 双通道构造（文本视图直触＋卡面点按），
                // 不再依赖单一路径的环境状态
                .background {
                    Color.clear
                        .contentShape(composerShape)
                        .onTapGesture {
                            composerFocusHandle.focus()
                        }
                }
                .glassEffect(.regular, in: composerShape)
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingS)
        // 提议链断环（0.2.5 根因注，§9）：本 VStack 的高度
        // 只认内容，不许把外层提议透传给胶囊
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 引用条（0.4.1，照 Muse 样板「正在回复＋摘要」）：
    /// 左细线＋两行（正在回复 X／摘要一行截断）＋右端
    /// ✕ 取消。发送后由 send() 清除、点 ✕ 即时清除、
    /// 切换线程经 onChange 清除（见 body）
    private func quoteBar(_ quote: MessageQuote) -> some View {
        HStack(alignment: .center, spacing: OneDayMetrics.spacingS) {
            Rectangle()
                .fill(Palette.inkMuted)
                .frame(width: 2, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.role == "user"
                    ? "正在回复我的消息"
                    : "正在回复 \(MessageQuote.speakerName(for: quote.role))")
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
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消引用")
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(
            Palette.fieldFill,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
        )
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
    private var composerRow: some View {
        ComposerBarLayout {
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
        // 实测高在布局周期内回写（0.3.5，§20）：只喂玻
        // 璃圆角的连续半径（见 composerShape），高度本
        // 身不经任何动画——形态切换一帧落定。0.2.6–
        // 0.3.4 的离散形状动画（.animation(value:
        // composerMultiline)＋异步形态状态）已整条撤
        // 销：回车跨行时布局先落多行几何、形状隔一拍
        // 才跟，旧 Capsule 被拉成体育场形盖住新几何再
        // 跳成圆角矩形——录屏里的双层重影（定因 §20.1）
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { _, newHeight in
            if abs(newHeight - composerCapsuleHeight) > 0.5 {
                composerCapsuleHeight = newHeight
            }
        }
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
            multiline: ComposerLayout.isMultiline(measured: narrowTextH),
            totalHeight: ComposerLayout.capsuleHeight(
                narrowMeasured: narrowTextH, fullMeasured: fullTextH
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
    /// - 流式中：停止键（逻辑沿用 sendTask?.cancel()）
    /// - 有可发送内容（文字或附件）：发送箭头
    /// - 空输入：裸麦克风符号占位（无圆盘底、无描边）
    @ViewBuilder
    private var trailingControl: some View {
        if isStreaming || canSend {
            sendStopButton
        } else {
            micButton
        }
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
                sendTask?.cancel()
            } else {
                send()
            }
        } label: {
            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: isStreaming ? 12 : 13, weight: .bold))
                .foregroundStyle(Palette.onPrimary)
                .frame(
                    width: ComposerLayout.buttonHeight,
                    height: ComposerLayout.buttonHeight
                )
                .background(Palette.primaryFill, in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(isStreaming ? "停止生成" : "发送")
    }

    /// （旧发送/停止两键已合并为 sendStopButton 变形键，见上。）

    /// 语音占位（0.2.5）：裸麦克风符号——无圆盘底、无描边，
    /// 与 Muse 空输入态的右端形态一致。语音输入尚未接入，
    /// 点按无动作，仅占形态位；接入时在此挂起录音流程
    private var micButton: some View {
        Button {
            // 语音输入未接入：占位符号，点按无动作
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
        .accessibilityLabel("语音输入（尚未开放）")
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
                showFileImporter = true
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

    /// 待发附件条：图片出缩略图、文件出名牌，都可单独移除
    private var attachmentsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OneDayMetrics.spacingS) {
                ForEach(attachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingXS)
            .padding(.vertical, OneDayMetrics.spacingXS)
        }
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
            case .file(let name, _):
                HStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "doc")
                        .foregroundStyle(Palette.inkSecondary)
                    Text(name)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .frame(maxWidth: 140)
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .frame(height: 54)
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
            }
            .offset(x: 5, y: -5)
            .accessibilityLabel("移除附件")
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

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            appendImage(data)
        }
    }

    private func loadPickedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: url) else {
                notice = "读取「\(url.lastPathComponent)」失败，未加入待发列表。"
                continue
            }
            // 待发上限 20MB：超限只报不收，不静默截断
            guard data.count <= 20 * 1024 * 1024 else {
                notice = "「\(url.lastPathComponent)」超过 20MB，未加入待发列表。"
                continue
            }
            attachments.append(
                PendingAttachment(kind: .file(name: url.lastPathComponent, data: data))
            )
        }
    }

    // （会话抽屉本体已于 0.4.5 迁至 DrawerView.swift、
    // 承载提到壳层 ContentView，见 DESIGN-V4 §30；
    // 本页只经 AppState 通道与抽屉互通）

    // MARK: - 发送

    private func ensureThread() -> ChatThread {
        if let currentThread {
            return currentThread
        }
        let thread = ChatThread()
        modelContext.insert(thread)
        currentThreadID = thread.id
        return thread
    }

    private func newThread() {
        let thread = ChatThread()
        modelContext.insert(thread)
        try? modelContext.save()
        currentThreadID = thread.id
    }

    // MARK: - 服务端会话续聊（0.4.0，审计 §3.4）

    /// 消费待续聊 id：先清 AppState 再导入（防 onChange
    /// 与 onAppear 双通道重复消费同一条）
    private func consumePendingChatSession(_ id: String) async {
        guard appState.pendingChatSessionID == id else { return }
        appState.pendingChatSessionID = nil
        await openServerSession(id)
    }

    /// 打开服务端会话续聊：已有 serverSessionID 关联线
    /// 程直接切换（不重复导入）；否则拉元信息＋消息历
    /// 史导入新线程（过滤口径在 SessionHistoryImport：
    /// 只取 user/assistant 有正文者，工具/系统消息不进
    /// 线程、不进上下文重放）。
    /// R1 未验证项（明记）：续聊发送维持现有无状态上下
    /// 文重放链（/v1/chat/completions 不带服务端会话
    /// id）——续聊回合是否回写同一条服务端会话记录未
    /// 经实测（红线：不许对生产 Hermes 发写请求验证），
    /// 等用户点头后另行受控实测；App 内续聊体验不依赖
    /// 该结论，服务端可能另起新会话记录。
    private func openServerSession(_ id: String) async {
        if let existing = threads.first(where: { $0.serverSessionID == id }) {
            currentThreadID = existing.id
            return
        }
        guard importingSessionID == nil else { return }
        importingSessionID = id
        defer { importingSessionID = nil }
        do {
            let session = try? await appState.performAdmin { client, config in
                try await client.serverSession(config: config, id: id)
            }
            let messages = try await appState.performAdmin { client, config in
                try await client.sessionMessages(config: config, id: id)
            }
            let entries = SessionHistoryImport.importableEntries(
                from: messages
            )
            let thread = ChatThread(
                title: SessionHistoryImport.threadTitle(
                    session: session, entries: entries
                )
            )
            thread.serverSessionID = id
            if let started = session?.startedDate {
                thread.createdAt = started
            }
            thread.updatedAt = session?.endedDate
                ?? session?.startedDate ?? Date()
            modelContext.insert(thread)
            for entry in entries {
                let chatEntry = ChatEntry(
                    role: entry.role, content: entry.content, thread: thread
                )
                if let date = entry.date {
                    chatEntry.createdAt = date
                }
                modelContext.insert(chatEntry)
            }
            try? modelContext.save()
            currentThreadID = thread.id
        } catch {
            errorMessage = (error as? HermesError)?.userMessage
                ?? "会话导入失败，请稍后再试。"
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
        // （流完成 .success / 失败 .warning，见 runStream）
        input = ""
        attachments = []
        pendingQuote = nil
        errorMessage = nil
        notice = nil
        let thread = ensureThread()
        let imageDatas = pending.compactMap(\.imageData)
        let fileNames = pending.compactMap(\.fileName)
        modelContext.insert(
            ChatEntry(
                role: "user", content: text, thread: thread,
                imageData: imageDatas.first, quote: quote
            )
        )
        if thread.title == "新会话" {
            thread.title = text.isEmpty ? "图片消息" : String(text.prefix(20))
        }
        thread.updatedAt = Date()
        try? modelContext.save()
        // 0.4.1：上下文组装走 MessageQuote.outgoingContent
        // ——带引用的消息（含本轮新消息与历史回放）把引
        // 用块拼进 content，引用在每轮重放里持续在场；
        // 无引用的消息原样（纯函数保证）
        var context = thread.sortedEntries.suffix(20).map {
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
        // 文件直发：/api/chat/file-upload 在 openapi 里有端点，
        // 但其回执与 /v1 消息的拼装契约未经实测（红线：不对
        // 生产发写请求验证），本版只做选择与待发列表，发送时
        // 如实说明未随条发送，不静默丢弃
        if !fileNames.isEmpty {
            notice = "文件直发尚未开放：\(fileNames.joined(separator: "、")) 未随本条发送。"
        }
        streamingText = ""
        sendTask = Task {
            await runStream(thread: thread, messages: context)
        }
    }

    /// 演示模式：种子对话的最后一句用户消息由假客户端流式回完，
    /// 演示态能看到「半截回复＋流式光标」的流式效果。正常模式
    /// 直接返回，零影响。
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
        let context = thread.sortedEntries.suffix(20).map {
            ChatMessage(role: $0.role, content: $0.content)
        }
        streamingText = ""
        await runStream(thread: thread, messages: context)
    }

    private func runStream(thread: ChatThread, messages: [ChatMessage]) async {
        guard let config = appState.config, let apiKey = appState.apiKey else {
            streamingText = nil
            streamingReasoning = nil
            reasoningStartedAt = nil
            errorMessage = HermesError.sessionExpired.userMessage
            // 结果触感（0.3.2 纪律）：发送失败 .warning
            Haptics.warning()
            return
        }
        // 0.5.1（§32）：发布合并——SSE 增量先过发布闸
        // （OneDayCore.StreamPublishGate）攒缓冲，按
        // 80ms 窗／64 字阈值合并后才写 @State，下游
        // StreamingText 不再逐增量整串重分词。本轮两闸
        // 与思考计时先归零；精确全文恒由闸的 fullText
        // 记账（已发布＋待发布），落盘走它、节流不丢字
        contentPublishGate.reset()
        reasoningPublishGate.reset()
        streamingReasoning = nil
        reasoningStartedAt = nil
        var reasoningEndedAt: Date?
        var retried = false
        var failed = false
        // 发布巡查 ticker：窗口到期把攒着的增量推给视图
        // ——低速流的尾巴增量靠它到期，不必等下一个增
        // 量到达；40ms 一查（半窗粒度），runStream 退
        // 出即取消
        let publishTicker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                if Task.isCancelled { break }
                let now = ProcessInfo.processInfo.systemUptime
                if let snapshot = contentPublishGate.collectDue(at: now) {
                    streamingText = snapshot
                }
                if let snapshot = reasoningPublishGate.collectDue(at: now) {
                    streamingReasoning = snapshot
                }
            }
        }
        defer { publishTicker.cancel() }
        while true {
            do {
                let stream = appState.client.chatStream(
                    config: config, apiKey: apiKey,
                    model: appState.chatModel, messages: messages
                )
                for try await event in stream {
                    let now = ProcessInfo.processInfo.systemUptime
                    switch event {
                    case .content(let delta):
                        // 首个正文增量到达＝思考计时终点
                        if reasoningStartedAt != nil, reasoningEndedAt == nil {
                            reasoningEndedAt = Date()
                        }
                        if let snapshot = contentPublishGate.offer(delta, at: now) {
                            streamingText = snapshot
                        }
                    case .reasoning(let delta):
                        if reasoningStartedAt == nil {
                            reasoningStartedAt = Date()
                        }
                        if let snapshot = reasoningPublishGate.offer(delta, at: now) {
                            streamingReasoning = snapshot
                        }
                    }
                }
                break
            } catch {
                // Qwen 冷启唤醒重试（0.3.0 接线，DESIGN-V4
                // §15）：自部署模型休眠后首请求常在网关冷启
                // 期失败（冷启竞速实测口径）——尚未产出任何
                // 字时自动重试一次并亮唤醒提示；已产出则照
                // 常收尾不重发（防重复内容）；用户停止不重试
                var shouldRetry = false
                if !contentPublishGate.hasContent,
                   !reasoningPublishGate.hasContent, !retried,
                   appState.chatModel == ChatModels.coldStartID {
                    if let hermesError = error as? HermesError {
                        if case .cancelled = hermesError {
                            shouldRetry = false
                        } else {
                            shouldRetry = true
                        }
                    } else {
                        shouldRetry = true
                    }
                }
                if shouldRetry {
                    retried = true
                    isWakingModel = true
                    continue
                }
                // 停止生成（cancelled）不报错：已生成的半截照常落盘
                if let hermesError = error as? HermesError {
                    if case .cancelled = hermesError {
                        // 用户主动停止，静默收尾（不算失败、无触感）
                    } else {
                        errorMessage = hermesError.userMessage
                        failed = true
                    }
                } else {
                    errorMessage = "发送失败，请稍后再试。"
                    failed = true
                }
                break
            }
        }
        // 收尾 flush：残余增量精确发布（不多不少），流结
        // 束/取消同路；落盘随后以条目变化接管最后一贴
        let flushNow = ProcessInfo.processInfo.systemUptime
        if let snapshot = contentPublishGate.flush(at: flushNow) {
            streamingText = snapshot
        }
        if let snapshot = reasoningPublishGate.flush(at: flushNow) {
            streamingReasoning = snapshot
        }
        isWakingModel = false
        let accumulated = contentPublishGate.fullText
        let reasoningText = reasoningPublishGate.fullText
        // 思考耗时（落盘口径）：首个思考增量→首个正文
        // 增量，未产正文时到流结束；无思考为 nil
        var reasoningSeconds: Double?
        if let started = reasoningStartedAt {
            let ended = reasoningEndedAt ?? Date()
            reasoningSeconds = (ended.timeIntervalSince(started) * 10)
                .rounded() / 10
        }
        if !accumulated.isEmpty {
            modelContext.insert(
                ChatEntry(
                    role: "assistant", content: accumulated, thread: thread,
                    reasoning: reasoningText.isEmpty ? nil : reasoningText,
                    reasoningSeconds: reasoningText.isEmpty ? nil : reasoningSeconds
                )
            )
            thread.updatedAt = Date()
            try? modelContext.save()
        }
        // 结果触感（0.3.2 纪律，只挂结果事件）：失败
        // .warning；回复完整落地 .success；用户主动停止
        // 且无内容时不给触感
        if failed {
            Haptics.warning()
        } else if !accumulated.isEmpty {
            Haptics.success()
        }
        streamingText = nil
        streamingReasoning = nil
        reasoningStartedAt = nil
        sendTask = nil
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
    let onSelect: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                Button(action: onReply) {
                    Label("回复", systemImage: MessageActionSymbols.reply)
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
            HStack(spacing: 5) {
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
