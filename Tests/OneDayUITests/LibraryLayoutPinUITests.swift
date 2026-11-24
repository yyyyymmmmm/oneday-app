import XCTest

/// §473 件四回归门：资源库页头钉顶——有内容态与空
/// 态的页头钮（会话列表）顶距必须同高。旧病：空态
/// 分支 ODEmptyState 刚性高度直接放进根 VStack，
/// 整栈收缩为内容高被宿主垂直居中，页头被推到屏
/// 高约 39%（用户 2026-11-24 真机截图实证；定因量
/// 测：有内容 y=55、搜索空态 y=156.7，iPhone 17e
/// 模拟器）。修法：空态分支占满内容区（frame
/// maxHeight .infinity），根栈恒全高。
final class LibraryLayoutPinUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testHeaderPinnedInContentAndEmptyStates() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-odDemoMode", "-AppleLanguages", "(zh-Hans)",
        ]
        app.launch()
        let tab = app.tabBars.buttons["资源库"]
        XCTAssertTrue(tab.waitForExistence(timeout: 25))
        tab.tap()
        let drawerBtn = app.buttons["会话列表"]
        XCTAssertTrue(drawerBtn.waitForExistence(timeout: 25))
        let contentHeaderY = drawerBtn.frame.minY
        XCTAssertGreaterThan(contentHeaderY, 0)
        // §473 件四②：大标题在位（兄弟页统一口径）
        let pageTitle = app.staticTexts["资源库"]
        XCTAssertTrue(pageTitle.waitForExistence(timeout: 5))
        let contentTitleY = pageTitle.frame.minY
        let contentShot = XCTAttachment(
            screenshot: app.screenshot()
        )
        contentShot.name = "library-content-pinned"
        contentShot.lifetime = .keepAlways
        add(contentShot)

        // 搜索乱词 → 空态（没有匹配的文件）
        let searchBtn = app.buttons["搜索"]
        XCTAssertTrue(searchBtn.waitForExistence(timeout: 10))
        searchBtn.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("zzzzqqqq")
        XCTAssertTrue(
            app.staticTexts["没有匹配的文件"]
                .waitForExistence(timeout: 8),
            "乱词搜索应落空态"
        )
        let emptyHeaderY = app.buttons["会话列表"].frame.minY
        XCTAssertEqual(
            emptyHeaderY, contentHeaderY, accuracy: 1.0,
            "空态页头必须与有内容态同高（钉顶），"
                + "实测 content=\(contentHeaderY) empty=\(emptyHeaderY)"
        )
        XCTAssertEqual(
            pageTitle.frame.minY, contentTitleY, accuracy: 1.0,
            "空态大标题必须与有内容态同高（钉顶），"
                + "实测 content=\(contentTitleY) empty=\(pageTitle.frame.minY)"
        )
        // 空态本体在内容区内（页头之下、屏幕下半之前）
        let title = app.staticTexts["没有匹配的文件"]
        XCTAssertGreaterThan(title.frame.minY, emptyHeaderY + 80)
        XCTAssertLessThan(title.frame.minY, app.frame.height * 0.75)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "library-empty-pinned"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
