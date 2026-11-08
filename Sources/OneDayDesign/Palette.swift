import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 语义令牌（自礼记 Palette 移植，换蓝色令牌表）
// 组件只许引用这里的语义令牌，不写裸 hex。
//
// 色彩纪律（沿礼记 v3 大厂口径）：90% 中性打底，强调色只有一个
// 色族、面积受控。OneDay 的强调色族＝蓝：以腾讯蓝 #0052D9 为基色
// 派生整套（品牌主色 / 填充深档 / 浅染），中性色与品牌同色温。
// 深浅两套值均逐对验过对比度 ≥4.5:1（文字对 pageBG / surface /
// primaryTint；白字对 primaryFill），验算表见 docs/M1-NOTES.md。

public extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
#endif

public enum Palette {
    /// 动态色工厂：浅/深两套值，系统切换外观时自动生效
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }))
        #else
        return Color(hex: light)
        #endif
    }

    // —— 界面语义令牌（蓝色令牌表：浅 #0052D9 基色派生 / 深档提亮保对比） ——
    /// 页面底（带蓝色温的微染中性）
    public static let pageBG = dyn(0xF2F3F5, 0x10151C)
    /// 容器底（卡片、列表行）
    public static let surface = dyn(0xFFFFFF, 0x1A212B)
    /// 主文字
    public static let ink = dyn(0x1F2329, 0xEDF1F6)
    /// 次文字
    public static let sub = dyn(0x5F6570, 0x9AA6B5)
    /// 描边线（装饰线，不承载文字，无对比度要求）
    public static let line = dyn(0xE3E6EB, 0x2A3340)
    /// 品牌主色：文字/图标强调。浅色为腾讯蓝本体 #0052D9；
    /// 深色提亮为 #6BA3FF（深底上保 ≥4.5:1，本体蓝在深底只有约 3:1）
    public static let primary = dyn(0x0052D9, 0x6BA3FF)
    /// 品牌填充深档：一切「强调底＋白字」填充（主按钮、发送键）
    public static let primaryFill = dyn(0x003CAB, 0x0052D9)
    /// 品牌浅染：选中态衬底、标签底、用户消息气泡底
    public static let primaryTint = dyn(0xEAF1FE, 0x1B2B4D)

    // —— 反馈语义令牌（沿礼记口径：取系统语义色，视图禁止裸用 .red/.green） ——
    /// 成功 / 在线
    public static let success = Color.green
    /// 警告 / 降级
    public static let warning = Color.orange
    /// 危险 / 错误 / 离线
    public static let danger = Color.red

    /// 平台/网关状态字符串 → 状态色：connected/running/ok 为绿，
    /// error/failed/disconnected 为红，其余（未知、未配置）为次文字。
    public static func stateColor(_ state: String?) -> Color {
        switch state?.lowercased() {
        case "connected", "running", "ok", "ready":
            return success
        case "error", "failed", "disconnected", "stopped":
            return danger
        case "degraded", "warning", "restarting":
            return warning
        default:
            return sub
        }
    }
}

// MARK: - 度量（沿礼记 LiqianMetrics 定版值）

public enum OneDayMetrics {
    /// 触摸目标下限 44pt
    public static let minTapTarget: CGFloat = 44
    /// 主表面卡片圆角
    public static let cardCorner: CGFloat = 18
    /// 一般控件圆角
    public static let controlCorner: CGFloat = 10
    /// 卡片内边距
    public static let cardPadding: CGFloat = 16
    /// 间距梯队：4/8/12/16/24/32 六档，栈间距与内边距一律走令牌
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingSM: CGFloat = 12
    public static let spacingM: CGFloat = 16
    public static let spacingL: CGFloat = 24
    public static let spacingXL: CGFloat = 32
}
