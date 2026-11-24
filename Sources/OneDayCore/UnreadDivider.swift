import Foundation

/// NEW 未读分界线落点（台账 148，学 OpenBot 机制）：
/// 分界线立在第一条未读消息上方。未读的定义与
/// OB/桌面端同口径——只有对方（非 user）的消息能
/// 开启未读段，自己的消息永不算未读；工具卡条目
/// 不是会话发言、不作分界锚（与时间分隔条只认会
/// 话条目同规，见 ChatView.timelineDividers）。
///
/// 已读水位由持有者（App 层 ThreadReadMarkStore）
/// 按线程持久化（条目 id＋时刻）：打开线程时以水
/// 位解析一次锚点、随即把水位推进到当前末条——
/// 分界线在本次观看内定格（只演一次），下次打开
/// 已无未读。水位条目已被删时按时刻回落：水位之
/// 后第一条候选即锚。本解析纯函数、单测把守。
public enum UnreadDivider {
    /// 条目的最小投影：判定只需要 id、角色、时刻
    /// 与是否工具卡
    public struct EntryStub: Equatable, Sendable {
        public let id: UUID
        public let role: String
        public let createdAt: Date
        public let isToolCard: Bool

        public init(
            id: UUID, role: String, createdAt: Date,
            isToolCard: Bool
        ) {
            self.id = id
            self.role = role
            self.createdAt = createdAt
            self.isToolCard = isToolCard
        }
    }

    /// 已读水位：读到过的最后一条 id 与其时刻
    /// （id 优先定位、时刻作条目已删时的回落）
    public struct Watermark: Equatable, Sendable {
        public let entryID: UUID?
        public let date: Date

        public init(entryID: UUID?, date: Date) {
            self.entryID = entryID
            self.date = date
        }
    }

    /// 未读分界锚（分界线挂在此条上方）；无水位
    /// （从未打开过）或水位后无候选（全读完/只有
    /// 自己新发的）→ nil，不画线。entries 须为时
    /// 间升序（调用方传 sortedEntries 投影）
    public static func anchorEntryID(
        entries: [EntryStub], watermark: Watermark?
    ) -> UUID? {
        guard let watermark else { return nil }
        let startIndex: Int
        if let entryID = watermark.entryID,
           let index = entries.firstIndex(
               where: { $0.id == entryID }
           ) {
            startIndex = index + 1
        } else {
            startIndex = entries.firstIndex(
                where: { $0.createdAt > watermark.date }
            ) ?? entries.count
        }
        guard startIndex < entries.count else { return nil }
        for entry in entries[startIndex...] {
            if !entry.isToolCard, entry.role != "user" {
                return entry.id
            }
        }
        return nil
    }
}
