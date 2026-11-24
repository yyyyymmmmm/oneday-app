import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest

/// 0.23.0 整机视觉定向的三设置检查闸（审计 G1/G2/G3
/// ＋native-ios-design 三设置检查的代码层落点）：不截
/// 图、不碰真机——以令牌数值、颜色解析实算与离线渲
/// 染量测把守三件事：①字阶角色表的数值对账＋角色字
/// 体真随 Dynamic Type 缩放；②文字对比按 WCAG 公式
/// 实算达标（inkMuted 的不达标也被钉住——它退出文
/// 字位的理由不许被后人改值改没）；③减透明回退裁
/// 决与图标令牌单源对账。
final class VisualDirectionGateTests: XCTestCase {

    // MARK: - 字阶角色表对账

    func testTypeRoleTable() {
        // 0.24.0 按 HIG 重排（用户当日指令）：行题/行
        // 内容题归 Body、名字头 Title1 28 bold、meta/
        // sectionLabel 归 Footnote、rowTitleLSemi 退役
        // ——九角色（断言随规格改值、非删测）
        // §157 增抽屉局部三角色（用户 2026-11-11 补
        // 充方案：导航 medium/次要 regular/当前 semi-
        // bold，只许抽屉消费）——十二角色
        // 2026-11-21 样板对齐包增 drawerTitle（抽屉身
        // 份名 Title2 22 bold，见 TypeRole 头注）——
        // 十三角色
        // 2026-11-22 抽屉量测对齐包 C 项：drawerTitle
        // 基准按用户亲令对齐样板实测改 24（title2 自
        // 此为相对缩放锚、weight 不变，见 TypeRole
        // 头注订正）——断言随规格改值、非删测
        // §364（台账 23，用户 2026-11-22 裁定同例
        // 扩展）增 contentListTitle（Title3 20
        // semibold，三面行题例外角色）——十四角色
        // §485（2026-11-24 目标页全抄修复）增
        // pageTitle（Title2 锚 24 bold，一级页页
        // 题）与 groupHeader（Title3 20 semibold，
        // 目标页分组头）两局部角色——十六角色
        let expected: [TypeRole: (style: String, pt: CGFloat, weight: String)] = [
            .screenName: ("title", 28, "bold"),
            .drawerTitle: ("title2", 24, "bold"),
            .pageTitle: ("title2", 24, "bold"),
            .groupHeader: ("title3", 20, "semibold"),
            .rowTitleL: ("body", 17, "regular"),
            .rowTitle: ("body", 17, "regular"),
            .bodyText: ("body", 17, "regular"),
            .rowSubtitle: ("subheadline", 15, "regular"),
            .meta: ("footnote", 13, "regular"),
            .sectionLabel: ("footnote", 13, "regular"),
            .captionText: ("footnote", 13, "regular"),
            .badgeOnly: ("caption", 12, "regular"),
            .drawerNavTitle: ("body", 17, "medium"),
            .drawerRowTitle: ("body", 17, "regular"),
            .drawerRowTitleCurrent: ("body", 17, "semibold"),
            .contentListTitle: ("title3", 20, "semibold"),
        ]
        XCTAssertEqual(Set(TypeRole.allCases), Set(expected.keys))
        for (role, spec) in expected {
            XCTAssertEqual(role.textStyleName, spec.style, "\(role) 样式名")
            XCTAssertEqual(role.defaultPointSize, spec.pt, "\(role) 默认字号")
            XCTAssertEqual(role.weightName, spec.weight, "\(role) 字重档")
        }
    }

    // MARK: - Dynamic Type 缩放（离线渲染量测）

