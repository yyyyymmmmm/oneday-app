import OneDayCore
import OneDayDesign
import SwiftUI

/// 平台用户配对（H5，台账 35，DESIGN §359）：设置
/// → 服务与工作区 → 服务器段「平台用户配对」。管
/// 的是网关消息平台的用户白名单——陌生人在
/// Telegram／WhatsApp 等平台第一次私聊网关时拿到
/// 一次性配对码（1 小时内有效），在这里批准后才
/// 能开始和网关对话；已批准的人可随时撤销。
/// 与同段相邻的「添加设备」是两物：那面管哪台手
/// 机连进来（设备入驻），本面管谁能跟网关说话，
/// 页首说明写死防混。
/// 纪律：批准走申请编号、不经手配对码本体；三写
/// 动作全部回读对账才算生效（PairingStore）；生
/// 产网关暂未接入消息平台时两列恒空——如实空态
/// ＋接入指引，不造样例数据
struct PairingManagementView: View {
    @Environment(AppState.self) private var appState
    @State private var store = PairingStore()
    @State private var revokeTarget: PairingApprovedEntry?
    @State private var showClearConfirm = false

    /// 操作组装：全部走管理面统一通道（401 自动重
    /// 登、终局 sessionExpired），与全 App /api/* 同路
    private var operations: PairingOperations {
        PairingOperations(
            list: {
                try await appState.performAdmin { client, config in
                    try await client.pairingList(config: config)
                }
            },
            approve: { entry in
                try await appState.performAdmin { client, config in
                    try await client.pairingApprove(
                        config: config, platform: entry.platform,
                        requestID: entry.requestID
                    )
                }
            },
            revoke: { entry in
                try await appState.performAdmin { client, config in
                    try await client.pairingRevoke(
                        config: config, platform: entry.platform,
                        userID: entry.userID
                    )
                }
            },
            clearPending: {
                try await appState.performAdmin { client, config in
                    try await client.pairingClearPending(config: config)
                }
            }
        )
    }

    private var serverBase: String? { appState.config?.baseString }

