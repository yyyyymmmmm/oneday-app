import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 症二阶段一·胶囊命中扫描 v2（2026-11-12 13:42 阶段门
/// 改判的数据路径；v2 订正归属仪表）
///
/// v1 教训（run 43164623681）：靠 accessibilityLabel
/// 在视图树里找钮帧落空（单元测试宿主内 SwiftUI 无障
/// 碍元素不物化为带标签的 UIView，三组 hub/model 帧
/// 全 nil、归属与串扰判定落空）。v2 改纯几何归属：
/// ②③组两钮以 .background GeometryReader 捕获钮帧；
/// ①组（生产件不可内插）以命中视图帧聚类还原两钮
/// 帧；每点记录命中视图类名＋帧，归属按命中帧相对
/// 分隔线（两钮帧间隙中点）的位置判定。
///
/// 层级与口径同 v1：DrawerContainerController 裸装
/// （静止态）→ TabView → 聊天面替身（ScrollView＋
/// .safeAreaBar(edge:.top) 顶栏、.soft 顶缘）。扫描
/// 行：状态栏带 y=30／顶栏衬垫带 minY−5（症状落点
/// 带、只记录）＋胶囊三行 top+2／mid／bot−2（x 步进
/// 2pt，串扰判定行）。
///
/// 串扰（几何定义）：落点距分隔线 ≥2pt 且位于身份
/// 侧，却命中帧中心在模型侧的视图、或命中跨两钮中
/// 心的整幅玻璃面；镜像同理。代码：H 身份域／M 模
/// 型域／G 跨域玻璃／U 整行命中（非玻璃）／· 无命中。
/// ③组阶段门（历史）：钮帧可测＋三行零串扰＋无 G
/// 点——阶段一判定未过（union 面结构上跨两域），
/// 主线改判动作级证据放行（XCUITest，见 TAP-
/// DISPATCH-DATA），③组结构断言随重建落地改记录
/// 制：本组只留仪表断言（两钮帧可测），串扰/跨域
/// 点数只记录、数据定格 HIT-SCAN-DATA。
@MainActor
final class CapsuleHitScanTests: XCTestCase {

    // MARK: - 脚手架

    private final class ScanBox {
        var capsuleFrame: CGRect?
        var hubFrame: CGRect?
        var modelFrame: CGRect?
    }

