import AlarmKit
import Foundation
import OneDayCore
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 闹钟执行器（设备扩容批二，AlarmKit）

/// AlarmKit 闹钟的 attributes 元数据：标题随闹钟存
/// 进系统（响铃界面显示的就是它）；但系统闹钟列表
/// 回读时不回吐 attributes，标题另在本机登记表对
/// 账呈现（登记缺失不编标题，以系统列表为准绳）
struct DeviceAlarmMetadata: AlarmMetadata {
    var title: String = ""
}

/// 详情页闹钟条目（系统列表＋本机标题登记合成）
struct DeviceAlarmItem: Identifiable, Sendable {
    let id: String
    let title: String?
    let isCountdown: Bool
    let fireAt: Date?
    let stateText: String
}

/// 闹钟走 AlarmKit（iOS 26）：响铃是系统全屏界面、
/// 穿透静音与专注，App 不在前台也照常响。授权面守
/// 系统授权铁律：authorizationState 是同步属性，
/// 先读现态过 Core 的 DevicePermissionGate——只有
/// 未决定才发那一次 requestAuthorization，已授权
/// 直达、已拒绝只如实回错，永不重走异步请求回调。
/// 不建 widget 扩展：倒计时/暂停的自绘界面才需要
/// 它，只给 alert 呈现时系统默认界面兜底（§113）。
final class AlarmEngine: @unchecked Sendable {

