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

    // MARK: - 发送贴底与回底钮显隐（0.36.5 审计双修；§135 显隐改几何单源）

    func testNearBottomAfterOwnSendIsAlwaysTrue() {
        // 自己发送是「离底不打扰」的唯一例外：落盘成
        // 功后无条件进贴底态，不问发送前的判定为何
        XCTAssertTrue(BottomFollowPolicy.nearBottomAfterOwnSend())
    }

    func testScrollButtonHiddenWhenNearBottom() {
        // §135 几何单源：判在底即不显——「钮不显即在
        // 底」是回底钮与未读计数共用的唯一口径
        XCTAssertFalse(
            BottomFollowPolicy.showsScrollToBottomButton(
                isNearBottom: true
            )
        )
    }

    func testScrollButtonShownWhenOffBottom() {
        // §135 改判：0.36.5 的事实信号纠偏（几何离底
        // 但末条在可见集内则压显）已随其 @State 回写
        // 风暴一并退役——几何离底即显示，不问末条可
        // 见与否（旧断言两法随口径作废改写于此）
        XCTAssertTrue(
            BottomFollowPolicy.showsScrollToBottomButton(
                isNearBottom: false
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

    // MARK: - 落定复贴阈值（0.36.13，诊断修法 1；§176 收紧 24 → 7）

    func testBottomSettleRestickThreshold() {
        // §176 阈值 7：带内残差（≤7）不触发；阈值本
        // 值不触发（严格大于）；诊断截图实测残差 8.3
        // 自此必触发（旧阈 24 时被放行）；旧口径下
        // 「正常落定误差」带的 17 现亦触发（以观感
        // 换紧凑的定版取舍）；估算误差量级（57pt）
        // 必触发；橡皮筋负距不触发
        XCTAssertFalse(BottomSettle.shouldRestick(distance: 3))
        XCTAssertFalse(BottomSettle.shouldRestick(distance: 7))
        XCTAssertTrue(BottomSettle.shouldRestick(distance: 8))
        XCTAssertTrue(BottomSettle.shouldRestick(distance: 8.3))
        XCTAssertTrue(BottomSettle.shouldRestick(distance: 17))
        XCTAssertTrue(BottomSettle.shouldRestick(distance: 57))
        XCTAssertFalse(BottomSettle.shouldRestick(distance: -10))
    }

    func testBottomSettleThresholdValue() {
        // 阈值本值钉死（§176）：间距链写死 17＋本值
        // 7＝稳态总量上限 24，与目标带对平；改值必
        // 先改 DESIGN §176 的九环对账
        XCTAssertEqual(BottomSettle.restickThreshold, 7)
    }
}

extension BottomFollowTests {

    // MARK: - 离底未读计数（0.41.0 收口批）

    private func ids(_ n: Int, from base: Int = 0) -> [UUID] {
        (0..<n).map { i in
            UUID(uuidString: String(
                format: "00000000-0000-0000-0000-%012d", base + i + 1
            ))!
        }
    }

    func testAwayUnreadStaysZeroAtBottom() {
        var counter = AwayUnreadCounter()
        XCTAssertEqual(counter.ingest(entryIDs: ids(3), isAtBottom: true), 0)
        XCTAssertEqual(counter.ingest(entryIDs: ids(5), isAtBottom: true), 0)
        XCTAssertNil(counter.displayText)
    }

    func testAwayUnreadCountsOnlyEntriesAfterLeaving() {
        var counter = AwayUnreadCounter()
        _ = counter.ingest(entryIDs: ids(3), isAtBottom: true)
        // 离底后新增 2 条
        XCTAssertEqual(counter.ingest(entryIDs: ids(5), isAtBottom: false), 2)
        // 流式原地生长（id 不变）不计数
        XCTAssertEqual(counter.ingest(entryIDs: ids(5), isAtBottom: false), 2)
        // 再新增 1 条
        XCTAssertEqual(counter.ingest(entryIDs: ids(6), isAtBottom: false), 3)
        XCTAssertEqual(counter.displayText, "3")
    }

    func testAwayUnreadFirstAwayFrameDoesNotInventCount() {
        // 从未在底建立水位（冷开即离底）：首帧只立水
        // 位、不把既有历史算成未读
        var counter = AwayUnreadCounter()
        XCTAssertEqual(counter.ingest(entryIDs: ids(10), isAtBottom: false), 0)
        XCTAssertEqual(counter.ingest(entryIDs: ids(11), isAtBottom: false), 1)
    }

    func testAwayUnreadResetsWhenBackAtBottom() {
        var counter = AwayUnreadCounter()
        _ = counter.ingest(entryIDs: ids(3), isAtBottom: true)
        _ = counter.ingest(entryIDs: ids(6), isAtBottom: false)
        XCTAssertEqual(counter.count, 3)
        XCTAssertEqual(counter.ingest(entryIDs: ids(6), isAtBottom: true), 0)
        XCTAssertNil(counter.displayText)
    }

    func testAwayUnreadOwnSendClears() {
        var counter = AwayUnreadCounter()
        _ = counter.ingest(entryIDs: ids(3), isAtBottom: true)
        _ = counter.ingest(entryIDs: ids(5), isAtBottom: false)
        XCTAssertEqual(counter.count, 2)
        counter.noteOwnSend(entryIDs: ids(6))
        XCTAssertEqual(counter.count, 0)
        // 发送后离底再新增，从发送条之后起算
        XCTAssertEqual(counter.ingest(entryIDs: ids(7), isAtBottom: false), 1)
    }

    func testAwayUnreadWatermarkDeletedFallsBackToZero() {
        var counter = AwayUnreadCounter()
        let first = ids(3)
        _ = counter.ingest(entryIDs: first, isAtBottom: true)
        _ = counter.ingest(entryIDs: ids(5), isAtBottom: false)
        XCTAssertEqual(counter.count, 2)
        // 水位条目被删（整表换血）：不虚报，重立水位
        XCTAssertEqual(counter.ingest(entryIDs: ids(4, from: 100), isAtBottom: false), 0)
    }

    func testAwayUnreadResetAllClearsWatermark() {
        var counter = AwayUnreadCounter()
        _ = counter.ingest(entryIDs: ids(3), isAtBottom: true)
        _ = counter.ingest(entryIDs: ids(5), isAtBottom: false)
        counter.resetAll()
        XCTAssertEqual(counter.count, 0)
        // 新线程离底首帧只立水位
        XCTAssertEqual(counter.ingest(entryIDs: ids(9, from: 50), isAtBottom: false), 0)
    }

    func testAwayUnreadDisplayCap() {
        var counter = AwayUnreadCounter()
        _ = counter.ingest(entryIDs: ids(1), isAtBottom: true)
        _ = counter.ingest(entryIDs: ids(150), isAtBottom: false)
        XCTAssertEqual(counter.count, 149)
        XCTAssertEqual(counter.displayText, "99+")
    }

    func testAwayUnreadEmptyListClears() {
        var counter = AwayUnreadCounter()
        _ = counter.ingest(entryIDs: ids(3), isAtBottom: true)
        _ = counter.ingest(entryIDs: ids(5), isAtBottom: false)
        XCTAssertEqual(counter.ingest(entryIDs: [], isAtBottom: false), 0)
    }

    // MARK: - §124 补钉（落位整套退役后，判定层口径续钉）

    /// 角标封顶边界：恰 99 显「99」、100 起才显
    /// 「99+」——既有封顶测只钉 149，本测补边界本值
    func testAwayUnreadDisplayTextAtCapBoundary() {
        var counter = AwayUnreadCounter()
        _ = counter.ingest(entryIDs: ids(1), isAtBottom: true)
        XCTAssertEqual(counter.ingest(entryIDs: ids(100), isAtBottom: false), 99)
        XCTAssertEqual(counter.displayText, "99")
        XCTAssertEqual(counter.ingest(entryIDs: ids(101), isAtBottom: false), 100)
        XCTAssertEqual(counter.displayText, "99+")
    }

    /// 水位之后的条目被删：计数随现存条目回落，不
    /// 停在删除前的虚高（结构体头注「计数回落」的
    /// 部分删除分支，既有测只覆盖整表换血）
    func testAwayUnreadShrinkAfterWatermarkReducesCount() {
        var counter = AwayUnreadCounter()
        _ = counter.ingest(entryIDs: ids(3), isAtBottom: true)
        XCTAssertEqual(counter.ingest(entryIDs: ids(5), isAtBottom: false), 2)
        XCTAssertEqual(counter.ingest(entryIDs: ids(4), isAtBottom: false), 1)
        XCTAssertEqual(counter.ingest(entryIDs: ids(3), isAtBottom: false), 0)
    }

    /// 点钮 reset 的语义钉：只清计数、水位不动——
    /// 下一帧若仍离底，计数按水位如实重算（视图层
    /// 点钮后程式贴底、随后 ingest 以在底事实推进
    /// 水位，两步口径不许在 Core 侧混成「reset 即
    /// 已读全部」）
    func testAwayUnreadResetClearsCountButKeepsWatermark() {
        var counter = AwayUnreadCounter()
        _ = counter.ingest(entryIDs: ids(3), isAtBottom: true)
        _ = counter.ingest(entryIDs: ids(5), isAtBottom: false)
        XCTAssertEqual(counter.count, 2)
        counter.reset()
        XCTAssertEqual(counter.count, 0)
        XCTAssertNil(counter.displayText)
        XCTAssertEqual(counter.ingest(entryIDs: ids(5), isAtBottom: false), 2)
        // 在底一帧后水位推进：其后新增从新水位起算
        _ = counter.ingest(entryIDs: ids(5), isAtBottom: true)
        XCTAssertEqual(counter.ingest(entryIDs: ids(6), isAtBottom: false), 1)
    }

    /// 自发发送时列表为空（发送即清线程的边角）：
    /// noteOwnSend 空表只清水位不留悬空标记，其后
    /// 离底首帧仍按「只立水位」口径不虚报
    func testAwayUnreadOwnSendWithEmptyList() {
        var counter = AwayUnreadCounter()
        _ = counter.ingest(entryIDs: ids(3), isAtBottom: true)
        _ = counter.ingest(entryIDs: ids(5), isAtBottom: false)
        XCTAssertEqual(counter.count, 2)
        counter.noteOwnSend(entryIDs: [])
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(counter.ingest(entryIDs: ids(4, from: 200), isAtBottom: false), 0)
        XCTAssertEqual(counter.ingest(entryIDs: ids(5, from: 200), isAtBottom: false), 1)
    }

    /// 列表只有一条且为工具条目：连段长 1、目标是
    /// 其本身（既有单工具测是「文本＋工具」两条，
    /// 本测钉全表仅一条的最小形）
    func testLastScrollTargetSingleToolOnlyEntry() {
        let only = UUID()
        XCTAssertEqual(
            LastScrollTarget.lastScrollTargetID(
                entries: [stub(only, tool: true)]
            ),
            only
        )
    }

    // MARK: - 回底钮定版判定（BottomArrowVisibility，R2）

    func testArrowHidesWhenContentEndVisible() {
        // 症②钉测：末条已在屏——估算距底报多远都消
        XCTAssertTrue(
            BottomArrowVisibility.isNearBottom(
                distance: 260, contentEndVisible: true,
                wasNearBottom: false
            )
        )
        XCTAssertTrue(
            BottomArrowVisibility.isNearBottom(
                distance: 900, contentEndVisible: true,
                wasNearBottom: false
            )
        )
    }

    func testArrowHidesWithinSevenPoints() {
        // §176 冻结阈值：距底 ≤7 消（边界含 7）
        XCTAssertTrue(
            BottomArrowVisibility.isNearBottom(
                distance: 7, contentEndVisible: false,
                wasNearBottom: false
            )
        )
        XCTAssertTrue(
            BottomArrowVisibility.isNearBottom(
                distance: 0, contentEndVisible: false,
                wasNearBottom: false
            )
        )
    }

    func testArrowShowsAtExitDistance() {
        // 距底 ≥176 显（边界含 176；与事实同真时
        // 事实优先、此测只验事实缺位）
        XCTAssertFalse(
            BottomArrowVisibility.isNearBottom(
                distance: 176, contentEndVisible: false,
                wasNearBottom: true
            )
        )
        XCTAssertFalse(
            BottomArrowVisibility.isNearBottom(
                distance: 480, contentEndVisible: false,
                wasNearBottom: true
            )
        )
    }

    func testArrowKeepsStateInMiddleBand() {
        // 中段（7, 176）且尾条不在屏：保持上一判定，
        // 两向都不许因估算抖动翻转
        XCTAssertTrue(
            BottomArrowVisibility.isNearBottom(
                distance: 60, contentEndVisible: false,
                wasNearBottom: true
            )
        )
        XCTAssertFalse(
            BottomArrowVisibility.isNearBottom(
                distance: 60, contentEndVisible: false,
                wasNearBottom: false
            )
        )
        XCTAssertFalse(
            BottomArrowVisibility.isNearBottom(
                distance: 175.9, contentEndVisible: false,
                wasNearBottom: false
            )
        )
        XCTAssertTrue(
            BottomArrowVisibility.isNearBottom(
                distance: 7.5, contentEndVisible: false,
                wasNearBottom: true
            )
        )
    }

    // MARK: - 键盘几何快照（KeyboardGeometrySnapshot，R1）

    func testSnapshotBottomSpaceAtRest() {
        // 静息：舱底贴坞顶——留位＝坞下段＋栈高
        let snapshot = KeyboardGeometrySnapshot(
            windowHeight: 874, dockTopInWindow: 791,
            pocketHeight: 105
        )
        XCTAssertFalse(snapshot.isKeyboardUp)
        XCTAssertEqual(snapshot.bottomSpace, 874 - 791 + 105)
    }

    func testSnapshotBottomSpaceWithKeyboard() {
        // 键盘态：舱底贴键盘顶，同式换锚
        let snapshot = KeyboardGeometrySnapshot(
            keyboardTopInWindow: 518,
            animationDuration: 0.25,
            animationCurveRawValue: 7,
            windowHeight: 874, dockTopInWindow: 791,
            pocketHeight: 105
        )
        XCTAssertTrue(snapshot.isKeyboardUp)
        XCTAssertEqual(snapshot.bottomSpace, 874 - 518 + 105)
    }

    func testSnapshotBottomSpaceFollowsKeyboardTopOneToOne() {
        // 交互拖动收起：键盘顶逐帧变，留位逐帧同
        // 步——刚性同拍的算术面（症③记账分量钉测）
        var snapshot = KeyboardGeometrySnapshot(
            keyboardTopInWindow: 518,
            windowHeight: 874, dockTopInWindow: 791,
            pocketHeight: 105
        )
        let before = snapshot.bottomSpace
        snapshot.keyboardTopInWindow = 600
        XCTAssertEqual(snapshot.bottomSpace - before, -82)
        snapshot.keyboardTopInWindow = 874
        XCTAssertEqual(snapshot.bottomSpace, 105)
    }

    func testSnapshotBottomSpaceClampsOffscreenAnchor() {
        // 异常帧锚点出窗：下段高钳 0、留位只剩栈高，
        // 不出负数
        let snapshot = KeyboardGeometrySnapshot(
            keyboardTopInWindow: 920,
            windowHeight: 874, dockTopInWindow: 791,
            pocketHeight: 105
        )
        XCTAssertEqual(snapshot.bottomSpace, 105)
    }

    func testSnapshotPocketHeightChangeShiftsOneToOne() {
        // 栈高变化（回底钮行/错误行显隐）两态同式
        // 传导
        var snapshot = KeyboardGeometrySnapshot(
            windowHeight: 874, dockTopInWindow: 791,
            pocketHeight: 105
        )
        let restBefore = snapshot.bottomSpace
        snapshot.pocketHeight = 129
        XCTAssertEqual(snapshot.bottomSpace - restBefore, 24)
        snapshot.keyboardTopInWindow = 518
        let kbBefore = snapshot.bottomSpace
        snapshot.pocketHeight = 105
        XCTAssertEqual(kbBefore - snapshot.bottomSpace, 24)
    }
}
