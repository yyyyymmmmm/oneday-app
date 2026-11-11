import AlarmKit
import Contacts
import EventKit
import Foundation
import OneDayCore
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// 系统权限翻译层：EK/CN 的授权状态逐件翻成 Core
/// 的 DevicePermissionState（呈现与注册载荷只认这
/// 一套枚举）。健康/家庭未接线、从未申请，如实
/// 报 notDetermined——不许拿别件的授权冒充。
enum DevicePermissions {
    static func currentStates() -> [DeviceSourceID: DevicePermissionState] {
        [
            .calendar: calendarState(),
            .reminders: remindersState(),
            .contacts: contactsState(),
            // 照片/步数状态函数在 DeviceSyncExecutors
            // （PhotoKit/CoreMotion 翻译层同文件）
            .photos: photosState(),
            .motion: motionState(),
            // 剪贴板/沙盒文件（设备扩容批一）：iOS 没
            // 有这两件的系统权限，如实报 notApplicable
            // ——不许拿 granted 冒充系统已授权；能不能
            // 调用只看「允许智能体调用」开关
            .clipboard: .notApplicable,
            .files: .notApplicable,
            // 闹钟/通知/打开目标（设备扩容批二）：
            // 闹钟走 AlarmKit 同步 authorizationState
            // 现读；通知没有同步读状态的 API，报最近
            // 一次刷新的缓存值（进前台/进页/执行前都
            // 会刷新，执行判门以刷新后的真状态为准）；
            // 打开目标没有系统权限，如实 notApplicable
            .alarm: AlarmEngine.systemState(),
            .notifications: NotificationEngine.cachedState,
            .opener: .notApplicable,
            .health: .notDetermined,
            .home: .notDetermined,
        ]
    }

    static func calendarState() -> DevicePermissionState {
        translate(EKEventStore.authorizationStatus(for: .event))
    }

    static func remindersState() -> DevicePermissionState {
        translate(EKEventStore.authorizationStatus(for: .reminder))
    }

    private static func translate(
        _ status: EKAuthorizationStatus
    ) -> DevicePermissionState {
        switch status {
        case .fullAccess, .authorized: return .granted
        case .writeOnly: return .writeOnly
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func contactsState() -> DevicePermissionState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return .granted
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}

// MARK: - 呈现层条目（详情页 L1 本地读的形状）

struct DeviceAgendaEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarName: String
    let calendarColorHex: UInt32
    let location: String?
}

struct DeviceReminderItem: Identifiable, Sendable {
    let id: String
    let title: String
    let due: Date?
    let priority: Int
    let notes: String?
    let listName: String
    let isCompleted: Bool

    /// 过期判定（呈现口径）：未完成且到期已过
    var isOverdue: Bool {
        guard !isCompleted, let due else { return false }
        return due < Date()
    }
}

struct DeviceContactItem: Identifiable, Sendable {
    let id: String
    let name: String
    let phones: [String]
    let emails: [String]
    let organization: String?
}

/// 沙盒文件条目（文件详情页本地浏览用）：path 是
/// 相对 Documents 根的规范路径，既是身份也是定位
struct DeviceFileItem: Identifiable, Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    let sizeBytes: Int64
    let modifiedAt: Date

    var id: String { path }
}

// MARK: - EventKit 执行器（日历＋提醒同 store）

/// 日历/提醒的框架执行：工具调用与详情页 L1 读共
/// 用这一份（同一数据源、同一翻译，不许两处各读各
/// 的）。写纪律落在这里：回读验证——写完必须重新取
/// 回对象才许报成功；回读不到即失败原文。
final class EventKitEngine: @unchecked Sendable {
    let store = EKEventStore()

    // MARK: 授权

    func requestCalendarAccess() async -> DevicePermissionState {
        _ = try? await store.requestFullAccessToEvents()
        return DevicePermissions.calendarState()
    }

    func requestRemindersAccess() async -> DevicePermissionState {
        _ = try? await store.requestFullAccessToReminders()
        return DevicePermissions.remindersState()
    }

    // MARK: 日历读

