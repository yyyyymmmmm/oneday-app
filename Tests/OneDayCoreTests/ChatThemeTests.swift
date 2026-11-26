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

    /// 注册表：9 款（§503 新增「微信」款）、id 唯一
    /// 非空、默认款居首、名非空
    func testRegistryShape() {
        XCTAssertEqual(ChatThemes.all.count, 9)
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
        XCTAssertEqual(theme.accentDark, 0x359FF0, "dp-214: 降饱和收带 S78%")
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
                hexBackground: 0xFFFFFF  // dp-214: 页底收敛至 #FFFFFF
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

    /// 对比闸⑥（2026-11-15，第 85 条对比度收口；
    /// §503 改判口径）：全款浅档强调对**自家 AI 卡
    /// 面**（theme.aiCardLight）≥4.5——卡内链接/强
    /// 调字可读。旧口径对 #EEEEF0 设闸（Palette.
    /// bubbleFill 旧浅档）；§503 卡面归主题整包辖
    /// （默认款 #E9EAEC、微信款 #FFFFFF），闸随辖
    /// 区改对自家卡面。改判实算：pink 旧强调对新卡
    /// 面 4.35、peach 约 4.0 双双差线——已按 §66.1
    /// 先例同色相加深一档（0xB03670／0xA14F11，
    /// 对卡面 4.84／4.79）；余款本已过闸。暗档同
    /// 组合由闸④（对 #2C2C2E）辖，不在此重复
    func testAccentContrastOnBubbleLightGate() {
        for theme in ChatThemes.all {
            let ratio = WCAGContrast.ratio(
                hexForeground: theme.accentLight,
                hexBackground: theme.aiCardLight
            )
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5, "\(theme.id) 浅档强调对 AI 卡面对比 \(ratio)"
            )
        }
    }

    /// 对比闸⑨（§503 新立，AI 全宽卡）：全款——正
    /// 文墨（浅 #11191C＝Palette.bodyInk 浅档定值
    /// ／暗 #FFFFFF）对自家 AI 卡面 ≥4.5；卡面对
    /// 自家主题背景 ∈[1.10, 1.60]（与用户泡闸⑦浅
    /// 档同带：可辨靠形不靠对比，Muse 卡/页实测
    /// 1.17）。逐值实算（2026-11-24）：字/卡浅
    /// 14.79–17.80、暗 13.94；卡/背景浅 1.17、暗
    /// 1.35–1.51，全款过线
    func testAICardContrastGate503() {
        for theme in ChatThemes.all {
            for dark in [false, true] {
                let card = theme.aiCardFill(dark: dark)
                let ink: UInt32 = dark ? 0xFFFFFF : 0x11191C
                let textRatio = WCAGContrast.ratio(
                    hexForeground: ink, hexBackground: card
                )
                XCTAssertGreaterThanOrEqual(
                    textRatio, 4.5,
                    "\(theme.id) dark=\(dark) 卡字对比 \(textRatio)"
                )
                let bg = theme.chatBackground(dark: dark)
                let cardRatio = WCAGContrast.ratio(
                    hexForeground: card, hexBackground: bg
                )
                XCTAssertGreaterThanOrEqual(
                    cardRatio, 1.10,
                    "\(theme.id) dark=\(dark) 卡对背景 \(cardRatio)＜带下限"
                )
                XCTAssertLessThanOrEqual(
                    cardRatio, 1.60,
                    "\(theme.id) dark=\(dark) 卡对背景 \(cardRatio)＞带上限"
                )
            }
        }
    }

    /// §503 整包定值钉：默认款＝Muse 构图（AI 卡
    /// #E9EAEC/#2C2C2E、背景页底 #FCFCFC/#000000）；
    /// 微信款逐值＝取样表（发泡 #95EC69、卡浅
    /// #FFFFFF＝收泡、背景浅 #EDEDED＝WeUI BG-0）
    /// ＋无取样半边的在册落值（卡暗 #2C2C2E、背景
    /// 暗 #111113），防逐款漂移
    func testThemePackageValues503() {
        let sangou = ChatThemes.defaultTheme
        XCTAssertEqual(sangou.aiCardLight, 0xE9EAEC)
        XCTAssertEqual(sangou.aiCardDark, 0x2C2C2E)
        XCTAssertEqual(sangou.backgroundLight, 0xFFFFFF, "dp-214: 收敛至 systemBackground")
        XCTAssertEqual(sangou.backgroundDark, 0x000000)
        let wechat = ChatThemes.theme(forID: "wechat")
        XCTAssertEqual(wechat.bubbleLight, 0x95EC69)
        XCTAssertEqual(wechat.aiCardLight, 0xFFFFFF)
        XCTAssertEqual(wechat.aiCardDark, 0x2C2C2E)
        XCTAssertEqual(wechat.backgroundLight, 0xEDEDED)
        XCTAssertEqual(wechat.backgroundDark, 0x111113)
        // 解析出口成对钉（与 bubbleFill/bubbleText 同式）
        for theme in ChatThemes.all {
            XCTAssertEqual(theme.aiCardFill(dark: false), theme.aiCardLight, theme.id)
            XCTAssertEqual(theme.aiCardFill(dark: true), theme.aiCardDark, theme.id)
            XCTAssertEqual(theme.chatBackground(dark: false), theme.backgroundLight, theme.id)
            XCTAssertEqual(theme.chatBackground(dark: true), theme.backgroundDark, theme.id)
        }
    }

    /// §503 新键与新档：文字大小（未设回跟随系统、
    /// round-trip、脏值回落）、强调覆盖（未设 nil、
    /// 写读 round-trip、nil 复位删键、脏值回 nil）、
    /// 背景扩容（新档 round-trip、图案映射、脏值仍
    /// 回 standard）、强调预设盘＝TG 出厂 11 色逐值
    func testTextSizeAccentAndBackground503() {
        XCTAssertEqual(
            AppearancePreferences.textSizeTier(in: defaults), .system
        )
        AppearancePreferences.setTextSizeTier(.large, in: defaults)
        XCTAssertEqual(
            AppearancePreferences.textSizeTier(in: defaults), .large
        )
        XCTAssertEqual(
            defaults.string(forKey: AppearanceStorageKeys.chatTextSize),
            "large"
        )
        defaults.set("junk", forKey: AppearanceStorageKeys.chatTextSize)
        XCTAssertEqual(
            AppearancePreferences.textSizeTier(in: defaults), .system
        )

        XCTAssertNil(AppearancePreferences.accentOverride(in: defaults))
        AppearancePreferences.setAccentOverride(0x0088FF, in: defaults)
        XCTAssertEqual(
            AppearancePreferences.accentOverride(in: defaults), 0x0088FF
        )
        AppearancePreferences.setAccentOverride(nil, in: defaults)
        XCTAssertNil(AppearancePreferences.accentOverride(in: defaults))
        // 哨兵 -1（外观页「跟随主题」落盘值）＝未设
        defaults.set(-1, forKey: AppearanceStorageKeys.chatAccentOverride)
        XCTAssertNil(AppearancePreferences.accentOverride(in: defaults))

        AppearancePreferences.setBackgroundStyle(.wechatGray, in: defaults)
        XCTAssertEqual(
            AppearancePreferences.backgroundStyle(in: defaults), .wechatGray
        )
        AppearancePreferences.setBackgroundStyle(.theme, in: defaults)
        XCTAssertEqual(
            AppearancePreferences.backgroundStyle(in: defaults), .theme
        )
        XCTAssertEqual(ChatBackgroundStyle.dots.patternKind, .dots)
        XCTAssertEqual(ChatBackgroundStyle.grid.patternKind, .grid)
        XCTAssertEqual(ChatBackgroundStyle.diagonal.patternKind, .diagonal)
        XCTAssertNil(ChatBackgroundStyle.standard.patternKind)
        XCTAssertNil(ChatBackgroundStyle.theme.patternKind)
        XCTAssertEqual(ChatBackgroundStyle.allCases.count, 9)
        XCTAssertEqual(ChatTextSizeTier.allCases.count, 5)

        XCTAssertEqual(
            ChatAccentPresets.values,
            [0x0088FF, 0x00C2ED, 0x29B327, 0xEB6CA4, 0xF08200,
             0x9472EE, 0xD33213, 0xEDB400, 0x6D839E, 0x000000,
             0xFFFFFF]
        )
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
                let page: UInt32 = dark ? 0x000000 : 0xFFFFFF  // dp-214: 页底收敛至 #FFFFFF
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
            // §503 新增：微信款发泡＝取样表 #95EC69
            "wechat": 0x95EC69,
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
