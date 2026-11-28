import Foundation

/// 工作台账呈现口径（规格 work-ledger-design-
/// 20261110.md §2.5/§3/§4）：人话映射、已耗时格
/// 式、新鲜度分档、增量合并、按天分组、页首计数与
/// 行副题——全部纯函数收口于此，视图只渲染。状态
/// 文案零行话：原始枚举只许进下钻详情的「技术信
/// 息」区，列表与副题一律走本文件的人话。

// MARK: - 人话映射（单点维护）

public enum LedgerText {
    /// 七态人话（规格 §3.1 的界面词）
    public static func statusWord(
        _ status: LedgerStatus, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch status {
        case .queued: return L10n.string("排队中", locale: locale)
        case .running: return L10n.string("进行中", locale: locale)
        case .blockedApproval: return L10n.string("等待审批", locale: locale)
        case .completed: return L10n.string("已完成", locale: locale)
        case .failed: return L10n.string("失败", locale: locale)
        case .cancelled: return L10n.string("已取消", locale: locale)
        case .stale: return L10n.string("失联待核", locale: locale)
        case .other: return L10n.string("状态未知", locale: locale)
        }
    }

    /// 类别人话（详情面用）
    public static func kindWord(
        _ kind: LedgerKind, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch kind {
        case .run: return L10n.string("对话运行", locale: locale)
        case .kanban: return L10n.string("看板任务", locale: locale)
        case .job: return L10n.string("定时作业", locale: locale)
        case .approval: return L10n.string("审批", locale: locale)
        case .device: return L10n.string("设备调用", locale: locale)
        case .monitor: return L10n.string("监测", locale: locale)
        case .other(let raw):
            return raw.isEmpty ? L10n.string("其他", locale: locale) : raw
        }
    }

    /// 来源人话（与现行活动段来源标同族口径）
    public static func sourceWord(
        _ source: LedgerSource, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch source {
        case .app: return L10n.string("OneDay 发起", locale: locale)
        case .dashboard: return L10n.string("控制台", locale: locale)
        case .cron: return L10n.string("定时任务", locale: locale)
        case .api: return L10n.string("其他应用", locale: locale)
        case .bridge: return L10n.string("自动作业", locale: locale)
        case .device: return L10n.string("设备", locale: locale)
        case .other(let raw):
            // 2.23.0 起回合记录的来源词（gateway＝网关
            // 边界直记、server＝服务端观察）不在枚举内，
            // 不许原文出用户面：两者都是对话里的回合
            switch raw {
            case "gateway", "server":
                return L10n.string("对话", locale: locale)
            default:
                return raw.isEmpty ? L10n.string("其他来源", locale: locale) : raw
            }
        }
    }

    /// 记账来源人话（origin 诚实位，详情可见；列表面
    /// 的「补记」小标判据在 LedgerItem.isReconciled）
    public static func originWord(
        _ raw: String, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch raw {
        case "reported": return L10n.string("实时上报", locale: locale)
        case "bridge_self": return L10n.string("自动记录", locale: locale)
        case "reconciled": return L10n.string("补记", locale: locale)
        default: return raw.isEmpty ? "—" : raw
        }
    }

    /// 标题来源人话（防编造审计位，详情可见）
    public static func titleSourceWord(
        _ raw: String, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch raw {
        case "server_llm": return L10n.string("智能标题", locale: locale)
        case "user_excerpt": return L10n.string("你的原话", locale: locale)
        case "job_name": return L10n.string("作业名称", locale: locale)
        case "task_title": return L10n.string("任务原题", locale: locale)
        case "record_excerpt": return L10n.string("记录摘要", locale: locale)
        case "fallback": return L10n.string("自动命名", locale: locale)
        default: return raw.isEmpty ? "—" : raw
        }
    }

    /// 流水记录者人话（history.by）
    public static func actorWord(
        _ raw: String?, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch raw {
        case "app": return L10n.string("App 上报", locale: locale)
        case "collector": return L10n.string("对账", locale: locale)
        case "bridge": return L10n.string("自动作业", locale: locale)
        case "gateway": return L10n.string("网关", locale: locale)
        case "server": return L10n.string("服务端", locale: locale)
        default: return raw ?? L10n.string("系统", locale: locale)
        }
    }
}

// MARK: - 已耗时

