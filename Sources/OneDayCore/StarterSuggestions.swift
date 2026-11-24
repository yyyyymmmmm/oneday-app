import Foundation

/// §455 聊天空态建议分级：需要处理 > 未完事项 > 时段
/// 相关 > 冷启回落。数值越小越优先，装配按级序取前三。
public enum StarterSuggestionTier: Int, Codable, Equatable, Sendable {
    case actionNeeded = 0
    case unfinished = 1
    case timeContext = 2
    case fallback = 3
}

/// 一条空态建议：文案是可直接发出的完整问句（点按即
/// 经既有 send 链发出）；key 是稳定身份——状态类建议
/// 的 key 带状态指纹，状态一变 key 即换、旧抑制自动
/// 失效，不必等抑制窗过期。
public struct StarterSuggestion: Equatable, Sendable, Identifiable {
    public let key: String
    public let text: String
    public let symbol: String
    public let tier: StarterSuggestionTier

    public var id: String { key }

    public init(
        key: String, text: String, symbol: String,
        tier: StarterSuggestionTier
    ) {
        self.key = key
        self.text = text
        self.symbol = symbol
        self.tier = tier
    }
}

/// 装配快照：每一项都对应一个 App 已经在同步的真数据
/// 口，nil/空＝该口暂无数据（没同步到/当下无此事），
/// 引擎据此不生成该条——不许拿默认值脑补用户状态。
public struct StarterContext: Equatable, Sendable {
    /// 待批请求（Hub 审核段 /pending 回读）：token 是
    /// 状态指纹（条数＋最新一条 id），新待批到达即换。
    public struct PendingApprovals: Equatable, Sendable {
        public let count: Int
        public let token: String

        public init(count: Int, token: String) {
            self.count = count
            self.token = token
        }
    }

    /// 卡住的目标（activity.state == blocked 或有失败
    /// 任务）：token 是状态指纹（卡住起始/最近活动时刻）。
    public struct BlockedGoal: Equatable, Sendable {
        public let id: String
        public let title: String
        public let token: String

        public init(id: String, title: String, token: String) {
            self.id = id
            self.title = title
            self.token = token
        }
    }

    /// 在推进中的目标（running/waiting，取最近活动一条）
    public struct ActiveGoal: Equatable, Sendable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// 最近一次运行失败的定时任务（last_error 非空）：
    /// token 是状态指纹（last_run_at 原串），再跑即换。
    public struct FailedCronJob: Equatable, Sendable {
        public let id: String
        public let name: String
        public let token: String

        public init(id: String, name: String, token: String) {
            self.id = id
            self.name = name
            self.token = token
        }
    }

    /// 资源库最近交付物（48 小时内）：newestName 是最
    /// 新一份的文件名，extraCount 是其余份数；token
    /// 是状态指纹（最新一份路径＋mtime），新交付即换。
    public struct RecentDelivery: Equatable, Sendable {
        public let newestName: String
        public let extraCount: Int
        public let token: String

        public init(newestName: String, extraCount: Int, token: String) {
            self.newestName = newestName
            self.extraCount = extraCount
            self.token = token
        }
    }

    public var pendingApprovals: PendingApprovals?
    public var failedCronJob: FailedCronJob?
    public var blockedGoal: BlockedGoal?
    public var activeGoal: ActiveGoal?
    public var recentDelivery: RecentDelivery?
    /// 未来 24 小时内有定时任务要跑的个数，0＝无
    public var upcomingCronCount: Int
    /// 本地小时（0–23）；nil＝上下文整体未就绪（冷启
    /// 首帧、任一数据源都还没同步过），此时连时段条
    /// 也不出，整面回落冷启三条
    public var hour: Int?
    /// 已用/已弃且在抑制窗内的 key 集（装配侧由记账本
    /// 算好喂入，引擎只消费）
    public var suppressedKeys: Set<String>

