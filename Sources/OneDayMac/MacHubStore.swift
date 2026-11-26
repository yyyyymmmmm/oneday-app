import Foundation
import Observation
import OneDayCore

/// 枢纽状态店（棒 4，对位 #11/#39–#64）：24 个管理面
/// 共用一店，按面懒加载；一切写动作走「发出→回读该
/// 面→以回读为终局」口径（与 iOS 各 Directive 一致，
/// 不认回执自报）。只复用现行网关 API、零新后端。
@MainActor
@Observable
final class MacHubStore {
    var loadingFaces: Set<MacHubFace> = []
    var loadedFaces: Set<MacHubFace> = []
    var errors: [MacHubFace: String] = [:]
    var actionNote: String?

    // 台账 / 审计 / 电脑 / 身份
    var ledgerSummary: JSONValue?
    var ledgerEntries: [JSONValue] = []
    var ledgerDetail: JSONValue?
    var computerStatus: JSONValue?
    var egressStatus: JSONValue?
    var identity: JSONValue?
    var avatarImages: [String: Data] = [:]

    // 档案 / 记忆 / 技能 / 工具集 / 委派
    var profiles: [JSONValue] = []
    var soulText: String = ""
    var soulProfileName: String?
    var memoryStatus: MemoryStatus?
    var memoryLayers: JSONValue?
    var graphNodes: [JSONValue] = []
    var nodeText: String = ""
    var nodeID: String?
    var skills: [SkillItem] = []
    var skillText: String = ""
    var skillName: String?
    var toolsetRows: [JSONValue] = []
    var routingRaw: JSONValue?
    var routing: DelegationRouting?

    // 定时 / MCP / 连接器 / 频道 / 设备
    var cronJobs: [CronJob] = []
    var blueprints: [JSONValue] = []
    var mcpServers: [MCPServerItem] = []
    var mcpCatalog: [JSONValue] = []
    var platforms: JSONValue?
    var channels: JSONValue?
    var deviceSession: JSONValue?
    var deviceSync: JSONValue?
    var parkState: JSONValue?
    var authSessions: JSONValue?

    // 监控 / Webhooks / 预设 / 环境 / 看板
    var monitors: [BridgeMonitor] = []
    var monitorChanges: [String: [BridgeMonitorChange]] = [:]
    var webhooksPage: WebhooksPage?
    var combosRaw: JSONValue?
    var envRows: [MacEnvRow] = []
    var kanbanBoards: [String] = []
    var kanbanBoard: String = ""
    var kanbanSnapshot: KanbanBoardSnapshot?

    // 网关 / 模型 / 配对 / 用量
    var serverStatus: ServerStatus?
    var modelOptions: [String] = []
    var auxiliary: JSONValue?
    var moa: JSONValue?
    var pairing: JSONValue?
    var usage: UsageAnalytics?
    var modelUsage: ModelAnalytics?

    private func creds(
        _ session: SessionStore
    ) -> (ServerConfig, String)? {
        guard session.isConnected, let config = session.config,
              let key = session.apiKey else { return nil }
        return (config, key)
    }

    func isLoading(_ face: MacHubFace) -> Bool {
        loadingFaces.contains(face)
    }

