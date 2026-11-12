import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 0.50.24 严重回归诊断探针（hotfix/05024-bars）：聊天页
/// 顶栏胶囊＋铃铛与底部输入舱在真机整体消失、单测全绿
/// 未拦住——两包（§185 背景全出血／§186 输入舱承载换
/// 代）各自的探针都没组装过真实聊天页整页。本探针以
/// 生产根 RootView（演示已连接态）＋真实 DrawerCont-
/// ainer＋真实 TabView＋真实 ChatView 整页装配， dump
/// 视图层级与关键帧（BARPROBE 前缀），供二分定因读数；
/// 断言只锁装配成立，栏位存在性结论由日志裁决后另立
/// 回归测试钉死。
@MainActor
final class ChatPageAssemblyProbeTests: XCTestCase {

    /// 与 TabBarFloatTests 同口径的设备窗：402×874、
    /// 安全区覆写 top 59／bottom 34（真机同值）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!

    override func tearDown() async throws {
        window?.rootViewController = nil
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

    /// 生产整页装配：RootView（演示已连接）→
    /// ContentView → DrawerContainer 桥 →
    /// DrawerContainerController → TabView → ChatView
    private func assembleProductionPage() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        let host = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 2.0)
        window.layoutIfNeeded()
    }

    private func fmt(_ r: CGRect) -> String {
        String(
            format: "(%.0f,%.0f %.0fx%.0f)",
            r.minX, r.minY, r.width, r.height
        )
    }

    private func dumpView(
        _ view: UIView, depth: Int, lines: inout [String]
    ) {
        guard lines.count < 700 else { return }
        let frame = view.convert(view.bounds, to: window)
        let indent = String(repeating: "  ", count: depth)
        lines.append(
            "\(indent)\(String(describing: type(of: view))) "
                + "f=\(fmt(frame)) hid=\(view.isHidden) "
                + "a=\(String(format: "%.2f", view.alpha))"
        )
        for sub in view.subviews {
            dumpView(sub, depth: depth + 1, lines: &lines)
        }
    }

    func testDumpProductionChatPageAssembly() throws {
        try assembleProductionPage()

        // 控制器链定位（ComposerGuideHost 按类名字符串匹配，
        // 使探针在 §186 回退变体里也能编译运行）
        var drawerContainer: DrawerContainerController?
        var composerHosts: [UIViewController] = []
        func findVC(_ vc: UIViewController) {
            if let found = vc as? DrawerContainerController {
                drawerContainer = found
            }
            if String(describing: type(of: vc))
                .contains("ComposerGuideHost")
            {
                composerHosts.append(vc)
            }
            for child in vc.children { findVC(child) }
        }
        if let root = window.rootViewController { findVC(root) }
        XCTAssertNotNil(
            drawerContainer, "生产桥链未装配：DrawerContainerController 缺席"
        )
        print(
            "BARPROBE| composerHostCount=\(composerHosts.count)"
        )
        for (i, host) in composerHosts.enumerated() {
            let vf = host.view.convert(host.view.bounds, to: window)
            print(
                "BARPROBE| composerHost[\(i)] viewFrame=\(fmt(vf))"
            )
            for child in host.children {
                let cf = child.view.convert(
                    child.view.bounds, to: window
                )
                print(
                    "BARPROBE| composerHost[\(i)] child "
                        + "\(String(describing: type(of: child))) "
                        + "frame=\(fmt(cf))"
                )
            }
        }

        // 滚动面与坞
        func walkViews(_ view: UIView) {
            if let sv = view as? UIScrollView {
                let f = sv.convert(sv.bounds, to: window)
                print(
                    "BARPROBE| scroll f=\(fmt(f)) "
                        + "adjInset t=\(sv.adjustedContentInset.top) "
                        + "b=\(sv.adjustedContentInset.bottom)"
                )
            }
            if let bar = view as? UITabBar {
                let f = bar.convert(bar.bounds, to: window)
                print("BARPROBE| tabBar f=\(fmt(f))")
            }
            for sub in view.subviews { walkViews(sub) }
        }
        walkViews(window)

        // 整树 dump（供人工定位两栏宿主在不在、帧如何）
        var lines: [String] = []
        dumpView(window, depth: 0, lines: &lines)
        print("BARPROBE| dump lines=\(lines.count)")
        for line in lines { print("BARPROBE| \(line)") }
    }
}
