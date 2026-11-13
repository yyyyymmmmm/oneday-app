import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit

/// 输入舱引导线托管（§186，用户 2026-11-12 03:02 亲点
/// 「层级内承载＋系统键盘引导线钉底」）：取代消息列表
/// `.safeAreaBar(edge: .bottom)` 承载（0.4.3–§177）。
///
/// ## 为什么换（证据链）
/// - 诊断第三题：键盘升起时 SwiftUI 安全区整栈重排——
///   键盘→坞→舱→内容，坞被顶到舱与键盘之间（约 62pt），
///   无任何一行代码「顶」它，是两条 bar 同住一个安全区
///   体系的涌现结果；系统只给「整栈一起避让」，不给
///   「只避让一条」的开关。
/// - 配件托管（inputAccessoryView）已证伪硬停：两大成熟
///   聊天 SDK（MessageKit 4／Stream）均已弃用，且配件在
///   标签栏下只能盖坞、不能停在坞上方，与「落下回坞上
///   方」定版结构性冲突（composer-accessory-external-
///   check-20261112.md）。
/// - 成熟形态收敛点＝层级内 composer＋键盘驱动
///   （MessageKit 4 的 KeyboardManager／Stream 的
///   messageComposerBottomConstraint 同向）：整栈留在前
///   景层级内，底边改钉 `UIView.keyboardLayoutGuide`。
///
/// ## 接法（小样实证，探针两轮 CI 量测）
/// - 本件是 ChatView 根 ZStack 的一层（全帧提议）：控制
///   器视图是**透传视图**（舱带之外不拦命中，列表点空白
///   收键盘等手势照常落到下层列表）；舱本体（bottomBar
///   整栈）托管在子 UIHostingController 里，底边一条约
///   束钉本视图的 keyboardLayoutGuide.topAnchor，地板
///   钳制在布局回调里按 `min(guideTop, 视图底边)` 逐拍
///   补偿——升起跟引导线（含交互式下滑收键盘的逐帧跟
///   随，引导线本体性质）、落下停在视图底边。
/// - 视图底边即坞顶（探针实证：TabView 把页帧收在坞上
///   方、内嵌控制器视图底＝坞顶；且 SwiftUI **不**给内
///   嵌控制器传 additionalSafeAreaInsets（实测 0），地
///   板不得再减安全区数——第一轮探针多减 83pt 当场证
///   伪、双计教训记 §186）。
/// - 列表底留位改由本件实测回报驱动：舱顶在窗口坐标的
///   实测值换算成「舱顶→窗口底距离」回写 ChatView，
///   列表 `.contentMargins(.bottom)` ＝该值＋spacingS
///   （§176 单点边距 8 不变、记账只剩一处）；列表本体
///   `.ignoresSafeArea(edges: .bottom)` 退掉安全区传播
///   （探针实证：传播的 83pt 双计归零、帧延伸到屏底、
///   留位全由 contentMargins 一处说了算）。窗口坐标结
///   算对页帧在键盘态的伸缩免疫（公式只认窗口真值）。
/// - 坞的键盘态：TabView 的安全区预留不因舱退出而消
///   失，键盘升起时坞仍骑键盘顶、与舱的下段带重叠——
///   「坞被键盘窗自然覆盖」在 SwiftUI TabView 下不成立
///   （诊断 3.1 机制＋真机图 986D2887）。配套动作在
///   ChatView：聚焦态 `.toolbar(.hidden, for: .tabBar)`
///   （诊断 K1）令坞在打字时退出、落下恢复；舱的承载
///   与跟随不依赖此件（坞即便骑上来也只与舱带重叠，
///   不再处于「舱与键盘之间」的栈位）。
///
/// ## 协作面
/// - 抽屉：本件在前景宿主（DrawerContainer 内容宿主）
///   的 SwiftUI 树内，抽屉推开时随前景整体滑动（开抽屉
///   先收键盘是容器既有纪律）；附件 sheet／选图器等自
///   ChatView 呈现，盖在本件之上（同窗呈现链不变，
///   §147/§152 时序零触碰）。
/// - 环境注入照 DrawerContainer 先例：宿主不继承桥的
///   环境——对象类三项（AppState、modelContext、
///   locale）在本桥读出后逐项写进舱宿主根视图，粗体
///   映射同挂；trait 类（深色／字号／减动态）不快照
///   注入（其环境键路无写入口、抽屉桥同例）——经控
///   制器层级的 trait 自动派生进托管树且随系统变化
///   持续同步
/// - 贴底四路（§124/§135/§176）：bottomBar 整栈与回底
///   钮本体一字不动、ScrollViewReader 与列表同树不变，
///   scrollToBottom 仍经原 proxy 直达；变的只有留位来
///   源（安全区→实测 contentMargins），距底读数出自滚
///   动几何、对留位来源无感——四路判定与协调器零改动。
///
/// ## §193 锚定式重构（2026-11-13，用户拍板，覆盖上
/// 文 §186 接法中的钉位部分；诊断 bars-diagnosis-
/// round3-20261113.md）
/// 0.50.24 起真机三栏缺席两轮补丁未愈（§191 size-
/// ThatFits 收口被 149 真机证伪、§192 优先级断链未
/// 及真机验证即被用户叫停）：病根不在某个数，而在
/// 「栏位位置由 SwiftUI 尺寸协商决定」本身——真机
/// 冷启时序下本桥的控制器视图帧被协商污染为
/// (0,-89,402×1030) 后，§186 的地板钳制信任的正是
/// 污染帧内的 keyboardLayoutGuide（读数近视图顶），
/// 舱被钉到屏外上方。本轮按大厂形态收口（苹果官方
/// keyboardLayoutGuide 锚定形态＋Telegram/WhatsApp
/// 手工锚位先例，主线外部核查在案）：
/// - SwiftUI 侧：本桥退出根 ZStack 定尺寸，改挂列
///   表 .overlay 次级层（次级视图不参加父级协商）；
/// - UIKit 侧：宿主底边双锚、且两锚都是**本视图
///   内层级**的约束——键盘升起钉本视图 keyboard-
///   LayoutGuide.topAnchor（升起态下引导线由 UIKit
///   按真实键盘帧算、与本视图帧污染无关；交互式
///   下滑收键盘逐帧跟随）；键盘落下钉自有布局引
///   导线，其 top 常量逐拍由坞本体（窗口层级里找
///   到的 UITabBar 或类名兜底命中）的布局空间实
///   帧换算（忽略 transform、抽屉随动不假补偿）。
///   坞只被读帧、永不被约束直接引用：跨层级直钉
///   坞 topAnchor 的 v1 形态在切格/藏坞的层级手
///   术瞬间会留下悬空约束、求解抛 no-common-
///   ancestor（CI 43337805344 两测试实证），整类
///   退役。键盘通知切换两锚、动画参数与键盘同
///   步；坞参照在入窗/显形/键盘收起时重解析，无
///   坞环境（探针裸装配）回落窗口安全区底。§186
///   地板钳制就此退役——它防的「落下漂移」由坞
///   锚构造性消除。
/// - 宿主顶/左右仍贴本视图：本视图帧即便再被污染，
///   宿主内 VStack 的 Spacer 吸收多余高度，舱恒坐
///   宿主底边＝锚点——「SwiftUI 内部固有尺寸变化不
///   许改变栏位帧」由约束构造保证，不再靠量测。
/// - 抽屉随动不变：宿主在抽屉前景的布局树内、坞锚
///   在窗内同树，抽屉平移走 transform 不进布局帧，
///   舱随前景同移；呈现链（sheet/选图器自 ChatView
///   复合体呈现）零触碰。
///
/// ## §194 键盘半边改单值驱动（2026-11-13，覆盖
/// §193 的键盘锚一半；证据：151 真机录屏＋自述）
/// 151 真机判绿静息几何，但点输入框后键盘升起、舱
/// 留在静息位被键盘盖住：§193 键盘态的约束（底边
/// 钉本视图 keyboardLayoutGuide.topAnchor）在真机
/// 上处于激活态而舱纹丝不动——引导线在本承载
/// （SwiftUI 平台层级内嵌控制器＋双层托管）下不追
/// 踪真键盘（模拟器组装全链绿、真机独红，与本系列
/// 「协商污染」同型；引导线帧不更新另有 FB9733654
/// 系前科，不可再作唯一依据）。通知不背锅：Notifi-
/// cationCenter 投递与层级无关、控制器在屏存活、
/// 键盘保持升起证明文本视图与宿主子树存活——
/// willShow 必达、约束必已切换，坏的只是引导线本
/// 体的追踪。改法按 Telegram/ContainerViewLayout
/// 式收口（键盘的位置是一个自窗口广播的数、一次
/// 算死；大厂三路殊途同归于「位置只有一个主人＝
/// 键盘本身」，主线外部核查在案）：
/// - 约束收成一条且永不切换：宿主底边恒钉自有
///   bottomGuide.topAnchor；bottomGuide 的 top 常
///   量是唯一的位置数，只由 syncBottomConstant
///   一个函数算——§193「双锚＋通知切换激活态」退
///   役，「模式」本身就是病灶的一半；
/// - 常量取值二路、皆为实测真值：键盘升起态＝键
///   盘通知广播的结束帧顶（存窗口坐标、逐布局拍
///   按本视图当前布局空间换算）；静息态＝坞实测
///   顶（§193 判绿路径原样保留）。静息数值与 151
///   判绿几何同值（坞顶 791＝原引导线静息顶
///   791），几何口径不动：pocket 62／宿主帧
///   729／adjBottom 197；
/// - willChangeFrame 同步跟进：交互式下滑收键盘
///   与候选条高度变化逐帧改常量（时长 0 的通知直
///   接布局、不包动画）；状态翻转沿用通知自带时
///   长/曲线推进布局；
/// - 自述留证：kb 探针逐次记事件/键盘顶窗口值/
///   生效常量，kbShow/kbHide 事件采样＋0.9 秒落
///   定采样各一帧——真机验收看数字：舱底应＝
///   kbTopWin；系统 guide= 行同帧对账（预期仍停
///   静息值，即根因本人）。
///
/// ## §195 顶边同式收口（2026-11-13，153 急修；
/// 证据：152 真机自述 bars-geometry-trace-device-
/// 152-20261113）
/// 152 的 [kbShow] 帧舱底＝kbTopWin 分毫不差、跟
/// 随判绿；但 [kbShowSettled] 落定帧顶簇整体上移
/// 49 撞状态栏：pocket 62→13、surface 同移、列表
/// adjTop 122→73。常数链无错（kb 常量仍 483、舱
/// 本人靠窗口坐标自纠、落点终值正确）——坏在顶边
/// 没有这层保护：顶簇挂列表 .safeAreaBar(.top)、
/// surface 顶边由 TabView 页面传播来的安全区决
/// 定，而这份传播值在 `.toolbar(.hidden, for:
/// .tabBar)` 藏坞落定后被重算偷走 49（top 与
/// bottom 各 −49＝标签栏高，minimize 已写死
/// .never、与之无关）。窗口本身的 UIKit 安全区
/// 在自述每一帧恒 (62,0,34,0)——不变量在窗口、
/// 不在传播链。修法（用户 10:42 口径：顶簇结构
/// 性脱钩、不许只在 surface 顶边补常量）：顶簇
/// 本体迁 TopBarGuideHost 锚定托管（落位只认窗
/// 口、与本件无关）；本件只多担一条回报——窗口
/// 顶安全区实测（onTopSafeChange，与 bottom-
/// Space 同一条回报纪律：布局拍读窗口真值、变
/// 化 >0.5 才外发），供 ChatView 在断顶缘传播后
/// 以「此值＋顶簇实高」记账列表顶 contentMar-
/// gins（留位记账、非落位）。
///
/// ## §210 舱带/坞改内容驱动注册（2026-11-13，
/// 用户 21:39 验收口径，取代 §200 两件与 A2 材质）
/// §200 曾垫两件均匀系统磨砂（舱宿主层级内舱带＋
/// UITabBar 本体内坞带）治内容透字；A2（17:02）
/// 又把舱带几何收为卡段（衬顶＝卡帧顶、衬底＝宿
/// 主底，整栈生长不牵衬）。用户 21:39 点名：条下
/// 无内容时须与页面同色不可见、有内容滚过才朦
/// 胧——常驻材质片与内容无关恒定渲染、静止自成
/// 色带（探针实证：舱带静止色差浅 14／深 19、坞
/// 带深 19），§200 材质机制就此退役。改走系统边
/// 缘效果正道注册（ScrollEdgeRegistration）：
/// ①舱带几何（A2 卡段）原样保留、载体换透明注册
/// 容器（EdgeBandContainerView＋底缘 inter-
/// action），效果由系统按内容滚过与否自适应；
/// ②坞带整件删除——UITabBar 是系统条，其自身玻
/// 璃与自动边缘效果即正道（resolveAnchors 不再
/// 往坞里塞任何子视图，坞只读帧的纪律还原）。
/// §194 常量机制与舱落位零改动；不自绘渐变擦淡
/// （§173 红线）、内容全强度活到被系统效果化开
/// 为止。
struct ComposerGuideHost<Content: View>: UIViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    /// 舱顶→窗口底距离的实测回报（host 在布局拍回写；
    /// ChatView 以此＋spacingS 作列表底 contentMargins）
    @Binding var bottomSpace: CGFloat
    /// §195：窗口顶安全区的实测回报（host 在布局拍
    /// 回写 window.safeAreaInsets.top；ChatView 以
    /// 此值＋顶簇实高记账列表顶 contentMargins，
    /// 顶簇落位归 TopBarGuideHost，见文件头 §195）
    @Binding var topSafe: CGFloat
    /// 舱本体（ChatView 的 bottomBar 整栈）：在 init 里
    /// 由构建闭包求值成视图值——求值发生在 ChatView 的
    /// body 构建期，bottomBar 内部的全部状态读数由此归
    /// 因到 ChatView（与换代前「bottomBar 在列表树内构
    /// 建」的追踪语义一致）；新鲜度机制＝ChatView 重渲
    /// →本桥重建→apply 把新值重赋值进舱宿主。两条替代
    /// 路线经宿主测试证伪：闭包在 apply（update 期）求
    /// 值——读数不归因、舱内独有状态陈旧；闭包托管内
    /// 树活根求值——内树不自追踪 @Observable（子视图
    /// body 读数同样不触发重渲），与本仓「托管靠外层
    /// 重赋值刷新」的一贯机制不合
    var content: Content
    /// §210：聊天列表滚动视图句柄（ChatView 同一份
    /// 亦喂顶簇宿主与列表内锚点；控制器据此把舱带
    /// 容器的底缘 interaction 对齐列表本体）
    let scrollHandle: ChatListScrollViewHandle

    init(
        bottomSpace: Binding<CGFloat>,
        topSafe: Binding<CGFloat>,
        scrollHandle: ChatListScrollViewHandle,
        @ViewBuilder content: () -> Content
    ) {
        self._bottomSpace = bottomSpace
        self._topSafe = topSafe
        self.scrollHandle = scrollHandle
        self.content = content()
    }

    func makeUIViewController(
        context: Context
    ) -> ComposerGuideHostController {
        let controller = ComposerGuideHostController()
        let bottomSpace = $bottomSpace
        controller.onBottomSpaceChange = { value in
            // 布局拍内同步写 SwiftUI 状态会撞「视图更新
            // 中改状态」；回报统一走下一拍（首报前 Chat-
            // View 以近似值兜底、量级与现行静止总量同档）
            DispatchQueue.main.async {
                if abs(bottomSpace.wrappedValue - value) > 0.5 {
                    bottomSpace.wrappedValue = value
                }
            }
        }
        let topSafe = $topSafe
        controller.onTopSafeChange = { value in
            // §195：与 bottomSpace 同一条回报纪律（下
            // 一拍写、>0.5 才发）
            DispatchQueue.main.async {
                if abs(topSafe.wrappedValue - value) > 0.5 {
                    topSafe.wrappedValue = value
                }
            }
        }
        apply(to: controller)
        return controller
    }

    func updateUIViewController(
        _ controller: ComposerGuideHostController,
        context: Context
    ) {
        apply(to: controller)
    }

    /// 尺寸协商收口（§191，真机量测定因，诊断全文
    /// bars-fix-diagnosis-20261113）：恒回提议尺寸——
    /// 本桥在 ZStack 里只做全帧提议的透传层，舱的实
    /// 际落位 100% 由控制器内约束（§193 双锚）
    /// 决定，SwiftUI 尺寸协商本就不该有发言权。默认
    /// sizeThatFits 会把控制器视图的当前/拟合尺寸报
    /// 回去：真机冷启布局时序下（真实窗口＋引导线约
    /// 束系未定态）拟合高被污染为约 1030，ZStack 取
    /// 子视图最大值撑高自身、超尺寸子视图在安全区矩
    /// 形内居中安放（62−(1030−729)/2≈−89），列表与
    /// 顶栏随坏帧一并出屏——0.50.24/0.50.25 真机三
    /// 栏缺席的定因链；模拟器装配走已定态几何、拟合
    /// 回提议值本身，故探针全绿而真机独坏。提议未定
    /// 的维度回 nil 走系统默认（ZStack 全帧提议下两
    /// 维恒定，此分支只兜底）
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: ComposerGuideHostController,
        context: Context
    ) -> CGSize? {
        let result: CGSize?
        if let width = proposal.width, width.isFinite,
           let height = proposal.height, height.isFinite {
            result = CGSize(width: width, height: height)
        } else {
            result = nil
        }
        return result
    }

    /// 把当前 SwiftUI 侧状态（环境＋舱本体视图值）刷
    /// 进托管控制器：舱宿主根视图以同型新值重赋值
    /// （SwiftUI 按身份 diff、舱内 @State 不重建，与
    /// DrawerContainer 内容宿主同机制）；舱本体的新
    /// 鲜度由 init 求值的归因链保证（见 content 注），
    /// 本函数只做注入与赋值、不求值任何闭包
    private func apply(to controller: ComposerGuideHostController) {
        let appState = appState
        let modelContext = modelContext
        let locale = locale
        controller.edgeScrollHandle = scrollHandle
        controller.composerRoot = AnyView(
            VStack(spacing: 0) {
                // 宿主全高填充（顶贴页顶、底钉引导线）：
                // 舱在托管树内被 Spacer 顶到宿主底边，
                // 以自身理想高成帧——舱高不经 UIHosting-
                // Controller 的任何 sizing 通道（嵌套托
                // 管下其理想高在换根/生长时不重算、量根
                // 帧又是约束自引用，宿主测试三路证伪；
                // 树内布局是唯一如实通道）。Spacer 与
                // VStack 容器本身不接命中，舱带外命中
                // 的穿透由控制器根视图按实测舱帧判定
                Spacer(minLength: 0)
                content
                    // 舱帧实测：背景 GeometryReader 报
                    // 舱的窗口系帧（CGRect），Preference-
                    // Key 在托管树内上行（不跨托管边
                    // 界，量与收同树）→控制器据此算舱
                    // 顶回报并作透传判定帧
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ComposerBarFrameKey.self,
                                value: proxy.frame(in: .global)
                            )
                        }
                    }
            }
            .onPreferenceChange(ComposerBarFrameKey.self) { frame in
                controller.updateBarFrame(frame)
            }
            // A2：输入舱卡本体帧同树上行（写入点在
            // ChatView 的 inputBar，量点与收点同树、
            // 与整栈帧同一窗口系）→控制器据此定舱带
            // 高（带顶改随卡顶、不再随整栈顶）
            .onPreferenceChange(ComposerCardFrameKey.self) { frame in
                controller.updateCardFrame(frame)
            }
            .environment(appState)
            .environment(\.modelContext, modelContext)
            .environment(\.locale, locale)
            .boldTextMapping()
        )
    }
}