    func events(from start: Date, to end: Date) -> [DeviceAgendaEvent] {
        let predicate = store.predicateForEvents(
            withStart: start, end: end, calendars: nil
        )
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                DeviceAgendaEvent(
                    id: event.eventIdentifier,
                    title: event.title ?? "(无标题)",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarName: event.calendar.title,
                    calendarColorHex: Self.colorHex(event.calendar.cgColor),
                    location: event.location
                )
            }
    }

    func todayEventCount() -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return events(from: start, to: end).count
    }

    static func colorHex(_ cgColor: CGColor?) -> UInt32 {
        guard let components = cgColor?.components,
              components.count >= 3 else { return 0x8E8E93 }
        let r = UInt32(min(max(components[0], 0), 1) * 255)
        let g = UInt32(min(max(components[1], 0), 1) * 255)
        let b = UInt32(min(max(components[2], 0), 1) * 255)
        return (r << 16) | (g << 8) | b
    }

    static func eventObject(_ event: EKEvent) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "id": .string(event.eventIdentifier),
            "title": .string(event.title ?? ""),
            "start": .string(DeviceISO8601.format(event.startDate)),
            "end": .string(DeviceISO8601.format(event.endDate)),
            "allDay": .bool(event.isAllDay),
            "calendarName": .string(event.calendar.title),
        ]
        if let location = event.location, !location.isEmpty {
            object["location"] = .string(location)
        }
        if let notes = event.notes, !notes.isEmpty {
            object["notes"] = .string(notes)
        }
        return object
    }

    /// calendar_list_events 结果：窗口内事件＋readAt
    /// （现读时刻，诚实口径的证据）
    func listEventsResult(window: CalendarListWindow) -> JSONValue {
        let predicate = store.predicateForEvents(
            withStart: window.start, end: window.end, calendars: nil
        )
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
        var result: [String: JSONValue] = [
            "readAt": .string(DeviceISO8601.format(Date())),
            "events": .array(events.map { .object(Self.eventObject($0)) }),
        ]
        if window.wasClamped {
            result["windowClamped"] = .bool(true)
        }
        return .object(result)
    }

    // MARK: 日历写（回读验证）

    func createEvent(
        _ args: CalendarCreateArgs
    ) throws -> (objectID: String, result: JSONValue) {
        let calendars = store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
        let target: EKCalendar?
        if let name = args.calendarName {
            target = calendars.first { $0.title == name }
            if target == nil {
                throw DeviceToolError.failed("找不到可写的日历「\(name)」")
            }
        } else {
            target = store.defaultCalendarForNewEvents
                ?? calendars.first
        }
        guard let calendar = target else {
            throw DeviceToolError.failed("没有可写的日历")
        }
        let event = EKEvent(eventStore: store)
        event.title = args.title
        event.startDate = args.start
        event.endDate = args.end
        event.isAllDay = args.allDay
        event.calendar = calendar
        event.location = args.location
        event.notes = args.notes
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            throw DeviceToolError.failed("新建日程失败：\(error.localizedDescription)")
        }
        // 回读验证：取回刚建的对象才许报成功
        guard let saved = store.event(withIdentifier: event.eventIdentifier) else {
            throw DeviceToolError.failed("新建后没能确认该日程已保存，不报成功")
        }
        return (saved.eventIdentifier, .object([
            "objectId": .string(saved.eventIdentifier),
            "event": .object(Self.eventObject(saved)),
        ]))
    }

    func updateEvent(
        _ args: CalendarUpdateArgs
    ) throws -> (objectID: String, result: JSONValue) {
        guard let event = store.event(withIdentifier: args.eventID) else {
            throw DeviceToolError.failed("找不到该日程（可能已被删除）")
        }
        guard event.calendar.allowsContentModifications else {
            throw DeviceToolError.updateNotAllowed("该日历不允许修改")
        }
        // 红线（设计档 §5）：他人组织的日程只许看不许改
        if let organizer = event.organizer, !organizer.isCurrentUser {
            throw DeviceToolError.updateNotAllowed(
                "这是他人组织的日程，只能查看不能修改"
            )
        }
        if let title = args.title { event.title = title }
        if let start = args.start {
            // 只给开始时刻时整体平移、保持原时长
            if args.end == nil {
                let duration = event.endDate.timeIntervalSince(event.startDate)
                event.endDate = start.addingTimeInterval(duration)
            }
            event.startDate = start
        }
        if let end = args.end { event.endDate = end }
        if let location = args.location { event.location = location }
        if let notes = args.notes { event.notes = notes }
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            throw DeviceToolError.failed("修改日程失败：\(error.localizedDescription)")
        }
        guard let saved = store.event(withIdentifier: args.eventID) else {
            throw DeviceToolError.failed("修改后没能确认该日程已保存，不报成功")
        }
        return (saved.eventIdentifier, .object([
            "objectId": .string(saved.eventIdentifier),
            "event": .object(Self.eventObject(saved)),
        ]))
    }

    /// 幂等重放时的回读：按 id 取事件现状（不在了回 nil）
    func eventObjectByID(_ id: String) -> [String: JSONValue]? {
        store.event(withIdentifier: id).map(Self.eventObject)
    }

    // MARK: 同步制（0.36.14）：窗口场次整表读

    /// 同步窗口内的场次记录：predicate 已把重复事
    /// 件按场次展开，occurrenceId＝事件标识＋场次
    /// 开始时刻（同一重复事件的各场次靠它区分）
    func syncOccurrences(
        from start: Date, to end: Date
    ) -> [SyncCalendarRecord] {
        let predicate = store.predicateForEvents(
            withStart: start, end: end, calendars: nil
        )
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                SyncCalendarRecord(
                    occurrenceId: event.eventIdentifier + "|"
                        + DeviceISO8601.format(event.startDate),
                    eventId: event.eventIdentifier,
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    allDay: event.isAllDay,
                    calendarName: event.calendar.title,
                    location: event.location
                )
            }
    }

    /// 同步快照：未完成提醒全量记录＋聚合（今日已
    /// 完成/已过期，Core 同口径计算）
    func reminderSyncSnapshot() async -> (
        records: [SyncReminderRecord],
        aggregates: SyncReminderAggregates
    ) {
        let all = await fetchAllReminders()
        let inputs = all.map { reminder in
            SyncReminderInput(
                due: reminder.dueDateComponents.flatMap {
                    Calendar.current.date(from: $0)
                },
                isCompleted: reminder.isCompleted,
                completionDate: reminder.completionDate
            )
        }
        let records = all.filter { !$0.isCompleted }.map { reminder in
            SyncReminderRecord(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "",
                due: reminder.dueDateComponents.flatMap {
                    Calendar.current.date(from: $0)
                },
                priority: reminder.priority,
                listName: reminder.calendar.title
            )
        }
        return (
            records,
            SyncReminderAggregates.compute(inputs, now: Date())
        )
    }

    // MARK: 提醒读

    /// EKReminder 非 Sendable，过 continuation 边界用
    /// 盒包一层（取回后只在本引擎内读，不跨线共享）
    private struct ReminderBox: @unchecked Sendable {
        let reminders: [EKReminder]
    }

    private func fetchAllReminders() async -> [EKReminder] {
        let calendars = store.calendars(for: .reminder)
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: calendars)
        let box = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(
                    returning: ReminderBox(reminders: reminders ?? [])
                )
            }
        }
        return box.reminders
    }

    func reminderItems() async -> [DeviceReminderItem] {
        await fetchAllReminders().map(Self.reminderItem)
    }

    static func reminderItem(_ reminder: EKReminder) -> DeviceReminderItem {
        DeviceReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "(无标题)",
            due: reminder.dueDateComponents.flatMap {
                Calendar.current.date(from: $0)
            },
            priority: reminder.priority,
            notes: reminder.notes,
            listName: reminder.calendar.title,
            isCompleted: reminder.isCompleted
        )
    }

    static func reminderObject(_ reminder: EKReminder) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "id": .string(reminder.calendarItemIdentifier),
            "title": .string(reminder.title ?? ""),
            "listName": .string(reminder.calendar.title),
            "completed": .bool(reminder.isCompleted),
            "priority": .number(Double(reminder.priority)),
        ]
        if let due = reminder.dueDateComponents.flatMap({
            Calendar.current.date(from: $0)
        }) {
            object["due"] = .string(DeviceISO8601.format(due))
        }
        if let notes = reminder.notes, !notes.isEmpty {
            object["notes"] = .string(notes)
        }
        return object
    }

    /// reminders_list 结果：只回未完成项＋计数（含今
    /// 日已完成数），不回已完成历史（设计档粒度）
    func listRemindersResult() async -> JSONValue {
        let all = await fetchAllReminders()
        let lists = store.calendars(for: .reminder)
        let todayStart = Calendar.current.startOfDay(for: Date())
        var groups: [[String: JSONValue]] = []
        var total = 0
        for list in lists {
            let items = all.filter {
                $0.calendar.calendarIdentifier
                    == list.calendarIdentifier && !$0.isCompleted
            }.sorted {
                ($0.dueDateComponents.flatMap {
                    Calendar.current.date(from: $0)
                } ?? .distantFuture)
                    < ($1.dueDateComponents.flatMap {
                        Calendar.current.date(from: $0)
                    } ?? .distantFuture)
            }
            total += items.count
            groups.append([
                "name": .string(list.title),
                "incompleteCount": .number(Double(items.count)),
                "items": .array(items.map { .object(Self.reminderObject($0)) }),
            ])
        }
        let completedToday = all.filter {
            $0.isCompleted
                && ($0.completionDate ?? .distantPast) >= todayStart
        }.count
        return .object([
            "readAt": .string(DeviceISO8601.format(Date())),
            "totalIncomplete": .number(Double(total)),
            "completedToday": .number(Double(completedToday)),
            "lists": .array(groups.map { .object($0) }),
        ])
    }

    // MARK: 提醒写（回读验证）

    func createReminder(
        _ args: ReminderCreateArgs
    ) throws -> (objectID: String, result: JSONValue) {
        let lists = store.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
        let target: EKCalendar?
        if let name = args.listName {
            target = lists.first { $0.title == name }
            if target == nil {
                throw DeviceToolError.failed("找不到可写的提醒清单「\(name)」")
            }
        } else {
            target = store.defaultCalendarForNewReminders() ?? lists.first
        }
        guard let list = target else {
            throw DeviceToolError.failed("没有可写的提醒清单")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = args.title
        reminder.calendar = list
        reminder.notes = args.notes
        if let due = args.due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw DeviceToolError.failed("新建提醒失败：\(error.localizedDescription)")
        }
        guard let saved = store.calendarItem(
            withIdentifier: reminder.calendarItemIdentifier
        ) as? EKReminder else {
            throw DeviceToolError.failed("新建后没能确认该提醒已保存，不报成功")
        }
        return (saved.calendarItemIdentifier, .object([
            "objectId": .string(saved.calendarItemIdentifier),
            "reminder": .object(Self.reminderObject(saved)),
        ]))
    }

    /// App 内手动新建提醒（详情页本地动作，不经桥、
    /// 不进审计——那是用户自己的手，设计档 §5）
    func createReminderSimple(title: String, due: Date?) throws {
        let list = store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder)
                .first { $0.allowsContentModifications }
        guard let list else {
            throw DeviceToolError.failed("没有可写的提醒清单")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw DeviceToolError.failed(
                "新建提醒失败：\(error.localizedDescription)"
            )
        }
    }

    /// 勾完成：已完成再勾回已完成态不报错（天然幂等，
    /// 设计档 §5）；App 内手动勾选与工具共用此口
    func setReminderCompleted(
        id: String, completed: Bool
    ) throws -> (objectID: String, result: JSONValue) {
        guard let reminder = store.calendarItem(
            withIdentifier: id
        ) as? EKReminder else {
            throw DeviceToolError.failed("找不到该提醒（可能已被删除）")
        }
        if reminder.isCompleted != completed {
            reminder.isCompleted = completed
            reminder.completionDate = completed ? Date() : nil
            do {
                try store.save(reminder, commit: true)
            } catch {
                throw DeviceToolError.failed(
                    "更新提醒失败：\(error.localizedDescription)"
                )
            }
        }
        guard let saved = store.calendarItem(
            withIdentifier: id
        ) as? EKReminder else {
            throw DeviceToolError.failed("更新后没能确认该提醒已保存，不报成功")
        }
        return (saved.calendarItemIdentifier, .object([
            "objectId": .string(saved.calendarItemIdentifier),
            "reminder": .object(Self.reminderObject(saved)),
        ]))
    }

    /// 幂等重放时的回读：按 id 取提醒现状
    func reminderObjectByID(_ id: String) -> [String: JSONValue]? {
        (store.calendarItem(withIdentifier: id) as? EKReminder)
            .map(Self.reminderObject)
    }
}

