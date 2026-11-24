import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §374.7 帧量测探针（只进测试目标）：步骤 2/3/4
/// 探针同口径（控制器装配、合成会话、生产形态
/// ＝单 section＋变更集喂入），测滚动闸三态——
/// 现行闸（回退形态：停滚回调武装结清阶段、自
/// 排落定拍消费记账槽，结清模式认②的单拍缺省）
/// ／记账降级（缺省形态：记账槽在停滚回调点当
/// 场应用、余链归随后一落定拍）／直达参照（不
/// 进滚动态、同序列逐笔即时应用——终局裁决的
/// 数据面，只测不落码）。场景：冷开 300 行收
/// 敛后进入滚动态，按发布闸节拍（拍间约 80ms）
/// 连喂 6 笔变更集（每笔 8 行改高＋改订、末笔
/// 追加 12 行），停滚后量结清全程。仪器＝快照
/// 施工计数＋落定拍布局失效施工计数＋采用高谱
/// ＋内容总高＋逐笔喂入耗时＋1ms 步进采样；墙
/// 钟 best-of-5 min（§374.2/§374.3 量测口径）。
/// 断言口径：两闸形态滚动期列表侧工作量为零
/// （快照施工 0、布局施工 0、匣不落写）；记账
/// 态数据在停滚回调返回时已落写（判别点）、现
/// 行闸态未落写（须等武装拍）；两闸形态停滚后
/// 布局施工恰一次；三态终态（采用高谱/内容总
/// 高/行数）逐值同。实测数入 §374.7
@MainActor
final class ChatSwapStep4dProbeTests: XCTestCase {

    private let layout = ChatNativeLayout(
        horizontalPadding: OneDayMetrics.pageGutter,
        topPadding: OneDayMetrics.spacingM,
        bottomPadding: 8,
        rowSpacing: OneDayMetrics.spacingL,
        arrowTrailing: OneDayMetrics.spacingM,
        arrowGapAboveComposer: 8,
        arrowSize: OneDayMetrics.minTapTarget
    )
    private var windows: [UIWindow] = []
    private var controller: ChatRootViewController?
    private var handle: ChatNativeListHandle?

    override func tearDown() {
        for window in windows { window.isHidden = true }
        windows = []
        controller = nil
        handle = nil
        super.tearDown()
    }

    private enum Mode {
        case gate
        case ledger
        case direct
    }

    private func assemble(mode: Mode) {
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        windows.append(window)
        let listHandle = ChatNativeListHandle()
        let list = ChatRootViewController()
        list.handle = listHandle
        list.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        listHandle.controller = list
        // 生产形态：单 section 构造＋变更集喂入；
        // 闸形态经覆盖口按本配置（现行闸态＝降级
        // 开关置假＋结清认②单拍缺省）
        list.testSingleSectionOverride = true
        switch mode {
        case .gate:
            list.testScrollLedgerOverride = false
            list.testSettleSingleBeatOverride = true
        case .ledger:
            list.testScrollLedgerOverride = true
        case .direct:
            // 不进滚动态、覆盖口无涉（冻结判据不达）
            list.testScrollLedgerOverride = true
        }
        root.addChild(list)
        list.view.frame = root.view.bounds
        root.view.addSubview(list.view)
        list.didMove(toParent: root)
        root.view.layoutIfNeeded()
        controller = list
        handle = listHandle
    }

