import Foundation
import Observation
import SwiftUI

// MARK: - 主题令牌表（0.3.2 礼记化，DESIGN-V4 §17）
// 学礼记 AppThemeTokens 的架构：每个主题一整套令牌（表面
// 四层、文字三角色、强调三档、反馈语义、线与遮罩），全
// App 语义令牌一律由「当前主题的令牌表」查表生成（见
// Palette.token 工厂），组件不许再拼裸色。
//
// 本轮范围（如实记）：腾讯蓝是唯一完整主题行——结构令牌
// （表面/文字/线/反馈）全套定值；其余四款（深蓝/墨黑/紫/
// 绿）沿 0.2.1 既有行为，只替换强调三档、结构令牌共用腾
// 讯蓝行（withAccent 派生）。将来某主题要整套换肤色温，
// 给它一行完整令牌即可，组件零改动——结构按可换主题建。
// 取值依据：腾讯蓝＝TDesign 官方品牌色阶（brand7 #0052D9
// 主色、brand8 #003CAB 填充、brand1 #F2F3FF 浅染，0.2.2
// 查证口径）；紫＝HIG systemPurple；绿＝TDesign 成功色。
public struct ThemeTokens: Sendable {
    /// 一个外观（浅或深）下的整套令牌值
    public struct Scheme: Sendable {
        // 表面四层阶梯（§14 条 1：层间明度差 1–3%）
        public let pageBG: UInt32
        public let surface: UInt32
        public let bubbleFill: UInt32
        public let fieldFill: UInt32
        // 0.3.6 立宪新增（§22 Muse 基线）：导航/聊天面
        // 与选中胶囊垫——基线冻值，不随强调主题变
        public let chatSurface: UInt32
        public let selectionFill: UInt32
        // 遮罩与发丝线（基色＋alpha 成对，墨色推导不用 #000）
        public let scrimBase: UInt32
        public let scrimAlpha: Double
        public let hairlineBase: UInt32
        public let hairlineAlpha: Double
        // 文字三角色
        public let ink: UInt32
        public let inkSecondary: UInt32
        public let inkMuted: UInt32
        // 强调三档＋填充上的文字色
        public let primary: UInt32
        public let primaryFill: UInt32
        public let primaryTint: UInt32
        public let onPrimary: UInt32
        // 反馈语义（成套降饱和，不用系统纯色）
        public let success: UInt32
        public let warning: UInt32
        public let danger: UInt32

        public init(
            pageBG: UInt32, surface: UInt32, bubbleFill: UInt32,
            fieldFill: UInt32, scrimBase: UInt32, scrimAlpha: Double,
            hairlineBase: UInt32, hairlineAlpha: Double,
            ink: UInt32, inkSecondary: UInt32, inkMuted: UInt32,
            primary: UInt32, primaryFill: UInt32, primaryTint: UInt32,
            onPrimary: UInt32, success: UInt32, warning: UInt32,
            danger: UInt32, chatSurface: UInt32, selectionFill: UInt32
        ) {
            self.pageBG = pageBG
            self.surface = surface
            self.bubbleFill = bubbleFill
            self.fieldFill = fieldFill
            self.scrimBase = scrimBase
            self.scrimAlpha = scrimAlpha
            self.hairlineBase = hairlineBase
            self.hairlineAlpha = hairlineAlpha
            self.ink = ink
            self.inkSecondary = inkSecondary
            self.inkMuted = inkMuted
            self.primary = primary
            self.primaryFill = primaryFill
            self.primaryTint = primaryTint
            self.onPrimary = onPrimary
            self.success = success
            self.warning = warning
            self.danger = danger
            self.chatSurface = chatSurface
            self.selectionFill = selectionFill
        }

