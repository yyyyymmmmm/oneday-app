import Foundation
import OneDayCore
import XCTest
@testable import OneDayApp

/// §369（缓存审计 C4）资源库名单店钉测：
/// ①有快照冷启＝先渲染快照＋恰 1 次对账请求；
/// ②删除＝0 次名单请求（本地摘行）、失败原位回滚；
/// ③换配置键＝快照弃用、全量拉；
/// ④对账结果与全量拉取逐项等价；
/// ⑤结构——视图名单 @State 退役、删除路径不再
///   collect()（源码钉测）。
/// 请求计数走假服务端：fetch 闭包计名单请求、
/// perform 闭包计删除请求，与生产接线同形（视图
/// 分别传 bridgeClient.fileLibrary 与 performAdmin
/// 删除）。
@MainActor
final class LibraryListStoreC4Tests: XCTestCase {

    // MARK: - 假服务端与构造

    private var tempDir: URL!
    private var snapshotURL: URL {
        tempDir.appendingPathComponent("snapshot.json")
    }

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "c4-\(UUID().uuidString)", isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() -> LibraryListStore {
        LibraryListStore(snapshotFileURL: snapshotURL)
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
        _ name: String, mtime: Double? = nil,
        source: String = "产出"
    ) -> Deliverable {
        Deliverable(entry: entry(name, mtime: mtime), source: source)
    }

    private var fixture: [Deliverable] {
        [
            item("报告甲.md", mtime: 300),
            item("方案.pptx", mtime: 400),
            item("IMG_0001.png", mtime: 500),
            item("clip.mp4", mtime: 600),
        ]
    }

    /// 假服务端：名单请求与删除请求分别计数；名单
    /// 内容可换；fetch 执行瞬间回调探针（断言「拉取
    /// 发起时屏上已是快照」用）
    @MainActor
    private final class FakeServer {
        var list: [Deliverable] = []
        var listError: Error?
        var deleteError: Error?
        private(set) var listRequestCount = 0
        private(set) var deleteRequestCount = 0
        var onListRequest: (@MainActor () -> Void)?

        @MainActor
        func fetch() async throws -> [Deliverable] {
            listRequestCount += 1
            onListRequest?()
            if let listError { throw listError }
            return list
        }

        @MainActor
        func delete(path: String) async throws {
            deleteRequestCount += 1
            if let deleteError { throw deleteError }
            list.removeAll { $0.entry.path == path }
        }
    }

    private func paths(
        _ items: [Deliverable]?
    ) -> [String]? {
        items?.map(\.entry.path)
    }

    // MARK: - ① 有快照冷启：先快照、恰 1 次对账

    func testColdStartWithSnapshotSeedsFirstThenOneRevalidation()
        async
    {
        let server = FakeServer()
        server.list = fixture
        let key = "http://server-a"

        // 第一程：正常对账落盘快照
        let writer = makeStore()
        let first = await writer.refresh(
            currentConfigKey: key, fetch: server.fetch
        )
        XCTAssertEqual(first, .loaded)
        XCTAssertEqual(server.listRequestCount, 1)

        // 服务端名单已变（删一加一）
        var updated = fixture
        updated.removeAll { $0.entry.name == "方案.pptx" }
        updated.append(item("新稿.docx", mtime: 700))
        server.list = updated

        // 第二程：新店（模拟冷启）——fetch 发起瞬间
        // 屏上必须是快照名单，且全程恰 1 次对账
        let cold = makeStore()
        var atFetchTime: [String]?
        server.onListRequest = { @MainActor in
            atFetchTime = cold.deliverables?.map(\.entry.path)
        }
        let outcome = await cold.refresh(
            currentConfigKey: key, fetch: server.fetch
        )
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(
            server.listRequestCount, 2, "冷启对账恰 1 次"
        )
        XCTAssertEqual(
            atFetchTime, paths(fixture),
            "对账发起时应已先渲染快照"
        )
        XCTAssertEqual(
            paths(cold.deliverables), paths(updated),
            "对账后与服务端逐项同序一致"
        )
    }

