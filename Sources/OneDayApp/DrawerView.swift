import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 抽屉（侧边栏）。0.36.3：面板底由纯色实板改系
/// 统朦胧材质（用户 18:31 点名，详见 body 内注）。
/// 0.19.0 照 Muse 本体侧边栏重构，
/// 当日两轮口径（用户 2026-11-09 22:26 首令＋22:45
/// 纠正，现行以纠正为准）：
///
/// - 结构：顶部名字头（28 bold）→导航行组（对样板
///   「选项卡」：主线聊天／动态／点子／目标／文件，
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
/// - 0.36.29（频道规格 §3）：管理行与旁聊区之间插
///   「频道」区（一期只有 Hermes 一行，分类后频道
///   会话 ≥1 才整区显示、空态整区收起）；数据源复
///   用开抽屉既有那一路拉取现算 Core 分类，不新增
///   拉取；频道行不给计数徽标（口径见 drawerChannel-
///   Row 注）。
/// - 承载沿 0.17.0：壳层（ContentView.DrawerShell）
///   以覆盖形态自左滑入盖在静止内容之上，本面根
///   ScrollView＋头尾 safeAreaBar 注册结构不变；头
///   尾固定实色条是 0.6.1「两端 E11 带全删」后的定
///   式：内容从实色条下方滑过被遮、条面与面板同色
///   一贯，不许再挂任何自绘渐变带/模糊层（E11 已
///   注销）。（0.36.5 订正：底条 0.20.0 已改浮置、
///   顶 safeAreaBar 注册本版整块取消——标题改浮
///   层、只有文字本体，见 body 内 D3 注；本段与
///   下文 0.20.0 注中「顶条维持实色注册」只存沿革。
///   0.36.27 再订正：底条浮置＋霜层退役、改注册名
///   单 safeAreaBar 走纯系统朦胧，见 body 内注。）
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
    /// 打开频道页（0.36.29，频道规格 §3）：频道行
    /// 点按先经 onClose 关抽屉，ContentView 注入呈
    /// 现；入参为频道 id（一期只有 Hermes）
    var onOpenChannel: (String) -> Void

    /// 顶部标题带高（0.36.5）：名单顶部空程
    /// （contentMargins）与标题浮层共用一数——
    /// drawerAgentName 的顶距 24＋Title1 行高约
    /// 34＋底距 12＝70。Dynamic Type 极端档下行
    /// 高变大、静止时首行可能被标题略压（已知边
    /// 界，待真机）
    private static let titleStripHeight: CGFloat = 70

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    /// 减透明（0.23.0）：面板底 drawerBackdrop 的实
    /// 色回退读它（经 Core TransparencyFallback 裁
    /// 决）；底条霜层的那路已于 0.36.27 随霜层删除
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Query(sort: \ChatThread.updatedAt, order: .reverse)
    private var threads: [ChatThread]
    /// 底条搜索词（本地过滤旁聊区，22:45 纠正后恢复
    /// 0.18.0 抽屉搜索口径）
    @State private var drawerQuery = ""
    /// 服务端会话 source 映射（会话 id→source）：只
    /// 喂旁聊行显的来源过滤判定，不作名单数据源；
    /// 拉不到为空表（本地行恒放行）
    @State private var drawerServerSources: [String: String] = [:]
    /// 服务端会话本体映射（会话 id→ServerSession，
    /// 0.20.0 第三条）：旁聊行标题解析取服务端 AI 标
    /// 题用（DrawerThreadTitle）；与 source 映射同次
    /// 拉取同批落位，拉不到为空表（行标题回落本地）
    @State private var drawerServerSessions: [String: ServerSession] = [:]
    /// 本地旁聊行重命名（长按四件之一，0.18.0 沿革）
    @State private var renamingThread: ChatThread?
    @State private var renameText = ""

    var body: some View {
        // 0.36.27（§97 件三，用户 03:54 拍板「抽屉朦
        // 胧与聊天页一样走纯系统路线比较好点」）：底
        // 条改注册为名单 ScrollView 的 .safeAreaBar
        // (edge: .bottom)——与聊天页发送舱同构，朦胧
        // 由名单 .scrollEdgeEffectStyle(.soft, for:
        // .bottom) 在注册栏高内发放，零自绘。0.20.0
        // 的浮置构造（ZStack 浮置＋ultraThinMaterial
        // 霜层＋LinearGradient 渐隐 mask＋霜层实色回
        // 退分支）整套退役；名单 .ignoresSafeArea
        // (.bottom) 与手排末行避让（padding 84）随之
        // 退役，末行避让改由注册留位＋contentMargins
        // 底 8 承接。底条三件本体与落点（indicator
        // 线上方 4pt）不变、不给注册 bar 自加 back-
        // ground（WWDC25-323 口径）；顶部标题浮层不
        // 动（0.36.5 定版）。Reduce Transparency 下
        // 边缘效果由系统自理（系统自动增不透明），
        // 霜层时代的手排实色回退随霜层一并删除（理
        // 由见 DESIGN §97.3）
        ZStack(alignment: .bottom) {
            // 0.36.5（D2，用户实拍右缘贯穿长线）：长线
            // 即名单 ScrollView 的默认滚动指示器——关
            // 掉。壳层与本面已查：右缘只有壳层柔影、
            // 无描边/分隔视图，长线来源唯一在此。口
            // 径：Muse 抽屉无边线，与内容只靠材质＋
            // 蒙层分界
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if isSearching {
                        drawerSearchList
                    } else {
                        drawerNavList
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 0.36.27：手排末行避让（padding 84）退
                // 役——改由下方 safeAreaBar 注册留位（条
                // 高 68）＋contentMargins 底 8 承接
            }
            // 0.36.5（D3，用户 19:27 对照 Muse 本体
            // 抽屉实拍纠正，覆盖顶带「统一材质」口
            // 径）：顶部标题带整块取消——safeAreaBar
            // 注册退役。原实色带来自两处：①该注册把
            // 标题锁进一块独立带、下方名单滚不到带
            // 下，带与主体天然有界；②0.36.3 给带内
            // 名字单挂一层 drawerBackdrop，与根背景
            // 的同名材质叠成双层、带面比主体更实更
            // 灰，断层雪上加霜。现落法：标题只剩文
            // 字本体（下方浮层）、固定悬于根背景同
            // 一层材质之上；名单顶部留标题带高的空
            // 程（contentMargins）——静止时首行不被
            // 标题压住，滚动时行从标题后方穿过、隐
            // 约透出（Muse 本体同形态）
            .contentMargins(
                .top, Self.titleStripHeight, for: .scrollContent
            )
            // 0.36.27：末行与注册底条之间留一档小间隙
            // （与聊天页列表底口径同式）；注册留位之外
            // 本面唯一的底部手排数
            .contentMargins(
                .bottom, OneDayMetrics.spacingS, for: .scrollContent
            )
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // 0.36.27（§97 件三）：底条注册（与聊天页
            // bottomBar 同挂法）——搜索态与普通态两套
            // 名单共用本 ScrollView，注册只此一处、两
            // 态一致
            .safeAreaBar(edge: .bottom) {
                drawerBottomBar
            }
            // 标题浮层：ZStack 顶＝安全区顶（状态栏
            // 之下），只有文字、无底块无色带；不承
            // 命中——标题区拖动归名单/壳层手势
            VStack {
                drawerAgentName
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        // 面板底穿过上下安全区（0.4.1 第 10 修沿革：
        // 顶边贴到屏幕顶、底边直达屏底，形态不变）
        // 0.36.3（用户 18:31 点名）：底由纯色实板改
        // 系统朦胧材质——对照 Muse 抽屉参考图：整面
        // 磨砂、后面聊天内容隐约透出、标题与行直接浮
        // 于材质上。只用系统材质 API（thinMaterial）；
        // Reduce Transparency 时经 Core 裁决落实色面
        // （chatSurface 同档；底条霜层的那路回退已于
        // 0.36.27 随霜层删除，此处只剩面板底本路）。
        // 私有 variableBlur 永不碰（E11 已注销）
        .background {
            drawerBackdrop
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
        // 0.21.0 标题回流触发点补环：App 回前台重拉
        // （切后台期间服务端标题可能已升级；此前注
        // 释自称「开抽屉/回前台」实则只有开抽屉一
        // 路，本版坐实）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await loadDrawerData() }
            }
        }
        // 0.21.0：已链接旁聊一轮落地后的刷新令牌
        // （完成即时＋6 秒延迟，见 AppState）——抽屉
        // 挂载期间标题实时跟上，未挂载时下次 onAppear
        // /开抽屉的既有拉取兜底
        .onChange(of: appState.drawerRefreshTick) {
            Task { await loadDrawerData() }
        }
    }

    /// 抽屉底（0.36.3）：系统 thinMaterial 朦胧面；
    /// Reduce Transparency 开启时经 Core
    /// TransparencyFallback 裁决落实色（chatSurface
    /// 与旧实板同档），面板与顶条共用同一底、整面
    /// 一贯。深浅双档由材质本体随系统呈现
    @ViewBuilder
    private var drawerBackdrop: some View {
        if TransparencyFallback.surface(
            reduceTransparency: reduceTransparency
        ) == .solid {
            Palette.chatSurface
        } else {
            Rectangle().fill(.thinMaterial)
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
            // 0.20.0 第三条：同批落本体映射，旁聊行标
            // 题解析（drawerDisplayTitle）取服务端标题
            drawerServerSessions = Dictionary(
                uniqueKeysWithValues: page.sessions.map {
                    ($0.id, $0)
                }
            )
        }
    }

    /// 旁聊行显示名（0.20.0 第三条）：本地线程已关联
    /// 服务端会话时走 DrawerThreadTitle 解析（手改名
    /// ＞服务端 AI 标题＞本地派生快照）——开抽屉/
    /// 回前台拉到的服务端标题经 drawerServerSessions
    /// 实时参与呈现，服务端改名/新生成标题下次开抽屉
    /// 即跟上；未关联的纯本地线程 serverTitle 恒 nil、
    /// 原样回落本地标题
    private func drawerDisplayTitle(for thread: ChatThread) -> String {
        DrawerThreadTitle.resolve(
            localTitle: thread.title,
            titleIsManual: thread.titleIsManual,
            serverTitle: thread.serverSessionID.flatMap {
                drawerServerSessions[$0]?.cleanedServerTitle
            }
        )
    }

    /// 栏内顶部（0.3.6 立宪，§21.3）：只有智能体名字
    /// （28 bold）——状态点＋状态词·模型小字全撤（定
    /// 义卡删减清单：那是管理面信息，不占导航壳第一眼）
    private var drawerAgentName: some View {
        // 0.36.22：名字头收敛档案出口（改名此处同步）
        Text(appState.agentDisplayName)
            // 0.20.0（第二条，Muse 抽屉图推算）：名字头
            // 升 34pt——图中状态栏高约 54pt 为锚、名字
            // 字形 cap 高约 34pt（推算表见 §47）；0.17.0
            // 的 28 bold 让位
            // 0.22.0（用户 00:29 并排图点名「Hermes 粗黑
            // 压人」）：字号 34 不动（推算锚只定字号）、
            // 字重 bold→semibold 降一档——参考图「三狗」
            // 同为大标题而笔画克制，SF bold 的拉丁字面
            // 渲染近黑体级、正是压人来源；取舍记 §49
            // 0.23.0：落字阶角色 screenName（largeTitle
            // semibold，默认 34 与定版等值、随 Dynamic
            // Type 缩放，审计 G2/D1）
            // 0.24.0（用户当日指令，口径变更）：角色改
            // Title1 28 bold——HIG 大标题档；34 semibold
            // 的 Muse 量测口径让位（见 §51）
            .font(.screenName)
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
                // 0.36.7：本行在单一政策里是主线会话的
                // 代表行——只有「正在看主线」时带胶囊，
                // 不再是「人在聊天表面」的指示（§10.2）
                selected: drawerSelection == .main
            ) {
                onClose()
                // 0.30.0（用户 12:56 录屏点名 Muse 模
                // 型）：本行是显式回主线的唯一入口——经
                // 线程选择通道直切钦定主线（ChatView 消
                // 费切换、并经落点记忆落盘）；底部页签本
                // 身不再承担回主线语义（点页签回上次对
                // 话，见 ChatLandingResolution）。钦定尚
                // 未落定时只切页签，ChatView 落点解析会
                // 以主线兜底
                if let mainID = appState.sideChats.mainThreadID {
                    appState.drawerThreadSelection = mainID
                }
                // 0.36.7（§10.3 置位纪律）：导航动作显
                // 式写当前对象引用，胶囊随点按即归主线
                // 0.36.29：回主线即离频道出处（§10.3
                // 置位点清零），防残留出处把后续同步带
                // 回 .channel
                appState.channelViewingOrigin = nil
                appState.currentDrawerObject = .main
                onSelectTab(.chat)
            }
            // 枢纽行已删（0.36.5，用户 19:24 点名）：
            // 枢纽 sheet 本体长在聊天页，删行后的入口
            // ＝聊天页身份胶囊点按与回告卡点按（均直
            // 接置 showHub）；hubOpenRequested 请求通
            // 道保留不动（ChatView 消费端在原处）
            // 0.35.0（P3 五格）：动态行与底栏同序进
            // 「选项卡」组
            drawerNavRow(
                symbol: TabBarSymbols.feed.normal,
                title: "动态",
                selected: drawerSelection == .surface(.feed)
            ) {
                onClose()
                onSelectTab(.feed)
            }
            drawerNavRow(
                symbol: TabBarSymbols.ideas.normal,
                title: "点子",
                selected: drawerSelection == .surface(.ideas)
            ) {
                onClose()
                onSelectTab(.ideas)
            }
            drawerNavRow(
                symbol: TabBarSymbols.goals.normal,
                title: "目标",
                selected: drawerSelection == .surface(.goals)
            ) {
                onClose()
                onSelectTab(.goals)
            }
            drawerNavRow(
                // 0.20.0 第七条：应用格改文件格，导航行
                // 同步改「文件」（符号与底栏同源 files 对）
                symbol: TabBarSymbols.files.normal,
                title: "文件",
                selected: drawerSelection == .surface(.files)
            ) {
                onClose()
                onSelectTab(.files)
            }
            drawerDivider
                .padding(.top, OneDayMetrics.spacingS)
            drawerManageRow
            // 0.36.29（频道规格 §3.1）：频道区插在管
            // 理行与旁聊区之间（面先于条，与 Muse 样
            // 板同序）；整区空态不显示——无频道行时
            // 分区头与其下发丝线一并收起，不留空头
            if hermesChannelVisible {
                drawerDivider
                    .padding(.top, OneDayMetrics.spacingS)
                drawerChannelSection
            }
            drawerDivider
                .padding(.top, OneDayMetrics.spacingS)
            drawerSideSection
            Color.clear
                .frame(height: OneDayMetrics.spacingL)
        }
        .padding(.top, OneDayMetrics.spacingS)
    }

    // MARK: - 频道区（0.36.29，频道规格 §3）

    /// 抽屉数据源的分类分筐：复用开抽屉既有那一路
    /// 拉取（drawerServerSessions，limit 100）现算，
    /// 不为频道区新增拉取（规格 §3.3「开抽屉只拉一
    /// 路」纪律）；本地关联集走 ThreadLinkage 与频
    /// 道页/管理页同一派生
    private var drawerPartition: SessionPartition {
        SessionClassifier.partition(
            sessions: Array(drawerServerSessions.values),
            mainServerSessionID: appState.sideChats.mainServerSessionID,
            linkedThreadSessionIDs: ThreadLinkage.nonMainLinkedSessionIDs(
                threads: threads, sideChats: appState.sideChats
            )
        )
    }

    /// Hermes 行显行条件（规格 §3.1）：分类后 Hermes
    /// 频道会话数 ≥ 1（合并桶计入频道成员）才显整
    /// 区；超 limit 100 的漏判是已知边界（规格
    /// §8-5），只影响呈现、不影响数据
    private var hermesChannelVisible: Bool {
        drawerPartition.hermesChannelCount >= 1
    }

    /// 频道区：一期只有 Hermes 一行（注册表派生，
    /// 外部频道未通不占位——通一个显一个）
    @ViewBuilder
    private var drawerChannelSection: some View {
        drawerGroupHeader("频道")
        ForEach(ChannelRegistry.phaseOne) { channel in
            drawerChannelRow(channel)
        }
    }

    /// 频道行（规格 §3.2）：沿导航行档（图标槽＋标
    /// 题 Body 17＋drawerRowHeight），行尾 chevron
    /// 示「进去是一个面」；**不给计数徽标**（抽屉拉
    /// 取口径与全量不一致，挂数即埋假新鲜，S7 纪
    /// 律）；图标用注册表资产（Hermes＝0.36.3 登记
    /// 的本机服务定制图面 LocalHermes）；选中态问
    /// 单一选择政策（.channel 命中才带胶囊）
    private func drawerChannelRow(_ channel: ChannelDescriptor) -> some View {
        let selected = drawerSelection == .channel(channel.id)
        return Button {
            onClose()
            onOpenChannel(channel.id)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Group {
                    if let asset = channel.iconAssetName {
                        Image(asset)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(
                                size: FrameworkIcon.drawerGlyphSize,
                                weight: .regular
                            ))
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(
                    width: OneDayMetrics.iconSlot,
                    height: OneDayMetrics.iconSlot
                )
                .accessibilityHidden(true)
                Text(channel.name)
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OneDayMetrics.drawerRowHeight)
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
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingS)
        .accessibilityLabel(channel.name)
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
                .foregroundStyle(Palette.inkSecondary)
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
                    .foregroundStyle(Palette.inkSecondary)
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

    /// 抽屉单一选择（0.36.7，频道规格 §10）：全抽屉
    /// 胶囊只许出自 Core 单一政策——当前表面（壳层
    /// 回写的 currentTab）＋当前对象引用（AppState，
    /// 导航动作与 ChatView 同步置位）两入参，任何行
    /// 不得再私读页签/线程 id 自画胶囊（旧双源即双
    /// 胶囊同框的 bug 本体）。落点派生在 ChatView 同
    /// 步点已完成（引用恒新），此处 landing 传 nil
    private var drawerSelection: DrawerSelection<ContentView.MainTab> {
        DrawerSelectionPolicy.resolve(
            currentTab: currentTab,
            chatTab: .chat,
            currentObject: appState.currentDrawerObject,
            landingThreadID: nil,
            mainThreadID: appState.sideChats.mainThreadID
        )
    }

    /// 搜索过滤（0.18.0 口径原样）：标题或任一条目内
    /// 容包含搜索词（不区分大小写）；非搜索态恒全量
    private var filteredThreads: [ChatThread] {
        let query = drawerQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return threads }
        return threads.filter { thread in
            // 0.20.0：搜索按显示名匹配（AI 标题回流后用
            // 户看到什么名就能搜到什么名）
            drawerDisplayTitle(for: thread)
                .localizedCaseInsensitiveContains(query)
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
    /// 平台源的导入线程不显示；来源未知恒放行）。
    /// 0.29.0：主线判定改走 Core 单一函数 SideChat-
    /// Classifier.isMain 双信号（钦定 id＋主线会话绑
    /// 定）——旧单信号只认钦定 id，钦定丢失/指向他
    /// 条时绑着主线会话的真主线对话会漏进本区（用
    /// 户 12:31 点名「主线聊天不需要出现在旁聊里
    /// 面」）；搜索态名单与本区同一行源、自动同口径
    private var sideThreads: [ChatThread] {
        drawerItems.filter { thread in
            DrawerSideChatFilter.threadListed(
                isMainThread: SideChatClassifier.isMain(
                    localThreadID: thread.id,
                    linkedServerSessionID: thread.serverSessionID,
                    mainThreadID: appState.sideChats.mainThreadID,
                    mainServerSessionID: appState.sideChats
                        .mainServerSessionID
                ),
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
        // 0.36.7：当前位只认单一政策（§10.2）——正在
        // 看这条旁聊时胶囊只归本行、主线聊天行无胶囊
        let isCurrent = drawerSelection == .side(thread.id)
        return Button {
            appState.drawerThreadSelection = thread.id
            // 0.36.7（§10.3 置位纪律）：导航动作显式
            // 写当前对象引用
            // 0.36.29（§10.4-⑤）：从旁聊区进入即离频
            // 道出处——哪怕进的是刚从频道收养的同一
            // 条线程，胶囊也随入口归旁聊行，出处必须
            // 在此清零（否则 ChatView 同步会按残留出
            // 处又把引用派生回 .channel）
            appState.channelViewingOrigin = nil
            appState.currentDrawerObject = .side(thread.id)
            onClose()
        } label: {
            HStack(spacing: 6) {
                Text(drawerDisplayTitle(for: thread))
                    // 0.20.0 字阶：旁聊行题 20 常规（图
                    // 中同为 20pt 级、重于导航行半粗一
                    // 档之差）；标题走 drawerDisplayTitle
                    // 解析（第三条 AI 标题回流）
                    // 0.23.0：落字阶角色 rowTitleL（title3，
                    // 默认 20 等值，审计 G2/D1）
                    // 0.24.0：角色改 Body 17 regular（HIG
                    // 落档，见 §51）——本行随角色变
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: OneDayMetrics.spacingS)
                Text(LocalThreadSubtitle.timeText(
                    updatedAt: thread.updatedAt,
                    now: Date()
                ))
                // 0.23.0：落字阶角色 meta（subheadline，
                // 默认 15 等值，审计 G2/D1）
                // 0.24.0：角色改 Footnote 13（HIG 时间
                // 戳档）——本行随角色变
                .font(.meta)
                // 0.22.0（审计 G1/D2）：时间戳是「要读的
                // 字」，inkMuted 实算 2.75:1 不达标——换
                // inkSecondary（4.84:1）；inkMuted 就此只
                // 留非文字用途，本屏其余面归 0.23.0
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, OneDayMetrics.spacingS)
            .frame(
                maxWidth: .infinity,
                minHeight: OneDayMetrics.drawerRowHeight,
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
        // 编辑框预填当前显示名（可能是服务端 AI 标题）
        renameText = drawerDisplayTitle(for: thread)
        renamingThread = thread
    }

    private func commitRenameThread() {
        let title = renameText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let thread = renamingThread, !title.isEmpty {
            thread.title = title
            // 0.20.0 第三条补环：本地改名打手改标记——
            // 此后服务端 AI 标题再刷新也不许覆盖此名
            // （DrawerThreadTitle 口径）；此前本地存储
            // 无此标记、回流无从分辨，是标题断环之一
            thread.titleIsManual = true
            try? modelContext.save()
        }
        renamingThread = nil
    }

    private func deleteThread(_ thread: ChatThread) {
        // 0.4.5 通道化：删的若是 ChatView 正在显示的线
        // 程，经 drawerDeletedThreadID 通知它置空当前
        // 线程（本面不持有 currentThreadID）
        // 0.36.7：「是否当前线程」改经单一选择政策判
        // 定（旁聊行命中 .side，或主线在看且本线程是
        // 主线）——activeThreadID 退役后的唯一口径
        let isCurrent = drawerSelection == .side(thread.id)
            || (drawerSelection == .main
                && SideChatClassifier.isMain(
                    localThreadID: thread.id,
                    linkedServerSessionID: thread.serverSessionID,
                    mainThreadID: appState.sideChats.mainThreadID,
                    mainServerSessionID: appState.sideChats
                        .mainServerSessionID
                ))
            // 0.36.29：正从频道看着的正是本线程（收养
            // 后的导入线程）时同属「当前线程」——删它
            // 必须通知 ChatView 置空（.channel 态下选
            // 择既非 .side 也非 .main，旧两条判不到）
            || (thread.serverSessionID != nil
                && thread.serverSessionID
                    == appState.channelViewingOrigin?.sessionID)
        if isCurrent {
            appState.drawerDeletedThreadID = thread.id
        }
        // 0.21.0 删除语义：本地线程删除是全仓唯一删
        // 除点（管理面删的是服务端会话本体、口径不
        // 变）；删前快照关联会话 id，本地删除照常先
        // 行，关联服务端会话随后做归档（PATCH
        // archived:true，尽力而为）——归档失败不阻
        // 塞本地删除，会话 id 落 SideChatStore 留痕
        // 账待对账（该会话在管理页未归档段仍可见）
        // 0.27.0 加闸（Core mayArchiveOnDelete）：只
        // 许归档本线程自建的 oneday- 会话；绑合并桶
        // 或他方服务端会话的线程只删本地、服务端零
        // 动作——合并桶里混着主线服务端历史，归档
        // 它等于连带归档主线
        let linkedSessionID = SideChatLink
            .mayArchiveOnDelete(sessionID: thread.serverSessionID)
            ? thread.serverSessionID
            : nil
        modelContext.delete(thread)
        try? modelContext.save()
        if let linkedSessionID {
            Task {
                do {
                    try await appState
                        .performAdmin { client, config in
                            try await client.updateServerSession(
                                config: config, id: linkedSessionID,
                                title: nil, pinned: nil,
                                archived: true
                            )
                        }
                    appState.sideChats
                        .clearFailedSessionArchive(linkedSessionID)
                } catch {
                    appState.sideChats
                        .noteFailedSessionArchive(linkedSessionID)
                }
            }
        }
    }

    /// 分组小标题（0.3.6 立宪）：13–14 号灰标签、左线
    /// 恒 drawerInset 20、上下留白 S/SM——分组就这一
    /// 种形态（0.17.0 补全宽左对齐帧治居中病根）
    private func drawerGroupHeader(_ title: String) -> some View {
        Text(title)
            // 0.20.0 字阶：分区头 15 medium 灰（图中约
            // 15–16pt 小灰字）；旧 .subheadline 让位
            // 0.22.0（审计 G1/D2）：颜色同时间戳换
            // inkSecondary（inkMuted 2.75:1 不达标）
            // 0.23.0：落字阶角色 sectionLabel（subhead-
            // line medium，默认 15 等值，审计 G2/S4）
            // 0.24.0：角色改 Footnote 13 regular（苹果
            // 设置分区头同款形态，HIG 落档见 §51）
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
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
                    // 0.20.0 字阶（Muse 抽屉图推算）：
                    // 图标约 27、行题 20 半粗、行高 58
                    // （drawerRowHeight）——0.19.0 的
                    // 19/body/47 偏小偏细一并让位
                    // 0.22.0 字形定版（用户 00:29 并排图点
                    // 名＋探针复量）：字重 regular→light 一
                    // 档（27pt 紧致密度：message .267→
                    // .217、list.bullet .352→.290、light-
                    // bulb .328→.283、checklist .300→
                    // .266）；符号经候选量测不换——目标位
                    // 参考图的方框勾形（checkmark.square
                    // .412）实测为候选最浓、否决，check-
                    // list 同为框勾线家族且密度低一档；枢
                    // 纽 list.bullet 无更轻的同义候选
                    // （rectangle.stack .353 同档），细线
                    // 感由字重达成（DESIGN-V4 §49）
                    // 0.24.0（用户当日指令，口径变更）：
                    // 字形 27 light→21 regular（令牌同改）
                    // ——落 HIG 符号带 20–22、字重与文字同
                    // 档；行题 title3 semibold→Body 17
                    // regular（角色 rowTitleLSemi 退役）
                    .font(.system(
                        size: FrameworkIcon.drawerGlyphSize,
                        weight: .regular
                    ))
                    .foregroundStyle(Palette.ink)
                    .frame(
                        width: OneDayMetrics.iconSlot,
                        alignment: .center
                    )
                    .accessibilityHidden(true)
                Text(title)
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OneDayMetrics.drawerRowHeight)
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
        .buttonStyle(.odPressable)
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
                    // 0.20.0 字阶与导航行同档（27/20 半粗
                    // /58，见 drawerNavRow 注）；0.22.0 字
                    // 重随导航行同批降 light（.353→.294）
                    // 0.24.0：随导航行同批改 21 regular＋
                    // 行题 Body 17 regular（见彼处注）
                    .font(.system(
                        size: FrameworkIcon.drawerGlyphSize,
                        weight: .regular
                    ))
                    .foregroundStyle(Palette.ink)
                    .frame(
                        width: OneDayMetrics.iconSlot,
                        alignment: .center
                    )
                    .accessibilityHidden(true)
                Text("管理全部对话")
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OneDayMetrics.drawerRowHeight)
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingS)
        // 0.22.0（并排图节奏复量，审计外用户 00:29 点
        // 名）：旧形态本行自带顶距 12 叠加发丝线的顶距
        // 8，管理行上方留白 20pt——是名单里唯一的双线
        // 孤岛（像素实测：线前留白本行 20pt vs 名单其
        // 余线前 8pt，参考图同位约 12pt 同档）。撤本行
        // 额外顶距后线前留白归一为 8pt，管理行回连续
        // 名单节奏；线→旁聊头留白（8＋头顶距 8）实测
        // 已比参考图更紧（约 12pt vs 约 24pt），不动
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
                // 0.20.0：应用格退役、设置改走根级 sheet
                // （ContentView 消费 settingsSheetRequested
                // 呈现新设置页）；0.6.0 的 pendingAppsPage
                // 落位通道随应用格一并退役
                systemName: "gearshape",
                label: "设置"
            ) {
                onClose()
                appState.settingsSheetRequested = true
            }
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
                TextField("搜索会话", text: $drawerQuery)
                    // 0.20.0 字阶：底条搜索字约 18（图中占
                    // 位字量级介于分区头与行题之间）
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                if !drawerQuery.isEmpty {
                    Button {
                        drawerQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.inkMuted)
                            // 0.23.0（命中域审计）：字形不
                            // 变、命中域外扩 44（胶囊高 52
                            // 可容纳），与文件页 ⋮ 同口径
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("清空搜索")
                    // 0.25.0（动效专包）：清除钮原无按钮样
                    // 式（无按压反馈）——补 .odPressable
                    .buttonStyle(.odPressable)
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
