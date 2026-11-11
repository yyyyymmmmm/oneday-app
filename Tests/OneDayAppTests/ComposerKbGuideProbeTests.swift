import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 小样探针第二轮（§178 施工前验证，非正式测试，随定稿删除）。
/// 变体 G（拟定新承载）：列表 ignoresSafeArea(.bottom)＋引导线托管舱。
/// 变体 A（现行承载 A/B 基准）：列表 safeAreaBar 挂替身舱。
/// 量：静止帧／真聚焦后／合成键盘帧通知后 三态的坞帧、页帧、
/// 舱帧、列表几何。结果以单行 PROBE2-REPORT 经 XCTFail 带出。
@MainActor
private final class ProbeBox {
    static let shared = ProbeBox()
    var textView: UITextView?
    var pageSafeBottom: CGFloat = -1
    var pageHeight: CGFloat = -1
    var scrollInsetsBottom: CGFloat = -1
    var scrollContainerHeight: CGFloat = -1
    var abBarFrame: CGRect = .zero
    var floorInset: CGFloat = 0

    func reset() {
        textView = nil
        pageSafeBottom = -1
        pageHeight = -1
        scrollInsetsBottom = -1
        scrollContainerHeight = -1
        abBarFrame = .zero
    }
}

private struct ProbeTextView: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.text = "probe"
        tv.font = .systemFont(ofSize: 16)
        tv.backgroundColor = .secondarySystemBackground
        ProbeBox.shared.textView = tv
        return tv
    }
    func updateUIView(_ uiView: UITextView, context: Context) {}
}

/// 帧回报件：把自身在窗口中的帧写进 box（A/B 基准舱用）
private struct FrameReporter: UIViewRepresentable {
    final class View: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            if let window {
                ProbeBox.shared.abBarFrame =
                    convert(bounds, to: window)
            }
        }
    }
    func makeUIView(context: Context) -> View { View() }
    func updateUIView(_ uiView: View, context: Context) {}
}

private final class ProbeHostController: UIViewController {
    let barHost: UIHostingController<AnyView> = {
        let root = AnyView(
            VStack(spacing: 8) {
                Text("notice-row").font(.caption)
                ProbeTextView().frame(height: 38)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        )
        return UIHostingController(rootView: root)
    }()
    private var bottomConstraint: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        barHost.sizingOptions = [.intrinsicContentSize]
        addChild(barHost)
        barHost.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(barHost.view)
        barHost.didMove(toParent: self)
        bottomConstraint = barHost.view.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor)
        NSLayoutConstraint.activate([
            barHost.view.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            barHost.view.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            bottomConstraint,
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 地板＝本视图底边（探针一轮实证：页帧已收在坞上方、
        // 视图底即坞顶，不得再减安全区数——双计）
        let guideTop = view.keyboardLayoutGuide.layoutFrame.minY
        let floorY = view.bounds.height - ProbeBox.shared.floorInset
        let target = min(guideTop, floorY)
        let constant = target - guideTop
        if abs(bottomConstraint.constant - constant) > 0.25 {
            bottomConstraint.constant = constant
        }
    }
}

private struct ProbeHostRep: UIViewControllerRepresentable {
    func makeUIViewController(
        context: Context
    ) -> ProbeHostController { ProbeHostController() }
    func updateUIViewController(
        _ controller: ProbeHostController, context: Context
    ) {}
}

private struct ProbePage<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(
                            of: proxy.safeAreaInsets.bottom,
                            initial: true
                        ) { _, v in
                            ProbeBox.shared.pageSafeBottom = v
                            ProbeBox.shared.pageHeight = proxy.size.height
                        }
                }
            }
    }
}

private func probeRows() -> some View {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(0..<40, id: \.self) { i in Text("row \(i)") }
    }
    .padding()
}

private struct ProbeShellGuide: View {
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            Tab("聊天", systemImage: "message", value: 0) {
                ProbePage {
                    ZStack {
                        ScrollView { probeRows() }
                            .ignoresSafeArea(edges: .bottom)
                            .onScrollGeometryChange(
                                for: CGFloat.self
                            ) { $0.contentInsets.bottom } action: { _, v in
                                ProbeBox.shared.scrollInsetsBottom = v
                            }
                            .onScrollGeometryChange(
                                for: CGFloat.self
                            ) { $0.containerSize.height } action: { _, v in
                                ProbeBox.shared.scrollContainerHeight = v
                            }
                        ProbeHostRep()
                    }
                }
            }
            Tab("其他", systemImage: "square", value: 1) {
                Text("other")
            }
        }
    }
}

