import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit

/// 顶簇锚定托管（§195，2026-11-13，用户 10:42 亲
/// 定口径：大厂标准就是顶栏固定不动）：顶栏（汉
/// 堡钮＋身份胶囊＋铃铛）与进展胶囊自此退出消息
/// 列表的 .safeAreaBar(edge: .top) 注册，改由本
/// 件以 UIKit 约束锚定——纵坐标只由窗口顶部安全
/// 区决定，与输入舱的 surface、与坞、与键盘彻底
/// 脱钩，任何帧（静息/kbShow/kbShowSettled/
/// kbHide/抽屉）恒为窗口顶安全区（真机 62），动
/// 1pt 不算过（用户验收口径原话大意）。
///
/// ## 耦合路径（断链证据，152 真机自述）
/// 旧形态下 pocket 虽不在输入舱的承载里，却挂在
/// 同一条传播链上：TabView 页面把安全区传播进
/// ChatView → 列表 adjustedContentInset.top 与
/// safeAreaBar 的落位都读这份传播值 →
/// `.toolbar(.hidden, for: .tabBar)` 藏坞落定后
/// SwiftUI 重算页面安全区、top/bottom 各偷 49
/// （标签栏高；minimize 已写死 .never、无关）→
/// pocket 62→13 撞状态栏、adjTop 122→73。输入
/// 舱同帧独活，只因 §194 的常量读窗口坐标自纠
/// ——顶边没有这层保护。本轮把同一式子搬到顶
/// 边：宿主底/顶都只认实测真值，传播链再翻与
/// 顶簇无关（列表顶留位同步改走实测 content-
/// Margins，与底缘 §186 同式，见 ChatView）。
///
/// ## 接法（与 ComposerGuideHost 同式）
/// - 本件挂 chatSurface 复合面的 .overlay 次级层
///   （不参加父级尺寸协商，§193 同判）；控制器
///   视图是透传视图（顶簇带之外不拦命中，列表滚
///   动/点空白收键盘照常落到下层）。
/// - 顶簇宿主（子 UIHostingController）顶边钉自
///   有 topGuide：其 top 常量＝窗口顶安全区实测
///   − 本视图布局空间顶边，逐布局拍由 syncTop-
///   Constant 一个函数重算——SwiftUI 把本视图帧
///   再挪到哪（落定重算把 overlay 帧挪到 13 的
///   同型事），常量随之补偿、顶簇的窗口落点恒定
///   （§194 舱在 152 落定帧靠同式自纠、终值正确，
///   是本式的真机前证）。
/// - 顶簇高不经任何 sizing 通道：内容以 fixed-
///   Size 只认自身实高、经 onGeometryChange 实测
///   回报控制器定高约束，并同值回写 ChatView 作
///   列表顶 contentMargins 的记账（＋窗口顶安全
///   区常数，见 ChatView messageList §195 注）。
/// - 宿主 safeAreaRegions 置空（与舱宿主同纪律）：
///   托管树不许再按任何安全区派生内边距，顶簇内
///   布局只认宿主帧本体。
/// - 环境注入照 ComposerGuideHost 先例（宿主不
///   继承桥的环境）：AppState、modelContext、
///   locale 在桥侧读出后逐项写进顶簇宿主根视图，
///   粗体映射同挂；trait 类经控制器层级自动派生。
///
/// ## §213 顶缘改内容驱动注册（2026-11-13，用户
/// 21:39 验收口径，取代 §200 顶带底衬）
/// §200 曾在本层级内垫均匀系统磨砂（窗口顶→顶簇
/// 底）治内容透字；用户 21:39 点名：条下无内容时
/// 须与页面同色不可见、有内容滚过才朦胧——常驻材
/// 质片与内容无关恒定渲染、静止自成色带（探针实
/// 证静止色差深色 39），§200 机制就此退役。改走
/// 系统边缘效果正道注册（ScrollEdgeRegistrat-
/// ion）：interaction 直接挂顶簇宿主视图（紧凑容
/// 器、后代玻璃即效果形状，WWDC25-284 原式）；
/// 状态栏带由列表自身的顶缘 .soft 效果覆盖（消
/// 融臂实证成立）。胶囊玻璃本体（§179 定式）一字
/// 不动；栏位落位/记账口径零改动。
///
/// ## §327 顶簇不透明背板（2026-11-17 入席，
/// 2026-11-22 退役，用户 0.50.78 真机反馈亲裁）
/// §213 的内容驱动边缘效果治得了「静止自成色
/// 带」，治不了滚动态正文滑入顶簇带后隔着半透
/// 明胶囊与柔边可读，审计二选一裁决曾取背板
/// 路：控制器在顶簇宿主之下垫 Palette.chat-
/// Surface 实色背板（与页面底同令牌同值：静止
/// 时与页面同色不可见、滚动态对带下正文全遮
/// 蔽），覆盖窗口顶→顶簇底全带；胶囊玻璃本体
/// 与 §213 边缘注册当时一字未动。2026-11-20
/// 又因背板是带内唯一无条件不透明层、内容链
/// 某帧缺席时独自裸呈成整块实心白，加「背板
/// 入席闸门」（可见性与顶簇首个实测高挂钩、
/// 单向入席）与树内契约兜底。2026-11-22 用
/// 户真机反馈 0.50.78：顶栏实色块又在、朦胧
/// 感没了——实色口径就此退役，背板整件删除，
/// 带面回到 §213 系统边缘效果单机制（下节）。
///
/// ## 带面构造（2026-11-22 定版，取代 §327）
/// 顶簇带面不垫任何自家层：控制器子视图只剩
/// 顶簇宿主本体，带下透明——静止时控件自身玻
/// 璃（§179 定式）直浮页面底；内容滚过带下时
/// 由 §213 注册的系统滚动边缘效果在栏下沿生
/// 成模糊渐变（interaction 挂顶簇宿主、样式由
/// 列表顶缘 edge effect 承），§327 的透字问
/// 题自此归系统机制覆盖（iOS 26 通行形态），
/// 不再自绘不透明板。原入席闸门的等价物是结
/// 构本身：带内无板即无裸板——内容链缺席帧
/// 里带内只有透明宿主，白块无从产生。首个实
/// 测高闩 hasBarContentMeasure 降为纯取证信
/// 号（内容链齐备度留痕，见 viewDidAppear），
/// 不再驱动任何可见层显隐。
///
/// ## 树内契约（2026-11-20 立，2026-11-22 随
/// 带面构造改版，纲要原则 3/4、D3-1/D3-2）
/// 把装配不变量钉在控制器本体上：①控制器子
/// 视图恒只含顶簇宿主一层——带内不许再垫任何
/// 自绘层（背板/材质片/色片同禁），「内容缺席
/// 时无裸块」是结构保证而非运行时巧合；②宿
/// 主 safeAreaRegions 恒空（托管树不许按安全
/// 区派生内边距）。契约自检＝assemblyContract-
/// Violations()：装配完成（viewDidLoad）与首
/// 个实测高两拍各断言一次，测试侧同口直读。
/// 常数回写（实高/底缘）是记账通道、只喂列表
/// 留位、不驱动任何可见层显隐。
struct TopBarGuideHost<Content: View>: UIViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    /// 顶簇实高的实测回报（host 在布局拍回写；
    /// ChatView 以窗口顶安全区＋此值作列表顶
    /// contentMargins，顶留位记账只剩这一处）
    @Binding var barHeight: CGFloat
    /// §321：顶簇底缘的窗口坐标实测回报（host 在
    /// 布局拍以活帧 convert 回写）——新面列表顶
    /// inset 自此认本值（顶簇在窗口里的真实底边，
    /// 安全区/实高/进展胶囊生长全含），不再在
    /// ChatView 侧以两个独立种子数相加推算；未接
    /// 本绑定的调用点（存量测试装配）默认 .constant
    /// 占位、行为不变
    @Binding var barBottom: CGFloat
    /// 顶簇本体（ChatView 的 headerBar＋进展胶囊）：
    /// 在 init 里由构建闭包求值成视图值——求值发生
    /// 在 ChatView 的 body 构建期，内部状态读数由
    /// 此归因到 ChatView（与 ComposerGuideHost
    /// content 同一条归因链）
    var content: Content
    /// §213：聊天列表滚动视图句柄（ChatView 同一份
    /// 亦喂舱宿主与列表内锚点；控制器据此把顶缘
    /// interaction 的 scrollView 对齐列表本体）
    let scrollHandle: ChatListScrollViewHandle

    init(
        barHeight: Binding<CGFloat>,
        barBottom: Binding<CGFloat> = .constant(0),
        scrollHandle: ChatListScrollViewHandle,
        @ViewBuilder content: () -> Content
    ) {
        self._barHeight = barHeight
        self._barBottom = barBottom
        self.scrollHandle = scrollHandle
        self.content = content()
    }

    func makeUIViewController(
        context: Context
    ) -> TopBarGuideHostController {
        let controller = TopBarGuideHostController()
        let barHeight = $barHeight
        controller.onBarHeightChange = { value in
            // 与舱宿主回报同一纪律：布局拍内同步写
            // SwiftUI 状态会撞「视图更新中改状态」，
            // 统一走下一拍、变化 >0.5 才写
            DispatchQueue.main.async {
                if abs(barHeight.wrappedValue - value) > 0.5 {
                    barHeight.wrappedValue = value
                }
            }
        }
        let barBottom = $barBottom
        controller.onBarBottomChange = { value in
            // §321：与实高回报同一纪律（下一拍写、
            // 变化 >0.5 才发）
            DispatchQueue.main.async {
                if abs(barBottom.wrappedValue - value) > 0.5 {
                    barBottom.wrappedValue = value
                }
            }
        }
        apply(to: controller)
        return controller
    }

    func updateUIViewController(
        _ controller: TopBarGuideHostController,
        context: Context
    ) {
        apply(to: controller)
    }

    /// 尺寸协商收口（§191 同判）：恒回提议尺寸——
    /// 本桥在 overlay 里只做全帧提议的透传层，顶簇
    /// 落位 100% 由控制器内约束（窗口顶锚）决定，
    /// SwiftUI 尺寸协商没有发言权
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: TopBarGuideHostController,
        context: Context
    ) -> CGSize? {
        if let width = proposal.width, width.isFinite,
           let height = proposal.height, height.isFinite {
            return CGSize(width: width, height: height)
        }
        return nil
    }

    /// 把当前 SwiftUI 侧状态（环境＋顶簇本体视图
    /// 值）刷进托管控制器（与舱宿主 apply 同式：
    /// 只做注入与赋值、不求值任何闭包）
    private func apply(to controller: TopBarGuideHostController) {
        let appState = appState
        let modelContext = modelContext
        let locale = locale
        controller.edgeScrollHandle = scrollHandle
        controller.topBarRoot = AnyView(
            content
                // 顶簇高只认内容自身：fixedSize 断外
                // 层提议（宿主定高约束的种子值/量测
                // 未及帧不许把内容压扁——舱宿主替身
                // 实证过的同坑，见 ComposerGuideHost-
                // Tests 的 fixedSize 注）
                .fixedSize(horizontal: false, vertical: true)
                // 顶簇实高实测：托管树内量、控制器据
                // 此定高并回报 ChatView 记账
                .onGeometryChange(
                    for: CGFloat.self
                ) { proxy in
                    proxy.size.height
                } action: { _, height in
                    controller.updateBarContentHeight(height)
                }
                .environment(appState)
                .environment(\.modelContext, modelContext)
                .environment(\.locale, locale)
                .boldTextMapping()
        )
    }
}

