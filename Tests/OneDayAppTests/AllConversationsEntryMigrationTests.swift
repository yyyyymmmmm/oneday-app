import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 全部对话入口迁移钉测（管理收口包补件，用户
/// 2026-11-13 18:57 拍板「挪进设置页、抽屉不再
/// 放」）：
/// ① 真抽屉（DrawerContainer＋真 DrawerView）开屉
///    后无障碍树里不得再有「管理全部对话」行——抽
///    屉内不再有任何进全部对话页的路径（导航行本
///    体须在场作锚，防空树假绿）；
/// ② 真设置页里「全部对话」行与「侧边栏」行同在
///    （目录同组相邻由 Core 目录钉测管，见
///    SettingsCatalogTests），且点按该行真触发跳
///    出回调 onRequestAllConversations——入口可达
///    不是只画一行。
/// 采集法：宿主窗口内递归收集无障碍元素（子视图
/// ＋accessibilityElements 双路），标签取元素自带
/// accessibilityLabel；设置页宿主取高窗让偏好组行
/// 全部落进实装区（List 惰性实装、屏外行不存在）。
@MainActor
final class AllConversationsEntryMigrationTests: XCTestCase {

    private var window: UIWindow!
    private var appState: AppState!

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        appState = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// 递归采集无障碍元素（去重防容器自引用死循环）
    private func collectElements(from root: UIView) -> [NSObject] {
        var out: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted
            else { return }
            if object.isAccessibilityElement {
                out.append(object)
            }
            if let children = object.accessibilityElements {
                for child in children {
                    if let ns = child as? NSObject { visit(ns) }
                }
            }
            if let view = object as? UIView {
                for sub in view.subviews { visit(sub) }
            }
        }
        visit(root)
        return out
    }

    private func labels(from root: UIView) -> [String] {
        collectElements(from: root)
            .compactMap { $0.accessibilityLabel }
            .filter { !$0.isEmpty }
    }

    // MARK: - ① 抽屉无管理行

    private struct DrawerHarness: View {
        @Environment(AppState.self) private var appState
        @State private var selection: ContentView.MainTab = .chat

        var body: some View {
            DrawerContainer(
                selection: $selection,
                presented: appState.drawerPresented,
                onOpenChannel: {}
            ) {
                Text("content替身")
            }
        }
    }

    func testDrawerHasNoManageAllRow() throws {
        appState = AppState()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        let host = UIHostingController(
            rootView: DrawerHarness()
                .environment(appState)
                .modelContainer(container)
        )
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 393, height: 1200)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.5)
        appState.drawerPresented = true
        spinRunLoop(seconds: 2.0)

        let found = labels(from: window)
        XCTAssertTrue(
            found.contains("主线聊天"),
            "锚点缺失（导航行未实装，采集不可信）：\(found)"
        )
        XCTAssertFalse(
            found.contains("管理全部对话"),
            "抽屉仍有管理全部对话行：\(found)"
        )
    }

    // MARK: - ② 设置有全部对话行且点按可达

    private final class RequestProbe {
        var count = 0
    }

    func testSettingsAllConversationsRowFiresRequest() {
        appState = AppState()
        let probe = RequestProbe()
        let host = UIHostingController(
            rootView: SettingsView(
                onRequestAllConversations: { probe.count += 1 }
            )
            .environment(appState)
        )
        // 高窗：让偏好与权限组（含侧边栏/全部对话行）
        // 全部落进 List 实装区
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 393, height: 2600)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        spinRunLoop(seconds: 1.5)

        let elements = collectElements(from: window)
        let found = elements.compactMap { $0.accessibilityLabel }
        XCTAssertTrue(
            found.contains("侧边栏"),
            "锚点缺失（侧边栏行未实装，采集不可信）：\(found)"
        )
        guard let row = elements.first(where: {
            $0.accessibilityLabel == "全部对话"
                && $0.accessibilityTraits.contains(.button)
        }) ?? elements.first(where: {
            $0.accessibilityLabel == "全部对话"
        }) else {
            XCTFail("设置页无全部对话行：\(found)")
            return
        }
        XCTAssertTrue(
            row.accessibilityActivate(),
            "全部对话行无障碍激活未被接受"
        )
        spinRunLoop(seconds: 0.5)
        XCTAssertEqual(
            probe.count, 1,
            "点按全部对话行未触发跳出请求（行在而不可达）"
        )
    }
}
