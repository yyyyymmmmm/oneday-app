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
///
/// 2026-11-14 注入失稳修线（fix/bar-probe-injection）：
/// 本关在 2026-11-13/14 五轮 CI 里三度以逐字相同的值
/// 失败（舱条 46→52、帧 (-40,784 398x52)，锚点 783→
/// 836），两轮通过（46→75）。定因见 oneday-design-
/// review/bar-probe-injection-fix-20261113.md：AX5 覆
/// 写未稳定到达舱量测链（文本视图 trait＋Layout 注入
/// 档），而顶簇同轮正常生长；量测改为舱宿主子树内取
/// 数＋前置条件轮询＋落定后读数，断言口径（生长 ≥20、
/// 锚点 ±2、pocket ±1）与守卫的 §193 不变量一字未动。
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
        // 舱条只在舱宿主子树内找（组装回归测试
        // findComposerBar 同口径；2026-11-14 修线：
        // 全窗首匹配在注入失稳态下曾读到 (-40,784
        // 398x52)——对 §194 坞锚几何不可能的帧，祖
        // 先身份是唯一的量测口径；子树内无匹配即
        // 精确失败，不静默回落全窗）
        let bar = findVC(
            ComposerGuideHostController.self
        ).flatMap { composer in
            findViews(composer.view) { view in
                String(describing: type(of: view))
                    .contains("UIPlatformGlassInteractionView")
                    && frameInWindow(view).width > 300
            }.first.map { frameInWindow($0) }
        }
        return (pocket, bar)
    }

    /// 舱内输入框文本视图（量测链的直接输入：其 trait
    /// 档决定 ComposerTextMetrics 的量测字体；修线
    /// 前置条件的读数点）
    private func composerTextView() -> UITextView? {
        guard let composer = findVC(
            ComposerGuideHostController.self
        ) else {
            return nil
        }
        return findViews(composer.view) { $0 is UITextView }
            .first as? UITextView
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
        //
        // 2026-11-14 修线（bar-probe-injection-fix）：
        // 旧注入只写外层 host＋window、固定等 2 秒
        // 即测——五轮 CI 实证其在舱子树的效果是双
        // 态的：两轮舱条 46→75（锚定成立）、三轮舱
        // 条 46→52 且帧落在 (-40,784 398x52)（对
        // §194 坞锚几何不可能）。按 ComposerLayout
        // 算术，52.0 恰为文本按 XXXL 档量测（行高
        // ≈26）＋布局档亦未达 AX5 之值——即 AX5
        // 覆写在三轮里没有到达舱的量测链（UIText-
        // View trait＋Layout 注入档），而顶簇同轮
        // 60→83 证明覆写到达了 SwiftUI 环境（传播
        // 在嵌套托管＋representable 处失稳，与产品
        // 代码无关；分支相关性 n=5 未坐实，不作定
        // 因）。修法三件：①覆写改在量测点直施（舱
        // 控制器＋文本视图本体各一份，不再只靠窗口
        // 向下的传播）；②先验前置条件（文本视图
        // trait 档确为 AX5，有界轮询）再量测——断
        // 言后果之前先证前提；③量测改舱宿主子树
        // 内取数（组装回归测试同口径），玻璃帧落定
        // 后再读。
        let composerGuide = try XCTUnwrap(
            findVC(ComposerGuideHostController.self),
            "ComposerGuideHostController 缺席"
        )
        assembly.host.traitOverrides.legibilityWeight = .bold
        assembly.host.traitOverrides
            .preferredContentSizeCategory =
            .accessibilityExtraExtraLarge
        window.traitOverrides.legibilityWeight = .bold
        window.traitOverrides.preferredContentSizeCategory =
            .accessibilityExtraExtraLarge
        composerGuide.traitOverrides.legibilityWeight = .bold
        composerGuide.traitOverrides.preferredContentSizeCategory =
            .accessibilityExtraExtraLarge
        if let textView = composerTextView() {
            textView.traitOverrides.legibilityWeight = .bold
            textView.traitOverrides.preferredContentSizeCategory =
                .accessibilityExtraExtraLarge
        }
        // 前置条件轮询：文本视图 trait 档确为 AX5
        // 才量测（有界 8 秒、每 0.25 秒一拍；超时即
        // 以精确口径失败——「trait 未到达文本视图」，
        // 不再把传播失败误报成「注入未生效」）
        let traitDeadline = Date().addingTimeInterval(8)
        var traitCategory: UIContentSizeCategory?
        while Date() < traitDeadline {
            traitCategory = composerTextView()?
                .traitCollection.preferredContentSizeCategory
            if traitCategory == .accessibilityExtraExtraLarge {
                break
            }
            spinRunLoop(seconds: 0.25)
        }
        XCTAssertTrue(
            traitCategory == .accessibilityExtraExtraLarge,
            "前置条件未达成：trait 未到达文本视图，当前档＝"
                + "\(traitCategory?.rawValue ?? "缺席")"
                + "（8 秒轮询）；量测链未进入 AX5，锚定断言无意义"
        )
        window.layoutIfNeeded()
        // 玻璃交互视图的帧随渲染提交落定，不与
        // layoutIfNeeded 同拍——再转半拍才读数
        spinRunLoop(seconds: 0.5)
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
        // 2026-11-14 修线：形态带——AX5 单行既有量
        // 级为 46→75；文本 AX5 而布局档滞后时会进
        // 多行支（≈109），生长断言与锚点断言都会
        // 放过它（假绿）。带宽 ±5 容 iOS 字体系数
        // 漂移，带外即布局档未到位的实证
        XCTAssertTrue(
            (70...80).contains(grownBar.height),
            "生长形态异常：舱条高 \(grownBar.height)"
                + " 不在 AX5 单行带 70...80 内（基线 "
                + "\(baseBar.height)）；疑布局注入档滞后"
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
            + " trait=\(traitCategory?.rawValue ?? "?")"
            + " | polluted bar=\(fmt(pollutedBar))"
            + " pocket=\(fmt(pollutedPocket))")
    }
}