/// 透传根视图：只有顶簇宿主子视图的实帧接命中，
/// 本体空白处一律穿透到下层（消息列表）——与
/// ComposerPassthroughView 同式（帧未到时全放行，
/// 首拍前的亚拍级瞬态，顶簇随即实测就位）
private final class TopBarPassthroughView: UIView {
    /// 顶簇宿主视图（控制器装配时注入）：命中疆
    /// 域与闸门裁决一律按它的**活帧**当场现算
    ///（§214：布局拍缓存的窗口坐标快照帧作废——
    /// 位置补偿≠0 时顶簇被钉出本视图 bounds，point
    /// (inside:) 与缓存帧双双按旧坐标裁决、钮在
    /// 视觉位上点不响；活帧裁决使透传回到无状态
    /// 的通行形态，rig 证据见本线报告 §3）
    weak var barView: UIView?

    /// 入窗/换窗回调（锚重算的触发点之一；UIView-
    /// Controller 无 viewDidMoveToWindow，借根视
    /// 图的 didMoveToWindow 驱动，与舱宿主同式）
    var onMoveToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onMoveToWindow?()
    }

    /// 顶簇的窗口系活帧：未装配/未入窗/零高回 nil
    ///（闸门回退为放行，与旧口径一致）
    private func liveBarFrameInWindow() -> CGRect? {
        guard let barView, let window,
              barView.bounds.height > 0
        else { return nil }
        return barView.convert(barView.bounds, to: window)
    }

    override func point(
        inside point: CGPoint, with event: UIEvent?
    ) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }
        // 补偿把顶簇钉出本视图 bounds 时，疆域按活
        // 帧补认——否则命中下行在本视图边界即被挡
        // 下、整棵顶簇子树不被咨询（§214 主病灶）
        guard let frame = liveBarFrameInWindow(),
              let window
        else { return false }
        return frame.contains(convert(point, to: window))
    }

    override func hitTest(
        _ point: CGPoint, with event: UIEvent?
    ) -> UIView? {
        let hit = super.hitTest(point, with: event)
        guard let hit, hit !== self else { return nil }
        guard let frame = liveBarFrameInWindow(),
              let window
        else { return hit }
        let windowPoint = convert(point, to: window)
        return frame.contains(windowPoint) ? hit : nil
    }
}

