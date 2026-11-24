import Foundation

/// 台账 161/164 的服务端深口模型（Hermes 0.23.0 冻
/// 结 OpenAPI＋部署版路由源码实证，2026-11-21）：
/// - 161：GET /api/sessions/{id}/timeline（prompt 元
///   数据＋row_id 寻址）与 GET .../messages/around
///   （自某 prompt 起的有界展示页）；
/// - 164：GET /api/learning/graph（学到的技能＋记忆
///   块图谱）与 GET/PUT/DELETE /api/learning/node。
/// 响应体在 OpenAPI 里是自由形态——解码一律宽容：
/// 已知键逐字对齐实证来源，未知键忽略、可选键缺失
/// 不判死；timeline/node 这类形态未被冻结件钉死的
/// 面走 JSONValue 提取（多候选键），宁可少拿信息、
/// 不可因键名漂移整面报废（判定纯函数可单测）。

// MARK: - 161 时间线

/// 会话时间线一页：entries 为 prompt 条目（时序），
/// nextCursor 是下一页的 after_row_id（部署版路由
/// docstring 口径：stable logical first-row id）
public struct SessionTimelinePage: Sendable, Equatable {
    public let entries: [SessionTimelineEntry]
    public let nextCursor: Int64?

    public init(entries: [SessionTimelineEntry], nextCursor: Int64?) {
        self.entries = entries
        self.nextCursor = nextCursor
    }

    /// 条目数组的候选键（形态未钉死，按实证优先级）：
    /// timeline 本体语义即条目列，entries 为首选
    private static let entryKeys = ["entries", "timeline", "prompts", "items"]
    private static let cursorKeys = ["next_cursor", "nextCursor"]

    /// 从原始 JSON 提取（顶层须为对象；条目列缺失
    /// → 空页，不抛错——调用方据空页如实收官）
    public static func extract(from value: JSONValue) -> SessionTimelinePage {
        guard case .object(let root) = value else {
            return SessionTimelinePage(entries: [], nextCursor: nil)
        }
        var rawEntries: [JSONValue] = []
        for key in entryKeys {
            if case .array(let items)? = root[key] {
                rawEntries = items
                break
            }
        }
        let entries = rawEntries.compactMap(SessionTimelineEntry.extract)
        var cursor: Int64?
        for key in cursorKeys {
            if let number = deepNumber(root[key]) {
                cursor = Int64(number)
                break
            }
        }
        return SessionTimelinePage(entries: entries, nextCursor: cursor)
    }
}

/// 时间线条目：row_id 是唯一硬字段（around 寻址坐
/// 标，部署版 docstring 明示）；时刻与 prompt 文本
/// 为可选元数据（文本在场时供 161 猎取的直达快路）
public struct SessionTimelineEntry: Sendable, Equatable {
    public let rowID: Int64
    public let timestamp: Double?
    public let text: String?

    public init(rowID: Int64, timestamp: Double?, text: String?) {
        self.rowID = rowID
        self.timestamp = timestamp
        self.text = text
    }

    private static let textKeys = [
        "text", "content", "preview", "title", "prompt",
    ]
    private static let timestampKeys = [
        "timestamp", "created_at", "started_at", "time",
    ]

    public static func extract(from value: JSONValue) -> SessionTimelineEntry? {
        guard case .object(let object) = value,
              let rowNumber = deepNumber(object["row_id"])
        else { return nil }
        var timestamp: Double?
        for key in timestampKeys {
            if let number = deepNumber(object[key]) {
                timestamp = number
                break
            }
        }
        var text: String?
        for key in textKeys {
            if let candidate = object[key]?.stringValue,
               !candidate.isEmpty {
                text = candidate
                break
            }
        }
        return SessionTimelineEntry(
            rowID: Int64(rowNumber), timestamp: timestamp, text: text
        )
    }
}

// MARK: - 161 around 页

