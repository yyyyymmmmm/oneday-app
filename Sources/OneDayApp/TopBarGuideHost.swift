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
/// ## §200 顶带底衬（2026-11-13，用户 11:24 拍板）
/// 顶簇背后在本控制器视图层级内垫一层均匀系统磨
/// 砂（SystemBackdrop，.systemChromeMaterial）：
/// 覆盖窗口顶（状态栏带）→顶簇底，治内容上滚滑进
/// 状态栏带与时间/电量叠字、胶囊玻璃透字重影、汉
/// 堡钮压列表序号（用户 11:18 真机点名，同源于顶
/// 部浮层无底衬）。底衬顶边落点与顶簇同式补偿（窗
/// 口落点恒 0），底边随顶簇宿主底（进展胶囊生长同
/// 跟）；均匀材质、非 §173 渐进溶化（已作废、不许
/// 复活）；胶囊玻璃本体（§179 定式）一字不动、底
/// 衬只在其后。栏位落位/记账口径零改动。
struct TopBarGuideHost<Content: View>: UIViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    /// 顶簇实高的实测回报（host 在布局拍回写；
    /// ChatView 以窗口顶安全区＋此值作列表顶
    /// contentMargins，顶留位记账只剩这一处）
    @Binding var barHeight: CGFloat
    /// 顶簇本体（ChatView 的 headerBar＋进展胶囊）：
    /// 在 init 里由构建闭包求值成视图值——求值发生
    /// 在 ChatView 的 body 构建期，内部状态读数由
    /// 此归因到 ChatView（与 ComposerGuideHost
    /// content 同一条归因链）
    var content: Content

    init(
        barHeight: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        self._barHeight = barHeight
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
    /// 顶簇的窗口系实测帧（控制器逐次更新）
    var barFrameInWindow: CGRect = .zero

    /// 入窗/换窗回调（锚重算的触发点之一；UIView-
    /// Controller 无 viewDidMoveToWindow，借根视
    /// 图的 didMoveToWindow 驱动，与舱宿主同式）
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

/// 顶簇锚定托管控制器本体：只管顶簇宿主的钉位
/// （窗口顶安全区单常数）与实高定高/回报，不知
/// 业务页面。键盘与坞的任何信号都不订阅——脱钩
/// 是构造性的，不是运行时判断
final class TopBarGuideHostController: UIViewController {
    /// 顶簇根视图（桥注入；赋值即刷进顶簇宿主）
    var topBarRoot: AnyView? {
        didSet {
            if let topBarRoot {
                barHost.rootView = topBarRoot
            }
        }
    }
    /// 顶簇实高变化回调（桥接回 SwiftUI 状态；本
    /// 类内先做等值守卫、变化 >0.5pt 才外发）
    var onBarHeightChange: ((CGFloat) -> Void)?

    private let barHost = UIHostingController<AnyView>(
        rootView: AnyView(EmptyView())
    )
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
    /// §200 顶带底衬（系统材质）：本视图层级内最底
    /// 层；顶边常量由 syncTopConstant 与顶簇常量同
    /// 拍补偿（窗口落点恒为窗口顶），底边钉顶簇宿
    /// 主底——覆盖带＝窗口顶→顶簇底
    private let backdropView = SystemBackdrop.makeView()
    private var backdropTopConstraint: NSLayoutConstraint!

    /// 自述/测试定位口：顶簇宿主视图本体（pocket
    /// 的 UIKit 落点，§195 起 ScrollPocket 落点退役）
    var traceBarView: UIView { barHost.view }

    /// §200 自述/测试定位口：顶带底衬本体
    var traceBackdropView: UIView { backdropView }

    /// 顶簇实高喂入点（托管树每次布局后经 onGeo-
    /// metryChange 上行）：定高＋回报——顶簇在树内
    /// 生长（进展胶囊出现）时本类未必有布局拍，回
    /// 报不能只靠 viewDidLayoutSubviews 兜底（与舱
    /// 宿主 updateBarFrame 同判）
    func updateBarContentHeight(_ height: CGFloat) {
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
        addChild(barHost)
        barHost.view.backgroundColor = .clear
        barHost.view.translatesAutoresizingMaskIntoConstraints =
            false
        view.addSubview(barHost.view)
        barHost.didMove(toParent: self)
        // §200：顶带底衬入层——插在顶簇宿主之下（本
        // 视图子视图序最底）；左右贴本视图、底随顶
        // 簇宿主底、顶由 backdropTopConstraint 的常
        // 量定位（syncTopConstant 补偿至窗口顶）
        backdropView.translatesAutoresizingMaskIntoConstraints =
            false
        view.insertSubview(
            backdropView, belowSubview: barHost.view
        )
        backdropTopConstraint = backdropView.topAnchor
            .constraint(equalTo: view.topAnchor, constant: 0)
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
            backdropView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(
                equalTo: barHost.view.bottomAnchor),
            backdropTopConstraint,
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 显形重算（与舱宿主锚解析同触发口径）：切
        // 格往返/抽屉收合后本视图布局空间原点若变，
        // 常量在此对齐窗口真值
        syncTopConstant()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncTopConstant()
        // 透传判定帧同步：顶簇宿主的窗口系实帧（本
        // 拍约束已解、帧即落位结果）
        if let window = view.window {
            (view as? TopBarPassthroughView)?
                .barFrameInWindow = barHost.view.convert(
                    barHost.view.bounds, to: window
                )
        }
        reportBarHeight()
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
        // §200：底衬顶边同式补偿——常量＝−本视图布
        // 局空间顶边，底衬的窗口落点恒为窗口顶（0）：
        // 本视图帧被再挪到哪，底衬带的上缘恒贴屏顶、
        // 与顶簇落点补偿同一实测输入、同拍重算
        if let backdropTopConstraint {
            let backdropConstant =
                -Self.layoutSpaceMinY(of: view)
            if abs(backdropTopConstraint.constant
                    - backdropConstant) > 0.5 {
                backdropTopConstraint.constant =
                    backdropConstant
            }
        }
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
