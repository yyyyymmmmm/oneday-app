import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 键盘真崩解耦验收（本包）：ChatView 主线钦定「解
/// 析与写库解耦」的三支落点恒等＋同步窗口零写证明。
/// 背景：旧 ensureMainThread 在 onAppear 同步 save()，
/// 其变更通知同步投递进 _SwiftData_SwiftUI 观察者触
/// 发断言真崩（定因见 keyboard-trap 三档）；等价改法
/// ＝落点输入仍在原程序点同步得出（.needsCreation
/// 支预生成将建 id）、写库后置且与链接预热串成同一
/// 条有序链。本组以生产 RootView 整页装配（口径同
/// ChatPageAssemblyRegressionTests）＋SideChatStore
/// 钦定回读＋抽屉当前对象引用（DrawerSelectionPolicy
/// 派生）观测落点，不读 ChatView 私有状态：
/// ①同步窗口零写：装配只做同步布局、不转运行循环
/// ——解析已产出待定 id，但容器零线程、钦定未落；
/// 写库链落定后建出的主线就是待定 id 本人；
/// ②三支恒等：空容器首启落新建主线、名单非空无钦
/// 定落新建主线而非名单第一条、上次记录失效回主
/// 线、存量钦定沿用且元数据对齐后置、钦定失效以
/// 预生成 id 重建
@MainActor
final class MainThreadDecoupleTests: XCTestCase {

    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
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

    /// 装配生产整页、只跑同步布局：返回时 onAppear 同
    /// 步段（纯解析）已执行，后置写库链（MainActor
    /// Task）未获运行机会——同步窗口观测点。本函数内
    /// 不许出现任何 await/转运行循环，否则观测失效
    private func assembleSyncWindow(
        appState: AppState, container: ModelContainer
    ) {
        let host = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    private func settle() {
        spinRunLoop(seconds: 2.0)
        window.layoutIfNeeded()
    }

    private func fetchThreads(
        _ container: ModelContainer
    ) throws -> [ChatThread] {
        try container.mainContext.fetch(
            FetchDescriptor<ChatThread>()
        )
    }

    @discardableResult
    private func seedThread(
        _ container: ModelContainer, title: String
    ) throws -> ChatThread {
        let thread = ChatThread()
        thread.title = title
        container.mainContext.insert(thread)
        try container.mainContext.save()
        return thread
    }

    // MARK: - ① 同步窗口零写（.needsCreation 支）

    func testSyncWindowWritesNothingThenCreatesMainWithPendingID()
        throws
    {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        assembleSyncWindow(appState: appState, container: container)

        let store = appState.sideChats
        // 解析已跑（待定 id 已铸）——未跑则在此硬红，
        // 不许以「什么都没发生」冒充零写通过
        let pending = try XCTUnwrap(
            store.pendingMainThreadID,
            "onAppear 同步段未产出待定钦定——解析未跑或未走 .needsCreation 支"
        )
        XCTAssertNil(
            store.mainThreadID,
            "同步窗口内钦定已落值——钦定写入未后置"
        )
        XCTAssertTrue(
            try fetchThreads(container).isEmpty,
            "同步窗口内容器已出现线程——onAppear 同步段仍在写 SwiftData"
        )

        // 写库链落定：建出的主线就是待定 id 本人
        settle()
        let threads = try fetchThreads(container)
        XCTAssertEqual(
            threads.map(\.id), [pending],
            "落定后的主线 id 与落点输入（待定 id）不一致"
        )
        XCTAssertEqual(
            threads.first?.title, SideChatStore.mainTitle
        )
        XCTAssertEqual(store.mainThreadID, pending)
        XCTAssertNil(
            store.pendingMainThreadID, "钦定落定后待定未清"
        )
        XCTAssertEqual(appState.currentDrawerObject, .main)
    }

    // MARK: - ② 三支恒等

    /// 名单非空、无钦定：落点必须是新建主线，不许退
    /// 化到名单第一条（Codex 补丁被否的落点改写形态）
    func testNoDesignationWithSideThreadLandsOnNewMainNotFirst()
        throws
    {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        let side = try seedThread(container, title: "旁聊种子")
        assembleSyncWindow(appState: appState, container: container)
        settle()

        let store = appState.sideChats
        let mainID = try XCTUnwrap(store.mainThreadID)
        XCTAssertNotEqual(
            mainID, side.id,
            "钦定落到了名单第一条——落点退化复发"
        )
        let threads = try fetchThreads(container)
        XCTAssertEqual(threads.count, 2)
        XCTAssertEqual(
            threads.first { $0.id == mainID }?.title,
            SideChatStore.mainTitle
        )
        XCTAssertEqual(appState.currentDrawerObject, .main)
    }

    /// 上次停留记录指向已删线程（记录失效）：回主线
    /// ——落点走 .main 支而非名单第一条
    func testStaleLastThreadRecordFallsBackToNewMain() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        let side = try seedThread(container, title: "旁聊种子")
        appState.sideChats.setLastThreadID(UUID())
        assembleSyncWindow(appState: appState, container: container)
        settle()

        let store = appState.sideChats
        let mainID = try XCTUnwrap(store.mainThreadID)
        XCTAssertNotEqual(mainID, side.id)
        XCTAssertEqual(
            try fetchThreads(container)
                .first { $0.id == mainID }?.title,
            SideChatStore.mainTitle
        )
        XCTAssertEqual(appState.currentDrawerObject, .main)
    }

