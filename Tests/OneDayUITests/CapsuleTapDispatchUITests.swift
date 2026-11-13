import XCTest

/// 症二阶段二·胶囊动作级点按派发验证（XCUITest，
/// 2026-11-12）
///
/// 阶段一 hitTest 结构扫描给不出动作归属；宿主内自
/// 造 UIEvent 投递两轮实证到不了 SwiftUI 按钮
/// machinery（诊断数据见 TAP-DISPATCH-DATA），本组
/// 改走系统级真实点按：被测 App 以 DEBUG 启动参数
/// -CapsuleTapHarness 直达实验装配（根宿主→
/// DrawerContainer→TabView→safeAreaBar 顶栏，与
/// 生产同深度），XCUITest 按无障碍树实读帧逐点点
/// 按，以探针面（枢纽 cover／模型 sheet 替身）的
/// 实际升起记录派发结果。
///
/// 点位与判定（预注册、与宿主台同口径）：
/// - 校准点：内容区普通钮——不响＝仪表门未过、整组
///   作废（与派发结论分开记）。
/// - 域内点：某钮帧内（x 内缩 ≥2pt）、胶囊中带行
///   ——必须只升该面；升对侧或不升＝派错。
/// - 缘带点：胶囊上/下缘带、x 在某钮域内——升对侧
///   面或不升可记，升错侧＝派错（症状高发带）。
/// - 缝点/衬垫带点：只记录、无预设对错。
/// C 臂（官方定式）绑阶段门；P 臂（生产现行形态）
/// 只记录。
final class CapsuleTapDispatchUITests: XCTestCase {

    private enum Zone {
        case domainHub, domainModel, edgeHub, edgeModel, record
    }

    private struct TapPoint {
        var name: String
        var point: CGPoint
        var zone: Zone
    }

    override func setUpWithError() throws {
        // 逐点收集成表、末尾统一判门，单点异常不中断
        continueAfterFailure = true
    }

    // MARK: - 两臂

    func testOfficialPatternDispatch_StageGate() throws {
        let result = runArm(official: true)
        emit(result.lines)
        if !result.violations.isEmpty {
            XCTFail(
                "官方定式动作级派发有误："
                    + result.violations.joined(separator: "; ")
            )
        }
    }

    func testCurrentProductionDispatch_Record() throws {
        let result = runArm(official: false)
        emit(result.lines)
    }

    // MARK: - 执行

    private func runArm(
        official: Bool
    ) -> (lines: [String], violations: [String]) {
        let armName = official ? "C-official" : "P-current"
        var lines: [String] = []
        var violations: [String] = []
        let app = XCUIApplication()
        app.launchArguments = ["-CapsuleTapHarness"]
            + (official ? ["-CapsuleArmC"] : [])
        app.launch()
        defer { app.terminate() }

        let capsuleEl = app.otherElements["harness.capsule"]
        let calibButton = app.buttons["harness.calibration"]
        guard capsuleEl.waitForExistence(timeout: 20),
              calibButton.waitForExistence(timeout: 10)
        else {
            lines.append("arm=\(armName) VERDICT=HARNESS-NOT-UP")
            return (lines, ["实验台未起"])
        }

        // 仪表门：校准钮先响
        calibButton.tap()
        let calibrated = app.staticTexts["harness.calibrationOK"]
            .waitForExistence(timeout: 3)
        lines.append("arm=\(armName) calibration ok=\(calibrated)")
        guard calibrated else {
            lines.append("arm=\(armName) VERDICT=INSTRUMENT-FAIL")
            return (lines, ["仪表门未过"])
        }

        // 两钮帧：C 臂按标识；P 臂按几何（生产枢纽钮
        // 标签经 App 三语本地化在无障碍树里是英文
        // "Hermes, 在线, open Hub"，文本匹配与语言绑
        // 定不可靠——胶囊槽内中心落槽、按 minX 序取
        // 两钮，语言无关）
        let capsule = capsuleEl.frame
        let hubEl: XCUIElement
        let modelEl: XCUIElement
        if official {
            hubEl = app.buttons["harness.hubButton"]
            modelEl = app.buttons["harness.modelButton"]
            guard hubEl.waitForExistence(timeout: 10),
                  modelEl.waitForExistence(timeout: 10)
            else {
                lines.append("arm=\(armName) VERDICT=FRAMES-NOT-FOUND")
                return (lines, ["两钮元素未找到"])
            }
        } else {
            let inner = app.buttons.allElementsBoundByIndex
                .filter { element in
                    element.exists && capsule.contains(
                        CGPoint(x: element.frame.midX, y: element.frame.midY)
                    )
                }
                .sorted { $0.frame.minX < $1.frame.minX }
            guard inner.count == 2 else {
                lines.append("arm=\(armName) VERDICT=FRAMES-NOT-FOUND")
                print("CAPSULE-TREE-BEGIN")
                print(app.debugDescription)
                print("CAPSULE-TREE-END")
                return (lines, ["两钮元素未找到"])
            }
            hubEl = inner[0]
            modelEl = inner[1]
        }
        let hub = hubEl.frame
        let model = modelEl.frame
        lines.append(
            "arm=\(armName) capsule=\(fmt(capsule)) hub=\(fmt(hub)) "
                + "model=\(fmt(model))"
        )

        let hubProbe = app.staticTexts["probe.hubCover"]
        let modelProbe = app.staticTexts["probe.modelSheet"]
        let origin = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        )