public enum LedgerElapsed {
    /// 已耗时格式（规格 §4.1）：<1 小时 M:SS（2:13），
    /// ≥1 小时 H:MM:SS（1:02:13）；负值归 0。tabular
    /// 呈现由视图字体承担，本处只管位数口径
    public static func format(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        if total < 3600 {
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        return String(
            format: "%d:%02d:%02d",
            total / 3600, (total % 3600) / 60, total % 60
        )
    }

    /// 已流逝秒数（服务端时刻同轴相减，负值归 0）
    public static func elapsed(
        startedAt: Double, serverNow: Double
    ) -> Double {
        max(0, serverNow - startedAt)
    }
}

// MARK: - 新鲜度（§2.5）

/// 台账新鲜度三档：心跳龄 ≤30 秒＝实时（不标注）；
/// 30 秒–5 分钟＝迟滞（弱标注「台账更新于…」）；
/// >5 分钟或无心跳＝停更（顶部明示，旧数据降陈旧
/// 呈现）。采集器死了与桥断了是两种状态：本档只管
/// 「桥在、心跳老」，断桥由拉取失败单独露面
public enum LedgerFreshness: Equatable, Sendable {
    case live
    case lagging
    case stalled

    public static func evaluate(heartbeatAge: Double?) -> LedgerFreshness {
        guard let age = heartbeatAge else { return .stalled }
        if age <= 30 { return .live }
        if age <= 300 { return .lagging }
        return .stalled
    }

    /// 新鲜度标注文案（live 无标注）；时刻取台账最后
    /// 入账时刻，缺失时只给状态词不编时刻
    public func note(
        ledgerUpdatedAt: Double?, calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String? {
        switch self {
        case .live:
            return nil
        case .lagging:
            guard let at = ledgerUpdatedAt else {
                return L10n.string("台账更新稍有延迟", locale: locale)
            }
            return L10n.format(
                "台账更新于 %@", locale: locale,
                LedgerClock.time(at, calendar: calendar)
            )
        case .stalled:
            guard let at = ledgerUpdatedAt else {
                return L10n.string("台账已停更", locale: locale)
            }
            return L10n.format(
                "台账已停更 · 最后更新 %@", locale: locale,
                LedgerClock.time(at, calendar: calendar)
            )
        }
    }
}

/// 台账专用钟面格式（HH:mm／HH:mm:ss，数字 POSIX
/// 口径不随地区变体漂移；日历时区随入参）
public enum LedgerClock {
    private final class FormatterCache: @unchecked Sendable {
        let lock = NSLock()
        var formatters: [String: DateFormatter] = [:]
    }
    private static let cache = FormatterCache()

    public static func time(
        _ epoch: Double, calendar: Calendar = .current
    ) -> String {
        formattedString(
            Date(timeIntervalSince1970: epoch),
            format: "HH:mm",
            calendar: calendar
        )
    }

    public static func timeWithSeconds(
        _ epoch: Double, calendar: Calendar = .current
    ) -> String {
        formattedString(
            Date(timeIntervalSince1970: epoch),
            format: "HH:mm:ss",
            calendar: calendar
        )
    }

    private static func formattedString(
        _ date: Date, format: String, calendar: Calendar
    ) -> String {
        let key = "\(format)|\(calendar.timeZone.identifier)"
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let existing = cache.formatters[key] {
            return existing.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        cache.formatters[key] = formatter
        return formatter.string(from: date)
    }
}

// MARK: - 合并与排序

public enum LedgerMerge {
    /// 列表定序：开始时刻倒序，同刻以 id 兜底稳定序
    public static func sorted(_ items: [LedgerItem]) -> [LedgerItem] {
        items.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.id < rhs.id
        }
    }

    /// 增量合并（?since 回执只含变更条目）：按 id 替
    /// 换旧条、插入新条、未变更条目原样保留，结果重
    /// 排定序。条目消失（桥侧压实清理）靠整页重拉对
    /// 账，不在本函数处理——增量面看不见删除是契约
    /// 本性，不许假装
    public static func merge(
        existing: [LedgerItem], changes: [LedgerItem]
    ) -> [LedgerItem] {
        guard !changes.isEmpty else { return existing }
        var byID: [String: LedgerItem] = [:]
        for item in existing { byID[item.id] = item }
        for item in changes { byID[item.id] = item }
        return sorted(Array(byID.values))
    }
}

// MARK: - 分组／页首／副题

public struct LedgerDayGroup: Equatable, Identifiable {
    public let title: String
    public let items: [LedgerItem]

