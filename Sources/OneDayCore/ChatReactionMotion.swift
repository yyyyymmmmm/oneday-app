import SwiftUI

// MARK: - 反应动画参数表（大厂对位版）

/// 反应动画参数统一管理（DESIGN 反应系统大厂对位）：
/// 区分两类动画——①浮排菜单呈现（ReactionBarMotion
/// 既有参数，照抄 Exyte Chat 源码）②反应自动出现
/// （pill/badge 从无到有的入场，本文件新增）。自动
/// 出现动画参数对标 iOS 典型 spring 值（response
/// 0.55／dampingFraction 0.825，来源：Apple WWDC
/// 2023 spring 动画讲座、iOS Animations by Tutorials
/// 第 4 章、GetStream swiftui-spring-animations 研
/// 究），效果＝轻量弹性入场、不干扰阅读
public enum ChatReactionMotion {

    // MARK: 自动出现动画（pill/badge 入场）

    /// pill/badge 入场 spring 参数（iOS 典型值）：
    /// response 0.55（弹簧响应速度）、damping 0.825
    /// （阻尼比，控制过冲与振荡）——来源：Apple 自家
    /// 系统动画普遍采用此范围、GetStream/swiftui-
    /// spring-animations 研究验证、WWDC 2023-10158
    /// 讲座推荐值。效果：温和弹性、不过度振荡、符合
    /// iOS HIG 流畅感
    public static var appearanceSpring: Animation {
        .spring(response: 0.55, dampingFraction: 0.825)
    }

    /// 入场起始 scale（pill/badge 从此值放大到 1.0）
    public static let appearanceStartScale: CGFloat = 0.5

    /// 入场起始 opacity（pill/badge 从此值淡入到 1.0）
    public static let appearanceStartOpacity: Double = 0

    // MARK: 浮排菜单动画（ReactionBarMotion 既有参数）

    /// 浮排菜单基准时长 D（Exyte animationDuration 默认）
    public static let menuDuration: CGFloat = 0.3

    /// 浮排菜单段间时序点 0.33D（Exyte 状态机推进点）
    public static var menuStageDelay: CGFloat { menuDuration / 3 }

    public static var menuBackgroundIn: Animation {
        .easeInOut(duration: menuDuration)
    }

    public static var menuMessageIn: Animation {
        .easeInOut(duration: menuDuration * 1.33)
    }

    public static var menuChromeIn: Animation {
        .bouncy(duration: menuDuration)
    }

    public static var menuChromeOut: Animation {
        .snappy(duration: menuDuration * 0.66)
    }

    public static var menuBackgroundOut: Animation {
        .easeOut(duration: menuDuration)
            .delay(menuDuration / 3)
    }

    /// 浮排收起全程（背景淡出走完）后才摘会话的等待
    public static var menuDismissalTotal: CGFloat {
        menuDuration / 3 + menuDuration + 0.02
    }
}
