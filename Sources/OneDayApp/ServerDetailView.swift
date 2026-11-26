import OneDayDesign
import OneDayCore
import SwiftUI

/// 当前服务器详情页（统一原生 iOS 26 List(.insetGrouped) + Hero 摘要卡，
/// 彻底替换旧版手绘 ScrollView + .odGroup() 拼接风格）
struct ServerDetailView: View {
    @Environment(AppState.self) private var appState

    @State private var serverText = ""
    @State private var apiKeyText = ""
    @State private var isSaving = false
    @State private var saveResult: String?
    @State private var saveFailed = false
    @State private var isRetesting = false
    @State private var hasRetested = false
    @State private var retestResult: String?
    @State private var retestFailed = false
    @State private var showDisconnectConfirm = false

    private var heroTone: SettingsStatusTone {
        if retestFailed { return .error }
        if hasRetested { return .healthy }
        return appState.config != nil ? .neutral : .warning
    }

    private var heroStatusText: String {
        if retestFailed { return "连接异常" }
        if hasRetested { return "连接正常" }
        return appState.config != nil ? "已保存凭据" : "未连接"
    }

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "server.rack",
                tint: .blue,
                title: appState.config?.host ?? "未连接服务器",
                subtitle: "管理自部署 Hermes 网关地址、Bearer 密钥与设备接入。",
                statusText: heroStatusText,
                statusTone: heroTone
            )

            Section {
                ServerAddressFieldRow(text: $serverText)
                ServerSecretFieldRow(
                    label: "密钥",
                    text: $apiKeyText,
                    placeholder: "Hermes 的 Bearer 密钥"
                )
            } header: {
                SettingsSectionHeader("连接凭据")
            } footer: {
                if let saveResult {
                    Text(saveResult)
                        .font(.footnote)
                        .foregroundStyle(saveFailed ? Palette.danger : Palette.successText)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(
                            symbol: "checkmark.circle",
                            color: isEdited && !isSaving ? Palette.primary : Palette.inkMuted
                        )
                        Text(isSaving ? "正在测试…" : "保存并测试")
                            .font(.rowTitleL.weight(.medium))
                            .foregroundStyle(isEdited && !isSaving ? Palette.primary : Palette.inkMuted)
                        Spacer()
                        if isSaving {
                            ProgressView()
                        }
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .disabled(isSaving || !isEdited)
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                Button {
                    Task { await retest() }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "antenna.radiowaves.left.and.right")
                        Text("重新测试连接")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        if isRetesting {
                            ProgressView()
                        }
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .disabled(isRetesting)
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            } footer: {
                if let retestResult {
                    Text(retestResult)
                        .font(.footnote)
                        .foregroundStyle(retestFailed ? Palette.danger : Palette.successText)
                }
            }

            Section {
                NavigationLink(value: SettingsRoute.addDevice) {
                    serverLinkRow(
                        icon: "qrcode",
                        title: "添加设备",
                        summary: "生成认领二维码，让新设备扫码接入"
                    )
                }
                NavigationLink(value: SettingsRoute.pairingManagement) {
                    serverLinkRow(
                        icon: "person.badge.key",
                        title: "设备配对",
                        summary: "批准消息平台上申请对话的新用户"
                    )
                }
            } header: {
                SettingsSectionHeader("多设备与配对")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                NavigationLink(value: SettingsRoute.envVars) {
                    serverLinkRow(
                        icon: "key",
                        title: "服务器密钥",
                        summary: "管理保存在服务端的环境变量与 API 密钥"
                    )
                }
                NavigationLink(value: SettingsRoute.connectionSelfCheck) {
                    serverLinkRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "连接自检",
                        summary: "秒级探活检查网络连通与接口能力"
                    )
                }
                NavigationLink(value: SettingsRoute.healthCheck) {
                    serverLinkRow(
                        icon: "stethoscope",
                        title: "体检与存档",
                        summary: "深度自检、安全审计与备份存档"
                    )
                }
                NavigationLink(value: SettingsRoute.logs) {
                    serverLinkRow(
                        icon: "doc.text",
                        title: "系统日志",
                        summary: "查看服务端运行日志"
                    )
                }
            } header: {
                SettingsSectionHeader("服务器管理")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            ServerVersionSection()

            Section {
                Button(role: .destructive) {
                    showDisconnectConfirm = true
                } label: {
                    Text("断开连接")
                        .font(.rowTitleL.weight(.medium))
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, minHeight: OneDayMetrics.settingsRowHeight, alignment: .center)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .confirmationDialog(
            "断开连接？",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("断开连接", role: .destructive) {
                appState.disconnect()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除这台手机上保存的服务器凭据与登录会话。本地聊天记录保留。")
        }
        .navigationTitle("当前服务器")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if serverText.isEmpty {
                serverText = appState.config?.baseString ?? ""
            }
            if apiKeyText.isEmpty {
                apiKeyText = appState.apiKey ?? ""
            }
        }
    }

    private func serverLinkRow(
        icon: String, title: String, summary: String
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            SettingsRowIcon(symbol: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private var isEdited: Bool {
        serverText != (appState.config?.baseString ?? "")
            || apiKeyText != (appState.apiKey ?? "")
    }

    private func save() async {
        saveResult = nil
        guard let config = ServerConfig(rawInput: serverText) else {
            saveFailed = true
            saveResult = HermesError.invalidServerAddress.userMessage
            Haptics.error()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await appState.connectDirect(config: config, apiKey: apiKeyText)
            serverText = config.baseString
            apiKeyText = appState.apiKey ?? apiKeyText
            saveFailed = false
            hasRetested = true
            retestFailed = false
            saveResult = "已保存：健康检查与密钥验证全部通过。"
            Haptics.success()
        } catch {
            saveFailed = true
            saveResult = (error as? HermesError)?.userMessage ?? "保存失败，请稍后再试。"
            Haptics.error()
        }
    }

    private func retest() async {
        isRetesting = true
        retestResult = nil
        defer { isRetesting = false }
        do {
            try await appState.retestConnection()
            retestFailed = false
            hasRetested = true
            retestResult = "连接正常：所有校验已通过。"
            Haptics.success()
        } catch {
            retestFailed = true
            hasRetested = true
            retestResult = (error as? HermesError)?.userMessage ?? "连接失败。"
            Haptics.error()
        }
    }
}
