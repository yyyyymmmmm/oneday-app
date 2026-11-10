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

    // 0.36.19（P-12）：引用注入全文化——旧 1000 字截
    // 断＋「…（以下省略）」编辑标记退役，打包给模型的
    // 用户内容不许静默截断、更不许拼编辑标记
    func testInjectionKeepsLongQuoteVerbatim() {
        let tail = "尾巴标记"
        let long = String(repeating: "a", count: 5000) + tail
        let quote = MessageQuote(role: "assistant", content: long)
        XCTAssertEqual(quote.injectionText, long)
        let composed = MessageQuote.outgoingContent(
            userText: "问", quote: quote
        )
        XCTAssertTrue(composed.hasPrefix("[引用 Hermes 的消息]\n"))
        // 全文逐字在场、尾段可达，出站末尾是用户正文
        XCTAssertTrue(composed.contains(long))
        XCTAssertTrue(composed.hasSuffix(tail + "\n\n问"))
        XCTAssertFalse(composed.contains("以下省略"))
    }

    func testInjectionBoundaryLengthsVerbatim() {
        // 旧上限 1000 及其两侧、与病理级长文一律全文往返
        for count in [999, 1000, 1001, 20000] {
            let content = String(repeating: "字", count: count)
            let quote = MessageQuote(role: "user", content: content)
            XCTAssertEqual(quote.injectionText, content)
        }
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
