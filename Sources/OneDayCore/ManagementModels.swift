import Foundation

// MARK: - P10 管理面模型（0.16.0）
//
// 五个面的 DTO 与纯派生，形状证据分级（2026-11-09 主
// 代理只读联调实查，服务器内存 49% 时取样）：
// - MCP 列表、会话搜索：生产 GET 实测原样（fixture 逐
//   字收进 ManagementModelsTests），字段按实样钉死、
//   未知键容忍。
// - 审批已决：桥 GET /decisions 已上线现成面，DTO 复
//   用 P7 的 WriteGateDecisionRecord（MemoryBridge-
//   Models.swift），本文件只补展示派生。
// - 技能商店 search/sources/preview：端点在 OpenAPI
//   在册，但本部署实测 30s/120s 均无响应（服务端抓外
//   部注册表出网受阻），响应形状无从实样——DTO 按
//   identifier 语义（official/<类>/<名> 等，官方文档
//   在案）做多形宽容解码（results/skills/items 键与裸
//   数组都收），字段全可选、缺失不猜。

// MARK: - 技能商店（/api/skills/hub/*）

public struct HubSkill: Decodable, Sendable, Identifiable {
    /// 来源限定标识（如 official/security/1password），
    /// 安装入参就是它
    public let identifier: String
    public let name: String?
    public let description: String?
    public let source: String?
    public let author: String?
    public let version: String?

    public var id: String { identifier }

    /// identifier 末段＝装好后在 /api/skills 里的名字
    public var installedName: String {
        identifier.split(separator: "/").last.map(String.init) ?? identifier
    }

    /// 展示名：服务端 name 优先，否则 identifier 末段
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return installedName
    }

    /// 来源标签：source 字段优先，否则 identifier 首段
    public var sourceLabel: String {
        if let source, !source.isEmpty { return source }
        return identifier.split(separator: "/").first.map(String.init) ?? "hub"
    }

    /// 是否已在已装名单里（按装后名对账）
    public func isInstalled(installedNames: Set<String>) -> Bool {
        installedNames.contains(installedName)
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, id, name, description, source, author, version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try container.decodeIfPresent(String.self, forKey: .identifier)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        let rawName = try container.decodeIfPresent(String.self, forKey: .name)
        guard let resolved = rawID ?? rawName, !resolved.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .identifier, in: container,
                debugDescription: "hub skill without identifier/name"
            )
        }
        identifier = resolved
        name = rawName
        description = try container.decodeIfPresent(String.self, forKey: .description)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        version = try container.decodeIfPresent(String.self, forKey: .version)
    }

    public init(
        identifier: String, name: String? = nil, description: String? = nil,
        source: String? = nil, author: String? = nil, version: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.description = description
        self.source = source
        self.author = author
        self.version = version
    }
}

/// hub 搜索响应多形收口：{results:[…]} / {skills:[…]} /
/// {items:[…]} / 裸数组，四形任一
public struct HubSearchResponse: Decodable, Sendable {
    public let results: [HubSkill]

    private enum CodingKeys: String, CodingKey {
        case results, skills, items
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            for key in [CodingKeys.results, .skills, .items] {
                if let found = try container.decodeIfPresent(
                    [HubSkill].self, forKey: key
                ) {
                    results = found
                    return
                }
            }
        }
        let single = try decoder.singleValueContainer()
        results = try single.decode([HubSkill].self)
    }
}

public struct HubSource: Decodable, Sendable, Identifiable {
    public let name: String
    public let label: String?
    public let skillCount: Int?

    public var id: String { name }
    public var displayLabel: String {
        if let label, !label.isEmpty { return label }
        return name
    }

    private enum CodingKeys: String, CodingKey {
        case name, id, source, label, title
        case skillCount = "skill_count"
        case count, total
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let resolved = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .source)
        guard let resolved, !resolved.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .name, in: container,
                debugDescription: "hub source without name"
            )
        }
        name = resolved
        label = try container.decodeIfPresent(String.self, forKey: .label)
            ?? container.decodeIfPresent(String.self, forKey: .title)
        skillCount = try container.decodeIfPresent(Int.self, forKey: .skillCount)
            ?? container.decodeIfPresent(Int.self, forKey: .count)
            ?? container.decodeIfPresent(Int.self, forKey: .total)
    }

    public init(name: String, label: String? = nil, skillCount: Int? = nil) {
        self.name = name
        self.label = label
        self.skillCount = skillCount
    }
}

/// hub 来源响应多形收口：{sources:[…]} / 裸数组
public struct HubSourcesResponse: Decodable, Sendable {
    public let sources: [HubSource]

    private enum CodingKeys: String, CodingKey {
        case sources, results
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            for key in [CodingKeys.sources, .results] {
                if let found = try container.decodeIfPresent(
                    [HubSource].self, forKey: key
                ) {
                    sources = found
                    return
                }
            }
        }
        let single = try decoder.singleValueContainer()
        sources = try single.decode([HubSource].self)
    }
}

