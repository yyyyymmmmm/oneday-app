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
    /// 字形尺寸带（pt）：全 App 框架字形同带。
    /// 2026-11-21 抽屉样板对齐包上沿 22→24——Muse
    /// 现行版抽屉线描图标框实测 24×24pt（图标墨迹
    /// 宽达 23.7），抽屉名单字形随之出带上行，本带
    /// 上沿同步抬至 24（其余字形仍在 20–22 旧带
    /// 内，见 pkg-drawer-muse-look-delivery-
    /// 20261121.md）
    public static let glyphSizeRange: ClosedRange<CGFloat> = 20...24

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
    /// 0.22.0 追认，字重 light）→21 regular（0.24.0
    /// HIG 落档）；2026-11-21 抽屉样板对齐包改 24：
    /// 用户亲递 Muse 现行版截图实测图标框 24×24、
    /// 墨迹宽达 23.7pt，SF 字形 21 渲染墨迹仅约
    /// 20.5 宽、明显小于样板——字号取 24 使墨迹落
    /// 样板带（约 23.5 宽），字重 regular 不变；
    /// glyphSizeRange 上沿同步抬至 24（见本文件头注）
    public static let drawerGlyphSize: CGFloat = 24
    /// 抽屉底条圆钮字形：第 24 条——齿轮与名单同线宽
    /// 档。2026-11-21 样板对齐包改 20：样板齿轮字形
    /// 实测 20×20pt、新建字形约 17.5pt——SF 两符号
    /// 墨迹比不同（gearshape 约 0.98、square.and.
    /// pencil 约 0.87），同字号 20 时墨迹恰各落
    /// 20/17.4，与样板两数同归一档（旧 17 齿轮墨迹
    /// 仅约 16.7、偏小一圈）
    public static let drawerBarGlyphSize: CGFloat = 20
    /// 设置页行字形：第 14 条——与同列统一复杂度档
    /// （密度上限由量测断言钉）；尺寸沿革：17（0.3.8）
    /// →24（0.20.0）→28（0.22.0 Muse 图量测追认）；
    /// 0.24.0 按用户当日指令改 21 regular——与抽屉名单
    /// 字形同值、落 glyphSizeRange 带内（见 §51）
    public static let settingsGlyphSize: CGFloat = 21
    /// 聊天气泡工具字形（＋/麦克风）：第 32 条——15pt
    /// regular，笔画目标约 1.8pt（16pt 时实测约 2.5）
    public static let composerGlyphSize: CGFloat = 15

    // MARK: - 宪法收编一期补充令牌（2026-11-22，台账 17 补包）
    // 上一包（提交 25561fe）收编一期范围内的图标字号时，
    // 因本表缺对应令牌而跳过了 21 条：19 条 10–13pt 小
    // 装饰图标 + 2 条 28/46pt 大图标。本节补齐实际用到
    // 的 6 档令牌（10/11/12/13/28/46pt），按尺寸升序排列。

    /// 徽标/角标字形：10pt（最小档，用于角标与极小装饰）
    public static let badgeGlyphSize: CGFloat = 10
    /// 极小装饰图标：11pt
    public static let tinyGlyphSize: CGFloat = 11
    /// 迷你装饰图标：12pt
    public static let miniGlyphSize: CGFloat = 12
    /// 小装饰图标：13pt（最常用的小图标尺寸）
    public static let smallGlyphSize: CGFloat = 13
    /// 大图标：28pt（连接状态等大型图标）
    public static let largeGlyphSize: CGFloat = 28
    /// 身份区超大字形：46pt（全仓最大字形，HubIdentitySection 专用）
    public static let identityGlyphSize: CGFloat = 46
    // MARK: - 收编二期补充令牌（2026-11-24，P2-01 字号收编续批）
    // 审计 P2-01 余量分拣：以下八档是字面量收编时令牌
    // 表无档的在用字形尺寸，按收编一期先例补齐（等值
    // 收编、渲染不变），逐处分拣表见 hig-p201-font-
    // sort-table-20261124.md。新写字形不许再用字面量，
    // 无档尺寸先在本表补档再消费。

    /// 行内伴随字形：14pt（披露 chevron、刷新、行内状态/动作字形）
    public static let inlineGlyphSize: CGFloat = 14
    /// 行内动作与状态字形：15pt（弹层/面板内动作、状态提示字形）
    public static let actionGlyphSize: CGFloat = 15
    /// 卡面与浮层重点字形：16pt（类别字形、工具卡、圆盘钮、卡头 ellipsis）
    public static let cardGlyphSize: CGFloat = 16
    /// 「更多」字形：18pt（卡头 ellipsis 专用；审核页 iconBox 18 为
    /// §434 量测光学值、属另一语义，不共用本档）
    public static let moreGlyphSize: CGFloat = 18
    /// 浮层大字形：26pt（媒体播放钮、查看器空态图）
    public static let overlayGlyphSize: CGFloat = 26
    /// 附件面板大动作字形：30pt（相机入口）
    public static let attachmentGlyphSize: CGFloat = 30
    /// 设计库 EmptyState 主字形：34pt
    public static let emptyStateGlyphSize: CGFloat = 34
    /// 空态大字形：44pt（EmptyState.swift 空态主图）
    public static let emptyStateLargeGlyphSize: CGFloat = 44
    /// 框架图标墨迹密度目标带（紧致 alpha 包围盒口径，
    /// RenderMeasureTests 同口径复量）：Muse 同位 13–21%
    /// ——注意本带是 17–18pt 小字形口径（0.3.6 定）；字
    /// 形放大到 24/27pt 时紧致密度系统性上移（同符号
    /// 24pt regular 实测 .27–.40），大字形面以「同尺寸
    /// light 档读数」为操作口径（0.22.0 探针，§49），
    /// 本带保留给小字形面
    public static let inkDensityTarget: ClosedRange<Double> = 0.10...0.24
}