/// around 页：与 /messages 同投影的展示消息列（部
/// 署版路由实证：result["messages"] 经同一 _project_
/// for_display），故消息体直接复用 SessionMessage；
/// 页外其余键（锚点/边界标记）本包不消费、忽略
public struct SessionAroundPage: Decodable, Sendable {
    public let sessionID: String?
    public let messages: [SessionMessage]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case messages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decodeIfPresent(
            String.self, forKey: .sessionID
        )
        messages = try container.decodeIfPresent(
            [SessionMessage].self, forKey: .messages
        ) ?? []
    }

    public init(sessionID: String?, messages: [SessionMessage]) {
        self.sessionID = sessionID
        self.messages = messages
    }
}

// MARK: - 161 窗口猎取判定

/// 搜索落点的窗口猎取（台账 161）：服务端搜索命中
/// 不带消息 id（部署版 search 实现实证：命中只有摘
/// 要＋角色），目标行号只能经 timeline 的 prompt
/// row_id 寻址、再以 around 页内容核对。本枚举只
/// 管判定（针的取法与 150 的 SearchTargetResolu-
/// tion 同源同口径），网络与落盘由宿主执行。
public enum AroundWindowHunt {
    /// 探针轮数上限：自最近一轮起逐轮回探的预算，
    /// 耗尽即退回现行落点行为（回补落盘后本地解
    /// 析），不无限打服务端
    public static let maxProbes = 30
    /// around 单页行数（服务端上限 120，取满）
    public static let pageLimit = 120
    /// timeline 单页条数（服务端上限 500，取满）
    public static let timelineLimit = 500

    /// 消息的最小投影：行号＋角色＋正文（判定只需
    /// 这三样，与 SessionMessage 解耦便于单测）
    public struct MessageStub: Equatable, Sendable {
        public let rowID: Int64
        public let role: String
        public let content: String

        public init(rowID: Int64, role: String, content: String) {
            self.rowID = rowID
            self.role = role
            self.content = content
        }
    }

    /// 在一页消息里按摘要找目标行号：口径与 Search-
    /// TargetResolution.targetEntryID 逐条同构（同
    /// 针、同归一、同角色域、同「首个命中」），只
    /// 是坐标换成服务端行号
    public static func targetRowID(
        in messages: [MessageStub], snippet: String?,
        role: String?
    ) -> Int64? {
        guard let snippet,
              let needle = SearchTargetResolution.needle(
                fromSnippet: snippet
              )
        else { return nil }
        let scoped = (role == "user" || role == "assistant")
            ? messages.filter { $0.role == role }
            : messages
        for message in scoped {
            if SearchTargetResolution.normalized(message.content)
                .contains(needle) {
                return message.rowID
            }
        }
        return nil
    }

    /// 直达快路：timeline 条目文本命中针时，该条目
    /// 的 row_id 即目标轮的 prompt 坐标（多见于
    /// user 命中——命中消息本体就是 prompt）；命
    /// 中不了返回 nil、走逐轮探针
    public static func directPromptRowID(
        entries: [SessionTimelineEntry], snippet: String?,
        role: String?
    ) -> Int64? {
        guard role == "user" || role == nil,
              let snippet,
              let needle = SearchTargetResolution.needle(
                fromSnippet: snippet
              )
        else { return nil }
        for entry in entries {
            guard let text = entry.text else { continue }
            if SearchTargetResolution.normalized(text)
                .contains(needle) {
                return entry.rowID
            }
        }
        return nil
    }

    /// 探针次序：直达行号（在场时）置首，其后按
    /// row_id 自大到小（最近一轮先探——搜索命中偏
    /// 近、且导入已先落最新页，猎取只补未落区）；
    /// 去重后截到 maxProbes
    public static func probeOrder(
        promptRowIDs: [Int64], directRowID: Int64?
    ) -> [Int64] {
        var seen = Set<Int64>()
        var order: [Int64] = []
        if let directRowID {
            seen.insert(directRowID)
            order.append(directRowID)
        }
        for rowID in promptRowIDs.sorted(by: >) {
            if seen.insert(rowID).inserted {
                order.append(rowID)
            }
        }
        return Array(order.prefix(maxProbes))
    }
}

// MARK: - 164 学习图谱

