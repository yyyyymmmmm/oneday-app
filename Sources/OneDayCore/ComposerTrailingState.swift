import Foundation

/// 发送舱右端状态机（0.25.0，交互与动效专包立）：
/// 胶囊右端在三态间切换——空输入出裸麦克风占位、
/// 有可发送内容出发送箭头、流式中出停止键。三态
/// 判定原散在 ChatView.trailingControl 的条件里，
/// 本枚举收敛为纯函数：视图只读它选形态与驱动切
/// 换动画（mic↔发送/停止的 opacity 交叉淡化以本
/// 枚举为动画值），判定口径由单测把守。判定序自
/// §446（用户 2026-11-24 亲裁）定版为「内容优
/// 先」：有可发送内容恒出发送（流式中点按走
/// §419 排队落位），无内容时流式中出停止、空闲
/// 出麦克风——单槽位按内容切换（对位 ChatGPT/
/// Claude 单槽置换的通行形态）。§419 曾设双钮
/// 态（发送＋停止小钮同排），真机
/// 实证双钮总宽 62pt 溢出布局槽位 30pt、发送钮
/// 被挤出屏幕（0.50.105 verdict），§446 退役。
public enum ComposerTrailingState: Equatable, CaseIterable {
    /// 空输入：裸麦克风符号占位（语音未接入）
    case mic
    /// 有可发送内容（文字或附件）：发送箭头
    case send
    /// 流式生成中且无可发送内容：停止键
    case stop

    /// 判定序（§446）：可发送 → 发送；流式 →
    /// 停止；否则占位（麦克风）。单槽位恒一钮，
    /// 任何状态下布局宽都是 ComposerLayout
    /// .buttonHeight，切换不引起输入栏宽度跳动
    public static func resolve(
        isStreaming: Bool, canSend: Bool
    ) -> ComposerTrailingState {
        if canSend { return .send }
        if isStreaming { return .stop }
        return .mic
    }

    /// 派发同一圆盘按钮在当前状态下的动作。
    public func activateDisc(onSend: () -> Void, onStop: () -> Void) {
        switch self {
        case .send: onSend()
        case .stop: onStop()
        case .mic: break
        }
    }

    /// 是否为圆盘键形态（发送/停止共用同一颗圆
    /// 盘键，内部符号以 symbolEffect 形变切换；
    /// 麦克风是裸符号、无圆盘）
    public var isDiscKey: Bool {
        self != .mic
    }
}
