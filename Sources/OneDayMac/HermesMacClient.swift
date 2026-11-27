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
    // MARK: - 桥面：动态/想法/目标/文件库（棒 3，对位 #2/#3/#4/#5/#34–#38/#10）

    /// oneday-bridge 通用口：与 iOS OneDayBridgeClient
    /// 同前缀（/api/oneday-bridge）、同 Bearer（登录密
    /// 钥一把，桥面直接验令牌）、同 DTO（Core 单源，
    /// 不另立第二形）。零新后端。
    private func bridgeRequest<T: Decodable>(
        config: ServerConfig, apiKey: String, path: String,
        method: String = "GET", query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil, endpoint: String
    ) async throws -> T {
        let (status, data) = try await sendRaw(
            config: config, apiKey: apiKey, path: path,
            method: method, query: query, body: body
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
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    private static let bridgeBase = "/api/oneday-bridge"

    // MARK: 动态（#2/#34）

    /// GET /feed?days=30：近 30 天帖流（晨报＋汇编双
    /// 生产者同流，kind 在帖上分型）
    func feedPosts(
        config: ServerConfig, apiKey: String
    ) async throws -> [BridgeFeedPost] {
        let response: BridgeFeedPostsResponse = try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/feed",
            query: [URLQueryItem(name: "days", value: "30")],
            endpoint: "动态列表"
        )
        return response.items
    }

    /// POST /feed/{id}/read：已读落服务端真源，回执全形
    func feedMarkRead(
        config: ServerConfig, apiKey: String, id: String
    ) async throws -> BridgeFeedPost {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/feed/\(id)/read",
            method: "POST", endpoint: "标记已读"
        )
    }

    /// POST /feed/{id}/like {liked}：幂等，回执全形为
    /// 点赞态唯一真源
    func feedSetLiked(
        config: ServerConfig, apiKey: String, id: String,
        liked: Bool
    ) async throws -> BridgeFeedPost {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/feed/\(id)/like",
            method: "POST",
            body: try encodeBody(BridgeFeedLikeRequest(liked: liked)),
            endpoint: "点赞"
        )
    }

    /// POST /feed/{id}/signal {type:"discuss"}：引用建
    /// 聊后发一记讨论信号（弱信号记账，无 note 不带）
    func feedDiscussSignal(
        config: ServerConfig, apiKey: String, id: String
    ) async throws {
        let _: BridgeOKResponse = try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/feed/\(id)/signal",
            method: "POST",
            body: try encodeBody(
                BridgeFeedSignalRequest(type: "discuss", note: nil)
            ),
            endpoint: "讨论信号"
        )
    }

    /// GET /meta/brief：动态简报全文（当前生效全文）
    func feedBrief(
        config: ServerConfig, apiKey: String
    ) async throws -> BridgeBriefDoc {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/meta/brief",
            endpoint: "动态简报"
        )
    }

    /// PUT /meta/brief {text}：保存简报，回执为保存后全文
    func saveFeedBrief(
        config: ServerConfig, apiKey: String, text: String
    ) async throws -> BridgeBriefDoc {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/meta/brief",
            method: "PUT",
            body: try encodeBody(BridgeBriefSaveRequest(text: text)),
            endpoint: "保存简报"
        )
    }

    /// POST /feed/generate：手动起一轮调研（在跑时桥
    /// 回 409，文案由调用方原样呈现）
    func generateFeed(
        config: ServerConfig, apiKey: String
    ) async throws {
        let _: BridgeOKResponse = try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/feed/generate",
            method: "POST", endpoint: "生成动态"
        )
    }

    // MARK: 想法（#3/#35）

    /// GET /ideas：点子全集
    func ideas(
        config: ServerConfig, apiKey: String
    ) async throws -> [BridgeIdea] {
        let response: BridgeIdeasResponse = try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/ideas", endpoint: "点子列表"
        )
        return response.items
    }

    /// POST /ideas：新建点子（用户手建）
    func createIdea(
        config: ServerConfig, apiKey: String,
        request body: BridgeIdeaCreateRequest
    ) async throws -> BridgeIdea {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/ideas", method: "POST",
            body: try encodeBody(body), endpoint: "新建点子"
        )
    }

    /// DELETE /ideas/{id}
    func deleteIdea(
        config: ServerConfig, apiKey: String, id: String
    ) async throws {
        let _: BridgeOKResponse = try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/ideas/\(id)",
            method: "DELETE", endpoint: "删除点子"
        )
    }

    /// PATCH /ideas/{id}：状态流转（忽略/恢复），桥侧
    /// 状态机把关，非法流转回 400 原样上抛
    func patchIdea(
        config: ServerConfig, apiKey: String, id: String,
        request body: BridgeIdeaPatchRequest
    ) async throws -> BridgeIdea {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/ideas/\(id)",
            method: "PATCH", body: try encodeBody(body),
            endpoint: "更新点子"
        )
    }

    /// GET /ideas/generation：生成管道账面（上次/下次
    /// 运行与近轮记录）；端点不存在时上抛，调用方降级
    func ideasGeneration(
        config: ServerConfig, apiKey: String
    ) async throws -> BridgeGenerationInfo {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/ideas/generation",
            endpoint: "生成记录"
        )
    }

    // MARK: 目标（#4/#36）

    /// GET /goals：目标全集
    func goals(
        config: ServerConfig, apiKey: String
    ) async throws -> [BridgeGoal] {
        let response: BridgeGoalsResponse = try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/goals", endpoint: "目标列表"
        )
        return response.items
    }

    /// POST /goals：新建目标
    func createGoal(
        config: ServerConfig, apiKey: String,
        request body: BridgeGoalCreateRequest
    ) async throws -> BridgeGoal {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/goals", method: "POST",
            body: try encodeBody(body), endpoint: "新建目标"
        )
    }

    /// PATCH /goals/{id}：标题/备注全量编辑
    func patchGoal(
        config: ServerConfig, apiKey: String, id: String,
        request body: BridgeGoalPatchRequest
    ) async throws -> BridgeGoal {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/goals/\(id)",
            method: "PATCH", body: try encodeBody(body),
            endpoint: "保存目标"
        )
    }

    /// PATCH /goals/{id} {status}：状态流转（完成/重开等）
    func patchGoalStatus(
        config: ServerConfig, apiKey: String, id: String,
        status: GoalStatus
    ) async throws -> BridgeGoal {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/goals/\(id)",
            method: "PATCH",
            body: try encodeBody(
                BridgeGoalStatusPatchRequest(status: status)
            ),
            endpoint: "目标状态"
        )
    }

    /// DELETE /goals/{id}
    func deleteGoal(
        config: ServerConfig, apiKey: String, id: String
    ) async throws {
        let _: BridgeOKResponse = try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/goals/\(id)",
            method: "DELETE", endpoint: "删除目标"
        )
    }

    /// GET /goals/{id}/entries：进展条目流（升序）
    func goalEntries(
        config: ServerConfig, apiKey: String, goalID: String
    ) async throws -> [BridgeGoalEntry] {
        let response: BridgeGoalEntriesResponse =
            try await bridgeRequest(
                config: config, apiKey: apiKey,
                path: "\(Self.bridgeBase)/goals/\(goalID)/entries",
                endpoint: "进展记录"
            )
        return response.items
    }

    /// POST /goals/{id}/entries：追加一条进展
    func createGoalEntry(
        config: ServerConfig, apiKey: String, goalID: String,
        request body: BridgeGoalEntryCreateRequest
    ) async throws -> BridgeGoalEntry {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/goals/\(goalID)/entries",
            method: "POST", body: try encodeBody(body),
            endpoint: "记录进展"
        )
    }

    /// DELETE /goals/{id}/entries/{eid}：删单条纠错
    func deleteGoalEntry(
        config: ServerConfig, apiKey: String, goalID: String,
        entryID: String
    ) async throws {
        let _: BridgeOKResponse = try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/goals/\(goalID)"
                + "/entries/\(entryID)",
            method: "DELETE", endpoint: "删除进展"
        )
    }

    /// GET /goals/{id}/briefings：目标简报信件（最新在前）
    func goalBriefings(
        config: ServerConfig, apiKey: String, goalID: String
    ) async throws -> [BridgeBriefing] {
        let response: BridgeBriefingsResponse =
            try await bridgeRequest(
                config: config, apiKey: apiKey,
                path: "\(Self.bridgeBase)/goals/\(goalID)/briefings",
                endpoint: "目标简报"
            )
        return response.items
    }

    /// POST /goals/{id}/briefings/{bid}/opened：打开信
    /// 件记一记（台账看「写了没看」），回执为盖过记录
    /// 的简报全形
    func markBriefingOpened(
        config: ServerConfig, apiKey: String, goalID: String,
        briefingID: String
    ) async throws -> BridgeBriefing {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/goals/\(goalID)"
                + "/briefings/\(briefingID)/opened",
            method: "POST", endpoint: "简报打开记录"
        )
    }

    // MARK: 文件库与文件字节（#5/#37/#38）

    /// GET /file-library：文件页聚合读面（产出根走查、
    /// 准入、去重、排序全在服务端，客户端只消费单流）
    func fileLibrary(
        config: ServerConfig, apiKey: String
    ) async throws -> FileLibraryPage {
        try await bridgeRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/file-library",
            endpoint: "文件库"
        )
    }

    /// GET /api/files/download?path=：原文件字节（网关
    /// 面 Bearer，与 iOS 同路）；预览/打开/导出共用此口
    func fileDownload(
        config: ServerConfig, apiKey: String, path: String
    ) async throws -> Data {
        var request = URLRequest(
            url: authedURL(
                config: config, path: "/api/files/download",
                query: [URLQueryItem(name: "path", value: path)]
            )
        )
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: "文件下载", status: http.statusCode
            )
        }
    }

    // MARK: 全局搜索·会话段（#10）

    /// GET /api/sessions/search?q=&limit=：服务端会话
    /// 全文搜索（与 iOS 全局搜索同口径）
    func searchSessions(
        config: ServerConfig, apiKey: String, query: String,
        limit: Int = 50
    ) async throws -> [SessionSearchHit] {
        let response: SessionSearchResponse = try await sessionGet(
            config: config, apiKey: apiKey,
            path: "/api/sessions/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            endpoint: "会话搜索"
        )
        return response.results
    }

    // MARK: - 枢纽与管理面（棒 4，对位 #11/#39–#64）

    /// 管理面通用口：与 iOS HermesClient 同路径、同
    /// 状态码口径（Bearer 登录密钥＋共享 cookie 双通
    /// 道，sendRaw 底座）。零新后端。
    private func hubRequest<T: Decodable>(
        config: ServerConfig, apiKey: String, path: String,
        method: String = "GET", query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil, endpoint: String
    ) async throws -> T {
        let (status, data) = try await sendRaw(
            config: config, apiKey: apiKey, path: path,
            method: method, query: query, body: body
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
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    /// 宽容 JSON 口：形状随服务端版本漂移的管理面
    /// （委派/频道/设备等）先取 JSONValue，呈现层按
    /// 字段宽容提取，不因多/少字段整面解码失败
    private func hubJSON(
        config: ServerConfig, apiKey: String, path: String,
        method: String = "GET", query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil, endpoint: String
    ) async throws -> JSONValue {
        try await hubRequest(
            config: config, apiKey: apiKey, path: path,
            method: method, query: query, body: body,
            endpoint: endpoint
        )
    }

    /// 动作口：只认状态码（成败终局由调用方回读对账，
    /// 与 iOS 各 Directive 口径一致，不认回执自报）
    private func hubFire(
        config: ServerConfig, apiKey: String, path: String,
        method: String = "POST", query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil, endpoint: String
    ) async throws {
        let (status, _) = try await sendRaw(
            config: config, apiKey: apiKey, path: path,
            method: method, query: query, body: body
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
    }

    /// 原始字节口（身份头像图等）
    private func hubData(
        config: ServerConfig, apiKey: String, path: String,
        query: [URLQueryItem] = [], endpoint: String
    ) async throws -> Data {
        var request = URLRequest(
            url: authedURL(config: config, path: path, query: query)
        )
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200:
            return data
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: endpoint, status: http.statusCode
            )
        }
    }

    // MARK: 工作台账与身份（桥面，#39/#42）

    /// GET /api/oneday-bridge/ledger/summary：台账汇总
    func hubLedgerSummary(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/ledger/summary",
            endpoint: "台账汇总"
        )
    }

    /// GET /api/oneday-bridge/ledger：台账条目列
    func hubLedger(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/ledger",
            endpoint: "工作台账"
        )
    }

    /// GET /api/oneday-bridge/ledger/{id}：条目详情
    func hubLedgerEntry(
        config: ServerConfig, apiKey: String, id: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/ledger/\(id)",
            endpoint: "台账详情"
        )
    }

    /// GET /api/identity-bridge/identity：身份全档
    /// （名/头像/档案），与 iOS IdentityBridgeClient 同面
    func hubIdentity(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/identity-bridge/identity",
            endpoint: "身份"
        )
    }

    /// GET /api/identity-bridge/identity/avatar/image：
    /// 头像图字节（当前或指定 id）
    func hubAvatarImage(
        config: ServerConfig, apiKey: String, id: String?
    ) async throws -> Data {
        var query: [URLQueryItem] = []
        if let id { query.append(URLQueryItem(name: "id", value: id)) }
        return try await hubData(
            config: config, apiKey: apiKey,
            path: "/api/identity-bridge/identity/avatar/image",
            query: query, endpoint: "头像图"
        )
    }

    // MARK: 电脑与出口（#41）

    /// GET /api/tools/computer-use/status：电脑操控状态
    func hubComputerStatus(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/tools/computer-use/status",
            endpoint: "电脑状态"
        )
    }

    /// GET /api/egress/status：出口状态
    func hubEgressStatus(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/egress/status",
            endpoint: "出口状态"
        )
    }

    // MARK: 档案（#44）

    /// GET /api/profiles：档案清单（宽容提取名/激活态）
    func hubProfiles(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/profiles", endpoint: "档案清单"
        )
    }

    /// POST /api/profiles/active {name}：切换激活档案
    func hubSetActiveProfile(
        config: ServerConfig, apiKey: String, name: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/profiles/active",
            body: ["name": .string(name)], endpoint: "切换档案"
        )
    }

    /// GET /api/profiles/{name}/soul：指定档案的 Soul 文档
    func hubProfileSoul(
        config: ServerConfig, apiKey: String, name: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/profiles/\(name)/soul",
            endpoint: "档案 Soul"
        )
    }

    /// PUT /api/profiles/{name}/soul {content}：写回 Soul
    func hubUpdateProfileSoul(
        config: ServerConfig, apiKey: String, name: String,
        content: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/profiles/\(name)/soul", method: "PUT",
            body: ["content": .string(content)],
            endpoint: "保存 Soul"
        )
    }

    // MARK: 记忆与学习图谱（#45）

    /// GET /api/memory：记忆状态（provider/内置文件数）
    func hubMemoryStatus(
        config: ServerConfig, apiKey: String
    ) async throws -> MemoryStatus {
        try await hubRequest(
            config: config, apiKey: apiKey,
            path: "/api/memory", endpoint: "记忆状态"
        )
    }

    /// GET /v1/memory/layers：分层记忆（Bearer 面）
    func hubMemoryLayers(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/v1/memory/layers", endpoint: "分层记忆"
        )
    }

    /// GET /api/learning/graph：学习图谱（技能＋记忆块）
    func hubLearningGraph(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/learning/graph", endpoint: "学习图谱"
        )
    }

    /// GET /api/learning/node?id=：节点全文（编辑预填）
    func hubLearningNode(
        config: ServerConfig, apiKey: String, id: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/learning/node",
            query: [URLQueryItem(name: "id", value: id)],
            endpoint: "图谱节点"
        )
    }

    /// PUT /api/learning/node {id, content}：改写节点全文
    func hubUpdateLearningNode(
        config: ServerConfig, apiKey: String, id: String,
        content: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/learning/node", method: "PUT",
            body: ["id": .string(id), "content": .string(content)],
            endpoint: "保存节点"
        )
    }

    /// DELETE /api/learning/node {id}：技能归档/记忆删除
    /// （服务端语义，呈现层按 kind 分流确认文案）
    func hubDeleteLearningNode(
        config: ServerConfig, apiKey: String, id: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/learning/node", method: "DELETE",
            body: ["id": .string(id)], endpoint: "删除节点"
        )
    }

    // MARK: 技能（#46）

    /// GET /api/skills（裸数组）
    func hubSkills(
        config: ServerConfig, apiKey: String
    ) async throws -> [SkillItem] {
        try await hubRequest(
            config: config, apiKey: apiKey,
            path: "/api/skills", endpoint: "技能清单"
        )
    }

    /// GET /api/skills/content?name=：技能全文
    func hubSkillContent(
        config: ServerConfig, apiKey: String, name: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/skills/content",
            query: [URLQueryItem(name: "name", value: name)],
            endpoint: "技能内容"
        )
    }

    /// PUT /api/skills/content {name, content}
    func hubUpdateSkillContent(
        config: ServerConfig, apiKey: String, name: String,
        content: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/skills/content", method: "PUT",
            body: ["name": .string(name),
                   "content": .string(content)],
            endpoint: "保存技能"
        )
    }

    /// PUT /api/skills/toggle {name, enabled}
    func hubToggleSkill(
        config: ServerConfig, apiKey: String, name: String,
        enabled: Bool
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/skills/toggle", method: "PUT",
            body: ["name": .string(name),
                   "enabled": .bool(enabled)],
            endpoint: "技能开关"
        )
    }

    /// PUT /api/skills/lock {name, locked}
    func hubLockSkill(
        config: ServerConfig, apiKey: String, name: String,
        locked: Bool
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/skills/lock", method: "PUT",
            body: ["name": .string(name),
                   "locked": .bool(locked)],
            endpoint: "技能锁定"
        )
    }

    /// GET /api/skills/hub/search?q=：技能市集搜索
    func hubSkillSearch(
        config: ServerConfig, apiKey: String, query: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/skills/hub/search",
            query: [URLQueryItem(name: "q", value: query)],
            endpoint: "技能市集搜索"
        )
    }

    /// POST /api/skills/hub/install {identifier}
    func hubSkillInstall(
        config: ServerConfig, apiKey: String, identifier: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/skills/hub/install",
            body: ["identifier": .string(identifier)],
            endpoint: "安装技能"
        )
    }

    /// POST /api/skills/hub/uninstall {name}
    func hubSkillUninstall(
        config: ServerConfig, apiKey: String, name: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/skills/hub/uninstall",
            body: ["name": .string(name)],
            endpoint: "卸载技能"
        )
    }

    // MARK: 工具集与委派（#47/#48）

    /// GET /v1/toolsets（Bearer）：api_server 平台真值
    func hubToolsets(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/v1/toolsets", endpoint: "工具集"
        )
    }

    /// PUT /v1/toolsets/{name} {enabled}
    func hubSetToolsetEnabled(
        config: ServerConfig, apiKey: String, name: String,
        enabled: Bool
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/v1/toolsets/\(name)", method: "PUT",
            body: ["enabled": .bool(enabled)],
            endpoint: "工具集开关"
        )
    }

    /// GET /api/delegation/routing：委派路由全量
    func hubDelegationRouting(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/delegation/routing", endpoint: "委派路由"
        )
    }

    /// PUT /api/delegation/backend {backend}：切换后端
    /// （成败以 routing 回读为准）
    func hubSetDelegationBackend(
        config: ServerConfig, apiKey: String, backend: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/delegation/backend", method: "PUT",
            body: ["backend": .string(backend)],
            endpoint: "切换委派后端"
        )
    }

    /// PUT /api/delegation/backends/model_map：模型映射
    func hubSetDelegationModelMap(
        config: ServerConfig, apiKey: String,
        body: [String: JSONValue]
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/delegation/backends/model_map",
            method: "PUT", body: body, endpoint: "委派模型映射"
        )
    }

    /// PUT /api/delegation/backends/profile_routes：档案路由
    func hubSetDelegationProfileRoutes(
        config: ServerConfig, apiKey: String,
        body: [String: JSONValue]
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/delegation/backends/profile_routes",
            method: "PUT", body: body, endpoint: "委派档案路由"
        )
    }

    // MARK: 定时任务（#49，兼全局搜索定时段 #10）

    /// GET /api/cron/jobs（裸数组）
    func hubCronJobs(
        config: ServerConfig, apiKey: String
    ) async throws -> [CronJob] {
        try await hubRequest(
            config: config, apiKey: apiKey,
            path: "/api/cron/jobs", endpoint: "定时任务"
        )
    }

    /// POST /api/cron/jobs：新建（schedule 为字符串表达式）
    func hubCreateCronJob(
        config: ServerConfig, apiKey: String, name: String?,
        prompt: String, schedule: String, deliver: String?
    ) async throws -> CronJob {
        var body: [String: JSONValue] = [
            "prompt": .string(prompt),
            "schedule": .string(schedule),
        ]
        if let name { body["name"] = .string(name) }
        if let deliver { body["deliver"] = .string(deliver) }
        return try await hubRequest(
            config: config, apiKey: apiKey,
            path: "/api/cron/jobs", method: "POST", body: body,
            endpoint: "新建定时任务"
        )
    }

    /// PUT /api/cron/jobs/{id} {updates}
    func hubUpdateCronJob(
        config: ServerConfig, apiKey: String, id: String,
        updates: [String: JSONValue]
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/cron/jobs/\(id)", method: "PUT",
            body: updates, endpoint: "更新定时任务"
        )
    }

    /// DELETE /api/cron/jobs/{id}
    func hubDeleteCronJob(
        config: ServerConfig, apiKey: String, id: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/cron/jobs/\(id)", method: "DELETE",
            endpoint: "删除定时任务"
        )
    }

    /// POST /api/cron/jobs/{id}/pause|resume|trigger
    func hubCronAction(
        config: ServerConfig, apiKey: String, id: String,
        action: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/cron/jobs/\(id)/\(action)",
            endpoint: "定时任务动作"
        )
    }

    /// GET /api/cron/blueprints：蓝图目录
    func hubCronBlueprints(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/cron/blueprints", endpoint: "任务蓝图"
        )
    }

    /// GET /api/cron/delivery-targets：投递目标
    func hubCronDeliveryTargets(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/cron/delivery-targets",
            endpoint: "投递目标"
        )
    }

    // MARK: MCP（#50）

    private struct MCPServersEnvelope: Decodable {
        let servers: [MCPServerItem]
    }

    /// GET /api/mcp/servers（{"servers":[…]} 信封）
    func hubMCPServers(
        config: ServerConfig, apiKey: String
    ) async throws -> [MCPServerItem] {
        let envelope: MCPServersEnvelope = try await hubRequest(
            config: config, apiKey: apiKey,
            path: "/api/mcp/servers", endpoint: "MCP 服务器"
        )
        return envelope.servers
    }

    /// PUT /api/mcp/servers/{name}/enabled {enabled}
    func hubSetMCPServerEnabled(
        config: ServerConfig, apiKey: String, name: String,
        enabled: Bool
    ) async throws {
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? name
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/mcp/servers/\(encoded)/enabled",
            method: "PUT", body: ["enabled": .bool(enabled)],
            endpoint: "MCP 开关"
        )
    }

    /// POST /api/mcp/servers/{name}/test：连通性测试
    func hubTestMCPServer(
        config: ServerConfig, apiKey: String, name: String
    ) async throws -> JSONValue {
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? name
        return try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/mcp/servers/\(encoded)/test",
            method: "POST", endpoint: "MCP 测试"
        )
    }

    /// GET /api/mcp/catalog：可安装目录
    func hubMCPCatalog(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/mcp/catalog", endpoint: "MCP 目录"
        )
    }

    /// POST /api/mcp/catalog/install：安装目录条目
    func hubMCPInstall(
        config: ServerConfig, apiKey: String,
        body: [String: JSONValue]
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/mcp/catalog/install", body: body,
            endpoint: "安装 MCP"
        )
    }

    // MARK: 频道（#52）

    /// GET /api/messaging/platforms：消息平台全量
    func hubMessagingPlatforms(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/messaging/platforms",
            endpoint: "消息平台"
        )
    }

    /// GET /api/companion/gateway-channels：网关频道
    func hubGatewayChannels(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/companion/gateway-channels",
            endpoint: "网关频道"
        )
    }

    // MARK: 设备与主会话（#53/#61）

    /// GET /api/device-bridge/device/session：设备会话
    func hubDeviceSession(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/device-bridge/device/session",
            endpoint: "设备会话"
        )
    }

    /// GET /api/device-bridge/device/sync/status：同步状态
    func hubDeviceSyncStatus(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/device-bridge/device/sync/status",
            endpoint: "设备同步状态"
        )
    }

    /// GET /api/device-bridge/device/park-state：主会话停泊态
    func hubDeviceParkState(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/device-bridge/device/park-state",
            endpoint: "主会话状态"
        )
    }

    /// GET /v1/auth/sessions：登录会话清单（#60 服务器会话）
    func hubAuthSessions(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/v1/auth/sessions", endpoint: "登录会话"
        )
    }

    // MARK: 监控（桥面，#54）

    /// GET /api/oneday-bridge/monitors
    func hubMonitors(
        config: ServerConfig, apiKey: String
    ) async throws -> BridgeMonitorsResponse {
        try await hubRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/monitors",
            endpoint: "监控清单"
        )
    }

    /// GET /api/oneday-bridge/monitors/{id}/changes
    func hubMonitorChanges(
        config: ServerConfig, apiKey: String, id: String
    ) async throws -> BridgeMonitorChangesResponse {
        try await hubRequest(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/monitors/\(id)/changes",
            endpoint: "监控变化"
        )
    }

    /// POST /api/oneday-bridge/monitors：新建监控
    func hubCreateMonitor(
        config: ServerConfig, apiKey: String,
        request: BridgeMonitorCreateRequest
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/monitors",
            body: try encodeBody(request), endpoint: "新建监控"
        )
    }

    /// DELETE /api/oneday-bridge/monitors/{id}
    func hubDeleteMonitor(
        config: ServerConfig, apiKey: String, id: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/monitors/\(id)",
            method: "DELETE", endpoint: "删除监控"
        )
    }

    // MARK: Webhooks（#55）

    /// GET /api/webhooks：平台开关＋订阅清单（摘要无密钥）
    func hubWebhooks(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/webhooks", endpoint: "Webhooks"
        )
    }

    /// POST /api/webhooks：建订阅（回执含一次性密钥，
    /// 调用方只在当次呈现、不落盘）
    func hubCreateWebhook(
        config: ServerConfig, apiKey: String,
        body: [String: JSONValue]
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/webhooks", method: "POST", body: body,
            endpoint: "新建 Webhook"
        )
    }

    /// DELETE /api/webhooks/{name}
    func hubDeleteWebhook(
        config: ServerConfig, apiKey: String, name: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/webhooks/\(name)", method: "DELETE",
            endpoint: "删除 Webhook"
        )
    }

    /// PUT /api/webhooks/{name}/enabled {enabled}
    func hubSetWebhookEnabled(
        config: ServerConfig, apiKey: String, name: String,
        enabled: Bool
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/webhooks/\(name)/enabled",
            method: "PUT", body: ["enabled": .bool(enabled)],
            endpoint: "Webhook 开关"
        )
    }

    /// POST /api/webhooks/enable：开启 webhook 平台
    func hubEnableWebhookPlatform(
        config: ServerConfig, apiKey: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/webhooks/enable",
            endpoint: "开启 Webhook 平台"
        )
    }

    // MARK: 预设·模型组合（桥面，#56）

    /// GET /api/oneday-bridge/meta/model-combos：组合文档
    func hubModelCombos(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/meta/model-combos",
            endpoint: "模型组合"
        )
    }

    /// PUT /api/oneday-bridge/meta/model-combos：整档写回
    /// （先读后改、原样保留不认识的字段，与 iOS 同口径）
    func hubSaveModelCombos(
        config: ServerConfig, apiKey: String,
        document: [String: JSONValue]
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "\(Self.bridgeBase)/meta/model-combos",
            method: "PUT", body: document,
            endpoint: "保存模型组合"
        )
    }

    // MARK: 环境变量（#57）

    /// GET /api/env：顶层字典（值默认遮蔽）
    func hubEnvVarsRaw(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/env", endpoint: "环境变量"
        )
    }

    /// PUT /api/env {key, value}
    func hubSetEnvVar(
        config: ServerConfig, apiKey: String, key: String,
        value: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/env", method: "PUT",
            body: ["key": .string(key),
                   "value": .string(value)],
            endpoint: "设置环境变量"
        )
    }

    /// DELETE /api/env {key}（带 body 的 DELETE）
    func hubDeleteEnvVar(
        config: ServerConfig, apiKey: String, key: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/env", method: "DELETE",
            body: ["key": .string(key)],
            endpoint: "删除环境变量"
        )
    }

    // MARK: 看板（#58，兼想法采纳 #35 建卡口）

    /// GET /api/plugins/kanban/boards → 板 slug 清单
    func hubKanbanBoards(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/plugins/kanban/boards",
            endpoint: "看板清单"
        )
    }

    /// GET /api/plugins/kanban/board?board=
    func hubKanbanBoard(
        config: ServerConfig, apiKey: String, board: String
    ) async throws -> KanbanBoardSnapshot {
        try await hubRequest(
            config: config, apiKey: apiKey,
            path: "/api/plugins/kanban/board",
            query: [URLQueryItem(name: "board", value: board)],
            endpoint: "看板"
        )
    }

    /// POST /api/plugins/kanban/tasks?board=：建卡（初始 ready）
    func hubKanbanCreateTask(
        config: ServerConfig, apiKey: String, board: String,
        title: String, body: String, idempotencyKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/plugins/kanban/tasks", method: "POST",
            query: [URLQueryItem(name: "board", value: board)],
            body: [
                "title": .string(title),
                "body": .string(body),
                "idempotency_key": .string(idempotencyKey),
            ],
            endpoint: "看板建卡"
        )
    }

    /// PATCH /api/plugins/kanban/tasks/{id}?board= {status}
    func hubKanbanPatchTaskStatus(
        config: ServerConfig, apiKey: String, board: String,
        id: String, status: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/plugins/kanban/tasks/\(id)",
            method: "PATCH",
            query: [URLQueryItem(name: "board", value: board)],
            body: ["status": .string(status)],
            endpoint: "看板改状态"
        )
    }

    /// DELETE /api/plugins/kanban/tasks/{id}?board=
    func hubKanbanDeleteTask(
        config: ServerConfig, apiKey: String, board: String,
        id: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/plugins/kanban/tasks/\(id)",
            method: "DELETE",
            query: [URLQueryItem(name: "board", value: board)],
            endpoint: "看板删卡"
        )
    }

    /// POST /api/plugins/kanban/dispatch?board=：催派
    func hubKanbanDispatch(
        config: ServerConfig, apiKey: String, board: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/plugins/kanban/dispatch",
            query: [URLQueryItem(name: "board", value: board)],
            endpoint: "看板催派"
        )
    }

    // MARK: 网关与模型（#59/#63）

    /// POST /api/gateway/start|stop|restart
    func hubGatewayAction(
        config: ServerConfig, apiKey: String, action: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/gateway/\(action)",
            endpoint: "网关动作"
        )
    }

    /// GET /api/model/options：模型 id 宽容提取源
    func hubModelOptionsRaw(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/model/options", endpoint: "模型选项"
        )
    }

    /// POST /api/model/set {model}：设主模型
    func hubSetMainModel(
        config: ServerConfig, apiKey: String, model: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/model/set",
            body: ["model": .string(model)],
            endpoint: "设置主模型"
        )
    }

    /// GET /api/model/auxiliary：辅助模型配置
    func hubAuxiliaryModels(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/model/auxiliary", endpoint: "辅助模型"
        )
    }

    /// GET /api/model/moa：MoA 配置
    func hubMoaConfig(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/model/moa", endpoint: "MoA 配置"
        )
    }

    // MARK: 配对管理（#62，cookie 面）

    /// GET /api/pairing：待批＋已配对清单（面板 cookie
    /// 随共享 URLSession 自动带上，与 iOS 同路）
    func hubPairingList(
        config: ServerConfig, apiKey: String
    ) async throws -> JSONValue {
        try await hubJSON(
            config: config, apiKey: apiKey,
            path: "/api/pairing", endpoint: "配对清单"
        )
    }

    /// POST /api/pairing/approve {platform, request_id}
    func hubPairingApprove(
        config: ServerConfig, apiKey: String, platform: String,
        requestID: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/pairing/approve",
            body: ["platform": .string(platform),
                   "request_id": .string(requestID)],
            endpoint: "批准配对"
        )
    }

    /// POST /api/pairing/revoke {platform, user_id}
    func hubPairingRevoke(
        config: ServerConfig, apiKey: String, platform: String,
        userID: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/pairing/revoke",
            body: ["platform": .string(platform),
                   "user_id": .string(userID)],
            endpoint: "撤销配对"
        )
    }

    /// POST /api/pairing/clear-pending：清空待批
    func hubPairingClearPending(
        config: ServerConfig, apiKey: String
    ) async throws {
        try await hubFire(
            config: config, apiKey: apiKey,
            path: "/api/pairing/clear-pending",
            endpoint: "清空待批配对"
        )
    }

    // MARK: 用量（#64）

    /// GET /api/analytics/usage?days=
    func hubUsageAnalytics(
        config: ServerConfig, apiKey: String, days: Int = 30
    ) async throws -> UsageAnalytics {
        try await hubRequest(
            config: config, apiKey: apiKey,
            path: "/api/analytics/usage",
            query: [URLQueryItem(
                name: "days", value: String(days)
            )],
            endpoint: "用量统计"
        )
    }

    /// GET /api/analytics/models?days=
    func hubModelAnalytics(
        config: ServerConfig, apiKey: String, days: Int = 30
    ) async throws -> ModelAnalytics {
        try await hubRequest(
            config: config, apiKey: apiKey,
            path: "/api/analytics/models",
            query: [URLQueryItem(
                name: "days", value: String(days)
            )],
            endpoint: "模型用量"
        )
    }
}
