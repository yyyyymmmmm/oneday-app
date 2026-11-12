import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 抽屉容器（§156）真机打不开的复现/回归组（热修
/// 诊断用）：控制器裸装进窗口，只验开合呈现位移；
/// 干扰组分别复现「动画中布局往返」与「动画中宿主
/// 根视图重赋值」两种生产环境干扰，定位动画被谁摁死。
@MainActor
final class DrawerContainerControllerTests: XCTestCase {
    private var window: UIWindow!
    private var controller: DrawerContainerController!

    override func setUp() async throws {
        try await super.setUp()
        controller = DrawerContainerController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    override func tearDown() async throws {
        window.isHidden = true
        window = nil
        controller = nil
        try await super.tearDown()
    }

    /// 前景层＝容器 view 的第二个子视图（底层抽屉宿
    /// 主第一、前景第二，viewDidLoad 装配序）；位移只
    /// 读它的 transform.tx（呈现口唯一写口）
    private var foregroundTx: CGFloat {
        let subviews = controller.view.subviews
        guard subviews.count >= 2 else { return -1 }
        return subviews[1].transform.tx
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    func testTravelEstablishedFromLayout() {
        XCTAssertEqual(controller.travel, min(393 * 0.79, 400), accuracy: 0.5)
    }

    func testInstantOpenAppliesFullTravel() {
        controller.setDrawer(true, animated: false)
        XCTAssertTrue(controller.semanticPresented)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 0.5)
    }

    /// 裸动画：无任何干扰，弹簧动画必须自己走完到
    /// travel（真机症状是停在约 9.5% travel）
    func testAnimatedOpenCompletesWithoutInterference() {
        controller.setDrawer(true, animated: true)
        spinRunLoop(seconds: 2.0)
        XCTAssertTrue(controller.semanticPresented)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
    }

    /// 干扰甲：动画途中反复触发容器布局往返（生产
    /// 里 SwiftUI 桥更新/宿主重排可引发）
    func testAnimatedOpenSurvivesLayoutPasses() {
        controller.setDrawer(true, animated: true)
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            spinRunLoop(seconds: 0.05)
        }
        spinRunLoop(seconds: 1.0)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
    }

    /// 干扰乙：动画途中反复重赋值两个宿主的根视图
    /// （生产里桥 apply() 每次 ContentView 求值都做）
    func testAnimatedOpenSurvivesRootViewChurn() {
        controller.drawerBuilder = { _ in AnyView(Text("drawer")) }
        controller.setDrawer(true, animated: true)
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline {
            controller.contentRoot = AnyView(Text("content"))
            spinRunLoop(seconds: 0.05)
        }
        spinRunLoop(seconds: 1.0)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
    }

    func testAnimatedCloseReturnsToZero() {
        controller.setDrawer(true, animated: false)
        controller.setDrawer(false, animated: true)
        spinRunLoop(seconds: 2.0)
        XCTAssertFalse(controller.semanticPresented)
        XCTAssertEqual(foregroundTx, 0, accuracy: 1.0)
    }

