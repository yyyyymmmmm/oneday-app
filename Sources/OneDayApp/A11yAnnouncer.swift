import OneDayCore
import UIKit

/// VoiceOver 运行态播报（0.43.0 无障碍专项，
/// A11Y-S6）：系统开关响应里最后一块——VO 开启
/// 时把「看不见的状态变化」读出来（首用：生成
/// 完成）。VO 未运行时恒无声、不打扰普通用户；
/// 文案走 L10n 与界面同语言
enum A11yAnnouncer {
    static func announce(_ message: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(
            notification: .announcement, argument: message
        )
    }

    /// 生成完成（聊天流式下降沿）：VO 用户不必守
    /// 着焦点等回复落盘，完成即播报
    static func generationCompleted() {
        announce(L10n.string("回复完成"))
    }
}
