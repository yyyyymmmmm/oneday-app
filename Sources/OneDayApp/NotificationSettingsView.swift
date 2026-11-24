import OneDayCore
import OneDayDesign
import SwiftUI

/// 通知设置面（总表 162/163，DESIGN §385）：设置 →
/// 偏好与权限 →「通知」。四类分级开关与实时活动总
/// 开关——键与 Core 偏好口（NotificationTier-
/// Preferences／RunLiveActivityCenter.enabledKey）
/// 逐字同键，开关即真接口：改完提醒器与活动中心
/// 按同一 UserDefaults 实值回读生效，不设第二套账。
/// 分级口径（哪类是哪级）在行右与页脚写明，不让用
/// 户对着开关猜后果。
struct NotificationSettingsView: View {
    // 键与 NotificationTier.Category.preferenceKey
    // 逐字一致（结构钉测把守四键全在场）
    @AppStorage("notify.category.approval.enabled")
    private var approvalEnabled = true
    @AppStorage("notify.category.runCompleted.enabled")
    private var runCompletedEnabled = true
    @AppStorage("notify.category.failure.enabled")
    private var failureEnabled = true
    @AppStorage("notify.category.system.enabled")
    private var systemEnabled = true
    @AppStorage(RunLiveActivityCenter.enabledKey)
    private var liveActivityEnabled = true

    // §397 子项 3 组版接线：推送就绪面挂本面（唯一的家）
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                categoryToggle(
                    category: .approval, isOn: $approvalEnabled
                )
                categoryToggle(
                    category: .failure, isOn: $failureEnabled
                )
                categoryToggle(
                    category: .runCompleted,
                    isOn: $runCompletedEnabled
                )
                categoryToggle(
                    category: .system, isOn: $systemEnabled
                )
            } header: {
                sectionHeader("分类提醒")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)

            Section {
                Toggle(isOn: $liveActivityEnabled) {
                    Text("实时活动")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } header: {
                sectionHeader("进行中任务")
            } footer: {
                Text("开启后，一轮生成进行时会在锁屏和灵动岛显示会话名与进度阶段（准备中／生成中），结束自动收起；只显示名称和阶段，不显示回复内容。关掉后不再发起新的实时活动。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
            PushReadinessView(store: appState.pushRegistration)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.large)
    }

    private func categoryToggle(
        category: NotificationTier.Category,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(category.label())
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(
                    NotificationTier.tier(for: category).label()
                )
                .font(.rowSubtitle)
                .foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
    }

    private var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }
}