        for tap in planPoints(capsule: capsule, hub: hub, model: model) {
            origin.withOffset(
                CGVector(dx: tap.point.x, dy: tap.point.y)
            ).tap()
            Thread.sleep(forTimeInterval: 1.1)
            // 迟现兜底：两面都未升时再轮询一小段，防动
            // 画慢被误记为无触发
            if !hubProbe.exists, !modelProbe.exists {
                for _ in 0..<6 {
                    Thread.sleep(forTimeInterval: 0.25)
                    if hubProbe.exists || modelProbe.exists { break }
                }
            }
            let hubUp = hubProbe.exists
            let modelUp = modelProbe.exists
            let fired = hubUp && modelUp
                ? "both"
                : hubUp ? "hub" : modelUp ? "model" : "none"
            var wrong = false
            switch tap.zone {
            case .domainHub: wrong = fired != "hub"
            case .domainModel: wrong = fired != "model"
            case .edgeHub: wrong = fired == "model" || fired == "both"
            case .edgeModel: wrong = fired == "hub" || fired == "both"
            case .record: wrong = false
            }
            if wrong {
                violations.append(
                    "\(tap.name)@(\(Int(tap.point.x)),\(Int(tap.point.y))) "
                        + "fired=\(fired)"
                )
            }
            lines.append(
                "arm=\(armName) tap=\(tap.name) "
                    + "at=(\(Int(tap.point.x)),\(Int(tap.point.y))) "
                    + "zone=\(tap.zone) fired=\(fired) wrong=\(wrong)"
            )
            if hubUp || modelUp {
                app.buttons["probe.dismiss"].tap()
                let deadline = Date().addingTimeInterval(3)
                while (hubProbe.exists || modelProbe.exists),
                      Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
        }
        lines.append(
            "arm=\(armName) violations=\(violations.count) "
                + violations.joined(separator: "; ")
        )
        lines.append(
            "arm=\(armName) VERDICT="
                + (violations.isEmpty ? "PASS" : "FAIL")
        )
        return (lines, violations)
    }

    // MARK: - 点位计划（预注册）

    private func planPoints(
        capsule: CGRect, hub: CGRect, model: CGRect
    ) -> [TapPoint] {
        let divider = (hub.maxX + model.minX) / 2
        let midY = capsule.midY
        var points: [TapPoint] = [
            TapPoint(
                name: "HUB-C", point: CGPoint(x: hub.midX, y: midY),
                zone: .domainHub
            ),
            TapPoint(
                name: "MOD-C", point: CGPoint(x: model.midX, y: midY),
                zone: .domainModel
            ),
            TapPoint(
                name: "HUB-IN", point: CGPoint(x: hub.maxX - 6, y: midY),
                zone: .domainHub
            ),
            TapPoint(
                name: "MOD-IN", point: CGPoint(x: model.minX + 6, y: midY),
                zone: .domainModel
            ),
            TapPoint(
                name: "HUB-T",
                point: CGPoint(x: hub.midX, y: capsule.minY + 2),
                zone: .edgeHub
            ),
            TapPoint(
                name: "MOD-T",
                point: CGPoint(x: model.midX, y: capsule.minY + 2),
                zone: .edgeModel
            ),
            TapPoint(
                name: "HUB-B",
                point: CGPoint(x: hub.midX, y: capsule.maxY - 2),
                zone: .edgeHub
            ),
            TapPoint(
                name: "MOD-B",
                point: CGPoint(x: model.midX, y: capsule.maxY - 2),
                zone: .edgeModel
            ),
        ]
        // 缝点：按实测帧归类——落进某钮帧（内缩 2pt）
        // 的按域内点判，落在开缝里的只记录
        for (label, x) in [
            ("GAP-3L", divider - 3), ("GAP-3R", divider + 3),
            ("GAP-6L", divider - 6), ("GAP-6R", divider + 6),
        ] {
            let zone: Zone
            if x >= hub.minX + 2, x <= hub.maxX - 2 {
                zone = .domainHub
            } else if x >= model.minX + 2, x <= model.maxX - 2 {
                zone = .domainModel
            } else {
                zone = .record
            }
            points.append(TapPoint(
                name: label, point: CGPoint(x: x, y: midY), zone: zone
            ))
        }
        points.append(TapPoint(
            name: "TOP-DIV",
            point: CGPoint(x: divider, y: capsule.minY + 2),
            zone: .record
        ))
        points.append(TapPoint(
            name: "PAD-H",
            point: CGPoint(x: hub.midX, y: capsule.minY - 5),
            zone: .record
        ))
        points.append(TapPoint(
            name: "PAD-M",
            point: CGPoint(x: model.midX, y: capsule.minY - 5),
            zone: .record
        ))
        return points
    }

    private func fmt(_ rect: CGRect) -> String {
        String(
            format: "(%.0f,%.0f %.0f×%.0f)",
            rect.minX, rect.minY, rect.width, rect.height
        )
    }

    private func emit(_ lines: [String]) {
        let text = lines.joined(separator: "\n")
        print("CAPSULE-TAP-BEGIN")
        print(text)
        print("CAPSULE-TAP-END")
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
