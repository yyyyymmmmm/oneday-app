import OneDayCore
import SwiftUI
import UIKit

/// 枢纽页左边缘右滑返回桥（0.36.22 立、0.36.24 改
/// 判）：整页呈现（fullScreenCover）没有导航栈 pop
/// 手势，用系统边缘识别器 UIScreenEdgePanGesture-
/// Recognizer 补齐——零尺寸探针（不参与命中）把识
/// 别器装到枢纽根容器的父视图，判据只认 OneDay-
/// Core.HubEdgeSwipe 单源、桥侧不另写比值。
///
/// 0.36.24 改判（错题本 P-15 同病复发后的裁决，
/// 调研报告 swipe-reply-arbitration-research-
/// 20261111）：首版在 gestureRecognizerShouldBegin
/// 里读**速度**判方向——begin 被咨询的时刻速度与
/// 位移一样未累积、判据恒假死（与右滑引用 0.36.21
/// 速度门同病），真机「右滑不会退出」。本轮三改：
///
/// 1. 生死关不放任何方向/量级判据：shouldBegin 只
///    余段位启用门（浏览器段禁用），识别器只从左
///    缘起手即放行；
/// 2. 方向改在 handler 里按 translation 仲裁（Core
///    HubEdgeSwipe.arbitration）：横向右滑主导→跟
///    手（followedOffset/shouldDismiss 两数沿用）；
///    纵向/左向/斜向不明确→识别器自取消（state =
///    .cancelled）＋offset 从未写过、天然复位，触
///    摸让给枢纽内列表纵滚；
/// 3. 编排走调研候选 3（同时识别＋handler 仲裁）：
///    与滚动 pan 同时识别——纵向定案时滚动 pan 已
///    同步 begin、自取消无损让位；横向定案时闪断
///    正在追踪的滚动 pan（isEnabled 关开一次放掉
///    当前触摸），页面独占余下行程。不用 require
///    (toFail:)：被要求等待的滚动 pan 在本识别器
///    begin 的瞬间即被置 Failed，begin 后自取消救
///    不回同一触摸的纵滚（Event Handling Guide 语
///    义），左缘纵滑首触必死、与本桥验收口径冲突。
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
        /// 段位启用门（浏览器段为 false）：置位时同步
        /// 落到识别器本体——禁用段里识别器根本不追踪
        var isEnabled = true {
            didSet { recognizer?.isEnabled = isEnabled }
        }
        private weak var hostView: UIView?
        private var recognizer: UIScreenEdgePanGestureRecognizer?
        /// 本次触摸的方向定案：nil＝尚未定案（逐帧继
        /// 续判读）；定案后不再改判（跟手途中反向改判
        /// 会让页面与列表互相夺摸，口径同聊天右滑的
        /// 「定案不回头」）
        private var verdict: HubEdgeSwipe.Arbitration?

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
            pan.isEnabled = isEnabled
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
            verdict = nil
        }

        /// 生死关只余段位启用门（0.36.24）：不读速度、
        /// 不读位移、不判方向——begin 时刻任何量都未
        /// 累积，在此处判方向必恒假死（首版速度门与
        /// 右滑引用两轮量级门的共同死因，P-15）。方
        /// 向全部推迟到 handler 的逐帧仲裁
        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            isEnabled
        }

        /// 同时识别只对滚动 pan 开（调研候选 3）：枢
        /// 纽内列表的滚动 pan 与本识别器同步 begin，
        /// 方向在 handler 里仲裁——纵向定案本识别器
        /// 自取消、滚动无损接管；横向定案闪断滚动
        /// pan 独占行程。其余识别器（行内滑动操作/
        /// 长按等）保持默认互斥、不许同时
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith
                otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
                && otherGestureRecognizer.view is UIScrollView
        }

        @objc private func handlePan(
            _ pan: UIScreenEdgePanGestureRecognizer
        ) {
            guard let view = pan.view, let handlers else { return }
            let translation = pan.translation(in: view)
            switch pan.state {
            case .began:
                verdict = nil
                judge(pan, translation: translation)
                // 快起手时 began 当帧已可定案：同帧补发
                // 首帧位移，跟手不等下一帧
                if verdict == .follow {
                    handlers.onProgress(
                        HubEdgeSwipe.followedOffset(
                            translationX: translation.x
                        )
                    )
                }
            case .changed:
                if verdict == nil {
                    judge(pan, translation: translation)
                }
                if verdict == .follow {
                    handlers.onProgress(
                        HubEdgeSwipe.followedOffset(
                            translationX: translation.x
                        )
                    )
                }
            case .ended:
                let shouldDismiss = verdict == .follow
                    && HubEdgeSwipe.shouldDismiss(
                        translationX: translation.x,
                        velocityX: pan.velocity(in: view).x
                    )
                verdict = nil
                handlers.onRelease(shouldDismiss)
            case .cancelled, .failed:
                verdict = nil
                // 系统夺走或自取消让位：只复位、绝不误
                // 触返回
                handlers.onRelease(false)
            default:
                break
            }
        }

        /// 逐帧方向仲裁（begin 后、定案前每帧调用）：
        /// Core 判 follow→定案跟手并闪断正在追踪的滚
        /// 动 pan；判 yieldToScroll→定案让位并把识别
        /// 器置 .cancelled（随后 .cancelled 回调走复
        /// 位路）；undecided→不定案、下一帧再看
        private func judge(
            _ pan: UIScreenEdgePanGestureRecognizer,
            translation: CGPoint
        ) {
            switch HubEdgeSwipe.arbitration(
                translationX: translation.x,
                translationY: translation.y
            ) {
            case .undecided:
                break
            case .follow:
                verdict = .follow
                releaseTrackingScrollPans(from: pan)
            case .yieldToScroll:
                verdict = .yieldToScroll
                pan.state = .cancelled
            }
        }

        /// 横向定案时闪断正在追踪的滚动 pan：从识别器
        /// 宿主上行到本页根视图，遍历其下全部滚动视图，
        /// 对 pan 处于 .began/.changed 的逐个 isEnabled
        /// 关开一次——识别器放掉当前触摸并复位到
        /// .possible，本次横滑余下行程不再有滚动竞争；
        /// 下一次触摸照常可用（WWDC14-235 的关开让位
        /// 技巧，调研候选 3 引）。只在定案一刻执行一
        /// 次，不逐帧扫树
        private func releaseTrackingScrollPans(
            from pan: UIScreenEdgePanGestureRecognizer
        ) {
            guard let host = pan.view else { return }
            var root: UIView = host
            while let parent = root.superview { root = parent }
            releaseTrackingScrollPans(in: root)
        }

        private func releaseTrackingScrollPans(in view: UIView) {
            if let scrollView = view as? UIScrollView {
                let scrollPan = scrollView.panGestureRecognizer
                if scrollPan.state == .began
                    || scrollPan.state == .changed {
                    scrollPan.isEnabled = false
                    scrollPan.isEnabled = true
                }
            }
            for subview in view.subviews {
                releaseTrackingScrollPans(in: subview)
            }
        }
    }
}
