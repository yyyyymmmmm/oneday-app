import OneDayCore
import SwiftUI
import UIKit

/// 右滑回复的 UIKit 识别器桥（§265，换代包 5；
/// 换代包 7 仲裁重做；换代包 8 判定点前移）：取
/// 代 SwipeReplyModifier 旧用的 SwiftUI `.sim-
/// ultaneousGesture(DragGesture)`——双审计
/// （claude-/codex-chat-stack-audit-20261114）
/// 定性：SwiftUI 手势与子树 UIKit 手势同场时跟
/// 踪消耗触摸序列，UITextView 双击选字所需的两
/// 次完整 down→up 被打断。用户 2026-11-14 亲令
/// 大厂机制三条之③：手势仲裁＝方向门＋失败依
/// 赖，禁 simultaneousGesture 拖拽压文本手势。
///
/// 构造（全走 UIKit 官方仲裁入口，不自研识别）：
/// - UIPanGestureRecognizer 装在宿主滚动视图上
///   （装配走 ScrollViewTapDismiss 已验的 as-
///   cend 寻面：桥视图是行内容的 background、
///   恒在滚动视图子树内，新旧两承载同路）；每
///   行一枚、delegate 以「触点起始位置落在本
///   行帧内」圈定辖区（shouldReceive）；
/// - 失败依赖（纵滚让行）：安装时令宿主滚动视
///   图的自家 pan require(toFail: 本识别器)，纵
///   滚等本行横滑先失败（方向判死即失败、延迟
///   只有锁距一段位移）；
/// - 起始点排除（代码块/表格横滚区）也在 should-
///   Begin 判：落在排除帧内直接 failed，触摸不
///   被 cancelsTouchesInView 吞掉、横滚区自家
///   滚动不受扰（旧 SwiftUI 构造靠同时识别＋回
///   调内忽略，本构造靠不开始）；
/// - 排除帧来源（G-07 收口，2026-11-23）：原为行
///   内背景 GeometryReader 经偏好键在布局期发布
///   帧、修饰符 @State 收集——行内协商型构件兼作
///   手势仲裁，与列表行「尺寸确定」通则相悖（大
///   厂差距审计 G-07）；改贴 UIKit 标记视图
///   （SwipeReplyExcludedMarker），帧由本类在判
///   定时刻自 cell 视图层级直算，布局期零状态写
///   入、行内零协商型构件。
/// - 数值判定（起滑/触发/封顶）仍全走 Core
///   SwipeReplyMotion 单源，呈现层状态写回走
///   onPanChanged/onPanEnded 两条回调（修饰符
///   每次 body 求值经 updateUIView 刷新闭包，
///   与 ScrollViewTapDismiss 的 onBlankTap 同式）。
///
/// 换代包 7（0.50.78 真机反馈修复 B，仲裁重做）：
/// 方向判定改位移式方向锁（Core SwipeReplyMo-
/// tion.determineDirection）——起手前约 10pt 位
/// 移内按位移比判方向，横向锁定后立即 1:1 跟
/// 手；竖向判死只针对明确竖向位移（|dy| > |dx|）；
/// 仲裁关系收窄：只保留与滚动的失败依赖（纵滚
/// 等横滑）、去掉等点按/长按的无谓等待（位移锁
/// 已足够快，大厂通行做法）；触发阈值维持 60pt、
/// 越线给 soft 触觉（带回程 re-arm 迟滞 55pt）。
///
/// 换代包 8（0.50.80 热修，0.50.79 真机反馈）：
/// 修复 B 把方向判定放在 handlePan（识别器
/// .began 之后消费位移）——纵滚的 require(to-
/// Fail:) 在识别器 began 的同一拍即被判死，
/// 10pt 后再把自己置 .failed 也救不回本段触
/// 摸：0.50.79 真机聊天页按在消息行上竖滑全
/// 灭（行间空隙无识别器、纵滚照常，故障形态
/// 与构造逐项吻合）。判定搬回 began 之前：识
/// 别器子类（DirectionLockPanGestureRecogni-
/// zer）在 .possible 阶段吞位移、自算累计位
/// 移，达锁距当场出结论——竖向/左向在开始之
/// 前置 .failed（纵滚随即接管本段触摸）、右向
/// 横滑才放行 super 开始识别。判据仍走 Core
/// determineDirection 单源，数值口径（锁距
/// 10/起滑 30/触发 60/re-arm 55）逐字不变；
/// handlePan 自此只消费已锁定横向的位移与收尾。
struct SwipeReplyPanInstaller: UIViewRepresentable {
    var onPanChanged: (CGFloat) -> Void
    var onPanEnded: () -> Void

    func makeUIView(
        context: Context
    ) -> SwipeReplyPanInstallerView {
        let view = SwipeReplyPanInstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
        return view
    }

