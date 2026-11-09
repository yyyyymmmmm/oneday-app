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

    // MARK: - 0.3.8 分位尺寸（fixlist 第 15/24/32 条）

    /// 抽屉名单字形：第 15 条——与底栏同线宽档。尺寸
    /// 0.22.0 追认现行渲染 27（0.20.0 按 Muse 抽屉图
    /// 落值；第 15 条的 18 为历史档）；字重 0.22.0 起
    /// light（探针复量：regular 全候选紧致密度 .27–
    /// .41、light 降一档到 .22–.34，符号本身经量测不
    /// 换，见 DESIGN-V4 §49）
    public static let drawerGlyphSize: CGFloat = 27
    /// 抽屉底条圆钮字形：第 24 条——齿轮与名单同线宽档
    public static let drawerBarGlyphSize: CGFloat = 17
    /// 设置页行字形：第 14 条——与同列统一复杂度档
    /// （密度上限由量测断言钉）；尺寸 0.22.0 追认现行
    /// 渲染 28 regular（用户按 Muse 设置图实测量定：
    /// 行图标约 28–30 细线字形；0.3.8 的 17 与 0.20.0
    /// 的 24 均为历史档）
    public static let settingsGlyphSize: CGFloat = 28
    /// 聊天气泡工具字形（＋/麦克风）：第 32 条——15pt
    /// regular，笔画目标约 1.8pt（16pt 时实测约 2.5）
    public static let composerGlyphSize: CGFloat = 15
    /// 框架图标墨迹密度目标带（紧致 alpha 包围盒口径，
    /// RenderMeasureTests 同口径复量）：Muse 同位 13–21%
    /// ——注意本带是 17–18pt 小字形口径（0.3.6 定）；字
    /// 形放大到 24/27pt 时紧致密度系统性上移（同符号
    /// 24pt regular 实测 .27–.40），大字形面以「同尺寸
    /// light 档读数」为操作口径（0.22.0 探针，§49），
    /// 本带保留给小字形面
    public static let inkDensityTarget: ClosedRange<Double> = 0.10...0.24
}
