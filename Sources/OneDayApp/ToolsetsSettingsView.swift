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
    @State private var store = ToolsetsStore()
    @State private var selectedName: String?

    var body: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
        .navigationTitle("工具")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load(appState: appState)
        }
        .refreshable {
            await store.load(appState: appState)
        }
        .navigationDestination(item: $selectedName) { name in
            ToolsetDetailView(store: store, name: name)
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
        }
        switch store.state {
        case .idle, .loading:
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取工具集…")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        case .unavailable(let message), .failed(let message):
            Section {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                Button("重试") {
                    Task { await store.load(appState: appState) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .ready:
            readyContent
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        if let list = store.list {
            Section {
                if list.data.isEmpty {
                    Text("服务器没报回任何工具集。下拉刷新再试；一直这样说明服务端清单为空。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(list.data) { row in
                    toolsetRow(row)
                }
            } header: {
                Text("手机会话工具集")
            } footer: {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingXS
                ) {
                    Text("开关对新会话生效：改完后新开的会话按新清单干活，正在进行的会话不受影响。")
                    if store.configUnread {
                        Text("服务器配置这次没读全，个别工具集（如语音转写）的开关状态可能还没确认准，下拉刷新再试。")
                    }
                }
            }
        }
        backendsSection
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
                        .font(.body)
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
                    Text("服务器没报回终端后端。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(backends.backends) { backend in
                    backendRow(backend)
                }
            } else if store.backendsUnread {
                Text("终端后端这次没读出来，下拉刷新再试。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } header: {
            Text("终端后端")
        } footer: {
            Text("终端工具实际在哪台机器上跑命令。只有状态为「就绪」的后端能选；切换对全局生效（所有平台的会话都跟着换）。")
        }
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
                        .font(.body)
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
            }
            detailSections
        }
        .listStyle(.insetGrouped)
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
                    .font(.subheadline)
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
            Text("基本")
        } footer: {
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingXS
            ) {
                Text("开关对新会话生效，正在进行的会话不受影响。")
                if configBacked {
                    Text("这个工具集的开关状态以服务器配置为准（服务端按配置节计），页面显示的是配置里的真值。")
                }
                if !row.configured {
                    Text("这个工具集还没配置齐：开关打开也可能用不了，先在下面看服务商与密钥状态。")
                }
            }
        }
    }

    @ViewBuilder
    private var detailSections: some View {
        if store.detail.loading {
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取细调项…")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
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
                Text("服务商")
            } footer: {
                Text("服务商写的是服务器全局配置，所有平台的会话都跟着换。")
            }
        } else if store.detail.panelFailed {
            Section {
                Text("服务商清单这次没读出来，退出重进再试。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            } header: {
                Text("服务商")
            }
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
                            .font(.body)
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
                Text("后端模型")
            } footer: {
                Text("模型写的是服务器全局配置，所有平台的会话都跟着换。")
            }
        } else if store.detail.catalogFailed {
            Section {
                Text("模型目录这次没读出来，退出重进再试。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            } header: {
                Text("后端模型")
            }
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
                        .font(.body)
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
                    Text("密钥状态")
                } footer: {
                    Text("这里只看密钥配没配，不在这里录入。需要配置时，在服务器上把密钥写进 Hermes 的环境配置（.env）后，回到这里刷新即可。")
                }
            }
        }
    }
}