/// 舱帧实测的 PreferenceKey（单舱单值、取后到帧；
/// 零帧＝未布局，不采）
private struct ComposerBarFrameKey: PreferenceKey {
    // 计算属性形态：Swift 6 下存储型静态默认值会撞
    // 并发安全（nonisolated 全局可变状态）
    static var defaultValue: CGRect { .zero }
    static func reduce(
        value: inout CGRect, nextValue: () -> CGRect
    ) {
        let next = nextValue()
        if next.height > 0 { value = next }
    }
}

/// 输入舱卡本体帧的 PreferenceKey（A2 舱带收边）：
/// 写入点在 ChatView 的 inputBar（composerCard 外
/// 挂背景 GeometryReader），与整栈帧同一窗口系、同
/// 一棵托管树上行；口径与 ComposerBarFrameKey 同
/// 式（单值、取后到非零帧）。internal 而非 private
/// ——写入点跨文件在 ChatView
struct ComposerCardFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(
        value: inout CGRect, nextValue: () -> CGRect
    ) {
        let next = nextValue()
        if next.height > 0 { value = next }
    }
}

/// 透传根视图：只有舱宿主子视图的实帧接命中，本体空
/// 白处一律穿透到下层（消息列表）——列表的点空白收键
/// 盘、滚动手势的作用域不因本件盖了一层全帧视图而缩
private final class ComposerPassthroughView: UIView {
    /// 舱的窗口系实测帧（控制器逐次更新）：宿主全高
    /// 填充后，舱带外的空白区同在宿主子树内——命中
    /// 点落在实测舱帧外的一律放行穿透到下层（消息
    /// 列表）；帧未到（.zero）时全放行（首拍前的亚
    /// 拍级瞬态，舱随即实测就位）
    var barFrameInWindow: CGRect = .zero

