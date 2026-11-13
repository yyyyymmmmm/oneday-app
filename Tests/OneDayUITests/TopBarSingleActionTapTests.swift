import XCTest

/// §198 动作级点按派发验证（XCUITest，路线 B）
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
