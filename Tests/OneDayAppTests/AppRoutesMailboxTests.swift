import XCTest
@testable import OneDayApp

/// 设置路由信箱归并钉死（§260）：跨页信箱五件（深链
/// 两路／设置 sheet 请求／切格请求／文件定位请求）收
/// 进 AppState.routes（AppRoutes）单一出处后，置位—
/// 消费—清零语义逐项沿旧散字段口径。本组只做状态级
/// 断言：默认全空、五件互不干扰、逐件清零不牵连他
/// 件；ManageSheet 上移公共层后 rawValue／id 不变
/// （sheet 呈现身份稳定）。
@MainActor
final class AppRoutesMailboxTests: XCTestCase {

    func testRoutesDefaultEmpty() {
        let state = AppState(client: DemoHermesClient(), demoMode: .connected)
        XCTAssertNil(state.routes.pendingAgentRoute)
        XCTAssertNil(state.routes.pendingSettingsRoute)
        XCTAssertFalse(state.routes.settingsSheetRequested)
        XCTAssertNil(state.routes.mainTabSwitchRequest)
        XCTAssertNil(state.routes.fileRevealPath)
    }

    func testMailboxRoundTripsAreIndependent() {
        let state = AppState(client: DemoHermesClient(), demoMode: .connected)
        state.routes.pendingSettingsRoute = .models
        state.routes.pendingAgentRoute = .memory
        state.routes.settingsSheetRequested = true
        state.routes.mainTabSwitchRequest = .files
        state.routes.fileRevealPath = "/tmp/a.txt"

        // 逐项消费清零不牵连他件
        state.routes.pendingSettingsRoute = nil
        XCTAssertNil(state.routes.pendingSettingsRoute)
        XCTAssertEqual(state.routes.pendingAgentRoute, .memory)
        XCTAssertTrue(state.routes.settingsSheetRequested)
        XCTAssertEqual(state.routes.mainTabSwitchRequest, .files)
        XCTAssertEqual(state.routes.fileRevealPath, "/tmp/a.txt")

        state.routes.pendingAgentRoute = nil
        state.routes.settingsSheetRequested = false
        state.routes.mainTabSwitchRequest = nil
        state.routes.fileRevealPath = nil
        XCTAssertNil(state.routes.pendingAgentRoute)
        XCTAssertFalse(state.routes.settingsSheetRequested)
        XCTAssertNil(state.routes.mainTabSwitchRequest)
        XCTAssertNil(state.routes.fileRevealPath)
    }

    func testManageSheetIdentityStable() {
        XCTAssertEqual(ManageSheet.overview.rawValue, "overview")
        XCTAssertEqual(ManageSheet.computer.rawValue, "computer")
        XCTAssertEqual(ManageSheet.serverFiles.rawValue, "serverFiles")
        XCTAssertEqual(ManageSheet.serverFiles.id, "serverFiles")
    }
}
