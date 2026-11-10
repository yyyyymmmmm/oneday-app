import Foundation

/// 枢纽页左边缘右滑返回的仲裁（0.36.22 立、0.36.24
/// 改判）：整页呈现（fullScreenCover）没有导航栈的
/// 系统 pop 手势，用 UIScreenEdgePanGestureRecog-
/// nizer（系统边缘识别器本体）补齐，判据全收本处、
/// 单测把守：
///
/// - 生死（shouldBegin）**不放任何方向/量级判据**
///   （0.36.24 定案）：首版在此读速度域判方向，与右
///   滑引用 0.36.21 的速度门同病——生死关被咨询的时
///   刻量未累积、判据恒假死，真机「右滑不会退出」
///   （错题本 P-15 同病复发）。生死关只余段位启用门
///   （浏览器段禁用），方向一律推迟到 begin 之后的
///   handler 里按 translation 判。
/// - 方向仲裁（handler 内、begin 后）：横向右滑主
///   导才跟手；其余（纵向/左向/斜向不明确）判让位，
///   识别器自取消、把触摸还给枢纽内列表纵滚。退出
///   的代价高于滚动，含糊一律判给滚动。
/// - 编排走调研候选 3（同时识别＋handler 仲裁），
///   不用 require(toFail:)：按 Event Handling Guide
///   语义，被要求等待的滚动 pan 在边缘识别器 begin
///   的瞬间即被置 Failed，begin 后自取消救不回同一
///   触摸的纵滚——左缘纵滑首触必死、与复验口径冲
///   突。同时识别下滚动 pan 已同步 begin：纵向定案
///   自取消边缘识别器即无损让位；横向定案再闪断正
///   在追踪的滚动 pan（isEnabled 关开一次、放掉当
///   前触摸），页面跟手独占余下行程。
/// - 跟手位移只进不出：负位移钳 0（左拖不跟）、上
///   限封顶（整页横移不跑飞）。
/// - 松手裁决只认位移与速度两数（松手时刻两量已
///   充分累积，与生死关的未累积量不是一回事）：位
///   移过线直接返回；位移半线＋快甩也返回（与消息
///   列表右滑引用「只认位移不认速度」的口径不同
///   ——那边是内容手势、误触代价是错引用；这边是
///   页面返回、快甩是用户明确的返回意图，两处口
///   径各自成文不混）。
public enum HubEdgeSwipe {
    /// 跟手位移封顶（pt）
    public static let maxFollowOffset: CGFloat = 480
    /// 松手位移直达线（pt）
    public static let dismissTranslation: CGFloat = 90
    /// 快甩辅助线：位移（pt）与速度（pt/s）
    public static let flickTranslation: CGFloat = 40
    public static let flickVelocity: CGFloat = 500
    /// 方向仲裁的决定下限（pt）：主导轴位移未过此数
    /// 时方向读数还是噪声、暂不表态——这是 handler
    /// 内的连续判读（识别器已经 begin），不是生死
    /// 关的量级门；过线后逐帧判读到定案为止
    public static let decisionFloor: CGFloat = 8

    /// handler 方向仲裁三态
    public enum Arbitration: Equatable {
        /// 位移未过决定下限，继续看下一帧
        case undecided
        /// 横向右滑主导：跟手返回
        case follow
        /// 其余一切：让位给枢纽内列表纵滚
        case yieldToScroll
    }

    /// 方向仲裁（handler 内、begin 后调用）：只认
    /// translation 的方向比值——比值引 DrawerMotion
    /// .directionLockRatio 与全 App 方向锁单源；过决
    /// 定下限后不是明确横向右滑就让位
    public static func arbitration(
        translationX: CGFloat, translationY: CGFloat
    ) -> Arbitration {
        let ax = abs(translationX)
        let ay = abs(translationY)
        guard max(ax, ay) >= decisionFloor else { return .undecided }
        if translationX > 0,
           ax >= ay * DrawerMotion.directionLockRatio {
            return .follow
        }
        return .yieldToScroll
    }

    /// 跟手位移：负钳 0、上限封顶
    public static func followedOffset(translationX: CGFloat) -> CGFloat {
        min(max(translationX, 0), maxFollowOffset)
    }

    /// 松手裁决：回不回聊天页
    public static func shouldDismiss(
        translationX: CGFloat, velocityX: CGFloat
    ) -> Bool {
        if translationX >= dismissTranslation { return true }
        return translationX >= flickTranslation
            && velocityX >= flickVelocity
    }
}
