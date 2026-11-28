import Foundation
import OneDayCore

// MARK: - HermesClient 反应、工作区文件与 Kanban 域（#37 模块化拆分）

extension HermesClient {
    // MARK: - 消息反应（台账 187）

    func listApprovals(
        config: ServerConfig, apiKey: String
    ) async throws -> ApprovalsListResponse {
        try await bearerGetJSON(
            config: config, apiKey: apiKey, path: "/v1/approvals",
            endpoint: L10n.string("待批接口")
        )
    }

    func routeProbe(
        config: ServerConfig, apiKey: String?, path: String
    ) async -> RouteProbeResult? {
        var request = URLRequest(url: config.endpoint(path))
        request.timeoutInterval = 15
        if let apiKey {
            request.setValue(
                "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
            )
        }
        // 探针永不抛错：传输失败回 nil（未探），HTTP
        // 状态与错误码原样带回供 Core 判据分流
        guard let (data, http) = try? await dataRequest(request)
        else { return nil }
        return RouteProbeResult(
            status: http.statusCode,
            errorCode: Self.gatewayErrorCode(from: data)
        )
    }

    func setReaction(
        config: ServerConfig, apiKey: String,
        sessionID: String, rowID: Int, emoji: String
    ) async throws -> ReactionUpdate {
        var request = URLRequest(
            url: config.endpoint(
                "/v1/reactions/\(sessionID)/\(rowID)"
            )
        )
        request.httpMethod = "PUT"
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try encoder.encode(["emoji": emoji])
        return try await reactionUpdate(request)
    }

    func clearReaction(
        config: ServerConfig, apiKey: String,
        sessionID: String, rowID: Int
    ) async throws -> ReactionUpdate {
        var request = URLRequest(
            url: config.endpoint(
                "/v1/reactions/\(sessionID)/\(rowID)"
            )
        )
        request.httpMethod = "DELETE"
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        return try await reactionUpdate(request)
    }

