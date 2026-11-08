import XCTest

/// 回归：发送舱静止态几何（0.2.5 膨胀 → 0.2.6 承载换代 →
/// 0.2.7 高度权威换代，DESIGN-V4 §9/§10/§11）。
///
/// 0.2.7 处置（§11.4）：本文件原有的键盘态断言（点按聚焦 →
/// 键盘升起 → 各态量高）已删除。原因：发送舱文本视图换成
/// UIViewRepresentable 后，XCUI 的合成点按无法可靠驱动其
/// 聚焦；按既定验收分工，键盘态观感由用户真机终审，高
/// 度算术由 OneDayCore 的 ComposerLayoutTests 单测把守
/// （空／单行／多行／上限四态）。焦点响应链另有 App 本体
/// 程序化聚焦自检（ScreenshotTests.test07，0.2.8 §12.2）。
/// 本文件只保留不需要聚焦即可量测的静止态断言：
/// ①胶囊推导高＝＋键底边 − 输入框上沿 ＋ 21（＋键恒在
/// 胶囊内左下；输入框上沿距胶囊上沿＝行边距 8＋文本边
/// 距 5＝13，＋键底边距胶囊下沿 8），须为 0.2.8 单行规
/// 格 46（目标带 45–46，§12.3 改基数）；②防撕裂不变量：
/// ＋键底边 − 输入框底边 ＝文本下边距 5±3（两键 .bottom
/// 锚在 field 底行）；③缺陷 B：标题胶囊（按钮「切换模
/// 型」）宽 ≤ 202。
/// 诊断截图（kb-idle）随附件导出，只作定位证据、不进留档。
final class ComposerKeyboardTests: XCTestCase {
    override func setUpWithError() throws {
        // 诊断量要全打印出来再失败，单条断言不中断整场
        continueAfterFailure = true
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testComposerIdleGeometry() {
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

        // field 是 UITextView（AX 类型 textView）；
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
            attach.frame.maxY - field.frame.minY + 21
        }
        func anchorGap() -> CGFloat {
            attach.frame.maxY - field.frame.maxY
        }
        print("[MEASURE] idle capsuleDerived=\(capsuleHeight())")
        print("[MEASURE] idle fieldFrame=\(field.frame)")
        print("[MEASURE] idle attachFrame=\(attach.frame)")
        print("[MEASURE] idle anchorGap=\(anchorGap())")
        print("[MEASURE] idle headerCapsuleWidth=\(headerCapsule.frame.width)")
        capture("kb-idle")

        XCTAssertTrue(
            (43...49).contains(capsuleHeight()),
            "静止态发送舱高异常：推导高 \(capsuleHeight())，应为单行规格 46（目标带 45–46）"
        )
        XCTAssertTrue(
            (17...24).contains(field.frame.height),
            "静止态输入框单行高异常：\(field.frame.height)（自量高单行约 20，16pt 字体口径）"
        )
        XCTAssertTrue(
            (2...8).contains(anchorGap()),
            "防撕裂不变量破：＋键底边−输入框底边＝\(anchorGap())，应约 5（文本下边距）"
        )
        XCTAssertLessThanOrEqual(
            headerCapsule.frame.width, 202,
            "标题胶囊过宽：\(headerCapsule.frame.width)，上限约 200（缺陷 B）"
        )
    }

    // MARK: - 0.2.9 多行闭环量测（DESIGN-V4 §13）

    /// 以 `-odDemoComposerText <case>` 启动演示（可选叠加
    /// `-odDemoFocusComposer` 抬键盘），等注入文本落到字段
    /// 后返回 (app, field, attach)。聚焦走 App 本体程序化通
    /// 道，不用 XCUI 合成点按（§11.4 工具侧限制）。
    private func launchInjected(
        case caseName: String, focus: Bool
    ) -> (XCUIApplication, XCUIElement, XCUIElement) {
        let app = XCUIApplication()
        var args = [
            "-AppleInterfaceStyle", "Light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            "-odDemoMode", "-odDemoComposerText", caseName,
        ]
        if focus { args.append("-odDemoFocusComposer") }
        app.launchArguments = args
        app.launch()

        let byView = app.textViews["composerField"]
        let field = byView.waitForExistence(timeout: 20)
            ? byView
            : app.textFields["composerField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "未找到输入框")
        let attach = app.buttons["添加附件"]
        XCTAssertTrue(attach.waitForExistence(timeout: 10), "未找到＋键")
        // 等注入文本落到字段：同步轮询 value（expectation /
        // waitForExpectations 在 Swift 6 下有并发隔离编译坑，
        // 本仓 UI 测试一律同步等待，此处从例）
        let deadline = Date().addingTimeInterval(20)
        var injectedText = (field.value as? String) ?? ""
        while !injectedText.contains("量测"), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
            injectedText = (field.value as? String) ?? ""
        }
        XCTAssertTrue(
            injectedText.contains("量测"),
            "注入文本未落到发送舱：\(injectedText)"
        )
        if focus {
            XCTAssertTrue(
                app.keyboards.firstMatch.waitForExistence(timeout: 15),
                "程序化聚焦后键盘应升起"
            )
        }
        // 等高度落稳（量高回写经主线程异步调度）
        Thread.sleep(forTimeInterval: 0.8)
        return (app, field, attach)
    }