    var body: some View {
        List {
            if let note = store.note {
                Section {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(
                            store.noteIsProblem
                                ? Palette.danger : Palette.inkSecondary
                        )
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(settingsRowInsets)
            }

            content
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("设备配对")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load(
                operations: operations, serverBase: serverBase
            )
        }
        .refreshable {
            await store.load(
                operations: operations, serverBase: serverBase
            )
        }
        .confirmationDialog(
            "撤销这个用户的批准？",
            isPresented: Binding(
                get: { revokeTarget != nil },
                set: { if !$0 { revokeTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: revokeTarget
        ) { entry in
            Button("撤销批准", role: .destructive) {
                Task {
                    await store.revoke(
                        entry, operations: operations,
                        serverBase: serverBase
                    )
                }
                revokeTarget = nil
            }
            Button("取消", role: .cancel) {
                revokeTarget = nil
            }
        } message: { entry in
            Text("撤销后，\(entry.userName.isEmpty ? entry.userID : entry.userName) 将不能再和网关对话，需要重新申请配对。")
        }
        .confirmationDialog(
            "清空全部待批申请？",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("全部清空", role: .destructive) {
                Task {
                    await store.clearPending(
                        operations: operations, serverBase: serverBase
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会清掉所有平台的待批申请（不分平台），已批准的用户不受影响。")
        }
    }

    // MARK: - 状态内容

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取配对清单…")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
        case .notLoggedIn:
            Section {
                Text("登录已过期。回到连接页重新登录后，再回来管理配对。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                retryRow
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
        case .failed(let message):
            Section {
                Text(message)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                retryRow
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
        case .ready(let response):
            readyContent(response)
        }
    }

    private var retryRow: some View {
        Button("重试") {
            Task {
                await store.load(
                    operations: operations, serverBase: serverBase
                )
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private func readyContent(_ response: PairingListResponse) -> some View {
        if response.pending.isEmpty && response.approved.isEmpty {
            Section {
                Text("还没有消息平台接入；接入 Telegram／WhatsApp 等平台后，在这里批准新用户。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
        } else {
            Section {
                if response.pending.isEmpty {
                    Text("暂无待批申请。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(response.pending) { entry in
                    pendingRow(entry)
                }
            } header: {
                sectionHeader("待批准")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)

            if !response.approved.isEmpty {
                Section {
                    ForEach(response.approved) { entry in
                        approvedRow(entry)
                    }
                } header: {
                    sectionHeader("已批准")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(settingsRowInsets)
            }

            if !response.pending.isEmpty {
                Section {
                    Button("清空全部待批申请", role: .destructive) {
                        showClearConfirm = true
                    }
                    .font(.rowSubtitle)
                    .disabled(store.isClearing)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(settingsRowInsets)
            }
        }
    }

    // MARK: - 行

    private func pendingRow(_ entry: PairingPendingEntry) -> some View {
        HStack(
            alignment: .top, spacing: OneDayMetrics.spacingS
        ) {
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(entry.userName.isEmpty ? entry.userID : entry.userName)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.ink)
                Text(pendingMeta(entry))
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                if !entry.canApprove {
                    Text("这条是旧版申请、没有编号，不能在这里批准。")
                        .font(.caption)
                        .foregroundStyle(Palette.warningText)
                }
            }
            Spacer()
            if store.actingIDs.contains(entry.id) {
                ProgressView()
            } else if entry.canApprove {
                Button("批准") {
                    Task {
                        await store.approve(
                            entry, operations: operations,
                            serverBase: serverBase
                        )
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingMicro)
    }

    private func approvedRow(_ entry: PairingApprovedEntry) -> some View {
        HStack(
            alignment: .top, spacing: OneDayMetrics.spacingS
        ) {
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(entry.userName.isEmpty ? entry.userID : entry.userName)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.ink)
                Text(approvedMeta(entry))
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            if store.actingIDs.contains(entry.id) {
                ProgressView()
            } else {
                Button("撤销", role: .destructive) {
                    revokeTarget = entry
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingMicro)
    }

    // MARK: - 呈现派生

    private func pendingMeta(_ entry: PairingPendingEntry) -> String {
        var parts = [Self.platformDisplayName(entry.platform)]
        if !entry.userName.isEmpty {
            parts.append(entry.userID)
        }
        parts.append(Self.ageText(entry.ageMinutes))
        return parts.joined(separator: " · ")
    }

    private func approvedMeta(_ entry: PairingApprovedEntry) -> String {
        var parts = [Self.platformDisplayName(entry.platform)]
        if !entry.userName.isEmpty {
            parts.append(entry.userID)
        }
        parts.append(Self.approvedAtText(entry.approvedAt))
        return parts.joined(separator: " · ")
    }

    /// 平台名呈现：已知平台给正式名，未知原样显（不猜）
    static func platformDisplayName(_ platform: String) -> String {
        switch platform.lowercased() {
        case "telegram": return "Telegram"
        case "whatsapp": return "WhatsApp"
        case "signal": return "Signal"
        case "discord": return "Discord"
        case "slack": return "Slack"
        case "matrix": return "Matrix"
        case "feishu": return "飞书"
        case "dingtalk": return "钉钉"
        case "wecom": return "企业微信"
        case "email": return "邮件"
        case "api_server": return "API"
        default: return platform
        }
    }

    /// 等待时长人话（服务端 age_minutes 现算值，只做
    /// 量级呈现、不编造精确时刻）
    static func ageText(_ minutes: Double) -> String {
        if minutes < 1 { return "刚刚申请" }
        if minutes < 60 {
            return "等待约 \(Int(minutes.rounded())) 分钟"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "等待约 \(Int(hours.rounded())) 小时"
        }
        return "等待约 \(Int((hours / 24).rounded())) 天"
    }

    /// 批准时刻呈现：服务端原样字符串——能按 ISO
    /// 解析就格式化，解析不了原样显，缺失显「未记录」
    static func approvedAtText(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "批准时间未记录" }
        if let date = parseISODate(raw) {
            return "批准于 \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "批准于 \(raw)"
    }

    private static func parseISODate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    // MARK: - 共用件（与设置域叶子页同式）

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
    }

    private var settingsRowInsets: EdgeInsets {
        OneDayMetrics.settingsRowInsets
    }
}
