import Foundation
import OneDayCore

/// 桥客户端基座（C-10 收敛，DESIGN 审计 overcomplexity-
/// audit-20261114 C-10）：定位先说清——**API 直连优先、
/// 桥是无奈兜底**；本基座不把桥做强，只把「剩余桥调用」
/// 重复了十几遍的连接/单钥注入/请求管线/安全错误文案收
/// 成一处。各桥在基座之上只留：路径前缀、自家 DTO、自
/// 家状态口径（checkStatus 闭包或本地小开关）。
///
/// 基座统一的四件事：
/// 1. 会话：URLSessionConfiguration（超时/waitsFor-
///    Connectivity 按桥传入），另有 makeSession 供双
///    会话分档（盒桥读/写、设备长轮询）自取；
/// 2. 单钥：Bearer 只从 BridgeCredential 统一读（0.33.1
///    定版：聊天同一份 Hermes 登录密钥，桥钥是服务端内
///    部的事）；读不到钥一律抛各桥自家 noKey、不发请求；
/// 3. 管线：makeRequest（前缀拼装＋Bearer）→ data（传
///    输失败收敛成 failed 人话：「%@无响应」/「%@网络不
///    可达」）→ decode（格式失败收敛）；状态码口径**不**
///    在基座写死——各桥冻结口径不同（404 分流/409 冲
///    突/透传人话），由各桥以闭包或本地 check 给出，
///    基座只提供两份已同口径的共享实现（checkStatus＝
///    oneday 系、checkPassthroughStatus＝透传系）与
///    serverMessage（{"error": 人话} 提取）；
/// 4. 取消语义：默认与各桥旧口径一致（收敛成 failed），
///    设备长轮询这类「取消即停」的通道显式传
///    propagateCancellation（URLError.cancelled 一并
///    归一成 CancellationError 上抛）。
final class BridgeClientBase<Failure: Error>: @unchecked Sendable {
    /// 桥路径前缀（如 "/api/oneday-bridge"）
    let pathPrefix: String
    /// 主会话（分档桥的第二会话经 makeSession 自建、
    /// 调用时以 using: 传入）
    let session: URLSession
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    private let noKeyError: Failure
    private let failedError: (String) -> Failure

    init(
        pathPrefix: String, timeout: TimeInterval,
        waitsForConnectivity: Bool = false,
        noKey: Failure, failed: @escaping (String) -> Failure
    ) {
        self.pathPrefix = pathPrefix
        self.session = Self.makeSession(
            timeout: timeout, waitsForConnectivity: waitsForConnectivity
        )
        self.noKeyError = noKey
        self.failedError = failed
    }

