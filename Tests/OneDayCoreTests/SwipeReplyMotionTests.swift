import OneDayCore
import XCTest

/// 右滑引用纯逻辑（0.36.19，§84.3）：方向门/跟手位
/// 移/触发阈值/显形进度。呈现层手势与滚动的仲裁不
/// 在此测——门控构造（接管前零写入、纵向锁不上）
/// 由本层判据保证，视图层只消费
final class SwipeReplyMotionTests: XCTestCase {

    // MARK: - 方向门（右向＋横向主导，与抽屉 S2 同源）

    func testEngagesOnlyRightwardHorizontalDominant() {
        // 纯右拖与横向主导的斜拖接管
        XCTAssertTrue(SwipeReplyMotion.engages(dx: 20, dy: 0))
        XCTAssertTrue(SwipeReplyMotion.engages(dx: 30, dy: 20))
        // 纵向主导（列表滚动的形态）永远锁不上
        XCTAssertFalse(SwipeReplyMotion.engages(dx: 12, dy: 20))
        XCTAssertFalse(SwipeReplyMotion.engages(dx: 0, dy: 30))
        // 左拖不接管（本手势只认右滑）
        XCTAssertFalse(SwipeReplyMotion.engages(dx: -20, dy: 0))
        // 未达锁定距离（抽屉 S2 的 10pt）不接管
        XCTAssertFalse(SwipeReplyMotion.engages(dx: 9, dy: 0))
    }

    // MARK: - 跟手位移（扣锁定段、两端钳制）

    func testFollowedOffsetDeductsLockAndClamps() {
        // 接管瞬间位移为 0（起步无跳）
        XCTAssertEqual(
            SwipeReplyMotion.followedOffset(dx: 12, lockTranslation: 12),
            0
        )
        // 界内 1:1
        XCTAssertEqual(
            SwipeReplyMotion.followedOffset(dx: 42, lockTranslation: 12),
            30
        )
        // 向右封顶 maxOffset
        XCTAssertEqual(
            SwipeReplyMotion.followedOffset(dx: 300, lockTranslation: 12),
            SwipeReplyMotion.maxOffset
        )
        // 回拖过起点钳到 0，不出负位移
        XCTAssertEqual(
            SwipeReplyMotion.followedOffset(dx: 4, lockTranslation: 12),
            0
        )
    }

    // MARK: - 触发阈值（只认松手位移、不认速度）

    func testShouldTriggerAtThreshold() {
        XCTAssertFalse(
            SwipeReplyMotion.shouldTrigger(
                offset: SwipeReplyMotion.triggerOffset - 0.1
            )
        )
        XCTAssertTrue(
            SwipeReplyMotion.shouldTrigger(
                offset: SwipeReplyMotion.triggerOffset
            )
        )
        XCTAssertTrue(
            SwipeReplyMotion.shouldTrigger(
                offset: SwipeReplyMotion.maxOffset
            )
        )
    }

    // MARK: - 箭头显形进度（0…1 钳制）

    func testRevealProgressClamps() {
        XCTAssertEqual(SwipeReplyMotion.revealProgress(offset: 0), 0)
        XCTAssertEqual(
            SwipeReplyMotion.revealProgress(
                offset: SwipeReplyMotion.triggerOffset / 2
            ),
            0.5, accuracy: 0.001
        )
        XCTAssertEqual(
            SwipeReplyMotion.revealProgress(
                offset: SwipeReplyMotion.triggerOffset
            ),
            1
        )
        XCTAssertEqual(
            SwipeReplyMotion.revealProgress(offset: 200), 1
        )
        XCTAssertEqual(
            SwipeReplyMotion.revealProgress(offset: -5), 0
        )
    }
}
