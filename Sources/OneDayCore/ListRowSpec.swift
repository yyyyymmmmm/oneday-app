import Foundation

/// 二级页统一行规格（0.3.8，基线补遗增量令 2「一种列表
/// 语法统治全应用」）：左图标列＋标题＋灰副题＋右浅灰元
/// 信息，四件冻死，各页只换图标与文案，不许各页自定行
/// 高/字号/列宽。发丝线与留白分段、几乎不用卡片框（卡
/// 片只留身份与生成内容两类）。Design 层 ContentRow /
/// UnifiedRow 按本表落值，单测钉住数值。
public enum ListRowSpec {
    /// 左图标列宽（图标在其内居中）
    public static let iconSlotWidth: CGFloat = 28
    /// 行最小高（单行 56；两行副题行 57 起由内容撑高）
    public static let minHeight: CGFloat = 56
    /// 两行制会话行最小高（抽屉名单与会话列表同值）
    public static let sessionRowMinHeight: CGFloat = 57
    /// 标题字号（17 regular，账本 navRowText/rowTitle）
    public static let titleSize: CGFloat = 17
    /// 副题字号（13 regular 灰）
    public static let subtitleSize: CGFloat = 13
    /// 右侧元信息字号（13，等宽数字口径由视图层落）
    public static let metaSize: CGFloat = 13
    /// 行内横向间距（图标列与文字列之间）
    public static let columnSpacing: CGFloat = 12
    /// 行横向内边距（与页面 gutter 同值）
    public static let horizontalPadding: CGFloat = 20
}