    func testColdStartWithoutSnapshotFetchesOnceFromNil()
        async
    {
        let server = FakeServer()
        server.list = fixture
        let store = makeStore()
        var atFetchTime: [Deliverable]?
        var fetchRan = false
        server.onListRequest = { @MainActor in
            fetchRan = true
            atFetchTime = store.deliverables
        }
        let outcome = await store.refresh(
            currentConfigKey: "http://server-a",
            fetch: server.fetch
        )
        XCTAssertEqual(outcome, .loaded)
        XCTAssertTrue(fetchRan)
        XCTAssertNil(atFetchTime, "无快照时拉取前为空")
        XCTAssertEqual(server.listRequestCount, 1)
        XCTAssertEqual(paths(store.deliverables), paths(fixture))
    }

    // MARK: - ② 删除：0 名单请求、失败回滚

    func testDeleteRemovesRowWithZeroListRequests() async {
        let server = FakeServer()
        server.list = fixture
        let key = "http://server-a"
        let store = makeStore()
        _ = await store.refresh(
            currentConfigKey: key, fetch: server.fetch
        )
        XCTAssertEqual(server.listRequestCount, 1)

        let target = fixture[1]
        let outcome = await store.delete(
            paths: [target.entry.path], perform: server.delete
        )
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(server.deleteRequestCount, 1)
        XCTAssertEqual(
            server.listRequestCount, 1, "删除不许发名单请求"
        )
        XCTAssertEqual(
            paths(store.deliverables),
            paths(fixture.filter { $0.entry.path != target.entry.path })
        )

        // 快照同步摘行：新店只播种即可见删除后名单
        let reseeded = makeStore()
        reseeded.seedFromSnapshotIfNeeded(currentConfigKey: key)
        XCTAssertEqual(
            paths(reseeded.deliverables), paths(store.deliverables)
        )
    }

    func testBatchDeleteRemovesAllWithZeroListRequests() async {
        let server = FakeServer()
        server.list = fixture
        let key = "http://server-a"
        let store = makeStore()
        _ = await store.refresh(
            currentConfigKey: key, fetch: server.fetch
        )
        let targets = [fixture[0], fixture[2]]
        let outcome = await store.delete(
            paths: targets.map(\.entry.path),
            perform: server.delete
        )
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(server.deleteRequestCount, 2)
        XCTAssertEqual(server.listRequestCount, 1)
        XCTAssertEqual(
            paths(store.deliverables),
            paths(fixture.filter {
                !targets.map(\.entry.path).contains($0.entry.path)
            })
        )
    }

    func testDeleteFailureRestoresRowAtOriginalIndex() async {
        let server = FakeServer()
        server.list = fixture
        let key = "http://server-a"
        let store = makeStore()
        _ = await store.refresh(
            currentConfigKey: key, fetch: server.fetch
        )
        server.deleteError = NSError(
            domain: "c4", code: 500
        )
        let outcome = await store.delete(
            paths: [fixture[1].entry.path],
            perform: server.delete
        )
        guard case .failed = outcome else {
            return XCTFail("删除失败应回 .failed，得 \(outcome)")
        }
        XCTAssertEqual(
            paths(store.deliverables), paths(fixture),
            "失败须原位回滚、整表复原"
        )
        // 快照同步恢复
        let reseeded = makeStore()
        reseeded.seedFromSnapshotIfNeeded(currentConfigKey: key)
        XCTAssertEqual(paths(reseeded.deliverables), paths(fixture))
    }

    // MARK: - ③ 换配置键：快照弃用、全量拉

    func testConfigKeyChangeDiscardsSnapshotAndMemory() async {
        let serverA = FakeServer()
        serverA.list = fixture
        let keyA = "http://server-a"
        let keyB = "http://server-b"
        let store = makeStore()
        _ = await store.refresh(
            currentConfigKey: keyA, fetch: serverA.fetch
        )
        XCTAssertEqual(paths(store.deliverables), paths(fixture))

        // 同店换键：内存里的 A 名单是外来货，fetch 发
        // 起时必须已清、且 B 键无快照可用＝从 nil 全
        // 量拉
        let serverB = FakeServer()
        serverB.list = [item("乙机文件.md", mtime: 10)]
        var atFetchTime: [Deliverable]?
        var fetchRan = false
        serverB.onListRequest = { @MainActor in
            fetchRan = true
            atFetchTime = store.deliverables
        }
        let outcome = await store.refresh(
            currentConfigKey: keyB, fetch: serverB.fetch
        )
        XCTAssertEqual(outcome, .loaded)
        XCTAssertTrue(fetchRan)
        XCTAssertNil(
            atFetchTime, "换键后拉取前不得残留 A 名单/快照"
        )
        XCTAssertEqual(serverB.listRequestCount, 1)
        XCTAssertEqual(
            paths(store.deliverables), paths(serverB.list)
        )

        // 新店只带 B 键播种：落盘快照已是 B 的（A 的
        // 已被覆写），拿 A 键播种应落空
        let probe = makeStore()
        probe.seedFromSnapshotIfNeeded(currentConfigKey: keyA)
        XCTAssertNil(probe.deliverables)
        probe.seedFromSnapshotIfNeeded(currentConfigKey: keyB)
        XCTAssertEqual(paths(probe.deliverables), paths(serverB.list))
    }