    /// §193：入窗/换窗回调（锚解析的触发点之一；
    /// UIViewController 无 viewDidMoveToWindow，
    /// 锚解析借本视图的 didMoveToWindow 驱动）
    var onMoveToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onMoveToWindow?()
    }

    override func hitTest(
        _ point: CGPoint, with event: UIEvent?
    ) -> UIView? {
        let hit = super.hitTest(point, with: event)
        guard let hit, hit !== self else { return nil }
        guard barFrameInWindow.height > 0, let window
        else { return hit }
        let windowPoint = convert(point, to: window)
        return barFrameInWindow.contains(windowPoint)
            ? hit : nil
    }
}

/// 锚定托管控制器本体：只管舱宿主的钉位（§194 单
/// 常量：键盘帧顶／坞实测顶）与舱顶实测回报，不知
/// 业务页面。宿主全高
/// 填充本控制器视图（顶贴视图顶、底钉引导线），舱在
/// 托管树内被 Spacer 顶到宿主底边以理想高成帧（桥侧
/// apply 组合），本类不再经手舱高
final class ComposerGuideHostController: UIViewController {
    /// 舱根视图（桥注入；赋值即刷进舱宿主）
    var composerRoot: AnyView? {
        didSet {
            if let composerRoot {
                composerHost.rootView = composerRoot
            }
        }
    }
    /// 舱顶→窗口底距离变化回调（桥接回 SwiftUI 状态；
    /// 本类内先做等值守卫、变化 >0.5pt 才外发）
    var onBottomSpaceChange: ((CGFloat) -> Void)?
    /// §195：窗口顶安全区变化回调（同上守卫口径）
    var onTopSafeChange: ((CGFloat) -> Void)?

