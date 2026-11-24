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

    /// 底条行高（圆钮/搜索胶囊 45 居中于 52 行盒——
    /// 2026-11-21 抽屉样板对齐包实测：控件 Ø45、控件
    /// 中心距屏底 64.2pt＝安全区 34＋底距 4＋行盒半高
    /// 26，行盒 52 与控件 45 两数同归本口径，见
    /// pkg-drawer-muse-look-delivery-20261121.md）
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

/// 抽屉卡几何定值单源（§313，横扫 A-02 收口）：圆角/
/// 纵向内嵌/柔影/推开量四组值此前散在容器现算与
/// DrawerMotion 白名单里逐代拟合追加，自此只许出自
/// 本结构体一处，出处逐项注明；DrawerMotion 的同名
/// 白名单改为转发本处、容器 travel 改走 travel(
/// containerWidth:) 派生，不再有第二写点。
public enum DrawerCardGeometry {
    /// 推开量占容器宽比例：2026-11-21 抽屉样板对齐
    /// 包改 0.79——用户当日亲递 Muse 现行版真机截
    /// 图（402×874pt）两路独立量测互证：主面卡左直
    /// 边 x＝951px→抽屉宽 317.0pt、底栏对称布局反
    /// 推 317.5pt，占比 0.7886→取 0.79。第 78 条 D2
    /// 的 0.75（2026-11-14 录屏拟合 301pt）是旧版
    /// Muse 的数、被本量测覆盖；0.79 与第 78 条前
    /// 「旧版化石」同值纯属版本漂移往返，以用户现
    /// 行版实机截图为准（量测全表见 pkg-drawer-
    /// muse-look-delivery-20261121.md）。400 cap 口
    /// 径不变：无 cap
    public static let travelWidthFraction: CGFloat = 0.79
    /// 前景卡圆角定值：§202 对 Muse 参照图拟合 54.5pt
    /// （出处见 DrawerMotion.cardCornerRadius 注）；
    /// 第 78 条录屏复测等效 ≈57pt、同档不改
    public static let cornerRadius: CGFloat = 54.5
    /// 圆角一步到位阈值（S3）：progress 过此值半径直
    /// 接到定值、拖动期不插值
    public static let cornerStepProgress: CGFloat = 0.02
    /// 纵向内嵌定值（§202 K1）：开态前景卡上/下各内
    /// 嵌此值、整卡浮置
    public static let verticalInset: CGFloat = 2
    /// 深色卡面横向内缩定值（§351）：深色开态卡面
    /// 左缘右移此值、露出前景底色（Palette.drawer-
    /// Backdrop #191919）作接缝中间层——出处＝
    /// 2026-11-22 用户 Muse 真机视频（720×1566
    /// @30fps）定格量测：接缝三段台阶 #000000 →
    /// 中间带 lum≈24（≈#191919）宽约 28px（屏宽
    /// 720px＝402pt、≈1.79px/pt → 约 14–16pt）→
    /// 卡面 #2C2C2E；取 16pt。浅色无此层（接缝走
    /// §345 柔影）
    public static let darkCardLeadingInset: CGFloat = 16
    /// 柔影定值（§202 回宽）：radius 18（定版区间
    /// 16–20 取中值偏上）/x −4
    public static let shadowRadius: CGFloat = 18
    public static let shadowX: CGFloat = -4
    /// 柔影峰值 alpha（progress=1、浅色）：§202 定
    /// 0.22（区间 0.18–0.25）；深色归零（第 78 条
    /// D4：Muse 录屏深色帧段无可量测阴影）
    public static let shadowMaxOpacity: Double = 0.22

    /// 推开量派生：容器宽 × 0.75、无 cap（量测口径见
    /// travelWidthFraction 注）
    public static func travel(containerWidth: CGFloat) -> CGFloat {
        containerWidth * travelWidthFraction
    }
}
