import Contacts
import EventKit
import Foundation
import OneDayCore

/// 系统权限翻译层：EK/CN 的授权状态逐件翻成 Core
/// 的 DevicePermissionState（呈现与注册载荷只认这
/// 一套枚举）。健康/家庭批二未接线、从未申请，如实
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
}
