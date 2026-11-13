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

/// 设备窗口：测试宿主的裸 UIWindow 底部安全区恒 0
/// （无 Home Indicator 区），底栏落在无指示器档位、
/// 各组无从分辨——照胶囊扫描线 StatusBarWindow 口
/// 径覆写为真机值（iPhone 17：顶 59／底 34）
private final class FloatDeviceWindow: UIWindow {
    override var safeAreaInsets: UIEdgeInsets {
        UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }
}

/// 症三·底坞浮空回归（2026-11-12 定因，报告见
/// docs/shell-float-fix/FLOAT-FIX-REPORT.md）
///
/// 真机量测：自家浮空 ≈57±2pt；同机型、同玻璃视觉
/// 口径的 Muse 锚点 ≈23±2pt（详见报告双判据）。
/// 探针四组对照（同台 402×874、窗口安全区 59/34）：
/// - A 纯宿主 TabView：Platter 浮空 21.0（本台标准）
/// - B 容器裸装为根：21.0（容器本体无罪）
/// - C 容器＋additionalSafeAreaInsets.bottom 34：
///   55.0（双计的另一机制，同签名；生产源码核账排除）
/// - D 生产桥链（DrawerContainer 经 Representable
///   进宿主）：55.0 —— **定因**：桥被 SwiftUI 摆进
///   安全区矩形，容器帧 (0,59 402×781)、自身安全
///   区读数为零；从几何上看，底部 34pt 被排除在帧
///   外，内部坞盘相对宿主底边仍留 21pt，距物理屏
///   底＝34＋21＝55（真机 57±2 同构）。内部为何仍
///   留 21pt 是推断，不是布局档位的直接观测
/// - F 桥链＋.ignoresSafeArea()（＝ContentView 现
///   行落法）：21.0、容器帧回全屏、安全区 B34 走
///   传播——修复成立
///
/// 本套件原钉三条：B 与 A 同值（容器无罪不回退）、
/// D 的缺陷签名（无 ignoresSafeArea 时恰高一个底
/// 安全区＋帧被安全区矩形收编——系统若改 Representable
/// 落位行为，此条先红、提示重裁）、生产落法与 A
/// 同值且容器帧全屏（修复在位）；另有一条限定生产
/// 装配点的源码守护，核实本体结果直挂该修饰符。
@MainActor
final class TabBarFloatTests: XCTestCase {

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

    /// 与 DrawerBridgeHarness 同款装配；production-
    /// Placement＝true 时镜像 ContentView 现行落法
    /// （DrawerContainer 挂 .ignoresSafeArea()）
    private struct BridgeHarness: View {
        @Environment(AppState.self) private var appState
        @State private var selection: ContentView.MainTab = .chat
        let box: ProbeBox
        var productionPlacement = false

        var body: some View {
            if productionPlacement {
                DrawerContainer(
                    selection: $selection,
                    presented: appState.drawerPresented,
                    onManageAll: {},
                    onOpenChannel: { _ in }
                ) {
                    TabStandIn(box: box)
                }
                .ignoresSafeArea()
            } else {
                DrawerContainer(
                    selection: $selection,
                    presented: appState.drawerPresented,
                    onManageAll: {},
                    onOpenChannel: { _ in }
                ) {
                    TabStandIn(box: box)
                }
            }
        }
    }

    private struct Measurement {
        var platterFloat: CGFloat
        var pageBottomInset: CGFloat
        var containerFrame: CGRect?
        var containerViewSafeBottom: CGFloat?
    }

    private var windows: [FloatDeviceWindow] = []

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

    private func mount(root: UIViewController) -> FloatDeviceWindow {
        let window = FloatDeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        windows.append(window)
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        spinRunLoop(seconds: 1.2)
        root.view.layoutIfNeeded()
        return window
    }

