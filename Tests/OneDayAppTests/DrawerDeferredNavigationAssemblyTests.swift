import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 147 装配层：抽屉控制器呈现进度/打断回调
/// → AppRouter 延迟导航状态机的整链——点行只置
/// 待办、近闭合才落 drawerThreadSelection、关动画
/// 被打断即刻落值。判定机本身在 Core 测
/// （DrawerDeferredNavigationTests），本组钉装配
@MainActor
final class DrawerDeferredNavigationAssemblyTests: XCTestCase {
    private var window: UIWindow!
    private var controller: DrawerContainerController!
    private var router: AppRouter!
    private let threadID = UUID()

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        controller = DrawerContainerController()
        router = AppRouter()
        controller.onDrawerProgress = { [weak router] progress in
            router?.noteDrawerProgress(progress)
        }
        controller.onDrawerCloseInterrupted = { [weak router] in
            router?.noteDrawerCloseInterrupted()
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        controller = nil
        router = nil
        super.tearDown()
    }

    private func spin(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(
                mode: .default,
                before: Date().addingTimeInterval(0.02)
            )
        }
    }

    /// 开抽屉（无动画直达）后点行置待办：关动画进
    /// 行中待办不落值、近闭合（或落定兜底）后落值
    func testNavigationFiresOnlyNearClosed() {
        controller.setDrawer(true, animated: false)
        // 置位口返回 Void——「不得立即导航」由下两
        // 行断言（待办在位＋真值未落）钉住
        router.stageDrawerThreadSelection(threadID)
        XCTAssertTrue(router.hasPendingDrawerNavigation)
        XCTAssertNil(router.drawerThreadSelection)
        controller.setDrawer(false, animated: true)
        spin(1.2)
        XCTAssertEqual(
            router.drawerThreadSelection, threadID,
            "关动画近闭合后待办须落值"
        )
        XCTAssertFalse(router.hasPendingDrawerNavigation)
    }

    /// 关动画被重开打断：待办即刻落值（不吞导航），
    /// 即使抽屉最终停在打开态
    func testCloseInterruptedFiresImmediately() {
        controller.setDrawer(true, animated: false)
        router.stageDrawerThreadSelection(threadID)
        XCTAssertTrue(router.hasPendingDrawerNavigation)
        controller.setDrawer(false, animated: true)
        controller.setDrawer(true, animated: true)
        XCTAssertEqual(
            router.drawerThreadSelection, threadID,
            "关动画被打断时待办须即刻执行"
        )
        spin(0.8)
        // 抽屉最终打开、导航仍只执行一次
        XCTAssertEqual(router.drawerThreadSelection, threadID)
        XCTAssertFalse(router.hasPendingDrawerNavigation)
    }

    /// Reduce Motion 瞬时关：进度直达 0、待办同步落值
    func testReduceMotionInstantCloseFires() {
        controller.reduceMotion = true
        controller.setDrawer(true, animated: true)
        router.stageDrawerThreadSelection(threadID)
        XCTAssertTrue(router.hasPendingDrawerNavigation)
        controller.setDrawer(false, animated: true)
        XCTAssertEqual(router.drawerThreadSelection, threadID)
    }
}
