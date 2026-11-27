import OneDayCore
import SwiftUI
import UIKit

/// 全屏右滑返回桥（呈现与导航手势审计 2026-11-24
/// 问题二）：iOS 原生导航只有左边缘 pop，大厂通
/// 行形态是任意位置右拖即返回（微信/FD Fullscreen-
/// PopGesture 一系）。本桥一处收口全部导航栈：
/// - 机制照 FD 定式：全屏 UIPanGestureRecognizer
///   驱动系统交互式 pop 的同一内部目标（interactive-
///   PopGestureRecognizer 的 delegate＋handleNavi-
///   gationTransition:）——系统转场本体不换，只把
///   识别器作用域从左边缘扩到全屏；内部目标取不到
///   时整桥不装配、系统边缘 pop 原样保留（降级安
///   全，不许半装配后把边缘 pop 也弄丢）；
/// - 是否放行只问 Core FullscreenPopPolicy（栈深
///   >1、横向主导、无转场在飞、起点不在豁免区），
///   事实在判定时刻自 UIKit 层级采集，与抽屉场景
///   门（§323）的采集/判定分工同式；
/// - 装配入口只有两个：各 NavigationStack 根挂
///   .fullscreenPopBridge()（安装器视图自寻所属导
///   航控制器装配），安装器同时全窗巡检把层级内
///   其余导航控制器一并装配（模态自带栈等不在根
///   修饰位上的栈靠巡检收口）；逐页零手搓。

