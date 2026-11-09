import OneDayCore
import OneDayDesign
import SwiftUI

/// 「全部对话」管理页（0.18.0，旁聊立项档 A.3）：抽屉
/// 「管理全部对话」行进来的全屏页。服务端全量名单
/// （分页拉全）、四段＝主线／站内／外部／已归档、顶
/// 部服务端搜索（吸收 0.16.0 的 /api/sessions/search，
/// 不许两套搜索并存）、行长按四件与抽屉共用同一组件
/// （ServerSessionRow）、多选批量（站内：归档/删除；
/// 已归档：恢复/删除）、清理区（prune 先 dry_run 展
/// 示将删条数、用户确认才真跑）、存量本地覆盖一次
/// 性迁移（首开执行、失败逐项留痕不静默吞）。
/// 纪律：一切写动作经 ServerSessionActions 回读对账
/// 才落 UI，本页不乐观改行数据；主线行钦定保护
/// （无菜单、不可改名/归档/删除）。
struct AllConversationsView: View {
    /// 打开会话（宿主关页＋切聊天格＋走续聊通道）
    var onOpenSession: (String) -> Void
    var onClose: () -> Void

    @Environment(AppState.self) private var appState
    @State private var store = AllConversationsStore()
    @State private var segment: Segment = .station
    @State private var searchText = ""
    @State private var searchResults: [ServerSession] = []
    @State private var searching = false
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var showBatchDeleteConfirm = false
    @State private var showPruneConfirm = false
    @State private var pruneDaysText = "90"
    @State private var migrationStarted = false

    enum Segment: String, CaseIterable {
        case main = "主线"
        case station = "站内"
        case external = "外部"
        case archived = "已归档"
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mainSessionID: String? {
        appState.sideChats.mainServerSessionID
    }

    /// 站内段行：全量减主线，置顶者稳定置顶（服务端
    /// 序为底、pinned 组内保序）
    private var stationSessions: [ServerSession] {
        let rows = store.sessions.filter { $0.id != mainSessionID }
        return rows.filter { $0.isPinned == true }
            + rows.filter { $0.isPinned != true }
    }

    /// 已归档段行：服务端 archived 全量减主线
    private var archivedRows: [ServerSession] {
        store.archivedSessions.filter { $0.id != mainSessionID }
    }

