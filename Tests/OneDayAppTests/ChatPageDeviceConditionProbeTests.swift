import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 0.50.25 真机复测仍翻车·第二轮定因探针（hotfix/05025-bars2）：
/// 第一轮组装探针（ChatPageAssemblyRegressionTests）在
/// 「Demo 客户端＋内存空库＋默认 trait＋裸窗覆写安全区」
/// 条件下全绿，但真机（深色＋系统粗体＋真实长会话＋
/// 持久化冷启恢复落点）上胶囊/输入舱/抽屉三件集体缺
/// 席。本探针把装配条件逐项推向真机，分场景二分：
/// 每场景全量量测打印（PROBE-DUMP 前缀，CI 日志可捞），
/// 栏位缺席即红——先复现、再定因，不许拿探针绿当结论。
@MainActor
final class ChatPageDeviceConditionProbeTests: XCTestCase {

    /// 与既有组装探针同款设备窗（安全区覆写 59/34）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: UIWindow!

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

    // MARK: - 场景装配

    private struct Assembly {
        var appState: AppState
        var container: ModelContainer
        var host: UIHostingController<AnyView>
    }

    /// 落盘库播种一条长会话（160 条、长段落，贴近真机
    /// 截图里的壁挂炉长文形态）：数据先于视图存在，
    /// 装配后经 ChatLandingResolution 的恢复落点进入
    private func seedLongThread(
        into container: ModelContainer, appState: AppState
    ) -> UUID {
        let context = ModelContext(container)
        let thread = ChatThread(title: "壁挂炉选型")
        context.insert(thread)
        let longParagraph = """
        但有一条必须盯死：最低输出功率。86 平米采暖只要 \
        7～9kW，如果你买的炉子最小火就是 7kW 甚至更高，它就会不停地 \
        开开关关，费气、有噪音、还伤机器。选最低输出 ≤4kW 的冷凝炉，\
        最好能到 3kW 出头，这样大部分时间它都稳在低火运行。\
        这一条比牌子重要。照单抓药，买的时候问商家这几项：\
        型式是燃气冷凝两用炉，采暖加生活热水一体。\
        额定 24kW，最低输出功率 ≤4kW。采暖水温能调到 \
        40～50°C（地暖专用低温档），最好支持室外温度补偿。
        """
        let base = Date().addingTimeInterval(-6 * 3600)
        for index in 0..<160 {
            let isUser = index % 2 == 0
            let entry = ChatEntry(
                role: isUser ? "user" : "assistant",
                content: isUser
                    ? "第 \(index / 2 + 1) 问：这个参数再确认一下。"
                    : longParagraph,
                thread: thread
            )
            entry.createdAt = base
                .addingTimeInterval(Double(index * 61))
            context.insert(entry)
        }
        thread.createdAt = base
        thread.updatedAt = base.addingTimeInterval(160 * 61)
        try? context.save()
        // 冷启落点：上次线程＝这条长会话（真实恢复路径）
        appState.sideChats.setLastThreadID(thread.id)
        return thread.id
    }

