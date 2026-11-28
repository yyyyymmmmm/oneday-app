import OneDayDesign
import OneDayCore
import SwiftUI

/// 记忆页（P1-2 重构：原生 iOS 26 List(.insetGrouped) + SettingsHeroCard + 原生四层记忆/提供方/重置分组）
struct MemoryView: View {
    @Environment(AppState.self) private var appState

    @State private var status: MemoryStatus?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var resetTarget: String?
    @State private var notice: String?
    @State private var memoriesStore = MemoriesStore()
    @State private var learningStore = LearningGraphStore()
    @State private var showMemoryEditorSheet = false
    @State private var showMemoryRewindSheet = false

    var body: some View {
        List {
            if let status {
                let activeName = (status.active ?? "").isEmpty ? "内置记忆" : (status.active ?? "内置记忆")
                let totalFiles = status.builtinFiles.values.reduce(0, +)
                SettingsHeroCard(
                    symbol: "memorychip.fill",
                    tint: .purple,
                    title: "记忆系统",
                    subtitle: "管理四层语义记忆、长期档案与外接记忆提供方。",
                    statusText: "\(activeName) · \(AdminFormat.count(totalFiles)) 条",
                    statusTone: .healthy
                )
            } else {
                SettingsHeroCard(
                    symbol: "memorychip.fill",
                    tint: .purple,
                    title: "记忆系统",
                    subtitle: "管理四层语义记忆、长期档案与外接记忆提供方。"
                )
            }

            LayeredMemorySection()

            Section {
                MemoryEntriesSection(store: memoriesStore)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                LearningMemorySection(store: learningStore)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let status {
                providersSection(status)
                builtinSection(status)
                resetSection
            } else if let errorMessage {
                Section {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .foregroundStyle(Palette.primary)
                }
                .listRowBackground(Palette.surface)
            } else {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取记忆状态…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Palette.surface)
            }

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
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load()
            await memoriesStore.load(appState: appState)
            await learningStore.load(appState: appState)
        }
        .task {
            await load()
            await memoriesStore.loadIfNeeded(appState: appState)
            await learningStore.loadIfNeeded(appState: appState)
        }
        .sheet(isPresented: $showMemoryEditorSheet) {
            MemoryMarkdownEditorSheet(appState: appState) {
                notice = "记忆文档与审批策略已保存。"
                Task { await load() }
            }
        }
        .sheet(isPresented: $showMemoryRewindSheet) {
            MemoryRewindSheet(appState: appState) { targetRev in
                notice = "已提交记忆回滚请求：\(targetRev)"
                Task { await load() }
            }
        }
        .confirmationDialog(
            "重置记忆？",
            isPresented: Binding(
                get: { resetTarget != nil },
                set: { if !$0 { resetTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认重置", role: .destructive) {
                if let target = resetTarget {
                    Task { await reset(target) }
                }
                resetTarget = nil
            }
            Button("取消", role: .cancel) { resetTarget = nil }
        } message: {
            Text(resetDescription)
        }
    }

    private var resetDescription: String {
        switch resetTarget {
        case "memory":
            return "将删除内置记忆文件（MEMORY），用户档案文件保留。此操作不可恢复。"
        case "user":
            return "将删除内置用户文件（USER），记忆文件保留。此操作不可恢复。"
        default:
            return "将删除全部内置记忆文件（MEMORY 与 USER）。此操作不可恢复。"
        }
    }

    private func providersSection(_ status: MemoryStatus) -> some View {
        let builtinActive = (status.active ?? "").isEmpty
        return Section {
            HStack(spacing: OneDayMetrics.spacingSM) {
                SettingsRowIcon(symbol: "internaldrive")
                Text("内置记忆")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if builtinActive {
                    SettingsStatusPill(text: "使用中", tone: .healthy)
                }
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)

            ForEach(status.providers) { provider in
                NavigationLink {
                    MemoryProviderConfigView(provider: provider, isActive: isActive(provider, in: status))
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "brain")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            if let desc = provider.description, !desc.isEmpty, ServerLabels.isChineseText(desc) {
                                Text(desc)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if isActive(provider, in: status) {
                            SettingsStatusPill(text: "使用中", tone: .healthy)
                        }
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
            }
        } header: {
            SettingsSectionHeader("记忆提供方")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    private func isActive(
        _ provider: MemoryStatus.MemoryProvider, in status: MemoryStatus
    ) -> Bool {
        status.active == provider.name
    }

    private func builtinSection(_ status: MemoryStatus) -> some View {
        Section {
            SettingsValueRow(
                symbol: "doc.text",
                tint: .indigo,
                title: "MEMORY（长期记忆）",
                value: status.builtinFiles["memory"].map { AdminFormat.count($0) } ?? "—",
                monospaced: true
            )
            SettingsValueRow(
                symbol: "person.text.rectangle",
                tint: .teal,
                title: "USER（用户档案）",
                value: status.builtinFiles["user"].map { AdminFormat.count($0) } ?? "—",
                monospaced: true
            )
            Button {
                showMemoryEditorSheet = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    SettingsRowIcon(symbol: "square.and.pencil", color: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("编辑 MEMORY / USER 与写入审批")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text("分段编辑长期记忆档案、查看并审批 AI 待写入 Diff")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer()
                    DisclosureChevron(font: .footnote.weight(.semibold))
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showMemoryRewindSheet = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    SettingsRowIcon(symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90", color: .purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("记忆版本回滚（memory-rewind）")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text("按历史版本时间轴回滚并管理外部记忆后端")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer()
                    DisclosureChevron(font: .footnote.weight(.semibold))
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            SettingsSectionHeader("内置记忆文件与版本控制")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    private var resetSection: some View {
        Section {
            resetRow(title: "重置全部记忆", target: "all")
            resetRow(title: "只重置 MEMORY", target: "memory")
            resetRow(title: "只重置 USER", target: "user")
        } header: {
            SettingsSectionHeader("危险操作")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    private func resetRow(title: String, target: String) -> some View {
        Button(role: .destructive) {
            resetTarget = target
        } label: {
            HStack {
                Text(title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.danger)
                Spacer()
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            status = try await appState.performAdmin { client, config in
                try await client.memoryStatus(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "记忆状态没读出来，可能是网络或服务暂时没响应"
        }
    }

    private func reset(_ target: String) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.resetMemory(config: config, target: target)
            }
            notice = "已重置。新的记忆会从下一次对话重新积累。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "重置失败，请稍后再试。"
        }
    }
}

/// 记忆提供方配置页：字段表单（GET …/config 的 fields 驱动）＋切换当前提供方
struct MemoryProviderConfigView: View {
    @Environment(AppState.self) private var appState
    let provider: MemoryStatus.MemoryProvider
    let isActive: Bool

    @State private var config: MemoryProviderConfig?
    @State private var values: [String: String] = [:]
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isSwitching = false
    @State private var showSwitchConfirm = false
    @State private var notice: String?

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "brain.head.profile",
                tint: .purple,
                title: provider.name,
                subtitle: "配置外接记忆引擎参数或切换为当前默认提供方。",
                statusText: isActive ? "使用中" : (provider.available == true ? "可用" : "不可用"),
                statusTone: isActive ? .healthy : (provider.available == true ? .neutral : .warning)
            )
            statusGroup
            if let config, !config.fields.isEmpty {
                fieldsGroup(config)
            } else if let errorMessage {
                Section {
                    InlineError(errorMessage)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            } else if config != nil {
                Section {
                    Text("该提供方没有可配置项。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            } else {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取配置…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
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
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(
            "切换记忆提供方？",
            isPresented: $showSwitchConfirm,
            titleVisibility: .visible
        ) {
            Button("切换到 \(provider.name)") {
                Task { await switchProvider() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("切换后新的对话将使用 \(provider.name) 读写长期记忆；已有记忆文件不删除。")
        }
    }

    @ViewBuilder
    private var statusGroup: some View {
        Section {
            KeyValueRow("可用", value: provider.available == true ? "是" : "否")
            KeyValueRow("已配置", value: provider.configured == true ? "是" : "否")
            if let state = provider.status, !state.isEmpty {
                KeyValueRow("状态", value: state)
            }
        } header: {
            SettingsSectionHeader("状态")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
        if !isActive {
            Section {
                Button(isSwitching ? "切换中…" : "切换为当前提供方") {
                    showSwitchConfirm = true
                }
                .buttonStyle(.odPrimary)
                .disabled(isSwitching)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
    }

    @ViewBuilder
    private func fieldsGroup(_ config: MemoryProviderConfig) -> some View {
        Section {
            ForEach(config.fields) { field in
                fieldRow(field)
            }
        } header: {
            SettingsSectionHeader("配置")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
        Section {
            Button(isSaving ? "保存中…" : "保存配置") {
                Task { await save(config) }
            }
            .buttonStyle(.odPrimary)
            .disabled(isSaving)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    private func fieldRow(_ field: MemoryProviderConfig.Field) -> some View {
        FieldRow(label: field.label ?? field.key) {
            Group {
                if field.kind == "secret" || field.kind == "password" {
                    SecureField(
                        field.isSet == true ? "已设置（输入新值替换）" : (field.placeholder ?? ""),
                        text: binding(for: field)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } else {
                    TextField(
                        field.placeholder ?? "",
                        text: binding(for: field)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            }
        }
    }

    private func binding(for field: MemoryProviderConfig.Field) -> Binding<String> {
        Binding(
            get: { values[field.key] ?? field.value?.stringValue ?? "" },
            set: { values[field.key] = $0 }
        )
    }

    private func load() async {
        do {
            let loaded = try await appState.performAdmin { client, config in
                try await client.memoryProviderConfig(config: config, name: provider.name)
            }
            config = loaded
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "配置没读出来，可能是网络或服务暂时没响应"
        }
    }

    private func save(_ config: MemoryProviderConfig) async {
        isSaving = true
        defer { isSaving = false }
        var changed: [String: JSONValue] = [:]
        for field in config.fields {
            if let value = values[field.key],
               value != (field.value?.stringValue ?? "") {
                changed[field.key] = .string(value)
            }
        }
        guard !changed.isEmpty else {
            notice = "没有改动。"
            return
        }
        do {
            try await appState.performAdmin { client, config in
                try await client.updateMemoryProviderConfig(
                    config: config, name: provider.name, values: changed
                )
            }
            values = [:]
            notice = "已保存。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "保存失败，请稍后再试。"
        }
    }

    private func switchProvider() async {
        isSwitching = true
        defer { isSwitching = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.setMemoryProvider(config: config, name: provider.name)
            }
            notice = "已切换。返回上一页可看到新的当前提供方。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "切换失败，请稍后再试。"
        }
    }
}
