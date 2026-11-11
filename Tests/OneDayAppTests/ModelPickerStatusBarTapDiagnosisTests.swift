import SwiftUI
import UIKit
import XCTest

/// 热修诊断（临时件，定因后随修法一并处置）：用户报
/// 0.50.21 点状态栏区域打开模型选择页。本测试在宿主
/// 窗口内复刻聊天页顶栏的真实结构（顶 safeAreaBar 注
/// 册＋.scrollEdgeEffectStyle(.soft, for: .top)＋
/// ViewThatFits 双档身份胶囊＋枢纽/模型双钮＋玻璃），
/// 窗口安全区覆写为真机状态栏高（顶 59），量测：
/// ①两钮标签的窗口坐标帧；②状态栏带内若干点（x 取
/// 两钮标签中心）经 UIWindow.hitTest 的归属——命中
/// 视图与「在标签中心处命中的同一视图」比对身份。
/// 变体 A＝现行生产（sheet 挂聊天根）；变体 B＝补丁
/// 前（sheet 挂模型钮本体）。两变体对照定位回归面。
@MainActor
final class ModelPickerStatusBarTapDiagnosisTests: XCTestCase {

    // MARK: - 探针记录

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

    // MARK: - 复刻视图（结构与 ChatView 顶栏逐项同构）

    private struct PressableReplica: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.55 : 1)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
        }
    }

    private struct SheetPlacement: ViewModifier {
        var onButton: Bool
        @Binding var shown: Bool

        func body(content: Content) -> some View {
            if onButton {
                content.sheet(isPresented: $shown) {
                    Text("模型选择面（复刻）")
                }
            } else {
                content
            }
        }
    }

    private struct CapsuleReplica: View {
        var sheetOnButton: Bool
        @Binding var pickerShown: Bool
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
                VStack(spacing: 6) {
                    headerBar
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .modifier(
                SheetPlacement(onButton: !sheetOnButton, shown: $pickerShown)
            )
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
            HStack(spacing: 8) {
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

                Button {
                    pickerShown = true
                } label: {
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
                .modifier(
                    SheetPlacement(onButton: sheetOnButton, shown: $pickerShown)
                )
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
            .glassEffect(.regular, in: Capsule())
        }
    }

    // MARK: - 窗口（覆写安全区＝真机状态栏带）

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

    // MARK: - 量测

    private func measure(sheetOnButton: Bool) -> [String] {
        let frames = FrameLog()
        var shown = false
        let binding = Binding<Bool>(
            get: { shown },
            set: { shown = $0 }
        )
        let root = CapsuleReplica(
            sheetOnButton: sheetOnButton,
            pickerShown: binding,
            frames: frames
        )
        let host = UIHostingController(rootView: root)
        window = StatusBarWindow(
            frame: CGRect(x: 0, y: 0, width: 393, height: 852)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        host.view.layoutIfNeeded()

        var lines: [String] = []
        let variant = sheetOnButton ? "B(sheet@button)" : "A(sheet@root)"
        lines.append("=== variant \(variant) ===")
        lines.append("hostSafeArea=\(host.view.safeAreaInsets)")
        lines.append("capsuleFrame=\(String(describing: frames.capsule))")
        lines.append("hubLabelFrame=\(String(describing: frames.hub))")
        lines.append("modelLabelFrame=\(String(describing: frames.model))")

        guard let hub = frames.hub, let model = frames.model else {
            lines.append("NO FRAMES CAPTURED")
            return lines
        }

        // 标签中心命中视图＝该钮的命中承载视图（身份基准）
        func hitIdentity(at point: CGPoint) -> UIView? {
            window.hitTest(point, with: nil)
        }
        let modelHit = hitIdentity(
            at: CGPoint(x: model.midX, y: model.midY)
        )
        let hubHit = hitIdentity(
            at: CGPoint(x: hub.midX, y: hub.midY)
        )
        lines.append(
            "modelCenterHit=\(describe(modelHit)) hubCenterHit=\(describe(hubHit))"
        )

        func attribute(_ view: UIView?) -> String {
            guard let view else { return "nil" }
            if let modelHit, view === modelHit || view.isDescendant(of: modelHit) {
                return "MODEL"
            }
            if let hubHit, view === hubHit || view.isDescendant(of: hubHit) {
                return "HUB"
            }
            return "OTHER(\(describe(view)))"
        }

        for y in [8.0, 18, 28, 38, 48, 56] {
            let atModel = attribute(
                window.hitTest(CGPoint(x: model.midX, y: y), with: nil)
            )
            let atHub = attribute(
                window.hitTest(CGPoint(x: hub.midX, y: y), with: nil)
            )
            lines.append(
                "strip y=\(Int(y)) x=model(\(Int(model.midX)))->\(atModel) x=hub(\(Int(hub.midX)))->\(atHub)"
            )
        }

        // 状态栏带内全部 UIKit 视图帧转储（找溢出帧）
        var dump: [String] = []
        func walk(_ view: UIView, depth: Int) {
            let frame = view.convert(view.bounds, to: window)
            if frame.minY < 59, frame.height > 0, frame.width > 0, depth > 0 {
                dump.append(
                    "\(String(describing: type(of: view))) \(frame)"
                )
            }
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        walk(window, depth: 0)
        lines.append("stripViews(\(dump.count)):")
        lines.append(contentsOf: dump.prefix(60).map { "  \($0)" })
        return lines
    }

    private func describe(_ view: UIView?) -> String {
        guard let view else { return "nil" }
        let frame = view.convert(view.bounds, to: window)
        return "\(type(of: view))\(frame)"
    }

    func testDiagnoseStatusBarTapAttribution() {
        var all: [String] = []
        all.append(contentsOf: measure(sheetOnButton: false))
        window.isHidden = true
        window = nil
        all.append(contentsOf: measure(sheetOnButton: true))
        let report = all.joined(separator: "\n")
        print("DIAG-BEGIN\n\(report)\nDIAG-END")
        XCTFail("DIAGNOSTIC DUMP:\n\(report)")
    }
}
