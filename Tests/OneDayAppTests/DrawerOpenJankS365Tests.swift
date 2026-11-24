import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §365 钉测组（抽屉打开卡顿修复：D1 桥等值守卫＋
/// D2 打开刷新落定后落写）。预期口径（§365.3 写死）：
/// 装配完成后开→关→开全程，抽屉根重建次数与内容根
/// 刷入次数恒定（只在首次布局/make 时各 +1）；指纹输
/// 入真变（页签切换）时 apply 重跑、内容根 +1、抽屉
/// 根仍不重建（builder 只存不建）；开落定计数只随开
/// 落定 +1、关落定不计。

@Observable
private final class DrawerJankSelection {
    var tab: ContentView.MainTab = .chat
}

/// 与 DrawerBridgeHarness 同装配（真桥＋真 Drawer-
/// View、内容侧替身），另把页签选择提为可外部驱动
/// 的观察对象，验指纹输入真变路
private struct DrawerJankHarness: View {
    @Environment(AppState.self) private var appState
    @Environment(DrawerJankSelection.self) private var selectionBox

    var body: some View {
        @Bindable var selectionBox = selectionBox
        return DrawerContainer(
            selection: $selectionBox.tab,
            presented: appState.router.drawerPresented,
            onOpenChannel: { _ in }
        ) {
            Text("content替身")
        }
    }
}

@MainActor
final class DrawerOpenJankS365Tests: XCTestCase {
    private var window: UIWindow!
    private var appState: AppState!
    private var selectionBox: DrawerJankSelection!
    private var container: ModelContainer!
    /// §184：容器租约——见 SwiftDataTestMount
    private var swiftDataMount = SwiftDataTestMount()

    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        selectionBox = DrawerJankSelection()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        let host = UIHostingController(
            rootView: DrawerJankHarness()
                .environment(appState)
                .environment(selectionBox)
                .modelContainer(container)
        )
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
    }

    override func tearDown() async throws {
        window.rootViewController = nil
        window.isHidden = true
        window = nil
        await swiftDataMount.release()
        container = nil
        selectionBox = nil
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

    private func mountedDrawer() throws -> DrawerContainerController {
        spinRunLoop(seconds: 0.5)
        let drawer = try XCTUnwrap(
            findDrawerController(in: window.rootViewController!),
            "宿主内未找到 DrawerContainerController"
        )
        XCTAssertGreaterThan(drawer.travel, 0)
        return drawer
    }

    /// D1 主钉：开→关→开全程双宿主根零重建；D2 主
    /// 钉：开落定计数只随开落定走（开 +1、关不计、
    /// 再开 +1）
    func testOpenCloseOpenKeepsHostRootsUnRebuilt() throws {
        let drawer = try mountedDrawer()
        XCTAssertFalse(drawer.semanticPresented)
        let rebuild0 = drawer.drawerRootRebuildCount
        let content0 = drawer.contentRootApplyCount
        XCTAssertGreaterThanOrEqual(rebuild0, 1, "首次布局应已建立抽屉根")
        XCTAssertGreaterThanOrEqual(content0, 1, "make 应已刷入内容根")
        XCTAssertEqual(appState.router.drawerOpenSettledCount, 0)

        appState.router.drawerPresented = true
        spinRunLoop(seconds: 3.5)
        XCTAssertTrue(drawer.semanticPresented)
        XCTAssertEqual(
            drawer.view.subviews[1].transform.tx, drawer.travel,
            accuracy: 1.0, "打开动画应走完到 travel")
        XCTAssertEqual(
            drawer.drawerRootRebuildCount, rebuild0,
            "打开翻转不许重建抽屉根（D1）")
        XCTAssertEqual(
            drawer.contentRootApplyCount, content0,
            "打开翻转不许重刷内容根（D1）")
        XCTAssertEqual(
            appState.router.drawerOpenSettledCount, 1,
            "开落定应回写计数 +1（D2）")

        appState.router.drawerPresented = false
        spinRunLoop(seconds: 3.5)
        XCTAssertFalse(drawer.semanticPresented)
        XCTAssertEqual(drawer.drawerRootRebuildCount, rebuild0)
        XCTAssertEqual(drawer.contentRootApplyCount, content0)
        XCTAssertEqual(
            appState.router.drawerOpenSettledCount, 1,
            "关落定不许触发打开刷新计数（D2）")

        appState.router.drawerPresented = true
        spinRunLoop(seconds: 3.5)
        XCTAssertTrue(drawer.semanticPresented)
        XCTAssertEqual(drawer.drawerRootRebuildCount, rebuild0)
        XCTAssertEqual(drawer.contentRootApplyCount, content0)
        XCTAssertEqual(appState.router.drawerOpenSettledCount, 2)
    }

    /// D1 指纹路：页签真变 → apply 重跑（内容根 +1），
    /// 抽屉 builder 只存不建（重建次数恒定）；落定计
    /// 数不受页签切换影响
    func testSelectionChangeReappliesBridgeWithoutDrawerRebuild() throws {
        let drawer = try mountedDrawer()
        let rebuild0 = drawer.drawerRootRebuildCount
        let content0 = drawer.contentRootApplyCount

        selectionBox.tab = .feed
        spinRunLoop(seconds: 1.0)
        XCTAssertEqual(
            drawer.contentRootApplyCount, content0 + 1,
            "指纹输入真变时 apply 应重跑、内容根重刷一次")
        XCTAssertEqual(
            drawer.drawerRootRebuildCount, rebuild0,
            "builder 换新只存不建：抽屉根不许因桥更新重建")
        XCTAssertEqual(appState.router.drawerOpenSettledCount, 0)
    }
}