/// hub 预览：正文键名未实样证，content / skill_md /
/// readme / markdown 四键任一收；files 收字符串数组或
/// {path|name} 对象数组（只取名字上屏）
public struct HubPreview: Decodable, Sendable {
    public let identifier: String?
    public let name: String?
    public let description: String?
    public let content: String?
    public let files: [String]

    public var hasContent: Bool {
        content.map { !$0.isEmpty } ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, name, description, content, files
        case skillMD = "skill_md"
        case readme, markdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        content = try container.decodeIfPresent(String.self, forKey: .content)
            ?? container.decodeIfPresent(String.self, forKey: .skillMD)
            ?? container.decodeIfPresent(String.self, forKey: .readme)
            ?? container.decodeIfPresent(String.self, forKey: .markdown)
        if let names = try? container.decodeIfPresent(
            [String].self, forKey: .files
        ) {
            files = names
        } else if let raw = try? container.decodeIfPresent(
            [JSONValue].self, forKey: .files
        ) {
            files = raw.compactMap { value -> String? in
                switch value {
                case .string(let text):
                    return text
                case .object(let object):
                    if case .string(let path)? = object["path"] { return path }
                    if case .string(let name)? = object["name"] { return name }
                    return nil
                default:
                    return nil
                }
            }
        } else {
            files = []
        }
    }

    public init(
        identifier: String? = nil, name: String? = nil,
        description: String? = nil, content: String? = nil,
        files: [String] = []
    ) {
        self.identifier = identifier
        self.name = name
        self.description = description
        self.content = content
        self.files = files
    }
}

// MARK: - MCP 连接（/api/mcp/servers*）

/// 生产实样（2026-11-09 只读联调）：{"name":"box",
/// "transport":"http","url":"https://mcp.box.simular.
/// ai/mcp","command":null,"args":[],"env":{},
/// "auth":"header","enabled":true,"tools":null,
/// "source":"plugin","plugin":"box"}——args/env/tools
/// 不上屏不建模，未知键解码自动忽略
public struct MCPServerItem: Decodable, Sendable, Identifiable {
    public let name: String
    public let transport: String?
    public let url: String?
    public let command: String?
    public let enabled: Bool
    /// "plugin"＝插件预置（非用户手配），其余/缺失＝手动配置
    public let source: String?
    public let plugin: String?

    public var id: String { name }

    public var isPluginProvided: Bool { source == "plugin" }

    /// 来源人话：插件预置的如实标插件名，施工图 P10 口径
    public var originLabel: String {
        if isPluginProvided {
            if let plugin, !plugin.isEmpty {
                return "插件预置 · \(plugin)"
            }
            return "插件预置"
        }
        return "手动配置"
    }

    /// 连接端点行：http 类给 url，stdio 类给命令
    public var endpointLine: String? {
        if let url, !url.isEmpty { return url }
        if let command, !command.isEmpty { return command }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case name, transport, url, command, enabled, source, plugin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        transport = try container.decodeIfPresent(String.self, forKey: .transport)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        source = try container.decodeIfPresent(String.self, forKey: .source)
        plugin = try container.decodeIfPresent(String.self, forKey: .plugin)
    }

    public init(
        name: String, transport: String? = nil, url: String? = nil,
        command: String? = nil, enabled: Bool = true,
        source: String? = nil, plugin: String? = nil
    ) {
        self.name = name
        self.transport = transport
        self.url = url
        self.command = command
        self.enabled = enabled
        self.source = source
        self.plugin = plugin
    }
}

/// MCP 列表响应：{servers:[…]} 或裸数组
public struct MCPServersResponse: Decodable, Sendable {
    public let servers: [MCPServerItem]

    private enum CodingKeys: String, CodingKey {
        case servers
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let found = try container.decodeIfPresent(
               [MCPServerItem].self, forKey: .servers
           ) {
            servers = found
            return
        }
        let single = try decoder.singleValueContainer()
        servers = try single.decode([MCPServerItem].self)
    }
}

/// MCP 测试回执：形状未实样（POST 属写面、本包未对生
/// 产发），ok/status/message/error/tools 多键宽容收，
/// 成败判定只认显式信号——皆缺时不判成功（与盒终端
/// succeeded 同口径）
public struct MCPTestResult: Decodable, Sendable {
    public let ok: Bool?
    public let status: String?
    public let message: String?
    public let error: String?
    public let toolCount: Int?

    public var succeeded: Bool {
        if let ok { return ok }
        guard let status else { return false }
        return ["ok", "success", "succeeded", "connected", "healthy"]
            .contains(status.lowercased())
    }

    public var displayMessage: String? {
        if let message, !message.isEmpty { return message }
        if let error, !error.isEmpty { return error }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case ok, status, message, error, tools
        case toolCount = "tool_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        if let count = try container.decodeIfPresent(Int.self, forKey: .toolCount) {
            toolCount = count
        } else if let tools = try? container.decodeIfPresent(
            [JSONValue].self, forKey: .tools
        ) {
            toolCount = tools.count
        } else {
            toolCount = nil
        }
    }

    public init(
        ok: Bool? = nil, status: String? = nil, message: String? = nil,
        error: String? = nil, toolCount: Int? = nil
    ) {
        self.ok = ok
        self.status = status
        self.message = message
        self.error = error
        self.toolCount = toolCount
    }
}

