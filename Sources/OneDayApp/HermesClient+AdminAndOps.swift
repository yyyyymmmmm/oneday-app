import Foundation
import OneDayCore

// MARK: - HermesClient 配置、运维、语音、认领、推送、票据、授权与高级能力域（#37 模块化拆分）

extension HermesClient {
    // MARK: - MCP 连接（P10）

    /// MCP 名 path 段编码（同 profilePath 口径）
    private func mcpPath(name: String, suffix: String = "") -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? name
        return "/api/mcp/servers/\(encoded)\(suffix)"
    }

    func mcpServers(config: ServerConfig) async throws -> [MCPServerItem] {
        let response: MCPServersResponse = try await getJSON(
            config: config, path: "/api/mcp/servers", endpoint: L10n.string("MCP 连接")
        )
        return response.servers
    }

    func setMCPServerEnabled(
        config: ServerConfig, name: String, enabled: Bool
    ) async throws {
        try await sendJSON(
            config: config, path: mcpPath(name: name, suffix: "/enabled"),
            method: "PUT", endpoint: L10n.string("MCP 开关"),
            body: ["enabled": .bool(enabled)]
        )
    }

    func testMCPServer(
        config: ServerConfig, name: String
    ) async throws -> MCPTestResult {
        try await sendJSONDecoding(
            config: config, path: mcpPath(name: name, suffix: "/test"),
            method: "POST", endpoint: L10n.string("MCP 测试"), body: [:]
        )
    }

    // MARK: - MCP 目录（§388 H7）

    func mcpCatalog(config: ServerConfig) async throws -> MCPCatalogResponse {
        try await getJSON(
            config: config, path: "/api/mcp/catalog",
            endpoint: L10n.string("MCP 目录")
        )
    }

    func installMCPCatalogEntry(
        config: ServerConfig, name: String, env: [String: String], enable: Bool
    ) async throws -> MCPInstallReceipt {
        try await sendJSONDecoding(
            config: config, path: "/api/mcp/catalog/install",
            method: "POST", endpoint: L10n.string("MCP 目录安装"),
            body: [
                "name": .string(name),
                "env": .object(env.mapValues { JSONValue.string($0) }),
                "enable": .bool(enable),
            ]
        )
    }

    func addMCPServer(
        config: ServerConfig, name: String, url: String?,
        command: String?, args: [String], env: [String: String],
        auth: String?, bearerToken: String?
    ) async throws {
        var body: [String: JSONValue] = [
            "name": .string(name),
            "args": .array(args.map { .string($0) }),
            "env": .object(env.mapValues { .string($0) }),
        ]
        if let url, !url.isEmpty { body["url"] = .string(url) }
        if let command, !command.isEmpty { body["command"] = .string(command) }
        if let auth, !auth.isEmpty { body["auth"] = .string(auth) }
        if let bearerToken, !bearerToken.isEmpty {
            body["bearer_token"] = .string(bearerToken)
        }
        try await sendJSON(
            config: config, path: "/api/mcp/servers",
            method: "POST", endpoint: L10n.string("添加 MCP 服务"),
            body: body
        )
    }

    func deleteMCPServer(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: mcpPath(name: name),
            method: "DELETE", endpoint: L10n.string("删除 MCP 服务")
        )
    }

    func startMCPOAuthFlow(config: ServerConfig, name: String) async throws -> MCPOAuthFlowSnapshot {
        try await sendJSONDecoding(
            config: config, path: mcpPath(name: name, suffix: "/auth"),
            method: "POST", endpoint: L10n.string("MCP OAuth 授权"),
            body: [:]
        )
    }

    func pollMCPOAuthFlow(config: ServerConfig, flowID: String) async throws -> MCPOAuthFlowSnapshot {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = flowID.addingPercentEncoding(withAllowedCharacters: allowed) ?? flowID
        return try await getJSON(
            config: config, path: "/api/mcp/oauth/flows/\(encoded)",
            endpoint: L10n.string("MCP OAuth 状态")
        )
    }

    func cancelMCPOAuthFlow(config: ServerConfig, flowID: String) async throws {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = flowID.addingPercentEncoding(withAllowedCharacters: allowed) ?? flowID
        try await sendJSON(
            config: config, path: "/api/mcp/oauth/flows/\(encoded)",
            method: "DELETE", endpoint: L10n.string("取消 MCP OAuth")
        )
    }

    // MARK: - Agent Plugins 插件市场（Hermes v0.23.0 dashboard_ui.py）

    private func pluginPath(name: String, suffix: String = "") -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
        return "/api/dashboard/agent-plugins/\(encoded)\(suffix)"
    }

    func pluginsHub(config: ServerConfig) async throws -> [AgentPluginItem] {
        let response: AgentPluginsHubResponse = try await getJSON(
            config: config, path: "/api/dashboard/plugins/hub",
            endpoint: L10n.string("插件中心")
        )
        return response.plugins
    }

    func pluginsCatalog(config: ServerConfig) async throws -> [AgentPluginCatalogEntry] {
        let response: AgentPluginCatalogResponse = try await getJSON(
            config: config, path: "/api/dashboard/plugins/catalog",
            endpoint: L10n.string("插件目录")
        )
        return response.entries
    }

    func installAgentPlugin(
        config: ServerConfig, identifier: String?, catalogName: String?, enable: Bool
    ) async throws {
        var body: [String: JSONValue] = [
            "identifier": .string(identifier ?? ""),
            "enable": .bool(enable),
        ]
        if let catalogName, !catalogName.isEmpty {
            body["catalog_name"] = .string(catalogName)
        }
        try await sendJSON(
            config: config, path: "/api/dashboard/agent-plugins/install",
            method: "POST", endpoint: L10n.string("安装插件"),
            body: body, timeout: 120
        )
    }

    func setAgentPluginEnabled(config: ServerConfig, name: String, enabled: Bool) async throws {
        try await sendJSON(
            config: config, path: pluginPath(name: name, suffix: enabled ? "/enable" : "/disable"),
            method: "POST", endpoint: L10n.string("插件开关")
        )
    }

    func updateAgentPlugin(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: pluginPath(name: name, suffix: "/update"),
            method: "POST", endpoint: L10n.string("更新插件"),
            body: [:], timeout: 120
        )
    }

    func updateAllAgentPlugins(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/dashboard/agent-plugins/update-all",
            method: "POST", endpoint: L10n.string("全部更新插件"),
            timeout: 180
        )
    }

    func deleteAgentPlugin(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: pluginPath(name: name),
            method: "DELETE", endpoint: L10n.string("卸载插件")
        )
    }

    func pluginsAutoUpdate(config: ServerConfig) async throws -> PluginAutoUpdateState {
        try await getJSON(
            config: config, path: "/api/dashboard/plugins/auto-update",
            endpoint: L10n.string("插件自动更新状态")
        )
    }

    func setPluginsAutoUpdate(config: ServerConfig, enabled: Bool) async throws -> PluginAutoUpdateState {
        try await sendJSONDecoding(
            config: config, path: "/api/dashboard/plugins/auto-update",
            method: "PUT", endpoint: L10n.string("插件自动更新设置"),
            body: ["enabled": .bool(enabled)]
        )
    }

    func voiceLiveStatus(config: ServerConfig) async throws -> VoiceLiveStatus {
        try await getJSON(
            config: config, path: "/api/audio/voice-live/status",
            endpoint: L10n.string("实时语音状态")
        )
    }

    func transcribeAudio(
        config: ServerConfig, dataURL: String, mimeType: String?
    ) async throws -> AudioTranscribeReceipt {
        var body: [String: JSONValue] = ["data_url": .string(dataURL)]
        if let mimeType, !mimeType.isEmpty {
            body["mime_type"] = .string(mimeType)
        }
        return try await sendJSONDecoding(
            config: config, path: "/api/audio/transcribe",
            method: "POST", endpoint: L10n.string("音频转写"),
            body: body
        )
    }

    // MARK: - 自定义模型端点与凭据池（Hermes v0.23.0）

    private func encodedPathSegment(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    func customEndpoints(config: ServerConfig) async throws -> CustomEndpointsResponse {
        try await getJSON(
            config: config, path: "/api/providers/custom-endpoints",
            endpoint: L10n.string("自定义模型端点")
        )
    }

    func upsertCustomEndpoint(
        config: ServerConfig, id: String?, name: String, baseURL: String,
        apiKey: String?, model: String?, makeDefault: Bool
    ) async throws {
        var body: [String: JSONValue] = [
            "name": .string(name),
            "base_url": .string(baseURL),
            "make_default": .bool(makeDefault),
        ]
        if let id, !id.isEmpty { body["id"] = .string(id) }
        if let apiKey { body["api_key"] = .string(apiKey) }
        if let model, !model.isEmpty { body["model"] = .string(model) }
        try await sendJSON(
            config: config, path: "/api/providers/custom-endpoints",
            method: "POST", endpoint: L10n.string("保存自定义端点"),
            body: body
        )
    }

    func activateCustomEndpoint(config: ServerConfig, endpointID: String) async throws {
        let encoded = encodedPathSegment(endpointID)
        try await sendJSON(
            config: config, path: "/api/providers/custom-endpoints/\(encoded)/activate",
            method: "POST", endpoint: L10n.string("启用自定义端点"),
            body: [:]
        )
    }

    func deleteCustomEndpoint(config: ServerConfig, endpointID: String) async throws {
        let encoded = encodedPathSegment(endpointID)
        try await sendJSON(
            config: config, path: "/api/providers/custom-endpoints/\(encoded)",
            method: "DELETE", endpoint: L10n.string("删除自定义端点")
        )
    }

    func validateCustomEndpoint(
        config: ServerConfig, baseURL: String, apiKey: String?, model: String?
    ) async throws -> CustomEndpointValidationResult {
        var body: [String: JSONValue] = [
            "name": .string("probe"),
            "base_url": .string(baseURL),
        ]
        if let apiKey, !apiKey.isEmpty { body["api_key"] = .string(apiKey) }
        if let model, !model.isEmpty { body["model"] = .string(model) }
        return try await sendJSONDecoding(
            config: config, path: "/api/providers/custom-endpoints/validate",
            method: "POST", endpoint: L10n.string("校验自定义端点"),
            body: body
        )
    }

    func credentialPool(config: ServerConfig) async throws -> [CredentialPoolProviderGroup] {
        let response: CredentialPoolResponse = try await getJSON(
            config: config, path: "/api/credentials/pool",
            endpoint: L10n.string("凭据池")
        )
        return response.providers
    }

    func addCredentialPoolEntry(
        config: ServerConfig, provider: String, apiKey: String, label: String?
    ) async throws {
        var body: [String: JSONValue] = [
            "provider": .string(provider),
            "api_key": .string(apiKey),
        ]
        if let label, !label.isEmpty { body["label"] = .string(label) }
        try await sendJSON(
            config: config, path: "/api/credentials/pool",
            method: "POST", endpoint: L10n.string("添加凭据池密钥"),
            body: body
        )
    }

    func deleteCredentialPoolEntry(
        config: ServerConfig, provider: String, index: Int
    ) async throws {
        let encoded = encodedPathSegment(provider)
        try await sendJSON(
            config: config, path: "/api/credentials/pool/\(encoded)/\(index)",
            method: "DELETE", endpoint: L10n.string("删除凭据池密钥")
        )
    }

    // MARK: - Bot Mode 多智能体房间协作与授权（Hermes v0.23.0）

    func createRoomInvitation(
        config: ServerConfig, apiKey: String, roomID: String,
        homeInstallID: String, authorityGatewayID: String,
        authorityEpoch: Int, memberID: String, ttlSeconds: Int
    ) async throws -> RoomMemberInvitationReceipt {
        let body: [String: JSONValue] = [
            "room_id": .string(roomID),
            "home_install_id": .string(homeInstallID),
            "authority_gateway_id": .string(authorityGatewayID),
            "authority_epoch": .number(Double(authorityEpoch)),
            "member_id": .string(memberID),
            "ttl_seconds": .number(Double(ttlSeconds)),
        ]
        return try await sendJSONDecoding(
            config: config, path: "/v1/room-members/invitations",
            method: "POST", endpoint: L10n.string("创建房间邀请"),
            body: body, bearer: apiKey
        )
    }

    private func hermesRoomRequest<T: Decodable>(
        config: ServerConfig, path: String, method: String,
        grantToken: String, body: [String: JSONValue]? = nil,
        endpoint: String
    ) async throws -> T {
        var request = URLRequest(url: config.endpoint(path))
        request.httpMethod = method
        request.setValue("HermesRoom \(grantToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.fromHTTPResponse(
                endpoint: endpoint, status: http.statusCode,
                data: data, retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    func roomMemberCapabilities(
        config: ServerConfig, grantToken: String
    ) async throws -> RoomMemberCapabilitiesResponse {
        try await hermesRoomRequest(
            config: config, path: "/v1/room-members/capabilities",
            method: "GET", grantToken: grantToken,
            endpoint: L10n.string("房间成员能力")
        )
    }

    func refreshRoomGrant(
        config: ServerConfig, grantToken: String, ttlSeconds: Int
    ) async throws -> RoomGrantRefreshReceipt {
        try await hermesRoomRequest(
            config: config, path: "/v1/room-members/grants/refresh",
            method: "POST", grantToken: grantToken,
            body: ["ttl_seconds": .number(Double(ttlSeconds))],
            endpoint: L10n.string("续期房间授权")
        )
    }

    func revokeRoomGrant(
        config: ServerConfig, grantToken: String
    ) async throws -> RoomGrantRevokeReceipt {
        try await hermesRoomRequest(
            config: config, path: "/v1/room-members/grants/revoke",
            method: "POST", grantToken: grantToken,
            body: [:],
            endpoint: L10n.string("撤销房间授权")
        )
    }

    func computerUseStatus(
        config: ServerConfig
    ) async throws -> ComputerUseStatus {
        try await getJSON(
            config: config, path: "/api/tools/computer-use/status",
            endpoint: L10n.string("电脑操作状态")
        )
    }

    // MARK: - 配置与密钥

    func rawConfig(config: ServerConfig) async throws -> [String: JSONValue] {
        try await getJSON(config: config, path: "/api/config", endpoint: L10n.string("配置接口"))
    }

    func updateConfig(config: ServerConfig, newConfig: [String: JSONValue]) async throws {
        try await sendJSON(
            config: config, path: "/api/config", method: "PUT",
            endpoint: L10n.string("配置写入"), body: ["config": .object(newConfig)]
        )
    }

    func envVars(config: ServerConfig) async throws -> [EnvVarEntry] {
        let response: EnvVars = try await getJSON(
            config: config, path: "/api/env", endpoint: L10n.string("密钥接口")
        )
        return response.entries
    }

    func setEnvVar(config: ServerConfig, key: String, value: String) async throws {
        try await sendJSON(
            config: config, path: "/api/env", method: "PUT",
            endpoint: L10n.string("密钥写入"),
            body: ["key": .string(key), "value": .string(value)]
        )
    }

    func deleteEnvVar(config: ServerConfig, key: String) async throws {
        try await sendJSON(
            config: config, path: "/api/env", method: "DELETE",
            endpoint: L10n.string("密钥删除"), body: ["key": .string(key)]
        )
    }

    func revealEnvVar(config: ServerConfig, key: String) async throws -> String {
        var request = URLRequest(url: config.endpoint("/api/env/reveal"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["key": JSONValue.string(key)])
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(endpoint: L10n.string("密钥查看"), status: http.statusCode)
        }
        // 回执形态宽容：{"value": "…"} / {"key": "…", "value": "…"} / 纯字符串
        let value = try decoder.decode(JSONValue.self, from: data)
        switch value {
        case .string(let text):
            return text
        case .object(let object):
            if let text = object["value"]?.stringValue {
                return text
            }
            throw HermesError.decodingFailed(endpoint: L10n.string("密钥查看"))
        default:
            throw HermesError.decodingFailed(endpoint: L10n.string("密钥查看"))
        }
    }

    // MARK: - 用量与日志

    func usageAnalytics(config: ServerConfig, days: Int) async throws -> UsageAnalytics {
        try await getJSON(
            config: config, path: "/api/analytics/usage", endpoint: L10n.string("用量接口"),
            query: [URLQueryItem(name: "days", value: String(days))]
        )
    }

    func modelAnalytics(config: ServerConfig, days: Int) async throws -> ModelAnalytics {
        try await getJSON(
            config: config, path: "/api/analytics/models", endpoint: L10n.string("模型用量接口"),
            query: [URLQueryItem(name: "days", value: String(days))]
        )
    }

    func modelOptionsRaw(config: ServerConfig) async throws -> JSONValue {
        try await getJSON(
            config: config, path: "/api/model/options", endpoint: L10n.string("模型列表接口")
        )
    }

    func modelOptions(config: ServerConfig) async throws -> [String] {
        // 扁平 id 口径保留给设置页候选管线（ModelCatalog）；
        // 整树由 modelOptionsRaw 出，顶栏分组走它（§153）
        let root = try await modelOptionsRaw(config: config)
        return ModelCatalog.extractModelIDs(from: root)
    }

    func setMainModel(
        config: ServerConfig, provider: String, model: String
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/model/set", method: "POST",
            endpoint: L10n.string("默认模型切换"),
            body: [
                "scope": .string("main"),
                "provider": .string(provider),
                "model": .string(model),
            ]
        )
    }

    func mainModelAssignment(
        config: ServerConfig, providerNames: [String]
    ) async throws -> MainModelAssignment {
        let root: JSONValue = try await getJSON(
            config: config, path: "/api/model/options",
            endpoint: L10n.string("模型列表接口")
        )
        return MainModelAssignment.parse(
            optionsRoot: root, providerNames: providerNames
        )
    }

    func logs(
        config: ServerConfig, level: String?, search: String?, lines: Int
    ) async throws -> LogsResponse {
        var query = [URLQueryItem(name: "lines", value: String(lines))]
        if let level, !level.isEmpty {
            query.append(URLQueryItem(name: "level", value: level))
        }
        if let search, !search.isEmpty {
            query.append(URLQueryItem(name: "search", value: search))
        }
        return try await getJSON(
            config: config, path: "/api/logs", endpoint: L10n.string("日志接口"), query: query
        )
    }

    func egressStatus(config: ServerConfig) async throws -> EgressStatus {
        try await getJSON(config: config, path: "/api/egress/status", endpoint: L10n.string("出口状态"))
    }

    // MARK: - 频道直连（API 直连 B 包）

    func messagingPlatforms(config: ServerConfig) async throws -> MessagingPlatformsResponse {
        try await getJSON(
            config: config, path: "/api/messaging/platforms",
            endpoint: L10n.string("频道状态")
        )
    }

    func updateMessagingPlatform(
        config: ServerConfig, platform: String, enabled: Bool,
        env: [String: String], clearEnv: [String]
    ) async throws {
        let envObject = Dictionary(
            uniqueKeysWithValues: env.map { ($0.key, JSONValue.string($0.value)) }
        )
        let body: [String: JSONValue] = [
            "enabled": .bool(enabled),
            "env": .object(envObject),
            "clear_env": .array(clearEnv.map { .string($0) }),
        ]
        // 平台 id 是目录常量，仍按 soulPath 同法转义兜底
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = platform.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? platform
        try await sendJSON(
            config: config,
            path: "/api/messaging/platforms/\(encoded)",
            method: "PUT", endpoint: L10n.string("频道配对"),
            body: body
        )
    }

    // MARK: - 网关动作

    func gatewayRestart(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/gateway/restart", method: "POST",
            endpoint: L10n.string("网关重启"), timeout: 120
        )
    }

    func gatewayStart(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/gateway/start", method: "POST",
            endpoint: L10n.string("网关启动"), timeout: 120
        )
    }

    func gatewayStop(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/gateway/stop", method: "POST",
            endpoint: L10n.string("网关停止"), timeout: 120
        )
    }

    // MARK: - 运维体检（H1-a）

    /// 无 body 的 POST 并解码回执（ops 触发端点专用：
    /// 服务端不收 body，回执是小 JSON）
    private func postDecoding<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String
    ) async throws -> T {
        var request = URLRequest(url: config.endpoint(path))
        request.httpMethod = "POST"
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.fromHTTPResponse(
                endpoint: endpoint,
                status: http.statusCode,
                data: data,
                retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    func opsDoctor(config: ServerConfig) async throws -> OpsSpawnResponse {
        try await postDecoding(
            config: config, path: "/api/ops/doctor",
            endpoint: L10n.string("自检")
        )
    }

    func opsSecurityAudit(
        config: ServerConfig
    ) async throws -> OpsSpawnResponse {
        try await postDecoding(
            config: config, path: "/api/ops/security-audit",
            endpoint: L10n.string("安全审计")
        )
    }

    func opsActionStatus(
        config: ServerConfig, name: String, lines: Int
    ) async throws -> OpsActionStatus {
        // 动作名是服务端常量（doctor/security-audit），
        // 仍按路径段转义兜底（与频道 id 同法）
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? name
        return try await getJSON(
            config: config,
            path: "/api/actions/\(encoded)/status",
            endpoint: L10n.string("体检进度"),
            query: [URLQueryItem(
                name: "lines",
                value: String(min(max(lines, 1), 2000))
            )]
        )
    }

    func opsBackup(
        config: ServerConfig
    ) async throws -> OpsSpawnResponse {
        // 冻结件 BackupRequest 的 body 必填（output 可
        // 空）：发空对象，不用 H1-a 的无 body postDecoding
        try await sendJSONDecoding(
            config: config, path: "/api/ops/backup",
            method: "POST", endpoint: L10n.string("备份"),
            body: [:]
        )
    }

    func opsCheckpoints(
        config: ServerConfig
    ) async throws -> CheckpointsResponse {
        try await getJSON(
            config: config, path: "/api/ops/checkpoints",
            endpoint: L10n.string("检查点")
        )
    }

    // MARK: - 服务端语音（H2-a）

    func voiceConfig(
        config: ServerConfig
    ) async throws -> VoiceConfigResponse {
        try await getJSON(
            config: config, path: "/api/audio/voice-config",
            endpoint: L10n.string("语音配置")
        )
    }

    func elevenLabsVoices(
        config: ServerConfig
    ) async throws -> ElevenLabsVoicesResponse {
        try await getJSON(
            config: config, path: "/api/audio/elevenlabs/voices",
            endpoint: L10n.string("音色列表")
        )
    }

    func speak(
        config: ServerConfig, text: String
    ) async throws -> SpeakResponse {
        // 专用实现（不走 sendJSONDecoding）：失败分型
        // 要读 400 的 detail 原文——provider 未开通与
        // 其他合成失败在文案和可用性精修上完全不同，
        // 裸状态码分不开。长回复的合成耗时远超普通
        // 接口（服务端内部分块合成），超时单独放宽
        // 到 120 秒
        var request = URLRequest(
            url: config.endpoint("/api/audio/speak")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try encoder.encode(["text": text])
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            let kind = SpeakFailureKind.classify(
                status: http.statusCode,
                detail: Self.errorDetail(from: data)
            )
            if kind == .providerUnavailable {
                throw HermesError.speechProviderUnavailable
            }
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("朗读"),
                status: http.statusCode
            )
        }
        do {
            return try decoder.decode(SpeakResponse.self, from: data)
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("朗读")
            )
        }
    }

    /// FastAPI 失败体 {"detail": "…"} 的原文提取：只
    /// 作失败分型输入，取不到返回 nil；原文不许当
    /// 用户文案直显（人话口径在 HermesError/呈现层）
    private static func errorDetail(from data: Data) -> String? {
        struct DetailBody: Decodable { let detail: String? }
        return (try? JSONDecoder().decode(
            DetailBody.self, from: data
        ))?.detail
    }

    /// 网关面失败体 {"error": {"code": …}} 的码提取：
    /// 只作失败分型输入，取不到返回 nil（与 error-
    /// Detail 同口径）
    static func gatewayErrorCode(from data: Data) -> String? {
        struct Body: Decodable {
            struct Inner: Decodable { let code: String? }
            let error: Inner?
        }
        return (try? JSONDecoder().decode(
            Body.self, from: data
        ))?.error?.code
    }

    // MARK: - 设备认领（配对一期，台账 153/160）

    func issueEnrollmentCode(
        config: ServerConfig, apiKey: String
    ) async throws -> EnrollmentIssue {
        var request = URLRequest(
            url: config.endpoint("/v1/enrollment/codes")
        )
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            if Self.gatewayErrorCode(from: data)
                == "enrollment_too_many_pending" {
                throw HermesError.enrollmentTooManyPending
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("认领码"), status: http.statusCode
            )
        }
        do {
            return try decoder.decode(EnrollmentIssue.self, from: data)
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("认领码")
            )
        }
    }

    func claimEnrollment(
        config: ServerConfig, code: String
    ) async throws -> EnrollmentClaim {
        var request = URLRequest(
            url: config.endpoint("/v1/enrollment/claim")
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try encoder.encode(["code": code])
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            switch Self.gatewayErrorCode(from: data) {
            case "enrollment_code_expired":
                throw HermesError.enrollmentCodeExpired
            case "enrollment_locked":
                throw HermesError.enrollmentLocked
            case "enrollment_code_invalid":
                throw HermesError.enrollmentCodeInvalid
            default:
                throw HermesError.unexpectedStatus(
                    endpoint: L10n.string("认领"),
                    status: http.statusCode
                )
            }
        }
        do {
            return try decoder.decode(EnrollmentClaim.self, from: data)
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("认领")
            )
        }
    }

    // MARK: - 推送登记（总表 138，DESIGN §397）

    func registerPushToken(
        config: ServerConfig, apiKey: String,
        body: PushTokenRegistrationBody
    ) async throws -> PushTokenRegisteredResponse {
        var request = URLRequest(
            url: config.endpoint("/v1/push/tokens")
        )
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try encoder.encode(body)
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            if http.statusCode == 404 {
                throw HermesError.pushEndpointNotReady
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("推送登记"),
                status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                PushTokenRegisteredResponse.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("推送登记")
            )
        }
    }

    // MARK: - 短时票据与会话管理（#1 短时票据）

    func exchangeShortLivedToken(
        config: ServerConfig, apiKey: String,
        deviceName: String?, appVersion: String?
    ) async throws -> ShortLivedTokenPair {
        var body: [String: JSONValue] = [:]
        if let deviceName, !deviceName.isEmpty {
            body["device_name"] = .string(deviceName)
        }
        if let appVersion, !appVersion.isEmpty {
            body["app_version"] = .string(appVersion)
        }
        return try await sendJSONDecoding(
            config: config,
            path: "/v1/auth/token",
            method: "POST",
            endpoint: L10n.string("短时票据签发"),
            body: body,
            bearer: apiKey
        )
    }

    func refreshShortLivedToken(
        config: ServerConfig, refreshToken: String
    ) async throws -> ShortLivedTokenPair {
        try await sendJSONDecoding(
            config: config,
            path: "/v1/auth/refresh",
            method: "POST",
            endpoint: L10n.string("短时票据刷新"),
            body: ["refresh_token": .string(refreshToken)],
            bearer: nil
        )
    }

    func listAuthSessions(
        config: ServerConfig, apiKey: String
    ) async throws -> [AuthSessionSummary] {
        let response: AuthSessionsListResponse = try await bearerGetJSON(
            config: config,
            apiKey: apiKey,
            path: "/v1/auth/sessions",
            endpoint: L10n.string("登录会话列表")
        )
        return response.data
    }

    func revokeAuthSession(
        config: ServerConfig, apiKey: String, sessionID: String
    ) async throws -> AuthRevokeReceipt {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: allowed) ?? sessionID
        var request = URLRequest(url: config.endpoint("/v1/auth/sessions/\(encoded)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            throw HermesError.fromHTTPResponse(
                endpoint: L10n.string("撤销登录会话"),
                status: http.statusCode,
                data: data,
                retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
        do {
            return try decoder.decode(AuthRevokeReceipt.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: L10n.string("撤销登录会话"))
        }
    }

    // MARK: - 命令授权（批 5，DESIGN §355）

    func listGrants(
        config: ServerConfig, apiKey: String
    ) async throws -> GrantsListResponse {
        var request = URLRequest(url: config.endpoint("/v1/grants"))
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            // 503 grant_projection_unavailable 连码上行：
            // 呈现层据码给「投影不可用」专属人话，不与
            // 一般失败混同
            if let code = Self.gatewayErrorCode(from: data) {
                throw HermesError.serverError(
                    endpoint: L10n.string("授权清单"),
                    status: http.statusCode, code: code
                )
            }
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("授权清单"),
                status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                GrantsListResponse.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("授权清单")
            )
        }
    }

    func revokeGrant(
        config: ServerConfig, apiKey: String, patternKey: String
    ) async throws -> GrantRevocationReceipt {
        var request = URLRequest(
            url: config.endpoint("/v1/grants/revoke")
        )
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        // 请求体组装走 Core 纯函数（单测把守形态）
        request.httpBody = try encoder.encode(
            GrantRevokeRequest.exec(patternKey: patternKey)
        )
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            if let code = Self.gatewayErrorCode(from: data) {
                throw HermesError.serverError(
                    endpoint: L10n.string("撤销授权"),
                    status: http.statusCode, code: code
                )
            }
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("撤销授权"),
                status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                GrantRevocationReceipt.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("撤销授权")
            )
        }
    }

    // MARK: - 平台用户配对（H5，DESIGN §359）

    func pairingList(
        config: ServerConfig
    ) async throws -> PairingListResponse {
        try await getJSON(
            config: config, path: "/api/pairing",
            endpoint: L10n.string("平台用户配对")
        )
    }

    func pairingApprove(
        config: ServerConfig, platform: String, requestID: String
    ) async throws -> PairingApproveReceipt {
        var request = URLRequest(
            url: config.endpoint("/api/pairing/approve")
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        // 请求体组装走 Core 纯函数（单测把守形态）
        request.httpBody = try encoder.encode(
            PairingApproveRequest(
                platform: platform, requestID: requestID
            )
        )
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            // 状态码原样上行（404 过期/429 锁定/401 会
            // 话失效的呈现分型在 PairingActionDirective）
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("批准配对"),
                status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                PairingApproveReceipt.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("批准配对")
            )
        }
    }

    func pairingRevoke(
        config: ServerConfig, platform: String, userID: String
    ) async throws {
        var request = URLRequest(
            url: config.endpoint("/api/pairing/revoke")
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try encoder.encode(
            PairingRevokeRequest(platform: platform, userID: userID)
        )
        let (_, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("撤销配对"),
                status: http.statusCode
            )
        }
    }

    func pairingClearPending(
        config: ServerConfig
    ) async throws -> PairingClearPendingReceipt {
        var request = URLRequest(
            url: config.endpoint("/api/pairing/clear-pending")
        )
        request.httpMethod = "POST"
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("清空待批配对"),
                status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                PairingClearPendingReceipt.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("清空待批配对")
            )
        }
    }

    // MARK: - 工具集治理（台账 34，DESIGN §358）

    func toolsets(
        config: ServerConfig, apiKey: String
    ) async throws -> ToolsetsListResponse {
        try await getJSON(
            config: config, path: "/v1/toolsets",
            endpoint: L10n.string("工具集接口"), bearer: apiKey
        )
    }

    func setToolsetEnabled(
        config: ServerConfig, apiKey: String,
        name: String, enabled: Bool
    ) async throws -> ToolsetToggleReceipt {
        var request = URLRequest(
            url: config.endpoint("/v1/toolsets/\(name)")
        )
        request.httpMethod = "PUT"
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        // 请求体组装走 Core 纯函数（单测把守形态）
        request.httpBody = try encoder.encode(
            ToolsetToggleRequest.set(enabled)
        )
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            // 400 unknown_toolset / invalid_enabled 连码
            // 上行：呈现层据码分型（ToolsetToggleDirective）
            if let code = Self.gatewayErrorCode(from: data) {
                throw HermesError.serverError(
                    endpoint: L10n.string("工具集开关"),
                    status: http.statusCode, code: code
                )
            }
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("工具集开关"),
                status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                ToolsetToggleReceipt.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("工具集开关")
            )
        }
    }

    func toolsetConfig(
        config: ServerConfig, name: String
    ) async throws -> ToolsetConfigPanel {
        try await getJSON(
            config: config,
            path: "/api/tools/toolsets/\(name)/config",
            endpoint: L10n.string("工具集配置")
        )
    }

    func selectToolsetProvider(
        config: ServerConfig, name: String, provider: String
    ) async throws {
        try await sendJSON(
            config: config,
            path: "/api/tools/toolsets/\(name)/provider",
            method: "PUT",
            endpoint: L10n.string("工具集服务商"),
            body: ["provider": .string(provider)]
        )
    }

    func toolsetModels(
        config: ServerConfig, name: String
    ) async throws -> ToolsetModelCatalog {
        try await getJSON(
            config: config,
            path: "/api/tools/toolsets/\(name)/models",
            endpoint: L10n.string("工具集模型")
        )
    }

    func selectToolsetModel(
        config: ServerConfig, name: String, model: String
    ) async throws {
        try await sendJSON(
            config: config,
            path: "/api/tools/toolsets/\(name)/model",
            method: "PUT",
            endpoint: L10n.string("工具集模型"),
            body: ["model": .string(model)]
        )
    }

    func terminalBackends(
        config: ServerConfig
    ) async throws -> TerminalBackends {
        try await getJSON(
            config: config, path: "/api/tools/terminal/backends",
            endpoint: L10n.string("终端后端")
        )
    }

    func selectTerminalBackend(
        config: ServerConfig, backend: String
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/tools/terminal/backend",
            method: "PUT",
            endpoint: L10n.string("终端后端"),
            body: ["backend": .string(backend)]
        )
    }

    // MARK: - 高级能力面（H8/H9/H11/H13，DESIGN §390）

    func delegationRouting(
        config: ServerConfig
    ) async throws -> DelegationRouting {
        try await getJSON(
            config: config, path: "/api/delegation/routing",
            endpoint: L10n.string("委派路由")
        )
    }

    func setDelegationBackend(
        config: ServerConfig, backend: String
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/delegation/backend",
            method: "PUT", endpoint: L10n.string("委派后端"),
            body: ["backend": .string(backend)]
        )
    }

    func setDelegationModelMap(
        config: ServerConfig, routes: [DelegationModelRoute],
        defaultRoute: String?
    ) async throws {
        var body: [String: JSONValue] = [
            "options": .array(routes.map { .object($0.putFields()) }),
        ]
        if let defaultRoute { body["default"] = .string(defaultRoute) }
        try await sendJSON(
            config: config, path: "/api/delegation/backends/model_map",
            method: "PUT", endpoint: L10n.string("委派模型路由"),
            body: body
        )
    }

    func setDelegationProfileRoutes(
        config: ServerConfig, routes: [DelegationProfileRoute],
        defaultRoute: String?
    ) async throws {
        var body: [String: JSONValue] = [
            "profiles": .array(routes.map { .object($0.putFields()) }),
        ]
        if let defaultRoute { body["default"] = .string(defaultRoute) }
        try await sendJSON(
            config: config, path: "/api/delegation/backends/profile_routes",
            method: "PUT", endpoint: L10n.string("委派档案路由"),
            body: body
        )
    }

    func moaConfig(config: ServerConfig) async throws -> MoaConfig {
        try await getJSON(
            config: config, path: "/api/model/moa",
            endpoint: L10n.string("多模型会商")
        )
    }

    func setMoaConfig(
        config: ServerConfig, moa: MoaConfig
    ) async throws -> MoaConfig {
        try await sendJSONDecoding(
            config: config, path: "/api/model/moa",
            method: "PUT", endpoint: L10n.string("多模型会商"),
            body: moa.putBody()
        )
    }

    func auxiliaryTasks(
        config: ServerConfig
    ) async throws -> AuxiliaryTasksResponse {
        try await getJSON(
            config: config, path: "/api/model/auxiliary",
            endpoint: L10n.string("辅助模型")
        )
    }

    func setModelAssignment(
        config: ServerConfig, scope: String, task: String?,
        provider: String, model: String, confirmExpensive: Bool
    ) async throws -> ModelSetReceipt {
        var body: [String: JSONValue] = [
            "scope": .string(scope),
            "provider": .string(provider),
            "model": .string(model),
            "confirm_expensive_model": .bool(confirmExpensive),
        ]
        if let task { body["task"] = .string(task) }
        return try await sendJSONDecoding(
            config: config, path: "/api/model/set",
            method: "POST", endpoint: L10n.string("模型分配"),
            body: body
        )
    }

    func webhooksPage(config: ServerConfig) async throws -> WebhooksPage {
        try await getJSON(
            config: config, path: "/api/webhooks",
            endpoint: L10n.string("外部事件")
        )
    }

    func createWebhook(
        config: ServerConfig, input: WebhookCreateInput
    ) async throws -> WebhookCreateReceipt {
        try await sendJSONDecoding(
            config: config, path: "/api/webhooks",
            method: "POST", endpoint: L10n.string("新建外部事件"),
            body: input.putBody()
        )
    }

    func deleteWebhook(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: "/api/webhooks/\(name)",
            method: "DELETE", endpoint: L10n.string("删除外部事件")
        )
    }

    func setWebhookEnabled(
        config: ServerConfig, name: String, enabled: Bool
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/webhooks/\(name)/enabled",
            method: "PUT", endpoint: L10n.string("外部事件启停"),
            body: ["enabled": .bool(enabled)]
        )
    }

    func enableWebhooks(
        config: ServerConfig
    ) async throws -> WebhooksEnableReceipt {
        try await sendJSONDecoding(
            config: config, path: "/api/webhooks/enable",
            method: "POST", endpoint: L10n.string("开启外部事件"),
            body: [:]
        )
    }

    func curatorStatus(config: ServerConfig) async throws -> CuratorStatus {
        try await getJSON(
            config: config, path: "/api/curator",
            endpoint: L10n.string("技能整理")
        )
    }

    func setCuratorPaused(config: ServerConfig, paused: Bool) async throws {
        try await sendJSON(
            config: config, path: "/api/curator/paused",
            method: "PUT", endpoint: L10n.string("技能整理暂停"),
            body: ["paused": .bool(paused)]
        )
    }

    func runCurator(
        config: ServerConfig, profile: String?
    ) async throws -> OpsSpawnResponse {
        var query: [URLQueryItem] = []
        if let profile, !profile.isEmpty {
            query.append(URLQueryItem(name: "profile", value: profile))
        }
        // sendJSON 无解码口，curator/run 回执 {ok,pid,name}
        // 与 ops 两段式同形：手拼一次（与 pairingApprove 同式）
        var request = URLRequest(
            url: url(
                config: config, path: "/api/curator/run", query: query
            )
        )
        request.httpMethod = "POST"
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("立即整理技能"), status: http.statusCode
            )
        }
        do {
            return try decoder.decode(OpsSpawnResponse.self, from: data)
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("立即整理技能")
            )
        }
    }

    func sessionStoreStats(
        config: ServerConfig
    ) async throws -> SessionStoreStats {
        try await getJSON(
            config: config, path: "/api/sessions/stats",
            endpoint: L10n.string("会话统计")
        )
    }

    func opsHooks(config: ServerConfig) async throws -> OpsHooksPage {
        try await getJSON(
            config: config, path: "/api/ops/hooks",
            endpoint: L10n.string("钩子")
        )
    }

}