    /// 反应两口的回执收口：200 系解 ReactionUpdate；
    /// 网关错误码 message_not_found → reactionTarget-
    /// Gone（回滚＋人话在调用方）；401/403 → 密钥被拒
    private func reactionUpdate(
        _ request: URLRequest
    ) async throws -> ReactionUpdate {
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            if Self.gatewayErrorCode(from: data)
                == "message_not_found" {
                throw HermesError.reactionTargetGone
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("反应"),
                status: http.statusCode
            )
        }
        do {
            return try decoder.decode(ReactionUpdate.self, from: data)
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("反应")
            )
        }
    }

    // MARK: - 工作区文件与系统（0.2.1）

    func files(config: ServerConfig, path: String?) async throws -> FilesListing {
        var query: [URLQueryItem] = []
        if let path, !path.isEmpty {
            query.append(URLQueryItem(name: "path", value: path))
        }
        return try await getJSON(
            config: config, path: "/api/files", endpoint: L10n.string("文件列表"), query: query
        )
    }

    func deleteFile(config: ServerConfig, path: String, recursive: Bool) async throws {
        try await sendJSON(
            config: config, path: "/api/files", method: "DELETE",
            endpoint: L10n.string("删除文件"),
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
            throw HermesError.unexpectedStatus(endpoint: L10n.string("文件下载"), status: http.statusCode)
        }
        return data
    }

    /// §452 实现：照 §237 P7 上传先例——每请求新建会
    /// 话挂本请求的 delegate 取字节回调，cookie 走
    /// .shared 同一存储、鉴权口径与 dataRequest 一
    /// 致，用完即 invalidate。Task 取消传导取消底层
    /// 任务，URLError.cancelled 归一 Cancellation-
    /// Error（调用方按用户取消收尾、不挂失败标记）
    func fileDataWithProgress(
        config: ServerConfig, path: String,
        onProgress: @escaping @Sendable (_ received: Int64, _ expected: Int64) -> Void
    ) async throws -> Data {
        let request = URLRequest(
            url: url(
                config: config, path: "/api/files/download",
                query: [URLQueryItem(name: "path", value: path)]
            )
        )
        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.waitsForConnectivity = true
        let downloadSession = URLSession(
            configuration: configuration,
            delegate: delegate, delegateQueue: nil
        )
        defer { downloadSession.finishTasksAndInvalidate() }
        let data: Data
        let http: HTTPURLResponse
        do {
            let (rawData, response) = try await downloadSession.data(
                for: request, delegate: delegate
            )
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HermesError.unreachable(L10n.string("无响应"))
            }
            data = rawData
            http = httpResponse
        } catch let urlError as URLError
        where urlError.code == .cancelled {
            throw CancellationError()
        } catch let error as HermesError {
            throw error
        } catch {
            throw mapNetworkError(error)
        }
        guard http.statusCode == 200 else {
            throw HermesError.unexpectedStatus(endpoint: L10n.string("文件下载"), status: http.statusCode)
        }
        onTransportSuccess?()
        return data
    }

    func uploadFile(
        config: ServerConfig, path: String, dataURL: String, overwrite: Bool
    ) async throws {
        // data_url 是 base64 JSON 体（25MB 原始上限膨胀后约
        // 34MB），超时给 180 秒；服务端回执不解码，落定以
        // 调用方回读列表对账为准（sendJSON 既有口径）
        try await sendJSON(
            config: config, path: "/api/files/upload", method: "POST",
            endpoint: L10n.string("文件上传"),
            body: [
                "path": .string(path),
                "data_url": .string(dataURL),
                "overwrite": .bool(overwrite),
            ],
            timeout: 180
        )
    }

    func uploadAttachment(
        config: ServerConfig, path: String, dataURL: String
    ) async throws -> ManagedFileUploadReceipt {
        // 与 uploadFile 同端点同超时（data_url 体积约
        // 原始 1.37 倍），差异只在解码回执取 entry
        // .path；回执不合格（无绝对路径）在调用方判
        // 失败有声，不在此处吞
        var request = URLRequest(
            url: config.endpoint("/api/files/upload")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        // §410：JSON 体编码下主线程——旧链在调用方
        // actor 上下文同步成形整份体
        request.httpBody = try await Self.encodeUploadBodyDetached(
            path: path, dataURL: dataURL
        )
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("文件上传"), status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                ManagedFileUploadReceipt.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(endpoint: L10n.string("文件上传"))
        }
    }

    /// §237 P7 实现：同一请求改走带 delegate 的
    /// upload task——didSendBodyData 的已发送字节是
    /// 唯一进度源（此前 data(for:) 无字节回调、界面
    /// 只能假菊花）；每请求新建会话以挂本请求的
    /// delegate，cookie 仍走 .shared 同一存储，鉴权
    /// 口径与 dataRequest 一致；用完即 invalidate。
    /// Swift Task 取消会传导取消底层 upload task，
    /// URLError.cancelled 在此归一为 Cancellation-
    /// Error，调用方按「用户停止」语义收尾、不挂
    /// 失败标记。
    func uploadAttachment(
        config: ServerConfig, path: String, dataURL: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ManagedFileUploadReceipt {
        var request = URLRequest(
            url: config.endpoint("/api/files/upload")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let body: Data
        do {
            // §410：同上，编码移独立任务
            body = try await Self.encodeUploadBodyDetached(
                path: path, dataURL: dataURL
            )
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("文件上传")
            )
        }
        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 180
        configuration.waitsForConnectivity = true
        let uploadSession = URLSession(
            configuration: configuration,
            delegate: delegate, delegateQueue: nil
        )
        defer { uploadSession.finishTasksAndInvalidate() }
        let data: Data
        let http: HTTPURLResponse
        do {
            let (rawData, response) = try await uploadSession.upload(
                for: request, from: body
            )
            guard let httpResponse = response as? HTTPURLResponse
            else {
                throw HermesError.unreachable(L10n.string("无响应"))
            }
            data = rawData
            http = httpResponse
        } catch let error as HermesError {
            throw error
        } catch let urlError as URLError
            where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw mapNetworkError(error)
        }
        onTransportSuccess?()
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("文件上传"), status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                ManagedFileUploadReceipt.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(endpoint: L10n.string("文件上传"))
        }
    }

    /// §410 实现：请求体在后台流式拼装成临时文件再
    /// 由 upload task 直发——base64 不再整份成串、
    /// JSON 体不再整份成 Data，峰值内存从 ≈3.7× 文
    /// 件大小降到 ≈1×（源字节本身）＋分片缓冲；进
    /// 度/取消/错误口径与 dataURL 版逐项一致（同
    /// delegate 会话、同端点、同回执解码）
    func uploadAttachment(
        config: ServerConfig, path: String, fileName: String,
        data: Data,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ManagedFileUploadReceipt {
        let bodyFile = try await Self.makeUploadBodyFile(
            path: path, fileName: fileName, data: data
        )
        defer {
            try? FileManager.default.removeItem(at: bodyFile)
        }
        var request = URLRequest(
            url: config.endpoint("/api/files/upload")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 180
        configuration.waitsForConnectivity = true
        let uploadSession = URLSession(
            configuration: configuration,
            delegate: delegate, delegateQueue: nil
        )
        defer { uploadSession.finishTasksAndInvalidate() }
        let responseData: Data
        let http: HTTPURLResponse
        do {
            let (rawData, response) = try await uploadSession.upload(
                for: request, fromFile: bodyFile
            )
            guard let httpResponse = response as? HTTPURLResponse
            else {
                throw HermesError.unreachable(L10n.string("无响应"))
            }
            responseData = rawData
            http = httpResponse
        } catch let error as HermesError {
            throw error
        } catch let urlError as URLError
            where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw mapNetworkError(error)
        }
        onTransportSuccess?()
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("文件上传"), status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                ManagedFileUploadReceipt.self, from: responseData
            )
        } catch {
            throw HermesError.decodingFailed(endpoint: L10n.string("文件上传"))
        }
    }

    /// §410：请求体拼装的离主线程入口（钉测与生产共
    /// 用）：独立任务里流式写体，主线只等文件落点
    static func makeUploadBodyFile(
        path: String, fileName: String, data: Data
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try UploadBodyFile.make(
                path: path, fileName: fileName, data: data
            )
        }.value
    }

    /// §410：dataURL 版的 JSON 体离主线程编码——独立
    /// 任务里以新编码器（与共享 encoder 同为默认配
    /// 置）成形，不与共享实例跨线并发
    private static func encodeUploadBodyDetached(
        path: String, dataURL: String
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try JSONEncoder().encode([
                "path": JSONValue.string(path),
                "data_url": JSONValue.string(dataURL),
                "overwrite": JSONValue.bool(true),
            ])
        }.value
    }

    func makeDirectory(config: ServerConfig, path: String) async throws {
        try await sendJSON(
            config: config, path: "/api/files/mkdir", method: "POST",
            endpoint: L10n.string("新建文件夹"),
            body: ["path": .string(path)]
        )
    }

    func systemStats(config: ServerConfig) async throws -> SystemStats {
        try await getJSON(config: config, path: "/api/system/stats", endpoint: L10n.string("系统状态"))
    }
}