    static func makeSession(
        timeout: TimeInterval, waitsForConnectivity: Bool = false
    ) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = waitsForConnectivity
        return URLSession(configuration: configuration)
    }

    // MARK: - 单钥

    var bridgeKey: String? {
        BridgeCredential.read()
    }

    /// 取钥：读不到/为空一律 noKey、不发请求（各桥冻结
    /// 口径：不冒充已接通）
    func requireKey() throws -> String {
        guard let key = bridgeKey, !key.isEmpty else {
            throw noKeyError
        }
        return key
    }

    /// 各桥自家 failed 构造（本地 check/开关拼文案用）
    func fail(_ message: String) -> Failure {
        failedError(message)
    }

    var noKey: Failure { noKeyError }

    // MARK: - 请求组装

    /// 桥内请求：pathPrefix＋path
    func makeRequest(
        config: ServerConfig, path: String, method: String,
        cachePolicy: URLRequest.CachePolicy? = nil
    ) throws -> URLRequest {
        try makeRequest(
            config: config, fullPath: pathPrefix + path,
            method: method, cachePolicy: cachePolicy
        )
    }

    /// 服务器根下绝对路径请求（跨面调用：伴生探测
    /// /api/companion/info 等）
    func makeRequest(
        config: ServerConfig, fullPath: String, method: String,
        cachePolicy: URLRequest.CachePolicy? = nil
    ) throws -> URLRequest {
        let key = try requireKey()
        var request = URLRequest(url: config.endpoint(fullPath))
        request.httpMethod = method
        request.setValue(
            "Bearer \(key)", forHTTPHeaderField: "Authorization"
        )
        if let cachePolicy {
            request.cachePolicy = cachePolicy
        }
        return request
    }

    // MARK: - 传输

    /// 中性传输错误（performRaw 专用：调用方自管全部
    /// 失败呈现时用，如网关渠道的非抛错读面）
    enum TransportError: Error {
        case notHTTPResponse
        case underlying(Error)
    }

    /// 原始传输：不做任何文案收敛，失败原样分型上抛
    func performRaw(
        _ request: URLRequest, using session: URLSession? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await (session ?? self.session)
                .data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TransportError.notHTTPResponse
            }
            return (data, http)
        } catch let error as TransportError {
            throw error
        } catch {
            throw TransportError.underlying(error)
        }
    }

    /// 标准传输：无响应/网络不可达收敛成 failed 人话；
    /// 自家 Failure 原样透传；取消按 propagateCancell-
    /// ation 分流（见文件头第 4 条）
    func data(
        for request: URLRequest, endpoint: String,
        using session: URLSession? = nil,
        propagateCancellation: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await (session ?? self.session)
                .data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw failedError(L10n.format("%@无响应", endpoint))
            }
            return (data, http)
        } catch let error as Failure {
            throw error
        } catch is CancellationError {
            if propagateCancellation { throw CancellationError() }
            throw failedError(L10n.format("%@网络不可达", endpoint))
        } catch let error as URLError where error.code == .cancelled {
            if propagateCancellation { throw CancellationError() }
            throw failedError(L10n.format("%@网络不可达", endpoint))
        } catch {
            throw failedError(L10n.format("%@网络不可达", endpoint))
        }
    }

    /// 一次完整调用（组装→可选 JSON 体→传输），状态与
    /// 解码留调用方：供请求体走 JSONSerialization、状
    /// 态开关带分型的桥面（频道/设备/write-gate 写口等）
    func perform(
        config: ServerConfig, path: String, method: String,
        bodyData: Data?, endpoint: String,
        using session: URLSession? = nil,
        propagateCancellation: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        var request = try makeRequest(
            config: config, path: path, method: method
        )
        if let bodyData {
            request.httpBody = bodyData
            request.setValue(
                "application/json", forHTTPHeaderField: "Content-Type"
            )
        }
        return try await data(
            for: request, endpoint: endpoint, using: session,
            propagateCancellation: propagateCancellation
        )
    }

    /// serverMessage 的实例转发（各桥本地 check 拼装用）
    func serverMessage(_ data: Data) -> String? {
        Self.serverMessage(data)
    }

    // MARK: - 解码

    /// 解码或抛调用方给定的格式失败（各桥文案自带，
    /// 基座不猜）
    func decode<T: Decodable>(
        _ data: Data, orThrow failure: Failure
    ) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw failure
        }
    }

    /// 桥错误体提取（冻结口径）：失败响应 {"error": 人话}
    static func serverMessage(_ data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(
            BridgeServerErrorBody.self, from: data
        ), let message = body.error, !message.isEmpty else {
            return nil
        }
        return message
    }

    // MARK: - 常用动词（状态口径由 checkStatus 闭包给出）

    /// GET 解码：状态闭包通过后解码，格式失败文案
    /// 「%@返回格式无法识别」（各桥 GET 统一口径）
    func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        checkStatus: (HTTPURLResponse, Data) throws -> Void
    ) async throws -> T {
        let request = try makeRequest(
            config: config, path: path, method: "GET"
        )
        let (data, http) = try await data(for: request, endpoint: endpoint)
        try checkStatus(http, data)
        return try decode(
            data,
            orThrow: failedError(L10n.format("%@返回格式无法识别", endpoint))
        )
    }

    /// 带 Encodable 体的调用：组装失败文案「%@请求组装
    /// 失败」、解码失败文案「%@回执格式无法识别」（各桥
    /// 写口统一口径；文案不同的个别口在调用方自组装）
    func send<Body: Encodable, T: Decodable>(
        config: ServerConfig, path: String, method: String,
        body: Body, endpoint: String,
        using session: URLSession? = nil,
        checkStatus: (HTTPURLResponse, Data) throws -> Void
    ) async throws -> T {
        var request = try makeRequest(
            config: config, path: path, method: method
        )
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw failedError(L10n.format("%@请求组装失败", endpoint))
        }
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await data(
            for: request, endpoint: endpoint, using: session
        )
        try checkStatus(http, data)
        return try decode(
            data,
            orThrow: failedError(L10n.format("%@回执格式无法识别", endpoint))
        )
    }

    /// 无体调用解码（DELETE/动作 POST）：解码失败文案
    /// 同 send 的回执口径
    func sendEmpty<T: Decodable>(
        config: ServerConfig, path: String, method: String,
        endpoint: String,
        checkStatus: (HTTPURLResponse, Data) throws -> Void
    ) async throws -> T {
        let request = try makeRequest(
            config: config, path: path, method: method
        )
        let (data, http) = try await data(for: request, endpoint: endpoint)
        try checkStatus(http, data)
        return try decode(
            data,
            orThrow: failedError(L10n.format("%@回执格式无法识别", endpoint))
        )
    }

    // MARK: - 共享状态口径（已同口径的两份，桥按系选用）

    /// 透传系（设备桥）：2xx 通过；401 unauthorized；
    /// 其余优先透服务端 {"error": 人话}、解不出回落
    /// 「%@返回 %@」
    func checkPassthroughStatus(
        _ http: HTTPURLResponse, data: Data, endpoint: String,
        unauthorized: Failure
    ) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw unauthorized
        default:
            if let message = Self.serverMessage(data) {
                throw failedError(message)
            }
            throw failedError(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
    }
}

