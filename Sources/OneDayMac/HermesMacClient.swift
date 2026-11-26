import Foundation
import OneDayCore

/// Mac 端网关客户端（地基棒）：只实现登录链与壳层状态
/// 面要用的端点，全部与 iOS 端 HermesClient 同路径、
/// 同状态码口径——GET /health → POST /api/companion/
/// web-login（面板密码一步制，§244 一把密码统一）→
/// POST /api/env/reveal 换 API_SERVER_KEY → GET
/// /v1/models 验钥，另加 /v1/capabilities 与 /api/status
/// 供壳层消费。后续棒按对位表逐面扩端点，不另起第二
/// 套客户端。cookie 落 URLSession 共享存储（web-login
/// 换来的 dashboard 会话 cookie 由 reveal 一步带上，
/// 与 iOS 同机制）。
struct HermesMacClient: Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 传输底座

    private func dataRequest(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HermesError.unexpectedStatus(
                    endpoint: "网络响应", status: -1
                )
            }
            return (data, http)
        } catch let error as URLError {
            throw HermesError.fromURLError(error)
        }
    }

    private func bearerGet<T: Decodable>(
        config: ServerConfig, apiKey: String, path: String,
        endpoint: String
    ) async throws -> T {
        var request = URLRequest(url: config.endpoint(path))
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: endpoint, status: http.statusCode
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    // MARK: - 登录链（与 iOS connectWithPassword 同序）

    /// 探活一：GET /health（免鉴权）
    func health(config: ServerConfig) async throws -> HealthResponse {
        var request = URLRequest(url: config.endpoint("/health"))
        request.timeoutInterval = 15
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            throw HermesError.healthCheckFailed(status: http.statusCode)
        }
        do {
            return try decoder.decode(HealthResponse.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: "健康检查")
        }
    }

    /// 探活二：POST /api/companion/web-login 验面板密码
    /// （桥在服务器内部换 dashboard 会话 cookie 原样透
    /// 传，部署密码永不出服务器）
    func login(config: ServerConfig, password: String) async throws {
        var request = URLRequest(
            url: config.endpoint("/api/companion/web-login")
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["password": password]
        )
        let (_, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw HermesError.loginRejected
        case 429:
            throw HermesError.loginRateLimited
        default:
            throw HermesError.loginFailed(status: http.statusCode)
        }
    }

    /// 换钥：POST /api/env/reveal {key} → 明文（响应形
    /// 态宽容提取，与 iOS revealEnvVar 同口径）
    func revealEnvVar(config: ServerConfig, key: String) async throws -> String {
        var request = URLRequest(url: config.endpoint("/api/env/reveal"))
        request.httpMethod = "POST"
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["key": key]
        )
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: "密钥查看", status: http.statusCode
            )
        }
        let value = try decoder.decode(JSONValue.self, from: data)
        switch value {
        case .string(let text):
            return text
        case .object(let object):
            if let text = object["value"]?.stringValue {
                return text
            }
            throw HermesError.decodingFailed(endpoint: "密钥查看")
        default:
            throw HermesError.decodingFailed(endpoint: "密钥查看")
        }
    }

    /// 探活三：GET /v1/models（Bearer 登录密钥）→ 模型 id 列表
    func models(
        config: ServerConfig, apiKey: String
    ) async throws -> [String] {
        let response: ModelsResponse = try await bearerGet(
            config: config, apiKey: apiKey, path: "/v1/models",
            endpoint: "模型接口"
        )
        return response.ids
    }

    /// 能力发现：GET /v1/capabilities（Bearer）
    func capabilities(
        config: ServerConfig, apiKey: String
    ) async throws -> CapabilitiesResponse {
        try await bearerGet(
            config: config, apiKey: apiKey, path: "/v1/capabilities",
            endpoint: "能力接口"
        )
    }

    /// 服务状态：GET /api/status（免登录）
    func status(config: ServerConfig) async throws -> ServerStatus {
        let request = URLRequest(url: config.endpoint("/api/status"))
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            throw HermesError.unexpectedStatus(
                endpoint: "状态接口", status: http.statusCode
            )
        }
        do {
            return try decoder.decode(ServerStatus.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: "状态接口")
        }
    }
}
