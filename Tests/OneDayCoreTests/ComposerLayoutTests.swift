import OneDayCore
import XCTest

/// 发送舱高度回归（DESIGN-V4 §11）：0.2.5/0.2.6 两代的键盘
/// 膨胀都出在「高度没有单一权威」。0.2.7 起量高归 UITextView
/// 本体（ComposerTextView.sizeThatFits），应得高度的计算归
/// ComposerLayout 纯逻辑——本组单测把守四态：空／单行／
/// 多行／上限。键盘态的端到端观感由用户真机验收（既定
/// 分工），UI 层不再为聚焦驱动开诊断轮（见 §11.4）。
final class ComposerLayoutTests: XCTestCase {
    /// 空态：实测 0 也按一行计，胶囊总高＝单行规格 54±4
    func testEmptyCountsAsSingleLine() {
        XCTAssertEqual(ComposerLayout.effectiveTextHeight(measured: 0), 22.5)
        let capsule = ComposerLayout.capsuleHeight(measured: 0)
        XCTAssertEqual(capsule, 54.5, accuracy: 0.001)
        XCTAssertTrue((50...58).contains(capsule), "空态胶囊高 \(capsule) 应在 54±4 内")
        XCTAssertFalse(ComposerLayout.isMultiline(measured: 0))
        XCTAssertFalse(ComposerLayout.shouldScroll(measured: 0))
    }

    /// 单行：胶囊总高 54.5（规格 54±4），不多行、不内滚
    func testSingleLineSpec() {
        let oneLine = ComposerLayout.textHeight(forLineCount: 1)
        XCTAssertEqual(oneLine, 22.5)
        let capsule = ComposerLayout.capsuleHeight(measured: oneLine)
        XCTAssertEqual(capsule, 54.5, accuracy: 0.001)
        XCTAssertTrue((50...58).contains(capsule))
        XCTAssertFalse(ComposerLayout.isMultiline(measured: oneLine))
        XCTAssertFalse(ComposerLayout.shouldScroll(measured: oneLine))
    }

    /// 多行：3 行文本高原样通过，胶囊随行数长；判为多行形态
    func testMultilineGrowsWithLines() {
        let threeLines = ComposerLayout.textHeight(forLineCount: 3)
        XCTAssertEqual(ComposerLayout.cappedTextHeight(measured: threeLines), 67.5)
        XCTAssertEqual(
            ComposerLayout.capsuleHeight(measured: threeLines), 99.5,
            accuracy: 0.001
        )
        XCTAssertTrue(ComposerLayout.isMultiline(measured: threeLines))
        XCTAssertFalse(ComposerLayout.shouldScroll(measured: threeLines))
        // 判据边界：恰 1.5 行不多行，2 行起多行
        XCTAssertFalse(ComposerLayout.isMultiline(measured: 33.75))
        XCTAssertTrue(ComposerLayout.isMultiline(
            measured: ComposerLayout.textHeight(forLineCount: 2)
        ))
    }

    /// 上限：7 行实测封顶在 6 行（135），胶囊 167，且须内滚；
    /// 恰在封顶值不内滚
    func testCapAtSixLines() {
        let sevenLines = ComposerLayout.textHeight(forLineCount: 7)
        XCTAssertEqual(ComposerLayout.cappedTextHeight(measured: sevenLines), 135)
        XCTAssertEqual(
            ComposerLayout.capsuleHeight(measured: sevenLines), 167,
            accuracy: 0.001
        )
        XCTAssertTrue(ComposerLayout.shouldScroll(measured: sevenLines))
        XCTAssertTrue(ComposerLayout.isMultiline(measured: sevenLines))
        XCTAssertFalse(ComposerLayout.shouldScroll(measured: 135))
        XCTAssertTrue(ComposerLayout.shouldScroll(measured: 135.1))
    }
}