/// 控制器级（裸装窗口，与 DrawerContainerControll-
/// erTests 同台）：builder 赋值语义与落定回调时机
@MainActor
final class DrawerSettleSignalS365Tests: XCTestCase {
    private var window: UIWindow!
    private var controller: DrawerContainerController!

    override func setUp() async throws {
        try await super.setUp()
        controller = DrawerContainerController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    override func tearDown() async throws {
        window.isHidden = true
        window = nil
        controller = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// D1 容器半：builder 赋值只存不建；重建只在
    /// travel 真变拍发生、且用最新落账的 builder
    func testBuilderAssignmentStoresWithoutRebuilding() {
        XCTAssertGreaterThan(controller.travel, 0)
        XCTAssertEqual(controller.drawerRootRebuildCount, 0)

        var firstBuilderCalls = 0
        controller.drawerBuilder = { _ in
            firstBuilderCalls += 1
            return AnyView(Text("drawer一"))
        }
        XCTAssertEqual(firstBuilderCalls, 0, "赋值不许触发重建")
        XCTAssertEqual(controller.drawerRootRebuildCount, 0)

        window.frame = CGRect(x: 0, y: 0, width: 430, height: 852)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(firstBuilderCalls, 1, "travel 真变拍应以落账 builder 重建")
        XCTAssertEqual(controller.drawerRootRebuildCount, 1)

        var secondBuilderCalls = 0
        controller.drawerBuilder = { _ in
            secondBuilderCalls += 1
            return AnyView(Text("drawer二"))
        }
        XCTAssertEqual(secondBuilderCalls, 0)
        XCTAssertEqual(controller.drawerRootRebuildCount, 1)

        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(secondBuilderCalls, 1, "再变 travel 应改用最新 builder")
        XCTAssertEqual(firstBuilderCalls, 1, "旧 builder 不许再被调用")
        XCTAssertEqual(controller.drawerRootRebuildCount, 2)
    }

    /// D2 容器半：落定回调只在 finishSettle 出——瞬
    /// 时路同拍、动画路落定后；动画在途不许抢报
    func testSettledCallbackFiresOnlyAtSettle() {
        var settled: [Bool] = []
        controller.onDrawerSettled = { settled.append($0) }

        controller.setDrawer(true, animated: false)
        XCTAssertEqual(settled, [true], "瞬时路落定同拍回写")

        controller.setDrawer(false, animated: false)
        XCTAssertEqual(settled, [true, false])

        controller.setDrawer(true, animated: true)
        XCTAssertEqual(
            settled, [true, false],
            "动画在途不许提前报落定（D2 的窗外语义）")
        spinRunLoop(seconds: 2.0)
        XCTAssertEqual(settled, [true, false, true], "动画落定后回写开落定")

        controller.setDrawer(false, animated: true)
        spinRunLoop(seconds: 2.0)
        XCTAssertEqual(settled, [true, false, true, false])
    }
}
