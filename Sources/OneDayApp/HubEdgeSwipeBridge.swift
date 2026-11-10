import OneDayCore
import SwiftUI
import UIKit

/// 枢纽页左边缘右滑返回桥（0.36.22）：整页呈现
/// （fullScreenCover）没有导航栈 pop 手势，用系统
/// 边缘识别器 UIScreenEdgePanGestureRecognizer 补
/// 齐——形态与右滑引用桥（SwipeReplyGestureBridge）
/// 同族：零尺寸探针（不参与命中）把识别器装到枢纽
/// 根容器的父视图，判据只认 OneDayCore.HubEdgeSwipe
/// 单源、桥侧不另写比值。
///
/// 生死口径（错题本 P-15 续修的直接应用）：should-
/// Begin 只读**速度**判方向——begin 时刻平移≈0、读
/// 位移恒假死（0.36.20 第一版桥的死因）；纵向主导
/// 的速度在此被拒、识别器对本次触摸直接死亡，枢纽
/// 内列表的纵滚完整不受扰。横向 begin 后位移才经
/// 跟手回调写呈现层 offset，纵滚那时已由识别器互
/// 斥仲裁让位（不设同时识别）。
struct HubEdgeSwipeProbe: UIViewRepresentable {
    /// 浏览器段禁用（网页自有横移/缩放手势，边缘返
    /// 回不与它抢；由呈现层按当前段置位）
    var isEnabled: Bool
    /// 跟手中的横向位移（已由 Core 钳制）
    var onProgress: (CGFloat) -> Void
    /// 松手/被夺走：true＝裁决返回（关闭枢纽），
    /// false＝回弹复位
    var onRelease: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.handlers = Handlers(
            onProgress: onProgress, onRelease: onRelease
        )
        context.coordinator.isEnabled = isEnabled
        context.coordinator.attachIfNeeded(from: uiView)
    }

    static func dismantleUIView(
        _ uiView: ProbeView, coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    /// 探针视图：自身零命中，进层级时请协调器就近挂载
    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            coordinator?.attachIfNeeded(from: self)
        }
    }

    struct Handlers {
        var onProgress: (CGFloat) -> Void
        var onRelease: (Bool) -> Void
    }

    /// 协调器：识别器的持有者与代理。NSObject 非隔离
    /// 域——UIKit 在主线程投递识别器回调，本类不继承
    /// 任何 actor 隔离，回调里只转手呈现层闭包（回调
    /// 隔离铁律同精神）
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var handlers: Handlers?
        var isEnabled = true
        private weak var hostView: UIView?
        private var recognizer: UIScreenEdgePanGestureRecognizer?

        func attachIfNeeded(from probe: UIView) {
            guard let host = probe.superview else { return }
            if hostView === host, recognizer != nil { return }
            detach()
            let pan = UIScreenEdgePanGestureRecognizer(
                target: self,
                action: #selector(handlePan(_:))
            )
            pan.edges = .left
            pan.delegate = self
            host.addGestureRecognizer(pan)
            hostView = host
            recognizer = pan
        }

        func detach() {
            if let recognizer, let hostView {
                hostView.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            hostView = nil
        }

        /// 方向生死：只认速度域（Core 单源）——右向且
        /// 横向主导才 begin；纵向主导在此被拒、纵滚
        /// 归列表。禁用段（浏览器）恒拒
        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard isEnabled,
                  let pan = gestureRecognizer
                    as? UIScreenEdgePanGestureRecognizer,
                  let view = pan.view
            else { return false }
            let velocity = pan.velocity(in: view)
            return HubEdgeSwipe.shouldBegin(
                velocityX: velocity.x, velocityY: velocity.y
            )
        }

        @objc private func handlePan(
            _ pan: UIScreenEdgePanGestureRecognizer
        ) {
            guard let view = pan.view, let handlers else { return }
            let translation = pan.translation(in: view)
            switch pan.state {
            case .began, .changed:
                handlers.onProgress(
                    HubEdgeSwipe.followedOffset(
                        translationX: translation.x
                    )
                )
            case .ended:
                let velocity = pan.velocity(in: view)
                handlers.onRelease(
                    HubEdgeSwipe.shouldDismiss(
                        translationX: translation.x,
                        velocityX: velocity.x
                    )
                )
            case .cancelled, .failed:
                // 系统夺走只复位、绝不误触返回
                handlers.onRelease(false)
            default:
                break
            }
        }
    }
}
