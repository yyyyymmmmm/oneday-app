import OneDayCore
import OneDayDesign
import SwiftUI

// MARK: - #41 MEMORY / USER / SOUL 分段编辑器与写入审批

struct MemoryPendingDiffItem: Identifiable, Equatable {
    let id: String
    let targetFile: String
    let summary: String
    let addedLines: [String]
    let removedLines: [String]
}

struct MemoryMarkdownEditorSheet: View {
    let appState: AppState
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    enum MemoryDocTab: String, CaseIterable, Identifiable {
        case memory = "MEMORY.md"
        case user = "USER.md"
        case soul = "SOUL.md"
        var id: String { rawValue }

        var configKey: String {
            switch self {
            case .memory: return "memory_md"
            case .user: return "user_md"
            case .soul: return "soul_md"
            }
        }
    }

    @State private var activeTab: MemoryDocTab = .memory
    @State private var drafts: [MemoryDocTab: String] = [:]
    @State private var requireWriteApproval = true
    @State private var pendingDiffs: [MemoryPendingDiffItem] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var feedback: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("文档", selection: $activeTab) {
                        ForEach(MemoryDocTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                Section {
                    Toggle(isOn: $requireWriteApproval) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI 写入记忆前需要审批")
                                .font(.rowTitleL)
                            Text("开启后，Hermes 修改 MEMORY/USER 前将生成 Diff 供你确认")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                } header: {
                    SettingsSectionHeader("写入审批策略")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                if !pendingDiffs.isEmpty {
                    Section {
                        ForEach(pendingDiffs) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(item.targetFile) · \(item.summary)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Palette.ink)
                                    Spacer()
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(item.removedLines, id: \.self) { line in
                                        Text("- \(line)")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(Palette.danger)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 6)
                                            .background(Palette.danger.opacity(0.10))
                                    }
                                    ForEach(item.addedLines, id: \.self) { line in
                                        Text("+ \(line)")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(Palette.successText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 6)
                                            .background(Palette.success.opacity(0.10))
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                HStack(spacing: 8) {
                                    Button("拒绝") {
                                        Haptics.selection()
                                        pendingDiffs.removeAll { $0.id == item.id }
                                    }
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Palette.danger)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Palette.danger.opacity(0.12), in: Capsule())
                                    .buttonStyle(.odPressable)

                                    Button("批准写入") {
                                        Haptics.success()
                                        approveDiff(item)
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Palette.primary, in: Capsule())
                                    .buttonStyle(.odPressable)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        SettingsSectionHeader("待审批写入 Diff（\(pendingDiffs.count)）")
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }

                Section {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在读取服务端记忆文档…")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    } else {
                        TextEditor(text: Binding(
                            get: { drafts[activeTab] ?? "" },
                            set: { drafts[activeTab] = $0 }
                        ))
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 240)
                        .scrollContentBackground(.hidden)
                    }
                } header: {
                    SettingsSectionHeader("\(activeTab.rawValue) 正文编辑")
                } footer: {
                    if let feedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle("长期记忆与画像编辑")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadFromServer() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await saveToServer() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func approveDiff(_ item: MemoryPendingDiffItem) {
        let target: MemoryDocTab = item.targetFile.contains("USER") ? .user : (item.targetFile.contains("SOUL") ? .soul : .memory)
        let current = drafts[target] ?? ""
        let appended = item.addedLines.joined(separator: "\n")
        drafts[target] = current.isEmpty ? appended : "\(current)\n\(appended)"
        pendingDiffs.removeAll { $0.id == item.id }
        feedback = "已将变更合并到 \(target.rawValue)，点击右上角「保存」同步至服务端。"
    }

    private func loadFromServer() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard appState.config != nil else { return }
        if let raw = try? await appState.readDashboardConfig() {
            if let memoryCfg = raw["memory"]?.objectValue {
                if let approval = memoryCfg["require_write_approval"]?.boolValue {
                    requireWriteApproval = approval
                }
                if let files = memoryCfg["files"]?.objectValue {
                    if let m = files["memory_md"]?.stringValue { drafts[.memory] = m }
                    if let u = files["user_md"]?.stringValue { drafts[.user] = u }
                    if let s = files["soul_md"]?.stringValue { drafts[.soul] = s }
                }
            }
        }
        if drafts[.memory] == nil {
            drafts[.memory] = "# MEMORY.md\n\n- 记录长期项目约定、架构偏好与关键决策\n"
        }
        if drafts[.user] == nil {
            drafts[.user] = "# USER.md\n\n- 记录沟通风格、时区与工作流习惯\n"
        }
        if drafts[.soul] == nil {
            drafts[.soul] = "# SOUL.md\n\n- 定义智能体的核心人格、边界与协作原则\n"
        }
    }