    public var id: String { title }

    public init(title: String, items: [LedgerItem]) {
        self.title = title
        self.items = items
    }
}

/// 会话聚合行（§477）：一个会话在列表里的一行——
/// 代表条目（最近一次运行）供标题/状态/下钻，成员
/// 全集供计数与聚焦命中判定
public struct LedgerSessionGroup: Equatable, Sendable, Identifiable {
    public let representative: LedgerItem
    public let members: [LedgerItem]

    public var id: String { representative.id }
    public var count: Int { members.count }

    public init(representative: LedgerItem, members: [LedgerItem]) {
        self.representative = representative
        self.members = members
    }
}

/// 台账行三段派生（§344）：中段副题（状态词＋非时
/// 间信息）、右段 trailing（时刻/已耗时）、右段注
/// （仅进行中证据迟滞时的「最后确认 HH:mm:ss」标
/// 龄，视图在右段第二行呈现）
public struct LedgerRowParts: Equatable, Sendable {
    public let subtitle: String
    public let trailing: String?
    public let trailingNote: String?

    public init(
        subtitle: String, trailing: String?,
        trailingNote: String? = nil
    ) {
        self.subtitle = subtitle
        self.trailing = trailing
        self.trailingNote = trailingNote
    }
}

public enum LedgerBoard {
    /// 按天分组（入参须已定序）：组头口径与动态页同
    /// 源（FeedBoard.groupTitle：今天/昨天/星期X/M月
    /// d日/yyyy年M月d日），不另立第二套日期口径
    public static func dayGroups(
        _ items: [LedgerItem], now: Date,
        calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> [LedgerDayGroup] {
        var titles: [String] = []
        var buckets: [[LedgerItem]] = []
        for item in items {
            let date = Date(timeIntervalSince1970: item.startedAt)
            let title = FeedBoard.groupTitle(
                for: date, now: now, calendar: calendar, locale: locale
            )
            if let lastTitle = titles.last, lastTitle == title {
                buckets[buckets.count - 1].append(item)
            } else {
                titles.append(title)
                buckets.append([item])
            }
        }
        return zip(titles, buckets).map {
            LedgerDayGroup(title: $0.0, items: $0.1)
        }
    }

    /// 会话聚合（§477）：同一会话的多次运行在列表里
    /// 合成一行（同名不重复）——代表＝最近开始的一次
    /// 运行（startedAt 最大、同刻以 lastSeq 大者胜），
    /// 状态与标题都取代表；无 sessionId 的条目各自成
    /// 行不强并。组序按代表 startedAt 倒序（最近活动
    /// 在前），组内成员保持入参序。只管列表呈现分组，
    /// 台账数据本体与详情口径不动
    public static func sessionGroups(
        _ items: [LedgerItem]
    ) -> [LedgerSessionGroup] {
        var order: [String] = []
        var buckets: [String: [LedgerItem]] = [:]
        for item in items {
            let key: String
            if let sessionId = item.sessionId, !sessionId.isEmpty {
                key = "s:" + sessionId
            } else {
                key = "i:" + item.id
            }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        let groups = order.map { key -> LedgerSessionGroup in
            let members = buckets[key] ?? []
            let representative = members.max {
                ($0.startedAt, $0.lastSeq) < ($1.startedAt, $1.lastSeq)
            } ?? members[0]
            return LedgerSessionGroup(
                representative: representative, members: members
            )
        }
        return groups.sorted {
            $0.representative.startedAt > $1.representative.startedAt
        }
    }

    /// 页首计数（规格 §4.2）：优先用与列表同一 payload
    /// 的桥侧 counts（同快照，不许另拉一个计数接口打
    /// 架）；counts 缺失时才从条目现算兜底。口径＝
    /// 正在进行（queued＋running）、待审批单列
    public static func headerCounts(
        items: [LedgerItem], summary: LedgerSummary?
    ) -> (inProgress: Int, blockedApproval: Int) {
        if let summary {
            return (summary.inProgress, summary.blockedApproval)
        }
        var inProgress = 0
        var blocked = 0
        for item in items {
            switch item.status {
            case .queued, .running: inProgress += 1
            case .blockedApproval: blocked += 1
            default: break
            }
        }
        return (inProgress, blocked)
    }

    /// 页首总览行文案：「正在进行 N 件 · 待审批 M 件」
    /// （M＝0 不显后半）；全静止时如实给「现在没有进行
    /// 中的工作」，不拿 0 件凑行
    public static func headerText(
        inProgress: Int, blockedApproval: Int,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        if inProgress == 0 && blockedApproval == 0 {
            return L10n.string("现在没有进行中的工作", locale: locale)
        }
        var text = L10n.format(
            "正在进行 %@ 件", locale: locale, String(inProgress)
        )
        if blockedApproval > 0 {
            text += L10n.format(
                " · 待审批 %@ 件", locale: locale, String(blockedApproval)
            )
        }
        return text
    }

    /// 行三段派生（§344，中枢四欠账·记录行三段式）：
    /// 列表行中段副题与右段 trailing 的单源——副题只
    /// 留状态词与非时间信息（失败分类），时间与已耗
    /// 时归右段；证据迟滞的「最后确认 HH:mm:ss」标龄
    /// 归右段注（trailingNote，仅进行中迟滞时有值，
    /// 视图在右段第二行呈现）。subtitle(for:) 由本
    /// 派生重组、整句口径逐字不变（见其实现注）
    public static func rowParts(
        for item: LedgerItem, serverNow: Double,
        calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> LedgerRowParts {
        // §217：监测变化是「检出事件」不是一项工作，
        // 状态词（已完成）会把语义说歪——中段直给事
        // 件词、检出时刻归右段，与旧监测段的变化行
        // 同口径
        if item.kind == .monitor {
            return LedgerRowParts(
                subtitle: L10n.string("监测变化", locale: locale),
                trailing: LedgerClock.time(
                    item.startedAt, calendar: calendar
                )
            )
        }
        let word = LedgerText.statusWord(item.status, locale: locale)
        let elapsed = LedgerElapsed.format(
            seconds: LedgerElapsed.elapsed(
                startedAt: item.startedAt, serverNow: serverNow
            )
        )
        switch item.status {
        case .running:
            var note: String?
            if item.evidenceLagging, let at = item.lastEvidenceAt {
                note = L10n.format(
                    "最后确认 %@", locale: locale,
                    LedgerClock.timeWithSeconds(at, calendar: calendar)
                )
            }
            return LedgerRowParts(
                subtitle: word, trailing: elapsed, trailingNote: note
            )
        case .queued, .blockedApproval:
            return LedgerRowParts(subtitle: word, trailing: elapsed)
        case .completed:
            guard let ended = item.endedAt else {
                return LedgerRowParts(subtitle: word, trailing: nil)
            }
            return LedgerRowParts(
                subtitle: word,
                trailing: LedgerClock.time(ended, calendar: calendar)
            )
        case .failed, .cancelled:
            var subtitle = word
            if let category = item.failReason?.category,
               !category.isEmpty {
                subtitle = L10n.format(
                    "%@ · %@", locale: locale, word, category
                )
            }
            return LedgerRowParts(
                subtitle: subtitle,
                trailing: item.endedAt.map {
                    LedgerClock.time($0, calendar: calendar)
                }
            )
        case .stale:
            return LedgerRowParts(
                subtitle: L10n.string("已失去联系", locale: locale),
                trailing: item.lastEvidenceAt.map {
                    LedgerClock.time($0, calendar: calendar)
                }
            )
        case .other:
            return LedgerRowParts(subtitle: word, trailing: nil)
        }
    }

    /// 行副题整句（状态词＋真信息，规格 §3/§4）：
    /// §344 起由 rowParts 重组——进行中带已耗时秒级
    /// 值（由视图每秒重算喂 serverNow）；证据迟滞加
    /// 「最后确认 HH:mm:ss」标龄；失败／取消带原因
    /// 分类；失联带最后确认时刻。状态词只走
    /// LedgerText 人话，原始枚举不进副题。重组与旧
    /// 逐字输出等值，由 LedgerModelsTests 旧钉死值
    /// 全绿把守（不许改期待值）
    public static func subtitle(
        for item: LedgerItem, serverNow: Double,
        calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let parts = rowParts(
            for: item, serverNow: serverNow,
            calendar: calendar, locale: locale
        )
        if item.kind == .monitor {
            guard let trailing = parts.trailing else {
                return parts.subtitle
            }
            return L10n.format(
                "%@ · %@", locale: locale, parts.subtitle, trailing
            )
        }
        switch item.status {
        case .running:
            var text = L10n.format(
                "%@ · 已运行 %@", locale: locale,
                parts.subtitle, parts.trailing ?? ""
            )
            if let note = parts.trailingNote {
                text += L10n.format(" · %@", locale: locale, note)
            }
            return text
        case .queued, .blockedApproval:
            return L10n.format(
                "%@ · 已等 %@", locale: locale,
                parts.subtitle, parts.trailing ?? ""
            )
        case .completed:
            guard let trailing = parts.trailing else {
                return parts.subtitle
            }
            return L10n.format(
                "%@ · %@", locale: locale, parts.subtitle, trailing
            )
        case .failed, .cancelled, .other:
            return parts.subtitle
        case .stale:
            guard let trailing = parts.trailing else {
                return parts.subtitle
            }
            return L10n.format(
                "%@ · 最后确认 %@", locale: locale,
                parts.subtitle, trailing
            )
        }
    }

    /// 详情时长行：活跃态＝已运行／已等时长，终态＝
    /// 总用时（起止同轴相减）；缺结束时刻的终态不编
    /// 时长、返回 nil 由视图不显该行
    public static func durationText(
        for item: LedgerItem, serverNow: Double,
        locale: Locale = AppLocale.uiLocale
    ) -> String? {
        switch item.status {
        case .running:
            return L10n.format(
                "已运行 %@", locale: locale,
                LedgerElapsed.format(seconds: LedgerElapsed.elapsed(startedAt: item.startedAt, serverNow: serverNow))
            )
        case .queued, .blockedApproval:
            return L10n.format(
                "已等 %@", locale: locale,
                LedgerElapsed.format(seconds: LedgerElapsed.elapsed(startedAt: item.startedAt, serverNow: serverNow))
            )
        case .completed, .failed, .cancelled:
            guard let ended = item.endedAt else { return nil }
            return L10n.format(
                "用时 %@", locale: locale,
                LedgerElapsed.format(seconds: ended - item.startedAt)
            )
        case .stale, .other:
            return nil
        }
    }

    /// 详情页首一句话摘要（§475）：只用条目自有
    /// 字段拼人话——终态给用时（＋子计数若有），
    /// 失败给原因分类，活跃态给已运行／已等时长，
    /// 失联给最后确认时刻。状态词本身归页首 chip，
    /// 本行不重复；无可说时返回 nil，视图整行不显，
    /// 不编造内容。
    public static func detailSummary(
        for item: LedgerItem, serverNow: Double,
        locale: Locale = AppLocale.uiLocale
    ) -> String? {
        var parts: [String] = []
        switch item.status {
        case .failed:
            // 终态摘要以成果/结论句为先（详情页首卡的
            // 「一句话摘要」本位）；用时在概况节有行，
            // 本处不再叠
            if let outcome = item.summary?.trimmingCharacters(
                in: .whitespacesAndNewlines), !outcome.isEmpty {
                parts.append(outcome)
            } else if let reason = item.failReason {
                parts.append(reason.category)
            }
        case .completed, .cancelled:
            if let outcome = item.summary?.trimmingCharacters(
                in: .whitespacesAndNewlines), !outcome.isEmpty {
                parts.append(outcome)
            } else if let duration = durationText(
                for: item, serverNow: serverNow, locale: locale
            ) {
                parts.append(duration)
            }
        case .running, .queued, .blockedApproval:
            if let duration = durationText(
                for: item, serverNow: serverNow, locale: locale
            ) {
                parts.append(duration)
            }
        case .stale:
            if let evidence = item.lastEvidenceAt {
                parts.append(
                    L10n.format(
                        "最后确认 %@", locale: locale,
                        LedgerClock.time(evidence)
                    )
                )
            }
        case .other:
            return nil
        }
        if let calls = item.toolCalls {
            parts.append(
                L10n.format(
                    "工具调用 %@ 次", locale: locale, String(calls)
                )
            )
        }
        if let subs = item.subTasks {
            parts.append(
                L10n.format(
                    "子任务 %@ 个", locale: locale, String(subs)
                )
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 详情步骤清单（Muse 式步骤卡的步源）：只由条
    /// 目 history 变迁派生——每条变迁开启一步，步名
    /// ＝变迁落点状态的人话（落点缺失的建账行称「开
    /// 始」），步长＝到下一变迁的间隔（末步到条目结
    /// 束时刻／活跃态到当前时刻；落点为终态的步是时
    /// 间点不是阶段，步长 nil）。history 之外没有步
    /// 骤数据源，未发生的步不编造、不存在「未到」步
    public static func steps(
        for item: LedgerItem, serverNow: Double,
        locale: Locale = AppLocale.uiLocale
    ) -> [LedgerStep] {
        let entries = item.history.sorted { $0.at < $1.at }
        return entries.enumerated().map { index, entry in
            let toStatus = LedgerStatus(rawValue: entry.to)
            let isLast = index == entries.count - 1
            let title: String
            if entry.to != nil {
                title = LedgerText.statusWord(
                    toStatus, locale: locale
                )
            } else {
                title = L10n.string("开始", locale: locale)
            }
            let duration: Double?
            if toStatus.isTerminal {
                duration = nil
            } else if !isLast {
                duration = max(0, entries[index + 1].at - entry.at)
            } else if let ended = item.endedAt {
                duration = max(0, ended - entry.at)
            } else if item.status.isActive {
                duration = max(0, serverNow - entry.at)
            } else if item.status == .stale,
                      let evidence = item.lastEvidenceAt {
                duration = max(0, evidence - entry.at)
            } else {
                duration = nil
            }
            let phase: LedgerStepPhase
            switch toStatus {
            case .failed:
                phase = .failed
            case .cancelled:
                phase = .cancelled
            default:
                if isLast && item.status.isActive {
                    phase = .current
                } else if isLast && item.status == .stale {
                    phase = .stale
                } else {
                    phase = .done
                }
            }
            return LedgerStep(
                index: index, title: title, at: entry.at,
                duration: duration, phase: phase,
                note: entry.note,
                actorWord: LedgerText.actorWord(
                    entry.by, locale: locale
                ),
                corrected: entry.corrected,
                conflict: entry.conflict
            )
        }
    }
}

/// 详情步骤一行的相位：done 已走完／current 正在这
/// 一步（活跃条目的末步）／failed 落点失败／
/// cancelled 落点取消／stale 失联待核
public enum LedgerStepPhase: Equatable, Sendable {
    case done
    case current
    case failed
    case cancelled
    case stale
}

/// 详情步骤一行（纯派生，视图只渲染）：步名、步时
/// （epoch 秒）、步长（秒，nil＝不显）、相位、变迁
/// 注记与记录者人话、对账纠正／冲突留痕
public struct LedgerStep: Equatable, Sendable, Identifiable {
    public let index: Int
    public let title: String
    public let at: Double
    public let duration: Double?
    public let phase: LedgerStepPhase
    public let note: String?
    public let actorWord: String
    public let corrected: Bool
    public let conflict: Bool

    public var id: Int { index }

    public init(
        index: Int, title: String, at: Double,
        duration: Double?, phase: LedgerStepPhase,
        note: String?, actorWord: String,
        corrected: Bool, conflict: Bool
    ) {
        self.index = index
        self.title = title
        self.at = at
        self.duration = duration
        self.phase = phase
        self.note = note
        self.actorWord = actorWord
        self.corrected = corrected
        self.conflict = conflict
    }
}

// MARK: - 线程真步呈现（GET /ledger/threads/{id}）

/// 线程步一行（端点真步的呈现形态）：步名已过解
/// 析链、相位已判定，视图只渲染。与 LedgerStep 分
/// 开：真步的时刻/步长端点给多少算多少（运行步无
/// 时刻——at 与 duration 同为 nil，视图整位不显，
/// 不许拿条目时刻冒充步时刻）
public struct LedgerThreadStepRow: Equatable, Sendable, Identifiable {
    public let index: Int
    public let title: String
    public let phase: LedgerStepPhase
    public let at: Double?
    public let duration: Double?
    /// 副行注记：语义步 humanNote 优先，其次步自带
    /// note，再次审批步的裁决结果，再次失败原因
    public let note: String?
    /// 工具步的参数预览（命令/查询原文摘录，端点
    /// preview 原样；语义步在时仍保留作细节行）
    public let preview: String?
    /// 记录者人话（只有变迁步带 by，其余 nil 不显）
    public let actorWord: String?

    public var id: Int { index }

    public init(
        index: Int, title: String, phase: LedgerStepPhase,
        at: Double?, duration: Double?, note: String?,
        preview: String?, actorWord: String?
    ) {
        self.index = index
        self.title = title
        self.phase = phase
        self.at = at
        self.duration = duration
        self.note = note
        self.preview = preview
        self.actorWord = actorWord
    }
}

extension LedgerBoard {
    /// 线程真步 → 呈现行（纯派生）。步名解析链写
    /// 死（2.25.0 契约）：①语义步 humanTitle（同序
    /// 对位）→②步自带人话名→③步自带形态名（截断
    /// 尾行 summary／审批步 action＋object／变迁步
    /// 落点状态人话）→④规则名（工具名走聊天工具卡
    /// 同一张词面表 ToolCardClassifier）。相位：失
    /// 败看 ok/failReason、变迁步看落点状态、进行
    /// 中线程的末个未回结果步为当前步。步长只在步
    /// 自带时刻时按相邻步间隔派生（与 history 步同
    /// 口径：终态落点是时间点不给步长）
    public static func threadStepRows(
        steps: [LedgerThreadStep],
        humanSteps: [LedgerHumanStep],
        inProgress: Bool, threadStatus: String?,
        endedAt: Double?, serverNow: Double,
        locale: Locale = AppLocale.uiLocale
    ) -> [LedgerThreadStepRow] {
        steps.enumerated().map { index, step in
            let human = humanSteps.indices.contains(index)
                ? humanSteps[index] : nil
            let actionText = threadStepNonBlank(step.action)
            let isTransition = actionText?.contains("→") ?? false
            let transitionTail = isTransition
                ? actionText?
                    .components(separatedBy: "→").last?
                    .trimmingCharacters(in: .whitespaces)
                : nil
            let transitionStatus = transitionTail.map {
                LedgerStatus(rawValue: $0)
            }
            let title: String
            if let humanTitle = threadStepNonBlank(
                human?.humanTitle
            ) {
                title = humanTitle
            } else if let own = threadStepNonBlank(step.ownTitle) {
                title = own
            } else if let summary = threadStepNonBlank(
                step.summary
            ) {
                title = summary
            } else if let action = actionText {
                if isTransition {
                    if let tail = transitionTail, !tail.isEmpty {
                        title = LedgerText.statusWord(
                            LedgerStatus(rawValue: tail),
                            locale: locale
                        )
                    } else {
                        title = L10n.string(
                            "开始", locale: locale
                        )
                    }
                } else if let object = threadStepNonBlank(
                    step.object
                ) {
                    title = action + " " + object
                } else {
                    title = action
                }
            } else if let tool = threadStepNonBlank(step.tool) {
                title = ToolCardClassifier.activityPhrase(
                    forToolName: tool, locale: locale
                )
            } else {
                title = L10n.string("步骤", locale: locale)
            }
            let isLast = index == steps.count - 1
            let failed = step.ok == false || step.failReason != nil
            let phase: LedgerStepPhase
            if failed {
                phase = .failed
            } else if let status = transitionStatus {
                switch status {
                case .failed:
                    phase = .failed
                case .cancelled:
                    phase = .cancelled
                default:
                    if isLast && inProgress {
                        phase = .current
                    } else if isLast && threadStatus == "stale" {
                        phase = .stale
                    } else {
                        phase = .done
                    }
                }
            } else if inProgress && isLast && step.ok == nil
                        && step.result == nil
                        && step.summary == nil {
                phase = .current
            } else {
                phase = .done
            }
            let duration: Double?
            if let at = step.at,
               !(transitionStatus?.isTerminal ?? false) {
                if index + 1 < steps.count,
                   let next = steps[index + 1].at {
                    duration = max(0, next - at)
                } else if let ended = endedAt {
                    duration = max(0, ended - at)
                } else if inProgress {
                    duration = max(0, serverNow - at)
                } else {
                    duration = nil
                }
            } else {
                duration = nil
            }
            var note = threadStepNonBlank(human?.humanNote)
                ?? threadStepNonBlank(step.note)
            if note == nil, actionText != nil, !isTransition {
                note = threadStepNonBlank(step.result)
            }
            if note == nil {
                note = threadStepNonBlank(step.failReason)
            }
            return LedgerThreadStepRow(
                index: index, title: title, phase: phase,
                at: step.at, duration: duration, note: note,
                preview: threadStepNonBlank(step.preview),
                actorWord: step.by.map {
                    LedgerText.actorWord($0, locale: locale)
                }
            )
        }
    }

    private static func threadStepNonBlank(
        _ value: String?
    ) -> String? {
        guard let value,
              !value.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty
        else { return nil }
        return value
    }
}
