import OneDayCore
import XCTest

/// 视觉纪律纯逻辑（0.3.0，DESIGN-V4 §14 条 8）。
/// （条 3 字重降档用例已于 0.4.0 随 VisualWeight 删除）
final class VisualRulesTests: XCTestCase {
    /// 条 8：末两字绑定，末行不可能只剩孤字
    func testPrettyWrapBindsLastTwoGlyphs() {
        let shaped = TextShaping.prettyWrap("服务器一切正常")
        XCTAssertEqual(shaped, "服务器一切正\u{2060}常")
        XCTAssertFalse(TextShaping.prettyWrap("正常").contains("\u{2060}"))
        XCTAssertEqual(TextShaping.prettyWrap("好"), "好")
    }

    /// 条 8：末字为句末标点时绑三个字形（尾内逐对绑）
    func testPrettyWrapBindsThreeBeforeClosingPunctuation() {
        let shaped = TextShaping.prettyWrap("已经处理完了。")
        XCTAssertEqual(shaped, "已经处理完\u{2060}了\u{2060}。")
    }

    /// 条 8：含换行的行不整形；文档版逐行施加
    func testPrettyWrapDocumentAppliesPerLine() {
        let doc = TextShaping.prettyWrapDocument("第一行文字\n第二行")
        XCTAssertEqual(doc, "第一行文\u{2060}字\n第二\u{2060}行")
    }
}