    private struct CapsuleFrameKey: PreferenceKey {
        static var defaultValue: CGRect? { nil }
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
            value = nextValue() ?? value
        }
    }

    private struct HubFrameKey: PreferenceKey {
        static var defaultValue: CGRect? { nil }
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
            value = nextValue() ?? value
        }
    }

    private struct ModelFrameKey: PreferenceKey {
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

    /// 聊天面替身：装配照生产 headerBar（左右玻璃圆
    /// 钮 44 命中域＋胶囊居中＋同组 padding）
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
                                        key: CapsuleFrameKey.self,
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
            .onPreferenceChange(CapsuleFrameKey.self) { value in
                box.capsuleFrame = value ?? box.capsuleFrame
            }
            .onPreferenceChange(HubFrameKey.self) { value in
                box.hubFrame = value ?? box.hubFrame
            }
            .onPreferenceChange(ModelFrameKey.self) { value in
                box.modelFrame = value ?? box.modelFrame
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

    private static func frameCapture<Key: PreferenceKey>(
        _ key: Key.Type
    ) -> some View where Key.Value == CGRect? {
        GeometryReader { proxy in
            Color.clear.preference(
                key: Key.self,
                value: proxy.frame(in: .global)
            )
        }
    }

    /// ②行本体玻璃（§179 缺陷构型）：两钮＋.glassEffect
    /// 直接挂行本体、无背景层玻璃；钮帧以 background
    /// 几何捕获（不拦截命中）
    private struct RowBodyGlassArm: View {
        var body: some View {
            HStack(spacing: OneDayMetrics.spacingS) {
                Button {
                } label: {
                    CapsuleHitScanTests.hubLabelContent(showName: true)
                }
                .buttonStyle(.odPressable)
                .background {
                    CapsuleHitScanTests.frameCapture(HubFrameKey.self)
                }

                CapsuleHitScanTests.hairline

                Button {
                } label: {
                    CapsuleHitScanTests.modelLabelContent
                }
                .buttonStyle(.odPressable)
                .background {
                    CapsuleHitScanTests.frameCapture(ModelFrameKey.self)
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: Capsule())
        }
    }

    /// ③苹果官方定式：GlassEffectContainer 包裹、两钮
    /// 各自交互玻璃＋glassEffectUnion 同一 id、无
    /// .odPressable；钮帧捕获挂在 union 之后
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
                .background {
                    CapsuleHitScanTests.frameCapture(HubFrameKey.self)
                }

                CapsuleHitScanTests.hairline

                Button {
                } label: {
                    CapsuleHitScanTests.modelLabelContent
                }
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectUnion(id: "identity-capsule", namespace: glassUnion)
                .background {
                    CapsuleHitScanTests.frameCapture(ModelFrameKey.self)
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, 7)
        }
    }

    // MARK: - 装配（真实容器层级）

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

    private func fmt(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(
            format: "(%.0f,%.0f %.0f×%.0f)",
            rect.minX, rect.minY, rect.width, rect.height
        )
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

    // MARK: - 扫描引擎（两遍：采样→定帧→几何归属）

    private struct RawSample {
        var x: CGFloat
        var hitClass: String?
        var hitFrame: CGRect?
        var isGlass: Bool
    }

    private struct ScanOutcome {
        var report: String
        var crosstalk: Int
        var spanningPoints: Int
        var framesResolved: Bool
    }

    private func runScan(armName: String, box: ScanBox) throws -> ScanOutcome {
        let capsule = try XCTUnwrap(box.capsuleFrame, "胶囊帧未量得")
        XCTAssertGreaterThan(capsule.width, 150, "胶囊应为全量档宽")

        // 采样行：状态栏带/衬垫带只记录，胶囊三行判串扰
        let recordRows: [(String, CGFloat)] = [
            ("status", 30),
            ("barpad", capsule.minY - 5),
        ]
        let judgedRows: [(String, CGFloat)] = [
            ("top+2", capsule.minY + 2),
            ("mid", capsule.midY),
            ("bot-2", capsule.maxY - 2),
        ]
        var samples: [String: [RawSample]] = [:]
        var inventory: [String: Int] = [:]
        for (rowName, y) in recordRows + judgedRows {
            var rowSamples: [RawSample] = []
            var x = capsule.minX + 1
            while x < capsule.maxX {
                let hit = window.hitTest(CGPoint(x: x, y: y), with: nil)
                var sample = RawSample(
                    x: x, hitClass: nil, hitFrame: nil, isGlass: false
                )
                if let hit {
                    sample.hitClass = String(describing: type(of: hit))
                    sample.hitFrame = hit.convert(hit.bounds, to: window)
                    sample.isGlass = isGlassInteraction(hit)
                    let key = "\(sample.hitClass!) \(fmt(sample.hitFrame))"
                    inventory[key, default: 0] += 1
                }
                rowSamples.append(sample)
                x += 2
            }
            samples[rowName] = rowSamples
        }

        // 定帧：②③组用捕获帧；①组聚类（左/右三分区内
        // 最高频的合格命中帧）
        var hubFrame = box.hubFrame
        var modelFrame = box.modelFrame
        if hubFrame == nil || modelFrame == nil {
            func dominantFrame(leftSide: Bool) -> CGRect? {
                var counts: [String: (CGRect, Int)] = [:]
                for (_, rowSamples) in samples {
                    for sample in rowSamples {
                        guard let frame = sample.hitFrame, !sample.isGlass,
                              frame.width >= 30,
                              frame.width < capsule.width - 10
                        else { continue }
                        let inSide = leftSide
                            ? sample.x < capsule.minX + capsule.width / 3
                            : sample.x > capsule.maxX - capsule.width / 3
                        guard inSide else { continue }
                        let key = fmt(frame)
                        counts[key] = (frame, (counts[key]?.1 ?? 0) + 1)
                    }
                }
                return counts.values.max(by: { $0.1 < $1.1 })?.0
            }
            hubFrame = hubFrame ?? dominantFrame(leftSide: true)
            modelFrame = modelFrame ?? dominantFrame(leftSide: false)
        }
        let framesResolved = hubFrame != nil && modelFrame != nil
        let divider: CGFloat? = if let hubFrame, let modelFrame {
            (hubFrame.maxX + modelFrame.minX) / 2
        } else {
            nil
        }

        // 几何归属＋串扰（死区 ±6pt 不计）
        func attribute(
            _ sample: RawSample, judged: Bool
        ) -> (code: Character, cross: Bool, spanning: Bool) {
            guard let frame = sample.hitFrame, let divider else {
                return ("·", false, false)
            }
            let pointSide = sample.x < divider
            if sample.isGlass {
                if let hubFrame, let modelFrame,
                   frame.contains(CGPoint(x: hubFrame.midX, y: hubFrame.midY)),
                   frame.contains(CGPoint(x: modelFrame.midX, y: modelFrame.midY)) {
                    return ("G", judged, true)
                }
                let glassSide = frame.midX < divider
                let cross = judged
                    && abs(sample.x - divider) >= 6
                    && glassSide != pointSide
                return (glassSide ? "H" : "M", cross, false)
            }
            if frame.width >= capsule.width - 4 {
                return ("U", judged, false)
            }
            let hitSide = frame.midX < divider
            let cross = judged
                && abs(sample.x - divider) >= 6
                && hitSide != pointSide
            return (hitSide ? "H" : "M", cross, false)
        }

        var lines: [String] = []
        lines.append(
            "arm=\(armName) capsule=\(fmt(capsule)) hub=\(fmt(hubFrame)) "
                + "model=\(fmt(modelFrame)) divider="
                + (divider.map { String(format: "%.0f", $0) } ?? "nil")
        )
        let glasses = glassFrames()
        lines.append(
            "arm=\(armName) glassTree="
                + (glasses.isEmpty
                    ? "none"
                    : glasses.map { fmt($0) }.joined(separator: " "))
        )
        var totalCross = 0
        var totalSpanning = 0
        for (rowName, _) in recordRows + judgedRows {
            let judged = judgedRows.contains { $0.0 == rowName }
            var codes: [Character] = []
            var cross = 0
            var flipX: CGFloat?
            var seenHub = false
            for sample in samples[rowName] ?? [] {
                let result = attribute(sample, judged: judged)
                codes.append(result.code)
                if result.cross { cross += 1 }
                if result.spanning { totalSpanning += 1 }
                if result.code == "H" { seenHub = true }
                if result.code == "M", seenHub, flipX == nil {
                    flipX = sample.x
                }
            }
            if judged { totalCross += cross }
            lines.append(
                "arm=\(armName) row=\(rowName) judged=\(judged) cross=\(cross) "
                    + "flipX=\(flipX.map { String(format: "%.0f", $0) } ?? "-") "
                    + rle(codes)
            )
        }
        for (key, count) in inventory.sorted(by: { $0.value > $1.value }).prefix(8) {
            lines.append("arm=\(armName) hit \(key) n=\(count)")
        }
        lines.append(
            "arm=\(armName) crosstalkTotal=\(totalCross) "
                + "spanningPoints=\(totalSpanning) framesResolved=\(framesResolved)"
        )
        return ScanOutcome(
            report: lines.joined(separator: "\n"),
            crosstalk: totalCross,
            spanningPoints: totalSpanning,
            framesResolved: framesResolved
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

    /// ①生产形态：IdentityCapsuleView 本体（阶段二
    /// 重建前＝§179 背景玻璃＋.odPressable；重建后＝
    /// 官方定式，扫描随生产件现形态走）——只记录
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
        emit(try runScan(armName: "A-current", box: box))
    }

    /// ②行本体玻璃（§179 缺陷构型）——只记录
    func testScanArmB_RowBodyGlassForm() throws {
        let box = ScanBox()
        mount(arm: RowBodyGlassArm(), box: box)
        emit(try runScan(armName: "B-rowbody", box: box))
    }

    /// ③苹果官方定式——记录制（原阶段门结构断言已
    /// 按改判处置：放行依据是动作门 CapsuleTapDis-
    /// patchUITests，本组只保留仪表断言——两钮帧
    /// 未能测得才算仪表落空）
    func testScanArmC_OfficialPattern_StageGate() throws {
        let box = ScanBox()
        mount(arm: OfficialPatternArm(), box: box)
        let outcome = try runScan(armName: "C-official", box: box)
        emit(outcome)
        XCTAssertTrue(
            outcome.framesResolved,
            "官方定式两钮帧未能测得——仪表落空"
        )
    }
}
