import XCTest
@testable import OneDayCore

/// §165 审批锚点包的 Core 钉测：桥 anchor 字段解码、
/// 物化规划（冻结/回溯窗/去重）、锚定行呈现态、点达
/// 解析与通知路由。真源判定全钉在纯函数层，View 不
/// 许各自拼——与 §123 闭环包同纪律。
final class ApprovalAnchorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func pendingRecord(
        id: String, subsystem: WriteGateSubsystem = .skills,
        createdAt: Date?, anchor: WriteGateAnchor?
    ) -> WriteGateRecord {
        WriteGateRecord(
            id: id, subsystem: subsystem, action: "edit",
            summary: "摘要", origin: "background_review",
            createdAt: createdAt, anchor: anchor
        )
    }

    private func decisionRecord(
        id: String, subsystem: WriteGateSubsystem = .skills,
        decidedAt: Date?, createdAt: Date? = nil,
        anchor: WriteGateAnchor?
    ) -> WriteGateDecisionRecord {
        WriteGateDecisionRecord(
            id: id, subsystem: subsystem, action: "edit",
            summary: "摘要", origin: "background_review",
            decision: "approved", decidedAt: decidedAt,
            anchor: anchor, createdAt: createdAt
        )
    }

    // MARK: - 桥字段解码（1.0.19 出口形态）

    func testPendingAnchorDecodes() throws {
        let json = """
        {"id":"20977b0a","subsystem":"skills","action":"edit",\
        "summary":"s","origin":"background_review",\
        "created_at":"2026-11-11T04:25:40Z",\
        "anchor":{"sessionId":"oneday-side-c60d7bfd","tier":"T3"}}
        """
        let record = try JSONDecoder().decode(
            WriteGateRecord.self, from: Data(json.utf8)
        )
        XCTAssertEqual(record.anchor?.sessionId, "oneday-side-c60d7bfd")
        XCTAssertEqual(record.anchor?.tier, "T3")
        XCTAssertNotNil(record.createdAt)
    }

    func testPendingAnchorNullAndMissingDecodeNil() throws {
        let withNull = """
        {"id":"a1","subsystem":"memory","action":"add",\
        "summary":"s","origin":"oneday_app","anchor":null}
        """
        let missing = """
        {"id":"a2","subsystem":"memory","action":"add",\
        "summary":"s","origin":"oneday_app"}
        """
        for json in [withNull, missing] {
            let record = try JSONDecoder().decode(
                WriteGateRecord.self, from: Data(json.utf8)
            )
            XCTAssertNil(record.anchor)
        }
    }

    func testDecisionAnchorAndCreatedAtDecode() throws {
        let json = """
        {"id":"3258e01d","subsystem":"memory","action":"append",\
        "summary":"s","origin":"background_review",\
        "decision":"approved",\
        "created_at":"2026-11-10T17:08:17Z",\
        "decided_at":"2026-11-10T17:09:00Z",\
        "anchor":{"sessionId":"oneday-main-bfb4e3ed","tier":"T3"}}
        """
        let item = try JSONDecoder().decode(
            WriteGateDecisionRecord.self, from: Data(json.utf8)
        )
        XCTAssertEqual(item.anchor?.sessionId, "oneday-main-bfb4e3ed")
        XCTAssertNotNil(item.createdAt)
        XCTAssertNotNil(item.decidedAt)
    }

    // MARK: - 物化规划

    func testPlanPendingAnchoredMaterializes() {
        let record = pendingRecord(
            id: "r1", createdAt: now.addingTimeInterval(-60),
            anchor: WriteGateAnchor(sessionId: "sess-1", tier: "T1")
        )
        let planned = ApprovalAnchor.plan(
            pending: [record], decisions: [],
            existingKeys: [], now: now
        )
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(
            planned[0].key,
            ApprovalAnchor.key(subsystem: .skills, id: "r1")
        )
        XCTAssertEqual(planned[0].sessionID, "sess-1")
        XCTAssertEqual(
            planned[0].createdAt, now.addingTimeInterval(-60)
        )
    }

    func testPlanSkipsUnanchoredAndFrozen() {
        let unanchored = pendingRecord(
            id: "r2", createdAt: now, anchor: nil
        )
        let frozen = pendingRecord(
            id: "r3", createdAt: now,
            anchor: WriteGateAnchor(sessionId: "sess-9", tier: "T3")
        )
        // 冻结口径：r3 已落锚（键在 existingKeys）——本轮
        // anchor 指向 sess-9 也不再规划、不迁移
        let planned = ApprovalAnchor.plan(
            pending: [unanchored, frozen], decisions: [],
            existingKeys: [
                ApprovalAnchor.key(subsystem: .skills, id: "r3")
            ],
            now: now
        )
        XCTAssertTrue(planned.isEmpty)
    }

    func testPlanDecisionBackfillWindow() {
        let inside = decisionRecord(
            id: "d1",
            decidedAt: now.addingTimeInterval(-29 * 24 * 3600),
            createdAt: now.addingTimeInterval(-29 * 24 * 3600 - 60),
            anchor: WriteGateAnchor(sessionId: "sess-1", tier: "T3")
        )
        let outside = decisionRecord(
            id: "d2",
            decidedAt: now.addingTimeInterval(-31 * 24 * 3600),
            createdAt: now.addingTimeInterval(-31 * 24 * 3600),
            anchor: WriteGateAnchor(sessionId: "sess-1", tier: "T3")
        )
        let planned = ApprovalAnchor.plan(
            pending: [], decisions: [inside, outside],
            existingKeys: [], now: now
        )
        XCTAssertEqual(planned.map(\.key), [
            ApprovalAnchor.key(subsystem: .skills, id: "d1")
        ])
        // 落位时刻取记录 created_at，不是裁决时刻
        XCTAssertEqual(
            planned[0].createdAt,
            now.addingTimeInterval(-29 * 24 * 3600 - 60)
        )
    }

    func testPlanDecisionWithoutAnyTimestampSkipped() {
        let timeless = decisionRecord(
            id: "d3", decidedAt: nil, createdAt: nil,
            anchor: WriteGateAnchor(sessionId: "sess-1", tier: "T3")
        )
        let planned = ApprovalAnchor.plan(
            pending: [], decisions: [timeless],
            existingKeys: [], now: now
        )
        XCTAssertTrue(planned.isEmpty)
    }

    func testPlanPendingWinsOverDecisionDuplicate() {
        let stamp = now.addingTimeInterval(-120)
        let pending = pendingRecord(
            id: "dup", createdAt: stamp,
            anchor: WriteGateAnchor(sessionId: "sess-1", tier: "T2")
        )
        let decided = decisionRecord(
            id: "dup", decidedAt: now, createdAt: stamp,
            anchor: WriteGateAnchor(sessionId: "sess-1", tier: "T2")
        )
        let planned = ApprovalAnchor.plan(
            pending: [pending], decisions: [decided],
            existingKeys: [], now: now
        )
        XCTAssertEqual(planned.count, 1)
    }

    // MARK: - 行呈现态

    func testRowStatePrecedenceAndStaleGate() {
        let record = pendingRecord(
            id: "r1", createdAt: now,
            anchor: WriteGateAnchor(sessionId: "s", tier: "T1")
        )
        let decided = decisionRecord(
            id: "r1", decidedAt: now, anchor: nil
        )
        // 待批优先于已决（裁决刚落账的竞态以待批现态为准）
        XCTAssertEqual(
            ApprovalAnchor.rowState(
                recordID: "r1", dataReady: true,
                pending: [record], decisions: [decided], missCount: 0
            ),
            .pending(record)
        )
        XCTAssertEqual(
            ApprovalAnchor.rowState(
                recordID: "r1", dataReady: true,
                pending: [], decisions: [decided], missCount: 0
            ),
            .decided(decided)
        )
        // 两处皆无：缺席 1 轮不判死（loading 等对账），
        // 满 2 轮才已失效；数据未就绪恒 loading
        XCTAssertEqual(
            ApprovalAnchor.rowState(
                recordID: "r1", dataReady: true,
                pending: [], decisions: [], missCount: 1
            ),
            .loading
        )
        XCTAssertEqual(
            ApprovalAnchor.rowState(
                recordID: "r1", dataReady: true,
                pending: [], decisions: [], missCount: 2
            ),
            .stale
        )
        XCTAssertEqual(
            ApprovalAnchor.rowState(
                recordID: "r1", dataReady: false,
                pending: [], decisions: [], missCount: 9
            ),
            .loading
        )
    }

    func testMissCounting() {
        XCTAssertEqual(
            ApprovalAnchor.missCountAfterRefresh(
                previous: 0, present: false
            ), 1
        )
        XCTAssertEqual(
            ApprovalAnchor.missCountAfterRefresh(
                previous: 1, present: false
            ), 2
        )
        XCTAssertEqual(
            ApprovalAnchor.missCountAfterRefresh(
                previous: 2, present: true
            ), 0
        )
        XCTAssertTrue(ApprovalAnchor.isStale(missCount: 2))
        XCTAssertFalse(ApprovalAnchor.isStale(missCount: 1))
    }

    func testKeyAndRecordIDRoundTrip() {
        let key = ApprovalAnchor.key(subsystem: .memory, id: "abc123")
        XCTAssertEqual(key, "wg:memory:abc123")
        XCTAssertEqual(ApprovalAnchor.recordID(fromKey: key), "abc123")
        XCTAssertNil(ApprovalAnchor.recordID(fromKey: "bogus"))
        XCTAssertNil(ApprovalAnchor.recordID(fromKey: "wg:memory:"))
        XCTAssertEqual(
            ApprovalAnchor.anchoredRecordIDs(keys: [key, "junk"]),
            ["abc123"]
        )
    }

    // MARK: - 点达解析与通知路由

    func testNavigationTargetPrecedence() {
        let threadA = UUID()
        let threadB = UUID()
        let key = ApprovalAnchor.key(subsystem: .skills, id: "r1")
        let materialized = ApprovalAnchorNavigation.MaterializedIndex(
            threadIDByKey: [key: threadA],
            entryIDByKey: [key: UUID()]
        )
        // 已物化最硬：即使 anchor 会话另有线程也认物化位
        XCTAssertEqual(
            ApprovalAnchorNavigation.target(
                subsystem: .skills, recordID: "r1",
                anchorSessionID: "sess-b",
                threadIDByServerSessionID: ["sess-b": threadB],
                materialized: materialized
            ),
            .entry(threadID: threadA, approvalKey: key)
        )
        // 未物化但锚会话有线程：只达线程不定位
        XCTAssertEqual(
            ApprovalAnchorNavigation.target(
                subsystem: .skills, recordID: "rX",
                anchorSessionID: "sess-b",
                threadIDByServerSessionID: ["sess-b": threadB],
                materialized: materialized
            ),
            .threadOnly(threadID: threadB)
        )
        // 无锚/无线程：none（调用方降级，不许假定位）
        XCTAssertEqual(
            ApprovalAnchorNavigation.target(
                subsystem: .skills, recordID: "rX",
                anchorSessionID: nil,
                threadIDByServerSessionID: [:],
                materialized: materialized
            ),
            .none
        )
    }

    func testNotificationRouting() {
        let thread = UUID()
        let key = ApprovalAnchor.key(subsystem: .memory, id: "wg_1")
        let receipt = OverviewNotification(
            id: "n_1", kind: "write_gate_decision", title: "题",
            body: "文", createdAt: "2026-11-11T00:00:00Z",
            read: false, refId: "wg_1"
        )
        XCTAssertEqual(
            ApprovalNotificationRouting.destination(
                notification: receipt,
                anchorTarget: .entry(threadID: thread, approvalKey: key)
            ),
            .approvalAnchor(threadID: thread, approvalKey: key)
        )
        XCTAssertEqual(
            ApprovalNotificationRouting.destination(
                notification: receipt,
                anchorTarget: .threadOnly(threadID: thread)
            ),
            .approvalThread(threadID: thread)
        )
        // 未命中锚：回 §123 现行落点（枢纽段聚焦）
        XCTAssertEqual(
            ApprovalNotificationRouting.destination(
                notification: receipt, anchorTarget: .none
            ),
            .approvalDecision(id: "wg_1")
        )
        // 非审批通知不走锚路由
        let monitor = OverviewNotification(
            id: "n_2", kind: "monitor_change", title: "题",
            body: "文", createdAt: "2026-11-11T00:00:00Z",
            read: false, refId: "mon_1", changeId: "chg_1"
        )
        XCTAssertEqual(
            ApprovalNotificationRouting.destination(
                notification: monitor,
                anchorTarget: .entry(threadID: thread, approvalKey: key)
            ),
            .monitorChange(monitorID: "mon_1", changeID: "chg_1")
        )
    }
}
