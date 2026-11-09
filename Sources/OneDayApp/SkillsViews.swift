import OneDayDesign
import OneDayCore
import SwiftUI

/// 技能页（智能体格，IA v3 §5.2）：已装技能列表＋行内开关，
/// 点入详情看/改内容与锁定。顶部「技能商店」入口进
/// SkillHubView（P10 已接 /api/skills/hub）。锁定中的技能
/// 行内开关禁用（锁的语义就是防误改），解锁在详情页。
struct SkillsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var skills: [SkillItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var notice: String?
    /// 正在写开关的技能名（防重复点）
    @State private var toggling: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 技能商店入口（P10）：独立成组置顶，常驻
                VStack(spacing: 0) {
                    NavigationLink {
                        SkillHubView()
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Image(systemName: "bag")
                                .font(.system(size: 16))
                                .foregroundStyle(Palette.inkSecondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("技能商店")
                                    .font(.body)
                                    .foregroundStyle(Palette.ink)
                                Text("从技能库搜索并安装新技能")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer(minLength: OneDayMetrics.spacingS)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Palette.inkMuted)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
                .odGroup()
                .padding(.bottom, OneDayMetrics.spacingM)
                if !skills.isEmpty {
                    // 0.3.7 卡 14：摘要卡「已装 N · 启用 M」＋
                    // 按服务端类别分组（已裁 4，类别名走翻译）
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text("已装 \(skills.count) 个 · 启用 \(skills.filter(\.isEnabled).count) 个")
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .odGroup()
                    ForEach(
                        Array(skillGroups.enumerated()), id: \.element.label
                    ) { _, group in
                        SectionLabel(group.label)
                            .padding(.top, 28)
                            .padding(.bottom, OneDayMetrics.spacingS)
                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, skill in
                                if index > 0 {
                                    GroupDivider(inset: OneDayMetrics.spacingM)
                                }
                                skillRow(skill)
                            }
                        }
                        .odGroup()
                    }
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else if isLoading {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取技能…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                } else {
                    EmptyState(
                        icon: "puzzlepiece.extension",
                        title: "还没有技能",
                        message: "服务端尚未安装任何技能。"
                    )
                    .padding(.top, OneDayMetrics.spacingXXL)
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
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
                HStack(spacing: OneDayMetrics.spacingSM) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: OneDayMetrics.spacingXS) {
                            Text(skill.name)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            if skill.locked == true {
                                Image(systemName: "lock")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.inkMuted)
                                    .accessibilityLabel("已锁定")
                            }
                        }
                        // 卡 14：英文 description 不上屏；
                        // category 原文小字删（已升组头译名）
                        if let description = skill.description,
                           !description.isEmpty,
                           ServerLabels.isChineseText(description) {
                            Text(description)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: toggleBinding(for: skill))
                .labelsHidden()
                .disabled(skill.locked == true || toggling == skill.name)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
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
            errorMessage = (error as? HermesError)?.userMessage ?? "技能读取失败。"
        }
    }

    private func toggle(_ skill: SkillItem, to newValue: Bool) async {
        toggling = skill.name
        defer { toggling = nil }
        // 先乐观更新，失败回滚并提示
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

/// 技能详情：内容（SKILL.md）查看与编辑、启用开关、锁定开关。
/// 内容是代码类文本：等宽、字段面底，编辑走 TextEditor 全量保存。
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                metaGroup
                contentGroup
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var metaGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("技能")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if let description = skill.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GroupDivider(inset: OneDayMetrics.spacingM)
                }
                HStack {
                    Text("启用")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .disabled(isLocked)
                        .onChange(of: isEnabled) { _, newValue in
                            Task { await setEnabled(newValue) }
                        }
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                GroupDivider(inset: OneDayMetrics.spacingM)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("锁定")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text("锁定后不能改内容、不能停用")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $isLocked)
                        .labelsHidden()
                        .onChange(of: isLocked) { _, newValue in
                            Task { await setLocked(newValue) }
                        }
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
            }
            .odGroup()
        }
    }

    private var contentGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("内容（SKILL.md）")
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
                    // 卡 17：medium 退出，保存钮 regular
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
            .padding(.top, 28)
            .padding(.bottom, OneDayMetrics.spacingS)
            Group {
                if isEditing {
                    TextEditor(text: $draft)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 320)
                        .scrollContentBackground(.hidden)
                        .padding(OneDayMetrics.spacingS)
                } else if let content {
                    Text(content)
                        .font(.system(.footnote, design: .monospaced))
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
        }
    }

    private func load() async {
        do {
            let loaded = try await appState.performAdmin { client, config in
                try await client.skillContent(config: config, name: skill.name)
            }
            content = loaded.content
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "内容读取失败。"
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
