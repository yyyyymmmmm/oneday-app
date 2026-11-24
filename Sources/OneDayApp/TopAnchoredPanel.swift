import SwiftUI

/// 顶部锚定覆盖面板（§487）：呈现组件单源——覆盖式
/// 呈现（overlay＋自顶生长转场＋平台弹簧），底层页
/// 随同一下降＋压暗。首个消费面＝动态简报编辑器
/// （FeedView）；中枢卡片线（hub-card 同族呈现）后
/// 续复用本件，不许各面再自拼一套近亲实现。
///
/// 判定依据（brief-editor-presentation-audit
/// -20261124 §四）：iOS 无顶部锚定 sheet API（detent
/// 只管底部高度），顶部面板只能由平台标准件组合
/// （overlay／transition／spring）拼成——属判①原生
/// 可达，组合本身不是自创机制：动画曲线用平台弹
/// 簧、几何数值全抄参照录屏量测，不发明运动模型。
enum TopPanelMetrics {
    /// 卡顶边距屏顶（参照量测 62pt，紧贴状态栏下）
    static let cardTopInset: CGFloat = 62
    /// 卡高占屏高（参照量测 400pt／874pt）
    static let cardHeightFraction: CGFloat = 0.458
    /// 卡左右边距（参照量测 10pt）
    static let cardHorizontalInset: CGFloat = 10
    /// 卡圆角（参照量测 ≈31pt）
    static let cornerRadius: CGFloat = 31
    /// 卡内文字左右内距（参照量测：字面 x 55px −
    /// 卡缘 18px，换算 ≈20pt）
    static let contentHorizontalInset: CGFloat = 20
    /// 卡与卡外钮行间距（参照量测 ≈10pt）
    static let cardButtonGap: CGFloat = 10
    /// 钮行左右边距（参照量测 ≈14pt）
    static let buttonRowHorizontalInset: CGFloat = 14
    /// 双钮间距（参照量测 ≈19pt）
    static let buttonSpacing: CGFloat = 19
    /// 钮高（参照量测 ≈47pt）
    static let buttonHeight: CGFloat = 47
    /// 底层压暗：亮度 ×0.46 的等价黑罩不透明度
    static let dimOpacity: Double = 0.54
    /// 底层下推：页顶落点占屏高（参照量测 531pt／
    /// 874pt，下部约 39% 仍可见）
    static let pushFraction: CGFloat = 0.607

    /// 面板底：纯黑满屏（参照量测 RGB ≈(1,0,1)）
    static let backdrop = Color.black
    /// 卡与钮的底色：参照采样亮度 27／255 ≈ 白 0.11
    static let cardFill = Color(white: 0.11)
    /// 说明文字：参照字芯亮度 ≈155／255 ≈ 白 0.6
    static let textSecondary = Color.white.opacity(0.6)
    /// 保存钮未改字灰置标签：参照字芯亮度 ≈69／255
    /// ≈ 白 0.27（仅视觉档位，钮恒可用——§473 定版）
    static let saveIdleLabel = Color(white: 0.27)
    /// 错误回执文字（深底上的浅红，本面局部色）
    static let errorText = Color(red: 1.0, green: 0.45, blue: 0.42)

    /// 入场弹簧（DESIGN §487）：参照入场
    /// 0.20–0.23s、ease-out 无过冲。初值按对位
    /// 推算 response 0.30，2026-11-24 模拟器录屏
    /// 实测可见时长 ≈0.30s 超带，按比例回填
    /// 0.22／damping 0.92 定钉（录屏复测为准）
    static var enterAnimation: Animation {
        .spring(response: 0.22, dampingFraction: 0.92)
    }
    /// 退出弹簧：参照退出 0.17–0.20s。初值
    /// 0.25 实测 0.23s 在带内上沿，回填 0.21／
    /// damping 0.95 落带中段
    static var exitAnimation: Animation {
        .spring(response: 0.21, dampingFraction: 0.95)
    }
    /// Reduce Motion 降级：crossfade（§487，照
    /// ZoomTransitionPolicy 先例的降级口径）
    static var reduceMotionAnimation: Animation {
        .easeInOut(duration: 0.2)
    }

    static func cardHeight(screenHeight: CGFloat) -> CGFloat {
        screenHeight * cardHeightFraction
    }

    /// 面板总占位（卡顶→钮底）占屏高：验收口径
    /// 52.4% ±2%（参照量测，874pt 屏）
    static func totalOccupancyFraction(
        screenHeight: CGFloat
    ) -> CGFloat {
        (cardHeight(screenHeight: screenHeight)
            + cardButtonGap + buttonHeight) / screenHeight
    }
}

/// 顶部锚定面板呈现修饰符：挂在被呈现页根层。
/// 呈现进度由 isPresented 单状态驱动三件——面板自
/// 顶生长、底层页下推、底层压暗；面板内容由调用方
/// 按 TopPanelMetrics 自行组装（卡＋卡外钮行等）。
struct TopAnchoredPanelModifier<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    let panel: (CGSize) -> PanelContent

    private var activeAnimation: Animation {
        if reduceMotion {
            return TopPanelMetrics.reduceMotionAnimation
        }
        return isPresented
            ? TopPanelMetrics.enterAnimation
            : TopPanelMetrics.exitAnimation
    }

    func body(content: Content) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                TopPanelMetrics.backdrop
                    .opacity(isPresented ? 1 : 0)
                    .ignoresSafeArea()
                content
                    .overlay {
                        Color.black.opacity(
                            isPresented
                                ? TopPanelMetrics.dimOpacity : 0
                        )
                    }
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: isPresented
                                ? TopPanelMetrics.cornerRadius : 0,
                            topTrailingRadius: isPresented
                                ? TopPanelMetrics.cornerRadius : 0,
                            style: .continuous
                        )
                    )
                    .offset(
                        y: isPresented && !reduceMotion
                            ? geo.size.height
                                * TopPanelMetrics.pushFraction
                            : 0
                    )
                    .allowsHitTesting(!isPresented)
                    .accessibilityHidden(isPresented)
                if isPresented {
                    panel(geo.size)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .top
                        )
                        .padding(
                            .top, TopPanelMetrics.cardTopInset
                        )
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .top)
                                    .combined(with: .opacity)
                        )
                        .zIndex(1)
                }
            }
            .animation(activeAnimation, value: isPresented)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// 顶部锚定覆盖面板呈现（§487）：用法见
    /// TopAnchoredPanelModifier；panel 闭包拿到根层
    /// 尺寸（屏宽高），按 TopPanelMetrics 组装面板。
    func topAnchoredPanel<PanelContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder panel: @escaping (CGSize) -> PanelContent
    ) -> some View {
        modifier(
            TopAnchoredPanelModifier(
                isPresented: isPresented, panel: panel
            )
        )
    }
}
