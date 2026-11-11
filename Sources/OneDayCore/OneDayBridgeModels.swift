import Foundation

/// oneday-bridge 冻结契约模型（0.11.0，P4 目标＋P5 点子）：
/// 桥是同机 sidecar 的目标/点子仓，基址为当前服务器的
/// `/api/oneday-bridge`，鉴权复用 write-gate 钥匙（与
/// 总览桥同一把、用户零新增粘贴）。契约逐字冻结：
///
/// - GET    /goals → {items:[Goal]}；POST /goals → 201 Goal
/// - PATCH  /goals/{id}（milestones 全量替换）；DELETE → {ok:true}
/// - GET    /ideas → {items:[Idea]}；POST /ideas → 201 Idea
/// - DELETE /ideas/{id} → {ok:true}
/// - 时间一律 epoch 秒（float）；title 空 → 400、id 不存在 → 404
///
/// 本文件只放 DTO＋请求体组装＋纯派生（进度/勾选计划/
/// 转任务计划/本地已转标记编解码），网络与状态在 App 层。

// MARK: - 目标 DTO

public struct BridgeMilestone: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let done: Bool

    public init(id: String, title: String, done: Bool) {
        self.id = id
        self.title = title
        self.done = done
    }
}

/// 目标状态（P2，设计档 §2.4 状态机）：只有 active/
/// completed 两态（学 Muse，无暂停态）；未知值按
/// active 收（宽容解码口径，与点子状态同纪律）
public enum GoalStatus: String, Sendable, Equatable, Codable {
    case active
    case completed

    public static func from(_ raw: String?) -> GoalStatus {
        GoalStatus(rawValue: raw ?? "") ?? .active
    }
}

/// 目标创建来源（P2）：manual＝App 内表单/子目标添加，
/// chat＝对话式创建（桥契约已落，App 入口待智能体侧
/// 写路径接通后开）。未知值按 manual 收
public enum GoalSource: String, Sendable, Equatable, Codable {
    case manual
    case chat

    public static func from(_ raw: String?) -> GoalSource {
        GoalSource(rawValue: raw ?? "") ?? .manual
    }
}

/// 进展条目来源（P2）：user＝用户手记，agent＝智能体
/// 记账。未知值按 user 收
public enum GoalEntrySource: String, Sendable, Equatable, Codable {
    case user
    case agent

    public static func from(_ raw: String?) -> GoalEntrySource {
        GoalEntrySource(rawValue: raw ?? "") ?? .user
    }
}

public struct BridgeGoal: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    /// 契约全形带 note；缺失/null 按空串收（不因备注
    /// 字段漂移整表解码失败）
    public let note: String
    public let milestones: [BridgeMilestone]
    /// epoch 秒（float）
    public let createdAt: Double
    public let updatedAt: Double
    /// P2 四字段：旧载荷（0.33.0 前桥）缺失时按
    /// 「active/未完成/顶层目标/manual」收
    public let status: GoalStatus
    /// 完成时刻（epoch 秒）；未完成为 nil。由桥在状态
    /// 流转时落字，客户端永不自写
    public let completedAt: Double?
    /// 父目标 id；顶层目标为 nil。子目标恰好一层
    public let parentId: String?
    public let source: GoalSource
    /// 分类（0.40.0）：用户创建/编辑时自己选的七类之一；
    /// 存量目标与未选时为 nil（未分类）——未知枚举串同样
    /// 按 nil 收，任何层都不许推断补位
    public let category: GoalCategory?
    /// 最新一条进展条目（桥在 goal 视图里只读嵌入，供
    /// 列表行摘要免 N+1 拉取）；无条目为 nil。它是条目
    /// 流的读穿呈现、不是第二份存储
    public let latestEntry: BridgeGoalEntry?

    public init(
        id: String, title: String, note: String,
        milestones: [BridgeMilestone],
        createdAt: Double, updatedAt: Double,
        status: GoalStatus = .active, completedAt: Double? = nil,
        parentId: String? = nil, source: GoalSource = .manual,
        category: GoalCategory? = nil,
        latestEntry: BridgeGoalEntry? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.milestones = milestones
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.completedAt = completedAt
        self.parentId = parentId
        self.source = source
        self.category = category
        self.latestEntry = latestEntry
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, note, milestones, createdAt, updatedAt
        case status, completedAt, parentId, source, latestEntry
        case category
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        milestones = try container.decodeIfPresent(
            [BridgeMilestone].self, forKey: .milestones
        ) ?? []
        createdAt = try container.decodeIfPresent(
            Double.self, forKey: .createdAt
        ) ?? 0
        updatedAt = try container.decodeIfPresent(
            Double.self, forKey: .updatedAt
        ) ?? 0
        status = GoalStatus.from(
            try container.decodeIfPresent(String.self, forKey: .status)
        )
        completedAt = try container.decodeIfPresent(
            Double.self, forKey: .completedAt
        )
        parentId = try container.decodeIfPresent(
            String.self, forKey: .parentId
        )
        source = GoalSource.from(
            try container.decodeIfPresent(String.self, forKey: .source)
        )
        category = GoalCategory.from(
            try container.decodeIfPresent(String.self, forKey: .category)
        )
        latestEntry = try container.decodeIfPresent(
            BridgeGoalEntry.self, forKey: .latestEntry
        )
    }
}

