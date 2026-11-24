import XCTest
@testable import OneDayCore

/// §208 动态讨论引用化的 Core 钉测：FeedPostQuote
/// 组装与来源行优先级、注入拼装（全文不截断、身份
/// 分开）、分发收口、存量清扫的逐字判定（改一字不
/// 算机器预填）。呈现与交接在 App 层，判定全钉在
/// 纯函数层
final class FeedDiscussQuoteTests: XCTestCase {

    private func post(
        id: String = "fp_1", title: String = "标题",
        body: String = "正文内容",
        links: [BridgeFeedLink] = [],
        images: [BridgeFeedImage] = [],
        sourceCard: BridgeFeedSourceCard? = nil,
        direction: String? = nil,
        emoji: String? = "🔥"
    ) -> BridgeFeedPost {
        BridgeFeedPost(
            id: id, kind: .research, title: title, body: body,
            links: links, images: images,
            sourceCard: sourceCard, direction: direction,
            createdAt: 1_700_000_000, emoji: emoji
        )
    }

    // MARK: - 组装与来源行

    func testQuoteFromPostCarriesSnapshotFields() {
        let quote = FeedPostQuote(post: post(
            images: [BridgeFeedImage(
                url: "https://img.example/a.png", sourceUrl: "s"
            )]
        ))
        XCTAssertEqual(quote.postID, "fp_1")
        XCTAssertEqual(quote.title, "标题")
        XCTAssertEqual(quote.body, "正文内容")
        XCTAssertEqual(quote.imageURL, "https://img.example/a.png")
        XCTAssertEqual(quote.mark, "🔥")
    }

    func testQuoteFromPostWithoutImageHasNoThumbnail() {
        let quote = FeedPostQuote(post: post())
        XCTAssertNil(quote.imageURL)
    }

    func testSourceLinePrefersSourceCardName() {
        let card = BridgeFeedSourceCard(
            kind: "github", name: "owner/repo",
            description: "", url: "https://github.com/owner/repo"
        )
        let quote = FeedPostQuote(post: post(
            links: [BridgeFeedLink(
                title: "x", url: "https://example.com/a"
            )],
            sourceCard: card, direction: "搞钱与副业机会"
        ))
        XCTAssertEqual(quote.sourceLine, "owner/repo")
    }

    func testSourceLineFallsBackToDirection() {
        let quote = FeedPostQuote(post: post(
            links: [BridgeFeedLink(
                title: "x", url: "https://example.com/a"
            )],
            direction: "AI 实质进展"
        ))
        XCTAssertEqual(quote.sourceLine, "AI 实质进展")
    }

    func testSourceLineFallsBackToFirstLinkHost() {
        let quote = FeedPostQuote(post: post(
            links: [BridgeFeedLink(
                title: "x", url: "https://sub.example.com/a?b=1"
            )]
        ))
        XCTAssertEqual(quote.sourceLine, "sub.example.com")
    }

    func testSourceLineEmptyWhenNoSource() {
        let quote = FeedPostQuote(post: post())
        XCTAssertEqual(quote.sourceLine, "")
    }

    // MARK: - 注入拼装

    func testOutgoingPutsFullBodyBlockBeforeUserText() {
        // 正文超旧预填 1200 上限：引用注入全文打包、
        // 不节选（P-12 口径）
        let longBody = String(repeating: "这是一个完整的句子。", count: 200)
        let quote = FeedPostQuote(
            postID: "fp_9", title: "长帖", body: longBody,
            sourceLine: "example.com"
        )
        let out = FeedPostQuote.outgoingContent(
            userText: "这篇怎么看", feedQuote: quote
        )
        XCTAssertTrue(out.hasPrefix("[引用动态：《长帖》]\n"))
        XCTAssertTrue(out.contains(longBody))
        XCTAssertTrue(out.contains("\n（来源：example.com）\n\n这篇怎么看"))
        XCTAssertFalse(out.contains("以下为原帖节选"))
    }

    func testOutgoingWithoutUserTextIsBlockOnly() {
        let quote = FeedPostQuote(
            postID: "fp_9", title: "帖", body: "正文",
            sourceLine: ""
        )
        let out = FeedPostQuote.outgoingContent(
            userText: "", feedQuote: quote
        )
        XCTAssertEqual(out, "[引用动态：《帖》]\n正文")
    }

