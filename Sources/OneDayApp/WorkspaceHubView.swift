import OneDayDesign
import OneDayCore
import SwiftUI

/// 工作区枢纽页（prototype-2，DESIGN §164 升级）：
/// 总览／电脑／服务器文件三件——保持现行 sheet 机制
struct WorkspaceHubView: View {
    @Binding var manageSheet: ManageSheet?

    enum ManageSheet: String, Identifiable {
        case overview, computer, serverFiles
        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                Button {
                    manageSheet = .overview
                } label: {
                    rowContent(
                        icon: "chart.xyaxis.line",
                        title: "总览",
                        subtitle: "服务器与智能体的运行概况"
                    )
                }
                .buttonStyle(.odPressable)
                .settingsSeparatorToIconEdge()

                Button {
                    manageSheet = .computer
                } label: {
                    rowContent(
                        icon: "display",
                        title: "电脑",
                        subtitle: "电脑设备与协作能力"
                    )
                }
                .buttonStyle(.odPressable)
                .settingsSeparatorToIconEdge()

                Button {
                    manageSheet = .serverFiles
                } label: {
                    rowContent(
                        icon: "folder",
                        title: "服务器文件",
                        subtitle: "浏览允许访问的目录"
                    )
                }
                .buttonStyle(.odPressable)
                .settingsSeparatorToIconEdge()
            } header: {
                Text("资源")
                    .font(.sectionLabel)
                    .foregroundStyle(Palette.inkSecondary)
                    .textCase(nil)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("工作区")
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

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true)
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
