import XCTest
@testable import OneDayApp
import OneDayCore
import UIKit

/// 全屏右滑返回桥钉测（呈现与导航手势审计
/// 2026-11-24 问题二）：UIKit 层装配与裁决用真
/// UINavigationController 装配台验——全屏 pan
/// 装上、系统边缘识别器关闭、delegate 裁决与
/// Core 谓词同表；H1 深度采集（卡内让行事实）
/// 用真层级验；五入口 cover 收编与栈根全覆盖
/// 走源码守护。
final class FullscreenPopBridgeTests: XCTestCase {

    private func spin(seconds: TimeInterval) {
        RunLoop.main.run(
            until: Date().addingTimeInterval(seconds)
        )
    }

    /// 装配台：窗口＋导航控制器（根页），返回已
    /// 入窗的导航控制器
    @MainActor
    private func makeNavigationRig() -> (
        window: UIWindow, nav: UINavigationController
    ) {
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let nav = UINavigationController(
            rootViewController: UIViewController()
        )
        window.rootViewController = nav
        window.makeKeyAndVisible()
        spin(seconds: 0.3)
        return (window, nav)
    }

    /// 桥的全屏 pan（以 delegate 类型辨识，区别于
    /// 系统边缘识别器）
    private func bridgePan(
        in nav: UINavigationController
    ) -> UIPanGestureRecognizer? {
        nav.view.gestureRecognizers?
            .compactMap { $0 as? UIPanGestureRecognizer }
            .first { $0.delegate is FullscreenPopController }
    }

    // MARK: - 装配

    @MainActor
    func testEquipInstallsFullscreenPanAndDisablesEdgePop() {
        let (window, nav) = makeNavigationRig()
        defer { window.isHidden = true }
        FullscreenPopController.equip(nav)
        XCTAssertNotNil(
            bridgePan(in: nav),
            "装配后导航视图上须有桥的全屏 pan"
        )
        XCTAssertEqual(
            nav.interactivePopGestureRecognizer?.isEnabled,
            false,
            "全屏 pan 接管后系统边缘识别器须关闭防双驱动"
        )
        // 幂等：重复装配不叠第二枚
        FullscreenPopController.equip(nav)
        let pans = nav.view.gestureRecognizers?
            .compactMap { $0 as? UIPanGestureRecognizer }
            .filter { $0.delegate is FullscreenPopController }
        XCTAssertEqual(pans?.count, 1)
    }

    // MARK: - delegate 裁决（与 Core 谓词同表）

    @MainActor
    func testDelegateAdjudicationMatchesPolicy() {
        let (window, nav) = makeNavigationRig()
        defer { window.isHidden = true }
        FullscreenPopController.equip(nav)
        guard let pan = bridgePan(in: nav),
              let delegate = pan.delegate
                as? FullscreenPopController
        else {
            XCTFail("桥未装配")
            return
        }
        let probe = UIPanGestureRecognizer()
        func begins(
            _ translation: CGPoint
        ) -> Bool {
            probe.setTranslation(translation, in: nav.view)
            return delegate.gestureRecognizerShouldBegin(probe)
        }
        // 栈深 1（根页）：右滑横向也不触发
        XCTAssertFalse(begins(CGPoint(x: 40, y: 6)))
        // 下钻一层：右向横向主导放行
        nav.setViewControllers(
            [UIViewController(), UIViewController()],
            animated: false
        )
        XCTAssertTrue(begins(CGPoint(x: 40, y: 6)))
        // 纵向主导让行滚动、左向不触发
        XCTAssertFalse(begins(CGPoint(x: 6, y: 40)))
        XCTAssertFalse(begins(CGPoint(x: -40, y: 6)))
    }

    // MARK: - 豁免区