/// §237 P7：upload task 的字节进度转发——只把
/// URLSession 实报的已发送/预计总字节折成比例向
/// 外送，不缓存、不估算；预计总量未知（≤0）时报
/// 0，由聚合层峰值口径兜住不后退。
private final class UploadProgressDelegate: NSObject,
    URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else {
            onProgress(0)
            return
        }
        onProgress(
            min(
                1,
                max(
                    0,
                    Double(totalBytesSent)
                        / Double(totalBytesExpectedToSend)
                )
            )
        )
    }
}

/// §452：download 字节进度转发——只把 URLSession
/// 实报的已收/预计字节向外送，不缓存、不估算。回
/// 调在会话队列线程投递：闭包 nonisolated 语义、只
/// 碰本盒的锁内计数与 Sendable 回调（回调隔离铁律）
private final class DownloadProgressDelegate: NSObject,
    URLSessionDataDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private let lock = NSLock()
    private var received: Int64 = 0
    private var expected: Int64 = -1

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        expected = response.expectedContentLength
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        received += Int64(data.count)
        let snapshot = (received, expected)
        lock.unlock()
        onProgress(snapshot.0, snapshot.1)
    }
}

// MARK: - Kanban（P3 任务薄适配）
//
// 走 9119 dashboard 插件面 /api/plugins/kanban，与其
// 他 /api/* 同一条会话 cookie 通道（performAdmin 的
// 401 重登兜底同样适用）。全部请求带 ?board= 指名
// 专属板（spike 数据隔离口径）；写动作的回执只作参
// 考，生效与否由 KanbanStore 回读确认，不乐观假成功。

extension HermesClient {
    private var kanbanBase: String { "/api/plugins/kanban" }

    private func kanbanQuery(board: String) -> [URLQueryItem] {
        [URLQueryItem(name: "board", value: board)]
    }

