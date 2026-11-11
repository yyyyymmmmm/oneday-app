import Foundation

/// 对话提示条档位（§131 提示纪律第 3 条「告知性提示
/// 瞬时自消」）：无需用户动手的告知统一自清——中性
/// 告知 5 秒、信息量大的重要告知 8 秒。常驻只留给
/// 「需要用户动手且带动作位」的面（错误族、审批卡、
/// 未配模型引导），那些不走本档位。5 秒档有自家先
/// 例：听写提示行 5 秒自清（DictationController）。
public enum ChatNoticeTier: String, CaseIterable, Equatable, Sendable {
    /// 中性告知（自家动作的确认回执、一次性状态告知）
    case brief
    /// 重要告知（点名信息量大、需要读完）
    case extended

    /// 自消秒数（赋值即起计时，到点自清、不留残影）
    public var autoDismissSeconds: Double {
        switch self {
        case .brief:
            return 5
        case .extended:
            return 8
        }
    }
}

/// 一条在场提示（值语义）。`id` 是代号：自清计时只
/// 准清自己那一代——新条换代后旧计时到期不得误清
/// 新条，已手关的条也不得被旧计时复活。
public struct ChatNotice: Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let tier: ChatNoticeTier

    public init(
        id: UUID = UUID(),
        text: String,
        tier: ChatNoticeTier
    ) {
        self.id = id
        self.text = text
        self.tier = tier
    }
}

/// 提示条呈现状态（纯值状态机，App 侧以 @State 持
/// 有）：赋值即换代；到期清除必须代号吻合，手关即
/// 清且旧代号从此失效。恢复成功类结果（重连、补
/// 齐）根本不进本状态机——§131 提示纪律第 1 条
/// 「成功不报」，静默是删除赋值点、不设档位。
public struct NoticePresentation: Equatable, Sendable {
    public private(set) var current: ChatNotice?

    public init() {}

    public var isPresenting: Bool { current != nil }

    /// 呈现新条（换代：旧条连同其代号一并作废）
    public mutating func present(_ notice: ChatNotice) {
        current = notice
    }

    /// 自清计时到期：仅当代号仍是当前条才清，返回
    /// 是否清掉（代号过期＝已被换代/手关，不动手）
    @discardableResult
    public mutating func expire(id: UUID) -> Bool {
        guard current?.id == id else { return false }
        current = nil
        return true
    }

    /// 手动关闭（✕／发送起手清）：即清，旧计时随后
    /// 到期也只能对空代号空转
    public mutating func dismiss() {
        current = nil
    }
}
