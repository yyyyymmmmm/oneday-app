import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit

/// 抽屉容器（§156，用户 2026-11-11 20:58 亲递方案定
/// 调）：外层容器换 UIKit，现有 SwiftUI 页面与底栏
/// 一字不动。取代 0.17.0 的 SwiftUI 覆盖式 Drawer-
/// Shell——旧形态是抽屉自左滑入**盖在**静止内容之
/// 上（蒙层压暗）；新形态照用户方案与 Muse 本体
/// 形态：侧栏在后静止、**完整主页面整体右移**露出
/// 侧栏，右侧留一条明亮窄条，点窄条/左拖关闭，第
/// 一版不缩放。
///
/// 结构（两个长期存在的 UIHostingController，开关
/// 抽屉从不重建——聊天滚动位/输入草稿/导航栈/生成
/// 中回复全靠它保住）：
/// - 底层 drawerHost：DrawerView，宽 travel、静止；
/// - 前景 wrapper（阴影层）→ clip（圆角裁切层）→
///   contentHost（现有 TabView）：主页面恒按容器全
///   尺寸布局，位移只写 wrapper.transform 的
///   translationX，拖动期不改任何宽高约束、不逐帧
///   动安全区（0.6.1/0.17.0 两代「外层包裹扰动
///   TabView 安全区、底栏下沉」的病根正是变换/量测
///   加在 TabView 本人身上；本代变换只落在本容器自
///   有的普通 UIView 上，TabView 在宿主内仍是零修
///   饰根级安放）。
/// - 阴影与裁切分层：wrapper 只挂阴影（DrawerMotion
///   §202 定值 radius 18/x −4、alpha 随 progress、峰
///   值 0.22）、clip 只管圆角裁切（DrawerMotion.
///   cornerRadius 一步到位口径：progress>0.02 即
///   54.5pt——§202 对 Muse 新参照图量测拟合定值，
///   出处见 DrawerMotion 常量注；本注释早年写的 28pt
///   是更旧一版定值、早已作废），阴影不被裁、圆角不
///   带影；开态 clip 帧另按 DrawerMotion.vertical-
///   Inset 纵向内嵌（§202 K1）、整卡浮置。
/// - 强黑蒙层整套退役（覆盖形态的分离手段）；分离
///   感由页卡圆角＋柔影＋窄条明亮承担。
///
/// 环境显式注入（方案点名）：宿主不继承桥的环境——
/// AppState、modelContext、locale、粗体映射在本桥
/// 读出后逐项写进两个宿主的根视图；.id(appLanguage)
/// 的整树重建在桥的上层（OneDayApp 根），切语言时
/// 本桥整体重建、宿主随之新建，口径与旧壳一致。
/// scenePhase/reduceTransparency/深色等走宿主 trait
/// 自动派生，不手工搬。
///
/// 手势（方案清单逐项）：
/// - 关闭态：左缘 24pt 热区（OneDayMetrics.drawer-
///   EdgeZone）UIPan 开抽屉；对系统返回手势让行——
///   本手势 require 系统边缘返回手势先失败（二级页
///   返回优先、根页返回手势即刻失败不拖开抽屉）。
/// - 打开态：前景窄条 UIPan 左拖跟手关＋点按关；
///   内容本体交互关闭（防穿透）；抽屉面上不挂横拖
///   手势，纵向滚动天然不被抢（旧壳抽屉面共用拖拽
///   手势的口径就此变更）。
/// - 跟手：DrawerMotion 方向锁定（10pt/1.5 倍）达
///   成前不写位移、纵向主导即取消本手势；写入走
///   followedOffset（扣锁定段＋橡皮筋），判定走
///   settleOpens（动量投影以速度×DrawerSpring-
///   Timing.settleProjectionInterval 近似）。
/// - 动画中再拖：停 animator 并从 presentation 层
///   当前 tx 接管，无跳变帧。
/// - 归位动画：UIViewPropertyAnimator＋UISpring-
///   TimingParameters（参数出 OneDayCore.Drawer-
///   SpringTiming，与 MotionTokens.drawerSpring 的
///   response 0.34/ζ 0.86 换算等价、单测回算钉死）；
///   松手速度按相对位移换算作初速交接；Reduce
///   Motion 时瞬时归位。
/// - 打开先收键盘（旧纪律沿用）；VoiceOver：开态
///   抽屉出 a11y 树、内容退出，关态反之，切换时发
///   screenChanged（开→抽屉面、关→内容面；回触发
///   钮本体的精确落点真机验）。
///
/// 语义开合：AppState.drawerPresented 仍是各入口的
/// 写入面——ContentView 在 body 里读它并以 presented
/// 入参喂本桥（观察在 ContentView 层成立），桥在更
/// 新时与容器语义对账执行；容器侧手势/点按改变开
/// 合经 onPresentedChange 回写同一值， guard 防回环。
struct DrawerContainer<Content: View>: UIViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selection: ContentView.MainTab
    /// 语义开合（ContentView 以 appState.drawer-
    /// Presented 喂入；本桥据此与容器对账）
    var presented: Bool
    /// 抽屉「管理全部对话」透传（0.18.0 沿用）
    var onManageAll: () -> Void
    /// 抽屉频道行透传（0.36.29 沿用）
    var onOpenChannel: () -> Void
    @ViewBuilder var content: () -> Content

    func makeUIViewController(
        context: Context
    ) -> DrawerContainerController {
        let controller = DrawerContainerController()
        let appState = appState
        controller.onPresentedChange = { newValue in
            if appState.drawerPresented != newValue {
                appState.drawerPresented = newValue
            }
        }
        apply(to: controller)
        controller.setDrawer(presented, animated: false)
        return controller
    }

    func updateUIViewController(
        _ controller: DrawerContainerController, context: Context
    ) {
        apply(to: controller)
        if controller.semanticPresented != presented {
            controller.setDrawer(presented, animated: true)
        }
    }

    /// 把当前 SwiftUI 侧状态（环境、回调、内容）刷进
    /// 容器：两个宿主的根视图以同型新值更新（SwiftUI
    /// 按身份 diff、宿主与页内 @State 不重建）；抽屉
    /// 宽随容器 travel 变时由容器回调本处 builder 重建
    private func apply(to controller: DrawerContainerController) {
        let appState = appState
        let modelContext = modelContext
        let locale = locale
        controller.reduceMotion = reduceMotion
        controller.drawerBuilder = { width in
            AnyView(
                DrawerView(
                    width: width,
                    currentTab: selection,
                    onSelectTab: { selection = $0 },
                    onClose: { controller.setDrawer(false, animated: true) },
                    onManageAll: onManageAll,
                    onOpenChannel: { _ in onOpenChannel() }
                )
                .environment(appState)
                .environment(\.modelContext, modelContext)
                .environment(\.locale, locale)
                .boldTextMapping()
            )
        }
        controller.contentRoot = AnyView(
            content()
                .environment(appState)
                .environment(\.modelContext, modelContext)
                .environment(\.locale, locale)
                .boldTextMapping()
        )
    }
}

