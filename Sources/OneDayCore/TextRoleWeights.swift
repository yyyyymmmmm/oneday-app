import Foundation

/// 字重阶梯定版（0.3.3 全局审计，DESIGN-V4 §18）：全 App
/// 文字角色 → CSS 字重的唯一账本。阶梯（用户点破的要害：
/// 正文已粗则加粗无层级可走）：
/// - 正文（助手 Markdown 段落、流式文本、用户气泡）＝400
/// - 行标题／胶囊标题／分区题／Markdown 粗体＝600
/// - bold 700 只许标题角色（上限封顶），不作正文强调
/// 礼记与 Muse 本体正文均为 regular，此账与之同构。
/// Design 层 TypeScale 各角色按此表落值，单测钉住数值
/// 与档距（正文→粗体恰一档、粗体不越标题上限）。
public enum TextRoleWeights {
    /// 正文基重
    public static let body = 400
    /// 行右侧值
    public static let rowValue = 400
    /// 行副标题
    public static let rowSubtitle = 400
    /// 行标题（列表内唯一半粗位）
    public static let rowTitle = 600
    /// 顶栏胶囊标题
    public static let capsuleTitle = 600
    /// 分区/空态小标题
    public static let sectionTitle = 600
    /// Markdown 行内粗体（与正文拉开恰一档）
    public static let markdownStrong = 600
    /// Markdown 标题（H1 走 TypeScale.title 的 600）
    public static let heading = 600
    /// bold 上限：仅标题角色可用，正文强调禁入
    public static let boldCeiling = 700
}
