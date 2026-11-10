import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 同步制视图（0.36.14 立制，0.36.18 改「权限即
/// 同步」终形态）：详情页只剩一个权限开关＋安静
/// 状态字＋同步记录，照片/步数两件的详情页也在
/// 本文件。文案口径：说人话、零行话——存哪、新
/// 到什么时候、怎么删，一句说清、不成段

private func syncSectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.sectionLabel)
        .foregroundStyle(Palette.inkSecondary)
        .textCase(nil)
}

private let syncRowInsets = EdgeInsets(
    top: 0, leading: 20, bottom: 0, trailing: 20
)

// MARK: - 详情页权限开关区（0.36.18 终形态）

struct DeviceSyncSection: View {
    @Environment(AppState.self) private var appState
    let source: DeviceSourceID

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

    /// 状态字一行：副本条数 · 数据新到（安静呈现，
    /// 不摆行、不带控件）
    private var copyStatusLine: String? {
        guard let countLine else { return nil }
        var parts = ["服务器上的副本 \(countLine)"]
        if let freshnessLine { parts.append(freshnessLine) }
        return parts.joined(separator: " · ")
    }

    /// 权限关但副本还在（完全停供的用户面说法：
    /// 查不到、副本保留、重开恢复）
    private var revokedLine: String? {
        guard !permission.isUsable, hasCopy else { return nil }
        return "权限已关：智能体现在查不到这一件。服务器上的副本还在，重新打开权限就会恢复。"
    }

    private var expiredLine: String? {
        guard status?.expired == true, revokedLine == nil
        else { return nil }
        return "这份副本超过一天没更新了：回到 App 前台会自动同步一次。"
    }

    /// 本件同步日志（新在上，控制器与偏好同值）
    private var logEntries: [DeviceSyncLogEntry] {
        sync.logs[dataset] ?? []
    }

    /// 唯一的开关：绑真实权限状态（Core 映射一处
    /// 真源），显示永远回读现态、不认本地偏好
    private var switchBinding: Binding<Bool> {
        Binding(
            get: { DeviceSyncControl.switchIsOn(permission) },
            set: { newValue in
                if newValue { turnOn() } else { turnOff() }
            }
        )
    }

    /// 拨开（用户亲定语义）：未决定——先落日志
    /// 「正在开启」，再发那一次系统请求，授权到
    /// 手当场补首轮自动同步；已决定为不可用（系
    /// 统不再弹窗）——跳系统设置；已授权不会走
    /// 到这里（开关本就呈开态）
    private func turnOn() {
        switch DeviceSyncControl.toggleOnAction(for: permission) {
        case .requestPermission:
            sync.noteEnabling(dataset)
            actionNote = nil
            Task {
                await session.requestAccess(for: source)
                if DeviceSyncControl.switchIsOn(
                    session.permissions[source] ?? .notDetermined
                ) {
                    await sync.detailPageCheck(
                        dataset: dataset, config: appState.config
                    )
                }
            }
        case .openSettings:
            openSystemSettings()
        case .alreadyOn:
            break
        }
    }

    /// 拨关（用户亲定语义）：跳系统设置由用户亲
    /// 手关权限——App 关不掉、也不假装已关；关没
    /// 关成，回前台按真实状态回读，停供与日志记
    /// 账在状态上报里落
    private func turnOff() {
        openSystemSettings()
    }

    private func openSystemSettings() {
        if let url = URL(
            string: UIApplication.openSettingsURLString
        ) {
            UIApplication.shared.open(url)
        }
    }

    var body: some View {
        Group {
            Section {
                Toggle(isOn: switchBinding) {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text("访问权限")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text(
                            DeviceSyncControl.switchIsOn(permission)
                                ? "开着：自动同步到你的服务器，智能体可以查"
                                : "关着：智能体用不了这一件"
                        )
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)

                statusBlock

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
            .listRowBackground(Palette.surface)
            .listRowInsets(syncRowInsets)

            logSection
        }
        .task {
            // 触发③：进页补查（过期才真跑同步）
            await sync.detailPageCheck(
                dataset: dataset, config: appState.config
            )
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
                        ? "副本已删除。权限还开着，下次打开 App 会自动重新同步回来；不想再同步就关掉上方开关。"
                        : "没删成，检查服务器连接后再试。"
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删的只是服务器上的这一份副本；手机上的数据、系统权限都不动。")
        }
    }

    /// 开关下方的安静状态字：同步中/停供/失败/副
    /// 本现状，互斥优先、如实报——只是一行小字，
    /// 不摆行、不带控件（立即同步钮随本版退役，
    /// 失败会在下次回前台/数据变更时自动重试）
    @ViewBuilder
    private var statusBlock: some View {
        if sync.isRunning(dataset) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                ProgressView()
                Text(sync.progress[dataset] ?? "同步中…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } else if let revokedLine {
            Text(revokedLine)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        } else if let error = sync.lastErrors[dataset] {
            Text(error)
                .font(.footnote)
                .foregroundStyle(Palette.danger)
        } else if let copyStatusLine {
            Text(copyStatusLine)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            if let expiredLine {
                Text(expiredLine)
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
            }
        }
    }

    /// 同步日志（用户亲定形态）：时间打头一行一
    /// 条——时间 12pt 次级色在前、事由脚注级常
    /// 规字重、数字等宽；发丝线分隔、密排；只有
    /// 失败行带红点＋红字。事件分类与存储上限沿
    /// 0.36.16 不变
    private var logSection: some View {
        Section {
            if logEntries.isEmpty {
                Text("还没有记录。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(
                    Array(logEntries.enumerated()), id: \.offset
                ) { _, entry in
                    logRow(entry)
                }
            }
        } header: {
            syncSectionHeader("同步记录")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(syncRowInsets)
    }

    private func logRow(_ entry: DeviceSyncLogEntry) -> some View {
        let failed = DeviceSyncLogPresentation.isFailure(entry)
        return HStack(
            alignment: .firstTextBaseline,
            spacing: OneDayMetrics.spacingSM
        ) {
            Text(
                DeviceSyncLogPresentation.timeText(
                    for: entry, now: Date()
                )
            )
            .font(.caption)
            .foregroundStyle(Palette.inkSecondary)
            .monospacedDigit()
            if failed {
                Circle()
                    .fill(Palette.danger)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(
                DeviceSyncLogPresentation.line(
                    for: entry, dataset: dataset
                )
            )
            .font(.footnote)
            .foregroundStyle(failed ? Palette.danger : Palette.ink)
        }
        .padding(.vertical, OneDayMetrics.spacingMicro)
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
