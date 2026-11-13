import SwiftUI
import UIKit

/// 滚动边缘效果注册（§210，2026-11-13，用户 21:39
/// 验收口径）：聊天页上下条区改「内容驱动」——条下
/// 无内容时与页面背景同色不可见、有内容滚过时才朦
/// 胧。实现走 iOS 26 系统边缘效果的正道注册通道
/// （WWDC25 Session 284《Build a UIKit app with
/// the new design》：`UIScrollEdgeElementContainer-
/// Interaction` 注册到覆盖滚动视图边缘的容器上、效
/// 果由系统按内容滚过与否自适应溶解），取代 §200
/// 三处常驻系统材质底衬——材质片与内容无关恒定渲
/// 染、静止态自成色带（定因探针 EdgeEffectProbe-
/// Tests 双态采样：顶带静止色差浅 4／深 39、舱带
/// 浅 14／深 19、坞带浅 4／深 19；消融后顶带→1、
/// 坞带→0，系统边缘效果本体静止≈不可见）。
///
/// ## 三个注册点（与 WWDC 原式同构）
/// - 顶缘：interaction 直接挂顶簇宿主视图（TopBar-
///   GuideHostController 的 barHost.view——紧凑容
///   器、后代玻璃即效果形状）；状态栏带由列表自身
///   的顶缘效果（ChatView .scrollEdgeEffectStyle
///   (.soft, for: .top)）覆盖（消融臂实证：无注册
///   时该带内容亦被溶解、静止色差 1）。
/// - 底缘：interaction 挂舱带容器（EdgeBandCon-
///   tainerView，§200/A2 的卡段几何原样保留、只换
///   机制：透明容器＋全幅透明后代作形状质量）；舱
///   宿主视图本体是全帧透传层、不合「紧凑容器」
///   形态，故不直接挂它。
/// - 坞：UITabBar 是系统条——其自身玻璃与自动边
///   缘效果即正道，不再垫任何自家片（§200 坞底衬
///   退役）。
///
/// ## 纪律
/// - 样式仍由列表的 .scrollEdgeEffectStyle(.soft)
///   单点承（样式挂滚动视图的 edge effect、不挂
///   interaction——公开文档口径）；本文件只注册、
///   不设样式、不留位、不碰栏位几何（§193–§195
///   冻结口径零改动）。
/// - 不自绘渐变/擦淡（§173 红线）、不用 variable-
///   Blur 私有 API；注册容器一律透明、不接命中。

/// 聊天列表 UIScrollView 本体的交接句柄：列表内锚
/// 点视图上行祖先链登记本体，两宿主在离散事件/布
/// 局拍按指针比对把各自 interaction 的 scrollView
/// 对齐现值（与 ComposerFocusHandle 同式的被动登
/// 记匣：不观察、不回写 SwiftUI 状态、无失效链）
final class ChatListScrollViewHandle {
    weak var scrollView: UIScrollView?

    func register(_ scrollView: UIScrollView) {
        if self.scrollView !== scrollView {
            self.scrollView = scrollView
        }
    }
}

/// 登记锚本体：坐在列表内容栈一角（ChatView 以
/// background 挂 0 帧），入层级即沿祖先链找首个
/// UIScrollView 登记进句柄——祖先链首个滚动视图
/// 恒是聊天列表本体（锚不在任何气泡内层滚动区
/// 里）。纯登记：透明、不接命中、不占布局
final class ChatListScrollAnchorView: UIView {
    var handle: ChatListScrollViewHandle?

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        resolve()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolve()
    }

    func resolve() {
        guard let handle else { return }
        var node = superview
        while let current = node {
            if let scrollView = current as? UIScrollView {
                handle.register(scrollView)
                return
            }
            node = current.superview
        }
    }
}

/// 登记锚的 SwiftUI 桥（同上）
struct ChatListScrollAnchor: UIViewRepresentable {
    let handle: ChatListScrollViewHandle

    func makeUIView(
        context: Context
    ) -> ChatListScrollAnchorView {
        let view = ChatListScrollAnchorView()
        view.handle = handle
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(
        _ view: ChatListScrollAnchorView, context: Context
    ) {
        view.handle = handle
        view.resolve()
    }
}

/// 舱带容器（§210 底缘注册点）：透明视图＋全幅透明
/// 后代（给效果一份形状质量，WWDC 口径后代形状决
/// 定效果范围）＋一只底缘 interaction；几何由宿主
/// 约束决定（A2 卡段，本类不管）。绑定按指针比对
/// 幂等——宿主在离散事件/布局拍反复调 bind 即可
final class EdgeBandContainerView: UIView {
    private let interaction =
        UIScrollEdgeElementContainerInteraction()
    private weak var boundScrollView: UIScrollView?

    init(edge: UIRectEdge) {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        let filler = UIView()
        filler.backgroundColor = .clear
        filler.isUserInteractionEnabled = false
        filler.frame = bounds
        filler.autoresizingMask = [
            .flexibleWidth, .flexibleHeight,
        ]
        addSubview(filler)
        interaction.edge = edge
        addInteraction(interaction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 把底缘效果绑定到列表本体（指针未变即无操作）
    func bind(scrollView: UIScrollView) {
        guard boundScrollView !== scrollView else { return }
        boundScrollView = scrollView
        interaction.scrollView = scrollView
    }

    /// 自述/测试定位口：注册的 interaction 本体
    var traceInteraction:
        UIScrollEdgeElementContainerInteraction { interaction }
}
