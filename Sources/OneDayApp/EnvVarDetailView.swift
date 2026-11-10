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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("变量")
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    LabeledContent("键") {
                        Text(entry.key)
                            .font(.system(.callout, design: .monospaced))
                    }
                    if let description = entry.description, !description.isEmpty {
                        GroupDivider()
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.horizontal, OneDayMetrics.spacingM)
                            .padding(.vertical, OneDayMetrics.spacingSM)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let category = entry.category, !category.isEmpty {
                        GroupDivider()
                        LabeledContent("类别", value: ServerLabels.categoryLabel(category))
                    }
                    GroupDivider()
                    valueRow
                }
                .odGroup()

                SectionLabel("操作")
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    actionRow(title: entry.isSet ? "修改值" : "设置值", icon: "pencil.circle") {
                        showEditor = true
                    }
                    if entry.isSet {
                        GroupDivider()
                        actionRow(
                            title: isRevealing ? "拉取中…" : "查看明文",
                            icon: "eye.circle"
                        ) {
                            Task { await reveal() }
                        }
                        GroupDivider()
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
                                    .font(.body)
                                    .foregroundStyle(Palette.danger)
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
                if let notice {
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
                .font(.body)
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
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
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
