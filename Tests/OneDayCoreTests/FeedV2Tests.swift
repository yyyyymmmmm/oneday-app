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

    // MARK: - 简报两层文档

    func testBriefDocDecodesFullShape() throws {
        let json = #"""
        {"brief": "正式简报正文", "interest": "我想看开源",
         "briefUpdatedAt": 111, "interestUpdatedAt": 100,
         "expanding": true, "expandError": null,
         "expandStarted": true}
        """#
        let doc = try JSONDecoder().decode(
            BridgeBriefDoc.self, from: Data(json.utf8)
        )
        XCTAssertEqual(doc.brief, "正式简报正文")
        XCTAssertEqual(doc.interest, "我想看开源")
        XCTAssertTrue(doc.expanding)
        XCTAssertEqual(doc.expandStarted, true)
        XCTAssertNil(doc.expandError)
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
    }

    func testBriefSaveRequestEncodesOnlySetLayer() throws {
        let interestOnly = try JSONEncoder().encode(
            BridgeBriefSaveRequest(interest: "兴趣")
        )
        let interestObj = try JSONSerialization.jsonObject(
            with: interestOnly
        ) as? [String: Any]
        XCTAssertEqual(interestObj?["interest"] as? String, "兴趣")
        XCTAssertNil(interestObj?["brief"])

        let briefOnly = try JSONEncoder().encode(
            BridgeBriefSaveRequest(brief: "执行层")
        )
        let briefObj = try JSONSerialization.jsonObject(
            with: briefOnly
        ) as? [String: Any]
        XCTAssertEqual(briefObj?["brief"] as? String, "执行层")
        XCTAssertNil(briefObj?["interest"])
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

    func testExampleInterestCoversThreeDirections() {
        let example = FeedBriefBoard.exampleInterest
        XCTAssertTrue(example.contains("GitHub"))
        XCTAssertTrue(example.contains("AI"))
        XCTAssertTrue(example.contains("副业"))
        XCTAssertTrue(example.contains("中文"))
        XCTAssertTrue(example.contains("割韭菜"))
    }
}
