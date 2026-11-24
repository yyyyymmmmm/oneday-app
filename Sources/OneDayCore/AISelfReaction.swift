import Foundation

// MARK: - AI 自反应开关（DESIGN §432）

/// AI 自反应特性开关：助手给用户消息贴的反应在本
/// 机显不显。UserDefaults 布尔键，**缺省 true**＝
/// 显示；显式 false 只关本机呈现——服务端照常产
/// 生、数据不删，重新打开历史角标全量回来（施工
/// 图 §4 口径）。存取口径与 ChatReactionsFloating-
/// BarFeature 同（键缺省与显式 true 同义、只有显
/// 式 false 才关）。服务端总闸是另一回事（部署侧
/// config display.agent_self_reactions），不在本键
/// 语义内
public enum ChatReactionsAISelfFeature {
    public static let defaultsKey = "chat.reactions.aiSelf"

    public static func isEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil
        else { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}

// MARK: - 呈现判定（纯函数单点，呈现与行高共用）

/// AI 自反应的呈现分工判定（§432）：反应按 author
/// 分型两面——用户自己的段走既有 pill（ChatView 承
/// 接 MessageReactions.ownReactions），助手的段走
/// 用户气泡角小角标，两面永不合并。本枚举只判角
/// 标一面与「铬件在场」（行高预留与呈现共用同判，
/// 不许两处各写一份：§329 facet 纪律）
public enum AISelfReactionDecision {

    /// 角标 emoji：开关开且镜像里有 agent 反应才
    /// 出；用户自己的反应再多也不误触（分型单点
    /// 在 MessageReaction.isAgent）
    public static func badgeEmoji(
        reactions: [MessageReaction],
        featureEnabled: Bool
    ) -> String? {
        guard featureEnabled else { return nil }
        return MessageReactions.agentEmoji(in: reactions)
    }

    /// 反应铬件在场（pill 或角标任一在场）：行高
    /// 合成器的 reactionReserve 与本判逐值同源——
    /// 开关关时仅有 agent 反应的行不再预留
    public static func hasVisibleChrome(
        reactions: [MessageReaction],
        featureEnabled: Bool
    ) -> Bool {
        if reactions.contains(where: { $0.isOwn }) {
            return true
        }
        return badgeEmoji(
            reactions: reactions,
            featureEnabled: featureEnabled
        ) != nil
    }
}

// MARK: - 设置行显隐（能力门控）

/// 外观页「AI 反应」开关行的显隐策略（§432）：服
/// 务端能力位 self_reactions 未广告（协商结论非
/// available，含未探得的 unknown）时整行不出——
/// 僵尸禁令（施工图 §4）：没接通宁可不上架，不给
/// 用户一个拨了没反应的开关。开关自身开闭不影响
/// 行显隐（行在场时开关才有意义）
public enum SelfReactionsSettingsRowPolicy {
    public static func isRowVisible(
        availability: CapabilityAvailability
    ) -> Bool {
        availability == .available
    }
}
