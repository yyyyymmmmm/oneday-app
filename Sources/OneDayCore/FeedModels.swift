import Foundation

// MARK: - 动态帖（P3，oneday-bridge /feed 契约）

/// 帖子类别：digest＝段一确定性汇编（当日真实事件），
/// morning＝段二旧晨报（0.38.0 前，只读呈现），
/// research＝段二调研帖（0.38.0 起，简报驱动的外网
/// 调研五步链产出）。未知值按 unknown 收，呈现走
/// 通用形态、不猜。
public enum FeedPostKind: String, Sendable {
    case digest
    case morning
    case research
    case unknown

    public static func from(_ raw: String?) -> FeedPostKind {
        FeedPostKind(rawValue: raw ?? "") ?? .unknown
    }

    /// kind 瓷砖符号（SF Symbol outline 原名，设计档
    /// §3.4 落点：晨报＝日出；汇编帖取报纸形态；
    /// 调研帖取放大镜）
    public var symbolName: String {
        switch self {
        case .morning: return "sunrise"
        case .research: return "magnifyingglass"
        case .digest: return "doc.text"
        case .unknown: return "doc.text"
        }
    }

    public var label: String {
        switch self {
        case .morning: return "晨报"
        case .research: return "调研"
        case .digest: return "今日动态"
        case .unknown: return "动态"
        }
    }
}

/// 引用对象类别（桥侧落库前逐个验存在，假引用整帖
/// 不落；客户端只呈现认识的类别）
public enum FeedRefType: String, Sendable {
    case idea
    case goal
    case task
    case monitor
    case briefing

    public static func from(_ raw: String?) -> FeedRefType? {
        FeedRefType(rawValue: raw ?? "")
    }

    public var symbolName: String {
        switch self {
        case .idea: return "lightbulb"
        case .goal: return "checklist"
        case .task: return "checkmark.circle"
        case .monitor: return "antenna.radiowaves.left.and.right"
        case .briefing: return "envelope"
        }
    }

    public var label: String {
        switch self {
        case .idea: return "点子"
        case .goal: return "目标"
        case .task: return "任务"
        case .monitor: return "监测"
        case .briefing: return "简报"
        }
    }
}

/// 帖子引用：{type, id}；简报类另带 goalId（桥读时
/// 富化，App 点达所属目标的简报区，不靠猜）
public struct BridgeFeedRef: Decodable, Equatable, Hashable, Sendable {
    public let type: String
    public let id: String
    public let goalId: String?

    public var refType: FeedRefType? { FeedRefType.from(type) }

    public init(type: String, id: String, goalId: String? = nil) {
        self.type = type
        self.id = id
        self.goalId = goalId
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, goalId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(
            String.self, forKey: .type
        ) ?? ""
        id = try container.decodeIfPresent(
            String.self, forKey: .id
        ) ?? ""
        goalId = try container.decodeIfPresent(
            String.self, forKey: .goalId
        )
    }
}

/// 晨报帖的外部链接（只许调研真返，桥侧已滤协议）
public struct BridgeFeedLink: Decodable, Equatable, Sendable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case title, url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(
            String.self, forKey: .title
        ) ?? ""
        url = try container.decodeIfPresent(
            String.self, forKey: .url
        ) ?? ""
    }
}

/// 调研帖配图：只来自来源页真图（桥侧深读抽取＋可达
/// 性校验后才落库）；sourceUrl＝这张图出自哪篇来源
public struct BridgeFeedImage: Decodable, Equatable, Sendable {
    public let url: String
    public let sourceUrl: String

    public init(url: String, sourceUrl: String) {
        self.url = url
        self.sourceUrl = sourceUrl
    }

    private enum CodingKeys: String, CodingKey {
        case url, sourceUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(
            String.self, forKey: .url
        ) ?? ""
        sourceUrl = try container.decodeIfPresent(
            String.self, forKey: .sourceUrl
        ) ?? ""
    }
}

/// 来源嵌入卡的一条事实（如仓库卡的星标数）
public struct BridgeFeedCardFact: Decodable, Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case label, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(
            String.self, forKey: .label
        ) ?? ""
        value = try container.decodeIfPresent(
            String.self, forKey: .value
        ) ?? ""
    }
}

/// 来源嵌入卡（0.38.0）：数据与图均自来源真抓（如
/// GitHub 仓库卡＝仓库接口原样字段）；桥抓不到就不
/// 带卡，App 不自拼、不假造
public struct BridgeFeedSourceCard: Decodable, Equatable, Sendable {
    public let kind: String
    public let name: String
    public let description: String
    public let url: String
    public let imageUrl: String?
    public let facts: [BridgeFeedCardFact]

