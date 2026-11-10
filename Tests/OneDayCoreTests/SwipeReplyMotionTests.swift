import OneDayCore
import XCTest

/// 右滑引用纯逻辑（0.36.19 立；0.36.26 §95 按
/// Stream 生产构造整件重写）：起滑线/拖动 off-
/// set/途中触发/显示封顶/显形进度/起始点排除。
/// 桥时代测试（shouldBeginPan 三件＋engages＋旧
/// followedOffset 扣锁定段＋松手触发）随判据整件
/// 退役——调研裁决（production-patterns-research-
/// 20261111 §1.4）：四轮里判据三换、死状不变，
/// 判据从来不是死因；新构造无方向门、无识别器
/// 生死关，测试面随之换代（增减账见 DESIGN
/// §95）。验收必含真机「从气泡上起手纵滚顺畅」
/// 与「右滑途中过线触发引用带震」并列两条（见
/// DESIGN §95 复验口径）
final class SwipeReplyMotionTests: XCTestCase {

    // MARK: - 参数单源（Stream 口径钉死）

    func testStreamParametersAreSingleSource() {
        // 起滑 30/途中触发 60（Stream Chat SwiftUI
        // 现行值），本处是全仓唯一出处
        XCTAssertEqual(SwipeReplyMotion.minimumDistance, 30)
        XCTAssertEqual(SwipeReplyMotion.triggerOffset, 60)
        // 显示封顶＝触发线＋起滑线（Stream maxi-
        // mumHorizontalSwipeDisplacement 同式）
        XCTAssertEqual(SwipeReplyMotion.maxOffset, 90)
        XCTAssertEqual(
            SwipeReplyMotion.maxOffset,
            SwipeReplyMotion.triggerOffset
                + SwipeReplyMotion.minimumDistance
        )
    }

    // MARK: - 拖动 offset（dragOffset）

    func testDragOffsetIgnoresBelowMinimumDistance() {
        // 未达起滑线不写位移：纵滑起手的横向分量
        // 与抖动在此归零，气泡不动
        XCTAssertEqual(
            SwipeReplyMotion.dragOffset(
                translationWidth: 0, currentOffset: 0
            ),
            0
        )
        XCTAssertEqual(
            SwipeReplyMotion.dragOffset(
                translationWidth: 29.9, currentOffset: 0
            ),
            0
        )
    }

    func testDragOffsetFollowsOneToOneAboveMinimum() {
        // 达线当刻即 1:1、不扣起滑段（手势 mini-
        // mumDistance 已把起步段挡在 onChanged
        // 之外，Stream 同式）
        XCTAssertEqual(
            SwipeReplyMotion.dragOffset(
                translationWidth: 30, currentOffset: 0
            ),
            30
        )
        XCTAssertEqual(
            SwipeReplyMotion.dragOffset(
                translationWidth: 75, currentOffset: 30
            ),
            75
        )
        // 状态值不自钳：可越过显示封顶（钳制在显示层）
        XCTAssertEqual(
            SwipeReplyMotion.dragOffset(
                translationWidth: 200, currentOffset: 90
            ),
            200
        )
    }

    func testDragOffsetDiscardsNegativeEvents() {
        // 横向位移为负的事件弃、保留现值（Stream
        // dragChanged 同义）：回拖过起点不抖，松
        // 手再统一归零
        XCTAssertEqual(
            SwipeReplyMotion.dragOffset(
                translationWidth: -10, currentOffset: 50
            ),
            50
        )
        XCTAssertEqual(
            SwipeReplyMotion.dragOffset(
                translationWidth: -10, currentOffset: 0
            ),
            0
        )
    }

    func testDragOffsetFallsBackToZeroWhenReversedBelowMinimum() {
        // 已起滑后回拖进起滑线内（仍非负）：归 0，
        // 不留半截位移
        XCTAssertEqual(
            SwipeReplyMotion.dragOffset(
                translationWidth: 12, currentOffset: 48
            ),
            0
        )
    }

    // MARK: - 显示位移（displayOffset）

    func testDisplayOffsetClampsToMax() {
        XCTAssertEqual(
            SwipeReplyMotion.displayOffset(for: 45), 45
        )
        XCTAssertEqual(
            SwipeReplyMotion.displayOffset(for: 90), 90
        )
        XCTAssertEqual(
            SwipeReplyMotion.displayOffset(for: 200), 90
        )
        XCTAssertEqual(
            SwipeReplyMotion.displayOffset(for: -5), 0
        )
    }

    // MARK: - 途中触发（越线严格大于，Stream 同义）

    func testShouldTriggerOnlyBeyondThreshold() {
        XCTAssertFalse(
            SwipeReplyMotion.shouldTrigger(offset: 59.9)
        )
        // 恰压在线上不触发（Stream `offsetX >
        // replyThreshold` 的严格大于，逐字同义）
        XCTAssertFalse(
            SwipeReplyMotion.shouldTrigger(offset: 60)
        )
        XCTAssertTrue(
            SwipeReplyMotion.shouldTrigger(offset: 60.1)
        )
        XCTAssertTrue(
            SwipeReplyMotion.shouldTrigger(offset: 90)
        )
    }

    // MARK: - 箭头显形进度（0…1 钳制，分母换触发线 60）

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

    // MARK: - 起始点排除（代码块/表格横滚区）

    func testIsExcludedByStartLocation() {
        let frames = [
            CGRect(x: 10, y: 10, width: 100, height: 40),
            CGRect(x: 200, y: 0, width: 50, height: 50),
        ]
        // 落在任一排除帧内即整段忽略
        XCTAssertTrue(
            SwipeReplyMotion.isExcluded(
                startLocation: CGPoint(x: 20, y: 20),
                frames: frames
            )
        )
        XCTAssertTrue(
            SwipeReplyMotion.isExcluded(
                startLocation: CGPoint(x: 210, y: 10),
                frames: frames
            )
        )
        // 帧外正常起滑
        XCTAssertFalse(
            SwipeReplyMotion.isExcluded(
                startLocation: CGPoint(x: 150, y: 100),
                frames: frames
            )
        )
        // 无排除帧（纯文本行）永不排除
        XCTAssertFalse(
            SwipeReplyMotion.isExcluded(
                startLocation: CGPoint(x: 20, y: 20),
                frames: []
            )
        )
    }
}
