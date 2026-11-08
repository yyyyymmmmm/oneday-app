import XCTest

/// 0.2.7 逐环探针（诊断专用，不是回归断言）：真机拼音＋
/// 标记文本态下发送舱膨胀约 139pt（图上量测），英文键盘
/// 在模拟器测不出。本类在三种条件下逐环打印 frame——
/// composerZone（底部发送区）/ composerBar（inputBar）/
/// composerRow（玻璃行）/ composerField / ＋键 / 键盘高：
/// ①默认玻璃（GlassEffectContainer＋union）＋编程 marked
/// text；②裸玻璃（-odBareGlass）＋marked text；③真实拼
/// 音键盘（工作流预置 HIToolbox 输入源）打拼音选词。
/// 哪一环在组合态单独变高，哪一环就是膨胀源（§11）。
final class ComposerPinyinProbeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch(extraArgs: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleInterfaceStyle", "Light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            "-odDemoMode",
        ] + extraArgs
        app.launch()
        let seed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "一切正常")
        ).firstMatch
        XCTAssertTrue(seed.waitForExistence(timeout: 25), "种子对话未出现")
        return app
    }

    private func sample(_ app: XCUIApplication, _ tag: String) {
        let zone = app.otherElements["composerZone"]
        let bar = app.otherElements["composerBar"]
        let row = app.otherElements["composerRow"]
        let field = app.textFields["composerField"]
        let attach = app.buttons["添加附件"]
        let keyboard = app.keyboards.firstMatch
        func f(_ e: XCUIElement) -> String {
            e.exists ? "\(e.frame)" : "MISSING"
        }
        print("[PROBE] \(tag) zone=\(f(zone))")
        print("[PROBE] \(tag) bar=\(f(bar))")
        print("[PROBE] \(tag) row=\(f(row))")
        print("[PROBE] \(tag) field=\(f(field)) value=\(field.value ?? "nil")")
        print("[PROBE] \(tag) attach=\(f(attach))")
        print("[PROBE] \(tag) keyboardShown=\(keyboard.exists) kbFrame=\(f(keyboard))")
    }

    private func focusField(_ app: XCUIApplication) {
        let field = app.textFields["composerField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "未找到输入框")
        field.tap()
        let focusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: field
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [focusExpectation], timeout: 10),
            .completed, "输入框未获得键盘焦点"
        )
    }

    /// ①②共用流程：聚焦后 MarkedTextDriver 在 +0.8s 置
    /// marked、+2.8s 提交并再置 marked，测试在窗口内采样
    private func markedFlow(_ app: XCUIApplication, prefix: String) {
        sample(app, "\(prefix)-idle")
        focusField(app)
        settle(1.6)
        sample(app, "\(prefix)-marked")
        capture("probe-\(prefix)-marked")
        settle(2.8)
        sample(app, "\(prefix)-predictive")
        capture("probe-\(prefix)-predictive")
        settle(2.0)
        sample(app, "\(prefix)-settled")
    }

    func testProbeMarkedDefaultGlass() {
        let app = launch(extraArgs: ["-odMarkedProbe"])
        markedFlow(app, prefix: "def")
    }

    func testProbeMarkedBareGlass() {
        let app = launch(extraArgs: ["-odMarkedProbe", "-odBareGlass"])
        markedFlow(app, prefix: "bare")
    }

    /// ③真实拼音：工作流已把拼音置入模拟器输入源；打
    /// jingjinji 选词提交、再打 huanjing 停在预测态采样。
    /// 拼音未生效（无候选条）时打印 UNAVAILABLE 并跳过。
    func testProbePinyinKeyboard() {
        let app = launch(extraArgs: [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
        ])
        sample(app, "pin-idle")
        focusField(app)
        settle(1.2)
        let keyboard = app.keyboards.firstMatch
        print("[PROBE] pin keyboardFrame=\(keyboard.exists ? "\(keyboard.frame)" : "MISSING")")
        let field = app.textFields["composerField"]
        field.typeText("jingjinji")
        settle(1.2)
        sample(app, "pin-marked-jingjinji")
        capture("probe-pin-marked")
        // 候选条：键盘区内的静态文本候选词，点第一个提交
        let candidate = app.keyboards.staticTexts.firstMatch
        if candidate.exists {
            candidate.tap()
            settle(0.8)
            print("[PROBE] pin committed value=\(field.value ?? "nil")")
        } else {
            print("[PROBE] pin UNAVAILABLE no candidate bar")
            return
        }
        field.typeText("huanjing")
        settle(1.2)
        sample(app, "pin-marked-huanjing")
        capture("probe-pin-predictive")
        let candidate2 = app.keyboards.staticTexts.firstMatch
        if candidate2.exists {
            candidate2.tap()
            settle(0.8)
        }
        sample(app, "pin-committed")
        capture("probe-pin-committed")
    }
}
