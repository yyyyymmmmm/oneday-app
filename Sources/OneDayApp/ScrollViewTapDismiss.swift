import SwiftUI
import UIKit

/// 点空白收键盘（键盘整包·第五症，2026-11-13）：
/// 装在消息列表 UIScrollView 本体上的一枚 UITap-
/// GestureRecognizer——取代内容栈上的祖先 SwiftUI
/// 单击 tap（0.2.1–本包，退役理由见 ChatView 栈内
/// 注：辖区不及顶/底 contentMargins 带、content-
/// Shape 全域命中圈入文字区、无 failure-require-
/// ment 仲裁）。
///
/// 口径（苹果官方文档为据）：
/// - 辖区＝滚动视口本体：顶/底留位带、行间空隙、
///   气泡非文字区全覆盖——点空白收起本就是滚动视
///   图自家手势体系的事（iMessage 同构：拖动收起
///   走 UIScrollView.keyboardDismissMode、点按走
///   滚动视图上的识别器），不另叠自研识别层；
/// - 仲裁走 UIGestureRecognizerDelegate 的官方
///   入口 shouldReceive：触点落在任何 UITextView
///   子树内（消息正文/链接/选字领地）时识别器根
///   本不接收该触摸——文字区的点按、双击选字、长
///   按菜单全归其自家体系，本识别器无从打断（与
///   选字会诊建议修法 2 同向：正文区不触发 dis-
///   miss，只是本包更进一步：连识别都不发生）；
/// - cancelsTouchesInView＝false：不吞触摸——行
///   内按钮、右滑回复等其他消费方照常收到点按，
///   本识别器只做旁观触发；
/// - shouldRecognizeSimultaneouslyWith 恒真：不
///   与滚动 pan/行内识别器互斥排队，点按的成败由
///   识别器自身的移动容差决定（拖动超容差自动失
///   败、不会在滑动结束时误收键盘）。
///
/// 装配：零尺寸桥视图挂在 ScrollView 的 .back-
/// ground 位入树，自其层级 ascend 找 UIScrollView
/// 本体安装；ascend 不中时以窗口子树内帧吻合者兜
/// 底（两路都只认「包含桥视图且帧与其一致」的滚
/// 动视图，防误装到抽屉等其他滚动面）。识别器以
/// name 标记防重复安装（body 重建/桥视图重挂不
/// 叠装）。
struct ScrollViewTapDismissInstaller: UIViewRepresentable {
    /// 收键盘动作的既有通道（与旧祖先 tap 同一出
    /// 口：句柄直达输入舱文本视图 resign）
    let focusHandle: ComposerFocusHandle

    func makeUIView(
        context: Context
    ) -> TapDismissInstallerView {
        let view = TapDismissInstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onBlankTap = { [focusHandle] in
            focusHandle.dismiss()
        }
        return view
    }

    func updateUIView(
        _ uiView: TapDismissInstallerView,
        context: Context
    ) {
        uiView.onBlankTap = { [focusHandle] in
            focusHandle.dismiss()
        }
        uiView.installIfNeeded()
    }
}

/// 安装宿主视图兼识别器 delegate：本体随 SwiftUI
/// 桥存活，识别器的 target/delegate 均指本视图
/// （识别器由滚动视图持有、本视图由桥持有，环外
/// 无泄漏面；滚动视图重装/桥卸载时识别器随滚动
/// 视图释放）
final class TapDismissInstallerView: UIView,
    UIGestureRecognizerDelegate
{
    var onBlankTap: (() -> Void)?
    private weak var installedScrollView: UIScrollView?
    private var recognizer: UITapGestureRecognizer?

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        installIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    private var retryScheduled = false

    /// 定位底层滚动视图并安装（幂等：已装在同一滚
    /// 动视图上直接返回；滚动视图换人（装配重建）
    /// 时旧识别器随旧视图走、本视图在新视图上补装）。
    /// 首试在入窗/更新拍——彼时帧可能未定版，失败
    /// 时排一次主队列延迟重试（安装时机兜底、非
    /// 落定机制；装成即止、不循环）
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
        if installedScrollView === scrollView,
           recognizer != nil {
            return
        }
        if scrollView.gestureRecognizers?.contains(
            where: {
                $0.name == TapDismissInstallerView
                    .recognizerName
            }
        ) == true {
            installedScrollView = scrollView
            return
        }
        let tap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleBlankTap)
        )
        tap.name = Self.recognizerName
        tap.cancelsTouchesInView = false
        tap.delegate = self
        scrollView.addGestureRecognizer(tap)
        recognizer = tap
        installedScrollView = scrollView
    }

    static let recognizerName = "OneDayBlankTapDismiss"

    private func findHostingScrollView() -> UIScrollView? {
        // 主路：自本视图 ascend——背景桥视图在托管
        // 层级里位于滚动视图子树内
        var ancestor = superview
        var hops = 0
        while let current = ancestor, hops < 16 {
            if let scroll = current as? UIScrollView {
                return scroll
            }
            ancestor = current.superview
            hops += 1
        }
        // 兜底：背景桥与滚动视图是同父兄弟（背景
        // 在其后层）——ancend 链天然不中（验收轮
        // 43463400274 实证未装上）；改按「窗口内帧
        // 重叠面积最大」在 HostingScrollView 候选
        // 里选面：桥帧＝滚动视图帧（背景填充被修
        // 饰视图），重叠近全幅者即本体；要求重叠
        // ≥ 桥帧面积一半，防误装邻面
        guard let window else { return nil }
        let myFrame = convert(bounds, to: window)
        // 候选可嵌套（同页两面全帧滚动视图同帧并
        // 存，验收轮 census 实证）：先按重叠面积筛
        // 近全幅者，再取层级最深者——内容本体恒在
        // 内层，平局先到先得会装到外层壳上
        var candidates: [(view: UIScrollView, area: CGFloat)] = []
        func walk(_ view: UIView) {
            if String(describing: type(of: view))
                .contains("HostingScrollView"),
               let scroll = view as? UIScrollView,
               scroll.bounds.width > 300 {
                let frame = scroll.convert(
                    scroll.bounds, to: window
                )
                let overlap = frame.intersection(myFrame)
                let area = overlap.isNull
                    ? 0
                    : overlap.width * overlap.height
                candidates.append((scroll, area))
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)
        let myArea = myFrame.width * myFrame.height
        guard let maxArea = candidates.map({ $0.area }).max(),
              myArea > 0, maxArea >= myArea * 0.5
        else { return nil }
        func depth(of view: UIView) -> Int {
            var d = 0
            var current = view.superview
            while current != nil {
                d += 1
                current = current?.superview
            }
            return d
        }
        return candidates
            .filter { $0.area >= maxArea * 0.99 }
            .max(by: { depth(of: $0.view) < depth(of: $1.view) })
            .map { $0.view }
    }

    @objc private func handleBlankTap() {
        onBlankTap?()
    }

    // MARK: - UIGestureRecognizerDelegate（官方仲裁口径）

    /// 触摸过滤：落在任何 UITextView 子树内的触摸
    /// 不进本识别器（正文/链接/选字的领地）；其余
    /// （行间、留位带、气泡非文字区、代码块等）放行
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    /// 与滚动视图自家 pan 及其余识别器同时识别：
    /// 不排队、不互斥；点按成败由自身移动容差决定
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith
            otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
