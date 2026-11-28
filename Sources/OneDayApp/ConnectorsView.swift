import OneDayCore
import OneDayDesign
import SwiftUI

/// 连接器页（大厂标杆重构版）：
/// - 严格分层：①「你的设备」（iOS 本机权限 + 按需同步开关）②「已接 MCP 服务」③「可安装的 MCP 目录」；
/// - 修复 `.searchable` 搜索：跨三段实时过滤，无结果给原生 `ContentUnavailableView.search`；
/// - 图标严格合规：统一 36×36 连续圆角 + `.hierarchical` SF Symbol 语义色块（零 Apple 原生 App 图标）；
/// - 替换原 `MCPServerDetailView` 占位视图，完整呈现连接测试结果、工具数、来源与协议元数据；
/// - 暴露 `ConnectorsFacade` 已有的 MCP 目录一键安装与环境变量表单。
struct ConnectorsView: View {
    @Environment(AppState.self) private var appState

    @State private var facade = ConnectorsFacade()
    @State private var query = ""
    @State private var detailTarget: DetailTarget?

    private enum DetailTarget: Identifiable {
        case device(DeviceSourceID)
        case mcpServer(String)
        case catalogEntry(MCPCatalogEntry)

        var id: String {
            switch self {
            case .device(let source): return "device-\(source.rawValue)"
            case .mcpServer(let name): return "mcp-\(name)"
            case .catalogEntry(let entry): return "catalog-\(entry.name)"
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredDevices: [DeviceSourceDescriptor] {
        let roster = DeviceSourceDirectory.roster
        guard !trimmedQuery.isEmpty else { return roster }
        let needle = trimmedQuery.lowercased()
        return roster.filter { descriptor in
            descriptor.name.lowercased().contains(needle)
                || descriptor.sourceID.rawValue.lowercased().contains(needle)
        }
    }

    private var filteredServers: [MCPServerItem] {
        guard !trimmedQuery.isEmpty else { return facade.servers }
        let needle = trimmedQuery.lowercased()
        return facade.servers.filter { server in
            server.name.lowercased().contains(needle)
                || (server.url?.lowercased().contains(needle) ?? false)
                || (server.command?.lowercased().contains(needle) ?? false)
                || (server.plugin?.lowercased().contains(needle) ?? false)
        }
    }

    private var filteredCatalogEntries: [MCPCatalogEntry] {
        let entries = facade.catalogEntries.filter { !$0.installed }
        guard !trimmedQuery.isEmpty else { return entries }
        let needle = trimmedQuery.lowercased()
        return entries.filter { entry in
            entry.name.lowercased().contains(needle)
                || entry.description.lowercased().contains(needle)
                || (entry.connectorSlug?.lowercased().contains(needle) ?? false)
        }
    }

    private var hasAnySearchMatch: Bool {
        !filteredDevices.isEmpty
            || !filteredServers.isEmpty
            || !filteredCatalogEntries.isEmpty
    }

    private var rowInsets: EdgeInsets {
        OneDayMetrics.settingsRowInsets
    }

    var body: some View {
        List {
            if let notice = facade.catalogNotice ?? facade.notice {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Palette.primary)
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 4)
                        Button {
                            facade.catalogNotice = nil
                            facade.notice = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, OneDayMetrics.spacingS)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(rowInsets)
            }

            if !trimmedQuery.isEmpty && !hasAnySearchMatch {
                ContentUnavailableView.search(text: trimmedQuery)
                    .listRowBackground(Color.clear)
            } else {
                if !filteredDevices.isEmpty {
                    deviceSection
                }
                if trimmedQuery.isEmpty || !filteredServers.isEmpty {
                    mcpSection
                }
                if trimmedQuery.isEmpty || !filteredCatalogEntries.isEmpty {
                    catalogSection
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("连接器")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索本机权限或 MCP 服务"
        )
        .refreshable {
            async let base: Void = facade.refresh(appState: appState)
            async let catalog: Void = facade.loadCatalog(appState: appState)
            _ = await (base, catalog)
        }
        .task {
            async let base: Void = facade.refresh(appState: appState)
            async let catalog: Void = facade.loadCatalog(appState: appState)
            _ = await (base, catalog)
        }
        .sheet(item: $detailTarget) { target in
            detailSheet(for: target)
        }
    }

    // MARK: - 36×36 合规 SF Symbol 语义色块（零 Apple 原生 App 图标）

    private func connectorTile(
        symbol: String,
        tint: Color,
        ink: Color
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(ink)
            .frame(width: 36, height: 36)
            .background(
                tint,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusTile,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
    }

    private func deviceTileStyle(for sourceID: DeviceSourceID) -> (tint: Color, ink: Color) {
        let index = abs(sourceID.rawValue.hashValue) % 4
        switch index {
        case 0: return (Palette.tintSky, Palette.tintSkyInk)
        case 1: return (Palette.tintGreen, Palette.tintGreenInk)
        case 2: return (Palette.tintLavender, Palette.tintLavenderInk)
        default: return (Palette.tintOrange, Palette.tintOrangeInk)
        }
    }

    // MARK: - 手机应用权限区

    @ViewBuilder
    private var deviceSection: some View {
        Section {
            ForEach(filteredDevices) { descriptor in
                deviceRow(descriptor)
            }
        } header: {
            Text("你的设备")
                .font(.sectionLabel)
                .foregroundStyle(Palette.inkSecondary)
                .textCase(nil)
        } footer: {
            Text("仅在你开启对应开关后，Hermes 才会按需读取本机数据；已拒绝的权限需前往系统设置重新开启。")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    private func deviceRow(_ descriptor: DeviceSourceDescriptor) -> some View {
        let permission = appState.deviceSession.permissions[descriptor.sourceID] ?? .notDetermined
        let dataset = DeviceSyncDataset.fromSource(descriptor.sourceID)
        let style = deviceTileStyle(for: descriptor.sourceID)
        let metric = facade.deviceMetrics[descriptor.sourceID]

        return Button {
            detailTarget = .device(descriptor.sourceID)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                connectorTile(
                    symbol: descriptor.tileSymbol,
                    tint: style.tint,
                    ink: style.ink
                )

                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(descriptor.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)

                    HStack(spacing: OneDayMetrics.iconTextGap) {
                        permissionStatusMark(permission)
                        if let metric, !metric.isEmpty {
                            Text("\(permissionStatusText(permission)) · \(metric)")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        } else {
                            Text(permissionStatusText(permission))
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: OneDayMetrics.spacingS)

                if dataset != nil,
                   DeviceSyncControl.agentCanQuery(permission: permission) {
                    let syncEnabled = appState.deviceSession.agentCallEnabled[descriptor.sourceID] ?? false
                    Toggle("同步", isOn: Binding(
                        get: { syncEnabled },
                        set: { newValue in
                            appState.deviceSession.setAgentCallEnabled(descriptor.sourceID, newValue)
                        }
                    ))
                    .labelsHidden()
                } else {
                    DisclosureChevron(font: .footnote.weight(.semibold))
                }
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            36 + OneDayMetrics.spacingSM
        }
    }

    @ViewBuilder
    private func permissionStatusMark(_ permission: DevicePermissionState) -> some View {
        let color: Color = {
            switch permission {
            case .granted, .limited, .writeOnly, .notApplicable:
                return Palette.success
            case .denied, .restricted:
                return Palette.danger
            case .notDetermined:
                return Palette.inkSecondary
            }
        }()

        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private func permissionStatusText(_ permission: DevicePermissionState) -> String {
        switch permission {
        case .granted: return "已授权"
        case .limited: return "部分授权"
        case .writeOnly: return "仅写入"
        case .denied: return "已拒绝"
        case .restricted: return "受限"
        case .notDetermined: return "未询问"
        case .notApplicable: return "无需权限"
        }
    }

    // MARK: - 已接 MCP 服务区

    @ViewBuilder
    private var mcpSection: some View {
        Section {
            if facade.isLoadingServers && facade.servers.isEmpty {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                        .controlSize(.small)
                    Text("读取 MCP 服务中…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } else if let error = facade.serversError, facade.servers.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } else if filteredServers.isEmpty {
                ContentUnavailableView(
                    "暂无已接 MCP 服务",
                    systemImage: "puzzlepiece.extension",
                    description: Text("可以从下方官方目录一键安装，或下拉刷新同步。")
                )
            } else {
                ForEach(filteredServers) { server in
                    mcpServerRow(server)
                }
            }
        } header: {
            Text("云端与 MCP 服务")
                .font(.sectionLabel)
                .foregroundStyle(Palette.inkSecondary)
                .textCase(nil)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    private func mcpServerRow(_ server: MCPServerItem) -> some View {
        let testResult = facade.testResults[server.name]
        let toolCount = facade.cachedToolCounts[server.name]
            ?? testResult?.toolCount
            ?? server.tools
            ?? 0
        let isToggling = facade.toggling.contains(server.name)

        return Button {
            detailTarget = .mcpServer(server.name)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                connectorTile(
                    symbol: server.transport == "http" ? "globe" : "puzzlepiece.extension.fill",
                    tint: server.enabled ? Palette.tintSky : Palette.fillTertiary,
                    ink: server.enabled ? Palette.tintSkyInk : Palette.inkSecondary
                )

                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(server.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)

                    HStack(spacing: OneDayMetrics.iconTextGap) {
                        Circle()
                            .fill(server.enabled ? Palette.success : Palette.inkSecondary)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)

                        Text(mcpStatusSummary(server: server, toolCount: toolCount))
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: OneDayMetrics.spacingS)

                if isToggling {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Toggle("启用", isOn: Binding(
                        get: { server.enabled },
                        set: { newValue in
                            Task {
                                await facade.setEnabled(server, to: newValue, appState: appState)
                            }
                        }
                    ))
                    .labelsHidden()
                }
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            36 + OneDayMetrics.spacingSM
        }
    }

    private func mcpStatusSummary(server: MCPServerItem, toolCount: Int) -> String {
        var parts = [server.enabled ? "已启用" : "已停用"]
        if toolCount > 0 {
            parts.append("\(toolCount) 工具")
        }
        if let transport = server.transport, !transport.isEmpty {
            parts.append(transport.uppercased())
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 可安装的 MCP 目录（服务端官方目录单源）

    @ViewBuilder
    private var catalogSection: some View {
        Section {
            if facade.isLoadingCatalog && facade.catalogEntries.isEmpty {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                        .controlSize(.small)
                    Text("读取可安装目录中…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } else if let error = facade.catalogError, facade.catalogEntries.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } else if filteredCatalogEntries.isEmpty {
                Text("官方目录里的常用 MCP 服务均已安装")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(minHeight: 44)
            } else {
                ForEach(filteredCatalogEntries) { entry in
                    catalogRow(entry)
                }
            }
        } header: {
            Text("可安装的 MCP 目录")
                .font(.sectionLabel)
                .foregroundStyle(Palette.inkSecondary)
                .textCase(nil)
        } footer: {
            Text("基于 Hermes 服务端官方 MCP 目录安装；安装前可查看完整启动命令、接口地址与所需环境变量。")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    private func catalogRow(_ entry: MCPCatalogEntry) -> some View {
        let isInstalling = facade.installingCatalog.contains(entry.name)

        return Button {
            detailTarget = .catalogEntry(entry)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                connectorTile(
                    symbol: entry.transport == "http" ? "link" : "shippingbox.fill",
                    tint: Palette.tintLavender,
                    ink: Palette.tintLavenderInk
                )

                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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

                if isInstalling {
                    ProgressView().controlSize(.small)
                } else {
                    Text("获取")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Palette.primaryTint, in: Capsule())
                }
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .disabled(isInstalling)
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            36 + OneDayMetrics.spacingSM
        }
    }

    // MARK: - 详情页

    @ViewBuilder
    private func detailSheet(for target: DetailTarget) -> some View {
        switch target {
        case .device(let sourceID):
            DeviceDetailDestination(
                source: sourceID,
                inSheet: true
            )
        case .mcpServer(let name):
            if let server = facade.servers.first(where: { $0.name == name }) {
                MCPServerDetailView(
                    server: server,
                    facade: facade,
                    appState: appState
                )
            }
        case .catalogEntry(let entry):
            MCPCatalogInstallSheet(
                entry: entry,
                facade: facade,
                appState: appState
            )
        }
    }
}

// MARK: - MCP 服务详情页（真实测试结果、工具数、协议元数据与开关）

private struct MCPServerDetailView: View {
    let server: MCPServerItem
    let facade: ConnectorsFacade
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var currentServer: MCPServerItem {
        facade.servers.first(where: { $0.name == server.name }) ?? server
    }

    private var testResult: MCPTestResult? {
        facade.testResults[server.name]
    }

    private var isTesting: Bool {
        facade.testing.contains(server.name)
    }

    private var toolCount: Int? {
        facade.cachedToolCounts[server.name]
            ?? testResult?.toolCount
            ?? currentServer.tools
    }

    var body: some View {
        NavigationStack {
            List {
                Section("服务概览") {
                    LabeledContent("名称", value: currentServer.name)
                    LabeledContent("来源", value: currentServer.originLabel)
                    if let transport = currentServer.transport, !transport.isEmpty {
                        LabeledContent("传输协议", value: transport.uppercased())
                    }
                    if let endpoint = currentServer.endpointLine {
                        LabeledContent("端点 / 命令") {
                            Text(endpoint)
                                .font(.footnote.monospaced())
                                .foregroundStyle(Palette.inkSecondary)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                    if let toolCount {
                        LabeledContent("可用工具数", value: "\(toolCount) 个")
                    }
                    Toggle("启用此连接器", isOn: Binding(
                        get: { currentServer.enabled },
                        set: { newValue in
                            Task {
                                await facade.setEnabled(
                                    currentServer, to: newValue, appState: appState
                                )
                            }
                        }
                    ))
                    .disabled(facade.toggling.contains(currentServer.name))
                }

                Section("连通性测试") {
                    Button {
                        Task {
                            await facade.test(currentServer, appState: appState)
                        }
                    } label: {
                        HStack {
                            Label("立即测试连接", systemImage: "bolt.horizontal.circle")
                            Spacer()
                            if isTesting {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isTesting)

                    if let result = testResult {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: result.succeeded
                                      ? "checkmark.circle.fill"
                                      : "xmark.circle.fill")
                                    .foregroundStyle(result.succeeded ? Palette.success : Palette.danger)
                                Text(result.succeeded ? "连接正常" : "测试未通过")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(result.succeeded ? Palette.successText : Palette.danger)
                                if let count = result.toolCount {
                                    Text("· 发现 \(count) 个工具")
                                        .font(.footnote)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                            }
                            if let msg = result.displayMessage, !msg.isEmpty {
                                Text(msg)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(currentServer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - MCP 目录安装表（透明展示命令/地址 + 必填环境变量表单）

private struct MCPCatalogInstallSheet: View {
    let entry: MCPCatalogEntry
    let facade: ConnectorsFacade
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var envValues: [String: String] = [:]
    @State private var enableAfterInstall = true

    private var isInstalling: Bool {
        facade.installingCatalog.contains(entry.name)
    }

    private var canInstall: Bool {
        for spec in entry.requiredEnv where spec.required {
            let value = envValues[spec.name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty { return false }
        }
        return !isInstalling
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("服务说明") {
                    if !entry.description.isEmpty {
                        Text(entry.description)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                    }
                    if let transport = entry.transport, !transport.isEmpty {
                        LabeledContent("传输协议", value: transport.uppercased())
                    }
                    if let url = entry.url, !url.isEmpty {
                        LabeledContent("接口地址") {
                            Text(url)
                                .font(.caption.monospaced())
                                .foregroundStyle(Palette.inkSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let cmd = entry.commandLine {
                        LabeledContent("启动命令") {
                            Text(cmd)
                                .font(.caption.monospaced())
                                .foregroundStyle(Palette.inkSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if !entry.requiredEnv.isEmpty {
                    Section("所需凭据与环境变量") {
                        ForEach(entry.requiredEnv) { spec in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(spec.name)
                                        .font(.caption.monospaced().weight(.semibold))
                                        .foregroundStyle(Palette.ink)
                                    if spec.required {
                                        Text("必填")
                                            .font(.caption2)
                                            .foregroundStyle(Palette.danger)
                                    }
                                }
                                if !spec.prompt.isEmpty {
                                    Text(spec.prompt)
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                let binding = Binding<String>(
                                    get: { envValues[spec.name] ?? "" },
                                    set: { envValues[spec.name] = $0 }
                                )
                                if spec.looksSecret {
                                    SecureField("输入 \(spec.name)", text: binding)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                } else {
                                    TextField("输入 \(spec.name)", text: binding)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    Toggle("安装后立即启用", isOn: $enableAfterInstall)
                }
            }
            .navigationTitle("安装 \(entry.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isInstalling ? "安装中…" : "安装") {
                        Task {
                            let cleaned = envValues
                                .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.value.isEmpty }
                            await facade.installCatalogEntry(
                                entry,
                                env: cleaned,
                                enable: enableAfterInstall,
                                appState: appState
                            )
                            dismiss()
                        }
                    }
                    .disabled(!canInstall)
                }
            }
        }
    }
}
