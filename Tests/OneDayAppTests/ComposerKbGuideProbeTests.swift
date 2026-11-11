import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 小样探针（§178 施工前验证，非正式测试）：与生产同构的嵌套——
/// DrawerContainerController → 内容宿主（TabView）→ 聊天页替身，
/// 聊天页内嵌引导线托管探针控制器（整栈替身挂 UIHostingController、
/// 底边钉 view.keyboardLayoutGuide＋地板补偿）。量三组事实：
/// 静止态几何、键盘升起后坞的去向（被键盘盖住还是骑到键盘上方）、
/// 引导线与 additionalSafeAreaInsets 的实测值。结果以单行
/// PROBE-REPORT 经 XCTFail 通道带出（本文件是探针、随施工定稿删除）。
@MainActor
private final class ProbeBox {
    static let shared = ProbeBox()
    var textView: UITextView?
    var pageSafeBottom: CGFloat = -1
    var scrollInsetsBottom: CGFloat = -1
    var keyboardEndFrames: [CGRect] = []
    var floorInset: CGFloat = 83
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

/// 引导线托管探针控制器：职责与拟定生产件同构——
/// 舱宿主底边钉本视图 keyboardLayoutGuide.top，地板常数在
/// 每次布局时按 min(guideTop, floorY) 补偿（键盘升起跟引导线、
/// 落下停在地板＝坞顶）。
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

private struct ProbeChatPage: View {
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<40, id: \.self) { i in
                        Text("row \(i)")
                    }
                }
                .padding()
            }
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentInsets.bottom
            } action: { _, value in
                ProbeBox.shared.scrollInsetsBottom = value
            }
            ProbeHostRep()
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        ProbeBox.shared.pageSafeBottom =
                            proxy.safeAreaInsets.bottom
                    }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, v in
                        if ProbeBox.shared.pageSafeBottom < 0 {
                            ProbeBox.shared.pageSafeBottom = v
                        }
                    }
            }
        }
    }
}

private struct ProbeShell: View {
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            Tab("聊天", systemImage: "message", value: 0) {
                ProbeChatPage()
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
    private var frameObserver: NSObjectProtocol?

    override func setUp() async throws {
        try await super.setUp()
        ProbeBox.shared.keyboardEndFrames = []
        frameObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main
        ) { note in
            if let frame = note.userInfo?[
                UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                ProbeBox.shared.keyboardEndFrames.append(frame)
            }
        }
        controller = DrawerContainerController()
        controller.contentRoot = AnyView(ProbeShell())
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    override func tearDown() async throws {
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
        window.isHidden = true
        window = nil
        controller = nil
        ProbeBox.shared.textView = nil
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

    private func frameInWindow(_ view: UIView) -> CGRect {
        view.convert(view.bounds, to: window)
    }

    /// 在容器层级里定位探针控制器（内容宿主的 SwiftUI 树内）
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

    private func snapshot(_ label: String) -> String {
        controller.view.layoutIfNeeded()
        let tabs = findViews(UITabBar.self, in: window)
        let tabDesc = tabs.map {
            "tabBar@\(fmt(frameInWindow($0)))"
        }.joined(separator: ",")
        var probeDesc = "probe=nil"
        if let probe = locateProbe() {
            let pv = probe.view!
            let guide = pv.keyboardLayoutGuide.layoutFrame
            let bar = frameInWindow(probe.barHost.view)
            probeDesc = "probeFrame@\(fmt(frameInWindow(pv)))"
                + " addSAI=\(Int(probe.additionalSafeAreaInsets.bottom))"
                + " viewSAI=\(Int(pv.safeAreaInsets.bottom))"
                + " guide(minY=\(Int(guide.minY)),h=\(Int(guide.height)))"
                + " bar@\(fmt(bar))"
        }
        let kbFrames = ProbeBox.shared.keyboardEndFrames
            .map { fmt($0) }.joined(separator: ",")
        return "\(label): \(tabDesc); \(probeDesc);"
            + " pageSA=\(Int(ProbeBox.shared.pageSafeBottom))"
            + " scrollInsetB=\(Int(ProbeBox.shared.scrollInsetsBottom))"
            + " kbNotifs=[\(kbFrames)]"
    }

    private func fmt(_ r: CGRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width))x\(Int(r.height)))"
    }

    func testProbeReport() {
        spin(0.8)
        if ProbeBox.shared.pageSafeBottom > 0 {
            ProbeBox.shared.floorInset = ProbeBox.shared.pageSafeBottom
        }
        let rest = snapshot("REST")
        ProbeBox.shared.textView?.becomeFirstResponder()
        spin(1.8)
        let kb = snapshot("KBUP")
        ProbeBox.shared.textView?.resignFirstResponder()
        spin(1.4)
        let rest2 = snapshot("REST2")
        XCTFail("PROBE-REPORT | \(rest) | \(kb) | \(rest2)")
    }
}