// MARK: - Contacts 执行器（只读现查）

/// 通讯录执行器：只做关键词现查与本地列表读，写一
/// 律不做（设计档定版：高误伤）。受限授权时系统框
/// 架天然只返回被勾选子集——呈现层据权限态明说。
final class ContactsEngine: @unchecked Sendable {
    let store = CNContactStore()

    private static var keysToFetch: [CNKeyDescriptor] {
        // 键是 String 常量、描述符是 CNKeyDescriptor，
        // 异构字面量推断不稳——命令式组装（逐个桥 NSString）
        var keys: [CNKeyDescriptor] = []
        keys.append(CNContactGivenNameKey as NSString)
        keys.append(CNContactFamilyNameKey as NSString)
        keys.append(CNContactOrganizationNameKey as NSString)
        keys.append(CNContactPhoneNumbersKey as NSString)
        keys.append(CNContactEmailAddressesKey as NSString)
        keys.append(
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        )
        return keys
    }

    func requestAccess() async -> DevicePermissionState {
        _ = try? await store.requestAccess(for: .contacts)
        return DevicePermissions.contactsState()
    }

    private static func item(_ contact: CNContact) -> DeviceContactItem {
        let name = CNContactFormatter.string(
            from: contact, style: .fullName
        ) ?? ""
        return DeviceContactItem(
            id: contact.identifier,
            name: name.isEmpty ? "(无姓名)" : name,
            phones: contact.phoneNumbers.map { $0.value.stringValue },
            emails: contact.emailAddresses.map { $0.value as String },
            organization: contact.organizationName.isEmpty
                ? nil : contact.organizationName
        )
    }

