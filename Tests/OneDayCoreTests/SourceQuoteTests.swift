import XCTest
@testable import OneDayCore

/// §209 点子/文件「重发同型后门」收口的 Core 钉测：
/// IdeaQuote/FileQuote 组装与注入拼装（块在前、亲
/// 笔在后、全文不截断）、SourceQuote 分发收口（来
/// 源引用优先于消息引用）、IdeaChatPrefill 重构后
/// 的逐字稳定性、点子存量清扫的逐字判定（改一字
/// 不算机器预填）。呈现与交接在 App 层，判定全钉
/// 在纯函数层（与 §208 FeedDiscussQuoteTests 同式）
final class SourceQuoteTests: XCTestCase {

    private let zh = Locale(identifier: "zh-Hans")
    private let en = Locale(identifier: "en")

    private func idea(
        id: String = "i_1", title: String = "双11 AI 会员购买清单",
        detail: String = "给双十一列一份购买清单。",
        source: IdeaSource = .generated,
        evidence: String = "对话里你说过想趁双十一把会员开齐",
        emoji: String? = "🛒",
        deliverables: [BridgeIdeaDeliverable] = []
    ) -> BridgeIdea {
        BridgeIdea(
            id: id, title: title, detail: detail,
            goalId: nil, createdAt: 100,
            source: source, evidence: evidence,
            emoji: emoji, deliverables: deliverables
        )
    }

    // MARK: - IdeaQuote 组装

    func testIdeaQuoteCarriesSnapshotFields() {
        let quote = IdeaQuote(idea: idea(), locale: zh)
        XCTAssertEqual(quote.ideaID, "i_1")
        XCTAssertEqual(quote.title, "双11 AI 会员购买清单")
        XCTAssertEqual(quote.mark, "🛒")
        // 载荷＝题头之外的全部段：说明＋依据（生成卡）
        XCTAssertEqual(
            quote.body,
            "给双十一列一份购买清单。\n\n"
                + "依据：对话里你说过想趁双十一把会员开齐"
        )
    }

    func testIdeaQuoteBodyIncludesDeliverables() {
        let quote = IdeaQuote(
            idea: idea(deliverables: [
                BridgeIdeaDeliverable(
                    name: "购买清单表格", summary: "列清要买的会员"
                ),
                BridgeIdeaDeliverable(name: "时间节点提醒"),
            ]),
            locale: zh
        )
        XCTAssertTrue(
            quote.body.hasSuffix(
                "包含的内容：\n· 购买清单表格：列清要买的会员\n· 时间节点提醒"
            )
        )
    }

    func testIdeaQuoteMarkFallsBackWhenEmojiMissing() {
        let quote = IdeaQuote(idea: idea(emoji: nil), locale: zh)
        XCTAssertEqual(quote.mark, IdeaEmoji.fallback)
    }

    func testIdeaQuoteManualIdeaSkipsEvidence() {
        // 手记卡即使带 evidence 也不进载荷（与详情页
        // 依据小节只对生成卡出现的口径一致）
        let quote = IdeaQuote(
            idea: idea(source: .manual), locale: zh
        )
        XCTAssertFalse(quote.body.contains("依据："))
    }

    func testIdeaQuoteEmptyBodyForBareIdea() {
        let quote = IdeaQuote(
            idea: idea(detail: "", source: .manual, evidence: ""),
            locale: zh
        )
        XCTAssertEqual(quote.body, "")
    }

    // MARK: - IdeaQuote 注入拼装

    func testIdeaOutgoingPutsBlockBeforeUserText() {
        let quote = IdeaQuote(idea: idea(), locale: zh)
        let out = IdeaQuote.outgoingContent(
            userText: "先聊聊预算", ideaQuote: quote
        )
        XCTAssertEqual(
            out,
            "[引用点子：《双11 AI 会员购买清单》]\n"
                + "给双十一列一份购买清单。\n\n"
                + "依据：对话里你说过想趁双十一把会员开齐"
                + "\n\n先聊聊预算"
        )
    }

    func testIdeaOutgoingHasNoFirstPersonHeadline() {
        // 旧预填的题头句是系统代笔的第一人称口吻
        // （「我们来聊聊这个点子」）——引用块只作标
        // 识，拼装里不许再出现它
        let quote = IdeaQuote(idea: idea(), locale: zh)
        let out = IdeaQuote.outgoingContent(
            userText: "", ideaQuote: quote
        )
        XCTAssertFalse(out.contains("我们来聊聊"))
    }

