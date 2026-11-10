import Foundation

/// 右滑引用纯逻辑（0.36.19 立；0.36.26 §95 按生产
/// 同构整件重写）：消息气泡向右滑触发与长按菜单
/// 「回复」完全相同的引用动作，本枚举管它的全部
/// 数值判定——起滑线、拖动 offset、途中触发线、
/// 显示封顶、箭头显形进度、起始点排除。呈现层
/// （SwipeReplyModifier）只持拖动状态、判定全走
/// 本处单测把守。
///
/// 构造口径（Stream Chat SwiftUI 现行生产代码逐
/// 行同构，调研报告 production-patterns-research-
/// 20261111 §1.2/§1.5）：呈现层在行内容上挂
/// `.simultaneousGesture(DragGesture(minimumDi-
/// stance: 30))`，onChanged 只消费横向分量写
/// offset——**不设方向比值门、不做任何识别器编
/// 排**：纵滑时横向分量≈0、offset 恒 0、气泡不
/// 动，纵滚完整归列表；横滑只跟横向分量，纵向
/// 分量直接丢弃。阈值以 Stream 参数为单源，本
/// 处不许另写数字：起滑 30（MessageListConfig
/// minimumSwipeGestureDistance）、途中触发 60
/// （SwipeToReplyModifier.replyThreshold）、显示
/// 封顶 90（触发线＋起滑线，Stream maximumHor-
/// izontalSwipeDisplacement 同式）。
///
/// 沿革与退役（P-15）：0.36.19 首版 DragGesture
/// ＋onChanged 方向门真机压死纵滚；0.36.20–
/// 0.36.23 改走 UIKit 探针桥，先后换位移量级门/
/// 速度门/位移纯比值＋require(toFail:) 编排四轮
/// 真机全灭（形态①纹丝不动，判据三换死状不变、
/// 定案不在判据）。桥时代判据 `shouldBeginPan`
/// 与 `engages`、跟手口径 `followedOffset(dx:
/// lockTranslation:)`（扣锁定段）随桥整件退役；
/// 旧阈值 52（松手触发）/76（封顶）一并作废。
public enum SwipeReplyMotion {
    /// 起滑线：手势 minimumDistance 与「开始写
    /// 位移」的横向分量线同值（Stream 同式）
    public static let minimumDistance: CGFloat = 30
    /// 途中触发线：拖动 offset 越过此值即触发引
    /// 用（不等松手；同时是箭头武装态与显形进度
    /// 满格的判据）
    public static let triggerOffset: CGFloat = 60
    /// 显示位移封顶：箭头显形区＋气泡让位的最大
    /// 行程（状态值本身可超过，显示层钳到此值）
    public static let maxOffset: CGFloat = 90

    /// 拖动 offset（状态值，Stream dragChanged 同
    /// 义）：横向位移为负的事件**弃**（保留现值，
    /// 不回写——回拖过起点不抖、松手统一归零）；
    /// 未达起滑线归 0；达线后 1:1 取横向位移（不
    /// 扣起滑段——手势 minimumDistance 已把起步
    /// 段挡在 onChanged 之外，Stream 同式不扣）
    public static func dragOffset(
        translationWidth: CGFloat, currentOffset: CGFloat
    ) -> CGFloat {
        if translationWidth < 0 { return currentOffset }
        if translationWidth >= minimumDistance {
            return translationWidth
        }
        return 0
    }

    /// 显示位移：状态值两端钳制（负钳 0、右封顶
    /// maxOffset），呈现层 offset 只认本函数
    public static func displayOffset(for offset: CGFloat) -> CGFloat {
        min(max(offset, 0), maxOffset)
    }

    /// 途中触发判定：越线（严格大于）即触发——
    /// 恰压在线上不触发，与 Stream `offsetX >
    /// replyThreshold` 逐字同义；整段拖动只触发
    /// 一次由呈现层的一次性标记把守
    public static func shouldTrigger(offset: CGFloat) -> Bool {
        offset > triggerOffset
    }

    /// 箭头显形进度（0…1）：随位移趋近触发线长
    /// 满；呈现层据此驱动箭头的不透明度与缩放，
    /// 过线即满格
    public static func revealProgress(offset: CGFloat) -> Double {
        Double(min(max(offset / triggerOffset, 0), 1))
    }

    /// 起始点排除判定：拖动起始点落在任一排除帧
    /// 内即整段忽略（行内自有横向交互的子区——
    /// 代码块/表格的横向滚动——经 PreferenceKey
    /// 发布其在命名坐标空间内的帧，帧的坐标与手
    /// 势 startLocation 同空间，Stream 同款）
    public static func isExcluded(
        startLocation: CGPoint, frames: [CGRect]
    ) -> Bool {
        frames.contains { $0.contains(startLocation) }
    }
}