    static func contactObject(_ item: DeviceContactItem) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "name": .string(item.name),
            "phones": .array(item.phones.map { .string($0) }),
            "emails": .array(item.emails.map { .string($0) }),
        ]
        if let organization = item.organization {
            object["organization"] = .string(organization)
        }
        return object
    }

    /// contacts_search：关键词现查、只回命中（限额收敛在 Core 解析层）
    func search(_ args: ContactsSearchArgs) throws -> JSONValue {
        let predicate = CNContact.predicateForContacts(
            matchingName: args.query
        )
        do {
            let found = try store.unifiedContacts(
                matching: predicate, keysToFetch: Self.keysToFetch
            )
            let items = found.prefix(args.limit).map(Self.item)
            return .object([
                "readAt": .string(DeviceISO8601.format(Date())),
                "query": .string(args.query),
                "count": .number(Double(items.count)),
                "contacts": .array(
                    items.map { .object(Self.contactObject($0)) }
                ),
            ])
        } catch {
            throw DeviceToolError.failed(
                "通讯录搜索失败：\(error.localizedDescription)"
            )
        }
    }

    /// 本地列表读（详情页）：进页才读、离页不留副本
    func allContacts(limit: Int = 1000) throws -> [DeviceContactItem] {
        let request = CNContactFetchRequest(keysToFetch: Self.keysToFetch)
        request.sortOrder = .userDefault
        var items: [DeviceContactItem] = []
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                items.append(Self.item(contact))
                if items.count >= limit { stop.pointee = true }
            }
        } catch {
            throw DeviceToolError.failed(
                "通讯录读取失败：\(error.localizedDescription)"
            )
        }
        return items
    }

    /// 本地按名过滤（详情页搜索框）：与工具同谓词口径
    func searchLocal(query: String, limit: Int = 200) throws -> [DeviceContactItem] {
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let found = try store.unifiedContacts(
            matching: predicate, keysToFetch: Self.keysToFetch
        )
        return found.prefix(limit).map(Self.item)
    }

    // MARK: 同步制（0.36.14）：清单＋全量记录一次枚举

    /// 同步快照：一次整本枚举同时产出清单条目（标
    /// 识＋指纹，送伴生比对）与全量最小字段记录
    /// （只取比对说有变的那些上传）。分组名靠分组
    /// 成员关系反查（联系人本体不带分组信息）；
    /// 受限授权下系统只给勾选子集，枚举天然收敛
    func syncSnapshot() throws -> (
        entries: [ContactManifestEntry],
        records: [SyncContactRecord]
    ) {
        let groupMap = groupNamesByContactID()
        let request = CNContactFetchRequest(keysToFetch: Self.keysToFetch)
        request.sortOrder = .userDefault
        var records: [SyncContactRecord] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                records.append(Self.syncRecord(
                    contact, groups: groupMap[contact.identifier] ?? []
                ))
            }
        } catch {
            throw DeviceToolError.failed(
                "通讯录读取失败：\(error.localizedDescription)"
            )
        }
        return (records.map(\.manifestEntry), records)
    }

    private static func syncRecord(
        _ contact: CNContact, groups: [String]
    ) -> SyncContactRecord {
        let name = CNContactFormatter.string(
            from: contact, style: .fullName
        ) ?? ""
        return SyncContactRecord(
            id: contact.identifier,
            displayName: name,
            familyName: contact.familyName.isEmpty
                ? nil : contact.familyName,
            givenName: contact.givenName.isEmpty
                ? nil : contact.givenName,
            organization: contact.organizationName.isEmpty
                ? nil : contact.organizationName,
            phones: contact.phoneNumbers.map {
                SyncLabeledValue(
                    label: $0.label.map {
                        CNLabeledValue<NSString>.localizedString(
                            forLabel: $0
                        )
                    } ?? "",
                    value: $0.value.stringValue
                )
            },
            emails: contact.emailAddresses.map {
                SyncLabeledValue(
                    label: $0.label.map {
                        CNLabeledValue<NSString>.localizedString(
                            forLabel: $0
                        )
                    } ?? "",
                    value: $0.value as String
                )
            },
            groups: groups
        )
    }

    /// 分组名反查：逐组取成员标识建映射（分组数
    /// 量级小，成本可控）；取不到分组就回空表（分
    /// 组只是记录的一个字段，缺了不拦整本同步）
    private func groupNamesByContactID() -> [String: [String]] {
        guard let groups = try? store.groups(matching: nil)
        else { return [:] }
        var map: [String: [String]] = [:]
        for group in groups {
            let predicate = CNContact.predicateForContactsInGroup(
                withIdentifier: group.identifier
            )
            var keys: [CNKeyDescriptor] = []
            keys.append(CNContactIdentifierKey as NSString)
            guard let members = try? store.unifiedContacts(
                matching: predicate, keysToFetch: keys
            ) else { continue }
            for member in members {
                map[member.identifier, default: []].append(group.name)
            }
        }
        return map
    }
}

