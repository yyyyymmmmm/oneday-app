import XCTest

/// §351 验收专用临时驱动（不入仓、验后删）：录屏
/// 逐帧差分用——生产装配（-odDemoMode）开/合抽
/// 屉各 3 次，每次落定后停 0.9s 让录屏可分段
final class DrawerMotionRecordingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDriveDrawerOpenCloseThreeTimes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        let openButton = app.buttons["drawer.open"]
        XCTAssertTrue(
            openButton.waitForExistence(timeout: 20), "生产抽屉入口未出现")
        let row = app.buttons["drawer.row.channel.hermes"]
        let strip = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5))
        for round in 1...3 {
            if openButton.isHittable { openButton.tap() }
            XCTAssertTrue(
                row.waitForExistence(timeout: 10),
                "第 \(round) 次抽屉未打开")
            Thread.sleep(forTimeInterval: 0.9)
            strip.tap()
            let closed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isHittable == true"),
                object: openButton)
            XCTAssertEqual(
                XCTWaiter.wait(for: [closed], timeout: 10), .completed,
                "第 \(round) 次抽屉未关闭")
            Thread.sleep(forTimeInterval: 0.9)
        }
    }
}
