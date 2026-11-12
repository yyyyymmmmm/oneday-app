import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

private struct FloatInsetKey: PreferenceKey {
    static var defaultValue: CGFloat { -1 }
    static func reduce(
        value: inout CGFloat, nextValue: () -> CGFloat
    ) {
        value = nextValue()
    }
}

/// 症三·底坞浮空定因探针（2026-11-12 施工第一步）
///
/// 背景：真机量测自家浮空 ≈57±2pt、原生标准带 34–36pt、
/// 代码层显式增距＝0pt，多出的 ~20pt 在容器安全区传播
/// 里。本探针在同一窗口尺寸（402×874，iPhone 17 逻辑
/// 屏、窗口底安全区 34）下四组对照，逐层打印安全区链
/// 与底栏玻璃面帧，一轮 CI 出全表定贡献层：
///
/// - A 对照：UIHostingController 直装 TabView（无容器）
/// - B 现行台：DrawerContainerController 裸装为根
///   （与胶囊命中扫描同台）
/// - C 模拟桥注入：B ＋ 容器 additionalSafeAreaInsets
///   .bottom＝34（UIViewControllerRepresentable 把
///   SwiftUI 安全区经 additionalSafeAreaInsets 注入
///   被代表 VC 的候选机制）
/// - D 真实链：DrawerContainer 桥装进 UIHosting-
///   Controller（DrawerBridgeHarness 同款装配、内容
///   换 TabView 替身），复现生产链原样
///
/// 读数口径：FLOAT＝窗口高 − 底栏候选面 maxY；页面
/// inset＝TabView 页内 GeometryProxy 实读的底部安
/// 全区（系统给页面预留的底距，与 FLOAT 应同涨落）。
/// 本文件纯探针：只打印、不断言定罪（定因后另立回
/// 归测试）。
/// 设备窗口：测试宿主的裸 UIWindow 底部安全区恒 0
/// （无 Home Indicator 区），底栏落在无指示器档位、
/// 四组无从分辨——照胶囊扫描线 StatusBarWindow 口
/// 径覆写为真机值（iPhone 17：顶 59／底 34）
private final class FloatDeviceWindow: UIWindow {
    override var safeAreaInsets: UIEdgeInsets {
        UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }
}

@MainActor
final class TabBarFloatProbeTests: XCTestCase {

    private final class ProbeBox {
        var pageBottomInset: CGFloat = -1
    }

