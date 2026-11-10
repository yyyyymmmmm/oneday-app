import OneDayCore
import SwiftUI
import UIKit

/// 右滑引用手势桥（0.36.20 §85 立桥；0.36.21 §88 曾
/// 改速度域判据；0.36.23 §90 改装载编排＋回归位移
/// 纯比值）：把右滑引用的接管层从 SwiftUI DragGes-
/// ture 换成 UIKit 平移识别器，生死在 `gestureRec-
/// ognizerShouldBegin` 阶段按 Core `SwipeReplyMo-
/// tion.shouldBeginPan`（位移纯比值、无量级门）决
/// 定，滚动与行 pan 的求值顺序由失败要求明文编排
/// （见 Coordinator.orchestrateIfNeeded）。
///
/// 为什么必须下到 UIKit（外部核查对账见 DESIGN
/// §85）：DragGesture 在识别层无法自我失败——mini-
/// mumDistance 一到识别即成立，纵滚意图在 onChanged
/// 判读前已被手势系统卷入；方向门写在 onChanged 里
/// 只挡位移写入、挡不住识别抢占。
///
/// 0.36.23 改法（§90 调研裁决，报告 swipe-reply-
/// arbitration-research-20261111）：三轮真机死状
/// （识别器从未启动）随判据量纲更换而不变，定案死
/// 因不在 translation/velocity 之争、在**零编排**：
/// 苹果官方口径——识别器之间默认没有求值顺序保
/// 证、默认互斥，定序必须显式声明；前两轮与 Scr-
/// ollView 的 pan 裸拼仲裁，输赢不受任何保证。本
/// 轮补上编排：宿主 ScrollView 的 pan 对行 pan 做
/// require(toFail:)——纵滚必须等行 pan 先判：行
/// pan 判横向则滚动被置 Failed、行跟手；判纵向则
/// 行 pan 当场 Failed、滚动无感接管。判据同时回归
/// 位移纯比值（SwipeCellKit 现行 master 同型；
/// 0.36.21 的速度域立论经逐行核查不成立，退役理
/// 由见 Core shouldBeginPan 注）。
///
/// 挂载形态沿用：零尺寸探针视图（不参与命中测试）
/// 把识别器装到本行修饰符容器的宿主视图上——每行
/// 一个、位于该行自己的视图层级；不用覆盖全行的
/// overlay 视图，避免吞掉内容子视图的触摸（长按
/// 菜单/点图/点链接各有自己的识别器，不受影响）。
///
/// 诊断打点（临时，下一轮撤）：shouldReceive＋视
/// 图链、shouldBegin＋实测值、宿主 scroll pan 的
/// .began 时刻三处，全在 SwipeReplyDiagnostics，
/// 为 P-15 补定案证据（H1/H2/H3 判读表见 §90）。
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

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // 层级完整后再请一次：编排要向上找到
            // ScrollView，挂载当刻链可能还没接全
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
        /// 已编排到的宿主 ScrollView（每行一对一绑定，
        /// 行回收换宿主时随 detach 清零重绑）
        private weak var orchestratedScrollView: UIScrollView?

        /// 把识别器装到探针的父视图（本行修饰符容器的
        /// 宿主视图）上；已装在同一父视图则不动（只补
        /// 编排），换父（行回收复用）时先卸旧再装新
        func attachIfNeeded(from probe: UIView) {
            guard let host = probe.superview else { return }
            if hostView === host, recognizer != nil {
                orchestrateIfNeeded()
                return
            }
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
            orchestrateIfNeeded()
        }

        /// 编排（本轮核心新增）：从行宿主向上找到包围
        /// 本行的 UIScrollView，令其 panGestureRecog-
        /// nizer 对行 pan 做 require(toFail:)——滚动
        /// pan 停在 .possible 等行 pan 判决：行 pan
        /// Failed 它才开始分析、行 pan Began 它直接
        /// Failed（苹果 Event Handling Guide 的失败要
        /// 求语义原文，§90 引）。装载当刻链未接全（找
        /// 不到 ScrollView）时不强求，随后的 update/
        /// didMoveToWindow 会再请本函数补齐。行 pan 被
        /// detach 移除后，其失败要求随识别器消亡由系
        /// 统按已失败处理，不留悬挂等待。
        private func orchestrateIfNeeded() {
            guard let pan = recognizer, let host = hostView,
                  orchestratedScrollView == nil else { return }
            var node: UIView? = host.superview
            while let current = node {
                if let scrollView = current as? UIScrollView {
                    scrollView.panGestureRecognizer
                        .require(toFail: pan)
                    orchestratedScrollView = scrollView
                    SwipeReplyDiagnostics.shared
                        .watchScrollPan(scrollView)
                    return
                }
                node = current.superview
            }
        }

        func detach() {
            if let recognizer, let hostView {
                hostView.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            hostView = nil
            orchestratedScrollView = nil
        }

        /// 触摸分发打点（临时诊断，下一轮撤）：恒 true
        /// 不改分发行为，只记「触摸到了装载点」＋视图
        /// 链实况（SwipeReplyDiagnostics 打点 1）
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            SwipeReplyDiagnostics.shared.recordShouldReceive(
                recognizer: gestureRecognizer)
            return true
        }

        /// 方向生死：纵向主导在此被拒——识别器当场
        /// Failed，失败要求随即放行 ScrollView 的平
        /// 移识别器完整接管纵滚；横向主导才许 begin，
        /// 滚动 pan 按失败要求语义已被置 Failed。判
        /// 据只认 Core 单源（SwipeReplyMotion.should-
        /// BeginPan），本处不许另写比值。**读位移纯
        /// 比值**（§90）：shouldBegin 是一次性闸门、
        /// 咨询时位移只有数 pt，纯比值与量级无关才定
        /// 得了案；0.36.20 的量级门与 0.36.21 的速度
        /// 域都已真机证伪（退役理由见 Core 注）
        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return false }
            let translation = pan.translation(in: view)
            let verdict = SwipeReplyMotion.shouldBeginPan(
                dx: translation.x, dy: translation.y
            )
            // 临时诊断打点（下一轮撤）：进入即记＋实测
            // 值＋判决，P-15 判读用
            SwipeReplyDiagnostics.shared.recordShouldBegin(
                translation: translation, verdict: verdict)
            return verdict
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
