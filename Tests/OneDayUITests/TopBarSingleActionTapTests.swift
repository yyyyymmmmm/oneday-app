import XCTest

/// §449 顶带动作级点按派发验证（XCUITest；前身
/// §202 两代——双动作胶囊、顶栏行中央组〈头像＋
/// 模型胶囊〉——均绑已退役形态，随 §449 顶带定
/// 版整体重钉）。打**真 App 生产装配**：启动参
/// 数 -odDemoMode 直达已连接态（RootView→Dra-
/// werContainer→TabView→ChatView→TopBarGuide-
/// Host 托管的真实顶带），按无障碍标识读四件实
/// 帧、逐点系统级点按，以真实呈现（枢纽 push／
/// 抽屉／通知 sheet）的升起判派发。
///
/// 点位与判定（预注册）：
/// - 头像域内点（中心/左右内缩 5/上缘内 5/底上
///   12 避胶囊压叠区）：必须只升枢纽。
/// - 身份胶囊域内点（中心/左右内缩 6）：必须只
///   升枢纽（与头像同路、单义）。
/// - 汉堡钮中心：只升抽屉；铃钮中心：只升通知
///   sheet。
/// - 死带三点（左右间隙中点＝钮与头像同带的横
///   向空当、头像顶上 6）：任何面都不许升。
/// 结构钉同在本门：头像命中帧 67、两钮与头像同
/// 带（钮心纵差 ≤14）、胶囊压头像下沿、已退役
/// 的顶栏模型胶囊/放大镜钮不得在场、无横跨头
/// 像与胶囊双域的融合元素。关闭路径全走生产自
/// 带口（枢纽 ✕／抽屉点行／通知 sheet 下滑）。
/// 枢纽布局回归（testHubLayoutWithFullCatalog）
/// 沿 §434 口径续行：模型入口在中枢、段集注册
/// 表动态渲染、末段可滚到底、底栏在场与否只记
/// 软留痕（硬判据在 HubPresentationProbeTests）。

final class TopBarSingleActionTapTests: XCTestCase {

    private enum Expect { case hub, drawer, sheet, none }

    /// 顶带四件实帧（点位现算的入参：每点开点前
    /// 重读——呈现往返后帧可能微移，按开场旧帧算
    /// 的点位会过期，run 43372118468 的 GAP 违规
    /// 教训）
    private struct BandFrames {
        var drawer: CGRect
        var avatar: CGRect
        var capsule: CGRect
        var bell: CGRect
    }