public struct BridgeGoalsResponse: Decodable, Equatable, Sendable {
    public let items: [BridgeGoal]

    public init(items: [BridgeGoal]) {
        self.items = items
    }
}

// MARK: - 点子 DTO

/// 点子来源（P1，设计档 §1.4）：generated＝生成管道产出，
/// manual＝用户手记。未知值按 manual 收（宽容解码口径）
public enum IdeaSource: String, Sendable, Equatable {
    case generated
    case manual

    public static func from(_ raw: String?) -> IdeaSource {
        IdeaSource(rawValue: raw ?? "") ?? .manual
    }
}

/// 点子状态机（P1，设计档 §1.4）：pending 待阅 →
/// adopted 已采纳（taskId 落字）/ dismissed 已忽略 /
/// expired 已过期，三者皆终态；done 不落字段、由
/// taskId 指向的任务状态在呈现层派生。未知值按 pending 收
public enum IdeaStatus: String, Sendable, Equatable {
    case pending
    case adopted
    case dismissed
    case expired

    public static func from(_ raw: String?) -> IdeaStatus {
        IdeaStatus(rawValue: raw ?? "") ?? .pending
    }
}

/// 点子交付物一条（0.47.0，§117）：详情 sheet「包含
/// 哪些内容」清单的 {name, summary}；桥生成时按内容
/// 给出，旧记录无此字段（空数组收，清单整段不出现）
public struct BridgeIdeaDeliverable: Decodable, Equatable, Sendable {
    public let name: String
    public let summary: String

    public init(name: String, summary: String = "") {
        self.name = name
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case name, summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(
            String.self, forKey: .name
        ) ?? ""
        summary = try container.decodeIfPresent(
            String.self, forKey: .summary
        ) ?? ""
    }
}