/// 顶簇锚定托管控制器本体：只管顶簇宿主的钉位
/// （窗口顶安全区单常数）与实高定高/回报，不知
/// 业务页面。键盘与坞的任何信号都不订阅——脱钩
/// 是构造性的，不是运行时判断
final class TopBarGuideHostController: UIViewController {
    /// 顶簇根视图（桥注入；赋值即刷进顶簇宿主）
    var topBarRoot: AnyView? {
        didSet {
            if let topBarRoot {
                if !hasReceivedTopBarRoot {
                    hasReceivedTopBarRoot = true
                    // 取证探针（2026-11-20 白块诊断）：
                    // 内容链首达留痕——复发时与「首个
                    // 实测高」留痕对拍，分清断点在
                    // apply 前还是量测前；纯留证
                    ChatDiagTrace.record(
                        "顶簇内容链首达（topBarRoot 首刷）"
                    )
                }
                barHost.rootView = topBarRoot
            }
        }
    }
    /// 内容链首达闩（取证探针用；只记账、不参与
    /// 任何判定）
    private var hasReceivedTopBarRoot = false
    /// 顶簇实高变化回调（桥接回 SwiftUI 状态；本
    /// 类内先做等值守卫、变化 >0.5pt 才外发）
    var onBarHeightChange: ((CGFloat) -> Void)?
    /// §321：顶簇底缘（窗口坐标）变化回调——与实
    /// 高回调同一守卫口径；消费方＝ChatView 新面
    /// 列表顶 inset 喂入（顶簇真实底边单源）
    var onBarBottomChange: ((CGFloat) -> Void)?
    private var lastReportedBottom: CGFloat = -1

