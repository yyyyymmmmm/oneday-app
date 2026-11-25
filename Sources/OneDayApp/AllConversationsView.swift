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
/// 结构归位第二批（2026-11-20，用户亲批纲要
/// D2-1/2/3）：本页升一级面（抽屉名单收尾行直
/// 达，呈现路不变）；段序定版四段＝主线／我的
/// 对话／频道／已归档——「系统」段连同其筛选开
/// 关自本页退役，系统运行、批量多选、清理旧会
/// 话（prune）、存量迁移留痕整体下沉到一层之
/// 下的维护子页（ConversationMaintenanceView，
/// 工具栏「维护」进入），本页只剩浏览与单条管
/// 理（行长按四件）；一切写动作的行为与确认口
/// 径随迁、不变。
struct AllConversationsView: View {
    /// 打开会话（宿主关页＋切聊天格＋走续聊通道）
    var onOpenSession: (String) -> Void
    /// 打开搜索命中（台账 150）：与 onOpenSession
    /// 同路，但把命中本体（摘要＋角色）一并交给宿
    /// 主——ChatView 据此在打开后收敛落点到命中消
    /// 息；宿主未提供时命中行回落 onOpenSession
    var onOpenSearchHit: ((SessionSearchHit) -> Void)? = nil
    var onClose: () -> Void

    @Environment(AppState.self) private var appState
    // 0.25.0（动效专包）：本面动画走令牌＋resolved 出口
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 「会话」Rotor 命名空间（0.43.0，A11Y-V7）：
    /// 长列表里按标题直达任意一行——条目集随当前
    /// 段/搜索态现算（rotorTargets），行标记挂在
    /// 各行分发处（sessionRow/mainRowButton/搜索
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
    /// 维护子页呈现（结构归位第二批）：工具栏
    /// 「维护」置位、导航栈推入 Conversation-
    /// MaintenanceView
    @State private var showMaintenance = false
    /// 全局搜索（台账 176，§391）：本页工具栏入口，
    /// sheet 内自带 NavigationStack
    @State private var showGlobalSearch = false
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

    enum Segment: String {
        case main = "主线"
        case mine = "我的对话"
        case channels = "频道"
        case archived = "已归档"
    }

