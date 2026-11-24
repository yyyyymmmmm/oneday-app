import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 记忆可见化数据中枢（台账 164）：数据源是 Hermes
/// 本体的学习图谱（GET /api/learning/graph）——服
/// 务端学到的技能＋记忆块。真源纪律：记忆只此一份
/// 在服务端，本店只持呈现快照、不落盘、不与「记
/// 忆条目」段（write-gate 桥数据）合并冒充；改/删
/// 走 /api/learning/node 本体口，写后回读图谱验生
/// 效（不做本地乐观落定）。刷新失败且已有数据时保
/// 持旧数据不翻态（MemoriesStore 同口径），只记一
/// 行人话提示。
@MainActor
@Observable
final class LearningGraphStore {
    enum LoadState: Equatable {
        case loading
        case failed(String)
        case ready
    }

    private(set) var loadState: LoadState = .loading
    private(set) var graph: LearningGraph = .empty
    /// 已有数据时刷新/写后回读失败的人话（段内小字
    /// 呈现，不翻态、不清数据）
    private(set) var notice: String?
    private var loadInFlight = false
    /// 新鲜度门（§416 收编，§367 口径）：读触发先
    /// 过门，TTL 内零请求
    private var freshness = FreshnessGate(
        ttl: FreshnessGate.standardListTTL
    )

    func load(appState: AppState) async {
        await load(appState: appState, now: Date())
    }

    /// 读触发入口（§416 新鲜度门）：TTL 内且配置没
    /// 变直接用已载图谱、零请求；首拉/过期/换服务
    /// 器才走 load 全量。下拉刷新不经此门、恒走
    /// load 强制；写后回读（改写/删除节点）走 load
    /// 本体、成功同落 stamp（§367.4）
    func loadIfNeeded(appState: AppState) async {
        await loadIfNeeded(appState: appState, now: Date())
    }

    func loadIfNeeded(appState: AppState, now: Date) async {
        guard !freshness.isFresh(
            configKey: appState.config?.baseString, now: now
        ) else { return }
        await load(appState: appState, now: now)
    }

    /// 时刻注入的加载本体（钉测拨时刻验过期）
    func load(appState: AppState, now: Date) async {
        guard !loadInFlight else { return }
        loadInFlight = true
        defer { loadInFlight = false }
        do {
            let loaded = try await appState.performAdmin { client, config in
                try await client.learningGraph(config: config)
            }
            graph = loaded
            loadState = .ready
            freshness.stamp(
                configKey: appState.config?.baseString, now: now
            )
            notice = nil
        } catch {
            let message = (error as? HermesError)?.userMessage
                ?? "它记住的事没读出来，可能是网络或服务暂时没响应"
            if loadState == .ready {
                notice = message
            } else {
                loadState = .failed(message)
            }
        }
    }

    /// 节点全文（编辑预填）：GET 提不到内容（形态
    /// 漂移/服务端无此节点）→ nil，详情页退回图谱卡
    /// 面兜底、不假装拿到全文
    func nodeContent(appState: AppState, id: String) async -> String? {
        let loaded = try? await appState.performAdmin { client, config in
            try await client.learningNode(config: config, id: id)
        }
        return loaded?.content
    }

    /// 改写节点全文：PUT 后回读图谱（真源覆写呈现，
    /// 回读失败只记提示、详情照常关）
    func updateNode(
        appState: AppState, id: String, content: String
    ) async throws {
        try await appState.performAdmin { client, config in
            try await client.updateLearningNode(
                config: config, id: id, content: content
            )
        }
        await load(appState: appState)
    }

    /// 删除/归档节点：DELETE 后回读图谱
    func deleteNode(appState: AppState, id: String) async throws {
        try await appState.performAdmin { client, config in
            try await client.deleteLearningNode(config: config, id: id)
        }
        await load(appState: appState)
    }
}

