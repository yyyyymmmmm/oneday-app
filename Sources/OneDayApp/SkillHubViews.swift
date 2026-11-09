import OneDayCore
import OneDayDesign
import SwiftUI

/// 技能商店（P10）：/api/skills/hub 搜索/预览/安装/卸载。
/// 数据源实查（2026-11-09 只读联调）：三端点在 OpenAPI
/// 在册，但本部署服务端抓外部注册表时出网受阻、30 秒
/// 无响应——本页全部状态如实露：慢/失败给原因与重试，
/// 绝不拿空结果冒充「商店里没东西」。
/// 安装/卸载是服务端动作：POST 成功只算已提交，必须
/// 回读已装列表对账（出现/消失）才标已装/已卸，与本仓
/// 写动作回读口径一致。
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchBar
                if !sources.isEmpty {
                    sourceChips
                }
                content
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("技能商店")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSources()
            await refreshInstalled()
        }
    }

    private var searchBar: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            TextField("搜索技能，如 pdf、browser", text: $queryText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
            Button("搜索") { Task { await search() } }
                .buttonStyle(.odPrimary)
                .disabled(isSearching)
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
            .padding(.vertical, OneDayMetrics.spacingSM)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selected ? Palette.primaryTint : Palette.surface,
                    in: Capsule()
                )
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
            EmptyState(
                icon: "bag",
                title: "搜索技能库",
                message: "输入关键词搜索可安装的技能。服务端会直接连接外部技能库，网络不通时可能较慢或失败。"
            )
            .padding(.top, OneDayMetrics.spacingXXL)
        case .searching:
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在连接技能库…服务端直连外部技能库，可能需要一会儿")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.top, OneDayMetrics.spacingL)
        case .results(let skills) where skills.isEmpty:
            EmptyState(
                icon: "magnifyingglass",
                title: "没有找到相关技能",
                message: "换个关键词，或切换来源再试。"
            )
            .padding(.top, OneDayMetrics.spacingXXL)
        case .results(let skills):
            VStack(spacing: 0) {
                ForEach(
                    Array(skills.enumerated()), id: \.element.id
                ) { index, skill in
                    if index > 0 {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                    }
                    hubRow(skill)
                }
            }
            .odGroup()
            .padding(.top, OneDayMetrics.spacingS)
        case .failed(let message):
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                InlineError(message)
                Button("重试") { Task { await search() } }
                    .buttonStyle(.odSecondary)
            }
            .padding(.top, OneDayMetrics.spacingL)
        }
    }

    private func hubRow(_ skill: HubSkill) -> some View {
        NavigationLink {
            HubSkillDetailView(skill: skill, installedNames: $installedNames)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text(skill.displayName)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        if installedNames.contains(skill.installedName) {
                            Text("已安装")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.success)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Palette.success.opacity(0.12), in: Capsule()
                                )
                        }
                    }
                    // 商店目录文案是内容不是界面装饰：与技能页
                    // 「英文不上屏」口径不同，这里照原文呈现，
                    // 用户靠它判断装不装
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
        } catch {
            phase = .failed("搜索失败：服务端连接外部技能库超时或出错，请稍后重试。")
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

/// 商店技能详情：预览（SKILL.md 全文＋文件清单）＋
/// 安装/卸载。安装态以父页共享的已装名集为准，动作后
/// 回读刷新该集合，父页行徽章随之同步。
struct HubSkillDetailView: View {
    @Environment(AppState.self) private var appState

    let skill: HubSkill
    @Binding var installedNames: Set<String>

    @State private var preview: HubPreview?
    @State private var previewFailed = false
    @State private var isActing = false
    @State private var actionNote: String?
    @State private var confirmUninstall = false

    private var isInstalled: Bool {
        installedNames.contains(skill.installedName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                actionArea
                    .padding(.top, OneDayMetrics.spacingM)
                if let actionNote {
                    Text(actionNote)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingS)
                }
                previewArea
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text(skill.displayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
            HStack(spacing: OneDayMetrics.spacingS) {
                Text("来源 \(skill.sourceLabel)")
                if let author = skill.author, !author.isEmpty {
                    Text("作者 \(author)")
                }
                if let version = skill.version, !version.isEmpty {
                    Text("版本 \(version)")
                }
            }
            .font(.caption)
            .foregroundStyle(Palette.inkSecondary)
            if let description = skill.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if isInstalled {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Label("已安装", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.success)
                Spacer()
                Button("卸载", role: .destructive) {
                    confirmUninstall = true
                }
                .buttonStyle(.odSecondary)
                .disabled(isActing)
            }
        } else {
            Button {
                Task { await install() }
            } label: {
                if isActing {
                    ProgressView()
                } else {
                    Text("安装")
                }
            }
            .buttonStyle(.odPrimary)
            .disabled(isActing)
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        SectionLabel("技能说明")
            .padding(.top, 28)
            .padding(.bottom, OneDayMetrics.spacingS)
        if let preview {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                if let content = preview.content, !content.isEmpty {
                    MarkdownText(content)
                }
                if !preview.files.isEmpty {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                        Text("包含文件")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.inkSecondary)
                        ForEach(preview.files, id: \.self) { file in
                            Label(file, systemImage: "doc")
                                .font(.footnote)
                                .foregroundStyle(Palette.ink)
                        }
                    }
                }
                if (preview.content ?? "").isEmpty && preview.files.isEmpty {
                    Text("预览没有返回内容。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        } else if previewFailed {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                InlineError("预览读取失败：服务端连接外部技能库超时或出错。")
                Button("重试") { Task { await loadPreview() } }
                    .buttonStyle(.odSecondary)
            }
        } else {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在读取预览…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func loadPreview() async {
        previewFailed = false
        do {
            preview = try await appState.performAdmin { client, config in
                try await client.skillHubPreview(
                    config: config, identifier: skill.identifier
                )
            }
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
        } catch {
            actionNote = "安装提交失败，请稍后重试。"
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
        } catch {
            actionNote = "卸载提交失败，请稍后重试。"
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
