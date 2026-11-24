import XCTest

@testable import OneDayCore

/// §454 通知入账分级钉测：前台会话正常完成不入账、
/// 待批两处同数（角标待批轴与快照逐字同值——枢纽
/// 审核格与铃铛角标同出写闸待批一账：桥 _overview
/// 的 pendingApprovals 取写闸 /status 计数、枢纽
/// gateClient.pendingList 取同一写闸 /pending 名
/// 单，本包不新建第三计数）、二级聚合窗链式合并。
/// §459 增补：自有会话失败与完成同档不入账（非自
/// 有失败维持一级）、自有识别归一（集合命中∨自
/// 铸前缀）、真机同构用例（真实 refId 形态＋集合
/// 缺条/空集）
final class NotificationIntakePolicyTests: XCTestCase {

    private func item(
        _ id: String, kind: String, refId: String? = nil,
        read: Bool = false,
        createdAt: String = "2026-11-24T03:00:00Z"
    ) -> OverviewNotification {
        OverviewNotification(
            id: id, kind: kind, title: "t", body: "b",
            createdAt: createdAt, read: read, refId: refId
        )
    }

    private let mine: Set<String> = ["sess-mine"]

    // MARK: - 三级：前台会话正常完成不入账

    func testUserSessionCompletionIsSuppressed() {
        let entry = item(
            "run-1", kind: "task_completed", refId: "sess-mine"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: mine
            ),
            .suppressed
        )
        XCTAssertEqual(
            NotificationIntakePolicy.suppressedIDs(
                notifications: [entry], userSessionIDs: mine
            ),
            ["run-1"]
        )
    }

    func testBackgroundCompletionIsKeptAsAggregatable() {
        let entry = item(
            "run-2", kind: "task_completed", refId: "sess-cron-9"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: mine
            ),
            .aggregatable
        )
        XCTAssertTrue(
            NotificationIntakePolicy.suppressedIDs(
                notifications: [entry], userSessionIDs: mine
            ).isEmpty
        )
    }

    func testCompletionWithoutRefIdIsKept() {
        // 正向识别不成立就不压：无 refId 的完成宁可
        // 留底，不许错杀
        let entry = item("run-3", kind: "task_completed")
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: mine
            ),
            .aggregatable
        )
    }

    func testEmptySessionChainSuppressesNothing() {
        // 非自铸形态的 refId 只认集合键：集合为空
        // （调用方给不出名单）时不压——归一后仍成
        // 立（自铸前缀键是另一键、见真机同构例）
        let entry = item(
            "run-4", kind: "task_completed", refId: "sess-mine"
        )
        XCTAssertTrue(
            NotificationIntakePolicy.suppressedIDs(
                notifications: [entry], userSessionIDs: []
            ).isEmpty
        )
    }

    // MARK: - §459 真机同构：自有终态不入账（完成＋失败）

    /// 真机实证形态（2026-11-24 05:57 生产实查）：
    /// 用户本人会话的完成 run——refId＝网关 runs
    /// .session_id 原值（oneday-side-<uuid>），本
    /// 机线程表快照缺该条（集合不含/为空）时 §454
    /// 判据漏成二级；归一后凭自铸前缀键判自有
    func testRealFormCompletionSuppressedWithoutSetHit() {
        let entry = item(
            "run-run_5854ae82",
            kind: "task_completed",
            refId: "oneday-side-59aed275-2cc0-42d7-8028-5443453b83a3"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: []
            ),
            .suppressed
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: mine
            ),
            .suppressed
        )
        XCTAssertEqual(
            NotificationIntakePolicy.suppressedIDs(
                notifications: [entry], userSessionIDs: []
            ),
            ["run-run_5854ae82"]
        )
    }

    /// 真机实证形态（2026-11-24 05:47 生产实查）：
    /// 用户本人会话的失败 run（run_9791273a）——
    /// §454 旧口径一律一级即时弹铃铛；§459 起自
    /// 有失败与完成同档：不即时、不计未读、不入账
    func testRealFormFailureSuppressedForOwnSession() {
        let entry = item(
            "run-run_9791273a",
            kind: "run_failed",
            refId: "oneday-side-b6238dda-8ce5-4f24-8e7e-e8e93ec339a4"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: []
            ),
            .suppressed
        )
        XCTAssertEqual(
            NotificationIntakePolicy.suppressedIDs(
                notifications: [entry], userSessionIDs: []
            ),
            ["run-run_9791273a"]
        )
    }

    func testOwnSessionFailureSuppressedViaSetHit() {
        let failed = item(
            "run-5", kind: "run_failed", refId: "sess-mine"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: failed, userSessionIDs: mine
            ),
            .suppressed
        )
        // error 信号同口径（与 NotificationTier 分类同源）
        let errored = item(
            "run-6", kind: "task_error", refId: "sess-mine"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: errored, userSessionIDs: mine
            ),
            .suppressed
        )
    }

    func testMainSessionCompletionSuppressedByPrefix() {
        let entry = item(
            "run-7", kind: "task_completed",
            refId: "oneday-main-59aed275-2cc0-42d7-8028-5443453b83a3"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: []
            ),
            .suppressed
        )
    }

    // MARK: - 一级：非自有失败必入账、待批与回执逐条在账

    func testExternalFailureIsImmediate() {
        // 服务端自跑 run（session_id 为 run id 自指
        // 形，生产实查形态）：非自有，失败维持一级
        let selfKeyed = item(
            "run-8", kind: "run_failed",
            refId: "run_4c56cfc32b104f6bbcd270e22742798b"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: selfKeyed, userSessionIDs: mine
            ),
            .immediate
        )
        // 外部/cron 会话失败同口径
        let cron = item(
            "run-9", kind: "run_failed", refId: "sess-cron-9"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: cron, userSessionIDs: mine
            ),
            .immediate
        )
        // 无 refId 的失败认不出归属，维持一级不压
        let anon = item("run-10", kind: "run_failed")
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: anon, userSessionIDs: mine
            ),
            .immediate
        )
    }

    func testSelfKeyedCompletionStaysAggregatable() {
        // 服务端自跑 run 的完成不是用户会话完成：
        // 留底二级，不许被前缀键误压
        let entry = item(
            "run-11", kind: "task_completed",
            refId: "run_4c56cfc32b104f6bbcd270e22742798b"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: []
            ),
            .aggregatable
        )
    }

    func testApprovalKindsAreImmediate() {
        let pending = item(
            "wgp-1", kind: "approval_pending", refId: "mem_1"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: pending, userSessionIDs: mine
            ),
            .immediate
        )
        let receipt = item(
            "dec-1", kind: "write_gate_decision", refId: "mem_1"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: receipt, userSessionIDs: mine
            ),
            .immediate
        )
    }

    func testMonitorChangeIsAggregatable() {
        let change = item(
            "mon-1", kind: "monitor_change", refId: "watch-1"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: change, userSessionIDs: mine
            ),
            .aggregatable
        )
    }

    // MARK: - 待批同数：角标待批轴＝快照原值

    func testBadgePendingComponentIsSnapshotVerbatim() {
        let snapshot = OverviewSnapshot(
            hermesUp: true, activeSessions: 0,
            pendingApprovals: 3, unreadNotifications: 0,
            generatedAt: ""
        )
        XCTAssertEqual(OverviewBadge.count(snapshot: snapshot), 3)
        let mixed = OverviewSnapshot(
            hermesUp: true, activeSessions: 0,
            pendingApprovals: 3, unreadNotifications: 2,
            generatedAt: ""
        )
        XCTAssertEqual(OverviewBadge.count(snapshot: mixed), 5)
    }

    // MARK: - 二级聚合：同类短窗链式合并

    func testRowsAggregateBurstWithinWindow() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m3", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
            item("m2", kind: "monitor_change",
                 createdAt: "2026-11-24T03:07:00Z"),
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T03:02:00Z"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].items.count, 3)
        XCTAssertEqual(rows[0].lead.id, "m3")
        XCTAssertTrue(rows[0].isAggregate)
    }

    func testRowsChainAcrossLongSpanBySmallGaps() {
        // 相邻间隔各 8 分钟（窗 10 分钟）：链式合并
        // 跨度 16 分钟仍并一行——突发以相邻密度判，
        // 不以总跨度判
        let rows = NotificationIntakePolicy.rows(items: [
            item("m3", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
            item("m2", kind: "monitor_change",
                 createdAt: "2026-11-24T03:02:00Z"),
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T02:54:00Z"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].items.count, 3)
    }

    func testRowsSplitWhenGapExceedsWindow() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m2", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T02:50:00Z"),
        ])
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(rows[0].isAggregate)
        XCTAssertFalse(rows[1].isAggregate)
    }

    func testRowsImmediateBreaksChain() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m2", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
            item("f1", kind: "run_failed",
                 createdAt: "2026-11-24T03:08:00Z"),
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T03:06:00Z"),
        ])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1].lead.id, "f1")
    }

    func testRowsDifferentKindsDoNotMerge() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
            item("r1", kind: "task_completed",
                 refId: "sess-cron-9",
                 createdAt: "2026-11-24T03:09:00Z"),
        ])
        XCTAssertEqual(rows.count, 2)
    }

    func testRowsSingleAggregatableStaysSingle() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].isAggregate)
        XCTAssertEqual(rows[0].lead.id, "m1")
    }

    func testRowsUnreadPropagatesToAggregate() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m2", kind: "monitor_change", read: true,
                 createdAt: "2026-11-24T03:10:00Z"),
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T03:08:00Z"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].hasUnread)
    }
}
