import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 「全部对话」页（0.18.0，旁聊立项档 A.3）：全屏
/// 页。入口沿革：0.18.0 起自抽屉「管理全部对话」
/// 行；管理收口包补件起改自设置页「全部对话」行
/// （用户 2026-11-13 18:57 拍板挪进设置页），呈现
/// 路（ContentView 根级 fullScreenCover）与本页功
/// 能五项自始至终未变。服务端全量名单
/// （分页拉全）、顶部服务端搜索（吸收 0.16.0 的
/// /api/sessions/search，不许两套搜索并存）、行长
/// 按四件与抽屉共用同一组件（ServerSessionRow）、
/// 多选批量（归档/删除；已归档：恢复/删除）、清理
/// 区（prune 先 dry_run 展示将删条数、用户确认才真
/// 跑）、存量本地覆盖一次性迁移（首开执行、失败逐
/// 项留痕不静默吞）。
/// 纪律：一切写动作经 ServerSessionActions 回读对账
/// 才落 UI，本页不乐观改行数据；主线行钦定保护
/// （无菜单、不可改名/归档/删除）。
/// 0.36.29（频道规格 §5，方案 A）：分段按三层分类
/// 换代——旧「站内」（全量减主线、不分来源一筐）与
/// 「外部」（写死空态）退役；新段＝主线／我的对话
/// （分类 R2/R3）／频道（频道总览，Hermes 行带全量
/// 计数）／已归档（全量口径不变），另有默认关闭、
/// 不落盘的「显示系统运行」筛选开出第五段「系统」
/// （分类 R4/R5＋清理区）。默认落地段改「我的对
/// 话」。分类全走 Core SessionClassifier 现算，各
/// 段不许再自拼「全量减主线」口径。
struct AllConversationsView: View {
    /// 打开会话（宿主关页＋切聊天格＋走续聊通道）
    var onOpenSession: (String) -> Void
    var onClose: () -> Void

    @Environment(AppState.self) private var appState
    // 0.25.0（动效专包）：本面动画走令牌＋resolved 出口
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 「会话」Rotor 命名空间（0.43.0，A11Y-V7）：
    /// 长列表里按标题直达任意一行——条目集随当前
    /// 段/搜索态现算（rotorTargets），行标记挂在
    /// 各行分发处（selectableRow/mainRowButton/搜索
    /// 命中行），id 与条目一一对位
    @Namespace private var rotorNamespace
    /// 本地线程全集（分类 R2 的关联集派生用，与抽屉
    /// /频道页同一 ThreadLinkage 派生）
    @Query private var threads: [ChatThread]
    /// 本地写上下文（§223 删除收口与名单对账清线
    /// 程用）
    @Environment(\.modelContext) private var modelContext
    @State private var store = AllConversationsStore()
    @State private var segment: Segment = .mine
    /// 「显示系统运行」筛选（0.36.29，规格 §5.2）：
    /// 默认关、只存 @State **不落盘**——每次进页默
    /// 认关是纪律，落盘会让开过一次的人默认变开
    @State private var showSystemRuns = false
    /// 频道段 Hermes 行的频道页呈现（本页内 full-
    /// ScreenCover，与抽屉入口同目的地同组件）
    @State private var showHermesChannel = false
    /// 平台频道页呈现（2026-11-13 频道一期）：频道
    /// 段里有成员的平台行置位，目的地与抽屉入口同
    /// 一 ChannelEntryView，不许两套平台频道页
    @State private var presentedPlatformChannel: ChannelDescriptor?
    @State private var searchText = ""
    @State private var searchResults: [SessionSearchHit] = []
    @State private var searching = false
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var showBatchDeleteConfirm = false
    @State private var showBatchArchiveConfirm = false
    @State private var showPruneConfirm = false
    @State private var pruneDaysText = "90"
    @State private var migrationStarted = false

    enum Segment: String {
        case main = "主线"
        case mine = "我的对话"
        case channels = "频道"
        case archived = "已归档"
        case system = "系统"
    }

