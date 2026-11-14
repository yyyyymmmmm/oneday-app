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

public struct OverviewNotification: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let body: String
    public let createdAt: String
    public var read: Bool
    /// 联动键（0.36.5 契约增补）：裁决回执通知带出其
    /// write-gate 记录 id——审批裁决与通知已读两套账
    /// 按此键联动（见 ApprovalResolution）。桥未升
    /// 级前 payload 无此字段、解码为 nil，联动不成立
    /// （回执按普通未读事件呈现），不许拿摘要文本等
    /// 弱信号冒充联动键
    public let refId: String?
    /// 变化联动键（§123 H2，伴生 1.0.14 起）：monitor_
    /// change 通知带出其变化记录 id（refId 为监测 id），
    /// 通知点达可直达那一条变化；旧桥通知无此字段、
    /// 解码为 nil，落点只达监测详情
    public let changeId: String?

    public init(
        id: String, kind: String, title: String, body: String,
        createdAt: String, read: Bool, refId: String? = nil,
        changeId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.read = read
        self.refId = refId
        self.changeId = changeId
    }

    /// 是否为审批裁决回执（kind 与 overview-bridge
    /// 生成端逐字一致：write_gate_decision）
    public var isDecisionReceipt: Bool {
        kind == "write_gate_decision"
    }

    /// 是否为监测变化（kind 与 oneday-bridge 监测账
    /// 本逐字一致：monitor_change；铃铛页元信息行
    /// 的类别词判定，0.36.7）
    public var isMonitorChange: Bool {
        kind == "monitor_change"
    }
}

/// 审批裁决联动（0.36.5，用户 19:10 点名：角标只许
/// 报未决事项，已批准/已驳回的不许再提示）：本人在
/// App 内落的裁决，其回执通知一到即自动消账——角
/// 标、通知列表、聊天回告卡三处读同一份通知状态，
/// 一处标已读、三处同消；历史留痕归枢纽「已决历
/// 史」，不占角标。他人/自动审核落的裁决不在本人
/// 裁决集内，其回执仍是「未读重要事件」，读后才消
/// ——提醒＝待办、办完即消，只对自己办完的成立。
public enum ApprovalResolution {
    /// 待自动消账的通知 id：未读＋裁决回执＋refId
    /// 命中本人裁决集，三条全中才算——任一不中（已
    /// 读/非回执/桥未带 refId/本人没裁过）都不动
    public static func receiptsToResolve(
        notifications: [OverviewNotification],
        selfDecidedIDs: Set<String>
    ) -> [String] {
        guard !selfDecidedIDs.isEmpty else { return [] }
        return notifications.compactMap { item in
            guard !item.read, item.isDecisionReceipt,
                  let refId = item.refId,
                  selfDecidedIDs.contains(refId)
            else { return nil }
            return item.id
        }
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
    /// 状态语气三态（0.19.0）：与状态词同源派生，供身份
    /// 胶囊的状态点取色——online 绿／attention 橙／
    /// offline 灰。此前点色在 App 层另立一套只认桥快照
    /// 的判定，与词（通道口径）两源分叉：桥挂＋通道在
    /// 时词报「在线」点却落灰（用户 22:26 真机点名）。
    /// 自此词与点共用 classify 一处判定，不许再分叉。
    public enum Tone: Equatable, Sendable {
        case online
        case attention
        case offline
    }

    private enum Kind {
        case offline
        case pending(Int)
        case online
    }

    /// §259 单源化（2026-11-14）：入参只剩一个在线结
    /// 论＋一个待审批计数。此前 classify 双入参（桥快
    /// 照 hermesUp 与通道探活）互为仲裁——探活未知时
    /// 桥快照替判在线与否，同一事实两个主源。自此结
    /// 论的合成归 App 层 OverviewBridgeStore 一处
    /// （channelUp：探活为主源、未知回落桥 hermesUp），
    /// 本函数只把结论＋计数翻成词与语气，不再仲裁。
    /// 判定矩阵与旧双入参版逐例等价（旧测试全集已迁
    /// 至本签名、对账见 §259）。
    private static func classify(
        channelUp: Bool?, pendingApprovals: Int
    ) -> Kind {
        guard let channelUp else { return .offline }
        guard channelUp else { return .offline }
        if pendingApprovals > 0 {
            return .pending(pendingApprovals)
        }
        return .online
    }

    public static func resolve(
        channelUp: Bool?, pendingApprovals: Int
    ) -> String {
        switch classify(
            channelUp: channelUp, pendingApprovals: pendingApprovals
        ) {
        case .offline: return "联系不上"
        case .pending(let count): return "待审批 \(count)"
        case .online: return "在线"
        }
    }

    public static func tone(
        channelUp: Bool?, pendingApprovals: Int
    ) -> Tone {
        switch classify(
            channelUp: channelUp, pendingApprovals: pendingApprovals
        ) {
        case .offline: return .offline
        case .pending: return .attention
        case .online: return .online
        }
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