    private let composerHost = UIHostingController<AnyView>(
        rootView: AnyView(EmptyView())
    )
    /// §194 单约束（见文件头）：宿主底边恒钉自有位
    /// 置引导线 bottomGuide.topAnchor、永不切换激活
    /// 态；位置只活在 bottomGuideTopConstraint 的常
    /// 量里（键盘态＝通知帧顶、静息态＝坞实测顶，
    /// syncBottomConstant 唯一计算点）。§193 双锚
    /// （坞锚/键盘引导线锚＋通知切换）退役：151 真
    /// 机证伪引导线在本承载下不追踪、「模式切换」
    /// 本身即病灶。坞与键盘都只以「实测/广播的数」
    /// 进本层级、永不被约束直接引用——跨层级直钉
    /// 坞本体的约束在切格/藏坞的层级手术瞬间会成为
    /// 悬空约束、求解即抛 no-common-ancestor（CI
    /// 43337805344 两测试实证），整类不许回潮
    private var bottomConstraint: NSLayoutConstraint?
    /// 位置引导线：top 由 bottomGuideTopConstraint
    /// 的常量定位（布局空间换算，见 syncBottom-
    /// Constant）
    private let bottomGuide = UILayoutGuide()
    private var bottomGuideTopConstraint: NSLayoutConstraint!
    /// 坞锚当前参照（UITabBar 本体或类名兜底命中；
    /// 回落态为 nil 且 dockIsFallback=true，参照＝
    /// 窗口安全区底）。只读其实帧、不被约束引用，
    /// 离场最多让常量短暂陈旧、下个离散事件即刷新
    private weak var dockBarView: UIView?
    private var dockIsFallback = false
    private weak var anchorWindow: UIWindow?
    private var keyboardUp = false
    /// §194 键盘顶存账（窗口坐标）：willShow/will-
    /// ChangeFrame 通知的结束帧顶——键盘本人广播的
    /// 真值，常量换算的唯一键盘输入；收起即清
    private var keyboardTopInWindow: CGFloat?
    /// 舱的窗口系实测帧（桥的 Preference 通道喂入）：
    /// 回报与透传判定共用这一份事实
    private var barFrameInWindow: CGRect = .zero
    private var lastReportedSpace: CGFloat = -1
    /// §195：窗口顶安全区上次回报值（等值守卫）
    private var lastReportedTopSafe: CGFloat = -1
    /// §210 舱带注册容器（透明，EdgeBandContainer-
    /// View＋底缘 interaction）：舱宿主层级内最底
    /// 层；左右/底随舱宿主、高由 bandHeightCon-
    /// straint 承实测帧算出（A2 卡段高：整栈帧底−卡
    /// 帧顶；卡帧未到回落整栈高；syncBandHeight 唯
    /// 一计算点，两路帧喂入同拍同步，种子 0＝帧未
    /// 到时零高）。容器本身无色——静止态条下无内容
    /// 时此带与页面同色，内容滚过时系统边缘效果在
    /// 容器后自适应化开
    private let bandView = EdgeBandContainerView(edge: .bottom)
    private var bandHeightConstraint: NSLayoutConstraint!
    /// §210：列表滚动视图句柄（桥注入；赋值即尝试
    /// 对齐绑定，本体未登记时由显形/布局拍补绑）
    var edgeScrollHandle: ChatListScrollViewHandle? {
        didSet { refreshEdgeBinding() }
    }

