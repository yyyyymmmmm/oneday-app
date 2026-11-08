import XCTest

/// 回归：键盘态发送舱高度（0.2.5 膨胀 → 0.2.6 承载换代 →
/// 0.2.7 高度权威换代，DESIGN-V4 §9/§10/§11）。
/// 0.2.7 起发送舱文本视图是自量高 UITextView
/// （ComposerTextView），其无障碍框＝视图真框。断言三组：
/// ①胶囊推导高：＋键底边 − 输入框上沿 ＋ 24（＋键恒在胶囊
/// 内左下、输入框上沿距胶囊上沿恒 16）——键盘各态须为单行
/// 规格 54±4；②防撕裂不变量：＋键底边 − 输入框底边 ＝ 8±3
/// （两键 .bottom 锚在 field 底行）——真机撕裂空盒的签名
/// 正是此差值爆炸（文字掉底、中间撕空），高度由文本布局
/// 单方决定后此式恒成立；③多行封顶：7 行输入后 field 高
/// ≈6 行封顶（约 135），胶囊随之约 167，且不变量仍成立。
/// 另兼缺陷 B 把守：标题胶囊（按钮「切换模型」）宽 ≤ 202。
/// 诊断截图（kb-*）随附件导出，只作定位证据、不进留档。
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

        // 0.2.7：field 是 UITextView（AX 类型 textView）；
        // 兜底 textFields 以防系统映射口径变化
        let byView = app.textViews["composerField"]
        let field = byView.waitForExistence(timeout: 15)
            ? byView
            : app.textFields["composerField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "未找到输入框")
        let attach = app.buttons["添加附件"]
        XCTAssertTrue(attach.waitForExistence(timeout: 10), "未找到＋键")
        let headerCapsule = app.buttons["切换模型"]

        func capsuleHeight() -> CGFloat {
            attach.frame.maxY - field.frame.minY + 24
        }
        func anchorGap() -> CGFloat {
            attach.frame.maxY - field.frame.maxY
        }
        func report(_ tag: String) {
            print("[MEASURE] \(tag) capsuleDerived=\(capsuleHeight())")
            print("[MEASURE] \(tag) fieldFrame=\(field.frame)")
            print("[MEASURE] \(tag) attachFrame=\(attach.frame)")
            print("[MEASURE] \(tag) anchorGap=\(anchorGap())")
            print("[MEASURE] \(tag) headerCapsuleWidth=\(headerCapsule.frame.width)")
        }
        func assertSingleLine(_ tag: String) {
            XCTAssertLessThanOrEqual(
                capsuleHeight(), 58,
                "\(tag) 发送舱膨胀：推导高 \(capsuleHeight())，应为单行规格 54±4"
            )
            XCTAssertTrue(
                (18...30).contains(field.frame.height),
                "\(tag) 输入框单行高异常：\(field.frame.height)（自量高单行约 22）"
            )
            XCTAssertTrue(
                (5...11).contains(anchorGap()),
                "\(tag) 防撕裂不变量破：＋键底边−输入框底边＝\(anchorGap())，应约 8"
            )
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
        assertSingleLine("键盘态")

        // 【临时诊断】＋键（同行 SwiftUI Menu 按钮）命中探活：
        // 菜单能开＝行区域命中活、问题只在 representable；
        // 菜单不能开＝整行命中被上层吞
        attach.tap()
        settle(1.0)
        let menuItem = app.buttons["相册选图"]
        print("[MEASURE] attachMenuOpened=\(menuItem.exists)")
        capture("kb-attach")
        if menuItem.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            settle(0.5)
        }

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
        assertSingleLine("键盘＋滚动态")

        // 多行封顶：输入 7 行，field 应封顶在 6 行量级、
        // 胶囊＝field＋32（两层纵向边距），锚定不变量不破
        field.typeText("第一行先写长一点看看换行与生长是不是正常工作起来\n第二行\n第三行\n第四行\n第五行\n第六行\n第七行")
        settle(1.0)
        report("multiline")
        capture("kb-multiline")
        XCTAssertTrue(
            (120...150).contains(field.frame.height),
            "多行封顶异常：field 高 \(field.frame.height)，应为 6 行量级约 135"
        )
        XCTAssertTrue(
            (5...11).contains(anchorGap()),
            "多行态防撕裂不变量破：\(anchorGap())，应约 8"
        )
    }
}
