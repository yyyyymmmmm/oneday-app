import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 终端后端参数配置表单（Hermes v0.23.0 6 大终端后端：
/// Local / Docker / SSH / Modal / Daytona / Vercel Sandbox）。
/// 通过 `PUT /api/config` 写入 `terminal.*` 字段，支持镜像名、SSH 主机/端口/用户、
/// 工作目录、超时时间与环境变量透传。
struct TerminalBackendConfigSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let backend: TerminalBackend

    @State private var dockerImage = "python:3.12-slim"
    @State private var dockerMountCwd = true
    @State private var sshHost = ""
    @State private var sshUser = "root"
    @State private var sshPort = "22"
    @State private var sshKeyPath = ""
    @State private var sandboxWorkspace = ""
    @State private var workingDirectory = ""
    @State private var timeoutSeconds = 180
    @State private var envPassthrough = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var isError = false

    private var normalizedKind: String {
        backend.name.lowercased()
    }

    var body: some View {
        NavigationStack {
            List {
                SettingsHeroCard(
                    symbol: backendSymbol,
                    tint: Palette.tintSkyInk,
                    title: "\(backend.displayLabel) 参数配置",
                    subtitle: "配置该终端后端的镜像、连接主机、工作目录与超时策略，保存后写入 Hermes 服务端 config.yaml。",
                    statusText: backend.status == .ready ? "就绪" : "待配置",
                    statusTone: backend.status == .ready ? .healthy : .warning
                )

                if normalizedKind.contains("docker") {
                    Section {
                        LabeledContent("容器镜像") {
                            TextField("python:3.12-slim", text: $dockerImage)
                                .multilineTextAlignment(.trailing)
                                .font(.metaMonospaced)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Toggle("挂载当前工作区目录", isOn: $dockerMountCwd)
                            .tint(Palette.primary)
                    } header: {
                        SettingsSectionHeader("Docker 容器参数")
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }

                if normalizedKind.contains("ssh") {
                    Section {
                        LabeledContent("SSH 主机") {
                            TextField("192.168.1.10 或 host.example.com", text: $sshHost)
                                .multilineTextAlignment(.trailing)
                                .font(.metaMonospaced)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        LabeledContent("登录用户") {
                            TextField("root / ubuntu", text: $sshUser)
                                .multilineTextAlignment(.trailing)
                                .font(.metaMonospaced)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        LabeledContent("端口") {
                            TextField("22", text: $sshPort)
                                .multilineTextAlignment(.trailing)
                                .font(.metaMonospaced)
                                .keyboardType(.numberPad)
                        }
                        LabeledContent("私钥路径（服务端）") {
                            TextField("~/.ssh/id_ed25519", text: $sshKeyPath)
                                .multilineTextAlignment(.trailing)
                                .font(.metaMonospaced)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        SettingsSectionHeader("SSH 远程主机参数")
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }

                if normalizedKind.contains("modal")
                    || normalizedKind.contains("daytona")
                    || normalizedKind.contains("vercel") {
                    Section {
                        LabeledContent("沙箱镜像 / 工作区") {
                            TextField("默认云沙箱环境", text: $sandboxWorkspace)
                                .multilineTextAlignment(.trailing)
                                .font(.metaMonospaced)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        SettingsSectionHeader("云沙箱参数")
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }

                Section {
                    LabeledContent("默认工作目录") {
                        TextField("/workspace 或留空", text: $workingDirectory)
                            .multilineTextAlignment(.trailing)
                            .font(.metaMonospaced)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Stepper(value: $timeoutSeconds, in: 30...900, step: 30) {
                        LabeledContent("命令超时") {
                            Text("\(timeoutSeconds) 秒")
                                .font(.rowSubtitle)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("环境变量透传（逗号分隔键名）")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        TextField("例如：HTTP_PROXY,NO_PROXY,NODE_ENV", text: $envPassthrough)
                            .font(.metaMonospaced)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                } header: {
                    SettingsSectionHeader("通用执行策略")
                } footer: {
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(isError ? Palette.danger : Palette.successText)
                    }
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle("后端参数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await saveConfig() }
                    }
                    .disabled(isSaving || isLoading)
                }
            }
            .task {
                await loadExistingConfig()
            }
        }
    }

    private var backendSymbol: String {
        if normalizedKind.contains("docker") { return "shippingbox.fill" }
        if normalizedKind.contains("ssh") { return "network" }
        if normalizedKind.contains("local") { return "terminal.fill" }
        return "cloud.fill"
    }

    private func loadExistingConfig() async {
        guard let config = appState.config, let apiKey = appState.apiKey else { return }
        isLoading = true
        defer { isLoading = false }
        guard let raw = try? await appState.client.rawConfig(config: config, apiKey: apiKey),
              let term = raw["terminal"] as? [String: Any]
        else { return }
        if let img = term["docker_image"] as? String, !img.isEmpty { dockerImage = img }
        if let mount = term["docker_mount_cwd"] as? Bool { dockerMountCwd = mount }
        if let host = term["ssh_host"] as? String { sshHost = host }
        if let user = term["ssh_user"] as? String, !user.isEmpty { sshUser = user }
        if let port = term["ssh_port"] as? Int { sshPort = String(port) }
        if let key = term["ssh_key"] as? String { sshKeyPath = key }
        if let cwd = term["cwd"] as? String { workingDirectory = cwd }
        if let t = term["timeout"] as? Int, t >= 30 { timeoutSeconds = t }
        if let pass = term["env_passthrough"] as? [String] {
            envPassthrough = pass.joined(separator: ",")
        }
    }

    private func saveConfig() async {
        guard let config = appState.config, let apiKey = appState.apiKey else { return }
        isSaving = true
        statusMessage = nil
        isError = false
        defer { isSaving = false }

        var terminalPatch: [String: Any] = [
            "backend": backend.name,
            "timeout": timeoutSeconds,
        ]
        if !workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            terminalPatch["cwd"] = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let passList = envPassthrough
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !passList.isEmpty {
            terminalPatch["env_passthrough"] = passList
        }
        if normalizedKind.contains("docker") {
            terminalPatch["docker_image"] = dockerImage.trimmingCharacters(in: .whitespacesAndNewlines)
            terminalPatch["docker_mount_cwd"] = dockerMountCwd
        }
        if normalizedKind.contains("ssh") {
            terminalPatch["ssh_host"] = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
            terminalPatch["ssh_user"] = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
            terminalPatch["ssh_port"] = Int(sshPort) ?? 22
            if !sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalPatch["ssh_key"] = sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if !sandboxWorkspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            terminalPatch["sandbox_image"] = sandboxWorkspace.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        do {
            try await appState.client.updateConfig(
                config: config,
                apiKey: apiKey,
                values: ["terminal": terminalPatch]
            )
            statusMessage = "已保存并同步至 Hermes 服务端。"
            isError = false
            Haptics.success()
        } catch {
            statusMessage = (error as? HermesError)?.userMessage ?? "保存失败：\(error.localizedDescription)"
            isError = true
            Haptics.error()
        }
    }
}
