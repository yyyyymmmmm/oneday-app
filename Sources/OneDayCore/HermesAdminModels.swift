import Foundation

// MARK: - JSONValue（配置/动态字段的通用载体）

/// /api/config 全量配置、记忆 provider 配置值等动态 JSON 的载体：
/// 服务端字段随版本增减，写回时必须原样保留不认识的字段，
/// 不能用强类型模型解一遍再编回去（会丢字段）。
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// 展示用字符串：数字去掉无意义的小数尾，对象/数组不展开
    public var displayString: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value == value.rounded()
                ? String(Int64(value))
                : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .object: return "{…}"
        case .array(let values): return "[\(values.count) 项]"
        case .null: return ""
        }
    }
}

// MARK: - GET /api/memory（记忆状态，需会话）

/// 实测样本（2026-11-08）：{"active": "", "providers": [{"name": "byterover",
/// "description": "…", "available": false, "configured": true,
/// "status": "unavailable", "setup": {…}}],
/// "builtin_files": {"memory": 0, "user": 0}}
/// active 为空串＝没有外部 provider 接管，内置记忆当值。
public struct MemoryStatus: Decodable, Sendable {
    public let active: String?
    public let providers: [MemoryProvider]
    public let builtinFiles: [String: Double]

    public struct MemoryProvider: Decodable, Sendable, Identifiable {
        public let name: String
        public let description: String?
        public let available: Bool?
        public let configured: Bool?
        public let status: String?

        public var id: String { name }
    }

    enum CodingKeys: String, CodingKey {
        case active
        case providers
        case builtinFiles = "builtin_files"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        active = try container.decodeIfPresent(String.self, forKey: .active)
        providers = try container.decodeIfPresent(
            [MemoryProvider].self, forKey: .providers
        ) ?? []
        builtinFiles = try container.decodeIfPresent(
            [String: Double].self, forKey: .builtinFiles
        ) ?? [:]
    }
}

// MARK: - GET /api/memory/providers/{name}/config（provider 配置表单）

/// 实测样本：{"name": "byterover", "label": "ByteRover",
/// "fields": [{"key": "…", "label": "…", "kind": "string",
/// "description": "…", "placeholder": "", "required": false,
/// "value": "", "is_set": false, "options": [], "url": "…"}]}
/// 写回走 PUT 同路径，body {"values": {key: value}}。
public struct MemoryProviderConfig: Decodable, Sendable {
    public let name: String?
    public let label: String?
    public let fields: [Field]

    enum CodingKeys: String, CodingKey {
        case name, label, fields
    }

    public struct Field: Decodable, Sendable, Identifiable {
        public let key: String
        public let label: String?
        public let kind: String?
        public let description: String?
        public let placeholder: String?
        public let required: Bool?
        public let value: JSONValue?
        public let isSet: Bool?
        public let options: [String]?

        public var id: String { key }

        enum CodingKeys: String, CodingKey {
            case key, label, kind, description, placeholder, required, value, options
            case isSet = "is_set"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        fields = try container.decodeIfPresent([Field].self, forKey: .fields) ?? []
    }
}

// MARK: - GET /api/skills（技能列表，需会话）

/// 实测样本：裸数组 [{"name": "…", "description": "…",
/// "category": "…", "locked": false, "enabled": true,
/// "usage": 0, "provenance": "builtin"}]
public struct SkillItem: Decodable, Sendable, Identifiable {
    public let name: String
    public let description: String?
    public let category: String?
    public let locked: Bool?
    public let enabled: Bool?
    public let usage: Double?
    public let provenance: String?

    public var id: String { name }
    public var isEnabled: Bool { enabled ?? true }

    public init(
        name: String, description: String? = nil, category: String? = nil,
        locked: Bool? = nil, enabled: Bool? = nil, usage: Double? = nil,
        provenance: String? = nil
    ) {
        self.name = name
        self.description = description
        self.category = category
        self.locked = locked
        self.enabled = enabled
        self.usage = usage
        self.provenance = provenance
    }
}

// MARK: - GET /api/skills/content?name=（技能内容）

/// 实测样本：{"name": "…", "content": "…", "path": "…"}
public struct SkillContent: Decodable, Sendable {
    public let name: String?
    public let content: String
    public let path: String?
}

// MARK: - /api/cron/jobs（定时任务，需会话）

/// 列表为裸数组。字段口径对官方桌面端类型定义（apps/desktop
/// 的 CronJob 接口）：enabled 必备，schedule 是对象（另有
/// schedule_display 现成展示串），last/next_run_at 是 ISO 串。
/// 创建走 POST（schedule 传字符串），更新走 PUT {"updates": {…}}。
public struct CronJob: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let prompt: String?
    public let scheduleDisplay: String?
    public let scheduleRaw: JSONValue?
    public let enabled: Bool
    public let state: String?
    public let deliver: String?
    public let model: String?
    public let provider: String?
    public let lastRunAt: String?
    public let nextRunAt: String?
    public let lastError: String?

