import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 桥级复现：与 ContentView 同款把 appState.
/// drawerPresented 喂 DrawerContainer（抽屉侧是真
/// DrawerView、内容侧替身），验「语义翻转→桥更新→
/// 容器动画」整链在 SwiftUI 宿主里是否成立。
private struct DrawerBridgeHarness: View {
    @Environment(AppState.self) private var appState
    @State private var selection: ContentView.MainTab = .chat

    var body: some View {
        DrawerContainer(
            selection: $selection,
            presented: appState.drawerPresented,
            onManageAll: {},
            onOpenChannel: { _ in }
        ) {
            Text("content替身")
        }
    }
}

@MainActor
final class DrawerBridgeHarnessTests: XCTestCase {
    private var window: UIWindow!
    private var appState: AppState!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        let host = UIHostingController(
            rootView: DrawerBridgeHarness()
                .environment(appState)
                .modelContainer(container)
        )
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
    }

    override func tearDown() async throws {
        window.isHidden = true
        window = nil
        container = nil
        appState = nil
        try await super.tearDown()
    }

    private func findDrawerController(
        in vc: UIViewController
    ) -> DrawerContainerController? {
        if let found = vc as? DrawerContainerController { return found }
        for child in vc.children {
            if let found = findDrawerController(in: child) {
                return found
            }
        }
        return nil
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    func testBridgeTapToOpenReachesFullTravel() throws {
        spinRunLoop(seconds: 0.5)
        let drawer = try XCTUnwrap(
            findDrawerController(in: window.rootViewController!),
            "宿主内未找到 DrawerContainerController"
        )
        XCTAssertGreaterThan(drawer.travel, 0)
        XCTAssertFalse(drawer.semanticPresented)
        appState.drawerPresented = true
        spinRunLoop(seconds: 2.0)
        XCTAssertTrue(
            drawer.semanticPresented,
            "语义未达容器：桥更新未触发 setDrawer"
        )
        let subviews = drawer.view.subviews
        XCTAssertGreaterThanOrEqual(subviews.count, 2)
        XCTAssertEqual(
            subviews[1].transform.tx, drawer.travel, accuracy: 1.0,
            "语义已达但位移未走完：动画在桥环境下被摁死"
        )
    }
}
