import OneDayCore
import XCTest
@testable import OneDayApp

/// §202 动态讨论引用化的 App 层钉测：讨论去重的
/// 关联反查（SideChatStore）、存量预填清扫（包 3）
/// ——判定逻辑在 Core 纯函数层（FeedDiscussQuote-
/// Tests 已钉），本组钉存储层的落点与零误伤
final class FeedDiscussQuoteAppTests: XCTestCase {

    // MARK: - 讨论去重反查（包 2）

    func testThreadLookupByDiscussPostID() {
        let store = SideChatStore(persisted: false)
        let thread = UUID()
        XCTAssertNil(store.threadID(forFeedDiscussPostID: "fp_1"))
        store.linkFeedDiscussThread(thread, postID: "fp_1")
        XCTAssertEqual(
            store.threadID(forFeedDiscussPostID: "fp_1"), thread
        )
        XCTAssertEqual(
            store.feedDiscussPostID(forThreadID: thread), "fp_1"
        )
        XCTAssertNil(store.threadID(forFeedDiscussPostID: "fp_x"))
    }

    func testRelinkOverwritesStaleThread() {
        // 关联在但线程已删：discuss() 补建后改写关联，
        // 反查须指向新线程（旧线程 id 不许残留命中）
        let store = SideChatStore(persisted: false)
        let old = UUID()
        let fresh = UUID()
        store.linkFeedDiscussThread(old, postID: "fp_1")
        store.linkFeedDiscussThread(fresh, postID: "fp_1")
        XCTAssertEqual(
            store.threadID(forFeedDiscussPostID: "fp_1"), fresh
        )
    }

    // MARK: - 存量预填清扫（包 3）

    private func feedPost(
        id: String, title: String, body: String
    ) -> BridgeFeedPost {
        BridgeFeedPost(
            id: id, kind: .research, title: title, body: body,
            createdAt: 1_700_000_000
        )
    }

    func testPurgeClearsVerbatimMachineDraft() {
        let store = SideChatStore(persisted: false)
        let thread = UUID()
        let post = feedPost(
            id: "fp_1", title: "存量帖", body: "正文一共两句。就这样。"
        )
        store.linkFeedDiscussThread(thread, postID: "fp_1")
        store.setDraft(
            FeedDiscussPrefill.make(title: post.title, body: post.body),
            for: thread
        )
        let cleared = store.purgeLegacyFeedDiscussDrafts(
            posts: [post]
        )
        XCTAssertEqual(cleared, 1)
        XCTAssertNil(store.draft(for: thread))
        // 幂等：复跑恒 0、线程关联本体保留不动
        XCTAssertEqual(
            store.purgeLegacyFeedDiscussDrafts(posts: [post]), 0
        )
        XCTAssertEqual(
            store.feedDiscussPostID(forThreadID: thread), "fp_1"
        )
    }

    func testPurgeKeepsEditedDraft() {
        // 用户改过一字＝亲笔，清扫不许动
        let store = SideChatStore(persisted: false)
        let thread = UUID()
        let post = feedPost(
            id: "fp_1", title: "存量帖", body: "正文一共两句。就这样。"
        )
        store.linkFeedDiscussThread(thread, postID: "fp_1")
        let edited = FeedDiscussPrefill.make(
            title: post.title, body: post.body
        ).replacingOccurrences(of: "两句", with: "三句")
        store.setDraft(edited, for: thread)
        XCTAssertEqual(
            store.purgeLegacyFeedDiscussDrafts(posts: [post]), 0
        )
        XCTAssertEqual(store.draft(for: thread), edited)
    }

    func testPurgeKeepsHandwrittenDrafts() {
        // 亲笔保活零误伤：讨论线程里的亲笔、无关联线
        // 程的亲笔，两者都不是机器预填、都不许清
        let store = SideChatStore(persisted: false)
        let discussThread = UUID()
        let plainThread = UUID()
        let post = feedPost(
            id: "fp_1", title: "存量帖", body: "正文"
        )
        store.linkFeedDiscussThread(discussThread, postID: "fp_1")
        store.setDraft("我自己写了一半的话", for: discussThread)
        store.setDraft("另一条线的亲笔草稿", for: plainThread)
        XCTAssertEqual(
            store.purgeLegacyFeedDiscussDrafts(posts: [post]), 0
        )
        XCTAssertEqual(
            store.draft(for: discussThread), "我自己写了一半的话"
        )
        XCTAssertEqual(
            store.draft(for: plainThread), "另一条线的亲笔草稿"
        )
    }

    func testPurgeSkipsDraftWhenPostUnavailable() {
        // 原帖已不在名单（过期）：无从逐字核验，不清
        let store = SideChatStore(persisted: false)
        let thread = UUID()
        store.linkFeedDiscussThread(thread, postID: "fp_gone")
        let machine = FeedDiscussPrefill.make(
            title: "已过期帖", body: "正文"
        )
        store.setDraft(machine, for: thread)
        XCTAssertEqual(
            store.purgeLegacyFeedDiscussDrafts(posts: [
                feedPost(id: "fp_other", title: "别的帖", body: "正文"),
            ]),
            0
        )
        XCTAssertEqual(store.draft(for: thread), machine)
    }
}
