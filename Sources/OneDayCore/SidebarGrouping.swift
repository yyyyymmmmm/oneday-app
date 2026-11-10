import Foundation

/// 侧边栏会话分组（0.3.6，DESIGN-V4 §21；调研见
/// docs/reference/sidebar-research.md）：时间五段
/// （今天／昨天／过去 7 天／过去 30 天／更早按月）
/// ＋置顶组——ChatGPT 与 Claude 两家侧栏的共识粒
/// 度。纯函数：入参为 (key, updatedAt, isPinned)
/// 三元组与现在时刻，输出有序分组、组内按
/// updatedAt 倒序。分界按自然日差（startOfDay 对
/// 齐）：≤0 今天、1 昨天、2–7 过去 7 天、8–30 过
/// 去 30 天、>30 按月（同年「M月」、跨年
/// 「yyyy年M月」）。搜索态单组「搜索结果」：置顶
/// 不单列、按时间序混排。
public enum SidebarGrouping {
    public struct Item<Key: Hashable>: Equatable {
        public let key: Key
        public let updatedAt: Date
        public let isPinned: Bool

        public init(key: Key, updatedAt: Date, isPinned: Bool) {
            self.key = key
            self.updatedAt = updatedAt
            self.isPinned = isPinned
        }
    }

    public struct Group<Key: Hashable>: Equatable {
        public let label: String
        public let keys: [Key]

        public init(label: String, keys: [Key]) {
            self.label = label
            self.keys = keys
        }
    }

    public static func groups<Key: Hashable>(
        items: [Item<Key>],
        now: Date,
        calendar: Calendar = .current,
        searching: Bool = false,
        locale: Locale = AppLocale.uiLocale
    ) -> [Group<Key>] {
        let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
        if searching {
            return sorted.isEmpty
                ? []
                : [Group(label: L10n.string("搜索结果", locale: locale), keys: sorted.map(\.key))]
        }
        var result: [Group<Key>] = []
        let pinned = sorted.filter(\.isPinned)
        if !pinned.isEmpty {
            result.append(Group(label: L10n.string("置顶", locale: locale), keys: pinned.map(\.key)))
        }
        let todayStart = calendar.startOfDay(for: now)
        func dayDiff(_ date: Date) -> Int {
            let dayStart = calendar.startOfDay(for: date)
            return calendar.dateComponents(
                [.day], from: dayStart, to: todayStart
            ).day ?? Int.max
        }
        var today: [Key] = []
        var yesterday: [Key] = []
        var week: [Key] = []
        var month: [Key] = []
        var olderOrder: [(year: Int, month: Int)] = []
        var olderKeys: [String: [Key]] = [:]
        for item in sorted where !item.isPinned {
            switch dayDiff(item.updatedAt) {
            case ...0:
                today.append(item.key)
            case 1:
                yesterday.append(item.key)
            case 2...7:
                week.append(item.key)
            case 8...30:
                month.append(item.key)
            default:
                let comps = calendar.dateComponents(
                    [.year, .month], from: item.updatedAt
                )
                let year = comps.year ?? 0
                let mon = comps.month ?? 0
                let bucketID = "\(year)-\(mon)"
                if olderKeys[bucketID] == nil {
                    olderOrder.append((year: year, month: mon))
                    olderKeys[bucketID] = []
                }
                olderKeys[bucketID]?.append(item.key)
            }
        }
        if !today.isEmpty {
            result.append(Group(label: L10n.string("今天", locale: locale), keys: today))
        }
        if !yesterday.isEmpty {
            result.append(Group(label: L10n.string("昨天", locale: locale), keys: yesterday))
        }
        if !week.isEmpty {
            result.append(Group(label: L10n.string("过去 7 天", locale: locale), keys: week))
        }
        if !month.isEmpty {
            result.append(Group(label: L10n.string("过去 30 天", locale: locale), keys: month))
        }
        let nowYear = calendar.component(.year, from: now)
        for bucket in olderOrder {
            // 月组标题走系统格式器（钉 locale）：简体
            // 「11月」/「2025年11月」、英文「November」/
            // 「November 2025」，字段序由格式器按语言定
            let bucketDate = calendar.date(
                from: DateComponents(year: bucket.year, month: bucket.month, day: 1)
            ) ?? now
            let monthStyle = Date.FormatStyle(
                locale: locale, calendar: calendar, timeZone: calendar.timeZone
            )
            let label = bucket.year == nowYear
                ? bucketDate.formatted(monthStyle.month(.wide))
                : bucketDate.formatted(monthStyle.year().month(.wide))
            result.append(Group(
                label: label,
                keys: olderKeys["\(bucket.year)-\(bucket.month)"] ?? []
            ))
        }
        return result
    }
}
