import OneDayDesign
import OneDayCore
import SwiftUI

/// 组合编辑器（0.37.0 分配层）：逐槽位自选——主模型、
/// 常用辅助槽位、其他槽位、委派、备用链（可排序）。
/// 口径（设计 §5）：只存被改过的槽位；provider 候选
/// 只给本机实际可用的（自动／主端点／已添加的提供
/// 商）；模型候选带来源标注。保存只写组合定义（存
/// 服务端），启用是另一个动作（列表页「启用」）。
struct ModelComboEditorView: View {
    var store: ModelManagementStore
    /// nil＝新建；非 nil＝编辑既有
    var combo: ModelCombo?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var name: String = ""
    @State private var mainEnabled = false
    @State private var mainModel = ""
    @State private var slotEnabled: [String: Bool] = [:]
    @State private var slotChoices: [String: SlotChoice] = [:]
    @State private var delegationEnabled = false
    @State private var delegationChoice = SlotChoice(provider: "main", model: "")
    @State private var fallbackEnabled = false
    @State private var fallback: [SlotChoice] = []
    @State private var formProblem: String?
    @State private var isSaving = false
    @State private var initialized = false

    /// 编辑器呈现的槽位序：常用目录序在前，其余按
    /// config 里实际存在的键补后
    private var slotKeys: [String] {
        let primary = AuxSlotCatalog.primary.map(\.key)
        let others = store.presentAuxSlots.filter {
            !AuxSlotCatalog.isPrimary($0)
        }
        return primary + others
    }

    private var providerOptions: [String] {
        AuxSlotCatalog.providerChoices(
            namedProviders: store.providers.map(\.name)
        )
    }

    private var annotatedModels: [AnnotatedModel] {
        store.annotatedModels(appState: appState)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("组合名字（如：省钱版）", text: $name)
                } header: {
                    Text("名字")
                }

