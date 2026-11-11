import OneDayDesign
import OneDayCore
import SwiftUI

/// 重启网关页（prototype-2，DESIGN §164 升级监工纠正③）：
/// 按原型落页面形态（重启前状态组＋操作按钮），重启逻辑复用
/// 现行全链（确认弹窗＋restartGateway()＋notice）
struct RestartGatewayView: View {
    @Environment(\.dismiss) private var dismiss
    let status: ServerStatus?
    @Binding var showRestartConfirm: Bool

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                    LabeledContent {
                        Text(gatewayStatusText)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    } label: {
                        Text("状态")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    LabeledContent {
                        Text("Hermes 网关服务")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    } label: {
                        Text("影响范围")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    LabeledContent {
                        Text("不受影响，保留在服务器上")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    } label: {
                        Text("聊天记录")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    LabeledContent {
                        Text("通常 10–20 秒")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    } label: {
                        Text("恢复时间")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .padding(.vertical, OneDayMetrics.spacingS)
                .listRowBackground(Palette.surface)
            } header: {
                Text("重启前")
                    .font(.sectionLabel)
                    .foregroundStyle(Palette.inkSecondary)
                    .textCase(nil)
            }
            .listRowInsets(settingsRowInsets)

            // 操作按钮组
            Section {
                Button {
                    showRestartConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Text("重启网关")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.surface)
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .listRowBackground(Palette.danger)
                .listRowInsets(settingsRowInsets)

                Button {
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("取消")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(settingsRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("重启网关")
        .navigationBarTitleDisplayMode(.large)
    }

    /// 网关状态文案（与 ServerManagementView.gatewayStateWord 同口径）
    private var gatewayStatusText: String {
        switch status?.gatewayState?.lowercased() {
        case "running": return "运行中"
        case "stopped": return "已停止"
        case "error", "failed": return "异常"
        default: return status == nil ? "—" : "未知"
        }
    }

    private var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }
}