    private struct ProbePage: View {
        let box: ProbeBox
        var body: some View {
            Color.clear
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FloatInsetKey.self,
                            value: proxy.safeAreaInsets.bottom
                        )
                    }
                }
                .onPreferenceChange(FloatInsetKey.self) { value in
                    box.pageBottomInset = value
                }
        }
    }

    private struct TabStandIn: View {
        let box: ProbeBox
        @State private var tab = 0
        var body: some View {
            TabView(selection: $tab) {
                ProbePage(box: box)
                    .tabItem {
                        Label("聊天", systemImage: "message.fill")
                    }
                    .tag(0)
                Text("动态")
                    .tabItem {
                        Label(
                            "动态",
                            systemImage: "square.stack.3d.up.fill"
                        )
                    }
                    .tag(1)
                Text("点子")
                    .tabItem {
                        Label("点子", systemImage: "lightbulb.fill")
                    }
                    .tag(2)
                Text("目标")
                    .tabItem {
                        Label("目标", systemImage: "target")
                    }
                    .tag(3)
                Text("文件")
                    .tabItem {
                        Label("文件", systemImage: "folder.fill")
                    }
                    .tag(4)
            }
        }
    }

    private struct BridgeHarness: View {
        @Environment(AppState.self) private var appState
        @State private var selection: ContentView.MainTab = .chat
        let box: ProbeBox
        var ignoresSafeAreaFix = false

        var body: some View {
            if ignoresSafeAreaFix {
                DrawerContainer(
                    selection: $selection,
                    presented: appState.drawerPresented,
                    onManageAll: {},
                    onOpenChannel: {}
                ) {
                    TabStandIn(box: box)
                }
                .ignoresSafeArea()
            } else {
                DrawerContainer(
                    selection: $selection,
                    presented: appState.drawerPresented,
                    onManageAll: {},
                    onOpenChannel: {}
                ) {
                    TabStandIn(box: box)
                }
            }
        }
    }

    private var window: FloatDeviceWindow!

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

    private func makeWindow(root: UIViewController) {
        window = FloatDeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        spinRunLoop(seconds: 1.2)
        root.view.layoutIfNeeded()
    }

    // MARK: - 四组对照

    func testProbeArmA_PlainHostControl() {
        let box = ProbeBox()
        let host = UIHostingController(
            rootView: TabStandIn(box: box)
        )
        makeWindow(root: host)
        dump(arm: "A-plain-host", box: box)
    }

    func testProbeArmB_ContainerDirectRoot() {
        let box = ProbeBox()
        let controller = DrawerContainerController()
        controller.drawerBuilder = { _ in AnyView(EmptyView()) }
        controller.contentRoot = AnyView(TabStandIn(box: box))
        makeWindow(root: controller)
        dump(arm: "B-container-direct", box: box)
    }

    func testProbeArmC_ContainerAdditionalInset() {
        let box = ProbeBox()
        let controller = DrawerContainerController()
        controller.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0, left: 0, bottom: 34, right: 0
        )
        controller.drawerBuilder = { _ in AnyView(EmptyView()) }
        controller.contentRoot = AnyView(TabStandIn(box: box))
        makeWindow(root: controller)
        dump(arm: "C-container-additional34", box: box)
    }

    func testProbeArmD_FullBridgeChain() throws {
        let box = ProbeBox()
        let appState = AppState()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        let host = UIHostingController(
            rootView: BridgeHarness(box: box)
                .environment(appState)
                .modelContainer(container)
        )
        makeWindow(root: host)
        dump(arm: "D-full-bridge", box: box)
    }

    func testProbeArmF_BridgeIgnoresSafeArea() throws {
        let box = ProbeBox()
        let appState = AppState()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        let host = UIHostingController(
            rootView: BridgeHarness(
                box: box, ignoresSafeAreaFix: true
            )
            .environment(appState)
            .modelContainer(container)
        )
        makeWindow(root: host)
        dump(arm: "F-bridge-ignoresSafeArea", box: box)
    }

    // MARK: - 打印

    private func p(_ line: String) {
        print("FLOATPROBE| \(line)")
    }

    private func fmt(_ rect: CGRect) -> String {
        String(
            format: "(%.0f,%.0f %.0f×%.0f)",
            rect.minX, rect.minY, rect.width, rect.height
        )
    }

    private func fmtInsets(_ insets: UIEdgeInsets) -> String {
        String(
            format: "T%.1f L%.1f B%.1f R%.1f",
            insets.top, insets.left, insets.bottom, insets.right
        )
    }

    private func dump(arm: String, box: ProbeBox) {
        let height = window.bounds.height
        p("\(arm) BEGIN")
        p("\(arm) window=\(fmt(window.bounds)) "
            + "safe=\(fmtInsets(window.safeAreaInsets))")
        p("\(arm) pageInset.bottom=\(box.pageBottomInset)")

        func dumpVC(_ vc: UIViewController, _ depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            let frame = vc.view.convert(vc.view.bounds, to: window)
            p("\(arm) VC \(pad)\(type(of: vc)) "
                + "frame=\(fmt(frame)) "
                + "viewSafe=\(fmtInsets(vc.view.safeAreaInsets)) "
                + "addl=\(fmtInsets(vc.additionalSafeAreaInsets))")
            for child in vc.children { dumpVC(child, depth + 1) }
        }
        if let root = window.rootViewController {
            dumpVC(root, 0)
        }

        var candidates: [(String, CGRect)] = []
        func walk(_ view: UIView) {
            let frame = view.convert(view.bounds, to: window)
            let cls = String(describing: type(of: view))
            let named = cls.contains("Tab")
                || cls.contains("Glass")
                || cls.contains("Hosting")
            let inBand = frame.maxY > height - 190
                && frame.width > 120
                && frame.height > 4 && frame.height < 130
            if named || inBand {
                p("\(arm) VIEW \(cls) frame=\(fmt(frame)) "
                    + "safe=\(fmtInsets(view.safeAreaInsets)) "
                    + "float=\(String(format: "%.1f", height - frame.maxY))")
            }
            if cls.contains("Platter")
                || (frame.width >= 240 && frame.height >= 38
                    && frame.height <= 80 && frame.maxY > height - 190)
            {
                candidates.append((cls, frame))
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)

        let tabNamed = candidates.filter { $0.0.contains("Platter") }
        let pool = tabNamed.isEmpty ? candidates : tabNamed
        if let best = pool.max(by: { $0.1.maxY < $1.1.maxY }) {
            p("\(arm) RESULT capsule=\(best.0) \(fmt(best.1)) "
                + "FLOAT=\(String(format: "%.1f", height - best.1.maxY))")
        } else {
            p("\(arm) RESULT no-capsule-candidate")
        }
        p("\(arm) END")
    }
}
