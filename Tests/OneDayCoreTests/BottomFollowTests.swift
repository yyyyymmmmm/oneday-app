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

    // MARK: - 迟滞锁死序列（0.36.13，诊断 chat-bottom-geometry §2.2）

    func testProximityLatchSequenceStaysOffUntilBelowEnter() {
        // 真机驻留回路的钉死：一次 ≥176 的估算读数把
        // 判定打翻后，静止点回到迟滞带内（140）仍不
        // 恢复——必须回到进入阈值（<96）之下才复位。
        // 本序列同时是护栏：修法 1（落定复贴）落地后
        // 不许顺手改动迟滞语义去「治」这个驻留
        var near = true
        near = BottomProximity.update(distance: 200, wasNearBottom: near)
        XCTAssertFalse(near)
        near = BottomProximity.update(distance: 140, wasNearBottom: near)
        XCTAssertFalse(near)
        near = BottomProximity.update(distance: 95, wasNearBottom: near)
        XCTAssertTrue(near)
    }

    // MARK: - 最后渲染项滚动目标（0.36.13，诊断 §2.3 事实路堵洞）

    private func stub(
        _ id: UUID, tool: Bool = false
    ) -> LastScrollTarget.EntryStub {
        LastScrollTarget.EntryStub(id: id, isToolCard: tool)
    }

    func testLastScrollTargetWhenLastIsText() {
        let a = UUID(), b = UUID(), c = UUID()
        // 末条为文本：目标就是末条本身（含前方有工
        // 具组也不影响——组不在尾部）
        XCTAssertEqual(
            LastScrollTarget.lastScrollTargetID(
                entries: [stub(a), stub(b, tool: true),
                          stub(UUID(), tool: true), stub(c)]
            ),
            c
        )
        XCTAssertEqual(
            LastScrollTarget.lastScrollTargetID(entries: [stub(a)]),
            a
        )
    }

    func testLastScrollTargetWhenLastIsSingleTool() {
        let a = UUID(), b = UUID()
        // 末条为单个工具条目（连段长 1、不成组）：
        // 渲染走 .entry 原路、目标仍是其本身
        XCTAssertEqual(
            LastScrollTarget.lastScrollTargetID(
                entries: [stub(a), stub(b, tool: true)]
            ),
            b
        )
    }

    func testLastScrollTargetWhenLastIsInToolGroup() {
        let a = UUID(), g1 = UUID(), g2 = UUID(), g3 = UUID()
        // 末条在 ≥2 工具组内：目标是组首条——旧实现
        // 拿末条 id 比可见集永假的病灶钉在此
        XCTAssertEqual(
            LastScrollTarget.lastScrollTargetID(
                entries: [stub(a), stub(g1, tool: true),
                          stub(g2, tool: true)]
            ),
            g1
        )
        XCTAssertEqual(
            LastScrollTarget.lastScrollTargetID(
                entries: [stub(g1, tool: true), stub(g2, tool: true),
                          stub(g3, tool: true)]
            ),
            g1
        )
        // 工具组不在尾部时不越界：其后有文本则目标
        // 是该文本（由上一组用例覆盖，此处钉组后单
        // 工具的边界——连段被文本截断后重新起算）
        XCTAssertEqual(
            LastScrollTarget.lastScrollTargetID(
                entries: [stub(g1, tool: true), stub(g2, tool: true),
                          stub(a), stub(g3, tool: true)]
            ),
            g3
        )
    }

    func testLastScrollTargetWhenEmpty() {
        XCTAssertNil(
            LastScrollTarget.lastScrollTargetID(entries: [])
        )
    }

    // MARK: - 落定复贴阈值（0.36.13，诊断修法 1）

    func testBottomSettleRestickThreshold() {
        // 正常落定误差（尾锚＋padding＋边距 ≈17pt）
        // 不触发；阈值本值不触发（严格大于）；估算误
        // 差量级（57pt）必触发；橡皮筋负距不触发
        XCTAssertFalse(BottomSettle.shouldRestick(distance: 17))
        XCTAssertFalse(BottomSettle.shouldRestick(distance: 24))
        XCTAssertTrue(BottomSettle.shouldRestick(distance: 25))
        XCTAssertTrue(BottomSettle.shouldRestick(distance: 57))
        XCTAssertFalse(BottomSettle.shouldRestick(distance: -10))
    }
}
