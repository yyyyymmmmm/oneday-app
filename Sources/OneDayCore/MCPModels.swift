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
    public let params: [String: AnyCodable]?

    public init(id: String, method: String, params: [String: AnyCodable]? = nil) {
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
    public let data: AnyCodable?
}

/// MCP 结果（tools/call 的返回）
public struct MCPResult: Decodable {
    public let content: [MCPContent]?
    public let isError: Bool?
    public let structuredContent: AnyCodable?

    private enum CodingKeys: String, CodingKey {
        case content, isError, structuredContent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent([MCPContent].self, forKey: .content)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
        structuredContent = try container.decodeIfPresent(AnyCodable.self, forKey: .structuredContent)
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

/// AnyCodable：支持任意 JSON 值的编解码
public struct AnyCodable: Codable, Equatable, Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyCodable.init))
        default:
            try container.encodeNil()
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // 简化相等性判断：只支持基础类型
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull): return true
        case (let l as Bool, let r as Bool): return l == r
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as String, let r as String): return l == r
        default: return false
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
    if let sc = result.structuredContent?.value as? [String: Any] {
        return sc
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