        /// 只换强调三档派生新行（结构令牌原样）
        func withAccent(
            primary: UInt32, primaryFill: UInt32, primaryTint: UInt32
        ) -> Scheme {
            Scheme(
                pageBG: pageBG, surface: surface, bubbleFill: bubbleFill,
                fieldFill: fieldFill, scrimBase: scrimBase,
                scrimAlpha: scrimAlpha, hairlineBase: hairlineBase,
                hairlineAlpha: hairlineAlpha, ink: ink,
                inkSecondary: inkSecondary, inkMuted: inkMuted,
                primary: primary, primaryFill: primaryFill,
                primaryTint: primaryTint, onPrimary: onPrimary,
                success: success, warning: warning, danger: danger,
                chatSurface: chatSurface, selectionFill: selectionFill
            )
        }
    }

    public let light: Scheme
    public let dark: Scheme

    public init(light: Scheme, dark: Scheme) {
        self.light = light
        self.dark = dark
    }

    /// 强调变体行：浅/深各换三档，结构令牌共用本行
    func withAccent(
        light: (primary: UInt32, fill: UInt32, tint: UInt32),
        dark: (primary: UInt32, fill: UInt32, tint: UInt32)
    ) -> ThemeTokens {
        ThemeTokens(
            light: lightScheme.withAccent(
                primary: light.primary, primaryFill: light.fill,
                primaryTint: light.tint
            ),
            dark: darkScheme.withAccent(
                primary: dark.primary, primaryFill: dark.fill,
                primaryTint: dark.tint
            )
        )
    }

    private var lightScheme: Scheme { light }
    private var darkScheme: Scheme { dark }

    /// 腾讯蓝完整主题行（默认主题）。
    /// 0.3.3 去暖定版（§18，用户当场否决暖色）：浅色阶梯
    /// 逐项对齐礼记 AppTheme.tencentBlue 令牌原值——
    /// pageBG 0xF2F3F5（冷灰底）、surface 0xFFFFFF（纯白
    /// 卡，底卡明度差拉开、卡浮得起来）、ink 0x1F2329、
    /// inkSecondary 0x5F6570（礼记 sub）、hairlineBase
    /// 0x1F2329（礼记 line 0xE3E6EB 的基色侧）、primary-
    /// Tint 0xEAF1FE（礼记原值）；bubbleFill/fieldFill 为
    /// 同温冷灰派生（0xECEEF1/0xF2F3F5，B≥G≥R 无暖序）。
    /// inkMuted 0x646C76：对 surface/pageBG 对比 5.3/4.7:1。
    /// 此前 0.3.0 的「纯白底＋FAFAFB 卡」阶梯卡底只差一
    /// 丝且方向反转（卡比底暗），与暖化口径一并作废。
    /// 暗色 inkMuted 于 0.3.2 按审查 I-1 提亮 0x8A8A90。
    /// 0.3.6 立宪覆盖（§22，Muse 实测基线为准、与上文
    /// 0.3.3 礼记原值对齐冲突处以基线胜出，§21.5 对账）：
    /// 浅色 pageBG 改 0xF3F4F6（设置类页灰底）、bubbleFill
    /// 改 0xE9EAEC（助手泡冷灰、永不染色）、fieldFill 改
    /// 0xF2F2F4（灰胶囊带内）、inkSecondary 改 0x6E6E73
    /// （次级灰冻值）、scrim 改白色半透纱（基色 0xFFFFFF、
    /// alpha 0.55；暗色行暂留旧值、归 0.3.8）；新增
    /// chatSurface 0xFCFCFC（导航/聊天近白面）与
    /// selectionFill 0xE3E3E5（选中浅灰胶囊垫）。
    public static let tencentBlue = ThemeTokens(
        light: Scheme(
            pageBG: 0xF3F4F6, surface: 0xFFFFFF, bubbleFill: 0xE9EAEC,
            fieldFill: 0xF2F2F4, scrimBase: 0xFFFFFF, scrimAlpha: 0.55,
            hairlineBase: 0x1F2329, hairlineAlpha: 0.08,
            ink: 0x1F2329, inkSecondary: 0x6E6E73, inkMuted: 0x646C76,
            primary: 0x0052D9, primaryFill: 0x003CAB,
            primaryTint: 0xEAF1FE, onPrimary: 0xFFFFFF,
            success: 0x1E8E4F, warning: 0xA85B0A, danger: 0xC62F24,
            chatSurface: 0xFCFCFC, selectionFill: 0xE3E3E5
        ),
        dark: Scheme(
            pageBG: 0x0B0B0D, surface: 0x121214, bubbleFill: 0x17181B,
            fieldFill: 0x1B1C1F, scrimBase: 0x050506, scrimAlpha: 0.55,
            hairlineBase: 0xEDF0F4, hairlineAlpha: 0.12,
            ink: 0xF2F2F4, inkSecondary: 0xAEAEB4, inkMuted: 0x8A8A90,
            primary: 0x6BA3FF, primaryFill: 0x0052D9,
            primaryTint: 0x1B2B4D, onPrimary: 0xFFFFFF,
            success: 0x45B878, warning: 0xD98E32, danger: 0xFF7A6B,
            chatSurface: 0x131316, selectionFill: 0x2C2C2F
        )
    )
}

