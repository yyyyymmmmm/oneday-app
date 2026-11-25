import UIKit
import XCTest

/// §265（换代包 5）手势仲裁系统级验收：打
/// -odDemoMode 真 App 生产装配，XCUITest 投递
/// 真手势，验 C4 两路与 T4 两条件：
/// 1. 长按正文文本→系统编辑菜单（选字），整行
///    菜单不出现（S3：菜单已下移非文本层）；
/// 2. 长按气泡内边距带（非文本层）→整行菜单出
///    现（按 SF Symbol 标识查、与语言无关——
///    DrawerRowContextMenuTests 先例）；第十轮改
///    四点取证梯（左带/上带/左带长压/右带逐点记
///    结果），九轮左带单点长按命中层不响应；
/// 3. 双击正文→选词＋编辑菜单，整行菜单不出现
///    （右滑 pan 的失败依赖＝点按先行的可见证）；
/// 4. 右滑一行→引用横幅出现（「取消引用」钮，
///    字面量 accessibilityLabel、与语言无关）；
///    第十轮改慢速拖＋终点保持、边距带起拖优先；
/// 5. 电话命中段（T4）：第十轮定性——长按号码
///    正中仍只出编辑菜单＝可选文本视图里长按由
///    文本选择接管、检测链接主动作是点按（平台
///    行为）；证明改两阶段：长按出 Call 项链接
///    菜单（探针 §5.2 形态）或点按出系统链接动
///    作，任一达即算主动作已证。
/// 【整册退役 · §353（2026-11-22）】本册使命结束、
/// 默认 skip：其启动参数钉 `-chat.list.native NO`
/// 非默认回退面——生产默认原生面自 §297 起、本册
/// 量的签名已无被测对象，「浸泡期保签名」使命随旧
/// 面退出默认面终结；且本册 finder/settle 机器在
/// 旧面 AX 树上结构性超时（2026-11-22 收口调查实
/// 跑 5 件全红、4 件约 222 秒死于 UI 查询求值超
/// 时、手势根本没投递；2026-11-15 同型案底两轮修
/// 法未达绿）。同题同判据已由原生面册
/// ChatGestureNativeSurfaceTests 在出货面覆盖
/// （双击选字/边距带长按/右滑引用 UI 实证绿），
/// 覆盖不丢。定性与收口路径见 oneday-design-
/// review/gesture-suite-rootcause-20261122.md。
/// 退役方式＝setUpWithError 无条件 XCTSkip（仓
/// 内 PresentationLayerScenarios 占位 skip 惯
/// 例）；文件保留备查、不删。
final class ChatGestureArbitrationTests: XCTestCase {

    /// 整行菜单首项（回复）的 SF Symbol 标识
    private let rowMenuReplySymbol =
        "arrowshape.turn.up.left"

    override func setUpWithError() throws {
        continueAfterFailure = false
        // §353 整册退役（见文件头）：默认 skip、
        // 不投递任何手势
        throw XCTSkip(
            "§353 退役：本册钉非默认回退面、签名已无被测对象；"
                + "同题覆盖在原生面册"
                + "（ChatGestureNativeSurfaceTests）"
        )
    }

    // MARK: - 用例

