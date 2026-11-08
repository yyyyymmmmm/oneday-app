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

    /// 02–06 主界面：聊天落点 → 抽屉展开 → 总览 → 智能体 → 设置
    func test02MainPages() {
        let app = launch(["-odDemoMode"])

        // 聊天（默认落点）：种子对话落稳、演示流式行进中段再截
        waitText(app, "一切正常")
        waitText(app, "先从定时任务模块动手", timeout: 25)
        capture("02-chat")

        // 抽屉：顶栏左键唤出，等分段标题与底行到位、弹簧落稳再截
        app.buttons["会话列表"].tap()
        waitText(app, "本机会话")
        waitText(app, "下雨天节点会不会掉线")
        settle()
        capture("03-chat-sidebar")

        // 点 scrim 右侧收起抽屉
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        settle(0.6)

        // 总览（IA v3 五段）：等指标行与最近会话到位
        app.tabBars.buttons["总览"].tap()
        waitText(app, "今日 Token")
        waitText(app, "帮我看看服务器状态")
        capture("04-overview")

        // 智能体（运维四模块目录，等摘要值落地）
        app.tabBars.buttons["智能体"].tap()
        waitText(app, "定时任务")
        waitText(app, "已装 4 个")
        capture("05-agent")

        // 设置（四组目录，等当前值行到位）
        app.tabBars.buttons["设置"].tap()
        waitText(app, "对话模型")
        waitText(app, "当前服务器")
        capture("06-settings")
    }
}