public struct BridgeIdea: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    /// 契约全形带 detail；缺失/null 按空串收（同 note 口径）
    public let detail: String
    /// 内容 emoji（0.47.0，§117）：桥按内容选定；旧记
    /// 录为 nil，呈现走 IdeaEmoji 按锚点 kind 兜底
    public let emoji: String?
    /// 交付物清单（0.47.0，§117）：旧记录为空数组
    public let deliverables: [BridgeIdeaDeliverable]
    /// 挂靠目标 id；未挂为 nil
    public let goalId: String?
    /// epoch 秒（float）
    public let createdAt: Double
    /// P1 五字段：旧载荷缺失时按「manual/空依据/pending/
    /// 无任务/不过期」收（0.32.0 前桥不回这些字段）
    public let source: IdeaSource
    /// 生成卡的依据一句；手记卡为空串
    public let evidence: String
    /// 依据指向的素材编号（S/G/M/K/R 编号，轮内编号），可空
    public let evidenceRef: String?
    /// 0.39.0 新增：evidenceRef 解析出的真实锚点
    /// （"<源字母>:<对象 id>"），跨轮去重的键在桥侧；
    /// 旧载荷/手记卡为 nil
    public let anchorId: String?
    /// 0.39.0 新增：忽略原因（目前只有 "tooGeneric"＝用户
    /// 标了「太泛了」）；未标为 nil
    public let dismissReason: String?
    public let status: IdeaStatus
    /// 采纳后回写的 kanban 任务 id；未采纳为 nil。
    /// 这是「已转任务」的服务端真源（取代旧本地标记）
    public let taskId: String?
    /// 生成卡的过期时刻（epoch 秒）；手记卡为 nil＝不过期
    public let expiresAt: Double?

    public init(
        id: String, title: String, detail: String,
        goalId: String?, createdAt: Double,
        source: IdeaSource = .manual, evidence: String = "",
        evidenceRef: String? = nil, anchorId: String? = nil,
        dismissReason: String? = nil,
        status: IdeaStatus = .pending,
        taskId: String? = nil, expiresAt: Double? = nil,
        emoji: String? = nil,
        deliverables: [BridgeIdeaDeliverable] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.emoji = emoji
        self.deliverables = deliverables
        self.goalId = goalId
        self.createdAt = createdAt
        self.source = source
        self.evidence = evidence
        self.evidenceRef = evidenceRef
        self.anchorId = anchorId
        self.dismissReason = dismissReason
        self.status = status
        self.taskId = taskId
        self.expiresAt = expiresAt
    }

    /// 已采纳的呈现判定：状态或任务 id 任一落字即算
    public var isAdopted: Bool {
        status == .adopted || taskId != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, goalId, createdAt
        case source, evidence, evidenceRef, anchorId, dismissReason
        case status, taskId, expiresAt
        case emoji, deliverables
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(
            String.self, forKey: .detail
        ) ?? ""
        emoji = try container.decodeIfPresent(
            String.self, forKey: .emoji
        )
        deliverables = try container.decodeIfPresent(
            [BridgeIdeaDeliverable].self, forKey: .deliverables
        ) ?? []
        goalId = try container.decodeIfPresent(String.self, forKey: .goalId)
        createdAt = try container.decodeIfPresent(
            Double.self, forKey: .createdAt
        ) ?? 0
        source = IdeaSource.from(
            try container.decodeIfPresent(String.self, forKey: .source)
        )
        evidence = try container.decodeIfPresent(
            String.self, forKey: .evidence
        ) ?? ""
        evidenceRef = try container.decodeIfPresent(
            String.self, forKey: .evidenceRef
        )
        anchorId = try container.decodeIfPresent(
            String.self, forKey: .anchorId
        )
        dismissReason = try container.decodeIfPresent(
            String.self, forKey: .dismissReason
        )
        status = IdeaStatus.from(
            try container.decodeIfPresent(String.self, forKey: .status)
        )
        taskId = try container.decodeIfPresent(
            String.self, forKey: .taskId
        )
        expiresAt = try container.decodeIfPresent(
            Double.self, forKey: .expiresAt
        )
    }
}

/// PATCH /ideas/{id} 请求体：桥只许改 status、taskId 与
/// dismissReason 三项；nil 字段不落键（不带＝不改）。回写
/// taskId 时桥侧同时把 status 置 adopted（采纳是事实、
/// 不是请求）；dismissReason 只在转 dismissed 时可带
/// （"tooGeneric"＝用户标「太泛了」，桥计入生成避让）
public struct BridgeIdeaPatchRequest: Encodable, Equatable, Sendable {
    public let status: IdeaStatus?
    public let taskId: String?
    public let dismissReason: String?

    public init(
        status: IdeaStatus? = nil, taskId: String? = nil,
        dismissReason: String? = nil
    ) {
        self.status = status
        self.taskId = taskId
        self.dismissReason = dismissReason
    }

    private enum CodingKeys: String, CodingKey {
        case status, taskId, dismissReason
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(status?.rawValue, forKey: .status)
        try container.encodeIfPresent(taskId, forKey: .taskId)
        try container.encodeIfPresent(
            dismissReason, forKey: .dismissReason
        )
    }
}

// MARK: - 生成管道信息（GET /ideas/generation）

/// 一轮生成记录（桥 meta.ideasGen.history 的行）：状态
/// ok（有产出）/empty（跑空）/failed/skipped 均只记账、
/// 不落卡（设计档 §1.4）
public struct BridgeGenerationRun: Decodable, Equatable, Sendable {
    public let at: Double
    public let trigger: String
    public let status: String
    public let produced: Int
    public let dropped: Int

    private enum CodingKeys: String, CodingKey {
        case at, trigger, status, produced, dropped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decodeIfPresent(Double.self, forKey: .at) ?? 0
        trigger = try container.decodeIfPresent(
            String.self, forKey: .trigger
        ) ?? ""
        status = try container.decodeIfPresent(
            String.self, forKey: .status
        ) ?? ""
        produced = try container.decodeIfPresent(
            Int.self, forKey: .produced
        ) ?? 0
        dropped = try container.decodeIfPresent(
            Int.self, forKey: .dropped
        ) ?? 0
    }

    public init(
        at: Double, trigger: String, status: String,
        produced: Int, dropped: Int
    ) {
        self.at = at
        self.trigger = trigger
        self.status = status
        self.produced = produced
        self.dropped = dropped
    }
}

