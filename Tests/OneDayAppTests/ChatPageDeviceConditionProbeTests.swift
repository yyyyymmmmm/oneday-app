import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 0.50.25 真机复测仍翻车·第二轮定因探针（hotfix/05025-bars2）
/// 出身，§196 栏位案结案后瘦身：六个分场景二分探针已
/// 退役（见下方 MARK 注），本文件自此只承 §193 锚定不
/// 变量关（testAnchoredBarsSurviveGrowthAndFramePollu-
/// tion）与其装配脚手架——锚定构造的常驻回归守卫，不
/// 再是定因工具。装配条件（设备窗覆写 59/34、长会话落
/// 盘恢复等）沿探针时代实证形态保留。
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

        // §195：pocket 落点换代（顶簇锚定宿主视图；
        // elements 改数玻璃交互视图，口径同装配关一）
        let pocket = findVC(
            TopBarGuideHostController.self
        )?.traceBarView
        var pocketElements = 0
        if let pocket {
            lines.append("pocket: \(fmt(frameInWindow(pocket)))")
            pocketElements = findViews(pocket) { view in
                String(describing: type(of: view))
                    .contains("UIPlatformGlassInteractionView")
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
        }.first as? UIScrollView
        if let scroll {
            let scrollFrame: CGRect = frameInWindow(scroll)
            let insetTop: Int = Int(scroll.adjustedContentInset.top)
            let insetBottom: Int = Int(
                scroll.adjustedContentInset.bottom
            )
            let contentH: Int = Int(scroll.contentSize.height)
            lines.append(
                "chatScroll: \(fmt(scrollFrame))"
                    + " adjInset top=\(insetTop)"
                    + " bottom=\(insetBottom)"
                    + " contentSize=\(contentH)"
            )
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
            pocketElements, 2,
            "[\(scenario)] 顶栏元素不足（两端玻璃钮）\n\(dump)"
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

    /// §193 锚定不变量量测：pocket 帧＋输入舱玻璃条
    /// 帧（与 dumpAndAssert 同找法，只取数不断言，
    /// 供跨阶段对读）
    private func measureBars() -> (
        pocket: CGRect?, bar: CGRect?
    ) {
        let pocket = findVC(
            TopBarGuideHostController.self
        ).map { frameInWindow($0.traceBarView) }
        let bar = findViews(window) { view in
            String(describing: type(of: view))
                .contains("UIPlatformGlassInteractionView")
                && frameInWindow(view).width > 300
        }.first.map { frameInWindow($0) }
        return (pocket, bar)
    }

    // MARK: - 场景（二分探针已退役）
    //
    // §196：六个分场景定因探针（Baseline/Dark/
    // BoldAX/LongThread/SceneWindow/RealDevice-
    // Combo）随栏位案结案退役——其职（真机条件二
    // 分复现）已了，栏位在场与浮空带的常驻回归由
    // ChatPageAssemblyRegressionTests 四关＋本文件
    // 下方 §193 锚定不变量关承接。

    /// §193 锚定不变量（本轮修复成立的最低证据）：
    /// 两相注入下舱底锚点与 pocket 位置不许漂移——
    /// 一相以 trait 覆写把舱内容固有高撑大（本套件
    /// 既有量级：玻璃条 46→75；真机动态证据同型：
    /// 条高 +61 时旧构造盒高 +63 同涨出屏）；二相
    /// 把舱宿主控制器视图帧强制写成真机坏帧
    /// (0,-89,402×1030)（148/149 实测帧——旧构造
    /// 下其地板钳制会把舱钉到屏外上方，真机实证）。
    /// 新构造下舱底由窗口层级的坞锚决定、与宿主帧
    /// 及内容固有高均无关。红侧证据＝148/149 真机
    /// 自述（模拟器旧构造本就健康，本测试对旧构造
    /// 不必然红——它 gate 的是新构造的不变量本身）
    func testAnchoredBarsSurviveGrowthAndFramePollution() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer(fileBacked: true)
        let threadID = seedLongThread(
            into: container, appState: appState
        )
        let assembly = try assemble(
            sceneWindow: true, dark: false, boldAX: false,
            seededThreadID: threadID,
            container: container, appState: appState
        )
        dumpAndAssert(
            scenario: "anchorBase", assembly: assembly,
            strictBands: false
        )
        let base = measureBars()
        let basePocket = try XCTUnwrap(
            base.pocket, "基线 pocket 缺席"
        )
        let baseBar = try XCTUnwrap(
            base.bar, "基线舱条缺席"
        )

        // 一相：固有高注入（trait 覆写，与 boldAX
        // 场景同一杠杆的事后施加形态）
        assembly.host.traitOverrides.legibilityWeight = .bold
        assembly.host.traitOverrides
            .preferredContentSizeCategory =
            .accessibilityExtraExtraLarge
        window.traitOverrides.legibilityWeight = .bold
        window.traitOverrides.preferredContentSizeCategory =
            .accessibilityExtraExtraLarge
        spinRunLoop(seconds: 2.0)
        window.layoutIfNeeded()
        let grown = measureBars()
        let grownPocket = try XCTUnwrap(
            grown.pocket, "生长后 pocket 缺席"
        )
        let grownBar = try XCTUnwrap(
            grown.bar, "生长后舱条缺席"
        )
        XCTAssertGreaterThanOrEqual(
            grownBar.height - baseBar.height, 20,
            "注入未生效：玻璃条高未明显生长 "
                + "\(baseBar.height)→\(grownBar.height)"
        )
        XCTAssertEqual(
            grownBar.maxY, baseBar.maxY, accuracy: 2,
            "固有高生长下舱底锚点漂移："
                + "\(baseBar.maxY)→\(grownBar.maxY)"
        )
        XCTAssertEqual(
            grownPocket.minY, basePocket.minY, accuracy: 1,
            "固有高生长下 pocket 漂移："
                + "\(basePocket.minY)→\(grownPocket.minY)"
        )

        // 二相：宿主帧污染（真机坏帧复刻；同步一拍
        // 布局后即测，不等运行循环里的重排覆盖）
        let composer = try XCTUnwrap(
            findVC(ComposerGuideHostController.self),
            "ComposerGuideHostController 缺席"
        )
        composer.view.frame = CGRect(
            x: 0, y: -89, width: 402, height: 1030
        )
        window.layoutIfNeeded()
        let polluted = measureBars()
        let pollutedBar = try XCTUnwrap(
            polluted.bar, "污染帧下舱条缺席"
        )
        let pollutedPocket = try XCTUnwrap(
            polluted.pocket, "污染帧下 pocket 缺席"
        )
        XCTAssertEqual(
            pollutedBar.maxY, grownBar.maxY, accuracy: 2,
            "宿主帧污染下舱底锚点漂移："
                + "\(grownBar.maxY)→\(pollutedBar.maxY)"
        )
        XCTAssertEqual(
            pollutedPocket.minY, grownPocket.minY, accuracy: 1,
            "宿主帧污染下 pocket 漂移："
                + "\(grownPocket.minY)→\(pollutedPocket.minY)"
        )
        print("PROBE-DUMP anchorInvariant"
            + " base bar=\(fmt(baseBar))"
            + " pocket=\(fmt(basePocket))"
            + " | grown bar=\(fmt(grownBar))"
            + " | polluted bar=\(fmt(pollutedBar))"
            + " pocket=\(fmt(pollutedPocket))")
    }
}
