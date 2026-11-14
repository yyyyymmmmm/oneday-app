import Foundation
import OneDayCore

/// 总览桥错误：区分「没有钥匙」「钥匙被拒（401）」与
/// 「其余失败」——前两类是桥未连接（钥匙问题），要在
/// 设置里如实露「桥未连接」；其余失败（网络/格式）不
/// 归因于钥匙，不许混报。
enum OverviewBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case failed(String)
}

/// 总览桥客户端（0.6.0 一期，冻结契约）：路径挂在当前
/// 服务器根下（默认 https://hermes.didichou.site 的
/// /api/overview-bridge，与桥部署口径一致；用户改址后
/// 桥随服务器走）。Bearer 只从 Keychain 的
/// BridgeCredential 统一读（0.33.1：聊天同一份
/// Hermes 登录密钥，入口在服务器内部换桥钥）；
/// 读不到钥匙一律 noKey、不发请求、不冒充已接通。
/// C-10 收敛：连接/单钥/管线/文案走统一基座（短请求
/// waitsForConnectivity 与 HermesClient 短请求同口径，
/// 0.36.20 §86.4），本类只留路径与状态口径。
final class OverviewBridgeClient: @unchecked Sendable {
    private let base = BridgeClientBase<OverviewBridgeError>(
        pathPrefix: "/api/overview-bridge", timeout: 15,
        waitsForConnectivity: true,
        noKey: .noKey, failed: OverviewBridgeError.failed
    )

    func overview(config: ServerConfig) async throws -> OverviewSnapshot {
        try await get(config: config, path: "/overview", endpoint: L10n.string("总览"))
    }

    func notifications(config: ServerConfig) async throws -> [OverviewNotification] {
        let response: OverviewNotificationsResponse = try await get(
            config: config, path: "/notifications", endpoint: L10n.string("通知")
        )
        return response.items
    }

    @discardableResult
    func markRead(config: ServerConfig, id: String) async throws -> Bool {
        let endpoint = L10n.string("通知已读")
        let (data, http) = try await base.perform(
            config: config, path: "/notifications/\(id)/read",
            method: "POST", bodyData: nil, endpoint: endpoint
        )
        if http.statusCode == 401 {
            throw OverviewBridgeError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw OverviewBridgeError.failed(L10n.format("通知已读返回 %@", String(http.statusCode)))
        }
        let response: OverviewReadResponse = try base.decode(
            data,
            orThrow: OverviewBridgeError.failed(L10n.string("通知已读回执格式无法识别"))
        )
        return response.ok
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String
    ) async throws -> T {
        try await base.get(
            config: config, path: path, endpoint: endpoint
        ) { http, _ in
            if http.statusCode == 401 {
                throw OverviewBridgeError.unauthorized
            }
            guard http.statusCode == 200 else {
                throw OverviewBridgeError.failed(
                    L10n.format("%@返回 %@", endpoint, String(http.statusCode))
                )
            }
        }
    }
}