/// 强调色主题（0.2.1 引入）：五款可选、默认腾讯蓝。
/// 0.3.2 起每款对应令牌表一行（见 ThemeTokens）：腾讯蓝
/// 是完整行，其余四款为强调变体行。
public enum AccentTheme: String, CaseIterable, Identifiable, Sendable {
    case tencent
    case deepBlue
    case inkBlack
    case purple
    case green

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tencent: return "腾讯蓝"
        case .deepBlue: return "深蓝"
        case .inkBlack: return "墨黑"
        case .purple: return "紫"
        case .green: return "绿"
        }
    }

    /// 本主题的整套令牌（Palette 唯一数据源）
    public var tokens: ThemeTokens {
        switch self {
        case .tencent:
            return .tencentBlue
        case .deepBlue:
            return ThemeTokens.tencentBlue.withAccent(
                light: (primary: 0x003CAB, fill: 0x002A66, tint: 0xD9E1FF),
                dark: (primary: 0x5B8DEF, fill: 0x003CAB, tint: 0x16233F)
            )
        case .inkBlack:
            // 填充原为 #000，0.3.0 起禁纯黑（§14 条 1），
            // 改近黑墨色 0x111114，视觉无差、口径合规
            return ThemeTokens.tencentBlue.withAccent(
                light: (primary: 0x1F1F24, fill: 0x111114, tint: 0xECECF1),
                dark: (primary: 0xEDF0F4, fill: 0x454C55, tint: 0x23282F)
            )
        case .purple:
            return ThemeTokens.tencentBlue.withAccent(
                light: (primary: 0xAF52DE, fill: 0x8E3DB8, tint: 0xF6E9FB),
                dark: (primary: 0xBF5AF2, fill: 0xAF52DE, tint: 0x2C2145)
            )
        case .green:
            return ThemeTokens.tencentBlue.withAccent(
                light: (primary: 0x00A870, fill: 0x007A52, tint: 0xE6F7F0),
                dark: (primary: 0x35C48D, fill: 0x00A870, tint: 0x14332A)
            )
        }
    }

    /// 设置页色板圆点用：浅色填充档（十六进制值）
    public var swatch: UInt32 { tokens.light.primaryFill }

    /// 设置页色板圆点用：浅色填充档（颜色对象，设计层内生成，
    /// 页面不许自己拼 Color(hex:)）
    public var swatchColor: Color { Color(hex: swatch) }
}

/// 主题存储：UserDefaults 持久化（本机偏好，不进 Keychain）。
/// @Observable 让引用 Palette 令牌的视图在切换时自动重绘——
/// Palette 的令牌是计算属性，视图 body 求值时读到 theme
/// 即建立订阅。
@Observable
public final class AccentStore {
    /// 单例供 Palette 计算属性在任意上下文读取；theme 的读写
    /// 只发生在主线程 UI 路径，UserDefaults 本身线程安全
    nonisolated(unsafe) public static let shared = AccentStore()

    private static let key = "od.accentTheme"

    public var theme: AccentTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        theme = saved.flatMap(AccentTheme.init(rawValue:)) ?? .tencent
    }
}
