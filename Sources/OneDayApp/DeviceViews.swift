import EventKit
import EventKitUI
import OneDayCore
import OneDayDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 本机连接器详情页组（0.34.0 批一，设计档 §6.2 通
/// 用骨架）：状态头（系统权限行＋调用去向行＋「允
/// 许智能体调用」开关＋设备会话态＋最近调用元数据）
/// → 内容区（逐件形态）→ 口径脚注。被拒/未授权时内
/// 容区换降级说明、不留空白页；每次进页重读系统权
/// 限（不缓存上次的绿）。
/// 0.36.3（详情页语法重做，用户 18:05 点名）：状
/// 态头按五段式模板重排——瓷砖＋名称＋一句话能力
/// 领头（居中）、系统权限行带可操作控件（S4）、
/// 开关副文压一行、门面口径下沉节脚注；三页撤
/// .navigationTitle 居中标题、内容领头。
///
/// 诚实边界（本版）：设备会话在线只说明手机侧通道
/// 活着；Hermes 侧工具门面注册留收官窗口——状态头
/// 与总览页都明说「智能体实际调用待服务器侧开通」，
/// 不许写成已可调用。

// MARK: - 瓷砖（0.36.0，宪法 §4／审计 C7）
// 苹果应用图标画法：白底 squircle＋标志元素字形
// ——字形用各件的标志色（原色表语义由「底色」改
// 为「字形色」），容器走 Design 层 AppSymbolTile
// 单一实现。旧「饱和纯色块压白字形」自本版退役
// （既非官方原图、亦非苹果画法）。

struct DeviceSymbolTile: View {
    let symbol: String
    let colorHex: UInt32
    var size: CGFloat = 40

    var body: some View {
        AppSymbolTile(symbol: symbol, glyphColor: tileColor, size: size)
    }

    private var tileColor: Color {
        Color(
            red: Double((colorHex >> 16) & 0xFF) / 255,
            green: Double((colorHex >> 8) & 0xFF) / 255,
            blue: Double(colorHex & 0xFF) / 255
        )
    }
}

// MARK: - 状态头（五件共用）

struct DeviceStatusHeader: View {
    @Environment(AppState.self) private var appState
    let source: DeviceSourceID

    private var controller: DeviceSessionController { appState.deviceSession }
    private var descriptor: DeviceSourceDescriptor {
        DeviceSourceDirectory.descriptor(source)
    }
    private var permission: DevicePermissionState {
        controller.permissions[source] ?? .notDetermined
    }

