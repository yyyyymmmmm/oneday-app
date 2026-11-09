import CryptoKit
import Foundation

/// write-gate 桥记忆条目契约模型（0.13.0，P7 客户端
/// 先行）：契约冻结于 oneday-design-review/memory-
/// bridge-contract-20261109.md——Hermes 本体无条目级
/// API（只有状态/计数）、write-gate 桥无拟写发起面，
/// 条目读与 propose 暂存须由桥在 /api/write-gate 下
/// 新增 /memories 路由组才成立；本包按契约形状建
/// 客户端，端点 404＝「记忆条目尚未开通」如实露。
/// 审批裁决与待批/已决读取走桥已上线现成面，不重造。
/// 口径：时间 epoch 秒（float）；id 内容寻址；列表
/// 不带全文（沿「列表不带大正文」纪律）；条目正文
/// 不写日志、不进 Demo 数据。本文件只放 DTO＋纯
/// 派生（摘要/分组/过滤/提案落定判定），网络与状态
/// 在 App 层。

// MARK: - 条目来源（target）

/// 条目所在文件：memory＝长期记忆（MEMORY）、
/// user＝用户档案（USER）；契约外的值按 unknown
/// 处理、呈现「未注明来源」，不猜
public enum MemoryTarget: String, Equatable, Sendable {
    case memory
    case user
    case unknown

    /// 宽容映射（不用合成的 failable init 是因为
    /// 未知值要落 unknown 而不是 nil）：契约外的值
    /// 一律未注明来源，不猜
    public static func from(_ raw: String) -> MemoryTarget {
        switch raw.lowercased() {
        case "memory": return .memory
        case "user": return .user
        default: return .unknown
        }
    }

    /// 来源人话（条目行 small 与详情共用，全 App 只此一处）
    public var label: String {
        switch self {
        case .memory: return "长期记忆"
        case .user: return "用户档案"
        case .unknown: return "未注明来源"
        }
    }

    /// 分组呈现序：长期记忆在前、用户档案次之、
    /// 未注明来源垫底
    public var groupOrder: Int {
        switch self {
        case .memory: return 0
        case .user: return 1
        case .unknown: return 2
        }
    }
}

// MARK: - 内容摘要（id/digest 的唯一算法口径）

/// 条目 id 与 digest 的生成口径（契约 §2.2）：桥与
/// 客户端必须同算法——sha256(条目原文 UTF-8) 十六
/// 进制小写；id＝"mem_"＋前 16 位。客户端算 digest
/// 只用于回读验落盘与待批匹配，不在本地生成条目。
public enum MemoryDigest {
    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func entryID(forContent content: String) -> String {
        "mem_" + String(sha256Hex(content).prefix(16))
    }
}

// MARK: - 条目 DTO

/// 条目摘要（GET /memories 列表项）：无正文字段——
/// 列表只呈桥生成的 title/summary，不在客户端截
/// 正文拼摘要（敏感内容不在列表层扩散）
public struct BridgeMemoryEntry: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    /// 来源原值（memory/user；其余按未注明来源）
    public let targetRaw: String
    public let title: String
    public let summary: String
    /// 文件级时刻（epoch 秒）：所在记忆文件的
    /// mtime，同文件条目相同，不是逐条修改时间
    public let updatedAt: Double
    /// 条目原文 sha256 全量十六进制（改/删提案的
    /// baseDigest 与回读验落盘都以它为准）
    public let digest: String

    public var target: MemoryTarget { MemoryTarget.from(targetRaw) }

    public init(
        id: String, targetRaw: String, title: String,
        summary: String, updatedAt: Double, digest: String
    ) {
        self.id = id
        self.targetRaw = targetRaw
        self.title = title
        self.summary = summary
        self.updatedAt = updatedAt
        self.digest = digest
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, summary, updatedAt, digest
        case targetRaw = "target"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        targetRaw = try container.decodeIfPresent(
            String.self, forKey: .targetRaw
        ) ?? ""
        title = try container.decodeIfPresent(
            String.self, forKey: .title
        ) ?? ""
        summary = try container.decodeIfPresent(
            String.self, forKey: .summary
        ) ?? ""
        updatedAt = try container.decodeIfPresent(
            Double.self, forKey: .updatedAt
        ) ?? 0
        digest = try container.decodeIfPresent(
            String.self, forKey: .digest
        ) ?? ""
    }
}

