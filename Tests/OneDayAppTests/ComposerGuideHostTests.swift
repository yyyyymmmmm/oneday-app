import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §178 输入舱引导线托管的宿主级几何验收：把生产件
/// ComposerGuideHost 装进与生产同构的壳（DrawerCon-
/// tainerController 前景＋真 TabView＋真 UITabBar）里，
/// 聊天页替身按 ChatView 的现行接法复刻（ScrollView-
/// Reader 同树、列表 .ignoresSafeArea(.bottom)、底
/// contentMargins ＝实测回报＋spacingS、舱经 host 托
/// 管），钉静止几何与协作行为：
/// 1. 静止帧舱底＝坞顶（地板钳制落在页帧底边）
/// 2. 列表贴底静止时末行底＝舱顶－8（§176 单点边距
///    经实测留位链端到端成立）
/// 3. 回报值＝舱顶→窗口底的实测距离
/// 4. 舱内容长高：舱顶上移同量、舱底不动
/// 5. 透传：舱带之外 host 视图 hitTest 穿透（列表手
///    势作用域不被全帧层吞掉）
/// 6. 切格往返与抽屉开合后静止几何复原（前景协作）
/// 键盘跟随本身 CI 模拟器升不起真键盘（探针两轮实
/// 证：isFirstResponder 可达、无键盘窗、合成通知
/// SwiftUI 不认），归真机清单（DESIGN §178）不在此断言
@MainActor
final class ComposerGuideHostTests: XCTestCase {

    // MARK: - 替身与量具

    /// 壳状态盒（测试与替身视图共享同一份事实）。不
    /// 设 private：@Observable 宏展开在文件作用域生成
    /// 代码，private 嵌套类会让宏够不着（CI 实证编译
    /// 错 'ShellState' is inaccessible）
    @Observable
    final class ShellState {
        var selection = 0
        var bottomSpace: CGFloat = 168
        var tallBar = false
    }

    /// 帧采集盒：GuideFrameReporter 逐布局拍回写窗口帧
    private final class FrameBox: @unchecked Sendable {
        var frames: [String: CGRect] = [:]
    }

    /// 把宿主视图的窗口帧写进采集盒的量具
    private struct GuideFrameReporter: UIViewRepresentable {
        let name: String
        let box: FrameBox
        func makeUIView(context: Context) -> ReporterView {
            let view = ReporterView()
            view.name = name
            view.box = box
            view.backgroundColor = .clear
            return view
        }
        func updateUIView(_ view: ReporterView, context: Context) {
            view.name = name
            view.box = box
        }
        final class ReporterView: UIView {
            var name: String = ""
            var box: FrameBox?
            override func layoutSubviews() {
                super.layoutSubviews()
                report()
            }
            override func didMoveToWindow() {
                super.didMoveToWindow()
                report()
            }
            private func report() {
                guard let window, bounds.height > 0 else { return }
                box?.frames[name] = convert(bounds, to: window)
            }
        }
    }

