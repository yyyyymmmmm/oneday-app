import XCTest

/// 0.2.6 回归：键盘弹起时发送舱膨胀缺陷（用户真机截图实证，
/// 0.2.5 的 fixedSize 断环只治住静态覆盖态、没治住聚焦态）。
/// 本测试在演示模式下聚焦输入框调起软键盘，断言发送舱高
/// 度保持单行规格（54 ± 4）；同时打印顶栏胶囊宽与多行态
/// 高度作诊断量（缺陷 B 与多行形态的实测依据）。
final class ComposerKeyboardTests: XCTestCase {
    override func setUpWithError() throws {
        // 诊断量要全打印出来再失败，单条断言不中断整场
        continueAfterFailure = true
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func testComposerHeightAcrossKeyboardStates() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleInterfaceStyle", "Light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            "-odDemoMode",
        ]
        app.launch()

        // 等种子对话落稳（与 ScreenshotTests 同一锚点）
        let seed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "一切正常")
        ).firstMatch
        XCTAssertTrue(seed.waitForExistence(timeout: 25), "种子对话未出现")

        let composer = app.descendants(matching: .any)
            .matching(identifier: "composerBar").firstMatch
        XCTAssertTrue(
            composer.waitForExistence(timeout: 20),
            "未找到发送舱容器（composerBar）"
        )
        let field = app.textFields["发消息…"].exists
            ? app.textFields["发消息…"]
            : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "未找到输入框")

        let headerCapsule = app.buttons["切换模型"]
        print("[MEASURE] idle composerHeight=\(composer.frame.height)")
        print("[MEASURE] idle fieldHeight=\(field.frame.height)")
        print("[MEASURE] idle headerCapsuleWidth=\(headerCapsule.frame.width)")

        // 聚焦输入框：等键盘焦点确立（软键盘是否升起另打印）
        field.tap()
        let focusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: field
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [focusExpectation], timeout: 10),
            .completed, "输入框未获得键盘焦点"
        )
        let keyboard = app.keyboards.firstMatch
        let keyboardShown = keyboard.waitForExistence(timeout: 5)
        print("[MEASURE] keyboardShown=\(keyboardShown) keyboardHeight=\(keyboardShown ? keyboard.frame.height : -1)")
        settle(1.5)

        print("[MEASURE] keyboard composerHeight=\(composer.frame.height)")
        print("[MEASURE] keyboard fieldHeight=\(field.frame.height)")
        print("[MEASURE] keyboard headerCapsuleWidth=\(headerCapsule.frame.width)")
        XCTAssertLessThanOrEqual(
            composer.frame.height, 58,
            "键盘态发送舱膨胀：高度 \(composer.frame.height)，应为单行规格 54±4"
        )

        // 多行态只打印（形态与封顶高度的诊断量，不在本测试断言）
        field.typeText("第一行先写长一点看看换行与生长是不是正常工作起来\n第二行\n第三行\n第四行\n第五行\n第六行\n第七行")
        settle(1.0)
        print("[MEASURE] multiline composerHeight=\(composer.frame.height)")
        print("[MEASURE] multiline fieldHeight=\(field.frame.height)")
    }
}
