import XCTest

/// 出厂冒烟门（2026-11-14 立门，release-smoke-gate-20261114.md；
/// 2026-11-23 按现行面重做，DESIGN §401）：把「默认路径之
/// 外真用一遍」落成 UI 真执行——开关真拨、数据真非空、首
/// 帧真渲染。本套件红＝不许组版交付（DESIGN §190 前置
/// 子集）。与 §395 生命周期常设门分工：那边管装/升/降，
/// 本门管核心面真执行冒烟。
///
/// 重做沿革：旧套件在 chore/smoke-gate 分支 12 轮未合入，
/// 其间多例目标面已被换引擎（§374）/结构归位（2026-11
/// -20）/文件面重构改写。逐例三态（详 §401）：
/// - 已改写 2：gen3 两例——gen3 承载与开关已随换引擎步
///   骤 6（§374.9）整件退役，现行列表为 ChatNativeList
///   单面；其「非默认构造首帧不崩」职责改写到现行仍在
///   的真开关「聊天列表单 section 布局」（关＝回退
///   §329 逐行 section 构造）：设置内真拨＋启动参数
///   预置两路，形态与原例 1:1。
/// - 迁移 5：A-1 首连（欢迎面改分叉版式，首步改点「连
///   接已有服务器」）／A-4 文件网格／A-6 英文首帧／偏
///   好合并／回底箭头端到端（第十一轮自进程内例迁入，
///   沿革见例内注）。
/// - 退役 2（不在本文件立例，理由在此登记）：全部对话
///   「显示系统运行」开关——2026-11-20 结构归位第二批
///   退役，系统运行下沉维护子页恒显、无开关可拨；A-8
///   抽屉分区显隐——显隐账整套 2026-11-20 退役（Core
///   SectionCollapse.swift 退役注记：治理面摘除、分
///   区恒显），无面可验。
/// A-2 存量迁移在 OneDayAppTests 的 SmokeGateMigra-
/// tionTests；长会话内容侧在 SmokeGateLongListScroll-
/// Tests；A-3/A-5/A-7 自动化够不到，逐条转发版门文
/// 档真机手验清单。
final class SmokeGateUITests: XCTestCase {

    /// 演示种子主线程首帧可见文（现行 DemoSeeder 播
    /// 种，逐字核对 2026-11-23）：尾三条（开线程默认
    /// 落底、必在树里）＋头两条（列表若落顶时兜底），
    /// 任一命中即算开出。
    private let seedMarkers = [
        "三个节点都在线",
        "昨晚洛川雨挺大",
        "好，就按你说的顺序来。",
        "刚查过，一切正常",
        "帮我看看服务器现在的状态，顺便确认",
    ]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// pinChineseLocale：CI 模拟器是英文区域（DrawerRow
    /// 注释实证），演示文案经词条库本地化——不钉语言，
    /// 「开始连接」等按钮以英文渲染、按中文查必然超时
    /// （run 43612107391 的 A1 即此）。标准做法：
    /// -AppleLanguages (zh-Hans)。A6 测英文路径，显式
    /// 传 false（其断言只认硬编码中文件＋本地化行）。
    private func launchDemo(
        _ extra: [String], pinChineseLocale: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-odDemoMode"]
        if pinChineseLocale {
            args += ["-AppleLanguages", "(zh-Hans)"]
        }
        args += extra
        app.launchArguments = args
        app.launch()
        return app
    }

