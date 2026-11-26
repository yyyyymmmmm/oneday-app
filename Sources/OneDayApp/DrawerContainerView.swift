import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit

/// 桥 apply 的输入指纹（§365 D1 等值守卫）：两个
/// 宿主根视图与四回调的全部造料——环境对象身份
/// （AppState/ModelContext）＋locale 标识＋Reduce
/// Motion＋当前选择页签。指纹不变即桥两侧产物必
/// 同，整次 apply 可跳过。onOpenChannel 不入指纹
/// （只写 ContentView 的 @State 身份存储、新旧闭
/// 包写同一存储，见 §365.3）
struct DrawerBridgeFingerprint: Equatable {
    var appState: ObjectIdentifier
    var modelContext: ObjectIdentifier
    var localeIdentifier: String
    var reduceMotion: Bool
    var selection: ContentView.MainTab
}

/// 抽屉容器（§156，用户 2026-11-11 20:58 亲递方案定
/// 调）：外层容器换 UIKit，现有 SwiftUI 页面与底栏
/// 一字不动。取代 0.17.0 的 SwiftUI 覆盖式 Drawer-
/// Shell——旧形态是抽屉自左滑入**盖在**静止内容之
/// 上（蒙层压暗）；新形态照用户方案与 Muse 本体
/// 形态：侧栏在后静止、**完整主页面整体右移**露出
/// 侧栏，右侧留一条明亮窄条，点窄条/左拖关闭，第
/// 一版不缩放。
/// §313（第 78 条＋横扫 A-01/A-02/A-21）在此形态上
/// 做变换对齐与内部收敛：抽屉层改与主面锁步同行、
/// travel 改宽×0.75、弹簧定版（其值 §322 已重定
/// 版、慢阻尼旧值作废）、深色阴影归零；位移单源、
/// 阴影单写、几何/弹簧单源逐项见
/// 下结构注（宿主 safeAreaRegions 的 §313 清零已
/// 由 §318 订正为分界口径、见彼段）。
///
/// 结构（两个长期存在的 UIHostingController，开关
/// 抽屉从不重建——聊天滚动位/输入草稿/导航栈/生成
/// 中回复全靠它保住）：
/// - 底层 drawerHost：DrawerView，宽 travel；§313
///   起与前景锁步同行（第 78 条 D1）——关闭态整体
///   左移一个 travel 藏于主面之后（offset −travel），
///   开合时只写它自己的 transform.translationX＝
///   offset − travel，与前景构成同一刚性平移（Muse
///   录屏五帧拟合与 travel 全等，prep §2.3）。§156
///   初版「抽屉静止、前景右移露出（帘幕式）」就此
///   变更，抽屉根视图重建时机与帧口径（x 0/宽
///   travel）不变。
/// - 前景 wrapper → clip（圆角裁切层）→ contentHost
///   （现有 TabView）：主页面恒按容器全尺寸布局，
///   位移只写 wrapper.transform 的 translationX，
///   拖动期不改任何宽高约束、不逐帧动安全区
///   （0.6.1/0.17.0 两代「外层包裹扰动 TabView 安全
///   区、底栏下沉」的病根正是变换/量测加在 TabView
///   本人身上；本代变换只落在本容器自有的普通
///   UIView 上，TabView 在宿主内仍是零修饰根级
///   安放）。容器唯一位移事实源是 offset 一值：前景/
///   抽屉两层 transform 与全部呈现派生只在
///   applyOffset 一处写（A-01 收敛）。§323 起
///   clip/内容宿主两帧同归本口唯一写点（layout
///   不再直写帧、只更新未变换几何事实后经本口
///   重派生），呈现派生本体立 DrawerMotion 为
///   唯一通道（裁切几何迁入 DrawerMotion.clip-
///   Geometry）——收口包单写点治理，学 Simplenote
///   单 animator 单写点。
/// - 阴影与裁切同层（§313 A-01 收敛）：柔影改挂
///   clip 本人（CALayer 语义：阴影按本层 alpha 形
///   状投射、clipsToBounds 只裁子层——阴影在裁切
///   区域之外、不被自裁），shadowPath 不再手写
///   （§182.2 的路径跟随圆角改由图层形状自动成
///   影，layout/applyOffset 双写点整删）；圆角仍走
///   DrawerMotion.cornerRadius 一步到位口径
///   （progress>0.02 即 54.5pt——§202 对 Muse 新参
///   照图量测拟合定值，出处见 DrawerCardGeometry
///   注；第 78 条录屏复测 ≈57pt 同档）；开态 clip
///   帧另按 DrawerMotion.verticalInset 纵向内嵌
///   （§202 K1）、整卡浮置。阴影 alpha 口径：第 78
///   条 D4——浅色按 §202 定值（峰值 0.22）、深色
///   归零（Muse 深色帧段无可量测阴影），派生走
///   DrawerMotion.shadowOpacity(progress:
///   appearance:) 单点。
/// - 宿主安全区（§318 分界口径，订正 §313 的
///   A-21 一刀切）：drawerHost/contentHost 两宿主
///   走默认 regions 派生、**不清零**——两宿主承载
///   的是常规安全区消费方（DrawerView 身份行顶
///   栏注册与 .safeAreaBar 底条、其余四 Tab 页
///   面），其安全
///   区只能由本层派生、没有下层真宿主自理；清零
///   纪律只适用于内容自管几何的宿主（聊天页内
///   ComposerGuideHost/TopBarGuideHost/列表行宿
///   主——它们各自手排几何、宿主派生只会叠成第二
///   份）。§313 曾把两宿主一并清零、.64 真机实证
///   误伤（身份行撞状态栏/底条进 Home 区），本口
///   径回到 .63 已验形态。
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
/// - 场景门（§323）：左缘开手势 shouldBegin 先过
///   三道场合门（任一侧列表 dragging 中/内容导航
///   深层/编辑态不开，学 Simplenote C/D/F），与方
///   向锁定分工——场合归 shouldBegin、方向归接管
///   后判定，判定走 DrawerMotion.allowsOpenGesture。
/// - 跟手：DrawerMotion 方向锁定（10pt/1.5 倍）达
///   成前不写位移、纵向主导即取消本手势；写入走
///   followedOffset（扣锁定段＋橡皮筋），判定走
///   settleOpens（动量投影以速度×DrawerSpring-
///   Timing.settleProjectionInterval 近似）。
/// - 动画中再拖：停 animator 并从 presentation 层
///   当前 tx 接管，无跳变帧。
/// - 归位动画：UIViewPropertyAnimator＋UISpring-
///   TimingParameters（参数出 OneDayCore.Drawer-
///   SpringTiming 定版单源——§322 重定版 response
///   0.35/ζ 0.85 快档欠阻尼（§313 的 1.4/ζ 1.2 慢
///   阻尼档经 Muse 录屏对照证伪作废），Motion-
///   Tokens.drawerSpring 只以同字面值镜像、单测对
///   钉；旧「双口径换算等价」表述随换算层退役作
///   废）；松手速度按相对位
///   移换算作初速交接；Reduce Motion 时瞬时归位。
/// - 打开先收键盘（旧纪律沿用）；VoiceOver：开态
///   抽屉出 a11y 树、内容退出，关态反之，切换时发
///   screenChanged（开→抽屉面、关→内容面；回触发
///   钮本体的精确落点真机验）。
///
/// 语义开合：AppState.router.drawerPresented 仍是各入口的
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
    /// 抽屉频道行透传（0.36.29 沿用；2026-11-13 频
    /// 道一期起带频道 id——平台频道与 Hermes 频道
    /// 目的地不同，宿主按 id 分发）
    var onOpenChannel: (String) -> Void
    @ViewBuilder var content: () -> Content

    func makeUIViewController(
        context: Context
    ) -> DrawerContainerController {
        let controller = DrawerContainerController()
        let appState = appState
        controller.onPresentedChange = { newValue in
            if appState.router.drawerPresented != newValue {
                appState.router.drawerPresented = newValue
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
    func apply(to controller: DrawerContainerController) {
        let appState = appState
        let modelContext = modelContext
        let locale = locale
        // §365 D1 等值守卫：AnyView/闭包本体不可比——
        // 以「造视图的全部输入」指纹对账，与上次落账
        // 相等即整次跳过（开合翻转本身不再重建双宿主
        // 根，调研 D1 定因）；开合对账在本函数外独立
        // 执行、不受守卫影响
        let fingerprint = DrawerBridgeFingerprint(
            appState: ObjectIdentifier(appState),
            modelContext: ObjectIdentifier(modelContext),
            localeIdentifier: locale.identifier,
            reduceMotion: reduceMotion,
            selection: selection
        )
        guard controller.lastAppliedFingerprint != fingerprint
        else { return }
        controller.lastAppliedFingerprint = fingerprint
        controller.reduceMotion = reduceMotion
        // 台账 147：呈现进度与关打断回写 Router 的
        // 延迟导航喂入口（判定在 Core 状态机）
        controller.onDrawerProgress = { progress in
            appState.router.noteDrawerProgress(progress)
        }
        controller.onDrawerCloseInterrupted = {
            appState.router.noteDrawerCloseInterrupted()
        }
        // §365 D2：落定回写 Router（打开刷新自此只在
        // 开落定时触发、退出动画窗，见 DrawerView）
        controller.onDrawerSettled = { open in
            appState.router.noteDrawerSettled(open: open)
        }
        controller.drawerBuilder = { width in
            AnyView(
                DrawerView(
                    width: width,
                    currentTab: selection,
                    onSelectTab: { selection = $0 },
                    onClose: { controller.setDrawer(false, animated: true) },
                    onOpenChannel: onOpenChannel
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
    /// 开合语义（与 AppState.router.drawerPresented 对账的
    /// 容器侧副本；setDrawer 是唯一写口）
    var semanticPresented = false
    /// 推开量（§313：第 78 条 D2——容器宽×0.75、无
    /// cap，派生单源 DrawerCardGeometry.travel；旧
    /// 口径 min(宽×0.79, 400) 作废）
    private(set) var travel: CGFloat = 0
    /// Reduce Motion（桥注入；true 时归位瞬时）
    var reduceMotion = false
    /// 容器开合变化回写（桥接回 AppState）
    var onPresentedChange: ((Bool) -> Void)?
    /// 呈现进度回写（台账 147 延迟导航的事实源）：
    /// 动画在途时为 presentation 层逐帧采样、其余
    /// 时刻为 model 值——桥接回 AppRouter 的进度喂
    /// 入口（判定在 Core DrawerDeferredNavigation）。
    /// 本口报的 DrawerMotion.progress 即开度（off-
    /// set 为前景位移：0＝合、travel＝开），与状态
    /// 机同口径、Router 直喂不换算
    var onDrawerProgress: ((Double) -> Void)?
    /// 关动画被另一运动打断的回写（台账 147）：桥
    /// 接回 AppRouter——待办导航即刻执行、不吞
    var onDrawerCloseInterrupted: (() -> Void)?
    /// 抽屉根视图 builder（桥注入；travel 变化时容器
    /// 以新宽重取根视图，闭包内回调恒取最新桥状态）
    /// §365 D1：赋值只存不建——根重建唯一时机是布局
    /// 里 travel 真变（rebuildDrawerRoot 以 travel 为
    /// 唯一入参；闭包捕获的 Binding/环境恒为活引用，
    /// 存而不建不丢更新）；旧 didSet 无条件重建是开
    /// 合翻转自带整树重建的定因（调研 D1）
    var drawerBuilder: ((CGFloat) -> AnyView)?
    /// 内容根视图（桥注入；赋值即刷进内容宿主；桥侧
    /// 由 §365 指纹守卫把关，容器侧赋值语义不变）
    var contentRoot: AnyView? {
        didSet {
            if let contentRoot {
                contentHost.rootView = contentRoot
                contentRootApplyCount += 1
            }
        }
    }
    /// 桥上次 apply 的输入指纹（§365 D1 对账面；桥
    /// 写、容器只存）
    var lastAppliedFingerprint: DrawerBridgeFingerprint?
    /// 抽屉根实际重建次数（§365 钉测对账口：只在
    /// rebuildDrawerRoot 真正落笔时 +1）
    private(set) var drawerRootRebuildCount = 0
    /// 内容根实际刷入次数（§365 钉测对账口）
    private(set) var contentRootApplyCount = 0
    /// 开合落定回写（桥注入；§365 D2——finishSettle
    /// 是开合两路的唯一收口，落定事实只从这里出）
    var onDrawerSettled: ((Bool) -> Void)?

    let drawerHost = UIHostingController<AnyView>(
        rootView: AnyView(EmptyView())
    )
    let contentHost = UIHostingController<AnyView>(
        rootView: AnyView(EmptyView())
    )
    /// 前景变换层（只承 transform 与窄条手势）
    let foreground = UIView()
    /// 前景投影层（台账 201 双层结构）：不裁切、只
    /// 投影——与裁切层同帧同半径、垫在其下，柔影
    /// 自本层 alpha 形状（圆角矩形填充）向外投射；
    /// 纯视觉、永不承命中
    let shadowView = UIView()
    /// 前景裁切层（只承圆角裁切、装内容）：台账
    /// 201 前柔影曾与裁切同层（§313 A-01），像素
    /// 实测证伪后投影迁出至 shadowView（见装配注）
    let clipView = UIView()
    /// 关闭态左缘热区（24pt；开态隐藏不挡抽屉）
    let edgeView = UIView()

    /// 当前呈现位移（0…travel，橡皮筋段可越界；跟手
    /// 与动画的唯一事实源，与旧壳 S1 口径同构）——
    /// 前景/抽屉双层 transform 与圆角/阴影/命中/a11y
    /// 派生只许经 applyOffset 由本值写出（§313 A-01）
    var offset: CGFloat = 0
    /// §351 显式阴影路径的当前键（帧＋半径）：与实
    /// 际路径不一致时才在 applyOffset 重设——飞行
    /// 途中帧/半径恒定、路径零重设（零重栅格钉点）
    var shadowPathBounds: CGRect = .null
    var shadowPathRadius: CGFloat = -1
    var animator: UIViewPropertyAnimator?
    /// 在途 animator 的目标方向（true＝开）：停
    /// animator 时据此分「关被打断」（147 待办即刻
    /// 执行）与「开被顶替」（待办继续等关）
    var animatorHeadingOpen = false
    /// 动画在途的呈现进度采样链（台账 147）：anim-
    /// ator 只写 model 值、呈现位移在 presenta-
    /// tion 层——延迟导航的触发事实必须读呈现层
    /// 逐帧采样（与 OB 以共享进度值反应式触发同
    /// 构）；动画落定/被停即拆链
    var progressDisplayLink: CADisplayLink?
    /// 手势会话：接管起点位移＋锁定段（nil＝未锁定）
    var dragStartOffset: CGFloat = 0
    var dragLockTranslation: CGFloat?

    lazy var edgePan: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(
            target: self, action: #selector(handlePan(_:))
        )
        recognizer.delegate = self
        return recognizer
    }()
    lazy var stripPan: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(
            target: self, action: #selector(handlePan(_:))
        )
        recognizer.delegate = self
        recognizer.isEnabled = false
        return recognizer
    }()
    lazy var stripTap: UITapGestureRecognizer = {
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
        // §351 深色接缝中间层底：前景底色＝Palette.
        // drawerBackdrop（深 #191919、浅与 pageBG 同
        // 值）——深色开态卡面横向内缩露出的带与纵向
        // scale 露出的上下细带都读它；卡面本体被投
        // 影层不透明填充全幅盖住、本底色只在露出带
        // 可见（浅色露出带与 pageBG 同值、视觉零变
        // 化）
        foreground.backgroundColor = UIColor(Palette.drawerBackdrop)

        // §318（A-21 分界订正）：两宿主安全区派生**不
        // 清零**、走默认 regions——.64 曾按 A-21 一刀
        // 切清零（原注称「内容安全区归 TabView 内真
        // 宿主自理」），但该立论只对聊天页成立：Drawer-
        // View 与其余四 Tab 都是常规安全区消费方（身
        // 份行顶栏注册靠安全区顶定位、底条是 .safeAreaBar），
        // 清零后身份行上移 59pt 撞状态栏、底条下沉
        // 34pt 进 Home 区（2026-11-17 真机定因，诊断
        // drawer-broken-diagnosis-20261117.md）。清零
        // 纪律自此按宿主性质分界：自管几何者（聊天页
        // 内 ComposerGuideHost/TopBarGuideHost/列表
        // 行宿主等）清零、常规消费方的承载宿主不列。
        // 本处恢复 .63 已验形态（默认派生、聊天页当
        // 时正常，无双份安全区）

        addChild(drawerHost)
        drawerHost.view.backgroundColor = .clear
        view.addSubview(drawerHost.view)
        drawerHost.didMove(toParent: self)
        drawerHost.view.isHidden = true

        view.addSubview(foreground)
        // 台账 201 双层结构（订正 §313 A-01）：§313
        // 自述「clipsToBounds 只裁子层、阴影不被自
        // 裁」——2026-11-22 像素剖面实测证伪：同层
        // masksToBounds 把自家阴影一并裁掉，真机图
        // 与模拟器剖面接缝全程 252、无任何暗带（数
        // 值断言却全绿，规格 drawer-card-edge-
        // shadow-20261122.md §1/§3）。改业界通行双
        // 层：投影层垫底（不裁切、同帧同半径、填充
        // 取卡面色只供轮廓成影、本体被裁切层同帧
        // 盖住）＋裁切层在上装内容；shadowPath §351
        // 起改显式（自动成影随帧 bounds 逐帧重栅格
        // ＝卡顿定因之一；路径只在帧/半径变化时于
        // applyOffset 一处重设、单写点纪律不变）；
        // radius/offset 定值出
        // DrawerCardGeometry 单源（经 DrawerMotion
        // 转发），opacity 只在 applyOffset 随
        // progress 与外观派生
        shadowView.backgroundColor = UIColor(Palette.chatSurface)
        shadowView.layer.cornerCurve = .continuous
        shadowView.layer.shadowColor = UIColor(Palette.shadowBase).cgColor
        shadowView.layer.shadowRadius = DrawerMotion.shadowRadius
        shadowView.layer.shadowOffset = CGSize(
            width: DrawerMotion.shadowX, height: 0
        )
        shadowView.layer.shadowOpacity = 0
        shadowView.isUserInteractionEnabled = false
        foreground.addSubview(shadowView)
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

    // §323：前景裁切几何的派生已迁 DrawerMotion.
    // clipGeometry（progress 纯派生、与全部呈现派
    // 生同源，DrawerMotion 立为唯一通道）；本容器
    // 私收实现删除。派生口径沿革（§202 K1/K2 反向
    // 补偿、§313 阴影挂 clip 本人自动成影）见
    // DrawerMotion 该函数注

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let newTravel = DrawerCardGeometry.travel(
            containerWidth: bounds.width
        )
        let travelChanged = newTravel != travel
        travel = newTravel
        // 抽屉未变换几何口径不变（原点 0/宽 travel/
        // 全高）：锁步靠 transform 承担（applyOffset
        // 写 offset−travel）。§313 起抽屉层同带
        // transform——与前景同一纪律：布局只准以
        // bounds＋center 写未变换几何，**不许写 frame**
        // （frame setter 会按当前 transform 反解
        // center：合态布局一趟就能把抽屉显示位补偿回
        // x=0、下次打开整体错位一个 travel）
        drawerHost.view.bounds = CGRect(
            origin: .zero,
            size: CGSize(width: travel, height: bounds.height)
        )
        drawerHost.view.center = CGPoint(
            x: travel / 2, y: bounds.midY
        )
        // 前景同纪律：transform 非 identity 时 frame
        // 未定义（Apple 文档明文），布局只准以 bounds
        // ＋center 写「未变换几何」、位移全部由
        // transform 承担。旧写法在此以 frame 重设——
        // animator 已把 model transform 承诺到目标
        // 值，frame setter 按当前 transform 反解 center，
        // 一次布局往返就把视觉位置补偿回原位（0.50.18
        // 真机抽屉打不开的定案主因：动画只剩布局触发前
        // 约 30pt 的呈现残移，见诊断报告与回归测试
        // testAnimatedOpenSurvivesMidFlightResize）
        foreground.bounds = CGRect(origin: .zero, size: bounds.size)
        foreground.center = CGPoint(x: bounds.midX, y: bounds.midY)
        edgeView.frame = CGRect(
            x: 0, y: 0,
            width: OneDayMetrics.drawerEdgeZone,
            height: bounds.height
        )
        if travelChanged {
            rebuildDrawerRoot()
            // 旋转/尺寸变：无拖无动画时开态位移跟到新
            // travel（主页面仍完整露出同一比例）
            if animator == nil, dragLockTranslation == nil,
               semanticPresented {
                offset = travel
            }
        }
        // §323 单写点：clip/内容宿主两帧自此只许
        // applyOffset 一处写——本处不再直写（收掉
        // layout 与 applyOffset 的双调用点，学
        // Simplenote 单写点）；布局事实（bounds/
        // center/travel）更新后统一经呈现口按当前
        // offset 重派生一遍：关态把抽屉锁步位钉到
        // 新 −travel（§313：合态抽屉恒藏于主面之
        // 后一个 travel、首次布局后即成立）、高度
        // 单变（travel 不变）时裁切帧同源跟随。动
        // 画在途时 model 值已是目标值、重派生同值
        // 不打架（traitCollectionDidChange 同先例）
        applyOffset(offset)
    }

    func rebuildDrawerRoot() {
        guard travel > 0, let drawerBuilder else { return }
        drawerHost.rootView = drawerBuilder(travel)
        drawerRootRebuildCount += 1
    }

    /// 外观（浅/深）切换：阴影口径随外观分叉（第 78
    /// 条 D4），以当前 offset 经唯一呈现口重派生一次
    /// （offset 不变、只换阴影口径；动画在途时 model
    /// 值已是目标值、重派生与飞行呈现同值不打架）
    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle
            != previousTraitCollection?.userInterfaceStyle {
            applyOffset(offset)
        }
    }

    // MARK: - 位移呈现

    /// 位移唯一呈现口：只写双层 transform（主页面布
    /// 局尺寸恒不变）＋圆角/阴影/命中/a11y 派生——全
    /// 容器不许有第二处写 transform 或阴影（§313
    /// A-01 单源收敛）。§323 起 clip/内容宿主两帧
    /// 同归本口唯一写点（layout 只写未变换几何事实
    /// 后经本口重派生，学 Simplenote 单写点）
    /// §351 起三层帧在本口钉前景全幅（开合全程恒
    /// 定、只随布局尺寸变），呈现全走 transform——
    /// 逐帧零帧写、零 bounds 变化（刚体口径，定
    /// 因与对位见 DESIGN §351）
    func applyOffset(_ newOffset: CGFloat) {
        offset = newOffset
        foreground.transform = CGAffineTransform(
            translationX: newOffset, y: 0
        )
        // 第 78 条 D1 锁步：抽屉层同刚体平移——位移＝
        // offset − travel（合态 −travel 藏于主面之后、
        // 开态 0 归位）；§318：越界段由 DrawerMotion
        // 钳制 [−travel, 0]（开向过冲不露容器底）；
        // travel 未量得（0）时恒 0 不动
        drawerHost.view.transform = CGAffineTransform(
            translationX: DrawerMotion.drawerOffset(
                offset: newOffset, travel: travel
            ),
            y: 0
        )
        let progress = DrawerMotion.progress(
            offset: newOffset, travel: travel
        )
        let appearance: DrawerMotion.ShadowAppearance =
            traitCollection.userInterfaceStyle == .dark
                ? .dark : .light
        // §351 刚体化（定因见 DESIGN §351）：此前本
        // 口按 clipGeometry 逐帧写三层 frame——clip
        // 层 bounds 逐帧变＝裁切子树逐帧重合成、无
        // shadowPath 的自动阴影随 bounds 逐帧重栅
        // 格（真机录屏开场死帧/中段冻结的呈现侧成
        // 本）。改整卡刚体：三层未变换几何钉前景全
        // 幅（bounds＋center 写、与前景同纪律——卡
        // 层带 transform 后 frame 未定义），开合视
        // 觉全由 transform 承担：横移在前景层；纵
        // 向内嵌（K1）改整卡 scaleY 等效（Drawer-
        // Motion.cardScaleY、与旧帧几何逐值等价）
        let fullBounds = CGRect(
            origin: .zero, size: foreground.bounds.size
        )
        let fullCenter = CGPoint(
            x: fullBounds.midX, y: fullBounds.midY
        )
        shadowView.bounds = fullBounds
        shadowView.center = fullCenter
        clipView.bounds = fullBounds
        clipView.center = fullCenter
        contentHost.view.bounds = fullBounds
        contentHost.view.center = fullCenter
        let radius = DrawerMotion.cornerRadius(
            progress: progress
        )
        clipView.layer.cornerRadius = radius
        shadowView.layer.cornerRadius = radius
        // 深色横向内缩（§351）：卡面（投影层＋裁切
        // 层）随 progress 右移 cardLeadingShift、露
        // 出前景底色作接缝中间层（Palette.drawer-
        // Backdrop、深 #191919——Muse 深色接缝三
        // 段台阶量测，见令牌注）；内容宿主反向平移
        // 抵消——内容只随前景横移、窗口位移对内容
        // 透明（与 §202 反向补偿同构）。浅色恒 0、
        // 无此层（浅色接缝＝§345 柔影、已关账）
        let shift = DrawerMotion.cardLeadingShift(
            progress: progress, appearance: appearance
        )
        let cardTransform = CGAffineTransform(
            a: 1, b: 0, c: 0,
            d: DrawerMotion.cardScaleY(
                progress: progress,
                foregroundHeight: foreground.bounds.height
            ),
            tx: shift, ty: 0
        )
        clipView.transform = cardTransform
        shadowView.transform = cardTransform
        contentHost.view.transform = CGAffineTransform(
            translationX: -shift, y: 0
        )
        // 阴影路径显式化（§351）：按当前 bounds 与
        // 半径生成、只在帧/半径变化时重设——飞行途
        // 中 bounds 与半径（阶跃定值）恒定，路径零
        // 重设、渲染端零重栅格；关态（progress 0
        // 且无动画在途）清掉防陈旧路径残留（关飞行
        // 途中 animator 在途、路径保留到落定）
        if progress > 0 {
            if shadowPathBounds != shadowView.bounds
                || shadowPathRadius != radius {
                shadowView.layer.shadowPath = UIBezierPath(
                    roundedRect: shadowView.bounds,
                    cornerRadius: radius
                ).cgPath
                shadowPathBounds = shadowView.bounds
                shadowPathRadius = radius
            }
        } else if animator == nil,
                  shadowView.layer.shadowPath != nil {
            shadowView.layer.shadowPath = nil
            shadowPathBounds = .null
            shadowPathRadius = -1
        }
        // 阴影只在此写 opacity 一项；外观口径第 78
        // 条 D4：浅色走定值、深色归零，读容器当前
        // trait（随 trait 变化由 traitCollectionDid-
        // Change 以当前 offset 重派生）
        shadowView.layer.shadowOpacity = Float(
            DrawerMotion.shadowOpacity(
                progress: progress,
                appearance: appearance
            )
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
        // 台账 147：无动画在途时 model 值即呈现事
        // 实、就地回写进度（拖动逐帧/瞬时关/布局重
        // 派生都经本口）；动画在途时 model 已跳目标
        // 值、进度归采样链逐帧回写，不在此抢报
        if animator == nil {
            onDrawerProgress?(progress)
        }
    }

    /// 呈现进度采样（台账 147）：读 foreground
    /// presentation 层的当前 tx 换算进度回写——关
    /// 动画途中 model 恒为目标值，唯呈现层是逐帧
    /// 真值（stopAnimatorCapturingPresentation 读
    /// 呈现层接管同源）
    @objc func samplePresentationProgress() {
        guard travel > 0 else { return }
        let presented = foreground.layer.presentation()?
            .transform.m41 ?? offset
        onDrawerProgress?(
            DrawerMotion.progress(
                offset: presented, travel: travel
            )
        )
    }

    func startProgressSampling() {
        guard progressDisplayLink == nil else { return }
        let link = CADisplayLink(
            target: self,
            selector: #selector(samplePresentationProgress)
        )
        link.add(to: .main, forMode: .common)
        progressDisplayLink = link
    }

    func stopProgressSampling() {
        progressDisplayLink?.invalidate()
        progressDisplayLink = nil
    }

}
