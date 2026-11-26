import Foundation
import Observation
import OneDayCore

/// 待发附件（棒 1，对位 #16）：图片走多模态尾条、
/// 文件走托管上传＋@file 引用（契约 FileSend-
/// Assembly 同口径），发送前都只在本地排队
struct MacPendingAttachment: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let data: Data
    let isImage: Bool
}

/// 发件箱一条（棒 1，对位 #31）：提交段真失败才入
/// 箱（结果未知不入箱、不自动重发——0.31.0 铁律）；
/// 重发沿用同一幂等键，服务端同键重演不双跑。记账
/// 走 Core OutboxRetryRecord 同形字段
struct MacFailedSend: Identifiable, Sendable {
    let id: String  // 幂等键
    let sessionID: String
    let text: String
    let imageDataURLs: [String]
    let fileNames: [String]
    var attempts: Int
    var lastError: String
    var manualOnly: Bool
}

/// 会话店（棒 1）：一个打开中的会话的全部状态——
/// 消息流（#13）、流式生成与停止（#14，runs 通道）、
/// 草稿（#15，Core DraftSavePolicy 口径）、附件
/// （#16）、模型（#17）、聊天内查找（#24，Core
/// ChatFind）、未读分隔（#30，Core UnreadDivider）、
/// 发送失败重发（#31）。transcript 以服务端为唯一
/// 真源：本地只留流式半截与回显，落定一律回读。
@MainActor
@Observable
final class MacConversationStore {
    private(set) var sessionID: String?
    private(set) var sessionTitle = ""
    private(set) var messages: [SessionMessage] = []
    private(set) var isLoadingMessages = false
    var loadError: String?

    // 流式（#14）
    private(set) var isGenerating = false
    private(set) var isStopping = false
    private(set) var streamingText = ""
    private(set) var streamingToolNotes: [String] = []
    private var activeRunID: String?
    private var runTask: Task<Void, Never>?
    private var sawTerminal = false

    // 输入与附件（#15/#16/#17）
    var draftText = ""
    var pendingAttachments: [MacPendingAttachment] = []
    /// 动态引用（#34/§208）：发送舱临时态——永不进草
    /// 稿落盘、切线程作废、发送后随消息拼装落盘（Core
    /// FeedPostQuote.outgoingContent 收口），与 iOS 同口径
    var pendingFeedQuote: FeedPostQuote?
    var selectedModel: String?
    var sendError: String?

    // 发件箱（#31）
    private(set) var failedSends: [MacFailedSend] = []

    // 查找（#24）：消息行 stub 映射（Core ChatFind/
    // UnreadDivider 以 UUID 寻址，服务端行 id 为
    // Double，店内建稳定映射）
    private(set) var stubIDs: [Double: UUID] = [:]
    var findQuery = ""
    private(set) var findMatchIDs: [UUID] = []
    private(set) var findCurrentIndex = 0
    var findCurrentStubID: UUID? {
        guard findMatchIDs.indices.contains(findCurrentIndex)
        else { return nil }
        return findMatchIDs[findCurrentIndex]
    }

    // 未读分隔（#30）
    private(set) var unreadAnchorStubID: UUID?
    private let watermarkKey = "mac.readWatermark.v1"
    private let draftsKey = "mac.drafts.v1"

    // 选项卡（mac-09，对位 #21）：复用 Core OptionsCardOverlay 单源
    private let optionsOverlay = OptionsCardOverlay()
    private var threadUUIDs: [String: UUID] = [:]
    private(set) var optionsRevision = 0

    // 表情反应（mac-09，对位 #22）：按服务端行 id 存乐观/回执镜像
    private(set) var reactionOverrides: [Double: [MessageReaction]] = [:]

    private func threadUUID(for sessionID: String) -> UUID {
        if let existing = threadUUIDs[sessionID] { return existing }
        let created = UUID()
        threadUUIDs[sessionID] = created
        return created
    }

    // MARK: - 打开/切换会话