    private func capsuleDerived(
        field: XCUIElement, attach: XCUIElement
    ) -> CGFloat {
        attach.frame.maxY - field.frame.minY + 21
    }

    /// 2 行：文本高 40、胶囊 = max(40+10, 30)+16 = 66。
    func testComposerTwoLinesGeometry() {
        let (app, field, attach) = launchInjected(case: "two", focus: false)
        _ = app
        let capsule = capsuleDerived(field: field, attach: attach)
        print("[MEASURE] two fieldH=\(field.frame.height) capsule=\(capsule)")
        print("[MEASURE] two fieldFrame=\(field.frame)")
        capture("kb-lines-2")
        XCTAssertEqual(field.frame.height, 40, accuracy: 4, "两行文本高应 ≈40：\(field.frame.height)")
        XCTAssertEqual(capsule, 66, accuracy: 3, "两行胶囊高应 ≈66：\(capsule)")
    }

    /// 4 行：文本高 80、胶囊 = max(80+10, 30)+16 = 106。
    func testComposerFourLinesGeometry() {
        let (app, field, attach) = launchInjected(case: "four", focus: false)
        _ = app
        let capsule = capsuleDerived(field: field, attach: attach)
        print("[MEASURE] four fieldH=\(field.frame.height) capsule=\(capsule)")
        print("[MEASURE] four fieldFrame=\(field.frame)")
        capture("kb-lines-4")
        XCTAssertEqual(field.frame.height, 80, accuracy: 4, "四行文本高应 ≈80：\(field.frame.height)")
        XCTAssertEqual(capsule, 106, accuracy: 3, "四行胶囊高应 ≈106：\(capsule)")
    }

    /// 缠绕 3 行：37 字单行长句在字段宽下应恰缠 3 行——
    /// 文本高须为整行倍数（60±5、无幽灵行），胶囊严格跟
    /// 随 fieldH+26（文本边距 10＋行边距 16）。
    func testComposerWrapLinesGeometry() {
        let (app, field, attach) = launchInjected(case: "wrap", focus: false)
        _ = app
        let capsule = capsuleDerived(field: field, attach: attach)
        print("[MEASURE] wrap fieldH=\(field.frame.height) capsule=\(capsule)")
        print("[MEASURE] wrap fieldFrame=\(field.frame)")
        capture("kb-lines-wrap")
        XCTAssertEqual(field.frame.height, 60, accuracy: 5, "缠绕应恰 3 行（文本高 ≈60）：\(field.frame.height)")
        XCTAssertEqual(capsule, field.frame.height + 26, accuracy: 3, "胶囊应严格跟随文本高 +26：胶囊 \(capsule) vs 文本 \(field.frame.height)")
    }

    /// 键盘态 2 行：与 testComposerTwoLinesGeometry 同期望
    /// ——键盘升起不得改变胶囊几何（设备撕开场景的最接近
    /// 复现：键盘＋已有文本）。
    func testComposerKeyboardTwoLinesGeometry() {
        let (app, field, attach) = launchInjected(case: "two", focus: true)
        _ = app
        let capsule = capsuleDerived(field: field, attach: attach)
        print("[MEASURE] kb-two fieldH=\(field.frame.height) capsule=\(capsule)")
        print("[MEASURE] kb-two fieldFrame=\(field.frame)")
        capture("kb-lines-2-kb")
        XCTAssertEqual(field.frame.height, 40, accuracy: 4, "键盘态两行文本高应 ≈40：\(field.frame.height)")
        XCTAssertEqual(capsule, 66, accuracy: 3, "键盘态两行胶囊高应 ≈66：\(capsule)")
    }
}
