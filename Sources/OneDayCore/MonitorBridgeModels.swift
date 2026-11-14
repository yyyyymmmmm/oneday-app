import Foundation

/// oneday-bridge 监测契约模型（0.12.0，P6 客户端先行）：
/// 契约冻结于 oneday-design-review/monitor-bridge-
/// contract-20261109.md——Hermes 本体无 monitor 实体、
/// cron job 无指纹/结果字段，监测数据源须由桥扩展
/// /monitors 才成立；本包按契约形状建客户端，桥未开
/// 通时集合端点 404＝「监测数据源未开通」如实露。
/// 字段口径与 goals/ideas 一致：时间 epoch 秒（float）、
/// 错误体 {"error": 人话}、可选字段缺失按空收、不因
/// 单字段漂移整表解码失败。本文件只放 DTO＋纯派生
/// （状态分类/未读聚合/排序/差异行组装），网络与状态
/// 在 App 层。

// MARK: - 监测 DTO

public struct BridgeMonitor: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// 盯的 URL/对象原文
    public let target: String
    /// 频率人话（服务端给显示串，客户端不解析 cron 语法）
    public let scheduleText: String
    /// 承载调度的 Hermes cron job id；未建为 nil
    public let cronJobId: String?
    public let enabled: Bool
    /// 最近一次检查时刻（epoch 秒）；从未检查为 nil
    public let lastCheckedAt: Double?
    /// 最近一次检查结果原文：changed/unchanged/failed；
    /// 从未检查为 nil。契约三分之外的值不猜（见呈现层）
    public let lastResult: String?
    /// 最近一次检查失败的人话原因；非失败时为 nil
    public let lastError: String?
    /// 未读变化数（服务端权威计数）
    public let unreadChanges: Int
    /// 最近一次变化的人话摘要；无变化记录为 nil
    public let latestChangeSummary: String?
    /// 最近一次变化时刻；无变化记录为 nil
    public let latestChangeAt: Double?
    public let createdAt: Double
    public let updatedAt: Double
    /// 挂靠目标 id（P2 桥字段，0.40.0 起 App 才解）：目标
    /// 详情「关联」段按此过滤；未挂靠/旧载荷缺失为 nil
    public let goalId: String?

    public init(
        id: String, name: String, target: String,
        scheduleText: String, cronJobId: String?,
        enabled: Bool, lastCheckedAt: Double?,
        lastResult: String?, lastError: String?,
        unreadChanges: Int, latestChangeSummary: String?,
        latestChangeAt: Double?,
        createdAt: Double, updatedAt: Double,
        goalId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.scheduleText = scheduleText
        self.cronJobId = cronJobId
        self.enabled = enabled
        self.lastCheckedAt = lastCheckedAt
        self.lastResult = lastResult
        self.lastError = lastError
        self.unreadChanges = unreadChanges
        self.latestChangeSummary = latestChangeSummary
        self.latestChangeAt = latestChangeAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.goalId = goalId
    }

    /// 启停开关的本地乐观副本（§232）：只翻 enabled，
    /// 其余字段原样。服务端仍是真源——写后回读整表
    /// 替换，失败以原副本恢复呈现
    public func withEnabled(_ enabled: Bool) -> BridgeMonitor {
        BridgeMonitor(
            id: id, name: name, target: target,
            scheduleText: scheduleText, cronJobId: cronJobId,
            enabled: enabled, lastCheckedAt: lastCheckedAt,
            lastResult: lastResult, lastError: lastError,
            unreadChanges: unreadChanges,
            latestChangeSummary: latestChangeSummary,
            latestChangeAt: latestChangeAt,
            createdAt: createdAt, updatedAt: updatedAt,
            goalId: goalId
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, target, scheduleText, cronJobId, enabled
        case lastCheckedAt, lastResult, lastError, unreadChanges
        case latestChangeSummary, latestChangeAt, createdAt, updatedAt
        case goalId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        target = try container.decodeIfPresent(
            String.self, forKey: .target
        ) ?? ""
        scheduleText = try container.decodeIfPresent(
            String.self, forKey: .scheduleText
        ) ?? ""
        cronJobId = try container.decodeIfPresent(
            String.self, forKey: .cronJobId
        )
        enabled = try container.decodeIfPresent(
            Bool.self, forKey: .enabled
        ) ?? true
        lastCheckedAt = try container.decodeIfPresent(
            Double.self, forKey: .lastCheckedAt
        )
        lastResult = try container.decodeIfPresent(
            String.self, forKey: .lastResult
        )
        lastError = try container.decodeIfPresent(
            String.self, forKey: .lastError
        )
        unreadChanges = try container.decodeIfPresent(
            Int.self, forKey: .unreadChanges
        ) ?? 0
        latestChangeSummary = try container.decodeIfPresent(
            String.self, forKey: .latestChangeSummary
        )
        latestChangeAt = try container.decodeIfPresent(
            Double.self, forKey: .latestChangeAt
        )
        createdAt = try container.decodeIfPresent(
            Double.self, forKey: .createdAt
        ) ?? 0
        updatedAt = try container.decodeIfPresent(
            Double.self, forKey: .updatedAt
        ) ?? 0
        goalId = try container.decodeIfPresent(
            String.self, forKey: .goalId
        )
    }

    /// 解析后的检查结果；原文不在契约三分内 → nil
    /// （呈现层按未识别态处理，绝不猜成无变化）
    public var checkResult: MonitorCheckResult? {
        guard let lastResult else { return nil }
        return MonitorCheckResult(rawValue: lastResult)
    }
}

