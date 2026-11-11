import Foundation

/// 抽屉弹簧的 UIKit 对应参数（§156，抽屉 UIKit 容器
/// 专用）：OneDayDesign.MotionTokens.drawerSpring 是
/// SwiftUI Animation.interactiveSpring(response 0.34,
/// dampingFraction 0.86)（0.7.1 S7 定版），UIKit 的
/// UISpringTimingParameters 不吃 response/阻尼比口径，
/// 本枚举是两者的唯一换算口——response/ζ 在此与
/// DesignTokens 的定版值逐字对应，改一处必须同改另
/// 一处（单测以回算钉死等价关系）。
/// 换算（单位质量）：ω＝2π/response、k＝ω²、
/// c＝2ζω；回算 ζ＝c/(2√k)、response＝2π/√k 恒等。
public enum DrawerSpringTiming {
    /// 与 MotionTokens.drawerSpring 的 response 对应
    public static let response: CGFloat = 0.34
    /// 与 MotionTokens.drawerSpring 的 damping-
    /// Fraction 对应（0.86：无可见回弹）
    public static let dampingFraction: CGFloat = 0.86
    /// 松手吸附的动量投影时长：UIKit 手势无 SwiftUI
    /// 的 predictedEndTranslation，以「速度 × 本时长」
    /// 近似其外推增量后仍走 DrawerMotion.settleOpens
    /// 同一判定（判定口径不分家）
    public static let settleProjectionInterval: CGFloat = 0.22

    /// 弹簧刚度 k（质量恒 1）
    public static var stiffness: CGFloat {
        let omega = 2 * CGFloat.pi / response
        return omega * omega
    }

    /// 弹簧阻尼 c（质量恒 1）
    public static var damping: CGFloat {
        let omega = 2 * CGFloat.pi / response
        return 2 * dampingFraction * omega
    }
}