    private func refreshEdgeBinding() {
        guard let scrollView = edgeScrollHandle?.scrollView
        else { return }
        bandView.bind(scrollView: scrollView)
    }
    /// A2：输入舱卡本体的窗口系实测帧（桥的 Prefe-
    /// rence 通道喂入）：只供舱带高计算（带顶随卡
    /// 顶），不参与舱顶回报与透传判定（那两路仍只
    /// 认整栈帧，口径零改动）
    private var cardFrameInWindow: CGRect = .zero

    /// §210 自述/测试定位口：舱带注册容器本体
    var traceComposerHostView: UIView { composerHost.view }
    var traceBandView: UIView { bandView }

    /// 舱帧喂入点（托管树每次布局后经 Preference 上
    /// 行）：存帧、同步给透传判定、并立即尝试回报——
    /// 舱在树内生长时本类未必有布局拍，回报不能只靠
    /// viewDidLayoutSubviews 兜底
    func updateBarFrame(_ frame: CGRect) {
        guard frame.height > 0 else { return }
        barFrameInWindow = frame
        (viewIfLoaded as? ComposerPassthroughView)?
            .barFrameInWindow = frame
        // §210/A2：舱带高随实测帧同拍同步（计算点收
        // 口 syncBandHeight：带顶随卡帧顶、整栈生长
        // ——多行输入、错误条、回底钮行显隐——只经卡
        // 帧/整栈帧两路输入进公式）
        syncBandHeight()
        reportBottomSpace()
    }