    public init(
        kind: String, name: String, description: String,
        url: String, imageUrl: String? = nil,
        facts: [BridgeFeedCardFact] = []
    ) {
        self.kind = kind
        self.name = name
        self.description = description
        self.url = url
        self.imageUrl = imageUrl
        self.facts = facts
    }

    private enum CodingKeys: String, CodingKey {
        case kind, name, description, url, imageUrl, facts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(
            String.self, forKey: .kind
        ) ?? ""
        name = try container.decodeIfPresent(
            String.self, forKey: .name
        ) ?? ""
        description = try container.decodeIfPresent(
            String.self, forKey: .description
        ) ?? ""
        url = try container.decodeIfPresent(
            String.self, forKey: .url
        ) ?? ""
        imageUrl = try container.decodeIfPresent(
            String.self, forKey: .imageUrl
        )
        facts = try container.decodeIfPresent(
            [BridgeFeedCardFact].self, forKey: .facts
        ) ?? []
    }
}

/// 一篇动态帖（桥 feedPosts 的读视图）：已读以服务
/// 端 readAt 为真源；expiresAt 过期帖桥端列表不回。
public struct BridgeFeedPost: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: FeedPostKind
    public let title: String
    /// 正文（Markdown）
    public let body: String
    public let refs: [BridgeFeedRef]
    public let links: [BridgeFeedLink]
    /// 「为什么选这篇」（晨报/调研帖才有）
    public let why: String?
    /// 配图（调研帖才有；只含来源页真图）
    public let images: [BridgeFeedImage]
    /// 来源嵌入卡（调研帖可选）
    public let sourceCard: BridgeFeedSourceCard?
    /// 所属简报方向名（调研帖才有）
    public let direction: String?
    /// epoch 秒（float）
    public let createdAt: Double
    public let expiresAt: Double?
    /// 已读时刻；nil＝未读
    public let readAt: Double?

    public var isRead: Bool { readAt != nil }

    public init(
        id: String, kind: FeedPostKind, title: String,
        body: String, refs: [BridgeFeedRef] = [],
        links: [BridgeFeedLink] = [], why: String? = nil,
        images: [BridgeFeedImage] = [],
        sourceCard: BridgeFeedSourceCard? = nil,
        direction: String? = nil,
        createdAt: Double, expiresAt: Double? = nil,
        readAt: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.refs = refs
        self.links = links
        self.why = why
        self.images = images
        self.sourceCard = sourceCard
        self.direction = direction
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.readAt = readAt
    }

    /// 本地已读副本（回执到达前的呈现不回退用；真源
    /// 仍是服务端回执，FeedStore 以回执为准对账）
    public func markedRead(at ts: Double) -> BridgeFeedPost {
        BridgeFeedPost(
            id: id, kind: kind, title: title, body: body,
            refs: refs, links: links, why: why,
            images: images, sourceCard: sourceCard,
            direction: direction,
            createdAt: createdAt, expiresAt: expiresAt,
            readAt: ts
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, body, refs, links, why
        case images, sourceCard, direction
        case createdAt, expiresAt, readAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = FeedPostKind.from(
            try container.decodeIfPresent(String.self, forKey: .kind)
        )
        title = try container.decodeIfPresent(
            String.self, forKey: .title
        ) ?? ""
        body = try container.decodeIfPresent(
            String.self, forKey: .body
        ) ?? ""
        refs = try container.decodeIfPresent(
            [BridgeFeedRef].self, forKey: .refs
        ) ?? []
        links = try container.decodeIfPresent(
            [BridgeFeedLink].self, forKey: .links
        ) ?? []
        why = try container.decodeIfPresent(String.self, forKey: .why)
        images = try container.decodeIfPresent(
            [BridgeFeedImage].self, forKey: .images
        ) ?? []
        sourceCard = try container.decodeIfPresent(
            BridgeFeedSourceCard.self, forKey: .sourceCard
        )
        direction = try container.decodeIfPresent(
            String.self, forKey: .direction
        )
        createdAt = try container.decodeIfPresent(
            Double.self, forKey: .createdAt
        ) ?? 0
        expiresAt = try container.decodeIfPresent(
            Double.self, forKey: .expiresAt
        )
        readAt = try container.decodeIfPresent(
            Double.self, forKey: .readAt
        )
    }
}

public struct BridgeFeedPostsResponse: Decodable, Sendable {
    public let items: [BridgeFeedPost]
}

// MARK: - 生成账面（GET /feed/generation）

