import OneDayCore
import OneDayDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 底部四格（0.6.0 五格 IA 起，聊天／活动／点子／目标
/// ／应用；**0.17.0 真机五修⑤改四格**：活动格撤销——
/// 枢纽（AgentHubView .activity 四段）改由聊天页身份
/// 胶囊点开 sheet 呈现（用户 2026-11-09 19:51 点名），
/// 总览/文件/设置仍收进应用格内页面）。
/// 底栏沿革：0.2.4 回归原生 TabView → 0.3.1 换 Tab(value:)
/// ＋Label 直渲 → 0.3.8 按当时裁决隐藏原生栏、叠自绘
/// FloatingTabBar → **0.4.0 拆自绘、回原生（审计 §3.2）**：
/// 自绘前提「原生选中垫宽约 98pt 改不了」已被 Muse 本体
/// 截图证伪（它用的就是 iOS 26 原生玻璃坞）；呈现全交
/// 系统——Liquid Glass 坞、选中态、滚动最小化、键盘联
/// 动都是系统行为（WWDC25-323）。符号源仍是 OneDayCore
/// .TabBarSymbols（原生 Tab 的 Label 直接取用，§1.2
/// #28 数据保留）；Label 标题随栏进系统排布（0.3.1 礼
/// 记同款口径）。0.4.1 底栏向 Muse 本体靠：①根 .tint
/// 由系统默认蓝改 .primary 单色（去蓝）；②开 .tabBar-
/// MinimizeBehavior(.onScrollDown) 滚动收起；③图标变体
/// 锁 0.4.3 改挂 TabView 根环境（§28.9）；**0.4.5 换路
/// 线：符号本体换线条画法符号＋墨迹密度量测把关，变
/// 体锁只作第二道防线（§30）**。
/// 深链口径：AgentRoute / SettingsRoute 落点仍是设置格；
/// 服务端会话续聊（§3.4）经 pendingChatSessionID 切聊天格。
///
/// 抽屉壳层（0.4.5，§30；取代 0.1.3–0.4.4 的覆盖式）：
/// 用户 2026-11-09 11:37 发 Muse 本体录屏点名「侧边栏
/// 是推不是盖」——抽屉承载自此在本根：底层是抽屉面
/// （DrawerView），上层是整个应用表面（TabView）做成一
/// 张可变换页卡，单一进度驱动四件事：位移（推开量＝屏
/// 宽 79%、录屏逐帧量测）、缩放（→0.96、顶锚：顶部地
/// 标纵向不动、卡底升到屏高约 96%）、四角圆角（→28pt）、
/// 左缘柔影；抽屉面与页卡刚性联动（偏移恒差一个推开
/// 量——录屏地标拟合：抽屉内容与页卡同速同距、无视差）。
/// 0.4.1 第 8 修「开抽屉藏底栏」撤销：底栏坞是页卡的
/// 一部分、随卡同走，不再隐藏（toolbarVisibility 绑定
/// 随 ChatView 覆盖层一并拆除）。手势：左缘热区右滑
/// 开、开态拖页卡/抽屉面跟手关、点露出窄条关，松手按
/// 预测位移吸附；动画走条 9 定版 dragSpring（与录屏
/// 约 0.35s 级减速吸附同档）。开抽屉必先收键盘。
///
/// 抽屉选型结论（0.6.1，用户令原生优先复核）：系统无
/// 等价物，保留自研推式——NavigationSplitView 在
/// iPhone 紧凑宽下塌缩为导航栈推送（侧栏变成一页被
/// push 进栈），不是「底层名单＋表面页卡同速推出」的
/// 抽屉形态；TabView 的 .tabViewStyle(.sidebarAdapt-
/// able) 只在 iPad/大屏把底栏变侧栏、iPhone 上仍是底
/// 栏、不产抽屉。Muse 式 peek 推抽屉在 iPhone 上无系
/// 统原语可平替（例外 E3 既有裁定），故按「修净缺陷
/// 不换容器」办：底层按需挂载（本文件 body）、抽屉
/// 两端改实色固定条（DrawerView 0.6.1）、三页底部自
/// 绘绘制层全拆（ChatView/DrawerView 0.6.1）
///
/// **0.7.1 壳层重构（chrome 裁决全案，档 chrome-**
/// **research-20261109.md §3.3/§3.5，用户 16:15 批**
/// **准）**：壳层状态与变换整体下沉到本文件下方的
/// DrawerShell 包装层，要点四条——①TabView 不再被
/// GeometryReader 包裹（0.6.1 量测坐实其扰动安全区
/// 传递、底栏贴底，§1.4）：推开量改由壳层在卡层以
/// 外以 onGeometryChange 量测，TabView 回归正常安
/// 全区链；②位移改单一事实源 drawerOffset（S1，
/// bool＋delta 双状态退役，纯逻辑在 OneDayCore.
/// DrawerMotion 并有单测）；③挂载改预挂载/迟卸载
/// （S5，取代 0.6.1 的按需挂载——其起步帧建树卡顿
/// 与关抽屉瞬间名单整幅消失见 §1.5-4）；④归位弹簧
/// 换 MotionTokens.drawerSpring（S7），手势按 S2
/// 方向锁定＋S6 吸附判定执行。本层只剩选格状态、
/// 总览桥轮询与跨格深链对账。
///
/// **0.17.0 壳层再换代（真机五修①，用户 2026-11-09**
/// **19:51 点名「底部导航栏下面被盖住一点」，修法以**
/// **全网调研 ios26-tabbar-topbar-issues 报告 Q1/Q4**
/// **为准绳）**：推式页卡**退役**——TabView 被页卡变
/// 换（顶锚 scale＋offset）整体承载正是底栏下沉、标
/// 签压进 home indicator 区、坞下沿出画的病根（0.6.1
/// 已坐实「外层包裹扰动 TabView 安全区」、当时只拆了
/// GeometryReader 一层）。新结构：TabView 回归**根级
/// 安放、零变换零偏移**（壳层不给它加任何 modifier），
/// 抽屉改**覆盖形态**（调研结构 A）：抽屉面＋整屏蒙
/// 层自左滑入盖在静止的内容之上，分离感由蒙层
/// （DrawerMotion.scrimOpacity）承担；推式视觉让位于
/// 底栏落位正确（简报取舍口径：底栏落位＋抽屉可用优
/// 先）。位移三件（S1 单一事实源/S2 方向锁定跟手/S6
/// 吸附）、S5 预挂载迟卸载、S7 弹簧桥接全部保留、只
/// 换承载关系。附带：.tabBarMinimizeBehavior 由
/// .onScrollDown 改 .never（0.4.1 为学 Muse 加的收起
/// 行为、用户已下令去掉；调研 Q2 证实最小化只剩单图
/// 标胶囊是该行为的设计结果、非 bug）。
///
/// **0.19.0 抽屉重构（真机五条·二轮，用户 2026-11-09**
/// **22:26 点名＋22:45 纠正）**：抽屉照 Muse 本体侧
/// 边栏重构（名字头＋「选项卡」导航行组＋管理行＋
/// 「旁聊」区只列本人在 App 里开的旁聊，详见
/// DrawerView 文件头）；本层随之退役的只有壳层的窗
/// 口底 inset 量测与 DrawerView 的 bottomSafeInset
/// 入参（底条拆双计改 safeAreaBar 系统定位＋固定小
/// 间距，定因见 DrawerView 底条注）。
struct ContentView: View {
    /// 底栏格（0.17.0 起四格：活动格已撤销、枢纽走聊
    /// 天页胶囊 sheet，见文件头 0.17.0 注）
    enum MainTab: Hashable {
        case chat
        /// 0.35.0（P3，拍板 1A）：动态格进第二格——
        /// 段一汇编＋段二晨报双生产者已上线才开此格
        /// （设计档 C1 前置：内容先行、空栏不开）
        case feed
        case ideas
        case goals
        /// 0.20.0 第七条：第四格由「应用」换「文件」
        /// （交付物库，DeliverablesView）；原应用格的
        /// 总览/电脑/服务器文件/设置全部迁设置（见
        /// SettingsView「管理」组与根级设置 sheet）
        case files
    }

    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: MainTab = .chat
    /// 总览桥状态（0.6.0）：壳层持有，聊天页顶栏与枢纽
    /// sheet 共同消费；前台 30 秒轮询由下方 scenePhase 驱动
    @State private var overviewStore = OverviewBridgeStore()
    /// 动态未读数（0.38.0）：壳层持有、动态格角标消
    /// 费；只认桥 /feed/generation 的 unread。APNs 到
    /// 位前这就是「有新动态」的唯一提醒形态——呈现
    /// 与文案都不冒充系统推送
    @State private var feedUnread = 0
    private let feedBadgeClient = OneDayBridgeClient()
    /// 「全部对话」管理页呈现（0.18.0，A.3）：抽屉「管
    /// 理全部对话」行置位，全屏页自带导航栈呈现
    @State private var showAllConversations = false
    /// Hermes 频道页呈现（0.36.29，频道规格 §4.1）：
    /// 抽屉频道行置位，全屏页承载与管理页同通道（本
    /// 层 fullScreenCover）；管理页频道段的同名行走
    /// 管理页内部呈现，目的地是同一个 HermesChannel-
    /// View，不许两套频道页
    @State private var showHermesChannel = false
    /// 设置 sheet 呈现（0.20.0 第六条）：抽屉齿轮经
    /// AppState.settingsSheetRequested 置位、本层消费
    /// 呈现；设置页本体内带大标题＋圆 X 头（照 Muse
    /// 设置页图形态）
    @State private var showSettings = false

