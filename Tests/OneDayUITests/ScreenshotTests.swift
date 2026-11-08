import XCTest

/// 截图验收环（0.1.3）：演示模式下截六页全屏图，附件随
/// xcresult 导出，CI 再按名整理为 oneday-shots 产物。
/// 浅色模式＋默认字体档由启动参数钉死，截图只比版式不比数据；
/// 全部数据来自 App 内静态样本（-odDemoMode / -odDemoConnect），
/// 不连任何服务器。聊天是默认落点，抽屉经顶栏左键打开截展开态。
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleInterfaceStyle", "Light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ] + extra
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 等某段文字出现（标签子串匹配，兼容 Markdown 渲染后的整段标签）
    private func waitText(_ app: XCUIApplication, _ fragment: String, timeout: TimeInterval = 20) {
        let predicate = NSPredicate(format: "label CONTAINS %@", fragment)
        let element = app.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "未等到文本：\(fragment)"
        )
    }

    /// 页签点按（0.2.4 原生 TabView）：条目名称只在无障碍
    /// 标签里，标识与标签双通道匹配，先到先点
    private func tapTab(_ app: XCUIApplication, id: String, label: String) {
        let predicate = NSPredicate(
            format: "identifier == %@ OR label == %@", id, label
        )
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(
            button.waitForExistence(timeout: 20),
            "未等到页签：\(label)"
        )
        button.tap()
    }

    /// 等动效落稳（抽屉弹簧 0.35s 口径，留足余量再截图）
    private func settle(_ seconds: TimeInterval = 0.9) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// 01 连接页：未连接态，字段预填展示值
    func test01ConnectPage() {
        let app = launch(["-odDemoConnect"])
        // 等 onAppear 预填落地：账号字段值变为 admin 才说明
        // 演示预填完成（SecureField 圆点也在同一时刻就位）
        let adminField = app.textFields.matching(
            NSPredicate(format: "value == %@", "admin")
        ).firstMatch
        XCTAssertTrue(
            adminField.waitForExistence(timeout: 20),
            "演示预填未落地（账号字段未变为 admin）"
        )
        XCTAssertTrue(app.buttons["测试并连接"].waitForExistence(timeout: 20))
        waitText(app, "连接你的 Hermes 服务器")
        settle(0.5)
        capture("01-connect")
    }

    /// 02–06 主界面：聊天落点 → 抽屉展开 → 总览 → 文件 → 设置
    func test02MainPages() {
        let app = launch(["-odDemoMode"])

        // 聊天（默认落点）：种子对话落稳、演示流式行进中段再截
        waitText(app, "一切正常")
        waitText(app, "先从定时任务模块动手", timeout: 25)
        // 0.2.4 重叠架构硬指标：上滑一截，让消息文字滚到
        // 发送舱与底栏背后——截图里必须能看见文字透过玻璃
        // 的模糊影（静止停在底部时内容边距会把末条顶到
        // 玻璃上方，天然无重叠，故主动制造滚动中段）
        let dragStart = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)
        )
        let dragEnd = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36)
        )
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        settle(0.6)
        capture("02-chat")

        // 抽屉（0.2.1 重做）：身份块＋时间分组＋服务端会话组
        app.buttons["会话列表"].tap()
        waitText(app, "今天")
        waitText(app, "下雨天节点会不会掉线")
        waitText(app, "节点巡检")
        settle()
        capture("03-chat-sidebar")

        // 点 scrim 右侧收起抽屉
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        settle(0.6)

        // 总览（五段；状态头可点进状态屏，本环不点）
        tapTab(app, id: "tab.overview", label: "总览")
        waitText(app, "今日 Token")
        waitText(app, "帮我看看服务器状态")
        capture("04-overview")

        // 文件（0.2.2 交付物库）：影音网格为先（§6 形态分工）；
        // 分段标签是按钮不是 staticText，直接等控件出现
        tapTab(app, id: "tab.files", label: "文件")
        XCTAssertTrue(
            app.segmentedControls.buttons["影音"].waitForExistence(timeout: 20),
            "未等到分段控件：影音"
        )
        settle()
        capture("05-files")

        // 文件段紧凑行（审查用附加帧，不进六张留档）
        app.segmentedControls.buttons["文件"].tap()
        waitText(app, "网络巡检周报.md")
        waitText(app, "每日简报-1108.txt")
        capture("05b-files-list")

        // 设置（0.2.1 分组目录）：等智能体组与外观组行到位
        tapTab(app, id: "tab.settings", label: "设置")
        waitText(app, "定时任务")
        waitText(app, "主题")
        capture("06-settings")
    }
}