public struct BridgeMemoryEntriesResponse: Decodable, Equatable, Sendable {
    public let entries: [BridgeMemoryEntry]
    public let generatedAt: Double?

    public init(entries: [BridgeMemoryEntry], generatedAt: Double?) {
        self.entries = entries
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case entries, generatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent(
            [BridgeMemoryEntry].self, forKey: .entries
        ) ?? []
        generatedAt = try container.decodeIfPresent(
            Double.self, forKey: .generatedAt
        )
    }
}

/// 条目详情（GET /memories/{id}）：摘要字段＋全文
public struct BridgeMemoryEntryDetail: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let targetRaw: String
    public let title: String
    public let summary: String
    public let updatedAt: Double
    public let digest: String
    /// 条目全文（详情独有）
    public let content: String

    public var target: MemoryTarget { MemoryTarget.from(targetRaw) }

    public init(
        id: String, targetRaw: String, title: String,
        summary: String, updatedAt: Double, digest: String,
        content: String
    ) {
        self.id = id
        self.targetRaw = targetRaw
        self.title = title
        self.summary = summary
        self.updatedAt = updatedAt
        self.digest = digest
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, summary, updatedAt, digest, content
        case targetRaw = "target"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        targetRaw = try container.decodeIfPresent(
            String.self, forKey: .targetRaw
        ) ?? ""
        title = try container.decodeIfPresent(
            String.self, forKey: .title
        ) ?? ""
        summary = try container.decodeIfPresent(
            String.self, forKey: .summary
        ) ?? ""
        updatedAt = try container.decodeIfPresent(
            Double.self, forKey: .updatedAt
        ) ?? 0
        digest = try container.decodeIfPresent(
            String.self, forKey: .digest
        ) ?? ""
        content = try container.decodeIfPresent(
            String.self, forKey: .content
        ) ?? ""
    }
}

public struct BridgeMemoryDetailResponse: Decodable, Equatable, Sendable {
    public let entry: BridgeMemoryEntryDetail

    public init(entry: BridgeMemoryEntryDetail) {
        self.entry = entry
    }
}

// MARK: - propose（唯一的写发起面）

/// 写操作三形：新建/修改（全文替换）/遗忘（删除）。
/// 全部只发起暂存待批——批准才落盘，客户端不许有
/// 任何绕过审批的直写路径（契约 §1 红线）
public enum MemoryProposeOperation: String, Equatable, Sendable {
    case create
    case update
    case delete

    /// 桥暂存 payload 的 action 对应（契约 §2.3）
    public var gateAction: String {
        switch self {
        case .create: return "add"
        case .update: return "replace"
        case .delete: return "remove"
        }
    }

    /// 动作人话（提案行与提示文案共用）
    public var label: String {
        switch self {
        case .create: return "新建记忆"
        case .update: return "修改记忆"
        case .delete: return "遗忘记忆"
        }
    }
}

/// POST /memories/propose 请求体：create 只带
/// target＋content；update/delete 带 entryId＋
/// baseDigest（桥据 digest 校验条目未被改动）；
/// 可选字段 nil 不落键
public struct BridgeMemoryProposeRequest: Encodable, Equatable, Sendable {
    public let operation: MemoryProposeOperation
    /// 目标文件原值（"memory"/"user"）
    public let target: String
    public let entryId: String?
    public let content: String?
    public let baseDigest: String?

    public init(
        operation: MemoryProposeOperation, target: String,
        entryId: String?, content: String?, baseDigest: String?
    ) {
        self.operation = operation
        self.target = target
        self.entryId = entryId
        self.content = content
        self.baseDigest = baseDigest
    }

