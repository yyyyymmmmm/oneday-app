import OneDayCore
import OneDayDesign
import SwiftUI

/// 连接器目录页（0.28.0，用户 10:32 对标 Muse 连接
/// 器页令；设置「MCP 连接」升级）：页顶搜索（系统
/// searchable）＋已连接/可连接分段＋分类分组卡。
/// 第一纪律＝状态真实（Core ConnectorCatalog 口径）：
/// 「已连接」只来自 GET /api/mcp/servers 的实时读
/// 取——与既有 MCP 页同一条数据链、不另造状态口
/// 径；2026-11-10 实查在册仅 box（Simular 官方插件
/// 预置、enabled）。「可连接」是静态目录八家，全标
/// 未接入＋接入路径，**不设假连接按钮**：行尾只有
/// 「未接入」状态字，点开详情 sheet 看接入说明。
/// 已连接条目的详情保留真实操作（启停 PUT、连接测
/// 试 POST，沿旧 MCP 页语义：乐观更新＋失败回滚、
/// 回执无显式成功信号不判成功）。页面规范遵
/// 0.24.0 定版＋0.26.0 设置语言：List(.insetGrouped)
/// ＋settingsBG＋行题 Body 17（rowTitleL）＋分区头
/// Footnote 13（sectionLabel）＋行高 settingsRowHeight。
///
/// 0.29.0 补组（用户 12:30 点名、12:31 拍板）：顶部
/// 第一组「本机服务」——自家的四条线（Hermes 本体/
/// 记忆与技能审批桥/目标与点子/总览数据）补上名分
/// 与状态。0.28.0 时内部桥以「自身设施」为由不列，
/// 用户口径是它们同样要能在目录里看到通断。状态进
/// 页实时探活（各桥既有客户端的只读 GET、与功能页
/// 同源同钥匙），不缓存上次结果冒充实时；电脑
/// （Simular Box）留在已连接组原位、本组不重复列
/// （box-bridge 是电脑页的内部设施、同样不列）。
struct ConnectorsView: View {
    @Environment(AppState.self) private var appState

    /// 总览入口（设置页注入）：本机服务「总览数据」
    /// 详情的跳转闭包——总览 sheet 的承载在设置页
    /// 管理组，本页不另立第二份
    var onOpenOverview: (() -> Void)? = nil

    @State private var servers: [MCPServerItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var notice: String?
    @State private var toggling: Set<String> = []
    @State private var testing: Set<String> = []
    @State private var testResults: [String: MCPTestResult] = [:]
    @State private var query = ""
    @State private var segment: Segment = .connected
    @State private var detailTarget: DetailTarget?

    // 本机服务探活（0.29.0）：状态字典进页首帧全为
    // 读取中、探活回来逐条落定；客户端与各功能页同
    // 一批类（WriteGateClient/OneDayBridgeClient/
    // OverviewBridgeClient/MemoryBridgeClient），基
    // 址与钥匙全走既有 ServerConfig＋Keychain 单源
    @State private var localStates: [LocalServiceID: LocalServiceProbeState] = [:]
    @State private var localProbing = false
    @State private var lastProbeAt: Date?
    @State private var gateSnapshot: WriteGateStatus?
    @State private var overviewGeneratedAt: String?
    private let writeGateClient = WriteGateClient()
    private let oneDayBridgeClient = OneDayBridgeClient()
    private let overviewBridgeClient = OverviewBridgeClient()
    private let memoryBridgeClient = MemoryBridgeClient()

    private enum Segment: String, CaseIterable, Identifiable {
        case connected = "已连接"
        case available = "可连接"
        var id: String { rawValue }
    }

    private enum DetailTarget: Identifiable {
        case connected(String)
        case catalog(String)
        case local(LocalServiceID)
        case device(DeviceSourceID)
        var id: String {
            switch self {
            case .connected(let name): return "c-\(name)"
            case .catalog(let id): return "a-\(id)"
            case .local(let service): return "l-\(service.rawValue)"
            case .device(let source): return "d-\(source.rawValue)"
            }
        }
    }

    // 本机连接器（0.34.0 批一）：目录行读数（本地现读
    // 的一句数：今天日程数/未完成提醒数；取不到不拼）
    @State private var deviceMetrics: [DeviceSourceID: String] = [:]

    private var connected: [ConnectedConnector] {
        ConnectorDirectory.connectedEntries(from: servers)
    }

    private var available: [ConnectorCatalogEntry] {
        ConnectorDirectory.availableEntries(connected: connected)
    }

    private var searching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }

