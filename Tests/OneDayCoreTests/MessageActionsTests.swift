import OneDayCore
import UIKit
import XCTest

/// 消息长按四件的纯逻辑（0.4.1）：引用摘要/注入拼装
/// 与 Markdown 纯文本口径。视图层（contextMenu 本体）
/// 不在此测——手势与菜单呈现是系统件，逻辑只此一层
final class MessageActionsTests: XCTestCase {

    // MARK: - 引用：称呼与摘要

    func testSpeakerNames() {
        XCTAssertEqual(MessageQuote.speakerName(for: "assistant"), "Hermes")
        XCTAssertEqual(MessageQuote.speakerName(for: "user"), "我")
        XCTAssertEqual(MessageQuote.speakerName(for: "tool"), "对方")
    }

    func testSummaryCollapsesWhitespace() {
        let quote = MessageQuote(
            role: "assistant", content: "第一行\n\n  第二行\t继续  "
        )
        XCTAssertEqual(quote.summary(), "第一行 第二行 继续")
    }

    func testSummaryTruncatesWithEllipsis() {
        let quote = MessageQuote(
            role: "user", content: String(repeating: "字", count: 100)
        )
        let summary = quote.summary(maxLength: 10)
        XCTAssertEqual(summary.count, 11)
        XCTAssertTrue(summary.hasSuffix("…"))
    }

    // MARK: - 引用：上下文注入

    func testOutgoingWithoutQuoteIsUnchanged() {
        XCTAssertEqual(
            MessageQuote.outgoingContent(userText: "正文", quote: nil),
            "正文"
        )
    }

    func testOutgoingWithQuotePrependsBlock() {
        let quote = MessageQuote(role: "assistant", content: "旧回复")
        XCTAssertEqual(
            MessageQuote.outgoingContent(userText: "就这条展开", quote: quote),
            "[引用 Hermes 的消息]\n旧回复\n\n就这条展开"
        )
    }

    func testOutgoingWithQuoteAndEmptyTextIsBlockOnly() {
        let quote = MessageQuote(role: "user", content: "我之前说的")
        XCTAssertEqual(
            MessageQuote.outgoingContent(userText: "", quote: quote),
            "[引用 我 的消息]\n我之前说的"
        )
    }

    func testInjectionTruncatesLongQuoteWithNotice() {
        let long = String(
            repeating: "a",
            count: MessageQuote.injectionCharacterLimit + 50
        )
        let quote = MessageQuote(role: "assistant", content: long)
        let composed = MessageQuote.outgoingContent(
            userText: "问", quote: quote
        )
        XCTAssertTrue(composed.contains("…（以下省略）"))
        XCTAssertTrue(composed.hasSuffix("问"))
        // 引用块本体不超过上限＋标记行＋省略注的量级
        XCTAssertLessThan(
            composed.count,
            MessageQuote.injectionCharacterLimit + 60
        )
    }

    // MARK: - 纯文本口径

    func testPlainTextStripsHeadingsAndEmphasis() {
        let markdown = "# 标题\n正文有 **粗体** 和 *斜体* 与 `代码`。"
        XCTAssertEqual(
            MessagePlainText.make(from: markdown),
            "标题\n正文有 粗体 和 斜体 与 代码。"
        )
    }

    func testPlainTextKeepsFencedCodeVerbatim() {
        let markdown = "看这段：\n```swift\nlet x = \"**不是粗体**\"\n```\n完。"
        XCTAssertEqual(
            MessagePlainText.make(from: markdown),
            "看这段：\nlet x = \"**不是粗体**\"\n完。"
        )
    }

    func testPlainTextLinksKeepTextAndURL() {
        let markdown = "见 [文档](https://example.com/doc) 与 ![示意图](https://example.com/a.png)"
        XCTAssertEqual(
            MessagePlainText.make(from: markdown),
            "见 文档（https://example.com/doc） 与 示意图"
        )
    }

    func testPlainTextBlockquoteAndRule() {
        let markdown = "> 引用的话\n---\n下一段"
        XCTAssertEqual(
            MessagePlainText.make(from: markdown),
            "引用的话\n下一段"
        )
    }

    func testPlainTextLeavesUnpairedMarkersAlone() {
        // 落单星号（乘法/脚注式写法）不许误剥
        XCTAssertEqual(MessagePlainText.make(from: "3 * 5 = 15"), "3 * 5 = 15")
    }

    // MARK: - 菜单符号存在性（写错名 CI 当场红）

    func testMenuSymbolsExist() {
        for name in MessageActionSymbols.all {
            XCTAssertNotNil(
                UIImage(systemName: name),
                "SF Symbol 不存在：\(name)"
            )
        }
    }
}