    enum CodingKeys: String, CodingKey {
        case id, name, prompt, enabled, paused, state, deliver, model, provider
        case scheduleDisplay = "schedule_display"
        case scheduleRaw = "schedule"
        case lastRunAt = "last_run_at"
        case nextRunAt = "next_run_at"
        case lastError = "last_error"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        scheduleDisplay = try container.decodeIfPresent(String.self, forKey: .scheduleDisplay)
        scheduleRaw = try container.decodeIfPresent(JSONValue.self, forKey: .scheduleRaw)
        // enabled 缺失时用 paused 反推（旧形态兼容），再缺默认启用
        if let value = try container.decodeIfPresent(Bool.self, forKey: .enabled) {
            enabled = value
        } else if let paused = try container.decodeIfPresent(Bool.self, forKey: .paused) {
            enabled = !paused
        } else {
            enabled = true
        }
        state = try container.decodeIfPresent(String.self, forKey: .state)
        deliver = try container.decodeIfPresent(String.self, forKey: .deliver)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        lastRunAt = try container.decodeIfPresent(String.self, forKey: .lastRunAt)
        nextRunAt = try container.decodeIfPresent(String.self, forKey: .nextRunAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    /// 计划展示串：优先服务端 schedule_display，其次从
    /// schedule 对象/字符串里取可读字段，都没有给占位。
    public var scheduleText: String {
        if let scheduleDisplay, !scheduleDisplay.isEmpty {
            return scheduleDisplay
        }
        switch scheduleRaw {
        case .string(let value):
            return value
        case .object(let object):
            for key in ["expression", "expr", "cron", "display", "summary"] {
                if let value = object[key]?.stringValue, !value.isEmpty {
                    return value
                }
            }
            return "自定义计划"
        default:
            return "—"
        }
    }

    /// 标题：name 缺失时用 prompt 首行，再缺用 id 前缀
    public var title: String {
        if let name, !name.isEmpty { return name }
        if let prompt, !prompt.isEmpty {
            return String(prompt.split(separator: "\n").first ?? "")
        }
        return "任务 \(id.prefix(8))"
    }
}

// MARK: - /api/sessions（服务端会话，需会话）

/// 实测样本：{"sessions": [{"id": "…", "source": "dashboard",
/// "session_key": "…", "display_name": null, "model": "…",
/// "started_at": 1762…, "ended_at": null, "end_reason": null,
/// "message_count": 7, "tool_call_count": 0, "input_tokens": 0,
/// "output_tokens": 0, …}], "total": 3, "limit": 3, "offset": 0}
/// started_at/ended_at 是 epoch 数值（秒或毫秒，解码后按量级归一）。
/// 定时任务运行记录（/api/cron/jobs/{id}/runs 的 {"runs": […]}）
/// 与本结构同构（官方口径 runs 即 sessions），共用此模型。
/// 0.18.0（A 期专题二）：列表行本就带 title/title_source/
/// archived/pinned（2026-11-09 晚带登录态实拉样本坐实：
/// 28 条中 26 条 llm 标题、2 条 title 为 null 即 Qwen 会
/// 话标题升级失败者）——0.6.1 前客户端只解码 display_
/// name（渠道身份列、API 会话恒 null）从未声明 title，
/// 「接口无 title」系客户端口径误判、就此更正。
public struct ServerSession: Decodable, Sendable, Identifiable {
    public let id: String
    public let source: String?
    public let sessionKey: String?
    public let displayName: String?
    /// 服务端会话标题本体（state.db sessions.title）：
    /// Hermes 两段式自动标题（derived 占位→llm 升级）与
    /// 手动改名的落点，来源看 titleSource
    public let serverTitle: String?
    /// 标题来源：user（手动）/llm（AI 生成）/derived
    /// （占位）；缺失或标题为空时为 nil 或其他值
    public let titleSource: String?
    /// 服务端归档位（PATCH {archived} 的落点，0.18.0
    /// 起归档走服务端本体、本地归档集合只剩迁移输入）
    public let isArchived: Bool?
    /// 服务端置顶位（PATCH {pinned} 的落点）
    public let isPinned: Bool?
    public let model: String?
    public let profile: String?
    public let startedAt: Double?
    public let endedAt: Double?
    public let endReason: String?
    public let messageCount: Int?
    public let toolCallCount: Int?
    public let inputTokens: Double?
    public let outputTokens: Double?
    /// 会话行当前的 mutation 修订号（0.27.0）：Dash-
    /// board 面的会话写（PATCH 改名/归档等）走围栏
    /// 协议——请求须带 expected_revision 等于此值，
    /// 无围栏必 409 client_upgrade_required（本包生
    /// 产实证）；网关面投影可能不带此字段，故可选；
    /// 默认 nil 兼容既有直构点（解码时有键照常取值）
    public let runtimeRevision: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, source, model, profile
        case sessionKey = "session_key"
        case displayName = "display_name"
        case serverTitle = "title"
        case titleSource = "title_source"
        case isArchived = "archived"
        case isPinned = "pinned"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case endReason = "end_reason"
        case messageCount = "message_count"
        case toolCallCount = "tool_call_count"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case runtimeRevision = "runtime_revision"
    }

