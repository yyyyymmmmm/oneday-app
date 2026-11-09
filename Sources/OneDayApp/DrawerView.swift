import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 抽屉（侧边栏）。历史三代名单形态（覆盖 peek→推式页
/// 卡→覆盖层）之后，0.19.0 照 Muse 本体侧边栏整面重
/// 构为**纯导航形态**（用户 2026-11-09 22:26 真机点
/// 名，附 Muse 侧边栏样板图）：
///
/// - 顶部名字头（28 bold）之下只有两组：导航行组
///   （对样板「选项卡」：主线聊天／枢纽／点子／目标／
///   应用）＋「管理全部对话」一行——**对话名单整段退
///   役**：主线区/站内区/今天分组/已归档区、会话行、
///   行尾时间、旁聊角标、分区标签、契约文案一律不再
///   出现在抽屉里；对话今后只在管理页找与管（数据本
///   体 SideChatStore/AllConversationsStore 不动、管
///   理页全量可用如旧）。本面自此不持有任何名单数
///   据、开抽屉零网络拉取（旧 onChange/onAppear 两路
///   拉取与本地线程 @Query 一并退役）。
/// - 0.6.1 曾以「与底栏逐项重复」删过同类导航组
///   （抽屉回归名单单一职责）；0.19.0 用户对着 Muse
///   样板亲口改令（导航留下、名单删掉），新令覆盖旧
///   裁决，此注为据。
/// - 底条三件套保留（齿轮圆钮＋搜索胶囊＋新聊圆
///   钮）：搜索胶囊随名单退役改行为——点它进管理页
///   并聚焦其搜索（.searchable 呈现），不留搜空气的
///   假搜索（旧本地过滤 TextField 退役）；下边距改
///   固定 4（0.19.0 拆双计，见 drawerBottomBar 注）。
/// - 承载沿 0.17.0：壳层（ContentView.DrawerShell）
///   以覆盖形态自左滑入盖在静止内容之上，本面根
///   ScrollView＋头尾 safeAreaBar 注册结构不变（名单
///   退役后内容不足一屏、ScrollView 只作承载骨架，
///   滚动实际不发生）；头尾固定实色条是 0.6.1「两端
///   E11 带全删」后的定式：名单从实色条下方滑过被
///   遮、条面与面板同色一贯，不许再挂任何自绘渐变
///   带/模糊层（E11 已注销）。
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
    /// 打开「全部对话」管理页（0.18.0；0.19.0 加参：
    /// true＝打开时聚焦其搜索，底条搜索胶囊用；本面
    /// 先经 onClose 关抽屉，ContentView 注入呈现）
    var onManageAll: (Bool) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            drawerNavList
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

    /// 导航组＋管理行：对 Muse 样板的结构——「选项
    /// 卡」组五行为全抽屉的导航面，其下发丝线＋「管
    /// 理全部对话」一行（对话只在管理页找/管）
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
            // 名单退役后内容短，尾留白只留一档（旧名单
            // 时代的尾 spacingL 是给长名单收尾的）
            Color.clear
                .frame(height: OneDayMetrics.spacingM)
        }
        .padding(.top, OneDayMetrics.spacingS)
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
            onManageAll(false)
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
    /// （左设置/右新建）＋中间同高搜索胶囊。
    /// 0.19.0 两改：①搜索胶囊由本地过滤 TextField 改
    /// 按钮——名单已不在抽屉，点它进管理页并聚焦其搜
    /// 索（观感与旧胶囊同：glass＋发丝边＋柔影）；
    /// ②下边距拆双计改固定 4——0.4.5 手算口径（壳层
    /// 量测的窗口底 inset＋4＝约 38pt）的前提是推式时
    /// 代「名单 ScrollView ignoresSafeArea(.bottom) 后
    /// safeAreaBar 的代抬消失」；0.17.0 覆盖承载下本条
    /// 是系统注册 bar（与顶条同结构、无人给顶条手算
    /// 过、从无此病），bar 内容本就停在安全区线之上，
    /// 再叠手算等于把 home indicator 段算两遍——真机
    /// 底条之下死白一大坨（用户 22:26 截图）的可证一
    /// 段即此。拆后落点与注册 bar 时代（0.4.2–0.4.4）
    /// 的固定 4pt 一致：底条底缘停在 indicator 线上
    /// 方 4pt、照 Muse 样板贴底；壳层量测的 bottom-
    /// SafeInset 入参随之退役（DrawerGeometry 的量测
    /// 纯函数本体保留作口径档案、单测继续把守）
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
            Button {
                onClose()
                onManageAll(true)
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                    Text("搜索会话")
                        .font(.body)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .frame(maxWidth: .infinity)
                .frame(height: OneDayMetrics.drawerBarButton)
                // 玻璃＋发丝边＋轻柔影与旧搜索胶囊、圆钮
                // 同式（玻璃施加于件本体、内容在其上）
                .glassEffect(.regular, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Palette.hairline, lineWidth: 0.5)
                }
                .shadow(
                    color: Palette.shadowBase.opacity(0.06),
                    radius: 8, y: 2
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("搜索会话")
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
