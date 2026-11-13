import XCTest

/// A5 拖动条·跨宿主有效性先验（评审合成条目 5，
/// 2026-11-13）：`.scrollDismissesKeyboard(.inter-
/// actively)`（＝UIScrollView.keyboardDismissMode
/// =.interactive 的 SwiftUI 面）在本承载（SwiftUI
/// 列表＋UIKit 宿主内 UITextView 第一响应者）下是
/// 否真能跨界触发——真 App 真点拖验证：
/// - 聚焦升键盘后，在消息区做一次缓慢下拖（内容
///   下行方向）：交互式收起应让键盘跟手下行；
/// - 拖过阈值松手：键盘应完全收起。
/// 本门只验拖动条（点空白条由落点矩阵门承担，两
/// 条交互自评审合成起分开成案）。若本门红：产品
/// 侧须上手动桥接降级案（滚动位移观察＋阈值
/// resign），不得以「已设 .interactively」交差。
final class KeyboardDragDismissTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInteractiveDragDismissAcrossHosts() throws {
        var lines: [String] = []
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        defer { app.terminate() }

        let capsule = app.buttons["topbar.modelCapsule"]
        guard capsule.waitForExistence(timeout: 30) else {
            XCTFail("演示装配聊天页未起来")
            return
        }
        let win = app.windows.firstMatch.frame

        // 聚焦升键盘（与矩阵门同一入口）
        let texts = app.textViews.allElementsBoundByIndex
        guard let composer = texts.first(where: {
            $0.frame.minY > win.height - 320 && $0.frame.width > 150
        }) else {
            XCTFail("输入舱文本视图未找到")
            return
        }
        composer.tap()
        guard app.keyboards.firstMatch
            .waitForExistence(timeout: 8) else {
            XCTFail("键盘未升起，拖动条无从验起")
            return
        }
        let kbFrame0 = app.keyboards.firstMatch.frame
        lines.append("kbUp top=\(Int(kbFrame0.minY))")

        // 主臂：左缘页边距带起点（x=10，行容器的内
        // 边距区、无文本视图）缓慢下拖——这是 dis-
        // missMode 自己的契约面（滚动视图 pan 驱动）
        func dragArm(
            x: CGFloat, label: String
        ) -> (followed: Bool, dismissed: Bool) {
            func point(_ y: CGFloat) -> XCUICoordinate {
                app.windows.firstMatch.coordinate(
                    withNormalizedOffset: CGVector(dx: 0, dy: 0)
                ).withOffset(CGVector(dx: x, dy: y))
            }
            point(380).press(
                forDuration: 0.15, thenDragTo: point(540),
                withVelocity: .slow,
                thenHoldForDuration: 0.6
            )
            let kb = app.keyboards.firstMatch
            let top = kb.exists ? kb.frame.minY : -1
            let followed = top > kbFrame0.minY + 30
            lines.append(
                "\(label) midTop=\(Int(top)) followed=\(followed)"
            )
            point(540).press(
                forDuration: 0.1, thenDragTo: point(700),
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            Thread.sleep(forTimeInterval: 1.2)
            let dismissed = !app.keyboards.firstMatch.exists
            lines.append("\(label) dismissed=\(dismissed)")
            return (followed, dismissed)
        }
        let edge = dragArm(x: 10, label: "edgeArm")
        var center: (followed: Bool, dismissed: Bool)?
        if !edge.dismissed {
            // 记录臂：中央文字起点（首轮实测此起点键
            // 盘纹丝不动——疑触摸被文本视图自家手势
            // 吸收；本臂只记录、不作门）
            if !app.keyboards.firstMatch.exists {
                composer.tap()
                _ = app.keyboards.firstMatch
                    .waitForExistence(timeout: 8)
            }
            center = dragArm(x: win.midX, label: "centerArm")
        }
        lines.append(
            "centerArm="
                + (center.map {
                    "followed=\($0.followed) dismissed=\($0.dismissed)"
                } ?? "skipped")
        )
        let dismissed = edge.dismissed

        let text = lines.joined(separator: "\n")
        print("DRAG-DISMISS-BEGIN")
        print(text)
        print("DRAG-DISMISS-END")
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(
            edge.followed,
            "左缘拖动中键盘未跟手下行"
                + "——.interactively 在本承载下未跨界生效，"
                + "须走手动桥接降级案"
        )
        XCTAssertTrue(
            dismissed,
            "拖过阈值松手后键盘未收起——交互式收起未完成"
        )
    }
}