    /// 呈现段集（结构归位第二批定版）：四段恒定
    /// ——旧第五段「系统」（0.36.29 §5.2 筛选开关
    /// 开出）已随维护层下沉退役，系统运行只在维
    /// 护子页呈现，不再与用户段同级（纲要 D2-2）
    private var visibleSegments: [Segment] {
        [.main, .mine, .channels, .archived]
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mainSessionID: String? {
        appState.sessionLedger.mainServerSessionID
    }

    /// 未归档全量的分类分筐（0.36.29）：各段行源的
    /// 唯一出处——旧「全量减主线」口径（stationSes-
    /// sions）退役，分类走 Core SessionClassifier
    /// 现算（主线/合并桶/我的对话/系统/频道一筐出）
    /// 账本名单（第 67 条包一）：本页两段名单的唯
    /// 一输入——账本投影（@Query 本地线程注入合
    /// 并）；本页 store 自此只管 UI 态与迁移执行，
    /// 不再自持名单
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

    /// 我的对话段行：分类为我的对话层（R2 关联行＋
    /// R3 前缀行，主线除外），置顶者稳定置顶（服务
    /// 端序为底、pinned 组内保序，沿旧站内段行序口径）
    private var mineRows: [ServerSession] {
        let rows = partition.mine
        return rows.filter { $0.isPinned == true }
            + rows.filter { $0.isPinned != true }
    }

    /// 已归档段行：服务端 archived 全量减主线（归档
    /// 是正交维度、全量呈现不按层分类，规格 §2/§5.1；
    /// 主线剔除走 Core 单一判定）
    private var archivedRows: [ServerSession] {
        ledgerArchivedSessions.filter {
            !SideChatClassifier.isMain(
                serverSessionID: $0.id,
                mainServerSessionID: mainSessionID
            )
        }
    }

    /// 主线行：全量里找钦定 id，找不到走单查兜底
    private var mainRow: ServerSession? {
        guard let mainSessionID else { return nil }
        return ledgerVisibleSessions.first { $0.id == mainSessionID }
            ?? ledgerArchivedSessions.first { $0.id == mainSessionID }
            ?? appState.sessionLedger.mainFallback
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
                content
            }
            .background(Palette.pageBG)
            .navigationTitle("全部对话")
            // OpenBot 样式采纳包（2026-11-20）：标题改
            // 系统大标题呈现（.large＝34pt bold 本体、
            // 滚动态栏内自动收小标题——与 OpenBot 首页
            // 「大标题＋滚过收小题」同形态，标题内容
            // 「全部对话」口径不动）；顶栏改透明（去栏
            // 自有底、透出页面底 pageBG）
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 采纳包：文字钮改 48 圆钮（口径见
                    // barRoundButton），无障碍名保留原文
                    barRoundButton(
                        systemName: "checkmark",
                        label: "完成"
                    ) { onClose() }
                }
                // 结构归位第二批：原「选择」（多选批
                // 量）钮随维护层下沉退役，本页工具栏
                // 只剩「维护」一个出口（进维护子页）
                ToolbarItem(placement: .primaryAction) {
                    Button("维护") { showMaintenance = true }
                        .disabled(isSearching)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showGlobalSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("全局搜索")
                    .disabled(isSearching)
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索全部会话（服务端）"
            )
            // 结构归位第二批：维护层推入点（系统运
            // 行／批量管理／清理／迁移留痕，见
            // ConversationMaintenanceView）；原挂底
            // 批量栏随层下沉、本页不再有编辑态
            .sheet(isPresented: $showGlobalSearch) {
                NavigationStack {
                    GlobalSearchView(
                        onOpenSearchHit: onOpenSearchHit,
                        onCloseHost: onClose
                    )
                }
                .fullscreenPopBridge()
            }
            .navigationDestination(isPresented: $showMaintenance) {
                ConversationMaintenanceView(
                    store: store,
                    onOpenSession: onOpenSession
                )
            }
        }
        .fullscreenPopBridge()
        .task {
            await reload()
            // 存量迁移：挂载点已迁账本（第 90 条收
            // 尾）——全量刷新（reload→账本 refresh）
            // 归档段同步完成即触发，失败留痕在账本、
            // 维护子页迁移区呈现，本页不再自持触发
        }
        .task(id: searchText) {
            await runSearch()
        }
        // §232 恢复回行：本页名单读账本投影——删除
        // 引擎恢复时已解墓碑＋把名单回行落账本，本
        // 页随投影自动对齐，不再需要恢复信号重拉
        // （第 67 条包二，restoreRevision 监听退役）
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
        // 批量删除/归档与清理的三张确认弹窗已随维
        // 护层迁往 ConversationMaintenanceView（结
        // 构归位第二批）——确认文案与触感口径随迁
        // 不变，本页不再持有批量/清理状态
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
                ContentUnavailableView(
                    "服务端没有匹配的会话。",
                    systemImage: "magnifyingglass"
                )
            } else {
                ForEach(searchResults) { hit in
                    Button {
                        // 台账 150：命中行优先走落点通
                        // 道（带摘要回找目标消息），宿
                        // 主未提供时回落普通打开
                        if let onOpenSearchHit {
                            onOpenSearchHit(hit)
                        } else {
                            onOpenSession(hit.sessionID)
                        }
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
        // OpenBot 样式采纳包：本页全面去分隔线、靠
        // 留白分行（各段 List 同口径，逐个落）
        .listRowSeparator(.hidden)
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
                    ContentUnavailableView(
                        "主线还没有绑定服务端会话（在聊天页发一条消息后会出现）。",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }
            } footer: {
                Text("主线是你的唯一指挥席：受钦定保护，本页不提供改名、归档与删除。")
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .refreshable { await reload() }
    }

    /// 我的对话段（0.36.29 替代旧站内段）：只有出
    /// 生/收养证明在身的服务端行——机器运行记录与
    /// 未认领的外部会话不再混列于此（规格 §5.1）
    private var mineContent: some View {
        List {
            if store.isLoading, ledgerVisibleSessions.isEmpty {
                Text("正在读取…")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else if let error = store.loadError {
                Text(error)
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else if mineRows.isEmpty {
                ContentUnavailableView(
                    "我的对话里还没有服务端会话。",
                    systemImage: "bubble.left.and.bubble.right"
                )
            } else {
                ForEach(mineRows) { session in
                    sessionRow(session)
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .refreshable { await reload() }
    }

    /// 频道段（0.36.29 替代旧外部空态段）：频道总览
    /// ——Hermes 行带会话数小字（本页是分页拉全口
    /// 径，数可信，与抽屉行不给数分工，规格 §5.1）；
    /// 2026-11-13 频道一期：有成员的平台频道在此续
    /// 行（同口径带数），点开与抽屉同一入口分发器
    /// 平台频道行源（2026-11-15 图标统一批，第 86
    /// 条）：与抽屉同律——有官方原图（注册表已登
    /// 记 iconAssetName）才上行；无资产的平台本页
    /// 不出裸行（此前无图标行与有图标行同段并存、
    /// 标题左缘错位，且与抽屉「无资产不上行」纪
    /// 律正相反，审计 C 线硬伤 2-1）。将来某平台补
    /// 登官方原图即自动上行，不需再改本面
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
            .filter { $0.iconAssetName != nil }
    }

    private var channelsContent: some View {
        List {
            Section {
                Button {
                    showHermesChannel = true
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        if let asset = ChannelRegistry.hermes.iconAssetName {
                            Image(asset)
                                .resizable()
                                .scaledToFit()
                                // 采纳包：频道图标 40→44，
                                // 走头像列表行档令牌
                                .frame(
                                    width: OneDayMetrics.avatarListRow,
                                    height: OneDayMetrics.avatarListRow
                                )
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
                        DisclosureChevron(font: .system(size: FrameworkIcon.inlineGlyphSize, weight: .regular))
                    }
                    // 采纳包：与会话行同高档（68），整页
                    // 列表一个节奏
                    .frame(
                        maxWidth: .infinity,
                        minHeight: OneDayMetrics
                            .sessionListRowMinHeight,
                        alignment: .leading
                    )
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
                                    .frame(
                                        width: OneDayMetrics.avatarListRow,
                                        height: OneDayMetrics.avatarListRow
                                    )
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
                            DisclosureChevron(font: .system(size: FrameworkIcon.inlineGlyphSize, weight: .regular))
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: OneDayMetrics
                                .sessionListRowMinHeight,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .refreshable { await reload() }
    }


    private var archivedContent: some View {
        List {
            if store.isLoading, ledgerArchivedSessions.isEmpty {
                Text("正在读取…")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            } else if archivedRows.isEmpty {
                ContentUnavailableView(
                    "没有已归档的会话。",
                    systemImage: "archivebox"
                )
            } else {
                ForEach(archivedRows) { session in
                    sessionRow(session)
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .refreshable { await reload() }
    }

    // MARK: - 行与小区

    /// 顶栏圆钮（OpenBot 样式采纳包）：48 圆＋裸玻璃
    /// ＋ink 字形——画法与抽屉底条圆钮（drawerRound-
    /// Button）同式（现行圆钮语言），直径走令牌
    /// barRoundButtonDiameter、字形走 FrameworkIcon
    /// .barButtonGlyphSize（22、regular、禁 fill 本
    /// 表宪法）；系统工具栏的共享玻璃底关掉
    /// （sharedBackgroundVisibility），免与自有玻璃
    /// 叠成双层。无障碍名由调用方给原文（「完成」/
    /// 「选择」），UI 测试按名命中不受形态影响
    private func barRoundButton(
        systemName: String, label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(
                    size: FrameworkIcon.barButtonGlyphSize,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
                .frame(
                    width: OneDayMetrics.barRoundButtonDiameter,
                    height: OneDayMetrics.barRoundButtonDiameter
                )
                .glassEffect(.regular, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(label)
        .sharedBackgroundVisibility(.hidden)
    }

    /// 会话行（浏览态）：共用组件（点按打开＋长按
    /// 四件）；多选批量形态已随维护层下沉到
    /// ConversationMaintenanceView，本页行不再有
    /// 编辑态分支
    private func sessionRow(_ session: ServerSession) -> some View {
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
        // 0.43.0（A11Y-V7）：Rotor 行标记
        .accessibilityRotorEntry(
            id: session.id, in: rotorNamespace
        )
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
        // OpenBot 样式采纳包：去线后靠留白分行——行
        // 最小高走 sessionListRowMinHeight 68（定值
        // 依据见令牌注；AX 档内容更高时由内容撑高、
        // 本值只作下限不钉死）
        .frame(
            maxWidth: .infinity,
            minHeight: OneDayMetrics.sessionListRowMinHeight,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }

    /// 行标题：与抽屉同口径，经账本标题读点（存量
    /// 本地覆盖优先，其后统一管线）
    private func rowTitle(_ session: ServerSession) -> String {
        appState.sessionLedger.title(
            for: session, appState: appState
        )
    }

    // MARK: - 动作

    /// 名单重拉唯一口（§223）：全量拉成后 store 内
    /// 顺带对账回收本地残留线程——本页所有重拉点
    /// （首开/下拉/行变更）统一走此口，不许直调
    /// store.load 漏掉对账（维护子页自持同口径的
    /// reload，两页共用同一 store 与账本）
    private func reload() async {
        await store.load(
            appState: appState, localThreads: threads,
            modelContext: modelContext
        )
    }

    /// 服务端搜索（与 0.16.0 会话搜索同一端点的管理
    /// 页呈现——搜索面收敛到本页一处）：450ms 防抖、
    /// 旧任务取消口径沿旧制（原设置名单页同款，其页
    /// 已随台账 199 删除、搜索只剩本页一份）
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

/// 管理页数据层（0.18.0 立、第 67 条包一瘦身）：
/// 自持名单退役——两段名单/主线兜底/对账/归档缓
/// 存对齐全归账本（SessionLedger），本店只剩本页
/// UI 态（加载/错误/提示/prune 预演数）。存量迁
/// 移执行与失败留痕第 90 条收尾迁账本（触发挂账
/// 本 refresh 归档段同步完成点）。load 只做触发
/// 与错误转译，拉取本体在账本 refresh（§223：本
/// 页所有重拉点仍统一走 reload → 本 load，不许
/// 漏对账）
@MainActor
@Observable
final class AllConversationsStore {
    var isLoading = false
    var loadError: String?
    /// 批量/清理结果人话条
    var notice: String?
    /// prune 预演回的将删条数（确认弹窗文案用）
    var pruneDryRunCount: Int?

/// §416 新鲜度普查豁免：全量重拉是显式动作口，经 SessionLedger 强制路，不经读触发门（判定表见 DESIGN §416）
    /// 名单全量重拉（触发账本 refresh；任一段拉取
    /// 失败转人话错误——可见段已落位不回滚，与旧
    /// load 的失败形态一致）
    func load(
        appState: AppState, localThreads: [ChatThread],
        modelContext: ModelContext
    ) async {
        isLoading = true
        loadError = nil
        do {
            try await appState.sessionLedger.refresh(
                appState: appState, localThreads: localThreads,
                modelContext: modelContext
            )
        } catch {
            loadError = (error as? HermesError)?.userMessage
                ?? "名单没拉下来，请稍后再试。"
        }
        isLoading = false
    }

}
