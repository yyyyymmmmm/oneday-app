import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §179 回归组：身份胶囊命中域。缺陷机理（宿主两轮
/// 量测坐实，见 DESIGN §179）：.glassEffect 直接加
/// 在装有两钮的胶囊行本体上时，iOS 26 生成单一
/// UIPlatformGlassInteractionView 盖满整颗胶囊——
/// 两钮无独立命中域，紧贴状态栏带下沿的胶囊上缘
/// 玻璃带落点被整面吞下、按位置派给模型钮（点状
/// 态栏求回顶却开模型面）。修法＝玻璃降为行背景
/// 背板、胶囊独立成生产件 IdentityCapsuleView。
/// 本组直接宿主该生产件，钉两条不变量：
/// ①窗口内不存在盖满胶囊的宽幅玻璃交互视图；
/// ②状态栏带内点与胶囊上缘带点的 hitTest 永不
///   返回玻璃交互视图。
/// （两钮标签为组件内静态字符串、编译期即定，不
/// 在本组重复断言；功能存活由真机验点覆盖。）
@MainActor
final class IdentityCapsuleHitDomainTests: XCTestCase {

    private final class CapsuleFrameBox {
        var frame: CGRect?
    }

    private struct FrameKey: PreferenceKey {
        static var defaultValue: CGRect? { nil }
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
            value = nextValue() ?? value
        }
    }

    /// 生产同构脚手架：消息列表＋顶 safeAreaBar 注册
    /// ＋.soft 顶缘，bar 内只放生产胶囊件（居中）
    private struct Scaffold: View {
        let box: CapsuleFrameBox

        var body: some View {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<40, id: \.self) { index in
                        Text("消息行 \(index)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 20)
            }
            .safeAreaBar(edge: .top) {
                HStack(alignment: .center, spacing: 8) {
                    Spacer()
                    IdentityCapsuleView(
                        avatar: Image(systemName: "person.circle.fill"),
                        displayName: "Hermes",
                        statusWord: "在线",
                        statusColor: .green,
                        avatarPointSize: 28,
                        modelTriggerLabel: "deepseek-flash",
                        modelAccessibilityLabel: "当前模型 deepseek-flash，切换模型",
                        onOpenHub: {},
                        onOpenModelPicker: {}
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: FrameKey.self,
                                value: proxy.frame(in: .global)
                            )
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onPreferenceChange(FrameKey.self) { value in
                box.frame = value ?? box.frame
            }
        }
    }

    private final class StatusBarWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: StatusBarWindow!

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func glassInteractionViews() -> [UIView] {
        var found: [UIView] = []
        func walk(_ view: UIView) {
            if String(describing: type(of: view))
                .contains("GlassInteraction") {
                found.append(view)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)
        return found
    }

    private func isGlassInteraction(_ view: UIView?) -> Bool {
        guard let view else { return false }
        return String(describing: type(of: view))
            .contains("GlassInteraction")
    }

    func testCapsuleHasNoSpanningGlassHitSurface() throws {
        let box = CapsuleFrameBox()
        let host = UIHostingController(rootView: Scaffold(box: box))
        window = StatusBarWindow(
            frame: CGRect(x: 0, y: 0, width: 393, height: 852)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        host.view.layoutIfNeeded()

        let capsule = try XCTUnwrap(box.frame, "胶囊帧未量得")
        XCTAssertGreaterThan(capsule.width, 150, "胶囊应为全量档宽")
        XCTAssertGreaterThanOrEqual(
            capsule.minY, 59,
            "胶囊顶边不得进入状态栏带（带高 59）"
        )

        // ①：不存在宽幅玻璃交互视图（缺陷态为 256 宽
        // 盖满胶囊；修后胶囊玻璃只作背景、不生成交
        // 互视图）
        for glass in glassInteractionViews() {
            let frame = glass.convert(glass.bounds, to: window)
            XCTAssertLessThanOrEqual(
                frame.width, 44,
                "出现宽幅玻璃交互视图 \(frame)——玻璃疑被加回行本体"
            )
        }

        // ②：状态栏带内（y=30）与胶囊上缘带（顶边
        // +2，缺陷态的误触落点）的 hitTest 永不返回
        // 玻璃交互视图
        let probePoints: [CGPoint] = [
            CGPoint(x: capsule.midX, y: 30),
            CGPoint(x: capsule.maxX - 30, y: 30),
            CGPoint(x: capsule.midX, y: capsule.minY + 2),
            CGPoint(x: capsule.maxX - 30, y: capsule.minY + 2),
            CGPoint(x: capsule.minX + 30, y: capsule.minY + 2),
        ]
        for point in probePoints {
            let hit = window.hitTest(point, with: nil)
            XCTAssertFalse(
                isGlassInteraction(hit),
                "点 \(point) 命中玻璃交互视图 \(String(describing: hit))"
            )
        }

    }
}
