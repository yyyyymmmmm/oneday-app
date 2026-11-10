import Foundation

/// 枢纽根页左缘右滑退出的阈值与触发判读（0.36.27
/// §97 件五整桥退役后留下的全部）：
///
/// - 沿革：0.36.22 立 UIKit 边缘探针桥（HubEdge-
///   SwipeBridge）＋本处桥判据（生死关/handler 仲裁/
///   跟手/松手裁决），0.36.24 改判一轮、0.36.26 加深
///   度门控——真机四轮从未成功退出根页，且深度门控
///   被证伪（NavigationStack(path:) 不追踪目标式推
///   入、hubPath 恒空、探针从未停用，状态页 pop 一
///   直在与探针抢触摸）。0.36.27 整桥退役：栈内页
///   返回全归系统 pop；根页退出改 SwiftUI 边缘拖
///   （AgentHubView 根内容挂 .simultaneousGesture，
///   与聊天右滑引用同族构造——后者已于 0.36.26 真
///   机证明）。
/// - 本处只留阈值常量与一条纯判读：起始点须落在左
///   缘带内、横向位移途中过线即触发（严格大于，与
///   SwipeReplyMotion.shouldTrigger 同义）。桥时代
///   的 arbitration/followedOffset/shouldDismiss 及
///   其速度/比值判据全数退役，不许复活。
public enum HubEdgeSwipe {
    /// 起始点左缘带宽（pt，全局坐标）
    public static let edgeWidth: CGFloat = 28
    /// 起滑线（pt）：与聊天右滑引用同值单源口径
    public static let minimumDistance: CGFloat = 30
    /// 途中触发线（pt）：横向位移严格大于此数即退出
    public static let triggerTranslation: CGFloat = 60

    /// 起始点是否落在左缘带内
    public static func isEdgeStart(globalX: CGFloat) -> Bool {
        globalX <= edgeWidth
    }

    /// 途中触发判读：左缘起手＋横向位移过线
    public static func shouldTrigger(
        startGlobalX: CGFloat, translationX: CGFloat
    ) -> Bool {
        isEdgeStart(globalX: startGlobalX)
            && translationX > triggerTranslation
    }
}
