import XCTest
@testable import OneDayCore

/// 台账 147（抽屉点行近闭合才导航）：延迟导航状
/// 态机的判定全集——阈值触发、单槽待办、连点忽
/// 略、打断即推、落定兜底，逐条对 OpenBot 抽屉的
/// 实际机制（NAVIGATE_AT_PROGRESS＝0.05、待办在
/// 位第二下点按整下忽略、关动画被打断即刻 push）
final class DrawerDeferredNavigationTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()

    func testStageAtFullOpenWaits() {
        var machine = DrawerDeferredNavigation()
        XCTAssertNil(machine.stage(first, currentProgress: 1))
        XCTAssertTrue(machine.hasPending)
        XCTAssertEqual(machine.pendingID, first)
    }

    func testProgressCrossingThresholdFiresOnce() {
        var machine = DrawerDeferredNavigation()
        machine.stage(first, currentProgress: 1)
        XCTAssertNil(machine.progressSample(0.5))
        XCTAssertNil(machine.progressSample(0.06))
        XCTAssertEqual(machine.progressSample(0.05), first)
        XCTAssertFalse(machine.hasPending)
        // 只执行一次：其后采样不再吐
        XCTAssertNil(machine.progressSample(0))
    }

    func testStageNearClosedFiresImmediately() {
        var machine = DrawerDeferredNavigation()
        XCTAssertEqual(
            machine.stage(first, currentProgress: 0.03), first
        )
        XCTAssertFalse(machine.hasPending)
    }

    func testSecondStageWhilePendingIsIgnored() {
        var machine = DrawerDeferredNavigation()
        machine.stage(first, currentProgress: 1)
        // 待办在位：第二下置位被忽略、首个待办为准
        XCTAssertNil(machine.stage(second, currentProgress: 0.8))
        XCTAssertEqual(machine.pendingID, first)
        XCTAssertEqual(machine.progressSample(0), first)
    }

    func testCloseInterruptedFiresImmediately() {
        var machine = DrawerDeferredNavigation()
        machine.stage(first, currentProgress: 1)
        XCTAssertNil(machine.progressSample(0.6))
        // 关动画被另一运动打断：待办即刻执行、不吞
        XCTAssertEqual(machine.closeInterrupted(), first)
        XCTAssertNil(machine.progressSample(0))
    }

    func testSettledClosedFlushesAsBackstop() {
        var machine = DrawerDeferredNavigation()
        machine.stage(first, currentProgress: 1)
        // 采样漏过阈值（如瞬时关跳变）：落定兜底
        XCTAssertEqual(machine.settledClosed(), first)
        XCTAssertNil(machine.settledClosed())
    }

    func testStageAfterFireWorksAgain() {
        var machine = DrawerDeferredNavigation()
        machine.stage(first, currentProgress: 1)
        XCTAssertEqual(machine.progressSample(0), first)
        XCTAssertNil(machine.stage(second, currentProgress: 1))
        XCTAssertEqual(machine.progressSample(0.04), second)
    }

    func testNoPendingNoFire() {
        var machine = DrawerDeferredNavigation()
        XCTAssertNil(machine.progressSample(0))
        XCTAssertNil(machine.closeInterrupted())
        XCTAssertNil(machine.settledClosed())
    }
}
