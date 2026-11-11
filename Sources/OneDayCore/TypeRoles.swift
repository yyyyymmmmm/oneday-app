import Foundation

/// 字阶角色表（0.23.0 立，视觉审计 G2）：全 App 文字只许
/// 走本表角色。Design 层 Font 扩展（FontRoles.swift）
/// 按本表落 SwiftUI 文本样式，本表是数值的单测把守面
/// （文本样式名／默认字号／字重档三项对账）。
/// 沿革：0.19/0.20 两轮照 Muse 真机图把抽屉/设置/文件
/// 三面钉成固定 pt（34/20/15），与 0.4.0「直用语义字
/// 阶」立宪形成双轨；0.23.0 把钉值映射回等值文本样式、
/// Dynamic Type 全 App 归一。
/// 0.24.0 口径变更（用户 2026-11-10 当日指令，覆盖
/// 0.22/0.23 的 Muse 量测口径）：以苹果 HIG Typography
/// 文本样式为唯一落档依据重排——行题/导航/分段/会话题
/// 一律 Body 17 regular，名字头 Title1 28 bold，分区头
/// 与时间戳 Footnote 13；rowTitleLSemi 退役（Semi 角色
/// 不留），rowTitle 由 Headline 改 Body（列表行题一律
/// regular，「不许乱加粗」令）。bold 全表只剩 screenName
/// 一处（大标题/身份名配额）；系统 Headline 语义位仅留
/// 非角色的定点（身份胶囊名/主按钮/空态题，逐处登记于
/// DESIGN-V4 §51）。
/// §157 例外（用户 2026-11-11 21:01 抽屉补充方案）：
/// 抽屉局部三角色 drawerNavTitle（Body medium）/
/// drawerRowTitle（Body regular）/drawerRowTitle-
/// Current（Body semibold）——只许抽屉内导航/频道/
/// 会话行消费，给「当前项适度加重、主要导航与次要
/// 行分层」的局部层级；全局 Body 与其余面的 regu-
/// lar 口径一字不变，本例外不许外溢到其他页面
public enum TypeRole: String, CaseIterable {
    case screenName
    case rowTitleL
    case rowTitle
    case bodyText
    case rowSubtitle
    case meta
    case sectionLabel
    case captionText
    case badgeOnly
    case drawerNavTitle
    case drawerRowTitle
    case drawerRowTitleCurrent

    /// SwiftUI 文本样式名（与 FontRoles 落法同名对账）
    public var textStyleName: String {
        switch self {
        case .screenName: return "title"
        case .rowTitleL, .rowTitle, .bodyText,
             .drawerNavTitle, .drawerRowTitle,
             .drawerRowTitleCurrent: return "body"
        case .rowSubtitle: return "subheadline"
        case .meta, .sectionLabel, .captionText: return "footnote"
        case .badgeOnly: return "caption"
        }
    }

    /// 默认字号（pt，Dynamic Type 默认档的系统值）
    public var defaultPointSize: CGFloat {
        switch self {
        case .screenName: return 28
        case .rowTitleL, .rowTitle, .bodyText,
             .drawerNavTitle, .drawerRowTitle,
             .drawerRowTitleCurrent: return 17
        case .rowSubtitle: return 15
        case .meta, .sectionLabel, .captionText: return 13
        case .badgeOnly: return 12
        }
    }

    /// 字重档名。0.24.0 起 bold 只许 screenName（Tit-
    /// le1，抽屉身份名＝大标题/身份名配额）；其余全
    /// regular——Semi 角色已退役、Headline 不再作行题
    /// §157：medium/semibold 两档只许抽屉局部三角色
    /// （见枚举头注），不许其他角色跟进
    public var weightName: String {
        switch self {
        case .screenName: return "bold"
        case .drawerNavTitle: return "medium"
        case .drawerRowTitleCurrent: return "semibold"
        default: return "regular"
        }
    }
}

/// WCAG 对比度纯函数（0.23.0，视觉审计 G1 的实算口
/// 径）：相对亮度按 WCAG 2.x 公式（sRGB 分量先做伽马
/// 展开），比值＝(L1＋0.05)/(L2＋0.05)。审计报告里的
/// 2.75:1／4.84:1／5.2:1 皆出自此式，单测以同式复算
/// Palette 角色对，防令牌值漂移后文字对比静默跌破线。
public enum WCAGContrast {
    public static func relativeLuminance(
        red: Double, green: Double, blue: Double
    ) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928
                ? c / 12.92
                : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red)
            + 0.7152 * channel(green)
            + 0.0722 * channel(blue)
    }

    /// 两色对比（入参为 sRGB 分量 0–1，不分主次）
    public static func ratio(
        foreground: (red: Double, green: Double, blue: Double),
        background: (red: Double, green: Double, blue: Double)
    ) -> Double {
        let l1 = relativeLuminance(
            red: foreground.red,
            green: foreground.green,
            blue: foreground.blue
        )
        let l2 = relativeLuminance(
            red: background.red,
            green: background.green,
            blue: background.blue
        )
        let (lighter, darker) = l1 >= l2 ? (l1, l2) : (l2, l1)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// hex 便捷口（0xRRGGBB）
    public static func ratio(
        hexForeground: UInt32, hexBackground: UInt32
    ) -> Double {
        func parts(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
            (
                red: Double((hex >> 16) & 0xFF) / 255.0,
                green: Double((hex >> 8) & 0xFF) / 255.0,
                blue: Double(hex & 0xFF) / 255.0
            )
        }
        return ratio(
            foreground: parts(hexForeground),
            background: parts(hexBackground)
        )
    }
}
