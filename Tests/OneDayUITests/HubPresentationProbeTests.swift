import XCTest

/// §449 探针（改前/改后同法同判据，基线与落码后各跑一轮对账）：
/// ①第 5 条：中枢开页时底栏在场与否——判据＝底栏元素帧
/// （不存在／高为 0／顶边已出窗口底三者居一为「已隐藏」）；
/// §502 改钉（归因见 DESIGN §502）：呈现由 push＋藏栏改
/// fullScreenCover 覆盖层后，底层底栏的 AX 帧恒在场、帧
/// 判据失效——判据增列「不可命中」（被覆盖层遮挡）为等
/// 价隐藏信号，帧三式保留兼容旧形态。另附截图留痕；
/// ②第 4 条旁证：点头像→中枢锚格分段（工作/身份）＋模型
/// 入口全数可命中的耗时，首开与重开各量一次。
/// 本探针在基线（rel-05106）上预期：第 5 条判 FAIL（底栏
/// 在场、与真机截图一致），第 4 条给出改前耗时基线。
final class HubPresentationProbeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testHubTabBarAndOpenTiming() throws {
        var lines: [String] = []
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        defer { app.terminate() }

        let capsuleEl = app.buttons["topbar.identityCapsule"]
        let avatarEl = app.buttons["topbar.hubAvatarButton"]
        guard capsuleEl.waitForExistence(timeout: 30),
              avatarEl.waitForExistence(timeout: 10)
        else {
            emit(lines + ["VERDICT=PROBE-NOT-UP"])
            XCTFail("演示装配顶簇未出现")
            return
        }
        let win = app.windows.firstMatch.frame

        // 聊天态底栏基线（在场为正常）；元素不存在
        // 时读帧会抛错（K 轮实证），一律先判存在
        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 10)
        lines.append(
            "CHAT_TABBAR exists=\(tabBar.exists) "
                + "frame=\(tabBar.exists ? fmt(tabBar.frame) : "n/a")")

        // 首开：点头像中心，量到「✕ 在屏＋锚格＋模型入口齐」
        let first = openHubAndMeasure(app, avatarEl: avatarEl)
        lines.append(
            "FIRST_OPEN_MS=\(first.ms) ready=\(first.ready)")
        lines.append(
            "FIRST_SHELL_MS=\(first.shellMs)")
        let hubTab = app.tabBars.firstMatch
        let hubTabExists = hubTab.exists
        lines.append(
            "HUB_TABBAR exists=\(hubTabExists) "
                + "frame=\(hubTabExists ? fmt(hubTab.frame) : "n/a") "
                + "winH=\(Int(win.height))")
        let shot = XCTAttachment(
            screenshot: app.screenshot())
        shot.name = "hub-open-state"
        shot.lifetime = .keepAlways
        add(shot)
        let tabHidden = !hubTabExists
            || (hubTabExists && hubTab.frame.height == 0)
            || (hubTabExists && hubTab.frame.minY >= win.height - 1)
            || (hubTabExists && !hubTab.isHittable)
        lines.append("TABBAR_HIDDEN=\(tabHidden)")

        // 关枢纽回聊天
        hubCloseButton(app)?.tap()
        let backDeadline = Date().addingTimeInterval(6)
        while !capsuleEl.isHittable, Date() < backDeadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        lines.append("BACK_TO_CHAT=\(capsuleEl.isHittable)")
        // §449 变体 K 回归门：pop 回聊天后底栏须回归
        let tabAfter = app.tabBars.firstMatch
        _ = tabAfter.waitForExistence(timeout: 10)
        lines.append(
            "CHAT_TABBAR_AFTER exists=\(tabAfter.exists)")

        // 重开：同法量耗时（同会话热态，第 4 条主判据）
        let second = openHubAndMeasure(app, avatarEl: avatarEl)
        lines.append(
            "REOPEN_MS=\(second.ms) ready=\(second.ready)")
        lines.append(
            "REOPEN_SHELL_MS=\(second.shellMs)")
        hubCloseButton(app)?.tap()

        lines.append("VERDICT="
            + (tabHidden ? "TABBAR-HIDDEN" : "TABBAR-VISIBLE"))
        emit(lines)
        XCTAssertTrue(
            tabHidden,
            "中枢开页底栏仍在场可命中（第 5 条）："
                + "frame=\(hubTabExists ? fmt(hubTab.frame) : "n/a")")
        XCTAssertTrue(
            tabAfter.exists,
            "pop 回聊天后底栏未回归（变体 K 回归门）")
    }

    /// 点头像→轮询至中枢内容齐（✕ 在屏＋工作/身份两锚格
    /// ＋选择模型入口全数存在且可命中），返回耗时毫秒
    private func openHubAndMeasure(
        _ app: XCUIApplication, avatarEl: XCUIElement
    ) -> (ms: Int, ready: Bool, shellMs: Int) {
        let origin = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let frame = avatarEl.frame
        let start = Date()
        origin.withOffset(CGVector(
            dx: frame.midX, dy: frame.midY)).tap()
        var shellMs = -1
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if shellMs < 0, hubCloseButton(app) != nil {
                shellMs = Int(
                    Date().timeIntervalSince(start) * 1000)
            }
            if shellMs >= 0,
               segmentReady(app, "工作"),
               segmentReady(app, "身份"),
               modelEntryReady(app) {
                return (
                    Int(Date().timeIntervalSince(start) * 1000),
                    true, shellMs)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return (
            Int(Date().timeIntervalSince(start) * 1000),
            false, shellMs)
    }

    private func segmentReady(
        _ app: XCUIApplication, _ name: String
    ) -> Bool {
        let seg = app.buttons[name]
        return seg.exists && seg.isHittable
    }

    private func modelEntryReady(_ app: XCUIApplication) -> Bool {
        let entry = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '选择模型'")
        ).firstMatch
        return entry.exists && entry.isHittable
    }

    /// 枢纽 ✕（与 TopBarSingleActionTapTests 同口径：在屏语义）
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

    private func fmt(_ rect: CGRect) -> String {
        String(
            format: "(%.0f,%.0f %.0f×%.0f)",
            rect.minX, rect.minY, rect.width, rect.height)
    }

    private func emit(_ lines: [String]) {
        let text = lines.joined(separator: "\n")
        print("HUB-PROBE-BEGIN")
        print(text)
        print("HUB-PROBE-END")
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
