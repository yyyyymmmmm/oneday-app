import OneDayCore
import XCTest

/// 发送舱高度回归（DESIGN-V4 §11 定案、§12.3 改基数、
/// §13.2 行高校准）：0.2.5/0.2.6 两代的键盘膨胀都出在
/// 「高度没有单一权威」。0.2.7 起量高归 UITextView 本体
/// （ComposerTextView.sizeThatFits），应得高度的计算归
/// ComposerLayout 纯逻辑——本组单测把守四态：空／单行／
/// 多行／上限。0.2.8 单行规格由 54.5 改 46（真机量测对
/// 齐 Muse 约 45）：文本纵向边距 10、键直径 30、行边
/// 距 16。0.2.9 行高常数由近似 20 改 CI 帧实测 19.17
/// （2 行 38.33、4 行 76.67），封顶随之 115.02、胶囊上
/// 限 141.02；单行规格不变（键侧主导仍 46）。键盘态端
/// 到端观感由用户真机验收（既定分工）。
final class ComposerLayoutTests: XCTestCase {
    /// 空态：实测 0 也按一行计，胶囊总高＝单行规格 46
    func testEmptyCountsAsSingleLine() {
        XCTAssertEqual(
            ComposerLayout.effectiveTextHeight(measured: 0),
            19.17, accuracy: 0.01
        )
        let capsule = ComposerLayout.capsuleHeight(measured: 0)
        XCTAssertEqual(capsule, 46, accuracy: 0.001)
        XCTAssertTrue((45...46).contains(capsule), "空态胶囊高 \(capsule) 应在目标带 45–46 内")
        XCTAssertFalse(ComposerLayout.isMultiline(measured: 0))
        XCTAssertFalse(ComposerLayout.shouldScroll(measured: 0))
    }

    /// 单行：胶囊总高 46（目标带 45–46），不多行、不内滚
    func testSingleLineSpec() {
        let oneLine = ComposerLayout.textHeight(forLineCount: 1)
        XCTAssertEqual(oneLine, 19.17, accuracy: 0.01)
        let capsule = ComposerLayout.capsuleHeight(measured: oneLine)
        XCTAssertEqual(capsule, 46, accuracy: 0.001)
        XCTAssertTrue((45...46).contains(capsule))
        XCTAssertFalse(ComposerLayout.isMultiline(measured: oneLine))
        XCTAssertFalse(ComposerLayout.shouldScroll(measured: oneLine))
    }

    /// 多行：3 行文本高原样通过，胶囊随行数长（文本侧
    /// 接管：57.51＋10＋16＝83.51）；判为多行形态
    func testMultilineGrowsWithLines() {
        let threeLines = ComposerLayout.textHeight(forLineCount: 3)
        XCTAssertEqual(
            ComposerLayout.cappedTextHeight(measured: threeLines),
            57.51, accuracy: 0.01
        )
        XCTAssertEqual(
            ComposerLayout.capsuleHeight(measured: threeLines),
            83.51, accuracy: 0.01
        )
        XCTAssertTrue(ComposerLayout.isMultiline(measured: threeLines))
        XCTAssertFalse(ComposerLayout.shouldScroll(measured: threeLines))
        // 判据边界：恰 1.5 行（阈值 28.76）不多行，过阈值
        // 即多行；2 行起多行
        XCTAssertFalse(ComposerLayout.isMultiline(
            measured: ComposerLayout.multilineThreshold
        ))
        XCTAssertTrue(ComposerLayout.isMultiline(
            measured: ComposerLayout.multilineThreshold + 0.1
        ))
        XCTAssertTrue(ComposerLayout.isMultiline(
            measured: ComposerLayout.textHeight(forLineCount: 2)
        ))
    }

    /// 上限：7 行实测封顶在 6 行（115.02），胶囊 141.02，
    /// 且须内滚；恰在封顶值不内滚
    func testCapAtSixLines() {
        let sevenLines = ComposerLayout.textHeight(forLineCount: 7)
        XCTAssertEqual(
            ComposerLayout.cappedTextHeight(measured: sevenLines),
            115.02, accuracy: 0.01
        )
        XCTAssertEqual(
            ComposerLayout.capsuleHeight(measured: sevenLines),
            141.02, accuracy: 0.01
        )
        XCTAssertTrue(ComposerLayout.shouldScroll(measured: sevenLines))
        XCTAssertTrue(ComposerLayout.isMultiline(measured: sevenLines))
        XCTAssertFalse(ComposerLayout.shouldScroll(
            measured: ComposerLayout.maxTextHeight
        ))
        XCTAssertTrue(ComposerLayout.shouldScroll(
            measured: ComposerLayout.maxTextHeight + 0.1
        ))
    }
}
