import Foundation

/// 中枢卡片转场数学与裁决（DESIGN-V4 §502）：交互式
/// 卡片转场的全部数值口径收在此一处纯函数——缩放只
/// 由横向位移 Δx 驱动、圆角随拖动渐入、松手判定走
/// 「位移＋速度投影」、呈现降级走 Reduce Motion 裁
/// 决。数值全部出自参照录屏量测正本（hub-card-
/// presentation-spec-20261124 §2），呈现层只许问本
/// 件、不许各面自拼近似值。
public enum HubCardTransition {

    /// 缩放斜率（量测拟合 §2.3）：每右拖 1pt 缩小
    /// 0.0021，四回合互证、散布 ±0.04
    public static let scaleSlope: CGFloat = 0.0021

    /// 缩放下限（量测完成飞出末段 ≈0.48、拖动态实
    /// 测最低 0.63；下限取 0.55 防拖动态过度缩小）
    public static let minScale: CGFloat = 0.55

    /// 卡片圆角（量测 §2.4：拖动态 ≈57pt，与外壳
    /// 圆角既有量测对账一致；iOS 连续曲率）
    public static let maxCornerRadius: CGFloat = 57

    /// 圆角渐入行程：拖动 24pt 内由 0 渐入至满值
    /// ——量测 §2.4 在 Δx≈33pt（缩放 0.93）处圆角
    /// 属性已 ≈57pt，故渐入必须快于缩放行程；初值
    /// 线性、真机调（施工图 §6 口径）
    public static let cornerRadiusRamp: CGFloat = 24

    /// 松手完成阈值：投影位移 ≥ 屏宽 50%（量测
    /// §2.6：306px 慢拖取消 vs 312px 快拖完成，投
    /// 影模型与两回合均自洽）
    public static let finishProjectionFraction: CGFloat = 0.5

    /// 方向锁阈值：主导分量超过 10pt 才定锁（量
    /// 测 §2.8 仲裁：横向主导归卡片、纵向归列表）
    public static let directionLockThreshold: CGFloat = 10

    /// 底层压暗上限：黑罩不透明度 0.20 ≈ 亮度
    /// ×0.80（量测 §2.5：压暗至 0.77–0.82×）
    public static let underlayMaxDimOpacity: Double = 0.20

    /// 卡片缩放：只认右向 Δx（关闭方向），左向与
    /// 纵向不驱动缩放（量测 §2.3：纵向拖缩放 ≈1）
    public static func scale(forDeltaX dx: CGFloat) -> CGFloat {
        let shrink = scaleSlope * max(0, dx)
        return min(1, max(minScale, 1 - shrink))
    }

    /// 圆角：静止 0、拖动开始即快速渐入至 57pt
    public static func cornerRadius(forDeltaX dx: CGFloat) -> CGFloat {
        let t = min(1, max(0, dx) / cornerRadiusRamp)
        return maxCornerRadius * t
    }

    /// 底层强度（0–1）：由卡片当前缩放反推——入
    /// 场（0.75 起）/拖动/飞出三态共用同一口径，
    /// 缩放回到 1 即归零
    public static func underlayStrength(forScale scale: CGFloat) -> CGFloat {
        min(1, max(0, (1 - scale) / 0.25))
    }

    /// 底层压暗罩不透明度（亮度 ≈ 1 − 本值）
    public static func underlayDimOpacity(forScale scale: CGFloat) -> Double {
        underlayMaxDimOpacity * Double(underlayStrength(forScale: scale))
    }

    /// 松手判定（投影模型）：predictedEndTransla-
    /// tion.x 已含速度投影，与屏宽 50% 比
    public static func shouldFinish(
        predictedEndX: CGFloat, screenWidth: CGFloat
    ) -> Bool {
        guard screenWidth > 0 else { return false }
        return predictedEndX >= screenWidth * finishProjectionFraction
    }

    /// 拖动方向锁（量测 §2.8）：未锁定时按主导分
    /// 量定锁、锁定后本手势内不再翻转
    public enum DragDirection: Equatable {
        case undecided
        case horizontal
        case vertical
    }

    public static func classifyDrag(
        translation: CGSize, current: DragDirection
    ) -> DragDirection {
        if current != .undecided { return current }
        let ax = abs(translation.width)
        let ay = abs(translation.height)
        guard max(ax, ay) > directionLockThreshold else {
            return .undecided
        }
        return ax >= ay ? .horizontal : .vertical
    }

    /// 卡级拖动让行裁决（H1，呈现与导航手势审计
    /// 2026-11-24 问题二）：卡内任一导航栈已下钻
    /// （深度 >1）时，右滑先归卡内 pop、卡片关
    /// 卡手势全程让行；全卡回到根层才轮到关卡。
    /// 深度事实由宿主在手势起手一拍自层级采集
    /// （抽屉门 D 同源口径：层级内最大导航深度）
    public static func allowsCardDrag(
        innerStackDepth: Int
    ) -> Bool {
        innerStackDepth <= 1
    }
}

/// 中枢卡片呈现裁决（§502，照 ZoomTransitionPolicy
/// 先例）：Reduce Motion 开启时位移/缩放类转场降级
/// 为标准呈现（系统 cover＋✕ 关闭、无手势变形）；
/// 呈现层只许问本件。
public enum HubCardDecision: Equatable {
    /// 交互式卡片转场（手势跟手＋弹簧收尾）
    case card
    /// 标准呈现（系统默认 cover 转场）
    case standard
}

public enum HubCardPolicy {
    public static func decide(
        reduceMotion: Bool
    ) -> HubCardDecision {
        reduceMotion ? .standard : .card
    }
}