    func testLongPressOnTextShowsEditMenuNotRowMenu() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        let text = try lastUserTextView(in: app)
        text.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).press(forDuration: 1.2)
        assertEditMenuShown(in: app)
        assertRowMenuAbsent(in: app)
    }

    func testLongPressOnBubblePaddingShowsRowMenu() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        // 取证梯（第十轮）：九轮实证左带中点 1.5 秒长
        // 按后什么菜单都没出（按钮树无 Copy、无整行
        // 菜单项）——那个点命中的层不响应。本轮四点
        // 逐个试、逐个记结果（TEST-PADDING 行：row-
        // Menu／editMenu／none），任一出整行菜单即
        // 收；点位全走元素坐标系（八轮实证）
        let attempts: [(
            name: String, base: CGVector,
            offset: CGVector, duration: TimeInterval
        )] = [
            // 左带中点（九轮基线点）
            ("左带", CGVector(dx: 0, dy: 0.5),
             CGVector(dx: -8, dy: 0), 1.5),
            // 上带中点（文本顶缘外 6pt、V 带 13 内）
            ("上带", CGVector(dx: 0.5, dy: 0),
             CGVector(dx: 0, dy: -6), 1.5),
            // 左带中点·加长按压（排除识别时长不足）
            ("左带长压", CGVector(dx: 0, dy: 0.5),
             CGVector(dx: -8, dy: 0), 2.5),
            // 右带中点
            ("右带", CGVector(dx: 1, dy: 0.5),
             CGVector(dx: 8, dy: 0), 1.5),
        ]
        var evidence: [String] = []
        for attempt in attempts {
            let text = try lastUserTextView(in: app)
            let point = text.coordinate(
                withNormalizedOffset: attempt.base
            ).withOffset(attempt.offset)
            point.press(forDuration: attempt.duration)
            if pollRowMenu(in: app, timeout: 5) {
                print(
                    "TEST-PADDING point=\(attempt.name)"
                        + " result=rowMenu"
                )
                // hittable 复核双口径同 pollRowMenu
                // 注（台账 193）：命中哪口径复核哪口径
                let bySymbol = app.buttons.matching(
                    NSPredicate(
                        format: "identifier == %@",
                        rowMenuReplySymbol
                    )
                ).firstMatch
                let byLabel = app.buttons.matching(
                    NSPredicate(
                        format: "label == %@", "回复"
                    )
                ).firstMatch
                let item = bySymbol.exists
                    ? bySymbol : byLabel
                XCTAssertTrue(item.isHittable)
                return
            }
            let result = editMenuVisible(in: app)
                ? "editMenu" : "none"
            print(
                "TEST-PADDING point=\(attempt.name)"
                    + " result=\(result)"
            )
            evidence.append("\(attempt.name)=\(result)")
            dismissMenus(in: app)
        }
        XCTFail(
            "气泡边距带四点均未出整行菜单；逐点结果："
                + evidence.joined(separator: ", ")
                + "；当时按钮树：" + treeSnapshot(in: app)
        )
    }

    /// 正文双击由 UITextView 原生处理为选词与编辑菜单，
    /// 整行菜单只由非文本气泡区域触发。
    func testDoubleTapOnTextSelectsWordNotRowMenu() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        let text = try lastUserTextView(in: app)
        text.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).doubleTap()
        assertEditMenuShown(in: app)
        assertRowMenuAbsent(in: app)
    }

    func testSwipeRightOnRowTriggersReplyQuote() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        // 第十轮改法（九轮卡点①定案后）：合成拖动改
        // 慢速拖（XCUIGestureVelocity.slow、Keyboar-
        // dDragDismissTests 同式）＋终点保持 1 秒，让
        // 桥的方向门在低速下完成起滑判定、途中触发
        // （过 60）在松手前发生。两尝试：先边距带起
        // 拖（避开文本区、免触摸先被文本自家识别器
        // 跟踪）、不成再文本左缘内起拖（九轮点位）
        let starts: [(name: String, offsetX: CGFloat)] = [
            ("边距带起拖", -8),
            ("文本区起拖", 12),
        ]
        for start in starts {
            let text = try lastUserTextView(in: app)
            let begin = text.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0.5)
            ).withOffset(CGVector(dx: start.offsetX, dy: 0))
            let end = begin.withOffset(
                CGVector(dx: 170, dy: 0)
            )
            begin.press(
                forDuration: 0.1, thenDragTo: end,
                withVelocity: .slow,
                thenHoldForDuration: 1.0
            )
            let cancel = app.buttons["取消引用"]
            let found = cancel.waitForExistence(timeout: 6)
            print(
                "TEST-SWIPE attempt=\(start.name)"
                    + " banner=\(found)"
            )
            if found { return }
        }
        XCTFail(
            "两轮慢速右滑均未触发引用横幅；当时按钮树："
                + treeSnapshot(in: app)
        )
    }

    func testLongPressOnPhoneShowsLinkMenuNotRowMenu() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        // 阶段一（第十轮）：长按号码正中——点位由
        // phoneNumberCoordinate 按实帧＋字宽测算钉死
        // （九轮 (0.32, 0.30) 是对着退化帧盲打、本轮
        // 先取证再定点）
        let point = try phoneNumberCoordinate(in: app)
        point.press(forDuration: 1.5)
        if waitForCallItem(in: app, timeout: 6) {
            print("TEST-PHONE proof=longpress-linkmenu")
            assertRowMenuAbsent(in: app)
            return
        }
        print(
            "TEST-PHONE 长按号码正中未出链接菜单；"
                + "当时菜单项="
                + menuLabels(in: app).joined(separator: "/")
                + "；按钮树：" + treeSnapshot(in: app)
        )
        // 定性（第十轮·主线裁示）：点位已钉在号码正
        // 中、长按仍只出编辑菜单——可选文本视图里长
        // 按由文本选择接管、检测链接的主动作是点
        // 按，平台即如此（非产品反例）。T4 的 UI 证
        // 明自此改走点按：清掉选区后点按号码正中，
        // 系统链接动作（动作单/告警/Call 项/号码钮
        // 任一形态）出现即算主动作已达
        dismissMenus(in: app)
        clearSelectionByTappingPlainText(in: app)
        for tapIndex in 0..<2 {
            let tapPoint = try phoneNumberCoordinate(
                in: app
            )
            tapPoint.tap()
            if waitForLinkAction(in: app, timeout: 5) {
                print(
                    "TEST-PHONE proof=tap-linkaction"
                        + " tapIndex=\(tapIndex)"
                )
                return
            }
        }
        XCTFail(
            "长按（只出编辑菜单）与点按均未见链接动作；"
                + "点按后按钮树：" + treeSnapshot(in: app)
        )
    }

    // MARK: - 装配与查找

    private func launchDemoApp() -> XCUIApplication {
        let app = XCUIApplication()
        // §297（原生重建 R4 转默认）：本套件是旧面手势
        // 仲裁基线，浸泡期显式钉回旧面保签名；原生面
        // 同题同判据在 ChatGestureNativeSurfaceTests
        app.launchArguments = [
            "-odDemoMode", "-chat.list.native", "NO",
        ]
        app.launch()
        return app
    }

    /// 打开演示种子会话（§265 五轮树转储定案）：
    /// 演示启动落在主线（审批卡＋空状态建议），种
    /// 子会话「帮我看看服务器状态」在抽屉本地行里
    /// ——先开抽屉、按行标题点开它，消息才上屏。
    /// 抽屉行口径与 DrawerRowContextMenuTests 同源
    private func openSeededThread(in app: XCUIApplication) {
        let openButton = app.buttons["drawer.open"]
        XCTAssertTrue(
            openButton.waitForExistence(timeout: 15),
            "抽屉入口未出现"
        )
        if openButton.isHittable {
            openButton.tap()
        }
        let rows = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "drawer.row.side.local."
            )
        )
        var target: XCUIElement?
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, target == nil {
            for row in rows.allElementsBoundByIndex
            where row.label.contains("服务器状态") {
                target = row
                break
            }
            if target == nil {
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
        guard let target else {
            XCTFail("抽屉里找不到演示种子会话行")
            return
        }
        // 2026-11-21 深夜定性（导航追踪探针实证）：种子行在未
        // 滚动的抽屉名单里位于最底部（frame y≈847、中心距屏
        // 底约 5pt），isHittable 虽判 true，XCUI 在该点的 tap
        // 落进底边死区、按钮根本不触发，旧版直点＋丢弃等待结
        // 果一路假绿到找字超时。先把行滚到可视区中部再点，
        // 点后断言胶囊在位才许往下走。
        let rowID = target.identifier
        var row = app.buttons[rowID]
        var scrolls = 0
        while row.exists, row.frame.minY > 620, scrolls < 10 {
            if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else {
                app.swipeUp()
            }
            scrolls += 1
            Thread.sleep(forTimeInterval: 0.4)
            row = app.buttons[rowID]
        }
        row.tap()
        XCTAssertTrue(
            app.buttons["topbar.identityCapsule"]
                .waitForExistence(timeout: 15),
            "点种子行后顶栏胶囊未出现——抽屉导航没落定"
        )
        // 跳到底部：列表初始停在顶部、LazyVStack 只
        // 物化首屏行，末尾消息不在树里——走生产「回
        // 到底部」钮（不在底部时才出现），无钮时以
        // 列表上滑兜底；落底后末条消息物化且在屏内
        let toBottom = app.buttons["chevron.down"]
        if toBottom.waitForExistence(timeout: 3),
           toBottom.isHittable {
            toBottom.tap()
        } else {
            let list = app.scrollViews.firstMatch
            for _ in 0..<6 {
                list.swipeUp()
            }
        }
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// 末条用户消息的正文文本视图（演示种子末条
    /// 用户消息「好，就按你说的顺序来。」）
    private func lastUserTextView(
        in app: XCUIApplication
    ) throws -> XCUIElement {
        try textView(matching: "按你说的顺序来", in: app)
    }

    /// §265 演示种子 T4 样本消息的文本视图（值班
    /// 电话/状态页/邮箱一条）
    private func contactTextView(
        in app: XCUIApplication
    ) throws -> XCUIElement {
        try textView(matching: "值班电话", in: app)
    }

    /// 按正文找承载文本视图：a11y value 经 TextSh-
    /// aping 整形、字间插有 U+2060（冒烟门同族实
    /// 证），谓词 CONTAINS 原文必落空——改逐元素
    /// 读 value、剥整形字符后比对；首轮找不到时
    /// 上滑列表促 LazyVStack 物化后重找（两轮）。
    /// 终失败把全树文本视图的 value 摘要写进断言
    /// 信息、自带取证
    private func textView(
        matching needle: String, in app: XCUIApplication
    ) throws -> XCUIElement {
        // 先等聊天页装配到位（顶栏胶囊在位＝页面已
        // 组装）：本类按字母序在全轮 UI 测试里最先
        // 跑、吃冷启动，未等页面起来时全树无文本视
        // 图、轮询多久都是零（KeyboardDragDismiss-
        // Tests 同口径先等胶囊 30 秒）
        XCTAssertTrue(
            app.buttons["topbar.identityCapsule"]
                .waitForExistence(timeout: 30),
            "聊天页未组装：顶栏胶囊 30 秒未出现"
        )
        for round in 0..<2 {
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                for element in candidateElements(in: app) {
                    let raw = (element.value as? String)
                        ?? element.label
                    guard !raw.isEmpty else { continue }
                    let stripped = raw
                        .replacingOccurrences(
                            of: "\u{2060}", with: ""
                        )
                        .replacingOccurrences(
                            of: "\u{200B}", with: ""
                        )
                        .replacingOccurrences(
                            of: "\u{FEFF}", with: ""
                        )
                    if stripped.contains(needle) {
                        print(
                            "TEST-FINDER matched needle="
                                + needle
                                + " type=\(element.elementType.rawValue)"
                                + " frame=\(element.frame)"
                        )
                        reveal(element, in: app)
                        return element
                    }
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
            if round == 0 { app.swipeUp() }
        }
        XCTFail(
            "按正文找不到承载文本视图「\(needle)」；"
                + "当时文本视图 value 摘要："
                + valueDigest(in: app)
        )
        throw NSError(domain: "ChatGestureArbitration", code: 1)
    }

    /// 候选元素池（§265 四轮判读后扩面）：消息正文
    /// 在演示聊天页的无障碍树里不是 TextView 形态
    /// 出现（四轮快照恒只有输入舱一枚 TextView）——
    /// 正文可能以 StaticText／合并元素形态在树，
    /// 三类一并扫、命中打 TEST-FINDER 行留痕
    private func candidateElements(
        in app: XCUIApplication
    ) -> [XCUIElement] {
        app.textViews.allElementsBoundByIndex
            + app.staticTexts.allElementsBoundByIndex
    }

    private func valueDigest(in app: XCUIApplication) -> String {
        candidateElements(in: app).map {
            let raw = ($0.value as? String) ?? $0.label
            let stripped = raw.replacingOccurrences(
                of: "\u{2060}", with: ""
            )
            return "t\($0.elementType.rawValue):"
                + String(stripped.prefix(30))
        }.joined(separator: " | ")
    }

    /// 双向 reveal：元素在视口上方（含帧退化——回
    /// 底后较旧消息在视口上方、帧为 inf）下滑找，
    /// 在下方上滑找（八轮实证：联系方式消息回底后
    /// 帧退化、单向上滑永不命中）
    private func reveal(
        _ element: XCUIElement, in app: XCUIApplication
    ) {
        let list = app.scrollViews.firstMatch
        var attempts = 0
        while !element.isHittable, attempts < 14 {
            let frame = element.frame
            if frame.isEmpty || !frame.minY.isFinite
                || frame.minY < 130 {
                list.swipeDown()
            } else {
                list.swipeUp()
            }
            attempts += 1
        }
        XCTAssertTrue(
            element.isHittable,
            "目标文本滚动后仍不可命中"
        )
    }

    // MARK: - 断言助手

    /// 编辑菜单出现的判据：menuItems 或按钮里出
    /// 现 Copy/拷贝（两档语言都认）
    private func assertEditMenuShown(in app: XCUIApplication) {
        let copyItem = app.menuItems.matching(
            NSPredicate(
                format: "label IN %@", ["Copy", "拷贝"]
            )
        ).firstMatch
        let copyButton = app.buttons.matching(
            NSPredicate(
                format: "label IN %@", ["Copy", "拷贝"]
            )
        ).firstMatch
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              !copyItem.exists, !copyButton.exists {
            Thread.sleep(forTimeInterval: 0.3)
        }
        if !copyItem.exists, !copyButton.exists {
            XCTFail(
                "文本手势后系统编辑菜单未出现；当时按钮树："
                    + treeSnapshot(in: app)
            )
        }
    }

    /// 整行菜单不出现的判据：回复项不存在——双
    /// 口径（台账 193 判读对齐）：台账 187 起整行
    /// 菜单换自绘动作面（项以标题「回复」在树），
    /// SF Symbol 标识是已退役的系统 contextMenu
    /// 形态口径；两口径任一在场即算菜单在场（与
    /// 原生面套件 pollRowMenu 的双查同式）
    private func assertRowMenuAbsent(in app: XCUIApplication) {
        let bySymbol = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@",
                rowMenuReplySymbol
            )
        ).firstMatch
        let byLabel = app.buttons.matching(
            NSPredicate(format: "label == %@", "回复")
        ).firstMatch
        XCTAssertFalse(
            bySymbol.exists || byLabel.exists,
            "文本区手势不许出整行菜单（S3 仲裁）"
        )
    }

    /// 整行菜单出现的轮询判据（边距带取证梯用；
    /// 双口径同 assertRowMenuAbsent 注）
    private func pollRowMenu(
        in app: XCUIApplication, timeout: TimeInterval
    ) -> Bool {
        let bySymbol = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@",
                rowMenuReplySymbol
            )
        ).firstMatch
        let byLabel = app.buttons.matching(
            NSPredicate(format: "label == %@", "回复")
        ).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if bySymbol.exists || byLabel.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return bySymbol.exists || byLabel.exists
    }

    /// 编辑菜单在场的判据（Copy 项，menuItems 与
    /// 按钮两形态都认——九轮实证编辑菜单项以按钮
    /// 形态出现在树里）
    private func editMenuVisible(
        in app: XCUIApplication
    ) -> Bool {
        app.menuItems.matching(
            NSPredicate(
                format: "label IN %@", ["Copy", "拷贝"]
            )
        ).firstMatch.exists
            || app.buttons.matching(
                NSPredicate(
                    format: "label IN %@", ["Copy", "拷贝"]
                )
            ).firstMatch.exists
    }

    /// 当前 menuItems 的标签清单（失败取证用）
    private func menuLabels(
        in app: XCUIApplication
    ) -> [String] {
        app.menuItems.allElementsBoundByIndex
            .map { $0.label }.filter { !$0.isEmpty }
    }

    /// 菜单在场时 dismiss（台账 193 判读对齐）：
    /// 自绘动作面（sheet）以 app 级下滑收（下滑起
    /// 点在屏中、落在 sheet 面内——旧法对列表滚
    /// 动视图下滑够不到模态 sheet，面不散则下一
    /// 点位的元素被模态挡住、reveal 恒死，0.50.
    /// 77 两轮失败签名实证）；编辑菜单仍以列表小
    /// 滚散。两者都不在场时不动列表，免扰动后续
    /// 尝试的点位
    private func dismissMenus(in app: XCUIApplication) {
        let sheetItem = app.buttons.matching(
            NSPredicate(format: "label == %@", "回复")
        ).firstMatch
        if sheetItem.exists {
            app.swipeDown()
            let deadline = Date()
                .addingTimeInterval(4)
            while sheetItem.exists,
                  Date() < deadline {
                Thread.sleep(forTimeInterval: 0.3)
            }
            Thread.sleep(forTimeInterval: 0.5)
            return
        }
        let rowItem = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@",
                rowMenuReplySymbol
            )
        ).firstMatch
        if rowItem.exists || editMenuVisible(in: app) {
            app.scrollViews.firstMatch.swipeDown()
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    /// 系统链接菜单的判别项＝Call（编辑菜单无此
    /// 项；中英两档标签、menuItems 与按钮两形态都
    /// 认）
    private func waitForCallItem(
        in app: XCUIApplication, timeout: TimeInterval
    ) -> Bool {
        let item = app.menuItems.matching(
            NSPredicate(
                format: "label IN %@", ["Call", "呼叫"]
            )
        ).firstMatch
        let button = app.buttons.matching(
            NSPredicate(
                format: "label IN %@", ["Call", "呼叫"]
            )
        ).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if item.exists || button.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return item.exists || button.exists
    }

    /// 点按检测链接后的系统链接动作判据（第十轮改
    /// 证路）：动作单／告警／Call 项／以号码为标签
    /// 的钮，任一形态出现即算主动作已达；命中的形
    /// 态打 TEST-PHONE 行留痕
    private func waitForLinkAction(
        in app: XCUIApplication, timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if app.sheets.firstMatch.exists {
                print("TEST-PHONE linkAction=sheet")
                return true
            }
            if app.alerts.firstMatch.exists {
                print("TEST-PHONE linkAction=alert")
                return true
            }
            if app.buttons.matching(
                NSPredicate(
                    format: "label IN %@",
                    ["Call", "呼叫"]
                )
            ).firstMatch.exists
                || app.menuItems.matching(
                    NSPredicate(
                        format: "label IN %@",
                        ["Call", "呼叫"]
                    )
                ).firstMatch.exists {
                print("TEST-PHONE linkAction=callItem")
                return true
            }
            if app.buttons.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "13800138000"
                )
            ).firstMatch.exists {
                print("TEST-PHONE linkAction=numberButton")
                return true
            }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    /// 联系方式消息的点位几何（第十轮取证定点）：
    /// 帧在 reveal 后重读（九轮命中时帧退化为
    /// inf/0、对它算归一化点位等于盲打）；文本视
    /// 图零内边距＋lineFragmentPadding＝0（Select-
    /// ableTextView 钉死），横坐标按呈现字体
    /// .callout 在测试进程内实测字宽：号码中心＝
    /// 「值班电话 」前缀宽＋号码宽一半；纵坐标取首
    /// 行行心（lineHeight/2）。测算全程打 TEST-
    /// PHONE 行留痕；帧仍退化时回落九轮经验点位
    private func contactGeometry(
        in app: XCUIApplication
    ) throws -> (
        element: XCUIElement, frame: CGRect,
        prefixWidth: CGFloat, numberWidth: CGFloat,
        lineHeight: CGFloat
    ) {
        let text = try contactTextView(in: app)
        let frame = text.frame
        let font = UIFont.preferredFont(
            forTextStyle: .callout
        )
        let prefixWidth = ("值班电话 " as NSString)
            .size(withAttributes: [.font: font]).width
        let numberWidth = ("13800138000" as NSString)
            .size(withAttributes: [.font: font]).width
        print(
            "TEST-PHONE frame=\(frame)"
                + " prefixW=\(prefixWidth)"
                + " numberW=\(numberWidth)"
                + " lineH=\(font.lineHeight)"
        )
        return (
            text, frame, prefixWidth, numberWidth,
            font.lineHeight
        )
    }

    /// 号码正中点（阶段一长按与阶段二点按共用）
    private func phoneNumberCoordinate(
        in app: XCUIApplication
    ) throws -> XCUICoordinate {
        let g = try contactGeometry(in: app)
        guard g.frame.width > 10, g.frame.height > 5
        else {
            print("TEST-PHONE 帧退化、回落经验点位")
            return g.element.coordinate(
                withNormalizedOffset:
                    CGVector(dx: 0.32, dy: 0.30)
            )
        }
        let dx = (g.prefixWidth + g.numberWidth / 2)
            / g.frame.width
        let dy = (g.lineHeight / 2) / g.frame.height
        print(
            "TEST-PHONE numberCenter dx=\(dx) dy=\(dy)"
        )
        return g.element.coordinate(
            withNormalizedOffset: CGVector(dx: dx, dy: dy)
        )
    }

    /// 点按首行纯文本处（「值班电话」前缀）清掉阶
    /// 段一长按留下的选区——点在文本视图内、无链
    /// 接、不触发任何主动作；尽力而为、失败不拦
    private func clearSelectionByTappingPlainText(
        in app: XCUIApplication
    ) {
        guard let g = try? contactGeometry(in: app),
              g.frame.width > 10, g.frame.height > 5
        else { return }
        let dx = (g.prefixWidth / 2) / g.frame.width
        let dy = (g.lineHeight / 2) / g.frame.height
        g.element.coordinate(
            withNormalizedOffset: CGVector(dx: dx, dy: dy)
        ).tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// 失败取证：全树按钮的标识/标签紧凑清单
    private func treeSnapshot(in app: XCUIApplication) -> String {
        let buttons = app.buttons.allElementsBoundByIndex.map {
            "\($0.identifier)|\($0.label)"
        }
        return buttons.joined(separator: ", ")
    }
}
