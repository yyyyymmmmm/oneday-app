import Foundation

/// 抽屉几何（0.3.6，DESIGN-V4 §21）：拖拽越界橡皮
/// 筋——界内 1:1 跟手由调用方钳制，本函数只处理越
/// 界量：按 Apple 材质口径的常用橡皮筋公式渐进衰
/// 减 effective = (x · W · c) / (W + c · x)，c =
/// 0.55；x→∞ 时趋近 W（永不超过一个容器宽），x→0
/// 时斜率趋近 c。审查备忘录 E-3 立项、0.3.6 落地
/// 于抽屉开合拖拽（此前为硬钳制、边界撞墙感）。
public enum DrawerGeometry {
    public static let rubberBandConstant: CGFloat = 0.55

    public static func rubberBand(
        overshoot: CGFloat, containerWidth: CGFloat
    ) -> CGFloat {
        let x = max(overshoot, 0)
        guard containerWidth > 0, x > 0 else { return 0 }
        return (x * containerWidth * rubberBandConstant)
            / (containerWidth + rubberBandConstant * x)
    }
}
