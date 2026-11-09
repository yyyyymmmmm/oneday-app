import OneDayCore
import SwiftUI

// MARK: - 设计令牌（v2 定版，见 docs/DESIGN-V2.md）
// 定版融合句沿礼记：「纸墨为体，玻璃为用。」内容层（分组、列表、
// 表单、消息）永远纸墨平面、零玻璃零阴影零描边；玻璃只活在功能
// 层（发送键），且染色只许走主题强调令牌（Palette.primary /
// primaryFill），禁止写死 hex。

// MARK: - 字阶（定版 §3.1：一个家族、七档、三字重）

/// 字体角色令牌：页面只许引用这里，不许自选字号字重。
/// 家族只有一个（系统 SF Pro，中文落 PingFang SC）；等宽角色只
/// 给四类真实数据：版本号、计数、时间、代码块。
public enum TypeScale {
    // —— 0.3.6 立宪字阶（§22 Muse 基线：全 HIG、字重
    // 只 regular/bold 两档；旧七档与 semibold/medium
    // 合法位与宪法冲突，归 0.3.7 页面轮统一，本三档
    // 先行供导航壳使用） ——
    /// 大标题（28 bold；抽屉智能体名字用；基线带 28–34）
    public static let largeTitle = Font.title.weight(.bold)
    /// 页标题（17 bold）
    public static let pageTitle = Font.body.weight(.bold)
    /// 分组标签（13 regular、次级灰；基线带 13–14）
    public static let groupLabel = Font.footnote
    /// 每屏唯一的排版时刻（0.3.7 账本改版：semibold →
    /// bold，§22.6——标题位只许 400/700 两档）
    public static let display = Font.title.weight(.bold)
    /// 页内大标题（连接页字标；0.3.7 改版同 display）
    public static let title = Font.title2.weight(.bold)
    /// 标题位文字（主按钮/空态题/智能体名；0.3.7 改版：
    /// Font.headline 的内建 semibold 退出账本，落 bold）
    public static let headline = Font.body.weight(.bold)
    /// 正文与助手回答
    public static let body = Font.body
    /// 次级正文（字段值、步骤名）
    public static let callout = Font.callout
    /// 说明文字（空态、错误正文）
    public static let subhead = Font.subheadline
    /// 元信息
    public static let footnote = Font.footnote
    /// 分区标题（0.3.7 改版：medium 退出账本，与
    /// groupLabel 同为 footnote regular、句首大写、无
    /// 字距，禁大写 eyebrow）
    public static let label = Font.footnote
    /// 最弱信息（时间戳）
    public static let caption = Font.caption
    /// 等宽正文（版本号、host 等读数）
    public static let monoBody = Font.system(.body, design: .monospaced)
    /// 等宽次级（模型名等标识符读数）
    public static let monoCallout = Font.system(.callout, design: .monospaced)
    /// 等宽元信息（计数）
    public static let monoFootnote = Font.system(.footnote, design: .monospaced)
    /// 等宽最弱信息（窄行内的标识符，如抽屉底行模型名）
    public static let monoCaption = Font.system(.caption, design: .monospaced)
    /// 等宽代码
    public static let monoCode = Font.system(.footnote, design: .monospaced)
    // —— 列表行角色（0.3.3 立、0.3.4 分域、0.3.7 改版）：
    // 0.3.3 的「标题 semibold 独响」被 §22.6 字重映射
    // 令牌推翻——行标题改 regular（层级靠字号与灰度，
    // 设置页 0.3.4 已先行此口径、全局跟上）；行图标按
    // §22.5 图标变体令牌改 regular 线条体（字号走
    // OneDayMetrics.rowIconGlyph 不变）。
    /// 行标题（0.3.7 改版：regular）
    public static let rowTitle = Font.body
    /// 行图标字形（0.3.7 改版：regular 线条体）
    public static let rowIcon = Font.system(
        size: OneDayMetrics.rowIconGlyph, weight: .regular
    )
    /// 行右侧值（regular，与 callout 同体）
    public static let rowValue = Font.callout
    /// 行副标题（regular，与 footnote 同体）
    public static let rowSubtitle = Font.footnote
    // —— 字重阶梯（0.3.3 全局审计立账，0.3.7 按 §22.6
    // 字重映射令牌改版，数值账在 OneDayCore.TextRole-
    // Weights、单测钉住）：正文/行位全 400 regular；
    // bold 700 只许标题位（大标题/页标题/胶囊题）与
    // Markdown 行内粗体（与正文拉开恰一档、不越上限）。
    // 600 semibold 与 500 medium 退出账本，新代码不许
    // 再有角色请求这两档。
    /// 胶囊标题（顶栏模型胶囊题，标题位 bold）
    public static let capsuleTitle = Font.system(size: 16, weight: .bold)
    /// 分区/空态小标题（0.3.7 改版：regular，与 callout 同体）
    public static let sectionTitle = Font.callout
    /// Markdown 行内粗体的目标字体（bold，与正文拉开
    /// 恰一档；解析侧按 intent 重映射，见 MarkdownText）
    public static let markdownStrong = Font.body.weight(.bold)
    /// 摘要卡/大卡的主读数（0.3.7 新增：28 bold，与
    /// largeTitle 同档；读数位另加 tabularDigits 防抖）
    public static let metricNumber = Font.system(size: 28, weight: .bold)
    /// 等宽大读数（模型名等标识符作摘要卡主读数时用，
    /// 0.3.7 新增：title3 等宽 bold）
    public static let monoTitle = Font.system(.title3, design: .monospaced)
        .weight(.bold)