    static func systemState() -> DevicePermissionState {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// 详情页权限开关动作的引擎侧：过门决策——只有
    /// requestOnce 才真发请求，其余档只回读现态
    func requestAccess() async -> DevicePermissionState {
        let current = Self.systemState()
        guard OneDayCore.DevicePermissionGate.decision(for: current)
            == .requestOnce else { return current }
        _ = try? await AlarmManager.shared.requestAuthorization()
        return Self.systemState()
    }

    // MARK: 标题登记表（只记在这台手机上，不出手机）

    private struct RegistryEntry: Codable {
        var title: String
        var kind: String
        var fireAt: TimeInterval
    }

    private static let registryKey = "device.alarmRegistry.v1"

    private func loadRegistry() -> [String: RegistryEntry] {
        guard let data = UserDefaults.standard.data(
            forKey: Self.registryKey
        ),
        let decoded = try? JSONDecoder().decode(
            [String: RegistryEntry].self, from: data
        ) else { return [:] }
        return decoded
    }

    private func saveRegistry(
        _ registry: [String: RegistryEntry]
    ) {
        if let data = try? JSONEncoder().encode(registry) {
            UserDefaults.standard.set(data, forKey: Self.registryKey)
        }
    }

    private func register(
        id: String, title: String, kind: String, fireAt: Date
    ) {
        var registry = loadRegistry()
        registry[id] = RegistryEntry(
            title: title, kind: kind,
            fireAt: fireAt.timeIntervalSince1970
        )
        saveRegistry(registry)
    }

    private func unregister(id: String) {
        var registry = loadRegistry()
        registry[id] = nil
        saveRegistry(registry)
    }

    func registeredTitle(id: String) -> String? {
        loadRegistry()[id]?.title
    }

    // MARK: 系统列表合成（存在性与状态以系统为准）

    private func systemAlarms() throws -> [Alarm] {
        try AlarmManager.shared.alarms
    }

    static func stateText(_ state: Alarm.State) -> String {
        switch state {
        case .scheduled: return "等待响铃"
        case .countdown: return "倒计时中"
        case .paused: return "已暂停"
        case .alerting: return "正在响铃"
        default: return "未知状态"
        }
    }

    private static func fireDate(
        of alarm: Alarm, registry: [String: RegistryEntry]
    ) -> Date? {
        if let schedule = alarm.schedule,
           case .fixed(let date) = schedule {
            return date
        }
        return registry[alarm.id.uuidString].map {
            Date(timeIntervalSince1970: $0.fireAt)
        }
    }

    /// 某个闹钟的回读对象（alarm_set 结果与幂等回
    /// 放共用）：不在系统列表里回 nil，不编造
    func alarmObject(id: String) -> [String: JSONValue]? {
        guard let alarms = try? systemAlarms(),
              let alarm = alarms.first(
                where: { $0.id.uuidString == id }
              )
        else { return nil }
        let registry = loadRegistry()
        var object: [String: JSONValue] = [
            "id": .string(id),
            "kind": .string(
                alarm.countdownDuration != nil
                    ? "countdown" : "fixed"
            ),
            "state": .string(Self.stateText(alarm.state)),
        ]
        if let title = registry[id]?.title {
            object["title"] = .string(title)
        }
        if let fireAt = Self.fireDate(of: alarm, registry: registry) {
            object["fireAt"] = .string(
                DeviceISO8601.format(fireAt)
            )
        }
        return object
    }

    func currentItems() -> [DeviceAlarmItem] {
        let registry = loadRegistry()
        let alarms = (try? systemAlarms()) ?? []
        return alarms.map { alarm in
            DeviceAlarmItem(
                id: alarm.id.uuidString,
                title: registry[alarm.id.uuidString]?.title,
                isCountdown: alarm.countdownDuration != nil,
                fireAt: Self.fireDate(
                    of: alarm, registry: registry
                ),
                stateText: Self.stateText(alarm.state)
            )
        }.sorted {
            ($0.fireAt ?? .distantFuture)
                < ($1.fireAt ?? .distantFuture)
        }
    }

    // MARK: 工具动作

    func listResult() -> JSONValue {
        let items = currentItems()
        return .object([
            "count": .number(Double(items.count)),
            "alarms": .array(items.map { item in
                var object: [String: JSONValue] = [
                    "id": .string(item.id),
                    "kind": .string(
                        item.isCountdown ? "countdown" : "fixed"
                    ),
                    "state": .string(item.stateText),
                ]
                if let title = item.title {
                    object["title"] = .string(title)
                }
                if let fireAt = item.fireAt {
                    object["fireAt"] = .string(
                        DeviceISO8601.format(fireAt)
                    )
                }
                return .object(object)
            }),
            "readAt": .string(DeviceISO8601.format(Date())),
        ])
    }

    /// alarm_set：调度后回读系统闹钟列表，id 在册才
    /// 报成功（回读验证纪律）；标题同步登记本机表
    func setAlarm(
        _ args: AlarmSetArgs
    ) async throws -> (objectID: String, result: JSONValue) {
        let state = Self.systemState()
        guard state.isUsable else {
            throw DeviceToolError.permissionDenied(
                "闹钟的系统权限当前是「\(state.label)」，无法设定"
            )
        }
        let id = UUID()
        let now = Date()
        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(
                title: LocalizedStringResource(
                    stringLiteral: args.title
                ),
                // 26.0 形态：停止钮必传（无此参的构造是
                // 26.1 才有的）；钮面显式构造，无静态简写
                stopButton: AlarmButton(
                    text: "停止",
                    textColor: .white,
                    systemImageName: "stop.fill"
                )
            )
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: DeviceAlarmMetadata(title: args.title),
            tintColor: Color.orange
        )
        let kind: String
        let fireAt: Date
        let configuration:
            AlarmManager.AlarmConfiguration<DeviceAlarmMetadata>
        if let at = args.at {
            guard at > now else {
                throw DeviceToolError.invalidArguments(
                    "定点时刻已经过去，设不上"
                )
            }
            kind = "fixed"
            fireAt = at
            configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: nil,
                schedule: .fixed(at),
                attributes: attributes,
                stopIntent: nil,
                secondaryIntent: nil
            )
        } else {
            let seconds = args.afterSeconds ?? 0
            kind = "countdown"
            fireAt = now.addingTimeInterval(seconds)
            configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: Alarm.CountdownDuration(
                    preAlert: seconds, postAlert: nil
                ),
                schedule: nil,
                attributes: attributes,
                stopIntent: nil,
                secondaryIntent: nil
            )
        }
        do {
            _ = try await AlarmManager.shared.schedule(
                id: id, configuration: configuration
            )
        } catch {
            throw DeviceToolError.failed(
                "系统没能设定这个闹钟：\(error.localizedDescription)"
            )
        }
        let key = id.uuidString
        register(id: key, title: args.title, kind: kind, fireAt: fireAt)
        guard let object = alarmObject(id: key) else {
            unregister(id: key)
            throw DeviceToolError.failed(
                "设定后在系统闹钟列表里没找到，不报成功"
            )
        }
        var result = object
        result["verified"] = .bool(true)
        result["humanSummary"] = .string(args.humanSummary)
        return (key, .object(result))
    }

    /// alarm_cancel：正在响的走 stop、其余走 cancel，
    /// 回读列表确认不在册才报成功；目标本就不在册时
    /// 语义收敛（取消的结果状态一致）但如实标
    /// wasPresent=false
    func cancelAlarm(
        _ args: AlarmCancelArgs
    ) throws -> (objectID: String, result: JSONValue) {
        guard let uuid = UUID(uuidString: args.alarmID) else {
            throw DeviceToolError.invalidArguments(
                "闹钟编号不是有效的编号"
            )
        }
        let before = (try? systemAlarms()) ?? []
        guard let target = before.first(
            where: { $0.id == uuid }
        ) else {
            let knownTitle = registeredTitle(id: args.alarmID)
            unregister(id: args.alarmID)
            return (args.alarmID, .object([
                "cancelled": .bool(true),
                "wasPresent": .bool(false),
                "verified": .bool(true),
                "humanSummary": .string(
                    args.humanSummary(title: knownTitle)
                ),
            ]))
        }
        let knownTitle = registeredTitle(id: args.alarmID)
        do {
            if target.state == .alerting {
                try AlarmManager.shared.stop(id: uuid)
            } else {
                try AlarmManager.shared.cancel(id: uuid)
            }
        } catch {
            throw DeviceToolError.failed(
                "系统没能取消这个闹钟：\(error.localizedDescription)"
            )
        }
        let after = (try? systemAlarms()) ?? []
        guard !after.contains(where: { $0.id == uuid }) else {
            throw DeviceToolError.failed(
                "取消后这个闹钟还在系统列表里，不报成功"
            )
        }
        unregister(id: args.alarmID)
        return (args.alarmID, .object([
            "cancelled": .bool(true),
            "wasPresent": .bool(true),
            "verified": .bool(true),
            "humanSummary": .string(
                args.humanSummary(title: knownTitle)
            ),
        ]))
    }

    /// 详情页本地取消（用户亲手点，不经桥与账本）
    func cancelLocal(id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        let alarms = (try? systemAlarms()) ?? []
        if let target = alarms.first(where: { $0.id == uuid }) {
            if target.state == .alerting {
                try? AlarmManager.shared.stop(id: uuid)
            } else {
                try? AlarmManager.shared.cancel(id: uuid)
            }
        }
        unregister(id: id)
    }
}