    func testIdeaOutgoingWithoutUserTextIsBlockOnly() {
        let quote = IdeaQuote(idea: idea(), locale: zh)
        let out = IdeaQuote.outgoingContent(
            userText: "", ideaQuote: quote
        )
        XCTAssertTrue(out.hasPrefix("[引用点子：《双11 AI 会员购买清单》]"))
        XCTAssertFalse(out.hasSuffix("\n\n"))
    }

    func testIdeaOutgoingBareIdeaIsHeaderOnly() {
        let quote = IdeaQuote(
            idea: idea(detail: "", source: .manual, evidence: ""),
            locale: zh
        )
        let out = IdeaQuote.outgoingContent(
            userText: "就它了", ideaQuote: quote
        )
        XCTAssertEqual(
            out, "[引用点子：《双11 AI 会员购买清单》]\n\n就它了"
        )
    }

    func testIdeaOutgoingNilQuoteReturnsUserText() {
        XCTAssertEqual(
            IdeaQuote.outgoingContent(
                userText: "亲笔", ideaQuote: nil
            ),
            "亲笔"
        )
    }

    // MARK: - FileQuote 组装与拼装

    func testFileQuoteFromTargetRoundTrips() {
        let target = FileOpenTarget(
            name: "报告.pdf", path: "/opt/data/files/报告.pdf"
        )
        let quote = FileQuote(target: target)
        XCTAssertEqual(quote.name, "报告.pdf")
        XCTAssertEqual(quote.path, "/opt/data/files/报告.pdf")
        XCTAssertEqual(quote.target, target)
    }

    func testFileOutgoingCarriesFullResendText() {
        let quote = FileQuote(
            name: "报告.pdf", path: "/opt/data/files/报告.pdf"
        )
        let out = FileQuote.outgoingContent(
            userText: "", fileQuote: quote
        )
        // 块头＋重发话术全文：三要点逐字承接（名／
        // 原路径以「它原来的路径是：<路径>」形态呈现／
        // 要求对方确认存在后把正确路径单独写一行回复——
        // 「单独成行」约束的是智能体的回复，不是预填呈现）
        XCTAssertEqual(
            out,
            "[引用文件：《报告.pdf》]\n"
                + FileResendPrefill.make(
                    name: "报告.pdf",
                    path: "/opt/data/files/报告.pdf"
                )
        )
        XCTAssertTrue(
            out.contains("它原来的路径是：/opt/data/files/报告.pdf")
        )
    }

    func testFileOutgoingAppendsUserTextAfterBlock() {
        let quote = FileQuote(name: "a.txt", path: "/x/a.txt")
        let out = FileQuote.outgoingContent(
            userText: "麻烦了", fileQuote: quote
        )
        XCTAssertTrue(out.hasSuffix("\n\n麻烦了"))
        XCTAssertTrue(out.hasPrefix("[引用文件：《a.txt》]"))
    }

    func testFileOutgoingNilQuoteReturnsUserText() {
        XCTAssertEqual(
            FileQuote.outgoingContent(
                userText: "亲笔", fileQuote: nil
            ),
            "亲笔"
        )
    }

    // MARK: - SourceQuote 分发

    func testDispatchSourceQuoteRoutesByCase() {
        let ideaQuote = IdeaQuote(idea: idea(), locale: zh)
        let fileQuote = FileQuote(name: "a.txt", path: "/x/a.txt")
        let feedQuote = FeedPostQuote(
            postID: "fp_1", title: "帖题", body: "帖文",
            sourceLine: ""
        )
        XCTAssertEqual(
            SourceQuote.idea(ideaQuote).outgoingContent(
                userText: "问"
            ),
            IdeaQuote.outgoingContent(
                userText: "问", ideaQuote: ideaQuote
            )
        )
        XCTAssertEqual(
            SourceQuote.file(fileQuote).outgoingContent(
                userText: "问"
            ),
            FileQuote.outgoingContent(
                userText: "问", fileQuote: fileQuote
            )
        )
        XCTAssertEqual(
            SourceQuote.feed(feedQuote).outgoingContent(
                userText: "问"
            ),
            FeedPostQuote.outgoingContent(
                userText: "问", feedQuote: feedQuote
            )
        )
    }

