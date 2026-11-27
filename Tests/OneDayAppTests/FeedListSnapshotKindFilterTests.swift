import XCTest
@testable import OneDayApp
import OneDayCore

/// 动态流过滤点子卡测试（UI7-7 返工）：按 FeedPostKind 判别——
/// 点子卡给独立 kind 时滤除，事件帖引用点子不误滤，普通帖保留
final class FeedListSnapshotKindFilterTests: XCTestCase {

    /// 纯点子卡（future）：当服务端下发 kind=ideaCard 时应滤除
    func testIdeaCardFiltering_futureKind() {
        // 当前 FeedPostKind 无 ideaCard，此测试预留给未来
        // 实现时验证：点子卡应从动态流滤除
        let posts: [BridgeFeedPost] = [
            makeMockPost(kind: .digest, title: "普通动态", refs: []),
            // 未来点子卡：kind 为 .ideaCard（待补充枚举值）
            makeMockPost(kind: .digest, title: "点子", refs: [])
        ]
        let snapshot = FeedListSnapshot.make(
            posts: posts, searchText: "", isSearching: false
        )
        // 当前实现：所有帖都保留（点子卡 kind 未出现）
        XCTAssertEqual(snapshot.visiblePosts.count, 2)
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
