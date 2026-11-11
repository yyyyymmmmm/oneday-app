import OneDayCore
import XCTest

/// §117 对标包（0.47.0）呈现口径钉测：点子 emoji 解
/// 析（桥值优先、按锚点 kind 兜底）、deliverables 容
/// 缺解码与小节呈现判定、动态帖 emoji 容缺解码与行
/// 内全文呈现判定。旧载荷（无新字段）一律不炸。
final class MuseAlign117Tests: XCTestCase {

    // MARK: - 点子 emoji

    func testIdeaEmojiBridgeValueWins() {
        XCTAssertEqual(
            IdeaEmoji.resolve(
                emoji: "💍", evidenceRef: "S1",
                anchorId: nil, source: .generated
            ),
            "💍"
        )
        // 桥值带空白先裁再用
        XCTAssertEqual(
            IdeaEmoji.resolve(
                emoji: " 📄 ", evidenceRef: nil,
                anchorId: nil, source: .manual
            ),
            "📄"
        )
    }

    func testIdeaEmojiFallsBackByAnchorKind() {
        XCTAssertEqual(
            IdeaEmoji.resolve(
                emoji: nil, evidenceRef: "S2",
                anchorId: nil, source: .generated
            ),
            "💬"
        )
        XCTAssertEqual(
            IdeaEmoji.resolve(
                emoji: nil, evidenceRef: nil,
                anchorId: "G:g_1", source: .generated
            ),
            "🎯"
        )
        XCTAssertEqual(
            IdeaEmoji.resolve(
                emoji: "", evidenceRef: "M1",
                anchorId: nil, source: .generated
            ),
            "📡"
        )
        XCTAssertEqual(
            IdeaEmoji.resolve(
                emoji: nil, evidenceRef: "K3",
                anchorId: nil, source: .generated
            ),
            "✅"
        )
        XCTAssertEqual(
            IdeaEmoji.resolve(
                emoji: nil, evidenceRef: "R1",
                anchorId: nil, source: .generated
            ),
            "🧠"
        )
        // anchorId 优先于 evidenceRef
        XCTAssertEqual(
            IdeaEmoji.resolve(
                emoji: nil, evidenceRef: "S1",
                anchorId: "K:t_1", source: .generated
            ),
            "✅"
        )
    }

    func testIdeaEmojiManualAndUnknown() {
        XCTAssertEqual(
            IdeaEmoji.resolve(
                emoji: nil, evidenceRef: nil,
                anchorId: nil, source: .manual
            ),
            "✏️"
        )
        XCTAssertEqual(
            IdeaEmoji.resolve(
                emoji: nil, evidenceRef: "X9",
                anchorId: nil, source: .generated
            ),
            "💡"
        )
    }

    // MARK: - 点子新字段解码

    func testIdeaDecodesEmojiAndDeliverables() throws {
        let json = """
        {"id": "i_1", "title": "t", "detail": "d",
         "goalId": null, "createdAt": 100, "source": "generated",
         "evidence": "e", "evidenceRef": "S1",
         "emoji": "💍",
         "deliverables": [{"name": "发言稿文档",
                            "summary": "可直接念"}],
         "status": "pending", "taskId": null,
         "expiresAt": null}
        """
        let idea = try JSONDecoder().decode(
            BridgeIdea.self, from: Data(json.utf8)
        )
        XCTAssertEqual(idea.emoji, "💍")
        XCTAssertEqual(idea.deliverables.count, 1)
        XCTAssertEqual(idea.deliverables.first?.name, "发言稿文档")
        XCTAssertTrue(
            IdeaDeliverablesSection.isVisible(idea.deliverables)
        )
    }

    func testIdeaOldPayloadDecodesWithoutNewFields() throws {
        let json = """
        {"id": "i_0", "title": "t", "detail": "d",
         "goalId": null, "createdAt": 100, "source": "manual",
         "status": "pending"}
        """
        let idea = try JSONDecoder().decode(
            BridgeIdea.self, from: Data(json.utf8)
        )
        XCTAssertNil(idea.emoji)
        XCTAssertEqual(idea.deliverables, [])
        XCTAssertFalse(
            IdeaDeliverablesSection.isVisible(idea.deliverables)
        )
        // 只有无名条目时小节同样不出现
        XCTAssertFalse(
            IdeaDeliverablesSection.isVisible(
                [BridgeIdeaDeliverable(name: "", summary: "x")]
            )
        )
    }

    // MARK: - 动态帖 emoji 与全文呈现

    func testFeedPostEmojiDecodeAndFallback() throws {
        let withEmoji = """
        {"id": "f_1", "kind": "research", "title": "t",
         "body": "b", "refs": [], "links": [],
         "createdAt": 100, "emoji": "🏠"}
        """
        let post = try JSONDecoder().decode(
            BridgeFeedPost.self, from: Data(withEmoji.utf8)
        )
        XCTAssertEqual(post.displayEmoji, "🏠")
        XCTAssertEqual(post.markedRead(at: 200).displayEmoji, "🏠")

        let old = """
        {"id": "f_0", "kind": "research", "title": "t",
         "body": "b", "refs": [], "links": [],
         "createdAt": 100}
        """
        let oldPost = try JSONDecoder().decode(
            BridgeFeedPost.self, from: Data(old.utf8)
        )
        XCTAssertNil(oldPost.emoji)
        XCTAssertEqual(oldPost.displayEmoji, "🔍")

        let digest = BridgeFeedPost(
            id: "f_2", kind: .digest, title: "t", body: "b",
            createdAt: 100
        )
        XCTAssertEqual(digest.displayEmoji, "📰")
        let morning = BridgeFeedPost(
            id: "f_3", kind: .morning, title: "t", body: "b",
            createdAt: 100
        )
        XCTAssertEqual(morning.displayEmoji, "🌅")
    }

    func testFeedRowShowsFullBodyRegardlessOfLength() {
        let longBody = String(repeating: "正文一段。", count: 500)
        let post = BridgeFeedPost(
            id: "f_9", kind: .research, title: "t",
            body: longBody, createdAt: 100
        )
        XCTAssertTrue(FeedBoard.rowShowsFullBody(post))
    }
}
