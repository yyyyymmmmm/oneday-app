import OneDayCore
import XCTest
@testable import OneDayApp

/// 轻动作乐观化时序（§232）：各 Store 的乐观落点
/// 同步生效、失败恢复原状、无连接时不假动只留提
/// 示——网络往返段由接缝两侧的同步原语钉住（翻面
/// ＝接缝调用后立即读呈现；恢复＝以原值整行放回）
@MainActor
final class MutationOptimisticTests: XCTestCase {

    // MARK: - 件一 动态点赞（FeedStore）

    private func feedPost(
        id: String, likedAt: Double? = nil, readAt: Double? = nil
    ) -> BridgeFeedPost {
        BridgeFeedPost(
            id: id, kind: .research, title: "帖", body: "文",
            createdAt: 100, readAt: readAt, likedAt: likedAt
        )
    }

    func testOptimisticLikeFlipsImmediatelyOnlyTarget() {
        let store = FeedStore()
        store.installLoadedPosts([
            feedPost(id: "p1"), feedPost(id: "p2", likedAt: 5),
        ])
        store.applyOptimisticLike(postID: "p1", liked: true, at: 42)
        XCTAssertEqual(store.post(id: "p1")?.likedAt, 42)
        XCTAssertEqual(store.post(id: "p2")?.likedAt, 5)

        store.applyOptimisticLike(postID: "p1", liked: false, at: 43)
        XCTAssertNil(store.post(id: "p1")?.likedAt)
    }

    func testLikeFailureRestorePutsOriginalBack() {
        let store = FeedStore()
        let original = feedPost(id: "p1")
        store.installLoadedPosts([original])
        store.applyOptimisticLike(postID: "p1", liked: true, at: 42)
        store.restorePost(original)
        XCTAssertEqual(store.post(id: "p1"), original)
    }

    func testLikeSettleReplacesWithServerShape() {
        let store = FeedStore()
        store.installLoadedPosts([feedPost(id: "p1")])
        store.applyOptimisticLike(postID: "p1", liked: true, at: 42)
        store.settlePost(feedPost(id: "p1", likedAt: 77))
        XCTAssertEqual(store.post(id: "p1")?.likedAt, 77)
    }

    // MARK: - 件五 动态已读（FeedStore）

    func testFeedLocalReadFlipsImmediatelyAndIdempotent() {
        let store = FeedStore()
        store.installLoadedPosts([feedPost(id: "p1")])
        store.applyLocalRead(postID: "p1", at: 10)
        XCTAssertEqual(store.post(id: "p1")?.readAt, 10)
        store.applyLocalRead(postID: "p1", at: 20)
        XCTAssertEqual(store.post(id: "p1")?.readAt, 10)
    }

    // MARK: - 件二/件四 目标（GoalsStore）

    private func goal() -> BridgeGoal {
        BridgeGoal(
            id: "g1", title: "目标", note: "",
            milestones: [
                BridgeMilestone(id: "m1", title: "一", done: false),
            ],
            createdAt: 1, updatedAt: 2
        )
    }

    func testGoalApplyReplacesRowImmediately() {
        let store = GoalsStore()
        store.installLoadedGoals([goal()])
        store.applyGoal(goal().withMilestoneDone(id: "m1", done: true))
        XCTAssertEqual(
            store.goal(id: "g1")?.milestones.first?.done, true
        )
        store.applyGoal(goal().withStatus(.completed, completedAt: 9))
        XCTAssertEqual(store.goal(id: "g1")?.status, .completed)
        XCTAssertEqual(store.goal(id: "g1")?.completedAt, 9)
    }

    func testToggleMilestoneWithoutConfigDoesNotFlip() async {
        let store = GoalsStore()
        store.installLoadedGoals([goal()])
        let ok = await store.toggleMilestone(
            appState: AppState(), goalID: "g1", milestoneID: "m1"
        )
        XCTAssertFalse(ok)
        XCTAssertEqual(
            store.goal(id: "g1")?.milestones.first?.done, false
        )
        XCTAssertNotNil(store.notes["g1"])
    }

    func testSetStatusWithoutConfigDoesNotFlip() async {
        let store = GoalsStore()
        store.installLoadedGoals([goal()])
        let ok = await store.setStatus(
            appState: AppState(), goalID: "g1", status: .completed
        )
        XCTAssertFalse(ok)
        XCTAssertEqual(store.goal(id: "g1")?.status, .active)
        XCTAssertNotNil(store.notes["g1"])
    }

