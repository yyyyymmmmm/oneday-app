import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §366（流畅度 S5）钉测组：
/// ①证据钉测——在本布局（UICollectionViewCompositionalLayout、
/// §329 一行一 section、.absolute 回喂高）上，invalidateLayout
/// (with:) 携带 item 索引路的 context 不被按范围消费（提供者
/// 重召数与全量同），此即本包弃定向失效、走时间窗合并的依据；
/// ②等价钉测——流式生长全程结束后几何终态与修前逐值同；
/// ③新行为钉测——时间窗合并（窗内失效攒拍）、停滚结清拆拍
/// （数据拍先行、布局拍顺延）、抽屉运动窗冻结（窗内只记账）、
/// 参数类失效紧急直通（窗口合并的守卫回归）。
/// 拍级断言仪器＝落定拍布局失效施工计数（testSettleLayout-
/// FlushCount）＋布局匣采用高（testAdoptedRowHeights）＋帧读数。
/// §374.4 注：时间窗合并缺省已删后，③之窗合并测与参数
/// 直通测经控制器覆盖口（testCoalesceWindowDropOver-
/// ride＝false）钉回旧窗模式——窗代码在开关包裹下保
/// 留一个版本周期、其语义仍由本套把守；其余各测与窗
/// 模式无关、两模式同断言。
/// §374.5 注：停滚结清缺省改单拍结清后，③之拆拍测经
/// 覆盖口（testSettleSingleBeatOverride＝false）钉回
/// 拆拍模式——拆拍代码在开关包裹下保留一个版本周
/// 期、其语义仍由本测把守；单拍结清的新行为由新增
/// 单拍测（缺省模式）在同场景下断言同拍结清；其余
/// 各测与结清模式无关、两模式同断言。
/// §374.6 注：抽屉动画期冻结缺省已删后，③之抽屉冻
/// 结测经覆盖口（testDrawerFreezeDropOverride
/// ＝false）钉回冻结模式——冻结代码在开关包裹下
/// 保留一个版本周期、其语义仍由本测把守；删冻新
/// 行为（动画期喂入直达应用）由 ChatSwapStep4c-
/// ProbeTests 量测对账把守；其余各测与抽屉模式
/// 无关、两模式同断言。
/// §374.7 注：滚动闸缺省降级为过渡记账规则后，
/// ③之停滚结清两测（拆拍/单拍）经覆盖口（test-
/// ScrollLedgerOverride＝false）钉回现行闸模式
/// ——闸代码在开关包裹下保留一个版本周期、其
/// 武装结清阶段消费记账槽的语义仍由两测把守；
/// 降级新行为（停滚回调点当场应用）由新增记账
/// 测（缺省模式）在同场景下断言；其余各测与滚
/// 动闸模式无关、两模式同断言。
/// 装配与 ChatNativeHotfix330Tests 同式（窗口＋根 VC＋handle＋
/// carrier 回调）。基线对账（未改生产行为、仅加计数读口时）：
/// ①②绿、③之合并/拆拍/抽屉三测按设计红、参数直通绿（修前
/// 本无窗口、直通是其天然形态，本测是给新闸的回归守卫）。
@MainActor
final class ChatSettleScopeS5Tests: XCTestCase {
    private var window: UIWindow?
    private var controller: ChatRootViewController?
    private var handle: ChatNativeListHandle?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    private func assemble() {
        let win = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let root = UIViewController()
        win.rootViewController = root
        win.makeKeyAndVisible()
        let listHandle = ChatNativeListHandle()
        let list = ChatRootViewController()
        // §377（0.50.97 组版）：本套断言以 §329 逐行
        // section 构造寻址（section＝行／提供者计数），
        // 缺省翻真后经测试覆盖口钉旧构造；新构造等价
        // 由 ChatSwapStep3 五套＋生产链双形态把守
        list.testSingleSectionOverride = false
        list.handle = listHandle
        list.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        listHandle.controller = list
        root.addChild(list)
        list.view.frame = root.view.bounds
        root.view.addSubview(list.view)
        list.didMove(toParent: root)
        root.view.layoutIfNeeded()
        window = win
        controller = list
        handle = listHandle
    }

