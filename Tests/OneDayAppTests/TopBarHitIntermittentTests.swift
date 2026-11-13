import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 顶簇间歇失灵 rig（fix/topbar-hit-intermittent）：
/// 用户真机实报（0.50.30）抽屉钮＋模型胶囊「有时」
/// 打不开。生产同构壳（DrawerContainerController
/// 前景＋真 TabView，与 ComposerGuideHostTests 同
/// 式）里挂**生产件** TopBarGuideHost，顶簇内容按
/// ChatView.topBarCluster 的现行构成复刻（抽屉钮
/// 本体照 headerBar 原样、HubAvatarButton 与
/// ModelCapsuleView 用生产件、16pt 命中死区同位）。
///
/// 证据纪律＝路由环为判据（本线三轮取证演进的
/// 终点，逐项有 CI 实证）：断言＝在钮的活量中心
/// 做 container.view.hitTest（生产壳的命中入
/// 口、与 ComposerGuideHostTests 同式），命中
/// 必须落进顶簇宿主子树。这是真触摸 began 相
/// 位的同一次裁决（触摸终生绑定命中视图），也
/// 是本病灶所在层（透传宿主的命中可达性）的直
/// 接判据。触发→开面的接线不在本 rig 里重证：
/// 钮是生产件＋生产闭包（§175 已验接线），真
/// App 真点由 XCUITest 动作门（TopBarSingle-
/// ActionTapTests，§202）覆盖；状态间唯一变量
/// 就是命中路由，本 rig 只隔离它。弃用两路（均
/// 有 CI 实证）：合成触摸两路在本宿主连原生
/// UIControl 都点不响；无障碍激活——托管树在单
/// 测宿主里不物化 a11y 元素（实测 count=0）。
///
/// 装配要点：测试窗的安全区顶以子类覆写对齐
/// SwiftUI 页内边距（54）——设备上两者同源（窗
/// 口安全区），宿主的落位补偿在静息态≈0（与设
/// 备常态同构）；补偿≠0 的状态（坞显隐落定重
/// 算、手动重排）才是本病的发作态，rig 逐个制
/// 造并裁决。
///
/// 状态空间：静息基线／宿主帧被重排但无布局拍
/// （±49 与 −8 两档，模拟 §195 落定重算挪帧）／
/// 坞显隐落定（键盘态的结构同构件）／切格往返／
/// sheet 开关往返／抽屉开合（含动画途中）／进展
/// 行生长／外观切换。
@MainActor
final class TopBarHitIntermittentTests: XCTestCase {

    // MARK: - 状态盒与量具

    /// 顶簇替身状态（文件作用域：@Observable 宏展
    /// 开够得着，见 ComposerGuideHostTests 的教训）
    @Observable
    final class RigState {
        var selection = 0
        var topBarHeight: CGFloat = 60
        /// 聚焦态（替身以此驱动 .toolbar 坞显隐，与
        /// 生产 composerFocused 同一位的开关）
        var focused = false
        var progressShown = false
        var showSheet = false
        var drawerTaps = 0
        var hubTaps = 0
        var modelTaps = 0
        var bellTaps = 0
    }

    private final class FrameBox: @unchecked Sendable {
        var views: [String: UIView] = [:]
    }