    func open(
        _ target: ServerSession, from session: SessionStore,
        listStore: MacSessionListStore
    ) async {
        saveDraft()
        cancelRunObservation()
        sessionID = target.id
        sessionTitle = MacSessionListStore.titleText(for: target)
        selectedModel = target.model ?? session.modelID
        draftText = loadDraft(for: target.id)
        pendingAttachments = []
        pendingFeedQuote = nil
        sendError = nil
        findQuery = ""
        findMatchIDs = []
        await reload(from: session, listStore: listStore)
    }

    /// 回读 transcript 落定：拉最新一页、建 stub 映
    /// 射、算未读分隔锚（用水位线，算完即把水位推
    /// 到尾行——本次打开见到的都算已读，下次打开
    /// 只对新行画线）
    func reload(
        from session: SessionStore, listStore: MacSessionListStore
    ) async {
        guard let sessionID, let config = session.config,
              let key = session.apiKey else { return }
        isLoadingMessages = true
        loadError = nil
        do {
            let fetched = try await session.chatClient.sessionMessages(
                config: config, apiKey: key, id: sessionID
            )
            messages = fetched.filter { $0.displayKind != "hidden" }
            reactionOverrides = [:]
            seedOptionsCardIfNeeded(sessionID: sessionID, session: session)
            rebuildStubs()
            computeUnreadAnchor(sessionID: sessionID)
            if let last = messages.last {
                saveWatermark(sessionID: sessionID, rowID: last.id)
            }
            listStore.markRead(
                sessionID: sessionID, messageCount: fetched.count
            )
            recomputeFind()
        } catch let error as HermesError {
            loadError = error.userMessage
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingMessages = false
    }

    private func rebuildStubs() {
        var map: [Double: UUID] = [:]
        for message in messages where map[message.id] == nil {
            map[message.id] = stubIDs[message.id] ?? UUID()
        }
        stubIDs = map
    }

    private func stubEntries() -> [UnreadDivider.EntryStub] {
        messages.map { message in
            UnreadDivider.EntryStub(
                id: stubIDs[message.id] ?? UUID(),
                role: message.role,
                createdAt: message.date ?? .distantPast,
                isToolCard: message.role == "tool"
                    || !message.toolCalls.isEmpty
            )
        }
    }

    private func computeUnreadAnchor(sessionID: String) {
        let stored = UserDefaults.standard.dictionary(
            forKey: watermarkKey
        ) as? [String: Double] ?? [:]
        guard let rowID = stored[sessionID] else {
            unreadAnchorStubID = nil
            return
        }
        let watermark = UnreadDivider.Watermark(
            entryID: stubIDs[rowID],
            date: messages.first { $0.id == rowID }?.date
                ?? .distantPast
        )
        unreadAnchorStubID = UnreadDivider.anchorEntryID(
            entries: stubEntries(), watermark: watermark
        )
    }

    private func saveWatermark(sessionID: String, rowID: Double) {
        var stored = UserDefaults.standard.dictionary(
            forKey: watermarkKey
        ) as? [String: Double] ?? [:]
        stored[sessionID] = rowID
        UserDefaults.standard.set(stored, forKey: watermarkKey)
    }

    /// 新对话落点：清当前会话态，首发时才在服务端
    /// 建行（与 iOS 新对话同口径）
    func startNew() {
        saveDraft()
        cancelRunObservation()
        sessionID = nil
        sessionTitle = "新对话"
        messages = []
        stubIDs = [:]
        draftText = ""
        pendingAttachments = []
        pendingFeedQuote = nil
        sendError = nil
        loadError = nil
        findQuery = ""
        findMatchIDs = []
        unreadAnchorStubID = nil
    }

    // MARK: - 草稿（#15）

    private func loadDraft(for sessionID: String) -> String {
        let stored = UserDefaults.standard.dictionary(
            forKey: draftsKey
        ) as? [String: String] ?? [:]
        return stored[sessionID] ?? ""
    }

    /// 存草稿：有当前会话且会话仍在（DraftSavePolicy
    /// 同判据）才落；空草稿删键
    func saveDraft() {
        guard let sessionID else { return }
        let stillExists = true
        guard DraftSavePolicy.shouldSaveOnLeavingActive(
            hasCurrentThread: true, threadStillExists: stillExists
        ) else { return }
        var stored = UserDefaults.standard.dictionary(
            forKey: draftsKey
        ) as? [String: String] ?? [:]
        let trimmed = draftText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed.isEmpty {
            stored.removeValue(forKey: sessionID)
        } else {
            stored[sessionID] = draftText
        }
        UserDefaults.standard.set(stored, forKey: draftsKey)
    }

    // MARK: - 附件（#16）

    func addAttachment(fileName: String, data: Data) {
        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "heic",
        ]
        let ext = (fileName as NSString).pathExtension.lowercased()
        pendingAttachments.append(
            MacPendingAttachment(
                fileName: fileName, data: data,
                isImage: imageExtensions.contains(ext)
            )
        )
    }

