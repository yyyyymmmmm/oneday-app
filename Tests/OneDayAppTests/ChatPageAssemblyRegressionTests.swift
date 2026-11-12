import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 0.50.24 严重回归整页组装回归测试（hotfix/05024-bars）：
/// 真机 0.50.24 聊天页顶栏胶囊＋铃铛与底部输入舱整体
/// 消失，而 §185／§186 各自的隔离探针全绿——盲区在
/// 「没人组装过真实整页」。本测试以生产 RootView 整页
/// 装配（演示已连接态→DrawerContainer→TabView→
/// ChatView），四关同锁，任一回潮先红：
/// ①两栏在层级内、帧非零、输入舱底边贴坞上方；
/// ②症一不回潮：消息列表帧全出血（0→窗高）、顶栏
/// 空间以 adjustedContentInset 形式预留（§185 判据）；
/// ③症三浮空落带：坞玻璃盘下缘距屏底 20–27pt；
/// ④键盘变体：键盘升起时只有输入舱跟走（底边贴键盘
/// 顶）、导航坞帧与无键盘时一致（留在屏底）。
@MainActor
final class ChatPageAssemblyRegressionTests: XCTestCase {

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

    // MARK: - 层级定位助手

    private func frameInWindow(_ view: UIView) -> CGRect {
        view.convert(view.bounds, to: window)
    }

    private func fmt(_ r: CGRect) -> String {
        String(
            format: "(%.0f,%.0f %.0fx%.0f)",
            r.minX, r.minY, r.width, r.height
        )
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

    private func findComposerHost() -> UIViewController? {
        var found: UIViewController?
        func walk(_ vc: UIViewController) {
            if String(describing: type(of: vc))
                .contains("ComposerGuideHost")
            {
                found = vc
            }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }
        return found
    }

    /// 顶栏 pocket 承载（safeAreaBar 的 UIKit 落点）
    private func findTopPocketBar() -> UIView? {
        findViews(window) { view in
            String(describing: type(of: view))
                .contains("ScrollPocketBarInteraction")
                && frameInWindow(view).width > 400
                && frameInWindow(view).minY < 100
        }.first
    }

    /// 输入舱玻璃条（宿主子树内宽 >300 的玻璃交互视图）
    private func findComposerBar(in host: UIViewController) -> UIView? {
        findViews(host.view) { view in
            String(describing: type(of: view))
                .contains("UIPlatformGlassInteractionView")
                && frameInWindow(view).width > 300
        }.first
    }

    private func findComposerTextView(
        in host: UIViewController
    ) -> UITextView? {
        findViews(host.view) { view in
            view is UITextView && frameInWindow(view).width > 200
        }.first as? UITextView
    }

    private func findTabBar() -> UITabBar? {
        findViews(window) { $0 is UITabBar }.first as? UITabBar
    }

    private func findTabPlatter() -> UIView? {
        findViews(window) { view in
            String(describing: type(of: view))
                .contains("UITabBarPlatterView")
        }.first
    }

    /// 聊天消息列表（宽 402 的 HostingScrollView）
    private func findChatScrollView() -> UIScrollView? {
        findViews(window) { view in
            view is UIScrollView
                && String(describing: type(of: view))
                    .contains("HostingScrollView")
                && frameInWindow(view).width > 400
        }.first as? UIScrollView
    }

    // MARK: - 关一至三：静止态组装

    func testChatPageBarsAssembledOnProductionPage() throws {
        try assembleProductionPage()

        // ① 顶栏：pocket 承载在层级内、帧非零、内含
        // 至少 3 个 pocket 元素（胶囊行＋两端玻璃钮）
        let pocket = try XCTUnwrap(
            findTopPocketBar(), "顶栏 safeAreaBar 承载缺席"
        )
        let pocketFrame = frameInWindow(pocket)
        XCTAssertGreaterThanOrEqual(pocketFrame.height, 40)
        XCTAssertLessThanOrEqual(pocketFrame.minY, 62)
        let elements = findViews(pocket) { view in
            String(describing: type(of: view))
                .contains("ScrollPocketElementInteraction")
                && frameInWindow(view).width >= 20
                && frameInWindow(view).height >= 20
        }
        XCTAssertGreaterThanOrEqual(
            elements.count, 3, "顶栏元素不足：胶囊/铃铛未组装"
        )

        // ① 输入舱：宿主在场、玻璃条帧非零、底边贴坞上方
        let host = try XCTUnwrap(
            findComposerHost(), "ComposerGuideHost 缺席"
        )
        let bar = try XCTUnwrap(
            findComposerBar(in: host), "输入舱玻璃条缺席"
        )
        let barFrame = frameInWindow(bar)
        XCTAssertGreaterThanOrEqual(barFrame.height, 40)
        XCTAssertNotNil(
            findComposerTextView(in: host), "输入舱文本视图缺席"
        )
        let platter = try XCTUnwrap(findTabPlatter(), "导航坞缺席")
        let platterFrame = frameInWindow(platter)
        let gap = platterFrame.minY - barFrame.maxY
        XCTAssertTrue(
            (0...20).contains(gap),
            "输入舱底边与坞顶间距异常：\(gap)"
        )

        // ② 症一不回潮：列表帧全出血到窗上下缘、顶栏
        // 空间以内容 inset 预留（内容流到栏下）
        let scroll = try XCTUnwrap(
            findChatScrollView(), "聊天消息列表缺席"
        )
        let scrollFrame = frameInWindow(scroll)
        XCTAssertEqual(scrollFrame.minY, 0, accuracy: 1)
        XCTAssertEqual(
            scrollFrame.maxY, window.frame.height, accuracy: 1
        )
        XCTAssertTrue(
            (110...130).contains(scroll.adjustedContentInset.top),
            "顶栏预留 inset 异常：\(scroll.adjustedContentInset.top)"
        )

        // ③ 症三浮空落带：坞玻璃盘下缘距屏底 20–27pt
        let float = window.frame.height - platterFrame.maxY
        XCTAssertTrue(
            (20...27).contains(float),
            "坞浮空出带：\(float)（应在 20–27）"
        )
    }

    // MARK: - 关四：键盘变体

    func testKeyboardUpMovesComposerOnlyDockStays() throws {
        // 键盘引导线跟的是窗口场景的键盘：测试窗须附着
        // 到 App 的 UIWindowScene（裸 UIWindow(frame:)
        // 无场景时引导线永不驱动——前轮实测舱只落到
        // 「坞隐藏」位 832 而键盘不起，即此故）。
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
        let rootHost = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first,
            "测试宿主无 UIWindowScene，键盘变体无从验起"
        )
        window = DeviceWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = rootHost
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 2.0)
        window.layoutIfNeeded()
        print(
            "KBPROBE| sceneWindow insets "
                + "t=\(window.safeAreaInsets.top) "
                + "b=\(window.safeAreaInsets.bottom)"
        )
        let host = try XCTUnwrap(findComposerHost())
        let bar = try XCTUnwrap(findComposerBar(in: host))
        let textView = try XCTUnwrap(
            findComposerTextView(in: host)
        )
        let platter = try XCTUnwrap(findTabPlatter())
        let tabBar = try XCTUnwrap(findTabBar())
        let baselineBar = frameInWindow(bar)
        let baselinePlatter = frameInWindow(platter)
        let baselineTabBar = frameInWindow(tabBar)

