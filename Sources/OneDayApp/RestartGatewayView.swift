import OneDayDesign
import OneDayCore
import SwiftUI

/// 重启网关页（prototype-2，DESIGN §164 升级监工纠正③）：
/// 按原型落页面形态（重启前状态组＋操作按钮），重启逻辑复用
/// 现行全链（确认弹窗＋restartGateway()＋notice）
struct RestartGatewayView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showRestartConfirm: Bool

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                    infoRow(label: "影响范围", value: "Hermes 网关服务")
                    infoRow(label: "聊天记录", value: "不受影响，保留在服务器上")
                    infoRow(label: "恢复时间", value: "通常 10–20 秒")
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

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(.rowTitleL)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
            Spacer(minLength: 0)
        }
    }

    private var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }
}
