import Foundation
import OneDayCore

/// 伴生 front 客户端（0.37.0）：连接记录与网关渠道两
/// 面都挂在服务器根 /api/companion/*（front 8650），
/// 鉴权走 App 既有单钥 Bearer（BridgeCredential，与
/// LedgerBridgeClient 的伴生探测同通道；front 对 App
/// 通道免 CSRF、写口与面板同权）。连接凭据只出不进：
/// 本客户端只有提交口、没有任何读回凭据值的接口。
final class CompanionFrontClient: @unchecked Sendable {
    /// C-10 收敛：连接/单钥/管线/文案全走统一基座，
    /// 本类只留路径、DTO 与 front 状态口径
    private let base = BridgeClientBase<OneDayBridgeError>(
        pathPrefix: "/api/companion", timeout: 20,
        noKey: .noKey, failed: OneDayBridgeError.failed
    )

    private var decoder: JSONDecoder { base.decoder }

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
        guard let stored = base.bridgeKey, !stored.isEmpty else {
            return .failed(L10n.string("还没有登录凭据，读不到网关渠道。"))
        }
        _ = stored
        var request: URLRequest
        do {
            request = try base.makeRequest(
                config: config,
                fullPath: "/api/companion/gateway-channels",
                method: "GET"
            )
        } catch {
            return .failed(L10n.string("网关渠道读取失败，请稍后再试。"))
        }
        request.timeoutInterval = 10
        do {
            let (data, http) = try await base.performRaw(request)
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

    // MARK: - 请求底座（基座代行，本类只给状态口径）

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String
    ) async throws -> T {
        try await base.get(
            config: config, path: path, endpoint: endpoint
        ) { http, data in
            try self.checkStatus(http, data: data, endpoint: endpoint)
        }
    }

    private func post<T: Decodable>(
        config: ServerConfig, path: String,
        body: [String: JSONValue], endpoint: String
    ) async throws -> T {
        try await base.send(
            config: config, path: path, method: "POST",
            body: body, endpoint: endpoint
        ) { http, data in
            try self.checkStatus(http, data: data, endpoint: endpoint)
        }
    }

    /// front 状态口径：2xx 通过；401 钥匙被拒；404＝记
    /// 录已不在；其余优先透服务端人话（error 字段）
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
            if let message = base.serverMessage(data) {
                throw OneDayBridgeError.failed(message)
            }
            throw OneDayBridgeError.failed(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
    }
}
