import Foundation
import XCTest

/// §397 结构钉测：推送准备面的接线形态在源码层把守——
/// 委托安装与 adaptor 在位、RootView 三处同步、登记存
/// 储绝不发授权请求（铁律）、客户端端点字面、就绪面
/// 只渲染 Core 报告。行为终判（真机收到真推送）属批
/// 4b 验收门，不在本套冒充
final class PushPrepStructureTests: XCTestCase {

    private func source(
        _ relativePath: String
    ) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let url = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testAppInstallsDelegateAndAdaptor() throws {
        let app = try source("Sources/OneDayApp/OneDayApp.swift")
        XCTAssertTrue(
            app.contains("NotificationCenterDelegate.install()")
        )
        XCTAssertTrue(
            app.contains(
                "UIApplicationDelegateAdaptor(PushAppDelegate.self)"
            )
        )
    }

    func testRootViewSynchronizesPushRegistration() throws {
        let app = try source("Sources/OneDayApp/OneDayApp.swift")
        let marker = "struct RootView: View {"
        let start = try XCTUnwrap(app.range(of: marker))
        let rootView = String(app[start.lowerBound...])
        let calls = rootView.components(
            separatedBy:
                "pushRegistration.synchronize(appState: appState)"
        ).count - 1
        XCTAssertEqual(calls, 3)
    }

    func testStoreNeverRequestsAuthorization() throws {
        let store = try source(
            "Sources/OneDayApp/PushRegistrationStore.swift"
        )
        // 查调用形态（带括号）：注释里点名此词是口径
        // 说明、不算调用；真调用必带括号收不住
        XCTAssertFalse(store.contains("requestAuthorization("))
        XCTAssertTrue(store.contains("readSystemState"))
        XCTAssertTrue(
            store.contains("registerForRemoteNotifications")
        )
        XCTAssertTrue(store.contains("recordToken"))
    }

    func testDelegatePresentsAndRoutes() throws {
        let delegate = try source(
            "Sources/OneDayApp/NotificationCenterDelegate.swift"
        )
        XCTAssertTrue(delegate.contains("willPresent"))
        XCTAssertTrue(delegate.contains("interruptionLevel"))
        XCTAssertTrue(
            delegate.contains("PushNotificationRouteResolver")
        )
    }

    func testClientEndpointAndAppStateWiring() throws {
        let client = try source(
            "Sources/OneDayApp/HermesClient.swift"
        )
        XCTAssertTrue(client.contains("/v1/push/tokens"))
        XCTAssertTrue(client.contains("pushEndpointNotReady"))
        let appState = try source(
            "Sources/OneDayApp/AppState.swift"
        )
        XCTAssertTrue(
            appState.contains(
                "let pushRegistration = PushRegistrationStore()"
            )
        )
    }

    func testReadinessViewRendersCoreReportOnly() throws {
        let view = try source(
            "Sources/OneDayApp/PushReadinessView.swift"
        )
        XCTAssertTrue(view.contains("readinessReport"))
        XCTAssertTrue(view.contains("PushReadinessRow.Tone"))
    }
}