    func removeAttachment(_ attachment: MacPendingAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - 发送与生成（#14/#31）

    var canSend: Bool {
        !isGenerating
            && (!draftText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty || !pendingAttachments.isEmpty
                || pendingFeedQuote != nil)
    }

    func send(
        from session: SessionStore, listStore: MacSessionListStore
    ) {
        guard canSend else { return }
        let text = draftText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let attachments = pendingAttachments
        let quote = pendingFeedQuote
        draftText = ""
        pendingAttachments = []
        pendingFeedQuote = nil
        saveDraft()
        // 引用拼装走 Core 收口：引用块在前、亲笔在后，
        // 身份分开不冒充用户口吻（§208）
        let outgoing = FeedPostQuote.outgoingContent(
            userText: text, feedQuote: quote
        )
        Task {
            await performSend(
                text: outgoing, attachments: attachments,
                idempotencyKey: UUID().uuidString,
                from: session, listStore: listStore
            )
        }
        // 讨论信号（契约 rev2 §1.9）：引用建聊后发一记
        if let quote, let config = session.config,
           let key = session.apiKey {
            Task {
                try? await session.chatClient.feedDiscussSignal(
                    config: config, apiKey: key, id: quote.postID
                )
            }
        }
    }

    private func performSend(
        text: String, attachments: [MacPendingAttachment],
        presetImageURLs: [String] = [],
        idempotencyKey: String, from session: SessionStore,
        listStore: MacSessionListStore
    ) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        sendError = nil
        do {
            // 会话未建先建（新对话首发）
            var targetID = sessionID
            if targetID == nil {
                let created = try await session.chatClient
                    .createSession(
                        config: config, apiKey: key,
                        id: UUID().uuidString, title: nil
                    )
                targetID = created.id
                sessionID = created.id
                sessionTitle = "新对话"
                await listStore.load(from: session)
            }
            guard let targetID else { return }
            // 文件附件先上传、拼 @file 引用；图片走多
            // 模态尾条（契约同口径）
            var finalText = text
            var imageURLs: [String] = presetImageURLs
            var uploadedPaths: [String] = []
            for attachment in attachments {
                if attachment.isImage {
                    imageURLs.append(
                        FileSendAssembly.dataURL(
                            fileName: attachment.fileName,
                            data: attachment.data
                        )
                    )
                } else {
                    let receipt = try await session.chatClient
                        .uploadAttachment(
                            config: config, apiKey: key,
                            fileName: attachment.fileName,
                            data: attachment.data
                        )
                    guard let path = receipt.serverPath else {
                        throw HermesError.decodingFailed(
                            endpoint: "文件上传"
                        )
                    }
                    uploadedPaths.append(path)
                }
            }
            finalText = FileSendAssembly.appendingFileRefs(
                to: finalText, serverPaths: uploadedPaths
            )
            let input: RunInput = imageURLs.isEmpty
                ? .text(finalText)
                : .message(
                    ChatMessage(
                        role: "user", text: finalText,
                        imageDataURLs: imageURLs
                    )
                )
            let model = selectedModel ?? session.modelID ?? ""
            // 本地回显（落定以 transcript 回读为准）
            appendEcho(text: finalText)
            isGenerating = true
            isStopping = false
            streamingText = ""
            streamingToolNotes = []
            sawTerminal = false
            let receipt = try await session.chatClient.submitRun(
                config: config, apiKey: key, sessionID: targetID,
                input: input, model: model,
                idempotencyKey: idempotencyKey
            )
            activeRunID = receipt.runID
            observeRun(
                runID: receipt.runID, from: session,
                listStore: listStore
            )
        } catch let error as HermesError {
            isGenerating = false
            failedSends.append(
                MacFailedSend(
                    id: idempotencyKey, sessionID: sessionID ?? "",
                    text: text,
                    imageDataURLs: attachments
                        .filter(\.isImage)
                        .map {
                            FileSendAssembly.dataURL(
                                fileName: $0.fileName, data: $0.data
                            )
                        },
                    fileNames: attachments
                        .filter { !$0.isImage }
                        .map(\.fileName),
                    attempts: 1, lastError: error.userMessage,
                    manualOnly: false
                )
            )
            sendError = error.userMessage
        } catch {
            isGenerating = false
            sendError = error.localizedDescription
        }
    }

