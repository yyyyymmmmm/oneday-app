import OneDayCore
import UIKit
import XCTest

/// 行高回字阶规格单源（2026-11-15 第 84 条，DESIGN
/// §265；审计 standards-audit-type-layout-20261115
/// §2 对齐项）：各面摘除自加 lineSpacing 后，pitch
/// 只由字阶规格 leading 决定。本组以固定多行串
/// 经 TextKit 实排、由相邻行片段原点差反推
/// pitch，钉两组锚：
/// ①字阶规格锚——涉案三字阶（Body/Subheadline/
///   Footnote）在默认 Large 档、无额外行距（＝各
///   面本包后的生产形态）下实排 pitch 须合 HIG
///   规格 leading 22/20/18。量测串用拉丁文：二
///   轮 CI 实证中文串在 TextKit 里由 CJK 回退字
///   体主导行高（三字阶 pitch 同率 1.1933＝回退
///   字体自然行高比、测不到字阶字体本体），拉
///   丁串字形全程走字阶字体本体、pitch 即其规
///   格 leading 的实排值；
/// ②输入舱锚——基准字体实排 pitch 须合
///   ComposerLayout.lineHeight 常数（常数与真实
///   排版脱钩即红——0.2.9 累计漂移事故的防线），
///   且基准字号已按主线裁定升 Body 17；此锚是
///   生产 TextKit 路径本体，量测串维持中文。
final class LineHeightSpecTests: XCTestCase {
    /// 四行定长中文串：显式换行、每行同字数；宽容
    /// 器下不缠绕——行数与 pitch 只由字体决定
    private static let fourLines =
        "行高规格量测中文串甲\n行高规格量测中文串乙\n"
        + "行高规格量测中文串丙\n行高规格量测中文串丁"

    /// 四行拉丁串（字阶锚专用，理由见文件头）：字
    /// 形全程走字阶字体本体
    private static let fourLatinLines =
        "Line height spec measure one\nLine height spec measure two\n"
        + "Line height spec measure three\nLine height spec measure four"

    /// TextKit 实排反推 pitch：相邻行片段原点差均值
    private func measuredPitch(
        font: UIFont, text: String
    ) -> CGFloat {
        let storage = NSTextStorage(
            string: text, attributes: [.font: font]
        )
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(
                width: 2000, height: CGFloat.greatestFiniteMagnitude
            )
        )
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        var origins: [CGFloat] = []
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(
                location: 0, length: layoutManager.numberOfGlyphs
            )
        ) { rect, _, _, _, _ in
            origins.append(rect.minY)
        }
        XCTAssertEqual(
            origins.count, 4,
            "定长串应排 4 行，实得 \(origins.count)"
        )
        guard origins.count >= 2 else { return 0 }
        return (origins.last! - origins.first!)
            / CGFloat(origins.count - 1)
    }

    /// Body（文档阅读页正文/引用/列表、点子正文的
    /// 字阶）：规格 17/22
    func testBodyPitchMatchesSpec() {
        let font = UIFont.preferredFont(forTextStyle: .body)
        XCTAssertEqual(font.pointSize, 17, accuracy: 0.01)
        XCTAssertEqual(
            measuredPitch(font: font, text: Self.fourLatinLines), 22, accuracy: 1.0,
            "Body 实排 pitch 应合规格 leading 22"
        )
    }

    /// Subheadline（通知摘要的 .rowSubtitle 字阶）：
    /// 规格 15/20
    func testSubheadlinePitchMatchesSpec() {
        let font = UIFont.preferredFont(
            forTextStyle: .subheadline
        )
        XCTAssertEqual(font.pointSize, 15, accuracy: 0.01)
        XCTAssertEqual(
            measuredPitch(font: font, text: Self.fourLatinLines), 20, accuracy: 1.0,
            "Subheadline 实排 pitch 应合规格 leading 20"
        )
    }

    /// Footnote（通知审批注的字阶）：规格 13/18
    func testFootnotePitchMatchesSpec() {
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        XCTAssertEqual(font.pointSize, 13, accuracy: 0.01)
        XCTAssertEqual(
            measuredPitch(font: font, text: Self.fourLatinLines), 18, accuracy: 1.0,
            "Footnote 实排 pitch 应合规格 leading 18"
        )
    }

    /// 输入舱：基准已升 17（与聊天正文 Body 同档），
    /// 实排 pitch 与 ComposerLayout 常数同源
    func testComposerPitchMatchesLayoutConstant() {
        XCTAssertEqual(
            ComposerTextMetrics.basePointSize, 17,
            accuracy: 0.01,
            "输入框基准应已升 Body 17（第 84 条裁定）"
        )
        let font = ComposerTextMetrics.bodyFont(for: .large)
        XCTAssertEqual(font.pointSize, 17, accuracy: 0.01)
        let pitch = measuredPitch(font: font, text: Self.fourLines)
        XCTAssertEqual(
            pitch, ComposerLayout.lineHeight(for: .large),
            accuracy: 0.5,
            "输入舱实排 pitch \(pitch) 与行高常数 "
                + "\(ComposerLayout.lineHeight(for: .large)) 脱钩"
        )
        XCTAssertEqual(
            pitch, 20.37, accuracy: 0.5,
            "输入舱实排 pitch \(pitch) 应合 17pt 基准行高 20.37"
        )
    }
}
