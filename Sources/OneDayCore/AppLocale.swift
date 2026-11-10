import Foundation

/// 界面语言的唯一取口（0.42.0 国际化包）：App 不
/// 设语言开关、随系统语言（iOS 既有口径）。一切
/// 格式化器与目录取词都钉在「App 实际解析出的界
/// 面语言」上，保证界面语言与日期/数字语言恒一
/// 致——这是 0.36.0 审计 C11「中文写定、不随
/// locale 变脸」的国际化续编：C11 防的是界面中文
/// 时日期漏出英文的混排；本包钉的不是写死的中文，
/// 而是 App 当前语言本身，混排在三语下都不发生。
public enum AppLocale {
    /// App 当前界面语言：取主 bundle 已解析的本地
    /// 化（系统语言与已装目录求交后的结果），无目
    /// 录时回系统当前语言
    public static var uiLocale: Locale {
        if let id = Bundle.main.preferredLocalizations.first {
            return Locale(identifier: id)
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
        for name in localizationCandidates(for: locale) {
            if let path = Bundle.main.path(forResource: name, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
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