    // —— 0.3.8 增补角色 ——
    /// 设置页自绘大标题（fixlist 第 4 条）：30 bold、
    /// 目标墨高约 25.7pt（系统大标题实测 29.3 已弃）；
    /// 尺寸/字重数值在账本 TextRoleWeights.settingsTitle*
    public static let settingsTitle = Font.system(
        size: TextRoleWeights.settingsTitleSize, weight: .bold
    )
    /// 气泡正文（fixlist 第 29 条）：17 regular 显式定版，
    /// 双侧气泡与流式文本共用（此前走 Font.body 名义同
    /// 值，本轮落显式角色供量测与单测钉）
    public static let bubbleBody = Font.system(
        size: TextRoleWeights.bubbleTextSize, weight: .regular
    )
    /// 内容标题（基线补遗字体补测合法领地）：19–21
    /// semibold 只许内容卡/文章式标题用，框架页标题仍
    /// 走 700 两档；本角色取带中 20
    public static let contentTitle = Font.system(size: 20, weight: .semibold)

    // —— 条 3 暗色降档变体（0.3.0，§14）：带权字体在暗色
    // 环境下经 VisualWeight 降一档；调用点以 colorScheme
    // 传入。未带权的字体（body/callout 等）由根环境
    // fontWeight 在暗色统一降档（ContentView 施加），两
    // 路合起来覆盖「所有文字」。
    public static func display(for scheme: ColorScheme) -> Font {
        Font.title.weight(.od(css: 700, scheme: scheme))
    }
    public static func title(for scheme: ColorScheme) -> Font {
        Font.title2.weight(.od(css: 700, scheme: scheme))
    }
    public static func label(for scheme: ColorScheme) -> Font {
        Font.footnote.weight(.od(css: 400, scheme: scheme))
    }
    /// 0.3.8 暗色审计补齐：此前只有 display/title/label
    /// 三个角色有降档变体，带权角色在暗色漏降——本轮补
    /// headline/capsuleTitle/metricNumber/monoTitle 四个
    /// （700 → 暗色 600 经 VisualWeight.steppedDown）
    public static func headline(for scheme: ColorScheme) -> Font {
        Font.body.weight(.od(css: 700, scheme: scheme))
    }
    public static func capsuleTitle(for scheme: ColorScheme) -> Font {
        Font.system(size: 16)
            .weight(.od(css: 700, scheme: scheme))
    }
    public static func metricNumber(for scheme: ColorScheme) -> Font {
        Font.system(size: 28)
            .weight(.od(css: 700, scheme: scheme))
    }
    public static func monoTitle(for scheme: ColorScheme) -> Font {
        Font.system(.title3, design: .monospaced)
            .weight(.od(css: 700, scheme: scheme))
    }
}

public extension Font.Weight {
    /// CSS 量纲字重（100–900）→ SwiftUI 字重；暗色环境
    /// 按 §14 条 3 降一档（映射表在 OneDayCore.VisualWeight，
    /// 单测把守）
    static func od(css: Int, scheme: ColorScheme) -> Font.Weight {
        let grade = scheme == .dark
            ? VisualWeight.steppedDown(css)
            : VisualWeight.nearestGrade(css)
        switch grade {
        case 100: return .ultraLight
        case 200: return .thin
        case 300: return .light
        case 500: return .medium
        case 600: return .semibold
        case 700: return .bold
        case 800: return .heavy
        case 900: return .black
        default: return .regular
        }
    }
}

// MARK: - 玻璃令牌（0.3.8 已删）
// Mat 三档与 odGlassButton/odGlassSurface 曾是玻璃期的
// 令牌入口；发送舱 0.3.0 去玻璃后全仓零调用（0.3.8 删残
// 审计 grep 实证），本轮整段删除。浮件画法由白浮纸接管
// （Palette.floatFill＋odFloatPaper），玻璃不再回来。

// MARK: - Elevation（定版 §3.4：只剩浮层一档，内容层零阴影）

/// 阴影规格令牌。
public struct ShadowSpec: Sendable {
    public let opacity: Double
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(opacity: Double, radius: CGFloat, x: CGFloat = 0, y: CGFloat) {
        self.opacity = opacity
        self.radius = radius
        self.x = x
        self.y = y
    }
}

