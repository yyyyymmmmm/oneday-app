import OneDayDesign
import OneDayCore
import SwiftUI

/// 技能页（P1-3 重构：原生 iOS 26 List(.insetGrouped) + SettingsHeroCard + 行内开关）
struct SkillsView: View {
    @Environment(AppState.self) private var appState

    @State private var skills: [SkillItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var notice: String?
    @State private var toggling: String?

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "puzzlepiece.extension.fill",
                tint: .indigo,
                title: "智能体技能",
                subtitle: "为智能体安装、启用或锁定领域技能与工作流。",
                statusText: skills.isEmpty ? nil : "已启用 \(skills.filter(\.isEnabled).count) / \(skills.count)",
                statusTone: .healthy
            )

            Section {
                NavigationLink {
                    SkillHubView()
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "bag")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("技能商店")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Text("从技能库搜索并安装新技能")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer(minLength: OneDayMetrics.spacingS)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            if !skills.isEmpty {
                ForEach(skillGroups, id: \.label) { group in
                    Section {
                        ForEach(group.items) { skill in
                            skillRow(skill)
                        }
                    } header: {
                        SettingsSectionHeader(group.label)
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }
            } else if let errorMessage {
                Section {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .foregroundStyle(Palette.primary)
                }
                .listRowBackground(Palette.surface)
            } else if isLoading {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取技能…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Palette.surface)
            } else {
                Section {
                    ContentUnavailableView(
                        "还没有技能",
                        systemImage: "puzzlepiece.extension",
                        description: Text("服务端尚未安装任何技能，可前往技能商店浏览安装。")
                    )
                }
                .listRowBackground(Color.clear)
            }

            Section {
                CuratorBlock()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("技能")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var skillGroups: [(label: String, items: [SkillItem])] {
        ServerLabels.grouped(skills) { $0.category }
    }

    private func skillRow(_ skill: SkillItem) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            NavigationLink {
                SkillDetailView(skill: skill)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text(skill.name)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        if skill.locked == true {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(Palette.inkMuted)
                                .accessibilityLabel("已锁定")
                        }
                    }
                    if let description = skill.description,
                       !description.isEmpty,
                       ServerLabels.isChineseText(description) {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Toggle("", isOn: toggleBinding(for: skill))
                .labelsHidden()
                .disabled(skill.locked == true || toggling == skill.name)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private func toggleBinding(for skill: SkillItem) -> Binding<Bool> {
        Binding(
            get: { skill.isEnabled },
            set: { newValue in
                Task { await toggle(skill, to: newValue) }
            }
        )
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            skills = try await appState.performAdmin { client, config in
                try await client.skills(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "技能没读出来，可能是网络或服务暂时没响应"
        }
    }

    private func toggle(_ skill: SkillItem, to newValue: Bool) async {
        toggling = skill.name
        defer { toggling = nil }
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index] = SkillItem(
                name: skill.name, description: skill.description,
                category: skill.category, locked: skill.locked,
                enabled: newValue, usage: skill.usage,
                provenance: skill.provenance
            )
        }
        do {
            try await appState.performAdmin { client, config in
                try await client.toggleSkill(
                    config: config, name: skill.name, enabled: newValue
                )
            }
        } catch {
            if let index = skills.firstIndex(where: { $0.id == skill.id }) {
                skills[index] = skill
            }
            notice = (error as? HermesError)?.userMessage ?? "开关失败，请稍后再试。"
        }
    }
}

/// 技能详情：内容（SKILL.md）查看与编辑、启用开关、锁定开关
struct SkillDetailView: View {
    @Environment(AppState.self) private var appState
    let skill: SkillItem

    @State private var content: String?
    @State private var draft: String = ""
    @State private var isEditing = false
    @State private var isEnabled: Bool
    @State private var isLocked: Bool
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var isSaving = false

    init(skill: SkillItem) {
        self.skill = skill
        _isEnabled = State(initialValue: skill.isEnabled)
        _isLocked = State(initialValue: skill.locked ?? false)
    }

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "puzzlepiece.extension.fill",
                tint: .indigo,
                title: skill.name,
                subtitle: skill.description ?? "查看或编辑此技能的 SKILL.md 指令定义。",
                statusText: isLocked ? "已锁定" : (isEnabled ? "已启用" : "已停用"),
                statusTone: isLocked ? .warning : (isEnabled ? .healthy : .neutral)
            )
            metaGroup
            contentGroup
            if let notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var metaGroup: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                Text("启用")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
            }
            .disabled(isLocked)
            .onChange(of: isEnabled) { _, newValue in
                Task { await setEnabled(newValue) }
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)

            Toggle(isOn: $isLocked) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("锁定")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text("锁定后不能改内容、不能停用")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .onChange(of: isLocked) { _, newValue in
                Task { await setLocked(newValue) }
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
        } header: {
            SettingsSectionHeader("状态控制")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    private var contentGroup: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                if isEditing {
                    TextEditor(text: $draft)
                        .font(.metaMonospaced)
                        .frame(minHeight: 320)
                        .scrollContentBackground(.hidden)
                        .padding(OneDayMetrics.spacingS)
                } else if let content {
                    Text(content)
                        .font(.metaMonospaced)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OneDayMetrics.spacingM)
                } else if let errorMessage {
                    InlineError(errorMessage)
                        .padding(OneDayMetrics.spacingM)
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取内容…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(OneDayMetrics.spacingM)
                }
            }
            .background(
                Palette.fieldFill,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.codeCorner)
            )
        } header: {
            HStack(alignment: .firstTextBaseline) {
                SettingsSectionHeader("内容（SKILL.md）")
                Spacer()
                if isEditing {
                    Button("取消") {
                        draft = content ?? ""
                        isEditing = false
                    }
                    .font(.callout)
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await saveContent() }
                    }
                    .font(.callout)
                    .disabled(isSaving)
                } else if content != nil {
                    Button("编辑") {
                        draft = content ?? ""
                        isEditing = true
                    }
                    .font(.callout)
                    .disabled(isLocked)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    private func load() async {
        do {
            let loaded = try await appState.performAdmin { client, config in
                try await client.skillContent(config: config, name: skill.name)
            }
            content = loaded.content
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "内容没读出来，可能是网络或服务暂时没响应"
        }
    }

    private func saveContent() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.updateSkillContent(
                    config: config, name: skill.name, content: draft
                )
            }
            content = draft
            isEditing = false
            notice = "内容已保存。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "保存失败，请稍后再试。"
        }
    }

    private func setEnabled(_ newValue: Bool) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.toggleSkill(
                    config: config, name: skill.name, enabled: newValue
                )
            }
        } catch {
            isEnabled = !newValue
            notice = (error as? HermesError)?.userMessage ?? "开关失败，请稍后再试。"
        }
    }

    private func setLocked(_ newValue: Bool) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.lockSkill(
                    config: config, name: skill.name, locked: newValue
                )
            }
        } catch {
            isLocked = !newValue
            notice = (error as? HermesError)?.userMessage ?? "锁定操作失败，请稍后再试。"
        }
    }
}