public struct BridgeGenerationInfo: Decodable, Equatable, Sendable {
    public let lastRunAt: Double?
    public let nextRunAt: Double?
    public let running: Bool
    public let history: [BridgeGenerationRun]

    private enum CodingKeys: String, CodingKey {
        case lastRunAt, nextRunAt, running, history
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastRunAt = try container.decodeIfPresent(
            Double.self, forKey: .lastRunAt
        )
        nextRunAt = try container.decodeIfPresent(
            Double.self, forKey: .nextRunAt
        )
        running = try container.decodeIfPresent(
            Bool.self, forKey: .running
        ) ?? false
        history = try container.decodeIfPresent(
            [BridgeGenerationRun].self, forKey: .history
        ) ?? []
    }

    public init(
        lastRunAt: Double?, nextRunAt: Double?,
        running: Bool, history: [BridgeGenerationRun]
    ) {
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
        self.running = running
        self.history = history
    }
}

// MARK: - 点子页呈现口径（P1，设计档 §1.4 视觉落点）

public enum IdeaBoard {
    /// 待阅分区：pending 才呈现；生成卡在前、手记在后，
    /// 各按 createdAt 倒序（设计档分区顺序定版）
    public static func pendingList(_ ideas: [BridgeIdea]) -> [BridgeIdea] {
        ideas
            .filter { $0.status == .pending }
            .sorted { a, b in
                if (a.source == .generated) != (b.source == .generated) {
                    return a.source == .generated
                }
                return a.createdAt > b.createdAt
            }
    }

