import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

extension DrawerContainerController {
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
        animatorHeadingOpen = open
        startProgressSampling()
        animator.startAnimation()
    }

    func finishSettle(open: Bool) {
        stopProgressSampling()
        // 台账 147：落定回写终值进度——关落定的 0
        // 是延迟导航的兜底 flush 事实（采样漏过阈
        // 值时在此补达，判定在 Router/Core）
        onDrawerProgress?(
            DrawerMotion.progress(offset: offset, travel: travel)
        )
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
        // §365 D2：落定事实回写（桥接 Router 的开落
        // 定计数；DrawerView 的打开刷新自此只在此触
        // 发、退出动画窗）
        onDrawerSettled?(open)
    }

    /// VoiceOver 树切换：开态只留抽屉、关态只留内容；
    /// 焦点引导发 screenChanged（开→抽屉面、关→内容
    /// 面近似回触发侧，精确落点真机验）
    func syncAccessibility(open: Bool) {
        drawerHost.view.accessibilityElementsHidden = !open
        contentHost.view.accessibilityElementsHidden = open
        UIAccessibility.post(
            notification: .screenChanged,
            argument: open ? drawerHost.view : contentHost.view
        )
    }

    func resignKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// 动画中再拖/再令：停 animator 并把 presentation
    /// 层的当前 tx 收回事实源——接管无跳变帧（S7 桥
    /// 接在 UIKit 侧的等价落法）
    func stopAnimatorCapturingPresentation() {
        guard let animator, animator.isRunning else {
            self.animator = nil
            return
        }
        // 台账 147：被停的若是关动画——延迟导航待
        // 办即刻执行（OB 口径：关被另一运动打断也
        // 推、只推一次）；被停的是开动画则待办继
        // 续等随后的关（点行本人在停后即下达关令）
        let interruptedClose = !animatorHeadingOpen
        animator.pauseAnimation()
        if let presentation = foreground.layer.presentation() {
            offset = presentation.transform.m41
        }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .current)
        self.animator = nil
        stopProgressSampling()
        if interruptedClose {
            onDrawerCloseInterrupted?()
        }
        // 呈现位回写走唯一呈现口（§313：transform 不
        // 许有第二写点；animator 已清零、交互派生按
        // 捕获位成立，随后 setDrawer/手势流程再行对账）
        applyOffset(offset)
    }

    // MARK: - 手势

    @objc func handleStripTap() {
        setDrawer(false, animated: true)
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
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
            // 触感矩阵条件项（体验三件规格 §2.3／表 D
            // 物理吸附）：手势拖拽吸附落位且状态真翻
            // 转才补 impact .light 一次；回弹原态不响、
            // 按钮开合不走本路（防腻清单：抽屉开合无
            // 触感，只给手势吸附这一处例外）
            if opens != semanticPresented {
                Haptics.impact(.light)
            }
            setDrawer(opens, animated: true, velocityX: velocity.x)
        case .cancelled, .failed:
            dragLockTranslation = nil
            setDrawer(semanticPresented, animated: true)
        default:
            break
        }
    }

    /// 场景门（§323，学 Simplenote shouldBegin 的
    /// C/D/F 三道场合门）：只管左缘开手势——任一侧
    /// 列表 dragging 中（C）、内容导航栈深层（D、
    /// 左缘是系统返回手势领地，与既有 require-
    /// failure 让行互为双保险）、任一侧编辑态（F）
    /// 时不开抽屉。判定走 DrawerMotion.allowsOpen-
    /// Gesture 纯谓词；事实采集＝宿主层级扫描（尽力
    /// 而为：未见对应结构按无阻碍计、深度恒 1，不
    /// 因采集不到而误锁正常开合——四场景终验归真
    /// 机手测）。窄条关手势不设门（关抽屉不许被场
    /// 合挡住）
    func gestureRecognizerShouldBegin(
        _ recognizer: UIGestureRecognizer
    ) -> Bool {
        guard recognizer === edgePan else { return true }
        return DrawerMotion.allowsOpenGesture(scene: currentGestureScene())
    }

    /// 场景事实采集（§323）：两宿主层级递归扫描——
    /// UIScrollView.isDragging（SwiftUI List/Scroll-
    /// View 的 UIKit 底座同源）、UINavigationCont-
    /// roller 栈深（取层级内最大值）、UITableView.
    /// isEditing（SwiftUI List 编辑态的底座同源）
    func currentGestureScene() -> DrawerMotion.GestureScene {
        DrawerMotion.GestureScene(
            contentListDragging: Self.hierarchyHasDraggingScrollView(
                contentHost.view),
            drawerListDragging: Self.hierarchyHasDraggingScrollView(
                drawerHost.view),
            contentNavigationDepth: Self.hierarchyMaxNavigationDepth(
                contentHost.view),
            isEditing: Self.hierarchyHasEditingList(contentHost.view)
                || Self.hierarchyHasEditingList(drawerHost.view)
        )
    }

    /// 层级内任一滚动视图正在拖动（门 C 的采集半）
    static func hierarchyHasDraggingScrollView(_ root: UIView) -> Bool {
        if let scrollView = root as? UIScrollView, scrollView.isDragging {
            return true
        }
        return root.subviews.contains {
            hierarchyHasDraggingScrollView($0)
        }
    }

    /// 层级内导航栈最大深度（门 D 的采集半；未见
    /// 导航控制器恒 1＝根层、不阻碍）。导航控制器
    /// 是控制器不是视图、不在视图树上——逐视图沿
    /// 响应链向上找到的首个控制器即其宿主控制器，
    /// 导航栈的容器视图宿主恰是 UINavigationCont-
    /// roller 本人（首轮 CI 实证：在视图树里直接
    /// 找控制器类型恒落空、深度恒 1，两例新测红
    /// 后改本法）
    static func hierarchyMaxNavigationDepth(_ root: UIView) -> Int {
        var depth = 1
        var responder: UIResponder? = root
        while let current = responder {
            if let controller = current as? UIViewController {
                if let navigation = controller as? UINavigationController {
                    depth = max(depth, navigation.viewControllers.count)
                }
                break
            }
            responder = current.next
        }
        for subview in root.subviews {
            depth = max(depth, hierarchyMaxNavigationDepth(subview))
        }
        return depth
    }

    /// 层级内任一列表处于编辑态（门 F 的采集半）
    static func hierarchyHasEditingList(_ root: UIView) -> Bool {
        if let table = root as? UITableView, table.isEditing {
            return true
        }
        return root.subviews.contains {
            hierarchyHasEditingList($0)
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