    /// 角色字体在 AX 档必须真长大：固定号字体在此闸
    /// 下高度不变、当场现形——这是字阶双轨的机器判据
    @MainActor
    func testRoleFontsScaleWithDynamicType() {
        let roles: [(String, Font)] = [
            ("screenName", .screenName),
            ("rowTitleL", .rowTitleL),
            ("rowTitle", .rowTitle),
            ("meta", .meta),
            ("captionText", .captionText),
            // §157 抽屉局部角色同受本闸把守（带字重的
            // 文本样式字体也必须真随 Dynamic Type 缩放）
            // 2026-11-21：drawerTitle 同入闸——取文本
            // 样式档而非钉死 24 的理由正在于此
            // 2026-11-22 C 项：drawerTitle 的 Font 静
            // 态值已退役（基准 24 改 @ScaledMetric 相
            // 对缩放承载、Font 静态值表达不了），本列
            // 随之撤下；其缩放把守移交 DrawerMuse-
            // MetricsTests 的消费形态渲染测（同口径
            // 1.2 倍判据、测的是 DrawerView 实际消费
            // 形态），规格对账仍在本测 testTypeRole-
            // Table（24/title2/bold）
            ("drawerNavTitle", .drawerNavTitle),
            ("drawerRowTitle", .drawerRowTitle),
            ("drawerRowTitleCurrent", .drawerRowTitleCurrent),
            ("contentListTitle", .contentListTitle),
            // §485：groupHeader 有静态 Font、同入本
            // 闸；pageTitle 与 drawerTitle 同因不设
            // 静态值（@ScaledMetric 承载），不入本
            // 列——其规格对账在 testTypeRoleTable
            ("groupHeader", .groupHeader),
        ]
        for (name, font) in roles {
            let base = renderedTextHeight(font: font, category: .large)
            let ax = renderedTextHeight(
                font: font, category: .accessibilityExtraExtraExtraLarge
            )
            XCTAssertGreaterThan(
                ax, base * 1.2,
                "\(name) 在 AX3 下应显著长大（base \(base), ax \(ax)）"
            )
        }
    }

    @MainActor
    private func renderedTextHeight(
        font: Font, category: ContentSizeCategory
    ) -> CGFloat {
        let view = Text("Hermes 旁聊标题")
            .font(font)
            .environment(\.sizeCategory, category)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage?.size.height ?? 0
    }

    // MARK: - 对比度实算（Palette 解析值 × WCAG 公式）

    private func rgb(
        _ color: Color, dark: Bool
    ) -> (red: Double, green: Double, blue: Double) {
        var env = EnvironmentValues()
        env.colorScheme = dark ? .dark : .light
        let resolved = color.resolve(in: env)
        return (
            red: Double(resolved.red),
            green: Double(resolved.green),
            blue: Double(resolved.blue)
        )
    }

    private func ratio(
        _ foreground: Color, on background: Color, dark: Bool
    ) -> Double {
        WCAGContrast.ratio(
            foreground: rgb(foreground, dark: dark),
            background: rgb(background, dark: dark)
        )
    }