    /// A2：输入舱卡本体帧喂入点（托管树每次布局后
    /// 经 Preference 上行）：只存帧并同拍重算舱带高
    /// ——卡在树内生长（引用块/附件条/多行输入）时本
    /// 类未必有布局拍，同步不能只靠整栈帧通道兜底
    /// （与 updateBarFrame 的即时回报同判）
    func updateCardFrame(_ frame: CGRect) {
        guard frame.height > 0 else { return }
        cardFrameInWindow = frame
        syncBandHeight()
    }

    /// A2 舱带高唯一计算点：带底恒＝整栈帧底（带底
    /// 边钉宿主底、整栈底贴宿主底，两值同位）；带
    /// 顶＝卡帧顶（卡帧未到回落整栈帧顶）。两帧同
    /// 为窗口系、相减即带高（高度是标量，与本地坐
    /// 标系无关）。偏差 >0.5 才写，与原同步守卫同档
    private func syncBandHeight() {
        guard isViewLoaded, bandHeightConstraint != nil,
              barFrameInWindow.height > 0
        else { return }
        let top = cardFrameInWindow.height > 0
            ? cardFrameInWindow.minY
            : barFrameInWindow.minY
        let height = barFrameInWindow.maxY - top
        guard height > 0,
              abs(bandHeightConstraint.constant - height)
                > 0.5
        else { return }
        bandHeightConstraint.constant = height
        view.setNeedsLayout()
    }

