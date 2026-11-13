import Foundation
import OneDayCore

/// 身份桥错误：与总览桥同分法——没有钥匙/钥匙被拒是
/// 「桥未连接」，其余失败如实报、不归因于钥匙。
enum IdentityBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case failed(String)
}

/// 头像仓状态（与伴生 identity_bridge 的 GET
/// /identity/avatar 同形）：当前指针＋全量条目历史；
/// 图片条目的字节本体走单独端点取，不塞进状态回执。
struct IdentityAvatarState: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let id: String
        let kind: String
        let presetId: String?
        let contentType: String?
        let bytes: Int?
        let sha256: String?
        let current: Bool
    }

    let currentId: String?
    let items: [Item]

    /// 当前条目：优先信条目自带的 current 标记，缺失
    /// 时按 currentId 兜底查
    var currentItem: Item? {
        items.first(where: { $0.current })
            ?? items.first(where: { $0.id == currentId })
    }
}

/// 身份桥客户端（P1 身份包）：App 侧只读头像仓——写
/// 口（改名/换头像）是智能体经 MCP 工具走的，不在
/// App 侧开第二条写路。路径挂当前服务器根下
/// /api/identity-bridge，Bearer 只从 BridgeCredential
/// 统一读（与全 App 桥客户端同口径，0.33.1）。
final class IdentityBridgeClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    private var bridgeKey: String? {
        BridgeCredential.read()
    }

    func avatarState(config: ServerConfig) async throws -> IdentityAvatarState {
        let data = try await get(
            config: config, path: "/identity/avatar",
            endpoint: L10n.string("头像仓")
        )
        do {
            return try decoder.decode(IdentityAvatarState.self, from: data)
        } catch {
            throw IdentityBridgeError.failed(L10n.string("头像仓返回格式无法识别"))
        }
    }

    func avatarImage(config: ServerConfig, id: String) async throws -> Data {
        try await get(
            config: config, path: "/identity/avatar/image?id=\(id)",
            endpoint: L10n.string("头像图")
        )
    }

    private func get(
        config: ServerConfig, path: String, endpoint: String
    ) async throws -> Data {
        guard let key = bridgeKey, !key.isEmpty else {
            throw IdentityBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/identity-bridge" + path)
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await send(request, endpoint: endpoint)
        if http.statusCode == 401 {
            throw IdentityBridgeError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw IdentityBridgeError.failed(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
        return data
    }

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw IdentityBridgeError.failed(L10n.format("%@无响应", endpoint))
            }
            return (data, http)
        } catch let error as IdentityBridgeError {
            throw error
        } catch {
            throw IdentityBridgeError.failed(L10n.format("%@网络不可达", endpoint))
        }
    }
}
