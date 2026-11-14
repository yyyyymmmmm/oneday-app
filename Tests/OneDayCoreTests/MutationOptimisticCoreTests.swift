import XCTest
@testable import OneDayCore

/// 乐观化副本助手与回写闸（§232）：里程碑/状态/
/// 开关的本地先行副本只翻目标字段；抽屉归档/置顶
/// 回写服务端的闸口径（linked 放行、主线/合并桶/
/// 无绑定不放行）
final class MutationOptimisticCoreTests: XCTestCase {

    private func goal(
        milestones: [BridgeMilestone] = [
            BridgeMilestone(id: "m_1", title: "a", done: false),
            BridgeMilestone(id: "m_2", title: "b", done: true),
        ]
    ) -> BridgeGoal {
        BridgeGoal(
            id: "g_1", title: "目标", note: "备注",
            milestones: milestones, createdAt: 10, updatedAt: 20,
            status: .active, completedAt: nil, parentId: nil,
            category: nil, latestEntry: nil
        )
    }

    // MARK: - 里程碑乐观副本

    func testWithMilestoneDoneFlipsOnlyTarget() {
        let flipped = goal().withMilestoneDone(id: "m_1", done: true)
        XCTAssertEqual(
            flipped.milestones.map(\.done), [true, true]
        )
        XCTAssertEqual(flipped.title, "目标")
        XCTAssertEqual(flipped.updatedAt, 20)
        XCTAssertEqual(flipped.status, .active)
    }

    func testWithMilestoneDoneUnknownIDIsNoOp() {
        let goal = goal()
        XCTAssertEqual(
            goal.withMilestoneDone(id: "nope", done: true), goal
        )
    }

    // MARK: - 目标状态乐观副本

    func testWithStatusCompletedSetsPlaceholderTimestamp() {
        let done = goal().withStatus(.completed, completedAt: 999)
        XCTAssertEqual(done.status, .completed)
        XCTAssertEqual(done.completedAt, 999)
        XCTAssertEqual(done.milestones.count, 2)
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