// MARK: - 剪贴板执行器（设备扩容批一）

/// 剪贴板现读现写：内容在别家 App 手里时，读取动作
/// 本身会触发系统粘贴提示横幅（iOS 16+ 的规矩，数据
/// 源说明里已如实写明、不装无感）；只探测类型
/// （hasStrings 等）不触发提示，故先探测后取内容，
/// 非文字内容如实回类型、不编内容。写完回读比对才
/// 报成功（写纪律与既有写工具同）。
final class ClipboardEngine: @unchecked Sendable {

    /// clipboard_get 结果：文字原样回；链接回其文字
    /// 形态；只有图片时回类型说明、无内容
    func getResult() -> JSONValue {
        let board = UIPasteboard.general
        var result: [String: JSONValue] = [
            "readAt": .string(DeviceISO8601.format(Date())),
        ]
        if board.hasStrings, let text = board.string {
            result["type"] = .string("text")
            result["text"] = .string(text)
        } else if board.hasURLs, let url = board.url {
            result["type"] = .string("url")
            result["text"] = .string(url.absoluteString)
        } else if board.hasImages {
            result["type"] = .string("image")
            result["note"] = .string("剪贴板里是一张图片，没有文字内容")
        } else {
            result["type"] = .string("empty")
            result["note"] = .string("剪贴板是空的")
        }
        return .object(result)
    }

    /// clipboard_set：写入后回读比对（回读自家刚写
    /// 的内容不触发系统提示）；不一致即失败
    func setClipboard(
        _ args: ClipboardSetArgs
    ) throws -> (objectID: String, result: JSONValue) {
        let board = UIPasteboard.general
        board.string = args.text
        guard board.string == args.text else {
            throw DeviceToolError.failed("写入后核对不一致，不报成功")
        }
        return ("clipboard", .object([
            "written": .bool(true),
            "verified": .bool(true),
            "characters": .number(Double(args.text.count)),
        ]))
    }

