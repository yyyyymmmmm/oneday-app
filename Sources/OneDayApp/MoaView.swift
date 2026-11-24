import OneDayCore
import OneDayDesign
import SwiftUI

/// 多模型会商页（H9 MoA，DESIGN §390；设置·模型）：一组
/// 预设＝几个参考模型先各自答、一个汇总模型综合。预设
/// 存服务端 moa 配置（整图权威、预设名是配置的键）；
/// 在聊天里从模型选择器的「多模型会商」组直接选预设就
/// 能用（逐请求 provider=moa）。与组合（逐槽位自选）是
/// 同一思想的服务端实现：组合管单模型槽位，会商管多
/// 模型协同。
struct MoaView: View {
    @Environment(AppState.self) private var appState
    let modelStore: ModelManagementStore
    @State private var store = MoaStore()
    @State private var editingPreset: MoaPreset?
    @State private var editingName: String?
    @State private var showEditor = false

    private var ops: MoaOperations {
        MoaOperations(
            load: {
                try await appState.performAdmin { client, config in
                    try await client.moaConfig(config: config)
                }
            },
            save: { edited in
                try await appState.performAdmin { client, config in
                    try await client.setMoaConfig(config: config, moa: edited)
                }
            }
        )
    }

    var body: some View {
        List {
            Section {
                Text("重要问题可以让几个模型先各自想一遍，再由一个汇总模型综合成最终回答——这就是会商。一套会商方案叫一个预设；建好后，在聊天的模型选择器里选「多模型会商」下的预设就能用。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Color.clear)

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
            }

            content
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("多模型会商")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(ops: ops) }
        .refreshable { await store.load(ops: ops) }
        .sheet(isPresented: $showEditor) {
            if let editingPreset {
                MoaPresetEditor(
                    preset: editingPreset,
                    name: editingName ?? "",
                    isDefault: store.config?.defaultPreset == (editingName ?? ""),
                    mainModels: appState.availableModels,
                    namedProviders: modelStore.userProviders
                ) { saved, savedName, makeDefault in
                    // 整图保存口径：以当前真值为底，改名先
                    // 摘旧名、落新预设、按需改默认，再整图
                    // 交 MoaStore 保存（图外名字＝删除）
                    guard var edited = store.config else { return }
                    if let original = editingName, original != savedName {
                        edited.presets.removeValue(forKey: original)
                        if edited.defaultPreset == original {
                            edited.defaultPreset = savedName
                        }
                        if edited.activePreset == original {
                            edited.activePreset = savedName
                        }
                    }
                    edited.presets[savedName] = saved
                    if makeDefault { edited.defaultPreset = savedName }
                    await store.save(ops: ops, edited: edited)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取会商预设…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
        case .notLoggedIn:
            Section {
                Text("登录已失效，重新连接服务器后这里会显示会商预设。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
        case .failed(let message):
            Section {
                InlineError(message)
                Button("重试") { Task { await store.load(ops: ops) } }
            }
            .listRowBackground(Palette.surface)
        case .ready(let config):
            Section {
                if config.presets.isEmpty {
                    Text("还没有预设。建一个：选几个参考模型，再选一个汇总模型。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(config.presetNames, id: \.self) { name in
                    if let preset = config.presets[name] {
                        Button {
                            editingPreset = preset
                            editingName = name
                            showEditor = true
                        } label: {
                            presetRow(name: name, preset: preset, config: config)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isWriting)
                    }
                }
                Button("新建预设") {
                    editingPreset = MoaPreset()
                    editingName = nil
                    showEditor = true
                }
                .disabled(store.isWriting)
            } header: {
                Text("会商预设")
            } footer: {
                Text("「默认」是没指定时用的预设；「使用中」是服务端当前生效的那套。在聊天里选预设是逐次的，不改这里的默认。")
            }
        }
    }

    private func presetRow(
        name: String, preset: MoaPreset, config: MoaConfig
    ) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                if config.defaultPreset == name {
                    Text("默认")
                        .font(.caption)
                        .foregroundStyle(Palette.primary)
                }
                if config.effectivePresetName == name {
                    Text("使用中")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                if !preset.enabled {
                    Text("已停用")
                        .font(.caption)
                        .foregroundStyle(Palette.danger)
                }
                Spacer()
                DisclosureChevron(font: .caption)
            }
            Text("参考 \(preset.referenceModels.count) 个 · 汇总：\(preset.aggregator.model.isEmpty ? "未选" : preset.aggregator.model)")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .contentShape(Rectangle())
    }
}

/// 预设编辑器：参考槽可增删启停、汇总槽必填；未编辑的
/// 高级字段（温度/超时/降级策略）从原预设原样带回，不
/// 在保存时丢失；保存前按服务端 validate_moa_payload
/// 同口径本地预检（至少一个完整参考槽＋汇总完整）
struct MoaPresetEditor: View {
    private struct SlotDraft: Identifiable {
        let id = UUID()
        var slot: MoaSlot
    }

    @Environment(\.dismiss) private var dismiss
    /// 原预设全量副本：保存时以它为底，只覆写编辑到的
    /// 字段（参考槽/汇总槽/启用），高级字段不丢
    private let original: MoaPreset
    @State private var name: String
    @State private var enabled: Bool
    @State private var makeDefault: Bool
    @State private var refs: [SlotDraft]
    @State private var aggregator: MoaSlot
    @State private var problem: String?
    let mainModels: [String]
    let namedProviders: [ProviderRegistry.Entry]
    let onSave: (MoaPreset, String, Bool) async -> Void

    init(
        preset: MoaPreset, name: String, isDefault: Bool,
        mainModels: [String], namedProviders: [ProviderRegistry.Entry],
        onSave: @escaping (MoaPreset, String, Bool) async -> Void
    ) {
        self.original = preset
        _name = State(initialValue: name)
        _enabled = State(initialValue: preset.enabled)
        _makeDefault = State(initialValue: isDefault)
        _refs = State(initialValue: preset.referenceModels.map { SlotDraft(slot: $0) })
        _aggregator = State(initialValue: preset.aggregator)
        self.mainModels = mainModels
        self.namedProviders = namedProviders
        self.onSave = onSave
    }

    private var draftPreset: MoaPreset {
        var preset = original
        preset.enabled = enabled
        preset.referenceModels = refs.map(\.slot)
        preset.aggregator = aggregator
        return preset
    }

    var body: some View {
        NavigationStack {
            Form {
                if let problem {
                    Section {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
                Section("预设") {
                    TextField("预设名（如 careful）", text: $name)
                    Toggle("启用这个预设", isOn: $enabled)
                    Toggle("设为默认预设", isOn: $makeDefault)
                }
                Section("参考模型（各自先答）") {
                    ForEach($refs) { $draft in
                        slotFields($draft.slot)
                        Toggle("这一路参与会商", isOn: $draft.slot.enabled)
                        Button("删掉这一路", role: .destructive) {
                            let id = draft.id
                            refs.removeAll { $0.id == id }
                        }
                    }
                    Button("加一路参考模型") {
                        refs.append(SlotDraft(slot: MoaSlot()))
                    }
                }
                Section("汇总模型（综合成最终回答）") {
                    slotFields($aggregator)
                }
            }
            .navigationTitle(name.isEmpty ? "会商预设" : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let preset = draftPreset
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            problem = "先给预设起个名字。"
                            return
                        }
                        if let first = preset.problems(named: trimmed).first {
                            problem = first
                            return
                        }
                        Task {
                            await onSave(preset, trimmed, makeDefault)
                            dismiss()
                        }
                    }
                }
            }
        }
        .fullscreenPopBridge()
    }

    /// 一个槽的服务商/模型：快捷菜单（默认服务商模型＋
    /// 已配服务商模型，与辅助模型页同源）＋自由填写
    @ViewBuilder
    private func slotFields(_ slot: Binding<MoaSlot>) -> some View {
        Menu {
            Section("默认服务商") {
                ForEach(mainModels, id: \.self) { model in
                    Button(model) {
                        slot.wrappedValue.provider = "custom"
                        slot.wrappedValue.model = model
                    }
                }
            }
            ForEach(namedProviders, id: \.name) { provider in
                Section(provider.name) {
                    ForEach(provider.models, id: \.self) { model in
                        Button(model) {
                            slot.wrappedValue.provider = provider.name
                            slot.wrappedValue.model = model
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text("选模型")
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(slot.wrappedValue.model.isEmpty ? "未选" : slot.wrappedValue.model)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                DisclosureChevron(.upDown, font: .caption2)
            }
        }
        TextField("服务商（如 custom、openrouter）", text: slot.provider)
        TextField("模型", text: slot.model)
        TextField("思考强度（可选，如 high）", text: Binding(
            get: { slot.wrappedValue.reasoningEffort ?? "" },
            set: { slot.wrappedValue.reasoningEffort = $0.isEmpty ? nil : $0 }
        ))
    }
}
