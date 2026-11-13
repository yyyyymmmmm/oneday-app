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

        // 缓慢下拖：从列表中段按下、停顿、拖到下方
        // ——交互式收起的跟手位移在拖动中段采样
        let start = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(CGVector(dx: win.midX, dy: 380))
        let mid = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(CGVector(dx: win.midX, dy: 520))
        let end = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(CGVector(dx: win.midX, dy: 660))
        start.press(
            forDuration: 0.15, thenDragTo: mid,
            withVelocity: .slow, thenHoldForDuration: 0.6
        )
        let kbMid = app.keyboards.firstMatch
        let midTop = kbMid.exists ? kbMid.frame.minY : -1
        lines.append(
            "kbMid top=\(Int(midTop))"
                + " followed=\(midTop > kbFrame0.minY + 30)"
        )
        // 继续拖完并松手
        mid.press(
            forDuration: 0.1, thenDragTo: end,
            withVelocity: .slow, thenHoldForDuration: 0.2
        )
        Thread.sleep(forTimeInterval: 1.2)
        let dismissed = !app.keyboards.firstMatch.exists
        lines.append("dismissedAfterDrag=\(dismissed)")

        let text = lines.joined(separator: "\n")
        print("DRAG-DISMISS-BEGIN")
        print(text)
        print("DRAG-DISMISS-END")
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(
            midTop > kbFrame0.minY + 30,
            "拖动中键盘未跟手下行（kbMid=\(Int(midTop)))"
                + "——.interactively 在本承载下未跨界生效，"
                + "须走手动桥接降级案"
        )
        XCTAssertTrue(
            dismissed,
            "拖过阈值松手后键盘未收起——交互式收起未完成"
        )
    }
}
