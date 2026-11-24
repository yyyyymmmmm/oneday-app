import SwiftUI
import UIKit

/// 聊天行高量测的线程分发原语（§331，0.50.70
/// 热修题 3 根治）：主线程走现行量测视图（§168
/// 共享台——同步路径与既有全部口径逐值不变）；
/// 后台线程走 §251 后台量测池的每线 TextKit 2
/// 栈（与量测视图同引擎、影子对拍自 2026-11-14
/// 在产验证）。合成器核心据此成为线程无关的纯
/// 量测，可在量测台队列整行执行——主线程自此
/// 只在同步兜底路径上量测（直播行等少数行），
/// 历史行全量走后台预排版
enum ChatNativeTextMeasure {
    /// 给定宽下的高。emptyLineHeight＝空串兜底
    /// 口径：量测视图对空串回自家字体实高（R10
    /// 实测 22.0、与被量串的意图字体无关），后
    /// 台以主线程探针实值回同值（见 emptyProbe
    /// 注）、未探得才回本兜底，两路同值
    static func height(
        attributed: NSAttributedString, width: CGFloat,
        emptyLineHeight: CGFloat
    ) -> CGFloat {
        if Thread.isMainThread {
            // 量测视图口是 @MainActor 隔离的；本
            // 支以 Thread.isMainThread 钉死主线
            // 程、assumeIsolated 桥接隔离（前提
            // 由线程检查构造保证）
            // 装箱后闭包只捕获 Sendable 箱（与
            // §251 影子账过 detached 边界同式）：
            // 裸 attributed 是 task 隔离值、直捕
            // 进 @MainActor 闭包即发送错误
            let boxed = LayoutAttributedBox(attributed)
            let value = MainActor.assumeIsolated {
                SelectableTextRepresentable
                    .referenceHeight(
                        attributed: boxed.value,
                        width: width
                    )
            }
            if attributed.length == 0 {
                emptyProbe.storeHeight(value)
            }
            return value
        }
        guard attributed.length > 0 else {
            // 空串口径（R10 实测修正）：空串无属
            // 性、量测视图以自家字体回高（实测
            // 22.0、并非调用方字体行高 20.29）——
            // 后台回主线程探针实值、与同步路径逐
            // 值同；未探得才回字体行高兜底
            return emptyProbe.storedHeight()
                ?? emptyLineHeight
        }
        return LayoutMeasurePool.shared
            .measureSizeSynchronously(
                attributed, width: width
            ).height
    }

    /// 空串实值探针：量测视图对空串的高/宽只由
    /// 它自家字体决定（与被量串的意图字体无关、
    /// 随环境变）——主线程量到即记、后台只读，
    /// 两路空串恒同值（NSLock 锁盒、@unchecked
    /// 依据＝读写全在锁内）
    private static let emptyProbe = EmptyProbe()

    private final class EmptyProbe:
        @unchecked Sendable {
        private let lock = NSLock()
        private var height: CGFloat?
        private var width: CGFloat?

        func storeHeight(_ value: CGFloat) {
            lock.lock()
            height = value
            lock.unlock()
        }

        func storeWidth(_ value: CGFloat) {
            lock.lock()
            width = value
            lock.unlock()
        }

        func storedHeight() -> CGFloat? {
            lock.lock()
            defer { lock.unlock() }
            return height
        }

        func storedWidth() -> CGFloat? {
            lock.lock()
            defer { lock.unlock() }
            return width
        }
    }

    /// 自然单行宽（表格列宽/时间列宽用）：与量测
    /// 视图同口径——无提议宽时按 10_000 宽量一
    /// 行、取其宽
    static func naturalWidth(
        attributed: NSAttributedString
    ) -> CGFloat {
        if Thread.isMainThread {
            let boxed = LayoutAttributedBox(attributed)
            let size = MainActor.assumeIsolated {
                SelectableTextRepresentable
                    .measuredSize(
                        attributed: boxed.value,
                        proposal: ProposedViewSize(
                            width: nil, height: nil
                        )
                    )
            }
            if attributed.length == 0 {
                emptyProbe.storeWidth(size.width)
            }
            return size.width
        }
        guard attributed.length > 0 else {
            return emptyProbe.storedWidth() ?? 0
        }
        return LayoutMeasurePool.shared
            .measureSizeSynchronously(
                attributed, width: 10_000
            ).width
    }
}
