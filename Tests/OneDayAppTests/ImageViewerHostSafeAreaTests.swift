import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// A-21 查看器半边收口（§315）：ZoomHostingController
/// 宿主 safeAreaRegions 清零断言（H2 纪律，与抽屉双宿
/// 主同口径）＋全幅呈现不变面——宿主装窗布局后视图帧
/// 占满窗口帧。缩放/双击本体在 ZoomableImageView（本
/// 包未动），由既有套件全绿担。
@MainActor
final class ImageViewerHostSafeAreaTests: XCTestCase {
    private var window: UIWindow!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    /// 对照组：裸 UIHostingController 默认 safeArea-
    /// Regions＝.all——证明下条断言量的不是平台默认
    /// 值、清零确为本宿主落码所致。
    func testPlainHostingControllerDefaultsToAllSafeAreaRegions() {
        let plain = UIHostingController(rootView: Color.clear)
        XCTAssertEqual(plain.safeAreaRegions, .all)
    }

    /// A-21 本体：查看器宿主 viewDidLoad 后 safeArea-
    /// Regions 已清零。
    func testZoomHostingControllerClearsSafeAreaRegions() {
        let controller = ZoomHostingController(
            rootView: Color.clear, sourceID: nil
        )
        controller.loadViewIfNeeded()
        XCTAssertEqual(controller.safeAreaRegions, [])
    }

    /// 全幅不变：宿主装窗布局后视图帧＝窗口帧（全幅
    /// 呈现面未被清零收走），且装窗后清零仍在。
    func testZoomHostingControllerViewFillsWindow() {
        let controller = ZoomHostingController(
            rootView: Color.clear, sourceID: nil
        )
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.view.frame, window.bounds)
        XCTAssertEqual(controller.safeAreaRegions, [])
    }
}
