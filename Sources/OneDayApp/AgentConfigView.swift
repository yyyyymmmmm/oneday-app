import OneDayDesign
import OneDayCore
import SwiftUI

/// 智能体配置枢纽页（prototype-2，DESIGN §164 升级）：
/// 汇总配置档案／记忆／技能三项——原散落在根页 agent 组，
/// 本页枢纽化后根页只剩模型与服务商／智能体配置／定时任务
struct AgentConfigView: View {
    var body: some View {
        List {
            Section {
                NavigationLink(value: SettingsRoute.profiles) {
                    rowContent(
                        icon: "archivebox",
                        title: "配置档案",
                        subtitle: "人设与系统提示"
                    )
                }
                .settingsSeparatorToIconEdge()

                NavigationLink(value: SettingsRoute.agent(.memory)) {
                    rowContent(
                        icon: "memorychip",
                        title: "记忆",
                        subtitle: "长期偏好与记忆条目"
                    )
                }
                .settingsSeparatorToIconEdge()

                NavigationLink(value: SettingsRoute.agent(.skills)) {
                    rowContent(
                        icon: "puzzlepiece.extension",
                        title: "技能",
                        subtitle: "已安装的工具与扩展能力"
                    )
                }
                .settingsSeparatorToIconEdge()
            } header: {
                Text("行为与能力")
                    .font(.sectionLabel)
                    .foregroundStyle(Palette.inkSecondary)
                    .textCase(nil)
            } footer: {
                Text("这些配置保存在服务器；形象与名称只影响本机显示。")
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
        .navigationTitle("智能体配置")
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