// MARK: - 本地通知执行器（设备扩容批二，UserNotifications）

/// 详情页待发通知条目（只列 OneDay 自家调度的）
struct DeviceNotificationItem: Identifiable, Sendable {
    let id: String
    let title: String
    let body: String
    let fireAt: Date?
}

/// 本地通知走 UNUserNotificationCenter。与 AlarmKit
/// 不同，UN 没有同步读授权状态的 API（只有带回调的
/// getNotificationSettings）——这是与「同步现读」口
/// 径的唯一出入（§113 登记）：状态读数缓存最近一次
/// 异步刷新值，进前台/进详情页/执行前三处刷新；执
/// 行 notify_post 前分发器先 await 刷新真状态再判
/// 门，绝不拿陈缓存放行。回调闭包只 resume
/// continuation（照 EK fetchReminders 的 nonisolated
/// 先例），不碰引擎其他状态。
final class NotificationEngine: @unchecked Sendable {

    static let maxPending = 64
    static let identifierPrefix = "oneday-notify-"

    // MARK: 授权状态（缓存＋异步刷新）

    /// 锁盒：静态缓存值与锁同居一盒（Swift 6 并发安全形态，
    /// 与本仓锁盒先例同式），外部只经存取口进出
    private final class StateCacheBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: DevicePermissionState = .notDetermined