    private struct TapPoint {
        var name: String
        var expect: Expect
        /// 点位现算：每点开点前重读两元素实帧再落点
        /// ——关面兜底若换过模型，胶囊标签宽度会变、
        /// 左缘随之移位，按开场旧帧算的点位会过期
        /// （run 43372118468 的 GAP 违规先按此嫌疑
        /// 排除，再看是否真有命中外溢）
        var makePoint: (_ f: BandFrames) -> CGPoint
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testTopBarSingleActionDispatch() throws {
        var lines: [String] = []
        var violations: [String] = []
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        defer { app.terminate() }

        let avatarEl = app.buttons["topbar.hubAvatarButton"]
        let capsuleEl = app.buttons["topbar.identityCapsule"]
        let drawerEl = app.buttons["drawer.open"]
        let bellEl = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '通知'")
        ).firstMatch
        guard avatarEl.waitForExistence(timeout: 30),
              capsuleEl.waitForExistence(timeout: 10),
              drawerEl.waitForExistence(timeout: 10),
              bellEl.waitForExistence(timeout: 10)
        else {
            emit(["VERDICT=TOPBAR-NOT-UP"])
            XCTFail("顶带四件未在演示装配里出现")
            return
        }
        // §449 删除钉：顶栏模型胶囊与放大镜钮不许在场
        if app.buttons["topbar.modelCapsule"].exists {
            violations.append(
                "已退役的顶栏模型胶囊仍在（topbar.modelCapsule）")
        }
        if app.buttons["topbar.findButton"].exists {
            violations.append(
                "已退役的顶栏放大镜钮仍在（topbar.findButton）")
        }
        let f0 = BandFrames(
            drawer: drawerEl.frame, avatar: avatarEl.frame,
            capsule: capsuleEl.frame, bell: bellEl.frame)
        lines.append(
            "drawer=\(fmt(f0.drawer)) avatar=\(fmt(f0.avatar)) "
                + "capsule=\(fmt(f0.capsule)) bell=\(fmt(f0.bell))")
        // 几何钉（§449.3）：头像命中帧 67；两钮与头
        // 像同带（钮心纵差 ≤14＝设计 7.5＋AX 宽容）；
        // 胶囊压头像下沿（顶边在头像心之下、头像底
        // 之上）；两钮与头像横向不重叠
        // 组版 0.50.116 改钉注记：XCUI 报的 capsule 帧
        // 是胶囊内容帧（钮体恒 44 高、hero 底对齐与头
        // 像底距 36 在 §474/§477/§479 合并中一字未动，
        // 玻璃胶囊本体仍压头像下沿 ≈8）；§474 起空闲
        // 态第二行不呈现，内容由两行（37）变一行（20）、
        // 内容顶随之上移 8，旧「内容顶须压进下沿」口
        // 径改钉为「内容跨下沿带」：顶在头像心之下、
        // 底过头像底、顶距下沿 ≤12（两态实测 −4/+4）
        if abs(f0.avatar.width - 67) > 1.5
            || abs(f0.avatar.height - 67) > 1.5 {
            violations.append(
                "头像命中帧非 67：\(fmt(f0.avatar))")
        }
        if abs(f0.drawer.midY - f0.avatar.midY) > 14 {
            violations.append(
                "汉堡钮心与头像心纵差 >14："
                    + "\(f0.drawer.midY - f0.avatar.midY)")
        }
        if abs(f0.bell.midY - f0.avatar.midY) > 14 {
            violations.append(
                "铃钮心与头像心纵差 >14："
                    + "\(f0.bell.midY - f0.avatar.midY)")
        }
        if !(f0.capsule.minY > f0.avatar.midY
             && f0.capsule.minY < f0.avatar.maxY + 12
             && f0.capsule.maxY > f0.avatar.maxY) {
            violations.append(
                "身份胶囊未压头像下沿：capsule=\(fmt(f0.capsule)) "
                    + "avatar=\(fmt(f0.avatar))")
        }
        if f0.drawer.maxX > f0.avatar.minX
            || f0.bell.minX < f0.avatar.maxX {
            violations.append("两钮与头像横向重叠")
        }
        // 融合元素检查：任一按钮的帧同时盖住头像心
        // 与胶囊心＝两件被单一元素横跨（旧融域形态
        // 的残留特征），出现即违规
        let fused = app.buttons.allElementsBoundByIndex
            .filter {
                $0.frame.contains(CGPoint(
                    x: f0.avatar.midX, y: f0.avatar.midY))
                    && $0.frame.contains(CGPoint(
                        x: f0.capsule.midX, y: f0.capsule.midY))
            }
        if !fused.isEmpty {
            violations.append(
                "存在横跨头像/胶囊双域的融合元素："
                    + "\(fused.map { fmt($0.frame) })")
        }