    /// 开始时间（epoch 量级归一：>1e11 视为毫秒）
    public var startedDate: Date? {
        guard let startedAt else { return nil }
        return Date(timeIntervalSince1970: startedAt > 1e11 ? startedAt / 1000 : startedAt)
    }

    public var endedDate: Date? {
        guard let endedAt else { return nil }
        return Date(timeIntervalSince1970: endedAt > 1e11 ? endedAt / 1000 : endedAt)
    }

    /// 是否活跃：没有结束时间即仍在进行
    public var isActive: Bool { endedAt == nil }

    /// 标题：display_name 优先，其次来源＋时间，最后 id 前缀
    public var title: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let source, !source.isEmpty { return "\(source) 会话" }
        return "会话 \(id.prefix(8))"
    }
}

public struct SessionsPage: Decodable, Sendable {
    public let sessions: [ServerSession]
    public let total: Int?

    public init(from decoder: Decoder) throws {
        // 兼容两种形态：{"sessions": [...]} 与裸数组
        if var container = try? decoder.unkeyedContainer() {
            var items: [ServerSession] = []
            while !container.isAtEnd {
                if let item = try? container.decode(ServerSession.self) {
                    items.append(item)
                }
            }
            sessions = items
            total = items.count
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try container.decodeIfPresent([ServerSession].self, forKey: .sessions) ?? []
        total = try container.decodeIfPresent(Int.self, forKey: .total)
    }

    enum CodingKeys: String, CodingKey {
        case sessions, total
    }
}

/// 建会话回执（POST /api/sessions，0.7.0 主线钦定建线用）：
/// 回执形态以实查为准宽容——{"session": {...}} 包裹与裸
/// 会话对象两种都收，只取建成的会话本体
public struct CreatedSession: Decodable, Sendable {
    public let session: ServerSession

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let wrapped = try? container.decode(ServerSession.self, forKey: .session) {
            session = wrapped
            return
        }
        session = try ServerSession(from: decoder)
    }

    enum CodingKeys: String, CodingKey {
        case session
    }
}

/// 定时任务运行记录：{"runs": [SessionInfo]}（与会话同构）
public struct CronRunsResponse: Decodable, Sendable {
    public let runs: [ServerSession]

    public init(from decoder: Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            var items: [ServerSession] = []
            while !container.isAtEnd {
                if let item = try? container.decode(ServerSession.self) {
                    items.append(item)
                }
            }
            runs = items
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runs = try container.decodeIfPresent([ServerSession].self, forKey: .runs) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case runs
    }
}

// MARK: - GET /api/sessions/{id}/messages（会话消息）

