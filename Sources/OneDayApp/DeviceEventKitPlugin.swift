import EventKit
import Foundation
import OneDayCore

// MARK: - EventKit 执行器（日历＋提醒同 store）

/// 日历/提醒的框架执行：工具调用与详情页 L1 读共
/// 用这一份（同一数据源、同一翻译，不许两处各读各
/// 的）。写纪律落在这里：回读验证——写完必须重新取
/// 回对象才许报成功；回读不到即失败原文。
final class EventKitEngine: @unchecked Sendable {
    /// §468：store 不再终身一只——授权状态变化后
    /// 旧实例的源缓存可能停在旧授权面，官方口径是
    /// 授权落定后以新实例读、读前 refreshSources-
    /// IfNecessary 刷新源。授权请求成功即重建，
    /// 每次框架读入口先刷新源
    private(set) var store = EKEventStore()

    private func rebuildStore() {
        store = EKEventStore()
    }

    // MARK: 授权

    func requestCalendarAccess() async -> DevicePermissionState {
        _ = try? await store.requestFullAccessToEvents()
        let state = DevicePermissions.calendarState()
        if state.isUsable { rebuildStore() }
        return state
    }

    func requestRemindersAccess() async -> DevicePermissionState {
        _ = try? await store.requestFullAccessToReminders()
        let state = DevicePermissions.remindersState()
        if state.isUsable { rebuildStore() }
        return state
    }

    // MARK: 日历读

    func events(from start: Date, to end: Date) -> [DeviceAgendaEvent] {
        store.refreshSourcesIfNecessary()
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
        store.refreshSourcesIfNecessary()
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
        store.refreshSourcesIfNecessary()
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
    /// 完成/已过期，Core 同口径计算）。读取失败向
    /// 上抛（§468）：提醒是全量整换，读不到绝不许
    /// 拿空集去把服务器副本清零
    func reminderSyncSnapshot() async throws -> (
        records: [SyncReminderRecord],
        aggregates: SyncReminderAggregates
    ) {
        let all = try await fetchAllReminders()
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

    /// continuation 一次性 resume 盒（§468）：框架
    /// 回调与超时兜底两路竞速，先到者赢、后到者丢
    /// 弃——CheckedContinuation 重复 resume 是致命
    /// 错误，必须有这层守卫
    private final class ResumeOnceBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation:
            CheckedContinuation<ReminderBox, Error>?

        init(_ continuation: CheckedContinuation<ReminderBox, Error>) {
            self.continuation = continuation
        }

        func resume(returning box: ReminderBox) {
            take()?.resume(returning: box)
        }

        func resume(throwing error: Error) {
            take()?.resume(throwing: error)
        }

        private func take()
            -> CheckedContinuation<ReminderBox, Error>?
        {
            lock.lock()
            defer { lock.unlock() }
            let taken = continuation
            continuation = nil
            return taken
        }
    }

    /// §468：fetchReminders 的完成回调在系统侧丢
    /// 失时，旧写法让这一轮同步永久挂起（continu-
    /// ation 永不 resume、进度残留锁死后续每一
    /// 轮）。加 20 秒超时兜底：超时按失败抛错，本
    /// 轮落账失败、下轮照常——绝不拿空集冒充读到
    private func fetchAllReminders() async throws -> [EKReminder] {
        store.refreshSourcesIfNecessary()
        let calendars = store.calendars(for: .reminder)
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: calendars)
        let box = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<ReminderBox, Error>)
            in
            let once = ResumeOnceBox(continuation)
            store.fetchReminders(matching: predicate) { reminders in
                once.resume(
                    returning: ReminderBox(reminders: reminders ?? [])
                )
            }
            Task {
                try? await Task.sleep(for: .seconds(20))
                once.resume(
                    throwing: DeviceToolError.failed(
                        "读取提醒超时（系统没有回话）"
                    )
                )
            }
        }
        return box.reminders
    }

    func reminderItems() async -> [DeviceReminderItem] {
        let all = (try? await fetchAllReminders()) ?? []
        return all.map(Self.reminderItem)
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
        let all = (try? await fetchAllReminders()) ?? []
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


extension EventKitEngine: DeviceCapabilityPlugin {
    static let capabilityDomain = "eventkit"
}
