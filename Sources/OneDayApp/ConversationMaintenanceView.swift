import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 会话维护子页（结构归位第二批，2026-11-20，纲要
/// D2-2/D2-3）：全部对话页的维护层——自浏览页同
/// 层下沉一层（浏览页工具栏「维护」推入）。承载
/// 四件，全部自 AllConversationsView 原样随迁、
/// 行为与确认口径一字不变：①系统运行（内部会话
/// 全量行，不再与用户段同级——原「系统」段＋
/// 「显示系统运行」筛选开关退役）②批量管理（我
/// 的对话／已归档两组的多选归档/恢复/删除）③清
/// 理旧会话（prune 预演＋确认真删）④存量迁移留
/// 痕与操作结果人话条。台账 199（2026-11-21）
/// 补第五件：空会话清理（§241）自设置旧名单页
/// 随迁入本页（旧页已删），计数显隐与审计留痕
/// 口径不变。数据口径与浏览页同源：
/// 账本投影＋Core SessionClassifier 现算，名单
/// 重拉走同口径 reload（§223）。
/// 终局归属备忘：纲要原文把系统段指向「会话管
/// 理维护区」、批量与清理指向「服务器管理维护
/// 段」——两张枢纽页已随结构归位第一批撤销，本
/// 子页即现行维护之家；后续若再并入设置服务器
/// 组维护尾段，迁挂载点即可、四件本体不动
struct ConversationMaintenanceView: View {
    /// 与浏览页共享的 UI 态店（notice/prune 预演
    /// 数两页同源，批量/清理结果条在本页落点呈现）
    let store: AllConversationsStore
    /// 打开会话（宿主关页＋切聊天格＋走续聊通道，
    /// 与浏览页同一回调）
    var onOpenSession: (String) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    // 动效口径与浏览页同：动画走令牌＋resolved 出口
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 本地线程全集（分类关联集派生用，与浏览页
    /// 同一 ThreadLinkage 派生）
    @Query private var threads: [ChatThread]
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var showBatchDeleteConfirm = false
    @State private var showBatchArchiveConfirm = false
    @State private var showPruneConfirm = false
    @State private var pruneDaysText = "90"
    /// 空会话清理（台账 199 自设置旧名单页随迁）：
    /// 服务端空会话计数（reload 同拍拉取）与清理面
    /// 呈现旗
    @State private var emptyCount = 0
    @State private var showEmptyCleanup = false

    private var mainSessionID: String? {
        appState.sessionLedger.mainServerSessionID
    }

    /// 账本名单（与浏览页同一输入：账本投影）
    private var ledgerVisibleSessions: [ServerSession] {
        appState.sessionLedger.managementVisible(
            appState: appState, localThreads: threads
        )
    }

    private var ledgerArchivedSessions: [ServerSession] {
        appState.sessionLedger.managementArchived(
            appState: appState, localThreads: threads
        )
    }

    private var partition: SessionPartition {
        SessionClassifier.partition(
            sessions: ledgerVisibleSessions,
            mainServerSessionID: mainSessionID,
            linkedThreadSessionIDs: ThreadLinkage.nonMainLinkedSessionIDs(
                threads: threads, ledger: appState.sessionLedger
            )
        )
    }

    /// 我的对话行（与浏览页同派生：置顶者稳定置顶）
    private var mineRows: [ServerSession] {
        let rows = partition.mine
        return rows.filter { $0.isPinned == true }
            + rows.filter { $0.isPinned != true }
    }

    /// 系统运行行：分类为系统运行的全量行（服务端序）
    private var systemRows: [ServerSession] {
        partition.system
    }

    /// 已归档行：服务端 archived 全量减主线（与浏
    /// 览页同口径）
    private var archivedRows: [ServerSession] {
        ledgerArchivedSessions.filter {
            !SideChatClassifier.isMain(
                serverSessionID: $0.id,
                mainServerSessionID: mainSessionID
            )
        }
    }

    private var archivedIDSet: Set<String> {
        Set(archivedRows.map(\.id))
    }

