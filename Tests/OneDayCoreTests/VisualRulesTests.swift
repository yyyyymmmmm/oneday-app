import OneDayCore
import XCTest

/// 视觉纪律纯逻辑（0.3.0，DESIGN-V4 §14 条 8）。
/// （条 3 字重降档用例已于 0.4.0 随 VisualWeight 删除）
final class VisualRulesTests: XCTestCase {
    /// 条 8 沿革：尾行孤字绑定已于台账 200 件四
    /// 退役（2026-11-22，用户拍板）——整形往字间
    /// 插 U+2060，污染找字/复制/读屏且曾劈数据检
    /// 测令牌。本组钉死新口径：任何输入恒原样返回
    func testPrettyWrapReturnsInputVerbatim() {
        XCTAssertEqual(
            TextShaping.prettyWrap("服务器一切正常"),
            "服务器一切正常")
        XCTAssertEqual(
            TextShaping.prettyWrap("已经处理完了。"),
            "已经处理完了。")
        XCTAssertEqual(TextShaping.prettyWrap("正常"), "正常")
        XCTAssertEqual(TextShaping.prettyWrap("好"), "好")
        XCTAssertFalse(
            TextShaping.prettyWrap("服务器一切正常")
                .contains("\u{2060}"))
    }

    func testPrettyWrapDocumentReturnsInputVerbatim() {
        let doc = "第一行文字\n第二行"
        XCTAssertEqual(TextShaping.prettyWrapDocument(doc), doc)
    }
}
