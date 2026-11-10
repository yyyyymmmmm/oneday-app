import Foundation

// MARK: - 简报两层（0.38.0，GET/PUT /meta/brief 契约）
//
// 兴趣层＝用户用自己的话写「我感兴趣什么」；执行层＝
// AI 据兴趣层扩写维护的正式简报（生成链真正消费的
// 文本），可见可改。两层分开存、分开显示；改兴趣层
// 触发扩写，扩写落盘且执行层真变了才触发一轮调研；
// 直接改执行层＝真变更触发一轮调研。

/// 简报全文（桥 /meta/brief 读视图；PUT 回执同形另带
/// expandStarted，只在回执里有意义、解码宽容可缺）
public struct BridgeBriefDoc: Decodable, Equatable, Sendable {
    /// 执行层（正式简报）
    public let brief: String
    /// 兴趣层（用户原话）
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
        expandStarted: Bool? = nil
    ) {
        self.brief = brief
        self.interest = interest
        self.briefUpdatedAt = briefUpdatedAt
        self.interestUpdatedAt = interestUpdatedAt
        self.expanding = expanding
        self.expandError = expandError
        self.expandStarted = expandStarted
    }

    private enum CodingKeys: String, CodingKey {
        case brief, interest, briefUpdatedAt, interestUpdatedAt
        case expanding, expandError, expandStarted
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

    /// 引导态：两层都还没写过（兴趣层空且执行层空）
    public static func isGuideState(_ doc: BridgeBriefDoc) -> Bool {
        doc.interest.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
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

    /// 示例兴趣（用户现行简报的原话口径）：只作编辑
    /// 器里的示例呈现，用户点「填入示例改一改」才进
    /// 输入框，绝不静默预填、绝不当用户已保存的兴趣
    public static let exampleInterest =
        "我的兴趣动态版块，围绕三块内容：热门 GitHub 项目、"
        + "AI 相关进展、搞钱和副业机会。全部用中文写。"
        + "GitHub 项目要正在升温、有实际用处的；AI 只报"
        + "实质进展，不报炒作；搞钱和副业只报具体可落地的"
        + "机会与真实案例，不写割韭菜营销号内容。"
}


/// 简报保存请求（PUT /meta/brief）：两层分别保存、
/// 分别触发——兴趣层保存走 {interest}，执行层保存走
/// {brief}，绝不混发（混发会让桥侧变更判定失真）
public struct BridgeBriefSaveRequest: Encodable, Sendable, Equatable {
    public let interest: String?
    public let brief: String?

    public init(interest: String? = nil, brief: String? = nil) {
        self.interest = interest
        self.brief = brief
    }

    private enum CodingKeys: String, CodingKey {
        case interest, brief
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(interest, forKey: .interest)
        try container.encodeIfPresent(brief, forKey: .brief)
    }
}
