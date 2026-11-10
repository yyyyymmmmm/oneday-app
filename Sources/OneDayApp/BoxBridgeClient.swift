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
/// BridgeKeyStore 的 .box 分项读（0.32.1 分权，
/// F03/R8；分项未配置时过渡回退旧共用钥）；读不到
/// 钥匙一律
/// noKey、不发请求、不冒充已接通。
/// 超时分档：状态读 20 秒；截图/接管要唤醒 Box 并等
/// 厂商回图，给 100 秒（nginx 上限 120 秒之内）。
final class BoxBridgeClient: @unchecked Sendable {
    private let readSession: URLSession
    private let actSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let readConfiguration = URLSessionConfiguration.default
        readConfiguration.timeoutIntervalForRequest = 20
        readSession = URLSession(configuration: readConfiguration)
        let actConfiguration = URLSessionConfiguration.default
        actConfiguration.timeoutIntervalForRequest = 100
        actSession = URLSession(configuration: actConfiguration)
    }

    private var bridgeKey: String? {
        BridgeKeyStore.read(.box)
    }

    func status(config: ServerConfig) async throws -> BoxBridgeStatus {
        try await get(config: config, path: "/status", endpoint: "云电脑状态")
    }

    func screenshot(config: ServerConfig) async throws -> BoxScreenshot {
        try await post(
            config: config, path: "/screenshot",
            body: BoxScreenshotRequest(), endpoint: "桌面截图"
        )
    }

    func act(
        config: ServerConfig, request: BoxActRequest
    ) async throws -> BoxActResponse {
        try await post(
            config: config, path: "/act",
            body: request, endpoint: "接管动作"
        )
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String
    ) async throws -> T {
        let request = try makeRequest(
            config: config, path: path, method: "GET", body: nil
        )
        let (data, http) = try await send(
            request, session: readSession, endpoint: endpoint
        )
        try check(http, endpoint: endpoint)
        return try decode(data, endpoint: endpoint)
    }

    private func post<T: Decodable, B: Encodable>(
        config: ServerConfig, path: String, body: B, endpoint: String
    ) async throws -> T {
        let bodyData: Data
        do {
            bodyData = try encoder.encode(body)
        } catch {
            throw BoxBridgeError.failed("\(endpoint)请求组装失败")
        }
        let request = try makeRequest(
            config: config, path: path, method: "POST", body: bodyData
        )
        let (data, http) = try await send(
            request, session: actSession, endpoint: endpoint
        )
        try check(http, endpoint: endpoint)
        return try decode(data, endpoint: endpoint)
    }

    private func makeRequest(
        config: ServerConfig, path: String, method: String, body: Data?
    ) throws -> URLRequest {
        guard let key = bridgeKey, !key.isEmpty else {
            throw BoxBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/box-bridge" + path)
        )
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue(
                "application/json", forHTTPHeaderField: "Content-Type"
            )
        }
        return request
    }

    private func check(
        _ http: HTTPURLResponse, endpoint: String
    ) throws {
        if http.statusCode == 401 {
            throw BoxBridgeError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw BoxBridgeError.failed("\(endpoint)返回 \(http.statusCode)")
        }
    }

    private func decode<T: Decodable>(
        _ data: Data, endpoint: String
    ) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BoxBridgeError.failed("\(endpoint)返回格式无法识别")
        }
    }

    private func send(
        _ request: URLRequest, session: URLSession, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BoxBridgeError.failed("\(endpoint)无响应")
            }
            return (data, http)
        } catch let error as BoxBridgeError {
            throw error
        } catch {
            throw BoxBridgeError.failed("\(endpoint)网络不可达")
        }
    }
}
