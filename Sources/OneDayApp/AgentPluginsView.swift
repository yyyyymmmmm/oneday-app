import OneDayCore
import OneDayDesign
import SwiftUI

/// Agent Plugins 插件市场（Hermes v0.23.0 `dashboard_ui.py` 全闭环）：
/// - 收口在「设置 → 智能体工作台 → 插件市场」，绝不污染一级设置页；
/// - 统一 Apple HIG 视觉语言：`SettingsHeroCard` + 29×29 语义色块 + `.searchable` 搜索；
/// - 支持已装插件一键启停/更新/卸载、全部更新、自动更新开关、官方精选目录安装以及自定义 Git/标识安装。
struct AgentPluginsView: View {
    @Environment(AppState.self) private var appState

    @State private var installed: [AgentPluginItem] = []
    @State private var catalog: [AgentPluginCatalogEntry] = []
    @State private var autoUpdate = false
    @State private var query = ""
    @State private var isLoading = false
    @State private var busyNames: Set<String> = []
    @State private var isUpdatingAll = false
    @State private var showCustomInstall = false
    @State private var errorMessage: String?
    @State private var notice: String?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredInstalled: [AgentPluginItem] {
        guard !trimmedQuery.isEmpty else { return installed }
        return installed.filter {
            $0.name.lowercased().contains(trimmedQuery)
                || ($0.description?.lowercased().contains(trimmedQuery) ?? false)
        }
    }

    private var filteredCatalog: [AgentPluginCatalogEntry] {
        let notInstalled = catalog.filter { !$0.installed }
        guard !trimmedQuery.isEmpty else { return notInstalled }
        return notInstalled.filter {
            $0.name.lowercased().contains(trimmedQuery)
                || ($0.title?.lowercased().contains(trimmedQuery) ?? false)
                || ($0.description?.lowercased().contains(trimmedQuery) ?? false)
        }
    }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                SettingsHeroCard(
                    symbol: "shippingbox.fill",
                    tint: Palette.tintLavenderInk,
                    title: "插件市场",
                    subtitle: "扩展 Hermes 的 Agent 插件、工具包与后台能力；启停与更新均即时同步服务端。",
                    statusText: installed.isEmpty ? nil : "已安装 \(installed.count) 个",
                    statusTone: .healthy
                )

