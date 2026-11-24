import OneDayCore
import XCTest

/// 动态换代（0.38.0）：调研帖新字段宽容解码、来源嵌
/// 入卡、简报两层文档与呈现口径、段二账面 research
/// 键——全是进页前的纯计算与契约钉测。
final class FeedV2Tests: XCTestCase {
    // MARK: - 调研帖解码

    func testResearchPostDecodesNewFields() throws {
        let json = #"""
        {"id": "f_r1", "kind": "research", "title": "真调研",
         "body": "正文", "refs": [],
         "links": [{"title": "甲文", "url": "https://example.com/a"}],
         "why": "因为值得",
         "images": [{"url": "https://img.example.com/a.png",
                     "sourceUrl": "https://example.com/a"}],
         "sourceCard": {"kind": "github", "name": "octo/hello",
                        "description": "打招呼仓库",
                        "url": "https://github.com/octo/hello",
                        "imageUrl": "https://avatars.example/o.png",
                        "facts": [{"label": "星标", "value": "12.3k"}]},
         "direction": "开源项目",
         "createdAt": 100, "expiresAt": 200, "readAt": null}
        """#
        let post = try JSONDecoder().decode(
            BridgeFeedPost.self, from: Data(json.utf8)
        )
        XCTAssertEqual(post.kind, .research)
        XCTAssertEqual(post.kind.label, "调研")
        XCTAssertEqual(post.kind.symbolName, "magnifyingglass")
        XCTAssertEqual(post.images.count, 1)
        XCTAssertEqual(post.images.first?.sourceUrl,
                       "https://example.com/a")
        XCTAssertEqual(post.sourceCard?.name, "octo/hello")
        XCTAssertEqual(post.sourceCard?.facts.first?.value, "12.3k")
        XCTAssertEqual(post.direction, "开源项目")
    }

    func testOldPostDecodesWithEmptyNewFields() throws {
        let json = #"""
        {"id": "f_old", "kind": "morning", "title": "旧晨报",
         "body": "正文", "createdAt": 100}
        """#
        let post = try JSONDecoder().decode(
            BridgeFeedPost.self, from: Data(json.utf8)
        )
        XCTAssertEqual(post.kind, .morning)
        XCTAssertTrue(post.images.isEmpty)
        XCTAssertNil(post.sourceCard)
        XCTAssertNil(post.direction)
    }

    func testMarkedReadKeepsNewFields() {
        let card = BridgeFeedSourceCard(
            kind: "github", name: "octo/hello", description: "d",
            url: "https://github.com/octo/hello"
        )
        let post = BridgeFeedPost(
            id: "f_r2", kind: .research, title: "t", body: "b",
            images: [BridgeFeedImage(
                url: "https://img.example.com/a.png",
                sourceUrl: "https://example.com/a"
            )],
            sourceCard: card, direction: "开源项目",
            createdAt: 100
        )
        let read = post.markedRead(at: 150)
        XCTAssertTrue(read.isRead)
        XCTAssertEqual(read.images, post.images)
        XCTAssertEqual(read.sourceCard, card)
        XCTAssertEqual(read.direction, "开源项目")
    }

    // MARK: - 段二账面 research 键

    func testGenerationDecodesResearchKey() throws {
        let json = #"""
        {"assembly": null,
         "morning": {"lastRunAt": 10, "nextRunAt": 20,
                     "running": false, "history": []},
         "research": {"lastRunAt": 10, "nextRunAt": 20,
                      "running": true, "history": []},
         "unread": 3}
        """#
        let gen = try JSONDecoder().decode(
            BridgeFeedGeneration.self, from: Data(json.utf8)
        )
        XCTAssertEqual(gen.unread, 3)
        XCTAssertEqual(gen.segmentTwo?.running, true)
        XCTAssertEqual(gen.segmentTwo?.lastRunAt, 10)
    }

    func testGenerationFallsBackToMorningKey() throws {
        let json = #"""
        {"morning": {"lastRunAt": 7, "nextRunAt": null,
                     "running": false, "history": []},
         "unread": 0}
        """#
        let gen = try JSONDecoder().decode(
            BridgeFeedGeneration.self, from: Data(json.utf8)
        )
        XCTAssertNil(gen.research)
        XCTAssertEqual(gen.segmentTwo?.lastRunAt, 7)
    }

    // MARK: - 简报文档（§459 单层）

    func testBriefDocDecodesFullShape() throws {
        let json = #"""
        {"brief": "正式简报正文", "interest": "我想看开源",
         "briefUpdatedAt": 111, "interestUpdatedAt": 100,
         "expanding": true, "expandError": null,
         "expandStarted": true,
         "text": "我想看开源", "polished": false,
         "polishState": "pending"}
        """#
        let doc = try JSONDecoder().decode(
            BridgeBriefDoc.self, from: Data(json.utf8)
        )
        XCTAssertEqual(doc.brief, "正式简报正文")
        XCTAssertEqual(doc.interest, "我想看开源")
        XCTAssertTrue(doc.expanding)
        XCTAssertEqual(doc.expandStarted, true)
        XCTAssertNil(doc.expandError)
        XCTAssertEqual(doc.text, "我想看开源")
        XCTAssertFalse(doc.polished)
        XCTAssertEqual(doc.polishState, .pending)
    }

    func testBriefDocToleratesOldShape() throws {
        let json = #"{"brief": "只有执行层"}"#
        let doc = try JSONDecoder().decode(
            BridgeBriefDoc.self, from: Data(json.utf8)
        )
        XCTAssertEqual(doc.brief, "只有执行层")
        XCTAssertEqual(doc.interest, "")
        XCTAssertFalse(doc.expanding)
        XCTAssertNil(doc.expandStarted)
        // §459 新字段缺失时宽容缺省：text 空、未润色、
        // 状态 idle——不许缺省冒充已润色
        XCTAssertEqual(doc.text, "")
        XCTAssertFalse(doc.polished)
        XCTAssertEqual(doc.polishState, .idle)
    }

    func testBriefSaveRequestEncodesOnlySetLayer() throws {
        // §459 单层保存：只发 {text}，两层字段不混发
        let textOnly = try JSONEncoder().encode(
            BridgeBriefSaveRequest(text: "生效全文")
        )
        let textObj = try JSONSerialization.jsonObject(
            with: textOnly
        ) as? [String: Any]
        XCTAssertEqual(textObj?["text"] as? String, "生效全文")
        XCTAssertNil(textObj?["interest"])
        XCTAssertNil(textObj?["brief"])

        let interestOnly = try JSONEncoder().encode(
            BridgeBriefSaveRequest(interest: "兴趣")
        )
        let interestObj = try JSONSerialization.jsonObject(
            with: interestOnly
        ) as? [String: Any]
        XCTAssertEqual(interestObj?["interest"] as? String, "兴趣")
        XCTAssertNil(interestObj?["brief"])
        XCTAssertNil(interestObj?["text"])

        let briefOnly = try JSONEncoder().encode(
            BridgeBriefSaveRequest(brief: "执行层")
        )
        let briefObj = try JSONSerialization.jsonObject(
            with: briefOnly
        ) as? [String: Any]
        XCTAssertEqual(briefObj?["brief"] as? String, "执行层")
        XCTAssertNil(briefObj?["interest"])
        XCTAssertNil(briefObj?["text"])
    }

    // MARK: - §459 单层呈现口径

    func testEffectiveTextPrefersServerText() {
        let doc = BridgeBriefDoc(
            brief: "执行层", interest: "兴趣层",
            text: "生效全文", polished: true,
            polishStateRaw: "done"
        )
        XCTAssertEqual(FeedBriefBoard.effectiveText(doc), "生效全文")
    }

    func testEffectiveTextFallsBackForOldBridge() {
        // 旧桥无 text：兴趣层优先、其次执行层
        let interestDoc = BridgeBriefDoc(
            brief: "执行层", interest: "兴趣层"
        )
        XCTAssertEqual(
            FeedBriefBoard.effectiveText(interestDoc), "兴趣层"
        )
        let briefDoc = BridgeBriefDoc(brief: "执行层", interest: "")
        XCTAssertEqual(
            FeedBriefBoard.effectiveText(briefDoc), "执行层"
        )
    }

    func testPolishHintIsTruthful() {
        // done 但 text 是原文（polished=false）：不许
        // 冒充已润色，不出提示
        let doneOriginal = BridgeBriefDoc(
            brief: "", interest: "", text: "原文",
            polished: false, polishStateRaw: "done"
        )
        XCTAssertNil(FeedBriefBoard.polishHint(doneOriginal))
        // done 且润色稿生效：如实说明
        let donePolished = BridgeBriefDoc(
            brief: "", interest: "", text: "润色稿",
            polished: true, polishStateRaw: "done"
        )
        XCTAssertNotNil(FeedBriefBoard.polishHint(donePolished))
        // pending / error 恒如实出
        let pending = BridgeBriefDoc(
            brief: "", interest: "", polishStateRaw: "pending"
        )
        XCTAssertNotNil(FeedBriefBoard.polishHint(pending))
        let error = BridgeBriefDoc(
            brief: "", interest: "", polishStateRaw: "error"
        )
        XCTAssertNotNil(FeedBriefBoard.polishHint(error))
        // idle 无事可报
        let idle = BridgeBriefDoc(brief: "", interest: "")
        XCTAssertNil(FeedBriefBoard.polishHint(idle))
        // 未知状态值折 idle，不猜
        let unknown = BridgeBriefDoc(
            brief: "", interest: "", polishStateRaw: "weird"
        )
        XCTAssertEqual(unknown.polishState, .idle)
        XCTAssertNil(FeedBriefBoard.polishHint(unknown))
    }

    // MARK: - 简报呈现口径

    func testSummaryLinePrefersInterestFirstLine() {
        let doc = BridgeBriefDoc(
            brief: "执行层第一行\n执行层第二行",
            interest: "  我想看开源项目  \n第二行兴趣"
        )
        XCTAssertEqual(
            FeedBriefBoard.summaryLine(doc), "我想看开源项目"
        )
    }

    func testSummaryLineFallsBackToBrief() {
        let doc = BridgeBriefDoc(brief: "执行层首行", interest: "  ")
        XCTAssertEqual(FeedBriefBoard.summaryLine(doc), "执行层首行")
    }

    func testSummaryLineNilWhenBothEmpty() {
        let doc = BridgeBriefDoc(brief: "", interest: "")
        XCTAssertNil(FeedBriefBoard.summaryLine(doc))
        XCTAssertTrue(FeedBriefBoard.isGuideState(doc))
    }

    func testTextChangedTrimsBeforeComparing() {
        XCTAssertFalse(FeedBriefBoard.textChanged("开源 ", " 开源"))
        XCTAssertTrue(FeedBriefBoard.textChanged("开源", "开源项目"))
        XCTAssertTrue(FeedBriefBoard.textChanged("", "有内容"))
    }

    // MARK: - §459 动态新字段（category/usefulness/event）

    func testFeedPostDecodesCategoryAndUsefulness() throws {
        let json = #"""
        {"id": "f1", "kind": "research", "title": "t",
         "body": "b", "createdAt": 10,
         "category": "GitHub 热门", "usefulness": 85.5}
        """#
        let post = try JSONDecoder().decode(
            BridgeFeedPost.self, from: Data(json.utf8)
        )
        XCTAssertEqual(post.category, "GitHub 热门")
        XCTAssertEqual(post.usefulness, 85.5)
        // 本地副本（已读/点赞翻面）不丢新字段
        XCTAssertEqual(post.markedRead(at: 20).category, "GitHub 热门")
        XCTAssertEqual(post.withLikedAt(30).usefulness, 85.5)
    }

    func testFeedPostToleratesMissingParityFields() throws {
        let json = #"""
        {"id": "f2", "kind": "research", "title": "t",
         "body": "b", "createdAt": 10}
        """#
        let post = try JSONDecoder().decode(
            BridgeFeedPost.self, from: Data(json.utf8)
        )
        XCTAssertNil(post.category)
        XCTAssertNil(post.usefulness)
    }

    func testEventPostKindDecodes() throws {
        let json = #"""
        {"id": "f3", "kind": "event", "title": "新点子",
         "body": "b", "createdAt": 10, "category": null,
         "refs": [{"type": "idea", "id": "i1"}]}
        """#
        let post = try JSONDecoder().decode(
            BridgeFeedPost.self, from: Data(json.utf8)
        )
        XCTAssertEqual(post.kind, .event)
        XCTAssertEqual(post.kind.label, "本地动态")
        XCTAssertNil(post.category)
        XCTAssertEqual(post.refs.first?.refType, .idea)
    }

}
