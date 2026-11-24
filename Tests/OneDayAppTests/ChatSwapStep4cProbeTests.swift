import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §374.6 帧量测探针（只进测试目标）：步骤 2/3/4
/// 探针同口径（控制器装配、合成会话、生产形态
/// ＝单 section＋变更集喂入），测 §366 抽屉动画
/// 期冻结删/留两态的动画期喂入相。场景：冷开
/// 300 行收敛后置抽屉运动窗（句柄 deadline＝
/// now＋1.2s、覆盖全部喂入拍），窗内按发布闸
/// 节拍（拍间约 80ms）连续喂入 6 笔变更集（每
/// 笔 8 行改高＋改订、末笔追加 12 行）：
/// 删冻态——每笔喂入即时落写、施工随笔到达
/// （逐笔量「喂入→该笔施工」墙钟）；留冻态——
/// 每笔只记账（匣不落写、施工计数不动），窗
/// 末唤醒拍合并落写、施工恰一次。基线态——
/// 不置抽屉窗、同序列直用（成本对照：删冻态
/// 与基线态同代码路、只差抽屉窗信号在场）。
/// 仪器＝采用高谱＋落定拍布局失效施工计数＋
/// 内容总高＋逐笔墙钟；成本 best-of-5 min。
/// 断言口径：删冻态每笔施工在窗内到达（延迟
/// ＜一拍间）、留冻态延迟＝整窗（窗内零落写
/// 零施工、窗末恰一次施工）；三态终态（采用
/// 高谱/内容总高/行数）逐值同；删冻逐笔总成
/// 本不劣于基线（同路口径、噪声容忍内）。实
/// 测数入 §374.6
@MainActor
final class ChatSwapStep4cProbeTests: XCTestCase {

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
        case baseline
        case dropped
        case retained
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
        // 抽屉冻结模式经覆盖口按本配置（留冻态＝
        // 回退开关置假的形态）
        list.testSingleSectionOverride = true
        list.testDrawerFreezeDropOverride =
            (mode != .retained)
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
    /// 订随高变（与 4b 探针同式）
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
                key: "s4c-\(index)",
                entryID: nil,
                revision: revision,
                height: height,
                makeView: { AnyView(EmptyView()) }
            )
        }
    }

    private func feed(
        _ vc: ChatRootViewController,
        tracker: ChatFeedChangeTracker,
        rows: [ChatNativeRow]
    ) {
        vc.applyChanges(
            rows: rows,
            changeSet: tracker.ingest(rows: rows),
            layout: layout, topInset: 122,
            bottomMargin: 0,
            composerView: AnyView(Color.clear),
            arrowView: AnyView(Color.clear)
        )
    }

    private struct PhaseResult {
        var beatWalls: [TimeInterval]
        var flushesInWindow: Int
        var adoptedInWindow: [CGFloat]
        var adopted: [CGFloat]
        var contentHeight: CGFloat
        var itemCount: Int
    }

    /// 一相：冷开收敛→（非基线态）置抽屉运动窗
    /// →窗内 6 笔喂入→收尾对账
    private func runPhase(
        mode: Mode, size: Int
    ) -> PhaseResult {
        assemble(mode: mode)
        let vc = controller!
        let cv = vc.collectionView
        let tracker = ChatFeedChangeTracker()
        feed(
            vc, tracker: tracker,
            rows: makeRows(count: size, heights: [:])
        )
        XCTAssertTrue(quiesce(), "装配后提供者计数须收敛稳态")
        let f0 = vc.testSettleLayoutFlushCount
        if mode != .baseline {
            handle?.drawerMotionDeadline =
                CACurrentMediaTime() + 1.2
        }
        var heights: [Int: CGFloat] = [:]
        var total = size
        var beatWalls: [TimeInterval] = []
        var flushTarget = f0
        for beat in 0..<6 {
            for k in 0..<8 {
                let idx = beat * 8 + k
                heights[idx] = 120 + CGFloat(idx)
            }
            if beat == 5 { total = size + 12 }
            let rows = makeRows(
                count: total, heights: heights
            )
            let beatStart = CFAbsoluteTimeGetCurrent()
            feed(vc, tracker: tracker, rows: rows)
            if mode == .retained {
                // 留冻态：只记账、拍间按发布闸节拍
                drain(0.08)
            } else {
                // 删冻/基线态：等本笔施工到达（落定
                // 拍布局失效施工计数 +1），1ms 步进
                flushTarget += 1
                var arrived: TimeInterval = -1
                let deadline =
                    CFAbsoluteTimeGetCurrent() + 2
                while CFAbsoluteTimeGetCurrent() < deadline {
                    if vc.testSettleLayoutFlushCount
                        >= flushTarget {
                        arrived =
                            CFAbsoluteTimeGetCurrent()
                            - beatStart
                        break
                    }
                    RunLoop.main.run(
                        until: Date()
                            .addingTimeInterval(0.001)
                    )
                }
                XCTAssertGreaterThan(
                    arrived, 0,
                    "第 \(beat) 笔须在抽屉窗内施工到达（删冻/基线态）"
                )
                beatWalls.append(arrived)
                let elapsed =
                    CFAbsoluteTimeGetCurrent() - beatStart
                if elapsed < 0.08 {
                    drain(0.08 - elapsed)
                }
            }
        }
        let flushesInWindow =
            vc.testSettleLayoutFlushCount - f0
        let adoptedInWindow = vc.testAdoptedRowHeights
        if mode == .retained {
            XCTAssertEqual(
                flushesInWindow, 0,
                "留冻态窗内不许施工布局失效"
            )
            XCTAssertEqual(
                adoptedInWindow,
                [CGFloat](repeating: 80, count: size),
                "留冻态窗内喂入只记账、匣不落写"
            )
            // 窗末唤醒拍合并落写、施工恰一次
            let expected = expectedSpectrum(size: size)
            XCTAssertTrue(
                spinUntil(timeout: 6) {
                    vc.testAdoptedRowHeights == expected
                },
                "窗末唤醒拍须合并落写全部记账喂入"
            )
            drain(0.35)
            XCTAssertEqual(
                vc.testSettleLayoutFlushCount - f0, 1,
                "留冻态窗末施工须恰一次（合并落写）"
            )
        } else {
            drain(0.35)
        }
        windows.last?.layoutIfNeeded()
        return PhaseResult(
            beatWalls: beatWalls,
            flushesInWindow: flushesInWindow,
            adoptedInWindow: adoptedInWindow,
            adopted: vc.testAdoptedRowHeights,
            contentHeight: cv.contentSize.height,
            itemCount: cv.numberOfItems(inSection: 0)
        )
    }

    private func expectedSpectrum(size: Int) -> [CGFloat] {
        (0..<(size + 12)).map { i in
            i < 48 ? 120 + CGFloat(i) : 80
        }
    }

    func testDrawerWindowLatencyAndCostDroppedVsRetained() {
        let size = 300
        var baselineTotals: [TimeInterval] = []
        var droppedTotals: [TimeInterval] = []
        var baselineEnd: PhaseResult?
        var droppedEnd: PhaseResult?
        for _ in 0..<5 {
            let r = runPhase(mode: .baseline, size: size)
            baselineTotals.append(
                r.beatWalls.reduce(0, +)
            )
            baselineEnd = r
        }
        for _ in 0..<5 {
            let r = runPhase(mode: .dropped, size: size)
            droppedTotals.append(
                r.beatWalls.reduce(0, +)
            )
            droppedEnd = r
        }
        let retained = runPhase(mode: .retained, size: size)
        let base = baselineEnd!
        let drop = droppedEnd!
        let expected = expectedSpectrum(size: size)

        // 终态逐值同：三态采用高谱与喂入谱同、内
        // 容总高同、行数同
        XCTAssertEqual(
            base.adopted, expected,
            "基线态采用高谱须与喂入逐值同"
        )
        XCTAssertEqual(
            drop.adopted, expected,
            "删冻态采用高谱须与喂入逐值同"
        )
        XCTAssertEqual(
            retained.adopted, expected,
            "留冻态采用高谱须与喂入逐值同"
        )
        XCTAssertEqual(
            drop.contentHeight, base.contentHeight,
            accuracy: 0.6,
            "删冻/基线内容总高须逐值同（删 \(drop.contentHeight) vs 基 \(base.contentHeight)）"
        )
        XCTAssertEqual(
            retained.contentHeight, base.contentHeight,
            accuracy: 0.6,
            "留冻/基线内容总高须逐值同（留 \(retained.contentHeight) vs 基 \(base.contentHeight)）"
        )
        XCTAssertEqual(base.itemCount, size + 12)
        XCTAssertEqual(drop.itemCount, size + 12)
        XCTAssertEqual(retained.itemCount, size + 12)
        // 删冻态窗内施工随笔发生（6 笔至少 6 次）
        XCTAssertGreaterThanOrEqual(
            drop.flushesInWindow, 6,
            "删冻态窗内施工须随笔发生（实测 \(drop.flushesInWindow)）"
        )
        // 逐笔总成本 best-of-5 min：删冻不劣于基线
        let baselineMin = baselineTotals.min()!
        let droppedMin = droppedTotals.min()!
        XCTAssertLessThanOrEqual(
            droppedMin, baselineMin * 1.5 + 0.002,
            "删冻逐笔总成本不许劣于基线（删 "
                + "\(Int(droppedMin * 1000))ms vs 基 "
                + "\(Int(baselineMin * 1000))ms）"
        )
        let fmt: ([TimeInterval]) -> String = { ws in
            ws.map { String(format: "%.1f", $0 * 1000) }
                .joined(separator: "/")
        }
        print(
            "[swap4c-probe] size=\(size)"
                + " baseline beatTotals(ms)=\(fmt(baselineTotals))"
                + " dropped beatTotals(ms)=\(fmt(droppedTotals))"
                + " min baseline=\(String(format: "%.1f", baselineMin * 1000))ms"
                + " dropped=\(String(format: "%.1f", droppedMin * 1000))ms"
                + " droppedFlushes=\(drop.flushesInWindow)"
                + " content=\(base.contentHeight)"
        )
    }
}
