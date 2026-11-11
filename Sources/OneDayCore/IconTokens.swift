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

    // MARK: - 0.23.0 单源化（视觉审计 G3）
    // 本表自本版起是全 App 框架字形尺寸的唯一源：旧三
    // 源（本表／OneDayMetrics 的 navGlyph·tabGlyph·
    // rowIconGlyph／ListRowSpec 的字号字段）合一——
    // OneDayMetrics 三字段改引用本表（值不变）、
    // ListRowSpec 字号字段改挂字阶角色（TypeRole）不
    // 再自带图标数。逐项对账见 DESIGN-V4 §50。
    // 字重分位口径：0.22.0 定版为底栏/抽屉名单字形
    // light、设置 regular；0.24.0（用户 2026-11-10 指
    // 令：符号字重与文字同档）把抽屉名单/设置行字形
    // 改 regular——本轮范围只及设置与抽屉两面，底栏
    // 字形 light 是 0.22.0 探针定版、不在本轮范围，
    // 保留；本表只管尺寸，字重在各消费点按注记。

    /// 底栏字形：22（0.3.6 立宪带 21–22 上沿；原
    /// OneDayMetrics.tabGlyph 同值迁入）
    public static let tabGlyphSize: CGFloat = 22
    /// 名单导航字形：21（原 OneDayMetrics.navGlyph 同
    /// 值迁入；现行消费面为枢纽等名单行）
    public static let navGlyphSize: CGFloat = 21
    /// 内容行字形：20（原 OneDayMetrics.rowIconGlyph
    /// 同值迁入，ContentRow/UnifiedRow 消费）
    public static let rowGlyphSize: CGFloat = 20
    /// 文件类型盒单字字形：17（0.22.0 图标规格 v2 的
    /// W/P/X 白字档；§128 字母块渲染退役后无消费面，
    /// 值由 VisualDirectionGateTests 钉住保留，待令牌
    /// 卫生轮处置）
    public static let fileGlyphSize: CGFloat = 17

    // MARK: - 0.3.8 分位尺寸（fixlist 第 15/24/32 条）

    /// 抽屉名单字形：第 15 条——与底栏同线宽档。尺寸
    /// 沿革：18（第 15 条）→27（0.20.0 Muse 图落值、
    /// 0.22.0 追认，字重 light）；0.24.0 按用户当日
    /// 指令改 21 regular——落 glyphSizeRange 20–22 带
    /// 内、与设置行字形同值同档（HIG 侧栏/列表符号
    /// 惯例带，两面自此同尺，见 §51）
    public static let drawerGlyphSize: CGFloat = 21
    /// 抽屉底条圆钮字形：第 24 条——齿轮与名单同线宽档
    public static let drawerBarGlyphSize: CGFloat = 17
    /// 设置页行字形：第 14 条——与同列统一复杂度档
    /// （密度上限由量测断言钉）；尺寸沿革：17（0.3.8）
    /// →24（0.20.0）→28（0.22.0 Muse 图量测追认）；
    /// 0.24.0 按用户当日指令改 21 regular——与抽屉名单
    /// 字形同值、落 glyphSizeRange 带内（见 §51）
    public static let settingsGlyphSize: CGFloat = 21
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
