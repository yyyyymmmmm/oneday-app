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

    /// 行首 emoji 缺省（0.47.0，§117）：桥帖带 emoji
    /// 时用桥值；旧帖无值按 kind 回本表
    public var fallbackEmoji: String {
        switch self {
        case .morning: return "🌅"
        case .research: return "🔍"
        case .digest: return "📰"
        case .unknown: return "📰"
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
    /// 行首内容 emoji（0.47.0，§117）：research 由桥
    /// 按主题选定、digest 固定 📰；旧帖为 nil，呈现
    /// 走 kind 缺省（displayEmoji）
    public let emoji: String?
    /// epoch 秒（float）
    public let createdAt: Double
    public let expiresAt: Double?
    /// 已读时刻；nil＝未读
    public let readAt: Double?

    public var isRead: Bool { readAt != nil }

    /// 行首 emoji 呈现值：桥值优先、kind 缺省兜底
    public var displayEmoji: String {
        if let emoji {
            let trimmed = emoji.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return kind.fallbackEmoji
    }

    public init(
        id: String, kind: FeedPostKind, title: String,
        body: String, refs: [BridgeFeedRef] = [],
        links: [BridgeFeedLink] = [], why: String? = nil,
        images: [BridgeFeedImage] = [],
        sourceCard: BridgeFeedSourceCard? = nil,
        direction: String? = nil,
        createdAt: Double, expiresAt: Double? = nil,
        readAt: Double? = nil, emoji: String? = nil
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
        self.emoji = emoji
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
            readAt: ts, emoji: emoji
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, body, refs, links, why
        case images, sourceCard, direction
        case createdAt, expiresAt, readAt, emoji
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
        emoji = try container.decodeIfPresent(
            String.self, forKey: .emoji
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
        calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> [DayGroup] {
        var groups: [DayGroup] = []
        for post in posts {
            let date = Date(timeIntervalSince1970: post.createdAt)
            let title = groupTitle(for: date, now: now, calendar: calendar, locale: locale)
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
        for date: Date, now: Date, calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        // 0.42.0：档位不变，文案走 DisplayDate 同源格
        // 式器与目录取词（未来侧恒「今天」，与
        // DisplayDate.dateOnly 的明天档分工不变）
        let dayDiff = DisplayDate.dayDifference(of: date, now: now, calendar: calendar)
        switch dayDiff {
        case ..<1:
            return L10n.string("今天", locale: locale)
        case 1:
            return L10n.string("昨天", locale: locale)
        case 2...6:
            return DisplayDate.weekdayText(of: date, calendar: calendar, locale: locale)
        default:
            return DisplayDate.absoluteDate(of: date, now: now, calendar: calendar, locale: locale)
        }
    }

    /// 动作行相对时间（对标 Muse 动态：7分钟/1小时
    /// 式；过日界走日期口径，与 ChatTimeline 五档同族）
    public static func relativeText(
        for ts: Double, now: Date, calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        // 0.42.0：分/时紧凑档走目录模板（"%@分钟"/
        // "%@小时"），过日界各档与 ChatTimeline 同源
        let date = Date(timeIntervalSince1970: ts)
        let diff = now.timeIntervalSince(date)
        if diff < 60 {
            return L10n.string("刚刚", locale: locale)
        }
        let dayDiff = DisplayDate.dayDifference(of: date, now: now, calendar: calendar)
        if dayDiff <= 0 {
            if diff < 3600 {
                return L10n.format("%@分钟", locale: locale, String(Int(diff / 60)))
            }
            return L10n.format("%@小时", locale: locale, String(Int(diff / 3600)))
        }
        let time = DisplayDate.timeText(of: date, calendar: calendar, locale: locale)
        switch dayDiff {
        case 1:
            return L10n.format("昨天 %@", locale: locale, time)
        case 2...6:
            let weekday = DisplayDate.weekdayText(of: date, calendar: calendar, locale: locale)
            return "\(weekday) \(time)"
        default:
            let absolute = DisplayDate.absoluteDate(of: date, now: now, calendar: calendar, locale: locale)
            return "\(absolute) \(time)"
        }
    }

    public static func unreadCount(_ posts: [BridgeFeedPost]) -> Int {
        posts.count { !$0.isRead }
    }

    /// 列表顶部避让政策（§126）：顶距只为
    /// 「真的有浮层压在列表顶部」而存在——无重叠
    /// （overlayHeight 为 nil 或 ≤0）恒 0，不许留一
    /// 个无条件小数字冒充条件化（§122 的无条件
    /// 64pt 即此病：胶囊不在场也照收、压出死空）；
    /// 真重叠时＝实测重叠高度＋gap（视图侧传令牌
    /// spacingS）。重叠高度必须由浮层的宿主实测喂
    /// 入，不许在列表侧反推或写死
    public static func topClearance(
        overlayHeight: CGFloat?, gap: CGFloat
    ) -> CGFloat {
        guard let overlayHeight, overlayHeight > 0 else { return 0 }
        return overlayHeight + gap
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

    /// 列表行正文呈现判定（0.47.0，§117）：行内恒渲
    /// 全文——用户口径「动态的内容不需要点开」，行内
    /// 截断自本包退役；本函数是该口径的唯一开关位，
    /// 将来若给长帖加「收起」只许在此收口
    /// 0.48.0（§122，用户 12:41/12:45 对尺改判）：短帖
    /// 仍全文内联不变；长帖（超 rowBodyCharacterLimit）
    /// 改句界截断＋「展开全文」进详情——本函数口径随
    /// 之改为「本帖在行内是否全文」，判定与截断点统
    /// 一走 rowBodyPresentation，不许在视图侧另算
    public static func rowShowsFullBody(_ post: BridgeFeedPost) -> Bool {
        !rowBodyPresentation(post.body).isTruncated
    }

    /// 行内正文上限（字符数，§122 定版）：对尺 Muse
    /// 动态帖正文约 80–150 字全文铺——本阈值只作安全
    /// 网（源头长度由桥侧生成面收紧），约当两倍余量；
    /// 超限才截，阈值内一字不动
    public static let rowBodyCharacterLimit = 300

    /// 行内正文呈现：全文或截断稿（截断稿止于句界、
    /// 视图在其后挂「展开全文」入口进详情看全文）
    public struct RowBodyPresentation: Equatable, Sendable {
        public let text: String
        public let isTruncated: Bool

        public init(text: String, isTruncated: Bool) {
            self.text = text
            self.isTruncated = isTruncated
        }
    }

    /// 行内正文截断（§122）：全文 Character 计数（多
    /// 字节/emoji 安全）≤上限即原样；超限时在上限内找
    /// 最后一个完整句界（。！？及后随空白的 .!?；与
    /// 段落换行）截断——句界须落在上限后半段才采用
    /// （太靠前的句界截完近乎空行，不如硬截），无合
    /// 格句界则硬截上限字数＋省略号。截点若落在未闭
    /// 合的代码围栏（```）内，回退到围栏开始之前，
    /// 防半截围栏把余下全文染成代码块
    public static func rowBodyPresentation(
        _ body: String
    ) -> RowBodyPresentation {
        guard body.count > rowBodyCharacterLimit else {
            return RowBodyPresentation(text: body, isTruncated: false)
        }
        let limit = rowBodyCharacterLimit
        let head = String(body.prefix(limit))
        // 句界以字符偏移计（全文同一索引空间，不混用
        // 前缀串的下标）：合格句界截断、无则硬截
        var cutOffset: Int?
        if let boundary = lastSentenceBoundary(in: body, limit: limit),
           boundary >= limit / 2 {
            cutOffset = boundary
        }
        var kept = cutOffset.map { String(body.prefix($0)) } ?? head
        // 围栏守卫：保留段内 ``` 奇数个＝截在围栏里
        let fenceCount = kept.components(separatedBy: "```").count - 1
        if fenceCount % 2 == 1,
           let fenceStart = kept.range(of: "```", options: .backwards) {
            kept = String(kept[..<fenceStart.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if kept.isEmpty {
                kept = head
            }
        }
        if cutOffset != nil {
            return RowBodyPresentation(text: kept, isTruncated: true)
        }
        return RowBodyPresentation(
            text: kept + "…", isTruncated: true
        )
    }

    /// 句界扫描：返回上限内最后一个句末的保留字符数
    /// （句末标点及其后紧随的收尾引号/括号一并保留）；
    /// ASCII 标点须后随空白/换行/收尾符才算句界（防
    /// 0.47、域名里的小数点与点号误判，后随字符看到
    /// 上限外一字）；换行本身作段落界（保留数止于其前）
    private static func lastSentenceBoundary(
        in body: String, limit: Int
    ) -> Int? {
        let closers: Set<Character> = [
            "」", "』", "”", "’", "）", ")", "】", "]", "》",
        ]
        let chars = Array(body.prefix(limit + 1))
        var boundary: Int?
        var i = 0
        while i < limit, i < chars.count {
            let ch = chars[i]
            if ch == "\n" {
                boundary = i
                i += 1
                continue
            }
            let isCJKStop = "。！？；".contains(ch)
            var isASCIIStop = false
            if ".!?;".contains(ch), i + 1 < chars.count {
                let nc = chars[i + 1]
                isASCIIStop = nc == " " || nc == "\n"
                    || nc == "\t" || closers.contains(nc)
            }
            if isCJKStop || isASCIIStop {
                var end = i + 1
                while end < limit, end < chars.count,
                      closers.contains(chars[end]) {
                    end += 1
                }
                boundary = end
            }
            i += 1
        }
        return boundary
    }

    /// 正文摘（0.47.0 起行内退役）：剥 Markdown 结构
    /// 符后压平空白、截断——只余胶囊/通知一类真摘要
    /// 位可用，帖行不许再走它
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
}