/// UIKit 抽屉容器本体（职责见 DrawerContainer 文件
/// 注）：只管两层宿主的安放、位移变换与手势/动画，
/// 不知道任何业务页面
final class DrawerContainerController: UIViewController,
    UIGestureRecognizerDelegate
{
    /// 开合语义（与 AppState.drawerPresented 对账的
    /// 容器侧副本；setDrawer 是唯一写口）
    private(set) var semanticPresented = false
    /// 推开量（min(容器宽×0.79, 400)，方案起点值＝
    /// 现行壳层 §30 量测口径，未随令牌 0.75/340 改）
    private(set) var travel: CGFloat = 0
    /// Reduce Motion（桥注入；true 时归位瞬时）
    var reduceMotion = false
    /// 容器开合变化回写（桥接回 AppState）
    var onPresentedChange: ((Bool) -> Void)?
    /// 抽屉根视图 builder（桥注入；travel 变化时容器
    /// 以新宽重取根视图，闭包内回调恒取最新桥状态）
    var drawerBuilder: ((CGFloat) -> AnyView)? {
        didSet { rebuildDrawerRoot() }
    }
    /// 内容根视图（桥注入；赋值即刷进内容宿主）
    var contentRoot: AnyView? {
        didSet {
            if let contentRoot {
                contentHost.rootView = contentRoot
            }
        }
    }

    private let drawerHost = UIHostingController<AnyView>(
        rootView: AnyView(EmptyView())
    )
    private let contentHost = UIHostingController<AnyView>(
        rootView: AnyView(EmptyView())
    )
    /// 前景阴影层（只挂阴影、不裁切）
    private let foreground = UIView()
    /// 前景裁切层（只管圆角、不挂阴影）
    private let clipView = UIView()
    /// 关闭态左缘热区（24pt；开态隐藏不挡抽屉）
    private let edgeView = UIView()

    /// 当前呈现位移（0…travel，橡皮筋段可越界；跟手
    /// 与动画的唯一事实源，与旧壳 S1 口径同构）
    private var offset: CGFloat = 0
    private var animator: UIViewPropertyAnimator?
    /// 手势会话：接管起点位移＋锁定段（nil＝未锁定）
    private var dragStartOffset: CGFloat = 0
    private var dragLockTranslation: CGFloat?

    private lazy var edgePan: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(
            target: self, action: #selector(handlePan(_:))
        )
        recognizer.delegate = self
        return recognizer
    }()
    private lazy var stripPan: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(
            target: self, action: #selector(handlePan(_:))
        )
        recognizer.delegate = self
        recognizer.isEnabled = false
        return recognizer
    }()
    private lazy var stripTap: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(
            target: self, action: #selector(handleStripTap)
        )
        recognizer.isEnabled = false
        return recognizer
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        // 容器底色＝页面底：抽屉材质（thinMaterial）
        // 向下采样到的就是它，取 Palette.pageBG 与旧
        // 覆盖形态下抽屉糊到的内容底色同族
        view.backgroundColor = UIColor(Palette.pageBG)

        addChild(drawerHost)
        drawerHost.view.backgroundColor = .clear
        view.addSubview(drawerHost.view)
        drawerHost.didMove(toParent: self)
        drawerHost.view.isHidden = true

        foreground.layer.shadowColor = UIColor(Palette.shadowBase).cgColor
        foreground.layer.shadowRadius = DrawerMotion.shadowRadius
        foreground.layer.shadowOffset = CGSize(
            width: DrawerMotion.shadowX, height: 0
        )
        foreground.layer.shadowOpacity = 0
        view.addSubview(foreground)
        clipView.clipsToBounds = true
        clipView.layer.cornerCurve = .continuous
        foreground.addSubview(clipView)
        addChild(contentHost)
        contentHost.view.backgroundColor = .clear
        clipView.addSubview(contentHost.view)
        contentHost.didMove(toParent: self)
        foreground.addGestureRecognizer(stripPan)
        foreground.addGestureRecognizer(stripTap)

        edgeView.backgroundColor = .clear
        view.addSubview(edgeView)
        edgeView.addGestureRecognizer(edgePan)

        applyOffset(0)
    }

    /// 当前 progress 的前景裁切几何：圆角半径＋纵向内
    /// 嵌帧（§202 K1/K2）。layout 与 applyOffset 两写点
    /// 共用这一处派生——§182.2 的教训是阴影路径双写必
    /// 须同拍同口径，几何再多一个事实源就会打架：帧＝
    /// 前景 bounds 纵向内嵌 verticalInset(progress)
    /// （合态 0、开态满值、随 progress 线性行进）、半
    /// 径＝cornerRadius(progress)（一步到位、K4 不插值）
    private func clipGeometry(progress: CGFloat)
        -> (frame: CGRect, radius: CGFloat)
    {
        let radius = DrawerMotion.cornerRadius(progress: progress)
        let inset = DrawerMotion.verticalInset(progress: progress)
        let frame = foreground.bounds.insetBy(dx: 0, dy: inset)
        return (frame, radius)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let newTravel = min(bounds.width * 0.79, 400)
        let travelChanged = newTravel != travel
        travel = newTravel
        drawerHost.view.frame = CGRect(
            x: 0, y: 0, width: travel, height: bounds.height
        )
        // 前景是全容器唯一带 transform 的视图：transform
        // 非 identity 时 frame 未定义（Apple 文档明文），
        // 布局只准以 bounds＋center 写「未变换几何」、位
        // 移全部由 transform 承担。旧写法在此以 frame 重
        // 设——animator 已把 model transform 承诺到目标
        // 值，frame setter 按当前 transform 反解 center，
        // 一次布局往返就把视觉位置补偿回原位（0.50.18
        // 真机抽屉打不开的定案主因：动画只剩布局触发前
        // 约 30pt 的呈现残移，见诊断报告与回归测试
        // testAnimatedOpenSurvivesMidFlightResize）
        foreground.bounds = CGRect(origin: .zero, size: bounds.size)
        foreground.center = CGPoint(x: bounds.midX, y: bounds.midY)
        // §182.2 阴影路径跟随圆角：shadowPath 必须与
        // clipView 的圆角半径一致，否则直角矩形阴影会
        // 在圆角区域外露、视觉上圆角「不显」（用户真机
        // 报无弧的定案主因）。§202 起帧与路径同走
        // clipGeometry 单点派生（帧含纵向内嵌）。进度读
        // 当前 offset 实算，不读语义 presented（布局期
        // 可能先于手势/动画）
        let currentProgress = DrawerMotion.progress(
            offset: offset, travel: travel
        )
        let geometry = clipGeometry(progress: currentProgress)
        foreground.layer.shadowPath = UIBezierPath(
            roundedRect: geometry.frame,
            cornerRadius: geometry.radius
        ).cgPath
        clipView.frame = geometry.frame
        contentHost.view.frame = clipView.bounds
        edgeView.frame = CGRect(
            x: 0, y: 0,
            width: OneDayMetrics.drawerEdgeZone,
            height: bounds.height
        )
        if travelChanged {
            rebuildDrawerRoot()
            // 旋转/尺寸变：开态无拖无动画时位移跟到新
            // travel（主页面仍完整露出同一比例）
            if semanticPresented, animator == nil,
               dragLockTranslation == nil
            {
                offset = travel
                applyOffset(offset)
            }
        }
    }

    private func rebuildDrawerRoot() {
        guard travel > 0, let drawerBuilder else { return }
        drawerHost.rootView = drawerBuilder(travel)
    }

    // MARK: - 位移呈现

    /// 位移唯一呈现口：只写前景 transform（主页面布
    /// 局尺寸恒不变）＋圆角/阴影/命中/a11y 派生
    private func applyOffset(_ newOffset: CGFloat) {
        offset = newOffset
        foreground.transform = CGAffineTransform(
            translationX: newOffset, y: 0
        )
        let progress = DrawerMotion.progress(
            offset: newOffset, travel: travel
        )
        let geometry = clipGeometry(progress: progress)
        clipView.layer.cornerRadius = geometry.radius
        clipView.frame = geometry.frame
        contentHost.view.frame = clipView.bounds
        // §182.2 阴影路径跟随圆角；§202 起路径矩形＝内
        // 缩后的 clip 帧（与布局期同走 clipGeometry 派生）
        foreground.layer.shadowPath = UIBezierPath(
            roundedRect: geometry.frame,
            cornerRadius: geometry.radius
        ).cgPath
        foreground.layer.shadowOpacity = Float(
            DrawerMotion.shadowOpacity(progress: progress)
        )
        // 穿透防护：只要离开合位，内容本体不接触摸
        // （窄条的点/拖由前景手势承接）；全合位恢复。
        // §186.8 补修（Codex 异源复核）：归位动画在途
        // 时同样保持关闭——animator 的动画闭包在启动
        // 拍即以目标值调本函数（model 值同步落位），
        // 若只看 offset，关闭动画起始帧内容就已可点，
        // 而呈现层还在移动、舱的透传判定帧是布局快照
        // （transform 位移不触发 preference 更新）——
        // 点会落进正在移动的舱/列表。落定复位在
        // finishSettle（animator 已清零后按 offset
        // 终值重断言）；跟手拖动期 animator 恒为 nil
        // （接管时先停 animator），本条不改变拖动态
        // 语义（offset 本身即呈现事实）
        contentHost.view.isUserInteractionEnabled =
            newOffset <= 0 && animator == nil
        edgeView.isHidden = semanticPresented || newOffset > 0
    }

    // MARK: - 开合

    /// 开合统一走口：语义先行回写、动画随后；打开必
    /// 先收键盘（旧纪律）；Reduce Motion/无宽时瞬时
    func setDrawer(
        _ open: Bool, animated: Bool, velocityX: CGFloat = 0
    ) {
        if open {
            resignKeyboard()
            drawerHost.view.isHidden = false
        }
        semanticPresented = open
        onPresentedChange?(open)
        stripPan.isEnabled = open
        stripTap.isEnabled = open
        edgePan.isEnabled = !open
        let target = open ? travel : 0
        stopAnimatorCapturingPresentation()
        guard animated, !reduceMotion, travel > 0 else {
            applyOffset(target)
            finishSettle(open: open)
            return
        }
        let delta = target - offset
        var initialVelocity = CGVector.zero
        if abs(delta) > 1, abs(velocityX) > 1 {
            // UISpringTimingParameters 的初速以「每秒
            // 走完全程的比例」计：手势速度按相对位移
            // 换算，方向与目标同向才交接
            let relative = velocityX / delta
            if relative > 0 {
                initialVelocity = CGVector(dx: relative, dy: 0)
            }
        }
        let timing = UISpringTimingParameters(
            mass: 1,
            stiffness: DrawerSpringTiming.stiffness,
            damping: DrawerSpringTiming.damping,
            initialVelocity: initialVelocity
        )
        let animator = UIViewPropertyAnimator(
            duration: 0, timingParameters: timing
        )
        animator.addAnimations { [weak self] in
            self?.applyOffset(target)
        }
        animator.addCompletion { [weak self] position in
            guard let self, position == .end else { return }
            self.animator = nil
            self.finishSettle(open: open)
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func finishSettle(open: Bool) {
        if !open {
            drawerHost.view.isHidden = true
        }
        // §186.8：归位落定的交互复位——动画路径下
        // applyOffset 因 animator 在途恒置关闭，落定
        // （完成回调已先清 animator／瞬时路径本就无
        // animator）在此按 offset 终值放行；开态终值
        // >0、恒保持关闭
        contentHost.view.isUserInteractionEnabled = offset <= 0
        syncAccessibility(open: open)
    }

    /// VoiceOver 树切换：开态只留抽屉、关态只留内容；
    /// 焦点引导发 screenChanged（开→抽屉面、关→内容
    /// 面近似回触发侧，精确落点真机验）
    private func syncAccessibility(open: Bool) {
        drawerHost.view.accessibilityElementsHidden = !open
        contentHost.view.accessibilityElementsHidden = open
        UIAccessibility.post(
            notification: .screenChanged,
            argument: open ? drawerHost.view : contentHost.view
        )
    }

    private func resignKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// 动画中再拖/再令：停 animator 并把 presentation
    /// 层的当前 tx 收回事实源——接管无跳变帧（S7 桥
    /// 接在 UIKit 侧的等价落法）
    private func stopAnimatorCapturingPresentation() {
        guard let animator, animator.isRunning else {
            self.animator = nil
            return
        }
        animator.pauseAnimation()
        if let presentation = foreground.layer.presentation() {
            offset = presentation.transform.m41
        }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .current)
        self.animator = nil
        foreground.transform = CGAffineTransform(
            translationX: offset, y: 0
        )
    }

    // MARK: - 手势

    @objc private func handleStripTap() {
        setDrawer(false, animated: true)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        switch recognizer.state {
        case .began:
            stopAnimatorCapturingPresentation()
            dragStartOffset = offset
            dragLockTranslation = nil
            if recognizer === edgePan {
                // 预挂载等价：抽屉树在锁定达成前先可见
                // （宿主本体恒在、此处只揭隐藏）
                drawerHost.view.isHidden = false
            }
        case .changed:
            if dragLockTranslation == nil {
                let dx = translation.x
                let dy = translation.y
                guard DrawerMotion.isDirectionLocked(dx: dx, dy: dy)
                else {
                    // 纵向主导过锁定距：本手势让行（其
                    // 下滚动面接不接得住这一下真机验，
                    // 与旧壳 SwiftUI 口径同界）
                    if abs(dy) >= DrawerMotion.directionLockDistance,
                       abs(dy) > abs(dx)
                    {
                        recognizer.state = .cancelled
                    }
                    return
                }
                dragLockTranslation = dx
                dragStartOffset = offset
            }
            let target = DrawerMotion.followedOffset(
                startOffset: dragStartOffset,
                translation: translation.x,
                lockTranslation: dragLockTranslation ?? 0,
                travel: travel
            )
            applyOffset(target)
        case .ended:
            let velocity = recognizer.velocity(in: view)
            let opens: Bool
            if dragLockTranslation != nil {
                opens = DrawerMotion.settleOpens(
                    currentOffset: offset,
                    startOffset: dragStartOffset,
                    predictedExtra: velocity.x
                        * DrawerSpringTiming.settleProjectionInterval,
                    velocityX: velocity.x,
                    travel: travel
                )
            } else {
                opens = semanticPresented
            }
            dragLockTranslation = nil
            setDrawer(opens, animated: true, velocityX: velocity.x)
        case .cancelled, .failed:
            dragLockTranslation = nil
            setDrawer(semanticPresented, animated: true)
        default:
            break
        }
    }

    /// 手势仲裁：左缘手势须等系统边缘返回手势先失
    /// 败（二级页返回优先）；窄条手势与点按同属前景
    /// 时点按须等拖拽失败（拖动不误触发点按关）
    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRequireFailureOf other: UIGestureRecognizer
    ) -> Bool {
        if recognizer === edgePan {
            return other is UIScreenEdgePanGestureRecognizer
        }
        if recognizer === stripTap {
            return other === stripPan
        }
        return false
    }

    /// 前景手势只在开态启用（stripPan/stripTap 的
    /// isEnabled 随语义切换）；左缘手势与内容滚动的
    /// 并行关系走系统默认（不声明 simultaneously，
    /// 保方向锁定语义）
    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