    /// 直接测生产折叠件的 TupleView：五条导航必须同列，
    /// 不能被 GridRow 拆成五个 cell。不能只验壳层 tx。
    func testExpandedNavigationChildrenStayInOneColumn() throws {
        let frames = DrawerLayoutMeasurements()
        let root = DrawerCollapsibleContent(collapsed: false) {
            measuredDrawerRow(0)
            measuredDrawerRow(1)
            measuredDrawerRow(2)
            measuredDrawerRow(3)
            measuredDrawerRow(4)
        }
        .frame(width: 310, alignment: .leading)
        .coordinateSpace(name: "drawer-layout-test")
        .onPreferenceChange(DrawerRowFramesKey.self) { value in
            Task { @MainActor in frames.rows = value }
        }
        let host = UIHostingController(rootView: root)
        window.rootViewController = host
        host.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.5)
        XCTAssertEqual(frames.rows.count, 5)
        for index in 0..<5 {
            let rect = try XCTUnwrap(frames.rows[index])
            XCTAssertEqual(rect.minX, 0, accuracy: 1)
            XCTAssertEqual(rect.width, 310, accuracy: 1)
            if index > 0 {
                let previous = try XCTUnwrap(frames.rows[index - 1])
                XCTAssertGreaterThanOrEqual(rect.minY, previous.maxY - 1)
            }
        }
    }

    func testCollapsedNavigationConsumesNoHeight() {
        let host = UIHostingController(rootView:
            DrawerCollapsibleContent(collapsed: true) {
                measuredDrawerRow(0)
                measuredDrawerRow(1)
            }
        )
        let size = host.sizeThatFits(in: CGSize(width: 310, height: 700))
        XCTAssertEqual(size.height, 0, accuracy: 1)
    }

    /// ForEach 多条旁聊也需要堆叠，不只修写死的导航行。
    func testExpandedThreadRowsAccumulateHeightAtNarrowWidth() {
        let host = UIHostingController(rootView:
            DrawerCollapsibleContent(collapsed: false) {
                ForEach(0..<6) { index in measuredDrawerRow(index) }
            }
        )
        let size = host.sizeThatFits(in: CGSize(width: 253, height: 700))
        XCTAssertLessThanOrEqual(size.width, 254)
        XCTAssertEqual(size.height, 6 * 54, accuracy: 1)
    }
}

private struct DrawerRowFramesKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(
        value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

@MainActor
private final class DrawerLayoutMeasurements {
    var rows: [Int: CGRect] = [:]
}

@MainActor
private func measuredDrawerRow(_ index: Int) -> some View {
    Color.clear
        .frame(height: 54)
        .overlay(alignment: .leading) { Text("导航 \(index)") }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DrawerRowFramesKey.self,
                    value: [index: proxy.frame(in: .named("drawer-layout-test"))]
                )
            }
        }
}

extension DrawerContainerControllerTests {
    /// 显示原点口径：transform.tx 是 model 值、被布局
    /// 补偿时照样达标，必须直验前景的实际显示原点
    /// （frame getter 按 center/bounds/transform 合成）
    private var foregroundDisplayedOriginX: CGFloat {
        let subviews = controller.view.subviews
        guard subviews.count >= 2 else { return -1 }
        return subviews[1].frame.origin.x
    }

    func testAnimatedOpenDisplayedOriginReachesTravel() {
        controller.setDrawer(true, animated: true)
        spinRunLoop(seconds: 2.0)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
        XCTAssertEqual(
            foregroundDisplayedOriginX, controller.travel, accuracy: 1.0,
            "model 位移达标但显示原点未达：位移被几何补偿吃掉"
        )
    }

