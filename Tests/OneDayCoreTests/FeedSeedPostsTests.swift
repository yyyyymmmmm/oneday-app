import XCTest
@testable import OneDayCore

/// FA-2 种子帖钉测：可见性口径逐条（无真帖＋从未产出
/// 才垫底、删了不复活、真帖出现即退场）与身份标记
/// （kicker 明示「上手指南」、不冒充生成帖）
final class FeedSeedPostsTests: XCTestCase {

    func testSeedCatalogCoversFiveTopics() {
        XCTAssertEqual(FeedSeedPosts.all.count, 5)
        XCTAssertTrue(FeedSeedPosts.all.allSatisfy {
            $0.kind == .seed && FeedSeedPosts.isSeed($0.id)
        })
        XCTAssertEqual(
            Set(FeedSeedPosts.all.map(\.id)).count, 5,
            "种子帖 id 不许重复"
        )
    }

    func testKindLabelIsTheHonestKicker() {
        XCTAssertEqual(FeedPostKind.seed.label, "上手指南")
        XCTAssertEqual(
            FeedPostKind.from("seed"), .seed,
            "桥若将来下发 seed 也不许落成别的 kind"
        )
    }

    func testVisibleOnlyWhenNeverProducedAndNoRealPosts() {
        XCTAssertEqual(
            FeedSeedPosts.visible(
                realPostCount: 0, neverProduced: true,
                deletedIDs: []
            ).count, 5
        )
        XCTAssertTrue(
            FeedSeedPosts.visible(
                realPostCount: 1, neverProduced: true,
                deletedIDs: []
            ).isEmpty,
            "真帖出现即退场"
        )
        XCTAssertTrue(
            FeedSeedPosts.visible(
                realPostCount: 0, neverProduced: false,
                deletedIDs: []
            ).isEmpty,
            "产过就不垫底（quiet 空态走旧口径）"
        )
    }

    func testDeletedSeedsNeverResurrect() {
        let deleted: Set<String> = [
            FeedSeedPosts.all[0].id, FeedSeedPosts.all[3].id,
        ]
        let visible = FeedSeedPosts.visible(
            realPostCount: 0, neverProduced: true,
            deletedIDs: deleted
        )
        XCTAssertEqual(visible.count, 3)
        XCTAssertTrue(visible.allSatisfy {
            !deleted.contains($0.id)
        })
        let allDeleted = FeedSeedPosts.visible(
            realPostCount: 0, neverProduced: true,
            deletedIDs: Set(FeedSeedPosts.all.map(\.id))
        )
        XCTAssertTrue(allDeleted.isEmpty, "全删完就是空，不许复活")
    }

    func testSeedIDsNeverCollideWithBridgeIDs() {
        XCTAssertFalse(FeedSeedPosts.isSeed("fp_123"))
        XCTAssertTrue(FeedSeedPosts.isSeed("oneday-seed-brief"))
    }
}
