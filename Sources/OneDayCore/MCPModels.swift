import Foundation

// MARK: - MCP Protocol Models
//
// Model Context Protocol (MCP) streamable HTTP 客户端基础模型。
// 协议参考：box_bridge.py BoxMCP 实现验证过的行为。
//
// 核心约定：
// 1. 会话长驻、调用串行、懒重连（重连=新会话，窗口重置）
// 2. 响应兼容纯 JSON 与 text/event-stream 两种形态
// 3. 工具调用结果：content 数组（text/image/structuredContent）+ isError

/// JSON-RPC 2.0 请求信封
public struct MCPRequest: Encodable {
    public let jsonrpc = "2.0"
    public let id: String
    public let method: String
    public let params: [String: JSONValue]?

    public init(id: String, method: String, params: [String: JSONValue]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 响应信封
public struct MCPResponse: Decodable {
    public let jsonrpc: String
    public let id: String?
    public let result: MCPResult?
    public let error: MCPError?

    public var isError: Bool { error != nil }
}

/// MCP 错误
public struct MCPError: Decodable, Equatable, Sendable {
    public let code: Int
    public let message: String
    public let data: JSONValue?
}

/// MCP 结果（tools/call 的返回）
public struct MCPResult: Decodable {
    public let content: [MCPContent]?
    public let isError: Bool?
    public let structuredContent: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case content, isError, structuredContent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent([MCPContent].self, forKey: .content)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
        structuredContent = try container.decodeIfPresent(JSONValue.self, forKey: .structuredContent)
    }
}

/// MCP 内容块（文本/图像/结构化数据）
public enum MCPContent: Decodable, Equatable, Sendable {
    case text(String)
    case image(data: String, mimeType: String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, mime_type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""

        switch type {
        case "text":
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .text(text)
        case "image":
            let data = try container.decodeIfPresent(String.self, forKey: .data) ?? ""
            // 兼容 mimeType 与 mime_type 两种键名（box_bridge.py:228）
            let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
                ?? container.decodeIfPresent(String.self, forKey: .mime_type)
                ?? "image/jpeg"
            self = .image(data: data, mimeType: mimeType)
        default:
            self = .unknown
        }
    }
}

// MARK: - MCP 工具调用结果解析

/// 提取文本块（对齐 box_bridge.py:150-155 tool_texts）
public func mcpTexts(_ result: MCPResult) -> [String] {
    guard let content = result.content else { return [] }
    return content.compactMap {
        if case .text(let text) = $0 { return text }
        return nil
    }
}

/// 提取结构化数据（对齐 box_bridge.py:158-171 tool_structured）
public func mcpStructured(_ result: MCPResult) -> [String: Any]? {
    // 优先读 structuredContent
    if let sc = result.structuredContent {
        return jsonValueToAny(sc) as? [String: Any]
    }
    // 回退：尝试解析第一个文本块为 JSON
    for text in mcpTexts(result) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            continue
        }
        return json
    }
    return nil
}

/// 提取错误文本（对齐 box_bridge.py:174-176 tool_error_text）
public func mcpErrorText(_ result: MCPResult) -> String {
    let texts = mcpTexts(result)
    guard let first = texts.first else { return "tool error" }
    return String(first.prefix(400))
}

// MARK: - JSONValue 辅助

/// 将 JSONValue 转换为 Any（用于与旧代码的互操作）
private func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .string(let s): return s
    case .number(let n): return n
    case .bool(let b): return b
    case .object(let dict): return dict.mapValues(jsonValueToAny)
    case .array(let arr): return arr.map(jsonValueToAny)
    case .null: return NSNull()
    }
}

// MARK: - SSE 响应解析（F4）

/// 从 SSE 格式的响应数据中提取 JSON-RPC 响应
/// - Parameters:
///   - data: SSE 格式的响应数据
///   - requestId: 请求 ID，用于匹配对应的响应
/// - Returns: 匹配 requestId 的 JSON-RPC 响应数据，如果没有找到则返回 nil
public func parseSSEResponse(data: Data, requestId: String) -> Data? {
    guard let text = String(data: data, encoding: .utf8) else { return nil }

    let lines = text.components(separatedBy: .newlines)
    for line in lines {
        // SSE 数据行格式：data: <json>
        guard line.hasPrefix("data: ") else { continue }
        let jsonText = line.dropFirst(6)  // 移除 "data: " 前缀
        guard let jsonData = jsonText.data(using: .utf8) else { continue }

        // 尝试解析为 JSON-RPC 响应并检查 id
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let id = json["id"] as? String,
              id == requestId else {
            continue
        }

        return jsonData
    }

    return nil
}

