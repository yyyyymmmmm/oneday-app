import Foundation

/// 通知分级矩阵（总表 162，DESIGN §385）：站内通知按
/// 类分级——分类（审批／运行完成／失败／系统）只认条
/// 目自带的结构信号（kind 与既有派生口），分级对位
/// iOS 通行口径（UNNotificationInterruptionLevel）：
/// 即时打断＝timeSensitive、静默入盒＝passive、仅角
/// 标＝不发本地通知。本文件只放纯派生与偏好口：分类
/// 与矩阵全 App 只许在此算，View 与提醒器不许各自拼。
public enum NotificationTier {

    // MARK: - 分类

    public enum Category: String, CaseIterable, Equatable, Sendable {
        /// 审批：写闸裁决回执（write_gate_decision）
        case approval
        /// 运行完成：任务结果（task_completed）
        case runCompleted
        /// 失败：服务端尚无专用 kind（§385 缺口 G1）——
        /// kind 含 fail/error 信号即归此类，服务端补
        /// kind 后自动生效
        case failure
        /// 系统：监测变化与未知 kind 兜底
        case system

        /// 设置与偏好键的稳定名（改名即断档，不许漂移）
        public var preferenceKey: String {
            "notify.category.\(rawValue).enabled"
        }

        public func label(locale: Locale = AppLocale.uiLocale) -> String {
            switch self {
            case .approval: return L10n.string("审批结果", locale: locale)
            case .runCompleted: return L10n.string("运行完成", locale: locale)
            case .failure: return L10n.string("失败提醒", locale: locale)
            case .system: return L10n.string("系统与监测", locale: locale)
            }
        }
    }

    /// 条目 → 类：只认结构信号——裁决回执认既有
    /// isDecisionReceipt、完成认 kind 字面、失败认
    /// kind 内的 fail/error 信号（G1 预留口）、监测
    /// 与其余一切归系统兜底
    public static func category(
        for item: OverviewNotification
    ) -> Category {
        if item.isDecisionReceipt { return .approval }
        if item.kind == "task_completed" { return .runCompleted }
        let kind = item.kind.lowercased()
        if kind.contains("fail") || kind.contains("error") {
            return .failure
        }
        return .system
    }

    // MARK: - 分级

    public enum Tier: Equatable, Sendable {
        /// 即时打断：timeSensitive＋声音
        case interrupt
        /// 静默入盒：passive、无声音、只进列表
        case inbox
        /// 仅角标：不发本地通知，只留站内列表＋角标
        case badgeOnly

        public func label(locale: Locale = AppLocale.uiLocale) -> String {
            switch self {
            case .interrupt: return L10n.string("即时打断", locale: locale)
            case .inbox: return L10n.string("静默入盒", locale: locale)
            case .badgeOnly: return L10n.string("仅角标", locale: locale)
            }
        }
    }

    /// 类 → 级（矩阵定版，§385.2）：审批与失败需用
    /// 户及时知晓/介入，给即时打断；运行完成是可回
    /// 看的结果，静默入盒；系统监测是背景信息流，
    /// 仅角标
    public static func tier(for category: Category) -> Tier {
        switch category {
        case .approval, .failure: return .interrupt
        case .runCompleted: return .inbox
        case .system: return .badgeOnly
        }
    }

    public static func tier(
        for item: OverviewNotification
    ) -> Tier {
        tier(for: category(for: item))
    }
}

/// 通知分类偏好口（总表 162）：四类开关同键两读——
/// Core 本口与设置页 @AppStorage 共用
/// `notify.category.<类>.enabled` 键，缺省全开；写后
/// 读回以同一 UserDefaults 实值为准（钉测把守）。
public enum NotificationTierPreferences {

    public static func isEnabled(
        _ category: NotificationTier.Category,
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: category.preferenceKey) as? Bool
            ?? true
    }

    public static func setEnabled(
        _ category: NotificationTier.Category,
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: category.preferenceKey)
    }
}

/// 提醒规划（纯函数）：新一轮拉到的条目里，哪些该发
/// 本地提醒——只认「未读＋分类开关开＋级非仅角标＋
/// 未提醒过」四条全中；规划同时产出新的已提醒集
/// （含本轮全部所见 id），提醒器落盘后下轮不重复。
/// 首见基线：已提醒集为空（从未规划过）时，本轮只
/// 登记不发——防积压未读一次性补发成风暴。
public enum NotificationAlertPlanner {