    /// 按面加载（已加载过的面重进不重拉，刷新走显式
    /// reload）；失败如实记 errors，不回假空面
    func load(
        _ face: MacHubFace, session: SessionStore, force: Bool = false
    ) async {
        if loadedFaces.contains(face) && !force { return }
        guard let (config, key) = creds(session) else { return }
        loadingFaces.insert(face)
        errors[face] = nil
        defer { loadingFaces.remove(face) }
        let client = session.chatClient
        do {
            switch face {
            case .ledger:
                ledgerSummary = try await client.hubLedgerSummary(
                    config: config, apiKey: key
                )
                let raw = try await client.hubLedger(
                    config: config, apiKey: key
                )
                ledgerEntries = raw.hubFirstList(
                    ["entries", "items", "ledger"]
                )
                if ledgerEntries.isEmpty { ledgerEntries = raw.hubList }
            case .audit:
                // 审计面状态归 MacApprovalStore（棒 2 既有
                // 店：已决/规则/授权＋撤销动作），本店不另
                // 立第二份；视图进面时调它的 refresh 三件
                break
            case .computer:
                computerStatus = try await client.hubComputerStatus(
                    config: config, apiKey: key
                )
                egressStatus = try? await client.hubEgressStatus(
                    config: config, apiKey: key
                )
            case .identity:
                identity = try await client.hubIdentity(
                    config: config, apiKey: key
                )
            case .mail:
                break // 邮件面走网关频道口径，见 MacHubFacesB 注释
            case .profiles:
                let raw = try await client.hubProfiles(
                    config: config, apiKey: key
                )
                profiles = raw.hubFirstList(["profiles", "items"])
                if profiles.isEmpty { profiles = raw.hubList }
            case .memory:
                memoryStatus = try await client.hubMemoryStatus(
                    config: config, apiKey: key
                )
                memoryLayers = try? await client.hubMemoryLayers(
                    config: config, apiKey: key
                )
                let graph = try await client.hubLearningGraph(
                    config: config, apiKey: key
                )
                graphNodes = graph.hubFirstList(["nodes", "items"])
                if graphNodes.isEmpty { graphNodes = graph.hubList }
            case .skills:
                skills = try await client.hubSkills(
                    config: config, apiKey: key
                )
            case .toolsets:
                let raw = try await client.hubToolsets(
                    config: config, apiKey: key
                )
                toolsetRows = Self.normalizeToolsets(raw)
            case .delegation:
                routingRaw = try await client.hubDelegationRouting(
                    config: config, apiKey: key
                )
                if let routingRaw {
                    routing = DelegationRouting(jsonValue: routingRaw)
                }
            case .cron:
                cronJobs = try await client.hubCronJobs(
                    config: config, apiKey: key
                )
                if let bp = try? await client.hubCronBlueprints(
                    config: config, apiKey: key
                ) {
                    blueprints = bp.hubFirstList(
                        ["blueprints", "items"]
                    )
                }
            case .mcp:
                mcpServers = try await client.hubMCPServers(
                    config: config, apiKey: key
                )
                if let catalog = try? await client.hubMCPCatalog(
                    config: config, apiKey: key
                ) {
                    mcpCatalog = catalog.hubFirstList(
                        ["entries", "servers", "items"]
                    )
                }
            case .connectors:
                mcpServers = try await client.hubMCPServers(
                    config: config, apiKey: key
                )
            case .channels:
                platforms = try await client.hubMessagingPlatforms(
                    config: config, apiKey: key
                )
                channels = try? await client.hubGatewayChannels(
                    config: config, apiKey: key
                )
            case .devices:
                deviceSession = try? await client.hubDeviceSession(
                    config: config, apiKey: key
                )
                deviceSync = try? await client.hubDeviceSyncStatus(
                    config: config, apiKey: key
                )
                parkState = try? await client.hubDeviceParkState(
                    config: config, apiKey: key
                )
                authSessions = try? await client.hubAuthSessions(
                    config: config, apiKey: key
                )
                if deviceSession == nil && deviceSync == nil
                    && parkState == nil && authSessions == nil {
                    throw HermesError.unreachable(
                        "设备面数据源都取不到"
                    )
                }
            case .monitors:
                monitors = try await client.hubMonitors(
                    config: config, apiKey: key
                ).items
            case .webhooks:
                let raw = try await client.hubWebhooks(
                    config: config, apiKey: key
                )
                webhooksPage = WebhooksPage(jsonValue: raw)
            case .presets:
                combosRaw = try await client.hubModelCombos(
                    config: config, apiKey: key
                )
            case .env:
                let raw = try await client.hubEnvVarsRaw(
                    config: config, apiKey: key
                )
                envRows = Self.mapEnvRows(raw)
            case .kanban:
                let raw = try await client.hubKanbanBoards(
                    config: config, apiKey: key
                )
                kanbanBoards = raw.hubFirstList(["boards"])
                    .compactMap { $0.stringValue }
                if kanbanBoards.isEmpty {
                    kanbanBoards = raw.hubList.compactMap {
                        $0.stringValue
                    }
                }
                if kanbanBoard.isEmpty {
                    kanbanBoard = kanbanBoards.first ?? ""
                }
                if !kanbanBoard.isEmpty {
                    kanbanSnapshot = try await client.hubKanbanBoard(
                        config: config, apiKey: key,
                        board: kanbanBoard
                    )
                }
            case .gateway:
                serverStatus = try await client.status(config: config)
            case .models:
                let raw = try await client.hubModelOptionsRaw(
                    config: config, apiKey: key
                )
                modelOptions = Self.extractModelIDs(raw)
                auxiliary = try? await client.hubAuxiliaryModels(
                    config: config, apiKey: key
                )
                moa = try? await client.hubMoaConfig(
                    config: config, apiKey: key
                )
            case .pairing:
                pairing = try await client.hubPairingList(
                    config: config, apiKey: key
                )
            case .usage:
                usage = try await client.hubUsageAnalytics(
                    config: config, apiKey: key
                )
                modelUsage = try? await client.hubModelAnalytics(
                    config: config, apiKey: key
                )
            }
            loadedFaces.insert(face)
        } catch let error as HermesError {
            errors[face] = error.userMessage
        } catch {
            errors[face] = "\(face.title)加载失败"
        }
    }

