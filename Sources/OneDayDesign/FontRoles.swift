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
    /// 内容页大标题（§486）：动态/点子页头标题——
    /// LargeTitle 34 bold，与 Muse 参照页同档（审
    /// 计 three-pages-20261124 量测：参照 34pt、动
    /// 态页旧呈现低一档、点子页系统大标题同为 34，
    /// 自此两页共用本令牌钉死）；screenName（抽屉
    /// 名头 28）是另一角色，不合并
    static let pageTitle: Font = .largeTitle.weight(.bold)
    /// 内容标题（0.41.0 收口批 C14/P5 定点登记）：帖
    /// 子详情等「对象本体的标题」——不是界面行题、不
    /// 进 TypeRole 角色表（角色表只管界面文字）；与
    /// §51 Headline 定点同属内容层定点，消费点只许对
    /// 象标题（帖子详情题、文档阅读页题）
    static let contentTitle: Font = .title3.weight(.semibold)
    /// 内容 emoji 定点（§415 登记）：动态/点子行首
    /// 的内容 emoji（§117.5「emoji 是内容不是界面
    /// 图标」）——38pt 钉值配 44 帧，是内容层定点、
    /// 不是界面字阶，不进 TypeRole 角色表（与
    /// contentTitle/detailTitle 同种登记）；消费点
    /// 只许行首内容 emoji
    static let contentEmoji: Font = .system(size: 38)
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
    /// 内容行题（§364 局部角色，台账 23）：Title3
    /// 20 semibold——点子/动态/目标三面行题专用
    /// （§117.5 例外升档＋用户 2026-11-22 同例扩
    /// 展裁定，对位 Muse 实测约 20–21 semibold）；
    /// 只许三面行题消费、不许外溢（Core TypeRole
    /// .contentListTitle 对账）
    static let contentListTitle: Font = .title3.weight(.semibold)
    /// 分组头（§485 局部角色，目标页分组头专用）：
    /// Title3 20 semibold——照 Muse 目标页段头量测
    /// ≈18–20pt semibold 深色字（Core TypeRole
    /// .groupHeader 对账）；只许目标页分组头消费、
    /// 不许外溢（与 contentListTitle 同为局部例外，
    /// 消费面不同：彼为行题、此为段头）
    static let groupHeader: Font = .title3.weight(.semibold)
    /// 页题（§485）：基准 24 bold、Title2 锚——与
    /// drawerTitle 同因（24 无文本样式档、Font 静
    /// 态值承载不了相对缩放），本处不设静态值；规
    /// 格单源在 Core TypeRole.pageTitle，消费形态
    /// 在 GoalsView 的 GoalsPageTitle（@Scaled-
    /// Metric relativeTo: .title2 基准 24）
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
    /// 抽屉导航行题（§157 局部角色，用户 2026-11-11
    /// 21:01 抽屉补充方案）：Body 17 medium——抽屉内
    /// 主要导航（五导航行/频道行）比次要行重半档，
    /// 与名字头 Title1 bold、次要行 regular 之间补出
    /// 中间层级；只许抽屉消费（Core TypeRole.drawer-
    /// NavTitle 对账），不许外溢其他页面
    static let drawerNavTitle: Font = .body.weight(.medium)
    /// 抽屉次要行题（§157 局部角色）：Body 17 regular
    /// ——会话行题，弱于主要导航一档（Core TypeRole
    /// .drawerRowTitle 对账）；（§157 立时同档的「管
    /// 理全部对话」行题已随该行迁出抽屉退役——管理
    /// 收口包补件，用户 2026-11-13 18:57）
    static let drawerRowTitle: Font = .body
    /// 抽屉身份名（2026-11-21 样板对齐包新增局部角
    /// 色、2026-11-22 抽屉量测对齐包 C 项退役本静
    /// 态值）：基准已按用户亲令对齐样板实测 24
    /// bold，落法改 DrawerView 的 @ScaledMetric
    /// (relativeTo: .title2) 相对缩放——Font 静态
    /// 值承载不了相对缩放，本处不再有 drawerTitle
    /// 静态 Font；规格单源在 Core TypeRole.drawer-
    /// Title（title2 锚/24/bold），缩放把守在
    /// DrawerMuseMetricsTests 的消费形态渲染测。
    /// screenName 本体不动
    /// 抽屉当前行题（§157 局部角色）：Body 17 semi-
    /// bold——导航/频道/会话同一套选中规则的加重档，
    /// 恒与 selectionFill 浅灰底同出（Core TypeRole
    /// .drawerRowTitleCurrent 对账）
    static let drawerRowTitleCurrent: Font = .body.weight(.semibold)
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
