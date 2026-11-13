import XCTest

/// §202 动作级点按派发验证（XCUITest，路线 B）
///
/// 前身 CapsuleTapDispatchUITests 绑的是已退役的
/// 实验台装配（-CapsuleTapHarness＋safeAreaBar 复
/// 刻顶栏）——与生产托管链不同构，随双动作胶囊
/// 一并退役。本组改打**真 App 生产装配**：启动参
/// 数 -odDemoMode 直达已连接态（RootView→Drawer-
/// Container→TabView→ChatView→TopBarGuideHost 托
/// 管的真实顶簇），按无障碍标识读两元素实帧、逐
/// 点系统级点按，以真实呈现（模型 sheet／枢纽
/// cover）的升起判派发。
///
/// 点位与判定（预注册）：
/// - 胶囊域内点（中心/左右内缩 6/上下缘内 3）：
///   必须只升模型面；升枢纽或不升＝派错。
/// - 头像钮域内点（中心/四向内缩 5）：必须只升
///   枢纽；升模型面或不升＝派错。
/// - 间隙点（两元素帧间中点）：两面都不许升。
/// 关闭路径：模型面下拉拖拽消散、枢纽点其页头
/// ✕ 钮——都走生产自带关闭口，不借探针。
///
/// 结构断言同在本门（§202.6 整合）：进程内结
/// 构门 TopBarClusterHitDomainTests 六轮全灭
/// （生产装配页进程内查无障碍元素与 §184 进程
/// 死亡族同签名；作用域改顶栏宿主子树后又证实
/// 平台子视图遍历根本够不到宿主内的 SwiftUI
/// 元素），间隔/命中盘宽/无融合元素三项结构事
/// 实改在本门以同一份实帧判（开场违规项）；玻
/// 璃不跨双域由构造（玻璃只在胶囊标签背景层、
/// 头像钮无玻璃）＋本门归属全对共同证明。间隙
/// 判点＝死带三点（中点 ±2，§202.6 定界）。
final class TopBarSingleActionTapTests: XCTestCase {

    private enum Expect { case model, hub, none }

    private struct TapPoint {
        var name: String
        var expect: Expect
        /// 点位现算：每点开点前重读两元素实帧再落点
        /// ——关面兜底若换过模型，胶囊标签宽度会变、
        /// 左缘随之移位，按开场旧帧算的点位会过期
        /// （run 43372118468 的 GAP 违规先按此嫌疑
        /// 排除，再看是否真有命中外溢）
        var makePoint: (_ capsule: CGRect, _ avatar: CGRect) -> CGPoint
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

        let capsuleEl = app.buttons["topbar.modelCapsule"]
        let avatarEl = app.buttons["topbar.hubAvatarButton"]
        guard capsuleEl.waitForExistence(timeout: 30),
              avatarEl.waitForExistence(timeout: 10)
        else {
            emit(["VERDICT=TOPBAR-NOT-UP"])
            XCTFail("顶簇两元素未在演示装配里出现")
            return
        }
        lines.append(
            "capsule=\(fmt(capsuleEl.frame)) avatar=\(fmt(avatarEl.frame)) "
                + "gap=\(capsuleEl.frame.minX - avatarEl.frame.maxX)"
        )
        if capsuleEl.frame.minX - avatarEl.frame.maxX < 7.5 {
            violations.append("两元素间隔 <8pt")
        }
        if abs(avatarEl.frame.width - 44) > 1 {
            violations.append(
                "头像钮命中盘宽非 44：\(avatarEl.frame.width)")
        }
        // 融合元素检查：任一按钮的帧同时盖住两元
        // 素中心＝双域被单一元素横跨（旧融域形态
        // 的残留特征），出现即违规
        let fused = app.buttons.allElementsBoundByIndex
            .filter {
                $0.frame.contains(CGPoint(
                    x: capsuleEl.frame.midX,
                    y: capsuleEl.frame.midY))
                    && $0.frame.contains(CGPoint(
                        x: avatarEl.frame.midX,
                        y: avatarEl.frame.midY))
            }
        if !fused.isEmpty {
            violations.append(
                "存在横跨双域的融合元素："
                    + "\(fused.map { fmt($0.frame) })")
        }

        let origin = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        )

