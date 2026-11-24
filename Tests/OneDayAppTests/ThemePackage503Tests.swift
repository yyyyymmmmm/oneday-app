import XCTest

/// §503 主题包（2026-11-24）：AI 全宽底衬卡形态、
/// 主题整包接线、外观页重构与两页迁家的装配钉
/// （源代码装配断言，与 ReplyRenderingAlignment-
/// Tests/StreamingTokenScopeTests 同式）。数值与
/// 对比口径的实算钉在 Core ChatThemeTests（闸⑥
/// 改判/闸⑨/整包定值/新键持久化）
final class ThemePackage503Tests: XCTestCase {

    private func sourceText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    /// AI 全宽卡：assistantBubble 满宽承载＋卡面走
    /// Palette.bubbleFill（主题 aiCard 读口）；§263
    /// 窄列几何（列宽封顶/左缘占屏比）在 ChatView
    /// 不许残留
    func testAssistantCardIsFullWidth503() throws {
        let chat = try sourceText("Sources/OneDayApp/ChatView.swift")
        XCTAssertTrue(chat.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(chat.contains("Palette.bubbleFill"))
        XCTAssertFalse(chat.contains("assistantTextWidthFraction"))
        XCTAssertFalse(chat.contains("assistantTextLeadingFraction"))
        XCTAssertFalse(chat.contains("columnCap"))
    }

    /// 文宽单源：量测三面同读 OneDayMetrics.
    /// assistantTextWidth，不许再各自拼算
    func testTextWidthSingleSource503() throws {
        let metrics = try sourceText("Sources/OneDayDesign/Palette.swift")
        XCTAssertTrue(metrics.contains("static func assistantTextWidth"))
        let layout = try sourceText(
            "Sources/OneDayApp/LayoutProductService.swift")
        XCTAssertTrue(layout.contains(
            "OneDayMetrics.assistantTextWidth(screenWidth: screenWidth)"))
        let heights = try sourceText(
            "Sources/OneDayApp/ChatNativeRowHeight.swift")
        XCTAssertTrue(heights.contains(
            ".assistantTextWidth(screenWidth: screenWidth)"))
    }

    /// 预览单数据源：外观预览与聊天页共用 Chat-
    /// BackgroundSurface、双边气泡走 Palette 现读
    /// 且带真字；旧假预览（空形状 previewBubble＋
    /// 写死 pageBG 底）不许残留
    func testPreviewSharesLiveSources503() throws {
        let appearance = try sourceText(
            "Sources/OneDayApp/AppearanceView.swift")
        XCTAssertTrue(appearance.contains("ChatBackgroundSurface()"))
        XCTAssertTrue(appearance.contains("Palette.userBubbleFill"))
        XCTAssertTrue(appearance.contains("Palette.bubbleFill"))
        XCTAssertTrue(appearance.contains("Palette.userBubbleText"))
        XCTAssertFalse(appearance.contains("previewBubble"))
        XCTAssertFalse(appearance.contains("Palette.pageBG"))
        // 主题卡片列（带名）与强调色点列在位
        XCTAssertTrue(appearance.contains("themeCard"))
        XCTAssertTrue(appearance.contains("ChatAccentPresets.values"))
        XCTAssertTrue(appearance.contains("跟随主题"))
        // 聊天页背景层同面（双面同源的另一半）
        let chat = try sourceText("Sources/OneDayApp/ChatView.swift")
        XCTAssertTrue(chat.contains("ChatBackgroundSurface()"))
    }

    /// 两页迁家：语言页承语言键与勾选行、互动页承
    /// 两反应键；外观页不再有两节残留
    func testLanguageAndReactionPagesMoved503() throws {
        let language = try sourceText(
            "Sources/OneDayApp/LanguageSettingsView.swift")
        XCTAssertTrue(language.contains("LanguageStorageKeys.appLanguage"))
        XCTAssertTrue(language.contains("AppLanguagePreference.allCases"))
        let reaction = try sourceText(
            "Sources/OneDayApp/ReactionSettingsView.swift")
        XCTAssertTrue(reaction.contains(
            "ChatReactionsFloatingBarFeature.defaultsKey"))
        XCTAssertTrue(reaction.contains(
            "ChatReactionsAISelfFeature.defaultsKey"))
        XCTAssertTrue(reaction.contains(
            "refreshSelfReactionsAvailability"))
        let appearance = try sourceText(
            "Sources/OneDayApp/AppearanceView.swift")
        XCTAssertFalse(appearance.contains("languageSection"))
        XCTAssertFalse(appearance.contains("replyPresentationSection"))
        XCTAssertFalse(appearance.contains(
            "ChatReactionsFloatingBarFeature"))
        XCTAssertFalse(appearance.contains(
            "ChatReactionsAISelfFeature"))
        // 路由与目录接线在位
        let settings = try sourceText(
            "Sources/OneDayApp/SettingsView.swift")
        XCTAssertTrue(settings.contains("LanguageSettingsView()"))
        XCTAssertTrue(settings.contains("ReactionSettingsView()"))
    }

    /// 文字大小接线：聊天页读 chatTextSize 键、映
    /// 射走 fixedDynamicTypeSize 单源、列表面施环
    /// 境覆盖；外观页有同键写口
    func testTextSizeWiring503() throws {
        let chat = try sourceText("Sources/OneDayApp/ChatView.swift")
        XCTAssertTrue(chat.contains("AppearanceStorageKeys.chatTextSize"))
        XCTAssertTrue(chat.contains("fixedDynamicTypeSize"))
        XCTAssertTrue(chat.contains(".dynamicTypeSize(dynamicTypeSize)"))
        let appearance = try sourceText(
            "Sources/OneDayApp/AppearanceView.swift")
        XCTAssertTrue(appearance.contains(
            "AppearanceStorageKeys.chatTextSize"))
        XCTAssertTrue(appearance.contains(
            "AppearanceStorageKeys.chatAccentOverride"))
    }
}
