import SwiftUI
import OneDayCore
import OneDayDesign
import UniformTypeIdentifiers

/// 聊天面（棒 1，详情区）：消息流＋流式泡＋未读分
/// 隔＋查找条＋输入区（附件队列/模型钮/发送停止）。
/// 滚动跟随口径（Telegram Mac 形态）：贴底时新内容
/// 自动跟随，用户上滑后停跟、显「回到底部」钮。
struct MacChatView: View {
    @Environment(SessionStore.self) private var session
    @Bindable var conversation: MacConversationStore
    var listStore: MacSessionListStore

    @State private var findVisible = false
    @State private var modelPickerVisible = false
    @State private var atBottom = true
    @State private var composerHeight: CGFloat = 44
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if findVisible { findBar }
            messageScroll
            if !conversation.failedSends.isEmpty { failedBar }
            if let error = conversation.sendError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            composer
        }
        .background(Palette.chatBackground)
        .toolbar { toolbarItems }
        .onDrop(of: [.fileURL, .image, .png, .jpeg], isTargeted: nil) {
            providers in
            MacFileIntake.readProviders(providers) { items in
                for item in items {
                    conversation.addAttachment(
                        fileName: item.fileName, data: item.data
                    )
                }
            }
            return true
        }
    }

    // MARK: - 工具栏（标题＋模型选择 #17）

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(conversation.sessionTitle)
                .font(.headline)
                .lineLimit(1)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                modelPickerVisible.toggle()
            } label: {
                Label(
                    conversation.selectedModel ?? "模型",
                    systemImage: "cpu"
                )
            }
            .help("选择模型（⌘M）")
            .popover(isPresented: $modelPickerVisible) {
                modelPicker
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("") {
                modelPickerVisible.toggle()
            }
            .keyboardShortcut("m", modifiers: .command)
            .hidden()
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                findVisible.toggle()
                if findVisible { findFocused = true }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("聊天内查找（⌘F）")
            .keyboardShortcut("f", modifiers: .command)
        }
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("模型")
                .font(.headline)
                .padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(session.availableModels, id: \.self) {
                        model in
                        Button {
                            conversation.selectModel(
                                model, from: session
                            )
                            modelPickerVisible = false
                        } label: {
                            HStack {
                                Text(model)
                                    .lineLimit(1)
                                Spacer()
                                if model == conversation.selectedModel {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 300)
    }

    // MARK: - 查找条（#24）

    private var findBar: some View {
        HStack(spacing: 8) {
            TextField(
                "在对话中查找",
                text: $conversation.findQuery
            )
            .textFieldStyle(.roundedBorder)
            .focused($findFocused)
            .onChange(of: conversation.findQuery) {
                conversation.recomputeFind()
            }
            .onSubmit { conversation.findNext() }
            Text(conversation.findStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44)
            Button {
                conversation.findPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(conversation.findMatchIDs.isEmpty)
            Button {
                conversation.findNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(conversation.findMatchIDs.isEmpty)
            Button {
                findVisible = false
                conversation.findQuery = ""
                conversation.recomputeFind()
            } label: {
                Image(systemName: "xmark")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Palette.surface)
    }

    // MARK: - 消息流（#13/#30）

    private var messageScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(conversation.messages, id: \.id) { message in
                        let stub = conversation.stubIDs[message.id]
                        VStack(alignment: .leading, spacing: 14) {
                            if stub != nil,
                               stub == conversation.unreadAnchorStubID {
                                MacUnreadDividerView()
                            }
                            MacMessageRow(
                                message: message,
                                isFindCurrent: stub != nil
                                    && stub == conversation
                                        .findCurrentStubID,
                                isFindMatch: stub.map {
                                    conversation.findMatchIDs
                                        .contains($0)
                                } ?? false
                            )
                        }
                        .id(stub ?? UUID())
                    }
                    if conversation.isGenerating {
                        streamingBubble
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("mac-chat-bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom {
                    Button {
                        scrollToBottom(proxy)
                    } label: {
                        Image(systemName: "chevron.down")
                            .padding(8)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .padding(12)
                }
            }
            .onChange(of: conversation.messages.count) {
                if atBottom { scrollToBottom(proxy) }
            }
            .onChange(of: conversation.streamingText) {
                if atBottom { scrollToBottom(proxy) }
            }
            .onChange(of: conversation.findCurrentStubID) {
                if let stub = conversation.findCurrentStubID {
                    withAnimation {
                        proxy.scrollTo(stub, anchor: .center)
                    }
                }
            }
            .onChange(of: conversation.sessionID) {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("mac-chat-bottom", anchor: .bottom)
    }

    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(
                Array(conversation.streamingToolNotes.enumerated()),
                id: \.offset
            ) { _, note in
                Label(note, systemImage: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if conversation.streamingText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(
                        conversation.isStopping
                            ? "正在停止…" : "正在思考…"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else {
                MacMarkdownView(text: conversation.streamingText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 发件箱（#31）

    private var failedBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(conversation.failedSends) { failed in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("发送失败：\(failed.lastError)")
                        .font(.caption)
                        .lineLimit(1)
                    Text(failed.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("重发") {
                        conversation.retry(
                            failed, from: session,
                            listStore: listStore
                        )
                    }
                    .font(.caption)
                    Button("删除") {
                        conversation.discard(failed)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.06))
    }

    // MARK: - 输入区（#15/#16）

    private var composer: some View {
        VStack(spacing: 8) {
            if !conversation.pendingAttachments.isEmpty {
                attachmentChips
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    for item in MacFileIntake.pickFiles() {
                        conversation.addAttachment(
                            fileName: item.fileName, data: item.data
                        )
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("添加附件")
                ZStack(alignment: .topLeading) {
                    if conversation.draftText.isEmpty {
                        Text("发消息…（Return 发送，⇧Return 换行）")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    MacComposerView(
                        text: $conversation.draftText,
                        onSend: {
                            conversation.send(
                                from: session, listStore: listStore
                            )
                        },
                        onPasteAttachments: { items in
                            for item in items {
                                conversation.addAttachment(
                                    fileName: item.fileName,
                                    data: item.data
                                )
                            }
                        }
                    )
                    .frame(height: composerHeight)
                }
                .background(
                    Palette.fieldFill,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .onChange(of: conversation.draftText) {
                    let lines = conversation.draftText
                        .components(separatedBy: "\n").count
                    composerHeight = min(
                        120, max(44, CGFloat(lines) * 20 + 22)
                    )
                    conversation.saveDraft()
                }
                if conversation.isGenerating {
                    Button {
                        conversation.stop(from: session)
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .help("停止生成（⌘.）")
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button {
                        conversation.send(
                            from: session, listStore: listStore
                        )
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!conversation.canSend)
                    .help("发送")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(conversation.pendingAttachments) { item in
                    HStack(spacing: 6) {
                        Image(
                            systemName: item.isImage
                                ? "photo" : "doc"
                        )
                        Text(item.fileName)
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            conversation.removeAttachment(item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Palette.surface,
                        in: Capsule()
                    )
                }
            }
        }
    }
}
