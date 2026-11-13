import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §213 滚动边缘效果内容驱动注册的宿主级验收（取
/// 代 §200 的 SystemBackdropTests）：两宿主不再垫
/// 常驻材质片——顶簇宿主视图上挂顶缘 interaction、
/// 舱带保留 A2 卡段几何但载体换透明注册容器＋底
/// 缘 interaction、坞（UITabBar）不被塞任何自家子
/// 视图；绑定经 ChatListScrollViewHandle 在赋值/
/// 显形拍对齐列表本体；栏位几何（顶簇落点/舱带高
/// 链）与 §200 时代逐值不变；深色＋AX 最大字号下
/// 同断。像素级双态验收（静止不可见/滚动朦胧在）
/// 由 EdgeEffectProbeTests 承担。
@MainActor
final class EdgeEffectRegistrationTests: XCTestCase {

    /// 设备窗口：覆写为真机安全区（顶 62／底 34）
    /// ——裸 UIWindow 的安全区恒 0、顶簇落点无从分
    /// 辨（照 SystemBackdropTests 旧脚手架先例）
    private final class EdgeDeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        }
    }

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func makeWindow() -> EdgeDeviceWindow {
        let window = EdgeDeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        windows.append(window)
        return window
    }

    private func findViews(
        _ root: UIView, where matches: (UIView) -> Bool
    ) -> [UIView] {
        var out: [UIView] = []
        if matches(root) { out.append(root) }
        for sub in root.subviews {
            out += findViews(sub, where: matches)
        }
        return out
    }

    // MARK: - 顶宿主装配（与旧底衬测试同式）

    private func mountTopHost(
        topOffset: CGFloat, barHeight: CGFloat
    ) -> (EdgeDeviceWindow, TopBarGuideHostController) {
        let window = makeWindow()
        let wrapper = UIViewController()
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints =
            false
        wrapper.view.addSubview(container)
        let host = TopBarGuideHostController()
        wrapper.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints =
            false
        container.addSubview(host.view)
        host.didMove(toParent: wrapper)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(
                equalTo: wrapper.view.leadingAnchor),
            container.trailingAnchor.constraint(
                equalTo: wrapper.view.trailingAnchor),
            container.topAnchor.constraint(
                equalTo: wrapper.view.topAnchor,
                constant: topOffset),
            container.bottomAnchor.constraint(
                equalTo: wrapper.view.bottomAnchor),
            host.view.leadingAnchor.constraint(
                equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(
                equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(
                equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(
                equalTo: container.bottomAnchor),
        ])
        window.rootViewController = wrapper
        window.makeKeyAndVisible()
        host.updateBarContentHeight(barHeight)
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        window.layoutIfNeeded()
        return (window, host)
    }

    private func mountComposerInTabShell()
        -> (EdgeDeviceWindow, ComposerGuideHostController,
            UITabBarController) {
        let window = makeWindow()
        let host = ComposerGuideHostController()
        let tabs = UITabBarController()
        tabs.viewControllers = [host]
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 1.2)
        window.layoutIfNeeded()
        return (window, host, tabs)
    }

    // MARK: - 顶缘注册

    func testTopEdgeInteractionBindsToRegisteredScrollView() {
        let (_, host) = mountTopHost(
            topOffset: 0, barHeight: 72
        )
        // 结构：宿主层级内只剩顶簇宿主视图——§200 的
        // 材质片兄弟已退役，全子树无 UIVisualEffectView
        XCTAssertEqual(host.view.subviews.count, 1)
        XCTAssertTrue(
            host.view.subviews.first === host.traceBarView
        )
        XCTAssertTrue(
            findViews(host.view) {
                $0 is UIVisualEffectView
            }.isEmpty,
            "顶宿主子树内不应再有任何材质视图"
        )
        // 注册本体：interaction 挂在顶簇宿主视图上、
        // edge=.top、未喂句柄时 scrollView 为空
        let interaction = host.traceEdgeInteraction
        XCTAssertTrue(
            host.traceBarView.interactions.contains(
                where: { $0 === interaction }
            )
        )
        XCTAssertEqual(interaction.edge, .top)
        XCTAssertNil(interaction.scrollView)
        // 喂入已登记本体的句柄：赋值即绑定
        let handle = ChatListScrollViewHandle()
        let scroll = UIScrollView()
        handle.register(scroll)
        host.edgeScrollHandle = handle
        XCTAssertTrue(interaction.scrollView === scroll)
    }

    func testTopEdgeBindingRefreshesOnAppearAfterLateRegistration() {
        let (_, host) = mountTopHost(
            topOffset: 0, barHeight: 72
        )
        // 先喂空句柄（列表本体未登记）：不绑
        let handle = ChatListScrollViewHandle()
        host.edgeScrollHandle = handle
        XCTAssertNil(host.traceEdgeInteraction.scrollView)
        // 本体后到登记：显形拍（syncTopConstant 同路
        // 刷新）补绑
        let scroll = UIScrollView()
        handle.register(scroll)
        host.viewDidAppear(false)
        XCTAssertTrue(
            host.traceEdgeInteraction.scrollView === scroll
        )
    }

    // MARK: - 顶簇几何（§200 时代逐值不变）

    func testTopBarGeometryUnchangedWithoutSheet() {
        let (window, host) = mountTopHost(
            topOffset: 0, barHeight: 72
        )
        let barFrame = host.traceBarView.convert(
            host.traceBarView.bounds, to: window
        )
        XCTAssertEqual(barFrame.minY, 62, accuracy: 0.6)
        XCTAssertEqual(barFrame.maxY, 134, accuracy: 0.6)
        XCTAssertEqual(barFrame.width, 402, accuracy: 0.6)
    }

    func testTopBarGeometryCompensatesShiftedHostFrame() {
        let (window, host) = mountTopHost(
            topOffset: 25, barHeight: 72
        )
        let barFrame = host.traceBarView.convert(
            host.traceBarView.bounds, to: window
        )
        XCTAssertEqual(barFrame.minY, 62, accuracy: 0.6)
        XCTAssertEqual(barFrame.maxY, 134, accuracy: 0.6)
    }

    // MARK: - 舱带容器（A2 几何不变、载体换注册）

    func testComposerBandContainerInTabShell() {
        let (_, host, _) = mountComposerInTabShell()
        // 舱带：宿主视图内最底层、透明注册容器（非材
        // 质视图）、不接命中、自带底缘 interaction
        let band = host.traceBandView
        XCTAssertTrue(band.superview === host.view)
        XCTAssertTrue(host.view.subviews.first === band)
        XCTAssertFalse(band is UIVisualEffectView)
        XCTAssertFalse(band.isUserInteractionEnabled)
        guard let bandContainer =
                band as? EdgeBandContainerView else {
            return XCTFail("舱带不是 EdgeBandContainerView")
        }
        XCTAssertEqual(bandContainer.traceInteraction.edge, .bottom)
        XCTAssertTrue(
            band.interactions.contains(
                where: { $0 === bandContainer.traceInteraction }
            )
        )
        // 带高随舱帧实测：喂 128 高舱帧后同高、底边
        // 与舱宿主底同位（静息态舱底＝坞顶 791）
        host.updateBarFrame(
            CGRect(x: 0, y: 600, width: 402, height: 128)
        )
        host.view.layoutIfNeeded()
        XCTAssertEqual(band.frame.height, 128, accuracy: 0.6)
        XCTAssertEqual(
            band.frame.maxY,
            host.traceComposerHostView.frame.maxY,
            accuracy: 0.6
        )
        XCTAssertEqual(
            host.traceComposerHostView.frame.maxY, 791,
            accuracy: 0.6
        )
    }

    func testComposerBandShrinksToCardSegment() {
        let (_, host, _) = mountComposerInTabShell()
        let band = host.traceBandView
        // 卡帧未到：回落整栈口径——喂整栈帧（顶 560、
        // 高 240），带同高
        host.updateBarFrame(
            CGRect(x: 0, y: 560, width: 402, height: 240)
        )
        host.view.layoutIfNeeded()
        XCTAssertEqual(band.frame.height, 240, accuracy: 0.6)
        // 卡帧到（卡顶 672＝整栈底 800−卡高 128）：带
        // 高收为卡段 128，带底仍贴宿主底
        host.updateCardFrame(
            CGRect(x: 14, y: 672, width: 374, height: 128)
        )
        host.view.layoutIfNeeded()
        XCTAssertEqual(band.frame.height, 128, accuracy: 0.6)
        XCTAssertEqual(
            band.frame.maxY,
            host.traceComposerHostView.frame.maxY,
            accuracy: 0.6
        )
        // 整栈再长高（回底钮行出现：栈顶上移 52、卡
        // 顶不动）：带高不变
        host.updateBarFrame(
            CGRect(x: 0, y: 508, width: 402, height: 292)
        )
        host.view.layoutIfNeeded()
        XCTAssertEqual(band.frame.height, 128, accuracy: 0.6)
        // 卡生长（多行输入：卡顶上移 30）：带随卡长高
        host.updateCardFrame(
            CGRect(x: 14, y: 642, width: 374, height: 158)
        )
        host.view.layoutIfNeeded()
        XCTAssertEqual(band.frame.height, 158, accuracy: 0.6)
    }

    // MARK: - 舱带绑定＋坞零侵入

    func testComposerEdgeBindingAndDockUntouchedInTabShell() {
        let (_, host, tabs) = mountComposerInTabShell()
        let tabBar = tabs.tabBar
        let subviewCountBefore = tabBar.subviews.count
        print("EDGE-REG dock subviews: "
            + tabBar.subviews.map {
                String(describing: type(of: $0))
            }.joined(separator: ","))
        // 坞内无自家注册容器、无全幅材质片
        XCTAssertTrue(
            tabBar.subviews.allSatisfy {
                !($0 is EdgeBandContainerView)
            }
        )
        XCTAssertFalse(
            tabBar.subviews.contains {
                $0 is UIVisualEffectView
                    && $0.frame == tabBar.bounds
            },
            "坞内不应有 §200 式全幅材质片"
        )
        // 舱带绑定：喂句柄（赋值即绑）
        let handle = ChatListScrollViewHandle()
        let scroll = UIScrollView()
        handle.register(scroll)
        host.edgeScrollHandle = handle
        guard let bandContainer =
                host.traceBandView as? EdgeBandContainerView
        else { return XCTFail("舱带不是注册容器") }
        XCTAssertTrue(
            bandContainer.traceInteraction.scrollView === scroll
        )
        // 锚解析重跑（显形）不往坞里加任何东西
        host.viewDidAppear(false)
        XCTAssertEqual(
            tabBar.subviews.count, subviewCountBefore
        )
    }

    // MARK: - 登记锚（祖先链定位本体）

    func testAnchorRegistersAncestorScrollView() {
        let window = makeWindow()
        let wrapper = UIViewController()
        let scroll = UIScrollView(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let chain = UIView()
        scroll.addSubview(chain)
        let handle = ChatListScrollViewHandle()
        let anchor = ChatListScrollAnchorView()
        anchor.handle = handle
        chain.addSubview(anchor)
        wrapper.view.addSubview(scroll)
        window.rootViewController = wrapper
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.4)
        XCTAssertTrue(handle.scrollView === scroll)
    }

    // MARK: - 深色＋AX 最大字号自查帧

    func testRegistrationUnderDarkAndLargestAX() {
        let (window, host) = mountTopHost(
            topOffset: 0, barHeight: 72
        )
        window.overrideUserInterfaceStyle = .dark
        if let wrapper = window.rootViewController {
            wrapper.setOverrideTraitCollection(
                UITraitCollection(traitsFrom: [
                    UITraitCollection(
                        preferredContentSizeCategory:
                            .accessibilityExtraExtraExtraLarge
                    ),
                    UITraitCollection(
                        userInterfaceStyle: .dark),
                ]),
                forChild: host
            )
        }
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        window.layoutIfNeeded()
        // 两 trait 下顶簇落点不变、注册仍在位、子树无
        // 材质视图
        let barFrame = host.traceBarView.convert(
            host.traceBarView.bounds, to: window
        )
        XCTAssertEqual(barFrame.minY, 62, accuracy: 0.6)
        XCTAssertEqual(host.traceEdgeInteraction.edge, .top)
        XCTAssertTrue(
            host.traceBarView.interactions.contains(
                where: { $0 === host.traceEdgeInteraction }
            )
        )
        XCTAssertTrue(
            findViews(host.view) {
                $0 is UIVisualEffectView
            }.isEmpty
        )
    }
}