    /// 已采纳分区：近 30 天的 adopted，按 createdAt 倒序
    public static func adoptedList(
        _ ideas: [BridgeIdea], now: Double
    ) -> [BridgeIdea] {
        ideas
            .filter {
                $0.status == .adopted
                    && $0.createdAt >= now - 30 * 24 * 3600
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 空态分法：从没生成过（无任何点子且无一轮生成记录）
    /// 与「生成后被清完」（有过记录/有过卡、当前待阅为空）
    /// 是两句不同的话（设计档 §1.4 空态口径）
    public enum EmptyKind: Equatable, Sendable {
        case neverProduced
        case cleared
    }

    public static func emptyKind(
        totalIdeas: Int, lastRunAt: Double?
    ) -> EmptyKind {
        (totalIdeas == 0 && lastRunAt == nil) ? .neverProduced : .cleared
    }

    /// 距过期的整天数（向上取整：还剩不足一天算 1 天）；
    /// 无过期时刻或已过期回 nil/0 由调用方分流
    public static func expiryDaysLeft(
        _ idea: BridgeIdea, now: Double
    ) -> Int? {
        guard let expiresAt = idea.expiresAt else { return nil }
        let seconds = expiresAt - now
        if seconds <= 0 { return 0 }
        return Int(ceil(seconds / 86400))
    }

    /// 采纳行尾的任务状态派生文案：任务列名 done＝已完成，
    /// 其余在办列一律「进行中」；任务读不到（板未拉/已删）
    /// 回 nil、只显「已转任务」不编状态
    public static func taskStatusText(
        idea: BridgeIdea, taskStatusRaw: String?
    ) -> String? {
        guard idea.isAdopted else { return nil }
        guard let raw = taskStatusRaw else { return nil }
        return raw == "done" ? "任务已完成" : "任务进行中"
    }
}

public struct BridgeIdeasResponse: Decodable, Equatable, Sendable {
    public let items: [BridgeIdea]

    public init(items: [BridgeIdea]) {
        self.items = items
    }
}

public struct BridgeOKResponse: Decodable, Equatable, Sendable {
    public let ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

// MARK: - 请求体（POST 新建目标）

/// 新建目标时里程碑只有标题（id 与 done 由服务端定）
public struct BridgeMilestoneDraft: Encodable, Equatable, Sendable {
    public let title: String

    public init(title: String) {
        self.title = title
    }
}

/// POST /goals 请求体：{title, note?, milestones?,
/// parentId?, source?, category?}——可选字段为 nil 时不
/// 落键（合成 Encodable 对 Optional 走 encodeIfPresent）
public struct BridgeGoalCreateRequest: Encodable, Equatable, Sendable {
    public let title: String
    public let note: String?
    public let milestones: [BridgeMilestoneDraft]?
    /// P2：子目标创建带父 id（桥校验父存在且为顶层）
    public let parentId: String?
    /// P2：创建来源；App 表单/子目标添加恒 manual，
    /// chat 只由未来的对话式创建路径带
    public let source: GoalSource?
    /// 0.40.0：分类——分类创建流预置进表单的值（用户在
    /// 表单里可改/可清）；子目标创建不带（恒未分类）
    public let category: GoalCategory?

    public init(
        title: String, note: String?,
        milestones: [BridgeMilestoneDraft]?,
        parentId: String? = nil, source: GoalSource? = nil,
        category: GoalCategory? = nil
    ) {
        self.title = title
        self.note = note
        self.milestones = milestones
        self.parentId = parentId
        self.source = source
        self.category = category
    }

    /// 表单口径收口：标题/备注去首尾空白，备注空→不带
    /// 字段、里程碑空标题行剔除、全空→不带字段
    public static func make(
        title: String, note: String, milestoneTitles: [String],
        parentId: String? = nil, category: GoalCategory? = nil
    ) -> BridgeGoalCreateRequest {
        let trimmedNote = note.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let drafts = milestoneTitles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { BridgeMilestoneDraft(title: $0) }
        return BridgeGoalCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            milestones: drafts.isEmpty ? nil : drafts,
            parentId: parentId,
            source: parentId == nil ? nil : .manual,
            category: category
        )
    }
}

/// PATCH /goals/{id} 状态流转专用体：{status}——状态是
/// 独立动作（列表勾选/详情按钮），不与全量编辑体混发；
/// completedAt 由桥落字，客户端不送时间
public struct BridgeGoalStatusPatchRequest: Encodable, Equatable, Sendable {
    public let status: GoalStatus

    public init(status: GoalStatus) {
        self.status = status
    }
}

/// PATCH /goals/{id} 分类专用体：{category}——与状态同
/// 纪律，分类变更是独立动作（编辑 sheet 里改类别），不
/// 与全量编辑体混发。注意 nil 必须显式编码为 JSON null
/// （「清除分类」是合法动作），不能靠合成 Encodable 的
/// encodeIfPresent 把键省掉——省键在桥侧是「不改」
public struct BridgeGoalCategoryPatchRequest: Encodable, Equatable,
    Sendable {
    public let category: GoalCategory?

    public init(category: GoalCategory?) {
        self.category = category
    }

    private enum CodingKeys: String, CodingKey {
        case category
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let category {
            try container.encode(category, forKey: .category)
        } else {
            try container.encodeNil(forKey: .category)
        }
    }
}

// MARK: - 进展条目与简报 DTO（P2）

/// 目标进展条目：append-only 的事实流（桥
/// /goals/{id}/entries）。条目不可编辑，纠错靠删单条
/// 或补新条（设计档 §2.4 状态机口径）
public struct BridgeGoalEntry: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let goalId: String
    public let body: String
    public let source: GoalEntrySource
    /// epoch 秒（float）
    public let createdAt: Double

    public init(
        id: String, goalId: String, body: String,
        source: GoalEntrySource, createdAt: Double
    ) {
        self.id = id
        self.goalId = goalId
        self.body = body
        self.source = source
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, goalId, body, source, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        goalId = try container.decode(String.self, forKey: .goalId)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        source = GoalEntrySource.from(
            try container.decodeIfPresent(String.self, forKey: .source)
        )
        createdAt = try container.decodeIfPresent(
            Double.self, forKey: .createdAt
        ) ?? 0
    }
}

public struct BridgeGoalEntriesResponse: Decodable, Equatable, Sendable {
    public let items: [BridgeGoalEntry]

    public init(items: [BridgeGoalEntry]) {
        self.items = items
    }
}

/// POST /goals/{id}/entries 请求体：{body, source?}
public struct BridgeGoalEntryCreateRequest: Encodable, Equatable, Sendable {
    public let body: String
    public let source: GoalEntrySource?

    public init(body: String, source: GoalEntrySource? = nil) {
        self.body = body
        self.source = source
    }

    /// 用户手记口径：正文去首尾空白、来源恒 user
    public static func userNote(_ raw: String) -> BridgeGoalEntryCreateRequest {
        BridgeGoalEntryCreateRequest(
            body: raw.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .user
        )
    }
}

/// 目标周简报：桥简报管道每周一封的「信」（桥
/// /goals/{id}/briefings，createdAt 降序）。正文是信件
/// 体、只读呈现，客户端永不改写
public struct BridgeBriefing: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let goalId: String
    /// ISO 周次（如 2026-W46，Asia/Shanghai 口径）
    public let period: String
    public let title: String
    public let body: String
    /// epoch 秒（float）
    public let createdAt: Double