    /// 详情页本地预览（页面只在用户亲手点按钮时调，
    /// 因为这一读同样可能触发系统粘贴提示）
    func currentText() -> String? {
        UIPasteboard.general.string
    }
}

// MARK: - 沙盒文件执行器（设备扩容批一）

/// App 自有 Documents 区的文本文件列/读/写：路径先
/// 过 Core 的 SandboxPath 规范化（防越界纯逻辑），落
/// 到 URL 后再做一次「解析符号链接＋标准化后仍在根
/// 内」的前缀校验，双保险。写完回读字节比对才报成
/// 功；二进制/超限如实报错、不静默截断。
final class SandboxFilesEngine: @unchecked Sendable {

    private var rootURL: URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
    }

    /// 规范相对路径 → 根内 URL（越界即 invalidArguments）
    private func resolvedURL(
        forNormalizedPath path: String
    ) throws -> URL {
        var url = rootURL
        for component in path.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        let root = rootURL.resolvingSymlinksInPath()
            .standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath()
            .standardizedFileURL.path
        guard resolved == root || resolved.hasPrefix(root + "/")
        else {
            throw DeviceToolError.invalidArguments(
                "路径越出了 OneDay 文件夹的范围"
            )
        }
        return url
    }

    /// 文件元数据对象（列表条目与写回放共用）：只
    /// 含名/路径/大小/修改时刻，不含内容
    static func fileObject(
        _ item: DeviceFileItem
    ) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "name": .string(item.name),
            "path": .string(item.path),
            "isDirectory": .bool(item.isDirectory),
            "modifiedAt": .string(
                DeviceISO8601.format(item.modifiedAt)
            ),
        ]
        if !item.isDirectory {
            object["sizeBytes"] = .number(Double(item.sizeBytes))
        }
        return object
    }

    /// 某相对路径的当前条目（不在/越界回 nil）：写
    /// 回放与详情页共用
    func item(relativePath: String) -> DeviceFileItem? {
        guard !relativePath.isEmpty,
              let url = try? resolvedURL(
                forNormalizedPath: relativePath
              ),
              let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey,
                .contentModificationDateKey,
              ])
        else { return nil }
        return DeviceFileItem(
            name: url.lastPathComponent,
            path: relativePath,
            isDirectory: values.isDirectory ?? false,
            sizeBytes: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate
                ?? Date(timeIntervalSince1970: 0)
        )
    }

    /// 一层列表（不递归；工具与详情页共用）：目录
    /// 在前、同类按名序，输出确定性
    func listItems(
        relativePath: String
    ) throws -> [DeviceFileItem] {
        let url = try resolvedURL(forNormalizedPath: relativePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDirectory
        ) else {
            throw DeviceToolError.failed(
                relativePath.isEmpty
                    ? "文件夹不存在"
                    : "文件夹不存在：\(relativePath)"
            )
        }
        guard isDirectory.boolValue else {
            throw DeviceToolError.failed(
                "「\(relativePath)」是文件，不是文件夹"
            )
        }
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .fileSizeKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw DeviceToolError.failed(
                "读取文件夹失败：\(error.localizedDescription)"
            )
        }
        let prefix = relativePath.isEmpty ? "" : relativePath + "/"
        let items = children.map { child -> DeviceFileItem in
            let values = try? child.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey,
                .contentModificationDateKey,
            ])
            return DeviceFileItem(
                name: child.lastPathComponent,
                path: prefix + child.lastPathComponent,
                isDirectory: values?.isDirectory ?? false,
                sizeBytes: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate
                    ?? Date(timeIntervalSince1970: 0)
            )
        }
        return items.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedStandardCompare($1.name)
                == .orderedAscending
        }
    }

    /// files_list 结果：条目上限在 Core 常量，超了
    /// 截断并标 truncated（不装全给了）
    func listResult(_ args: FilesListArgs) throws -> JSONValue {
        let items = try listItems(relativePath: args.path)
        let capped = Array(
            items.prefix(SandboxPath.maxListEntries)
        )
        var result: [String: JSONValue] = [
            "path": .string(args.path),
            "readAt": .string(DeviceISO8601.format(Date())),
            "count": .number(Double(capped.count)),
            "entries": .array(
                capped.map { .object(Self.fileObject($0)) }
            ),
        ]
        if items.count > capped.count {
            result["truncated"] = .bool(true)
        }
        return .object(result)
    }

    /// 读文本（工具与详情页预览共用）：不存在/是目
    /// 录/超限/非 UTF-8 文本一律如实报错
    func readText(relativePath: String) throws -> String {
        let url = try resolvedURL(forNormalizedPath: relativePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDirectory
        ) else {
            throw DeviceToolError.failed("文件不存在：\(relativePath)")
        }
        guard !isDirectory.boolValue else {
            throw DeviceToolError.failed(
                "「\(relativePath)」是文件夹，读不出文本"
            )
        }
        let attributes = try? FileManager.default
            .attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value
            ?? 0
        guard size <= SandboxPath.maxContentBytes else {
            throw DeviceToolError.failed(
                "文件超过 256 KB 上限，不整份读取"
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DeviceToolError.failed(
                "读取文件失败：\(error.localizedDescription)"
            )
        }
        guard let text = String(data: data, encoding: .utf8)
        else {
            throw DeviceToolError.failed(
                "这个文件不是文本内容，读不出文字"
            )
        }
        return text
    }

    /// files_read 结果：内容＋字节数＋现读时刻
    func readResult(_ args: FilesReadArgs) throws -> JSONValue {
        let text = try readText(relativePath: args.path)
        return .object([
            "path": .string(args.path),
            "readAt": .string(DeviceISO8601.format(Date())),
            "bytes": .number(Double(text.utf8.count)),
            "content": .string(text),
        ])
    }

    /// files_write：父目录自动建、原子写、回读逐字
    /// 节比对才报成功；objectID＝规范相对路径（账
    /// 本只存路径这一元数据，不存内容）
    func writeFile(
        _ args: FilesWriteArgs
    ) throws -> (objectID: String, result: JSONValue) {
        let url = try resolvedURL(forNormalizedPath: args.path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDirectory
        ), isDirectory.boolValue {
            throw DeviceToolError.failed(
                "同名文件夹已存在，写不进去：\(args.path)"
            )
        }
        let data = Data(args.content.utf8)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw DeviceToolError.failed(
                "写入文件失败：\(error.localizedDescription)"
            )
        }
        guard let back = try? Data(contentsOf: url),
              back == data
        else {
            throw DeviceToolError.failed("写入后核对不一致，不报成功")
        }
        return (args.path, .object([
            "path": .string(args.path),
            "written": .bool(true),
            "verified": .bool(true),
            "bytes": .number(Double(data.count)),
        ]))
    }
}

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
        let settings = await withCheckedContinuation {
            (continuation:
                CheckedContinuation<UNNotificationSettings, Never>
            ) in
            UNUserNotificationCenter.current()
                .getNotificationSettings { settings in
                    continuation.resume(returning: settings)
                }
        }
        let state = translate(settings.authorizationStatus)
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

