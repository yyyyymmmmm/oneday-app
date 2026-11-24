import Foundation

/// 右滑引用纯逻辑（0.36.19 立；0.36.26 §95 按生产
/// 同构整件重写）：消息气泡向右滑触发与长按菜单
/// 「回复」完全相同的引用动作，本枚举管它的全部
/// 数值判定——起滑线、拖动 offset、途中触发线、
/// 显示封顶、箭头显形进度、起始点排除、方向锁定。
/// 呈现层（SwipeReplyModifier）只持拖动状态、判定
/// 全走本处单测把守。
///
/// 数值口径（Stream Chat SwiftUI 现行生产代码同
/// 源，调研报告 production-patterns-research-
/// 20261111 §1.2/§1.5）：阈值以 Stream 参数为单
/// 源，本处不许另写数字：起滑 30（MessageList-
/// Config minimumSwipeGestureDistance）、途中触
/// 发 60（SwipeToReplyModifier.replyThresh-
/// old）、显示封顶 90（触发线＋起滑线，Stream
/// maximumHorizontalSwipeDisplacement 同式）。
/// 承载构造沿革：0.36.26–§264 呈现层挂 SwiftUI
/// simultaneousGesture(DragGesture) 只消费横向
/// 分量（纵滑时横向分量≈0、offset 恒 0）；§265
/// 起识别层换 UIKit 仲裁（见下沿革段），本枚举
/// 数值逐字不变。
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
///
/// §265（换代包 5，用户 2026-11-14 亲令大厂机制
/// 三条之③）：simultaneousGesture 构造与双击选
/// 字共存失败（双审计定性：SwiftUI 手势跟踪消耗
/// 文本视图的触摸序列），呈现层改走 UIKit 识别
/// 器仲裁——UIPanGestureRecognizer 装在宿主滚
/// 动视图上（ScrollViewTapDismiss 的 ascend 装
/// 配同路），仲裁两条：方向门（本处 passesDir-
/// ectionGate，gestureRecognizerShouldBegin 消
/// 费）＋失败依赖（点按/长按先行，delegate 的
/// shouldRequireFailureOf 声明；列表纵滚经
/// require(toFail:) 等本识别器先失败）。本枚举
/// 的数值口径（起滑/触发/封顶/排除）逐字不变，
/// 变的只是识别与仲裁的承载层；桥的装配与回调
/// 在 OneDayApp SwipeReplyPanBridge。
///
/// 换代包 7（0.50.78 真机反馈修复 B，仲裁重做）：
/// 方向判定改位移式方向锁（成熟做法对位）——起
/// 手前约 10pt 位移内按累计位移比判定方向（|dx|
/// > |dy| 且 dx > 0 即横向锁定、立即 1:1 跟手），
/// 判死只针对明确竖向位移；仲裁关系收窄为只等滚
/// 动、不等点按/长按（位移锁已解决共存）；触发
/// 阈值维持 60pt、越线给 soft 触觉（带回程 re-arm
/// 迟滞 55pt）。旧速度门 passesDirectionGate 退役。
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
    /// 方向锁定判定距离：起手前此距离内按累计位
    /// 移比判定方向（大厂通行带 5–16pt，本处取
    /// 10pt 中值）
    public static let directionLockDistance: CGFloat = 10
    /// 触觉 re-arm 回程线：越过触发线后回拖到此
    /// 值以下才重新武装（迟滞防抖，触发线 60 →
    /// 回程线 55，差值 5pt）
    public static let hapticRearmThreshold: CGFloat = 55

    /// 拖动 offset（状态值，Stream dragChanged 同
    /// 义）：横向位移为负的事件**弃**（保留现值，
    /// 不回写——回拖过起点不抖、松手统一归零）；
    /// 未达起滑线归 0；达线后 1:1 取横向位移（不
    /// 扣起步段——手势 minimumDistance 已把起步
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

    // MARK: - 方向锁定（换代包 7，位移式判定）

    /// 滑动方向：未定/横向/竖向三态
    public enum SwipeDirection {
        case undetermined
        case horizontal
        case vertical
    }

    /// 方向锁定判定（位移式，换代包 7）：累计位
    /// 移按比值判方向——|dx| > |dy| 且 dx > 0 即
    /// 横向锁定；|dy| > |dx| 即竖向判死（让给滚
    /// 动）；两者皆不满足归未定（继续观察）。判
    /// 据口径：大厂通行做法（WhatsApp / Telegram /
    /// iMessage 同构，mature-practice-gestures-
    /// topbar-20261122.md 题 2.1③）
    public static func determineDirection(
        translationX: CGFloat, translationY: CGFloat
    ) -> SwipeDirection {
        let absDx = abs(translationX)
        let absDy = abs(translationY)

        if absDx > absDy && translationX > 0 {
            return .horizontal
        } else if absDy > absDx {
            return .vertical
        }
        return .undetermined
    }

    /// 方向门（退役，换代包 7）：速度式判定已改
    /// 位移式方向锁，本方法保留供过渡期兼容、不
    /// 再被桥消费
    @available(*, deprecated, message: "已改位移式方向锁，本方法不再使用")
    public static func passesDirectionGate(
        velocityX: CGFloat, velocityY: CGFloat
    ) -> Bool {
        velocityX > 0 && abs(velocityX) > abs(velocityY)
    }
}
