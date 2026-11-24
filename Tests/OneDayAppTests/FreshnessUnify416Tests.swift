import OneDayCore
import XCTest

@testable import OneDayApp

/// §416 新鲜度双轨收口钉测：五面接门的行为对拍
/// ——读触发首拉恰一轮、TTL（60 秒）内零请求、过
/// 期再付一轮、失败不落账（下轮必重试）、强制口
/// 不经门；资源库另钉冷启首帧快照可见＋取数发
/// 起瞬间快照已在屏（SWR 时机）＋改名失效必真拉。
/// 判定表与普查全集见 DESIGN §416。
@MainActor
final class FreshnessUnify416Tests: XCTestCase {

    // MARK: - 资源库（LibraryListStore）

    private var tempDir: URL!
    private var snapshotURL: URL {
        tempDir.appendingPathComponent("snapshot.json")
    }

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "fresh416-\(UUID().uuidString)", isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func entry(
        _ name: String, mtime: Double? = nil
    ) -> WorkspaceFileEntry {
        WorkspaceFileEntry(
            name: name, path: "/opt/data/\(name)",
            isDirectory: false, size: 100, mtime: mtime,
            mimeType: nil
        )
    }

    private func item(
        _ name: String, mtime: Double? = nil
    ) -> Deliverable {
        Deliverable(entry: entry(name, mtime: mtime), source: "产出")
    }

    private var fixture: [Deliverable] {
        [item("报告甲.md", mtime: 300), item("方案.pptx", mtime: 400)]
    }

    /// 读触发对拍：首拉 1、TTL 内 .stillFresh 零请
    /// 求、过期再拉、换键必拉、强制口不经门、失效
    /// 后必真拉
    func testLibraryGateCountsFetches() async {
        let store = LibraryListStore(snapshotFileURL: snapshotURL)
        var fetchCount = 0
        let fetch: @MainActor () async throws -> [Deliverable] = {
            fetchCount += 1
            return self.fixture
        }
        let t0 = Date()

        let first = await store.refreshIfNeeded(
            currentConfigKey: "https://a", now: t0, fetch: fetch
        )
        XCTAssertEqual(first, .loaded)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(store.deliverables, fixture)

        let withinTTL = await store.refreshIfNeeded(
            currentConfigKey: "https://a",
            now: t0.addingTimeInterval(30), fetch: fetch
        )
        XCTAssertEqual(withinTTL, .stillFresh)
        XCTAssertEqual(fetchCount, 1)

        let expired = await store.refreshIfNeeded(
            currentConfigKey: "https://a",
            now: t0.addingTimeInterval(61), fetch: fetch
        )
        XCTAssertEqual(expired, .loaded)
        XCTAssertEqual(fetchCount, 2)

        let otherKey = await store.refreshIfNeeded(
            currentConfigKey: "https://b",
            now: t0.addingTimeInterval(62), fetch: fetch
        )
        XCTAssertEqual(otherKey, .loaded)
        XCTAssertEqual(fetchCount, 3)

        // 强制口不经门：刚 stamp 完也必拉
        let forced = await store.refresh(
            currentConfigKey: "https://b", fetch: fetch
        )
        XCTAssertEqual(forced, .loaded)
        XCTAssertEqual(fetchCount, 4)

        // 名单外写动作失效口：下一次读触发必真拉
        store.invalidateFreshness()
        let afterInvalidate = await store.refreshIfNeeded(
            currentConfigKey: "https://b",
            now: t0.addingTimeInterval(63), fetch: fetch
        )
        XCTAssertEqual(afterInvalidate, .loaded)
        XCTAssertEqual(fetchCount, 5)
    }

    /// 失败不落账：无数据时回 .failedNoData 且下轮
    /// 重试；有数据时回 .keptAfterFailure 且失败轮
    /// 不 stamp、紧接着的读触发仍真拉
    func testLibraryFailureDoesNotStamp() async {
        let store = LibraryListStore(snapshotFileURL: snapshotURL)
        var fetchCount = 0
        var shouldFail = true
        let fetch: @MainActor () async throws -> [Deliverable] = {
            fetchCount += 1
            if shouldFail { throw OneDayBridgeError.failed("断网") }
            return self.fixture
        }
        let t0 = Date()

        let failed = await store.refreshIfNeeded(
            currentConfigKey: "https://a", now: t0, fetch: fetch
        )
        XCTAssertEqual(failed, .failedNoData)
        XCTAssertEqual(fetchCount, 1)

        shouldFail = false
        let retried = await store.refreshIfNeeded(
            currentConfigKey: "https://a",
            now: t0.addingTimeInterval(1), fetch: fetch
        )
        XCTAssertEqual(retried, .loaded)
        XCTAssertEqual(fetchCount, 2)

        shouldFail = true
        let kept = await store.refreshIfNeeded(
            currentConfigKey: "https://a",
            now: t0.addingTimeInterval(62), fetch: fetch
        )
        XCTAssertEqual(kept, .keptAfterFailure)
        XCTAssertEqual(store.deliverables, fixture)
        XCTAssertEqual(fetchCount, 3)

        shouldFail = false
        let afterFailure = await store.refreshIfNeeded(
            currentConfigKey: "https://a",
            now: t0.addingTimeInterval(63), fetch: fetch
        )
        XCTAssertEqual(afterFailure, .loaded)
        XCTAssertEqual(fetchCount, 4)
    }

