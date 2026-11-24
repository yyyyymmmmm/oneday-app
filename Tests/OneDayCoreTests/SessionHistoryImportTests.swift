import XCTest
@testable import OneDayCore

/// 0.4.0（审计 §3.4）：服务端会话历史导入口径——只取
/// user/assistant 有正文者、保原序；工具/系统消息与
/// 空正文不进本地线程（不渲染、不进上下文重放）。
final class SessionHistoryImportTests: XCTestCase {
    private func messages(_ json: String) throws -> [SessionMessage] {
        let data = Data(json.utf8)
        return try JSONDecoder()
            .decode(SessionMessagesResponse.self, from: data)
            .messages
    }

    func testKeepsOnlyUserAssistantWithContentInOrder() throws {
        let loaded = try messages("""
        {"messages": [
          {"id": 1, "role": "user", "content": "你好", "timestamp": 1762000000},
          {"id": 2, "role": "tool", "content": "{\\"a\\":1}", "timestamp": 1762000001},
          {"id": 3, "role": "assistant", "content": "在的", "timestamp": 1762000002},
          {"id": 4, "role": "system", "content": "sys", "timestamp": 1762000003},
          {"id": 5, "role": "assistant", "content": "  ", "timestamp": 1762000004},
          {"id": 6, "role": "user", "content": "", "timestamp": 1762000005},
          {"id": 7, "role": "assistant", "content": "继续", "timestamp": 1762000006}
        ]}
        """)
        let entries = SessionHistoryImport.importableEntries(from: loaded)
        XCTAssertEqual(entries.map(\.role), ["user", "assistant", "assistant"])
        XCTAssertEqual(entries.map(\.content), ["你好", "在的", "继续"])
        XCTAssertEqual(
            entries.first?.date,
            Date(timeIntervalSince1970: 1762000000)
        )
    }

