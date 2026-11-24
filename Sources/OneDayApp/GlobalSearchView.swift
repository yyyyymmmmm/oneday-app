import OneDayCore
import OneDayDesign
import SwiftUI

/// 全局统一搜索（台账 176，OB-U4；DESIGN §391）：一个
/// 入口搜四类——
/// - 会话：服务端搜索端点（与全部对话页同一个 /api/
///   sessions/search，450ms 防抖同口径），命中走宿主
///   回调（与全部对话页搜索命中同路：关页＋切聊天格
///   ＋落点请求）；
/// - 文件：资源库名单店（LibraryListStore，与文件页同
///   一份名单/快照），命中走文件页定位信箱；
/// - 定时任务：定时共享店（CronStore），命中在本栈内
///   直推既有详情页；
/// - 设置项：Core SettingsCatalog.search（与设置页内
///   搜索同源同口径），命中走设置路由信箱＋设置 sheet
///   请求（目的地→路由映射与设置页共用 SettingsRoute.
///   from(destination:)）。
/// 本面只做聚合与分发，不自建任何一类数据的第二真源。
struct GlobalSearchView: View {
    /// 会话命中回调（宿主承接打开＋落点，与全部对话页
    /// 的 onOpenSearchHit 同语义）
    var onOpenSearchHit: ((SessionSearchHit) -> Void)? = nil
    /// 文件/设置命中后的宿主收尾（关掉宿主页封皮，落
    /// 点信箱由根层 ContentView 消费；会话命中走上面
    /// 的回调、自带收尾，不经此口）
    var onCloseHost: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var sessionHits: [SessionSearchHit] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    private let bridgeClient = OneDayBridgeClient()

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cronStore: CronStore { appState.sharedCronStore() }
    private var libraryStore: LibraryListStore {
        appState.sharedLibraryListStore()
    }

    private var fileHits: [Deliverable] {
        guard !trimmedQuery.isEmpty,
              let items = libraryStore.deliverables else { return [] }
        let needle = trimmedQuery.lowercased()
        return items.filter {
            $0.entry.name.lowercased().contains(needle)
                || $0.entry.path.lowercased().contains(needle)
        }
    }

    private var cronHits: [CronJob] {
        guard !trimmedQuery.isEmpty else { return [] }
        let needle = trimmedQuery.lowercased()
        return cronStore.jobs.filter {
            $0.title.lowercased().contains(needle)
                || ($0.prompt?.lowercased().contains(needle)
                    ?? false)
        }
    }

    private var settingHits: [SettingsCatalogEntry] {
        guard !trimmedQuery.isEmpty else { return [] }
        return SettingsCatalog.search(trimmedQuery)
    }

    private var hasAnyHit: Bool {
        !sessionHits.isEmpty || !fileHits.isEmpty
            || !cronHits.isEmpty || !settingHits.isEmpty
    }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
            } else {
                sessionSection
                fileSection
                cronSection
                settingSection
                if !searching && !hasAnyHit {
                    Text("没有找到和「\(trimmedQuery)」相关的东西。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("全局搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("搜索会话、文件、定时、设置")
        )
        .onChange(of: query) { _, _ in scheduleSearch() }
        .task {
            await cronStore.loadIfNeeded()
            if libraryStore.deliverables == nil {
                _ = await libraryStore.refreshIfNeeded(
                    currentConfigKey: appState.config?.baseString
                ) {
                    guard let config = appState.config else {
                        throw HermesError.sessionExpired
                    }
                    let page = try await bridgeClient.fileLibrary(
                        config: config
                    )
                    return page.items.map {
                        Deliverable(entry: $0.entry, source: $0.source)
                    }
                }
            }
        }
    }

    // MARK: - 结果段

    @ViewBuilder
    private var sessionSection: some View {
        if !sessionHits.isEmpty {
            Section("会话") {
                ForEach(sessionHits) { hit in
                    Button {
                        dismiss()
                        onOpenSearchHit?(hit)
                    } label: {
                        VStack(
                            alignment: .leading,
                            spacing: OneDayMetrics.spacingMicro
                        ) {
                            Text(hit.displayTitle)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if let snippet = hit.snippet,
                               !snippet.isEmpty {
                                Text(snippet)
                                    .font(.footnote)
                                    .foregroundStyle(
                                        Palette.inkSecondary
                                    )
                                    .lineLimit(2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            }
        } else if searching {
            Section("会话") {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在搜会话…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var fileSection: some View {
        if !fileHits.isEmpty {
            Section("文件") {
                ForEach(fileHits, id: \.entry.path) { item in
                    Button {
                        appState.router.fileRevealPath = item.entry.path
                        appState.router.mainTabSwitchRequest = .files
                        dismiss()
                        onCloseHost?()
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            VStack(
                                alignment: .leading,
                                spacing: OneDayMetrics.spacingMicro
                            ) {
                                Text(item.entry.name)
                                    .font(.body)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text(item.entry.path)
                                    .font(.footnote)
                                    .foregroundStyle(
                                        Palette.inkSecondary
                                    )
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            }
        }
    }

    @ViewBuilder
    private var cronSection: some View {
        if !cronHits.isEmpty {
            Section("定时任务") {
                ForEach(cronHits) { job in
                    NavigationLink {
                        CronJobDetailView(job: job) {
                            Task { await cronStore.refresh() }
                        }
                    } label: {
                        VStack(
                            alignment: .leading,
                            spacing: OneDayMetrics.spacingMicro
                        ) {
                            Text(job.title)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text(job.scheduleText)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.odPressable)
                }
            }
        }
    }

    @ViewBuilder
    private var settingSection: some View {
        if !settingHits.isEmpty {
            Section("设置") {
                ForEach(settingHits) { entry in
                    Button {
                        openSetting(entry)
                    } label: {
                        VStack(
                            alignment: .leading,
                            spacing: OneDayMetrics.spacingMicro
                        ) {
                            Text(entry.title)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text(entry.summary)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            }
        }
    }

    // MARK: - 落点

    /// 设置命中：有路由的走设置信箱（关本面→开设置
    /// sheet→直达目标页）；无路由项（电脑/服务器文件
    /// 等 sheet 型）只开设置 sheet 落根页，不假装直达
    private func openSetting(_ entry: SettingsCatalogEntry) {
        if let route = SettingsRoute.from(
            destination: entry.destination
        ) {
            appState.router.pendingSettingsRoute = route
        }
        appState.router.settingsSheetRequested = true
        dismiss()
        onCloseHost?()
    }

    /// 会话搜索：450ms 防抖＋旧任务取消（与全部对话页
    /// runSearch 同口径）
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = trimmedQuery
        guard !query.isEmpty else {
            sessionHits = []
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            if Task.isCancelled { return }
            let hits = try? await appState.performAdmin {
                client, config in
                try await client.searchSessions(
                    config: config, query: query, limit: 50
                )
            }
            if Task.isCancelled { return }
            sessionHits = hits ?? []
            searching = false
        }
    }
}
