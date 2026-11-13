import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 键盘真崩最小触发配方实验（一期筛查）——纯实验代码，不动生产逻辑。
/// 背景（keyboard-ips-verdict-20261113.md）：陷阱指纹 rawCodes
/// [1, 7824747624]＋f0 SwiftData +502888，与调用点/同步性无关；
/// 三条到达路径的共同分母＝「存活的 _SwiftData_SwiftUI 观察面」，
/// 前置条件疑在被观察数据状态。本组以裁决档 #4 形态（种子写＋
/// 存活观察面）为复现器，筛查两个维度：
///   观察面形态：无观察／纯 @Query／排序 @Query／谓词 @Query／
///     列表逐行求值 @Query／陈旧观察面（装配后拆除、跨容器）／
///     存活观察面跨容器／生产 RootView 整页（同容器后置 save、
///     陈旧整页跨容器）
///   save 时机：观察面求值落定后／装配窗内立即
/// 种子一期恒用默认形态（ChatThread()＋标题），属性二分留二期。
/// 每格内循环 5 次（每次全新容器/观察面），每迭代存活后往
/// 沙盒 tmp 的 repro-progress.txt 追加一行——宿主死亡后 CI
/// 收集步可据此数出死亡发生在第几次迭代。
@MainActor
final class KeyboardReproExperimentTests: XCTestCase {

    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow?

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    // MARK: - 进度标记（死亡取证）