    // MARK: - ④ 对账等价与失败保旧

    func testReconciledMatchesFreshItemForItem() {
        let old = fixture
        var fresh = fixture
        fresh.removeAll { $0.entry.name == "方案.pptx" }
        fresh.append(item("新稿.docx", mtime: 700))
        // 改一条（同路径异 mtime＋异来源）
        fresh[0] = item("报告甲.md", mtime: 999, source: "附件")
        let merged = LibraryListStore.reconciled(
            old: old, fresh: fresh
        )
        XCTAssertEqual(merged.count, fresh.count)
        for (got, want) in zip(merged, fresh) {
            XCTAssertEqual(got.entry, want.entry)
            XCTAssertEqual(got.source, want.source)
        }
        // nil 旧集：原样采纳
        let fromNil = LibraryListStore.reconciled(
            old: nil, fresh: fresh
        )
        XCTAssertEqual(paths(fromNil), paths(fresh))
    }

    func testRefreshFailureKeepsSnapshotSeededList() async {
        let server = FakeServer()
        server.list = fixture
        let key = "http://server-a"
        let writer = makeStore()
        _ = await writer.refresh(
            currentConfigKey: key, fetch: server.fetch
        )
        server.listError = NSError(domain: "c4", code: 503)
        let cold = makeStore()
        let outcome = await cold.refresh(
            currentConfigKey: key, fetch: server.fetch
        )
        XCTAssertEqual(outcome, .keptAfterFailure)
        XCTAssertEqual(
            paths(cold.deliverables), paths(fixture),
            "对账失败保留快照名单不清屏"
        )
    }

    func testRefreshFailureWithoutDataReportsFailedNoData()
        async
    {
        let server = FakeServer()
        server.listError = NSError(domain: "c4", code: 503)
        let store = makeStore()
        let outcome = await store.refresh(
            currentConfigKey: "http://server-a",
            fetch: server.fetch
        )
        XCTAssertEqual(outcome, .failedNoData)
        XCTAssertNil(store.deliverables)
    }

    func testNoConfigSkipsFetch() async {
        let server = FakeServer()
        let store = makeStore()
        let outcome = await store.refresh(
            currentConfigKey: nil, fetch: server.fetch
        )
        XCTAssertEqual(outcome, .noConfig)
        XCTAssertEqual(server.listRequestCount, 0)
    }

    func testCorruptSnapshotIsIgnored() async {
        try? Data("not-json".utf8).write(to: snapshotURL)
        let server = FakeServer()
        server.list = fixture
        let store = makeStore()
        let outcome = await store.refresh(
            currentConfigKey: "http://server-a",
            fetch: server.fetch
        )
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(paths(store.deliverables), paths(fixture))
    }

    // MARK: - ⑤ 结构钉测（视图接线）

    func testViewWiringPins() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/OneDayApp/DeliverablesView.swift"
            )
        let src = try String(contentsOf: srcURL, encoding: .utf8)
        XCTAssertFalse(
            src.contains("@State private var deliverables"),
            "§369：名单不得再活在视图 @State"
        )
        XCTAssertTrue(
            src.contains("sharedLibraryListStore()"),
            "§369：名单应走 AppState 共享店"
        )
        XCTAssertEqual(
            src.components(separatedBy: "await collect()")
                .count - 1,
            2,
            "§369＋§416：collect 强制口只许上传完成、失败"
                + "重试两处触发；.task 读触发改走 collectIfNeeded "
                + "过新鲜度门（§416）；删除路径不许再整表重拉"
        )
        XCTAssertEqual(
            src.components(separatedBy: "await collectIfNeeded()")
                .count - 1,
            1,
            "§416：collectIfNeeded 读触发口只许 .task 一处"
        )
    }
}