    /// 冷启对拍（收编硬线）：新店实例先播种——首帧
    /// 名单已在屏；读触发取数发起瞬间名单仍是快照
    /// （网络返回前不空屏）；别台快照不串台
    func testLibraryColdSeedFirstFrameAndSWR() async {
        let writer = LibraryListStore(snapshotFileURL: snapshotURL)
        _ = await writer.refresh(currentConfigKey: "https://a") {
            self.fixture
        }

        let cold = LibraryListStore(snapshotFileURL: snapshotURL)
        cold.seedFromSnapshotIfNeeded(currentConfigKey: "https://a")
        XCTAssertEqual(cold.deliverables, fixture)

        var sawSeededAtFetchTime = false
        let outcome = await cold.refreshIfNeeded(
            currentConfigKey: "https://a", now: Date()
        ) {
            sawSeededAtFetchTime = cold.deliverables != nil
            return self.fixture
        }
        XCTAssertEqual(outcome, .loaded)
        XCTAssertTrue(sawSeededAtFetchTime)

        let foreign = LibraryListStore(snapshotFileURL: snapshotURL)
        foreign.seedFromSnapshotIfNeeded(currentConfigKey: "https://b")
        XCTAssertNil(foreign.deliverables)
    }

    // MARK: - 监测（MonitorsStore，注入缝数请求）

    func testMonitorsGateCountsFetches() async {
        let store = MonitorsStore()
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        var fetchCount = 0
        let t0 = Date()
        let fetch: (ServerConfig) async throws -> [BridgeMonitor] = {
            _ in
            fetchCount += 1
            return []
        }

        await store.loadIfNeeded(appState: appState, now: t0, fetch: fetch)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(store.loadState, .ready)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(30),
            fetch: fetch
        )
        XCTAssertEqual(fetchCount, 1)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(61),
            fetch: fetch
        )
        XCTAssertEqual(fetchCount, 2)
    }

    func testMonitorsFailureDoesNotStamp() async {
        let store = MonitorsStore()
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        var fetchCount = 0
        let t0 = Date()
        let fetch: (ServerConfig) async throws -> [BridgeMonitor] = {
            _ in
            fetchCount += 1
            throw OneDayBridgeError.failed("断网")
        }

        await store.loadIfNeeded(appState: appState, now: t0, fetch: fetch)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertNotEqual(store.loadState, .ready)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(1),
            fetch: fetch
        )
        XCTAssertEqual(fetchCount, 2)
    }

    // MARK: - 记忆库（MemoriesStore，注入缝数请求）

    func testMemoriesGateCountsFetches() async {
        let store = MemoriesStore()
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        var fetchCount = 0
        let t0 = Date()
        let fetch: (ServerConfig) async throws -> [BridgeMemoryEntry] = {
            _ in
            fetchCount += 1
            return []
        }

        await store.loadIfNeeded(
            appState: appState, now: t0, fetchEntries: fetch
        )
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(store.loadState, .ready)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(30),
            fetchEntries: fetch
        )
        XCTAssertEqual(fetchCount, 1)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(61),
            fetchEntries: fetch
        )
        XCTAssertEqual(fetchCount, 2)
    }

    func testMemoriesFailureDoesNotStamp() async {
        let store = MemoriesStore()
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        var fetchCount = 0
        let t0 = Date()
        let fetch: (ServerConfig) async throws -> [BridgeMemoryEntry] = {
            _ in
            fetchCount += 1
            throw WriteGateError.noKey
        }

        await store.loadIfNeeded(
            appState: appState, now: t0, fetchEntries: fetch
        )
        XCTAssertEqual(fetchCount, 1)
        XCTAssertNotEqual(store.loadState, .ready)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(1),
            fetchEntries: fetch
        )
        XCTAssertEqual(fetchCount, 2)
    }

    // MARK: - 看板与学习图谱（计数客户端数请求）

    func testKanbanGateCountsFetches() async {
        let recorder = KanbanLearningCallRecorder()
        let appState = AppState(
            client: CountingKanbanLearningClient(recorder: recorder),
            demoMode: .connected
        )
        let store = KanbanStore()
        let t0 = Date()

        await store.loadIfNeeded(appState: appState, now: t0)
        XCTAssertEqual(recorder.count("kanbanBoard"), 1)
        XCTAssertEqual(store.loadState, .ready)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(30)
        )
        XCTAssertEqual(recorder.count("kanbanBoard"), 1)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(61)
        )
        XCTAssertEqual(recorder.count("kanbanBoard"), 2)
    }

    func testLearningGraphGateCountsFetches() async {
        let recorder = KanbanLearningCallRecorder()
        let appState = AppState(
            client: CountingKanbanLearningClient(recorder: recorder),
            demoMode: .connected
        )
        let store = LearningGraphStore()
        let t0 = Date()

        await store.loadIfNeeded(appState: appState, now: t0)
        XCTAssertEqual(recorder.count("learningGraph"), 1)
        XCTAssertEqual(store.loadState, .ready)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(30)
        )
        XCTAssertEqual(recorder.count("learningGraph"), 1)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(61)
        )
        XCTAssertEqual(recorder.count("learningGraph"), 2)
    }
}