    func updateUIView(
        _ uiView: SwipeReplyPanInstallerView,
        context: Context
    ) {
        uiView.onPanChanged = onPanChanged
        uiView.onPanEnded = onPanEnded
        uiView.installIfNeeded()
    }

    static func dismantleUIView(
        _ uiView: SwipeReplyPanInstallerView,
        coordinator: ()
    ) {
        uiView.uninstall()
    }
}

/// 方向锁识别器（换代包 8）：方向结论必须在
/// began 之前出——纵滚经 require(toFail:) 等
/// 本识别器先失败，本识别器一旦 began，纵滚在
/// 同一拍被判死、事后再 fail 救不回本段触摸
/// （0.50.79 事故形态）。故 .possible 阶段吞
/// 掉位移事件、自算累计位移：未达锁距不放行
/// super（识别器停在 .possible、纵滚同停
/// .possible 等裁决）；达锁距按 Core deter-
/// mineDirection 判向——右向横滑放行 super 开
/// 始识别（super 的平移账自 touchesBegan 起
/// 算、吞掉的锁距段不丢），竖向与左向当场置
/// .failed 让纵滚接管。判定是纯位移比、不看
/// 速度（慢拖/斜向起手不被一票否决——修复 B
/// 的目标不变，只把判定点从 began 后搬回
/// began 前）
final class DirectionLockPanGestureRecognizer:
    UIPanGestureRecognizer
{
    /// began 前裁决三态：继续观察/放行开始/当场判死
    enum PreBeginVerdict {
        case observe, begin, fail
    }

    /// began 前方向裁决（纯函数面，单测直钉）：
    /// 位移未达锁距恒观察；达锁距走 Core deter-
    /// mineDirection——横向（右滑）放行、竖向判
    /// 死；Core 归未定的左向占优（|dx|>|dy| 且
    /// dx<0）同判死（非本手势辖区，不许悬置占
    /// 住纵滚），斜向未分继续观察
    static func preBeginVerdict(
        translationX dx: CGFloat,
        translationY dy: CGFloat
    ) -> PreBeginVerdict {
        guard max(abs(dx), abs(dy))
            >= SwipeReplyMotion.directionLockDistance
        else { return .observe }
        switch SwipeReplyMotion.determineDirection(
            translationX: dx, translationY: dy
        ) {
        case .horizontal:
            return .begin
        case .vertical:
            return .fail
        case .undetermined:
            return abs(dx) > abs(dy) ? .fail : .observe
        }
    }

    /// 触摸起始点（识别器视图坐标系＝宿主滚动
    /// 视图）：delegate 的排除帧判定以此为准
    /// （began 时刻的当前点已漂移约一个锁距）
    private(set) var touchStartLocation: CGPoint?

    override func touchesBegan(
        _ touches: Set<UITouch>, with event: UIEvent
    ) {
        touchStartLocation =
            touches.first?.location(in: view)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(
        _ touches: Set<UITouch>, with event: UIEvent
    ) {
        guard state == .possible else {
            super.touchesMoved(touches, with: event)
            return
        }
        guard let start = touchStartLocation,
              let view,
              let touch = touches.first
        else {
            super.touchesMoved(touches, with: event)
            return
        }
        let point = touch.location(in: view)
        switch Self.preBeginVerdict(
            translationX: point.x - start.x,
            translationY: point.y - start.y
        ) {
        case .observe:
            // 未出结论：吞掉本拍（不放行 super、
            // 识别器与纵滚同停 .possible）
            return
        case .begin:
            super.touchesMoved(touches, with: event)
        case .fail:
            // 在 began 之前判死：纵滚随即接管本
            // 段触摸（换代包 8 的修复本体）
            state = .failed
        }
    }

    override func touchesEnded(
        _ touches: Set<UITouch>, with event: UIEvent
    ) {
        if state == .possible {
            // 未出结论触摸已收尾：判死收场，不留
            // 悬置识别器
            state = .failed
        } else {
            super.touchesEnded(touches, with: event)
        }
        touchStartLocation = nil
    }

    override func touchesCancelled(
        _ touches: Set<UITouch>, with event: UIEvent
    ) {
        if state == .possible {
            state = .failed
        } else {
            super.touchesCancelled(touches, with: event)
        }
        touchStartLocation = nil
    }

    override func reset() {
        super.reset()
        touchStartLocation = nil
    }
}

/// 安装宿主视图兼识别器 delegate（与 TapDismiss-
/// InstallerView 同分工：本体随 SwiftUI 桥存活，
/// 识别器由滚动视图持有、target/delegate 指本
/// 视图；桥卸载时 uninstall 摘除识别器，滚动视
/// 图的 require(toFail:) 随识别器释放失效）
final class SwipeReplyPanInstallerView: UIView,
    UIGestureRecognizerDelegate
{
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    private weak var installedScrollView: UIScrollView?
    private var pan: DirectionLockPanGestureRecognizer?
    private var retryScheduled = false

    // MARK: - 触觉状态（换代包 7）

    private var hasTriggeredHaptic = false
    private var currentOffset: CGFloat = 0

    static let recognizerName = "OneDaySwipeReplyPan"

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        installIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    /// 定位宿主滚动视图并安装（幂等：已装在同一滚
    /// 动视图上直接返回；承载换人时旧识别器随旧
    /// 视图走、本视图在新视图上补装——与 TapDis-
    /// missInstallerView 同口径）。首试在入窗/更
    /// 新拍——彼时层级可能未定版，失败时排一次主
    /// 队列延迟重试（安装时机兜底、装成即止）
    func installIfNeeded() {
        guard let scrollView = findHostingScrollView()
        else {
            if window != nil, !retryScheduled {
                retryScheduled = true
                DispatchQueue.main.async { [weak self] in
                    self?.retryScheduled = false
                    self?.installIfNeeded()
                }
            }
            return
        }
        if installedScrollView === scrollView, pan != nil {
            return
        }
        uninstall()
        let recognizer = DirectionLockPanGestureRecognizer(
            target: self,
            action: #selector(handlePan(_:))
        )
        recognizer.name = Self.recognizerName
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        scrollView.addGestureRecognizer(recognizer)
        // 失败依赖（纵滚让行）：列表纵滚须等本行
        // 横滑先失败才开始——横滑的方向判死发生
        // 在识别器 began 之前的锁距判定点（换代
        // 包 8），纵滚延迟以点计
        scrollView.panGestureRecognizer.require(
            toFail: recognizer
        )
        pan = recognizer
        installedScrollView = scrollView
    }

    /// 摘除本行识别器（桥 dismantle 时调用；识别
    /// 器释放后滚动视图侧的失败依赖随之失效）
    func uninstall() {
        if let pan, let installedScrollView {
            installedScrollView.removeGestureRecognizer(pan)
        }
        pan = nil
        installedScrollView = nil
    }

    /// 测试与普查入口：本视图当前持有的识别器
    var installedRecognizer: UIPanGestureRecognizer? {
        pan
    }

    private func findHostingScrollView() -> UIScrollView? {
        // 桥视图是行内容的 background、恒在宿主滚
        // 动视图子树内（旧承载 HostingScrollView/
        // 新承载 ChatListCarrier 的 UIScrollView 同
        // 理）——ascend 直达，不需要 TapDismiss 的
        // 窗口选面兜底（那是给「与滚动视图同父兄
        // 弟」的桥用的，本桥不在那个位置）
        var ancestor = superview
        var hops = 0
        while let current = ancestor, hops < 16 {
            if let scroll = current as? UIScrollView {
                return scroll
            }
            ancestor = current.superview
            hops += 1
        }
        return nil
    }

    // MARK: - 识别器动作（换代包 8：只消费已锁定横向）

    @objc private func handlePan(
        _ recognizer: UIPanGestureRecognizer
    ) {
        switch recognizer.state {
        case .began, .changed:
            // 能走到本口的识别器必已在 began 之前
            // 锁定右向横滑（DirectionLockPanGes-
            // tureRecognizer 的前置判定），本口只
            // 消费位移并检查触觉
            let translation = recognizer.translation(
                in: recognizer.view
            )
            processPanTranslation(translation.x)
            checkAndTriggerHaptic(translation.x)

        case .ended, .cancelled, .failed:
            processPanEnd()
            hasTriggeredHaptic = false
            currentOffset = 0

        default:
            break
        }
    }

    /// 触觉反馈检查（换代包 7）：越过触发线
    /// （60pt）时给 soft 触觉、带回程 re-arm 迟
    /// 滞（回拖到 55pt 以下重新武装、防抖）
    private func checkAndTriggerHaptic(_ translationX: CGFloat) {
        let offset = SwipeReplyMotion.dragOffset(
            translationWidth: translationX,
            currentOffset: currentOffset
        )
        currentOffset = offset

        // 越过触发线且未触发过
        if !hasTriggeredHaptic && SwipeReplyMotion.shouldTrigger(offset: offset) {
            hasTriggeredHaptic = true
            Haptics.impact(.soft)
        }

        // 回程 re-arm：回拖到 rearm 线以下重新武装
        if hasTriggeredHaptic && offset < SwipeReplyMotion.hapticRearmThreshold {
            hasTriggeredHaptic = false
        }
    }

    /// 拖动处理（与识别器动作的接缝：单测以合成
    /// 位移直调本口验回调链，触摸 plumbing 本身
    /// 归 UIKit、无可自验面）
    func processPanTranslation(_ translationX: CGFloat) {
        onPanChanged?(translationX)
    }

    /// 拖动收尾（松手/取消/失败同口：呈现层回位）
    func processPanEnd() {
        onPanEnded?()
    }

    // MARK: - UIGestureRecognizerDelegate（仲裁）

    /// 辖区圈定：触点起始位置落在本行帧内才接收
    /// （桥视图＝行内容 background、其帧即行帧；
    /// 坐标换算到滚动视图内容系，与触点同系比对）
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let scrollView = installedScrollView
        else { return false }
        let point = touch.location(in: scrollView)
        let rowFrame = convert(bounds, to: scrollView)
        return rowFrame.contains(point)
    }

    /// 起始点排除门：起滑点落在排除帧（代码块/
    /// 表格横滚区）内——不许开始（转 failed、触
    /// 摸不被吞）。判定以触摸起始点为准：本口在
    /// 识别器放行 super 开始识别时才被问（换代
    /// 包 8），彼时当前点已漂移约一个锁距——子
    /// 类留存的起始点（滚动视图坐标系）换算回本
    /// 视图坐标系再判；无留存时回退当前点。方向
    /// 判定不在本口（识别器子类的 began 前裁决）
    override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let pan = gestureRecognizer
            as? UIPanGestureRecognizer
        else { return true }
        let startLocation: CGPoint
        if let lockPan = gestureRecognizer
            as? DirectionLockPanGestureRecognizer,
           let start = lockPan.touchStartLocation,
           let hostView = lockPan.view {
            startLocation = convert(start, from: hostView)
        } else {
            startLocation = pan.location(in: self)
        }
        if SwipeReplyMotion.isExcluded(
            startLocation: startLocation,
            frames: computeExcludedFrames()
        ) {
            return false
        }
        return true
    }

    /// 失败依赖收窄（换代包 7）：不再等点按/长按
    /// 识别器——位移式方向锁已足够快（约 10pt 内
    /// 判定），点按/长按与横滑的共存靠方向锁解决
    /// （大厂通行做法，mature-practice-gestures-
    /// topbar-20261122.md 题 2.2①）。只保留与滚
    /// 动的失败依赖（安装时 require(toFail:) 显
    /// 式声明，不经本口）
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf
            otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    /// 与任何识别器都不同时识别：成败只走方向锁
    /// 与失败依赖两条明路，不留并行含糊面
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith
            otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

