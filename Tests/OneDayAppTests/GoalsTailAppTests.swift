import OneDayCore
import XCTest
@testable import OneDayApp

/// GD-2 归组时序（总纲口径）：乐观落点同步摘行、
/// 失败整行放回归位、无连接时不假动只留提示——
/// 网络往返段由接缝两侧的同步原语钉住（与
/// MutationOptimisticTests 同纪律）
@MainActor
final class GoalsTailAppTests: XCTestCase {

    private func row(
        _ id: String, createdAt: Double, origin: BridgeUngroupedTask.Origin = .chat
    ) -> BridgeUngroupedTask {
        BridgeUngroupedTask(
            taskId: id, title: "任务 \(id)", status: "todo",
            bucket: "waiting", origin: origin,
            ideaId: origin == .adopted ? "i_\(id)" : nil,
            ownerSessionId: origin == .chat ? "s_1" : nil,
            createdAt: createdAt, updatedAt: nil
        )
    }

    func testInstallUngroupedReplacesFace() {
        let store = GoalsStore()
        store.installUngroupedTasks([row("t1", createdAt: 30)])
        XCTAssertEqual(store.ungroupedTasks.map(\.taskId), ["t1"])
        store.installUngroupedTasks([])
        XCTAssertTrue(store.ungroupedTasks.isEmpty)
    }

    func testOptimisticUngroupRemovesOnlyTargetImmediately() {
        let store = GoalsStore()
        store.installUngroupedTasks([
            row("t1", createdAt: 30), row("t2", createdAt: 20),
        ])
        let taken = store.applyOptimisticUngroup(taskID: "t1")
        XCTAssertEqual(taken?.taskId, "t1")
        XCTAssertEqual(store.ungroupedTasks.map(\.taskId), ["t2"])
    }

    func testOptimisticUngroupUnknownTaskIsNoOp() {
        let store = GoalsStore()
        store.installUngroupedTasks([row("t1", createdAt: 30)])
        XCTAssertNil(store.applyOptimisticUngroup(taskID: "t_x"))
        XCTAssertEqual(store.ungroupedTasks.count, 1)
    }

    func testRestorePutsRowBackInCreatedOrder() {
        let store = GoalsStore()
        store.installUngroupedTasks([
            row("t1", createdAt: 30), row("t3", createdAt: 10),
        ])
        store.restoreUngrouped(row("t2", createdAt: 20))
        XCTAssertEqual(
            store.ungroupedTasks.map(\.taskId), ["t1", "t2", "t3"]
        )
    }

    func testRestoreIsIdempotent() {
        let store = GoalsStore()
        let original = row("t1", createdAt: 30)
        store.installUngroupedTasks([original])
        store.restoreUngrouped(original)
        XCTAssertEqual(store.ungroupedTasks, [original])
    }

    func testAssignWithoutConfigKeepsRowAndNotes() async {
        let store = GoalsStore()
        store.installUngroupedTasks([row("t1", createdAt: 30)])
        await store.assignUngroupedTask(
            appState: AppState(), taskID: "t1", toGoalID: "g1"
        )
        XCTAssertEqual(store.ungroupedTasks.map(\.taskId), ["t1"])
        XCTAssertNotNil(store.ungroupedNote)
    }
}
