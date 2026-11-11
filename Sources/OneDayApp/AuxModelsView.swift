import OneDayDesign
import OneDayCore
import SwiftUI

/// 辅助模型（§119，用户定版两块之二）：把当前服务
/// 商的模型拉出来，给每个用途分配——什么时候用什
/// 么模型。数据源＝Hermes auxiliary 活槽注册表 19
/// 个（Core AuxSlotCatalog；已死三槽永不呈现），常
/// 用 11 行＋更多 8 行；MoA 两行按拍板②条件显隐。
/// 每行选完即存，走 Dashboard config 写回（通道选
/// 型见 DESIGN §119）；生效口径如实标「下次重启
/// Hermes 后生效」（热生效未验，§103.6 旧账③）。
struct AuxModelsView: View {
    var store: ModelManagementStore

    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("每个用途用哪个模型，在这里分。没单独指定的用途，跟随主模型。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.bottom, OneDayMetrics.spacingS)
                let sections = AuxSlotCatalog.sections(
                    assignments: store.auxAssignments,
                    activePresetUsesMoA: store.activePresetUsesMoA
                )
                slotGroup(title: "常用", slots: sections.common)
                slotGroup(title: "更多", slots: sections.more)
                Text("改动保存后，下次重启 Hermes 才生效。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, OneDayMetrics.spacingM)
                if let notice = store.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingS)
                }
                if let errorMessage = store.errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("辅助模型")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.rawConfig.isEmpty {
                await store.load(appState: appState)
            }
        }
    }

    private func slotGroup(
        title: String, slots: [AuxSlotCatalog.Slot]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
                .padding(.top, OneDayMetrics.spacingL)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    if index > 0 {
                        GroupDivider()
                    }
                    slotRow(slot)
                }
            }
            .odGroup()
        }
    }

    @ViewBuilder
    private func slotRow(_ slot: AuxSlotCatalog.Slot) -> some View {
        let assignment = store.auxAssignments[slot.key] ?? .follow
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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
                assignmentMenu(slot: slot, current: assignment)
            }
            if slot.hasEnabledSwitch {
                Toggle(isOn: enabledBinding(for: slot.key)) {
                    Text("启用")
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                }
                .padding(.top, OneDayMetrics.spacingMicro)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    /// 行内选择器：值域＝跟随主模型＋全部已登记服务
    /// 商的全部模型（默认服务商的模型＝网关候选）
    private func assignmentMenu(
        slot: AuxSlotCatalog.Slot, current: AuxAssignment
    ) -> some View {
        Menu {
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
            guard choice != current else { return }
            Task {
                await store.saveAux(
                    slot: slot.key, assignment: choice,
                    enabled: nil, appState: appState
                )
            }
        } label: {
            if choice == current {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    private func enabledBinding(for slotKey: String) -> Binding<Bool> {
        Binding(
            get: { store.auxEnabled[slotKey] ?? true },
            set: { newValue in
                Task {
                    await store.saveAux(
                        slot: slotKey,
                        assignment: store.auxAssignments[slotKey] ?? .follow,
                        enabled: newValue, appState: appState
                    )
                }
            }
        )
    }
}