    /// α 合成对比（0.36.1，批一B）：暗档标签/fill 改挂
    /// α 语义色后，resolve 的 rgb 通道是未合成原值——
    /// 须按 α 把前景压在背景上再算（审计 D3/D4/D5 的
    /// 实算口径）。UIColor 解析与 RenderMeasure 同路
    private func compositedRatio(
        _ foreground: Color, on background: Color, dark: Bool
    ) -> Double {
        let traits = UITraitCollection(
            userInterfaceStyle: dark ? .dark : .light
        )
        func rgba(
            _ color: Color
        ) -> (red: Double, green: Double, blue: Double, alpha: Double) {
            var r: CGFloat = 0, g: CGFloat = 0
            var b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).resolvedColor(with: traits)
                .getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b), Double(a))
        }
        let f = rgba(foreground)
        let b = rgba(background)
        let composited = (
            red: f.red * f.alpha + b.red * (1 - f.alpha),
            green: f.green * f.alpha + b.green * (1 - f.alpha),
            blue: f.blue * f.alpha + b.blue * (1 - f.alpha)
        )
        return WCAGContrast.ratio(
            foreground: composited,
            background: (red: b.red, green: b.green, blue: b.blue)
        )
    }

    func testTextContrastGates() {
        // 浅色：正文与次级文字在页面底上 ≥4.5
        XCTAssertGreaterThanOrEqual(
            ratio(Palette.ink, on: Palette.pageBG, dark: false), 4.5
        )
        XCTAssertGreaterThanOrEqual(
            ratio(Palette.inkSecondary, on: Palette.pageBG, dark: false),
            4.5
        )
        // 0.36.0（审计 C1／无障碍 A11Y-C1）：同一色
        // 在设置底上原 4.46 压线——浅档加深一档
        // （#646B71）后必须 ≥4.5，最吃紧的底先过闸
        XCTAssertGreaterThanOrEqual(
            ratio(Palette.inkSecondary, on: Palette.settingsBG, dark: false),
            4.5
        )
        // 浅色：填充面次级文字（C4 新角色）在助手泡上 ≥4.5
        XCTAssertGreaterThanOrEqual(
            ratio(
                Palette.inkSecondaryOnFill, on: Palette.bubbleFill,
                dark: false
            ),
            4.5
        )
        // 暗色（0.36.1 改口径）：标签暗档改挂 α 语义色
        // 后必须按合成值算——次墨在三面（页底/卡面/泡
        // 面）自适应达标（实算 6.36/5.94/5.29），主墨
        // 纯白对纯黑页底充裕
        XCTAssertGreaterThanOrEqual(
            compositedRatio(
                Palette.inkSecondary, on: Palette.pageBG, dark: true
            ),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            compositedRatio(
                Palette.inkSecondary, on: Palette.surface, dark: true
            ),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            compositedRatio(
                Palette.inkSecondaryOnFill, on: Palette.bubbleFill,
                dark: true
            ),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            compositedRatio(
                Palette.ink, on: Palette.pageBG, dark: true
            ),
            4.5
        )
        // 暗档可见性闸（0.36.1，审计 D4/D5）：分隔线与
        // 发丝描边、选中填充压卡面合成对比 ≥1.4——旧
        // 实色口径分别为 1.17/1.17/1.12 近乎消失，新
        // 语义口径实算约 1.60/1.45/1.62（CI 实测过闸）
        XCTAssertGreaterThanOrEqual(
            compositedRatio(
                Palette.separator, on: Palette.surface, dark: true
            ),
            1.4
        )
        XCTAssertGreaterThanOrEqual(
            compositedRatio(
                Palette.hairline, on: Palette.surface, dark: true
            ),
            1.4
        )
        XCTAssertGreaterThanOrEqual(
            compositedRatio(
                Palette.selectionFill, on: Palette.surface, dark: true
            ),
            1.4
        )
        // 危险钉暗档版：inkMuted（tertiaryLabel α0.30）
        // 合成后仍不达标（实算 2.24）——非文字角色的
        // 理由在暗档同样钉住
        XCTAssertLessThan(
            compositedRatio(
                Palette.inkMuted, on: Palette.pageBG, dark: true
            ),
            4.5
        )
        // 危险钉：inkMuted 在页面底上就是不达标——它只
        // 许非文字用途；若有人给它提亮到达标，本断言提
        // 醒回看 G1 的角色分工（不是让它回文字位）
        XCTAssertLessThan(
            ratio(Palette.inkMuted, on: Palette.pageBG, dark: false), 4.5
        )
    }

    /// 对比闸⑧（2026-11-21，台账 191／DESIGN
    /// §334，与用户泡闸⑦成套）：AI 泡走中性令牌
    /// Palette.bubbleFill（主题无关）——正文字
    /// （bodyInk）/泡 ≥4.5 且次级字（inkSecondary-
    /// OnFill）/泡 ≥4.5（浅实算 15.36/5.04、暗
    /// 13.94/≈5.29）；泡/页（chatSurface）∈
    /// [1.10, 1.60]——下限保可辨、上限保安静（浅
    /// 1.13、暗 1.51；恒低于用户泡闸⑦的 2.9 线，
    /// 大厂入泡同级：iMessage 1.21/微信 1.17）。
    /// 次级字浅档与暗档合成口径同 testTextContrast-
    /// Gates 既有断言（彼处散列、本闸成套立名）；
    /// 令牌值本体由 RenderMeasureTests 逐值钉
    /// （浅 #EEEEF0/暗 #2C2C2E）
    func testAssistantBubbleContrastGate() {
        // 正文字/泡：两档 ≥4.5
        XCTAssertGreaterThanOrEqual(
            ratio(Palette.bodyInk, on: Palette.bubbleFill, dark: false),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            ratio(Palette.bodyInk, on: Palette.bubbleFill, dark: true),
            4.5
        )
        // 次级字/泡：浅档直算、暗档 α 合成（secondary-
        // Label 压泡面），两档 ≥4.5
        XCTAssertGreaterThanOrEqual(
            ratio(
                Palette.inkSecondaryOnFill, on: Palette.bubbleFill,
                dark: false
            ),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            compositedRatio(
                Palette.inkSecondaryOnFill, on: Palette.bubbleFill,
                dark: true
            ),
            4.5
        )
        // 泡/页：两档同入 [1.10, 1.60]
        for dark in [false, true] {
            let bubbleVsPage = ratio(
                Palette.bubbleFill, on: Palette.chatSurface, dark: dark
            )
            XCTAssertGreaterThanOrEqual(
                bubbleVsPage, 1.10,
                "dark=\(dark) AI 泡/页 \(bubbleVsPage)＜可辨下限 1.10"
            )
            XCTAssertLessThanOrEqual(
                bubbleVsPage, 1.60,
                "dark=\(dark) AI 泡/页 \(bubbleVsPage)＞安静上限 1.60"
            )
        }
    }

    /// 字形/填充对闸（2026-11-21，台账 197／DESIGN
    /// §335 补，与闸⑦成套）：浅填恢复后骑
    /// primaryPale 的字形对恒守 ≥4.5——主钮/发送
    /// 字（onPrimary＝泡字别名）压 primaryPale、
    /// 回底钮字形（ink）压 primaryPale 实填盘，
    /// 两档实算（默认款浅 13.84/13.84、暗 4.87/
    /// 4.87；主题经 AppearancePreferences 读口取
    /// 当前款、本测环境未设＝默认款）。配对纪律
    /// 本体（浅填只配深字、白字不压浅填）由
    /// ChatThemeTests 闸⑦的解析对全款钉守，本闸
    /// 守 Palette 别名链落到视图令牌后不脱钩
    func testPrimaryPaleGlyphPairingGate() {
        for dark in [false, true] {
            XCTAssertGreaterThanOrEqual(
                ratio(
                    Palette.onPrimary, on: Palette.primaryPale,
                    dark: dark
                ),
                4.5, "dark=\(dark) onPrimary/primaryPale"
            )
            XCTAssertGreaterThanOrEqual(
                ratio(
                    Palette.ink, on: Palette.primaryPale,
                    dark: dark
                ),
                4.5, "dark=\(dark) ink/primaryPale（回底钮字形）"
            )
        }
    }

    /// WCAG 公式自证（对审计报告的实算原值复算）
    func testWCAGFormulaAgainstAuditValues() {
        // inkSecondary #697176 on 页面底 #FCFCFC ≈ 4.84
        XCTAssertEqual(
            WCAGContrast.ratio(
                hexForeground: 0x697176, hexBackground: 0xFCFCFC
            ),
            4.84, accuracy: 0.05
        )
        // inkMuted #949B9F on #FCFCFC ≈ 2.75
        XCTAssertEqual(
            WCAGContrast.ratio(
                hexForeground: 0x949B9F, hexBackground: 0xFCFCFC
            ),
            2.75, accuracy: 0.05
        )
        // inkSecondaryOnFill #5F666B on 助手泡 #EEEEF0 ＝ 5.04
        // （首轮 CI 实测 5.035 推翻施工时估的 5.2，按实
        // 测校准——达标线 4.5 有余量，非规格变更）
        XCTAssertEqual(
            WCAGContrast.ratio(
                hexForeground: 0x5F666B, hexBackground: 0xEEEEF0
            ),
            5.04, accuracy: 0.05
        )
    }

    // MARK: - 减透明回退裁决

    func testTransparencyFallback() {
        XCTAssertEqual(
            TransparencyFallback.surface(reduceTransparency: true), .solid
        )
        XCTAssertEqual(
            TransparencyFallback.surface(reduceTransparency: false),
            .material
        )
    }

    // MARK: - 图标令牌单源对账

    func testIconTokenSingleSource() {
        // OneDayMetrics 三个别名必须与 Core 单源同值
        XCTAssertEqual(OneDayMetrics.navGlyph, FrameworkIcon.navGlyphSize)
        XCTAssertEqual(OneDayMetrics.tabGlyph, FrameworkIcon.tabGlyphSize)
        XCTAssertEqual(
            OneDayMetrics.rowIconGlyph, FrameworkIcon.rowGlyphSize
        )
        // 单源定版值（0.22.0 探针定版回填，§49/§50 对
        // 账表；0.24.0 抽屉/设置字形改 21，§51 对账；
        // 2026-11-21 样板对齐包抽屉名单字形改 24、底
        // 条字形改 20——样板实测，见 IconTokens 两令
        // 牌注）
        XCTAssertEqual(FrameworkIcon.tabGlyphSize, 22)
        XCTAssertEqual(FrameworkIcon.navGlyphSize, 21)
        XCTAssertEqual(FrameworkIcon.rowGlyphSize, 20)
        XCTAssertEqual(FrameworkIcon.drawerGlyphSize, 24)
        XCTAssertEqual(FrameworkIcon.drawerBarGlyphSize, 20)
        XCTAssertEqual(FrameworkIcon.settingsGlyphSize, 21)
        XCTAssertEqual(FrameworkIcon.composerGlyphSize, 15)
        XCTAssertEqual(FrameworkIcon.fileGlyphSize, 17)
    }
}
