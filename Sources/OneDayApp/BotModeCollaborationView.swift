import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// Bot Mode 多智能体房间协作与授权管理（Hermes v0.23.0 `/v1/room-members/*`）：
/// 完整闭环房间邀请票据签发（POST /v1/room-members/invitations）、
/// 成员能力发现（GET /v1/room-members/capabilities）、
/// 授权续期（POST /v1/room-members/grants/refresh）与立即撤销（POST /v1/room-members/grants/revoke）。
struct BotModeCollaborationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 多分身 @mention 群聊编排
    @State private var rosterProfiles: [ProfileSummary] = []
    @State private var selectedBotNames: Set<String> = []
    @State private var groupTopic = ""

    // 签发房间邀请表单
    @State private var roomID = "room-main"
    @State private var homeInstallID = "oneday-ios"
    @State private var authorityGatewayID = "gateway-primary"
    @State private var authorityEpoch = 1
    @State private var memberID = "agent-peer-1"
    @State private var ttlMinutes = 60

    // 当前活跃或导入的房间授权票据（HermesRoom <grant>）
    @State private var activeGrantToken = ""
    @State private var activeProfile = ""
    @State private var expiresAt: Double?
    @State private var capabilities: RoomMemberCapabilitiesResponse?

    @State private var busyAction: String?
    @State private var feedbackText: String?
    @State private var isFeedbackError = false

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "person.3.sequence.fill",
                tint: Palette.tintLavenderInk,
                title: "Bot Mode 多体协作",
                subtitle: "为跨实例 Hermes 智能体签发短时房间授权票据（HermesRoom Grant），实时核验成员能力目录、按需续期或一键撤销。",
                statusText: activeGrantToken.isEmpty ? "待签发" : "已持有票据",
                statusTone: activeGrantToken.isEmpty ? .neutral : .healthy
            )

            if let feedbackText {
                Section {
                    Label(
                        feedbackText,
                        systemImage: isFeedbackError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(isFeedbackError ? Palette.danger : Palette.successText)
                }
                .listRowBackground(Palette.surface)
            }

            groupOrchestrationSection

            Section {
                LabeledContent("房间 ID") {
                    TextField("room-main", text: $roomID)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("成员 ID") {
                    TextField("agent-peer-1", text: $memberID)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("主实例 ID") {
                    TextField("oneday-ios", text: $homeInstallID)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("权威网关 ID") {
                    TextField("gateway-primary", text: $authorityGatewayID)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Stepper("有效期：\(ttlMinutes) 分钟", value: $ttlMinutes, in: 5...1440, step: 15)

                Button {
                    Task { await mintInvitation() }
                } label: {
                    HStack {
                        if busyAction == "mint" {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "ticket.fill")
                        }
                        Text(busyAction == "mint" ? "正在签发房间邀请…" : "签发房间成员授权票据")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busyAction != nil || roomID.isEmpty || memberID.isEmpty)
            } header: {
                SettingsSectionHeader("签发新房间邀请")
            }
            .listRowBackground(Palette.surface)

            Section {
                TextField("粘贴或使用上方签发的 HermesRoom Grant 票据", text: $activeGrantToken, axis: .vertical)
                    .font(.caption.monospaced())
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !activeGrantToken.isEmpty {
                    HStack(spacing: 10) {
                        Button("复制票据") {
                            UIPasteboard.general.string = activeGrantToken
                            Haptics.success()
                            showFeedback("已复制 HermesRoom 授权票据", isError: false)
                        }
                        .buttonStyle(.bordered)

                        Button("查询能力") {
                            Task { await inspectCapabilities() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busyAction != nil)

                        Button("续期") {
                            Task { await refreshGrant() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busyAction != nil)

                        Spacer()

                        Button("撤销", role: .destructive) {
                            Task { await revokeGrant() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busyAction != nil)
                    }
                    .font(.caption.weight(.semibold))
                }

                if let expiresAt, expiresAt > 0 {
                    LabeledContent("派发授权到期") {
                        Text(Date(timeIntervalSince1970: expiresAt), style: .relative)
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                if !activeProfile.isEmpty {
                    LabeledContent("目标分身档案") {
                        Text(activeProfile)
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            } header: {
                SettingsSectionHeader("授权票据生命周期")
            }
            .listRowBackground(Palette.surface)

            if let cap = capabilities {
                Section {
                    LabeledContent("房间", value: cap.roomID)
                    LabeledContent("成员", value: cap.memberID)
                    LabeledContent("目标档案", value: cap.targetProfile)
                    if let gw = cap.authorityGatewayID, !gw.isEmpty {
                        LabeledContent("权威网关", value: gw)
                    }
                } header: {
                    SettingsSectionHeader("实时成员能力核验")
                }
                .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .animation(MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion), value: selectedBotNames)
        .navigationTitle("Bot Mode 多体协作")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRosterProfiles() }
    }

    private var groupOrchestrationSection: some View {
        let sortedSelected = rosterProfiles.map(\.name).filter { selectedBotNames.contains($0) }
        let mentionsPrefix = sortedSelected.map { "@\($0)" }.joined(separator: " ")
        return Section {
            if rosterProfiles.isEmpty {
                Text("正在读取常驻分身花名册…可在「配置档案与分身」中创建多个专家分身。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(rosterProfiles, id: \.name) { profile in
                            let picked = selectedBotNames.contains(profile.name)
                            Button {
                                Haptics.selection()
                                if picked {
                                    selectedBotNames.remove(profile.name)
                                } else {
                                    selectedBotNames.insert(profile.name)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: picked ? "checkmark.circle.fill" : "person.crop.circle")
                                    Text(profile.name)
                                }
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(picked ? .white : Palette.ink)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(
                                    picked ? Palette.tintLavenderInk : Palette.fillTertiary,
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                TextField("输入协同议题（如：请各自评估此架构方案的风险与排期）", text: $groupTopic, axis: .vertical)
                    .lineLimit(2...4)

                if !mentionsPrefix.isEmpty {
                    Text("将生成接力指令：\(mentionsPrefix) \(groupTopic)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Palette.inkSecondary)
                }

                Button {
                    let combined = "\(mentionsPrefix) \(groupTopic.trimmingCharacters(in: .whitespacesAndNewlines))".trimmingCharacters(in: .whitespaces)
                    UIPasteboard.general.string = combined
                    Haptics.success()
                    showFeedback("已生成多分身 @mention 协同指令并复制到剪贴板，正在跳转聊天页。", isError: false)
                    appState.router.mainTabSwitchRequest = .chat
                    dismiss()
                } label: {
                    Label("发起多分身 @mention 协同群聊", systemImage: "bubble.left.and.bubble.right.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.tintLavenderInk)
                .disabled(selectedBotNames.count < 2 || groupTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            SettingsSectionHeader("多分身 @mention 群聊编排")
        } footer: {
            Text("选择 2 位及以上常驻专家分身，一键组装 @mention 接力指令并跳转会话协作。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
    }

    private func loadRosterProfiles() async {
        guard let config = appState.config, let apiKey = appState.apiKey else { return }
        if let resp = try? await appState.client.profiles(config: config, apiKey: apiKey) {
            rosterProfiles = resp.profiles
        }
    }

    private func mintInvitation() async {
        guard let config = appState.config, let apiKey = appState.apiKey else {
            showFeedback("请先连接 Hermes 服务器并确保 API 密钥可用。", isError: true)
            return
        }
        busyAction = "mint"
        defer { busyAction = nil }

        do {
            let receipt = try await appState.client.createRoomInvitation(
                config: config,
                apiKey: apiKey,
                roomID: roomID.trimmingCharacters(in: .whitespacesAndNewlines),
                homeInstallID: homeInstallID.trimmingCharacters(in: .whitespacesAndNewlines),
                authorityGatewayID: authorityGatewayID.trimmingCharacters(in: .whitespacesAndNewlines),
                authorityEpoch: authorityEpoch,
                memberID: memberID.trimmingCharacters(in: .whitespacesAndNewlines),
                ttlSeconds: ttlMinutes * 60
            )
            activeGrantToken = receipt.grant
            activeProfile = receipt.targetProfile
            expiresAt = receipt.expiresAt
            Haptics.success()
            showFeedback("已签发短时房间授权票据，可复制到协作节点或立即核验能力。", isError: false)
        } catch {
            showFeedback(error.localizedDescription, isError: true)
        }
    }

    private func inspectCapabilities() async {
        guard let config = appState.config else { return }
        let token = activeGrantToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        busyAction = "capabilities"
        defer { busyAction = nil }

        do {
            let cap = try await appState.client.roomMemberCapabilities(config: config, grantToken: token)
            capabilities = cap
            activeProfile = cap.targetProfile
            Haptics.success()
            showFeedback("已核验成员「\(cap.memberID)」在房间「\(cap.roomID)」的实时能力。", isError: false)
        } catch {
            showFeedback(error.localizedDescription, isError: true)
        }
    }

    private func refreshGrant() async {
        guard let config = appState.config else { return }
        let token = activeGrantToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        busyAction = "refresh"
        defer { busyAction = nil }

        do {
            let receipt = try await appState.client.refreshRoomGrant(
                config: config, grantToken: token, ttlSeconds: ttlMinutes * 60
            )
            activeGrantToken = receipt.grant
            expiresAt = receipt.expiresAt
            Haptics.success()
            showFeedback("房间授权已续期，新票据已自动替换。", isError: false)
        } catch {
            showFeedback(error.localizedDescription, isError: true)
        }
    }

    private func revokeGrant() async {
        guard let config = appState.config else { return }
        let token = activeGrantToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        busyAction = "revoke"
        defer { busyAction = nil }

        do {
            _ = try await appState.client.revokeRoomGrant(config: config, grantToken: token)
            activeGrantToken = ""
            expiresAt = nil
            capabilities = nil
            Haptics.success()
            showFeedback("房间授权已立即撤销并加入吊销列表。", isError: false)
        } catch {
            showFeedback(error.localizedDescription, isError: true)
        }
    }

    private func showFeedback(_ text: String, isError: Bool) {
        feedbackText = text
        isFeedbackError = isError
    }
}