    func testDispatchPrefersSourceQuoteOverMessageQuote() {
        // 一条消息至多一种引用：来源引用在场时分发
        // 优先它，消息引用不叠加（槽位单一在场的拼
        // 装面保证）
        let messageQuote = MessageQuote(
            role: "assistant", content: "被引消息"
        )
        let out = MessageQuote.outgoingContent(
            userText: "正文",
            quote: messageQuote,
            sourceQuote: .file(
                FileQuote(name: "a.txt", path: "/x/a.txt")
            )
        )
        XCTAssertTrue(out.hasPrefix("[引用文件：《a.txt》]"))
        XCTAssertFalse(out.contains("被引消息"))
    }

    func testDispatchFallsBackToMessageQuote() {
        // 无来源引用时回落消息引用：与旧二参变体逐
        // 字一致（拼装细节——称呼/全文/分隔——以
        // §208 与 MessageQuote 既有钉测为准，本条
        // 只钉回落路径本身）
        let messageQuote = MessageQuote(
            role: "assistant", content: "被引消息"
        )
        let out = MessageQuote.outgoingContent(
            userText: "正文问", quote: messageQuote,
            sourceQuote: nil
        )
        XCTAssertEqual(
            out,
            MessageQuote.outgoingContent(
                userText: "正文问", quote: messageQuote
            )
        )
        XCTAssertTrue(out.contains("被引消息"))
    }

    func testDispatchNoQuoteReturnsUserText() {
        XCTAssertEqual(
            MessageQuote.outgoingContent(
                userText: "正文", quote: nil, sourceQuote: nil
            ),
            "正文"
        )
    }

    // MARK: - IdeaChatPrefill 重构逐字稳定性

    func testPrefillMakeEqualsHeadlinePlusContextBody() {
        // 本包把 make 的后段抽成 IdeaChatContext.body
        // 供 IdeaQuote 共用——make 的输出必须逐字不
        // 变（存量清扫拿它当参照，漂移即误判）
        let target = idea(deliverables: [
            BridgeIdeaDeliverable(
                name: "购买清单表格", summary: "列清要买的会员"
            ),
        ])
        let make = IdeaChatPrefill.make(idea: target, locale: zh)
        let body = IdeaChatContext.body(idea: target, locale: zh)
        XCTAssertEqual(
            make,
            "我们来聊聊这个点子：《双11 AI 会员购买清单》"
                + "\n\n" + body
        )
        let bare = IdeaChatPrefill.make(
            idea: idea(detail: "", source: .manual, evidence: ""),
            locale: zh
        )
        XCTAssertEqual(bare, "我们来聊聊这个点子：《双11 AI 会员购买清单》")
    }

    // MARK: - 点子存量清扫判定

    func testIdeaCleanupMatchesVerbatimMachineOutput() {
        let target = idea()
        let text = IdeaChatPrefill.make(idea: target, locale: zh)
        XCTAssertTrue(
            IdeaPrefillDraftCleanup.isMachinePrefill(
                text, idea: target
            )
        )
    }

    func testIdeaCleanupMatchesEnglishMachineOutput() {
        // 预填按当时界面语言生成：英文界面的存量须
        // 以英文候选再生才认得出（三语候选的意义）
        let target = idea()
        let text = IdeaChatPrefill.make(idea: target, locale: en)
        XCTAssertTrue(
            IdeaPrefillDraftCleanup.isMachinePrefill(
                text, idea: target
            )
        )
    }

    func testIdeaCleanupRejectsSingleCharacterEdit() {
        let target = idea()
        var text = IdeaChatPrefill.make(idea: target, locale: zh)
        text += "！"
        XCTAssertFalse(
            IdeaPrefillDraftCleanup.isMachinePrefill(
                text, idea: target
            )
        )
    }

    func testIdeaCleanupRejectsWrongIdea() {
        let text = IdeaChatPrefill.make(idea: idea(), locale: zh)
        XCTAssertFalse(
            IdeaPrefillDraftCleanup.isMachinePrefill(
                text, idea: idea(id: "i_2", title: "另一个点子")
            )
        )
    }

    func testIdeaCleanupRejectsPlainUserDraft() {
        XCTAssertFalse(
            IdeaPrefillDraftCleanup.isMachinePrefill(
                "我自己写的草稿", idea: idea()
            )
        )
    }
}
