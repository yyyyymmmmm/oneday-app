import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 同步制视图（0.36.14）：详情页「数据同步」区、
/// 首次开启说明屏、照片/步数两件的详情页。文案
/// 口径：说人话、零行话——同步什么、存哪、新到
/// 什么时候、怎么删，全部摆在明面上（规格 §6–§7）

private func syncSectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.sectionLabel)
        .foregroundStyle(Palette.inkSecondary)
        .textCase(nil)
}

private let syncRowInsets = EdgeInsets(
    top: 0, leading: 20, bottom: 0, trailing: 20
)

// MARK: - 详情页「数据同步」区

struct DeviceSyncSection: View {
    @Environment(AppState.self) private var appState
    let source: DeviceSourceID

    @State private var showIntro = false
    @State private var showTurnOffDialog = false
    @State private var showDeleteDialog = false
    @State private var actionNote: String?

    /// 只挂在五个同步数据集的详情页上（调用点已限死）
    private var dataset: DeviceSyncDataset {
        DeviceSyncDataset.fromSource(source)!
    }
    private var sync: DeviceSyncController { appState.deviceSync }
    private var session: DeviceSessionController {
        appState.deviceSession
    }
    private var permission: DevicePermissionState {
        session.permissions[source] ?? .notDetermined
    }
    private var status: DeviceSyncDatasetStatus? {
        sync.statuses[dataset]
    }
    private var enabled: Bool { sync.isSyncEnabled(dataset) }
    private var hasCopy: Bool {
        status?.synced == true || sync.receipts[dataset] != nil
    }

    private var countLine: String? {
        if let status, status.synced {
            return "\(status.itemCount) \(dataset.countUnit)"
        }
        if let receipt = sync.receipts[dataset] {
            return "\(receipt.count) \(dataset.countUnit)"
        }
        return nil
    }

    private var freshnessLine: String? {
        if let status, status.synced {
            // 桥的人话新鲜度是整句现成的（与工具答
            // 案同源），在手就原样用，不二次拼装
            if let bridgeText = status.freshness,
               !bridgeText.isEmpty
            {
                return bridgeText
            }
            if let syncedAt = status.syncedAt {
                return DeviceSyncPresentation.freshnessLine(
                    syncedAt: syncedAt, now: Date(),
                    pendingWrite: status.pendingWrite
                )
            }
        }
        if let receipt = sync.receipts[dataset] {
            return DeviceSyncPresentation.freshnessLine(
                syncedAt: Date(
                    timeIntervalSince1970: receipt.syncedAt
                ),
                now: Date(), pendingWrite: false
            )
        }
        return nil
    }

    private var rangeLine: String? {
        guard hasCopy else { return nil }
        let range = status?.authRange
            ?? sync.receipts[dataset]?.authRange
        return range == "limited"
            ? "部分（你在系统里勾选的那些）" : "全部"
    }

    /// 撤销停供明示（用户拍板口径：权限一关，智能
    /// 体立刻查不到，副本保留、重开恢复）
    private var revokedLine: String? {
        guard status?.permissionState == "revoked",
              status?.synced == true else { return nil }
        return "系统权限已经关掉：智能体现在查不到这一件了。服务器上的副本还在，重新打开权限就会恢复。"
    }

