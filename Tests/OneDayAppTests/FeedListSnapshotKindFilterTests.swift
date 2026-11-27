import XCTest
@testable import OneDayApp
import OneDayCore

/// 动态流过滤点子卡测试（UI7-7 返工）：按 FeedPostKind 判别——
/// .seed 即点子卡形态（FA-2 首次种子帖），滤除；事件帖引用点子不误滤
final class FeedListSnapshotKindFilterTests: XCTestCase {

    /// 种子帖过滤：kind=.seed 应从动态流滤除
    func testSeedPostFiltering() {
        let posts: [BridgeFeedPost] = [
            makeMockPost(kind: .digest, title: "普通动态", refs: []),
            makeMockPost(kind: .seed, title: "动态替你盯着感兴趣的事", refs: []),
            makeMockPost(kind: .research, title: "调研帖", refs: [])
        ]
        let snapshot = FeedListSnapshot.make(
            posts: posts, searchText: "", isSearching: false
        )
        // 种子帖应滤除，只保留 digest 和 research
        XCTAssertEqual(snapshot.visiblePosts.count, 2)
        XCTAssertEqual(snapshot.visiblePosts[0].title, "普通动态")
        XCTAssertEqual(snapshot.visiblePosts[1].title, "调研帖")
    }

    /// 事件帖带点子引用：应保留（不按 refs 误滤）
    func testEventPostWithIdeaRef_notFiltered() {
        let posts: [BridgeFeedPost] = [
            makeMockPost(
                kind: .event,
                title: "我可以出本周 GitHub 活动汇总",
                refs: [.init(type: .idea, id: "idea-123")]
            ),
            makeMockPost(kind: .digest, title: "普通动态", refs: [])
        ]
        let snapshot = FeedListSnapshot.make(
            posts: posts, searchText: "", isSearching: false
        )
        // 事件帖合法引用点子，不应滤除
        XCTAssertEqual(snapshot.visiblePosts.count, 2)
        XCTAssertEqual(snapshot.visiblePosts[0].title, "我可以出本周 GitHub 活动汇总")
    }

    /// 普通帖（digest/research）：应保留
    func testRegularPosts_notFiltered() {
        let posts: [BridgeFeedPost] = [
            makeMockPost(kind: .digest, title: "今日动态", refs: []),
            makeMockPost(kind: .research, title: "调研帖", refs: []),
            makeMockPost(kind: .morning, title: "晨报", refs: [])
        ]
        let snapshot = FeedListSnapshot.make(
            posts: posts, searchText: "", isSearching: false
        )
        XCTAssertEqual(snapshot.visiblePosts.count, 3)
    }

    // MARK: - Helpers

    private func makeMockPost(
        kind: FeedPostKind,
        title: String,
        refs: [BridgeFeedRef]
    ) -> BridgeFeedPost {
        BridgeFeedPost(
            id: UUID().uuidString,
            kind: kind,
            title: title,
            body: "",
            emoji: nil,
            kicker: nil,
            createdAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            refs: refs
        )
    }
}
