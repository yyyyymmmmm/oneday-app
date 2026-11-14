import XCTest

/// 抽屉行上下文菜单系统级验收：打 -odDemoMode 真 App
/// 生产装配，按生产汉堡钮开抽屉，由 XCUITest 投递长按。
final class DrawerRowContextMenuTests: XCTestCase {
    private let sidePrefix = "drawer.row.side."
    private let localRowPrefix = "drawer.row.side.local."
    private let serverRowID =
        "drawer.row.side.server.oneday-ai-drawer-longpress"
    private let channelRowID = "drawer.row.channel.hermes"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLocalAndCurrentSelectedRowsExposeFourActions() throws {
        let app = launchDemoApp()
        openDrawer(app)
        let localRow = try firstLocalRow(in: app)
        assertMenu(on: localRow, items: ["重命名", "置顶", "归档", "删除会话"], in: app)
        dismissMenuAndDrawer(in: app)

        // 点击旁聊行走生产选择路径；抽屉关闭后再由生产钮重开。
        openDrawer(app)
        let selectedRow = try firstLocalRow(in: app)
        let selectedRowID = selectedRow.identifier
        selectedRow.tap()
        openDrawer(app)
        let selected = app.buttons[selectedRowID]
        reveal(selected, in: app)
        assertMenu(on: selected, items: ["重命名", "置顶", "归档", "删除会话"], in: app)
        dismissMenuAndDrawer(in: app)
    }

    func testUnadoptedServerRowExposesFourActions() throws {
        let app = launchDemoApp()
        openDrawer(app)
        let row = app.buttons[serverRowID]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "演示未收养行未出现")
        assertMenu(on: row, items: ["重命名", "置顶", "归档", "删除会话"], in: app)
        dismissMenuAndDrawer(in: app)
    }

    func testHermesChannelRowExposesOpenAction() throws {
        let app = launchDemoApp()
        openDrawer(app)
        let row = app.buttons[channelRowID]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Hermes 频道行未出现")
        assertMenu(on: row, items: ["打开"], in: app)
        dismissMenuAndDrawer(in: app)
    }

    func testSideListFirstAndLastRowsExposeContextMenu() throws {
        let app = launchDemoApp()
        openDrawer(app)
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", sidePrefix)
        )
        XCTAssertGreaterThanOrEqual(rows.count, 3, "旁聊样本不足以验首、中、末行")

        let orderedRows = rows.allElementsBoundByIndex.sorted {
            $0.frame.minY < $1.frame.minY
        }
        let first = try XCTUnwrap(orderedRows.first)
        assertMenu(on: first, items: ["重命名"], in: app)
        dismissMenuAndDrawer(in: app)

        openDrawer(app)
        let refreshedRows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", sidePrefix)
        )
        XCTAssertGreaterThanOrEqual(refreshedRows.count, 3)
        let orderedRefreshedRows = refreshedRows.allElementsBoundByIndex.sorted {
            $0.frame.minY < $1.frame.minY
        }
        let last = try XCTUnwrap(orderedRefreshedRows.last)
        assertMenu(on: last, items: ["重命名"], in: app)
        dismissMenuAndDrawer(in: app)
    }

    private func launchDemoApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        return app
    }

    private func openDrawer(_ app: XCUIApplication) {
        let openButton = app.buttons["drawer.open"]
        XCTAssertTrue(
            openButton.waitForExistence(timeout: 15), "生产抽屉入口未出现"
        )
        if openButton.isHittable {
            openButton.tap()
        }
        let row = app.buttons[channelRowID]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "生产抽屉未打开")
    }

    private func firstLocalRow(in app: XCUIApplication) throws -> XCUIElement {
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", localRowPrefix)
        )
        XCTAssertGreaterThanOrEqual(rows.count, 1, "演示本地旁聊行未出现")
        let row = rows.element(boundBy: 0)
        reveal(row, in: app)
        return row
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<8 where !element.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "目标行滚动后仍不可命中：\(element.identifier)")
    }

    /// 预注册判点：1.2 秒系统长按后，要求菜单项存在且 hittable。
    private func assertMenu(
        on row: XCUIElement, items: [String], in app: XCUIApplication
    ) {
        reveal(row, in: app)
        row.press(forDuration: 1.2)
        for title in items {
            let item = app.buttons[title]
            XCTAssertTrue(item.waitForExistence(timeout: 5), "长按菜单缺少「\(title)」")
            XCTAssertTrue(item.isHittable, "长按菜单项不可达：「\(title)」")
        }
    }

    /// 点抽屉外的生产前景窄条：关闭菜单，同时经容器原有点按关闭抽屉。
    private func dismissMenuAndDrawer(in app: XCUIApplication) {
        let outside = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)
        )
        outside.tap()
        let menuDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.buttons["重命名"]
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [menuDismissed], timeout: 5), .completed,
            "菜单外点击后上下文菜单仍在"
        )

        let openButton = app.buttons["drawer.open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 10))
        if !openButton.isHittable { outside.tap() }
        let drawerClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: openButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [drawerClosed], timeout: 10), .completed,
            "菜单外点击后生产抽屉未关闭"
        )
    }
}
