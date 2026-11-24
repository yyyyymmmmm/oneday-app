import OneDayCore
import UserNotifications

/// 分级提醒器（总表 162，DESIGN §385.2）：站内通知
/// 拉取成功后消费 Core 提醒规划，把新到未读按级投
/// 成本地通知——即时打断级 timeSensitive＋声音、静
/// 默入盒级 passive 无声、仅角标级不投。已提醒 id
/// 落盘去重（`notify.tier.alertedIDs`），首见先种基
/// 线不补发（防积压风暴）。投递前只读真授权状态
/// （NotificationPermissionGate.currentState）：
/// 已决定状态照读、未决定**不发**授权请求（铁律：
/// 轮询不许弹授权窗）——未授权时本轮只登记已提醒，
/// 不投递、不下轮补弹。
enum NotificationTierAlerter {

    static let identifierPrefix = "oneday-tier-"
    private static let seenIDsKey = "notify.tier.alertedIDs"
    private static let seededKey = "notify.tier.baselineSeeded"
    /// 已提醒账上限：超出留最近 500 条（通知 id 时
    /// 序追加，截旧不截新）
    private static let seenIDsCap = 500

    static func consume(items: [OverviewNotification]) async {
        let defaults = UserDefaults.standard
        let orderedSeen =
            defaults.stringArray(forKey: seenIDsKey) ?? []
        let plan = NotificationAlertPlanner.plan(
            items: items,
            seenIDs: Set(orderedSeen),
            isCategoryEnabled: {
                NotificationTierPreferences.isEnabled($0)
            }
        )
        // 已提醒账先落盘：投递成败都不许下轮重复投；
        // 账按时序追加新 id（规划的 seenIDs 是集合，
        // 落盘序在此按「旧序＋本轮新增」重建）
        let known = Set(orderedSeen)
        let appended = items
            .map(\.id)
            .filter { !known.contains($0) }
        persistSeen(
            orderedSeen + appended, defaults: defaults
        )
        let seeded = defaults.bool(forKey: seededKey)
        if !seeded {
            defaults.set(true, forKey: seededKey)
            return
        }
        guard !plan.directives.isEmpty else { return }
        // 只读真状态过门：未授权（含未决定）静默收场，
        // 绝不在此发授权请求（铁律）
        let state = await NotificationPermissionGate.currentState()
        guard state.isUsable else { return }
        let byID = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0) }
        )
        let center = UNUserNotificationCenter.current()
        for directive in plan.directives {
            guard let item = byID[directive.notificationID]
            else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = NotificationSummary.presentation(
                kind: item.kind, title: item.title, body: item.body
            ).summary
            content.threadIdentifier =
                "oneday-tier-\(directive.category.rawValue)"
            switch directive.tier {
            case .interrupt:
                content.interruptionLevel = .timeSensitive
                content.sound = .default
            case .inbox:
                content.interruptionLevel = .passive
            case .badgeOnly:
                continue
            }
            let request = UNNotificationRequest(
                identifier: identifierPrefix + item.id,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private static func persistSeen(
        _ ordered: [String], defaults: UserDefaults
    ) {
        // 有序账截旧保新：超上限从最旧一头摘
        let capped = ordered.count > seenIDsCap
            ? Array(ordered.suffix(seenIDsCap)) : ordered
        defaults.set(capped, forKey: seenIDsKey)
    }
}
