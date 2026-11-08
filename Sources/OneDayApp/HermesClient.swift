import Foundation
import OneDayCore

/// Hermes 服务端对接协议：连接页三步探活、总览与聊天走对话面，
/// 智能体/设置的总览外全部功能走 Dashboard 管理面（/api/*，
/// 会话 cookie 鉴权，401 由 AppState 自动重登兜底）。
/// 接口路径与请求体口径全部对 docs/hermes-0.23.0-openapi.json
/// 与 2026-11-08 GET 实测结构（见 docs/API-SURFACE.md）。
protocol HermesClientProtocol: Sendable {
    /// 探活一：GET /health（免鉴权）
    func health(config: ServerConfig) async throws -> HealthResponse
    /// 探活二：POST /auth/password-login 拿会话 cookie
    /// （cookie 由 URLSession 共享存储持有，本方法只判成败）
    func login(config: ServerConfig, username: String, password: String) async throws
    /// GET /api/status（免登录）
    func status(config: ServerConfig) async throws -> ServerStatus
    /// GET /api/config（需会话；401 由调用方走重登重试）
    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary
    /// 探活三：GET /v1/models（Bearer API 密钥），返回模型 id 列表
    func models(config: ServerConfig, apiKey: String) async throws -> [String]
    /// POST /v1/chat/completions 流式：逐段产出文本增量
    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error>
    /// 清除某服务器的全部会话 cookie（断开连接时调用）
    func clearCookies(config: ServerConfig)

    // MARK: 管理面（里程碑 2，IA v3）

    /// GET /api/memory
    func memoryStatus(config: ServerConfig) async throws -> MemoryStatus
    /// PUT /api/memory/provider {provider}
    func setMemoryProvider(config: ServerConfig, name: String) async throws
    /// GET /api/memory/providers/{name}/config
    func memoryProviderConfig(config: ServerConfig, name: String) async throws -> MemoryProviderConfig
    /// PUT /api/memory/providers/{name}/config {values}
    func updateMemoryProviderConfig(
        config: ServerConfig, name: String, values: [String: JSONValue]
    ) async throws
    /// POST /api/memory/reset {target}
    func resetMemory(config: ServerConfig, target: String) async throws

    /// GET /api/skills（裸数组）
    func skills(config: ServerConfig) async throws -> [SkillItem]
    /// GET /api/skills/content?name=
    func skillContent(config: ServerConfig, name: String) async throws -> SkillContent
    /// PUT /api/skills/content {name, content}
    func updateSkillContent(config: ServerConfig, name: String, content: String) async throws
    /// PUT /api/skills/toggle {name, enabled}
    func toggleSkill(config: ServerConfig, name: String, enabled: Bool) async throws
    /// PUT /api/skills/lock {name, locked}
    func lockSkill(config: ServerConfig, name: String, locked: Bool) async throws

    /// GET /api/cron/jobs（裸数组）
    func cronJobs(config: ServerConfig) async throws -> [CronJob]
    /// POST /api/cron/jobs（schedule 传字符串表达式）
    func createCronJob(
        config: ServerConfig, name: String?, prompt: String, schedule: String, deliver: String?
    ) async throws -> CronJob
    /// PUT /api/cron/jobs/{id} {updates}
    func updateCronJob(config: ServerConfig, id: String, updates: [String: JSONValue]) async throws
    /// DELETE /api/cron/jobs/{id}
    func deleteCronJob(config: ServerConfig, id: String) async throws
    /// POST /api/cron/jobs/{id}/pause
    func pauseCronJob(config: ServerConfig, id: String) async throws
    /// POST /api/cron/jobs/{id}/resume
    func resumeCronJob(config: ServerConfig, id: String) async throws
    /// POST /api/cron/jobs/{id}/trigger（服务端同步等任务跑完，
    /// 官方桌面端为此单独放宽到 24h；App 侧放宽到 10 分钟）
    func triggerCronJob(config: ServerConfig, id: String) async throws
    /// GET /api/cron/jobs/{id}/runs?limit=（{"runs": [会话同构行]}）
    func cronRuns(config: ServerConfig, id: String, limit: Int) async throws -> [ServerSession]