    /// §178.8 补修 A（Codex 异源复核）：关闭动画起
    /// 始帧起内容必须保持不可点、命中不得落进内容
    /// 宿主，直到落定才恢复——修复前 animator 闭包
    /// 在起始拍以目标值 applyOffset(0) 把交互同步置
    /// true，呈现层还在移动（透传/命中按 model 值与
    /// 布局快照帧走），点会落进正在移动的内容
    func testAnimatedCloseKeepsContentUntouchableUntilSettled() {
        controller.contentRoot = AnyView(Color.red)
        controller.view.layoutIfNeeded()
        controller.setDrawer(true, animated: false)
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, false,
            "开态内容应不可点")
        pauseForegroundLayerClock()
        controller.setDrawer(false, animated: true)
        // 起始帧同步断言（不泵 runloop）：交互置位在
        // animator 闭包内同步发生——此处已被置 true
        // 即回归本体
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, false,
            "关闭动画起始帧内容即恢复可点（呈现层还在移动）")
        let midTx = waitForInFlightPresentationTx()
        XCTAssertGreaterThan(
            midTx, 1,
            "呈现层应仍在位移途中")
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, false,
            "关闭动画途中内容应保持不可点")
        let center = CGPoint(x: 196, y: 426)
        let midHit = controller.view.hitTest(center, with: nil)
        XCTAssertFalse(
            isInContentHost(midHit),
            "关闭动画途中命中穿进了内容宿主")
        resumeForegroundLayerClock()
        spinRunLoop(seconds: 2.0)
        XCTAssertEqual(foregroundTx, 0, accuracy: 1.0)
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, true,
            "落定后内容应恢复可点")
        let settledHit = controller.view.hitTest(center, with: nil)
        XCTAssertTrue(
            isInContentHost(settledHit),
            "落定后命中应回到内容")
    }

    /// §178.8 补修 A（开向）：打开动画起始帧内容即
    /// 不可点、落定后保持（窄条承接点按）
    func testAnimatedOpenDisablesContentFromFirstFrame() {
        controller.contentRoot = AnyView(Color.red)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, true,
            "关态落定内容应可点")
        pauseForegroundLayerClock()
        controller.setDrawer(true, animated: true)
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, false,
            "打开动画起始帧内容应即刻不可点")
        let midTx = waitForInFlightPresentationTx()
        XCTAssertGreaterThan(
            midTx, -0.5,
            "呈现层应已有值（动画已提交；-1 为 nil 哨兵）")
        XCTAssertLessThan(
            midTx, controller.travel - 1,
            "呈现层应仍在位移途中")
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, false,
            "打开动画途中内容应保持不可点")
        resumeForegroundLayerClock()
        spinRunLoop(seconds: 2.0)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, false,
            "开态落定后内容仍不可点")
    }

    /// 内容宿主视图（viewDidLoad 装配序：前景为容器
    /// 第二子、其内裁切层第一子、内容宿主在裁切层内）
    private var contentHostView: UIView? {
        let subviews = controller.view.subviews
        guard subviews.count >= 2 else { return nil }
        return subviews[1].subviews.first?.subviews.first
    }

    /// 前景呈现层当前位移（动画途中量测：model 值在
    /// 起始拍已落目标、只有 presentation 是途中事实）
    private var foregroundPresentationTx: CGFloat {
        let subviews = controller.view.subviews
        guard subviews.count >= 2 else { return -1 }
        return subviews[1].layer.presentation()?.transform.m41 ?? -1
    }

    /// The clock is paused before starting the animator: rendering delays
    /// cannot consume the spring before these first-frame assertions.
    private func waitForInFlightPresentationTx(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGFloat {
        let layer = controller.view.subviews[1].layer
        CATransaction.flush()
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            _ = RunLoop.main.run(
                mode: .default,
                before: Date().addingTimeInterval(1.0 / 120.0)
            )
            if layer.presentation() != nil,
               !(layer.animationKeys() ?? []).isEmpty {
                return foregroundPresentationTx
            }
        }
        XCTFail("presentation layer did not appear during animation", file: file, line: line)
        return foregroundPresentationTx
    }

    private func pauseForegroundLayerClock() {
        let layer = controller.view.subviews[1].layer
        let localTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = localTime
    }

    private func resumeForegroundLayerClock() {
        let layer = controller.view.subviews[1].layer
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
    }

    private func isInContentHost(_ view: UIView?) -> Bool {
        guard let host = contentHostView else { return false }
        var node = view
        while let current = node {
            if current === host { return true }
            node = current.superview
        }
        return false
    }

    /// 动画途中强制真实布局（改窗口宽→容器 bounds 变
    /// →viewDidLayoutSubviews 必触发）：布局往返不得
    /// 改写已承诺的开合显示位置
    func testAnimatedOpenSurvivesMidFlightResize() {
        controller.setDrawer(true, animated: true)
        spinRunLoop(seconds: 0.15)
        window.frame = CGRect(x: 0, y: 0, width: 403, height: 852)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.15)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 2.0)
        XCTAssertTrue(controller.semanticPresented)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
        XCTAssertEqual(
            foregroundDisplayedOriginX, controller.travel, accuracy: 1.0,
            "动画途中布局往返后显示原点未达 travel：frame 重设在 transform 下反解 center 吃掉位移"
        )
    }
}
