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
struct ComposerGuideHost<Content: View>: UIViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    /// 舱顶→窗口底距离的实测回报（host 在布局拍回写；
    /// ChatView 以此＋spacingS 作列表底 contentMargins）
    @Binding var bottomSpace: CGFloat
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

    init(
        bottomSpace: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        self._bottomSpace = bottomSpace
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
        // §192 量测：fit 往来逐字记账（提议×回报）——
        // 149 真机证伪「默认拟合回 1030」后，1030 到
        // 底是谁在协商里提出的，只认这本账：若提议
        // 本身即 1030，撑高者在上层（ZStack 提议来
        // 源）；若提议 729 而落位仍 1030，协商之外
        // 另有通道（控制器侧量测同轮对账）
        BarsGeometryTrace.noteFit(
            "hostFit proposal=(\(BarsTraceFormat.dim(proposal.width)),"
                + "\(BarsTraceFormat.dim(proposal.height))) -> "
                + (result.map { BarsTraceFormat.size($0) }
                    ?? "nil(默认)")
        )
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
                    // §192 量测：舱本体（bottomBar 整
                    // 栈）在托管树内的实尺寸——149 动态
                    // 证据示盒高随舱内容固有高同涨，此
                    // 数是那条链的第一环
                    .onGeometryChange(
                        for: CGSize.self
                    ) { proxy in
                        proxy.size
                    } action: { _, size in
                        controller.updateBarContentSize(size)
                    }
            }
            // §192 量测：宿主 VStack（Spacer＋舱）整体
            // 实尺寸——与控制器侧 hostFit@… 对账：内栈
            // 若在 729 提议下自报更高，撑高者即在此树内
            .onGeometryChange(
                for: CGSize.self
            ) { proxy in
                proxy.size
            } action: { _, size in
                controller.updateHostStackSize(size)
            }
            .onPreferenceChange(ComposerBarFrameKey.self) { frame in
                controller.updateBarFrame(frame)
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

/// 锚定托管控制器本体：只管舱宿主的钉位（§193 双
/// 锚：坞顶／窗口键盘引导线）与舱顶实测回报，不知
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

    private let composerHost = UIHostingController<AnyView>(
        rootView: AnyView(EmptyView())
    )
    /// §193 双锚（见文件头）：坞锚（键盘落下）与键盘
    /// 锚（键盘升起）恒只活一条。两条都是**本视图内
    /// 层级**的约束（坞锚经自有布局引导线翻译、键盘
    /// 锚钉本视图 keyboardLayoutGuide）——跨层级直
    /// 钉坞本体的约束在切格/藏坞的层级手术瞬间会成
    /// 为悬空约束、求解即抛 no-common-ancestor（CI
    /// 43337805344 两测试实证），故坞的位置只以「实
    /// 帧换算出的常量」进本层级，锚本体永不被约束
    /// 直接引用
    private var dockBottomConstraint: NSLayoutConstraint?
    private var keyboardBottomConstraint: NSLayoutConstraint?
    /// 坞锚引导线：top 由 dockGuideTopConstraint 的
    /// 常量定位（布局空间换算，见 syncDockConstant）
    private let dockGuide = UILayoutGuide()
    private var dockGuideTopConstraint: NSLayoutConstraint!
    /// 坞锚当前参照（UITabBar 本体或类名兜底命中；
    /// 回落态为 nil 且 dockIsFallback=true，参照＝
    /// 窗口安全区底）。只读其实帧、不被约束引用，
    /// 离场最多让常量短暂陈旧、下个离散事件即刷新
    private weak var dockBarView: UIView?
    private var dockIsFallback = false
    private weak var anchorWindow: UIWindow?
    private var keyboardUp = false
    /// 舱的窗口系实测帧（桥的 Preference 通道喂入）：
    /// 回报与透传判定共用这一份事实
    private var barFrameInWindow: CGRect = .zero
    private var lastReportedSpace: CGFloat = -1

    /// §192 量测喂入：舱本体在托管树内的实尺寸
    func updateBarContentSize(_ size: CGSize) {
        BarsGeometryTrace.noteProbe(
            "barContent", BarsTraceFormat.size(size)
        )
    }

    /// §192 量测喂入：宿主 VStack 整体实尺寸
    func updateHostStackSize(_ size: CGSize) {
        BarsGeometryTrace.noteProbe(
            "hostStack", BarsTraceFormat.size(size)
        )
    }

    /// 舱帧喂入点（托管树每次布局后经 Preference 上
    /// 行）：存帧、同步给透传判定、并立即尝试回报——
    /// 舱在树内生长时本类未必有布局拍，回报不能只靠
    /// viewDidLayoutSubviews 兜底
    func updateBarFrame(_ frame: CGRect) {
        guard frame.height > 0 else { return }
        barFrameInWindow = frame
        (viewIfLoaded as? ComposerPassthroughView)?
            .barFrameInWindow = frame
        reportBottomSpace()
    }

    override func loadView() {
        let passthrough = ComposerPassthroughView()
        // §193：入窗/换窗即重解析锚并按当前键盘态
        // 生效（控制器无 viewDidMoveToWindow，借根
        // 视图的 didMoveToWindow 驱动）
        passthrough.onMoveToWindow = { [weak self] in
            self?.resolveAnchors()
            self?.applyAnchorState()
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
        // §193：宿主顶/左右贴本视图、底边走双锚（全
        // 部本层级约束，见 resolveAnchors/applyAnchor-
        // State/syncDockConstant）：坞引导线先入本视
        // 图（top 常量待 syncDockConstant 按坞实帧填，
        // 初始 0＝未解析前宿主贴顶、无害瞬态）
        view.addLayoutGuide(dockGuide)
        dockGuideTopConstraint = dockGuide.topAnchor
            .constraint(equalTo: view.topAnchor, constant: 0)
        dockBottomConstraint = composerHost.view.bottomAnchor
            .constraint(equalTo: dockGuide.topAnchor)
        keyboardBottomConstraint = composerHost.view
            .bottomAnchor.constraint(
                equalTo: view.keyboardLayoutGuide.topAnchor
            )
        NSLayoutConstraint.activate([
            composerHost.view.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            composerHost.view.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            composerHost.view.topAnchor.constraint(
                equalTo: view.topAnchor),
            dockGuide.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            dockGuide.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            dockGuide.heightAnchor.constraint(equalToConstant: 0),
            dockGuideTopConstraint,
        ])
        if barFrameInWindow.height > 0 {
            (view as? ComposerPassthroughView)?
                .barFrameInWindow = barFrameInWindow
        }
        // 键盘锚切换信号（§193）：willShow/willHide
        // 是唯一状态源，动画参数（时长/曲线）随通知
        // 取，与系统键盘动画同步。selector 式观察者
        // （不存 token）：块式 token 数组在 Swift 6
        // 下 deinit 不可访问、Notification 跨闭包发
        // 送亦被判竞态（CI 43337400356 实证）
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // §193 锚解析触发点之二（入窗触发点在透传视
        // 图的 didMoveToWindow，见 loadView 接线）：
        // 每次显形重解析——切格往返期间标签栏实例
        // 若被换过，旧锚在此换新
        resolveAnchors()
        applyAnchorState()
    }

    /// §193 锚解析：在本视图所在窗口的层级里找坞参
    /// 照（UITabBar 本体或类名兜底），只登记引用与
    /// 命中模式——位置由 syncDockConstant 逐拍换算
    /// 进引导线常量，参照本身不被任何约束引用。触
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
                BarsGeometryTrace.noteProbe(
                    "anchorMode", foundBar.mode
                )
            }
        } else if !dockIsFallback || windowChanged {
            // 无坞环境回落（探针裸装配等非生产形态）：
            // 参照＝窗口安全区底——生产装配恒有坞，
            // 不走此路
            dockBarView = nil
            dockIsFallback = true
            BarsGeometryTrace.noteProbe(
                "anchorMode", "fallbackWindowSafe"
            )
        }
        syncDockConstant()
        applyAnchorState()
    }

    /// §193 坞锚换算：坞参照的布局空间顶边（沿
    /// superview 链累加 frame 原点——布局真值、忽
    /// 略 transform，抽屉平移不假补偿、舱随前景同
    /// 移）换算成本视图坐标内的引导线 top 常量；
    /// 逐布局拍调用（只读缓存参照的帧、无层级遍
    /// 历），偏差 >0.5 才写。参照离场（window 对不
    /// 上）时保留上次常量——位置短暂陈旧但绝不悬
    /// 空，下个离散事件重解析刷新
    private func syncDockConstant() {
        guard let window = view.window,
              let dockGuideTopConstraint else { return }
        let targetTop: CGFloat
        if let bar = dockBarView, bar.window === window {
            targetTop = Self.layoutSpaceMinY(of: bar)
        } else if dockIsFallback {
            targetTop = window.bounds.height
                - window.safeAreaInsets.bottom
        } else {
            return
        }
        let constant = targetTop - Self.layoutSpaceMinY(of: view)
        if abs(dockGuideTopConstraint.constant - constant)
            > 0.5 {
            dockGuideTopConstraint.constant = constant
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

    /// §193 锚生效：键盘态决定唯一活锚（先灭后亮，
    /// 防同边双约束瞬时冲突；两锚皆本层级约束，
    /// 激活时机无跨层级前提）
    private func applyAnchorState() {
        if keyboardUp {
            dockBottomConstraint?.isActive = false
            keyboardBottomConstraint?.isActive = true
        } else {
            keyboardBottomConstraint?.isActive = false
            dockBottomConstraint?.isActive = true
        }
    }

    /// §193 键盘态切换：收起时先重解析坞锚（聚焦藏
    /// 坞期间标签栏可能换实例，旧约束不许指向已离场
    /// 的视图）；约束切换与键盘动画同参推进
    private func setKeyboardUp(
        _ up: Bool, note: Notification
    ) {
        if !up { resolveAnchors() }
        guard up != keyboardUp else { return }
        keyboardUp = up
        applyAnchorState()
        let userInfo = note.userInfo
        let duration = userInfo?[
            UIResponder.keyboardAnimationDurationUserInfoKey
        ] as? Double ?? 0.25
        let curveRaw = userInfo?[
            UIResponder.keyboardAnimationCurveUserInfoKey
        ] as? UInt ?? 7
        UIView.animate(
            withDuration: duration, delay: 0,
            options: UIView.AnimationOptions(
                rawValue: curveRaw << 16
            )
        ) { [weak self] in
            self?.view.layoutIfNeeded()
        }
    }

    /// 窗口层级内找坞锚目标（深度优先两级）：先
    /// UITabBar 本体；无本体时取类名含 TabBar 且宽
    /// 度 >300 的视图（系统内部实现跨版本改名/换类
    /// 的兜底——149 真机 iOS 27 上 platter 类缺席、
    /// 坞本体类名未定，锚目标不许绑死单一类名）。
    /// 命中模式随自述落盘（anchorMode），真机判读
    /// 先看锚钉没钉对、再看帧
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
        // §193：本拍做坞锚常量同步（只读缓存参照实
        // 帧）、舱顶回报与回落态自愈（回落＝窗口内
        // 暂未找到坞：标签栏随呈现时序迟到时在此补
        // 解析，找到即退出回落、不再走层级）。§186
        // 地板钳制与 §192 控制器侧主动量测（布局拍
        // 内调 fitting 触发重入式布局、150 探针两场
        // 景超时与此相关）均已随锚定重构退役
        if dockIsFallback, !keyboardUp {
            resolveAnchors()
        }
        syncDockConstant()
        reportBottomSpace()
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
