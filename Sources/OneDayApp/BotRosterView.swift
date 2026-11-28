import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// Bot Mode 具名专家分身花名册（Hermes v0.23.0 Bot Roster）：
/// 聚合展示服务端所有常驻专家分身（Profile 驱动），支持按角色检索、
/// 查看独立模型与技能画像，以及一键激活并开启专属分身对话。
struct BotRosterView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var profiles: [ProfileSummary] = []
    @State private var activeProfileName: String = ""
    @State private var isLoading = false
    @State private var switchingProfile: String?
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var noticeMessage: String?

    private var filteredProfiles: [ProfileSummary] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return profiles }
        return profiles.filter { p in
            p.name.lowercased().contains(q)
                || (p.model ?? "").lowercased().contains(q)
                || (p.provider ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "person.2.badge.gearshape.fill",
                tint: Palette.tintLavenderInk,
                title: "专家分身花名册",
                subtitle: "浏览并唤醒常驻的 Hermes Bot Mode 专家分身，每个分身拥有独立模型、记忆与工具权限。",
                statusText: profiles.isEmpty ? "加载中" : "\(profiles.count) 位常驻分身",
                statusTone: profiles.isEmpty ? .neutral : .healthy
            )

            if let errorMessage {
                Section {
                    InlineError(errorMessage)
                }
            }

            if let noticeMessage {
                Section {
                    Text(noticeMessage)
                        .font(.footnote)
                        .foregroundStyle(Palette.successText)
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                if isLoading && profiles.isEmpty {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        ProgressView()
                        Text("正在同步分身花名册…")
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                } else if filteredProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profiles.isEmpty ? "暂无具名分身" : "没有匹配的分身")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text("可在「配置档案与分身」中创建专属专家分身（如代码架构师、深度研究员、日程助理）。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(filteredProfiles, id: \.name) { profile in
                        botRow(profile)
                    }
                }
            } header: {
                SettingsSectionHeader("常驻专家分身")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                NavigationLink(value: SettingsRoute.profiles) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "plus.circle.fill", color: Palette.primary)
                        Text("新建或编辑专家分身")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.primary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                NavigationLink(value: SettingsRoute.agent(.botMode)) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "person.3.sequence.fill", color: Palette.tintLavenderInk)
                        Text("多体房间协作与授权")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
            } header: {
                SettingsSectionHeader("分身治理与协作")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .searchable(text: $searchText, prompt: Text("搜索分身名称或模型"))
        .navigationTitle("专家分身花名册")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadRoster() }
        .task { await loadRoster() }
    }

    private func botRow(_ profile: ProfileSummary) -> some View {
        let isActive = profile.isActive || profile.name == activeProfileName
        let visual = botVisual(for: profile.name)
        return HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: visual.symbol)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(visual.tint)
                .frame(width: 36, height: 36)
                .background(
                    visual.tint.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.rowTitleL.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if isActive {
                        SettingsStatusPill(text: "在线", tone: .healthy)
                    }
                }
                HStack(spacing: 6) {
                    if let model = profile.model, !model.isEmpty {
                        Text(model)
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    } else {
                        Text("跟随默认模型")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if let provider = profile.provider, !provider.isEmpty {
                        Text("· \(provider)")
                            .font(.caption)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: OneDayMetrics.spacingS)

            if switchingProfile == profile.name {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(isActive ? "去对话" : "唤醒") {
                    Task { await wakeAndChat(profile) }
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? Palette.tintGreenInk : Palette.primary)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func botVisual(for name: String) -> (symbol: String, tint: Color) {
        let lower = name.lowercased()
        if lower.contains("code") || lower.contains("dev") || lower.contains("代码") || lower.contains("架构") {
            return ("chevron.left.forwardslash.chevron.right", Palette.tintSkyInk)
        }
        if lower.contains("research") || lower.contains("研究") || lower.contains("分析") {
            return ("magnifyingglass.circle.fill", Palette.tintLavenderInk)
        }
        if lower.contains("ops") || lower.contains("运维") || lower.contains("安全") {
            return ("shield.lefthalf.filled", Palette.tintOrangeInk)
        }
        if lower.contains("write") || lower.contains("写作") || lower.contains("内容") {
            return ("pencil.and.outline", Palette.tintGreenInk)
        }
        return ("sparkles", Palette.primary)
    }

    private func loadRoster() async {
        guard let config = appState.config, let apiKey = appState.apiKey else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await appState.client.profiles(config: config, apiKey: apiKey)
            profiles = response.profiles
            activeProfileName = response.activeProfile ?? profiles.first(where: \.isActive)?.name ?? ""
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "无法读取分身花名册：\(error.localizedDescription)"
        }
    }

    private func wakeAndChat(_ profile: ProfileSummary) async {
        guard let config = appState.config, let apiKey = appState.apiKey else { return }
        switchingProfile = profile.name
        errorMessage = nil
        noticeMessage = nil
        defer { switchingProfile = nil }
        do {
            if profile.name != activeProfileName {
                _ = try await appState.client.activateProfile(
                    config: config,
                    apiKey: apiKey,
                    name: profile.name
                )
                activeProfileName = profile.name
            }
            noticeMessage = "已唤醒专家分身「\(profile.name)」，正在切换至对话界面。"
            Haptics.success()
            appState.router.mainTabSwitchRequest = .chat
            dismiss()
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "唤醒分身失败：\(error.localizedDescription)"
            Haptics.error()
        }
    }
}