    public init(
        id: String, goalId: String, period: String,
        title: String, body: String, createdAt: Double
    ) {
        self.id = id
        self.goalId = goalId
        self.period = period
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

public struct BridgeBriefingsResponse: Decodable, Equatable, Sendable {
    public let items: [BridgeBriefing]

    public init(items: [BridgeBriefing]) {
        self.items = items
    }
}

// MARK: - 请求体（PATCH 目标：milestones 全量替换）

/// PATCH 里程碑全量替换的单条：已有条带 id（服务端
/// 按 id 对齐）、新建条 id 为 nil 不落键（服务端发新 id）
public struct BridgeMilestonePatch: Encodable, Equatable, Sendable {
    public let id: String?
    public let title: String
    public let done: Bool

    public init(id: String?, title: String, done: Bool) {
        self.id = id
        self.title = title
        self.done = done
    }
}

/// PATCH /goals/{id} 请求体：标题＋备注＋里程碑全量。
/// 冻结合约只点名 milestones 全量替换；标题/备注编辑
/// 同走本端点（编辑保存一次 PATCH 送全形）
public struct BridgeGoalPatchRequest: Encodable, Equatable, Sendable {
    public let title: String
    public let note: String
    public let milestones: [BridgeMilestonePatch]

    public init(
        title: String, note: String,
        milestones: [BridgeMilestonePatch]
    ) {
        self.title = title
        self.note = note
        self.milestones = milestones
    }
}

/// 编辑草稿里的一条里程碑（详情编辑器与计划组装共用形）
public struct MilestoneDraftState: Equatable, Sendable {
    /// 已有条带服务端 id；新建条为 nil
    public let id: String?
    public var title: String
    public var done: Bool

    public init(id: String?, title: String, done: Bool) {
        self.id = id
        self.title = title
        self.done = done
    }
}

/// PATCH 体组装计划（纯函数，单测钉死）：勾选与编辑
/// 保存共用同一条全量替换口径——不做增量 PATCH，
/// 每次都把标题/备注/里程碑全量送出，服务端以此为准
public enum GoalPatchPlan {
    /// 勾选翻转：以服务端现值为底，只翻目标条的 done，
    /// 其余条 id/标题/done 原样全量带回。id 不存在 → nil
    /// （调用方不发请求、不假装成功）
    public static func toggle(
        goal: BridgeGoal, milestoneID: String
    ) -> BridgeGoalPatchRequest? {
        guard goal.milestones.contains(where: { $0.id == milestoneID })
        else { return nil }
        let milestones = goal.milestones.map { milestone in
            BridgeMilestonePatch(
                id: milestone.id,
                title: milestone.title,
                done: milestone.id == milestoneID
                    ? !milestone.done : milestone.done
            )
        }
        return BridgeGoalPatchRequest(
            title: goal.title, note: goal.note, milestones: milestones
        )
    }

    /// 编辑保存：标题/备注取草稿（去首尾空白），里程碑
    /// 取草稿全量（空标题行剔除，与新建口径一致）
    public static func update(
        title: String, note: String, milestones: [MilestoneDraftState]
    ) -> BridgeGoalPatchRequest {
        let kept = milestones
            .map {
                MilestoneDraftState(
                    id: $0.id,
                    title: $0.title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    done: $0.done
                )
            }
            .filter { !$0.title.isEmpty }
        return BridgeGoalPatchRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            milestones: kept.map {
                BridgeMilestonePatch(id: $0.id, title: $0.title, done: $0.done)
            }
        )
    }
}

// MARK: - 进度派生

/// 目标进度（列表卡 x/y 与进度条共用，全 App 只此一处算）
public enum GoalProgress {
    public static func counts(of goal: BridgeGoal) -> (done: Int, total: Int) {
        (
            done: goal.milestones.count(where: { $0.done }),
            total: goal.milestones.count
        )
    }

    /// 进度条填充比例；无里程碑为 0（不拿 0/0 说成完成）
    public static func fraction(of goal: BridgeGoal) -> Double {
        let counts = counts(of: goal)
        guard counts.total > 0 else { return 0 }
        return Double(counts.done) / Double(counts.total)
    }