    private func appendEcho(text: String) {
        let echo = SessionMessage(
            id: -1 * (Double(messages.count) + 1),
            role: "user", content: text,
            timestamp: Date().timeIntervalSince1970
        )
        messages.append(echo)
        rebuildStubs()
    }

    /// 订阅 run 事件：正文增量进流式泡、工具起落进
    /// 旁注、终态触发回读落定；流断未见终态转状态
    /// 轮询对账（绝不自动重发，0.31.0 铁律）
    private func observeRun(
        runID: String, from session: SessionStore,
        listStore: MacSessionListStore
    ) {
        runTask = Task { [weak self] in
            guard let self, let config = session.config,
                  let key = session.apiKey else { return }
            let stream = session.chatClient.runEvents(
                config: config, apiKey: key, runID: runID,
                lastSeq: -1
            )
            for await envelope in stream {
                if Task.isCancelled { return }
                switch envelope.event {
                case .contentDelta(let delta), .interim(let delta):
                    self.streamingText += delta
                case .toolStarted(_, let name, _):
                    self.streamingToolNotes.append("正在使用 \(name)…")
                case .toolCompleted(_, let name, _, let failed):
                    self.streamingToolNotes.append(
                        failed ? "\(name) 执行失败" : "\(name) 已完成"
                    )
                case .reasoningPreview:
                    break  // 思考全文以 transcript 对账为准
                case .terminal(let kind, _):
                    self.sawTerminal = true
                    await self.finishRun(
                        kind: kind, from: session, listStore: listStore
                    )
                    return
                case .other:
                    break
                }
            }
            if Task.isCancelled { return }
            // 流断未见终态：状态轮询对账
            await self.reconcileRun(
                runID: runID, from: session, listStore: listStore
            )
        }
    }

