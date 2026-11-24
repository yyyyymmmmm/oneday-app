import Foundation

/// 目标分类（0.40.0，规格 three-pages-mechanism-v2 第三章）：
/// 人生领域的七分——无目标时分类创建流的入口、创建时的
/// 语境、点子 G 源与目标简报组织素材的维度。分类是用户
/// 在创建/编辑时自己的选择：桥只校验枚举并原样存储，
/// 存量目标一律未分类（nil），任何层都不许按标题关键词
/// 推断补位冒充用户选择。rawValue 与桥 GOAL_CATEGORIES
/// 枚举逐字一致（桥侧校验真源）
public enum GoalCategory: String, Sendable, Equatable, Codable,
    CaseIterable {
    case health
    case relationships
    case finance
    case career
    case interest
    case efficiency
    case other

    /// 宽容解码口径：缺失/未知值一律按未分类收（nil），
    /// 不因类别字段漂移让整张目标列表解码失败
    public static func from(_ raw: String?) -> GoalCategory? {
        guard let raw else { return nil }
        return GoalCategory(rawValue: raw)
    }

    /// 用户面类名（与桥 400 人话里的七类同词）
    public var title: String { title(locale: AppLocale.uiLocale) }

    /// 类名的目录取词形（0.42.1 国际化长尾包：类名随
    /// 界面语言，呈现层把自己的 locale 透传到这里）
    public func title(locale: Locale) -> String {
        switch self {
        case .health: return L10n.string("健康", locale: locale)
        case .relationships: return L10n.string("人际关系", locale: locale)
        case .finance: return L10n.string("财务", locale: locale)
        case .career: return L10n.string("事业", locale: locale)
        case .interest: return L10n.string("兴趣", locale: locale)
        case .efficiency: return L10n.string("效率提升", locale: locale)
        case .other: return L10n.string("其他", locale: locale)
        }
    }

    /// 分类行图标：SF Symbols 同语义位（设计宪法 §4 三源
    /// 制——系统符号，不仿绘参照截图的 3D/字形原图）
    public var symbolName: String {
        switch self {
        case .health: return "heart"
        case .relationships: return "person.2"
        case .finance: return "banknote"
        case .career: return "briefcase"
        case .interest: return "paintpalette"
        case .efficiency: return "laptopcomputer"
        case .other: return "ellipsis.circle"
        }
    }

    /// 创建流七行的呈现序（规格第三章截图序，即声明序）
    public static var creationOrder: [GoalCategory] {
        allCases
    }

    /// 介绍卡首句（GA-1）：点分类后先出介绍卡，这句说清
    /// 这一类聊的是什么；只陈述类别本身、不编造用户的
    /// 具体目标内容（目标本体在旁聊里由用户聊定）
    public var introLead: String {
        introLead(locale: AppLocale.uiLocale)
    }

    public func introLead(locale: Locale) -> String {
        switch self {
        case .health:
            return L10n.string(
                "想改善的身体状态、想养成的习惯，都从这里开始。",
                locale: locale
            )
        case .relationships:
            return L10n.string(
                "想多陪伴的人、想走近的关系，都从这里开始。",
                locale: locale
            )
        case .finance:
            return L10n.string(
                "想存下的钱、想理顺的收支，都从这里开始。",
                locale: locale
            )
        case .career:
            return L10n.string(
                "想推进的工作、想拿下的机会，都从这里开始。",
                locale: locale
            )
        case .interest:
            return L10n.string(
                "想学的东西、想捡起来的爱好，都从这里开始。",
                locale: locale
            )
        case .efficiency:
            return L10n.string(
                "想省下的时间、想理顺的流程，都从这里开始。",
                locale: locale
            )
        case .other:
            return L10n.string(
                "暂时归不进上面几类的目标，从这里开始。",
                locale: locale
            )
        }
    }
}
