import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §200 系统材质底衬的宿主级验收：三处底衬（顶带/
/// 输入框周边/底部坞）的结构与几何——材质档单点定
/// 义、挂载层级（宿主自有层级最底/坞本体最底）、覆
/// 盖带落点（顶带＝窗口顶→顶簇底、补偿对宿主帧移
/// 动免疫；舱带高随舱帧实测；坞带＝坞 bounds 全幅
/// 且装配幂等）、深色＋AX 最大字号 trait 下覆盖不
/// 变。观感本身（糊化是否够、与胶囊玻璃的层次）归
/// 真机清单（DESIGN §200），不在此断言。
@MainActor
final class SystemBackdropTests: XCTestCase {

    /// 设备窗口：覆写为真机安全区（§195 自述口径：
    /// 顶 62／底 34）——裸 UIWindow 的安全区恒 0、
    /// 顶带补偿无从分辨（照 TabBarFloatTests 的
    /// FloatDeviceWindow 先例）
    private final class BackdropDeviceWindow: UIWindow {
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

    private func makeWindow() -> BackdropDeviceWindow {
        let window = BackdropDeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        windows.append(window)
        return window
    }

    // MARK: - 材质单点定义

    func testSharedStyleIsSystemChromeMaterial() {
        XCTAssertEqual(
            SystemBackdrop.style, .systemChromeMaterial
        )
        let view = SystemBackdrop.makeView()
        XCTAssertTrue(view.effect is UIBlurEffect)
        XCTAssertFalse(view.isUserInteractionEnabled)
    }

    // MARK: - 顶带

    /// 把顶簇宿主装进一个可纵向偏移的容器（偏移＝
    /// §195 病形：宿主帧被 SwiftUI 挪位时，顶簇与底
    /// 衬的窗口落点都须靠常量补偿钉死）
    private func mountTopHost(
        topOffset: CGFloat, barHeight: CGFloat
    ) -> (BackdropDeviceWindow, TopBarGuideHostController) {
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

    func testTopBackdropCoversWindowTopToBarBottom() {
        let (window, host) = mountTopHost(
            topOffset: 0, barHeight: 72
        )
        let backdrop = host.traceBackdropView
        // 层级：底衬在宿主视图内、且位于顶簇宿主之下
        XCTAssertTrue(backdrop.superview === host.view)
        let subviews = host.view.subviews
        guard let backdropIndex = subviews.firstIndex(
                where: { $0 === backdrop }),
              let barIndex = subviews.firstIndex(
                where: { $0 === host.traceBarView })
        else {
            return XCTFail("底衬或顶簇宿主不在宿主视图层级内")
        }
        XCTAssertLessThan(backdropIndex, barIndex)
        // 覆盖带：窗口顶（0）→顶簇底（安全区 62＋实高 72）
        let backdropFrame = backdrop.convert(
            backdrop.bounds, to: window
        )
        let barFrame = host.traceBarView.convert(
            host.traceBarView.bounds, to: window
        )
        XCTAssertEqual(barFrame.minY, 62, accuracy: 0.6)
        XCTAssertEqual(backdropFrame.minY, 0, accuracy: 0.6)
        XCTAssertEqual(
            backdropFrame.maxY, barFrame.maxY, accuracy: 0.6
        )
        XCTAssertEqual(backdropFrame.maxY, 134, accuracy: 0.6)
        XCTAssertEqual(backdropFrame.width, 402, accuracy: 0.6)
    }

    func testTopBackdropCompensatesShiftedHostFrame() {
        // 宿主帧被下挪 25（§195 落定帧的病形）：顶簇
        // 窗口落点仍须 62、底衬上缘仍须贴窗口顶 0
        let (window, host) = mountTopHost(
            topOffset: 25, barHeight: 72
        )
        let backdrop = host.traceBackdropView
        let backdropFrame = backdrop.convert(
            backdrop.bounds, to: window
        )
        let barFrame = host.traceBarView.convert(
            host.traceBarView.bounds, to: window
        )
        XCTAssertEqual(barFrame.minY, 62, accuracy: 0.6)
        XCTAssertEqual(backdropFrame.minY, 0, accuracy: 0.6)
        XCTAssertEqual(
            backdropFrame.maxY, barFrame.maxY, accuracy: 0.6
        )
    }

    // MARK: - 输入框周边＋底部坞（同装配）

    func testComposerBackdropAndDockBackdropInTabShell() {
        let window = makeWindow()
        let host = ComposerGuideHostController()
        let tabs = UITabBarController()
        tabs.viewControllers = [host]
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 1.2)
        window.layoutIfNeeded()

        // 舱底衬：宿主视图内最底层
        let backdrop = host.traceBackdropView
        XCTAssertTrue(backdrop.superview === host.view)
        XCTAssertTrue(host.view.subviews.first === backdrop)
        XCTAssertFalse(backdrop.isUserInteractionEnabled)

        // 舱带高随舱帧实测：喂一帧 128 高的舱帧，底
        // 衬布局后同高、底边与舱宿主底同位——静息
        // 态舱底＝坞顶 791，舱带覆盖至此为止、其下
        // 由坞底衬接续（两段在坞顶边相接）
        host.updateBarFrame(
            CGRect(x: 0, y: 600, width: 402, height: 128)
        )
        host.view.layoutIfNeeded()
        XCTAssertEqual(backdrop.frame.height, 128, accuracy: 0.6)
        XCTAssertEqual(
            backdrop.frame.maxY,
            host.traceComposerHostView.frame.maxY,
            accuracy: 0.6
        )
        XCTAssertEqual(
            host.traceComposerHostView.frame.maxY, 791,
            accuracy: 0.6
        )

        // 坞底衬：resolveAnchors 已随显形跑过——坞本
        // 体内恰一份底衬、最底层、帧＝坞 bounds
        let tabBar = tabs.tabBar
        let dockBackdrops = tabBar.subviews.filter {
            $0 is SystemDockBackdropView
        }
        XCTAssertEqual(dockBackdrops.count, 1)
        guard let dockBackdrop = dockBackdrops.first else {
            return XCTFail("坞底衬未装配")
        }
        XCTAssertTrue(tabBar.subviews.first === dockBackdrop)
        XCTAssertEqual(dockBackdrop.frame, tabBar.bounds)
        XCTAssertFalse(dockBackdrop.isUserInteractionEnabled)
        XCTAssertTrue(dockBackdrop is UIVisualEffectView)
    }

