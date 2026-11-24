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
    // 连接自检扩键（DESIGN §357；33/36 共用一次扩好）：
    // 配置最新版号／可自更新旗／总体判定／组件状态／
    // 磁盘与内存压力（advisory，官方口径不入 overall）
    public let latestConfigVersion: Int?
    public let canUpdateHermes: Bool?
    public let overall: String?
    public let components: Components?
    public let disk: PressureInfo?
    public let memory: PressureInfo?

    public struct PlatformState: Decodable, Sendable {
        public let state: String?
        public let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case state
            case errorMessage = "error_message"
        }
    }

    /// 组件状态（官方 web_routers/status.py
    /// `_component_health` 形态：状态枚举＋计数，不带
    /// 正文/路径）
    public struct Components: Decodable, Sendable {
        public let gateway: ComponentState?
        public let dashboard: DashboardComponent?
        public let storage: ComponentState?
        public let platforms: PlatformsComponent?
    }

    public struct ComponentState: Decodable, Sendable {
        public let status: String?
        public let state: String?
        /// storage 损坏时为 "corrupt"（消费方认的唯一
        /// 原因枚举）；其余组件一般缺省
        public let reason: String?
    }

    public struct DashboardComponent: Decodable, Sendable {
        public let status: String?
        public let recentUnhandledErrors: Int?
        public let selftest: String?

        enum CodingKeys: String, CodingKey {
            case status, selftest
            case recentUnhandledErrors = "recent_unhandled_errors"
        }
    }

    public struct PlatformsComponent: Decodable, Sendable {
        public let status: String?
        public let configured: Int?
        public let connected: Int?
    }

    /// 压力信息（gateway disk_status/memory_status 形
    /// 态：pressure 枚举＋粗粒度数值，读不到回 unknown）
    public struct PressureInfo: Decodable, Sendable {
        public let pressure: String?
        public let usedPercent: Double?
        public let freeMB: Double?

        enum CodingKeys: String, CodingKey {
            case pressure
            case usedPercent = "used_percent"
            case freeMB = "free_mb"
        }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case releaseDate = "release_date"
        case configVersion = "config_version"
        case gatewayRunning = "gateway_running"
        case gatewayState = "gateway_state"
        case platforms = "gateway_platforms"
        case latestConfigVersion = "latest_config_version"
        case canUpdateHermes = "can_update_hermes"
        case overall, components, disk, memory
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
        latestConfigVersion = try container.decodeIfPresent(
            Int.self, forKey: .latestConfigVersion
        )
        canUpdateHermes = try container.decodeIfPresent(
            Bool.self, forKey: .canUpdateHermes
        )
        overall = try container.decodeIfPresent(String.self, forKey: .overall)
        components = try container.decodeIfPresent(
            Components.self, forKey: .components
        )
        disk = try container.decodeIfPresent(
            PressureInfo.self, forKey: .disk
        )
        memory = try container.decodeIfPresent(
            PressureInfo.self, forKey: .memory
        )
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
    /// 流式工具调用分片（OpenAI 形态，0.8.0）：同 index
    /// 的 function.name/arguments 分多片到达，客户端累
    /// 积拼装（ToolCallStreamAccumulator）。服务端是否
    /// 下发未经生产实测，防御式解码、无此分片零影响。
    public struct ToolCallFragment: Decodable, Sendable, Equatable {
        public struct FunctionFragment: Decodable, Sendable, Equatable {
            public let name: String?
            public let arguments: String?

            public init(name: String?, arguments: String?) {
                self.name = name
                self.arguments = arguments
            }
        }

        public let index: Int?
        public let id: String?
        public let function: FunctionFragment?

        public init(
            index: Int?, id: String?, function: FunctionFragment?
        ) {
            self.index = index
            self.id = id
            self.function = function
        }
    }

    public struct Choice: Decodable, Sendable {
        public struct Delta: Decodable, Sendable {
            public let content: String?
            public let reasoningContent: String?
            public let toolCalls: [ToolCallFragment]?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
                case toolCalls = "tool_calls"
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

    /// 本分片的工具调用分片（无则 nil）
    public var toolCallFragments: [ToolCallFragment]? {
        guard let fragments = choices.first?.delta?.toolCalls,
              !fragments.isEmpty else { return nil }
        return fragments
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
/// 发布闸与呈现（正文进气泡、思考进折叠单元）。
/// 0.8.0 加工具通道：累积拼装完成的一次工具调用以
/// ToolCard 整体下发（结果不在流内，恒为 nil）。
public enum ChatStreamEvent: Equatable, Sendable {
    case content(String)
    case reasoning(String)
    case toolCall(ToolCard)
}

// MARK: - 设备认领（配对一期，台账 153/160；网关面 /v1/enrollment/*）

/// POST /v1/enrollment/codes 回执（Bearer 鉴权，已登录
/// 侧出码）：码本体只出现这一次、服务端只存盐化哈希；
/// fingerprint 是服务器实例指纹（实例 id 的 sha256 前
/// 16 位），扫码侧认领后必须与二维码里带的指纹对上
/// 才走连接流水线（防码被搬到另一台服务器兑现）
public struct EnrollmentIssue: Decodable, Sendable, Equatable {
    public let code: String
    public let expiresAt: Double
    public let ttlSeconds: Int
    public let fingerprint: String

    enum CodingKeys: String, CodingKey {
        case code
        case expiresAt = "expires_at"
        case ttlSeconds = "ttl_seconds"
        case fingerprint
    }
}

/// POST /v1/enrollment/claim 回执（公开，码即凭据）：
/// 认领成功一次性下发本服务器的登录密钥（凭据落盘
/// 走既有 Keychain 单钥通道，与手填密钥同账一份）
public struct EnrollmentClaim: Decodable, Sendable, Equatable {
    public let apiKey: String
    public let fingerprint: String?

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case fingerprint
    }
}
