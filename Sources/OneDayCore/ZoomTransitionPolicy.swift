import Foundation

/// Zoom 转场裁决（动效规矩包，DESIGN-V4 §245.2）：共享
/// 元素放大转场（系统 .zoom）只许在「有真源＋动态允许」
/// 两条件齐备时启用，任一不成立即回标准呈现——裁决收
/// 在 Core 纯函数，呈现层（UIKit preferredTransition /
/// SwiftUI navigationTransition）只许问它，不许各面自判。
///
/// - 源不可用：源视图已滚出屏/被列表回收/入口未挂锚点
///   时，硬启 zoom 只会得到无源的假放大，不如标准呈现。
/// - Reduce Motion：动效宪法 M8——位移/缩放类转场降级
///   为标准呈现（系统默认），不许无降级直上 zoom。
public enum ZoomTransitionDecision: Equatable {
    /// 启用系统 zoom 转场（自源视图长出）
    case zoom
    /// 标准呈现（系统默认转场，不做共享元素放大）
    case standard
}

public enum ZoomTransitionPolicy {
    public static func decide(
        reduceMotion: Bool,
        sourceAvailable: Bool
    ) -> ZoomTransitionDecision {
        if reduceMotion { return .standard }
        return sourceAvailable ? .zoom : .standard
    }
}
