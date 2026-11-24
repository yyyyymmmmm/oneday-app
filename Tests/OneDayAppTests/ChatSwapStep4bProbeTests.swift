import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §374.5 帧量测探针（只进测试目标）：步骤 2/3/4
/// 探针同口径（控制器装配、合成会话、生产形态
/// ＝单 section＋变更集喂入），测 §366 停滚结清
/// 拆拍/单拍两态的结清相。场景：滚动冻结期逐笔
/// 喂入攒账（整笔变更集在槽内合成：6 笔共 48 行
/// 改高＋末笔追加 12 行），停滚落写口放行后量
/// 结清全程——仪器＝落定拍布局失效施工计数＋采
/// 用高谱＋内容总高＋1ms 步进采样（匣落写与布
/// 局施工的同拍/异拍判读）＋整相墙钟，两态各
/// 跑 5 次取 best-of-5 min（§374.2/§374.3 量测
/// 口径）。断言口径：两态结清施工恰一次、终态
/// （采用高谱/内容总高/行数）与喂入逐值同；单
/// 拍态不得出现「匣已落写而失效未施工」的中
/// 间态、拆拍态必须出现（探针判别力自证）；单
/// 拍结清墙钟不劣于拆拍（拆拍含 30ms 顺延常
/// 量）。实测数入 §374.5
/// §374.7 注：滚动闸降级后本探针经覆盖口
/// （testScrollLedgerOverride＝false）钉回现
/// 行闸模式——本探针的被测对象是结清阶段机
/// 两态、不是 flush 点形态；降级形态的量测
/// 归 ChatSwapStep4dProbeTests
@MainActor
final class ChatSwapStep4bProbeTests: XCTestCase {

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

