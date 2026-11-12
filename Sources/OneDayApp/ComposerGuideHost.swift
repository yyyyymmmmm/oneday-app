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
    /// 际落位 100% 由控制器内约束（引导线＋地板钳制）
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

/// 引导线托管控制器本体：只管舱宿主的钉位（引导线＋
/// 地板钳制）与舱顶实测回报，不知业务页面。宿主全高
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
    private var bottomConstraint: NSLayoutConstraint!
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
            composerHost.view.topAnchor.constraint(
                equalTo: view.topAnchor),
            bottomConstraint,
        ])
        if barFrameInWindow.height > 0 {
            (view as? ComposerPassthroughView)?
                .barFrameInWindow = barFrameInWindow
        }
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
        logNegotiationIfChanged()
    }

    /// §192 量测（控制器侧对账，值变才记）：本视图
    /// 界 × 宿主视图帧 × 宿主在两档目标高下的拟合
    /// 回报 × 本视图 Auto Layout 拟合回报——若 Swift-
    /// UI 协商之外另有通道把 1030 喂给落位（平台视
    /// 图 fitting／宿主理想高传播），必在此露头：
    /// hostFit@3000 给的是内栈在近未定提议下的理想
    /// 高、sysFit@729 给的是约束系（引导线钉底）
    /// 在区域高提议下的解
    private var lastNegotLine = ""
    private func logNegotiationIfChanged() {
        let width = view.bounds.width
        guard width > 0, composerHost.view.superview != nil
        else { return }
        let hostFit729 = composerHost.sizeThatFits(
            in: CGSize(width: width, height: 729)
        )
        let hostFitTall = composerHost.sizeThatFits(
            in: CGSize(width: width, height: 3000)
        )
        let sysFit729 = view.systemLayoutSizeFitting(
            CGSize(width: width, height: 729)
        )
        // 拆段拼接：整串插值链会触发类型推断超时
        // （CI 实证 43331533247），逐段成行再 join
        let parts = [
            "bounds=" + BarsTraceFormat.size(view.bounds.size),
            "hostView=" + BarsTraceFormat.size(
                composerHost.view.frame.size
            ),
            "hostFit@729=" + BarsTraceFormat.size(hostFit729),
            "hostFit@3000=" + BarsTraceFormat.size(hostFitTall),
            "sysFit@729=" + BarsTraceFormat.size(sysFit729),
        ]
        let line = parts.joined(separator: " ")
        guard line != lastNegotLine else { return }
        lastNegotLine = line
        BarsGeometryTrace.noteProbe("vcLayout", line)
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