public struct BridgeMonitorsResponse: Decodable, Equatable, Sendable {
    public let items: [BridgeMonitor]

    public init(items: [BridgeMonitor]) {
        self.items = items
    }
}

// MARK: - 变化记录 DTO

public struct BridgeMonitorChange: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let monitorId: String
    /// 检出时刻（epoch 秒）
    public let detectedAt: Double
    /// 人话一句（如「价格从 ¥199 变为 ¥179」）
    public let summary: String
    /// 变化前原文/关键值；桥没存原文时为 nil
    public let before: String?
    /// 变化后原文/关键值；同上
    public let after: String?
    public let read: Bool

    public init(
        id: String, monitorId: String, detectedAt: Double,
        summary: String, before: String?, after: String?,
        read: Bool
    ) {
        self.id = id
        self.monitorId = monitorId
        self.detectedAt = detectedAt
        self.summary = summary
        self.before = before
        self.after = after
        self.read = read
    }

    private enum CodingKeys: String, CodingKey {
        case id, monitorId, detectedAt, summary, before, after, read
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        monitorId = try container.decode(String.self, forKey: .monitorId)
        detectedAt = try container.decodeIfPresent(
            Double.self, forKey: .detectedAt
        ) ?? 0
        summary = try container.decodeIfPresent(
            String.self, forKey: .summary
        ) ?? ""
        before = try container.decodeIfPresent(
            String.self, forKey: .before
        )
        after = try container.decodeIfPresent(
            String.self, forKey: .after
        )
        read = try container.decodeIfPresent(
            Bool.self, forKey: .read
        ) ?? false
    }

    /// 已读副本（标记已读后本地即时呈现，服务端计数
    /// 仍以回读 /monitors 为权威）
    public func markingRead() -> BridgeMonitorChange {
        BridgeMonitorChange(
            id: id, monitorId: monitorId, detectedAt: detectedAt,
            summary: summary, before: before, after: after,
            read: true
        )
    }
}

public struct BridgeMonitorChangesResponse: Decodable, Equatable, Sendable {
    public let items: [BridgeMonitorChange]

    public init(items: [BridgeMonitorChange]) {
        self.items = items
    }
}

// MARK: - 检查结果与状态分类

/// 检查结果三分（契约冻结值）：有变化/无变化/检查
/// 失败——三者语义完全不同，呈现层不许混淆
public enum MonitorCheckResult: String, Equatable, Sendable {
    case changed
    case unchanged
    case failed
}

/// 监测卡状态点五态＋未识别态：已暂停优先于结果态；
/// 结果原文不在三分内 → unknown（如实露「状态未
/// 识别」，不猜）
public enum MonitorStatusKind: Equatable, Sendable {
    case paused
    case changed
    case unchanged
    case failed
    case neverChecked
    case unknown
}

