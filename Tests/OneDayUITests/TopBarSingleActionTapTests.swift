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

    // MARK: - 呈现探测与关闭

    private func modelRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'deepseek-v4-pro'")
        ).firstMatch
    }

    private func hubCloseButton(_ app: XCUIApplication) -> XCUIElement? {
        for label in ["关闭", "Close"] {
            let el = app.buttons[label]
            if el.exists { return el }
        }
        return app.buttons.allElementsBoundByIndex.first {
            $0.exists && $0.frame.minX < 70 && $0.frame.minY < 140
                && $0.frame.width <= 44 && $0.frame.width > 0
        }
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
