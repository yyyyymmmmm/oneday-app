import Foundation

/// 选择框状态机（总表 203／DESIGN §441）：纯派生、
/// 无存储——卡的存废由「它挂的那行还在不在线程
/// 尾部」决定，与审批卡（服务端待批账真源）分工
/// 不同：选择框真源在消息行 display_metadata，
/// 本机只持瞬态覆盖层（见 OptionsCardOverlay）
public enum OptionsCardState: Equatable, Sendable {
    /// 可点：卡行是线程内最后一条 assistant 发言
    /// 行、其后无 user 行、无在飞 run
    case live
    /// 已点选：卡收起为一行静态回执（与审批卡流
    /// 内回执同口径），载荷为所选 label
    case selected(String)
    /// 过期：卡后已有 user 行或新一轮已落定——置
    /// 灰紧凑、不可点；仅覆盖层在席时呈现，重启
    /// 后不再播种＝自然消失（失效侧安全）
    case expired
    /// 不渲染：无卡／演示态／能力未证（行高不留位）
    case hidden
}

/// 选择框状态派生（纯函数，钉测面）
public enum OptionsCardLogic {
    public static func state(
        card: OptionsCardOverlay.Card?,
        isTailAssistant: Bool,
        hasUserAfter: Bool,
        runInFlight: Bool,
        isDemo: Bool
    ) -> OptionsCardState {
        guard let card, !isDemo else { return .hidden }
        if let selected = card.selectedLabel {
            return .selected(selected)
        }
        guard isTailAssistant, !hasUserAfter, !runInFlight
        else { return .expired }
        return .live
    }

    /// 播种尾位规则（落定回读与历史导入共用）：
    /// 线程内最后一条 assistant 发言行带 options
    /// 且其后无 user 行才成卡；messages 为服务端
    /// 原序（旧→新）
    public static func seedCandidate(
        in messages: [SessionMessage]
    ) -> (serverRowID: Int, options: MessageOptions)? {
        guard let lastAssistant = messages.last(where: {
            $0.role == "assistant"
        }), let options = lastAssistant.options else {
            return nil
        }
        let after = messages.drop(while: { $0.id != lastAssistant.id }).dropFirst()
        guard !after.contains(where: { $0.role == "user" }) else {
            return nil
        }
        return (Int(lastAssistant.id), options)
    }
}

/// 选择框瞬态覆盖层（§441 存储定版）：v1 不动
/// ChatEntry／不走 schema 升版——选项只在会话尾
/// 部可点，覆盖层每线程至多一张活卡；服务端仍
/// 是唯一真源，重进线程按尾位规则重播种。过期
/// 置灰痕迹跨重启持久化是明示欠账，等下一次
/// schema 升版与 reactionsData 同形搭车
@MainActor
public final class OptionsCardOverlay {
    public struct Card: Equatable, Sendable {
        public let serverRowID: Int
        public let options: MessageOptions
        public var selectedLabel: String?

        public init(
            serverRowID: Int, options: MessageOptions,
            selectedLabel: String? = nil
        ) {
            self.serverRowID = serverRowID
            self.options = options
            self.selectedLabel = selectedLabel
        }
    }

    private var cards: [UUID: Card] = [:]

    public init() {}

    public func card(for threadID: UUID) -> Card? {
        cards[threadID]
    }

    /// 播种：只接受不旧于现卡的行（重进线程重播
    /// 种同行幂等；旧行迟到不许覆盖新卡）
    public func seed(threadID: UUID, card: Card) {
        if let existing = cards[threadID],
           existing.serverRowID > card.serverRowID {
            return
        }
        cards[threadID] = card
    }

    /// 点选即消费：记所选 label（回执呈现），卡
    /// 不复活——发送失败走发件箱原位重试（§414）
    public func markSelected(threadID: UUID, label: String) {
        cards[threadID]?.selectedLabel = label
    }

    public func clear(threadID: UUID) {
        cards[threadID] = nil
    }
}

/// 选择框行高输入（App 行高合成器消费的值形）：
/// 状态＋项数——选项行单行截断（lineLimit(1)）
/// 高度只由项数定，不量文本（与来源条限行量测
/// 价同思路、更严：恒定行高）
public struct OptionsCardHeightInput: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case live
        case selected
        case expired
    }

    public let kind: Kind
    public let optionCount: Int

    public init(kind: Kind, optionCount: Int) {
        self.kind = kind
        self.optionCount = optionCount
    }

    public init?(state: OptionsCardState, optionCount: Int) {
        switch state {
        case .live: kind = .live
        case .selected: kind = .selected
        case .expired: kind = .expired
        case .hidden: return nil
        }
        self.optionCount = optionCount
    }
}
