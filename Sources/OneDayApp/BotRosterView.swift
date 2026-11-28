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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var profiles: [ProfileItem] = []
    @State private var activeProfileName: String = ""
    @State private var isLoading = false
    @State private var switchingProfile: String?
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var noticeMessage: String?
    @State private var showCreateBotSheet = false

    private var filteredProfiles: [ProfileItem] {
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
                Button {
                    showCreateBotSheet = true
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "plus.circle.fill", color: Palette.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("新建专家分身")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.primary)
                            Text("可同时绑定定时巡检，实现后台常驻干活")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                NavigationLink(value: SettingsRoute.profiles) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "slider.horizontal.3", color: Palette.tintSkyInk)
                        Text("全部档案与导入导出")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
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
        .animation(MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion), value: filteredProfiles.map(\.name))
        .searchable(text: $searchText, prompt: Text("搜索分身名称或模型"))
        .navigationTitle("专家分身花名册")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateBotSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建专家分身")
            }
        }
        .sheet(isPresented: $showCreateBotSheet) {
            CreateSpecialistBotSheet(
                existingNames: profiles.map(\.name),
                onCreated: { newName in
                    noticeMessage = "已创建专家分身「\(newName)」，现在可在聊天中 @\(newName) 随时召唤。"
                    Task { await loadRoster() }
                }
            )
        }
        .refreshable { await loadRoster() }
        .task { await loadRoster() }
    }

    private func botRow(_ profile: ProfileItem) -> some View {
        let isActive = profile.name == activeProfileName
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            profiles = try await appState.performAdmin { client, config in
                try await client.profiles(config: config)
            }
            activeProfileName = (try? await appState.performAdmin { client, config in
                try await client.activeProfileName(config: config)
            }) ?? profiles.first(where: { $0.isDefault == true })?.name ?? ""
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "无法读取分身花名册：\(error.localizedDescription)"
        }
    }

    private func wakeAndChat(_ profile: ProfileItem) async {
        switchingProfile = profile.name
        errorMessage = nil
        noticeMessage = nil
        defer { switchingProfile = nil }
        do {
            if profile.name != activeProfileName {
                try await appState.performAdmin { client, config in
                    try await client.setActiveProfile(config: config, name: profile.name)
                }
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

private struct CreateSpecialistBotSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let existingNames: [String]
    let onCreated: (String) -> Void

    @State private var name = ""
    @State private var cloneFrom = ""
    @State private var enableAlwaysOnCron = false
    @State private var cronSchedule = "0 */2 * * *"
    @State private var cronPrompt = "检查近期重点事项与未处理消息，有重要更新立即汇总提醒我。"
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && !existingNames.contains(trimmedName) && !isCreating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("分身名称（如：代码架构师 / 调研专家）", text: $name)
                        .autocorrectionDisabled()
                    if !existingNames.isEmpty {
                        Picker("克隆已有配置（可选）", selection: $cloneFrom) {
                            Text("全新空白分身").tag("")
                            ForEach(existingNames, id: \.self) { item in
                                Text(item).tag(item)
                            }
                        }
                    }
                }

                Section {
                    Toggle(isOn: $enableAlwaysOnCron) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("开启后台常驻巡检（定时唤醒）")
                                .font(.rowTitleL)
                            Text("按设定频率自动唤醒分身执行巡检并推送结果，实现长期在线体验")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    if enableAlwaysOnCron {
                        TextField("Cron 表达式（如 0 */2 * * *）", text: $cronSchedule)
                            .font(.metaMonospaced)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("后台常驻巡检任务指令", text: $cronPrompt, axis: .vertical)
                            .lineLimit(2...4)
                    }
                } header: {
                    Text("常驻活跃设置")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("新建专家分身")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "创建中…" : "创建") {
                        Task { await create() }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.createProfile(
                    config: config,
                    name: trimmedName,
                    cloneFrom: cloneFrom.isEmpty ? nil : cloneFrom
                )
            }
            if enableAlwaysOnCron {
                let prompt = cronPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                let sched = cronSchedule.trimmingCharacters(in: .whitespacesAndNewlines)
                if !prompt.isEmpty && !sched.isEmpty {
                    _ = try? await appState.performAdmin { client, config in
                        try await client.createCronJob(
                            config: config,
                            name: "\(trimmedName)·常驻巡检",
                            prompt: "[分身:\(trimmedName)] \(prompt)",
                            schedule: sched,
                            deliver: nil
                        )
                    }
                }
            }
            Haptics.success()
            onCreated(trimmedName)
            dismiss()
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "创建失败：\(error.localizedDescription)"
            Haptics.error()
        }
    }
}
