import OneDayCore
import XCTest

/// 总览桥冻结契约（0.6.0 一期）：DTO 按契约桩解码，
/// 状态行四支与角标聚合逐项钉死。桥未上线前本组就是
/// 契约的唯一机器可读口径，字段名不许漂移。
final class OverviewBridgeTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testOverviewSnapshotDecodesContractFixture() throws {
        let data = Data("""
        {
          "hermesUp": true,
          "activeSessions": 2,
          "pendingApprovals": 3,
          "unreadNotifications": 4,
          "generatedAt": "2026-11-09T06:50:00Z"
        }
        """.utf8)
        let snapshot = try decoder.decode(OverviewSnapshot.self, from: data)
        XCTAssertTrue(snapshot.hermesUp)
        XCTAssertEqual(snapshot.activeSessions, 2)
        XCTAssertEqual(snapshot.pendingApprovals, 3)
        XCTAssertEqual(snapshot.unreadNotifications, 4)
        XCTAssertEqual(snapshot.generatedAt, "2026-11-09T06:50:00Z")
    }

    func testNotificationsDecodeContractFixture() throws {
        let data = Data("""
        {
          "items": [
            {
              "id": "n-1",
              "kind": "write_gate_decided",
              "title": "一条写入已批准",
              "body": "记忆写入已经落盘。",
              "createdAt": "2026-11-09T06:49:00Z",
              "read": false
            },
            {
              "id": "n-2",
              "kind": "write_gate_decided",
              "title": "一条写入已驳回",
              "body": "技能写入没有生效。",
              "createdAt": "2026-11-09T06:48:00Z",
              "read": true
            }
          ]
        }
        """.utf8)
        let response = try decoder.decode(
            OverviewNotificationsResponse.self, from: data
        )
        XCTAssertEqual(response.items.count, 2)
        XCTAssertEqual(response.items[0].id, "n-1")
        XCTAssertEqual(response.items[0].title, "一条写入已批准")
        XCTAssertFalse(response.items[0].read)
        XCTAssertTrue(response.items[1].read)
    }

    func testReadResponseDecodesContractFixture() throws {
        let response = try decoder.decode(
            OverviewReadResponse.self, from: Data(#"{"ok": true}"#.utf8)
        )
        XCTAssertTrue(response.ok)
    }

    private func snapshot(
        hermesUp: Bool = true, active: Int = 0,
        pending: Int = 0, unread: Int = 0
    ) -> OverviewSnapshot {
        OverviewSnapshot(
            hermesUp: hermesUp, activeSessions: active,
            pendingApprovals: pending, unreadNotifications: unread,
            generatedAt: "2026-11-09T06:50:00Z"
        )
    }

    func testStatusLineUnreachableWhenNoSnapshot() {
        XCTAssertEqual(OverviewStatusLine.resolve(snapshot: nil), "暂时联系不上")
    }

    func testStatusLineUnreachableWhenHermesDown() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(snapshot: snapshot(hermesUp: false, pending: 2)),
            "暂时联系不上"
        )
    }

    func testStatusLinePendingApprovalsWinsOverActiveSessions() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(snapshot: snapshot(active: 1, pending: 2)),
            "有 2 条待你审批"
        )
    }

    func testStatusLineActiveSessions() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(snapshot: snapshot(active: 1)),
            "正在处理会话"
        )
    }

    func testStatusLineIdle() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(snapshot: snapshot()),
            "随时待命"
        )
    }

    func testBadgeAggregatesUnreadAndPending() {
        XCTAssertEqual(
            OverviewBadge.count(snapshot: snapshot(pending: 3, unread: 4)), 7
        )
        XCTAssertEqual(OverviewBadge.count(snapshot: snapshot()), 0)
    }

    func testBadgeIsZeroWhenUnreachable() {
        XCTAssertEqual(OverviewBadge.count(snapshot: nil), 0)
    }

    func testBadgeClampsNegativeInputs() {
        XCTAssertEqual(
            OverviewBadge.count(snapshot: snapshot(pending: -2, unread: -1)), 0
        )
    }
}
