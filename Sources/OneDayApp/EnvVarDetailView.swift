import OneDayDesign
import OneDayCore
import SwiftUI

/// 密钥详情：说明、当前值（脱敏）、查看明文、改值、删除。
struct EnvVarDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let entry: EnvVarEntry
    var onChange: () -> Void = {}

    @State private var revealed: String?
    @State private var isRevealing = false
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var notice: String?

    var body: some View {
        List {
            Section {
                // 键值行走 List 行盒（台账 198 收敛
                // S5 嫌疑页查实：键/类别两行同构造）
                listKeyValueRow("键", value: entry.key)
                if let description = entry.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let category = entry.category, !category.isEmpty {
                    listKeyValueRow("类别", value: ServerLabels.categoryLabel(category))
                }
                valueRow
            } header: {
                SettingsSectionHeader("变量")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                actionRow(title: entry.isSet ? "修改值" : "设置值", icon: "pencil.circle") {
                    showEditor = true
                }
                if entry.isSet {
                    actionRow(
                        title: isRevealing ? "拉取中…" : "查看明文",
                        icon: "eye.circle"
                    ) {
                        Task { await reveal() }
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Image(systemName: "trash.circle")
                                .font(.body)
                                .foregroundStyle(Palette.danger)
                                .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                                .accessibilityHidden(true)
                            Text("删除")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.danger)
                            Spacer()
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            } header: {
                SettingsSectionHeader("操作")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            if let notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle(entry.key)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            EnvVarEditorView(existingKey: entry.key) {
                onChange()
                dismiss()
            }
        }
        .confirmationDialog(
            "删除这个环境变量？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await deleteVar() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("依赖它的功能会立即失效；变量目录条目仍在，可随时重新设置。")
        }
    }

    private var valueRow: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text("当前值")
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            if let revealed {
                Text(revealed)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .lineLimit(2)
            } else {
                Text(entry.isSet ? (entry.redactedValue ?? "已设置") : "未设置")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }


    /// List 行盒下的键值行（台账 198 收敛 S5）：共享
    /// KeyValueRow 是 odGroup 卡内件、自带 spacingM 横
    /// 距；List 行盒横距由 listRowInsets 统一给，故本页
    /// 以同构行件就地呈现，只去卡内横距、行高改
    /// settingsRowHeight
    private func listKeyValueRow(_ label: String, value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(.metaMonospaced)
                .tabularDigits()
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .contentShape(Rectangle())
    }

    private func actionRow(
        title: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func reveal() async {
        isRevealing = true
        defer { isRevealing = false }
        do {
            revealed = try await appState.performAdmin { client, config in
                try await client.revealEnvVar(config: config, key: entry.key)
            }
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "明文拉取失败。"
        }
    }

    private func deleteVar() async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteEnvVar(config: config, key: entry.key)
            }
            onChange()
            dismiss()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "删除失败，请稍后再试。"
        }
    }
}
