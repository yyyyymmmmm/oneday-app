import Foundation

/// 界面语言的唯一取口（0.42.0 国际化包立、§140 续
/// 编）：默认随系统语言（iOS 既有口径），设置页
/// 「语言」档可选覆盖——0.42.0 文件头旧注释「App
/// 不设语言开关」口径就此作废（2026-11-11 用户点
/// 名：设置里没有语言切换、无从验证三语）。一切
/// 格式化器与目录取词都钉在「App 实际解析出的界
/// 面语言」上，保证界面语言与日期/数字语言恒一
/// 致——这是 0.36.0 审计 C11「中文写定、不随
/// locale 变脸」的国际化续编：C11 防的是界面中文
/// 时日期漏出英文的混排；本包钉的不是写死的中文，
/// 而是 App 当前语言本身，混排在三语下都不发生。
public enum AppLocale {
    /// App 当前界面语言：覆盖档优先（设置页语言
    /// Picker 写入的持久化值），无覆盖时回 0.42.0
    /// 现行解析——取主 bundle 已解析的本地化（系
    /// 统语言与已装目录求交后的结果），无目录时
    /// 回系统当前语言。进程内切换、不写 apple-
    /// Languages、不重启（i18n 漏网审计 §1.4 C 案）
    public static var uiLocale: Locale {
        resolve(
            preference: languagePreference(),
            preferredLocalizations: Bundle.main.preferredLocalizations
        )
    }

    /// 覆盖档读口：未设/脏值一律回 .system（跟随
    /// 系统）。App 侧交互写走 @AppStorage（同键、
    /// LanguageStorageKeys.appLanguage），本读口供
    /// 非视图层与单测使用
    public static func languagePreference(
        in defaults: UserDefaults = .standard
    ) -> AppLanguagePreference {
        let raw = defaults.string(
            forKey: LanguageStorageKeys.appLanguage
        )
        return AppLanguagePreference(rawValue: raw ?? "") ?? .system
    }

    /// 覆盖档写口（非视图层用；写入即原始值落盘）
    public static func setLanguagePreference(
        _ preference: AppLanguagePreference,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(
            preference.rawValue,
            forKey: LanguageStorageKeys.appLanguage
        )
    }

    /// 语言解析纯函数（钉测口）：显式档直取其
    /// Locale；跟随系统档取系统已解析本地化的首
    /// 项；清单为空时回系统当前语言（与 0.42.0
    /// 旧解析的尾巴同口径）
    static func resolve(
        preference: AppLanguagePreference,
        preferredLocalizations: [String]
    ) -> Locale {
        if let identifier = preference.localeIdentifier {
            return Locale(identifier: identifier)
        }
        if let first = preferredLocalizations.first {
            return Locale(identifier: first)
        }
        return Locale.autoupdatingCurrent
    }

    /// 指定语言的本地化 bundle：String Catalog 编
    /// 译后以 `<语言>.lproj` 落在主 bundle 内，按
    /// 完整标识→语言-文字→语言的顺序找；都没有时
    /// 回主 bundle（测试宿主无目录时 NSLocalizedString
    /// 回落键本身＝简体源串，断言确定性不随运行环
    /// 境语言漂移）
    static func bundle(for locale: Locale) -> Bundle {
        bundle(for: locale, in: .main)
    }

    /// 同上、基底 bundle 可注入（钉测以 fixture
    /// .lproj 目录验取词命中，宿主无真目录时的机
    /// 制验证口；生产恒走 .main）
    static func bundle(for locale: Locale, in base: Bundle) -> Bundle {
        for name in localizationCandidates(for: locale) {
            if let path = base.path(forResource: name, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return base
    }

    static func localizationCandidates(for locale: Locale) -> [String] {
        var out: [String] = []
        func append(_ s: String) {
            if !s.isEmpty && !out.contains(s) { out.append(s) }
        }
        let id = locale.identifier.replacingOccurrences(of: "_", with: "-")
        append(id)
        let parts = id.split(separator: "-").map(String.init)
        if parts.count >= 2 { append("\(parts[0])-\(parts[1])") }
        if let first = parts.first { append(first) }
        return out
    }
}

/// 语言覆盖四档（§140）：跟随系统／简体中文／繁
/// 體中文／English。rawValue 即持久化值——显式档
/// 就是其 Locale 标识、跟随系统档用哨兵值 system，
/// 单一事实源（@AppStorage 与上方读口同引此枚举）
public enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    public var id: String { rawValue }

    /// 显式档的 Locale 标识；跟随系统档为 nil
    /// （解析时回系统本地化清单）
    public var localeIdentifier: String? {
        self == .system ? nil : rawValue
    }

    /// 档名目录键（键＝简体源串，呈现经 L10n 取
    /// 词、不直写字面量过 Text(String) 原样面）
    public var displayKey: String {
        switch self {
        case .system: return "跟随系统"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁体中文"
        case .english: return "English"
        }
    }
}

/// 语言持久化键的单一出处（§140，照 Appearance-
/// StorageKeys 先例）：AppStorage 与 UserDefaults
/// 读口都引此，不许再散写字面量
public enum LanguageStorageKeys {
    public static let appLanguage = "appLanguage"
}

/// 目录取词口（Localizable.xcstrings，键＝简体源
/// 串）：Core 层一切呈现串经此取词；App 层 SwiftUI
/// 字面量由系统自动查目录、不经此口。指定 locale
/// 时按该语言的 .lproj 取词（格式化器的相对日词
/// 与注入语言一致靠这条）
public enum L10n {
    public static func string(
        _ key: String, locale: Locale = AppLocale.uiLocale
    ) -> String {
        NSLocalizedString(key, bundle: AppLocale.bundle(for: locale), comment: "")
    }

    public static func format(
        _ key: String, locale: Locale = AppLocale.uiLocale, _ args: CVarArg...
    ) -> String {
        String(format: string(key, locale: locale), arguments: args)
    }
}