    private let barHost = UIHostingController<AnyView>(
        rootView: AnyView(EmptyView())
    )
    /// 内容链首个实测高闩（原 §327 背板入席闸门
    /// 的信号源，2026-11-22 背板退役后降为纯取
    /// 证）：实测高只认 updateBarContentHeight
    /// 的 >0 喂入（托管树内容真量到的第一笔）；
    /// reportBarHeight 报的是含种子 60 的记账
    /// 值、内容缺席时照样发，不作实测信号。单
    /// 向闩：首报即立、此后不回退——只喂 view-
    /// DidAppear 的内容链齐备度留痕，不驱动任
    /// 何可见层显隐（带面构造与契约见文件头）
    private var hasBarContentMeasure = false
    /// 顶边位置引导线：top 由 topGuideTopConstraint
    /// 的常量定位（syncTopConstant 唯一计算点）
    private let topGuide = UILayoutGuide()
    private var topGuideTopConstraint: NSLayoutConstraint!
    /// 顶簇定高约束：常量＝内容实测高（种子 60＝
    /// 顶栏单行高、首个量测拍即被实测覆盖；进展胶
    /// 囊出现/消失随量测跟进）
    private var barHeightConstraint: NSLayoutConstraint!
    private var barContentHeight: CGFloat = 60
    private var lastReportedHeight: CGFloat = -1
    /// §213 顶缘边缘效果注册：interaction 在 view-
    /// DidLoad 挂上顶簇宿主视图（edge=.top）；其
    /// scrollView 由 refreshEdgeBinding 按句柄现值
    /// 对齐（指针比对、未变即无操作）
    private let edgeInteraction =
        UIScrollEdgeElementContainerInteraction()
    private weak var boundEdgeScrollView: UIScrollView?
    /// §213：列表滚动视图句柄（桥注入；赋值即尝试
    /// 对齐绑定，列表本体未登记时留待离散事件/布局
    /// 拍的 syncTopConstant 同路刷新补绑）
    var edgeScrollHandle: ChatListScrollViewHandle? {
        didSet { refreshEdgeBinding() }
    }

