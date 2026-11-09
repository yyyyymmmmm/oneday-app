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
/// 头尾 safeAreaBar 钉住＋E11 两端模糊带＋名单/搜索/底条，
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
    /// 窗口底部安全区 inset（壳层 GeometryReader 给）：
    /// 名单 ScrollView 已 ignoresSafeArea(.bottom)、安
    /// 全区不再代抬底条，下边距与底缘模糊带据此手算
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
    /// 服务端会话组的数据（开抽屉时拉取）
    @State private var drawerServerSessions: [ServerSession] = []

    var body: some View {
        // 头尾钉住＋中段滚动（0.4.2，用户 10:54 对照
        // Muse 本体标注图纠正，取代 0.4.1 的整栏全滚
        // 读法）：智能体名区不滚、底条（齿轮/搜索/新建）
        // 不滚、只有中间名单区滚动，且滚动内容滑到头
        // 尾两端时朦胧渐隐。结构：名单 ScrollView 居中，
        // 名字与底条经 safeAreaBar 钉进它的上下安全区
        // ——与聊天页发送舱同一系统通道（条即安全区、
        // 内容从其下方滑过），上下两缘的化开由
        // .scrollEdgeEffectStyle(.soft)＋E11 模糊带承担。
        // 头尾两区不设自有背景：透出的就是面板底色
        // （#FCFCFC，§26 第 10 修量测口径不变）
        ScrollView {
            VStack(spacing: 0) {
                drawerNavList
                drawerList
            }
        }
        // 0.4.5（§30，用户 11:47 点名）：名单向下穿过
        // 底部安全区直达屏幕底边——样板里名单尾行在
        // 底条下方继续渐隐到屏边、没有死白条；旧承载
        // 下 ScrollView 帧止于安全区、底条下方留 34pt
        // 许的纯面板色带。代价是安全区不再代抬底条：
        // 底条下边距改手算（见 drawerBottomBar）、底
        // 缘 E11 带随之向下延长到屏边（见彼处注）
        .ignoresSafeArea(edges: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // 0.4.3（§28.5）：头尾承载走 safeAreaBar 注册
        // ——未注册的 inset 条不在边缘效果系统内、
        // .soft 等于没发；注册后内容从头尾下方穿过
        // 并在两端化开（用户 10:54 标注口径）
        .safeAreaBar(edge: .top, spacing: 0) {
            drawerAgentName
                // 0.4.4（§29，例外 E11）：抽屉顶缘渐进
                // 模糊层——作名字区 background 上探状态
                // 区 56pt、向下延进名单约 35pt，名单滑
                // 到名字下方先化开（组件与几何口径见
                // EdgeProgressiveBlur）
                .background(alignment: .top) {
                    EdgeProgressiveBlur(stops: EdgeProgressiveBlur.drawerTop)
                        .frame(height: 150)
                        .offset(y: -56)
                        .allowsHitTesting(false)
                }
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            drawerBottomBar
                // 0.4.4（§29，例外 E11）＋0.4.5 延长：
                // 底缘带作底条 background 向上延约 68pt
                // 化开名单（0.4.4 口径不变），0.4.5 起
                // 带底随底条落到屏幕底边——带长补上底
                // 条下边距段（安全区 inset＋4），名单在
                // 底条下方、home indicator 区里继续被
                // 满模糊盖住渐隐到屏边（用户 11:47 点
                // 名）；停点按绝对锚重算、带顶的化开形
                // 态与 0.4.4 逐点一致（见 EdgeProgress-
                // iveBlur.drawerBottom(bandHeight:)）
                .background(alignment: .bottom) {
                    EdgeProgressiveBlur(stops: EdgeProgressiveBlur.drawerBottom(
                        bandHeight: Double(124 + bottomSafeInset + 4)
                    ))
                    .frame(height: 124 + bottomSafeInset + 4)
                    .allowsHitTesting(false)
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
        // 开抽屉时拉服务端会话组（0.4.4 前挂 ChatView
        // 的 drawerOpen onChange；0.4.5 起抽屉自理，
        // 信号源＝壳层维护的语义开合状态 drawerPresented）
        .onChange(of: appState.drawerPresented) { _, presented in
            if presented {
                Task { await loadDrawerData() }
            }
        }
    }

    /// 栏内顶部（0.3.6 立宪，§21.3）：只有智能体名字
    /// （28 bold）——状态点＋状态词·模型小字全撤（定
    /// 义卡删减清单：那是管理面信息，不占导航壳第一眼）
    private var drawerAgentName: some View {
        Text("Hermes")
            .font(.largeTitle)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.drawerInset)
            .padding(.top, OneDayMetrics.spacingL)
            .padding(.bottom, OneDayMetrics.spacingSM)
    }

    private func loadDrawerData() async {
        if let page = try? await appState.performAdmin({ client, config in
            try await client.serverSessions(config: config, limit: 6)
        }) {
            drawerServerSessions = page.sessions
        }
    }

    /// 全局名单（0.3.6 立宪先行件，§21.3；定义卡：一
    /// 页一事——名单只做切目的地）：与底栏五格一一对
    /// 应、同一符号源（TabBarSymbols）；行高约 47、
    /// 只有图标＋标题（无箭头无值）；当前位（本面锚定
    /// 聊天格）以 selectionFill 浅灰垫标示、不变色不
    /// 加粗。名单末尾一条发丝线与会话组分界。
    private var drawerNavList: some View {
        VStack(spacing: 0) {
            // 0.3.8 第 20 条：导航区补分组标签（与会话区
            // 的时间分组标签同一形态：13 regular 次级灰）
            Text("选项卡")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OneDayMetrics.drawerInset)
                .padding(.top, OneDayMetrics.spacingSM)
                .padding(.bottom, OneDayMetrics.spacingS)
            ForEach(drawerTabs, id: \.pair.id) { item in
                drawerNavRow(tab: item.tab, pair: item.pair)
            }
            // 第 21 条：发丝线只留功能区之间（导航↔会话
            // 这一条保留；会话组之间已改纯留白分段）
            drawerDivider
                .padding(.top, OneDayMetrics.spacingS)
        }
    }

    private var drawerTabs: [(tab: ContentView.MainTab, pair: TabSymbolPair)] {
        [
            (.chat, TabBarSymbols.chat),
            (.activity, TabBarSymbols.activity),
            (.ideas, TabBarSymbols.ideas),
            (.goals, TabBarSymbols.goals),
            (.apps, TabBarSymbols.apps),
        ]
    }

    private func drawerNavRow(
        tab: ContentView.MainTab, pair: TabSymbolPair
    ) -> some View {
        let isCurrent = tab == currentTab
        return Button {
            onClose()
            if !isCurrent { onSelectTab(tab) }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: pair.normal)
                    // 0.3.8 第 15 条：名单字形与底栏同线宽
                    // 档——21 无字重 → 18 regular（令牌
                    // FrameworkIcon.drawerGlyphSize；0.3.7
                    // 实测对话 27.6%/文件夹 19.6% 线宽不齐）
                    .font(.system(
                        size: FrameworkIcon.drawerGlyphSize,
                        weight: .regular
                    ))
                    .foregroundStyle(Palette.ink)
                    .frame(
                        width: OneDayMetrics.spacingL,
                        alignment: .leading
                    )
                    .accessibilityHidden(true)
                Text(pair.title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.navRowHeight)
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
        .accessibilityLabel(pair.title)
    }

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

    /// 侧边栏会话组（0.3.6 立，§21.3/§21.4；0.4.1 改
    /// 承载）：只产出素行内容（组标题/会话行/空态/尾
    /// 留白，x 线全自控），直排进面板 ScrollView 的同
    /// 一 VStack。会话行长按菜单＝置顶/重命名/删除三
    /// 件套。分组＝灰标签＋留白（0.3.8 第 21 条后组间
    /// 不划线——0.4.1 第 10 修又逐项补回发丝线，见下）
    /// 服务端会话组在尾（0.4.0 起点行改道聊天页续聊、
    /// 标题人话化）。
    private var drawerList: some View {
        VStack(spacing: 0) {
            if filteredThreads.isEmpty {
                if drawerQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    // 卡 18 纠正 3：无会话不留标签夹空带，
                    // 换新建入口行
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
                } else {
                    drawerPlainRow {
                        Text("没有匹配的会话")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkMuted)
                            .padding(.horizontal, OneDayMetrics.drawerInset)
                            .padding(.top, OneDayMetrics.spacingL)
                    }
                }
            } else {
                ForEach(
                    Array(threadGroups.enumerated()),
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
            if !drawerServerSessions.isEmpty {
                // 第 10 修：与本地组之间同补发丝线（本
                // 地组在场时）；第 18 条：组名改人话——
                // 「服务端会话」是实现口径，改「其他会
                // 话」（这些是在别处开的会话，不是本机
                // 这台开的）
                if !filteredThreads.isEmpty {
                    drawerDivider
                        .padding(.top, OneDayMetrics.spacingS)
                }
                drawerGroupHeader("其他会话")
                ForEach(drawerServerSessions) { session in
                    drawerServerSessionRow(session)
                }
            }
            drawerPlainRow {
                Color.clear
                    .frame(height: OneDayMetrics.spacingL)
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
    private var threadGroups: [(label: String, threads: [ChatThread])] {
        let searching = !drawerQuery
            .trimmingCharacters(in: .whitespaces).isEmpty
        let items = filteredThreads.map {
            SidebarGrouping.Item(
                key: $0.id, updatedAt: $0.updatedAt, isPinned: $0.isPinned
            )
        }
        let byID = Dictionary(
            uniqueKeysWithValues: filteredThreads.map { ($0.id, $0) }
        )
        return SidebarGrouping.groups(
            items: items, now: Date(), searching: searching
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
                // 标题只有内容名（人话 display_name/内容
                // 摘要，否则「未命名会话」），时间/条数/状
                // 态/来源全在副题——SessionDisplay 同源；
                // 0.3.8 第 18/19 条：副题改序（来源退尾、
                // 状态只写属实）且与本地行同行型（标题
                // 17 regular＋副题 13、行高 57 两行制）
                Text(session.humanTitle)
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
    }

    /// 会话行（0.3.6 立宪，0.3.8 第 19 条改两行制）：
    /// 标题 17 regular＋副题时间·条数、高 57；选中态
    /// ＝selectionFill 整行浅灰垫（第 17 条裁决保留）、
    /// 标题不变色不加粗。长按菜单＝置顶/重命名/删除。
    /// 0.4.5 通道化：当前位读 AppState.activeThreadID
    /// （ChatView 回写）、点按经 drawerThreadSelection
    /// 请 ChatView 切换（本面不持有 currentThreadID）
    private func drawerThreadRow(_ thread: ChatThread) -> some View {
        let isCurrent = thread.id == appState.activeThreadID
        return Button {
            appState.drawerThreadSelection = thread.id
            onClose()
        } label: {
            // 0.3.8 第 19 条：本地行与服务端行统一两行制
            // （标题 17 regular＋副题「时间 · 条数」13 灰、
            // 行高 57）；选中整行浅灰填充保留（第 17 条
            // 用户裁决：保留灰块不改）
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(thread.title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
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
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .contextMenu {
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