    /// 主线行：全量里找钦定 id，找不到走单查兜底
    private var mainRow: ServerSession? {
        guard let mainSessionID else { return nil }
        return store.sessions.first { $0.id == mainSessionID }
            ?? store.archivedSessions.first { $0.id == mainSessionID }
            ?? store.mainFallback
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("分区", selection: $segment) {
                    ForEach(Segment.allCases, id: \.self) { seg in
                        Text(seg.rawValue).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.vertical, OneDayMetrics.spacingS)
                .disabled(isSearching)
                content
            }
            .background(Palette.canvas)
            .navigationTitle("全部对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { onClose() }
                }
                if segment == .station || segment == .archived {
                    ToolbarItem(placement: .primaryAction) {
                        Button(editMode.isEditing ? "取消选择" : "选择") {
                            withAnimation {
                                editMode = editMode.isEditing
                                    ? .inactive : .active
                            }
                            if !editMode.isEditing {
                                selection.removeAll()
                            }
                        }
                        .disabled(isSearching)
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索全部会话（服务端）"
            )
            .safeAreaInset(edge: .bottom) {
                if editMode.isEditing, !selection.isEmpty {
                    batchBar
                }
            }
        }
        .task {
            await store.load(appState: appState)
            // 存量迁移：首开执行一次（计划为空即无事）；
            // 失败留痕留在 store、页顶呈现，重开本页会
            // 再试（本地值未退役者仍在计划内）
            if !migrationStarted {
                migrationStarted = true
                await store.runMigration(appState: appState)
            }
        }
        .task(id: searchText) {
            await runSearch()
        }
        .alert(
            "删除所选会话？",
            isPresented: $showBatchDeleteConfirm
        ) {
            Button("删除", role: .destructive) { runBatch(.delete) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 \(selection.count) 条会话，删除后不可恢复。")
        }
        .alert(
            "确认清理？",
            isPresented: $showPruneConfirm
        ) {
            Button("清理", role: .destructive) {
                Task { await runPrune(dryRun: false) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                "将删除 \(store.pruneDryRunCount ?? 0) 条超过 "
                    + "\(pruneDaysText) 天的旧会话，删除后不可恢复。"
            )
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        if isSearching {
            searchContent
        } else {
            switch segment {
            case .main: mainContent
            case .station: stationContent
            case .external: externalContent
            case .archived: archivedContent
            }
        }
    }

    private var searchContent: some View {
        List {
            if searching {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("搜索中…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                }
            } else if searchResults.isEmpty {
                Text("服务端没有匹配的会话。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ForEach(searchResults) { session in
                    if session.id == mainSessionID {
                        mainRowButton(session)
                    } else {
                        ServerSessionRow(
                            session: session,
                            title: rowTitle(session),
                            onOpen: { onOpenSession(session.id) },
                            onChanged: {
                                Task { await store.load(appState: appState) }
                            }
                        ) {
                            rowLabel(session)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var mainContent: some View {
        List {
            Section {
                if let mainRow {
                    mainRowButton(mainRow)
                } else if store.isLoading {
                    Text("正在读取…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                } else {
                    Text("主线还没有绑定服务端会话（在聊天页发一条消息后会出现）。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                }
            } footer: {
                Text("主线是你的唯一指挥席：受钦定保护，本页不提供改名、归档与删除。")
            }
            migrationSection
            noticeSection
        }
        .listStyle(.plain)
        .refreshable { await store.load(appState: appState) }
    }

    private var stationContent: some View {
        List(selection: $selection) {
            migrationSection
            noticeSection
            if store.isLoading, store.sessions.isEmpty {
                Text("正在读取…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            } else if let error = store.loadError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            } else if stationSessions.isEmpty {
                Text("站内还没有会话。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ForEach(stationSessions) { session in
                    selectableRow(session)
                }
            }
            cleanupSection
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .refreshable { await store.load(appState: appState) }
    }

    private var externalContent: some View {
        List {
            migrationSection
            noticeSection
            Section {
                EmptyState(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "通道未开通",
                    message: "外部旁聊要等首个通道接通后才有内容；届时分身在外面的对话会出现在这里，只向主线汇报。"
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private var archivedContent: some View {
        List(selection: $selection) {
            migrationSection
            noticeSection
            if store.isLoading, store.archivedSessions.isEmpty {
                Text("正在读取…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            } else if archivedRows.isEmpty {
                Text("没有已归档的会话。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ForEach(archivedRows) { session in
                    selectableRow(session)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .refreshable { await store.load(appState: appState) }
    }

    // MARK: - 行与小区

    /// 可多选行：编辑态走 List 原生勾选（纯标签、无
    /// 按钮菜单），常态走共用组件（点按打开＋长按四
    /// 件）；两态同标题同副题
    @ViewBuilder
    private func selectableRow(_ session: ServerSession) -> some View {
        if editMode.isEditing {
            rowLabel(session)
                .tag(session.id)
        } else {
            ServerSessionRow(
                session: session,
                title: rowTitle(session),
                onOpen: { onOpenSession(session.id) },
                onChanged: { Task { await store.load(appState: appState) } }
            ) {
                rowLabel(session)
            }
            .tag(session.id)
        }
    }

    /// 主线行（钦定保护）：纯打开按钮、无长按菜单
    private func mainRowButton(_ session: ServerSession) -> some View {
        Button {
            onOpenSession(session.id)
        } label: {
            rowLabel(session)
        }
        .buttonStyle(.odPressable)
    }

    /// 行面：标题（统一管线）＋置顶标＋人话副题
    private func rowLabel(_ session: ServerSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(rowTitle(session))
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if session.isPinned == true {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            Text(session.humanSubtitle(now: Date()))
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 行标题：与抽屉同口径——存量本地覆盖（迁移未
    /// 完前）优先，其后统一管线 resolvedTitle
    private func rowTitle(_ session: ServerSession) -> String {
        appState.sideChats.titleOverrides[session.id]
            ?? appState.sessionTitles.title(for: session)
    }

    /// 迁移留痕区：有失败项才出现，逐项人话（哪条、
    /// 哪件、为什么没落定）＋本地值保留的说明
    @ViewBuilder
    private var migrationSection: some View {
        if !store.migrationFailures.isEmpty {
            Section("存量迁移未完成") {
                ForEach(
                    Array(store.migrationFailures.enumerated()),
                    id: \.offset
                ) { _, line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text("未落定的项本地值仍保留，下次打开本页会再试。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    /// 操作结果人话条（批量/清理的落定汇总）
    @ViewBuilder
    private var noticeSection: some View {
        if let notice = store.notice {
            Section {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    /// 清理区（站内段底部）：prune 两段式——先
    /// dry_run 展示将删条数、确认后才真跑；施工期与
    /// 真机同规：真跑只发生在用户在本页点「清理」后
    private var cleanupSection: some View {
        Section("清理旧会话") {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text("删除超过")
                TextField("天数", text: $pruneDaysText)
                    .keyboardType(.numberPad)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                Text("天的会话")
                Spacer()
                Button("预演") {
                    Task { await runPrune(dryRun: true) }
                }
            }
            .font(.body)
            Text("先预演看将删条数，确认后才会真删；真删不可恢复。")
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    /// 批量操作栏（编辑态且有选中时挂底）
    private var batchBar: some View {
        HStack(spacing: OneDayMetrics.spacingM) {
            Text("已选 \(selection.count) 条")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            if segment == .archived {
                Button("恢复") { runBatch(.restore) }
            } else {
                Button("归档") { runBatch(.archive) }
            }
            Button("删除", role: .destructive) {
                showBatchDeleteConfirm = true
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(Palette.canvas)
    }

    // MARK: - 动作

    private enum BatchKind { case archive, restore, delete }

    /// 批量：逐条经动作层（PATCH/DELETE＋回读对账），
    /// 未落定逐条计数、汇总人话呈现，不许整批乐观
    private func runBatch(_ kind: BatchKind) {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        Task {
            var failedCount = 0
            for id in ids {
                let outcome: ServerSessionActions.Outcome
                switch kind {
                case .archive:
                    outcome = await ServerSessionActions.setArchived(
                        appState: appState, id: id, archived: true
                    )
                case .restore:
                    outcome = await ServerSessionActions.setArchived(
                        appState: appState, id: id, archived: false
                    )
                case .delete:
                    outcome = await ServerSessionActions.delete(
                        appState: appState, id: id
                    )
                }
                if outcome != .verified { failedCount += 1 }
            }
            selection.removeAll()
            editMode = .inactive
            store.notice = failedCount == 0
                ? "已处理 \(ids.count) 条，全部回读落定。"
                : "\(ids.count - failedCount) 条已落定，\(failedCount) 条未落定——名单已按服务端现状刷新，请核对。"
            await store.load(appState: appState)
        }
    }

    /// 清理两段：dryRun 只取将删条数（取不到数不许
    /// 进入确认、更不许真跑）；真跑后回执条数入结果
    /// 条、名单重拉对账
    private func runPrune(dryRun: Bool) async {
        guard let days = Int(pruneDaysText), days > 0 else {
            store.notice = "天数要填正整数。"
            return
        }
        do {
            let receipt = try await appState.performAdmin { client, config in
                try await client.pruneSessions(
                    config: config, olderThanDays: days, dryRun: dryRun
                )
            }
            if dryRun {
                guard let count = receipt.count else {
                    store.notice = "服务端这次没回将删条数，无法预演——为稳妥起见没有执行清理。"
                    return
                }
                store.pruneDryRunCount = count
                showPruneConfirm = true
            } else {
                store.pruneDryRunCount = nil
                store.notice = receipt.count.map {
                    "已清理 \($0) 条旧会话。"
                } ?? "清理已执行（服务端未回条数，以刷新后的名单为准）。"
                await store.load(appState: appState)
            }
        } catch {
            store.notice = (error as? HermesError)?.userMessage
                ?? "清理没完成，请稍后再试。"
        }
    }

    /// 服务端搜索（与 0.16.0 会话搜索同一端点的管理
    /// 页呈现——搜索面收敛到本页一处）：450ms 防抖、
    /// 旧任务取消口径同 ServerSessionsViews
    private func runSearch() async {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            searchResults = []
            searching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        if Task.isCancelled { return }
        searching = true
        defer { searching = false }
        if let hits = try? await appState.performAdmin({ client, config in
            try await client.searchSessions(
                config: config, query: query, limit: 50
            )
        }) {
            searchResults = hits
        }
    }
}

/// 管理页数据层（0.18.0）：全量分页拉取＋主线兜底
/// 单查＋存量迁移执行与留痕。
@MainActor
@Observable
final class AllConversationsStore {
    /// 可见全量（archived=exclude 分页拉全）
    var sessions: [ServerSession] = []
    /// 已归档全量（archived=only 分页拉全）
    var archivedSessions: [ServerSession] = []
    /// 主线行兜底：分页没拉到钦定 id 时的单查结果
    var mainFallback: ServerSession?
    var isLoading = false
    var loadError: String?
    /// 批量/清理结果人话条
    var notice: String?
    /// 迁移失败留痕（逐项人话行）
    var migrationFailures: [String] = []
    /// prune 预演回的将删条数（确认弹窗文案用）
    var pruneDryRunCount: Int?

    func load(appState: AppState) async {
        isLoading = true
        loadError = nil
        do {
            let visible = try await Self.fetchAll(
                appState: appState, archived: "exclude"
            )
            let archived = try await Self.fetchAll(
                appState: appState, archived: "only"
            )
            sessions = visible
            archivedSessions = archived
            if let mainID = appState.sideChats.mainServerSessionID,
               !visible.contains(where: { $0.id == mainID }),
               !archived.contains(where: { $0.id == mainID }) {
                mainFallback = try? await appState.performAdmin {
                    client, config in
                    try await client.serverSession(
                        config: config, id: mainID
                    )
                }
            } else {
                mainFallback = nil
            }
            // 标题回落素材：无服务端标题者才拉消息派生
            await appState.sessionTitles.ensureTitles(
                for: visible + archived, appState: appState, budget: 12
            )
        } catch {
            loadError = (error as? HermesError)?.userMessage
                ?? "名单没拉下来，请稍后再试。"
        }
        isLoading = false
    }

    /// 分页拉全：limit 100 逐页至不足一页或达 total，
    /// 上限 10 页（防服务端分页异常时无界拉取）
    private static func fetchAll(
        appState: AppState, archived: String
    ) async throws -> [ServerSession] {
        try await appState.performAdmin { client, config in
            var all: [ServerSession] = []
            var offset = 0
            for _ in 0..<10 {
                let page = try await client.serverSessionsPage(
                    config: config, limit: 100,
                    offset: offset, archived: archived
                )
                all.append(contentsOf: page.sessions)
                if page.sessions.count < 100 { break }
                if let total = page.total, all.count >= total { break }
                offset += 100
            }
            return all
        }
    }

    /// 存量迁移执行（管理页首开）：计划走 Core 纯函数
    /// （SessionMigration.plan），逐项经动作层回写＋
    /// 回读对账；折叠后成功项清本地（覆盖表删项、归
    /// 档键删项），失败项逐项留痕＋本地值保留。迁移
    /// 后名单重拉（归档项的服务端状态已变）
    func runMigration(appState: AppState) async {
        let sideChats = appState.sideChats
        let overrides = sideChats.titleOverrides
        let keys = sideChats.archivedKeys
        let plan = SessionMigration.plan(
            titleOverrides: overrides, archivedKeys: keys
        )
        guard !plan.isEmpty else { return }
        var failureReasons: [SessionMigration.Item: String] = [:]
        for item in plan {
            let outcome: ServerSessionActions.Outcome
            switch item.kind {
            case .rename(let title):
                outcome = await ServerSessionActions.rename(
                    appState: appState, id: item.sessionID, title: title
                )
            case .archive:
                outcome = await ServerSessionActions.setArchived(
                    appState: appState, id: item.sessionID, archived: true
                )
            }
            if case .failed(let reason) = outcome {
                failureReasons[item] = reason
            }
        }
        let outcome = SessionMigration.fold(
            plan: plan, failureReasons: failureReasons,
            titleOverrides: overrides, archivedKeys: keys
        )
        // 退役成功项：本地只删「计划内且已落定」的键
        for id in overrides.keys
        where outcome.remainingTitleOverrides[id] == nil {
            sideChats.setTitleOverride(nil, for: id)
        }
        for key in keys
        where !outcome.remainingArchivedKeys.contains(key) {
            sideChats.unarchive(key: key)
        }
        migrationFailures = outcome.failures.map { failure in
            "「\(failure.item.sessionID)」\(failure.item.actionLabel)未落定：\(failure.reason)"
        }
        await load(appState: appState)
    }
}