    /// 列表卡进度短文案：「2/5」
    public static func text(of goal: BridgeGoal) -> String {
        let counts = counts(of: goal)
        return "\(counts.done)/\(counts.total)"
    }
}

// MARK: - 目标呈现口径（P2）

/// 目标列表/详情的呈现派生（纯函数，单测钉死）：分组、
/// 子目标、进展摘要、折叠——视图只渲染这里的结果。
/// 数据真源恒为桥：这里不存任何状态、不做本地标记
/// （审计 R 档口径：不在 App 侧再建副本账）
public enum GoalBoard {
    /// 列表折叠阈值（照 Muse 目标行实测形态：先给 4
    /// 条、余者收进「显示另外N项」）
    public static let foldThreshold = 4

    /// 顶层目标（子目标只在父目标详情里出现，不进列表）
    public static func topLevel(_ goals: [BridgeGoal]) -> [BridgeGoal] {
        goals.filter { $0.parentId == nil }
    }

    /// 某目标的子目标（保持桥的 createdAt 升序）
    public static func children(
        of goalID: String, in goals: [BridgeGoal]
    ) -> [BridgeGoal] {
        goals.filter { $0.parentId == goalID }
    }

    /// 列表分组：进行中/已完成（仅顶层，各组保持桥序）
    public static func grouped(
        _ goals: [BridgeGoal]
    ) -> (active: [BridgeGoal], completed: [BridgeGoal]) {
        let top = topLevel(goals)
        return (
            active: top.filter { $0.status == .active },
            completed: top.filter { $0.status == .completed }
        )
    }

    /// 折叠裁切：未展开时只给前 foldThreshold 条＋隐藏数
    public static func folded<T>(
        _ items: [T], expanded: Bool
    ) -> (visible: [T], hiddenCount: Int) {
        guard !expanded, items.count > foldThreshold else {
            return (items, 0)
        }
        return (
            Array(items.prefix(foldThreshold)),
            items.count - foldThreshold
        )
    }

    /// 行内进展摘要的来源（设计档 §2.4）：最新一条进展
    /// 条目优先；无条目时回既有口径——备注，再无备注而
    /// 有里程碑时给「x/y 里程碑」；全无则空串（行只剩
    /// 标题，不编造近况）
    public static func summary(
        for goal: BridgeGoal, latestEntry: BridgeGoalEntry?
    ) -> String {
        if let latestEntry, !latestEntry.body.isEmpty {
            return latestEntry.body
        }
        if !goal.note.isEmpty {
            return goal.note
        }
        if !goal.milestones.isEmpty {
            return "\(GoalProgress.text(of: goal)) 里程碑"
        }
        return ""
    }

    /// 里程碑全勾（且至少一个）：呈现「可以完成了」的
    /// 事实判据——只是提示，完成永远由用户点（状态机
    /// 口径：系统不替用户下结论）
    public static func allMilestonesDone(_ goal: BridgeGoal) -> Bool {
        !goal.milestones.isEmpty
            && goal.milestones.allSatisfy { $0.done }
    }
}

// MARK: - 请求体（POST 新建点子）

/// POST /ideas 请求体：{title, detail?, goalId?}——
/// 可选字段为 nil 时不落键
public struct BridgeIdeaCreateRequest: Encodable, Equatable, Sendable {
    public let title: String
    public let detail: String?
    public let goalId: String?

    public init(title: String, detail: String?, goalId: String?) {
        self.title = title
        self.detail = detail
        self.goalId = goalId
    }

    /// 表单口径收口：标题/详情去首尾空白，详情空→不带字段
    public static func make(
        title: String, detail: String, goalId: String?
    ) -> BridgeIdeaCreateRequest {
        let trimmedDetail = detail.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return BridgeIdeaCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
            goalId: goalId
        )
    }
}

// MARK: - 点子转任务计划

/// 点子 → kanban 任务的载荷组装（纯函数，单测钉死）：
/// 标题直用点子标题；正文＝详情（有才带行）＋关联目标
/// 行（挂了且目标名可解析才带）＋来源行。任务本体经
/// P3 KanbanStore.createTask 落板并回读确认，本计划
/// 只管「建成什么样」，不管成没成
public enum IdeaTaskPlan {
    public static func make(
        idea: BridgeIdea, goalTitle: String?
    ) -> (title: String, body: String) {
        var lines: [String] = []
        let detail = idea.detail.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !detail.isEmpty {
            lines.append(detail)
        }
        if idea.goalId != nil, let goalTitle, !goalTitle.isEmpty {
            lines.append("关联目标：\(goalTitle)")
        }
        let evidence = idea.evidence.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !evidence.isEmpty {
            lines.append("依据：\(evidence)")
        }
        lines.append("来源：点子")
        return (title: idea.title, body: lines.joined(separator: "\n"))
    }
}