    private func assemble(
        sceneWindow: Bool,
        dark: Bool,
        boldAX: Bool,
        seededThreadID: UUID?,
        container: ModelContainer,
        appState: AppState
    ) throws -> Assembly {
        let host = UIHostingController(
            rootView: AnyView(
                RootView()
                    .environment(appState)
                    .environment(\.locale, AppLocale.uiLocale)
                    .modelContainer(container)
            )
        )
        if sceneWindow {
            let scene = try XCTUnwrap(
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }.first,
                "测试宿主无 UIWindowScene"
            )
            let win = UIWindow(windowScene: scene)
            win.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window = win
        } else {
            window = DeviceWindow(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
        }
        if dark {
            window.overrideUserInterfaceStyle = .dark
            host.overrideUserInterfaceStyle = .dark
        }
        if boldAX {
            host.traitOverrides.legibilityWeight = .bold
            host.traitOverrides.preferredContentSizeCategory =
                .accessibilityExtraExtraLarge
            window.traitOverrides.legibilityWeight = .bold
            window.traitOverrides.preferredContentSizeCategory =
                .accessibilityExtraExtraLarge
        }
        _ = seededThreadID
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: seededThreadID == nil ? 2.5 : 3.5)
        window.layoutIfNeeded()
        return Assembly(
            appState: appState, container: container, host: host
        )
    }

    private func makeContainer(
        fileBacked: Bool
    ) throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        if fileBacked {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "probe-\(UUID().uuidString)", isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            let url = dir.appendingPathComponent("store.sqlite")
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(
                    schema: schema, url: url
                )]
            )
        }
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    // MARK: - 层级定位（与组装探针同口径）

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

    private func findVC<T: UIViewController>(
        _ type: T.Type
    ) -> T? {
        var found: T?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? T { found = hit }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }
        return found
    }

    // MARK: - 量测倾印＋断言

    private func dumpAndAssert(
        scenario: String,
        assembly: Assembly,
        strictBands: Bool
    ) {
        var lines: [String] = []
        lines.append("=== PROBE-DUMP \(scenario) ===")
        lines.append("window \(fmt(window.frame)) "
            + "safeArea=\(window.safeAreaInsets)")

        let drawer = findVC(DrawerContainerController.self)
        lines.append("drawerVC: \(drawer == nil ? "缺席" : "在场")"
            + (drawer.map {
                " frame=\(fmt(frameInWindow($0.view)))"
                    + " semantic=\($0.semanticPresented)"
                    + " travel=\(Int($0.travel))"
            } ?? ""))

        let pocket = findViews(window) { view in
            String(describing: type(of: view))
                .contains("ScrollPocketBarInteraction")
                && frameInWindow(view).width > 400
                && frameInWindow(view).minY < 100
        }.first
        var pocketElements = 0
        if let pocket {
            lines.append("pocket: \(fmt(frameInWindow(pocket)))")
            pocketElements = findViews(pocket) { view in
                String(describing: type(of: view))
                    .contains("ScrollPocketElementInteraction")
                    && frameInWindow(view).width >= 20
                    && frameInWindow(view).height >= 20
            }.count
            lines.append("pocketElements: \(pocketElements)")
        } else {
            lines.append("pocket: 缺席")
        }

        let composer = findVC(ComposerGuideHostController.self)
        var barFrame: CGRect?
        if let composer {
            lines.append("composerVC: 在场 view="
                + "\(fmt(frameInWindow(composer.view)))")
            let bar = findViews(composer.view) { view in
                String(describing: type(of: view))
                    .contains("UIPlatformGlassInteractionView")
                    && frameInWindow(view).width > 300
            }.first
            if let bar {
                barFrame = frameInWindow(bar)
                lines.append("composerBar: \(fmt(barFrame!))")
            } else {
                lines.append("composerBar: 缺席")
            }
            let textViews = findViews(composer.view) {
                $0 is UITextView
            }
            lines.append("composerTextViews: \(textViews.count)")
        } else {
            lines.append("composerVC: 缺席")
        }

        let platter = findViews(window) { view in
            String(describing: type(of: view))
                .contains("UITabBarPlatterView")
        }.first
        if let platter {
            lines.append("platter: \(fmt(frameInWindow(platter)))")
        } else {
            lines.append("platter: 缺席")
        }

        let scroll = findViews(window) { view in
            view is UIScrollView
                && String(describing: type(of: view))
                    .contains("HostingScrollView")
                && frameInWindow(view).width > 400
        }.first
        if let scroll {
            lines.append("chatScroll: \(fmt(frameInWindow(scroll)))"
                + " adjInset top=\(Int(scroll.adjustedContentInset.top))"
                + " bottom=\(Int(scroll.adjustedContentInset.bottom))"
                + " contentSize=\(Int(scroll.contentSize.height))")
        } else {
            lines.append("chatScroll: 缺席")
        }

        let dump = lines.joined(separator: "\n")
        print(dump)
        add(XCTAttachment(string: dump))

        // 栏位在场断言（复现目标：任一缺席即红）
        XCTAssertNotNil(
            pocket, "[\(scenario)] 顶栏 pocket 缺席\n\(dump)"
        )
        XCTAssertGreaterThanOrEqual(
            pocketElements, 3,
            "[\(scenario)] 顶栏元素不足（胶囊/铃铛）\n\(dump)"
        )
        XCTAssertNotNil(
            composer, "[\(scenario)] 输入舱宿主缺席\n\(dump)"
        )
        XCTAssertNotNil(
            barFrame, "[\(scenario)] 输入舱玻璃条缺席\n\(dump)"
        )
        if strictBands, let barFrame, let platter {
            let gap = frameInWindow(platter).minY - barFrame.maxY
            XCTAssertTrue(
                (0...20).contains(gap),
                "[\(scenario)] 舱底与坞顶间距异常：\(gap)\n\(dump)"
            )
            let float = window.frame.height
                - frameInWindow(platter).maxY
            XCTAssertTrue(
                (20...27).contains(float),
                "[\(scenario)] 坞浮空出带：\(float)\n\(dump)"
            )
        }
    }

    // MARK: - 场景

    /// 对照：与现行组装探针同条件（裸窗覆写＋内存空库）
    func testScenarioBaselineControl() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer(fileBacked: false)
        let assembly = try assemble(
            sceneWindow: false, dark: false, boldAX: false,
            seededThreadID: nil,
            container: container, appState: appState
        )
        dumpAndAssert(
            scenario: "baseline", assembly: assembly,
            strictBands: true
        )
    }

    /// 深色单变量
    func testScenarioDarkOnly() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer(fileBacked: false)
        let assembly = try assemble(
            sceneWindow: false, dark: true, boldAX: false,
            seededThreadID: nil,
            container: container, appState: appState
        )
        dumpAndAssert(
            scenario: "dark", assembly: assembly, strictBands: true
        )
    }

    /// 粗体＋无障碍大字号单变量
    func testScenarioBoldAXOnly() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer(fileBacked: false)
        let assembly = try assemble(
            sceneWindow: false, dark: false, boldAX: true,
            seededThreadID: nil,
            container: container, appState: appState
        )
        dumpAndAssert(
            scenario: "boldAX", assembly: assembly,
            strictBands: false
        )
    }

    /// 长会话＋落盘恢复落点单变量（裸窗覆写、浅色默认字）
    func testScenarioLongThreadOnly() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer(fileBacked: true)
        let threadID = seedLongThread(
            into: container, appState: appState
        )
        let assembly = try assemble(
            sceneWindow: false, dark: false, boldAX: false,
            seededThreadID: threadID,
            container: container, appState: appState
        )
        dumpAndAssert(
            scenario: "longThread", assembly: assembly,
            strictBands: true
        )
    }

    /// 场景窗单变量（真安全区、无覆写；空库浅色）
    func testScenarioSceneWindowOnly() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer(fileBacked: false)
        let assembly = try assemble(
            sceneWindow: true, dark: false, boldAX: false,
            seededThreadID: nil,
            container: container, appState: appState
        )
        dumpAndAssert(
            scenario: "sceneWindow", assembly: assembly,
            strictBands: true
        )
    }

    /// 真机全组合：场景窗＋深色＋粗体/AX＋长会话落盘恢复，
    /// 另验抽屉容器挂载（程序化开抽屉看位移与抽屉面显形）
    func testScenarioRealDeviceCombo() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer(fileBacked: true)
        let threadID = seedLongThread(
            into: container, appState: appState
        )
        let assembly = try assemble(
            sceneWindow: true, dark: true, boldAX: true,
            seededThreadID: threadID,
            container: container, appState: appState
        )
        dumpAndAssert(
            scenario: "realDeviceCombo", assembly: assembly,
            strictBands: false
        )

        // 抽屉挂载：程序化开→前景应位移、抽屉面应显形
        let drawer = try XCTUnwrap(
            findVC(DrawerContainerController.self),
            "[realDeviceCombo] DrawerContainerController 缺席"
        )
        drawer.setDrawer(true, animated: false)
        spinRunLoop(seconds: 0.5)
        window.layoutIfNeeded()
        XCTAssertTrue(
            drawer.semanticPresented,
            "[realDeviceCombo] 开抽屉后语义未置位"
        )
        let shifted = drawer.view.subviews.contains { sub in
            sub.transform.tx > 200
                || frameInWindow(sub).minX > 200
        }
        print("PROBE-DUMP combo drawer shifted=\(shifted) "
            + "travel=\(Int(drawer.travel))")
        XCTAssertTrue(
            shifted,
            "[realDeviceCombo] 开抽屉后前景未位移（travel="
                + "\(Int(drawer.travel))）"
        )
    }
}