private struct ProbeShellAB: View {
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            Tab("聊天", systemImage: "message", value: 0) {
                ProbePage {
                    ScrollView { probeRows() }
                        .onScrollGeometryChange(
                            for: CGFloat.self
                        ) { $0.contentInsets.bottom } action: { _, v in
                            ProbeBox.shared.scrollInsetsBottom = v
                        }
                        .onScrollGeometryChange(
                            for: CGFloat.self
                        ) { $0.containerSize.height } action: { _, v in
                            ProbeBox.shared.scrollContainerHeight = v
                        }
                        .safeAreaBar(edge: .bottom, spacing: 0) {
                            ZStack {
                                Color(.systemBackground)
                                ProbeTextView().frame(height: 38)
                                FrameReporter()
                            }
                            .frame(height: 60)
                        }
                }
            }
            Tab("其他", systemImage: "square", value: 1) {
                Text("other")
            }
        }
    }
}

@MainActor
final class ComposerKbGuideProbeTests: XCTestCase {
    private var window: UIWindow!
    private var controller: DrawerContainerController!

    private func boot(_ root: AnyView) {
        ProbeBox.shared.reset()
        controller = DrawerContainerController()
        controller.contentRoot = root
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    override func tearDown() async throws {
        window.isHidden = true
        window = nil
        controller = nil
        try await super.tearDown()
    }

    private func spin(_ seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func findViews<T: UIView>(
        _ type: T.Type, in view: UIView
    ) -> [T] {
        var out: [T] = []
        if let hit = view as? T { out.append(hit) }
        for sub in view.subviews {
            out.append(contentsOf: findViews(type, in: sub))
        }
        return out
    }

    private func locateProbe() -> ProbeHostController? {
        func search(_ vc: UIViewController) -> ProbeHostController? {
            if let probe = vc as? ProbeHostController { return probe }
            for child in vc.children {
                if let hit = search(child) { return hit }
            }
            return nil
        }
        return search(controller)
    }

    private func fmt(_ r: CGRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width))x\(Int(r.height)))"
    }

    private func snapshot(_ label: String) -> String {
        controller.view.layoutIfNeeded()
        let tabs = findViews(UITabBar.self, in: window).map {
            "tab@\(fmt($0.convert($0.bounds, to: window)))"
        }.joined(separator: ",")
        var probeDesc = ""
        if let probe = locateProbe() {
            let pv = probe.view!
            let guide = pv.keyboardLayoutGuide.layoutFrame
            let bar = probe.barHost.view.convert(
                probe.barHost.view.bounds, to: window)
            probeDesc = " probe@\(fmt(pv.convert(pv.bounds, to: window)))"
                + " guide(minY=\(Int(guide.minY)))"
                + " bar@\(fmt(bar))"
        }
        let wins = UIApplication.shared.windows.map {
            "\(type(of: $0))@\(fmt($0.frame))"
        }.joined(separator: ",")
        return "\(label): \(tabs);\(probeDesc)"
            + " pageSA=\(Int(ProbeBox.shared.pageSafeBottom))"
            + " pageH=\(Int(ProbeBox.shared.pageHeight))"
            + " scrInsetB=\(Int(ProbeBox.shared.scrollInsetsBottom))"
            + " scrContH=\(Int(ProbeBox.shared.scrollContainerHeight))"
            + " abBar@\(fmt(ProbeBox.shared.abBarFrame))"
            + " isFR=\(ProbeBox.shared.textView?.isFirstResponder ?? false)"
            + " wins=[\(wins)]"
    }

    private func postKeyboard(endY: CGFloat, height: CGFloat) {
        let frame = CGRect(x: 0, y: endY, width: 402, height: height)
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: frame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.25,
                UIResponder.keyboardAnimationCurveUserInfoKey: 7,
            ]
        )
    }

    private func flow(_ tag: String) -> String {
        spin(0.8)
        let rest = snapshot("REST")
        ProbeBox.shared.textView?.becomeFirstResponder()
        spin(1.6)
        let real = snapshot("REALKB")
        postKeyboard(endY: 538, height: 336)
        spin(1.0)
        let synth = snapshot("SYNTH")
        postKeyboard(endY: 874, height: 336)
        spin(1.0)
        let restored = snapshot("RESTORED")
        return "\(tag} | \(rest) | \(real) | \(synth) | \(restored)"
    }

    func testProbeGuideVariant() {
        boot(AnyView(ProbeShellGuide()))
        XCTFail("PROBE2-REPORT " + flow("GUIDE"))
    }

    func testProbeABVariant() {
        boot(AnyView(ProbeShellAB()))
        XCTFail("PROBE2-REPORT " + flow("AB"))
    }
}