/// 每导航控制器一份的桥控制器：持有全屏 pan 与
/// 裁决 delegate，经 associated object 挂在导航
/// 控制器上随其生命周期（识别器的 delegate 是弱
/// 引用，靠这份关联保活）
final class FullscreenPopController: NSObject,
    UIGestureRecognizerDelegate
{
    private weak var navigationController: UINavigationController?
    private var panRecognizer: UIPanGestureRecognizer?

    private init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        super.init()
    }

    // MARK: - 装配（单点收口）

    private static var associationKey: UInt8 = 0

    /// 装配指定导航控制器（幂等：已装配只重申系
    /// 统边缘识别器关闭——SwiftUI 更新可能复位它）
    static func equip(_ nav: UINavigationController) {
        if let existing = objc_getAssociatedObject(
            nav, &associationKey
        ) as? FullscreenPopController {
            existing.reassert()
            return
        }
        let controller = FullscreenPopController(
            navigationController: nav
        )
        guard controller.install() else { return }
        objc_setAssociatedObject(
            nav, &associationKey, controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    /// 全窗巡检：自窗口根控制器遍历控制器树（含
    /// presented 链），层级内每个导航控制器都装配
    static func equipAll(in window: UIWindow) {
        guard let root = window.rootViewController else { return }
        equipRecursively(root)
    }

    private static func equipRecursively(
        _ controller: UIViewController
    ) {
        if let nav = controller as? UINavigationController {
            equip(nav)
        }
        controller.children.forEach(equipRecursively)
        if let presented = controller.presentedViewController {
            equipRecursively(presented)
        }
    }

    /// 自任意视图沿响应链找最近的导航控制器（抽
    /// 屉门 D 采集半同法：先看响应链上的控制器本
    /// 人、再看其 navigationController）
    static func nearestNavigationController(
        from view: UIView
    ) -> UINavigationController? {
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

    // MARK: - 安装/重申

    /// 内部目标（系统交互式 pop 的转场对象）取不
    /// 到或不响应转场 selector 时返回 false、整桥
    /// 不装配——系统边缘 pop 保持原样
    private func install() -> Bool {
        guard let nav = navigationController,
              let systemPop = nav.interactivePopGestureRecognizer,
              let target = systemPop.delegate,
              target.responds(
                  to: NSSelectorFromString(
                      "handleNavigationTransition:"
                  )
              )
        else { return false }
        let pan = UIPanGestureRecognizer(
            target: target,
            action: NSSelectorFromString(
                "handleNavigationTransition:"
            )
        )
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        nav.view.addGestureRecognizer(pan)
        panRecognizer = pan
        reassert()
        return true
    }

    /// 全屏 pan 已接管（含左边缘起滑），系统边缘
    /// 识别器关闭防双驱动同一转场
    private func reassert() {
        navigationController?
            .interactivePopGestureRecognizer?.isEnabled = false
    }

    // MARK: - 裁决（delegate）

    /// 判定时刻采集事实、裁决走 Core 单源谓词；
    /// 不声明同时识别与失败依赖——纵向主导时本
    /// 识别器自失败、列表滚动原样接管（与抽屉/
    /// 右滑回复桥的仲裁哲学一致）
    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let nav = navigationController,
              let pan = gestureRecognizer as? UIPanGestureRecognizer
        else { return false }
        let translationPoint = pan.translation(in: nav.view)
        let scene = FullscreenPopPolicy.Scene(
            stackDepth: nav.viewControllers.count,
            translation: CGSize(
                width: translationPoint.x,
                height: translationPoint.y
            ),
            isTransitioning: nav.transitionCoordinator != nil,
            startsInExemptRegion:
                FullscreenPopExemption.hierarchyContainsMarker(
                    in: nav.view,
                    at: pan.location(in: nav.view)
                )
        )
        return FullscreenPopPolicy.shouldBegin(scene)
    }
}

// MARK: - 豁免区（自有横向手势的面）

/// 豁免标记视图（与 SwipeReplyExcludedMarker 同
/// 式）：贴在自有横向手势的区域上（图像平移面
/// 等），桥在判定时刻自层级直算其帧、触点起点
/// 落入即让行；布局期零状态写入
final class FullscreenPopExemptMarkerView: UIView {}

struct FullscreenPopExemptMarker: UIViewRepresentable {
    func makeUIView(
        context: Context
    ) -> FullscreenPopExemptMarkerView {
        let view = FullscreenPopExemptMarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(
        _ uiView: FullscreenPopExemptMarkerView,
        context: Context
    ) {}
}

extension View {
    /// 本区域豁免全屏 pop（区域内右滑归区域自有
    /// 横向手势）；只许贴在真有横向业务的面上
    func fullscreenPopExempt() -> some View {
        background { FullscreenPopExemptMarker() }
    }
}

enum FullscreenPopExemption {
    /// 触点（root 坐标系）是否落在层级内任一豁
    /// 免标记的帧里
    @MainActor
    static func hierarchyContainsMarker(
        in root: UIView, at point: CGPoint
    ) -> Bool {
        var found = false
        func visit(_ view: UIView) {
            if found { return }
            if view is FullscreenPopExemptMarkerView,
               view.convert(view.bounds, to: root)
                   .contains(point) {
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

/// 安装器视图：入窗/更新时装配所属导航控制器，
/// 并全窗巡检收口其余栈（模态自带栈等）
final class FullscreenPopInstallerView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh()
    }

    func refresh() {
        guard let window else { return }
        if let nav = FullscreenPopController
            .nearestNavigationController(from: self) {
            FullscreenPopController.equip(nav)
        }
        FullscreenPopController.equipAll(in: window)
    }
}

struct FullscreenPopInstaller: UIViewRepresentable {
    func makeUIView(
        context: Context
    ) -> FullscreenPopInstallerView {
        let view = FullscreenPopInstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(
        _ uiView: FullscreenPopInstallerView,
        context: Context
    ) {
        uiView.refresh()
    }
}

struct FullscreenPopBridgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background { FullscreenPopInstaller() }
    }
}

extension View {
    /// 本导航栈接入全屏右滑返回（统一桥）：只许
    /// 挂在 NavigationStack 根上，逐页不许另搓
    func fullscreenPopBridge() -> some View {
        modifier(FullscreenPopBridgeModifier())
    }
}

// MARK: - 卡内深度采集（H1 让行事实）

/// 中枢卡片宿主的深度采集：自卡内锚点视图上溯
/// 到首个控制器根视图（呈现宿主层），再以抽屉
/// 门 D 同源的层级扫描取卡内最大导航深度——
/// path 绑定已于 0.36.27 真机证伪退役，本采集
/// 不复活任何绑定，只在手势起手一拍现采现判；
/// 采集不到按 1（根层）计、不误锁关卡
enum HubCardDepthProbe {
    static func maxNavigationDepth(fromAnchor anchor: UIView) -> Int {
        guard let root = hostingRootView(of: anchor) else {
            return 1
        }
        return DrawerContainerController
            .hierarchyMaxNavigationDepth(root)
    }

    /// 首个「控制器根视图」祖先：next 响应者是
    /// 控制器本人的那层视图即其根视图
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
