import OneDayCore
import OneDayDesign
import SwiftUI

/// 工具集治理面（DESIGN §358；台账 34）：设置·智能体组
/// 「工具集」页——手机会话（api_server 平台）能用的工具
/// 集清单＋启停＋细调（provider/model）＋终端后端。
/// 诚实口径（僵尸禁令）：
/// - 清单真源是网关 /v1/toolsets（手机面真值），不是
///   9119 的 cli 配置视图；开关写 34-S 端点、写后回读
///   确认才算生效，文案写明「对新会话生效」；
/// - config-only 集（语音转写 stt）的开关真值在服务
///   器配置里，页面按合成有效态呈现并注明来源；
/// - 密钥只显「已配置/未配置」状态，不在这里录入。

struct ToolsetsSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = ToolsetsStore()
    @State private var selectedName: String?
    @State private var configuringBackend: TerminalBackend?
    @State private var toolSearchEnabled = true
    @State private var toolSearchLazyThreshold = 25
    @State private var pinCoreTools = true

    var body: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("工具")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load(appState: appState)
            await loadToolSearchConfig()
        }
        .refreshable {
            await store.load(appState: appState)
        }
        .navigationDestination(item: $selectedName) { name in
            ToolsetDetailView(store: store, name: name)
        }
        .sheet(item: $configuringBackend) { backend in
            TerminalBackendConfigSheet(backend: backend)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let note = store.note {
            Section {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(
                        store.noteIsProblem
                            ? Palette.danger : Palette.inkSecondary
                    )
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        switch store.state {
        case .idle, .loading:
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取工具集…")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        case .unavailable(let message), .failed(let message):
            Section {
                Text(message)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                Button("重试") {
                    Task { await store.load(appState: appState) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        case .ready:
            readyContent
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        SettingsHeroCard(
            symbol: "wrench.and.screwdriver.fill",
            tint: Palette.tintOrangeInk,
            title: "工具集与终端后端",
            subtitle: "管理手机会话可用的工具集开关，并切换或配置 Local / Docker / SSH / 云沙箱终端执行后端。",
            statusText: store.backends?.active.map { "后端：\($0)" } ?? "已同步",
            statusTone: .healthy
        )
        if let list = store.list {
            Section {
                if list.data.isEmpty {
                    Text("暂未获取到工具集，请下拉刷新重试。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(list.data) { row in
                    toolsetRow(row)
                }
            } header: {
                SettingsSectionHeader("会话工具集")
            } footer: {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingXS
                ) {
                    Text("修改后对新会话生效，当前会话不受影响。")
                    if store.configUnread {
                        Text("部分服务器配置未读取完整，下拉刷新可重新同步。")
                    }
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        toolSearchSection
        backendsSection
    }

    private var toolSearchSection: some View {
        Section {
            Toggle(isOn: $toolSearchEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("按需工具发现（Tool Search）")
                        .font(.rowTitleL)
                    Text("工具较多时按语义动态检索加载，减少上下文 Token 占用")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .onChange(of: toolSearchEnabled) { _, val in
                Task { await saveToolSearchConfig(key: "enabled", value: .bool(val)) }
            }

            if toolSearchEnabled {
                Picker("懒加载触发阈值", selection: $toolSearchLazyThreshold) {
                    Text("超过 15 个工具").tag(15)
                    Text("超过 25 个工具").tag(25)
                    Text("超过 40 个工具").tag(40)
                    Text("超过 60 个工具").tag(60)
                }
                .onChange(of: toolSearchLazyThreshold) { _, val in
                    Task { await saveToolSearchConfig(key: "lazy_threshold", value: .number(Double(val))) }
                }

                Toggle(isOn: $pinCoreTools) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("常驻核心工具集")
                            .font(.rowTitleL)
                        Text("保留文件/终端/记忆工具常驻，其余 MCP 工具按需懒加载")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .onChange(of: pinCoreTools) { _, val in
                    Task { await saveToolSearchConfig(key: "pin_core_tools", value: .bool(val)) }
                }
            }
        } header: {
            SettingsSectionHeader("动态工具搜索与懒加载")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    private func loadToolSearchConfig() async {
        guard appState.config != nil else { return }
        if let raw = try? await appState.readDashboardConfig(),
           let ts = raw["tools"]?.objectValue?["tool_search"]?.objectValue {
            if let e = ts["enabled"]?.boolValue { toolSearchEnabled = e }
            if let t = ts["lazy_threshold"]?.intValue { toolSearchLazyThreshold = t }
            if let p = ts["pin_core_tools"]?.boolValue { pinCoreTools = p }
        }
    }

    private func saveToolSearchConfig(key: String, value: JSONValue) async {
        guard appState.config != nil else { return }
        try? await appState.applyDashboardConfig(["tools": .object(["tool_search": .object([key: value])])])
    }

    private func toolsetRow(_ row: ToolsetRow) -> some View {
        let effective = ToolsetStateResolution.effectiveEnabled(
            row, configEnabled: store.configEnabled
        )
        let configBacked = ToolsetStateResolution.isConfigBacked(
            row, configEnabled: store.configEnabled
        )
        return HStack(spacing: OneDayMetrics.spacingSM) {
            Button {
                selectedName = row.name
            } label: {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingMicro
                ) {
                    Text(row.displayLabel)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    if !row.description.isEmpty,
                       ServerLabels.isChineseText(row.description) {
                        Text(row.description)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                    HStack(
                        spacing: OneDayMetrics.spacingXS
                    ) {
                        if !row.configured {
                            Text("未配置")
                                .font(.caption)
                                .foregroundStyle(Palette.warningText)
                        }
                        if configBacked {
                            Text("开关以服务器配置为准")
                                .font(.caption)
                                .foregroundStyle(Palette.inkMuted)
                        }
                        Text("\(row.tools.count) 个工具")
                            .font(.caption)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: OneDayMetrics.spacingS)
            Toggle(
                "",
                isOn: Binding(
                    get: { effective },
                    set: { newValue in
                        Task {
                            await store.toggle(
                                row, to: newValue,
                                appState: appState
                            )
                        }
                    }
                )
            )
            .labelsHidden()
            .disabled(store.togglingNames.contains(row.name))
            .accessibilityLabel(
                "\(row.displayLabel)，\(effective ? "已启用" : "已停用")"
            )
        }
    }

    // MARK: 终端后端（列表页尾独立段，§358 施工口径）

    @ViewBuilder
    private var backendsSection: some View {
        Section {
            if let backends = store.backends {
                if backends.backends.isEmpty {
                    Text("暂无可用终端后端。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(backends.backends) { backend in
                    backendRow(backend)
                }
            } else if store.backendsUnread {
                Text("终端后端读取失败，请下拉刷新重试。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } header: {
            SettingsSectionHeader("终端后端")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    private func backendRow(_ backend: TerminalBackend) -> some View {
        let isActive = store.backends?.active == backend.name
            || backend.active
        return Button {
            if !isActive {
                Task {
                    await store.selectBackend(
                        backend, appState: appState
                    )
                }
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingMicro
                ) {
                    Text(backend.displayLabel)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(backendStatusText(backend))
                        .font(.caption)
                        .foregroundStyle(
                            backend.status == .ready
                                ? Palette.inkSecondary
                                : Palette.warningText
                        )
                    if !backend.detail.isEmpty {
                        Text(backend.detail)
                            .font(.caption)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                if store.selectingBackend {
                    ProgressView()
                } else {
                    HStack(spacing: 10) {
                        if isActive {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.primary)
                                .accessibilityHidden(true)
                        }
                        Button {
                            Haptics.selection()
                            configuringBackend = backend
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Palette.inkSecondary)
                                .frame(width: 30, height: 30)
                                .background(Palette.fillTertiary, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("配置 \(backend.displayLabel) 参数")
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.selectingBackend)
        .accessibilityLabel(
            "\(backend.displayLabel)，\(backendStatusText(backend))\(isActive ? "，当前使用" : "")"
        )
    }

    private func backendStatusText(
        _ backend: TerminalBackend
    ) -> String {
        switch backend.status {
        case .ready: return "就绪"
        case .needsSetup: return "还没配置好"
        case .unavailable: return "不可用"
        case .other(let raw): return raw.isEmpty ? "状态未知" : raw
        }
    }
}

// MARK: - 详情（细调）

/// 工具集详情：基本（说明/开关/工具清单）＋服务商＋
/// 模型＋密钥状态四段。细调写口（provider/model）走
/// 9119 会话面、写全局 config——页脚如实标注全平台
/// 生效；密钥只显状态、不做录入入口（一期口径）
struct ToolsetDetailView: View {
    let store: ToolsetsStore
    let name: String
    @Environment(AppState.self) private var appState

    private var row: ToolsetRow? {
        store.list?.row(named: name)
    }

    var body: some View {
        List {
            if let row {
                basicSection(row)
            }
            if let note = store.detailNote {
                Section {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(
                            store.detailNoteIsProblem
                                ? Palette.danger
                                : Palette.inkSecondary
                        )
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
            detailSections
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle(row?.displayLabel ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadDetail(name: name, appState: appState)
        }
    }

    private func basicSection(_ row: ToolsetRow) -> some View {
        let effective = ToolsetStateResolution.effectiveEnabled(
            row, configEnabled: store.configEnabled
        )
        let configBacked = ToolsetStateResolution.isConfigBacked(
            row, configEnabled: store.configEnabled
        )
        return Section {
            if !row.description.isEmpty {
                Text(row.description)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Toggle(
                "启用",
                isOn: Binding(
                    get: { effective },
                    set: { newValue in
                        Task {
                            await store.toggle(
                                row, to: newValue,
                                appState: appState
                            )
                        }
                    }
                )
            )
            .disabled(store.togglingNames.contains(row.name))
            if !row.tools.isEmpty {
                DisclosureGroup(
                    "包含的工具（\(row.tools.count)）"
                ) {
                    ForEach(row.tools, id: \.self) { tool in
                        Text(tool)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
        } header: {
            SettingsSectionHeader("基本")
        } footer: {
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingXS
            ) {
                Text("修改后对新会话生效，当前会话不受影响。")
                if configBacked {
                    Text("此开关状态由服务器配置决定。")
                }
                if !row.configured {
                    Text("当前尚未完成配置，请在下方检查服务商与密钥状态。")
                }
            }
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    @ViewBuilder
    private var detailSections: some View {
        if store.detail.loading {
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取配置…")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        } else {
            providerSection
            modelSection
            envSection
        }
    }

    @ViewBuilder
    private var providerSection: some View {
        if let panel = store.detail.panel,
           !panel.providers.isEmpty {
            Section {
                ForEach(panel.providers) { provider in
                    providerRow(provider, panel: panel)
                }
            } header: {
                SettingsSectionHeader("服务商")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        } else if store.detail.panelFailed {
            Section {
                Text("服务商清单读取失败，请返回重试。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            } header: {
                SettingsSectionHeader("服务商")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
    }

    private func providerRow(
        _ provider: ToolsetProvider, panel: ToolsetConfigPanel
    ) -> some View {
        let isActive = panel.activeProvider == provider.name
            || provider.isActive
        return Button {
            if !isActive {
                Task {
                    await store.selectProvider(
                        provider, appState: appState
                    )
                }
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingMicro
                ) {
                    HStack(
                        spacing: OneDayMetrics.spacingXS
                    ) {
                        Text(provider.name)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        if !provider.badge.isEmpty {
                            Text(provider.badge)
                                .font(.caption)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    if !provider.tag.isEmpty {
                        Text(provider.tag)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                    if provider.requiresNousAuth {
                        Text("需要 Nous 账号授权")
                            .font(.caption)
                            .foregroundStyle(Palette.warningText)
                    }
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                if store.detailBusy {
                    ProgressView()
                } else if isActive {
                    Image(systemName: "checkmark")
                        .font(
                            .system(
                                size: FrameworkIcon.smallGlyphSize,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(Palette.primary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.detailBusy)
        .accessibilityLabel(
            "\(provider.name)\(isActive ? "，当前使用" : "")"
        )
    }

    @ViewBuilder
    private var modelSection: some View {
        if let catalog = store.detail.catalog,
           catalog.hasModels, !catalog.models.isEmpty {
            Section {
                ForEach(catalog.models) { model in
                    modelRow(model, catalog: catalog)
                }
            } header: {
                SettingsSectionHeader("后端模型")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        } else if store.detail.catalogFailed {
            Section {
                Text("模型目录读取失败，请返回重试。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            } header: {
                SettingsSectionHeader("后端模型")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
    }

    private func modelRow(
        _ model: ToolsetModelOption,
        catalog: ToolsetModelCatalog
    ) -> some View {
        let isCurrent = catalog.current == model.id
        return Button {
            if !isCurrent {
                Task {
                    await store.selectModel(
                        model, appState: appState
                    )
                }
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingMicro
                ) {
                    Text(model.displayName)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    HStack(
                        spacing: OneDayMetrics.spacingXS
                    ) {
                        if catalog.defaultModel == model.id {
                            Text("默认")
                                .font(.caption)
                                .foregroundStyle(Palette.inkMuted)
                        }
                        if !model.speed.isEmpty {
                            Text(model.speed)
                                .font(.caption)
                                .foregroundStyle(Palette.inkMuted)
                        }
                        if !model.price.isEmpty {
                            Text(model.price)
                                .font(.caption)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    if !model.strengths.isEmpty {
                        Text(model.strengths)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                if store.detailBusy {
                    ProgressView()
                } else if isCurrent {
                    Image(systemName: "checkmark")
                        .font(
                            .system(
                                size: FrameworkIcon.smallGlyphSize,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(Palette.primary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.detailBusy)
        .accessibilityLabel(
            "\(model.displayName)\(isCurrent ? "，当前使用" : "")"
        )
    }

    /// 密钥状态段：汇总当前（或全部）provider 的 env
    /// 状态行——只显已配置/未配置，不做录入入口
    @ViewBuilder
    private var envSection: some View {
        if let panel = store.detail.panel {
            // 同一密钥可能被多个 provider 声明，按键去重
            // （先出现者为准）避免重复行
            var seen = Set<String>()
            let envVars = panel.providers
                .flatMap(\.envVars)
                .filter { seen.insert($0.key).inserted }
            if !envVars.isEmpty {
                Section {
                    ForEach(envVars, id: \.key) { envVar in
                        HStack(
                            spacing: OneDayMetrics.spacingSM
                        ) {
                            VStack(
                                alignment: .leading,
                                spacing: OneDayMetrics
                                    .spacingMicro
                            ) {
                                Text(envVar.key)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.ink)
                                if !envVar.prompt.isEmpty {
                                    Text(envVar.prompt)
                                        .font(.caption)
                                        .foregroundStyle(
                                            Palette.inkMuted
                                        )
                                        .lineLimit(1)
                                }
                            }
                            Spacer(
                                minLength: OneDayMetrics.spacingS
                            )
                            Text(envVar.isSet ? "已配置" : "未配置")
                                .font(.caption)
                                .foregroundStyle(
                                    envVar.isSet
                                        ? Palette.inkSecondary
                                        : Palette.warningText
                                )
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(envVar.key)，\(envVar.isSet ? "已配置" : "未配置")"
                        )
                    }
                } header: {
                    SettingsSectionHeader("密钥状态")
                } footer: {
                    Text("仅展示配置状态；如需修改请在服务端环境变量配置后刷新。")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
        }
    }
}
