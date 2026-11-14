import Foundation
import OneDayCore
import UIKit

/// §245（2026-11-14）后台量测池（换代包 2）
///
/// 蓝图 §1.3：量测用 TextKit 在后台量测实例池（每
/// 并发一台、实例不跨线程共享），替代「单台全进程
/// 共享量测视图在布局期主线程串行量测」成为将来
/// 的行高来源——本包只建池与影子对拍（见 Layout-
/// ShadowLedger），现量测视图仍是行高来源、呈现
/// 零改动。
///
/// 线程纪律（外部核查，报告 §一）：TextKit 对象非
/// 线程安全，成熟做法（Texture 的 ASTextKitRenderer
/// 族）从来不是「加锁共用一台」，而是每条后台线一
/// 套独立文本栈、栈不跨线。本池按此：一名 worker
/// ＝一条串行队列＋一套 (NSTextContentStorage＋
/// NSTextLayoutManager＋NSTextContainer)，栈只在
/// 自己的队列上被碰。量测栈与承载/量测视图同为
/// TextKit 2（§168 承载显式 TK2），同引擎是对拍
/// 一致的前提。
///
/// 高度口径：容器宽＝提议宽、行片段内边距 0（与
/// 量测视图同参），高＝usageBoundsForTextContainer
/// .height（UITextView.sizeThatFits 的内部同源值，
/// 容器内边距在量测视图侧为零）
final class LayoutMeasurePool: @unchecked Sendable {
    static let shared = LayoutMeasurePool()

    private final class Worker {
        let queue: DispatchQueue
        private var storage: NSTextContentStorage?
        private var layoutManager: NSTextLayoutManager?
        private var container: NSTextContainer?

        init(index: Int) {
            queue = DispatchQueue(
                label: "site.didichou.oneday.layoutmeasure.\(index)",
                qos: .userInitiated
            )
        }

        /// 只在自己的 queue 上调用：栈懒建、复用；
        /// 每次量测整体换串（产物按条目短命，栈长
        /// 命——与 Texture renderer 的栈复用同形）
        func measure(
            _ attributed: NSAttributedString, width: CGFloat
        ) -> CGFloat {
            if storage == nil {
                let storage = NSTextContentStorage()
                let layoutManager = NSTextLayoutManager()
                let container = NSTextContainer()
                container.lineFragmentPadding = 0
                layoutManager.textContainer = container
                storage.addTextLayoutManager(layoutManager)
                self.storage = storage
                self.layoutManager = layoutManager
                self.container = container
            }
            guard let storage, let layoutManager, let container
            else { return 0 }
            container.size = CGSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )
            storage.attributedString = attributed
            layoutManager.ensureLayout(for: storage.documentRange)
            return layoutManager.usageBoundsForTextContainer.height
        }
    }

    private let workers: [Worker]
    private let routingLock = NSLock()
    private var routingCounter = 0

    /// 路由取 worker（同步函数内持锁——锁不跨挂起
    /// 点，async 上下文不直接碰 NSLock 的 Swift 6
    /// 口径）
    private func nextWorker() -> Worker {
        routingLock.lock()
        defer { routingLock.unlock() }
        routingCounter += 1
        return workers[routingCounter % workers.count]
    }

    init(workerCount: Int = 3) {
        workers = (0..<max(1, workerCount)).map { Worker(index: $0) }
    }

    /// 后台量测一段属性串在给定宽下的高。调用方线
    /// 程不限（主线程调用也只投递不等结果——提交
    /// 即返回，完成在 worker 队列）
    func measure(
        _ attributed: NSAttributedString, width: CGFloat
    ) async -> CGFloat {
        guard width > 0, attributed.length > 0 else {
            // 空串口径：现行量测视图对空文回一行的高
            // （字体行高），池无字体上下文不造数——
            // 返 0 并由影子账记为豁免（报告 §四）；
            // 非空但宽非法同理
            return 0
        }
        let worker = nextWorker()
        return await withCheckedContinuation { continuation in
            worker.queue.async {
                continuation.resume(
                    returning: worker.measure(
                        attributed, width: width
                    )
                )
            }
        }
    }
}
