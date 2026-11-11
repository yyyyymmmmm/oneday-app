import OneDayDesign
@testable import OneDayCore
import SwiftUI
import UIKit
import XCTest

/// 无障碍专项钉测（0.43.0，上架线 A11Y 包）：只钉
/// 可离线判定的合同——V2 标签拼装、D1 档位映射与
/// 发送舱按档几何（基准档与旧定案逐字一致）、S5
/// 高对比解析（默认解析不变＋HC 档全过 7:1）。
/// 视图层语义（Rotor/合并/特征）无离线判据、归真
/// 机 VO 走查（DESIGN §112 自查表）
final class AccessibilityPackageTests: XCTestCase {
    private let zhHans = Locale(identifier: "zh-Hans")

    // MARK: - V2 图片标签拼装

    /// 无文件名（nil/空）回落裸词——不编造描述
    func testImageLabelFallsBackToBareWord() {
        XCTAssertEqual(
            A11yText.imageLabel(fileName: nil, locale: zhHans), "图片"
        )
        XCTAssertEqual(
            A11yText.imageLabel(fileName: "", locale: zhHans), "图片"
        )
    }

    /// 有文件名拼「图片，<文件名>」
    func testImageLabelUsesFileName() {
        XCTAssertEqual(
            A11yText.imageLabel(
                fileName: "report.pdf", locale: zhHans
            ),
            "图片，report.pdf"
        )
    }

