import Foundation
import OneDayCore

/// Box MCP 客户端错误
enum BoxMCPError: Error, Sendable, Equatable {
    case noKey
    case sessionFailed(String)
    case toolCallFailed(String)
    case networkError
}

/// Box MCP 客户端：直连 Simular Box MCP 服务
///
/// 架构对齐 box_bridge.py BoxMCP（行为已验证）：
/// - 会话长驻：一个 URLSession 对象保持连接
/// - 调用串行：通过 actor 隔离保证串行执行
/// - 懒重连：会话失效时下次调用重建（重连=新会话，浏览器窗口重置）
/// - 重试逻辑：失败时最多重试 2 次
///
/// 关键差异：Python 实现用 mcp SDK 维护持久连接；Swift 实现
/// 每次调用发独立 HTTP 请求，通过 Mcp-Session-Id 头维护会话。
/// Box MCP 服务实测支持这种"stateless client"模式。
actor BoxMCPClient {
    private let mcpURL: URL
    private let apiKey: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// 会话 ID（懒初始化，失效后重建）
    private var sessionId: String?

    /// 最后一次 box_status 调用的状态缓存（20 秒有效，对齐 box_bridge.py:129）
    private var lastState: String?
    private var lastStateAt: Date?

    /// F7.3：最后确认的页面缓存
    private var lastKnownPage: [String: Any]?

    init(mcpURL: URL, apiKey: String) {
        self.mcpURL = mcpURL
        self.apiKey = apiKey

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - 会话管理

    /// 初始化会话（对齐 box_bridge.py:93 initialize）
    private func initialize() async throws {
        let request = MCPRequest(
            id: UUID().uuidString,
            method: "initialize",
            params: [
                "protocolVersion": .string("2025-03-26"),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("OneDay"),
                    "version": .string("1.0")
                ])
            ]
        )

        let (data, response) = try await sendRequest(request, captureSessionId: true)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BoxMCPError.sessionFailed("initialize failed")
        }

        // 从响应头提取 Mcp-Session-Id
        if let newSessionId = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Mcp-Session-Id") {
            sessionId = newSessionId
        }

        // 解析响应确认初始化成功
        let mcpResponse = try decoder.decode(MCPResponse.self, from: data)
        if mcpResponse.isError {
            throw BoxMCPError.sessionFailed(mcpResponse.error?.message ?? "initialize error")
        }

        // 发送 initialized 通知（F3：MCP 握手要求）
        let notification = MCPRequest(
            id: UUID().uuidString,
            method: "notifications/initialized",
            params: nil
        )
        // 通知无需响应体，容忍 202 或其他成功码
        _ = try? await sendRequest(notification, captureSessionId: false)
    }

    /// 重置会话（对齐 box_bridge.py:96-105 _disconnect）
    private func resetSession() {
        sessionId = nil
        lastState = nil
        lastStateAt = nil
        lastKnownPage = nil
    }

    // MARK: - F7.3 lastKnownPage 缓存

    func updateLastKnownPage(_ page: [String: Any]) {
        lastKnownPage = page
    }

    func getLastKnownPage() -> (page: [String: Any]?, checkedAt: String?) {
        guard let page = lastKnownPage else { return (nil, nil) }
        return (page, page["checkedAt"] as? String)
    }

    // MARK: - 工具调用

    /// 调用 MCP 工具（对齐 box_bridge.py:107-119 _call，包含重试）
    func callTool(name: String, arguments: [String: Any], timeout: TimeInterval = 60) async throws -> MCPResult {
        var lastError: Error?

        // 最多重试 2 次（对齐 box_bridge.py:110）
        for attempt in 1...2 {
            do {
                // 确保会话存在
                if sessionId == nil {
                    try await initialize()
                }

                // 构建 tools/call 请求（F2：顶层 params 包含 name 和 arguments）
                let argumentsJSON = anyToJSONValue(arguments)
                let request = MCPRequest(
                    id: UUID().uuidString,
                    method: "tools/call",
                    params: [
                        "name": .string(name),
                        "arguments": argumentsJSON
                    ]
                )

                // 发送请求（F5：使用请求的 timeout 参数）
                let (data, response) = try await sendRequest(request, captureSessionId: false, timeout: timeout)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BoxMCPError.networkError
                }

                // 会话失效，重置后重试
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    resetSession()
                    if attempt < 2 {
                        continue
                    }
                    throw BoxMCPError.sessionFailed("unauthorized")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw BoxMCPError.toolCallFailed("HTTP \(httpResponse.statusCode)")
                }

                // F4：解析响应（支持 SSE 和纯 JSON）
                let responseData: Data
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
                   contentType.contains("text/event-stream") {
                    // SSE 响应：按 requestId 匹配提取 JSON
                    guard let extracted = parseSSEResponse(data: data, requestId: request.id) else {
                        throw BoxMCPError.toolCallFailed("SSE response parsing failed")
                    }
                    responseData = extracted
                } else {
                    // 纯 JSON 响应
                    responseData = data
                }

                // 解析响应
                let mcpResponse = try decoder.decode(MCPResponse.self, from: responseData)
                if let error = mcpResponse.error {
                    throw BoxMCPError.toolCallFailed(error.message)
                }

                guard let result = mcpResponse.result else {
                    throw BoxMCPError.toolCallFailed("no result in response")
                }

                return result

            } catch {
                lastError = error
                resetSession()
                if attempt == 2 {
                    break
                }
            }
        }

        throw BoxMCPError.toolCallFailed("MCP call \(name) failed: \(lastError?.localizedDescription ?? "unknown")")
    }

    // MARK: - Box 专用逻辑

    /// 确保 Box 运行（对齐 box_bridge.py:126-136 ensure_running）
    func ensureRunning() async throws {
        // 检查状态缓存（20 秒有效）
        if let lastState = lastState,
           let lastStateAt = lastStateAt,
           lastState == "running",
           Date().timeIntervalSince(lastStateAt) < 20 {
            return
        }

        // 查询状态
        let statusResult = try await callTool(name: "box_status", arguments: [:], timeout: 30)
        if let state = mcpStructured(statusResult)?["state"] as? String {
            lastState = state
            lastStateAt = Date()

            if state != "running" {
                // 启动 Box
                _ = try await callTool(
                    name: "box_ensure",
                    arguments: ["wait": true],
                    timeout: 90
                )
                lastState = "running"
                lastStateAt = Date()
            }
        }
    }

    // MARK: - HTTP 传输

    private func sendRequest(_ request: MCPRequest, captureSessionId: Bool, timeout: TimeInterval = 60) async throws -> (Data, URLResponse) {
        let bodyData = try encoder.encode(request)

        var urlRequest = URLRequest(url: mcpURL)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = bodyData
        urlRequest.timeoutInterval = timeout  // F5：每次请求独立设置超时

        // F4：添加 SSE 支持的 Accept 头
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        // 附加会话 ID（如果有）
        if let sessionId = sessionId {
            urlRequest.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }

        return try await session.data(for: urlRequest)
    }

    /// 将 [String: Any] 转换为 JSONValue
    private func anyToJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let s as String: return .string(s)
        case let n as Int: return .number(Double(n))
        case let n as Double: return .number(n)
        case let b as Bool: return .bool(b)
        case let dict as [String: Any]:
            return .object(dict.mapValues(anyToJSONValue))
        case let arr as [Any]:
            return .array(arr.map(anyToJSONValue))
        default: return .null
        }
    }
}

/// Box MCP 客户端工厂：管理全局单例
@MainActor
final class BoxMCPClientFactory {
    private static var client: BoxMCPClient?

    /// 获取或创建客户端（凭据变更时会创建新实例）
    static func getClient() throws -> BoxMCPClient {
        // 读取凭据
        guard let apiKey = KeychainStore.read(account: "box.mcp.key"),
              !apiKey.isEmpty else {
            throw BoxMCPError.noKey
        }

        // 读取 MCP URL（默认 Simular Box）
        let urlString = UserDefaults.standard.string(forKey: "box.mcp.url")
            ?? "https://mcp.box.simular.ai/mcp"
        guard let url = URL(string: urlString) else {
            throw BoxMCPError.sessionFailed("invalid MCP URL")
        }

        // 复用或创建客户端
        if let existing = client {
            return existing
        }

        let newClient = BoxMCPClient(mcpURL: url, apiKey: apiKey)
        client = newClient
        return newClient
    }

    /// 重置客户端（用于凭据变更）
    static func reset() {
        client = nil
    }
}
