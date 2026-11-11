import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 热修诊断·第二轮（临时件）：第一轮已证——①sheet
/// 宿主迁移对命中路由零影响（A/B 全等）；②胶囊行
/// 的 .glassEffect 生成单一 UIPlatformGlassInter-
/// actionView（整颗胶囊一个命中体、两钮无独立命中
/// 视图）。本轮钉死三环：
/// 甲：胶囊内「标签外」点（上缘玻璃带／分隔线／左
///     角）的 hitTest 归属＋玻璃视图手势识别器转储；
/// 乙：把复刻装进生产壳层 DrawerContainerControl-
///     ler 后，胶囊帧是否上抬进状态栏带、带内点归
///     属是否变；
/// 丙：修复方向预验——D1 玻璃降为行背景层、D2 去
///     玻璃换 ultraThinMaterial，命中是否收回各自
///     标签、标签外点是否不再命中钮。
@MainActor
final class ModelPickerHitDomainDiagnosis2Tests: XCTestCase {

    private final class FrameLog {
        var hub: CGRect?
        var model: CGRect?
        var capsule: CGRect?
    }

    private struct FramesKey: PreferenceKey {
        static let defaultValue: [String: CGRect] = [:]
        static func reduce(
            value: inout [String: CGRect],
            nextValue: () -> [String: CGRect]
        ) {
            value.merge(nextValue()) { _, latest in latest }
        }
    }