/// 段一汇编账面：今日事件数与轮询通道状态（通道注记
/// 只供诊断呈现，不编事件）
public struct BridgeFeedAssembly: Decodable, Equatable, Sendable {
    public let date: String?
    public let digestPostId: String?
    public let eventsToday: Int
    public let lastAssemblyAt: Double?
    public let kanbanNote: String?
    public let approvalTotal: Int?
    public let approvalsNote: String?

    private enum CodingKeys: String, CodingKey {
        case date, digestPostId, eventsToday, lastAssemblyAt
        case kanbanNote, approvalTotal, approvalsNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(
            String.self, forKey: .date
        )
        digestPostId = try container.decodeIfPresent(
            String.self, forKey: .digestPostId
        )
        eventsToday = try container.decodeIfPresent(
            Int.self, forKey: .eventsToday
        ) ?? 0
        lastAssemblyAt = try container.decodeIfPresent(
            Double.self, forKey: .lastAssemblyAt
        )
        kanbanNote = try container.decodeIfPresent(
            String.self, forKey: .kanbanNote
        )
        approvalTotal = try container.decodeIfPresent(
            Int.self, forKey: .approvalTotal
        )
        approvalsNote = try container.decodeIfPresent(
            String.self, forKey: .approvalsNote
        )
    }

    public init(
        date: String?, digestPostId: String?, eventsToday: Int,
        lastAssemblyAt: Double?, kanbanNote: String?,
        approvalTotal: Int?, approvalsNote: String?
    ) {
        self.date = date
        self.digestPostId = digestPostId
        self.eventsToday = eventsToday
        self.lastAssemblyAt = lastAssemblyAt
        self.kanbanNote = kanbanNote
        self.approvalTotal = approvalTotal
        self.approvalsNote = approvalsNote
    }
}

/// 动态账面全形：段一汇编＋段二账面（与点子生成账
/// 面同形 BridgeGenerationInfo）＋未读数。段二账面
/// 桥侧双键同指一份：morning＝0.38.0 前的键名（兼容
/// 旧读法），research＝0.38.0 起的正名；解码两键都
/// 收，新代码读 research，缺 research 时回落 morning
public struct BridgeFeedGeneration: Decodable, Equatable, Sendable {
    public let assembly: BridgeFeedAssembly?
    public let morning: BridgeGenerationInfo?
    public let research: BridgeGenerationInfo?
    public let unread: Int

    /// 段二账面正读口径：research 优先、morning 兜底
    public var segmentTwo: BridgeGenerationInfo? {
        research ?? morning
    }

    private enum CodingKeys: String, CodingKey {
        case assembly, morning, research, unread
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assembly = try container.decodeIfPresent(
            BridgeFeedAssembly.self, forKey: .assembly
        )
        morning = try container.decodeIfPresent(
            BridgeGenerationInfo.self, forKey: .morning
        )
        research = try container.decodeIfPresent(
            BridgeGenerationInfo.self, forKey: .research
        )
        unread = try container.decodeIfPresent(
            Int.self, forKey: .unread
        ) ?? 0
    }

    public init(
        assembly: BridgeFeedAssembly?,
        morning: BridgeGenerationInfo?,
        research: BridgeGenerationInfo? = nil, unread: Int
    ) {
        self.assembly = assembly
        self.morning = morning
        self.research = research
        self.unread = unread
    }
}

// MARK: - 动态页呈现口径（P3，设计档第三章）