    /// 存量钦定沿用：落点输入＝钦定 id 本人、不新建；
    /// 元数据对齐（标题/服务端绑定）同属写库——同步
    /// 窗口内不得先行落写，落定后对齐到位
    func testExistingDesignationKeptAndAlignmentDeferred() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        let main = try seedThread(container, title: "错标题")
        main.serverSessionID = nil
        try container.mainContext.save()
        appState.sideChats.designateMainThread(main.id)

        assembleSyncWindow(appState: appState, container: container)
        let store = appState.sideChats
        XCTAssertNil(
            store.pendingMainThreadID,
            ".existing 支不许铸待定 id"
        )
        XCTAssertEqual(
            main.title, "错标题",
            "同步窗口内标题已被改写——元数据对齐未后置"
        )
        XCTAssertNil(
            main.serverSessionID,
            "同步窗口内服务端绑定已被改写——元数据对齐未后置"
        )

        settle()
        XCTAssertEqual(
            store.mainThreadID, main.id, "存量钦定被改写"
        )
        XCTAssertEqual(
            try fetchThreads(container).count, 1,
            ".existing 支不许新建线程"
        )
        XCTAssertEqual(main.title, SideChatStore.mainTitle)
        XCTAssertEqual(
            main.serverSessionID, store.ensureMainServerSessionID()
        )
        XCTAssertEqual(appState.currentDrawerObject, .main)
    }

    /// 钦定失效（钦定 id 已不在名单）：以预生成 id 重
    /// 建主线并改钦定到新线，不许沿用失效 id、也不许
    /// 落到名单第一条
    func testStaleDesignationRecreatedWithPendingID() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        let side = try seedThread(container, title: "旁聊种子")
        let ghost = UUID()
        appState.sideChats.designateMainThread(ghost)

        assembleSyncWindow(appState: appState, container: container)
        let pending = try XCTUnwrap(
            appState.sideChats.pendingMainThreadID,
            "钦定失效未走 .needsCreation 支预生成 id"
        )
        XCTAssertNotEqual(pending, ghost)
        settle()

        let store = appState.sideChats
        XCTAssertEqual(
            store.mainThreadID, pending,
            "重建后钦定不是预生成 id——落点输入与建线不一致"
        )
        XCTAssertNotEqual(store.mainThreadID, side.id)
        let threads = try fetchThreads(container)
        XCTAssertEqual(threads.count, 2)
        XCTAssertFalse(
            threads.contains { $0.id == ghost },
            "失效 id 被建成线程——幻影钦定落盘"
        )
        XCTAssertEqual(appState.currentDrawerObject, .main)
    }
}
