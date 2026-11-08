import Foundation
import OneDayCore

/// Hermes 服务端对接协议：连接页三步探活、总览与聊天都走它。
/// 写协议抽象是为后测留口（里程碑 2 可注入假实现跑 UI 单测）。
protocol HermesClientProtocol: Sendable {
    /// 探活一：GET /health（免鉴权）
    func health(config: ServerConfig) async throws -> HealthResponse
    /// 探活二：POST /auth/password-login 拿会话 cookie
    /// （cookie 由 URLSession 共享存储持有，本方法只判成败）
    func login(config: ServerConfig, username: String, password: String) async throws
    /// GET /api/status（免登录）
    func status(config: ServerConfig) async throws -> ServerStatus
    /// GET /api/config（需会话；401 由调用方走重登重试）
    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary
    /// 探活三：GET /v1/models（Bearer API 密钥），返回模型 id 列表
    func models(config: ServerConfig, apiKey: String) async throws -> [String]
    /// POST /v1/chat/completions 流式：逐段产出文本增量
    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error>
    /// 清除某服务器的全部会话 cookie（断开连接时调用）
    func clearCookies(config: ServerConfig)
}

/// URLSession 实现。会话 cookie 走 .shared 存储：登录一次，
/// 后续 /api/* 自动带上；进程重启后 cookie 仍在（系统持久化），
/// 过期则由 AppState 的自动重登兜底。
final class HermesClient: HermesClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    // MARK: - 基础请求

    /// 网络层错误统一映射：URLError → HermesError.unreachable（人话简述）
    private func mapNetworkError(_ error: Error) -> HermesError {
        if let hermesError = error as? HermesError {
            return hermesError
        }
        guard let urlError = error as? URLError else {
            return .unreachable("网络错误")
        }
        switch urlError.code {
        case .timedOut:
            return .unreachable("请求超时")
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .unreachable("无法建立连接")
        case .notConnectedToInternet, .networkConnectionLost:
            return .unreachable("网络不可用")
        default:
            return .unreachable("网络错误")
        }
    }

    private func dataRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HermesError.unreachable("无响应")
            }
            return (data, http)
        } catch let error as HermesError {
            throw error
        } catch {
            throw mapNetworkError(error)
        }
    }

    private func getJSON<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String, bearer: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: config.endpoint(path))
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            throw HermesError.unexpectedStatus(endpoint: endpoint, status: http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    // MARK: - 探活与接口

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

    func login(config: ServerConfig, username: String, password: String) async throws {
        var request = URLRequest(url: config.endpoint("/auth/password-login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 登录契约（2026-11-08 实测）：JSON 四字段，缺 provider 返回 422
        let body: [String: String] = [
            "provider": "basic",
            "username": username,
            "password": password,
            "next": "/",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403, 422:
            throw HermesError.loginRejected
        default:
            throw HermesError.loginFailed(status: http.statusCode)
        }
    }

    func status(config: ServerConfig) async throws -> ServerStatus {
        try await getJSON(config: config, path: "/api/status", endpoint: "状态接口")
    }

    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary {
        try await getJSON(config: config, path: "/api/config", endpoint: "配置接口")
    }

    func models(config: ServerConfig, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: config.endpoint("/v1/models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(endpoint: "模型接口", status: http.statusCode)
        }
        do {
            return try decoder.decode(ModelsResponse.self, from: data).ids
        } catch {
            throw HermesError.decodingFailed(endpoint: "模型接口")
        }
    }

    // MARK: - 流式聊天

    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: config.endpoint("/v1/chat/completions"))
                    request.httpMethod = "POST"
                    // 长回复逐字到达：单请求超时放宽到 10 分钟，
                    // 停止生成走 task.cancel()（onTermination 承接）
                    request.timeoutInterval = 600
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let payload: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw HermesError.unreachable("无响应")
                    }
                    guard http.statusCode == 200 else {
                        if http.statusCode == 401 || http.statusCode == 403 {
                            throw HermesError.apiKeyRejected
                        }
                        throw HermesError.unexpectedStatus(
                            endpoint: "聊天接口", status: http.statusCode
                        )
                    }
                    let parser = SSEParser()
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            throw HermesError.cancelled
                        }
                        switch parser.consume(line: line) {
                        case .delta(let text):
                            continuation.yield(text)
                        case .done:
                            continuation.finish()
                            return
                        case nil:
                            continue
                        }
                    }
                    // 服务端未发 [DONE] 就收尾：已产出内容照常成篇
                    continuation.finish()
                } catch let error as HermesError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish(throwing: HermesError.cancelled)
                } catch {
                    continuation.finish(throwing: mapNetworkError(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Cookie

    func clearCookies(config: ServerConfig) {
        guard let storage = session.configuration.httpCookieStorage,
              let host = config.endpoint("/").host else {
            return
        }
        let cookies = storage.cookies ?? []
        for cookie in cookies where cookie.domain.contains(host) || host.contains(cookie.domain) {
            storage.deleteCookie(cookie)
        }
    }
}
