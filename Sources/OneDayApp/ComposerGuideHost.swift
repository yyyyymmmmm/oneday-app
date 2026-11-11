import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit

/// 输入舱引导线托管（§178，用户 2026-11-12 03:02 亲点
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
///   伪、双计教训记 §178）。
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
///   环境——AppState、modelContext、locale、reduce-
///   Motion、dynamicTypeSize 在本桥读出后逐项写进舱宿
///   主根视图，粗体映射同挂；trait 类（深色／字号）走
///   控制器层级自动派生。
/// - 贴底四路（§124/§135/§176）：bottomBar 整栈与回底
///   钮本体一字不动、ScrollViewReader 与列表同树不变，
///   scrollToBottom 仍经原 proxy 直达；变的只有留位来
///   源（安全区→实测 contentMargins），距底读数出自滚
///   动几何、对留位来源无感——四路判定与协调器零改动。
struct ComposerGuideHost<Content: View>: UIViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 舱顶→窗口底距离的实测回报（host 在布局拍回写；
    /// ChatView 以此＋spacingS 作列表底 contentMargins）
    @Binding var bottomSpace: CGFloat
    /// 舱本体（ChatView 的 bottomBar 整栈，构建闭包在
    /// ChatView 上下文求值、状态盒与 ChatView 同源）
    @ViewBuilder var content: () -> Content

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

    /// 把当前 SwiftUI 侧状态（环境＋舱本体）刷进托管
    /// 控制器：舱宿主根视图以同型新值更新（SwiftUI 按
    /// 身份 diff、舱内 @State 不重建，与 DrawerContainer
    /// 内容宿主同机制）
    private func apply(to controller: ComposerGuideHostController) {
        let appState = appState
        let modelContext = modelContext
        let locale = locale
        controller.composerRoot = AnyView(
            content()
                .environment(appState)
                .environment(\.modelContext, modelContext)
                .environment(\.locale, locale)
                .environment(
                    \.accessibilityReduceMotion, reduceMotion)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
                .boldTextMapping()
        )
    }
}

/// 透传根视图：只有舱宿主子视图的实帧接命中，本体空
/// 白处一律穿透到下层（消息列表）——列表的点空白收键
/// 盘、滚动手势的作用域不因本件盖了一层全帧视图而缩
private final class ComposerPassthroughView: UIView {
    override func hitTest(
        _ point: CGPoint, with event: UIEvent?
    ) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// 引导线托管控制器本体：只管舱宿主的钉位（引导线＋
/// 地板钳制）与舱顶实测回报，不知业务页面
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
    private var bottomConstraint: NSLayoutConstraint!
    private var lastReportedSpace: CGFloat = -1

    override func loadView() {
        view = ComposerPassthroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // 舱宿主自管安全区：托管树的安全区归零——舱是
        // 自包含栈（内边距全在内容里，见 inputBar 注），
        // 不许宿主再按窗口安全区给它派生一份（双计防线，
        // 配件核查报告第 6 条同坑）
        composerHost.safeAreaRegions = []
        // 高度走托管内容的理想高（舱内 fixedSize 断环是
        // 既有口径，理想高即内容高）
        composerHost.sizingOptions = [.intrinsicContentSize]
        addChild(composerHost)
        composerHost.view.backgroundColor = .clear
        composerHost.view.translatesAutoresizingMaskIntoConstraints =
            false
        view.addSubview(composerHost.view)
        composerHost.didMove(toParent: self)
        bottomConstraint = composerHost.view.bottomAnchor
            .constraint(
                equalTo: view.keyboardLayoutGuide.topAnchor)
        NSLayoutConstraint.activate([
            composerHost.view.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            composerHost.view.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            bottomConstraint,
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 地板钳制：舱底目标＝min(引导线顶, 视图底边)——
        // 键盘升起跟引导线走、落下停在视图底边（＝坞
        // 顶）；常数逐拍按当前帧重算，交互式收键盘拖到
        // 半程时引导线与地板的交接连续无跳。常数只在偏
        // 差 >0.25 时写（布局拍内不重入 layoutIfNeeded，
        // 新常数随下一拍生效——地板交接只发生在近静止
        // 段，一拍延迟不可见）
        let guideTop = view.keyboardLayoutGuide.layoutFrame.minY
        let target = min(guideTop, view.bounds.height)
        let constant = target - guideTop
        if abs(bottomConstraint.constant - constant) > 0.25 {
            bottomConstraint.constant = constant
        }
        reportBottomSpace()
    }

    /// 舱顶实测回报：舱帧换算到窗口坐标，报「舱顶→窗
    /// 口底」距离——页帧在键盘态如何伸缩都不进公式，
    /// ChatView 侧只做＋spacingS 一步
    private func reportBottomSpace() {
        guard let window = view.window,
              composerHost.view.bounds.height > 0
        else { return }
        let barFrame = composerHost.view.convert(
            composerHost.view.bounds, to: window)
        let space = window.bounds.height - barFrame.minY
        guard abs(space - lastReportedSpace) > 0.5 else { return }
        lastReportedSpace = space
        onBottomSpaceChange?(space)
    }
}
