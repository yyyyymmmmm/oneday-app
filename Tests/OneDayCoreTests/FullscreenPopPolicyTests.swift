import XCTest
@testable import OneDayCore

/// 全屏右滑返回裁决表钉测（呈现与导航手势审计
/// 2026-11-24 问题二）：统一桥的放行条件逐行钉
/// 死——栈深 1 不触发、横向主导才放行、转场在
/// 飞与豁免区一律让行；卡级让行（H1）同包钉。
final class FullscreenPopPolicyTests: XCTestCase {

    private func scene(
        depth: Int = 2,
        translation: CGSize = CGSize(width: 40, height: 6),
        transitioning: Bool = false,
        exempt: Bool = false
    ) -> FullscreenPopPolicy.Scene {
        FullscreenPopPolicy.Scene(
            stackDepth: depth,
            translation: translation,
            isTransitioning: transitioning,
            startsInExemptRegion: exempt
        )
    }

    func testRootPageNeverBegins() {
        XCTAssertFalse(FullscreenPopPolicy.shouldBegin(
            scene(depth: 1)
        ))
        XCTAssertFalse(FullscreenPopPolicy.shouldBegin(
            scene(depth: 0)
        ))
    }

    func testPushedPageRightwardHorizontalBegins() {
        XCTAssertTrue(FullscreenPopPolicy.shouldBegin(
            scene(depth: 2)
        ))
        XCTAssertTrue(FullscreenPopPolicy.shouldBegin(
            scene(
                depth: 5,
                translation: CGSize(width: 12, height: 11)
            )
        ))
    }

    func testVerticalDominantYieldsToScroll() {
        XCTAssertFalse(FullscreenPopPolicy.shouldBegin(
            scene(translation: CGSize(width: 6, height: 40))
        ))
        // 等幅不算横向主导
        XCTAssertFalse(FullscreenPopPolicy.shouldBegin(
            scene(translation: CGSize(width: 20, height: 20))
        ))
        XCTAssertFalse(FullscreenPopPolicy.shouldBegin(
            scene(translation: CGSize(width: 20, height: -20))
        ))
    }

    func testLeftwardNeverBegins() {
        XCTAssertFalse(FullscreenPopPolicy.shouldBegin(
            scene(translation: CGSize(width: -40, height: 6))
        ))
        XCTAssertFalse(FullscreenPopPolicy.shouldBegin(
            scene(translation: .zero)
        ))
    }

    func testTransitionInFlightBlocks() {
        XCTAssertFalse(FullscreenPopPolicy.shouldBegin(
            scene(transitioning: true)
        ))
    }

    func testExemptRegionBlocks() {
        XCTAssertFalse(FullscreenPopPolicy.shouldBegin(
            scene(exempt: true)
        ))
    }

    // MARK: - H1 卡级让行

    func testCardDragYieldsWhenInnerStackPushed() {
        XCTAssertTrue(HubCardTransition.allowsCardDrag(
            innerStackDepth: 1
        ))
        XCTAssertTrue(HubCardTransition.allowsCardDrag(
            innerStackDepth: 0
        ))
        XCTAssertFalse(HubCardTransition.allowsCardDrag(
            innerStackDepth: 2
        ))
        XCTAssertFalse(HubCardTransition.allowsCardDrag(
            innerStackDepth: 4
        ))
    }
}