/// 一次工具调用（assistant 消息的 tool_calls 元素，0.8.0
/// P1 富内容）：生产实查形态 {"id": "call_…", "call_id":
/// 同值, "type": "function", "function": {"name": …,
/// "arguments": "JSON 字符串"}}——fixture 冻在
/// RichContentTests（会话 audit-browser-20261109 等）。
public struct SessionToolCall: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// function.arguments 原文（JSON 字符串，可为空串）
    public let arguments: String

    private struct FunctionBody: Decodable {
        let name: String?
        let arguments: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, callID = "call_id", function
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .callID)
            ?? ""
        let function = try container.decodeIfPresent(
            FunctionBody.self, forKey: .function
        )
        name = function?.name ?? ""
        arguments = function?.arguments ?? ""
    }

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// 服务端随消息下发的工具调用展示标签（tool_call_labels，
/// 0.8.0 实查：仅部分消息带）：{"<call_id>": [{"kind":
/// "mcp", "app": "Box", "action": "browser navigate",
/// "text": "Box · browser navigate", "name":
/// "mcp__box__browser_navigate", …}]}。只取 text/name 作
/// 未知工具的标题兜底，标题主口径仍是客户端中文映射。
public struct SessionToolCallLabel: Decodable, Sendable, Equatable {
    public let text: String?
    public let name: String?

    public init(text: String?, name: String?) {
        self.text = text
        self.name = name
    }
}

/// 实测样本：{"session_id": "…", "profile": "default",
/// "messages": [{"id": 1, "role": "user", "content": "…",
/// "timestamp": 1762…, …}]}
public struct SessionMessage: Decodable, Sendable, Identifiable {
    public let id: Double
    public let role: String
    public let content: String
    public let timestamp: Double?
    /// assistant 行的工具调用（0.8.0 起解码；此前只解四
    /// 字段、工具数据整段丢弃）
    public let toolCalls: [SessionToolCall]
    /// tool 行回联键（tool_call_id）与真实工具名
    /// （tool_name；经 tool_call 间接层的行也带真实名，
    /// 生产实查坐实——配对与分类都以它为准）
    public let toolCallID: String?
    public let toolName: String?
    /// 服务端展示标签（按 call id 索引，可缺）
    public let toolCallLabels: [String: [SessionToolCallLabel]]
    /// 思考全文（0.31.0 起解码；服务端 _message_
    /// response 的 safe_keys 本就含 reasoning 与
    /// reasoning_content，此前客户端未解。run 对账
    /// 落定时思考以此回填——直播 events 无思考流）
    public let reasoningContent: String?
    public let reasoning: String?
    /// 服务端展示分类（failed_turn＝失败边界行、
    /// hidden＝不呈现；0.31.0 起解码，run 落定提取
    /// 据此分型）
    public let displayKind: String?

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
        case toolName = "tool_name"
        case toolCallLabels = "tool_call_labels"
        case reasoningContent = "reasoning_content"
        case reasoning
        case displayKind = "display_kind"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 工具调用类消息的 content 可能为 null：整页解码不许被一条打死
        id = try container.decodeIfPresent(Double.self, forKey: .id) ?? 0
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "unknown"
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
        toolCalls = try container.decodeIfPresent(
            [SessionToolCall].self, forKey: .toolCalls
        ) ?? []
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolCallLabels = try container.decodeIfPresent(
            [String: [SessionToolCallLabel]].self, forKey: .toolCallLabels
        ) ?? [:]
        reasoningContent = try container.decodeIfPresent(
            String.self, forKey: .reasoningContent
        )
        reasoning = try container.decodeIfPresent(
            String.self, forKey: .reasoning
        )
        displayKind = try container.decodeIfPresent(
            String.self, forKey: .displayKind
        )
    }

    /// 测试与拼装用直构（解码路径外）
    public init(
        id: Double, role: String, content: String, timestamp: Double? = nil,
        toolCalls: [SessionToolCall] = [], toolCallID: String? = nil,
        toolName: String? = nil,
        toolCallLabels: [String: [SessionToolCallLabel]] = [:],
        reasoningContent: String? = nil, reasoning: String? = nil,
        displayKind: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.toolCallLabels = toolCallLabels
        self.reasoningContent = reasoningContent
        self.reasoning = reasoning
        self.displayKind = displayKind
    }

    public var date: Date? {
        guard let timestamp else { return nil }
        return Date(timeIntervalSince1970: timestamp > 1e11 ? timestamp / 1000 : timestamp)
    }
}

public struct SessionMessagesResponse: Decodable, Sendable {
    public let messages: [SessionMessage]

