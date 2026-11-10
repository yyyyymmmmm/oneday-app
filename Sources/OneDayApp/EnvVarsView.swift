import OneDayDesign
import OneDayCore
import SwiftUI

struct EnvVarsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var entries: [EnvVarEntry] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !entries.isEmpty {
                    // 0.3.7 卡 9：摘要卡「已设置 X / 共 Y」＋
                    // 按服务端类别分组（已裁 4：类别名走
                    // ServerLabels 翻译，未知回落「其他」；
                    // 组内已设定在前）
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text("已设置 \(entries.filter(\.isSet).count) / 共 \(entries.count)")
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .odGroup()
                    ForEach(
                        Array(entryGroups.enumerated()), id: \.element.label
                    ) { groupIndex, group in
                        SectionLabel(group.label)
                            .padding(.top, groupIndex == 0 ? 28 : 28)
                            .padding(.bottom, OneDayMetrics.spacingS)
                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 {
                                    GroupDivider()
                                }
                                NavigationLink {
                                    EnvVarDetailView(entry: entry) {
                                        Task { await load() }
                                    }
                                } label: {
                                    entryRow(entry)
                                }
                                .buttonStyle(.odPressable)
                            }
                        }
                        .odGroup()
                    }
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取密钥…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("密钥")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增环境变量")
            }
        }
        .sheet(isPresented: $showAdd) {
            EnvVarEditorView(existingKey: nil) {
                Task { await load() }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    /// 类别分组（组内已设定在前的排序先行，再按类别归组）
    private var entryGroups: [(label: String, items: [EnvVarEntry])] {
        let sorted = entries.sorted { $0.isSet && !$1.isSet }
        return ServerLabels.grouped(sorted) { $0.category }
    }

    private func entryRow(_ entry: EnvVarEntry) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.key)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                // 卡 9 点名：服务端 description 无中文不上屏
                if let description = entry.description,
                   !description.isEmpty,
                   ServerLabels.isChineseText(description) {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(entry.isSet ? (entry.redactedValue ?? "已设置") : "未设置")
                .font(.system(.caption, design: .monospaced))
                // 0.23.0（审计 G1）：未设置也是要读的字，
                // inkMuted（2.75:1）退出文字位，两态同归
                // inkSecondary
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await appState.performAdmin { client, config in
                try await client.envVars(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "密钥读取失败。"
        }
    }
}