    @MainActor
    func testExemptionHitTestUsesMarkerFrames() {
        let root = UIView(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let marker = FullscreenPopExemptMarkerView(
            frame: CGRect(x: 100, y: 200, width: 120, height: 80)
        )
        root.addSubview(marker)
        XCTAssertTrue(FullscreenPopExemption
            .hierarchyContainsMarker(
                in: root, at: CGPoint(x: 150, y: 240)
            ))
        XCTAssertFalse(FullscreenPopExemption
            .hierarchyContainsMarker(
                in: root, at: CGPoint(x: 20, y: 20)
            ))
        // 嵌套层级内的标记同判
        let container = UIView(
            frame: CGRect(x: 0, y: 400, width: 402, height: 200)
        )
        let nested = FullscreenPopExemptMarkerView(
            frame: CGRect(x: 10, y: 10, width: 50, height: 50)
        )
        container.addSubview(nested)
        root.addSubview(container)
        XCTAssertTrue(FullscreenPopExemption
            .hierarchyContainsMarker(
                in: root, at: CGPoint(x: 30, y: 430)
            ))
    }

    // MARK: - H1 深度采集

    @MainActor
    func testHubCardDepthProbeReadsInnerStackDepth() {
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let host = UIViewController()
        let innerNav = UINavigationController(
            rootViewController: UIViewController()
        )
        host.addChild(innerNav)
        host.view.addSubview(innerNav.view)
        innerNav.view.frame = host.view.bounds
        innerNav.didMove(toParent: host)
        let anchor = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        host.view.addSubview(anchor)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        spin(seconds: 0.3)

        XCTAssertEqual(
            HubCardDepthProbe.hostingRootView(of: anchor),
            host.view,
            "锚点上溯的首个控制器根视图须是呈现宿主层"
        )
        XCTAssertEqual(
            HubCardDepthProbe.maxNavigationDepth(fromAnchor: anchor),
            1,
            "卡内栈在根层时深度为 1（关卡不让行）"
        )
        innerNav.setViewControllers(
            [UIViewController(), UIViewController()],
            animated: false
        )
        XCTAssertEqual(
            HubCardDepthProbe.maxNavigationDepth(fromAnchor: anchor),
            2,
            "卡内下钻后深度为 2（关卡须让行）"
        )
    }

    // MARK: - 源码守护（收编与全覆盖）

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    private func codeLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let t = line.trimmingCharacters(
                    in: .whitespaces
                )
                return !t.hasPrefix("///") && !t.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    /// H2：四格入中枢只许 cover（同一宿主），push
    /// 入中枢的代码行零残留；置位走统一呈现点
    func testFourTabsPresentHubByCoverOnly() throws {
        for file in [
            "FeedView", "IdeasView", "GoalsView",
            "DeliverablesView",
        ] {
            let code = try codeLines(source(
                "Sources/OneDayApp/\(file).swift"
            ))
            XCTAssertFalse(
                code.contains(
                    "navigationDestination(isPresented: $showHub)"
                ),
                "\(file) 不许再 push 入中枢"
            )
            XCTAssertTrue(
                code.contains(".hubCover(isPresented: $showHub)"),
                "\(file) 须挂统一 cover 修饰位"
            )
            XCTAssertTrue(
                code.contains("HubCoverPresenter.present"),
                "\(file) 开中枢须走统一呈现点"
            )
        }
    }

    /// H1：卡片宿主的关卡手势须过让行裁决（深度
    /// 采集＋Core 谓词），不许无条件接管
    func testHubCardHostGatesDragByInnerDepth() throws {
        let code = try codeLines(source(
            "Sources/OneDayApp/HubCardPresentation.swift"
        ))
        XCTAssertTrue(code.contains("allowsCardDrag"))
        XCTAssertTrue(code.contains("yieldedToInnerStack"))
        XCTAssertTrue(code.contains("HubCardDepthProbe"))
    }

    /// 全覆盖：凡有 NavigationStack 构造的文件必
    /// 挂桥修饰（逐页零手搓、栈根一处接入）；新
    /// 栈漏挂在此红
    func testEveryNavigationStackFileHasBridge() throws {
        let dir = repoRoot()
            .appendingPathComponent("Sources/OneDayApp")
        let files = try FileManager.default
            .contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
        var offenders: [String] = []
        for file in files {
            let code = try codeLines(source(
                "Sources/OneDayApp/\(file)"
            ))
            let hasStack = code.contains("NavigationStack {")
                || code.contains("NavigationStack(")
            if hasStack && !code.contains("fullscreenPopBridge()") {
                offenders.append(file)
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "有栈未挂桥：\(offenders)"
        )
    }
}