        let frOK = textView.becomeFirstResponder()
        print("KBPROBE| becomeFirstResponder=\(frOK) isFR=\(textView.isFirstResponder)")
        for (i, win) in UIApplication.shared.windows.enumerated() {
            print("KBPROBE| window[\(i)] \(String(describing: type(of: win))) f=\(win.frame) level=\(win.windowLevel.rawValue)")
        }
        XCTAssertTrue(
            frOK,
            "输入框未能成为第一响应者，键盘变体无从验起"
        )
        // 等键盘升起带动输入舱上移（轮询至多 10 秒）
        var moved = false
        for tick in 0..<20 {
            spinRunLoop(seconds: 0.5)
            window.layoutIfNeeded()
            if tick % 4 == 0 {
                var kbFound = false
                for win in UIApplication.shared.windows {
                    let hits = findViews(win) { v in
                        String(describing: type(of: v)).contains("Keyboard")
                    }
                    if !hits.isEmpty { kbFound = true }
                }
                var kbFrames: [String] = []
                for win in UIApplication.shared.windows {
                    for v in findViews(win) { x in
                        String(describing: type(of: x)).contains("Keyboard")
                    } {
                        let f = v.convert(v.bounds, to: window)
                        if f.height > 50 {
                            kbFrames.append("\(fmt(f))")
                        }
                    }
                }
                print("KBPROBE| tick=\(tick) barMaxY=\(frameInWindow(bar).maxY) kbViews=\(kbFound) kbFrames=\(kbFrames) windows=\(UIApplication.shared.windows.count)")
            }
            if frameInWindow(bar).maxY < baselineBar.maxY - 150 {
                moved = true
                break
            }
        }
        XCTAssertTrue(
            moved, "键盘升起后输入舱未跟随上移（引导线未驱动）"
        )

        // 输入舱底边贴键盘顶（键盘视图在任意窗口内定位）
        var keyboardTop: CGFloat?
        for win in UIApplication.shared.windows {
            let hits = findViews(win) { view in
                let name = String(describing: type(of: view))
                return (name.contains("UIKeyboard")
                    || name.contains("UIRemoteKeyboard"))
                    && view.convert(view.bounds, to: window).height
                        > 100
            }
            if let kb = hits.first {
                keyboardTop = kb.convert(kb.bounds, to: window).minY
            }
        }
        if let keyboardTop {
            let barBottom = frameInWindow(bar).maxY
            XCTAssertEqual(
                barBottom, keyboardTop, accuracy: 24,
                "输入舱底边未贴键盘顶：舱 \(barBottom) 键盘 \(keyboardTop)"
            )
        }

        // 导航坞帧与无键盘时一致：留在屏底、不跟键盘走
        XCTAssertEqual(
            frameInWindow(platter), baselinePlatter,
            "键盘升起时导航坞跟着上移了"
        )
        XCTAssertEqual(
            frameInWindow(tabBar), baselineTabBar,
            "键盘升起时 TabBar 帧变化"
        )
    }
}
