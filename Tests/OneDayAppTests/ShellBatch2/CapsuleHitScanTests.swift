import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 症二阶段一·胶囊命中扫描（2026-11-12 13:42 阶段门改判
/// 的数据路径）：原定的真机触摸逐点扫描本环境产不出，
/// 改判以**真实容器层级内的程序化 hitTest 逐点扫描**
/// 为数据路径（§179 的 256×42 结论即此法所得）。
///
/// 层级：DrawerContainerController（生产容器本体，裸
/// 装、静止态＝抽屉关/无动画）→ TabView → 聊天面替身
/// （ScrollView＋生产同构顶栏 .safeAreaBar(edge:.top)
/// 注册、.soft 顶缘）。对胶囊行逐点（x 步进 2pt；三
/// 个 y 行：上缘带 minY+2／中线 midY／下缘带 maxY−2）
/// 调用 window.hitTest，记录命中视图与动作归属（命中
/// 视图沿 superview 链的 accessibilityLabel 对照两钮
/// 标签；玻璃命中按其帧与两钮帧的包含关系归属）。
///
/// 三组同条件对照（内容度量恒同：Hermes／在线／
/// deepseek-flash／头像 28）：
/// ①现行形态＝生产 IdentityCapsuleView 本体（§179
///   玻璃降背景层＋.odPressable）——只记录不作断言；
/// ②行本体玻璃＝两钮＋.glassEffect 直接挂行本体
///   （§179 缺陷构型，0.49.3 玻璃位置变量）——只记录；
/// ③苹果官方定式＝GlassEffectContainer＋两钮各自
///   .glassEffect(.regular.interactive())＋
///   .glassEffectUnion 同一 id＋无 .odPressable
///   ——**阶段门：零串扰＋树内无跨两域玻璃面**。
///
/// 串扰定义：落点在身份钮帧内（x 内缩 1pt）却归模型
/// 域/跨域玻璃，或镜像；跨域玻璃＝玻璃交互视图帧同
/// 时覆盖两钮帧。扫描全表经 print 落 CI 日志
/// （CAPSULE-SCAN-BEGIN/END 标记间）＋附件留存。
@MainActor
final class CapsuleHitScanTests: XCTestCase {

    // MARK: - 脚手架

    private final class ScanBox {
        var capsuleFrame: CGRect?
    }

