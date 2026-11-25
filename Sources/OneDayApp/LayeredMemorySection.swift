import OneDayCore
import OneDayDesign
import SwiftUI

/// OneDay 分层记忆清单、语义混合搜索与 ExpeL 行为洞察治理区（P1-2 原生 Section 化）
struct LayeredMemorySection: View {
    @Environment(AppState.self) private var appState

    @State private var layers: [MemoryLayerSummary] = []
    @State private var insights: [MemoryInsightItem] = []
    @State private var searchQuery = ""
    @State private var searchHits: [MemorySearchHit] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var isLoaded = false
    @State private var showAllInsights = false

    var body: some View {
        Group {
            if isLoaded && (!layers.isEmpty || !insights.isEmpty) {
                searchSection
                if !layers.isEmpty {
                    layersSection
                }
                if !insights.isEmpty {
                    insightsSection
                }
            }
        }
        .task {
            await load()
        }
    }

    // MARK: - 混合语义记忆检索

    private var searchSection: some View {
        Section {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                TextField("搜索它记住的事实、偏好或规则…", text: $searchQuery)
                    .font(.subheadline)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await performSearch() }
                    }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchHits = []
                        hasSearched = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)

            if hasSearched {
                if searchHits.isEmpty && !isSearching {
                    Text("没有匹配到相关记忆条目")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    ForEach(searchHits.prefix(8)) { hit in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(hit.title.isEmpty ? hit.layer : hit.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text(hit.layer)
                                    .font(.caption2)
                                    .foregroundStyle(Palette.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.primaryTint, in: Capsule())
                            }
                            if !hit.snippet.isEmpty {
                                Text(hit.snippet)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, OneDayMetrics.spacingXS)
                    }
                }
            }
        } header: {
            SettingsSectionHeader("语义记忆检索")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    // MARK: - 分层记忆概览

    private var layersSection: some View {
        Section {
            ForEach(layers) { layer in
                HStack(spacing: OneDayMetrics.spacingSM) {
                    IconTile(symbol: layer.symbolName, color: Palette.primary, size: OneDayMetrics.iconSlot)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.displayTitle)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text("\(layer.files) 个文件 · \(ByteCountFormatter.string(fromByteCount: Int64(layer.bytes), countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer()
                    Text("\(layer.entries) 条")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.vertical, OneDayMetrics.spacingXS)
            }
        } header: {
            SettingsSectionHeader("分层记忆")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    // MARK: - ExpeL 行为洞察账本

    private var insightsSection: some View {
        let visible = showAllInsights ? insights : Array(insights.prefix(4))
        return Section {
            ForEach(visible) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.rule)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: OneDayMetrics.spacingS) {
                        SettingsStatusPill(
                            text: item.statusLabel,
                            tone: item.status == "active" ? .healthy : .neutral
                        )
                        if !item.scope.isEmpty {
                            Text(item.scope)
                                .font(.caption2)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                        Label("\(item.votesUp)", systemImage: "hand.thumbsup")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Palette.inkSecondary)
                        if item.votesDown > 0 {
                            Label("\(item.votesDown)", systemImage: "hand.thumbsdown")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                }
                .padding(.vertical, OneDayMetrics.spacingXS)
            }
            if insights.count > 4 {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        showAllInsights.toggle()
                    }
                } label: {
                    Text(showAllInsights ? "收起" : "查看全部 \(insights.count) 条洞察")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.primary)
                        .frame(maxWidth: .infinity)
                }
            }
        } header: {
            SettingsSectionHeader("提炼的行为洞察（\(insights.count)）")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    // MARK: - 数据加载

    private func load() async {
        guard let config = appState.config,
              let apiKey = appState.apiKey,
              !appState.isDemo
        else { return }
        async let fetchedLayers = try? appState.client.memoryLayers(config: config, apiKey: apiKey)
        async let fetchedInsights = try? appState.client.memoryInsights(config: config, apiKey: apiKey)
        let (l, i) = await (fetchedLayers, fetchedInsights)
        if let l { layers = l }
        if let i { insights = i }
        isLoaded = true
    }

    private func performSearch() async {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let config = appState.config,
              let apiKey = appState.apiKey,
              !appState.isDemo
        else { return }
        isSearching = true
        defer {
            isSearching = false
            hasSearched = true
        }
        if let hits = try? await appState.client.searchLayeredMemory(
            config: config, apiKey: apiKey, query: q, limit: 20, mode: "hybrid"
        ) {
            searchHits = hits
        } else if let fallback = try? await appState.client.searchLayeredMemory(
            config: config, apiKey: apiKey, query: q, limit: 20, mode: "keyword"
        ) {
            searchHits = fallback
        }
    }
}
