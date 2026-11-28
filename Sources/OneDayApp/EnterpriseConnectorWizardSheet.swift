import OneDayCore
import OneDayDesign
import SwiftUI

// MARK: - #36 飞书 / Microsoft Graph / Discord 企业协同生态向导

struct EnterpriseEcosystemPreset: Identifiable, Equatable {
    struct CredentialField: Identifiable, Equatable {
        let id: String
        let key: String
        let label: String
        let placeholder: String
        let isSecret: Bool
    }

    let id: String
    let serverName: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let ink: Color
    let command: String
    let args: [String]
    let fields: [CredentialField]

    static let all: [EnterpriseEcosystemPreset] = [
        EnterpriseEcosystemPreset(
            id: "feishu",
            serverName: "feishu-lark",
            title: "飞书 / Lark 协同套件",
            subtitle: "打通飞书文档、多维表格、群消息与审批流，支持自动同步与消息触发",
            symbol: "paperplane.circle.fill",
            tint: Palette.tintSky,
            ink: Palette.tintSkyInk,
            command: "npx",
            args: ["-y", "@larksuiteoapi/lark-mcp"],
            fields: [
                .init(id: "app_id", key: "FEISHU_APP_ID", label: "飞书 App ID", placeholder: "cli_a1b2c3d4e5f6", isSecret: false),
                .init(id: "app_secret", key: "FEISHU_APP_SECRET", label: "飞书 App Secret", placeholder: "输入应用密钥", isSecret: true),
            ]
        ),
        EnterpriseEcosystemPreset(
            id: "microsoft-graph",
            serverName: "microsoft-365-graph",
            title: "Microsoft 365 / Graph",
            subtitle: "接入 Outlook 邮件、Teams、OneDrive、SharePoint 与企业日程",
            symbol: "building.2.crop.circle.fill",
            tint: Palette.tintLavender,
            ink: Palette.tintLavenderInk,
            command: "npx",
            args: ["-y", "@softeria/ms-365-mcp-server"],
            fields: [
                .init(id: "tenant", key: "MS_GRAPH_TENANT_ID", label: "Tenant ID（租户 ID）", placeholder: "common 或组织 GUID", isSecret: false),
                .init(id: "client_id", key: "MS_GRAPH_CLIENT_ID", label: "Application (Client) ID", placeholder: "Azure AD 应用 ID", isSecret: false),
                .init(id: "client_secret", key: "MS_GRAPH_CLIENT_SECRET", label: "Client Secret", placeholder: "输入客户端密钥", isSecret: true),
            ]
        ),
        EnterpriseEcosystemPreset(
            id: "discord",
            serverName: "discord-bot",
            title: "Discord 社区与 Bot",
            subtitle: "读写 Discord 频道消息、Thread 讨论、Webhook 推送与社区巡检",
            symbol: "bubble.left.and.bubble.right.fill",
            tint: Palette.tintGreen,
            ink: Palette.tintGreenInk,
            command: "npx",
            args: ["-y", "mcp-discord"],
            fields: [
                .init(id: "token", key: "DISCORD_BOT_TOKEN", label: "Discord Bot Token", placeholder: "输入机器人令牌", isSecret: true),
                .init(id: "guild", key: "DISCORD_GUILD_ID", label: "默认服务器 ID（可选）", placeholder: "如 123456789012345678", isSecret: false),
            ]
        ),
    ]
}

struct EnterpriseConnectorWizardSheet: View {
    let preset: EnterpriseEcosystemPreset
    let facade: ConnectorsFacade
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var values: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        for field in preset.fields where !field.label.contains("可选") {
            let v = values[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if v.isEmpty { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Image(systemName: preset.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(preset.ink)
                            .frame(width: 40, height: 40)
                            .background(preset.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Text(preset.subtitle)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    LabeledContent("注册服务名", value: preset.serverName)
                    LabeledContent("启动命令") {
                        Text("\(preset.command) \(preset.args.joined(separator: " "))")
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.inkSecondary)
                    }
                } header: {
                    Text("生态连接器说明")
                }

                Section {
                    ForEach(preset.fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            let binding = Binding<String>(
                                get: { values[field.key] ?? "" },
                                set: { values[field.key] = $0 }
                            )
                            if field.isSecret {
                                SecureField(field.placeholder, text: binding)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                TextField(field.placeholder, text: binding)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("应用凭据配置")
                } footer: {
                    Text("凭据仅写入你自己的 Hermes 服务端配置，不会经过任何第三方中转。")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("接入 \(preset.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "接入中…" : "一键接入") {
                        Task { await install() }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private func install() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let env = values
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }
        let ok = await facade.addCustomServer(
            name: preset.serverName,
            url: nil,
            command: preset.command,
            args: preset.args,
            env: env,
            auth: nil,
            bearerToken: nil,
            appState: appState
        )
        if ok {
            Haptics.success()
            dismiss()
        } else {
            errorMessage = facade.notice ?? "接入失败，请检查服务是否在线或是否存在同名连接器。"
        }
    }
}
