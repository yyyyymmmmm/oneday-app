import OneDayCore
import XCTest

/// 右滑引用纯逻辑（0.36.19，§84.3；0.36.20 §85 补
/// 方向生死判据）：方向门/跟手位移/触发阈值/显形进
/// 度。0.36.19 的教训（P-15）：本文件旧头注写「呈现
/// 层手势与滚动的仲裁不在此测」——判据全过、共存从
/// 未验，纵滚在真机被压死。自 0.36.20 起方向生死判
/// 据（shouldBeginPan）也在此钉死，且验收必含真机
/// 「从气泡上起手纵滚」一条（见 DESIGN §85 复验口径）
final class SwipeReplyMotionTests: XCTestCase {

    // MARK: - 方向生死判据（0.36.20：UIKit 桥 shouldBegin 同源）

    func testShouldBeginPanRejectsVerticalDominant() {
        // 纯纵向与纵向主导的斜拖：识别器必死、纵滚归列表
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(dx: 0, dy: 30))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(dx: 5, dy: 40))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(dx: 12, dy: 20))
        // 临界比值外侧：|dx| 只差一点不到 1.5×|dy| 仍拒
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(dx: 14, dy: 10))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(dx: 10, dy: 7))
    }

    func testShouldBeginPanAllowsHorizontalDominant() {
        // 纯右拖与横向主导：必允
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(dx: 20, dy: 0))
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(dx: 30, dy: 20))
        // 恰达锁定距离 10pt：允
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(dx: 10, dy: 0))
        // 临界比值恰达 1.5 倍：按 engages 既有口径（≥）允
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(dx: 15, dy: 10))
    }

    func testShouldBeginPanRejectsLeftwardAndShort() {
        // 左拖不归本手势
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(dx: -20, dy: 0))
        // 未达锁定距离：不 begin（与滚动的先手之争不许
        // 在 10pt 内发生）
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(dx: 9, dy: 0))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(dx: 0, dy: 0))
    }

    func testShouldBeginPanMatchesEngages() {
        // 桥判据与方向门永远同源：抽查网格逐点相等，
        // 防将来任一处改口径另一处漏改
        for dx in stride(from: -30.0, through: 30.0, by: 5.0) {
            for dy in stride(from: -30.0, through: 30.0, by: 5.0) {
                XCTAssertEqual(
                    SwipeReplyMotion.shouldBeginPan(dx: dx, dy: dy),
                    SwipeReplyMotion.engages(dx: dx, dy: dy),
                    "dx=\(dx) dy=\(dy)"
                )
            }
        }
    }

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
