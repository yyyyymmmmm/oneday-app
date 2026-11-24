import OneDayDesign
import OneDayCore
import SwiftUI

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
    @Environment(\.modelContext) private var modelContext

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
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
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
        // §232 乐观删除：确认即交协调器（本地先删）
        // 并关页，不等服务端落定；后台最终失败由协
        // 调器恢复＋提醒（提醒走聊天页提示条，本页
        // 已关不拦）
        appState.sessionDeletions.begin(
            sessionID: sessionID,
            title: session?.cleanedServerTitle ?? "",
            appState: appState, modelContext: modelContext
        )
        dismiss()
    }
}
