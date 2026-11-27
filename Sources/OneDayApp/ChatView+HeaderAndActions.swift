import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

// MARK: - 顶栏状态、按钮簇、中枢入口与对话内查找（Batch 5 #53 从 ChatView.swift 拆离）

extension ChatView {
    /// 顶栏状态行（0.6.0 立；0.6.1 改短词；0.7.0 通道
    /// 口径修正）：词由 OneDayCore.OverviewStatusLine
    /// 对「桥快照＋Hermes 通道探活」双输入纯派生，只报
    /// 可证事实短词（联系不上／待审批 N／在线）
    var overviewStatusWord: String {
        overviewStore?.statusLine ?? "联系不上"
    }

    /// 状态点色（0.19.0 改同源）：与状态词共用 Core 的
    /// classify 一处判定（OverviewBridgeStore.statusTone）
    var overviewStatusColor: Color {
        switch overviewStore?.statusTone {
        case .online: return Palette.success
        case .attention: return Palette.warning
        case .offline, nil: return Palette.inkMuted
        }
    }

    var overviewBadgeCount: Int {
        overviewStore?.badgeCount ?? 0
    }

    /// D9：对话内查找栏（对标 iOS Messages）
    var findBar: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)

                TextField("在对话中搜索", text: $findController.query)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($findFieldFocused)
                    .onSubmit {
                        performFind()
                    }

                if !findController.trimmedQuery.isEmpty {
                    Text(
                        findController.session.matches.isEmpty
                            ? "无结果"
                            : "\(findController.session.currentIndex + 1)/\(findController.session.matches.count)"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.fieldFill, in: Capsule())
                }

                if !findController.query.isEmpty {
                    Button {
                        findController.query = ""
                        findController.clearMatches()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索词")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .glassEffect(.regular, in: Capsule())

            HStack(spacing: 4) {
                Button {
                    navigateToPreviousMatch()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            findController.session.matches.isEmpty ? Palette.inkMuted : Palette.ink
                        )
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular, in: Circle())
                }
                .disabled(findController.session.matches.isEmpty)
                .buttonStyle(.odPressable)
                .accessibilityLabel("上一条命中")

                Button {
                    navigateToNextMatch()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            findController.session.matches.isEmpty ? Palette.inkMuted : Palette.ink
                        )
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular, in: Circle())
                }
                .disabled(findController.session.matches.isEmpty)
                .buttonStyle(.odPressable)
                .accessibilityLabel("下一条命中")

                Button {
                    closeFind()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("关闭搜索")
            }
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingXS)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            findFieldFocused = true
        }
        .task(id: findController.query) {
            guard findController.isPresented else { return }
            guard findController.normalizedQuery != nil else {
                findController.clearMatches()
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            recomputeFind()
        }
    }

    /// 中枢呈现内容（§502）：卡片／标准二选一由 HubCardPolicy 裁决
    @ViewBuilder
    var hubCover: some View {
        if HubCardPolicy.decide(
            reduceMotion: reduceMotion
        ) == .card {
            HubCardHost(
                progress: appState.hubCardProgress,
                onDismissed: { dismissHubWithoutAnimation() }
            ) { requestClose in
                hubView(onCardClose: requestClose)
            }
        } else {
            hubView(onCardClose: nil)
        }
    }

    /// 中枢本体构造（§502）
    func hubView(
        onCardClose: (() -> Void)?
    ) -> some View {
        AgentHubView(
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
                },
                onTap: {
                    showHub = true
                }
            ),
            onCardClose: onCardClose
        )
    }

    /// 开中枢（§502）
    func presentHub() {
        showHub = true
    }

    func dismissHubWithoutAnimation() {
        showHub = false
        appState.hubCardProgress.strength = 0
    }

    /// 顶簇本体（TopBarGuideHost），列表顶留位据此记账
    var topBarCluster: some View {
        VStack(spacing: OneDayMetrics.rowInnerGap) {
            topBand
            if findController.isPresented {
                findBar
            }
        }
    }

    /// 顶带（§449；2026-11-27 用户亲令改版）：
    /// 汉堡/查找/铃铛与居中身份区同带。
    /// 2026-11-27 改版：右侧查找/铃铛两按钮收进同一胶囊容器
    var topBand: some View {
        ZStack(alignment: .center) {
            headerIdentityHero
            HStack(alignment: .center, spacing: 0) {
                drawerButton
                Spacer(minLength: OneDayMetrics.spacingS)
                // 右侧两按钮收进同一胶囊（2026-11-27）
                HStack(spacing: 4) {
                    findButton
                    bellButton
                }
                .padding(.horizontal, 4)
                .glassEffect(.regular, in: Capsule())
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    /// 左钮：汉堡（开抽屉）
    var drawerButton: some View {
        Button {
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

    /// 查找钮（总表 150／§500；2026-11-27 改版）：会话内查找的直达入口
    var findButton: some View {
        Button {
            findController.open()
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
                .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("在对话中查找")
        .accessibilityIdentifier("topbar.find")
    }

    /// 右钮：铃铛＋角标（角标＝未读通知＋待审批，总览桥聚合；2026-11-27 改版）
    var bellButton: some View {
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
                if overviewBadgeCount > 0 {
                    Text("\(overviewBadgeCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, OneDayMetrics.spacingXS)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Palette.dangerFill, in: Capsule())
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(
            overviewBadgeCount > 0
                ? "通知，\(overviewBadgeCount) 条待处理"
                : "通知"
        )
    }

    /// 居中身份区（§434）：大头像 67pt 居中＋名/状态身份胶囊
    /// §名下状态行改造（2026-11-27）：传入活动短语与连接状态词
    var headerIdentityHero: some View {
        HubIdentityCapsule(
            displayName: appState.agentDisplayName,
            statusWord: assistantActivityStatus,
            needsApproval: appState.sharedHubStore().hasPendingApprovals,
            avatar: appState.agentAvatarImage,
            statusColor: overviewStatusColor,
            liveActivityPhrase: appState.liveActivityPhrase,
            connectionStatusWord: appState.connectionStatus.phaseWord,
            onOpenHub: { presentHub() },
            onFindInConversation: { findController.open() },
            onForkSession: currentThread?.serverSessionID != nil
                ? { forkCurrentSession() }
                : nil
        )
    }

    // MARK: - D9 对话内查找（§503 全件接线）

    /// 执行查找（键盘「搜索」键）
    func performFind() {
        recomputeFind()
    }

    /// 重算命中：计算委托给 Core ChatFind，状态与高亮生命周期归 findController
    func recomputeFind(allowHunt: Bool = true) {
        guard let thread = currentThread,
              let query = findController.normalizedQuery
        else {
            findController.clearMatches()
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
            findController.clearMatches()
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
        var session = findController.session
        let target = session.recompute(
            matches: found.map(\.id), startIndex: startIndex
        )
        findController.session = session
        if let target {
            findController.applyTarget(target) { surfaceFocusEntry($0) }
        }
    }

    func findHighlightQuery(for entryID: UUID) -> String? {
        findController.highlightQuery(for: entryID)
    }

    func navigateToNextMatch() {
        findController.moveNext { surfaceFocusEntry($0) }
    }

    func navigateToPreviousMatch() {
        findController.movePrevious { surfaceFocusEntry($0) }
    }

    func closeFind() {
        findController.close()
    }

    func huntFindWindow(
        query: String, thread: ChatThread
    ) {
        guard let sessionID = thread.serverSessionID,
              !sessionID.isEmpty
        else { return }
        let huntKey = "\(thread.id.uuidString)|\(query)"
        guard findController.huntedKey != huntKey else { return }
        findController.huntedKey = huntKey
        let threadID = thread.id
        let token = UUID()
        findController.huntToken = token
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
                    if entries.isEmpty { return }
                    break
                }
                entries.append(contentsOf: page.entries)
                guard currentThreadID == threadID,
                      findController.huntToken == token,
                      let next = page.nextCursor, next != cursor
                else { break }
                cursor = next
            }
            guard currentThreadID == threadID,
                  findController.huntToken == token,
                  findController.normalizedQuery == query
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
                      findController.huntToken == token,
                      findController.normalizedQuery == query
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
}