    private func apply(
        _ rows: [ChatNativeRow],
        rowSpacing: CGFloat = OneDayMetrics.spacingL,
        settleLayout: Bool = true
    ) {
        controller?.apply(
            rows: rows,
            layout: ChatNativeLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: 8,
                rowSpacing: rowSpacing,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: 122,
            bottomMargin: 0,
            composerView: AnyView(
                Rectangle()
                    .fill(Color.gray)
                    .frame(height: 54)
            ),
            arrowView: AnyView(Color.clear)
        )
        if settleLayout {
            window?.layoutIfNeeded()
        }
    }

    private func drain(_ seconds: TimeInterval) {
        let exp = expectation(
            description: "drain \(seconds)"
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window?.layoutIfNeeded()
    }

    /// 小步自旋 runloop 直到条件成立（5ms 一步）：整拍
    /// 同步执行、拍间必有 runloop 回转，跨拍中间态以
    /// 本口观察（拆拍/窗末施工的时序断言用）
    private func spinUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.005)
            )
        }
        return condition()
    }

    /// 等提供者计数稳态（连续 3 采样不变）：落定拍/落点
    /// 意图等异步施工收敛后才许取基线（与 RowHeight-
    /// Fitting 的稳态采样同式）
    private func quiesce(timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var stable = 0
        var last = -1
        while Date() < deadline {
            drain(0.25)
            window?.layoutIfNeeded()
            let now = controller?.testSectionProviderCallCount ?? -2
            if now == last {
                stable += 1
                if stable >= 3 { return true }
            } else {
                stable = 0
                last = now
            }
        }
        return false
    }

    private func textRow(
        _ key: String, text: String,
        height: CGFloat = 60
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: ChatNativeRowRevision(
                parts: [.text(text)]
            ),
            height: height,
            makeView: {
                AnyView(
                    Text(text)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                )
            }
        )
    }

    private func makeRows(
        count: Int, height: CGFloat = 60
    ) -> [ChatNativeRow] {
        (0..<count).map {
            textRow("k\($0)", text: "row \($0)", height: height)
        }
    }

    private func frameHeight(
        _ vc: ChatRootViewController, section: Int
    ) -> CGFloat {
        window?.layoutIfNeeded()
        return vc.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 0, section: section)
        )?.frame.height ?? -1
    }

    // MARK: - ① 证据钉测：定向失效在本布局不成立

    /// 三段实测（60 行、section＝行）：A 全量 invalidate-
    /// Layout() 的提供者重召数；B 原始定向（context 只带
    /// section 30 的 item 路）重召数——须与 A 同量级（不
    /// 按范围消费的实证）；C 端到端（生产 apply 改第 30
    /// 行高、匣已同步落写后定向失效该行）——帧高/总高须
    /// 即刻正确（机制正确、只是范围不成立）。
    func testTargetedInvalidationIsNotScopedOnThisLayout()
        throws
    {
        assemble()
        let vc = try XCTUnwrap(controller)
        apply(makeRows(count: 60))
        XCTAssertTrue(
            quiesce(), "装配后提供者计数须收敛稳态"
        )
        let cv = vc.collectionView
        let layout = cv.collectionViewLayout

        let a0 = vc.testSectionProviderCallCount
        layout.invalidateLayout()
        window?.layoutIfNeeded()
        let fullDelta =
            vc.testSectionProviderCallCount - a0
        XCTAssertEqual(
            fullDelta, 60,
            "全量失效须重召全部 60 个 section 提供者"
        )

        XCTAssertTrue(quiesce(), "全量失效后须再收敛")

        let b0 = vc.testSectionProviderCallCount
        let ctx = UICollectionViewLayoutInvalidationContext()
        ctx.invalidateItems(
            at: [IndexPath(item: 0, section: 30)]
        )
        layout.invalidateLayout(with: ctx)
        window?.layoutIfNeeded()
        let targetedDelta =
            vc.testSectionProviderCallCount - b0
        XCTAssertGreaterThan(
            targetedDelta, fullDelta / 2,
            "定向 context 在本布局退化为全量重召（实测 "
                + "targeted=\(targetedDelta) full=\(fullDelta)"
                + "）——§366 弃定向走时间窗合并的依据"
        )

        var rowsC = makeRows(count: 60)
        rowsC[30] = textRow(
            "k30", text: "row 30", height: 150
        )
        let sizeBefore = cv.contentSize.height
        apply(rowsC, settleLayout: false)
        let ctxC = UICollectionViewLayoutInvalidationContext()
        ctxC.invalidateItems(
            at: [IndexPath(item: 0, section: 30)]
        )
        layout.invalidateLayout(with: ctxC)
        window?.layoutIfNeeded()
        XCTAssertEqual(
            frameHeight(vc, section: 30), 150, accuracy: 0.6,
            "定向失效后变化行帧高须即刻反映匣内新高"
        )
        XCTAssertEqual(
            cv.contentSize.height - sizeBefore, 90,
            accuracy: 0.6,
            "定向失效后内容总高须即刻反映 +90"
        )
        drain(0.5)
    }

    // MARK: - ② 等价钉测：流式生长终态

    /// 模拟流式：尾行逐拍长高＋间歇追加新行，每步给足
    /// 收敛时间；终态须与逐值预期全等（采用高谱、内容
    /// 总高、末行帧、落点距离）——修前修后同断言。
    func testStreamingGrowthEndStateEquivalence() throws {
        assemble()
        let vc = try XCTUnwrap(controller)
        var rows = makeRows(count: 30)
        apply(rows)
        XCTAssertTrue(quiesce(), "装配后须收敛")

        var expectedHeights = rows.map(\.height)
        for step in 0..<10 {
            // 尾行长高（流行高变化主形态）
            let tail = rows.count - 1
            let grown = expectedHeights[tail] + 12
            expectedHeights[tail] = grown
            rows[tail] = textRow(
                "k\(tail)", text: "row \(tail)",
                height: grown
            )
            // 每 3 步追加一行（新行到达）
            if step % 3 == 2 {
                let idx = rows.count
                rows.append(
                    textRow(
                        "k\(idx)", text: "row \(idx)",
                        height: 60
                    )
                )
                expectedHeights.append(60)
            }
            apply(rows)
            drain(0.3)
        }
        XCTAssertTrue(quiesce(), "流式结束后须收敛")

        XCTAssertEqual(
            vc.testAdoptedRowHeights, expectedHeights,
            "采用高谱须与喂入逐值同"
        )
        let n = expectedHeights.count
        let expectedContent =
            expectedHeights.reduce(0, +)
            + OneDayMetrics.spacingM
            + CGFloat(n - 1) * OneDayMetrics.spacingL + 8
        XCTAssertEqual(
            vc.collectionView.contentSize.height,
            expectedContent, accuracy: 0.6,
            "内容总高须＝高谱和＋首行顶距＋行距＋底距"
        )
        XCTAssertEqual(
            frameHeight(vc, section: n - 1),
            expectedHeights[n - 1], accuracy: 0.6,
            "末行帧高须与喂入同"
        )
        // 注：跟随钉底（落点距离）归 ChatView 跟随链
        // ——裸装配无此环（基线实测距离随生长累积、
        // 非本面几何等价的判据），由 BottomFollow 套
        // 件在其装配形态下覆盖，本测不冒领
    }

    // MARK: - ③ 新行为：时间窗合并

    /// 窗内连续行高变化只许攒拍：首改立即施工（窗钟起
    /// 点），其后同窗两改的落定拍不施工布局失效（帧高
    /// 采纳滞后为证），窗末合并一拍全部采纳。
    func testHeightChangeInvalidationsCoalesceWithinWindow()
        throws
    {
        assemble()
        let vc = try XCTUnwrap(controller)
        // §374.4：本测钉旧窗模式（窗语义把守）
        vc.testCoalesceWindowDropOverride = false
        apply(makeRows(count: 40))
        XCTAssertTrue(quiesce(), "装配后须收敛")
        let f0 = vc.testSettleLayoutFlushCount

        // 首改：窗钟未起，落定拍立即施工
        var rows = makeRows(count: 40)
        rows[5] = textRow("k5", text: "row 5", height: 90)
        apply(rows)
        XCTAssertTrue(
            spinUntil {
                vc.testSettleLayoutFlushCount == f0 + 1
            },
            "首改须被落定拍施工一次布局失效"
        )
        XCTAssertEqual(
            frameHeight(vc, section: 5), 90, accuracy: 0.6
        )

        // 同窗两改（同步连发＋短 drain，恒在窗内）
        rows[6] = textRow("k6", text: "row 6", height: 95)
        apply(rows)
        rows[7] = textRow("k7", text: "row 7", height: 100)
        apply(rows)
        drain(0.05)
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0 + 1,
            "窗内失效须攒拍、落定拍不许再施工"
        )
        XCTAssertEqual(
            frameHeight(vc, section: 6), 60, accuracy: 0.6,
            "窗内行高采纳须滞后（帧仍旧高）"
        )

        // 窗末合并一拍：两改一并采纳
        XCTAssertTrue(
            spinUntil(timeout: 3) {
                vc.testSettleLayoutFlushCount == f0 + 2
            },
            "窗末须合并施工恰一次"
        )
        XCTAssertEqual(
            frameHeight(vc, section: 6), 95, accuracy: 0.6
        )
        XCTAssertEqual(
            frameHeight(vc, section: 7), 100, accuracy: 0.6
        )
        drain(0.3)
    }

    // MARK: - ③ 新行为：停滚结清拆拍

    /// 滚动冻结期整笔喂入只记账；停滚后结清拆两拍——
    /// 数据拍先落匣（行集/采用高更新）而布局失效尚未
    /// 施工，布局拍随后恰施工一次且帧采纳新高。
    func testScrollClearingSplitsIntoTwoBeats() throws {
        assemble()
        let vc = try XCTUnwrap(controller)
        let cv = vc.collectionView
        // §374.5：本测钉拆拍模式（拆拍语义把守）——
        // 缺省已改单拍结清，拆拍在开关包裹下保留一
        // 个版本周期、经覆盖口置假在本测复活
        // §374.7：滚动闸缺省已降级（停滚回调点当场
        // 应用记账槽），本测的武装阶段消费路径须同
        // 钉回现行闸模式（下行覆盖口）
        vc.testScrollLedgerOverride = false
        vc.testSettleSingleBeatOverride = false
        apply(makeRows(count: 40))
        XCTAssertTrue(quiesce(), "装配后须收敛")
        let f0 = vc.testSettleLayoutFlushCount

        vc.scrollViewWillBeginDragging(cv)
        var rows = makeRows(count: 40)
        rows[3] = textRow("k3", text: "row 3", height: 140)
        rows.append(textRow("k40", text: "row 40"))
        rows.append(textRow("k41", text: "row 41"))
        apply(rows)
        drain(0.15)
        XCTAssertEqual(
            vc.testAdoptedRowHeights.count, 40,
            "滚动冻结期整笔喂入只记账、匣不落写"
        )
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0,
            "滚动冻结期不许施工布局失效"
        )

        vc.scrollViewDidEndDragging(
            cv, willDecelerate: false
        )
        // 数据拍：匣先落写、布局失效尚未施工（同拍形态
        // 下本断言不可能成立——拆拍的判别点）
        XCTAssertTrue(
            spinUntil(timeout: 3) {
                vc.testAdoptedRowHeights.count == 42
            },
            "停滚后数据拍须先落写整笔喂入"
        )
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0,
            "数据拍不得同拍施工布局失效（须拆拍）"
        )
        // 布局拍：恰一次施工、帧采纳新高与新行
        XCTAssertTrue(
            spinUntil(timeout: 3) {
                vc.testSettleLayoutFlushCount == f0 + 1
            },
            "布局拍须随后施工恰一次"
        )
        XCTAssertEqual(
            frameHeight(vc, section: 3), 140, accuracy: 0.6
        )
        XCTAssertEqual(cv.numberOfSections, 42)
        drain(0.3)
    }

    // MARK: - ③ 新行为（§374.5）：停滚结清单拍结清

    /// 缺省单拍结清（与拆拍测同场景）：滚动冻结期整
    /// 笔喂入只记账；停滚后落定拍一拍结清——匣落写
    /// 被观察到的同一拍布局失效必已施工（拆拍形态
    /// 下本断言不可能成立——单拍的判别点），帧采
    /// 纳新高与新行、结清后不再有第二拍补施工。
    func testScrollClearingSettlesInSingleBeat() throws {
        assemble()
        let vc = try XCTUnwrap(controller)
        let cv = vc.collectionView
        // §374.5 缺省口径（单拍结清）的把守测；
        // §374.7：滚动闸缺省已降级（停滚回调点当
        // 场应用记账槽），本测断言的「武装阶段 2 落
        // 定拍同拍结清」路径须钉回现行闸模式（结
        // 清模式覆盖口仍不设、认缺省单拍）
        vc.testScrollLedgerOverride = false
        apply(makeRows(count: 40))
        XCTAssertTrue(quiesce(), "装配后须收敛")
        let f0 = vc.testSettleLayoutFlushCount

        vc.scrollViewWillBeginDragging(cv)
        var rows = makeRows(count: 40)
        rows[3] = textRow("k3", text: "row 3", height: 140)
        rows.append(textRow("k40", text: "row 40"))
        rows.append(textRow("k41", text: "row 41"))
        apply(rows)
        drain(0.15)
        XCTAssertEqual(
            vc.testAdoptedRowHeights.count, 40,
            "滚动冻结期整笔喂入只记账、匣不落写"
        )
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0,
            "滚动冻结期不许施工布局失效"
        )

        vc.scrollViewDidEndDragging(
            cv, willDecelerate: false
        )
        // 单拍判别点：匣落写（42 行）被观察到时布局
        // 失效必须已同拍施工——两读数同拍跳变、无
        // 「匣已落写而失效未施工」的中间态
        XCTAssertTrue(
            spinUntil(timeout: 3) {
                vc.testAdoptedRowHeights.count == 42
            },
            "停滚后落定拍须落写整笔喂入"
        )
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0 + 1,
            "单拍结清：匣落写同拍布局失效须已施工（不许顺延下一拍）"
        )
        XCTAssertEqual(
            frameHeight(vc, section: 3), 140, accuracy: 0.6
        )
        XCTAssertEqual(cv.numberOfSections, 42)
        drain(0.3)
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0 + 1,
            "结清后不许再有第二拍补施工"
        )
    }

    // MARK: - ③ 新行为（§374.7）：滚动闸记账降级

    /// 缺省记账降级（与单拍测同场景）：滚动期整笔
    /// 喂入只记账；停滚回调返回时记账喂入必须已经
    /// 落写（回调点当场应用——武装落定拍消费形态
    /// 下回调返回时匣不可能已落写，本测的判别
    /// 点）；其后落定拍恰一次施工布局失效、帧采
    /// 纳新高与新行、再无第二拍补施工。回调点只
    /// 应用数据——布局失效施工仍归落定拍唯一施
    /// 工口（§325.2 不变量不因降级而动）
    func testScrollLedgerFlushAppliesAtScrollEndCallback() throws {
        assemble()
        let vc = try XCTUnwrap(controller)
        let cv = vc.collectionView
        // 缺省模式（不设覆盖口）：记账降级为现行口径
        apply(makeRows(count: 40))
        XCTAssertTrue(quiesce(), "装配后须收敛")
        let f0 = vc.testSettleLayoutFlushCount

        vc.scrollViewWillBeginDragging(cv)
        var rows = makeRows(count: 40)
        rows[3] = textRow("k3", text: "row 3", height: 140)
        rows.append(textRow("k40", text: "row 40"))
        rows.append(textRow("k41", text: "row 41"))
        apply(rows)
        drain(0.15)
        XCTAssertEqual(
            vc.testAdoptedRowHeights.count, 40,
            "滚动记账期整笔喂入只记账、匣不落写"
        )
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0,
            "滚动记账期不许施工布局失效"
        )

        vc.scrollViewDidEndDragging(
            cv, willDecelerate: false
        )
        // 回调点判别点：回调返回的此刻记账喂入须已
        // 落写（不许等落定拍消费）
        XCTAssertEqual(
            vc.testAdoptedRowHeights.count, 42,
            "停滚回调返回时记账喂入须已当场应用"
        )
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0,
            "回调点只应用数据、布局失效施工仍归落定拍"
        )
        // 落定拍：恰一次施工、帧采纳新高与新行
        XCTAssertTrue(
            spinUntil(timeout: 3) {
                vc.testSettleLayoutFlushCount == f0 + 1
            },
            "落定拍须随后施工恰一次"
        )
        XCTAssertEqual(
            frameHeight(vc, section: 3), 140, accuracy: 0.6
        )
        XCTAssertEqual(cv.numberOfSections, 42)
        drain(0.3)
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0 + 1,
            "结清后不许再有第二拍补施工"
        )
    }

    // MARK: - ③ 新行为：抽屉运动窗冻结

    /// 抽屉运动窗内：喂入只记账（匣不落写）、落定拍不
    /// 施工；窗末唤醒一拍合并落写＋施工（且不受时间窗
    /// 合并拖延——本测窗长 0.8s 远超合并窗，唤醒拍到
    /// 达即施工完毕为据）。
    func testDrawerMotionFreezesSettleConstruction() throws {
        assemble()
        let vc = try XCTUnwrap(controller)
        // §374.6：本测钉回退模式（冻结语义把守）
        vc.testDrawerFreezeDropOverride = false
        apply(makeRows(count: 40))
        XCTAssertTrue(quiesce(), "装配后须收敛")
        let f0 = vc.testSettleLayoutFlushCount

        handle?.drawerMotionDeadline =
            CACurrentMediaTime() + 0.8
        var rows = makeRows(count: 40)
        rows[2] = textRow("k2", text: "row 2", height: 130)
        apply(rows)
        drain(0.25)
        XCTAssertEqual(
            vc.testAdoptedRowHeights[2], 60,
            "抽屉窗内喂入只记账、匣不落写"
        )
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0,
            "抽屉窗内不许施工布局失效"
        )

        XCTAssertTrue(
            spinUntil(timeout: 3) {
                vc.testAdoptedRowHeights[2] == 130
            },
            "窗末唤醒拍须合并落写记账喂入"
        )
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0 + 1,
            "窗末唤醒拍须施工恰一次布局失效"
        )
        XCTAssertEqual(
            frameHeight(vc, section: 2), 130, accuracy: 0.6
        )
        handle?.drawerMotionDeadline = 0
        drain(0.3)
    }

    // MARK: - ③ 守卫回归：参数类失效紧急直通

    /// 布局参数变化（行距）属全几何变更：即便在时间窗
    /// 合并窗内，落定拍也须立即施工、不许攒拍。
    func testParamsChangeInvalidationBypassesWindow() throws {
        assemble()
        let vc = try XCTUnwrap(controller)
        // §374.4：本测钉旧窗模式（绕窗语义把守）
        vc.testCoalesceWindowDropOverride = false
        apply(makeRows(count: 40))
        XCTAssertTrue(quiesce(), "装配后须收敛")
        let f0 = vc.testSettleLayoutFlushCount

        // 先起窗钟（一次行高改＋施工）
        var rows = makeRows(count: 40)
        rows[5] = textRow("k5", text: "row 5", height: 90)
        apply(rows)
        XCTAssertTrue(
            spinUntil {
                vc.testSettleLayoutFlushCount == f0 + 1
            },
            "首改须施工（窗钟起点）"
        )
        // 窗内改行距：须立即施工
        apply(
            rows, rowSpacing: OneDayMetrics.spacingL + 16
        )
        XCTAssertTrue(
            spinUntil(timeout: 2) {
                vc.testSettleLayoutFlushCount == f0 + 2
            },
            "参数类失效不许等窗、须立即施工"
        )
        drain(0.3)
    }
}
