import Foundation

// MARK: - write-gate 桥契约模型（一期·待批卡）
//
// 字段口径以桥方案 hermes-deploy/write-approval-bridge-plan.md
// §3 接口契约为准（桥与本线同日并行上线，联调在合并后）：
//   Base = <服务器>/api/write-gate，单独 Bearer 鉴权。
//   GET  /status                          → WriteGateStatus
//   GET  /pending                         → WriteGatePendingList
//   GET  /pending/{subsystem}/{id}        → WriteGateDetail
//   POST /pending/{subsystem}/{id}/approve → WriteGateDecisionResponse
//   POST /pending/{subsystem}/{id}/reject  → WriteGateDecisionResponse
// 一期只上待批卡：已决历史（GET /decisions）是二期接口，
// 本文件不定义历史抓取模型、不从本地消失的卡推断历史。

/// 待批子系统：桥只许 memory / skills 两值；未知值解为
/// unknown——未知类型只许看、不许批准（桥升级契约前
/// 客户端不开批准口，见 WriteGateRecord.canDecide）。
public enum WriteGateSubsystem: String, Decodable, Sendable, Equatable {
    case memory
    case skills
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WriteGateSubsystem(rawValue: raw.lowercased()) ?? .unknown
    }

    /// 桥路径段（unknown 无合法路径，返回 nil）
    public var pathSegment: String? {
        switch self {
        case .memory: return "memory"
        case .skills: return "skills"
        case .unknown: return nil
        }
    }

    /// 类型徽标文案
    public var badgeLabel: String {
        switch self {
        case .memory: return "记忆"
        case .skills: return "技能"
        case .unknown: return "其他写入"
        }
    }
}

/// GET /status：闸门三态的判定源（supported＋两键＋计数）。
/// 宽容解码：字段缺失按 false/0 落，不许整包解码失败。
public struct WriteGateStatus: Decodable, Sendable, Equatable {
    public let supported: Bool
    public let memoryGateEnabled: Bool
    public let skillsGateEnabled: Bool
    public let memoryCount: Int
    public let skillsCount: Int

    public var anyGateEnabled: Bool {
        memoryGateEnabled || skillsGateEnabled
    }

    public var totalCount: Int { memoryCount + skillsCount }

    private struct Gate: Decodable {
        let memory: Bool?
        let skills: Bool?
    }

    private struct Counts: Decodable {
        let memory: Int?
        let skills: Int?
    }

    enum CodingKeys: String, CodingKey {
        case supported, gate, counts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supported = try container.decodeIfPresent(Bool.self, forKey: .supported) ?? false
        let gate = try container.decodeIfPresent(Gate.self, forKey: .gate)
        memoryGateEnabled = gate?.memory ?? false
        skillsGateEnabled = gate?.skills ?? false
        let counts = try container.decodeIfPresent(Counts.self, forKey: .counts)
        memoryCount = counts?.memory ?? 0
        skillsCount = counts?.skills ?? 0
    }

    public init(
        supported: Bool, memoryGateEnabled: Bool, skillsGateEnabled: Bool,
        memoryCount: Int, skillsCount: Int
    ) {
        self.supported = supported
        self.memoryGateEnabled = memoryGateEnabled
        self.skillsGateEnabled = skillsGateEnabled
        self.memoryCount = memoryCount
        self.skillsCount = skillsCount
    }
}