                Section {
                    Toggle("改主模型", isOn: $mainEnabled)
                    if mainEnabled {
                        Picker("主模型", selection: $mainModel) {
                            ForEach(appState.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("主模型")
                } footer: {
                    Text("主模型是新会话的默认；单个会话里还能另换。")
                }

                Section {
                    ForEach(slotKeys, id: \.self) { key in
                        slotRow(key)
                    }
                } header: {
                    Text("辅助槽位")
                } footer: {
                    Text("看图、标题、压缩这些活各用哪个模型。没打开的槽位保持现在的设置不动。")
                }

                Section {
                    Toggle("改委派设置", isOn: $delegationEnabled)
                    if delegationEnabled {
                        choicePickers(choice: $delegationChoice)
                    }
                } header: {
                    Text("委派")
                } footer: {
                    Text("智能体派子任务干活时用哪个模型；不改就跟随主模型。")
                }

                Section {
                    Toggle("改备用链", isOn: $fallbackEnabled)
                    if fallbackEnabled {
                        ForEach(Array(fallback.enumerated()), id: \.offset) { index, _ in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("第 \(index + 1) 级")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                                choicePickers(choice: bindingForFallback(index))
                                Button("删掉这一级", role: .destructive) {
                                    fallback.remove(at: index)
                                }
                                .font(.callout)
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove { from, to in
                            fallback.move(fromOffsets: from, toOffset: to)
                        }
                        Button("加一级备用") {
                            fallback.append(SlotChoice(
                                provider: "main",
                                model: appState.availableModels.first ?? ""
                            ))
                        }
                    }
                } header: {
                    Text("备用链（主模型出故障时按顺序顶上）")
                } footer: {
                    Text("只有主模型彻底用不了时才按顺序换，不做负载均衡。长按拖动可排序。")
                }

                if let formProblem {
                    Section {
                        Text(formProblem)
                            .font(.callout)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle(combo == nil ? "新建组合" : "编辑组合")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear { initializeIfNeeded() }
        }
    }

    // MARK: - 槽位行

    @ViewBuilder
    private func slotRow(_ key: String) -> some View {
        let enabled = Binding<Bool>(
            get: { slotEnabled[key] ?? false },
            set: { slotEnabled[key] = $0 }
        )
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AuxSlotCatalog.title(forKey: key))
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Text(slotDetail(key))
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
            }
            if enabled.wrappedValue {
                choicePickers(choice: bindingForSlot(key))
            }
        }
        .padding(.vertical, 2)
    }

    /// 槽位副行：目录说明（常用槽位）＋当前值
    private func slotDetail(_ key: String) -> String {
        let current = ComboCurrentValues.auxChoice(in: store.rawConfig, slot: key)
        let currentText = current == .auto
            ? "现在：自动"
            : "现在：\(current.providerLabel) · \(current.model.isEmpty ? "模型自动" : current.model)"
        if let detail = AuxSlotCatalog.primary.first(where: { $0.key == key })?.detail {
            return "\(detail)（\(currentText)）"
        }
        return currentText
    }

    // MARK: - 选择器组（provider＋model 两行菜单）

    @ViewBuilder
    private func choicePickers(choice: Binding<SlotChoice>) -> some View {
        Picker("走哪条路", selection: Binding(
            get: { choice.wrappedValue.provider },
            set: { choice.wrappedValue.provider = $0 }
        )) {
            ForEach(providerOptions, id: \.self) { provider in
                Text(SlotChoice(provider: provider, model: "").providerLabel)
                    .tag(provider)
            }
        }
        .pickerStyle(.menu)
        Picker("用哪个模型", selection: Binding(
            get: { choice.wrappedValue.model },
            set: { choice.wrappedValue.model = $0 }
        )) {
            Text("不指定（自动）").tag("")
            ForEach(annotatedModels) { entry in
                Text("\(entry.model)（\(entry.source.label)）")
                    .tag(entry.model)
            }
        }
        .pickerStyle(.menu)
    }

    private func bindingForSlot(_ key: String) -> Binding<SlotChoice> {
        Binding(
            get: { slotChoices[key] ?? .auto },
            set: { slotChoices[key] = $0 }
        )
    }

    private func bindingForFallback(_ index: Int) -> Binding<SlotChoice> {
        Binding(
            get: {
                fallback.indices.contains(index)
                    ? fallback[index] : .auto
            },
            set: { value in
                if fallback.indices.contains(index) {
                    fallback[index] = value
                }
            }
        )
    }

    // MARK: - 初始化与保存

    private func initializeIfNeeded() {
        guard !initialized else { return }
        initialized = true
        if let combo {
            name = combo.name
            if let main = combo.mainModel {
                mainEnabled = true
                mainModel = main
            }
            for key in slotKeys {
                if let choice = combo.aux[key] {
                    slotEnabled[key] = true
                    slotChoices[key] = choice
                } else {
                    slotChoices[key] = ComboCurrentValues.auxChoice(
                        in: store.rawConfig, slot: key
                    )
                }
            }
            if let delegation = combo.delegation {
                delegationEnabled = true
                delegationChoice = delegation
            }
            fallbackEnabled = combo.includesFallback
            fallback = combo.fallback
        } else {
            for key in slotKeys {
                slotChoices[key] = ComboCurrentValues.auxChoice(
                    in: store.rawConfig, slot: key
                )
            }
        }
        if mainModel.isEmpty {
            mainModel = appState.availableModels.first ?? ""
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            formProblem = "先给这套组合起个名字。"
            return
        }
        formProblem = nil
        var aux: [String: SlotChoice] = [:]
        for key in slotKeys where slotEnabled[key] == true {
            aux[key] = slotChoices[key] ?? .auto
        }
        let built = ModelCombo(
            id: combo?.id ?? UUID().uuidString,
            name: trimmed,
            mainModel: mainEnabled && !mainModel.isEmpty ? mainModel : nil,
            aux: aux,
            delegation: delegationEnabled ? delegationChoice : nil,
            fallback: fallbackEnabled ? fallback : [],
            includesFallback: fallbackEnabled,
            updatedAt: Date().timeIntervalSince1970
        )
        isSaving = true
        defer { isSaving = false }
        if await store.saveCombo(built, appState: appState) {
            onSaved()
            dismiss()
        } else {
            formProblem = store.notice ?? "保存没完成，请稍后再试。"
        }
    }
}
