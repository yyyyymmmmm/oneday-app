import Foundation
import OneDayCore

/// 伴生 front 客户端（0.37.0）：连接记录与网关渠道两
/// 面都挂在服务器根 /api/companion/*（front 8650），
/// 鉴权走 App 既有单钥 Bearer（BridgeCredential，与
/// LedgerBridgeClient 的伴生探测同通道；front 对 App
/// 通道免 CSRF、写口与面板同权）。连接凭据只出不进：
/// 本客户端只有提交口、没有任何读回凭据值的接口。
final class CompanionFrontClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    private var bridgeKey: String? { BridgeCredential.read() }

    // MARK: - 连接记录（云电脑配置面）

    func connections(
        config: ServerConfig
    ) async throws -> [CompanionConnection] {
        struct Response: Decodable {
            let connections: [CompanionConnection]
        }
        let response: Response = try await get(
            config: config, path: "/connections", endpoint: L10n.string("连接清单")
        )
        return response.connections
    }

    /// 创建云电脑（front 只许 cloud_computer 两类）
    @discardableResult
    func createConnection(
        config: ServerConfig, provider: String, name: String
    ) async throws -> CompanionConnection {
        struct Response: Decodable {
            let connection: CompanionConnection
        }
        let response: Response = try await post(
            config: config, path: "/connections",
            body: ConnectionPayloads.create(provider: provider, name: name),
            endpoint: L10n.string("添加电脑")
        )
        return response.connection
    }

    /// 提交/更换凭据：front 内部验活＋失败回滚，回执
    /// {ok, detail, connection}——ok=false 不是 HTTP 错
    /// 误，是「验活没过、已撤回」，原样带回给状态机。
    func submitCredential(
        config: ServerConfig, id: String, body: [String: JSONValue]
    ) async throws -> (ok: Bool, detail: String, connection: CompanionConnection?) {
        let response: CredentialResponse = try await post(
            config: config, path: "/connections/\(id)/credential",
            body: body, endpoint: L10n.string("保存凭据")
        )
        return (response.ok, response.detail ?? "", response.connection)
    }

    /// 重新验活（已配置的连接）
    func verify(
        config: ServerConfig, id: String
    ) async throws -> (ok: Bool, detail: String, connection: CompanionConnection?) {
        let response: CredentialResponse = try await post(
            config: config, path: "/connections/\(id)/verify",
            body: [:], endpoint: L10n.string("测试连接")
        )
        return (response.ok, response.detail ?? "", response.connection)
    }

    /// 断开（摘凭据；厂商侧吊销由用户在厂商处办，页
    /// 面文案明示）
    func disconnect(
        config: ServerConfig, id: String
    ) async throws -> CompanionConnection? {
        let response: CredentialResponse = try await post(
            config: config, path: "/connections/\(id)/disconnect",
            body: [:], endpoint: L10n.string("断开连接")
        )
        return response.connection
    }

    private struct CredentialResponse: Decodable {
        let ok: Bool
        let detail: String?
        let connection: CompanionConnection?
    }

    // MARK: - 网关渠道（只读，管理面）

    /// GET /api/companion/gateway-channels：2026-11-11
    /// 实测该面未开通（404）——返回 .faceMissing 与读
    /// 失败分开，UI 如实露面（GatewayChannelsFace 口径）
    func gatewayChannels(
        config: ServerConfig
    ) async -> GatewayChannelsFace {
        guard let key = bridgeKey, !key.isEmpty else {
            return .failed(L10n.string("还没有登录凭据，读不到网关渠道。"))
        }
        var request = URLRequest(
            url: config.endpoint("/api/companion/gateway-channels")
        )
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(key)", forHTTPHeaderField: "Authorization"
        )
        request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(L10n.string("网关渠道读取失败，请稍后再试。"))
            }
            switch http.statusCode {
            case 200:
                if let decoded = try? decoder.decode(
                    GatewayChannelsResponse.self, from: data
                ) {
                    return .ready(decoded.channels)
                }
                return .failed(L10n.string("网关渠道的返回格式无法识别。"))
            case 404:
                return .faceMissing
            case 401:
                return .failed(L10n.string("登录凭据被拒绝，读不到网关渠道。"))
            default:
                return .failed(L10n.format("网关渠道读取失败（%@）。", String(http.statusCode)))
            }
        } catch {
            return .failed(L10n.string("网关渠道读取失败，请稍后再试。"))
        }
    }

    // MARK: - 请求底座（与 LedgerBridgeClient 同口径）

    private func makeRequest(
        config: ServerConfig, path: String, method: String
    ) throws -> URLRequest {
        guard let key = bridgeKey, !key.isEmpty else {
            throw OneDayBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/companion" + path)
        )
        request.httpMethod = method
        request.setValue(
            "Bearer \(key)", forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String
    ) async throws -> T {
        let request = try makeRequest(config: config, path: path, method: "GET")
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@返回格式无法识别", endpoint))
        }
    }

    private func post<T: Decodable>(
        config: ServerConfig, path: String,
        body: [String: JSONValue], endpoint: String
    ) async throws -> T {
        var request = try makeRequest(config: config, path: path, method: "POST")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@请求组装失败", endpoint))
        }
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@回执格式无法识别", endpoint))
        }
    }

    private struct BridgeErrorBody: Decodable {
        let ok: Bool?
        let error: String?
    }

    private func checkStatus(
        _ http: HTTPURLResponse, data: Data, endpoint: String
    ) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw OneDayBridgeError.unauthorized
        case 404:
            throw OneDayBridgeError.recordGone
        default:
            if let body = try? decoder.decode(
                BridgeErrorBody.self, from: data
            ), let message = body.error, !message.isEmpty {
                // §232 安全门（件八同族第四处）：与
                // OneDayBridgeClient 同口径——服务端
                // 文案过门才许进 .failed 上屏，不过门
                // 落通用人话、原文只进诊断留痕
                if let safe = ServerErrorText.userSafe(message) {
                    throw OneDayBridgeError.failed(safe)
                }
                ChatDiagTrace.record(
                    "伴生 front 错误原文未过安全门 [\(endpoint) \(http.statusCode)] \(message)"
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

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OneDayBridgeError.failed(L10n.format("%@无响应", endpoint))
            }
            return (data, http)
        } catch let error as OneDayBridgeError {
            throw error
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@网络不可达", endpoint))
        }
    }
}
