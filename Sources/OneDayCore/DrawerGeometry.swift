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

    // MARK: - 底条钉底（0.3.8 第 22 条）

    /// 底条行高（圆钮 44 与搜索胶囊同高带，行盒 52）
    public static let bottomBarRowHeight: CGFloat = 52
    /// 底条下边距＝安全区底 inset＋4：底条落进原底栏
    /// 坑位（第 3 条抽屉开时底栏隐藏，坑位空出）
    public static func bottomBarBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom + 4
    }

    /// 底条中心距屏幕顶部的比例（量测口径）：852pt 屏、
    /// 安全区 34 时＝(852 − 34 − 4 − 26) / 852 ≈ 92.5%，
    /// 与 Muse 实测条中心 92.5% 对齐（0.3.7 实测旧值
    /// 77.5%、条下约 170pt 死白，本轮主犯）
    public static func bottomBarCenterFraction(
        screenHeight: CGFloat, safeAreaBottom: CGFloat
    ) -> Double {
        guard screenHeight > 0 else { return 0 }
        let fromBottom = bottomBarBottomPadding(safeAreaBottom: safeAreaBottom)
            + bottomBarRowHeight / 2
        return Double((screenHeight - fromBottom) / screenHeight)
    }
}