/// 学习图谱（GET /api/learning/graph）：节点＝学到
/// 的技能＋记忆块，另带记忆卡列（memory）与边/簇/
/// 统计（本包呈现只消费节点与记忆卡，其余宽容解
/// 码备查）。字段形态据该特性源头实现实证（部署
/// 版 OpenAPI 描述与之逐字同口径）
public struct LearningGraph: Decodable, Sendable, Equatable {
    public let nodes: [LearningNode]
    public let memoryCards: [LearningMemoryCard]
    public let edges: [LearningEdge]

    enum CodingKeys: String, CodingKey {
        case nodes, edges
        case memoryCards = "memory"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try container.decodeIfPresent(
            [LearningNode].self, forKey: .nodes
        ) ?? []
        memoryCards = try container.decodeIfPresent(
            [LearningMemoryCard].self, forKey: .memoryCards
        ) ?? []
        edges = try container.decodeIfPresent(
            [LearningEdge].self, forKey: .edges
        ) ?? []
    }

    public init(
        nodes: [LearningNode],
        memoryCards: [LearningMemoryCard],
        edges: [LearningEdge]
    ) {
        self.nodes = nodes
        self.memoryCards = memoryCards
        self.edges = edges
    }

    public static let empty = LearningGraph(
        nodes: [], memoryCards: [], edges: []
    )

    /// 技能节点（kind=skill）与记忆节点（kind=memory）
    public var skillNodes: [LearningNode] {
        nodes.filter { $0.kind == "skill" }
    }
    public var memoryNodes: [LearningNode] {
        nodes.filter { $0.kind == "memory" }
    }

    /// 记忆节点 → 对应记忆卡：节点 id 形如 memory:
    /// {source}:{全局序号}，序号即 memoryCards 下标
    /// （图谱组装实证：节点与卡同序枚举）；序号越
    /// 界或来源对不上 → nil（呈现退回节点 label）
    public func card(for node: LearningNode) -> LearningMemoryCard? {
        guard node.kind == "memory",
              let index = node.memoryCardIndex,
              memoryCards.indices.contains(index)
        else { return nil }
        let card = memoryCards[index]
        if let source = node.memorySource, card.source != source {
            return nil
        }
        return card
    }
}

/// 图谱节点：id 是 /api/learning/node 的寻址坐标
/// （技能＝技能名、记忆＝memory:{source}:{序号}），
/// 只作内部寻址、永不递给用户看
public struct LearningNode: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let kind: String
    public let memorySource: String?
    public let timestamp: Double?
    public let category: String?
    public let useCount: Int
    public let state: String?
    public let createdBy: String?
    public let pinned: Bool

    enum CodingKeys: String, CodingKey {
        case id, label, kind, memorySource, timestamp, category
        case useCount, state, createdBy, pinned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decodeIfPresent(
            String.self, forKey: .label
        ) ?? ""
        kind = try container.decodeIfPresent(
            String.self, forKey: .kind
        ) ?? ""
        memorySource = try container.decodeIfPresent(
            String.self, forKey: .memorySource
        )
        timestamp = try container.decodeIfPresent(
            Double.self, forKey: .timestamp
        )
        category = try container.decodeIfPresent(
            String.self, forKey: .category
        )
        useCount = try container.decodeIfPresent(
            Int.self, forKey: .useCount
        ) ?? 0
        state = try container.decodeIfPresent(
            String.self, forKey: .state
        )
        createdBy = try container.decodeIfPresent(
            String.self, forKey: .createdBy
        )
        pinned = try container.decodeIfPresent(
            Bool.self, forKey: .pinned
        ) ?? false
    }

    public init(
        id: String, label: String, kind: String,
        memorySource: String? = nil, timestamp: Double? = nil,
        category: String? = nil, useCount: Int = 0,
        state: String? = nil, createdBy: String? = nil,
        pinned: Bool = false
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.memorySource = memorySource
        self.timestamp = timestamp
        self.category = category
        self.useCount = useCount
        self.state = state
        self.createdBy = createdBy
        self.pinned = pinned
    }

    /// 记忆节点 id 尾段的全局序号（memory:{source}:
    /// {序号}）；非此形态 → nil
    public var memoryCardIndex: Int? {
        guard kind == "memory" else { return nil }
        let parts = id.split(separator: ":")
        guard parts.count == 3, parts[0] == "memory",
              let index = Int(parts[2])
        else { return nil }
        return index
    }

    public var timestampDate: Date? {
        timestamp.map { Date(timeIntervalSince1970: $0) }
    }
}

