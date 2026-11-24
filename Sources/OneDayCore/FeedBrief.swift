import Foundation

// MARK: - 简报单层（§459，GET/PUT /meta/brief 契约）
//
// 0.38.0 的两层（兴趣层＋执行层）在 §459 合一层：
// 编辑器只见一份「当前生效全文」text——服务端按
// 单层规则出数（润色稿与当前 interest 逐字相等才
// 出润色稿、否则出原文），保存只发 {text}（服务端
// 折为 interest 保存、briefInterest 永不被润色覆
// 盖）。brief/interest 字段服务端照旧出、App 只作
// 旧桥容错回落与摘要行口径，不再进编辑器。润色状
// 态以 polishState 如实呈现，绝不假装已润色。

/// 润色状态（§459 契约四值；未知值宽容折 idle）
public enum BriefPolishState: String, Sendable, Equatable {
    case done
    case pending
    case error
    case idle
}

/// 简报全文（桥 /meta/brief 读视图；PUT 回执同形另带
/// expandStarted，只在回执里有意义、解码宽容可缺）
public struct BridgeBriefDoc: Decodable, Equatable, Sendable {
    /// 当前生效全文（§459 单层编辑器唯一绑定）
    public let text: String
    /// text 是否为润色稿（false＝用户原文）
    public let polished: Bool
    /// 润色状态原始值（BriefPolishState 解析）
    public let polishStateRaw: String
    /// 执行层（正式简报，旧字段、兼容保留）
    public let brief: String
    /// 兴趣层（用户原话，旧字段、兼容保留）
    public let interest: String
    public let briefUpdatedAt: Double?
    public let interestUpdatedAt: Double?
    /// 扩写进行中
    public let expanding: Bool
    /// 最近一次扩写失败原因（没有为 nil）
    public let expandError: String?
    /// 本次保存是否起了一轮扩写/调研（仅 PUT 回执）
    public let expandStarted: Bool?

    public init(
        brief: String, interest: String,
        briefUpdatedAt: Double? = nil,
        interestUpdatedAt: Double? = nil,
        expanding: Bool = false, expandError: String? = nil,
        expandStarted: Bool? = nil,
        text: String = "", polished: Bool = false,
        polishStateRaw: String = "idle"
    ) {
        self.brief = brief
        self.interest = interest
        self.briefUpdatedAt = briefUpdatedAt
        self.interestUpdatedAt = interestUpdatedAt
        self.expanding = expanding
        self.expandError = expandError
        self.expandStarted = expandStarted
        self.text = text
        self.polished = polished
        self.polishStateRaw = polishStateRaw
    }

    /// 润色状态（未知/缺失一律 idle，不猜已润色）
    public var polishState: BriefPolishState {
        BriefPolishState(rawValue: polishStateRaw) ?? .idle
    }

    private enum CodingKeys: String, CodingKey {
        case brief, interest, briefUpdatedAt, interestUpdatedAt
        case expanding, expandError, expandStarted
        case text, polished, polishState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brief = try container.decodeIfPresent(
            String.self, forKey: .brief
        ) ?? ""
        interest = try container.decodeIfPresent(
            String.self, forKey: .interest
        ) ?? ""
        briefUpdatedAt = try container.decodeIfPresent(
            Double.self, forKey: .briefUpdatedAt
        )
        interestUpdatedAt = try container.decodeIfPresent(
            Double.self, forKey: .interestUpdatedAt
        )
        expanding = try container.decodeIfPresent(
            Bool.self, forKey: .expanding
        ) ?? false
        expandError = try container.decodeIfPresent(
            String.self, forKey: .expandError
        )
        expandStarted = try container.decodeIfPresent(
            Bool.self, forKey: .expandStarted
        )
        text = try container.decodeIfPresent(
            String.self, forKey: .text
        ) ?? ""
        polished = try container.decodeIfPresent(
            Bool.self, forKey: .polished
        ) ?? false
        polishStateRaw = try container.decodeIfPresent(
            String.self, forKey: .polishState
        ) ?? "idle"
    }
}

// MARK: - 简报呈现口径

public enum FeedBriefBoard {
    /// 动态页顶部摘要行：兴趣层首行优先（那是用户认
    /// 得的自己的话），没有兴趣层时回落执行层首行；
    /// 两层皆空为 nil（页面走引导态）
    public static func summaryLine(_ doc: BridgeBriefDoc) -> String? {
        for text in [doc.interest, doc.brief] {
            let first = text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if !first.isEmpty {
                return first
            }
        }
        return nil
    }

    /// 引导态：还没写过（生效全文与两层旧字段皆空）
    public static func isGuideState(_ doc: BridgeBriefDoc) -> Bool {
        effectiveText(doc).trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
            && doc.interest.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && doc.brief.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }

    /// 真变更判定（与桥侧同口径：trim 后比较，纯空白
    /// 抖动不算改）
    public static func textChanged(_ old: String, _ new: String) -> Bool {
        old.trimmingCharacters(in: .whitespacesAndNewlines)
            != new.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 编辑器打开时见到的全文（§459）：服务端 text
    /// 优先；旧桥未出 text 时回落旧两层口径（兴趣层
    /// 优先、其次执行层），不许空白冒充已同步
    public static func effectiveText(_ doc: BridgeBriefDoc) -> String {
        if !doc.text.isEmpty { return doc.text }
        if !doc.interest.isEmpty { return doc.interest }
        return doc.brief
    }

    /// 润色状态极小提示（§459：只许小字如实呈现，
    /// 不许假装已润色）：pending/error 恒出；done
    /// 仅当 text 确为润色稿时出；idle 且原文生效
    /// 时不出（原文即生效、无事可报）
    public static func polishHint(_ doc: BridgeBriefDoc) -> String? {
        switch doc.polishState {
        case .pending:
            return "正在整理成正式简报…"
        case .error:
            return "上次整理没成功，现在生效的是你保存的原文。"
        case .done:
            return doc.polished
                ? "现在生效的是整理后的简报；你改的就是它，保存后原样生效。"
                : nil
        case .idle:
            return nil
        }
    }
}


/// 简报保存请求（PUT /meta/brief）：§459 起编辑器
/// 只发 {text}（服务端折为 interest 保存）；interest
/// /brief 字段保留在契约里（服务端显式给出时优先），
/// App 不再混发
public struct BridgeBriefSaveRequest: Encodable, Sendable, Equatable {
    public let text: String?
    public let interest: String?
    public let brief: String?

    public init(
        text: String? = nil,
        interest: String? = nil, brief: String? = nil
    ) {
        self.text = text
        self.interest = interest
        self.brief = brief
    }

    private enum CodingKeys: String, CodingKey {
        case text, interest, brief
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(interest, forKey: .interest)
        try container.encodeIfPresent(brief, forKey: .brief)
    }
}
