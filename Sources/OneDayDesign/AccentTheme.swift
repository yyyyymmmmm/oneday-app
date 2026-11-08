import Foundation
import Observation

/// 强调色主题（0.2.1，用户拍板）：全 App 只动强调色一族
/// （主色/填充/浅染），静态色（纸底、墨色、语义色）不随主题变。
/// 五款克制备选，默认腾讯蓝。
///
/// 取值口径：
/// - 腾讯蓝：明快品牌蓝 #00A4FF 为主色；填充档同色系加深到
///   #0076C9（白字对比约 4.6:1）——沿用设计 v2 的
///   primary/primaryFill 双档纪律（现行深蓝即 #0052D9/#003CAB）。
/// - 深蓝：0.2.0 现行整套（#0052D9/#003CAB/#EBF1FC），原样保留。
/// - 其余三款同纪律：主色取品牌色本体，填充加深一档保白字，
///   浅染约 8% 同色系。
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

    /// (浅主色, 深主色, 浅填充, 深填充, 浅浅染, 深浅染)
    public var values: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) {
        switch self {
        case .tencent:
            return (0x00A4FF, 0x4DBDFF, 0x0076C9, 0x0B84D8, 0xE6F6FF, 0x10344D)
        case .deepBlue:
            return (0x0052D9, 0x6BA3FF, 0x003CAB, 0x0052D9, 0xEBF1FC, 0x1B2B4D)
        case .inkBlack:
            return (0x191D23, 0xEDF0F4, 0x191D23, 0x454C55, 0xEDEFF2, 0x23282F)
        case .purple:
            return (0x7B3FE4, 0xB79CFF, 0x6D28D9, 0x7C3AED, 0xF1EAFE, 0x2C2145)
        case .green:
            return (0x0E9F6E, 0x4CC38A, 0x067A54, 0x0B8A5F, 0xE4F6EF, 0x14332A)
        }
    }

    /// 设置页色板圆点用：浅色填充档
    public var swatch: UInt32 { values.2 }
}

/// 主题存储：UserDefaults 持久化（本机偏好，不进 Keychain）。
/// @Observable 让引用 Palette 强调色的视图在切换时自动重绘——
/// Palette 的强调色是计算属性，视图 body 求值时读到 theme
/// 即建立订阅。
@Observable
public final class AccentStore {
    public static let shared = AccentStore()

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
