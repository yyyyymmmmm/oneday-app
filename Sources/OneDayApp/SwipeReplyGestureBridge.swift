import OneDayCore
import SwiftUI
import UIKit

/// 右滑引用手势桥（0.36.20，§85，P-15 终修）：把右滑
/// 引用的接管层从 SwiftUI DragGesture 换成 UIKit 平移
/// 识别器——生死在 `gestureRecognizerShouldBegin` 阶
/// 段按 Core `SwipeReplyMotion.shouldBeginPan` 同一判
/// 据决定：横向主导才 begin，纵向主导直接不 begin、
/// 纵滚完整让给 ScrollView。
///
/// 为什么必须下到 UIKit（外部核查对账见 DESIGN §85）：
/// DragGesture 在识别层无法自我失败——minimumDistance
/// 一到识别即成立，纵滚意图在 onChanged 判读前已被手
/// 势系统卷入；方向门写在 onChanged 里只挡位移写入、
/// 挡不住识别抢占（真实项目 Revela 的实测报告与本次
/// 真机回归逐字同型）。UIKit 的 shouldBegin 是通行解
/// （SwipeCellKit 等生产级滑动单元格库同模式）。
///
/// 挂载形态：零尺寸探针视图（不参与命中测试）把识别
/// 器装到修饰符容器的父视图上——识别器由此成为消息
/// 内容的祖先级识别器，能收到整行触摸；不使用覆盖全
/// 行的 overlay 视图，避免吞掉内容子视图的触摸（长
/// 按菜单/点图/点链接各有自己的识别器，不受影响）。
/// 与滚动识别器不设同时识别（默认排斥仲裁）：本识别
/// 器被 shouldBegin 拒即对本次触摸死亡、滚动接管；
/// 横向 begin 后滚动平移不得同行。
struct SwipeReplyPanProbe: UIViewRepresentable {
    /// begin 瞬间的全量横向位移（锁定段，呈现层扣除）
    var onBegan: (CGFloat) -> Void
    /// 跟手中的全量横向位移
    var onChanged: (CGFloat) -> Void
    /// 松手（呈现层按阈值判触发）
    var onEnded: () -> Void
    /// 被系统夺走（来电/系统手势等）：只复位不触发
    var onCancelled: () -> Void

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
            onBegan: onBegan, onChanged: onChanged,
            onEnded: onEnded, onCancelled: onCancelled
        )
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
        var onBegan: (CGFloat) -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded: () -> Void
        var onCancelled: () -> Void
    }

    /// 协调器：识别器的持有者与代理。NSObject 非隔离
    /// 域——UIKit 在主线程投递识别器回调，本类不继承
    /// 任何 actor 隔离，回调里只转手呈现层闭包（与回
    /// 调隔离铁律同精神：系统回调闭包不许继承隔离）
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var handlers: Handlers?
        private weak var hostView: UIView?
        private var recognizer: UIPanGestureRecognizer?

        /// 把识别器装到探针的父视图（修饰符容器）上；
        /// 已装在同一父视图则不动，换父（行回收复用）
        /// 时先卸旧再装新
        func attachIfNeeded(from probe: UIView) {
            guard let host = probe.superview else { return }
            if hostView === host, recognizer != nil { return }
            detach()
            let pan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handlePan(_:))
            )
            pan.delegate = self
            // 一次只认一只手指：多指触摸不属于滑动引用
            pan.maximumNumberOfTouches = 1
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

        /// 方向生死：纵向主导在此被拒——识别器对本次
        /// 触摸直接死亡，ScrollView 的平移识别器完整
        /// 接管纵滚；横向主导才许 begin。判据只认 Core
        /// 单源（SwipeReplyMotion.shouldBeginPan），本
        /// 处不许另写比值
        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return false }
            let translation = pan.translation(in: view)
            return SwipeReplyMotion.shouldBeginPan(
                dx: translation.x, dy: translation.y
            )
        }

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view, let handlers else { return }
            let dx = pan.translation(in: view).x
            switch pan.state {
            case .began:
                handlers.onBegan(dx)
            case .changed:
                handlers.onChanged(dx)
            case .ended:
                handlers.onEnded()
            case .cancelled, .failed:
                // 系统夺走的手势只复位、绝不触发引用
                handlers.onCancelled()
            default:
                break
            }
        }
    }
}