    /// 选中集里的未归档/已归档分流（批量栏与批量
    /// 动作的归属判定：归档只作用于未归档选中、恢
    /// 复只作用于已归档选中）
    private var selectedActiveIDs: [String] {
        selection.filter { !archivedIDSet.contains($0) }
    }

    private var selectedArchivedIDs: [String] {
        selection.filter { archivedIDSet.contains($0) }
    }

    /// 0.27.0：批量选择里是否含已判死的合并桶——含
    /// 则归档/删除确认必须带牵连主线历史的说明（与
    /// 单行菜单同一道闸，见 ServerSessionRow）
    private var selectionHasMergeBucket: Bool {
        selection.contains { SideChatLink.isMergeBucket($0) }
    }

    var body: some View {
        List(selection: $selection) {
            migrationSection
            noticeSection
            Section("我的对话") {
                rowsOrStatus(
                    mineRows,
                    emptyText: "没有可管理的对话。"
                )
            }
            Section("已归档") {
                rowsOrStatus(
                    archivedRows,
                    emptyText: "没有已归档的会话。"
                )
            }
            Section("系统运行") {
                rowsOrStatus(
                    systemRows,
                    emptyText: "没有系统运行记录。"
                )
            }
            cleanupSection
            emptyCleanupSection
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .navigationTitle("会话维护")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editMode.isEditing ? "取消选择" : "选择") {
                    // 动效收编 swap 令牌＋resolved 出
                    // 口（与浏览页旧「选择」钮同式）
                    withAnimation(
                        MotionTokens.resolved(
                            MotionTokens.swap,
                            reduceMotion: reduceMotion
                        )
                    ) {
                        editMode = editMode.isEditing
                            ? .inactive : .active
                    }
                    if !editMode.isEditing {
                        selection.removeAll()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode.isEditing, !selection.isEmpty {
                batchBar
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showEmptyCleanup) {
            EmptyCleanupSheet {
                Task { await reload() }
            }
        }
        .alert(
            "删除所选会话？",
            isPresented: $showBatchDeleteConfirm
        ) {
            Button("删除", role: .destructive) {
                // 触感矩阵（表 D）：删除确认落锤＝
                // impact heavy；删除后不再叠 success
                // （同一因果链只震一次）
                Haptics.impact(.heavy)
                runBatch(.delete)
            }
            Button("取消", role: .cancel) {}
        } message: {
            if selectionHasMergeBucket {
                Text(SideChatLink.mergeBucketWarning)
            } else {
                Text("将删除 \(selection.count) 条会话，删除后不可恢复。")
            }
        }
        .alert(
            "归档所选会话？",
            isPresented: $showBatchArchiveConfirm
        ) {
            Button("归档", role: .destructive) { runBatch(.archive) }
            Button("取消", role: .cancel) {}
        } message: {
            Text(SideChatLink.mergeBucketWarning)
        }
        .alert(
            "确认清理？",
            isPresented: $showPruneConfirm
        ) {
            Button("清理", role: .destructive) {
                // 清理即批量删除旧会话，同属删除确认
                // 落锤口径（表 D）
                Haptics.impact(.heavy)
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

    // MARK: - 行与小区

    /// 一组行或状态行：加载/错误优先（与浏览页各
    /// 段同形态），空组给弱字一行、不留空白段
    @ViewBuilder
    private func rowsOrStatus(
        _ rows: [ServerSession], emptyText: String
    ) -> some View {
        if store.isLoading, ledgerVisibleSessions.isEmpty,
           ledgerArchivedSessions.isEmpty {
            Text("正在读取…")
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
        } else if let error = store.loadError {
            Text(error)
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
        } else if rows.isEmpty {
            Text(emptyText)
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
        } else {
            ForEach(rows) { session in
                selectableRow(session)
            }
        }
    }

    /// 可多选行：编辑态走 List 原生勾选（纯标签、无
    /// 按钮菜单），常态走共用组件（点按打开＋长按四
    /// 件）；两态同标题同副题（自浏览页原样随迁）
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
                onChanged: { Task { await reload() } },
                onDeleteRequested: { session in
                    // §232 乐观删除：确认即同拍摘自家
                    // 名单行＋协调器起手（墓碑/目录摘
                    // 行/后台删）；最终失败由协调器恢
                    // 复，恢复信号触发本页重拉对齐
                    appState.sessionLedger.removeSession(sessionID: session.id)
                    appState.sessionDeletions.begin(
                        sessionID: session.id,
                        title: rowTitle(session),
                        appState: appState,
                        modelContext: modelContext
                    )
                }
            ) {
                rowLabel(session)
            }
            .tag(session.id)
        }
    }

    /// 行面：标题（统一管线）＋置顶标＋人话副题
    /// （与浏览页 rowLabel 同式，两页行面不许分叉）
    private func rowLabel(_ session: ServerSession) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
            HStack(spacing: OneDayMetrics.rowInnerGap) {
                Text(rowTitle(session))
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                    // 0.43.0（A11Y-D3）：AX 档放宽行数
                    .a11yLineLimit(1, ax: 2)
                if session.isPinned == true {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            Text(session.humanSubtitle(now: Date()))
                .font(.meta)
                .foregroundStyle(Palette.inkSecondary)
                // 0.43.0（A11Y-D3）：AX 档放宽行数
                .a11yLineLimit(1, ax: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 行标题：与浏览页/抽屉同口径，经账本标题读点
    private func rowTitle(_ session: ServerSession) -> String {
        appState.sessionLedger.title(
            for: session, appState: appState
        )
    }

    /// 迁移留痕区：有失败项才出现，逐项人话（哪条、
    /// 哪件、为什么没落定）＋本地值保留的说明（自
    /// 浏览页原样随迁）
    @ViewBuilder
    private var migrationSection: some View {
        if !appState.sessionLedger.migrationFailures.isEmpty {
            Section("存量迁移未完成") {
                ForEach(
                    Array(appState.sessionLedger.migrationFailures.enumerated()),
                    id: \.offset
                ) { _, line in
                    Text(line)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text("没改成的项先按你改的样子显示，下次打开本页刷新名单时会自动再试。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    /// 操作结果人话条（批量/清理的落定汇总）
    @ViewBuilder
    private var noticeSection: some View {
        if let notice = store.notice {
            Section {
                Text(notice)
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    /// 清理区（自旧系统段底部随迁——清理是全服按天
    /// 数执行、主要清的就是系统与频道存量）：prune
    /// 两段式——先 dry_run 展示将删条数、确认后才
    /// 真跑；真跑只发生在用户在本页点「清理」后
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
            .font(.bodyText)
            Text("先预演看将删条数，确认后才会真删；真删不可恢复。")
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    /// 空会话清理区（台账 199 自设置旧名单页随迁，
    /// §241）：计数 >0 才出现（与旧页同显隐）；进
    /// 面走 EmptyCleanupSheet——dry-run 预览＋围栏
    /// 单删＋删后核验＋审计留痕，本体与确认口径一
    /// 字不变；上次清理留痕一行随迁（审计记录在本
    /// 机，清理面里有完整清单与核验结果）
    @ViewBuilder
    private var emptyCleanupSection: some View {
        if emptyCount > 0 {
            Section("空会话清理") {
                Button {
                    showEmptyCleanup = true
                } label: {
                    HStack {
                        Text("清理空会话")
                            .font(.bodyText)
                            .foregroundStyle(Palette.danger)
                        Spacer()
                        Text("\(emptyCount) 条")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                if let last = EmptyCleanupAuditStore.latestFinished {
                    Text("上次清理：\(last.plannedAt.prefix(10)) · 删除 \(last.deletedIDs.count) 条 · 核验消失 \(last.verifiedGoneIDs?.count ?? 0) 条")
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    /// 批量操作栏（编辑态且有选中时挂底）：按钮按
    /// 选中归属出——含未归档选中才有「归档」、含
    /// 已归档选中才有「恢复」、「删除」恒有（原分
    /// 段页里选择集恒属单一段、本式与旧呈现等价，
    /// 且容跨组混选）
    private var batchBar: some View {
        HStack(spacing: OneDayMetrics.spacingM) {
            Text("已选 \(selection.count) 条")
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            if !selectedActiveIDs.isEmpty {
                Button("归档") {
                    // 0.27.0：选含合并桶时先过二次确认
                    if selectionHasMergeBucket {
                        showBatchArchiveConfirm = true
                    } else {
                        runBatch(.archive)
                    }
                }
            }
            if !selectedArchivedIDs.isEmpty {
                Button("恢复") { runBatch(.restore) }
            }
            Button("删除", role: .destructive) {
                showBatchDeleteConfirm = true
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(Palette.pageBG)
    }

    // MARK: - 动作

    /// 名单重拉唯一口（§223，与浏览页同口径）：触
    /// 发账本 refresh＋对账，本页所有重拉点统一走
    /// 此口；空会话计数同拍拉取（台账 199 随迁，
    /// 取不到数保留旧值、不假报）
    private func reload() async {
        await store.load(
            appState: appState, localThreads: threads,
            modelContext: modelContext
        )
        if let count = try? await appState.performAdmin({ client, config in
            try await client.emptySessionCount(config: config)
        }) {
            emptyCount = count
        }
    }

    private enum BatchKind { case archive, restore, delete }

    /// 批量：归档/恢复逐条经动作层（PATCH＋回读对
    /// 账），未落定逐条计数、汇总人话呈现。删除自
    /// §232 起不走本路——乐观删除专路（下方入口分
    /// 流）：逐条本地先删、后台逐条删，成败不汇总
    /// （最终失败由协调器逐条恢复＋提醒）。归档/
    /// 恢复按选中归属分流（见 selectedActiveIDs
    /// 注）——原分段页选择集恒属单一段，分流后行
    /// 为与旧口径等价
    private func runBatch(_ kind: BatchKind) {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        if kind == .delete {
            for id in ids {
                let title = (ledgerVisibleSessions + ledgerArchivedSessions)
                    .first { $0.id == id }.map { rowTitle($0) } ?? ""
                appState.sessionLedger.removeSession(sessionID: id)
                appState.sessionDeletions.begin(
                    sessionID: id, title: title,
                    appState: appState, modelContext: modelContext
                )
            }
            selection.removeAll()
            editMode = .inactive
            return
        }
        let targets = kind == .archive
            ? selectedActiveIDs : selectedArchivedIDs
        guard !targets.isEmpty else {
            selection.removeAll()
            editMode = .inactive
            return
        }
        Task {
            var failedCount = 0
            for id in targets {
                let outcome = await ServerSessionActions.setArchived(
                    appState: appState, id: id,
                    archived: kind == .archive
                )
                if outcome != .verified {
                    failedCount += 1
                }
            }
            selection.removeAll()
            editMode = .inactive
            store.notice = failedCount == 0
                ? "已处理 \(targets.count) 条，全部确认完成。"
                : "\(targets.count - failedCount) 条已改好，\(failedCount) 条没改成——列表已按服务器现状刷新，你核对一下。"
            await reload()
        }
    }

    /// 清理两段：dryRun 只取将删条数（取不到数不许
    /// 进入确认、更不许真跑）；真跑后回执条数入结果
    /// 条、名单重拉对账（自浏览页原样随迁）
    private func runPrune(dryRun: Bool) async {
        guard let days = Int(pruneDaysText), days > 0 else {
            store.notice = "天数要填正整数。"
            return
        }
        do {
            // 回执条数由客户端多键宽容提取（SessionPrune-
            // Receipt）：取不到为 nil、如实呈现不编数
            let count = try await appState.performAdmin { client, config in
                try await client.pruneSessions(
                    config: config,
                    olderThanDays: Double(days), dryRun: dryRun
                )
            }
            if dryRun {
                guard let count else {
                    store.notice = "服务端这次没回将删条数，无法预演——为稳妥起见没有执行清理。"
                    return
                }
                store.pruneDryRunCount = count
                showPruneConfirm = true
            } else {
                store.pruneDryRunCount = nil
                store.notice = count.map {
                    "已清理 \($0) 条旧会话。"
                } ?? "清理已执行（服务端未回条数，以刷新后的名单为准）。"
                await reload()
            }
        } catch {
            store.notice = (error as? HermesError)?.userMessage
                ?? "清理没完成，请稍后再试。"
        }
    }
}