    private func mark(_ cell: String, _ iter: Int, _ note: String = "ok") {
        let line = "\(cell) iter=\(iter) \(note)\n"
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("repro-progress.txt")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - 基础设施

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

    private func mount<V: View>(_ view: V, container: ModelContainer) {
        let host = UIHostingController(
            rootView: view.modelContainer(container)
        )
        let w = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        w.rootViewController = host
        w.makeKeyAndVisible()
        w.layoutIfNeeded()
        window = w
    }

    private func unmount() {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
    }

    @discardableResult
    private func seed(
        _ container: ModelContainer, title: String = "旁聊种子"
    ) throws -> ChatThread {
        let thread = ChatThread()
        thread.title = title
        container.mainContext.insert(thread)
        try container.mainContext.save()
        return thread
    }

    private func assembleRoot(
        appState: AppState, container: ModelContainer
    ) {
        let host = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        let w = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        w.rootViewController = host
        w.makeKeyAndVisible()
        w.layoutIfNeeded()
        window = w
    }

    // MARK: - 观察探针（最小观察面，非生产视图）

    private struct ProbePlain: View {
        @Query private var threads: [ChatThread]
        var body: some View { Text("n=\(threads.count)") }
    }

    private struct ProbeSorted: View {
        @Query(sort: \ChatThread.updatedAt, order: .reverse)
        private var threads: [ChatThread]
        var body: some View { Text("n=\(threads.count)") }
    }

    private struct ProbePredicate: View {
        @Query(filter: #Predicate<ChatThread> { $0.serverSessionID == nil })
        private var threads: [ChatThread]
        var body: some View { Text("n=\(threads.count)") }
    }

    private struct ProbeList: View {
        @Query(sort: \ChatThread.updatedAt, order: .reverse)
        private var threads: [ChatThread]
        var body: some View {
            List(threads) { t in
                VStack(alignment: .leading) {
                    Text(t.title)
                    Text(t.serverSessionID ?? "-")
                    Text("e=\(t.entries.count)")
                }
            }
        }
    }

    // MARK: - E01 对照：无观察面，纯种子写

    func testE01_noObserver_seedSave() throws {
        for i in 1...5 {
            let c = try makeContainer()
            try seed(c)
            mark("E01", i)
        }
    }

    // MARK: - E02 纯 @Query 同容器、求值落定后种子写

    func testE02_plainQuery_settled_seedSave() throws {
        for i in 1...5 {
            let c = try makeContainer()
            mount(ProbePlain(), container: c)
            spinRunLoop(seconds: 1.0)
            try seed(c)
            mark("E02", i)
            unmount()
        }
    }

    // MARK: - E03 纯 @Query 同容器、装配窗内立即种子写（未转运行循环）

    func testE03_plainQuery_immediate_seedSave() throws {
        for i in 1...5 {
            let c = try makeContainer()
            mount(ProbePlain(), container: c)
            try seed(c)
            mark("E03", i)
            unmount()
        }
    }

    // MARK: - E04 排序 @Query 同容器、落定后种子写（生产 ChatView 形态）

    func testE04_sortedQuery_settled_seedSave() throws {
        for i in 1...5 {
            let c = try makeContainer()
            mount(ProbeSorted(), container: c)
            spinRunLoop(seconds: 1.0)
            try seed(c)
            mark("E04", i)
            unmount()
        }
    }

    // MARK: - E05 列表逐行求值 @Query 同容器、落定后种子写（#3 路径形态）

    func testE05_listQuery_settled_seedSave() throws {
        for i in 1...5 {
            let c = try makeContainer()
            mount(ProbeList(), container: c)
            spinRunLoop(seconds: 1.0)
            try seed(c)
            mark("E05", i)
            unmount()
        }
    }

    // MARK: - E06 谓词 @Query 同容器、落定后种子写

    func testE06_predicateQuery_settled_seedSave() throws {
        for i in 1...5 {
            let c = try makeContainer()
            mount(ProbePredicate(), container: c)
            spinRunLoop(seconds: 1.0)
            try seed(c)
            mark("E06", i)
            unmount()
        }
    }

    // MARK: - E07 陈旧最小观察面：A 容器观察面装配→落定→拆除，
    //         随后对全新 B 容器种子写（#4 形状的最小版）

    func testE07_stalePlainQuery_seedSaveOnNewContainer() throws {
        for i in 1...5 {
            let a = try makeContainer()
            mount(ProbePlain(), container: a)
            spinRunLoop(seconds: 1.0)
            unmount()
            spinRunLoop(seconds: 0.5)
            let b = try makeContainer()
            try seed(b)
            mark("E07", i)
        }
    }

    // MARK: - E08 陈旧生产整页：RootView 在 A 装配落定→拆除，
    //         随后对全新 B 容器种子写（#4 原形状）

    func testE08_staleRootView_seedSaveOnNewContainer() throws {
        for i in 1...5 {
            let appState = AppState(
                client: DemoHermesClient(), demoMode: .connected
            )
            let a = try makeContainer()
            assembleRoot(appState: appState, container: a)
            spinRunLoop(seconds: 2.0)
            window?.layoutIfNeeded()
            unmount()
            spinRunLoop(seconds: 0.5)
            let b = try makeContainer()
            try seed(b)
            mark("E08", i)
        }
    }

    // MARK: - E09 存活观察面跨容器：A 观察面保持挂载，对 B 种子写

    func testE09_livePlainQueryOnA_seedSaveOnB() throws {
        for i in 1...5 {
            let a = try makeContainer()
            mount(ProbePlain(), container: a)
            spinRunLoop(seconds: 1.0)
            let b = try makeContainer()
            try seed(b)
            mark("E09", i)
            unmount()
        }
    }

    // MARK: - E10 生产整页同容器：RootView 装配落定后同容器追加种子写
    //         （旧 ensure 死亡与新 #1 的形状）

    func testE10_rootView_postAssembly_seedSaveSameContainer() throws {
        for i in 1...5 {
            let appState = AppState(
                client: DemoHermesClient(), demoMode: .connected
            )
            let c = try makeContainer()
            assembleRoot(appState: appState, container: c)
            spinRunLoop(seconds: 2.0)
            window?.layoutIfNeeded()
            try seed(c, title: "追加种子")
            mark("E10", i)
            unmount()
        }
    }
}