    /// 等任一文案出现在无障碍树（轮询多元素类型）
    private func waitForAnyText(
        _ app: XCUIApplication, _ needles: [String],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for needle in needles {
                let hit = app.descendants(matching: .any)
                    .matching(NSPredicate(
                        format: "label CONTAINS %@", needle
                    )).firstMatch
                if hit.exists { return true }
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return false
    }

    /// 开抽屉并点进第一条本地种子线程（非空首帧落点；
    /// 演示种子按 updatedAt 倒序，首行即主线程）
    private func openFirstSeededThread(
        _ app: XCUIApplication, line: UInt = #line
    ) {
        let rows = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "drawer.row.side.local."
        ))
        if !rows.firstMatch.waitForExistence(timeout: 6) {
            // 抽屉未开（设置关闭后可能已收回）：先开抽屉
            let opener = app.buttons["drawer.open"]
            XCTAssertTrue(
                opener.waitForExistence(timeout: 15),
                "抽屉开启钮应在场", line: line
            )
            opener.tap()
        }
        XCTAssertTrue(
            rows.firstMatch.waitForExistence(timeout: 15),
            "抽屉本地种子行应在场", line: line
        )
        // r2 定因（§401）：现行抽屉行高/分区变长，本
        // 地行默认落在屏幕外（实测首行 frame y≈839、
        // 屏高 874，仅露一线）；XCUI 对半露行仍报
        // hittable、点按落在屏底不激活——旧版「不可
        // 命中才滑一次」的兜底不触发。改为先把抽屉
        // 滚到行完整入屏再点。
        let row = rows.firstMatch
        let screen = app.windows.firstMatch.frame
        var swipes = 0
        while swipes < 8 {
            let frame = row.frame
            if frame.height > 0, frame.minY >= screen.minY,
                frame.maxY <= screen.maxY - 4
            {
                break
            }
            app.swipeUp()
            swipes += 1
        }
        row.tap()
    }

    /// 经抽屉底条齿轮进设置（演示态既有路径）。
    /// run 43612107391 自查：三例同卡于「关闭钮未现」
    /// ——齿轮在抽屉宿主常驻、未开时也可能已在树里，
    /// 只查存在就点，可能点到未落定的抽屉动画或离屏
    /// 钮。本版三道加固：①等频道行可命中、确认抽屉
    /// 真开；②齿轮可命中才点；③关钮 20 秒未现则重
    /// 拨一次（置位只在呈现时消费，重拨幂等），仍未
    /// 现把当场按钮清单写进断言、供下一轮日志定位。
    /// 生产路径真机可证，若加固后重跑仍卡于此步，即
    /// 升产品问题处理。
    private func openSettings(
        _ app: XCUIApplication,
        gearLabels: [String] = ["设置"],
        closeLabel: String = "关闭设置",
        line: UInt = #line
    ) {
        let channelRow = app.buttons["drawer.row.channel.hermes"]
        if !channelRow.exists {
            // 抽屉未开才走开启钮：开态下内容面被
            // DrawerContainerView.syncAccessibility
            // 整棵摘出无障碍树，drawer.open 永不存在
            // （run 43650912503 ZA8 实证）；调用方若
            // 已在开态抽屉里，频道行直接在场、跳过
            // 开启步。
            let opener = app.buttons["drawer.open"]
            XCTAssertTrue(
                opener.waitForExistence(timeout: 25),
                "抽屉开启钮应在场", line: line
            )
            opener.tap()
        }
        XCTAssertTrue(
            channelRow.waitForExistence(timeout: 15),
            "抽屉应打开（频道行在场）", line: line
        )
        var gear: XCUIElement?
        for label in gearLabels {
            let candidate = app.buttons[label]
            if candidate.waitForExistence(timeout: 8) {
                gear = candidate
                break
            }
        }
        guard let gear else {
            XCTFail("抽屉底条设置钮应在场", line: line)
            return
        }
        let gearDeadline = Date().addingTimeInterval(10)
        while !gear.isHittable && Date() < gearDeadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(gear.isHittable, "抽屉齿轮应可命中", line: line)
        gear.tap()
        if !app.buttons[closeLabel].waitForExistence(timeout: 20) {
            if gear.exists && gear.isHittable {
                gear.tap()
            }
            if !app.buttons[closeLabel].waitForExistence(timeout: 15) {
                let visible = app.buttons.allElementsBoundByIndex
                    .prefix(20).map { $0.label }
                    .joined(separator: " | ")
                XCTFail(
                    "设置页应打开（关闭钮在场）；当场按钮：\(visible)",
                    line: line
                )
                return
            }
        }
    }

    /// 在设置类列表里滚动直到元素可点（设置根与关于
    /// 页均为 List，XCUI 侧或作 table 或作 collection
    /// ——依次试三种容器，取先在场者滑动）
    @discardableResult
    private func scrollSettings(
        _ app: XCUIApplication, until element: XCUIElement,
        maxSwipes: Int = 18
    ) -> Bool {
        func container() -> XCUIElement {
            if app.tables.firstMatch.exists {
                return app.tables.firstMatch
            }
            if app.collectionViews.firstMatch.exists {
                return app.collectionViews.firstMatch
            }
            return app.scrollViews.firstMatch
        }
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return true
            }
            container().swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// 开关真拨：点 knob 坐标＋轮询读值。
    /// run 43634025826 实证：整行中点点按事件已合成、
    /// 值仍为 "0"，点按后立即读值不可靠——落点改点
    /// 开关 trailing 侧 knob，读值改带超时轮询。
    private func tapSwitchAndWait(
        _ element: XCUIElement, to expected: String,
        timeout: TimeInterval = 8, line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: 20),
            "开关应在场", line: line
        )
        element.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == expected {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(
            element.value as? String, expected,
            "开关拨后值应为 \(expected)", line: line
        )
    }

    /// 设置根→「关于 OneDay」→内部实验节的单 section
    /// 开关（现行实验开关的家：结构归位 2026-11-20
    /// 起实验组沉关于页末节，SettingsSupportViews
    /// .AboutView.labSection）
    private func openLabSingleSectionToggle(
        _ app: XCUIApplication, line: UInt = #line
    ) -> XCUIElement {
        let aboutRow = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "label == %@", "关于 OneDay"
            )).firstMatch
        XCTAssertTrue(
            scrollSettings(app, until: aboutRow),
            "设置内关于 OneDay 行应可达", line: line
        )
        aboutRow.tap()
        let toggle = app.switches.matching(NSPredicate(
            format: "label CONTAINS %@", "单 section"
        )).firstMatch
        XCTAssertTrue(
            scrollSettings(app, until: toggle),
            "内部实验单 section 开关应可达", line: line
        )
        return toggle
    }

    /// 全部滚动条证据（归属判定用）：逐个打印 frame
    /// 与 value——聊天列表的滚动条贴窗口右缘（x≈369
    /// 起）、抽屉的贴抽屉右缘（x≈287 起），按 x 分
    /// 归属，免单值误取（r5 的 90% 归属未定）
    private func mainScrollValue(_ app: XCUIApplication) -> String {
        let bars = app.otherElements.matching(NSPredicate(
            format: "label CONTAINS %@", "垂直滚动条"
        )).allElementsBoundByIndex
        if bars.isEmpty { return "none" }
        return bars.map {
            "x\($0.frame.minX)/h\($0.frame.height)"
                + "=\($0.value ?? "nil")"
        }.joined(separator: " ")
    }

    /// 自关于页返回设置根并关设置
    private func closeSettingsFromAbout(
        _ app: XCUIApplication, line: UInt = #line
    ) {
        app.navigationBars.buttons.firstMatch.tap()
        let close = app.buttons["关闭设置"]
        XCTAssertTrue(
            close.waitForExistence(timeout: 10),
            "返回设置根后关闭钮应在场", line: line
        )
        close.tap()
    }

    // MARK: - 列表引擎非默认构造（旧 A-0 gen3 两例改写）

    /// 设置内真拨：单 section（默认开）→拨关（回退
    /// §329 逐行 section 构造）→进非空线程首帧不崩。
    /// 通过后拨回开，免污染同轮其他套件的沙盒默认值。
    /// 原例拨的是 gen3 承载开关（chat.carrier.gen3）：
    /// 承载本体与开关已随换引擎步骤 6 退役（§374.9），
    /// 本例按同形态（真开关＋非默认构造＋首帧）改写到
    /// 现行开关，防崩职责不变。
    func testSmokeListEngineFlipFromSettings() {
        let app = launchDemo([])
        openSettings(app)
        let toggle = openLabSingleSectionToggle(app)
        // 基线归一化：UI 套件同装共享沙盒、上轮若在
        // 拨关后中断会把「关」留在盘上（r3 实证）；
        // 先拨回开建立基线，再走被测的关程——归一
        // 化只摆 fixture、不动被测断言。
        if (toggle.value as? String) != "1" {
            tapSwitchAndWait(toggle, to: "1")
        }
        XCTAssertEqual(
            toggle.value as? String, "1", "基线应先归一化为开"
        )
        tapSwitchAndWait(toggle, to: "0")
        XCTAssertEqual(
            app.state, .runningForeground,
            "拨关单 section 后 App 必须存活"
        )
        closeSettingsFromAbout(app)
        openFirstSeededThread(app)
        XCTAssertTrue(
            waitForAnyText(app, seedMarkers, timeout: 25),
            "回退构造首帧应渲染出种子消息（非空）"
        )
        XCTAssertEqual(app.state, .runningForeground)
        // 恢复默认开
        openSettings(app)
        let toggleBack = openLabSingleSectionToggle(app)
        if (toggleBack.value as? String) == "0" {
            tapSwitchAndWait(toggleBack, to: "1")
        }
        XCTAssertEqual(toggleBack.value as? String, "1")
        closeSettingsFromAbout(app)
    }

    /// 预置关闭首帧：启动参数域预置 chatListSingle-
    /// SectionEnabled=NO 直达会话，复刻用户「关着开
    /// 关冷启动」路径（原例预置 gen3=YES 复刻 .ips 的
    /// 启动即崩循环，形态同构）。
    func testSmokeListEnginePresetFirstFrame() {
        let app = launchDemo(["-chatListSingleSectionEnabled", "NO"])
        XCTAssertTrue(
            app.buttons["drawer.open"]
                .waitForExistence(timeout: 25),
            "预置回退构造冷启动必须活着进主界面"
        )
        openFirstSeededThread(app)
        XCTAssertTrue(
            waitForAnyText(app, seedMarkers, timeout: 25),
            "回退构造首帧应渲染出种子消息（非空）"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - 回底箭头端到端（真手势，第十一轮收口迁入）

    /// 长会话真手势离底→回底箭头出现→点箭头回
    /// 底→箭头消失。进程内长列表例的台阶判别量经第
    /// 十轮仪表定因为装配差异（进程内托管下 SwiftUI
    /// 几何回调不向 action 送达、台阶原理性不可达，
    /// 产品喂入环无罪；定案 smoke-feed-link-
    /// diagnosis-20261115.md §五），箭头端到端按等
    /// 价覆盖原则迁本形态：UI 测独立进程、真窗口、
    /// 真手势通道，几何回调送达与真机同路。演示种
    /// 子主线程含多条长回复（内容高数倍于视口），开
    /// 线程默认落底、箭头不应在场；真手势上滑过
    /// 176pt 离底阈值后箭头进布局流（label「回到
    /// 底部」，离底未读时带「，N 条新消息」后缀、按
    /// 包含匹配）；点后滚回底部、箭头退出布局流消
    /// 失。链上派生政策与量测传导另由 Core 纯函数测
    /// ＋ComposerGuideHostTests 替身钉住，覆盖不降
    /// 反升。
    /// 第十二轮改造：第十一轮首步在尾段文案进树约
    /// 3 秒即断言失败（落底态箭头已在场），「开线程
    /// 落定」族两候选未分——①落定未稳／断言抢跑
    /// （懒估行高修正把落点推离真底，或落底滚动尚
    /// 在途）；②本环境开线程初始即离底。首步改落
    /// 定轮询：轮询等箭头消失（上限 10 秒、每秒一
    /// 行 ARROWSETTLE 证据行），消失才进后续三步
    /// （原样不动）；10 秒仍在场＝候选②成立，断
    /// 言如实失败报主线（升产品开线程落底取证），
    /// 不改产品码、不放宽后续断言。
    /// 2026-11-23 重做注：承载已换 ChatNativeList
    /// （UICollectionView＋增量喂入），开线程落底由
    /// 原生面 apply 链自产（ChatNativeListAssembly
    /// Tests ③帧口径实证距底 ≤1）；候选②若在新面
    /// 复现即为新面真问题，照原口径如实红、不降格。
    func testSmokeBackToBottomArrowEndToEnd() {
        let app = launchDemo([])
        openFirstSeededThread(app)
        XCTAssertTrue(
            waitForAnyText(
                app,
                ["三个节点都在线", "昨晚洛川雨挺大",
                 "好，就按你说的顺序来。"],
                timeout: 25
            ),
            "种子主线程尾段应渲染（开线程默认落底）"
        )
        let arrow = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "回到底部"
        )).firstMatch
        // 首步落定轮询（第十二轮）：每秒查一次并打
        // 一行 ARROWSETTLE 证据行（在场状态），上限
        // 10 秒。轮询内消失＝落定完成（候选①：第十
        // 一轮首断言系抢跑），进后续三步；10 秒仍在
        // 场＝候选②成立（本环境开线程初始即离底），
        // 下方断言如实失败、分清即止。
        // r5 增证（§401）：新面首跑轮询全程在场，与
        // 诊断实测「同线程 +4s 滚动条 value=100%」
        // 相左——证据行加打箭头 frame 与主列表滚动
        // 条 value，分清「在底但箭头挂树不走」（渲染
        // 形态问题、断言口径要改）与「真离底」（产
        // 品问题、如实红）。
        let settleDeadline = Date().addingTimeInterval(10)
        var settleSecond = 0
        while arrow.exists && Date() < settleDeadline {
            print(
                "ARROWSETTLE t=\(settleSecond)s arrowExists=true"
                    + " frame=\(arrow.frame)"
                    + " scroll=\(mainScrollValue(app))"
            )
            Thread.sleep(forTimeInterval: 1)
            settleSecond += 1
        }
        print(
            "ARROWSETTLE t=\(settleSecond)s arrowExists=\(arrow.exists)"
                + " scroll=\(mainScrollValue(app))"
        )
        XCTAssertFalse(
            arrow.exists,
            "落定轮询 10 秒后回底箭头仍在场（候选②：本环境开线程初始即离底）"
        )
        // 真手势下滑离底：逐滑轮询箭头出现（离底阈
        // 值 176pt，种子内容数倍于视口、数滑必过；
        // 流式补回复在近底时可能跟随回拉，循环逐滑
        // 直至真离底）。
        // 方向定因（r3 诊断，§401）：旧承载是翻转列
        // 表、上滑离底；新 ChatNativeList 为正向
        // UICollectionView——已在底部时上滑无处可
        // 去（三式手势连读滚动条 value 全程 100% 实
        // 证），离底须下滑（手指下拖、内容下移露出
        // 旧消息）。
        let deadline = Date().addingTimeInterval(30)
        while !arrow.exists && Date() < deadline {
            app.swipeDown()
            _ = arrow.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(
            arrow.exists,
            "真手势上滑离底后回底箭头应出现"
        )
        arrow.tap()
        // 点箭头回底：箭头退出布局流、从树消失
        let goneDeadline = Date().addingTimeInterval(12)
        while arrow.exists && Date() < goneDeadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertFalse(
            arrow.exists,
            "点箭头回底后箭头应消失"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - A-1 连接页装配与首连全流程

    /// -odDemoConnect 全新安装路径：欢迎面（分叉版
    /// 式）→点「连接已有服务器」→登录面预填→点连接
    /// →探活（演示假回执）→成功页点主按钮（现行文
    /// 案「继续」）→进主界面。横扫实查此启动参数此
    /// 前在 Tests/ 内零引用。2026-11-23 改写首步：
    /// 欢迎面已改分叉版式（台账 193 引导小包），旧
    /// 「开始连接」钮不复存在，主路大按钮为「连接
    /// 已有服务器」。
    func testSmokeA1ConnectFirstRun() {
        let app = XCUIApplication()
        // 语言钉中文：连接页按钮走词条库本地化，CI 英文
        // 模拟器上不钉则以英文渲染、按中文查必然超时
        // （run 43612107391 实证）。
        app.launchArguments = [
            "-odDemoConnect", "-AppleLanguages", "(zh-Hans)",
        ]
        app.launch()
        let start = app.buttons["connect.existingServer"]
        XCTAssertTrue(
            start.waitForExistence(timeout: 25),
            "连接页欢迎面首帧应渲染（分叉主路钮在场）"
        )
        start.tap()
        let connect = app.buttons["connect.submit"]
        XCTAssertTrue(
            connect.waitForExistence(timeout: 12),
            "登录面应渲染出连接钮（表单真装配）"
        )
        XCTAssertTrue(
            app.textFields.count + app.secureTextFields.count >= 2,
            "登录面表单字段应在场"
        )
        connect.tap()
        // 成功页须手动点主按钮才进主界面（ConnectView
        // successPage：无自动跳转；run 43634025826
        // 实证：点连接后 35 秒轮询 drawer.open 永不
        // 到，因停在成功页）。按钮永不出现＝探活失
        // 败，先在此分清。按钮文案现行是「继续」
        // （2026-11-23 活树实证：成功页「已连接／
        // Hermes 已就绪」＋主按钮「继续」；旧审计记
        // 的「开始聊天」已不符，两名并查防文案再漂）。
        let begin = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["继续", "开始聊天"]
        )).firstMatch
        XCTAssertTrue(
            begin.waitForExistence(timeout: 35),
            "探活成功后应出现成功页主按钮（未出现＝探活失败）"
        )
        begin.tap()
        // r3 定因（§401）：成功页之后还有一页通知引
        // 导（「允许通知／暂时跳过」），点「暂时跳
        // 过」才进主界面；引导页若未出现（口径变更）
        // 则直达主界面、跳过本步。
        let skip = app.buttons["暂时跳过"]
        if skip.waitForExistence(timeout: 10) {
            skip.tap()
        }
        XCTAssertTrue(
            app.buttons["drawer.open"]
                .waitForExistence(timeout: 25),
            "首连全流程走完应进主界面"
        )
    }

    // MARK: - A-4 文件网格模式首帧

    /// files.displayMode 非默认档（grid）持久化后进资源
    /// 库首帧：网格真渲染出种子文件。
    /// run 43612107391 自查：旧断言按文件名查影音格，
    /// 但网格态 MediaCell 刻意不渲染文件名（0.36.4：
    /// 生成图名多为哈希串、属原始名漏出，已撤除），
    /// 按名查在网格态永远查不到。本版改断两件网格态
    /// 真渲染的东西：①文件段网格卡带标题（displayTitle
    /// 去扩展名），任一 seeded 文档卡名命中即算数据到
    /// 位；②全页按钮数下限（底栏 5＋影音格 4＋文件卡
    /// 4，取 10 作松下限），证影音格真有格子而非空态。
    /// 另断空态文案不在场（collect 空集才会出空态）。
    func testSmokeA4FilesGridFirstFrame() {
        let app = launchDemo(["-files.displayMode", "grid"])
        let tab = app.tabBars.buttons["资源库"]
        XCTAssertTrue(tab.waitForExistence(timeout: 25))
        tab.tap()
        XCTAssertTrue(
            waitForAnyText(
                app,
                ["网络巡检周报", "每日简报-1108", "交付说明"],
                timeout: 30
            ),
            "网格首帧应渲染出种子文件卡（文件段卡名）"
        )
        XCTAssertFalse(
            app.staticTexts["暂无影音交付"].exists
                || app.staticTexts["暂无交付物"].exists,
            "网格首帧不应落空态（聚合已到数据）"
        )
        XCTAssertGreaterThanOrEqual(
            app.buttons.count, 10,
            "网格首帧按钮数应含底栏＋影音格＋文件卡（≥10）"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - A-6 英文语言路径首帧

    /// appLanguage=en：设置面以英文真渲染（词条库 en
    /// 全译；未入词条库的硬编码面回落中文——登记项，
    /// 不在本例断言）。
    /// run 43612107391 自查：旧断言两处查无此物——底栏
    /// 标题是 TabBarSymbols 硬编码中文（.labelStyle
    /// (.iconOnly)＋.accessibilityLabel(pair.title)），
    /// 「Chat」在任何语言下都不存在；设置关闭钮的
    /// accessibilityLabel 原也是硬编码「关闭设置」，
    /// 「Close Settings」同样查不到。英文证明只剩本地
    /// 化行（Appearance 行），底栏只断在场。另登记产品
    /// 观察：底栏标题未本地化（A-6 原前提「底栏英文」
    /// 不成立），修不修归主线，本线只改测试预期。
    /// 2026-11-23 注：关闭钮无障碍名已由 A6 修线钉死
    /// 逐字「关闭设置」（SettingsView Text(verbatim:)，
    /// 已合入现行树）——英文档下设置 sheet 不呈现的产
    /// 品定因即此（钮名被译走、测试与读屏同失）；本例
    /// 在现行树上即该修复的常驻回归。设置 sheet 呈现
    /// 本体另有 SettingsSheetLocaleTests 中英对照钉，
    /// 本例管英文冷启首帧整面。
    func testSmokeA6EnglishFirstFrame() {
        let app = launchDemo(
            ["-appLanguage", "en"], pinChineseLocale: false
        )
        XCTAssertTrue(
            app.tabBars.buttons["聊天"]
                .waitForExistence(timeout: 25),
            "英文态底栏应在场（标题硬编码中文，不本地化）"
        )
        openSettings(
            app, gearLabels: ["Settings", "设置"],
            closeLabel: "关闭设置"
        )
        let appearance = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "label == %@", "Appearance"
            )).firstMatch
        XCTAssertTrue(
            scrollSettings(app, until: appearance),
            "英文态设置面应渲染出 Appearance 行"
        )
        app.buttons["关闭设置"].tap()
    }

    // MARK: - 偏好路径合并冒烟（深色＋主题＋头像尺寸）

    /// 三个值域型偏好一次预置非默认值：深色外观＋
    /// obsidian 聊天主题＋大头像——会话首帧照常渲染。
    func testSmokePreferencesDarkThemeAvatar() {
        let app = launchDemo([
            "-appearanceMode", "dark",
            "-chatTheme", "obsidian",
            "-avatarSize", "large",
        ])
        XCTAssertTrue(
            app.buttons["drawer.open"]
                .waitForExistence(timeout: 25)
        )
        openFirstSeededThread(app)
        XCTAssertTrue(
            waitForAnyText(app, seedMarkers, timeout: 25),
            "深色＋非默认主题＋大头像下首帧应渲染种子消息"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }
}
