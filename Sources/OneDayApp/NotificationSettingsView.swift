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
            SettingsHeroCard(
                symbol: "bell.badge.fill",
                tint: .red,
                title: "通知与实时活动",
                subtitle: "按事件重要程度分层提醒，避免无关噪音打扰。"
            )

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
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        IconTile(symbol: "platter.filled.top.iphone", color: .blue, size: OneDayMetrics.iconSlot)
                        Text("实时活动")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } header: {
                sectionHeader("进行中任务")
            } footer: {
                Text("生成进行时在锁屏与灵动岛展示会话名和进度阶段（不暴露回复内容），完成后自动收起。")
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
        .navigationBarTitleDisplayMode(.inline)
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
        OneDayMetrics.settingsRowInsets
    }
}
