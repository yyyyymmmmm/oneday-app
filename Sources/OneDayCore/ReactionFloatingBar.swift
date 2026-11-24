import Foundation

// MARK: - 反应浮排开关（DESIGN §343）

/// 反应浮排特性开关（反应浮排包第一步）：长按消息
/// 先浮出反应药丸排（Muse 形态），动作列表仍走
/// 系统面。UserDefaults 布尔键，**缺省 true**＝浮
/// 排开；显式 false 回 0.50.80 形态（反应走系统菜
/// 单「添加反应」子菜单）——回滚不发版：设置→外
/// 观→回复呈现可关。存取口径与 ChatStreaming-
/// Feature 同（键缺省与显式 true 同义、只有显式
/// false 才关）
public enum ChatReactionsFloatingBarFeature {
    public static let defaultsKey = "chat.reactions.floatingBar"

    public static func isEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil
        else { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}

/// 长按呈现路由（纯函数单点）：开关开且本条可反
/// 应才走浮排；其余一律系统菜单原形态——不可反
/// 应条目（未钉桩/未落定）不因浮排开关改变呈现面
public enum ReactionBarRoute: Equatable, Sendable {
    case systemMenu
    case floatingBar
}

public enum ReactionBarRouting {
    public static func route(
        flagEnabled: Bool, canReact: Bool
    ) -> ReactionBarRoute {
        flagEnabled && canReact ? .floatingBar : .systemMenu
    }
}

// MARK: - 浮排呈现状态机

/// 浮排阶段：idle（无呈现）／bar（三层同呈在场：
/// 药丸排＋快照＋动作卡，DESIGN §346）
public enum ReactionBarPhase: Equatable, Sendable {
    case idle, bar
}

/// 状态机迁移产出：视图/会话层据此执行呈现与投
/// 递——机内不碰数据与回调，反应投递由会话层在
/// 收到 deliverReaction 后调 data.onPickReaction、
/// 动作执行由会话层在收到 deliverAction 后调条目
/// 自带 action（与系统菜单同一闭包路由）
public enum ReactionBarEffect: Equatable, Sendable {
    case presentBar, deliverReaction, deliverAction
}

/// 反应浮排呈现状态机（纯值、无副作用）：长按进
/// bar（三层同呈）；bar 内点药丸＝投递反应并回
/// idle、点动作卡条目＝执行动作并回 idle；呈现被
/// 外部关闭回 idle。阶段不合的事件一律忽略（返回
/// nil），不许错序投递（防双投）。§343 的转交迁
/// 移（requestActions/actionSheet）随 §346 动作卡
/// 同呈退役：动作已在同一呈现内、无处可转交；不
/// 可反应长按在本机不直达任何面（路由层恒先拦、
/// 会话只在可反应时创建）
public struct ReactionBarStateMachine: Equatable, Sendable {
    public private(set) var phase: ReactionBarPhase = .idle

    public init() {}

    @discardableResult
    public mutating func longPress(
        canReact: Bool
    ) -> ReactionBarEffect? {
        guard phase == .idle, canReact else { return nil }
        phase = .bar
        return .presentBar
    }

    @discardableResult
    public mutating func pickReaction() -> ReactionBarEffect? {
        guard phase == .bar else { return nil }
        phase = .idle
        return .deliverReaction
    }

    @discardableResult
    public mutating func pickAction() -> ReactionBarEffect? {
        guard phase == .bar else { return nil }
        phase = .idle
        return .deliverAction
    }

    /// 呈现被外部关闭（点空白/快照收起/浮排被系统
    /// 收起）：任意非 idle 阶段回 idle；已 idle 返回
    /// false
    @discardableResult
    public mutating func dismiss() -> Bool {
        guard phase != .idle else { return false }
        phase = .idle
        return true
    }
}

// MARK: - 反应全集目录（DESIGN §346）

/// 药丸排「＋」展开目录：完整常用集（表情/手势/
/// 爱心/庆典/日常符号）。与 MessageReactions.
/// palette（用户拍板样板 8 个、药丸排本体）不重
/// 复、不替换——palette 仍是单排唯一集，本目录只
/// 供半页网格展开层消费。写入路径核查（§346 施
/// 工图）：反应以 String 存储、toggle/乐观组装/
/// 端点参数均无 palette 限定，集外 emoji 与集内
/// 同路落锤
public enum ReactionEmojiCatalog {
    public static let morePalette: [String] = [
        // 表情
        "😀", "😄", "😁", "🤣", "😊", "😍", "😘", "😎",
        "🤔", "🤨", "😐", "😑", "😶", "😴", "😪", "🤤",
        "😷", "🤒", "🤕", "🤢", "🤮", "🥵", "🥶", "🥴",
        "😵", "🤯", "🥳", "🥺", "😳", "🤗", "🤫", "🤭",
        "🫡", "🙄", "😬", "🤐", "😈", "💀", "👻", "👽",
        "🤖", "🎃", "😺", "😸", "😹",
        // 手势与身体
        "👎", "👏", "🙌", "🤝", "💪", "🦾", "🖖", "✌️",
        "🤞", "🫰", "🤟", "🤙", "👌", "🤌", "👈", "👉",
        "👆", "👇", "☝️", "✋", "👋", "🫶", "🧠", "👀",
        // 爱心、庆典与日常符号
        "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎",
        "💔", "💖", "💗", "💯", "💢", "💥", "💫", "⭐",
        "🌟", "✨", "⚡", "🌈", "☀️", "🌙", "☔", "❄️",
        "🎊", "🎁", "🏆", "🥇", "🍻", "🥂", "☕", "🍺",
        "🎂", "🍕", "🍔", "🌹", "🌸", "💡", "💰", "💎",
        "🔑", "📌", "✂️", "✅", "❌", "❓", "❗", "⚠️",
        "🚀", "🎵", "🎧", "⚽", "🏀", "🐶", "🐱", "🦄",
        "🍀",
    ]
}
