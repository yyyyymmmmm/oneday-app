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
        // 2026-11-15（第 85 条）：再深一档至 0x1268B8
        // （压助手泡面 4.45 差线），回潮到 0x136FC1
        // 会让对比闸⑥转红
        XCTAssertEqual(theme.accentLight, 0x1268B8)
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

    /// 对比闸⑥（2026-11-15，第 85 条对比度收口）：
    /// 全款浅档强调对助手泡面（#EEEEF0＝Palette.
    /// bubbleFill 浅档）≥4.5——泡内链接/强调字可读。
    /// 立闸前实算：sangou 4.45／iceBlue 4.39 两款差
    /// 线（审计原稿只报默认款），均已同色相深一档
    /// （0x1268B8／0x1B6AB9）；余款本已过闸（最低
    /// pink 4.51、peach 4.60）。暗档同组合由闸④
    /// （对 #2C2C2E）辖，不在此重复
    func testAccentContrastOnBubbleLightGate() {
        for theme in ChatThemes.all {
            let ratio = WCAGContrast.ratio(
                hexForeground: theme.accentLight,
                hexBackground: 0xEEEEF0
            )
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5, "\(theme.id) 浅档强调对助手泡面对比 \(ratio)"
            )
        }
    }

    // MARK: - 气泡浅填深字定版（台账 197）

    /// 解析口径钉（197 定版／§335，188 单档口径的
    /// 浅档半边改判）：浅＝同款 bubbleLight 浅填＋
    /// 同款 bubbleTextLight 深字、暗＝现 bubbleDark
    /// ＋现泡字（188 暗档维持），全款无第二路；曜
    /// 黑暗档定值钉 0x585E65（旧 0x2C3138 对暗页底
    /// 仅 1.60 的留账清账值，回潮即红）
    func testSingleBubbleResolution() {
        for theme in ChatThemes.all {
            XCTAssertEqual(
                theme.bubbleFill(dark: false),
                theme.bubbleLight, theme.id
            )
            XCTAssertEqual(
                theme.bubbleText(dark: false),
                theme.bubbleTextLight, theme.id
            )
            XCTAssertEqual(
                theme.bubbleFill(dark: true),
                theme.bubbleDark, theme.id
            )
            XCTAssertEqual(
                theme.bubbleText(dark: true),
                theme.bubbleTextDark, theme.id
            )
        }
        XCTAssertEqual(
            ChatThemes.theme(forID: "obsidian").bubbleDark,
            0x585E65
        )
    }

    /// 对比闸⑦（台账 197 改判口径／§335，188 的
    /// 2.90 参照线退役）：泡字 vs 泡面 ≥4.5 两档
    /// 恒守（与闸①同线）；泡面 vs 页底（浅
    /// #FCFCFC／暗 #000000）——浅档浅填款 ∈
    /// [1.10, 1.60]（与闸⑧同带：可辨靠形不靠对
    /// 比，样板 Muse 用户泡实测 1.26／iMessage
    /// 同级 ≈1.2；2.90 线当年取自 OpenBot 饱和
    /// 形态、不普适，退役）、深泡款曜黑浅档（泡/
    /// 页 14.66）豁免带只守字闸、暗档维持 188 的
    /// ≥2.9（深饱实填对黑页）。实算（2026-11-21
    /// 逐值）：浅 字/泡 7.64–15.04、泡/页 1.16–
    /// 1.50（曜黑 14.66 豁免）；暗 字/泡 4.87–
    /// 6.72、泡/页 3.12–4.32，全款过线
    func testSingleBubbleContrastGates() {
        for theme in ChatThemes.all {
            for dark in [false, true] {
                let fill = theme.bubbleFill(dark: dark)
                let text = theme.bubbleText(dark: dark)
                let textRatio = WCAGContrast.ratio(
                    hexForeground: text, hexBackground: fill
                )
                XCTAssertGreaterThanOrEqual(
                    textRatio, 4.5,
                    "\(theme.id) dark=\(dark) 泡字对比 \(textRatio)"
                )
                let page: UInt32 = dark ? 0x000000 : 0xFCFCFC
                let pageRatio = WCAGContrast.ratio(
                    hexForeground: fill, hexBackground: page
                )
                if dark {
                    XCTAssertGreaterThanOrEqual(
                        pageRatio, 2.9,
                        "\(theme.id) dark=true 泡面对页底 \(pageRatio)＜下限 2.9"
                    )
                } else if theme.id != "obsidian" {
                    XCTAssertGreaterThanOrEqual(
                        pageRatio, 1.10,
                        "\(theme.id) 浅填泡面对页底 \(pageRatio)＜带下限 1.10"
                    )
                    XCTAssertLessThanOrEqual(
                        pageRatio, 1.60,
                        "\(theme.id) 浅填泡面对页底 \(pageRatio)＞带上限 1.60"
                    )
                }
            }
        }
    }


    /// §431（2026-11-24 主题对位包）：八款 bubbleLight
    /// 与参照应用（Muse）外观页色板工具采样逐值对钉
    /// （采样表见 DESIGN §431）；默认款三狗为定版锚、
    /// 与采样表无关、值不许漂移，此处并钉全表防逐
    /// 款漂移。深档 bubbleDark 无参照样本、不在本钉
    /// 范围（§431 明示无据不动）
    func testThemeBubbleLightMatchesReferenceSamples431() {
        let expected: [String: UInt32] = [
            "sangou": 0xC8E7FF,
            "iceBlue": 0xCBE5FE,
            "obsidian": 0x000000,
            "greige": 0xE4DAD1,
            "skyBlue": 0xB8DAFD,
            "lavender": 0xDBC6F1,
            "pink": 0xFDB9DE,
            "peach": 0xFFD7B5,
        ]
        XCTAssertEqual(Set(ChatThemes.all.map(\.id)), Set(expected.keys))
        for theme in ChatThemes.all {
            XCTAssertEqual(
                theme.bubbleLight, expected[theme.id],
                "\(theme.id) bubbleLight 与 §431 采样表不符"
            )
        }
    }

    // 184 的浓淡偏好测试（testBubbleFillStyle-
    // Preference）已随 188 删机制退役：键与读口
    // 均不存在、无偏好可测
}
