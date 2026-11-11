import OneDayCore
import OneDayDesign
import SwiftUI

/// 连接器目录页（0.28.0，用户 10:32 对标 Muse 连接
/// 器页令；设置「MCP 连接」升级）：页顶搜索（系统
/// searchable）＋可连接/已连接分段＋分类分组卡。
/// 0.36.5（用户 19:03 点名，对照 Muse 目录图）：
/// 分段胶囊改「可连接」在前、「已连接」在后，默认
/// 落地可连接（目录的首要任务是发现新连接），且胶
/// 囊上移至名单首位、紧贴搜索框（旧序已连接在前＋
/// 胶囊夹在本机服务/设备组之后，被指逻辑不对）。
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
/// （Simular Box）0.29.0 时留在已连接组原位、本组
/// 不重复列（box-bridge 是电脑页的内部设施、同样
/// 不列）——0.37.0 起按云电脑规格 §6.1 收敛：Box
/// 迁入新设「云电脑」组，已连接组滤掉其在册行，
/// 同一台电脑全页只出现一处。
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
    /// 默认落地可连接（0.36.5）：先进目录先见可接
    /// 入的，已连接是回头看的
    @State private var segment: Segment = .available
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

    /// 分段序（0.36.5）：声明序即胶囊呈现序——可连
    /// 接在前、已连接在后（对照 Muse 目录图）
    private enum Segment: String, CaseIterable, Identifiable {
        case available = "可连接"
        case connected = "已连接"
        var id: String { rawValue }
    }

    private enum DetailTarget: Identifiable {
        case connected(String)
        case catalog(String)
        case local(LocalServiceID)
        case device(DeviceSourceID)
        case computer(String)
        var id: String {
            switch self {
            case .connected(let name): return "c-\(name)"
            case .catalog(let id): return "a-\(id)"
            case .local(let service): return "l-\(service.rawValue)"
            case .device(let source): return "d-\(source.rawValue)"
            case .computer(let id): return "pc-\(id)"
            }
        }
    }

    // 本机连接器（0.34.0 批一）：目录行读数（本地现读
    // 的一句数：今天日程数/未完成提醒数；取不到不拼）
    @State private var deviceMetrics: [DeviceSourceID: String] = [:]

    // 云电脑（0.37.0，规格 §6.1）：连接记录走伴生
    // connections 契约（ConnectionsStore），组内每台
    // 一行＋添加入口；Simular Box 自已连接组迁入本组
    @State private var connectionsStore = ConnectionsStore()
    @State private var showAddComputer = false

    private var connected: [ConnectedConnector] {
        // 0.37.0（云电脑规格 §6.1 收敛）：Simular Box
        // 迁入下方「云电脑」组单独呈现，同一台电脑只
        // 许出现一处——已连接组滤掉 box 在册行（连接
        // 记录里有这台时才滤，避免记录没读到时两处皆空）
        let entries = ConnectorDirectory.connectedEntries(from: servers)
        guard connectionsStore.cloudComputers.contains(
            where: { $0.provider == "simular_box" }
        ) else { return entries }
        return entries.filter { $0.id != "box" }
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
                // 0.36.5：胶囊置顶紧贴搜索框（名单首
                // 位），本机服务/你的设备两组随其后、
                // 分段内容殿后
                segmentSection
                localSection
                deviceSection
                computerSection
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
        // 0.36.7（用户点名胶囊上下间距太大）：本页间
        // 距自设置页梯队 28 收紧到 spacingM 16——胶囊
        // 与搜索框、与下方名单的间距同源于此（胶囊行
        // 自身内边距再归零，见 segmentSection）；本页
        // 是目录面、节奏从 Muse 参照的紧凑口径，不
        // 动设置页本体的 28
        .listSectionSpacing(OneDayMetrics.spacingM)
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
            await connectionsStore.load(appState: appState)
        }
        .task {
            await load()
            await probeLocals()
            await probeDevices()
            await connectionsStore.load(appState: appState)
        }
        .sheet(item: $detailTarget) { target in
            detailSheet(for: target)
        }
        .sheet(isPresented: $showAddComputer) {
            AddComputerView(store: connectionsStore)
        }
    }

    private func headerText(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
    }

    // MARK: - 分段

    @Namespace private var segmentNamespace
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// 分段胶囊（0.36.10，判词 2 按图量测对齐）：系
    /// 统 segmented 退役——实拍三宗错：轨道灰
    /// （#E3E2E8 量测）＋选中片白（角色与定版语言
    /// 正反）、轨道高仅约 31pt、胶囊上方留白实测约
    /// 56pt。改与文件页同源的自制控件（Segmented-
    /// ControlSpec 钉死）：轨道＝surface 白＋发丝边、
    /// 全胶囊总高 48；选中药丸＝selectionFill 浅灰
    /// 垫（#F0F1F2，与 Muse 实测选中片 #F3F4F6 同
    /// 级）、高 36、内缩 6、无阴影；字 17 semibold
    /// 两态皆 ink，区分只靠灰垫。对照量测（2026-
    /// 11-10 用户图，3x 像素实测）：Muse 轨白
    /// #FFFFFF、选中片 #F3F4F6、总高 ≈47.5pt、内缩
    /// ≈5pt、搜索框→轨道 16pt、轨道→分组头 ≈30pt；
    /// 本页左右边距由 List 行距 20 承接（Muse 连
    /// 接器页实测 ≈21pt、同本页页面节奏）。行上下
    /// 内边距归零，间距只由 listSectionSpacing（16）
    /// 一处出——对照旧实测 56pt 的叠加留白
    private var segmentSection: some View {
        Section {
            HStack(spacing: 0) {
                ForEach(Segment.allCases) { item in
                    segmentButton(item)
                }
            }
            .padding(SegmentedControlSpec.inset)
            .background(Palette.surface, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Palette.separator, lineWidth: 1)
            }
            .sensoryFeedback(.selection, trigger: segment)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(
            EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        )
    }

    private func segmentButton(_ item: Segment) -> some View {
        let selected = segment == item
        return Button {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.selectionSpring,
                    reduceMotion: reduceMotion
                )
            ) { segment = item }
        } label: {
            Text(item.rawValue)
                .font(.bodyText.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SegmentedControlSpec.pillHeight
                )
                .background {
                    if selected {
                        Capsule()
                            .fill(Palette.selectionFill)
                            .matchedGeometryEffect(
                                id: "connectorSegmentPill",
                                in: segmentNamespace
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - 本机服务（0.29.0 补组，进页实时探活）

    /// 本机服务组：分段胶囊之下第一组（0.36.5 胶囊
    /// 置顶前的旧序为目录顶部）；四条全列、状态随
    /// 探活逐条落定，读取中也占行不塌组
    private var localSection: some View {
        Section {
            ForEach(LocalServiceDirectory.roster) { descriptor in
                localRow(descriptor)
            }
        } header: {
            headerText("本机服务")
        }
        // 0.36.7（用户点名）：本机服务组下方的备注脚
        // 注整段删除、不留替代文案——那段话是给开发
        // 者解释分组口径的，不是给用户看的
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
                // 0.36.3（§4 加严口径）：本机服务换定
                // 制图标面资产，裸 SF 符号瓷砖退役
                ConnectorIconView(
                    spec: .asset(descriptor.iconAssetName), size: 40
                )
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(descriptor.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: OneDayMetrics.iconTextGap) {
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
        // 0.36.3（目录行语法，对照 Muse 目录参考
        // 图）：分隔线对齐文字列——起于名称左缘、
        // 不穿图标下方（与设置页贯通口径不同页不
        // 同规矩：目录页从参考图、设置页从用户点名）
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            40 + OneDayMetrics.spacingSM
        }
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
            let dataset = DeviceSyncDataset.fromSource(
                descriptor.sourceID
            )
            lines[descriptor.sourceID] = DeviceRowStatus.line(
                descriptor: descriptor,
                permission: appState.deviceSession
                    .permissions[descriptor.sourceID] ?? .notDetermined,
                agentCallEnabled: appState.deviceSession
                    .agentCallEnabled[descriptor.sourceID] ?? false,
                // 0.36.10（判词 4）：「可调用」须有自家
                // 会话在线这一本地可验事实托底，离线如
                // 实降级（DeviceRowStatus 口径）
                sessionOnline: appState.deviceSession.sessionOnline,
                metric: deviceMetrics[descriptor.sourceID],
                // 0.36.14：同步件在行尾拼同步段（副本条
                // 数＋新到什么时候，Core 同口径组装）；
                // 0.36.18 起授权态只认真实权限
                syncSegment: dataset.map {
                    DeviceSyncPresentation.segment(
                        dataset: $0,
                        status: appState.deviceSync.statuses[$0],
                        authorized: DeviceSyncControl.agentCanQuery(
                            permission: appState.deviceSession
                                .permissions[descriptor.sourceID]
                                ?? .notDetermined
                        ),
                        now: Date()
                    )
                },
                // 照片/步数没有现读现回的通道，行里不
                // 拼「可调用/调用已关」
                showsCallState: dataset == nil
                    || descriptor.sourceID == .calendar
                    || descriptor.sourceID == .reminders
                    || descriptor.sourceID == .contacts
            )
        }
        return lines
    }

    /// 你的设备组：恒显（在本机服务之后、分段内容
    /// 之前——两组都是「自家的东西」，与 MCP 的已
    /// 连接/可连接语义无关，不被分段切换藏掉，设计
    /// 档 §6.1；分段胶囊本体 0.36.5 起置于名单首
    /// 位）。批一三件可点进详情；健康/家庭待签名权
    /// 益，行在、状态如实、无假入口
    private var deviceSection: some View {
        Section {
            ForEach(DeviceSourceDirectory.roster) { descriptor in
                deviceRow(descriptor)
            }
        } header: {
            headerText("你的设备")
        }
        // 0.36.10（判词 1）：组下解释段整段删除——
        // 「数据留在手机上、现读现回、不存副本」逐件
        // 已在各自详情页尾的口径脚注里（descriptor
        // .footnote），「健康/家庭待签名权益」在各自
        // 行状态字与详情里都有；目录页不再成段复述，
        // 也不换位置再出现
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    // 云电脑组（0.37.0，规格 §6.1）：每台一行（名＋
    // 类型＋状态词，词表与伴生面板同源），行尾添加
    // 入口。状态来自 connections 契约的实时读取；读
    // 失败如实露一行，不拿旧列表冒充
    @ViewBuilder
    private var computerSection: some View {
        Section {
            if let loadError = connectionsStore.loadError,
               connectionsStore.cloudComputers.isEmpty {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            ForEach(connectionsStore.cloudComputers) { connection in
                Button {
                    detailTarget = .computer(connection.id)
                } label: {
                    computerRowLabel(connection)
                }
                .buttonStyle(.odPressable)
            }
            Button {
                showAddComputer = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.primary)
                    Text("添加电脑")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
        } header: {
            headerText("云电脑")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    private func computerRowLabel(
        _ connection: CompanionConnection
    ) -> some View {
        let status = ConnectionStatusWording.evaluate(connection)
        return HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 20))
                .foregroundStyle(Palette.primary)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(connection.name)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text("\(connection.providerWording) · \(status.text)")
                    .font(.footnote)
                    .foregroundStyle(
                        status.tone == .ok ? Palette.success
                            : status.tone == .bad ? Palette.danger
                            : Palette.inkSecondary
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .contentShape(Rectangle())
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
            DeviceAppIconView(source: descriptor.sourceID, size: 40)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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
        // 0.36.3（目录行语法，对照 Muse 目录参考
        // 图）：分隔线对齐文字列——起于名称左缘、
        // 不穿图标下方（与设置页贯通口径不同页不
        // 同规矩：目录页从参考图、设置页从用户点名）
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            40 + OneDayMetrics.spacingSM
        }
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
        // 同步状态同拍刷新（目录行同步段的数据源）
        await appState.deviceSync.refreshStatus(
            config: appState.config
        )
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
                // 0.41.0（收口批 P7 余项）：页脚由整句说
                // 明瘦身为一句事实——去「MCP／服务端」术
                // 语（宪法 §8），只留用户需要知道的：状
                // 态是现读的、读不到不冒充（S7 如实）
                Text("这里的状态是刚刚向服务器确认过的，读不到会如实显示。")
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
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(entry.displayName)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: OneDayMetrics.iconTextGap) {
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
        // 0.36.3（目录行语法，对照 Muse 目录参考
        // 图）：分隔线对齐文字列——起于名称左缘、
        // 不穿图标下方（与设置页贯通口径不同页不
        // 同规矩：目录页从参考图、设置页从用户点名）
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            40 + OneDayMetrics.spacingSM
        }
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
                headerText(group.category.title)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)
        }
        // 0.36.10（判词 1）：页底总结段整段删除——
        // 「尚未接入」在每行状态字、「接入路径」在各
        // 自详情页（接入路径行＋accessDetail 明写 App
        // 内暂不能直接连接），信息一件不少、目录页
        // 不再成段复述
    }

    private func catalogRow(_ entry: ConnectorCatalogEntry) -> some View {
        Button {
            detailTarget = .catalog(entry.id)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                ConnectorIconView(spec: entry.iconSpec, size: 40)
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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
        // 0.36.3（目录行语法，对照 Muse 目录参考
        // 图）：分隔线对齐文字列——起于名称左缘、
        // 不穿图标下方（与设置页贯通口径不同页不
        // 同规矩：目录页从参考图、设置页从用户点名）
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            40 + OneDayMetrics.spacingSM
        }
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
                    headerText(group.category.title)
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
                sheetStack {
                    connectedDetail(entry)
                }
            }
        case .catalog(let id):
            if let entry = ConnectorDirectory.catalog
                .first(where: { $0.id == id }) {
                sheetStack {
                    catalogDetail(entry)
                }
            }
        case .local(let serviceID):
            sheetStack {
                localDetail(
                    LocalServiceDirectory.descriptor(serviceID)
                )
            }
        case .device(let source):
            sheetStack {
                deviceDetail(source)
            }
        case .computer(let id):
            sheetStack {
                CloudComputerDetailView(
                    store: connectionsStore, connectionID: id
                )
            }
        }
    }

    /// 详情 sheet 壳（0.36.5，用户 19:08 点名退出机
    /// 制缺失）：四类详情统一承载——关闭圆钮常驻左
    /// 上（系统工具栏玻璃圆钮，与图片查看器 ✕ 同
    /// 位）＋拖动指示器露面。0.36.0/0.36.3「撤手写
    /// 关闭、走系统下拉手势」的口径在真机不成立：
    /// 设备三页自带下拉刷新，下拉先被刷新截走（见
    /// DeviceViews 的 RefreshableIfEnabled），关不
    /// 掉又无按钮即无出口；连接器三页无刷新占用、
    /// 下拉本可关，同壳补钮保四类一致、且明示可拖
    private func sheetStack<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            detailTarget = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .accessibilityLabel("关闭")
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    /// 设备详情分发（批一三件；批二两件无详情、不
    /// 点入）。本面恒以 sheet 呈现：三页带 inSheet
    /// 标记，下拉手势归 sheet 关闭、不再被下拉刷
    /// 新截走
    @ViewBuilder
    private func deviceDetail(_ source: DeviceSourceID) -> some View {
        switch source {
        case .calendar: CalendarDetailView(inSheet: true)
        case .reminders: RemindersDetailView(inSheet: true)
        case .contacts: ContactsDetailView(inSheet: true)
        case .photos: PhotosDetailView(inSheet: true)
        case .motion: MotionDetailView(inSheet: true)
        case .clipboard: ClipboardDetailView()
        case .files: FilesDetailView()
        case .alarm: AlarmDetailView()
        case .notifications: NotificationsDetailView()
        case .opener: OpenTargetDetailView()
        case .camera: CameraDetailView()
        case .vision: VisionDetailView()
        case .translate: TranslateDetailView()
        case .ondevice: OnDeviceDetailView()
        case .biometric: BiometricDetailView()
        case .health, .home: EmptyView()
        }
    }

    /// 详情页头（0.36.3，详情页语法重做）：对齐
    /// Muse 授权页五段式的领头段——居中大真图标
    /// （64）→名称（Title2 bold，身份名档）→一句
    /// 话能力说明（居中、次色、至多两行）。旧行首
    /// 小图＋行题的设置式页头退役：详情页先让用户
    /// 看见「它是谁、能干什么」，状态与动作随后。
    private func sheetHeader(
        spec: ConnectorIconSpec, name: String, subline: String
    ) -> some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            ConnectorIconView(spec: spec, size: 64)
            Text(name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(subline)
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OneDayMetrics.spacingSM)
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
            .listRowBackground(Color.clear)
            .listRowInsets(rowInsets)

            Section {
                detailRow("连接状态", entry.statusLabel)
                detailRow("证据档位", entry.evidence.label)
                detailRow("来源", server.originLabel)
                detailRow("传输方式", transportLabel(server))
                if let endpoint = server.endpointLine {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)

            // 0.36.3（五段式）：主动作＝整宽主按钮
            // （测试连接），启停开关作控件行在前；测
            // 试结果独立成行，不与按钮挤一格。原「操
            // 作」分区头撤除——控件自明
            Section {
                Toggle("启用", isOn: toggleBinding(for: server))
                    .font(.rowTitleL)
                    .disabled(toggling.contains(server.name))
                Button {
                    Task { await test(server) }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        if testing.contains(server.name) {
                            ProgressView()
                        }
                        Text("测试连接")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.odPrimary)
                .disabled(testing.contains(server.name))
                if let result = testResults[server.name],
                   !testing.contains(server.name) {
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
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
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
            .listRowBackground(Color.clear)
            .listRowInsets(rowInsets)

            // 0.36.0（§5／C9）：原分区头「状态」与首
            // 行行题「状态」同词重复——去分区头，行
            // 本身即状态呈现
            Section {
                detailRow("状态", "未接入")
                detailRow("分类", entry.category.title)
                detailRow("接入路径", entry.accessSummary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)

            // 0.36.3（五段式）：说明文字下沉页脚小
            // 字——不再成段塞卡（对照授权页条款段）
            Section {
                Text(entry.accessDetail)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            .listRowBackground(Color.clear)
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
                    spec: .asset(descriptor.iconAssetName),
                    name: descriptor.name, subline: descriptor.blurb
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(rowInsets)

            Section {
                detailRow("状态", state.statusLabel)
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
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(rowInsets)

            // 0.36.3：证据口径下沉页脚小字（检查的是
            // 什么、何时查的——小字交代、不占卡内行）
            Section {
                Text(descriptor.evidenceLine)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(rowInsets)

            if case .down(let message) = state {
                Section {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.vertical, OneDayMetrics.spacingS)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(rowInsets)
            }

            if case .notConfigured = state {
                Section {
                    Text("这台手机上还没有登录信息。先到「设置」确认已连接并登录，再回到本页下拉刷新即可。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.vertical, OneDayMetrics.spacingS)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(rowInsets)
            }

            Section {
                localEntries(descriptor.serviceID)
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