    private func measure(
        in window: FloatDeviceWindow, box: ProbeBox, arm: String
    ) -> Measurement {
        var platter: CGRect?
        func walk(_ view: UIView) {
            if String(describing: type(of: view))
                .contains("Platter")
            {
                platter = view.convert(view.bounds, to: window)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)
        var container: DrawerContainerController?
        func findVC(_ vc: UIViewController) {
            if let found = vc as? DrawerContainerController {
                container = found
            }
            for child in vc.children { findVC(child) }
        }
        if let root = window.rootViewController { findVC(root) }
        let float = platter.map { window.bounds.height - $0.maxY }
        let containerFrame = container.map {
            $0.view.convert($0.view.bounds, to: window)
        }
        print(
            "FLOATPROBE| \(arm) platter=\(platter as Any) "
            + "FLOAT=\(float as Any) "
            + "pageInset=\(box.pageBottomInset) "
            + "containerFrame=\(containerFrame as Any) "
            + "containerSafeB="
            + "\(container?.view.safeAreaInsets.bottom as Any)"
        )
        return Measurement(
            platterFloat: float ?? -1,
            pageBottomInset: box.pageBottomInset,
            containerFrame: containerFrame,
            containerViewSafeBottom: container?.view
                .safeAreaInsets.bottom
        )
    }

    // MARK: - 对照基线

    private func measurePlainHost() -> Measurement {
        let box = ProbeBox()
        let host = UIHostingController(
            rootView: TabStandIn(box: box)
        )
        let window = mount(root: host)
        return measure(in: window, box: box, arm: "A-plain-host")
    }

    private func measureBridge(
        productionPlacement: Bool
    ) throws -> Measurement {
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
                box: box,
                productionPlacement: productionPlacement
            )
            .environment(appState)
            .modelContainer(container)
        )
        let window = mount(root: host)
        return measure(
            in: window, box: box,
            arm: productionPlacement
                ? "F-bridge-production" : "D-bridge-legacy"
        )
    }

    // MARK: - 用例

    /// 容器本体无罪：裸装为根时浮空与纯宿主同值
    func testContainerDirectRoot_MatchesPlainHost() {
        let baseline = measurePlainHost()
        let box = ProbeBox()
        let controller = DrawerContainerController()
        controller.drawerBuilder = { _ in AnyView(EmptyView()) }
        controller.contentRoot = AnyView(TabStandIn(box: box))
        let window = mount(root: controller)
        let direct = measure(
            in: window, box: box, arm: "B-container-direct"
        )
        XCTAssertGreaterThan(baseline.platterFloat, 0)
        XCTAssertEqual(
            direct.platterFloat, baseline.platterFloat,
            accuracy: 1.5,
            "容器裸装浮空应与纯宿主同值（容器本体无罪）"
        )
    }

    /// 缺陷签名：桥链不挂 ignoresSafeArea 时，浮空
    /// 恰高一个底安全区（34）、容器帧被安全区矩形
    /// 收编（高 781）、自身安全区读数为零
    func testBridgeChain_LegacyPlacement_FloatsOneBottomInsetHigher()
        throws
    {
        let baseline = measurePlainHost()
        let legacy = try measureBridge(productionPlacement: false)
        XCTAssertEqual(
            legacy.platterFloat,
            baseline.platterFloat + 34,
            accuracy: 1.5,
            "缺陷签名：浮空应恰高一个底安全区"
        )
        let frame = try XCTUnwrap(legacy.containerFrame)
        XCTAssertEqual(frame.minY, 59, accuracy: 1)
        XCTAssertEqual(frame.height, 781, accuracy: 1)
        XCTAssertEqual(
            legacy.containerViewSafeBottom ?? -1, 0, accuracy: 0.5
        )
    }

    /// 修复在位：生产落法（.ignoresSafeArea）下桥链
    /// 浮空与纯宿主同值、容器帧回全屏、安全区走传
    /// 播（B＝34）
    func testBridgeChain_ProductionPlacement_MatchesPlainHost()
        throws
    {
        let baseline = measurePlainHost()
        let fixed = try measureBridge(productionPlacement: true)
        XCTAssertEqual(
            fixed.platterFloat, baseline.platterFloat,
            accuracy: 1.5,
            "生产落法浮空应与纯宿主同值（多出的 34 已消除）"
        )
        let frame = try XCTUnwrap(fixed.containerFrame)
        XCTAssertEqual(frame.minY, 0, accuracy: 1)
        XCTAssertEqual(frame.height, 874, accuracy: 1)
        XCTAssertEqual(
            fixed.containerViewSafeBottom ?? -1, 34, accuracy: 0.5
        )
        XCTAssertEqual(
            fixed.pageBottomInset, baseline.pageBottomInset,
            accuracy: 0.5,
            "页面底预留（TabView 坞区 83）不应被本修复改变"
        )
    }

    // MARK: - 生产装配点源码守护

    private enum SourceGuardError: Error {
        case malformedDrawerContainerExpression
    }

    /// 限定在 ContentView.body 的生产装配点：截取有限
    /// 片段、去注释后解析 DrawerContainer 的实参括号
    /// 与尾随闭包，核实其结果紧接着直挂
    /// `.ignoresSafeArea()`。删除、移位到其他修饰符
    /// 之后，或只把该调用留在注释中，都会判红；本测
    /// 不托管真实 ContentView，也不对全文件做无限定
    /// 的目标字符串搜。
    func testContentViewDrawerContainerResultDirectlyIgnoresSafeArea()
        throws
    {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentViewURL = repositoryRoot.appendingPathComponent(
            "Sources/OneDayApp/ContentView.swift"
        )
        let raw = try String(
            contentsOf: contentViewURL, encoding: .utf8
        )
        let bodyRange = try XCTUnwrap(
            raw.range(of: "var body: some View")
        )
        let segment = String(
            raw[bodyRange.lowerBound...].prefix(6_000)
        )
        let code = Self.stripComments(segment)
        let callRange = try XCTUnwrap(
            code.range(of: "DrawerContainer")
        )
        let argumentsAndRest = code[callRange.upperBound...]
        let expressionEnd = try Self
            .endOfDrawerContainerExpression(argumentsAndRest)
        let nextCode = argumentsAndRest[expressionEnd...]
            .drop(while: { $0.isWhitespace })
        XCTAssertTrue(
            nextCode.hasPrefix(".ignoresSafeArea()"),
            "ContentView 中 DrawerContainer 的结果必须直挂 "
                + ".ignoresSafeArea()"
        )
    }

    private static func endOfDrawerContainerExpression(
        _ text: Substring
    ) throws -> String.Index {
        var index = text.startIndex
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "(" else {
            throw SourceGuardError
                .malformedDrawerContainerExpression
        }
        index = try scanBalanced(
            text, from: index, opening: "(", closing: ")"
        )
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        if index < text.endIndex, text[index] == "{" {
            return try scanBalanced(
                text, from: index, opening: "{", closing: "}"
            )
        }
        return index
    }

    private static func scanBalanced(
        _ text: Substring,
        from start: String.Index,
        opening: Character,
        closing: Character
    ) throws -> String.Index {
        var depth = 0
        var index = start
        var inString = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return text.index(after: index)
                }
            }
            index = text.index(after: index)
        }
        throw SourceGuardError.malformedDrawerContainerExpression
    }

    private static func stripComments(_ source: String) -> String {
        var result = ""
        var index = source.startIndex
        var inLineComment = false
        var inString = false
        var escaped = false
        var blockDepth = 0

        func nextCharacter() -> Character? {
            let next = source.index(after: index)
            guard next < source.endIndex else { return nil }
            return source[next]
        }

        while index < source.endIndex {
            let character = source[index]
            let next = nextCharacter()
            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    result.append(character)
                }
                index = source.index(after: index)
                continue
            }
            if blockDepth > 0 {
                if character == "/", next == "*" {
                    blockDepth += 1
                    index = source.index(index, offsetBy: 2)
                    continue
                }
                if character == "*", next == "/" {
                    blockDepth -= 1
                    index = source.index(index, offsetBy: 2)
                    continue
                }
                if character == "\n" {
                    result.append(character)
                }
                index = source.index(after: index)
                continue
            }
            if inString {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = source.index(after: index)
                continue
            }
            if character == "\"" {
                inString = true
                result.append(character)
                index = source.index(after: index)
                continue
            }
            if character == "/", next == "/" {
                inLineComment = true
                index = source.index(index, offsetBy: 2)
                continue
            }
            if character == "/", next == "*" {
                blockDepth = 1
                index = source.index(index, offsetBy: 2)
                continue
            }
            result.append(character)
            index = source.index(after: index)
        }
        return result
    }
}
