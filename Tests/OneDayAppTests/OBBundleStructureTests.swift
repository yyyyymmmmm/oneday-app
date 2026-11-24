import XCTest

/// OB 合包结构钉测（台账 174–179；DESIGN §391）：六条
/// 的形态把守——入口在场、单源复用、失败常驻、向导无
/// 付费面、个性化默认不漂移。读源码口径与既有结构测
/// 同制（整行注释不算代码）。
final class OBBundleStructureTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    private func codeLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("///") && !t.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    // MARK: - 174 关系图

    func testCronGraphEntryAndViewExist() throws {
        let cron = try codeLines(
            source("Sources/OneDayApp/CronViews.swift")
        )
        XCTAssertTrue(cron.contains("CronRelationGraphView()"))
        let graph = try codeLines(
            source("Sources/OneDayApp/CronRelationGraphView.swift")
        )
        // 图数据只许走 Core 单源组装
        XCTAssertTrue(graph.contains("CronRelationGraph.build"))
        // 点任务进既有详情
        XCTAssertTrue(graph.contains("CronJobDetailView"))
    }

    // MARK: - 175 更新说明

    func testAboutShowsReleaseNotesFromCoreTable() throws {
        let about = try codeLines(
            source("Sources/OneDayApp/SettingsSupportViews.swift")
        )
        XCTAssertTrue(about.contains("ReleaseNotes.entries"))
        XCTAssertTrue(
            about.contains("CFBundleShortVersionString")
        )
    }

    // MARK: - 176 全局搜索

    func testGlobalSearchReusesSingleSources() throws {
        let search = try codeLines(
            source("Sources/OneDayApp/GlobalSearchView.swift")
        )
        // 会话＝服务端搜索端点
        XCTAssertTrue(search.contains("searchSessions"))
        // 设置＝Core 目录搜索（与设置页内搜索同源）
        XCTAssertTrue(search.contains("SettingsCatalog.search"))
        // 定时＝共享店＋既有详情
        XCTAssertTrue(search.contains("sharedCronStore"))
        XCTAssertTrue(search.contains("CronJobDetailView"))
        // 文件＝名单店＋文件页定位信箱
        XCTAssertTrue(search.contains("sharedLibraryListStore"))
        XCTAssertTrue(search.contains("fileRevealPath"))
        // 入口在全部对话页
        let all = try codeLines(
            source("Sources/OneDayApp/AllConversationsView.swift")
        )
        XCTAssertTrue(all.contains("GlobalSearchView("))
    }

    func testSettingsRouteMappingIsShared() throws {
        let router = try codeLines(
            source("Sources/OneDayApp/AppRouter.swift")
        )
        XCTAssertTrue(router.contains("static func from("))
        let settings = try codeLines(
            source("Sources/OneDayApp/SettingsView.swift")
        )
        XCTAssertTrue(
            settings.contains(
                "SettingsRoute.from(destination: destination)"
            )
        )
    }

    // MARK: - 177 空态编排

    func testEmptyStateComponentAndMigrations() throws {
        let design = try source(
            "Sources/OneDayDesign/EmptyState.swift"
        )
        XCTAssertTrue(design.contains("struct ODEmptyState"))
        XCTAssertTrue(
            design.contains("accessibilityReduceMotion")
        )
        for file in [
            "Sources/OneDayApp/FeedView.swift",
            "Sources/OneDayApp/IdeasView.swift",
            "Sources/OneDayApp/DeliverablesView.swift",
            "Sources/OneDayApp/CronViews.swift",
        ] {
            let text = try codeLines(source(file))
            XCTAssertTrue(
                text.contains("ODEmptyState("),
                "\(file) 主空态应走编排件"
            )
        }
    }

    // MARK: - 178 首启无付费面（OB-U6 定案把守）

    func testConnectWizardHasNoPaymentSurface() throws {
        let connect = try source(
            "Sources/OneDayApp/ConnectView.swift"
        )
        for token in [
            "StoreKit", "付费", "订阅", "购买",
            "purchase", "Purchase", "paywall",
        ] {
            XCTAssertFalse(
                connect.contains(token),
                "首连向导不得出现付费面符号：\(token)"
            )
        }
        // 欢迎面双出口在场（主路连接＋备路部署了解）
        XCTAssertTrue(connect.contains("连接已有服务器"))
        XCTAssertTrue(connect.contains("还没有服务器？了解部署"))
    }

    // MARK: - 178/OB-I3 失败常驻

    func testFailureNoticesUsePersistentTier() throws {
        let chat = try codeLines(
            source("Sources/OneDayApp/ChatView.swift")
        )
        // 常驻档消费点不少于失败改判点数（删除×2/编辑/
        // 重生成/反应×2/照片汇总/文件被拒/文件汇总/
        // 无效路径/朗读 = 11）
        let occurrences = chat.components(
            separatedBy: "tier: .persistent"
        ).count - 1
        XCTAssertGreaterThanOrEqual(occurrences, 11)
        // showNotice 对常驻档不起计时
        XCTAssertTrue(
            chat.contains(
                "if let seconds = item.tier.autoDismissSeconds"
            )
        )
        // 图片查看器失败分型在场
        let viewer = try codeLines(
            source("Sources/OneDayApp/ImageViewerView.swift")
        )
        XCTAssertTrue(viewer.contains("isFailure: true"))
        XCTAssertTrue(
            viewer.contains("guard !notice.isFailure")
        )
    }

    // MARK: - 179 个性化

    func testPersonalizationWiring() throws {
        let appearance = try codeLines(
            source("Sources/OneDayApp/AppearanceView.swift")
        )
        // §503 改判：personalizationSection 拆为背景/
        // 圆角两节（原二合一节退役），键引用不变
        XCTAssertTrue(appearance.contains("backgroundSection"))
        XCTAssertTrue(appearance.contains("bubbleCornerSection"))
        XCTAssertTrue(
            appearance.contains(
                "AppearanceStorageKeys.chatBubbleStyle"
            )
        )
        XCTAssertTrue(
            appearance.contains(
                "AppearanceStorageKeys.chatBackground"
            )
        )
        let palette = try codeLines(
            source("Sources/OneDayDesign/Palette.swift")
        )
        // 圆角与聊天背景都走 Core 读口现读
        XCTAssertTrue(
            palette.contains("AppearancePreferences.bubbleStyle()")
        )
        XCTAssertTrue(
            palette.contains(
                "AppearancePreferences.backgroundStyle()"
            )
        )
        XCTAssertTrue(palette.contains("static var chatBackground"))
        // §503：聊天页背景层改走单源呈现面 ChatBack-
        // groundSurface（其内读 Palette.chatBack-
        // ground 个性化口＋图案叠绘），外观预览同面
        XCTAssertTrue(palette.contains("struct ChatBackgroundSurface"))
        XCTAssertTrue(palette.contains("Palette.chatBackground"))
        let chat = try codeLines(
            source("Sources/OneDayApp/ChatView.swift")
        )
        XCTAssertTrue(chat.contains("ChatBackgroundSurface()"))
    }
}
