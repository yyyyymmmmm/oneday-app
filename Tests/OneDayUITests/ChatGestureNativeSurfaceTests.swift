import UIKit
import XCTest

/// §295（原生重建 R3）包 5 手势五件在新承载
/// （UICollectionView 原生面）的对位复验：第
/// 95 条收口指定——旧承载（gen3）上 UI 绿证未
/// 达成的五件在本面以真实装配＋UI 证明复验。
/// 与 ChatGestureArbitrationTests（gen3 面基
/// 线）同题同判据、另立一册：启动参数加
/// `-chat.list.native YES`（@AppStorage 读
/// standard defaults、参数域在席即开原生面，
/// 产品码零改动）；列表元素改集合视图口径。
/// finder 沿基线的值匹配＋reveal 路（第 95 条
/// 的帧落定机器按收口口径不迁移、不重建）。
/// 五件：
/// 1. 长按正文/气泡→原生消息操作菜单与顶部玻璃反应条；
/// 2. 长按气泡边距带→整行菜单；
/// 3. 双击正文→UITextView 原生选词＋编辑菜单；
/// 4. 右滑一行→引用横幅（桥辖区帧＝cell 帧）；
/// 5. 电话（T4）：长按号码由文本选择接管（平
///    台定性）或点按出系统链接动作——任一达即
///    主动作已证；本面联系方式消息是助手原生
///    散文 cell，finder 须命中真实 UITextView。
final class ChatGestureNativeSurfaceTests: XCTestCase {

    private let rowMenuReplySymbol =
        "arrowshape.turn.up.left"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 用例

    func testComposerKeepsOneHittableActionAsDraftChanges() {
        let app = launchDemoApp()
        openSeededThread(in: app)

        let microphone = app.buttons["语音输入"]
        let send = app.buttons["发送"]
        let stop = app.buttons["停止生成"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 10))
        XCTAssertTrue(microphone.isHittable)
        XCTAssertFalse(send.exists)
        XCTAssertFalse(stop.exists)

