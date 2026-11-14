import Foundation

/// 待删队列单条（乐观删除，§232）：用户已确认删
/// 除、服务端后台删除未落定的一条会话。只承载恢
/// 复所需的最小信息——会话 id、标题（最终失败提
/// 醒文案用）、入队时刻；线程本体靠 ChatThread 的
/// isPendingDeletion 墓碑原地保留，不在本账复制内
/// 容（恢复＝解标，零数据搬运、零失真）
public struct PendingSessionDeletion: Codable, Equatable, Sendable {
    public var sessionID: String
    public var title: String
    public var enqueuedAt: Date

    public init(sessionID: String, title: String, enqueuedAt: Date) {
        self.sessionID = sessionID
        self.title = title
        self.enqueuedAt = enqueuedAt
    }
}

/// 待删队列（乐观删除，§232）：纯值集合、零 IO——
/// 宿主（SessionDeletionCoordinator）负责 JSON 进
/// UserDefaults 落盘（与 SideChatStore／FilePinSet
/// 同模式），App 被杀/重启后读回续跑。同会话重复
/// 入队恒只留一条（先入队者为准，标题不被后到者
/// 覆盖）
public struct PendingSessionDeletionQueue: Codable, Equatable, Sendable {
    public private(set) var records: [PendingSessionDeletion] = []

    public init() {}

    public var isEmpty: Bool { records.isEmpty }

    public var sessionIDs: Set<String> {
        Set(records.map(\.sessionID))
    }

    public func contains(sessionID: String) -> Bool {
        records.contains { $0.sessionID == sessionID }
    }

    public func record(sessionID: String) -> PendingSessionDeletion? {
        records.first { $0.sessionID == sessionID }
    }

    /// 入队：已在队返回 false、不动原条
    @discardableResult
    public mutating func enqueue(
        _ record: PendingSessionDeletion
    ) -> Bool {
        guard !contains(sessionID: record.sessionID) else {
            return false
        }
        records.append(record)
        return true
    }

    /// 出队：返回被摘掉的条（不在队返回 nil）
    @discardableResult
    public mutating func dequeue(
        sessionID: String
    ) -> PendingSessionDeletion? {
        guard let index = records.firstIndex(
            where: { $0.sessionID == sessionID }
        ) else { return nil }
        return records.remove(at: index)
    }
}