    /// 本地图以发送时刻拼（HH:mm 模板、三语同制式；
    /// 日历钉 UTC 免时区漂移）
    func testImageLabelUsesSentTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = DateComponents(
            calendar: calendar, year: 2026, month: 11, day: 11,
            hour: 14, minute: 32
        ).date!
        XCTAssertEqual(
            A11yText.imageLabel(
                sentAt: date, calendar: calendar, locale: zhHans
            ),
            "图片，14:32"
        )
    }

    // MARK: - D1 档位映射

    /// SwiftUI 十二档 → UIKit 档逐项同名对应——映射
    /// 错一档，量测与排版就在该档脱钩（D1 的命门）
    func testDynamicTypeSizeCategoryMapping() {
        let pairs: [(DynamicTypeSize, UIContentSizeCategory)] = [
            (.xSmall, .extraSmall),
            (.small, .small),
            (.medium, .medium),
            (.large, .large),
            (.xLarge, .extraLarge),
            (.xxLarge, .extraExtraLarge),
            (.xxxLarge, .extraExtraExtraLarge),
            (.accessibility1, .accessibilityMedium),
            (.accessibility2, .accessibilityLarge),
            (.accessibility3, .accessibilityExtraLarge),
            (.accessibility4, .accessibilityExtraExtraLarge),
            (.accessibility5, .accessibilityExtraExtraExtraLarge),
        ]
        XCTAssertEqual(pairs.count, 12)
        for (size, category) in pairs {
            XCTAssertEqual(
                size.contentSizeCategory, category,
                "档位映射错位：\(size)"
            )
        }
    }

    // MARK: - D1 发送舱按档几何

    /// 基准档字体恒 16pt（0.2.9 定案不漂移）；档位
    /// 两端单调（小档更小、AX 档更大）
    func testBodyFontScalesWithCategory() {
        XCTAssertEqual(
            ComposerTextMetrics.bodyFont(for: .large).pointSize,
            16, accuracy: 0.01
        )
        XCTAssertLessThan(
            ComposerTextMetrics.bodyFont(for: .extraSmall).pointSize,
            16
        )
        XCTAssertGreaterThan(
            ComposerTextMetrics.bodyFont(
                for: .accessibilityExtraExtraExtraLarge
            ).pointSize,
            16
        )
    }

    /// 行高派生：基准档与定案常数逐字相同；任意档
    /// 行高＝常数 × 该档字号比（同源派生、无第二张
    /// 档位表）；全梯非递减
    func testLineHeightDerivation() {
        XCTAssertEqual(
            ComposerLayout.lineHeight(for: .large),
            ComposerLayout.lineHeight, accuracy: 0.0001
        )
        let ax = UIContentSizeCategory.accessibilityExtraLarge
        let expected = ComposerLayout.lineHeight
            * ComposerTextMetrics.bodyFont(for: ax).pointSize / 16
        XCTAssertEqual(
            ComposerLayout.lineHeight(for: ax), expected,
            accuracy: 0.0001
        )
        let ladder: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge,
            .extraExtraLarge, .extraExtraExtraLarge,
            .accessibilityMedium, .accessibilityLarge,
            .accessibilityExtraLarge,
            .accessibilityExtraExtraLarge,
            .accessibilityExtraExtraExtraLarge,
        ]
        let heights = ladder.map { ComposerLayout.lineHeight(for: $0) }
        for (lower, higher) in zip(heights, heights.dropFirst()) {
            XCTAssertLessThanOrEqual(lower, higher)
        }
        XCTAssertLessThan(heights.first!, heights.last!)
    }

    /// 封顶与胶囊基准：.large 档下旧钉值全数不变
    /// （封顶 115.02、空文案胶囊 46）；AX 档胶囊随
    /// 行高长高（发送舱在大字下不截字的几何前提）
    func testComposerBaselineUnchangedAndAXGrows() {
        XCTAssertEqual(
            ComposerLayout.maxTextHeight(for: .large),
            115.02, accuracy: 0.001
        )
        XCTAssertEqual(
            ComposerTextMetrics.capsuleHeight(
                for: "", containerWidth: 402, category: .large
            ),
            46, accuracy: 0.001
        )
        XCTAssertGreaterThan(
            ComposerTextMetrics.capsuleHeight(
                for: "", containerWidth: 402,
                category: .accessibilityExtraExtraExtraLarge
            ),
            46
        )
    }

    /// 文本高按档贯穿：空文案恒一行、行高取同档
    func testTextHeightThreadsCategory() {
        let ax = UIContentSizeCategory.accessibilityLarge
        XCTAssertEqual(
            ComposerTextMetrics.textHeight(
                for: "", width: 270, category: ax
            ),
            ComposerLayout.lineHeight(for: ax), accuracy: 0.0001
        )
    }

    // MARK: - S5 高对比解析

    private func resolvedHex(
        _ color: Color, traits: UITraitCollection
    ) -> (red: Double, green: Double, blue: Double) {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0
        var b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    private func assertHex(
        _ actual: (red: Double, green: Double, blue: Double),
        _ hex: UInt32, _ message: String
    ) {
        XCTAssertEqual(
            actual.red, Double((hex >> 16) & 0xFF) / 255.0,
            accuracy: 0.004, message
        )
        XCTAssertEqual(
            actual.green, Double((hex >> 8) & 0xFF) / 255.0,
            accuracy: 0.004, message
        )
        XCTAssertEqual(
            actual.blue, Double(hex & 0xFF) / 255.0,
            accuracy: 0.004, message
        )
    }

    /// 默认（普通对比）解析与旧值逐字相同——S5 只
    /// 动高对比 traits、默认外观零变化的闸
    func testHighContrastLeavesDefaultResolutionUnchanged() {
        let plain = UITraitCollection(userInterfaceStyle: .light)
        assertHex(
            resolvedHex(Palette.inkSecondary, traits: plain),
            0x646B71, "inkSecondary 默认浅档解析漂移"
        )
        assertHex(
            resolvedHex(Palette.danger, traits: plain),
            0xAA4A45, "danger 默认浅档解析漂移"
        )
    }

    /// 高对比浅档：inkSecondary 解析为加深变体且三
    /// 面（设置底/页面底/卡面）全过 7:1；danger 变
    /// 体对卡面与错误面全过 7:1
    func testHighContrastVariantsPassSevenToOne() {
        let hc = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .light),
            UITraitCollection(accessibilityContrast: .high),
        ])
        assertHex(
            resolvedHex(Palette.inkSecondary, traits: hc),
            0x43494E, "inkSecondary 高对比变体未生效"
        )
        for background: UInt32 in [0xF2F2F7, 0xFCFCFC, 0xFFFFFF] {
            let ratio = WCAGContrast.ratio(
                hexForeground: 0x43494E, hexBackground: background
            )
            XCTAssertGreaterThanOrEqual(
                ratio, 7.0,
                "inkSecondary HC 对 \(String(background, radix: 16)) 仅 \(ratio)"
            )
        }
        assertHex(
            resolvedHex(Palette.danger, traits: hc),
            0x8C332C, "danger 高对比变体未生效"
        )
        for background: UInt32 in [0xFFFFFF, 0xFBEFED] {
            let ratio = WCAGContrast.ratio(
                hexForeground: 0x8C332C, hexBackground: background
            )
            XCTAssertGreaterThanOrEqual(
                ratio, 7.0,
                "danger HC 对 \(String(background, radix: 16)) 仅 \(ratio)"
            )
        }
    }
}