    public init(
        pendingApprovals: PendingApprovals? = nil,
        failedCronJob: FailedCronJob? = nil,
        blockedGoal: BlockedGoal? = nil,
        activeGoal: ActiveGoal? = nil,
        recentDelivery: RecentDelivery? = nil,
        upcomingCronCount: Int = 0,
        hour: Int? = nil,
        suppressedKeys: Set<String> = []
    ) {
        self.pendingApprovals = pendingApprovals
        self.failedCronJob = failedCronJob
        self.blockedGoal = blockedGoal
        self.activeGoal = activeGoal
        self.recentDelivery = recentDelivery
        self.upcomingCronCount = upcomingCronCount
        self.hour = hour
        self.suppressedKeys = suppressedKeys
    }
}

/// 空态建议引擎（纯函数）：每次进空态以当下快照现算
/// 现排，最多三条。凑不满三条时用冷启池补位；连回落
/// 都被抑制时整池原样出——空态不许空白。
public enum StarterSuggestionsEngine {
    public static let maxCount = 3

    public static func suggestions(
        context: StarterContext
    ) -> [StarterSuggestion] {
        var picked: [StarterSuggestion] = []
        var seenTexts = Set<String>()

        func offer(_ suggestion: StarterSuggestion) {
            guard picked.count < maxCount else { return }
            guard !context.suppressedKeys.contains(suggestion.key)
            else { return }
            guard seenTexts.insert(suggestion.text).inserted
            else { return }
            picked.append(suggestion)
        }

        // 一级：需要处理（待批 > 定时异常 > 目标卡住）
        if let pending = context.pendingApprovals, pending.count > 0 {
            offer(StarterSuggestion(
                key: "approvals/\(pending.token)",
                text: "有 \(pending.count) 条请求等我批，帮我逐条看看都要批什么",
                symbol: "checkmark.shield",
                tier: .actionNeeded
            ))
        }
        if let job = context.failedCronJob {
            offer(StarterSuggestion(
                key: "cronFailed/\(job.id)/\(job.token)",
                text: "定时任务「\(job.name)」上次运行失败了，帮我看看是什么原因",
                symbol: "exclamationmark.triangle",
                tier: .actionNeeded
            ))
        }
        if let goal = context.blockedGoal {
            offer(StarterSuggestion(
                key: "goalBlocked/\(goal.id)/\(goal.token)",
                text: "目标「\(goal.title)」卡住了，帮我看看卡在哪一步、怎么往下推进",
                symbol: "flag",
                tier: .actionNeeded
            ))
        }

        // 二级：未完事项（在办目标 > 新交付 > 将跑的定时）
        if let goal = context.activeGoal {
            offer(StarterSuggestion(
                key: "goalActive/\(goal.id)",
                text: "目标「\(goal.title)」现在进展到哪了？",
                symbol: "target",
                tier: .unfinished
            ))
        }
        if let delivery = context.recentDelivery {
            let text = delivery.extraCount > 0
                ? "资源库最近新到了 \(delivery.extraCount + 1) 份交付物，帮我列一下都是什么"
                : "资源库里刚到的「\(delivery.newestName)」是什么？帮我看看"
            offer(StarterSuggestion(
                key: "delivery/\(delivery.token)",
                text: text,
                symbol: "tray.full",
                tier: .unfinished
            ))
        }
        if context.upcomingCronCount > 0 {
            offer(StarterSuggestion(
                key: "cronUpcoming",
                text: "接下来 24 小时有哪些定时任务要跑？帮我列一下",
                symbol: "clock",
                tier: .unfinished
            ))
        }

        // 三级：时段相关（至多一条）
        if let hour = context.hour,
           let time = timeSuggestion(hour: hour) {
            offer(time)
        }

        // 回落补位：真上下文凑不满三条时用冷启池填
        if picked.count < maxCount {
            for (index, text) in EmptyChatSuggestions.texts.enumerated() {
                guard picked.count < maxCount else { break }
                offer(StarterSuggestion(
                    key: "fallback/\(index)",
                    text: text,
                    symbol: EmptyChatSuggestions.symbols[index],
                    tier: .fallback
                ))
            }
        }

        // 极端情形：连回落都被抑制——不许空面，整池原样出
        if picked.isEmpty {
            return EmptyChatSuggestions.texts.enumerated().map {
                index, text in
                StarterSuggestion(
                    key: "fallback/\(index)",
                    text: text,
                    symbol: EmptyChatSuggestions.symbols[index],
                    tier: .fallback
                )
            }
        }
        return picked
    }

