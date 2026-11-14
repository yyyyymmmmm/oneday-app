import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §259 回归：新承载首帧闪退（0.50.45 真机 .ips
/// 定案，ChatListCarrier.swift 原 L431 下标越界）。
/// CI 漏检原因＝开关默认关、开着开关的首帧路径从
/// 无测试执行过——本套三条正打该路径：非空行集
/// ＋apply 先行换行＋首帧布局 setFrame＋didScroll
/// 同步重入；断言口径＝不崩（跑到断言即证）＋施
/// 工被延迟到落定拍＋多次记账合并为一拍
@MainActor
final class ChatListCarrierReentrancyTests: XCTestCase {

    private final class Counter {
        var value = 0
    }

    private var makeViewCounter: Counter!
    private var geometryCounter: Counter!
    private var controller: ChatListCarrierViewController!
    private var handle: ChatListCarrierHandle!

    override func setUp() {
        super.setUp()
        makeViewCounter = Counter()
        geometryCounter = Counter()
        controller = ChatListCarrierViewController()
        handle = ChatListCarrierHandle()
        controller.handle = handle
        let geometry = geometryCounter!
        controller.callbacks = ChatListCarrierCallbacks(
            onScrollGeometry: { geometry.value += 1 },
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
        controller.loadViewIfNeeded()
    }

    override func tearDown() {
        controller = nil
        handle = nil
        super.tearDown()
    }

    /// 固定高 60 的占位行视图：量实与估算恒等，
    /// 量实回填不触发二次重排，落定拍数可精确断言
    private func makeRows(count: Int, keyPrefix: String)
        -> [ChatCarrierRow]
    {
        let counter = makeViewCounter!
        return (0..<count).map { index in
            ChatCarrierRow(
                key: "\(keyPrefix)-\(index)",
                entryID: UUID(),
                version: 1,
                estimatedHeight: 60,
                makeView: {
                    counter.value += 1
                    return AnyView(
                        Color.clear.frame(height: 60)
                    )
                }
            )
        }
    }

    private var testLayout: ChatCarrierLayout {
        ChatCarrierLayout(
            horizontalPadding: 20, topPadding: 16,
            bottomPadding: 8, rowSpacing: 24,
            arrowTrailing: 16, arrowSize: 44
        )
    }

    private func applyRows(
        _ rows: [ChatCarrierRow],
        topInset: CGFloat = 100, bottomInset: CGFloat = 60
    ) {
        controller.apply(
            rows: rows, layout: testLayout,
            topInset: topInset, bottomInset: bottomInset,
            bottomSpace: 200,
            keyboardAnimationDuration: 0,
            keyboardAnimationCurveRaw: 0,
            arrowView: nil
        )
    }

    /// 已托管行数＝内容视图的子视图数（每行一个
    /// UIHostingController 的视图）
    private var hostedCount: Int {
        controller.scrollView.subviews.first?.subviews.count ?? 0
    }

    private func drainRunLoop(
        seconds: TimeInterval = 0.3
    ) {
        RunLoop.main.run(
            until: Date().addingTimeInterval(seconds)
        )
    }

    /// .ips 时序正打：apply 先行换入非空行集（视
    /// 图宽为零、layoutContent 早退、帧表仍空），
    /// 随后首帧布局 setFrame＋didScroll 同步重入。
    /// 旧形态在此必陷阱（测试进程当场崩）；新形态
    /// 只记账、落定拍后托管与读数到位
    func testFirstFrameApplyThenLayoutScrollReentryDoesNotTrap() {
        applyRows(makeRows(count: 5, keyPrefix: "first"))
        // 帧表未建时同步直调 didScroll（系统 offset
        // 校正在首帧的等价复刻）：只许记账
        controller.scrollViewDidScroll(controller.scrollView)
        XCTAssertEqual(hostedCount, 0)
        XCTAssertEqual(geometryCounter.value, 0)

        controller.view.frame = CGRect(
            x: 0, y: 0, width: 390, height: 700
        )
        controller.view.layoutIfNeeded()
        // 布局期同样不许同步施工
        XCTAssertEqual(hostedCount, 0)

        drainRunLoop()
        XCTAssertEqual(hostedCount, 5)
        XCTAssertGreaterThan(geometryCounter.value, 0)
        XCTAssertEqual(makeViewCounter.value, 5)
    }

    /// 合并调度：didScroll 五连发只记账，落定拍
    /// 只执行一次（读数恰产出一次、托管不重建）
    func testDidScrollBurstCoalescesIntoSingleSettleBeat() {
        applyRows(makeRows(count: 4, keyPrefix: "burst"))
        controller.view.frame = CGRect(
            x: 0, y: 0, width: 390, height: 700
        )
        controller.view.layoutIfNeeded()
        drainRunLoop()
        XCTAssertEqual(hostedCount, 4)

        let reportsBefore = geometryCounter.value
        let makeViewsBefore = makeViewCounter.value
        for _ in 0..<5 {
            controller.scrollViewDidScroll(controller.scrollView)
        }
        // 同步段内零产出（只记账的直接证据）
        XCTAssertEqual(geometryCounter.value, reportsBefore)
        drainRunLoop()
        XCTAssertEqual(geometryCounter.value, reportsBefore + 1)
        XCTAssertEqual(makeViewCounter.value, makeViewsBefore)
        XCTAssertEqual(hostedCount, 4)
    }

    /// 行集替换后 didScroll 在帧表同拍对齐前到达：
    /// 落定拍后新行集全量托管（命令/回调消费帧表
    /// 的同拍前提在替换路径同样成立）
    func testRowsReplacedThenScrollSettlesWithNewRows() {
        applyRows(makeRows(count: 3, keyPrefix: "old"))
        controller.view.frame = CGRect(
            x: 0, y: 0, width: 390, height: 700
        )
        controller.view.layoutIfNeeded()
        drainRunLoop()
        XCTAssertEqual(hostedCount, 3)

        applyRows(makeRows(count: 6, keyPrefix: "new"))
        controller.scrollViewDidScroll(controller.scrollView)
        drainRunLoop()
        XCTAssertEqual(hostedCount, 6)
    }
}
