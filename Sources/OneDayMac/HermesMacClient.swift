import Foundation
import OneDayCore

/// Mac 端网关客户端（地基棒）：只实现登录链与壳层状态
/// 面要用的端点，全部与 iOS 端 HermesClient 同路径、
/// 同状态码口径——GET /health → POST /api/companion/
/// web-login（面板密码一步制，§244 一把密码统一）→
/// POST /api/env/reveal 换 API_SERVER_KEY → GET
/// /v1/models 验钥，另加 /v1/capabilities 与 /api/status
/// 供壳层消费。后续棒按对位表逐面扩端点，不另起第二
/// 套客户端。cookie 落 URLSession 共享存储（web-login
/// 换来的 dashboard 会话 cookie 由 reveal 一步带上，
/// 与 iOS 同机制）。
struct HermesMacClient: Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 传输底座

    private func dataRequest(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HermesError.unexpectedStatus(
                    endpoint: "网络响应", status: -1
                )
            }
            return (data, http)
        } catch let error as URLError {
            throw HermesError.fromURLError(error)
        }
    }

    private func bearerGet<T: Decodable>(
        config: ServerConfig, apiKey: String, path: String,
        endpoint: String
    ) async throws -> T {
        var request = URLRequest(url: config.endpoint(path))
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: endpoint, status: http.statusCode
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    // MARK: - 登录链（与 iOS connectWithPassword 同序）

    /// 探活一：GET /health（免鉴权）
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

    /// 探活二：POST /api/companion/web-login 验面板密码
    /// （桥在服务器内部换 dashboard 会话 cookie 原样透
    /// 传，部署密码永不出服务器）
    func login(config: ServerConfig, password: String) async throws {
        var request = URLRequest(
            url: config.endpoint("/api/companion/web-login")
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["password": password]
        )
        let (_, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw HermesError.loginRejected
        case 429:
            throw HermesError.loginRateLimited
        default:
            throw HermesError.loginFailed(status: http.statusCode)
        }
    }

    /// 换钥：POST /api/env/reveal {key} → 明文（响应形
    /// 态宽容提取，与 iOS revealEnvVar 同口径）
    func revealEnvVar(config: ServerConfig, key: String) async throws -> String {
        var request = URLRequest(url: config.endpoint("/api/env/reveal"))
        request.httpMethod = "POST"
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["key": key]
        )
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: "密钥查看", status: http.statusCode
            )
        }
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

    /// 探活三：GET /v1/models（Bearer 登录密钥）→ 模型 id 列表
    func models(
        config: ServerConfig, apiKey: String
    ) async throws -> [String] {
        let response: ModelsResponse = try await bearerGet(
            config: config, apiKey: apiKey, path: "/v1/models",
            endpoint: "模型接口"
        )
        return response.ids
    }

    /// 能力发现：GET /v1/capabilities（Bearer）
    func capabilities(
        config: ServerConfig, apiKey: String
    ) async throws -> CapabilitiesResponse {
        try await bearerGet(
            config: config, apiKey: apiKey, path: "/v1/capabilities",
            endpoint: "能力接口"
        )
    }

    /// 服务状态：GET /api/status（免登录）
    func status(config: ServerConfig) async throws -> ServerStatus {
        let request = URLRequest(url: config.endpoint("/api/status"))
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            throw HermesError.unexpectedStatus(
                endpoint: "状态接口", status: http.statusCode
            )
        }
        do {
            return try decoder.decode(ServerStatus.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: "状态接口")
        }
    }

    // MARK: - 聊天主链传输底座（棒 1）

    /// 带 Bearer 的 URL 拼装（query 走 URLComponents，
    /// 与 iOS url(config:path:query:) 同形）
    private func authedURL(
        config: ServerConfig, path: String,
        query: [URLQueryItem] = []
    ) -> URL {
        guard var components = URLComponents(
            url: config.endpoint(path), resolvingAgainstBaseURL: false
        ) else { return config.endpoint(path) }
        if !query.isEmpty { components.queryItems = query }
        return components.url ?? config.endpoint(path)
    }

    /// 会话面通用 GET（Bearer＋共享 cookie 双通道，与
    /// iOS 会话面同路径；网关面认 Bearer、面板面认
    /// cookie，两面投影同形）
    private func sessionGet<T: Decodable>(
        config: ServerConfig, apiKey: String, path: String,
        query: [URLQueryItem] = [], endpoint: String
    ) async throws -> T {
        var request = URLRequest(
            url: authedURL(config: config, path: path, query: query)
        )
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: endpoint, status: http.statusCode
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    /// 写请求原始回执形（状态＋响应体都带回，围栏类
    /// 接口的拒因在 body 的 detail 码里，与 iOS
    /// sendRaw 同口径）
    private func sendRaw(
        config: ServerConfig, apiKey: String, path: String,
        method: String, query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(
            url: authedURL(config: config, path: path, query: query)
        )
        request.httpMethod = method
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        if let body {
            request.setValue(
                "application/json", forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, http) = try await dataRequest(request)
        return (http.statusCode, data)
    }

    // MARK: - 会话列表与消息（棒 1，对位 #9/#13）

    /// GET /api/sessions?limit=&offset=&archived=
    /// （archived 取 exclude/only/include，与 iOS
    /// serverSessionsPage 同口径）
    func sessionsPage(
        config: ServerConfig, apiKey: String, limit: Int,
        offset: Int, archived: String?
    ) async throws -> SessionsPage {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let archived {
            query.append(URLQueryItem(name: "archived", value: archived))
        }
        return try await sessionGet(
            config: config, apiKey: apiKey, path: "/api/sessions",
            query: query, endpoint: "服务端会话"
        )
    }

    /// GET /api/sessions/{id}/messages?limit=&order=
    /// latest（§237 订正口径：latest 从最新一页取起、
    /// 页内时序返回，本地按行 id 升序重排落盘）
    func sessionMessages(
        config: ServerConfig, apiKey: String, id: String,
        limit: Int = 200
    ) async throws -> [SessionMessage] {
        let response: SessionMessagesResponse = try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/api/sessions/\(id)/messages",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "order", value: "latest"),
            ],
            endpoint: "服务端会话消息"
        )
        return response.messages.sorted { $0.id < $1.id }
    }

    /// POST /api/sessions（网关面 Bearer 建会话，
    /// 0.7.0 主线钦定：id/title 由 App 指定、回执 id
    /// 为准；不带 title 时服务端两段式标题自生）
    func createSession(
        config: ServerConfig, apiKey: String, id: String?,
        title: String?
    ) async throws -> ServerSession {
        var body: [String: JSONValue] = [:]
        if let id { body["id"] = .string(id) }
        if let title { body["title"] = .string(title) }
        let (status, data) = try await sendRaw(
            config: config, apiKey: apiKey, path: "/api/sessions",
            method: "POST", body: body
        )
        switch status {
        case 200...299:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: "服务端建会话", status: status
            )
        }
        do {
            return try decoder.decode(CreatedSession.self, from: data).session
        } catch {
            throw HermesError.decodingFailed(endpoint: "服务端建会话")
        }
    }

    /// GET /api/sessions/{id}/mutation-snapshot：围栏
    /// 身份的官方指定来源（PATCH/DELETE 共用）
    func mutationSnapshot(
        config: ServerConfig, apiKey: String, id: String
    ) async throws -> SessionMutationSnapshot {
        try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/api/sessions/\(id)/mutation-snapshot",
            endpoint: "服务端会话变更快照"
        )
    }

    /// PATCH /api/sessions/{id}（围栏制，与 iOS
    /// updateServerSession 同口径：快照现读修订号→
    /// 带 request_id＋expected_revision 发→409 冲突
    /// 重读重试一次；身份读不到如实上抛、不裸发）
    func updateSession(
        config: ServerConfig, apiKey: String, id: String,
        title: String?, pinned: Bool?, archived: Bool?
    ) async throws {
        let endpoint = "服务端会话更新"
        for attempt in 0..<2 {
            let snapshot = try await mutationSnapshot(
                config: config, apiKey: apiKey, id: id
            )
            if snapshot.exists == false {
                throw HermesError.unexpectedStatus(
                    endpoint: endpoint, status: 404
                )
            }
            guard let revision = snapshot.runtimeRevision else {
                throw HermesError.decodingFailed(endpoint: endpoint)
            }
            var body: [String: JSONValue] = [
                "request_id": .string(UUID().uuidString),
                "expected_revision": .number(Double(revision)),
            ]
            if let title { body["title"] = .string(title) }
            if let pinned { body["pinned"] = .bool(pinned) }
            if let archived { body["archived"] = .bool(archived) }
            let (status, _) = try await sendRaw(
                config: config, apiKey: apiKey,
                path: "/api/sessions/\(id)", method: "PATCH", body: body
            )
            switch status {
            case 200...299:
                return
            case 401, 403:
                throw HermesError.apiKeyRejected
            case 409 where attempt == 0:
                continue
            default:
                throw HermesError.unexpectedStatus(
                    endpoint: endpoint, status: status
                )
            }
        }
    }

    /// DELETE /api/sessions/{id}（围栏三参数走 query，
    /// 与 iOS deleteServerSession 同口径：每试现读快
    /// 照、request_id 每试新铸、分流走 Core 的
    /// SessionDeleteDirective；身份读不到不发）
    func deleteSession(
        config: ServerConfig, apiKey: String, id: String
    ) async throws {
        let endpoint = "服务端会话删除"
        for attempt in 0..<3 {
            let snapshot: SessionMutationSnapshot
            do {
                snapshot = try await mutationSnapshot(
                    config: config, apiKey: apiKey, id: id
                )
            } catch let error as HermesError {
                if case .unexpectedStatus(_, let status) = error,
                   status == 404 {
                    return  // 快照都读不到＝已经不在了
                }
                throw error
            }
            if snapshot.exists == false { return }
            guard let revision = snapshot.runtimeRevision,
                  let generation = snapshot.runtimeGeneration else {
                throw HermesError.decodingFailed(endpoint: endpoint)
            }
            let (status, body) = try await sendRaw(
                config: config, apiKey: apiKey,
                path: "/api/sessions/\(id)", method: "DELETE",
                query: [
                    URLQueryItem(
                        name: "request_id", value: UUID().uuidString
                    ),
                    URLQueryItem(
                        name: "expected_revision", value: String(revision)
                    ),
                    URLQueryItem(
                        name: "expected_generation",
                        value: String(generation)
                    ),
                ]
            )
            switch SessionDeleteDirective.directive(
                status: status,
                serverCode: HermesServerErrorCode.parse(body)
            ) {
            case .done:
                return
            case .retryWithFreshIdentity:
                if attempt < 2 { continue }
            case .retryAfterBusy:
                if attempt < 2 {
                    try await Task.sleep(
                        for: attempt == 0
                            ? .milliseconds(1500) : .seconds(3)
                    )
                    continue
                }
                throw HermesError.sessionBusy
            case .fail:
                break
            }
            throw HermesError.unexpectedStatus(
                endpoint: endpoint, status: status
            )
        }
    }

    /// POST /api/sessions/{id}/model：会话内切换模型
    /// （与 iOS updateServerSessionModel 同路径）
    func updateSessionModel(
        config: ServerConfig, apiKey: String, id: String, model: String
    ) async throws {
        let (status, _) = try await sendRaw(
            config: config, apiKey: apiKey,
            path: "/api/sessions/\(id)/model", method: "POST",
            body: ["model": .string(model)]
        )
        switch status {
        case 200...299:
            return
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: "会话模型切换", status: status
            )
        }
    }

    // MARK: - 任务制生成（棒 1，对位 #14/#31）

    /// POST /v1/runs：提交一轮生成、立即返回 run_id
    /// （与 iOS submitRun 同体：session_id＋input＋
    /// model＋client_message_id 与 Idempotency-Key 头
    /// 同值双带，§383 幂等口径）
    func submitRun(
        config: ServerConfig, apiKey: String, sessionID: String,
        input: RunInput, model: String, idempotencyKey: String
    ) async throws -> RunSubmitResponse {
        var request = URLRequest(url: config.endpoint("/v1/runs"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            idempotencyKey, forHTTPHeaderField: "Idempotency-Key"
        )
        let payload: [String: Any] = [
            "session_id": sessionID,
            "input": try input.encodedValue(),
            "model": model,
            "client_message_id": idempotencyKey,
        ]
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload
        )
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        case 429:
            throw HermesError.rateLimited(retryAfterSeconds: nil)
        default:
            throw HermesError.unexpectedStatus(
                endpoint: "发送接口", status: http.statusCode
            )
        }
        do {
            return try decoder.decode(RunSubmitResponse.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: "发送接口")
        }
    }

    /// GET /v1/runs/{id}：run 状态轮询（404＝记录过
    /// 期/不存在，返回 nil 由调用方转 transcript 定性）
    func runStatus(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws -> RunStatusResponse? {
        var request = URLRequest(
            url: config.endpoint("/v1/runs/\(runID)")
        )
        request.timeoutInterval = 30
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200:
            break
        case 404:
            return nil
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: "生成状态接口", status: http.statusCode
            )
        }
        do {
            return try decoder.decode(RunStatusResponse.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: "生成状态接口")
        }
    }

    /// GET /v1/runs/{id}/events：结构化事件流（Core
    /// RunEventParser 逐行解析；流断只收尾不抛错——
    /// 定性归状态轮询与 transcript 对账，0.31.0 铁律）
    func runEvents(
        config: ServerConfig, apiKey: String, runID: String,
        lastSeq: Int
    ) -> AsyncStream<RunEventEnvelope> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(
                        url: config.endpoint(
                            "/v1/runs/\(runID)/events"
                        )
                    )
                    request.timeoutInterval = 600
                    request.setValue(
                        "Bearer \(apiKey)",
                        forHTTPHeaderField: "Authorization"
                    )
                    request.setValue(
                        "text/event-stream",
                        forHTTPHeaderField: "Accept"
                    )
                    if lastSeq >= 0 {
                        request.setValue(
                            String(lastSeq),
                            forHTTPHeaderField: "Last-Event-ID"
                        )
                    }
                    let (bytes, response) = try await session.bytes(
                        for: request
                    )
                    guard let http = response as? HTTPURLResponse,
                          http.statusCode == 200 else {
                        continuation.finish()
                        return
                    }
                    var parser = RunEventParser()
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let envelope = parser.consume(line: line) {
                            continuation.yield(envelope)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// POST /v1/runs/{id}/stop：真取消（404/409＝已
    /// 不在活动态、按受理处理，与 iOS 同口径）
    func stopRun(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws {
        var request = URLRequest(
            url: config.endpoint("/v1/runs/\(runID)/stop")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Data("{}".utf8)
        let (_, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299, 404, 409:
            return
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: "停止接口", status: http.statusCode
            )
        }
    }

    // MARK: - 待批数与附件（棒 1，对位 M1/#16）

    /// GET /v1/approvals（Bearer）：跨会话待批聚合，
    /// 菜单栏状态项只取件数（宽容提取：数组本体或
    /// approvals 键，取不到回 nil 不冒充 0）
    func pendingApprovalCount(
        config: ServerConfig, apiKey: String
    ) async throws -> Int? {
        let value: JSONValue = try await bearerGet(
            config: config, apiKey: apiKey, path: "/v1/approvals",
            endpoint: "待批接口"
        )
        switch value {
        case .array(let items):
            return items.count
        case .object(let object):
            if case .array(let items)? = object["approvals"] {
                return items.count
            }
            if case .number(let total)? = object["total"] {
                return Int(total)
            }
            return nil
        default:
            return nil
        }
    }

    /// POST /api/files/upload {path, data_url,
    /// overwrite}：附件先落托管根 attachments/（契约
    /// file-upload-contract-20261111，拼装走 Core
    /// FileSendAssembly），回执取服务端绝对路径
    func uploadAttachment(
        config: ServerConfig, apiKey: String, fileName: String,
        data: Data
    ) async throws -> ManagedFileUploadReceipt {
        let body: [String: JSONValue] = [
            "path": .string(FileSendAssembly.uploadPath(fileName: fileName)),
            "data_url": .string(
                FileSendAssembly.dataURL(fileName: fileName, data: data)
            ),
            "overwrite": .bool(true),
        ]
        let (status, responseData) = try await sendRaw(
            config: config, apiKey: apiKey, path: "/api/files/upload",
            method: "POST", body: body
        )
        switch status {
        case 200...299:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: "文件上传", status: status
            )
        }
        do {
            return try decoder.decode(
                ManagedFileUploadReceipt.self, from: responseData
            )
        } catch {
            throw HermesError.decodingFailed(endpoint: "文件上传")
        }
    }

    // MARK: - 档案与身份（棒 1，对位 #65）

    /// GET /api/profiles/active：当前档案名
    func activeProfile(
        config: ServerConfig, apiKey: String
    ) async throws -> ActiveProfileResponse {
        try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/api/profiles/active", endpoint: "当前档案"
        )
    }

    /// GET /api/profiles/{name}/soul：档案人设正文
    /// （profile 名按单个 path segment 百分号编码，
    /// 与 iOS soulPath 同口径）
    func profileSoul(
        config: ServerConfig, apiKey: String, name: String
    ) async throws -> ProfileSoulDocument {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? name
        return try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/api/profiles/\(encoded)/soul",
            endpoint: "档案人设"
        )
    }

    // MARK: - 批准与授权（棒 2，对位 #18/#19）

    /// 任意 Encodable 请求体转 sendRaw 的 JSONValue 字典
    private func encodeBody<T: Encodable>(
        _ value: T
    ) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(
            JSONValue.self, from: data
        )
        guard case .object(let dict) = decoded else {
            throw HermesError.decodingFailed(endpoint: "请求组装")
        }
        return dict
    }

    /// GET /v1/approvals（Bearer）：跨会话批准聚合
    /// 逐条记录（执行批准：命令/说明/可选裁决/状态）
    func approvalsList(
        config: ServerConfig, apiKey: String
    ) async throws -> MacApprovalsResponse {
        try await sessionGet(
            config: config, apiKey: apiKey, path: "/v1/approvals",
            endpoint: "待批接口"
        )
    }

    /// POST /v1/approvals/{request_id} {choice, reason?}：
    /// 执行批准裁决（choice 取记录 choices 内的值；
    /// 409＝已被处理/无活等待者，状态原样上抛供呈现
    /// 层分型，不盲重试）
    func resolveApproval(
        config: ServerConfig, apiKey: String, requestID: String,
        choice: String, reason: String?
    ) async throws {
        var body: [String: JSONValue] = ["choice": .string(choice)]
        if let reason, !reason.isEmpty {
            body["reason"] = .string(reason)
        }
        let (status, _) = try await sendRaw(
            config: config, apiKey: apiKey,
            path: "/v1/approvals/\(requestID)", method: "POST",
            body: body
        )
        switch status {
        case 200...299:
            return
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: "批准裁决", status: status
            )
        }
    }

    /// GET /v1/grants（Bearer）：统一授权清单（Core
    /// GrantsListResponse；双源皆败服务端回 503，如
    /// 实上抛、不回假空清单）
    func grants(
        config: ServerConfig, apiKey: String
    ) async throws -> GrantsListResponse {
        try await sessionGet(
            config: config, apiKey: apiKey, path: "/v1/grants",
            endpoint: "授权清单"
        )
    }

    /// POST /v1/grants/revoke {source:"exec",
    /// pattern_key}：撤销一条命令授权；回执不作终局
    /// （成败以事后清单回读为准），状态＋服务端错误
    /// 码原样带回供 GrantRevokeDirective 分型
    func revokeGrant(
        config: ServerConfig, apiKey: String, patternKey: String
    ) async throws -> (status: Int, serverCode: String?) {
        let (status, data) = try await sendRaw(
            config: config, apiKey: apiKey, path: "/v1/grants/revoke",
            method: "POST",
            body: try encodeBody(GrantRevokeRequest.exec(
                patternKey: patternKey
            ))
        )
        return (status, HermesServerErrorCode.parse(data))
    }

    // MARK: - 写闸批准（棒 2，对位 #18/#19；网关原生面）

    /// GET /v1/write-gate/status：闸门判定源（桥退役
    /// 后由网关 write_gate_gateway 同形提供，Bearer
    /// 同一把登录密钥）
    func writeGateStatus(
        config: ServerConfig, apiKey: String
    ) async throws -> WriteGateStatus {
        try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/v1/write-gate/status", endpoint: "审批状态"
        )
    }

    /// GET /v1/write-gate/pending：待批记录（桥序＝
    /// created_at 升序，先进先审）
    func writeGatePending(
        config: ServerConfig, apiKey: String
    ) async throws -> WriteGatePendingList {
        try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/v1/write-gate/pending", endpoint: "待批列表"
        )
    }

    /// GET /v1/write-gate/pending/{subsystem}/{id}：
    /// 记录＋改动对照（review）一次返回
    func writeGateDetail(
        config: ServerConfig, apiKey: String,
        subsystem: WriteGateSubsystem, id: String
    ) async throws -> WriteGateDetail {
        guard let segment = subsystem.pathSegment else {
            throw MacWriteGateError.failed(
                "这类审批 App 里还处理不了，请在 Hermes 网页端处理。"
            )
        }
        do {
            return try await sessionGet(
                config: config, apiKey: apiKey,
                path: "/v1/write-gate/pending/\(segment)/\(id)",
                endpoint: "待批详情"
            )
        } catch let error as HermesError {
            if case .unexpectedStatus(_, let status) = error {
                switch status {
                case 401, 403: throw MacWriteGateError.unauthorized
                case 404: throw MacWriteGateError.recordGone
                case 409: throw MacWriteGateError.conflict
                default: break
                }
            }
            throw error
        }
    }

    /// POST /v1/write-gate/pending/{subsystem}/{id}/
    /// approve|reject：裁决（回执 success=false 一律
    /// 按失败处理，与 iOS 同口径）
    func writeGateDecide(
        config: ServerConfig, apiKey: String,
        subsystem: WriteGateSubsystem, id: String, approve: Bool
    ) async throws -> WriteGateDecisionResponse {
        guard let segment = subsystem.pathSegment else {
            throw MacWriteGateError.failed(
                "这类审批 App 里还处理不了，请在 Hermes 网页端处理。"
            )
        }
        let action = approve ? "approve" : "reject"
        let (status, data) = try await sendRaw(
            config: config, apiKey: apiKey,
            path: "/v1/write-gate/pending/\(segment)/\(id)/\(action)",
            method: "POST", body: [:]
        )
        switch status {
        case 200...299:
            do {
                return try decoder.decode(
                    WriteGateDecisionResponse.self, from: data
                )
            } catch {
                throw MacWriteGateError.failed("裁决回执格式无法识别")
            }
        case 401, 403:
            throw MacWriteGateError.unauthorized
        case 404:
            throw MacWriteGateError.recordGone
        case 409:
            throw MacWriteGateError.conflict
        default:
            throw MacWriteGateError.failed("裁决返回 \(status)")
        }
    }

    /// GET /v1/write-gate/decisions?limit=：已决历史
    func writeGateDecisions(
        config: ServerConfig, apiKey: String, limit: Int = 50
    ) async throws -> [WriteGateDecisionRecord] {
        let response: WriteGateDecisionsResponse = try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/v1/write-gate/decisions",
            query: [URLQueryItem(name: "limit", value: String(limit))],
            endpoint: "已决记录"
        )
        return response.decisions
    }

    /// GET /v1/write-gate/rules：「总是允许」规则全集
    /// （规则只存服务端，端侧不落本地）
    func writeGateRules(
        config: ServerConfig, apiKey: String
    ) async throws -> [WriteGateRule] {
        let response: WriteGateRulesResponse = try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/v1/write-gate/rules", endpoint: "审批规则"
        )
        return response.rules
    }

    /// POST /v1/write-gate/rules {subsystem, origin}：
    /// 建一条「总是允许」规则（服务端同键幂等）
    func createWriteGateRule(
        config: ServerConfig, apiKey: String,
        subsystem: WriteGateSubsystem, origin: String
    ) async throws -> WriteGateRule {
        guard let segment = subsystem.pathSegment else {
            throw MacWriteGateError.failed(
                "这类审批 App 里还处理不了，请在 Hermes 网页端处理。"
            )
        }
        let (status, data) = try await sendRaw(
            config: config, apiKey: apiKey,
            path: "/v1/write-gate/rules", method: "POST",
            body: [
                "subsystem": .string(segment),
                "origin": .string(origin),
            ]
        )
        switch status {
        case 200...299:
            do {
                return try decoder.decode(
                    WriteGateRuleResponse.self, from: data
                ).rule
            } catch {
                throw MacWriteGateError.failed("建立规则回执格式无法识别")
            }
        case 401, 403:
            throw MacWriteGateError.unauthorized
        case 409:
            throw MacWriteGateError.conflict
        default:
            throw MacWriteGateError.failed("建立规则返回 \(status)")
        }
    }

    /// DELETE /v1/write-gate/rules/{id}：撤销一条规则
    /// （404＝已不存在，如实上抛、不假装撤成）
    func deleteWriteGateRule(
        config: ServerConfig, apiKey: String, id: String
    ) async throws {
        let (status, _) = try await sendRaw(
            config: config, apiKey: apiKey,
            path: "/v1/write-gate/rules/\(id)", method: "DELETE"
        )
        switch status {
        case 200...299:
            return
        case 401, 403:
            throw MacWriteGateError.unauthorized
        case 404:
            throw MacWriteGateError.failed(
                "这条规则已不存在，可能已被撤销。"
            )
        default:
            throw MacWriteGateError.failed("撤销规则返回 \(status)")
        }
    }

    // MARK: - 凭据库（棒 2，对位 #71/#20）

    /// GET /v1/vault/entries：条目元数据全集（值不回
    /// 客户端，只有字段名与 has_secret）
    func vaultEntries(
        config: ServerConfig, apiKey: String
    ) async throws -> [MacVaultEntry] {
        let response: MacVaultEntryListResponse = try await sessionGet(
            config: config, apiKey: apiKey, path: "/v1/vault/entries",
            endpoint: "凭据库"
        )
        return response.data
    }

    /// GET /v1/vault/entries/{id}：单条元数据
    func vaultEntry(
        config: ServerConfig, apiKey: String, id: String
    ) async throws -> MacVaultEntry {
        try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/v1/vault/entries/\(id)", endpoint: "凭据条目"
        )
    }

    /// POST /v1/vault/entries：新建条目（值由用户在端
    /// 上输入、直送服务端，本地不落盘）
    func createVaultEntry(
        config: ServerConfig, apiKey: String,
        request: MacVaultWriteRequest
    ) async throws -> MacVaultWriteResponse {
        try await vaultWrite(
            config: config, apiKey: apiKey, path: "/v1/vault/entries",
            method: "POST", request: request, endpoint: "凭据库"
        )
    }

    /// PUT /v1/vault/entries/{id}：整条替换
    func replaceVaultEntry(
        config: ServerConfig, apiKey: String, id: String,
        request: MacVaultWriteRequest
    ) async throws -> MacVaultWriteResponse {
        try await vaultWrite(
            config: config, apiKey: apiKey,
            path: "/v1/vault/entries/\(id)",
            method: "PUT", request: request, endpoint: "凭据条目"
        )
    }

    private func vaultWrite(
        config: ServerConfig, apiKey: String, path: String,
        method: String, request: MacVaultWriteRequest,
        endpoint: String
    ) async throws -> MacVaultWriteResponse {
        let (status, data) = try await sendRaw(
            config: config, apiKey: apiKey, path: path,
            method: method, body: try encodeBody(request)
        )
        switch status {
        case 200...299:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: endpoint, status: status
            )
        }
        do {
            return try decoder.decode(
                MacVaultWriteResponse.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    /// DELETE /v1/vault/entries/{id}：撤销（删除）条目
    func revokeVaultEntry(
        config: ServerConfig, apiKey: String, id: String
    ) async throws {
        let (status, _) = try await sendRaw(
            config: config, apiKey: apiKey,
            path: "/v1/vault/entries/\(id)", method: "DELETE"
        )
        switch status {
        case 200...299:
            return
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: "凭据条目", status: status
            )
        }
    }

    /// GET /v1/vault/requests：凭据请求全集（待办面
    /// 按 status 分流呈现）
    func vaultRequests(
        config: ServerConfig, apiKey: String
    ) async throws -> [MacVaultRequest] {
        let response: MacVaultRequestListResponse = try await sessionGet(
            config: config, apiKey: apiKey, path: "/v1/vault/requests",
            endpoint: "凭据请求"
        )
        return response.data
    }

    /// GET /v1/vault/requests/{id}：单条请求状态
    func vaultRequestStatus(
        config: ServerConfig, apiKey: String, requestID: String
    ) async throws -> MacVaultRequestStatus {
        try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/v1/vault/requests/\(requestID)",
            endpoint: "凭据请求"
        )
    }

    /// POST /v1/vault/requests/{id}/fulfill：兑现
    /// （decision=fulfill 带值）或拒绝（decision=
    /// reject）；值只在本次请求内出现，不落盘不进日志
    func fulfillVaultRequest(
        config: ServerConfig, apiKey: String, requestID: String,
        request: MacVaultFulfillRequest
    ) async throws -> MacVaultFulfillResponse {
        let (status, data) = try await sendRaw(
            config: config, apiKey: apiKey,
            path: "/v1/vault/requests/\(requestID)/fulfill",
            method: "POST", body: try encodeBody(request)
        )
        switch status {
        case 200...299:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: "凭据请求", status: status
            )
        }
        do {
            return try decoder.decode(
                MacVaultFulfillResponse.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(endpoint: "凭据请求")
        }
    }
}