        for tap in planPoints() {
            // 每点现读实帧现算点位（帧过期排除，见
            // TapPoint.makePoint 注）
            let capsule = capsuleEl.frame
            let avatar = avatarEl.frame
            let point = tap.makePoint(capsule, avatar)
            origin.withOffset(
                CGVector(dx: point.x, dy: point.y)
            ).tap()
            let fired = awaitSurface(app, expect: tap.expect)
            var wrong = false
            switch tap.expect {
            case .model: wrong = fired != "model"
            case .hub: wrong = fired != "hub"
            case .none: wrong = fired != "none"
            }
            if wrong {
                violations.append(
                    "\(tap.name)@(\(Int(point.x)),\(Int(point.y))) "
                        + "fired=\(fired) expect=\(tap.expect)"
                )
            }
            lines.append(
                "tap=\(tap.name) at=(\(Int(point.x)),\(Int(point.y))) "
                    + "frames=capsule:\(fmt(capsule))/avatar:\(fmt(avatar)) "
                    + "expect=\(tap.expect) fired=\(fired) wrong=\(wrong)"
            )
            dismissSurfaces(app)
        }
        lines.append("violations=\(violations.count) "
            + violations.joined(separator: "; "))
        lines.append("VERDICT=" + (violations.isEmpty ? "PASS" : "FAIL"))
        emit(lines)
        if !violations.isEmpty {
            XCTFail("顶簇单动作派发有误："
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
    /// - 模型单行入口（当前模型名＋chevron）在屏内
    ///   且可点，点开的是正牌模型选择面；
    /// - 枢纽内不存在目录行（抽查目录深处三 id）；
    /// - 七段逐段可达、每次切段后页头仍在屏内；末
    ///   段（身份）内容区可滚到底且页头不失。
    func testHubLayoutWithFullCatalog() throws {
        var lines: [String] = []
        var violations: [String] = []
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        defer { app.terminate() }

        let capsuleEl = app.buttons["topbar.modelCapsule"]
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

        // 模型单行入口在屏内
        let entry = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '会话模型：'")
        ).firstMatch
        if entry.waitForExistence(timeout: 5), entry.isHittable,
           isFullyOnScreen(entry.frame, in: win) {
            lines.append(
                "modelEntry=\(fmt(entry.frame)) label=\(entry.label)")
        } else {
            violations.append("模型单行入口不在屏内或不可点")
        }

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

        // 入口点开正牌选择面（以探针行 deepseek-v4-
        // pro 在面内出现为据，与派发门口径同源）
        if entry.exists, entry.isHittable {
            entry.tap()
            if modelRow(app).waitForExistence(timeout: 6) {
                lines.append("picker=open via hub entry")
                // 关面：取消钮（本环境本地化串解析为英
                // 文 Cancel——首轮 CI 树扫描实证；双标
                // 签都试）→ 兜底点当前模型行（选中即关
                // 面、同模型重选无副作用）
                var closed = false
                for label in ["取消", "Cancel"] {
                    let cancel = app.buttons[label]
                    if cancel.exists, cancel.isHittable {
                        cancel.tap()
                        break
                    }
                }
                var deadline = Date().addingTimeInterval(8)
                while Date() < deadline {
                    if !modelRow(app).exists { closed = true; break }
                    Thread.sleep(forTimeInterval: 0.25)
                }
                if !closed {
                    let current = app.buttons.matching(
                        NSPredicate(format:
                            "label CONTAINS[c] 'deepseek-flash'"
                            + " AND label CONTAINS 'Via gateway'")
                    ).firstMatch
                    if current.exists, current.isHittable {
                        current.tap()
                        deadline = Date().addingTimeInterval(8)
                        while Date() < deadline {
                            if !modelRow(app).exists {
                                closed = true
                                break
                            }
                            Thread.sleep(forTimeInterval: 0.25)
                        }
                    }
                }
                if !closed {
                    violations.append("选择面关不掉")
                }
                if hubCloseButton(app) == nil {
                    violations.append("关选择面后枢纽页头 ✕ 不在屏内")
                }
            } else {
                violations.append("模型入口未打开选择面")
            }
        }

        // 七段逐段可达＋切段后页头不失
        for name in ["活动", "任务", "审核", "浏览器",
                     "定时", "监测", "身份"] {
            let seg = segmentButton(app, name)
            if seg.waitForExistence(timeout: 4), seg.isHittable {
                seg.tap()
                Thread.sleep(forTimeInterval: 0.4)
                if hubCloseButton(app) == nil {
                    violations.append("切到「\(name)」段后页头 ✕ 不在屏内")
                }
            } else {
                violations.append("分段「\(name)」不可达")
            }
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

    private func modelRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'deepseek-v4-pro'")
        ).firstMatch
    }

    /// 枢纽 ✕ 钮查找（2026-11-13 在屏语义改版）：旧版
    /// 按标签查到「存在」即认——枢纽布局溢出时 ✕ 被
    /// 顶到 y≈−1500 仍 exists、照样判绿（rig 盲区定
    /// 案，见 hub-tap-misfire-hunt-self-20261113）。
    /// 现口径：存在＋可点＋AX 帧完整落在窗口内，三
    /// 者缺一不算找到；回落的几何启发式同样先过在
    /// 屏闸、再看位置/尺寸
    private func hubCloseButton(_ app: XCUIApplication) -> XCUIElement? {
        let win = app.windows.firstMatch.frame
        for label in ["关闭", "Close"] {
            let el = app.buttons[label]
            if el.exists, el.isHittable,
               isFullyOnScreen(el.frame, in: win) {
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

    /// 等待并判定升起的面：model（模型行出现）／
    /// hub（胶囊被盖住且枢纽 ✕ 钮出现）／none
    private func awaitSurface(
        _ app: XCUIApplication, expect: Expect
    ) -> String {
        let capsuleEl = app.buttons["topbar.modelCapsule"]
        let deadline = Date().addingTimeInterval(
            expect == .none ? 1.8 : 6
        )
        while Date() < deadline {
            if modelRow(app).exists { return "model" }
            if !capsuleEl.isHittable, hubCloseButton(app) != nil {
                return "hub"
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if modelRow(app).exists { return "model" }
        if !capsuleEl.isHittable, hubCloseButton(app) != nil {
            return "hub"
        }
        return "none"
    }

    private func dismissSurfaces(_ app: XCUIApplication) {
        let capsuleEl = app.buttons["topbar.modelCapsule"]
        if modelRow(app).exists {
            // 模型面关闭一：sheet 元素下滑消散（生产
            // sheet 无 interactiveDismissDisabled）
            let sheet = app.sheets.firstMatch
            if sheet.exists {
                sheet.swipeDown()
                let deadline = Date().addingTimeInterval(4)
                while modelRow(app).exists, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.25)
                }
            }
            // 关闭二（兜底）：点「当前已选行」关面
            // （点行即落账关面；选当前行不换模型——
            // 换模型会改胶囊标签宽度、令后续点位帧
            // 过期；按可命中过滤，防误认被盖住的胶
            // 囊钮——其标签同含模型名）
            if modelRow(app).exists {
                let row = app.buttons.matching(
                    NSPredicate(
                        format: "label CONTAINS[c] 'deepseek'"
                    )
                ).allElementsBoundByIndex.first {
                    $0.isHittable && $0.isSelected
                }
                row?.tap()
                let deadline = Date().addingTimeInterval(4)
                while modelRow(app).exists, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.25)
                }
            }
        }
        if !capsuleEl.isHittable, let close = hubCloseButton(app) {
            close.tap()
            let deadline = Date().addingTimeInterval(5)
            while !capsuleEl.isHittable, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
    }

    // MARK: - 点位计划（预注册）

    private func planPoints() -> [TapPoint] {
        [
            TapPoint(name: "CAP-C", expect: .model) { c, _ in
                CGPoint(x: c.midX, y: c.midY)
            },
            TapPoint(name: "CAP-L", expect: .model) { c, _ in
                CGPoint(x: c.minX + 6, y: c.midY)
            },
            TapPoint(name: "CAP-R", expect: .model) { c, _ in
                CGPoint(x: c.maxX - 6, y: c.midY)
            },
            TapPoint(name: "CAP-T", expect: .model) { c, _ in
                CGPoint(x: c.midX, y: c.minY + 3)
            },
            TapPoint(name: "CAP-B", expect: .model) { c, _ in
                CGPoint(x: c.midX, y: c.maxY - 3)
            },
            TapPoint(name: "AVA-C", expect: .hub) { _, a in
                CGPoint(x: a.midX, y: a.midY)
            },
            TapPoint(name: "AVA-L", expect: .hub) { _, a in
                CGPoint(x: a.minX + 5, y: a.midY)
            },
            TapPoint(name: "AVA-R", expect: .hub) { _, a in
                CGPoint(x: a.maxX - 5, y: a.midY)
            },
            TapPoint(name: "AVA-T", expect: .hub) { _, a in
                CGPoint(x: a.midX, y: a.minY + 5)
            },
            TapPoint(name: "AVA-B", expect: .hub) { _, a in
                CGPoint(x: a.midX, y: a.maxY - 5)
            },
            TapPoint(name: "GAP", expect: .none) { c, a in
                CGPoint(x: (a.maxX + c.minX) / 2, y: c.midY)
            },
            // 死带探针（§202.6）：run 43378398732
            // 边界点已定界——两钮命中域比无障碍帧
            // 外扩约 4pt（平台宽容），属各钮自身的
            // 宽容带、与相邻域无关，不作违规点；本
            // 组只守 16pt 间隔中央死带（中点 ±2），
            // 三点两面都不许升
            TapPoint(name: "DEAD-L", expect: .none) { c, a in
                CGPoint(x: (a.maxX + c.minX) / 2 - 2, y: c.midY)
            },
            TapPoint(name: "DEAD-R", expect: .none) { c, a in
                CGPoint(x: (a.maxX + c.minX) / 2 + 2, y: c.midY)
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
