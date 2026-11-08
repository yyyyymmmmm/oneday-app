import Foundation
import Observation

/// 强调色主题（0.2.1 引入，0.2.2 按查证口径纠正）：全 App 只动
/// 强调色一族（主色/填充/浅染），静态色（纸底、墨色、语义色）
/// 不随主题变。取值依据见 docs/DESIGN-V3-NOTES.md §1–§2：
/// - 腾讯蓝（默认）：TDesign 官方品牌色阶 brand7 #0052D9 为主色、
///   brand8 #003CAB 为填充档（按下阶，白字对比足）、brand1
///   #F2F3FF 为浅染。0.2.1 曾误用 #00A4FF（未查证的猜值），
///   0.2.2 改回官方值。
/// - 深蓝：以 brand8 #003CAB 为主色、按同规则加深/取浅阶。
/// - 墨黑：TDesign 中性深色 #181818 一带的中性墨。
/// - 紫：Apple HIG 系统色 systemPurple #AF52DE（深色档 #BF5AF2
///   为其官方深色变体）。
/// - 绿：TDesign 功能色·成功 #00A870。
/// 填充档与浅染档一律按「同色阶加深一档/最浅档」规则推导，
/// 保证白字对比——沿用设计 v2 的 primary/primaryFill 双档纪律。
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
            return (0x0052D9, 0x6BA3FF, 0x003CAB, 0x0052D9, 0xF2F3FF, 0x1B2B4D)
        case .deepBlue:
            return (0x003CAB, 0x5B8DEF, 0x002A66, 0x003CAB, 0xD9E1FF, 0x16233F)
        case .inkBlack:
            // 主填充原为 #000，0.3.0 起禁纯黑（§14 条 1），
            // 改近黑墨色 0x111114，视觉无差、口径合规
            return (0x1F1F24, 0xEDF0F4, 0x111114, 0x454C55, 0xECECF1, 0x23282F)
        case .purple:
            return (0xAF52DE, 0xBF5AF2, 0x8E3DB8, 0xAF52DE, 0xF6E9FB, 0x2C2145)
        case .green:
            return (0x00A870, 0x35C48D, 0x007A52, 0x00A870, 0xE6F7F0, 0x14332A)
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
