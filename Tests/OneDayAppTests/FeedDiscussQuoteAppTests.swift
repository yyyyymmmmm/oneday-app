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
}
