import Foundation
import OneDayCore

/// 连接器面门面（DESIGN §259，拼装普查收口第 69
/// 条）：连接器目录页的唯一入口与连接状态单源。
///
/// 收口前（普查实证）：ConnectorsView 一 View 直持
/// WriteGate/OneDayBridge/OverviewBridge/MemoryBridge
/// 四个桥客户端，探活状态、MCP 名单、设备读数、云
/// 电脑子店各存一处，「连没连上」散在 ≥5 个持有者。
/// 本门面把四客户端与全部面内状态收为一处持有：
/// - 客户端只在本类内实例化，View 不再直持；
/// - MCP 名单/本机服务探活/设备读数/云电脑记录的
///   状态只在本类记账，目录行与详情只读派生；
/// - 已连接/可连接目录由 Core ConnectorDirectory
///   自本类持有的名单单源派生，不在 View 二次拼。
///
/// 行为口径与收口前逐项一致：探活只读 GET、进页/
/// 下拉整批重探、不缓存上次结果冒充实时；MCP 启停
/// 乐观更新＋失败回滚、测试回执无显式成功信号不判
/// 成功（均沿旧页语义原文搬运）。频道状态不在本面
/// （ChannelStatusStore 于 §256 已改直连、归频道
/// 面）；设备权限/同步状态读 AppState 既有单实例
/// （deviceSession/deviceSync），本类只协调读数、
/// 不另立第二份。
@MainActor
@Observable
final class ConnectorsFacade {
    // MARK: - MCP 已连接面（与既有 MCP 页同源数据链）

    private(set) var servers: [MCPServerItem] = []
    private(set) var serversError: String?
    private(set) var isLoadingServers = false
    var notice: String?
    private(set) var toggling: Set<String> = []
    private(set) var testing: Set<String> = []
    private(set) var testResults: [String: MCPTestResult] = [:]

    // MARK: - 本机服务探活（0.29.0）

    /// 状态字典进页首帧全为读取中、探活回来逐条落
    /// 定；客户端与各功能页同一批类，基址与钥匙全
    /// 走既有 ServerConfig＋Keychain 单源
    private(set) var localStates: [LocalServiceID: LocalServiceProbeState] = [:]
    private(set) var lastProbeAt: Date?
    private(set) var gateSnapshot: WriteGateStatus?
    private(set) var overviewGeneratedAt: String?
    @ObservationIgnored
    private var localProbing = false

    // MARK: - 本机连接器读数（0.34.0 批一）

    /// 目录行读数（本地现读的一句数：今天日程数/未
    /// 完成提醒数；取不到不拼）
    private(set) var deviceMetrics: [DeviceSourceID: String] = [:]

    // MARK: - 云电脑（0.37.0，规格 §6.1）

    /// 连接记录走伴生 connections 契约的子店由门面
    /// 单实例持有，View 与详情 sheet 只经门面取用
    let connectionsStore = ConnectionsStore()

    // MARK: - 客户端（门面私有，View 不直持）

    private let writeGateClient = WriteGateClient()
    private let oneDayBridgeClient = OneDayBridgeClient()
    private let overviewBridgeClient = OverviewBridgeClient()
    private let memoryBridgeClient = MemoryBridgeClient()

    // MARK: - 目录派生（单源）

    var connectedConnectors: [ConnectedConnector] {
        // 0.37.0（云电脑规格 §6.1 收敛）：Simular Box
        // 迁入「云电脑」组单独呈现，同一台电脑只许
        // 出现一处——已连接组滤掉 box 在册行（连接
        // 记录里有这台时才滤，避免记录没读到时两处皆空）
        let entries = ConnectorDirectory.connectedEntries(from: servers)
        guard connectionsStore.cloudComputers.contains(
            where: { $0.provider == "simular_box" }
        ) else { return entries }
        return entries.filter { $0.id != "box" }
    }

    var availableConnectors: [ConnectorCatalogEntry] {
        ConnectorDirectory.availableEntries(connected: connectedConnectors)
    }

    // MARK: - 整批刷新（进页/下拉同一序）

    func refresh(appState: AppState) async {
        await loadServers(appState: appState)
        await probeLocals(appState: appState)
        await probeDevices(appState: appState)
        await connectionsStore.load(appState: appState)
    }

    func loadConnections(appState: AppState) async {
        await connectionsStore.load(appState: appState)
    }

    // MARK: - MCP 数据链（与既有 MCP 页同源，语义不变）

    func loadServers(appState: AppState) async {
        guard !isLoadingServers else { return }
        isLoadingServers = true
        defer { isLoadingServers = false }
        do {
            servers = try await appState.performAdmin { client, config in
                try await client.mcpServers(config: config)
            }
            serversError = nil
        } catch {
            serversError = (error as? HermesError)?.userMessage
                ?? "连接状态没读出来，可能是网络或服务暂时没响应"
        }
    }

    /// 开关：乐观更新，PUT 失败回滚＋提示（旧页先例）
    func setEnabled(
        _ server: MCPServerItem, to newValue: Bool, appState: AppState
    ) async {
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

    func test(_ server: MCPServerItem, appState: AppState) async {
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

    // MARK: - 本机服务探活（0.29.0，只读 GET、不写生产）

    /// 四条并行探活：进页/下拉整批重探，按名册序逐
    /// 条落定（一条慢不拖住已回的）；状态只存本面生
    /// 命周期——重进页门面随 View 重建、必从读取中
    /// 重探，不存在跨页缓存的绿色
    func probeLocals(appState: AppState) async {
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
        async let hermes = probeHermes(appState: appState, config: config)
        async let gate = probeWriteGate(appState: appState, config: config)
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
        appState: AppState, config: ServerConfig
    ) async -> LocalServiceProbeOutcome {
        do {
            let health = try await appState.client.health(config: config)
            if ServiceHealth.from(health: health) == .up {
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
        appState: AppState, config: ServerConfig
    ) async -> LocalServiceProbeOutcome {
        do {
            let status = try await writeGateClient.gateStatus(
                config: config
            )
            gateSnapshot = status
            guard status.supported else {
                return .success(metric: "写入审批没开")
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

    // MARK: - 设备读数（本地现读，进页/下拉时算）

    /// 日历＝今天日程数、提醒＝未完成数；通讯录全量
    /// 计数要整表枚举、不为一行读数付这个成本，取
    /// 不到就不拼。权限/同步状态本体在 AppState 的
    /// deviceSession/deviceSync 单实例，本处只触发
    /// 刷新与读数、不记第二份账
    func probeDevices(appState: AppState) async {
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
}