        func get() -> DevicePermissionState {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ newValue: DevicePermissionState) {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    private static let stateCache = StateCacheBox()

    static var cachedState: DevicePermissionState {
        stateCache.get()
    }

    private static func updateCache(
        _ state: DevicePermissionState
    ) {
        stateCache.set(state)
    }

    static func translate(
        _ status: UNAuthorizationStatus
    ) -> DevicePermissionState {
        switch status {
        // provisional/ephemeral 都是「能发」的临时授
        // 权形态，如实归可用档（呈现文案不夸大为完
        // 全授权——状态字仍走 granted 的「已授权」）
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// 异步刷新真状态并回填缓存（呈现与分发共用）
    @discardableResult
    static func readSystemState() async -> DevicePermissionState {
        // 只把 Sendable 的状态枚举带出回调：设置对象本身
        // 不跨越并发边界（Swift 6 区域隔离会拦）
        let status = await withCheckedContinuation {
            (continuation:
                CheckedContinuation<UNAuthorizationStatus, Never>
            ) in
            UNUserNotificationCenter.current()
                .getNotificationSettings { settings in
                    continuation.resume(
                        returning: settings.authorizationStatus
                    )
                }
        }
        let state = translate(status)
        updateCache(state)
        return state
    }

    /// 详情页权限开关动作的引擎侧：先读真状态过门
    /// ——只有未决定才发那一次请求；已决定不重走异
    /// 步请求（铁律在异步读框架上的等价落法）
    func requestAccess() async -> DevicePermissionState {
        let current = await Self.readSystemState()
        guard OneDayCore.DevicePermissionGate.decision(for: current)
            == .requestOnce else { return current }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        return await Self.readSystemState()
    }

    // MARK: 发送与回读

    /// notify_post：执行前以刚刷新的真状态判门；调
    /// 度后回读待发∪已送达列表、含本次 id 才报成功
    /// （立即发的会直接转入已送达）；延时通知待发满
    /// 64 条如实拒绝（系统上限，硬塞会被系统丢弃）
    func post(
        _ args: NotifyPostArgs
    ) async throws -> (objectID: String, result: JSONValue) {
        let state = await Self.readSystemState()
        guard state.isUsable else {
            throw DeviceToolError.permissionDenied(
                "通知的系统权限当前是「\(state.label)」，发不了通知"
            )
        }
        let center = UNUserNotificationCenter.current()
        if args.delaySeconds > 0 {
            let pending = await center
                .pendingNotificationRequests()
            guard pending.count < Self.maxPending else {
                throw DeviceToolError.failed(
                    "待发通知已经满了（\(Self.maxPending) 条），先等前面的送达再发新的"
                )
            }
        }
        let identifier = Self.identifierPrefix
            + UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = args.title
        content.body = args.body
        content.sound = .default
        let trigger: UNNotificationTrigger? =
            args.delaySeconds > 0
            ? UNTimeIntervalNotificationTrigger(
                timeInterval: args.delaySeconds, repeats: false
            )
            : nil
        let request = UNNotificationRequest(
            identifier: identifier, content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            throw DeviceToolError.failed(
                "系统没能安排这条通知：\(error.localizedDescription)"
            )
        }
        // 回读验证：立即发的可能已转入已送达列表
        let pending = await center
            .pendingNotificationRequests()
        var verified = pending.contains {
            $0.identifier == identifier
        }
        if !verified {
            let delivered = await center.deliveredNotifications()
            verified = delivered.contains {
                $0.request.identifier == identifier
            }
        }
        guard verified else {
            throw DeviceToolError.failed(
                "安排后在待发列表里没找到这条通知，不报成功"
            )
        }
        var result: [String: JSONValue] = [
            "posted": .bool(true),
            "verified": .bool(true),
            "id": .string(identifier),
            "title": .string(args.title),
            "humanSummary": .string(args.humanSummary),
        ]
        if args.delaySeconds > 0 {
            result["deliverAt"] = .string(
                DeviceISO8601.format(
                    Date().addingTimeInterval(args.delaySeconds)
                )
            )
        }
        return (identifier, .object(result))
    }

    /// 详情页：OneDay 自家待发通知（只认自家前缀，
    /// 别家 App 的通知不在此列、不冒充）
    func pendingItems() async -> [DeviceNotificationItem] {
        let requests = await UNUserNotificationCenter
            .current().pendingNotificationRequests()
        return requests
            .filter {
                $0.identifier.hasPrefix(Self.identifierPrefix)
            }
            .map { request in
                DeviceNotificationItem(
                    id: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    fireAt: (request.trigger
                        as? UNTimeIntervalNotificationTrigger)?
                        .nextTriggerDate()
                )
            }
            .sorted {
                ($0.fireAt ?? .distantFuture)
                    < ($1.fireAt ?? .distantFuture)
            }
    }
}

// MARK: - 拉起执行器（设备扩容批二）

/// open_target：目标只能来自 Core 白名单目录，执
/// 行层只负责把目录里的地址打开——设置页恒在、直
/// 接开；应用先探装没装（没装如实报错、不许假装打
/// 开）。打开成功即用户被带离 App、设备会话随之断
/// 开属预期（名册文案已明说），本次回执以 open 的
/// 完成回调为准。UIKit 触点收在 MainActor 跳板里，
/// completion 闭包只 resume continuation。
final class OpenTargetEngine: @unchecked Sendable {

    func open(
        _ args: OpenTargetArgs
    ) async throws -> (objectID: String, result: JSONValue) {
        let target = args.target
        let urlString = target.urlString
            == OpenTarget.appSettingsSentinel
            ? await MainActor.run {
                UIApplication.openSettingsURLString
            }
            : target.urlString
        guard let url = URL(string: urlString) else {
            throw DeviceToolError.failed("这个目标的地址打不开")
        }
        if target.kind == .app {
            let canOpen = await MainActor.run {
                UIApplication.shared.canOpenURL(url)
            }
            guard canOpen else {
                throw DeviceToolError.failed(
                    "\(target.name(locale: AppLocale.uiLocale))没有装在这台手机上，打不开"
                )
            }
        }
        let opened = await withCheckedContinuation {
            (continuation: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                UIApplication.shared.open(
                    url, options: [:]
                ) { success in
                    continuation.resume(returning: success)
                }
            }
        }
        guard opened else {
            throw DeviceToolError.failed("系统没能打开这个目标")
        }
        return (target.id, .object([
            "opened": .bool(true),
            "target": .string(target.id),
            "name": .string(
                target.name(locale: AppLocale.uiLocale)
            ),
            "humanSummary": .string(args.humanSummary),
        ]))
    }

    /// 详情页本地打开（用户亲手点，人在场是天然前
    /// 提；视图本身在 MainActor 上下文里）
    func openLocal(_ target: OpenTarget) {
        let urlString = target.urlString
            == OpenTarget.appSettingsSentinel
            ? UIApplication.openSettingsURLString
            : target.urlString
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(
            url, options: [:], completionHandler: nil
        )
    }
}


extension AlarmEngine: DeviceCapabilityPlugin {
    static let capabilityDomain = "alarm"
}
extension NotificationEngine: DeviceCapabilityPlugin {
    static let capabilityDomain = "notifications"
}
extension OpenTargetEngine: DeviceCapabilityPlugin {
    static let capabilityDomain = "opener"
}