public enum FeedBoard {
    /// 列表排序：发布时间倒序（设计档定版：有用度
    /// 排序缓办）；同刻以 id 定序，保证稳定
    public static func sorted(_ posts: [BridgeFeedPost]) -> [BridgeFeedPost] {
        posts.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.id > $1.id
        }
    }

    public struct DayGroup: Equatable {
        public let title: String
        public let posts: [BridgeFeedPost]

        public init(title: String, posts: [BridgeFeedPost]) {
            self.title = title
            self.posts = posts
        }
    }

    /// 按日分组（入参须已倒序）：组头口径与聊天时间
    /// 系统同族（今天/昨天/星期X/本年 M月d日/跨年
    /// yyyy年M月d日），只到日、不带时刻
    public static func dayGroups(
        _ posts: [BridgeFeedPost], now: Date,
        calendar: Calendar = .current
    ) -> [DayGroup] {
        var groups: [DayGroup] = []
        for post in posts {
            let date = Date(timeIntervalSince1970: post.createdAt)
            let title = groupTitle(for: date, now: now, calendar: calendar)
            if var last = groups.last, last.title == title {
                last = DayGroup(
                    title: last.title, posts: last.posts + [post]
                )
                groups[groups.count - 1] = last
            } else {
                groups.append(DayGroup(title: title, posts: [post]))
            }
        }
        return groups
    }

    public static func groupTitle(
        for date: Date, now: Date, calendar: Calendar = .current
    ) -> String {
        let dayDiff = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? Int.max
        switch dayDiff {
        case ..<1:
            return "今天"
        case 1:
            return "昨天"
        case 2...6:
            return weekdayText(for: date, calendar: calendar)
        default:
            let parts = calendar.dateComponents(
                [.year, .month, .day], from: date
            )
            guard let year = parts.year, let month = parts.month,
                  let day = parts.day else { return "" }
            if year == calendar.component(.year, from: now) {
                return "\(month)月\(day)日"
            }
            return "\(year)年\(month)月\(day)日"
        }
    }

    /// 动作行相对时间（对标 Muse 动态：7分钟/1小时
    /// 式；过日界走日期口径，与 ChatTimeline 五档同族）
    public static func relativeText(
        for ts: Double, now: Date, calendar: Calendar = .current
    ) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let diff = now.timeIntervalSince(date)
        if diff < 60 {
            return "刚刚"
        }
        let dayDiff = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? Int.max
        if dayDiff <= 0 {
            if diff < 3600 {
                return "\(Int(diff / 60))分钟"
            }
            return "\(Int(diff / 3600))小时"
        }
        let time = timeText(for: date, calendar: calendar)
        switch dayDiff {
        case 1:
            return "昨天 \(time)"
        case 2...6:
            return "\(weekdayText(for: date, calendar: calendar)) \(time)"
        default:
            let parts = calendar.dateComponents(
                [.year, .month, .day], from: date
            )
            guard let year = parts.year, let month = parts.month,
                  let day = parts.day else { return time }
            if year == calendar.component(.year, from: now) {
                return "\(month)月\(day)日 \(time)"
            }
            return "\(year)年\(month)月\(day)日 \(time)"
        }
    }

    public static func unreadCount(_ posts: [BridgeFeedPost]) -> Int {
        posts.count { !$0.isRead }
    }

    /// 简报胶囊落点：今日汇编帖优先，其次今日晨报，
    /// 再其次最近未读，最后最近一篇（全读时胶囊仍
    /// 指最新动态）；无帖为 nil（胶囊显「今日暂无」）
    public static func capsulePost(
        _ posts: [BridgeFeedPost], now: Date,
        calendar: Calendar = .current
    ) -> BridgeFeedPost? {
        let ordered = sorted(posts)
        let todayStart = calendar.startOfDay(for: now)
        let todays = ordered.filter {
            Date(timeIntervalSince1970: $0.createdAt) >= todayStart
        }
        if let digest = todays.first(where: { $0.kind == .digest }) {
            return digest
        }
        if let morning = todays.first(where: { $0.kind == .morning }) {
            return morning
        }
        if let unread = ordered.first(where: { !$0.isRead }) {
            return unread
        }
        return ordered.first
    }

    public enum EmptyKind: Equatable {
        /// 从未产出（无晨报记录、今日零事件）
        case neverProduced
        /// 产过但当前列表为空（过期/已清/今日无素材）
        case quiet
    }

    public static func emptyKind(
        hasAnyPost: Bool, morningLastRunAt: Double?,
        eventsToday: Int
    ) -> EmptyKind {
        if !hasAnyPost, morningLastRunAt == nil, eventsToday == 0 {
            return .neverProduced
        }
        return .quiet
    }

    /// 列表行正文摘：剥 Markdown 结构符（标题/列表/
    /// 引用/强调）后压平空白、截断——摘只供行内预览，
    /// 详情页渲染原文
    public static func excerpt(_ body: String, maxLength: Int = 120) -> String {
        var text = body
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            while line.hasPrefix("#") || line.hasPrefix("-")
                    || line.hasPrefix(">") {
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespaces)
            }
            line = line.replacingOccurrences(of: "**", with: "")
            line = line.replacingOccurrences(of: "`", with: "")
            if !line.isEmpty {
                lines.append(line)
            }
        }
        let flat = lines.joined(separator: " ")
        if flat.count <= maxLength {
            return flat
        }
        return String(flat.prefix(maxLength)) + "…"
    }

    private static func timeText(for date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    private static let weekdayNames = [
        "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六",
    ]

    private static func weekdayText(
        for date: Date, calendar: Calendar
    ) -> String {
        let weekday = calendar.component(.weekday, from: date)
        guard (1...7).contains(weekday) else { return "" }
        return weekdayNames[weekday - 1]
    }
}
