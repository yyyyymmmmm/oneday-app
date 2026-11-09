import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 抽屉（侧边栏）。0.19.0 照 Muse 本体侧边栏重构，
/// 当日两轮口径（用户 2026-11-09 22:26 首令＋22:45
/// 纠正，现行以纠正为准）：
///
/// - 结构：顶部名字头（28 bold）→导航行组（对样板
///   「选项卡」：主线聊天／枢纽／点子／目标／应用，
///   点行即达并关抽屉）→发丝线→「管理全部对话」一
///   行→发丝线→**「旁聊」区：只列用户本人在 App 里
///   开的旁聊**（平铺、最近时间倒序、无分组字、无
///   每行角标，点行进该会话续聊）。
/// - 22:45 纠正的要害：要撤的只是「其他的对话」——
///   Hermes 内部 worker/kanban 会话、验收测试会
///   话、微信/TG 等外部平台通道进来的会话；本人开
///   的旁聊（如「你好」）必须留。过滤落法（实查依
///   据见 OneDayCore.DrawerSideChatFilter 文件注：
///   生产 28 条会话逐条分类在 DESIGN-V4 §46）：抽
///   屉名单本体收敛为**本地线程**（用户在 App 里新
///   建的旁聊恒为本地线程、serverSessionID 恒 nil，
///   服务端名单整类不单独成行即无误伤）；本地线程
///   若关联了服务端会话，其来源再过 Core 过滤一
///   道（kanban/平台源即便被点开导入过也不显示）。
///   撤除面：旧「站内」分区字、「今天」等时间分组
///   字、每行「旁聊」角标、旧「主线」分区头与主线
///   行（导航组「主线聊天」行已覆盖）、契约文案、
///   服务端独立行、已归档区（归档归管理页）。
/// - 服务端会话与本地线程的数据本体（SideChat-
///   Store/AllConversationsStore/ServerSessionRow）
///   不动：管理页全量可用如旧；本面开抽屉只拉一路
///   服务端会话取 source 映射作过滤判定（拉不到时
///   映射为空、本地行恒放行，不因服务端不可达藏
///   掉本人旁聊）。
/// - 底条三件套保留（齿轮圆钮＋搜索胶囊＋新聊圆
///   钮）：搜索＝本地过滤旁聊区（标题＋条目内容，
///   与 0.18.0 抽屉搜索同口径；22:26 首令的「跳管
///   理页聚焦」随 22:45 纠正作废）；下边距固定 4
///   （0.19.0 拆双计，见 drawerBottomBar 注）。
/// - 0.6.1 曾以「与底栏逐项重复」删过同类导航组；
///   0.19.0 用户对着 Muse 样板亲口改令立导航组，
///   新令覆盖旧裁决，此注为据。
/// - 承载沿 0.17.0：壳层（ContentView.DrawerShell）
///   以覆盖形态自左滑入盖在静止内容之上，本面根
///   ScrollView＋头尾 safeAreaBar 注册结构不变；头
///   尾固定实色条是 0.6.1「两端 E11 带全删」后的定
///   式：内容从实色条下方滑过被遮、条面与面板同色
///   一贯，不许再挂任何自绘渐变带/模糊层（E11 已
///   注销）。
struct DrawerView: View {
    /// 面板宽＝壳层量测给（录屏量测 0.79×屏宽、上限
    /// 400，见 ContentView 壳层注）
    let width: CGFloat
    /// 当前底栏格（壳层回写，导航行选中垫用）
    let currentTab: ContentView.MainTab
    /// 导航点按 → 切换底栏格（ContentView 注入）
    var onSelectTab: (ContentView.MainTab) -> Void
    /// 关抽屉（壳层执行：弹簧归位＋状态回写）
    var onClose: () -> Void
    /// 打开「全部对话」管理页（0.18.0；本面先经
    /// onClose 关抽屉，ContentView 注入呈现）
    var onManageAll: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatThread.updatedAt, order: .reverse)
    private var threads: [ChatThread]
    /// 底条搜索词（本地过滤旁聊区，22:45 纠正后恢复
    /// 0.18.0 抽屉搜索口径）
    @State private var drawerQuery = ""
    /// 服务端会话 source 映射（会话 id→source）：只
    /// 喂旁聊行显的来源过滤判定，不作名单数据源；
    /// 拉不到为空表（本地行恒放行）
    @State private var drawerServerSources: [String: String] = [:]
    /// 本地旁聊行重命名（长按四件之一，0.18.0 沿革）
    @State private var renamingThread: ChatThread?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            Group {
                if isSearching {
                    drawerSearchList
                } else {
                    drawerNavList
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ignoresSafeArea(edges: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // 0.4.3（§28.5）：头尾承载走 safeAreaBar 注册。
        // 0.6.1（用户第二轮真机点名）：两端 E11 渐进
        // 模糊带全删——顶带是「标题区朦胧透内容」的
        // 元凶、底带是抽屉底部乳白块的元凶（带底落到
        // 屏边、满 alpha 盖住 home indicator 区）；头
        // 尾改固定实色条（令牌表面色打底、内容从其下
        // 方滑过被实色遮住），顶缘 .soft 随顶带一并
        // 撤销（实色条下无可化开的透层）
        .safeAreaBar(edge: .top, spacing: 0) {
            drawerAgentName
                .background {
                    Palette.surface
                        .ignoresSafeArea(edges: .top)
                }
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            drawerBottomBar
                .background {
                    Palette.surface
                        .ignoresSafeArea(edges: .bottom)
                }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        // 面板底色穿过上下安全区（0.4.1 第 10 修：顶边
        // 贴到屏幕顶——状态栏压面板之上、左缘贴边；
        // 0.4.5 起底边同口径直达屏底，0.19.0 导航形态
        // 下不变：抽屉面底色须一贯到底缘、不留色带）
        .background {
            Palette.chatSurface
                .ignoresSafeArea(edges: [.top, .bottom])
        }
        .alert(
            "重命名会话",
            isPresented: Binding(
                get: { renamingThread != nil },
                set: { if !$0 { renamingThread = nil } }
            )
        ) {
            TextField("会话标题", text: $renameText)
            Button("取消", role: .cancel) { renamingThread = nil }
            Button("保存") { commitRenameThread() }
        }
        // 开抽屉时补拉服务端 source 映射（只喂来源过
        // 滤判定；信号源＝壳层维护的语义开合状态）
        .onChange(of: appState.drawerPresented) { _, presented in
            if presented {
                Task { await loadDrawerData() }
            }
        }
        // 0.7.1（裁决 §3.5 S5 预挂载）：壳层在左缘触摸
        // 按下时即挂载本面抢建树——本面出现即补拉一
        // 次作预取（本地名单由 @Query 随挂载自动建
        // 树），语义打开时仍走上方 onChange 的拉取
        .onAppear {
            if drawerServerSources.isEmpty {
                Task { await loadDrawerData() }
            }
        }
    }

    /// 服务端会话 source 映射拉取（0.19.0 返工瘦身
    /// 版）：0.18.0 时代此处拉两路名单（可见＋归档）
    /// 喂抽屉成行；现名单本体是本地线程，服务端只
    /// 需 id→source 一张映射作行显过滤（limit 100 一
    /// 页取全——现存 28 条；archived=exclude 与管理
    /// 页可见口径同源，归档会话的关联线程另有本地
    /// 归档位把守）
    private func loadDrawerData() async {
        if let page = try? await appState.performAdmin({ client, config in
            try await client.serverSessionsPage(
                config: config, limit: 100, offset: 0, archived: "exclude"
            )
        }) {
            drawerServerSources = Dictionary(
                uniqueKeysWithValues: page.sessions.map {
                    ($0.id, $0.source ?? "")
                }
            )
        }
    }

    /// 栏内顶部（0.3.6 立宪，§21.3）：只有智能体名字
    /// （28 bold）——状态点＋状态词·模型小字全撤（定
    /// 义卡删减清单：那是管理面信息，不占导航壳第一眼）
    private var drawerAgentName: some View {
        Text(appState.identityName ?? AgentName.fallback)
            // 0.17.0（五修③照样板）：名字回 0.3.6 立宪的
            // 28 bold（.title＋bold）——此前漂移成
            // .largeTitle regular，样板（Muse 本体侧栏）
            // 的名字是粗体大字、第一眼即身份
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.drawerInset)
            .padding(.top, OneDayMetrics.spacingL)
            .padding(.bottom, OneDayMetrics.spacingSM)
    }

    // MARK: - 导航主体（0.19.0）

    /// 导航组＋管理行＋旁聊区：对 Muse 样板的结构
    /// ——「选项卡」组五行管导航，其下发丝线＋「管理
    /// 全部对话」一行，再下发丝线＋「旁聊」区（本人
    /// 旁聊平铺，见旁聊区注）
    private var drawerNavList: some View {
        VStack(alignment: .leading, spacing: 0) {
            drawerGroupHeader("选项卡")
            drawerNavRow(
                symbol: TabBarSymbols.chat.normal,
                title: "主线聊天",
                selected: currentTab == .chat
            ) {
                onClose()
                onSelectTab(.chat)
            }
            // 枢纽行：枢纽 sheet 本体长在聊天页（胶囊入
            // 口同处），先切聊天格再经请求通道置位（不
            // 在本面另立第二份承载）；动作型行、无选中垫
            drawerNavRow(
                symbol: TabBarSymbols.activity.normal,
                title: "枢纽",
                selected: false
            ) {
                onClose()
                if currentTab != .chat {
                    onSelectTab(.chat)
                }
                appState.hubOpenRequested = true
            }
            drawerNavRow(
                symbol: TabBarSymbols.ideas.normal,
                title: "点子",
                selected: currentTab == .ideas
            ) {
                onClose()
                onSelectTab(.ideas)
            }
            drawerNavRow(
                symbol: TabBarSymbols.goals.normal,
                title: "目标",
                selected: currentTab == .goals
            ) {
                onClose()
                onSelectTab(.goals)
            }
            drawerNavRow(
                symbol: TabBarSymbols.apps.normal,
                title: "应用",
                selected: currentTab == .apps
            ) {
                onClose()
                onSelectTab(.apps)
            }
            drawerDivider
                .padding(.top, OneDayMetrics.spacingS)
            drawerManageRow
            drawerDivider
                .padding(.top, OneDayMetrics.spacingS)
            drawerSideSection
            Color.clear
                .frame(height: OneDayMetrics.spacingL)
        }
        .padding(.top, OneDayMetrics.spacingS)
    }

    // MARK: - 旁聊区（0.19.0 返工，22:45 纠正口径）

    /// 旁聊区：单个「旁聊」分区头＋平铺行（@Query 的
    /// updatedAt 倒序即呈现序，不分组、不置顶分段）；
    /// 空时只留一行弱字提示（不整区消失——让用户知
    /// 道新建入口在哪）
    @ViewBuilder
    private var drawerSideSection: some View {
        drawerGroupHeader("旁聊")
        if sideThreads.isEmpty {
            Text("还没有旁聊")
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OneDayMetrics.drawerInset)
                .padding(.bottom, OneDayMetrics.spacingS)
        } else {
            ForEach(sideThreads) { thread in
                drawerSideThreadRow(thread)
            }
        }
    }

    /// 搜索态名单：只显命中的旁聊行（导航组与管理行
    /// 隐藏，与 0.18.0 抽屉搜索同行为）；无命中给弱
    /// 字一行，不留空白屏
    @ViewBuilder
    private var drawerSearchList: some View {
        VStack(alignment: .leading, spacing: 0) {
            drawerGroupHeader("旁聊")
            if sideThreads.isEmpty {
                Text("没有匹配的旁聊")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OneDayMetrics.drawerInset)
                    .padding(.bottom, OneDayMetrics.spacingS)
            } else {
                ForEach(sideThreads) { thread in
                    drawerSideThreadRow(thread)
                }
            }
            Color.clear
                .frame(height: OneDayMetrics.spacingL)
        }
        .padding(.top, OneDayMetrics.spacingS)
    }

    private var isSearching: Bool {
        !drawerQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 搜索过滤（0.18.0 口径原样）：标题或任一条目内
    /// 容包含搜索词（不区分大小写）；非搜索态恒全量
    private var filteredThreads: [ChatThread] {
        let query = drawerQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return threads }
        return threads.filter { thread in
            thread.title.localizedCaseInsensitiveContains(query)
                || thread.entries.contains {
                    $0.content.localizedCaseInsensitiveContains(query)
                }
        }
    }

    /// 可见本地线程（0.7.0 口径原样）：归档过滤恒生
    /// 效——本地归档旁聊从一切名单隐藏（搜索也不许
    /// 捞出来），只在管理页已归档段可见
    private var drawerItems: [ChatThread] {
        filteredThreads.filter {
            !SideChatArchive.isArchived(
                localThreadID: $0.id,
                archivedKeys: appState.sideChats.archivedKeys
            )
        }
    }

    /// 旁聊区行源：可见本地线程剔主线后逐条过 Core
    /// 行显过滤（DrawerSideChatFilter：主线/归档已在
    /// 上游剔除，此处再核关联会话来源一道——kanban/
    /// 平台源的导入线程不显示；来源未知恒放行）
    private var sideThreads: [ChatThread] {
        drawerItems.filter { thread in
            DrawerSideChatFilter.threadListed(
                isMainThread: thread.id == appState.sideChats.mainThreadID,
                isLocallyArchived: false,
                linkedSource: thread.serverSessionID.flatMap {
                    drawerServerSources[$0]
                }
            )
        }
    }

    /// 旁聊行（0.17.0 单行形态沿用、0.19.0 返工去角
    /// 标）：标题＋行尾小字时间、当前位浅灰垫；点按
    /// 经 drawerThreadSelection 请 ChatView 切换并关
    /// 抽屉（0.4.5 通道化沿革）；长按四件与 0.18.0
    /// 本地行同序（重命名/置顶/归档/删除）——置顶只
    /// 落数据（isPinned），抽屉呈现恒时间序（22:45
    /// 平铺口径），置顶的呈现归管理页等其他面
    private func drawerSideThreadRow(_ thread: ChatThread) -> some View {
        let isCurrent = thread.id == appState.activeThreadID
        return Button {
            appState.drawerThreadSelection = thread.id
            onClose()
        } label: {
            HStack(spacing: 6) {
                Text(thread.title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: OneDayMetrics.spacingS)
                Text(LocalThreadSubtitle.timeText(
                    updatedAt: thread.updatedAt,
                    now: Date()
                ))
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, OneDayMetrics.spacingS)
            .frame(
                maxWidth: .infinity,
                minHeight: OneDayMetrics.navRowHeight,
                alignment: .leading
            )
            .background(
                isCurrent ? Palette.selectionFill : Color.clear,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.fieldCorner
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .contextMenu {
            Button {
                beginRenameThread(thread)
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button {
                togglePinThread(thread)
            } label: {
                Label(
                    thread.isPinned ? "取消置顶" : "置顶",
                    systemImage: thread.isPinned ? "pin.slash" : "pin"
                )
            }
            Button {
                appState.sideChats.archive(localThreadID: thread.id)
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                deleteThread(thread)
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        }
    }

    private func togglePinThread(_ thread: ChatThread) {
        thread.isPinned.toggle()
        try? modelContext.save()
    }

    private func beginRenameThread(_ thread: ChatThread) {
        renameText = thread.title
        renamingThread = thread
    }

    private func commitRenameThread() {
        let title = renameText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let thread = renamingThread, !title.isEmpty {
            thread.title = title
            try? modelContext.save()
        }
        renamingThread = nil
    }

    private func deleteThread(_ thread: ChatThread) {
        // 0.4.5 通道化：删的若是 ChatView 正在显示的线
        // 程，经 drawerDeletedThreadID 通知它置空当前
        // 线程（本面不持有 currentThreadID）
        if thread.id == appState.activeThreadID {
            appState.drawerDeletedThreadID = thread.id
        }
        modelContext.delete(thread)
        try? modelContext.save()
    }

    /// 分组小标题（0.3.6 立宪）：13–14 号灰标签、左线
    /// 恒 drawerInset 20、上下留白 S/SM——分组就这一
    /// 种形态（0.17.0 补全宽左对齐帧治居中病根）
    private func drawerGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(Palette.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.drawerInset)
            .padding(.top, OneDayMetrics.spacingS)
            .padding(.bottom, OneDayMetrics.spacingSM)
    }

    /// 导航行（0.19.0，对 Muse 样板「选项卡」行）：单
    /// 行制——SF 符号（与底栏同源 TabBarSymbols，不另
    /// 立第二套符号表）＋标题，选中格浅灰垫（selec-
    /// tionFill 整行圆角垫、标题不变色不加粗），行高
    /// 与 0.17.0 单行会话行同档（47pt 导航行档）
    private func drawerNavRow(
        symbol: String, title: String, selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OneDayMetrics.navRowHeight)
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .background {
                if selected {
                    Palette.selectionFill
                        .clipShape(RoundedRectangle(
                            cornerRadius: OneDayMetrics.fieldCorner,
                            style: .continuous
                        ))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, OneDayMetrics.spacingS)
        .accessibilityLabel(title)
    }

    /// 「管理全部对话」行（0.18.0 立、0.19.0 随名单退
    /// 役保留）：rectangle.stack＋标题＋chevron 单行，
    /// 点按关抽屉进管理页（对话的找与管全在那里：
    /// 四段分区、长按四件、批量、清理、服务端搜索）
    private var drawerManageRow: some View {
        Button {
            onClose()
            onManageAll()
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)
                Text("管理全部对话")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OneDayMetrics.navRowHeight)
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, OneDayMetrics.spacingS)
        .padding(.top, OneDayMetrics.spacingSM)
        .accessibilityLabel("管理全部对话")
    }

    /// 发丝线（左右留 drawerInset 20）：组间分隔的唯
    /// 一形态（立宪：分组＝13–14 灰标签＋发丝线）
    private var drawerDivider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.horizontal, OneDayMetrics.drawerInset)
    }

    // MARK: - 底条

    /// 抽屉底部浮动条（0.3.6 立宪，§21.3）：左右圆钮
    /// （左设置/右新建）＋中间同高搜索胶囊——搜索只
    /// 服务旁聊区名单、贴在其脚下（本地过滤，见文件
    /// 头 22:45 口径）。
    /// 0.19.0 改：下边距拆双计改固定 4——0.4.5 手算口
    /// 径（壳层量测的窗口底 inset＋4＝约 38pt）的前提
    /// 是推式时代「名单 ScrollView ignoresSafeArea
    /// (.bottom) 后 safeAreaBar 的代抬消失」；0.17.0
    /// 覆盖承载下本条是系统注册 bar（与顶条同结构、
    /// 无人给顶条手算过、从无此病），bar 内容本就停
    /// 在安全区线之上，再叠手算等于把 home indicator
    /// 段算两遍——真机底条之下死白一大坨（用户 22:26
    /// 截图）的可证一段即此。拆后落点与注册 bar 时代
    /// （0.4.2–0.4.4）的固定 4pt 一致：底条底缘停在
    /// indicator 线上方 4pt、照 Muse 样板贴底；壳
    /// 层量测的 bottomSafeInset 入参随之退役（Drawer-
    /// Geometry 的量测纯函数本体保留作口径档案、单
    /// 测继续把守）
    private var drawerBottomBar: some View {
        // 0.3.8 第 23 条：三件紧凑成组——横边距 20→12、
        // 件间距 12→8，搜索胶囊随之拉长（面板宽约 310
        // 时胶囊约 166–174，Muse 实测约 173）
        HStack(spacing: OneDayMetrics.spacingS) {
            drawerRoundButton(
                // 卡 18 纠正 4：左圆钮用独立齿轮 glyph，
                // 与名单设置行（滑杆）、底栏设置格三者不同图
                // 0.6.0：设置收进应用格内页面——经
                // pendingAppsPage 通道落位（AppsView 消费）
                systemName: "gearshape",
                label: "设置"
            ) {
                onClose()
                appState.pendingAppsPage = .settings
                onSelectTab(.apps)
            }
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
                TextField("搜索会话", text: $drawerQuery)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                if !drawerQuery.isEmpty {
                    Button {
                        drawerQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .frame(height: OneDayMetrics.drawerBarButton)
            // 0.4.1 第 10 修：白浮纸（灰实填）换近白玻
            // 璃（与圆钮同改）——.glassEffect(.regular)
            // 系统玻璃（压在 #FCFCFC 面板上采样约
            // #F9F9F9）＋发丝边＋轻柔影；与发送舱同式
            // （玻璃施加于件本体、内容在其上）
            .glassEffect(.regular, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Palette.hairline, lineWidth: 0.5)
            }
            .shadow(
                color: Palette.shadowBase.opacity(0.06),
                radius: 8, y: 2
            )
            drawerRoundButton(
                systemName: "square.and.pencil",
                label: "新建会话"
            ) {
                createThread()
                onClose()
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.top, OneDayMetrics.spacingSM)
        .padding(.bottom, 4)
    }

    private func drawerRoundButton(
        systemName: String, label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                // 0.3.8 第 24 条：齿轮字形与名单同线宽档
                // （17 regular，令牌 drawerBarGlyphSize；
                // 旧 18 无字重渲染偏实）
                .font(.system(
                    size: FrameworkIcon.drawerBarGlyphSize,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
                .frame(
                    width: OneDayMetrics.drawerBarButton,
                    height: OneDayMetrics.drawerBarButton
                )
                // 0.4.1 第 10 修：白浮纸换近白玻璃（与
                // 搜索胶囊同改，口径见彼处注）
                .glassEffect(.regular, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Palette.hairline, lineWidth: 0.5)
                }
                .shadow(
                    color: Palette.shadowBase.opacity(0.06),
                    radius: 8, y: 2
                )
                .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(label)
    }

    /// 新建会话（0.4.5 通道化）：本地插入后经 AppState
    /// 通道请 ChatView 切换过去（本面不持有当前线程
    /// 状态；ChatView 消费 drawerThreadSelection 后清零）
    private func createThread() {
        let thread = ChatThread()
        modelContext.insert(thread)
        try? modelContext.save()
        appState.drawerThreadSelection = thread.id
    }
}