/// 「它记住的事」段（台账 164）：记忆页内、紧随
/// 「记忆条目」段（两者数据源不同、标题与说明都
/// 分开，不合并）。呈现纪律：只给人话——节点 id
/// （寻址坐标）不露面、来源翻成人话（关于你/它的
/// 备忘）、技能只报名字/分类/用过几次；图谱的边与
/// 统计是系统内部量、不递给用户。
struct LearningMemorySection: View {
    @Environment(AppState.self) private var appState
    let store: LearningGraphStore

    @State private var selectedNode: LearningNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("它记住的事")
                .padding(.bottom, OneDayMetrics.spacingXS)

            switch store.loadState {
            case .loading:
                loadingRow
            case .failed(let message):
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                    InlineError(message)
                    Button("重试") {
                        Task { await store.load(appState: appState) }
                    }
                    .buttonStyle(.odSecondary)
                }
            case .ready:
                readyContent
            }
            if let notice = store.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, OneDayMetrics.spacingS)
            }
        }
        .padding(.bottom, OneDayMetrics.sectionOuterSpacing)
        .sheet(item: $selectedNode) { node in
            LearningNodeDetailView(store: store, node: node)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            ProgressView()
            Text("正在读取它记住的事…")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    @ViewBuilder
    private var readyContent: some View {
        let memoryNodes = store.graph.memoryNodes
        let skillNodes = store.graph.skillNodes
        if memoryNodes.isEmpty && skillNodes.isEmpty {
            EmptyState(
                icon: "brain",
                title: "还没有记住什么",
                message: "它还没有积累长期记忆、也没学会新技能；聊得多了，这里会慢慢长出来。"
            )
        } else {
            if !memoryNodes.isEmpty {
                groupTitle("记住的事")
                groupCard {
                    ForEach(memoryNodes) { node in
                        if node.id != memoryNodes.first?.id { Divider() }
                        memoryRow(node)
                    }
                }
            }
            if !skillNodes.isEmpty {
                groupTitle("学会的技能")
                    .padding(.top, OneDayMetrics.spacingM)
                groupCard {
                    ForEach(skillNodes) { node in
                        if node.id != skillNodes.first?.id { Divider() }
                        skillRow(node)
                    }
                }
            }
        }
    }

    private func groupTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.bottom, OneDayMetrics.spacingXS)
    }

    private func groupCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .odGroup()
    }

    private func memoryRow(_ node: LearningNode) -> some View {
        let card = store.graph.card(for: node)
        return Button {
            selectedNode = node
        } label: {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(memoryRowTitle(node, card: card))
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let body = card?.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                Text(memoryMetaLine(node, card: card))
                    .font(.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, OneDayMetrics.spacingS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func skillRow(_ node: LearningNode) -> some View {
        Button {
            selectedNode = node
        } label: {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(node.label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(skillMetaLine(node))
                    .font(.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, OneDayMetrics.spacingS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    /// 记忆行标题：卡标题优先（图谱组装的块首行），
    /// 卡缺失/标题空退回节点 label
    private func memoryRowTitle(
        _ node: LearningNode, card: LearningMemoryCard?
    ) -> String {
        if let title = card?.title, !title.isEmpty { return title }
        return node.label
    }

    /// 记忆行小字：来源人话＋时刻（来源："profile"
    /// ＝关于你、"memory"＝它的备忘）
    private func memoryMetaLine(
        _ node: LearningNode, card: LearningMemoryCard?
    ) -> String {
        var parts: [String] = []
        let source = node.memorySource ?? card?.source
        parts.append(source == "profile" ? "关于你" : "它的备忘")
        if let date = node.timestampDate {
            parts.append(DisplayDate.dateTime(date))
        }
        return parts.joined(separator: " · ")
    }

    /// 技能行小字：分类＋用过几次＋时刻（分类是服
    /// 务端原样短词，属内容不是系统量、照原样出）
    private func skillMetaLine(_ node: LearningNode) -> String {
        var parts: [String] = []
        if let category = node.category, !category.isEmpty {
            parts.append(category)
        }
        if node.useCount > 0 {
            parts.append("用过 \(node.useCount) 次")
        }
        if let date = node.timestampDate {
            parts.append(DisplayDate.dateTime(date))
        }
        return parts.isEmpty ? "学会的技能" : parts.joined(separator: " · ")
    }
}

/// 节点详情（台账 164）：全文读取（GET 预填）→ 可
/// 编辑 → 保存（PUT）；删除/归档走确认（服务端语
/// 义按 kind 分流文案：记忆删了不可恢复、技能归档
/// 可恢复）。全文读不到时如实露错、不拿截断的卡面
/// 冒充全文让人误改（记忆节点例外：卡面即块全文
/// 的截断形态，仍须明示是预览截断——故同样不开放
/// 编辑，只给删除）。
struct LearningNodeDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let store: LearningGraphStore
    let node: LearningNode

    @State private var draft = ""
    @State private var original = ""
    @State private var isLoadingContent = true
    @State private var contentUnavailable = false
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var isMemory: Bool { node.kind == "memory" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                    metaBlock
                    if isLoadingContent {
                        HStack(spacing: OneDayMetrics.spacingS) {
                            ProgressView()
                            Text("正在读取全文…")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    } else if contentUnavailable {
                        InlineError("全文没读出来（可能是网络或服务暂时没响应），先不开放编辑，以免把不完整的内容存回去。")
                        Button("重新读取") { Task { await loadContent() } }
                            .buttonStyle(.odSecondary)
                    } else {
                        TextEditor(text: $draft)
                            .font(.body)
                            .frame(minHeight: 260)
                            .padding(OneDayMetrics.spacingS)
                            .odGroup()
                    }
                    if let errorMessage {
                        InlineError(errorMessage)
                    }
                    deleteBlock
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle(isMemory ? "这条记忆" : "这个技能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(
                            isLoadingContent || contentUnavailable
                                || isSaving || draft == original
                                || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
        }
        .fullscreenPopBridge()
        .task { await loadContent() }
        .confirmationDialog(
            isMemory ? "删掉这条记忆？" : "归档这个技能？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(
                isMemory ? "确认删除" : "确认归档",
                role: .destructive
            ) {
                Task { await deleteNode() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                isMemory
                    ? "删了就没了，它之后不会再记得这件事。"
                    : "归档后它不再使用这个技能，但还能恢复。"
            )
        }
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            Text(node.label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(metaLine)
                .font(.caption)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if isMemory {
            parts.append(
                node.memorySource == "profile" ? "关于你" : "它的备忘"
            )
        } else {
            if let category = node.category, !category.isEmpty {
                parts.append(category)
            }
            if node.useCount > 0 {
                parts.append("用过 \(node.useCount) 次")
            }
            if node.createdBy == "agent" {
                parts.append("它自己学会的")
            }
        }
        if let date = node.timestampDate {
            parts.append(DisplayDate.dateTime(date))
        }
        return parts.joined(separator: " · ")
    }

    private var deleteBlock: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Divider()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Text(isMemory ? "删掉这条记忆" : "归档这个技能")
                    .font(.body)
            }
            .buttonStyle(.odPressable)
            .disabled(isDeleting || isSaving)
            Text(
                isMemory
                    ? "删除立即生效、不能恢复。"
                    : "归档立即生效，之后还能恢复。"
            )
            .font(.footnote)
            .foregroundStyle(Palette.inkSecondary)
        }
    }

    private func loadContent() async {
        isLoadingContent = true
        contentUnavailable = false
        errorMessage = nil
        if let content = await store.nodeContent(
            appState: appState, id: node.id
        ) {
            draft = content
            original = content
        } else {
            contentUnavailable = true
        }
        isLoadingContent = false
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await store.updateNode(
                appState: appState, id: node.id, content: draft
            )
            dismiss()
        } catch {
            errorMessage = (error as? HermesError)?.userMessage
                ?? "没存上，请稍后再试。"
        }
    }

    private func deleteNode() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await store.deleteNode(appState: appState, id: node.id)
            dismiss()
        } catch {
            errorMessage = (error as? HermesError)?.userMessage
                ?? (isMemory ? "没删掉，请稍后再试。" : "没归档成，请稍后再试。")
        }
    }
}
