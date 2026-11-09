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

/// 顶栏状态行派生（0.6.1 改短词口径，用户真机点名；
/// 0.7.0 通道口径修正，用户 16:05 真机截图坐实）：
/// 胶囊里只放可证事实的短词。0.6.1 的病：状态只读桥
/// 快照——桥一旦连不上（钥匙未粘 401/桥抖动）快照置
/// 空就报「联系不上」，可聊天走的是 Hermes API 通道、
/// 明明刚收到回复，自相矛盾。0.7.0 口径：
///
/// - 「联系不上」只许由 Hermes API 通道本身的探活
///   （hermesChannelUp，App 每轮直探 /health）为假触发；
/// - 桥只是数据面：桥挂只降级桥自己的数（待审批不显
///   示），通道在就报「在线」；桥在且有待审批才报
///   「待审批 N」（数字只出自桥）；
/// - 通道探活未知（nil，冷启尚未探到）时退回桥快照
///   口径（桥的 hermesUp 字段），不新造第三种说法。
///
/// 旧四句（暂时联系不上/有 N 条待你审批/正在处理会话/
/// 随时待命）已于 0.6.1 全退役：长句在胶囊宽度里必被
/// 截断成「…」，且「正在处理会话」建立在桥的
/// activeSessions 上——Hermes 不写 ended_at、该数实
/// 为会话总数、是假进行中（桥字段本身不动、仍按契约
/// 传输，客户端文案不再把它说成进行中）。
public enum OverviewStatusLine {
    public static func resolve(
        snapshot: OverviewSnapshot?, hermesChannelUp: Bool?
    ) -> String {
        if let hermesChannelUp {
            guard hermesChannelUp else { return "联系不上" }
            if let snapshot, snapshot.pendingApprovals > 0 {
                return "待审批 \(snapshot.pendingApprovals)"
            }
            return "在线"
        }
        guard let snapshot, snapshot.hermesUp else {
            return "联系不上"
        }
        if snapshot.pendingApprovals > 0 {
            return "待审批 \(snapshot.pendingApprovals)"
        }
        return "在线"
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