    /// GET /api/sessions?limit=
    func serverSessions(config: ServerConfig, limit: Int) async throws -> SessionsPage
    /// GET /api/sessions/{id}
    func serverSession(config: ServerConfig, id: String) async throws -> ServerSession
    /// GET /api/sessions/{id}/messages
    func sessionMessages(config: ServerConfig, id: String) async throws -> [SessionMessage]
    /// DELETE /api/sessions/{id}
    func deleteServerSession(config: ServerConfig, id: String) async throws
    /// POST /api/sessions/bulk-delete {ids}
    func bulkDeleteServerSessions(config: ServerConfig, ids: [String]) async throws
    /// GET /api/sessions/empty/count
    func emptySessionCount(config: ServerConfig) async throws -> Int
    /// DELETE /api/sessions/empty
    func deleteEmptySessions(config: ServerConfig) async throws

    /// GET /api/profiles
    func profiles(config: ServerConfig) async throws -> [ProfileItem]
    /// GET /api/profiles/active
    func activeProfileName(config: ServerConfig) async throws -> String?
    /// POST /api/profiles/active {name}
    func setActiveProfile(config: ServerConfig, name: String) async throws

    /// GET /api/config 全量（动态 JSON，原样保留未知字段）
    func rawConfig(config: ServerConfig) async throws -> [String: JSONValue]
    /// PUT /api/config {config}（全量写回，调用方负责先读后改）
    func updateConfig(config: ServerConfig, newConfig: [String: JSONValue]) async throws

    /// GET /api/env（顶层字典，解码层已排序）
    func envVars(config: ServerConfig) async throws -> [EnvVarEntry]
    /// PUT /api/env {key, value}
    func setEnvVar(config: ServerConfig, key: String, value: String) async throws
    /// DELETE /api/env {key}（带 body 的 DELETE）
    func deleteEnvVar(config: ServerConfig, key: String) async throws
    /// POST /api/env/reveal {key} → 明文（响应形态宽容提取）
    func revealEnvVar(config: ServerConfig, key: String) async throws -> String

    /// GET /api/analytics/usage?days=
    func usageAnalytics(config: ServerConfig, days: Int) async throws -> UsageAnalytics
    /// GET /api/analytics/models?days=
    func modelAnalytics(config: ServerConfig, days: Int) async throws -> ModelAnalytics
    /// GET /api/model/options：上游提供商＋精选模型列表（官方
    /// ModelPickerDialog 同源端点）；回执未定型，经
    /// ModelCatalog.extractModelIDs 宽容提取为 id 列表
    func modelOptions(config: ServerConfig) async throws -> [String]
    /// GET /api/logs?level=&search=&lines=
    func logs(
        config: ServerConfig, level: String?, search: String?, lines: Int
    ) async throws -> LogsResponse
    /// GET /api/egress/status
    func egressStatus(config: ServerConfig) async throws -> EgressStatus

    /// POST /api/gateway/restart
    func gatewayRestart(config: ServerConfig) async throws
    /// POST /api/gateway/start
    func gatewayStart(config: ServerConfig) async throws
    /// POST /api/gateway/stop
    func gatewayStop(config: ServerConfig) async throws

    // MARK: 工作区文件与系统（0.2.1）

    /// GET /api/files?path=（path 为 nil 时服务端回默认根，
    /// 2026-11-08 实查根被 locked_root 锁在 /opt/data）
    func files(config: ServerConfig, path: String?) async throws -> FilesListing
    /// DELETE /api/files {path, recursive}
    func deleteFile(config: ServerConfig, path: String, recursive: Bool) async throws
    /// GET /api/files/download?path= → 原始字节（预览/下载共用）
    func fileData(config: ServerConfig, path: String) async throws -> Data
    /// GET /api/system/stats
    func systemStats(config: ServerConfig) async throws -> SystemStats
}