    /// 呈现段集（§5.2）：「系统」段只在筛选开启时挂
    /// 进分段控件末位，关闭即消失（正处该段则由
    /// showSystemRuns 的 onChange 回落「我的对话」）
    private var visibleSegments: [Segment] {
        var segments: [Segment] = [.main, .mine, .channels, .archived]
        if showSystemRuns {
            segments.append(.system)
        }
        return segments
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mainSessionID: String? {
        appState.sideChats.mainServerSessionID
    }

    /// 0.27.0：批量选择里是否含已判死的合并桶——含
    /// 则归档/删除确认必须带牵连主线历史的说明（与
    /// 单行菜单同一道闸，见 ServerSessionRow）
    private var selectionHasMergeBucket: Bool {
        selection.contains { SideChatLink.isMergeBucket($0) }
    }

    /// 未归档全量的分类分筐（0.36.29）：各段行源的
    /// 唯一出处——旧「全量减主线」口径（stationSes-
    /// sions）退役，分类走 Core SessionClassifier
    /// 现算（主线/合并桶/我的对话/系统/频道一筐出）
    private var partition: SessionPartition {
        SessionClassifier.partition(
            sessions: store.sessions,
            mainServerSessionID: mainSessionID,
            linkedThreadSessionIDs: ThreadLinkage.nonMainLinkedSessionIDs(
                threads: threads, sideChats: appState.sideChats
            )
        )
    }

    /// 我的对话段行：分类为我的对话层（R2 关联行＋
    /// R3 前缀行，主线除外），置顶者稳定置顶（服务
    /// 端序为底、pinned 组内保序，沿旧站内段行序口径）
    private var mineRows: [ServerSession] {
        let rows = partition.mine
        return rows.filter { $0.isPinned == true }
            + rows.filter { $0.isPinned != true }
    }

    /// 系统段行：分类为系统运行的全量行（服务端序）
    private var systemRows: [ServerSession] {
        partition.system
    }

    /// 已归档段行：服务端 archived 全量减主线（归档
    /// 是正交维度、全量呈现不按层分类，规格 §2/§5.1；
    /// 主线剔除走 Core 单一判定）
    private var archivedRows: [ServerSession] {
        store.archivedSessions.filter {
            !SideChatClassifier.isMain(
                serverSessionID: $0.id,
                mainServerSessionID: mainSessionID
            )
        }
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
                    ForEach(visibleSegments, id: \.self) { seg in
                        Text(seg.rawValue).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.vertical, OneDayMetrics.spacingS)
                .disabled(isSearching)
                // 0.36.29（规格 §5.2）：分段控件下方一
                // 行系统筛选——默认关、不落盘；开启后
                // 分段末位多出「系统」一段
                if !isSearching {
                    Toggle("显示系统运行", isOn: $showSystemRuns)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.bottom, OneDayMetrics.spacingS)
                }
                content
            }
            .background(Palette.pageBG)
            .navigationTitle("全部对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { onClose() }
                }
                if segment == .mine || segment == .archived
                    || segment == .system {
                    ToolbarItem(placement: .primaryAction) {
                        Button(editMode.isEditing ? "取消选择" : "选择") {
                            // 0.25.0（动效专包）：原裸
                            // withAnimation（隐式 .default）——
                            // 收编 swap 令牌＋resolved 出口
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
            await reload()
            // 存量迁移：首开执行一次（计划为空即无事）；
            // 失败留痕留在 store、页顶呈现，重开本页会
            // 再试（本地值未退役者仍在计划内）
            if !migrationStarted {
                migrationStarted = true
                await store.runMigration(
                    appState: appState, localThreads: threads,
                    modelContext: modelContext
                )
            }
        }
        .task(id: searchText) {
            await runSearch()
        }
        // 0.36.29：筛选关掉而正处系统段时回落「我的
        // 对话」（段集随开关动态增减，§5.2）
        .onChange(of: showSystemRuns) { _, on in
            if !on, segment == .system {
                segment = .mine
            }
        }
        // 0.36.29：频道段 Hermes 行的频道页（本页内呈
        // 现，与抽屉入口同一 HermesChannelView）；页
        // 内打开会话先关频道页、再走宿主既有续聊通道
        // （频道标记由频道页点行时已置位）
        .fullScreenCover(isPresented: $showHermesChannel) {
            HermesChannelView(
                onOpenSession: { id in
                    showHermesChannel = false
                    onOpenSession(id)
                },
                onClose: { showHermesChannel = false }
            )
        }
        // 2026-11-13 频道一期：平台频道行（频道段）
        // 的入口分发器，与抽屉入口同一目的地
        .fullScreenCover(item: $presentedPlatformChannel) { descriptor in
            ChannelEntryView(
                channel: descriptor,
                onOpenSession: { id in
                    presentedPlatformChannel = nil
                    onOpenSession(id)
                },
                onClose: { presentedPlatformChannel = nil }
            )
        }
        .alert(
            "删除所选会话？",
            isPresented: $showBatchDeleteConfirm
        ) {
            Button("删除", role: .destructive) {
                // 触感矩阵（表 D）：删除确认落锤＝
                // impact heavy；删除后不再叠 success
                // （同一因果链只震一次）。与文件/交
                // 付物/图片/富内容四面同式——本面批
                // 量删除此前独缺，本包补齐
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
                // 落锤口径（表 D），与上方批量删除同式
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

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        Group {
            if isSearching {
                searchContent
            } else {
                switch segment {
                case .main: mainContent
                case .mine: mineContent
                case .channels: channelsContent
                case .archived: archivedContent
                case .system: systemContent
                }
            }
        }
        // 0.43.0（A11Y-V7）：「会话」Rotor——VO 转子
        // 里按标题字母/浏览直达长列表任意一行（条
        // 目与行标记同 id 对位，见 rotorTargets）
        .accessibilityRotor(L10n.string("会话")) {
            ForEach(rotorTargets) { target in
                AccessibilityRotorEntry(
                    target.title, target.id, in: rotorNamespace
                )
            }
        }
    }

    /// Rotor 条目（当前可见行集）：搜索态＝命中行、
    /// 否则当前段的行集；标题与行面同源（rowTitle/
    /// 命中标题），频道段是总览行、不入转子
    private struct RotorTarget: Identifiable {
        let id: String
        let title: String
    }

    private var rotorTargets: [RotorTarget] {
        if isSearching {
            return searchResults.map {
                RotorTarget(id: $0.sessionID, title: $0.displayTitle)
            }
        }
        switch segment {
        case .main:
            return mainRow.map {
                [RotorTarget(id: $0.id, title: rowTitle($0))]
            } ?? []
        case .mine:
            return mineRows.map {
                RotorTarget(id: $0.id, title: rowTitle($0))
            }
        case .channels:
            return []
        case .archived:
            return archivedRows.map {
                RotorTarget(id: $0.id, title: rowTitle($0))
            }
        case .system:
            return systemRows.map {
                RotorTarget(id: $0.id, title: rowTitle($0))
            }
        }
    }

    /// 搜索结果：命中是轻量行（标题＋命中摘要，与
    /// 0.16.0 会话搜索同呈现同端点），点按打开续聊；
    /// 四件动作在各分段的全量行上（那里有完整会话行
    /// 数据），不在命中行上另拼一套
    private var searchContent: some View {
        List {
            if searching {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("搜索中…")
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else if searchResults.isEmpty {
                Text("服务端没有匹配的会话。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(searchResults) { hit in
                    Button {
                        onOpenSession(hit.sessionID)
                    } label: {
                        VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
                            Text(hit.displayTitle)
                                .font(.rowTitle)
                                .foregroundStyle(Palette.ink)
                                // 0.43.0（A11Y-D3）：AX 档放宽
                                .a11yLineLimit(1, ax: 2)
                            if let snippet = hit.snippet,
                               !snippet.isEmpty {
                                Text(snippet)
                                    .font(.captionText)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .a11yLineLimit(2, ax: 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                    // 0.43.0（A11Y-V7）：Rotor 行标记
                    .accessibilityRotorEntry(
                        id: hit.sessionID, in: rotorNamespace
                    )
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
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    Text("主线还没有绑定服务端会话（在聊天页发一条消息后会出现）。")
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } footer: {
                Text("主线是你的唯一指挥席：受钦定保护，本页不提供改名、归档与删除。")
            }
            migrationSection
            noticeSection
        }
        .listStyle(.plain)
        .refreshable { await reload() }
    }

    /// 我的对话段（0.36.29 替代旧站内段）：只有出
    /// 生/收养证明在身的服务端行——机器运行记录与
    /// 未认领的外部会话不再混列于此（规格 §5.1）
    private var mineContent: some View {
        List(selection: $selection) {
            migrationSection
            noticeSection
            if store.isLoading, store.sessions.isEmpty {
                Text("正在读取…")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else if let error = store.loadError {
                Text(error)
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else if mineRows.isEmpty {
                Text("我的对话里还没有服务端会话。在 App 里开的旁聊连上服务端、或从频道收进来的对话会出现在这里。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(mineRows) { session in
                    selectableRow(session)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .refreshable { await reload() }
    }

    /// 频道段（0.36.29 替代旧外部空态段）：频道总览
    /// ——Hermes 行带会话数小字（本页是分页拉全口
    /// 径，数可信，与抽屉行不给数分工，规格 §5.1）；
    /// 2026-11-13 频道一期：有成员的平台频道在此续
    /// 行（同口径带数），点开与抽屉同一入口分发器
    private var platformChannelRows: [ChannelDescriptor] {
        let order = ChannelRegistry.drawerList.map(\.id)
        return partition.channels
            .filter { $0.key != ChannelRegistry.hermesChannelID
                && !$0.value.isEmpty }
            .keys
            .sorted { a, b in
                let ia = order.firstIndex(of: a) ?? Int.max
                let ib = order.firstIndex(of: b) ?? Int.max
                if ia != ib { return ia < ib }
                return a < b
            }
            .compactMap { ChannelRegistry.descriptor(for: $0) }
    }

    private var channelsContent: some View {
        List {
            migrationSection
            noticeSection
            Section {
                Button {
                    showHermesChannel = true
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        if let asset = ChannelRegistry.hermes.iconAssetName {
                            Image(asset)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
                            Text(ChannelRegistry.hermes.name)
                                .font(.rowTitle)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text("\(partition.hermesChannelCount) 条会话")
                                .font(.captionText)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Palette.inkMuted)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                ForEach(platformChannelRows) { descriptor in
                    Button {
                        presentedPlatformChannel = descriptor
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            if let asset = descriptor.iconAssetName {
                                Image(asset)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
                                Text(descriptor.name)
                                    .font(.rowTitle)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text("\(partition.channels[descriptor.id]?.count ?? 0) 条会话")
                                    .font(.captionText)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Palette.inkMuted)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await reload() }
    }

    /// 系统段（0.36.29，规格 §5.2）：分类为系统运行
    /// 的全量行＋清理区（自旧站内段移来——清理是全
    /// 服按天数执行、主要清的就是系统与频道存量，
    /// 挂此最诚实）；行上不叠层标（本段本身即系统，
    /// 与归档段不叠标同理）
    private var systemContent: some View {
        List(selection: $selection) {
            migrationSection
            noticeSection
            if store.isLoading, store.sessions.isEmpty {
                Text("正在读取…")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else if let error = store.loadError {
                Text(error)
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else if systemRows.isEmpty {
                Text("没有系统运行记录。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(systemRows) { session in
                    selectableRow(session)
                }
            }
            cleanupSection
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .refreshable { await reload() }
    }

    private var archivedContent: some View {
        List(selection: $selection) {
            migrationSection
            noticeSection
            if store.isLoading, store.archivedSessions.isEmpty {
                Text("正在读取…")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else if archivedRows.isEmpty {
                Text("没有已归档的会话。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(archivedRows) { session in
                    selectableRow(session)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .refreshable { await reload() }
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
                // 0.43.0（A11Y-V7）：Rotor 行标记
                .accessibilityRotorEntry(
                    id: session.id, in: rotorNamespace
                )
        } else {
            ServerSessionRow(
                session: session,
                title: rowTitle(session),
                onOpen: { onOpenSession(session.id) },
                onChanged: { Task { await reload() } },
                onDeleted: { id in
                    // §223：单删落定即走共享收口清本地
                    // 线程（旧路只删服务端，抽屉残留行
                    // 点开撞 404 的出处）
                    DeletedSessionCloseout.apply(
                        sessionID: id, appState: appState,
                        threads: threads, modelContext: modelContext
                    )
                }
            ) {
                rowLabel(session)
            }
            .tag(session.id)
            // 0.43.0（A11Y-V7）：Rotor 行标记
            .accessibilityRotorEntry(
                id: session.id, in: rotorNamespace
            )
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
        // 0.43.0（A11Y-V7）：Rotor 行标记
        .accessibilityRotorEntry(id: session.id, in: rotorNamespace)
    }

    /// 行面：标题（统一管线）＋置顶标＋人话副题
    private func rowLabel(_ session: ServerSession) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
            HStack(spacing: OneDayMetrics.rowInnerGap) {
                Text(rowTitle(session))
                    // 0.23.0（审计 M1）：会话行升内容行档
                    // ——题 rowTitle（0.24.0 起 Body 17
                    // regular，角色改档）、副/时间
                    // meta（15），与点子/目标/总览会话行同尺
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
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text("没改成的项先按你改的样子显示，下次打开本页会自动再试。")
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

    /// 清理区（系统段底部，0.36.29 自旧站内段移来）：
    /// prune 两段式——先
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
            .font(.bodyText)
            Text("先预演看将删条数，确认后才会真删；真删不可恢复。")
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    /// 批量操作栏（编辑态且有选中时挂底）
    private var batchBar: some View {
        HStack(spacing: OneDayMetrics.spacingM) {
            Text("已选 \(selection.count) 条")
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            if segment == .archived {
                Button("恢复") { runBatch(.restore) }
            } else {
                Button("归档") {
                    // 0.27.0：选含合并桶时先过二次确认
                    if selectionHasMergeBucket {
                        showBatchArchiveConfirm = true
                    } else {
                        runBatch(.archive)
                    }
                }
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

    /// 名单重拉唯一口（§223）：全量拉成后 store 内
    /// 顺带对账回收本地残留线程——本页所有重拉点
    /// （首开/下拉/行变更/批量/清理）统一走此口，
    /// 不许直调 store.load 漏掉对账
    private func reload() async {
        await store.load(
            appState: appState, localThreads: threads,
            modelContext: modelContext
        )
    }

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
                if outcome != .verified {
                    failedCount += 1
                } else if kind == .delete {
                    // §223：批删落定逐条走共享收口清本
                    // 地线程（旧路只删服务端、抽屉留残
                    // 留行的出处）；未落定本地不动
                    DeletedSessionCloseout.apply(
                        sessionID: id, appState: appState,
                        threads: threads, modelContext: modelContext
                    )
                }
            }
            selection.removeAll()
            editMode = .inactive
            store.notice = failedCount == 0
                ? "已处理 \(ids.count) 条，全部确认完成。"
                : "\(ids.count - failedCount) 条已改好，\(failedCount) 条没改成——列表已按服务器现状刷新，你核对一下。"
            await reload()
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

    /// 名单全量重拉（§223 扩展：带本地线程与写上下
    /// 文，供两段拉成后的对账回收）。可见集拉成即
    /// 落位＋写回共享目录（§223 硬化：不再被已归档
    /// 段失败连坐——旧形态两段任一失败 publish 不
    /// 执行、目录静默变旧）；两段都拉成后以并集为
    /// 存活集对账清本地残留（prune 与他端删除在本
    /// 机的残留靠它回收）；任一段失败走 catch、不
    /// 对账（名单不全不清）
    func load(
        appState: AppState, localThreads: [ChatThread],
        modelContext: ModelContext
    ) async {
        isLoading = true
        loadError = nil
        do {
            let visible = try await ServerSessionCatalog.fetchAll(
                appState: appState, archived: "exclude"
            )
            sessions = visible
            // §198：全量可见集写回共享目录——抽屉频道
            // 显行闸与本页频道段自此同源同数（本页已付
            // 的分页代价全 App 只付一次）
            appState.serverSessionCatalog.publish(visible: visible)
            let archived = try await ServerSessionCatalog.fetchAll(
                appState: appState, archived: "only"
            )
            archivedSessions = archived
            // §223 名单对账：存活集（可见＋已归档并
            // 集）之外的自有绑定线程即残留，走共享
            // 收口清除
            DeletedSessionCloseout.reconcileLocalThreads(
                threads: localThreads,
                liveSessionIDs: Set(visible.map(\.id))
                    .union(archived.map(\.id)),
                appState: appState, modelContext: modelContext
            )
            // §232 归档单真相·读面对账：抽屉的本地归
            // 档键自此只是服务端归档态的呈现缓存——两
            // 段名单齐全时逐条对齐（服务端已归档→补
            // 键同隐、服务端可见→清键同显，含本页恢
            // 复后的回显与存量本地独账的收敛）
            syncDrawerArchiveCache(
                localThreads: localThreads,
                archivedIDs: Set(archived.map(\.id)),
                visibleIDs: Set(visible.map(\.id)),
                appState: appState
            )
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

    /// 抽屉归档缓存对账（§232）：以服务端两段名单为
    /// 准，把过回写闸的绑定线程的本地归档键对齐到服
    /// 务端归档态——同物同账，本地键只是缓存、不再
    /// 是第二真相。主线/合并桶绑定不在闸内（其本地
    /// 键是呈现口径，不被服务端名单反向改写）
    private func syncDrawerArchiveCache(
        localThreads: [ChatThread], archivedIDs: Set<String>,
        visibleIDs: Set<String>, appState: AppState
    ) {
        let sideChats = appState.sideChats
        for thread in localThreads {
            guard let sessionID = thread.serverSessionID,
                  SideChatLink.mayWriteThroughToServer(
                      sessionID: sessionID,
                      mainSessionID: sideChats.mainServerSessionID
                  ) else { continue }
            if archivedIDs.contains(sessionID) {
                sideChats.archive(localThreadID: thread.id)
            } else if visibleIDs.contains(sessionID) {
                sideChats.unarchive(localThreadID: thread.id)
            }
        }
    }

    /// 存量迁移执行（管理页首开）：计划走 Core 纯函数
    /// （SessionMigration.plan），逐项经动作层回写＋
    /// 回读对账；折叠后成功项清本地（覆盖表删项、归
    /// 档键删项），失败项逐项留痕＋本地值保留。迁移
    /// 后名单重拉（归档项的服务端状态已变）
    func runMigration(
        appState: AppState, localThreads: [ChatThread],
        modelContext: ModelContext
    ) async {
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
        where !outcome.remainingArchivedKeys.contains(key)
            && key.hasPrefix("server:") {
            sideChats.unarchive(
                serverSessionID: String(key.dropFirst("server:".count))
            )
        }
        migrationFailures = outcome.failures.map { failure in
            "「\(failure.item.sessionID)」\(failure.item.actionLabel)没改成：\(failure.reason)"
        }
        await load(
            appState: appState, localThreads: localThreads,
            modelContext: modelContext
        )
    }
}
