import OneDayDesign
import OneDayCore
import SwiftUI

/// 服务器管理枢纽页（prototype-2，DESIGN §164 升级）：
/// 顶部服务器卡片＋运行与用量组（网关/日志/用量）＋维护组
/// （密钥/重启网关）＋底部断开连接行
struct ServerManagementView: View {
    @Environment(AppState.self) private var appState
    /// 服务器状态：卡片需显示连接状态与绿点
    let status: ServerStatus?
    @Binding var showDisconnectConfirm: Bool

    var body: some View {
        List {
            // Lead 副标题
            Section {
                Text("连接、诊断与维护，集中在这里。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))

            // 当前服务器卡片
            Section {
                NavigationLink(value: SettingsRoute.serverDetail) {
                    serverConnectionCard
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(EdgeInsets(top: 0, leading: 19, bottom: 0, trailing: 17))
            }

            // 运行与用量组
            Section {
                NavigationLink(value: SettingsRoute.gateway) {
                    rowContent(
                        icon: "network",
                        title: "网关状态",
                        subtitle: gatewayStateWord
                    )
                }
                .settingsSeparatorToIconEdge()

                NavigationLink(value: SettingsRoute.logs) {
                    rowContent(icon: "doc.text", title: "日志", subtitle: nil)
                }
                .settingsSeparatorToIconEdge()

                NavigationLink(value: SettingsRoute.usage) {
                    rowContent(icon: "chart.bar", title: "用量", subtitle: nil)
                }
                .settingsSeparatorToIconEdge()
            } header: {
                Text("运行与用量")
                    .font(.sectionLabel)
                    .foregroundStyle(Palette.inkSecondary)
                    .textCase(nil)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)

            // 维护组
            Section {
                NavigationLink(value: SettingsRoute.envVars) {
                    rowContent(icon: "key", title: "密钥", subtitle: nil)
                }
                .settingsSeparatorToIconEdge()

                NavigationLink(value: SettingsRoute.restartGateway) {
                    rowContent(icon: "arrow.clockwise", title: "重启网关", subtitle: nil)
                }
                .settingsSeparatorToIconEdge()
            } header: {
                Text("维护")
                    .font(.sectionLabel)
                    .foregroundStyle(Palette.inkSecondary)
                    .textCase(nil)
            } footer: {
                Text("断开不会删除聊天记录。维护操作执行前需要确认。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)

            // 断开连接（独立节、页底）
            Section {
                Button(role: .destructive) {
                    showDisconnectConfirm = true
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Text("断开连接")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.danger)
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .contentShape(Rectangle())
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("服务器管理")
        .navigationBarTitleDisplayMode(.large)
    }

    /// 服务器连接卡片：图标砖＋「当前服务器」标签＋host＋状态点
    private var serverConnectionCard: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            // 图标砖 44pt
            Image(systemName: "server.rack")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.settingsBG)
                .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text("当前服务器")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)

                HStack(spacing: OneDayMetrics.spacingS) {
                    Text(appState.config?.host ?? "未连接")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)

                    if let status {
                        StatusDot(color: Palette.stateColor(status.gatewayState))
                    }
                }

                if let status {
                    Text(connectionStatusText)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
        }
        .padding(.vertical, OneDayMetrics.spacingM)
        .contentShape(Rectangle())
    }

    private var connectionStatusText: String {
        guard let status else { return "未知" }
        let state = status.gatewayState?.lowercased()
        switch state {
        case "running": return "已连接"
        case "stopped": return "已停止"
        case "error", "failed": return "异常"
        default: return "未知"
        }
    }

    private var gatewayStateWord: String {
        switch status?.gatewayState?.lowercased() {
        case "running": return "运行中"
        case "stopped": return "已停止"
        case "error", "failed": return "异常"
        default: return status == nil ? "—" : "未知"
        }
    }

    private func rowContent(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: icon)
                .font(.system(
                    size: FrameworkIcon.settingsGlyphSize,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
                .frame(width: OneDayMetrics.iconSlot, alignment: .center)
                .accessibilityHidden(true)

            if let subtitle {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(title)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            } else {
                Text(title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .contentShape(Rectangle())
    }

    private var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }
}

private extension View {
    func settingsSeparatorToIconEdge() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
