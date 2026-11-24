import XCTest

/// §502 中枢卡片呈现 UI 钉测（演示模式，与 HubPres-
/// entationProbeTests 同启动配方）：开页满屏＋底栏
/// 被覆盖、✕ 飞出关页后底栏即时回归（§472 验收口
/// 径平移）、快拖右滑关闭、慢短拖弹回、慢长拖（过
/// 半屏）关闭、纵向滚动不误触关闭。手势判据对应量
/// 测 §2.6 投影模型与 §2.8 方向锁仲裁。
final class HubCardPresentationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 开页形态＋✕ 关页回归

    func testHubOpensFullscreenAndCloseReturnsFast() throws {
        let app = launchApp()
        defer { app.terminate() }
        let win = app.windows.firstMatch.frame

        openHub(app)
        // 卡片静止态＝满屏：hub.card 帧与窗口帧对账
        let card = app.otherElements["hub.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(card.frame.width, win.width, accuracy: 2)
        XCTAssertEqual(card.frame.height, win.height, accuracy: 2)
        // 底栏被覆盖层盖住（探针同判据：不存在／高
        // 0／顶边出窗底居一）
        let tab = app.tabBars.firstMatch
        let tabHidden = !tab.exists || tab.frame.height == 0
            || tab.frame.minY >= win.height - 1
            || !tab.isHittable
        XCTAssertTrue(tabHidden, "中枢开页底栏未被覆盖")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "hub-card-open"
        shot.lifetime = .keepAlways
        add(shot)

        // ✕ 关页：量「点✕→聊天胶囊可命中」耗时（§472
        // 口径平移：飞出 0.43s＋落账，上限取 1.6s 并
        // 把实测值留档）
        let capsule = app.buttons["topbar.identityCapsule"]
        let close = try XCTUnwrap(hubCloseButton(app))
        let start = Date()
        close.tap()
        var elapsed = -1
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if capsule.exists && capsule.isHittable {
                elapsed = Int(Date().timeIntervalSince(start) * 1000)
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertGreaterThanOrEqual(elapsed, 0, "关页后聊天面未回归")
        XCTAssertLessThan(elapsed, 1600, "关页回归耗时 \(elapsed)ms 超带")
        let tabAfter = app.tabBars.firstMatch
        XCTAssertTrue(tabAfter.waitForExistence(timeout: 5))
        emit(["CLOSE_RETURN_MS=\(elapsed)"])
    }

    // MARK: - 右滑关闭（投影判定）

    func testHubFastRightDragDismisses() throws {
        let app = launchApp()
        defer { app.terminate() }
        openHub(app)
        // 快速右拖：位移约 65% 屏宽＋高速 → 投影过半关闭
        drag(app, from: (0.30, 0.45), to: (0.95, 0.45), velocity: .fast)
        assertHubDismissed(app)
    }

    func testHubSlowLongDragDismisses() throws {
        let app = launchApp()
        defer { app.terminate() }
        openHub(app)
        // 慢拖至约 62% 屏宽松手：位移本身过半 → 关闭
        // （§7.4 投影阈值上界验证的 UI 对应项）
        drag(app, from: (0.20, 0.45), to: (0.82, 0.45), velocity: .slow)
        assertHubDismissed(app)
    }

    func testHubSlowShortDragSpringsBack() throws {
        let app = launchApp()
        defer { app.terminate() }
        let win = app.windows.firstMatch.frame
        openHub(app)
        // 慢短拖：约 25% 屏宽、低速 → 投影不过半弹回
        drag(app, from: (0.25, 0.45), to: (0.50, 0.45), velocity: .slow)
        // 弹回沉降后卡片仍满屏在场、✕ 可命中
        Thread.sleep(forTimeInterval: 1.5)
        let card = app.otherElements["hub.card"]
        XCTAssertTrue(card.exists)
        XCTAssertEqual(card.frame.width, win.width, accuracy: 2)
        XCTAssertNotNil(hubCloseButton(app))
    }

    // MARK: - 纵向仲裁

    func testHubVerticalScrollDoesNotDismiss() throws {
        let app = launchApp()
        defer { app.terminate() }
        openHub(app)
        // 纵向大拖（列表滚动方向）：不许触发卡片关闭
        drag(app, from: (0.50, 0.70), to: (0.50, 0.30), velocity: .default)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertNotNil(hubCloseButton(app))
        XCTAssertTrue(app.otherElements["hub.card"].exists)
    }

    // MARK: - 配方（与 HubPresentationProbeTests 同法）

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        return app
    }

    private func openHub(_ app: XCUIApplication) {
        let capsule = app.buttons["topbar.identityCapsule"]
        let avatar = app.buttons["topbar.hubAvatarButton"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 30))
        XCTAssertTrue(avatar.waitForExistence(timeout: 10))
        let origin = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let f = avatar.frame
        origin.withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        XCTAssertTrue(
            app.otherElements["hub.card"].waitForExistence(timeout: 15),
            "中枢卡片未开")
    }

    private func assertHubDismissed(_ app: XCUIApplication) {
        let capsule = app.buttons["topbar.identityCapsule"]
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if capsule.exists && capsule.isHittable
                && !app.otherElements["hub.card"].exists {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("右滑后中枢未关闭")
    }

    private func drag(
        _ app: XCUIApplication,
        from: (CGFloat, CGFloat), to: (CGFloat, CGFloat),
        velocity: XCUIGestureVelocity
    ) {
        let win = app.windows.firstMatch
        let start = win.coordinate(withNormalizedOffset:
            CGVector(dx: from.0, dy: from.1))
        let end = win.coordinate(withNormalizedOffset:
            CGVector(dx: to.0, dy: to.1))
        start.press(
            forDuration: 0.05,
            thenDragTo: end,
            withVelocity: velocity,
            thenHoldForDuration: 0.1)
    }

    /// 枢纽 ✕（与 HubPresentationProbeTests 同口径）
    private func hubCloseButton(
        _ app: XCUIApplication
    ) -> XCUIElement? {
        let win = app.windows.firstMatch.frame
        for label in ["关闭", "Close"] {
            let el = app.buttons[label]
            if el.exists, el.isHittable,
               isFullyOnScreen(el.frame, in: win) {
                return el
            }
        }
        return app.buttons.allElementsBoundByIndex.first {
            $0.exists && $0.isHittable
                && isFullyOnScreen($0.frame, in: win)
                && $0.frame.minX < 70 && $0.frame.minY < 140
                && $0.frame.width <= 44 && $0.frame.width > 0
        }
    }

    private func isFullyOnScreen(
        _ frame: CGRect, in win: CGRect
    ) -> Bool {
        frame.width > 0 && frame.height > 0
            && frame.minX >= win.minX - 1
            && frame.minY >= win.minY - 1
            && frame.maxX <= win.maxX + 1
            && frame.maxY <= win.maxY + 1
    }

    private func emit(_ lines: [String]) {
        let text = lines.joined(separator: "\n")
        print("HUBCARD-BEGIN")
        print(text)
        print("HUBCARD-END")
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
