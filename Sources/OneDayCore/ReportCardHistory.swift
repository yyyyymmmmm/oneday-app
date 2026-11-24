import Foundation

/// 回告留存合并（§241，2026-11-14 大厂九项①拍板）：
/// 回告卡已读只消未读标记、不清记录——记录留存成
/// 历史，在通知面板可回看、点行进详情、落点可达。
///
/// 为什么要本机存档：桥侧通知只是服务端易失窗口
/// （最近 50 条、状态随桥），卡在聊天页点掉已读后
/// 若无本机留存，记录就再也找不回来。本机存档是
/// 留存的单一记录面；回告不物化进聊天流（定版明
/// 令：无会话归属不塞聊天流；有归属的事件回响走
/// §229 既有物化通道，不在此重造）。
public enum ReportCardHistory {
    /// 留存上限：最近 200 条，超限丢最旧
    public static let retentionLimit = 200

    /// 合并现行与存档：同一 id 以现行（桥）为准——
    /// 内容与已读态皆服务端权威；只在存档里的（已
    /// 滑出桥窗口）保留存档最后所知状态。结果按
    /// createdAt 倒序（解析不了的垫后、彼此保入
    /// 序），最后截到留存上限
    public static func merge(
        live: [OverviewNotification],
        archived: [OverviewNotification]
    ) -> [OverviewNotification] {
        let liveIDs = Set(live.map(\.id))
        let combined = live + archived.filter { !liveIDs.contains($0.id) }
        let dated = combined.enumerated().map {
            (offset: $0.offset, item: $0.element,
             date: NotificationGrouping.parseCreatedAt($0.element.createdAt))
        }
        let sorted = dated.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?):
                return x != y ? x > y : a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }
        return Array(sorted.map(\.item).prefix(retentionLimit))
    }
}
