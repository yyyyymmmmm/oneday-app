import Foundation
import OneDayCore

// MARK: - HermesClient 会话、记忆、技能、定时任务与档案域（#37 模块化拆分）

extension HermesClient {
    // MARK: - 记忆

    func memoryStatus(config: ServerConfig) async throws -> MemoryStatus {
        try await getJSON(config: config, path: "/api/memory", endpoint: L10n.string("记忆接口"))
    }

    func setMemoryProvider(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: "/api/memory/provider", method: "PUT",
            endpoint: L10n.string("记忆提供方切换"), body: ["provider": .string(name)]
        )
    }

    func memoryProviderConfig(
        config: ServerConfig, name: String
    ) async throws -> MemoryProviderConfig {
        try await getJSON(
            config: config,
            path: "/api/memory/providers/\(name)/config",
            endpoint: L10n.string("记忆提供方配置")
        )
    }

    func updateMemoryProviderConfig(
        config: ServerConfig, name: String, values: [String: JSONValue]
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/memory/providers/\(name)/config",
            method: "PUT", endpoint: L10n.string("记忆提供方配置"),
            body: ["values": .object(values)]
        )
    }

    func resetMemory(config: ServerConfig, target: String) async throws {
        try await sendJSON(
            config: config, path: "/api/memory/reset", method: "POST",
            endpoint: L10n.string("记忆重置"), body: ["target": .string(target)]
        )
    }

    func learningGraph(config: ServerConfig) async throws -> LearningGraph {
        try await getJSON(
            config: config, path: "/api/learning/graph",
            endpoint: L10n.string("学习图谱")
        )
    }

    func learningNode(
        config: ServerConfig, id: String
    ) async throws -> LearningNodeContent {
        let raw: JSONValue = try await getJSON(
            config: config, path: "/api/learning/node",
            endpoint: L10n.string("学习节点"),
            query: [URLQueryItem(name: "id", value: id)]
        )
        return LearningNodeContent.extract(from: raw)
    }

    func updateLearningNode(
        config: ServerConfig, id: String, content: String
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/learning/node", method: "PUT",
            endpoint: L10n.string("学习节点改写"),
            body: ["id": .string(id), "content": .string(content)]
        )
    }

    func deleteLearningNode(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/learning/node", method: "DELETE",
            endpoint: L10n.string("学习节点删除"),
            body: ["id": .string(id)]
        )
    }

    // MARK: - 技能

    func skills(config: ServerConfig) async throws -> [SkillItem] {
        try await getJSON(config: config, path: "/api/skills", endpoint: L10n.string("技能接口"))
    }

    func skillContent(config: ServerConfig, name: String) async throws -> SkillContent {
        try await getJSON(
            config: config, path: "/api/skills/content", endpoint: L10n.string("技能内容"),
            query: [URLQueryItem(name: "name", value: name)]
        )
    }

    func updateSkillContent(config: ServerConfig, name: String, content: String) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/content", method: "PUT",
            endpoint: L10n.string("技能内容"),
            body: ["name": .string(name), "content": .string(content)]
        )
    }

    func toggleSkill(config: ServerConfig, name: String, enabled: Bool) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/toggle", method: "PUT",
            endpoint: L10n.string("技能开关"),
            body: ["name": .string(name), "enabled": .bool(enabled)]
        )
    }

    func lockSkill(config: ServerConfig, name: String, locked: Bool) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/lock", method: "PUT",
            endpoint: L10n.string("技能锁定"),
            body: ["name": .string(name), "locked": .bool(locked)]
        )
    }

    // MARK: - 技能商店（P10）

    /// hub 三读的长超时：服务端要抓外部注册表，本部署
    /// 实测 30s 无响应（出网受阻）——客户端放宽到 120s
    /// 等它自己失败/返回，超时按失败态呈给用户，不假装
    /// 商店里没东西
    private static let hubTimeout: TimeInterval = 120

    func skillHubSources(config: ServerConfig) async throws -> [HubSource] {
        let response: HubSourcesResponse = try await getJSON(
            config: config, path: "/api/skills/hub/sources",
            endpoint: L10n.string("技能商店来源"), timeout: Self.hubTimeout
        )
        return response.sources
    }

    func skillHubSearch(
        config: ServerConfig, query: String, source: String?
    ) async throws -> [HubSkill] {
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "30"),
        ]
        if let source, !source.isEmpty {
            queryItems.append(URLQueryItem(name: "source", value: source))
        }
        let response: HubSearchResponse = try await getJSON(
            config: config, path: "/api/skills/hub/search",
            endpoint: L10n.string("技能商店搜索"), query: queryItems,
            timeout: Self.hubTimeout
        )
        return response.results
    }

    func skillHubPreview(
        config: ServerConfig, identifier: String
    ) async throws -> HubPreview {
        try await getJSON(
            config: config, path: "/api/skills/hub/preview",
            endpoint: L10n.string("技能预览"),
            query: [URLQueryItem(name: "identifier", value: identifier)],
            timeout: Self.hubTimeout
        )
    }

    func skillHubInstall(config: ServerConfig, identifier: String) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/hub/install", method: "POST",
            endpoint: L10n.string("技能安装"),
            body: ["identifier": .string(identifier)],
            timeout: Self.hubTimeout
        )
    }

    func skillHubUninstall(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/hub/uninstall", method: "POST",
            endpoint: L10n.string("技能卸载"),
            body: ["name": .string(name)],
            timeout: Self.hubTimeout
        )
    }

    // MARK: - 定时任务

    func cronJobs(config: ServerConfig) async throws -> [CronJob] {
        try await getJSON(config: config, path: "/api/cron/jobs", endpoint: L10n.string("定时任务接口"))
    }

    func createCronJob(
        config: ServerConfig, name: String?, prompt: String, schedule: String, deliver: String?
    ) async throws -> CronJob {
        var body: [String: JSONValue] = [
            "prompt": .string(prompt),
            "schedule": .string(schedule),
        ]
        if let name, !name.isEmpty {
            body["name"] = .string(name)
        }
        if let deliver, !deliver.isEmpty {
            body["deliver"] = .string(deliver)
        }
        return try await sendJSONDecoding(
            config: config, path: "/api/cron/jobs", method: "POST",
            endpoint: L10n.string("定时任务创建"), body: body
        )
    }

    func updateCronJob(
        config: ServerConfig, id: String, updates: [String: JSONValue]
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)", method: "PUT",
            endpoint: L10n.string("定时任务更新"), body: ["updates": .object(updates)]
        )
    }

    func deleteCronJob(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)", method: "DELETE",
            endpoint: L10n.string("定时任务删除")
        )
    }

    func pauseCronJob(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)/pause", method: "POST",
            endpoint: L10n.string("定时任务暂停")
        )
    }

    func resumeCronJob(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)/resume", method: "POST",
            endpoint: L10n.string("定时任务恢复")
        )
    }

    func triggerCronJob(config: ServerConfig, id: String) async throws {
        // 触发是同步执行：服务端等任务跑完才回执，放宽超时
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)/trigger", method: "POST",
            endpoint: L10n.string("定时任务触发"), timeout: 600
        )
    }

    func cronRuns(config: ServerConfig, id: String, limit: Int) async throws -> [ServerSession] {
        let response: CronRunsResponse = try await getJSON(
            config: config, path: "/api/cron/jobs/\(id)/runs",
            endpoint: L10n.string("定时任务运行记录"),
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return response.runs
    }

    // MARK: - 定时蓝图与投递目标（§388 H6）

    func cronBlueprints(config: ServerConfig) async throws -> [CronBlueprint] {
        let response: CronBlueprintsResponse = try await getJSON(
            config: config, path: "/api/cron/blueprints",
            endpoint: L10n.string("定时任务模板")
        )
        return response.blueprints
    }

    func instantiateBlueprint(
        config: ServerConfig, blueprint: String, values: [String: JSONValue]
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/blueprints/instantiate",
            method: "POST", endpoint: L10n.string("定时任务模板创建"),
            body: [
                "blueprint": .string(blueprint),
                "values": .object(values),
            ]
        )
    }

    func cronDeliveryTargets(config: ServerConfig) async throws -> [CronDeliveryTarget] {
        let response: CronDeliveryTargetsResponse = try await getJSON(
            config: config, path: "/api/cron/delivery-targets",
            endpoint: L10n.string("定时任务投递目标")
        )
        return response.targets
    }

    // MARK: - 服务端会话

    func serverSessions(config: ServerConfig, limit: Int) async throws -> SessionsPage {
        try await getJSON(
            config: config, path: "/api/sessions", endpoint: L10n.string("服务端会话"),
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    func serverSession(config: ServerConfig, id: String) async throws -> ServerSession {
        try await getJSON(
            config: config, path: "/api/sessions/\(id)", endpoint: L10n.string("服务端会话详情")
        )
    }

    func sessionMutationSnapshot(
        config: ServerConfig, id: String
    ) async throws -> SessionMutationSnapshot {
        try await getJSON(
            config: config, path: "/api/sessions/\(id)/mutation-snapshot",
            endpoint: L10n.string("服务端会话变更快照")
        )
    }

    /// 写请求原始回执形：不抛状态错、把响应体带回来
    /// ——围栏类接口的拒因在 body 的 detail 码里
    /// （revision_conflict/session_busy/…），sendJSON
    /// 把 body 丢掉的旧形到不了分流逻辑（报告 §2.3）。
    /// 传输层失败仍走 dataRequest 的 HermesError 映射
    private func sendRaw(
        config: ServerConfig, path: String, method: String,
        query: [URLQueryItem] = []
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url(config: config, path: path, query: query))
        request.httpMethod = method
        let (data, http) = try await dataRequest(request)
        return (http.statusCode, data)
    }

    /// sendRaw 的带体形（D3/D2 rewind 用）：围栏写口
    /// 的拒因同样在 body detail 码里，状态与响应体都
    /// 要带回分流；请求体走专用 Encodable 直编（整数
    /// 字段不许经 JSONValue.number(Double) 转手）
    private func sendRawJSON<Body: Encodable>(
        config: ServerConfig, path: String, method: String,
        body: Body
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url(config: config, path: path))
        request.httpMethod = method
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, http) = try await dataRequest(request)
        return (http.statusCode, data)
    }

    func createServerSession(config: ServerConfig, apiKey: String, id: String?, title: String?) async throws -> ServerSession {
        // 0.27.0：网关面 Bearer 送达（见协议注）；请求
        // 体组装走 Core 纯函数（单测把守形态）
        let created: CreatedSession = try await sendJSONDecoding(
            config: config, path: "/api/sessions", method: "POST",
            endpoint: L10n.string("服务端会话创建"),
            body: SideChatLink.createSessionBody(id: id, title: title),
            bearer: apiKey
        )
        return created.session
    }

    func createLinkedServerSession(config: ServerConfig, apiKey: String, id: String, model: String) async throws -> ServerSession {
        // 0.21.0：研究档实测链口径——建会话带 model＋
        // require_model_lock:true 得确认锁（route 无法
        // 落锁时服务端 409 拒、不会静默兜底）；title
        // 不带（见协议注）。0.27.0：网关面 Bearer 送达
        let created: CreatedSession = try await sendJSONDecoding(
            config: config, path: "/api/sessions", method: "POST",
            endpoint: L10n.string("旁聊会话创建"),
            body: SideChatLink.linkedCreateSessionBody(id: id, model: model),
            bearer: apiKey
        )
        return created.session
    }

    func importServerSession(
        config: ServerConfig, requestID: String,
        expectedRevision: Int, sessionBody: [String: JSONValue]
    ) async throws {
        // Dashboard 面 cookie 通道（调用方在
        // performAdmin 内执行、401 自动重登口径同其
        // 他 /api/*）；回执 {ok:true,…} 不解码，落定
        // 靠调用方 GET 回读对账（O-4）
        try await sendJSON(
            config: config, path: "/api/sessions/import", method: "POST",
            endpoint: L10n.string("会话种子导入"),
            body: SideChatLink.importRequestBody(
                requestID: requestID,
                expectedRevision: expectedRevision,
                sessions: [sessionBody]
            )
        )
    }

    func updateServerSessionModel(config: ServerConfig, id: String, model: String) async throws {
        try await sendJSON(
            config: config, path: "/api/sessions/\(id)/model", method: "POST",
            endpoint: L10n.string("会话模型切换"), body: ["model": .string(model)]
        )
    }

    func sessionMessages(config: ServerConfig, id: String) async throws -> [SessionMessage] {
        let response: SessionMessagesResponse = try await getJSON(
            config: config, path: "/api/sessions/\(id)/messages",
            endpoint: L10n.string("服务端会话消息")
        )
        return response.messages
    }

    func sessionMessagesPage(
        config: ServerConfig, id: String, limit: Int, offset: Int,
        afterRowID: Int? = nil
    ) async throws -> [SessionMessage] {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            // §331：规范值 latest（服务端只认
            // oldest/latest，desc 会吃 400）
            URLQueryItem(name: "order", value: "latest"),
        ]
        if let afterRowID {
            query.append(
                URLQueryItem(name: "after_row_id", value: String(afterRowID))
            )
        }
        let response: SessionMessagesResponse = try await getJSON(
            config: config, path: "/api/sessions/\(id)/messages",
            endpoint: L10n.string("服务端会话消息"),
            query: query
        )
        return response.messages
    }

    func searchSessions(
        config: ServerConfig, query: String, limit: Int
    ) async throws -> [SessionSearchHit] {
        let response: SessionSearchResponse = try await getJSON(
            config: config, path: "/api/sessions/search",
            endpoint: L10n.string("会话搜索"),
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        return response.results
    }

    func sessionTimeline(
        config: ServerConfig, id: String,
        afterRowID: Int64?, limit: Int
    ) async throws -> SessionTimelinePage {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let afterRowID {
            query.append(
                URLQueryItem(
                    name: "after_row_id", value: String(afterRowID)
                )
            )
        }
        let raw: JSONValue = try await getJSON(
            config: config, path: "/api/sessions/\(id)/timeline",
            endpoint: L10n.string("会话时间线"),
            query: query
        )
        return SessionTimelinePage.extract(from: raw)
    }

    func sessionMessagesAround(
        config: ServerConfig, id: String,
        rowID: Int64, limit: Int
    ) async throws -> SessionAroundPage {
        try await getJSON(
            config: config, path: "/api/sessions/\(id)/messages/around",
            endpoint: L10n.string("消息上下文窗口"),
            query: [
                URLQueryItem(name: "row_id", value: String(rowID)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    func deleteServerSession(config: ServerConfig, id: String) async throws {
        // 0.50.30 围栏接线（DESIGN §204.6）：DELETE 与
        // PATCH 同围栏制，三参数必须走 query string
        // （放 body 或缺失必被拒）。
        // 删除 409 热修（报告 §1.4/§2）：身份改读官方
        // mutation-snapshot，不再经详情 GET——详情回
        // 包的 int 形 archived/pinned 曾把 DTO 解码整
        // 行打死、旧实现 try? 吞错后裸发 DELETE，必吃
        // client_upgrade_required 409 且重试同死。每
        // 试现读快照、request_id 每试新铸（已删后靠快
        // 照 404/exists=false 与 DELETE 404 收口，不依
        // 赖同 request_id 的收据重放）；收口按 Core 的
        // SessionDeleteDirective 分流：冲突重读即时再
        // 试、busy 短等再试（共 3 试）、耗尽按码如实
        // 上抛（busy 报 sessionBusy 人话）。身份读不
        // 到就报错、什么都不发——删掉裸发回退：服务
        // 端契约是无围栏永不落改，裸发只是亲手制造一
        // 个误导性 409
        let endpoint = L10n.string("服务端会话删除")
        for attempt in 0..<3 {
            let snapshot: SessionMutationSnapshot
            do {
                snapshot = try await sessionMutationSnapshot(config: config, id: id)
            } catch let error as HermesError {
                if case .unexpectedStatus(_, let status) = error, status == 404 {
                    return  // 快照都读不到这条＝已经不在了
                }
                throw error
            }
            if snapshot.exists == false {
                return  // 服务端明示已不在，删除目的已达成
            }
            guard let revision = snapshot.runtimeRevision,
                  let generation = snapshot.runtimeGeneration else {
                throw HermesError.decodingFailed(endpoint: endpoint)
            }
            let (status, body) = try await sendRaw(
                config: config, path: "/api/sessions/\(id)", method: "DELETE",
                query: [
                    URLQueryItem(name: "request_id", value: UUID().uuidString),
                    URLQueryItem(name: "expected_revision", value: String(revision)),
                    URLQueryItem(name: "expected_generation", value: String(generation)),
                ]
            )
            switch SessionDeleteDirective.directive(
                status: status, serverCode: HermesServerErrorCode.parse(body)
            ) {
            case .done:
                return
            case .retryWithFreshIdentity:
                if attempt < 2 { continue }
            case .retryAfterBusy:
                if attempt < 2 {
                    try await Task.sleep(
                        for: attempt == 0 ? .milliseconds(1500) : .seconds(3)
                    )
                    continue
                }
                throw HermesError.sessionBusy
            case .fail:
                break
            }
            throw HermesError.unexpectedStatus(endpoint: endpoint, status: status)
        }
    }

    /// rewind 落地（DESIGN §352）：与 deleteServer-
    /// Session 同构的围栏写口——快照现读→组 Rewind-
    /// Request（request_id 每试新铸）→POST→Core 的
    /// RewindDirective 分流。冲突先对账：回执可能已
    /// 在服务端落了截断却丢在路上，先比尾行（GET
    /// messages 最大行 id＝＝predecessorRowID，或无
    /// 前行且列表为空）——已截断直接 done，不许对同
    /// 一 target 二次 POST（第二次的 target 已不在，
    /// 只会吃 invalid_params 假失败）。网络瞬断（结
    /// 果未知）同律：先对账，未截断且围栏未变才许
    /// 重发一次。身份读不到 fail-closed（同 DELETE
    /// 口径：什么都不发）
    func rewindSession(
        config: ServerConfig, id: String,
        targetMessageID: Int, predecessorRowID: Int?
    ) async throws -> RewindReceipt {
        let endpoint = L10n.string("服务端消息回退")
        // 对账：服务端尾行是否已停在 target 前一行
        func alreadyRewound() async -> Bool {
            guard let messages = try? await sessionMessages(
                config: config, id: id
            ) else { return false }
            let tail = messages.compactMap {
                Int(exactly: $0.id)
            }.max()
            return tail == predecessorRowID
        }
        var conflictRetries = 0
        var busyRetries = 0
        var transportReposts = 0
        while true {
            let snapshot: SessionMutationSnapshot
            do {
                snapshot = try await sessionMutationSnapshot(
                    config: config, id: id
                )
            } catch let error as HermesError {
                if case .unexpectedStatus(_, let status) = error,
                   status == 404 {
                    throw RewindError.invalidTarget
                }
                throw error
            }
            if snapshot.exists == false {
                throw RewindError.invalidTarget
            }
            guard let revision = snapshot.runtimeRevision,
                  let generation = snapshot.runtimeGeneration else {
                throw HermesError.decodingFailed(endpoint: endpoint)
            }
            let request = RewindRequest(
                requestID: UUID().uuidString,
                expectedRevision: revision,
                expectedGeneration: generation,
                targetMessageID: targetMessageID
            )
            let status: Int
            let body: Data
            do {
                (status, body) = try await sendRawJSON(
                    config: config,
                    path: "/api/sessions/\(id)/rewind",
                    method: "POST", body: request
                )
            } catch let error as HermesError {
                // 结果未知：不盲重 POST——先对账，已截
                // 断即 done；未截断且围栏未变（重读快照
                // 与本次同值）才重发一次；仍未知如实
                // 上抛（调用方走回滚，服务端未变由对
                // 账保证）
                if await alreadyRewound() {
                    return RewindReceipt(ok: true)
                }
                if transportReposts == 0,
                   let fresh = try? await sessionMutationSnapshot(
                       config: config, id: id
                   ),
                   fresh.runtimeRevision == revision,
                   fresh.runtimeGeneration == generation {
                    transportReposts += 1
                    continue
                }
                throw error
            }
            switch RewindDirective.directive(
                status: status,
                serverCode: HermesServerErrorCode.parse(body)
            ) {
            case .done:
                if let receipt = try? JSONDecoder().decode(
                    RewindReceipt.self, from: body
                ) {
                    return receipt
                }
                return RewindReceipt(ok: true)
            case .reconcileConflict:
                if await alreadyRewound() {
                    return RewindReceipt(ok: true)
                }
                conflictRetries += 1
                if conflictRetries > 2 {
                    throw RewindError.conflictExhausted
                }
                continue
            case .retryAfterBusy:
                busyRetries += 1
                if busyRetries > 3 {
                    throw HermesError.sessionBusy
                }
                try await Task.sleep(
                    for: busyRetries == 1
                        ? .milliseconds(1500) : .seconds(3)
                )
                continue
            case .failInvalidTarget:
                throw RewindError.invalidTarget
            case .fail:
                throw HermesError.unexpectedStatus(
                    endpoint: endpoint, status: status
                )
            }
        }
    }

    func emptySessionCount(config: ServerConfig) async throws -> Int {
        struct CountResponse: Decodable { let count: Int? }
        let response: CountResponse = try await getJSON(
            config: config, path: "/api/sessions/empty/count",
            endpoint: L10n.string("空会话计数")
        )
        return response.count ?? 0
    }

    func serverSessionsPage(
        config: ServerConfig, limit: Int, offset: Int, archived: String?
    ) async throws -> SessionsPage {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let archived {
            query.append(URLQueryItem(name: "archived", value: archived))
        }
        return try await getJSON(
            config: config, path: "/api/sessions", endpoint: L10n.string("服务端会话"),
            query: query
        )
    }

    func updateServerSession(
        config: ServerConfig, id: String,
        title: String?, pinned: Bool?, archived: Bool?
    ) async throws {
        // 0.27.0 围栏接线（见协议注）＋删除 409 热修
        // 收口：修订号改读 mutation-snapshot（官方身
        // 份源、与 DELETE 同源），PATCH 带 request_id
        // ＋expected_revision；409 冲突重读重试一次，
        // 再失败如实上抛。旧「修订号读不到退回无围栏
        // 直发」的回退就此删除——详情解码曾被 int 形
        // archived/pinned 恒打死、回退实际一直在裸发
        // 必拒请求（报告 §2.2）；读不到改为如实上抛
        for attempt in 0..<2 {
            let snapshot = try await sessionMutationSnapshot(config: config, id: id)
            if snapshot.exists == false {
                throw HermesError.unexpectedStatus(
                    endpoint: L10n.string("服务端会话更新"), status: 404
                )
            }
            guard let revision = snapshot.runtimeRevision else {
                throw HermesError.decodingFailed(
                    endpoint: L10n.string("服务端会话更新")
                )
            }
            var body: [String: JSONValue] = [:]
            if let title { body["title"] = .string(title) }
            if let pinned { body["pinned"] = .bool(pinned) }
            if let archived { body["archived"] = .bool(archived) }
            body["request_id"] = .string(UUID().uuidString)
            body["expected_revision"] = .number(Double(revision))
            do {
                try await sendJSON(
                    config: config, path: "/api/sessions/\(id)",
                    method: "PATCH", endpoint: L10n.string("服务端会话更新"),
                    body: body
                )
                return
            } catch let error as HermesError {
                if case .unexpectedStatus(_, let status) = error,
                   status == 409, attempt == 0 {
                    continue
                }
                throw error
            }
        }
    }

    func pruneSessions(
        config: ServerConfig, olderThanDays: Double, dryRun: Bool
    ) async throws -> Int? {
        let receipt: JSONValue = try await sendJSONDecoding(
            config: config, path: "/api/sessions/prune", method: "POST",
            endpoint: L10n.string("服务端会话清理"),
            body: [
                "older_than_days": .number(olderThanDays),
                "dry_run": .bool(dryRun),
            ]
        )
        return SessionPruneReceipt.count(from: receipt)
    }

    // MARK: - 档案

    func profiles(config: ServerConfig) async throws -> [ProfileItem] {
        let response: ProfilesResponse = try await getJSON(
            config: config, path: "/api/profiles", endpoint: L10n.string("档案接口")
        )
        return response.profiles
    }

    func activeProfileName(config: ServerConfig) async throws -> String? {
        let response: ActiveProfileResponse = try await getJSON(
            config: config, path: "/api/profiles/active", endpoint: L10n.string("当前档案")
        )
        return response.name
    }

    func activeProfile(
        config: ServerConfig
    ) async throws -> ActiveProfileResponse {
        try await getJSON(
            config: config, path: "/api/profiles/active",
            endpoint: L10n.string("当前档案")
        )
    }

    func setActiveProfile(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: "/api/profiles/active", method: "POST",
            endpoint: L10n.string("档案切换"), body: ["name": .string(name)]
        )
    }

    /// profile 名按单个 path segment 百分号编码：profile
    /// 名是用户可控字符串，不许把 "/" 等分隔符带进路径
    /// （数据设计 §2.4；现有客户端多处直接插值 id，soul
    /// 方法不复制这个缺口）
    private func soulPath(name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? name
        return "/api/profiles/\(encoded)/soul"
    }

    func profileSoul(
        config: ServerConfig, name: String
    ) async throws -> ProfileSoulDocument {
        try await getJSON(
            config: config, path: soulPath(name: name), endpoint: L10n.string("档案人设")
        )
    }

    func updateProfileSoul(
        config: ServerConfig, name: String, content: String
    ) async throws {
        try await sendJSON(
            config: config, path: soulPath(name: name), method: "PUT",
            endpoint: L10n.string("档案人设"),
            body: ["content": .string(content)]
        )
    }

    /// 档案名 path 段编码（与 soulPath 同口径：用户可控
    /// 字符串不许带分隔符进路径）
    private func profilePath(name: String, suffix: String = "") -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? name
        return "/api/profiles/\(encoded)\(suffix)"
    }

    func createProfile(
        config: ServerConfig, name: String, cloneFrom: String?
    ) async throws {
        var body: [String: JSONValue] = ["name": .string(name)]
        if let cloneFrom, !cloneFrom.isEmpty {
            body["clone_from"] = .string(cloneFrom)
        }
        try await sendJSON(
            config: config, path: "/api/profiles", method: "POST",
            endpoint: L10n.string("档案创建"), body: body
        )
    }

    func deleteProfile(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: profilePath(name: name), method: "DELETE",
            endpoint: L10n.string("档案删除")
        )
    }

    func exportProfile(
        config: ServerConfig, name: String
    ) async throws -> ProfileExportResult {
        try await sendJSONDecoding(
            config: config, path: profilePath(name: name, suffix: "/export"),
            method: "POST", endpoint: L10n.string("档案导出"), body: [:]
        )
    }

    func importProfile(
        config: ServerConfig, archive: String, name: String?
    ) async throws {
        var body: [String: JSONValue] = ["archive": .string(archive)]
        if let name, !name.isEmpty {
            body["name"] = .string(name)
        }
        try await sendJSON(
            config: config, path: "/api/profiles/import", method: "POST",
            endpoint: L10n.string("档案导入"), body: body
        )
    }

    func renameProfile(
        config: ServerConfig, name: String, newName: String
    ) async throws {
        try await sendJSON(
            config: config, path: profilePath(name: name), method: "PATCH",
            endpoint: L10n.string("分身重命名"),
            body: ["new_name": .string(newName)]
        )
    }

    func updateProfileDescription(
        config: ServerConfig, name: String, description: String
    ) async throws {
        try await sendJSON(
            config: config, path: profilePath(name: name, suffix: "/description"),
            method: "PUT", endpoint: L10n.string("分身简介"),
            body: ["description": .string(description)]
        )
    }

    func autoDescribeProfile(
        config: ServerConfig, name: String, overwrite: Bool
    ) async throws -> ProfileAutoDescribeResult {
        try await sendJSONDecoding(
            config: config, path: profilePath(name: name, suffix: "/describe-auto"),
            method: "POST", endpoint: L10n.string("自动生成分身简介"),
            body: ["overwrite": .bool(overwrite)]
        )
    }

    func updateProfileModel(
        config: ServerConfig, name: String, provider: String, model: String
    ) async throws {
        try await sendJSON(
            config: config, path: profilePath(name: name, suffix: "/model"),
            method: "PUT", endpoint: L10n.string("分身模型绑定"),
            body: [
                "provider": .string(provider),
                "model": .string(model),
            ]
        )
    }

}
