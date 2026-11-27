import Foundation
import OneDayCore
#if canImport(MCP)
import MCP
#endif

/// Box MCP 客户端错误
enum BoxMCPError: Error, Sendable, Equatable {
    case noKey
    case sessionFailed(String)
    case toolCallFailed(String)
    case networkError
}

/// Box MCP 客户端：直连 Simular Box MCP 服务（#23 真切流官方 modelcontextprotocol/swift-sdk）
///
/// - 使用官方 `MCP.Client` + `HTTPClientTransport` 维护会话、协议版本协商与工具调用
/// - 调用串行：通过 actor 隔离保证串行执行
/// - 懒重连：会话失效时断开并重建官方 SDK Client，失败时最多重试 2 次
/// - 保留 20 秒 `box_status` 缓存与 `lastKnownPage` 缓存语义
actor BoxMCPClient {
    private let mcpURL: URL
    private let apiKey: String

    #if canImport(MCP)
    private var sdkClient: MCP.Client?
    private var sdkTransport: HTTPClientTransport?
    #else
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var sessionId: String?
    #endif

    /// 最后一次 box_status 调用的状态缓存（20 秒有效，对齐 box_bridge.py:129）
    private var lastState: String?
    private var lastStateAt: Date?

    /// F7.3：最后确认的页面缓存
    private var lastKnownPage: MCPPageRef?

    init(mcpURL: URL, apiKey: String) {
        self.mcpURL = mcpURL
        self.apiKey = apiKey

        #if !canImport(MCP)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        self.session = URLSession(configuration: configuration)
        #endif
    }

    // MARK: - 会话管理

    #if canImport(MCP)
    private func ensureConnected(timeout: TimeInterval) async throws -> MCP.Client {
        if let sdkClient {
            return sdkClient
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = max(timeout, 60)
        let token = apiKey
        let transport = HTTPClientTransport(
            endpoint: mcpURL,
            configuration: configuration,
            streaming: false,
            requestModifier: { request in
                var req = request
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return req
            }
        )
        let client = MCP.Client(name: "OneDay", version: "1.0")
        _ = try await client.connect(transport: transport)
        self.sdkTransport = transport
        self.sdkClient = client
        return client
    }

    private func resetSession() async {
        if let sdkClient {
            await sdkClient.disconnect()
        }
        sdkClient = nil
        sdkTransport = nil
        lastState = nil
        lastStateAt = nil
        lastKnownPage = nil
    }
    #else
    private func resetSession() async {
        sessionId = nil
        lastState = nil
        lastStateAt = nil
        lastKnownPage = nil
    }
    #endif

    // MARK: - F7.3 lastKnownPage 缓存

    func updateLastKnownPage(_ page: MCPPageRef) {
        lastKnownPage = page
    }

    func getLastKnownPage() -> MCPPageRef? {
        return lastKnownPage
    }

    // MARK: - 工具调用

    /// 调用 MCP 工具（对齐 box_bridge.py:107-119 _call，包含最多 2 次重试）
    func callTool(name: String, arguments: [String: Any], timeout: TimeInterval = 60) async throws -> MCPResult {
        var lastError: Error?

        for attempt in 1...2 {
            do {
                #if canImport(MCP)
                let client = try await ensureConnected(timeout: timeout)
                let mcpArgs = Self.toSDKArguments(arguments)
                let (content, isError) = try await client.callTool(
                    name: name,
                    arguments: mcpArgs.isEmpty ? nil : mcpArgs
                )
                return Self.toOneDayResult(content: content, isError: isError)
                #else
                throw BoxMCPError.sessionFailed("MCP SDK unavailable")
                #endif
            } catch {
                lastError = error
                await resetSession()
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
        if let lastState = lastState,
           let lastStateAt = lastStateAt,
           lastState == "running",
           Date().timeIntervalSince(lastStateAt) < 20 {
            return
        }

        let statusResult = try await callTool(name: "box_status", arguments: [:], timeout: 30)
        if let state = mcpStructured(statusResult)?["state"] as? String {
            lastState = state
            lastStateAt = Date()

            if state != "running" {
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

    #if canImport(MCP)
    private static func toSDKArguments(_ dict: [String: Any]) -> [String: MCP.Value] {
        dict.mapValues(toSDKValue)
    }

    private static func toSDKValue(_ value: Any) -> MCP.Value {
        switch value {
        case let b as Bool: return .bool(b)
        case let s as String: return .string(s)
        case let i as Int: return .int(i)
        case let d as Double: return .double(d)
        case let arr as [Any]: return .array(arr.map(toSDKValue))
        case let dict as [String: Any]: return .object(dict.mapValues(toSDKValue))
        default: return .null
        }
    }

    private static func toOneDayResult(
        content: [MCP.Tool.Content],
        isError: Bool?
    ) -> MCPResult {
        let mapped: [MCPContent] = content.map { item in
            switch item {
            case .text(let text, _, _):
                return .text(text)
            case .image(let data, let mimeType, _, _):
                return .image(data: data, mimeType: mimeType)
            default:
                return .unknown
            }
        }
        return MCPResult(content: mapped, isError: isError, structuredContent: nil)
    }
    #endif

    /// 兼容既有内部工具转换接口
    internal func anyToJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let b as Bool: return .bool(b)
        case let s as String: return .string(s)
        case let n as Int: return .number(Double(n))
        case let n as Double: return .number(n)
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
    private static let mcpURL = URL(string: "https://mcp.box.simular.ai/mcp")!

    /// 获取或创建客户端（凭据变更时会创建新实例）
    static func getClient() throws -> BoxMCPClient {
        guard let apiKey = KeychainStore.read(account: "box.mcp.key"),
              !apiKey.isEmpty else {
            throw BoxMCPError.noKey
        }

        if let existing = client {
            return existing
        }

        let newClient = BoxMCPClient(mcpURL: mcpURL, apiKey: apiKey)
        client = newClient
        return newClient
    }

    /// 重置客户端（用于凭据变更）
    static func reset() {
        client = nil
    }
}