    /// 聊天页替身：按 ChatView §178 接法复刻（同树
    /// proxy、实测留位、host 托管同位）
    private struct ChatReplica: View {
        @Bindable var state: ShellState
        let box: FrameBox
        var body: some View {
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<60, id: \.self) { row in
                                Text("row \(row)")
                                    .frame(height: 30)
                                    .frame(maxWidth: .infinity)
                                    .id(row)
                                    .background {
                                        if row == 59 {
                                            GuideFrameReporter(
                                                name: "lastRow",
                                                box: box)
                                        }
                                    }
                            }
                        }
                    }
                    // 修饰顺序与生产 messageList 对齐
                    // （contentMargins 在前、ignoresSafe-
                    // Area 在后，照 ChatView 的现行链位）
                    .contentMargins(
                        .bottom, state.bottomSpace + 8,
                        for: .scrollContent
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .task {
                        try? await Task.sleep(
                            for: .milliseconds(400))
                        proxy.scrollTo(59, anchor: .bottom)
                    }
                    ComposerGuideHost(
                        bottomSpace: $state.bottomSpace
                    ) {
                        VStack(spacing: 0) {
                            if state.tallBar {
                                Color.clear.frame(height: 40)
                            }
                            Text("BAR")
                                .frame(height: 76)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                        .background(
                            GuideFrameReporter(
                                name: "bar", box: box)
                        )
                    }
                }
            }
        }
    }

    private struct ShellTabs: View {
        @Bindable var state: ShellState
        let box: FrameBox
        var body: some View {
            TabView(selection: $state.selection) {
                Tab("聊天", systemImage: "message", value: 0) {
                    ChatReplica(state: state, box: box)
                }
                Tab("文件", systemImage: "folder", value: 1) {
                    Text("other")
                }
            }
        }
    }

    // MARK: - 装配

    private var window: UIWindow!
    private var container: DrawerContainerController!
    private var state: ShellState!
    private var box: FrameBox!

    override func setUp() async throws {
        try await super.setUp()
        state = ShellState()
        box = FrameBox()
        let state = state!
        let box = box!
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        container = DrawerContainerController()
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        // 环境与生产根同口径：ComposerGuideHost 桥读
        // AppState（未注入会 trap），在内容根处注入
        container.drawerBuilder = { _ in AnyView(Text("drawer")) }
        container.contentRoot = AnyView(
            ShellTabs(state: state, box: box)
                .environment(AppState())
        )
    }

    override func tearDown() async throws {
        window.rootViewController = nil
        window.isHidden = true
        window = nil
        container = nil
        state = nil
        box = nil
        try await super.tearDown()
    }

    /// 等待泵：照 DrawerBridgeHarnessTests 的可用配
    /// 方（expectation＋wait）——RunLoop.run 紧循环泵
    /// 不动 SwiftUI 的布局/显示链（首轮 CI 五法全灭
    /// 的实证：frames 恒空、连 UITabBar 都不出现）
    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func settle(_ seconds: TimeInterval = 1.2) {
        spinRunLoop(seconds: seconds)
    }

    /// 等舱帧首次落盒（渲染完成判据），上限约 6 秒
    private func waitForBarFrame() {
        let deadline = Date().addingTimeInterval(6)
        while box.frames["bar"] == nil, Date() < deadline {
            spinRunLoop(seconds: 0.25)
        }
    }

    private func tabBar() -> UITabBar? {
        func find(_ view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            for sub in view.subviews {
                if let found = find(sub) { return found }
            }
            return nil
        }
        return window.flatMap { find($0) }
    }

    private func guideHostController() -> ComposerGuideHostController? {
        func find(_ vc: UIViewController) -> ComposerGuideHostController? {
            if let host = vc as? ComposerGuideHostController {
                return host
            }
            for child in vc.children {
                if let found = find(child) { return found }
            }
            return nil
        }
        return container.flatMap { find($0) }
    }

    // MARK: - 断言

    /// 静止几何三连：舱底贴坞顶、回报值对账、末行贴
    /// 底停在舱顶上方恰一个单点边距（8）
    func testRestGeometry_barDockedListSpacingAndReport() {
        waitForBarFrame()
        // 再给 .task 的滚底与留位回报落定留一拍
        settle(1.0)
        guard let tab = tabBar(),
              let bar = box.frames["bar"],
              let lastRow = box.frames["lastRow"]
        else {
            XCTFail("量具未齐：tab=\(tabBar() != nil) frames=\(box.frames.keys.sorted())")
            return
        }
        let tabTop = tab.convert(tab.bounds, to: window).minY
        XCTAssertEqual(
            bar.maxY, tabTop, accuracy: 2,
            "舱底应落在坞顶（地板钳制＝页帧底边）")
        XCTAssertEqual(
            state.bottomSpace, window.bounds.height - bar.minY,
            accuracy: 2,
            "回报值应为舱顶→窗口底的实测距离")
        XCTAssertEqual(
            bar.minY - lastRow.maxY, 8, accuracy: 2,
            "末行底距舱顶应为 §176 单点边距 8")
    }

    /// 舱内容长高 40：舱顶上移 40±2、舱底不动、回报
    /// 同步增 40±2
    func testBarGrowth_topRisesBottomPinned() {
        waitForBarFrame()
        guard let before = box.frames["bar"] else {
            XCTFail("首帧未到")
            return
        }
        let spaceBefore = state.bottomSpace
        state.tallBar = true
        settle()
        guard let after = box.frames["bar"] else {
            XCTFail("长高后帧丢失")
            return
        }
        XCTAssertEqual(
            before.minY - after.minY, 40, accuracy: 2,
            "舱顶应随内容长高同量上移")
        XCTAssertEqual(
            after.maxY, before.maxY, accuracy: 2,
            "舱底应钉住不动（地板/引导线钉位）")
        XCTAssertEqual(
            state.bottomSpace - spaceBefore, 40, accuracy: 2,
            "回报值应随舱顶同步变化")
    }

    /// 透传：host 视图在列表区（舱带之上）的点 hitTest
    /// 穿透为 nil、舱带内的点命中舱子树
    func testPassthrough_listAreaFallsThroughBarHits() {
        waitForBarFrame()
        guard let host = guideHostController(),
              let bar = box.frames["bar"]
        else {
            XCTFail("host 或舱帧未就位")
            return
        }
        let hostView = host.view!
        // 舱带上方 120pt（列表区）：应穿透
        let listPointWindow = CGPoint(
            x: bar.midX, y: bar.minY - 120)
        let listPoint = hostView.convert(
            listPointWindow, from: window)
        XCTAssertNil(
            hostView.hitTest(listPoint, with: nil),
            "舱带之外不应拦命中（点空白收键盘等列表手势）")
        // 舱带正中：应命中舱子树
        let barPoint = hostView.convert(
            CGPoint(x: bar.midX, y: bar.midY), from: window)
        let hit = hostView.hitTest(barPoint, with: nil)
        XCTAssertNotNil(hit, "舱带内应可命中")
        XCTAssertFalse(
            hit === hostView,
            "舱带内命中应落在舱子树、不是透传根视图本体")
    }

    /// 切格往返：去别的格再回来，host 仍在层级内、静
    /// 止几何复原
    func testTabRoundTrip_restGeometryRestored() {
        waitForBarFrame()
        guard let before = box.frames["bar"] else {
            XCTFail("首帧未到")
            return
        }
        state.selection = 1
        settle(0.8)
        state.selection = 0
        settle(1.6)
        guard let after = box.frames["bar"] else {
            XCTFail("回格后舱帧丢失")
            return
        }
        XCTAssertNotNil(guideHostController(), "host 控制器应仍在层级内")
        XCTAssertEqual(after.minY, before.minY, accuracy: 2)
        XCTAssertEqual(after.maxY, before.maxY, accuracy: 2)
    }

    /// 抽屉开合：舱随前景整体滑动、关后几何复原。前
    /// 景平移走 transform、不触发深层 layoutSubviews，
    /// 宿主根视图用活量换算（convert 即时反映变换）、
    /// 舱帧经一次内容长高戳动强制重报后读取
    func testDrawerOpenClose_composerRidesForeground() {
        waitForBarFrame()
        guard let host = guideHostController(),
              let hostView = host.view,
              let before = box.frames["bar"]
        else {
            XCTFail("host 或首帧未就位")
            return
        }
        let hostFrameBefore = hostView.convert(
            hostView.bounds, to: window)
        container.setDrawer(true, animated: false)
        settle(0.8)
        let hostFrameOpened = hostView.convert(
            hostView.bounds, to: window)
        XCTAssertGreaterThan(
            hostFrameOpened.minX, hostFrameBefore.minX + 40,
            "开抽屉时宿主应随前景右移（同在前景层级）")
        // 戳一次长高让舱帧在变换下重报：纵向钉位不变、
        // 横向随前景走、高恰多 40
        state.tallBar = true
        settle(0.8)
        guard let openedBar = box.frames["bar"] else {
            XCTFail("抽屉开后舱帧丢失")
            return
        }
        XCTAssertGreaterThan(
            openedBar.minX, before.minX + 40,
            "舱帧应随前景右移")
        XCTAssertEqual(
            openedBar.maxY, before.maxY, accuracy: 2,
            "前景平移不改舱的纵向钉位")
        XCTAssertEqual(
            openedBar.height, before.height + 40, accuracy: 2)
        state.tallBar = false
        container.setDrawer(false, animated: false)
        settle(0.8)
        state.tallBar = true
        settle(0.8)
        state.tallBar = false
        settle(0.8)
        guard let closedBar = box.frames["bar"] else {
            XCTFail("抽屉关后舱帧丢失")
            return
        }
        XCTAssertEqual(closedBar.minX, before.minX, accuracy: 2)
        XCTAssertEqual(closedBar.maxY, before.maxY, accuracy: 2)
        XCTAssertEqual(closedBar.height, before.height, accuracy: 2)
    }
}
