import XCTest
import OneDayCore
@testable import OneDayApp

/// 平台用户配对状态机钉测（DESIGN §359）：操作口注
/// 入脚本，只验状态机本身——加载三态、写后整表回
/// 读对账（确认/未确认）、失败分型（404 良性刷新/
/// 429 锁定/401 未登录）、旧版无编号条目结构上批不
/// 了。端点真形态在 OneDayCoreTests.PairingContract-
/// Tests 钉
@MainActor
final class PairingStoreTests: XCTestCase {

    // MARK: - 脚本与夹具

    private final class Script {
        var listQueue: [PairingListResponse] = []
        var listError: HermesError?
        var approveError: HermesError?
        var revokeError: HermesError?
        var clearError: HermesError?
        var clearedCount = 0
        var approveCalls = 0
        var revokeCalls = 0
        var clearCalls = 0

        func operations() -> PairingOperations {
            PairingOperations(
                list: {
                    if let err = self.listError { throw err }
                    if self.listQueue.count > 1 {
                        return self.listQueue.removeFirst()
                    }
                    return self.listQueue.first
                        ?? PairingListResponse(pending: [], approved: [])
                },
                approve: { _ in
                    self.approveCalls += 1
                    if let err = self.approveError { throw err }
                    return try JSONDecoder().decode(
                        PairingApproveReceipt.self,
                        from: Data(#"{"ok": true, "user": {"user_id": "424242", "user_name": "小明"}}"#.utf8)
                    )
                },
                revoke: { _ in
                    self.revokeCalls += 1
                    if let err = self.revokeError { throw err }
                },
                clearPending: {
                    self.clearCalls += 1
                    if let err = self.clearError { throw err }
                    return try JSONDecoder().decode(
                        PairingClearPendingReceipt.self,
                        from: Data(#"{"ok": true, "cleared": \#(self.clearedCount)}"#.utf8)
                    )
                }
            )
        }
    }

    private var pendingMing: PairingPendingEntry {
        PairingPendingEntry(
            platform: "telegram", requestID: "req-1",
            userID: "424242", userName: "小明", ageMinutes: 5
        )
    }

    private var approvedMing: PairingApprovedEntry {
        PairingApprovedEntry(
            platform: "telegram", userID: "424242",
            userName: "小明", approvedAt: "2026-11-22T09:00:00Z"
        )
    }

    private func makeSummaryStore() -> PairingSummaryStore {
        let suite = UserDefaults(
            suiteName: "pairing-tests-\(UUID().uuidString)"
        )!
        return PairingSummaryStore(defaults: suite)
    }

    private func readyList(_ store: PairingStore) -> PairingListResponse? {
        if case .ready(let response) = store.state { return response }
        return nil
    }

    // MARK: - 加载

    func testLoadSuccessSetsReadyAndSavesPendingCount() async {
        let summaryStore = makeSummaryStore()
        let store = PairingStore(summaryStore: summaryStore)
        let script = Script()
        script.listQueue = [
            PairingListResponse(pending: [pendingMing], approved: [])
        ]

        await store.load(
            operations: script.operations(), serverBase: "https://a.test"
        )

        XCTAssertEqual(readyList(store)?.pending.count, 1)
        XCTAssertEqual(
            summaryStore.pendingCount(for: "https://a.test"), 1
        )
        // 按服务器隔离：别的服务器没有留痕（未知，不是 0）
        XCTAssertNil(summaryStore.pendingCount(for: "https://b.test"))
    }

    func testLoadSessionExpiredShowsNotLoggedIn() async {
        let store = PairingStore(summaryStore: makeSummaryStore())
        let script = Script()
        script.listError = .sessionExpired

        await store.load(
            operations: script.operations(), serverBase: "https://a.test"
        )

        guard case .notLoggedIn = store.state else {
            return XCTFail("401 终局应落未登录态，实际 \(store.state)")
        }
    }

    func testLoadFailureShowsFailed() async {
        let store = PairingStore(summaryStore: makeSummaryStore())
        let script = Script()
        script.listError = .unexpectedStatus(endpoint: "配对", status: 500)

        await store.load(
            operations: script.operations(), serverBase: "https://a.test"
        )

        guard case .failed = store.state else {
            return XCTFail("读失败应落 failed，实际 \(store.state)")
        }
    }

    // MARK: - 批准（回读对账）

    func testApproveConfirmedByReadback() async {
        let store = PairingStore(summaryStore: makeSummaryStore())
        let script = Script()
        script.listQueue = [
            PairingListResponse(pending: [pendingMing], approved: []),
            PairingListResponse(pending: [], approved: [approvedMing]),
        ]
        await store.load(
            operations: script.operations(), serverBase: "https://a.test"
        )

        await store.approve(
            pendingMing, operations: script.operations(),
            serverBase: "https://a.test"
        )

        XCTAssertEqual(script.approveCalls, 1)
        XCTAssertEqual(readyList(store)?.approved.count, 1)
        XCTAssertTrue(readyList(store)?.pending.isEmpty ?? false)
        XCTAssertNil(store.note)
    }

    func testApproveUnconfirmedWhenReadbackStillPending() async {
        let store = PairingStore(summaryStore: makeSummaryStore())
        let script = Script()
        // 回读仍是原清单（批准没生效）——不许报成功
        script.listQueue = [
            PairingListResponse(pending: [pendingMing], approved: [])
        ]
        await store.load(
            operations: script.operations(), serverBase: "https://a.test"
        )

        await store.approve(
            pendingMing, operations: script.operations(),
            serverBase: "https://a.test"
        )

        XCTAssertNotNil(store.note)
        XCTAssertTrue(store.noteIsProblem)
        XCTAssertEqual(readyList(store)?.pending.count, 1)
    }

    func testApproveGoneIsBenignAndRefreshes() async {
        let store = PairingStore(summaryStore: makeSummaryStore())
        let script = Script()
        script.listQueue = [
            PairingListResponse(pending: [pendingMing], approved: []),
            PairingListResponse(pending: [], approved: []),
        ]
        script.approveError = .unexpectedStatus(endpoint: "批准", status: 404)
        await store.load(
            operations: script.operations(), serverBase: "https://a.test"
        )

        await store.approve(
            pendingMing, operations: script.operations(),
            serverBase: "https://a.test"
        )

        XCTAssertNotNil(store.note)
        XCTAssertFalse(store.noteIsProblem)
        XCTAssertTrue(readyList(store)?.pending.isEmpty ?? false)
    }

    func testApproveLockedShowsProblemNote() async {
        let store = PairingStore(summaryStore: makeSummaryStore())
        let script = Script()
        script.listQueue = [
            PairingListResponse(pending: [pendingMing], approved: [])
        ]
        script.approveError = .unexpectedStatus(endpoint: "批准", status: 429)
        await store.load(
            operations: script.operations(), serverBase: "https://a.test"
        )

        await store.approve(
            pendingMing, operations: script.operations(),
            serverBase: "https://a.test"
        )

        XCTAssertNotNil(store.note)
        XCTAssertTrue(store.noteIsProblem)
        // 锁定不改清单：条目仍在待批列
        XCTAssertEqual(readyList(store)?.pending.count, 1)
    }

    /// 旧版无编号条目：批准动作结构上不发出（canApprove
    /// 为假时 store 直接返回，不打服务端）
    func testApproveSkipsLegacyEntryWithoutRequestID() async {
        let store = PairingStore(summaryStore: makeSummaryStore())
        let script = Script()
        let legacy = PairingPendingEntry(
            platform: "telegram", requestID: "",
            userID: "777", userName: "", ageMinutes: 3
        )
        script.listQueue = [
            PairingListResponse(pending: [legacy], approved: [])
        ]
        await store.load(
            operations: script.operations(), serverBase: "https://a.test"
        )

        await store.approve(
            legacy, operations: script.operations(),
            serverBase: "https://a.test"
        )

        XCTAssertEqual(script.approveCalls, 0)
    }

    // MARK: - 撤销与清待批

    func testRevokeConfirmedByReadback() async {
        let store = PairingStore(summaryStore: makeSummaryStore())
        let script = Script()
        script.listQueue = [
            PairingListResponse(pending: [], approved: [approvedMing]),
            PairingListResponse(pending: [], approved: []),
        ]
        await store.load(
            operations: script.operations(), serverBase: "https://a.test"
        )

        await store.revoke(
            approvedMing, operations: script.operations(),
            serverBase: "https://a.test"
        )

        XCTAssertEqual(script.revokeCalls, 1)
        XCTAssertTrue(readyList(store)?.approved.isEmpty ?? false)
        XCTAssertNil(store.note)
    }

    func testClearPendingReportsClearedCount() async {
        let store = PairingStore(summaryStore: makeSummaryStore())
        let script = Script()
        let second = PairingPendingEntry(
            platform: "whatsapp", requestID: "req-2",
            userID: "8613", userName: "阿华", ageMinutes: 30
        )
        script.listQueue = [
            PairingListResponse(pending: [pendingMing, second], approved: []),
            PairingListResponse(pending: [], approved: []),
        ]
        script.clearedCount = 2
        await store.load(
            operations: script.operations(), serverBase: "https://a.test"
        )

        await store.clearPending(
            operations: script.operations(), serverBase: "https://a.test"
        )

        XCTAssertEqual(script.clearCalls, 1)
        XCTAssertTrue(readyList(store)?.pending.isEmpty ?? false)
        XCTAssertNotNil(store.note)
        XCTAssertTrue(store.note?.contains("2") ?? false)
        XCTAssertFalse(store.noteIsProblem)
    }
}
