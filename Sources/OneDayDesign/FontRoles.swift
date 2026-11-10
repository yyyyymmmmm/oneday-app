import OneDayCore
import SwiftUI

// MARK: - 字阶角色（0.23.0 立表，视觉审计 G2；0.24.0 按 HIG 重排）
// 纪律：全 App 文字只许用本表角色（或系统文本样式的
// 同名直用），不许 .system(size:) 钉文字。角色的数
// 值对账面在 Core TypeRole（样式名/默认 pt/字重档，
// 单测钉）；本文件只落 SwiftUI 形态。
// 0.24.0 口径变更（用户 2026-11-10 当日指令，覆盖
// 此前 Muse 量测口径）：以苹果 HIG Typography 文本
// 样式为唯一依据——行题/导航/分段/会话题一律 Body
// 17 regular；名字头 Title1 28 bold（bold 全 App 配
// 额仅大标题类与身份名）；分区头/时间戳 Footnote
// 13 regular。rowTitleLSemi 退役、rowTitle 由系统
// Headline 改 Body：列表行题不再有 semibold 角色。

public extension Font {
    /// 屏名（抽屉名字头）：Title1 28 bold——HIG 大标
    /// 题档（旧 largeTitle 34 semibold 让位：Muse 量
    /// 测口径被用户当日指令覆盖，见 §51）
    static let screenName: Font = .title.weight(.bold)
    /// 内容标题（0.41.0 收口批 C14/P5 定点登记）：帖
    /// 子详情等「对象本体的标题」——不是界面行题、不
    /// 进 TypeRole 角色表（角色表只管界面文字）；与
    /// §51 Headline 定点同属内容层定点，消费点只许对
    /// 象标题（帖子详情题、文档阅读页题）
    static let contentTitle: Font = .title3.weight(.semibold)
    /// 详情页题（0.41.0 收口批 P6 定点登记）：对象详
    /// 情页的页题（目标详情头）——一页至多一处、是该
    /// 页唯一的第一级；Title2 semibold。行题/分区头
    /// 各归角色表，本定点只管详情页题本体
    static let detailTitle: Font = .title2.weight(.semibold)
    /// 行题（抽屉旁聊题/设置行题/交付物题/会话行题）：
    /// Body 17 regular（旧 title3 20 让位）
    static let rowTitleL: Font = .body
    /// 内容行题（ContentRow/UnifiedRow）：Body 17
    /// regular（旧 .headline 让位——列表行题一律
    /// regular，0.24.0 字重清仓）
    static let rowTitle: Font = .body
    /// 正文：17 regular
    static let bodyText: Font = .body
    /// 行副题（设置状态副行/交付物类型小字）：15 regular
    static let rowSubtitle: Font = .subheadline
    /// 元信息（行尾时间戳/计数）：Footnote 13 regular
    /// （旧 subheadline 15 让位，HIG 时间戳档）
    static let meta: Font = .footnote
    /// 元信息等宽变体（服务器 host 等标识读数）
    static let metaMonospaced: Font = .system(
        .footnote, design: .monospaced
    )
    /// 分区头（全 App 统一）：Footnote 13 regular，墨
    /// 色由消费点给 secondary（苹果设置同款形态；旧
    /// subheadline 15 medium 让位）
    static let sectionLabel: Font = .footnote
    /// 说明小字（思考正文/引用条摘要/状态说明）：13 regular
    static let captionText: Font = .footnote
    /// 仅徽标：12，禁作正文
    static let badgeOnly: Font = .caption
}

// MARK: - 粗体文字映射（0.36.0，无障碍 A11Y-S3）
// 系统「粗体文本」开关的唯一接线点：挂在根视图
// 一处。策略在 Core BoldTextPolicy（关＝不干预、
// 开＝未钉字重的文本样式字体统一按 semibold 环
// 境字重渲染）；钉死字重的字体（Font.weight 烘
// 入）与近处显式 .fontWeight 声明不受环境字重影
// 响——与系统粗体文本的作用域一致。
public struct BoldTextRootModifier: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight

    public init() {}

    public func body(content: Content) -> some View {
        if let weight = BoldTextPolicy.rootWeight(
            boldTextEnabled: legibilityWeight == .bold
        ) {
            content.fontWeight(weight.fontWeight)
        } else {
            content
        }
    }
}

public extension View {
    /// 根视图挂一处，全 App 文本随系统粗体文本开
    /// 关（A11Y-S3）；非根处不许重复挂
    func boldTextMapping() -> some View {
        modifier(BoldTextRootModifier())
    }
}

private extension BoldTextPolicy.Weight {
    var fontWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}
