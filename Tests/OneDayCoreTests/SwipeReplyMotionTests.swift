import OneDayCore
import XCTest

/// 右滑引用纯逻辑（0.36.19，§84.3；0.36.20 §85 补
/// 方向生死判据；0.36.21 §88 生死判据改速度域）：
/// 方向门/跟手位移/触发阈值/显形进度。0.36.19 的教
/// 训（P-15）：本文件旧头注写「呈现层手势与滚动的
/// 仲裁不在此测」——判据全过、共存从未验，纵滚在真
/// 机被压死。方向生死判据（shouldBeginPan）自 0.36.20
/// 起在此钉死、0.36.21 改判速度域（位移域版随 §88
/// 定案退役），且验收必含真机「从气泡上起手纵滚」
/// 与「右滑过半程触发引用」并列两条（见 DESIGN §88
/// 复验口径）
final class SwipeReplyMotionTests: XCTestCase {

    // MARK: - 方向生死判据（0.36.21 §88：速度域，桥 shouldBegin 同源）
    //
    // 0.36.20 的位移域判据（shouldBeginPan(dx:dy:) 与
    // engages 逐点相等那组测试）已随定案退役：should-
    // Begin 时位移未达锁定距离、位移判据恒拒，右滑在
    // 真机全灭。速度域判据只保留方向与比值（比值引
    // DrawerMotion.directionLockRatio 单源），pt/s 与
    // pt 不同量纲、不设距离门。仲裁四态对本形态的映
    // 射：拒 begin＝识别层自取消（本次触摸零写入）；
    // 允 begin 后禁滚由系统默认排斥仲裁承担；全程不
    // 改任何滚动开关，松手/系统取消无状态可恢复、
    // 只复位位移（呈现层口径，见桥与修饰符）

    func testShouldBeginPanRejectsVerticalDominantVelocity() {
        // 纯纵向与纵向主导的速度：拒 begin、纵滚归列表
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            velocityX: 0, velocityY: 300))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            velocityX: 50, velocityY: 400))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            velocityX: 120, velocityY: 200))
        // 临界比值外侧：vx 只差一点不到 1.5×vy 仍拒
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            velocityX: 149, velocityY: 100))
    }

    func testShouldBeginPanAllowsHorizontalDominantVelocity() {
        // 纯右向与横向主导的速度：必允
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(
            velocityX: 300, velocityY: 0))
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(
            velocityX: 300, velocityY: 200))
        // 临界比值恰达 1.5 倍：按 ≥ 口径允
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(
            velocityX: 150, velocityY: 100))
        // 慢速但方向明确的右拖同样允（速度域不设大小
        // 门——SwipeCellKit 同形态：只问角度不问快慢）
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(
            velocityX: 40, velocityY: 10))
    }

    func testShouldBeginPanRejectsLeftwardAndStillVelocity() {
        // 左向不归本手势
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            velocityX: -300, velocityY: 0))
        // 静止/未定案：不 begin（本次触摸零写入）
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            velocityX: 0, velocityY: 0))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            velocityX: 0, velocityY: -200))
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
