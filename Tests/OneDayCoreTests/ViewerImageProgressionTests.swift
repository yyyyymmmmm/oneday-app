import OneDayCore
import XCTest

/// 查看器递进链状态机（§138，DESIGN-V4 §138）：白屏＋
/// 二次点击的病根在状态呈现缺位——本组钉死：种子先到
/// 即显、档位只升不降、有图失败不毁图、无图失败才进
/// failed 且重试有门。宿主只按状态机呈现，不自拼状态
final class ViewerImageProgressionTests: XCTestCase {

    func testTierOrderingAndLongEdges() {
        XCTAssertLessThan(ImageRenditionTier.seed, .thumb)
        XCTAssertLessThan(ImageRenditionTier.thumb, .viewer)
        XCTAssertLessThan(ImageRenditionTier.viewer, .detail)
        XCTAssertLessThan(ImageRenditionTier.detail, .original)
        XCTAssertEqual(ImageRenditionTier.thumb.longEdge, 360)
        XCTAssertEqual(ImageRenditionTier.viewer.longEdge, 1080)
        XCTAssertEqual(ImageRenditionTier.detail.longEdge, 2048)
        XCTAssertEqual(ImageRenditionTier.thumb.renditionWidth, 360)
        XCTAssertEqual(ImageRenditionTier.viewer.renditionWidth, 1080)
        XCTAssertEqual(ImageRenditionTier.detail.renditionWidth, 2048)
        XCTAssertNil(ImageRenditionTier.seed.renditionWidth)
        XCTAssertNil(ImageRenditionTier.original.renditionWidth)
    }

    func testSeedArrivesShowsImmediately() {
        var progression = ViewerImageProgression()
        XCTAssertEqual(progression.phase, .empty)
        XCTAssertFalse(progression.hasImage)
        progression.seedArrived()
        XCTAssertEqual(progression.phase, .showing)
        XCTAssertEqual(progression.displayedTier, .seed)
        XCTAssertTrue(progression.hasImage)
    }

    func testTierUpgradesInOrder() {
        var progression = ViewerImageProgression()
        progression.seedArrived()
        progression.tierArrived(.viewer)
        XCTAssertEqual(progression.displayedTier, .viewer)
        progression.tierArrived(.detail)
        XCTAssertEqual(progression.displayedTier, .detail)
        progression.tierArrived(.original)
        XCTAssertEqual(progression.displayedTier, .original)
        XCTAssertEqual(progression.phase, .showing)
    }

    func testLateLowerTierNeverDowngrades() {
        var progression = ViewerImageProgression()
        progression.tierArrived(.detail)
        progression.tierArrived(.viewer)
        XCTAssertEqual(progression.displayedTier, .detail)
        progression.tierArrived(.thumb)
        XCTAssertEqual(progression.displayedTier, .detail)
        // 等档迟到也不算换图
        progression.tierArrived(.detail)
        XCTAssertEqual(progression.displayedTier, .detail)
    }

    func testSeedNeverDisplacesLoadedTier() {
        var progression = ViewerImageProgression()
        progression.tierArrived(.viewer)
        progression.seedArrived()
        XCTAssertEqual(progression.displayedTier, .viewer)
    }

    func testFailureWithoutImageEntersFailed() {
        var progression = ViewerImageProgression()
        progression.tierFailed()
        XCTAssertEqual(progression.phase, .failed)
        XCTAssertFalse(progression.hasImage)
    }

    func testFailureWithImageKeepsShowingDegraded() {
        var progression = ViewerImageProgression()
        progression.seedArrived()
        progression.tierFailed()
        XCTAssertEqual(progression.phase, .showing)
        XCTAssertEqual(progression.displayedTier, .seed)
        XCTAssertTrue(progression.degraded)
        // 更高档补回来清 degraded
        progression.tierArrived(.viewer)
        XCTAssertFalse(progression.degraded)
        XCTAssertEqual(progression.displayedTier, .viewer)
    }

    func testRetryOnlyFromFailedAndCountsAttempts() {
        var progression = ViewerImageProgression()
        XCTAssertFalse(progression.retry())
        progression.seedArrived()
        XCTAssertFalse(progression.retry())
        progression.reset()
        progression.tierFailed()
        XCTAssertTrue(progression.retry())
        XCTAssertEqual(progression.phase, .empty)
        XCTAssertEqual(progression.attempt, 1)
        progression.tierFailed()
        XCTAssertTrue(progression.retry())
        XCTAssertEqual(progression.attempt, 2)
    }

    func testLateSuccessAfterFailureRecovers() {
        var progression = ViewerImageProgression()
        progression.tierFailed()
        XCTAssertEqual(progression.phase, .failed)
        progression.tierArrived(.viewer)
        XCTAssertEqual(progression.phase, .showing)
        XCTAssertEqual(progression.displayedTier, .viewer)
    }

    func testResetClearsEverything() {
        var progression = ViewerImageProgression()
        progression.tierArrived(.detail)
        progression.tierFailed()
        progression.reset()
        XCTAssertEqual(progression, ViewerImageProgression())
        XCTAssertEqual(progression.phase, .empty)
        XCTAssertNil(progression.displayedTier)
    }

    func testRemoteImageKeyStabilityAndSeparation() {
        let key = RemoteImageKey.make(
            path: "/opt/data/a.png", mtime: 100, tier: .viewer)
        XCTAssertEqual(
            key,
            RemoteImageKey.make(
                path: "/opt/data/a.png", mtime: 100, tier: .viewer))
        XCTAssertNotEqual(
            key,
            RemoteImageKey.make(
                path: "/opt/data/a.png", mtime: 101, tier: .viewer))
        XCTAssertNotEqual(
            key,
            RemoteImageKey.make(
                path: "/opt/data/a.png", mtime: 100, tier: .thumb))
        XCTAssertNotEqual(
            key,
            RemoteImageKey.make(
                path: "/opt/data/b.png", mtime: 100, tier: .viewer))
    }
}
