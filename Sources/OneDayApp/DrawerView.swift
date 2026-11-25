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
///   计数改读共享全量目录（原 ServerSessionCatalog、
///   第 90 条收尾后归 SessionLedger 本体，与全部
///   对话页频道段同份可见集），0.36.29 的窗
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
///   单 safeAreaBar 走纯系统朦胧，见 body 内注。
///   2026-11-22 抽屉量测对齐包三订正：顶注册恢复
///   ——身份行改挂 safeAreaBar(edge: .top)＋名单
///   顶缘 .soft 渐隐（Muse 钉顶＋渐隐带机制，主
///   线量测定案，见 body 内 D3 订正注）；「头尾固
///   定实色条」旧定式中顶条一侧自此为注册栏＋系
///   统渐隐，仍不许自绘渐变带/模糊层（E11 纪律不
///   变，渐隐走系统边缘效果非自绘）。同包：旁聊
///   行（本地＋未收养）行尾时间整段删除。）
/// - 结构归位第二批（2026-11-20，用户亲批结构纲
///   要 D0-1/D1-1/D2-1）：名单结构改定为——主线
///   行（独立行、动作沿旧）→「旁聊」分区（升 L1
///   顶点）→「频道」分区（降 L2）→「全部对话」
///   收尾行（全量列表一级入口、经路由旗根级呈
///   现）。旧「选项卡」分区整组退役（四行与底栏
///   同目的地双挂收口，TabView 一处当家）；分区
///   显隐账消费退役（两区恒在场、折叠保留），跨
///   页可见性管理元层级自本面剥离。详见
///   drawerNavList 注
/// - 台账 194（2026-11-21）：用户真机点题后改
///   判——「选项卡」分区恢复（四行回收＋主线行
///   归组）、次序回「选项卡→频道→旁聊」、「全
///   部对话」迁入选项卡组作第六行；显隐账退役
///   不恢复、192 视觉值不动。详见 drawerNavList
///   注⑤
struct DrawerView: View {
    /// 面板宽＝容器量测给（§313：第 78 条 D2 录屏实
    /// 测 0.75×容器宽、无上限，单源 DrawerCard-
    /// Geometry.travel；旧口径 0.79×屏宽/上限 400 作废）
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

    /// 顶部标题带高（0.36.5 立、2026-11-22 抽屉
    /// 量测对齐包退役）：旧制名单顶部空程（con-
    /// tentMargins）与标题浮层共用一数 56。本包
    /// 身份行改挂名单 .safeAreaBar(edge: .top)
    /// 注册（见 body 注），带高改由身份行本体构
    /// 成（顶距 8＋头像 44＋底距 4＝56，与旧空程
    /// 逐点恒等、静止布局不变），本令牌随手排空
    /// 程退役、不再有第二写点（同日 B 项追加后
    /// 页头只留名字大标题、带高改 49，见身份行
    /// 注）。沿革：§157 口径
    /// 72→2026-11-21 样板对齐包改 56（身份行顶
    /// 距 24→8；样板标题墨顶距安全区顶实测
    /// 13.7pt、本面名字墨顶 20.1，Δ6.4 是头像
    /// 44 同行居中的固有量，见交卷对位表）

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 字号档（§157）：会话行在大字体（AX）档改标题/
    /// 时间上下排列，判定只读本环境，不另设开关
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 减透明环境量原供面板底回退裁决读（0.23.0）；
    /// §318 面板底改恒实色后本面再无消费方，声明
    /// 随回退分支一并退役（TransparencyFallback
    /// 本体在 Core 保留、他面仍可用）
    @Query(sort: \ChatThread.updatedAt, order: .reverse)
    private var threads: [ChatThread]
    /// 底条搜索词（本地过滤旁聊区，22:45 纠正后恢复
    /// 0.18.0 抽屉搜索口径）
    @State private var drawerQuery = ""
    /// 本地旁聊行重命名（长按四件之一，0.18.0 沿革）
    @State private var renamingThread: ChatThread?
    @State private var renameText = ""
    /// 删除二次确认的待删线程（0.50.30：真删不可恢
    /// 复，确认门与管理面 ServerSessionRow 同口径）
    @State private var pendingDeleteThread: ChatThread?
    /// 归档/置顶回写服务端未落定的人话原因（§233：
    /// 本地呈现已恢复原状，原因弹报，与删除同式；
    /// 删除失败原因位已随 §232 乐观删除退役——失
    /// 败走恢复＋提醒，不再有本位）
    @State private var archiveFailureReason: String?
    @State private var pinFailureReason: String?
    /// 页头名字字号（2026-11-22 抽屉量测对齐包 C
    /// 项）：基准 24pt bold 对齐 Muse 量测，经
    /// ScaledMetric 相对 title2 样式缩放——Dynamic
    /// Type 缩放保住、不钉死字号（规格与沿革见
    /// TypeRole.drawerTitle 头注）；本面唯一消费点
    @ScaledMetric(relativeTo: .title2)
    private var drawerNamePointSize: CGFloat = 24
    /// 分区折叠账（§158）：按区持久化（Core
    /// SectionCollapseState 唯一口径，键见
    /// DrawerSectionKey），杀 App 重进保持
    @AppStorage(SectionCollapseStorageKeys.drawerSections)
    private var drawerCollapseData: Data = Data()
    /// 分区显隐账消费已退役（结构归位第二批，
    /// 2026-11-20，纲要 D1-1）：本面不再读 Section-
    /// VisibilityState——跨页可见性管理元层级自导
    /// 航面剥离、两区恒在场。账本本体与设置→侧边
    /// 栏管理面的退役归第一批对接（见本包交卷）

