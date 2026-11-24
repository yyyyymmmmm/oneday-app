import OneDayCore
import SwiftUI

/// 中枢卡片底层处理进度（§502 灰底根治）：0–1 共
/// 享持有者，值由 HubCardTransition.underlay-
/// Strength 派生。写端＝HubCardHost（入场/拖动/飞
/// 出/弹回四态与卡片同弹簧、同事务写）；读端＝呈
/// 现方壳层 HubUnderlayTreatment（对聊天页本体挂
/// 模糊＋压暗）；ChatView 呈现路径注入两端、关页
/// 落账时同事务归零。实例由 AppState 单例持有
/// （optionsOverlay 同式），全 App 一份
@Observable
final class HubCardProgress {
    var strength: CGFloat = 0
}

/// 中枢卡片呈现宿主（DESIGN-V4 §502）：fullScreen-
/// Cover 内的整页卡片容器——与 TopAnchoredPanel 同
/// 族同纪律（呈现组件单源、数值走令牌/量测、平台弹
/// 簧），几何与手势不同故不共用本体。职责：
/// - 入场：缩放 0.75→1.0＋上浮 34pt、弹簧沉降
///   （量测 §2.7：≈0.36s、小过冲）；
/// - 拖动：方向锁仲裁（横向主导归卡片、纵向归内
///   层列表滚动，量测 §2.8），卡片平移＋缩放＋圆
///   角＋阴影实时跟手，底层处理进度同步写共享持
///   有者、由呈现方壳层对聊天页本体压暗＋强模糊
///   （量测 §2.5；灰底根治——宿主内无合成背板，
///   审计 nav-gesture-coverage-audit 问题一）；
///   横向锁定时冻结内层滚动；
/// - 松手：投影判定（Core HubCardTransition）→
///   沿拖动方向飞出关闭（≈0.43s）或弹簧弹回；
/// - ✕ 关闭：内容经 requestClose 回调走同款飞出。
/// 全部数值口径走 Core HubCardTransition 单源，本
/// 件不自拼近似值。飞出走完才回调 onDismissed 真
/// 关闭（宿主以无动画事务落 showHub，防系统 cover
/// 转场二次抢镜、即 §472 迟滞的结构性退场）。
struct HubCardHost<Content: View>: View {
    /// 底层处理进度共享持有者（本件为写端）
    let progress: HubCardProgress
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
            card(size: size, scale: scale)
        }
        .ignoresSafeArea()
        .presentationBackground(.clear)
        .onAppear {
            // 灰底根治：底层进度与入场同弹簧回零——
            // presentHub 已在盖落前置满格，此处先补同
            // 值（直达本宿主的装配路径不漏帧）再动画
            progress.strength = HubCardTransition
                .underlayStrength(forScale: 0.75)
            withAnimation(Self.entrySpring) {
                entered = true
                progress.strength = 0
            }
        }
        .onDisappear {
            // 收口兜底：宿主退场时底层进度必归零（正
            // 常路径已由 ChatView 关页落账同事务归零，
            // 此处防异常拆解留糊/留暗）
            progress.strength = 0
        }
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

    // MARK: - 底层处理（灰底根治后不在本件）

    // 底层形态改治本体：本件只写进度（HubCard-
    // Progress），呈现方壳层 HubUnderlayTreatment
    // 据此对聊天页本体挂模糊＋压暗。旧合成背板
    // （ultraThinMaterial＋黑罩替身）整幅盖换聊天
    // 页、饱和后只剩均匀灰场＝用户真机所见灰底，
    // 审计问题一定案退役、本件不再造任何底层视图

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
                    // 灰底根治：底层进度跟手写共享持有
                    // 者（壳层据此糊化＋压暗聊天页本体）
                    progress.strength = HubCardTransition
                        .underlayStrength(forScale:
                            HubCardTransition.scale(
                                forDeltaX: value.translation.width))
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
                            progress.strength = 0
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
            // 灰底根治：飞出段底层进度随卡同弹簧升满
            // （飞出终点缩放口径）；completion 落真关
            // 闭时由 ChatView 同事务归零、本体同帧复原
            progress.strength = HubCardTransition
                .underlayStrength(forScale: Self.flyOutScale)
        } completion: {
            onDismissed()
        }
    }
}

/// 呈现方壳层底层处理包装（§502 灰底根治）：包住
/// TabView（底栏同层、随本体同步进出），按共享进
/// 度对**本体**挂强模糊＋压暗——拖动时露出的就是
/// 聊天页自己的糊化形态，不再有合成背板替身。进
/// 度每帧变化只重算本包装自身：内容以 closure 传
/// 入、子视图输入不变则其 body 不重跑（ChatView
/// 大 body 不随拖动帧重演）。动画不在本件自拼：
/// 写端各态写入时所带事务/弹簧即本件的动画来源
struct HubUnderlayTreatment<Content: View>: View {
    let progress: HubCardProgress
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .blur(radius: HubCardTransition
                .underlayBlurRadius(
                    forStrength: progress.strength))
            .brightness(HubCardTransition
                .underlayBrightnessDelta(
                    forStrength: progress.strength))
    }
}