public enum MonitorPresentation {
    public static func status(of monitor: BridgeMonitor) -> MonitorStatusKind {
        guard monitor.enabled else { return .paused }
        guard monitor.lastCheckedAt != nil else { return .neverChecked }
        switch monitor.checkResult {
        case .changed: return .changed
        case .unchanged: return .unchanged
        case .failed: return .failed
        case nil: return .unknown
        }
    }

    /// 状态人话（卡面状态行与详情共用，全 App 只此一处）
    public static func statusText(of monitor: BridgeMonitor) -> String {
        switch status(of: monitor) {
        case .paused: return "已暂停"
        case .changed: return "有变化"
        case .unchanged: return "无变化"
        case .failed: return "检查失败"
        case .neverChecked: return "还没检查过"
        case .unknown: return "状态未识别"
        }
    }

    /// 未读变化总数（段标题角标口径＝各监测服务端
    /// 计数之和，不自己数变化记录条数）
    public static func totalUnread(_ monitors: [BridgeMonitor]) -> Int {
        monitors.reduce(0) { $0 + max($1.unreadChanges, 0) }
    }
}

// MARK: - 排序（呈现层纯函数）

public enum MonitorOrdering {
    /// 列表序：未读多者靠前 → 最近变化新者靠前 →
    /// 创建早者靠前（同批稳定序）
    public static func sorted(_ monitors: [BridgeMonitor]) -> [BridgeMonitor] {
        monitors.sorted { lhs, rhs in
            if lhs.unreadChanges != rhs.unreadChanges {
                return lhs.unreadChanges > rhs.unreadChanges
            }
            let lhsChange = lhs.latestChangeAt ?? -Double.infinity
            let rhsChange = rhs.latestChangeAt ?? -Double.infinity
            if lhsChange != rhsChange { return lhsChange > rhsChange }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

public enum MonitorChangeOrdering {
    /// 变化记录一律检出时刻倒序（服务端同口径，
    /// 客户端再排一遍防桥实现漂移）
    public static func sorted(
        _ changes: [BridgeMonitorChange]
    ) -> [BridgeMonitorChange] {
        changes.sorted { $0.detectedAt > $1.detectedAt }
    }
}

// MARK: - 新建监测（0.12.1 控制接线）

/// 新建监测的频率三档（0.12.1）：手动只在点「立即
/// 检查」时跑；间隔两档落 intervalSeconds 由桥内
/// 调度到点执行。cron 高级档本包不出 UI——契约字段
/// 在请求体留口（恒 nil 不落键），桥认 cron 优先。
public enum MonitorFrequency: String, CaseIterable, Equatable, Sendable {
    case manual
    case hourly
    case daily

    /// 机器调度间隔（秒）；手动档为 nil（桥据此判
    /// 手动型：两者都不给＝不会自己跑）
    public var intervalSeconds: Int? {
        switch self {
        case .manual: return nil
        case .hourly: return 3600
        case .daily: return 86400
        }
    }

    /// 客户端组的人话频率串，随请求体上送、服务端
    /// 原样存作显示串（客户端不解析、服务端不改写）
    public var scheduleText: String {
        switch self {
        case .manual: return "手动检查"
        case .hourly: return "每小时检查"
        case .daily: return "每天检查"
        }
    }

    /// 表单选项短名
    public var label: String {
        switch self {
        case .manual: return "手动检查"
        case .hourly: return "每小时"
        case .daily: return "每天"
        }
    }
}

/// POST /monitors 请求体（桥上线实形）：{name,
/// target, scheduleText?, cron?, intervalSeconds?}；
/// 可选字段 nil 不落键（合成 Encodable 对 Optional
/// 走 encodeIfPresent）
public struct BridgeMonitorCreateRequest: Encodable, Equatable, Sendable {
    public let name: String
    public let target: String
    public let scheduleText: String?
    /// cron 高级档留口：本包不组装，恒 nil
    public let cron: String?
    public let intervalSeconds: Int?

    public init(
        name: String, target: String, scheduleText: String?,
        cron: String?, intervalSeconds: Int?
    ) {
        self.name = name
        self.target = target
        self.scheduleText = scheduleText
        self.cron = cron
        self.intervalSeconds = intervalSeconds
    }

    /// 表单口径收口：名称/链接去首尾空白，频率档展开
    /// 为 scheduleText 人话串＋intervalSeconds
    public static func make(
        name: String, target: String, frequency: MonitorFrequency
    ) -> BridgeMonitorCreateRequest {
        BridgeMonitorCreateRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            target: target.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            scheduleText: frequency.scheduleText,
            cron: nil,
            intervalSeconds: frequency.intervalSeconds
        )
    }
}

/// 新建表单校验（与桥端 400 口径对齐：名称空、链接
/// 空、链接非 http(s) 先在客户端拦下，不发必失败的
/// 请求；真发后服务端人话仍会透传，不双轨）
public enum MonitorCreateValidation {
    /// 返回第一条问题人话；无问题为 nil
    public static func problem(name: String, target: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            return "请填写监测名称。"
        }
        let target = target.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if target.isEmpty {
            return "请填写要盯的链接。"
        }
        if !target.hasPrefix("http://"),
           !target.hasPrefix("https://") {
            return "链接要以 http:// 或 https:// 开头。"
        }
        return nil
    }
}

// MARK: - 差异呈现组装

/// 变化详情页的行组装（纯函数，单测钉死）：摘要必有；
/// before/after 有才成行；两者皆无时 hasOriginalText
/// 为 false，页面据此明说「没有保存变化前后的原文」，
/// 不拿摘要冒充 diff。
/// §123 N3 起 before/after 另带预览形（preview）：页面
/// 默认只铺预览（限长、行界截断），全文收进展开区——
/// 桥没有「要点」数据，不编造要点，结构化只做到
/// 摘要＋预览＋原文折叠这一层。
public enum MonitorChangeDetail {
    /// 预览上限（字数）：监测原文是整页快照，动辄上千
    /// 字；480 字够看出变没变、变在哪一段
    public static let previewLimit = 480

