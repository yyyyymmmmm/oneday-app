import Foundation

/// 字重阶梯定版（0.3.3 全局审计立账，0.3.7 按 DESIGN-V4
/// §22.6 字重映射令牌改版）：全 App 文字角色 → CSS 字重
/// 的唯一账本。0.3.7 改版口径（用户真机纠正批：基线只冻
/// 颜色/圆角没冻字重，页面层沿用旧 semibold 默认）：
/// - regular 400：正文、行标题、行值、行副标题、分区
///   小标题——层级靠字号与灰度，不靠半粗
/// - bold 700：大标题/页标题/胶囊标题（标题位）、
///   Markdown 行内粗体（与正文拉开恰一档、不越上限）
/// - semibold 600 与 medium 500 退出账本：新代码不许
///   再有角色请求这两档（VisualWeight 档位表是换算
///   machinery，不在此列）
/// Design 层 TypeScale 各角色按此表落值，单测钉住数值
/// 与档距（正文→粗体差 300、粗体即上限不越界）。
public enum TextRoleWeights {
    /// 正文基重
    public static let body = 400
    /// 行右侧值
    public static let rowValue = 400
    /// 行副标题
    public static let rowSubtitle = 400
    /// 行标题（0.3.7 改版：semibold → regular，层级改靠
    /// 字号/灰度；设置页 0.3.4 已先行此口径，全局跟上）
    public static let rowTitle = 400
    /// 分区/空态小标题（0.3.7 改版：semibold → regular，
    /// 与 groupLabel 同档）
    public static let sectionTitle = 400
    /// 顶栏胶囊标题（标题位，0.3.7 改版：semibold → bold）
    public static let capsuleTitle = 700
    /// Markdown 行内粗体（0.3.7 改版：semibold → bold，
    /// 与正文拉开恰一档）
    public static let markdownStrong = 700
    /// Markdown 标题（走 TypeScale.title/largeTitle 的
    /// bold，0.3.7 改版 600 → 700）
    public static let heading = 700
    /// bold 上限：仅标题角色与 Markdown 粗体可用
    public static let boldCeiling = 700

    // MARK: - 0.3.8 增补（fixlist 第 4/5/16/29 条＋基线补遗字体补测）

    /// 设置页自绘大标题：第 4 条——系统大标题墨高实测
    /// 29.3pt（约 34pt black 量级），定版 30pt bold、
    /// 目标墨高约 25.7pt
    public static let settingsTitleSize: CGFloat = 30
    public static let settingsTitle = 700
    /// 气泡正文（双侧）：第 29 条——17pt regular，
    /// 不许跟标题位借 semibold
    public static let bubbleText = 400
    public static let bubbleTextSize: CGFloat = 17
    /// 名单/导航行文字：第 16 条——17pt regular
    public static let navRowText = 400
    public static let navRowTextSize: CGFloat = 17
    /// 内容标题（补遗字体补测合法领地）：内容卡/文章式
    /// 标题 19–21pt semibold——这是账本里 semibold 唯一
    /// 合法角色（框架位仍禁 600，见 boldCeiling 口径与
    /// §22.6 注）；框架页标题走 700 不走本角色
    public static let contentTitle = 600
    public static let contentTitleSizeRange: ClosedRange<CGFloat> = 19...21
}
