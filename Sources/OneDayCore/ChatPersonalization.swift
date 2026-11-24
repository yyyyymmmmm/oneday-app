import CoreGraphics
import Foundation

/// 聊天个性化（台账 179，OB-I1；DESIGN §391）：气泡样式
/// 与聊天背景做成可选开关——默认恒为自家风格定版（台账
/// 146/188/197），用户在外观页主动改才变。智能体专属
/// backdrop 未在本包落地（缺口登记见 §391：需逐智能体
/// 资产与身份 plumbing，不在本包硬造）。
///
/// 本枚举只管「选了哪档」的值与几何/色值口径；持久化键
/// 归 AppearanceStorageKeys、读写口归 AppearancePrefer-
/// ences（与主题/形象档同制），呈现层（Palette）现读现解。

/// 气泡样式三档：定版＝现行圆角原值（22/22/7，与
/// OneDayMetrics 旧常量逐值相同，未设置时呈现零变化）
public enum ChatBubbleStyle: String, CaseIterable, Equatable, Sendable {
    /// 自家定版（默认）
    case standard
    /// 圆润：三角放大
    case rounded
    /// 利落：三角收紧
    case squared

    public var displayName: String {
        switch self {
        case .standard: return "定版"
        case .rounded: return "圆润"
        case .squared: return "利落"
        }
    }

    /// 用户泡圆角
    public var bubbleCorner: CGFloat {
        switch self {
        case .standard: return 22
        case .rounded: return 28
        case .squared: return 12
        }
    }

    /// 助手泡圆角（定版与用户泡同值，沿 0.6.1 双泡同圆角）
    public var assistantBubbleCorner: CGFloat {
        bubbleCorner
    }

    /// 气泡尾角
    public var bubbleTailCorner: CGFloat {
        switch self {
        case .standard: return 7
        case .rounded: return 10
        case .squared: return 4
        }
    }
}

/// 聊天背景三档：默认＝现行 chatSurface 原值；另两档只
/// 换聊天页底色（冷中性灰阶，浅/暗成对在 Palette 侧），
/// 抽屉/卡面等共用 chatSurface 的面不跟随（各守定版）
public enum ChatBackgroundStyle: String, CaseIterable, Equatable, Sendable {
    /// 自家定版（默认，与 Palette.chatSurface 同值）
    case standard
    /// 雾灰：比定版深一档的浅灰
    case mist
    /// 石板：再深一档
    case slate

    public var displayName: String {
        switch self {
        case .standard: return "默认"
        case .mist: return "雾灰"
        case .slate: return "石板"
        }
    }
}