/// URLSession 实现。会话 cookie 走 .shared 存储：登录一次，
/// 后续 /api/* 自动带上；进程重启后 cookie 仍在（系统持久化），
/// 过期则由 AppState 的自动重登兜底。
final class HermesClient: HermesClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    // MARK: - 基础请求

    /// 网络层错误统一映射：URLError → HermesError.unreachable（人话简述）
    private func mapNetworkError(_ error: Error) -> HermesError {
        if let hermesError = error as? HermesError {
            return hermesError
        }
        guard let urlError = error as? URLError else {
            return .unreachable("网络错误")
        }
        switch urlError.code {
        case .timedOut:
            return .unreachable("请求超时")
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .unreachable("无法建立连接")
        case .notConnectedToInternet, .networkConnectionLost:
            return .unreachable("网络不可用")
        default:
            return .unreachable("网络错误")
        }
    }

    private func dataRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HermesError.unreachable("无响应")
            }
            return (data, http)
        } catch let error as HermesError {
            throw error
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// 拼 query 的 URL：path 里已带路径参数时用 URLComponents 挂参
    private func url(
        config: ServerConfig, path: String, query: [URLQueryItem] = []
    ) -> URL {
        let base = config.endpoint(path)
        guard !query.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        components.queryItems = query
        return components.url ?? base
    }

    private func getJSON<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        query: [URLQueryItem] = [], bearer: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: url(config: config, path: path, query: query))
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            throw HermesError.unexpectedStatus(endpoint: endpoint, status: http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    /// 带 JSON body 的写请求：2xx 即成功，不解码响应体
    /// （各写接口的回执形态不一，调用方需要新状态时自行重拉）。
    private func sendJSON(
        config: ServerConfig, path: String, method: String, endpoint: String,
        body: [String: JSONValue]? = nil, timeout: TimeInterval? = nil
    ) async throws {
        var request = URLRequest(url: config.endpoint(path))
        request.httpMethod = method
        if let timeout {
            request.timeoutInterval = timeout
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let (_, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(endpoint: endpoint, status: http.statusCode)
        }
    }

    /// 写请求并解码回执（创建类接口返回新建对象时使用）
    private func sendJSONDecoding<T: Decodable>(
        config: ServerConfig, path: String, method: String, endpoint: String,
        body: [String: JSONValue]
    ) async throws -> T {
        var request = URLRequest(url: config.endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(endpoint: endpoint, status: http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    // MARK: - 探活与接口

    func health(config: ServerConfig) async throws -> HealthResponse {
        var request = URLRequest(url: config.endpoint("/health"))
        request.timeoutInterval = 15
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            throw HermesError.healthCheckFailed(status: http.statusCode)
        }
        do {
            return try decoder.decode(HealthResponse.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: "健康检查")
        }
    }

    func login(config: ServerConfig, username: String, password: String) async throws {
        var request = URLRequest(url: config.endpoint("/auth/password-login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 登录契约（2026-11-08 实测）：JSON 四字段，缺 provider 返回 422
        let body: [String: String] = [
            "provider": "basic",
            "username": username,
            "password": password,
            "next": "/",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403, 422:
            throw HermesError.loginRejected
        default:
            throw HermesError.loginFailed(status: http.statusCode)
        }
    }

    func status(config: ServerConfig) async throws -> ServerStatus {
        try await getJSON(config: config, path: "/api/status", endpoint: "状态接口")
    }

    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary {
        try await getJSON(config: config, path: "/api/config", endpoint: "配置接口")
    }

    func models(config: ServerConfig, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: config.endpoint("/v1/models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(endpoint: "模型接口", status: http.statusCode)
        }
        do {
            return try decoder.decode(ModelsResponse.self, from: data).ids
        } catch {
            throw HermesError.decodingFailed(endpoint: "模型接口")
        }
    }

    // MARK: - 流式聊天

    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: config.endpoint("/v1/chat/completions"))
                    request.httpMethod = "POST"
                    // 长回复逐字到达：单请求超时放宽到 10 分钟，
                    // 停止生成走 task.cancel()（onTermination 承接）
                    request.timeoutInterval = 600
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let payload: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw HermesError.unreachable("无响应")
                    }
                    guard http.statusCode == 200 else {
                        if http.statusCode == 401 || http.statusCode == 403 {
                            throw HermesError.apiKeyRejected
                        }
                        throw HermesError.unexpectedStatus(
                            endpoint: "聊天接口", status: http.statusCode
                        )
                    }
                    let parser = SSEParser()
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            throw HermesError.cancelled
                        }
                        switch parser.consume(line: line) {
                        case .delta(let text):
                            continuation.yield(text)
                        case .done:
                            continuation.finish()
                            return
                        case nil:
                            continue
                        }
                    }
                    // 服务端未发 [DONE] 就收尾：已产出内容照常成篇
                    continuation.finish()
                } catch let error as HermesError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish(throwing: HermesError.cancelled)
                } catch {
                    continuation.finish(throwing: mapNetworkError(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Cookie

    func clearCookies(config: ServerConfig) {
        guard let storage = session.configuration.httpCookieStorage,
              let host = config.endpoint("/").host else {
            return
        }
        let cookies = storage.cookies ?? []
        for cookie in cookies where cookie.domain.contains(host) || host.contains(cookie.domain) {
            storage.deleteCookie(cookie)
        }
    }

    // MARK: - 记忆

    func memoryStatus(config: ServerConfig) async throws -> MemoryStatus {
        try await getJSON(config: config, path: "/api/memory", endpoint: "记忆接口")
    }

    func setMemoryProvider(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: "/api/memory/provider", method: "PUT",
            endpoint: "记忆提供方切换", body: ["provider": .string(name)]
        )
    }

    func memoryProviderConfig(
        config: ServerConfig, name: String
    ) async throws -> MemoryProviderConfig {
        try await getJSON(
            config: config,
            path: "/api/memory/providers/\(name)/config",
            endpoint: "记忆提供方配置"
        )
    }

    func updateMemoryProviderConfig(
        config: ServerConfig, name: String, values: [String: JSONValue]
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/memory/providers/\(name)/config",
            method: "PUT", endpoint: "记忆提供方配置",
            body: ["values": .object(values)]
        )
    }

    func resetMemory(config: ServerConfig, target: String) async throws {
        try await sendJSON(
            config: config, path: "/api/memory/reset", method: "POST",
            endpoint: "记忆重置", body: ["target": .string(target)]
        )
    }

    // MARK: - 技能

    func skills(config: ServerConfig) async throws -> [SkillItem] {
        try await getJSON(config: config, path: "/api/skills", endpoint: "技能接口")
    }

    func skillContent(config: ServerConfig, name: String) async throws -> SkillContent {
        try await getJSON(
            config: config, path: "/api/skills/content", endpoint: "技能内容",
            query: [URLQueryItem(name: "name", value: name)]
        )
    }

    func updateSkillContent(config: ServerConfig, name: String, content: String) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/content", method: "PUT",
            endpoint: "技能内容",
            body: ["name": .string(name), "content": .string(content)]
        )
    }

    func toggleSkill(config: ServerConfig, name: String, enabled: Bool) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/toggle", method: "PUT",
            endpoint: "技能开关",
            body: ["name": .string(name), "enabled": .bool(enabled)]
        )
    }

    func lockSkill(config: ServerConfig, name: String, locked: Bool) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/lock", method: "PUT",
            endpoint: "技能锁定",
            body: ["name": .string(name), "locked": .bool(locked)]
        )
    }

    // MARK: - 定时任务

    func cronJobs(config: ServerConfig) async throws -> [CronJob] {
        try await getJSON(config: config, path: "/api/cron/jobs", endpoint: "定时任务接口")
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
            endpoint: "定时任务创建", body: body
        )
    }

    func updateCronJob(
        config: ServerConfig, id: String, updates: [String: JSONValue]
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)", method: "PUT",
            endpoint: "定时任务更新", body: ["updates": .object(updates)]
        )
    }

    func deleteCronJob(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)", method: "DELETE",
            endpoint: "定时任务删除"
        )
    }

    func pauseCronJob(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)/pause", method: "POST",
            endpoint: "定时任务暂停"
        )
    }

    func resumeCronJob(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)/resume", method: "POST",
            endpoint: "定时任务恢复"
        )
    }

    func triggerCronJob(config: ServerConfig, id: String) async throws {
        // 触发是同步执行：服务端等任务跑完才回执，放宽超时
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)/trigger", method: "POST",
            endpoint: "定时任务触发", timeout: 600
        )
    }

    func cronRuns(config: ServerConfig, id: String, limit: Int) async throws -> [ServerSession] {
        let response: CronRunsResponse = try await getJSON(
            config: config, path: "/api/cron/jobs/\(id)/runs",
            endpoint: "定时任务运行记录",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return response.runs
    }

    // MARK: - 服务端会话

    func serverSessions(config: ServerConfig, limit: Int) async throws -> SessionsPage {
        try await getJSON(
            config: config, path: "/api/sessions", endpoint: "服务端会话",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    func serverSession(config: ServerConfig, id: String) async throws -> ServerSession {
        try await getJSON(
            config: config, path: "/api/sessions/\(id)", endpoint: "服务端会话详情"
        )
    }

    func sessionMessages(config: ServerConfig, id: String) async throws -> [SessionMessage] {
        let response: SessionMessagesResponse = try await getJSON(
            config: config, path: "/api/sessions/\(id)/messages",
            endpoint: "服务端会话消息"
        )
        return response.messages
    }

    func deleteServerSession(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/sessions/\(id)", method: "DELETE",
            endpoint: "服务端会话删除"
        )
    }

    func bulkDeleteServerSessions(config: ServerConfig, ids: [String]) async throws {
        try await sendJSON(
            config: config, path: "/api/sessions/bulk-delete", method: "POST",
            endpoint: "服务端会话批量删除",
            body: ["ids": .array(ids.map(JSONValue.string))]
        )
    }

    func emptySessionCount(config: ServerConfig) async throws -> Int {
        struct CountResponse: Decodable { let count: Int? }
        let response: CountResponse = try await getJSON(
            config: config, path: "/api/sessions/empty/count",
            endpoint: "空会话计数"
        )
        return response.count ?? 0
    }

    func deleteEmptySessions(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/sessions/empty", method: "DELETE",
            endpoint: "空会话清理"
        )
    }

    // MARK: - 档案

    func profiles(config: ServerConfig) async throws -> [ProfileItem] {
        let response: ProfilesResponse = try await getJSON(
            config: config, path: "/api/profiles", endpoint: "档案接口"
        )
        return response.profiles
    }

    func activeProfileName(config: ServerConfig) async throws -> String? {
        let response: ActiveProfileResponse = try await getJSON(
            config: config, path: "/api/profiles/active", endpoint: "当前档案"
        )
        return response.name
    }

    func setActiveProfile(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: "/api/profiles/active", method: "POST",
            endpoint: "档案切换", body: ["name": .string(name)]
        )
    }

    // MARK: - 配置与密钥

    func rawConfig(config: ServerConfig) async throws -> [String: JSONValue] {
        try await getJSON(config: config, path: "/api/config", endpoint: "配置接口")
    }

    func updateConfig(config: ServerConfig, newConfig: [String: JSONValue]) async throws {
        try await sendJSON(
            config: config, path: "/api/config", method: "PUT",
            endpoint: "配置写入", body: ["config": .object(newConfig)]
        )
    }

    func envVars(config: ServerConfig) async throws -> [EnvVarEntry] {
        let response: EnvVars = try await getJSON(
            config: config, path: "/api/env", endpoint: "密钥接口"
        )
        return response.entries
    }

    func setEnvVar(config: ServerConfig, key: String, value: String) async throws {
        try await sendJSON(
            config: config, path: "/api/env", method: "PUT",
            endpoint: "密钥写入",
            body: ["key": .string(key), "value": .string(value)]
        )
    }

    func deleteEnvVar(config: ServerConfig, key: String) async throws {
        try await sendJSON(
            config: config, path: "/api/env", method: "DELETE",
            endpoint: "密钥删除", body: ["key": .string(key)]
        )
    }

    func revealEnvVar(config: ServerConfig, key: String) async throws -> String {
        var request = URLRequest(url: config.endpoint("/api/env/reveal"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["key": JSONValue.string(key)])
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(endpoint: "密钥查看", status: http.statusCode)
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
            throw HermesError.decodingFailed(endpoint: "密钥查看")
        default:
            throw HermesError.decodingFailed(endpoint: "密钥查看")
        }
    }

    // MARK: - 用量与日志

    func usageAnalytics(config: ServerConfig, days: Int) async throws -> UsageAnalytics {
        try await getJSON(
            config: config, path: "/api/analytics/usage", endpoint: "用量接口",
            query: [URLQueryItem(name: "days", value: String(days))]
        )
    }

    func modelAnalytics(config: ServerConfig, days: Int) async throws -> ModelAnalytics {
        try await getJSON(
            config: config, path: "/api/analytics/models", endpoint: "模型用量接口",
            query: [URLQueryItem(name: "days", value: String(days))]
        )
    }

    func modelOptions(config: ServerConfig) async throws -> [String] {
        // 回执在 OpenAPI 里未定型：先以 JSONValue 整树接住，
        // 再由 ModelCatalog 宽容提取（形状容忍优先于强解码）
        let root: JSONValue = try await getJSON(
            config: config, path: "/api/model/options", endpoint: "模型列表接口"
        )
        return ModelCatalog.extractModelIDs(from: root)
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
            config: config, path: "/api/logs", endpoint: "日志接口", query: query
        )
    }

    func egressStatus(config: ServerConfig) async throws -> EgressStatus {
        try await getJSON(config: config, path: "/api/egress/status", endpoint: "出口状态")
    }

    // MARK: - 网关动作

    func gatewayRestart(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/gateway/restart", method: "POST",
            endpoint: "网关重启", timeout: 120
        )
    }

    func gatewayStart(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/gateway/start", method: "POST",
            endpoint: "网关启动", timeout: 120
        )
    }

    func gatewayStop(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/gateway/stop", method: "POST",
            endpoint: "网关停止", timeout: 120
        )
    }

    // MARK: - 工作区文件与系统（0.2.1）

    func files(config: ServerConfig, path: String?) async throws -> FilesListing {
        var query: [URLQueryItem] = []
        if let path, !path.isEmpty {
            query.append(URLQueryItem(name: "path", value: path))
        }
        return try await getJSON(
            config: config, path: "/api/files", endpoint: "文件列表", query: query
        )
    }

    func deleteFile(config: ServerConfig, path: String, recursive: Bool) async throws {
        try await sendJSON(
            config: config, path: "/api/files", method: "DELETE",
            endpoint: "删除文件",
            body: ["path": .string(path), "recursive": .bool(recursive)]
        )
    }

    func fileData(config: ServerConfig, path: String) async throws -> Data {
        let request = URLRequest(
            url: url(
                config: config, path: "/api/files/download",
                query: [URLQueryItem(name: "path", value: path)]
            )
        )
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            throw HermesError.unexpectedStatus(endpoint: "文件下载", status: http.statusCode)
        }
        return data
    }

    func systemStats(config: ServerConfig) async throws -> SystemStats {
        try await getJSON(config: config, path: "/api/system/stats", endpoint: "系统状态")
    }
}
