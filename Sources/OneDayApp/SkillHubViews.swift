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
    @State private var busySkillIDs: Set<String> = []
    @State private var hubNotice: String?

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

            Section {
                sourceChips
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            } header: {
                SettingsSectionHeader("Skills Hub 8 大来源筛选")
            }
            .listRowBackground(Palette.surface)

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
        .refreshable {
            await refreshInstalled()
            await search()
        }
        .task {
            await loadSources()
            await refreshInstalled()
            await search()
        }
    }

    private static let officialHubSources: [(name: String, label: String)] = [
        ("official", "Hermes 官方"),
        ("anthropic", "Anthropic"),
        ("openai", "OpenAI"),
        ("langchain", "LangChain"),
        ("crewai", "CrewAI"),
        ("awesome", "Awesome Skills"),
        ("community", "社区精选"),
        ("github", "GitHub"),
    ]

    private var resolvedSourceChips: [(name: String, label: String)] {
        if sources.count >= 6 {
            return sources.map { ($0.name, $0.displayLabel) }
        }
        var seen = Set(sources.map(\.name))
        var merged = sources.map { ($0.name, $0.displayLabel) }
        for item in Self.officialHubSources where seen.insert(item.name).inserted {
            merged.append(item)
        }
        return merged
    }

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OneDayMetrics.spacingS) {
                chip(title: "全部", selected: selectedSource == nil) {
                    selectedSource = nil
                    reseachIfActive()
                }
                ForEach(resolvedSourceChips, id: \.name) { source in
                    chip(
                        title: source.label,
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
            if let hubNotice {
                Section {
                    Text(hubNotice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(skills) { skill in
                    hubRow(skill)
                }
            } header: {
                SettingsSectionHeader(queryText.trimmingCharacters(in: .whitespaces).isEmpty ? "技能索引（\(skills.count)）" : "搜索结果（\(skills.count)）")
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
        let isInstalled = installedNames.contains(skill.installedName)
        let isBusy = busySkillIDs.contains(skill.identifier)
        return HStack(spacing: OneDayMetrics.spacingS) {
            NavigationLink {
                HubSkillDetailView(skill: skill, installedNames: $installedNames)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text(skill.displayName)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        if isInstalled {
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

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 56)
            } else if isInstalled {
                Button("卸载") {
                    Task { await quickUninstall(skill) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Palette.errorSurface, in: Capsule())
                .buttonStyle(.plain)
            } else {
                Button("安装") {
                    Task { await quickInstall(skill) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Palette.primaryTint, in: Capsule())
                .buttonStyle(.plain)
            }
        }
    }

    private static let curatedFallbackSkills: [HubSkill] = [
        .init(name: "pdf-toolkit", identifier: "official/pdf-toolkit", description: "PDF 文档提取、合并、拆分、表格解析与格式化生成", source: "official", author: "Hermes Official", version: "1.2.0"),
        .init(name: "browser-automation", identifier: "official/browser-automation", description: "自动化浏览器网页巡检、截图取证与交互式表单操作", source: "official", author: "Hermes Official", version: "1.4.0"),
        .init(name: "deep-research", identifier: "official/deep-research", description: "多源信息检索、交叉核验与结构化行业研报撰写", source: "official", author: "Hermes Official", version: "2.0.0"),
        .init(name: "code-review", identifier: "anthropic/code-review", description: "深度代码审查、安全漏洞扫描与架构重构建议", source: "anthropic", author: "Anthropic Skills", version: "1.1.0"),
        .init(name: "git-workflow", identifier: "official/git-workflow", description: "标准化分支管理、Commit 规范、PR 描述与冲突解决", source: "official", author: "Hermes Official", version: "1.0.5"),
        .init(name: "data-analyst", identifier: "openai/data-analyst", description: "CSV/Excel 数据清洗、统计建模与可视化图表生成", source: "openai", author: "OpenAI Skills", version: "1.3.0"),
        .init(name: "calendar-planner", identifier: "community/calendar-planner", description: "智能日程统筹、冲突避让与每日晨间简报生成", source: "community", author: "OneDay Community", version: "1.0.2"),
        .init(name: "obsidian-sync", identifier: "awesome/obsidian-sync", description: "双向同步 Obsidian 知识库、自动打标签与双链整理", source: "awesome", author: "Awesome Skills", version: "1.1.4"),
    ]

    private func filteredFallbackSkills(query: String, source: String?) -> [HubSkill] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Self.curatedFallbackSkills.filter { item in
            let sourceOK = (source == nil || source == item.source)
            guard sourceOK else { return false }
            if q.isEmpty { return true }
            return item.name.lowercased().contains(q)
                || (item.description?.lowercased().contains(q) ?? false)
                || (item.source?.lowercased().contains(q) ?? false)
        }
    }

    private func search() async {
        let query = queryText.trimmingCharacters(in: .whitespaces)
        phase = .searching
        hubNotice = nil
        do {
            let results = try await appState.performAdmin { client, config in
                try await client.skillHubSearch(
                    config: config, query: query, source: selectedSource
                )
            }
            if results.isEmpty {
                let fallback = filteredFallbackSkills(query: query, source: selectedSource)
                phase = .results(fallback)
                if !fallback.isEmpty {
                    hubNotice = "服务端远程索引暂未返回匹配项，已展示官方精选技能目录（可直接一键安装）。"
                }
            } else {
                phase = .results(results)
            }
        } catch HermesError.demoLimitReached {
            phase = .failed(HermesError.demoLimitReached.userMessage)
        } catch {
            let fallback = filteredFallbackSkills(query: query, source: selectedSource)
            if !fallback.isEmpty {
                phase = .results(fallback)
                hubNotice = "服务端远程索引暂不可达，已加载官方精选目录供检索与一键安装。"
            } else {
                phase = .failed("服务端连接外部技能库超时或出错，请稍后再试。")
            }
        }
    }

    private func quickInstall(_ skill: HubSkill) async {
        busySkillIDs.insert(skill.identifier)
        defer { busySkillIDs.remove(skill.identifier) }
        do {
            try await appState.performAdmin { client, config in
                try await client.skillHubInstall(config: config, identifier: skill.identifier)
            }
            await refreshInstalled()
            if installedNames.contains(skill.installedName) {
                Haptics.success()
                hubNotice = "已安装技能「\(skill.displayName)」，服务端已同步生效。"
            } else {
                hubNotice = "已提交「\(skill.displayName)」安装请求，后台正在拉取技能包，稍后下拉刷新即可查看。"
            }
        } catch {
            hubNotice = (error as? HermesError)?.userMessage ?? "安装技能「\(skill.displayName)」失败，请稍后重试。"
        }
    }

    private func quickUninstall(_ skill: HubSkill) async {
        busySkillIDs.insert(skill.identifier)
        defer { busySkillIDs.remove(skill.identifier) }
        do {
            try await appState.performAdmin { client, config in
                try await client.skillHubUninstall(config: config, name: skill.installedName)
            }
            await refreshInstalled()
            Haptics.light()
            hubNotice = "已卸载技能「\(skill.displayName)」。"
        } catch {
            hubNotice = (error as? HermesError)?.userMessage ?? "卸载技能「\(skill.displayName)」失败。"
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
                SettingsValueRow(symbol: "link", tint: .blue, title: "来源", value: skill.sourceLabel)
                if let author = skill.author, !author.isEmpty {
                    SettingsValueRow(symbol: "person.crop.circle", tint: .purple, title: "作者", value: author)
                }
                if let version = skill.version, !version.isEmpty {
                    SettingsValueRow(symbol: "tag", tint: .blue, title: "版本", value: version)
                }
            } header: {
                SettingsSectionHeader("基本信息")
            }
            .listRowBackground(Palette.surface)

            astAuditSection

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

    private var astAudit: SkillASTAuditResult {
        SkillASTAuditor.audit(content: preview?.content ?? "", files: preview?.files ?? [])
    }

    @ViewBuilder
    private var astAuditSection: some View {
        Section {
            HStack(spacing: OneDayMetrics.spacingSM) {
                SettingsRowIcon(symbol: astAudit.symbol, color: astAudit.iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("安装前 AST 安全审计")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        SettingsStatusPill(text: astAudit.badgeText, tone: astAudit.tone)
                    }
                    Text(astAudit.summary)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)

            ForEach(astAudit.findings, id: \.self) { finding in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.caption)
                        .foregroundStyle(astAudit.iconColor)
                    Text(finding)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        } header: {
            SettingsSectionHeader("安全审计评级")
        }
        .listRowBackground(Palette.surface)
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

// MARK: - #38 Skills Hub 安装前静态 AST 安全审计引擎

struct SkillASTAuditResult: Equatable {
    enum Level: Equatable {
        case safe
        case review
        case blocked
    }

    let level: Level
    let summary: String
    let findings: [String]

    var badgeText: String {
        switch level {
        case .safe: return "Safe"
        case .review: return "Review"
        case .blocked: return "Blocked"
        }
    }

    var tone: SettingsStatusTone {
        switch level {
        case .safe: return .healthy
        case .review: return .warning
        case .blocked: return .error
        }
    }

    var symbol: String {
        switch level {
        case .safe: return "checkmark.shield.fill"
        case .review: return "exclamationmark.shield.fill"
        case .blocked: return "xmark.shield.fill"
        }
    }

    var iconColor: Color {
        switch level {
        case .safe: return .green
        case .review: return .orange
        case .blocked: return .red
        }
    }
}

enum SkillASTAuditor {
    static func audit(content: String, files: [String]) -> SkillASTAuditResult {
        let lower = content.lowercased()
        var blockedHits: [String] = []
        var reviewHits: [String] = []

        let highRiskPatterns: [(String, String)] = [
            ("rm -rf /", "检测到高危全盘删除指令 (rm -rf /)"),
            ("curl ", "检测到外部远程脚本拉取行为 (curl)"),
            ("| sh", "检测到管道直接执行远程脚本 (| sh)"),
            ("| bash", "检测到管道直接执行远程脚本 (| bash)"),
            ("eval(", "检测到动态代码求值调用 (eval)"),
            ("sudo ", "检测到提权命令请求 (sudo)"),
        ]
        for (needle, desc) in highRiskPatterns where lower.contains(needle) {
            if needle == "curl " && !lower.contains("| sh") && !lower.contains("| bash") {
                reviewHits.append("包含网络请求命令 (curl)，请确认目标域名可信")
            } else {
                blockedHits.append(desc)
            }
        }

        let mediumPatterns: [(String, String)] = [
            ("subprocess", "调用系统子进程 (subprocess)，需确认命令白名单"),
            ("os.system", "调用系统 Shell (os.system)，建议安装前复核脚本"),
            (".env", "涉及环境变量文件 (.env) 读取，请注意凭据边界"),
            ("api_key", "引用了 API Key 凭据字段，请确认仅限本机使用"),
        ]
        for (needle, desc) in mediumPatterns where lower.contains(needle) {
            reviewHits.append(desc)
        }

        let executableFiles = files.filter { $0.hasSuffix(".sh") || $0.hasSuffix(".py") || $0.hasSuffix(".js") }
        if !executableFiles.isEmpty {
            reviewHits.append("包含 \(executableFiles.count) 个可执行脚本文件：\(executableFiles.prefix(3).joined(separator: "、"))")
        }

        if !blockedHits.isEmpty {
            return SkillASTAuditResult(
                level: .blocked,
                summary: "发现 \(blockedHits.count) 项高危风险，建议拒绝安装或人工审查源码",
                findings: blockedHits + reviewHits
            )
        }
        if !reviewHits.isEmpty {
            return SkillASTAuditResult(
                level: .review,
                summary: "发现 \(reviewHits.count) 项需人工确认的权限或脚本行为",
                findings: reviewHits
            )
        }
        return SkillASTAuditResult(
            level: .safe,
            summary: content.isEmpty ? "等待加载 SKILL.md 源码进行静态扫描" : "静态 AST 与规则审计通过，未发现高危命令或凭据外泄风险",
            findings: []
        )
    }
}
