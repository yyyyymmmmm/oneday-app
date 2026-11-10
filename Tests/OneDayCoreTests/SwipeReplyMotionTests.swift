import OneDayCore
import XCTest

/// 右滑引用纯逻辑（0.36.19，§84.3；0.36.20 §85 补
/// 方向生死判据；0.36.21 §88 曾改速度域；0.36.23
/// §90 回归位移纯比值）：
/// 方向门/跟手位移/触发阈值/显形进度。0.36.19 的教
/// 训（P-15）：本文件旧头注写「呈现层手势与滚动的
/// 仲裁不在此测」——判据全过、共存从未验，纵滚在真
/// 机被压死。方向生死判据（shouldBeginPan）自 0.36.20
/// 起在此钉死：0.36.21 的速度域版随 §90 调研裁决退
/// 役（立论依据 PR #381 未证实合入、SwipeCellKit
/// 现行 master 仍是位移比值），本轮回归位移纯比值
/// （无量级门）；验收必含真机「从气泡上起手纵滚」
/// 与「右滑过半程触发引用」并列两条，另加「斜向慢
/// 滑不误触」（见 DESIGN §90 复验口径）
final class SwipeReplyMotionTests: XCTestCase {

    // MARK: - 方向生死判据（0.36.23 §90：位移纯比值，桥 shouldBegin 同源）
    //
    // 沿革：0.36.20 位移域判据带 10pt 量级门——should-
    // Begin 一次性闸门在数 pt 时被咨询、量级门数学上
    // 过不去，真机右滑全灭；0.36.21 改速度域——立论
    // （SwipeCellKit PR #381 已合入 velocity 形态）经
    // §90 调研逐行核查不成立，真机仍全灭。现行判据：
    // 位移纯比值、无任何量级门，比值引 DrawerMotion
    // .directionLockRatio 单源（1.5）。仲裁对本形态的
    // 映射：拒 begin＝识别器当场 Failed、桥侧失败要
    // 求随即放行滚动 pan（本次触摸零写入）；允 begin
    // 后滚动 pan 按 require(toFail:) 语义已被置
    // Failed、本段触摸内绝不滚动；全程不改任何滚动
    // 开关，松手/系统取消无状态可恢复、只复位位移
    // （呈现层口径，见桥与修饰符）

    func testShouldBeginPanRejectsVerticalDominantTranslation() {
        // 纯纵向与纵向主导的首次移动：拒 begin、纵滚归列表
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            dx: 0, dy: 3))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            dx: 2, dy: 10))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            dx: 10, dy: 20))
        // 临界比值外侧：dx 只差一点不到 1.5×dy 仍拒
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            dx: 14, dy: 10))
    }

    func testShouldBeginPanAllowsHorizontalDominantTranslation() {
        // 纯右向与横向主导的首次移动：必允——位移只有
        // 数 pt 也定案（纯比值与量级无关，正是闸门能
        // 活下来的形态）
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(
            dx: 3, dy: 0))
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(
            dx: 30, dy: 20))
        // 临界比值恰达 1.5 倍：按 ≥ 口径允
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(
            dx: 15, dy: 10))
        // 慢拖但方向明确同样允（只问比值不问快慢）
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(
            dx: 4, dy: 1))
    }

    func testShouldBeginPanRejectsLeftwardAndStillTranslation() {
        // 左向不归本手势
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            dx: -30, dy: 0))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            dx: -3, dy: -1))
        // 静止/未动：不 begin（本次触摸零写入）
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            dx: 0, dy: 0))
        XCTAssertFalse(SwipeReplyMotion.shouldBeginPan(
            dx: 0, dy: -20))
    }

    func testShouldBeginPanHasNoMagnitudeGate() {
        // 与 engages 的分工钉死：同样 (3, 2) 这一步，
        // engages 带 10pt 锁定距离判「未接管」，should-
        // BeginPan 无量级门判「可 begin」——前者是跟手
        // 接管的语义判据、后者是一次性闸门的生死判据，
        // 0.36.20 把带量级门的判据喂闸门正是全灭病根，
        // 本测试防它以任何形式回来
        XCTAssertFalse(SwipeReplyMotion.engages(dx: 3, dy: 2))
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(dx: 3, dy: 2))
        XCTAssertTrue(SwipeReplyMotion.shouldBeginPan(dx: 1, dy: 0))
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
