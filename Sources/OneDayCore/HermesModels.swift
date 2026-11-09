import Foundation

// MARK: - GET /health（API Server 公共健康，免鉴权）

/// 实测样本：{"status": "ok", "platform": "hermes-agent", "version": "0.23.0"}
public struct HealthResponse: Decodable, Sendable, Equatable {
    public let status: String
    public let platform: String?
    public let version: String?

    public var isOK: Bool { status == "ok" }
}

// MARK: - GET /api/status（Dashboard 状态，免登录）

/// 实测样本（节选）：{"version": "0.23.0", "release_date": "2026.9.24",
/// "gateway_running": true, "gateway_state": "running",
/// "gateway_platforms": {"api_server": {"state": "connected", ...}}}
/// 字段一律宽容解码：服务端小版本字段增减不许打死总览页。
public struct ServerStatus: Decodable, Sendable {
    public let version: String?
    public let releaseDate: String?
    public let configVersion: Int?
    public let gatewayRunning: Bool?
    public let gatewayState: String?
    public let platforms: [String: PlatformState]

    public struct PlatformState: Decodable, Sendable {
        public let state: String?
        public let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case state
            case errorMessage = "error_message"
        }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case releaseDate = "release_date"
        case configVersion = "config_version"
        case gatewayRunning = "gateway_running"
        case gatewayState = "gateway_state"
        case platforms = "gateway_platforms"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        configVersion = try container.decodeIfPresent(Int.self, forKey: .configVersion)
        gatewayRunning = try container.decodeIfPresent(Bool.self, forKey: .gatewayRunning)
        gatewayState = try container.decodeIfPresent(String.self, forKey: .gatewayState)
        platforms = try container.decodeIfPresent(
            [String: PlatformState].self, forKey: .platforms
        ) ?? [:]
    }
}

// MARK: - GET /api/config（Dashboard 配置，需登录会话）

/// 实测样本（节选）：{"model": "anthropic/claude-opus-4.6",
/// "providers": {}, "toolsets": ["hermes-cli"], ...}
/// 总览页只取摘要：当前模型、已配提供商名、工具集；全量配置
/// 管理是里程碑 2 的事，此处不建模其余字段。
public struct ServerConfigSummary: Decodable, Sendable {
    public let model: String?
    public let providerNames: [String]
    public let toolsets: [String]

    private struct EmptyObject: Decodable {}

    enum CodingKeys: String, CodingKey {
        case model
        case providers
        case toolsets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        let providers = try container.decodeIfPresent(
            [String: EmptyObject].self, forKey: .providers
        ) ?? [:]
        providerNames = providers.keys.sorted()
        toolsets = try container.decodeIfPresent([String].self, forKey: .toolsets) ?? []
    }
}

// MARK: - GET /v1/models（API Server，Bearer API 密钥）

/// 实测样本：{"object": "list", "data": [{"id": "hermes-agent", ...}]}
public struct ModelsResponse: Decodable, Sendable {
    public struct ModelItem: Decodable, Sendable {
        public let id: String
    }

    public let data: [ModelItem]

    public var ids: [String] { data.map(\.id) }
}

// MARK: - POST /v1/chat/completions（OpenAI 兼容）

/// 多模态内容部分（OpenAI 格式）：文本或图片 URL
/// （data: base64 或 https）。0.2.1 聊天附件用。
public enum ChatContentPart: Codable, Sendable, Equatable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey {
        case type, text, imageURL = "image_url"
    }

    private struct ImageURLBody: Codable, Sendable, Equatable {
        let url: String
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "image_url" {
            let body = try container.decode(ImageURLBody.self, forKey: .imageURL)
            self = .imageURL(body.url)
        } else {
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLBody(url: url), forKey: .imageURL)
        }
    }
}

public struct ChatMessage: Codable, Sendable, Equatable {
    public let role: String
    /// 纯文本视图：多模态消息时为其中文本部分的拼接（历史回放用）
    public let content: String
    /// 多模态部分：非 nil 时 content 按 parts 数组编码（OpenAI 格式）
    public let parts: [ChatContentPart]?

    public init(role: String, content: String) {
        self.role = role
        self.content = content
        self.parts = nil
    }

    /// 带图片的用户消息：文本可为空（纯图片消息）
    public init(role: String, text: String, imageDataURLs: [String]) {
        self.role = role
        self.content = text
        var parts: [ChatContentPart] = []
        if !text.isEmpty {
            parts.append(.text(text))
        }
        parts.append(contentsOf: imageDataURLs.map(ChatContentPart.imageURL))
        self.parts = parts.isEmpty ? nil : parts
    }

    private enum CodingKeys: String, CodingKey {
        case role, content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        if let text = try? container.decode(String.self, forKey: .content) {
            content = text
            parts = nil
        } else {
            let decoded = try container.decode([ChatContentPart].self, forKey: .content)
            parts = decoded
            content = decoded.compactMap { part in
                if case .text(let text) = part { return text }
                return nil
            }.joined(separator: "\n")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if let parts {
            try container.encode(parts, forKey: .content)
        } else {
            try container.encode(content, forKey: .content)
        }
    }

    public static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: "user", content: content)
    }

    public static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: "assistant", content: content)
    }
}

/// 流式分片（stream=true 时逐行 data: 推送）：
/// {"choices": [{"delta": {"content": "…"}, "finish_reason": null}]}
/// 思考增量走独立字段（0.5.1，§32）：
/// {"choices": [{"delta": {"reasoning_content": "…"}}]}
public struct ChatStreamChunk: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public struct Delta: Decodable, Sendable {
            public let content: String?
            public let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        public let delta: Delta?
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    public let choices: [Choice]

    /// 本分片的文本增量（无内容分片返回 nil）
    public var deltaText: String? {
        guard let text = choices.first?.delta?.content, !text.isEmpty else { return nil }
        return text
    }

    /// 本分片的思考增量（无思考分片返回 nil）。形态定案
    /// （0.5.1 前置核查，§32）：Hermes 网关 /v1/chat/completions
    /// 流式把 agent 的 reasoning_callback 结构化增量以
    /// DeepSeek 风格独立字段 delta.reasoning_content 下发
    /// （gateway/platforms/api_server_openai_routes.py
    /// @ v0.23.0 生产同版源码坐实），非 <think> 内联
    public var deltaReasoning: String? {
        guard let text = choices.first?.delta?.reasoningContent,
              !text.isEmpty else { return nil }
        return text
    }
}

/// 流式通道事件（0.5.1，§32）：正文与思考分开走——
/// 客户端 chatStream 的元素类型，视图层按通道分别过
/// 发布闸与呈现（正文进气泡、思考进折叠单元）
public enum ChatStreamEvent: Equatable, Sendable {
    case content(String)
    case reasoning(String)
}