    enum CodingKeys: String, CodingKey {
        case messages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent([SessionMessage].self, forKey: .messages) ?? []
    }
}

// MARK: - GET /api/env（密钥与环境变量，需会话）

/// 实测样本：顶层是 {KEY: 条目} 字典。条目 {"is_set": true,
/// "redacted_value": "sk-…1234" | null, "description": "…",
/// "url": "…" | null, "category": "provider", "is_password": true,
/// "advanced": false, …}。未设定的键也在列表里（is_set=false），
/// 这是服务端认得的全部变量目录，不是「已存密钥清单」。
public struct EnvVarEntry: Decodable, Sendable, Identifiable {
    public let key: String
    public let isSet: Bool
    public let redactedValue: String?
    public let description: String?
    public let url: String?
    public let category: String?
    public let isPassword: Bool?

    public var id: String { key }
}

/// /api/env 的解码结果：条目序列（已设定在前、同组按名排序），
/// 字典本身无序，展示顺序在此一次定死。
public struct EnvVars: Decodable, Sendable {
    public let entries: [EnvVarEntry]

    private struct RawEntry: Decodable {
        let isSet: Bool?
        let redactedValue: String?
        let description: String?
        let url: String?
        let category: String?
        let isPassword: Bool?

        enum CodingKeys: String, CodingKey {
            case redactedValue = "redacted_value"
            case description, url, category
            case isSet = "is_set"
            case isPassword = "is_password"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try [String: RawEntry](from: decoder)
        entries = raw.map { key, value in
            EnvVarEntry(
                key: key,
                isSet: value.isSet ?? false,
                redactedValue: value.redactedValue,
                description: value.description,
                url: value.url,
                category: value.category,
                isPassword: value.isPassword
            )
        }.sorted { lhs, rhs in
            if lhs.isSet != rhs.isSet { return lhs.isSet }
            return lhs.key < rhs.key
        }
    }
}

// MARK: - GET /api/analytics/usage（用量趋势，需会话）

/// 实测样本：{"daily": [{"day": "2026-11-08", "input_tokens": 0,
/// "output_tokens": 0, "cache_read_tokens": 0, "reasoning_tokens": 0,
/// "estimated_cost": 0.0, "actual_cost": 0.0, "sessions": 0,
/// "api_calls": 0}], "totals": {"total_input": 0, "total_output": 0,
/// "total_sessions": 0, "total_api_calls": 0,
/// "total_estimated_cost": 0.0, …}, "period_days": 7, …}
public struct UsageAnalytics: Decodable, Sendable {
    public let daily: [Day]
    public let totals: Totals

    public struct Day: Decodable, Sendable, Identifiable {
        public let day: String
        public let inputTokens: Double?
        public let outputTokens: Double?
        public let sessions: Int?
        public let apiCalls: Int?
        public let estimatedCost: Double?

        public var id: String { day }
        /// 当日 Token 口径：输入＋输出（缓存读单列不并入）
        public var tokens: Double { (inputTokens ?? 0) + (outputTokens ?? 0) }

        enum CodingKeys: String, CodingKey {
            case day, sessions
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case apiCalls = "api_calls"
            case estimatedCost = "estimated_cost"
        }
    }

    public struct Totals: Decodable, Sendable {
        public let totalInput: Double?
        public let totalOutput: Double?
        public let totalSessions: Int?
        public let totalAPICalls: Int?
        public let totalEstimatedCost: Double?

        public var tokens: Double { (totalInput ?? 0) + (totalOutput ?? 0) }

        public init(
            totalInput: Double?, totalOutput: Double?, totalSessions: Int?,
            totalAPICalls: Int?, totalEstimatedCost: Double?
        ) {
            self.totalInput = totalInput
            self.totalOutput = totalOutput
            self.totalSessions = totalSessions
            self.totalAPICalls = totalAPICalls
            self.totalEstimatedCost = totalEstimatedCost
        }

        enum CodingKeys: String, CodingKey {
            case totalInput = "total_input"
            case totalOutput = "total_output"
            case totalSessions = "total_sessions"
            case totalAPICalls = "total_api_calls"
            case totalEstimatedCost = "total_estimated_cost"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            totalInput = try container.decodeIfPresent(Double.self, forKey: .totalInput)
            totalOutput = try container.decodeIfPresent(Double.self, forKey: .totalOutput)
            totalSessions = try container.decodeIfPresent(Int.self, forKey: .totalSessions)
            totalAPICalls = try container.decodeIfPresent(Int.self, forKey: .totalAPICalls)
            totalEstimatedCost = try container.decodeIfPresent(Double.self, forKey: .totalEstimatedCost)
        }
    }

