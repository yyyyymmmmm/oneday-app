import os
import UIKit

/// 右滑引用手势诊断打点（0.36.23 §90 **临时件，下一
/// 轮撤**）：P-15 三轮真机失败、形态①（识别器从未启
/// 动）有三个外观不可分辨的互斥假设——H1 仲裁抢先
/// （shouldBegin 从未被咨询）、H2 咨询值不可用、
/// H3 触摸未分发（装载点不在命中链上）。本轮按调研
/// 报告第三节随构建保留三处打点，一轮真机凭读数定
/// 案、定案后整件删除，不进任何正常 UI。
///
/// 落点（照听写诊断的既有双通道先例）：统一日志
/// （os.Logger，subsystem 同听写、category 换
/// swipeReply）＋UserDefaults 落盘环（最近 40 条，
/// 带时刻，杀进程不丢）。读数发回路径：真机复验后
/// 把落盘环内容经既有诊断通道回传（键 swipeReply.
/// diagTrace），或抓统一日志同 category 段。
// @unchecked Sendable 的依据（NetworkPathObserver
// 同款口径）：全部调用点都是主线程的 UIKit 手势回
// 调，实例无可变状态，落盘走 UserDefaults（线程安
// 全）；0.36.23 出包 CI 首轮实证缺此标注编不过
final class SwipeReplyDiagnostics: NSObject, @unchecked Sendable {
    static let shared = SwipeReplyDiagnostics()

    private static let log = Logger(
        subsystem: "site.didichou.oneday", category: "swipeReply")
    private static let traceKey = "swipeReply.diagTrace"
    private static let traceLimit = 40

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// 已挂只读 target 的 ScrollView 标记键（关联对象
    /// 随视图生死，不留悬挂引用）；键只作地址用、初
    /// 始化后从不写——Swift 6 下 static var 直报全局
    /// 可变状态、UnsafeRawPointer 常量又非 Sendable，
    /// 故以 nonisolated(unsafe) 明示豁免（本文件临时
    /// 件，下一轮随打点整件撤除）
    nonisolated(unsafe) private static var watchedKey: UInt8 = 0

    /// 打点 3 的装载：给宿主 ScrollView 自己的 pan
    /// 加一个只记录 .began 时刻的 target（寄生打点、
    /// 不改其任何行为），同一 ScrollView 只挂一次
    func watchScrollPan(_ scrollView: UIScrollView) {
        if objc_getAssociatedObject(scrollView, &Self.watchedKey) != nil {
            return
        }
        objc_setAssociatedObject(
            scrollView, &Self.watchedKey, true,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        scrollView.panGestureRecognizer.addTarget(
            self, action: #selector(handleWatchedScrollPan(_:)))
        record("watch scrollPan attached")
    }

    @objc private func handleWatchedScrollPan(
        _ pan: UIPanGestureRecognizer
    ) {
        // 只记 .began：与打点 1/2 同轴对时，判 H1 用
        guard pan.state == .began else { return }
        record("scrollPan began")
    }

    /// 打点 1：行 pan 的 shouldReceive——触发即证明触
    /// 摸分发到了装载点；附 recognizer.view 的完整
    /// superview 类名链，判 H3（装载点不在命中链上）
    /// 与装载层级实况都看这一条
    func recordShouldReceive(recognizer: UIGestureRecognizer) {
        var chain: [String] = []
        var node = recognizer.view
        while let current = node {
            chain.append(String(describing: type(of: current)))
            node = current.superview
        }
        record(
            "shouldReceive chain="
                + chain.joined(separator: "<-"))
    }

    /// 打点 2：行 pan 的 shouldBegin 进入即记，附当刻
    /// translation 实测值与 Core 判决——从未出现即
    /// H1、出现且判 false 即查判据（H2 的位移版形态）
    func recordShouldBegin(translation: CGPoint, verdict: Bool) {
        record(
            "shouldBegin dx=\(Self.fmt(translation.x)) "
                + "dy=\(Self.fmt(translation.y)) "
                + "verdict=\(verdict ? "begin" : "fail")")
    }

    /// 一行打点：日志与落盘环同写（主线程投递，UIK-
    /// it 手势回调恒在主线程，本件不另设队列）
    private func record(_ event: String) {
        let line = "\(Self.clock.string(from: Date())) \(event)"
        Self.log.info("\(line, privacy: .public)")
        let defaults = UserDefaults.standard
        var trace = defaults.stringArray(forKey: Self.traceKey) ?? []
        trace.append(line)
        if trace.count > Self.traceLimit {
            trace.removeFirst(trace.count - Self.traceLimit)
        }
        defaults.set(trace, forKey: Self.traceKey)
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
