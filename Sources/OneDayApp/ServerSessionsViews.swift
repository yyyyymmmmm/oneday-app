import OneDayDesign
import OneDayCore
import SwiftUI

/// 服务端会话页（智能体格，IA v3 §5.2）：服务端保存的会话
/// 列表、详情（元信息＋消息）、单删/多选批量删/清空空会话。
/// 本机会话在聊天抽屉，两处分工不同、不合并（定版明记）。
/// P10 补全文搜索：GET /api/sessions/search（生产实样
/// 已验：蓝鲸暗号命中真会话）——搜索态整页切换、隐藏
/// 管理工具，点命中行同正表走续聊。
struct ServerSessionsView: View {
    @Environment(AppState.self) private var appState

    @State private var sessions: [ServerSession] = []
    @State private var total: Int = 0
    @State private var emptyCount: Int = 0
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var notice: String?

    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showEmptyDeleteConfirm = false

    @State private var searchText = ""
    @State private var searchHits: [SessionSearchHit] = []
    @State private var isSearching = false
    @State private var searchError: String?

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isSearchActive {
                    searchContent
                } else if !sessions.isEmpty {
                    // 0.3.7 卡 16：摘要卡置顶，计数只在此一处
                    // 0.6.1：删「进行中 N 条」——isActive 靠
                    // endedAt==nil 判定、Hermes 不写 ended_at
                    // 时全量恒真，是与活动页同源的假数据；
                    // 列表语境只报可证的总数
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text("共 \(total) 条")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .odGroup()
                    SectionLabel("全部会话")
                        .padding(.top, 28)
                        .padding(.bottom, OneDayMetrics.spacingS)
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            if index > 0 {
                                GroupDivider()
                            }
                            sessionRow(session)
                        }
                    }
                    .odGroup()
                    if emptyCount > 0 {
                        cleanupGroup
                    }
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else if isLoading {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取会话…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                } else {
                    EmptyState(
                        icon: "bubble.left.and.text.bubble.right",
                        title: "服务端还没有会话",
                        message: "在聊天页和 Hermes 对话后，会话会同步保存在服务端。"
                    )
                    .padding(.top, OneDayMetrics.spacingXXL)
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("服务端会话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !sessions.isEmpty && !isSearchActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "完成" : "选择") {
                        selecting.toggle()
                        if !selecting { selectedIDs = [] }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting && !isSearchActive {
                bulkBar
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索会话内容"
        )
        .refreshable { await load() }
        .task { await load() }
        .task(id: searchText) { await runSearch() }
        .confirmationDialog(
            "删除所选 \(selectedIDs.count) 条会话？",
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await bulkDelete() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复；本机聊天记录不受影响。")
        }
        .confirmationDialog(
            "清空 \(emptyCount) 条空会话？",
            isPresented: $showEmptyDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                Task { await deleteEmpty() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("空会话指没有任何消息的会话，删除后无法恢复。")
        }
    }

    private var bulkBar: some View {
        HStack {
            Text("已选 \(selectedIDs.count) 条")
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Button("删除所选", role: .destructive) {
                showBulkDeleteConfirm = true
            }
            // 卡 17：medium 退出账本
            .font(.body)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingSM)
        .background(Palette.surface)
    }

    private var cleanupGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("清理")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                Button {
                    showEmptyDeleteConfirm = true
                } label: {
                    HStack {
                        Text("清空空会话")
                            .font(.body)
                            .foregroundStyle(Palette.danger)
                        Spacer()
                        Text("\(emptyCount) 条")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
            }
            .odGroup()
        }
    }

    private func sessionRow(_ session: ServerSession) -> some View {
        Group {
            if selecting {
                Button {
                    if selectedIDs.contains(session.id) {
                        selectedIDs.remove(session.id)
                    } else {
                        selectedIDs.insert(session.id)
                    }
                } label: {
                    rowContent(session, selecting: true)
                }
                .buttonStyle(.odPressable)
            } else {
                // 0.4.0（§3.4）：点会话改道聊天页续聊；本页
                // 只保留管理面（选择/批量删/清空）
                Button {
                    appState.pendingChatSessionID = session.id
                } label: {
                    rowContent(session, selecting: false)
                }
                .buttonStyle(.odPressable)
            }
        }
    }

    private func rowContent(_ session: ServerSession, selecting: Bool) -> some View {
        // 0.3.8 基线补遗增量令 2：行收编统一行组件
        // UnifiedRow（ListRowSpec 冻死规格）；选择态勾选
        // 圈是本页独有控件、留在组件外侧拼装；活跃点改
        // 走组件的状态点位（右侧，与箭头同簇）
        HStack(spacing: OneDayMetrics.spacingSM) {
            if selecting {
                Image(
                    systemName: selectedIDs.contains(session.id)
                        ? "checkmark.circle.fill" : "circle"
                )
                .font(.body)
                .foregroundStyle(
                    selectedIDs.contains(session.id) ? Palette.primary : Palette.inkMuted
                )
                .accessibilityHidden(true)
            }
            UnifiedRow(
                // 0.6.1 同口径收口：标题走全局派生（与
                // 抽屉/活动/总览行同源）；状态点删除——
                // isActive 在 ended_at 缺失下全量恒真、
                // 绿点即逐行假宣称「进行中」
                title: appState.sessionTitles.title(for: session),
                subtitle: session.humanSubtitle(now: Date()),
                statusColor: nil,
                showsChevron: !selecting
            )
        }
        .padding(.leading, selecting ? OneDayMetrics.spacingM : 0)
        .contentShape(Rectangle())
    }

    // MARK: - 搜索（P10）

    @ViewBuilder
    private var searchContent: some View {
        if isSearching {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在搜索…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.top, OneDayMetrics.spacingL)
        } else if let searchError {
            InlineError(searchError)
                .padding(.top, OneDayMetrics.spacingS)
        } else if searchHits.isEmpty {
            EmptyState(
                icon: "magnifyingglass",
                title: "没有找到相关的会话",
                message: "换个关键词再试。"
            )
            .padding(.top, OneDayMetrics.spacingXXL)
        } else {
            SectionLabel("搜索结果")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(
                    Array(searchHits.enumerated()), id: \.element.id
                ) { index, hit in
                    if index > 0 {
                        GroupDivider()
                    }
                    searchHitRow(hit)
                }
            }
            .odGroup()
        }
    }

    private func searchHitRow(_ hit: SessionSearchHit) -> some View {
        Button {
            // 与正表同路：交聊天页按服务端会话续聊
            appState.pendingChatSessionID = hit.sessionID
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
                    Text(hit.displayTitle)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let snippet = hit.snippet, !snippet.isEmpty {
                        Text(snippetLine(hit, snippet: snippet))
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                    }
                    Text(hitMetaLine(hit))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    /// 命中片段：带上命中角色（服务端 role 原值只译
    /// user/assistant，其余不臆断、不加前缀）
    private func snippetLine(_ hit: SessionSearchHit, snippet: String) -> String {
        if let role = hit.roleLabel {
            return "\(role)：\(snippet)"
        }
        return snippet
    }

    private func hitMetaLine(_ hit: SessionSearchHit) -> String {
        var parts: [String] = []
        parts.append(sourceText(hit.source))
        if let model = ModelDisplayNames.displayName(for: hit.model) {
            parts.append(model)
        }
        if let date = hit.startedDate {
            parts.append(DisplayDate.dateTime(date))
        }
        if let count = hit.messageCount {
            parts.append("\(count) 条消息")
        }
        return parts.joined(separator: " · ")
    }

    /// 来源译名与 ServerSession.sourceLabel 同表
    /// （SessionDisplay.swift），搜索行单独一份小表
    private func sourceText(_ source: String?) -> String {
        switch source?.lowercased() {
        case "api_server": return "其他应用"
        case "dashboard": return "控制台"
        case "cli": return "命令行"
        case "cron", "cron_job", "scheduler": return "定时任务"
        default: return "服务端"
        }
    }

    /// 搜索执行：.task(id: searchText) 驱动，先防抖
    /// 450ms 再打服务端；文本已变则本轮作废
    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchHits = []
            searchError = nil
            isSearching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        if Task.isCancelled { return }
        guard searchText.trimmingCharacters(in: .whitespaces) == query
        else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            searchHits = try await appState.performAdmin { client, config in
                try await client.searchSessions(
                    config: config, query: query, limit: 30
                )
            }
        } catch {
            searchHits = []
            searchError = (error as? HermesError)?.userMessage
                ?? "会话搜索失败。"
        }
    }

    // MARK: - 数据与动作

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await appState.performAdmin { client, config in
                try await client.serverSessions(config: config, limit: 100)
            }
            sessions = page.sessions
            // 派生标题补齐（0.6.1，全局解析器、预算封顶）
            await appState.sessionTitles.ensureTitles(
                for: page.sessions, appState: appState
            )
            total = page.total ?? page.sessions.count
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "会话没读出来，可能是网络或服务暂时没响应"
        }
        if let count = try? await appState.performAdmin({ client, config in
            try await client.emptySessionCount(config: config)
        }) {
            emptyCount = count
        }
    }

    private func bulkDelete() async {
        // 0.50.30 对齐真删标准：bulk-delete 端点在网关
        // 运行期被独占维护守卫拒绝（2026-11-13 生产实
        // 证 409），删会话只走围栏 DELETE 一条路——逐
        // 条走 ServerSessionActions.delete（围栏＋删后
        // 回查），失败的留在选中集里可重试、原因显形
        let ids = Array(selectedIDs)
        var failedIDs: [String] = []
        var firstReason: String?
        for id in ids {
            switch await ServerSessionActions.delete(
                appState: appState, id: id
            ) {
            case .verified:
                break
            case .failed(let reason):
                failedIDs.append(id)
                if firstReason == nil { firstReason = reason }
            }
        }
        selectedIDs = Set(failedIDs)
        if failedIDs.isEmpty {
            selecting = false
            notice = "已删除 \(ids.count) 条会话。"
        } else if let firstReason {
            notice = firstReason
        }
        await load()
    }

    private func deleteEmpty() async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteEmptySessions(config: config)
            }
            notice = "空会话已清空。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "清理失败，请稍后再试。"
        }
    }
}

