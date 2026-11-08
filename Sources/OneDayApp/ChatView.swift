import OneDayDesign
import OneDayCore
import SwiftData
import SwiftUI

/// 聊天页：本地会话（SwiftData）＋ /v1/chat/completions 流式。
/// 上下文取当前会话最近 20 条；停止生成保留已生成的半截回复。
/// v2 视觉（docs/DESIGN-V2.md §3.5）：助手回答裸排在底色上（学
/// ChatGPT/Claude 的共识）、用户是浅染气泡、输入区是浮空胶囊，
/// 流式光标是本页的签名细节、也是全页唯一的蓝色时刻之一。
/// 0.1.3 导航（§7）：会话历史改左侧抽屉（顶栏左键＋左缘手势
/// 唤出），顶栏中 = 会话名＋模型名副题，右 = 新建会话。
struct ChatView: View {
    /// 抽屉底部服务器行点按 → 切到设置格（ContentView 注入）
    var onOpenSettings: () -> Void = {}

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]

    @State private var currentThreadID: UUID?
    @State private var input = ""
    /// 非 nil 表示正在生成：值是已累积的流式文本
    @State private var streamingText: String?
    @State private var sendTask: Task<Void, Never>?
    @State private var errorMessage: String?
    /// 抽屉开合与抽屉内搜索词
    @State private var drawerOpen = false
    @State private var drawerQuery = ""
    /// 演示模式自动开流只跑一次（截图环截流式帧用）
    @State private var demoStreamStarted = false

    private var currentThread: ChatThread? {
        threads.first { $0.id == currentThreadID } ?? threads.first
    }

    private var isStreaming: Bool { streamingText != nil }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                NavigationStack {
                    VStack(spacing: 0) {
                        messageList
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                        inputBar
                    }
                    .background(Palette.pageBG)
                    .navigationTitle(currentThread?.title ?? "聊天")
                    .navigationSubtitle(appState.modelID)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                setDrawer(true)
                            } label: {
                                Image(systemName: "sidebar.left")
                            }
                            .accessibilityLabel("会话列表")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                newThread()
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .accessibilityLabel("新建会话")
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
                }
                drawerOverlay(width: min(geo.size.width * 0.82, 340))
            }
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
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
                        EmptyState(
                            icon: "bubble.left.and.bubble.right",
                            title: "和你的 Hermes 聊聊",
                            message: "消息经你自己的服务器发给 Agent，记录只存这台手机。"
                        )
                        .padding(.top, OneDayMetrics.spacingXXL)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingS)
            }
            .onChange(of: currentThread?.sortedEntries.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: streamingText) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(MotionTokens.pageCrossfade) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    @ViewBuilder
    private func bubble(_ entry: ChatEntry) -> some View {
        if entry.role == "user" {
            HStack {
                Spacer(minLength: 44)
                Text(entry.content)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Palette.primaryTint,
                        in: RoundedRectangle(cornerRadius: OneDayMetrics.bubbleCorner)
                    )
            }
        } else {
            MarkdownText(entry.content)
        }
    }

    @ViewBuilder
    private func streamingRow(_ text: String) -> some View {
        if text.isEmpty {
            TypingDots()
                .padding(.vertical, OneDayMetrics.spacingXS)
        } else {
            HStack(alignment: .bottom, spacing: OneDayMetrics.spacingS) {
                MarkdownText(text)
                StreamingCaret()
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

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: OneDayMetrics.spacingS) {
            TextField("发消息…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.vertical, OneDayMetrics.spacingSM)
                .background(
                    Palette.surface,
                    in: RoundedRectangle(cornerRadius: OneDayMetrics.composerCorner)
                )
                .odElevation(Elevation.floating)
            Button {
                if isStreaming {
                    sendTask?.cancel()
                } else {
                    send()
                }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
            }
            .odGlassButton(.tinted)
            .disabled(!isStreaming && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(isStreaming ? "停止生成" : "发送")
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    // MARK: - 会话抽屉（0.1.3，定版 §7）

    /// 开合统一走定版弹簧（indicator），Reduce Motion 时瞬时。
    private func setDrawer(_ open: Bool) {
        withAnimation(
            MotionTokens.resolved(MotionTokens.indicator, reduceMotion: reduceMotion)
        ) {
            drawerOpen = open
        }
    }

    /// 抽屉覆盖层：scrim（全开 0.4 黑）＋面板（宽 82%、上限
    /// 340）＋左缘唤出手势层。面板盖住导航栏、止于标签栏之上
    /// （标签栏属 ContentView，抽屉不越界盖它）。
    @ViewBuilder
    private func drawerOverlay(width: CGFloat) -> some View {
        Color.black
            .opacity(drawerOpen ? 0.4 : 0)
            .allowsHitTesting(drawerOpen)
            .onTapGesture { setDrawer(false) }
        drawerPanel(width: width)
            .offset(x: drawerOpen ? 0 : -width - 8)
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        if value.translation.width < -48 {
                            setDrawer(false)
                        }
                    }
            )
        if !drawerOpen {
            // 左缘 24pt 热区：右滑唤出，不挡正文纵向滚动
            Color.clear
                .frame(width: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 16)
                        .onEnded { value in
                            if value.translation.width > 48 {
                                setDrawer(true)
                            }
                        }
                )
        }
    }

    private func drawerPanel(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            drawerSearchField
            drawerNewChatRow
            ScrollView {
                drawerList
            }
            drawerServerRow
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Palette.surface)
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
            in: RoundedRectangle(cornerRadius: OneDayMetrics.fieldCorner)
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
                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                    .accessibilityHidden(true)
                Text("新建会话")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
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

    /// 分段口径（框架定版）：先按来源分段——本机会话是里程碑 1
    /// 的真实数据（最近更新在前）；服务端会话待里程碑 2 接
    /// /api/sessions 后点亮，先以安静文字占位，不伪造列表。
    private var drawerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("本机会话")
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.top, OneDayMetrics.spacingL)
                .padding(.bottom, OneDayMetrics.spacingS)
            if filteredThreads.isEmpty {
                Text(drawerQuery.isEmpty ? "暂无会话" : "没有匹配的会话")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.horizontal, OneDayMetrics.spacingM)
            }
            ForEach(filteredThreads) { thread in
                drawerThreadRow(thread)
            }
            SectionLabel("服务端会话")
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.top, OneDayMetrics.spacingL)
                .padding(.bottom, OneDayMetrics.spacingS)
            Text("将在里程碑 2 接入后列在这里")
                .font(TypeScale.footnote)
                .foregroundStyle(Palette.inkMuted)
                .padding(.horizontal, OneDayMetrics.spacingM)
        }
        .padding(.bottom, OneDayMetrics.spacingL)
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

    /// 会话行：与旧历史行同信息量（标题＋条数＋时间），当前会话
    /// 以一级面差衬底（学两家参照的选中行填充，不用蓝色）。
    private func drawerThreadRow(_ thread: ChatThread) -> some View {
        let isCurrent = thread.id == currentThread?.id
        return Button {
            currentThreadID = thread.id
            setDrawer(false)
        } label: {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(thread.title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("\(thread.entries.count) 条 · \(Self.threadDateText(thread.updatedAt))")
                    .font(TypeScale.monoFootnote)
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, OneDayMetrics.spacingSM)
            .frame(
                maxWidth: .infinity,
                minHeight: OneDayMetrics.rowHeight,
                alignment: .leading
            )
            .background(
                isCurrent ? Palette.fieldFill : Color.clear,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.fieldCorner)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                HStack(spacing: OneDayMetrics.spacingXS) {
                    StatusDot(color: Palette.success)
                    Text(appState.config?.host ?? "未连接")
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: OneDayMetrics.spacingXS)
                    Text(appState.modelID)
                        .font(TypeScale.monoCaption)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
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
        guard !text.isEmpty, !isStreaming else { return }
        input = ""
        errorMessage = nil
        let thread = ensureThread()
        modelContext.insert(ChatEntry(role: "user", content: text, thread: thread))
        if thread.title == "新会话" {
            thread.title = String(text.prefix(20))
        }
        thread.updatedAt = Date()
        try? modelContext.save()
        let context = thread.sortedEntries.suffix(20).map {
            ChatMessage(role: $0.role, content: $0.content)
        }
        streamingText = ""
        sendTask = Task {
            await runStream(thread: thread, messages: context)
        }
    }

    /// 演示模式：种子对话的最后一句用户消息由假客户端流式回完，
    /// 让截图环能截到「半截回复＋流式光标」的静止帧。正常模式
    /// 直接返回，零影响。
    private func startDemoStreamIfNeeded() async {
        guard DemoMode.current.isDemo, !demoStreamStarted,
              let thread = currentThread else {
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
            return
        }
        var accumulated = ""
        do {
            let stream = appState.client.chatStream(
                config: config, apiKey: apiKey,
                model: appState.modelID, messages: messages
            )
            for try await delta in stream {
                accumulated += delta
                streamingText = accumulated
            }
        } catch {
            // 停止生成（cancelled）不报错：已生成的半截照常落盘
            if let hermesError = error as? HermesError {
                if case .cancelled = hermesError {
                    // 用户主动停止，静默收尾
                } else {
                    errorMessage = hermesError.userMessage
                }
            } else {
                errorMessage = "发送失败，请稍后再试。"
            }
        }
        if !accumulated.isEmpty {
            modelContext.insert(
                ChatEntry(role: "assistant", content: accumulated, thread: thread)
            )
            thread.updatedAt = Date()
            try? modelContext.save()
        }
        streamingText = nil
        sendTask = nil
    }
}

/// 三点指示：未出字时的等待信号（安静的弱色圆点错峰，
/// Reduce Motion 时静止）。不进气泡、不配卡片。
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

/// 流式光标：文末的 accent 小块，0.9 秒阶梯闪烁——它是「正在
/// 生成」的活信号，也是聊天页的签名细节。Reduce Motion 时静止。
private struct StreamingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.45)) { context in
            let on = reduceMotion
                || Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.primary)
                .frame(width: 7, height: 16)
                .opacity(on ? 1 : 0.15)
        }
        .accessibilityHidden(true)
    }
}
