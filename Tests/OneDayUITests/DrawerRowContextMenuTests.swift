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
        // CI 模拟器是英文区域：不钉语言时全 App 走 en 本地
        // 化，菜单项是 Rename/Pin/Archive（首两轮 CI 快照实
        // 证：菜单明明开着、项也在树里，只是查中文标签查不
        // 到）。产品主语言是简体中文（真机菜单即中文四
        // 项），测试钉回 zh-Hans 与真机口径一致再断言。
        app.launchArguments = [
            "-odDemoMode",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_Hans_CN",
        ]
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

    /// 预注册判点：标题区坐标 1.5 秒系统长按后，要求菜单
    /// 项存在且 hittable。按压点取行宽 30% 处（标题区）而
    /// 非行正中——正中是标题与行尾之间的 Spacer 死区。
    /// 首项等不到时把当时全树按钮清单写进断言信息，下轮
    /// 日志直接分清「菜单没弹」与「弹了但项不在按钮树」。
    private func assertMenu(
        on row: XCUIElement, items: [String], in app: XCUIApplication
    ) {
        reveal(row, in: app)
        let pressPoint = row.coordinate(
            withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)
        )
        pressPoint.press(forDuration: 1.5)
        for (index, title) in items.enumerated() {
            let item = app.buttons[title]
            let timeout: TimeInterval = index == 0 ? 10 : 5
            if !item.waitForExistence(timeout: timeout) {
                XCTFail(
                    "长按菜单缺少「\(title)」；当时按钮树："
                        + treeSnapshot(in: app)
                )
            }
            XCTAssertTrue(item.isHittable, "长按菜单项不可达：「\(title)」")
        }
    }

    /// 失败取证：全树按钮的标识/标签紧凑清单
    private func treeSnapshot(in app: XCUIApplication) -> String {
        let buttons = app.buttons.allElementsBoundByIndex.map {
            "\($0.identifier)|\($0.label)"
        }
        return buttons.joined(separator: ", ")
    }

    /// 点抽屉外的生产前景窄条关菜单、关抽屉。顺序不能反：
    /// 抽屉打开时容器把内容宿主整树 accessibilityEle-
    /// mentsHidden（DrawerContainerView），drawer.open 在
    /// 树里根本不存在——必须先点窄条把抽屉关掉，才等得到
    /// 它重新出现且可命中（首轮 CI 断 :147 即此序错）。
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

        // 菜单已散，再点一次窄条关抽屉（若第一击已连抽屉
        // 一并关掉，这击落在聊天页空白处、无副作用）
        outside.tap()
        let openButton = app.buttons["drawer.open"]
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
