import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §351 刚体回归钉：开合全程（含飞行中 model 值
/// 与落定后）裁切层/内容宿主/投影层的未变换几何
/// （bounds/center）恒为前景全幅——呈现只许由
/// transform 承担。旧口径下开态 clip bounds 高
/// −4、内容原点移位，本组断言在旧实现上必红、
/// 新实现恒绿（防逐帧帧写回潮）
@MainActor
final class DrawerRigidBodyTests: XCTestCase {
    private var window: UIWindow!
    private var controller: DrawerContainerController!

    override func setUp() async throws {
        try await super.setUp()
        controller = DrawerContainerController()
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 393, height: 852)
        )
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

    private var foreground: UIView { controller.view.subviews[1] }
    private var shadowView: UIView { foreground.subviews[0] }
    private var clipView: UIView { foreground.subviews[1] }
    private var contentView: UIView { clipView.subviews[0] }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func assertRigidFullBounds(_ label: String) {
        let full = foreground.bounds
        let center = CGPoint(x: full.midX, y: full.midY)
        for (name, view) in [
            ("shadow", shadowView), ("clip", clipView),
            ("content", contentView),
        ] {
            XCTAssertEqual(
                view.bounds, full,
                "\(label)：\(name) bounds 应恒全幅")
            XCTAssertEqual(
                view.center, center,
                "\(label)：\(name) center 应恒居中")
        }
    }

    func testCardLayersKeepFullBoundsAcrossStates() {
        assertRigidFullBounds("合态")
        controller.setDrawer(true, animated: false)
        controller.view.layoutIfNeeded()
        assertRigidFullBounds("开态（瞬时）")
        // 开态呈现全在 transform：纵向 scaleY 等效
        // （848/852）、横移与内容反向抵消成对
        XCTAssertEqual(
            clipView.transform.d, 848.0 / 852.0, accuracy: 0.0001)
        XCTAssertEqual(clipView.transform.a, 1, accuracy: 0.0001)
        XCTAssertEqual(shadowView.transform, clipView.transform)
        XCTAssertEqual(
            contentView.transform.tx, -clipView.transform.tx,
            accuracy: 0.001)
        XCTAssertEqual(contentView.transform.d, 1, accuracy: 0.0001)
        controller.setDrawer(false, animated: false)
        controller.view.layoutIfNeeded()
        assertRigidFullBounds("回合态")
        XCTAssertEqual(clipView.transform, .identity)
        XCTAssertEqual(contentView.transform, .identity)
    }

    func testCardLayersKeepFullBoundsDuringAnimatedFlight() {
        controller.setDrawer(true, animated: true)
        // 动画闭包启动拍 model 已落目标值——此刻即
        // 「飞行中」口径：animator 插值的只是
        // transform、几何恒定由构造保证
        assertRigidFullBounds("开飞行 model")
        spinRunLoop(seconds: 1.2)
        assertRigidFullBounds("开落定")
        controller.setDrawer(false, animated: true)
        assertRigidFullBounds("关飞行 model")
        spinRunLoop(seconds: 1.2)
        assertRigidFullBounds("关落定")
    }

    func testCardLayersKeepFullBoundsAcrossLayoutPasses() {
        controller.setDrawer(true, animated: true)
        // 飞行中布局往返（以当前 offset 重派生）不
        // 许把任何帧写偏
        controller.view.layoutIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        assertRigidFullBounds("飞行中布局往返后")
        spinRunLoop(seconds: 1.2)
        // 尺寸变：全幅跟随新尺寸、三层仍恒等
        window.frame = CGRect(x: 0, y: 0, width: 852, height: 393)
        controller.view.layoutIfNeeded()
        assertRigidFullBounds("旋转后开态")
        XCTAssertEqual(clipView.bounds.height, 393, accuracy: 0.5)
    }
}
