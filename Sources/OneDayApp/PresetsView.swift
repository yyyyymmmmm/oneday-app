import OneDayDesign
import OneDayCore
import SwiftUI

/// 预设页（§150 B5：自模型设置主面降为一行入口点
/// 入；本体沿 §119＋cx-model 的本地预设形态——清
/// 单即本地文档、启用只剩服务端写回＋本地 active
/// 标记）。启用不再弹窗（B6 点即生效）；删除是
/// 不可逆事，保留确认弹窗一处
struct PresetsView: View {
    let store: ModelManagementStore

    @Environment(AppState.self) private var appState
    @State private var editingPreset: ModelCombo?
    @State private var showNewPreset = false
    @State private var pendingDeletePreset: ModelCombo?

    var body: some View {
        List {
            Section {
                let presets = store.comboDocument?.combos ?? []
                if presets.isEmpty {
                    Text("还没有预设。可以新建一份，或先把当前设置存为第一份再改。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                    starterButton
                    newPresetButton
                } else {
                    ForEach(presets, id: \.id) { preset in
                        presetRow(preset)
                    }
                    newPresetButton
                }
            } footer: {
                Text("预设是整套设置的快照：默认模型加全部辅助分配，一次切换。不是几个模型一起答一道题。")
            }
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
        .navigationTitle("预设")
        .navigationBarTitleDisplayMode(.inline)
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
            }
        }
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
            }
        }
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
                    Task {
                        await store.activateCombo(
                            preset, appState: appState
                        )
                    }
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
    }
}