    public static func create(
        target: MemoryTarget, content: String
    ) -> BridgeMemoryProposeRequest {
        BridgeMemoryProposeRequest(
            operation: .create, target: target.rawValue,
            entryId: nil, content: content, baseDigest: nil
        )
    }

    public static func update(
        entry: BridgeMemoryEntry, content: String
    ) -> BridgeMemoryProposeRequest {
        BridgeMemoryProposeRequest(
            operation: .update, target: entry.targetRaw,
            entryId: entry.id, content: content,
            baseDigest: entry.digest
        )
    }

    public static func delete(
        entry: BridgeMemoryEntry
    ) -> BridgeMemoryProposeRequest {
        BridgeMemoryProposeRequest(
            operation: .delete, target: entry.targetRaw,
            entryId: entry.id, content: nil,
            baseDigest: entry.digest
        )
    }

    private enum CodingKeys: String, CodingKey {
        case operation, target, entryId, content, baseDigest
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation.rawValue, forKey: .operation)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(entryId, forKey: .entryId)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(baseDigest, forKey: .baseDigest)
    }
}

/// propose 201 回执：拿到 pendingId 才算发起成功；
/// 此后该提案在裁决前一律只是「待审批」
public struct BridgeMemoryProposeResponse: Decodable, Equatable, Sendable {
    public let pendingId: String
    public let operation: String
    public let target: String

    public init(pendingId: String, operation: String, target: String) {
        self.pendingId = pendingId
        self.operation = operation
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case pendingId, operation, target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pendingId = try container.decode(String.self, forKey: .pendingId)
        operation = try container.decodeIfPresent(
            String.self, forKey: .operation
        ) ?? ""
        target = try container.decodeIfPresent(
            String.self, forKey: .target
        ) ?? ""
    }
}

// MARK: - 已决记录（GET /decisions，桥已上线现成面）

/// 已决记录（桥 decisions.jsonl 的规范化行，只含
/// 元数据、无正文）：提案落定判定靠它区分已批准/
/// 已驳回，不许从「待批里消失了」反推裁决结果
public struct WriteGateDecisionRecord: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let subsystem: WriteGateSubsystem
    public let action: String
    public let summary: String
    public let origin: String
    /// "approved" / "rejected"（桥原值）
    public let decision: String
    public let decidedAt: Date?

    public var isApproved: Bool { decision == "approved" }
    public var isRejected: Bool { decision == "rejected" }

    public init(
        id: String, subsystem: WriteGateSubsystem, action: String,
        summary: String, origin: String, decision: String,
        decidedAt: Date?
    ) {
        self.id = id
        self.subsystem = subsystem
        self.action = action
        self.summary = summary
        self.origin = origin
        self.decision = decision
        self.decidedAt = decidedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, subsystem, action, summary, origin, decision
        case decidedAt = "decided_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        subsystem = try container.decodeIfPresent(
            WriteGateSubsystem.self, forKey: .subsystem
        ) ?? .unknown
        action = try container.decodeIfPresent(
            String.self, forKey: .action
        ) ?? ""
        summary = try container.decodeIfPresent(
            String.self, forKey: .summary
        ) ?? ""
        origin = try container.decodeIfPresent(
            String.self, forKey: .origin
        ) ?? ""
        decision = try container.decodeIfPresent(
            String.self, forKey: .decision
        ) ?? ""
        if let text = (try? container.decodeIfPresent(
            String.self, forKey: .decidedAt
        )) ?? nil {
            decidedAt = ProfileSoulDocument.parseDate(.string(text))
        } else if let epoch = (try? container.decodeIfPresent(
            Double.self, forKey: .decidedAt
        )) ?? nil {
            decidedAt = ProfileSoulDocument.parseDate(.number(epoch))
        } else {
            decidedAt = nil
        }
    }
}

public struct WriteGateDecisionsResponse: Decodable, Equatable, Sendable {
    public let decisions: [WriteGateDecisionRecord]

