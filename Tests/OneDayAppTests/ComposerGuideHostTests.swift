import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §186 输入舱引导线托管的宿主级几何验收：把生产件
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
/// 7. §186.8 无戳归因三法：舱内结构状态（错误条行
///    /回底钮行/多行生长）切换不写回报绑定，构建
///    次数、舱高与留位回报经归因链自然更新
/// 8. §186.8 抽屉 animated 关闭中途命中：动画途中
///    舱不可达、落定后恢复可命中（补修 A 端到端）
/// 键盘跟随本身 CI 模拟器升不起真键盘（探针两轮实
/// 证：isFirstResponder 可达、无键盘窗、合成通知
/// SwiftUI 不认），归真机清单（DESIGN §186）不在此断言
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
        /// §195：顶安全区回报的接收槽（本替身只验通
        /// 道在场、值域由生产整页关承担）
        var topSafe: CGFloat = 0
        var tallBar = false
        /// §186.8 结构三态开关（舱内独有状态：只改这
        /// 些、不写 bottomSpace，验刷新归因本身）
        var errorRow = false
        var jumpRow = false
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

    /// 聊天页替身：按 ChatView §186 接法复刻（同树
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
                        topSafe: $state.topSafe
                    ) {
                        // 构建计数（诊断：桥 init 求值次数
                        // ——分清「没重建」与「重建没长高」）
                        let _ = box.notes["builds"] =
                            "\((Int(box.notes["builds"] ?? "0") ?? 0) + 1)"
                        VStack(spacing: 0) {
                            // §186.8 结构三态段（生产 bot-
                            // tomBar 条件段的同构复刻：栈
                            // spacingS、每段高含其后一档
                            // 栈距）：错误条行（条 36＋距
                            // 8＝44）／回底钮行（命中域
                            // 44＋距 8＝52）／多行生长（输
                            // 入段本体 +40、无额外栈距）
                            if state.errorRow {
                                VStack(spacing: 0) {
                                    Text("ERR")
                                        .frame(height: 36)
                                        .frame(maxWidth: .infinity)
                                    Color.clear.frame(height: 8)
                                }
                            }
                            if state.jumpRow {
                                VStack(spacing: 0) {
                                    HStack {
                                        Spacer(minLength: 0)
                                        Color.clear.frame(
                                            width: 44, height: 44)
                                    }
                                    Color.clear.frame(height: 8)
                                }
                            }
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
                        // 舱的 SwiftUI 真帧量具（托管树内
                        // 专用）：UIViewRepresentable 的报
                        // 帧在托管树内不随内容生长更新（实
                        // 证：生产 Preference 通道已量到
                        // +40、reporter 帧恒 76）——长高断
                        // 言改读本量具（与生产量测同族：
                        // GeometryReader 全局帧、onChange
                        // 落盒）
                        .background {
                            GeometryReader { geo in
                                Color.clear.onChange(
                                    of: geo.frame(in: .global),
                                    initial: true
                                ) { _, frame in
                                    box.notes["barGeo"] =
                                        "\(frame.minY)/\(frame.height)/\(frame.maxY)"
                                }
                            }
                        }
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

    /// 等回报增量抵达期望（±2）的截止轮询：结构切
    /// 换→归因重建→树内布局→Preference 帧回报链的
    /// 落定判据（§186.8 无戳三态法共用）
    private func waitForReportDelta(
        from base: CGFloat, expected: CGFloat
    ) {
        let deadline = Date().addingTimeInterval(4)
        while abs((state.bottomSpace - base) - expected) > 2,
              Date() < deadline {
            spinRunLoop(seconds: 0.25)
        }
    }

    /// 命中视图是否落在指定祖先的子树内（§186.8 动
    /// 画中途命中断言用）
    private func isDescendant(
        _ view: UIView?, of ancestor: UIView
    ) -> Bool {
        var node = view
        while let current = node {
            if current === ancestor { return true }
            node = current.superview
        }
        return false
    }

    /// 登记视图的活量帧（滚动/变换后即时准确，绕开
    /// 落盒帧的陈旧窗口）
    private func liveFrame(_ name: String) -> CGRect? {
        guard let view = box.views[name], let window
        else { return nil }
        return view.convert(view.bounds, to: window)
    }

    /// 舱的活量帧：量 reporter 登记的舱本体视图（滚动
    /// /变换后即时准确，绕开落盒帧的陈旧窗口）。宿主
    /// 自 §186 定版起全高填充、其帧不再是舱帧——舱帧
    /// 只认舱本体（树内以理想高成帧）
    private func liveBarFrame() -> CGRect? {
        liveFrame("bar")
    }

    /// 舱的 SwiftUI 真帧（替身的 GeometryReader 量具
    /// 落盒值 minY/height/maxY）：托管树内的生长只有
    /// SwiftUI 侧量具如实（见替身 barGeo 注）
    private func barGeo() -> (
        minY: CGFloat, height: CGFloat, maxY: CGFloat
    )? {
        guard let raw = box.notes["barGeo"] else { return nil }
        let parts = raw.split(separator: "/")
            .compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return (
            CGFloat(parts[0]), CGFloat(parts[1]),
            CGFloat(parts[2])
        )
    }

    private func waitForBarGeo() {
        let deadline = Date().addingTimeInterval(4)
        while box.notes["barGeo"] == nil, Date() < deadline {
            spinRunLoop(seconds: 0.25)
        }
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
    /// 同步增 40±2（舱帧读替身的 SwiftUI 真帧量具
    /// barGeo——托管树内的生长 reporter 量不到，见
    /// 替身注；回报断言走生产通道本身）
    func testBarGrowth_topRisesBottomPinned() {
        waitForBarFrame()
        waitForBarGeo()
        // 采样前等回报落稳（首帧瞬态差约 9pt，不落稳
        // 会把瞬态记成变化量）
        let spaceBefore = stableBottomSpace()
        guard let before = barGeo() else {
            XCTFail("首帧未到")
            return
        }
        let buildsBefore = box.notes["builds"] ?? "?"
        state.tallBar = true
        // §186.8 补修（Codex 复核点名）：原法在此戳回
        // 报绑定（bottomSpace += 1）逼替身重建，绕开
        // 了刷新归因——戳已删。本法现与三态切换三法
        // （错误条/回底钮行/多行无戳）同口径：只改舱
        // 内状态，验「归因重建→桥 init 重估→重赋值
        // →宿主随高→回报跟随」整链自发成立
        // 等回报跟上长高（重建→树内布局→帧回报链）：
        // 等变化量抵达 40 而非任一变化
        let deadline = Date().addingTimeInterval(4)
        while abs((state.bottomSpace - spaceBefore) - 40) > 2,
              Date() < deadline {
            spinRunLoop(seconds: 0.25)
        }
        settle(0.4)
        guard let after = barGeo() else {
            XCTFail("长高后帧丢失")
            return
        }
        let diag = "builds=\(buildsBefore)→\(box.notes["builds"] ?? "?")"
            + " barGeo=\(box.notes["barGeo"] ?? "-")"
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
            after.height, 116, accuracy: 2,
            "舱本体高应随内容长到 116（\(diag)）")
    }

    /// §186.8 无戳归因（错误条行）：只改舱内结构状
    /// 态、不写 bottomSpace——构建次数、舱高、留位
    /// 回报必须全经归因链自然更新（原长高法靠戳回
    /// 报绑定逼重建、绕开了归因，本组三法补上）
    func testErrorRowToggle_growthFlowsWithoutReportPoke() {
        waitForBarFrame()
        waitForBarGeo()
        let spaceBefore = stableBottomSpace()
        guard let before = barGeo() else {
            XCTFail("首帧未到")
            return
        }
        let buildsBefore = Int(box.notes["builds"] ?? "0") ?? 0
        state.errorRow = true
        waitForReportDelta(from: spaceBefore, expected: 44)
        settle(0.4)
        guard let after = barGeo() else {
            XCTFail("切换后帧丢失")
            return
        }
        let buildsAfter = Int(box.notes["builds"] ?? "0") ?? 0
        XCTAssertGreaterThan(
            buildsAfter, buildsBefore,
            "舱内状态变化应经归因链触发替身重建（无人戳绑定）")
        XCTAssertEqual(
            after.height - before.height, 44, accuracy: 2,
            "错误条行出现应令舱高 +44（条 36＋栈距 8）")
        XCTAssertEqual(
            after.maxY, before.maxY, accuracy: 2,
            "舱底应钉住不动")
        XCTAssertEqual(
            state.bottomSpace - spaceBefore, 44, accuracy: 2,
            "留位回报应自然跟随 +44")
    }

    /// §186.8 无戳归因（回底钮行）：同上，钮行段高
    /// 52（命中域 44＋栈距 8）
    func testJumpRowToggle_growthFlowsWithoutReportPoke() {
        waitForBarFrame()
        waitForBarGeo()
        let spaceBefore = stableBottomSpace()
        guard let before = barGeo() else {
            XCTFail("首帧未到")
            return
        }
        let buildsBefore = Int(box.notes["builds"] ?? "0") ?? 0
        state.jumpRow = true
        waitForReportDelta(from: spaceBefore, expected: 52)
        settle(0.4)
        guard let after = barGeo() else {
            XCTFail("切换后帧丢失")
            return
        }
        let buildsAfter = Int(box.notes["builds"] ?? "0") ?? 0
        XCTAssertGreaterThan(
            buildsAfter, buildsBefore,
            "舱内状态变化应经归因链触发替身重建（无人戳绑定）")
        XCTAssertEqual(
            after.height - before.height, 52, accuracy: 2,
            "回底钮行出现应令舱高 +52（命中域 44＋栈距 8）")
        XCTAssertEqual(
            after.maxY, before.maxY, accuracy: 2,
            "舱底应钉住不动")
        XCTAssertEqual(
            state.bottomSpace - spaceBefore, 52, accuracy: 2,
            "留位回报应自然跟随 +52")
    }

    /// §186.8 无戳归因（多行生长）：与长高法同事实、
    /// 独立成法钉归因——只改舱内状态，构建/舱高/回
    /// 报三者自发更新（长高法本轮已同步删戳）
    func testMultilineGrowth_reportFollowsWithoutPoke() {
        waitForBarFrame()
        waitForBarGeo()
        let spaceBefore = stableBottomSpace()
        guard let before = barGeo() else {
            XCTFail("首帧未到")
            return
        }
        let buildsBefore = Int(box.notes["builds"] ?? "0") ?? 0
        state.tallBar = true
        waitForReportDelta(from: spaceBefore, expected: 40)
        settle(0.4)
        guard let after = barGeo() else {
            XCTFail("长高后帧丢失")
            return
        }
        let buildsAfter = Int(box.notes["builds"] ?? "0") ?? 0
        XCTAssertGreaterThan(
            buildsAfter, buildsBefore,
            "舱内状态变化应经归因链触发替身重建（无人戳绑定）")
        XCTAssertEqual(
            before.minY - after.minY, 40, accuracy: 2,
            "舱顶应随多行生长同量上移")
        XCTAssertEqual(
            after.maxY, before.maxY, accuracy: 2,
            "舱底应钉住不动")
        XCTAssertEqual(
            after.height, 116, accuracy: 2,
            "舱本体高应长到 116")
        XCTAssertEqual(
            state.bottomSpace - spaceBefore, 40, accuracy: 2,
            "留位回报应自然跟随 +40")
    }

    /// §186.8 抽屉 animated 关闭中途命中（补修 A 的
    /// 同构壳端到端）：关闭动画起始帧起，容器命中不
    /// 得落进输入舱（修复前内容在起始帧即恢复可点、
    /// 透传判定帧又是位移前快照——点会落进正在移动
    /// 的舱）；落定后舱带恢复可命中、几何复原
    func testDrawerAnimatedClose_midFlightBarUnreachableThenRestored() {
        waitForBarFrame()
        guard let host = guideHostController(),
              let hostView = host.view,
              let before = liveBarFrame()
        else {
            XCTFail("host 或首帧未就位")
            return
        }
        container.setDrawer(true, animated: false)
        settle(0.8)
        guard let openedBar = liveBarFrame() else {
            XCTFail("抽屉开后舱活量帧丢失")
            return
        }
        container.setDrawer(false, animated: true)
        // 起始帧同步断言（不泵 runloop）：动画在途、
        // 呈现层还带着位移——此刻命中舱带不得入舱。
        // 采样点取开态舱的可见窄条内（舱随前景右移
        // 后只有左段在屏面内、中点已出屏会让断言空过）
        let midHit = container.view.hitTest(
            container.view.convert(
                CGPoint(x: openedBar.minX + 40, y: openedBar.midY),
                from: window),
            with: nil)
        XCTAssertFalse(
            isDescendant(midHit, of: hostView),
            "关闭动画途中命中落进了正在移动的输入舱")
        spinRunLoop(seconds: 2.0)
        settle(0.4)
        guard let closedBar = liveBarFrame() else {
            XCTFail("抽屉关后舱活量帧丢失")
            return
        }
        XCTAssertEqual(
            closedBar.minX, before.minX, accuracy: 2,
            "落定后舱几何应复原")
        XCTAssertEqual(
            closedBar.maxY, before.maxY, accuracy: 2)
        let settledHit = container.view.hitTest(
            container.view.convert(
                CGPoint(x: closedBar.midX, y: closedBar.midY),
                from: window),
            with: nil)
        XCTAssertTrue(
            isDescendant(settledHit, of: hostView),
            "落定后舱带应恢复可命中")
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

    /// §194 键盘半边（单值驱动）：宿主壳升不起真键
    /// 盘（文件头注），本关以合成通知验收——通知帧
    /// 就是生产修法的输入通道本身（键盘本人的广播
    /// 真值）：willShow 帧顶 538 → 舱底贴 538；
    /// willChangeFrame 改帧顶 500 → 舱底跟到 500；
    /// willHide → 舱底/舱顶回静息坞位分毫不差
    func testKeyboardNotifications_barFollowsFrameThenRestores() {
        waitForBarFrame()
        guard let rest = liveBarFrame() else {
            XCTFail("首帧未就位")
            return
        }
        let center = NotificationCenter.default
        func postKeyboard(
            _ name: Notification.Name, top: CGFloat
        ) {
            center.post(
                name: name, object: nil,
                userInfo: [
                    UIResponder.keyboardFrameEndUserInfoKey:
                        NSValue(cgRect: CGRect(
                            x: 0, y: top, width: 402,
                            height: 874 - top)),
                    UIResponder
                        .keyboardAnimationDurationUserInfoKey:
                        0.0,
                    UIResponder
                        .keyboardAnimationCurveUserInfoKey:
                        7,
                ]
            )
        }
        postKeyboard(
            UIResponder.keyboardWillShowNotification, top: 538)
        settle(0.6)
        guard let shown = liveBarFrame() else {
            XCTFail("键盘升起后舱帧丢失")
            return
        }
        XCTAssertEqual(
            shown.maxY, 538, accuracy: 2,
            "舱底应贴通知广播的键盘顶 538，实测 \(shown.maxY)")
        XCTAssertEqual(
            shown.minY, rest.minY + (538 - rest.maxY),
            accuracy: 2,
            "舱应整舱上移同量（高不变、底贴键盘顶）")
        postKeyboard(
            UIResponder.keyboardWillChangeFrameNotification,
            top: 500)
        settle(0.6)
        guard let reframed = liveBarFrame() else {
            XCTFail("键盘改帧后舱帧丢失")
            return
        }
        XCTAssertEqual(
            reframed.maxY, 500, accuracy: 2,
            "舱底应随 willChangeFrame 跟到 500，实测 \(reframed.maxY)")
        postKeyboard(
            UIResponder.keyboardWillHideNotification, top: 874)
        settle(0.6)
        guard let restored = liveBarFrame() else {
            XCTFail("键盘收起后舱帧丢失")
            return
        }
        XCTAssertEqual(
            restored.maxY, rest.maxY, accuracy: 1,
            "收起后舱底应回静息坞顶分毫不差")
        XCTAssertEqual(
            restored.minY, rest.minY, accuracy: 1,
            "收起后舱顶应回静息位")
    }

}
