import OneDayDesign
import OneDayCore
import SwiftUI

/// 预设编辑（§119，旧组合编辑器降维）：一份预设＝
/// 默认模型＋整套辅助分配的快照。新建时以当前设置
/// 为底稿（整套快照口径），逐行可改；旧组合的委派/
/// 备用链字段本页不编辑、保存时原样保留不丢。预设
/// 与「多模型汇总」不是一回事：那是几个模型一起答
/// 一道题，这里是把各用途的分配打包切换。
struct PresetEditorView: View {
    var store: ModelManagementStore
    /// nil＝新建（以当前设置为底稿）；非 nil＝编辑
    var combo: ModelCombo?
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var name: String
    @State private var mainModel: String?
    @State private var choices: [String: AuxAssignment]
    @State private var isSaving = false
    @State private var formProblem: String?

    init(
        store: ModelManagementStore, combo: ModelCombo?,
        onDone: @escaping () -> Void
    ) {
        self.store = store
        self.combo = combo
        self.onDone = onDone
        _name = State(initialValue: combo?.name ?? "")
        // 新建以当前设置为底稿：默认模型先落现行值
        _mainModel = State(
            initialValue: combo?.mainModel ?? store.currentModel
        )
        var initial: [String: AuxAssignment] = [:]
        let named = store.providers.map(\.name)
        for slot in AuxSlotCatalog.all {
            if let combo, let choice = combo.aux[slot.key] {
                initial[slot.key] = AuxAssignment.from(
                    choice: choice, namedProviders: named
                )
            } else {
                initial[slot.key] = store.auxAssignments[slot.key] ?? .follow
            }
        }
        _choices = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("预设名字（如：省钱模式）", text: $name)
                } header: {
                    Text("预设")
                } footer: {
                    Text("预设是「默认模型＋整套辅助分配」的一份快照，启用后整套一起换；与多模型汇总（几个模型一起答一道题）不是一回事。")
                }

                Section {
                    Picker("默认模型", selection: $mainModel) {
                        Text("不指定（启用时不动默认模型）")
                            .tag(String?.none)
                        ForEach(mainModelOptions, id: \.self) { model in
                            Text(model).tag(String?.some(model))
                        }
                    }
                } header: {
                    Text("默认模型")
                } footer: {
                    Text("只有经网关的模型能设为全局默认；直连服务商的模型请在下面给具体用途指定。")
                }

                slotSection(title: "常用", slots: AuxSlotCatalog.common)
                slotSection(title: "更多", slots: AuxSlotCatalog.more)

                if let combo, combo.delegation != nil || combo.includesFallback {
                    Section {
                        Text("这份预设还带着旧版的委派/备用链设置，本页不改它，启用时照旧生效。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                if let formProblem {
                    Section {
                        Text(formProblem)
                            .font(.callout)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle(combo == nil ? "新建预设" : "编辑预设")
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
        }
    }

    private var mainModelOptions: [String] {
        var options = appState.availableModels
        if let mainModel, !options.contains(mainModel) {
            options.insert(mainModel, at: 0)
        }
        return options
    }

    private func slotSection(
        title: String, slots: [AuxSlotCatalog.Slot]
    ) -> some View {
        Section {
            ForEach(slots, id: \.id) { slot in
                HStack(spacing: OneDayMetrics.spacingSM) {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text(slot.title())
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text(slot.detail())
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: OneDayMetrics.spacingS)
                    assignmentMenu(for: slot)
                }
            }
        } header: {
            Text(title)
        }
    }

    private func assignmentMenu(
        for slot: AuxSlotCatalog.Slot
    ) -> some View {
        let current = choices[slot.key] ?? .follow
        return Menu {
            optionButton(
                slot: slot, choice: .follow, current: current,
                label: "跟随主模型"
            )
            Section("默认服务商") {
                ForEach(appState.availableModels, id: \.self) { model in
                    optionButton(
                        slot: slot,
                        choice: .use(.mainEndpoint, model: model),
                        current: current, label: model
                    )
                }
            }
            ForEach(store.providers, id: \.name) { provider in
                Section(provider.name) {
                    ForEach(provider.models, id: \.self) { model in
                        optionButton(
                            slot: slot,
                            choice: .use(.named(provider.name), model: model),
                            current: current, label: model
                        )
                    }
                }
            }
            if case .use(.other(let raw), let model) = current {
                Section("现在的设置（不在服务商名单里）") {
                    optionButton(
                        slot: slot, choice: current, current: current,
                        label: model.isEmpty ? raw : "\(raw) · \(model)"
                    )
                }
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingMicro) {
                Text(current.valueLabel())
                    .font(.callout)
                    .foregroundStyle(Palette.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .contentShape(Rectangle())
        }
    }

    private func optionButton(
        slot: AuxSlotCatalog.Slot, choice: AuxAssignment,
        current: AuxAssignment, label: String
    ) -> some View {
        Button {
            choices[slot.key] = choice
        } label: {
            if choice == current {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            formProblem = L10n.string("先给这份预设起个名字。")
            return
        }
        formProblem = nil
        isSaving = true
        defer { isSaving = false }
        var aux: [String: SlotChoice] = [:]
        for slot in AuxSlotCatalog.all {
            aux[slot.key] = (choices[slot.key] ?? .follow).slotChoice
        }
        let saved = ModelCombo(
            id: combo?.id ?? UUID().uuidString,
            name: trimmed,
            mainModel: mainModel,
            aux: aux,
            delegation: combo?.delegation,
            fallback: combo?.fallback ?? [],
            includesFallback: combo?.includesFallback ?? false,
            updatedAt: Date().timeIntervalSince1970
        )
        if await store.saveCombo(saved, appState: appState) {
            onDone()
            dismiss()
        } else {
            formProblem = store.notice ?? "保存没完成，请稍后再试。"
        }
    }
}
