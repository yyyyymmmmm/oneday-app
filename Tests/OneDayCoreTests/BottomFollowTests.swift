import OneDayCore
import XCTest

/// 底部跟随（0.4.2，DESIGN-V4 §27）：迟滞判定与流
/// 式节流闸的构造断言——划到底抖动的修复钉在此处：
/// 阈值附近不许翻转、流式不许逐 token 放行滚动
final class BottomFollowTests: XCTestCase {

    // MARK: - 迟滞判定

    func testProximityEntersBelowEnterDistance() {
        XCTAssertTrue(
            BottomProximity.update(distance: 95, wasNearBottom: false)
        )
        XCTAssertTrue(
            BottomProximity.update(distance: 0, wasNearBottom: false)
        )
        XCTAssertFalse(
            BottomProximity.update(distance: 96, wasNearBottom: false)
        )
        // 旧单阈值 140 在迟滞带内、未贴底时不进入
        XCTAssertFalse(
            BottomProximity.update(distance: 140, wasNearBottom: false)
        )
    }

    func testProximityHoldsInsideBandBothWays() {
        // 迟滞带（96…176）内保持原态：贴底的不脱落、
        // 未贴底的不误入——阈值附近游走不再逐帧翻转
        XCTAssertTrue(
            BottomProximity.update(distance: 140, wasNearBottom: true)
        )
        XCTAssertFalse(
            BottomProximity.update(distance: 140, wasNearBottom: false)
        )
        XCTAssertTrue(
            BottomProximity.update(distance: 96, wasNearBottom: true)
        )
        XCTAssertFalse(
            BottomProximity.update(distance: 175, wasNearBottom: false)
        )
    }

    func testProximityExitsAtExitDistance() {
        XCTAssertTrue(
            BottomProximity.update(distance: 175, wasNearBottom: true)
        )
        XCTAssertFalse(
            BottomProximity.update(distance: 176, wasNearBottom: true)
        )
        XCTAssertFalse(
            BottomProximity.update(distance: 300, wasNearBottom: true)
        )
    }

    func testProximityOverscrollStaysNear() {
        // 橡皮筋越过底部（距离为负）两向都判贴底
        XCTAssertTrue(
            BottomProximity.update(distance: -30, wasNearBottom: false)
        )
        XCTAssertTrue(
            BottomProximity.update(distance: -30, wasNearBottom: true)
        )
    }

    // MARK: - 发送贴底与回底钮事实信号（0.36.5 审计双修）

    func testNearBottomAfterOwnSendIsAlwaysTrue() {
        // 自己发送是「离底不打扰」的唯一例外：落盘成
        // 功后无条件进贴底态，不问发送前的判定为何
        XCTAssertTrue(BottomFollowPolicy.nearBottomAfterOwnSend())
    }

    func testScrollButtonHiddenWhenLastEntryVisible() {
        // 审计 bug 2 的驻留回路：几何估算说离底、但最
        // 后一条已在可见集内（事实在底）——钮必须消失
        XCTAssertFalse(
            BottomFollowPolicy.showsScrollToBottomButton(
                isNearBottom: false, lastEntryVisible: true
            )
        )
        // 已判贴底时恒不显（与旧口径一致）
        XCTAssertFalse(
            BottomFollowPolicy.showsScrollToBottomButton(
                isNearBottom: true, lastEntryVisible: true
            )
        )
        XCTAssertFalse(
            BottomFollowPolicy.showsScrollToBottomButton(
                isNearBottom: true, lastEntryVisible: false
            )
        )
    }

    func testScrollButtonShownOnlyWhenOffBottomAndLastEntryUnseen() {
        XCTAssertTrue(
            BottomFollowPolicy.showsScrollToBottomButton(
                isNearBottom: false, lastEntryVisible: false
            )
        )
    }

    // MARK: - 流式节流闸

    func testGateBlocksSmallGrowth() {
        var gate = StreamFollowGate()
        XCTAssertFalse(gate.shouldFollow(currentCount: 1))
        XCTAssertFalse(gate.shouldFollow(currentCount: 39))
        XCTAssertEqual(gate.followedCount, 0)
    }

    func testGateFollowsAtMinimumGrowthAndAccumulates() {
        var gate = StreamFollowGate()
        XCTAssertTrue(gate.shouldFollow(currentCount: 40))
        XCTAssertEqual(gate.followedCount, 40)
        // 增量按已跟随数累计：39 不放行、40 放行
        XCTAssertFalse(gate.shouldFollow(currentCount: 79))
        XCTAssertTrue(gate.shouldFollow(currentCount: 80))
        XCTAssertEqual(gate.followedCount, 80)
    }

    func testGateResetReArms() {
        var gate = StreamFollowGate()
        XCTAssertTrue(gate.shouldFollow(currentCount: 100))
        gate.reset()
        XCTAssertEqual(gate.followedCount, 0)
        XCTAssertFalse(gate.shouldFollow(currentCount: 20))
        XCTAssertTrue(gate.shouldFollow(currentCount: 45))
    }

    func testGateShorterNewStreamCountsFromZero() {
        var gate = StreamFollowGate()
        XCTAssertTrue(gate.shouldFollow(currentCount: 200))
        // 未 reset 直接开始一条更短的新流：按从零计
        XCTAssertFalse(gate.shouldFollow(currentCount: 39))
        XCTAssertTrue(gate.shouldFollow(currentCount: 40))
    }
}
