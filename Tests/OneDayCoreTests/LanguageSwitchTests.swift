import XCTest
@testable import OneDayCore

/// 语言切换钉测（§140，i18n 漏网审计包 0）：四档
/// 解析、跟随系统回落、覆盖值持久化、三语取词命
/// 中。目录真值由 validate_i18n.py 把守；本文件
/// 的取词断言以 fixture .lproj 载目录真值同文
/// （键「跟随系统」三语各异）验 AppLocale 的解
/// 析→选包→取词整条机制——逻辑宿主无真目录，
/// 与 I18nFormattingTests 的宿主口径分工见彼处
/// 文件头注。
final class LanguageSwitchTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var fixtureDir: URL?

    override func setUp() {
        super.setUp()
        suiteName = "LanguageSwitchTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        if let fixtureDir {
            try? FileManager.default.removeItem(at: fixtureDir)
        }
        defaults = nil
        fixtureDir = nil
        super.tearDown()
    }

    // MARK: - 四档解析

    func testResolveExplicitPreferences() {
        XCTAssertEqual(
            AppLocale.resolve(
                preference: .simplifiedChinese,
                preferredLocalizations: ["en"]
            ).identifier,
            "zh-Hans"
        )
        XCTAssertEqual(
            AppLocale.resolve(
                preference: .traditionalChinese,
                preferredLocalizations: ["en"]
            ).identifier,
            "zh-Hant"
        )
        XCTAssertEqual(
            AppLocale.resolve(
                preference: .english,
                preferredLocalizations: ["zh-Hans"]
            ).identifier,
            "en"
        )
    }

    // MARK: - 跟随系统回落 preferredLocalizations

    func testSystemFallsBackToPreferredLocalizations() {
        XCTAssertEqual(
            AppLocale.resolve(
                preference: .system,
                preferredLocalizations: ["zh-Hant", "en"]
            ).identifier,
            "zh-Hant"
        )
        XCTAssertEqual(
            AppLocale.resolve(
                preference: .system,
                preferredLocalizations: ["en"]
            ).identifier,
            "en"
        )
        XCTAssertEqual(
            AppLocale.resolve(
                preference: .system,
                preferredLocalizations: []
            ).identifier,
            Locale.autoupdatingCurrent.identifier
        )
    }

    // MARK: - 覆盖值持久化回读一致

    func testPreferencePersistenceRoundTrip() {
        // 未设＝跟随系统（默认档）
        XCTAssertEqual(
            AppLocale.languagePreference(in: defaults), .system
        )
        for preference in AppLanguagePreference.allCases {
            AppLocale.setLanguagePreference(preference, in: defaults)
            XCTAssertEqual(
                AppLocale.languagePreference(in: defaults), preference
            )
            XCTAssertEqual(
                defaults.string(
                    forKey: LanguageStorageKeys.appLanguage
                ),
                preference.rawValue
            )
        }
        // 脏值回定版默认
        defaults.set("junk-value", forKey: LanguageStorageKeys.appLanguage)
        XCTAssertEqual(
            AppLocale.languagePreference(in: defaults), .system
        )
    }

    // MARK: - 四档取词命中对应语言

    func testWordLookupHitsEachLanguage() throws {
        let base = try makeFixtureBundle()
        // 键「跟随系统」：目录三语各异（跟随系统／
        // 跟隨系統／Follow system），四档逐档断言
        let cases: [(
            preference: AppLanguagePreference,
            preferred: [String],
            expected: String
        )] = [
            (.simplifiedChinese, ["en"], "跟随系统"),
            (.traditionalChinese, ["en"], "跟隨系統"),
            (.english, ["zh-Hans"], "Follow system"),
            (.system, ["zh-Hant"], "跟隨系統"),
            (.system, ["en"], "Follow system"),
        ]
        for testCase in cases {
            let locale = AppLocale.resolve(
                preference: testCase.preference,
                preferredLocalizations: testCase.preferred
            )
            let bundle = AppLocale.bundle(for: locale, in: base)
            XCTAssertEqual(
                NSLocalizedString(
                    "跟随系统", bundle: bundle, comment: ""
                ),
                testCase.expected,
                "档位 \(testCase.preference.rawValue) 取词未命中"
            )
        }
    }

    /// fixture bundle：临时目录内三套 .lproj，各
    /// 放一份 Localizable.strings，只载键「跟随系
    /// 统」的目录真值三语（机制验证用、非目录副
    /// 本——目录本体的三语完整性由 validate 守）
    private func makeFixtureBundle() throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LanguageSwitchFixture-\(UUID().uuidString)"
            )
        fixtureDir = root
        let entries: [(lproj: String, value: String)] = [
            ("zh-Hans", "跟随系统"),
            ("zh-Hant", "跟隨系統"),
            ("en", "Follow system"),
        ]
        for entry in entries {
            let dir = root.appendingPathComponent(
                "\(entry.lproj).lproj"
            )
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            let content = "\"跟随系统\" = \"\(entry.value)\";\n"
            try content.write(
                to: dir.appendingPathComponent("Localizable.strings"),
                atomically: true, encoding: .utf16
            )
        }
        return try XCTUnwrap(Bundle(path: root.path))
    }
}
