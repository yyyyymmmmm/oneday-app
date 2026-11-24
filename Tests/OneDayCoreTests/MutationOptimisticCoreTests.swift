import XCTest
@testable import OneDayCore

/// 乐观化副本助手与回写闸（§233）：状态/开关的
/// 本地先行副本只翻目标字段；抽屉归档/置顶回写服
/// 务端的闸口径（linked 放行、主线/合并桶/无绑定
/// 不放行）。G-6（2026-11-24）：里程碑乐观副本随
/// 概念移除，本文件的里程碑段已删
final class MutationOptimisticCoreTests: XCTestCase {

    private func goal() -> BridgeGoal {
        BridgeGoal(
            id: "g_1", title: "目标", note: "备注",
            entriesFingerprint: "fp_1",
            createdAt: 10, updatedAt: 20,
            status: .active, completedAt: nil, parentId: nil,
            category: nil, latestEntry: nil
        )
    }

    // MARK: - 目标状态乐观副本

    func testWithStatusCompletedSetsPlaceholderTimestamp() {
        let done = goal().withStatus(.completed, completedAt: 999)
        XCTAssertEqual(done.status, .completed)
        XCTAssertEqual(done.completedAt, 999)
        // 其余字段原样（指纹不被状态副本动）
        XCTAssertEqual(done.entriesFingerprint, "fp_1")
    }

    func testWithStatusReactivatedClearsTimestamp() {
        let done = goal().withStatus(.completed, completedAt: 999)
        let back = done.withStatus(.active, completedAt: nil)
        XCTAssertEqual(back.status, .active)
        XCTAssertNil(back.completedAt)
    }

    // MARK: - 监测开关乐观副本

    func testMonitorWithEnabledFlipsOnlyEnabled() {
        let monitor = BridgeMonitor(
            id: "mo_1", name: "盯梢", target: "example",
            scheduleText: "每天", cronJobId: "c_1", enabled: true,
            lastCheckedAt: nil, lastResult: nil, lastError: nil,
            unreadChanges: 3, latestChangeSummary: nil,
            latestChangeAt: nil, createdAt: 1, updatedAt: 2,
            goalId: nil
        )
        let off = monitor.withEnabled(false)
        XCTAssertFalse(off.enabled)
        XCTAssertEqual(off.name, "盯梢")
        XCTAssertEqual(off.unreadChanges, 3)
        XCTAssertTrue(off.withEnabled(true).enabled)
    }

    // MARK: - 回写闸矩阵（SideChatLink.mayWriteThroughToServer）

    func testGateAllowsOrdinaryLinkedSession() {
        XCTAssertTrue(
            SideChatLink.mayWriteThroughToServer(
                sessionID: "srv-abc", mainSessionID: "srv-main"
            )
        )
        XCTAssertTrue(
            SideChatLink.mayWriteThroughToServer(
                sessionID: "srv-abc", mainSessionID: nil
            )
        )
    }

    func testGateRejectsMissingBinding() {
        XCTAssertFalse(
            SideChatLink.mayWriteThroughToServer(
                sessionID: nil, mainSessionID: "srv-main"
            )
        )
        XCTAssertFalse(
            SideChatLink.mayWriteThroughToServer(
                sessionID: "", mainSessionID: "srv-main"
            )
        )
    }

    func testGateRejectsMergeBuckets() {
        for bucket in ["api-592647b9ae21ec54", "api-e8c923beeaebed9c"] {
            XCTAssertFalse(
                SideChatLink.mayWriteThroughToServer(
                    sessionID: bucket, mainSessionID: "srv-main"
                ),
                bucket
            )
        }
    }

    func testGateRejectsMainlineItself() {
        XCTAssertFalse(
            SideChatLink.mayWriteThroughToServer(
                sessionID: "srv-main", mainSessionID: "srv-main"
            )
        )
        XCTAssertFalse(
            SideChatLink.mayWriteThroughToServer(
                sessionID: "oneday-main-xyz", mainSessionID: nil
            )
        )
    }
}
