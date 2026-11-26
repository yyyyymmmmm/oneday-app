import OneDayCore
import SwiftUI
import UIKit

/// 全屏右滑返回桥（Phase 2.2 标准化）：
/// 使用 iOS 26 官方原生 `UINavigationController.interactiveContentPopGestureRecognizer`
/// 替代早期的私有 selector (`handleNavigationTransition:`) 反射挂钩，
/// 彻底消除私有 API 审核风险，同时保留豁免区（`.fullscreenPopExempt()`）与
/// 中枢卡深度探测（`HubCardDepthProbe`）行为不变。
@MainActor
final class FullscreenPopController: NSObject, UIGestureRecognizerDelegate {
    private weak var navigationController: UINavigationController?
    private weak var previousDelegate: (any UIGestureRecognizerDelegate)?

    private init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        super.init()
    }

    private static var associationKey: UInt8 = 0

    static func equip(_ nav: UINavigationController) {
        if let existing = objc_getAssociatedObject(
            nav, &associationKey
        ) as? FullscreenPopController {
            existing.reassert()
            return
        }
        let controller = FullscreenPopController(navigationController: nav)
        controller.install()
        objc_setAssociatedObject(
            nav, &associationKey, controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func equipAll(in window: UIWindow) {
        guard let root = window.rootViewController else { return }
        equipRecursively(root)
    }

    private static func equipRecursively(_ controller: UIViewController) {
        if let nav = controller as? UINavigationController {
            equip(nav)
        }
        controller.children.forEach(equipRecursively)
        if let presented = controller.presentedViewController {
            equipRecursively(presented)
        }
    }

    static func nearestNavigationController(from view: UIView) -> UINavigationController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let nav = current as? UINavigationController {
                return nav
            }
            if let controller = current as? UIViewController,
               let nav = controller.navigationController {
                return nav
            }
            responder = current.next
        }
        return nil
    }

    private func install() {
        guard let nav = navigationController else { return }
        nav.interactiveContentPopGestureRecognizer?.isEnabled = true
        if let contentPop = nav.interactiveContentPopGestureRecognizer,
           contentPop.delegate !== self {
            previousDelegate = contentPop.delegate
            contentPop.delegate = self
        }
    }

    private func reassert() {
        navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController else { return false }
        if FullscreenPopExemption.hierarchyContainsMarker(
            in: nav.view,
            at: gestureRecognizer.location(in: nav.view)
        ) {
            return false
        }
        if let previousDelegate,
           previousDelegate.responds(to: #selector(UIGestureRecognizerDelegate.gestureRecognizerShouldBegin(_:))) {
            return previousDelegate.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
        }
        return nav.viewControllers.count > 1 && nav.transitionCoordinator == nil
    }
}

// MARK: - 豁免区（自有横向手势的面）

final class FullscreenPopExemptMarkerView: UIView {}

struct FullscreenPopExemptMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> FullscreenPopExemptMarkerView {
        let view = FullscreenPopExemptMarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: FullscreenPopExemptMarkerView, context: Context) {}
}

extension View {
    func fullscreenPopExempt() -> some View {
        background { FullscreenPopExemptMarker() }
    }
}

enum FullscreenPopExemption {
    @MainActor
    static func hierarchyContainsMarker(in root: UIView, at point: CGPoint) -> Bool {
        var found = false
        func visit(_ view: UIView) {
            if found { return }
            if view is FullscreenPopExemptMarkerView,
               view.convert(view.bounds, to: root).contains(point) {
                found = true
                return
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return found
    }
}

// MARK: - 安装器（栈根修饰位）

final class FullscreenPopInstallerView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh()
    }

    func refresh() {
        guard let window else { return }
        if let nav = FullscreenPopController.nearestNavigationController(from: self) {
            FullscreenPopController.equip(nav)
        }
        FullscreenPopController.equipAll(in: window)
    }
}

struct FullscreenPopInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> FullscreenPopInstallerView {
        let view = FullscreenPopInstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: FullscreenPopInstallerView, context: Context) {
        uiView.refresh()
    }
}

struct FullscreenPopBridgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background { FullscreenPopInstaller() }
    }
}

extension View {
    func fullscreenPopBridge() -> some View {
        modifier(FullscreenPopBridgeModifier())
    }
}

// MARK: - 卡内深度采集（H1 让行事实）

enum HubCardDepthProbe {
    @MainActor
    static func maxNavigationDepth(fromAnchor anchor: UIView) -> Int {
        guard let root = hostingRootView(of: anchor) else {
            return 1
        }
        return DrawerContainerController.hierarchyMaxNavigationDepth(root)
    }

    @MainActor
    static func hostingRootView(of view: UIView) -> UIView? {
        var current: UIView? = view
        while let candidate = current {
            if candidate.next is UIViewController {
                return candidate
            }
            current = candidate.superview
        }
        return nil
    }
}