    public struct Directive: Equatable, Sendable {
        public let notificationID: String
        public let category: NotificationTier.Category
        public let tier: NotificationTier.Tier

        public init(
            notificationID: String,
            category: NotificationTier.Category,
            tier: NotificationTier.Tier
        ) {
            self.notificationID = notificationID
            self.category = category
            self.tier = tier
        }
    }

    public struct Plan: Equatable, Sendable {
        public let directives: [Directive]
        public let seenIDs: Set<String>

        public init(directives: [Directive], seenIDs: Set<String>) {
            self.directives = directives
            self.seenIDs = seenIDs
        }
    }

    public static func plan(
        items: [OverviewNotification],
        seenIDs: Set<String>,
        isCategoryEnabled: (NotificationTier.Category) -> Bool
    ) -> Plan {
        let isBaseline = seenIDs.isEmpty
        var newSeen = seenIDs
        var directives: [Directive] = []
        for item in items {
            newSeen.insert(item.id)
            guard !isBaseline, !item.read,
                  !seenIDs.contains(item.id) else { continue }
            let category = NotificationTier.category(for: item)
            guard isCategoryEnabled(category) else { continue }
            let tier = NotificationTier.tier(for: category)
            guard tier != .badgeOnly else { continue }
            directives.append(
                Directive(
                    notificationID: item.id,
                    category: category,
                    tier: tier
                )
            )
        }
        return Plan(directives: directives, seenIDs: newSeen)
    }
}

// MARK: - 按服务器/每智能体三档通知与继承（第五批 #17）

/// 三档通知模式（学 OpenBot）：全部提醒 / 只提醒需要我的（审批、失败） / 静默
public enum NotificationDeliveryMode: String, CaseIterable, Codable, Equatable, Sendable {
    case all
    case needsMeOnly
    case muted

    public func label(locale: Locale = AppLocale.uiLocale) -> String {
        switch self {
        case .all: return L10n.string("全部提醒", locale: locale)
        case .needsMeOnly: return L10n.string("只提醒需要我的", locale: locale)
        case .muted: return L10n.string("静默", locale: locale)
        }
    }

    /// 给定通知级别在该模式下是否允许发本地提醒
    public func allows(_ tier: NotificationTier.Tier) -> Bool {
        switch self {
        case .all:
            return tier != .badgeOnly
        case .needsMeOnly:
            return tier == .interrupt
        case .muted:
            return false
        }
    }
}

/// 服务器默认 + 每智能体覆盖的通知分档存储（支持继承：智能体未单独设置时继承所属服务器档位，服务器未设时默认 `.all`）
public enum NotificationScopePreferences {
    private static func serverKey(_ serverID: String) -> String {
        "notify.scope.server.\(serverID).mode"
    }

    private static func agentKey(_ serverID: String, _ agentID: String) -> String {
        "notify.scope.agent.\(serverID).\(agentID).mode"
    }

    public static func serverMode(
        serverID: String,
        defaults: UserDefaults = .standard
    ) -> NotificationDeliveryMode {
        guard let raw = defaults.string(forKey: serverKey(serverID)),
              let mode = NotificationDeliveryMode(rawValue: raw) else {
            return .all
        }
        return mode
    }

    public static func setServerMode(
        _ mode: NotificationDeliveryMode,
        serverID: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: serverKey(serverID))
    }

    /// 智能体覆盖档位（nil 表示继承服务器档位）
    public static func agentOverrideMode(
        serverID: String,
        agentID: String,
        defaults: UserDefaults = .standard
    ) -> NotificationDeliveryMode? {
        guard let raw = defaults.string(forKey: agentKey(serverID, agentID)) else {
            return nil
        }
        return NotificationDeliveryMode(rawValue: raw)
    }

    public static func setAgentOverrideMode(
        _ mode: NotificationDeliveryMode?,
        serverID: String,
        agentID: String,
        defaults: UserDefaults = .standard
    ) {
        let key = agentKey(serverID, agentID)
        if let mode {
            defaults.set(mode.rawValue, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// 生效档位：智能体覆盖优先 → 服务器默认 → `.all`
    public static func resolvedMode(
        serverID: String,
        agentID: String?,
        defaults: UserDefaults = .standard
    ) -> NotificationDeliveryMode {
        if let agentID, !agentID.isEmpty,
           let override = agentOverrideMode(
               serverID: serverID, agentID: agentID, defaults: defaults
           ) {
            return override
        }
        return serverMode(serverID: serverID, defaults: defaults)
    }
}