/// pending 记录（桥规范化后的 Record，源头是 pending
/// JSON 文件，桥不发明字段）：summary 是上游生成的摘要、
/// 直接作卡标题；客户端只在 summary 为空时按 action＋
/// 类型拼兜底文案，绝不直出 id/JSON/payload 正文。
public struct WriteGateRecord: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let subsystem: WriteGateSubsystem
    /// 上游原值（skills: create/edit/patch/write_file/
    /// remove_file/delete；memory 枚举待桥侧复核）
    public let action: String
    public let summary: String
    /// 上游来源标识原值（上屏前过 WriteGateLabels.originLabel）
    public let origin: String
    public let createdAt: Date?
    /// created_at 由文件 mtime 兜底时为 true（桥标注）
    public let createdAtApprox: Bool
    /// replay payload 原样（列表可省略，详情必带）；只供
    /// 详情内次级呈现，不进列表摘要
    public let payload: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, subsystem, action, summary, origin, payload
        case createdAt = "created_at"
        case createdAtApprox = "created_at_approx"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        subsystem = try container.decodeIfPresent(
            WriteGateSubsystem.self, forKey: .subsystem
        ) ?? .unknown
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        origin = try container.decodeIfPresent(String.self, forKey: .origin) ?? ""
        createdAtApprox = try container.decodeIfPresent(
            Bool.self, forKey: .createdAtApprox
        ) ?? false
        payload = try container.decodeIfPresent(JSONValue.self, forKey: .payload)
        // created_at：桥转 ISO8601 字符串；也宽容 epoch 数值
        if let text = (try? container.decodeIfPresent(
            String.self, forKey: .createdAt
        )) ?? nil {
            createdAt = ProfileSoulDocument.parseDate(.string(text))
        } else if let epoch = (try? container.decodeIfPresent(
            Double.self, forKey: .createdAt
        )) ?? nil {
            createdAt = ProfileSoulDocument.parseDate(.number(epoch))
        } else {
            createdAt = nil
        }
    }

    public init(
        id: String, subsystem: WriteGateSubsystem, action: String,
        summary: String, origin: String, createdAt: Date?,
        createdAtApprox: Bool = false, payload: JSONValue? = nil
    ) {
        self.id = id
        self.subsystem = subsystem
        self.action = action
        self.summary = summary
        self.origin = origin
        self.createdAt = createdAt
        self.createdAtApprox = createdAtApprox
        self.payload = payload
    }

    /// 是否可裁决：未知子系统不开批准/驳回口（契约红线）
    public var canDecide: Bool { subsystem != .unknown }

    /// 卡标题：上游 summary 优先；为空时按 action＋类型
    /// 拼兜底人话，不许拿正文截段当摘要（敏感内容不在
    /// 列表层扩散，phase3-data-design §5.3）
    public var displaySummary: String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let verb = WriteGateLabels.actionVerb(action)
        switch subsystem {
        case .memory: return "\(verb)一条长期记忆"
        case .skills: return "\(verb)一个技能"
        case .unknown: return "\(verb)一项写入"
        }
    }

    /// 来源行人话（原始标识不上屏）
    public var originLabel: String {
        WriteGateLabels.originLabel(origin)
    }
}

/// GET /pending：记录按 created_at 升序（先进先审）
public struct WriteGatePendingList: Decodable, Sendable, Equatable {
    public let records: [WriteGateRecord]
    public let supported: Bool

    enum CodingKeys: String, CodingKey {
        case records, supported
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decodeIfPresent(
            [WriteGateRecord].self, forKey: .records
        ) ?? []
        supported = try container.decodeIfPresent(
            Bool.self, forKey: .supported
        ) ?? false
    }

    public init(records: [WriteGateRecord], supported: Bool) {
        self.records = records
        self.supported = supported
    }
}

/// diff 呈现结构（与桥 Review 同构）：skills 看 unified
/// diff；memory 的 diff ＝ payload JSON 文本（桥口径）。
public struct WriteGateReview: Decodable, Sendable, Equatable {
    public let subsystem: WriteGateSubsystem
    /// 目标标签（skills＝目标文件名；memory＝"memory"）
    public let targetLabel: String
    public let language: String
    /// 现行内容（memory 恒为空串）
    public let current: String
    /// 拟写入内容（memory 为 payload 的 JSON 文本）
    public let proposed: String
    public let diff: String
    /// patch 定位失败时回传的原 old_string（客户端须显性
    /// 呈给审批人，不许静默按成功处理）
    public let requestedOldString: String?
    public let notes: [Note]

    public struct Note: Decodable, Sendable, Equatable {
        public let type: String
        public let targetLabel: String?
        public let skillName: String?

        enum CodingKeys: String, CodingKey {
            case type
            case targetLabel = "targetLabel"
            case skillName = "skillName"
        }

        public init(type: String, targetLabel: String?, skillName: String?) {
            self.type = type
            self.targetLabel = targetLabel
            self.skillName = skillName
        }
    }

    public init(
        subsystem: WriteGateSubsystem, targetLabel: String,
        language: String, current: String, proposed: String,
        diff: String, requestedOldString: String?, notes: [Note]
    ) {
        self.subsystem = subsystem
        self.targetLabel = targetLabel
        self.language = language
        self.current = current
        self.proposed = proposed
        self.diff = diff
        self.requestedOldString = requestedOldString
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case subsystem, language, current, proposed, diff, notes
        case targetLabel = "targetLabel"
        case requestedOldString = "requestedOldString"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subsystem = try container.decodeIfPresent(
            WriteGateSubsystem.self, forKey: .subsystem
        ) ?? .unknown
        targetLabel = try container.decodeIfPresent(
            String.self, forKey: .targetLabel
        ) ?? ""
        language = try container.decodeIfPresent(
            String.self, forKey: .language
        ) ?? ""
        current = try container.decodeIfPresent(
            String.self, forKey: .current
        ) ?? ""
        proposed = try container.decodeIfPresent(
            String.self, forKey: .proposed
        ) ?? ""
        diff = try container.decodeIfPresent(
            String.self, forKey: .diff
        ) ?? ""
        requestedOldString = try container.decodeIfPresent(
            String.self, forKey: .requestedOldString
        )
        notes = try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
    }

    /// 屏上 diff 文本：diff 为空时回落 proposed（memory 的
    /// payload 文本），再空回落 current
    public var displayDiff: String {
        if !diff.isEmpty { return diff }
        if !proposed.isEmpty { return proposed }
        return current
    }

