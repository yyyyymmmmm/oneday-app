import Foundation

/// 发送舱右端状态机（0.25.0，交互与动效专包立）：
/// 胶囊右端在三态间切换——空输入出裸麦克风占位、
/// 有可发送内容出发送箭头、流式中出停止键。三态判
/// 定原散在 ChatView.trailingControl 的条件里，本枚
/// 举收敛为纯函数：视图只读它选形态与驱动切换动画
/// （mic↔发送/停止的 opacity 交叉淡化以本枚举为动画
/// 值），判定口径由单测把守（流式优先于可发送——流
/// 式中即使输入框已有字，右端也必须是停止键）。
public enum ComposerTrailingState: Equatable, CaseIterable {
    /// 空输入：裸麦克风符号占位（语音未接入）
    case mic
    /// 有可发送内容（文字或附件）：发送箭头
    case send
    /// 流式生成中：停止键
    case stop

    /// 三态判定：流式优先（停止），其次可发送（发
    /// 送），否则占位（麦克风）
    public static func resolve(
        isStreaming: Bool, canSend: Bool
    ) -> ComposerTrailingState {
        if isStreaming { return .stop }
        return canSend ? .send : .mic
    }

    /// 是否为圆盘键形态（发送/停止共用同一颗圆盘键，
    /// 内部符号以 symbolEffect 形变切换；麦克风是裸
    /// 符号、无圆盘）
    public var isDiscKey: Bool {
        self != .mic
    }
}