    override func loadView() {
        let passthrough = ComposerPassthroughView()
        // §193：入窗/换窗即重解析锚并按当前键盘态
        // 生效（控制器无 viewDidMoveToWindow，借根
        // 视图的 didMoveToWindow 驱动）
        passthrough.onMoveToWindow = { [weak self] in
            self?.resolveAnchors()
        }
        view = passthrough
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // 舱宿主自管安全区：托管树的安全区归零——舱是
        // 自包含栈（内边距全在内容里，见 inputBar 注），
        // 不许宿主再按窗口安全区给它派生一份（双计防线，
        // 配件核查报告第 6 条同坑）
        composerHost.safeAreaRegions = []
        addChild(composerHost)
        composerHost.view.backgroundColor = .clear
        composerHost.view.translatesAutoresizingMaskIntoConstraints =
            false
        view.addSubview(composerHost.view)
        composerHost.didMove(toParent: self)
        // §210：舱带注册容器入层——插在舱宿主之下
        // （本视图子视图序最底）；左右/底随舱宿主、
        // 高由 bandHeightConstraint 承实测帧算出的带
        // 高（A2 卡段高，syncBandHeight 同步，种子 0
        // ＝未到帧零高）。容器透明无色、只承载底缘
        // 效果注册（见文件头 §210）
        bandView.translatesAutoresizingMaskIntoConstraints =
            false
        view.insertSubview(
            bandView, belowSubview: composerHost.view
        )
        bandHeightConstraint = bandView.heightAnchor
            .constraint(equalToConstant: 0)
        refreshEdgeBinding()
        // §194：宿主顶/左右贴本视图、底边恒钉位置引
        // 导线（单约束永不切换，见 syncBottomCon-
        // stant）：引导线先入本视图（top 常量待 sync-
        // BottomConstant 按当前输入填，初始 0＝未解
        // 析前宿主贴顶、无害瞬态）
        view.addLayoutGuide(bottomGuide)
        bottomGuideTopConstraint = bottomGuide.topAnchor
            .constraint(equalTo: view.topAnchor, constant: 0)
        let bottom = composerHost.view.bottomAnchor
            .constraint(equalTo: bottomGuide.topAnchor)
        bottomConstraint = bottom
        NSLayoutConstraint.activate([
            composerHost.view.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            composerHost.view.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            composerHost.view.topAnchor.constraint(
                equalTo: view.topAnchor),
            bottomGuide.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            bottomGuide.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            bottomGuide.heightAnchor.constraint(
                equalToConstant: 0),
            bottomGuideTopConstraint,
            bottom,
            bandView.leadingAnchor.constraint(
                equalTo: composerHost.view.leadingAnchor),
            bandView.trailingAnchor.constraint(
                equalTo: composerHost.view.trailingAnchor),
            bandView.bottomAnchor.constraint(
                equalTo: composerHost.view.bottomAnchor),
            bandHeightConstraint,
        ])
        if barFrameInWindow.height > 0 {
            (view as? ComposerPassthroughView)?
                .barFrameInWindow = barFrameInWindow
        }
        // 键盘信号（§194）：willShow/willHide 定状态
        // 翻转、willChangeFrame 供逐帧跟随，三者的结
        // 束帧都是位置常量的键盘输入；动画参数（时
        // 长/曲线）随通知取，与系统键盘动画同步。
        // selector 式观察者（不存 token）：块式 token
        // 数组在 Swift 6 下 deinit 不可访问、Notifi-
        // cation 跨闭包发送亦被判竞态（CI 43337400356
        // 实证）
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        center.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func keyboardWillShow(
        _ note: Notification
    ) {
        setKeyboardUp(true, note: note)
    }

    @objc private func keyboardWillHide(
        _ note: Notification
    ) {
        setKeyboardUp(false, note: note)
    }

    /// §194 帧变化跟进（交互式下滑收键盘/候选条高
    /// 度变化）：键盘态内逐事件刷新存账帧顶并重算常
    /// 量——通知帧是键盘本人的广播，不经任何引导线
    /// 转译；时长 0 的逐帧事件直接布局、不包动画
    @objc private func keyboardWillChangeFrame(
        _ note: Notification
    ) {
        guard keyboardUp else { return }
        updateKeyboardTop(from: note)
        syncBottomConstant()
        animateLayout(with: note, immediateIfZero: true)
    }

    /// §194 键盘帧顶存账：通知的结束帧是屏幕坐标，
    /// 经本窗换算成窗口坐标存下（全屏单窗下与屏幕
    /// 同值，换算保多窗口径）；常量换算在 syncBot-
    /// tomConstant 里逐布局拍按本视图当前布局空间
    /// 重算，本函数只存窗口真值
    private func updateKeyboardTop(from note: Notification) {
        guard let value = note.userInfo?[
            UIResponder.keyboardFrameEndUserInfoKey
        ] as? NSValue else { return }
        let screenFrame = value.cgRectValue
        if let window = view.window {
            keyboardTopInWindow = window.convert(
                screenFrame, from: nil
            ).minY
        } else {
            keyboardTopInWindow = screenFrame.minY
        }
    }

    /// 与键盘动画同参推进一次布局（时长/曲线取自
    /// 通知）；immediateIfZero 时时长为 0 直接布局
    /// ——交互式逐帧跟随不许包进动画系统再迟一拍
    private func animateLayout(
        with note: Notification, immediateIfZero: Bool
    ) {
        let userInfo = note.userInfo
        let duration = userInfo?[
            UIResponder.keyboardAnimationDurationUserInfoKey
        ] as? Double ?? 0.25
        let curveRaw = userInfo?[
            UIResponder.keyboardAnimationCurveUserInfoKey
        ] as? UInt ?? 7
        if immediateIfZero, duration <= 0 {
            view.layoutIfNeeded()
            return
        }
        UIView.animate(
            withDuration: duration, delay: 0,
            options: UIView.AnimationOptions(
                rawValue: curveRaw << 16
            )
        ) { [weak self] in
            self?.view.layoutIfNeeded()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // §193 锚解析触发点之二（入窗触发点在透传视
        // 图的 didMoveToWindow，见 loadView 接线）：
        // 每次显形重解析——切格往返期间标签栏实例
        // 若被换过，旧参照在此换新（常量随之由
        // syncBottomConstant 重算，resolveAnchors 尾）
        resolveAnchors()
    }

    /// §193 锚解析：在本视图所在窗口的层级里找坞参
    /// 照（UITabBar 本体或类名兜底），只登记引用与
    /// 命中模式——位置由 syncBottomConstant 逐拍换
    /// 算进位置常量，参照本身不被任何约束引用。触
    /// 发点只在离散事件（入窗/显形/键盘收起/回落态
    /// 布局拍自愈），不在每拍布局里走层级
    private func resolveAnchors() {
        guard let window = view.window else { return }
        let windowChanged = anchorWindow !== window
        anchorWindow = window
        let foundBar = Self.findDockAnchor(in: window)
        if let foundBar {
            if dockBarView !== foundBar.view || dockIsFallback
                || windowChanged {
                dockBarView = foundBar.view
                dockIsFallback = false
            }
            // §210：坞内不再装任何自家子视图——UITab-
            // Bar 是系统条，其边缘呈现归系统自身（§200
            // 坞底衬退役）；本函数对坞仍只读帧
        } else if !dockIsFallback || windowChanged {
            // 无坞环境回落（探针裸装配等非生产形态）：
            // 参照＝窗口安全区底——生产装配恒有坞，
            // 不走此路
            dockBarView = nil
            dockIsFallback = true
        }
        syncBottomConstant()
    }

    /// §194 位置常量唯一计算点：bottomGuide 的 top
    /// 常量＝目标顶边－本视图布局空间顶边。目标顶
    /// 边按当前输入取实测真值：键盘升起态＝通知广
    /// 播的键盘帧顶（窗口坐标——键盘升起时抽屉必
    /// 闭、祖先链 transform 恒等，窗口坐标与布局空
    /// 间累加坐标同值；无帧存账时保留上次常量、不
    /// 许跌回坞值）；静息态＝坞参照的布局空间顶边
    /// （沿 superview 链累加 frame 原点——布局真
    /// 值、忽略 transform，抽屉平移不假补偿、舱随
    /// 前景同移）。逐布局拍调用（只读缓存值、无层
    /// 级遍历），偏差 >0.5 才写：键盘态下本视图布
    /// 局空间顶边若因藏坞等层级手术变化，常量随之
    /// 重算、舱的窗口落点恒钉键盘顶。参照离场
    /// （window 对不上）时保留上次常量——位置短暂
    /// 陈旧但绝不悬空，下个离散事件重解析刷新
    private func syncBottomConstant() {
        guard let window = view.window,
              let bottomGuideTopConstraint else { return }
        let targetTop: CGFloat
        if keyboardUp {
            guard let kbTop = keyboardTopInWindow
            else { return }
            targetTop = kbTop
        } else if let bar = dockBarView,
                  bar.window === window {
            targetTop = Self.layoutSpaceMinY(of: bar)
        } else if dockIsFallback {
            targetTop = window.bounds.height
                - window.safeAreaInsets.bottom
        } else {
            return
        }
        let constant = targetTop
            - Self.layoutSpaceMinY(of: view)
        if abs(bottomGuideTopConstraint.constant - constant)
            > 0.5 {
            bottomGuideTopConstraint.constant = constant
        }
    }

    /// 视图在窗口布局空间的顶边（frame 原点沿父链
    /// 累加；transform 不进布局帧、天然不计）
    private static func layoutSpaceMinY(
        of view: UIView
    ) -> CGFloat {
        var y = view.frame.minY
        var ancestor = view.superview
        while let current = ancestor,
              !(current is UIWindow) {
            y += current.frame.minY
            ancestor = current.superview
        }
        return y
    }

    /// §194 键盘态翻转：升起先把通知帧顶存账（常量
    /// 的唯一键盘输入），收起先重解析坞参照（聚焦
    /// 藏坞期间标签栏可能换实例）；常量重算后与键
    /// 盘动画同参推进布局。翻转与记账随自述落盘＋
    /// 事件采样（即时一帧＋0.9 秒落定一帧），真机
    /// 验收看数字不看肉眼
    private func setKeyboardUp(
        _ up: Bool, note: Notification
    ) {
        if up {
            updateKeyboardTop(from: note)
        } else {
            resolveAnchors()
        }
        guard up != keyboardUp else {
            // 同态重播（willShow 重发等）：按已存帧顶
            // 重同步常量即可，不重入采样与记账
            if up {
                syncBottomConstant()
                view.layoutIfNeeded()
            }
            return
        }
        keyboardUp = up
        if !up { keyboardTopInWindow = nil }
        syncBottomConstant()
        animateLayout(with: note, immediateIfZero: false)
    }

    /// 窗口层级内找坞锚目标（深度优先两级）：先
    /// UITabBar 本体；无本体时取类名含 TabBar 且宽
    /// 度 >300 的视图（系统内部实现跨版本改名/换类
    /// 的兜底——149 真机 iOS 27 上 platter 类缺席、
    /// 坞本体类名未定，锚目标不许绑死单一类名）
    private static func findDockAnchor(
        in window: UIWindow
    ) -> (view: UIView, mode: String)? {
        func walk(_ view: UIView) -> UIView? {
            if let bar = view as? UITabBar { return bar }
            for sub in view.subviews {
                if let hit = walk(sub) { return hit }
            }
            return nil
        }
        if let bar = walk(window) {
            return (bar, "uitabbar")
        }
        func walkByName(_ view: UIView) -> UIView? {
            let name = String(describing: type(of: view))
            if name.contains("TabBar"),
               view.frame.width > 300 {
                return view
            }
            for sub in view.subviews {
                if let hit = walkByName(sub) { return hit }
            }
            return nil
        }
        if let named = walkByName(window) {
            return (named, "tabbarByName")
        }
        return nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // §194：本拍做位置常量同步（只读缓存的坞参
        // 照实帧/键盘存账帧顶）、舱顶回报与回落态自
        // 愈（回落＝窗口内暂未找到坞：标签栏随呈现
        // 时序迟到时在此补解析，找到即退出回落、不
        // 再走层级）。§186 地板钳制与 §192 控制器侧
        // 主动量测（布局拍内调 fitting 触发重入式布
        // 局、150 探针两场景超时与此相关）均已随锚
        // 定重构退役
        if dockIsFallback, !keyboardUp {
            resolveAnchors()
        }
        // §210：舱带绑定同路刷新（列表本体登记晚于
        // 本控制器装配时在此补绑；指针比对、恒廉价）
        refreshEdgeBinding()
        syncBottomConstant()
        reportBottomSpace()
        reportTopSafe()
    }

    /// §195 窗口顶安全区实测回报：读本视图所在窗口
    /// 的 safeAreaInsets.top（UIKit 窗口真值——152
    /// 真机自述全帧恒 62，键盘/标签栏状态无关），变
    /// 化 >0.5 才外发。ChatView 以此值记账列表顶
    /// contentMargins（见文件头 §195）；窗口未就绪
    /// （离窗瞬间）不发、保留上次值
    private func reportTopSafe() {
        guard let window = viewIfLoaded?.window
        else { return }
        let top = window.safeAreaInsets.top
        guard top > 0,
              abs(top - lastReportedTopSafe) > 0.5
        else { return }
        lastReportedTopSafe = top
        onTopSafeChange?(top)
    }

    /// 舱顶实测回报：以桥喂入的窗口系舱帧为准，报
    /// 「舱顶→窗口底」距离——页帧在键盘态如何伸缩、
    /// 宿主填充多高都不进公式，ChatView 侧只做
    /// ＋spacingS 一步
    private func reportBottomSpace() {
        guard let window = viewIfLoaded?.window,
              barFrameInWindow.height > 0
        else { return }
        let space = window.bounds.height
            - barFrameInWindow.minY
        guard abs(space - lastReportedSpace) > 0.5 else { return }
        lastReportedSpace = space
        onBottomSpaceChange?(space)
    }
}