    private func saveToServer() async {
        isSaving = true
        defer { isSaving = false }
        guard appState.config != nil else {
            feedback = "当前未连接到 Hermes 服务端。"
            return
        }
        var files: [String: JSONValue] = [:]
        for tab in MemoryDocTab.allCases {
            if let text = drafts[tab] {
                files[tab.configKey] = .string(text)
            }
        }
        do {
            try await appState.applyDashboardConfig([
                "memory": .object([
                    "require_write_approval": .bool(requireWriteApproval),
                    "files": .object(files),
                ]),
            ])
            Haptics.success()
            onSaved()
            dismiss()
        } catch {
            feedback = (error as? HermesError)?.userMessage ?? "保存失败，请稍后再试。"
        }
    }
}

// MARK: - #42 记忆版本回滚（memory-rewind）与外部记忆后端选择

struct MemoryRevisionSnapshot: Identifiable {
    let id: String
    let label: String
    let timestamp: String
    let summary: String
}

struct MemoryRewindSheet: View {
    let appState: AppState
    let onRewindSubmitted: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBackend = "local_sqlite"
    @State private var isSavingBackend = false
    @State private var statusMessage: String?

    private let backends: [(id: String, title: String, subtitle: String)] = [
        ("local_sqlite", "Local SQLite + FTS5（内置默认）", "零外部依赖，本地高速全文索引与事务快照"),
        ("honcho", "Honcho（语义建模引擎）", "深度用户心智建模与多会话长期推理记忆"),
        ("mem0", "Mem0（向量图谱记忆）", "自动抽取事实三元组与跨端向量召回"),
        ("zep", "Zep（时序知识图谱）", "带时间衰减与事实演化追踪的企业级记忆"),
        ("obsidian", "Obsidian Vault（本地双向链接）", "直接读写 Markdown 知识库并保持双向链接"),
    ]

    private let snapshots: [MemoryRevisionSnapshot] = [
        MemoryRevisionSnapshot(id: "HEAD~1", label: "上一轮自动快照（HEAD~1）", timestamp: "最近一次记忆写入前", summary: "撤销最近一次对话写入的 MEMORY/USER 变更"),
        MemoryRevisionSnapshot(id: "HEAD~3", label: "3 轮前快照（HEAD~3）", timestamp: "最近 3 次写入前", summary: "回退到近期稳定记忆状态，保留更早档案"),
        MemoryRevisionSnapshot(id: "daily-0", label: "今日零点基线（daily-0）", timestamp: "今日 00:00", summary: "恢复至今日开始前的完整记忆版本"),
    ]

    var body: some View {
        NavigationStack {
            List {
                SettingsHeroCard(
                    symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    tint: .purple,
                    title: "记忆版本回滚与后端",
                    subtitle: "按历史版本时间轴一键执行 memory-rewind，并切换外部记忆后端插件。",
                    statusText: selectedBackend,
                    statusTone: .healthy
                )

                Section {
                    ForEach(snapshots) { snap in
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            SettingsRowIcon(symbol: "clock.badge.checkmark", color: .purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snap.label)
                                    .font(.rowTitleL)
                                    .foregroundStyle(Palette.ink)
                                Text("\(snap.timestamp) · \(snap.summary)")
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer(minLength: 6)
                            Button("回滚") {
                                Task { await triggerRewind(snap.id) }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.tintLavenderInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Palette.tintLavender, in: Capsule())
                            .buttonStyle(.odPressable)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    SettingsSectionHeader("memory-rewind 历史版本时间轴")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                Section {
                    ForEach(backends, id: \.id) { backend in
                        Button {
                            Haptics.selection()
                            selectedBackend = backend.id
                            Task { await saveBackend(backend.id) }
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingSM) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backend.title)
                                        .font(.rowTitleL)
                                        .foregroundStyle(Palette.ink)
                                    Text(backend.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer()
                                if selectedBackend == backend.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Palette.primary)
                                }
                            }
                            .frame(minHeight: OneDayMetrics.settingsRowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSavingBackend)
                    }
                } header: {
                    SettingsSectionHeader("外部记忆后端插件")
                } footer: {
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle("版本回滚与后端")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadCurrentBackend() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func loadCurrentBackend() async {
        guard appState.config != nil else { return }
        if let raw = try? await appState.readDashboardConfig(),
           let backend = raw["memory"]?.objectValue?["backend"]?.stringValue,
           !backend.isEmpty {
            selectedBackend = backend
        }
    }

    private func saveBackend(_ backend: String) async {
        isSavingBackend = true
        defer { isSavingBackend = false }
        guard appState.config != nil else { return }
        do {
            try await appState.applyDashboardConfig(["memory": .object(["backend": .string(backend)])])
            Haptics.success()
            statusMessage = "已切换记忆后端为 \(backend)。"
        } catch {
            statusMessage = (error as? HermesError)?.userMessage ?? "后端切换失败，请稍后再试。"
        }
    }

    private func triggerRewind(_ target: String) async {
        Haptics.selection()
        do {
            try await appState.applyDashboardConfig(["memory": .object(["rewind_target": .string(target)])])
            onRewindSubmitted(target)
            dismiss()
        } catch {
            statusMessage = (error as? HermesError)?.userMessage ?? "回滚请求未能保存。"
        }
    }
}
