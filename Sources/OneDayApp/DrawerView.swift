import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 会话抽屉面（0.4.5 承载换代，DESIGN-V4 §30）：0.4.4 前
/// 本体住在 ChatView 内、以覆盖层（纱＋peek 面板）盖在聊天
/// 主面上；用户 2026-11-09 11:37 发 Muse 本体录屏点名
/// 「侧边栏是推不是盖」——抽屉承载自此提到壳层（Content-
/// View 根）：本面是底层，整个应用表面（TabView）是被推
/// 开的页卡，两者刚性联动（录屏逐帧量测：抽屉地标与页卡
/// 同速同距、无视差，§30 量测表）。本文件只管抽屉面本体：
/// 头尾 safeAreaBar 钉住（0.6.1 起实色固定条）＋名单/搜索/底条，
/// 几何与行为口径自 0.4.2–0.4.4 原样搬迁；开合状态、跟手
/// 手势与页卡变换全在壳层，本面只经闭包与 AppState 通道
/// 与外界说话：
/// - 关抽屉：onClose（壳层执行动画与状态）
/// - 切底栏格：onSelectTab（ContentView 注入）
/// - 点本机会话：写 AppState.drawerThreadSelection，
///   ChatView 消费后切 currentThreadID 并清零
/// - 点服务端会话：写 AppState.pendingChatSessionID
///   （0.4.0 续聊改道链不变，ContentView 切聊天格、
///   ChatView 导入续聊）
/// - 删当前会话：写 AppState.drawerDeletedThreadID，
///   ChatView 若正显示该线程则置空当前线程
/// - 当前会话高亮：读 AppState.activeThreadID（ChatView
///   随 currentThreadID 变化回写）
/// 与旧承载的口径差（§30 在案）：①面板右缘发丝线＋贴边
/// 窄影撤销——推式下分离感由页卡的圆角/缩放/左缘柔影承
/// 担，面板与页卡贴合处再画一线是双重描边；②底条下边距
/// 改回手算（见 drawerBottomBar）；③名单 ScrollView 向
/// 下穿过安全区直达屏幕底边（用户 11:47 点名：内容在底
/// 条下方渐隐直达屏边、不留死白条）。
struct DrawerView: View {
    /// 面板宽＝壳层推开量（录屏量测 0.79×屏宽、上限
    /// 400，见 ContentView 壳层注）
    let width: CGFloat
    /// 窗口底部安全区 inset（壳层 onGeometryChange 量
    /// 测给，0.7.1 前为 GeometryReader）：名单 Scroll-
    /// View 已 ignoresSafeArea(.bottom)、安全区不再代
    /// 抬底条，底条下边距据此手算
    let bottomSafeInset: CGFloat
    /// 当前底栏格（壳层回写，高亮当前位用；0.6.0 五格）
    let currentTab: ContentView.MainTab
    /// 名单点按 → 切换底栏格（ContentView 注入）
    var onSelectTab: (ContentView.MainTab) -> Void
    /// 关抽屉（壳层执行：弹簧归位＋状态回写）
    var onClose: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]

    /// 抽屉内搜索词
    @State private var drawerQuery = ""
    /// 侧边栏重命名（0.3.6，§21）：长按菜单发起，alert
    /// 输入后写回 ChatThread.title
    @State private var renamingThread: ChatThread?
    @State private var renameText = ""
    /// 服务端会话重命名（0.7.0，M3）：已建会话改 title
    /// 未证实——不走服务端，写本地覆盖表（SideChatStore
    /// .titleOverrides），名单标题以覆盖为准
    @State private var renamingServerSession: ServerSession?
    @State private var serverRenameText = ""
    /// 「已归档」区展开态（0.7.0，M2）：默认收起
    @State private var showArchived = false
    /// 服务端会话组的数据（开抽屉时拉取）
    @State private var drawerServerSessions: [ServerSession] = []

    var body: some View {
        // 头尾钉住＋中段滚动（0.4.2，用户 10:54 对照
        // Muse 本体标注图纠正，取代 0.4.1 的整栏全滚
        // 读法）：智能体名区不滚、底条（齿轮/搜索/新建）
        // 不滚、只有中间名单区滚动。结构：名单 Scroll-
        // View 居中，名字与底条经 safeAreaBar 钉进它的
        // 上下安全区——与聊天页发送舱同一系统通道（条
        // 即安全区、内容从其下方滑过）。0.6.1 起头尾
        // 两条改固定实色（令牌表面色打底、见 safeArea-
        // Bar 处注），旧「透出面板底色＋E11 两端化开」
        // 口径退役
        ScrollView {
            drawerList
        }
        // 0.4.5（§30，用户 11:47 点名）：名单向下穿过
        // 底部安全区直达屏幕底边；底条下边距手算（见
        // drawerBottomBar）
        .ignoresSafeArea(edges: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // 0.4.3（§28.5）：头尾承载走 safeAreaBar 注册。
        // 0.6.1（用户第二轮真机点名）：两端 E11 渐进
        // 模糊带全删——顶带是「标题区朦胧透内容」的
        // 元凶、底带是抽屉底部乳白块的元凶（带底落到
        // 屏边、满 alpha 盖住 home indicator 区）；头
        // 尾改固定实色条（令牌表面色打底、名单从其下
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
        // 0.4.5 起底边同口径直达屏底，与名单穿边一致）
        .background {
            Palette.chatSurface
                .ignoresSafeArea(edges: [.top, .bottom])
        }
        // （0.4.5 删：0.4.1 第 10 修的面板四角直角＋右缘
        // 发丝线＋贴边窄影——那是覆盖式 peek 面板的收
        // 尾；推式下本面与页卡左缘贴合，分离感由页卡
        // 本体的圆角/缩放/柔影承担（壳层），此处再描
        // 一线是双重描边，§30 口径变化在案）
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
        .alert(
            "重命名会话",
            isPresented: Binding(
                get: { renamingServerSession != nil },
                set: { if !$0 { renamingServerSession = nil } }
            )
        ) {
            TextField("会话标题", text: $serverRenameText)
            Button("取消", role: .cancel) { renamingServerSession = nil }
            Button("保存") { commitRenameServerSession() }
        }
        // 开抽屉时拉服务端会话组（0.4.4 前挂 ChatView
        // 的 drawerOpen onChange；0.4.5 起抽屉自理，
        // 信号源＝壳层维护的语义开合状态 drawerPresented）
        .onChange(of: appState.drawerPresented) { _, presented in
            if presented {
                Task { await loadDrawerData() }
            }
        }
        // 0.7.1（裁决 §3.5 S5 预挂载）：壳层在左缘触摸
        // 按下时即挂载本面抢建树——本面出现即补拉一次
        // 服务端会话组作预取（本地名单由 @Query 随挂
        // 载自动建树），拖动起步帧零等待；语义打开时
        // 仍走上方 onChange 的全量拉取，本处只补空缺
        .onAppear {
            if drawerServerSessions.isEmpty {
                Task { await loadDrawerData() }
            }
        }
    }

    /// 栏内顶部（0.3.6 立宪，§21.3）：只有智能体名字
    /// （28 bold）——状态点＋状态词·模型小字全撤（定
    /// 义卡删减清单：那是管理面信息，不占导航壳第一眼）
    private var drawerAgentName: some View {
        Text(appState.identityName ?? AgentName.fallback)
            .font(.largeTitle)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.drawerInset)
            .padding(.top, OneDayMetrics.spacingL)
            .padding(.bottom, OneDayMetrics.spacingSM)
    }

    private func loadDrawerData() async {
        if let page = try? await appState.performAdmin({ client, config in
            // 0.7.0：拉取量 6→20——可见区仍只摆前 6 条，
            // 多拉的是给「已归档」区与主线服务端会话的
            // 排除判定留量（归档条目不再挤占可见名额）
            try await client.serverSessions(config: config, limit: 20)
        }) {
            drawerServerSessions = page.sessions
            // 派生标题（0.6.1）：行标题走全局解析器（与
            // 活动行同一派生同一缓存）；0.7.0 预算随拉
            // 取量放大到 12（可见 6＋归档区在列者）
            await appState.sessionTitles.ensureTitles(
                for: page.sessions, appState: appState, budget: 12
            )
        }
    }

    // （0.6.1 删：全局名单「选项卡」五格组——与底栏
    // 五格逐项重复（用户第二轮真机点名），抽屉回归
    // 单一职责：身份标题＋会话名单＋底部三钮。切格
    // 只走底栏，onSelectTab/currentTab 仍供底条设置
    // 钮等既有通道使用）

    /// 发丝线（左右留 drawerInset 20）：组间分隔的唯
    /// 一形态（立宪：分组＝13–14 灰标签＋发丝线）
    private var drawerDivider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.horizontal, OneDayMetrics.drawerInset)
    }

    /// 抽屉底部浮动条（0.3.6 立宪，§21.3）：左右圆钮
    /// （左设置/右新建）＋中间同高搜索胶囊——搜索与
    /// 新建从顶部行位沉到拇指区（定义卡「控件跟内容
    /// 走」：搜索只服务这份会话名单、就贴在名单脚下）
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
        // 底边距（0.4.5 承载变化下复活手算口径，§30）：
        // 0.4.2–0.4.4 本条由 safeAreaBar 钉在名单底部
        // 安全区、安全区代抬 home indicator 段、下边距
        // 只留 4；0.4.5 名单 ScrollView 已 ignoresSafe-
        // Area(.bottom) 直达屏底（用户 11:47 点名内容
        // 渐隐到边），安全区底 inset 归零、代抬消失，
        // 下边距必须把那段补回来——DrawerGeometry
        // .bottomBarBottomPadding（安全区底 inset＋4，
        // 0.3.8 立、0.4.2 在注册 bar 结构里退役的纯函
        // 数）在此复活：落点与旧口径逐点一致，底条底
        // 缘在屏高约 95.5–96%（852/926pt 屏、inset 34），
        // 对样板实测 96.1%（§30 对照表）
        .padding(.bottom, DrawerGeometry.bottomBarBottomPadding(
            safeAreaBottom: bottomSafeInset
        ))
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

    private var isSearching: Bool {
        !drawerQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 0.7.0（M2）：归档过滤恒生效——归档旁聊从一切名单
    /// 隐藏（搜索也不许捞出来），只在「已归档」区可见
    private var drawerItems: [ChatThread] {
        filteredThreads.filter {
            !SideChatArchive.isArchived(
                localThreadID: $0.id,
                archivedKeys: appState.sideChats.archivedKeys
            )
        }
    }

    /// 钦定主线（D1）：抽屉置顶独立区，行保护见
    /// drawerThreadRow（无长按菜单、不可归档不可删）
    private var mainThread: ChatThread? {
        guard let mainID = appState.sideChats.mainThreadID else { return nil }
        return threads.first { $0.id == mainID }
    }

    /// 旁聊名单：可见本地线程剔除主线
    private var sideThreads: [ChatThread] {
        drawerItems.filter { $0.id != appState.sideChats.mainThreadID }
    }

    /// 归档区本地线程：不吃搜索词（归档区只在非搜索态出现）
    private var archivedLocalThreads: [ChatThread] {
        threads.filter {
            $0.id != appState.sideChats.mainThreadID
                && SideChatArchive.isArchived(
                    localThreadID: $0.id,
                    archivedKeys: appState.sideChats.archivedKeys
                )
        }
    }

    /// 服务端会话二分（0.7.0）：主线的服务端会话先整体
    /// 剔除（它就是主线本体、不进任何旁聊名单），其余
    /// 按归档集合分可见/归档；可见区仍只摆前 6 条
    private var serverPartition: (visible: [ServerSession], archived: [ServerSession]) {
        let sideOnly = drawerServerSessions.filter {
            SideChatClassifier.zone(
                serverSessionID: $0.id,
                mainServerSessionID: appState.sideChats.mainServerSessionID
            ) == .side
        }
        return SideChatArchive.partition(
            sideOnly,
            key: { SideChatArchive.serverKey($0.id) },
            archivedKeys: appState.sideChats.archivedKeys
        )
    }

    private var visibleServerSessions: [ServerSession] {
        Array(serverPartition.visible.prefix(6))
    }

    private var archivedServerSessions: [ServerSession] {
        serverPartition.archived
    }

    /// 服务端行标题（M3 管线合并）：用户改名（本地覆盖
    /// 表）＞ 派生管线（SessionTitleResolver：建线 title
    /// →首条消息派生→未命名会话）
    private func serverTitle(_ session: ServerSession) -> String {
        appState.sideChats.titleOverrides[session.id]
            ?? appState.sessionTitles.title(for: session)
    }

    /// 侧边栏会话组（0.3.6 立，§21.3/§21.4；0.4.1 改
    /// 承载）：只产出素行内容（组标题/会话行/空态/尾
    /// 留白，x 线全自控），直排进面板 ScrollView 的同
    /// 一 VStack。会话行长按菜单＝置顶/重命名/删除三
    /// 件套。分组＝灰标签＋留白（0.3.8 第 21 条后组间
    /// 不划线——0.4.1 第 10 修又逐项补回发丝线，见下）
    /// 服务端会话组在尾（0.4.0 起点行改道聊天页续聊、
    /// 标题人话化）。
    /// 名单结构（0.7.0 分区重排，D3）：非搜索态自上而下
    /// ＝「主线」区（钦定单行置顶、行保护）→「旁聊」区
    /// （其余本地线程走原时间分组、行带「旁聊」标识）
    /// →「其他会话」（服务端旁聊，可见前 6）→「已归档」
    /// 区（可展开恢复）→契约文案。搜索态退回单组平铺
    /// （主线可搜到、归档恒隐藏、分区头不出现）。
    private var drawerList: some View {
        VStack(spacing: 0) {
            if isSearching {
                if drawerItems.isEmpty {
                    drawerPlainRow {
                        Text("没有匹配的会话")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkMuted)
                            .padding(.horizontal, OneDayMetrics.drawerInset)
                            .padding(.top, OneDayMetrics.spacingL)
                    }
                } else {
                    threadGroupSections(groupedThreads(drawerItems))
                }
            } else {
                if let mainThread {
                    drawerGroupHeader("主线")
                    drawerThreadRow(mainThread)
                }
                if !sideThreads.isEmpty {
                    if mainThread != nil {
                        drawerDivider
                            .padding(.top, OneDayMetrics.spacingS)
                    }
                    drawerGroupHeader("旁聊")
                    threadGroupSections(groupedThreads(sideThreads))
                } else if mainThread == nil {
                    // 卡 18 纠正 3：无会话不留标签夹空带，
                    // 换新建入口行（主线钦定落位前才可能到这）
                    drawerPlainRow {
                        Button {
                            createThread()
                            onClose()
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingS) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(Palette.inkSecondary)
                                Text("新建会话")
                                    .font(.body)
                                    .foregroundStyle(Palette.ink)
                            }
                            .padding(.horizontal, OneDayMetrics.spacingS)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: OneDayMetrics.navRowHeight,
                                alignment: .leading
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                        .padding(.horizontal, OneDayMetrics.spacingSM)
                        .padding(.top, OneDayMetrics.spacingS)
                    }
                }
            }
            if !visibleServerSessions.isEmpty {
                // 第 10 修：与本地组之间同补发丝线（本
                // 地组在场时）；第 18 条：组名改人话——
                // 「服务端会话」是实现口径，改「其他会
                // 话」（这些是在别处开的会话，不是本机
                // 这台开的）
                if !drawerItems.isEmpty {
                    drawerDivider
                        .padding(.top, OneDayMetrics.spacingS)
                }
                drawerGroupHeader("其他会话")
                ForEach(visibleServerSessions) { session in
                    drawerServerSessionRow(session)
                }
            }
            if !isSearching {
                archivedZone
                // 契约文案（D3 呈现侧）：抽屉内写明旁聊
                // 的上下文与记忆口径，一行 footnote 收尾
                drawerPlainRow {
                    Text("旁聊各自独立上下文，记忆与任务全线共享。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        .padding(.horizontal, OneDayMetrics.drawerInset)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            drawerPlainRow {
                Color.clear
                    .frame(height: OneDayMetrics.spacingL)
            }
        }
    }

    /// 时间分组段落（组间发丝线＋组标题＋行列）：旁聊区
    /// 与搜索态共用同一渲染
    private func threadGroupSections(
        _ groups: [(label: String, threads: [ChatThread])]
    ) -> some View {
        ForEach(
            Array(groups.enumerated()),
            id: \.element.label
        ) { index, group in
            // 0.4.1 第 10 修：组间补发丝分隔线
            // （0.3.8 第 21 条的纯留白分段被用户
            // 逐项对比点名推翻——导航组与会话组
            // 之间、会话各组之间都要线，节奏与
            // 导航组下那条同式）
            if index > 0 {
                drawerDivider
                    .padding(.top, OneDayMetrics.spacingS)
            }
            drawerGroupHeader(group.label)
            ForEach(group.threads) { thread in
                drawerThreadRow(thread)
            }
        }
    }

    /// 「已归档」区（0.7.0，M2）：默认收起，点头展开；
    /// 本地归档行点按＝恢复并打开、长按可恢复/删除；
    /// 服务端归档行点按＝只恢复（不直接导入续聊）
    @ViewBuilder
    private var archivedZone: some View {
        let archivedCount = archivedLocalThreads.count + archivedServerSessions.count
        if archivedCount > 0 {
            drawerDivider
                .padding(.top, OneDayMetrics.spacingS)
            drawerPlainRow {
                Button {
                    showArchived.toggle()
                } label: {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text("已归档（\(archivedCount)）")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        Spacer()
                        Image(systemName: showArchived ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .padding(.horizontal, OneDayMetrics.drawerInset)
                    .padding(.top, OneDayMetrics.spacingSM)
                    .padding(.bottom, OneDayMetrics.spacingS)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
            }
            if showArchived {
                ForEach(archivedLocalThreads) { thread in
                    drawerArchivedThreadRow(thread)
                }
                ForEach(archivedServerSessions) { session in
                    drawerArchivedServerRow(session)
                }
            }
        }
    }

    /// 组标题行（0.3.6 立宪）：13 regular 次级灰标签，
    /// x 线 drawerInset 20。不用 SectionLabel——其 13
    /// medium 与宪法「字重只 regular/bold」冲突，全
    /// 局归 0.3.7 页面轮，壳内先行按宪法（§21.5）。
    private func drawerGroupHeader(_ label: String) -> some View {
        drawerPlainRow {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.horizontal, OneDayMetrics.drawerInset)
                .padding(.top, OneDayMetrics.spacingSM)
                .padding(.bottom, OneDayMetrics.spacingS)
        }
    }

    /// 会话组里的素行：padding 全部由内容自控（组标
    /// 题/空态/留白共用）。0.4.1 前是 List 行包装（零
    /// 行距/透明底/无分隔线的 listRow 三件套），List
    /// 退役后只剩内容本体
    private func drawerPlainRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
    }

    /// 本机会话分组（0.3.6）：纯逻辑下沉
    /// OneDayCore.SidebarGrouping（置顶＋时间五段，
    /// 单测把守），此处只做 ChatThread ↔ key 映射。
    /// 0.7.0 改入参制：搜索态喂全量可见名单（含主线）、
    /// 旁聊区喂剔除主线后的名单，两处共用同一分组口径
    private func groupedThreads(
        _ base: [ChatThread]
    ) -> [(label: String, threads: [ChatThread])] {
        let items = base.map {
            SidebarGrouping.Item(
                key: $0.id, updatedAt: $0.updatedAt, isPinned: $0.isPinned
            )
        }
        let byID = Dictionary(
            uniqueKeysWithValues: base.map { ($0.id, $0) }
        )
        return SidebarGrouping.groups(
            items: items, now: Date(), searching: isSearching
        ).map { group in
            (
                label: group.label,
                threads: group.keys.compactMap { byID[$0] }
            )
        }
    }

    private func drawerServerSessionRow(_ session: ServerSession) -> some View {
        Button {
            // 0.4.5 通道化：关抽屉归壳层、续聊改道归
            // AppState 通道（0.4.0 §3.4 链不变：Content-
            // View 切聊天格、ChatView 消费导入）
            onClose()
            appState.pendingChatSessionID = session.id
        } label: {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                // 标题只有内容名（人话 display_name→首条
                // 消息派生摘要→「未命名会话」，0.6.1 起派
                // 生经全局 SessionTitleResolver、与活动行
                // 同源），时间/条数/来源全在副题（0.6.1
                // 起副题不写「进行中」——ended_at 缺失下
                // 是假数据，见 SessionDisplay 文件头注）；
                // 0.3.8 第 18/19 条：副题改序（来源退尾）
                // 且与本地行同行型（标题 17 regular＋副
                // 题 13、行高 57 两行制）
                // 0.7.0（M3）：标题走合并管线——本地改名
                // 覆盖优先于派生（serverTitle）
                Text(serverTitle(session))
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(session.humanSubtitle(now: Date()))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            // 标题 x 线与本机会话行/组标题对齐（外 SM
            // 12＋内 S 8＝20＝drawerInset 线）
            .padding(.horizontal, OneDayMetrics.spacingS)
            .frame(
                maxWidth: .infinity,
                minHeight: OneDayMetrics.sessionRowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingSM)
        // 0.7.0：服务端旁聊长按菜单——打开续聊（与点按
        // 同链）/重命名（写本地覆盖表）/归档（本地隐藏，
        // 服务端本体不动）
        .contextMenu {
            Button {
                onClose()
                appState.pendingChatSessionID = session.id
            } label: {
                Label("打开续聊", systemImage: "bubble.left")
            }
            Button {
                beginRenameServerSession(session)
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button {
                appState.sideChats.archive(serverSessionID: session.id)
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }
    }

    /// 归档区服务端行（0.7.0，M2）：点按＝只恢复（回到
    /// 「其他会话」名单，不直接导入续聊）；长按同为恢复
    private func drawerArchivedServerRow(_ session: ServerSession) -> some View {
        Button {
            appState.sideChats.unarchive(serverSessionID: session.id)
        } label: {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(serverTitle(session))
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(session.humanSubtitle(now: Date()))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, OneDayMetrics.spacingS)
            .frame(
                maxWidth: .infinity,
                minHeight: OneDayMetrics.sessionRowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .contextMenu {
            Button {
                appState.sideChats.unarchive(serverSessionID: session.id)
            } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private func beginRenameServerSession(_ session: ServerSession) {
        serverRenameText = serverTitle(session)
        renamingServerSession = session
    }

    /// 服务端改名落本地覆盖表（M3 预案）：已建会话改
    /// title 未证实、不对服务端发改名请求
    private func commitRenameServerSession() {
        let title = serverRenameText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let session = renamingServerSession, !title.isEmpty {
            appState.sideChats.setTitleOverride(title, for: session.id)
        }
        renamingServerSession = nil
    }

    /// 「旁聊」小标识（0.7.0）：与聊天页标题行同画法——
    /// caption2＋fieldFill 胶囊垫，挂旁聊行标题后
    private var sideChatTag: some View {
        Text("旁聊")
            .font(.caption2)
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Palette.fieldFill, in: Capsule())
    }

    /// 本地行两行制标签（主线/旁聊/归档行共用）：标题
    /// 17 regular＋副题时间·条数、高 57；选中态＝
    /// selectionFill 整行浅灰垫（第 17 条裁决保留）、
    /// 标题不变色不加粗。0.7.0：主线标题恒「主聊」、
    /// 旁聊行标题后挂「旁聊」标识
    private func drawerThreadLabel(
        _ thread: ChatThread, isMain: Bool
    ) -> some View {
        let isCurrent = thread.id == appState.activeThreadID
        return VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            HStack(spacing: 6) {
                Text(isMain ? SideChatStore.mainTitle : thread.title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if !isMain {
                    sideChatTag
                }
            }
            Text(LocalThreadSubtitle.text(
                updatedAt: thread.updatedAt,
                messageCount: thread.entries.count,
                now: Date()
            ))
            .font(.footnote)
            .foregroundStyle(Palette.inkSecondary)
            .lineLimit(1)
        }
        .padding(.horizontal, OneDayMetrics.spacingS)
        .frame(
            maxWidth: .infinity,
            minHeight: OneDayMetrics.sessionRowHeight,
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

    /// 会话行（0.3.6 立宪，0.3.8 第 19 条改两行制）。
    /// 0.4.5 通道化：当前位读 AppState.activeThreadID
    /// （ChatView 回写）、点按经 drawerThreadSelection
    /// 请 ChatView 切换（本面不持有 currentThreadID）。
    /// 0.7.0：主线行受钦定保护——不可归档、不可删、
    /// 不可改名（UI 层约束：长按不出菜单）；旁聊行长按
    /// 菜单＝置顶/重命名/归档/删除
    private func drawerThreadRow(_ thread: ChatThread) -> some View {
        let isMain = thread.id == appState.sideChats.mainThreadID
        let row = Button {
            appState.drawerThreadSelection = thread.id
            onClose()
        } label: {
            drawerThreadLabel(thread, isMain: isMain)
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingSM)

        return Group {
            if isMain {
                row
            } else {
                row.contextMenu {
                    Button {
                        togglePinThread(thread)
                    } label: {
                        Label(
                            thread.isPinned ? "取消置顶" : "置顶",
                            systemImage: thread.isPinned ? "pin.slash" : "pin"
                        )
                    }
                    Button {
                        beginRenameThread(thread)
                    } label: {
                        Label("重命名", systemImage: "pencil")
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
        }
    }

    /// 归档区本地行（0.7.0，M2）：点按＝恢复并打开；
    /// 长按＝恢复/删除
    private func drawerArchivedThreadRow(_ thread: ChatThread) -> some View {
        Button {
            appState.sideChats.unarchive(localThreadID: thread.id)
            appState.drawerThreadSelection = thread.id
            onClose()
        } label: {
            drawerThreadLabel(thread, isMain: false)
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .contextMenu {
            Button {
                appState.sideChats.unarchive(localThreadID: thread.id)
            } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
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
        // 0.3.2：删除确认不再挂触觉（只挂结果事件，见 Haptics 注）
        // 0.4.5 通道化：删的若是 ChatView 正在显示的线
        // 程，经 drawerDeletedThreadID 通知它置空当前
        // 线程（本面不持有 currentThreadID）
        if thread.id == appState.activeThreadID {
            appState.drawerDeletedThreadID = thread.id
        }
        modelContext.delete(thread)
        try? modelContext.save()
    }
}