    public init(decisions: [WriteGateDecisionRecord]) {
        self.decisions = decisions
    }

    private enum CodingKeys: String, CodingKey {
        case decisions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        decisions = try container.decodeIfPresent(
            [WriteGateDecisionRecord].self, forKey: .decisions
        ) ?? []
    }
}

// MARK: - 条目呈现（标题/分组/过滤，纯函数）

public enum MemoryEntryPresentation {
    /// 行标题：桥生成 title 优先；为空回落摘要；
    /// 再为空（异常数据）明说无标题，不编造
    public static func displayTitle(of entry: BridgeMemoryEntry) -> String {
        let title = entry.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !title.isEmpty { return title }
        let summary = entry.summary.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !summary.isEmpty { return summary }
        return "（无标题）"
    }

    /// 分组：按来源分组（长期记忆→用户档案→未注
    /// 明来源），组内保持桥返回序不重排
    public static func groups(
        _ entries: [BridgeMemoryEntry]
    ) -> [(target: MemoryTarget, entries: [BridgeMemoryEntry])] {
        var byTarget: [MemoryTarget: [BridgeMemoryEntry]] = [:]
        for entry in entries {
            byTarget[entry.target, default: []].append(entry)
        }
        return byTarget
            .sorted { $0.key.groupOrder < $1.key.groupOrder }
            .map { (target: $0.key, entries: $0.value) }
    }

    /// 客户端搜索过滤：标题/摘要/来源人话做包含
    /// 匹配（大小写不敏感）；空查询返回全量
    public static func filtered(
        _ entries: [BridgeMemoryEntry], query: String
    ) -> [BridgeMemoryEntry] {
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            displayTitle(of: entry).lowercased().contains(needle)
                || entry.summary.lowercased().contains(needle)
                || entry.target.label.lowercased().contains(needle)
        }
    }
}

// MARK: - 提案（本会话发起的待批跟踪）

/// 提案落定状态：待审批是唯一中间态；离开待批后
/// 必须有裁决记录＋回读证据才落「已落定」
public enum MemoryProposalStatus: Equatable, Sendable {
    /// 仍在待批列表里
    case pending
    /// 已批准且回读确认变化已落盘
    case landed
    /// 已批准但回读还没确认到变化（不许假报成功）
    case approvedUnconfirmed
    /// 已驳回（条目保持原样）
    case rejected
    /// 已不在待批列表、又查不到裁决记录：结果未确认
    case unresolved
}

/// 一条本会话发起的写提案：只跟踪状态，不持有
/// 「已生效」的本地副本——条目内容永远以回读的
/// /memories 为唯一事实
public struct MemoryProposal: Equatable, Sendable, Identifiable {
    public let pendingId: String
    public let operation: MemoryProposeOperation
    public let targetRaw: String
    /// update/delete 的目标条目 id；create 为 nil
    public let entryId: String?
    /// update/delete 发起时条目的 digest；create 为 nil
    public let baseDigest: String?
    /// create/update 的拟写全文（回读验落盘时算
    /// 目标 digest 用；delete 为 nil）
    public let proposedContent: String?
    public var status: MemoryProposalStatus
    public var note: String?

    public var id: String { pendingId }
    public var target: MemoryTarget { MemoryTarget.from(targetRaw) }

    public init(
        pendingId: String, operation: MemoryProposeOperation,
        targetRaw: String, entryId: String?,
        baseDigest: String?, proposedContent: String?,
        status: MemoryProposalStatus = .pending, note: String? = nil
    ) {
        self.pendingId = pendingId
        self.operation = operation
        self.targetRaw = targetRaw
        self.entryId = entryId
        self.baseDigest = baseDigest
        self.proposedContent = proposedContent
        self.status = status
        self.note = note
    }

    /// 状态人话（提案行/详情提示共用）
    public var statusLabel: String {
        switch status {
        case .pending: return "待审批"
        case .landed: return "已生效"
        case .approvedUnconfirmed: return "已批准，待回读确认"
        case .rejected: return "已驳回"
        case .unresolved: return "结果未确认"
        }
    }
}