    var body: some View {
        DrawerShell(
            selection: $selection,
            onManageAll: { showAllConversations = true },
            onOpenChannel: { showHermesChannel = true }
        ) {
            tabView
        }
        // 0.36.0（无障碍 A11Y-S3）：粗体文字映射全
        // App 只挂根视图这一处
        .boldTextMapping()
        .fullScreenCover(isPresented: $showAllConversations) {
            AllConversationsView(
                onOpenSession: { id in
                    // 打开会话：关页＋切聊天格＋走既有续
                    // 聊通道（ChatView 消费导入）
                    showAllConversations = false
                    selection = .chat
                    appState.pendingChatSessionID = id
                },
                onClose: { showAllConversations = false }
            )
        }
        // 0.36.29：Hermes 频道页（抽屉频道行入口）；
        // 页内打开会话与管理页同走法（关页＋切聊天格
        // ＋续聊通道，频道标记由频道页点行时已置位）
        .fullScreenCover(isPresented: $showHermesChannel) {
            HermesChannelView(
                onOpenSession: { id in
                    showHermesChannel = false
                    selection = .chat
                    appState.pendingChatSessionID = id
                },
                onClose: { showHermesChannel = false }
            )
        }
        // 0.4.5：抽屉里点选/新建线程 → 落到聊天格
        // （ChatView 侧消费切换；含从其他格开抽屉的情形）
        .onChange(of: appState.drawerThreadSelection) { _, id in
            if id != nil { selection = .chat }
        }
        // 0.4.0（§3.4）：任一入口置位待续聊会话 → 切聊天格
        // （ChatView 侧消费导入；已在聊天格时 onChange 同样
        // 触发、由 ChatView 直接消费）
        .onChange(of: appState.pendingChatSessionID) { _, id in
            if id != nil { selection = .chat }
        }
        // 0.20.0：抽屉齿轮置位设置请求 → 呈现根级设置
        // sheet（0.6.0 的 pendingAppsPage 切格落位通道
        // 随应用格退役删除）
        .onChange(of: appState.settingsSheetRequested) { _, requested in
            if requested {
                appState.settingsSheetRequested = false
                showSettings = true
            }
        }
        // 0.29.0：设置内页面置位的切格请求（连接器目
        // 录本机服务详情的「目标/点子」入口）→关设置
        // 并切到目标格，消费后清零
        .onChange(of: appState.mainTabSwitchRequest) { _, tab in
            if let tab {
                appState.mainTabSwitchRequest = nil
                showSettings = false
                selection = tab
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                onClose: { showSettings = false },
                onRequestChat: {
                    showSettings = false
                    selection = .chat
                }
            )
        }
        // 0.6.0：总览桥前台轮询（30 秒一轮，OverviewBridge-
        // Store.poll）：以 scenePhase 为 task id——回前台
        // 自动重启、退后台系统自动取消，不学 OpenMuse
        // 的 3 秒轮询
        .task(id: scenePhase) {
            if scenePhase == .active {
                await overviewStore.poll(appState: appState)
            }
        }
        // 0.38.0：动态未读角标轮询——与总览轮询同节奏
        // （前台 30 秒一轮、scenePhase 驱动起停）；未
        // 连接/拉不到时保持上次数字、不清零造假象
        .task(id: scenePhase) {
            if scenePhase == .active {
                await pollFeedUnread()
            }
        }
        // 0.36.20（§86.2）：业务成功信号一到即把在线判
        // 定清零回写——不等 30 秒轮询，胶囊与事实同拍
        .onChange(of: appState.hermesBusinessSuccessTick) {
            overviewStore.noteBusinessSuccess()
        }
        // 0.36.20（§86.4）：网络路径恢复/切换即刻重探
        // 一轮（触发器语义：只催办、不下结论）
        .onChange(of: appState.networkPathEpoch) {
            Task { await overviewStore.refresh(appState: appState) }
        }
    }

