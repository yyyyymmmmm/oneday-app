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
    public var title: String {
        switch self {
        case .health: return "健康"
        case .relationships: return "人际关系"
        case .finance: return "财务"
        case .career: return "事业"
        case .interest: return "兴趣"
        case .efficiency: return "效率提升"
        case .other: return "其他"
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
}
