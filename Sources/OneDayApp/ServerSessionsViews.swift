import OneDayDesign
import OneDayCore
import SwiftUI

/// 服务端会话页（智能体格，IA v3 §5.2）：服务端保存的会话
/// 列表、详情（元信息＋消息）、单删/多选批量删/清空空会话。
/// 本机会话在聊天抽屉，两处分工不同、不合并（定版明记）。
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !sessions.isEmpty {
                    // 0.3.7 卡 16：摘要卡置顶，计数只在此一处
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text("共 \(total) 条 · 进行中 \(sessions.filter(\.isActive).count) 条")
                            .font(TypeScale.body)
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
                                GroupDivider(inset: OneDayMetrics.spacingM)
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
                            .font(TypeScale.footnote)
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
                        .font(TypeScale.footnote)
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
            if !sessions.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "完成" : "选择") {
                        selecting.toggle()
                        if !selecting { selectedIDs = [] }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                bulkBar
            }
        }
        .refreshable { await load() }
        .task { await load() }
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
                .font(TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Button("删除所选", role: .destructive) {
                showBulkDeleteConfirm = true
            }
            // 卡 17：medium 退出账本
            .font(TypeScale.body)
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
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.danger)
                        Spacer()
                        Text("\(emptyCount) 条")
                            .font(TypeScale.monoFootnote)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                .buttonStyle(.plain)
            } else {
                // 0.4.0（§3.4）：点会话改道聊天页续聊；本页
                // 只保留管理面（选择/批量删/清空）
                Button {
                    appState.pendingChatSessionID = session.id
                } label: {
                    rowContent(session, selecting: false)
                }
                .buttonStyle(.plain)
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
                .font(TypeScale.body)
                .foregroundStyle(
                    selectedIDs.contains(session.id) ? Palette.primary : Palette.inkMuted
                )
                .accessibilityHidden(true)
            }
            UnifiedRow(
                title: session.humanTitle,
                subtitle: session.humanSubtitle(now: Date()),
                statusColor: session.isActive ? Palette.success : nil,
                showsChevron: !selecting
            )
        }
        .padding(.leading, selecting ? OneDayMetrics.spacingM : 0)
        .contentShape(Rectangle())
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
            total = page.total ?? page.sessions.count
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "会话读取失败。"
        }
        if let count = try? await appState.performAdmin({ client, config in
            try await client.emptySessionCount(config: config)
        }) {
            emptyCount = count
        }
    }

    private func bulkDelete() async {
        let ids = Array(selectedIDs)
        do {
            try await appState.performAdmin { client, config in
                try await client.bulkDeleteServerSessions(config: config, ids: ids)
            }
            selectedIDs = []
            selecting = false
            notice = "已删除 \(ids.count) 条会话。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "删除失败，请稍后再试。"
        }
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
                dangerSection
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
        // 标题＝内容总结标题（首条用户消息摘要，与抽屉/
        // 列表同源），原始标题只留元信息组
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
        return session.contentTitle(firstUserMessage: firstUser)
    }

    // MARK: - 元信息（LabeledContent，审计 §3.1 键值统一口径）

    private func metaSection(_ session: ServerSession) -> some View {
        Section("会话信息") {
            if session.title != detailTitle {
                LabeledContent("原始标题", value: session.title)
            }
            LabeledContent("状态", value: session.isActive ? "进行中" : "已结束")
            if let source = session.source, !source.isEmpty {
                LabeledContent("来源", value: session.sourceLabel)
            }
            if let model = session.model, !model.isEmpty {
                // §3.3 第 6 处：历史记录属性、留只读——走显
                // 示名映射，原始 id 退次级小字
                LabeledContent("模型") {
                    VStack(alignment: .trailing, spacing: 2) {
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
            .padding(.vertical, 2)
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
            errorMessage = (error as? HermesError)?.userMessage ?? "会话读取失败。"
        }
        if let loaded = try? await appState.performAdmin({ client, config in
            try await client.sessionMessages(config: config, id: sessionID)
        }) {
            messages = loaded.filter { !$0.content.isEmpty }
        }
    }

    private func deleteSession() async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteServerSession(config: config, id: sessionID)
            }
            dismiss()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "删除失败，请稍后再试。"
        }
    }
}