/// 记忆卡（图谱 memory 列）：记忆块的标题＋正文
/// （服务端截到 1200 字——详情全文以 node GET 为准，
/// 卡只作列表预览与 GET 失败时的兜底呈现）
public struct LearningMemoryCard: Decodable, Sendable, Equatable {
    /// 来源："memory"＝备忘（MEMORY.md）、"profile"
    /// ＝关于用户（USER.md）
    public let source: String
    public let timestamp: Double?
    public let title: String
    public let body: String

    enum CodingKeys: String, CodingKey {
        case source, timestamp, title, body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(
            String.self, forKey: .source
        ) ?? "memory"
        timestamp = try container.decodeIfPresent(
            Double.self, forKey: .timestamp
        )
        title = try container.decodeIfPresent(
            String.self, forKey: .title
        ) ?? ""
        body = try container.decodeIfPresent(
            String.self, forKey: .body
        ) ?? ""
    }

    public init(
        source: String, timestamp: Double?,
        title: String, body: String
    ) {
        self.source = source
        self.timestamp = timestamp
        self.title = title
        self.body = body
    }
}

/// 图谱边（呈现本包不画布、只备查）
public struct LearningEdge: Decodable, Sendable, Equatable {
    public let source: String
    public let target: String

    enum CodingKeys: String, CodingKey {
        case source, target
    }

    public init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: CodingKeys.self),
           let source = try object.decodeIfPresent(
            String.self, forKey: .source
           ),
           let target = try object.decodeIfPresent(
            String.self, forKey: .target
           ) {
            self.source = source
            self.target = target
            return
        }
        var container = try decoder.unkeyedContainer()
        source = try container.decode(String.self)
        target = try container.decode(String.self)
    }

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

/// 节点全文（GET /api/learning/node 的编辑预填）：
/// 形态未被冻结件钉死——宽容提取：content 可在顶
/// 层、或嵌在 node 对象里，键名多候选；提不到 →
/// content 为 nil，调用方退回图谱卡面兜底、不假装
/// 拿到全文
public struct LearningNodeContent: Sendable, Equatable {
    public let id: String?
    public let content: String?

    public init(id: String?, content: String?) {
        self.id = id
        self.content = content
    }

    private static let contentKeys = ["content", "text", "body"]

    public static func extract(from value: JSONValue) -> LearningNodeContent {
        guard case .object(let root) = value else {
            if case .string(let text) = value {
                return LearningNodeContent(id: nil, content: text)
            }
            return LearningNodeContent(id: nil, content: nil)
        }
        let id = root["id"]?.stringValue
        if let content = firstContent(in: root) {
            return LearningNodeContent(id: id, content: content)
        }
        if case .object(let node)? = root["node"] {
            return LearningNodeContent(
                id: id ?? node["id"]?.stringValue,
                content: firstContent(in: node)
            )
        }
        return LearningNodeContent(id: id, content: nil)
    }

    private static func firstContent(
        in object: [String: JSONValue]
    ) -> String? {
        for key in contentKeys {
            if let text = object[key]?.stringValue {
                return text
            }
        }
        return nil
    }
}

// MARK: - 取值小口（文件内私有）

/// JSONValue 数值取值（字符串形态的数字也认——服
/// 务端时间戳偶以字符串下发，图谱组装层有同口径
/// 处理）；stringValue 复用 HermesAdminModels 既有
/// 公共定义，不重复声明
private func deepNumber(_ value: JSONValue?) -> Double? {
    switch value {
    case .number(let number): return number
    case .string(let text): return Double(text)
    default: return nil
    }
}