    enum CodingKeys: String, CodingKey {
        case daily, totals
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        daily = try container.decodeIfPresent([Day].self, forKey: .daily) ?? []
        if let decoded = try container.decodeIfPresent(Totals.self, forKey: .totals) {
            totals = decoded
        } else {
            totals = Totals(
                totalInput: nil, totalOutput: nil, totalSessions: nil,
                totalAPICalls: nil, totalEstimatedCost: nil
            )
        }
    }
}

// MARK: - GET /api/analytics/models（按模型用量，需会话）

/// 实测样本：{"models": [{"model": "deepseek-chat",
/// "provider": "custom", "input_tokens": 0, "output_tokens": 0,
/// "estimated_cost": 0.0, "sessions": 0, "api_calls": 0,
/// "last_used_at": 0, …}], "totals": {…}, "period_days": 7}
public struct ModelAnalytics: Decodable, Sendable {
    public let models: [ModelUsage]

    public struct ModelUsage: Decodable, Sendable, Identifiable {
        public let model: String
        public let provider: String?
        public let inputTokens: Double?
        public let outputTokens: Double?
        public let estimatedCost: Double?
        public let sessions: Int?
        public let apiCalls: Int?

        public var id: String { model }
        public var tokens: Double { (inputTokens ?? 0) + (outputTokens ?? 0) }

        enum CodingKeys: String, CodingKey {
            case model, provider, sessions
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case estimatedCost = "estimated_cost"
            case apiCalls = "api_calls"
        }
    }

    enum CodingKeys: String, CodingKey {
        case models
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = try container.decodeIfPresent([ModelUsage].self, forKey: .models) ?? []
    }
}

// MARK: - GET /api/logs（日志，需会话）

/// 实测样本：{"file": "agent.log", "lines": ["…", "…"]}
/// 行是纯文本；级别/组件筛选由服务端 query 参数完成。
public struct LogsResponse: Decodable, Sendable {
    public let file: String?
    public let lines: [String]

    enum CodingKeys: String, CodingKey {
        case file, lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        lines = try container.decodeIfPresent([String].self, forKey: .lines) ?? []
    }
}

// MARK: - /api/profiles（档案，需会话）

/// 实测样本：{"profiles": [{"name": "default", "path": "…",
/// "is_default": true, "model": "deepseek-chat", "provider": "custom",
/// "has_env": true, "skill_count": 39, "gateway_running": true,
/// "description": "", "display_name": ""}]}
/// 激活档案：GET /api/profiles/active → {"active": "default",
/// "current": "default"}；切换走 POST 同路径 {"name": "…"}。
public struct ProfileItem: Decodable, Sendable, Identifiable {
    public let name: String
    public let isDefault: Bool?
    public let model: String?
    public let provider: String?
    public let skillCount: Int?
    public let gatewayRunning: Bool?
    public let displayName: String?

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, model, provider
        case isDefault = "is_default"
        case skillCount = "skill_count"
        case gatewayRunning = "gateway_running"
        case displayName = "display_name"
    }
}

public struct ProfilesResponse: Decodable, Sendable {
    public let profiles: [ProfileItem]

    enum CodingKeys: String, CodingKey {
        case profiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decodeIfPresent([ProfileItem].self, forKey: .profiles) ?? []
    }
}

public struct ActiveProfileResponse: Decodable, Sendable {
    public let active: String?
    public let current: String?

    public var name: String? { active ?? current }
}

// MARK: - GET /api/egress/status（出口状态，需会话）

/// 实测样本：{"text": "Egress proxy status\n\nEnabled: no\n…\n
/// Listening: no\nProcess: (stopped)\n…"}
/// 出口未启用是正常形态（本机部署即如此），不算异常；
/// 异常只认「已启用但没在听/进程停了」。
public struct EgressStatus: Decodable, Sendable {
    public let text: String

    public var isEnabled: Bool {
        text.contains("Enabled: yes")
    }

    public var isAbnormal: Bool {
        guard isEnabled else { return false }
        return text.contains("Listening: no") || text.contains("Process: (stopped)")
    }
}