    private func refreshEdgeBinding() {
        guard let scrollView = edgeScrollHandle?.scrollView,
              boundEdgeScrollView !== scrollView
        else { return }
        boundEdgeScrollView = scrollView
        edgeInteraction.scrollView = scrollView
    }

    /// 自述/测试定位口：顶簇宿主视图本体（pocket
    /// 的 UIKit 落点，§195 起 ScrollPocket 落点退役）
    var traceBarView: UIView { barHost.view }

    /// §213 自述/测试定位口：顶缘注册的 interaction
    var traceEdgeInteraction:
        UIScrollEdgeElementContainerInteraction {
        edgeInteraction
    }

    /// 装配契约自检（树内契约，见文件头）：返回
    /// 违例清单，空＝契约成立。检查两条：控制器
    /// 子视图恒只含顶簇宿主一层（带内无任何自绘
    /// 垫层——2026-11-22 带面构造的结构保证）、
    /// 宿主 safeAreaRegions 为空。视图未加载时
    /// 只回「未装配」一条（契约的适用面是装配完
    /// 成后）
    func assemblyContractViolations() -> [String] {
        guard isViewLoaded else { return ["控制器视图未加载"] }
        var violations: [String] = []
        let subviews = view.subviews
        guard subviews.count == 1,
              subviews.first === barHost.view
        else {
            violations.append(
                "控制器子视图应只含顶簇宿主一层，实见 "
                    + "\(subviews.count) 层"
                    + "（带内不许垫任何自绘层）"
            )
            return violations
        }
        if !barHost.safeAreaRegions.isEmpty {
            violations.append("顶簇宿主 safeAreaRegions 非空")
        }
        return violations
    }

    /// 契约断言（装配完成/首个实测高两拍调用）：
    /// 违例只在调试构建炸出——发布构建由测试侧
    /// 同口自检守住（TopBarBandFaceTests 契约组）
    private func assertAssemblyContract() {
        let violations = assemblyContractViolations()
        assert(
            violations.isEmpty,
            "TopBarGuideHost 装配契约违例："
                + violations.joined(separator: "；")
        )
    }

