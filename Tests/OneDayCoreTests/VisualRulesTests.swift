import OneDayCore
import XCTest

/// 视觉纪律纯逻辑（0.3.0，DESIGN-V4 §14 条 3/条 8）。
final class VisualRulesTests: XCTestCase {
    /// 条 3：命名档降一档，地板 100
    func testWeightStepsDownOneGrade() {
        XCTAssertEqual(VisualWeight.steppedDown(600), 500)
        XCTAssertEqual(VisualWeight.steppedDown(500), 400)
        XCTAssertEqual(VisualWeight.steppedDown(400), 300)
        XCTAssertEqual(VisualWeight.steppedDown(700), 600)
        XCTAssertEqual(VisualWeight.steppedDown(900), 800)
        XCTAssertEqual(VisualWeight.steppedDown(100), 100)
        // 非命名值先就近落档再降：560 → 600 → 500
        XCTAssertEqual(VisualWeight.steppedDown(560), 500)
    }

    /// 条 8：末两字绑定，末行不可能只剩孤字
    func testPrettyWrapBindsLastTwoGlyphs() {
        let shaped = TextShaping.prettyWrap("服务器一切正常")
        XCTAssertEqual(shaped, "服务器一切正\u{2060}常")
        XCTAssertFalse(TextShaping.prettyWrap("正常").contains("\u{2060}"))
        XCTAssertEqual(TextShaping.prettyWrap("好"), "好")
    }

    /// 条 8：末字为句末标点时绑三个字形
    func testPrettyWrapBindsThreeBeforeClosingPunctuation() {
        let shaped = TextShaping.prettyWrap("已经处理完了。")
        XCTAssertEqual(shaped, "已经处理\u{2060}完了。")
    }

    /// 条 8：含换行的行不整形；文档版逐行施加
    func testPrettyWrapDocumentAppliesPerLine() {
        let doc = TextShaping.prettyWrapDocument("第一行文字\n第二行")
        XCTAssertEqual(doc, "第一行文\u{2060}字\n第\u{2060}二行")
    }
}