    private func drain(_ seconds: TimeInterval) {
        let exp = expectation(
            description: "drain \(seconds)"
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
    }

    /// 等提供者计数稳态（连续 3 采样不变），与
    /// S5/步骤 4 探针 quiesce 同式
    private func quiesce(timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var stable = 0
        var last = -1
        while Date() < deadline {
            drain(0.25)
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

    /// 合成行：缺省高 80；heights 命中行改高且修
    /// 订随高变（改高与改订同达，与生产结清账目
    /// 的混合形态同构）
    private func makeRows(
        count: Int, heights: [Int: CGFloat]
    ) -> [ChatNativeRow] {
        (0..<count).map { index in
            var revision = ChatNativeRowRevision()
            revision.addText("row-\(index)")
            let height = heights[index] ?? 80
            if heights[index] != nil {
                revision.addText("h-\(Int(height))")
            }
            return ChatNativeRow(
                key: "s4d-\(index)",
                entryID: nil,
                revision: revision,
                height: height,
                makeView: { AnyView(EmptyView()) }
            )
        }
    }

    @discardableResult
    private func feed(
        _ vc: ChatRootViewController,
        tracker: ChatFeedChangeTracker,
        rows: [ChatNativeRow]
    ) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        vc.applyChanges(
            rows: rows,
            changeSet: tracker.ingest(rows: rows),
            layout: layout, topInset: 122,
            bottomMargin: 0,
            composerView: AnyView(Color.clear),
            arrowView: AnyView(Color.clear)
        )
        return CFAbsoluteTimeGetCurrent() - start
    }

    private struct PhaseResult {
        /// 喂入期快照施工增量（闸形态须 0、直达
        /// 态＝逐笔各一次）
        var scrollApplies: Int
        /// 全相布局失效施工增量（闸形态须恰 1）
        var totalFlushes: Int
        /// 停滚回调返回时数据已落写（记账态判别
        /// 点；直达态无停滚点、恒真）
        var landedAtCallback: Bool
        /// 停滚→结清完成墙钟（数据落写且布局施
        /// 工恰一次到达）；直达态为 -1（无结清相）
        var clearingWall: TimeInterval
        /// 喂入期逐笔耗时（闸形态＝记账成本、直
        /// 达态＝逐笔应用成本）
        var feedDurations: [TimeInterval]
        var adopted: [CGFloat]
        var contentHeight: CGFloat
        var itemCount: Int
    }

    /// 一相：冷开收敛→（闸形态进滚动态）连喂 6
    /// 笔→停滚结清采样
    private func runPhase(mode: Mode) -> PhaseResult {
        assemble(mode: mode)
        let vc = controller!
        let cv = vc.collectionView
        let tracker = ChatFeedChangeTracker()
        feed(
            vc, tracker: tracker,
            rows: makeRows(count: 300, heights: [:])
        )
        XCTAssertTrue(quiesce(), "装配后提供者计数须收敛稳态")
        let f0 = vc.testSettleLayoutFlushCount
        let a0 = vc.testSnapshotApplyCount

        if mode != .direct {
            vc.scrollViewWillBeginDragging(cv)
        }
        var heights: [Int: CGFloat] = [:]
        var total = 300
        var durations: [TimeInterval] = []
        for beat in 0..<6 {
            for k in 0..<8 {
                let idx = beat * 8 + k
                heights[idx] = 120 + CGFloat(idx)
            }
            if beat == 5 { total = 312 }
            durations.append(feed(
                vc, tracker: tracker,
                rows: makeRows(
                    count: total, heights: heights
                )
            ))
            drain(0.08)
        }
        let scrollApplies =
            vc.testSnapshotApplyCount - a0
        if mode != .direct {
            XCTAssertEqual(
                vc.testAdoptedRowHeights.count, 300,
                "滚动记账期整笔喂入只记账、匣不落写"
            )
            XCTAssertEqual(
                vc.testSettleLayoutFlushCount, f0,
                "滚动记账期不许施工布局失效"
            )
        }

        var landedAtCallback = false
        var clearingWall: TimeInterval = -1
        if mode == .direct {
            landedAtCallback =
                vc.testAdoptedRowHeights.count == total
        } else {
            let start = CFAbsoluteTimeGetCurrent()
            vc.scrollViewDidEndDragging(
                cv, willDecelerate: false
            )
            landedAtCallback =
                vc.testAdoptedRowHeights.count == total
            let deadline = start + 10
            while CFAbsoluteTimeGetCurrent() < deadline {
                if vc.testAdoptedRowHeights.count == total
                    && vc.testSettleLayoutFlushCount
                        == f0 + 1 {
                    clearingWall =
                        CFAbsoluteTimeGetCurrent() - start
                    break
                }
                RunLoop.main.run(
                    until: Date().addingTimeInterval(0.001)
                )
            }
            XCTAssertGreaterThan(
                clearingWall, 0,
                "结清须在期限内完成（施工恰一次到达）"
            )
        }
        drain(0.35)
        windows.last?.layoutIfNeeded()
        return PhaseResult(
            scrollApplies: scrollApplies,
            totalFlushes:
                vc.testSettleLayoutFlushCount - f0,
            landedAtCallback: landedAtCallback,
            clearingWall: clearingWall,
            feedDurations: durations,
            adopted: vc.testAdoptedRowHeights,
            contentHeight: cv.contentSize.height,
            itemCount: cv.numberOfItems(inSection: 0)
        )
    }

    func testScrollGateThreeModeLedgerProbe() {
        var gate: [PhaseResult] = []
        var ledger: [PhaseResult] = []
        var direct: [PhaseResult] = []
        for _ in 0..<5 {
            gate.append(runPhase(mode: .gate))
            ledger.append(runPhase(mode: .ledger))
            direct.append(runPhase(mode: .direct))
        }
        // 闸形态纪律（每轮同断言）
        for r in gate + ledger {
            XCTAssertEqual(
                r.scrollApplies, 0,
                "闸形态滚动期快照施工须为零（只记账）"
            )
            XCTAssertEqual(
                r.totalFlushes, 1,
                "闸形态停滚后布局施工须恰一次"
            )
            XCTAssertEqual(r.itemCount, 312)
        }
        for r in gate {
            XCTAssertFalse(
                r.landedAtCallback,
                "现行闸态：停滚回调返回时数据不许已落写（须等武装拍消费）"
            )
        }
        for r in ledger {
            XCTAssertTrue(
                r.landedAtCallback,
                "记账态判别点：停滚回调返回时记账喂入须已当场应用"
            )
        }
        for r in direct {
            XCTAssertEqual(
                r.scrollApplies, 6,
                "直达参照：6 笔喂入须逐笔各应用一次"
            )
            XCTAssertTrue(r.landedAtCallback)
        }
        // 终态逐值同（三态互证）
        let reference = ledger[0]
        for r in gate + ledger + direct {
            XCTAssertEqual(
                r.adopted, reference.adopted,
                "三态采用高谱须逐值同"
            )
            XCTAssertEqual(
                r.contentHeight, reference.contentHeight,
                accuracy: 0.01,
                "三态内容总高须同值"
            )
            XCTAssertEqual(r.itemCount, 312)
        }
        // 量测读数（best-of-5 min；判读入 §374.7）
        func ms(_ v: TimeInterval) -> String {
            String(format: "%.1f", v * 1000)
        }
        let gateWall = gate.map(\.clearingWall).min()!
        let ledgerWall = ledger.map(\.clearingWall).min()!
        let directFeedMax = direct
            .flatMap(\.feedDurations).max()!
        let directFeedSum = direct.map {
            $0.feedDurations.reduce(0, +)
        }.min()!
        let ledgerFeedSum = ledger.map {
            $0.feedDurations.reduce(0, +)
        }.min()!
        print(
            "S4D-PROBE gateWallMs=\(ms(gateWall)) "
                + "ledgerWallMs=\(ms(ledgerWall)) "
                + "directFeedMaxMs=\(ms(directFeedMax)) "
                + "directFeedSumMs=\(ms(directFeedSum)) "
                + "ledgerFeedSumMs=\(ms(ledgerFeedSum)) "
                + "directFlushes=\(direct[0].totalFlushes) "
                + "contentHeight=\(reference.contentHeight)"
        )
    }
}
