import Foundation
import OneDayCore

/// oneday-bridge 错误口径：与总览桥同分法——「没有钥匙」
/// 「钥匙被拒（401）」是桥未连接（钥匙问题），要在面
/// 上如实露；集合端点 404 是「桥未开通」；条目端点
/// 404 是记录已不在；其余失败给人话、不混报。
enum OneDayBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case bridgeMissing
    case recordGone
    case failed(String)
}

/// oneday-bridge 客户端（0.11.0，冻结契约）：目标/点子
/// 仓，路径挂在当前服务器根下（/api/oneday-bridge，
/// 与桥部署口径一致）。Bearer 只从 Keychain 的
/// CredentialKey.writeGateKey 读——与总览桥/write-gate
/// 同一把钥匙，用户零新增粘贴；读不到钥匙一律 noKey、
/// 不发请求、不冒充已接通。
final class OneDayBridgeClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    private var bridgeKey: String? {
        KeychainStore.read(account: CredentialKey.writeGateKey)
    }

    // MARK: - 目标

    func goals(config: ServerConfig) async throws -> [BridgeGoal] {
        let response: BridgeGoalsResponse = try await get(
            config: config, path: "/goals", endpoint: "目标列表",
            collection: true
        )
        return response.items
    }

    func createGoal(
        config: ServerConfig, request body: BridgeGoalCreateRequest
    ) async throws -> BridgeGoal {
        try await send(
            config: config, path: "/goals", method: "POST",
            body: body, endpoint: "新建目标", collection: true
        )
    }

    func patchGoal(
        config: ServerConfig, id: String,
        request body: BridgeGoalPatchRequest
    ) async throws -> BridgeGoal {
        try await send(
            config: config, path: "/goals/\(id)", method: "PATCH",
            body: body, endpoint: "保存目标", collection: false
        )
    }

    func deleteGoal(config: ServerConfig, id: String) async throws {
        let _: BridgeOKResponse = try await sendEmpty(
            config: config, path: "/goals/\(id)", method: "DELETE",
            endpoint: "删除目标"
        )
    }

    // MARK: - 点子

    func ideas(config: ServerConfig) async throws -> [BridgeIdea] {
        let response: BridgeIdeasResponse = try await get(
            config: config, path: "/ideas", endpoint: "点子列表",
            collection: true
        )
        return response.items
    }

    func createIdea(
        config: ServerConfig, request body: BridgeIdeaCreateRequest
    ) async throws -> BridgeIdea {
        try await send(
            config: config, path: "/ideas", method: "POST",
            body: body, endpoint: "新建点子", collection: true
        )
    }

    func deleteIdea(config: ServerConfig, id: String) async throws {
        let _: BridgeOKResponse = try await sendEmpty(
            config: config, path: "/ideas/\(id)", method: "DELETE",
            endpoint: "删除点子"
        )
    }

    // MARK: - 请求底座

    private func makeRequest(
        config: ServerConfig, path: String, method: String
    ) throws -> URLRequest {
        guard let key = bridgeKey, !key.isEmpty else {
            throw OneDayBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/oneday-bridge" + path)
        )
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        collection: Bool
    ) async throws -> T {
        let request = try makeRequest(config: config, path: path, method: "GET")
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint, collection: collection)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed("\(endpoint)返回格式无法识别")
        }
    }

    private func send<Body: Encodable, T: Decodable>(
        config: ServerConfig, path: String, method: String,
        body: Body, endpoint: String, collection: Bool
    ) async throws -> T {
        var request = try makeRequest(config: config, path: path, method: method)
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw OneDayBridgeError.failed("\(endpoint)请求组装失败")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint, collection: collection)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed("\(endpoint)回执格式无法识别")
        }
    }

    private func sendEmpty<T: Decodable>(
        config: ServerConfig, path: String, method: String,
        endpoint: String
    ) async throws -> T {
        let request = try makeRequest(config: config, path: path, method: method)
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint, collection: false)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed("\(endpoint)回执格式无法识别")
        }
    }

    /// 桥错误体（冻结口径）：失败响应统一 {"error": 人话}
    private struct BridgeErrorBody: Decodable {
        let error: String
    }

    /// 状态口径：2xx 通过；401 钥匙被拒；404 按端点分流
    /// （集合＝桥未开通、条目＝记录已不在）；400 等内容
    /// 问题优先透服务端人话（标题为空/关联目标不存在
    /// 等，客户端不许猜成固定一条）
    private func checkStatus(
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
            if let body = try? decoder.decode(
                BridgeErrorBody.self, from: data
            ), !body.error.isEmpty {
                throw OneDayBridgeError.failed(body.error)
            }
            throw OneDayBridgeError.failed(
                "\(endpoint)返回 \(http.statusCode)"
            )
        }
    }

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OneDayBridgeError.failed("\(endpoint)无响应")
            }
            return (data, http)
        } catch let error as OneDayBridgeError {
            throw error
        } catch {
            throw OneDayBridgeError.failed("\(endpoint)网络不可达")
        }
    }
}
