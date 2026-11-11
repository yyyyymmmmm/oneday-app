import OneDayCore
import XCTest

/// 动态页紧凑化（§126）：列表顶部避让政策——顶距
/// 只随真实重叠存在，无重叠恒 0（§122 无条件 64pt
/// 的病不许以「换个小数字」的形式复发）；真重叠＝
/// 实测重叠高度＋gap 原样透传，不在政策内再加工。
final class FeedCompact126Tests: XCTestCase {

    func testTopClearanceIsZeroWhenNoOverlay() {
        XCTAssertEqual(
            FeedBoard.topClearance(overlayHeight: nil, gap: 8), 0
        )
    }

    func testTopClearanceIsZeroWhenOverlayHeightIsZero() {
        XCTAssertEqual(
            FeedBoard.topClearance(overlayHeight: 0, gap: 8), 0
        )
    }

    func testTopClearanceIsZeroWhenOverlayHeightIsNegative() {
        XCTAssertEqual(
            FeedBoard.topClearance(overlayHeight: -12, gap: 8), 0
        )
    }

    func testTopClearanceAddsGapToMeasuredOverlap() {
        XCTAssertEqual(
            FeedBoard.topClearance(overlayHeight: 44, gap: 8), 52
        )
    }

    func testTopClearancePassesGapThroughUnchanged() {
        XCTAssertEqual(
            FeedBoard.topClearance(overlayHeight: 30, gap: 16), 46
        )
        XCTAssertEqual(
            FeedBoard.topClearance(overlayHeight: 30, gap: 0), 30
        )
    }
}