    /// 时段条：一句不编造事实的时段问句（只依赖钟点本身）
    static func timeSuggestion(hour: Int) -> StarterSuggestion? {
        switch hour {
        case 6..<11:
            return StarterSuggestion(
                key: "time/morning",
                text: "帮我过一遍今天的安排：日程、待办，还有在跑的任务",
                symbol: "sun.max",
                tier: .timeContext
            )
        case 11..<18:
            return StarterSuggestion(
                key: "time/day",
                text: "帮我看看手头在推进的几件事都到哪一步了",
                symbol: "clock",
                tier: .timeContext
            )
        case 18..<23:
            return StarterSuggestion(
                key: "time/evening",
                text: "帮我复盘一下今天，再看看明天有什么要提前准备的",
                symbol: "moon",
                tier: .timeContext
            )
        default:
            return StarterSuggestion(
                key: "time/night",
                text: "帮我看看还有什么没收尾的事",
                symbol: "moon.stars",
                tier: .timeContext
            )
        }
    }
}

/// 已用/已弃记账本（纯值，落盘归 App 侧）：key → 标记
/// （级＋时刻）。抑制窗按级分——状态类 7 天（其 key 带
/// 状态指纹，状态一变自动重装，窗长不敏感）；时段条
/// 20 小时（隔日可再出）；回落条 3 天。
public struct StarterSuggestionMarkBook: Codable, Equatable, Sendable {
    public struct Mark: Codable, Equatable, Sendable {
        public var tier: StarterSuggestionTier
        public var at: Date

        public init(tier: StarterSuggestionTier, at: Date) {
            self.tier = tier
            self.at = at
        }
    }

    public private(set) var used: [String: Mark] = [:]
    public private(set) var dismissed: [String: Mark] = [:]

    public init() {}

    public static func window(
        for tier: StarterSuggestionTier
    ) -> TimeInterval {
        switch tier {
        case .actionNeeded, .unfinished: return 7 * 24 * 3600
        case .timeContext: return 20 * 3600
        case .fallback: return 3 * 24 * 3600
        }
    }

    public mutating func markUsed(
        key: String, tier: StarterSuggestionTier, at: Date
    ) {
        used[key] = Mark(tier: tier, at: at)
    }

    public mutating func markDismissed(
        key: String, tier: StarterSuggestionTier, at: Date
    ) {
        dismissed[key] = Mark(tier: tier, at: at)
    }

    /// 当下仍在抑制窗内的 key 集（用过与弃过同等对待）
    public func suppressedKeys(now: Date) -> Set<String> {
        var keys = Set<String>()
        for (key, mark) in used
        where now.timeIntervalSince(mark.at) < Self.window(for: mark.tier) {
            keys.insert(key)
        }
        for (key, mark) in dismissed
        where now.timeIntervalSince(mark.at) < Self.window(for: mark.tier) {
            keys.insert(key)
        }
        return keys
    }

    /// 清掉已过窗的旧标记（落盘前顺手做，账本不膨胀）
    public mutating func prune(now: Date) {
        used = used.filter {
            now.timeIntervalSince($0.value.at)
                < Self.window(for: $0.value.tier)
        }
        dismissed = dismissed.filter {
            now.timeIntervalSince($0.value.at)
                < Self.window(for: $0.value.tier)
        }
    }
}
