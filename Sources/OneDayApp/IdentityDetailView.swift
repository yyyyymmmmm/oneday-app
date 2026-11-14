import OneDayDesign
import OneDayCore
import SwiftUI

/// 形象与名称（设置页重塑，DESIGN §164；蓝本＝用户亲
/// 递原型 identity 页）：身份卡的详情页——大头像 hero
/// ＋本机资料两入口（更换形象／编辑名称，编辑面本体
/// 复用 AgentAvatarEditorView／AgentNameEditorView，
/// 与枢纽头像菜单、设置身份卡共用同一本机档案，不另
/// 做一套）＋活动两行（最近活动点达聊天、服务器状态
/// 进当前服务器页）。
/// 分工：这里管的是只存本机的显示名与形象；决定人设
/// 的配置档案在「智能体」组，两者互不回写（页脚明示）。
struct IdentityDetailView: View {
    @Environment(AppState.self) private var appState
    /// 服务器状态值位（设置页已加载的 status 派生，
    /// 由 SettingsView 注入；本页不另发请求）
    let serverStatusText: String
    /// 「最近活动」点达：关设置并切聊天（SettingsView
    /// 经 onClose＋onRequestChat 组合注入）
    var onOpenChat: (() -> Void)? = nil

    @State private var editorSheet: EditorSheet?

    private enum EditorSheet: String, Identifiable {
        case avatar, name
        var id: String { rawValue }
    }

    var body: some View {
        List {
            heroSection
            localProfileSection
            activitySection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("形象与名称")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorSheet) { item in
            switch item {
            case .avatar:
                AgentAvatarEditorView()
            case .name:
                AgentNameEditorView(
                    initialName: appState.identityName ?? ""
                )
            }
        }
    }

    // MARK: - Hero

    /// 大头像＋显示名＋身份分工副行：主名走全 App 单
    /// 一出口（本机覆盖→服务器人设名→回落）；副行明
    /// 示服务器身份名（无本机覆盖时与主名同值、照显）
    private var heroSection: some View {
        Section {
            VStack(spacing: OneDayMetrics.spacingS) {
                appState.agentAvatarImage
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: OneDayMetrics.avatarPageHead,
                        height: OneDayMetrics.avatarPageHead
                    )
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)
                Text(appState.agentDisplayName)
                    .font(.screenName)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("本机显示名 · 服务器身份 \(appState.identityName ?? AgentName.fallback)")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OneDayMetrics.spacingSM)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    // MARK: - 本机资料

    private var localProfileSection: some View {
        Section {
            editorRow(
                icon: "person.crop.circle", title: "更换形象",
                subtitle: "预置形象或从相册选择"
            ) { editorSheet = .avatar }
            editorRow(
                icon: "pencil", title: "编辑名称",
                subtitle: "最多 20 个字，只影响这台手机"
            ) { editorSheet = .name }
        } header: {
            sectionHeader("本机资料")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    private func editorRow(
        icon: String, title: String, subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon(icon)
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(L10n.string(title))
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(L10n.string(subtitle))
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
        .buttonStyle(.odPressable)
    }

    // MARK: - 活动

    private var activitySection: some View {
        Section {
            Button {
                onOpenChat?()
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowIcon("text.bubble")
                    Text("最近活动")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            NavigationLink(value: SettingsRoute.serverDetail) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowIcon("server.rack")
                    Text("服务器状态")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Text(serverStatusText)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
        } header: {
            sectionHeader("活动")
        } footer: {
            Text("形象与名称只保存在本机，不回写服务器。配置档案决定人设，在「智能体」里管理。")
                .font(.rowSubtitle)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    // MARK: - 共用件（与设置首页同口径复刻）

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(L10n.string(title))
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(
                size: FrameworkIcon.settingsGlyphSize,
                weight: .regular
            ))
            .foregroundStyle(Palette.ink)
            .frame(width: OneDayMetrics.iconSlot, alignment: .center)
            .accessibilityHidden(true)
    }
}