    /// 顶簇实高喂入点（托管树每次布局后经 onGeo-
    /// metryChange 上行）：定高＋回报——顶簇在树内
    /// 生长（进展胶囊出现）时本类未必有布局拍，回
    /// 报不能只靠 viewDidLayoutSubviews 兜底（与舱
    /// 宿主 updateBarFrame 同判）
    func updateBarContentHeight(_ height: CGFloat) {
        if height > 0, !hasBarContentMeasure {
            // 首个实测高：内容链已把真内容量进带
            // 内——在改高守卫之前记账：实测高恰与
            // 种子同值时也不能漏掉这一笔首报。本
            // 闩自 2026-11-22 起只作内容链取证
            // （带内已无背板可入席），同拍跑一次契
            // 约自检
            hasBarContentMeasure = true
            if isViewLoaded {
                assertAssemblyContract()
            }
            ChatDiagTrace.record(
                "顶簇首个实测高 \(height)"
            )
        }
        guard height > 0,
              abs(height - barContentHeight) > 0.5
        else { return }
        barContentHeight = height
        if isViewLoaded {
            barHeightConstraint?.constant = height
            view.setNeedsLayout()
        }
        reportBarHeight()
    }

    override func loadView() {
        let passthrough = TopBarPassthroughView()
        passthrough.onMoveToWindow = { [weak self] in
            self?.syncTopConstant()
        }
        view = passthrough
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // 顶簇宿主自管安全区（与舱宿主同纪律）：托
        // 管树的安全区归零——顶簇是自包含栈，不许
        // 宿主再按任何安全区给它派生一份内边距
        barHost.safeAreaRegions = []
        // 带面构造（2026-11-22 定版）：带内不垫任
        // 何自家层——顶簇宿主是控制器唯一子视图，
        // 带下透明、朦胧归 §213 系统边缘效果（见
        // 文件头带面构造节）
        addChild(barHost)
        barHost.view.backgroundColor = .clear
        barHost.view.translatesAutoresizingMaskIntoConstraints =
            false
        view.addSubview(barHost.view)
        barHost.didMove(toParent: self)
        // §214：透传疆域/闸门的活帧来源（命中间当
        // 场现算，不再经布局拍缓存）
        (view as? TopBarPassthroughView)?.barView =
            barHost.view
        // §213 + 大厂顶部朦胧位置校准：edgeInteraction 挂到顶簇
        // 顶部 44pt 锚定子视图（仅覆盖状态栏＋圆钮带，不再下探到身份
        // 胶囊底部 169pt），保持 view.subviews 仍只含 barHost.view 一层
        let edgeAnchor = UIView()
        edgeAnchor.backgroundColor = .clear
        edgeAnchor.isUserInteractionEnabled = false
        edgeAnchor.translatesAutoresizingMaskIntoConstraints = false
        barHost.view.addSubview(edgeAnchor)
        NSLayoutConstraint.activate([
            edgeAnchor.leadingAnchor.constraint(
                equalTo: barHost.view.leadingAnchor),
            edgeAnchor.trailingAnchor.constraint(
                equalTo: barHost.view.trailingAnchor),
            edgeAnchor.topAnchor.constraint(
                equalTo: barHost.view.topAnchor),
            edgeAnchor.heightAnchor.constraint(equalToConstant: 44),
        ])
        edgeInteraction.edge = .top
        edgeAnchor.addInteraction(edgeInteraction)
        refreshEdgeBinding()
        // 顶簇钉位：顶边恒钉自有 topGuide（单约束、
        // 常量由 syncTopConstant 按窗口实测重算）、
        // 左右贴本视图、高由实测常量定——本视图帧
        // 被 SwiftUI 再挪到哪，常量补偿后顶簇的窗
        // 口落点恒为窗口顶安全区
        view.addLayoutGuide(topGuide)
        topGuideTopConstraint = topGuide.topAnchor
            .constraint(equalTo: view.topAnchor, constant: 0)
        barHeightConstraint = barHost.view.heightAnchor
            .constraint(equalToConstant: barContentHeight)
        NSLayoutConstraint.activate([
            barHost.view.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            barHost.view.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            barHost.view.topAnchor.constraint(
                equalTo: topGuide.topAnchor),
            topGuide.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            topGuide.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            topGuide.heightAnchor.constraint(
                equalToConstant: 0),
            topGuideTopConstraint,
            barHeightConstraint,
        ])
        // 树内契约：装配完成即自检（带内单层/安全
        // 区纪律，见文件头契约节）
        assertAssemblyContract()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 取证探针（2026-11-20 白块诊断）：显形时
        // 内容链仍未齐＝故障帧的现场签名——留痕供
        // 下次复发一帧定断点（root 未达＝候选②空
        // 根停留、root 已达而实测未达＝量测回路）；
        // 齐备时不留、不扰常态账，纯留证不改行为
        if !hasReceivedTopBarRoot || !hasBarContentMeasure {
            ChatDiagTrace.record(
                "顶簇显形时内容链未齐：root达="
                    + "\(hasReceivedTopBarRoot) 实测高达="
                    + "\(hasBarContentMeasure)"
            )
        }
        // 显形重算（与舱宿主锚解析同触发口径）：切
        // 格往返/抽屉收合后本视图布局空间原点若变，
        // 常量在此对齐窗口真值
        syncTopConstant()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncTopConstant()
        // §214：透传判定帧不再于此缓存——闸门按顶
        // 簇活帧当场现算（TopBarPassthroughView）
        reportBarHeight()
        reportBarBottom()
    }