        let origin = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0))

        for tap in planPoints() {
            // 每点现读实帧现算点位（帧过期排除，见
            // BandFrames 注）
            let f = BandFrames(
                drawer: drawerEl.frame, avatar: avatarEl.frame,
                capsule: capsuleEl.frame, bell: bellEl.frame)
            let point = tap.makePoint(f)
            origin.withOffset(
                CGVector(dx: point.x, dy: point.y)
            ).tap()
            let fired = awaitSurface(app, expect: tap.expect)
            var wrong = false
            switch tap.expect {
            case .hub: wrong = fired != "hub"
            case .drawer: wrong = fired != "drawer"
            case .sheet: wrong = fired != "sheet"
            case .none: wrong = fired != "none"
            }
            if wrong {
                violations.append(
                    "\(tap.name)@(\(Int(point.x)),\(Int(point.y))) "
                        + "fired=\(fired) expect=\(tap.expect)")
            }
            lines.append(
                "tap=\(tap.name) at=(\(Int(point.x)),\(Int(point.y))) "
                    + "expect=\(tap.expect) fired=\(fired) wrong=\(wrong)")
            dismissSurfaces(app)
            settleBand(app, avatarEl: avatarEl)
        }
        lines.append("violations=\(violations.count) "
            + violations.joined(separator: "; "))
        lines.append("VERDICT=" + (violations.isEmpty ? "PASS" : "FAIL"))
        emit(lines)
        if !violations.isEmpty {
            XCTFail("顶带单动作派发有误："
                + violations.joined(separator: "; "))
        }
    }

    /// 枢纽布局回归（2026-11-13，演示目录 61 条生产
    /// 量级）：旧形态把全量目录平铺进不滚动的根列
    /// （模型区约 3,533pt），页头与 ✕ 在真机上不可
    /// 达、rig 却因「只查存在」判绿。本门按改口径后
    /// 的形态逐项验（定案见 hub-tap-misfire-hunt-
    /// self-20261113 与 hub-layout-overflow 报告）：
    /// - 点头像开枢纽：页头 ✕ 与分享钮完整在屏内；
    /// - §434 后枢纽身份头下有「选择模型」入口
    ///   （用户 2026-11-24 亲点恢复，复用聊天页同
    ///   一选择器；旧「无模型入口」口径作废）；
    /// - 枢纽内不存在目录行（抽查目录深处三 id）；
    /// - 段集由注册表动态渲染（§434）：必达＝工作/
    ///   身份（锚格）；审核/电脑/邮箱随能力回读长
    ///   格，演示装配里缺席不算违规、在场则须可达
    ///   且切段后页头不失；末段（身份）内容区可滚
    ///   到底且页头不失。
    func testHubLayoutWithFullCatalog() throws {
        var lines: [String] = []
        var violations: [String] = []
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        defer { app.terminate() }

        let capsuleEl = app.buttons["topbar.identityCapsule"]
        let avatarEl = app.buttons["topbar.hubAvatarButton"]
        guard capsuleEl.waitForExistence(timeout: 30),
              avatarEl.waitForExistence(timeout: 10)
        else {
            emit(["VERDICT=HUB-LAYOUT-NOT-UP"])
            XCTFail("顶簇两元素未在演示装配里出现")
            return
        }
        let win = app.windows.firstMatch.frame

        // 点头像钮中心（与派发门同点法，生产装配）
        let origin = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        )
        let avatarFrame = avatarEl.frame
        origin.withOffset(CGVector(
            dx: avatarFrame.midX, dy: avatarFrame.midY
        )).tap()

        // 枢纽升起判据＝✕ 在屏内出现（在屏语义，见
        // hubCloseButton）；旧溢出形态下 ✕ 永不达标
        var close = hubCloseButton(app)
        let hubDeadline = Date().addingTimeInterval(8)
        while close == nil, Date() < hubDeadline {
            Thread.sleep(forTimeInterval: 0.25)
            close = hubCloseButton(app)
        }
        guard let close else {
            emit(["VERDICT=HUB-LAYOUT-FAIL",
                  "violations=枢纽 ✕ 未在屏内出现（页头疑不可达）"])
            XCTFail("枢纽打开后 ✕ 未在屏内出现")
            return
        }
        lines.append("hubClose=\(fmt(close.frame)) win=\(fmt(win))")

        // 页头另一件：分享钮与 ✕ 同在页头行（ShareLink
        // 在 AX 树里的元素类型不稳定，探针不限类型按标
        // 签查；首轮 CI 实证 app.buttons 查不到它）。
        // 标签须三语并查：该文案在 Localizable.xcstrings
        // 里有正式译文（en "Share agent card"／zh-Hant
        // 「分享智慧代理名片」），CI 为 en 环境时 AX 标
        // 签只剩英文——run 43401214968 唯一违规即栽于
        // 此（shareKin=[]，与「取消→Cancel」同型坑）。
        // 装配 0.50.29 探针稳健化：只动测试、不动产品码
        let shareLabels = ["分享智能体名片", "分享智慧代理名片",
                           "Share agent card"]
        let share = app.descendants(matching: .any).matching(
            NSPredicate(format: "label IN %@", shareLabels)
        ).firstMatch
        if share.waitForExistence(timeout: 5), share.isHittable,
           isFullyOnScreen(share.frame, in: win) {
            lines.append("shareButton=\(fmt(share.frame))")
        } else {
            violations.append("页头分享钮不在屏内")
            // 失败路径诊断：树里带「分享/Share」的标签都长什么样
            let kin = app.descendants(matching: .any).matching(
                NSPredicate(format:
                    "label CONTAINS '分享' OR label CONTAINS[c] 'Share'"))
            var labels: [String] = []
            for i in 0..<min(kin.count, 5) {
                labels.append(kin.element(boundBy: i).label)
            }
            lines.append("shareKin=\(labels)")
        }

        // §434 模型入口（用户 2026-11-24 亲点）：
        // 身份头下、分段条上应有「选择模型」入口，
        // 点开是与聊天页胶囊同一套选择器；旧「枢纽
        // 内无模型入口」断言（结构归位包口径）作废
        let entry = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '选择模型'")
        ).firstMatch
        if entry.waitForExistence(timeout: 5), entry.isHittable {
            lines.append("modelEntry=\\(fmt(entry.frame))")
        } else {
            violations.append("枢纽内缺 §434 选择模型入口")
        }
        // §434 push 全页：底栏应被推页盖住/隐藏
        // （软留痕：环境差异大，只记不断言）
        lines.append("tabBarExistsWhileHubOpen="
            + "\(app.tabBars.firstMatch.exists)")

        // 枢纽内不存在目录行：三 id 只可能以目录行
        // 形态出现在枢纽里（非当前模型、选择面未开）
        for probe in ["dbrx-instruct", "qwen-3-max", "mixtral-8x22b"] {
            let rows = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", probe)
            )
            if rows.count > 0 {
                violations.append(
                    "枢纽内出现目录行 \(probe)×\(rows.count)")
            }
        }


        // §434 注册表段集：锚格（工作/身份）必达；
        // 能力格（审核/电脑/邮箱）随真回读长格——
        // 演示装配缺席不违规，在场则须可达且页头不失
        for name in ["工作", "身份"] {
            let seg = segmentButton(app, name)
            if seg.waitForExistence(timeout: 4), seg.isHittable {
                seg.tap()
                Thread.sleep(forTimeInterval: 0.4)
                if hubCloseButton(app) == nil {
                    violations.append("切到「\(name)」段后页头 ✕ 不在屏内")
                }
            } else {
                violations.append("锚格分段「\(name)」不可达")
            }
        }
        var optionalPresent: [String] = []
        for name in ["审核", "电脑", "邮箱"] {
            let seg = segmentButton(app, name)
            if seg.waitForExistence(timeout: 2), seg.isHittable {
                optionalPresent.append(name)
                seg.tap()
                Thread.sleep(forTimeInterval: 0.4)
                if hubCloseButton(app) == nil {
                    violations.append("切到「\(name)」段后页头 ✕ 不在屏内")
                }
            }
        }
        lines.append("optionalSegmentsPresent="
            + optionalPresent.joined(separator: ","))
        // 回身份段做末段滚动验收（与旧口径同落点）
        let identitySeg = segmentButton(app, "身份")
        if identitySeg.waitForExistence(timeout: 4),
           identitySeg.isHittable {
            identitySeg.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }

        // 末段（身份）内容区滚到底：探针文本（分段
        // 控件下方首个静态文本）帧位移停稳＝到底；
        // 无可滚内容（空态）时位移恒零、同判到底
        var lastY = segmentProbeText(app)?.frame.minY ?? -1
        var stable = 0
        for _ in 0..<12 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.35)
            let y = segmentProbeText(app)?.frame.minY ?? lastY
            if abs(y - lastY) < 1 {
                stable += 1
                if stable >= 2 { break }
            } else {
                stable = 0
            }
            lastY = y
        }
        lines.append("scrollBottom lastProbeY=\(Int(lastY))")
        if hubCloseButton(app) == nil {
            violations.append("末段滚到底后页头 ✕ 不在屏内")
        }

        // 收尾：✕ 关枢纽回聊天
        hubCloseButton(app)?.tap()
        let backDeadline = Date().addingTimeInterval(5)
        while !capsuleEl.isHittable, Date() < backDeadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        if !capsuleEl.isHittable {
            violations.append("✕ 关枢纽后未回到聊天")
        }

        lines.append("violations=\(violations.count) "
            + violations.joined(separator: "; "))
        lines.append("HUB-LAYOUT-VERDICT="
            + (violations.isEmpty ? "PASS" : "FAIL"))
        emit(lines)
        if !violations.isEmpty {
            XCTFail("枢纽布局回归有误："
                + violations.joined(separator: "; "))
        }
    }

    /// 分段控件项查找（segmented 作用域优先，回落
    /// 全局按钮）：段以 Label 标题为无障碍标签
    private func segmentButton(
        _ app: XCUIApplication, _ name: String
    ) -> XCUIElement {
        let scoped = app.segmentedControls.buttons[name]
        if scoped.exists { return scoped }
        return app.buttons[name]
    }

    /// 段内容探针：分段控件下缘以下首个有宽度的静
    /// 态文本（页头文本在控件之上、天然排除）
    private func segmentProbeText(
        _ app: XCUIApplication
    ) -> XCUIElement? {
        let picker = app.segmentedControls.firstMatch
        let floorY = picker.exists ? picker.frame.maxY : 0
        return app.staticTexts.allElementsBoundByIndex.first {
            $0.frame.minY > floorY + 4 && $0.frame.width > 0
        }
    }

    // MARK: - 呈现探测与关闭

    /// 枢纽 ✕ 钮查找（2026-11-13 在屏语义改版）：旧版
    /// 按标签查到「存在」即认——枢纽布局溢出时 ✕ 被
    /// 顶到 y≈−1500 仍 exists、照样判绿（rig 盲区定
    /// 案，见 hub-tap-misfire-hunt-self-20261113）。
    /// 现口径：存在＋可点＋AX 帧完整落在窗口内，三
    /// 者缺一不算找到；回落的几何启发式同样先过在
    /// 屏闸、再看位置/尺寸
    private func hubCloseButton(_ app: XCUIApplication) -> XCUIElement? {
        let win = app.windows.firstMatch.frame
        // 标签支也必须带帧位约束：通知 sheet 里同有
        // 「关闭」钮、无约束时被误认枢纽 ✕（BELL-C
        // fired=hub 实证）；枢纽 ✕ 恒在左上带
        // (16,66 44×44)，与回落支同界
        for label in ["关闭", "Close"] {
            let el = app.buttons[label]
            if el.exists, el.isHittable,
               isFullyOnScreen(el.frame, in: win),
               el.frame.minX < 70, el.frame.minY < 140,
               el.frame.width <= 44, el.frame.width > 0 {
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

    /// 在屏语义：帧非空且四边完整落在窗口内（1pt 容差）
    private func isFullyOnScreen(
        _ frame: CGRect, in win: CGRect
    ) -> Bool {
        frame.width > 0 && frame.height > 0
            && frame.minX >= win.minX - 1 && frame.minY >= win.minY - 1
            && frame.maxX <= win.maxX + 1 && frame.maxY <= win.maxY + 1
    }

    /// 带面落定等待：呈现往返（尤其抽屉关闭动画）
    /// 后前景帧仍在移动，按静止帧算的下一点位会打
    /// 空（BELL-C 首跑实证）——头像帧连续两读不变
    /// 才算落定，上限 4s
    private func settleBand(
        _ app: XCUIApplication, avatarEl: XCUIElement
    ) {
        var last = avatarEl.frame
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
            let now = avatarEl.frame
            if now == last { return }
            last = now
        }
    }

    /// 抽屉行（任一可命中的会话行＝抽屉已开的信
    /// 号；抽屉关时行在屏外、不可命中）
    private func drawerRow(
        _ app: XCUIApplication
    ) -> XCUIElement? {
        let rows = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'drawer.row.'"))
        return rows.allElementsBoundByIndex.first {
            $0.isHittable
        }
    }

    /// 通知 sheet 在场判据：sheet 容器在场＋枢纽 ✕
    /// 不在屏＋抽屉行不可命中（三者合取排除 push/
    /// 抽屉两态的误认）。不用「胶囊被盖」作条件：
    /// iOS 26 sheet 下底层元素 AX 仍报可命中，该条
    /// 件永假（BELL-C 两跑实证：sheet 实际已升、信
    /// 号却判 none）；sheet 内容在演示态可能为空、
    /// 亦不以标题文本为据
    private func notificationSheet(
        _ app: XCUIApplication
    ) -> Bool {
        // iOS 26 下本 sheet 在 AX 里不以 .sheet 类型
        // 出现（铃诊断实证：sheets=0 而通知面全文在
        // 树）——信号改以面标题静态文本为准
        app.staticTexts["通知"].exists
            && hubCloseButton(app) == nil
            && drawerRow(app) == nil
    }

    /// 等待并判定升起的面：hub（枢纽 ✕ 在屏且身份
    /// 胶囊被盖）／drawer（抽屉行可命中）／sheet
    /// （通知 sheet 在场）／none
    private func awaitSurface(
        _ app: XCUIApplication, expect: Expect
    ) -> String {
        let capsuleEl = app.buttons["topbar.identityCapsule"]
        let deadline = Date().addingTimeInterval(
            expect == .none ? 1.8 : 6
        )
        while Date() < deadline {
            if !capsuleEl.isHittable, hubCloseButton(app) != nil {
                return "hub"
            }
            if drawerRow(app) != nil { return "drawer" }
            if notificationSheet(app) { return "sheet" }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if !capsuleEl.isHittable, hubCloseButton(app) != nil {
            return "hub"
        }
        if drawerRow(app) != nil { return "drawer" }
        if notificationSheet(app) { return "sheet" }
        return "none"
    }

    private func dismissSurfaces(_ app: XCUIApplication) {
        let capsuleEl = app.buttons["topbar.identityCapsule"]
        // 枢纽：点页头 ✕（生产自带关闭口）
        if !capsuleEl.isHittable, let close = hubCloseButton(app) {
            close.tap()
            let deadline = Date().addingTimeInterval(5)
            while !capsuleEl.isHittable, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        // 抽屉：点露出窄条关闭（容器自带关闭口，
        // ContentView 沿革「点露出窄条关」）。不点
        // 会话行：演示态首行是频道行、点它跳服务器
        // 会话页回不到主聊天（BELLSEQ 诊断实证、
        // BELL-C 三跑连挂的真因）；窄条点不通时退
        // 左拖页卡跟手关
        if drawerRow(app) != nil {
            let win = app.windows.firstMatch.frame
            let origin = app.windows.firstMatch.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0))
            origin.withOffset(CGVector(
                dx: win.width * 0.93, dy: win.height * 0.5)).tap()
            var deadline = Date().addingTimeInterval(3)
            while drawerRow(app) != nil, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
            }
            if drawerRow(app) != nil {
                let start = origin.withOffset(CGVector(
                    dx: win.width * 0.75, dy: win.height * 0.5))
                let end = origin.withOffset(CGVector(
                    dx: win.width * 0.2, dy: win.height * 0.5))
                start.press(forDuration: 0.1, thenDragTo: end)
                deadline = Date().addingTimeInterval(5)
                while drawerRow(app) != nil, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.25)
                }
            }
        }
        // 通知 sheet：手势下滑消散（生产 sheet 无关
        // 闭禁令；AX 里无 .sheet 元素可 swipe、改窗
        // 口坐标拖拽，铃诊断定版）
        if notificationSheet(app) {
            let start = app.windows.firstMatch.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let end = app.windows.firstMatch.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            start.press(forDuration: 0.1, thenDragTo: end)
            let deadline = Date().addingTimeInterval(4)
            while notificationSheet(app), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
    }

    // MARK: - 点位计划（预注册）

    private func planPoints() -> [TapPoint] {
        [
            TapPoint(name: "AVA-C", expect: .hub) { f in
                CGPoint(x: f.avatar.midX, y: f.avatar.midY)
            },
            TapPoint(name: "AVA-L", expect: .hub) { f in
                CGPoint(x: f.avatar.minX + 5, y: f.avatar.midY)
            },
            TapPoint(name: "AVA-R", expect: .hub) { f in
                CGPoint(x: f.avatar.maxX - 5, y: f.avatar.midY)
            },
            TapPoint(name: "AVA-T", expect: .hub) { f in
                CGPoint(x: f.avatar.midX, y: f.avatar.minY + 5)
            },
            // 头像底缘内点避开胶囊压叠区（胶囊顶在头
            // 像底上方 ≈8pt），取底上 12
            TapPoint(name: "AVA-B", expect: .hub) { f in
                CGPoint(x: f.avatar.midX, y: f.avatar.maxY - 12)
            },
            TapPoint(name: "CAP-C", expect: .hub) { f in
                CGPoint(x: f.capsule.midX, y: f.capsule.midY)
            },
            TapPoint(name: "CAP-L", expect: .hub) { f in
                CGPoint(x: f.capsule.minX + 6, y: f.capsule.midY)
            },
            TapPoint(name: "CAP-R", expect: .hub) { f in
                CGPoint(x: f.capsule.maxX - 6, y: f.capsule.midY)
            },
            TapPoint(name: "DRAWER-C", expect: .drawer) { f in
                CGPoint(x: f.drawer.midX, y: f.drawer.midY)
            },
            TapPoint(name: "BELL-C", expect: .sheet) { f in
                CGPoint(x: f.bell.midX, y: f.bell.midY)
            },
            // 死带：钮与头像同带的横向间隙中点（左
            // 右）与头像顶上——命中域互不融接的构造
            // 判据，任何面都不许升
            TapPoint(name: "GAP-L", expect: .none) { f in
                CGPoint(
                    x: (f.drawer.maxX + f.avatar.minX) / 2,
                    y: f.avatar.midY)
            },
            TapPoint(name: "GAP-R", expect: .none) { f in
                CGPoint(
                    x: (f.avatar.maxX + f.bell.minX) / 2,
                    y: f.avatar.midY)
            },
            TapPoint(name: "GAP-TOP", expect: .none) { f in
                CGPoint(x: f.avatar.midX, y: f.avatar.minY - 6)
            },
        ]
    }

    private func fmt(_ rect: CGRect) -> String {
        String(
            format: "(%.0f,%.0f %.0f×%.0f)",
            rect.minX, rect.minY, rect.width, rect.height
        )
    }

    private func emit(_ lines: [String]) {
        let text = lines.joined(separator: "\n")
        print("TOPBAR-TAP-BEGIN")
        print(text)
        print("TOPBAR-TAP-END")
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