    /// notes 的人话提示（patch 定位失败等必须显性呈现）
    public var noteLabels: [String] {
        notes.map { WriteGateLabels.noteLabel($0.type) }
    }
}

/// GET /pending/{subsystem}/{id}：record＋review 一次返回
public struct WriteGateDetail: Decodable, Sendable, Equatable {
    public let record: WriteGateRecord
    public let review: WriteGateReview

    enum CodingKeys: String, CodingKey {
        case record, review
    }

    public init(record: WriteGateRecord, review: WriteGateReview) {
        self.record = record
        self.review = review
    }
}

/// POST approve/reject 回执：success=false 一律按失败
/// 处理（防上游静默失败被报成成功，桥方案 §3 成功判定）
public struct WriteGateDecisionResponse: Decodable, Sendable, Equatable {
    public let success: Bool
    public let output: String?
    /// "approved" / "rejected"
    public let decision: String?

    enum CodingKeys: String, CodingKey {
        case success, output, decision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        output = try container.decodeIfPresent(String.self, forKey: .output)
        decision = try container.decodeIfPresent(String.self, forKey: .decision)
    }

    public init(success: Bool, output: String?, decision: String?) {
        self.success = success
        self.output = output
        self.decision = decision
    }
}

// MARK: - 审核段状态机（诚实三态）

/// 审核段状态（规格 #23＋数据设计 §5.5）：裸空列表不许
/// 冒充「无待批」——没有 gate_enabled 证据时只能落
/// bridgeUnavailable（通道未接通），不能断言闸门没开。
public enum ApprovalSectionState: Equatable, Sendable {
    case loading
    /// 桥端点不存在/未部署/无钥匙/自检不过：通道未接通
    case bridgeUnavailable
    /// 桥可达且闸门两键皆关：写入审批未启用
    case gateDisabled
    /// 桥可达、至少一键开：records 为空即真无待批
    case ready([WriteGateRecord])
    case failed(String)

    /// 由 /status 结果与 pending 结果组装状态（纯函数，
    /// 调用方负责把网络失败映射为入参）：
    /// - statusReachable=false（404/501/无钥/网络失败到
    ///   连状态都拿不到）→ bridgeUnavailable。但注意区分：
    ///   纯网络失败应由调用方走 .failed；本函数只处理
    ///   「桥明确不存在」一类，见 Hub 侧映射口径。
    public static func resolve(
        status: WriteGateStatus?, records: [WriteGateRecord]?
    ) -> ApprovalSectionState {
        guard let status else { return .bridgeUnavailable }
        guard status.supported else { return .bridgeUnavailable }
        guard status.anyGateEnabled else { return .gateDisabled }
        return .ready(records ?? [])
    }
}

// MARK: - write-gate 文案翻译层

/// 来源/action/notes 的人话映射。origin 取值域经桥侧
/// 实测确认比上游 docstring 写的 foreground/background_
/// review 更宽（实测有 assistant_tool），本表按「实测
/// 枚举可扩展」做：已知值给人话译名，未知值回落原始值
/// 的诚实呈现——不许按二值写死、不许因为来源没见过就
/// 丢弃整张卡；新取值出现时往本表加一行即可。
public enum WriteGateLabels {
    public static func actionVerb(_ action: String) -> String {
        switch action.lowercased() {
        case "create", "add", "new": return "新建"
        case "append": return "追加"
        case "edit", "update", "modify": return "修改"
        case "patch": return "修订"
        case "write_file", "write": return "写入"
        case "delete", "remove": return "删除"
        case "remove_file": return "删除文件"
        default: return "写入"
        }
    }

    public static func originLabel(_ origin: String) -> String {
        let raw = origin.trimmingCharacters(in: .whitespaces)
        let key = raw.lowercased()
        guard !key.isEmpty else { return "来源未注明" }
        if key.contains("background") { return "后台自检" }
        switch key {
        case "assistant_tool": return "智能体工具调用"
        case "foreground": return "对话中写入"
        case "cli": return "命令行"
        case "dashboard", "web": return "控制台"
        case "chat", "gateway", "api_server", "api": return "对话中写入"
        default:
            // 未知来源：回落原始值诚实呈现，不编造译名、
            // 不丢卡（实测枚举可扩展口径，见本节文件头）
            return raw
        }
    }

    public static func noteLabel(_ type: String) -> String {
        switch type {
        case "patchOldStringMissing":
            return "定位文本已不存在，这条修订可能基于旧内容，批准前请仔细核对改动。"
        case "currentReadFailed":
            return "现行内容读取失败，改动对照可能不完整。"
        case "deleteSkill":
            return "这条待批会删除整个技能。"
        case "removeFile":
            return "这条待批会删除技能内的文件。"
        default:
            return "这条待批带有一条桥侧提示，批准前请打开改动核对。"
        }
    }
}
