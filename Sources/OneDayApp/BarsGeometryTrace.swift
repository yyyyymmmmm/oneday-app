import SwiftUI
import UIKit

/// 栏位几何自述（0.50.25 真机翻车第二轮·诊断构建专用，
/// hotfix/05025-bars2）：模拟器全真机条件（场景窗＋深
/// 色＋粗体/AX＋长会话落盘恢复）复现不出栏位缺席，按
/// 主线裁决转真机量测——本件在生产装配点采样层级几
/// 何（各宿主帧/安全区/命中实测），落 UserDefaults 供
/// 设置页自述面读出分享。只留证、不参与业务判定；定
/// 案后整件随诊断分支退役，不入主线口径。
@MainActor
enum BarsGeometryTrace {
    /// 抽屉左缘热区宽度（与 OneDayMetrics.drawerEdgeZone 同值 24；
    /// 该符号在本目标不可见，此处用本地常量替代，语义不变）
    private static let edgeZoneWidth: CGFloat = 24
    private static let key = "bars.geometry.traces"
    private static let cap = 6
    private static var didScheduleColdStart = false

    static var captures: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static var report: String {
        let all = captures
        return all.isEmpty
            ? "（尚无采样：请先打开一次聊天页，等几秒再回来看）"
            : all.joined(separator: "\n\n")
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// 冷启采样排程（ChatView.onAppear 首拍调用）：
    /// +1/+3/+6 秒各采一次，进程内只排一次
    static func scheduleColdStartCaptures() {
        guard !didScheduleColdStart else { return }
        didScheduleColdStart = true
        for (delay, tag) in [
            (1.0, "cold+1s"), (3.0, "cold+3s"), (6.0, "cold+6s"),
        ] {
            Task { @MainActor in
                try? await Task.sleep(
                    for: .milliseconds(Int64(delay * 1000))
                )
                capture(tag: tag)
            }
        }
    }

    /// 事件采样（抽屉开合等）：调用点即时采一次
    static func captureEvent(tag: String) {
        capture(tag: tag)
    }

    // MARK: - 采样本体

    private static func capture(tag: String) {
        guard let window = keyWindow() else {
            store(tag: tag, body: "keyWindow 缺席")
            return
        }
        var lines: [String] = []
        let tc = window.traitCollection
        let osv = ProcessInfo.processInfo.operatingSystemVersion
        lines.append(
            "[\(tag)] \(timestamp()) win=\(fmt(window.frame))"
                + " safe=\(insets(window.safeAreaInsets))"
                + " style=\(tc.userInterfaceStyle == .dark ? "dark" : "light")"
                + " bold=\(tc.legibilityWeight == .bold)"
                + " size=\(tc.preferredContentSizeCategory.rawValue)"
                + " os=\(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)"
        )

        // 抽屉容器（VC 树定位）
        var drawer: DrawerContainerController?
        var composer: ComposerGuideHostController?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? DrawerContainerController {
                drawer = hit
            }
            if let hit = vc as? ComposerGuideHostController {
                composer = hit
            }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }

        if let drawer {
            func isEdgeZone(_ view: UIView) -> Bool {
                let widthDelta = abs(view.frame.width - edgeZoneWidth)
                let atLeftEdge = view.frame.minX == 0
                return widthDelta < 1 && atLeftEdge
            }
            let edge = drawer.view.subviews.first(where: isEdgeZone)
            let edgeInfo: String
            if let edge {
                let recognizers: [UIGestureRecognizer] =
                    edge.gestureRecognizers ?? []
                let recs = recognizers
                    .map { (rec: UIGestureRecognizer) -> String in
                        let kind = rec is UIPanGestureRecognizer
                            ? "pan" : "rec"
                        let state = rec.isEnabled ? "on" : "off"
                        return "\(kind):\(state)"
                    }
                    .joined(separator: ",")
                edgeInfo = "edge=\(fmt(edge.frame))"
                    + " hidden=\(edge.isHidden) recs=[\(recs)]"
            } else {
                edgeInfo = "edge=缺席"
            }
            lines.append(
                "drawerVC frame=\(fmt(frameIn(window, drawer.view)))"
                    + " safe=\(insets(drawer.view.safeAreaInsets))"
                    + " semantic=\(drawer.semanticPresented)"
                    + " travel=\(Int(drawer.travel)) \(edgeInfo)"
            )
        } else {
            lines.append("drawerVC 缺席")
        }

        // 顶栏 pocket
        let pocket = findViews(window) { view in
            String(describing: type(of: view))
                .contains("ScrollPocketBarInteraction")
                && frameIn(window, view).width > 400
                && frameIn(window, view).minY < 100
        }.first
        if let pocket {
            let elements = findViews(pocket) { view in
                String(describing: type(of: view))
                    .contains("ScrollPocketElementInteraction")
                    && frameIn(window, view).width >= 20
                    && frameIn(window, view).height >= 20
            }.count
            lines.append(
                "pocket=\(fmt(frameIn(window, pocket)))"
                    + " elements=\(elements)"
                    + " hidden=\(pocket.isHidden)"
                    + " alpha=\(pocket.alpha)"
            )
        } else {
            lines.append("pocket=缺席")
        }

        // 输入舱宿主
        if let composer {
            var line = "composerVC view="
                + "\(fmt(frameIn(window, composer.view)))"
                + " safe=\(insets(composer.view.safeAreaInsets))"
                + " hidden=\(composer.view.isHidden)"
            let bar = findViews(composer.view) { view in
                String(describing: type(of: view))
                    .contains("UIPlatformGlassInteractionView")
                    && frameIn(window, view).width > 300
            }.first
            if let bar {
                line += " bar=\(fmt(frameIn(window, bar)))"
            } else {
                line += " bar=缺席"
            }
            let texts = findViews(composer.view) {
                $0 is UITextView
            }.count
            line += " textViews=\(texts)"
            lines.append(line)
            // §191 增补：控制器附加安全区＋键盘引导线
            // 帧（窗口系）——尺寸协商污染链的直接物证面
            let guide = composer.view.keyboardLayoutGuide
            let guideInWindow = composer.view.convert(
                guide.layoutFrame, to: window
            )
            lines.append(
                "composerAdd=\(insets(composer.additionalSafeAreaInsets))"
                    + " guide=\(fmt(guideInWindow))"
            )
            // §191 增补：祖先链逐层（类名/窗口系帧/安
            // 全区）——坏帧若修后仍在，一眼定位哪层引入
            var chain: [String] = []
            var ancestor = composer.view.superview
            var depth = 0
            while let view = ancestor, depth < 14 {
                chain.append(
                    "L\(depth) \(typeName(view))"
                        + " \(fmt(frameIn(window, view)))"
                        + " safe=\(insets(view.safeAreaInsets))"
                )
                if view === window { break }
                ancestor = view.superview
                depth += 1
            }
            lines.append(
                "ancestors:\n" + chain.joined(separator: "\n")
            )
        } else {
            lines.append("composerVC=缺席")
        }

        // 坞与列表
        let platter = findViews(window) { view in
            String(describing: type(of: view))
                .contains("UITabBarPlatterView")
        }.first
        if let platter {
            lines.append(
                "platter=\(fmt(frameIn(window, platter)))"
            )
        } else {
            lines.append("platter=缺席")
        }
        let scroll = findViews(window) { view in
            view is UIScrollView
                && String(describing: type(of: view))
                    .contains("HostingScrollView")
                && frameIn(window, view).width > 400
        }.first as? UIScrollView
        if let scroll {
            lines.append(
                "chatScroll=\(fmt(frameIn(window, scroll)))"
                    + " adjTop=\(Int(scroll.adjustedContentInset.top))"
                    + " adjBottom=\(Int(scroll.adjustedContentInset.bottom))"
                    + " offY=\(Int(scroll.contentOffset.y))"
                    + " contentH=\(Int(scroll.contentSize.height))"
            )
        } else {
            lines.append("chatScroll=缺席")
        }

        // 命中实测：左缘热区中点＋坞上方应属输入舱处
        let edgeHit = window.hitTest(
            CGPoint(x: 12, y: window.bounds.height / 2),
            with: nil
        )
        lines.append(
            "hitEdge=\(typeName(edgeHit))"
        )
        if let platter {
            let pf = frameIn(window, platter)
            let probePoint = CGPoint(
                x: window.bounds.width / 2, y: pf.minY - 30
            )
            let hit = window.hitTest(probePoint, with: nil)
            lines.append(
                "hitAboveDock@\(Int(probePoint.y))=\(typeName(hit))"
            )
        }

        store(tag: tag, body: lines.joined(separator: "\n"))
    }