    private struct PressableReplica: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.55 : 1)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
        }
    }

    private enum GlassMode {
        case rowGlass       // 生产现状：玻璃加在整行上
        case backgroundGlass // D1：玻璃降为行背景层
        case material       // D2：去玻璃、材质背景
    }

    private struct CapsuleReplica: View {
        var glassMode: GlassMode
        let frames: FrameLog

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
                VStack(spacing: 6) { headerBar }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onPreferenceChange(FramesKey.self) { value in
                frames.hub = value["hub"] ?? frames.hub
                frames.model = value["model"] ?? frames.model
                frames.capsule = value["capsule"] ?? frames.capsule
            }
        }

        private var headerBar: some View {
            HStack(alignment: .center, spacing: 8) {
                Button {} label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableReplica())

                Spacer()

                identityCapsule
                    .layoutPriority(1)

                Spacer()

                Button {} label: {
                    Image(systemName: "bell")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableReplica())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }

        private var identityCapsule: some View {
            ViewThatFits(in: .horizontal) {
                capsuleRow(showName: true)
                capsuleRow(showName: false)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: FramesKey.self,
                        value: ["capsule": proxy.frame(in: .global)]
                    )
                }
            }
        }

        private func capsuleRow(showName: Bool) -> some View {
            let row = HStack(spacing: 8) {
                Button {} label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 28, height: 28)
                        if showName {
                            Text("Hermes")
                                .font(.headline)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        HStack(spacing: 5) {
                            Circle().fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("在线")
                                .font(.footnote)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableReplica())
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FramesKey.self,
                            value: ["hub": proxy.frame(in: .global)]
                        )
                    }
                }

                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 0.5, height: 18)

                Button {} label: {
                    HStack(spacing: 3) {
                        Text("deepseek-flash")
                            .font(.callout)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableReplica())
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FramesKey.self,
                            value: ["model": proxy.frame(in: .global)]
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            switch glassMode {
            case .rowGlass:
                return AnyView(row.glassEffect(.regular, in: Capsule()))
            case .backgroundGlass:
                return AnyView(
                    row.background {
                        Capsule()
                            .fill(Color.clear)
                            .glassEffect(.regular, in: Capsule())
                    }
                )
            case .material:
                return AnyView(
                    row.background(.ultraThinMaterial, in: Capsule())
                )
            }
        }
    }

    private final class StatusBarWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: StatusBarWindow!

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

    private func describe(_ view: UIView?) -> String {
        guard let view else { return "nil" }
        let frame = view.convert(view.bounds, to: window)
        return "\(type(of: view))\(frame)"
    }

    /// 在给定窗口里装一个根控制器并完成布局
    private func install(_ controller: UIViewController) {
        window = StatusBarWindow(
            frame: CGRect(x: 0, y: 0, width: 393, height: 852)
        )
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        controller.view.layoutIfNeeded()
    }

    private func probe(
        frames: FrameLog, label: String
    ) -> [String] {
        var lines: [String] = ["--- probe \(label) ---"]
        lines.append("capsule=\(String(describing: frames.capsule))")
        lines.append("hub=\(String(describing: frames.hub))")
        lines.append("model=\(String(describing: frames.model))")
        guard let capsule = frames.capsule,
              let hub = frames.hub,
              let model = frames.model else {
            lines.append("NO FRAMES")
            return lines
        }
        let hubHit = window.hitTest(
            CGPoint(x: hub.midX, y: hub.midY), with: nil
        )
        let modelHit = window.hitTest(
            CGPoint(x: model.midX, y: model.midY), with: nil
        )
        lines.append("hubCenterHit=\(describe(hubHit))")
        lines.append("modelCenterHit=\(describe(modelHit))")
        lines.append(
            "sameHitView=\(hubHit != nil && hubHit === modelHit)"
        )

        func attribute(_ view: UIView?) -> String {
            guard let view else { return "nil" }
            if let modelHit,
               view === modelHit || view.isDescendant(of: modelHit) {
                return "MODEL-VIEW"
            }
            if let hubHit,
               view === hubHit || view.isDescendant(of: hubHit) {
                return "HUB-VIEW"
            }
            return "OTHER(\(describe(view)))"
        }

        // 胶囊内标签外点：上缘带（模型侧/枢纽侧）、
        // 下缘带、分隔线、左角、右角
        let dividerX = hub.maxX + 4 + 0.25
        let points: [(String, CGPoint)] = [
            ("topBand@hubX", CGPoint(x: hub.midX, y: capsule.minY + 2)),
            ("topBand@modelX", CGPoint(x: model.midX, y: capsule.minY + 2)),
            ("bottomBand@modelX", CGPoint(x: model.midX, y: capsule.maxY - 2)),
            ("divider", CGPoint(x: dividerX, y: capsule.midY)),
            ("leftCorner", CGPoint(x: capsule.minX + 3, y: capsule.midY)),
            ("rightCorner", CGPoint(x: capsule.maxX - 3, y: capsule.midY)),
            ("strip30@modelX", CGPoint(x: model.midX, y: 30)),
            ("strip30@hubX", CGPoint(x: hub.midX, y: 30)),
        ]
        for (name, point) in points {
            lines.append(
                "\(name) \(point)->\(attribute(window.hitTest(point, with: nil)))"
            )
        }

        // 玻璃交互视图与手势识别器转储
        var glassViews: [UIView] = []
        func walk(_ view: UIView) {
            if String(describing: type(of: view))
                .contains("GlassInteraction") {
                glassViews.append(view)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)
        lines.append("glassViews=\(glassViews.count)")
        for glass in glassViews {
            let frame = glass.convert(glass.bounds, to: window)
            let recognizers = (glass.gestureRecognizers ?? []).map {
                String(describing: type(of: $0))
            }
            lines.append(
                "glass \(frame) recognizers=\(recognizers)"
            )
        }
        return lines
    }

    func testDiagnoseRound2() {
        var all: [String] = []

        // 甲＋丙：平装三种玻璃形态
        for (mode, name) in [
            (GlassMode.rowGlass, "A-rowGlass(production)"),
            (.backgroundGlass, "D1-backgroundGlass"),
            (.material, "D2-material"),
        ] {
            let frames = FrameLog()
            install(UIHostingController(
                rootView: CapsuleReplica(glassMode: mode, frames: frames)
            ))
            all.append(contentsOf: probe(frames: frames, label: name))
            window.isHidden = true
            window = nil
        }

        // 乙：生产壳层 DrawerContainerController 承载
        let frames = FrameLog()
        let drawer = DrawerContainerController()
        drawer.drawerBuilder = { _ in AnyView(Text("抽屉")) }
        install(drawer)
        drawer.contentRoot = AnyView(
            CapsuleReplica(glassMode: .rowGlass, frames: frames)
        )
        spinRunLoop(seconds: 0.4)
        drawer.view.layoutIfNeeded()
        all.append(contentsOf: probe(frames: frames, label: "C-inDrawerShell"))

        let report = all.joined(separator: "\n")
        print("DIAG2-BEGIN\n\(report)\nDIAG2-END")
        XCTFail("DIAGNOSTIC2 DUMP:\n\(report)")
    }
}
