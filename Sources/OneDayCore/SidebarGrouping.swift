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
        searching: Bool = false
    ) -> [Group<Key>] {
        let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
        if searching {
            return sorted.isEmpty
                ? []
                : [Group(label: "搜索结果", keys: sorted.map(\.key))]
        }
        var result: [Group<Key>] = []
        let pinned = sorted.filter(\.isPinned)
        if !pinned.isEmpty {
            result.append(Group(label: "置顶", keys: pinned.map(\.key)))
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
            result.append(Group(label: "今天", keys: today))
        }
        if !yesterday.isEmpty {
            result.append(Group(label: "昨天", keys: yesterday))
        }
        if !week.isEmpty {
            result.append(Group(label: "过去 7 天", keys: week))
        }
        if !month.isEmpty {
            result.append(Group(label: "过去 30 天", keys: month))
        }
        let nowYear = calendar.component(.year, from: now)
        for bucket in olderOrder {
            let label = bucket.year == nowYear
                ? "\(bucket.month)月"
                : "\(bucket.year)年\(bucket.month)月"
            result.append(Group(
                label: label,
                keys: olderKeys["\(bucket.year)-\(bucket.month)"] ?? []
            ))
        }
        return result
    }
}