    /// 动态未读轮询（0.38.0）：30 秒一轮，只在拿到桥
    /// 的账面时更新数字；失败保持旧值（角标宁可慢半
    /// 拍，不许忽有忽无）
    private func pollFeedUnread() async {
        while !Task.isCancelled {
            if let config = appState.config,
               let generation = try? await feedBadgeClient
                .feedGeneration(config: config) {
                feedUnread = generation.unread
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private var tabView: some View {
        TabView(selection: $selection) {
            // 0.32.0（2A/案甲＋）：.tint(.primary) 从 TabView
            // 根收进各格内容根——底栏条目由宿主以 TabView
            // 本层环境构建（0.4.3 变体锁同理），根 tint 会
            // 把选中段玻璃垫按 .primary 派生成深灰黑（与
            // Muse 同位置的系统默认中性浅灰垫反明度，设
            // 计档横切 B 判因）。内容根各自保留 .primary：
            // 内容区链接/控件强调色与 0.4.1 定案一字不变，
            // 只是深 tint 不再到达栏件；栏件回系统默认
            // 中性着色。设置 sheet/全部对话/抽屉都在
            // TabView 之外、本就不吃这行 tint，不受影响
            // 0.33.1 口径更新：栏件无 tint 的副作用是选
            // 中字形回落系统蓝（用户 16:10 点名）——tint
            // 已改挂 TabView 本层只达栏件（见 tabView 修
            // 饰链 0.33.1 注）；本注「垫按 .primary 派生
            // 成深灰黑」的判因同步更正（垫为中性玻璃透
            // 镜、字形才吃 tint，0.33.0 默认蓝 tint 下垫
            // 仍浅灰为证）
            Tab(value: MainTab.chat) {
                ChatView(overviewStore: overviewStore)
                    .tint(.primary)
            } label: {
                tabLabel(TabBarSymbols.chat)
            }

            // 0.35.0：动态格与四格同走 tabLabel 路径
            // （0.34.0 的 symbolVariants 主锁挂在
            // tabLabel 本体，新格自动同锁；符号名单在
            // TabBarSymbols.all 与单测一并钉死）
            Tab(value: MainTab.feed) {
                FeedView()
                    .tint(.primary)
            } label: {
                tabLabel(TabBarSymbols.feed)
            }
            .badge(feedUnread)

            Tab(value: MainTab.ideas) {
                IdeasView()
                    .tint(.primary)
            } label: {
                tabLabel(TabBarSymbols.ideas)
            }

            Tab(value: MainTab.goals) {
                GoalsView()
                    .tint(.primary)
            } label: {
                tabLabel(TabBarSymbols.goals)
            }

            Tab(value: MainTab.files) {
                DeliverablesView()
                    .tint(.primary)
            } label: {
                tabLabel(TabBarSymbols.files)
            }
        }
        // 0.4.0（审计 §1.1）：根 .tint(Palette.ink) 与暗色
        // 字重降档 hack 一并删除——tint 回系统默认（强调
        // 色由系统/用户系统设置决定），字重不再做环境级
        // 覆写（正文字重回归语义样式自带，批次 4 收口）
        // 0.4.1（用户点名）：tint 改系统主色单色 .primary
        // （去蓝，见文件头 0.4.1 注）；0.32.0 起作用域
        // 收窄到各格内容根（见上方 Tab 内注），本层不再
        // 挂根 tint
        // 0.33.1（用户 16:10 真机截图点名）：tint 改挂
        // TabView 本层——0.32.0 收窄后栏件失去 tint 来
        // 源、回落系统默认强调蓝（选中字形呈系统蓝、与
        // Muse 深色字形不符）。本层 tint 只达栏件宿主
        // 构建处（内容根各自 .tint(.primary) 同值覆盖、
        // 内容区观感一字不变；设置/抽屉在本层之外不受
        // 影响）。选中垫不随 tint 变色：0.33.0 在默认蓝
        // tint 下真机垫已是中性浅灰——垫是玻璃透镜本
        // 体、字形才吃 tint（与 0.32.0 注里「垫按
        // .primary 派生」的旧判因就此更正：当年的深是
        // 字形＋标签同染的整体观感）。终审以 JJ 并排
        // 为准（垫明度/字形色逐项对 Muse）
        .tint(.primary)
        // 0.17.0（真机五修①附带，用户下令去掉）：滚动
        // 收起退役——0.4.1 为学 Muse 本体加的 .onScroll-
        // Down 最小化（commit 95ab47e）会把底栏缩成左下
        // 角一颗单图标胶囊（调研报告 Q2：该行为的设计
        // 结果、非渲染错误），改 .never 写死、底栏恒在
        .tabBarMinimizeBehavior(.never)
        // 0.4.3（§28.9，用户 11:22 点名）：变体锁改挂
        // 本层——TabView 宿主以**本层环境**构建底栏条
        // 目，0.4.1 把 .symbolVariant(.none) 挂在 Label
        // 字形子树里、宿主构建条目时根本读不到，选中
        // 态仍被系统换成 .fill 变体（11:10 真机截图实
        // 证）。根环境注入 .none 后全格全状态不变体；
        // tabLabel 内的 .symbolVariant(.none) 保留作第
        // 二道锁（单独无效、叠加无冲突）。0.4.5 起符号
        // 本体已换线条画法、本锁降为第二道防线（§30）
        // 0.34.0 更正：本层（TabView 外层）环境在
        // 0.33.1 真机仍判不够——用户 16:32 图证四格全
        // 实心含未选中态；按论坛调研，正解主锁改挂
        // tabLabel 本体（见 tabLabel 内 0.34.0 注），
        // 本行保留不动以保真机判读归因
        .environment(\.symbolVariants, .none)
    }

    /// 底栏标签（0.4.1）：标题随 Label 进栏（原生形态），
    /// 字形锁 outline——.symbolVariant(.none) 禁系统在
    /// 选中态自动替换 .fill 变体（符号表本身 selected≡
    /// normal 是第一道锁、此处是呈现侧第二道锁）
    /// 0.4.3 纠正（§28.9）：第二道锁单独**无效**——底
    /// 栏条目由 TabView 宿主以根环境构建、本子树的环
    /// 境到不了构建处；有效锁在 tabView 的 TabView 根
    /// .environment(\.symbolVariants, .none)，此处保留
    /// 仅作叠加
    /// 0.22.0（用户亲点对标 Muse，视觉审计 T1）：纯图
    /// 标化——Label 走系统 .labelStyle(.iconOnly)（公开
    /// LabelStyle、非自绘借道）：标题文字退出视觉呈现
    /// 但仍留在标签里，VoiceOver 读题不靠它也另有下方
    /// accessibilityLabel 显式钉死四格名，无障碍名实
    /// 不丢。知情登记：HIG tab-bars 推荐带标签，本项是
    /// 用户以 Muse 为参照的知情产品选择（审计 T1 原
    /// 文）；选中段深浅由系统按 tint（.primary 定案）
    /// 派生、无官方单独调浅开关——去标签后段内只剩字
    /// 形，观感随之变浅，tint 不改灰（改灰会连字形一
    /// 起变灰、与 Muse 黑细字形反向）
    /// 0.32.0 口径更新（2A/案甲＋，用户逐条拍板）：上
    /// 句「.primary 定案」作废——根 tint 已收窄至各格
    /// 内容根、栏件回系统默认中性着色（见 tabView 内
    /// 0.32.0 注）；「tint 不改灰」的理由仍成立，故采
    /// 收窄作用域而非改色
    private func tabLabel(_ pair: TabSymbolPair) -> some View {
        Label {
            Text(pair.title)
        } icon: {
            Image(systemName: pair.normal)
                .symbolVariant(.none)
                // 0.33.1：渲染模式钉 monochrome（系统栏件
                // 惯例）——单色模板渲染，杜绝 hierarchical/
                // palette 派生让字形发实发花的余地；符号名
                // 全表本就是 outline 原名（TabBarSymbols-
                // Tests 钉死禁 .fill、两态同名），选中态的
                // 填充观感来自宿主对栏件的自动 .fill 变体
                // 派生，变体锁（本处＋根环境）双锁保留
                .symbolRenderingMode(.monochrome)
                // 0.22.0 字形定版（审计 T1 复量）：符号
                // 不换、字重 regular→light 一档——探针实
                // 测（24pt 紧致密度）：message .270→.222、
                // lightbulb .340→.288、checklist .296→
                // .272、tray .383→.329；候选 checkmark
                // .square（.404）比现行 checklist 更浓、
                // 否决（§49）。字体直接钉在图上随图进宿
                // 主构建（与 0.4.3 的子树环境到不了构建
                // 处是两回事）；底栏呈现终由系统介导，
                // 落档以真机终审 V3 并排为准
                .font(.system(size: 24, weight: .light))
        }
        .labelStyle(.iconOnly)
        // 0.34.0（底栏填充正解，论坛调研 tabbar-fill-
        // forum-research-20261110.md）：WWDC24 session
        // 10147 官方机制——标签栏宿主对 symbol image
        // 统一自动选 fill 变体、与选中态无关；
        // .symbolVariant(.none) 是累积语义、清不掉宿
        // 主注入的 fill（先前两道锁打错靶子的根因）。
        // 唯一清除法是给 symbolVariants 环境**赋值**
        // .none，且必须罩住标签渲染点：生产库 call-
        // stack/react-native-bottom-tabs 的 noneSymbol-
        // Variant() 正是挂在 TabItem（label 视图）上、
        // 不在 TabView 本体修饰链里。OneDay 此前只试
        // 过 label 内累积修饰与 TabView 外层环境（后者
        // 0.33.1 真机 16:32 图证仍全格实心、判够不着
        // 渲染点）；本版把赋值环境改挂 label 本体为
        // 主锁。TabView 外层环境与 label 内 .symbol-
        // Variant 保留不动（无冲突，且保真机判读归
        // 因：若本版回描边、功劳只可能来自本处新增）。
        // CI 侧无法证伪/证实此项，终审仍以 JJ 真机逐
        // 格对 Muse 为准；本版判死则转备选 B（四字
        // 形导出模板图资产、脱离 symbol 身份）
        .environment(\.symbolVariants, .none)
        .accessibilityLabel(pair.title)
    }
}

/// 抽屉壳层包装（0.7.1 立、0.17.0 改覆盖形态）：
/// 全部抽屉状态只活在本层——位移状态不落在
/// ContentView 根，拖动期 ContentView/TabView 子树
/// 不因位移写入被牵动重算（S2「状态只落在壳层」）；
/// 内容（TabView）经闭包注入、身份不变。
/// 0.17.0 承载换代（定案见文件头 0.17.0 注）：本层
/// 自下而上＝TabView 本体（**根级安放、本层不给它
/// 加任何 modifier**，底栏落位全交系统）／露出区
/// 蒙层（开态命中＋跟手关，alpha 走 DrawerMotion
/// .scrimOpacity；0.36.4 起只罩抽屉外露出区、防
/// 抽屉材质采样到压暗画面，见中层注）／抽屉面
/// （自左滑入、offset 恒为
/// drawerOffset − travel，右缘柔影随 progress 变）；
/// 合态另有左缘热区一条（跟手开＋S5 预挂载旁听）。
/// 0.7.1 的可变换页卡（S3 白名单四件：页卡 offset、
/// 顶锚 scale、圆角裁切、页卡阴影）**整套退役**——
/// 它们承载 TabView 本人正是底栏下沉的病根；兜底
/// 画布层随页卡一并退役（内容静止、橡皮筋越界时抽
/// 屉下方就是内容本体，不再需要垫色）。
private struct DrawerShell<Content: View>: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: ContentView.MainTab
    /// 抽屉「管理全部对话」透传（0.18.0）
    var onManageAll: () -> Void
    /// 抽屉频道行透传（0.36.29）：一期只有 Hermes
    /// 一个频道，壳层不辨频道 id、宿主恒呈现 Hermes
    /// 频道页；外部频道落地时按 id 分发
    var onOpenChannel: () -> Void
    @ViewBuilder var content: () -> Content

    /// S1 单一事实源：抽屉呈现位移（0＝合拢、travel
    /// ＝全开；跟手期写入的是已含橡皮筋换算的呈现值，
    /// progress/抽屉位移/蒙层/开合语义全部由它派生；
    /// 0.17.0 前它驱动的是页卡变换，承载换代后只驱动
    /// 抽屉本体与蒙层，TabView 不再读它）
    @State private var drawerOffset: CGFloat = 0
    /// 推开量（录屏量测：全开抽屉右缘在屏宽 79%，
    /// §30 量测表；上限 400 防大屏抽屉过宽）：壳层在
    /// 本体上以 onGeometryChange 量测——0.7.1 §3.3
    /// 结构修复：TabView 不再被 GeometryReader 包
    /// 裹，回归正常安全区传递链（贴底病处方 §1.4）。
    /// （0.19.0 退役同处量测的窗口底 inset：它只喂
    /// DrawerView 底条的 0.4.5 手算下边距，底条拆双
    /// 计后无人消费，量测与入参一并撤）
    @State private var travel: CGFloat = 0
    /// S5 挂载态：预挂载（左缘热区触摸按下/语义打开
    /// 信号到达即挂载）＋迟卸载（归位动画结束且
    /// offset＝0 持续 150ms 后才卸）——关闭静止零绘
    /// 制的目标不变（0.6.1 按需挂载的初衷），只是挂
    /// 载点提前、卸载点推迟，换掉起步帧建树卡顿与关
    /// 抽屉瞬间整幅消失（§1.5-4；0.19.0 前此注作
    /// 「名单预取/名单整幅消失」，名单退役后口径同
    /// 步，机制不变）
    @State private var drawerMounted = false
    /// 本次手势会话：首次 onChanged 建立（记接管起
    /// 点与是否桥接）；方向锁定达成前 lockTranslation
    /// 为 nil、手势不写任何位移
    @State private var dragSession: DragSession?
    /// 归位动画在飞标记（setDrawer 置位、其 comple-
    /// tion 按代次清）；归位中再抓的手势走 bridged
    /// 桥接（见 drawerDragGesture 注）
    @State private var settleInFlight = false
    @State private var settleGeneration = 0
    /// 迟卸载代次：任何挂载/开合/新检查递增，过期
    /// 检查自废（防误卸刚重开的抽屉）
    @State private var mountGeneration = 0

    private struct DragSession {
        /// 接管瞬间位移（跟手换算与吸附判定的锚）
        var startOffset: CGFloat
        /// 接管瞬间的手势横向位移（锁定段，跟手写入
        /// 时扣除）；nil＝尚未锁定
        var lockTranslation: CGFloat?
        /// 接管时归位动画在飞：写入改走 drawerSpring
        /// 逐帧重定向（弹簧自当前呈现位接管并合并速
        /// 度，WWDC23 口径），不出现速度清零帧（S7）
        var bridged: Bool
    }

    /// S1 派生开合语义（本层内部用：命中层开关与语义
    /// 对账；不参与位移计算）
    private var isDrawerOpen: Bool {
        DrawerMotion.isOpen(offset: drawerOffset, travel: travel)
    }

    var body: some View {
        let progress = DrawerMotion.progress(
            offset: drawerOffset, travel: travel
        )
        return ZStack(alignment: .leading) {
            // 底层：应用表面本体（TabView）——根级安
            // 放，本层不给它加任何 modifier（无 offset/
            // scale/clip/背景），底栏的安全区传递与落
            // 位全交系统（0.17.0 定案，调研 Q1/Q4）
            content()
            // 中层：蒙层（抽屉挂载期间在场）——压暗静
            // 止的内容，alpha 随进度走 scrimOpacity
            // （两端钳制、越界不放大）；开态承接点按关
            // 抽屉与横拖跟手关（旧页卡命中层的职责改道）
            // 0.36.4（用户实拍点名「抽屉颜色反了」）：
            // 蒙层只罩抽屉之外的露出区——整幅左移
            // drawerOffset、左缘恒贴抽屉右缘。根因：
            // 0.36.3 抽屉底是 .thinMaterial，材质的背
            // 景采样取的是合成链里它下方的一切，旧蒙
            // 层整屏铺黑（峰值 0.32）正压在抽屉下方，
            // 材质糊到的就是压暗后的画面——浅档整面
            // 灰雾、selectionFill 灰垫（#F0F1F2）反衬
            // 成刺眼纯白，明暗关系全反。蒙层退出抽屉
            // 覆盖区后，材质采样的是未压暗的内容本
            // 体：浅档明亮近白＋灰垫回位、暗档内容本
            // 深、材质压深不翻亮。命中与手势只落在露
            // 出区（抽屉本体自带手势、无损）
            if drawerMounted {
                Color.black
                    .opacity(DrawerMotion.scrimOpacity(progress: progress))
                    .ignoresSafeArea()
                    .offset(x: drawerOffset)
                    .contentShape(Rectangle())
                    .allowsHitTesting(isDrawerOpen)
                    .onTapGesture { setDrawer(false) }
                    .gesture(drawerDragGesture)
            }
            // 上层：抽屉面（偏移恒比全开位少一个呈现
            // 位移：合拢时整幅退出左缘；橡皮筋越界段
            // 随 drawerOffset 一并呈现）。右缘柔影随
            // progress 变（radius/x 沿 §3.4 定值、x 改
            // 正向——影落在抽屉右缘外侧的内容/蒙层上）
            if drawerMounted {
                DrawerView(
                    width: travel,
                    currentTab: selection,
                    onSelectTab: { selection = $0 },
                    onClose: { setDrawer(false) },
                    onManageAll: onManageAll,
                    onOpenChannel: { _ in onOpenChannel() }
                )
                .offset(x: drawerOffset - travel)
                .shadow(
                    color: Palette.shadowBase.opacity(
                        DrawerMotion.shadowOpacity(progress: progress)
                    ),
                    radius: DrawerMotion.shadowRadius,
                    x: -DrawerMotion.shadowX, y: 0
                )
                .gesture(drawerDragGesture)
            }
            // 合态左缘热区：右滑跟手唤出（宽走 OneDay-
            // Metrics.drawerEdgeZone 令牌，0.2.2 沿革）；
            // 触摸按下即预挂载抽屉（S5，edgePrepare-
            // Gesture），拖动起步帧零建树。常挂、只切
            // 换命中开关——旧页卡热区自此改挂壳层顶层
            // （S3 禁拖动期结构切换的口径沿用）
            Color.clear
                .frame(width: OneDayMetrics.drawerEdgeZone)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .allowsHitTesting(!isDrawerOpen)
                .gesture(drawerDragGesture)
                .simultaneousGesture(edgePrepareGesture)
        }
        // 推开量量测（壳层本体上量，不包裹 TabView、
        // 不扰动其安全区传递，§3.3 口径沿用；同处的底
        // inset 量测已于 0.19.0 随底条手算退役删除）
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { _, size in
            travel = min(size.width * 0.79, 400)
        }
        // 语义开合对账：ChatView 汉堡钮等只写 AppState
        // .drawerPresented，壳层在此执行（setDrawer 内
        // 同步回写同值、派生语义已相等时被本 guard 拦
        // 下、不回环）
        .onChange(of: appState.drawerPresented) { _, presented in
            if presented != isDrawerOpen {
                setDrawer(presented)
            }
        }
    }

    /// 开合统一走 drawerSpring（0.7.1 S7：interactive-
    /// Spring 0.34/0.86、速度交接，取代 dragSpring 的
    /// 抽屉用途；Reduce Motion 时瞬时）。打开必先收
    /// 键盘（纪律＋旧承载同口径：键盘不许跟进抽屉世
    /// 界；聊天页焦点句柄在页内、壳层走系统第一响应
    /// 者通道直收）。语义状态同步回写 AppState
    /// （各处对账读它；0.19.0 前 DrawerView 还据此拉
    /// 名单数据，名单退役后该用途消灭）。
    /// 0.3.2 起抽屉吸附不挂触觉（口径不变）
    private func setDrawer(_ open: Bool) {
        if open {
            resignKeyboard()
            mountDrawer()
        }
        settleInFlight = true
        settleGeneration += 1
        let generation = settleGeneration
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.drawerSpring, reduceMotion: reduceMotion
            ),
            completionCriteria: .logicallyComplete
        ) {
            drawerOffset = open ? travel : 0
        } completion: {
            guard generation == settleGeneration else { return }
            settleInFlight = false
            if !open {
                // S5 迟卸载：归位结束、静止 150ms 后才卸
                scheduleUnmountCheck(after: .milliseconds(150))
            }
        }
        appState.drawerPresented = open
    }

