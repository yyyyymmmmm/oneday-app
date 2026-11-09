import Foundation

/// 总览桥冻结契约模型（0.6.0 一期）：桥是 write-gate 同机
/// sidecar 的只读聚合面，基址为当前服务器的
/// `/api/overview-bridge`，鉴权复用 write-gate 钥匙。
/// 本文件只放 DTO 与纯派生：状态行与角标口径全 App 只许
/// 在这里算，View 不许各自拼数（蓝图 §2.7/§2.16）。
public struct OverviewSnapshot: Decodable, Equatable, Sendable {
    public var hermesUp: Bool
    public var activeSessions: Int
    public var pendingApprovals: Int
    public var unreadNotifications: Int
    public var generatedAt: String

    public init(
        hermesUp: Bool, activeSessions: Int, pendingApprovals: Int,
        unreadNotifications: Int, generatedAt: String
    ) {
        self.hermesUp = hermesUp
        self.activeSessions = activeSessions
        self.pendingApprovals = pendingApprovals
        self.unreadNotifications = unreadNotifications
        self.generatedAt = generatedAt
    }
}

public struct OverviewNotification: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let body: String
    public let createdAt: String
    public var read: Bool

    public init(
        id: String, kind: String, title: String, body: String,
        createdAt: String, read: Bool
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.read = read
    }
}

public struct OverviewNotificationsResponse: Decodable, Equatable, Sendable {
    public let items: [OverviewNotification]

    public init(items: [OverviewNotification]) {
        self.items = items
    }
}

public struct OverviewReadResponse: Decodable, Equatable, Sendable {
    public let ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

/// 顶栏状态行派生（冻结口径）：桥连不上或 Hermes 不在
/// →「暂时联系不上」；有待审批 →「有 N 条待你审批」；
/// 有活跃会话 →「正在处理会话」；否则「随时待命」。
/// 优先级固定为可达性 > 待审批 > 活跃会话 > 待命。
public enum OverviewStatusLine {
    public static func resolve(snapshot: OverviewSnapshot?) -> String {
        guard let snapshot, snapshot.hermesUp else {
            return "暂时联系不上"
        }
        if snapshot.pendingApprovals > 0 {
            return "有 \(snapshot.pendingApprovals) 条待你审批"
        }
        if snapshot.activeSessions > 0 {
            return "正在处理会话"
        }
        return "随时待命"
    }
}

/// 铃铛角标聚合（与 OpenMuse 同口径，蓝图 §2.16）：
/// 未读通知数 + 待审批数；桥不可达时为 0（不拿旧数冒充）。
/// 负数输入按 0 计，防桥端脏数据把角标算成负数。
public enum OverviewBadge {
    public static func count(snapshot: OverviewSnapshot?) -> Int {
        guard let snapshot else { return 0 }
        return max(0, snapshot.unreadNotifications)
            + max(0, snapshot.pendingApprovals)
    }
}
