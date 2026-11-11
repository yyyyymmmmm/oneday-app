import OneDayDesign
import OneDayCore
import SwiftUI

/// 会话管理枢纽页（prototype-2，DESIGN §164 升级）：
/// 主线会话（真数据接线）＋服务端会话
struct SessionManagementView: View {
    var body: some View {
        List {
            // Lead 副标题
            Section {
                Text("继续当前对话，或查找服务器上的历史记录。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))

            Section {
                NavigationLink(value: SettingsRoute.mainSession) {
                    rowContent(
                        icon: "link",
                        title: "主线会话",
                        subtitle: "持续对话的主要会话"
                    )
                }
                .settingsSeparatorToIconEdge()

                NavigationLink(value: SettingsRoute.agent(.serverSessions)) {
                    rowContent(
                        icon: "bubble.left",
                        title: "服务端会话",
                        subtitle: "查看与管理历史会话"
                    )
                }
                .settingsSeparatorToIconEdge()
            } header: {
                Text("会话")
                    .font(.sectionLabel)
                    .foregroundStyle(Palette.inkSecondary)
                    .textCase(nil)
            } footer: {
                Text("完整会话 ID 可在详情中查看和复制。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("会话管理")
        .navigationBarTitleDisplayMode(.large)
    }

    private func rowContent(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: icon)
                .font(.system(
                    size: FrameworkIcon.settingsGlyphSize,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
                .frame(width: OneDayMetrics.iconSlot, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
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