    private var expiredLine: String? {
        guard status?.expired == true, revokedLine == nil
        else { return nil }
        return "这份副本超过一天没更新了：把 App 切回前台就会自动同步一次。"
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { newValue in
                if newValue {
                    // 首次先过说明屏，看清同步什么再开
                    if DevicePreferences.syncIntroAcked(
                        for: dataset
                    ) {
                        enableAndSync()
                    } else {
                        showIntro = true
                    }
                } else if hasCopy {
                    // 有副本：关开关时问清副本去留
                    showTurnOffDialog = true
                } else {
                    sync.setSyncEnabled(dataset, false)
                }
            }
        )
    }

    private func enableAndSync() {
        sync.setSyncEnabled(dataset, true)
        actionNote = nil
        Task {
            _ = await sync.syncNow(
                dataset, config: appState.config
            )
        }
    }

    var body: some View {
        Section {
            Toggle(isOn: toggleBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("同步到我的服务器")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(
                        enabled
                            ? "开着：整份清单有一份副本在你自己的服务器上"
                            : "关着：服务器上没有这一件的副本"
                    )
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                }
            }

            if enabled {
                if let countLine {
                    syncDetailRow("服务器上的副本", countLine)
                }
                if let freshnessLine {
                    syncDetailRow("数据新到", freshnessLine)
                }
                if let rangeLine {
                    syncDetailRow("同步范围", rangeLine)
                }
                if let revokedLine {
                    warningRow(revokedLine)
                } else if let expiredLine {
                    warningRow(expiredLine)
                }
                if sync.isRunning(dataset) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        ProgressView()
                        Text(
                            sync.progress[dataset] ?? "正在同步…"
                        )
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(
                        minHeight: OneDayMetrics.settingsRowHeight
                    )
                } else {
                    Button {
                        actionNote = nil
                        Task {
                            _ = await sync.syncNow(
                                dataset, config: appState.config
                            )
                        }
                    } label: {
                        Text("立即同步")
                    }
                }
                if let error = sync.lastErrors[dataset] {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                }
                if hasCopy {
                    Button(role: .destructive) {
                        showDeleteDialog = true
                    } label: {
                        Text("删除服务器上的副本")
                    }
                }
                if let actionNote {
                    Text(actionNote)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        } header: {
            syncSectionHeader("数据同步")
        } footer: {
            Text("同步只在打开 App 时进行，不在后台跑。智能体查到的，就是「数据新到」那一行写到的时刻为止的内容。")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(syncRowInsets)
        .task {
            await sync.refreshStatus(config: appState.config)
        }
        .sheet(isPresented: $showIntro) {
            DeviceSyncIntroView(dataset: dataset) {
                DevicePreferences.setSyncIntroAcked(for: dataset)
                showIntro = false
                enableAndSync()
            } onCancel: {
                showIntro = false
            }
        }
        .confirmationDialog(
            "关掉\(dataset.label)同步？",
            isPresented: $showTurnOffDialog,
            titleVisibility: .visible
        ) {
            Button("连副本一起删掉（推荐）", role: .destructive) {
                sync.setSyncEnabled(dataset, false)
                Task {
                    _ = await sync.deleteCopy(
                        dataset, config: appState.config
                    )
                }
            }
            Button("只关同步，副本先留着") {
                sync.setSyncEnabled(dataset, false)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("服务器上还有这一件的副本：删掉后智能体就整份查不到了；只关同步的话副本保留、但不再更新。")
        }
        .confirmationDialog(
            "删掉服务器上的\(dataset.label)副本？",
            isPresented: $showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("删除副本", role: .destructive) {
                Task {
                    let ok = await sync.deleteCopy(
                        dataset, config: appState.config
                    )
                    actionNote = ok
                        ? "副本已删除。同步开关还开着，下次打开 App 会重新同步回来；不想再同步就把上面的开关关掉。"
                        : "没删成，检查服务器连接后再试。"
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删的只是服务器上的这一份副本；手机上的数据、系统权限都不动。")
        }
    }

    private func syncDetailRow(
        _ title: String, _ value: String
    ) -> some View {
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

    private func warningRow(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Palette.warning)
    }
}

// MARK: - 首次开启说明屏

/// 说明屏（规格 §6.3）：同步什么/不同步什么/存
/// 哪/怎么删，四件说清才给「开启同步」；用户只
/// 点确认，不填任何东西
struct DeviceSyncIntroView: View {
    let dataset: DeviceSyncDataset
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var syncedFields: [String] {
        switch dataset {
        case .contacts:
            return ["姓名", "电话号码", "邮箱", "公司", "所在分组"]
        case .calendar:
            return [
                "日程标题", "开始和结束时间", "属于哪个日历",
                "地点",
            ]
        case .reminders:
            return [
                "没做完的提醒：标题、到期时间、优先级、属于哪个清单",
                "两个计数：今天完成了几项、过期了几项",
            ]
        case .photos:
            return [
                "拍摄时间", "是照片还是视频", "宽高（视频还有时长）",
                "是否收藏", "在哪个相册",
                "有没有拍摄地点（只记有或没有）",
            ]
        case .motion:
            return ["每天的步数总和", "每天的距离", "每天的爬楼层数"]
        }
    }

    private var notSyncedFields: [String] {
        switch dataset {
        case .contacts:
            return ["备注", "地址", "生日", "头像照片"]
        case .calendar:
            return [
                "日程备注", "参加的人",
                "过去 30 天之前、未来 90 天之后的日程",
            ]
        case .reminders:
            return ["提醒的备注", "做完的提醒本身（只记上面的计数）"]
        case .photos:
            return ["照片和视频本身", "缩略图", "拍摄地点的具体位置"]
        case .motion:
            return ["每一步的时间", "走过的路线"]
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(dataset.label)现在只能零散地现查：问「具体某一条」能答，问「一共有多少」「哪天最忙」这类整份的问题答不了。开启同步后，App 会把下面这些内容同步一份到你自己的服务器上，智能体就能整份地查了。")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                }
                .listRowBackground(Palette.surface)

                Section {
                    ForEach(syncedFields, id: \.self) { field in
                        Text(field)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                    }
                } header: {
                    syncSectionHeader("会同步这些")
                }
                .listRowBackground(Palette.surface)

                Section {
                    ForEach(notSyncedFields, id: \.self) { field in
                        Text(field)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                } header: {
                    syncSectionHeader("不会同步这些")
                }
                .listRowBackground(Palette.surface)

                Section {
                    Text("副本存在你自己的服务器上，和 OneDay 配套的那个服务里。它只新到上次同步为止，页面上会一直标着同步时刻。想关随时关：关的时候可以顺手删副本，也可以之后在这一页单独删。删副本只删服务器那一份，手机上的数据和系统权限都不动。同步只在打开 App 时进行，不在后台偷偷跑。")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                } header: {
                    syncSectionHeader("存在哪里、怎么删")
                }
                .listRowBackground(Palette.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle("开启\(dataset.label)同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("先不开") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开启同步") { onConfirm() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - 照片详情页

struct PhotosDetailView: View {
    @Environment(AppState.self) private var appState
    var inSheet = false
    @State private var summary: (total: Int, photos: Int, videos: Int)?

    private var session: DeviceSessionController {
        appState.deviceSession
    }
    private var permission: DevicePermissionState {
        session.permissions[.photos] ?? .notDetermined
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .photos)
            DeviceSyncSection(source: .photos)
            if permission.isUsable {
                Section {
                    if let summary {
                        countRow("照片", "\(summary.photos) 项")
                        countRow("视频", "\(summary.videos) 项")
                        countRow("合计", "\(summary.total) 项")
                    } else {
                        Text("正在数…")
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Text("这里数的是手机上有多少项。同步上去的只是清单（时间、类型、大小这些），照片和视频本身不上传。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                } header: {
                    syncSectionHeader("这台手机上")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(syncRowInsets)
            } else {
                DevicePermissionGate(
                    source: .photos, permission: permission
                )
            }
            DeviceFootnote(source: .photos)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .task { load() }
        .modifier(RefreshableIfEnabled(enabled: !inSheet) { load() })
    }

    private func load() {
        session.refreshPermissions()
        if permission.isUsable {
            summary = appState.deviceSync.photosEngine.localSummary()
        }
    }

    private func countRow(
        _ title: String, _ value: String
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(title)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }
}

// MARK: - 步数详情页

struct MotionDetailView: View {
    @Environment(AppState.self) private var appState
    var inSheet = false
    @State private var days: [SyncMotionDayRecord]?

    private var session: DeviceSessionController {
        appState.deviceSession
    }
    private var permission: DevicePermissionState {
        session.permissions[.motion] ?? .notDetermined
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .motion)
            DeviceSyncSection(source: .motion)
            if permission.isUsable {
                Section {
                    if let days {
                        if days.isEmpty {
                            Text("近 7 天没有计步数据。")
                                .font(.body)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        ForEach(days.reversed(), id: \.date) { day in
                            dayRow(day)
                        }
                    } else {
                        Text("正在读取…")
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Text("步数来自手机自己的计步，系统只留最近 7 天左右；同步到服务器后按天攒着，攒出更长的记录。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                } header: {
                    syncSectionHeader("最近 7 天")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(syncRowInsets)
            } else {
                DevicePermissionGate(
                    source: .motion, permission: permission
                )
            }
            DeviceFootnote(source: .motion)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .task { await load() }
        .modifier(
            RefreshableIfEnabled(enabled: !inSheet) {
                await load()
            }
        )
    }

    private func load() async {
        session.refreshPermissions()
        if permission.isUsable {
            days = await appState.deviceSync.motionEngine
                .recentDays()
        }
    }

    private func dayRow(_ day: SyncMotionDayRecord) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(dayLabel(day.date))
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text("\(day.steps) 步")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    /// "yyyy-MM-dd" → 人话日名（今天/昨天/M月d日）
    private func dayLabel(_ day: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else { return day }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "M月d日"
        return out.string(from: date)
    }
}
