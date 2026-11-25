import OneDayCore
import OneDayDesign
import SwiftUI

/// 技能商店（P10）：/api/skills/hub 搜索/预览/安装/卸载。
/// 统一原生 iOS 26 List(.insetGrouped) + .searchable + SettingsHeroCard + ContentUnavailableView。
struct SkillHubView: View {
    @Environment(AppState.self) private var appState

    @State private var queryText = ""
    @State private var sources: [HubSource] = []
    /// nil = 全部来源
    @State private var selectedSource: String?
    @State private var phase: Phase = .idle
    @State private var installedNames: Set<String> = []

    enum Phase {
        case idle
        case searching
        case results([HubSkill])
        case failed(String)
    }

    private var isSearching: Bool {
        if case .searching = phase { return true }
        return false
    }

    private var heroTone: SettingsStatusTone {
        if case .failed = phase { return .error }
        return installedNames.isEmpty ? .neutral : .healthy
    }

    private var heroStatusText: String {
        if isSearching { return "搜索中" }
        if case .failed = phase { return "连接异常" }
        return installedNames.isEmpty ? "可搜索" : "已装 \(installedNames.count) 项"
    }

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "bag.fill",
                tint: .indigo,
                title: "技能商店",
                subtitle: "从远程技能库搜索、预览并安装扩展技能包。",
                statusText: heroStatusText,
                statusTone: heroTone
            )

            if !sources.isEmpty {
                Section {
                    sourceChips
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                } header: {
                    SettingsSectionHeader("来源筛选")
                }
                .listRowBackground(Palette.surface)
            }

            content
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .searchable(
            text: $queryText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索技能，如 pdf、browser"
        )
        .onSubmit(of: .search) {
            Task { await search() }
        }
        .navigationTitle("技能商店")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSources()
            await refreshInstalled()
        }
    }

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OneDayMetrics.spacingS) {
                chip(title: "全部", selected: selectedSource == nil) {
                    selectedSource = nil
                    reseachIfActive()
                }
                ForEach(sources) { source in
                    chip(
                        title: source.displayLabel,
                        selected: selectedSource == source.name
                    ) {
                        selectedSource = source.name
                        reseachIfActive()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(
        title: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .foregroundStyle(
                    selected ? Palette.primary : Palette.inkSecondary
                )
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .padding(.vertical, OneDayMetrics.rowInnerGap)
                .background(
                    selected ? Palette.primaryTint : Palette.pageBG,
                    in: Capsule()
                )
                .frame(minHeight: OneDayMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 已搜过才随来源切换重搜；还没搜时只记选择
    private func reseachIfActive() {
        if case .idle = phase { return }
        Task { await search() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            Section {
                ContentUnavailableView(
                    "搜索技能库",
                    systemImage: "bag",
                    description: Text("在顶部搜索框输入关键词（如 pdf、browser）并回车检索。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, OneDayMetrics.spacingL)
            }
            .listRowBackground(Color.clear)
        case .searching:
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在连接技能库…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            .listRowBackground(Palette.surface)
        case .results(let skills) where skills.isEmpty:
            Section {
                ContentUnavailableView(
                    "没有找到相关技能",
                    systemImage: "magnifyingglass",
                    description: Text("换个关键词，或切换来源再试。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, OneDayMetrics.spacingL)
            }
            .listRowBackground(Color.clear)
        case .results(let skills):
            Section {
                ForEach(skills) { skill in
                    hubRow(skill)
                }
            } header: {
                SettingsSectionHeader("搜索结果（\(skills.count)）")
            }
            .listRowBackground(Palette.surface)
        case .failed(let message):
            Section {
                ContentUnavailableView {
                    Label("搜索失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") { Task { await search() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OneDayMetrics.spacingM)
            }
            .listRowBackground(Color.clear)
        }
    }

    private func hubRow(_ skill: HubSkill) -> some View {
        NavigationLink {
            HubSkillDetailView(skill: skill, installedNames: $installedNames)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: OneDayMetrics.spacingXS) {
                    Text(skill.displayName)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    if installedNames.contains(skill.installedName) {
                        SettingsStatusPill(text: "已安装", tone: .healthy)
                    }
                }
                if let description = skill.description,
                   !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                Text(skill.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func search() async {
        let query = queryText.trimmingCharacters(in: .whitespaces)
        phase = .searching
        do {
            let results = try await appState.performAdmin { client, config in
                try await client.skillHubSearch(
                    config: config, query: query, source: selectedSource
                )
            }
            phase = .results(results)
        } catch HermesError.demoLimitReached {
            phase = .failed(HermesError.demoLimitReached.userMessage)
        } catch {
            phase = .failed("服务端连接外部技能库超时或出错，请稍后再试。")
        }
    }

    /// 来源拉不到就不显示来源筛选（不编造来源清单）
    private func loadSources() async {
        if let loaded = try? await appState.performAdmin({ client, config in
            try await client.skillHubSources(config: config)
        }) {
            sources = loaded
        }
    }

    private func refreshInstalled() async {
        if let skills = try? await appState.performAdmin({ client, config in
            try await client.skills(config: config)
        }) {
            installedNames = Set(skills.map(\.name))
        }
    }
}

/// 商店技能详情：预览（SKILL.md 全文＋文件清单）＋安装/卸载。
struct HubSkillDetailView: View {
    @Environment(AppState.self) private var appState

    let skill: HubSkill
    @Binding var installedNames: Set<String>

    @State private var preview: HubPreview?
    @State private var previewFailed = false
    @State private var previewFailureMessage: String?
    @State private var isActing = false
    @State private var actionNote: String?
    @State private var confirmUninstall = false

    private var isInstalled: Bool {
        installedNames.contains(skill.installedName)
    }

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "puzzlepiece.extension.fill",
                tint: .indigo,
                title: skill.displayName,
                subtitle: skill.description?.isEmpty == false
                    ? (skill.description ?? "")
                    : "来自 \(skill.sourceLabel) 的扩展技能包",
                statusText: isInstalled ? "已安装" : "未安装",
                statusTone: isInstalled ? .healthy : .neutral
            )

            Section {
                SettingsValueRow(
                    symbol: "globe",
                    tint: .indigo,
                    title: "来源",
                    value: skill.sourceLabel
                )
                if let author = skill.author, !author.isEmpty {
                    SettingsValueRow(
                        symbol: "person",
                        tint: .blue,
                        title: "作者",
                        value: author
                    )
                }
                if let version = skill.version, !version.isEmpty {
                    SettingsValueRow(
                        symbol: "tag",
                        tint: .teal,
                        title: "版本",
                        value: version
                    )
                }
            } header: {
                SettingsSectionHeader("基本信息")
            }
            .listRowBackground(Palette.surface)

            Section {
                if isInstalled {
                    Button(role: .destructive) {
                        confirmUninstall = true
                    } label: {
                        HStack {
                            Spacer()
                            if isActing {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text(isActing ? "正在卸载…" : "卸载技能")
                                .font(.rowTitleL.weight(.semibold))
                                .foregroundStyle(Palette.danger)
                            Spacer()
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    }
                    .disabled(isActing)
                    .listRowBackground(Palette.surface)
                } else {
                    Button {
                        Task { await install() }
                    } label: {
                        HStack {
                            Spacer()
                            if isActing {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 6)
                            }
                            Text(isActing ? "正在安装…" : "安装技能")
                                .font(.rowTitleL.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    }
                    .disabled(isActing)
                    .listRowBackground(Palette.primary)
                }
            } footer: {
                if let actionNote {
                    Text(actionNote)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            previewSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle(skill.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPreview() }
        .confirmationDialog(
            "卸载这个技能？",
            isPresented: $confirmUninstall,
            titleVisibility: .visible
        ) {
            Button("卸载", role: .destructive) {
                Task { await uninstall() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("卸载后智能体将不能再用这个技能，随时可以重新安装。")
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview {
            if let content = preview.content, !content.isEmpty {
                Section {
                    MarkdownText(content)
                        .padding(.vertical, 4)
                } header: {
                    SettingsSectionHeader("技能说明")
                }
                .listRowBackground(Palette.surface)
            }
            if !preview.files.isEmpty {
                Section {
                    ForEach(preview.files, id: \.self) { file in
                        Label(file, systemImage: "doc")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink)
                    }
                } header: {
                    SettingsSectionHeader("包含文件（\(preview.files.count)）")
                }
                .listRowBackground(Palette.surface)
            }
            if (preview.content ?? "").isEmpty && preview.files.isEmpty {
                Section {
                    Text("预览没有返回内容。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                } header: {
                    SettingsSectionHeader("技能说明")
                }
                .listRowBackground(Palette.surface)
            }
        } else if previewFailed {
            Section {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                    Text(previewFailureMessage ?? "预览读取失败：服务端连接外部技能库超时或出错。")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                    Button("重试读取预览") { Task { await loadPreview() } }
                        .font(.footnote.weight(.medium))
                }
                .padding(.vertical, 4)
            } header: {
                SettingsSectionHeader("技能说明")
            }
            .listRowBackground(Palette.surface)
        } else {
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取预览…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } header: {
                SettingsSectionHeader("技能说明")
            }
            .listRowBackground(Palette.surface)
        }
    }

    private func loadPreview() async {
        previewFailed = false
        previewFailureMessage = nil
        do {
            preview = try await appState.performAdmin { client, config in
                try await client.skillHubPreview(
                    config: config, identifier: skill.identifier
                )
            }
        } catch HermesError.demoLimitReached {
            previewFailed = true
            previewFailureMessage = HermesError.demoLimitReached.userMessage
        } catch {
            previewFailed = true
        }
    }

    /// 安装：POST 只算提交，回读已装列表出现才算装上；
    /// 没出现如实提示后台处理中，不假报成功
    private func install() async {
        isActing = true
        actionNote = nil
        defer { isActing = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.skillHubInstall(
                    config: config, identifier: skill.identifier
                )
            }
        } catch HermesError.demoLimitReached {
            actionNote = HermesError.demoLimitReached.userMessage
            return
        } catch {
            actionNote = "安装提交失败，请稍后再试。"
            return
        }
        await refreshInstalled()
        if !isInstalled {
            actionNote = "已提交安装，服务端后台处理中——稍后在技能列表里确认是否出现。"
        }
    }

    /// 卸载：同口径——回读确认消失才算卸掉
    private func uninstall() async {
        isActing = true
        actionNote = nil
        defer { isActing = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.skillHubUninstall(
                    config: config, name: skill.installedName
                )
            }
        } catch HermesError.demoLimitReached {
            actionNote = HermesError.demoLimitReached.userMessage
            return
        } catch {
            actionNote = "卸载提交失败，请稍后再试。"
            return
        }
        await refreshInstalled()
        if isInstalled {
            actionNote = "已提交卸载，服务端后台处理中——稍后在技能列表里确认。"
        }
    }

    private func refreshInstalled() async {
        if let skills = try? await appState.performAdmin({ client, config in
            try await client.skills(config: config)
        }) {
            installedNames = Set(skills.map(\.name))
        }
    }
}