    // MARK: - 件三 点子放下（IdeasStore）

    private func idea(id: String) -> BridgeIdea {
        BridgeIdea(
            id: id, title: id, detail: "", goalId: nil,
            createdAt: 100, status: .pending, category: "interest"
        )
    }

    func testDismissOptimisticRemovalAndRestore() {
        let store = IdeasStore()
        store.installLoadedIdeas([idea(id: "i1"), idea(id: "i2")])
        let removed = store.applyOptimisticDismiss(ideaID: "i1")
        XCTAssertEqual(removed?.id, "i1")
        XCTAssertEqual(store.pendingIdeas.map(\.id), ["i2"])

        store.restoreDismissed(removed!)
        XCTAssertEqual(
            Set(store.pendingIdeas.map(\.id)), ["i1", "i2"]
        )
        // 恢复幂等：同一条再放不重复
        store.restoreDismissed(removed!)
        XCTAssertEqual(store.pendingIdeas.count, 2)
    }

    func testDismissWithoutConfigKeepsCard() async {
        let store = IdeasStore()
        let target = idea(id: "i1")
        store.installLoadedIdeas([target])
        await store.dismiss(appState: AppState(), idea: target)
        XCTAssertEqual(store.pendingIdeas.map(\.id), ["i1"])
        XCTAssertNotNil(store.notes["i1"])
    }

    // MARK: - 件四 监测开关（MonitorsStore）

    private func monitor(enabled: Bool) -> BridgeMonitor {
        BridgeMonitor(
            id: "mo1", name: "盯梢", target: "", scheduleText: "",
            cronJobId: nil, enabled: enabled, lastCheckedAt: nil,
            lastResult: nil, lastError: nil, unreadChanges: 0,
            latestChangeSummary: nil, latestChangeAt: nil,
            createdAt: 1, updatedAt: 2, goalId: nil
        )
    }

    func testMonitorApplyFlipsImmediately() {
        let store = MonitorsStore()
        store.installLoadedMonitors([monitor(enabled: true)])
        store.applyMonitor(monitor(enabled: false))
        XCTAssertEqual(store.monitor(id: "mo1")?.enabled, false)
    }

    func testSetEnabledWithoutConfigDoesNotFlip() async {
        let store = MonitorsStore()
        store.installLoadedMonitors([monitor(enabled: true)])
        await store.setEnabled(
            appState: AppState(), monitorID: "mo1", enabled: false
        )
        XCTAssertEqual(store.monitor(id: "mo1")?.enabled, true)
        XCTAssertNotNil(store.notes["mo1"])
    }

    // MARK: - 件五 通知已读（OverviewBridgeStore）

    private func notification(id: String, read: Bool) -> OverviewNotification {
        OverviewNotification(
            id: id, kind: "info", title: "题", body: "文",
            createdAt: "2026-11-14T00:00:00+08:00", read: read
        )
    }

    func testOverviewLocalReadFlipsImmediatelyAndIdempotent() {
        let store = OverviewBridgeStore()
        store.installLoadedNotifications([
            notification(id: "n1", read: false),
            notification(id: "n2", read: false),
        ])
        XCTAssertTrue(store.applyLocalRead(id: "n1"))
        XCTAssertEqual(
            store.notifications.map(\.read), [true, false]
        )
        XCTAssertFalse(store.applyLocalRead(id: "n1"))
        XCTAssertFalse(store.applyLocalRead(id: "nope"))
    }

    func testOverviewMarkReadAppliesLocallyWithoutConfig() async {
        let store = OverviewBridgeStore()
        store.installLoadedNotifications([
            notification(id: "n1", read: false),
        ])
        await store.markRead(appState: AppState(), id: "n1")
        XCTAssertEqual(store.notifications.first?.read, true)
    }

    func testOverviewMarkAllReadAppliesLocallyWithoutConfig() async {
        let store = OverviewBridgeStore()
        store.installLoadedNotifications([
            notification(id: "n1", read: false),
            notification(id: "n2", read: false),
        ])
        let ok = await store.markAllRead(appState: AppState())
        XCTAssertTrue(ok)
        XCTAssertEqual(
            store.notifications.map(\.read), [true, true]
        )
    }
}
