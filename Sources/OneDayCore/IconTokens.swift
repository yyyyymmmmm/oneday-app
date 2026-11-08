import Foundation

/// 图标变体令牌（0.3.7，DESIGN-V4 §22.5）：框架图标
/// （底栏/抽屉名单/导航行/顶栏与抽屉圆钮）一律 outline
/// 变体＋regular 字重——禁 .fill、禁 semibold。实测依
/// 据：0.3.6 真机底栏图标墨迹密度 55%/45%（实心砖），
/// Muse 同位 13–21%（细线）；观感目标靠 outline＋
/// regular 达成。内容缩略图与品牌图标豁免（内容有色
/// 原则），不在本令牌约束内。本表是令牌数值源，视图
/// 层字形配置按此落值，单测钉住。
public enum FrameworkIcon {
    /// 框架字形字重（CSS 量纲）：恒 regular
    public static let weightGrade = 400
    /// 框架位禁 .fill 变体（选中也不许，选中靠浅灰垫）
    public static let fillVariantAllowed = false
    /// 字形尺寸带（pt）：全 App 框架字形同带
    public static let glyphSizeRange: ClosedRange<CGFloat> = 20...22
}
