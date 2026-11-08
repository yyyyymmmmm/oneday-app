import XCTest

/// 0.2.6 回归：键盘弹起时发送舱膨胀缺陷（用户真机截图实证，
/// 0.2.5 的 fixedSize 断环只治住静态覆盖态、没治住聚焦态）。
/// 测量法：胶囊高由两个无歧义元素的框几何推导——＋键恒在
/// 胶囊内左下（HStack .bottom 对齐、36pt），输入框上沿距
/// 胶囊上沿恒为 16（胶囊纵向 padding 8＋field 自身
/// padding 8），故胶囊高＝＋键底边 − 输入框上沿 ＋ 24。
/// 断言：键盘态胶囊高 ≤ 58（单行规格 54±4）且输入框单行
/// 高 ≤ 26（一行文本约 22）。诊断截图（kb-*）随附件导出，
/// 只作定位证据、不进 docs/shots 留档。
/// 承载换代后（0.2.6：发送区由覆盖式 ZStack 改列表
/// .safeAreaInset 承载，DESIGN-V4 §10）本测试在新结构上
/// 继续把守同一规格；测量锚点（＋键无障碍标签、field 本体
/// 标识 composerField）与推导式未迁移、未改口径。
/// 另兼缺陷 B 把守：标题胶囊（按钮「切换模型」）宽 ≤ 202。
final class ComposerKeyboardTests: XCTestCase {
    override func setUpWithError() throws {
        // 诊断量要全打印出来再失败，单条断言不中断整场
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

        let field = app.textFields["composerField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "未找到输入框")
        let attach = app.buttons["添加附件"]
        XCTAssertTrue(attach.waitForExistence(timeout: 10), "未找到＋键")
        let headerCapsule = app.buttons["切换模型"]

        func capsuleHeight() -> CGFloat {
            attach.frame.maxY - field.frame.minY + 24
        }
        func report(_ tag: String) {
            print("[MEASURE] \(tag) capsuleDerived=\(capsuleHeight())")
            print("[MEASURE] \(tag) fieldFrame=\(field.frame)")
            print("[MEASURE] \(tag) attachFrame=\(attach.frame)")
            print("[MEASURE] \(tag) headerCapsuleWidth=\(headerCapsule.frame.width)")
        }

        report("idle")
        capture("kb-idle")
        XCTAssertLessThanOrEqual(
            headerCapsule.frame.width, 202,
            "标题胶囊过宽：\(headerCapsule.frame.width)，上限约 200（缺陷 B）"
        )

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

        report("keyboard")
        capture("kb-up")
        XCTAssertLessThanOrEqual(
            capsuleHeight(), 58,
            "键盘态发送舱膨胀：推导高 \(capsuleHeight())，应为单行规格 54±4"
        )
        XCTAssertLessThanOrEqual(
            field.frame.height, 26,
            "键盘态输入框单行高异常：\(field.frame.height)"
        )

        // 滚动态（对照用户截图：列表已上翻、回到底部钮在场）
        let dragStart = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)
        )
        let dragEnd = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)
        )
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        settle(1.0)
        report("keyboardScrolled")
        capture("kb-up-scrolled")
        XCTAssertLessThanOrEqual(
            capsuleHeight(), 58,
            "键盘＋滚动状态发送舱膨胀：推导高 \(capsuleHeight())"
        )

        // 多行态只打印＋留图（形态与封顶高度的诊断量）
        field.typeText("第一行先写长一点看看换行与生长是不是正常工作起来\n第二行\n第三行\n第四行\n第五行\n第六行\n第七行")
        settle(1.0)
        report("multiline")
        capture("kb-multiline")
    }
}