    // MARK: - 坞装配幂等

    func testDockBackdropEnsureIsIdempotent() {
        let tabBar = UITabBar(
            frame: CGRect(x: 0, y: 0, width: 402, height: 83)
        )
        let first = SystemDockBackdrop.ensureInstalled(
            in: tabBar
        )
        // UITabBar 自带系统背景子视图，总数不作数；
        // 只数底衬实例恰一份、且居层级最底
        XCTAssertEqual(
            tabBar.subviews.filter {
                $0 is SystemDockBackdropView
            }.count, 1
        )
        XCTAssertTrue(tabBar.subviews.first === first)
        XCTAssertEqual(first.frame, tabBar.bounds)
        // 外来子视图进场后再 ensure：底衬仍恰一份、
        // 被校正回最底层
        let other = UIView()
        tabBar.addSubview(other)
        tabBar.bringSubviewToFront(first)
        let second = SystemDockBackdrop.ensureInstalled(
            in: tabBar
        )
        XCTAssertTrue(first === second)
        XCTAssertEqual(
            tabBar.subviews.filter {
                $0 is SystemDockBackdropView
            }.count, 1
        )
        XCTAssertTrue(tabBar.subviews.first === second)
        // 坞 bounds 变化经 autoresizing 跟随
        tabBar.frame = CGRect(x: 0, y: 0, width: 402, height: 100)
        XCTAssertEqual(second.frame, tabBar.bounds)
    }

    // MARK: - 深色＋AX 最大字号自查帧

    func testBackdropCoverageUnderDarkAndLargestAX() {
        let (window, host) = mountTopHost(
            topOffset: 0, barHeight: 72
        )
        window.overrideUserInterfaceStyle = .dark
        // AX 最大档（accessibilityExExExL）经父级
        // overrideTraitCollection 下发给宿主
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
        // 两 trait 下覆盖带与栏位落点不变（底衬是均
        // 匀材质、无文字，其几何不随字号/明暗变）
        let backdrop = host.traceBackdropView
        let backdropFrame = backdrop.convert(
            backdrop.bounds, to: window
        )
        let barFrame = host.traceBarView.convert(
            host.traceBarView.bounds, to: window
        )
        XCTAssertEqual(barFrame.minY, 62, accuracy: 0.6)
        XCTAssertEqual(backdropFrame.minY, 0, accuracy: 0.6)
        XCTAssertEqual(
            backdropFrame.maxY, barFrame.maxY, accuracy: 0.6
        )
        // 底衬在深色下仍是同一材质档（自适应变体随系
        // 统切档、定义点不换）
        XCTAssertTrue(backdrop is UIVisualEffectView)
    }
}
