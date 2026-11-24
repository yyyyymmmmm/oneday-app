import OneDayCore
import SwiftUI

/// 中枢卡片呈现宿主（DESIGN-V4 §502）：fullScreen-
/// Cover 内的整页卡片容器——与 TopAnchoredPanel 同
/// 族同纪律（呈现组件单源、数值走令牌/量测、平台弹
/// 簧），几何与手势不同故不共用本体。职责：
/// - 入场：缩放 0.75→1.0＋上浮 34pt、弹簧沉降
///   （量测 §2.7：≈0.36s、小过冲）；
/// - 拖动：方向锁仲裁（横向主导归卡片、纵向归内
///   层列表滚动，量测 §2.8），卡片平移＋缩放＋圆
///   角＋阴影实时跟手，底层背板同步压暗＋强模糊
///   （量测 §2.5）；横向锁定时冻结内层滚动；
/// - 松手：投影判定（Core HubCardTransition）→
///   沿拖动方向飞出关闭（≈0.43s）或弹簧弹回；
/// - ✕ 关闭：内容经 requestClose 回调走同款飞出。
/// 全部数值口径走 Core HubCardTransition 单源，本
/// 件不自拼近似值。飞出走完才回调 onDismissed 真
/// 关闭（宿主以无动画事务落 showHub，防系统 cover
/// 转场二次抢镜、即 §472 迟滞的结构性退场）。
struct HubCardHost<Content: View>: View {
    /// 飞出动画完成后的真关闭回调
    let onDismissed: () -> Void
    /// 内容构造：入参为「请求动画关闭」回调（✕ 接缝）
    @ViewBuilder let content: (
        _ requestClose: @escaping () -> Void
    ) -> Content

    @State private var dragTranslation: CGSize = .zero
    @State private var direction:
        HubCardTransition.DragDirection = .undecided
    @State private var entered = false
    @State private var closing = false
    @State private var closeTranslation: CGSize = .zero

    /// 入场弹簧（量测拟合 §2.7：response 0.35–0.45、
    /// 阻尼 0.75–0.85 一族）
    private static var entrySpring: Animation {
        .spring(response: 0.38, dampingFraction: 0.82)
    }
    /// 飞出弹簧（量测 §2.7：完成段 ≈0.43s）
    private static var flyOutSpring: Animation {
        .spring(response: 0.42, dampingFraction: 0.92)
    }
    /// 弹回弹簧（量测 §2.7：快攻击、短尾、小过冲）
    private static var cancelSpring: Animation {
        .interactiveSpring(response: 0.4, dampingFraction: 0.8)
    }
    /// 飞出终点缩放（量测 §2.7：飞出末段 ≈0.48）
    private static var flyOutScale: CGFloat { 0.5 }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let scale = currentScale
            ZStack {
                backdrop(scale: scale)
                card(size: size, scale: scale)
            }
            .onAppear {
                withAnimation(Self.entrySpring) {
                    entered = true
                }
            }
        }
        .ignoresSafeArea()
        .presentationBackground(.clear)
    }

    // MARK: - 变换口径（当前帧）

    private var currentScale: CGFloat {
        if closing { return Self.flyOutScale }
        let dragScale = HubCardTransition.scale(
            forDeltaX: dragTranslation.width)
        let entryScale = entered ? 1 : 0.75
        return entryScale * dragScale
    }

    private var currentOffset: CGSize {
        if closing { return closeTranslation }
        return CGSize(
            width: dragTranslation.width,
            height: dragTranslation.height + (entered ? 0 : 34))
    }

    private var currentCornerRadius: CGFloat {
        if closing || !entered {
            return HubCardTransition.maxCornerRadius
        }
        return HubCardTransition.cornerRadius(
            forDeltaX: dragTranslation.width)
    }

    // MARK: - 背板（底层聊天页的压暗＋强模糊替身）

    /// cover 背景透明、底层聊天页透出；背板以系统
    /// material 强模糊＋黑罩压暗模拟量测 §2.5 的底
    /// 层形态，强度由卡片缩放反推（入场/拖动/飞出
    /// 三态同口径），静止归零不可见
    private func backdrop(scale: CGFloat) -> some View {
        let strength = HubCardTransition.underlayStrength(
            forScale: scale)
        return ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(Double(strength))
            Color.black.opacity(
                HubCardTransition.underlayDimOpacity(
                    forScale: scale))
        }
        .allowsHitTesting(false)
    }

    // MARK: - 卡片本体

    private func card(size: CGSize, scale: CGFloat) -> some View {
        let strength = HubCardTransition.underlayStrength(
            forScale: scale)
        return content {
            beginClose(fromDrag: false, screenWidth: size.width)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(
            cornerRadius: currentCornerRadius,
            style: .continuous))
        .shadow(
            color: .black.opacity(0.18 * Double(strength)),
            radius: 24, x: 0, y: 10)
        .scaleEffect(scale)
        .offset(x: currentOffset.width, y: currentOffset.height)
        .scrollDisabled(direction == .horizontal || closing)
        .simultaneousGesture(dragGesture(screenWidth: size.width))
        .accessibilityIdentifier("hub.card")
    }

    // MARK: - 手势（方向锁仲裁＋投影判定）

    /// 坐标空间取 .global：卡片本体随拖平移，.local
    /// 会令 translation 随卡片位置漂移成反馈环
    private func dragGesture(screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard !closing else { return }
                direction = HubCardTransition.classifyDrag(
                    translation: value.translation,
                    current: direction)
                if direction == .horizontal {
                    dragTranslation = value.translation
                }
            }
            .onEnded { value in
                guard !closing else { return }
                if direction == .horizontal {
                    if HubCardTransition.shouldFinish(
                        predictedEndX:
                            value.predictedEndTranslation.width,
                        screenWidth: screenWidth) {
                        beginClose(
                            fromDrag: true,
                            screenWidth: screenWidth)
                    } else {
                        withAnimation(Self.cancelSpring) {
                            dragTranslation = .zero
                            direction = .undecided
                        }
                    }
                } else {
                    direction = .undecided
                }
            }
    }

    // MARK: - 关闭（飞出→真关闭）

    /// 飞出：沿拖动方向（✕ 关闭为纯右向）冲出右缘、
    /// 缩放续降至飞出档；动画逻辑完成才真关闭
    private func beginClose(
        fromDrag: Bool, screenWidth: CGFloat
    ) {
        guard !closing else { return }
        let startY = fromDrag ? dragTranslation.height : 0
        closeTranslation = CGSize(
            width: screenWidth * 1.15,
            height: startY * 1.8)
        withAnimation(
            Self.flyOutSpring,
            completionCriteria: .logicallyComplete
        ) {
            closing = true
        } completion: {
            onDismissed()
        }
    }
}
