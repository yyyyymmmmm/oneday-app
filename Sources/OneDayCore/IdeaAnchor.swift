import Foundation

/// 点子依据的素材锚点（0.39.0，规格 three-pages-mechanism-v2
/// 第二章）。编号体系：evidenceRef 是生成轮内的编号（源字母＋
/// 序号），跨轮无意义；桥在落卡时把编号解析成真实对象、另存
/// anchorId（"<源字母>:<对象 id>"），跨轮锚点级去重以
/// anchorId 为准（桥侧执行）。本件是客户端侧的锚点模型：
/// 只做解析与呈现映射（来源瓷砖），不解读对象 id 本身。
public enum IdeaMaterialKind: String, Equatable, Sendable {
    /// S 近 14 天会话
    case session
    /// G 目标
    case goal
    /// M 监测变化
    case monitor
    /// K 任务板
    case kanban
    /// R 长期记忆摘录
    case memory
    case unknown

    public init(refLetter: Character?) {
        switch refLetter {
        case "S": self = .session
        case "G": self = .goal
        case "M": self = .monitor
        case "K": self = .kanban
        case "R": self = .memory
        default: self = .unknown
        }
    }

    /// 来源瓷砖的 SF Symbol 名（宪法 §4 三源制：SF Symbols
    /// 同语义位；S/G/M 与 0.32.0 既有映射逐一对齐不回退，
    /// K/R 为本包新增）
    public var tileSymbol: String {
        switch self {
        case .session: return "text.bubble"
        case .goal: return "target"
        case .monitor: return "dot.radiowaves.left.and.right"
        case .kanban: return "checklist"
        case .memory: return "brain"
        case .unknown: return "lightbulb"
        }
    }
}

/// 一条已解析的锚点引用：evidenceRef 形态带轮内序号，
/// anchorId 形态只有种类（对象 id 客户端不解读）。
public struct IdeaAnchor: Equatable, Sendable {
    public let kind: IdeaMaterialKind
    /// 轮内序号（evidenceRef 的数字部分）；anchorId 形态为 nil
    public let index: Int?
    /// 原始字符串（evidenceRef 或 anchorId 原样）
    public let raw: String

    /// 解析 evidenceRef（"S3"/"K12"…）；形状不对返回 nil
    /// （未知字母、无序号、序号非数字一律不认，不猜）
    public init?(evidenceRef: String?) {
        guard let ref = evidenceRef, !ref.isEmpty else { return nil }
        let kind = IdeaMaterialKind(refLetter: ref.first)
        guard kind != .unknown else { return nil }
        let digits = ref.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber),
              let n = Int(String(digits))
        else { return nil }
        self.kind = kind
        self.index = n
        self.raw = ref
    }

    /// 解析 anchorId（"K:t_xxx"/"S:sess-…"）：冒号前必须恰为
    /// 一个已知源字母；形状不对返回 nil
    public init?(anchorId: String?) {
        guard let aid = anchorId,
              let colon = aid.firstIndex(of: ":")
        else { return nil }
        let head = aid[..<colon]
        guard head.count == 1, let ch = head.first else { return nil }
        let kind = IdeaMaterialKind(refLetter: ch)
        guard kind != .unknown else { return nil }
        self.kind = kind
        self.index = nil
        self.raw = aid
    }
}
