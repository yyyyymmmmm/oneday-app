import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §374.4 帧量测探针（只进测试目标）：步骤 2/3
/// 探针同口径（控制器装配、合成会话、生产形态
/// ＝单 section＋变更集喂入），测 §366 时间窗
/// 合并删/留两态的流式趟。喂入按流式发布闸节
/// 拍（约 80ms/拍）逐拍尾行生长 20 拍；仪器＝
/// 落定拍布局失效施工计数（§366.4 同仪器）＋
/// 提供者重召数（单次施工宽度）＋整相墙钟。
/// 断言口径：删窗态施工频次＝喂入节拍（每拍一
/// 施工、行高采纳零攒滞），留窗态被窗闸压到约
/// 每 150ms 一次；两态单次施工宽度同量级（窗
/// 只压频次不压单宽、与 §366.4 旧口径互证）；
/// 两态终态采用高谱逐值同。实测数入 §374.4
@MainActor
final class ChatSwapStep4ProbeTests: XCTestCase {

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

    private func assemble(dropWindow: Bool) {
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
        // 生产形态：单 section 构造＋删窗覆盖口按
        // 本配置（留窗态＝回退开关置假的形态）
        list.testSingleSectionOverride = true
        list.testCoalesceWindowDropOverride = dropWindow
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
    /// S5 套件 quiesce 同式
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

    private func makeRows(
        count: Int, tailHeight: CGFloat, tailVersion: Int
    ) -> [ChatNativeRow] {
        (0..<count).map { index in
            var revision = ChatNativeRowRevision()
            revision.addText("row-\(index)")
            let isTail = index == count - 1
            if isTail {
                revision.addText("tail-v\(tailVersion)")
            }
            return ChatNativeRow(
                key: "s4-\(index)",
                entryID: nil,
                revision: revision,
                height: isTail ? tailHeight : 80,
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

    private struct StreamResult {
        var flushes: Int
        var providerDelta: Int
        var wall: TimeInterval
        var adopted: [CGFloat]
    }

    /// 一相流式：装配＋冷开收敛后，20 拍尾行生
    /// 长（每拍 +6 高＋修订变），拍间 drain 80ms
    /// 按发布闸节拍走真实时间（窗闸是墙钟口径、
    /// 不许压缩时间冒充节拍）
    private func runStreaming(
        size: Int, dropWindow: Bool
    ) -> StreamResult {
        assemble(dropWindow: dropWindow)
        let vc = controller!
        let tracker = ChatFeedChangeTracker()
        feed(
            vc, tracker: tracker,
            rows: makeRows(
                count: size, tailHeight: 80, tailVersion: 0
            )
        )
        XCTAssertTrue(quiesce(), "装配后提供者计数须收敛稳态")
        let f0 = vc.testSettleLayoutFlushCount
        let p0 = vc.testSectionProviderCallCount
        let beats = 20
        let start = CFAbsoluteTimeGetCurrent()
        for beat in 1...beats {
            feed(
                vc, tracker: tracker,
                rows: makeRows(
                    count: size,
                    tailHeight: 80 + CGFloat(beat) * 6,
                    tailVersion: beat
                )
            )
            drain(0.08)
        }
        let wall = CFAbsoluteTimeGetCurrent() - start
        // 窗末拍（留窗态）在末次记账后 150ms 内到
        // 达，给足时间再取终态
        drain(0.35)
        XCTAssertTrue(quiesce(), "流式结束后须收敛")
        return StreamResult(
            flushes: vc.testSettleLayoutFlushCount - f0,
            providerDelta: vc.testSectionProviderCallCount - p0,
            wall: wall,
            adopted: vc.testAdoptedRowHeights
        )
    }

    func testStreamingFlushCadenceWithAndWithoutWindow() {
        var lines: [String] = []
        for size in [300, 1200] {
            let dropped = runStreaming(
                size: size, dropWindow: true
            )
            let windowed = runStreaming(
                size: size, dropWindow: false
            )
            // 终态等价：两态采用高谱逐值同、且与喂
            // 入谱同（尾行 80＋20×6＝200、余行 80）
            XCTAssertEqual(
                dropped.adopted.count, size,
                "\(size) 行：采用高谱行数须与喂入同"
            )
            XCTAssertEqual(
                dropped.adopted, windowed.adopted,
                "\(size) 行：删/留窗两态终态采用高谱须逐值同"
            )
            XCTAssertEqual(
                dropped.adopted.last ?? -1, 200,
                accuracy: 0.6,
                "\(size) 行：尾行终高须＝200"
            )
            XCTAssertEqual(
                dropped.adopted.first ?? -1, 80,
                accuracy: 0.6,
                "\(size) 行：首行高须＝80"
            )
            // 频次：删窗态每拍一施工（发布闸节拍）
            XCTAssertGreaterThanOrEqual(
                dropped.flushes, 16,
                "\(size) 行：删窗态施工数须≈喂入拍数 20（实测 \(dropped.flushes)）"
            )
            XCTAssertLessThanOrEqual(
                dropped.flushes, 24,
                "\(size) 行：删窗态施工数不许超喂入拍数＋4（实测 \(dropped.flushes)）"
            )
            // 频次：留窗态被 150ms 窗闸压频（约每
            // 两拍一施工），且恒少于删窗态
            XCTAssertGreaterThanOrEqual(
                windowed.flushes, 6,
                "\(size) 行：留窗态施工数下限（实测 \(windowed.flushes)）"
            )
            XCTAssertLessThanOrEqual(
                windowed.flushes, 14,
                "\(size) 行：留窗态施工数须被窗闸压住（实测 \(windowed.flushes)）"
            )
            XCTAssertLessThan(
                windowed.flushes, dropped.flushes,
                "\(size) 行：留窗态施工数须少于删窗态"
            )
            // 单宽：两态单次施工的提供者重召同量级
            // （窗只压频次、不压单宽）
            let widthD = Double(dropped.providerDelta)
                / Double(max(dropped.flushes, 1))
            let widthW = Double(windowed.providerDelta)
                / Double(max(windowed.flushes, 1))
            XCTAssertLessThan(
                abs(widthD - widthW) / max(widthD, widthW),
                0.35,
                "\(size) 行：单次施工宽度两态须同量级（删 \(Int(widthD)) vs 留 \(Int(widthW))）"
            )
            lines.append(
                "size=\(size) dropped: flushes=\(dropped.flushes)"
                    + " width=\(Int(widthD))"
                    + " wall=\(String(format: "%.2f", dropped.wall))s"
                    + " | windowed: flushes=\(windowed.flushes)"
                    + " width=\(Int(widthW))"
                    + " wall=\(String(format: "%.2f", windowed.wall))s"
            )
        }
        print("[swap4-probe] " + lines.joined(separator: " ; "))
    }
}
