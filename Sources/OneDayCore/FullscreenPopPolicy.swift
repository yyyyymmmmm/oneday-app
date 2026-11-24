import Foundation

/// 全屏右滑返回的统一裁决（呈现与导航手势审计
/// 2026-11-24 问题二）：全 App 导航栈共用一处
/// UIKit 桥（App 层 FullscreenPopBridge），是否
/// 放行全屏 pop 只问本件——系统转场本体不换、
/// 只换识别器作用域，裁决口径收在此一处纯函数，
/// 各栈不许自拼近似判定。事实采集（栈深/转场
/// 态/豁免命中）在 App 层判定时刻完成（与抽屉
/// 场景门 §323 的「采集半/判定半」同式）。
public enum FullscreenPopPolicy {

    /// 裁决入参：判定一刻的场景事实
    public struct Scene: Equatable {
        /// 所在导航栈的当前深度（根页＝1）
        public var stackDepth: Int
        /// 识别器当前累计位移（右滑为正 x）
        public var translation: CGSize
        /// 栈上已有转场在飞（push/pop 动画未落定）
        public var isTransitioning: Bool
        /// 触点起点落在豁免区内（横向滚动面/图像
        /// 平移面等自有横向手势的区域，标记件登记）
        public var startsInExemptRegion: Bool

        public init(
            stackDepth: Int,
            translation: CGSize,
            isTransitioning: Bool,
            startsInExemptRegion: Bool
        ) {
            self.stackDepth = stackDepth
            self.translation = translation
            self.isTransitioning = isTransitioning
            self.startsInExemptRegion = startsInExemptRegion
        }
    }

    /// 放行全屏 pop 的充要条件（裁决表正本）：
    /// 栈深 >1（根页无返回、归呈现方自己的关闭
    /// 口）、无转场在飞、起点不在豁免区、位移
    /// 右向且横向主导（纵向主导归列表滚动，与
    /// 抽屉门 D、卡片方向锁同一仲裁哲学）
    public static func shouldBegin(_ scene: Scene) -> Bool {
        guard scene.stackDepth > 1 else { return false }
        guard !scene.isTransitioning else { return false }
        guard !scene.startsInExemptRegion else { return false }
        guard scene.translation.width > 0 else { return false }
        return abs(scene.translation.width)
            > abs(scene.translation.height)
    }
}
