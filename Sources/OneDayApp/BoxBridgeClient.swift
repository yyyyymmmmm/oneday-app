import Foundation
import OneDayCore

/// 盒桥错误：与总览桥同分法——「没有钥匙」「钥匙被拒
/// （401）」是桥未连接（钥匙问题）；其余（网络/厂商
/// 502/格式）如实归因，不许混报成未连接或电脑离线。
enum BoxBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case failed(String)
}

/// 盒桥客户端（P2，契约见 box-bridge-rollout-20261109）：
/// 路径挂在当前服务器根下 /api/box-bridge（与桥部署
/// 口径一致，用户改址后桥随服务器走）；Bearer 只从
/// BridgeCredential 统一读（0.33.1：聊天同一份
/// Hermes 登录密钥，入口在服务器内部换桥钥）；
/// 读不到钥匙一律
/// noKey、不发请求、不冒充已接通。
/// 超时分档：状态读 20 秒；截图/接管要唤醒 Box 并等
/// 厂商回图，给 100 秒（nginx 上限 120 秒之内）。
final class BoxBridgeClient: @unchecked Sendable {
    /// C-10 收敛：连接/单钥/管线/文案走统一基座（主会
    /// 话＝读档 20 秒），动作会话 100 秒经基座工厂自
    /// 建、调用时以 using: 传入；本类只留路径与口径
    private let base = BridgeClientBase<BoxBridgeError>(
        pathPrefix: "/api/box-bridge", timeout: 20,
        noKey: .noKey, failed: BoxBridgeError.failed
    )
    private let actSession = BridgeClientBase<BoxBridgeError>
        .makeSession(timeout: 100)

    private var decoder: JSONDecoder { base.decoder }

    func status(config: ServerConfig) async throws -> BoxBridgeStatus {
        try await get(config: config, path: "/status", endpoint: L10n.string("云电脑状态"))
    }

    func screenshot(config: ServerConfig) async throws -> BoxScreenshot {
        try await post(
            config: config, path: "/screenshot",
            body: BoxScreenshotRequest(), endpoint: L10n.string("桌面截图")
        )
    }

    func act(
        config: ServerConfig, request: BoxActRequest
    ) async throws -> BoxActResponse {
        try await post(
            config: config, path: "/act",
            body: request, endpoint: L10n.string("接管动作")
        )
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String
    ) async throws -> T {
        let (data, http) = try await base.perform(
            config: config, path: path, method: "GET",
            bodyData: nil, endpoint: endpoint
        )
        try check(http, endpoint: endpoint)
        return try decode(data, endpoint: endpoint)
    }

    private func post<T: Decodable, B: Encodable>(
        config: ServerConfig, path: String, body: B, endpoint: String
    ) async throws -> T {
        let bodyData: Data
        do {
            bodyData = try base.encoder.encode(body)
        } catch {
            throw BoxBridgeError.failed(L10n.format("%@请求组装失败", endpoint))
        }
        let (data, http) = try await base.perform(
            config: config, path: path, method: "POST",
            bodyData: bodyData, endpoint: endpoint,
            using: actSession
        )
        try check(http, endpoint: endpoint)
        return try decode(data, endpoint: endpoint)
    }

    private func check(
        _ http: HTTPURLResponse, endpoint: String
    ) throws {
        if http.statusCode == 401 {
            throw BoxBridgeError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw BoxBridgeError.failed(L10n.format("%@返回 %@", endpoint, String(http.statusCode)))
        }
    }

    private func decode<T: Decodable>(
        _ data: Data, endpoint: String
    ) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BoxBridgeError.failed(L10n.format("%@返回格式无法识别", endpoint))
        }
    }
}