    func testOutgoingOmitsSourceLineWhenEmpty() {
        let quote = FeedPostQuote(
            postID: "fp_9", title: "帖", body: "正文",
            sourceLine: ""
        )
        let out = FeedPostQuote.outgoingContent(
            userText: "问", feedQuote: quote
        )
        XCTAssertFalse(out.contains("来源"))
        XCTAssertEqual(out, "[引用动态：《帖》]\n正文\n\n问")
    }

    func testOutgoingNilQuoteReturnsUserText() {
        XCTAssertEqual(
            FeedPostQuote.outgoingContent(
                userText: "原样", feedQuote: nil
            ),
            "原样"
        )
    }

    // MARK: - 分发收口

    func testDispatchPrefersFeedQuote() {
        let feed = FeedPostQuote(
            postID: "fp_1", title: "帖", body: "正文",
            sourceLine: ""
        )
        let message = MessageQuote(role: "user", content: "被引消息")
        let out = MessageQuote.outgoingContent(
            userText: "正文问", quote: message, feedQuote: feed
        )
        XCTAssertTrue(out.hasPrefix("[引用动态：《帖》]"))
        XCTAssertFalse(out.contains("被引消息"))
    }

    func testDispatchFallsBackToMessageQuote() {
        let message = MessageQuote(role: "user", content: "被引消息")
        let out = MessageQuote.outgoingContent(
            userText: "正文问", quote: message, feedQuote: nil
        )
        XCTAssertEqual(out, "[引用 我 的消息]\n被引消息\n\n正文问")
    }

    func testDispatchNoQuoteReturnsUserText() {
        XCTAssertEqual(
            MessageQuote.outgoingContent(
                userText: "原样", quote: nil, feedQuote: nil
            ),
            "原样"
        )
    }

    // MARK: - 摘要

    func testSummaryCollapsesAndTruncates() {
        let quote = FeedPostQuote(
            postID: "fp_1", title: "帖",
            body: "第一行\n\n第二行  带空格",
            sourceLine: ""
        )
        XCTAssertEqual(quote.summary(), "第一行 第二行 带空格")
        let long = FeedPostQuote(
            postID: "fp_1", title: "帖",
            body: String(repeating: "字", count: 100),
            sourceLine: ""
        )
        XCTAssertEqual(long.summary().count, 61)
        XCTAssertTrue(long.summary().hasSuffix("…"))
    }

    // MARK: - 存量清扫逐字判定（包 3 的 Core 半）

    func testCleanupMatchesVerbatimMachineOutput() {
        let title = "存量帖"
        let body = "正文一共两句。就这样。"
        for locale in FeedDiscussDraftCleanup.candidateLocales {
            let machine = FeedDiscussPrefill.make(
                title: title, body: body, locale: locale
            )
            XCTAssertTrue(
                FeedDiscussDraftCleanup.isMachinePrefill(
                    machine, title: title, body: body
                ),
                "locale \(locale.identifier) 的机器输出应判中"
            )
        }
    }

    func testCleanupMatchesVerbatimExcerptOutput() {
        let title = "长帖"
        let body = String(
            repeating: "这是一个完整的句子。", count: 200
        )
        let machine = FeedDiscussPrefill.make(title: title, body: body)
        XCTAssertTrue(machine.contains("以下为原帖节选"))
        XCTAssertTrue(
            FeedDiscussDraftCleanup.isMachinePrefill(
                machine, title: title, body: body
            )
        )
    }

    func testCleanupRejectsSingleCharacterEdit() {
        let title = "存量帖"
        let body = "正文一共两句。就这样。"
        var edited = FeedDiscussPrefill.make(title: title, body: body)
        edited = edited.replacingOccurrences(
            of: "两句", with: "三句"
        )
        XCTAssertFalse(
            FeedDiscussDraftCleanup.isMachinePrefill(
                edited, title: title, body: body
            )
        )
    }

    func testCleanupRejectsWrongTitleOrBody() {
        let machine = FeedDiscussPrefill.make(
            title: "甲帖", body: "正文"
        )
        XCTAssertFalse(
            FeedDiscussDraftCleanup.isMachinePrefill(
                machine, title: "乙帖", body: "正文"
            )
        )
        XCTAssertFalse(
            FeedDiscussDraftCleanup.isMachinePrefill(
                machine, title: "甲帖", body: "别的正文"
            )
        )
    }

    func testCleanupRejectsPlainUserDraft() {
        XCTAssertFalse(
            FeedDiscussDraftCleanup.isMachinePrefill(
                "我自己写的话，还没写完", title: "存量帖", body: "正文"
            )
        )
    }
}