extension BridgeClientBase where Failure == OneDayBridgeError {
    /// oneday 系状态口径（oneday-bridge/台账/front 共
    /// 用）：2xx 通过；401 钥匙被拒；404 按端点分流
    /// （集合＝桥未开通 bridgeMissing、条目＝记录已不
    /// 在 recordGone）；其余优先透服务端人话
    func checkStatus(
        _ http: HTTPURLResponse, data: Data,
        endpoint: String, collection: Bool
    ) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw OneDayBridgeError.unauthorized
        case 404:
            throw collection
                ? OneDayBridgeError.bridgeMissing
                : OneDayBridgeError.recordGone
        default:
            if let message = Self.serverMessage(data) {
                // §233 安全门（件八）：服务端文案过
                // ServerErrorText 门才许进 .failed 上
                // 屏；不过门落通用人话，原文只进诊断
                // 留痕——不许服务端给什么显什么
                // （组版收口：轻动作包原改 OneDay 桥
                // 本地 checkStatus，桥收敛后该口径已
                // 沉到本共用实现，故门落此处一份）
                if let safe = ServerErrorText.userSafe(message) {
                    throw OneDayBridgeError.failed(safe)
                }
                ChatDiagTrace.record(
                    "桥错误原文未过安全门 [\(endpoint) \(http.statusCode)] \(message)"
                )
                throw OneDayBridgeError.failed(
                    L10n.format(
                        "%@返回了无法识别的错误，请稍后再试。",
                        endpoint
                    )
                )
            }
            throw OneDayBridgeError.failed(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
    }
}


/// 桥错误体（文件级：泛型类的 static 方法内不许嵌套
/// 类型，故收敛到此处一份，各桥共用）
private struct BridgeServerErrorBody: Decodable {
    let error: String?
}
