import OneDayCore
import OneDayDesign
import SwiftUI

/// 连接器页（2026-11-27 重做）：iOS 原生 List(.insetGrouped)
/// 分两类呈现——①手机应用权限区（日历/提醒事项/通讯录等，
/// 显示 iOS 系统权限真实状态＋同步开关）；②MCP 服务区
/// （数据来自 GET /api/mcp/servers，显示启用状态＋工具数）。
/// 数据源：系统权限 API、DeviceSync 状态、服务端端点，经
/// ConnectorsFacade 门面统一。视觉规范：settingsBG 背景、
/// settingsRowHeight 行高、rowTitleL 行题、sectionLabel 分区头。
struct ConnectorsView: View {
    @Environment(AppState.self) private var appState

    @State private var facade = ConnectorsFacade()
    @State private var query = ""
    @State private var detailTarget: DetailTarget?

    private enum DetailTarget: Identifiable {
        case device(DeviceSourceID)
        case mcpServer(String)

        var id: String {
            switch self {
            case .device(let source): return "device-\(source.rawValue)"
            case .mcpServer(let name): return "mcp-\(name)"
            }
        }
    }

    private var rowInsets: EdgeInsets {
        OneDayMetrics.settingsRowInsets
    }

    var body: some View {
        List {
            deviceSection
            mcpSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("连接器")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索连接器"
        )
        .refreshable {
            await facade.refresh(appState: appState)
        }
        .task {
            await facade.refresh(appState: appState)
        }
        .sheet(item: $detailTarget) { target in
            detailSheet(for: target)
        }
    }

    // MARK: - 手机应用权限区

    /// 手机应用权限区：按数据源逐行（日历/提醒事项/通讯录/照片/步数/健康/家庭等），
    /// 每行呈现 iOS 系统权限的真实状态（系统 API 实时读）＋同步开关 Toggle
    /// （接现行 DeviceSync 真实状态，乐观更新＋失败回滚）
    @ViewBuilder
    private var deviceSection: some View {
        Section {
            ForEach(DeviceSourceDirectory.roster) { descriptor in
                deviceRow(descriptor)
            }
        } header: {
            Text("你的设备")
                .font(.sectionLabel)
                .foregroundStyle(Palette.inkSecondary)
                .textCase(nil)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    private func deviceRow(_ descriptor: DeviceSourceDescriptor) -> some View {
        let permission = appState.deviceSession.permissions[descriptor.sourceID] ?? .notDetermined
        let dataset = DeviceSyncDataset.fromSource(descriptor.sourceID)

        return Button {
            detailTarget = .device(descriptor.sourceID)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                // 图标：30pt，来自 descriptor.tileSymbol
                Image(systemName: descriptor.tileSymbol)
                    .font(.system(size: OneDayMetrics.iconSlot))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: OneDayMetrics.iconSlot, height: OneDayMetrics.iconSlot)

                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(descriptor.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)

                    HStack(spacing: OneDayMetrics.iconTextGap) {
                        permissionStatusMark(permission)
                        Text(permissionStatusText(permission))
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: OneDayMetrics.spacingS)

                // 同步开关：只在有 dataset 且权限允许时显示
                if let ds = dataset,
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
            OneDayMetrics.iconSlot + OneDayMetrics.spacingSM
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

    // MARK: - MCP 服务区

    /// MCP 服务区：数据只来自 GET /api/mcp/servers 实时读——每行服务名＋
    /// 启用状态 Toggle（PUT /api/mcp/servers/:name/enabled，乐观更新＋
    /// 失败回滚）＋工具数（端点返回的 tools 字段）
    @ViewBuilder
    private var mcpSection: some View {
        Section {
            if facade.isLoadingServers && facade.servers.isEmpty {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("读取中...")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } else if let error = facade.serversError, facade.servers.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } else if facade.servers.isEmpty {
                ContentUnavailableView(
                    "暂无 MCP 服务",
                    systemImage: "puzzlepiece.extension",
                    description: Text("下拉刷新以查看可用服务")
                )
            } else {
                ForEach(facade.servers) { server in
                    mcpServerRow(server)
                }
            }
        } header: {
            Text("MCP 服务")
                .font(.sectionLabel)
                .foregroundStyle(Palette.inkSecondary)
                .textCase(nil)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    private func mcpServerRow(_ server: MCPServerItem) -> some View {
        let testResult = facade.testResults[server.name]
        let toolCount = server.tools ?? testResult?.toolCount ?? 0
        let isToggling = facade.toggling.contains(server.name)

        return Button {
            detailTarget = .mcpServer(server.name)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                // 图标：30pt
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: OneDayMetrics.iconSlot))
                    .foregroundStyle(server.enabled ? Palette.primary : Palette.inkSecondary)
                    .frame(width: OneDayMetrics.iconSlot, height: OneDayMetrics.iconSlot)

                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(server.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)

                    HStack(spacing: OneDayMetrics.iconTextGap) {
                        Circle()
                            .fill(server.enabled ? Palette.success : Palette.inkSecondary)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)

                        if toolCount > 0 {
                            Text("\(server.enabled ? "已启用" : "已停用") · \(toolCount) 工具")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        } else {
                            Text(server.enabled ? "已启用" : "已停用")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: OneDayMetrics.spacingS)

                // 启用开关
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
            OneDayMetrics.iconSlot + OneDayMetrics.spacingSM
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
        }
    }
}

// MARK: - MCP Server Detail View (Placeholder)

private struct MCPServerDetailView: View {
    let server: MCPServerItem
    let facade: ConnectorsFacade
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("名称", value: server.name)
                    LabeledContent("传输方式", value: server.transport)
                    if let url = server.url {
                        LabeledContent("地址", value: url)
                    }
                    LabeledContent("状态", value: server.enabled ? "已启用" : "已停用")
                } header: {
                    Text("基本信息")
                }

                Section {
                    Button("测试连接") {
                        Task {
                            await facade.test(server, appState: appState)
                        }
                    }
                }
            }
            .navigationTitle(server.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}
