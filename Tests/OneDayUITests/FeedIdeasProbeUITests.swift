import XCTest

/// §486 探针（改前/改后同法同判据）：演示模式下动态/点子
/// 两页静止＋滚动两帧截图留痕＋关键元素帧打印（标题/簇/
/// 字段），供与参照帧逐项量测对位。基线（rel-05113）与
/// 落码后各跑一轮，判据＝报告对位表。两页分开成两个
/// 测试方法，各自独立启动，避免一页失败吞掉另一页证据。
final class FeedIdeasProbeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testFeedFrames() throws {
        var lines: [String] = []
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        defer { app.terminate() }

        let capsule = app.buttons["topbar.identityCapsule"]
        guard capsule.waitForExistence(timeout: 30) else {
            emit(lines + ["VERDICT=PROBE-NOT-UP"])
            XCTFail("演示装配顶簇未出现")
            return
        }
        tapTab(app, index: 1, label: "动态")
        Thread.sleep(forTimeInterval: 2)
        lines.append("FEED_CAPSULE exists=\(app.buttons["topbar.identityCapsule"].exists) frame=\(fmt(app.buttons["topbar.identityCapsule"].frame))")
        lines.append("FEED_SLIDERS exists=\(app.buttons["编辑简报"].exists)")
        shot(app, name: "feed-resting")
        app.swipeUp()
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        lines.append("FEED_SCROLLED_CAPSULE exists=\(app.buttons["topbar.identityCapsule"].exists)")
        lines.append("FEED_SCROLLED_SLIDERS exists=\(app.buttons["编辑简报"].exists)")
        shot(app, name: "feed-scrolled")
        emit(lines + ["VERDICT=FEED-DONE"])
    }

    func testIdeasFrames() throws {
        var lines: [String] = []
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        defer { app.terminate() }

        let capsule = app.buttons["topbar.identityCapsule"]
        guard capsule.waitForExistence(timeout: 30) else {
            emit(lines + ["VERDICT=PROBE-NOT-UP"])
            XCTFail("演示装配顶簇未出现")
            return
        }
        tapTab(app, index: 2, label: "点子")
        Thread.sleep(forTimeInterval: 2)
        lines.append("IDEAS_CAPSULE exists=\(app.buttons["topbar.identityCapsule"].exists) frame=\(fmt(app.buttons["topbar.identityCapsule"].frame))")
        shot(app, name: "ideas-resting")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        shot(app, name: "ideas-scrolled")
        emit(lines + ["VERDICT=IDEAS-DONE"])
    }

    private func tapTab(_ app: XCUIApplication, index: Int, label: String) {
        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 10)
        let byLabel = tabBar.buttons[label]
        if byLabel.exists {
            byLabel.tap()
        } else {
            tabBar.buttons.element(boundBy: index).tap()
        }
    }

    private func shot(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func fmt(_ r: CGRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width))x\(Int(r.height)))"
    }

    private func emit(_ lines: [String]) {
        let text = lines.joined(separator: "\n")
        let attachment = XCTAttachment(string: text)
        attachment.name = "probe-lines"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(text)
    }
}
