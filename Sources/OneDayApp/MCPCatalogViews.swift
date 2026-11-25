import OneDayDesign
import OneDayCore
import SwiftUI

/// MCP 目录面（§388 H7，总表 167）：服务端批准目录单源。
/// 统一原生 iOS 26 List(.insetGrouped) + SettingsHeroCard + ContentUnavailableView。
struct MCPCatalogView: View {
    @Environment(AppState.self) private var appState

    let facade: ConnectorsFacade

    @State private var detailEntry: MCPCatalogEntry?

    private var installable: [MCPCatalogEntry] {
        facade.catalogEntries.filter { !$0.installed }
    }

    private var installed: [MCPCatalogEntry] {
        facade.catalogEntries.filter(\.installed)
    }

    private var heroTone: SettingsStatusTone {
        if facade.catalogError != nil, facade.catalogEntries.isEmpty { return .error }
        if facade.isLoadingCatalog, facade.catalogEntries.isEmpty { return .neutral }
        return installed.isEmpty ? .neutral : .healthy
    }

    private var heroStatusText: String {
        if facade.isLoadingCatalog, facade.catalogEntries.isEmpty { return "读取中" }
        if facade.catalogError != nil, facade.catalogEntries.isEmpty { return "读取失败" }
        if facade.catalogEntries.isEmpty { return "暂无条目" }
        return "已装 \(installed.count)/\(facade.catalogEntries.count)"
    }

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "shippingbox.fill",
                tint: .teal,
                title: "MCP 目录",
                subtitle: "浏览服务器批准的 MCP 工具目录，查看运行详情并一键安装。",
                statusText: heroStatusText,
                statusTone: heroTone
            )

            if let notice = facade.catalogNotice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Palette.surface)
            }

            if facade.isLoadingCatalog, facade.catalogEntries.isEmpty {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取目录…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .listRowBackground(Palette.surface)
            } else if let catalogError = facade.catalogError,
                      facade.catalogEntries.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("目录读取失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(catalogError)
                    } actions: {
                        Button("重试") {
                            Task { await facade.loadCatalog(appState: appState) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OneDayMetrics.spacingM)
                }
                .listRowBackground(Color.clear)
            } else if facade.catalogEntries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "目录暂无内容",
                        systemImage: "shippingbox",
                        description: Text("服务器当前没有可展示的 MCP 目录条目。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OneDayMetrics.spacingL)
                }
                .listRowBackground(Color.clear)
            } else {
                if !installable.isEmpty {
                    Section {
                        ForEach(installable) { entry in
                            catalogRow(entry)
                        }
                    } header: {
                        SettingsSectionHeader("可安装（\(installable.count)）")
                    }
                    .listRowBackground(Palette.surface)
                }
                if !installed.isEmpty {
                    Section {
                        ForEach(installed) { entry in
                            catalogRow(entry)
                        }
                    } header: {
                        SettingsSectionHeader("已安装（\(installed.count)）")
                    }
                    .listRowBackground(Palette.surface)
                }
                if !facade.catalogDiagnostics.isEmpty {
                    Section {
                        ForEach(
                            Array(facade.catalogDiagnostics.enumerated()),
                            id: \.offset
                        ) { _, diagnostic in
                            Text(diagnostic.message.isEmpty
                                ? diagnostic.kind : diagnostic.message)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    } header: {
                        SettingsSectionHeader("目录诊断")
                    }
                    .listRowBackground(Palette.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("MCP 目录")
        .navigationBarTitleDisplayMode(.inline)
        .task { await facade.loadCatalog(appState: appState) }
        .refreshable { await facade.loadCatalog(appState: appState) }
        .sheet(item: $detailEntry) { entry in
            MCPCatalogDetailView(entry: entry, facade: facade)
        }
    }

    private func catalogRow(_ entry: MCPCatalogEntry) -> some View {
        Button {
            detailEntry = entry
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    if !entry.description.isEmpty {
                        Text(entry.description)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                SettingsStatusPill(
                    text: entry.stateLabel,
                    tone: entry.installed ? .healthy : .neutral
                )
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 详情/安装面

struct MCPCatalogDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let entry: MCPCatalogEntry
    let facade: ConnectorsFacade

    @State private var envValues: [String: String] = [:]
    @State private var enableOnInstall = true

    /// 实时条目：安装回读后以门面最新名单为准，不看打开时的旧快照
    private var liveEntry: MCPCatalogEntry {
        facade.catalogEntries.first { $0.name == entry.name } ?? entry
    }

    private var isInstalling: Bool {
        facade.installingCatalog.contains(entry.name)
    }

    private var requiredEnvMissing: Bool {
        liveEntry.requiredEnv.contains { spec in
            spec.required
                && (envValues[spec.name] ?? "")
                    .trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            List {
                SettingsHeroCard(
                    symbol: "shippingbox.fill",
                    tint: .teal,
                    title: liveEntry.name,
                    subtitle: liveEntry.description.isEmpty
                        ? "服务器批准的 MCP 工具服务"
                        : liveEntry.description,
                    statusText: liveEntry.stateLabel,
                    statusTone: liveEntry.installed ? .healthy : .neutral
                )

                Section {
                    SettingsValueRow(
                        symbol: liveEntry.installed ? "checkmark.circle" : "arrow.down.circle",
                        tint: liveEntry.installed ? .green : .gray,
                        title: "安装状态",
                        value: liveEntry.stateLabel
                    )
                    if let transport = liveEntry.transport, !transport.isEmpty {
                        SettingsValueRow(
                            symbol: "arrow.left.arrow.right",
                            tint: .teal,
                            title: "传输",
                            value: transport
                        )
                    }
                    if let authType = liveEntry.authType, !authType.isEmpty {
                        SettingsValueRow(
                            symbol: "lock.shield",
                            tint: .orange,
                            title: "鉴权",
                            value: authType
                        )
                    }
                } header: {
                    SettingsSectionHeader("服务概览")
                }
                .listRowBackground(Palette.surface)

                trustSection

                if !liveEntry.postInstall.isEmpty {
                    Section {
                        Text(liveEntry.postInstall)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    } header: {
                        SettingsSectionHeader("安装后说明")
                    }
                    .listRowBackground(Palette.surface)
                }

                if liveEntry.installed {
                    Section {
                        Text("已安装。在连接器「已连接」里可以启停和测试它。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .listRowBackground(Palette.surface)
                } else {
                    installSection
                }

                if let notice = facade.catalogNotice {
                    Section {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle(liveEntry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .fullscreenPopBridge()
    }

    /// 信任信息：命令/地址/自举步骤全量摊开（服务端信任模型要求用户装前能查实际要跑什么）
    @ViewBuilder
    private var trustSection: some View {
        let commandLine = liveEntry.commandLine
        let url = liveEntry.url
        let installUrl = liveEntry.installUrl
        if commandLine != nil || url != nil || installUrl != nil
            || !liveEntry.bootstrap.isEmpty {
            Section {
                if let commandLine {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("命令")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.inkSecondary)
                        Text(commandLine)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
                if let url, !url.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("地址")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.inkSecondary)
                        Text(url)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
                if let installUrl, !installUrl.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自举来源")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.inkSecondary)
                        Text(installLine(installUrl))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
                if !liveEntry.bootstrap.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自举步骤")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.inkSecondary)
                        ForEach(
                            Array(liveEntry.bootstrap.enumerated()),
                            id: \.offset
                        ) { _, step in
                            Text(step)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Palette.ink)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                SettingsSectionHeader("将要运行")
            }
            .listRowBackground(Palette.surface)
        }
    }

    private func installLine(_ url: String) -> String {
        if let ref = liveEntry.installRef, !ref.isEmpty {
            return "\(url) @ \(ref)"
        }
        return url
    }

    @ViewBuilder
    private var installSection: some View {
        if !liveEntry.requiredEnv.isEmpty {
            Section {
                ForEach(liveEntry.requiredEnv) { spec in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(envLabel(spec))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.ink)
                        if spec.looksSecret {
                            SecureField(spec.name, text: envBinding(spec))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            TextField(spec.name, text: envBinding(spec))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        if !spec.prompt.isEmpty {
                            Text(spec.prompt)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                SettingsSectionHeader("安装参数")
            }
            .listRowBackground(Palette.surface)
        }

        Section {
            Toggle("安装后启用", isOn: $enableOnInstall)
                .listRowBackground(Palette.surface)

            Button {
                Task { await install() }
            } label: {
                HStack {
                    Spacer()
                    if isInstalling {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 6)
                        Text("安装中…")
                            .font(.rowTitleL.weight(.semibold))
                            .foregroundStyle(.white)
                    } else {
                        Text(liveEntry.needsInstall ? "安装（后台自举）" : "安装")
                            .font(.rowTitleL.weight(.semibold))
                            .foregroundStyle(requiredEnvMissing ? Palette.inkSecondary : .white)
                    }
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            .disabled(isInstalling || requiredEnvMissing)
            .listRowBackground(
                isInstalling || requiredEnvMissing ? Palette.surface : Palette.primary
            )
        } footer: {
            if requiredEnvMissing {
                Text("标了「必填」的参数还没填。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func envLabel(_ spec: MCPCatalogEnvSpec) -> String {
        spec.required ? "\(spec.name)（必填）" : spec.name
    }

    private func envBinding(_ spec: MCPCatalogEnvSpec) -> Binding<String> {
        Binding(
            get: { envValues[spec.name] ?? "" },
            set: { envValues[spec.name] = $0 }
        )
    }

    /// 只带填了值的声明键（服务端对未声明键 400、本面只从声明清单取值，天然合规）
    private func install() async {
        var env: [String: String] = [:]
        for spec in liveEntry.requiredEnv {
            let value = (envValues[spec.name] ?? "")
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { env[spec.name] = value }
        }
        await facade.installCatalogEntry(
            liveEntry, env: env, enable: enableOnInstall, appState: appState
        )
        if liveEntry.installed {
            dismiss()
        }
    }
}