    public struct Rows: Equatable, Sendable {
        public let summary: String
        public let before: String?
        public let after: String?
        public let hasOriginalText: Bool
        /// 预览形（未截断时与原文相同）；原文为 nil 时同为 nil
        public let beforePreview: String?
        public let afterPreview: String?
        /// 原文是否被预览截断（页面据此决定给不给展开入口）
        public let beforeTruncated: Bool
        public let afterTruncated: Bool

        public init(
            summary: String, before: String?,
            after: String?, hasOriginalText: Bool,
            beforePreview: String? = nil,
            afterPreview: String? = nil,
            beforeTruncated: Bool = false,
            afterTruncated: Bool = false
        ) {
            self.summary = summary
            self.before = before
            self.after = after
            self.hasOriginalText = hasOriginalText
            self.beforePreview = beforePreview ?? before
            self.afterPreview = afterPreview ?? after
            self.beforeTruncated = beforeTruncated
            self.afterTruncated = afterTruncated
        }
    }

    public static func rows(
        for change: BridgeMonitorChange
    ) -> Rows {
        let before = nonEmpty(change.before)
        let after = nonEmpty(change.after)
        let beforePreview = before.map { preview(of: $0) }
        let afterPreview = after.map { preview(of: $0) }
        return Rows(
            summary: change.summary,
            before: before,
            after: after,
            hasOriginalText: before != nil || after != nil,
            beforePreview: beforePreview?.text,
            afterPreview: afterPreview?.text,
            beforeTruncated: beforePreview?.truncated ?? false,
            afterTruncated: afterPreview?.truncated ?? false
        )
    }

    /// 预览截断：超限时优先断在后半段的最后一个换行
    /// 处（整行截断，不切半行），无好断点才硬断；断处
    /// 带省略号明示后面还有
    static func preview(
        of text: String
    ) -> (text: String, truncated: Bool) {
        guard text.count > previewLimit else {
            return (text, false)
        }
        var cut = String(text.prefix(previewLimit))
        if let nl = cut.lastIndex(of: "\n"),
           cut.distance(from: cut.startIndex, to: nl)
                >= previewLimit / 2 {
            cut = String(cut[..<nl])
        }
        return (cut + "…", true)
    }

    /// 空串与纯空白按「没存」处理（桥若落了空串，
    /// 不许在页面上摆两个空框冒充原文）
    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : value
    }
}