    /// 动作统一收尾：记一句人话结果＋回读该面
    private func settle(
        _ face: MacHubFace, session: SessionStore,
        ok: String, failed: String,
        _ action: () async throws -> Void
    ) async {
        guard creds(session) != nil else { return }
        do {
            try await action()
            actionNote = ok
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = failed
        }
        loadedFaces.remove(face)
        await load(face, session: session, force: true)
    }

    // MARK: - 动作（台账详情 / 审计）

    func loadLedgerEntry(session: SessionStore, id: String) async {
        guard let (config, key) = creds(session) else { return }
        ledgerDetail = try? await session.chatClient.hubLedgerEntry(
            config: config, apiKey: key, id: id
        )
    }

    // MARK: - 动作（档案 / 记忆 / 技能）

    func activateProfile(session: SessionStore, name: String) async {
        guard creds(session) != nil else { return }
        await settle(.profiles, session: session,
                     ok: "已切换到档案「\(name)」", failed: "切换档案失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubSetActiveProfile(
                config: config, apiKey: key, name: name
            )
        }
    }

    func loadSoul(session: SessionStore, name: String) async {
        guard let (config, key) = creds(session) else { return }
        soulProfileName = name
        if let raw = try? await session.chatClient.hubProfileSoul(
            config: config, apiKey: key, name: name
        ) {
            soulText = raw.hubFirstStr(["content", "soul", "text"])
                ?? raw.stringValue ?? ""
        }
    }

    func saveSoul(session: SessionStore) async {
        guard let name = soulProfileName else { return }
        await settle(.profiles, session: session,
                     ok: "Soul 已保存（已回读）", failed: "保存 Soul 失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubUpdateProfileSoul(
                config: config, apiKey: key, name: name,
                content: self.soulText
            )
        }
    }

    func loadNode(session: SessionStore, id: String) async {
        guard let (config, key) = creds(session) else { return }
        nodeID = id
        if let raw = try? await session.chatClient.hubLearningNode(
            config: config, apiKey: key, id: id
        ) {
            nodeText = raw.hubFirstStr(["content", "text"])
                ?? raw.stringValue ?? ""
        }
    }

    func saveNode(session: SessionStore) async {
        guard let id = nodeID else { return }
        await settle(.memory, session: session,
                     ok: "节点已保存（已回读）", failed: "保存节点失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubUpdateLearningNode(
                config: config, apiKey: key, id: id,
                content: self.nodeText
            )
        }
    }

    func deleteNode(session: SessionStore, id: String) async {
        await settle(.memory, session: session,
                     ok: "节点已处理（已回读）", failed: "删除节点失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubDeleteLearningNode(
                config: config, apiKey: key, id: id
            )
        }
    }

    func loadSkill(session: SessionStore, name: String) async {
        guard let (config, key) = creds(session) else { return }
        skillName = name
        if let raw = try? await session.chatClient.hubSkillContent(
            config: config, apiKey: key, name: name
        ) {
            skillText = raw.hubFirstStr(["content", "text"])
                ?? raw.stringValue ?? ""
        }
    }

    func saveSkill(session: SessionStore) async {
        guard let name = skillName else { return }
        await settle(.skills, session: session,
                     ok: "技能已保存（已回读）", failed: "保存技能失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubUpdateSkillContent(
                config: config, apiKey: key, name: name,
                content: self.skillText
            )
        }
    }

    func toggleSkill(
        session: SessionStore, name: String, enabled: Bool
    ) async {
        await settle(.skills, session: session,
                     ok: "技能开关已更新（已回读）",
                     failed: "技能开关失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubToggleSkill(
                config: config, apiKey: key, name: name,
                enabled: enabled
            )
        }
    }

    func lockSkill(
        session: SessionStore, name: String, locked: Bool
    ) async {
        await settle(.skills, session: session,
                     ok: "技能锁定状态已更新（已回读）",
                     failed: "技能锁定失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubLockSkill(
                config: config, apiKey: key, name: name,
                locked: locked
            )
        }
    }

    // MARK: - 动作（工具集 / 委派）

    func setToolset(
        session: SessionStore, name: String, enabled: Bool
    ) async {
        await settle(.toolsets, session: session,
                     ok: "工具集已更新（已回读）",
                     failed: "工具集开关失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubSetToolsetEnabled(
                config: config, apiKey: key, name: name,
                enabled: enabled
            )
        }
    }

    func setBackend(session: SessionStore, backend: String) async {
        await settle(.delegation, session: session,
                     ok: "委派后端已切换（以回读为准）",
                     failed: "切换后端失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubSetDelegationBackend(
                config: config, apiKey: key, backend: backend
            )
        }
    }

    /// 设默认模型路线：先读后改——拿原始 model_map
    /// 只换 default、options 原样带回，不丢未知字段
    func setModelRouteDefault(
        session: SessionStore, name: String
    ) async {
        guard var map = routingRaw?.hubDict["model_map"]?.hubDict
        else { return }
        map["default"] = .string(name)
        await settle(.delegation, session: session,
                     ok: "默认模型路线已更新（已回读）",
                     failed: "更新模型路线失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubSetDelegationModelMap(
                config: config, apiKey: key, body: map
            )
        }
    }

    func setProfileRouteDefault(
        session: SessionStore, name: String
    ) async {
        guard var routes = routingRaw?.hubDict["profile_routes"]?.hubDict
        else { return }
        routes["default"] = .string(name)
        await settle(.delegation, session: session,
                     ok: "默认档案路由已更新（已回读）",
                     failed: "更新档案路由失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient
                .hubSetDelegationProfileRoutes(
                    config: config, apiKey: key, body: routes
                )
        }
    }

    // MARK: - 动作（定时 / MCP）

    func cronAction(
        session: SessionStore, id: String, action: String
    ) async {
        await settle(.cron, session: session,
                     ok: "定时任务已更新（已回读）",
                     failed: "定时任务动作失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubCronAction(
                config: config, apiKey: key, id: id, action: action
            )
        }
    }

    func createCron(
        session: SessionStore, name: String, prompt: String,
        schedule: String
    ) async {
        await settle(.cron, session: session,
                     ok: "定时任务已新建（已回读）",
                     failed: "新建定时任务失败") {
            guard let (config, key) = self.creds(session) else { return }
            _ = try await session.chatClient.hubCreateCronJob(
                config: config, apiKey: key,
                name: name.isEmpty ? nil : name,
                prompt: prompt, schedule: schedule, deliver: nil
            )
        }
    }

    func deleteCron(session: SessionStore, id: String) async {
        await settle(.cron, session: session,
                     ok: "定时任务已删除（已回读）",
                     failed: "删除定时任务失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubDeleteCronJob(
                config: config, apiKey: key, id: id
            )
        }
    }

    func setMCPEnabled(
        session: SessionStore, name: String, enabled: Bool
    ) async {
        await settle(.mcp, session: session,
                     ok: "MCP 开关已更新（已回读）",
                     failed: "MCP 开关失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubSetMCPServerEnabled(
                config: config, apiKey: key, name: name,
                enabled: enabled
            )
        }
    }

    func testMCP(session: SessionStore, name: String) async {
        guard let (config, key) = creds(session) else { return }
        do {
            let raw = try await session.chatClient.hubTestMCPServer(
                config: config, apiKey: key, name: name
            )
            let verdict = raw.hubFirstStr(
                ["status", "message", "error"]
            ) ?? "已返回测试结果"
            actionNote = "「\(name)」测试：\(verdict)"
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "MCP 测试失败"
        }
    }

    // MARK: - 动作（监控 / Webhooks / 环境 / 看板）

    func loadMonitorChanges(session: SessionStore, id: String) async {
        guard let (config, key) = creds(session) else { return }
        if let response = try? await session.chatClient
            .hubMonitorChanges(config: config, apiKey: key, id: id) {
            monitorChanges[id] = response.items
        }
    }

    func createMonitor(
        session: SessionStore, name: String, target: String
    ) async {
        await settle(.monitors, session: session,
                     ok: "监控已新建（已回读）", failed: "新建监控失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubCreateMonitor(
                config: config, apiKey: key,
                request: BridgeMonitorCreateRequest(
                    name: name, target: target,
                    scheduleText: nil, cron: nil,
                    intervalSeconds: nil
                )
            )
        }
    }

    func deleteMonitor(session: SessionStore, id: String) async {
        await settle(.monitors, session: session,
                     ok: "监控已删除（已回读）", failed: "删除监控失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubDeleteMonitor(
                config: config, apiKey: key, id: id
            )
        }
    }

    func setWebhookEnabled(
        session: SessionStore, name: String, enabled: Bool
    ) async {
        await settle(.webhooks, session: session,
                     ok: "Webhook 开关已更新（已回读）",
                     failed: "Webhook 开关失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubSetWebhookEnabled(
                config: config, apiKey: key, name: name,
                enabled: enabled
            )
        }
    }

    func deleteWebhook(session: SessionStore, name: String) async {
        await settle(.webhooks, session: session,
                     ok: "Webhook 已删除（已回读）",
                     failed: "删除 Webhook 失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubDeleteWebhook(
                config: config, apiKey: key, name: name
            )
        }
    }

    func enableWebhookPlatform(session: SessionStore) async {
        await settle(.webhooks, session: session,
                     ok: "Webhook 平台已开启（已回读）",
                     failed: "开启平台失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubEnableWebhookPlatform(
                config: config, apiKey: key
            )
        }
    }

    func setEnv(session: SessionStore, key: String, value: String) async {
        await settle(.env, session: session,
                     ok: "环境变量已保存（已回读）",
                     failed: "保存环境变量失败") {
            guard let (config, apiKey) = self.creds(session)
            else { return }
            try await session.chatClient.hubSetEnvVar(
                config: config, apiKey: apiKey, key: key,
                value: value
            )
        }
    }

    func deleteEnv(session: SessionStore, key: String) async {
        await settle(.env, session: session,
                     ok: "环境变量已删除（已回读）",
                     failed: "删除环境变量失败") {
            guard let (config, apiKey) = self.creds(session)
            else { return }
            try await session.chatClient.hubDeleteEnvVar(
                config: config, apiKey: apiKey, key: key
            )
        }
    }

    func revealEnv(session: SessionStore, key: String) async -> String? {
        guard let (config, _) = creds(session) else { return nil }
        return try? await session.chatClient.revealEnvVar(
            config: config, key: key
        )
    }

    func selectBoard(session: SessionStore, board: String) async {
        kanbanBoard = board
        loadedFaces.remove(.kanban)
        // 只重拉板面，不动板清单
        guard let (config, key) = creds(session) else { return }
        kanbanSnapshot = try? await session.chatClient.hubKanbanBoard(
            config: config, apiKey: key, board: board
        )
        loadedFaces.insert(.kanban)
    }

    func kanbanCreate(
        session: SessionStore, title: String, body: String
    ) async {
        await settle(.kanban, session: session,
                     ok: "卡片已新建（已回读）", failed: "看板建卡失败") {
            guard let (config, key) = self.creds(session) else { return }
            _ = try await session.chatClient.hubKanbanCreateTask(
                config: config, apiKey: key, board: self.kanbanBoard,
                title: title, body: body,
                idempotencyKey: "mac-\(UUID().uuidString)"
            )
        }
    }

    func kanbanSetStatus(
        session: SessionStore, id: String, status: String
    ) async {
        await settle(.kanban, session: session,
                     ok: "卡片状态已更新（已回读）",
                     failed: "看板改状态失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubKanbanPatchTaskStatus(
                config: config, apiKey: key, board: self.kanbanBoard,
                id: id, status: status
            )
        }
    }

    func kanbanDelete(session: SessionStore, id: String) async {
        await settle(.kanban, session: session,
                     ok: "卡片已删除（已回读）", failed: "看板删卡失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubKanbanDeleteTask(
                config: config, apiKey: key, board: self.kanbanBoard,
                id: id
            )
        }
    }

    func kanbanDispatch(session: SessionStore) async {
        await settle(.kanban, session: session,
                     ok: "已催派（已回读）", failed: "看板催派失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubKanbanDispatch(
                config: config, apiKey: key, board: self.kanbanBoard
            )
        }
    }

    // MARK: - 动作（网关 / 模型 / 配对 / 身份）

    func gatewayAction(session: SessionStore, action: String) async {
        await settle(.gateway, session: session,
                     ok: "网关动作已执行（已回读状态）",
                     failed: "网关动作失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubGatewayAction(
                config: config, apiKey: key, action: action
            )
        }
    }

    func setMainModel(session: SessionStore, model: String) async {
        await settle(.models, session: session,
                     ok: "主模型已设置（已回读）",
                     failed: "设置主模型失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubSetMainModel(
                config: config, apiKey: key, model: model
            )
        }
    }

    func pairingApprove(
        session: SessionStore, platform: String, requestID: String
    ) async {
        await settle(.pairing, session: session,
                     ok: "配对已批准（已回读）", failed: "批准配对失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubPairingApprove(
                config: config, apiKey: key, platform: platform,
                requestID: requestID
            )
        }
    }

    func pairingRevoke(
        session: SessionStore, platform: String, userID: String
    ) async {
        await settle(.pairing, session: session,
                     ok: "配对已撤销（已回读）", failed: "撤销配对失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubPairingRevoke(
                config: config, apiKey: key, platform: platform,
                userID: userID
            )
        }
    }

    func pairingClearPending(session: SessionStore) async {
        await settle(.pairing, session: session,
                     ok: "待批配对已清空（已回读）",
                     failed: "清空待批失败") {
            guard let (config, key) = self.creds(session) else { return }
            try await session.chatClient.hubPairingClearPending(
                config: config, apiKey: key
            )
        }
    }

    func loadAvatar(session: SessionStore, id: String) async {
        guard avatarImages[id] == nil,
              let (config, key) = creds(session) else { return }
        avatarImages[id] = try? await session.chatClient
            .hubAvatarImage(config: config, apiKey: key, id: id)
    }

    // MARK: - 形状归一

    /// 工具集：数组本体/信封/字典三形归一为行数组，
    /// 行内保留原始字段（name/enabled 由视图提取）
    static func normalizeToolsets(_ raw: JSONValue) -> [JSONValue] {
        let listed = raw.hubFirstList(["toolsets", "items", "tools"])
        if !listed.isEmpty { return listed }
        if !raw.hubList.isEmpty { return raw.hubList }
        return raw.hubDict.map { key, value in
            var row = value.hubDict
            if row["name"] == nil { row["name"] = .string(key) }
            return .object(row)
        }
    }

    /// 环境变量：顶层字典 → 行（值只取遮蔽形与是否已设）
    static func mapEnvRows(_ raw: JSONValue) -> [MacEnvRow] {
        raw.hubDict.map { key, value in
            MacEnvRow(
                key: key,
                isSet: value.hubBool("is_set")
                    ?? value.hubBool("set") ?? false,
                redacted: value.hubFirstStr(
                    ["redacted_value", "redacted", "value_preview"]
                ),
                note: value.hubFirstStr(
                    ["description", "category"]
                )
            )
        }
        .sorted { $0.key < $1.key }
    }

    /// 模型 id 宽容提取（与 iOS ModelCatalog 同思路的
    /// 简版：字符串数组/对象数组取 id|model|name）
    static func extractModelIDs(_ raw: JSONValue) -> [String] {
        let items = raw.hubFirstList(
            ["models", "options", "items", "data"]
        )
        let source = items.isEmpty ? raw.hubList : items
        return source.compactMap { item in
            item.stringValue
                ?? item.hubFirstStr(["id", "model", "name"])
        }
    }
}