/// 服务端会话详情（0.4.0 降级为「会话信息」，审计 §3.4）：
/// 会话主落点已改道聊天页续聊（点会话 → 导入本地线程），
/// 本页只作聊天页内的次级入口（点会话名次行打开）：元
/// 信息＋消息记录＋删除。消息记录不再用气泡渲染拷贝
/// （旧 primaryTint 染色随之删除——聊天气泡渲染只留聊
/// 天页一份）；工具/系统类消息折叠为摘要行，原文收进
/// DisclosureGroup，raw JSON 不许裸奔上屏。
struct ServerSessionDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let sessionID: String
    /// 只读形态（0.36.29，频道规格 §4.3）：合并桶在
    /// Hermes 频道页点开只许只读查看历史——不呈现
    /// 删除区、不发任何写请求（连详情页既有的删除
    /// 入口都不许带进来）；元信息与消息记录照常。
    /// 默认 false，其余入口（聊天页次级入口）行为不变
    var readOnly = false

    @State private var session: ServerSession?
    @State private var messages: [SessionMessage] = []
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            if let session {
                metaSection(session)
                recordsSection
                if !readOnly {
                    dangerSection
                }
            } else if let errorMessage {
                Section {
                    InlineError(errorMessage)
                }
            } else {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取会话…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // 标题走统一管线（0.18.0：服务端标题＞本地派
        // 生＞未命名，与抽屉/管理页同源），原始标题只
        // 留元信息组
        .navigationTitle(detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(
            "删除这条服务端会话？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await deleteSession() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复；本机聊天记录不受影响。")
        }
    }

    private var detailTitle: String {
        guard let session else { return "会话信息" }
        let firstUser = messages.first { $0.role == "user" }?.content
        return session.resolvedTitle(firstUserMessage: firstUser)
    }

    // MARK: - 元信息（LabeledContent，审计 §3.1 键值统一口径）

    private func metaSection(_ session: ServerSession) -> some View {
        Section("会话信息") {
            if let rawTitle = session.cleanedServerTitle,
               rawTitle != detailTitle {
                LabeledContent("原始标题", value: rawTitle)
            }
            // 状态只写可证事实（0.6.1）：有 ended_at 才
            // 敢说已结束；为空时服务端未提供结束信息，
            // 不许反推「进行中」（Hermes 现不写 ended_at）
            LabeledContent("状态", value: session.isActive ? "状态未确认" : "已结束")
            if let source = session.source, !source.isEmpty {
                LabeledContent("来源", value: session.sourceLabel)
            }
            if let model = session.model, !model.isEmpty {
                // §3.3 第 6 处：历史记录属性、留只读——走显
                // 示名映射，原始 id 退次级小字
                LabeledContent("模型") {
                    VStack(alignment: .trailing, spacing: OneDayMetrics.spacingMicro) {
                        Text(ModelDisplayNames.displayName(for: model) ?? model)
                        if ModelDisplayNames.displayName(for: model) != nil {
                            Text(model)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let profile = session.profile, !profile.isEmpty {
                LabeledContent("档案", value: profile)
            }
            LabeledContent("开始", value: AdminFormat.short(session.startedDate))
            if let ended = session.endedDate {
                LabeledContent("结束", value: AdminFormat.short(ended))
            }
            if let count = session.messageCount {
                LabeledContent("消息数", value: "\(count)")
            }
            if let tokens = session.inputTokens, let out = session.outputTokens {
                LabeledContent(
                    "Token（入/出）",
                    value: "\(AdminFormat.count(tokens)) / \(AdminFormat.count(out))"
                )
            }
        }
    }

    // MARK: - 消息记录（非气泡渲染：记录行＋工具摘要行）

    private var recordsSection: some View {
        Section("消息记录") {
            if messages.isEmpty {
                Text("没有可回放的消息。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(messages) { message in
                    recordRow(message)
                }
            }
        }
    }

    @ViewBuilder
    private func recordRow(_ message: SessionMessage) -> some View {
        if message.role == "user" || message.role == "assistant" {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == "user" ? "用户" : "助手")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if message.role == "assistant" {
                    MarkdownText(message.content)
                } else {
                    Text(message.content)
                        .font(.body)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingMicro)
        } else {
            // 工具/系统类消息：摘要行＋展开看原文（raw
            // JSON 只许躺在 DisclosureGroup 里，不直出）
            DisclosureGroup {
                Text(message.content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } label: {
                Label(
                    message.role == "tool" ? "工具调用" : "系统消息",
                    systemImage: message.role == "tool"
                        ? "wrench.and.screwdriver" : "gearshape"
                )
                .font(.callout)
            }
        }
    }

    // MARK: - 删除

    private var dangerSection: some View {
        Section {
            Button("删除这条会话", role: .destructive) {
                showDeleteConfirm = true
            }
        }
    }

    private func load() async {
        do {
            session = try await appState.performAdmin { client, config in
                try await client.serverSession(config: config, id: sessionID)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "会话没读出来，可能是网络或服务暂时没响应"
        }
        if let loaded = try? await appState.performAdmin({ client, config in
            try await client.sessionMessages(config: config, id: sessionID)
        }) {
            messages = loaded.filter { !$0.content.isEmpty }
        }
    }

    private func deleteSession() async {
        // 0.50.30：同走 ServerSessionActions.delete
        // （围栏 DELETE＋删后回查），未落定不关页
        switch await ServerSessionActions.delete(
            appState: appState, id: sessionID
        ) {
        case .verified:
            dismiss()
        case .failed(let reason):
            notice = reason
        }
    }
}
