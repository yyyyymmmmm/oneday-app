import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 语义令牌（v2 定版，见 docs/DESIGN-V2.md §3.3）
// 组件只许引用这里的语义令牌，不写裸 hex。
//
// 色彩改「双原色推导」（学 Hermes Dashboard 的 color-mix 纪律）：
// 原色只有墨与信号蓝，其余面、线、染按百分比关系成套。表面保持
// 近中性（蓝味只在色温层），蓝色只活在强调与每屏唯一的时刻里。
// 文字三角色对 pageBG/surface 逐对验算 ≥4.5:1（定版文档 §3.3）。

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

    // —— 表面（近中性，只差一级） ——
    /// 页面底：近中性纸色
    public static let pageBG = dyn(0xF7F8FA, 0x0E1116)
    /// 分组容器面
    public static let surface = dyn(0xFFFFFF, 0x171B21)
    /// 字段面：比容器再降一级（输入字段、代码块）
    public static let fieldFill = dyn(0xF1F3F6, 0x1E242C)

    // —— 文字三角色 ——
    /// 主文字
    public static let ink = dyn(0x191D23, 0xEDF0F4)
    /// 次文字
    public static let inkSecondary = dyn(0x47525F, 0xA9B3BF)
    /// 弱文字：只用于元信息（计数、时间、占位性说明）
    public static let inkMuted = dyn(0x66727F, 0x7E8894)

    /// 发丝线：墨色低 alpha 推导（浅 8% / 深 12%），不用固定灰，
    /// 两套外观下都保持「看得见的线、不是一道杠」（Pro Rules）。
    public static var hairline: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor(dynamicProvider: { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(hex: 0xEDF0F4).withAlphaComponent(0.12)
            }
            return UIColor(hex: 0x191D23).withAlphaComponent(0.08)
        }))
        #else
        return Color(hex: 0x191D23, alpha: 0.08)
        #endif
    }

    // —— 强调（主题色，0.2.1 起由 AccentStore 驱动，五款可选、
    // 默认腾讯蓝；每屏至多一个时刻＋关键动作的纪律不变） ——
    /// 品牌主色：文字/图标强调，随当前主题
    public static var primary: Color {
        let values = AccentStore.shared.theme.values
        return dyn(values.0, values.1)
    }
    /// 品牌填充：强调底＋白字（主按钮、发送键），随当前主题
    public static var primaryFill: Color {
        let values = AccentStore.shared.theme.values
        return dyn(values.2, values.3)
    }
    /// 品牌浅染：用户气泡、选中衬底，随当前主题
    public static var primaryTint: Color {
        let values = AccentStore.shared.theme.values
        return dyn(values.4, values.5)
    }

    // —— 反馈语义（成套降饱和，不用系统纯色） ——
    /// 成功 / 在线
    public static let success = dyn(0x1E8E4F, 0x45B878)
    /// 警告 / 降级
    public static let warning = dyn(0xA85B0A, 0xD98E32)
    /// 危险 / 错误 / 离线
    public static let danger = dyn(0xC62F24, 0xFF7A6B)

    /// 平台/网关状态字符串 → 状态色：connected/running/ok 为绿，
    /// error/failed/disconnected 为红，其余（未知、未配置）为弱色。
    /// 状态色永不单独传意，调用方必须同时呈现状态词（定版 §3.5）。
    public static func stateColor(_ state: String?) -> Color {
        switch state?.lowercased() {
        case "connected", "running", "ok", "ready":
            return success
        case "error", "failed", "disconnected", "stopped":
            return danger
        case "degraded", "warning", "restarting":
            return warning
        default:
            return inkMuted
        }
    }
}

// MARK: - 度量（定版 §3.2/§3.4：4pt 网格、圆角梯队、行高与对齐线）

public enum OneDayMetrics {
    /// 触摸目标下限 44pt
    public static let minTapTarget: CGFloat = 44

    // 圆角梯队（同心推导的锚点，内层走 CornerRadius.concentric）
    /// 分组容器
    public static let containerCorner: CGFloat = 18
    /// 输入字段 / 代码块
    public static let fieldCorner: CGFloat = 12
    /// 按钮
    public static let buttonCorner: CGFloat = 14
    /// 用户消息气泡
    public static let bubbleCorner: CGFloat = 22
    /// 输入区胶囊
    public static let composerCorner: CGFloat = 24
    /// 代码块（正文区内的内容面）
    public static let codeCorner: CGFloat = 10

    /// 页面左右边距（内容页）
    public static let pageGutter: CGFloat = 20
    /// 列表行图标槽宽：全页同一条对齐线
    public static let iconSlot: CGFloat = 28
    /// 发丝线内缩：边距 20＋槽 28＋间距 12
    public static let dividerInset: CGFloat = 60
    /// 内容行最小高
    public static let rowHeight: CGFloat = 52
    /// 主按钮高
    public static let primaryButtonHeight: CGFloat = 50

    /// 间距梯队：4/8/12/16/20/24/32/48，只许取梯队值
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingSM: CGFloat = 12
    public static let spacingM: CGFloat = 16
    public static let spacingL: CGFloat = 24
    public static let spacingXL: CGFloat = 32
    public static let spacingXXL: CGFloat = 48
}
