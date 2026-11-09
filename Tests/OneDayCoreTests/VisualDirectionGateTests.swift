import OneDayCore
import OneDayDesign
import SwiftUI
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
        let expected: [TypeRole: (style: String, pt: CGFloat, weight: String)] = [
            .screenName: ("largeTitle", 34, "semibold"),
            .rowTitleL: ("title3", 20, "regular"),
            .rowTitleLSemi: ("title3", 20, "semibold"),
            .rowTitle: ("headline", 17, "semibold"),
            .bodyText: ("body", 17, "regular"),
            .rowSubtitle: ("subheadline", 15, "regular"),
            .meta: ("subheadline", 15, "regular"),
            .sectionLabel: ("subheadline", 15, "medium"),
            .captionText: ("footnote", 13, "regular"),
            .badgeOnly: ("caption", 12, "regular"),
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

    func testTextContrastGates() {
        // 浅色：正文与次级文字在页面底上 ≥4.5
        XCTAssertGreaterThanOrEqual(
            ratio(Palette.ink, on: Palette.pageBG, dark: false), 4.5
        )
        XCTAssertGreaterThanOrEqual(
            ratio(Palette.inkSecondary, on: Palette.pageBG, dark: false),
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
        // 暗色：同三对在暗色派生值上同样达标
        XCTAssertGreaterThanOrEqual(
            ratio(Palette.inkSecondary, on: Palette.pageBG, dark: true),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            ratio(
                Palette.inkSecondaryOnFill, on: Palette.bubbleFill,
                dark: true
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
        // inkSecondaryOnFill #5F666B on 助手泡 #EEEEF0 ≈ 5.2
        XCTAssertEqual(
            WCAGContrast.ratio(
                hexForeground: 0x5F666B, hexBackground: 0xEEEEF0
            ),
            5.2, accuracy: 0.1
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
        // 单源定版值（0.22.0 探针定版回填，§49/§50 对账表）
        XCTAssertEqual(FrameworkIcon.tabGlyphSize, 22)
        XCTAssertEqual(FrameworkIcon.navGlyphSize, 21)
        XCTAssertEqual(FrameworkIcon.rowGlyphSize, 20)
        XCTAssertEqual(FrameworkIcon.drawerGlyphSize, 27)
        XCTAssertEqual(FrameworkIcon.drawerBarGlyphSize, 17)
        XCTAssertEqual(FrameworkIcon.settingsGlyphSize, 28)
        XCTAssertEqual(FrameworkIcon.composerGlyphSize, 15)
        XCTAssertEqual(FrameworkIcon.fileGlyphSize, 17)
    }
}
