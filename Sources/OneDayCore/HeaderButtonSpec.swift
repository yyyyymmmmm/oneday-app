import Foundation

/// 顶栏圆钮规格（0.3.3，DESIGN-V4 §18）：聊天页顶栏左
/// 右两钮（侧边栏／新建）共用这一份规格——圆直径与字形
/// 字号同进同出，不许两处各调各的（真机第 2 条：两钮此
/// 前各写 36/15、无令牌，字形在圆盘里显小且无从对账）。
///
/// 校准口径：以用户提供的 Muse 本体截图量测——其顶栏
/// 汉堡钮字形高约占圆直径的 0.48；本规格取字形/圆比
/// 0.50（20/40）落在同一观感带。直径 40 与 HIG 触摸目
/// 标下限 44 的关系：玻璃圆钮的视觉盘 40、实际命中由
/// Button 承载（周围间距补足），与 Muse 本体顶栏钮的
/// 视觉尺寸同档。数值由 HeaderButtonSpecTests 钉住。
public enum HeaderButtonSpec {
    /// 玻璃圆钮视觉直径
    public static let diameter: CGFloat = 40
    /// 字形字号（semibold，与直径成对校准）
    public static let glyphPointSize: CGFloat = 20
    /// 字形/圆比（校准带 0.45–0.55，Muse 量测 ≈0.48）
    public static var glyphRatio: CGFloat {
        glyphPointSize / diameter
    }
}
