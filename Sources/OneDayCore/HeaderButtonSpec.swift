import Foundation

/// 顶栏圆钮规格（0.3.3，DESIGN-V4 §18）：聊天页顶栏左
/// 右两钮（侧边栏／新建）共用这一份规格——圆直径与字形
/// 字号同进同出，不许两处各调各的（真机第 2 条：两钮此
/// 前各写 36/15、无令牌，字形在圆盘里显小且无从对账）。
///
/// 校准口径（2026-11-27 改版）：对齐 iOS 标准导航栏按钮
/// 尺寸 44pt（UIKit 标准常量、HIG 触摸目标下限）——旧值
/// 40 按 Muse 截图量测、已退役；字形字号按原比例同步调整
/// 至 22pt（字形/圆比保持 0.50）。视觉盘与命中域自此统一
/// 44pt，不再拆两档。数值由 HeaderButtonSpecTests 钉住。
public enum HeaderButtonSpec {
    /// 玻璃圆钮视觉直径（2026-11-27：40→44，对齐 iOS 标准）
    public static let diameter: CGFloat = 44
    /// 字形字号（与直径成对校准；字重 0.3.7 卡 19 改
    /// regular——§22.5 框架图标令牌，规格只管几何；
    /// 2026-11-27：20→22，保持字形/圆比 0.50）
    public static let glyphPointSize: CGFloat = 22
    /// 字形/圆比（校准带 0.45–0.55，Muse 量测 ≈0.48）
    public static var glyphRatio: CGFloat {
        glyphPointSize / diameter
    }
}
