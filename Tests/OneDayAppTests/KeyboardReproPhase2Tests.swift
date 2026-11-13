import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 键盘真崩最小触发配方实验（二期二分）——纯实验代码。
/// 一期结论（3 轮 CI 全量 .ips 对位）：最小复现格 E09＝「容器 A 上
/// 存活的最小 @Query 观察面＋对另一容器 B 的种子 save」在 3/3 轮
/// 的第 1 次迭代即以陷阱指纹（rawCodes [1, 7824747624]＋f0
/// SwiftData +502888）击杀宿主；同容器各格（E02–E06）、陈旧观察
/// 面带 0.5s 排空（E07/E08）、无观察（E01）15 次迭代全存活。
/// 二期围绕 E09 二分两个维度：
///   F 组（观察面/save 动作侧）：观察面种类、未求值观察面、长落
///     定、空 save 负对照、B 侧改/删而非插、拆除无排空的陈旧竞态
///   G 组（种子属性侧）：预设 id/空标题/serverSessionID/置顶/
///     手改标记/带条目关系/双线一存/链接字段全集
/// 每格循环 5 次、存活逐次落 repro-progress.txt 标记。
@MainActor
final class KeyboardReproPhase2Tests: XCTestCase {

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

    private func mark(_ cell: String, _ iter: Int) {
        let line = "\(cell) iter=\(iter) ok\n"
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

    @discardableResult
    private func seed(
        _ container: ModelContainer,
        configure: (ChatThread) -> Void = { _ in }
    ) throws -> ChatThread {
        let thread = ChatThread()
        thread.title = "旁聊种子"
        configure(thread)
        container.mainContext.insert(thread)
        try container.mainContext.save()
        return thread
    }

    private struct ProbePlain: View {
        @Query private var threads: [ChatThread]
        var body: some View { Text("n=\(threads.count)") }
    }

    private struct ProbeSorted: View {
        @Query(sort: \ChatThread.updatedAt, order: .reverse)
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

    /// E09 基形助手：A 上挂探针并落定，返回 A 容器（探针保持存活）
    private func liveProbe<V: View>(
        _ probe: V, settle: TimeInterval = 1.0
    ) throws -> ModelContainer {
        let a = try makeContainer()
        mount(probe, container: a)
        spinRunLoop(seconds: settle)
        return a
    }

    // MARK: - F 组

    /// F01：E09＋排序探针（观察面种类无关性）
    func testF01_liveSortedOnA_seedSaveOnB() throws {
        for i in 1...5 {
            _ = try liveProbe(ProbeSorted())
            let b = try makeContainer()
            try seed(b)
            mark("F01", i)
            unmount()
        }
    }

    /// F02：E09＋列表逐行求值探针
    func testF02_liveListOnA_seedSaveOnB() throws {
        for i in 1...5 {
            _ = try liveProbe(ProbeList())
            let b = try makeContainer()
            try seed(b)
            mark("F02", i)
            unmount()
        }
    }

    /// F03：E09 但探针未落定（挂载后不转运行循环、立即对 B 写）
    func testF03_livePlainNoSettle_seedSaveOnB() throws {
        for i in 1...5 {
            let a = try makeContainer()
            mount(ProbePlain(), container: a)
            let b = try makeContainer()
            try seed(b)
            mark("F03", i)
            unmount()
        }
    }

    /// F04：E09＋长落定 5s（排除「观察面还在初始化」）
    func testF04_livePlainLongSettle_seedSaveOnB() throws {
        for i in 1...5 {
            _ = try liveProbe(ProbePlain(), settle: 5.0)
            let b = try makeContainer()
            try seed(b)
            mark("F04", i)
            unmount()
        }
    }

    /// F05：负对照——探针存活，B 做无变更 save（无插入/改/删）
    func testF05_livePlainOnA_emptySaveOnB() throws {
        for i in 1...5 {
            _ = try liveProbe(ProbePlain())
            let b = try makeContainer()
            try b.mainContext.save()
            mark("F05", i)
            unmount()
        }
    }

    /// F06：探针存活，B 侧是「改存量线」而非插入
    func testF06_livePlainOnA_updateSaveOnB() throws {
        for i in 1...5 {
            let b = try makeContainer()
            let existing = try seed(b)
            _ = try liveProbe(ProbePlain())
            existing.title = "改名"
            existing.updatedAt = Date()
            try b.mainContext.save()
            mark("F06", i)
            unmount()
        }
    }

    /// F07：探针存活，B 侧是「删存量线」
    func testF07_livePlainOnA_deleteSaveOnB() throws {
        for i in 1...5 {
            let b = try makeContainer()
            let existing = try seed(b)
            _ = try liveProbe(ProbePlain())
            b.mainContext.delete(existing)
            try b.mainContext.save()
            mark("F07", i)
            unmount()
        }
    }

    /// F08：陈旧竞态（最小面）——探针落定后拆除、不排空、立即对 B 写
    func testF08_stalePlainNoDrain_seedSaveOnB() throws {
        for i in 1...5 {
            let a = try makeContainer()
            mount(ProbePlain(), container: a)
            spinRunLoop(seconds: 1.0)
            unmount()
            let b = try makeContainer()
            try seed(b)
            mark("F08", i)
        }
    }

    /// F09：陈旧竞态（生产整页）——RootView 落定后拆除、不排空、立即对 B 写
    func testF09_staleRootNoDrain_seedSaveOnB() throws {
        for i in 1...5 {
            let appState = AppState(
                client: DemoHermesClient(), demoMode: .connected
            )
            let a = try makeContainer()
            assembleRoot(appState: appState, container: a)
            spinRunLoop(seconds: 2.0)
            window?.layoutIfNeeded()
            unmount()
            let b = try makeContainer()
            try seed(b)
            mark("F09", i)
        }
    }

    // MARK: - G 组（E09 基形＋种子属性变体）

    private func e09Variant(
        _ cell: String,
        configure: @escaping (ChatThread) -> Void
    ) throws {
        for i in 1...5 {
            _ = try liveProbe(ProbePlain())
            let b = try makeContainer()
            try seed(b, configure: configure)
            mark(cell, i)
            unmount()
        }
    }

    /// G01：预生成 id（init 后改派固定 UUID）
    func testG01_seedPresetID() throws {
        try e09Variant("G01") { $0.id = UUID() }
    }

    /// G02：空标题
    func testG02_seedEmptyTitle() throws {
        try e09Variant("G02") { $0.title = "" }
    }

    /// G03：serverSessionID 已落（链接态）
    func testG03_seedServerSessionID() throws {
        try e09Variant("G03") { $0.serverSessionID = "oneday-side-deadbeef" }
    }

    /// G04：置顶
    func testG04_seedPinned() throws {
        try e09Variant("G04") { $0.isPinned = true }
    }

    /// G05：手改标题标记
    func testG05_seedTitleManual() throws {
        try e09Variant("G05") { $0.titleIsManual = true }
    }

    /// G06：带条目关系（插入时挂一条 ChatEntry）
    func testG06_seedWithEntry() throws {
        for i in 1...5 {
            _ = try liveProbe(ProbePlain())
            let b = try makeContainer()
            let thread = ChatThread()
            thread.title = "旁聊种子"
            let entry = ChatEntry(role: "user", content: "hi", thread: thread)
            thread.entries = [entry]
            b.mainContext.insert(thread)
            b.mainContext.insert(entry)
            try b.mainContext.save()
            mark("G06", i)
            unmount()
        }
    }

    /// G07：双线同存
    func testG07_seedTwoThreadsOneSave() throws {
        for i in 1...5 {
            _ = try liveProbe(ProbePlain())
            let b = try makeContainer()
            let t1 = ChatThread(); t1.title = "甲"
            let t2 = ChatThread(); t2.title = "乙"
            b.mainContext.insert(t1)
            b.mainContext.insert(t2)
            try b.mainContext.save()
            mark("G07", i)
            unmount()
        }
    }

    /// G08：链接字段全集（失败留痕＋锁定模型＋已种子）
    func testG08_seedLinkFieldsFull() throws {
        try e09Variant("G08") {
            $0.linkFailureCount = 2
            $0.linkLastError = "boom"
            $0.linkedModel = "claude-sonnet-4-6"
            $0.serverSeeded = true
        }
    }
}
