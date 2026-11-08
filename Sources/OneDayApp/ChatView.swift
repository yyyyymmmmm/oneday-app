import OneDayDesign
import OneDayCore
import SwiftData
import SwiftUI

/// 聊天页：本地会话（SwiftData）＋ /v1/chat/completions 流式。
/// 上下文取当前会话最近 20 条；停止生成保留已生成的半截回复。
/// v2 视觉（docs/DESIGN-V2.md §3.5）：助手回答裸排在底色上（学
/// ChatGPT/Claude 的共识）、用户是浅染气泡、输入区是浮空胶囊，
/// 流式光标是本页的签名细节、也是全页唯一的蓝色时刻之一。
struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]

    @State private var currentThreadID: UUID?
    @State private var input = ""
    /// 非 nil 表示正在生成：值是已累积的流式文本
    @State private var streamingText: String?
    @State private var sendTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showHistory = false

    private var currentThread: ChatThread? {
        threads.first { $0.id == currentThreadID } ?? threads.first
    }

    private var isStreaming: Bool { streamingText != nil }

    var body: some View {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("历史会话")
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
            .sheet(isPresented: $showHistory) {
                historySheet
            }
            .onAppear {
                if currentThreadID == nil {
                    currentThreadID = threads.first?.id
                }
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

    // MARK: - 历史会话

    private var historySheet: some View {
        NavigationStack {
            List {
                ForEach(threads) { thread in
                    Button {
                        currentThreadID = thread.id
                        showHistory = false
                    } label: {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                            Text(thread.title)
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            HStack(spacing: OneDayMetrics.spacingS) {
                                Text("\(thread.entries.count) 条")
                                    .font(TypeScale.monoFootnote)
                                Text(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(TypeScale.caption)
                            }
                            .foregroundStyle(Palette.inkMuted)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let thread = threads[index]
                        if thread.id == currentThreadID {
                            currentThreadID = nil
                        }
                        modelContext.delete(thread)
                    }
                    try? modelContext.save()
                }
            }
            .navigationTitle("历史会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showHistory = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