    var body: some View {
        // F2（手感快速项，2026-11-23）：账本派生一趟
        // 算清、同源下传——记录合并、标题字典、合并
        // 行集在本趟各算一次（旧形态：行集与逐行标
        // 题解析各自重跑合并、标题逐行线性扫描，整
        // 趟 O(N²)，审计实测 500 条约 9.9ms）；账本
        // 一变本趟必重算——字典不跨趟存活、不显旧名
        let records = ledgerRecords
        let titles = LedgerProjection.titleByLocalThreadID(
            records
        )
        let rows = makeSideRows(records: records)
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
        // ground（WWDC25-323 口径）；顶部标题浮层当
        // 时不动（0.36.5 定版——已于 2026-11-22 抽
        // 屉量测对齐包改顶注册，见 D3 订正注）。
        // Reduce Transparency 下
        // 边缘效果由系统自理（系统自动增不透明），
        // 霜层时代的手排实色回退随霜层一并删除（理
        // 由见 DESIGN §97.3）
        return ZStack(alignment: .bottom) {
            // 0.36.5（D2，用户实拍右缘贯穿长线）：长线
            // 即名单 ScrollView 的默认滚动指示器——关
            // 掉。壳层与本面已查：右缘只有壳层柔影、
            // 无描边/分隔视图，长线来源唯一在此。口
            // 径：Muse 抽屉无边线，与内容只靠材质＋
            // 蒙层分界
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if isSearching {
                        drawerSearchList(rows: rows, titles: titles)
                    } else {
                        drawerNavList(rows: rows, titles: titles)
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
            // 2026-11-22 抽屉量测对齐包订正（覆盖上
            // 段 D3 落法）：主线对 Muse 现行版两图
            // 定位量测证伪「隐约透出同形态」——Muse
            // 机制是钉顶固定＋**列表顶部渐隐带**：
            // 滚动图标题与未滚动图同位（y≈92→94/
            // 1000），列表自标题下方穿过、最上方一
            // 行在标题带内呈半透明渐隐，行文字到达
            // 标题前先溶、永不与字形相撞；本面浮层
            // 无渐隐，行字形直撞标题带（用户当日图
            // 4 实证：「三狗」压「服务器会话」行）。
            // 新落法：身份行改挂名单 .safeAreaBar
            // (edge: .top) 注册（与底条同挂法、全
            // App 顶簇注册口径 §213 同路）＋名单
            // .scrollEdgeEffectStyle(.soft, for:
            // .top)，渐隐由系统在注册栏高内发放。
            // D3 当年撤注册的两病因在本落法下不成立：
            // ①注册不自加 background（WWDC25-323
            // 口径、底条先例）——静止态无独立色带、
            // 带与主体无界；②§318 后根背景是实色单
            // 层、bar 内不再叠 drawerBackdrop——无
            // 双层断层。不做整块不透明色块（Muse
            // 不是色块、§318 面板实色亦不变，渐隐
            // 是内容侧溶解）。带高＝身份行本体高：
            // 立项时 56（顶 8＋头像 44＋底 4）与旧手
            // 排空程逐点恒等、静止布局不变；同日 B
            // 项追加后页头只留名字大标题、带高改 49
            // （顶 12＋题行高 29＋底 8，见身份行注）
            // ——机制（顶注册＋顶缘渐隐）不变、变的
            // 只是栏内构成；名单顶 contentMargins
            // 随注册留位退役
            // 0.36.27：末行与注册底条之间留一档小间隙
            // （与聊天页列表底口径同式）；注册留位之外
            // 本面唯一的底部手排数
            .contentMargins(
                .bottom, OneDayMetrics.spacingS, for: .scrollContent
            )
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // 2026-11-22 抽屉量测对齐包：顶缘同挂
            // .soft——身份行顶注册后，行滚入标题带
            // 前先溶（Muse 钉顶＋渐隐机制，见上方
            // D3 订正注）；与设置页顶缘同式
            .scrollEdgeEffectStyle(.soft, for: .top)
            // 0.36.27（§97 件三）：底条注册（与聊天页
            // bottomBar 同挂法）——搜索态与普通态两套
            // 名单共用本 ScrollView，注册只此一处、两
            // 态一致
            .safeAreaBar(edge: .bottom) {
                drawerBottomBar
            }
            // 2026-11-22 抽屉量测对齐包：身份行改顶
            // 注册（与底条同挂法）——标题钉顶固定由
            // 注册承接、顶部渐隐由名单 .scrollEdge-
            // EffectStyle(.soft, for: .top) 在本栏
            // 高内发放（机制注见 D3 订正）；0.36.5
            // 的 ZStack 标题浮层（VStack＋Spacer 不
            // 承命中）随之退役，身份行本体与承命中
            // 口径（整行可点开编辑菜单）一字不变
            .safeAreaBar(edge: .top) {
                drawerIdentityRow
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        // 面板底穿过上下安全区（0.4.1 第 10 修沿革：
        // 顶边贴到屏幕顶、底边直达屏底，形态不变）
        // §318（2026-11-17 用户拍板）：面板底改**不透
        // 明实色**——0.36.3 的 thinMaterial 半透定案
        // 作废。出处：用户当日亲递 Muse 侧边栏基准
        // （纯黑实色、全幅盖严、主内容透出为零）并点
        // 名「这个就很好」；半透档在 .64 真机帧里呈深
        // 灰且动画中段叠加柔边/露底后「盖不严」观感
        // 成立（诊断 drawer-broken-diagnosis-
        // 20261117.md §5-①）。落色走 Palette.chat-
        // Surface 既有口径（浅 #FCFCFC／深 system-
        // Background 纯黑——与旧实板、减透明回退同
        // 档），全开与动画中段均零透出；减透明回退
        // 分支随材质退役（实色本体即回退终点、无分
        // 支可言）。私有 variableBlur 永不碰（E11
        // 已注销）
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
                    performDeleteThread(thread)
                }
            }
            Button("取消", role: .cancel) { pendingDeleteThread = nil }
        } message: {
            if let thread = pendingDeleteThread {
                Text("「\(drawerDisplayTitle(for: thread, titles: titles))」删除后不可恢复。")
            }
        }
        .alert(
            "没改成",
            isPresented: Binding(
                get: { archiveFailureReason != nil },
                set: { if !$0 { archiveFailureReason = nil } }
            )
        ) {
            Button("好", role: .cancel) { archiveFailureReason = nil }
        } message: {
            Text(archiveFailureReason ?? "")
        }
        .alert(
            "没改成",
            isPresented: Binding(
                get: { pinFailureReason != nil },
                set: { if !$0 { pinFailureReason = nil } }
            )
        ) {
            Button("好", role: .cancel) { pinFailureReason = nil }
        } message: {
            Text(pinFailureReason ?? "")
        }
        // 身份编辑页呈现已随页头改版撤出本面（2026-
        // 11-22 抽屉量测对齐包 B 项）：编辑入口归中
        // 枢身份行档案菜单与设置·身份详情两处既有家
        // （编辑页本体 AgentAvatarEditors 不动）
        // §162 状态呈现收敛：关抽屉（开→关一沿，Core
        // DrawerSearchPolicy 裁决）即复位搜索词——旧
        // 行为词残留到下次打开、入口直接落在上次的
        // 过滤态，与「重开呈默认态」不是一个状态；
        // 收敛后入口状态只许一个（全量名单＋空框）
        .onChange(of: appState.router.drawerPresented) { wasPresented, presented in
            if !presented, DrawerSearchPolicy.shouldResetQuery(
                wasPresented: wasPresented, isPresented: presented
            ) {
                drawerQuery = ""
            }
        }
        // §365 D2：开抽屉的账本可见段刷新（第 67 条
        // 包一：source/标题改读账本记录列）＋身份重拉
        // 的触发点，自语义翻转拍迁到开落定拍——旧形
        // 态两路在翻转即发、完成发布正落在 0.27s 动
        // 画窗内，名单/页头在滑动途中重渲染（调研
        // D2）；落定后落写与成熟做法「打开零数据工
        // 作、落定才应用」同构。新鲜度口径不变：名
        // 单本体是本地 @Query（开帧即现行数据）、身
        // 份重拉仍每次打开必发（节流在 AppState
        // 内），不许显旧身份不破
        // §370 补：名单一路自此先过账本新鲜度门
        // （60s）——落定触发点不变、只是新鲜时零请
        // 求；身份一路口径不变（自有 30s 节流、不入
        // 本门）
        .onChange(of: appState.router.drawerOpenSettledCount) {
            Task { await loadDrawerDataIfNeeded() }
            // 身份呈现跟随（末写胜包）：抽屉页头就
            // 是名字与头像——每次打开重拉（节流在
            // AppState 内），不许显服务器已改掉的旧
            // 身份
            Task { await appState.refreshIdentitySurfaces() }
        }
        // 0.7.1（裁决 §3.5 S5 预挂载）：壳层在左缘触摸
        // 按下时即挂载本面抢建树——本面出现即补拉一
        // 次作预取（本地名单由 @Query 随挂载自动建
        // 树），语义打开时仍走上方 onChange 的拉取
        .onAppear {
            if !appState.sessionLedger.hasLoaded {
                Task { await loadDrawerDataIfNeeded() }
            }
        }
        // 0.21.0 标题回流触发点补环：App 回前台重拉
        // （切后台期间服务端标题可能已升级；此前注
        // 释自称「开抽屉/回前台」实则只有开抽屉一
        // 路，本版坐实）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await loadDrawerDataIfNeeded() }
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

    /// 抽屉底（§318，2026-11-17 用户拍板改实色）：
    /// 恒 Palette.chatSurface 不透明实色（浅
    /// #FCFCFC／深纯黑），全幅盖严、零透出——
    /// 0.36.3 thinMaterial 半透定案与减透明回退分
    /// 支一并退役（定案变更出处见 body 背景注）。
    /// 本色即旧实板与回退分支一直用的同档，面板与
    /// 聊天表面同锚
    private var drawerBackdrop: some View {
        Palette.chatSurface
    }

    /// 抽屉数据刷新（第 67 条包一收编）：旧形态本面
    /// 自拉第一页建 source/标题映射（0.19.0/0.20.0）
    /// ＋目录冷补拉一路；自此只触发账本可见段刷新
    /// ——拉取全 App 只剩账本一处发起源，source/标
    /// 题改读记录列（全量名单、不再限第一页窗口）
    private func loadDrawerData() async {
        await appState.sessionLedger.refreshVisible(
            appState: appState, localThreads: threads
        )
    }

    /// 读触发路（§370）：落定/回前台/预挂载先过账
    /// 本新鲜度门——TTL 内重复打开零请求、新鲜时
    /// 直接用已载名单；强制路（刷新令牌、行操作
    /// onChanged）仍走上方 loadDrawerData 直拉
    private func loadDrawerDataIfNeeded() async {
        await appState.sessionLedger.refreshVisibleIfNeeded(
            appState: appState, localThreads: threads
        )
    }

    /// 旁聊行显示名（0.20.0 第三条口径不变、数据源
    /// 换账本）：记录标题列即 DrawerThreadTitle 解
    /// 析结果（手改名＞服务端 AI 标题＞本地派生快
    /// 照，合并时以全量名单算）；记录缺失（线程未
    /// 注入本轮合并）回落本地标题
    private func drawerDisplayTitle(for thread: ChatThread) -> String {
        // F2（手感快速项，2026-11-23）：标题解析改字
        // 典直达——旧形态逐行 first(where:) 线性扫
        // 描记录表（名单派生 O(N²) 本体）；现一趟建
        // 字典（LedgerProjection.titleByLocal-
        // ThreadID、首个命中优先）＋O(1) 查，语义逐
        // 字不变（记录缺失回落本地标题）。本式只剩
        // 动作路径（改名预填／删除执行）调用，手势
        // 频次、现建一趟与旧单次调用同级
        LedgerProjection.titleByLocalThreadID(ledgerRecords)[
            thread.id
        ] ?? thread.title
    }

    /// 呈现路径版（F2）：字典由 body 一趟建成下传
    /// （见 body 头注），行渲染只查不建
    private func drawerDisplayTitle(
        for thread: ChatThread,
        titles: [UUID: String]
    ) -> String {
        titles[thread.id] ?? thread.title
    }

    /// 页头（§157 第一批①立、2026-11-22 抽屉量测
    /// 对齐包 B/C 项改版）：只留名字大标题——去头
    /// 像 44 与铅笔钮，与 Muse 抽屉图 1/2 同形态
    /// （用户 2026-11-21 亲定的抽屉三差①在本包落
    /// 地）；名字字号按 C 项落 24 基准可缩放（见
    /// drawerNamePointSize 注）。身份编辑入口不丢
    /// 失：中枢身份行档案菜单（AgentHubView，同两
    /// 项：更换虚拟形象/编辑名称）与设置·身份详情
    /// （IdentityDetailView）两处既有家都在，编辑
    /// 页本体（AgentAvatarEditors）三处共用、本包
    /// 不动；本面旧 Menu＋两张 sheet 呈现随改版退
    /// 役。名字读 AppState 单一出口（档案覆盖→
    /// soul 名），与全 App 露脸面同源。
    /// 栏高算式：顶 spacingSM 12＋题行高（24 bold
    /// 行高 29）＋底 spacingS 8＝49——顶注册栏高自
    /// 此 49（旧身份行形态 56 的恒等沿革见 body
    /// D3 订正注）；名字墨顶距安全区顶实算 ≈15.4
    /// （12＋(29−22)/2），对 Muse 量测 13.7 差
    /// +1.7、在 ±2 归一线内
    private var drawerIdentityRow: some View {
        Text(appState.agentDisplayName)
            .font(.system(size: drawerNamePointSize, weight: .bold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.drawerInset)
            .padding(.top, OneDayMetrics.spacingSM)
            .padding(.bottom, OneDayMetrics.spacingS)
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
    /// 名单结构（结构归位第二批，2026-11-20，纲要
    /// D0-1/D1-1/D2-1）：自上而下＝主线行→「旁聊」
    /// 分区（会话列表，本面顶点）→「频道」分区→
    /// 「全部对话」收尾行。逐项口径：
    /// ①旧「选项卡」分区整组退役——动态／点子／目
    /// 标／资源库四行与前景 TabView 同目的地双挂
    /// （D0-1、原则 2），收口后五个格只在底栏一处
    /// 当家。其中「主线聊天」行语义不是切格而是回
    /// 主线线程（底栏格不承担回主线语义，见主线行
    /// 注），故以独立行形态留在名单顶部、动作与旧
    /// 行一字不变，不随组退役。
    /// ②分区次序对调：旁聊（会话列表）升 L1 顶点、
    /// 频道降 L2（纲要抽屉目标树）；旧序「频道插在
    /// 选项卡与旁聊之间」随选项卡组退役一并作废。
    /// ③分区显隐账退役：本面不再读 SectionVisibi-
    /// lityState、sectionGates 合成整件退役——两区
    /// 恒在场（频道恒显清单、旁聊空时留弱字行），
    /// 「配置我自己」的跨页可见性管理元层级自导航
    /// 面剥离（D1-1、原则 2 的管理面收口）；折叠账
    /// 保留（纲要明定折叠保留）。设置→侧边栏管理
    /// 面与 Core 显隐账本体的退役归第一批对接（见
    /// 本包交卷对接点），本面先断消费。
    /// ④分割线沿 R1–R10 旧口径：线恒挂下行分区组
    /// 头上方、与折叠态无关（R2/R6）；首行（主线
    /// 行）无顶线（R8）；「全部对话」收尾行上方挂
    /// 线与分区边界同式；不渲染的区连线退场（R7）
    /// 在本面已无适用对象（两区恒在场）
    /// ⑤台账 194（2026-11-21 用户 08:15 真机点题
    /// 「顺序不对、点子/动态/目标/资源库不见了、
    /// 全部对话/主聊没有归类」＋同日 00:39「抽屉
    /// 学 Muse 样板全部、含布局」令）：①的整组
    /// 退役与②的次序对调就此改判——「选项卡」分
    /// 区恢复（组头＋主线聊天／动态／点子／目标／
    /// 资源库四行，行本体逐字回收退役前装配），
    /// 次序回旧序「选项卡→频道→旁聊」（与样板同
    /// 序）；「全部对话」收尾行迁入选项卡组作第
    /// 六行归类（D2-1 一级入口语义与路由旗动作不
    /// 变、只迁装配位置，§198 第六行先例同位）。
    /// ③显隐账退役不恢复（三区恒在场、折叠账保
    /// 留）；④分割线口径不变、线随次序改挂频道／
    /// 旁聊组头上方。192 视觉量测值全保留、本条
    /// 只动内容装配；装配回归钉见 DrawerIAAssem-
    /// blyUITests（UI 测试——进程内单测环境 AX 树
    /// 不填充、本仓已有实证）
    private func drawerNavList(
        rows: [DrawerSideRow], titles: [UUID: String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            drawerTabSection
            // R2 边界线：恒挂频道组头上方，与频道区
            // 折叠态无关
            drawerDivider
                .padding(.top, OneDayMetrics.spacingS)
            drawerChannelSection
            // R2 边界线：恒挂旁聊组头上方，与旁聊区
            // 折叠态无关
            drawerDivider
                .padding(.top, OneDayMetrics.spacingS)
            drawerSideSection(rows: rows, titles: titles)
            Color.clear
                .frame(height: OneDayMetrics.spacingL)
        }
        .padding(.top, OneDayMetrics.spacingS)
    }

    /// 「选项卡」分区（台账 194 恢复）：组头＋六行
    /// ——主线聊天／动态／点子／目标／资源库／全部
    /// 对话。四导航行与主线行本体逐字沿退役前装配
    /// （fc93ea8^ 回收，动作与选中政策一字未改）；
    /// 全部对话行即原名单收尾行本体迁入作第六行
    /// （动作仍经路由旗根级呈现，只迁装配位置）。
    /// 折叠走既有折叠账 navigation 键、组头走
    /// drawerCollapsibleHeader 既有口径（192 视觉值
    /// 随件自带：stateText 尾件＋块高 36＋样板头墨）
    @ViewBuilder
    private var drawerTabSection: some View {
        drawerCollapsibleHeader(
            "选项卡", key: DrawerSectionKey.navigation
        )
        drawerCollapsibleContent(
            collapsed: drawerSectionCollapsed(
                DrawerSectionKey.navigation
            )
        ) {
            drawerMainThreadRow
            // 0.35.0（P3 五格）：动态行与底栏同序进
            // 「选项卡」组（194 恢复时逐字回收）
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
                // 0.20.0 第七条：应用格改文件格，导航
                // 行同步改「资源库」（符号与底栏同源
                // files 对）
                symbol: TabBarSymbols.files.normal,
                title: "资源库",
                selected: drawerSelection == .surface(.files)
            ) {
                onClose()
                onSelectTab(.files)
            }
            drawerAllConversationsRow
        }
    }

    /// 主线行（旧「选项卡」组首行；第二批随组退役
    /// 迁出作独立行、台账 194 随组恢复归组，动作沿
    /// 革见旧行注）：本行是显式回主线的唯一入口——经线
    /// 程选择通道直切钦定主线（ChatView 消费切换、
    /// 并经落点记忆落盘）；底部页签本身不承担回主
    /// 线语义（点页签回上次对话，见 ChatLanding-
    /// Resolution）。钦定尚未落定时只切页签，
    /// ChatView 落点解析会以主线兜底
    private var drawerMainThreadRow: some View {
        drawerNavRow(
            symbol: TabBarSymbols.chat.normal,
            title: "主线聊天",
            // 0.36.7：本行在单一政策里是主线会话的
            // 代表行——只有「正在看主线」时带胶囊，
            // 不再是「人在聊天表面」的指示（§10.2）
            selected: drawerSelection == .main
        ) {
            // 台账 147：延迟导航待办在位时整下忽
            // 略（OB 连点口径——关抽屉途中第二下
            // 点按不重复跳页、首个待办为准）
            guard !appState.router.hasPendingDrawerNavigation
            else { return }
            onClose()
            // 0.30.0（用户 12:56 录屏点名 Muse 模
            // 型）：经线程选择通道直切钦定主线；
            // 台账 147：线程切换改经延迟导航置位
            // 口——关到近闭合才落真值跳页（落真值
            // 时 ContentView 的 onChange 自会切格，
            // 与旁聊行同一条路）；钦定尚未落定（无
            // 主线 id）时无线程可延迟、仍即时只切
            // 页签（旧口径兜底不变）
            if let mainID = appState.sessionLedger.mainThreadID {
                appState.router.stageDrawerThreadSelection(mainID)
            } else {
                onSelectTab(.chat)
            }
            // 0.36.7（§10.3 置位纪律）：导航动作显
            // 式写当前对象引用，胶囊随点按即归主线
            // 0.36.29：回主线即离频道出处（§10.3
            // 置位点清零），防残留出处把后续同步带
            // 回 .channel
            appState.router.channelViewingOrigin = nil
            appState.router.currentDrawerObject = .main
        }
    }

    /// 「全部对话」行（结构归位第二批，纲要 D2-1
    /// 立项为名单收尾行；台账 194 迁入「选项卡」
    /// 组作第六行归类，一级入口语义不变）：全量
    /// 会话列表升一级面，入口住名单自身，不再埋
    /// 设置三级路径。点按
    /// 先收抽屉、再经路由旗请根级呈现（ContentView
    /// 消费 allConversationsRequested，与设置齿轮
    /// 的 settingsSheetRequested 同式）；行形态随
    /// 导航行同簇（字形＋标题），行尾加 chevron 示
    /// 「进一整页」（与全部对话页内频道行同式）
    private var drawerAllConversationsRow: some View {
        Button {
            onClose()
            appState.router.allConversationsRequested = true
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "rectangle.stack")
                    // 字形口径随导航行同档（见
                    // drawerNavRow 注）
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
                Text("全部对话")
                    .font(.drawerNavTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                DisclosureChevron(font: .system(size: FrameworkIcon.composerGlyphSize))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OneDayMetrics.drawerNavRowHeight)
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.spacingS)
        .accessibilityLabel("全部对话")
    }

    // MARK: - 频道区（0.36.29，频道规格 §3）

    /// 分区渲染合成（§198）已退役（结构归位第二
    /// 批，2026-11-20，纲要 D1-1）：显隐账是合成的
    /// 唯一输入、账退役则合成无物可合——两区恒在
    /// 场，呈现不再经任何闸。Core DrawerSection-
    /// Gates 与 SectionVisibilityState 本体随设
    /// 置→侧边栏管理面一并归第一批对接退役，本面
    /// 只断消费、不动 Core

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
    /// 本行展示名 2026-11-14 用户拍板改「服务器会
    /// 话」（§241 大厂九项⑨，内部 id 仍 hermes），
    /// 宪法 §7）；**不给计数徽标**（抽屉拉取口径与全量
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
                            // 2026-11-21 样板对齐包：品牌资
                            // 产 21→28＋圆角 6 裁形——样板
                            // 彩色缩略图实测约 28×28、圆角
                            // 约 6（28 的 22%、app-icon 比
                            // 例）；§101「资产落字形档 21
                            // 防卡片感」口径就此让位样板原
                            // 形（用户当日亲令学全），资产
                            // 在 30 槽内居中、左缘 21 对样
                            // 板 22（Δ1）
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(
                                cornerRadius: 6, style: .continuous
                            ))
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
                    DisclosureChevron(font: .caption2.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OneDayMetrics.drawerNavRowHeight)
            // OpenBot 样式采纳包（2026-11-20）：选中垫
            // 改整行贴边填充——去旧外层 spacingS 缩进、
            // 内边距改 drawerInset 直达（标题/图标起点
            // 恒 20 线不变），圆角改 drawerSelection-
            // Corner 16；三行（导航/频道/旁聊）同改同口径
            .padding(.horizontal, OneDayMetrics.drawerInset)
            .background {
                if selected {
                    // 2026-11-21 样板对齐包：选中垫改全
                    // 圆角 Capsule——样板实测 stadium（高
                    // 44、半径 22＝行高之半、圆拟合验
                    // 证）；旧 fieldCorner 19 圆角矩形仅
                    // 抽屉三行退场，字段面本体不动
                    Palette.drawerSelectionFill
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(
            accessory.word.map { "\(channel.name)，\($0)" }
                ?? channel.name
        )
        // 0.43.0（A11Y-V5）：选中态只靠胶囊底色——
        // 补已选特征，VO 不靠颜色辨当前频道
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .drawerRowContextMenu {
            Button {
                onClose()
                onOpenChannel(channel.id)
            } label: {
                Label("打开", systemImage: "arrow.up.right")
            }
        }
        .accessibilityIdentifier("drawer.row.channel.\(channel.id)")
    }

    /// 频道行尾件（频道扩展一期，冻结行尾随二期微
    /// 信行下架退役）：状态小字＋chevron 的唯一裁决
    /// 处。Hermes 行恒空尾；已配对平台同空尾（与
    /// Hermes 行同形态）；令牌型未配对/等待生效/
    /// 失败带小字＋chevron；状态未回（未加载/读取
    /// 失败）时只有 chevron（目的地是入口页、会在
    /// 页内把状态说清）
    private func drawerChannelAccessory(
        _ channel: ChannelDescriptor
    ) -> (word: String?, chevron: Bool) {
        switch ChannelRegistry.pairingKind(for: channel.id) {
        case .none:
            return (nil, false)
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
    private func drawerSideSection(
        rows: [DrawerSideRow], titles: [UUID: String]
    ) -> some View {
        drawerCollapsibleHeader("旁聊", key: DrawerSectionKey.sideChats)
        drawerCollapsibleContent(
            collapsed: drawerSectionCollapsed(DrawerSectionKey.sideChats)
        ) {
        if rows.isEmpty {
            Text("还没有旁聊")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OneDayMetrics.drawerInset)
                .padding(.bottom, OneDayMetrics.spacingS)
        } else {
            ForEach(rows) { row in
                drawerSideRowView(row, titles: titles)
            }
        }
        }
    }

    /// 搜索态名单：只显命中的旁聊行（导航组与管理行
    /// 隐藏，与 0.18.0 抽屉搜索同行为）；无命中给弱
    /// 字一行，不留空白屏
    @ViewBuilder
    private func drawerSearchList(
        rows: [DrawerSideRow], titles: [UUID: String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // §158：搜索态头走同一折叠件但状态被呈现
            // 层强制为展开（搜到一半不许被折叠挡住）；
            // 点它切换的是同一本账（旁聊区键）
            CollapsibleSectionHeader(
                title: "旁聊",
                isCollapsed: false,
                titleFont: .sectionLabel,
                // 2026-11-21 样板对齐包：与常态分区头
                // 同形态（stateText＋块高 36＋样板头
                // 墨，见 drawerCollapsibleHeader 注）；
                // 搜索态恒展开、尾件自然留空
                trailingStyle: .stateText,
                minHeight: 36,
                onToggle: {
                    toggleDrawerSection(DrawerSectionKey.sideChats)
                }
            )
            .foregroundStyle(Palette.drawerSectionInk)
            .padding(.horizontal, OneDayMetrics.drawerInset)
            if rows.isEmpty {
                Text("没有匹配的旁聊")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OneDayMetrics.drawerInset)
                    .padding(.bottom, OneDayMetrics.spacingS)
            } else {
                ForEach(rows) { row in
                    drawerSideRowView(row, titles: titles)
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
            currentObject: appState.router.currentDrawerObject,
            landingThreadID: nil,
            mainThreadID: appState.sessionLedger.mainThreadID
        )
    }

    /// 账本合并名单（第 67 条包一）：本面名单的唯
    /// 一输入——@Query 本地线程注入账本、与账本服
    /// 务端段现场合并；行集/排序/标题全读记录列，
    /// 本面不再自拉名单、不再自算行集
    private var ledgerRecords: [SessionRecord] {
        appState.sessionLedger.records(
            appState: appState, localThreads: threads
        )
    }

    private var threadsByID: [UUID: ChatThread] {
        Dictionary(
            uniqueKeysWithValues: threads.map { ($0.id, $0) }
        )
    }

    /// 旁聊区合并行集（账本投影＋本面搜索）：行集
    /// 与合并排序走 LedgerProjection.drawerSideRows
    /// （本地行＋未收养行同区平铺、活动时间倒序）；
    /// 搜索沿旧口径（0.18.0/§162）——本地行按记录
    /// 标题（＝显示名）或任一条目内容、未收养行按
    /// 服务端标题管线（resolvedTitle、素材传 nil
    /// 与旧行同式），不区分大小写
    private func makeSideRows(
        records: [SessionRecord]
    ) -> [DrawerSideRow] {
        let query = DrawerSearchPolicy.normalizedQuery(
            drawerQuery
        )
        var rows: [DrawerSideRow] = []
        for record in LedgerProjection.drawerSideRows(
            records
        ) {
            if let threadID = record.localThreadID,
               let thread = threadsByID[threadID] {
                if !query.isEmpty {
                    let hit = record.title
                        .localizedCaseInsensitiveContains(query)
                        || thread.entries.contains {
                            $0.content
                                .localizedCaseInsensitiveContains(
                                    query
                                )
                        }
                    guard hit else { continue }
                }
                rows.append(.thread(thread))
            } else if let session = record.session {
                if !query.isEmpty {
                    guard session.resolvedTitle(
                        firstUserMessage: nil
                    ).localizedCaseInsensitiveContains(query)
                    else { continue }
                }
                rows.append(.unadopted(session))
            }
        }
        return rows
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
    private func drawerSideRowView(
        _ row: DrawerSideRow, titles: [UUID: String]
    ) -> some View {
        switch row {
        case .thread(let thread):
            drawerSideThreadRow(thread, titles: titles)
        case .unadopted(let session):
            drawerUnadoptedSideRow(session)
        }
    }

    /// 未收养旁聊行（2026-11-13 P2 修复）：与本地行
    /// 同式（标题单件、行高与内距同档；行尾紧凑时
    /// 间已于 2026-11-22 抽屉量测对齐包随本地行同
    /// 批删除）；标题走服务端标题管线（resolved-
    /// Title——AI 给的名字如「爱的定义」直达）。无当前位胶
    /// 囊（当前线程恒为本地线程）；点行＝走既有续聊通道点
    /// 达（pendingChatSessionID 置位，与回响卡/管
    /// 理页/频道页同一路）：ContentView 切聊天格、
    /// ChatView 导入建本地线程即收养——收养后本行
    /// 现算自动消失、由本地行接管（全功能）
    private func drawerUnadoptedSideRow(
        _ session: ServerSession
    ) -> some View {
        ServerSessionRow(
            session: session,
            title: session.resolvedTitle(firstUserMessage: nil),
            onOpen: {
                appState.router.pendingChatSessionID = session.id
                onClose()
            },
            onChanged: { Task { await loadDrawerData() } },
            onDeleteRequested: { session in
                // §232 乐观删除（组版收口）：确认即协
                // 调器起手——目录摘行同拍消失、后台删，
                // 落定物理收口与最终失败恢复＋提醒由
                // 协调器统一走（本行原接的 §223 落定
                // onDeleted 收口钩已随乐观时序退役）
                appState.sessionDeletions.begin(
                    sessionID: session.id,
                    title: session.resolvedTitle(
                        firstUserMessage: nil
                    ),
                    appState: appState,
                    modelContext: modelContext
                )
            },
            deleteMenuTitle: "删除会话"
        ) {
            // 2026-11-22 抽屉量测对齐包：行尾时间删
            // ——与本地行同口径只留标题（用户亲令、
            // 对 Muse 旁聊行只有标题的形态）；旧
            // trailing 时间组与 AX 档上下排列分支随
            // 之退役（标题单件无需分档排向）
            Text(
                session.resolvedTitle(firstUserMessage: nil)
            )
            .font(.drawerRowTitle)
            .foregroundStyle(Palette.ink)
            .a11yLineLimit(1, ax: 2)
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .frame(
                maxWidth: .infinity,
                minHeight: OneDayMetrics.drawerRowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .padding(.horizontal, OneDayMetrics.spacingS)
        .accessibilityIdentifier("drawer.row.side.server.\(session.id)")
    }

    /// 旁聊行（0.17.0 单行形态沿用、0.19.0 返工去角
    /// 标）：标题＋当前位浅灰垫（行尾小字时间已于
    /// 2026-11-22 抽屉量测对齐包整段删除、只剩置
    /// 顶钉，见 label 内注）；点按
    /// 经 drawerThreadSelection 请 ChatView 切换并关
    /// 抽屉（0.4.5 通道化沿革）；长按四件与 0.18.0
    /// 本地行同序（重命名/置顶/归档/删除）——置顶只
    /// 落数据（isPinned），抽屉呈现恒时间序（22:45
    /// 平铺口径），置顶的呈现归管理页等其他面
    /// §157③④：置顶呈现口径变更——抽屉行内补图钉标
    /// 记（排序仍恒时间序、不学管理页的置顶分段）；
    /// 时间改紧凑口径、选中改字重＋浅灰底统一规则、
    /// AX 档标题/时间上下排列，逐项见 label 内注
    /// （时间呈现已于 2026-11-22 整段退役、AX 排
    /// 列随之只剩标题与置顶钉两件，见 label 内注）
    private func drawerSideThreadRow(
        _ thread: ChatThread, titles: [UUID: String]
    ) -> some View {
        // 0.36.7：当前位只认单一政策（§10.2）——正在
        // 看这条旁聊时胶囊只归本行、主线聊天行无胶囊
        let isCurrent = drawerSelection == .side(thread.id)
        return Button {
            // 台账 147：延迟导航待办在位时整下忽略
            // （OB 连点口径）；切换改经延迟置位口，
            // 关到近闭合才跳页（对象引用仍即时写——
            // 胶囊是抽屉内呈现、随点按即归位）
            guard !appState.router.hasPendingDrawerNavigation
            else { return }
            appState.router.stageDrawerThreadSelection(thread.id)
            // 0.36.7（§10.3 置位纪律）：导航动作显式
            // 写当前对象引用
            // 0.36.29（§10.4-⑤）：从旁聊区进入即离频
            // 道出处——哪怕进的是刚从频道收养的同一
            // 条线程，胶囊也随入口归旁聊行，出处必须
            // 在此清零（否则 ChatView 同步会按残留出
            // 处又把引用派生回 .channel）
            appState.router.channelViewingOrigin = nil
            appState.router.currentDrawerObject = .side(thread.id)
            onClose()
        } label: {
            // §157③④：标题与行尾两件先成件、再按字号
            // 档排向——常态横排（标题抢宽、行尾靠右）；
            // AX 大字体档上下排列（标题在上、行尾在其
            // 下左对齐），不再横向互挤
            let title = Text(
                drawerDisplayTitle(for: thread, titles: titles)
            )
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
                            size: FrameworkIcon.badgeGlyphSize,
                            weight: .semibold
                        ))
                        .foregroundStyle(Palette.inkSecondary)
                        .accessibilityHidden(true)
                }
                // 2026-11-22 抽屉量测对齐包：行尾时间
                // 整段删除（用户亲令「对话边没有时
                // 间」、对 Muse 旁聊行只有标题的形
                // 态）——trailing 自此只剩置顶钉一件；
                // compactTimeText 本体不动（服务端副
                // 题等他面同源消费）、排序恒时间序不
                // 变。旧时间呈现沿革（§157④紧凑口径/
                // meta 角色/inkSecondary 对比改档）随
                // 本段退役
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
            // 频道行同为 8 线、形状同为全圆角 Capsule
            // （2026-11-21 样板对齐包改，见频道行注）；
            // 标题起点仍恒 20（8＋12）不变
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .frame(
                maxWidth: .infinity,
                minHeight: OneDayMetrics.drawerRowHeight,
                alignment: .leading
            )
            .background {
                if isCurrent {
                    // 2026-11-21 样板对齐包：选中垫改全
                    // 圆角 Capsule（口径见频道行注）
                    Palette.drawerSelectionFill
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        // §157④：图钉是纯视觉标记——置顶状态经 acces-
        // sibilityValue 补播报（标题的内容自读不受
        // 影响）；未置顶行值为空、不出声
        .accessibilityValue(
            thread.isPinned ? L10n.string("已置顶") : ""
        )
        .drawerRowContextMenu {
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
                performArchiveThread(thread)
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                pendingDeleteThread = thread
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        }
        .accessibilityIdentifier(
            "drawer.row.side.local.\(thread.id.uuidString)"
        )
    }

    /// 抽屉置顶（§233 件七）：本地呈现当拍先翻；绑定
    /// 会话过回写闸（SideChatLink.mayWriteThroughTo-
    /// Server）时同步回写服务端 pinned，与全部对话
    /// 页同一账——不再抽屉一份、服务端一份。回写失
    /// 败翻回呈现＋弹原因（在飞期间又被改动则不回滚，
    /// 防覆盖用户的新选择）；无绑定/主线/合并桶维持
    /// 本地账（闸口径）
    private func togglePinThread(_ thread: ChatThread) {
        let target = !thread.isPinned
        thread.isPinned = target
        try? modelContext.save()
        guard let sessionID = thread.serverSessionID,
              SideChatLink.mayWriteThroughToServer(
                  sessionID: sessionID,
                  mainSessionID: appState.sessionLedger
                      .mainServerSessionID
              ) else { return }
        Task {
            let outcome = await ServerSessionActions.setPinned(
                appState: appState, id: sessionID, pinned: target
            )
            if case .failed(let reason) = outcome {
                if thread.isPinned == target {
                    thread.isPinned = !target
                    try? modelContext.save()
                }
                pinFailureReason = reason
            }
        }
    }

    /// 抽屉归档（§233 件六，归档单真相）：行当拍先隐
    /// 藏（本地键自此只是服务端归档态的呈现缓存）；
    /// 绑定会话过回写闸时走 ServerSessionActions.
    /// setArchived 落服务端——与全部对话页同一账，
    /// 服务端是归档真源。回写失败撤缓存键、行恢复＋
    /// 弹原因；读面收敛在全部对话页名单对账（sync-
    /// DrawerArchiveCache）。无绑定/主线/合并桶维持
    /// 本地账（合并桶的服务端归档须走管理页带牵连
    /// 说明的二次确认，抽屉菜单不许绕过）
    private func performArchiveThread(_ thread: ChatThread) {
        appState.sessionLedger.archive(localThreadID: thread.id)
        guard let sessionID = thread.serverSessionID,
              SideChatLink.mayWriteThroughToServer(
                  sessionID: sessionID,
                  mainSessionID: appState.sessionLedger
                      .mainServerSessionID
              ) else { return }
        Task {
            let outcome = await ServerSessionActions.setArchived(
                appState: appState, id: sessionID, archived: true
            )
            if case .failed(let reason) = outcome {
                appState.sessionLedger.unarchive(
                    localThreadID: thread.id
                )
                archiveFailureReason = reason
            }
        }
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
            //
            // §233 对账口径注记（件七，审计 §8 复核后
            // 的明示切割）：此手改名是**本机显示名**，
            // 按既定设计**不回写服务端标题**——它与服
            // 务端标题不是双账：呈现真值由 Drawer-
            // ThreadTitle 单一口径裁决（手改名＞服务端
            // AI 标题＞本地快照），手改标记的职责只是
            // 防 AI 标题回流覆盖用户手改。代价明示：
            // 服务端本体与网页端仍显服务端标题；要改
            // 服务端标题走全部对话页的服务端改名
            // （ServerSessionActions.rename，PATCH＋
            // 回读对账）。此切割与文件置顶的「仅本机」
            // 明示同式，不许后人误当双账事故再「修」
            thread.titleIsManual = true
            try? modelContext.save()
        }
        renamingThread = nil
    }

    /// 删除流（§232 乐观删除，用户 2026-11-14 亲
    /// 定口径，覆盖 0.50.30「服务端先行、回查落定
    /// 才动本地」）：本线程自建的旁聊会话（Core 真
    /// 删闸 mayHardDeleteOnThreadDelete）确认后即
    /// 交 SessionDeletionCoordinator——本地先删
    /// （墓碑＋目录摘行、同拍消失），服务端围栏删
    /// 在后台跑，最终失败自动恢复＋提醒；本面不
    /// 再等服务端、不再弹「没删掉」拦人。其余线
    /// 程（未链接/导入会话/合并桶绑定）维持只删
    /// 本地、服务端零动作；主线线程在本面无删除
    /// 入口（既有保护不动），协调器与真删闸对主
    /// 线会话本体另有双重拦截
    private func performDeleteThread(_ thread: ChatThread) {
        if let linkedSessionID = thread.serverSessionID,
           SideChatLink.mayHardDeleteOnThreadDelete(
               sessionID: linkedSessionID,
               mainSessionID: appState.sessionLedger.mainServerSessionID
           ) {
            appState.sessionDeletions.begin(
                sessionID: linkedSessionID,
                title: drawerDisplayTitle(for: thread),
                appState: appState, modelContext: modelContext
            )
            return
        }
        DeletedSessionCloseout.deleteLocalThread(
            thread, appState: appState, modelContext: modelContext
        )
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
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.sectionCollapse, reduceMotion: reduceMotion
            )
        ) {
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
    /// sectionLabel、颜色在本面补——公用件不私定颜
    /// 色），外距 drawerInset 横距＋顶距 S
    /// 2026-11-21 样板对齐包三改：①色 inkSecondary
    /// →drawerSectionInk（样板分组头原值 #9D9DA2、
    /// 代价与口径见该令牌注）；②尾件 chevron→
    /// stateText（折叠出「显示」、展开留空，样板两
    /// 态实测）；③块高 44→36、底距 SM→0——组节奏
    /// 按样板实测重排：展开头墨底→首行 12.2（样板
    /// 10.3、Δ1.9）、折叠头墨顶→线 31.9（32.0）、
    /// 线→次头墨顶 20.2（20.0）、折叠块距 52.0
    /// （52.0），逐项对账见交卷对位表
    private func drawerCollapsibleHeader(
        _ title: String, key: String
    ) -> some View {
        CollapsibleSectionHeader(
            title: title,
            isCollapsed: drawerSectionCollapsed(key),
            titleFont: .sectionLabel,
            trailingStyle: .stateText,
            minHeight: 36,
            onToggle: { toggleDrawerSection(key) }
        )
        .foregroundStyle(Palette.drawerSectionInk)
        .padding(.horizontal, OneDayMetrics.drawerInset)
        .padding(.top, OneDayMetrics.spacingS)
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
            // OpenBot 样式采纳包（2026-11-20）：选中垫
            // 改整行贴边填充（口径同频道行注）
            .padding(.horizontal, OneDayMetrics.drawerInset)
            .background {
                if selected {
                    // 2026-11-21 样板对齐包：选中垫改全
                    // 圆角 Capsule（口径见频道行注）
                    Palette.drawerSelectionFill
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(title)
        // 0.43.0（A11Y-V5）：选中态只靠浅灰垫——补
        // 已选特征，与频道行同式
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// 发丝线（左右留 drawerInset 20）：组间分隔的唯
    /// 一形态（立宪：分组＝灰标签＋发丝线，分隔几何
    /// 全名单只此一种，宪法 §3）
    /// 0.41.0（收口批 P3）：实现收编 GroupDivider 本
    /// 体——旧自绘 Rectangle 高 1pt 是全 App 最后一处
    /// 分隔线私实现；改走 GroupDivider（物理发丝
    /// 1/displayScale），双侧 inset 以 trailingInset
    /// 显式传同值保抽屉段内线几何
    /// 2026-11-21 样板对齐包：线色 separator→drawer-
    /// Hairline（#E3E3E3 样板原值）——separator 的加
    /// 强档是材质面板时代「线不可见」（用户 05:34 点
    /// 题）的对策，§318 面板改实色后前提已变、样板
    /// 本体即此淡色且可辨，理由与数值见 drawer-
    /// Hairline 令牌注；几何（20 线、物理发丝）不动
    private var drawerDivider: some View {
        GroupDivider(
            inset: OneDayMetrics.drawerInset,
            trailingInset: OneDayMetrics.drawerInset,
            color: Palette.drawerHairline
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
        // 0.3.8 第 23 条：三件紧凑成组、件间距 8
        // 2026-11-21 样板对齐包：横边距 12→20 回样板
        // 线——面板宽随 travel 0.79 涨到约 317.6 后，
        // 边距 20＋钮 45＋间距 8 的算式恰使搜索胶囊
        // 宽 171.6（样板实测约 172）、两钮中心 42.5/
        // 275.1（样板 41.8/275），三数同归一线；行盒
        // 高走 Core DrawerGeometry.bottomBarRowHeight
        // 52、控件 45 居中（落位口径见该令牌注）
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
                appState.router.settingsSheetRequested = true
            }
            HStack(spacing: OneDayMetrics.spacingS) {
                // 2026-11-21 样板对齐包：放大镜字形删
                // ——样板搜索胶囊内实测无图标（胶囊左
                // 内区像素复测无字形墨迹、占位字距胶
                // 囊左缘 17.4pt 即文字本体），只换皮
                // 不换机制：过滤逻辑/清除钮一字不动
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
                            // 变、命中域外扩 44（胶囊高 45
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
            // 内距 12→16：占位字左缘距胶囊左 16（样
            // 板实测 17.4、Δ1.4），与去放大镜同批
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(height: OneDayMetrics.drawerBarButton)
            // 2026-11-21 样板对齐包：材质玻璃→实色白
            // 卡＋发丝描边＋柔影（样板三件实测：填充
            // #FFFFFF、描边约 #E2E2E6 0.5–1pt、柔影
            // y 约 3/blur 约 10/黑约 7%）。§162 的裸玻
            // 璃口径（描边/柔影是第二三重分离机制）就
            // 此只对本底条让位——样板本体即白卡形态、
            // 用户当日亲令学全；发送舱/身份胶囊的裸
            // 玻璃口径不动。落法：填充走 Palette.
            // surface（浅 #FFFFFF／暗 #1C1C1E 角色等
            // 值）、描边走 hairline（浅 #EEEEF0 对样
            // 板 Δ约 8 级、暗 opaqueSeparator）、柔影
            // shadowBase 8%/半径 10/y 3
            .background {
                Capsule().fill(Palette.surface)
            }
            .overlay {
                Capsule().stroke(Palette.hairline, lineWidth: 1)
            }
            .shadow(
                color: Palette.shadowBase.opacity(0.08),
                radius: 10, x: 0, y: 3
            )
            drawerRoundButton(
                systemName: "square.and.pencil",
                label: "新建会话"
            ) {
                // 台账 147：延迟导航待办在位时整下忽
                // 略（不建新线程、不重复跳页）
                if !appState.router.hasPendingDrawerNavigation {
                    createThread()
                    onClose()
                }
            }
        }
        .frame(height: DrawerGeometry.bottomBarRowHeight)
        .padding(.horizontal, OneDayMetrics.drawerInset)
        .padding(.top, OneDayMetrics.spacingSM)
        .padding(.bottom, OneDayMetrics.spacingXS)
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
                // 2026-11-21 样板对齐包：与搜索胶囊同
                // 改实色白卡＋发丝描边＋柔影（口径见
                // 胶囊处注，§162 裸玻璃只对本底条让位）
                .background {
                    Circle().fill(Palette.surface)
                }
                .overlay {
                    Circle().stroke(Palette.hairline, lineWidth: 1)
                }
                .shadow(
                    color: Palette.shadowBase.opacity(0.08),
                    radius: 10, x: 0, y: 3
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
        // 台账 147：新建同走延迟导航置位口（关到近
        // 闭合才切过去）
        appState.router.stageDrawerThreadSelection(thread.id)
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