    /// 帧登记量具（照 ComposerGuideHostTests 的
    /// GuideFrameReporter 同式：登记视图本体，断言
    /// 时一律活量 convert，不读落盒快照）
    private struct FrameReporter: UIViewRepresentable {
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
                register()
            }
            override func didMoveToWindow() {
                super.didMoveToWindow()
                register()
            }
            private func register() {
                guard window != nil else { return }
                box?.views[name] = self
            }
        }
    }

    /// 测试窗：安全区顶覆写为 54，与本装配里
    /// SwiftUI 页的顶内边距对齐（设备上同一来源；
    /// 裸 UIWindow 的 safeAreaInsets.top=0 会让宿
    /// 主补偿恒 −54、静息态就失真）
    private final class RigWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 54, left: 0, bottom: 0, right: 0)
        }
    }

    // MARK: - 动作级取证（路由环）

    /// 视图是否落在顶簇宿主子树内（闸门放行的充
    /// 分条件：命中下行穿过闸门后只能落进宿主子
    /// 树或被驳回落到下层列表）
    private func isInsideBarHost(_ view: UIView?) -> Bool {
        guard let host = topHost(), let view else { return false }
        let barRoot = host.traceBarView
        var cursor: UIView? = view
        while let current = cursor {
            if current === barRoot { return true }
            cursor = current.superview
        }
        return false
    }



    // MARK: - 顶簇替身（按 ChatView 现行构成复刻）

    private struct ClusterReplica: View {
        @Bindable var state: RigState
        let box: FrameBox
        var body: some View {
            VStack(spacing: OneDayMetrics.rowInnerGap) {
                headerReplica
                if state.progressShown {
                    // 进展胶囊行的结构替身（生产 Pro-
                    // gressCapsuleView 显形时的同位行）
                    Capsule()
                        .fill(Color.gray.opacity(0.4))
                        .frame(height: 28)
                        .padding(.horizontal, OneDayMetrics.pageGutter)
                }
            }
        }

        /// 顶栏本体：构成照 ChatView.headerBar（左
        /// 钮本体逐字同式、中央组生产件＋16pt 死
        /// 区、右铃铛同式），动作改记替身计数
        private var headerReplica: some View {
            HStack(alignment: .center, spacing: 0) {
                Button {
                    state.drawerTaps += 1
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(
                            size: HeaderButtonSpec.glyphPointSize,
                            weight: .regular
                        ))
                        .foregroundStyle(Palette.ink)
                        .frame(
                            width: HeaderButtonSpec.diameter,
                            height: HeaderButtonSpec.diameter
                        )
                        .glassEffect(.regular, in: Circle())
                        .frame(
                            width: OneDayMetrics.minTapTarget,
                            height: OneDayMetrics.minTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("会话列表")
                .background(FrameReporter(name: "drawerBtn", box: box))

                Spacer(minLength: OneDayMetrics.spacingS)

                HStack(alignment: .center, spacing: 0) {
                    HubAvatarButton(
                        avatar: Image(systemName: "pawprint.fill"),
                        displayName: "三狗",
                        statusWord: "在线",
                        statusColor: .green,
                        avatarPointSize: 36,
                        onOpenHub: { state.hubTaps += 1 }
                    )
                    Color.clear
                        .frame(
                            width: OneDayMetrics.spacingM,
                            height: OneDayMetrics.minTapTarget
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {}
                    ModelCapsuleView(
                        modelTriggerLabel: "claude-sonnet-4-6",
                        modelAccessibilityLabel: "当前模型，切换模型",
                        onOpenModelPicker: { state.modelTaps += 1 }
                    )
                    .background(FrameReporter(name: "capsule", box: box))
                }

                Spacer(minLength: OneDayMetrics.spacingS)

                Button {
                    state.bellTaps += 1
                } label: {
                    Image(systemName: "bell")
                        .font(.system(
                            size: HeaderButtonSpec.glyphPointSize,
                            weight: .regular
                        ))
                        .foregroundStyle(Palette.ink)
                        .frame(
                            width: HeaderButtonSpec.diameter,
                            height: HeaderButtonSpec.diameter
                        )
                        .glassEffect(.regular, in: Circle())
                        .frame(
                            width: OneDayMetrics.minTapTarget,
                            height: OneDayMetrics.minTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("通知")
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingS)
            .padding(.bottom, OneDayMetrics.spacingS)
        }
    }

    /// 聊天页替身：列表替身＋.overlay 挂生产 Top-
    /// BarGuideHost（与生产 messageList 的挂位同
    /// 式）；坞显隐开关与 sheet 承载挂本页（与生
    /// 产 ChatView 同位）
    private struct ChatReplica: View {
        @Bindable var state: RigState
        let box: FrameBox
        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<40, id: \.self) { row in
                        Text("row \(row)")
                            .frame(height: 34)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .overlay {
                TopBarGuideHost(barHeight: $state.topBarHeight) {
                    ClusterReplica(state: state, box: box)
                }
            }
            .toolbar(
                state.focused ? .hidden : .visible,
                for: .tabBar
            )
            .sheet(isPresented: $state.showSheet) {
                Text("sheet替身")
            }
        }
    }

    private struct ShellTabs: View {
        @Bindable var state: RigState
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
    private var modelContainer: ModelContainer!
    private var state: RigState!
    private var box: FrameBox!

    override func setUp() async throws {
        try await super.setUp()
        state = RigState()
        box = FrameBox()
        let state = state!
        let box = box!
        let schema = Schema([ChatThread.self, ChatEntry.self])
        modelContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        container = DrawerContainerController()
        // 赋值序照 ComposerGuideHostTests 的可用形
        // 态：先刷 builder/contentRoot、再进窗口
        container.drawerBuilder = { _ in AnyView(Text("drawer")) }
        container.contentRoot = AnyView(
            ShellTabs(state: state, box: box)
                .environment(AppState())
                .modelContainer(modelContainer)
        )
        window = RigWindow(
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
        modelContainer = nil
        state = nil
        box = nil
        try await super.tearDown()
    }

    // MARK: - 泵与定位

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

    private func waitForView(_ name: String) {
        let deadline = Date().addingTimeInterval(6)
        while box.views[name] == nil, Date() < deadline {
            spinRunLoop(seconds: 0.25)
        }
    }

    private func topHost() -> TopBarGuideHostController? {
        func find(
            _ vc: UIViewController
        ) -> TopBarGuideHostController? {
            if let host = vc as? TopBarGuideHostController {
                return host
            }
            for child in vc.children {
                if let found = find(child) { return found }
            }
            return nil
        }
        return container.flatMap { find($0) }
    }

    /// 登记视图的活量窗口帧（convert 即时量，绕开
    /// 一切落盒快照）
    private func liveFrame(of name: String) -> CGRect? {
        guard let view = box.views[name], let window
        else { return nil }
        return view.convert(view.bounds, to: window)
    }

    private func liveCenter(of name: String) -> CGPoint? {
        liveFrame(of: name).map {
            CGPoint(x: $0.midX, y: $0.midY)
        }
    }

    /// 顶簇宿主的活量窗口帧（钮的真实像素落位）
    private func liveBarFrame() -> CGRect? {
        guard let host = topHost(), let window else { return nil }
        let bar = host.traceBarView
        return bar.convert(bar.bounds, to: window)
    }

    /// 闸门缓存帧（诊断专用：Mirror 读透传根视图
    /// 的 barFrameInWindow，只入日志不入断言——断
    /// 言只认动作计数）
    private func gateFrame() -> CGRect? {
        guard let host = topHost(), let rootView = host.view
        else { return nil }
        let mirror = Mirror(reflecting: rootView)
        for child in mirror.children {
            if child.label == "barFrameInWindow",
               let rect = child.value as? CGRect {
                return rect
            }
        }
        return nil
    }

    private func diag(_ label: String) -> String {
        let live = liveBarFrame()
            .map { "(\(Int($0.minX)),\(Int($0.minY)))-(\(Int($0.maxX)),\(Int($0.maxY)))" }
            ?? "nil"
        let gate = gateFrame()
            .map { "(\(Int($0.minX)),\(Int($0.minY)))-(\(Int($0.maxX)),\(Int($0.maxY)))" }
            ?? "nil"
        return "\(label)：活帧=\(live) 闸门帧=\(gate)"
    }

    /// 路由环：在钮的活量中心经生产壳入口（con-
    /// tainer.view）做命中裁决，命中必须落进顶簇
    /// 宿主子树（被驳回/被越界挡下＝落到下层列表
    /// 或 nil，本病的直接判据）
    private func assertRouting(
        _ name: String, _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let center = liveCenter(of: name) else {
            XCTFail("\(label)：量具未登记 \(name)", file: file, line: line)
            return
        }
        let hit = container.view.hitTest(center, with: nil)
        XCTAssertTrue(
            isInsideBarHost(hit),
            "\(label)：命中未落进顶簇宿主（命中=\(String(describing: hit))；\(diag(label))）",
            file: file, line: line)
    }

    private func assertDrawerFires(
        _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        assertRouting("drawerBtn", label, file: file, line: line)
    }

    private func assertCapsuleFires(
        _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        assertRouting("capsule", label, file: file, line: line)
    }

    private func primeRig() {
        waitForView("capsule")
        waitForView("drawerBtn")
        settle(0.6)
    }

    // MARK: - 状态空间

    /// S0 静息基线（兼两环取证通道自检）：两钮在
    /// 静息态必须两环全过——本法红＝取证通道或装
    /// 配坏了，不是产品病，后续状态结论全部作废
    /// 先修 rig
    func testRest_baseline_bothButtonsFire() {
        primeRig()
        assertDrawerFires("静息/抽屉钮")
        assertCapsuleFires("静息/模型胶囊")
    }

    /// S1a 宿主帧被重排上移 49、无布局拍（§195 落
    /// 定重算把 overlay 帧挪到 13 的同型事）：直接
    /// 改透传根视图的帧原点（尺寸不变——原点位移
    /// 不必然带布局拍，正是生产里补偿与闸门双双
    /// 依赖布局拍的风险口），不调 layoutIfNeeded、
    /// 不泵 runloop，随即在钮的**活量中心**点按。
    /// 修复前预期：闸门缓存帧停在旧位、点被驳回
    /// （动作不触发＝红）；修复后：闸门按活层级裁
    /// 决、点落钮上即触发（绿）
    func testOverlayShiftUp49_noLayout_tapsStillFire() {
        primeRig()
        guard let host = topHost() else {
            XCTFail("topHost 未就位")
            return
        }
        host.view!.frame.origin.y -= 49
        // 同步裁决（不泵 runloop，布局拍不许先行治愈）
        assertRouting("capsule", "重排上移49无布局拍/路由")
    }

    /// S1b 同上、方向向下 +49（坞回显/落定反向的
    /// 同型重排）
    func testOverlayShiftDown49_noLayout_tapsStillFire() {
        primeRig()
        guard let host = topHost() else {
            XCTFail("topHost 未就位")
            return
        }
        host.view!.frame.origin.y += 49
        assertRouting("drawerBtn", "重排下移49无布局拍/路由")
    }

    /// S1c 小位移 −8（特征化）：活量中心仍落在缓
    /// 存闸门帧内——修复前后都应触发，钉住「间歇」
    /// 的量级梯度（位移小于钮心到闸门边的距离时
    /// 症状不显）
    func testOverlayShiftSmall8_noLayout_tapsFire() {
        primeRig()
        guard let host = topHost() else {
            XCTFail("topHost 未就位")
            return
        }
        host.view!.frame.origin.y -= 8
        assertCapsuleFires("重排上移8")
    }

    /// S2 切格往返：去别的格再回来，落定后两钮可
    /// 点（viewDidAppear 是补偿的既有触发口，本法
    /// 验往返不留后遗症）
    func testTabRoundTrip_tapsFireAfterReturn() {
        primeRig()
        state.selection = 1
        settle(0.8)
        state.selection = 0
        settle(1.2)
        assertDrawerFires("切格往返/抽屉钮")
        assertCapsuleFires("切格往返/模型胶囊")
    }

    /// S3 sheet 开关往返：模型面同型的呈现/消散一
    /// 轮后两钮可点（呈现转场会不会留下命中残伤）
    func testSheetRoundTrip_tapsFireAfterDismiss() {
        primeRig()
        state.showSheet = true
        settle(1.0)
        state.showSheet = false
        settle(1.0)
        assertCapsuleFires("sheet往返/模型胶囊")
        assertDrawerFires("sheet往返/抽屉钮")
    }

    /// S4 抽屉开合：关闭动画途中点顶簇不得入钮
    /// （§186.8 容器层在途拦截的现行正确行为，防
    /// 本线修法把它拆掉）；落定后两钮恢复可点
    func testDrawerRoundTrip_midAnimationBlockedThenFires() {
        primeRig()
        container.setDrawer(true, animated: false)
        settle(0.8)
        container.setDrawer(false, animated: true)
        // 动画途中（同步采样、不泵）：抽屉钮活量中
        // 心的命中不得落进顶簇宿主（前景在移动、容
        // 器层拦截命中——与底舱 §186.8 的 hitTest
        // 同口径取证）
        if let center = liveCenter(of: "drawerBtn") {
            let hit = container.view.hitTest(center, with: nil)
            XCTAssertFalse(
                isInsideBarHost(hit),
                "抽屉关闭动画途中命中不应落进顶簇宿主")
        } else {
            XCTFail("动画途中抽屉钮活量中心缺失")
        }
        spinRunLoop(seconds: 2.0)
        settle(0.4)
        assertDrawerFires("抽屉落定/抽屉钮")
        assertCapsuleFires("抽屉落定/模型胶囊")
    }

    /// S5 坞显隐落定（键盘聚焦态的结构同构件）：
    /// focused 开→坞藏、关→坞回，两态落定后各点
    /// 一次（落定重算的重排若带布局拍应自愈，本
    /// 法钉它确实自愈、不留残伤）
    func testTabBarHideShow_tapsFireInBothStates() {
        primeRig()
        state.focused = true
        settle(1.2)
        assertCapsuleFires("坞隐藏落定/模型胶囊")
        state.focused = false
        settle(1.2)
        assertCapsuleFires("坞回显落定/模型胶囊")
        assertDrawerFires("坞回显落定/抽屉钮")
    }

    /// S6 进展行生长：顶簇长高一轮（宿主定高约束
    /// ＋闸门帧经布局拍刷新）后点第一行两钮——生
    /// 长不得把第一行钮挤出闸门
    func testProgressGrowth_tapsFireAfterGrowth() {
        primeRig()
        state.progressShown = true
        settle(1.2)
        assertDrawerFires("进展生长/抽屉钮")
        assertCapsuleFires("进展生长/模型胶囊")
        state.progressShown = false
        settle(1.2)
        assertCapsuleFires("进展收起/模型胶囊")
    }

    /// S7 外观切换：深色一轮后两钮可点（特征化状
    /// 态，几何中立、只防切换留残伤）
    func testAppearanceToggle_tapsFire() {
        primeRig()
        window.overrideUserInterfaceStyle = .dark
        settle(0.8)
        assertDrawerFires("深色/抽屉钮")
        assertCapsuleFires("深色/模型胶囊")
        window.overrideUserInterfaceStyle = .light
        settle(0.8)
        assertCapsuleFires("回浅色/模型胶囊")
    }
}
