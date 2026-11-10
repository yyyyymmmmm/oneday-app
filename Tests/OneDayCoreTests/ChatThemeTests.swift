import OneDayCore
import XCTest

/// 聊天主题与外观偏好（0.26.0，外观页专包）：注册表
/// 完整性、气泡字/强调对比闸（WCAGContrast 同式实
/// 算、全款 ≥4.5）、默认行＝旧 Palette 值映射、形象
/// 档映射、持久化默认/回落/round-trip。
final class ChatThemeTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "oneday.tests.chattheme"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// 注册表：8 款、id 唯一非空、默认款居首、名非空
    func testRegistryShape() {
        XCTAssertEqual(ChatThemes.all.count, 8)
        XCTAssertEqual(ChatThemes.all.first?.id, ChatThemes.defaultID)
        XCTAssertEqual(ChatThemes.defaultID, "sangou")
        XCTAssertEqual(
            Set(ChatThemes.all.map(\.id)).count, ChatThemes.all.count
        )
        for theme in ChatThemes.all {
            XCTAssertFalse(theme.displayName.isEmpty, theme.id)
        }
        XCTAssertEqual(ChatThemes.defaultTheme.id, "sangou")
    }

    /// 查表回落：nil/空/未注册 id 一律回默认款
    func testLookupFallback() {
        XCTAssertEqual(ChatThemes.theme(forID: nil).id, "sangou")
        XCTAssertEqual(ChatThemes.theme(forID: "").id, "sangou")
        XCTAssertEqual(ChatThemes.theme(forID: "garbage").id, "sangou")
        XCTAssertEqual(ChatThemes.theme(forID: "pink").displayName, "粉")
        XCTAssertEqual(ChatThemes.theme(forID: "obsidian").id, "obsidian")
    }

    /// 默认「三狗」行与 0.25.0 前 Palette 旧值逐字对
    /// 应（切回默认＝回原貌的钉子）：气泡/强调/弱面
    /// 三行全等；泡字浅档＝主墨、暗档＝纯白（旧暗档
    /// 反演墨 #EDF1F3 对比 4.28 压线、本版修正——此
    /// 处钉修正后值，防回潮）
    func testDefaultThemeMatchesLegacyPalette() {
        let theme = ChatThemes.defaultTheme
        XCTAssertEqual(theme.bubbleLight, 0xC8E7FF)
        XCTAssertEqual(theme.bubbleDark, 0x1473C8)
        // 0.41.0（浅档专项）：accentLight 按 §66.1 候
        // 选 (a) 加深一档，与旧值脱钩是本钉的本意——
        // 回潮到 0x1473C8 会让对比闸④转红
        XCTAssertEqual(theme.accentLight, 0x136FC1)
        XCTAssertEqual(theme.accentDark, 0x5EB1EF)
        XCTAssertEqual(theme.tintLight, 0xEDF7FD)
        XCTAssertEqual(theme.tintDark, 0x16242E)
        XCTAssertEqual(theme.bubbleTextLight, 0x11191C)
        XCTAssertEqual(theme.bubbleTextDark, 0xFFFFFF)
    }

    /// 对比闸①：全款气泡字对气泡（浅/暗两档）≥4.5
    func testBubbleTextContrastGate() {
        for theme in ChatThemes.all {
            let light = WCAGContrast.ratio(
                hexForeground: theme.bubbleTextLight,
                hexBackground: theme.bubbleLight
            )
            let dark = WCAGContrast.ratio(
                hexForeground: theme.bubbleTextDark,
                hexBackground: theme.bubbleDark
            )
            XCTAssertGreaterThanOrEqual(
                light, 4.5, "\(theme.id) 浅档气泡字对比 \(light)"
            )
            XCTAssertGreaterThanOrEqual(
                dark, 4.5, "\(theme.id) 暗档气泡字对比 \(dark)"
            )
        }
    }

    /// 对比闸②：全款强调对页底（浅 #FCFCFC/暗
    /// #000000——0.36.1 批一B 后 Palette.pageBG 暗档
    /// 改挂 systemBackground 纯黑，旧派生 #101619 退
    /// 役）≥4.5——链接/选中字色落页底也可读
    func testAccentContrastOnPageGate() {
        for theme in ChatThemes.all {
            let light = WCAGContrast.ratio(
                hexForeground: theme.accentLight,
                hexBackground: 0xFCFCFC
            )
            let dark = WCAGContrast.ratio(
                hexForeground: theme.accentDark,
                hexBackground: 0x000000
            )
            XCTAssertGreaterThanOrEqual(
                light, 4.5, "\(theme.id) 浅档强调对比 \(light)"
            )
            XCTAssertGreaterThanOrEqual(
                dark, 4.5, "\(theme.id) 暗档强调对比 \(dark)"
            )
        }
    }

    /// 对比闸③（0.36.1 扩面，审计 D9）：全款强调对
    /// 卡面（浅 #FFFFFF/暗 #1C1C1E＝Palette.surface
    /// 双档语义值）≥4.5——强调字落在分组卡上同样可读
    func testAccentContrastOnSurfaceGate() {
        for theme in ChatThemes.all {
            let light = WCAGContrast.ratio(
                hexForeground: theme.accentLight,
                hexBackground: 0xFFFFFF
            )
            let dark = WCAGContrast.ratio(
                hexForeground: theme.accentDark,
                hexBackground: 0x1C1C1E
            )
            XCTAssertGreaterThanOrEqual(
                light, 4.5, "\(theme.id) 浅档强调对卡面 \(light)"
            )
            XCTAssertGreaterThanOrEqual(
                dark, 4.5, "\(theme.id) 暗档强调对卡面 \(dark)"
            )
        }
    }

    /// 对比闸④（0.36.1 扩面，审计 D9）：全款强调对
    /// 助手泡面暗档（#2C2C2E＝Palette.bubbleFill 暗档
    /// tertiarySystemBackground）≥4.5——链接落助手泡
    /// 内可读。浅档同组合实算 4.20–4.68（四款压线
    /// 下）属浅档既有口径、本批（暗档专项）不辖，记
    /// DESIGN-V4 §66 留浅档专项处置，此处不设浅闸、
    /// 不冒充已验
    func testAccentContrastOnBubbleDarkGate() {
        for theme in ChatThemes.all {
            let dark = WCAGContrast.ratio(
                hexForeground: theme.accentDark,
                hexBackground: 0x2C2C2E
            )
            XCTAssertGreaterThanOrEqual(
                dark, 4.5, "\(theme.id) 暗档强调对泡面 \(dark)"
            )
        }
    }

    /// 对比闸⑤（0.36.1 扩面，审计 D9）：全款强调字
    /// 形对自家 tint 弱面（浅/暗）≥3.0——tint 按设计
    /// 只承载字形（其上文字走 ink/bodyInk，见
    /// ChatTheme 注），按 WCAG 图形对象口径 3.0 设
    /// 闸；实算浅档最低 4.31、暗档最低 5.90，均过。
    /// 曜黑款 tint 暗档与页底仅差一档的「近隐形」是
    /// 呈现问题、闸测不出，列真机肉眼验（§66）
    func testAccentGlyphContrastOnTintGate() {
        for theme in ChatThemes.all {
            let light = WCAGContrast.ratio(
                hexForeground: theme.accentLight,
                hexBackground: theme.tintLight
            )
            let dark = WCAGContrast.ratio(
                hexForeground: theme.accentDark,
                hexBackground: theme.tintDark
            )
            XCTAssertGreaterThanOrEqual(
                light, 3.0, "\(theme.id) 浅档字形对弱面 \(light)"
            )
            XCTAssertGreaterThanOrEqual(
                dark, 3.0, "\(theme.id) 暗档字形对弱面 \(dark)"
            )
        }
    }

    /// 形象档映射：胶囊 24/28/34（中档＝现行 28 锚）、
    /// 空态＝胶囊×2、序与 rawValue 往返
    func testAvatarTierMapping() {
        XCTAssertEqual(
            AvatarSizeTier.allCases, [.small, .medium, .large]
        )
        XCTAssertEqual(AvatarSizeTier.small.capsulePointSize, 24)
        XCTAssertEqual(AvatarSizeTier.medium.capsulePointSize, 28)
        XCTAssertEqual(AvatarSizeTier.large.capsulePointSize, 34)
        XCTAssertEqual(AvatarSizeTier.small.emptyStatePointSize, 48)
        XCTAssertEqual(AvatarSizeTier.medium.emptyStatePointSize, 56)
        XCTAssertEqual(AvatarSizeTier.large.emptyStatePointSize, 68)
        for tier in AvatarSizeTier.allCases {
            XCTAssertEqual(
                tier.emptyStatePointSize, tier.capsulePointSize * 2
            )
            XCTAssertEqual(AvatarSizeTier(rawValue: tier.rawValue), tier)
            XCTAssertFalse(tier.displayName.isEmpty)
        }
    }

    /// 持久化：未设＝默认（三狗/中档）；写入 round-
    /// trip；脏值回落默认不崩
    func testPersistenceDefaultsAndRoundTrip() {
        XCTAssertEqual(
            AppearancePreferences.chatTheme(in: defaults).id, "sangou"
        )
        XCTAssertEqual(
            AppearancePreferences.avatarTier(in: defaults), .medium
        )
        AppearancePreferences.setChatTheme(id: "lavender", in: defaults)
        XCTAssertEqual(
            AppearancePreferences.chatTheme(in: defaults).id, "lavender"
        )
        XCTAssertEqual(
            defaults.string(forKey: AppearanceStorageKeys.chatTheme),
            "lavender"
        )
        AppearancePreferences.setAvatarTier(.large, in: defaults)
        XCTAssertEqual(
            AppearancePreferences.avatarTier(in: defaults), .large
        )
        XCTAssertEqual(
            defaults.string(forKey: AppearanceStorageKeys.avatarSize),
            "large"
        )
        defaults.set("junk", forKey: AppearanceStorageKeys.chatTheme)
        defaults.set("junk", forKey: AppearanceStorageKeys.avatarSize)
        XCTAssertEqual(
            AppearancePreferences.chatTheme(in: defaults).id, "sangou"
        )
        XCTAssertEqual(
            AppearancePreferences.avatarTier(in: defaults), .medium
        )
    }

    /// 键名登记钉：三键字面不许漂移（appearanceMode
    /// 是 0.4.0 既有键、改名即丢用户已选值）
    func testStorageKeysPinned() {
        XCTAssertEqual(AppearanceStorageKeys.appearanceMode, "appearanceMode")
        XCTAssertEqual(AppearanceStorageKeys.chatTheme, "chatTheme")
        XCTAssertEqual(AppearanceStorageKeys.avatarSize, "avatarSize")
    }
}

extension ChatThemeTests {
    /// 对比闸④（0.41.0 收口批·浅档专项，DESIGN
    /// §66.1）：全款浅档强调对自家弱面（tintLight）
    /// ≥4.5——链接/强调落在助手侧弱面上也可读。加深
    /// 前实算：sangou 4.48／skyBlue 4.31／peach 4.43
    /// 三款压线下，余款本已过闸；三款已按候选 (a) 同
    /// 色相加深一档（值见 ChatTheme.swift 注）
    func testAccentContrastOnTintLightGate() {
        for theme in ChatThemes.all {
            let ratio = WCAGContrast.ratio(
                hexForeground: theme.accentLight,
                hexBackground: theme.tintLight
            )
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5, "\(theme.id) 浅档强调对弱面对比 \(ratio)"
            )
        }
    }
}
