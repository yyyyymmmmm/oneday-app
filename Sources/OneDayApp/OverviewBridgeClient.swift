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
final class OverviewBridgeClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        // 短请求开 waitsForConnectivity（0.36.20，§86.4，
        // 与 HermesClient 短请求会话同口径）：总览/通知
        // 取数在无路径时先等连通再开始，不立刻失败
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    private var bridgeKey: String? {
        BridgeCredential.read()
    }

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
        guard let key = bridgeKey, !key.isEmpty else {
            throw OverviewBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/overview-bridge/notifications/\(id)/read")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await send(request, endpoint: L10n.string("通知已读"))
        if http.statusCode == 401 {
            throw OverviewBridgeError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw OverviewBridgeError.failed(L10n.format("通知已读返回 %@", String(http.statusCode)))
        }
        do {
            return try decoder.decode(OverviewReadResponse.self, from: data).ok
        } catch {
            throw OverviewBridgeError.failed(L10n.string("通知已读回执格式无法识别"))
        }
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String
    ) async throws -> T {
        guard let key = bridgeKey, !key.isEmpty else {
            throw OverviewBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/overview-bridge" + path)
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await send(request, endpoint: endpoint)
        if http.statusCode == 401 {
            throw OverviewBridgeError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw OverviewBridgeError.failed(L10n.format("%@返回 %@", endpoint, String(http.statusCode)))
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OverviewBridgeError.failed(L10n.format("%@返回格式无法识别", endpoint))
        }
    }

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OverviewBridgeError.failed(L10n.format("%@无响应", endpoint))
            }
            return (data, http)
        } catch let error as OverviewBridgeError {
            throw error
        } catch {
            throw OverviewBridgeError.failed(L10n.format("%@网络不可达", endpoint))
        }
    }
}