    private func resignKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        #endif
    }

    /// S5 预挂载（0.19.0 前兼触发名单数据预取——Drawer-
    /// View 挂载即 @Query 建树、onAppear 补拉服务端会
    /// 话组；名单退役后本处只剩挂载建树一职，导航树
    /// 很轻、预挂载口径不变）
    private func mountDrawer() {
        mountGeneration += 1
        drawerMounted = true
    }

    /// 左缘热区触摸按下即预挂载（S5）：与主拖拽手势
    /// 并行旁听，第一次活动即挂载——方向锁定达成
    /// （10pt）前抽屉树已建好，起步帧零建树；若最终
    /// 没打开（纵滚/点按），迟卸载检查负责回收
    private var edgePrepareGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !drawerMounted else { return }
                mountDrawer()
                scheduleUnmountCheck(after: .milliseconds(600))
            }
    }

    /// 迟卸载检查：到期时仍合拢静止、无手势会话、语
    /// 义未打开才真正卸载；代次不符（其间有过新的挂
    /// 载/开合/检查）自废
    private func scheduleUnmountCheck(after delay: Duration) {
        mountGeneration += 1
        let generation = mountGeneration
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard generation == mountGeneration,
                  drawerOffset == 0,
                  dragSession == nil,
                  !appState.drawerPresented
            else { return }
            drawerMounted = false
        }
    }

    /// 壳层拖拽（左缘热区/蒙层/抽屉面三处共用，
    /// 0.7.1 按裁决 §3.5 重写）：
    /// - S2 方向锁定：累计 |dx|≥10 且 |dx|≥1.5|dy|
    ///   才接管；接管前不写任何状态（纵滚零干扰），
    ///   接管后写入扣除锁定段（起步无跳，§1.5-5）；
    ///   旧「minimumDistance 6 先认领再事后过滤」退役
    /// - S2 跟手期零动画直接写（bridged 会话除外，
    ///   见下）；越界橡皮筋走 DrawerMotion 换算
    /// - S7 桥接：接管时归位动画在飞（bridged），写
    ///   入改走 drawerSpring 逐帧重定向——弹簧自当
    ///   前呈现位接管并合并速度，不出现速度清零帧；
    ///   普通会话（静止起步）恒直接写、1:1 跟手
    /// - S6 松手：predictedEnd 动量投影相对起点过
    ///   30% travel 吸附，fling >800pt/s 直通，
    ///   判定在 DrawerMotion.settleOpens（单测把守）
    private var drawerDragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragSession == nil {
                    dragSession = DragSession(
                        startOffset: drawerOffset,
                        lockTranslation: nil,
                        bridged: settleInFlight
                    )
                }
                guard var session = dragSession else { return }
                if session.lockTranslation == nil {
                    guard DrawerMotion.isDirectionLocked(
                        dx: value.translation.width,
                        dy: value.translation.height
                    ) else { return }
                    session.lockTranslation = value.translation.width
                    session.startOffset = drawerOffset
                    dragSession = session
                }
                let target = DrawerMotion.followedOffset(
                    startOffset: session.startOffset,
                    translation: value.translation.width,
                    lockTranslation: session.lockTranslation ?? 0,
                    travel: travel
                )
                if session.bridged {
                    withAnimation(
                        MotionTokens.resolved(
                            MotionTokens.drawerSpring,
                            reduceMotion: reduceMotion
                        )
                    ) {
                        drawerOffset = target
                    }
                } else {
                    drawerOffset = target
                }
            }
            .onEnded { value in
                let session = dragSession
                dragSession = nil
                guard let session, session.lockTranslation != nil else {
                    // 未接管就松手（纵滚/点按）：位移从未
                    // 写入；仅回收可能的预挂载
                    if drawerOffset == 0 {
                        scheduleUnmountCheck(after: .milliseconds(150))
                    }
                    return
                }
                settleInFlight = false
                let opens = DrawerMotion.settleOpens(
                    currentOffset: drawerOffset,
                    startOffset: session.startOffset,
                    predictedExtra: value.predictedEndTranslation.width
                        - value.translation.width,
                    velocityX: value.velocity.width,
                    travel: travel
                )
                setDrawer(opens)
            }
    }
}
