import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §184 回归：容器租约的生命周期不变量（2026-11-15，第二版）。
///
/// 第一版的测试 1（树先于容器释放的弱引用时序）在 CI 第一轮
/// 根本没跑到断言：`wait(for:)` 在 async 测试里永不满足
/// （主执行器被 wait 占住、asyncAfter 块无从执行，5.5s 超时），
/// 三例里两例死于此自家 bug；第二版改用 `Task.sleep`。
/// 第一版的修法（排空后放容器）亦在同轮被证伪（run 43627222674
/// 宿主仍崩 10 次）——本文件第二版随租约改不变量：
/// ①容器挂载后进入进程级持有、拆卸后仍存活且线程可读
/// （旧顺序下容器随方法返回即死，此断言直接失败）；
/// ②多轮挂载／拆卸循环后异容器 save 不触发已销毁实例访问
/// （第一轮里此例本身在第二轮播种时崩——它就是崩溃的
/// 最小复现）；③拆卸后新容器的播种＋save（seedThreads
/// 同形）干净落盘。宿主去留只作观测打印、不作断言：
/// 第一轮实测残留观察者存活 ≥20 秒，树的析构时序不是
/// 本修法的承重墙，不许它误红。
/// 最终证据仍是 CI 全轮：四条无终局用例恢复终局、宿主零重启。
@MainActor
final class SwiftDataHostLifetimeTests: XCTestCase {

    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: UIWindow!
    private var swiftDataMount = SwiftDataTestMount()

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        await swiftDataMount.release()
        try await super.tearDown()
    }

    /// async 测试里等渲染落稳：只用 Task.sleep。
    /// `wait(for:)` 会占住主执行器、asyncAfter 块永不执行，
    /// 在 async 测试里 5.5s 必超时（第一轮自家 bug）。
    private func settle(seconds: TimeInterval) async {
        try? await Task.sleep(
            nanoseconds: UInt64(seconds * 1_000_000_000)
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    /// 播种一对线程（主线＋旁聊，同 ChatReliabilityOfflineTests
    /// 的 p1／p2 形态——崩溃里被销毁的恒为 p2 旁聊线程）。
    private func seedThreads(
        in container: ModelContainer
    ) throws -> (main: ChatThread, side: ChatThread) {
        let context = ModelContext(container)
        let main = ChatThread(title: "主线")
        let side = ChatThread(title: "旁聊")
        context.insert(main)
        context.insert(side)
        let entry = ChatEntry(
            role: "user", content: "回归标记", thread: main
        )
        context.insert(entry)
        try context.save()
        return (main, side)
    }

    private func mountRootView(
        container: ModelContainer, appState: AppState
    ) async -> UIHostingController<AnyView> {
        swiftDataMount.retain(container)
        let host = UIHostingController(
            rootView: AnyView(
                RootView()
                    .environment(appState)
                    .environment(\.locale, AppLocale.uiLocale)
                    .modelContainer(container)
            )
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        await settle(seconds: 0.5)
        window.layoutIfNeeded()
        return host
    }

    private func unmountWindow() {
        window.rootViewController = nil
        window.isHidden = true
        window = nil
    }

    // MARK: - 不变量 1：容器在挂载树拆卸后仍存活、线程可读

    func testContainerSurvivesMountedTreeTeardown() async throws {
        let heldBefore = SwiftDataTestMount.retainedCount
        let container = try makeContainer()
        let seeded = try seedThreads(in: container)
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        appState.sessionLedger.designateMainThread(seeded.main.id)
        appState.sideChats.setLastThreadID(seeded.main.id)
        var host: UIHostingController<AnyView>? =
            await mountRootView(container: container, appState: appState)
        weak var weakHost = host
        XCTAssertTrue(
            swiftDataMount.isRetained, "挂载后租约应持有容器"
        )

        // 拆窗＋释放实例引用：容器须留在进程级持有中。
        unmountWindow()
        host = nil
        await settle(seconds: 0.5)
        await swiftDataMount.release()
        XCTAssertEqual(
            SwiftDataTestMount.retainedCount, heldBefore + 1,
            "容器必须留在进程级持有中——旧顺序下它随方法"
                + "返回已释放，此处即为回归红点"
        )
        // 容器仍活：此前播种的 p2 旁聊线程可读、未被 reset 销毁。
        XCTAssertEqual(seeded.side.title, "旁聊")
        do {
            let live = try ModelContext(container).fetch(
                FetchDescriptor<ChatThread>()
            )
            XCTAssertEqual(live.count, 2)
        }
        // 观测（不作断言）：宿主是否已析构。第一轮实测
        // 残留观察者存活 ≥20 秒，析构时序不是承重墙。
        print(
            "DIAG §184: weakHost nil after teardown: "
                + "\(weakHost == nil)"
        )
    }

    // MARK: - 不变量 2：多轮挂载循环后异容器 save 不杀宿主

    func testRepeatedMountTeardownThenSaveDoesNotTrap() async throws {
        for _ in 0..<8 {
            let container = try makeContainer()
            _ = try seedThreads(in: container)
            let appState = AppState(
                client: DemoHermesClient(), demoMode: .connected
            )
            _ = await mountRootView(
                container: container, appState: appState
            )
            unmountWindow()
            await swiftDataMount.release()
        }
        // §184 触发器本尊：异容器 save——第一轮里此例在
        // 第二轮播种时崩（残留观察者触已销毁线程）；容器
        // 进程级持有后旧树再被唤醒也只读到活实例，此 save
        // 必须干净落盘。
        let fresh = try makeContainer()
        let context = ModelContext(fresh)
        let thread = ChatThread(title: "新会话")
        context.insert(thread)
        try context.save()
        let fetched = try ModelContext(fresh).fetch(
            FetchDescriptor<ChatThread>()
        )
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "新会话")
    }

    // MARK: - 不变量 3：拆卸后新容器的播种＋save 同形干净

    func testSeedSaveAfterTeardownDoesNotTrap() async throws {
        let container = try makeContainer()
        _ = try seedThreads(in: container)
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        _ = await mountRootView(container: container, appState: appState)
        unmountWindow()
        await swiftDataMount.release()

        // seedThreads 同形（主／旁聊双线程＋save）：R2／R3
        // 的崩溃即发生在此拍的通知投递里。
        let fresh = try makeContainer()
        let seeded = try seedThreads(in: fresh)
        XCTAssertEqual(seeded.main.title, "主线")
        XCTAssertEqual(seeded.side.title, "旁聊")
        let fetched = try ModelContext(fresh).fetch(
            FetchDescriptor<ChatThread>()
        )
        XCTAssertEqual(fetched.count, 2)
    }
}
