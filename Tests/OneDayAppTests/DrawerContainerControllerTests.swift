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
