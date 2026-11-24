import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest

/// 2026-11-22 抽屉量测对齐包（DESIGN §345）：
/// Muse 抽屉真机截图逐项量测值落成令牌断言——
/// 量测全表见 oneday-design-review/drawer-muse-
/// metrics-20261122.md（截图 1206×2622px、逻辑
/// 402×874pt、系数 ×3、pt＝px÷3）。本套件只钉
/// 「量过且已对齐」的令牌值与浅档色值；机制类
/// （身份行顶注册＋名单顶缘 .soft 渐隐）由
/// DrawerSafeAreaRealRootTests 的 contentInset
/// .top＝0 与 adjusted＝115 断言钉；字形相撞/
/// 闪烁/深色逐项归真机门（量测表真机门四项）
final class DrawerMuseMetricsTests: XCTestCase {

    /// 行高：Muse 导航行与旁聊行 pitch 实测
    /// 44.2≈44、选中胶囊高＝行高 44；OneDay 两档
    /// 行高令牌同值 44（2026-11-21 样板对齐包已
    /// 落、本包复核）
    func testRowHeightsMatchMuse() {
        XCTAssertEqual(OneDayMetrics.drawerRowHeight, 44, accuracy: 0.5)
        XCTAssertEqual(OneDayMetrics.drawerNavRowHeight, 44, accuracy: 0.5)
    }

    /// 面板宽：Muse 实测 317.0pt；OneDay 宽比
    /// 0.79×402＝317.6，同归一线
    func testPanelWidthFractionMatchesMuse() {
        XCTAssertEqual(
            DrawerCardGeometry.travelWidthFraction, 0.79, accuracy: 0.005
        )
    }

    /// 图标几何：Muse 字形档 24、槽 30、文字墨
    /// 左缘 63（外 8＋内 12＋槽 30＋间距 12＋行左
    /// 缘 1 归一）；内容左边距 20
    func testIconGeometryMatchesMuse() {
        XCTAssertEqual(FrameworkIcon.drawerGlyphSize, 24, accuracy: 0.5)
        XCTAssertEqual(OneDayMetrics.iconSlot, 30, accuracy: 0.5)
        XCTAssertEqual(OneDayMetrics.drawerInset, 20, accuracy: 0.5)
        XCTAssertEqual(OneDayMetrics.spacingSM, 12, accuracy: 0.5)
        XCTAssertEqual(OneDayMetrics.spacingS, 8, accuracy: 0.5)
    }

    /// 底条：Muse 圆钮 Ø44–45、胶囊高 44–45、
    /// 控件中心距屏底 64；OneDay 圆钮/胶囊令牌
    /// 45、行盒 52、落位中心 64（落位由 Drawer-
    /// SafeAreaRealRootTests 的字段中心断言钉）
    func testBottomBarGeometryMatchesMuse() {
        XCTAssertEqual(OneDayMetrics.drawerBarButton, 45, accuracy: 0.5)
        XCTAssertEqual(DrawerGeometry.bottomBarRowHeight, 52, accuracy: 0.5)
    }

    /// 主面卡几何（台账 201）：圆角 54.5 与 Muse
    /// 采样拟合 52–58 同档（规格 §4 维持）；柔影
    /// 定值 radius 18/x −4/峰值 0.22——双层结构修
    /// 复后像素剖面实测落规格带内（贴边 227 级、
    /// 带外 −50pt 干净），定值经像素拟合确认沿用
    /// （成影本体由 RealRoot 接缝剖面测把守，本处
    /// 只钉数值单源不漂移）
    func testCardGeometryMatchesSpec() {
        XCTAssertEqual(DrawerCardGeometry.cornerRadius, 54.5, accuracy: 0.5)
        XCTAssertEqual(DrawerCardGeometry.verticalInset, 2, accuracy: 0.5)
        XCTAssertEqual(DrawerCardGeometry.shadowRadius, 18, accuracy: 0.5)
        XCTAssertEqual(DrawerCardGeometry.shadowX, -4, accuracy: 0.5)
        XCTAssertEqual(DrawerCardGeometry.shadowMaxOpacity, 0.22, accuracy: 0.005)
    }

    /// 浅档色值逐项（Muse 采样 ↔ OneDay 令牌）：
    /// 面板底 #FCFCFC、选中药丸 #EEEFF1、发丝线
    /// #E3E3E3（Muse 采样 #E2E2E2 同归一线）、
    /// 分区头墨 #9D9DA2（Muse 采样 #9FA0A2／
    /// #A1A1A4 同族）
    func testLightPaletteMatchesMuse() {
        assertLightHex(Palette.chatSurface, 0xFC, 0xFC, 0xFC, "面板底")
        assertLightHex(Palette.drawerSelectionFill, 0xEE, 0xEF, 0xF1, "选中药丸")
        assertLightHex(Palette.drawerHairline, 0xE3, 0xE3, 0xE3, "发丝线")
        assertLightHex(Palette.drawerSectionInk, 0x9D, 0x9D, 0xA2, "分区头墨")
    }

    /// 名字字号消费形态（C 项）：DrawerView 页头
    /// 同款 @ScaledMetric(relativeTo: .title2) 基
    /// 准 24——默认档渲染行高落 24 bold 档（≈29，
    /// 与旧 22 档 ≈26.6 可分辨），AX3 档须长大
    /// 1.2 倍以上（与 VisualDirectionGateTests 渲
    /// 染测同口径；drawerTitle 的 Font 静态值退役
    /// 后，缩放把守在此按实际消费形态续接）
    @MainActor
    func testDrawerNameFontScalesFrom24Base() {
        let base = nameProbeHeight(category: .large)
        let ax = nameProbeHeight(
            category: .accessibilityExtraExtraExtraLarge
        )
        XCTAssertGreaterThanOrEqual(
            base, 28, "默认档名字行高应 ≥28（24 bold 档）；实测 \(base)"
        )
        XCTAssertLessThanOrEqual(
            base, 31, "默认档名字行高应 ≤31；实测 \(base)"
        )
        XCTAssertGreaterThan(
            ax, base * 1.2,
            "AX3 应长大 1.2 倍以上（base \(base)、ax \(ax)）"
        )
    }

    private struct NameProbe: View {
        @ScaledMetric(relativeTo: .title2)
        var pointSize: CGFloat = 24

        var body: some View {
            Text("三狗")
                .font(.system(size: pointSize, weight: .bold))
        }
    }

    @MainActor
    private func nameProbeHeight(category: ContentSizeCategory) -> CGFloat {
        let view = NameProbe().environment(\.sizeCategory, category)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage?.size.height ?? 0
    }

    private func assertLightHex(
        _ color: Color, _ r: Int, _ g: Int, _ b: Int, _ label: String
    ) {
        let resolved = UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
        XCTAssertTrue(
            resolved.getRed(&cr, green: &cg, blue: &cb, alpha: &ca),
            "\(label)：浅档色值不可解析"
        )
        let tol = 1.5 / 255
        XCTAssertEqual(cr, CGFloat(r) / 255, accuracy: tol, "\(label) R 通道")
        XCTAssertEqual(cg, CGFloat(g) / 255, accuracy: tol, "\(label) G 通道")
        XCTAssertEqual(cb, CGFloat(b) / 255, accuracy: tol, "\(label) B 通道")
    }
}