    var body: some View {
        Group {
            // 领头段（0.36.3，详情页语法五段式）：
            // 居中大真图标（苹果画法瓷砖 64）→名称→
            // 一句话能力说明。旧设置式分组头＋居中
            // 导航标题退役（对照授权页参考图）
            Section {
                VStack(spacing: OneDayMetrics.spacingS) {
                    DeviceSymbolTile(
                        symbol: descriptor.tileSymbol,
                        colorHex: descriptor.tileColorHex, size: 64
                    )
                    Text(descriptor.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    Text(descriptor.blurb)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OneDayMetrics.spacingSM)
            }
            .listRowBackground(Color.clear)

            Section {
                permissionRow
                Toggle(isOn: agentCallBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("允许智能体调用")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        // 0.36.3：副文压到一行短文案
                        // （capabilityLine），长说明
                        // agentNote 不再成段塞卡
                        Text(descriptor.capabilityLine)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } header: {
                headerText("授权与调用")
            }
            .listRowBackground(Palette.surface)

            Section {
                detailRow(
                    "设备会话",
                    controller.sessionOnline ? "在线" : "离线"
                )
                if let entry = controller.lastCallEntries[source] {
                    detailRow("最近调用", entry.summaryLine)
                    detailRow(
                        "调用时刻",
                        DisplayDate.dateTime(
                            Date(timeIntervalSince1970: entry.at)
                        )
                    )
                    detailRow("调用工具", entry.tool)
                } else {
                    detailRow("最近调用", "暂无调用记录")
                }
                if let error = controller.sessionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            } header: {
                headerText("通道状态")
            } footer: {
                // 0.36.3：门面注册口径由卡内成段文字
                // 下沉为本节页脚小字（一行交代）
                Text("智能体实际调用待服务器侧门面注册开通；开通前数据不会被调用。")
            }
            .listRowBackground(Palette.surface)
        }
        .listRowInsets(
            EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        )
    }

    /// 系统权限行（0.36.3，续编 S4 落地）：行必须
    /// 带可操作控件——未授权给「去开启」（触发系
    /// 统请求）、被拒/受限给「去设置」、已授权整行
    /// 可点进系统设置管理。旧形态只有「已授权」三
    /// 字文本、无任何控件（用户 18:05 点名）退役。
    @ViewBuilder
    private var permissionRow: some View {
        switch permission {
        case .notDetermined:
            HStack(spacing: OneDayMetrics.spacingSM) {
                permissionTitle
                Spacer(minLength: OneDayMetrics.spacingS)
                Text(permission.label)
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                Button("去开启") {
                    Task { await controller.requestAccess(for: source) }
                }
                .buttonStyle(.odSecondary)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
        case .denied, .restricted:
            HStack(spacing: OneDayMetrics.spacingSM) {
                permissionTitle
                Spacer(minLength: OneDayMetrics.spacingS)
                Text(permission.label)
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                Button("去设置") { openSystemSettings() }
                    .buttonStyle(.odSecondary)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
        default:
            Button {
                openSystemSettings()
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    permissionTitle
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Text(permission.label)
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityHint("在系统设置中管理此权限")
        }
    }

    private var permissionTitle: some View {
        Text("系统权限")
            .font(.rowTitleL)
            .foregroundStyle(Palette.ink)
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var agentCallBinding: Binding<Bool> {
        Binding(
            get: { controller.agentCallEnabled[source] ?? false },
            set: { controller.setAgentCallEnabled(source, $0) }
        )
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(title)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }
}

private func headerText(_ title: String) -> some View {
    Text(title)
        .font(.sectionLabel)
        .foregroundStyle(Palette.inkSecondary)
        .textCase(nil)
}

private let deviceRowInsets = EdgeInsets(
    top: 0, leading: 20, bottom: 0, trailing: 20
)

/// 未授权/被拒时的降级说明（内容区替换，不留空白页）
private struct DevicePermissionGate: View {
    let source: DeviceSourceID
    let permission: DevicePermissionState

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                Text(gateTitle)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(gateMessage)
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                if source == .calendar, permission == .writeOnly {
                    Text("在系统设置里改成「完全访问」后，这里就能看到安排。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingS)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(deviceRowInsets)
    }

    private var gateTitle: String {
        switch permission {
        case .notDetermined: return "还没有授权"
        case .denied, .restricted: return "系统权限被拒"
        case .writeOnly: return "当前只有写入权限"
        default: return "暂不可用"
        }
    }

    /// 降级说明（0.36.3 瘦身）：一句事实＋一个下
    /// 一步，不成段（续编 S11 空态句式同理）
    private var gateMessage: String {
        let name = DeviceSourceDirectory.descriptor(source).name
        switch permission {
        case .notDetermined:
            return "点上方「去开启」，系统会问你是否允许读取\(name)。"
        case .denied, .restricted:
            return "到系统设置打开\(name)权限后，回来下拉刷新即可。"
        case .writeOnly:
            return "当前只有写入权限，看不到已有安排。"
        default:
            return "当前状态下读不到数据。"
        }
    }
}

/// 口径脚注（详情页尾）
private struct DeviceFootnote: View {
    let source: DeviceSourceID

    var body: some View {
        Section {
            Text(DeviceSourceDirectory.descriptor(source).footnote)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(deviceRowInsets)
    }
}

// MARK: - 日历详情（议程形态，今起 14 天）

/// 议程按日分组（具名结构体承 ForEach 的 Identifiable）
private struct AgendaDayGroup: Identifiable {
    let day: Date
    let events: [DeviceAgendaEvent]
    var id: Date { day }
}

struct CalendarDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var days: [AgendaDayGroup] = []
    @State private var showNewEvent = false

    private var controller: DeviceSessionController { appState.deviceSession }
    private var permission: DevicePermissionState {
        controller.permissions[.calendar] ?? .notDetermined
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .calendar)
            if permission.isUsable {
                agendaSections
            } else {
                DevicePermissionGate(source: .calendar, permission: permission)
            }
            DeviceFootnote(source: .calendar)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.3：撤居中标题，领头段（瓷砖＋名称）即页头
        .toolbar {
            if permission.isUsable {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建日程")
                }
            }
        }
        .sheet(isPresented: $showNewEvent) {
            EventEditView(
                store: controller.dispatcher.events.store
            ) {
                showNewEvent = false
                load()
            }
        }
        .task { load() }
        .refreshable { load() }
    }

    @ViewBuilder
    private var agendaSections: some View {
        if days.isEmpty {
            Section {
                Text("接下来 14 天没有安排。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        ForEach(days) { group in
            Section {
                if group.events.isEmpty {
                    Text("这一天没有安排")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(group.events) { event in
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Circle()
                            .fill(Color(hex: event.calendarColorHex))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Text(eventSubline(event))
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
            } header: {
                headerText(dayTitle(group.day))
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
    }

    private func eventSubline(_ event: DeviceAgendaEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var text = event.isAllDay
            ? "全天"
            : "\(formatter.string(from: event.start)) – \(formatter.string(from: event.end))"
        text += " · \(event.calendarName)"
        if let location = event.location, !location.isEmpty {
            text += " · \(location)"
        }
        return text
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        if calendar.isDateInToday(day) {
            return "今天 · \(formatter.string(from: day))"
        }
        if calendar.isDateInTomorrow(day) {
            return "明天 · \(formatter.string(from: day))"
        }
        return formatter.string(from: day)
    }

    private func load() {
        guard permission.isUsable else {
            days = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 14, to: start) ?? start
        let events = controller.dispatcher.events.events(from: start, to: end)
        var grouped: [Date: [DeviceAgendaEvent]] = [:]
        for event in events {
            grouped[calendar.startOfDay(for: event.start), default: []]
                .append(event)
        }
        var ordered: [AgendaDayGroup] = grouped
            .map { AgendaDayGroup(day: $0.key, events: $0.value) }
            .sorted { $0.day < $1.day }
        // 「今天」组恒在（没安排也显一行空态，设计档口径）
        if grouped[start] == nil {
            ordered.insert(AgendaDayGroup(day: start, events: []), at: 0)
        }
        days = ordered
    }
}

/// 系统新建日程编辑器（EKEventEditViewController 桥）
private struct EventEditView: UIViewControllerRepresentable {
    let store: EKEventStore
    var onFinish: () -> Void

    func makeUIViewController(
        context: Context
    ) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: EKEventEditViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            onFinish()
        }
    }
}

// MARK: - 提醒详情（按清单分组，未完成在前）

struct RemindersDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [DeviceReminderItem] = []
    @State private var showAdd = false
    @State private var actionError: String?

    private var controller: DeviceSessionController { appState.deviceSession }
    private var permission: DevicePermissionState {
        controller.permissions[.reminders] ?? .notDetermined
    }

    private var incomplete: [DeviceReminderItem] {
        items.filter { !$0.isCompleted }
    }

    private var listNames: [String] {
        var seen: [String] = []
        for item in incomplete where !seen.contains(item.listName) {
            seen.append(item.listName)
        }
        return seen
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .reminders)
            if permission.isUsable {
                reminderSections
            } else {
                DevicePermissionGate(
                    source: .reminders, permission: permission
                )
            }
            if let actionError {
                Section {
                    Text(actionError)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(deviceRowInsets)
            }
            DeviceFootnote(source: .reminders)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.3：撤居中标题，领头段（瓷砖＋名称）即页头
        .toolbar {
            if permission.isUsable {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建提醒")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddReminderView {
                showAdd = false
                Task { await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var reminderSections: some View {
        if incomplete.isEmpty {
            Section {
                Text("没有未完成的提醒。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        ForEach(listNames, id: \.self) { listName in
            let group = incomplete.filter { $0.listName == listName }
            Section {
                ForEach(group) { item in
                    reminderRow(item)
                }
            } header: {
                headerText("\(listName) · \(group.count) 项未完成")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
    }

    private func reminderRow(_ item: DeviceReminderItem) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Button {
                Task { await toggle(item) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("勾完成：\(item.title)")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                if let subline = reminderSubline(item) {
                    Text(subline)
                        .font(.footnote)
                        .foregroundStyle(
                            item.isOverdue ? Palette.danger
                                : Palette.inkSecondary
                        )
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private func reminderSubline(_ item: DeviceReminderItem) -> String? {
        guard let due = item.due else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        if item.isOverdue {
            let days = Calendar.current.dateComponents(
                [.day], from: due, to: Date()
            ).day ?? 0
            return days > 0
                ? "已过期 \(days) 天 · \(formatter.string(from: due))"
                : "已过期 · \(formatter.string(from: due))"
        }
        return formatter.string(from: due)
    }

    private func toggle(_ item: DeviceReminderItem) async {
        do {
            _ = try controller.dispatcher.events.setReminderCompleted(
                id: item.id, completed: true
            )
            actionError = nil
        } catch let error as DeviceToolError {
            actionError = error.message
        } catch {
            actionError = "勾完成失败"
        }
        await load()
    }

    private func load() async {
        guard permission.isUsable else {
            items = []
            return
        }
        items = await controller.dispatcher.events.reminderItems()
    }
}

/// 新建提醒小表（本地动作：标题＋可选到期）
private struct AddReminderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDue = false
    @State private var due = Date().addingTimeInterval(3600)
    @State private var errorLine: String?
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("提醒标题", text: $title)
                Toggle("设到期时间", isOn: $hasDue)
                if hasDue {
                    DatePicker(
                        "到期", selection: $due,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                if let errorLine {
                    Text(errorLine)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            }
            .navigationTitle("新建提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(
                            title.trimmingCharacters(
                                in: .whitespaces
                            ).isEmpty
                        )
                }
            }
        }
    }

    private func save() {
        do {
            try appState.deviceSession.dispatcher.events
                .createReminderSimple(
                    title: title.trimmingCharacters(in: .whitespaces),
                    due: hasDue ? due : nil
                )
            onDone()
            dismiss()
        } catch let error as DeviceToolError {
            errorLine = error.message
        } catch {
            errorLine = "新建失败"
        }
    }
}

// MARK: - 通讯录详情（搜索现查，纯本地渲染）

struct ContactsDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [DeviceContactItem] = []
    @State private var query = ""
    @State private var loadError: String?
    @State private var selected: DeviceContactItem?

    private var controller: DeviceSessionController { appState.deviceSession }
    private var permission: DevicePermissionState {
        controller.permissions[.contacts] ?? .notDetermined
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .contacts)
            if permission.isUsable {
                contactsSections
            } else {
                DevicePermissionGate(
                    source: .contacts, permission: permission
                )
            }
            DeviceFootnote(source: .contacts)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.3：撤居中标题，领头段（瓷砖＋名称）即页头
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索联系人"
        )
        .onChange(of: query) { _, _ in load() }
        .sheet(item: $selected) { contact in
            NavigationStack { contactDetail(contact) }
        }
        .task { load() }
        .refreshable { load() }
    }

    @ViewBuilder
    private var contactsSections: some View {
        if permission == .limited {
            Section {
                Text("仅显示你勾选给 OneDay 的联系人（当前 \(items.count) 位）——受限授权下系统只给这部分，这是真实子集、不是全量。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        if let loadError {
            Section {
                Text(loadError)
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        } else if items.isEmpty {
            Section {
                Text(query.isEmpty ? "没有联系人。" : "没有匹配「\(query)」的联系人。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        } else {
            Section {
                ForEach(items) { contact in
                    Button {
                        selected = contact
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .font(.rowTitleL)
                                    .foregroundStyle(Palette.ink)
                                if let phone = contact.phones.first {
                                    Text(phone)
                                        .font(.footnote)
                                        .foregroundStyle(
                                            Palette.inkSecondary
                                        )
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.inkSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(
                            minHeight: OneDayMetrics.settingsRowHeight
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            } header: {
                headerText("联系人 · \(items.count)")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
    }

    private func contactDetail(_ contact: DeviceContactItem) -> some View {
        List {
            Section {
                ForEach(contact.phones, id: \.self) { phone in
                    labeledRow("电话", phone)
                }
                ForEach(contact.emails, id: \.self) { email in
                    labeledRow("邮箱", email)
                }
                if let organization = contact.organization {
                    labeledRow("公司", organization)
                }
                if contact.phones.isEmpty && contact.emails.isEmpty {
                    Text("这位联系人没有电话或邮箱。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.0（§5／审计 C9）：撤手写关闭（走系统
        // 下拉手势）；标题是联系人名＝内容身份本身、
        // 非通用栏题，保留（台账 E2 豁免候选）
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .textSelection(.enabled)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private func load() {
        guard permission.isUsable else {
            items = []
            return
        }
        do {
            let engine = controller.dispatcher.contacts
            items = query.trimmingCharacters(in: .whitespaces).isEmpty
                ? try engine.allContacts()
                : try engine.searchLocal(query: query)
            loadError = nil
        } catch let error as DeviceToolError {
            loadError = error.message
            items = []
        } catch {
            loadError = "通讯录读取失败"
            items = []
        }
    }
}

// MARK: - 设备与权限总览（设置页入口，设计档 §6.3）

/// 五件总览：授权状态＋调用开关汇总一张表，被拒在
/// 这里一眼可见；批二两件只显待权益、不给假入口
struct DevicePermissionsView: View {
    @Environment(AppState.self) private var appState

    private var controller: DeviceSessionController { appState.deviceSession }

    var body: some View {
        List {
            Section {
                ForEach(DeviceSourceDirectory.roster) { descriptor in
                    if descriptor.isWired {
                        NavigationLink {
                            detailDestination(descriptor.sourceID)
                        } label: {
                            overviewRow(descriptor)
                        }
                    } else {
                        overviewRow(descriptor)
                    }
                }
            } header: {
                headerText("你的设备")
            } footer: {
                Text("系统权限（iOS 管）与「允许智能体调用」（App 内开关）是两层：前者决定 App 能不能读，后者决定智能体能不能经调用拿到。健康与家庭还差系统签名权益，开通前只列名、不显数据。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)

            Section {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Text("设备会话")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Text(controller.sessionOnline ? "在线" : "离线")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                Text("会话只在 App 前台时活着；智能体实际调用还差服务器侧门面注册（下个收官窗口开通）。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            } header: {
                headerText("通道状态")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("设备与权限")
        .navigationBarTitleDisplayMode(.inline)
        .task { controller.refreshPermissions() }
    }

    private func overviewRow(
        _ descriptor: DeviceSourceDescriptor
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            DeviceSymbolTile(
                symbol: descriptor.tileSymbol,
                colorHex: descriptor.tileColorHex, size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.name)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(overviewStatus(descriptor))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .contentShape(Rectangle())
    }

    private func overviewStatus(
        _ descriptor: DeviceSourceDescriptor
    ) -> String {
        let permission = controller.permissions[descriptor.sourceID]
            ?? .notDetermined
        return DeviceRowStatus.line(
            descriptor: descriptor,
            permission: permission,
            agentCallEnabled:
                controller.agentCallEnabled[descriptor.sourceID] ?? false,
            metric: nil
        )
    }

    @ViewBuilder
    private func detailDestination(
        _ source: DeviceSourceID
    ) -> some View {
        switch source {
        case .calendar: CalendarDetailView()
        case .reminders: RemindersDetailView()
        case .contacts: ContactsDetailView()
        case .health, .home: EmptyView()
        }
    }
}

/// Color 十六进制便捷构造（瓷砖/日历色点共用）
extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
