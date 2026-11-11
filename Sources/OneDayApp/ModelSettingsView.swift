import OneDayDesign
import OneDayCore
import SwiftUI

/// 模型与服务商（§119 两块骨架＋§150 管理面重构，
/// 报告 hermes-studio-model-picker-20261111.md 的
/// B3/B5/B6；用户 2026-11-11 批准按报告全做）：
/// 本页改系统 List 三段——①「默认」只有一行（模型
/// 的唯一语义＝新对话起点，作用域在段下写全，B3）；
/// ②「服务商」一家一行（名＋计数＋默认徽标，徽标
/// 全页只用「默认」一种说法），点进详情页再展开清
/// 单与动作；③「辅助模型」一行入口，预设降为其下
/// 一行入口（B5）。卡面信息定额：部署说明与「渠道」
/// 行话段撤出用户面（渠道读面 store.channelsFace
/// 本体保留、仅视图段退场，留合并合裁）。设默认点
/// 即生效、不再弹窗（B6）；弹窗只留删除服务商与刷
/// 新清单有移除项两类不可逆事。模型清单呈现走
/// Core ModelListGovernance（搜索＋超 40 折叠）。
/// 管道沿 §119：密钥经 /api/env 保存、配置只存引
/// 用；本包只动设置侧，顶栏选择器与 AppState 模型
/// 取数层不碰（交叉点见 DESIGN §150 记账）。
struct ModelSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var store = ModelManagementStore()
    @State private var showProviderEditor = false
    @State private var editingProvider: ProviderRegistry.Entry?
    @State private var pendingDeleteProvider: ProviderRegistry.Entry?
    @State private var pendingRefresh: PendingRefresh?

    // 详情页本地态：测连接结果、进行中标记、清单搜索
    // （两个详情页共用一词，栈里同时只见一页，可接受）
    @State private var testResults: [String: ProviderConnectionOutcome] = [:]
    @State private var busyCards: Set<String> = []
    @State private var detailQuery = ""

    private struct PendingRefresh: Identifiable {
        var entry: ProviderRegistry.Entry
        var diff: ModelListDiff
        var models: [String]
        var id: String { entry.name }
    }

    private static let mainCardID = "默认服务商"

    /// 作用域成文（B3，Codex 式写全：管什么、不管
    /// 什么、例外是什么；全 App 只此一处口径）
    static let defaultScopeText = "默认模型只管新对话从哪个开始；正在聊的对话不受影响，要换在对话顶部点模型名。在顶栏单独选过的对话，之后也不会跟着默认变。"

    /// 默认是否在默认服务商（网关）名下（回读未到/
    /// 归属不明时回落 §119 旧呈现：默认归主通道）
    private var gatewayOwnsDefault: Bool {
        switch store.defaultAssignment?.owner {
        case .named, .other:
            return false
        case .gateway, .unknown, nil:
            return true
        }
    }

    /// 第一段「默认模型」行右值：服务商名 · 模型名
    private var defaultRowValue: String {
        guard let model = store.defaultAssignment?.model
            ?? store.currentModel else {
            return L10n.string("未配置")
        }
        switch store.defaultAssignment?.owner {
        case .named(let name):
            return "\(name) · \(model)"
        case .other(let slug):
            return "\(slug) · \(model)"
        case .gateway, .unknown, nil:
            return L10n.format("默认服务商 · %@", model)
        }
    }

    var body: some View {
        List {
            defaultSection
            providersSection
            auxSection
            if let errorMessage = store.errorMessage {
                Section {
                    InlineError(errorMessage)
                }
            }
            if let notice = store.notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
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

    // MARK: - 第一段：默认（B3，本页主角）

    private var defaultSection: some View {
        Section {
            NavigationLink {
                DefaultModelPickerView(
                    store: store,
                    gatewayModels: appState.availableModels,
                    providers: store.userProviders,
                    isCurrentDefault: isCurrentDefault,
                    onSelect: { selection in
                        Task { await performSwitch(selection) }
                    }
                )
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Text("默认模型")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Text(defaultRowValue)
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    if store.isLoading {
                        ProgressView()
                    }
                }
            }
        } header: {
            Text("默认")
        } footer: {
            Text(Self.defaultScopeText)
        }
    }

    /// 某家某模型是不是当前默认（默认的唯一判定口，
    /// 选择面/详情清单/徽标共用，不许各算各的）
    private func isCurrentDefault(
        owner: DefaultPickOwner, model: String
    ) -> Bool {
        let currentModel = store.defaultAssignment?.model
            ?? store.currentModel
        guard model == currentModel else { return false }
        switch (owner, store.defaultAssignment?.owner) {
        case (.gateway, .gateway), (.gateway, .unknown), (.gateway, nil):
            return gatewayOwnsDefault
        case (.provider(let name), .named(let current)):
            return name == current
        case (.provider(let name), .other(let slug)):
            return name == slug
        default:
            return false
        }
    }

    /// 设默认即时生效（B6，不再弹窗）：三条来路与
    /// §141 同——主通道旧改名路、经 Gateway 具名条
    /// 目切回、具名家经 /api/model/set 指派
    private func performSwitch(_ selection: DefaultPickSelection) async {
        switch selection {
        case .gateway(let model):
            switch store.defaultAssignment?.owner {
            case .named, .other:
                if store.gatewayEntry != nil {
                    await store.setDefaultViaGateway(
                        model: model, appState: appState
                    )
                } else {
                    store.notice = L10n.string("这台服务器还没登记网关服务商，暂时切不回默认服务商。")
                }
            case .gateway, .unknown, nil:
                await store.setDefaultModel(model, appState: appState)
            }
        case .provider(let entry, let model):
            await store.setDefaultModel(
                provider: entry, model: model, appState: appState
            )
        }
    }

    // MARK: - 第二段：服务商（B5，一家一行）

    private var providersSection: some View {
        Section {
            NavigationLink {
                gatewayDetail
            } label: {
                providerRowLabel(
                    name: L10n.string("默认服务商"),
                    modelCount: appState.availableModels.count,
                    isDefaultOwner: gatewayOwnsDefault
                )
            }
            ForEach(store.userProviders, id: \.name) { entry in
                NavigationLink {
                    providerDetail(entry)
                } label: {
                    providerRowLabel(
                        name: entry.name,
                        modelCount: entry.models.count,
                        isDefaultOwner: store.defaultAssignment?.owner
                            == .named(entry.name)
                    )
                }
            }
            Button {
                showProviderEditor = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Palette.primary)
                    Text("添加服务商")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                }
            }
        } header: {
            Text("服务商")
        } footer: {
            Text("填接口和密钥，获取模型，再选用。密钥只保存在你的服务端，App 不留存。")
        }
    }

    /// 服务商行定额：名＋计数＋默认徽标（只此一种
    /// 说法），地址/密钥状态/清单一律进详情页
    private func providerRowLabel(
        name: String, modelCount: Int, isDefaultOwner: Bool
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(name)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: OneDayMetrics.spacingS)
            if isDefaultOwner {
                Text("默认")
                    .font(.footnote)
                    .foregroundStyle(Palette.success)
            }
            Text(L10n.format("%lld 个模型", modelCount))
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    // MARK: - 第三段：辅助模型＋预设入口（B5，降权）

    private var auxSection: some View {
        Section {
            NavigationLink {
                AuxModelsView(store: store)
            } label: {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text("给各用途分配模型")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Text(auxSummaryLine)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            NavigationLink {
                PresetsView(store: store)
            } label: {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text("预设")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Text("把默认模型和辅助分配存成一份，整套切换。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text("辅助模型")
        }
    }

    private var auxSummaryLine: String {
        let specified = store.auxAssignments.values
            .filter { !$0.isFollow }.count
        return specified == 0
            ? L10n.string("全部用途都跟随主模型")
            : L10n.format("已给 %lld 个用途单独指定", specified)
    }

    // MARK: - 详情页：默认服务商

    private var gatewayDetail: some View {
        List {
            Section {
                detailInfoRow("密钥", "在服务器上保管")
            } header: {
                Text("默认服务商")
            } footer: {
                Text("服务器的主通道，新对话默认从这里开始。")
            }
            Section {
                GovernedModelRows(
                    models: appState.availableModels,
                    query: detailQuery,
                    isDefault: { model in
                        isCurrentDefault(owner: .gateway, model: model)
                    },
                    onSelect: { model in
                        Task {
                            await performSwitch(.gateway(model))
                        }
                    }
                )
            } header: {
                Text(L10n.format("模型（%lld）", appState.availableModels.count))
            } footer: {
                Text("点一行设为默认，立即生效。")
            }
            Section {
                actionRow("获取模型", busy: busyCards.contains(Self.mainCardID)) {
                    await refreshMainCard()
                }
                actionRow("测连接", busy: busyCards.contains(Self.mainCardID)) {
                    testResults[Self.mainCardID] = await store.testMainEndpoint(
                        appState: appState
                    )
                }
                if let outcome = testResults[Self.mainCardID] {
                    outcomeRow(outcome)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $detailQuery, prompt: Text("搜索模型"))
        .navigationTitle("默认服务商")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 详情页：具名服务商

    private func providerDetail(_ entry: ProviderRegistry.Entry) -> some View {
        List {
            Section {
                if let baseURL = entry.baseURL, !baseURL.isEmpty {
                    detailInfoRow("接口地址", baseURL)
                }
                detailInfoRow(
                    "密钥",
                    (entry.keyEnv?.isEmpty == false) ? "已保存" : "未保存"
                )
            } header: {
                Text(entry.name)
            }
            Section {
                if entry.models.isEmpty {
                    Text("还没有模型清单。获取一次，或在编辑里手动填。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    GovernedModelRows(
                        models: entry.models,
                        query: detailQuery,
                        isDefault: { model in
                            isCurrentDefault(
                                owner: .provider(entry.name), model: model
                            )
                        },
                        onSelect: { model in
                            Task {
                                await performSwitch(
                                    .provider(entry, model)
                                )
                            }
                        }
                    )
                }
            } header: {
                Text(L10n.format("模型（%lld）", entry.models.count))
            } footer: {
                Text("点一行设为默认，立即生效。")
            }
            Section {
                actionRow("获取模型", busy: busyCards.contains(entry.name)) {
                    await refreshProviderCard(entry)
                }
                actionRow("测连接", busy: busyCards.contains(entry.name)) {
                    testResults[entry.name] = await store.testConnection(
                        entry: entry, appState: appState
                    )
                }
                actionRow("编辑", busy: false) {
                    editingProvider = entry
                }
                if let outcome = testResults[entry.name] {
                    outcomeRow(outcome)
                }
                if store.previousModels(for: entry) != nil {
                    actionRow("恢复上一份模型清单", busy: false) {
                        await store.restorePreviousModels(
                            entry: entry, appState: appState
                        )
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    pendingDeleteProvider = entry
                } label: {
                    Text("删除服务商")
                        .font(.body)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $detailQuery, prompt: Text("搜索模型"))
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 详情页部件

    private func detailInfoRow(_ label: String, _ value: String) -> some View {
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
    }

    private func actionRow(
        _ title: String, busy: Bool,
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
                    .font(.body)
                    .foregroundStyle(Palette.primary)
            }
        }
        .disabled(busy)
    }

    private func outcomeRow(_ outcome: ProviderConnectionOutcome) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            Text(outcome.headline())
                .font(.footnote)
                .foregroundStyle(Palette.ink)
            if let advice = outcome.advice() {
                Text(advice)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
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

    /// 获取模型（具名家）：先拉新清单算差异——没变
    /// 直接报；有移除项才弹确认（不可逆，B6 保留），
    /// 纯新增直接落（K4 的 diff 呈现打磨不在本包）
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
        } else if diff.removed.isEmpty {
            await store.applyRefreshedModels(
                entry: entry, models: models, appState: appState
            )
        } else {
            pendingRefresh = PendingRefresh(
                entry: entry, diff: diff, models: models
            )
        }
    }
}

/// 默认的归属口（选择面与详情清单共用同一套语言）
enum DefaultPickOwner: Equatable {
    case gateway
    case provider(String)
}

/// 设默认的一次点选（ModelSettingsView.performSwitch 消费）
enum DefaultPickSelection {
    case gateway(String)
    case provider(ProviderRegistry.Entry, String)
}

/// 治理过的模型行组（搜索＋折叠，口径在 Core
/// ModelListGovernance）：当前默认行显「默认」标
/// （全页唯一说法）且不可再点，其余行整行可点，
/// 点选动作由宿主给（设默认/选择面回填共用）
struct GovernedModelRows: View {
    let models: [String]
    /// 搜索词由宿主持有（宿主 List 挂 .searchable），
    /// 分组多实例时各组同词过滤
    let query: String
    let isDefault: (String) -> Bool
    let onSelect: (String) -> Void

    @State private var expanded = false

    var body: some View {
        let presentation = ModelListGovernance.presentation(
            models: models, query: query, expanded: expanded
        )
        ForEach(presentation.shown, id: \.self) { model in
            modelRow(model)
        }
        if presentation.isFiltering && presentation.matchCount == 0 {
            Text("没有找到匹配的模型")
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
        }
        if presentation.hiddenCount > 0 {
            Button {
                expanded = true
            } label: {
                Text(L10n.format("显示全部（还有 %lld 个）", presentation.hiddenCount))
                    .font(.callout)
                    .foregroundStyle(Palette.primary)
            }
        }
    }

    private func modelRow(_ model: String) -> some View {
        let current = isDefault(model)
        let content = HStack(spacing: OneDayMetrics.spacingSM) {
            Text(model)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: OneDayMetrics.spacingS)
            if current {
                Text("默认")
                    .font(.footnote)
                    .foregroundStyle(Palette.success)
            }
        }
        .contentShape(Rectangle())
        if current {
            return AnyView(content)
        }
        return AnyView(
            Button { onSelect(model) } label: { content }
                .buttonStyle(.odPressable)
        )
    }
}

/// 默认模型选择面（第一段点入）：与顶栏同构的分组
/// 列表——默认服务商组＋各具名家组，段头带计数；点
/// 一行即设默认并返回（B6 点即生效），当前默认行
/// 打勾（系统选择器惯例）＋「默认」标双保险但措辞
/// 仍只一种。作用域全句在页脚（B3，与设置页段下
/// 同一句，不许两处两说）
struct DefaultModelPickerView: View {
    let store: ModelManagementStore
    let gatewayModels: [String]
    let providers: [ProviderRegistry.Entry]
    let isCurrentDefault: (DefaultPickOwner, String) -> Bool
    let onSelect: (DefaultPickSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            Section {
                GovernedModelRows(
                    models: gatewayModels,
                    query: query,
                    isDefault: { isCurrentDefault(.gateway, $0) },
                    onSelect: { model in
                        onSelect(.gateway(model))
                        dismiss()
                    }
                )
            } header: {
                Text(L10n.format("默认服务商（%lld）", gatewayModels.count))
            }
            ForEach(providers, id: \.name) { entry in
                Section {
                    GovernedModelRows(
                        models: entry.models,
                        query: query,
                        isDefault: {
                            isCurrentDefault(.provider(entry.name), $0)
                        },
                        onSelect: { model in
                            onSelect(.provider(entry, model))
                            dismiss()
                        }
                    )
                } header: {
                    Text(L10n.format("%@（%lld）", entry.name, entry.models.count))
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: Text("搜索模型"))
        .navigationTitle("默认模型")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text(ModelSettingsView.defaultScopeText)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingS)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.pageBG)
        }
    }
}
