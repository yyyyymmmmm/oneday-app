#if canImport(UIKit)
import UIKit
#endif

/// 触觉反馈（0.3.2 按礼记纪律收编，DESIGN-V4 §17）：只挂
/// 「结果事件」，不给普通点按、滚动、抽屉吸附、确认弹窗
/// 撒震动——
/// - 成功结果（发送完成、复制、连接成功、指令发送成功）
///   ＝ .success
/// - 失败结果（发送失败、连接失败、操作失败）＝ .warning
/// 0.2.2 的 light/medium 影响反馈点（抽屉开合、删除确认、
/// 发送起手、网关确认）自本版起全部撤销，触点清单以
/// §17.5 为准。复制点的触感在 CopyButton 内以 SwiftUI
/// .sensoryFeedback(.success) 施加（设计层组件够不着本
/// 文件），语义同属本纪律。
enum Haptics {
    /// 结果成功（通知型反馈）
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// 结果失败（通知型反馈）
    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
