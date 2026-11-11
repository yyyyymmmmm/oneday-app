import OneDayCore
import XCTest

/// §117 对标包（0.47.0）呈现口径钉测：点子 emoji 解
/// 析（桥值优先、§177 改判后缺失统一 💡 兜底）、
/// deliverables 容缺解码与小节呈现判定、动态帖
/// emoji 容缺解码与行内全文呈现判定。旧载荷（无新
/// 字段）一律不炸。
final class MuseAlign117Tests: XCTestCase {

    // MARK: - 点子 emoji

    func testIdeaEmojiBridgeValueWins() {
        XCTAssertEqual(
            IdeaEmoji.resolve(emoji: "💍"),
            "💍"
        )
        // 桥值带空白先裁再用
        XCTAssertEqual(
            IdeaEmoji.resolve(emoji: " 📄 "),
            "📄"
        )
    }

    /// §177 改判：兜底不再按锚点来源分档（旧
    /// testIdeaEmojiFallsBackByAnchorKind 与
    /// testIdeaEmojiManualAndUnknown 断言的 💬/🎯/
    /// 📡/✅/🧠/✏️ 分档口径随用户 2026-11-12 亲定
    /// 退役）——缺失形态只有一种结果 💡
    func testIdeaEmojiFallbackIsUnified() {
        XCTAssertEqual(IdeaEmoji.resolve(emoji: nil), "💡")
        XCTAssertEqual(IdeaEmoji.resolve(emoji: ""), "💡")
        XCTAssertEqual(IdeaEmoji.resolve(emoji: "   "), "💡")
        XCTAssertEqual(IdeaEmoji.fallback, "💡")
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
        // 0.48.0（§122）口径改判：§117 的「行内恒全文」
        // 只对短帖成立，长帖改句界截断——本断言随之更
        // 正（截断细则钉测在 ThreePages122Tests）
        let longBody = String(repeating: "正文一段。", count: 500)
        let post = BridgeFeedPost(
            id: "f_9", kind: .research, title: "t",
            body: longBody, createdAt: 100
        )
        XCTAssertFalse(FeedBoard.rowShowsFullBody(post))
        let shortPost = BridgeFeedPost(
            id: "f_10", kind: .research, title: "t",
            body: "两三句正文。", createdAt: 100
        )
        XCTAssertTrue(FeedBoard.rowShowsFullBody(shortPost))
    }
}
