import XCTest

/// A6 回归：英文语言下抽屉齿轮点按后设置 sheet 应呈现。
///
/// 事由：冒烟门第四轮 run 43634025826，A6（testSmokeA6EnglishFirstFrame）红——
/// 英文语言档（`-appLanguage en`）下齿轮点按成功、无报错，但设置 sheet 20 秒＋15 秒
/// 轮询均未呈现，齿轮随后不可命中；同 helper 中文态同轮 3 例均 1 秒内打开。
/// 本组把 A6 的最小复现收成常驻回归：英文例＋中文对照例各一。
/// 修复前英文例应红、中文例应绿；修复后两例皆绿。
///
/// 判定只认关闭钮「关闭设置」在场（SettingsView 恒传 onClose、关闭钮硬编码此标签，
/// sheet 若呈现必在场；反之 sheet 未呈现）。
///
/// 探针说明：App 进程的 print 探针不进 xcodebuild 日志（第二轮中文例已呈现
/// sheet、四行探针仍为零，已证实通道不通，App 侧探针已删），定因改走测试侧
/// 状态快照——抽屉开后（基线）／点按后 3 秒／呈现后各取一次，测试进程 print
/// 出来（测试进程输出进日志），失败时另写进断言信息（断言信息必进日志）。
/// 快照判读（须中英两例同刻对照）：
/// - 齿轮仍在且可命中、抽屉仍开、sheet 0 ＝ 点按未生效或消费未跑（动作/onChange 段）
/// - 齿轮/频道行消失、sheet 0 ＝ 抽屉被收回或根重建吞掉请求（重建/收回段）
/// - sheet 1 但关闭钮缺席 ＝ 呈现了但内容未进无障碍树（内容段）
/// - 关闭钮曾出现后消失 ＝ 呈现后即被关（dismiss 段）
/// - 齿轮在树但不可命中、底栏不在树、sheet 0（第三轮英文快照实测）＝ 抽屉仍开、
///   但有物盖住齿轮且底栏离树——须看中文同刻是否同形，同形即常态、异形即病灶。
final class SettingsSheetLocaleTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 英文例：复现 A6——英文档下点齿轮，设置 sheet 应升起。
    func testSettingsSheetPresentsInEnglishLocale() {
        let app = launchDemo(["-appLanguage", "en"])
        openSettingsViaDrawerGear(app)
    }

    /// 中文对照例：同一路径中文态应打开（A6 对照组同轮实证：约 1 秒即见关闭钮）。
    func testSettingsSheetPresentsInChineseLocale() {
        let app = launchDemo(["-AppleLanguages", "(zh-Hans)"])
        openSettingsViaDrawerGear(app)
    }

    // MARK: - helper（与冒烟门 openSettings 同形：先证抽屉真开再点齿轮）

    private func launchDemo(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"] + extra
        app.launch()
        XCTAssertTrue(
            app.tabBars.buttons["聊天"].waitForExistence(timeout: 25),
            "底栏应在场（标题硬编码中文，不本地化）"
        )
        return app
    }

    /// 经抽屉底条齿轮进设置；关闭钮 20 秒内应在场，验后点关闭钮收尾。
    /// 失败时断言信息带点按后快照与失败时快照，定位丢失段。
    private func openSettingsViaDrawerGear(
        _ app: XCUIApplication, line: UInt = #line
    ) {
        let opener = app.buttons["drawer.open"]
        XCTAssertTrue(
            opener.waitForExistence(timeout: 25),
            "抽屉开启钮应在场", line: line
        )
        opener.tap()
        let channelRow = app.buttons["drawer.row.channel.hermes"]
        XCTAssertTrue(
            channelRow.waitForExistence(timeout: 15),
            "抽屉应打开（频道行在场）", line: line
        )
        let gear = app.buttons["设置"]
        XCTAssertTrue(
            gear.waitForExistence(timeout: 10),
            "抽屉底条设置钮应在场", line: line
        )
        let gearDeadline = Date().addingTimeInterval(10)
        while !gear.isHittable && Date() < gearDeadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(gear.isHittable, "抽屉齿轮应可命中", line: line)
        // 探针 v3（测试侧）：点按前取基线快照（抽屉开、齿轮可命中时的常态）。
        print("[A6STATE] baseline " + snapshot(app, gear: gear, channelRow: channelRow))
        gear.tap()

        // 探针 v2（测试侧）：点按后 3 秒取快照，兼捕关闭钮是否曾短暂出现。
        Thread.sleep(forTimeInterval: 3)
        let snapAfterTap = snapshot(app, gear: gear, channelRow: channelRow)
        print("[A6STATE] afterTap " + snapAfterTap)
        var closeSeenTransiently = false
        for _ in 0..<10 {
            if app.buttons["关闭设置"].exists {
                closeSeenTransiently = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        let closeButton = app.buttons["关闭设置"]
        let opened = closeButton.waitForExistence(timeout: 20)
        if !opened {
            let snapAtFailure = snapshot(app, gear: gear, channelRow: channelRow)
            XCTFail(
                "设置页应打开（关闭钮在场）。点按后快照：\(snapAfterTap)；"
                    + "关闭钮曾现：\(closeSeenTransiently)；失败时快照：\(snapAtFailure)",
                line: line
            )
            return
        }
        // 探针 v3：呈现后取快照（中文对照例的同刻常态，与英文失败快照对照）。
        print("[A6STATE] presented " + snapshot(app, gear: gear, channelRow: channelRow))
        closeButton.tap()
    }

    /// 点按后状态快照：齿轮/频道行是否还在树里、是否可命中、sheet 数、窗口数、
    /// 底栏是否还在（根是否仍为 ContentView）、按钮/文本总数（盖层呈现会改数）。
    private func snapshot(
        _ app: XCUIApplication,
        gear: XCUIElement,
        channelRow: XCUIElement
    ) -> String {
        "gear.exists=\(gear.exists) gear.hittable=\(gear.isHittable)"
            + " channelRow.exists=\(channelRow.exists)"
            + " sheets=\(app.sheets.count) windows=\(app.windows.count)"
            + " tabChat.exists=\(app.tabBars.buttons["聊天"].exists)"
            + " buttons=\(app.buttons.count) texts=\(app.staticTexts.count)"
    }
}
