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

    /// 顶簇锚定宿主控制器（§195 的 pocket 落点）
    private func findTopBarHost() -> TopBarGuideHostController? {
        var found: TopBarGuideHostController?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? TopBarGuideHostController {
                found = hit
            }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }
        return found
    }

    /// 顶栏 pocket 承载（§195 起为 TopBarGuideHost
    /// 的顶簇宿主视图；此前是 safeAreaBar 的 UIKit
    /// 落点 ScrollPocketBarInteraction，已退役）
    private func findTopPocketBar() -> UIView? {
        findTopBarHost()?.traceBarView
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
        // 两端玻璃钮的交互视图（胶囊背板玻璃按
        // §179 不生成交互视图、不计数）；纵坐标恒
        // 等于窗口顶安全区（§195 用户口径：任何帧
        // 恒定、动 1pt 不算过——本测试窗覆写 59）
        let pocket = try XCTUnwrap(
            findTopPocketBar(), "顶栏锚定宿主缺席"
        )
        let pocketFrame = frameInWindow(pocket)
        XCTAssertGreaterThanOrEqual(pocketFrame.height, 40)
        XCTAssertEqual(
            pocketFrame.minY, window.safeAreaInsets.top,
            accuracy: 1,
            "顶簇纵坐标必须恒为窗口顶安全区：\(pocketFrame.minY)"
        )
        let elements = findViews(pocket) { view in
            String(describing: type(of: view))
                .contains("UIPlatformGlassInteractionView")
                && frameInWindow(view).width >= 20
                && frameInWindow(view).height >= 20
        }
        XCTAssertGreaterThanOrEqual(
            elements.count, 2, "顶栏元素不足：两端玻璃钮未组装"
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

        XCTAssertTrue(
            textView.becomeFirstResponder(),
            "输入框未能成为第一响应者，键盘变体无从验起"
        )
        // 等键盘升起带动输入舱上移（轮询至多 10 秒）
        var moved = false
        for _ in 0..<20 {
            spinRunLoop(seconds: 0.5)
            window.layoutIfNeeded()
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
        // 硬失败口径（2026-11-12 Codex 审计 ext-20261112
        // -022 点名）：旧写法 `if let keyboardTop` 取不到
        // 键盘帧时静默跳过仍报过——假绿洞。取不到帧＝
        // 键盘未真升起或定位失败，本关无从验起，必须红
        let resolvedKeyboardTop = try XCTUnwrap(
            keyboardTop,
            "键盘已升起却定位不到键盘帧，贴键盘顶断言无从验起"
        )
        let barBottom = frameInWindow(bar).maxY
        XCTAssertEqual(
            barBottom, resolvedKeyboardTop, accuracy: 24,
            "输入舱底边未贴键盘顶：舱 \(barBottom) 键盘 \(resolvedKeyboardTop)"
        )

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

    // MARK: - 关五：命中路由（§194 取证）

    /// 点按路由取证（生产整页、window.hitTest 实测）：
    /// ①文本区中心点必须落进文本视图本体——透传门按
    /// Preference 舱帧放行舱带（该帧的原点此前从未被
    /// 独立验过，本关即其验收）；②列表区一点必须落
    /// 在舱宿主子树之外（透传门帧外放行、点空白收键
    /// 盘的手势作用域不缩）；③顶栏胶囊身份域一点必
    /// 须落在 pocket 承载带内、且不被舱宿主层截走
    /// ——缺陷②（点胶囊开错面）的归属取证：路由若在
    /// 此已错位，命中链当场打进失败信息；路由对而真
    /// 机开错面，根子在胶囊域内派发（胶囊线 §179/
    /// §153 在案），不在本分支
    func testHitRouting_textListAndPocketIdentity() throws {
        try assembleProductionPage()
        let host = try XCTUnwrap(findComposerHost())
        let hostView = try XCTUnwrap(host.view)
        let textView = try XCTUnwrap(
            findComposerTextView(in: host)
        )
        // ① 文本区
        let textPoint = textView.convert(
            CGPoint(
                x: textView.bounds.midX,
                y: textView.bounds.midY
            ), to: window
        )
        let textHit = window.hitTest(textPoint, with: nil)
        XCTAssertTrue(
            textHit === textView
                || isWithin(textHit, of: textView),
            "文本区命中未落进文本视图："
                + hitAncestry(of: textHit)
        )
        // ② 列表区（舱顶上方 120pt）
        let bar = try XCTUnwrap(findComposerBar(in: host))
        let barFrame = frameInWindow(bar)
        let listPoint = CGPoint(
            x: barFrame.midX, y: barFrame.minY - 120
        )
        let listHit = window.hitTest(listPoint, with: nil)
        XCTAssertNotNil(
            listHit, "列表区命中不应为空（滚动面应接点）")
        XCTAssertFalse(
            isWithin(listHit, of: hostView),
            "列表区命中被舱宿主层吞掉："
                + hitAncestry(of: listHit)
        )
        // ③ 胶囊身份域（胶囊行左起约 1/4 处＝头像＋
        // 名称状态域；模型域在行右段）
        let pocket = try XCTUnwrap(findTopPocketBar())
        let pocketFrame = frameInWindow(pocket)
        // §195：胶囊在 UIKit 层无独立落点视图（背板
        // 玻璃按 §179 不生成交互视图）——身份域点
        // 位改按几何推导：左玻璃钮（汉堡）右缘与顶
        // 簇横中点的中点，必落在居中胶囊的左半
        // （身份域）内
        let discs = findViews(pocket) { view in
            String(describing: type(of: view))
                .contains("UIPlatformGlassInteractionView")
                && frameInWindow(view).width >= 20
                && frameInWindow(view).height >= 20
        }.sorted {
            frameInWindow($0).minX < frameInWindow($1).minX
        }
        let leftDisc = try XCTUnwrap(
            discs.first, "pocket 内未定位到左玻璃钮"
        )
        let identityPoint = CGPoint(
            x: (frameInWindow(leftDisc).maxX
                + pocketFrame.midX) / 2,
            y: pocketFrame.midY
        )
        let identityHit = window.hitTest(
            identityPoint, with: nil
        )
        XCTAssertNotNil(
            identityHit, "胶囊身份域命中不应为空")
        XCTAssertFalse(
            isWithin(identityHit, of: hostView),
            "胶囊身份域命中被舱宿主层截走："
                + hitAncestry(of: identityHit)
        )
        if let identityHit {
            let hitFrame = frameInWindow(identityHit)
            XCTAssertTrue(
                hitFrame.intersects(
                    pocketFrame.insetBy(dx: -8, dy: -8)),
                "胶囊身份域命中落在 pocket 带外："
                    + "\(hitAncestry(of: identityHit)) "
                    + "帧 \(hitFrame) pocket \(pocketFrame)"
            )
        }
    }

    // MARK: - 关六：传播安全区被偷位（§195）

    /// §195 结构不变量（152 真机落定帧缺陷的同型模
    /// 拟）：页面传播安全区被重算偷走 49（以根宿主
    /// additionalSafeAreaInsets.top = −49 模拟藏坞
    /// 落定那一拍）时，顶簇纵坐标与列表顶 inset 必
    /// 须纹丝不动——顶簇只认窗口顶安全区、列表顶
    /// 留位只认实测 contentMargins，两者都不经传
    /// 播链。真机落定帧的最终判读仍以 153 自述
    /// kbShowSettled 帧 pocket 恒 62 为准，本关锁
    /// 的是「传播变化带不走顶簇」的结构事实
    func testTopClusterImmuneToPropagatedSafeAreaTheft()
        throws
    {
        try assembleProductionPage()
        let pocket = try XCTUnwrap(
            findTopPocketBar(), "顶栏锚定宿主缺席"
        )
        let scroll = try XCTUnwrap(
            findChatScrollView(), "聊天消息列表缺席"
        )
        let baselinePocketY = frameInWindow(pocket).minY
        let baselineAdjTop = scroll.adjustedContentInset.top
        XCTAssertEqual(
            baselinePocketY, window.safeAreaInsets.top,
            accuracy: 1
        )
        // 模拟落定偷位：根宿主附加安全区顶 −49
        let rootHost = try XCTUnwrap(
            window.rootViewController, "根宿主缺席"
        )
        rootHost.additionalSafeAreaInsets.top = -49
        window.layoutIfNeeded()
        spinRunLoop(seconds: 1.0)
        window.layoutIfNeeded()
        XCTAssertEqual(
            frameInWindow(pocket).minY, baselinePocketY,
            accuracy: 1,
            "传播安全区被偷 49 后顶簇纵坐标漂移："
                + "\(frameInWindow(pocket).minY)"
                + " vs \(baselinePocketY)"
        )
        XCTAssertEqual(
            scroll.adjustedContentInset.top, baselineAdjTop,
            accuracy: 1,
            "传播安全区被偷 49 后列表顶 inset 漂移："
                + "\(scroll.adjustedContentInset.top)"
                + " vs \(baselineAdjTop)"
        )
        rootHost.additionalSafeAreaInsets.top = 0
    }

    /// 命中点是否落在指定视图的子树内（含本体）
    private func isWithin(
        _ view: UIView?, of ancestor: UIView
    ) -> Bool {
        var node = view
        while let current = node {
            if current === ancestor { return true }
            node = current.superview
        }
        return false
    }

    /// 命中链取证串（类名自动中点上溯 6 层）
    private func hitAncestry(of view: UIView?) -> String {
        var parts: [String] = []
        var node = view
        while let current = node, parts.count < 6 {
            parts.append(
                String(describing: type(of: current)))
            node = current.superview
        }
        return parts.isEmpty
            ? "nil" : parts.joined(separator: " <- ")
    }
}