public enum MemoryProposalResolution {
    /// 落定判定（纯函数，单测钉死）：入参为当前待批
    /// id 集合、已决记录（id→decision 原值）、最新
    /// 回读条目。判定优先级：还在待批→pending；
    /// 有裁决记录→按裁决＋回读验落盘；都没有→
    /// unresolved（如实未确认，不猜）
    public static func status(
        of proposal: MemoryProposal,
        pendingIDs: Set<String>,
        decisions: [String: String],
        entries: [BridgeMemoryEntry]
    ) -> MemoryProposalStatus {
        if pendingIDs.contains(proposal.pendingId) {
            return .pending
        }
        guard let decision = decisions[proposal.pendingId] else {
            return .unresolved
        }
        if decision == "rejected" {
            return .rejected
        }
        guard decision == "approved" else {
            return .unresolved
        }
        return landed(proposal, entries: entries) ? .landed : .approvedUnconfirmed
    }

    /// 回读验落盘：create 看新内容 digest 出现；
    /// update 看新 digest 出现且旧 digest 消失；
    /// delete 看旧 digest 消失
    public static func landed(
        _ proposal: MemoryProposal, entries: [BridgeMemoryEntry]
    ) -> Bool {
        let digests = Set(entries.map(\.digest))
        switch proposal.operation {
        case .create:
            guard let content = proposal.proposedContent else { return false }
            return digests.contains(MemoryDigest.sha256Hex(content))
        case .update:
            guard let content = proposal.proposedContent,
                  let base = proposal.baseDigest else { return false }
            let newDigest = MemoryDigest.sha256Hex(content)
            // 内容没变的「修改」新旧同 digest：出现即落定
            if newDigest == base { return digests.contains(base) }
            return digests.contains(newDigest) && !digests.contains(base)
        case .delete:
            guard let base = proposal.baseDigest else { return false }
            return !digests.contains(base)
        }
    }
}

// MARK: - 待批与条目的匹配（认领「我发起的」改/删）

public enum MemoryPendingMatching {
    /// App 发起待批的 origin 固定值（契约 §2.3）：
    /// 条目面据此与 agent 发起的待批区分
    public static let appOrigin = "oneday_app"

    /// 从一条 memory 待批记录的 payload 提取它要
    /// 改/删的条目原文 digest：replace/remove 看
    /// old_text（或 matched_entry）；add/batch 无
    /// 单一条目目标 → nil（只在待批区呈现，不往
    /// 条目行上贴标）
    public static func targetedDigest(payload: JSONValue?) -> String? {
        guard case .object(let object)? = payload else { return nil }
        let action = object["action"]?.stringValue?.lowercased() ?? ""
        // 只认 replace/remove：patch 的 old_text 是
        // 定位片段不是条目全文，拿它算 digest 匹配
        // 条目必然对不上，不如不贴标
        guard action == "replace" || action == "remove" else {
            return nil
        }
        for key in ["old_text", "matched_entry"] {
            if let text = object[key]?.stringValue, !text.isEmpty {
                return MemoryDigest.sha256Hex(text)
            }
        }
        return nil
    }
}

// MARK: - 表单校验（与桥端 400 口径对齐）

public enum MemoryProposalValidation {
    /// 返回第一条问题人话；无问题为 nil。create/
    /// update 正文去空白为空先在客户端拦下；update
    /// 与原文一字不差不算修改（提交只会白占一条
    /// 待批）——一并拦下并说清
    public static func problem(
        operation: MemoryProposeOperation,
        content: String?, originalContent: String? = nil
    ) -> String? {
        switch operation {
        case .create, .update:
            let text = (content ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if text.isEmpty {
                return "请先写下要记住的内容。"
            }
            if operation == .update,
               let originalContent, content == originalContent {
                return "内容还没有改动。"
            }
            return nil
        case .delete:
            return nil
        }
    }
}