    private func reconcileRun(
        runID: String, from session: SessionStore,
        listStore: MacSessionListStore
    ) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        for _ in 0..<40 {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            let status = try? await session.chatClient.runStatus(
                config: config, apiKey: key, runID: runID
            )
            guard let status else {
                // 记录查不到：转 transcript 定性
                await finishRun(
                    kind: .unknown, from: session, listStore: listStore
                )
                return
            }
            if status.status.isTerminal {
                await finishRun(
                    kind: status.status, from: session,
                    listStore: listStore
                )
                return
            }
        }
        // 预算耗尽：停在生成中呈现，不冒充失败
    }

    private func finishRun(
        kind: RunStatusKind, from session: SessionStore,
        listStore: MacSessionListStore
    ) async {
        isGenerating = false
        isStopping = false
        activeRunID = nil
        streamingText = ""
        streamingToolNotes = []
        await reload(from: session, listStore: listStore)
        await listStore.load(from: session)
        _ = kind
    }

    /// 停止（#14）：服务端真取消；本地观察任务随之
    /// 收尾，落定仍走回读
    func stop(from session: SessionStore) {
        guard let runID = activeRunID, !isStopping else { return }
        isStopping = true
        Task {
            guard let config = session.config,
                  let key = session.apiKey else { return }
            try? await session.chatClient.stopRun(
                config: config, apiKey: key, runID: runID
            )
        }
    }

    private func cancelRunObservation() {
        runTask?.cancel()
        runTask = nil
        isGenerating = false
        isStopping = false
        activeRunID = nil
        streamingText = ""
        streamingToolNotes = []
    }

    // MARK: - 发件箱重发（#31）

    /// 手点重发：同幂等键重演（服务端同键不双跑）；
    /// 文件附件按文件名提示需重新添加（字节不落盘
    /// 持久化，诚实口径——纯文本与图片可直接重发）
    func retry(
        _ failed: MacFailedSend, from session: SessionStore,
        listStore: MacSessionListStore
    ) {
        failedSends.removeAll { $0.id == failed.id }
        Task {
            await performSend(
                text: failed.text, attachments: [],
                presetImageURLs: failed.imageDataURLs,
                idempotencyKey: failed.id,
                from: session, listStore: listStore
            )
        }
    }

    func discard(_ failed: MacFailedSend) {
        failedSends.removeAll { $0.id == failed.id }
    }

    // MARK: - 模型（#17）

    /// 切换本会话模型：服务端落锁（POST /model）后
    /// 本地跟随；失败如实报错不假装已切换
    func selectModel(
        _ model: String, from session: SessionStore
    ) {
        guard let sessionID, model != selectedModel else { return }
        let previous = selectedModel
        selectedModel = model
        Task {
            guard let config = session.config,
                  let key = session.apiKey else { return }
            do {
                try await session.chatClient.updateSessionModel(
                    config: config, apiKey: key, id: sessionID,
                    model: model
                )
            } catch let error as HermesError {
                selectedModel = previous
                sendError = error.userMessage
            } catch {
                selectedModel = previous
                sendError = error.localizedDescription
            }
        }
    }

    // MARK: - 聊天内查找（#24）

    func recomputeFind() {
        guard let query = ChatFind.normalizedQuery(findQuery) else {
            findMatchIDs = []
            findCurrentIndex = 0
            return
        }
        let entries = messages.map { message in
            ChatFind.EntryStub(
                id: stubIDs[message.id] ?? UUID(),
                content: message.content,
                isSearchable: message.role == "user"
                    || message.role == "assistant"
            )
        }
        let matches = ChatFind.matches(entries: entries, query: query)
        findMatchIDs = matches.map(\.id)
        let anchor = entries.count - 1
        let start = ChatFind.nearestMatchIndex(
            matchPositions: matches.map(\.position),
            anchorPosition: anchor >= 0 ? anchor : nil
        )
        findCurrentIndex = start
    }

    func findNext() {
        guard !findMatchIDs.isEmpty else { return }
        findCurrentIndex = (findCurrentIndex + 1) % findMatchIDs.count
    }

    func findPrevious() {
        guard !findMatchIDs.isEmpty else { return }
        findCurrentIndex = (findCurrentIndex - 1 + findMatchIDs.count)
            % findMatchIDs.count
    }

    var findStatusText: String {
        guard ChatFind.normalizedQuery(findQuery) != nil else {
            return ""
        }
        if findMatchIDs.isEmpty { return "无结果" }
        return "\(findCurrentIndex + 1)/\(findMatchIDs.count)"
    }

    // MARK: - 选项卡（mac-09，对位 #21；Core OptionsCardLogic 单源）

    private func seedOptionsCardIfNeeded(
        sessionID: String, session: SessionStore
    ) {
        guard CapabilityNegotiation.optionsCardAvailability(
            session.capabilities
        ) != .unavailable else { return }
        guard let candidate = OptionsCardLogic.seedCandidate(
            in: messages
        ) else { return }
        let tid = threadUUID(for: sessionID)
        optionsOverlay.seed(
            threadID: tid,
            card: OptionsCardOverlay.Card(
                serverRowID: candidate.serverRowID,
                options: candidate.options
            )
        )
        optionsRevision += 1
    }

    func optionsCard(
        for message: SessionMessage, session: SessionStore
    ) -> (state: OptionsCardState, options: [MessageOption]) {
        let _ = optionsRevision
        guard message.role == "assistant",
              let sessionID,
              let rowID = Int(exactly: message.id),
              CapabilityNegotiation.optionsCardAvailability(
                  session.capabilities
              ) != .unavailable
        else { return (.hidden, []) }
        let tid = threadUUID(for: sessionID)
        guard let card = optionsOverlay.card(for: tid),
              card.serverRowID == rowID
        else { return (.hidden, []) }
        let lastAssistantID = messages.last(where: { $0.role == "assistant" })?.id
        let isTailAssistant = (lastAssistantID == message.id)
        let after = messages.drop(while: { $0.id != message.id }).dropFirst()
        let hasUserAfter = after.contains(where: { $0.role == "user" })
        let state = OptionsCardLogic.state(
            card: card,
            isTailAssistant: isTailAssistant,
            hasUserAfter: hasUserAfter,
            runInFlight: isGenerating,
            isDemo: false
        )
        return (state, card.options.options)
    }

    func selectOption(
        _ option: MessageOption, from session: SessionStore,
        listStore: MacSessionListStore
    ) {
        guard !isGenerating, let sessionID else { return }
        let tid = threadUUID(for: sessionID)
        optionsOverlay.markSelected(threadID: tid, label: option.label)
        optionsRevision += 1
        Task {
            await performSend(
                text: option.sendText, attachments: [],
                idempotencyKey: UUID().uuidString,
                from: session, listStore: listStore
            )
        }
    }

    // MARK: - 表情反应（mac-09，对位 #22；Core MessageReactions 单源）

    func reactions(for message: SessionMessage) -> [MessageReaction] {
        reactionOverrides[message.id] ?? message.reactions
    }

    func toggleReaction(
        emoji: String, on message: SessionMessage, from session: SessionStore
    ) {
        let current = reactions(for: message)
        if MessageReactions.ownEmoji(in: current) == emoji {
            clearReaction(on: message, from: session)
        } else {
            applyReaction(emoji: emoji, on: message, from: session)
        }
    }

    func clearReaction(
        on message: SessionMessage, from session: SessionStore
    ) {
        applyReaction(emoji: nil, on: message, from: session)
    }

    private func applyReaction(
        emoji: String?, on message: SessionMessage, from session: SessionStore
    ) {
        guard let sessionID,
              let rowID = Int(exactly: message.id), rowID > 0,
              let config = session.config, let key = session.apiKey
        else { return }
        let previous = reactions(for: message)
        reactionOverrides[message.id] = MessageReactions.applying(
            own: emoji, to: previous, at: Date().timeIntervalSince1970
        )
        Task {
            do {
                let updated: ReactionUpdate
                if let emoji {
                    updated = try await session.chatClient.setReaction(
                        config: config, apiKey: key,
                        sessionID: sessionID, rowID: rowID, emoji: emoji
                    )
                } else {
                    updated = try await session.chatClient.clearReaction(
                        config: config, apiKey: key,
                        sessionID: sessionID, rowID: rowID
                    )
                }
                reactionOverrides[message.id] = updated.reactions
            } catch let error as HermesError {
                if case .unexpectedStatus(_, let code) = error,
                   code == 404 || code == 405 {
                    // 服务端未开放 reactionsWrite：按能力协商口径保留本机显示并明示
                    sendError = "反应只在本机显示、服务端未开放持久化，刷新即丢"
                } else {
                    reactionOverrides[message.id] = previous
                    sendError = error.userMessage
                }
            } catch {
                reactionOverrides[message.id] = previous
                sendError = error.localizedDescription
            }
        }
    }
}