    private struct FrameKey: PreferenceKey {
        static var defaultValue: CGRect? { nil }
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
            value = nextValue() ?? value
        }
    }

    private final class StatusBarWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: StatusBarWindow!
    private var controller: DrawerContainerController!

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        controller = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// 聊天面替身：消息列表＋顶栏 safeAreaBar 注册，
    /// 顶栏装配照生产 headerBar（左右玻璃圆钮 44 命中
    /// 域＋胶囊居中 layoutPriority 1＋同组 padding）
    private struct ChatSurfaceStandIn<Arm: View>: View {
        let box: ScanBox
        @ViewBuilder var arm: () -> Arm

        var body: some View {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<40, id: \.self) { index in
                        Text("消息行 \(index)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 20)
            }
            .safeAreaBar(edge: .top) {
                VStack(spacing: OneDayMetrics.rowInnerGap) {
                    HStack(alignment: .center, spacing: OneDayMetrics.spacingS) {
                        sideButton("line.3.horizontal")
                        Spacer()
                        arm()
                            .layoutPriority(1)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: FrameKey.self,
                                        value: proxy.frame(in: .global)
                                    )
                                }
                            }
                        Spacer()
                        sideButton("bell")
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingS)
                .padding(.bottom, OneDayMetrics.spacingS)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onPreferenceChange(FrameKey.self) { value in
                box.capsuleFrame = value ?? box.capsuleFrame
            }
        }

        private func sideButton(_ symbol: String) -> some View {
            Button {
            } label: {
                Image(systemName: symbol)
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
        }
    }

    // MARK: - 三组胶囊形态（内容度量恒同）

    private static func hubLabelContent(showName: Bool) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Circle()
                .fill(.blue.gradient)
                .frame(width: 28, height: 28)
            if showName {
                Text("Hermes")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            HStack(spacing: OneDayMetrics.iconTextGap) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("在线")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .contentShape(Rectangle())
    }

    private static var modelLabelContent: some View {
        HStack(spacing: OneDayMetrics.stackGap) {
            Text("deepseek-flash")
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.inkSecondary)
        }
        .contentShape(Rectangle())
    }

    private static var hairline: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: 0.5, height: 18)
    }

    /// ②行本体玻璃（§179 缺陷构型）：两钮＋.glassEffect
    /// 直接挂行本体、无背景层玻璃
    private struct RowBodyGlassArm: View {
        var body: some View {
            HStack(spacing: OneDayMetrics.spacingS) {
                Button {
                } label: {
                    CapsuleHitScanTests.hubLabelContent(showName: true)
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("扫描-枢纽")

                CapsuleHitScanTests.hairline

                Button {
                } label: {
                    CapsuleHitScanTests.modelLabelContent
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("扫描-模型")
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: Capsule())
        }
    }

    /// ③苹果官方定式：GlassEffectContainer 包裹、两钮
    /// 各自交互玻璃＋glassEffectUnion 同一 id、无
    /// .odPressable（写法与 CapsuleFormComparison 的
    /// C 组实验件逐字同构，仅动作闭包换记录口）
    private struct OfficialPatternArm: View {
        @Namespace private var glassUnion

        var body: some View {
            GlassEffectContainer {
                ViewThatFits(in: .horizontal) {
                    row(showName: true)
                    row(showName: false)
                }
            }
        }

        private func row(showName: Bool) -> some View {
            HStack(spacing: OneDayMetrics.spacingS) {
                Button {
                } label: {
                    CapsuleHitScanTests.hubLabelContent(showName: showName)
                }
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectUnion(id: "identity-capsule", namespace: glassUnion)
                .accessibilityLabel("扫描-枢纽")

                CapsuleHitScanTests.hairline

                Button {
                } label: {
                    CapsuleHitScanTests.modelLabelContent
                }
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectUnion(id: "identity-capsule", namespace: glassUnion)
                .accessibilityLabel("扫描-模型")
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, 7)
        }
    }

    // MARK: - 装配（真实容器层级）

    /// DrawerContainerController 裸装＋TabView＋聊天面
    /// 替身；抽屉 builder 给空视图（静止态抽屉隐藏、
    /// 不参与命中），容器 offset 恒 0
    private func mount<Arm: View>(arm: Arm, box: ScanBox) {
        controller = DrawerContainerController()
        controller.drawerBuilder = { _ in AnyView(EmptyView()) }
        let root = TabView {
            ChatSurfaceStandIn(box: box) { arm }
                .tabItem { Label("聊天", systemImage: "message.fill") }
            Text("占位页")
                .tabItem { Label("占位", systemImage: "folder") }
        }
        controller.contentRoot = AnyView(root)
        window = StatusBarWindow(
            frame: CGRect(x: 0, y: 0, width: 393, height: 852)
        )
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.8)
        controller.view.layoutIfNeeded()
    }

    // MARK: - 视图树盘点

    private func walkViews(_ visit: (UIView) -> Void) {
        func walk(_ view: UIView) {
            visit(view)
            for sub in view.subviews { walk(sub) }
        }
        walk(window)
    }

    private func isGlassInteraction(_ view: UIView) -> Bool {
        String(describing: type(of: view)).contains("GlassInteraction")
    }

    private func glassFrames() -> [CGRect] {
        var frames: [CGRect] = []
        walkViews { view in
            if isGlassInteraction(view) {
                frames.append(view.convert(view.bounds, to: window))
            }
        }
        return frames
    }

    /// 按 accessibilityLabel 找钮帧（多候选取面积最大
    /// 者＝按钮本体层而非内部元素层）
    private func labeledFrame(_ label: String) -> CGRect? {
        var best: CGRect?
        walkViews { view in
            if view.accessibilityLabel == label {
                let frame = view.convert(view.bounds, to: window)
                if frame.width > 10,
                   frame.width * frame.height
                    > (best?.width ?? 0) * (best?.height ?? 0) {
                    best = frame
                }
            }
        }
        return best
    }

    private enum Domain {
        case hub, model, spanningGlass, other, none
    }

    /// 命中归属：先沿 superview 链找两钮标签；玻璃命
    /// 中无标签链时按其帧与两钮帧的覆盖关系定性
    private func domain(
        of hit: UIView?,
        hubLabel: String, modelLabel: String,
        hubFrame: CGRect?, modelFrame: CGRect?
    ) -> Domain {
        guard let hit else { return .none }
        var cursor: UIView? = hit
        while let view = cursor {
            if view.accessibilityLabel == hubLabel { return .hub }
            if view.accessibilityLabel == modelLabel { return .model }
            cursor = view.superview
        }
        if isGlassInteraction(hit) {
            let frame = hit.convert(hit.bounds, to: window)
            if let hubFrame, let modelFrame,
               frame.contains(hubFrame.midX, hubFrame.midY),
               frame.contains(modelFrame.midX, modelFrame.midY) {
                return .spanningGlass
            }
            if let hubFrame, frame.contains(hubFrame.midX, hubFrame.midY) {
                return .hub
            }
            if let modelFrame,
               frame.contains(modelFrame.midX, modelFrame.midY) {
                return .model
            }
            return .spanningGlass
        }
        if hit === window { return .none }
        return .other
    }

    private func rle(_ codes: [Character]) -> String {
        guard let first = codes.first else { return "" }
        var out: [String] = []
        var current = first
        var count = 0
        for code in codes {
            if code == current {
                count += 1
            } else {
                out.append("\(current)×\(count)")
                current = code
                count = 1
            }
        }
        out.append("\(current)×\(count)")
        return out.joined(separator: " ")
    }

    private func fmt(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(
            format: "(%.0f,%.0f %.0f×%.0f)",
            rect.minX, rect.minY, rect.width, rect.height
        )
    }

    // MARK: - 扫描引擎

    private struct ScanOutcome {
        var report: String
        var crosstalk: Int
        var spanningInTree: Bool
    }

    /// 对已装配的窗口执行一组的逐点扫描并生成报告行
    /// （H＝身份域 M＝模型域 G＝跨域玻璃 o＝其他视图
    /// ·＝窗口/滚动面）
    private func runScan(
        armName: String, hubLabel: String, modelLabel: String,
        box: ScanBox
    ) throws -> ScanOutcome {
        let capsule = try XCTUnwrap(box.capsuleFrame, "胶囊帧未量得")
        XCTAssertGreaterThan(capsule.width, 150, "胶囊应为全量档宽")
        let hubFrame = labeledFrame(hubLabel)
        let modelFrame = labeledFrame(modelLabel)
        let glasses = glassFrames()
        let spanningInTree = glasses.contains { frame in
            guard let hubFrame, let modelFrame else { return false }
            return frame.contains(hubFrame.midX, hubFrame.midY)
                && frame.contains(modelFrame.midX, modelFrame.midY)
        }

        var lines: [String] = []
        lines.append(
            "arm=\(armName) capsule=\(fmt(capsule)) "
                + "hub=\(fmt(hubFrame)) model=\(fmt(modelFrame))"
        )
        lines.append(
            "arm=\(armName) glassTree="
                + (glasses.isEmpty
                    ? "none"
                    : glasses.map { fmt($0) }.joined(separator: " "))
                + " spanningInTree=\(spanningInTree)"
        )

        var totalCrosstalk = 0
        let rows: [(String, CGFloat)] = [
            ("top+2", capsule.minY + 2),
            ("mid", capsule.midY),
            ("bot-2", capsule.maxY - 2),
        ]
        for (rowName, y) in rows {
            var codes: [Character] = []
            var cross = 0
            var flipX: CGFloat?
            var seenHub = false
            var x = capsule.minX + 1
            while x < capsule.maxX {
                let point = CGPoint(x: x, y: y)
                let hit = window.hitTest(point, with: nil)
                let hitDomain = domain(
                    of: hit,
                    hubLabel: hubLabel, modelLabel: modelLabel,
                    hubFrame: hubFrame, modelFrame: modelFrame
                )
                let code: Character
                switch hitDomain {
                case .hub: code = "H"
                case .model: code = "M"
                case .spanningGlass: code = "G"
                case .other: code = "o"
                case .none: code = "·"
                }
                codes.append(code)
                if code == "H" { seenHub = true }
                if code == "M", seenHub, flipX == nil { flipX = x }
                // 串扰：身份帧内（x 内缩 1pt）归模型/跨域
                // 玻璃，或镜像
                if let hubFrame,
                   point.x >= hubFrame.minX + 1,
                   point.x <= hubFrame.maxX - 1,
                   hitDomain == .model || hitDomain == .spanningGlass {
                    cross += 1
                }
                if let modelFrame,
                   point.x >= modelFrame.minX + 1,
                   point.x <= modelFrame.maxX - 1,
                   hitDomain == .hub || hitDomain == .spanningGlass {
                    cross += 1
                }
                x += 2
            }
            totalCrosstalk += cross
            lines.append(
                "arm=\(armName) row=\(rowName) cross=\(cross) "
                    + "flipX=\(flipX.map { String(format: "%.0f", $0) } ?? "-") "
                    + rle(codes)
            )
        }
        lines.append("arm=\(armName) crosstalkTotal=\(totalCrosstalk)")
        return ScanOutcome(
            report: lines.joined(separator: "\n"),
            crosstalk: totalCrosstalk,
            spanningInTree: spanningInTree
        )
    }

    private func emit(_ outcome: ScanOutcome) {
        print("CAPSULE-SCAN-BEGIN")
        print(outcome.report)
        print("CAPSULE-SCAN-END")
        let attachment = XCTAttachment(string: outcome.report)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 三组扫描

    /// ①现行形态：生产 IdentityCapsuleView 本体
    /// （§179 背景玻璃＋.odPressable）——只记录
    func testScanArmA_CurrentProductionForm() throws {
        let box = ScanBox()
        mount(
            arm: IdentityCapsuleView(
                avatar: Image(systemName: "person.circle.fill"),
                displayName: "Hermes",
                statusWord: "在线",
                statusColor: .green,
                avatarPointSize: 28,
                modelTriggerLabel: "deepseek-flash",
                modelAccessibilityLabel: "当前模型 deepseek-flash，切换模型",
                onOpenHub: {},
                onOpenModelPicker: {}
            ),
            box: box
        )
        let outcome = try runScan(
            armName: "A-current",
            hubLabel: "Hermes，在线，打开枢纽",
            modelLabel: "当前模型 deepseek-flash，切换模型",
            box: box
        )
        emit(outcome)
    }

    /// ②行本体玻璃（§179 缺陷构型）——只记录
    func testScanArmB_RowBodyGlassForm() throws {
        let box = ScanBox()
        mount(arm: RowBodyGlassArm(), box: box)
        let outcome = try runScan(
            armName: "B-rowbody",
            hubLabel: "扫描-枢纽",
            modelLabel: "扫描-模型",
            box: box
        )
        emit(outcome)
    }

    /// ③苹果官方定式——阶段门：零串扰＋树内无跨域玻璃
    func testScanArmC_OfficialPattern_StageGate() throws {
        let box = ScanBox()
        mount(arm: OfficialPatternArm(), box: box)
        let outcome = try runScan(
            armName: "C-official",
            hubLabel: "扫描-枢纽",
            modelLabel: "扫描-模型",
            box: box
        )
        emit(outcome)
        XCTAssertEqual(
            outcome.crosstalk, 0,
            "官方定式在真实容器层级内仍有串扰——按裁决停手回报，不许叠补丁"
        )
        XCTAssertFalse(
            outcome.spanningInTree,
            "官方定式树内仍存在跨两域玻璃交互视图"
        )
    }
}