// MARK: - 工具分发器（执行前复查＋幂等＋回读）

/// 一次桥下发调用的执行：先按注册时口径复查（权限
/// 仍可用、开关仍开——注册后用户可能刚关，执行时以
/// 当下为准），写工具先过 App 侧幂等账本（24 小时
/// 同 key 回原对象、不真写第二次），执行后结果必
/// 含回读字段（在各执行器内完成）。账本只存 key 与
/// 对象 id、落 UserDefaults，不存内容。
final class DeviceToolDispatcher: @unchecked Sendable {
    let events = EventKitEngine()
    let contacts = ContactsEngine()
    let clipboard = ClipboardEngine()
    let files = SandboxFilesEngine()
    let alarms = AlarmEngine()
    let notifications = NotificationEngine()
    let opener = OpenTargetEngine()

    private static let ledgerKey = "device.writeKeyLedger.v1"

    private func loadLedger() -> [WriteKeyRecord] {
        guard let data = UserDefaults.standard.data(
            forKey: Self.ledgerKey
        ),
        let records = try? JSONDecoder().decode(
            [WriteKeyRecord].self, from: data
        ) else { return [] }
        return records
    }

    private func saveLedger(_ records: [WriteKeyRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.ledgerKey)
        }
    }

    /// 幂等回放结果组装：原对象还在就带回读、不在
    /// 就只回 objectId 并标明对象已不在（如实）
    private func replayResult(
        tool: String, objectID: String?
    ) -> JSONValue {
        var result: [String: JSONValue] = [
            "idempotentReplay": .bool(true),
            "tool": .string(tool),
        ]
        if let objectID {
            result["objectId"] = .string(objectID)
            switch tool {
            case "calendar_create_event", "calendar_update_event":
                if let event = events.eventObjectByID(objectID) {
                    result["event"] = .object(event)
                }
            case "reminders_create", "reminders_complete":
                if let reminder = events.reminderObjectByID(objectID) {
                    result["reminder"] = .object(reminder)
                }
            case "files_write":
                // 回放只带文件元数据（还在不在、多大），
                // 不重读内容——内容不该在回放里再过境
                if let item = files.item(relativePath: objectID) {
                    result["file"] = .object(
                        SandboxFilesEngine.fileObject(item)
                    )
                }
            case "alarm_set":
                // 回放带闹钟当前回读（还在册才有），
                // 不重设第二个闹钟
                if let object = alarms.alarmObject(id: objectID) {
                    result["alarm"] = .object(object)
                }
            case "alarm_cancel":
                // 回放时复核目标确实已不在系统列表
                result["stillAbsent"] = .bool(
                    alarms.alarmObject(id: objectID) == nil
                )
            default:
                break
            }
        }
        return .object(result)
    }

    func execute(
        call: DeviceIncomingCall,
        permissions: [DeviceSourceID: DevicePermissionState],
        agentCallEnabled: [DeviceSourceID: Bool]
    ) async -> (result: JSONValue?, error: DeviceToolError?) {
        guard let spec = DeviceToolRegistry.spec(call.tool) else {
            return (nil, .toolUnavailable("未知工具 \(call.tool)"))
        }
        guard let source = spec.source,
              DeviceSourceDirectory.descriptor(source).isWired else {
            return (nil, .toolUnavailable("工具 \(call.tool) 尚未接线"))
        }
        // 通知无同步读状态 API：判门前先刷新真状态，
        // 不许拿进页时的缓存快照放行或误拒（§113）
        var permissions = permissions
        if source == .notifications {
            permissions[.notifications] =
                await NotificationEngine.readSystemState()
        }
        // 执行时复查：注册只是快照，当下为准
        let state = permissions[source] ?? .notDetermined
        guard state.isUsable else {
            return (nil, .permissionDenied(
                "\(DeviceSourceDirectory.descriptor(source).name)的系统权限当前是「\(state.label)」，无法执行"
            ))
        }
        guard agentCallEnabled[source] ?? false else {
            return (nil, .toolUnavailable(
                "\(DeviceSourceDirectory.descriptor(source).name)的智能体调用已关闭"
            ))
        }
        do {
            switch call.tool {
            case "calendar_list_events":
                let window = try CalendarListWindow.parse(call.arguments)
                return (events.listEventsResult(window: window), nil)
            case "calendar_create_event":
                let args = try CalendarCreateArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try events.createEvent(args) }
            case "calendar_update_event":
                let args = try CalendarUpdateArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try events.updateEvent(args) }
            case "reminders_list":
                return (await events.listRemindersResult(), nil)
            case "reminders_create":
                let args = try ReminderCreateArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try events.createReminder(args) }
            case "reminders_complete":
                let args = try ReminderCompleteArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) {
                    try events.setReminderCompleted(
                        id: args.reminderID, completed: true
                    )
                }
            case "contacts_search":
                let args = try ContactsSearchArgs.parse(call.arguments)
                return (try contacts.search(args), nil)
            case "clipboard_get":
                return (clipboard.getResult(), nil)
            case "clipboard_set":
                let args = try ClipboardSetArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try clipboard.setClipboard(args) }
            case "files_list":
                let args = try FilesListArgs.parse(call.arguments)
                return (try files.listResult(args), nil)
            case "files_read":
                let args = try FilesReadArgs.parse(call.arguments)
                return (try files.readResult(args), nil)
            case "files_write":
                let args = try FilesWriteArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try files.writeFile(args) }
            case "alarm_set":
                let args = try AlarmSetArgs.parse(call.arguments)
                return try await writeWithLedgerAsync(
                    key: args.idempotencyKey, tool: call.tool
                ) { try await alarms.setAlarm(args) }
            case "alarm_list":
                return (alarms.listResult(), nil)
            case "alarm_cancel":
                let args = try AlarmCancelArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try alarms.cancelAlarm(args) }
            case "notify_post":
                let args = try NotifyPostArgs.parse(call.arguments)
                return try await writeWithLedgerAsync(
                    key: args.idempotencyKey, tool: call.tool
                ) { try await notifications.post(args) }
            case "open_target":
                let args = try OpenTargetArgs.parse(call.arguments)
                return try await writeWithLedgerAsync(
                    key: args.idempotencyKey, tool: call.tool
                ) { try await opener.open(args) }
            default:
                return (nil, .toolUnavailable("工具 \(call.tool) 尚未接线"))
            }
        } catch let error as DeviceToolError {
            return (nil, error)
        } catch {
            return (nil, .failed(error.localizedDescription))
        }
    }

    /// 写工具统一路径：账本命中→回放；未命中→执行
    /// （执行器内含回读验证）→记账→回结果
    private func writeWithLedger(
        key: String, tool: String,
        perform: () throws -> (objectID: String, result: JSONValue)
    ) throws -> (result: JSONValue?, error: DeviceToolError?) {
        let now = Date()
        let records = loadLedger()
        if let hit = WriteKeyLedger.lookup(records, key: key, now: now) {
            return (replayResult(tool: tool, objectID: hit.objectID), nil)
        }
        let (objectID, result) = try perform()
        saveLedger(WriteKeyLedger.recording(
            records, key: key, tool: tool, objectID: objectID, now: now
        ))
        return (result, nil)
    }

    /// 写工具统一路径的异步形（批二动作型工具用）：
    /// 账本语义与同步形逐字一致——命中回放、未命中
    /// 执行（引擎内含回读验证）后记账
    private func writeWithLedgerAsync(
        key: String, tool: String,
        perform: () async throws
            -> (objectID: String, result: JSONValue)
    ) async throws -> (result: JSONValue?, error: DeviceToolError?) {
        let now = Date()
        let records = loadLedger()
        if let hit = WriteKeyLedger.lookup(
            records, key: key, now: now
        ) {
            return (
                replayResult(tool: tool, objectID: hit.objectID),
                nil
            )
        }
        let (objectID, result) = try await perform()
        saveLedger(WriteKeyLedger.recording(
            records, key: key, tool: tool,
            objectID: objectID, now: now
        ))
        return (result, nil)
    }
}
