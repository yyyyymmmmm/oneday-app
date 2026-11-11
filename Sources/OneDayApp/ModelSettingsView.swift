import OneDayDesign
import OneDayCore
import SwiftUI

/// 模型管理（0.37.0 模型包，设置·模型与密钥）：三层
/// 一页——接入层（提供商名册＋网关渠道只读）、清单层
/// （全部模型带来源标注）、分配层（模型组合）。口径
/// 依 model-provider-status-design-20261110 定版：
/// 用户自加/自组合，我方只做机制；密钥经 /api/env 落
/// 服务端、配置只存引用；渠道管理凭据不进 App，本页
/// 只读。数据中枢 ModelManagementStore（config 写回
/// 沿旧纪律：先读全量、只改目标键、整包写回）。
struct ModelSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var store = ModelManagementStore()
    @State private var pendingModel: String?
    @State private var pendingDeleteProvider: ProviderRegistry.Entry?
    @State private var showProviderEditor = false
    @State private var editingCombo: ModelCombo?
    @State private var showNewCombo = false
    @State private var pendingActivateCombo: ModelCombo?
    @State private var pendingDeleteCombo: ModelCombo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                currentGroup
                modelsGroup
                providersGroup
                channelsGroup
                combosGroup
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
        .navigationTitle("模型与提供商")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load(appState: appState) }
        .task { await store.load(appState: appState) }
        .sheet(isPresented: $showProviderEditor) {
            ProviderEditorView(store: store) { added in
                if added { Task { await store.load(appState: appState) } }
            }
        }
        .sheet(item: $editingCombo) { combo in
            ModelComboEditorView(store: store, combo: combo) {
                Task { await store.load(appState: appState) }
            }
        }
        .sheet(isPresented: $showNewCombo) {
            ModelComboEditorView(store: store, combo: nil) {
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
            "删除提供商？",
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
            Text("将从服务端配置里移除这家提供商，它的密钥也会一并删掉；正在用它的会话可能受影响。")
        }
        .confirmationDialog(
            "启用这套组合？",
            isPresented: Binding(
                get: { pendingActivateCombo != nil },
                set: { if !$0 { pendingActivateCombo = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("启用「\(pendingActivateCombo?.name ?? "")」") {
                if let combo = pendingActivateCombo {
                    Task { await store.activateCombo(combo, appState: appState) }
                }
                pendingActivateCombo = nil
            }
            Button("取消", role: .cancel) { pendingActivateCombo = nil }
        } message: {
            if let combo = pendingActivateCombo {
                Text(ComboActivation.activationNotice(for: combo))
            }
        }
        .confirmationDialog(
            "删除组合？",
            isPresented: Binding(
                get: { pendingDeleteCombo != nil },
                set: { if !$0 { pendingDeleteCombo = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let combo = pendingDeleteCombo {
                    Task { await store.deleteCombo(combo, appState: appState) }
                }
                pendingDeleteCombo = nil
            }
            Button("取消", role: .cancel) { pendingDeleteCombo = nil }
        } message: {
            Text("只删这套组合的定义；已经启用到服务端的设置不会被撤回。")
        }
    }

    // MARK: - 当前默认（旧段平移）

    private var currentGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("服务端默认模型")
                .padding(.bottom, OneDayMetrics.spacingS)
            Text("服务端新会话的默认模型；聊天时实际用的模型由聊天页顶栏胶囊决定。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Text(store.currentModel ?? "未配置")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                    Spacer()
                    if store.isLoading {
                        ProgressView()
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
            }
            .odGroup()
        }
    }

    // MARK: - 清单层（全部模型·来源标注）

    private var modelsGroup: some View {
        let annotated = store.annotatedModels(appState: appState)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("全部模型")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            Text("每个模型都标了从哪条路走：经网关，或直连某家提供商（直连不经过网关、没有网关的用量记录）。点经网关的模型可设为默认。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if annotated.isEmpty {
                    Text("服务端没有返回可用的模型。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(annotated.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        GroupDivider()
                    }
                    modelRow(entry)
                }
            }
            .odGroup()
        }
    }

    @ViewBuilder
    private func modelRow(_ entry: AnnotatedModel) -> some View {
        let isCurrent = entry.model == store.currentModel
        let content = HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(entry.model)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let runtime = ModelCatalog.aliasRuntime[entry.model] {
                    Text("别名 · 将按 \(runtime) 运行")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(entry.source.label)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            if isCurrent {
                Text("当前")
                    .font(.footnote)
                    .foregroundStyle(Palette.success)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())

        if case .gateway = entry.source, !isCurrent {
            Button {
                pendingModel = entry.model
            } label: {
                content
            }
            .buttonStyle(.odPressable)
        } else {
            content
        }
    }

    // MARK: - 接入层·提供商名册

    private var providersGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("提供商")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if store.providers.isEmpty {
                    Text("还没有添加提供商。添加后，它家的模型会出现在上面的清单里，也能在组合里按槽位选用。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GroupDivider()
                }
                ForEach(Array(store.providers.enumerated()), id: \.element.name) { index, provider in
                    if index > 0 {
                        GroupDivider()
                    }
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text(provider.name)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            if let baseURL = provider.baseURL, !baseURL.isEmpty {
                                Text(baseURL)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(1)
                            }
                            if !provider.models.isEmpty {
                                Text("模型 \(provider.models.count) 个")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        Spacer(minLength: OneDayMetrics.spacingS)
                        Button("删除", role: .destructive) {
                            pendingDeleteProvider = provider
                        }
                        .font(.callout)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
                GroupDivider()
                Button {
                    showProviderEditor = true
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Palette.primary)
                        Text("添加提供商")
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
            .odGroup()
        }
    }

    // MARK: - 接入层·网关渠道（只读）

    private var channelsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("网关渠道")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            Text("经网关的模型从这些渠道走。这里只看：启停与顺序在网关那边管理，App 不碰网关的管理员凭据。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, OneDayMetrics.spacingS)
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
                } else if let placeholder = store.channelsFace.placeholderText {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .odGroup()
        }
    }

    // MARK: - 分配层·组合

    private var combosGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("模型组合")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            Text("把主模型、看图、标题等每个位置用哪个模型存成一套，整套切换。组合对整台服务生效；只有主模型能按单个会话另换。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if store.combosFaceMissing {
                    Text("组合的服务端存储还没开通，这里先留位。开通前，默认模型与提供商照常可用。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if store.combosLoadFailed {
                    Text("组合清单没读出来，可能是网络或服务暂时没响应")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let combos = store.comboDocument?.combos ?? []
                    if combos.isEmpty {
                        Text("还没有组合。可以新建一套，或先把当前配置存为第一套再改。")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.horizontal, OneDayMetrics.spacingM)
                            .padding(.vertical, OneDayMetrics.spacingSM)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        GroupDivider()
                        starterButton
                        GroupDivider()
                        newComboButton
                    } else {
                        ForEach(Array(combos.enumerated()), id: \.element.id) { index, combo in
                            if index > 0 {
                                GroupDivider()
                            }
                            comboRow(combo)
                        }
                        GroupDivider()
                        newComboButton
                    }
                }
            }
            .odGroup()
        }
    }

    private var starterButton: some View {
        Button {
            Task { await store.saveStarterCombo(appState: appState) }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(Palette.primary)
                Text("把当前配置存为第一套组合")
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

    private var newComboButton: some View {
        Button {
            showNewCombo = true
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Palette.primary)
                Text("新建组合")
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

    private func comboRow(_ combo: ModelCombo) -> some View {
        let isActive = store.comboDocument?.activeComboID == combo.id
        return HStack(spacing: OneDayMetrics.spacingSM) {
            Button {
                editingCombo = combo
            } label: {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text(combo.name)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        if isActive {
                            Text("使用中")
                                .font(.footnote)
                                .foregroundStyle(Palette.success)
                        }
                    }
                    Text(combo.summaryLine)
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
                    pendingActivateCombo = combo
                }
                .font(.callout)
            }
            Button {
                pendingDeleteCombo = combo
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Palette.danger)
            }
            .buttonStyle(.odPressable)
            // 0.43.0（A11Y-V6）：纯图标删除钮补标签
            // （带组合名——多组合并列时不靠位置猜）
            .accessibilityLabel(
                L10n.string("删除组合") + "：" + combo.name
            )
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }
}