    /// 0.46.1（§116）：user 消息的网关展开块在导入时
    /// 还原——content 只剩干净正文、附件路径进
    /// fileRefs，英文脚手架不进线程
    func testRichItemsNormalizesAttachedContextBlock() {
        let expanded = """
        你可以看到这是什么吗
        @file:/opt/data/attachments/三藏.zip

        --- Attached Context ---

        📎 @file:/opt/data/attachments/三藏.zip (application/zip, 660.6 KB) — binary file, not inlined as text. It is available on disk at `/opt/data/attachments/三藏.zip`. Use your tools to work with it (read or convert it, extract its text, or view/render it as needed); do not tell the user the file type is unsupported.
        """
        let items = SessionHistoryImport.richItems(from: [
            SessionMessage(
                id: 947, role: "user", content: expanded,
                timestamp: 1762000000, displayKind: nil
            ),
            SessionMessage(
                id: 948, role: "assistant",
                content: "这是一个压缩包。",
                timestamp: 1762000001, displayKind: nil
            ),
        ])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].role, "user")
        XCTAssertEqual(items[0].content, "你可以看到这是什么吗")
        XCTAssertEqual(
            items[0].fileRefs, ["/opt/data/attachments/三藏.zip"]
        )
        XCTAssertTrue(items[0].imagePaths.isEmpty)
        XCTAssertFalse(items[0].content.contains("Attached"))
        // assistant 不走规范化、正文原样、fileRefs 恒空
        XCTAssertEqual(items[1].content, "这是一个压缩包。")
        XCTAssertTrue(items[1].fileRefs.isEmpty)
    }

    func testEmptyWhenNothingImportable() throws {
        let loaded = try messages("""
        {"messages": [
          {"id": 1, "role": "tool", "content": "{}", "timestamp": 1762000000}
        ]}
        """)
        XCTAssertTrue(
            SessionHistoryImport.importableEntries(from: loaded).isEmpty
        )
    }

    func testThreadTitleFallsBackWithoutSession() {
        let entries = [
            SessionHistoryImport.Entry(
                role: "user", content: "帮我看看明天的安排", date: nil
            ),
        ]
        XCTAssertEqual(
            SessionHistoryImport.threadTitle(session: nil, entries: entries),
            "帮我看看明天的安排"
        )
        XCTAssertEqual(
            SessionHistoryImport.threadTitle(session: nil, entries: []),
            "未命名会话"
        )
    }

    // MARK: - 收敛包：引用块拆解（P3-1）

    /// 引用块随回流进来要在规范化里拆回槽位：正文只
    /// 剩亲笔正文、引用进 quote，不再直显原文
    func testNormalizedUserContentSplitsQuoteBlock() {
        let wire = MessageQuote.outgoingContent(
            userText: "就这条展开",
            quote: MessageQuote(role: "assistant", content: "旧回复")
        )
        let normalized = SessionHistoryImport
            .normalizedUserContent(wire)
        XCTAssertEqual(normalized.text, "就这条展开")
        XCTAssertEqual(
            normalized.quote,
            MessageQuote(role: "assistant", content: "旧回复")
        )
    }

    func testNormalizedUserContentSplitsUserQuoteBlock() {
        let wire = "[引用 我 的消息]\n我之前说的\n\n对，就是这个"
        let normalized = SessionHistoryImport
            .normalizedUserContent(wire)
        XCTAssertEqual(normalized.text, "对，就是这个")
        XCTAssertEqual(normalized.quote?.role, "user")
        XCTAssertEqual(normalized.quote?.content, "我之前说的")
    }

    /// 纯引用块（正文为空的发送）拆得正文为空、引用在位
    func testNormalizedUserContentQuoteOnlyBlock() {
        let wire = MessageQuote.outgoingContent(
            userText: "",
            quote: MessageQuote(role: "user", content: "只有引用")
        )
        let normalized = SessionHistoryImport
            .normalizedUserContent(wire)
        XCTAssertEqual(normalized.text, "")
        XCTAssertEqual(normalized.quote?.content, "只有引用")
    }

    /// 同族块头不误拆：动态引用块头不以「 的消息]」收尾
    func testNormalizedUserContentLeavesFeedQuoteBlockAlone() {
        let wire = "[引用动态：《某帖》]\n帖子正文\n\n我的看法"
        let normalized = SessionHistoryImport
            .normalizedUserContent(wire)
        XCTAssertNil(normalized.quote)
        XCTAssertEqual(normalized.text, wire)
    }

    /// 无引用正文原样、quote 恒 nil（旧口径不回退）
    func testNormalizedUserContentPlainTextUnchanged() {
        let normalized = SessionHistoryImport
            .normalizedUserContent("普通消息")
        XCTAssertEqual(normalized.text, "普通消息")
        XCTAssertNil(normalized.quote)
    }

    /// richItems：带引用 user 消息落项时正文拆净、
    /// quote 在位；纯引用项不被空正文门吞掉
    func testRichItemsCarriesQuoteSlot() {
        let items = SessionHistoryImport.richItems(from: [
            SessionMessage(
                id: 11, role: "assistant", content: "被引用的回答",
                timestamp: 1762000100, displayKind: nil
            ),
            SessionMessage(
                id: 12, role: "user",
                content: "[引用 Hermes 的消息]\n被引用的回答\n\n展开讲讲",
                timestamp: 1762000101, displayKind: nil
            ),
            SessionMessage(
                id: 13, role: "user",
                content: "[引用 我 的消息]\n只有引用",
                timestamp: 1762000102, displayKind: nil
            ),
        ])
        XCTAssertEqual(items.count, 3)
        let quoted = items.first { $0.serverRowID == 12 }
        XCTAssertEqual(quoted?.content, "展开讲讲")
        XCTAssertEqual(quoted?.quote?.role, "assistant")
        XCTAssertEqual(quoted?.quote?.content, "被引用的回答")
        let quoteOnly = items.first { $0.serverRowID == 13 }
        XCTAssertEqual(quoteOnly?.content, "")
        XCTAssertEqual(quoteOnly?.quote?.content, "只有引用")
    }

    /// 校验集切分：被引长文含空行、正文也含空行时，
    /// 据同批已知消息定切点，不靠末界回落猜
    func testParsePrefersKnownQuoteTextSplit() {
        let longAnswer = "第一段\n\n第二段"
        let wire = "[引用 Hermes 的消息]\n\(longAnswer)\n\n正文一段\n\n正文二段"
        let parsed = MessageQuote.parse(
            wireContent: wire, knownQuoteTexts: [longAnswer]
        )
        XCTAssertEqual(parsed?.quote.content, longAnswer)
        XCTAssertEqual(parsed?.body, "正文一段\n\n正文二段")
    }

    /// parse 与 outgoingContent 互逆（无歧义样本）；
    /// 普通正文与同族块头不命中
    func testParseInvertsOutgoingContent() {
        let quote = MessageQuote(role: "assistant", content: "原回答")
        let wire = MessageQuote.outgoingContent(
            userText: "追问", quote: quote
        )
        let parsed = MessageQuote.parse(wireContent: wire)
        XCTAssertEqual(parsed?.quote, quote)
        XCTAssertEqual(parsed?.body, "追问")
        XCTAssertNil(MessageQuote.parse(wireContent: "普通正文"))
        XCTAssertNil(
            MessageQuote.parse(wireContent: "[引用动态：《x》]\n正文")
        )
    }

}
