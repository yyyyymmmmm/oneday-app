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

public struct ChatMessage: Codable, Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
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
public struct ChatStreamChunk: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public struct Delta: Decodable, Sendable {
            public let content: String?
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
}