// MARK: - 表格转码（§125，桥 /files/spreadsheet）

/// xlsx 转码回执：伴生把每个 sheet 转成 CSV 文本
/// （值口径——公式取缓存值），App 侧走 Document-
/// Reading 的 csv 块呈现。单 sheet 超行数上限时桥
/// 侧截断并明示（truncated＋totalRows），不许静默
/// 截断；notes 是如实标注（如某公式无缓存值），
/// 原样呈现、不加工
public struct BridgeSpreadsheet: Decodable, Equatable, Sendable {
    public struct Sheet: Decodable, Equatable, Identifiable, Sendable {
        public let name: String
        public let csv: String
        public let totalRows: Int
        public let truncated: Bool

        public var id: String { name }

        private enum CodingKeys: String, CodingKey {
            case name, csv, truncated
            case totalRows = "total_rows"
        }
    }

    public let name: String
    public let sheets: [Sheet]
    public let notes: [String]
}

// MARK: - 已转任务本地标记

/// 【0.32.0 退役为真源】「已转任务」标记曾只存本地
/// （旧冻结合约无此字段）；P1 起桥 idea 带 taskId/
/// status，服务端为唯一真源，IdeasStore 不再读写本
/// 标记。类型与编解码保留（单测仍钉其行为），仅作
/// 历史口径存档，不再有生产调用方。原口径：UserDefaults
/// 落排序后的 id 数组（去重＋排序＋容脏）
public enum IdeaConversionMarks {
    public static func encode(_ ids: Set<String>) -> [String] {
        ids.sorted()
    }

    public static func decode(_ raw: [String]?) -> Set<String> {
        guard let raw else { return [] }
        return Set(raw.filter { !$0.isEmpty })
    }
}

// MARK: - 文件交付登记（§146，规格 delivery-registry-spec-20261111 §5）

/// 登记元数据（GET /deliveries/{id} 回执）：全部
/// 字段由登记端点回读实文件生成（名/大小/指纹/
/// 图片宽高/封面有无），App 不采信正文自述——这
/// 是登记制与「正文写路径」的根本区别。status 是
/// 桥在每次 GET 时按指纹实时复核的读时状态：
/// ok＝与登记时全符；stale＝登记后被改过（照常
/// 渲染、不加警示）；gone＝文件已不在（降级一
/// 行文本）。kind 与 App FileItemCategory 对齐。
public struct BridgeDelivery: Decodable, Equatable, Sendable {
    public struct Cover: Decodable, Equatable, Sendable {
        /// 360 档缩略快照在不在（登记时生成）
        public let thumb: Bool
        /// 封面快照在不在（图片 1080/文档纸面渲染等）
        public let cover: Bool
    }

    public enum Status: String, Decodable, Equatable, Sendable {
        case ok
        case stale
        case gone
    }

    public let id: String
    public let status: Status
    public let name: String
    public let path: String
    public let size: Int64
    public let mime: String?
    public let kind: String
    public let width: Int?
    public let height: Int?
    public let sha256: String?
    public let registeredAt: String?
    public let cover: Cover

    /// 图片的实测像素尺寸（登记端点 Pillow 实测、
    /// 已校正 EXIF 方向）；非图片或未测得为 nil。
    /// §130 定高卡的卡宽由它先行算出，图未到版式
    /// 已定、不跳动
    public var imagePixelSize: CGSize? {
        guard let width, let height, width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// 登记快照图档位（GET /deliveries/{id}/<档位>）：
/// thumb＝360 档、cover＝封面档，与 §33 变体阶
/// 梯同名同义、不另起口径
public enum DeliveryImageVariant: String, Sendable {
    case thumb
    case cover
}

// MARK: - 桥错误口径（§139 自 App 层 OneDayBridgeClient 下沉 Core）

/// oneday-bridge 错误口径：与总览桥同分法——「没有钥匙」
/// 「钥匙被拒（401）」是桥未连接（钥匙问题），要在面
/// 上如实露；集合端点 404 是「桥未开通」；条目端点
/// 404 是记录已不在；其余失败给人话、不混报。
/// §139 起定义在 Core：错误→加载态的映射（StoreLoadState）
/// 与本类型同层共置，App 层客户端只负责抛出。
public enum OneDayBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case bridgeMissing
    case recordGone
    case failed(String)
}