                Section {
                    Toggle(isOn: Binding(
                        get: { autoUpdate },
                        set: { newValue in
                            Task { await toggleAutoUpdate(newValue) }
                        }
                    )) {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            SettingsRowIcon(symbol: "arrow.triangle.2.circlepath", color: Palette.tintSkyInk)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("自动更新插件")
                                    .font(.rowTitleL)
                                    .foregroundStyle(Palette.ink)
                                Text("后台自动更新无风险变更的已装插件")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)

                    if installed.contains(where: \.updateAvailable) {
                        Button {
                            Task { await updateAll() }
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingSM) {
                                SettingsRowIcon(symbol: "arrow.down.circle.fill", color: Palette.tintGreenInk)
                                Text(isUpdatingAll ? "正在更新全部插件…" : "一键更新全部可用插件")
                                    .font(.rowTitleL)
                                    .foregroundStyle(Palette.primary)
                                Spacer()
                                if isUpdatingAll { ProgressView().controlSize(.small) }
                            }
                            .frame(minHeight: OneDayMetrics.settingsRowHeight)
                        }
                        .disabled(isUpdatingAll)
                    }
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }

            if let notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
            }

            if isLoading && installed.isEmpty && catalog.isEmpty {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取插件市场…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage, installed.isEmpty && catalog.isEmpty {
                Section {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .foregroundStyle(Palette.primary)
                }
                .listRowBackground(Palette.surface)
            } else {
                if !filteredInstalled.isEmpty {
                    Section {
                        ForEach(filteredInstalled) { plugin in
                            installedRow(plugin)
                        }
                    } header: {
                        SettingsSectionHeader("已安装插件")
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }

                if !filteredCatalog.isEmpty {
                    Section {
                        ForEach(filteredCatalog) { entry in
                            catalogRow(entry)
                        }
                    } header: {
                        SettingsSectionHeader("精选插件目录")
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }

                if filteredInstalled.isEmpty && filteredCatalog.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("插件市场")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索已装插件或精选目录"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCustomInstall = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("通过地址安装插件")
            }
        }
        .sheet(isPresented: $showCustomInstall) {
            InstallCustomPluginSheet { identifier in
                await installCustom(identifier: identifier)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func installedRow(_ plugin: AgentPluginItem) -> some View {
        let isBusy = busyNames.contains(plugin.name)
        return HStack(spacing: OneDayMetrics.spacingSM) {
            SettingsRowIcon(
                symbol: "shippingbox.fill",
                color: plugin.enabled ? Palette.tintLavenderInk : Palette.inkMuted
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plugin.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    if let version = plugin.version, !version.isEmpty {
                        Text(version)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Palette.fillTertiary, in: Capsule())
                    }
                }
                if let desc = plugin.description, !desc.isEmpty {
                    Text(desc)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                if plugin.updateAvailable {
                    Button("更新") {
                        Task { await updatePlugin(plugin) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Palette.primaryTint, in: Capsule())
                    .buttonStyle(.plain)
                }
                Toggle("", isOn: Binding(
                    get: { plugin.enabled },
                    set: { newValue in
                        Task { await togglePlugin(plugin, enabled: newValue) }
                    }
                ))
                .labelsHidden()
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .swipeActions(edge: .trailing) {
            Button("卸载", role: .destructive) {
                Task { await deletePlugin(plugin) }
            }
        }
    }

    private func catalogRow(_ entry: AgentPluginCatalogEntry) -> some View {
        let isBusy = busyNames.contains(entry.name)
        return HStack(spacing: OneDayMetrics.spacingSM) {
            SettingsRowIcon(symbol: "sparkles.rectangle.stack.fill", color: Palette.tintSkyInk)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title ?? entry.name)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                if let desc = entry.description, !desc.isEmpty {
                    Text(desc)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                Button("安装") {
                    Task { await installCatalog(entry) }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Palette.primaryTint, in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private static let curatedFallbackCatalog: [AgentPluginCatalogEntry] = [
        .init(name: "kanban", title: "多 Agent 协同看板", description: "任务认领、状态流转、依赖管理与分身指派", identifier: "hermes-plugin-kanban", installed: false),
        .init(name: "browser-use", title: "浏览器自动化控制", description: "远程无头浏览器网页交互、截图与表单填写", identifier: "hermes-plugin-browser-use", installed: false),
        .init(name: "memory-honcho", title: "Honcho 深度记忆引擎", description: "跨会话用户画像与长期语义推理记忆插件", identifier: "hermes-plugin-memory-honcho", installed: false),
        .init(name: "git-worktree", title: "Git Worktree 隔离工作台", description: "多子分身并发修改代码自动隔离分支与 Diff 审阅", identifier: "hermes-plugin-git-worktree", installed: false),
        .init(name: "web-research", title: "深度网页调研套件", description: "多源网页抓取、摘要提取与引用核验工具集", identifier: "hermes-plugin-web-research", installed: false),
        .init(name: "voice-tts", title: "多引擎语音合成扩展", description: "接入 Edge / OpenAI / ElevenLabs / Kokoro 语音播报", identifier: "hermes-plugin-voice-tts", installed: false),
    ]

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let installedNames: Set<String>
        do {
            async let hub = appState.performAdmin { client, config in
                try await client.pluginsHub(config: config)
            }
            async let cat = appState.performAdmin { client, config in
                try await client.pluginsCatalog(config: config)
            }
            async let auto = appState.performAdmin { client, config in
                try await client.pluginsAutoUpdate(config: config)
            }
            installed = (try? await hub) ?? []
            installedNames = Set(installed.map(\.name))
            let remoteCatalog = (try? await cat) ?? []
            if remoteCatalog.isEmpty {
                catalog = Self.curatedFallbackCatalog.filter { !installedNames.contains($0.name) }
                notice = "服务端插件目录暂未返回数据，已展示 Hermes 官方精选插件目录（点击即可安装）。"
            } else {
                catalog = remoteCatalog
            }
            autoUpdate = (try? await auto)?.enabled ?? false
            errorMessage = nil
        } catch {
            installedNames = Set(installed.map(\.name))
            catalog = Self.curatedFallbackCatalog.filter { !installedNames.contains($0.name) }
            errorMessage = nil
            notice = "服务端插件接口暂不可达，已加载官方精选目录供检索与安装。"
        }
    }

    private func toggleAutoUpdate(_ enabled: Bool) async {
        autoUpdate = enabled
        do {
            let state = try await appState.performAdmin { client, config in
                try await client.setPluginsAutoUpdate(config: config, enabled: enabled)
            }
            autoUpdate = state.enabled
        } catch {
            autoUpdate = !enabled
            notice = (error as? HermesError)?.userMessage ?? "自动更新设置失败。"
        }
    }

    private func togglePlugin(_ plugin: AgentPluginItem, enabled: Bool) async {
        busyNames.insert(plugin.name)
        defer { busyNames.remove(plugin.name) }
        do {
            try await appState.performAdmin { client, config in
                try await client.setAgentPluginEnabled(config: config, name: plugin.name, enabled: enabled)
            }
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "切换插件状态失败。"
        }
    }

    private func updatePlugin(_ plugin: AgentPluginItem) async {
        busyNames.insert(plugin.name)
        defer { busyNames.remove(plugin.name) }
        do {
            try await appState.performAdmin { client, config in
                try await client.updateAgentPlugin(config: config, name: plugin.name)
            }
            notice = "插件「\(plugin.name)」已更新。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "更新插件失败。"
        }
    }

    private func updateAll() async {
        isUpdatingAll = true
        defer { isUpdatingAll = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.updateAllAgentPlugins(config: config)
            }
            notice = "已执行全部插件更新。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "批量更新失败。"
        }
    }

    private func deletePlugin(_ plugin: AgentPluginItem) async {
        busyNames.insert(plugin.name)
        defer { busyNames.remove(plugin.name) }
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteAgentPlugin(config: config, name: plugin.name)
            }
            notice = "已卸载插件「\(plugin.name)」。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "卸载插件失败。"
        }
    }

    private func installCatalog(_ entry: AgentPluginCatalogEntry) async {
        busyNames.insert(entry.name)
        defer { busyNames.remove(entry.name) }
        do {
            try await appState.performAdmin { client, config in
                try await client.installAgentPlugin(
                    config: config,
                    identifier: entry.identifier,
                    catalogName: entry.name,
                    enable: true
                )
            }
            notice = "已安装插件「\(entry.title ?? entry.name)」。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "安装插件失败。"
        }
    }

    private func installCustom(identifier: String) async -> Bool {
        do {
            try await appState.performAdmin { client, config in
                try await client.installAgentPlugin(
                    config: config,
                    identifier: identifier,
                    catalogName: nil,
                    enable: true
                )
            }
            notice = "已安装插件「\(identifier)」。"
            await load()
            return true
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "安装自定义插件失败。"
            return false
        }
    }
}

private struct InstallCustomPluginSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onInstall: (String) async -> Bool

    @State private var identifier = ""
    @State private var isSubmitting = false

    private var trimmed: String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("插件来源") {
                    TextField("GitHub owner/repo 或插件标识", text: $identifier)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("支持 Hermes 官方目录名、GitHub 仓库路径（如 owner/repo）或 Git URL。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .navigationTitle("安装外部插件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "安装中…" : "安装") {
                        Task {
                            isSubmitting = true
                            let ok = await onInstall(trimmed)
                            isSubmitting = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(trimmed.isEmpty || isSubmitting)
                }
            }
        }
    }
}