public enum Elevation {
    /// 浮档：只给浮空输入区与浮空控件（中性黑、带 y 偏移的软影）
    public static let floating = ShadowSpec(opacity: 0.14, radius: 16, y: 6)
    /// 抽屉档（0.3.6 立宪）：peek 面板右缘约 30pt 柔影，
    /// 向右外扩、无纵向偏移
    public static let drawer = ShadowSpec(opacity: 0.12, radius: 30, x: 16, y: 0)
    /// 白浮纸档（0.3.8，fixlist 第 28 条）：浮件统一柔影
    /// ——输入框/胶囊/圆钮/抽屉底条/自绘底栏同此一档
    /// （比 floating 收一档，浮纸靠发丝边定位、影只兜底）
    public static let paper = ShadowSpec(opacity: 0.10, radius: 12, y: 4)
}

public extension View {
    func odElevation(_ shadow: ShadowSpec) -> some View {
        // 阴影色不用纯黑（§14 条 1）：统一走 Palette.shadowBase
        self.shadow(
            color: Palette.shadowBase.opacity(shadow.opacity),
            radius: shadow.radius, x: shadow.x, y: shadow.y
        )
    }
}

// MARK: - 圆角同心机制（子圆角由容器推导，禁止手算）

public enum CornerRadius {
    /// 同心圆角：内层元素圆角 = 容器圆角 − 内边距，下限 2pt。
    public static func concentric(container: CGFloat, padding: CGFloat) -> CGFloat {
        max(container - padding, 2)
    }
}

// MARK: - Motion 令牌册（0.3.2 按礼记四档纪律收编，DESIGN-V4 §17）
// 礼记四档 ↔ OneDay 对应：press（点按反馈）/ liquidSpring
// （跟手位移与指示器滑移）/ pageCrossfade（内容切换默认过
// 渡）/ 偶发入场档（礼记为 sealIn 落印专用，OneDay 无落印
// 面，由 entrance 占此档：每屏至多一次）。OneDay 既有定版
// 弹簧（dragSpring/microSpring，§14 条 9）归档入册不改值。
// 另有两支专用档：swap（内容替换/状态变化）、streamIn
// （流式词元入场，§14 条 4 定版 120ms）。
// 纪律：全仓动画只许引用本册并经 resolved() 出口（Reduce
// Motion 开启即瞬时）；散落字面量曲线禁止。例外只有系统
// 行为（sheet/系统符号过渡）与 TimelineView 驱动的状态指
// 示（非 .animation 落点）。
// 退出快于进入（审查 M-4 成文）：弹簧面开合共用同一弹簧
// （归位语义）；定时面退出时长 ≤ 进入的 0.8——系统 sheet/
// popover 走系统行为不自改，本条只约束自有动画面。

public enum MotionTokens {
    /// press：一切点按反馈（150ms 内出）。OneDay 定版值
    /// （审查 E-5 确认为强项：按下即响应、只动 opacity/
    /// transform）；礼记同档为 snappy 0.22，本 App 不跟
    /// ——档位对齐、取值按自家实测口径，如实记于 §17
    public static let press = Animation.easeOut(duration: 0.15)
    /// swap：内容替换、错误出现、步骤状态变化、折叠展开
    public static let swap = Animation.easeInOut(duration: 0.2)
    /// liquidSpring：跟手位移、选择指示器滑移（礼记定版
    /// 值 interactiveSpring 0.34/0.72；0.3.2 起取代旧
    /// indicator 档，旧值 spring(0.35, 0.85) 退役）
    public static let liquidSpring = Animation.interactiveSpring(
        response: 0.34, dampingFraction: 0.72
    )
    /// entrance：偶发入场，每屏至多一次
    public static let entrance = Animation.easeOut(duration: 0.45)
    /// 页面交叉淡化（礼记定版值 0.25，0.3.2 对齐）
    public static let pageCrossfade = Animation.easeInOut(duration: 0.25)
    /// streamIn：流式词元渐显入场（§14 条 4 定版 120ms）
    public static let streamIn = Animation.easeOut(duration: 0.12)
    /// 条 9 定版弹簧·拖拽类（0.3.0，§14）：stiffness
    /// 1200 / damping 80——换算阻尼比 ζ≈1.15（过阻尼、
    /// 零回弹），抽屉拖动跟随与归位、一切拖拽类交互走它。
    /// 速度交接注（审查 E-2）：SwiftUI 无初速度参数，松手
    /// 瞬间以动量投影定去向＋本弹簧归位近似，为平台上限
    public static let dragSpring = Animation.interpolatingSpring(
        stiffness: 1200, damping: 80
    )
    /// 条 9 定版弹簧·小动作（0.3.0，§14）：stiffness
    /// 380 / damping 18——换算阻尼比 ζ≈0.46（欠阻尼、
    /// 微弹），点赞类点按反馈、徽标与浮钮的出现/跳动走它
    public static let microSpring = Animation.interpolatingSpring(
        stiffness: 380, damping: 18
    )

    /// Reduce Motion 降级口径：开启时返回 nil（调用方以
    /// withAnimation(resolved) 包裹，nil 即瞬时切换）；Reduce
    /// Transparency 的降级由系统玻璃自动回退实色，不在代码层处理。
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
