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
    /// 抽屉底部服务器行点按 → 切到设置格（ContentView 注入）
    var onOpenSettings: () -> Void = {}
    /// 抽屉服务端会话行点按 → 设置格智能体组的会话详情
    var onOpenServerSession: (String) -> Void = { _ in }

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]

    @State private var currentThreadID: UUID?
    @State private var input = ""
    /// 非 nil 表示正在生成：值是已累积的流式文本
    @State private var streamingText: String?
    /// Qwen 冷启唤醒重试中（0.3.0 接线，§15）：等待行亮
    /// 「模型唤醒中」提示
    @State private var isWakingModel = false
    @State private var sendTask: Task<Void, Never>?
    @State private var errorMessage: String?
    /// 0.2.1：非错误提示（如文件附件未发送说明），可关闭
    @State private var notice: String?
    /// 抽屉开合与抽屉内搜索词
    @State private var drawerOpen = false
    @State private var drawerQuery = ""
    /// 抽屉跟手拖拽的实时位移（0.2.2 动效专项：拖动跟随、
    /// 松手按预测位移弹簧归位，不再只判阈值瞬移）
    @State private var drawerDrag: CGFloat = 0
    /// 消息区是否贴近底部：决定自动跟随滚动与「回到底部」钮
    @State private var isNearBottom = true
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
    @State private var showModelPicker = false
    /// 抽屉身份块与服务端会话组的数据（开抽屉时拉取）
    @State private var drawerStatus: ServerStatus?
    @State private var drawerServerSessions: [ServerSession] = []
    /// 0.2.7：发送舱玻璃直接施加在行本体上，0.2.4–0.2.6 的
    /// GlassEffectContainer＋union 撤销（§11：容器在新承载
    /// 下不再承担布局，且 Session 219 忌玻璃叠玻璃）
    /// 0.2.6 多行形状变形（0.3.3 起判据由 ComposerBar-
    /// Layout 的窄宽量测经 onModeChange 回写，见
    /// composerRow）：跨过单行阈值后发送舱玻璃由
    /// Capsule 改固定圆角矩形（见 inputBar）
    @State private var composerMultiline = false
    /// 原生底栏在屏幕底部的占位，抽屉面板底部按它留位避让
    /// 服务器行（0.2.6 起发送舱已不在覆盖层、不再用它抬升；
    /// 0.3.2 数值收进 OneDayMetrics.tabBarZone 具名令牌）
    private let tabBarZone = OneDayMetrics.tabBarZone

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
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                chatSurface
                drawerOverlay(
                    width: min(
                        geo.size.width * OneDayMetrics.drawerWidthFraction,
                        OneDayMetrics.drawerMaxWidth
                    )
                )
            }
        }
    }

    // MARK: - 主面（0.2.6 承载换代：发送区回到布局流）

    /// 聊天主面：顶栏仍是悬浮覆盖层（玻璃三件套＋渐隐带，
    /// 见 topFade）；底部发送区 0.2.6 起退出覆盖层、回到
    /// 布局流——消息列表加 .safeAreaInset(edge: .bottom)
    /// 承载发送舱（见 messageList）。换代原因：0.2.4/0.2.5
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
    /// 内容、不是布局机制）。
    /// 原 NavigationStack＋toolbar 在 0.2.4 已撤销：栈内无
    /// 任何 push 依赖（全仓核查），顶栏以悬浮覆盖层实现。
    private var chatSurface: some View {
        ScrollViewReader { proxy in
            messageList(proxy)
        }
        .background(Palette.pageBG)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                topFade
                headerBar
            }
        }
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
        .onChange(of: drawerOpen) { _, open in
            if open {
                Task { await loadDrawerData() }
            }
        }
        .onAppear {
            if currentThreadID == nil {
                currentThreadID = threads.first?.id
            }
        }
        .task {
            await startDemoStreamIfNeeded()
        }
        .task {
            await appState.refreshModelCatalog()
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet()
                .presentationDetents([.medium])
        }
    }

    /// 顶部渐隐带（0.2.6，对照 Muse 顶栏背后的磨砂渐隐）：
    /// 一层自上而下的 pageBG 渐变，只作淡出遮罩——不做实色
    /// 顶栏、不带分界线。系统 .scrollEdgeEffectStyle(.soft)
    /// 在白底上单独不可感（0.2.5 已挂、真机仍见文字清晰撞
    /// 到胶囊周围），故由这层带子承担实际淡出。几何按诊断
    /// 图实测点位定（iPhone 17：忽略顶部安全区后带子覆盖
    /// 物理 0–128pt；顶栏胶囊占约 68–115pt，静止时首条消息
    /// 起于约 138pt）：渐变 0–90% 全不透明——文字滚到胶囊/
    /// 角钮一线（≤115pt）之前已完全淡出；90%–100% 在 13pt
    /// 内降到全透明，带尾止于 128pt、不触静止首条消息。
    /// 不吃手势。
    private var topFade: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.pageBG, location: 0),
                .init(color: Palette.pageBG, location: 0.9),
                .init(color: Palette.pageBG.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 128)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    /// 悬浮顶栏：左右系统玻璃角钮＋居中标题/模型胶囊，浮在
    /// 内容之上、无底色、无分界线，内容可滚到角钮背后。
    /// 角钮用系统 .glass 按钮样式＋.buttonBorderShape
    /// (.circle)，不再自绘 glassEffect 圆（0.2.3 的权宜件）。
    /// 0.2.5：中心由裸文字改悬浮玻璃胶囊（对照 Muse 顶端
    /// 中央的身份胶囊）——0.2.4 的裸文字悬浮时，正文上滚会
    /// 直接从标题文字里穿过、字撞字（用户真机截图实证）；
    /// 收进胶囊后标题自带玻璃底，撞色问题根除。整颗胶囊
    /// 可点（开模型选择器，与此前只有模型行可点的口径一致
    /// 地扩大命中区）。
    private var headerBar: some View {
        HStack(alignment: .center, spacing: OneDayMetrics.spacingS) {
            Button {
                setDrawer(true)
            } label: {
                Image(systemName: "sidebar.left")
                    // 0.3.3：顶栏两钮共用 HeaderButtonSpec
                    // 规格（直径 40／字形 20，与右钮同值，
                    // 单测钉住；此前两处各写 36/15）
                    .font(.system(
                        size: HeaderButtonSpec.glyphPointSize,
                        weight: .semibold
                    ))
                    .foregroundStyle(Palette.ink)
                    .frame(
                        width: HeaderButtonSpec.diameter,
                        height: HeaderButtonSpec.diameter
                    )
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("会话列表")

            Spacer()

            Button {
                showModelPicker = true
            } label: {
                VStack(spacing: 1) {
                    Text(currentThread?.title ?? "聊天")
                        // 0.3.3：胶囊标题走 capsuleTitle 角色
                        // （字重阶梯：标题位 semibold）
                        .font(TypeScale.capsuleTitle)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Text(displayModelName)
                            .font(TypeScale.caption)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.horizontal, OneDayMetrics.spacingSM + 2)
                .padding(.vertical, 6)
                // 0.2.6 缺陷 B：胶囊贴合内容（两行文字自然宽
                // ＋内边距），上限由 240 收至 200，与左右角钮
                // 留出明确间隙（0.2.5 真机实测约占屏宽 65%）
                .frame(maxWidth: 200)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换模型")

            Spacer()

            Button {
                newThread()
            } label: {
                Image(systemName: "square.and.pencil")
                    // 0.3.3：与左钮同一份 HeaderButtonSpec
                    .font(.system(
                        size: HeaderButtonSpec.glyphPointSize,
                        weight: .semibold
                    ))
                    .foregroundStyle(Palette.ink)
                    .frame(
                        width: HeaderButtonSpec.diameter,
                        height: HeaderButtonSpec.diameter
                    )
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("新建会话")
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    /// 底部发送区（0.2.6 起由消息列表的 .safeAreaInset
    /// 承载，不再是覆盖层）：回到底部钮＋错误/提示条＋发送
    /// 舱，自下而上排在列表下方的安全区留位里。键盘收起时
    /// 留位贴原生底栏上方；键盘升起时系统安全区扩张、整段
    /// 被顶到键盘上方（系统通道，见 chatSurface 换代注）。
    /// 高度只认内容：本 VStack 与发送舱各环保留 fixedSize
    /// 断环（0.2.5），在布局流里是双保险。
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
        // 条 9（§14）：回到底部钮的出入是小动作类，动画走
        // 定版 microSpring（380/18 微弹）；0.3.2 统一经
        // resolved 出口（Reduce Motion 时瞬时）
        .animation(
            MotionTokens.resolved(
                MotionTokens.microSpring, reduceMotion: reduceMotion
            ),
            value: isNearBottom
        )
    }

    /// 回到底部：系统 .glass 圆钮（0.2.4 换原生玻璃，撤掉
    /// 此前的实色底＋自绘阴影浮钮）
    private func scrollToBottomButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            scrollToBottom(proxy)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
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
                            // 见 TextRoleWeights）
                            .font(TypeScale.sectionTitle)
                            .foregroundStyle(Palette.ink)
                        Text("消息经你自己的服务器发给 Agent，记录只存这台手机。")
                            .font(TypeScale.caption)
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
            .onTapGesture {
                // 0.2.8：收键盘经焦点句柄直达文本视图本体
                //（resignFirstResponder），不写任何 SwiftUI
                // 焦点状态；失焦事实由 delegate 回调回写
                composerFocusHandle.dismiss()
            }
        }
        // 滚动边距：顶为悬浮顶栏让出首屏位置（滚动时内容
        // 从其背后穿过、经 topFade 渐隐带淡出）；底只留与
        // 发送舱的小间隙——发送区本体已由下方 safeAreaInset
        // 留位（0.2.6），不再按悬浮层实测高度给边距。
        // .scrollEdgeEffectStyle(.soft) 保留，与渐隐带并用
        // （白底上单独不可感、带子承担实际淡出，见 topFade）
        .contentMargins(.top, 64, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .contentMargins(.bottom, OneDayMetrics.spacingS, for: .scrollContent)
        // 0.2.6 承载换代核心：发送区进列表的底部安全区
        // 留位——Exyte/Stream 式「列表＋发送区同处布局流」
        // （DESIGN-V4 §10）。键盘避让自此走系统安全区通道：
        // 键盘升起留位随安全区顶到键盘上方、交互收起跟随，
        // 发送舱高度只由内容决定（高度口径归 Composer-
        // Layout/ComposerTextMetrics 纯逻辑＋单测把守，§13）
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(proxy)
        }
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height - geometry.contentOffset.y
                - geometry.containerSize.height < 140
        } action: { _, nearBottom in
            isNearBottom = nearBottom
        }
        // 「点空白收键盘」手势在内容栈上（见 messageList 内注），
        // 不挂 ScrollView 本体——其命中域含发送舱 inset
        .onChange(of: currentThread?.sortedEntries.count) { _, _ in
            // 用户已上翻看历史时不强拉回底（0.2.2 交互专项）
            if isNearBottom {
                scrollToBottom(proxy)
            }
        }
        .onChange(of: streamingText) { _, _ in
            if isNearBottom {
                scrollToBottom(proxy)
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.pageCrossfade, reduceMotion: reduceMotion
            )
        ) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    @ViewBuilder
    private func bubble(_ entry: ChatEntry) -> some View {
        if entry.role == "user" {
            HStack {
                Spacer(minLength: OneDayMetrics.bubbleSideInset)
                VStack(alignment: .trailing, spacing: OneDayMetrics.spacingXS) {
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
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, OneDayMetrics.bubblePaddingH)
                            .padding(.vertical, OneDayMetrics.bubblePaddingV)
                            .background(
                                Palette.primaryTint,
                                in: RoundedRectangle(cornerRadius: OneDayMetrics.bubbleCorner)
                            )
                    }
                }
            }
        } else {
            assistantBubble {
                MarkdownText(entry.content)
            }
        }
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
        if text.isEmpty {
            assistantBubble {
                if isWakingModel {
                    // Qwen 冷启唤醒中（0.3.0 接线，§15）：明示
                    // 状态，不让用户对着三个点干等
                    HStack(spacing: OneDayMetrics.spacingS) {
                        TypingDots()
                        Text("模型唤醒中，冷启动约 1–3 分钟…")
                            .font(TypeScale.footnote)
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
                    .font(TypeScale.subhead)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button {
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
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
                    .font(TypeScale.subhead)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                Button {
                    notice = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
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
    /// 形状变形保留：单行 Capsule、多行 RoundedRectangle(24,
    /// continuous)，判据＝文本实测高跨过单行阈值。
    private var composerShape: AnyShape {
        composerMultiline
            ? AnyShape(RoundedRectangle(
                cornerRadius: OneDayMetrics.composerCorner, style: .continuous
            ))
            : AnyShape(Capsule())
    }

    private var inputBar: some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            // 条 7（§14）：附件条的出现/消失走平滑高度
            // 动画（SmoothExpand，0fr→1fr 等价），禁跳变
            SmoothExpand(isExpanded: !attachments.isEmpty) {
                attachmentsStrip
            }
            // 0.2.7：玻璃裸施加在行本体——GlassEffectContainer
            // 与 union 已撤销（§10 承载换代后容器不再承担
            // 布局，裸施加即可，§11）
            // 0.3.2：材质与染色改走 Mat 令牌入口（学礼记
            // AdvisorView 输入栏：Mat.tinted＋主题染色）——
            // 玻璃以品牌浅染轻染，不再裸用系统 .regular
            composerRow
                .odGlassSurface(.tinted, in: composerShape)
                // 条 2（§14）：聚焦禁描边——聚焦态不加任何
                // stroke，改以加深的双环阴影表达（近环定界
                // 半径 6、远环扩散半径 18），随焦点观察态
                // 切换；静止态只留极淡的浮起影。影基色走
                // Palette.shadowBase 令牌（0.3.2 收编）
                .shadow(
                    color: Palette.shadowBase
                        .opacity(composerFocused ? 0.13 : 0.05),
                    radius: composerFocused ? 6 : 10, y: 2
                )
                .shadow(
                    color: Palette.shadowBase
                        .opacity(composerFocused ? 0.10 : 0.04),
                    radius: composerFocused ? 18 : 14, y: 6
                )
                .animation(
                    MotionTokens.resolved(
                        MotionTokens.swap, reduceMotion: reduceMotion
                    ),
                    value: composerFocused
                )
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingS)
        // 提议链断环（0.2.5 根因注，§9）：本 VStack 的高度
        // 只认内容，不许把外层提议透传给胶囊
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 发送舱内容（0.3.3 上文下钮，DESIGN-V4 §18）：自研
    /// Layout 排三件子视图（＋键／文本／右端状态机）——
    /// 单行形态与旧 HStack 几何逐项等价（总高 46、两键
    /// 夹文字、全部底对齐，0.2.8 定版尺寸不动）；多行形
    /// 态文字区全宽在上随行生长、按钮行钉在胶囊底部行
    /// （学 Muse/ChatGPT 本体与 Exyte/Stream Composer
    /// 的成熟结构）。形态判据恒以窄宽量测为准、经
    /// Layout 缓存回写 composerMultiline（只驱动玻璃形
    /// 状与 swap 动画）；Layout 保持子视图身份，形态切
    /// 换不重建 UITextView、焦点不丢。高度全走
    /// ComposerLayout.capsuleHeight(narrow:full:) 纯函数
    private var composerRow: some View {
        ComposerBarLayout(
            onModeChange: { newValue in
                if composerMultiline != newValue {
                    composerMultiline = newValue
                }
            }
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
                }
            )
            trailingControl
        }
        .fixedSize(horizontal: false, vertical: true)
        // 0.2.6 形状随行数变形（对照 Muse 多行态）：
        // 单行 Capsule、多行固定圆角矩形——Capsule
        // 拉长成体育场形大气球是用户点名「内容多了
        // 为什么变这样」的形状根源；玻璃本体由
        // inputBar 施加，形状定义在 composerShape。
        // 0.3.2：0.18 内联曲线收编 MotionTokens.swap
        // 并经 resolved 出口（审查 M-3＋动效纪律）
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: composerMultiline
        )
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
/// capsuleHeight(narrow:full:)；形态经缓存＋主队列异
/// 步回写 onModeChange（不在布局中改状态）；Layout 保
/// 持子视图身份，切换不重建 UITextView、焦点不丢
private struct ComposerBarLayout: Layout {
    var onModeChange: (Bool) -> Void

    final class Cache {
        var mode: Bool?
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

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
        cache: inout Cache
    ) -> CGSize {
        let rowWidth = proposal.width ?? 0
        let m = metrics(rowWidth: rowWidth, subviews: subviews)
        if cache.mode != m.multiline {
            cache.mode = m.multiline
            let callback = onModeChange
            let mode = m.multiline
            DispatchQueue.main.async { callback(mode) }
        }
        return CGSize(width: rowWidth, height: m.totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
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
                .font(.system(size: 16, weight: .regular))
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
                .font(.system(size: 16, weight: .regular))
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
                        .font(TypeScale.callout)
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
                .odElevation(Elevation.floating)
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

    // MARK: - 会话抽屉（0.1.3，定版 §7）

    /// 开合统一走条 9 定版拖拽弹簧（dragSpring：stiffness
    /// 1200 / damping 80、零回弹，0.3.0 §14——抽屉属拖拽类
    /// 交互），Reduce Motion 时瞬时。0.3.2 起抽屉吸附不再
    /// 挂触觉（触感只挂结果事件，见 Haptics 注）。
    private func setDrawer(_ open: Bool) {
        withAnimation(
            MotionTokens.resolved(MotionTokens.dragSpring, reduceMotion: reduceMotion)
        ) {
            drawerOpen = open
            drawerDrag = 0
        }
        appState.drawerPresented = open
    }

    /// 抽屉拖拽（开/合共用）：跟手实时位移，松手按预测位移
    /// （含速度）决定开合，弹簧归位由 setDrawer 承接。横向分量
    /// 必须大于纵向才接管，避免与面板内纵向滚动打架。
    private func drawerDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    drawerDrag = value.translation.width
                }
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width
                if drawerOpen {
                    setDrawer(projected > -width * 0.3)
                } else {
                    setDrawer(projected > width * 0.3)
                }
            }
    }

    /// 抽屉覆盖层：scrim（全开 0.4 黑）＋面板（宽 82%、上限
    /// 340）＋左缘唤出手势层。面板盖住聊天主面与悬浮顶栏；
    /// 原生底栏属系统层级、浮于抽屉之上（0.2.4 起服从系统
    /// 默认），面板底部以 tabBarZone 留位避让服务器行。
    @ViewBuilder
    private func drawerOverlay(width: CGFloat) -> some View {
        // 跟手偏移：基准位（开 0 / 合 -width-8）＋拖拽量（按方向钳制）
        let base = drawerOpen ? 0 : -width - 8
        let clampedDrag = drawerOpen
            ? min(max(drawerDrag, -width), 0)
            : min(max(drawerDrag, 0), width)
        let offsetX = base + clampedDrag
        // scrim 透明度随开合进度走，拖动时不跳变
        let progress = 1 - min(max(-offsetX, 0), width) / width
        // 遮罩走 Palette.scrim（§14 条 1 四层阶梯的层 4，
        // 墨色推导、不用纯黑），透明度随开合进度走
        Palette.scrim
            .opacity(progress)
            .allowsHitTesting(drawerOpen)
            .onTapGesture { setDrawer(false) }
        drawerPanel(width: width)
            .offset(x: offsetX)
            .gesture(drawerDragGesture(width: width))
        if !drawerOpen {
            // 左缘热区：右滑跟手唤出，不挡正文纵向滚动
            // （宽度走 OneDayMetrics.drawerEdgeZone 令牌）
            Color.clear
                .frame(width: OneDayMetrics.drawerEdgeZone)
                .contentShape(Rectangle())
                .gesture(drawerDragGesture(width: width))
        }
    }

    private func drawerPanel(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            drawerIdentity
            drawerSearchField
            drawerNewChatRow
            ScrollView {
                drawerList
            }
            .scrollDismissesKeyboard(.interactively)
            drawerServerRow
            // 0.2.4：原生底栏按系统层级浮于抽屉之上，面板
            // 底部留出底栏占位，服务器行不被玻璃栏遮挡
            Color.clear
                .frame(height: tabBarZone)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Palette.surface)
    }

    /// 顶部身份块（0.2.1 仿 Muse 侧边栏）：Hermes 名＋在线
    /// 状态点＋当前状态与模型小字
    private var drawerIdentity: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text("Hermes")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                StatusDot(
                    color: drawerStatus.map { Palette.stateColor($0.gatewayState) }
                        ?? Palette.success
                )
            }
            Text("\(drawerStateWord) · \(displayModelName)")
                .font(TypeScale.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.top, OneDayMetrics.spacingM)
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    private var drawerStateWord: String {
        switch drawerStatus?.gatewayState?.lowercased() {
        case "stopped": return "已停止"
        case "error", "failed": return "异常"
        default: return "运行中"
        }
    }

    private func loadDrawerData() async {
        if let loaded = try? await appState.performAdmin({ client, config in
            try await client.status(config: config)
        }) {
            drawerStatus = loaded
        }
        if let page = try? await appState.performAdmin({ client, config in
            try await client.serverSessions(config: config, limit: 6)
        }) {
            drawerServerSessions = page.sessions
        }
    }

    private var drawerSearchField: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true)
            TextField("搜索会话", text: $drawerQuery)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            if !drawerQuery.isEmpty {
                Button {
                    drawerQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.inkMuted)
                }
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .frame(minHeight: OneDayMetrics.minTapTarget)
        .background(
            Palette.fieldFill,
            in: Capsule()
        )
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.top, OneDayMetrics.spacingM)
    }

    private var drawerNewChatRow: some View {
        Button {
            newThread()
            setDrawer(false)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "square.and.pencil")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 30, alignment: .leading)
                    // 条 5 补落点（0.3.2，审查 #5）：图标与
                    // 文字同行走光学偏移
                    .iconOpticalOffset()
                    .accessibilityHidden(true)
                Text("新建会话")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, OneDayMetrics.spacingS)
    }

    private var filteredThreads: [ChatThread] {
        let query = drawerQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return threads }
        return threads.filter { thread in
            thread.title.localizedCaseInsensitiveContains(query)
                || thread.entries.contains {
                    $0.content.localizedCaseInsensitiveContains(query)
                }
        }
    }

    /// 本机会话按时间分组（0.2.1 仿 Muse 侧边栏）：今天／
    /// 昨天／更早；搜索时收成单组「搜索结果」。服务端会话
    /// 单列一组在下方（点行直达设置里的会话详情），拉不到
    /// 时回落一行去向说明。
    private var drawerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(threadGroups, id: \.label) { group in
                SectionLabel(group.label)
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.top, OneDayMetrics.spacingL)
                    .padding(.bottom, OneDayMetrics.spacingS)
                ForEach(group.threads) { thread in
                    drawerThreadRow(thread)
                }
            }
            if filteredThreads.isEmpty {
                Text(drawerQuery.isEmpty ? "暂无会话" : "没有匹配的会话")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.top, OneDayMetrics.spacingL)
            }
            SectionLabel("服务端会话")
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.top, OneDayMetrics.spacingL)
                .padding(.bottom, OneDayMetrics.spacingS)
            if drawerServerSessions.isEmpty {
                Text("在「设置 · 智能体 · 服务端会话」里查看与管理")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.horizontal, OneDayMetrics.spacingM)
            } else {
                ForEach(drawerServerSessions) { session in
                    drawerServerSessionRow(session)
                }
            }
        }
        .padding(.bottom, OneDayMetrics.spacingL)
    }

    /// 本机会话的时间分组（按 updatedAt 的自然日）
    private var threadGroups: [(label: String, threads: [ChatThread])] {
        let all = filteredThreads
        guard drawerQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            return all.isEmpty ? [] : [("搜索结果", all)]
        }
        let calendar = Calendar.current
        var today: [ChatThread] = []
        var yesterday: [ChatThread] = []
        var earlier: [ChatThread] = []
        for thread in all {
            if calendar.isDateInToday(thread.updatedAt) {
                today.append(thread)
            } else if calendar.isDateInYesterday(thread.updatedAt) {
                yesterday.append(thread)
            } else {
                earlier.append(thread)
            }
        }
        return [("今天", today), ("昨天", yesterday), ("更早", earlier)]
            .filter { !$0.threads.isEmpty }
    }

    private func drawerServerSessionRow(_ session: ServerSession) -> some View {
        Button {
            setDrawer(false)
            onOpenServerSession(session.id)
        } label: {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(session.title)
                    .font(TypeScale.callout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("\(session.messageCount ?? 0) 条 · \(AdminFormat.short(session.startedDate))")
                    .font(TypeScale.monoCaption)
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(
                maxWidth: .infinity,
                minHeight: 50,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingS)
    }

    /// 抽屉会话行的时间口径：固定中文短格式（11月8日 13:43），
    /// 不随系统语言漂移——首轮截图里系统英文格式
    ///（Nov 8, 2026 at 1:43 PM）混在中文行里读感破碎。
    private static let threadDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static func threadDateText(_ date: Date) -> String {
        threadDateFormatter.string(from: date)
    }

    /// 会话行（0.2.2 规格对齐 DESIGN-V3-NOTES §3/§6）：双行
    /// 最小高 50、标题 callout 常规字重；选中态＝浅灰填充＋
    /// 标题 semibold（近单色纪律，不用品牌色填充）
    private func drawerThreadRow(_ thread: ChatThread) -> some View {
        let isCurrent = thread.id == currentThread?.id
        return Button {
            currentThreadID = thread.id
            setDrawer(false)
        } label: {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(thread.title)
                    .font(TypeScale.callout)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("\(thread.entries.count) 条 · \(Self.threadDateText(thread.updatedAt))")
                    .font(TypeScale.monoCaption)
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(
                maxWidth: .infinity,
                minHeight: 50,
                alignment: .leading
            )
            .background(
                isCurrent ? Palette.fieldFill : Color.clear,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.fieldCorner)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingS)
        .contextMenu {
            Button(role: .destructive) {
                deleteThread(thread)
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        }
    }

    /// 底部固定服务器行：两家参照的「底部账号行」在 OneDay 的
    /// 对应物——状态点＋服务器名＋当前模型，点按去设置页。
    private var drawerServerRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
            Button {
                setDrawer(false)
                onOpenSettings()
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    StatusDot(color: Palette.success)
                    Text(appState.config?.host ?? "未连接")
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: OneDayMetrics.spacingXS)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("服务器设置")
        }
    }

    private func deleteThread(_ thread: ChatThread) {
        // 0.3.2：删除确认不再挂触觉（只挂结果事件，见 Haptics 注）
        if thread.id == currentThreadID {
            currentThreadID = nil
        }
        modelContext.delete(thread)
        try? modelContext.save()
    }

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

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = attachments
        guard !isStreaming, !text.isEmpty || !pending.isEmpty else { return }
        // 0.3.2：发送起手不再挂触觉——触感挪到结果点
        // （流完成 .success / 失败 .warning，见 runStream）
        input = ""
        attachments = []
        errorMessage = nil
        notice = nil
        let thread = ensureThread()
        let imageDatas = pending.compactMap(\.imageData)
        let fileNames = pending.compactMap(\.fileName)
        modelContext.insert(
            ChatEntry(
                role: "user", content: text, thread: thread,
                imageData: imageDatas.first
            )
        )
        if thread.title == "新会话" {
            thread.title = text.isEmpty ? "图片消息" : String(text.prefix(20))
        }
        thread.updatedAt = Date()
        try? modelContext.save()
        var context = thread.sortedEntries.suffix(20).map {
            ChatMessage(role: $0.role, content: $0.content)
        }
        // 本条若带图：最后一条用户消息改多模态 parts 编码
        // （图片走 OpenAI image_url + data: base64；服务端/模型
        // 不支持时错误经 errorBanner 如实呈现，不假装发过）
        if !imageDatas.isEmpty, let last = context.last, last.role == "user" {
            let urls = imageDatas.map {
                "data:image/jpeg;base64,\($0.base64EncodedString())"
            }
            context[context.count - 1] = ChatMessage(
                role: "user", text: text, imageDataURLs: urls
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
            errorMessage = HermesError.sessionExpired.userMessage
            // 结果触感（0.3.2 纪律）：发送失败 .warning
            Haptics.warning()
            return
        }
        var accumulated = ""
        var retried = false
        var failed = false
        while true {
            do {
                let stream = appState.client.chatStream(
                    config: config, apiKey: apiKey,
                    model: appState.chatModel, messages: messages
                )
                for try await delta in stream {
                    accumulated += delta
                    streamingText = accumulated
                }
                break
            } catch {
                // Qwen 冷启唤醒重试（0.3.0 接线，DESIGN-V4
                // §15）：自部署模型休眠后首请求常在网关冷启
                // 期失败（冷启竞速实测口径）——尚未产出任何
                // 字时自动重试一次并亮唤醒提示；已产出则照
                // 常收尾不重发（防重复内容）；用户停止不重试
                var shouldRetry = false
                if accumulated.isEmpty, !retried,
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
        isWakingModel = false
        if !accumulated.isEmpty {
            modelContext.insert(
                ChatEntry(role: "assistant", content: accumulated, thread: thread)
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
        sendTask = nil
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


/// 模型选择器（0.3.0 接线，DESIGN-V4 §15）：列表是
/// App 内写死三项（ChatModels：DeepSeek Flash / V4 Pro
/// / 自部署 Qwen3-30B），点选只写本地选择——逐请求生
/// 效（请求带 provider=custom 切上游），不改服务端默
/// 认、不发任何请求。0.2.4 的服务端目录拼装＋改默认
/// 口径就此撤销（理由见 ChatModels 文件头）。
private struct ModelPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(ChatModels.items.enumerated()),
                            id: \.element.id
                        ) { index, item in
                            if index > 0 {
                                GroupDivider(inset: OneDayMetrics.spacingM)
                            }
                            modelRow(item)
                        }
                    }
                    .odGroup()
                    Text("选择只保存在这台手机上，下一条消息立即生效；不会修改服务端默认模型。Qwen3-30B 是自部署模型，休眠后第一次提问会自动唤醒（约 1–3 分钟）。")
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        .padding(.top, OneDayMetrics.spacingM)
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func modelRow(_ item: ChatModels.Item) -> some View {
        let isCurrent = item.id == appState.chatModel
        return Button {
            appState.selectChatModel(item.id)
            dismiss()
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(item.note)
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.primary)
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