    var body: some View {
        List {
            if searching {
                searchSections
            } else {
                localSection
                deviceSection
                segmentSection
                if segment == .connected {
                    connectedSections
                } else {
                    catalogSections
                }
            }
            if let notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(rowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
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
            await load()
            await probeLocals()
            await probeDevices()
        }
        .task {
            await load()
            await probeLocals()
            await probeDevices()
        }
        .sheet(item: $detailTarget) { target in
            detailSheet(for: target)
        }
    }

    private func headerText(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
    }

    // MARK: - 分段

    private var segmentSection: some View {
        Section {
            Picker("连接器分组", selection: $segment) {
                ForEach(Segment.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(
            EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20)
        )
    }

    // MARK: - 本机服务（0.29.0 补组，进页实时探活）

    /// 本机服务组：恒在目录顶部第一组（分组序：本
    /// 机服务→已连接→可连接）；四条全列、状态随探
    /// 活逐条落定，读取中也占行不塌组
    private var localSection: some View {
        Section {
            ForEach(LocalServiceDirectory.roster) { descriptor in
                localRow(descriptor)
            }
        } header: {
            headerText("本机服务")
        } footer: {
            Text("这台服务器自家的线，状态是打开页面时当场检查的；电脑（Simular Box）是 MCP 连接、在下方「已连接」里，本组不重复列。")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    private func localRow(
        _ descriptor: LocalServiceDescriptor
    ) -> some View {
        let state = localStates[descriptor.serviceID] ?? .loading
        return Button {
            detailTarget = .local(descriptor.serviceID)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                ConnectorIconView(
                    spec: .symbol(descriptor.symbolName), size: 40
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 5) {
                        localStatusMark(state)
                        Text(state.subline)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    /// 状态点：正常绿/异常红/未配置灰；读取中是小转
    /// 圈（不用灰点冒充已探）
    @ViewBuilder
    private func localStatusMark(
        _ state: LocalServiceProbeState
    ) -> some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .up:
            Circle()
                .fill(Palette.success)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        case .down:
            Circle()
                .fill(Palette.danger)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        case .notConfigured:
            Circle()
                .fill(Palette.inkSecondary)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        }
    }

    // MARK: - 你的设备（0.34.0 批一，本机连接器）

    /// 设备组状态行字典（目录行与搜索共用一处映射）
    private var deviceStatusLines: [DeviceSourceID: String] {
        var lines: [DeviceSourceID: String] = [:]
        for descriptor in DeviceSourceDirectory.roster {
            lines[descriptor.sourceID] = DeviceRowStatus.line(
                descriptor: descriptor,
                permission: appState.deviceSession
                    .permissions[descriptor.sourceID] ?? .notDetermined,
                agentCallEnabled: appState.deviceSession
                    .agentCallEnabled[descriptor.sourceID] ?? false,
                metric: deviceMetrics[descriptor.sourceID]
            )
        }
        return lines
    }

    /// 你的设备组：恒显（在本机服务之后、分段控件之
    /// 前——两组都是「自家的东西」，与 MCP 的已连接/
    /// 可连接语义无关，不被分段切换藏掉，设计档
    /// §6.1）。批一三件可点进详情；健康/家庭待签名
    /// 权益，行在、状态如实、无假入口
    private var deviceSection: some View {
        Section {
            ForEach(DeviceSourceDirectory.roster) { descriptor in
                deviceRow(descriptor)
            }
        } header: {
            headerText("你的设备")
        } footer: {
            Text("这台手机自家的数据：授权与数据都留在手机上，智能体被问到时才现读现回、服务器不存副本。健康与家庭还差系统签名权益，开通前只列名。")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    @ViewBuilder
    private func deviceRow(
        _ descriptor: DeviceSourceDescriptor
    ) -> some View {
        let status = deviceStatusLines[descriptor.sourceID] ?? ""
        if descriptor.isWired {
            Button {
                detailTarget = .device(descriptor.sourceID)
            } label: {
                deviceRowLabel(descriptor, status: status, chevron: true)
            }
            .buttonStyle(.odPressable)
        } else {
            deviceRowLabel(descriptor, status: status, chevron: false)
        }
    }

    private func deviceRowLabel(
        _ descriptor: DeviceSourceDescriptor, status: String,
        chevron: Bool
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            DeviceSymbolTile(
                symbol: descriptor.tileSymbol,
                colorHex: descriptor.tileColorHex, size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.name)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .contentShape(Rectangle())
    }

    /// 设备读数（本地现读，进页/下拉时算）：日历＝今
    /// 天日程数、提醒＝未完成数；通讯录全量计数要整
    /// 表枚举、不为一行读数付这个成本，取不到就不拼
    private func probeDevices() async {
        appState.deviceSession.refreshPermissions()
        let controller = appState.deviceSession
        var metrics: [DeviceSourceID: String] = [:]
        if (controller.permissions[.calendar] ?? .notDetermined).isUsable {
            let count = controller.dispatcher.events.todayEventCount()
            metrics[.calendar] = "今天 \(count) 个日程"
        }
        if (controller.permissions[.reminders] ?? .notDetermined).isUsable {
            let items = await controller.dispatcher.events.reminderItems()
            let open = items.filter { !$0.isCompleted }.count
            metrics[.reminders] = "\(open) 项未完成"
        }
        deviceMetrics = metrics
    }

    // MARK: - 已连接（实查数据链）

    @ViewBuilder
    private var connectedSections: some View {
        if isLoading && servers.isEmpty {
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取服务端连接…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)
        } else if let errorMessage, servers.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                }
                .padding(.vertical, OneDayMetrics.spacingS)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)
        } else if connected.isEmpty {
            Section {
                EmptyState(
                    icon: "cable.connector",
                    title: "还没有已连接的服务",
                    message: "服务端尚未配置任何 MCP 连接。在电脑上给 Hermes 配置后会显示在这里。"
                )
                .padding(.vertical, OneDayMetrics.spacingM)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)
        } else {
            Section {
                ForEach(connected) { entry in
                    connectedRow(entry)
                }
            } header: {
                headerText("已连接 · \(connected.count)")
            } footer: {
                Text("状态来自服务端实时读取（MCP 服务器列表），与服务器实际配置一致；读取失败不会拿旧数据冒充。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)
        }
    }

    private func connectedRow(_ entry: ConnectedConnector) -> some View {
        Button {
            detailTarget = .connected(entry.id)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                ConnectorIconView(spec: entry.iconSpec, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(
                                entry.server.enabled
                                    ? Palette.success : Palette.inkSecondary
                            )
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(entry.statusLabel)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    // MARK: - 可连接（静态目录）

    @ViewBuilder
    private var catalogSections: some View {
        ForEach(ConnectorDirectory.grouped(available)) { group in
            Section {
                ForEach(group.entries) { entry in
                    catalogRow(entry)
                }
            } header: {
                headerText(group.category.rawValue)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)
        }
        Section {
            Text("以上服务尚未接入。点开条目可看各自的接入路径——接入需逐家在服务器端配置并完成授权，App 内暂不提供一键连接。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(rowInsets)
    }

    private func catalogRow(_ entry: ConnectorCatalogEntry) -> some View {
        Button {
            detailTarget = .catalog(entry.id)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                ConnectorIconView(spec: entry.iconSpec, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(entry.blurb)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Text("未接入")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    // MARK: - 搜索（跨两段真过滤）

    @ViewBuilder
    private var searchSections: some View {
        let hitLocal = LocalServiceProbeMapping.filtered(
            states: localStates, query: query
        )
        let hitDevices = DeviceRowStatus.filtered(
            statusLines: deviceStatusLines, query: query
        )
        let hitConnected = ConnectorDirectory.filteredConnected(
            connected, query: query
        )
        let hitCatalog = ConnectorDirectory.filteredCatalog(
            available, query: query
        )
        if hitLocal.isEmpty && hitDevices.isEmpty
            && hitConnected.isEmpty && hitCatalog.isEmpty {
            Section {
                EmptyState(
                    icon: "magnifyingglass",
                    title: "没有匹配的连接器",
                    message: "换个关键词试试，可按名称、分类或说明搜索。"
                )
                .padding(.vertical, OneDayMetrics.spacingM)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(rowInsets)
        } else {
            if !hitLocal.isEmpty {
                Section {
                    ForEach(hitLocal) { descriptor in
                        localRow(descriptor)
                    }
                } header: {
                    headerText("本机服务")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(rowInsets)
            }
            if !hitDevices.isEmpty {
                Section {
                    ForEach(hitDevices) { descriptor in
                        deviceRow(descriptor)
                    }
                } header: {
                    headerText("你的设备")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(rowInsets)
            }
            if !hitConnected.isEmpty {
                Section {
                    ForEach(hitConnected) { entry in
                        connectedRow(entry)
                    }
                } header: {
                    headerText("已连接")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(rowInsets)
            }
            ForEach(ConnectorDirectory.grouped(hitCatalog)) { group in
                Section {
                    ForEach(group.entries) { entry in
                        catalogRow(entry)
                    }
                } header: {
                    headerText(group.category.rawValue)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(rowInsets)
            }
        }
    }

    // MARK: - 详情 sheet

    @ViewBuilder
    private func detailSheet(for target: DetailTarget) -> some View {
        switch target {
        case .connected(let name):
            if let entry = connected.first(where: { $0.id == name }) {
                NavigationStack {
                    connectedDetail(entry)
                }
            }
        case .catalog(let id):
            if let entry = ConnectorDirectory.catalog
                .first(where: { $0.id == id }) {
                NavigationStack {
                    catalogDetail(entry)
                }
            }
        case .local(let serviceID):
            NavigationStack {
                localDetail(
                    LocalServiceDirectory.descriptor(serviceID)
                )
            }
        case .device(let source):
            NavigationStack {
                deviceDetail(source)
            }
        }
    }

    /// 设备详情分发（批一三件；批二两件无详情、不点入）
    @ViewBuilder
    private func deviceDetail(_ source: DeviceSourceID) -> some View {
        switch source {
        case .calendar: CalendarDetailView()
        case .reminders: RemindersDetailView()
        case .contacts: ContactsDetailView()
        case .health, .home: EmptyView()
        }
    }

    private func sheetHeader(
        spec: ConnectorIconSpec, name: String, subline: String
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            ConnectorIconView(spec: spec, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(subline)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(title)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    /// 已连接详情：状态与证据如实列全，启停/测试沿
    /// 旧 MCP 页的真实操作（不新造语义）
    private func connectedDetail(_ entry: ConnectedConnector) -> some View {
        let server = entry.server
        return List {
            Section {
                sheetHeader(
                    spec: entry.iconSpec,
                    name: entry.displayName, subline: entry.blurb
                )
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)

            Section {
                detailRow("连接状态", entry.statusLabel)
                detailRow("证据档位", entry.evidence.label)
                detailRow("来源", server.originLabel)
                detailRow("传输方式", transportLabel(server))
                if let endpoint = server.endpointLine {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("连接地址")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text(endpoint)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.inkSecondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, OneDayMetrics.spacingS)
                }
            } header: {
                headerText("状态")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)

            Section {
                Toggle("启用", isOn: toggleBinding(for: server))
                    .font(.rowTitleL)
                    .disabled(toggling.contains(server.name))
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Button("测试连接") {
                        Task { await test(server) }
                    }
                    .buttonStyle(.odSecondary)
                    .disabled(testing.contains(server.name))
                    if testing.contains(server.name) {
                        ProgressView()
                    } else if let result = testResults[server.name] {
                        HStack(spacing: 4) {
                            Image(
                                systemName: result.succeeded
                                    ? "checkmark.circle.fill"
                                    : "xmark.circle.fill"
                            )
                            .font(.system(size: 13))
                            .foregroundStyle(
                                result.succeeded
                                    ? Palette.success : Palette.danger
                            )
                            .accessibilityHidden(true)
                            Text(resultLine(result))
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } header: {
                headerText("操作")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.0（宪法 §5／审计 C9）：撤居中标题栏与
        // 手写关闭——sheetHeader 内容领头、关闭走系
        // 统下拉手势，不再双份呈现
    }

    /// 可连接详情：只有状态与接入说明，没有任何
    /// 形似连接的按钮——未接入就直说未接入
    private func catalogDetail(_ entry: ConnectorCatalogEntry) -> some View {
        List {
            Section {
                sheetHeader(
                    spec: entry.iconSpec,
                    name: entry.name, subline: entry.blurb
                )
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)

            // 0.36.0（§5／C9）：原分区头「状态」与首
            // 行行题「状态」同词重复——去分区头，行
            // 本身即状态呈现
            Section {
                detailRow("状态", "未接入")
                detailRow("分类", entry.category.rawValue)
                detailRow("接入路径", entry.accessSummary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)

            Section {
                Text(entry.accessDetail)
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            } header: {
                headerText("接入说明")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.0（§5／C9）：同 connectedDetail，撤
        // 标题与手写关闭、内容领头
    }

    /// 本机服务详情（0.29.0）：状态/证据/探活时间如
    /// 实列全；异常显错误原文、未配置显成因与补设入
    /// 口；有对应功能页的给入口跳转（口径与本页其他
    /// 详情一致：只跳转、不在本页另做一份功能面）
    private func localDetail(
        _ descriptor: LocalServiceDescriptor
    ) -> some View {
        let state = localStates[descriptor.serviceID] ?? .loading
        return List {
            Section {
                sheetHeader(
                    spec: .symbol(descriptor.symbolName),
                    name: descriptor.name, subline: descriptor.blurb
                )
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)

            Section {
                detailRow("状态", state.statusLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text("证据来源")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(descriptor.evidenceLine)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.vertical, OneDayMetrics.spacingS)
                if let metric = state.metric, !metric.isEmpty {
                    detailRow("当前读数", metric)
                }
                if let lastProbeAt {
                    detailRow(
                        "最近检查",
                        DisplayDate.dateTime(lastProbeAt)
                    )
                }
                if descriptor.serviceID == .writeGate,
                   let gate = gateSnapshot {
                    detailRow("闸门模块", gate.supported ? "已启用" : "未启用")
                    detailRow(
                        "记忆闸门", gate.memoryGateEnabled ? "开" : "关"
                    )
                    detailRow(
                        "技能闸门", gate.skillsGateEnabled ? "开" : "关"
                    )
                }
                if descriptor.serviceID == .overviewBridge,
                   let generated = overviewGeneratedAt {
                    detailRow("快照生成", generated)
                }
            } header: {
                headerText("状态")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)

            if case .down(let message) = state {
                Section {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.vertical, OneDayMetrics.spacingS)
                } header: {
                    headerText("异常详情")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(rowInsets)
            }

            if case .notConfigured = state {
                Section {
                    Text("这台手机上还没有登录信息：本机服务用的就是你的 Hermes 登录，没有登录信息时不会发出任何检查请求。先到「设置」里确认已经连接并登录，再回到本页下拉刷新即可。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.vertical, OneDayMetrics.spacingS)
                } header: {
                    headerText("未配置")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(rowInsets)
            }

            Section {
                localEntries(descriptor.serviceID)
            } header: {
                headerText("打开")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.0（§5／C9）：同 connectedDetail，撤
        // 标题与手写关闭、内容领头
    }

    /// 功能入口（按服务分发到各自既有页，不新造页面）
    @ViewBuilder
    private func localEntries(_ serviceID: LocalServiceID) -> some View {
        switch serviceID {
        case .hermes:
            entryRow("服务器详情") { jumpSettings(.serverDetail) }
        case .writeGate:
            entryRow("记忆") { jumpAgent(.memory) }
            entryRow("技能") { jumpAgent(.skills) }
        case .oneDayBridge:
            entryRow("目标") { jumpTab(.goals) }
            entryRow("点子") { jumpTab(.ideas) }
        case .overviewBridge:
            entryRow("总览") {
                detailTarget = nil
                onOpenOverview?()
            }
        }
    }

    private func entryRow(
        _ title: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Text(title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func jumpAgent(_ route: AgentRoute) {
        detailTarget = nil
        appState.pendingAgentRoute = route
    }

    private func jumpSettings(_ route: SettingsRoute) {
        detailTarget = nil
        appState.pendingSettingsRoute = route
    }

    private func jumpTab(_ tab: ContentView.MainTab) {
        detailTarget = nil
        appState.mainTabSwitchRequest = tab
    }

    // MARK: - 数据链（与既有 MCP 页同源，语义不变）

    private func transportLabel(_ server: MCPServerItem) -> String {
        switch server.transport?.lowercased() {
        case "http", "streamable-http", "sse":
            return "远程连接"
        case "stdio":
            return "本地进程"
        case let other?:
            return other
        default:
            return "—"
        }
    }

    private func resultLine(_ result: MCPTestResult) -> String {
        var text = result.displayMessage
            ?? (result.succeeded ? "连接成功" : "连接未成功")
        if let count = result.toolCount {
            text += " · \(count) 个工具"
        }
        return text
    }

    private func toggleBinding(for server: MCPServerItem) -> Binding<Bool> {
        Binding(
            get: { server.enabled },
            set: { newValue in
                Task { await setEnabled(server, to: newValue) }
            }
        )
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            servers = try await appState.performAdmin { client, config in
                try await client.mcpServers(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage
                ?? "连接状态读取失败。"
        }
    }

    // MARK: - 本机服务探活（0.29.0，只读 GET、不写生产）

    /// 四条并行探活：进页/下拉整批重探，按名册序逐
    /// 条落定（一条慢不拖住已回的）；状态只存本页生
    /// 命周期——重进页 @State 重建、必从读取中重探，
    /// 不存在跨页缓存的绿色
    private func probeLocals() async {
        guard !localProbing else { return }
        guard let config = appState.config else {
            for id in LocalServiceID.allCases {
                localStates[id] = .down(message: "尚未连接服务器。")
            }
            lastProbeAt = Date()
            return
        }
        localProbing = true
        defer { localProbing = false }
        if localStates.isEmpty {
            for id in LocalServiceID.allCases {
                localStates[id] = .loading
            }
        }
        async let hermes = probeHermes(config: config)
        async let gate = probeWriteGate(config: config)
        async let goals = probeOneDayBridge(config: config)
        async let overview = probeOverviewBridge(config: config)
        localStates[.hermes] = LocalServiceProbeMapping.state(
            from: await hermes
        )
        localStates[.writeGate] = LocalServiceProbeMapping.state(
            from: await gate
        )
        localStates[.oneDayBridge] = LocalServiceProbeMapping.state(
            from: await goals
        )
        localStates[.overviewBridge] = LocalServiceProbeMapping.state(
            from: await overview
        )
        lastProbeAt = Date()
    }

    /// Hermes 本体：GET /health（既有 HermesClient
    /// 探活一，与连接页同源）；版本读数取健康回执
    private func probeHermes(
        config: ServerConfig
    ) async -> LocalServiceProbeOutcome {
        do {
            let health = try await appState.client.health(config: config)
            if health.isOK {
                return .success(
                    metric: health.version.map { "版本 \($0)" }
                )
            }
            return .failure("健康检查返回状态：\(health.status)")
        } catch {
            return .failure(
                (error as? HermesError)?.userMessage ?? "健康检查请求失败"
            )
        }
    }

    /// 记忆与技能：GET /api/write-gate/status（审批
    /// 桥状态端点，枢纽/记忆页同源）；计数是尽力读数
    /// ——记忆条目走记忆页的 MemoryBridgeClient、技
    /// 能走技能页的 HermesClient.skills，任一取不到
    /// 就不出该数、不编造
    private func probeWriteGate(
        config: ServerConfig
    ) async -> LocalServiceProbeOutcome {
        do {
            let status = try await writeGateClient.gateStatus(
                config: config
            )
            gateSnapshot = status
            guard status.supported else {
                return .success(metric: "闸门未启用")
            }
            let memoryCount = (try? await memoryBridgeClient.entries(
                config: config
            ))?.count
            let skillCount = (try? await appState.performAdmin {
                client, config in
                try await client.skills(config: config)
            })?.count
            var parts: [String] = []
            if let memoryCount { parts.append("记忆 \(memoryCount)") }
            if let skillCount { parts.append("技能 \(skillCount)") }
            return .success(
                metric: parts.isEmpty ? nil : parts.joined(separator: " · ")
            )
        } catch let error as WriteGateError {
            switch error {
            case .noKey:
                return .keyNotConfigured
            case .unauthorized:
                return .failure("服务器拒绝了这次登录，请到「设置」里检查登录是否还有效")
            case .bridgeMissing:
                return .failure("审批服务还没有在服务器上开通")
            case .recordGone:
                return .failure("要看的记录已经不在了")
            case .conflict:
                return .failure("服务器上的状态对不上，请下拉刷新重试")
            case .failed(let message):
                return .failure(message)
            }
        } catch {
            return .failure("没能连上审批服务")
        }
    }

    /// 目标与点子：本桥无专用健康端点，探最轻只读
    /// 端点 GET /api/oneday-bridge/goals（目标页同
    /// 源）；计数随探活回执一并取（点子尽力而为）
    private func probeOneDayBridge(
        config: ServerConfig
    ) async -> LocalServiceProbeOutcome {
        do {
            let goals = try await oneDayBridgeClient.goals(config: config)
            let ideas = (try? await oneDayBridgeClient.ideas(
                config: config
            ))?.count
            var parts = ["目标 \(goals.count)"]
            if let ideas { parts.append("点子 \(ideas)") }
            return .success(metric: parts.joined(separator: " · "))
        } catch let error as OneDayBridgeError {
            switch error {
            case .noKey:
                return .keyNotConfigured
            case .unauthorized:
                return .failure("服务器拒绝了这次登录，请到「设置」里检查登录是否还有效")
            case .bridgeMissing:
                return .failure("这项服务还没有在服务器上开通")
            case .recordGone:
                return .failure("要看的记录已经不在了")
            case .failed(let message):
                return .failure(message)
            }
        } catch {
            return .failure("没能连上目标服务")
        }
    }

    /// 总览数据：本桥无专用健康端点，探最轻只读端
    /// 点 GET /api/overview-bridge/overview（总览页
    /// 同源快照端点）；待批数只在大于零时作读数
    private func probeOverviewBridge(
        config: ServerConfig
    ) async -> LocalServiceProbeOutcome {
        do {
            let snapshot = try await overviewBridgeClient.overview(
                config: config
            )
            overviewGeneratedAt = snapshot.generatedAt
            return .success(
                metric: snapshot.pendingApprovals > 0
                    ? "待批 \(snapshot.pendingApprovals)" : nil
            )
        } catch let error as OverviewBridgeError {
            switch error {
            case .noKey:
                return .keyNotConfigured
            case .unauthorized:
                return .failure("服务器拒绝了这次登录，请到「设置」里检查登录是否还有效")
            case .failed(let message):
                return .failure(message)
            }
        } catch {
            return .failure("没能连上总览服务")
        }
    }

    /// 开关：乐观更新，PUT 失败回滚＋提示（旧页先例）
    private func setEnabled(_ server: MCPServerItem, to newValue: Bool) async {
        guard let index = servers.firstIndex(where: { $0.id == server.id })
        else { return }
        let original = servers[index]
        servers[index] = MCPServerItem(
            name: original.name, transport: original.transport,
            url: original.url, command: original.command,
            enabled: newValue,
            source: original.source, plugin: original.plugin
        )
        toggling.insert(server.name)
        defer { toggling.remove(server.name) }
        do {
            try await appState.performAdmin { client, config in
                try await client.setMCPServerEnabled(
                    config: config, name: server.name, enabled: newValue
                )
            }
            testResults.removeValue(forKey: server.name)
        } catch {
            if let current = servers.firstIndex(where: { $0.id == server.id }) {
                servers[current] = original
            }
            notice = (error as? HermesError)?.userMessage ?? "开关切换失败。"
        }
    }

    private func test(_ server: MCPServerItem) async {
        testing.insert(server.name)
        defer { testing.remove(server.name) }
        do {
            testResults[server.name] = try await appState.performAdmin {
                client, config in
                try await client.testMCPServer(
                    config: config, name: server.name
                )
            }
        } catch {
            testResults[server.name] = MCPTestResult(
                ok: false, status: nil,
                message: (error as? HermesError)?.userMessage
                    ?? "测试请求失败",
                toolCount: nil
            )
        }
    }
}

/// 连接器图标（0.36.0，宪法 §4／审计 C6）：口径
/// 只两路——官方品牌原图资产（.asset，来源登记
/// 在整改台账 D 节）或 SF Symbol 通用瓷砖
/// （.symbol，走 Design 层 AppSymbolTile 的苹果
/// 应用图标画法）。旧「彩色圆角底＋白色字母/汉
/// 字」近似瓷砖（§55 登记）整类退役：既是字块、
/// 又是仿绘品牌，双触 §4。
private struct ConnectorIconView: View {
    let spec: ConnectorIconSpec
    var size: CGFloat = 40

    var body: some View {
        Group {
            switch spec {
            case .asset(let name):
                Image(name)
                    .resizable()
                    .scaledToFit()
            case .symbol(let name):
                AppSymbolTile(
                    symbol: name, glyphColor: Palette.ink, size: size
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
