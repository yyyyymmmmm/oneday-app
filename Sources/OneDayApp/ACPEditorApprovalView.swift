import OneDayCore
import OneDayDesign
import SwiftUI

// MARK: - #13 ACP 编辑器直连协议与移动端远程审批

struct ACPPendingEditApproval: Identifiable, Equatable {
    enum Decision: String {
        case pending
        case approved
        case rejected
    }

    let id: String
    let editorName: String
    let workspaceName: String
    let filePath: String
    let summary: String
    let diffLines: [String]
    var decision: Decision = .pending
}

struct ACPEditorApprovalView: View {
    @Environment(AppState.self) private var appState

    @State private var acpEnabled = true
    @State private var pushApprovalsToMobile = true
    @State private var transportMode = "stdio_ws_bridge"
    @State private var isLoading = false
    @State private var notice: String?
    @State private var approvals: [ACPPendingEditApproval] = []

    private let supportedEditors: [(name: String, symbol: String, detail: String)] = [
        ("VS Code / Cursor", "chevron.left.forwardslash.chevron.right", "通过 Hermes ACP 插件直连，支持文件 Diff 手机批复"),
        ("Zed Editor", "bolt.horizontal.fill", "原生 ACP (Agent Client Protocol) 双向会话与工具审批"),
        ("JetBrains IDEs", "hammer.fill", "通过 ACP 桥接网关同步重构提案与终端命令审批"),
    ]

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "laptopcomputer.and.iphone",
                tint: Palette.tintSkyInk,
                title: "ACP 编辑器直连与远程审批",
                subtitle: "桌面 IDE 通过 Agent Client Protocol 连接 Hermes 时，在手机端实时接收并批复代码改动与终端操作。",
                statusText: acpEnabled ? "远程审批已开启" : "未启用",
                statusTone: acpEnabled ? .healthy : .neutral
            )

            Section {
                Toggle(isOn: $acpEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用 ACP 编辑器直连协议")
                            .font(.rowTitleL)
                        Text("允许桌面 IDE 经网关接入同一 Hermes 实例与记忆")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .onChange(of: acpEnabled) { _, newValue in
                    Task { await persistConfig(key: "enabled", value: .bool(newValue)) }
                }

                Toggle(isOn: $pushApprovalsToMobile) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("桌面修改推送到手机批复")
                            .font(.rowTitleL)
                        Text("触发写入或高危命令时同步写入通知中心并等待确认")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .disabled(!acpEnabled)
                .onChange(of: pushApprovalsToMobile) { _, newValue in
                    Task { await persistConfig(key: "mobile_approval_push", value: .bool(newValue)) }
                }

                Picker("传输桥接模式", selection: $transportMode) {
                    Text("WebSocket + stdio 桥接").tag("stdio_ws_bridge")
                    Text("仅局域网 WebSocket").tag("lan_ws")
                    Text("仅本地 stdio").tag("local_stdio")
                }
                .onChange(of: transportMode) { _, newValue in
                    Task { await persistConfig(key: "transport", value: .string(newValue)) }
                }
            } header: {
                SettingsSectionHeader("协议与推送策略")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                if approvals.isEmpty {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(Palette.success)
                        Text("当前没有待批复的桌面 IDE 修改请求。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach($approvals) { $item in
                        approvalCard($item)
                    }
                }
            } header: {
                SettingsSectionHeader("待审批的 IDE 修改（\(approvals.filter { $0.decision == .pending }.count)）")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                ForEach(supportedEditors, id: \.name) { editor in
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: editor.symbol, color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(editor.name)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Text(editor.detail)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                SettingsSectionHeader("支持的桌面编辑器")
            } footer: {
                Text("在桌面端运行 `hermes acp --bridge` 即可自动将待审批修改同步到本页与通知中心。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            if let notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("ACP 编辑器直连")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFromServer() }
        .refreshable { await loadFromServer() }
    }

    private func approvalCard(_ item: Binding<ACPPendingEditApproval>) -> some View {
        let val = item.wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(val.editorName) · \(val.workspaceName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.primary)
                Spacer()
                if val.decision != .pending {
                    SettingsStatusPill(
                        text: val.decision == .approved ? "已批准" : "已拒绝",
                        tone: val.decision == .approved ? .healthy : .error
                    )
                }
            }
            Text(val.filePath)
                .font(.subheadline.monospaced().weight(.medium))
                .foregroundStyle(Palette.ink)
            Text(val.summary)
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)

            if !val.diffLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(val.diffLines.prefix(10).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("+") ? Palette.successText : (line.hasPrefix("-") ? Palette.danger : Palette.inkSecondary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .background(line.hasPrefix("+") ? Palette.success.opacity(0.10) : (line.hasPrefix("-") ? Palette.danger.opacity(0.10) : Color.clear))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            if val.decision == .pending {
                HStack(spacing: 8) {
                    Button("拒绝修改") {
                        Haptics.selection()
                        item.wrappedValue.decision = .rejected
                        Task { await persistConfig(key: "decisions", value: .object([val.id: .string("rejected")])) }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Palette.danger.opacity(0.12), in: Capsule())
                    .buttonStyle(.odPressable)

                    Button("批准写入") {
                        Haptics.success()
                        item.wrappedValue.decision = .approved
                        Task { await persistConfig(key: "decisions", value: .object([val.id: .string("approved")])) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Palette.primary, in: Capsule())
                    .buttonStyle(.odPressable)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func loadFromServer() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard appState.config != nil else { return }
        if let raw = try? await appState.readDashboardConfig(),
           let acp = raw["acp"]?.objectValue {
            if let v = acp["enabled"]?.boolValue { acpEnabled = v }
            if let v = acp["mobile_approval_push"]?.boolValue { pushApprovalsToMobile = v }
            if let v = acp["transport"]?.stringValue, !v.isEmpty { transportMode = v }
        }
    }

    private func persistConfig(key: String, value: JSONValue) async {
        guard appState.config != nil else { return }
        do {
            try await appState.applyDashboardConfig(["acp": .object([key: value])])
            notice = "ACP 配置已同步至服务端。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "配置同步失败，请稍后重试。"
        }
    }
}
