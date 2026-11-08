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
                    SectionLabel("服务端会话（共 \(total) 条）")
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
            .font(TypeScale.body.weight(.medium))
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
                NavigationLink(value: AgentRoute.serverSessionDetail(session.id)) {
                    rowContent(session, selecting: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rowContent(_ session: ServerSession, selecting: Bool) -> some View {
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: OneDayMetrics.spacingXS) {
                    if session.isActive {
                        StatusDot(color: Palette.success)
                    }
                    Text(session.title)
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                Text(subtitle(session))
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if !selecting {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    private func subtitle(_ session: ServerSession) -> String {
        var parts: [String] = []
        if let source = session.source, !source.isEmpty {
            parts.append(source)
        }
        parts.append(AdminFormat.short(session.startedDate))
        if let count = session.messageCount {
            parts.append("\(count) 条")
        }
        return parts.joined(separator: " · ")
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

/// 服务端会话详情：元信息＋消息回放（只读）＋删除。
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let session {
                    metaGroup(session)
                    messagesGroup
                    dangerGroup
                } else if let errorMessage {
                    InlineError(errorMessage)
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取会话…")
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
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
        .navigationTitle(session?.title ?? "会话详情")
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

    private func metaGroup(_ session: ServerSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("会话信息")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                infoRow("状态", session.isActive ? "进行中" : "已结束")
                if let source = session.source, !source.isEmpty {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("来源", source)
                }
                if let model = session.model, !model.isEmpty {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("模型", model, mono: true)
                }
                if let profile = session.profile, !profile.isEmpty {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("档案", profile)
                }
                GroupDivider(inset: OneDayMetrics.spacingM)
                infoRow("开始", AdminFormat.short(session.startedDate))
                if let ended = session.endedDate {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("结束", AdminFormat.short(ended))
                }
                if let count = session.messageCount {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("消息数", "\(count)")
                }
                if let tokens = session.inputTokens, let out = session.outputTokens {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow(
                        "Token（入/出）",
                        "\(AdminFormat.count(tokens)) / \(AdminFormat.count(out))"
                    )
                }
            }
            .odGroup()
        }
    }

    private var messagesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("消息")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            if messages.isEmpty {
                Text("没有可回放的消息。")
                    .font(TypeScale.callout)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                    ForEach(messages) { message in
                        messageRow(message)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: SessionMessage) -> some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 44)
                Text(message.content)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Palette.primaryTint,
                        in: RoundedRectangle(cornerRadius: OneDayMetrics.bubbleCorner)
                    )
            }
        } else if message.role == "assistant" {
            MarkdownText(message.content)
        } else {
            // 工具/系统类消息：安静的等宽摘要，不冒充对话
            Text("\(message.role)：\(message.content)")
                .font(TypeScale.monoFootnote)
                .foregroundStyle(Palette.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dangerGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("危险操作")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Text("删除这条会话")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.danger)
                        Spacer()
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

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(mono ? TypeScale.monoCallout : TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
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
            messages = loaded.filter { !$0.content.isEmpty || $0.role == "user" }
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
