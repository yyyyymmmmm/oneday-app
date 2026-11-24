import XCTest

/// 活头像逐状态实跑截图（§479 验收）：DEBUG 画廊
/// 页驱动真实状态机与播放器，逐态截屏留证（附件
/// 随 xcresult 导出）。帧内是真 AVPlayer 画面——
/// 本套只断言状态标签与按钮可达，画面对错归人工
/// 看图＋真机 verdict，不拿像素冒充手感。
final class LivingAvatarGalleryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-livingAvatarGallery"]
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(
            screenshot: XCUIScreen.main.screenshot()
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapAndWaitState(
        _ button: String, _ state: String,
        settle: TimeInterval = 1.4
    ) {
        app.buttons[button].tap()
        let label = app.staticTexts["gallery.state"]
        let predicate = NSPredicate(
            format: "label == %@", state
        )
        let exp = expectation(
            for: predicate, evaluatedWith: label
        )
        wait(for: [exp], timeout: 8)
        Thread.sleep(forTimeInterval: settle)
    }

    func testLivingAvatarStateShots() {
        let label = app.staticTexts["gallery.state"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        // 空闲：idle 片段循环中
        Thread.sleep(forTimeInterval: 1.6)
        shot("01-idle-light")
        tapAndWaitState("干活写", "working-write")
        shot("02-working-write")
        tapAndWaitState("干活通用", "working-general")
        shot("03-working-general")
        // 完成是瞬时态：标签一到就截
        tapAndWaitState("完成", "done", settle: 0.7)
        shot("04-done")
        tapAndWaitState("卡住", "blocked")
        shot("05-blocked-static")
        // 深色下睡着（静态）→醒来（醒来片段仅深色）
        app.buttons["深色"].tap()
        tapAndWaitState("睡着", "asleep", settle: 0.5)
        shot("06-asleep-dark-static")
        app.buttons["醒来"].tap()
        let wakePredicate = NSPredicate(
            format: "label == %@", "waking"
        )
        let wakeExp = expectation(
            for: wakePredicate, evaluatedWith: label
        )
        wait(for: [wakeExp], timeout: 8)
        Thread.sleep(forTimeInterval: 0.7)
        shot("07-waking-dark")
    }
}
