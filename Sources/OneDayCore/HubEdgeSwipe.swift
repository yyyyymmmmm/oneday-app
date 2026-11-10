import Foundation

/// 枢纽页左边缘右滑返回的仲裁（0.36.22）：整页呈现
/// （fullScreenCover）没有导航栈的系统 pop 手势，用
/// UIScreenEdgePanGestureRecognizer（系统边缘识别器
/// 本体）补齐，判据全收本处、单测把守：
///
/// - 生死（shouldBegin）只认**速度域**：begin 被咨询
///   的时刻平移≈0、读位移判方向恒假死（0.36.21 右滑
///   再修定案，错题本 P-15 续修）——右向且横向主导
///   的速度才放行，纵向主导（列表滚动的形态）在识
///   别器生死关就被拒、纵滚完整归列表。
/// - 跟手位移只进不出：负位移钳 0（左拖不跟）、上
///   限封顶（整页横移不跑飞）。
/// - 松手裁决只认位移与速度两数：位移过线直接返
///   回；位移半线＋快甩也返回（与消息列表右滑引用
///   「只认位移不认速度」的口径不同——那边是内容手
///   势、误触代价是错引用；这边是页面返回、快甩是
///   用户明确的返回意图，两处口径各自成文不混）。
public enum HubEdgeSwipe {
    /// 跟手位移封顶（pt）
    public static let maxFollowOffset: CGFloat = 480
    /// 松手位移直达线（pt）
    public static let dismissTranslation: CGFloat = 90
    /// 快甩辅助线：位移（pt）与速度（pt/s）
    public static let flickTranslation: CGFloat = 40
    public static let flickVelocity: CGFloat = 500

    /// 生死判据（速度域）：右向且横向主导才 begin
    public static func shouldBegin(
        velocityX: CGFloat, velocityY: CGFloat
    ) -> Bool {
        velocityX > 0 && abs(velocityX) > abs(velocityY)
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