// MARK: - 会话搜索（GET /api/sessions/search）

/// 生产实样（2026-11-09 只读联调，q=蓝鲸命中 R1 会
/// 话）：results[] 元素带 snippet（命中文本）/role
/// （命中消息的角色）/preview（首条用户消息）/title，
/// 时间是 epoch 秒浮点
public struct SessionSearchHit: Decodable, Sendable, Identifiable {
    public let sessionID: String
    public let title: String?
    public let snippet: String?
    public let preview: String?
    public let role: String?
    public let source: String?
    public let model: String?
    public let profile: String?
    public let startedAt: Double?
    public let messageCount: Int?

    public var id: String { sessionID }

    public var startedDate: Date? {
        startedAt.map { Date(timeIntervalSince1970: $0) }
    }

    /// 标题口径与会话列表同源心智：服务端 title 优先，
    /// 缺失时预览，再缺才是未命名
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let preview, !preview.isEmpty { return preview }
        return "未命名会话"
    }

    /// 命中角色人话：只译已知两值，其余原文不猜
    public var roleLabel: String? {
        switch role {
        case "user": return "用户消息"
        case "assistant": return "助手消息"
        default: return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case title, snippet, preview, role, source, model, profile
        case sessionID = "session_id"
        case fallbackID = "id"
        case startedAt = "started_at"
        case messageCount = "message_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let resolved = try container.decodeIfPresent(String.self, forKey: .sessionID)
            ?? container.decodeIfPresent(String.self, forKey: .fallbackID)
        guard let resolved, !resolved.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .sessionID, in: container,
                debugDescription: "search hit without session id"
            )
        }
        sessionID = resolved
        title = try container.decodeIfPresent(String.self, forKey: .title)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        startedAt = try container.decodeIfPresent(Double.self, forKey: .startedAt)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount)
    }

    public init(
        sessionID: String, title: String? = nil, snippet: String? = nil,
        preview: String? = nil, role: String? = nil, source: String? = nil,
        model: String? = nil, profile: String? = nil,
        startedAt: Double? = nil, messageCount: Int? = nil
    ) {
        self.sessionID = sessionID
        self.title = title
        self.snippet = snippet
        self.preview = preview
        self.role = role
        self.source = source
        self.model = model
        self.profile = profile
        self.startedAt = startedAt
        self.messageCount = messageCount
    }
}

public struct SessionSearchResponse: Decodable, Sendable {
    public let results: [SessionSearchHit]

    private enum CodingKeys: String, CodingKey {
        case results
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent(
            [SessionSearchHit].self, forKey: .results
        ) ?? []
    }
}

// MARK: - 会话清理（POST /api/sessions/prune）

/// prune 回执的条数提取（0.18.0）：回执形状未在
/// OpenAPI 里定死（空 schema），多键宽容取数——
/// deleted/count/matched/pruned/removed 任一数字键
/// 命中即用，可再嵌一层 result；全落空返回 nil，
/// 界面如实显「已执行、条数未回」，不许编数。
/// dry_run 与真跑共用同一提取口径。
public enum SessionPruneReceipt {
    private static let countKeys = [
        "deleted", "deleted_count", "count",
        "matched", "matched_count", "pruned", "removed",
    ]

    public static func count(from value: JSONValue) -> Int? {
        guard case .object(let dict) = value else { return nil }
        for key in countKeys {
            if case .number(let number)? = dict[key] {
                return Int(number)
            }
        }
        if case .object(let inner)? = dict["result"] {
            return count(from: .object(inner))
        }
        return nil
    }
}

// MARK: - 档案导出回执（POST /api/profiles/{name}/export）

/// 回执形状未实样（POST 属写面、本包未对生产发）：
/// 档案包在服务器上的引用键多形收（path/output/
/// archive/file 任一），皆缺时引用为空——界面如实显
/// 「已生成，但服务端没回路径」，不编造路径
public struct ProfileExportResult: Decodable, Sendable {
    public let archiveReference: String?

    private enum CodingKeys: String, CodingKey {
        case path, output, archive, file
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        archiveReference = try container.decodeIfPresent(String.self, forKey: .path)
            ?? container.decodeIfPresent(String.self, forKey: .output)
            ?? container.decodeIfPresent(String.self, forKey: .archive)
            ?? container.decodeIfPresent(String.self, forKey: .file)
    }

    public init(archiveReference: String?) {
        self.archiveReference = archiveReference
    }
}

// MARK: - 审批已决历史展示派生（DTO 本体在 MemoryBridgeModels）

public extension WriteGateDecisionRecord {
    /// 裁决人话：只译桥的两个原值，未知值回落原文不猜
    var decisionLabel: String {
        if isApproved { return "已批准" }
        if isRejected { return "已驳回" }
        return decision
    }

    /// 来源人话（与待批卡同一译表 WriteGateLabels）
    var originText: String {
        WriteGateLabels.originLabel(origin)
    }
}