/// 右滑引用排除区标记视图（G-07）：纯 UIKit 惰性
/// 标记——不参与命中、不发布状态；其帧即排除区
/// 几何，由安装器在判定时刻直算（见 computeEx-
/// cludedFrames）。SwiftUI 侧经 SwipeReplyExclu-
/// dedMarker 以背景形态贴附被标记视图、帧与被标
/// 记视图一致
final class SwipeReplyExcludedMarkerView: UIView {}

/// 排除区标记的 SwiftUI 桥（G-07）：取代原背景
/// GeometryReader＋偏好键的布局期帧发布
struct SwipeReplyExcludedMarker: UIViewRepresentable {
    func makeUIView(
        context: Context
    ) -> SwipeReplyExcludedMarkerView {
        let view = SwipeReplyExcludedMarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(
        _ uiView: SwipeReplyExcludedMarkerView,
        context: Context
    ) {}
}

extension SwipeReplyPanInstallerView {
    /// 本行内容的 UIKit 根：上行至 cell 为止；无
    /// cell 承载时取宿主滚动视图之下的最高祖先
    /// （判定与计算只在本行子树内，不越行串扰）
    private func rowRootView() -> UIView {
        var root: UIView = self
        var ancestor = superview
        while let current = ancestor {
            if current is UICollectionViewCell {
                return current
            }
            if let scroll = installedScrollView,
               current === scroll {
                break
            }
            root = current
            ancestor = current.superview
        }
        return root
    }

    /// 排除帧直算（G-07）：行子树内全部标记视图的
    /// 帧（换算到本视图坐标系），判定时刻现算——
    /// 与旧偏好发布同语义（被标记区＝代码块横滚
    /// ScrollView 本体／表格整区），只是几何来源
    /// 自布局期状态改为 UIKit 层级实帧
    func computeExcludedFrames() -> [CGRect] {
        let root = rowRootView()
        var frames: [CGRect] = []
        func walk(_ view: UIView) {
            if let marker = view
                as? SwipeReplyExcludedMarkerView {
                frames.append(
                    marker.convert(marker.bounds, to: self)
                )
            } else if let scroll = view as? UIScrollView,
                      scroll !== installedScrollView,
                      scroll.isScrollEnabled,
                      scroll.contentSize.width > scroll.bounds.width + 1 {
                frames.append(
                    scroll.convert(scroll.bounds, to: self)
                )
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(root)
        return frames
    }
}