    /// §321：顶簇底缘回报——顶簇宿主活帧 convert
    /// 到窗口系取 maxY（与 §214 活帧裁决同式：不
    /// 经任何缓存/推算，安全区＋实高＋宿主落位偏
    /// 移全在这一帧里）。窗口未就绪/零高时不报
    /// （消费方留旧值/回落推算值，不悬空）
    private func reportBarBottom() {
        guard let window = view.window,
              barHost.view.bounds.height > 0
        else { return }
        let bottom = barHost.view.convert(
            barHost.view.bounds, to: window
        ).maxY
        guard bottom > 0,
              abs(bottom - lastReportedBottom) > 0.5
        else { return }
        lastReportedBottom = bottom
        onBarBottomChange?(bottom)
    }

    /// 顶边常量唯一计算点：topGuide 的 top 常量＝
    /// 窗口顶安全区（UIKit 窗口真值——152 真机自
    /// 述全帧恒 62，键盘/标签栏/页面传播状态一概
    /// 不读）− 本视图布局空间顶边（frame 原点沿父
    /// 链累加、transform 不计——抽屉平移不假补偿、
    /// 顶簇随前景同移）。逐布局拍调用（只读窗口
    /// 实测、无层级遍历），偏差 >0.5 才写。窗口未
    /// 就绪时保留上次常量——位置短暂陈旧但绝不悬
    /// 空，下个离散事件/布局拍即刷新
    private func syncTopConstant() {
        guard let window = view.window,
              let topGuideTopConstraint else { return }
        let constant = window.safeAreaInsets.top
            - Self.layoutSpaceMinY(of: view)
        if abs(topGuideTopConstraint.constant - constant)
            > 0.5 {
            topGuideTopConstraint.constant = constant
        }
        // §213：顶缘绑定同路刷新——本函数是入窗/显
        // 形/逐布局拍的公共点，列表本体登记晚于本控
        // 制器装配时在此补绑（指针比对、恒廉价）
        refreshEdgeBinding()
    }

    /// 顶簇实高回报（与舱顶回报同守卫口径）
    private func reportBarHeight() {
        guard barContentHeight > 0,
              abs(barContentHeight - lastReportedHeight)
                > 0.5
        else { return }
        lastReportedHeight = barContentHeight
        onBarHeightChange?(barContentHeight)
    }

    /// 视图在窗口布局空间的顶边（frame 原点沿父链
    /// 累加；transform 不进布局帧、天然不计）——
    /// 与 ComposerGuideHostController 同式
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
}