    private func assemble(singleBeat: Bool) {
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
        // 结清模式经覆盖口按本配置（拆拍态＝回退
        // 开关置假的形态）
        list.testSingleSectionOverride = true
        // §374.7：本探针量的是结清阶段两态（武装
        // 消费路径），滚动闸缺省降级后 flush 改在
        // 回调点当场应用——钉回现行闸模式保住被
        // 测对象
        list.testScrollLedgerOverride = false
        list.testSettleSingleBeatOverride = singleBeat
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
                key: "s4b-\(index)",
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

    private struct ClearingResult {
        var wall: TimeInterval
        var flushes: Int
        var intermediateSeen: Bool
        var adopted: [CGFloat]
        var contentHeight: CGFloat
        var itemCount: Int
    }

    /// 一相结清：冷开收敛→滚动冻结攒账 6 笔→停
    /// 滚放行，1ms 步进采样量到结清完成（匣落写
    /// 终行数且布局施工恰一次到达）
    private func runClearing(
        size: Int, singleBeat: Bool
    ) -> ClearingResult {
        assemble(singleBeat: singleBeat)
        let vc = controller!
        let cv = vc.collectionView
        let tracker = ChatFeedChangeTracker()
        feed(
            vc, tracker: tracker,
            rows: makeRows(count: size, heights: [:])
        )
        XCTAssertTrue(quiesce(), "装配后提供者计数须收敛稳态")
        let f0 = vc.testSettleLayoutFlushCount

        vc.scrollViewWillBeginDragging(cv)
        var heights: [Int: CGFloat] = [:]
        var total = size
        for beat in 0..<6 {
            for k in 0..<8 {
                let idx = beat * 8 + k
                heights[idx] = 120 + CGFloat(idx)
            }
            if beat == 5 { total = size + 12 }
            feed(
                vc, tracker: tracker,
                rows: makeRows(
                    count: total, heights: heights
                )
            )
        }
        XCTAssertEqual(
            vc.testAdoptedRowHeights.count, size,
            "滚动冻结期整笔喂入只记账、匣不落写"
        )
        XCTAssertEqual(
            vc.testSettleLayoutFlushCount, f0,
            "滚动冻结期不许施工布局失效"
        )

        let start = CFAbsoluteTimeGetCurrent()
        vc.scrollViewDidEndDragging(
            cv, willDecelerate: false
        )
        var intermediateSeen = false
        var doneAt: TimeInterval = -1
        let deadline = start + 10
        while CFAbsoluteTimeGetCurrent() < deadline {
            let adoptedCount =
                vc.testAdoptedRowHeights.count
            let flushCount = vc.testSettleLayoutFlushCount
            if adoptedCount == total && flushCount == f0 {
                intermediateSeen = true
            }
            if adoptedCount == total
                && flushCount == f0 + 1 {
                doneAt =
                    CFAbsoluteTimeGetCurrent() - start
                break
            }
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.001)
            )
        }
        XCTAssertGreaterThan(
            doneAt, 0, "结清须在期限内完成（施工恰一次到达）"
        )
        drain(0.35)
        windows.last?.layoutIfNeeded()
        return ClearingResult(
            wall: doneAt,
            flushes: vc.testSettleLayoutFlushCount - f0,
            intermediateSeen: intermediateSeen,
            adopted: vc.testAdoptedRowHeights,
            contentHeight: cv.contentSize.height,
            itemCount: cv.numberOfItems(inSection: 0)
        )
    }

    func testClearingWallAndEndStateSplitVsSingle() {
        let size = 300
        var splitWalls: [TimeInterval] = []
        var singleWalls: [TimeInterval] = []
        var splitEnd: ClearingResult?
        var singleEnd: ClearingResult?
        for _ in 0..<5 {
            let r = runClearing(
                size: size, singleBeat: false
            )
            splitWalls.append(r.wall)
            splitEnd = r
        }
        for _ in 0..<5 {
            let r = runClearing(
                size: size, singleBeat: true
            )
            singleWalls.append(r.wall)
            singleEnd = r
        }
        let split = splitEnd!
        let single = singleEnd!

        // 结清施工恰一次（两态，含结清后 0.35s 观察窗）
        XCTAssertEqual(
            split.flushes, 1,
            "拆拍态结清布局施工须恰一次（实测 \(split.flushes)）"
        )
        XCTAssertEqual(
            single.flushes, 1,
            "单拍态结清布局施工须恰一次（实测 \(single.flushes)）"
        )
        // 中间态判别（探针判别力自证）
        XCTAssertTrue(
            split.intermediateSeen,
            "拆拍态须观察到中间态（匣已落写而失效未施工）"
        )
        XCTAssertFalse(
            single.intermediateSeen,
            "单拍态不许出现中间态（匣落写与布局施工须同拍）"
        )
        // 终态逐值同：两态采用高谱互同且与喂入谱同
        var expected: [CGFloat] = []
        for i in 0..<(size + 12) {
            expected.append(
                i < 48 ? 120 + CGFloat(i) : 80
            )
        }
        XCTAssertEqual(
            split.adopted, expected,
            "拆拍态采用高谱须与喂入逐值同"
        )
        XCTAssertEqual(
            single.adopted, expected,
            "单拍态采用高谱须与喂入逐值同"
        )
        XCTAssertEqual(
            single.contentHeight, split.contentHeight,
            accuracy: 0.6,
            "两态内容总高须逐值同（单 \(single.contentHeight) vs 拆 \(split.contentHeight)）"
        )
        XCTAssertEqual(split.itemCount, size + 12)
        XCTAssertEqual(single.itemCount, size + 12)
        // 墙钟 best-of-5 min：单拍不劣于拆拍
        let splitMin = splitWalls.min()!
        let singleMin = singleWalls.min()!
        XCTAssertLessThanOrEqual(
            singleMin, splitMin + 0.002,
            "单拍结清墙钟不许劣于拆拍（单 "
                + "\(Int(singleMin * 1000))ms vs 拆 "
                + "\(Int(splitMin * 1000))ms）"
        )
        let fmt: ([TimeInterval]) -> String = { ws in
            ws.map { String(format: "%.1f", $0 * 1000) }
                .joined(separator: "/")
        }
        print(
            "[swap4b-probe] size=\(size)"
                + " split walls(ms)=\(fmt(splitWalls))"
                + " single walls(ms)=\(fmt(singleWalls))"
                + " min split=\(String(format: "%.1f", splitMin * 1000))ms"
                + " single=\(String(format: "%.1f", singleMin * 1000))ms"
                + " content=\(split.contentHeight)"
        )
    }
}