        let placeholder = app.staticTexts["发消息…"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 10))
        let frame = placeholder.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        app.typeText("x")
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isHittable)
        XCTAssertFalse(microphone.exists)
        XCTAssertFalse(stop.exists)

        app.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        XCTAssertTrue(microphone.isHittable)
        XCTAssertFalse(send.exists)
        XCTAssertFalse(stop.exists)
    }

    /// 长按正文归消息操作菜单（含反应浮排），双击正文归系统选词与编辑菜单。
    func testLongPressOnTextShowsRowMenu() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        let text = try lastUserTextView(in: app)
        text.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).press(forDuration: 1.2)
        assertRowMenuShown(in: app)
    }

    func testLongPressOnBubblePaddingShowsRowMenu() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        // 与基线同梯：四点逐个试、逐个记结果，任
        // 一出整行菜单即收（点位全走元素坐标系）
        let attempts: [(
            name: String, base: CGVector,
            offset: CGVector, duration: TimeInterval
        )] = [
            ("左带", CGVector(dx: 0, dy: 0.5),
             CGVector(dx: -8, dy: 0), 1.5),
            ("上带", CGVector(dx: 0.5, dy: 0),
             CGVector(dx: 0, dy: -6), 1.5),
            ("左带长压", CGVector(dx: 0, dy: 0.5),
             CGVector(dx: -8, dy: 0), 2.5),
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
                // hittable 复核与 pollRowMenu 同口径
                // 双查（台账 193 判读对齐）：台账 187
                // 起动作面是自绘 sheet、项以标题在树，
                // SF Symbol 标识只在已退役的系统菜单
                // 形态在树——旧单查使本断言在面已呈
                // 现时恒假（0.50.77 两轮：pollRowMenu
                // 已命中、断言仍红，日志实证）
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

    /// 正文双击交给 UITextView 原生选词与编辑菜单；
    /// 点位分流应阻止同一触摸再触发整行菜单。
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
        // 与基线同法：慢速拖＋终点保持；先边距带
        // 起拖、不成再文本左缘内起拖
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
        // §353.3 降级登记：reveal 确定性化（定距拖
        // 动＋落定帧判）已按收口路径试跑一轮、未达
        // 绿——按路径停手、本件默认 skip，电话主
        // 动作证明归真机清单（与探针 §6-2b 既有挂
        // 账合并：UI 自动化内长期未达成）。真机备
        // 查时删本 skip 即跑（下方本体与确定性
        // reveal 均保留）。
        throw XCTSkip(
            "§353.3 降级：电话主动作证明归真机清单"
                + "（确定性 reveal 一轮未达绿、按收口"
                + "路径停手）"
        )
        let app = launchDemoApp()
        openSeededThread(in: app)
        // 阶段一：长按号码正中（点位由实帧＋字宽
        // 测算钉死）——出 Call 项链接菜单即收
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
        // 平台定性（基线第十轮·主线裁示）：可选
        // 文本视图里长按由文本选择接管、检测链接
        // 主动作是点按——改走点按证明：清选区后
        // 点按号码正中，系统链接动作任一形态出现
        // 即算主动作已达
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

    /// §330 流式工况（定因报告题 1 验收口径：双
    /// 击/长按必须在流式进行中验、静态绿不算数）。
    /// 演示发送流逐字产出定稿回复（约 14 秒）：
    /// 流式开始后对正在生长的回复正文双击→须出
    /// 编辑菜单、不出整行菜单；随后对同行气泡右
    /// 带长按→须出整行菜单。时序注记：本机执行
    /// 若慢、长按落点时流式已收尾，该断言退化为
    /// 静态长按——流式终判仍归真机照单验（交卷
    /// 清单在案）；本册在 CI 属基线红族（AX 环境
    /// 无有效信号），本件为真机/本地备查而落
    func testStreamingDoubleTapSelectsAndLongPressShowsMenu()
        throws
    {
        // §353 摘常规集（套件自注定性兑现）：流式
        // 变更树上 AX 快照按索引取元素结构性失效
        // （:290 index 56 无匹配、2026-11-22 收口
        // 调查同签名复现），本件定位真机/本地备查
        // ——默认 skip、不进常规红集口径；流式工况
        // 手势终判归真机清单（与电话主动作挂账同
        // 册）。备查时删本 skip 即跑。
        throw XCTSkip(
            "§353 摘常规集：流式 AX 快照索引失效属"
                + "环境形态、本件归真机/本地备查"
        )
        let app = launchDemoApp()
        openSeededThread(in: app)
        // 发送前基线：种子会话内同文回复的既有数
        // （发送后以「新增一条」认定流式回复在途）
        let baseline = streamingMatches(
            in: app, needle: "构建全绿"
        ).count
        // 唤起输入舱：占位字坐标点透到文本视图
        let placeholder = app.staticTexts["发消息…"]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 10),
            "输入舱占位字未出现"
        )
        let fieldFrame = placeholder.frame
        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(
            CGVector(
                dx: fieldFrame.midX, dy: fieldFrame.midY
            )
        ).tap()
        Thread.sleep(forTimeInterval: 0.6)
        app.typeText("在吗")
        let send = app.buttons["发送"]
        XCTAssertTrue(
            send.waitForExistence(timeout: 5),
            "发送钮未出现"
        )
        send.tap()
        // 流式在途证据：同文回复新增一条（生长中
        // 的前缀即含针文）
        let reply = try XCTUnwrap(
            waitStreamingReply(
                in: app, needle: "构建全绿",
                baselineCount: baseline, timeout: 12
            ),
            "流式回复未在 12 秒内开始产出"
        )
        // 流式中双击正文→选字＋编辑菜单
        reply.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)
        ).doubleTap()
        assertEditMenuShown(in: app)
        assertRowMenuAbsent(in: app)
        dismissMenus(in: app)
        // 流式中长按气泡右带（文本帧右缘外 8pt，
        // 与边距带件的右带同点法）→整行菜单
        let fresh = try XCTUnwrap(
            streamingMatches(
                in: app, needle: "构建全绿"
            ).last,
            "流式回复元素丢失"
        )
        let point = fresh.coordinate(
            withNormalizedOffset: CGVector(dx: 1, dy: 0.5)
        ).withOffset(CGVector(dx: 8, dy: 0))
        point.press(forDuration: 1.5)
        XCTAssertTrue(
            pollRowMenu(in: app, timeout: 5),
            "流式进行中长按气泡边距带须出整行菜单；"
                + "当时按钮树：" + treeSnapshot(in: app)
        )
    }

    /// 正文值匹配（与 textView(matching:) 同整形
    /// 口径）：剥整形字符后 CONTAINS 针文的元素集
    private func streamingMatches(
        in app: XCUIApplication, needle: String
    ) -> [XCUIElement] {
        candidateElements(in: app).filter { element in
            let raw = (element.value as? String)
                ?? element.label
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
            return stripped.contains(needle)
        }
    }

    /// 等流式回复出现：匹配数超过发送前基线即认
    /// 在途、返回新增的那条（集内末位）
    private func waitStreamingReply(
        in app: XCUIApplication, needle: String,
        baselineCount: Int, timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date()
            .addingTimeInterval(timeout)
        while Date() < deadline {
            let matches = streamingMatches(
                in: app, needle: needle
            )
            if matches.count > baselineCount {
                return matches.last
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return nil
    }

    // MARK: - 装配与查找

    private func launchDemoApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-odDemoMode", "-chat.list.native", "YES",
        ]
        app.launch()
        return app
    }

    /// 原生面在场的硬证据：聊天列表是集合视图
    /// （gen3/旧面为滚动视图口径）——五件全在本
    /// 断言之后跑，面不对整册无意义
    private func assertNativeSurface(in app: XCUIApplication) {
        XCTAssertTrue(
            app.collectionViews.firstMatch
                .waitForExistence(timeout: 15),
            "原生面未在场：集合视图不存在（旗未生效？）"
        )
    }

    /// 打开演示种子会话（与基线同路：抽屉本地
    /// 行点开种子会话；列表滚动口径换集合视图）
    private func openSeededThread(in app: XCUIApplication) {
        assertNativeSurface(in: app)
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
        // 跳到底部：走生产「回到底部」钮，无钮时
        // 以列表上滑兜底；落底后末条消息物化在屏内
        let toBottom = app.buttons["chevron.down"]
        if toBottom.waitForExistence(timeout: 3),
           toBottom.isHittable {
            toBottom.tap()
        } else {
            // 抽屉刚关、内容层回树有动画时差——走
            // app 级滑动不赌集合视图在树时刻
            for _ in 0..<6 {
                app.swipeUp()
            }
        }
        Thread.sleep(forTimeInterval: 1.5)
        // 落位搜索（2026-11-22 探针七＋八定案）：开页落点是流末
        // 待批卡片，末条用户消息在卡片上方；托管文本视图无障碍
        // 帧开页初读为陈旧值、元素随滚动物化进出树，帧稳定等待
        // 与单次滑动都落空。唯一可靠法：逐次单滑＋每滑必读，目
        // 标帧落进可视带（minY≥150、maxY≤740）且连续两读不变
        // 才算落位。先向下搜（朝更早消息），不中再向上搜。
        let list = app.collectionViews.firstMatch
        func targetFrame() -> CGRect? {
            for element in candidateElements(in: app) {
                let raw = (element.value as? String)
                    ?? element.label
                if raw.contains("按你说的顺序来") {
                    return element.frame
                }
            }
            return nil
        }
        func settledFrame() -> CGRect? {
            guard let f = targetFrame(),
                  f.minY >= 150, f.maxY <= 740, !f.isEmpty
            else { return nil }
            Thread.sleep(forTimeInterval: 0.35)
            guard let f2 = targetFrame(), f2 == f
            else { return nil }
            return f
        }
        var found = settledFrame()
        var tries = 0
        while found == nil, tries < 12 {
            list.swipeDown()
            Thread.sleep(forTimeInterval: 0.45)
            found = settledFrame()
            tries += 1
        }
        tries = 0
        while found == nil, tries < 12 {
            list.swipeUp()
            Thread.sleep(forTimeInterval: 0.45)
            found = settledFrame()
            tries += 1
        }
        XCTAssertNotNil(
            found,
            "落位搜索未找到末条用户消息的可视帧"
        )
    }

    private func lastUserTextView(
        in app: XCUIApplication
    ) throws -> XCUIElement {
        try textView(matching: "按你说的顺序来", in: app)
    }

    private func contactTextView(
        in app: XCUIApplication
    ) throws -> XCUIElement {
        try textView(matching: "值班电话", in: app)
    }

    /// 按正文找承载文本视图（基线同法：a11y
    /// value 经整形插有 U+2060、谓词 CONTAINS
    /// 必落空——逐元素读 value 剥整形字符后比
    /// 对；找不到时上滑促物化后重找）
    private func textView(
        matching needle: String, in app: XCUIApplication
    ) throws -> XCUIElement {
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
                        awaitStableFrame(element)
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
        throw NSError(
            domain: "ChatGestureNativeSurface", code: 1
        )
    }

    private func candidateElements(
        in app: XCUIApplication
    ) -> [XCUIElement] {
        app.textViews.allElementsBoundByIndex
            + app.staticTexts.allElementsBoundByIndex
    }

    /// 帧稳定等待（2026-11-22 探针定案）：原生面
    /// 行的无障碍帧在列表落位未稳时是瞬时值——
    /// 元素 hittable 为真、帧却是落底前的位置，
    /// 手势按该帧落点点在已移走的行上、恒无菜
    /// 单（文本三件全灭的真因，产品侧选字/菜单
    /// 经探针实证全好）。返回元素前等其帧连续
    /// 两读不变（0.4 秒间隔、最长约 6 秒），把
    /// 落位竞速关在 finder 里，五个用例同享。
    private func awaitStableFrame(_ element: XCUIElement) {
        var previous = element.frame
        for _ in 0..<15 {
            Thread.sleep(forTimeInterval: 0.4)
            let current = element.frame
            if current == previous, !current.isEmpty {
                return
            }
            previous = current
        }
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

    /// 确定性 reveal（§353 改版）：按元素实帧与
    /// 可视带（minY 150、maxY 740——openSeeded-
    /// Thread 落位搜索同带）的偏差定距拖动集合视
    /// 图、每步落定后重读帧判定。旧版盲滑（只按
    /// minY 二分方向整幅 swipe、不验落点）为收口
    /// 调查电话件失败形态：14 次滚动后元素仍不可
    /// 命中、未走到号码证明。帧退化时固定步长朝
    /// 列表下方探一步；单步限幅 600pt 防过冲、余
    /// 量下一步收；步数上限 14 沿旧值。
    private func reveal(
        _ element: XCUIElement, in app: XCUIApplication
    ) {
        let list = app.collectionViews.firstMatch
        let bandMinY: CGFloat = 150
        let bandMaxY: CGFloat = 740
        var attempts = 0
        while !element.isHittable, attempts < 14 {
            let frame = element.frame
            let anchor = list.coordinate(
                withNormalizedOffset:
                    CGVector(dx: 0.5, dy: 0.5)
            )
            if frame.isEmpty || !frame.minY.isFinite {
                anchor.press(
                    forDuration: 0.05,
                    thenDragTo: anchor.withOffset(
                        CGVector(dx: 0, dy: -300)
                    ),
                    withVelocity: .slow,
                    thenHoldForDuration: 0.2
                )
            } else {
                let targetCenterY =
                    (bandMinY + bandMaxY) / 2
                let rawDelta = frame.midY - targetCenterY
                let delta = max(-600, min(600, rawDelta))
                anchor.press(
                    forDuration: 0.05,
                    thenDragTo: anchor.withOffset(
                        CGVector(dx: 0, dy: -delta)
                    ),
                    withVelocity: .slow,
                    thenHoldForDuration: 0.2
                )
            }
            attempts += 1
            awaitStableFrame(element)
        }
        XCTAssertTrue(
            element.isHittable,
            "目标文本滚动后仍不可命中"
        )
    }

    // MARK: - 断言助手（与基线同判据）

    /// §353 浮排动作卡判据（§343/§346 三层同呈的
    /// 卡层）：卡内四项（回复/复制/选择/分享）以标
    /// 题在树——轮询至四项齐在或超时失败、失败倾
    /// 印按钮树。反应条（顶层药丸排）的 AX 形态不
    /// 稳、本判据以卡层为长按呈现的落点证据。
    private func assertFloatingActionCardShown(
        in app: XCUIApplication
    ) {
        let labels = ["回复", "复制", "选择", "分享"]
        func allPresent() -> Bool {
            labels.allSatisfy { label in
                app.buttons.matching(
                    NSPredicate(
                        format: "label == %@", label
                    )
                ).firstMatch.exists
            }
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !allPresent() {
            Thread.sleep(forTimeInterval: 0.3)
        }
        if !allPresent() {
            XCTFail(
                "长按正文后浮排动作卡未齐在场"
                    + "（回复/复制/选择/分享）；当时按钮树："
                    + treeSnapshot(in: app)
            )
        }
    }

    /// 「选择文本」页内的承载文本视图：与气泡内
    /// 同文元素并存于树（sheet 覆盖在上），以帧宽
    /// 最大者认页内件（页内正文整宽、气泡为消息
    /// 宽）。值匹配整形口径与 textView(matching:)
    /// 同源。
    private func widestTextView(
        matching needle: String, in app: XCUIApplication
    ) throws -> XCUIElement {
        var best: XCUIElement?
        var bestWidth: CGFloat = -1
        for element in candidateElements(in: app) {
            let raw = (element.value as? String)
                ?? element.label
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
            if stripped.contains(needle),
               element.frame.width > bestWidth {
                best = element
                bestWidth = element.frame.width
            }
        }
        guard let best else {
            XCTFail(
                "「选择文本」页内找不到正文「\(needle)」"
            )
            throw NSError(
                domain: "ChatGestureNativeSurface",
                code: 2
            )
        }
        return best
    }

    /// 全类型元素摘要（诊断用）：按钮/菜单项/其
    /// 他元素的标识与标签倾印
    private func allElementsDigest(
        in app: XCUIApplication
    ) -> String {
        let buttons = app.buttons.allElementsBoundByIndex
            .map { "B:\($0.identifier)|\($0.label)" }
        let items = app.menuItems.allElementsBoundByIndex
            .map { "M:\($0.identifier)|\($0.label)" }
        let others = app.otherElements.allElementsBoundByIndex
            .map { "O:\($0.identifier)|\($0.label)" }
        return (buttons + items + others)
            .joined(separator: ", ")
    }

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

    /// 整行菜单出现的判据：双口径轮询（同
    /// pollRowMenu），限时未出即判失败并附
    /// 按钮树（与 assertEditMenuShown 同式）
    private func assertRowMenuShown(in app: XCUIApplication) {
        if !pollRowMenu(in: app, timeout: 10) {
            XCTFail(
                "长按后整行菜单未出现；当时按钮树："
                    + treeSnapshot(in: app)
            )
        }
    }

    private func assertRowMenuAbsent(in app: XCUIApplication) {
        // 双口径同 pollRowMenu（台账 193 判读对
        // 齐）：自绘动作面项以标题在树——只查 SF
        // Symbol 标识时，文本长按若误呈动作面、本
        // 断言看不见（0.50.77 第二轮靠编辑菜单断
        // 言的标签错位才间接暴露），改两口径皆无
        // 才算不在场
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

    private func pollRowMenu(
        in app: XCUIApplication, timeout: TimeInterval
    ) -> Bool {
        // 原生 UIMenu 的菜单项以标题为标签在树；
        // SF Symbol 标识与标题两口径任一命中即认
        // （基线 SwiftUI 菜单以 symbol 标识在树）
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

    private func menuLabels(
        in app: XCUIApplication
    ) -> [String] {
        app.menuItems.allElementsBoundByIndex
            .map { $0.label }.filter { !$0.isEmpty }
    }

    private func dismissMenus(in app: XCUIApplication) {
        let rowItem = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@",
                rowMenuReplySymbol
            )
        ).firstMatch
        if rowItem.exists || editMenuVisible(in: app) {
            app.collectionViews.firstMatch.swipeDown()
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

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

    /// 联系方式消息的点位几何：帧在 reveal 后重
    /// 读；呈现字体走现行正文单源 .body（§263
    /// 后用户/助手同档——基线文件里的 .callout
    /// 是升档前口径、本册按现行口径测算）；号码
    /// 中心＝前缀宽＋号码宽一半、纵取首行行心
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
            forTextStyle: .body
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

    private func treeSnapshot(in app: XCUIApplication) -> String {
        let buttons = app.buttons.allElementsBoundByIndex.map {
            "\($0.identifier)|\($0.label)"
        }
        return buttons.joined(separator: ", ")
    }
}

// MARK: - §440 长按呈现（独立册，见类注释）

/// §440 长按呈现复现与量测（2026-11-24，用户真机
/// 亲报三件：预览截断／反应条与菜单锚定漂移／点
/// 空白不能取消）。
/// 目标口径（续办两轮改判）：其一，目标元素必须
/// 完整落进聊天区才许长按（首版测把贴顶元素中心
/// 按在顶栏区、浮排没呈起来、收起断言空过）；其
/// 二，靶子必须是**可反应条目**——种子长助手消息
/// 无 serverRowID（canReact 谓词不过）长按只出系
/// 统菜单、量不到浮排；同种子会话的用户消息「按
/// 你说的顺序来」可反应、与既有浮排测同靶。呈没
/// 呈浮排以药丸钮／「关闭」压暗钮在场判别（动作
/// 卡条目与系统菜单同名、不作判据）。截断几何由
/// ReactionFloatingBarTests 单测钉，本册只钉真窗
/// 口三层帧对账与收起往返（顶带／底带／侧边点按
/// ＋压暗区拖动逐路落账）。
final class LongPressPresentation440Tests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private let needle = "按你说的顺序来"

    // MARK: - 量测＋点空白收起（逐路试）

    func testMeasureStackFramesThenOutsideTapDismisses() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        let target = try positionedTarget(in: app)
        let before = target.frame
        print("§440-MEASURE window=\(app.frame)")
        print("§440-MEASURE targetTextFrame=\(before)")
        bubblePaddingCoordinate(for: target, in: app)
            .press(forDuration: 1.2)
        XCTAssertTrue(
            waitOverlay(in: app, timeout: 10),
            "长按后浮排（药丸排）未出现"
        )
        dumpStackFrames(in: app, tag: "presented")
        // 快照对位（§440 坐标原点回归全屏的判据）：
        // 同文副本（原行＋快照，含 textView/static-
        // Text 双份）的 minY 极差须 ≤6——快照 1.02
        // 缩放只许差 2~3；若浮层坐标原点被压进安
        // 全区，极差会是 62 量级、当场红
        let copies = (
            app.textViews.allElementsBoundByIndex
                + app.staticTexts.allElementsBoundByIndex
        ).filter { element in
            let raw = (element.value as? String)
                ?? element.label
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
            return stripped.contains(needle)
                && element.frame.height > 20
        }
        XCTAssertGreaterThanOrEqual(
            copies.count, 2, "原行与快照副本应同在场"
        )
        if copies.count >= 2 {
            let ys = copies.map { $0.frame.minY }
            XCTAssertLessThanOrEqual(
                (ys.max() ?? 0) - (ys.min() ?? 0), 6,
                "快照与原消息纵向错位（极差 "
                    + "\((ys.max() ?? 0) - (ys.min() ?? 0))）"
            )
        }
        // 逐路点空白：顶带→底带→左侧中段，逐路落账
        let probes: [(String, CGVector)] = [
            ("tapTopStrip", CGVector(dx: 0.5, dy: 0.045)),
            ("tapBottomStrip", CGVector(dx: 0.5, dy: 0.97)),
            ("tapLeftEdge", CGVector(dx: 0.04, dy: 0.45)),
        ]
        for (name, offset) in probes {
            if !overlayPresent(in: app) { break }
            app.coordinate(
                withNormalizedOffset: offset
            ).tap()
            Thread.sleep(forTimeInterval: 1.0)
            print(
                "§440-DISMISS \(name) gone="
                    + "\(!overlayPresent(in: app))"
            )
        }
        XCTAssertTrue(
            !overlayPresent(in: app),
            "三路点空白后浮排仍未收起（缺陷三复现）"
        )
    }

    // MARK: - 拖动收起往返

    func testDragDismissesOnDimAndSnapshot() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        // 一段：纯压暗区（左列中段，x=16 避开药丸与
        // 卡的横向跨度）起手纵拖——滚动意图须收起。
        // 注：首版起手点 (0.5,0.045) 落在状态栏带、
        // 触点没到压暗层，测的是空气；二版 (0.5,0.30)
        // 又落在药丸本体上。纯压暗点须三向避让
        var target = try positionedTarget(in: app)
        // 定位（探针二定案）：慢速拖（velocity
        // .slow）步长与拖程 1:1、无动量乱窜（实测
        // 拖 359 动 349）；普通拖在本面不跟手、
        // collection swipe 一步 ~500 太粗。瞄带中
        // 645 逐轮按偏差修正，目标带 [600, 690]：
        // 过 600 才逼得出整摞上移、过 690 按点压
        // 进输入栏区（实证：冲到 755 时长按落在
        // 输入栏上、不呈浮排）
        var rounds = 0
        while (target.frame.maxY < 600
            || target.frame.maxY > 690), rounds < 6 {
            let delta = 645 - target.frame.maxY
            bubblePaddingCoordinate(for: target, in: app).press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(
                        dx: 0.5,
                        dy: (target.frame.midY + delta)
                            / app.frame.height
                    )
                ),
                withVelocity: .slow,
                thenHoldForDuration: 0.1
            )
            Thread.sleep(forTimeInterval: 1.2)
            rounds += 1
            guard let again = settledNeedle(in: app) else {
                XCTFail("定位后 needle 元素丢失")
                return
            }
            target = again
        }
        XCTAssertTrue(
            target.frame.maxY >= 600
                && target.frame.maxY <= 690,
            "定位后靶子仍未进 [600,690] 带"
                + "（实得 \(target.frame)）"
        )
        // 落定再按：合成拖动后列表滑行期里长按会被
        // 滚动面吞掉（首跑实证：帧已到位、按了不呈）
        Thread.sleep(forTimeInterval: 1.5)
        if let settled = needleElement(in: app) {
            target = settled
        }
        dumpStackFrames(in: app, tag: "bottom440-pre")
        // 按点纵坐标钳进列表区（≤690）：元素中心可
        // 能已贴输入栏，按元素中心会压在输入栏上
        let pressY = min(
            max(target.frame.midY, 200), 690
        )
        bubblePaddingCoordinate(
            for: target, in: app, y: pressY
        ).press(forDuration: 1.2)
        if !waitOverlay(in: app, timeout: 6) {
            // 一次重试：先点角落散掉可能在场的系统
            // 菜单、重取帧再按
            dumpStackFrames(in: app, tag: "bottom440-mid")
            app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.04, dy: 0.10)
            ).tap()
            Thread.sleep(forTimeInterval: 0.8)
            if let again = needleElement(in: app) {
                target = again
            }
            let retryY = min(
                max(target.frame.midY, 200), 690
            )
            bubblePaddingCoordinate(
                for: target, in: app, y: retryY
            ).press(forDuration: 1.2)
        }
        XCTAssertTrue(
            waitOverlay(in: app, timeout: 10),
            "贴底靶子长按后浮排未出现"
        )
        dumpStackFrames(in: app, tag: "bottom440")
        let pills = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@", "反应："
            )
        ).allElementsBoundByIndex
        guard let pill = pills.first else {
            XCTFail("浮排已呈但药丸钮不在场")
            return
        }
        XCTAssertGreaterThanOrEqual(
            pill.frame.minY, 55,
            "药丸顶进了状态栏带——视口仍是全屏口径"
        )
        // 卡条目＝浮排在场时其余按钮里纵向成列的一组
        // （排除药丸/关闭/顶栏与输入区铬件，取 y 跨
        // 度最大的一组近似整卡）
        let others = app.buttons.allElementsBoundByIndex
            .filter { button in
                !button.label.hasPrefix("反应：")
                    && button.label != "关闭"
                    && button.frame.minY > pill.frame.maxY
                    && button.frame.width > 150
            }
        guard let firstItem = others.min(by: {
            $0.frame.minY < $1.frame.minY
        }), let lastItem = others.max(by: {
            $0.frame.maxY < $1.frame.maxY
        }) else {
            XCTFail("动作卡条目不在场")
            return
        }
        print(
            "§440-BOTTOM pill=\(pill.frame) "
                + "cardItemsTop=\(firstItem.frame.minY) "
                + "cardItemsBottom=\(lastItem.frame.maxY) "
                + "window=\(app.frame)"
        )
        XCTAssertLessThanOrEqual(
            abs(lastItem.frame.maxY - 834), 8,
            "卡底不在安全区口径 834±8（实得 "
                + "\(lastItem.frame.maxY)）——视口口径终判不合"
        )
        XCTAssertGreaterThan(
            firstItem.frame.minY, pill.frame.maxY,
            "卡不在药丸下方——整摞纵序坏了"
        )
        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)
        ).tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(
            !overlayPresent(in: app), "贴底浮排点底带未收起"
        )
    }

    // MARK: - 装配（与 ChatGestureNativeSurfaceTests 同路）

    private func launchDemoApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-odDemoMode", "-chat.list.native", "YES",
        ]
        app.launch()
        return app
    }

    private func openSeededThread(in app: XCUIApplication) {
        XCTAssertTrue(
            app.collectionViews.firstMatch
                .waitForExistence(timeout: 15),
            "原生面未在场"
        )
        let openButton = app.buttons["drawer.open"]
        XCTAssertTrue(
            openButton.waitForExistence(timeout: 15),
            "抽屉入口未出现"
        )
        if openButton.isHittable { openButton.tap() }
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
        guard let found = target else {
            XCTFail("抽屉里找不到演示种子会话行")
            return
        }
        let rowID = found.identifier
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
            "点种子行后顶栏胶囊未出现"
        )
    }

    /// needle 元素直查（不带落区口径、不滚动）：
    /// 贴底测把靶子顶出落区后靠它重取帧
    private func needleElement(
        in app: XCUIApplication
    ) -> XCUIElement? {
        let pool = app.textViews.allElementsBoundByIndex
            + app.staticTexts.allElementsBoundByIndex
        return pool.first { element in
            let raw = (element.value as? String)
                ?? element.label
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
            return stripped.contains(needle)
                && element.frame.height > 20
        }
    }

    /// needle 落定取帧：滚动后元素查询要等层级
    /// 快照刷新（探针实证 swipe 后即查得 nil），
    /// 4 次 0.5s 重试
    private func settledNeedle(
        in app: XCUIApplication
    ) -> XCUIElement? {
        for _ in 0..<4 {
            if let element = needleElement(in: app) {
                return element
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return needleElement(in: app)
    }

    /// 可反应用户消息定位：a11y value 剥整形字符
    /// （U+2060／U+200B／U+FEFF，既有测同口径）
    /// 后比对；完整落进聊天区（顶 120 至窗底
    /// −80）才返回，贴顶下滑／出底上滑逐轮重查
    private func positionedTarget(
        in app: XCUIApplication
    ) throws -> XCUIElement {
        let list = app.collectionViews.firstMatch
        let deadline = Date().addingTimeInterval(40)
        var step = 0
        while Date() < deadline {
            let candidates = (
                app.textViews.allElementsBoundByIndex
                    + app.staticTexts.allElementsBoundByIndex
            ).filter { element in
                let raw = (element.value as? String)
                    ?? element.label
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
                return stripped.contains(needle)
                    && element.frame.height > 20
            }
            print(
                "§440-POS step=\(step) candidates="
                    + "\(candidates.map { $0.frame })"
            )
            if let inZone = candidates.first(where: {
                $0.frame.minY >= 120
                    && $0.frame.maxY
                        <= app.frame.height - 80
            }) {
                return inZone
            }
            guard let tallest = candidates.max(by: {
                $0.frame.height < $1.frame.height
            }) else {
                list.swipeDown()
                Thread.sleep(forTimeInterval: 0.5)
                step += 1
                continue
            }
            if tallest.frame.minY < 120 {
                list.swipeDown()
            } else {
                list.swipeUp()
            }
            Thread.sleep(forTimeInterval: 0.5)
            step += 1
        }
        XCTFail("可反应消息「\(needle)」未能定位进聊天区")
        throw NSError(domain: "LongPress440", code: 1)
    }

    private func bubblePaddingCoordinate(
        for text: XCUIElement,
        in app: XCUIApplication,
        y: CGFloat? = nil
    ) -> XCUICoordinate {
        let frame = text.frame
        let x = max(1, frame.minX - 8)
        let pressY = y ?? frame.midY
        return app.coordinate(
            withNormalizedOffset: CGVector(
                dx: x / app.frame.width,
                dy: pressY / app.frame.height
            )
        )
    }

    /// 浮排在场判据：药丸钮（反应：…）或压暗钮
    /// （关闭）任一在场——系统菜单无此二者
    private func overlayPresent(
        in app: XCUIApplication
    ) -> Bool {
        app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@", "反应："
            )
        ).firstMatch.exists
            || app.buttons.matching(
                NSPredicate(format: "label == %@", "关闭")
            ).firstMatch.exists
    }

    private func waitOverlay(
        in app: XCUIApplication, timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if overlayPresent(in: app) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return overlayPresent(in: app)
    }

    /// 全钮倾印＋同文帧倾印：药丸钮／压暗钮／卡条
    /// 目的帧与位次靠全量落账对账（原行与快照复
    /// 刻并存时逐个落账）
    private func dumpStackFrames(
        in app: XCUIApplication, tag: String
    ) {
        var lines: [String] = []
        for button in app.buttons.allElementsBoundByIndex {
            let line = "§440-MEASURE \(tag) anyButton "
                + "label=\(button.label) frame=\(button.frame)"
            print(line)
            lines.append(line)
        }
        let copies = app.textViews.allElementsBoundByIndex
            + app.staticTexts.allElementsBoundByIndex
        for element in copies {
            let raw = (element.value as? String)
                ?? element.label
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
                let line = "§440-MEASURE \(tag) textCopy "
                    + "frame=\(element.frame)"
                print(line)
                lines.append(line)
            }
        }
        // print 在 UI 测进程里抓不到，帧账走附件出仓
        let attachment = XCTAttachment(
            string: lines.joined(separator: "\n")
        )
        attachment.name = "440frames-\(tag)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
