import Foundation
import OneDayCore

/// 工作台账按天＋会话聚合快照（第 3 项，照抄
/// FeedListSnapshot 模式）：按天分组与会话聚
/// 合一趟算齐，列表 body 消费快照不再每帧重算
/// （2000 条旧口径单趟 ≈17ms）；同时附带成员→
/// 代表行索引供聚焦滚动 O(1) 查表。
struct LedgerDaySessionSection: Equatable, Identifiable {
    let title: String
    let sessionGroups: [LedgerSessionGroup]

    var id: String { title }
}

struct LedgerListSnapshot: Equatable {
    let daySections: [LedgerDaySessionSection]
    let representativeIDByMemberID: [String: String]

    static func make(
        items: [LedgerItem],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> LedgerListSnapshot {
        // §名下状态行改造：过滤内部系统任务（动态调研等不进活动流水）
        let filteredItems = items.filter { !$0.isInternalSystemTask }
        let dayGroups = LedgerBoard.dayGroups(
            filteredItems, now: now, calendar: calendar, locale: locale
        )
        var sections: [LedgerDaySessionSection] = []
        sections.reserveCapacity(dayGroups.count)
        var index: [String: String] = [:]
        index.reserveCapacity(items.count)
        for group in dayGroups {
            let sessionGroups = LedgerBoard.sessionGroups(group.items)
            sections.append(
                LedgerDaySessionSection(
                    title: group.title,
                    sessionGroups: sessionGroups
                )
            )
            for sg in sessionGroups {
                for member in sg.members {
                    index[member.id] = sg.representative.id
                }
            }
        }
        return LedgerListSnapshot(
            daySections: sections,
            representativeIDByMemberID: index
        )
    }
}

/// 工作台账派生快照缓存：按已排序条目集＋当日零
/// 点＋日历时区缓存，输入未变直接复用上一份（秒
/// 级轮询无变更、折叠切换、焦点滚动不再整表重算）。
final class LedgerSnapshotCache {
    private var lastItems: [LedgerItem]?
    private var lastDayStart: Date?
    private var lastTimeZoneIdentifier: String?
    private var lastSnapshot: LedgerListSnapshot?

    private(set) var revision = 0

    func snapshot(
        items: [LedgerItem],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> LedgerListSnapshot {
        let dayStart = calendar.startOfDay(for: now)
        let tzID = calendar.timeZone.identifier
        if let lastSnapshot,
           lastDayStart == dayStart,
           lastTimeZoneIdentifier == tzID,
           lastItems == items {
            return lastSnapshot
        }
        let made = LedgerListSnapshot.make(
            items: items, now: now, calendar: calendar, locale: locale
        )
        lastItems = items
        lastDayStart = dayStart
        lastTimeZoneIdentifier = tzID
        lastSnapshot = made
        revision += 1
        return made
    }
}
