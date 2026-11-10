import Foundation

/// 底部跟随判定（0.4.2，DESIGN-V4 §27）：消息列表
/// 「是否贴近底部」的迟滞判定与流式跟随滚动节流。
/// 0.4.1 前 isNearBottom 是单阈值（距底 <140）即时判
/// 定：距离在阈值附近游走时判定逐帧翻转，连带「回到
/// 底部」钮显隐（底部 inset 高度随之动画）与自动贴
/// 底滚动反复触发——划到底抖动的放大器之一。本版
/// 判定与节流收进纯逻辑钉死：迟滞双阈值（进入 <96／
/// 退出 ≥176，中间带保持原态）；流式跟随按字符增量
/// 节流（每 ≥40 字至多放行一次），不再逐 token 追
/// 逐移动中的底部。
public enum BottomProximity {
    /// 进入「贴近底部」的距底阈值（pt）
    public static let enterDistance: CGFloat = 96
    /// 退出「贴近底部」的距底阈值（pt）；与进入阈值
    /// 之间是迟滞带，带内保持上一判定
    public static let exitDistance: CGFloat = 176

    /// 距底距离＝内容高 − 滚动偏移 − 容器高；橡皮筋
    /// 越过底部时为负（仍算贴底）
    public static func update(
        distance: CGFloat, wasNearBottom: Bool
    ) -> Bool {
        if wasNearBottom {
            return distance < exitDistance
        }
        return distance < enterDistance
    }
}

/// 底部跟随策略（0.36.5，聊天细节审计双修）：发送
/// 贴底与回底钮显隐的决策收进纯逻辑钉死，视图层只
/// 执行——
/// - 自己发送是「离底不打扰」的唯一例外：发送落盘
///   成功后无条件进贴底态（聊天 UI 通则 onNewMes-
///   sage＝atBottom || isOwnMessage）。旧实现 send()
///   无任何贴底动作、跟随又被 isNearBottom 门控，用
///   户上滑回看时发送，自己的消息与整段回复全被挡
///   在视外（审计 bug 1）。
/// - 回底钮显隐除几何判定外并入事实信号「最后一条
///   条目已在可见集内」：距底距离取自 LazyVStack 的
///   估算总高，长线程误差可把估算距离驻留在迟滞带
///   （96…176）内——用户已划到视觉底部、最后一条
///   肉眼可见，几何却仍报离底，钮永不消失（审计
///   bug 2）。事实信号只参与钮显隐，不改跟随门控
///   与滚动锚口径。
public enum BottomFollowPolicy {
    /// 发送落盘成功后 isNearBottom 的目标值：恒真
    /// ——置真后流式跟随与落定跟随自动接续，发送路
    /// 径只需再补即时贴底＋延迟复贴两步（视图层）
    public static func nearBottomAfterOwnSend() -> Bool { true }

    /// 回底钮显隐：几何判定离底、且最后一条条目不
    /// 在可见集内，两条同时成立才显示
    public static func showsScrollToBottomButton(
        isNearBottom: Bool, lastEntryVisible: Bool
    ) -> Bool {
        !isNearBottom && !lastEntryVisible
    }
}

/// 流式跟随滚动节流闸（0.4.2，§27）：流式文本每个
/// 增量都变化一次，逐次触发贴底滚动等于让滚动动画
/// 无限追逐随文本生长移动的底部。本闸按已跟随到的
/// 字符数记账：新增 ≥40 字才放行一次跟随；流结束的
/// 最后一贴由落盘条目变化事件承担，不经本闸。
public struct StreamFollowGate: Equatable {
    /// 放行一次跟随所需的最小新增字符数
    public static let minimumGrowth = 40
    /// 已跟随到的流式全文长度
    public private(set) var followedCount = 0

    public init() {}

    /// currentCount 为当前流式全文长度。放行时记账
    /// 到当前长度并返回 true；增量不足返回 false。
    /// 长度比已跟随数还小（新一轮流未经 reset 直接
    /// 开始）按从零计，不卡死
    public mutating func shouldFollow(currentCount: Int) -> Bool {
        let baseline = currentCount >= followedCount ? followedCount : 0
        guard currentCount - baseline >= Self.minimumGrowth else {
            return false
        }
        followedCount = currentCount
        return true
    }

    /// 一轮流结束／切换会话时归零
    public mutating func reset() {
        followedCount = 0
    }
}