    /// kanban 写请求（带 query 版 sendJSON：既有助手
    /// 不支持 query 参数，插件面每条都要带 board）
    private func kanbanSend(
        config: ServerConfig, path: String, method: String, endpoint: String,
        query: [URLQueryItem] = [], body: [String: JSONValue]? = nil
    ) async throws {
        var request = URLRequest(
            url: url(config: config, path: path, query: query)
        )
        request.httpMethod = method
        if let body {
            request.setValue(
                "application/json", forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = try encoder.encode(body)
        }
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.fromHTTPResponse(
                endpoint: endpoint,
                status: http.statusCode,
                data: data,
                retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
    }

    /// kanban 写请求并解码回执（建卡/催派用）
    private func kanbanSendDecoding<T: Decodable>(
        config: ServerConfig, path: String, method: String, endpoint: String,
        query: [URLQueryItem] = [], body: [String: JSONValue]? = nil
    ) async throws -> T {
        var request = URLRequest(
            url: url(config: config, path: path, query: query)
        )
        request.httpMethod = method
        if let body {
            request.setValue(
                "application/json", forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = try encoder.encode(body)
        }
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

    func kanbanWorkflow(config: ServerConfig) async throws -> KanbanWorkflow {
        try await getJSON(
            config: config, path: "\(kanbanBase)/workflow",
            endpoint: L10n.string("任务系统探针")
        )
    }

    func kanbanBoards(config: ServerConfig) async throws -> [String] {
        let value: JSONValue = try await getJSON(
            config: config, path: "\(kanbanBase)/boards",
            endpoint: L10n.string("任务板清单")
        )
        return KanbanBoardList.slugs(from: value)
    }

    func kanbanBoard(
        config: ServerConfig, board: String
    ) async throws -> KanbanBoardSnapshot {
        try await getJSON(
            config: config, path: "\(kanbanBase)/board",
            endpoint: L10n.string("任务板"), query: kanbanQuery(board: board)
        )
    }

    func kanbanTaskDetail(
        config: ServerConfig, board: String, id: String
    ) async throws -> KanbanTaskDetail {
        try await getJSON(
            config: config, path: "\(kanbanBase)/tasks/\(id)",
            endpoint: L10n.string("任务详情"), query: kanbanQuery(board: board)
        )
    }

    func kanbanCreateTask(
        config: ServerConfig, board: String, title: String, body: String,
        idempotencyKey: String
    ) async throws -> KanbanTask {
        var payload: [String: JSONValue] = [
            "title": .string(title),
            "assignee": .string(KanbanContract.defaultAssignee),
            "idempotency_key": .string(idempotencyKey),
        ]
        if !body.isEmpty {
            payload["body"] = .string(body)
        }
        return try await kanbanSendDecoding(
            config: config, path: "\(kanbanBase)/tasks", method: "POST",
            endpoint: L10n.string("任务创建"), query: kanbanQuery(board: board),
            body: payload
        )
    }

    func kanbanDispatch(
        config: ServerConfig, board: String
    ) async throws -> KanbanDispatchReceipt {
        try await kanbanSendDecoding(
            config: config, path: "\(kanbanBase)/dispatch", method: "POST",
            endpoint: L10n.string("任务派发"), query: kanbanQuery(board: board)
        )
    }

    func kanbanPatchTaskStatus(
        config: ServerConfig, board: String, id: String, status: String
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/tasks/\(id)",
            method: "PATCH", endpoint: L10n.string("任务状态更新"),
            query: kanbanQuery(board: board),
            body: ["status": .string(status)]
        )
    }

    func kanbanAssignTask(
        config: ServerConfig, board: String, id: String, assignee: String
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/tasks/\(id)",
            method: "PATCH", endpoint: L10n.string("任务指派"),
            query: kanbanQuery(board: board),
            body: ["assignee": .string(assignee)]
        )
    }

    func kanbanDeleteTask(
        config: ServerConfig, board: String, id: String
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/tasks/\(id)",
            method: "DELETE", endpoint: L10n.string("任务删除"),
            query: kanbanQuery(board: board)
        )
    }

    func kanbanComment(
        config: ServerConfig, board: String, id: String, body: String
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/tasks/\(id)/comments",
            method: "POST", endpoint: L10n.string("任务答题"),
            query: kanbanQuery(board: board),
            body: [
                "body": .string(body),
                "author": .string(KanbanContract.answerAuthor),
            ]
        )
    }

    func kanbanReclaimTask(
        config: ServerConfig, board: String, id: String
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/tasks/\(id)/reclaim",
            method: "POST", endpoint: L10n.string("任务急停"),
            query: kanbanQuery(board: board),
            body: ["reason": .string("App 停止")]
        )
    }

    func kanbanDecompose(
        config: ServerConfig, board: String, id: String
    ) async throws -> KanbanDecomposeReceipt {
        try await kanbanSendDecoding(
            config: config, path: "\(kanbanBase)/tasks/\(id)/decompose",
            method: "POST", endpoint: L10n.string("拆解任务"),
            query: kanbanQuery(board: board),
            body: [:]
        )
    }

    func kanbanTerminateRun(
        config: ServerConfig, board: String, runID: Int
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/runs/\(runID)/terminate",
            method: "POST", endpoint: L10n.string("运行终止"),
            query: kanbanQuery(board: board),
            body: ["reason": .string("App 停止")]
        )
    }
}

/// rewind 的定性失败（DESIGN §352）：分类器耗尽/目标
/// 不合法的用户可达结局——与 HermesError 分开，是因
/// 为调用方的回滚文案按此三类分流（太早了/对话有新
/// 变化/busy 已由 HermesError.sessionBusy 承接，不
/// 在此列）。busy 耗尽抛 HermesError.sessionBusy、
/// 其余未定性失败抛 HermesError.unexpectedStatus，
/// 均不在本枚举
