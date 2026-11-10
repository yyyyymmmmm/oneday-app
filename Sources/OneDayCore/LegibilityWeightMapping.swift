import Foundation

/// 粗体文字映射（0.36.0，无障碍走查 A11Y-S3／续
/// 编 S 组）：系统「粗体文本」开关此前全 App 零响
/// 应——字阶全走常规字重、开了等于没开。本文件只
/// 立策略（纯函数、单测钉）：根级给未钉字重的文
/// 本一个环境字重，钉死字重的位（Font.weight 烘
/// 进字体的、近处显式声明的）不归本策略管。呈现
/// 侧接线在 OneDayDesign 的 BoldTextRootModifier，
/// 全 App 只在根视图挂一处。
public enum BoldTextPolicy {
    /// 字重档（与呈现层 Font.Weight 语义档一一对
    /// 应；Core 不引 SwiftUI，只持档位）
    public enum Weight: Equatable, Sendable {
        case regular
        case medium
        case semibold
        case bold
    }

    /// 根级环境字重：关＝nil（不干预、呈现与现状逐
    /// 字一致）；开＝semibold（未钉字重的文本样式
    /// 字体统一按此档渲染，与系统粗体文本的视觉步
    /// 幅同级）
    public static func rootWeight(boldTextEnabled: Bool) -> Weight? {
        boldTextEnabled ? .semibold : nil
    }

    /// 单档升档表（逐处接入点将来若要按角色升档，
    /// 只许查本表、不许各页自定）：regular→medium
    /// →semibold→bold，bold 封顶不升
    public static func bumped(_ base: Weight) -> Weight {
        switch base {
        case .regular: return .medium
        case .medium: return .semibold
        case .semibold, .bold: return .bold
        }
    }
}
