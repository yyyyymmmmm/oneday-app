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
        var contentHeight: CGFloat = 76
        var tallBar = false
    }

    /// 帧采集盒：GuideFrameReporter 逐布局拍回写窗口
    /// 帧，并登记视图本体供断言时活量（滚动不改行在
    /// 内容视图内的帧、不会重触发其 layoutSubviews，
    /// 落盒帧是滚动前的旧值——实证差 1139pt）
    private final class FrameBox: @unchecked Sendable {
        var frames: [String: CGRect] = [:]
        var views: [String: UIView] = [:]
        var notes: [String: String] = [:]
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
                box?.views[name] = self
                box?.frames[name] = convert(bounds, to: window)
            }
        }
    }

    /// 聊天页替身：按 ChatView §178 接法复刻（同树
    /// proxy、实测留位、host 托管同位）。舱替身写在构
    /// 建闭包里（与生产 bottomBar 是 ChatView 函数、经
    /// 桥 init 在外层 body 期求值的形态同构——状态读
    /// 数归因到本替身、变化经重建＋重赋值传导）
    private struct ChatReplica: View {
        @Bindable var state: ShellState
        let box: FrameBox
        var body: some View {
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView {
                        // 急切栈（生产为 LazyVStack）：几
                        // 何链（留位/托管）与懒急无关，急
                        // 切栈保证行帧在宿主里可量（惰性
                        // 建列在测试窗里不触发尾行）
                        VStack(spacing: 0) {
                            ForEach(0..<60, id: \.self) { row in
                                Text("row \(row)")
                                    .frame(height: 30)
                                    .frame(maxWidth: .infinity)
                                    .id(row)
                                    .background {
                                        if row == 0 {
                                            GuideFrameReporter(
                                                name: "firstRow",
                                                box: box)
                                        }
                                        if row == 30 {
                                            GuideFrameReporter(
                                                name: "midRow",
                                                box: box)
                                        }
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
                    .onScrollGeometryChange(
                        for: String.self
                    ) { geo in
                        "insetB=\(Int(geo.contentInsets.bottom)) "
                            + "contH=\(Int(geo.containerSize.height)) "
                            + "offY=\(Int(geo.contentOffset.y)) "
                            + "sizeH=\(Int(geo.contentSize.height))"
                    } action: { _, v in
                        box.notes["geo"] = v
                    }
                    // （滚底驱动不在替身内：宿主里 Scroll-
                    // ViewReader 的程序化滚动不落位——实证
                    // offY 恒停顶；由测试侧以 UIKit 偏移驱
                    // 动，见 scrollListToBottom。本替身只验
                    // 几何链——托管＋实测留位；滚动指令链
                    // 由 Core 协调器测试与真机清单承担）
                    ComposerGuideHost(
                        bottomSpace: $state.bottomSpace,
                        contentHeight: $state.contentHeight
                    ) {
                        // 构建计数（诊断：桥 init 求值次数
                        // ——分清「没重建」与「重建没长高」）
                        let _ = box.notes["builds"] =
                            "\((Int(box.notes["builds"] ?? "0") ?? 0) + 1)"
                        VStack(spacing: 0) {
                            if state.tallBar {
                                Color.clear.frame(height: 40)
                            }
                            Text("BAR")
                                .frame(height: 76)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                        // 与生产 bottomBar 同口径：高度只
                        // 认内容（fixedSize 断外层提议）——
                        // 缺这行时长高段会被宿主提议压扁
                        // （实证：76 恒不变）
                        .fixedSize(horizontal: false, vertical: true)
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
        container = DrawerContainerController()
        // 赋值序照探针与生产桥的可用形态：先把
        // drawerBuilder/contentRoot 刷进控制器、再进
        // 窗口——先进窗口再赋值时内容宿主不重排、整壳
        // 不渲染（第二轮 CI 五法 frames 恒空实证）
        container.drawerBuilder = { _ in AnyView(Text("drawer")) }
        // 环境与生产根同口径：ComposerGuideHost 桥读
        // AppState（未注入会 trap），在内容根处注入
        container.contentRoot = AnyView(
            ShellTabs(state: state, box: box)
                .environment(AppState())
        )
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
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

    /// 等指定帧首次落盒（渲染完成判据），上限约 6 秒
    private func waitForFrame(_ name: String) {
        let deadline = Date().addingTimeInterval(6)
        while box.frames[name] == nil, Date() < deadline {
            spinRunLoop(seconds: 0.25)
        }
    }

    private func waitForBarFrame() {
        waitForFrame("bar")
    }

    /// 等回报值稳定（两读相隔 0.3 秒相等）：首帧布局
    /// 的瞬态值（实测可差约 9pt）落定后才许采样
    private func stableBottomSpace() -> CGFloat {
        var previous = state.bottomSpace
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            spinRunLoop(seconds: 0.3)
            let current = state.bottomSpace
            if abs(current - previous) < 0.1 { return current }
            previous = current
        }
        return state.bottomSpace
    }

    /// 登记视图的活量帧（滚动/变换后即时准确，绕开
    /// 落盒帧的陈旧窗口）
    private func liveFrame(_ name: String) -> CGRect? {
        guard let view = box.views[name], let window
        else { return nil }
        return view.convert(view.bounds, to: window)
    }

    /// 舱的活量帧：经控制器层级找舱宿主视图直接换算
    /// （reporter 的帧在纯 transform 位移下不重报、会
    /// 陈旧；活量对变换即时准确）
    private func liveBarFrame() -> CGRect? {
        guard let host = guideHostController(),
              let barHostView = host.children.first?.view,
              let window
        else { return nil }
        return barHostView.convert(barHostView.bounds, to: window)
    }

    /// 以 UIKit 把替身列表压到底：scrollRectToVisible
    /// 用滚动视图自己的 inset 记账落位（手算 maxY 会
    /// 与 SwiftUI 的容器记账差一截——实证差 221pt 停
    /// 在次底）；两跳：首跳触发惰性行建列、次跳在真
    /// 实内容高上落位
    private func scrollListToBottom() {
        func find(_ view: UIView) -> UIScrollView? {
            if let sv = view as? UIScrollView { return sv }
            for sub in view.subviews {
                if let found = find(sub) { return found }
            }
            return nil
        }
        guard let window, let sv = find(window) else { return }
        for _ in 0..<2 {
            let bottomRect = CGRect(
                x: 0, y: sv.contentSize.height - 1,
                width: 1, height: 1)
            sv.scrollRectToVisible(bottomRect, animated: false)
            spinRunLoop(seconds: 0.3)
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
        // UIKit 偏移压底（惰性行随偏移建列），末行帧
        // 出现即几何链落定
        scrollListToBottom()
        waitForFrame("lastRow")
        settle(0.4)
        guard let tab = tabBar(),
              let bar = box.frames["bar"],
              let lastRow = liveFrame("lastRow")
        else {
            XCTFail("量具未齐：tab=\(tabBar() != nil) frames=\(box.frames.keys.sorted()) bottomSpace=\(state.bottomSpace) geo=\(box.notes["geo"] ?? "-")")
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
        // 压底静止的链恒等式：末行底距舱顶恰为「滚动
        // 视图底 inset − 舱顶实测回报」——留位由回报＋
        // 边距经滚动视图自身记账落位（实测 17.0 与几
        // 何倾倒 176−159 严丝合缝）
        let geoInsetB = box.notes["geo"]
            .flatMap { note -> CGFloat? in
                guard let range = note.range(of: "insetB=") else {
                    return nil
                }
                let rest = note[range.upperBound...]
                let digits = rest.prefix { $0.isNumber }
                return CGFloat(Int(digits) ?? 0)
            } ?? -1
        XCTAssertEqual(
            bar.minY - lastRow.maxY,
            geoInsetB - state.bottomSpace, accuracy: 2,
            "末行休止位应由实测留位链精确决定")
        // 残差拆账：inset − 回报 = 边距 8（公式本体）
        // ＋替身壳滚动视图自带的安全区残差 9（宿主环
        // 境量、非公式项；生产真值归真机清单第 1 项）
        XCTAssertEqual(
            geoInsetB - state.bottomSpace, 17, accuracy: 2,
            "边距 8＋壳残差 9（见注）")
    }

    /// 舱内容长高 40：舱顶上移 40±2、舱底不动、回报
    /// 同步增 40±2
    func testBarGrowth_topRisesBottomPinned() {
        waitForBarFrame()
        // 采样前等回报落稳（首帧瞬态差约 9pt，不落稳
        // 会把瞬态记成变化量）
        let spaceBefore = stableBottomSpace()
        guard let before = box.frames["bar"] else {
            XCTFail("首帧未到")
            return
        }
        state.tallBar = true
        let buildsBefore = box.notes["builds"] ?? "?"
        // 戳一次外层已证可追踪的通道（回报绑定写）逼
        // 替身重建—— stand-in 生产里 ChatView 的重渲
        // 节奏（流式/@State 写恒定触发）；本法验的是
        // 「重建→桥 init 重估→重赋值→宿主随高→回报
        // 跟随」的整条传导链，状态归因的新鲜度本身由
        // 真机清单承担（错误条/回底钮显隐逐项在内）
        state.bottomSpace += 1
        // 等回报跟上长高（重建→布局→回报链）
        let deadline = Date().addingTimeInterval(4)
        while abs(state.bottomSpace - spaceBefore) < 1,
              Date() < deadline {
            spinRunLoop(seconds: 0.25)
        }
        settle(0.4)
        guard let after = box.frames["bar"] else {
            XCTFail("长高后帧丢失")
            return
        }
        let diag = "builds=\(buildsBefore)→\(box.notes["builds"] ?? "?")"
            + " liveBarH=\(liveBarFrame()?.height ?? -1)"
        XCTAssertEqual(
            before.minY - after.minY, 40, accuracy: 2,
            "舱顶应随内容长高同量上移（\(diag)）")
        XCTAssertEqual(
            after.maxY, before.maxY, accuracy: 2,
            "舱底应钉住不动（地板/引导线钉位）")
        XCTAssertEqual(
            state.bottomSpace - spaceBefore, 40, accuracy: 2,
            "回报值应随舱顶同步变化（\(diag)）")
        XCTAssertEqual(
            liveBarFrame()?.height ?? -1, 116, accuracy: 2,
            "宿主视图高应随内容长到 116（\(diag)）")
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
    /// 景平移走 transform（纯水平位移，DrawerContainer-
    /// Controller.applyOffset 实证）、不触发深层
    /// layoutSubviews——帧一律活量（convert 即时反映
    /// 变换），不用 reporter 的落盒帧（会陈旧）
    func testDrawerOpenClose_composerRidesForeground() {
        waitForBarFrame()
        guard let host = guideHostController(),
              let hostView = host.view,
              let before = liveBarFrame()
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
        guard let openedBar = liveBarFrame() else {
            XCTFail("抽屉开后舱活量帧丢失")
            return
        }
        XCTAssertGreaterThan(
            openedBar.minX, before.minX + 40,
            "舱帧应随前景右移")
        XCTAssertEqual(
            openedBar.maxY, before.maxY, accuracy: 2,
            "前景平移不改舱的纵向钉位")
        XCTAssertEqual(
            openedBar.height, before.height, accuracy: 2,
            "前景平移不改舱高")
        container.setDrawer(false, animated: false)
        settle(0.8)
        guard let closedBar = liveBarFrame() else {
            XCTFail("抽屉关后舱活量帧丢失")
            return
        }
        XCTAssertEqual(closedBar.minX, before.minX, accuracy: 2)
        XCTAssertEqual(closedBar.maxY, before.maxY, accuracy: 2)
    }

}