    // MARK: - 工具

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first
    }

    private static func store(tag: String, body: String) {
        var all = captures
        all.append(body)
        if all.count > cap {
            all.removeFirst(all.count - cap)
        }
        UserDefaults.standard.set(all, forKey: key)
        ChatDiagTrace.record("bars-geo \(tag) 已采样")
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private static func frameIn(
        _ window: UIWindow, _ view: UIView
    ) -> CGRect {
        view.convert(view.bounds, to: window)
    }

    private static func fmt(_ r: CGRect) -> String {
        String(
            format: "(%.0f,%.0f %.0fx%.0f)",
            r.minX, r.minY, r.width, r.height
        )
    }

    private static func insets(_ i: UIEdgeInsets) -> String {
        "(\(Int(i.top)),\(Int(i.left)),\(Int(i.bottom)),\(Int(i.right)))"
    }

    private static func typeName(_ view: UIView?) -> String {
        guard let view else { return "nil" }
        return String(describing: type(of: view))
    }

    private static func findViews(
        _ root: UIView, where matches: (UIView) -> Bool
    ) -> [UIView] {
        var out: [UIView] = []
        if matches(root) { out.append(root) }
        for sub in root.subviews {
            out += findViews(sub, where: matches)
        }
        return out
    }
}

/// 自述读出面（设置·支持组入口，诊断构建专用）：
/// 全文可选可分享，用户真机跑完把文本发回即完成量测
struct BarsGeometryReportView: View {
    @State private var report: String = ""

    var body: some View {
        ScrollView {
            Text(report)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("栏位几何自述")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: report) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新") {
                    report = BarsGeometryTrace.report
                }
            }
        }
        .onAppear { report = BarsGeometryTrace.report }
    }
}
