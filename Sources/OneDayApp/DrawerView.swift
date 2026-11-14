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
///   每行角标，点行进该会话续聊）。（订正：管理行
///   已于管理收口包补件整行删除——入口挪设置页
///   「全部对话」行，用户 2026-11-13 18:57 拍板；
///   现行结构＝导航行组→发丝线→频道区→旁聊区，
///   抽屉内无任何进全部对话页的路径）
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
/// - §198（抽屉包）三题：①频道显行闸改全量同源——
///   计数改读共享全量目录（ServerSessionCatalog，
///   与全部对话页频道段同份可见集），0.36.29 的窗
///   口共用口径退役（该闸已于频道扩展一期整体退
///   役，见 sectionGates 注）；
///   ②管理行并入选项卡组作第六行＋新建分区管理面
///   （设置→侧边栏，四区显隐账）；③分割线统一口
///   径 R1–R10（线属边界、挂下行组头、与折叠态无
///   关），结构见 drawerNavList 注、账本见 DESIGN
///   §198。（②订正：管理行已于管理收口包补件整行
///   迁出、显隐账收三区——见文件头结构条订正注）
/// - 2026-11-13（P2 真机判红修复）：旁聊区行源扩
///   一路——AI 经伴生门面在 App 里替用户开的旁聊
///   （R3b 出生证明 oneday-ai-，服务端建、无本地
///   线程）在 0.50.28 只进了全部对话页「我的对话」
///   段（分类 .mine 全仓只有管理页消费），抽屉纯本
///   地线程行源永不显、用户找不到。本版起旁聊区并
///   入 Core DrawerUnadoptedSideChats 现算的未收养
///   行（分类 .mine 且未关联本地线程者，与本地行
///   同区平铺、时间倒序），点行走既有续聊通道导入
///   收养、收养后本地行接管。22:45 纠正口径不变：
///   要撤的仍只是「其他的对话」（worker/kanban/
///   平台源不进本区——它们分类上就不是 .mine）。
/// - 频道扩展一期（2026-11-13）：频道区改恒显清
///   单（Hermes＋Telegram＋微信冻结行，注册表
///   drawerList）——成员内容闸退役、整区只认显隐
///   账；未配对行带状态小字＋chevron（本区唯一带
///   chevron 的行形态），状态来自伴生频道桥回读
///   （ChannelStatusStore），读不到不猜、行尾留空。
/// - 承载沿 0.17.0：壳层（ContentView.DrawerShell）
///   以覆盖形态自左滑入盖在静止内容之上（§156 订
///   正：覆盖式壳层已退役，本面改由 UIKit 抽屉容
///   器底层宿主静止承载、主页面右移露出本面；本面
///   根结构与回调口径一字未动），本面根
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
    /// 打开频道页（0.36.29，频道规格 §3）：频道行
    /// 点按先经 onClose 关抽屉，ContentView 注入呈
    /// 现；入参为频道 id（一期只有 Hermes）
    var onOpenChannel: (String) -> Void

    /// 顶部标题带高（0.36.5）：名单顶部空程
    /// （contentMargins）与标题浮层共用一数。
    /// §157 身份行口径：顶距 24＋行高 36（小头像
    /// 36 档＞Title1 行高约 34，取大者）＋底距 12
    /// ＝72。Dynamic Type 极端档下名字行高变大、
    /// 静止时首行可能被身份行略压（已知边界，待
    /// 真机，与旧口径同界）
    private static let titleStripHeight: CGFloat = 72

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    /// 字号档（§157）：会话行在大字体（AX）档改标题/
    /// 时间上下排列，判定只读本环境，不另设开关
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    /// 删除二次确认的待删线程（0.50.30：真删不可恢
    /// 复，确认门与管理面 ServerSessionRow 同口径）
    @State private var pendingDeleteThread: ChatThread?
    /// 真删未落定的人话原因（失败弹报、本地线程保留）
    @State private var deleteFailureReason: String?
    /// 身份行编辑入口（§157）：与枢纽头像菜单同两张
    /// 编辑页的呈现开关，本面只置位、不复制编辑逻辑
    @State private var showAvatarEditor = false
    @State private var showNameEditor = false
    /// 分区折叠账（§158）：按区持久化（Core
    /// SectionCollapseState 唯一口径，键见
    /// DrawerSectionKey），杀 App 重进保持
    @AppStorage(SectionCollapseStorageKeys.drawerSections)
    private var drawerCollapseData: Data = Data()
    /// 分区显隐账（§198）：设置→侧边栏的分区管理面
    /// 写、本面读（Core SectionVisibilityState 唯一口
    /// 径，键同 DrawerSectionKey 三键）；与折叠账分
    /// 册——折叠管收起/展开、本账管整区在/不在
    @AppStorage(SectionVisibilityStorageKeys.drawerSections)
    private var drawerVisibilityData: Data = Data()

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
            // 之下），无底块无色带。§157 起浮层首行是
            // 身份行（drawerIdentityRow）且承命中（整
            // 行可点开编辑菜单）；浮层其余部分（Spacer）
            // 仍不承命中——行外拖动归名单/壳层手势
            VStack {
                drawerIdentityRow
                Spacer()
                    .allowsHitTesting(false)
            }
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
        // §162 材质减法盘点：面板底本体已是单层（双
        // 层材质是 0.36.5 标题带时代的病、当时已删）；
        // thinMaterial 档位是 0.36.3 用户点名定案，
        // 降档（ultraThin）在仓内与外部均无对标实证、
        // 不猜不动——本批减法落点在底条三件的叠加装
        // 饰（见 drawerBottomBar 注）
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
        // 删除二次确认（0.50.30）：文案与管理面共用行
        // 组件同口径；确认后走真删流（服务端先行、回
        // 查落定才删本地），失败走下方 alert 显形
        .confirmationDialog(
            "删除这条会话？",
            isPresented: Binding(
                get: { pendingDeleteThread != nil },
                set: { if !$0 { pendingDeleteThread = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let thread = pendingDeleteThread {
                    pendingDeleteThread = nil
                    Task { await performDeleteThread(thread) }
                }
            }
            Button("取消", role: .cancel) { pendingDeleteThread = nil }
        } message: {
            if let thread = pendingDeleteThread {
                Text("「\(drawerDisplayTitle(for: thread))」删除后不可恢复。")
            }
        }
        .alert(
            "没删掉",
            isPresented: Binding(
                get: { deleteFailureReason != nil },
                set: { if !$0 { deleteFailureReason = nil } }
            )
        ) {
            Button("好", role: .cancel) { deleteFailureReason = nil }
        } message: {
            Text(deleteFailureReason ?? "")
        }
        // 身份行编辑页（§157）：复用枢纽同两张编辑页
        // 本体（改的都是本机档案），呈现口径与枢纽一
        // 致（sheet），不另做一套编辑面
        .sheet(isPresented: $showAvatarEditor) {
            AgentAvatarEditorView()
        }
        .sheet(isPresented: $showNameEditor) {
            AgentNameEditorView(
                initialOverride: appState.profileNameOverride
            )
        }
        // 开抽屉时补拉服务端 source 映射（只喂来源过
        // 滤判定；信号源＝壳层维护的语义开合状态）。
        // §162 状态呈现收敛：关抽屉（开→关一沿，Core
        // DrawerSearchPolicy 裁决）即复位搜索词——旧
        // 行为词残留到下次打开、入口直接落在上次的
        // 过滤态，与「重开呈默认态」不是一个状态；
        // 收敛后入口状态只许一个（全量名单＋空框）
        .onChange(of: appState.drawerPresented) { wasPresented, presented in
            if presented {
                Task { await loadDrawerData() }
                // 身份呈现跟随（末写胜包）：抽屉页头就
                // 是名字与头像——每次打开重拉（节流在
                // AppState 内），不许显服务器已改掉的旧
                // 身份
                Task { await appState.refreshIdentitySurfaces() }
            } else if DrawerSearchPolicy.shouldResetQuery(
                wasPresented: wasPresented, isPresented: presented
            ) {
                drawerQuery = ""
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
        // §198：频道闸的全量目录冷时补拉一轮（已热零
        // 新增拉取——管理页写回与本路补拉共用一份，
        // 见 ServerSessionCatalog）；不阻塞本路返回，
        // 目录落位后闸的呈现随观察自动刷新
        Task {
            await appState.serverSessionCatalog
                .refreshIfCold(appState: appState)
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

    /// 身份行（§157 第一批①，用户 2026-11-11 21:01
    /// 补充方案）：小头像＋名字＋轻量编辑入口，整行
    /// 可点。旧形态只有名字文本（0.3.6 立宪 §21.3：
    /// 状态点/状态词/模型小字全撤——那是管理面信
    /// 息，不占导航壳第一眼；本行同样不带服务器/模
    /// 型信息、不做账号卡），且标题浮层整体关命中，
    /// 用户无从知道去哪里改名换头像。本行落法：整
    /// 行是一个 Menu（与枢纽头像角标菜单同两项：更
    /// 换虚拟形象/编辑名称），点开后呈现的编辑页复
    /// 用枢纽同两张本体（AgentAvatarEditorView/
    /// AgentNameEditorView，改的都是本机档案 Agent-
    /// ProfileStore），不另做一套；头像与名字都读
    /// AppState 单一出口（档案覆盖→soul 名），与全
    /// App 露脸面同源。编辑提示只给一支铅笔字形
    /// （inkSecondary 弱档），不加第二层按钮底
    private var drawerIdentityRow: some View {
        Menu {
            Button {
                showAvatarEditor = true
            } label: {
                Label("更换虚拟形象", systemImage: "person.crop.circle")
            }
            Button {
                showNameEditor = true
            } label: {
                Label("编辑名称", systemImage: "pencil")
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                // 头像走列表行档（§222：与设置身份卡/
                // 编辑器行同为 44；旧 36 小档让抽屉与
                // 其他列表面头像大小不一，收敛退役）；
                // 呈现三件与枢纽同式：scaledToFill＋圆
                // 裁＋发丝环
                appState.agentAvatarImage
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: OneDayMetrics.avatarListRow,
                        height: OneDayMetrics.avatarListRow
                    )
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(
                            Palette.hairline, lineWidth: 0.5
                        )
                    }
                    .accessibilityHidden(true)
                // 名字沿革：0.20.0 升 34pt（Muse 图推
                // 算）→0.22.0 字重降 semibold→0.23.0 落
                // 角色→0.24.0 改 Title1 28 bold（HIG 大
                // 标题档，用户当日指令、§51）——现行角
                // 色 screenName 不动
                Text(appState.agentDisplayName)
                    .font(.screenName)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, OneDayMetrics.drawerInset)
        .padding(.top, OneDayMetrics.spacingL)
        .padding(.bottom, OneDayMetrics.spacingSM)
    }

    // MARK: - 导航主体（0.19.0）

    /// 导航组＋旁聊区：对 Muse 样板的结构——导航
    /// 五行管导航，其下发丝线＋「旁聊」区（本人旁
    /// 聊平铺，见旁聊区注）；（0.19.0 曾有「管理全
    /// 部对话」一行夹在导航组与旁聊区之间，§198 并
    /// 入选项卡组作第六行；已于管理收口包补件整行
    /// 迁出——入口挪设置页「全部对话」行，用户
    /// 2026-11-13 18:57 拍板，本面不再有进全部对
    /// 话页的路径）
    /// §157②：「选项卡」组头删除——其下五行已明示是
    /// 导航，再挂一层小标签只是多一道分隔与留白；
    /// 「频道」「旁聊」两组头保留（它们标的是名单分
    /// 区、不是导航自明区）
    /// §182.1：用户纠正口径——真问题是缺组标题，恢复
    /// 「选项卡」组头（与频道/旁聊同口径），与 Muse
    /// 参照对齐
    /// §198 重排：分区呈现走三区合成（sectionGates＝
    /// 显隐账 ∧ 内容闸）；分割线按统一口径 R1–R10：
    /// 线属于边界、恒挂下行分区的组头上方、与任何
    /// 区的折叠态无关（R2/R6）；首区无顶线（R8）；
    /// 组头与子项之间永不划线（R3）；不渲染的区连
    /// 线退场（R7）；线顶留白恒 spacingS 一处记账
    /// （R10）。（§198 的组内分簇线 R5 是为管理行而
    /// 设，管理行迁出后本组无簇可分，R5 随之退役；
    /// 选项卡组被管理面隐藏时导航槽整体不在场，频
    /// 道/旁聊的边界线按 R7/R8 自行退场/免顶线）
    private var drawerNavList: some View {
        // 在场合成：选项卡槽＝导航组本体；边界线只
        // 许出现在「上方已有在场区」的区头顶
        let navSlotPresent = sectionGates.navigation
        let channelsPresent = sectionGates.channels
        return VStack(alignment: .leading, spacing: 0) {
            if sectionGates.navigation {
            // §182.1：导航组头恢复标题「选项卡」，
            // 与频道/旁聊组头同形态同口径
            drawerCollapsibleHeader("选项卡", key: DrawerSectionKey.navigation)
            drawerCollapsibleContent(
                collapsed: drawerSectionCollapsed(
                    DrawerSectionKey.navigation
                )
            ) {
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
                title: "资源库",
                selected: drawerSelection == .surface(.files)
            ) {
                onClose()
                onSelectTab(.files)
            }
            }
            }
            // 0.36.29（频道规格 §3.1）：频道区插在选项
            // 卡槽与旁聊区之间（面先于条，与 Muse 样
            // 板同序）；§198：整区呈现＝显隐账 ∧ 全量
            // 成员闸（sectionGates.channels），不渲染
            // 时其头顶边界线一并退场（R7）
            if channelsPresent {
                if navSlotPresent {
                    // R2 边界线：恒挂频道组头上方，与
                    // 任何区的折叠态无关
                    drawerDivider
                        .padding(.top, OneDayMetrics.spacingS)
                }
                drawerChannelSection
            }
            if sectionGates.sideChats {
                if navSlotPresent || channelsPresent {
                    // R2 边界线：恒挂旁聊组头上方——旧
                    // 挂法「旁聊展开才挂」就此退役，全
                    // 折叠态本线仍在（验收第一帧）
                    drawerDivider
                        .padding(.top, OneDayMetrics.spacingS)
                }
                drawerSideSection
            }
            Color.clear
                .frame(height: OneDayMetrics.spacingL)
        }
        .padding(.top, OneDayMetrics.spacingS)
    }

    // MARK: - 频道区（0.36.29，频道规格 §3）

    /// 三区渲染合成（§198＋2026-11-13 频道一期）：
    /// 只认显隐账（分区管理面）——频道区的成员内容
    /// 闸已退役（恒显清单：未配对行与冻结行靠整区
    /// 常在才有地方站），§198 的全量分类计数闸随之
    /// 退场（drawerFullPartition 一并退役）；管理行
    /// 亦已随收口包补件迁出（合成四区收三区）。合成
    /// 走 Core DrawerSectionGates 唯一口径，本面只
    /// 消费结论排版、不私算
    private var sectionGates: DrawerSectionGates {
        DrawerSectionGates.resolve(
            visibility: SectionVisibilityState.decode(
                drawerVisibilityData
            )
        )
    }

    /// 频道配对状态（频道扩展一期）：行尾状态小字
    /// 的唯一来源——伴生频道桥回读，本面出现时拉
    /// 一次；读不到时状态为空、行尾不编词
    @State private var channelStatusStore = ChannelStatusStore()

    /// 频道区：恒显清单（注册表 drawerList：Hermes
    /// ＋Telegram＋微信冻结行）
    @ViewBuilder
    private var drawerChannelSection: some View {
        drawerCollapsibleHeader(
            "频道", key: DrawerSectionKey.channels
        )
        drawerCollapsibleContent(
            collapsed: drawerSectionCollapsed(DrawerSectionKey.channels)
        ) {
            ForEach(ChannelRegistry.drawerList) { channel in
                drawerChannelRow(channel)
            }
        }
        .task {
            await channelStatusStore.load(appState: appState)
        }
    }

    /// 频道行（规格 §3.2＋对 Muse 抽屉对图改平）：
    /// 与导航行完全同构的平排——图标槽＋标题 Body
    /// 17＋drawerRowHeight，选中才带与导航行同式
    /// 的胶囊；无卡片底（Muse 频道行 §157③：行高
    /// 与标题角色随导航行同批改导航簇档 54＋抽屉局
    /// 部角色（见 drawerNavRow 注），同构关系不变；
    /// 本行展示名（Hermes）本批不动——改名涉三层命
    /// 名口径，留待用户拍板（见 §157 记账），宪法
    /// §7）；**不给计数徽标**（抽屉拉取口径与全量
    /// 不一致，挂数即埋假新鲜，S7 纪律）；图标用注
    /// 册表资产（品牌频道＝官方原图，宪法 §4；无资
    /// 产的平台不许拿 SF 符号代用上行——注册表
    /// drawerList 只收有资产的行），资产本体落字形
    /// 档 21 居中于 30 槽内、与导航行 SF 字形同尺
    /// 寸——旧落法资产填满 30 槽，实色方块比线形字
    /// 形重一圈，是真机截图里本行「卡片感」的主源，
    /// 本包改平（见 DESIGN §101）；选中态问单一选
    /// 择政策（.channel 命中才带胶囊）。
    /// 2026-11-13 频道一期行尾新形态：已配对行与
    /// Hermes 行同尾（空）；未配对/连接中/连接失败
    /// 行带状态小字＋chevron（本区唯一带 chevron 的
    /// 行，进配对引导页）；冻结行（微信）只带「暂
    /// 不可用」小字、无 chevron（点开是说明页）。
    /// 状态读不到时小字留空，不编词
    private func drawerChannelRow(_ channel: ChannelDescriptor) -> some View {
        let selected = drawerSelection == .channel(channel.id)
        let accessory = drawerChannelAccessory(channel)
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
                            .frame(
                                width: FrameworkIcon.drawerGlyphSize,
                                height: FrameworkIcon.drawerGlyphSize
                            )
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
                    // §157③：与导航行同一套角色（常态
                    // medium／选中 semibold＋浅灰底）
                    .font(
                        selected
                            ? .drawerRowTitleCurrent
                            : .drawerNavTitle
                    )
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let word = accessory.word {
                    Text(word)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if accessory.chevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OneDayMetrics.drawerNavRowHeight)
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
        .accessibilityLabel(
            accessory.word.map { "\(channel.name)，\($0)" }
                ?? channel.name
        )
        // 0.43.0（A11Y-V5）：选中态只靠胶囊底色——
        // 补已选特征，VO 不靠颜色辨当前频道
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// 频道行尾件（频道扩展一期）：状态小字＋chevron
    /// 的唯一裁决处。Hermes 行恒空尾；已配对平台同
    /// 空尾（与 Hermes 行同形态）；冻结行只有小字；
    /// 令牌型未配对/等待生效/失败带小字＋chevron；
    /// 状态未回（未加载/读取失败）时只有 chevron
    /// （目的地是入口页、会在页内把状态说清）
    private func drawerChannelAccessory(
        _ channel: ChannelDescriptor
    ) -> (word: String?, chevron: Bool) {
        switch ChannelRegistry.pairingKind(for: channel.id) {
        case .none:
            return (nil, false)
        case .frozen:
            return (L10n.string("暂不可用"), false)
        case .qr:
            return (L10n.string("未配对"), true)
        case .token:
            guard let status = channelStatusStore.status(
                for: channel.id
            ) else {
                return (nil, true)
            }
            switch status.state {
            case "connected":
                return (nil, false)
            case "pending_restart":
                return (L10n.string("连接中"), true)
            case "error":
                return (L10n.string("连接失败"), true)
            default:
                return (L10n.string("未配对"), true)
            }
        }
    }

    // MARK: - 旁聊区（0.19.0 返工，22:45 纠正口径）

    /// 旁聊区：单个「旁聊」分区头＋平铺行（合并行集
    /// sideRows 活动时间倒序即呈现序——本地线程行与
    /// 未收养服务端行同区平铺，不分组、不置顶分段）；
    /// 空时只留一行弱字提示（不整区消失——让用户知
    /// 道新建入口在哪）
    @ViewBuilder
    private var drawerSideSection: some View {
        drawerCollapsibleHeader("旁聊", key: DrawerSectionKey.sideChats)
        drawerCollapsibleContent(
            collapsed: drawerSectionCollapsed(DrawerSectionKey.sideChats)
        ) {
        if sideRows.isEmpty {
            Text("还没有旁聊")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OneDayMetrics.drawerInset)
                .padding(.bottom, OneDayMetrics.spacingS)
        } else {
            ForEach(sideRows) { row in
                drawerSideRowView(row)
            }
        }
        }
    }

    /// 搜索态名单：只显命中的旁聊行（导航组与管理行
    /// 隐藏，与 0.18.0 抽屉搜索同行为）；无命中给弱
    /// 字一行，不留空白屏
    @ViewBuilder
    private var drawerSearchList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // §158：搜索态头走同一折叠件但状态被呈现
            // 层强制为展开（搜到一半不许被折叠挡住）；
            // 点它切换的是同一本账（旁聊区键）
            CollapsibleSectionHeader(
                title: "旁聊",
                isCollapsed: false,
                titleFont: .sectionLabel,
                onToggle: {
                    toggleDrawerSection(DrawerSectionKey.sideChats)
                }
            )
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, OneDayMetrics.drawerInset)
            if sideRows.isEmpty {
                Text("没有匹配的旁聊")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OneDayMetrics.drawerInset)
                    .padding(.bottom, OneDayMetrics.spacingS)
            } else {
                ForEach(sideRows) { row in
                    drawerSideRowView(row)
                }
            }
            Color.clear
                .frame(height: OneDayMetrics.spacingL)
        }
        .padding(.top, OneDayMetrics.spacingS)
    }

    /// 搜索态判定（§162 下沉 Core DrawerSearchPolicy
    /// 单一裁决，口径与 0.18.0 沿革一字不变：修剪后
    /// 非空）
    private var isSearching: Bool {
        DrawerSearchPolicy.isSearching(query: drawerQuery)
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
        // §162：规范化与判定同出 Core 政策一处
        let query = DrawerSearchPolicy.normalizedQuery(drawerQuery)
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

    /// 未收养旁聊行源（2026-11-13 P2 修复）：分类
    /// .mine 且无本地线程的服务端会话——AI 在 App
    /// 里替用户开的旁聊（R3b）与本地线程已删的 App
    /// 铸旁聊（R3）。现算口径在 Core DrawerUnadopted-
    /// SideChats（入参两路并集：全量目录＋本面刚拉
    /// 的第一页，新鲜度优先；已关联者剔除防与本地
    /// 行双出）；本面只补搜索过滤（按服务端标题，
    /// 与本地行按显示名搜同一手感）
    private var visibleUnadoptedSideSessions: [ServerSession] {
        let all = DrawerUnadoptedSideChats.sessions(
            catalog: appState.serverSessionCatalog.visibleSessions,
            latestPage: Array(drawerServerSessions.values),
            mainServerSessionID: appState.sideChats.mainServerSessionID,
            linkedThreadSessionIDs: ThreadLinkage
                .nonMainLinkedSessionIDs(
                    threads: threads, sideChats: appState.sideChats
                )
        )
        let query = DrawerSearchPolicy.normalizedQuery(drawerQuery)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.resolvedTitle(firstUserMessage: nil)
                .localizedCaseInsensitiveContains(query)
        }
    }

    /// 旁聊区合并行集（本地行＋未收养行同区平铺、
    /// 活动时间倒序）：本地行时间＝线程 updatedAt、
    /// 未收养行＝服务端活动时间（无日期者垫底）；
    /// 同刻保原序（本地行在前、各自保序——合并排
    /// 序不许打乱本地行既有相对序，22:45 平铺口径）
    private var sideRows: [DrawerSideRow] {
        var merged: [(row: DrawerSideRow, date: Date, order: Int)] = []
        for (index, thread) in sideThreads.enumerated() {
            merged.append((.thread(thread), thread.updatedAt, index))
        }
        let unadopted = visibleUnadoptedSideSessions
        for (index, session) in unadopted.enumerated() {
            merged.append((
                .unadopted(session),
                DrawerUnadoptedSideChats.activityDate(of: session)
                    ?? .distantPast,
                sideThreads.count + index
            ))
        }
        return merged
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.order < rhs.order
            }
            .map(\.row)
    }

    /// 旁聊区行型（本地线程行／未收养服务端行）：
    /// 两路行源合并呈现的统一行标识（id 带来源前缀
    /// 防撞），版式与点达各走自家分支（见 sideRows
    /// 与 drawerUnadoptedSideRow）
    private enum DrawerSideRow: Identifiable {
        case thread(ChatThread)
        case unadopted(ServerSession)

        var id: String {
            switch self {
            case .thread(let thread):
                return "local-\(thread.id.uuidString)"
            case .unadopted(let session):
                return "server-\(session.id)"
            }
        }
    }

    /// 合并行分发：本地行走既有整行（含长按四件），
    /// 未收养行走服务端行（点达收养）
    @ViewBuilder
    private func drawerSideRowView(_ row: DrawerSideRow) -> some View {
        switch row {
        case .thread(let thread):
            drawerSideThreadRow(thread)
        case .unadopted(let session):
            drawerUnadoptedSideRow(session)
        }
    }

    /// 未收养旁聊行（2026-11-13 P2 修复）：与本地行
    /// 同式（标题＋行尾紧凑时间、行高与内距同档）；
    /// 标题走服务端标题管线（resolvedTitle——AI 给
    /// 的名字如「爱的定义」直达），时间走服务端活
    /// 动时间（无日期不编造、行尾留空）。无当前位胶
    /// 囊（当前线程恒为本地线程）、无长按四件（那是
    /// 本地线程的操作面）；点行＝走既有续聊通道点
    /// 达（pendingChatSessionID 置位，与回响卡/管
    /// 理页/频道页同一路）：ContentView 切聊天格、
    /// ChatView 导入建本地线程即收养——收养后本行
    /// 现算自动消失、由本地行接管（全功能）
    private func drawerUnadoptedSideRow(
        _ session: ServerSession
    ) -> some View {
        Button {
            appState.pendingChatSessionID = session.id
            onClose()
        } label: {
            let title = Text(
                session.resolvedTitle(firstUserMessage: nil)
            )
            .font(.drawerRowTitle)
            .foregroundStyle(Palette.ink)
            .a11yLineLimit(1, ax: 2)
            let trailing = Group {
                if let date = DrawerUnadoptedSideChats
                    .activityDate(of: session) {
                    Text(LocalThreadSubtitle.compactTimeText(
                        updatedAt: date, now: Date()
                    ))
                    .font(.meta)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingMicro
                    ) {
                        title
                        trailing
                    }
                } else {
                    HStack(spacing: OneDayMetrics.rowInnerGap) {
                        title
                        Spacer(minLength: OneDayMetrics.spacingS)
                        trailing
                    }
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .frame(
                maxWidth: .infinity,
                minHeight: OneDayMetrics.drawerRowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingS)
    }

    /// 旁聊行（0.17.0 单行形态沿用、0.19.0 返工去角
    /// 标）：标题＋行尾小字时间、当前位浅灰垫；点按
    /// 经 drawerThreadSelection 请 ChatView 切换并关
    /// 抽屉（0.4.5 通道化沿革）；长按四件与 0.18.0
    /// 本地行同序（重命名/置顶/归档/删除）——置顶只
    /// 落数据（isPinned），抽屉呈现恒时间序（22:45
    /// 平铺口径），置顶的呈现归管理页等其他面
    /// §157③④：置顶呈现口径变更——抽屉行内补图钉标
    /// 记（排序仍恒时间序、不学管理页的置顶分段）；
    /// 时间改紧凑口径、选中改字重＋浅灰底统一规则、
    /// AX 档标题/时间上下排列，逐项见 label 内注
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
            // §157③④：标题与行尾两件先成件、再按字号
            // 档排向——常态横排（标题抢宽、行尾靠右）；
            // AX 大字体档上下排列（标题在上、行尾在其
            // 下左对齐），不再横向互挤
            let title = Text(drawerDisplayTitle(for: thread))
                // 0.20.0 字阶：旁聊行题 20 常规（图
                // 中同为 20pt 级、重于导航行半粗一
                // 档之差）；标题走 drawerDisplayTitle
                // 解析（第三条 AI 标题回流）
                // 0.23.0：落字阶角色 rowTitleL（title3，
                // 默认 20 等值，审计 G2/D1）
                // 0.24.0：角色改 Body 17 regular（HIG
                // 落档，见 §51）——本行随角色变
                // §157③：改落抽屉局部角色——常态
                // drawerRowTitle（Body regular、基值与
                // rowTitleL 逐点相同）、当前行 drawer-
                // RowTitleCurrent（semibold）＋浅灰底，
                // 与导航/频道同一套选中规则
                .font(
                    isCurrent
                        ? .drawerRowTitleCurrent
                        : .drawerRowTitle
                )
                .foregroundStyle(Palette.ink)
                // 0.43.0（A11Y-D3）：AX 档放宽行数
                .a11yLineLimit(1, ax: 2)
            let trailing = HStack(
                spacing: OneDayMetrics.rowInnerGap
            ) {
                // §157④：置顶行给小图钉标——旧口径置
                // 顶只落数据、抽屉呈现无任何标记，用
                // 户在此面无从分辨；本批只补呈现（排
                // 序恒时间序与长按四件本体不动）
                if thread.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(
                            size: 10, weight: .semibold
                        ))
                        .foregroundStyle(Palette.inkSecondary)
                        .accessibilityHidden(true)
                }
                Text(LocalThreadSubtitle.compactTimeText(
                    updatedAt: thread.updatedAt,
                    now: Date()
                ))
                // 0.23.0：落字阶角色 meta（subheadline，
                // 默认 15 等值，审计 G2/D1）
                // 0.24.0：角色改 Footnote 13（HIG 时间
                // 戳档）——本行随角色变
                // §157④：时间源改紧凑口径——今天只给
                // HH:mm（Core compactTimeText），跨日
                // 仍带日标
                .font(.meta)
                // 0.22.0（审计 G1/D2）：时间戳是「要读的
                // 字」，inkMuted 实算 2.75:1 不达标——换
                // inkSecondary（4.84:1）；inkMuted 就此只
                // 留非文字用途，本屏其余面归 0.23.0
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingMicro
                    ) {
                        title
                        trailing
                    }
                } else {
                    HStack(spacing: OneDayMetrics.rowInnerGap) {
                        title
                        Spacer(minLength: OneDayMetrics.spacingS)
                        trailing
                    }
                }
            }
            // §157③：内外边距与导航行对齐（内 spacingSM
            // ／外 spacingS）——选中胶囊左右边界与导航/
            // 频道行同为 8 线、形状同为 fieldCorner 连
            // 续圆角；标题起点仍恒 20（8＋12）不变
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .frame(
                maxWidth: .infinity,
                minHeight: OneDayMetrics.drawerRowHeight,
                alignment: .leading
            )
            .background {
                if isCurrent {
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
        // §157④：图钉是纯视觉标记——置顶状态经 acces-
        // sibilityValue 补播报（标题/时间的内容自读不
        // 受影响）；未置顶行值为空、不出声
        .accessibilityValue(
            thread.isPinned ? L10n.string("已置顶") : ""
        )
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
                pendingDeleteThread = thread
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

    /// 真删流（0.50.30，管理收口包件二；取代 0.21.0
    /// 「本地先删＋服务端归档（尽力而为）」旧语义——
    /// 旧流服务端只归档不删、会话本体从没删掉过）：
    /// 本线程自建的旁聊会话（Core 真删闸 mayHard-
    /// DeleteOnThreadDelete）先走 ServerSession-
    /// Actions.delete（围栏 DELETE＋删后回查、与全
    /// 部对话页同一条路），回查落定才清本地账并删
    /// 本地线程；未落定 → 本地线程原样保留、原因弹
    /// 报，不许再出现「本地没了、服务端还在」。其余
    /// 线程（未链接/导入会话/合并桶绑定）维持只删
    /// 本地、服务端零动作；主线线程在本面无删除入
    /// 口（既有保护不动），真删闸对主线会话本体另
    /// 有双重拦截
    private func performDeleteThread(_ thread: ChatThread) async {
        if let linkedSessionID = thread.serverSessionID,
           SideChatLink.mayHardDeleteOnThreadDelete(
               sessionID: linkedSessionID,
               mainSessionID: appState.sideChats.mainServerSessionID
           ) {
            let outcome = await ServerSessionActions.delete(
                appState: appState, id: linkedSessionID
            )
            guard case .verified = outcome else {
                if case .failed(let reason) = outcome {
                    deleteFailureReason = reason
                }
                return
            }
            appState.sideChats
                .purgeServerSessionRecords(linkedSessionID)
        }
        deleteLocalThread(thread)
    }

    private func deleteLocalThread(_ thread: ChatThread) {
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
        modelContext.delete(thread)
        try? modelContext.save()
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

    // MARK: - 分区折叠（§158）

    /// 折叠账读口（Core 唯一判定）：抽屉三区默认展开
    private func drawerSectionCollapsed(_ key: String) -> Bool {
        SectionCollapseState.isCollapsed(
            key: key,
            in: SectionCollapseState.decode(drawerCollapseData),
            defaultCollapsed: false
        )
    }

    private func toggleDrawerSection(_ key: String) {
        withAnimation(.smooth(duration: 0.3)) {
            drawerCollapseData = SectionCollapseState.encode(
                SectionCollapseState.toggled(
                    key: key,
                    in: SectionCollapseState.decode(drawerCollapseData),
                    defaultCollapsed: false
                )
            ) ?? drawerCollapseData
        }
    }


    /// 可折叠分区头：公用件 CollapsibleSectionHeader
    /// 本体（标题角色与旧 drawerGroupHeader 同档
    /// sectionLabel、颜色在本面补 inkSecondary——公用
    /// 件不私定颜色，与旧头呈现一贯），外距与旧头同
    /// 口径（drawerInset 横距＋上下 S/SM）
    private func drawerCollapsibleHeader(
        _ title: String, key: String
    ) -> some View {
        CollapsibleSectionHeader(
            title: title,
            isCollapsed: drawerSectionCollapsed(key),
            titleFont: .sectionLabel,
            onToggle: { toggleDrawerSection(key) }
        )
        .foregroundStyle(Palette.inkSecondary)
        .padding(.horizontal, OneDayMetrics.drawerInset)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingSM)
    }

    /// 折叠内容必须是单列：ViewBuilder 的多条导航/会话
    /// 直接放进 GridRow 会成为多个横向 cell，撑宽名单并
    /// 让居中的根内容从左缘溢出。高度折叠仍由原事务承接。
    private func drawerCollapsibleContent<Content: View>(
        collapsed: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        DrawerCollapsibleContent(collapsed: collapsed, content: content)
    }

    /// 导航行（0.19.0，对 Muse 样板「选项卡」行）：单
    /// 行制——SF 符号（与底栏同源 TabBarSymbols，不另
    /// 立第二套符号表）＋标题，选中格浅灰垫（selec-
    /// tionFill 整行圆角垫、标题不变色不加粗），行高
    /// 与 0.17.0 单行会话行同档（47pt 导航行档）
    /// §157②③（用户 21:01 补充方案）：行高改导航簇档
    /// drawerNavRowHeight 54（设计起点、非实测参数，
    /// 把空间让给会话区；仍是 minHeight、大字体随内
    /// 容增长）；标题落抽屉局部角色——常态 drawer-
    /// NavTitle（Body medium，主要导航层级），选中
    /// drawerRowTitleCurrent（semibold 适度加重）＋
    /// 浅灰底，与频道行/会话行同一套选中规则；旧口
    /// 径「选中标题不加粗」随本令让位（仅抽屉内）
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
                    // §157③：常态 medium／选中 semibold
                    // （抽屉局部角色，见函数头注）
                    .font(
                        selected
                            ? .drawerRowTitleCurrent
                            : .drawerNavTitle
                    )
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OneDayMetrics.drawerNavRowHeight)
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
        // 0.43.0（A11Y-V5）：选中态只靠浅灰垫——补
        // 已选特征，与频道行同式
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// 发丝线（左右留 drawerInset 20）：组间分隔的唯
    /// 一形态（立宪：分组＝灰标签＋发丝线，分隔几何
    /// 全名单只此一种，宪法 §3）。色改挂 Palette
    /// .separator（宪法 §3 定版的分隔单色、与全 App
    /// GroupDivider 同源，α 语义压任何面保持可辨）：
    /// 旧挂 hairline 的浅档 #EEEEF0 与抽屉磨砂底近
    /// 同色、真机截图里三处组间线全不可见（用户
    /// 05:34 对图点题），本包改挂显形、几何（20 线、
    /// 高 1）不动，见 DESIGN §101
    /// 0.41.0（收口批 P3）：实现收编 GroupDivider 本
    /// 体——旧自绘 Rectangle 高 1pt 是全 App 最后一处
    /// 分隔线私实现；改走 GroupDivider（物理发丝
    /// 1/displayScale＋separator 同源），双侧 inset
    /// 以 trailingInset 显式传同值保抽屉段内线几何。
    /// 视觉变化点明：线高由 1pt 变物理发丝（更细、
    /// 与全 App 其余分隔线同粗），待真机验
    private var drawerDivider: some View {
        GroupDivider(
            inset: OneDayMetrics.drawerInset,
            trailingInset: OneDayMetrics.drawerInset
        )
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
                // 2026-11-13（用户 15:52 亲令「侧边栏点
                // 设置的时候，侧边栏不要收回，不然不好
                // 看」）：本钮不再先 onClose()——旧动作
                // 先收抽屉再升设置 sheet、收回动画与设
                // 置升起叠着难看。改只置位请求：设置由
                // ContentView 根级 sheet 盖住整屏升起，
                // 抽屉语义开合一字不动（不收回、无动
                // 画），搜索词/分区折叠/滚动位随之天然
                // 保住，关设置原样回到仍开着的抽屉。抽
                // 屉内其余行（导航/频道/管理/新建/选
                // 会话）的 onClose 收回口径一字不变；
                // 设置内「跳去某格/某会话」的出口在
                // ContentView 消费点收抽屉（点达须看得
                // 见，见彼处三处注）
                systemName: "gearshape",
                label: "设置"
            ) {
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
            // #F9F9F9），玻璃施加于件本体、内容在其上。
            // §162 材质减法（抽屉呈现第二批）：0.4.1 注
            // 里「与发送舱同式」当时并不成立——发送舱
            // 玻璃卡与身份胶囊从来只有裸玻璃，本件却
            // 在玻璃之上又叠了发丝描边 overlay 与柔影
            // 两层（玻璃本体自带边缘高光、描边是第二
            // 次画边；本条注册在 safeAreaBar 内、下方
            // 有名单 soft 边缘效果承接分离，影是第三
            // 重分离机制）。本批两层一并删除，三件回
            // 到裸玻璃、与发送舱/身份胶囊真正同式
            .glassEffect(.regular, in: Capsule())
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
                // 搜索胶囊同改，口径见彼处注）；§162 材
                // 质减法：发丝描边 overlay 与柔影随搜索
                // 胶囊同删，只剩裸玻璃（理由见胶囊处注）
                .glassEffect(.regular, in: Circle())
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

/// 单列折叠布局，独立成件供宿主几何回归测试直接覆盖。
/// 不使用 GridRow；多子视图和 ForEach 都必须纵向堆叠。
struct DrawerCollapsibleContent<Content: View>: View {
    var collapsed: Bool
    let content: Content

    init(collapsed: Bool, @ViewBuilder content: () -> Content) {
        self.collapsed = collapsed
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: collapsed ? 0 : nil, alignment: .top)
        .clipped()
        .opacity(collapsed ? 0 : 1)
        .allowsHitTesting(!collapsed)
        .accessibilityHidden(collapsed)
    }
}
