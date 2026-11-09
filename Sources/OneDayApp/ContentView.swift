import OneDayCore
import OneDayDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 底部五格（0.6.0 五格 IA，蓝图 §4 一期：聊天／活动／
/// 点子／目标／应用；总览/文件/设置收进应用格内页面）。
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
struct ContentView: View {
    enum MainTab: Hashable {
        case chat
        case activity
        case ideas
        case goals
        case apps
    }

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: MainTab = .chat
    /// 总览桥状态（0.6.0）：壳层持有，聊天页顶栏与活动
    /// 格共同消费；前台 30 秒轮询由下方 scenePhase 驱动
    @State private var overviewStore = OverviewBridgeStore()
    /// 推式抽屉的壳层开合目标与跟手位移（0.4.5）：制式
    /// 与 0.4.4 前 ChatView 内的同名状态一致——跟手量
    /// 是相对当前基准位（开＝推开量／合＝0）的平移，
    /// 基准位由 drawerOpen 定，松手吸附在 setDrawer 收口
    @State private var drawerOpen = false
    @State private var drawerDrag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            // 推开量（录屏量测：全开页卡左缘在屏宽 79%，
            // §30 量测表）；上限 400 防大屏抽屉过宽
            let travel = min(geo.size.width * 0.79, 400)
            let offsetX = cardOffset(travel: travel)
            let progress = travel > 0
                ? min(max(offsetX / travel, 0), 1) : 0
            ZStack(alignment: .leading) {
                // 橡皮筋越界时（拖过两端）露出的兜底色：
                // 与抽屉面同色，正常态恒被页卡盖住
                Palette.chatSurface
                // 底层：抽屉面（偏移恒比页卡少一个推开
                // 量：页卡合拢时它恰好整幅退出左缘）。
                // 0.6.1 按需挂载（用户真机点名活动页底部
                // 左角透出/重影）：旧构造下本层在关闭态也
                // 常驻层级、只靠偏移恰 -travel 藏到左缘
                // 外，是全壳唯一「常驻挂载且带帧外绘制」
                // 的层（其 safeAreaBar 背景与底条钮阴影在
                // 关闭态仍参与离屏合成），是屏底残影的唯
                // 一结构嫌疑。改只在打开或拖拽进行中挂
                // 载：关闭静止时整层移出层级、零绘制；打
                // 开与拖拽中（drawerDrag≠0）保持挂载、
                // 跟手与动画口径不变；打开瞬间的挂载与
                // setDrawer 的动画同帧起步、无自身转场，
                // 不影响 §30 同速同距
                if drawerOpen || drawerDrag != 0 {
                    DrawerView(
                        width: travel,
                        bottomSafeInset: geo.safeAreaInsets.bottom,
                        currentTab: selection,
                        onSelectTab: { selection = $0 },
                        onClose: { setDrawer(false) }
                    )
                    .offset(x: offsetX - travel)
                    .gesture(drawerDragGesture(travel: travel))
                }
                // 上层：整个应用表面＝一张可变换页卡
                card(travel: travel, offsetX: offsetX, progress: progress)
            }
        }
        // 语义开合对账：ChatView 汉堡钮等只写 AppState
        // .drawerPresented，壳层在此执行（setDrawer 内
        // 同步回写同值、值已相等时被本 guard 拦下、不回环）
        .onChange(of: appState.drawerPresented) { _, presented in
            if presented != drawerOpen {
                setDrawer(presented)
            }
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
        // 0.6.0：跨格入口置位待开应用格内页面（抽屉齿轮
        // 等）→ 切应用格（AppsView 侧消费落位）
        .onChange(of: appState.pendingAppsPage) { _, page in
            if page != nil { selection = .apps }
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
    }

    /// 应用表面页卡：TabView 本体＋开态命中层/合态左缘
    /// 热区（都是卡的一部分、随卡同走），变换序＝圆角
    /// 裁切→缩放（顶锚）→位移→柔影（影取最终轮廓：录
    /// 屏里影是卡左缘外侧约 27pt 宽的软带、最深处贴缘、
    /// 向左衰减到无，§30）
    @ViewBuilder
    private func card(
        travel: CGFloat, offsetX: CGFloat, progress: CGFloat
    ) -> some View {
        let shaped = tabView
            // 开态命中层：盖住整卡接管点按（点露出的窄
            // 条关抽屉）与横拖（跟手关）；开态下卡内控
            // 件不可达——页卡只是被推开的预览（样板同理）
            .overlay {
                if drawerOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { setDrawer(false) }
                        .gesture(drawerDragGesture(travel: travel))
                }
            }
            // 合态左缘热区：右滑跟手唤出（宽走 OneDay-
            // Metrics.drawerEdgeZone 令牌，0.2.2 沿革）。
            // 显隐只认 drawerOpen——拖拽进行中（drawer-
            // Drag≠0、drawerOpen 仍为 false）它必须留在
            // 原地，否则手势中途被摘
            .overlay(alignment: .leading) {
                if !drawerOpen {
                    Color.clear
                        .frame(width: OneDayMetrics.drawerEdgeZone)
                        .contentShape(Rectangle())
                        .gesture(drawerDragGesture(travel: travel))
                }
            }
            .clipShape(RoundedRectangle(
                cornerRadius: 28 * progress, style: .continuous
            ))
            // 缩放锚点在顶中：录屏量测全开 0.96、顶部地
            // 标纵向位移≈0、卡底边升到屏高约 96%（§30）
            .scaleEffect(1 - 0.04 * progress, anchor: .top)
            .offset(x: offsetX)
        if progress > 0 {
            shaped.shadow(
                color: Palette.shadowBase.opacity(0.16 * Double(progress)),
                radius: 24 * progress, x: -10 * progress, y: 0
            )
        } else {
            shaped
        }
    }

    private var tabView: some View {
        TabView(selection: $selection) {
            Tab(value: MainTab.chat) {
                ChatView(
                    onOpenActivity: { selection = .activity },
                    overviewStore: overviewStore
                )
            } label: {
                tabLabel(TabBarSymbols.chat)
            }

            Tab(value: MainTab.activity) {
                ActivityView(overviewStore: overviewStore)
            } label: {
                tabLabel(TabBarSymbols.activity)
            }

            Tab(value: MainTab.ideas) {
                IdeasPlaceholderView()
            } label: {
                tabLabel(TabBarSymbols.ideas)
            }

            Tab(value: MainTab.goals) {
                GoalsPlaceholderView()
            } label: {
                tabLabel(TabBarSymbols.goals)
            }

            Tab(value: MainTab.apps) {
                AppsView(onOpenChat: { selection = .chat })
            } label: {
                tabLabel(TabBarSymbols.apps)
            }
        }
        // 0.4.0（审计 §1.1）：根 .tint(Palette.ink) 与暗色
        // 字重降档 hack 一并删除——tint 回系统默认（强调
        // 色由系统/用户系统设置决定），字重不再做环境级
        // 覆写（正文字重回归语义样式自带，批次 4 收口）
        // 0.4.1（用户点名）：tint 改系统主色单色 .primary
        // （去蓝，见文件头 0.4.1 注）；滚动收起走系统
        // tabBarMinimizeBehavior（.onScrollDown）
        .tint(.primary)
        .tabBarMinimizeBehavior(.onScrollDown)
        // 0.4.3（§28.9，用户 11:22 点名）：变体锁改挂
        // 本层——TabView 宿主以**本层环境**构建底栏条
        // 目，0.4.1 把 .symbolVariant(.none) 挂在 Label
        // 字形子树里、宿主构建条目时根本读不到，选中
        // 态仍被系统换成 .fill 变体（11:10 真机截图实
        // 证）。根环境注入 .none 后全格全状态不变体；
        // tabLabel 内的 .symbolVariant(.none) 保留作第
        // 二道锁（单独无效、叠加无冲突）。0.4.5 起符号
        // 本体已换线条画法、本锁降为第二道防线（§30）
        .environment(\.symbolVariants, .none)
    }

    /// 页卡实时位移：基准位（开 travel／合 0）＋跟手量
    /// （界内 1:1 跟手；越界段橡皮筋，OneDayCore.Drawer-
    /// Geometry——与 0.4.4 前 ChatView 的 drawerFollowed-
    /// Drag 同式，宽度参数换成推开量）
    private func cardOffset(travel: CGFloat) -> CGFloat {
        let base = drawerOpen ? travel : 0.0
        let followed: CGFloat
        if drawerOpen {
            followed = drawerDrag >= 0
                ? DrawerGeometry.rubberBand(
                    overshoot: drawerDrag, containerWidth: travel
                  )
                : max(drawerDrag, -travel)
        } else {
            followed = drawerDrag <= 0
                ? -DrawerGeometry.rubberBand(
                    overshoot: -drawerDrag, containerWidth: travel
                  )
                : min(drawerDrag, travel)
        }
        return base + followed
    }

    /// 开合统一走条 9 定版拖拽弹簧（dragSpring：stiffness
    /// 1200 / damping 80、零回弹，0.3.0 §14——抽屉属拖拽
    /// 类交互；与录屏约 0.35s 级减速吸附同档），Reduce
    /// Motion 时瞬时。打开必先收键盘（纪律＋旧承载同口
    /// 径：键盘不许跟进抽屉世界；聊天页焦点句柄在页内、
    /// 壳层走系统第一响应者通道直收）。语义状态同步回
    /// 写 AppState（DrawerView 拉数据与各处对账都读它）。
    /// 0.3.2 起抽屉吸附不挂触觉（口径不变）
    private func setDrawer(_ open: Bool) {
        if open {
            resignKeyboard()
        }
        withAnimation(
            MotionTokens.resolved(MotionTokens.dragSpring, reduceMotion: reduceMotion)
        ) {
            drawerOpen = open
            drawerDrag = 0
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

    /// 壳层拖拽（左缘热区/页卡命中层/抽屉面三处共用）：
    /// 跟手实时位移，松手按预测位移（含速度）决定开合，
    /// 弹簧归位由 setDrawer 承接——阈值口径与 0.4.4 前
    /// 一致（预测位移过推开量三成即吸附到对岸）。横向
    /// 分量必须大于纵向才接管：抽屉名单纵滚、聊天页纵
    /// 滚、各页既有横向交互（长按菜单等不经平移手势）
    /// 都不被本手势抢（仲裁清单见 §30）
    private func drawerDragGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    drawerDrag = value.translation.width
                }
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width
                if drawerOpen {
                    setDrawer(projected > -travel * 0.3)
                } else {
                    setDrawer(projected > travel * 0.3)
                }
            }
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
    private func tabLabel(_ pair: TabSymbolPair) -> some View {
        Label {
            Text(pair.title)
        } icon: {
            Image(systemName: pair.normal)
                .symbolVariant(.none)
        }
    }
}
