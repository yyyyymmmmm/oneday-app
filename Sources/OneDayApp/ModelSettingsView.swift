import OneDayDesign
import OneDayCore
import SwiftUI

/// 模型设置（§119 简化定版，用户 2026-11-11 亲定）：
/// 只留两块——①服务商管理：填接口＋密钥→获取模型
/// →选择，一家一卡，模型清单回归卡内；网关不再单
/// 设一层，它就是「默认服务商」这张卡本体，渠道降
/// 为卡内来源标记＋详情查看。②辅助模型：独立页给
/// 各用途分配（AuxModelsView）。旧「组合」降为轻量
/// 预设（快照切换，存储零迁移）。管道沿 0.37.0：密
/// 钥经 /api/env 保存、配置只存引用，写回先读全量、
/// 只改点名键。文案口径：服务商（D3-16）、辅助模型
/// （D3-01），不用旧词。
struct ModelSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var store = ModelManagementStore()
    @State private var pendingModel: String?
    @State private var showProviderEditor = false
    @State private var editingProvider: ProviderRegistry.Entry?
    @State private var pendingDeleteProvider: ProviderRegistry.Entry?
    @State private var editingPreset: ModelCombo?
    @State private var showNewPreset = false
    @State private var pendingActivatePreset: ModelCombo?
    @State private var pendingDeletePreset: ModelCombo?
    @State private var pendingRefresh: PendingRefresh?

    // 卡面本地态：展开的卡、测连接结果、进行中标记
    @State private var expandedCards: Set<String> = []
    @State private var channelsExpanded = false
    @State private var testResults: [String: ProviderConnectionOutcome] = [:]
    @State private var busyCards: Set<String> = []

    private struct PendingRefresh: Identifiable {
        var entry: ProviderRegistry.Entry
        var diff: ModelListDiff
        var models: [String]
        var id: String { entry.name }
    }

    private static let mainCardID = "默认服务商"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                providersGroup
                auxGroup
                presetsGroup
                if let errorMessage = store.errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingL)
                }
                if let notice = store.notice {
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
        .navigationTitle("模型与服务商")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load(appState: appState) }
        .task { await store.load(appState: appState) }
        .sheet(isPresented: $showProviderEditor) {
            ProviderEditorView(store: store) { added in
                if added { Task { await store.load(appState: appState) } }
            }
        }
        .sheet(item: $editingProvider) { entry in
            ProviderEditorView(store: store, editing: entry) { saved in
                if saved { Task { await store.load(appState: appState) } }
            }
        }
        .sheet(item: $editingPreset) { combo in
            PresetEditorView(store: store, combo: combo) {
                Task { await store.load(appState: appState) }
            }
        }
        .sheet(isPresented: $showNewPreset) {
            PresetEditorView(store: store, combo: nil) {
                Task { await store.load(appState: appState) }
            }
        }
        .confirmationDialog(
            "切换默认模型？",
            isPresented: Binding(
                get: { pendingModel != nil },
                set: { if !$0 { pendingModel = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("切换到 \(pendingModel ?? "")") {
                if let model = pendingModel {
                    Task { await store.setDefaultModel(model, appState: appState) }
                }
                pendingModel = nil
            }
            Button("取消", role: .cancel) { pendingModel = nil }
        } message: {
            Text("新的会话将默认使用该模型；已有会话不受影响。")
        }
        .confirmationDialog(
            "删除服务商？",
            isPresented: Binding(
                get: { pendingDeleteProvider != nil },
                set: { if !$0 { pendingDeleteProvider = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let entry = pendingDeleteProvider {
                    Task { await store.deleteProvider(entry, appState: appState) }
                }
                pendingDeleteProvider = nil
            }
            Button("取消", role: .cancel) { pendingDeleteProvider = nil }
        } message: {
            Text("将从服务端配置里移除这家服务商，它的密钥也会一并删掉；如果有辅助模型或预设还指着它，会先拦下来告诉你。")
        }
        .confirmationDialog(
            "更新模型清单？",
            isPresented: Binding(
                get: { pendingRefresh != nil },
                set: { if !$0 { pendingRefresh = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("更新") {
                if let pending = pendingRefresh {
                    Task {
                        await store.applyRefreshedModels(
                            entry: pending.entry, models: pending.models,
                            appState: appState
                        )
                    }
                }
                pendingRefresh = nil
            }
            Button("取消", role: .cancel) { pendingRefresh = nil }
        } message: {
            if let pending = pendingRefresh {
                Text(refreshDialogMessage(pending))
            }
        }
        .confirmationDialog(
            "启用这份预设？",
            isPresented: Binding(
                get: { pendingActivatePreset != nil },
                set: { if !$0 { pendingActivatePreset = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("启用「\(pendingActivatePreset?.name ?? "")」") {
                if let combo = pendingActivatePreset {
                    Task { await store.activateCombo(combo, appState: appState) }
                }
                pendingActivatePreset = nil
            }
            Button("取消", role: .cancel) { pendingActivatePreset = nil }
        } message: {
            if let combo = pendingActivatePreset {
                Text(ComboActivation.activationNotice(for: combo))
            }
        }
        .confirmationDialog(
            "删除预设？",
            isPresented: Binding(
                get: { pendingDeletePreset != nil },
                set: { if !$0 { pendingDeletePreset = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let combo = pendingDeletePreset {
                    Task { await store.deleteCombo(combo, appState: appState) }
                }
                pendingDeletePreset = nil
            }
            Button("取消", role: .cancel) { pendingDeletePreset = nil }
        } message: {
            Text("只删这份预设的定义；已经启用到服务端的设置不会被撤回。")
        }
    }

    private func refreshDialogMessage(_ pending: PendingRefresh) -> String {
        var parts: [String] = []
        if !pending.diff.removed.isEmpty {
            parts.append(L10n.format(
                "将删 %lld 个：%@",
                pending.diff.removed.count,
                pending.diff.removed.joined(separator: "、")
            ))
        }
        if !pending.diff.added.isEmpty {
            parts.append(L10n.format(
                "新增 %lld 个：%@",
                pending.diff.added.count,
                pending.diff.added.joined(separator: "、")
            ))
        }
        parts.append(L10n.string("确认后才保存；上一份清单会留着，可以恢复。"))
        return parts.joined(separator: "\n")
    }

    // MARK: - 服务商管理（卡面）

    private var providersGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("服务商")
                .padding(.bottom, OneDayMetrics.spacingS)
            Text("填接口和密钥，获取模型，再选用。密钥只保存在你的服务端，App 不留存。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: OneDayMetrics.spacingM) {
                mainCard
                ForEach(store.providers, id: \.name) { entry in
                    providerCard(entry)
                }
                addProviderButton
            }
        }
    }

    private var addProviderButton: some View {
        Button {
            showProviderEditor = true
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Palette.primary)
                Text("添加服务商")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .odGroup()
    }

    /// 默认服务商卡：服务器的主通道（经网关）本体——
    /// 默认模型住在这里；地址与密钥在服务器上配置，
    /// 本卡只呈现状、清单与渠道来源
    private var mainCard: some View {
        let expanded = expandedCards.contains(Self.mainCardID)
        return VStack(spacing: 0) {
            cardHeader(
                title: "默认服务商",
                subtitle: "服务器的主通道，经网关转发",
                badge: "默认"
            )
            GroupDivider()
            infoRow("默认模型", store.currentModel ?? "未配置")
            infoRow("接口地址", "在服务器上配置，App 里只看不改")
            infoRow("密钥", "在服务器上保管")
            GroupDivider()
            expandRow(
                title: L10n.format("模型（%lld）", appState.availableModels.count),
                expanded: expanded
            ) {
                toggleCard(Self.mainCardID)
            }
            if expanded {
                ForEach(appState.availableModels, id: \.self) { model in
                    GroupDivider()
                    gatewayModelRow(model)
                }
            }
            GroupDivider()
            cardActions {
                actionButton("获取模型", busy: busyCards.contains(Self.mainCardID)) {
                    await refreshMainCard()
                }
                actionButton("测连接", busy: busyCards.contains(Self.mainCardID)) {
                    testResults[Self.mainCardID] = await store.testMainEndpoint(
                        appState: appState
                    )
                }
                actionButton(
                    channelsExpanded ? "收起渠道" : "查看渠道", busy: false
                ) {
                    channelsExpanded.toggle()
                }
            }
            if let outcome = testResults[Self.mainCardID] {
                outcomeLine(outcome)
            }
            if channelsExpanded {
                GroupDivider()
                channelsList
            }
        }
        .odGroup()
    }

    private func gatewayModelRow(_ model: String) -> some View {
        let isCurrent = model == store.currentModel
        let channels = channelNames(for: model)
        let content = HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(model)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let runtime = ModelCatalog.aliasRuntime[model] {
                    Text("别名 · 将按 \(runtime) 运行")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if !channels.isEmpty {
                Text(channels.joined(separator: "、"))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            if isCurrent {
                Text("当前默认")
                    .font(.footnote)
                    .foregroundStyle(Palette.success)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())

        if isCurrent {
            return AnyView(content)
        }
        return AnyView(
            Button { pendingModel = model } label: { content }
                .buttonStyle(.odPressable)
        )
    }

    /// 模型 → 渠道来源标记（渠道读面里声明了该模型
    /// 的渠道名；读面没就绪时不标，不编造）
    private func channelNames(for model: String) -> [String] {
        guard case .ready(let channels) = store.channelsFace
        else { return [] }
        return channels
            .filter { $0.models.contains(model) }
            .map { $0.name }
    }

    private var channelsList: some View {
        VStack(spacing: 0) {
            if case .ready(let channels) = store.channelsFace,
               !channels.isEmpty {
                ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                    if index > 0 {
                        GroupDivider()
                    }
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text(channel.name)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            Text(channel.detailLine)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: OneDayMetrics.spacingS)
                        Text(channel.statusWording)
                            .font(.footnote)
                            .foregroundStyle(
                                channel.statusWording == "使用中"
                                    ? Palette.success : Palette.inkSecondary
                            )
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
                Text("渠道的启停与顺序在网关那边管理，App 不碰网关的管理员凭据。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let placeholder = store.channelsFace.placeholderText {
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func providerCard(_ entry: ProviderRegistry.Entry) -> some View {
        let expanded = expandedCards.contains(entry.name)
        return VStack(spacing: 0) {
            cardHeader(
                title: entry.name,
                subtitle: entry.baseURL ?? "",
                badge: nil
            )
            GroupDivider()
            infoRow(
                "密钥",
                (entry.keyEnv?.isEmpty == false) ? "已保存" : "未保存"
            )
            GroupDivider()
            expandRow(
                title: L10n.format("模型（%lld）", entry.models.count),
                expanded: expanded
            ) {
                toggleCard(entry.name)
            }
            if expanded {
                if entry.models.isEmpty {
                    GroupDivider()
                    Text("还没有模型清单。点「获取模型」拉一次，或在编辑里手动填。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(entry.models, id: \.self) { model in
                    GroupDivider()
                    HStack {
                        Text(model)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
            }
            GroupDivider()
            cardActions {
                actionButton("获取模型", busy: busyCards.contains(entry.name)) {
                    await refreshProviderCard(entry)
                }
                actionButton("测连接", busy: busyCards.contains(entry.name)) {
                    testResults[entry.name] = await store.testConnection(
                        entry: entry, appState: appState
                    )
                }
                actionButton("编辑", busy: false) {
                    editingProvider = entry
                }
                actionButton("删除", busy: false, destructive: true) {
                    pendingDeleteProvider = entry
                }
            }
            if let outcome = testResults[entry.name] {
                outcomeLine(outcome)
            }
            if store.previousModels(for: entry) != nil {
                GroupDivider()
                Button {
                    Task {
                        await store.restorePreviousModels(
                            entry: entry, appState: appState
                        )
                    }
                } label: {
                    HStack {
                        Text("恢复上一份模型清单")
                            .font(.callout)
                            .foregroundStyle(Palette.primary)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
            }
        }
        .odGroup()
    }

    // MARK: - 卡面部件

    private func cardHeader(
        title: String, subtitle: String, badge: String?
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(
                            .caption,
                            design: subtitle.hasPrefix("http")
                                ? .monospaced : .default
                        ))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if let badge {
                Text(badge)
                    .font(.footnote)
                    .foregroundStyle(Palette.success)
            }
            if store.isLoading {
                ProgressView()
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func expandRow(
        title: String, expanded: Bool, toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func cardActions(
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingL) {
            content()
            Spacer()
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func actionButton(
        _ title: String, busy: Bool, destructive: Bool = false,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: OneDayMetrics.spacingMicro) {
                if busy {
                    ProgressView()
                }
                Text(title)
                    .font(.callout)
                    .foregroundStyle(
                        destructive ? Palette.danger : Palette.primary
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .disabled(busy)
    }

    private func outcomeLine(_ outcome: ProviderConnectionOutcome) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            GroupDivider()
            Text(outcome.headline())
                .font(.footnote)
                .foregroundStyle(Palette.ink)
            if let advice = outcome.advice() {
                Text(advice)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleCard(_ id: String) {
        if expandedCards.contains(id) {
            expandedCards.remove(id)
        } else {
            expandedCards.insert(id)
        }
    }

    private func refreshMainCard() async {
        busyCards.insert(Self.mainCardID)
        defer { busyCards.remove(Self.mainCardID) }
        await appState.refreshModelCatalog()
        testResults[Self.mainCardID] = appState.availableModels.isEmpty
            ? .failed(message: L10n.string("没能读到网关的模型清单，检查网络与登录状态后再试。"))
            : .connected(modelCount: appState.availableModels.count)
    }

    /// 获取模型（具名卡）：先拉新清单算差异——没变
    /// 直接报，没变差才弹确认，不许默默覆盖
    private func refreshProviderCard(_ entry: ProviderRegistry.Entry) async {
        busyCards.insert(entry.name)
        defer { busyCards.remove(entry.name) }
        let result = await store.fetchRefreshedModels(
            entry: entry, appState: appState
        )
        guard let models = result.models else {
            testResults[entry.name] = result.outcome
            return
        }
        let diff = ModelListDiff.between(old: entry.models, new: models)
        if diff.isUnchanged {
            testResults[entry.name] = .connected(modelCount: models.count)
            store.notice = L10n.format("「%@」的模型清单没有变化。", entry.name)
        } else {
            pendingRefresh = PendingRefresh(
                entry: entry, diff: diff, models: models
            )
        }
    }

    // MARK: - 辅助模型入口

    private var auxGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("辅助模型")
                .padding(.top, OneDayMetrics.spacingL)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                NavigationLink {
                    AuxModelsView(store: store)
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text("给各用途分配模型")
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            Text(auxSummaryLine)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: OneDayMetrics.spacingS)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
            }
            .odGroup()
        }
    }

    private var auxSummaryLine: String {
        let specified = store.auxAssignments.values
            .filter { !$0.isFollow }.count
        return specified == 0
            ? L10n.string("全部用途都跟随主模型")
            : L10n.format("已给 %lld 个用途单独指定", specified)
    }

    // MARK: - 预设

    private var presetsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("预设")
                .padding(.top, OneDayMetrics.spacingL)
                .padding(.bottom, OneDayMetrics.spacingS)
            Text("把默认模型和整套辅助分配存成一份快照，整套切换。预设不是多模型汇总——那是几个模型一起答一道题。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if store.combosFaceMissing {
                    Text("预设的服务端存储还没开通，这里先留位。开通前，服务商与默认模型照常可用。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if store.combosLoadFailed {
                    Text("预设清单读取失败，请下拉重试。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let presets = store.comboDocument?.combos ?? []
                    if presets.isEmpty {
                        Text("还没有预设。可以新建一份，或先把当前设置存为第一份再改。")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.horizontal, OneDayMetrics.spacingM)
                            .padding(.vertical, OneDayMetrics.spacingSM)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        GroupDivider()
                        starterButton
                        GroupDivider()
                        newPresetButton
                    } else {
                        ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                            if index > 0 {
                                GroupDivider()
                            }
                            presetRow(preset)
                        }
                        GroupDivider()
                        newPresetButton
                    }
                }
            }
            .odGroup()
        }
    }

    private var starterButton: some View {
        Button {
            Task { await store.saveCurrentAsPreset(appState: appState) }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(Palette.primary)
                Text("把当前设置存为预设")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private var newPresetButton: some View {
        Button {
            showNewPreset = true
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Palette.primary)
                Text("新建预设")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func presetRow(_ preset: ModelCombo) -> some View {
        let isActive = store.comboDocument?.activeComboID == preset.id
        return HStack(spacing: OneDayMetrics.spacingSM) {
            Button {
                editingPreset = preset
            } label: {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text(preset.name)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        if isActive {
                            Text("使用中")
                                .font(.footnote)
                                .foregroundStyle(Palette.success)
                        }
                    }
                    Text(preset.summaryLine)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            if !isActive {
                Button("启用") {
                    pendingActivatePreset = preset
                }
                .font(.callout)
            }
            Button {
                pendingDeletePreset = preset
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Palette.danger)
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel(
                L10n.string("删除预设") + "：" + preset.name
            )
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }
}
