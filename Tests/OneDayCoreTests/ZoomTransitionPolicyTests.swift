import OneDayCore
import XCTest

/// Zoom 转场裁决钉（DESIGN-V4 §247.2）：两条件齐备才
/// zoom；Reduce Motion 优先于源可用性（M8 降级齐备）；
/// 无源不假放大。呈现层回潮（自行硬启 zoom）先在此红。
final class ZoomTransitionPolicyTests: XCTestCase {

    func testZoomWhenSourceAvailableAndMotionAllowed() {
        XCTAssertEqual(
            ZoomTransitionPolicy.decide(
                reduceMotion: false, sourceAvailable: true
            ),
            .zoom
        )
    }

    func testStandardWhenSourceMissing() {
        XCTAssertEqual(
            ZoomTransitionPolicy.decide(
                reduceMotion: false, sourceAvailable: false
            ),
            .standard
        )
    }

    func testStandardWhenReduceMotionEvenWithSource() {
        XCTAssertEqual(
            ZoomTransitionPolicy.decide(
                reduceMotion: true, sourceAvailable: true
            ),
            .standard
        )
    }

    func testStandardWhenReduceMotionAndNoSource() {
        XCTAssertEqual(
            ZoomTransitionPolicy.decide(
                reduceMotion: true, sourceAvailable: false
            ),
            .standard
        )
    }
}
