import Foundation
import OneDayCore

/// 目标列表派生快照（第 3 项，照抄 FeedList-
/// Snapshot 模式）：GoalBoard.grouped 一次算齐、
/// body 重跑（展开/折叠/sheet/轮询无变化等）
/// 直接复用，不再每帧重排全表。
struct GoalListSnapshot: Equatable {
    let active: [BridgeGoal]
    let completed: [BridgeGoal]

    static func make(goals: [BridgeGoal]) -> GoalListSnapshot {
        let grouped = GoalBoard.grouped(goals)
        return GoalListSnapshot(
            active: grouped.active,
            completed: grouped.completed
        )
    }
}

/// 目标派生快照缓存：按目标数组指纹缓存，输入未
/// 变直接复用。
final class GoalSnapshotCache {
    private var lastGoals: [BridgeGoal]?
    private var lastSnapshot: GoalListSnapshot?

    private(set) var revision = 0

    func snapshot(goals: [BridgeGoal]) -> GoalListSnapshot {
        if let lastSnapshot, lastGoals == goals {
            return lastSnapshot
        }
        let made = GoalListSnapshot.make(goals: goals)
        lastGoals = goals
        lastSnapshot = made
        revision += 1
        return made
    }
}
