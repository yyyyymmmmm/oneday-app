import OneDayDesign
import OneDayCore
import SwiftData
import SwiftUI

/// 聊天页：本地会话（SwiftData）＋ /v1/chat/completions 流式。
/// 上下文取当前会话最近 20 条；停止生成保留已生成的半截回复。
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
                LazyVStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                    if let thread = currentThread {
                        ForEach(thread.sortedEntries) { entry in
                            bubble(entry)
                                .id(entry.id)
                        }
                    }
                    if let streamingText {
                        streamingBubble(streamingText)
                            .id("streaming")
                    }
                    if currentThread == nil && !isStreaming {
                        emptyState
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(OneDayMetrics.spacingM)
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

    private func bubble(_ entry: ChatEntry) -> some View {
        HStack {
            if entry.role == "user" {
                Spacer(minLength: OneDayMetrics.spacingXL)
            }
            Group {
                if entry.role == "user" {
                    Text(entry.content)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, OneDayMetrics.spacingSM)
                        .padding(.vertical, OneDayMetrics.spacingS)
                        .background(
                            Palette.primaryTint,
                            in: RoundedRectangle(
                                cornerRadius: OneDayMetrics.cardCorner
                            )
                        )
                } else {
                    MarkdownText(entry.content)
                        .padding(.horizontal, OneDayMetrics.spacingSM)
                        .padding(.vertical, OneDayMetrics.spacingS)
                        .background(
                            Palette.surface,
                            in: RoundedRectangle(
                                cornerRadius: OneDayMetrics.cardCorner
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OneDayMetrics.cardCorner)
                                .strokeBorder(Palette.line, lineWidth: 1)
                        )
                }
            }
            if entry.role != "user" {
                Spacer(minLength: OneDayMetrics.spacingXL)
            }
        }
    }

    private func streamingBubble(_ text: String) -> some View {
        HStack {
            Group {
                if text.isEmpty {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在思考…")
                            .font(.callout)
                            .foregroundStyle(Palette.sub)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingSM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                } else {
                    MarkdownText(text)
                        .padding(.horizontal, OneDayMetrics.spacingSM)
                        .padding(.vertical, OneDayMetrics.spacingS)
                }
            }
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.cardCorner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OneDayMetrics.cardCorner)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
            Spacer(minLength: OneDayMetrics.spacingXL)
        }
    }

    private var emptyState: some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(Palette.primary)
            Text("和你的 Hermes 聊聊")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("消息经你自己的服务器发给 Agent，记录只存这台手机。")
                .font(.footnote)
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, OneDayMetrics.spacingXL)
    }

    // MARK: - 输入与错误

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.footnote)
            Spacer()
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
        }
        .foregroundStyle(Palette.danger)
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(Palette.surface)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: OneDayMetrics.spacingS) {
            TextField("发消息…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .padding(.vertical, OneDayMetrics.spacingS)
                .background(
                    Palette.surface,
                    in: RoundedRectangle(cornerRadius: OneDayMetrics.cardCorner)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OneDayMetrics.cardCorner)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
            Button {
                if isStreaming {
                    sendTask?.cancel()
                } else {
                    send()
                }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.body.weight(.bold))
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
            }
            .odGlassButton(.tinted)
            .disabled(!isStreaming && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(isStreaming ? "停止生成" : "发送")
        }
        .padding(OneDayMetrics.spacingSM)
        .background(Palette.surface)
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thread.title)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text("\(thread.entries.count) 条 · \(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(Palette.sub)
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
